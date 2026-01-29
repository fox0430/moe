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

import std/strformat

import pkg/[results, chronos]
import pkg/chronos/asyncproc

type
  BackgroundProcessCommand* = object
    cmd*: string
    args*: seq[string]
    workingDir*: string

  BackgroundProcess* = ref object
    process*: AsyncProcessRef

  StartProcessResult* = Result[BackgroundProcess, string]

proc isRunning*(bp: BackgroundProcess): bool =
  if bp.process.isNil:
    return false
  let r = bp.process.running()
  if r.isOk:
    return r.get
  return false

proc isFinish*(bp: BackgroundProcess): bool =
  not bp.isRunning

proc cancel*(bp: BackgroundProcess) =
  if not bp.process.isNil:
    discard bp.process.terminate()

proc kill*(bp: BackgroundProcess) =
  if not bp.process.isNil:
    discard bp.process.kill()

proc closeAsync*(bp: BackgroundProcess): Future[void] {.async: (raises: []).} =
  if not bp.process.isNil:
    await bp.process.closeWait()
    bp.process = nil

proc startBackgroundProcess*(
    command: BackgroundProcessCommand
): Future[StartProcessResult] {.async: (raises: []).} =
  ## Start the passed command in a new process and return BackgroundProcess.
  ## Use AsyncProcess.Pipe for stdout to capture output, StdErrToStdOut to also capture stderr
  const Options = {AsyncProcessOption.UsePath, AsyncProcessOption.StdErrToStdOut}

  try:
    let process = await startProcess(
      command.cmd,
      command.workingDir,
      command.args,
      options = Options,
      stdoutHandle = AsyncProcess.Pipe,
    )
    return StartProcessResult.ok BackgroundProcess(process: process)
  except AsyncProcessError as e:
    return StartProcessResult.err fmt"Failed to create a background process: {e.msg}"
  except CancelledError:
    return StartProcessResult.err "Process start was cancelled"

proc readAllOutput*(
    bp: BackgroundProcess
): Future[seq[string]] {.async: (raises: []).} =
  ## Read all output from the process stdout
  var lines: seq[string] = @[]
  if bp.process.isNil:
    return lines

  let stdout = bp.process.stdoutStream()
  if stdout.isNil:
    return lines

  try:
    while not stdout.atEof():
      let line = await stdout.readLine(sep = "\n")
      lines.add(line)
  except AsyncStreamError:
    discard
  except CancelledError:
    discard

  return lines

proc waitForExitAsync*(bp: BackgroundProcess): Future[int] {.async: (raises: []).} =
  ## Wait for the process to exit and return exit code
  if bp.process.isNil:
    return -1

  try:
    return await bp.process.waitForExit()
  except AsyncProcessError:
    return -1
  except CancelledError:
    return -1

proc waitForAsync*(bp: BackgroundProcess): Future[seq[string]] {.async: (raises: []).} =
  ## Wait for process to complete and return all output lines
  ## Read output first (blocks until EOF), then wait for exit
  let output = await bp.readAllOutput()
  discard await bp.waitForExitAsync()
  await bp.closeAsync()
  return output
