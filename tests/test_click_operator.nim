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

## Tests for a click with an operator waiting. Each result is Vim's.

import std/[unittest, options, strutils, tables]

import pkg/results

import
  ../src/moepkg/[
    buffer, types, modes, editor, config, key_bindings, handler, registers,
    frontend_input, pending_input, macro_recording, key_router,
  ]

proc pos(line, column: int): BufferPosition =
  BufferPosition(line: line, column: column)

proc createTestEditor(text = "abcdefgh\nijklmnop"): Editor =
  let config = newEditorConfig()
  config.clipboard.enable = false
  result = newEditor(config)
  discard result.activeBuffer.insertText(pos(0, 0), text)
  result.activeWindow.cursor = pos(0, 0)
  result.config.standard.mouse = true
  result.activeWindow.viewport.width = 80
  result.activeWindow.viewport.height = 24
  result.state.showTabLine = false
  result.state.showLineNumbers = false
  result.state.showSidebar = false

proc press(e: Editor, keys: varargs[string]) =
  for key in keys:
    check e.handleKeyCombo(parseKeyCombo(key).get)

const NoModifiers: set[KeyModifier] = {}

proc click(e: Editor, row, column: int) =
  check e.handlePointerInput(initPointerInput(row, column))
  discard e.handlePointerInput(initPointerInput(row, column, action = paRelease))

