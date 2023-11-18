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

import std/[unittest, random, options, sequtils, sugar, importutils]
import pkg/results
import moepkg/[highlight, editorstatus, gapbuffer, unicodeext, editor,
               bufferstatus, movement, autocomplete, windownode, ui]

import moepkg/suggestionwindow {.all.}

proc resize(status: var EditorStatus, h, w: int) =
  updateTerminalSize(h, w)
  status.resize

suite "Insert mode":
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

  proc prepareInsertMode(
    buffer: openArray[string],
    line, column, height, width: int): EditorStatus =

      result = initEditorStatus()
      result.settings.view.sidebar = false
      discard result.addNewBufferInCurrentWin(Mode.insert).get
      result.bufStatus[0].buffer = initGapBuffer(buffer.map(s => s.ru))
      result.mainWindow.currentMainWindowNode.currentLine = line
      result.mainWindow.currentMainWindowNode.currentColumn = column
      result.resize(height, width)
      result.update

  test "General-purpose autocomplete window position 1":
    const Buffer = @["a", "aba", "abb", "abc", "abd", "abe", "abf"]
    var status = prepareInsertMode(
      Buffer,
      0,
      1,
      100,
      100)

    var dictionary: WordDictionary
    let currentBufferIndex = currentMainWindowNode.bufferIndex
    var suggestionWindow = tryOpenSuggestionWindow(
      dictionary,
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    let
      mainWindowHeight = status.settings.getMainWindowHeight
      (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(
        currentMainWindowNode,
        mainWindowHeight)

    const
      IsEnableStatusLine = true
      MainWindowNodeY = 2
    suggestionWindow.get.writeSuggestionWindow(
      currentMainWindowNode,
      y, x,
      MainWindowNodeY,
      IsEnableStatusLine)

    check y == 2
    check x == 1

  test "General-purpose autocomplete window position 2":
    const
      Buffer = @["aba", "abb", "abc", "abcd", "", "a"]
      TerminalHeight = 10
    var status = prepareInsertMode(
      Buffer,
      Buffer.high,
      1,
      TerminalHeight,
      100)

    var dictionary: WordDictionary
    let currentBufferIndex =currentMainWindowNode.bufferIndex
    var suggestionWindow = tryOpenSuggestionWindow(
      dictionary,
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    let
      mainWindowHeight = status.settings.getMainWindowHeight
      (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(
        currentMainWindowNode,
        mainWindowHeight)

    const
      IsEnableStatusLine = true
      MainWindowNodeY = 2
    suggestionWindow.get.writeSuggestionWindow(
      currentMainWindowNode,
      y, x,
      MainWindowNodeY,
      IsEnableStatusLine)

    check y == 2
    check x == 1

  test "General-purpose autocomplete (Fix #1032)":
    const Buffer = @[
      "import os, unicode, times",
      "import"]
    var status = prepareInsertMode(
      Buffer,
      0,
      1,
      100,
      100)

    var dictionary: WordDictionary
    let currentBufferIndex =currentMainWindowNode.bufferIndex
    var suggestionWindow = tryOpenSuggestionWindow(
      dictionary,
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    let
      mainWindowHeight = status.settings.getMainWindowHeight
      (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(
        currentMainWindowNode,
        mainWindowHeight)

    const
      IsEnableStatusLine = true
      MainWindowNodeY = 2
    suggestionWindow.get.writeSuggestionWindow(
      currentMainWindowNode,
      y, x,
      MainWindowNodeY,
      IsEnableStatusLine)

  test "General-purpose autocomplete (the cursor position): Selecting a suggestion which is length 1 when the buffer contains some lines.":
    const Buffer = @["", "", "a"]
    var status = prepareInsertMode(
      Buffer,
      0,
      0,
      100,
      100)

    insertCharacter(
      currentBufStatus,
      currentMainWindowNode,
      status.settings.standard.autoCloseParen,
      ru'a')

    var dictionary: WordDictionary
    let currentBufferIndex =currentMainWindowNode.bufferIndex
    var suggestionWindow = tryOpenSuggestionWindow(
      dictionary,
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    status.update

    suggestionWindow.get.handleKeyInSuggestionWindow(
      currentBufStatus,
      currentMainWindowNode,
      ru'\t')

    check currentMainWindowNode.currentLine == 0

  test "General-purpose autocomplete (the cursor position): Selecting a suggestion which is length 1 when the buffer contains a line.":
    const Buffer = @[" a"]
    var status = prepareInsertMode(
      Buffer,
      0,
      0,
      100,
      100)

    insertCharacter(
      currentBufStatus,
      currentMainWindowNode,
      status.settings.standard.autoCloseParen,
      ru'a')

    var dictionary: WordDictionary
    let currentBufferIndex =currentMainWindowNode.bufferIndex
    var suggestionWindow = tryOpenSuggestionWindow(
      dictionary,
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    status.update

    suggestionWindow.get.handleKeyInSuggestionWindow(
      currentBufStatus,
      currentMainWindowNode,
      ru'\t')

    check currentMainWindowNode.currentColumn == 1

  test "General-purpose autocomplete: Check window position and height 1 (Fix #1049)":
    # Generate random string start with "a" and add to buffer
    var buffer: seq[string] = @["a"]
    # Generate the number of strings more than the window height
    for i in 0 ..< 110:
      var randStr = ""
      for _ in 0 .. 10: add(randStr, char(rand(int('A') .. int('z'))))
      buffer.add("a" & randStr)

    const
      Line = 0
      Column = 1
      TerminalHeight = 100
      TerminalWidth = 100
    var status = prepareInsertMode(
      buffer,
      Line,
      Column,
      TerminalHeight,
      TerminalWidth)

    status.settings.tabLine.enable = true
    status.settings.statusLine.enable = true

    var dictionary: WordDictionary
    let currentBufferIndex =currentMainWindowNode.bufferIndex
    var suggestionWindow = tryOpenSuggestionWindow(
      dictionary,
      status.bufStatus,
      currentBufferIndex,
      mainWindowNode,
      currentMainWindowNode)

    const MainWindowNodeY = 1
    let
      mainWindowHeight = status.settings.getMainWindowHeight
      (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(
        currentMainWindowNode,
        mainWindowHeight)
    suggestionWindow.get.writeSuggestionWindow(
      currentMainWindowNode,
      y, x,
      MainWindowNodeY,
      status.settings.statusLine.enable)

    privateAccess(suggestionWindow.get.type)

    check suggestionWindow.get.popUpWindow.get.position.y == 2
    check suggestionWindow.get.popUpWindow.get.size.h == TerminalHeight - 4
