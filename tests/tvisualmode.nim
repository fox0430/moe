#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[unittest, osproc, options]

import pkg/results

import moepkg/[highlight, independentutils, editorstatus, gapbuffer, unicodeext,
               bufferstatus, movement, registers, settings, clipboard, folding]

import utils

import moepkg/visualmode {.all.}

proc initSelectedArea(status: var EditorStatus) =
  currentBufStatus.selectedArea = initSelectedArea(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)
    .some

suite "Visual mode: Delete buffer":
  test "Delete buffer 1":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abcd"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    status.initSelectedArea

    status.update

    for i in 0 ..< 2:
      currentBufStatus.keyRight(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check(currentBufStatus.buffer[0] == ru"d")

  test "Delete buffer 2":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.resize(100, 100)

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"")

  test "Delete buffer 3":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"ab", ru"cdef"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)

    status.resize(100, 100)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"ef")

  test "Delete buffer 4":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"defg"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check(currentBufStatus.buffer.len == 2)
    check(currentBufStatus.buffer[0] == ru"a")
    check(currentBufStatus.buffer[1] == ru"g")

  test "Delete buffer 5":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    status.changeMode(Mode.visual)
    status.initSelectedArea

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check(currentBufStatus.buffer.len == 2)
    check(currentBufStatus.buffer[0] == ru"a")
    check(currentBufStatus.buffer[1] == ru"i")

  test "Delete buffer 6":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)
    status.update

    status.changeMode(Mode.visual)
    status.initSelectedArea

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check currentBufStatus.buffer[0] == ru"def"
    check currentBufStatus.buffer[1] == ru"ghi"

  test "Fix #890":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"", ru"a"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentBufStatus.keyDown(currentMainWindowNode)

    status.update

    status.changeMode(Mode.visual)
    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru"a"
    check currentBufStatus.buffer[1] == ru"a"

  test "Visual mode: Check cursor position after delete buffer":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a b c"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    currentMainWindowNode.currentColumn = 2

    status.update

    status.changeMode(Mode.visual)
    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check currentBufStatus.buffer[0] == ru"a  c"
    check currentMainWindowNode.currentColumn == 2

  test "Contains folding lines":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    assert status.addNewBufferInCurrentWin.isOk
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    status.initSelectedArea

    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check currentBufStatus.buffer.toSeqRunes == @[""].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

  test "Before folding lines":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    assert status.addNewBufferInCurrentWin.isOk
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 1, last: 2)]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)
    status.resize(100, 100)

    status.initSelectedArea

    status.update

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    status.execVisualModeCommand(ru"x")

    check currentBufStatus.buffer.toSeqRunes == @["b", "c"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 1)
    ]

suite "Visual mode: Yank buffer (Disable clipboard)":
  test "Yank lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let
      area = currentBufStatus.selectedArea
      firstCursorPosition = BufferPosition(
        line: area.get.startLine,
        column: area.get.startColumn)
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area.get,
      firstCursorPosition,
      status.settings)

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == @[ru"abc", ru"def"]

  test "Yank lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    let
      area = currentBufStatus.selectedArea
      firstCursorPosition = BufferPosition(
        line: area.get.startLine,
        column: area.get.startColumn)
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area.get,
      firstCursorPosition,
      status.settings)

    check not status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == @[ru"abc"]

  test "Yank string (Fix #1124)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    let
      area = currentBufStatus.selectedArea
      firstCursorPosition = BufferPosition(
        line: area.get.startLine,
        column: area.get.startColumn)
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area.get,
      firstCursorPosition,
      status.settings)

    check not status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer[^1] == ru"abc"

  test "Yank lines when the last line is empty (Fix #1183)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru""])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let
      area = currentBufStatus.selectedArea
      firstCursorPosition = BufferPosition(
        line: area.get.startLine,
        column: area.get.startColumn)
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area.get,
      firstCursorPosition,
      status.settings)

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == @[ru"abc", ru""]

  test "Yank the empty line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    status.update

    let
      area = currentBufStatus.selectedArea
      firstCursorPosition = BufferPosition(
        line: area.get.startLine,
        column: area.get.startColumn)
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area.get,
      firstCursorPosition,
      status.settings)

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == @[ru""]

  test "Contains folding lines":
    var status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let
      area = currentBufStatus.selectedArea
      firstCursorPosition = BufferPosition(
        line: area.get.startLine,
        column: area.get.startColumn)
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area.get,
      firstCursorPosition,
      status.settings)

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == @["a", "b", "c"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 1)
    ]

