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

import
  std/[unittest, options, os, osproc, strutils, streams, times, monotimes, tempfiles]

when defined(posix):
  import std/posix

import pkg/results

import ../src/moepkg/clipboard {.all.}
import ../src/moepkg/config
import ../src/moepkg/encoding

proc isProcessReaped*(p: Process, timeoutMs = 500): bool =
  ## Wait up to timeoutMs for p to be reaped, tolerating scheduler delay
  ## beyond ReapTimeoutMs=200. Returns true if peekExitCode != -1.
  let deadline = getMonoTime() + initDuration(milliseconds = timeoutMs)
  while getMonoTime() < deadline:
    try:
      if p.peekExitCode() != -1:
        return true
    except CatchableError:
      return true
    if not p.running():
      try:
        if p.peekExitCode() != -1:
          return true
      except CatchableError:
        return true
    sleep(5)
  try:
    return p.peekExitCode() != -1
  except CatchableError:
    return true

suite "clipboard: getClipboardCommand":
  test "xclip read command":
    let cmd = getClipboardCommand(cbtXclip, ClipboardOperation.read)
    check cmd.isSome
    check cmd.get() == @["xclip", "-selection", "clipboard", "-o"]

  test "xclip write command":
    let cmd = getClipboardCommand(cbtXclip, ClipboardOperation.write)
    check cmd.isSome
    check cmd.get() == @["xclip", "-selection", "clipboard", "-i"]

  test "xsel read command":
    let cmd = getClipboardCommand(cbtXsel, ClipboardOperation.read)
    check cmd.isSome
    check cmd.get() == @["xsel", "--clipboard", "--output"]

  test "xsel write command":
    let cmd = getClipboardCommand(cbtXsel, ClipboardOperation.write)
    check cmd.isSome
    check cmd.get() == @["xsel", "--clipboard", "--input"]

  test "wl-clipboard read command":
    let cmd = getClipboardCommand(cbtWlClipboard, ClipboardOperation.read)
    check cmd.isSome
    check cmd.get() == @["wl-paste", "-n"]

  test "wl-clipboard write command":
    let cmd = getClipboardCommand(cbtWlClipboard, ClipboardOperation.write)
    check cmd.isSome
    check cmd.get() == @["wl-copy"]

  test "win32yank read command":
    let cmd = getClipboardCommand(cbtWin32yank, ClipboardOperation.read)
    check cmd.isSome
    check cmd.get() == @["win32yank.exe", "-o", "--lf"]

  test "win32yank write command":
    let cmd = getClipboardCommand(cbtWin32yank, ClipboardOperation.write)
    check cmd.isSome
    check cmd.get() == @["win32yank.exe", "-i", "--crlf"]

  test "pbcopy read command":
    let cmd = getClipboardCommand(cbtPbcopy, ClipboardOperation.read)
    check cmd.isSome
    check cmd.get() == @["pbpaste"]

  test "pbcopy write command":
    let cmd = getClipboardCommand(cbtPbcopy, ClipboardOperation.write)
    check cmd.isSome
    check cmd.get() == @["pbcopy"]

proc isToolAvailable(cmd: string): bool =
  try:
    let (_, exitCode) = execCmdEx("which " & cmd)
    result = exitCode == 0
  except CatchableError:
    result = false

proc isXclipAvailable(): bool =
  existsEnv("DISPLAY") and isToolAvailable("xclip")

proc isXselAvailable(): bool =
  existsEnv("DISPLAY") and isToolAvailable("xsel")

proc isWlClipboardAvailable(): bool =
  existsEnv("WAYLAND_DISPLAY") and isToolAvailable("wl-copy")

proc readClipboardWithRetry(
    tool: ClipboardTool, expected: string, maxRetries: int = 10, delayMs: int = 100
): Result[string, string] =
  ## Retry reading from clipboard until the expected value is returned.
  ## Clipboard tools like xsel fork a background daemon to hold selection
  ## ownership, which may not be ready immediately after the write returns.
  for i in 0 ..< maxRetries:
    result = readFromClipboardSync(tool)
    if result.isOk and result.get() == expected:
      return
    sleep(delayMs)
  # Final attempt
  return readFromClipboardSync(tool)