suite "A click with an operator waiting":
  test "deletes up to the click":
    let e = createTestEditor()
    e.press("d")
    e.click(0, 4)

    check e.activeBuffer.getLine(0) == "efgh"
    check e.cursor == pos(0, 0)
    check e.state.registers.getRegisterContent('"') == "abcd"
    check e.state.pendingInput.pendingOperator.isNone
    e.press("l")
    check e.activeBuffer.getLine(0) == "efgh"
    check e.cursor == pos(0, 1)
    e.press("u")
    check e.activeBuffer.getLine(0) == "abcdefgh"

  test "deletes back to the click":
    let e = createTestEditor()
    e.press("$", "d")
    e.click(0, 2)

    check e.activeBuffer.getLine(0) == "abh"
    check e.cursor == pos(0, 2)

  test "deletes over lines":
    let e = createTestEditor()
    e.press("d")
    e.click(1, 2)

    check e.activeBuffer.len == 1
    check e.activeBuffer.getLine(0) == "klmnop"

  test "an end at a line start stops at the line before":
    let e = createTestEditor()
    e.press("l", "d")
    e.click(1, 0)

    check e.activeBuffer.len == 2
    check e.activeBuffer.getLine(0) == "a"

  test "a click past the end of the line takes all of it":
    let e = createTestEditor()
    e.press("d")
    e.click(0, 40)

    check e.activeBuffer.len == 2
    check e.activeBuffer.getLine(0) == ""

  test "past the end takes the last character, on it does not":
    block:
      let e = createTestEditor()
      e.press("j", "l", "l", "d")
      e.click(0, 29)
      check e.activeBuffer.getLine(0) == "abcdefglmnop"
      check e.state.registers.getRegisterContent('"') == "h\nijk"
    block:
      let e = createTestEditor()
      e.press("j", "l", "l", "d")
      e.click(0, 7)
      check e.activeBuffer.getLine(0) == "abcdefgklmnop"
    block:
      let e = createTestEditor()
      e.press("l", "l", "d")
      e.click(1, 29)
      check e.activeBuffer.len == 1
      check e.activeBuffer.getLine(0) == "ab"
    block:
      let e = createTestEditor()
      e.press("$", "d")
      e.click(0, 29)
      check e.activeBuffer.getLine(0) == "abcdefg"

  test "past the end of an empty line":
    proc after(start: BufferPosition, key: string, row, cell: int): (string, string) =
      let e = createTestEditor("abc\n\ndef")
      e.cursor = start
      e.press(key)
      e.click(row, cell)
      var lines: seq[string]
      for i in 0 ..< e.activeBuffer.len:
        lines.add e.activeBuffer.getLine(i)
      (lines.join("\n"), e.state.registers.getRegisterContent('"'))

    check after(pos(0, 1), "d", 1, 5) == ("a\ndef", "bc\n")
    check after(pos(0, 1), "d", 1, 0) == ("a\n\ndef", "bc")
    check after(pos(0, 0), "d", 1, 5)[0] == "def"
    check after(pos(2, 1), "d", 1, 5)[0] == "abc\nf"
    check after(pos(2, 1), "y", 1, 5)[1] == "\nde"
    check after(pos(1, 0), "d", 1, 5)[0] == "abc\n\ndef"

  test "a character's later cells take it":
    for (text, cell, left) in [
      ("ab\tcd", 2, "\tcd"),
      ("ab\tcd", 3, "cd"),
      ("abあcd", 2, "あcd"),
      ("abあcd", 3, "cd"),
    ]:
      let e = createTestEditor(text)
      e.press("d")
      e.click(0, cell)
      check e.activeBuffer.getLine(0) == left

  test "right of a closed fold's first line it goes to the fold's start":
    block:
      let e = createTestEditor("l1 a\nl2 b\nl3 c\nl4 defg\nl5")
      check e.activeBuffer.foldState.addFold(1, 3)
      e.activeBuffer.foldState.folds[0].collapsed = true
      e.cursor = pos(0, 2)
      e.press("d")
      e.click(1, 49)
      check e.activeBuffer.len == 5
      check e.state.registers.getRegisterContent('"') == " a"
    block:
      let e = createTestEditor("l1 a\nl2 b\nl3 c\nl4 defg\nl5")
      check e.activeBuffer.foldState.addFold(0, 2)
      e.activeBuffer.foldState.folds[0].collapsed = true
      e.cursor = pos(3, 4)
      e.press("d")
      e.click(0, 49)
      check e.activeBuffer.getLine(0) == "efg"

  test "Ctrl and Alt do not change the click, Shift cancels the operator":
    for (modifier, left) in [(kmCtrl, "efgh"), (kmAlt, "efgh"), (kmShift, "abcdefgh")]:
      let e = createTestEditor()
      e.press("d")
      discard e.handlePointerInput(initPointerInput(0, 4, modifiers = {modifier}))
      check e.activeBuffer.getLine(0) == left
      check e.state.pendingInput.pendingOperator.isNone

  test "a click on the cursor takes nothing":
    let e = createTestEditor()
    e.press("l", "d")
    e.click(0, 1)

    check e.activeBuffer.getLine(0) == "abcdefgh"
    check e.state.pendingInput.pendingOperator.isNone

  test "yank, change and case":
    block:
      let e = createTestEditor()
      e.press("y")
      e.click(0, 4)
      check e.activeBuffer.getLine(0) == "abcdefgh"
      check e.cursor == pos(0, 0)
      check e.state.registers.getRegisterContent('"') == "abcd"
    block:
      let e = createTestEditor()
      e.press("c")
      e.click(0, 4)
      check e.state.mode == EditorMode.Insert
      e.press("X", "Y", "Esc")
      check e.activeBuffer.getLine(0) == "XYefgh"
      e.press("u")
      check e.activeBuffer.getLine(0) == "abcdefgh"
    block:
      let e = createTestEditor()
      e.press("g", "U")
      e.click(0, 4)
      check e.activeBuffer.getLine(0) == "ABCDefgh"

  test "counts do nothing and the register is taken":
    let e = createTestEditor()
    e.press("\"", "b", "3", "d", "2")
    e.click(0, 4)

    check e.activeBuffer.getLine(0) == "efgh"
    check e.state.registers.getRegisterContent('b') == "abcd"
    e.press("x")
    check e.activeBuffer.getLine(0) == "fgh"

  test "it acts on the press, and a drag selects nothing":
    let e = createTestEditor()
    e.press("d")
    check e.handlePointerInput(initPointerInput(0, 4))
    check e.activeBuffer.getLine(0) == "efgh"
    discard e.handlePointerInput(initPointerInput(0, 2, action = paDrag))
    discard e.handlePointerInput(initPointerInput(0, 2, action = paRelease))

    check e.state.mode == EditorMode.Normal
    check e.cursor == pos(0, 0)
    check e.activeBuffer.getLine(0) == "efgh"

  test "`.` goes to the same cell":
    let e = createTestEditor()
    e.press("d")
    e.click(0, 2)
    e.press("j", "$", ".")

    check e.activeBuffer.len == 1
    check e.activeBuffer.getLine(0) == "cdp"

  test "`.` takes a change up to the same cell":
    let e = createTestEditor()
    e.press("c")
    e.click(0, 2)
    e.press("X", "Y", "Esc", "j", "0", ".")

    check e.activeBuffer.len == 2
    check e.activeBuffer.getLine(0) == "XYXY"
    check e.activeBuffer.getLine(1) == "ijklmnop"

  test "`.` goes by what the window shows":
    let e = createTestEditor("line\n".repeat(99) & "line")
    e.press("d")
    e.click(0, 2)
    check e.activeBuffer.getLine(0) == "ne"
    e.activeWindow.viewport.topLine = 30
    e.cursor = pos(30, 0)
    e.press(".")

    check e.activeBuffer.len == 100
    check e.activeBuffer.getLine(0) == "ne"
    check e.activeBuffer.getLine(30) == "ne"

  test "`.` in another buffer goes to its cell":
    let e = createTestEditor()
    e.press("d")
    e.click(0, 2)
    let first = e.activeBuffer
    e.addBuffer(newTextBuffer("BCDEFG"))
    e.switchToBufferByIndex(1)
    check e.activeBuffer != first
    e.cursor = pos(0, 0)
    e.press(".")

    check e.activeBuffer.getLine(0) == "DEFG"
    check first.getLine(0) == "cdefgh"

  test "`.` does nothing when its cell has left the window":
    let e = createTestEditor("line\n".repeat(9) & "line")
    e.press("d")
    e.click(8, 2)
    let lines = e.activeBuffer.len
    e.activeWindow.viewport.height = 6
    e.press(".")

    check e.activeBuffer.len == lines
    check e.state.pendingInput.pendingOperator.isNone

  test "`.` does nothing when its cell has left a narrowed window":
    let e = createTestEditor("abcdefghij".repeat(5) & "\n" & "abcdefghij".repeat(5))
    e.press("d")
    e.click(0, 30)
    e.activeWindow.viewport.width = 20
    e.press("j", "0", ".")

    check e.activeBuffer.len == 2
    check e.activeBuffer.getLine(1).len == 50

  test "`.` after the wheel goes by the window that shows the cursor":
    for operator in ["d", "c"]:
      let e = createTestEditor("line\n".repeat(99) & "line")
      e.press(operator)
      e.click(0, 2)
      e.press("Esc")
      e.cursor = pos(0, 0)
      discard e.handleScrollInput(initScrollInput(0, 0, 30))
      check e.activeWindow.viewport.topLine == 30
      e.press(".")

      check e.activeBuffer.len == 100
      check e.activeBuffer.getLine(0) == ""
      check e.activeWindow.viewport.topLine == 0

  test "`.` after keys that were not drawn goes by the window they lead to":
    let e = createTestEditor("line\n".repeat(99) & "line")
    e.press("d")
    e.click(3, 0)
    check e.activeBuffer.len == 97
    e.press("G", "u", ".")

    check e.activeBuffer.len == 97

  test "a start the window does not show takes nothing":
    for (top, line) in [(30, 0), (0, 60)]:
      let e = createTestEditor("line\n".repeat(99) & "line")
      e.activeWindow.viewport.topLine = top
      e.cursor = pos(line, 0)
      e.press("d")
      e.click(2, 2)

      check e.activeBuffer.len == 100
      check e.state.pendingInput.pendingOperator.isNone

  test "a start in a wrapped line's hidden rows takes nothing":
    let e = createTestEditor("abcdefghij".repeat(30) & "\nend")
    e.state.lineWrap = true
    e.activeWindow.viewport.topWrapOffset = 1
    e.press("d")
    e.click(1, 2)

    check e.activeBuffer.getLine(0).len == 300

  test "below the text, it is on the last line's first row, even one scrolled off":
    let text = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRST"
    for (row, left) in [
      (1, "0123456789abcdefghijklmnopqrstuvwxyzABCDEFJKLMNOPQRST"),
      (15, "01JKLMNOPQRST"),
    ]:
      let e = createTestEditor(text)
      e.state.lineWrap = true
      e.activeWindow.viewport.width = 10
      e.activeWindow.viewport.topWrapOffset = 3
      e.cursor = pos(0, 45)
      e.press("d")
      e.click(row, 2)

      check e.activeBuffer.getLine(0) == left

  test "it takes the character the click is on":
    # The cell the mouse finds and the one the operator finds are the same.
    for wrap in [false, true]:
      for gutter in [false, true]:
        for tabLine in [false, true]:
          let e = createTestEditor("abcdefghijklmnopqrstuvwxyz".repeat(2) & "\nend")
          e.state.lineWrap = wrap
          e.state.showLineNumbers = gutter
          e.state.showSidebar = gutter
          e.state.showTabLine = tabLine
          e.activeWindow.viewport.width = 30
          if not wrap:
            e.activeWindow.viewport.leftCell = 5
          let row = ord(tabLine) + ord(wrap)
          e.click(row, 15)
          let column = e.cursor.column
          check column > 0
          e.cursor = pos(0, 0)
          if not wrap:
            e.activeWindow.viewport.leftCell = 5
          let before = e.activeBuffer.getLine(0)
          e.press("d")
          if not wrap:
            e.activeWindow.viewport.leftCell = 5
          e.click(row, 15)
          check e.activeBuffer.getLine(0) == before[column ..^ 1]

  test "Ctrl-o resumes Insert after it":
    let e = createTestEditor()
    e.press("i", "C-o", "d")
    e.click(0, 4)
    check e.state.mode == EditorMode.Insert
    e.press("Z")

    check e.activeBuffer.getLine(0) == "Zefgh"

  test "a change that ends in a closed fold opens it":
    for search in [false, true]:
      let e = createTestEditor("l1 a\nl2 b\nl3 c\nl4 defg\nl5")
      check e.activeBuffer.foldState.addFold(0, 2)
      e.activeBuffer.foldState.folds[0].collapsed = true
      e.cursor = pos(3, 3)
      e.press("c")
      if search:
        e.press("?", "l", "1", "Enter")
      else:
        e.click(0, 1)

      check e.state.mode == EditorMode.Insert
      check e.activeBuffer.foldState.getCollapsedFoldAt(e.cursor.line).isNone

  test "a yank that ends in a closed fold leaves it closed":
    let e = createTestEditor("l1 a\nl2 b\nl3 c\nl4 defg\nl5")
    check e.activeBuffer.foldState.addFold(0, 2)
    e.activeBuffer.foldState.folds[0].collapsed = true
    e.cursor = pos(3, 3)
    e.press("y")
    e.click(0, 1)

    check e.activeBuffer.foldState.folds[0].collapsed

  test "a read-only buffer is left alone":
    let e = createTestEditor()
    e.activeBuffer.readOnly = true
    e.press("d")
    e.click(0, 4)

    check e.activeBuffer.getLine(0) == "abcdefgh"
    check e.state.pendingInput.pendingOperator.isNone

  test "a click in another window cancels it":
    let e = createTestEditor()
    let split = EditorWindow(viewBuffer: e.activeBuffer, tabBufferId: e.activeBuffer.id)
    split.viewport = ViewPort(x: 40, y: 0, width: 40, height: 24)
    e.activeWindow.viewport.width = 40
    e.windowManager.windows.add split
    e.press("d")
    e.click(0, 44)

    check e.windowManager.activeWindowIndex == 1
    check e.state.pendingInput.pendingOperator.isNone
    check e.activeBuffer.getLine(0) == "abcdefgh"

  test "a search prompt keeps its operator for Enter":
    let e = createTestEditor()
    e.press("d", "/", "l")
    discard e.handlePointerInput(initPointerInput(0, 4))
    check e.activeBuffer.getLine(0) == "abcdefgh"
    check e.state.isSearchOverlay
    check e.state.pendingInput.pendingOperator.isSome
    e.press("Enter")

    check e.activeBuffer.len == 1
    check e.activeBuffer.getLine(0) == "lmnop"

  test "a click on another tab cancels it":
    let e = createTestEditor()
    let first = e.activeBuffer
    let second = newTextBuffer("BBBBBBBB\nCCCCCCC")
    e.addBuffer(second)
    e.activeWindow.bufferIds.add second.id
    e.state.showTabLine = true
    check e.activeWindow.bufferIds.len == 2
    e.press("d")
    let was = e.activeBuffer
    for column in countup(0, 60, 4):
      discard e.handlePointerInput(initPointerInput(0, column))
      if e.activeBuffer != was:
        break
    check e.activeBuffer != was
    check e.state.pendingInput.pendingOperator.isNone
    let line = e.activeBuffer.getLine(0)
    e.click(1, 4)
    check e.activeBuffer.getLine(0) == line
    check first.getLine(0) == "abcdefgh"

  test "its message stays when the button is released":
    let e = createTestEditor()
    e.activeBuffer.readOnly = true
    e.press("d")
    check e.handlePointerInput(initPointerInput(0, 4))
    let message = e.state.statusMessage
    check message.len > 0
    discard e.handlePointerInput(initPointerInput(0, 4, action = paRelease))
    check e.state.statusMessage == message
    discard e.handlePointerInput(initPointerInput(0, 2))
    check e.state.statusMessage.len == 0

  test "an operator whose line is gone does nothing":
    let e = createTestEditor()
    e.press("j", ">")
    check e.activeBuffer.deleteLine(1).isOk
    e.click(0, 4)

    check e.activeBuffer.getLine(0) == "abcdefgh"
    check e.state.pendingInput.pendingOperator.isNone

