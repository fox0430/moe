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

import ../src/moepkg/[buffer, config, editor, types]

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
    e.state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 9),
      current: BufferPosition(line: 0, column: 6),
      active: true,
      kind: vskChar,
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
    e.state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 0),
      active: true,
      kind: vskLine,
    )

    check e.currentSelection().get.kind == EditorSelectionKind.Line
    check e.selectedText() == "alpha\nbeta"

    e.state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 1),
      current: BufferPosition(line: 2, column: 2),
      active: true,
      kind: vskBlock,
    )
    check e.currentSelection().get.kind == EditorSelectionKind.Block
    check e.selectedText() == "lp\net\nam"
