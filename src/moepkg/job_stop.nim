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

## A stop request handed to a job.
##
## A wait on an external command needs both answers to a stop: `onStop` runs at
## once (killing the process), since a stop at quit gets no later event-loop
## turn, and `stopped` is raced by the wait, so it ends without waiting for the
## command to close its pipes.

import pkg/chronos

type
  StopAction* = proc() {.closure, gcsafe, raises: [].}

  JobStop* = ref object
    asked: bool
    actions: seq[StopAction]
    signal: Future[void]

proc requested*(stop: JobStop): bool =
  ## Whether the job has been told to stop. Checked after each await, before
  ## acting on what was waited for.
  stop.asked

proc onStop*(stop: JobStop, action: StopAction) =
  ## Run `action` when the job is told to stop, after any set before it, or now
  ## if it has been.
  if stop.asked:
    action()
  else:
    stop.actions.add action

proc forget*(stop: JobStop, action: StopAction) =
  ## Drop `action`, set by `onStop`, for a holder done before the job is. A
  ## no-op once it has run.
  let i = stop.actions.find(action)
  if i >= 0:
    stop.actions.delete(i)

proc stopped*(stop: JobStop): Future[void] =
  ## Completes once the job is told to stop.
  if stop.signal.isNil:
    stop.signal = newFuture[void]("JobStop.stopped")
    if stop.asked:
      stop.signal.complete()
  stop.signal

proc request*(stop: JobStop) =
  ## Tell the job to stop. Only the first request acts.
  if stop.asked:
    return
  stop.asked = true
  let actions = move stop.actions
  for action in actions:
    action()
  if not stop.signal.isNil and not stop.signal.finished:
    stop.signal.complete()
