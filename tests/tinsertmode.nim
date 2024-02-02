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

import std/[unittest, options]

import pkg/results

import moepkg/[highlight, editorstatus, gapbuffer, unicodeext, editor, movement,
               bufferstatus, windownode, visualmode]

import utils

import moepkg/insertmode {.all.}

proc initSelectedArea(status: EditorStatus) =
  currentBufStatus.selectedArea = initSelectedArea(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)
    .some

suite "insert: Insert characters":
  test "Issue #474":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru""])

    currentMainWindowNode.highlight = initHighlight(
      status.bufStatus[0].buffer.toSeqRunes,
      status.settings.highlight.reservedWords,
      status.bufStatus[0].language)

    status.resize(10, 10)

    for i in 0..<100:
      insertCharacter(
        status.bufStatus[0],
        currentMainWindowNode,
        status.settings.standard.autoCloseParen,
        ru'a')

    status.update

  test "Insert the character which is below the cursor":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    status.bufStatus[0].insertCharacterBelowCursor(
      currentMainWindowNode)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 2)
    check(buffer[0] == ru"ba")
    check(buffer[1] == ru"b")

  test "Insert the character which is below the cursor 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.bufStatus[0].insertCharacterBelowCursor(
      currentMainWindowNode)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"abc")

  test "Insert the character which is below the cursor 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"e"])

    currentMainWindowNode.currentColumn = 2

    status.bufStatus[0].insertCharacterBelowCursor(
      currentMainWindowNode)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 2)
    check(buffer[0] == ru"abc")
    check(buffer[1] == ru"e")

  test "Insert the character which is above the cursor":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"b"])

    currentMainWindowNode.currentLine = 1

    status.bufStatus[0].insertCharacterAboveCursor(
      currentMainWindowNode)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 2)
    check(buffer[0] == ru"a")
    check(buffer[1] == ru"ab")

  test "Insert the character which is above the cursor":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a", ru"bcd"])

    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 2

    status.bufStatus[0].insertCharacterAboveCursor(
      currentMainWindowNode)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 2)
    check(buffer[0] == ru"a")
    check(buffer[1] == ru"bcd")

  test "Insert the character which is above the cursor 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.bufStatus[0].insertCharacterAboveCursor(
      currentMainWindowNode)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"a")

  test "Delete the word before the cursor":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc def"])

    currentMainWindowNode.currentColumn = 4

    const Loop = 1
    currentBufStatus.deleteWordBeforeCursor(
      currentMainWindowNode,
      status.registers,
      Loop,
      status.settings)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"def")

  test "Delete the word before the cursor 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

    const Loop = 1
    currentBufStatus.deleteWordBeforeCursor(
      currentMainWindowNode,
      status.registers,
      Loop,
      status.settings)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"abc")

  test "Delete the word before the cursor 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"def"])

    currentMainWindowNode.currentLine = 1

    const Loop = 1
    currentBufStatus.deleteWordBeforeCursor(
      currentMainWindowNode,
      status.registers,
      Loop,
      status.settings)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"abcdef")

  test "Delete characters before the cursor in current line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abcdef"])

    currentMainWindowNode.currentColumn = 4

    status.bufStatus[0].deleteCharactersBeforeCursorInCurrentLine(
      currentMainWindowNode)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"ef")

  test "Delete characters before the cursor in current line 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"a"])

    status.bufStatus[0].deleteCharactersBeforeCursorInCurrentLine(
      currentMainWindowNode)

    let buffer = status.bufStatus[0].buffer
    check(buffer.len == 1)
    check(buffer[0] == ru"a")

  test "Add indent in current line 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.bufStatus[0].indentInCurrentLine(
      currentMainWindowNode,
      status.settings.view.tabStop)

    let buffer = status.bufStatus[0].buffer
    check(buffer[0] == ru"  abc")

    check(currentMainWindowNode.currentColumn == 2)

  test "Indent in current line 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru" abc"])

    status.bufStatus[0].indentInCurrentLine(
      currentMainWindowNode,
      status.settings.view.tabStop)

    let buffer = status.bufStatus[0].buffer
    check(buffer[0] == ru"  abc")

    check(currentMainWindowNode.currentColumn == 2)

  test "Unindent in current line 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])

    status.bufStatus[0].unindentInCurrentLine(
      currentMainWindowNode,
      status.settings.view.tabStop)

    let buffer = status.bufStatus[0].buffer
    check(buffer[0] == ru"abc")

    check(currentMainWindowNode.currentColumn == 0)

  test "Delete indent in current line 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

    status.bufStatus[0].unindentInCurrentLine(
      currentMainWindowNode,
      status.settings.view.tabStop)

    let buffer = status.bufStatus[0].buffer
    check(buffer[0] == ru"abc")

    check(currentMainWindowNode.currentColumn == 0)

  test "Delete indent in current line 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"   abc"])

    status.bufStatus[0].unindentInCurrentLine(
      currentMainWindowNode,
      status.settings.view.tabStop)

    let buffer = status.bufStatus[0].buffer
    check(buffer[0] == ru"  abc")

    check(currentMainWindowNode.currentColumn == 0)

  test "Move to last of line":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])
    status.bufStatus[0].mode = Mode.insert

    status.bufStatus[0].moveToLastOfLine(currentMainWindowNode)

    check currentMainWindowNode.currentColumn == 3