suite "clipboard: readFromClipboardSync and writeToClipboardSync":
  test "write and read with xclip":
    if not isXclipAvailable():
      skip()
    else:
      let testText = "moe editor clipboard test - xclip"
      let writeResult = writeToClipboardSync(cbtXclip, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtXclip)
      check readResult.isOk
      check readResult.get() == testText

      # Kill xclip's background process that holds clipboard ownership
      discard execCmdEx("pkill xclip")
      sleep(100)

  test "write and read with xsel":
    if not isXselAvailable():
      skip()
    else:
      let testText = "moe editor clipboard test - xsel"
      let writeResult = writeToClipboardSync(cbtXsel, testText)
      check writeResult.isOk

      let readResult = readClipboardWithRetry(cbtXsel, testText)
      check readResult.isOk
      check readResult.get() == testText

      # Kill xsel's background process that holds clipboard ownership
      discard execCmdEx("pkill xsel")
      sleep(100)

  test "write and read with wl-clipboard":
    if not isWlClipboardAvailable():
      skip()
    else:
      let testText = "moe editor clipboard test - wl-clipboard"
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readClipboardWithRetry(cbtWlClipboard, testText)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read multiline text with xsel":
    if not isXselAvailable():
      skip()
    else:
      let testText = "line1\nline2\nline3"
      let writeResult = writeToClipboardSync(cbtXsel, testText)
      check writeResult.isOk

      let readResult = readClipboardWithRetry(cbtXsel, testText)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read unicode text with xsel":
    if not isXselAvailable():
      skip()
    else:
      let testText = "日本語テスト 🎉 emoji"
      let writeResult = writeToClipboardSync(cbtXsel, testText)
      check writeResult.isOk

      let readResult = readClipboardWithRetry(cbtXsel, testText)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read empty string with xsel":
    if not isXselAvailable():
      skip()
    else:
      let testText = ""
      let writeResult = writeToClipboardSync(cbtXsel, testText)
      check writeResult.isOk

      let readResult = readClipboardWithRetry(cbtXsel, testText)
      check readResult.isOk
      check readResult.get() == testText

      # Kill xsel's background process that holds clipboard ownership
      discard execCmdEx("pkill xsel")
      sleep(100)

  test "write and read multiline text with wl-clipboard":
    if not isWlClipboardAvailable():
      skip()
    else:
      let testText = "line1\nline2\nline3"
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readClipboardWithRetry(cbtWlClipboard, testText)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read unicode text with wl-clipboard":
    if not isWlClipboardAvailable():
      skip()
    else:
      let testText = "日本語テスト 🎉 emoji"
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readClipboardWithRetry(cbtWlClipboard, testText)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read empty string with wl-clipboard":
    if not isWlClipboardAvailable():
      skip()
    else:
      let testText = ""
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readClipboardWithRetry(cbtWlClipboard, testText)
      check readResult.isOk
      check readResult.get() == testText

