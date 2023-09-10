#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[unittest, osproc]
import moepkg/[highlight, independentutils, editorstatus, gapbuffer, unicodeext,
               bufferstatus, movement, editor, ui]

import moepkg/visualmode {.all.}
import moepkg/platform {.all.}

proc isXselAvailable(): bool {.inline.} =
  execCmdExNoOutput("xset q") == 0 and execCmdExNoOutput("xsel --version") == 0

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "Visual mode: Delete buffer":
  test "Delete buffer 1":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abcd"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check(currentBufStatus.buffer[0] == ru"d")

  test "Delete buffer 2":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"")

  test "Delete buffer 3":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"ab", ru"cdef"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"ef")

  test "Delete buffer 4":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"defg"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check(currentBufStatus.buffer.len == 2)
    check(currentBufStatus.buffer[0] == ru"a")
    check(currentBufStatus.buffer[1] == ru"g")

  test "Delete buffer 5":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check(currentBufStatus.buffer.len == 2)
    check(currentBufStatus.buffer[0] == ru"a")
    check(currentBufStatus.buffer[1] == ru"i")

  test "Delete buffer 6":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)
    status.update

    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check currentBufStatus.buffer[0] == ru"def"
    check currentBufStatus.buffer[1] == ru"ghi"

  test "Fix #890":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"", ru"a"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyDown(currentMainWindowNode)

    status.update

    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru"a"
    check currentBufStatus.buffer[1] == ru"a"

  test "Visual mode: Check cursor position after delete buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a b c"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentMainWindowNode.currentColumn = 2

    status.update

    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check currentBufStatus.buffer[0] == ru"a  c"
    check currentMainWindowNode.currentColumn == 2

suite "Visual mode: Yank buffer (Disable clipboard)":
  test "Yank lines":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings)

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer == @[ru"abc", ru"def"]

  test "Yank lines 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings)

    check not status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer == @[ru"abc"]

  test "Yank string (Fix #1124)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings)

    check not status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer[^1] == ru"abc"

  test "Yank lines when the last line is empty (Fix #1183)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru""])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings)

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer == @[ru"abc", ru""]

  test "Yank the empty line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"", ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings)

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer == @[ru""]

suite "Visual block mode: Yank buffer (Disable clipboard)":
  test "Yank lines 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBufferBlock(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings)

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer == @[ru"a", ru"d"]

  test "Yank lines 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"d"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)
      status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBufferBlock(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings)

    check status.registers.noNameRegisters.isLine
    check status.registers.noNameRegisters.buffer == @[ru"ab", ru"d"]

  test "Fix #1636":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"d"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    status.settings.clipboard.enable = false

    var area = currentBufStatus.selectedArea
    const Key = ru'y'
    status.visualBlockCommand(area, Key)

    check currentBufStatus.isNormalMode

suite "Visual block mode: Delete buffer (Disable clipboard)":
  test "Delete buffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.deleteBufferBlock(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings,
      status.commandLine)

    check(currentBufStatus.buffer[0] == ru"bc")
    check(currentBufStatus.buffer[1] == ru"ef")

if isXselAvailable():
  suite "Visual mode: Yank buffer (Enable clipboard)":
    test "Yank string":
      var status = initEditorStatus()

      status.addNewBufferInCurrentWin
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentMainWindowNode.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.changeMode(Mode.visual)

      status.resize(100, 100)
      status.update

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      status.update

      let area = currentBufStatus.selectedArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBuffer(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings)

      if currentPlatform == Platforms.linux or currentPlatform == Platforms.wsl:
        let
          cmd =
            if currentPlatform == Platforms.linux:
              execCmdEx("xsel -o")
            else:
              # On the WSL
             execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0

        if currentPlatform == Platforms.linux:
          check output[0 .. output.high - 1] == "abc"
        else:
          # On the WSL
          check output[0 .. output.high - 2] == "abc"

    test "Yank lines":
      var status = initEditorStatus()
      status.addNewBufferInCurrentWin
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentMainWindowNode.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visual)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      status.update

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let area = currentBufStatus.selectedArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBuffer(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings)

      if currentPlatform == Platforms.linux or currentPlatform == Platforms.wsl:
        let
          cmd =
            if currentPlatform == Platforms.linux:
              execCmdEx("xsel -o")
            else:
              # On the WSL
              execCmdEx("powershell.exe -Command Get-Clipboard")
          (output, exitCode) = cmd

        check exitCode == 0

        if currentPlatform == Platforms.linux:
          check output[0 .. output.high - 1] == "abc\ndef"
        else:
          # On the WSL
          check output[0 .. output.high - 2] == "abc\ndef"

