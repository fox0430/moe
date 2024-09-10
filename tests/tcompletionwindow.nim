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

import std/[unittest, options, sequtils]

import pkg/results

import moepkg/[unicodeext, completion, independentutils, bufferstatus, ui,
               windownode, gapbuffer, editorstatus, commandline]

import utils

import moepkg/completionwindow {.all.}

suite "completionwindow: selectedText":
  var list: CompletionList

  setup:
    list = initCompletionList()
    list.add CompletionItem(label: ru"ab", insertText: ru"ab")
    list.add CompletionItem(label: ru"ac", insertText: ru"ac")
    list.add CompletionItem(label: ru"ad", insertText: ru"ad")

  test "Return input":
    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")

    check c.selectedIndex == -1
    check c.selectedText == ru"a"

  test "Return suggestion":
    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")

    c.selectedIndex = 1

    check c.selectedText == ru"ac"

suite "completionwindow: prev":
  var list: CompletionList

  setup:
    list = initCompletionList()
    list.add CompletionItem(label: ru"ab", insertText: ru"ab")
    list.add CompletionItem(label: ru"ac", insertText: ru"ac")
    list.add CompletionItem(label: ru"ad", insertText: ru"ad")

  test "Basic":
    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")

    c.selectedIndex = 2

    block:
      c.prev
      check c.selectedIndex == 1

    block:
      c.prev
      check c.selectedIndex == 0

    block:
      c.prev
      check c.selectedIndex == -1

    block:
      c.prev
      check c.selectedIndex == 2

suite "completionwindow: next":
  var list: CompletionList

  setup:
    list = initCompletionList()
    list.add CompletionItem(label: ru"ab", insertText: ru"ab")
    list.add CompletionItem(label: ru"ac", insertText: ru"ac")
    list.add CompletionItem(label: ru"ad", insertText: ru"ad")

  test "Basic":
    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")

    block:
      c.next
      check c.selectedIndex == 0

    block:
      c.next
      check c.selectedIndex == 1

    block:
      c.next
      check c.selectedIndex == 2

    block:
      c.next
      check c.selectedIndex == -1

suite "completionwindow: removeInsertedText in editor":
  test "Remove input text":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @["a"].toSeqRunes.toGapBuffer

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      inputText = ru"a")

    bufStatus.removeInsertedText(c)
    check bufStatus.buffer.toSeqRunes == @[""].toSeqRunes

  test "Remove input text 2":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @["abc", "def ghi"].toSeqRunes.toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"ggg", insertText: ru"ggg")

    var c = initCompletionWindow(
      BufferPosition(line: 1, column: 4),
      list = list,
      inputText = ru"ghi")

    bufStatus.removeInsertedText(c)
    check bufStatus.buffer.toSeqRunes == @["abc", "def "].toSeqRunes

  test "Remove suggestion":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @["abc"].toSeqRunes.toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"abc", insertText: ru"abc")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")
    c.selectedIndex = 0

    bufStatus.removeInsertedText(c)
    check bufStatus.buffer.toSeqRunes == @[""].toSeqRunes

  test "Remove suggestion 2":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @["abc", "def ghi"].toSeqRunes.toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"ghi", insertText: ru"ghi")

    var c = initCompletionWindow(
      BufferPosition(line: 1, column: 4),
      list = list,
      inputText = ru"g")
    c.selectedIndex = 0

    bufStatus.removeInsertedText(c)
    check bufStatus.buffer.toSeqRunes == @["abc", "def "].toSeqRunes

  test "Multiple lines":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @["abc xyz", "defgxyzhi", "", "jkl xyz"]
      .toSeqRunes
      .toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"xyz", insertText: ru"xyz")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 4),
      list = list,
      inputText = ru"x")
    c.selectedIndex = 0

    const Lines = @[0, 1, 2, 3]
    bufStatus.removeInsertedText(c, Lines)
    check bufStatus.buffer.toSeqRunes == @["abc ", "defghi", "", "jkl "]
      .toSeqRunes