suite "Visual block mode: Yank buffer (Disable clipboard)":
  test "Yank lines 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.yankBufferBlock(
      status.registers,
      currentMainWindowNode,
      area.get,
      status.settings)

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == @[ru"a", ru"d"]

  test "Yank lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"d"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

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
      area.get,
      status.settings)

    check status.registers.getNoNamedRegister.isLine
    check status.registers.getNoNamedRegister.buffer == @[ru"ab", ru"d"]

  test "Fix #1636":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"d"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    status.settings.clipboard.enable = false

    var area = currentBufStatus.selectedArea
    const Key = ru"y"
    status.visualBlockCommand(area.get, Key)

    check currentBufStatus.isNormalMode

suite "Visual block mode: Delete buffer (Disable clipboard)":
  test "Delete buffer":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    status.settings.clipboard.enable = false
    currentBufStatus.deleteBufferBlock(
      status.registers,
      currentMainWindowNode,
      area.get,
      status.settings,
      status.commandLine)

    check(currentBufStatus.buffer[0] == ru"bc")
    check(currentBufStatus.buffer[1] == ru"ef")

suite "Visual mode: Yank buffer (Enable clipboard)":
  test "Yank string":
    if not isXselAvailable():
      skip()
    else:
      assert clearXsel()

      var status = initEditorStatus()

      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      status.initSelectedArea

      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.changeMode(Mode.visual)

      status.resize(100, 100)
      status.update

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      status.update

      let
        area = currentBufStatus.selectedArea
        firstCursorPosition = BufferPosition(
          line: area.get.startLine,
          column: area.get.startColumn)

      status.settings.clipboard.enable = true
      status.registers.setClipboardTool(ClipboardTool.xsel)

      currentBufStatus.yankBuffer(
        status.registers,
        currentMainWindowNode,
        area.get,
        firstCursorPosition,
        status.settings)

      check getXselBuffer().removeLineEnd == "abc"

  test "Yank lines":
    if not isXselAvailable():
      skip()
    else:
      assert clearXsel()

      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visual)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
        .some

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      status.update

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let
        area = currentBufStatus.selectedArea
        firstCursorPosition = BufferPosition(
          line: area.get.startLine,
          column: area.get.startColumn)

      status.settings.clipboard.enable = true
      status.registers.setClipboardTool(ClipboardTool.xsel)

      currentBufStatus.yankBuffer(
        status.registers,
        currentMainWindowNode,
        area.get,
        firstCursorPosition,
        status.settings)

      check getXselBuffer().removeLineEnd == "abc\ndef"

suite "Visual block mode: Yank buffer (Enable clipboard) 1":
  test "Yank lines 1":
    if not isXselAvailable():
      skip()
    else:
      assert clearXsel()

      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
        .some

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let area = currentBufStatus.selectedArea

      status.settings.clipboard.enable = true
      status.registers.setClipboardTool(ClipboardTool.xsel)

      currentBufStatus.yankBufferBlock(
        status.registers,
        currentMainWindowNode,
        area.get,
        status.settings)

      check getXselBuffer().removeLineEnd == "a\nd"

  test "Yank lines 2":
    if not isXselAvailable():
      skip()
    else:
      assert clearXsel()

      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"d"])

      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
        .some

      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
      status.update

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let area = currentBufStatus.selectedArea

      status.settings.clipboard.enable = true
      status.registers.setClipboardTool(ClipboardTool.xsel)

      currentBufStatus.yankBufferBlock(
        status.registers,
        currentMainWindowNode,
        area.get,
        status.settings)

      check getXselBuffer().removeLineEnd == "ab\nd"

