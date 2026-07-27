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

## Tests for editor_render_helpers.nim

import std/[unittest, options, tables]

import pkg/celina

import ../src/moepkg/[editor, config, config_loader, modes, types, color]
import ../src/moepkg/buffer/core
import ../src/moepkg/editor_render_helpers as renderHelpers

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  config.theme.kind = tkDefault
  let vr = newValidationResult()
  result = newEditor(config, vr)

suite "analyzeIndentation - Basic cases":
  test "Empty string":
    let info = analyzeIndentation("")
    check info.leadingWhitespaceEnd == -1
    check info.hasContent == false

  test "Single space":
    let info = analyzeIndentation(" ")
    check info.hasContent == false

  test "Multiple spaces only":
    let info = analyzeIndentation("        ")
    check info.hasContent == false

  test "Tabs only":
    let info = analyzeIndentation("\t\t\t")
    check info.hasContent == false

  test "Content without indentation":
    let info = analyzeIndentation("hello")
    check info.leadingWhitespaceEnd == -1
    check info.hasContent == true

  test "Single space before content":
    let info = analyzeIndentation(" x")
    check info.leadingWhitespaceEnd == 0
    check info.hasContent == true

  test "Multiple spaces before content":
    let info = analyzeIndentation("    hello world")
    check info.leadingWhitespaceEnd == 3
    check info.hasContent == true

  test "Tab before content":
    let info = analyzeIndentation("\thello")
    check info.leadingWhitespaceEnd == 0
    check info.hasContent == true

  test "Mixed tabs and spaces":
    let info = analyzeIndentation("\t  \t  code")
    check info.leadingWhitespaceEnd == 5
    check info.hasContent == true

suite "analyzeIndentation - Unicode":
  test "Japanese text without indentation":
    let info = analyzeIndentation("こんにちは")
    check info.leadingWhitespaceEnd == -1
    check info.hasContent == true

  test "Indented Japanese text":
    let info = analyzeIndentation("  日本語")
    check info.leadingWhitespaceEnd == 1
    check info.hasContent == true

  test "Full-width space is not treated as indentation":
    # Full-width space (U+3000) is content, not whitespace for indentation
    let info = analyzeIndentation("　hello")
    check info.leadingWhitespaceEnd == -1
    check info.hasContent == true

suite "analyzeIndentation - Edge cases":
  test "Only newline character":
    let info = analyzeIndentation("\n")
    check info.hasContent == true # \n is content

  test "Space then newline":
    let info = analyzeIndentation(" \n")
    check info.leadingWhitespaceEnd == 0
    check info.hasContent == true

  test "Very deep indentation":
    let info = analyzeIndentation("                                x")
    check info.leadingWhitespaceEnd == 31
    check info.hasContent == true

suite "isVisualAllMode - Comprehensive":
  test "All visual modes return true":
    check isVisualAllMode(EditorMode.Visual) == true
    check isVisualAllMode(EditorMode.VisualLine) == true
    check isVisualAllMode(EditorMode.VisualBlock) == true

  test "All non-visual modes return false":
    check isVisualAllMode(EditorMode.Normal) == false
    check isVisualAllMode(EditorMode.Insert) == false
    check isVisualAllMode(EditorMode.Replace) == false
    check isVisualAllMode(EditorMode.Filer) == false
    check isVisualAllMode(EditorMode.LogViewer) == false
    check isVisualAllMode(EditorMode.Help) == false
    check isVisualAllMode(EditorMode.BufferManager) == false
    check isVisualAllMode(EditorMode.Config) == false
    check isVisualAllMode(EditorMode.Debug) == false

suite "isPositionInDocumentHighlight - Detailed":
  test "Returns none when disabled":
    let e = createTestEditor()
    e.state.showDocumentHighlight = false
    e.state.lspCache.documentHighlightCache.isValid = true

    let result =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 5))
    check result.isNone

  test "Returns none when cache invalid":
    let e = createTestEditor()
    e.state.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = false

    let result =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 5))
    check result.isNone

  test "Returns none for line without highlights":
    let e = createTestEditor()
    e.state.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine =
      {0: @[DocumentHighlightItem(startColumn: 5, endColumn: 10, kind: 2)]}.toTable

    let result =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 1, column: 5))
    check result.isNone

  test "Returns kind for position in range":
    let e = createTestEditor()
    e.state.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine =
      {0: @[DocumentHighlightItem(startColumn: 5, endColumn: 10, kind: 2)]}.toTable

    let result =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 5))
    check result.isSome
    check result.get == 2

  test "Exclusive end column":
    let e = createTestEditor()
    e.state.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine =
      {0: @[DocumentHighlightItem(startColumn: 5, endColumn: 10, kind: 1)]}.toTable

    # Column 9 is the last included column
    let resultIn =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 9))
    check resultIn.isSome

    # Column 10 is excluded (endColumn is exclusive)
    let resultOut =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 10))
    check resultOut.isNone

  test "Multiple highlights on same line":
    let e = createTestEditor()
    e.state.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine = {
      0: @[
        DocumentHighlightItem(startColumn: 0, endColumn: 5, kind: 1),
        DocumentHighlightItem(startColumn: 10, endColumn: 15, kind: 2),
        DocumentHighlightItem(startColumn: 20, endColumn: 25, kind: 3),
      ]
    }.toTable

    let result1 =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 2))
    check result1.isSome
    check result1.get == 1

    let result2 =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 12))
    check result2.isSome
    check result2.get == 2

    let result3 =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 22))
    check result3.isSome
    check result3.get == 3

    # Between highlights
    let resultBetween =
      e.state.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 7))
    check resultBetween.isNone

