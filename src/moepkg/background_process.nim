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

when defined(posix):
  import std/posix

import types/background_process_types
export background_process_types

const KillGrace = 2.seconds
  ## Upper bound on waiting for a killed child to close its stdout. Only used
  ## after the process was already killed, so it merely bounds the cleanup.

proc timeoutFromSeconds*(seconds: int): Duration =
  ## Convert a config timeout to the value `waitForAsync` expects.
  ## Non-positive means the user opted out of the bound.
  if seconds <= 0: InfiniteDuration else: seconds.seconds

proc killProcessGroup(pid: int) =
  ## SIGKILL the whole process group. Processes are spawned as group leaders
  ## (AsyncProcessOption.ProcessGroup), so the negative-pid kill also reaps
  ## grandchildren - `nim c` spawning a C compiler, or the `sh -c "build && run"`
  ## of QuickRun. Harmless if the group is already gone (ESRCH is ignored).
  if pid <= 0:
    return
  when defined(posix):
    discard posix.kill(posix.Pid(-pid), posix.SIGKILL)

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
  ## SIGKILL the process and everything it spawned. Killing only the direct
  ## child would leave the real workers (compiler, linker, the program a
  ## `sh -c` wrapper launched) running with the pipe still open.
  if bp.process.isNil:
    return
  killProcessGroup(bp.process.pid)
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
  # ProcessGroup makes the child its own process-group leader so `kill` can
  # take out the grandchildren it spawns too (see killProcessGroup).
  const Options = {
    AsyncProcessOption.UsePath, AsyncProcessOption.StdErrToStdOut,
    AsyncProcessOption.ProcessGroup,
  }

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

proc reapAsync(bp: BackgroundProcess): Future[void] {.async: (raises: []).} =
  discard await bp.waitForExitAsync()
  await bp.closeAsync()

proc waitForAsync(bp: BackgroundProcess): Future[seq[string]] {.async: (raises: []).} =
  ## Wait for process to complete and return all output lines.
  ## Read output first (blocks until EOF), then wait for exit.
  ##
  ## Unbounded, and deliberately not exported: a command that never exits never
  ## resolves this future. Callers go through the `timeout` overload, which
  ## reaches this only for an explicit `InfiniteDuration`.
  let output = await bp.readAllOutput()
  await bp.reapAsync()
  return output

proc waitForAsync*(
    bp: BackgroundProcess, timeout: Duration
): Future[ProcessOutputResult] {.async: (raises: []).} =
  ## Wait for the process and return its output, killing it once `timeout`
  ## elapses. `InfiniteDuration` waits without a bound.
  ##
  ## This is the bounded form every external command should use: a command that
  ## never exits (a hung compiler, a program reading stdin) is turned into an
  ## error instead of a Future and a child process that live until the editor
  ## quits. A timeout is always reported as an error, never as empty output.
  if timeout == InfiniteDuration:
    return ProcessOutputResult.ok(await bp.waitForAsync())

  let
    reader = bp.readAllOutput()
    timer = sleepAsync(timeout)
  try:
    discard await race(reader, timer)
  except CancelledError:
    discard

  if reader.finished:
    await timer.cancelAndWait()
    let output = await reader
    await bp.reapAsync()
    return ProcessOutputResult.ok(output)

  # Timed out. Kill first so the child's stdout reaches EOF and the reader can
  # finish; `race` deliberately leaves it running, and closing the handle out
  # from under a live read would be a use-after-free.
  bp.kill()
  try:
    discard await reader.withTimeout(KillGrace)
  except CancelledError:
    discard
  await bp.reapAsync()
  # `$Duration` keeps sub-second timeouts honest; `timeout.seconds` would
  # report "0" for anything shorter than a second.
  return ProcessOutputResult.err fmt"Timed out after {timeout}"
