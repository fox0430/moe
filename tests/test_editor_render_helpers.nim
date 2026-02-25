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

import
  ../src/moepkg/
    [editor, buffer, config, config_loader, modes, types, color, render_utils]
import ../src/moepkg/editor_render_helpers as renderHelpers

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
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
    let info = analyzeIndentation("\u3000hello")
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

suite "isVisualMode - Comprehensive":
  test "All visual modes return true":
    check renderHelpers.isVisualMode(EditorMode.Visual) == true
    check renderHelpers.isVisualMode(EditorMode.VisualLine) == true
    check renderHelpers.isVisualMode(EditorMode.VisualBlock) == true

  test "All non-visual modes return false":
    check renderHelpers.isVisualMode(EditorMode.Normal) == false
    check renderHelpers.isVisualMode(EditorMode.Insert) == false
    check renderHelpers.isVisualMode(EditorMode.Replace) == false
    check renderHelpers.isVisualMode(EditorMode.Filer) == false
    check renderHelpers.isVisualMode(EditorMode.LogViewer) == false
    check renderHelpers.isVisualMode(EditorMode.Help) == false
    check renderHelpers.isVisualMode(EditorMode.BufferManager) == false
    check renderHelpers.isVisualMode(EditorMode.Config) == false
    check renderHelpers.isVisualMode(EditorMode.Debug) == false

suite "getVisualSelection - Detailed":
  test "Default hasSelection is false":
    let e = createTestEditor()
    let result = e.getVisualSelection(EditorMode.Normal)
    check result.hasSelection == false
    check result.selStart.line == 0
    check result.selStart.column == 0
    check result.selEnd.line == 0
    check result.selEnd.column == 0

  test "Visual mode with selection":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 1, column: 5)
    e.state.visualSelection.current = BufferPosition(line: 3, column: 10)

    let result = e.getVisualSelection(EditorMode.Visual)
    check result.hasSelection == true

  test "VisualLine mode":
    let e = createTestEditor()
    e.state.mode = EditorMode.VisualLine
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskLine
    e.state.visualSelection.start = BufferPosition(line: 2, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 5, column: 0)

    let result = e.getVisualSelection(EditorMode.VisualLine)
    check result.hasSelection == true

  test "VisualBlock mode":
    let e = createTestEditor()
    e.state.mode = EditorMode.VisualBlock
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskBlock
    e.state.visualSelection.start = BufferPosition(line: 0, column: 2)
    e.state.visualSelection.current = BufferPosition(line: 4, column: 8)

    let result = e.getVisualSelection(EditorMode.VisualBlock)
    check result.hasSelection == true

  test "windowActive=false disables selection":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.active = true
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 1, column: 5)

    let result = e.getVisualSelection(EditorMode.Visual, windowActive = false)
    check result.hasSelection == false

suite "shouldShowIndentationGuide - Detailed":
  test "Disabled when showIndentationLines is false":
    let e = createTestEditor()
    e.state.display.showIndentationLines = false
    let info = IndentInfo(leadingWhitespaceEnd: 7, hasContent: true)

    check e.shouldShowIndentationGuide(info, 4, 2) == false

  test "No guide at displayX 0":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 7, hasContent: true)

    check e.shouldShowIndentationGuide(info, 0, 0) == false

  test "Guide at tabStop multiples":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 4
    let info = IndentInfo(leadingWhitespaceEnd: 11, hasContent: true)

    # displayX=4 is a multiple of 4
    check e.shouldShowIndentationGuide(info, 4, 3) == true
    # displayX=8 is a multiple of 4
    check e.shouldShowIndentationGuide(info, 8, 7) == true

  test "No guide at non-tabStop positions":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 4
    let info = IndentInfo(leadingWhitespaceEnd: 11, hasContent: true)

    check e.shouldShowIndentationGuide(info, 1, 0) == false
    check e.shouldShowIndentationGuide(info, 2, 1) == false
    check e.shouldShowIndentationGuide(info, 3, 2) == false
    check e.shouldShowIndentationGuide(info, 5, 4) == false

  test "No guide when hasContent is false":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: -1, hasContent: false)

    check e.shouldShowIndentationGuide(info, 2, 1) == false
    check e.shouldShowIndentationGuide(info, 4, 3) == false

  test "No guide past leadingWhitespaceEnd":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 3, hasContent: true)

    # charIdx=4 is past whitespace end (3)
    check e.shouldShowIndentationGuide(info, 4, 4) == false
    # charIdx=5 is past whitespace end
    check e.shouldShowIndentationGuide(info, 6, 5) == false

  test "No guide for negative charIdx":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 5, hasContent: true)

    check e.shouldShowIndentationGuide(info, 2, -1) == false

