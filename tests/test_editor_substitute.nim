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

## Tests for editor_substitute.nim

import std/unittest

import ../src/moepkg/[editor, config, config_loader, editor_substitute]
import ../src/moepkg/types/editor_types
import ../src/moepkg/buffer

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc setBufferContent(e: Editor, content: string) =
  e.activeWindow.buffer = newTextBuffer(content)

suite "editor_substitute":
  test "startSubstitutePreview snapshots the buffer":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo\nbar baz")
    e.startSubstitutePreview()
    check e.state.ui.substitutePreview.isActive
    check e.state.ui.substitutePreview.originalLines.len == 2
    check e.state.ui.substitutePreview.originalLines[0] == "foo bar foo"
    check e.state.ui.substitutePreview.originalLines[1] == "bar baz"

  test "startSubstitutePreview is a no-op when already active":
    let e = createTestEditor()
    setBufferContent(e, "foo")
    e.startSubstitutePreview()
    e.state.ui.substitutePreview.originalLines[0] = "changed"
    e.startSubstitutePreview()
    check e.state.ui.substitutePreview.originalLines[0] == "changed"

  test "startSubstitutePreview is a no-op on a read-only buffer":
    let e = createTestEditor()
    setBufferContent(e, "foo")
    e.activeBuffer.readOnly = true
    e.startSubstitutePreview()
    check e.state.ui.substitutePreview.isActive == false

  test "updateSubstitutePreview applies a global replacement":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo\nfoo baz")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "qux")
    check e.activeBuffer.getLine(0) == "qux bar qux"
    check e.activeBuffer.getLine(1) == "qux baz"

  test "updateSubstitutePreview with isGlobalFlag=false replaces first only":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo\nfoo baz")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "qux", isGlobalFlag = false)
    check e.activeBuffer.getLine(0) == "qux bar foo"
    check e.activeBuffer.getLine(1) == "qux baz"

  test "updateSubstitutePreview with an empty pattern is a no-op":
    let e = createTestEditor()
    setBufferContent(e, "foo bar")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("", "qux")
    check e.activeBuffer.getLine(0) == "foo bar"

  test "updateSubstitutePreview skips identical pattern/replacement":
    let e = createTestEditor()
    setBufferContent(e, "foo bar")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "qux")
    check e.activeBuffer.getLine(0) == "qux bar"
    e.updateSubstitutePreview("foo", "qux")
    check e.activeBuffer.getLine(0) == "qux bar"

  test "updateSubstitutePreview without an active preview is a no-op":
    let e = createTestEditor()
    setBufferContent(e, "foo bar")
    e.updateSubstitutePreview("foo", "qux")
    check e.activeBuffer.getLine(0) == "foo bar"

  test "cancelSubstitutePreview restores the original content":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "qux")
    check e.activeBuffer.getLine(0) == "qux bar qux"
    e.cancelSubstitutePreview()
    check e.activeBuffer.getLine(0) == "foo bar foo"
    check e.state.ui.substitutePreview.isActive == false

  test "cancelSubstitutePreview restores cursor and viewport":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo")
    e.cursor = BufferPosition(line: 0, column: 4)
    e.viewport.topLine = 5
    e.viewport.leftColumn = 6
    e.startSubstitutePreview()
    e.cursor = BufferPosition(line: 1, column: 9)
    e.viewport.topLine = 8
    e.viewport.leftColumn = 7
    e.cancelSubstitutePreview()
    check e.cursor.line == 0
    check e.cursor.column == 4
    check e.viewport.topLine == 5
    check e.viewport.leftColumn == 6
    check e.state.ui.substitutePreview.isActive == false

  test "cancelSubstitutePreview without an active preview is a no-op":
    let e = createTestEditor()
    setBufferContent(e, "foo bar")
    e.cancelSubstitutePreview()
    check e.activeBuffer.getLine(0) == "foo bar"

  test "commitSubstitutePreview keeps the current changes":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "qux")
    e.commitSubstitutePreview()
    check e.activeBuffer.getLine(0) == "qux bar qux"
    check e.state.ui.substitutePreview.isActive == false
    check e.state.ui.substitutePreview.originalLines.len == 0

  test "restoreFromPreview restores line count differences":
    let e = createTestEditor()
    setBufferContent(e, "foo bar")
    e.startSubstitutePreview()
    e.activeBuffer.insertLineNoUndo(1, "extra line")
    e.activeBuffer.deleteLineNoUndo(1)
    e.activeBuffer.insertLineNoUndo(1, "extra line")
    check e.activeBuffer.len == 2
    e.restoreFromPreview()
    check e.activeBuffer.len == 1
    check e.activeBuffer.getLine(0) == "foo bar"