if isXselAvailable():
  suite "Visual block mode: Yank buffer (Enable clipboard) 1":
    test "Yank lines 1":
      var status = initEditorStatus()
      status.addNewBufferInCurrentWin
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentMainWindowNode.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let area = currentBufStatus.selectedArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBufferBlock(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings)

      if currentPlatform == Platforms.linux:
        let (output, exitCode) = execCmdEx("xsel -o")

        check exitCode == 0
        check output[0 .. output.high - 1] == "a\nd"

    test "Yank lines 2":
      var status = initEditorStatus()
      status.addNewBufferInCurrentWin
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"d"])

      currentMainWindowNode.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      status.update

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let area = currentBufStatus.selectedArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBufferBlock(
        status.registers,
       currentMainWindowNode,
       area,
       status.settings)

      if currentPlatform == Platforms.linux:
        let (output, exitCode) = execCmdEx("xsel -o")

        check exitCode == 0
        check output[0 .. output.high - 1] == "ab\nd"

if isXselAvailable():
  suite "Visual block mode: Delete buffer":
    test "Delete buffer (Enable clipboard) 1":
      var status = initEditorStatus()
      status.addNewBufferInCurrentWin
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentMainWindowNode.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let area = currentBufStatus.selectedArea
      status.settings.clipboard.enable = true
      currentBufStatus.deleteBufferBlock(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings,
        status.commandLine)

      if currentPlatform == Platforms.linux:
        let (output, exitCode) = execCmdEx("xsel -o")
        check(exitCode == 0 and output[0 .. output.high - 1] == "a\nd")

    test "Delete buffer (Enable clipboard) 2":
      var status = initEditorStatus()
      status.addNewBufferInCurrentWin
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"edf"])

      currentMainWindowNode.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      for i in 0 ..< 2:
        currentBufStatus.keyDown(currentMainWindowNode)
        status.update

      let area = currentBufStatus.selectedArea
      status.settings.clipboard.enable = true
      currentBufStatus.deleteBufferBlock(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings,
        status.commandLine)

    test "Fix #885":
      var status = initEditorStatus()
      status.addNewBufferInCurrentWin
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"de", ru"fgh"])

      currentMainWindowNode.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)

      currentBufStatus.keyRight(currentMainWindowNode)
      for i in 0 ..< 2:
        currentBufStatus.keyDown(currentMainWindowNode)
        status.update

      let area = currentBufStatus.selectedArea
      status.settings.clipboard.enable = true
      currentBufStatus.deleteBufferBlock(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings,
        status.commandLine)

      check currentBufStatus.buffer[0] == ru"c"
      check currentBufStatus.buffer[1] == ru""
      check currentBufStatus.buffer[2] == ru"h"

suite "Visual mode: Join lines":
  test "Join 3 lines":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    let area = currentBufStatus.selectedArea

    status.update
    currentBufStatus.joinLines(currentMainWindowNode, area, status.commandLine)

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"abcdefghi")

suite "Visual block mode: Join lines":
  test "Join 3 lines":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    let area = currentBufStatus.selectedArea

    status.update
    currentBufStatus.joinLines(currentMainWindowNode, area, status.commandLine)

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"abcdefghi")

test "Visual mode: Add indent":
  test "Add 1 indent":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea, ru'>')

    check(currentBufStatus.buffer[0] == ru"  abc")
    check(currentBufStatus.buffer[1] == ru"  def")
    check(currentBufStatus.buffer[2] == ru"  ghi")

