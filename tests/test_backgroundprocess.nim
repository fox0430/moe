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

import std/[unittest, os, strutils]

import pkg/chronos

import ../src/moepkg/background_process {.all.}

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
        let output = await bp.waitForAsync()
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
        discard await bp.waitForAsync()
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
        return exitCode
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
        return exitCode
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
        return exitCode
      else:
        return -999

    let exitCode = waitFor runTest()
    check exitCode == 42

  test "waitForExitAsync with nil process":
    proc runTest(): Future[int] {.async.} =
      let bp = BackgroundProcess(process: nil)
      return await bp.waitForExitAsync()

    let exitCode = waitFor runTest()
    check exitCode == -1

suite "BackgroundProcess - waitForAsync":
  test "Wait for command and get output":
    proc runTest(): Future[tuple[output: seq[string], processIsNil: bool]] {.async.} =
      let cmd = BackgroundProcessCommand(
        cmd: "echo", args: @["test output"], workingDir: getCurrentDir()
      )

      let r = await startBackgroundProcess(cmd)
      if r.isOk:
        let bp = r.get
        let output = await bp.waitForAsync()
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
        discard await bp.waitForAsync()
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
        return await bp.waitForAsync()
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
        return await bp.waitForAsync()
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
        return await bp.waitForAsync()
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
        return await bp.waitForAsync()
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
        return await bp.waitForAsync()
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
          let output = await bp.waitForAsync()
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
