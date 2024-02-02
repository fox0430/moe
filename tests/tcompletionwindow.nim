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
               windownode, gapbuffer, editorstatus]

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

suite "completionwindow: removeInsertedText":
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

suite "completionwindow: insertSelectedText":
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

suite "completionwindow: handleKey":
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

suite "completionwindow: completionWindowPosition":
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

    check Position(y: 1, x: 0) == completionWindowPosition(
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

    check completionWindowPosition(currentMainWindowNode, currentBufStatus) ==
      Position(y: 7, x: 7)
