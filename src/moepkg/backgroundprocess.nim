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

import std/[osproc, strformat, streams]
import pkg/results

type
  BackgroundProcessCommand* = object
    cmd*: string
    args*: seq[string]
    workingDir*: string

  BackgroundProcess* = object
    process*: Process

  StartProcessResult* = Result[BackgroundProcess, string]

proc isRunning*(bp: BackgroundProcess): bool {.inline.} = bp.process.running

proc isFinish*(bp: BackgroundProcess): bool {.inline.} = not bp.process.running

proc cancel*(bp: BackgroundProcess) = bp.process.terminate

proc kill*(bp: BackgroundProcess) = bp.process.kill

proc close*(bp: BackgroundProcess) = bp.process.close

proc outputStream*(bp: BackgroundProcess): Stream = bp.process.outputStream

proc startBackgroundProcess*(
  command: BackgroundProcessCommand): StartProcessResult =
    ## Start the passed command in a new process and return BackgroundProcess.

    const
      Env = nil
      Options = {poUsePath, poDaemon, poStdErrToStdOut}

    var process: Process
    try:
      process = startProcess(
        command.cmd,
        command.workingDir,
        command.args,
        Env,
        Options)
    except OSError as e:
      return StartProcessResult.err fmt"Failed to create a background process: {e.msg}"

    return StartProcessResult.ok BackgroundProcess(process: process)

proc result*(bp: var BackgroundProcess): Result[seq[string], string] =
  ## Return results (Stdout) the BackgroundProcess and close the process.

  if bp.isRunning:
    return Result[seq[string], string].err "BackgroundProcess is still running"

  let (output, _) = bp.process.readLines
  bp.close

  return Result[seq[string], string].ok output

proc waitFor*(bp: var BackgroundProcess, timeout: int = -1): seq[string] =
  ## Return results (Stdout) the BackgroundProcess and close the process.
  ## Block until quit the process.

  discard bp.process.waitForExit
  let (output, _) = bp.process.readLines
  bp.close
  return output
