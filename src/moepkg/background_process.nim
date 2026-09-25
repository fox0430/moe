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

import logger, child_process

import types/background_process_types
export background_process_types

proc timeoutFromSeconds*(seconds: int): Duration =
  ## Convert a config timeout to the value the bounded waits expect.
  ## Non-positive means the user opted out of the bound.
  if seconds <= 0: InfiniteDuration else: seconds.seconds

const KillGrace = 2.seconds
  ## How long a killed command is given to let go of its pipes before the
  ## transfers are cancelled out from under it.

proc exitCode*(bp: BackgroundProcess): Option[int] =
  ## How the command ended; none until then, or if that could not be learnt.
  if bp.process.isNil:
    none(int)
  else:
    bp.process.exitCode

proc cancel*(bp: BackgroundProcess) =
  ## SIGTERM the command and everything it started. A no-op once reaped.
  if not bp.process.isNil:
    bp.process.terminate()

proc kill*(bp: BackgroundProcess) =
  ## SIGKILL the command and everything it started: killing only the direct
  ## child would leave the real workers (compiler, linker, the program a
  ## `sh -c` wrapper launched) running with the pipe still open. A no-op once
  ## reaped, so the run that owns the job and the editor holding it can both
  ## signal through here.
  if not bp.process.isNil:
    bp.process.kill()

proc closeAsync*(bp: BackgroundProcess): Future[void] {.async: (raises: []).} =
  ## Let the command go: stopped if it still runs, reaped, pipes closed.
  if not bp.process.isNil:
    await bp.process.release()

proc waitForExitAsync*(
    bp: BackgroundProcess
): Future[Option[int]] {.async: (raises: []).} =
  ## Wait for the command to exit and return how it ended. `none` means that
  ## could not be learnt, which is not the same as any exit code a command
  ## could have produced; a cancelled wait also returns it, without waiting.
  if bp.process.isNil:
    return none(int)
  try:
    return some(await bp.process.waitForExit())
  except AsyncProcessError, CancelledError:
    return none(int)

proc runToCompletion(
    bp: BackgroundProcess, transfers: seq[FutureBase], timeout: Duration
): Future[ProcessRunOutcome] {.async: (raises: []).} =
  ## Wait for `transfers` and for the command to exit, bounded by `timeout`,
  ## then take the command down and reap it - whichever way the wait ended.
  ##
  ## The timeout and cancellation contract for external commands lives here and
  ## only here: however this returns, the command has been killed unless it
  ## exited on its own, every transfer is finished, its pipes are closed, and
  ## the child is reaped - or, if it outlived its kill, left to be reaped once
  ## it exits. A second copy of this drifts, and always the same way -
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
  # read.
  #
  # Nor is the exit waited for past the grace: a command in uninterruptible
  # sleep outlives its SIGKILL, and `release` has its own bound for that.
  if not await noCancel allFutures(waiter).withTimeout(KillGrace):
    await noCancel cancelAndWait(transfers)
  await cancelAndWait(transfers)
  await bp.closeAsync()
  return outcome

proc startBackgroundProcess*(command: BackgroundProcessCommand): StartProcessResult =
  ## Start the passed command in a new process and return BackgroundProcess.
  ## Standard error is merged into standard output, so a caller reading the
  ## output sees the diagnostics too.
  ##
  ## The command runs when this returns, and the handle is the caller's to
  ## list and to run: `waitForAsync` releases it.
  let process = startChild(command.cmd, command.workingDir, command.args).valueOr:
    return StartProcessResult.err fmt"Failed to create a background process: {error}"
  StartProcessResult.ok BackgroundProcess(process: process)

const ReadChunk = 64 * 1024 ## Bytes asked of a pipe per read.

const
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

proc addFront(s: var string, chunk: string, n: int) =
  ## Append the first `n` bytes of `chunk` without slicing them out first.
  if n > 0:
    let at = s.len
    s.setLen(at + n)
    copyMem(addr s[at], unsafeAddr chunk[0], n)

proc feedStdin(
    process: ChildProcess, data: string, failure: RunFailure
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
  var chunk = newString(ReadChunk)
  try:
    while not reader.atEof():
      let n = await reader.readOnce(addr chunk[0], ReadChunk)
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
          sink.text.addFront(chunk, sink.limit - sink.text.len)
        continue
      sink.text.addFront(chunk, n)
    sink.atEnd = true
  except AsyncStreamError as e:
    if sink.policy == dlpFail:
      # Nothing further on this stream is readable, so nothing further the
      # command writes is usable. The kill also keeps the other streams moving.
      failure.fail(ffReadFailed, "Failed to read the command output: " & e.msg)
      bp.kill()
  except CancelledError:
    discard

proc readAllOutput*(
    bp: BackgroundProcess
): Future[seq[string]] {.async: (raises: []).} =
  ## Read all output from the process stdout, split into lines.
  ##
  ## Split once it is all read rather than with `readLine`, which cannot tell a
  ## last empty line from a read that only found EOF: text after the last
  ## newline is a line, nothing after it is not, however the EOF arrives.
  if bp.process.isNil:
    return @[]
  let
    sink = DrainSink(policy: dlpFail)
    failure = RunFailure()
  await bp.drainBounded(bp.process.stdoutStream(), sink, failure)
  if failure.error.isSome:
    logError "background_process", failure.error.get.message
  if sink.text.len == 0:
    return @[]
  var lines = sink.text.split('\n')
  if sink.text.endsWith('\n'):
    lines.setLen(lines.len - 1)
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

proc startFilterProcess*(command: BackgroundProcessCommand): StartProcessResult =
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
  let process = startChild(
    command.cmd,
    command.workingDir,
    command.args,
    stdinMode = csPipe,
    stderrMode = cePipe,
  ).valueOr:
    return StartProcessResult.err fmt"Failed to create a background process: {error}"
  StartProcessResult.ok BackgroundProcess(process: process)

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
  ## However this returns, the process has been released.
  if bp.process.isNil or bp.process.released:
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