suite "clipboard: error handling (fd/zombie leak regression)":
  test "readFromClipboardSync returns err when tool not found":
    let r = readFromClipboardSync(cbtWin32yank)
    check r.isErr

  test "writeToClipboardSync returns err when tool not found":
    let r = writeToClipboardSync(cbtWin32yank, "test")
    check r.isErr

  test "readFromPrimarySelectionSync returns err when tool not found":
    let r = readFromPrimarySelectionSync(cbtWin32yank)
    check r.isErr

  test "writeToPrimarySelectionSync returns err when tool not found":
    let r = writeToPrimarySelectionSync(cbtWin32yank, "test")
    check r.isErr

  test "process lifecycle with try/finally pattern (normal exit)":
    var process: Process = nil
    try:
      process = startProcess("true", options = {poUsePath})
      discard process.waitForExit()
    except CatchableError:
      discard
    finally:
      if not process.isNil:
        process.close()
    check true

  test "process lifecycle with readAll and waitForExit (normal exit)":
    var process: Process = nil
    try:
      process = startProcess("echo", args = @["hello"], options = {poUsePath})
      let output = process.outputStream.readAll()
      let exitCode = process.waitForExit()
      check output.len > 0
      check exitCode == 0
    except CatchableError:
      check false
    finally:
      if not process.isNil:
        process.close()

  test "readAllWithTimeout returns err for nil process":
    # The nil guard is platform-independent; run this on every platform.
    let r = readAllWithTimeout(nil, 500)
    check r.isErr
    check r.error ==
      "Timed out after 500 ms waiting for the clipboard tool: process is nil"

  when defined(posix):
    test "readAllWithTimeout returns err and kills a hung tool within the timeout":
      var process: Process = nil
      try:
        process = startProcess("sleep", args = @["30"], options = {poUsePath})
        let start = getMonoTime()
        let r = readAllWithTimeout(process, 500)
        let elapsed = (getMonoTime() - start).inMilliseconds
        check r.isErr
        check r.error == "Timed out after 500 ms with no output from the clipboard tool"
        # Lower bound relaxed for loaded CI (scheduler may delay poll/kill);
        # upper bound widened so a slow runner does not flake.
        check elapsed >= 250
        check elapsed < 4000
        # Verify the child was actually killed and reaped (not just reported as err).
        # Without kill+waitForExit the test would still pass the checks above
        # while leaving the sleep process alive, so we assert the process state.
        # Use retry to tolerate scheduler delay beyond ReapTimeoutMs=200.
        check isProcessReaped(process, 500)
        check not process.running()
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout discards data from a tool that hangs without EOF":
      var process: Process = nil
      try:
        # Prints, closes its own stdout/stderr, then hangs. No EOF is delivered,
        # so the buffered bytes cannot be shown to be the whole selection: a
        # tool that closed stdout while something it forked still holds the
        # write end looks exactly the same. Fail closed and kill the tool.
        process = startProcess(
          "sh",
          args = @["-c", "printf hello; exec 1>&- 2>&-; sleep 30"],
          options = {poUsePath},
        )
        let start = getMonoTime()
        let r = readAllWithTimeout(process, 500)
        let elapsed = (getMonoTime() - start).inMilliseconds
        check elapsed >= 250
        check elapsed < 4000
        check r.isErr
        check r.error == "Timed out after 500 ms; partial output was discarded (5 bytes)"
        check isProcessReaped(process, 500)
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          try:
            process.kill()
          except CatchableError:
            discard
          try:
            discard process.waitForExit()
          except CatchableError:
            discard
          process.close()

    test "readAllWithTimeout returns err on mid-stream hang (truncated data discarded)":
      var process: Process = nil
      try:
        # Outputs partial data then hangs without closing stdout – the poll
        # loop timeout must discard truncated data and report err, not ok.
        process = startProcess(
          "sh", args = @["-c", "printf partial; sleep 30"], options = {poUsePath}
        )
        let start = getMonoTime()
        let r = readAllWithTimeout(process, 500)
        let elapsed = (getMonoTime() - start).inMilliseconds
        check elapsed >= 250
        check elapsed < 4000
        check r.isErr
        # The truncated data is discarded, but the error must not claim the tool
        # produced nothing.
        check r.error == "Timed out after 500 ms; partial output was discarded (7 bytes)"
        check isProcessReaped(process, 500)
        check not process.running()
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          try:
            process.kill()
          except CatchableError:
            discard
          try:
            discard process.waitForExit()
          except CatchableError:
            discard
          process.close()

    test "readAllWithTimeout returns only stdout when the tool also writes stderr":
      var process: Process = nil
      try:
        process = startProcess(
          "sh",
          args = @["-c", "printf 'noise' >&2; printf 'clipboard text'"],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 1000)
        check r.isOk
        check r.get() == "clipboard text"
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          try:
            process.kill()
          except CatchableError:
            discard
          try:
            discard process.waitForExit()
          except CatchableError:
            discard
          process.close()

    test "readAllWithTimeout never returns a hung tool's stderr as content":
      var process: Process = nil
      try:
        # A tool that only prints a diagnostic and then hangs. stderr is on its
        # own pipe, so the diagnostic must not come back as clipboard content.
        process = startProcess(
          "sh",
          args = @[
            "-c", "printf 'xclip: Error: cannot open display' >&2; exec 1>&-; sleep 30"
          ],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 500)
        check r.isErr
        check r.error == "Timed out after 500 ms with no output from the clipboard tool"
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          try:
            process.kill()
          except CatchableError:
            discard
          try:
            discard process.waitForExit()
          except CatchableError:
            discard
          process.close()

    test "readAllWithTimeout names the discarded bytes when output is partial":
      var process: Process = nil
      try:
        # The direct child exits while a forked grandchild keeps the write end
        # and may still produce output.
        process = startProcess(
          "sh",
          args = @["-c", "printf partial; sleep 3 & exit 0"],
          options = {poUsePath},
        )
        let start = getMonoTime()
        let r = readAllWithTimeout(process, 500)
        let elapsed = (getMonoTime() - start).inMilliseconds
        # Ensure the timeout bound is respected even though the direct child
        # exited; grandchild holding the pipe must not extend the wait.
        check elapsed >= 250
        check elapsed < 4000
        check r.isErr
        # The truncated data is still discarded, but the error must not claim
        # the tool produced nothing.
        check r.error == "Timed out after 500 ms; partial output was discarded (7 bytes)"
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          try:
            process.kill()
          except CatchableError:
            discard
          try:
            discard process.waitForExit()
          except CatchableError:
            discard
          process.close()

    test "readAllWithTimeout reads normal output":
      var process: Process = nil
      try:
        process = startProcess("echo", args = @["hello"], options = {poUsePath})
        let r = readAllWithTimeout(process, 1000)
        check r.isOk
        check r.get() == "hello\n"
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout accumulates multi-chunk output intact":
      var process: Process = nil
      try:
        # Forces many 4096-byte chunk reads; result must be byte-exact.
        process = startProcess(
          "sh",
          args = @["-c", "head -c 100000 /dev/zero | tr '\\0' 'a'"],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 10_000)
        check r.isOk
        check r.get() == 'a'.repeat(100_000)
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout enforces maxReadSize across chunks":
      var process: Process = nil
      try:
        # Crosses the limit mid-stream; the tool must be killed.
        process = startProcess(
          "sh",
          args = @["-c", "head -c 20000 /dev/zero | tr '\\0' 'b'"],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 5000, maxReadSize = 4096)
        check r.isErr
        check r.error == "The clipboard tool output exceeded the 4096 byte limit"
        check not process.running()
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          try:
            process.kill()
          except CatchableError:
            discard
          try:
            discard process.waitForExit()
          except CatchableError:
            discard
          process.close()

    test "readAllWithTimeout enforces maxReadSize and kills the tool":
      var process: Process = nil
      try:
        process = startProcess(
          "sh", args = @["-c", "printf '0123456789ABCDEF'"], options = {poUsePath}
        )
        let r = readAllWithTimeout(process, 1000, maxReadSize = 10)
        check r.isErr
        check r.error == "The clipboard tool output exceeded the 10 byte limit"
        check isProcessReaped(process, 500)
        check not process.running()
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          try:
            process.kill()
          except CatchableError:
            discard
          try:
            discard process.waitForExit()
          except CatchableError:
            discard
          process.close()

    test "readAllWithTimeout reports non-zero exit code with output":
      var process: Process = nil
      try:
        process =
          startProcess("sh", args = @["-c", "printf x; exit 3"], options = {poUsePath})
        let r = readAllWithTimeout(process, 1000)
        check r.isErr
        check r.error == "The clipboard tool exited with code 3"
        check isProcessReaped(process, 500)
        check not process.running()
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout treats a non-zero exit with no output as empty":
      # xclip / wl-paste exit non-zero for a merely empty selection, which must
      # not reach the user as a paste failure. Their diagnostic is what says so.
      var process: Process = nil
      try:
        process = startProcess(
          "sh",
          args = @["-c", "printf 'Error: target STRING not available\\n' >&2; exit 1"],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 1000)
        check r.isOk
        check r.get() == ""
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout reports a non-zero exit the tool did not call empty":
      # An unreachable display is not an empty selection: reporting it as one
      # turns every broken paste into a silent no-op.
      var process: Process = nil
      try:
        process = startProcess(
          "sh",
          args = @["-c", "printf 'Cannot open display\\n' >&2; exit 1"],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 1000)
        check r.isErr
        check r.error.contains("exited with code 1")
        check r.error.contains("Cannot open display")
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout reports a silent non-zero exit as a failure":
      var process: Process = nil
      try:
        process = startProcess("sh", args = @["-c", "exit 1"], options = {poUsePath})
        let r = readAllWithTimeout(process, 1000)
        check r.isErr
        check r.error == "The clipboard tool exited with code 1"
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout drains a tool that floods stderr":
      # stderr is a pipe of its own: leaving it unread blocks the tool once the
      # pipe fills, and its stdout never arrives.
      var process: Process = nil
      try:
        process = startProcess(
          "sh",
          args = @[
            "-c",
            "i=0; while [ $i -lt 4000 ]; do printf 'diagnostic line\\n' >&2; " &
              "i=$((i+1)); done; printf clip",
          ],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 2000)
        check r.isOk
        check r.get() == "clip"
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout finds the empty-selection marker after a flood":
      # The marker is the tool's last word. A verbose tool pushes it out of the
      # head of the captured diagnostics, and losing it turns an empty
      # clipboard into a reported failure.
      var process: Process = nil
      try:
        process = startProcess(
          "sh",
          args = @[
            "-c",
            "yes warning | head -c 20000 >&2; " &
              "printf 'Nothing is copied\\n' >&2; exit 1",
          ],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 2000)
        check r.isOk
        check r.get() == ""
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout bounds a tool that never stops writing stderr":
      # The stderr drain runs at the top of every read iteration. A writer that
      # keeps the pipe full never yields EOF or EAGAIN, so an unbounded drain
      # would hold the loop before it ever reaches its own deadline check.
      var process: Process = nil
      try:
        let start = getMonoTime()
        process =
          startProcess("sh", args = @["-c", "yes noise >&2"], options = {poUsePath})
        let r = readAllWithTimeout(process, 1000, maxTotalMs = 300)
        let elapsed = (getMonoTime() - start).inMilliseconds
        check r.isErr
        # Lower bound relaxed (CI may schedule slowly); upper bound widened.
        check elapsed >= 200
        check elapsed < 4000
        check isProcessReaped(process, 500)
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout keeps reading while the tool makes progress":
      # Six chunks ~150ms apart: a total-time budget matching the idle timeout
      # would kill the ~900ms transfer, an idle one (reset on progress) must
      # not. Idle 800ms vs 150ms interval gives ~650ms margin so a loaded CI
      # cannot push one gap past it; keep margin > 4× the sleep interval.
      var process: Process = nil
      try:
        process = startProcess(
          "sh",
          args = @["-c", "for i in 1 2 3 4 5 6; do printf abc; sleep 0.15; done"],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 800)
        check r.isOk
        check r.get() == "abc".repeat(6)
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout bounds a trickling tool by maxTotalMs":
      var process: Process = nil
      try:
        let start = getMonoTime()
        process = startProcess(
          "sh",
          args = @["-c", "while true; do printf a; sleep 0.05; done"],
          options = {poUsePath},
        )
        let r = readAllWithTimeout(process, 1000, maxTotalMs = 300)
        let elapsed = (getMonoTime() - start).inMilliseconds
        check r.isErr
        check elapsed >= 200
        check elapsed < 4000
        check isProcessReaped(process, 500)
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout returns ok for empty output":
      var process: Process = nil
      try:
        process = startProcess("sh", args = @["-c", "printf ''"], options = {poUsePath})
        let r = readAllWithTimeout(process, 1000)
        check r.isOk
        check r.get() == ""
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout sanitizes invalid UTF-8":
      var process: Process = nil
      try:
        process = startProcess(
          "sh", args = @["-c", "printf '\\377\\376'"], options = {poUsePath}
        )
        let r = readAllWithTimeout(process, 1000)
        check r.isOk
        # 0xFF 0xFE are invalid UTF-8, each replaced by U+FFFD (EF BF BD)
        check r.get() == "\xEF\xBF\xBD\xEF\xBF\xBD"
        check r.get().len == 6
      except CatchableError:
        check false
      finally:
        if not process.isNil:
          process.close()

    test "readAllWithTimeout respects maxReadSize boundary":
      var p1: Process = nil
      var p2: Process = nil
      try:
        p1 = startProcess(
          "sh", args = @["-c", "printf '0123456789'"], options = {poUsePath}
        )
        let r1 = readAllWithTimeout(p1, 1000, maxReadSize = 10)
        check r1.isOk
        check r1.get() == "0123456789"
        check r1.get().len == 10
      except CatchableError:
        check false
      finally:
        if not p1.isNil:
          try:
            p1.kill()
          except CatchableError:
            discard
          try:
            discard p1.waitForExit()
          except CatchableError:
            discard
          p1.close()
      try:
        p2 = startProcess(
          "sh", args = @["-c", "printf '0123456789A'"], options = {poUsePath}
        )
        let r2 = readAllWithTimeout(p2, 1000, maxReadSize = 10)
        check r2.isErr
        check r2.error == "The clipboard tool output exceeded the 10 byte limit"
        check isProcessReaped(p2, 500)
      except CatchableError:
        check false
      finally:
        if not p2.isNil:
          try:
            p2.kill()
          except CatchableError:
            discard
          try:
            discard p2.waitForExit()
          except CatchableError:
            discard
          p2.close()