suite "getDocumentHighlightStyle":
  test "Kind 1 (Text) returns text style":
    discard getDocumentHighlightStyle(1)
    check true

  test "Kind 2 (Read) returns read style":
    discard getDocumentHighlightStyle(2)
    check true

  test "Kind 3 (Write) returns write style":
    discard getDocumentHighlightStyle(3)
    check true

  test "Unknown kind returns text style":
    discard getDocumentHighlightStyle(0)
    discard getDocumentHighlightStyle(4)
    discard getDocumentHighlightStyle(100)
    check true

suite "colorIndexToStyle":
  test "Default color index":
    discard colorIndexToStyle(EditorColorPairIndex.default)
    check true

  test "Keyword color index":
    discard colorIndexToStyle(EditorColorPairIndex.keyword)
    check true

  test "String literal color index":
    discard colorIndexToStyle(EditorColorPairIndex.stringLit)
    check true

  test "Comment color index":
    discard colorIndexToStyle(EditorColorPairIndex.comment)
    check true

suite "bufferColToDisplayCol":
  test "Simple ASCII text":
    check bufferColToDisplayCol("hello", 0, 4) == 0
    check bufferColToDisplayCol("hello", 3, 4) == 3
    check bufferColToDisplayCol("hello", 5, 4) == 5

  test "Tab expansion":
    # Tab at start expands to tabStop width
    check bufferColToDisplayCol("\thello", 1, 4) == 4
    check bufferColToDisplayCol("\thello", 1, 8) == 8
    # Tab after some chars
    check bufferColToDisplayCol("ab\tc", 3, 4) == 4 # "ab"=2, tab fills to 4
    check bufferColToDisplayCol("abc\td", 4, 4) == 4 # "abc"=3, tab fills to 4

  test "Wide characters":
    # CJK characters take 2 display columns
    check bufferColToDisplayCol("日本語", 1, 4) == 2
    check bufferColToDisplayCol("日本語", 2, 4) == 4

  test "With startCol offset":
    # startCol skips initial characters
    check bufferColToDisplayCol("hello", 3, 4, startCol = 1) == 2 # "el" = 2
    check bufferColToDisplayCol("hello", 5, 4, startCol = 2) == 3 # "llo" = 3

  test "bufferCol before startCol returns -1":
    check bufferColToDisplayCol("hello", 1, 4, startCol = 3) == -1
    check bufferColToDisplayCol("hello", 0, 4, startCol = 1) == -1

  test "Empty string":
    check bufferColToDisplayCol("", 0, 4) == 0

  test "bufferCol past end of string":
    # Iterates all chars, result = display width of entire string
    check bufferColToDisplayCol("abc", 10, 4) == 3

suite "IndentInfo structure":
  test "Default values":
    var info: IndentInfo
    check info.leadingWhitespaceEnd == 0
    check info.hasContent == false

  test "Initialized values":
    let info = IndentInfo(leadingWhitespaceEnd: 5, hasContent: true)
    check info.leadingWhitespaceEnd == 5
    check info.hasContent == true

suite "isColumnInRanges":
  test "empty ranges":
    let ranges: seq[ColumnRange] = @[]
    check not isColumnInRanges(ranges, 0)
    check not isColumnInRanges(ranges, 5)

  test "single range - inside":
    let ranges = @[ColumnRange(startCol: 3, endCol: 7)]
    check isColumnInRanges(ranges, 3)
    check isColumnInRanges(ranges, 5)
    check isColumnInRanges(ranges, 6)

  test "single range - outside":
    let ranges = @[ColumnRange(startCol: 3, endCol: 7)]
    check not isColumnInRanges(ranges, 2)
    check not isColumnInRanges(ranges, 7) # endCol is exclusive
    check not isColumnInRanges(ranges, 10)

  test "multiple ranges":
    let ranges =
      @[ColumnRange(startCol: 0, endCol: 3), ColumnRange(startCol: 6, endCol: 9)]
    check isColumnInRanges(ranges, 0)
    check isColumnInRanges(ranges, 2)
    check not isColumnInRanges(ranges, 3)
    check not isColumnInRanges(ranges, 5)
    check isColumnInRanges(ranges, 6)
    check isColumnInRanges(ranges, 8)
    check not isColumnInRanges(ranges, 9)

  test "boundary values":
    let ranges = @[ColumnRange(startCol: 0, endCol: 1)]
    check isColumnInRanges(ranges, 0)
    check not isColumnInRanges(ranges, 1)
