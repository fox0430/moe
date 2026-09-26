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

import std/[unittest, importutils, sequtils, strutils, tables]

import pkg/chronos

import ../src/moepkg/job_lanes {.all.}

type Probe = ref object ## Records what the jobs did and holds each one until released.
  log: seq[string]
  gates: Table[string, Future[void]]

proc job(p: Probe, name: string, collapse = "", stubborn = false): LaneJob =
  ## A job that runs until released. Stopping ends its work, as killing its
  ## process would, unless it is `stubborn`: then it only notes the stop and
  ## keeps running until released, as a command slow to die does.
  let gate = newFuture[void]("test_job_lanes.job")
  p.gates[name] = gate
  proc run(stop: JobStop) {.async: (raises: []).} =
    p.log.add name & " start"
    stop.onStop(
      proc() =
        p.log.add name & " stopped"
        if not stubborn and not gate.finished:
          gate.complete()
    )
    try:
      await gate
    except CatchableError:
      discard
    p.log.add name & (if stop.requested: " cut short" else: " end")

  LaneJob(label: name, collapse: collapse, run: run)

proc instant(p: Probe, name: string): LaneJob =
  ## A job with nothing to wait for.
  proc run(stop: JobStop) {.async: (raises: []).} =
    p.log.add name

  LaneJob(label: name, run: run)

proc late(p: Probe, name: string): LaneJob =
  ## A job that awaits something before it says how to stop it.
  proc run(stop: JobStop) {.async: (raises: []).} =
    try:
      await sleepAsync(5.milliseconds)
    except CancelledError:
      discard
    stop.onStop(
      proc() =
        p.log.add name & " stopped"
    )

  LaneJob(label: name, run: run)

proc turn() =
  ## Give the loop the turns a lane takes to start a job or hand itself on.
  waitFor sleepAsync(1.milliseconds)

proc release(p: Probe, name: string) =
  if not p.gates[name].finished:
    p.gates[name].complete()
  turn()

proc started(p: Probe): seq[string] =
  p.log.filterIt(it.endsWith " start")

proc labels(lanes: JobLanes, state: JobState): seq[string] =
  for job in lanes.jobs:
    if job.state == state:
      result.add job.label

proc idle(lanes: JobLanes): bool =
  toSeq(lanes.jobs).len == 0

proc laneCount(lanes: JobLanes): int =
  privateAccess(JobLanes)
  privateAccess(Lanes)
  if lanes.lanes.isNil: 0 else: lanes.lanes.table.len

suite "Job stop":
  test "A stop runs the action and ends what races it":
    let stop = JobStop()
    var acted = 0
    stop.onStop(
      proc() =
        acted.inc
    )
    let ended = stop.stopped
    check not ended.finished

    stop.request()
    stop.request()
    check stop.requested
    check acted == 1
    check ended.finished

  test "What comes after the stop is carried out at once":
    let stop = JobStop()
    stop.request()
    var acted = false
    stop.onStop(
      proc() =
        acted = true
    )
    check acted
    check stop.stopped.finished

suite "Job lanes - order":
  test "Submitting runs none of the job; it starts on a later turn":
    var lanes: JobLanes
    let p = Probe()

    check lanes.submit("a", p.job("first")) == smNext
    check p.log.len == 0
    check lanes.labels(jsWaiting) == @["first"]

    turn()
    check p.log == @["first start"]
    check lanes.labels(jsRunning) == @["first"]

    p.release("first")
    check p.log == @["first start", "first end"]
    check lanes.idle

  test "One lane runs its jobs one at a time, in arrival order":
    var lanes: JobLanes
    let p = Probe()

    check lanes.submit("a", p.job("first")) == smNext
    check lanes.submit("a", p.job("second")) == smQueued
    check lanes.submit("a", p.job("third")) == smQueued
    turn()
    check p.started == @["first start"]

    p.release("first")
    check p.log == @["first start", "first end", "second start"]
    p.release("second")
    check p.log[^1] == "third start"
    p.release("third")
    check p.log ==
      @[
        "first start", "first end", "second start", "second end", "third start",
        "third end",
      ]
    check lanes.idle

  test "Separate lanes run side by side":
    var lanes: JobLanes
    let p = Probe()

    check lanes.submit("a", p.job("a1")) == smNext
    check lanes.submit("b", p.job("b1")) == smNext
    turn()
    check p.started == @["a1 start", "b1 start"]

    p.release("b1")
    check not lanes.idle
    p.release("a1")
    check lanes.idle

  test "A job that finishes at once hands the lane on":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.instant("one"))
    discard lanes.submit("a", p.instant("two"))
    turn()
    check p.log == @["one", "two"]
    check lanes.idle

  test "A lane with nothing left in it is dropped":
    var lanes: JobLanes
    let p = Probe()

    for name in ["a", "b", "c"]:
      discard lanes.submit(name, p.job(name))
    turn()
    check lanes.laneCount == 3

    for name in ["a", "b", "c"]:
      p.release(name)
    check lanes.laneCount == 0

