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

import std/[options, tables, unittest]

import pkg/results

import
  ../src/moepkg/[
    editor, config, config_loader, editor_substitute, highlight, key_bindings,
    primitives, types,
  ]
import ../src/moepkg/command_handlers/command_mode_handler
import ../src/moepkg/types/editor_types
import ../src/moepkg/buffer
import ../src/moepkg/command_line/substitute_parser
import ../src/moepkg/git_conflict
import ../src/moepkg/editor_reload

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc setBufferContent(e: Editor, content: string) =
  e.activeWindow.setTab(newTextBuffer(content))

proc textLines(b: TextBuffer): seq[string] =
  for line in b.lines:
    result.add line

suite "editor_substitute":
  test "startSubstitutePreview opens a preview on the active buffer":
    let e = createTestEditor()
    setBufferContent(e, "foo bar foo\nbar baz")
    e.startSubstitutePreview()
    check e.state.ui.substitutePreview.isActive
    check e.state.ui.substitutePreview.buffer == e.activeBuffer
    check e.state.ui.substitutePreview.swap.isNone

  test "startSubstitutePreview is a no-op when already active":
    let e = createTestEditor()
    setBufferContent(e, "foo")
    e.startSubstitutePreview()
    e.updateSubstitutePreview("foo", "x", "".parseSubstituteFlags, smRegex)
    e.startSubstitutePreview()
    check e.state.ui.substitutePreview.swap.isSome
    e.cancelSubstitutePreview()
    check e.activeBuffer.getLine(0) == "foo"

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
    check e.state.ui.substitutePreview.swap.isNone

  test "restoreFromPreview takes back the lines a preview broke":
    let e = createTestEditor()
    setBufferContent(e, "a,b,c\nx")
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r", "g".parseSubstituteFlags, smRegex)
    check e.activeBuffer.len == 4
    e.restoreFromPreview()
    check e.activeBuffer.textLines == @["a,b,c", "x"]
    check e.state.ui.substitutePreview.swap.isNone

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

  test "Typing a pattern alone writes nothing to the buffer":
    let e = createTestEditor()
    setBufferContent(e, "foo\nbar")
    let version = e.activeBuffer.contentVersion
    e.state.enterCommandOverlay()
    for ch in "%s/fo":
      discard e.handleCommandModeKeyCombo(KeyCombo(isSpecial: false, char: $ch))
    check e.state.ui.substitutePreview.isActive
    check e.activeBuffer.contentVersion == version

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

  proc typeKeys(e: Editor, keys: string) =
    for ch in keys:
      discard e.handleCommandModeKeyCombo(KeyCombo(isSpecial: false, char: $ch))

  test "The closing `/` leaves the preview as it was written":
    let e = typing("a,b\na,b", "%s/,/-")
    check e.activeBuffer.textLines == @["a-b", "a-b"]
    let version = e.activeBuffer.contentVersion
    e.typeKeys("/")
    check e.activeBuffer.contentVersion == version
    check e.state.input.line.wordAt == some(BufferPosition(line: 0, column: 0))

  test "A change made under an unchanged preview is previewed":
    let e = typing("x", "%s/a/b")
    check e.state.ui.substitutePreview.swap.isNone
    check e.activeBuffer.replaceLine(0, "a").isOk
    e.typeKeys("/")
    check e.activeBuffer.getLine(0) == "b"

  test "The view stays on the text a broken line above it moves down":
    var content = "a,b"
    for _ in 0 ..< 40:
      content.add "\nx"
    let e = createTestEditor()
    setBufferContent(e, content)
    e.state.input.search.incsearch = false
    e.cursor = BufferPosition(line: 30, column: 0)
    e.activeWindow.viewport.topLine = 20
    e.state.enterCommandOverlay()
    e.typeKeys("%s/,/\\r")
    check e.activeBuffer.len == 42
    check e.cursor == BufferPosition(line: 31, column: 0)
    check e.activeWindow.viewport.topLine == 21

suite "editor_substitute - a preview that breaks lines":
  test "the line arrays keep the buffer's length and move with their rows":
    let e = createTestEditor()
    setBufferContent(e, "a,b\nx\ny")
    let buffer = e.activeBuffer
    buffer.ensureMarkersSize()
    buffer.ensureModifiedLinesSize()
    buffer.setLineMarker(2, GitAdded)
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r\\r", "".parseSubstituteFlags, smRegex)
    check buffer.len == 5
    check buffer.lineMarkers.len == 5
    check buffer.modifiedLines.len == 5
    check buffer.lineMarkers[4] == some(GitAdded)
    # A rescan for conflict markers reads a marker for every row.
    buffer.refreshConflicts()

    e.restoreFromPreview()
    check buffer.len == 3
    check buffer.lineMarkers.len == 3
    check buffer.modifiedLines.len == 3
    check buffer.lineMarkers[2] == some(GitAdded)

  test "a preview drops the CR a backslash keeps, as :s does":
    let e = createTestEditor()
    setBufferContent(e, "a,b")
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "-\\\r-", "".parseSubstituteFlags, smRegex)
    check e.activeBuffer.getLine(0) == "a--b"

  test "restoring after something else changed the buffer writes into no row":
    let e = createTestEditor()
    setBufferContent(e, "a,b\nx")
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r", "".parseSubstituteFlags, smRegex)
    check e.activeBuffer.len == 3
    discard e.activeBuffer.replaceLinesNoUndo(1, 1, [])
    check not e.activeBuffer.isModified
    e.restoreFromPreview()
    check e.activeBuffer.textLines == @["a", "x"]
    check e.state.ui.substitutePreview.swap.isNone
    # The preview's lines stay, so the buffer says it holds a change.
    check e.activeBuffer.isModified

  test "a preview writes no line a :s would refuse":
    let e = createTestEditor()
    setBufferContent(e, "a,b")
    check e.activeBuffer.replaceLinesNoUndo(0, 1, ["x\ny"]).isNone
    check e.activeBuffer.len == 1
    check e.activeBuffer.getLine(0) == "a,b"