suite "Visual block mode: Delete buffer":
  test "Delete buffer (Enable clipboard) 1":
    if not isXselAvailable():
      skip()
    else:
      assert clearXsel()

      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
        .some

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

      let area = currentBufStatus.selectedArea

      status.settings.clipboard.enable = true
      status.registers.setClipboardTool(ClipboardTool.xsel)

      currentBufStatus.deleteBufferBlock(
        status.registers,
        currentMainWindowNode,
        area.get,
        status.settings,
        status.commandLine)

      check getXselBuffer().removeLineEnd == "a\nd"

  test "Delete buffer (Enable clipboard) 2":
    if not isXselAvailable():
      skip()
    else:
      assert clearXsel()

      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"edf"])

      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
        .some

      for i in 0 ..< 2:
        currentBufStatus.keyDown(currentMainWindowNode)
        status.update

      let area = currentBufStatus.selectedArea

      status.settings.clipboard.enable = true
      status.registers.setClipboardTool(ClipboardTool.xsel)

      currentBufStatus.deleteBufferBlock(
        status.registers,
        currentMainWindowNode,
        area.get,
        status.settings,
        status.commandLine)

  test "Fix #885":
    if not isXselAvailable():
      skip()
    else:
      assert clearXsel()

      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"de", ru"fgh"])

      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
        .some

      currentBufStatus.keyRight(currentMainWindowNode)
      for i in 0 ..< 2:
        currentBufStatus.keyDown(currentMainWindowNode)
        status.update

      let area = currentBufStatus.selectedArea

      status.settings.clipboard.enable = true
      status.registers.setClipboardTool(ClipboardTool.xsel)

      currentBufStatus.deleteBufferBlock(
        status.registers,
        currentMainWindowNode,
        area.get,
        status.settings,
        status.commandLine)

      check currentBufStatus.buffer[0] == ru"c"
      check currentBufStatus.buffer[1] == ru""
      check currentBufStatus.buffer[2] == ru"h"

suite "Visual mode: Join lines":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Join 2 lines":
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    currentBufStatus.joinLines(
      currentMainWindowNode,
      area.get,
      status.commandLine)

    check currentBufStatus.buffer.toSeqRunes == @["abcdef", "ghi"].toSeqRunes

  test "Contains folding lines":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    let area = currentBufStatus.selectedArea
    currentBufStatus.joinLines(
      currentMainWindowNode,
      area.get,
      status.commandLine)

    check currentBufStatus.buffer.toSeqRunes == @["abc"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Visual block mode: Join lines":
  test "Join 3 lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    let area = currentBufStatus.selectedArea

    status.update
    currentBufStatus.joinLines(
      currentMainWindowNode,
      area.get,
      status.commandLine)

    check(currentBufStatus.buffer.len == 1)
    check(currentBufStatus.buffer[0] == ru"abcdefghi")

suite "Visual mode: Add indent":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Add 1 indent":
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea.get, ru">")

    check currentBufStatus.buffer.toSeqRunes == @["  abc", "  def", "  ghi"]
      .toSeqRunes

  test "Contains folding lines":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru">")

    check currentBufStatus.buffer.toSeqRunes == @["  a", "  b", "  c"]
      .toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Visual block mode: Add indent":
  test "Add 1 indent":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"ghi"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    status.initSelectedArea

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectedArea.get, ru">")

    check(currentBufStatus.buffer[0] == ru"  abc")
    check(currentBufStatus.buffer[1] == ru"  def")
    check(currentBufStatus.buffer[2] == ru"  ghi")

suite "Visual mode: Delete indent":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Delete 1 indent":
    currentBufStatus.buffer = @["  abc", "  def", "  ghi"]
      .toSeqRunes
      .toGapBuffer

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"<")

    check currentBufStatus.buffer.toSeqRunes == @["abc", "def", "ghi"].toSeqRunes

  test "Contains folding line":
    currentBufStatus.buffer = @["  a", "  b", "  c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"<")

    check currentBufStatus.buffer.toSeqRunes == @["a", "b", "c"].toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Visual block mode: Delete indent":
  test "Delete 1 indent":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"  abc", ru"  def", ru"  ghi"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    status.initSelectedArea

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectedArea.get, ru"<")

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"def")
    check(currentBufStatus.buffer[2] == ru"ghi")

suite "Visual mode: Converts string into lower-case string":
  test "Converts string into lower-case string 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea.get, ru"u")

    check(currentBufStatus.buffer[0] == ru"abc")

  test "Converts string into lower-case string 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"AあbC"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea.get, ru"u")

    check(currentBufStatus.buffer[0] == ru"aあbc")

  test "Converts string into lower-case string 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"DEF"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"u")

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"dEF")

  test "Converts string into lower-case string 4 (Fix #687)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"", ru"DEF", ru""])
    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)
    status.initSelectedArea

    for i in 0 ..< 3:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"u")

    check(currentBufStatus.buffer[0] == ru"abc")
    check(currentBufStatus.buffer[1] == ru"")
    check(currentBufStatus.buffer[2] == ru"def")