suite "clipboard: reap and diagnostics contracts":
  when defined(posix):
    test "cleanupClipboardProcess leaves the caller's descriptors open":
      # Every caller closes the Process in its own `finally`, so a close here
      # would shut the same descriptors twice and hand them to whatever opens
      # a file next (the logger, an LSP pipe).
      var p: Process = nil
      try:
        p = startProcess("sleep", args = @["30"], options = {poUsePath})
        let outFd = p.outputHandle().cint
        let errFd = p.errorHandle().cint
        check cleanupClipboardProcess(p)
        check fcntl(outFd, F_GETFD) != -1
        check fcntl(errFd, F_GETFD) != -1
      except CatchableError:
        check false
      finally:
        if not p.isNil:
          p.close()

  test "a failure after an empty-selection marker is not an empty selection":
    var d = ToolDiagnostics()
    d.add("no selection\n")
    d.add("Error: Can't open display: :0\n")
    check not d.looksLikeEmptySelection
    let r = emptySelection(1, d)
    check r.isErr
    check r.error.contains("exited with code 1")

  test "an empty-selection marker as the final message is an empty selection":
    var d = ToolDiagnostics()
    d.add("xclip: Error: target STRING not available\n")
    check d.looksLikeEmptySelection
    let r = emptySelection(1, d)
    check r.isOk
    check r.get == ""

