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

import std/[unittest, options, osproc, envvars]

import pkg/results

import ../src/moepkg/clipboard {.all.}
import ../src/moepkg/config

proc isSkipTest(): bool =
  ## Skip test unless NOT_SKIP_TESTS=y is set
  getEnv("NOT_SKIP_TESTS") != "y"

suite "clipboard: getClipboardCommand":
  test "xclip read command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtXclip, ClipboardOperation.read)
      check cmd.isSome
      check cmd.get() == @["xclip", "-selection", "clipboard", "-o"]

  test "xclip write command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtXclip, ClipboardOperation.write)
      check cmd.isSome
      check cmd.get() == @["xclip", "-selection", "clipboard", "-i"]

  test "xsel read command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtXsel, ClipboardOperation.read)
      check cmd.isSome
      check cmd.get() == @["xsel", "--clipboard", "--output"]

  test "xsel write command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtXsel, ClipboardOperation.write)
      check cmd.isSome
      check cmd.get() == @["xsel", "--clipboard", "--input"]

  test "wl-clipboard read command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtWlClipboard, ClipboardOperation.read)
      check cmd.isSome
      check cmd.get() == @["wl-paste", "-n"]

  test "wl-clipboard write command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtWlClipboard, ClipboardOperation.write)
      check cmd.isSome
      check cmd.get() == @["wl-copy"]

  test "win32yank read command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtWin32yank, ClipboardOperation.read)
      check cmd.isSome
      check cmd.get() == @["win32yank.exe", "-o", "--lf"]

  test "win32yank write command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtWin32yank, ClipboardOperation.write)
      check cmd.isSome
      check cmd.get() == @["win32yank.exe", "-i", "--crlf"]

  test "pbcopy read command":
    if isSkipTest():
      skip()
    else:
      let cmd = getClipboardCommand(cbtPbcopy, ClipboardOperation.read)
      check cmd.isSome
      check cmd.get() == @["pbpaste"]

  test "pbcopy write command":
    if isSkipTest():
      skip()
    else:
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
  isToolAvailable("xclip")

proc isXselAvailable(): bool =
  isToolAvailable("xsel")

proc isWlClipboardAvailable(): bool =
  isToolAvailable("wl-copy")

suite "clipboard: readFromClipboardSync and writeToClipboardSync":
  test "write and read with xclip":
    if isSkipTest() or not isXclipAvailable():
      skip()
    else:
      let testText = "moe editor clipboard test - xclip"
      let writeResult = writeToClipboardSync(cbtXclip, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtXclip)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read with xsel":
    if isSkipTest() or not isXselAvailable():
      skip()
    else:
      let testText = "moe editor clipboard test - xsel"
      let writeResult = writeToClipboardSync(cbtXsel, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtXsel)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read with wl-clipboard":
    if isSkipTest() or not isWlClipboardAvailable():
      skip()
    else:
      let testText = "moe editor clipboard test - wl-clipboard"
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtWlClipboard)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read multiline text with xsel":
    if isSkipTest() or not isXselAvailable():
      skip()
    else:
      let testText = "line1\nline2\nline3"
      let writeResult = writeToClipboardSync(cbtXsel, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtXsel)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read unicode text with xsel":
    if isSkipTest() or not isXselAvailable():
      skip()
    else:
      let testText = "日本語テスト 🎉 emoji"
      let writeResult = writeToClipboardSync(cbtXsel, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtXsel)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read empty string with xsel":
    if isSkipTest() or not isXselAvailable():
      skip()
    else:
      let testText = ""
      let writeResult = writeToClipboardSync(cbtXsel, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtXsel)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read multiline text with wl-clipboard":
    if isSkipTest() or not isWlClipboardAvailable():
      skip()
    else:
      let testText = "line1\nline2\nline3"
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtWlClipboard)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read unicode text with wl-clipboard":
    if isSkipTest() or not isWlClipboardAvailable():
      skip()
    else:
      let testText = "日本語テスト 🎉 emoji"
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtWlClipboard)
      check readResult.isOk
      check readResult.get() == testText

  test "write and read empty string with wl-clipboard":
    if isSkipTest() or not isWlClipboardAvailable():
      skip()
    else:
      let testText = ""
      let writeResult = writeToClipboardSync(cbtWlClipboard, testText)
      check writeResult.isOk

      let readResult = readFromClipboardSync(cbtWlClipboard)
      check readResult.isOk
      check readResult.get() == testText
