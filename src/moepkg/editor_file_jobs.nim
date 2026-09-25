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

## The external commands the editor has started: what is running, and ending
## them.
##
## A command captures `commandEpoch` when it is queued and re-checks it after
## every await, so `:jobs!` reaches work already in flight rather than only
## what is still waiting to start.

import std/monotimes

from std/times import inSeconds

import types/editor_types
import background_process, quick_run_utils

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
  ## One line per running external command, for `:jobs`.
  for running in e.runningBackgroundProcesses:
    let name = if running.label.len > 0: running.label else: "Command"
    var line = name & " (" & elapsedText(running.startedAt) & ")"
    if running.path.len > 0:
      line &= ": " & running.path
    result.add line

  for qr in e.runningQuickRunProcesses:
    result.add "QuickRun (" & elapsedText(qr.startedAt) & "): " & qr.filePath

proc stopRunningCommands*(e: Editor): int =
  ## Kill every external command the editor started and report how many were
  ## stopped outright: each one `runningCommands` lists.
  ##
  ## Work that stops at its next epoch check instead is not counted, since it
  ## is still running when this returns.
  # Bumped first so everything unwinding below sees it and stops at its next
  # await rather than carrying on.
  e.state.commandEpoch.inc

  # Whether or not the command itself has exited: what it left running in its
  # group holds the job open until the run releases it.
  for running in e.runningBackgroundProcesses:
    running.process.kill()
  for qr in e.runningQuickRunProcesses:
    qr.process.kill()
  e.runningBackgroundProcesses.len + e.runningQuickRunProcesses.len
