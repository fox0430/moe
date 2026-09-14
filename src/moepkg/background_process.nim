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

import std/[options, strformat, strutils]

import pkg/[results, chronos]
import pkg/chronos/asyncproc

import logger

when defined(posix):
  import std/posix

import types/background_process_types
export background_process_types

proc timeoutFromSeconds*(seconds: int): Duration =
  ## Convert a config timeout to the value the bounded waits expect.
  ## Non-positive means the user opted out of the bound.
  if seconds <= 0: InfiniteDuration else: seconds.seconds

const KillGrace = 2.seconds
  ## How long a killed command is given to let go of its pipes before the
  ## transfers are cancelled out from under it.

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
  if bp.reaped or bp.process.isNil:
    return false
  let r = bp.process.running()
  if r.isErr:
    return false
  if not r.get:
    # `running` peeks with WNOHANG, which reaps the zombie it finds, so asking
    # is itself what spends the pid.
    bp.reaped = true
    return false
  return true

proc isFinish*(bp: BackgroundProcess): bool =
  not bp.isRunning

proc cancel*(bp: BackgroundProcess) =
  ## SIGTERM the process. A no-op once reaped, as for `kill`.
  if bp.process.isNil or bp.reaped:
    return
  discard bp.process.terminate()

proc kill*(bp: BackgroundProcess) =
  ## SIGKILL the process and everything it spawned. Killing only the direct
  ## child would leave the real workers (compiler, linker, the program a
  ## `sh -c` wrapper launched) running with the pipe still open.
  ##
  ## A no-op once the child has been reaped: the run that owns the job and the
  ## editor holding it both signal through here, so whether the pid is still
  ## the child's is decided once, here.
  if bp.process.isNil or bp.reaped:
    return
  killProcessGroup(bp.process.pid)
  discard bp.process.kill()

proc closeAsync*(bp: BackgroundProcess): Future[void] {.async: (raises: []).} =
  ## Release the handle.
  ##
  ## The field is cleared before the close suspends, not after: `closeWait` is
  ## a suspension point, and a `kill` arriving from the editor loop in that
  ## window would signal a pid the wait has already reaped.
  let process = bp.process
  bp.process = nil
  if not process.isNil:
    await noCancel process.closeWait()

proc waitForExitAsync*(
    bp: BackgroundProcess
): Future[Option[int]] {.async: (raises: []).} =
  ## Wait for the process to exit and return its status, also recording it in
  ## `exitCode` so it stays readable after the handle is gone. `none` means the
  ## status could not be determined, which is not the same as any exit code a
  ## command could have produced.
  if bp.process.isNil:
    return bp.exitCode

  try:
    let status = await bp.process.waitForExit()
    bp.reaped = true
    bp.exitCode = some(status)
  except AsyncProcessError:
    # Whether it was reaped is what could not be determined. Treated as reaped:
    # signalling a pid that may be somebody else's is the worse mistake.
    bp.reaped = true
    bp.exitCode = none(int)
  except CancelledError:
    # A cancelled wait never waited, so the child is still the child.
    bp.exitCode = none(int)
  return bp.exitCode

