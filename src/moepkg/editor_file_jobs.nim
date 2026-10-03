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

## The external commands the editor has started: listing them for `:jobs`,
## stopping them for `:jobs!`, and what a quit waits for.

import std/[monotimes, options]

from std/times import inSeconds

import types/editor_types
import background_process, job_lanes, quick_run_utils, unicode_utils

const NoCommandEpoch* = high(uint64)
  ## The epoch of work `:jobs!` cannot stop. The counter only counts up from
  ## zero, so it never reaches this.

proc commandEpoch*(e: Editor): uint64 =
  ## The epoch a command captures when spawned and passes to every later check.
  e.state.commandEpoch

proc commandsStoppedSince*(e: Editor, epoch: uint64): bool =
  ## Whether the user has stopped the external commands since `epoch` was taken,
  ## so that stopping also reaches work already running.
  epoch != NoCommandEpoch and e.state.commandEpoch != epoch

proc elapsedText(startedAt: MonoTime): string =
  ## How long a command has been running, at human resolution.
  let secs = (getMonoTime() - startedAt).inSeconds
  if secs < 60:
    $secs & "s"
  else:
    $(secs div 60) & "m" & $(secs mod 60) & "s"

proc runningCommands*(e: Editor): seq[string] =
  ## One line per external command running, stopping or queued, for `:jobs`.
  proc entry(label, state, path: string): string =
    result = label & " (" & state & ")"
    if path.len > 0:
      result &= ": " & path

  for running in e.runningBackgroundProcesses:
    let name = if running.label.len > 0: running.label else: "Command"
    result.add entry(name, elapsedText(running.startedAt), running.path)

  for job in e.jobLanes.jobs:
    case job.state
    of jsRunning:
      result.add entry(job.label, elapsedText(job.startedAt), job.path)
    of jsStopping:
      result.add entry(job.label, "stopping", job.path)
    of jsWaiting:
      discard

  for qr in e.runningQuickRunProcesses:
    result.add "QuickRun (" & elapsedText(qr.startedAt) & "): " & qr.filePath

  for job in e.jobLanes.jobs:
    if job.state == jsWaiting:
      result.add entry(job.label, "queued", job.path)

proc stopEverything(e: Editor): seq[JobInfo] =
  ## Kill every external command the editor started and drop the queued ones,
  ## returning the lane jobs this reached.
  # Bumped first so everything unwinding below sees it and stops at its next
  # await rather than carrying on.
  e.state.commandEpoch.inc
  result = e.jobLanes.stopAll()

  # Whether or not the command itself has exited: what it left running in its
  # group holds the job open until the run releases it.
  for running in e.runningBackgroundProcesses:
    running.process.kill()
  for qr in e.runningQuickRunProcesses:
    qr.process.kill()

proc stopRunningCommands*(e: Editor): int =
  ## Kill every external command the editor started, drop the queued ones, and
  ## return how many. Jobs already stopping, and work that stops at its next
  ## epoch check, are not counted.
  let fromLanes = e.stopEverything().len
  e.runningBackgroundProcesses.len + e.runningQuickRunProcesses.len + fromLanes

proc exitWaitTimedOut*(e: Editor): bool =
  ## Whether the quit has waited for owed work past `exitWaitTimeout`. A
  ## non-positive bound means time alone never ends the wait.
  if e.config.hooks.exitWaitTimeout <= 0 or e.state.exitWaitStartedAt.isNone:
    return false
  (getMonoTime() - e.state.exitWaitStartedAt.get).inSeconds >=
    e.config.hooks.exitWaitTimeout

type ExitWaitState* = enum
  ## Where a quit stands with the work it is owed. `exitWaitState` is the one
  ## place this is decided, from the quit, the owed jobs and the bound.
  ewsNotQuitting ## No quit was decided; everything runs as usual.
  ewsWaiting ## The quit is waiting for the hooks it owes.
  ewsReady ## Nothing owed is left, or the bound ran out: end the session.

type ExitWaitAction* = enum
  ## What a frontend does with an input event while `ExitWaitState` stands.
  ewaHandle ## The editor is not quitting: pass the event to it.
  ewaIgnore ## The quit is waiting: the event reaches nobody.
  ewaQuitNow ## End the session now.

proc exitWaitState*(e: Editor): ExitWaitState =
  if not e.state.quitDecided:
    return ewsNotQuitting
  if e.jobLanes.owedIdle or e.exitWaitTimedOut():
    return ewsReady
  ewsWaiting

proc exitWaitAction*(e: Editor, interrupt: bool): ExitWaitAction =
  ## What to do with an event, from the state alone. `interrupt` is the
  ## frontend's Ctrl-C, which gives up on the hooks a quit is waiting for.
  case e.exitWaitState
  of ewsNotQuitting:
    ewaHandle
  of ewsWaiting:
    (if interrupt: ewaQuitNow else: ewaIgnore)
  of ewsReady:
    ewaQuitNow

proc readyToExit*(e: Editor): bool =
  ## Whether the session may end now; `exitWaitState` is the state behind it.
  e.exitWaitState == ewsReady

const ExitWaitHint = "Ctrl-C quits now"

proc exitWaitStatus(e: Editor): string =
  ## What the status line says while a quit waits for its hooks: the bound,
  ## when one is set, so the wait's end is not a surprise.
  result = "Waiting for hooks to finish ("
  let bound = e.config.hooks.exitWaitTimeout
  if bound > 0:
    result &= "up to " & $bound & "s, "
  result &= ExitWaitHint & ")"

proc showExitWait*(e: Editor) =
  ## Say what a quit is waiting for and how to skip it. Called every frame to
  ## restore it once overwritten; set only when changed, since each set is logged.
  if e.exitWaitState == ewsWaiting:
    let msg = e.exitWaitStatus
    if e.state.statusMessage != msg:
      e.state.statusMessage = msg

proc beginQuit*(e: Editor) =
  ## Note the quit and start its wait, once: the wait is measured from the
  ## quit, and a second notice (a key mapping's timeout, say) must not push
  ## the bound back.
  if e.state.quitDecided:
    return
  e.state.quitDecided = true
  e.jobLanes.windDown()
  e.state.exitWaitStartedAt = some(getMonoTime())
  e.showExitWait()

proc abandonExitWait*(e: Editor) =
  ## Stop everything, owed work included, for a session ending without waiting
  ## (Ctrl-C, a signal, a crash, or a wait past `exitWaitTimeout`). Owed jobs
  ## are recorded for stderr, as a `$EDITOR` caller may rely on them; each
  ## once, however many paths call this.
  let jobs = e.stopEverything()
  var notedTimeout = false
  for job in jobs:
    if job.owed:
      if not notedTimeout:
        notedTimeout = true
        if e.exitWaitTimedOut():
          e.state.exitReports.add(
            "Hook wait timed out after " & $e.config.hooks.exitWaitTimeout & "s"
          )
      var report =
        (if job.state == jsWaiting: "Not run: " else: "Stopped before finishing: ") &
        job.label
      if job.path.len > 0:
        report &= " on " & job.path
      e.state.exitReports.add report.forDisplay
