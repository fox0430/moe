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

import std/[importutils, unittest, options, os, sequtils, strutils]

import pkg/chronos
import pkg/chronos/asyncproc

import ../src/moepkg/[background_process {.all.}, child_process {.all.}]

proc outputOf(bp: BackgroundProcess): Future[seq[string]] {.async.} =
  ## Unbounded wait, for the tests that are about what a command printed
  ## rather than about the bound. Production callers go through
  ## `waitForAsync(timeout)` and handle the failure.
  let r = await bp.waitForAsync(InfiniteDuration)
  return
    if r.isOk:
      r.get
    else:
      @[]

suite "BackgroundProcess - BackgroundProcessCommand":
  test "Create BackgroundProcessCommand":
    let cmd = BackgroundProcessCommand(
      cmd: "echo", args: @["hello", "world"], workingDir: "/tmp"
    )

    check cmd.cmd == "echo"
    check cmd.args == @["hello", "world"]
    check cmd.workingDir == "/tmp"

  test "Create BackgroundProcessCommand with empty args":
    let cmd = BackgroundProcessCommand(cmd: "pwd", args: @[], workingDir: ".")

    check cmd.cmd == "pwd"
    check cmd.args.len == 0
    check cmd.workingDir == "."

suite "BackgroundProcess - startBackgroundProcess":
  test "Start echo command":
    proc runTest(): Future[tuple[isOk: bool, processNotNil: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["hello"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let notNil = not bp.process.isNil
        await bp.closeAsync()
        return (true, notNil)
      else:
        return (false, false)

    let r = waitFor runTest()
    check r.isOk
    check r.processNotNil

  test "Start command with invalid executable":
    proc runTest(): Future[bool] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "/nonexistent/command/that/does/not/exist",
        args: @[],
        workingDir: getCurrentDir(),
      )

      let r = startBackgroundProcess(cmd)
      return r.isErr

    check waitFor(runTest())

  test "Start command with working directory":
    proc runTest(): Future[tuple[success: bool, output: seq[string]]] {.async.} =
      let cmd = BackgroundProcessCommand(cmd: "pwd", args: @[], workingDir: "/tmp")

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let output = await bp.outputOf()
        return (true, output)
      else:
        return (false, @[])

    let r = waitFor runTest()
    check r.success
    check r.output.len > 0
    check r.output[0] == "/tmp"

suite "BackgroundProcess - whether the child runs":
  test "A started child runs":
    proc runTest(): Future[bool] {.async.} =
      let bp = startBackgroundProcess(
        BackgroundProcessCommand(
          cmd: "sleep", args: @["1"], workingDir: getCurrentDir()
        )
      ).get
      let running = bp.process.running()
      await bp.closeAsync()
      return running

    check waitFor runTest()

  test "A child that has exited does not":
    proc runTest(): Future[bool] {.async.} =
      let bp = startBackgroundProcess(
        BackgroundProcessCommand(
          cmd: "echo", args: @["done"], workingDir: getCurrentDir()
        )
      ).get
      discard await bp.outputOf()
      return bp.process.running()

    check not waitFor runTest()

suite "BackgroundProcess - readAllOutput":
  test "Read single line output":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["hello"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let output = await bp.readAllOutput()
        await bp.closeAsync()
        return output
      else:
        return @[]

    let output = waitFor runTest()
    check output.len >= 1
    check output[0] == "hello"

  test "Read multiple line output":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sh",
        args: @["-c", "echo line1; echo line2; echo line3"],
        workingDir: getCurrentDir(),
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let output = await bp.readAllOutput()
        await bp.closeAsync()
        return output
      else:
        return @[]

    let output = waitFor runTest()
    check output.len >= 3
    check output[0] == "line1"
    check output[1] == "line2"
    check output[2] == "line3"

  test "Read empty output":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd =
        BackgroundProcessCommand(cmd: "true", args: @[], workingDir: getCurrentDir())

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let output = await bp.readAllOutput()
        await bp.closeAsync()
        return output
      else:
        return @["error"]

    let output = waitFor runTest()
    # true command produces no output
    check output.len == 0 or (output.len == 1 and output[0] == "")

  test "readAllOutput with nil process":
    proc runTest(): Future[seq[string]] {.async.} =
      let bp = BackgroundProcess(process: nil)
      return await bp.readAllOutput()

    let output = waitFor runTest()
    check output.len == 0

proc tailOf(script: string, limit: int): seq[string] =
  ## What `readAllOutput` keeps of `sh -c script` within `limit` bytes.
  proc run(): Future[seq[string]] {.async.} =
    let bp = startBackgroundProcess(
      BackgroundProcessCommand(
        cmd: "sh", args: @["-c", script], workingDir: getTempDir()
      )
    ).get
    let output = await bp.readAllOutput(limit)
    await bp.closeAsync()
    return output

  waitFor run()

suite "BackgroundProcess - readAllOutput keeping the end":
  test "Only the whole lines at the end of a flood are kept, after a mark":
    let output = tailOf("seq 1 100000", 1000)
    check output[0] == OutputDroppedMarker
    check output[^1] == "100000"
    # Every line kept is a whole number, not the cut end of one.
    check output[1 ..^ 1].allIt(it.len > 0 and it.allCharsInSet(Digits))
    check output[1 ..^ 1].join("\n").len <= 1000
    check output[1].parseInt + output.len - 2 == 100000

  test "A cut right after a newline keeps the line it starts":
    # The last 10 bytes are "ABCD\nEFGH\n", right after a newline.
    check tailOf("printf '0123456789\\nABCD\\nEFGH\\n'", 10) ==
      @[OutputDroppedMarker, "ABCD", "EFGH"]

  test "A cut inside a line drops what is left of it":
    # The last 10 bytes are "B\nCD\nEFGH\n": "B" is the end of "AB".
    check tailOf("printf '0123456789\\nAB\\nCD\\nEFGH\\n'", 10) ==
      @[OutputDroppedMarker, "CD", "EFGH"]

  test "Output within the limit is kept whole, with no mark":
    check tailOf("printf 'a\\nb\\n'", 1000) == @["a", "b"]

  test "A single line longer than the limit keeps its end":
    let output = tailOf("printf %05000d 7", 100)
    check output.len == 2
    check output[0] == OutputDroppedMarker
    check output[1].len == 100
    check output[1].endsWith("7")

  test "A single overlong line with a trailing newline keeps its end":
    let output = tailOf("printf '%05000d\\n' 7", 100)
    check output.len == 2
    check output[0] == OutputDroppedMarker
    check output[1].len == 99
    check output[1].endsWith("7")

  test "An overlong line ending in a blank line keeps its end":
    # The last 100 bytes are 98 digits then two newlines. Dropping the cut
    # line here would leave the mark and a blank line and nothing else.
    let output = tailOf("printf '%05000d\\n\\n' 7", 100)
    check output.len == 3
    check output[0] == OutputDroppedMarker
    check output[1].len == 98
    check output[1].endsWith("7")
    check output[2] == ""

  test "A read failing midway fails the run and kills the command":
    # What was kept is no longer the end, and a command still writing would
    # block on a pipe nobody empties until its timeout.
    privateAccess(DrainSink)
    privateAccess(RunFailure)
    const Script =
      "echo first; sleep 0.3; " &
      "i=0; while [ $i -lt 200000 ]; do echo more$i; i=$((i+1)); done"

    proc run(policy: DrainLimitPolicy): Future[(bool, bool)] {.async.} =
      let bp = startBackgroundProcess(
        BackgroundProcessCommand(cmd: "sh", args: @["-c", Script], workingDir: "")
      ).get
      let reader = bp.process.stdoutStream()
      let sink = DrainSink(limit: 1024 * 1024, policy: policy)
      let failure = RunFailure()
      let drain = bp.drainBounded(reader, sink, failure)
      await sleepAsync(100.milliseconds)
      # The next read raises, once the pending one returns.
      reader.close()
      await drain
      let failed = failure.error.isSome and failure.error.get.kind == ffReadFailed
      let exited = await bp.waitForExitAsync().withTimeout(2.seconds)
      bp.kill()
      await bp.closeAsync()
      return (failed, exited)

    for policy in [dlpFail, dlpKeepTail]:
      let (failed, exited) = waitFor run(policy)
      check failed
      check exited

suite "BackgroundProcess - waitForExitAsync":
  test "Wait for successful command":
    proc runTest(): Future[int] {.async.} =
      let cmd =
        BackgroundProcessCommand(cmd: "true", args: @[], workingDir: getCurrentDir())

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let exitCode = await bp.waitForExitAsync()
        await bp.closeAsync()
        return exitCode.get(-999)
      else:
        return -999

    let exitCode = waitFor runTest()
    check exitCode == 0

  test "Wait for failing command":
    proc runTest(): Future[int] {.async.} =
      let cmd =
        BackgroundProcessCommand(cmd: "false", args: @[], workingDir: getCurrentDir())

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let exitCode = await bp.waitForExitAsync()
        await bp.closeAsync()
        return exitCode.get(-999)
      else:
        return -999

    let exitCode = waitFor runTest()
    check exitCode == 1

  test "Wait for command with specific exit code":
    proc runTest(): Future[int] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sh", args: @["-c", "exit 42"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let exitCode = await bp.waitForExitAsync()
        await bp.closeAsync()
        return exitCode.get(-999)
      else:
        return -999

    let exitCode = waitFor runTest()
    check exitCode == 42

  test "A process that was never started has no status":
    proc runTest(): Future[Option[int]] {.async.} =
      let bp = BackgroundProcess(process: nil)
      return await bp.waitForExitAsync()

    check (waitFor runTest()).isNone

suite "BackgroundProcess - waitForAsync":
  test "Wait for command and get output":
    proc runTest(): Future[tuple[output: seq[string], processIsNil: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["test output"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let output = await bp.outputOf()
        return (output, bp.process.released)
      else:
        return (@[], false)

    let r = waitFor runTest()
    check r.output.len >= 1
    check r.output[0] == "test output"
    # After waitForAsync, process should be closed
    check r.processIsNil

  test "waitForAsync cleans up process":
    proc runTest(): Future[tuple[beforeNil: bool, afterNil: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["cleanup test"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let beforeNil = bp.process.released
        discard await bp.outputOf()
        let afterNil = bp.process.released
        return (beforeNil, afterNil)
      else:
        return (true, true)

    let r = waitFor runTest()
    check r.beforeNil == false
    check r.afterNil == true

suite "BackgroundProcess - cancel and kill":
  test "Cancel running process":
    proc runTest(): Future[bool] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["10"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let running = bp.process.running()
        bp.cancel()
        await sleepAsync(100.milliseconds)
        await bp.closeAsync()
        return running
      else:
        return false

    let wasRunning = waitFor runTest()
    check wasRunning == true

  test "Kill running process":
    proc runTest(): Future[bool] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["10"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let running = bp.process.running()
        bp.kill()
        await sleepAsync(100.milliseconds)
        await bp.closeAsync()
        return running
      else:
        return false

    let wasRunning = waitFor runTest()
    check wasRunning == true

  test "A released process is never signalled again":
    # Its pid may be somebody else's from then on, and both the run and the
    # editor holding the job in `runningBackgroundProcesses` signal through
    # the same `kill`.
    proc runTest(): Future[BackgroundProcess] {.async.} =
      let r = startBackgroundProcess(
        BackgroundProcessCommand(
          cmd: "sh", args: @["-c", "exit 0"], workingDir: getCurrentDir()
        )
      )
      let bp = r.get
      discard await bp.waitForExitAsync()
      await bp.closeAsync()
      bp.kill()
      bp.cancel()
      return bp

    let bp = waitFor runTest()
    check bp.process.fate == cfReaped
    check not bp.process.running()

  test "Cancel nil process does nothing":
    let bp = BackgroundProcess(process: nil)
    bp.cancel() # Should not crash
    check true # Test passes if no crash

  test "Kill nil process does nothing":
    let bp = BackgroundProcess(process: nil)
    bp.kill() # Should not crash
    check true # Test passes if no crash

suite "BackgroundProcess - closeAsync":
  test "Close running process":
    proc runTest(): Future[tuple[beforeNil: bool, afterNil: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["close test"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let beforeNil = bp.process.released
        await bp.closeAsync()
        let afterNil = bp.process.released
        return (beforeNil, afterNil)
      else:
        return (true, true)

    let r = waitFor runTest()
    check r.beforeNil == false
    check r.afterNil == true

  test "Close nil process does nothing":
    proc runTest(): Future[bool] {.async.} =
      let bp = BackgroundProcess(process: nil)
      await bp.closeAsync() # Should not crash
      return bp.process.isNil

    let isNil = waitFor runTest()
    check isNil

  test "Double close is safe":
    proc runTest(): Future[bool] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["double close"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        await bp.closeAsync()
        await bp.closeAsync() # Second close should be safe
        return bp.process.released
      else:
        return false

    let isNil = waitFor runTest()
    check isNil

suite "BackgroundProcess - stderr capture":
  test "Capture stderr output":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sh", args: @["-c", "echo error >&2"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        return await bp.outputOf()
      else:
        return @[]

    let output = waitFor runTest()
    # stderr should be captured (StdErrToStdOut option)
    check output.len >= 1
    check output[0] == "error"

  test "Capture mixed stdout and stderr":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sh",
        args: @["-c", "echo stdout; echo stderr >&2"],
        workingDir: getCurrentDir(),
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        return await bp.outputOf()
      else:
        return @[]

    let output = waitFor runTest()
    # Both stdout and stderr should be captured (may be on same or different lines)
    check output.len >= 1
    # Verify content contains both outputs
    let combined = output.join("")
    check "stdout" in combined
    check "stderr" in combined

suite "BackgroundProcess - edge cases":
  test "Command with special characters in args":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["hello world", "with spaces"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        return await bp.outputOf()
      else:
        return @[]

    let output = waitFor runTest()
    check output.len >= 1
    check output[0] == "hello world with spaces"

  test "Command with unicode output":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["日本語テスト"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        return await bp.outputOf()
      else:
        return @[]

    let output = waitFor runTest()
    check output.len >= 1
    check output[0] == "日本語テスト"

  test "Command with empty string arg":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd =
        BackgroundProcessCommand(cmd: "echo", args: @[""], workingDir: getCurrentDir())

      let r = startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        return await bp.outputOf()
      else:
        return @[]

    let output = waitFor runTest()
    check output.len >= 1

  test "Multiple sequential processes":
    proc runTest(): Future[seq[string]] {.async.} =
      var results: seq[string] = @[]
      for i in 1 .. 3:
        let cmd = BackgroundProcessCommand(
          cmd: "echo", args: @[$i], workingDir: getCurrentDir()
        )

        let r = startBackgroundProcess(cmd)
        if r.isOk:
          let bp = r.get
          let output = await bp.outputOf()
          if output.len > 0:
            results.add(output[0])

      return results

    let results = waitFor runTest()
    check results.len == 3
    check results[0] == "1"
    check results[1] == "2"
    check results[2] == "3"

suite "BackgroundProcess - waitForAsync with timeout":
  test "Return the output when the process finishes in time":
    proc runTest(): Future[ProcessOutputResult] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["fast"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isErr:
        return ProcessOutputResult.err "start failed"
      return await r.get.waitForAsync(5.seconds)

    let r = waitFor runTest()
    check r.isOk
    check r.get.len >= 1
    check r.get[0] == "fast"

  test "Kill and report an error when the timeout elapses":
    proc runTest(): Future[tuple[r: ProcessOutputResult, closed: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["30"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isErr:
        return (ProcessOutputResult.err "start failed", false)
      let bp = r.get
      let waitResult = await bp.waitForAsync(200.milliseconds)
      return (waitResult, bp.process.released)

    let r = waitFor runTest()
    check r.r.isErr
    check "Timed out" in r.r.error
    # The handle is released even on the timeout path.
    check r.closed

  test "Kill the whole process group on timeout":
    # `sh` exits immediately but its child keeps the pipe open, so killing only
    # the direct child would leave the reader waiting forever.
    proc runTest(): Future[ProcessOutputResult] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sh", args: @["-c", "sleep 30 & wait"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isErr:
        return ProcessOutputResult.err "start failed"
      return await r.get.waitForAsync(200.milliseconds)

    let r = waitFor runTest()
    check r.isErr
    check "Timed out" in r.error

  when defined(linux):
    test "Timeout when a grandchild escapes the group and keeps the pipe open":
      # The escaped grandchild keeps the pipe open after group kill, so EOF
      # never arrives. waitForAsync must cancel the reader before closing the
      # handle.
      proc runTest(): Future[ProcessOutputResult] {.async.} =
        let cmd = BackgroundProcessCommand(
          cmd: "sh", args: @["-c", "setsid sleep 5 & wait"], workingDir: getCurrentDir()
        )

        let r = startBackgroundProcess(cmd)
        if r.isErr:
          return ProcessOutputResult.err "start failed"
        return await r.get.waitForAsync(200.milliseconds)

      let r = waitFor runTest()
      check r.isErr
      check "Timed out" in r.error

  test "InfiniteDuration waits without a bound":
    proc runTest(): Future[ProcessOutputResult] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sh", args: @["-c", "sleep 0.2; echo slow"], workingDir: getCurrentDir()
      )

      let r = startBackgroundProcess(cmd)
      if r.isErr:
        return ProcessOutputResult.err "start failed"
      return await r.get.waitForAsync(InfiniteDuration)

    let r = waitFor runTest()
    check r.isOk
    check r.get[0] == "slow"

suite "BackgroundProcess - waitForAsync with a stop":
  proc stopLater(stop: JobStop) {.async.} =
    await sleepAsync(100.milliseconds)
    stop.request()

  test "A stop kills the command and is reported as one":
    proc runTest(): Future[tuple[r: ProcessOutputResult, closed: bool]] {.async.} =
      let r = startBackgroundProcess(
        BackgroundProcessCommand(
          cmd: "sleep", args: @["30"], workingDir: getCurrentDir()
        )
      )
      if r.isErr:
        return (ProcessOutputResult.err "start failed", false)
      let stop = JobStop()
      asyncSpawn stopLater(stop)
      let waitResult = await r.get.waitForAsync(30.seconds, stop)
      return (waitResult, r.get.process.released)

    let started = Moment.now()
    let r = waitFor runTest()
    check r.r.isErr
    check "stopped" in r.r.error
    check r.closed
    check Moment.now() - started < 5.seconds

  test "A stop asked before the wait ends it at once":
    proc runTest(): Future[ProcessOutputResult] {.async.} =
      let r = startBackgroundProcess(
        BackgroundProcessCommand(
          cmd: "sleep", args: @["30"], workingDir: getCurrentDir()
        )
      )
      if r.isErr:
        return ProcessOutputResult.err "start failed"
      let stop = JobStop()
      stop.request()
      return await r.get.waitForAsync(30.seconds, stop)

    let started = Moment.now()
    let r = waitFor runTest()
    check r.isErr
    check "stopped" in r.error
    check Moment.now() - started < 5.seconds

  test "The kill does not wait for a turn of the loop":
    # A stop at quit gets no further turn: the kill must already have landed.
    let r = startBackgroundProcess(
      BackgroundProcessCommand(cmd: "sleep", args: @["30"], workingDir: getCurrentDir())
    )
    check r.isOk
    let stop = JobStop()
    let waiting = r.get.waitForAsync(30.seconds, stop)
    stop.request()
    # Blocking, so the loop does not turn.
    var gone = false
    for _ in 0 ..< 200:
      if not r.get.process.running():
        gone = true
        break
      os.sleep(10)
    check gone
    discard waitFor waiting

  when defined(linux):
    test "A stop ends the wait within the grace when a descendant keeps the pipe":
      # The kill reaches the group, not what left it, so EOF never arrives.
      # Stopping from outside the wait left it waiting for that descendant.
      proc runTest(): Future[ProcessOutputResult] {.async.} =
        let r = startBackgroundProcess(
          BackgroundProcessCommand(
            cmd: "sh",
            args: @["-c", "setsid sleep 6 & sleep 30"],
            workingDir: getCurrentDir(),
          )
        )
        if r.isErr:
          return ProcessOutputResult.err "start failed"
        let stop = JobStop()
        asyncSpawn stopLater(stop)
        return await r.get.waitForAsync(InfiniteDuration, stop)

      let started = Moment.now()
      let r = waitFor runTest()
      check r.isErr
      check "stopped" in r.error
      check Moment.now() - started < 5.seconds

suite "BackgroundProcess - timeoutFromSeconds":
  test "Positive seconds become a bounded duration":
    check timeoutFromSeconds(30) == 30.seconds

  test "Zero and negative mean no timeout":
    check timeoutFromSeconds(0) == InfiniteDuration
    check timeoutFromSeconds(-1) == InfiniteDuration

suite "BackgroundProcess - filterOutput":
  const Unbounded = 64 * 1024 * 1024

  proc startFilter(cmd: string, args: seq[string]): BackgroundProcess =
    let r = startFilterProcess(
      BackgroundProcessCommand(cmd: cmd, args: args, workingDir: getTempDir())
    )
    doAssert r.isOk, r.error
    r.get

  proc runFilter(
      cmd: string,
      args: seq[string],
      input: string,
      timeout = InfiniteDuration,
      limit = Unbounded,
  ): FilterProcessResult =
    proc go(): Future[FilterProcessResult] {.async.} =
      let bp = startFilter(cmd, args)
      return await bp.filterOutput(input, timeout, limit)

    waitFor go()

  test "The command's standard output comes back verbatim":
    let r = runFilter("tr", @["a-z", "A-Z"], "hello\nworld\n")
    check r.isOk
    check r.get.output == "HELLO\nWORLD\n"
    check r.get.exitCode == some(0)

  test "An input larger than a pipe buffer does not deadlock":
    # A pipe holds 64 KiB on Linux. Feeding the whole input before reading any
    # output wedges both sides well before this size.
    let input = "x".repeat(4 * 1024 * 1024) & "\n"
    let r = runFilter("cat", @[], input)
    check r.isOk
    check r.get.output.len == input.len

  test "Standard error is kept out of the output":
    let r = runFilter("sh", @["-c", "cat; echo 'a warning' >&2"], "content\n")
    check r.isOk
    check r.get.output == "content\n"
    check r.get.diagnostics == @["a warning"]
    check not r.get.diagnosticsTruncated

  test "A blank line inside the diagnostics survives, the trailing one does not":
    let r = runFilter("sh", @["-c", "cat; printf 'one\n\ntwo\n' >&2"], "content\n")
    check r.isOk
    check r.get.diagnostics == @["one", "", "two"]

  test "Output past the limit is an error, not a truncation":
    let r = runFilter("cat", @[], "x".repeat(5000), limit = 1024)
    check r.isErr
    check r.error.kind == ffOutputTooLarge
    check "more than 1024 bytes" in r.error.message

  test "An oversized standard error is truncated rather than dropped":
    # Commentary is worth keeping in part. The drain also has to run to EOF:
    # a reader that stops leaves the command blocked on a full pipe, and
    # nothing else reaches EOF until the command exits.
    let r = runFilter(
      "sh",
      @["-c", "cat; yes warning | head -c 200000 >&2"],
      "content\n",
      timeout = 10.seconds,
      limit = 1024,
    )
    check r.isOk
    check r.get.output == "content\n"
    check r.get.diagnosticsTruncated
    check r.get.diagnostics.len > 0
    check r.get.diagnostics[0] == "warning"

  test "An oversized standard output ends the run instead of reading it away":
    # The error is the answer, and it must not be an error that only arrives
    # at the timeout: nothing the command writes from here on can be used, so
    # it is killed rather than drained.
    let r = runFilter(
      "sh", @["-c", "yes x | head -c 200000"], "", timeout = 10.seconds, limit = 1024
    )
    check r.isErr
    check r.error.kind == ffOutputTooLarge

  test "A non-positive limit means no bound":
    # Same convention as the timeout, and the arithmetic behind the bound is
    # only reached when there is one: a negative limit used to build a
    # negative-length slice and take the editor down with a Defect.
    for limit in [0, -1]:
      let r = runFilter("cat", @[], "x".repeat(5000), limit = limit)
      check r.isOk
      check r.get.output.len == 5000

  test "A non-zero exit is reported without losing the output":
    let r = runFilter("sh", @["-c", "cat; exit 3"], "kept\n")
    check r.isOk
    check r.get.exitCode == some(3)
    check r.get.output == "kept\n"

  test "A command that hangs is killed and reported":
    let r = runFilter("sh", @["-c", "sleep 30"], "in\n", timeout = 300.milliseconds)
    check r.isErr
    check r.error.kind == ffTimedOut

  test "A timeout is bounded even when the command closes its own streams":
    # The transfers all reach EOF while the command runs on. Bounding only
    # them would let the run last as long as the command does.
    let r = runFilter(
      "sh", @["-c", "exec 0<&- 1>&- 2>&-; sleep 30"], "in\n", timeout = 300.milliseconds
    )
    check r.isErr
    check r.error.kind == ffTimedOut

  test "A command that stops reading early keeps its output, as in vim":
    # `head -1` drops the pipe after its line, and what it printed is still
    # the answer.
    let r = runFilter("head", @["-n", "1"], "a\nb\nc\n")
    check r.isOk
    check r.get.output == "a\n"

  test "Stopping early is the same answer whatever the input size":
    # The write fails with EPIPE only once the text outgrows a pipe buffer, so
    # anything read off that distinction made the same command succeed on a
    # short selection and fail on a long one.
    let r = runFilter("head", @["-n", "1"], "a\n" & "x".repeat(1024 * 1024) & "\n")
    check r.isOk
    check r.get.output == "a\n"

  test "A command that never reads its input still filters":
    let r = runFilter("sh", @["-c", "echo replaced"], "x".repeat(1024 * 1024))
    check r.isOk
    check r.get.output == "replaced\n"

  test "Empty input is a clean EOF rather than a broken pipe":
    let r = runFilter("cat", @[], "")
    check r.isOk
    check r.get.output == ""

  when defined(linux):
    test "A grandchild holding the pipe open cannot outlast the timeout":
      # The escaped grandchild keeps the output pipe open after the group
      # kill, so the drain never sees EOF. Waiting for that EOF would make the
      # run last exactly as long as the grandchild, whatever the timeout said.
      let start = Moment.now()
      let r = runFilter(
        "sh", @["-c", "setsid sleep 30 &"], "in\n", timeout = 200.milliseconds
      )
      let elapsed = Moment.now() - start
      check r.isErr
      check r.error.kind == ffTimedOut
      check elapsed < 10.seconds

  test "Cancelling the run kills the command rather than orphaning it":
    # The `finally` of an aborted caller cancels this. Without a kill the child
    # runs on unattended, long after the editor stopped waiting for it.
    let marker = getTempDir() / "moe_filter_cancel_marker"
    removeFile(marker)
    defer:
      removeFile(marker)

    proc go(marker: string): Future[void] {.async.} =
      let bp = startFilter("sh", @["-c", "sleep 0.5; : > " & marker])
      let running = bp.filterOutput("in\n", InfiniteDuration, Unbounded)
      await sleepAsync(100.milliseconds)
      await running.cancelAndWait()

    waitFor go(marker)
    waitFor sleepAsync(1500.milliseconds)
    check not fileExists(marker)

  test "A cancellation landing after the transfers still kills the command":
    # The command closes its streams and keeps running, so the cancellation
    # arrives once every transfer is already done - the one path that used to
    # reach the wait for exit without a kill in front of it, report the run as
    # a success, and leave the child to finish on its own.
    let marker = getTempDir() / "moe_filter_late_cancel_marker"
    removeFile(marker)
    defer:
      removeFile(marker)

    proc go(marker: string): Future[void] {.async.} =
      let bp =
        startFilter("sh", @["-c", "exec 0<&- 1>&- 2>&-; sleep 0.5; : > " & marker])
      let running = bp.filterOutput("in\n", InfiniteDuration, Unbounded)
      await sleepAsync(150.milliseconds)
      await running.cancelAndWait()

    waitFor go(marker)
    waitFor sleepAsync(1500.milliseconds)
    check not fileExists(marker)

  test "A cancelled run is still reaped":
    # The editor holds the handle to kill the job, and it is cleared here as
    # the run ends. Missing that once strands the entry for the rest of the
    # session, where it keeps claiming its path against every later job on
    # that file.
    proc go(): Future[BackgroundProcess] {.async.} =
      let bp = startFilter("sh", @["-c", "sleep 5"])
      let running = bp.filterOutput("in\n", InfiniteDuration, Unbounded)
      await sleepAsync(100.milliseconds)
      # Twice, with the second landing while the first is already unwinding
      # the transfers: the teardown is where an escaping cancellation would
      # cost the reap.
      let stopping = running.cancelAndWait()
      await running.cancelAndWait()
      await stopping
      return bp

    let bp = waitFor go()
    check bp.process.released
    check not bp.process.running()

when defined(linux):
  import std/posix

  proc start(cmd: string, args: seq[string], dir = ""): BackgroundProcess =
    let r = startBackgroundProcess(
      BackgroundProcessCommand(cmd: cmd, args: args, workingDir: dir)
    )
    doAssert r.isOk, r.error
    r.get

  proc pidWrittenTo(path: string): Pid =
    for _ in 0 ..< 500:
      if fileExists(path) and readFile(path).strip.len > 0:
        return Pid(parseInt(readFile(path).strip))
      sleep(10)
    doAssert false, "no pid in " & path

  proc isZombie(pid: int): bool =
    readFile("/proc/" & $pid & "/stat").split(' ')[2] == "Z"

  proc gone(pid: Pid): bool =
    ## Whether `pid` has died; one that is not moe's child is reaped by init.
    for _ in 0 ..< 200:
      try:
        if posix.kill(pid, 0) != 0 or isZombie(int(pid)):
          return true
      except IOError:
        return true
      sleep(10)
    false

  proc zombieChildren(): int =
    ## Children of this process that exited and were never reaped.
    let me = $getCurrentProcessId()
    for kind, path in walkDir("/proc"):
      if kind != pcDir or not path.extractFilename.allCharsInSet(Digits):
        continue
      try:
        let
          stat = readFile(path / "stat")
          # After the parenthesised name: state, then the parent's pid.
          fields = stat[stat.rfind(')') + 2 .. ^1].split(' ')
        if fields[0] == "Z" and fields[1] == me:
          result.inc
      except IOError, OSError:
        discard

  suite "BackgroundProcess - how a child is started":
    # Run twice: as is, and from test_backgroundprocess_fork with fork and exec
    # starting every child. Both ways promise the same.
    test "moe's working directory stays put, even when a start fails":
      let
        before = getCurrentDir()
        a = getTempDir() / "moe_test_spawn_wd_a"
        b = getTempDir() / "moe_test_spawn_wd_b"
      createDir(a)
      createDir(b)
      defer:
        removeDir(a)
        removeDir(b)

      let missing = startBackgroundProcess(
        BackgroundProcessCommand(cmd: "moe-no-such-command", args: @[], workingDir: a)
      )
      let pwd = startBackgroundProcess(
        BackgroundProcessCommand(cmd: "pwd", args: @[], workingDir: b)
      )
      check getCurrentDir() == before
      check missing.isErr
      let output = waitFor pwd.get.waitForAsync(5.seconds)
      check getCurrentDir() == before
      check output.isOk and output.get == @[b]

    test "A command that is not found fails the start and leaves nothing":
      let before = zombieChildren()
      let r = startChild("moe-no-such-command", "", @[])
      check r.isErr and "No such file" in r.error
      check zombieChildren() == before

    test "A working directory that cannot be entered fails the start":
      let before = zombieChildren()
      let r = startChild("pwd", getTempDir() / "moe_test_no_such_dir", @[])
      check r.isErr and "No such file" in r.error
      check zombieChildren() == before

    test "A relative command is looked for in the working directory":
      # The child enters the directory before its exec, as `posix_spawnp`
      # does with a chdir action.
      let dir = getTempDir() / "moe_test_relative_command"
      createDir(dir)
      defer:
        removeDir(dir)
      writeFile(dir / "hello.sh", "#!/bin/sh\necho relative\n")
      setFilePermissions(dir / "hello.sh", {fpUserRead, fpUserWrite, fpUserExec})
      let output = waitFor start("./hello.sh", @[], dir).waitForAsync(5.seconds)
      check output.isOk and output.get == @["relative"]

    test "Standard input is /dev/null, not the terminal":
      let output =
        waitFor start("readlink", @["/proc/self/fd/0"]).waitForAsync(5.seconds)
      check output.isOk and output.get == @["/dev/null"]

    test "A descriptor of moe's without close-on-exec stays in moe":
      # `osproc` pipes (git, the clipboard) are not close-on-exec.
      var fds: array[2, cint]
      check posix.pipe(fds) == 0
      let high = fcntl(fds[0], F_DUPFD, 200)
      defer:
        discard posix.close(fds[0])
        discard posix.close(fds[1])
        discard posix.close(high)
      check high >= 200

      let output =
        waitFor start("sh", @["-c", "ls /proc/self/fd"]).waitForAsync(5.seconds)
      check output.isOk
      check $high notin output.get

    test "SIGPIPE is at its default in the child":
      # chronos ignores it in moe; a pipeline in a command would otherwise
      # report broken pipes instead of ending quietly.
      let output = waitFor start(
        "sh", @["-c", "yes | head -n 1 > /dev/null; echo done"]
      )
        .waitForAsync(5.seconds)
      check output.isOk and output.get == @["done"]

    test "A killed child reports 128 plus the signal":
      let bp = start("sleep", @["10"])
      bp.kill()
      check (waitFor bp.waitForExitAsync()) == some(128 + int(SIGKILL))
      waitFor bp.closeAsync()

    test "A stream that is not a pipe is nil":
      proc go(): Future[(bool, bool)] {.async.} =
        let child = startChild("true", "", @[]).get
        let streams = (child.stdinStream.isNil, child.stderrStream.isNil)
        await child.release()
        return streams

      check waitFor(go()) == (true, true)

    test "Two waits on one child both see its exit":
      proc go(): Future[(int, int)] {.async.} =
        let child = startChild("sh", "", @["-c", "sleep 0.2; exit 3"]).get
        let
          first = child.waitForExit()
          second = child.waitForExit()
        let codes = (await first, await second)
        await child.release()
        return codes

      check waitFor(go()) == (3, 3)

    test "Releasing a child that still runs stops and reaps it":
      # However a handle is let go, nothing is left running and no zombie
      # stays behind.
      proc go(): Future[ChildProcess] {.async.} =
        let child = startChild("sleep", "", @["30"]).get
        await child.release()
        return child

      let child = waitFor go()
      check child.fate == cfReaped
      check child.exitCode == some(128 + int(SIGKILL))
      check not dirExists("/proc/" & $child.pid)

    test "A wait alongside a release sees the end the release brought":
      proc go(): Future[int] {.async.} =
        let child = startChild("sleep", "", @["30"]).get
        let waiting = child.waitForExit()
        await sleepAsync(20.milliseconds)
        await child.release()
        return await waiting.wait(3.seconds)

      check waitFor(go()) == 128 + int(SIGKILL)

    test "A cancel reaches what the child started":
      # Every child leads a process group so that signals reach its children.
      let pidFile = getTempDir() / "moe_test_cancel_group"
      removeFile(pidFile)
      defer:
        removeFile(pidFile)
      let bp = start("sh", @["-c", "sleep 30 & echo $! > " & pidFile & "; wait"])
      let grandchild = pidWrittenTo(pidFile)

      bp.cancel()
      discard waitFor bp.waitForExitAsync()
      check gone(grandchild)
      waitFor bp.closeAsync()

    test "A timeout takes out what the command left in its group":
      # The command has exited and what it started holds the pipe. Unreaped,
      # its pid still names the group, so the kill still reaches that.
      let pidFile = getTempDir() / "moe_test_timeout_leftover"
      removeFile(pidFile)
      defer:
        removeFile(pidFile)
      let
        bp = start("sh", @["-c", "sleep 30 & echo $! > " & pidFile])
        leftover = pidWrittenTo(pidFile)
      # Asked meanwhile: that must not spend the pid.
      for _ in 0 ..< 200:
        if not bp.process.running():
          break
        sleep(10)
      check not bp.process.running()
      let r = waitFor bp.waitForAsync(200.milliseconds)
      check r.isErr and "Timed out" in r.error
      check gone(leftover)

    test "A timeout is bounded even when the exit is never announced":
      # As for a command in uninterruptible sleep, which outlives its SIGKILL:
      # the pidfd watches another process, so the wait for the exit never
      # returns within the grace. The command closes its output first, so the
      # run is waiting for the exit alone when the timeout comes.
      privateAccess(ChildProcess)
      proc go(): Future[(ProcessOutputResult, Duration, ChildFate)] {.async.} =
        let
          bp = start("sh", @["-c", "exec >&- 2>&-; exec sleep 30"])
          decoy = startChild("sleep", "", @["8"]).get
        discard posix.close(bp.process.pidfd)
        bp.process.pidfd = decoy.pidfd
        decoy.pidfd = -1
        let started = Moment.now()
        let r = await bp.waitForAsync(200.milliseconds)
        let took = Moment.now() - started
        await decoy.release()
        return (r, took, bp.process.fate)

      let (r, took, fate) = waitFor go()
      check r.isErr and "Timed out" in r.error
      # The timeout and the kill's grace, not the decoy's life.
      check took < 5.seconds
      check fate == cfReaped

    test "A child that has exited stays unreaped until it is released":
      proc go(): Future[(int, ChildFate, bool, ChildFate)] {.async.} =
        let child = startChild("sh", "", @["-c", "exit 7"]).get
        let code = await child.waitForExit()
        let
          before = child.fate
          zombie = isZombie(child.pid)
        await child.release()
        return (code, before, zombie, child.fate)

      check waitFor(go()) == (7, cfExited, true, cfReaped)

    test "A child is waited for by polling without its pidfd":
      # As on a kernel without pidfds, or once the dispatcher refused one.
      proc go(): Future[int] {.async.} =
        let child = startChild("sh", "", @["-c", "sleep 0.1; exit 5"]).get
        child.closePidfd()
        let code = await child.waitForExit().wait(5.seconds)
        await child.release()
        return code

      check waitFor(go()) == 5

    test "A cancelled release still reaps the child":
      proc go(): Future[ChildProcess] {.async.} =
        let child = startChild("sleep", "", @["30"]).get
        await child.release().cancelAndWait()
        return child

      let child = waitFor go()
      check child.fate == cfReaped
      check not dirExists("/proc/" & $child.pid)

    test "A child reaped behind the handle's back is not known, not exited":
      # Its pid may be somebody else's now: nothing may signal it, and how it
      # ended cannot be made up.
      let child = startChild("sh", "", @["-c", "exit 3"]).get
      var status: cint
      check posix.waitpid(Pid(child.pid), status, 0) == Pid(child.pid)
      check not child.running
      check child.fate == cfUnknown
      check child.exitCode.isNone
      expect AsyncProcessError:
        discard waitFor child.waitForExit()
      child.kill()
      waitFor child.release()
      check child.fate == cfUnknown

    test "A child left to be reaped later is reaped by the next start":
      # As `release` leaves one that outlived its kill; the next start or
      # release on any thread reaps it.
      let child = startChild("sh", "", @["-c", "sleep 0.1"]).get
      child.leaveToReaper()
      check child.fate == cfUnknown
      for _ in 0 ..< 200:
        if isZombie(child.pid):
          break
        sleep(10)
      check isZombie(child.pid)
      let next = startChild("true", "", @[]).get
      check not dirExists("/proc/" & $child.pid)
      waitFor next.release()
      waitFor child.release()

    test "A child that left its group is signalled by its pid as well":
      # It can join another group of the session; what it started stays in
      # the one it leads.
      let python = findExe("python3")
      if python.len == 0:
        skip()
      else:
        let pidFile = getTempDir() / "moe_test_left_group"
        removeFile(pidFile)
        defer:
          removeFile(pidFile)
        let bp = start(
          python,
          @[
            "-c",
            "import os, subprocess, sys, time\n" &
              "p = subprocess.Popen(['sleep', '10'])\n" &
              "os.setpgid(0, os.getpgid(os.getppid()))\n" &
              "open(sys.argv[1], 'w').write(str(p.pid))\n" & "time.sleep(10)",
            pidFile,
          ],
        )
        let leftover = pidWrittenTo(pidFile)
        bp.kill()
        check (waitFor bp.waitForExitAsync()) == some(128 + int(SIGKILL))
        check gone(leftover)
        waitFor bp.closeAsync()