proc runToCompletion(
    bp: BackgroundProcess, transfers: seq[FutureBase], timeout: Duration
): Future[ProcessRunOutcome] {.async: (raises: []).} =
  ## Wait for `transfers` and for the command to exit, bounded by `timeout`,
  ## then take the command down and reap it - whichever way the wait ended.
  ##
  ## The timeout and cancellation contract for external commands lives here and
  ## only here: however this returns, the command has been killed unless it
  ## exited on its own, every transfer is finished, the child is reaped and the
  ## handle released. A second copy of this drifts, and always the same way -
  ## some path reaches the wait for exit with no kill in front of it.
  proc runAll(): Future[void] {.async: (raises: [CancelledError]).} =
    ## Everything the run consists of. The exit belongs here with the transfers
    ## because `timeout` has to bound the two together: a command that closes
    ## its streams and keeps working would pass a bound of any size.
    await allFutures(transfers)
    discard await bp.waitForExitAsync()

  let waiter = runAll()
  var
    outcome = proCompleted
    timer: Future[void] = nil
  if timeout != InfiniteDuration:
    timer = sleepAsync(timeout)

  # Awaited through a wrapper, never directly: neither a timeout nor a
  # cancellation may cancel `waiter`, or the wait for the exit is abandoned and
  # the child is never reaped. `allFutures` and `race` are here because neither
  # cancels what it aggregates.
  let shield = allFutures(waiter)
  try:
    if timer.isNil:
      await shield
    else:
      discard await race(FutureBase(shield), FutureBase(timer))
      if not waiter.finished:
        outcome = proTimedOut
  except CancelledError:
    outcome = proCancelled

  await shield.cancelAndWait()
  if not timer.isNil:
    await timer.cancelAndWait()

  if outcome != proCompleted:
    # Kill first: a pipe reaches EOF only once the command is gone, and the
    # wait for its exit never returns while it runs. Unconditional because
    # `kill` is a no-op on a reaped child.
    bp.kill()

  # Bounded on purpose. A descendant that escaped the process group holds the
  # write end open, and then no transfer reaches EOF: waiting for one would
  # last as long as that descendant. Past the grace the transfers are
  # cancelled instead, which costs only the tail since each keeps what it
  # read, and `allFutures` over cancelled transfers completes, so the wait
  # goes on to reap the child it has already killed.
  #
  # Uncancellable: a second cancellation here would leave the child running
  # with nobody to reap it.
  if not await noCancel allFutures(waiter).withTimeout(KillGrace):
    await noCancel cancelAndWait(transfers)
    await noCancel allFutures(waiter)
  await cancelAndWait(transfers)
  await bp.closeAsync()
  return outcome

proc startBackgroundProcess*(
    command: BackgroundProcessCommand
): Future[StartProcessResult] {.async: (raises: []).} =
  ## Start the passed command in a new process and return BackgroundProcess.
  ## Standard error is merged into standard output, so a caller reading the
  ## output sees the diagnostics too.
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
  except AsyncStreamError as e:
    logError "background_process", "Failed to read process output: " & e.msg
  except CancelledError:
    discard

  return lines

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
  let reader = bp.readAllOutput()
  case await bp.runToCompletion(@[FutureBase(reader)], timeout)
  of proCompleted:
    return ProcessOutputResult.ok(await reader)
  of proTimedOut:
    # `$Duration` keeps sub-second timeouts honest; `timeout.seconds` would
    # report "0" for anything shorter than a second.
    return ProcessOutputResult.err fmt"Timed out after {timeout}"
  of proCancelled:
    return ProcessOutputResult.err "The command was cancelled"

const
  FilterReadChunk = 64 * 1024
  FilterDiagnosticsLimit = 8 * 1024
    ## Bytes of standard error worth keeping. Bounded on its own rather than by
    ## the output limit: the diagnostics go to the status line and the message
    ## log, which is never trimmed, so a chatty command (`:%!make`) would grow
    ## the log by megabytes for a message nobody can read.
  FilterDiagnosticsLines = 10 ## Lines of it worth showing.

type
  DrainLimitPolicy = enum
    ## What a stream outrunning its limit means for the run.
    dlpFail ## The stream is the answer, so an incomplete one is an error.
    dlpTruncate ## The stream is commentary, so the first `limit` bytes will do.

  DrainSink = ref object
    ## Where a drain accumulates, owned by the caller rather than returned by
    ## the drain. That is what makes a drain safe to cancel: the run can bound
    ## the read and still keep every byte that arrived before the bound, so no
    ## teardown has to wait for an EOF nothing guarantees.
    limit: int ## Bytes to keep. Non-positive means no bound.
    policy: DrainLimitPolicy
    text: string
    overflowed: bool ## The stream wrote more than `limit`.
    atEnd: bool ## The stream was read all the way to EOF.

  RunFailure = ref object
    ## The reason a run produced nothing, filled in by whichever part failed
    ## first. First wins because the first is the cause: output past its limit
    ## kills the command, which is then also why the feed could not finish.
    error: Option[FilterProcessError]