suite "A click with other keys pending":
  test "leaves nothing waiting in a viewer Visual mode began in":
    for key in ["i", "f", "\""]:
      let e = createTestEditor()
      e.setMode(EditorMode.LogViewer)
      e.state.previousMode = EditorMode.LogViewer
      e.setMode(EditorMode.Visual)
      e.press(key)
      check e.state.pendingInput.waitsForOperand(e.keyRouter.registry)
      e.click(0, 4)

      check e.state.mode == EditorMode.LogViewer
      check not e.state.pendingInput.waitsForOperand(e.keyRouter.registry)

  test "cancels what waits for a key":
    for keys in [@["f"], @["d", "f"], @["d", "i"], @["r"], @["2"], @["\""], @["v", "i"]]:
      let e = createTestEditor()
      e.press(keys)
      e.click(0, 4)
      e.press("x")

      check e.state.mode == EditorMode.Normal
      check e.activeBuffer.getLine(0) == "abcdfgh"

suite "Mouse input that cancels a waiting operator":
  test "the wheel":
    let e = createTestEditor("line\n".repeat(99) & "line")
    for waiting in ["d", "f"]:
      e.press(waiting)
      discard e.handleScrollInput(initScrollInput(0, 0, 3))
      check e.state.pendingInput.pendingOperator.isNone
      check not e.state.pendingInput.waitsForOperand(e.keyRouter.registry)
    e.click(0, 2)
    check e.activeBuffer.len == 100

  test "the status line":
    let e = createTestEditor()
    e.press("d")
    discard e.handlePointerInput(initPointerInput(23, 2))
    e.press("j")
    check e.activeBuffer.len == 2

  test "the current tab":
    let e = createTestEditor()
    e.state.showTabLine = true
    e.press("d")
    discard e.handlePointerInput(initPointerInput(0, 1))
    check e.state.pendingInput.pendingOperator.isNone

