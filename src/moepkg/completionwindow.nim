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

import std/[options, sequtils, deques]

import ui, unicodeext, independentutils, completion, popupwindow, bufferstatus,
       windownode, gapbuffer, worddictionary, editor

export popupwindow

type
  CompletionWindow* = ref object
    popupWindow*: Option[PopupWindow]
      # The popup window for completion items.
    firstDisplayItemIndex: int
      # The index of first item to display.
    startPosition: BufferPosition
      # The first position of inserting text.
    inputText*: Runes
      # The text entered by the user.
    list*: CompletionList
      # Completion items
    selectedIndex*: int
      # Index of the selected item. If -1, no selection.

proc initCompletionWindow*(
  startPosition: BufferPosition,
  windowPosition: Position = Position(y: 0, x: 0),
  size: Size = Size(h: 1, w: 1),
  list: CompletionList = initCompletionList(),
  inputText: Runes = ru""): CompletionWindow =

    CompletionWindow(
      startPosition: startPosition,
      popupWindow: some(initPopupWindow(windowPosition, size)),
      list: list,
      inputText: inputText,
      selectedIndex: -1)

proc isPathCompletion*(c: CompletionWindow): bool {.inline.} =
  c.inputText.isPathCompletion

proc startLine*(c: CompletionWindow): int {.inline.} =
  c.startPosition.line

proc startColumn*(c: CompletionWindow): int {.inline.} =
  c.startPosition.column

proc listHigh*(c: CompletionWindow): int {.inline.} = c.list.high

proc listLen*(c: CompletionWindow): int {.inline.} = c.list.len

proc autoMoveAndResize*(
  c: var CompletionWindow,
  min, max: Position) {.inline.} =

    if c.popupWindow.isSome:
      c.popupWindow.get.autoMoveAndResize(min, max)

proc addInput*(c: var CompletionWindow, r: Rune | Runes) {.inline.} =
  c.inputText &= r

proc setInput*(c: var CompletionWindow, r: Runes) {.inline.} =
  c.inputText = r

proc removeInput*(c: var CompletionWindow) {.inline.} =
  if c.inputText.len > 0:
    c.inputText.del(c.inputText.high)

proc setList*(c: var CompletionWindow, list: CompletionList) {.inline.} =
  c.list = list

proc setList*(
  c: var CompletionWindow,
  dictionary: WordDictionary) =

    c.list = initCompletionList()
    for word in dictionary.collect(c.inputText):
      c.list.add CompletionItem(label: word, insertText: word)

proc selectedText*(c: CompletionWindow): Runes =
  if c.selectedIndex == -1:
    return c.inputText
  else:
    return c.list[c.selectedIndex].insertText

proc inputText*(c: var CompletionWindow): Runes {.inline.} = c.inputText

proc prev*(c: var CompletionWindow) =
  if c.selectedIndex == -1:
    c.selectedIndex = c.list.items.high
    c.popupWindow.get.currentLine = none(int)
  else:
    c.selectedIndex.dec
    c.popupWindow.get.currentLine = some(c.selectedIndex)

proc next*(c: var CompletionWindow) =
  if c.selectedIndex == c.list.items.high:
    c.selectedIndex = -1
    c.popupWindow.get.currentLine = none(int)
  else:
    c.selectedIndex.inc
    c.popupWindow.get.currentLine = some(c.selectedIndex)

proc removeInsertedText*(
  bufStatus: var BufferStatus,
  completionWindow: CompletionWindow) =
    ## Remove text temporarily inserted by completion.

    var newLine = bufStatus.buffer[completionWindow.startPosition.line]
    let
      first = completionWindow.startPosition.column
      last = first + completionWindow.selectedText.high
    newLine.delete(first .. last)

    if bufStatus.buffer[completionWindow.startPosition.line] != newLine:
      bufStatus.buffer[completionWindow.startPosition.line] = newLine

proc removeInsertedText*(
  bufStatus: var BufferStatus,
  completionWindow: CompletionWindow,
  lines: seq[int]) =
    ## Remove text temporarily inserted by completion.

    for lineNum in lines:
      var newLine = bufStatus.buffer[lineNum]
      if newLine.high - completionWindow.inputText.len > 0:
        let
          first = completionWindow.startPosition.column
          last = first + completionWindow.selectedText.high
        newLine.delete(first .. last)

        if bufStatus.buffer[lineNum] != newLine:
          bufStatus.buffer[lineNum] = newLine