suite "Job lanes - collapsing":
  test "A repeat of a waiting job takes its place":
    var lanes: JobLanes
    let p = Probe()

    check lanes.submit("a", p.job("running", collapse = "build")) == smNext
    turn()
    check lanes.submit("a", p.job("older", collapse = "build")) == smQueued
    check lanes.submit("a", p.job("newer", collapse = "build")) == smMerged
    check lanes.labels(jsWaiting) == @["newer"]

    p.release("running")
    check p.started == @["running start", "newer start"]
    p.release("newer")
    check "older start" notin p.log

  test "Repeats that come before the lane starts run once":
    var lanes: JobLanes
    let p = Probe()

    check lanes.submit("a", p.job("first", collapse = "build")) == smNext
    check lanes.submit("a", p.job("second", collapse = "build")) == smMerged
    turn()
    check p.started == @["second start"]

  test "The running job is not collapsed into, nor stopped":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("running", collapse = "build"))
    turn()
    check lanes.submit("a", p.job("again", collapse = "build")) == smQueued
    check lanes.labels(jsWaiting) == @["again"]
    check "running stopped" notin p.log

  test "A collapsed job keeps its place in the queue":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("running"))
    discard lanes.submit("a", p.job("build 1", collapse = "build"))
    discard lanes.submit("a", p.job("check", collapse = "check"))
    check lanes.submit("a", p.job("build 2", collapse = "build")) == smMerged
    turn()
    check lanes.labels(jsWaiting) == @["build 2", "check"]

  test "Jobs without a collapse key all run":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("running"))
    check lanes.submit("a", p.job("one")) == smQueued
    check lanes.submit("a", p.job("two")) == smQueued
    turn()
    check lanes.labels(jsWaiting) == @["one", "two"]

  test "The same collapse key in another lane is another job":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("a running", collapse = "build"))
    discard lanes.submit("b", p.job("b running", collapse = "build"))
    turn()
    discard lanes.submit("a", p.job("a next", collapse = "build"))
    check lanes.submit("b", p.job("b next", collapse = "build")) == smQueued
    check lanes.labels(jsWaiting) == @["a next", "b next"]

suite "Job lanes - restarting":
  test "A newer job stops the running one and starts without waiting for it":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("old", stubborn = true), adRestart)
    turn()
    check lanes.submit("a", p.job("new"), adRestart) == smNext
    check p.log == @["old start", "old stopped"]

    turn()
    check p.started == @["old start", "new start"]
    check lanes.labels(jsStopping) == @["old"]
    check lanes.labels(jsRunning) == @["new"]

    p.release("old")
    check "old cut short" in p.log
    check lanes.labels(jsRunning) == @["new"]

  test "A burst of newer jobs runs only the newest":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("old"), adRestart)
    turn()
    discard lanes.submit("a", p.job("new 1"), adRestart)
    check lanes.submit("a", p.job("new 2"), adRestart) == smMerged
    turn()
    check p.started == @["old start", "new 2 start"]

  test "Restarting leaves other lanes alone":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("a check"), adRestart)
    discard lanes.submit("b", p.job("b check"), adRestart)
    discard lanes.submit("build", p.job("build"))
    turn()
    discard lanes.submit("a", p.job("a again"), adRestart)
    check p.log.filterIt(it.endsWith " stopped") == @["a check stopped"]