proc fail(f: RunFailure, kind: FilterFailureKind, message: string) =
  if f.error.isNone:
    f.error = some filterError(kind, message)

proc feedStdin(
    process: AsyncProcessRef, data: string, failure: RunFailure
): Future[void] {.async: (raises: []).} =
  ## Hand the command its input and close the pipe so it sees EOF.
  ##
  ## A command that stops reading early is not an error, as for `!` in vim:
  ## `head -1` takes its line, drops the pipe, and what it printed is still the
  ## answer. Nor could it be one - "the command consumed everything" is not
  ## observable from the writing end, and whether the write fails at all
  ## depends on how much of the text fitted in the pipe buffer.
  let writer = process.stdinStream()
  if writer.isNil:
    failure.fail(ffStartFailed, "The command has no standard input")
    return

  proc sendEof() {.async: (raises: []).} =
    ## Put EOF on the pipe, which is what lets a filter finish.
    ##
    ## Closing the stream is not enough in chronos 4.2.2: the transport, and
    ## with it the descriptor, stays open and the command waits for input
    ## forever. Reaching into `tsource` is the way around that, and it is
    ## confined to this proc so a chronos upgrade has one place to revisit.
    ## `closeWait` is a no-op on an already closed half, so the later
    ## process-wide close is still safe.
    await noCancel writer.closeWait()
    if not writer.tsource.isNil:
      await noCancel writer.tsource.closeWait()

  try:
    if data.len > 0:
      await writer.write(data)
    await writer.finish()
  except AsyncStreamError:
    # The command stopped reading. See above: that is its business.
    discard
  except CancelledError:
    # The outcome of the run says it was cancelled; saying so again here would
    # only compete with the failure that caused the cancellation.
    discard
  await sendEof()

proc drainBounded(
    bp: BackgroundProcess,
    reader: AsyncStreamReader,
    sink: DrainSink,
    failure: RunFailure,
): Future[void] {.async: (raises: []).} =
  ## Read a stream to EOF into `sink`, keeping at most `sink.limit` bytes.
  ##
  ## What passing the limit means is the whole difference between the two
  ## streams. The command's output becomes the file, so a cut-off read is
  ## indistinguishable from a short one and keeping the part that fit would
  ## delete the rest of the text: `dlpFail` makes it an error, and kills the
  ## command, since nothing it writes from here on can be used anyway.
  ##
  ## Standard error is commentary, so `dlpTruncate` keeps the first `limit`
  ## bytes and reads the rest away rather than failing the run. Reading it away
  ## is the part that matters: a drain that stopped early would leave the
  ## command blocked on a pipe nobody empties, and it is the command that has
  ## to exit before the other streams reach EOF.
  ##
  ## Cancellation is not a failure: whatever reached `sink` stays there, and
  ## `sink.atEnd` says whether it is the whole stream.
  if reader.isNil:
    failure.fail(ffReadFailed, "The command has no output stream")
    return

  let bounded = sink.limit > 0
  var chunk = newString(FilterReadChunk)
  try:
    while not reader.atEof():
      let n = await reader.readOnce(addr chunk[0], FilterReadChunk)
      if n <= 0:
        break
      if sink.overflowed:
        continue
      if bounded and sink.text.len + n > sink.limit:
        sink.overflowed = true
        case sink.policy
        of dlpFail:
          sink.text = ""
          failure.fail(
            ffOutputTooLarge, "The command produced more than " & $sink.limit & " bytes"
          )
          bp.kill()
        of dlpTruncate:
          sink.text.add chunk[0 ..< sink.limit - sink.text.len]
        continue
      sink.text.add chunk[0 ..< n]
    sink.atEnd = true
  except AsyncStreamError as e:
    if sink.policy == dlpFail:
      # Nothing further on this stream is readable, so nothing further the
      # command writes is usable. The kill also keeps the other streams moving.
      failure.fail(ffReadFailed, "Failed to read the command output: " & e.msg)
      bp.kill()
  except CancelledError:
    discard