suite "completionwindow: removeInsertedText in command line":
  test "Remove input text":
    var commandLine = initCommandLine()
    commandLine.insert(ru'a')

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      inputText = ru"a")

    commandLine.removeInsertedText(c)
    check commandLine.buffer == ru""

  test "Remove input text 2":
    var commandLine = initCommandLine()
    commandLine.insert(ru"abc d")

    var list = initCompletionList()
    list.add CompletionItem(label: ru"def", insertText: ru"def")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 4),
      list = list,
      inputText = ru"d")

    commandLine.removeInsertedText(c)
    check commandLine.buffer == ru"abc "

  test "Remove suggestion":
    var commandLine = initCommandLine()
    commandLine.insert(ru"abc")

    var list = initCompletionList()
    list.add CompletionItem(label: ru"abc", insertText: ru"abc")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")
    c.selectedIndex = 0

    commandLine.removeInsertedText(c)
    check commandLine.buffer == ru""

  test "Remove suggestion 2":
    var commandLine = initCommandLine()
    commandLine.insert(ru"abc def")

    var list = initCompletionList()
    list.add CompletionItem(label: ru"def", insertText: ru"def")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 4),
      list = list,
      inputText = ru"d")
    c.selectedIndex = 0

    commandLine.removeInsertedText(c)
    check commandLine.buffer == ru"abc "

suite "completionwindow: insertSelectedText in editor":
  test "Insert input text":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @[""].toSeqRunes.toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"abc", insertText: ru"abc")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")

    bufStatus.insertSelectedText(c)
    check bufStatus.buffer.toSeqRunes == @["a"].toSeqRunes

  test "Insert input text 2":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @["abc", "def "].toSeqRunes.toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"ggg", insertText: ru"ggg")

    var c = initCompletionWindow(
      BufferPosition(line: 1, column: 4),
      list = list,
      inputText = ru"gg")

    bufStatus.insertSelectedText(c)
    check bufStatus.buffer.toSeqRunes == @["abc", "def gg"].toSeqRunes

  test "Insert suggestion":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @[""].toSeqRunes.toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"abc", insertText: ru"abc")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")
    c.selectedIndex = 0

    bufStatus.insertSelectedText(c)
    check bufStatus.buffer.toSeqRunes == @["abc"].toSeqRunes

  test "Insert suggestion 2":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @["abc", "def "].toSeqRunes.toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"ghi", insertText: ru"ghi")

    var c = initCompletionWindow(
      BufferPosition(line: 1, column: 4),
      list = list,
      inputText = ru"g")
    c.selectedIndex = 0

    bufStatus.insertSelectedText(c)
    check bufStatus.buffer.toSeqRunes == @["abc", "def ghi"].toSeqRunes

  test "Multiple lines":
    var bufStatus = initBufferStatus("").get
    bufStatus.buffer = @["abc ", "defghi", "", "jkl "].toSeqRunes.toGapBuffer

    var list = initCompletionList()
    list.add CompletionItem(label: ru"xyz", insertText: ru"xyz")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 4),
      list = list,
      inputText = ru"x")
    c.selectedIndex = 0

    const Lines = @[0, 1, 2, 3]
    bufStatus.insertSelectedText(c, Lines)
    check bufStatus.buffer.toSeqRunes == @["abc xyz", "defgxyzhi", "", "jkl xyz"]
      .toSeqRunes

suite "completionwindow: insertSelectedText in command line":
  test "Insert input text":
    var commandLine = initCommandLine()

    var list = initCompletionList()
    list.add CompletionItem(label: ru"abc", insertText: ru"abc")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")

    commandLine.insertSelectedText(c)
    check commandLine.buffer == ru"a"

  test "Insert input text 2":
    var commandLine = initCommandLine()
    commandLine.buffer = ru"abc "

    var list = initCompletionList()
    list.add CompletionItem(label: ru"def", insertText: ru"def")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 4),
      list = list,
      inputText = ru"d")

    commandLine.insertSelectedText(c)
    check commandLine.buffer == ru"abc d"

  test "Insert suggestion":
    var commandLine = initCommandLine()

    var list = initCompletionList()
    list.add CompletionItem(label: ru"abc", insertText: ru"abc")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")
    c.selectedIndex = 0

    commandLine.insertSelectedText(c)
    check commandLine.buffer == ru"abc"

  test "Insert suggestion 2":
    var commandLine = initCommandLine()
    commandLine.buffer.insert(ru"abc ")

    var list = initCompletionList()
    list.add CompletionItem(label: ru"def", insertText: ru"def")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 4),
      list = list,
      inputText = ru"d")
    c.selectedIndex = 0

    commandLine.insertSelectedText(c)
    check commandLine.buffer == ru"abc def"

