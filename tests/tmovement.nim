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

import std/[unittest, sequtils]
import pkg/results
import moepkg/[editorstatus, gapbuffer, unicodeext, highlight, movement,
               bufferstatus, ui]

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

test "Move right":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  currentMainWindowNode.highlight = initHighlight(
    status.bufStatus[0].buffer.toSeqRunes,
    status.settings.highlight.reservedWords,
    status.bufStatus[0].language)

  for i in 0 ..< 3:
    status.bufStatus[0].keyRight(currentMainWindowNode)

  check(currentMainWindowNode.currentColumn == 2)

test "Move left":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc"])

  currentMainWindowNode.highlight = initHighlight(
    status.bufStatus[0].buffer.toSeqRunes,
    status.settings.highlight.reservedWords,
    status.bufStatus[0].language)

  currentMainWindowNode.currentColumn = 2
  for i in 0 ..< 3:
    currentMainWindowNode.keyLeft

  check(currentMainWindowNode.currentColumn == 0)

test "Move down":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij"])

  currentMainWindowNode.highlight = initHighlight(
    status.bufStatus[0].buffer.toSeqRunes,
    status.settings.highlight.reservedWords,
    status.bufStatus[0].language)

  for i in 0 ..< 3:
    status.bufStatus[0].keyDown(currentMainWindowNode)

  check(currentMainWindowNode.currentLine == 2)

test "Move up":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc", ru"efg", ru"hij"])

  currentMainWindowNode.highlight = initHighlight(
    status.bufStatus[0].buffer.toSeqRunes,
    status.settings.highlight.reservedWords,
    status.bufStatus[0].language)

  currentMainWindowNode.currentLine = 2
  for i in 0 ..< 3:
    status.bufStatus[0].keyUp(currentMainWindowNode)

  check(currentMainWindowNode.currentLine == 0)

test "Move to first non blank of current line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  currentMainWindowNode.currentColumn = 4
  status.bufStatus[0].moveToFirstNonBlankOfLine(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 2)

test "Move to first of current line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  currentMainWindowNode.currentColumn = 4
  currentMainWindowNode.moveToFirstOfLine
  check(currentMainWindowNode.currentColumn == 0)

test "Move to last of current line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc"])
  status.bufStatus[0].moveToLastOfLine(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 4)

test "Move to first of previous Line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"efg"])
  currentMainWindowNode.currentLine = 1
  status.bufStatus[0].moveToFirstOfPreviousLine(currentMainWindowNode)
  check(currentMainWindowNode.currentLine == 0)
  check(currentMainWindowNode.currentColumn == 0)

test "Move to first of next Line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"  abc", ru"efg"])
  status.bufStatus[0].moveToFirstOfNextLine(currentMainWindowNode)
  check(currentMainWindowNode.currentLine == 1)
  check(currentMainWindowNode.currentColumn == 0)

test "Jump line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[
    "abc",
    "efg",
    "hij",
    "klm",
    "nop",
    "qrs"].toSeqRunes)

  currentBufStatus.jumpLine(currentMainWindowNode, 1)
  currentBufStatus.jumpLine(currentMainWindowNode, 4)
  check(currentMainWindowNode.currentLine == 4)

test "Move to first line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[
    "abc",
    "efg",
    "hij",
    "klm",
    "nop",
    "qrs"].toSeqRunes)

  currentMainWindowNode.currentLine = 4
  currentBufStatus.moveToFirstLine(currentMainWindowNode)
  check(currentMainWindowNode.currentLine == 0)

test "Move to last line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[
    "abc",
    "efg",
    "hij",
    "klm",
    "nop",
    "qrs"].toSeqRunes)

  currentMainWindowNode.currentLine = 1
  currentBufStatus.moveToLastLine(currentMainWindowNode)
  check(currentMainWindowNode.currentLine == 5)

test "Move to forward word":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  status.bufStatus[0].moveToForwardWord(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 4)

test "Move to backward word":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  currentMainWindowNode.currentColumn = 5
  for i in 0 ..< 2:
    status.bufStatus[0].moveToBackwardWord(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 0)

test "Move to forward end of word":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  for i in 0 ..< 2:
    status.bufStatus[0].moveToForwardEndOfWord(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 6)

test "Move to forward end of word":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  status.bufStatus[0].buffer = initGapBuffer(@[ru"abc efg"])
  for i in 0 ..< 2:
    status.bufStatus[0].moveToForwardEndOfWord(currentMainWindowNode)
  check(currentMainWindowNode.currentColumn == 6)