suite "insertMulti: Insert characters to multiple positions":
  test "Insert characters to 3 lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "abc", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 0
    currentBufStatus.selectedArea.get.endColumn = 0

    let keys = ru"xyz"
    for k in keys: status.insertToBuffer(k)

    check currentBufStatus.buffer.toSeqRunes == @["xyzabc", "xyzabc", "xyzabc"]
      .toSeqRunes

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 3

  test "Insert characters to 3 lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "abc", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 1
    currentBufStatus.selectedArea.get.endColumn = 1

    currentMainWindowNode.currentColumn = 1

    let keys = ru"xyz"
    for k in keys: status.insertToBuffer(k)

    check currentBufStatus.buffer.toSeqRunes == @["axyzbc", "axyzbc", "axyzbc"]
      .toSeqRunes

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 4

  test "Insert characters to 3 lines 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "abc", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 2

    let keys = ru"xyz"
    for k in keys: status.insertToBuffer(k)

    check currentBufStatus.buffer.toSeqRunes == @["abxyzc", "abxyzc", "abxyzc"]
      .toSeqRunes

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 5

suite "insertMulti: Delete characters from multiple positions":
  test "Ignore":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["", "", ""].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 0

    status.deleteBeforeCursorAndMoveToLeft

    check currentBufStatus.buffer.toSeqRunes == @["", "", ""].toSeqRunes
    check currentMainWindowNode.currentColumn == 0

  test "Delete characters from 3 lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "abc", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 3

    for i in 0 .. 2:
      status.deleteBeforeCursorAndMoveToLeft

    check currentBufStatus.buffer.toSeqRunes == @["", "", ""].toSeqRunes
    check currentMainWindowNode.currentColumn == 0

  test "Delete characters from 3 lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 3

    for i in 0 .. 1:
      status.deleteBeforeCursorAndMoveToLeft

    check currentBufStatus.buffer.toSeqRunes == @["a", "", "a"].toSeqRunes
    check currentMainWindowNode.currentColumn == 1

suite "insertMulti: Delete current characters from multiple positions":
  test "Ignore":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["", "", ""].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 0

    status.deleteCurrentCursor

    check currentBufStatus.buffer.toSeqRunes == @["", "", ""].toSeqRunes
    check currentMainWindowNode.currentColumn == 0

  test "Delete current characters from 3 lines":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "abc", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 0

    for i in 0 .. 2:
      status.deleteCurrentCursor

    check currentBufStatus.buffer.toSeqRunes == @["", "", ""].toSeqRunes
    check currentMainWindowNode.currentColumn == 0

  test "Delete current characters from 3 lines 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 0

    for i in 0 .. 1:
      status.deleteCurrentCursor

    check currentBufStatus.buffer.toSeqRunes == @["c", "", "c"].toSeqRunes
    check currentMainWindowNode.currentColumn == 0

  test "Delete current characters from 3 lines 3":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "abc", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 1

    status.deleteCurrentCursor

    check currentBufStatus.buffer.toSeqRunes == @["ac", "ac", "ac"].toSeqRunes
    check currentMainWindowNode.currentColumn == 1

  test "Delete current characters from 3 lines 4":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = @["abc", "abc", "abc"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insertMulti

    status.initSelectedArea

    currentBufStatus.selectedArea.get.startLine = 0
    currentBufStatus.selectedArea.get.endLine = 2
    currentBufStatus.selectedArea.get.startColumn = 2
    currentBufStatus.selectedArea.get.endColumn = 2

    currentMainWindowNode.currentColumn = 3

    status.deleteCurrentCursor

    check currentBufStatus.buffer.toSeqRunes == @["ab", "ab", "ab"].toSeqRunes
    check currentMainWindowNode.currentColumn == 2