suite "completionwindow: handleKey in editor":
  test "Next suggest":
    for key in @[TabKey, DownKey]:
      var bufStatus = initBufferStatus("").get
      bufStatus.buffer = @["a"].toSeqRunes.toGapBuffer

      var winNode = initWindowNode()

      var list = initCompletionList()
      list.add CompletionItem(label: ru"ab", insertText: ru"ab")
      list.add CompletionItem(label: ru"ac", insertText: ru"ac")
      list.add CompletionItem(label: ru"ad", insertText: ru"ad")

      var c = initCompletionWindow(
        BufferPosition(line: 0, column: 0),
        list = list,
        inputText = ru"a")

      c.handleKey(bufStatus, winNode, key.Rune)
      check c.selectedIndex == 0
      check bufStatus.buffer.toSeqRunes == @["ab"].toSeqRunes
      check bufStatus.isUpdate
      check winNode.currentColumn == 2

  test "Next suggest 2":
    for key in @[TabKey, DownKey]:
      var bufStatus = initBufferStatus("").get
      bufStatus.buffer = @["ad"].toSeqRunes.toGapBuffer

      var winNode = initWindowNode()

      var list = initCompletionList()
      list.add CompletionItem(label: ru"ab", insertText: ru"ab")
      list.add CompletionItem(label: ru"ac", insertText: ru"ac")
      list.add CompletionItem(label: ru"ad", insertText: ru"ad")

      var c = initCompletionWindow(
        BufferPosition(line: 0, column: 0),
        list = list,
        inputText = ru"a")
      c.selectedIndex = 2

      c.handleKey(bufStatus, winNode, key.Rune)
      check c.selectedIndex == -1
      check bufStatus.buffer.toSeqRunes == @["a"].toSeqRunes
      check bufStatus.isUpdate
      check winNode.currentColumn == 1

  test "Prev suggest":
    for key in @[ShiftTab, UpKey]:
      var bufStatus = initBufferStatus("").get
      bufStatus.buffer = @["ad"].toSeqRunes.toGapBuffer

      var winNode = initWindowNode()

      var list = initCompletionList()
      list.add CompletionItem(label: ru"ab", insertText: ru"ab")
      list.add CompletionItem(label: ru"ac", insertText: ru"ac")
      list.add CompletionItem(label: ru"ad", insertText: ru"ad")

      var c = initCompletionWindow(
        BufferPosition(line: 0, column: 0),
        list = list,
        inputText = ru"a")
      c.selectedIndex = 2

      c.handleKey(bufStatus, winNode, key.Rune)
      check c.selectedIndex == 1
      check bufStatus.buffer.toSeqRunes == @["ac"].toSeqRunes
      check bufStatus.isUpdate
      check winNode.currentColumn == 2

  test "Prev suggest 2":
    for key in @[ShiftTab, UpKey]:
      var bufStatus = initBufferStatus("").get
      bufStatus.buffer = @["ab"].toSeqRunes.toGapBuffer

      var winNode = initWindowNode()

      var list = initCompletionList()
      list.add CompletionItem(label: ru"ab", insertText: ru"ab")
      list.add CompletionItem(label: ru"ac", insertText: ru"ac")
      list.add CompletionItem(label: ru"ad", insertText: ru"ad")

      var c = initCompletionWindow(
        BufferPosition(line: 0, column: 0),
        list = list,
        inputText = ru"a")
      c.selectedIndex = 0

      c.handleKey(bufStatus, winNode, key.Rune)
      check c.selectedIndex == -1
      check bufStatus.buffer.toSeqRunes == @["a"].toSeqRunes
      check bufStatus.isUpdate
      check winNode.currentColumn == 1

  test "Next suggest":
    for key in @[TabKey, DownKey]:
      var commandLine = initCommandLine()
      commandLine.insert(ru'a')

      var list = initCompletionList()
      list.add CompletionItem(label: ru"ab", insertText: ru"ab")
      list.add CompletionItem(label: ru"ac", insertText: ru"ac")
      list.add CompletionItem(label: ru"ad", insertText: ru"ad")

      var c = initCompletionWindow(
        BufferPosition(line: 0, column: 0),
        list = list,
        inputText = ru"a")

      c.handleKey(commandLine, key.Rune)
      check c.selectedIndex == 0
      check commandLine.buffer == ru"ab"
      check commandLine.isUpdate

  test "Next suggest 2":
    for key in @[TabKey, DownKey]:
      var commandLine = initCommandLine()
      commandLine.insert(ru"ad")

      var list = initCompletionList()
      list.add CompletionItem(label: ru"ab", insertText: ru"ab")
      list.add CompletionItem(label: ru"ac", insertText: ru"ac")
      list.add CompletionItem(label: ru"ad", insertText: ru"ad")

      var c = initCompletionWindow(
        BufferPosition(line: 0, column: 0),
        list = list,
        inputText = ru"a")
      c.selectedIndex = 2

      c.handleKey(commandLine, key.Rune)
      check c.selectedIndex == -1
      check commandLine.buffer == ru"a"
      check commandLine.isUpdate

  test "Prev suggest":
    for key in @[ShiftTab, UpKey]:
      var commandLine = initCommandLine()
      commandLine.insert(ru"ad")

      var list = initCompletionList()
      list.add CompletionItem(label: ru"ab", insertText: ru"ab")
      list.add CompletionItem(label: ru"ac", insertText: ru"ac")
      list.add CompletionItem(label: ru"ad", insertText: ru"ad")

      var c = initCompletionWindow(
        BufferPosition(line: 0, column: 0),
        list = list,
        inputText = ru"a")
      c.selectedIndex = 2

      c.handleKey(commandLine, key.Rune)
      check c.selectedIndex == 1
      check commandLine.buffer == ru"ac"
      check commandLine.isUpdate

  test "Prev suggest 2":
    for key in @[ShiftTab, UpKey]:
      var commandLine = initCommandLine()
      commandLine.insert(ru"ab")

      var winNode = initWindowNode()

      var list = initCompletionList()
      list.add CompletionItem(label: ru"ab", insertText: ru"ab")
      list.add CompletionItem(label: ru"ac", insertText: ru"ac")
      list.add CompletionItem(label: ru"ad", insertText: ru"ad")

      var c = initCompletionWindow(
        BufferPosition(line: 0, column: 0),
        list = list,
        inputText = ru"a")
      c.selectedIndex = 0

      c.handleKey(commandLine, key.Rune)
      check c.selectedIndex == -1
      check commandLine.buffer == ru"a"
      check commandLine.isUpdate

