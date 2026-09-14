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

import std/[unittest, options, os, strutils]

import pkg/chronos

import ../src/moepkg/background_process {.all.}

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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
      return r.isErr

    check waitFor(runTest())

  test "Start command with working directory":
    proc runTest(): Future[tuple[success: bool, output: seq[string]]] {.async.} =
      let cmd = BackgroundProcessCommand(cmd: "pwd", args: @[], workingDir: "/tmp")

      let r = await startBackgroundProcess(cmd)
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

suite "BackgroundProcess - isRunning and isFinish":
  test "isRunning returns true for running process":
    proc runTest(): Future[tuple[running: bool, finish: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "sleep", args: @["1"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let running = bp.isRunning
        let finish = bp.isFinish
        bp.kill()
        await bp.closeAsync()
        return (running, finish)
      else:
        return (false, true)

    let r = waitFor runTest()
    check r.running == true
    check r.finish == false

  test "isFinish returns true for completed process":
    proc runTest(): Future[tuple[running: bool, finish: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["done"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        discard await bp.outputOf()
        let running = bp.isRunning
        let finish = bp.isFinish
        return (running, finish)
      else:
        return (true, false)

    let r = waitFor runTest()
    check r.running == false
    check r.finish == true

  test "isRunning returns false for nil process":
    let bp = BackgroundProcess(process: nil)
    check bp.isRunning == false
    check bp.isFinish == true

suite "BackgroundProcess - readAllOutput":
  test "Read single line output":
    proc runTest(): Future[seq[string]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["hello"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

suite "BackgroundProcess - waitForExitAsync":
  test "Wait for successful command":
    proc runTest(): Future[int] {.async.} =
      let cmd =
        BackgroundProcessCommand(cmd: "true", args: @[], workingDir: getCurrentDir())

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let output = await bp.outputOf()
        return (output, bp.process.isNil)
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

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let beforeNil = bp.process.isNil
        discard await bp.outputOf()
        let afterNil = bp.process.isNil
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

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let running = bp.isRunning
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

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let running = bp.isRunning
        bp.kill()
        await sleepAsync(100.milliseconds)
        await bp.closeAsync()
        return running
      else:
        return false

    let wasRunning = waitFor runTest()
    check wasRunning == true

  test "A reaped process is never signalled again":
    # Waiting for the child is what spends its pid: from that moment the
    # number can be somebody else's, and both the run and the editor holding
    # the job in `runningBackgroundProcesses` signal through the same `kill`.
    proc runTest(): Future[BackgroundProcess] {.async.} =
      let r = await startBackgroundProcess(
        BackgroundProcessCommand(
          cmd: "sh", args: @["-c", "exit 0"], workingDir: getCurrentDir()
        )
      )
      let bp = r.get
      discard await bp.waitForExitAsync()
      # The handle outlives the reap - it is released later, and a kill from
      # the editor can land anywhere in that window.
      doAssert not bp.process.isNil
      bp.kill()
      bp.cancel()
      await bp.closeAsync()
      return bp

    let bp = waitFor runTest()
    check bp.reaped
    check not bp.isRunning

  test "Asking whether a process is running is itself a reap":
    # `running` peeks with WNOHANG, so the question reaps the zombie it finds
    # and the pid is spent even though this run never waited for it.
    proc runTest(): Future[BackgroundProcess] {.async.} =
      let r = await startBackgroundProcess(
        BackgroundProcessCommand(
          cmd: "sh", args: @["-c", "exit 0"], workingDir: getCurrentDir()
        )
      )
      let bp = r.get
      await sleepAsync(200.milliseconds)
      doAssert not bp.isRunning
      return bp

    let bp = waitFor runTest()
    check bp.reaped
    waitFor bp.closeAsync()

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

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let beforeNil = bp.process.isNil
        await bp.closeAsync()
        let afterNil = bp.process.isNil
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

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        await bp.closeAsync()
        await bp.closeAsync() # Second close should be safe
        return bp.process.isNil
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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

        let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
      if r.isErr:
        return (ProcessOutputResult.err "start failed", false)
      let bp = r.get
      let waitResult = await bp.waitForAsync(200.milliseconds)
      return (waitResult, bp.process.isNil)

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

      let r = await startBackgroundProcess(cmd)
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

        let r = await startBackgroundProcess(cmd)
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

      let r = await startBackgroundProcess(cmd)
      if r.isErr:
        return ProcessOutputResult.err "start failed"
      return await r.get.waitForAsync(InfiniteDuration)

    let r = waitFor runTest()
    check r.isOk
    check r.get[0] == "slow"

suite "BackgroundProcess - timeoutFromSeconds":
  test "Positive seconds become a bounded duration":
    check timeoutFromSeconds(30) == 30.seconds

  test "Zero and negative mean no timeout":
    check timeoutFromSeconds(0) == InfiniteDuration
    check timeoutFromSeconds(-1) == InfiniteDuration

suite "BackgroundProcess - filterOutput":
  const Unbounded = 64 * 1024 * 1024

  proc startFilter(
      cmd: string, args: seq[string]
  ): Future[BackgroundProcess] {.async.} =
    let r = await startFilterProcess(
      BackgroundProcessCommand(cmd: cmd, args: args, workingDir: getTempDir())
    )
    doAssert r.isOk, r.error
    return r.get

  proc runFilter(
      cmd: string,
      args: seq[string],
      input: string,
      timeout = InfiniteDuration,
      limit = Unbounded,
  ): FilterProcessResult =
    proc go(): Future[FilterProcessResult] {.async.} =
      let bp = await startFilter(cmd, args)
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
      let bp = await startFilter("sh", @["-c", "sleep 0.5; : > " & marker])
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
      let bp = await startFilter(
        "sh", @["-c", "exec 0<&- 1>&- 2>&-; sleep 0.5; : > " & marker]
      )
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
      let bp = await startFilter("sh", @["-c", "sleep 5"])
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
    check bp.process.isNil
    check bp.isFinish