test "Move to previous blank line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru"ghi"])
  currentMainWindowNode.currentLine = currentBufStatus.buffer.high

  currentBufStatus.moveToPreviousBlankLine(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 1
  check currentMainWindowNode.currentColumn == 0

test "Move to previous blank line 2":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"", ru"ghi"])
  currentMainWindowNode.currentLine = 2

  currentBufStatus.moveToPreviousBlankLine(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 0
  check currentMainWindowNode.currentColumn == 0

test "Move to previous blank line 3":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = initGapBuffer(@[ru"abc"])
  currentMainWindowNode.currentColumn = 2

  currentBufStatus.moveToPreviousBlankLine(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 0
  check currentMainWindowNode.currentColumn == 0

test "Move to next blank line":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"def", ru"", ru"ghi"])

  currentBufStatus.moveToNextBlankLine(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 2
  check currentMainWindowNode.currentColumn == 0

test "Move to next blank line 2":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = initGapBuffer(@[ru"abc", ru"", ru"def", ru"ghi"])
  currentMainWindowNode.currentLine = 1

  currentBufStatus.moveToNextBlankLine(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 3
  check currentMainWindowNode.currentColumn == 2

test "Move to next blank line 3":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = initGapBuffer(@[ru"abc"])

  currentBufStatus.moveToNextBlankLine(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 0
  check currentMainWindowNode.currentColumn == 2

test "Move to the top line of the screen":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = 7.newSeqWith(ru"").toGapBuffer

  status.resize(10, 10)
  status.update

  currentMainWindowNode.currentLine = currentBufStatus.buffer.high
  status.update

  currentBufStatus.moveToTopOfScreen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 0

test "Move to the top line of the screen 2":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = 20.newSeqWith(ru"").toGapBuffer

  status.resize(10, 10)
  status.update

  currentMainWindowNode.currentLine = currentBufStatus.buffer.high
  status.update

  currentBufStatus.moveToTopOfScreen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 13

test "Move to the center line of the screen":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = 7.newSeqWith(ru"").toGapBuffer

  status.resize(10, 10)
  status.update

  currentBufStatus.moveToCenterOfScreen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 3

test "Move to the center line of the screen 2":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = 20.newSeqWith(ru"").toGapBuffer

  status.resize(10, 10)

  currentMainWindowNode.currentLine = currentBufStatus.buffer.high
  status.update

  currentBufStatus.moveToCenterOfScreen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 16

test "Move to the bottom line of the screen":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = 7.newSeqWith(ru"").toGapBuffer

  status.resize(10, 10)
  status.update

  currentBufStatus.moveToBottomOfScreen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 6

test "Move to the bottom line of the screen 2":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = 2.newSeqWith(ru"").toGapBuffer

  status.resize(10, 10)
  status.update

  currentBufStatus.moveToBottomOfScreen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 1

test "Move to the bottom line of the screen 3":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = 20.newSeqWith(ru"").toGapBuffer

  status.resize(10, 10)

  currentMainWindowNode.currentLine = 15
  status.update

  currentBufStatus.moveToBottomOfScreen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 19

test "Move to matching pair of paren 1":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = @[ru"( )"].toGapBuffer

  status.resize(100, 100)
  status.update

  currentBufStatus.moveToPairOfParen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 0
  check currentMainWindowNode.currentColumn == 2

test "Move to matching pair of paren 2":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = @[ru"(", ru")"].toGapBuffer

  status.resize(100, 100)
  status.update

  currentBufStatus.moveToPairOfParen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 1
  check currentMainWindowNode.currentColumn == 0

test "Move to matching pair of paren 3":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = @[ru" )"].toGapBuffer

  status.resize(100, 100)
  status.update

  currentBufStatus.moveToPairOfParen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 0
  check currentMainWindowNode.currentColumn == 0

test "Move to matching pair of paren 4":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = @[ru"(", ru"", ru"]"].toGapBuffer

  status.resize(100, 100)
  status.update

  currentBufStatus.moveToPairOfParen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 0
  check currentMainWindowNode.currentColumn == 0

test "Move to matching pair of paren 5":
  var status = initEditorStatus()
  discard status.addNewBufferInCurrentWin.get
  currentBufStatus.buffer = @[ru"(", ru"", ru"]"].toGapBuffer
  currentMainWindowNode.currentColumn = currentBufStatus.buffer.len

  status.resize(100, 100)
  status.update

  currentBufStatus.moveToPairOfParen(currentMainWindowNode)

  check currentMainWindowNode.currentLine == 0
  check currentMainWindowNode.currentColumn == 0

suite "jumpToSearchForwardResults":
  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = initGapBuffer(@[
      "abc def",
      "ghi jkl",
      "mno jkl"].toSeqRunes)

    const Keyword = ru"jkl"
    currentBufStatus.jumpToSearchForwardResults(
      currentMainWindowNode,
      Keyword,
      status.settings.standard.ignorecase,
      status.settings.standard.smartcase)

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 4

  test "Basic 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = initGapBuffer(@[
      "abc def",
      "ghi jkl",
      "mno pqr"].toSeqRunes)

    const Keyword = ru"xyz"
    currentBufStatus.jumpToSearchForwardResults(
      currentMainWindowNode,
      Keyword,
      status.settings.standard.ignorecase,
      status.settings.standard.smartcase)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "With newline":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentMainWindowNode.currentColumn = 0
    currentBufStatus.buffer = @[
      "abc def",
      "ghi jkl",
      "mno pqr"]
      .toSeqRunes
      .toGapBuffer

    const Keyword = "jkl\nmno".toRunes
    currentBufStatus.jumpToSearchForwardResults(
      currentMainWindowNode,
      Keyword,
      status.settings.standard.ignorecase,
      status.settings.standard.smartcase)

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 4

suite "jumpToSearchBackwordResults":
  test "Basic":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentMainWindowNode.currentLine = 1
    currentBufStatus.buffer = initGapBuffer(@[
      "abc def",
      "ghi jkl",
      "mno abc"].toSeqRunes)

    const Keyword = ru"abc"
    currentBufStatus.jumpToSearchBackwordResults(
      currentMainWindowNode,
      Keyword,
      status.settings.standard.ignorecase,
      status.settings.standard.smartcase)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Basic 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentMainWindowNode.currentColumn = 1
    currentBufStatus.buffer = initGapBuffer(@[
      "abc def",
      "ghi jkl",
      "mno pqr"].toSeqRunes)

    const Keyword = ru"xyz"
    currentBufStatus.jumpToSearchBackwordResults(
      currentMainWindowNode,
      Keyword,
      status.settings.standard.ignorecase,
      status.settings.standard.smartcase)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 1

  test "With newline":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    currentMainWindowNode.currentLine = 2
    currentBufStatus.buffer = @[
      "abc def",
      "ghi jkl",
      "mno abc"]
      .toSeqRunes
      .initGapBuffer

    const Keyword = "def\nghi".toRunes
    currentBufStatus.jumpToSearchBackwordResults(
      currentMainWindowNode,
      Keyword,
      status.settings.standard.ignorecase,
      status.settings.standard.smartcase)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 4

suite "movement: moveToFirstWordOfPrevLine":
  test "Only whitespaces":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"  ", ru"  ", ru"  "])
    currentMainWindowNode.currentLine = 2

    status.resize(100, 100)
    status.update

    currentMainWindowNode.moveToFirstWordOfPrevLine(currentBufStatus)

    check currentMainWindowNode.currentLine == 2
    check currentMainWindowNode.currentColumn == 0

  test "Nothing to do":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"  word", ru"  ", ru"  "])
    currentMainWindowNode.currentLine = 2
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    currentMainWindowNode.moveToFirstWordOfPrevLine(currentBufStatus)

    check currentMainWindowNode.currentLine == 2
    check currentMainWindowNode.currentColumn == 1

  test "Move to the prev first word 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"  word", ru"  "])
    currentMainWindowNode.currentLine = 1

    status.resize(100, 100)
    status.update

    currentMainWindowNode.moveToFirstWordOfPrevLine(currentBufStatus)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 2

  test "Move to the prev first word 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"word", ru"  "])
    currentMainWindowNode.currentLine = 1
    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    currentMainWindowNode.moveToFirstWordOfPrevLine(currentBufStatus)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

suite "movement: moveToFirstWordOfNextLine":
  test "Only whitespaces":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"  ", ru"  ", ru"  "])
    currentMainWindowNode.currentLine = 0

    status.resize(100, 100)
    status.update

    currentMainWindowNode.moveToFirstWordOfNextLine(currentBufStatus)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Nothing to do":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"  ", ru"  ", ru"  word"])
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0

    status.resize(100, 100)
    status.update

    currentMainWindowNode.moveToFirstWordOfNextLine(currentBufStatus)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Move to the next first word 1":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"  ", ru"  word"])
    currentMainWindowNode.currentLine = 0

    status.resize(100, 100)
    status.update

    currentMainWindowNode.moveToFirstWordOfNextLine(currentBufStatus)

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 2

  test "Move to the next first word 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get
    currentBufStatus.buffer = toGapBuffer(@[ru"  ", ru"word"])
    currentMainWindowNode.currentLine = 0
    currentMainWindowNode.currentColumn = 0

    status.resize(100, 100)
    status.update

    currentMainWindowNode.moveToFirstWordOfNextLine(currentBufStatus)

    check currentMainWindowNode.currentLine == 1
    check currentMainWindowNode.currentColumn == 0