suite "Visual block mode: Add indent":
  test "Add 1 indent":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectedArea, ru'>')

    check(currentBufStatus.buffer[0] == ru"  abc")
    check(currentBufStatus.buffer[1] == ru"  def")
    check(currentBufStatus.buffer[2] == ru"  ghi")

suite "Visual mode: Delete indent":
  test "Delete 1 indent":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea, ru'<')

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"def")
    check(currentBufStatus.buffer[2] == ru"ghi")

suite "Visual block mode: Delete indent":
  test "Delete 1 indent":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectedArea, ru'<')

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"def")
    check(currentBufStatus.buffer[2] == ru"ghi")

suite "Visual mode: Converts string into lower-case string":
  test "Converts string into lower-case string 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abc")

  test "Converts string into lower-case string 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"AあbC"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"aあbc")

  test "Converts string into lower-case string 3":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"DEF"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"dEF")

  test "Converts string into lower-case string 4 (Fix #687)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"", ru"DEF", ru""])
    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 3:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"")
    check(currentBufStatus.buffer[2] == ru"def")

test "Visual block mode: Converts string into lower-case string":
  test "Converts string into lower-case string":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectedArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abc")

  test "Converts string into lower-case string 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"DEF"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualBlockCommand(currentBufStatus.selectedArea, ru'u')

    check(currentBufStatus.buffer[0] == ru"abC")
    check(currentBufStatus.buffer[1] == ru"deF")

suite "Visual mode: Converts string into upper-case string":
  test "Converts string into upper-case string 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABC")

  test "Converts string into upper-case string 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"aあBc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"AあBC")

  test "Converts string into upper-case string 3":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABC")
    check(currentBufStatus.buffer[1] == ru"Def")

  test "Visual mode: Converts string into upper-case string 4 (Fix #687)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru""])
    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    for i in 0 ..< 3:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABC")
    check(currentBufStatus.buffer[1] == ru"")
    check(currentBufStatus.buffer[2] == ru"DEF")

suite "Visual mode: Movement":
  test "Move to end of the line + 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    assert currentMainWindowNode.currentColumn == currentBufStatus.buffer[0].len

suite "Visual block mode: Converts string into upper-case string":
  test "Converts string into upper-case string 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectedArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABC")

  test "Converts string into upper-case string 2":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualBlockCommand(currentBufStatus.selectedArea, ru'U')

    check(currentBufStatus.buffer[0] == ru"ABc")
    check(currentBufStatus.buffer[1] == ru"DEf")

suite "Visual block mode: Insert buffer":
  test "insert tab (Fix #1186)":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    # Insert buffer
    block:
      status.changeMode(Mode.insert)

      let area = currentBufStatus.selectedArea
      currentMainWindowNode.currentLine = area.startLine
      currentMainWindowNode.currentColumn = area.startColumn

      const InsertBuffer = ru "\t"

      # Insert buffer to the area.startLine
      for c in InsertBuffer:
        insertTab(
          currentBufStatus,
          currentMainWindowNode,
          status.settings.tabStop,
          status.settings.autoCloseParen)

      currentBufStatus.insertCharBlock(
        currentMainWindowNode,
        InsertBuffer,
        area,
        status.settings.tabStop,
        status.settings.autoCloseParen,
        status.commandLine)

    check currentBufStatus.buffer[0] == ru"  abc"
    check currentBufStatus.buffer[1] == ru"  def"

suite "Visual mode: move to the previous blank line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"1", ru "", ru "3", ru "4"])

    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.execVisualModeCommand(ru"{")

    check currentMainWindowNode.currentLine == 1

suite "Visual mode: move to the next blank line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"1", ru "2", ru "", ru "4"])

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.execVisualModeCommand(ru"}")

    check currentMainWindowNode.currentLine == 2