suite "A press beside the text":
  test "the gutter is its row's first cell":
    let e = createTestEditor()
    e.state.showLineNumbers = true
    e.press("l", "l", "d")
    e.click(0, 0)
    check e.activeBuffer.getLine(0) == "cdefgh"

  test "the scrollbar is no text":
    for wrap in [false, true]:
      let e = createTestEditor("abcdefghij".repeat(5))
      e.state.lineWrap = wrap
      e.state.scrollbar = true
      e.state.scrollbarWidth = 2
      e.activeWindow.viewport.width = 22
      for column in [20, 21]:
        e.cursor = pos(0, 0)
        e.press("d")
        e.click(0, column)
        check e.activeBuffer.getLine(0).len == 50
        check e.state.pendingInput.pendingOperator.isNone
        # The last character the row shows.
        check e.cursor == pos(0, 19)

  test "the blank end of a wrapped row is on the row's last character":
    let e = createTestEditor("abcdeあいう")
    e.state.lineWrap = true
    e.activeWindow.viewport.width = 6
    e.click(0, 5)
    check e.cursor == pos(0, 4)
    e.click(1, 0)
    check e.cursor == pos(0, 5)

  test "a search prompt stays in its window and buffer":
    let e = createTestEditor()
    let second = newTextBuffer("BBBBBBBB")
    e.addBuffer(second)
    e.activeWindow.bufferIds.add second.id
    e.state.showTabLine = true
    let was = e.activeBuffer
    e.press("d", "/", "l")
    for column in 0 ..< 60:
      discard e.handlePointerInput(initPointerInput(0, column))
    check e.activeBuffer == was
    check e.state.isSearchOverlay
    check e.state.pendingInput.pendingOperator.isSome

  test "a prompt takes the mouse":
    for (before, prompt) in [("d", "/"), ("v", "/"), ("d", ":")]:
      for (count, modifiers) in [
        (1, NoModifiers), (2, NoModifiers), (3, NoModifiers), (1, {kmShift})
      ]:
        checkpoint prompt & before & $count & $modifiers
        let e = createTestEditor()
        e.press(before, prompt, "m")
        let
          mode = e.state.mode
          cursor = e.cursor
          operator = e.state.pendingInput.pendingOperator.isSome
        for action in [paPress, paDrag, paRelease]:
          discard e.handlePointerInput(
            initPointerInput(
              0,
              if action == paPress: 2 else: 4,
              action = action,
              modifiers = modifiers,
              clickCount = count,
            )
          )
        check e.state.hasOverlay
        check e.state.isSearchOverlay == (prompt == "/")
        check e.state.mode == mode
        check e.cursor == cursor
        check e.state.pendingInput.pendingOperator.isSome == operator
        if prompt == "/":
          e.press("Enter")
          if before == "d":
            check e.activeBuffer.getLine(0) == "mnop"
          else:
            check e.state.mode == EditorMode.Visual
            check e.cursor == pos(1, 4)

