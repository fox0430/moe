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

## Tests for visual_selection.nim

import std/unittest

import pkg/results

import ../src/moepkg/[buffer, types, modes, visual_selection]
import visual_test_helper

proc windowOn(
    buf: TextBuffer, mode: EditorMode, previousMode = EditorMode.Normal
): EditorWindow =
  result = EditorWindow(mode: mode, previousMode: previousMode)
  result.setTab(buf)

proc stateOn(win: EditorWindow): EditorState =
  EditorState(activeWindow: win)

suite "visual_selection - derived selection":
  test "runs from the anchor to the cursor":
    let state = windowOn(newTextBuffer("hello world"), EditorMode.Visual).stateOn
    state.visualAnchor = BufferPosition(line: 0, column: 2)
    state.cursor = BufferPosition(line: 0, column: 7)

    let sel = state.visualSelection
    check sel.active
    check sel.start == BufferPosition(line: 0, column: 2)
    check sel.current == BufferPosition(line: 0, column: 7)

  test "follows the cursor":
    let state = windowOn(newTextBuffer("hello world"), EditorMode.Visual).stateOn
    state.visualAnchor = BufferPosition(line: 0, column: 2)
    state.cursor = BufferPosition(line: 0, column: 4)

    state.cursor.column = 9

    check state.visualSelection.current == BufferPosition(line: 0, column: 9)

  test "takes its kind from the mode":
    for (mode, kind) in [
      (EditorMode.Visual, vskChar),
      (EditorMode.VisualLine, vskLine),
      (EditorMode.VisualBlock, vskBlock),
    ]:
      let state = windowOn(newTextBuffer("hello"), mode).stateOn
      check state.visualSelection.kind == kind

  test "is inactive outside the Visual modes":
    let state = windowOn(newTextBuffer("hello"), EditorMode.Normal).stateOn
    state.visualAnchor = BufferPosition(line: 0, column: 1)
    state.cursor = BufferPosition(line: 0, column: 3)

    check not state.visualSelection.active

  test "pulls an anchor past the last line back onto it":
    let buf = newTextBuffer("a\nbb\nccc")
    let state = windowOn(buf, EditorMode.Visual).stateOn
    state.visualAnchor = BufferPosition(line: 2, column: 3)
    check buf.deleteLine(2).isOk
    check buf.deleteLine(1).isOk

    check state.visualSelection.start == BufferPosition(line: 0, column: 1)

  test "is the active window's own":
    let
      a = windowOn(newTextBuffer("first buffer"), EditorMode.Visual)
      b = windowOn(newTextBuffer("second"), EditorMode.VisualLine)
    a.visualAnchor = BufferPosition(line: 0, column: 6)
    a.cursor = BufferPosition(line: 0, column: 11)
    let state = a.stateOn

    check state.visualSelection.start == BufferPosition(line: 0, column: 6)

    state.activeWindow = b

    check state.visualSelection.start == BufferPosition(line: 0, column: 0)
    check state.visualSelection.current == BufferPosition(line: 0, column: 0)
    check state.visualSelection.kind == vskLine

suite "visual_selection - entering Visual":
  test "starts the selection at the cursor, not at an old anchor":
    let state = windowOn(newTextBuffer("a\nb\nc\nd"), EditorMode.Insert).stateOn
    state.visualAnchor = BufferPosition(line: 0, column: 0)
    state.cursor = BufferPosition(line: 3, column: 0)

    state.mode = EditorMode.Visual

    check state.visualSelection.start == BufferPosition(line: 3, column: 0)

  test "keeps the anchor across a switch between Visual kinds":
    let state = windowOn(newTextBuffer("a\nb\nc\nd"), EditorMode.Visual).stateOn
    state.visualAnchor = BufferPosition(line: 1, column: 0)
    state.cursor = BufferPosition(line: 3, column: 0)

    state.mode = EditorMode.VisualLine

    check state.visualSelection.start == BufferPosition(line: 1, column: 0)

suite "visual_selection - enterVisual":
  test "selects the range and records the mode it came from":
    let state = windowOn(
      newTextBuffer("hello world"), EditorMode.Normal, EditorMode.Insert
    ).stateOn

    state.enterVisual(
      vskChar, BufferPosition(line: 0, column: 6), BufferPosition(line: 0, column: 10)
    )

    check state.mode == EditorMode.Visual
    check state.previousMode == EditorMode.Normal
    check state.visualSelection.start == BufferPosition(line: 0, column: 6)
    check state.cursor == BufferPosition(line: 0, column: 10)

  test "reshaping a selection keeps the mode Visual came from":
    let state = windowOn(
      newTextBuffer("hello world"), EditorMode.VisualLine, EditorMode.LogViewer
    ).stateOn

    state.enterVisual(
      vskChar, BufferPosition(line: 0, column: 1), BufferPosition(line: 0, column: 3)
    )

    check state.mode == EditorMode.Visual
    check state.previousMode == EditorMode.LogViewer
    check state.visualSelection.start == BufferPosition(line: 0, column: 1)