suite "Job lanes - stopping":
  test "Stopping ends the running jobs and forgets the waiting ones":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("running"))
    discard lanes.submit("a", p.job("next"))
    discard lanes.submit("b", p.job("other"))
    discard lanes.submit("b", p.job("other next"))
    turn()

    let stopped = lanes.stopAll()
    check stopped.mapIt(it.label).len == 4
    check stopped.filterIt(it.state == jsRunning).mapIt(it.label) ==
      @["running", "other"]
    check lanes.labels(jsWaiting).len == 0
    check "running stopped" in p.log
    check "other stopped" in p.log

    turn()
    check p.started == @["running start", "other start"]
    check "running cut short" in p.log
    check lanes.idle
    check lanes.laneCount == 0

  test "A job already told to stop is not reached again":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("slow to die", stubborn = true))
    turn()
    check lanes.stopAll().len == 1
    check lanes.labels(jsStopping) == @["slow to die"]
    check lanes.stopAll().len == 0

    p.release("slow to die")
    check lanes.idle

  test "A job that has not started is dropped and never starts":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("not yet"))
    check lanes.stopAll().mapIt(it.state) == @[jsWaiting]

    turn()
    check p.log.len == 0
    check lanes.idle
    check lanes.laneCount == 0

  test "A job told to stop before it says how still hears it":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.late("late"))
    turn()
    check lanes.stopAll().len == 1
    check p.log.len == 0

    waitFor sleepAsync(20.milliseconds)
    check p.log == @["late stopped"]

  test "Work submitted after a stop still runs":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("running"))
    turn()
    check lanes.stopAll().len == 1
    check lanes.submit("a", p.job("later")) == smQueued

    turn()
    check p.log[^1] == "later start"

  test "Closing stops what runs and refuses new work":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("running"))
    turn()
    discard lanes.submit("a", p.job("next"))
    lanes.close()
    check "running stopped" in p.log

    check lanes.submit("a", p.job("refused")) == smRefused
    check lanes.submit("b", p.job("refused elsewhere")) == smRefused
    check lanes.labels(jsWaiting).len == 0

    turn()
    check p.started == @["running start"]
    check lanes.idle

proc owedJob(job: LaneJob): LaneJob =
  result = job
  result.owed = true

suite "Job lanes - winding down":
  test "Winding down stops what is not owed and lets the owed run":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("owed running").owedJob)
    discard lanes.submit("a", p.job("dropped"))
    discard lanes.submit("a", p.job("owed next").owedJob)
    discard lanes.submit("b", p.job("stopped"))
    turn()
    lanes.windDown()

    check p.log.filterIt(it.endsWith " stopped") == @["stopped stopped"]
    check lanes.labels(jsWaiting) == @["owed next"]
    p.release("owed running")
    check p.started == @["owed running start", "stopped start", "owed next start"]

  test "Winding down refuses new work, owed or not":
    var lanes: JobLanes
    let p = Probe()

    lanes.windDown()
    check lanes.submit("a", p.job("owed").owedJob) == smRefused
    check lanes.submit("a", p.job("not owed")) == smRefused
    turn()
    check p.log.len == 0

  test "An owed job waits for a stopped one to end, as any queued job does":
    var lanes: JobLanes
    let p = Probe()

    discard lanes.submit("a", p.job("slow to die", stubborn = true))
    discard lanes.submit("a", p.job("owed").owedJob)
    turn()
    lanes.windDown()
    turn()
    check p.started == @["slow to die start"]

    p.release("slow to die")
    check p.started == @["slow to die start", "owed start"]

  test "Only owed jobs that wait or run keep the lanes from being idle for a quit":
    var lanes: JobLanes
    let p = Probe()
    check lanes.owedIdle

    discard lanes.submit("a", p.job("not owed"))
    check lanes.owedIdle
    discard lanes.submit("b", p.job("owed", stubborn = true).owedJob)
    check not lanes.owedIdle
    turn()
    check not lanes.owedIdle

    # Told to stop, it is not waited for: its kill has been sent.
    discard lanes.stopAll()
    check "owed" in lanes.labels(jsStopping)
    check lanes.owedIdle
