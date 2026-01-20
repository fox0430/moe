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

import std/[unittest, unicode]

import ../src/moepkg/highlight
import ../src/moepkg/syntax/highlite

suite "Highlight - Basic Initialization":
  test "initHighlight with empty buffer":
    let buffer: seq[Runes] = @[]
    let h = initHighlight(buffer)
    check h.colorSegments.len == 0

  test "initHighlight with single line":
    let buffer = @["hello".toRunes]
    let h = initHighlight(buffer)
    check h.colorSegments.len == 1
    check h[0].firstRow == 0
    check h[0].lastRow == 0
    check h[0].color == EditorColorPairIndex.default

  test "initHighlight with multiple lines":
    let buffer = @["line1".toRunes, "line2".toRunes, "line3".toRunes]
    let h = initHighlight(buffer)
    check h.colorSegments.len == 3
    check h[0].firstRow == 0
    check h[1].firstRow == 1
    check h[2].firstRow == 2

  test "initHighlight with empty line":
    let buffer = @["line1".toRunes, "".toRunes, "line3".toRunes]
    let h = initHighlight(buffer)
    check h.colorSegments.len == 3
    check h[1].firstRow == 1
    check h[1].lastRow == 1
    check h[1].lastColumn == -1 # Empty line

suite "Highlight - TokenizerState Capture/Restore":
  test "captureTokenizerState captures all fields":
    var token = GeneralTokenizer()
    token.initGeneralTokenizer("test")
    token.state = gtKeyword
    token.templateLiteralDepth = 5
    token.braceDepthStack = @[1, 2, 3]
    token.commentDepth = 2
    token.inJsxMode = true

    let state = captureTokenizerState(token)
    check state.state == gtKeyword
    check state.templateLiteralDepth == 5
    check state.braceDepthStack == @[1, 2, 3]
    check state.commentDepth == 2
    check state.inJsxMode == true

  test "restoreTokenizerState restores all fields":
    var token = GeneralTokenizer()
    token.initGeneralTokenizer("test")

    let state = TokenizerState(
      state: gtStringLit,
      templateLiteralDepth: 3,
      braceDepthStack: @[5, 6],
      commentDepth: 1,
      inJsxMode: false,
      jsxTagDepth: 0,
      inComment: true,
      inScript: false,
      inStyle: false,
      astroInFrontmatter: false,
      astroFirstLine: false,
    )

    token.restoreTokenizerState(state)
    check token.state == gtStringLit
    check token.templateLiteralDepth == 3
    check token.braceDepthStack == @[5, 6]
    check token.commentDepth == 1
    check token.inJsxMode == false
    check token.inComment == true

suite "Highlight - Incremental Initialization":
  test "initHighlightIncremental with empty buffer":
    let buffer: seq[Runes] = @[]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 0, TokenizerState(), @[], SourceLanguage.langRust
    )
    check segments.len == 0
    check lineStates.len == 0

  test "initHighlightIncremental with single line":
    let buffer = @["let x = 5;".toRunes]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 0, TokenizerState(), @[], SourceLanguage.langRust
    )
    check segments.len > 0
    check lineStates.len == 1

  test "initHighlightIncremental with multiple lines":
    let buffer = @["fn main() {".toRunes, "    let x = 5;".toRunes, "}".toRunes]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    check segments.len > 0
    check lineStates.len == 3

  test "initHighlightIncremental partial range":
    let buffer =
      @[
        "line1".toRunes, "line2".toRunes, "line3".toRunes, "line4".toRunes,
        "line5".toRunes,
      ]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 1, 3, TokenizerState(), @[], SourceLanguage.langRust
    )
    # Should return 3 line states (lines 1, 2, 3)
    check lineStates.len == 3
    # Segments should be for lines 1-3
    for seg in segments:
      check seg.firstRow >= 1
      check seg.lastRow <= 3

  test "initHighlightIncremental with initial state":
    let buffer =
      @["/* comment".toRunes, "still comment */".toRunes, "fn main() {}".toRunes]

    # First parse full buffer
    let (segments1, lineStates1) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    check segments1.len > 0 # Verify full parse worked

    # Parse line 2 onwards with state from line 1
    let (segments2, lineStates2) = initHighlightIncremental(
      buffer, 2, 2, lineStates1[1], @[], SourceLanguage.langRust
    )

    check segments2.len > 0
    check lineStates2.len == 1

