#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[osproc, strformat]
import pkg/results

type
  BackgroundProcess* = object
    process: Process

  StartProcessResult* = Result[BackgroundProcess, string]

proc isRunning*(bp: BackgroundProcess): bool {.inline.} = bp.process.running

proc isFinish*(bp: BackgroundProcess): bool {.inline.} = not bp.process.running

proc cancel*(bp: var BackgroundProcess) = bp.process.terminate

proc kill*(bp: var BackgroundProcess) = bp.process.kill

proc close(bp: var BackgroundProcess) = bp.process.close

proc startBackgroundProcess*(
  command: string,
  args: seq[string],
  workingDir: string = ""): StartProcessResult =
    ## Start the passed command in a new process and return BackgroundProcess.

    const
      Env = nil
      Options = {poUsePath, poDaemon, poStdErrToStdOut}

    var process: Process
    try:
      process = startProcess(command, workingDir, args, Env, Options)
    except OSError as e:
      return StartProcessResult.err fmt"Failed to create a background process: {e.msg}"

    return StartProcessResult.ok BackgroundProcess(process: process)

proc result*(bp: var BackgroundProcess): Result[seq[string], string] =
  ## Return results (Stdout) the BackgroundProcess and close the process.
  if bp.isRunning:
    return Result[seq[string], string].err "BackgroundProcess is still running"

  let (output, exitCode) = bp.process.readLines
  bp.close

  if exitCode == 0:
    return Result[seq[string], string].ok output
  else:
    return Result[seq[string], string].err fmt"BackgroundProcess is failed: {output}"

proc waitFor*(bp: var BackgroundProcess, timeout: int = -1): Result[seq[string], string] =
  let exitCode = bp.process.waitForExit
  if 0 == exitCode:
    let (output, _) = bp.process.readLines
    bp.close
    return Result[seq[string], string].ok output
  else:
    bp.close
    return Result[seq[string], string].err fmt"Failed to the background process: {$exitCode}"