suite "Visual mode: Run command when Readonly mode":
  test "Delete buffer (\"x\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\">\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'>')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\"<\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'<')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Join lines (\"J\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru "def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentMainWindowNode.currentColumn = currentBufStatus.buffer[0].high

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.selectedArea.endLine = 1

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'J')

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "def"

  test "To lower case (\"u\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'u')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "To upper case (\"U\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'U')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Replace characters (\"r\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    currentBufStatus.replaceCharacter(
      currentBufStatus.selectedArea,
      ru 'z',
      status.commandLine)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Enter insert mode when readonly mode (\"I\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'I')

    check currentBufStatus.mode == Mode.normal

suite "Visual block mode: move to the previous blank line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"1", ru "", ru "3", ru "4"])

    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.execVisualModeCommand(ru"{")

    check currentMainWindowNode.currentLine == 1

suite "Visual block mode: move to the next blank line":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"1", ru "2", ru "", ru "4"])

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.execVisualModeCommand(ru"}")

    check currentMainWindowNode.currentLine == 2

suite "Visual block mode: Run command when Readonly mode":
  test "Delete buffer (\"x\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Enter insert mode when readonly mode (\"I\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'I')

    check currentBufStatus.mode == Mode.normal

  test "Add the indent (\">\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'>')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\"<\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'<')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Join lines (\"J\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru "def"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentMainWindowNode.currentColumn = currentBufStatus.buffer[0].high

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.selectedArea.endLine = 1

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'J')

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "def"

  test "To lower case (\"u\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'u')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "To upper case (\"U\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'U')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Replace characters (\"r\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    currentBufStatus.replaceCharacter(
      currentBufStatus.selectedArea,
      ru 'z',
      status.commandLine)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

suite "Visual block mode: Movement":
  test "Move to end of the line + 1":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    assert currentMainWindowNode.currentColumn == currentBufStatus.buffer[0].len

suite "Visual line mode: Delete buffer":
  test "Delete buffer with 'x' command":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visualLine)

    status.resize(100, 100)
    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check currentBufStatus.buffer[0] == ru"b"
    check currentBufStatus.buffer[1] == ru"c"
    check currentBufStatus.buffer[2] == ru"d"

  test "Delete buffer with 'x' command 2":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visualLine)

    status.resize(100, 100)
    status.update

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'x')

    check(currentBufStatus.buffer[0] == ru"d")

  test "Delete buffer with 'd' command":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visualLine)

    status.resize(100, 100)
    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'd')

    check currentBufStatus.buffer[0] == ru"b"
    check currentBufStatus.buffer[1] == ru"c"
    check currentBufStatus.buffer[2] == ru"d"

  test "Delete buffer with 'd' command 2":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visualLine)

    status.resize(100, 100)
    status.update

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'd')

    check(currentBufStatus.buffer[0] == ru"d")

suite "Visual line mode: Yank buffer (Disable clipboard)":
  test "Yank lines":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin
    let buffer = @[ru"a", ru"b", ru"c", ru"d"]
    currentBufStatus.buffer = buffer.toGapBuffer

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)
    status.update

    status.changeMode(Mode.visualLine)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area,
      status.settings)

    check status.registers.noNameRegisters.buffer == @[buffer[0]]

if isXselAvailable():
  suite "Visual line mode: Yank buffer (Enable clipboard)":
    test "Yank lines":
      var status = initEditorStatus()
      status.addNewBufferInCurrentWin
      let buffer = @[ru"a", ru"b", ru"c", ru"d"]
      currentBufStatus.buffer = buffer.toGapBuffer

      currentMainWindowNode.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)
      status.update

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
      status.update

      let area = currentBufStatus.selectedArea
      status.settings.clipboard.enable = true
      currentBufStatus.yankBuffer(
        status.registers,
        currentMainWindowNode,
        area,
        status.settings)

      if currentPlatform == Platforms.linux:
        let (output, exitCode) = execCmdEx("xsel -o")

        check exitCode == 0
        check output[0 .. output.high - 1] == "a"

suite "Visual line mode: idenet":
  test "Add the indent (\">\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualLine)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'>')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\"<\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    status.addNewBufferInCurrentWin
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentMainWindowNode.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualline)

    currentBufStatus.selectedArea = initSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    status.visualCommand(currentBufStatus.selectedArea, ru'<')

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"