suite "Highlight - Incremental Update":
  test "updateHighlightIncremental without buffer size change":
    let buffer = @["fn main() {".toRunes, "    let x = 5;".toRunes, "}".toRunes]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates, version: 0)
    )

    # Update after editing line 1 (no size change)
    updateHighlightIncremental(
      buffer, incrHighlight, 1, 1, 1, @[], SourceLanguage.langRust
    )

    check incrHighlight.segments.len > 0
    check incrHighlight.lineStates.states.len == 3
    check incrHighlight.lineStates.version == 1

  test "updateHighlightIncremental with buffer size increase":
    var buffer = @["line1".toRunes, "line2".toRunes, "line3".toRunes]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates, version: 0)
    )

    # Add a line
    buffer.add("line4".toRunes)

    # Update with size change
    updateHighlightIncremental(
      buffer, incrHighlight, 3, 3, 1, @[], SourceLanguage.langRust
    )

    # Line states should be resized to match buffer
    check incrHighlight.lineStates.states.len == 4
    check incrHighlight.lineStates.version == 1

  test "updateHighlightIncremental with buffer size decrease":
    var buffer = @["line1".toRunes, "line2".toRunes, "line3".toRunes, "line4".toRunes]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 3, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates, version: 0)
    )

    # Remove a line
    buffer.delete(2)

    # Update with size change
    updateHighlightIncremental(
      buffer, incrHighlight, 2, 2, 1, @[], SourceLanguage.langRust
    )

    # Line states should be resized to match buffer
    check incrHighlight.lineStates.states.len == 3
    check incrHighlight.lineStates.version == 1

  test "updateHighlightIncremental safety margin":
    let buffer =
      @[
        "line0".toRunes, "line1".toRunes, "line2".toRunes, "line3".toRunes,
        "line4".toRunes,
      ]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 4, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates, version: 0)
    )

    # Edit line 2 - should re-parse with safety margin
    # Safety margin is 50, but buffer is only 5 lines, so should re-parse all
    updateHighlightIncremental(
      buffer, incrHighlight, 2, 2, 1, @[], SourceLanguage.langRust
    )

    check incrHighlight.segments.len > 0
    check incrHighlight.lineStates.states.len == 5

suite "Highlight - Rust Language Specific":
  test "Rust keywords highlighted correctly":
    let buffer = @["fn main let mut const".toRunes]
    let h = initHighlight(buffer, @[], SourceLanguage.langRust)

    # Should have multiple segments for different keywords
    check h.colorSegments.len > 1

    # Find keyword segments
    var foundKeyword = false
    for seg in h.colorSegments:
      if seg.color == EditorColorPairIndex.keyword:
        foundKeyword = true
        break
    check foundKeyword

  test "Rust comments highlighted":
    let buffer = @["// This is a comment".toRunes]
    let h = initHighlight(buffer, @[], SourceLanguage.langRust)

    var foundComment = false
    for seg in h.colorSegments:
      if seg.color == EditorColorPairIndex.comment:
        foundComment = true
        break
    check foundComment

  test "Rust string literals highlighted":
    let buffer = @["let s = \"hello\";".toRunes]
    let h = initHighlight(buffer, @[], SourceLanguage.langRust)

    var foundString = false
    for seg in h.colorSegments:
      if seg.color == EditorColorPairIndex.stringLit:
        foundString = true
        break
    check foundString

  test "Rust numbers highlighted":
    let buffer = @["let x = 42;".toRunes]
    let h = initHighlight(buffer, @[], SourceLanguage.langRust)

    var foundNumber = false
    for seg in h.colorSegments:
      if seg.color in [
        EditorColorPairIndex.decNumber, EditorColorPairIndex.hexNumber,
        EditorColorPairIndex.binNumber, EditorColorPairIndex.octNumber,
      ]:
        foundNumber = true
        break
    check foundNumber