suite "isPositionInDocumentHighlight - Detailed":
  test "Returns none when disabled":
    let e = createTestEditor()
    e.state.display.showDocumentHighlight = false
    e.state.lspCache.documentHighlightCache.isValid = true

    let result = e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 5))
    check result.isNone

  test "Returns none when cache invalid":
    let e = createTestEditor()
    e.state.display.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = false

    let result = e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 5))
    check result.isNone

  test "Returns none for line without highlights":
    let e = createTestEditor()
    e.state.display.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine =
      {0: @[DocumentHighlightItem(startColumn: 5, endColumn: 10, kind: 2)]}.toTable

    let result = e.isPositionInDocumentHighlight(BufferPosition(line: 1, column: 5))
    check result.isNone

  test "Returns kind for position in range":
    let e = createTestEditor()
    e.state.display.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine =
      {0: @[DocumentHighlightItem(startColumn: 5, endColumn: 10, kind: 2)]}.toTable

    let result = e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 5))
    check result.isSome
    check result.get == 2

  test "Exclusive end column":
    let e = createTestEditor()
    e.state.display.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine =
      {0: @[DocumentHighlightItem(startColumn: 5, endColumn: 10, kind: 1)]}.toTable

    # Column 9 is the last included column
    let resultIn = e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 9))
    check resultIn.isSome

    # Column 10 is excluded (endColumn is exclusive)
    let resultOut = e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 10))
    check resultOut.isNone

  test "Multiple highlights on same line":
    let e = createTestEditor()
    e.state.display.showDocumentHighlight = true
    e.state.lspCache.documentHighlightCache.isValid = true
    e.state.lspCache.documentHighlightCache.itemsByLine = {
      0: @[
        DocumentHighlightItem(startColumn: 0, endColumn: 5, kind: 1),
        DocumentHighlightItem(startColumn: 10, endColumn: 15, kind: 2),
        DocumentHighlightItem(startColumn: 20, endColumn: 25, kind: 3),
      ]
    }.toTable

    let result1 = e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 2))
    check result1.isSome
    check result1.get == 1

    let result2 = e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 12))
    check result2.isSome
    check result2.get == 2

    let result3 = e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 22))
    check result3.isSome
    check result3.get == 3

    # Between highlights
    let resultBetween =
      e.isPositionInDocumentHighlight(BufferPosition(line: 0, column: 7))
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

suite "getSelectionStyle - Basic":
  test "Returns cursor style at cursor position":
    let e = createTestEditor()
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    # At cursor position, should return cursor char style
    check true

  test "Returns normal style for non-cursor position":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check true

  test "Returns visual style when in selection":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 10)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 0,
      cursorCol = 10,
      windowMode = EditorMode.Visual,
    )
    check true

suite "getSelectionStyle - Matching paren":
  test "Returns paren pair style for matching paren":
    let e = createTestEditor()
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "(hello)")
    e.state.matchingParenPos = some(BufferPosition(line: 0, column: 6))

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 6),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

suite "getSelectionStyle - Find char match highlight (f/F/t/T)":
  test "Returns findCharMatch style for matched position":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.findCharMatches = @[0, 2, 4, 6]
    e.state.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style == findCharMatchStyle()

  test "Does not return findCharMatch style for non-matched position":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.findCharMatches = @[0, 2, 4, 6]
    e.state.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 1),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

  test "Does not return findCharMatch style for different line":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard
      e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada\nabacada")
    e.state.findCharMatches = @[0, 2, 4, 6]
    e.state.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 1, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

  test "No findCharMatch style when matches list is empty":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.findCharMatches = @[]
    e.state.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

  test "Visual selection takes priority over findCharMatch":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 6)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.findCharMatches = @[0, 2, 4, 6]
    e.state.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 2),
      cursorLine = 0,
      cursorCol = 6,
      windowMode = EditorMode.Visual,
    )
    check style == visualStyle()

  test "Matching paren takes priority over findCharMatch":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "(abacada)")
    e.state.matchingParenPos = some(BufferPosition(line: 0, column: 8))
    e.state.findCharMatches = @[1, 3, 5, 7]
    e.state.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 8),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check style == parenPairStyle()

  test "No findCharMatch style when findCharHighlight config is false":
    let e = createTestEditor()
    e.config.highlight.findCharHighlight = false
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.findCharMatches = @[0, 2, 4, 6]
    e.state.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

suite "getSelectionStyle - Search highlight":
  test "Returns search highlight style when search matches":
    let e = createTestEditor()
    e.state.search.hlsearch = true
    e.state.search.hlsearchTempDisabled = false
    e.state.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    discard
      e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world hello")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 5, # Cursor on different line
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No search highlight when hlsearch is disabled":
    let e = createTestEditor()
    e.state.search.hlsearch = false
    e.state.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 5,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No search highlight when hlsearchTempDisabled":
    let e = createTestEditor()
    e.state.search.hlsearch = true
    e.state.search.hlsearchTempDisabled = true
    e.state.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 5,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

