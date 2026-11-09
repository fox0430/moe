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

import std/[options, unittest]

import
  ../src/moepkg/
    [editor, config, config_loader, editor_substitute, key_bindings, primitives, types]
import ../src/moepkg/command_handlers/command_mode_handler
import ../src/moepkg/types/editor_types
import ../src/moepkg/buffer
import ../src/moepkg/command_line/substitute_parser

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc setBufferContent(e: Editor, content: string) =
  e.activeWindow.setTab(newTextBuffer(content))

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
    e.updateSubstitutePreview("foo", "qux", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "qux bar qux"
    check e.activeBuffer.getLine(1) == "qux baz"

  test "updateSubstitutePreview with isGlobalFlag=false replaces first only":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo\nfoo baz")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "qux", "".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "qux bar foo"
    check e.activeBuffer.getLine(1) == "qux baz"

  test "updateSubstitutePreview replaces only lines firstLine .. lastLine":
    let e = createTestEditor()
    setBufferContent(e, "foo\nfoo\nfoo")
    e.startSubstitutePreview()
    e.updateSubstitutePreview(
      "foo", "qux", "g".parseSubstituteFlags, smRegex, firstLine = 1, lastLine = 1
    )
    check e.activeBuffer.getLine(0) == "foo"
    check e.activeBuffer.getLine(1) == "qux"
    check e.activeBuffer.getLine(2) == "foo"

  test "updateSubstitutePreview reapplies when only the lines or the flag change":
    let e = createTestEditor()
    setBufferContent(e, "foo foo\nfoo foo")
    e.startSubstitutePreview()
    e.updateSubstitutePreview(
      "foo", "qux", "".parseSubstituteFlags, smRegex, lastLine = 0
    )
    e.updateSubstitutePreview(
      "foo", "qux", "g".parseSubstituteFlags, smRegex, lastLine = 0
    )
    check e.activeBuffer.getLine(0) == "qux qux"
    e.updateSubstitutePreview(
      "foo", "qux", "g".parseSubstituteFlags, smRegex, firstLine = 1
    )
    check e.activeBuffer.getLine(0) == "foo foo"
    check e.activeBuffer.getLine(1) == "qux qux"

  test "updateSubstitutePreview with an empty pattern is a no-op":
    let e = createTestEditor()
    setBufferContent(e, "foo bar")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("", "qux", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "foo bar"

  test "updateSubstitutePreview skips identical pattern/replacement":
    let e = createTestEditor()
    setBufferContent(e, "foo bar")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "qux", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "qux bar"
    e.updateSubstitutePreview("foo", "qux", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "qux bar"

  test "updateSubstitutePreview without an active preview is a no-op":
    let e = createTestEditor()
    setBufferContent(e, "foo bar")
    e.updateSubstitutePreview("foo", "qux", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "foo bar"

  test "cancelSubstitutePreview restores the original content":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "qux", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "qux bar qux"
    e.cancelSubstitutePreview()
    check e.activeBuffer.getLine(0) == "foo bar foo"
    check e.state.ui.substitutePreview.isActive == false

  test "cancelSubstitutePreview restores cursor and viewport":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo")
    e.cursor = BufferPosition(line: 0, column: 4)
    e.viewport.topLine = 5
    e.viewport.leftCell = 6
    e.startSubstitutePreview()
    e.cursor = BufferPosition(line: 1, column: 9)
    e.viewport.topLine = 8
    e.viewport.leftCell = 7
    e.cancelSubstitutePreview()
    check e.cursor.line == 0
    check e.cursor.column == 4
    check e.viewport.topLine == 5
    check e.viewport.leftCell == 6
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
    e.updateSubstitutePreview("foo", "qux", "g".parseSubstituteFlags, smRegex)
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

  test "updateSubstitutePreview reapplies when only the case changes":
    let e = createTestEditor()
    setBufferContent(e, "Foo foo")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "x", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "Foo x"
    e.updateSubstitutePreview("foo", "x", "gi".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "x x"

  test "updateSubstitutePreview with a pattern that does not compile undoes the last one":
    let e = createTestEditor()
    setBufferContent(e, "foo( foo")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "x", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "x( x"
    e.updateSubstitutePreview("foo(", "x", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "foo( foo"
    check e.state.ui.substitutePreview.isActive

suite ":s as it is typed":
  proc typing(content, command: string, last = SearchSpec()): Editor =
    let e = createTestEditor()
    setBufferContent(e, content)
    e.state.input.search.last = last
    e.state.input.search.ignorecase = true
    e.state.input.search.smartcase = true
    e.state.input.search.incsearch = true
    e.state.enterCommandOverlay()
    for ch in command:
      discard e.handleCommandModeKeyCombo(KeyCombo(isSpecial: false, char: $ch))
    e

  test "The preview finds an escaped slash as a slash":
    let e = typing("foo\nusr/bin", "%s/usr\\/bin")
    check e.state.ui.substitutePreview.isActive
    check e.cursor == BufferPosition(line: 1, column: 0)

  test "The first match follows 'ignorecase' as the highlight does":
    let e = typing("xx Foo\nfoo", "%s/foo")
    check e.cursor == BufferPosition(line: 0, column: 3)

  test "An upper case letter makes the first match exact":
    let e = typing("foo\nFoo", "%s/Foo")
    check e.cursor == BufferPosition(line: 1, column: 0)

  test "An escaped atom never makes the first match exact":
    let e = typing("FOObar\nfooX", "%s/foo\\S+")
    check e.cursor == BufferPosition(line: 0, column: 0)

  test "An escaped capital the regex matches as it is makes the first match exact":
    check typing("q\nQ", "%s/\\Q").cursor == BufferPosition(line: 1, column: 0)
    check typing("b\nB", "%s/[\\B]").cursor == BufferPosition(line: 1, column: 0)

  test "A class with an upper case letter makes the first match exact":
    check typing("abcd\nabcD", "%s/abc[D]").cursor == BufferPosition(line: 1, column: 0)

  test "A flag-only group never makes the first match exact":
    check typing("FOObar\nfoo", "%s/(?U)foo").cursor ==
      BufferPosition(line: 0, column: 0)

  test "The replacement preview ignores case as :s will":
    let e = typing("Foo\nfoo", "%s/foo/x/")
    check e.activeBuffer.getLine(0) == "x"
    check e.activeBuffer.getLine(1) == "x"

  test "A typed `I` makes the preview exact and `i` undoes it":
    let e = typing("Foo foo", "s/foo/x/I")
    check e.activeBuffer.getLine(0) == "Foo x"
    discard e.handleCommandModeKeyCombo(KeyCombo(isSpecial: false, char: "i"))
    check e.activeBuffer.getLine(0) == "x foo"

  test "A :s that `n` keeps from changing anything previews nothing":
    let e = typing("foo", "s/foo/x/n")
    check e.activeBuffer.getLine(0) == "foo"

  test "A :s it would refuse previews nothing":
    for command in ["s/foo/x/z", "s/foo/x/c"]:
      check typing("foo", command).activeBuffer.getLine(0) == "foo"

  test "The first match goes by the options, as 'incsearch' reads no flags":
    let e = typing("Foo\nfoo", "%s/foo/x/I")
    check e.cursor == BufferPosition(line: 0, column: 0)
    check e.activeBuffer.getLine(0) == "Foo"
    check e.activeBuffer.getLine(1) == "x"

  test "An empty pattern previews the last search, as :s will run it":
    let e = typing("foobar foo", "%s//X/g", SearchSpec(pattern: "foo", match: smWord))
    check e.state.ui.substitutePreview.isActive
    check e.activeBuffer.getLine(0) == "foobar X"

  test "An empty pattern jumps to the last search's first match":
    let e = typing("xx\nfzo", "%s//", SearchSpec(pattern: "f.o", match: smRegex))
    check e.cursor == BufferPosition(line: 1, column: 0)

  test "An empty pattern waits for its delimiter":
    let e = typing("xx\nfoo", "%s/", SearchSpec(pattern: "foo", match: smRegex))
    check not e.state.ui.substitutePreview.isActive
    check e.cursor == BufferPosition(line: 0, column: 0)

  test "The preview end follows the regex match, not the pattern length":
    let e = typing("foo abc a.c", "%s/(a).c")
    check e.cursor == BufferPosition(line: 0, column: 4)
    check e.state.input.line.wordAt == some(BufferPosition(line: 0, column: 7))

  test "A pattern that stops compiling as it is typed previews and finds nothing":
    # `%s/foo` takes the cursor to line 1; the `(` after it does not compile.
    let e = typing("xx\nfoo(", "%s/foo(/x/")
    check e.state.ui.substitutePreview.isActive
    check e.activeBuffer.getLine(1) == "foo("
    check e.cursor == BufferPosition(line: 0, column: 0)
    check e.state.input.line.wordAt == some(BufferPosition(line: 0, column: 0))
