#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## Background work that must not overlap with itself.
##
## Jobs in one lane never overlap; the lane's admission decides what a new job
## does while one runs: `adQueue` waits for it, `adRestart` stops it.
##
## `submit` only records the job and starts it on a later event-loop turn, so it
## is safe to call from anywhere. A waiting job is listed and stoppable like a
## running one. A stop reports each job once, however long it takes to end.
##
## A quit winds the lanes down: owed jobs still run, everything else stops.

import std/[monotimes, sequtils, tables]

import pkg/chronos

import job_stop
export job_stop

type
  LaneRun* = proc(stop: JobStop): Future[void] {.async: (raises: []), gcsafe.}
    ## The job's work. Must check `stop.requested` after each await.

  LaneJob* = object
    label*: string ## What the job is, for `:jobs`.
    path*: string ## The file it is for, for `:jobs`; may be empty.
    collapse*: string
      ## For `adQueue`: a waiting job with the same value is replaced in place
      ## rather than queued again. Empty never matches.
    owed*: bool ## Still run when the lanes wind down; a quit waits for it.
    run*: LaneRun

  Admission* = enum
    adQueue ## Wait for the running job, e.g. builds sharing an output.
    adRestart
      ## Stop the running job and start without waiting for it to end, e.g.
      ## read-only checks where only the newest result matters.

  Submission* = enum
    smNext ## Nothing is ahead of the job: it starts on the next turn.
    smQueued ## The job waits for those ahead of it.
    smMerged ## The job took the place of a waiting one.
    smRefused ## The lanes are closed: the job will not run.

  JobState* = enum
    jsWaiting
    jsRunning
    jsStopping ## Told to stop and not ended yet.

  JobInfo* = object ## A job as `:jobs` shows it.
    label*: string
    path*: string
    state*: JobState
    startedAt*: MonoTime ## Unset while waiting.
    owed*: bool

  Job = ref object
    spec: LaneJob
    state: JobState
    stop: JobStop
    startedAt: MonoTime

  Lane = ref object
    admission: Admission
    live: seq[Job] ## Started and not ended: running or stopping.
    waiting: seq[Job]
    startPending: bool ## A turn is booked to start what waits.

  Lanes = ref object
    table: OrderedTable[string, Lane] ## Only lanes with jobs; an idle one is dropped.
    closed: bool

  JobLanes* = object
    lanes: Lanes ## Made on first use, so an editor needs no set-up.

proc info(job: Job): JobInfo =
  JobInfo(
    label: job.spec.label,
    path: job.spec.path,
    state: job.state,
    startedAt: job.startedAt,
    owed: job.spec.owed,
  )

proc canStart(lane: Lane): bool =
  case lane.admission
  of adQueue:
    lane.live.len == 0
  of adRestart:
    lane.live.allIt(it.state == jsStopping)

proc tellToStop(job: Job) =
  job.state = jsStopping
  job.stop.request()

proc advance(lanes: Lanes, key: string, lane: Lane) {.gcsafe, raises: [].}

proc drive(lanes: Lanes, key: string, lane: Lane, job: Job) {.async: (raises: []).} =
  await job.spec.run(job.stop)
  lane.live.keepItIf(it != job)
  lanes.advance(key, lane)

proc advance(lanes: Lanes, key: string, lane: Lane) =
  ## Start the next job if the lane allows it, or drop the lane once it is idle.
  if lanes.table.getOrDefault(key) != lane:
    # Dropped meanwhile; nothing waits in it.
    return
  if lane.waiting.len == 0:
    if lane.live.len == 0:
      lanes.table.del(key)
    return
  if not lane.canStart:
    return
  let job = lane.waiting[0]
  lane.waiting.delete(0)
  job.state = jsRunning
  job.startedAt = getMonoTime()
  lane.live.add job
  asyncSpawn lanes.drive(key, lane, job)

proc bookStart(lanes: Lanes, key: string, lane: Lane) =
  if lane.startPending:
    return
  lane.startPending = true
  callSoon(
    proc(arg: pointer) {.gcsafe, raises: [].} =
      lane.startPending = false
      lanes.advance(key, lane)
  )

proc get(lanes: var JobLanes): Lanes =
  if lanes.lanes.isNil:
    lanes.lanes = Lanes()
  lanes.lanes

proc submit*(
    lanes: var JobLanes, key: string, job: LaneJob, admission = adQueue
): Submission =
  ## Put `job` in lane `key`. One lane takes one admission.
  let all = lanes.get
  if all.closed:
    return smRefused

  let lane = all.table.mgetOrPut(key, Lane(admission: admission))
  doAssert lane.admission == admission, "lane " & key & " takes one admission"
  let entry = Job(spec: job, state: jsWaiting, stop: JobStop())

  case admission
  of adRestart:
    for running in lane.live:
      if running.state == jsRunning:
        running.tellToStop()
    if lane.waiting.len > 0:
      lane.waiting[0] = entry
      result = smMerged
    else:
      lane.waiting.add entry
      result = smNext
  of adQueue:
    result = smQueued
    if job.collapse.len > 0:
      for queued in lane.waiting.mitems:
        if queued.spec.collapse == job.collapse:
          # In place, so jobs queued after it keep their order.
          queued = entry
          result = smMerged
          break
    if result != smMerged:
      lane.waiting.add entry
      if lane.live.len == 0 and lane.waiting.len == 1:
        result = smNext

  all.bookStart(key, lane)

iterator jobs*(lanes: JobLanes): JobInfo =
  ## Every job not ended, by lane in opening order: started ones first, then
  ## waiting ones in run order.
  if not lanes.lanes.isNil:
    for lane in lanes.lanes.table.values:
      for job in lane.live:
        yield job.info
      for job in lane.waiting:
        yield job.info

proc stopAll*(lanes: var JobLanes): seq[JobInfo] =
  ## Drop waiting jobs and tell running ones to stop, returning them as they
  ## were. Jobs already stopping are left out.
  let all = lanes.get
  var idle: seq[string]
  for key, lane in all.table:
    for job in lane.waiting:
      result.add job.info
    lane.waiting.setLen(0)
    for job in lane.live:
      if job.state == jsRunning:
        result.add job.info
        job.tellToStop()
    if lane.live.len == 0:
      idle.add key
  for key in idle:
    all.table.del(key)

proc windDown*(lanes: var JobLanes) =
  ## Refuse new work and stop what is not owed, for a quit that waits for the
  ## rest. Owed jobs keep their place and run as usual.
  let all = lanes.get
  all.closed = true
  var idle: seq[string]
  for key, lane in all.table:
    lane.waiting.keepItIf(it.spec.owed)
    for job in lane.live:
      if job.state == jsRunning and not job.spec.owed:
        job.tellToStop()
    if lane.waiting.len == 0 and lane.live.len == 0:
      idle.add key
  for key in idle:
    all.table.del(key)

proc owedIdle*(lanes: JobLanes): bool =
  ## Whether no owed job waits or runs. One told to stop is not waited for:
  ## its kill has been sent.
  for job in lanes.jobs:
    if job.owed and job.state != jsStopping:
      return false
  true

proc close*(lanes: var JobLanes) =
  ## Refuse new work and stop everything, for editor shutdown.
  lanes.get.closed = true
  discard lanes.stopAll()