suite "visual_selection - operandSelection":
  test "covers a closed fold it reaches into, linewise":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5")
    check buf.foldState.addFold(2, 4, collapsed = true)
    let state = windowOn(buf, EditorMode.Visual).stateOn
    state.visualAnchor = BufferPosition(line: 0, column: 0)
    state.cursor = BufferPosition(line: 2, column: 0)

    let sel = state.operandSelection(buf)

    check sel.kind == vskLine
    check sel.start == BufferPosition(line: 0, column: 0)
    check sel.current == BufferPosition(line: 4, column: 0)
    # The window's own selection, cursor and mode stay as they were.
    check state.visualSelection.kind == vskChar
    check state.cursor == BufferPosition(line: 2, column: 0)
    check state.mode == EditorMode.Visual

  test "keeps its shape across a closed fold it only contains":
    # As in Vim: only an end in a closed fold widens the selection.
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5")
    check buf.foldState.addFold(2, 3, collapsed = true)
    let state = windowOn(buf, EditorMode.Visual).stateOn
    state.visualAnchor = BufferPosition(line: 0, column: 0)
    state.cursor = BufferPosition(line: 5, column: 0)

    let sel = state.operandSelection(buf)

    check sel.kind == vskChar
    check sel.start == BufferPosition(line: 0, column: 0)
    check sel.current == BufferPosition(line: 5, column: 0)

  test "a block keeps its columns across a closed fold it only contains":
    # Vim's blockwise `d` cuts the same columns from the hidden lines too.
    let buf = newTextBuffer("0abc\n1abc\n2abc\n3abc\n4abc\n5abc")
    check buf.foldState.addFold(2, 3, collapsed = true)
    let state = windowOn(buf, EditorMode.VisualBlock).stateOn
    state.visualAnchor = BufferPosition(line: 0, column: 1)
    state.cursor = BufferPosition(line: 5, column: 2)

    let sel = state.operandSelection(buf)

    check sel.kind == vskBlock
    check sel.start == BufferPosition(line: 0, column: 1)
    check sel.current == BufferPosition(line: 5, column: 2)

  test "is the window's selection when it touches no closed fold":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5")
    check buf.foldState.addFold(2, 4, collapsed = false)
    let state = windowOn(buf, EditorMode.Visual).stateOn
    state.visualAnchor = BufferPosition(line: 0, column: 0)
    state.cursor = BufferPosition(line: 2, column: 0)

    let sel = state.operandSelection(buf)

    check sel.kind == vskChar
    check sel.start == BufferPosition(line: 0, column: 0)
    check sel.current == BufferPosition(line: 2, column: 0)

suite "visual_selection - selectVisualRange":
  test "anchors the range and moves the cursor to its focus":
    let state = windowOn(newTextBuffer("hello world"), EditorMode.Visual).stateOn

    state.selectVisualRange(
      BufferPosition(line: 0, column: 6), BufferPosition(line: 0, column: 1)
    )

    check state.visualAnchor == BufferPosition(line: 0, column: 6)
    check state.cursor == BufferPosition(line: 0, column: 1)

suite "visual_selection - leaveVisual":
  test "returns to the mode Visual was entered from":
    let state = windowOn(
      newTextBuffer("log"), EditorMode.VisualLine, EditorMode.LogViewer
    ).stateOn

    state.leaveVisual()

    check state.mode == EditorMode.LogViewer
    check not state.visualSelection.active

  test "never returns to another Visual mode":
    let state =
      windowOn(newTextBuffer("hello"), EditorMode.VisualLine, EditorMode.Visual).stateOn

    state.leaveVisual()

    check state.mode == EditorMode.Normal

  test "puts the cursor back on the line in Normal":
    let state = windowOn(newTextBuffer("abc\ndef"), EditorMode.Visual).stateOn
    state.cursor = BufferPosition(line: 0, column: 3)

    state.leaveVisual()

    check state.mode == EditorMode.Normal
    check state.cursor == BufferPosition(line: 0, column: 2)

  test "puts the cursor back on the line in a viewer":
    let state =
      windowOn(newTextBuffer("log"), EditorMode.Visual, EditorMode.LogViewer).stateOn
    state.cursor = BufferPosition(line: 0, column: 3)

    state.leaveVisual()

    check state.mode == EditorMode.LogViewer
    check state.cursor == BufferPosition(line: 0, column: 2)

  test "leaves the cursor past the end for Insert":
    let win = windowOn(newTextBuffer("abc"), EditorMode.Visual)
    win.cursor = BufferPosition(line: 0, column: 3)

    win.setMode(EditorMode.Insert)

    check win.cursor == BufferPosition(line: 0, column: 3)

  test "does nothing outside Visual":
    let state =
      windowOn(newTextBuffer("hello"), EditorMode.Normal, EditorMode.Insert).stateOn

    state.leaveVisual()

    check state.mode == EditorMode.Normal

suite "visual_selection - the command line":
  test "`:` ends Visual, as in Vim":
    let state = windowOn(newTextBuffer("hello"), EditorMode.Visual).stateOn

    state.enterCommandOverlay()

    check state.isCommandOverlay
    check state.mode == EditorMode.Normal
    check not state.visualSelection.active

  test "`:` returns to the mode Visual was entered from":
    let state = windowOn(
      newTextBuffer("log"), EditorMode.VisualLine, EditorMode.LogViewer
    ).stateOn

    state.enterCommandOverlay()

    check state.mode == EditorMode.LogViewer

  test "search keeps Visual, since it moves the cursor":
    let state = windowOn(newTextBuffer("hello"), EditorMode.Visual).stateOn

    state.enterSearchOverlay(Forward)

    check state.mode == EditorMode.Visual