suite "completionwindow: updateBuffer":
  test "Basic":
    var list = initCompletionList()
    list.add CompletionItem(label: ru"ab", insertText: ru"ab")
    list.add CompletionItem(label: ru"ac", insertText: ru"ac")
    list.add CompletionItem(label: ru"ad", insertText: ru"ad")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")

    c.popupwindow.get.buffer = @["xyz"].toSeqRunes

    c.updateBuffer
    check c.popupwindow.get.buffer == @[" ab ", " ac ", " ad "].toSeqRunes

  test "Basic 2":
    var list = initCompletionList()
    list.add CompletionItem(label: ru"abcdef", insertText: ru"abc")
    list.add CompletionItem(label: ru"abcghi", insertText: ru"abc")

    var c = initCompletionWindow(
      BufferPosition(line: 0, column: 0),
      list = list,
      inputText = ru"a")

    c.popupwindow.get.buffer = @["a"].toSeqRunes

    c.updateBuffer
    check c.popupwindow.get.buffer == @[" abcdef ", " abcghi "].toSeqRunes

suite "completionwindow: completionWindowPositionInEditor":
  test "Basic":
    var status = initEditorStatus()

    status.settings.view.lineNumber = false
    status.settings.view.sidebar = false
    status.settings.tabLine.enable = false

    discard status.addNewBufferInCurrentWin
    currentBufStatus.buffer = @["a"].toSeqRunes.toGapBuffer
    currentBufStatus.mode = Mode.insert

    currentMainWindowNode.currentColumn = 1

    status.resize(100, 100)
    status.update

    check Position(y: 1, x: 0) == completionWindowPositionInEditor(
      currentMainWindowNode,
      currentBufStatus)

  test "Basic 2":
    var status = initEditorStatus()

    status.settings.view.lineNumber = true
    status.settings.view.sidebar = true
    status.settings.tabLine.enable = true

    discard status.addNewBufferInCurrentWin
    currentBufStatus.buffer = toSeq(0 .. 9)
      .mapIt(it.toRunes & ru"abc")
      .toGapBuffer
    currentBufStatus.mode = Mode.insert

    currentMainWindowNode.currentLine = 5
    currentMainWindowNode.currentColumn = 4

    status.resize(100, 100)
    status.update

    check Position(y: 7, x: 7) == completionWindowPositionInEditor(
      currentMainWindowNode,
      currentBufStatus,
      ru"a")