suite "Visual block mode: Converts string into lower-case string":
  test "Converts string into lower-case string":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectedArea.get, ru"u")

    check(currentBufStatus.buffer[0] == ru"abc")

  test "Converts string into lower-case string 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"ABC", ru"DEF"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualBlockCommand(currentBufStatus.selectedArea.get, ru"u")

    check(currentBufStatus.buffer[0] == ru"abC")
    check(currentBufStatus.buffer[1] == ru"deF")

suite "Visual mode: Converts string into upper-case string":
  test "Converts string into upper-case string 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea.get, ru"U")

    check(currentBufStatus.buffer[0] == ru"ABC")

  test "Converts string into upper-case string 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"aあBc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualCommand(currentBufStatus.selectedArea.get, ru"U")

    check(currentBufStatus.buffer[0] == ru"AあBC")

  test "Converts string into upper-case string 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"U")

    check(currentBufStatus.buffer[0] == ru"ABC")
    check(currentBufStatus.buffer[1] == ru"Def")

  test "Visual mode: Converts string into upper-case string 4 (Fix #687)":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru""])
    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    for i in 0 ..< 3:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"U")

    check(currentBufStatus.buffer[0] == ru"ABC")
    check(currentBufStatus.buffer[1] == ru"")
    check(currentBufStatus.buffer[2] == ru"DEF")

suite "Visual mode: Movement":
  test "Move to end of the line + 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    assert currentMainWindowNode.currentColumn == currentBufStatus.buffer[0].len

suite "Visual block mode: Converts string into upper-case string":
  test "Converts string into upper-case string 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    status.update

    status.update
    status.visualBlockCommand(currentBufStatus.selectedArea.get, ru"U")

    check(currentBufStatus.buffer[0] == ru"ABC")

  test "Converts string into upper-case string 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    status.initSelectedArea

    currentBufStatus.keyRight(currentMainWindowNode)
    status.update

    currentBufStatus.keyDown(currentMainWindowNode)
    status.update

    status.visualBlockCommand(currentBufStatus.selectedArea.get, ru"U")

    check(currentBufStatus.buffer[0] == ru"ABc")
    check(currentBufStatus.buffer[1] == ru"DEf")

suite "Visual mode: move to the previous blank line":
  test "move to the previous blank line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"1", ru "", ru "3", ru "4"])

    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    status.execVisualModeCommand(ru"{")

    check currentMainWindowNode.currentLine == 1

suite "Visual mode: move to the next blank line":
  test "move to the next blank line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"1", ru "2", ru "", ru "4"])

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    status.execVisualModeCommand(ru"}")

    check currentMainWindowNode.currentLine == 2

suite "Visual mode: Replace characters":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Empty buffer":
    # NOTE: https://github.com/fox0430/moe/issues/1856
    currentBufStatus.buffer = @[""].toSeqRunes.toGapBuffer

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    currentBufStatus.replaceCharacter(
      currentMainWindowNode,
      currentBufStatus.selectedArea.get,
      ru 'a',
      status.commandLine)

    check currentBufStatus.buffer.toSeqRunes == @[ru""]

  test "Basic":
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea
    status.update

    var selectedArea = SelectedArea(
      startLine: 0,
      startColumn: 0,
      endLine: 2,
      endColumn: 2)

    currentBufStatus.replaceCharacter(
      currentMainWindowNode,
      selectedArea,
      ru'z',
      status.commandLine)

    check currentBufStatus.buffer.toSeqRunes == @["zzz", "zzz", "zzz"]
      .toSeqRunes

  test "Contains folding lines":
    currentBufStatus.buffer = @["abc", "def", "ghi"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea
    status.update

    var selectedArea = SelectedArea(
      startLine: 0,
      startColumn: 0,
      endLine: 2,
      endColumn: 2)

    currentBufStatus.replaceCharacter(
      currentMainWindowNode,
      selectedArea,
      ru'z',
      status.commandLine)

    check currentBufStatus.buffer.toSeqRunes == @["zzz", "zzz", "zzz"]
      .toSeqRunes

    check currentMainWindowNode.view.foldingRanges.len == 0

suite "Visual block mode: Replace characters":
  test "Empty buffer":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru""])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    currentBufStatus.replaceCharacterBlock(
      currentMainWindowNode,
      currentBufStatus.selectedArea.get,
      ru 'a',
      status.commandLine)

    check currentBufStatus.buffer.toSeqRunes == @[ru""]

