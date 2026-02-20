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

import std/[unittest, options, os, osproc]

import pkg/results

import ../src/moepkg/clipboard {.all.}
import ../src/moepkg/config

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

      let readResult = readFromClipboardSync(cbtWlClipboard)
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

      let readResult = readFromClipboardSync(cbtWlClipboard)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read unicode text with wl-clipboard":
    if not isWlClipboardAvailable():
      skip()
    else:
      let testText = "日本語テスト 🎉 emoji"
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtWlClipboard)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read empty string with wl-clipboard":
    if not isWlClipboardAvailable():
      skip()
    else:
      let testText = ""
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtWlClipboard)
      check readResult.isOk
      check readResult.get() == testText