suite "clipboard: waitForExitBounded coverage":
  test "waitForExitBounded returns 0 for quick exit":
    var p: Process = nil
    try:
      p = startProcess("true", options = {poUsePath})
      let code = waitForExitBounded(p, 1000)
      check code == 0
      check not p.running()
    except CatchableError:
      check false
    finally:
      if not p.isNil:
        p.close()

  test "waitForExitBounded returns -1 and kills hung tool":
    var p: Process = nil
    try:
      p = startProcess("sleep", args = @["30"], options = {poUsePath})
      let start = getMonoTime()
      let code = waitForExitBounded(p, 300)
      let elapsed = (getMonoTime() - start).inMilliseconds
      check code == -1
      check elapsed >= 200
      check elapsed < 4000
      check isProcessReaped(p, 500)
      check not p.running()
    except CatchableError:
      check false
    finally:
      if not p.isNil:
        p.close()

  test "waitForExitBounded returns -2 for nil process":
    check waitForExitBounded(nil, 100) == -2

  test "waitForExitBounded returns non-zero for failing tool":
    var p: Process = nil
    try:
      p = startProcess("sh", args = @["-c", "exit 7"], options = {poUsePath})
      let code = waitForExitBounded(p, 1000)
      check code == 7
    except CatchableError:
      check false
    finally:
      if not p.isNil:
        p.close()

  test "dataDespiteDeadline rejects data from a tool on its way to a non-zero exit":
    # The tool closed its stdout but has not exited yet, so there is no code to
    # peek. "Still running" must not be read as "did not fail": the buffer is a
    # fragment of a failed read, not the clipboard.
    var p: Process = nil
    try:
      p =
        startProcess("sh", args = @["-c", "sleep 0.05; exit 1"], options = {poUsePath})
      let r = dataDespiteDeadline(p, "partial", "test")
      check r.isErr
      check r.error == "The clipboard tool exited with code 1"
    except CatchableError:
      check false
    finally:
      if not p.isNil:
        p.close()

  test "dataDespiteDeadline rejects data when still running after grace":
    var p: Process = nil
    try:
      p = startProcess("sleep", args = @["30"], options = {poUsePath})
      let r = dataDespiteDeadline(p, "clip", "test", knownExitCode = -1)
      check r.isErr
      check r.error == "Failed to wait for the clipboard tool"
      check isProcessReaped(p, 500)
    except CatchableError:
      check false
    finally:
      if not p.isNil:
        p.close()

  test "wlCopyExitedEarly returns some(0) for early exit 0":
    var p: Process = nil
    try:
      p = startProcess("sh", args = @["-c", "exit 0"], options = {poUsePath})
      let r = p.wlCopyExitedEarly()
      check r.isSome
      check r.get() == 0
    except CatchableError:
      check false
    finally:
      if not p.isNil:
        p.close()

  test "wlCopyExitedEarly returns some(non-zero) for early failure":
    var p: Process = nil
    try:
      p = startProcess("sh", args = @["-c", "exit 3"], options = {poUsePath})
      let r = p.wlCopyExitedEarly()
      check r.isSome
      check r.get() == 3
    except CatchableError:
      check false
    finally:
      if not p.isNil:
        p.close()

  test "wlCopyExitedEarly returns none for hanging process":
    var p: Process = nil
    try:
      p = startProcess("sleep", args = @["5"], options = {poUsePath})
      let r = p.wlCopyExitedEarly()
      check r.isNone
      check p.running()
    except CatchableError:
      check false
    finally:
      if not p.isNil:
        try:
          p.kill()
        except CatchableError:
          discard
        try:
          discard p.waitForExit()
        except CatchableError:
          discard
        p.close()