suite "Visual mode: Run command when Readonly mode":
  test "Delete buffer (\"x\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\">\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru">")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\"<\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"<")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Join lines (\"J\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru "def"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    currentMainWindowNode.currentColumn = currentBufStatus.buffer[0].high

    status.initSelectedArea

    currentBufStatus.selectedArea.get.endLine = 1

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"J")

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "def"

  test "To lower case (\"u\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"u")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "To upper case (\"U\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"U")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Replace characters (\"r\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    currentBufStatus.replaceCharacter(
      currentMainWindowNode,
      currentBufStatus.selectedArea.get,
      ru 'z',
      status.commandLine)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Enter insert mode when readonly mode (\"I\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"I")

    check currentBufStatus.mode == Mode.normal

suite "Visual block mode: move to the previous blank line":
  test "move to the previous blank line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"1", ru "", ru "3", ru "4"])

    currentMainWindowNode.currentLine = 3

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    status.execVisualModeCommand(ru"{")

    check currentMainWindowNode.currentLine == 1

suite "Visual block mode: move to the next blank line":
  test "move to the next blank line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"1", ru "2", ru "", ru "4"])

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    status.execVisualModeCommand(ru"}")

    check currentMainWindowNode.currentLine == 2

suite "Visual block mode: Run command when Readonly mode":
  test "Delete buffer (\"x\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Enter insert mode when readonly mode (\"I\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualblock)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"I")

    check currentBufStatus.mode == Mode.normal

  test "Add the indent (\">\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru">")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\"<\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"<")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Join lines (\"J\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru "def"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    currentMainWindowNode.currentColumn = currentBufStatus.buffer[0].high

    status.initSelectedArea

    currentBufStatus.selectedArea.get.endLine = 1

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"J")

    check currentBufStatus.buffer.len == 2
    check currentBufStatus.buffer[0] == ru "abc"
    check currentBufStatus.buffer[1] == ru "def"

  test "To lower case (\"u\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"u")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "To upper case (\"U\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"U")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Replace characters (\"r\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)

    status.initSelectedArea

    status.update

    currentBufStatus.replaceCharacter(
      currentMainWindowNode,
      currentBufStatus.selectedArea.get,
      ru 'z',
      status.commandLine)

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

suite "Visual block mode: Movement":
  test "Move to end of the line + 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualBlock)
    status.initSelectedArea

    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    status.update

    assert currentMainWindowNode.currentColumn == currentBufStatus.buffer[0].len

suite "Visual line mode: Delete buffer":
  test "Delete buffer with 'x' command":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visualLine)

    status.resize(100, 100)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check currentBufStatus.buffer[0] == ru"b"
    check currentBufStatus.buffer[1] == ru"c"
    check currentBufStatus.buffer[2] == ru"d"

  test "Delete buffer with 'x' command 2":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visualLine)

    status.resize(100, 100)
    status.update

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"x")

    check(currentBufStatus.buffer[0] == ru"d")

  test "Delete buffer with 'd' command":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visualLine)

    status.resize(100, 100)
    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"d")

    check currentBufStatus.buffer[0] == ru"b"
    check currentBufStatus.buffer[1] == ru"c"
    check currentBufStatus.buffer[2] == ru"d"

  test "Delete buffer with 'd' command 2":
    var status = initEditorStatus()
    status.settings.clipboard.enable = false

    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"a", ru"b", ru"c", ru"d"])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visualLine)

    status.resize(100, 100)
    status.update

    for i in 0 ..< 2:
      currentBufStatus.keyDown(currentMainWindowNode)
      status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"d")

    check(currentBufStatus.buffer[0] == ru"d")

suite "Visual line mode: Yank buffer (Disable clipboard)":
  test "Yank lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    let buffer = @[ru"a", ru"b", ru"c", ru"d"]
    currentBufStatus.buffer = buffer.toGapBuffer

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)
    status.update

    status.changeMode(Mode.visualLine)

    status.initSelectedArea

    status.update

    let
      area = currentBufStatus.selectedArea
      firstCursorPosition = BufferPosition(
        line: area.get.startLine,
        column: area.get.startColumn)
    status.settings.clipboard.enable = false
    currentBufStatus.yankBuffer(
      status.registers,
      currentMainWindowNode,
      area.get,
      firstCursorPosition,
      status.settings)

    check status.registers.getNoNamedRegister.buffer == @[buffer[0]]