suite "getSelectionStyle - Cursor line":
  test "Returns cursor line style when on cursor line":
    let e = createTestEditor()
    e.state.display.showCursorLine = true
    e.state.display.showSyntax = false
    e.state.display.showDocumentHighlight = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No cursor line style when showCursorLine is false":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
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

suite "getSelectionStyle - Cursor column":
  test "Returns cursor column bg when on cursor column":
    let e = createTestEditor()
    e.state.display.showCursorColumn = true
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    e.state.display.showDocumentHighlight = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 1,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
      displayCol = 5,
      cursorDisplayCol = 5,
    )
    check style.bg == cursorColumnHighlightStyle().bg

  test "No cursor column style when showCursorColumn is false":
    let e = createTestEditor()
    e.state.display.showCursorColumn = false
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 1,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
      displayCol = 5,
      cursorDisplayCol = 5,
    )
    check style.bg == normalStyle().bg

  test "No cursor column style when displayCol does not match":
    let e = createTestEditor()
    e.state.display.showCursorColumn = true
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 1,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
      displayCol = 3,
      cursorDisplayCol = 5,
    )
    check style.bg == normalStyle().bg

  test "Cursor line takes priority over cursor column at intersection":
    let e = createTestEditor()
    e.state.display.showCursorColumn = true
    e.state.display.showCursorLine = true
    e.state.display.showSyntax = false
    e.state.display.showDocumentHighlight = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # At intersection (same line AND same column): cursorLine wins
    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
      displayCol = 5,
      cursorDisplayCol = 5,
    )
    check style.bg == cursorLineHighlightStyle().bg

  test "No cursor column when displayCol params not provided":
    let e = createTestEditor()
    e.state.display.showCursorColumn = true
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Without displayCol/cursorDisplayCol params (default -1), no column highlight
    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 1,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check style.bg == normalStyle().bg

suite "IndentInfo structure":
  test "Default values":
    var info: IndentInfo
    check info.leadingWhitespaceEnd == 0
    check info.hasContent == false

  test "Initialized values":
    let info = IndentInfo(leadingWhitespaceEnd: 5, hasContent: true)
    check info.leadingWhitespaceEnd == 5
    check info.hasContent == true

suite "renderLineSegmentWithSelection - trailing space highlight":
  test "Normal mode highlights trailing spaces":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("hello   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "hello   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    # Trailing spaces (columns 5, 6, 7) should have trailing space style
    check buf[5, 0].style == trailingStyle
    check buf[6, 0].style == trailingStyle
    check buf[7, 0].style == trailingStyle

  test "Help mode does not highlight trailing spaces":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("hello   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Help,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "hello   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    # Trailing spaces should NOT have trailing space style in Help mode
    check buf[5, 0].style != trailingStyle
    check buf[6, 0].style != trailingStyle
    check buf[7, 0].style != trailingStyle

  test "BufferManager mode does not highlight trailing spaces":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("entry   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.BufferManager,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "entry   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    check buf[5, 0].style != trailingStyle

  test "DiffViewer mode does not highlight trailing spaces":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("diff   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.DiffViewer,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "diff   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    check buf[4, 0].style != trailingStyle

suite "renderLineSegmentWithSelection - full-width space highlight":
  test "Normal mode highlights full-width space":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.fullWidthSpace = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let text = "ab" & $FULLWIDTH_SPACE & "cd"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let fwStyle = fullWidthSpaceStyle()
    # Full-width space at column 2 (takes 2 display cells) should be highlighted
    check buf[2, 0].style == fwStyle

  test "Help mode does not highlight full-width space":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.fullWidthSpace = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let text = "ab" & $FULLWIDTH_SPACE & "cd"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Help,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let fwStyle = fullWidthSpaceStyle()
    check buf[2, 0].style != fwStyle

  test "Debug mode does not highlight full-width space":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.fullWidthSpace = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let text = "ab" & $FULLWIDTH_SPACE & "cd"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Debug,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let fwStyle = fullWidthSpaceStyle()
    check buf[2, 0].style != fwStyle

suite "renderLineSegmentWithSelection - tab trailing space highlight":
  test "Normal mode highlights trailing tab":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false
    e.state.display.tabStop = 4

    let text = "ab\t"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    # Tab at column 2 expands to spaces; column 2 should have trailing style
    check buf[2, 0].style == trailingStyle

  test "Help mode does not highlight trailing tab":
    let config = newEditorConfig()
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false
    e.state.display.tabStop = 4

    let text = "ab\t"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Help,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    check buf[2, 0].style != trailingStyle