suite "clipboard: public API integration (covers helpers via public path)":
  # These tests exercise the public read/write entry points that delegate to the
  # helpers above. If the helpers were bypassed the suite would fail even though
  # helper-only unit tests still pass (addresses Medium #3: copy-test regression).
  when defined(posix):
    test "readFromClipboardSync via public API times out on hung tool":
      let fakeDir = createTempDir("moe-clip-public-", "")
      let origPath = getEnv("PATH")
      let fakeTool = fakeDir / "xclip"
      writeFile(fakeTool, "#!/bin/sh\nsleep 10\n")
      setFilePermissions(fakeTool, {fpUserRead, fpUserWrite, fpUserExec})
      putEnv("PATH", fakeDir & ":" & origPath)
      try:
        let start = getMonoTime()
        let r = readFromClipboardSync(cbtXclip)
        let elapsed = (getMonoTime() - start).inMilliseconds
        check r.isErr
        check r.error.contains("timed out") or r.error.contains("Timed out")
        # Bounded by ReadTimeoutMs, not by the tool's own sleep.
        check elapsed >= ReadTimeoutMs div 2
        check elapsed < ReadTimeoutMs + 3_000
      finally:
        putEnv("PATH", origPath)
        removeDir(fakeDir)

    test "writeToClipboardSync via public API reports failure on broken tool":
      let fakeDir = createTempDir("moe-clip-public-w-", "")
      let origPath = getEnv("PATH")
      let fakeTool = fakeDir / "xclip"
      writeFile(fakeTool, "#!/bin/sh\nexit 1\n")
      setFilePermissions(fakeTool, {fpUserRead, fpUserWrite, fpUserExec})
      putEnv("PATH", fakeDir & ":" & origPath)
      try:
        let r = writeToClipboardSync(cbtXclip, "hello")
        check r.isErr
        check r.error.contains("exit code 1") or r.error.contains("Failed")
      finally:
        putEnv("PATH", origPath)
        removeDir(fakeDir)

    test "ReadTimeoutMs is 500ms (TUI stall bound)":
      # Fixed-value guard: the 2000→500 shortening is intentional (TUI stalls
      # synchronously). If the constant drifts, the tautological
      # `elapsed < ReadTimeoutMs+3000` checks would still pass.
      check ReadTimeoutMs == 500

suite "clipboard: fcntl/poll error path coverage (regression for Medium)":
  when defined(posix):
    test "writeAllBounded returns err for nil process":
      let deadline = getMonoTime() + initDuration(milliseconds = 500)
      let r = writeAllBounded(nil, "hello", deadline)
      check r.isErr
      check not r.error.timedOut
      check r.error.msg.contains("process is nil")

    test "writeAllBounded returns err for closed fd (fcntl/poll branch)":
      var p: Process = nil
      var fd = -1
      var saved = -1
      try:
        p = startProcess("sleep", args = @["30"], options = {poUsePath})
        # Close the write end to make fcntl/poll fail with EBADF / POLLNVAL.
        # `p` still owns the number, so keep a copy and restore in finally:
        # otherwise an exception before restore would leak a recycled fd number
        # and the next test could close an unrelated descriptor.
        fd = p.inputHandle()
        if fd >= 0:
          saved = posix.dup(fd.cint)
          discard posix.close(fd.cint)
        let deadline = getMonoTime() + initDuration(milliseconds = 500)
        let r = writeAllBounded(p, "hello", deadline)
        check r.isErr
        # Should be one of the fcntl/poll error messages, all contain "Failed to"
        check not r.error.timedOut
        check r.error.msg.contains("Failed to")
        # Strict: must be reaped and not running; OR would hide a zombie leak.
        check isProcessReaped(p, 500)
        check not p.running()
      except CatchableError:
        check false
      finally:
        # Restore fd before p.close() so the process handle is not left dangling
        # with a recycled number, even if the check above threw.
        if saved >= 0 and fd >= 0:
          discard posix.dup2(saved.cint, fd.cint)
          discard posix.close(saved.cint)
        if not p.isNil:
          try:
            p.kill()
          except CatchableError:
            discard
          try:
            discard p.waitForExit()
          except CatchableError:
            discard
          p.close()

    test "readAllWithTimeout returns err for closed fd (poll branch)":
      var p: Process = nil
      var fd = -1
      var saved = -1
      try:
        p = startProcess("sleep", args = @["30"], options = {poUsePath})
        # As above: `p` still owns this number, so restore in finally.
        fd = p.outputHandle()
        if fd >= 0:
          saved = posix.dup(fd.cint)
          discard posix.close(fd.cint)
        let r = readAllWithTimeout(p, 500)
        check r.isErr
        check r.error.contains("Failed to")
        check isProcessReaped(p, 500)
        check not p.running()
      except CatchableError:
        check false
      finally:
        if saved >= 0 and fd >= 0:
          discard posix.dup2(saved.cint, fd.cint)
          discard posix.close(saved.cint)
        if not p.isNil:
          try:
            p.kill()
          except CatchableError:
            discard
          try:
            discard p.waitForExit()
          except CatchableError:
            discard
          p.close()

    test "writeAllBounded handles empty text without fd use":
      var p: Process = nil
      try:
        p = startProcess("cat", options = {poUsePath})
        let deadline = getMonoTime() + initDuration(milliseconds = 500)
        let r = writeAllBounded(p, "", deadline)
        check r.isOk
      except CatchableError:
        check false
      finally:
        if not p.isNil:
          try:
            p.kill()
          except CatchableError:
            discard
          try:
            discard p.waitForExit()
          except CatchableError:
            discard
          p.close()

    test "writeAllBounded times out when tool does not drain stdin":
      var p: Process = nil
      try:
        # `sleep` never reads stdin, so the pipe fills (~64KiB) and POLLOUT stops.
        p = startProcess("sleep", args = @["30"], options = {poUsePath})
        let deadline = getMonoTime() + initDuration(milliseconds = 200)
        let largeText = 'a'.repeat(512 * 1024)
        let start = getMonoTime()
        let r = writeAllBounded(p, largeText, deadline)
        let elapsed = (getMonoTime() - start).inMilliseconds
        check r.isErr
        check r.error.timedOut
        check elapsed >= 100
        check elapsed < 4000
        check isProcessReaped(p, 500)
        check not p.running()
      except CatchableError:
        check false
      finally:
        if not p.isNil:
          try:
            p.kill()
          except CatchableError:
            discard
          try:
            discard p.waitForExit()
          except CatchableError:
            discard
          p.close()