suite "Visual line mode: Yank buffer (Enable clipboard)":
  test "Yank lines":
    if not isXselAvailable():
      skip()
    else:
      assert clearXsel()

      var status = initEditorStatus()
      discard status.addNewBufferInCurrentWin.get
      let buffer = @[ru"a", ru"b", ru"c", ru"d"]
      currentBufStatus.buffer = buffer.toGapBuffer

      status.initSelectedArea

      currentBufStatus.highlight = initHighlight(
        currentBufStatus.buffer.toSeqRunes,
        status.settings.highlight.reservedWords,
        currentBufStatus.language)

      status.resize(100, 100)
      status.update

      status.changeMode(Mode.visualBlock)

      currentBufStatus.selectedArea = initSelectedArea(
        currentMainWindowNode.currentLine,
        currentMainWindowNode.currentColumn)
        .some

      status.update

      let
        area = currentBufStatus.selectedArea
        firstCursorPosition = BufferPosition(
          line: area.get.startLine,
          column: area.get.startColumn)

      status.settings.clipboard.enable = true
      status.registers.setClipboardTool(ClipboardTool.xsel)

      currentBufStatus.yankBuffer(
        status.registers,
        currentMainWindowNode,
        area.get,
        firstCursorPosition,
        status.settings)

      check getXselBuffer().removeLineEnd == "a"

suite "Visual line mode: idenet":
  test "Add the indent (\">\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualLine)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru">")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

  test "Add the indent (\"<\" command)":
    var status = initEditorStatus()
    status.isReadonly = true
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    status.initSelectedArea

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.resize(100, 100)

    status.changeMode(Mode.visualline)

    status.initSelectedArea

    status.update

    status.visualCommand(currentBufStatus.selectedArea.get, ru"<")

    check currentBufStatus.buffer.len == 1
    check currentBufStatus.buffer[0] == ru "abc"

suite "Visual mode: Add folding range":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin.isOk

  test "Ignore":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.selectedArea = some(SelectedArea(
      startLine: 0,
      startColumn: 0,
      endLine: 0,
      endColumn: 0,
    ))

    status.visualCommand(currentBufStatus.selectedArea.get, ru"zf")

    check currentMainWindowNode.view.foldingRanges.len == 0

  test "Basic":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.selectedArea = some(SelectedArea(
      startLine: 0,
      startColumn: 0,
      endLine: 1,
      endColumn: 0,
    ))
    currentMainWindowNode.currentLine = 1

    status.visualCommand(currentBufStatus.selectedArea.get, ru"zf")

    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 1)
    ]

  test "Nest":
    currentBufStatus.buffer = @["a", "b", "c"].toSeqRunes.toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[FoldingRange(first: 0, last: 1)]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.selectedArea = some(SelectedArea(
      startLine: 0,
      startColumn: 0,
      endLine: 2,
      endColumn: 0,
    ))
    currentMainWindowNode.currentLine = 2

    status.visualCommand(currentBufStatus.selectedArea.get, ru"zf")

    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 2),
      FoldingRange(first: 0, last: 1)
    ]

  test "Nest 2":
    currentBufStatus.buffer = @["a", "b", "c", "d", "e", "f", "g"]
      .toSeqRunes
      .toGapBuffer
    currentMainWindowNode.view.foldingRanges = @[
      FoldingRange(first: 1, last: 2),
      FoldingRange(first: 4, last: 5)
    ]

    currentBufStatus.highlight = initHighlight(
      currentBufStatus.buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      currentBufStatus.language)

    status.changeMode(Mode.visual)

    status.initSelectedArea

    status.resize(100, 100)
    status.update

    currentBufStatus.selectedArea = some(SelectedArea(
      startLine: 0,
      startColumn: 0,
      endLine: 6,
      endColumn: 0,
    ))
    currentMainWindowNode.currentLine = 6

    status.visualCommand(currentBufStatus.selectedArea.get, ru"zf")

    check currentMainWindowNode.view.foldingRanges == @[
      FoldingRange(first: 0, last: 6),
      FoldingRange(first: 1, last: 2),
      FoldingRange(first: 4, last: 5)
    ]
