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

import std/[options, unittest]

import ../src/moepkg/[buffer, config, editor, modes, types]
import visual_test_helper

proc createSelectionEditor(text: string): Editor =
  result = newEditor(newEditorConfig())
  discard result.activeBuffer.insertText(BufferPosition(line: 0, column: 0), text)

suite "editor selection API":
  test "inactive selection reports none and empty text":
    let e = createSelectionEditor("alpha")

    check e.currentSelection().isNone
    check e.selectedText() == ""

  test "character selection exposes an ordered value snapshot":
    let e = createSelectionEditor("alpha beta")
    e.state.selectVisual(
      BufferPosition(line: 0, column: 9), BufferPosition(line: 0, column: 6)
    )

    let selection = e.currentSelection()

    check selection.isSome
    check selection.get.bufferId == e.activeBuffer.id
    check selection.get.kind == EditorSelectionKind.Character
    check selection.get.anchor == BufferPosition(line: 0, column: 9)
    check selection.get.focus == BufferPosition(line: 0, column: 6)
    check selection.get.first == BufferPosition(line: 0, column: 6)
    check selection.get.last == BufferPosition(line: 0, column: 9)
    check e.selectedText() == "beta"

  test "line and block text use the editor selection semantics":
    let e = createSelectionEditor("alpha\nbeta\ngamma")
    e.state.selectVisual(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 1, column: 0), vskLine
    )

    check e.currentSelection().get.kind == EditorSelectionKind.Line
    check e.selectedText() == "alpha\nbeta"

    e.state.selectVisual(
      BufferPosition(line: 0, column: 1), BufferPosition(line: 2, column: 2), vskBlock
    )
    check e.currentSelection().get.kind == EditorSelectionKind.Block
    check e.selectedText() == "lp\net\nam"

  test "a selection ending in a closed fold reports the text a yank would take":
    let e = createSelectionEditor("alpha\nbeta\ngamma\ndelta")
    check e.activeBuffer.foldState.addFold(1, 2, collapsed = true)
    e.state.selectVisual(
      BufferPosition(line: 0, column: 2), BufferPosition(line: 1, column: 0)
    )

    let selection = e.currentSelection().get
    check selection.kind == EditorSelectionKind.Line
    check selection.first.line == 0
    check selection.last.line == 2
    # The ends stay where the user put them.
    check selection.anchor == BufferPosition(line: 0, column: 2)
    check selection.focus == BufferPosition(line: 1, column: 0)
    check e.selectedText() == "alpha\nbeta\ngamma"

  test "takes every field from the window the editor reports as active":
    # Between the window manager switching windows and the editor syncing, the
    # state still names the window left; the snapshot must not mix the two.
    let e = createSelectionEditor("alpha")
    let other = EditorWindow(mode: EditorMode.Normal)
    other.setTab(newTextBuffer("one two"))
    e.windowManager.windows.add other
    other.setMode(EditorMode.Visual)
    other.cursor = BufferPosition(line: 0, column: 2)
    e.windowManager.activeWindowIndex = 1

    let selection = e.currentSelection().get

    check selection.bufferId == other.buffer.id
    check selection.first == BufferPosition(line: 0, column: 0)
    check selection.last == BufferPosition(line: 0, column: 2)
    check e.selectedText() == "one"