proc startFilterProcess*(
    command: BackgroundProcessCommand
): Future[StartProcessResult] {.async: (raises: []).} =
  ## Start `command` with each of its three standard streams on a pipe of its
  ## own, ready to be driven by `filterOutput`.
  ##
  ## Standard error is not merged into standard output the way
  ## `startBackgroundProcess` merges it: a filter's output becomes the file, so
  ## a warning line would be written into the user's source.
  ##
  ## Split from the wait so the handle belongs to the caller from the moment it
  ## exists - the editor registers it and can kill it - rather than being
  ## lent back through a callback from inside the run.
  const Options = {AsyncProcessOption.UsePath, AsyncProcessOption.ProcessGroup}

  try:
    let process = await startProcess(
      command.cmd,
      command.workingDir,
      command.args,
      options = Options,
      stdinHandle = AsyncProcess.Pipe,
      stdoutHandle = AsyncProcess.Pipe,
      stderrHandle = AsyncProcess.Pipe,
    )
    return StartProcessResult.ok BackgroundProcess(process: process)
  except AsyncProcessError as e:
    return StartProcessResult.err fmt"Failed to create a background process: {e.msg}"
  except CancelledError:
    return StartProcessResult.err "Process start was cancelled"

proc filterOutput*(
    bp: BackgroundProcess, input: string, timeout: Duration, limit: int
): Future[FilterProcessResult] {.async: (raises: []).} =
  ## Run the process started by `startFilterProcess` as a text filter: `input`
  ## on its standard input, its standard output returned. `limit` bounds the
  ## output in bytes; non-positive means no bound, as it does for the timeout.
  ## Standard error is bounded separately and far more tightly: it is only a
  ## message, so a few lines of it are as much as anyone reads.
  ##
  ## Input and both outputs move at once. Feeding the input first would
  ## deadlock on anything larger than a pipe buffer.
  ##
  ## However this returns, the process has been reaped and the handle dropped.
  if bp.process.isNil:
    return
      FilterProcessResult.err(filterError(ffStartFailed, "The command is not running"))

  let
    process = bp.process
    failure = RunFailure()
    outSink = DrainSink(limit: limit, policy: dlpFail)
    errSink = DrainSink(limit: FilterDiagnosticsLimit, policy: dlpTruncate)
    feeder = feedStdin(process, input, failure)
    outReader = bp.drainBounded(process.stdoutStream(), outSink, failure)
    errReader = bp.drainBounded(process.stderrStream(), errSink, failure)

  let outcome = await bp.runToCompletion(
    @[FutureBase(feeder), FutureBase(outReader), FutureBase(errReader)], timeout
  )
  case outcome
  of proTimedOut:
    # `$Duration` keeps sub-second timeouts honest; `timeout.seconds` would
    # report "0" for anything shorter than a second.
    return
      FilterProcessResult.err(filterError(ffTimedOut, fmt"Timed out after {timeout}"))
  of proCancelled:
    return FilterProcessResult.err filterError(ffCancelled, "The command was cancelled")
  of proCompleted:
    discard

  if failure.error.isSome:
    return FilterProcessResult.err failure.error.get

  if not outSink.atEnd:
    # Something that outlived the process group is holding the pipe open, so
    # the drain was cut off at the grace. What arrived is a prefix of the
    # answer, and applying a prefix deletes the rest of the text.
    return FilterProcessResult.err filterError(
      ffReadFailed, "Could not read all of the command output"
    )

  # Standard error only ever costs the message, never the run.
  var diagnostics: seq[string]
  # Commands end their standard error with a newline, and splitting that
  # yields a trailing empty line that would show up as a blank diagnostic.
  let text = errSink.text.strip(leading = false, chars = {'\n', '\r'})
  if text.len > 0:
    diagnostics = text.splitLines
  var truncated = errSink.overflowed
  if diagnostics.len > FilterDiagnosticsLines:
    diagnostics.setLen(FilterDiagnosticsLines)
    truncated = true

  return FilterProcessResult.ok FilterProcessOutput(
    output: outSink.text,
    diagnostics: diagnostics,
    diagnosticsTruncated: truncated,
    exitCode: bp.exitCode,
  )