suite "clipboard: empty selection, stderr on writes, and group kill":
  when defined(posix):
    proc installScript(dir, name, body: string): string =
      result = dir / name
      writeFile(result, "#!/bin/sh\n" & body)
      setFilePermissions(result, {fpUserRead, fpUserWrite, fpUserExec})

    proc closeProcess(p: Process) =
      if p.isNil:
        return
      try:
        p.kill()
      except CatchableError:
        discard
      try:
        discard p.waitForExit()
      except CatchableError:
        discard
      p.close()

    test "a tool that reported an empty selection is not a timeout":
      # The tool says nothing is copied and then keeps running. Waiting for its
      # exit code would only turn an empty clipboard into a paste failure.
      let dir = createTempDir("moe-clipboard-empty-", "")
      var p: Process = nil
      try:
        let tool =
          installScript(dir, "emptyslow", "echo 'Nothing is copied' >&2\nsleep 5\n")
        p = startProcess(tool, options = {})
        let r = readAllWithTimeout(p, 150)
        check r.isOk
        check r.get() == ""
      finally:
        closeProcess(p)
        removeDir(dir)

    test "a silent tool that outlives the timeout is still a timeout":
      # Without an empty-selection marker there is nothing to distinguish a hung
      # tool from an empty one, so the bound must still be reported as an error.
      let dir = createTempDir("moe-clipboard-silent-", "")
      var p: Process = nil
      try:
        let tool = installScript(dir, "silent", "sleep 5\n")
        p = startProcess(tool, options = {})
        let r = readAllWithTimeout(p, 150)
        check r.isErr
        check r.error.contains("Timed out")
      finally:
        closeProcess(p)
        removeDir(dir)

    test "a write to a tool that floods stderr is not stalled by the full pipe":
      # The tool fills its stderr pipe before reading stdin. Without draining
      # stderr it never reaches `cat`, our stdin pipe fills too, and the write
      # blocks until the timeout kills it.
      let dir = createTempDir("moe-clipboard-flood-", "")
      var p: Process = nil
      try:
        let tool = installScript(
          dir, "floodwrite",
          "yes 'noise from the clipboard tool' | head -c 200000 >&2\ncat >/dev/null\n",
        )
        p = startProcess(tool, options = {})
        var diag = ToolDiagnostics()
        let errFd = p.diagnosticsFd()
        let deadline = getMonoTime() + initDuration(milliseconds = 5000)
        let r = writeAllBounded(p, 'a'.repeat(256 * 1024), deadline, errFd, diag)
        check r.isOk
        # Draining is what unblocked the write; the captured text proves it ran.
        check diag.finalDiagnostic.len > 0
      finally:
        closeProcess(p)
        removeDir(dir)

    test "a write to a tool that prints after reading stdin is not a timeout":
      # The tool takes the whole input first and only then floods stderr. The
      # exit wait has to keep draining that pipe: a tool blocked writing
      # diagnostics never exits, and the completed copy is reported as a
      # timeout and killed.
      let dir = createTempDir("moe-clipboard-latediag-", "")
      let origPath = getEnv("PATH")
      try:
        discard installScript(
          dir, "xclip",
          "cat >/dev/null\nyes 'noise from the clipboard tool' | head -c 200000 >&2\n",
        )
        putEnv("PATH", dir & ":" & origPath)
        let r = writeToClipboardSync(cbtXclip, "text", 2000)
        check r.isOk
        check r.get()
      finally:
        putEnv("PATH", origPath)
        removeDir(dir)

    test "a write to a tool that never reads stdin names the stalled write":
      # The tool hangs without draining stdin, so the input never landed. That
      # is not the same failure as a tool that took the input and would not
      # exit, and reporting it as one hides that nothing was copied.
      let dir = createTempDir("moe-clipboard-stalled-", "")
      let origPath = getEnv("PATH")
      try:
        discard installScript(dir, "xclip", "sleep 10\n")
        putEnv("PATH", dir & ":" & origPath)
        let r = writeToClipboardSync(cbtXclip, 'a'.repeat(256 * 1024), 300)
        check r.isErr
        check r.error.contains("Timed out sending the text")
        check not r.error.contains("did not exit")
      finally:
        putEnv("PATH", origPath)
        removeDir(dir)

    test "a read whose child was reaped elsewhere keeps the data":
      # Something else in the process reaped the child, so its exit status is
      # gone. The clipboard text was read to EOF and is complete: a missing
      # status is not evidence that the read failed.
      let dir = createTempDir("moe-clipboard-reaped-", "")
      var p: Process = nil
      try:
        let tool = installScript(dir, "quick", "printf clip\n")
        p = startProcess(tool, options = ClipboardProcessOptions)
        # Reap it here, before the read path can, to lose the status.
        var status: cint
        var waited = 0
        while waited < 2000 and waitpid(Pid(p.processID), status, WNOHANG) == 0:
          sleep(10)
          waited += 10
        let r = readAllWithTimeout(p, 2000)
        check r.isOk
        check r.get() == "clip"
      finally:
        closeProcess(p)
        removeDir(dir)

    test "processGone keeps the exit status queryable after it reports gone":
      # `processGone` must not reap behind `Process`'s back: doing so leaves
      # `exitFlag` false, so every later query loses the status for good and a
      # failed tool reads as a successful one.
      let dir = createTempDir("moe-clipboard-gone-", "")
      var p: Process = nil
      try:
        let tool = installScript(dir, "failing", "exit 3\n")
        p = startProcess(tool, options = ClipboardProcessOptions)
        var first = ExitUnknown
        var waited = 0
        while waited < 2000 and not processGone(p, first):
          sleep(10)
          waited += 10
        check first == 3
        # The status survives a query that throws its own copy away.
        check processGone(p)
        var second = ExitUnknown
        check processGone(p, second)
        check second == 3
        check p.peekExitCode() == 3
        check not p.running()
      finally:
        closeProcess(p)
        removeDir(dir)

    test "a read is not completed by a grandchild that has yet to write":
      # The tool closes its own stdout while something it forked still holds
      # the write end and more output on the way. No EOF arrives, so the
      # buffered prefix must not be pasted as if it were the whole selection.
      let dir = createTempDir("moe-clipboard-grandchild-", "")
      var p: Process = nil
      try:
        let tool = installScript(
          dir, "forking", "printf part\n(sleep 5; printf rest) &\nexec 1>&-\nsleep 30\n"
        )
        p = startProcess(tool, options = ClipboardProcessOptions)
        let r = readAllWithTimeout(p, 500)
        check r.isErr
        check r.error.contains("partial output was discarded")
      finally:
        closeProcess(p)
        removeDir(dir)

    test "a failed write reports what the tool printed":
      let dir = createTempDir("moe-clipboard-writeerr-", "")
      let origPath = getEnv("PATH")
      try:
        discard installScript(
          dir, "xclip", "echo \"Error: Can't open display: :0\" >&2\nexit 1\n"
        )
        putEnv("PATH", dir & ":" & origPath)
        let r = writeToClipboardSync(cbtXclip, "text", 2000)
        check r.isErr
        check r.error.contains("exit code 1")
        check r.error.contains("Can't open display")
      finally:
        putEnv("PATH", origPath)
        removeDir(dir)

    test "a long non-ASCII tool message is bounded and stays valid UTF-8":
      # Diagnostics are captured and truncated at byte offsets, so a localized
      # message gets cut mid-rune. The invalid bytes would otherwise reach the
      # status line and corrupt the renderer's width accounting.
      let dir = createTempDir("moe-clipboard-diag-", "")
      var p: Process = nil
      try:
        let tool = installScript(
          dir,
          "noisy",
          "i=0\nwhile [ $i -lt 100 ]; do printf %s " &
            "'ディスプレイを開けません' >&2; i=$((i+1)); done\nexit 1\n",
        )
        p = startProcess(tool, options = {})
        let r = readAllWithTimeout(p, 2000)
        check r.isErr
        # Repairing a partial rune is idempotent only if none is left.
        check sanitizeInvalidUtf8(r.error) == r.error
        check r.error.len < 400
        check r.error.contains("...")
      finally:
        closeProcess(p)
        removeDir(dir)

    test "the timeout kills what the tool forked, not only the tool":
      # A tool that forks leaves a grandchild holding the write end of stdout,
      # so killing the direct child alone delivers no EOF and leaks a process.
      let dir = createTempDir("moe-clipboard-group-", "")
      let pidFile = dir / "grandchild.pid"
      var p: Process = nil
      try:
        let tool = installScript(
          dir, "forking", "sleep 30 &\necho $! > \"" & pidFile & "\"\nsleep 30\n"
        )
        p = startProcess(tool, options = ClipboardProcessOptions)
        let r = readAllWithTimeout(p, 200)
        check r.isErr
        var grandchild = 0
        var tries = 0
        while tries < 50 and grandchild == 0:
          if fileExists(pidFile):
            let raw = readFile(pidFile).strip()
            if raw.len > 0:
              grandchild = raw.parseInt
          if grandchild == 0:
            sleep(10)
          inc tries
        check grandchild > 0
        var gone = false
        tries = 0
        while tries < 100:
          if posix.kill(Pid(grandchild), 0) != 0:
            gone = true
            break
          sleep(10)
          inc tries
        check gone
      finally:
        closeProcess(p)
        removeDir(dir)