suite "Mouse input while recording":
  proc fiveLines(): Editor =
    createTestEditor("abcdef\nghijkl\nmnopqr\nstuvwx\nyzabcd")

  proc recordedKeys(e: Editor): seq[string] =
    e.state.pendingInput.macroState.registers['q']

  test "an operator's click is not replayed with the next key as its motion":
    let e = fiveLines()
    e.press("q", "q", "d")
    e.click(0, 2)
    e.press("j", "q")
    check e.activeBuffer.len == 5
    check e.recordedKeys == @["d", clickMark(0, 2), "j"]
    e.press("0", "k", "@", "q")

    check e.activeBuffer.getLine(0) == "ef"
    check e.activeBuffer.len == 5
    check e.cursor.line == 1

  test "keys a press or the wheel cancels":
    for keys in [@["f"], @["2"], @["\"", "a", "2", "d"], @["d", "i"]]:
      for wheel in [false, true]:
        let e = fiveLines()
        e.press("q", "q")
        e.press(keys)
        if wheel:
          discard e.handleScrollInput(initScrollInput(0, 0, 1))
        else:
          # On the status line.
          discard e.handlePointerInput(initPointerInput(23, 0))
        e.press("x", "q")
        check e.activeBuffer.getLine(0) == "bcdef"
        e.press("@", "q")
        check e.activeBuffer.len == 5
        check e.activeBuffer.getLine(0) == "cdef"

  test "with no keys pending it records nothing":
    let e = fiveLines()
    e.press("q", "q", "x")
    e.click(1, 2)
    discard e.handleScrollInput(initScrollInput(0, 0, 1))
    e.press("x", "q")
    check e.recordedKeys == @["x", "x"]

  proc mouse(e: Editor, wheel: bool) =
    if wheel:
      discard e.handleScrollInput(initScrollInput(0, 0, 1))
    else:
      # On the status line.
      discard e.handlePointerInput(initPointerInput(23, 0))

  proc map(e: Editor, mode: EditorMode, lhs, rhs: string) =
    check e.keyBindingRegistry.addRuntimeMapping(mode, lhs, rhs, true) == ""

  test "keys cancelled in Visual":
    for keys in [@["f"], @["2"], @["i"]]:
      for wheel in [false, true]:
        checkpoint $keys & " " & $wheel
        let e = fiveLines()
        e.press("q", "q", "v")
        e.press(keys)
        e.mouse(wheel)
        e.press("l", "d", "q")
        check e.activeBuffer.getLine(0) == "cdef"
        e.press("@", "q")
        check e.activeBuffer.getLine(0) == "ef"

  test "a mapping of Escape is not run":
    for keys in [@["2"], @["\"", "a"]]:
      let e = fiveLines()
      e.map(EditorMode.Normal, "Esc", "J")
      e.press("q", "q")
      e.press(keys)
      e.mouse(wheel = false)
      e.press("l", "q", "@", "q")
      check e.activeBuffer.len == 5

  test "under Insert's Ctrl-o":
    for wheel in [false, true]:
      let e = fiveLines()
      e.press("q", "q", "i", "C-o")
      e.mouse(wheel)
      check e.state.mode == EditorMode.Insert
      e.press("x", "Esc", "q")
      check e.activeBuffer.getLine(0) == "xabcdef"
      e.press("@", "q")
      check e.activeBuffer.getLine(0) == "xxabcdef"

  test "with keys held for a mapping":
    for wheel in [false, true]:
      let e = fiveLines()
      e.map(EditorMode.Normal, "j k", "d d")
      e.press("q", "q", "j")
      check e.keyRouter.isHoldingKeys
      e.mouse(wheel)
      e.press("k", "q", "@", "q")
      check e.activeBuffer.len == 5
      check e.cursor.line == 0

  test "a change by a click takes the text typed after it":
    let e = fiveLines()
    e.press("q", "q", "c")
    e.click(0, 2)
    e.press("o", "d", "d", "Esc", "q")
    check e.activeBuffer.getLine(0) == "oddcdef"
    check e.recordedKeys == @["c", clickMark(0, 2), "o", "d", "d", "<Escape>"]
    e.press("0", "@", "q")
    check e.activeBuffer.getLine(0) == "odddcdef"
    check e.activeBuffer.len == 5
    check e.state.mode == EditorMode.Normal
    e.press("0", ".")
    check e.activeBuffer.getLine(0) == "oddddcdef"
    e.press("u")
    check e.activeBuffer.getLine(0) == "odddcdef"

  test "an operator's click under Insert's Ctrl-o":
    let e = fiveLines()
    e.press("q", "q", "i", "C-o", "d")
    e.click(0, 2)
    e.press("x", "Esc", "q")
    check e.activeBuffer.getLine(0) == "xcdef"
    e.press("@", "q")
    check e.activeBuffer.getLine(0) == "xdef"
    check e.state.mode == EditorMode.Normal

  test "a click that did not operate is recorded as a break":
    let e = createTestEditor()
    e.activeBuffer.readOnly = true
    e.press("q", "q", "d")
    e.click(0, 4)
    e.press("q")
    check e.recordedKeys == @["d", BreakMark]

  test "a click that cannot be played stops the macro":
    # The window has narrowed to leave the cell out; no operator waits.
    for narrowed in [true, false]:
      let e = fiveLines()
      e.press("q", "q", "c")
      e.click(0, 40)
      e.press("d", "d", "Esc", "q", "j", "0")
      if narrowed:
        e.activeWindow.viewport.width = 20
      else:
        e.state.pendingInput.macroState.registers['q'].delete(0)
      let text = e.activeBuffer.getTextString
      e.press("@", "q")
      check e.activeBuffer.getTextString == text
      check e.state.mode == EditorMode.Normal
      check e.state.pendingInput.pendingOperator.isNone

  test "only a whole mark is a click":
    check parseClickMark(clickMark(3, 14)) == some((row: 3, cell: 14))
    for key in ["<InputClick:>", "<InputClick:1>", "<InputClick:1,2>x", "a", BreakMark]:
      check parseClickMark(key).isNone

suite "Mouse input after held keys that quit":
  test "does nothing":
    let e = createTestEditor()
    for (lhs, rhs) in [("s", "Z Q"), ("s s s", "d d")]:
      check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, lhs, rhs, true) ==
        ""
    e.press("s")
    e.click(1, 4)
    check e.state.quitDecided
    check e.cursor == pos(0, 0)