proc insertSelectedText*(
  bufStatus: var BufferStatus,
  completionWindow: CompletionWindow) =
    # Insert the selected text to the line.

    var newLine = bufStatus.buffer[completionWindow.startPosition.line]
    let text = completionWindow.selectedText
    for i in 0 .. text.high:
      newLine.insert(text[i], completionWindow.startPosition.column + i)

    if bufStatus.buffer[completionWindow.startPosition.line] != newLine:
      bufStatus.buffer[completionWindow.startPosition.line] = newLine

proc insertSelectedText*(
  bufStatus: var BufferStatus,
  completionWindow: CompletionWindow,
  lines: seq[int]) =
    # Insert the selected text to multiple lines.

    let positons = lines.mapIt(BufferPosition(
      line: it,
      column: completionWindow.startColumn))
    bufStatus.insertMultiplePositions(
      positons,
      completionWindow.selectedText)

template canHandleInCompletionWindow*(key: Rune): bool =
  isTabKey(key) or
  isShiftTab(key) or
  isUpKey(key) or
  isDownKey(key)

proc handleKey*(
  c: var CompletionWindow,
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  key: Rune) =

    when not defined(release):
      doAssert(canHandleInCompletionWindow(key))

    if isTabKey(key) or isDownKey(key):
      if c.list.len > 0:
        # Move to the next item and inserting text.
        if bufStatus.isInsertMultiMode:
          let lines = bufStatus.selectedArea.get.selectedLineNumbers
          bufStatus.removeInsertedText(c, lines)
          c.next
          bufStatus.insertSelectedText(c, lines)
        else:
          bufStatus.removeInsertedText(c)
          c.next
          bufStatus.insertSelectedText(c)

        # Move cursor to the last position of the inserted text.
        windowNode.currentColumn = c.startPosition.column + c.selectedText.len

        bufStatus.isUpdate = true
    elif isShiftTab(key) or isUpKey(key):
      if c.list.len > 0:
        # Move to the prev item and inserting text.
        if bufStatus.isInsertMultiMode:
          let lines = bufStatus.selectedArea.get.selectedLineNumbers
          bufStatus.removeInsertedText(c, lines)
          c.prev
          bufStatus.insertSelectedText(c, lines)
        else:
          bufStatus.removeInsertedText(c)
          c.prev
          bufStatus.insertSelectedText(c)

        # Move cursor to the last position of the inserted text.
        windowNode.currentColumn = c.startPosition.column + c.selectedText.len

        bufStatus.isUpdate = true

proc resize*(c: var CompletionWindow, size: Size) {.inline.} =
  if c.popupWindow.isSome: c.popupWindow.get.resize(size)

proc updateBuffer*(c: var CompletionWindow) =
  ## Update display buffer.

  if c.popupWindow.isSome:
    c.popupWindow.get.buffer = @[]

    for item in c.list.items:
      c.popupWindow.get.buffer.add ru" " & item.insertText & ru" "

proc update*(c: var CompletionWindow) {.inline.} =
  c.popupWindow.get.update

proc close*(c: var CompletionWindow) {.inline.} =
  if c.popupWindow.isSome:
    c.popupWindow.get.close
    c.popupWindow = none(PopupWindow)

proc reopen*(
  c: var CompletionWindow,
  windowPosition: Position = Position(y: 0, x: 0),
  size: Size = Size(h: 1, w: 1)) =

    c.popupWindow = some(initPopupWindow(windowPosition, size))

proc isOpen*(c: CompletionWindow): bool {.inline.} = c.popupWindow.isSome

proc completionWindowPosition*(
  windowNode: var WindowNode,
  bufStatus: BufferStatus): Position =
    ## Return a position for the completion window.

    # Reload Editorview. This is not the actual terminal view.
    windowNode.reloadEditorView(bufStatus.buffer)
    # Seek cursor before getting the absolute cursor position.
    windowNode.seekCursor(bufStatus.buffer)

    let absCursorPositon = windowNode.absolutePosition
    return Position(
      y: (absCursorPositon.y + 1).clamp(0, getTerminalHeight()),
      x: (absCursorPositon.x - 2).clamp(0, getTerminalWidth()))