suite "editor_substitute - taking a preview back":
  proc tokens(columns: varargs[int]): SemanticOverlayLine =
    for column in columns:
      result.tokens.add SemanticOverlayToken(firstColumn: column, length: 2)

  proc spans(overlay: Table[int, SemanticOverlayLine]): seq[(int, int)] =
    ## Each token's row and column, by row.
    for row in 0 ..< 8:
      overlay.withValue(row, line):
        for token in line.tokens:
          result.add (row, token.firstColumn)

  test "the semantic overlay goes back to its rows, the broken one included":
    let e = createTestEditor()
    setBufferContent(e, "aa\nbb,cc\ndd\nee")
    let buffer = e.activeBuffer
    if buffer.highlight.isNil:
      buffer.highlight = Highlight(colorSegments: @[])
    buffer.highlight.semantic =
      {0: tokens(0), 1: tokens(0, 3), 2: tokens(0), 3: tokens(1)}.toTable
    buffer.highlight.semanticContentVersion = buffer.contentVersion
    let before = buffer.highlight.semantic
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r", "".parseSubstituteFlags, smRegex)
    check buffer.textLines == @["aa", "bb", "cc", "dd", "ee"]
    # While it shows, the rows below the break keep their colours.
    check buffer.highlight.semantic.spans == @[(0, 0), (1, 0), (3, 0), (4, 1)]
    e.cancelSubstitutePreview()
    check buffer.highlight.semantic.spans == before.spans
    check buffer.highlight.semanticContentVersion == buffer.contentVersion

  test "a line marker that arrives while it shows stays with its row":
    let e = createTestEditor()
    setBufferContent(e, "a,b\nx\ny")
    let buffer = e.activeBuffer
    buffer.ensureMarkersSize()
    buffer.ensureModifiedLinesSize()
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r", "".parseSubstituteFlags, smRegex)
    buffer.setLineMarker(3, GitAdded)
    e.cancelSubstitutePreview()
    check buffer.lineMarkers.len == 3
    check buffer.lineMarkers[2] == some(GitAdded)

  test "folds go back to their rows":
    let e = createTestEditor()
    setBufferContent(e, "a,b\nx\ny\nz")
    let buffer = e.activeBuffer
    check buffer.foldState.addFold(1, 2)
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r\\r", "".parseSubstituteFlags, smRegex)
    check buffer.foldState.getFoldAtStartLine(3).isSome
    e.cancelSubstitutePreview()
    check buffer.foldState.folds.len == 1
    check buffer.foldState.folds[0].startLine == 1
    check buffer.foldState.folds[0].endLine == 2

  test "an edit of the replacement takes back only what the preview wrote":
    let e = createTestEditor()
    setBufferContent(e, "a,b\nx,y\nz")
    let buffer = e.activeBuffer
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r", "g".parseSubstituteFlags, smRegex)
    check buffer.textLines == @["a", "b", "x", "y", "z"]
    e.updateSubstitutePreview(",", "-", "g".parseSubstituteFlags, smRegex)
    check buffer.textLines == @["a-b", "x-y", "z"]
    e.updateSubstitutePreview(
      ",", "\\r", "".parseSubstituteFlags, smRegex, lastLine = 0
    )
    check buffer.textLines == @["a", "b", "x,y", "z"]
    e.cancelSubstitutePreview()
    check buffer.textLines == @["a,b", "x,y", "z"]

suite "editor_substitute - what the preview moves":
  test "diagnostics go down with their rows and come back":
    let e = createTestEditor()
    setBufferContent(e, "a,b\nx\ny")
    e.activeBuffer.setDiagnostics(
      dsrcSyntaxCheck, @[BufferDiagnostic(startLine: 2, endLine: 2, severity: bdsError)]
    )
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r", "".parseSubstituteFlags, smRegex, 0, 0)
    check e.activeBuffer.diagnosticMarker(3).isSome
    check e.activeBuffer.diagnosticMarker(2).isNone
    e.cancelSubstitutePreview()
    check e.activeBuffer.diagnosticMarker(2).isSome
    check e.activeBuffer.diagnosticMarker(3).isNone

  test "the view starts a top line the preview rewrote from its first row":
    let e = createTestEditor()
    setBufferContent(e, "a\nb,c\nd")
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r", "".parseSubstituteFlags, smRegex)
    check e.inPreview((topLine: 1, topWrapOffset: 2, leftCell: 0)) ==
      (topLine: 1, topWrapOffset: 0, leftCell: 0)
    check e.inPreview((topLine: 2, topWrapOffset: 2, leftCell: 0)) ==
      (topLine: 3, topWrapOffset: 2, leftCell: 0)

  test "replacing the buffer under a preview puts the cursor back first":
    let e = createTestEditor()
    setBufferContent(e, "a,b\na,b\nx")
    e.activeWindow.cursor = BufferPosition(line: 2, column: 0)
    e.startSubstitutePreview()
    e.updateSubstitutePreview(",", "\\r", "".parseSubstituteFlags, smRegex)
    e.cursor = e.inPreview(e.state.ui.substitutePreview.originalCursor)
    check e.cursor.line == 4
    e.invalidatePositionStateForBuffer(e.activeBuffer)
    check not e.state.ui.substitutePreview.isActive
    check e.cursor.line == 2