suite "Highlight - Edge Cases":
  test "getColorPair with empty highlight":
    let buffer: seq[Runes] = @[]
    let h = initHighlight(buffer)
    let color = h.getColorPair(0, 0)
    check color == EditorColorPairIndex.default

  test "getColorPair out of bounds":
    let buffer = @["test".toRunes]
    let h = initHighlight(buffer)
    let color = h.getColorPair(10, 10)
    check color == EditorColorPairIndex.default

  test "getColorPair valid position":
    let buffer = @["test".toRunes]
    let h = initHighlight(buffer)
    let color = h.getColorPair(0, 0)
    check color == EditorColorPairIndex.default

  test "initHighlightIncremental with langNone returns empty":
    let buffer = @["test".toRunes]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 0, TokenizerState(), @[], SourceLanguage.langNone
    )
    check segments.len == 0
    check lineStates.len == 0

  test "updateHighlightIncremental with empty buffer":
    let buffer: seq[Runes] = @[]
    var incrHighlight = IncrementalHighlight(
      segments: @[], lineStates: LineStateCache(states: @[], version: 0)
    )

    # Should not crash
    updateHighlightIncremental(
      buffer, incrHighlight, 0, 0, 1, @[], SourceLanguage.langRust
    )

    check incrHighlight.lineStates.states.len == 0

suite "Highlight - Multi-line Constructs":
  test "Multi-line comment state preservation":
    let buffer =
      @[
        "/* comment line 1".toRunes, "comment line 2".toRunes,
        "comment line 3 */".toRunes, "fn main() {}".toRunes,
      ]

    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 3, TokenizerState(), @[], SourceLanguage.langRust
    )

    # All lines should be parsed correctly
    check segments.len > 0
    check lineStates.len == 4

    # Lines 0-2 should be in comment
    # Line 3 should have keyword highlighting
    var foundKeywordInLine3 = false
    for seg in segments:
      if seg.firstRow == 3 and seg.color == EditorColorPairIndex.keyword:
        foundKeywordInLine3 = true
        break
    check foundKeywordInLine3

  test "String literal across token boundaries":
    let buffer = @["let s = \"hello world this is a long string\";".toRunes]
    let h = initHighlight(buffer, @[], SourceLanguage.langRust)

    # Should have string literal segment
    var foundString = false
    for seg in h.colorSegments:
      if seg.color == EditorColorPairIndex.stringLit:
        foundString = true
        break
    check foundString

suite "Highlight - Segment Operations":
  test "indexOf finds correct segment":
    let buffer = @["hello world".toRunes]
    let h = initHighlight(buffer)

    let idx = h.indexOf(0, 5)
    check idx >= 0
    check idx < h.colorSegments.len

  test "segment overlap detection":
    let seg1 = ColorSegment(
      firstRow: 0,
      firstColumn: 0,
      lastRow: 0,
      lastColumn: 10,
      color: EditorColorPairIndex.default,
      style: defaultStyle,
    )
    let seg2 = ColorSegment(
      firstRow: 0,
      firstColumn: 5,
      lastRow: 0,
      lastColumn: 15,
      color: EditorColorPairIndex.keyword,
      style: defaultStyle,
    )

    # These should overlap
    check (seg1.lastRow, seg1.lastColumn) >= (seg2.firstRow, seg2.firstColumn)

  test "highlight length and high":
    let buffer = @["line1".toRunes, "line2".toRunes]
    let h = initHighlight(buffer)

    check h.len == h.colorSegments.len
    check h.high == h.colorSegments.len - 1

suite "Highlight - detectLanguage":
  test "detectLanguage for Rust":
    check detectLanguage("test.rs") == SourceLanguage.langRust

  test "detectLanguage for Nim":
    check detectLanguage("test.nim") == SourceLanguage.langNim

  test "detectLanguage for JavaScript":
    check detectLanguage("test.js") == SourceLanguage.langJavaScript

  test "detectLanguage for TypeScript":
    check detectLanguage("test.ts") == SourceLanguage.langTypeScript

  test "detectLanguage for Python":
    check detectLanguage("test.py") == SourceLanguage.langPython

  test "detectLanguage for unknown extension":
    check detectLanguage("test.xyz") == SourceLanguage.langNone

  test "detectLanguage for no extension":
    check detectLanguage("README") == SourceLanguage.langNone
