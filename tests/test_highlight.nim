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

import std/[unittest, unicode, os, strutils, json, tables]

import pkg/celina

import ../src/moepkg/highlight
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/buffer {.all.}
import ../src/moepkg/lsp/protocol/types as lspTypes

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
    token.lang.jslike = JsLikeState(
      templateLiteralDepth: 5,
      braceDepthStack: @[1, 2, 3],
      commentDepth: 2,
      inJsxMode: true,
    )

    let state = captureTokenizerState(token)
    check state.state == gtKeyword
    check state.lang.jslike.templateLiteralDepth == 5
    check state.lang.jslike.braceDepthStack == @[1, 2, 3]
    check state.lang.jslike.commentDepth == 2
    check state.lang.jslike.inJsxMode == true

  test "restoreTokenizerState restores all fields":
    var token = GeneralTokenizer()
    token.initGeneralTokenizer("test")

    let state = TokenizerState(
      state: gtStringLit,
      lang: LangState(
        jslike: JsLikeState(
          templateLiteralDepth: 3, braceDepthStack: @[5, 6], commentDepth: 1
        ),
        html: HtmlState(inComment: true),
      ),
    )

    token.restoreTokenizerState(state)
    check token.state == gtStringLit
    check token.lang.jslike.templateLiteralDepth == 3
    check token.lang.jslike.braceDepthStack == @[5, 6]
    check token.lang.jslike.commentDepth == 1
    check token.lang.jslike.inJsxMode == false
    check token.lang.html.inComment == true

suite "Highlight - Incremental Initialization":
  test "initHighlightIncremental with empty buffer":
    let buffer: seq[string] = @[]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 0, TokenizerState(), @[], SourceLanguage.langRust
    )
    check segments.len == 0
    check lineStates.len == 0

  test "initHighlightIncremental with single line":
    let buffer = @["let x = 5;"]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 0, TokenizerState(), @[], SourceLanguage.langRust
    )
    check segments.len > 0
    check lineStates.len == 1

  test "initHighlightIncremental with multiple lines":
    let buffer = @["fn main() {", "    let x = 5;", "}"]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    check segments.len > 0
    check lineStates.len == 3

  test "initHighlightIncremental partial range":
    let buffer = @["line1", "line2", "line3", "line4", "line5"]
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
    let buffer = @["/* comment", "still comment */", "fn main() {}"]

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
    let buffer = @["fn main() {", "    let x = 5;", "}"]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates)
    )

    # Update after editing line 1 (no size change)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      1,
      @[],
      SourceLanguage.langRust,
    )

    check incrHighlight.segments.len > 0
    check incrHighlight.lineStates.states.len == 3

  test "updateHighlightIncremental with buffer size increase":
    var buffer = @["line1", "line2", "line3"]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates)
    )

    # Add a line
    buffer.add("line4")

    # Update with size change
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      3,
      @[],
      SourceLanguage.langRust,
    )

    # Line states should be resized to match buffer
    check incrHighlight.lineStates.states.len == 4

  test "updateHighlightIncremental with buffer size decrease":
    var buffer = @["line1", "line2", "line3", "line4"]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 3, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates)
    )

    # Remove a line
    buffer.delete(2)

    # Update with size change
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      2,
      @[],
      SourceLanguage.langRust,
    )

    # Line states should be resized to match buffer
    check incrHighlight.lineStates.states.len == 3

  test "updateHighlightIncremental re-parses all lines from change point":
    let buffer = @["line0", "line1", "line2", "line3", "line4"]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 4, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates)
    )

    # Edit line 2 - should re-parse from line 0 (margin of 2) to end of file
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      2,
      @[],
      SourceLanguage.langRust,
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
    let buffer = @["test"]
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 0, TokenizerState(), @[], SourceLanguage.langNone
    )
    check segments.len == 0
    check lineStates.len == 0

  test "updateHighlightIncremental with empty buffer":
    let buffer: seq[string] = @[]
    var incrHighlight =
      IncrementalHighlight(segments: @[], lineStates: LineStateCache(states: @[]))

    # Should not crash
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      0,
      @[],
      SourceLanguage.langRust,
    )

    check incrHighlight.lineStates.states.len == 0

suite "Highlight - Multi-line Constructs":
  test "Multi-line comment state preservation":
    let buffer =
      @["/* comment line 1", "comment line 2", "comment line 3 */", "fn main() {}"]

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

  test "overwrite splits an overlapping segment at the boundary":
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.overwrite(
      ColorSegment(
        firstRow: 0,
        firstColumn: 5,
        lastRow: 0,
        lastColumn: 15,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )

    check h.colorSegments.len == 2
    check h.colorSegments[0].color == EditorColorPairIndex.default
    check h.colorSegments[0].firstColumn == 0
    check h.colorSegments[0].lastColumn == 4
    check h.colorSegments[1].color == EditorColorPairIndex.keyword
    check h.colorSegments[1].firstColumn == 5
    check h.colorSegments[1].lastColumn == 10

  test "highlight length and high":
    let buffer = @["line1".toRunes, "line2".toRunes]
    let h = initHighlight(buffer)

    check h.len == h.colorSegments.len
    check h.high == h.colorSegments.len - 1

suite "Highlight - Incremental Update After Edit":
  test "delete word preserves highlighting correctness":
    # Regression test: dw (delete word) should not break subsequent highlighting.
    # The incremental highlighter must re-parse to the end of the file so that
    # tokenizer state changes propagate correctly.
    var buffer = @["let x = \"hello\";", "let y = 42;", "fn main() {}"]

    # Initialize incremental highlight
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates)
    )

    # Simulate dw: delete "x = " from line 0 → "let \"hello\";"
    buffer[0] = "let \"hello\";"

    # Update with only line 0 changed (no line count change)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      0,
      @[],
      SourceLanguage.langRust,
    )

    # All lines should have valid segments
    check incrHighlight.lineStates.states.len == 3

    # Segments must cover all 3 lines
    var coveredLines: set[uint16]
    for seg in incrHighlight.segments:
      for row in seg.firstRow .. seg.lastRow:
        coveredLines.incl(row.uint16)
    check 0'u16 in coveredLines
    check 1'u16 in coveredLines
    check 2'u16 in coveredLines

  test "incremental update matches full parse after within-line edit":
    # After an in-line edit, the incremental result should produce the same
    # color at every position as a fresh full parse.
    var buffer = @["fn main() {", "    let x = 5;", "    let y = \"hello\";", "}"]

    # Build initial incremental cache
    let (segments0, lineStates0) = initHighlightIncremental(
      buffer, 0, 3, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments0, lineStates: LineStateCache(states: lineStates0)
    )

    # Simulate editing line 1: "    let x = 5;" → "    let z = 5;"
    buffer[1] = "    let z = 5;"

    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      1,
      @[],
      SourceLanguage.langRust,
    )
    let incrResult = Highlight(colorSegments: incrHighlight.segments)

    # Do a full parse of the same buffer
    var runesBuffer: seq[Runes]
    for line in buffer:
      runesBuffer.add(line.toRunes)
    let fullResult = initHighlight(runesBuffer, @[], SourceLanguage.langRust)

    # Colors should match at every position
    for row in 0 ..< buffer.len:
      for col in 0 ..< buffer[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

  test "Astro incremental reparse keeps frontmatter fence state":
    # Editing a line below the frontmatter makes the reparse start mid-file
    # (reparseStart > 0), so it must restore the boundary state instead of
    # treating the closing `---` fence as an opening one. Regression test for
    # the template region being misparsed as JavaScript frontmatter.
    var buffer = @[
      "---", "const color = \"red\";", "---", "<style>", "  body { color: var(--c); }",
      "</style>",
    ]

    let (segments0, lineStates0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langAstro
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments0, lineStates: LineStateCache(states: lineStates0)
    )

    # Within-line edit in the template body, well below the closing fence.
    buffer[4] = "  body { color: var(--cc); }"

    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      4,
      @[],
      SourceLanguage.langAstro,
    )

    let incrResult = Highlight(colorSegments: incrHighlight.segments)
    var runesBuffer: seq[Runes]
    for line in buffer:
      runesBuffer.add(line.toRunes)
    let fullResult = initHighlight(runesBuffer, @[], SourceLanguage.langAstro)

    for row in 0 ..< buffer.len:
      for col in 0 ..< buffer[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

  test "multiline comment edit propagates state to end of file":
    # Opening a multiline comment affects all subsequent lines.
    # The incremental highlighter must re-parse to the end.
    var buffer = @["fn a() {}", "fn b() {}", "fn c() {}", "fn d() {}"]

    let (segments0, lineStates0) = initHighlightIncremental(
      buffer, 0, 3, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments0, lineStates: LineStateCache(states: lineStates0)
    )

    # Verify line 3 has keyword highlighting before the edit
    var hadKeywordBefore = false
    for seg in incrHighlight.segments:
      if seg.firstRow == 3 and seg.color == EditorColorPairIndex.keyword:
        hadKeywordBefore = true
        break
    check hadKeywordBefore

    # Change line 0 to open a block comment that is never closed
    buffer[0] = "/* fn a() {}"

    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      0,
      @[],
      SourceLanguage.langRust,
    )

    # After the edit, all remaining lines should be inside the comment.
    # Line 3 should no longer have keyword highlighting.
    let incrResult = Highlight(colorSegments: incrHighlight.segments)
    var runesBuffer: seq[Runes]
    for line in buffer:
      runesBuffer.add(line.toRunes)
    let fullResult = initHighlight(runesBuffer, @[], SourceLanguage.langRust)

    for row in 0 ..< buffer.len:
      for col in 0 ..< buffer[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

  test "state convergence stops re-parsing early":
    # When editing a line in a large buffer, the incremental highlighter should
    # converge with the cached state and avoid re-parsing the entire file.
    # After convergence, the result must still match a full parse.
    var buffer: seq[string]
    for i in 0 ..< 300:
      buffer.add("let v" & $i & " = " & $i & ";")

    let (segments0, lineStates0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments0, lineStates: LineStateCache(states: lineStates0)
    )

    # Edit line 5 (well within the buffer, far from end)
    buffer[5] = "let changed = 999;"

    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      5,
      @[],
      SourceLanguage.langRust,
    )

    check incrHighlight.lineStates.states.len == 300

    # Result must match full parse
    let incrResult = Highlight(colorSegments: incrHighlight.segments)
    var runesBuffer: seq[Runes]
    for line in buffer:
      runesBuffer.add(line.toRunes)
    let fullResult = initHighlight(runesBuffer, @[], SourceLanguage.langRust)
    for row in 0 ..< buffer.len:
      for col in 0 ..< buffer[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

# Shared by multiple suites: verify the incremental result matches a full
# parse of `buffer`, column by column.
proc checkMatchesFullParse(
    buffer: seq[string], ih: IncrementalHighlight, lang: SourceLanguage
) =
  let incrResult = Highlight(colorSegments: ih.segments)
  var runesBuffer: seq[Runes]
  for line in buffer:
    runesBuffer.add(line.toRunes)
  let fullResult = initHighlight(runesBuffer, @[], lang)
  for row in 0 ..< buffer.len:
    for col in 0 ..< buffer[row].len:
      check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

suite "Highlight - budgeted incremental update":
  # A line-count change re-parses from the change point to EOF, which on a
  # large file must not block one frame: `budgetLines` splits the re-parse
  # across calls. Each call returns true while work remains, progress is
  # carried in `pendingReparse`, and the pre-change segments are trimmed
  # when the re-parse starts.

  proc parseFullIncremental(
      buf: seq[string], lang: SourceLanguage
  ): IncrementalHighlight =
    let (segments, lineStates) =
      initHighlightIncremental(buf, 0, buf.high, TokenizerState(), @[], lang)
    IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates)
    )

  proc rustLines(n: int): seq[string] =
    result = newSeq[string](n)
    for i in 0 ..< n:
      result[i] = "let value" & $i & " = " & $i & "; // note " & $i

  test "budget stops the re-parse early and returns true":
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    let ongoing = updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100
    )

    # Budget 100 < the ~240 lines below the change point: one chunk parsed,
    # still going.
    check ongoing
    check ih.pendingReparse != nil
    check ih.pendingReparse.currentStart > 10
    # No segment may point at a row the re-parse has not produced yet: the
    # pre-change segments below the trim point were dropped at the start.
    for seg in ih.segments:
      check seg.firstRow <= ih.pendingReparse.reparseEnd

  test "resume calls finish the re-parse and match a full parse":
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    var calls = 0
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100
    )
    :
      inc calls
    inc calls

    check calls >= 2
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)
    check ih.lineStates.states.len == buffer.len

  test "mid-re-parse segments stay sorted across calls":
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    var ongoing = true
    while ongoing:
      ongoing = updateHighlightIncremental(
        buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100
      )
      for i in 1 ..< ih.segments.len:
        check ih.segments[i].firstRow >= ih.segments[i - 1].firstRow
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)

  test "an edit during the re-parse restarts from the new anchor":
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    # Consume one budget slice
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100
    )
    check ih.pendingReparse != nil

    # A new edit (line-count change) arrives while the re-parse is in flight.
    buffer.insert("let another = 2;", 2)
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 2, @[], SourceLanguage.langRust, 0, 100
    )

    # Restarted from the new anchor (2-line backward margin), not resumed
    # from the old frontier; far more than one budget remains below it, so
    # the re-parse stays in flight.
    check ih.pendingReparse != nil
    check ih.pendingReparse.reparseStart == 0

    while updateHighlightIncremental(
      buffer.len, getLine, ih, 2, @[], SourceLanguage.langRust, 0, 100
    )
    :
      discard
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)

  test "an edit on the same line during the re-parse restarts":
    # A second edit on the same line cannot change the anchor, so the
    # restart must be driven by the content-version bump.
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, 1
    )
    check ih.pendingReparse != nil
    let oldFrontier = ih.pendingReparse.reparseEnd

    # Same line, new content (version 1 -> 2).
    buffer[10] = "let inserted = 1; // changed again"
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, 2
    )
    check ih.pendingReparse != nil
    # Restarted from scratch (rewound near the edit), not resumed from the
    # old frontier; exact values pin the restart.
    check ih.pendingReparse.reparseStart == 8
    check ih.pendingReparse.currentStart == oldFrontier + 1

    while updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, 2
    )
    :
      discard
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)

  test "content-version mismatch always restarts even when the new version is -1":
    # Regression: the restart predicate used to gate `pr.contentVersion !=
    # contentVersion` behind `contentVersion >= 0`, so a caller that
    # dropped from a real version to the default -1 skipped the version
    # check silently. Removing the gate makes any mismatch (including
    # `real -> -1`) restart.
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, 5
    )
    check ih.pendingReparse != nil
    let firstCurrentStart = ih.pendingReparse.currentStart

    # Same anchor, same line count, but the caller now passes the -1
    # default. The old gate short-circuited to false and left the flight
    # resuming over the stale content; the fix restarts.
    buffer[10] = "let inserted = 1; // changed"
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, -1
    )
    check ih.pendingReparse != nil
    # A restart re-processes the same first chunk, so `currentStart`
    # matches the first-call value; a resume would advance past it.
    check ih.pendingReparse.currentStart <= firstCurrentStart

  test "same-line-count edit with a tiny budget re-attaches the valid tail":
    # Convergence stops the re-parse at the first chunk boundary whose end
    # state matches the cache; the untouched tail rows keep their old
    # segments via the stashed tail.
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer[5] = "let changed = 1; // edited"

    let getLine = proc(i: int): string =
      buffer[i]
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 5, @[], SourceLanguage.langRust, 0, 100
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)
    check ih.lineStates.states.len == buffer.len

  test "empty buffer with a budget completes immediately":
    var ih = parseFullIncremental(@[], SourceLanguage.langRust)
    let getLine = proc(i: int): string =
      ""
    check not updateHighlightIncremental(
      0, getLine, ih, 0, @[], SourceLanguage.langRust, 0, 100
    )
    check ih.pendingReparse == nil

  test "budgeted YAML re-parse resumes across a block scalar":
    # The scalar is resumable across chunk boundaries (its context is
    # persisted on the boundary capture), so the budget spreads the re-parse
    # across calls instead of doubling the window until it spans the scalar.
    var buffer = @["long: |"]
    for i in 0 ..< 150:
      buffer.add("  scalar content " & $i)
    buffer.add("after: tail")
    var ih = parseFullIncremental(buffer, SourceLanguage.langYaml)
    buffer[1] = "  edited scalar content"

    let getLine = proc(i: int): string =
      buffer[i]
    var calls = 0
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 1, @[], SourceLanguage.langYaml, 0, 100
    )
    :
      inc calls
      check calls < 50 # must terminate
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langYaml)

  test "budgeted YAML re-parse inside a large block scalar stays within the budget":
    # Regression: a window fully inside a block scalar used to double
    # geometrically until it spanned the scalar's remainder — the per-frame
    # freeze the budget exists to prevent. The scalar is now resumable, so
    # each call accepts a budget-sized chunk; the varying content indentation
    # keeps convergence off, so the flight genuinely spans calls.
    var buffer = @["long: |"]
    for i in 0 ..< 250:
      buffer.add("    deeper content " & $i)
    for i in 0 ..< 250:
      buffer.add("  shallow content " & $i)
    buffer.add("after: tail")
    var ih = parseFullIncremental(buffer, SourceLanguage.langYaml)
    buffer[1] = "    edited deeper content"

    let getLine = proc(i: int): string =
      buffer[i]
    var maxParsed = 0
    while true:
      var parsed = 0
      if not updateHighlightIncremental(
        buffer.len, getLine, ih, 1, @[], SourceLanguage.langYaml, 0, 100, 1, parsed
      ):
        break
      maxParsed = max(maxParsed, parsed)
    check maxParsed <= 100
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langYaml)

  test "budgeted YAML re-parse across a long blank run stays within the budget":
    # Regression: a blank-line run is a YAML handoff hazard, so a window
    # inside it used to double geometrically and the doubled window
    # PERSISTED across frames (the per-frame freeze the budget exists to
    # prevent). Blank lines are resumable, so each call must accept a
    # budget-sized chunk; without the fix `maxParsed` grows 100, 200, 400...
    const BlankRun = 20000
    var buffer = @["a: 1", "b: 2"]
    for i in 0 ..< BlankRun:
      buffer.add("")
    buffer.add("after: tail")
    var ih = parseFullIncremental(buffer, SourceLanguage.langYaml)
    buffer.insert("b2: 22", 1)

    let getLine = proc(i: int): string =
      buffer[i]
    var maxParsed = 0
    while true:
      var parsed = 0
      if not updateHighlightIncremental(
        buffer.len, getLine, ih, 1, @[], SourceLanguage.langYaml, 0, 100, 1, parsed
      ):
        break
      maxParsed = max(maxParsed, parsed)
    check maxParsed <= 100
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langYaml)

  test "an emptied state cache mid-flight restarts from the cache top":
    # Regression (review finding): a line-count change at the top trims the
    # state cache; if the first chunk then sits inside a YAML handoff
    # hazard, the budget break leaves the flight live with an empty cache.
    # A second edit must restart from the top of the available cache (the
    # seed for the new anchor is gone), not from the new anchor's margin.
    var buffer = @["long: |"]
    for i in 1 .. 99:
      buffer.add("")
    for i in 100 ..< 1500:
      buffer.add("key" & $i & ": value")
    buffer.add("after: tail")
    var ih = parseFullIncremental(buffer, SourceLanguage.langYaml)
    buffer.insert("", 1)

    let getLine = proc(i: int): string =
      buffer[i]
    # First call: the window inside the blank run doubles until the budget
    # (50) is exhausted before any chunk is accepted; the cache stays empty.
    check updateHighlightIncremental(
      buffer.len, getLine, ih, 1, @[], SourceLanguage.langYaml, 0, 50, 1
    )
    check ih.pendingReparse != nil
    check ih.lineStates.states.len == 0

    # A second edit below the cache while the flight is live: the restart
    # must rewind to the top of the available cache.
    buffer.insert("let second = 1;", 500)
    check updateHighlightIncremental(
      buffer.len, getLine, ih, 500, @[], SourceLanguage.langYaml, 0, 1000, 2
    )
    check ih.pendingReparse != nil
    check ih.pendingReparse.reparseStart == 0

    while updateHighlightIncremental(
      buffer.len, getLine, ih, 500, @[], SourceLanguage.langYaml, 0, 1000, 2
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langYaml)

  test "an emptied-cache flight does not fall back to a full rebuild":
    # Regression (review finding): `updateHighlight`'s cache-validity gate
    # used to treat a live flight with an emptied state cache as "no cache"
    # and rebuild the whole file in one unbudgeted call.
    var content = "long: |\n"
    for i in 0 ..< 1500:
      content.add("\n")
    content.add("after: tail\n")
    let buf = newTextBuffer(content)
    buf.language = SourceLanguage.langYaml
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1

    discard buf.beginTransaction()
    discard buf.insert(1, "")
    discard buf.commitTransaction()
    check buf.updateHighlight(1000)
    check buf.incrementalHighlight.pendingReparse != nil
    check buf.incrementalHighlight.lineStates.states.len == 0

    # A second edit must restart the budgeted flight, not rebuild the whole
    # file in one call (which would leave no flight to resume).
    discard buf.beginTransaction()
    discard buf.insert(500, "let second = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(1000)
    check buf.incrementalHighlight.pendingReparse != nil
    check buf.incrementalHighlight.pendingReparse.reparseStart == 0
    while buf.continueIncrementalHighlight(1000):
      discard
    check buf.incrementalHighlight.pendingReparse == nil
    var lines = newSeq[string](buf.len)
    for i in 0 ..< buf.len:
      lines[i] = buf.getLine(i)
    checkMatchesFullParse(lines, buf.incrementalHighlight, SourceLanguage.langYaml)

  test "geometric growth in a handoff hazard does not over-charge parsedLines":
    # Regression: a rejected handoff-hazard attempt used to bump
    # `parsedLines` by the full window, draining the caller's shared budget
    # on every doubling. Refund the rejection.
    var buffer = @["long: |"]
    for i in 1 .. 99:
      buffer.add("")
    for i in 100 ..< 1500:
      buffer.add("key" & $i & ": value")
    buffer.add("after: tail")
    var ih = parseFullIncremental(buffer, SourceLanguage.langYaml)
    buffer.insert("", 1)

    let getLine = proc(i: int): string =
      buffer[i]
    var parsedLines: int
    check updateHighlightIncremental(
      buffer.len, getLine, ih, 1, @[], SourceLanguage.langYaml, 0, 50, 1, parsedLines
    )
    check ih.pendingReparse != nil
    # The doubling attempts were rejected, so nothing was accepted; the
    # shared-budget charge must reflect that (was previously ≥ 50 — the
    # doubled window's full length).
    check parsedLines == 0

  test "an empty chunk cut right after a YAML block-scalar header keeps the end checks":
    # Regression: a chunk ending at the blank line right after a block-scalar
    # header (header at row ChunkSize - 2, blank at the chunk's last row)
    # used to persist `blockScalarMinIndent = 0`. The resume then compared
    # every later line against 0, so a `#` comment less indented than the
    # scalar's content was swallowed as content.
    var buffer = newSeq[string](ChunkSize - 2)
    for i in 0 ..< ChunkSize - 2:
      buffer[i] = "key" & $i & ": value"
    buffer.add("long: |")
    buffer.add("")
    buffer.add("  scalar content")
    buffer.add("  more content")
    buffer.add(" # comment below the content indent")
    buffer.add("after: tail")
    var ih = parseFullIncremental(buffer, SourceLanguage.langYaml)
    buffer[1] = "b2: 22"

    let getLine = proc(i: int): string =
      buffer[i]
    var calls = 0
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 1, @[], SourceLanguage.langYaml, 0, 100
    )
    :
      inc calls
      check calls < 50 # must terminate
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langYaml)

  test "a resumed YAML block scalar ends at a comment below the persisted minimum":
    # Regression: a chunk boundary landing right before a `#` comment less
    # indented than the scalar's content must end the scalar like a
    # single-buffer scan. The resume must not fold the comment's indent into
    # the minimum before the end check — that would swallow the comment as
    # content.
    var buffer = @["long: |"]
    for i in 0 ..< ChunkSize - 1:
      buffer.add("  scalar content " & $i)
    buffer.add(" # comment below the content indent")
    buffer.add("after: tail")
    var ih = parseFullIncremental(buffer, SourceLanguage.langYaml)
    buffer[1] = "  edited scalar content"

    let getLine = proc(i: int): string =
      buffer[i]
    var calls = 0
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 1, @[], SourceLanguage.langYaml, 0, 100
    )
    :
      inc calls
      check calls < 50 # must terminate
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langYaml)

  test "an indicator header cut right after it keeps a shallow first-line comment as content":
    # Regression: a chunk boundary right after an indicator header (`key: |4`)
    # used to persist the indicator alone as the minimum, so a resume ended
    # the scalar at a `#` comment shallower than the indicator — while a
    # single-buffer scan folds the first content line into the indicator and
    # keeps the comment as content.
    var buffer = newSeq[string](ChunkSize)
    for i in 0 ..< ChunkSize - 1:
      buffer[i] = "key" & $i & ": value"
    buffer[ChunkSize - 1] = "long: |4"
    buffer.add("  # comment below the indicator")
    buffer.add("  scalar content")
    buffer.add("after: tail")
    var ih = parseFullIncremental(buffer, SourceLanguage.langYaml)
    buffer[1] = "b2: 22"

    let getLine = proc(i: int): string =
      buffer[i]
    var calls = 0
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 1, @[], SourceLanguage.langYaml, 0, 100, 1
    )
    :
      inc calls
      check calls < 50 # must terminate
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langYaml)

  test "updateHighlight and continueIncrementalHighlight drive the re-parse":
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_budgeted_update.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 2500:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()

    check buf.updateHighlight(100)
    var frames = 1
    while buf.continueIncrementalHighlight(100):
      inc frames
    check frames > 1
    check buf.incrementalHighlight.pendingReparse == nil
    check buf.incrementalHighlight.lineStates.states.len == buf.len
    var lines = newSeq[string](buf.len)
    for i in 0 ..< buf.len:
      lines[i] = buf.getLine(i)
    checkMatchesFullParse(lines, buf.incrementalHighlight, SourceLanguage.langRust)

  test "URI underlines re-cover a budgeted re-parse region":
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_budgeted_uri.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 1500:
      if i == 100:
        content.add("let x = 1; // see https://example.com/api\n")
      else:
        content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    let uriCol = "let x = 1; // see ".len
    check Underline in buf.highlight.getSegmentModifiers(100, uriCol)

    # Insert at the top: the re-parse trims the segments (URI underlines
    # included); the progressive scan must re-cover them.
    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()

    check buf.updateHighlight(100)
    while buf.continueIncrementalHighlight(100):
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    check Underline in buf.highlight.getSegmentModifiers(101, uriCol)

  test "URI rewind covers rows above the change when a block comment opener trims them":
    # Regression: the previous `-3` heuristic missed the MultiLineKinds
    # rewind — a `/*` opener above the edit trimmed segments from the
    # opener onward, but the URI scan resumed at `lastChangedLines - 3`,
    # skipping the URI inside the comment.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_uri_multiline_rewind.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 5:
      content.add("let value" & $i & " = " & $i & ";\n")
    content.add("/* opener\n")
    for i in 6 ..< 50:
      content.add(" * padding " & $i & "\n")
    content.add(" * see https://example.com/api\n")
    for i in 51 ..< 150:
      content.add(" * padding " & $i & "\n")
    content.add(" */\n")
    for i in 151 ..< 200:
      content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    let uriCol = " * see ".len
    check Underline in buf.highlight.getSegmentModifiers(50, uriCol)

    # Edit line 100 (inside the comment): reparseStart rewinds to the `/*`
    # opener, trimming the URI's segment. Re-parse completes in one call
    # (fits in the default budget); the completed-branch URI rewind must
    # reach past the URI so `continueUriScan` re-underlines it.
    discard buf.replaceLine(100, " * padding 100 edited")
    check buf.updateHighlight(1000) == false
    check buf.incrementalHighlight.pendingReparse == nil
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    check Underline in buf.highlight.getSegmentModifiers(50, uriCol)

  test "URI scan clamps to the re-parse frontier while in flight":
    # The scan must not run past the re-parse frontier: the trimmed rows
    # beyond it have no segments yet, and scanning past them would
    # permanently skip their underlines.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_budgeted_uri_clamp.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 1500:
      if i == 100:
        content.add("let x = 1; // see https://example.com/api\n")
      else:
        content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()

    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    discard buf.continueUriScan()
    # Clamped to the frontier: without it the scan would reach row 999 while
    # the re-parse has produced only rows up to 99.
    check buf.uriScanParsedUpTo <= buf.incrementalHighlight.pendingReparse.reparseEnd
    while buf.continueIncrementalHighlight(100):
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    let uriCol = "let x = 1; // see ".len
    check Underline in buf.highlight.getSegmentModifiers(101, uriCol)

  test "URI scan covers flight rows beyond a stalled initial-load frontier":
    # Regression: while a re-parse is in flight, the scan's early exit used
    # the STALE initial-load frontier (`parsedUpTo`), so rows the flight
    # re-parsed past it got no underlines until completion. The flight's
    # frontier (`reparseEnd`) must govern: rows up to it have fresh segments
    # and must be scanned immediately.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_uri_stalled_load.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 3000:
      if i == 2000:
        content.add("let x = 1; // see https://example.com/api\n")
      else:
        content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    # Advance the initial load by one chunk only: the frontier stalls below
    # the URI row (2000) while the URI sits beyond it.
    discard buf.continueInitialHighlight()
    let loadFrontier = buf.incrementalHighlight.parsedUpTo
    check loadFrontier < 2000
    check loadFrontier < buf.len - 1
    discard buf.continueUriScan()
    check buf.uriScanParsedUpTo == loadFrontier

    # Line-count change above the URI: the flight re-parses past the stale
    # load frontier and reparseStart <= parsedUpTo + 1, so the flight covers
    # the whole unparsed tail.
    discard buf.beginTransaction()
    discard buf.insert(500, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil

    # Drive the flight past the URI row, then let the scan catch up: it must
    # pass the stale load frontier up to the flight's frontier and underline
    # the URI while the flight is still in flight. `continueUriScan` returns
    # whether URIs were applied, not whether work remains, so drive by the
    # pointer.
    while buf.incrementalHighlight.pendingReparse.reparseEnd < 2100:
      discard buf.continueIncrementalHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    while buf.uriScanParsedUpTo < buf.incrementalHighlight.pendingReparse.reparseEnd:
      discard buf.continueUriScan()
    let uriCol = "let x = 1; // see ".len
    check Underline in buf.highlight.getSegmentModifiers(2001, uriCol)
    check buf.uriScanParsedUpTo > loadFrontier

  test "a line-count change mid-re-parse keeps the EOF re-parse after undo":
    # Regression: a restart discarded the flight's original tail, leaving
    # rows beyond its start without segments. The undo changes the line
    # count (251 -> 250): the tail is dropped and convergence stays off, so
    # the restarted re-parse runs to EOF.
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, 1
    )
    check ih.pendingReparse != nil

    # Undo the insert: the line-count change mid-flight must keep the
    # restarted re-parse from converging (it would splice a misaligned
    # tail); the assertions pin the EOF re-parse path.
    buffer.delete(10)
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, 2
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)

  test "a mid-re-parse line-count change re-parses to EOF instead of converging":
    # Rows below a line-count change shift, so convergence must stay off for
    # the restarted flight; `canConverge` alone cannot carry the suppression
    # (the count can match the cached length again), so `tailAligned` does.
    var buffer = newSeq[string](300)
    for i in 0 ..< 300:
      case i mod 3
      of 0:
        buffer[i] = "let value" & $i & " = " & $i & "; // note " & $i
      of 1:
        buffer[i] = "const S" & $i & ": &str = \"string " & $i & "\";"
      else:
        buffer[i] = "fn f" & $i & "() { let x = " & $i & "; }"
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, 1
    )
    check ih.pendingReparse != nil

    # A line-count change lands while the re-parse is in flight.
    buffer.delete(200)
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 200, @[], SourceLanguage.langRust, 0, 100, 2
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)

  test "an edit below the old frontier re-covers the gap on restart":
    # Regression: a restart from a lower anchor left the rows between the
    # old frontier and the new anchor without segments.
    var buffer = rustLines(300)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 10)

    let getLine = proc(i: int): string =
      buffer[i]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 10, @[], SourceLanguage.langRust, 0, 100, 1
    )
    check ih.pendingReparse != nil

    # A new edit below the flight's frontier: restarting from the new anchor
    # alone would skip rows [oldFrontier, newAnchor], which exist in no cache.
    buffer.insert("let another = 2;", 200)
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 200, @[], SourceLanguage.langRust, 0, 100, 2
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)

  test "an edit below the frontier with an incomplete initial load re-covers the band":
    # Regression: a discarded flight started during an incomplete initial
    # load trims nothing (its stashed tail is empty), so the restart override
    # must be position-based (`reparseStart > oldFrontier`), not tail-based.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_band_restart.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 2500:
      content.add("let value" & $i & " = " & $i & "; // note " & $i & "\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    # loadFile parses the first 1000 rows; one more chunk leaves the load
    # incomplete (caches cover rows [0, 1999], `states.len` < line count).
    check buf.incrementalHighlight.parsedUpTo == 999
    check buf.continueInitialHighlight()
    check buf.incrementalHighlight.parsedUpTo == 1999

    # An edit below the load frontier: the flight trims nothing, so its
    # stashed tail is empty.
    discard buf.beginTransaction()
    discard buf.insert(2200, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    let oldFrontier = buf.incrementalHighlight.pendingReparse.reparseEnd

    # A second edit below the flight's frontier restarts it; the override
    # must rewind the re-parse to the discarded flight's start, not the new
    # anchor's margin, or the band [oldFrontier, newAnchor) stays uncovered.
    discard buf.beginTransaction()
    discard buf.insert(2400, "let second = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    let pr = buf.incrementalHighlight.pendingReparse
    check pr != nil
    check pr.reparseStart < oldFrontier

    # Drain the restarted flight; every row above the old frontier must carry
    # fresh segments from the flight itself.
    while buf.continueIncrementalHighlight(100):
      discard
    check buf.incrementalHighlight.pendingReparse == nil

    # The completed flight must NOT advance the progressive-load frontier:
    # the band [2000, 2198) was covered by neither (the flight's initial
    # state was the neutral fallback). Regression: the completion used to
    # advance `parsedUpTo` unconditionally, leaving the band without
    # segments forever.
    check buf.incrementalHighlight.parsedUpTo == 1999
    while buf.continueInitialHighlight():
      discard
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1

    let incrResult = Highlight(colorSegments: buf.incrementalHighlight.segments)
    var runesBuffer: seq[Runes]
    var lines = newSeq[string](buf.len)
    for i in 0 ..< buf.len:
      lines[i] = buf.getLine(i)
      runesBuffer.add(lines[i].toRunes)
    let fullResult = initHighlight(runesBuffer, @[], SourceLanguage.langRust)
    for row in 0 ..< buf.len:
      for col in 0 ..< lines[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

  test "a band-flight with a construct open at its start heals on load resume":
    # Regression: when an edit lands below the load frontier, the flight
    # starts from the neutral state (the true entering state sits in the
    # unloaded band), so rows from `reparseStart` on can be mis-lexed — here
    # a `/*` comment opened inside the band colors the rows below as code.
    # The load must resume from its stale frontier and re-parse the band.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_band_construct.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 2500:
      if i == 2100:
        content.add("/*\n")
      elif i == 2300:
        content.add("*/\n")
      elif i >= 2100:
        content.add("  comment body " & $i & "\n")
      else:
        content.add("let value" & $i & " = " & $i & "; // note " & $i & "\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    check buf.continueInitialHighlight()
    check buf.incrementalHighlight.parsedUpTo == 1999

    # An edit inside the band, below the load frontier: the flight starts at
    # 2198 — inside the still-open comment — from the neutral state.
    discard buf.beginTransaction()
    discard buf.insert(2200, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    while buf.continueIncrementalHighlight(100):
      discard
    check buf.incrementalHighlight.pendingReparse == nil
    # The load must still resume from its stale frontier and re-parse the
    # band [2000, 2198) and the mis-lexed rows below it with the true state.
    check buf.incrementalHighlight.parsedUpTo == 1999
    while buf.continueInitialHighlight():
      discard

    let incrResult = Highlight(colorSegments: buf.incrementalHighlight.segments)
    var runesBuffer: seq[Runes]
    var lines = newSeq[string](buf.len)
    for i in 0 ..< buf.len:
      lines[i] = buf.getLine(i)
      runesBuffer.add(lines[i].toRunes)
    let fullResult = initHighlight(runesBuffer, @[], SourceLanguage.langRust)
    for row in 0 ..< buf.len:
      for col in 0 ..< lines[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

  test "a restarted re-parse does not converge inside the old flight's window":
    # Regression: after a restart, cached states inside the old flight's
    # window are its fresh states while the tail holds the ORIGINAL
    # segments; converging there would splice a stale tail (here: a comment
    # closed early below the old frontier keeps comment colors on code).
    var buffer = newSeq[string](300)
    for i in 0 ..< 300:
      if i == 100:
        buffer[i] = "/*"
      elif i == 299:
        buffer[i] = "*/"
      elif i > 100:
        buffer[i] = "  comment body " & $i
      else:
        buffer[i] = "let value" & $i & " = " & $i & "; // note " & $i
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)

    let getLine = proc(i: int): string =
      buffer[i]
    # Close the comment early: the state sequence below the edit diverges
    # from the original cache, so the re-parse keeps flying.
    buffer[120] = "*/"
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 120, @[], SourceLanguage.langRust, 0, 100, 1
    )
    check ih.pendingReparse != nil
    check ih.pendingReparse.reparseStart == 100

    # A second edit above restarts the flight. Its first chunk re-parses the
    # still-open comment, so its end state matches the discarded flight's
    # cache inside the old window; that convergence must be rejected (the
    # tail is the ORIGINAL comment, stale now that the comment closes early).
    buffer[5] = "let edited = 1; // changed"
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 5, @[], SourceLanguage.langRust, 0, 100, 2
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)

  test "a re-restarted re-parse does not converge inside the inherited barrier":
    # Regression (review finding): `convergeBarrier` is a max over restart
    # chains, but prior tests used single restarts where
    # `max(oldFrontier, -1) == oldFrontier` cannot tell the max apart from a
    # "last frontier only" implementation. This chain forces the max to pick
    # the INHERITED barrier: the third restart's first chunk ends inside the
    # first flight's window with matching states — accepting convergence
    # would splice the ORIGINAL tail (rows below the comment's early close
    # stay comment-colored).
    var buffer = newSeq[string](600)
    for i in 0 ..< 600:
      if i == 100:
        buffer[i] = "/*"
      elif i == 350:
        buffer[i] = "*/"
      elif i > 100:
        buffer[i] = "  comment body " & $i
      else:
        buffer[i] = "let value" & $i & " = " & $i & "; // note " & $i
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)

    let getLine = proc(i: int): string =
      buffer[i]
    # Close the comment early: rows below diverge from the original cache, so
    # the flight cannot converge; one 100-line chunk leaves it in flight with
    # frontier 199.
    buffer[120] = "*/"
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 120, @[], SourceLanguage.langRust, 0, 100, 1
    )
    check ih.pendingReparse != nil
    check ih.pendingReparse.reparseStart == 100
    check ih.pendingReparse.reparseEnd == ih.pendingReparse.reparseStart + ChunkSize - 1

    # A second edit (line-count-preserving, so the cache stays full and
    # convergence stays live) restarts from above. Its first chunk re-parses
    # the still-open comment and its end state matches the discarded flight's
    # cache inside the old window; the inherited barrier (199) rejects it,
    # and the flight persists at frontier 102 — BELOW the barrier.
    buffer[5] = "let edited = 1; // changed"
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 5, @[], SourceLanguage.langRust, 0, 100, 2
    )
    check ih.pendingReparse != nil
    check ih.pendingReparse.reparseStart == 3
    check ih.pendingReparse.reparseEnd == ih.pendingReparse.reparseStart + ChunkSize - 1

    # A third edit inside the comment rewinds the re-parse to the `/*`
    # opener (100): its first chunk re-parses rows 100..199 and the entering
    # state at 200 matches the first flight's fresh cache. Only the INHERITED
    # barrier (199) rejects that convergence — a "last frontier only"
    # implementation would accept it and splice the original tail, coloring
    # rows 200+ (now code) as comment.
    buffer[105] = "  edited comment body"
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 105, @[], SourceLanguage.langRust, 0, 100, 3
    )
    :
      discard
    check ih.pendingReparse == nil
    # Inline comparison instead of `checkMatchesFullParse`: a `check` inside
    # a helper proc does not fail the test in std/unittest, so the checks
    # must live in the test body.
    let incrResult = Highlight(colorSegments: ih.segments)
    var runesBuffer: seq[Runes]
    for line in buffer:
      runesBuffer.add(line.toRunes)
    let fullResult = initHighlight(runesBuffer, @[], SourceLanguage.langRust)
    for row in 0 ..< buffer.len:
      for col in 0 ..< buffer[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

  test "a content-version bump without needsUpdate mid-re-parse rewinds the URI scan":
    # Regression: a restart driven from continueIncrementalHighlight (the
    # undo/redo roll-forward paths bump contentVersion without
    # markLineChanged) re-creates segments without URI underlines, but the
    # continuation path had no URI-scan rewind — the rows between the new
    # reparseStart and the old scan position were never re-scanned.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_budgeted_uri_restart.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 1500:
      if i == 100:
        content.add("let x = 1; // see https://example.com/api\n")
      else:
        content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    let uriCol = "let x = 1; // see ".len
    check Underline in buf.highlight.getSegmentModifiers(100, uriCol)

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    # Let the flight and the URI scan advance past the re-parse start.
    for _ in 0 ..< 4:
      discard buf.continueIncrementalHighlight(100)
      discard buf.continueUriScan()
    check buf.uriScanParsedUpTo > buf.incrementalHighlight.pendingReparse.reparseStart

    # Simulate an undo/redo backend failure: contentVersion advances without
    # highlightNeedsUpdate, so the next continuation call restarts the
    # re-parse and must rewind the URI scan to the new reparseStart.
    buf.advanceContentVersion()
    discard buf.continueIncrementalHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    check buf.uriScanParsedUpTo ==
      buf.incrementalHighlight.pendingReparse.reparseStart - 1

    while buf.continueIncrementalHighlight(100):
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    # The underline is re-covered (insert moved the URI row from 100 to 101).
    check Underline in buf.highlight.getSegmentModifiers(101, uriCol)

  test "a restart completing in one continuation call rewinds the URI scan":
    # Regression: the continuation path's completed-restart rewind (the
    # `newPr == nil` branch of continueIncrementalHighlight) had no test.
    # Without the rewind the rows between the new reparseStart and the old
    # scan position keep underline-less segments that are never re-scanned.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_budgeted_uri_rewind_cont.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 900:
      if i == 1:
        content.add("let x = 1; // see https://example.com/api\n")
      else:
        content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()

    # A flight at the top stays in flight with a small budget.
    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(50)
    check buf.incrementalHighlight.pendingReparse != nil
    # Advance the flight and the URI scan past the re-parse start.
    for _ in 0 ..< 4:
      discard buf.continueIncrementalHighlight(50)
      discard buf.continueUriScan()
    check buf.uriScanParsedUpTo > buf.incrementalHighlight.pendingReparse.reparseStart

    # A second edit below the flight's frontier restarts it from the
    # discarded flight's start (rows between the old frontier and the new
    # anchor have no segments); the remaining distance is small enough that
    # a large budget completes the restart within this one continuation
    # call, exercising the `newPr == nil` rewind branch.
    discard buf.beginTransaction()
    discard buf.insert(600, "let second = 1;")
    discard buf.commitTransaction()
    check not buf.continueIncrementalHighlight(1000)
    check buf.incrementalHighlight.pendingReparse == nil
    # Rewound past the new re-parse start (the restart re-parsed from row 0).
    check buf.uriScanParsedUpTo == -1

    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    # The underline is re-covered (the URI row moved from 1 to 2 with the
    # first insert).
    let uriCol = "let x = 1; // see ".len
    check Underline in buf.highlight.getSegmentModifiers(2, uriCol)

  test "a restart that completes in one call rewinds the URI scan past the inherited start":
    # Regression: a restart whose reparseStart is overridden to the discarded
    # flight's start re-parses rows above lastChangedLines - 3; the
    # completed-re-parse rewind must cover them or those rows' new segments
    # keep no URI underlines.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_budgeted_uri_rewind.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 250:
      if i == 1:
        content.add("let x = 1; // see https://example.com/api\n")
      else:
        content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    let uriCol = "let x = 1; // see ".len
    check Underline in buf.highlight.getSegmentModifiers(1, uriCol)

    # Edit at the top: the re-parse (from row 0) stays in flight and the
    # clamped URI scan re-covers the re-parsed rows as the frontier grows.
    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()
    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    discard buf.continueIncrementalHighlight(100)
    discard buf.continueUriScan()
    check buf.uriScanParsedUpTo > 2
    # A second edit lands mid-flight with a reparseStart (3) below the new
    # anchor but above the discarded flight's start (0): the restart rewinds
    # the re-parse to row 0 and completes within this call. The completion
    # rewind must go back to the inherited start, not just lastChangedLines -
    # 3 (row 2), or the URI row's fresh segment keeps no underline.
    discard buf.beginTransaction()
    discard buf.insert(5, "let second = 1;")
    discard buf.commitTransaction()
    check not buf.updateHighlight(1000)
    check buf.incrementalHighlight.pendingReparse == nil
    # The edits grew the buffer past the initial load's stale frontier
    # (parsedUpTo), and continueUriScan refuses to pass it, so resume the
    # load before the scan can re-cover the re-parsed rows.
    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    # The URI row moved from 1 to 2 (inserts at rows 0 and 5).
    check Underline in buf.highlight.getSegmentModifiers(2, uriCol)

  test "a reserved-word change mid-re-parse restarts with the new words":
    # setReservedWords touches neither the anchor, the line count nor the
    # content version, so only the reserved-words check can detect it;
    # without the restart the already-accepted chunks keep the old colors.
    var buffer: seq[string]
    for i in 0 ..< 250:
      buffer.add("let value" & $i & " = " & $i & "; // NOTE " & $i)
    var ih = parseFullIncremental(buffer, SourceLanguage.langRust)
    buffer.insert("let inserted = 1;", 0)

    let getLine = proc(i: int): string =
      buffer[i]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 0, @[], SourceLanguage.langRust, 0, 100, 1
    )
    check ih.pendingReparse != nil

    # Same anchor / line count / content version; only the words change.
    let newWords =
      @[ReservedWord(word: "NOTE", color: EditorColorPairIndex.reservedWord)]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 0, newWords, SourceLanguage.langRust, 0, 100, 1
    )
    check ih.pendingReparse != nil

    while updateHighlightIncremental(
      buffer.len, getLine, ih, 0, newWords, SourceLanguage.langRust, 0, 100, 1
    )
    :
      discard
    check ih.pendingReparse == nil
    # Every row must match a full parse with the new words: the restart
    # re-parsed the chunks the old words had already colored.
    let incrResult = Highlight(colorSegments: ih.segments)
    var runesBuffer: seq[Runes]
    for line in buffer:
      runesBuffer.add(line.toRunes)
    let fullResult = initHighlight(runesBuffer, newWords, SourceLanguage.langRust)
    for row in 0 ..< buffer.len:
      for col in 0 ..< buffer[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

  test "an edit during the progressive initial load suppresses and resumes cleanly":
    # The initial load (parsedUpTo < lineCount) and a budgeted re-parse must
    # not fight: while the re-parse is in flight continueInitialHighlight is
    # suppressed, and after it completes the initial load resumes from its
    # stale frontier without duplicating the rows the re-parse covered.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_budgeted_initial.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 2500:
      if i == 2000:
        content.add("let x = 1; // see https://example.com/api\n")
      else:
        content.add("let value" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    # Only one chunk of the initial load, then an edit below its frontier.
    check buf.continueInitialHighlight()
    check buf.incrementalHighlight.parsedUpTo < buf.len - 1

    discard buf.beginTransaction()
    discard buf.insert(0, "let inserted = 1;")
    discard buf.commitTransaction()

    check buf.updateHighlight(100)
    check buf.incrementalHighlight.pendingReparse != nil
    # Suppressed while the re-parse is in flight.
    check not buf.continueInitialHighlight()
    while buf.continueIncrementalHighlight(100):
      discard
    check buf.incrementalHighlight.pendingReparse == nil
    # The initial load resumes from its stale frontier and must not leave the
    # caches in a state that diverges from a full parse.
    while buf.continueInitialHighlight():
      discard
    check buf.incrementalHighlight.lineStates.states.len == buf.len
    var lines = newSeq[string](buf.len)
    for i in 0 ..< buf.len:
      lines[i] = buf.getLine(i)
    checkMatchesFullParse(lines, buf.incrementalHighlight, SourceLanguage.langRust)
    # URI underlines survive the flight + resume interplay (the URI row moved
    # from 2000 to 2001 with the insert). Drive the scan per frame: it returns
    # whether a chunk applied URIs, not whether work remains.
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()
    let uriCol = "let x = 1; // see ".len
    check Underline in buf.highlight.getSegmentModifiers(2001, uriCol)

  test "an unclosed Nim block comment spans chunk boundaries":
    # Regression (found by the budgeted fuzz): the Nim tokenizer never set a
    # state for an unclosed `#[` comment, so the continuation re-lexed the
    # comment body as code and convergence spuriously matched the neutral
    # cached state, stopping the re-parse at the boundary.
    var buffer = rustLines(2 * ChunkSize + 50)
    var ih = parseFullIncremental(buffer, SourceLanguage.langNim)
    buffer[ChunkSize + 30] = "#[ outer block"

    let getLine = proc(i: int): string =
      buffer[i]
    while updateHighlightIncremental(
      buffer.len, getLine, ih, ChunkSize + 30, @[], SourceLanguage.langNim, 0, 100, 1
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

  test "an odd-run ##[ marker across a chunk boundary nests like the same-chunk scan":
    # Regression (review finding): the resume branch matches `##[`
    # positionally like the opener scan, so an odd run (`###[`) spanning a
    # chunk boundary must open a nested level and close at the SECOND `]##`,
    # mirroring the same-chunk scan and the real Nim lexer. The opener at
    # row 80 leaves the first chunk unclosed; only the resume branch sees
    # the odd run.
    var buffer = rustLines(2 * ChunkSize + 50)
    var ih = parseFullIncremental(buffer, SourceLanguage.langNim)
    buffer[80] = "##[ doc"
    let oddRun = 78 + ChunkSize + 3
    buffer[oddRun] = "  ###[ odd run"
    buffer[oddRun + 9] = "]##"
    buffer[oddRun + 10] = "let tail = 1"
    buffer[oddRun + 11] = "]##"
    buffer[oddRun + 12] = "let real = 2"

    let getLine = proc(i: int): string =
      buffer[i]
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 80, @[], SourceLanguage.langNim, 0, 100, 1
    )
    :
      discard
    check ih.pendingReparse == nil
    let incrResult = Highlight(colorSegments: ih.segments)
    # One level deep from the odd run: the first `]##` does not close.
    check incrResult.getColorPair(oddRun + 10, 4) == EditorColorPairIndex.docLongComment
    # The second `]##` closes; the code below is code again.
    check incrResult.getColorPair(oddRun + 12, 4) != EditorColorPairIndex.docLongComment
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

  test "an unclosed Python docstring spans chunk boundaries":
    # Regression (found by the budgeted fuzz): the Python tokenizer's EOF
    # guard wiped the docstring state at the chunk end, so the continuation
    # re-lexed the docstring body as code (and convergence spuriously
    # matched the neutral cached state).
    var buffer = rustLines(2 * ChunkSize + 50)
    var ih = parseFullIncremental(buffer, SourceLanguage.langPython)
    buffer[ChunkSize + 31] = "y = '''"

    let getLine = proc(i: int): string =
      buffer[i]
    while updateHighlightIncremental(
      buffer.len, getLine, ih, ChunkSize + 31, @[], SourceLanguage.langPython, 0, 100, 1
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langPython)

  test "a Markdown thematic break at a chunk boundary keeps its color":
    # Regression (found by the budgeted fuzz): Markdown's line-start checks
    # rely on the state a trailing newline leaves (`gtWhitespace`), which the
    # chunk-END capture could not see — a `---` at a chunk boundary was lexed
    # as gtNone and rendered uncolored.
    var buffer = rustLines(ChunkSize + 160)
    var ih = parseFullIncremental(buffer, SourceLanguage.langMarkdown)
    let markerLine = 102 + ChunkSize
    buffer[markerLine] = "---"
    let getLine = proc(i: int): string =
      buffer[i]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, markerLine, @[], SourceLanguage.langMarkdown, 0, 100, 1
    )
    # An edit above moves the re-parse across a chunk boundary exactly at the
    # marker line.
    buffer[104] = "edited paragraph"
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 104, @[], SourceLanguage.langMarkdown, 0, 100, 2
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

  test "a JS doc comment brace block spans chunk boundaries":
    # Regression (found by the budgeted fuzz): the `{...}` preprocessor block
    # inside a doc comment kept its nesting depth in a local variable, so a
    # chunk boundary inside the block lost it and the next chunk resumed the
    # comment body.
    var buffer = rustLines(2 * ChunkSize + 50)
    var ih = parseFullIncremental(buffer, SourceLanguage.langJavaScript)
    let openerLine = ChunkSize - 20
    buffer[openerLine] = "/**"
    let getLine = proc(i: int): string =
      buffer[i]
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, openerLine, @[], SourceLanguage.langJavaScript, 0, 100, 1
    )
    # The `{` opens the block; the MultiLineKinds rewind pushes the re-parse
    # back to the comment opener, so the chunk boundary falls inside the block.
    let braceLine = openerLine + ChunkSize - 6
    buffer[braceLine] = "async function compute(x) {"
    while updateHighlightIncremental(
      buffer.len, getLine, ih, braceLine, @[], SourceLanguage.langJavaScript, 0, 100, 2
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langJavaScript)

  test "a JS doc comment block abandoned at the comment close resumes":
    # Regression (found in review): when a chunk boundary splits a `{...}`
    # block and the comment closes (`*/`) before the block's `}`, the
    # persisted depth must be dropped at the `*/` — otherwise the resume
    # branch returns a zero-length token at the `*/` forever and everything
    # below the comment is re-lexed as comment/preprocessor.
    var buffer = rustLines(2 * ChunkSize + 50)
    var ih = parseFullIncremental(buffer, SourceLanguage.langJavaScript)
    buffer[0] = "/**"
    buffer[ChunkSize - 1] = " * @param {abc"
    buffer[ChunkSize] = " */"
    let getLine = proc(i: int): string =
      buffer[i]
    # The re-parse starts at the top, so the chunk boundary at
    # ChunkSize - 1 / ChunkSize falls inside the `{` block opened on row
    # ChunkSize - 1, and the next chunk starts with the comment close.
    buffer[0] = "/** edited"
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 0, @[], SourceLanguage.langJavaScript, 0, 100, 1
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langJavaScript)

  test "a fenced code block sub-language construct spans chunk boundaries":
    # Regression (found in review): the chunk-END capture must not normalize
    # a sub-language continuation state (an open Python docstring here) to
    # `gtWhitespace` — syntax_markdown resumes on exactly the continuation-
    # state set, so a normalized state re-lexes the construct as fresh code,
    # the closing `'''` opens a NEW docstring and swallows the closing fence.
    var buffer = rustLines(2 * ChunkSize + 50)
    var ih = parseFullIncremental(buffer, SourceLanguage.langMarkdown)
    buffer[ChunkSize - 2] = "```python"
    buffer[ChunkSize - 1] = "x = '''"
    buffer[ChunkSize] = "continued"
    buffer[ChunkSize + 1] = "'''"
    buffer[ChunkSize + 2] = "y = 1"
    buffer[ChunkSize + 3] = "```"
    let getLine = proc(i: int): string =
      buffer[i]
    # The re-parse starts at the top, so the chunk boundary at
    # ChunkSize - 1 / ChunkSize falls inside the docstring opened on row
    # ChunkSize - 1.
    buffer[0] = "paragraph 0 edited"
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 0, @[], SourceLanguage.langMarkdown, 0, 100, 1
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

  test "a restart does not converge inside the discarded flight's window":
    # Regression (found by the budgeted fuzz): a restart inherited the
    # ORIGINAL tail while the discarded flight had refreshed the cached
    # states up to its frontier. The convergence guard was lost on resume
    # calls, so the flight converged inside that window and spliced the
    # ORIGINAL (pre-edit) segments — here an unclosed Nim triple-quoted
    # string was colored as code below the convergence point.
    var buffer = rustLines(250)
    var ih = parseFullIncremental(buffer, SourceLanguage.langNim)
    buffer[130] = "const greeting = \"\"\""
    let getLine = proc(i: int): string =
      buffer[i]
    # Start a flight at the string and leave it in flight.
    check updateHighlightIncremental(
      buffer.len, getLine, ih, 130, @[], SourceLanguage.langNim, 0, 1, 1
    )
    # A second edit restarts the flight from above.
    buffer[8] = buffer[8].substr(0, 5) & "|" & buffer[8].substr(6)
    discard updateHighlightIncremental(
      buffer.len, getLine, ih, 8, @[], SourceLanguage.langNim, 0, 37, 2
    )
    while updateHighlightIncremental(
      buffer.len, getLine, ih, 8, @[], SourceLanguage.langNim, 0, 37, 2
    )
    :
      discard
    check ih.pendingReparse == nil
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

suite "Highlight - Nim Incremental Comment/String":
  test "insert comment in Nim source":
    var buffer = @[
      "import std/os", "", "type", "  Foo = object", "    name: string",
      "    value: int", "", "proc bar(f: Foo): string =", "  result = f.name",
    ]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

    # Insert comment before proc bar
    buffer.insert("# Helper function", 7)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      7,
      @[],
      SourceLanguage.langNim,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

  test "multiline string then insert comment":
    var buffer = @["let s = \"\"\"", "hello", "world", "\"\"\"", "echo s"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

    # Insert comment after the multiline string
    buffer.insert("# done", 5)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      5,
      @[],
      SourceLanguage.langNim,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

  test "simulate typing comment char by char":
    var buffer = @["import std/os", "", "proc main() =", "  echo \"hello\""]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

    # Insert empty line at 3
    buffer.insert("", 3)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      3,
      @[],
      SourceLanguage.langNim,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

    # Type '#'
    buffer[3] = "#"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      3,
      @[],
      SourceLanguage.langNim,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

    # Type '# comment'
    buffer[3] = "# comment"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      3,
      @[],
      SourceLanguage.langNim,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

  test "odd hash runs inside a ##[ doc comment nest positionally":
    # Pins the doc-comment nesting semantics (review finding): the `##[`
    # marker is matched at any offset, so an odd run like `###[` opens a
    # nested level — the comment closes at the SECOND `]##`, exactly as the
    # real Nim lexer behaves. The pre-budget lexHash consumed `##` in pairs
    # and skipped odd runs; the positional behavior is intentional.
    var buffer =
      @["##[ outer doc", "  ###[ odd run", "]##", "let tail = 1", "]##", "let real = 2"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

    let incrResult = Highlight(colorSegments: ih.segments)
    # One level deep from the odd run: the first `]##` does not close.
    check incrResult.getColorPair(3, 4) == EditorColorPairIndex.docLongComment
    # The second `]##` closes; the code below is code again.
    check incrResult.getColorPair(5, 4) != EditorColorPairIndex.docLongComment

  test "even hash runs inside a ##[ doc comment nest once":
    # Even runs (`####[`) must open exactly one nested level too: the
    # positional scan matches the marker at the last two hashes, matching the
    # old pair-consuming lexHash's depth. Pin the parity so a future refactor
    # cannot flip it.
    var buffer = @[
      "##[ outer doc", "  ####[ even run", "]##", "let tail = 1", "]##", "let real = 2"
    ]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langNim)

    let incrResult = Highlight(colorSegments: ih.segments)
    check incrResult.getColorPair(3, 4) == EditorColorPairIndex.docLongComment
    check incrResult.getColorPair(5, 4) != EditorColorPairIndex.docLongComment

suite "Highlight - Block Comment Multiline State":
  test "C: insert after multiline block comment":
    var buffer = @["int x = 1;", "/* this is", "   a comment", "*/", "int y = 2;"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langC
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))

    buffer.insert("int z = 3;", 5)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      5,
      @[],
      SourceLanguage.langC,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langC)

  test "Rust: insert after multiline block comment":
    var buffer = @["fn main() {", "/* block", "   comment */", "let x = 1;", "}"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langRust
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))

    buffer.insert("let z = 2;", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      @[],
      SourceLanguage.langRust,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langRust)

  test "JavaScript: insert after multiline block comment":
    var buffer = @["let x = 1;", "/* block", "   comment */", "let y = 2;"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langJavaScript
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))

    buffer.insert("let z = 3;", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      @[],
      SourceLanguage.langJavaScript,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langJavaScript)

  test "TypeScript: insert after multiline block comment":
    var buffer =
      @["let x: number = 1;", "/* block", "   comment */", "let y: number = 2;"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langTypeScript
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))

    buffer.insert("let z: number = 3;", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      @[],
      SourceLanguage.langTypeScript,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langTypeScript)

  test "Haskell: insert after multiline block comment":
    var buffer =
      @["module Main where", "{- block", "   comment -}", "main = putStrLn \"hello\""]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langHaskell
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))

    buffer.insert("foo = 1", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      @[],
      SourceLanguage.langHaskell,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langHaskell)

  test "TOML: insert after multiline string":
    var buffer = @["name = \"\"\"", "hello", "world\"\"\"", "value = 42"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langToml
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))

    buffer.insert("other = 1", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      @[],
      SourceLanguage.langToml,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langToml)

proc loadProgressiveScalarFixture(filename: string, scalarLines = 1200): TextBuffer =
  ## A YAML file whose block scalar spans continueInitialHighlight's
  ## ChunkSize=1000 chunk boundary, so the progressive load's resume rewind
  ## fires (the stored boundary state at the chunk edge is gtLongStringLit).
  result = newTextBuffer()
  let path = getTempDir() / filename
  defer:
    removeFile(path)
  var content = "top: value\nscalar: |\n"
  for i in 0 ..< scalarLines:
    content.add("  block scalar line " & $i & "\n")
  content.add("after: tail\n")
  writeFile(path, content)
  discard result.loadFile(path)

suite "Highlight - YAML internal chunk boundary handoff":
  # updateHighlightIncremental parses in ChunkSize=100 chunks and feeds each
  # chunk's final tokenizer state to the next chunk. A multi-line construct
  # crossing that internal boundary must highlight exactly as a full parse:
  # the tokenizer must not park gtOther at the chunk buffer's NUL while still
  # inside the construct. Regression tests for the chunk-handoff state loss
  # (fuzz cannot see this class: its buffers stay far below 100 lines).
  proc checkIncrementalMatchesFull(
      original: seq[string], editRow: int, insertLine = false
  ) =
    var buffer = original
    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langYaml
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))

    if insertLine:
      # A line-count change disables convergence: everything below is
      # re-parsed, which exercises every internal chunk boundary after the
      # insert point.
      buffer.insert("inserted: line", editRow)
    else:
      buffer[editRow] = buffer[editRow] & "x"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      editRow,
      @[],
      SourceLanguage.langYaml,
    )

    checkMatchesFullParse(buffer, ih, SourceLanguage.langYaml)

  test "double-quoted string crossing the chunk boundary":
    var buffer = @["multi: \"first line of string"]
    for i in 0 ..< 150:
      buffer.add("  still inside the string " & $i)
    buffer.add("  the end\"")
    buffer.add("afterkey: plainvalue")
    checkIncrementalMatchesFull(buffer, 2)

  test "single-quoted string crossing the chunk boundary":
    var buffer = @["multi: 'first line of string"]
    for i in 0 ..< 150:
      buffer.add("  still inside the string " & $i)
    buffer.add("  the end'")
    buffer.add("afterkey: plainvalue")
    checkIncrementalMatchesFull(buffer, 2)

  test "block scalar crossing the chunk boundary":
    var buffer = @["top: value", "long: |"]
    for i in 0 ..< 160:
      buffer.add("  scalar content " & $i)
    buffer.add("after: tail")
    for i in 0 ..< 20:
      buffer.add("k" & $i & ": v" & $i)
    checkIncrementalMatchesFull(buffer, 3)

  test "block scalar header as the chunk's last line":
    # The header (`block: |`) lands exactly on a 100-line chunk's last line,
    # so the boundary state is the pending-header gtCommand — which a fresh
    # chunk cannot resume; the handoff must rewind past it.
    var buffer: seq[string]
    for i in 0 ..< 99:
      buffer.add("key" & $i & ": value" & $i)
    buffer.add("block: |")
    for i in 0 ..< 30:
      buffer.add("  scalar content " & $i)
    buffer.add("after: tail")
    checkIncrementalMatchesFull(buffer, 0)

  test "block scalar header flipped mid-chunk, blank line at the boundary":
    # The header is not the chunk's last line, so its trailing newline flips
    # the state to gtLongStringLit inside the chunk; the blank line after it
    # starts the scalar (persisting `blockScalarActive`) and is then cut by
    # the chunk end. The next chunk must resume the scalar from the
    # persisted context, not fall back to plain parsing.
    var buffer: seq[string]
    for i in 0 ..< 98:
      buffer.add("key" & $i & ": value" & $i)
    buffer.add("block: |")
    buffer.add("") # the chunk [0..99] ends here, one row past the header
    for i in 0 ..< 30:
      buffer.add("  scalar content " & $i)
    buffer.add("after: tail")
    checkIncrementalMatchesFull(buffer, 0)

  test "block scalar first content line at the chunk boundary":
    # The header's newline is inside the chunk, so the flip happens
    # mid-chunk; the very first content line then starts the scalar and is
    # cut by the chunk end. The next chunk resumes the scalar mid-flight
    # from the persisted context.
    var buffer: seq[string]
    for i in 0 ..< 98:
      buffer.add("key" & $i & ": value" & $i)
    buffer.add("block: |")
    buffer.add("  first scalar content") # the chunk [0..99] ends here
    for i in 0 ..< 29:
      buffer.add("  more scalar content " & $i)
    buffer.add("after: tail")
    checkIncrementalMatchesFull(buffer, 0)

  test "alone block scalar header at an internal chunk boundary":
    # The alone header takes its indentation from the parent line above it.
    # When the header becomes a chunk's first line, the parent search must
    # not run off the chunk's top (it would force top level and swallow the
    # following keys) — the handoff has to rewind to the parent line.
    var buffer: seq[string]
    for i in 0 ..< 100:
      buffer.add("key" & $i & ": value" & $i)
    buffer.add("  parent:")
    buffer.add("    |")
    buffer.add("      folded content one")
    buffer.add("      folded content two")
    buffer.add("  next: outside")
    checkIncrementalMatchesFull(buffer, 4, insertLine = true)

  test "blank line inside a block scalar at the chunk boundary":
    # A chunk cut at a blank line inside the scalar must not end the scalar:
    # the blank line's indentation is unknowable until the next real line.
    var buffer = @["long: |"]
    for i in 0 ..< 98:
      buffer.add("  scalar content " & $i)
    buffer.add("") # the blank line lands at the 100-line chunk boundary
    for i in 0 ..< 30:
      buffer.add("  more content " & $i)
    buffer.add("after: tail")
    checkIncrementalMatchesFull(buffer, 1)

  test "progressive initial load resumes a block scalar across chunks":
    # continueInitialHighlight (ChunkSize=1000) must rewind its resume point
    # when the stored boundary state sits inside a block scalar: opening a
    # large YAML file must highlight it exactly as a full parse, no edits
    # required.
    var buf = loadProgressiveScalarFixture("moe_test_yaml_progressive_scalar.yaml")

    while buf.continueInitialHighlight():
      discard
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1

    var lines = newSeq[string](buf.len)
    for i in 0 ..< buf.len:
      lines[i] = buf.getLine(i)
    checkMatchesFullParse(lines, buf.incrementalHighlight, SourceLanguage.langYaml)

  test "progressive load advances a chunk-spanning block scalar linearly":
    # A chunk-spanning block scalar used to force a rewind to its header
    # every tick, re-parsing the whole prefix each time (quadratic total).
    # The scalar is now resumable across chunk boundaries, so the load
    # advances by a clean ChunkSize per tick — linear total.
    var buf = loadProgressiveScalarFixture(
      "moe_test_yaml_progressive_geometric.yaml", scalarLines = 10_000
    )

    var ticks = 0
    var maxLines = 0
    var consumed = 0
    while buf.continueInitialHighlight(0, consumed):
      inc ticks
      maxLines = max(maxLines, consumed)
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1
    # loadFile already parsed the first chunk; the remaining 9k scalar lines
    # advance one ChunkSize per tick plus the trailing tail chunk — no
    # rewinds.
    check ticks == 10
    check maxLines <= 1000

  test "budgeted progressive load completes across a deep rewind":
    # Regression: a rewind deeper than 4x the budget used to cap the window
    # at the old frontier, stalling the load forever. The cap is floored at
    # the rewind depth + one budget.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_yaml_progressive_deep_rewind.yaml"
    defer:
      removeFile(path)
    var content = "scalar: |\n"
    for i in 0 ..< 5000:
      content.add("\n")
    content.add("after: tail\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    var consumed = 0
    var ticks = 0
    # The tick bound keeps a pre-fix stall a bounded failure, not a hang.
    while buf.continueInitialHighlight(1000, consumed) and ticks < 100:
      inc ticks
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1
    check ticks < 100

    var lines = newSeq[string](buf.len)
    for i in 0 ..< buf.len:
      lines[i] = buf.getLine(i)
    checkMatchesFullParse(lines, buf.incrementalHighlight, SourceLanguage.langYaml)

  test "edit during progressive load does not duplicate cached rows":
    # An edit mid-load runs updateHighlightIncremental, which fills the caches
    # to EOF without advancing parsedUpTo; the next tick must drop the rows
    # past its resume point instead of appending duplicates (states grew past
    # the buffer length and segments lost the row ordering the binary
    # searches rely on).
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_yaml_edit_during_load.yaml"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 2500:
      content.add("key" & $i & ": value" & $i & "\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    check buf.incrementalHighlight.parsedUpTo < buf.len - 1

    # Edit while the progressive load is still behind.
    discard buf.beginTransaction()
    discard buf.deleteLine(5)
    discard buf.insert(5, "edited: line")
    discard buf.commitTransaction()
    buf.updateHighlight()

    while buf.continueInitialHighlight():
      discard

    check buf.incrementalHighlight.parsedUpTo == buf.len - 1
    check buf.incrementalHighlight.lineStates.states.len == buf.len
    var sorted = true
    for i in 1 ..< buf.incrementalHighlight.segments.len:
      if buf.incrementalHighlight.segments[i].firstRow <
          buf.incrementalHighlight.segments[i - 1].firstRow:
        sorted = false
    check sorted

suite "Highlight - early tokenizer stop keeps the line-state cache consistent":
  # When the tokenizer stops before the end of a chunk (gtEof at an interior
  # NUL byte, or the defensive out-of-bounds break), the producer must still
  # return one lineState per chunk line: the chunked drivers index into the
  # array positionally and advance `parsedUpTo` by the chunk size, so a short
  # array crashed with IndexDefect — in the internal handoff scan on the next
  # edit, and in continueInitialHighlight's `states[startLine - 1]` read on
  # the next tick.

  test "interior NUL pads lineStates to one per line":
    let bufferStr = "key: a\0b\nsecond: x\nthird: y"
    let (_, lineStates) = initHighlightIncrementalFromStr(
      bufferStr, 0, 2, TokenizerState(), @[], SourceLanguage.langYaml
    )
    check lineStates.len == 3

  test "interior NUL: incremental update survives and stays full-length":
    # Reproduces the handoff-scan IndexDefect: chunk [0..99] stops at the NUL
    # on line 10, then the scan indexed newLineStates[99] on an 11-entry seq.
    var buffer: seq[string]
    for i in 0 ..< 150:
      buffer.add("key" & $i & ": value" & $i)
    buffer[10] = "bin: a\0b"

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langYaml
    )
    check ls0.len == buffer.len
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))

    buffer[0] = buffer[0] & "x"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      0,
      @[],
      SourceLanguage.langYaml,
    )
    check ih.lineStates.states.len == buffer.len

  test "interior NUL: progressive initial load completes":
    # Reproduces the per-tick IndexDefect: the first chunk's parse stopped at
    # the NUL with ~11 states while parsedUpTo advanced to 999, so the next
    # tick read states[999] out of bounds — on every frame, killing the load.
    var buf = newTextBuffer()
    let path = getTempDir() / "moe_test_yaml_nul_progressive.yaml"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 1500:
      if i == 10:
        content.add("bin: a\0b\n")
      else:
        content.add("key" & $i & ": value" & $i & "\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    while buf.continueInitialHighlight():
      discard
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1
    check buf.incrementalHighlight.lineStates.states.len == buf.len

  test "markdown early stop pads every row with a resumable state":
    # Regression: the boundary normalization used to fire only for a
    # single-row pad; every padded row must be resumable or the next chunk
    # mis-lexes markdown line-start tokens (`---`, `#`).
    let bufferStr = "text a\0b\nplain body\nmore text\neven more"
    let (_, lineStates) = initHighlightIncrementalFromStr(
      bufferStr, 0, 3, TokenizerState(), @[], SourceLanguage.langMarkdown
    )
    check lineStates.len == 4
    const Resumable = {
      gtWhitespace, gtDocLongComment, gtLongStringLit, gtLongComment, gtStringLit,
      gtCData,
    }
    for state in lineStates:
      check state.state in Resumable

  test "gtCommand resume on a blank-first-line chunk parses the chunk":
    # Regression: resuming a fresh tokenizer from a captured gtCommand state
    # (block scalar header as the previous chunk's last line) with the chunk
    # starting on a newline hit the header branch's '\n' arm, which never
    # assigned `kind` — the init value gtEof leaked out of the first call and
    # the consumer dropped the whole chunk (zero segments). The drivers'
    # rewind currently excludes gtCommand handoffs, so this pins the contract
    # for any future caller resuming from a stored state.
    let (segments, lineStates) = initHighlightIncrementalFromStr(
      "\n  content\nafter: x",
      100,
      102,
      TokenizerState(state: gtCommand),
      @[],
      SourceLanguage.langYaml,
    )
    check lineStates.len == 3
    check segments.len > 0

suite "Highlight - diagnostics survive progressive load":
  test "rewound rows keep their diagnostic styling":
    # continueInitialHighlight's rewind truncates the display highlight and
    # re-appends plain parser segments; diagnostic undercurls (applied into
    # b.highlight by updateHighlight) on the rewound rows must be re-applied,
    # not silently dropped until the next edit.
    var buf = loadProgressiveScalarFixture("moe_test_yaml_diag_progressive.yaml")

    buf.diagnostics = @[
      BufferDiagnostic(
        startLine: 500,
        startCol: 0,
        endLine: 500,
        endCol: 5,
        severity: bdsError,
        message: "test error",
      )
    ]
    buf.diagnosticsDirty = true
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()
    check buf.highlight.getSegmentModifiers(500, 2) == {StyleModifier.Undercurl}

    # The next tick rewinds into the block scalar (the stored boundary state
    # at the 1000-line chunk edge is gtLongStringLit), truncating the display
    # segments from the scalar header down — including row 500.
    while buf.continueInitialHighlight():
      discard
    check buf.highlight.getSegmentModifiers(500, 2) == {StyleModifier.Undercurl}

  test "clearing diagnostics leaves no residual styling after URI scan rewind":
    # End-to-end: rewinding continueUriScan, then clearing diagnostics and
    # editing far from the affected line, must leave the old diagnostic line
    # with no undercurl and no syntaxCheck* colour.
    var buf = newTextBuffer()

    let path = getTempDir() / "test_uri_scan_diag_no_bake.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 500:
      if i == 250:
        content.add("// see https://example.com/api\n")
      else:
        content.add("let x = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()

    buf.diagnostics = @[
      BufferDiagnostic(
        startLine: 100,
        startCol: 0,
        endLine: 100,
        endCol: 5,
        severity: bdsError,
        message: "test error",
      )
    ]
    buf.diagnosticsDirty = true
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()
    check StyleModifier.Undercurl in buf.highlight.getSegmentModifiers(100, 2)

    buf.uriScanParsedUpTo = -1
    discard buf.continueUriScan()

    buf.diagnostics.setLen(0)
    buf.diagnosticsDirty = true

    buf.lastChangedLines = 490
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()

    check StyleModifier.Undercurl notin buf.highlight.getSegmentModifiers(100, 2)
    check buf.highlight.getColorPair(100, 2) notin {
      EditorColorPairIndex.syntaxCheckErr, EditorColorPairIndex.syntaxCheckWarn,
      EditorColorPairIndex.syntaxCheckInfo, EditorColorPairIndex.syntaxCheckHint,
    }

suite "Highlight - JS/TS String Line Bounding":
  # JS/TS string tokens (and the isKey lookahead) must not cross a newline:
  # a line's tokens may depend only on the tokenizer state at the line's
  # start, never on later lines, or incremental re-parsing (which resumes
  # from per-line states) diverges from a full reparse.
  proc runEditBelow(
      lang: SourceLanguage, buffer0: seq[string], editRow: int, newLine: string
  ) =
    var buffer = buffer0
    let (seg0, ls0) =
      initHighlightIncremental(buffer, 0, buffer.high, TokenizerState(), @[], lang)
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    buffer[editRow] = newLine
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      editRow,
      @[],
      lang,
    )
    checkMatchesFullParse(buffer, ih, lang)

  proc runColonBelowString(lang: SourceLanguage) =
    # Fuzz seed 180608 shape: an unterminated string on row 0 with a closing
    # quote + colon appearing rows below. A newline-crossing isKey lookahead
    # made row 0 gtKey in a full reparse, while the incremental pass (which
    # never re-tokenizes row 0 for an edit on row 4) kept gtStringLit.
    var buffer = @["s = \"abc", "1", "2", "3", "q\" 1"]
    let (seg0, ls0) =
      initHighlightIncremental(buffer, 0, buffer.high, TokenizerState(), @[], lang)
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    # Introduce the colon after the closing quote on row 4
    buffer[4] = "q\": 1"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      @[],
      lang,
    )
    checkMatchesFullParse(buffer, ih, lang)
    # Row 0's string must stay a string: its color may not depend on row 4.
    check Highlight(colorSegments: ih.segments).getColorPair(0, 4) ==
      EditorColorPairIndex.stringLit

  test "JS: escaped newline ends the string at EOL (edit below the margin)":
    # `"a\` once continued onto the next line; the continuation line's state
    # was captured as plain code, so an edit 3+ lines below (outside
    # updateHighlightIncremental's 2-line backward margin) resumed the
    # continuation line fresh and diverged from a full reparse.
    runEditBelow(
      SourceLanguage.langJavaScript,
      @["x = \"a\\", "b\" + 1", "foo()", "bar()"],
      3,
      "bar(1)",
    )

  test "JS: escaped-newline chain longer than the backward margin":
    runEditBelow(
      SourceLanguage.langJavaScript,
      @["x = \"a\\", "b\\", "c\\", "d\" + 1"],
      3,
      "d\" + 11",
    )

  test "TS: escaped newline ends the string at EOL (edit below the margin)":
    runEditBelow(
      SourceLanguage.langTypeScript,
      @["x = \"a\\", "b\" + 1", "foo()", "bar()"],
      3,
      "bar(1)",
    )

  test "TS: escaped-newline chain longer than the backward margin":
    runEditBelow(
      SourceLanguage.langTypeScript,
      @["x = \"a\\", "b\\", "c\\", "d\" + 1"],
      3,
      "d\" + 11",
    )

  test "JS: isKey lookahead must not see a colon on a later line":
    runColonBelowString(SourceLanguage.langJavaScript)

  test "TS: isKey lookahead must not see a colon on a later line":
    runColonBelowString(SourceLanguage.langTypeScript)

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

  test "detectLanguage for COMMIT_EDITMSG":
    check detectLanguage("COMMIT_EDITMSG") == SourceLanguage.langCommitEditMsg

  test "detectLanguage for COMMIT_EDITMSG with path":
    check detectLanguage("/repo/.git/COMMIT_EDITMSG") == SourceLanguage.langCommitEditMsg

  test "detectLanguage for git-rebase-todo":
    check detectLanguage("git-rebase-todo") == SourceLanguage.langGitRebaseTodo

  test "detectLanguage for git-rebase-todo with path":
    check detectLanguage("/repo/.git/rebase-merge/git-rebase-todo") ==
      SourceLanguage.langGitRebaseTodo

  test "detectLanguage for .gitignore":
    check detectLanguage(".gitignore") == SourceLanguage.langGitignore

  test "detectLanguage for .gitignore with path":
    check detectLanguage("/repo/.gitignore") == SourceLanguage.langGitignore

  test "detectLanguage for LaTeX .tex":
    check detectLanguage("main.tex") == SourceLanguage.langLatex

  test "detectLanguage for LaTeX .sty":
    check detectLanguage("custom.sty") == SourceLanguage.langLatex

  test "detectLanguage for LaTeX .cls":
    check detectLanguage("myclass.cls") == SourceLanguage.langLatex

  test "detectLanguage for LaTeX .ltx":
    check detectLanguage("file.ltx") == SourceLanguage.langLatex

  test "detectLanguage for LaTeX .dtx":
    check detectLanguage("package.dtx") == SourceLanguage.langLatex

  test "detectLanguage for Tcl .tcl":
    check detectLanguage("script.tcl") == SourceLanguage.langTcl

  test "detectLanguage for Tcl .tk":
    check detectLanguage("gui.tk") == SourceLanguage.langTcl

  test "detectLanguage for Tcl .itcl":
    check detectLanguage("class.itcl") == SourceLanguage.langTcl

  test "detectLanguage for Tcl .itk":
    check detectLanguage("widget.itk") == SourceLanguage.langTcl

  test "detectLanguage for Go .go":
    check detectLanguage("main.go") == SourceLanguage.langGo

  test "detectLanguage for Lua .lua":
    check detectLanguage("init.lua") == SourceLanguage.langLua

  test "detectLanguage for Lua .luau":
    check detectLanguage("script.luau") == SourceLanguage.langLua

  test "detectLanguage for Lua .rockspec":
    check detectLanguage("mylib-1.0-1.rockspec") == SourceLanguage.langLua

  test "detectLanguage for Zsh .zsh":
    check detectLanguage("script.zsh") == SourceLanguage.langZsh

  test "detectLanguage for Zsh .zshrc":
    check detectLanguage("custom.zshrc") == SourceLanguage.langZsh

  test "detectLanguage for Zsh .zshenv":
    check detectLanguage("env.zshenv") == SourceLanguage.langZsh

  test "detectLanguage for Zsh .zlogin":
    check detectLanguage("login.zlogin") == SourceLanguage.langZsh

  test "detectLanguage for Zsh .zlogout":
    check detectLanguage("logout.zlogout") == SourceLanguage.langZsh

  test "detectLanguage for Zsh .zprofile":
    check detectLanguage("profile.zprofile") == SourceLanguage.langZsh

  test "detectLanguage for XML .xml":
    check detectLanguage("config.xml") == SourceLanguage.langXml

  test "detectLanguage for XML .svg":
    check detectLanguage("icon.svg") == SourceLanguage.langXml

  test "detectLanguage for XML .xsd":
    check detectLanguage("schema.xsd") == SourceLanguage.langXml

  test "detectLanguage for XML .xsl":
    check detectLanguage("style.xsl") == SourceLanguage.langXml

  test "detectLanguage for XML .xslt":
    check detectLanguage("transform.xslt") == SourceLanguage.langXml

  test "detectLanguage for XML .rss":
    check detectLanguage("feed.rss") == SourceLanguage.langXml

  test "detectLanguage for XML .atom":
    check detectLanguage("feed.atom") == SourceLanguage.langXml

  test "detectLanguage for XML .plist":
    check detectLanguage("Info.plist") == SourceLanguage.langXml

suite "Highlight - getSegmentModifiers":
  test "Empty highlight returns empty modifiers":
    let h = Highlight(colorSegments: @[])
    check h.getSegmentModifiers(0, 0) == {}

  test "Position outside range returns empty modifiers":
    let h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 5,
          color: EditorColorPairIndex.default,
          style: Style(modifiers: {StyleModifier.Undercurl}),
        )
      ]
    )
    check h.getSegmentModifiers(1, 0) == {}

  test "Position inside segment returns segment modifiers":
    let h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: Style(modifiers: {StyleModifier.Undercurl}),
        )
      ]
    )
    check h.getSegmentModifiers(0, 3) == {StyleModifier.Undercurl}

  test "Segment without modifiers returns empty set":
    let h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: Style(modifiers: {}),
        )
      ]
    )
    check h.getSegmentModifiers(0, 3) == {}

suite "Highlight - addModifier":
  test "Fully contained segment":
    # Segment covers 0..10, modifier range covers 0..10
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.addModifier(0, 0, 0, 10, StyleModifier.Underline)
    check h.colorSegments.len == 1
    check Underline in h.colorSegments[0].style.modifiers

  test "No overlap":
    # Segment on row 0, modifier on row 1
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.addModifier(1, 0, 1, 5, StyleModifier.Underline)
    check h.colorSegments.len == 1
    check Underline notin h.colorSegments[0].style.modifiers

  test "Split segment - modifier in the middle":
    # Segment covers cols 0..20, modifier covers cols 5..10
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 20,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.addModifier(0, 5, 0, 10, StyleModifier.Underline)
    check h.colorSegments.len == 3
    # Before: 0..4, no modifier
    check h.colorSegments[0].firstColumn == 0
    check h.colorSegments[0].lastColumn == 4
    check Underline notin h.colorSegments[0].style.modifiers
    # Middle: 5..10, with modifier
    check h.colorSegments[1].firstColumn == 5
    check h.colorSegments[1].lastColumn == 10
    check Underline in h.colorSegments[1].style.modifiers
    # After: 11..20, no modifier
    check h.colorSegments[2].firstColumn == 11
    check h.colorSegments[2].lastColumn == 20
    check Underline notin h.colorSegments[2].style.modifiers

  test "Split segment - modifier at the start":
    # Segment covers cols 0..20, modifier covers cols 0..5
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 20,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.addModifier(0, 0, 0, 5, StyleModifier.Underline)
    check h.colorSegments.len == 2
    # Modified: 0..5
    check h.colorSegments[0].firstColumn == 0
    check h.colorSegments[0].lastColumn == 5
    check Underline in h.colorSegments[0].style.modifiers
    # After: 6..20
    check h.colorSegments[1].firstColumn == 6
    check h.colorSegments[1].lastColumn == 20
    check Underline notin h.colorSegments[1].style.modifiers

  test "Split segment - modifier at the end":
    # Segment covers cols 0..20, modifier covers cols 15..20
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 20,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.addModifier(0, 15, 0, 20, StyleModifier.Underline)
    check h.colorSegments.len == 2
    # Before: 0..14
    check h.colorSegments[0].firstColumn == 0
    check h.colorSegments[0].lastColumn == 14
    check Underline notin h.colorSegments[0].style.modifiers
    # Modified: 15..20
    check h.colorSegments[1].firstColumn == 15
    check h.colorSegments[1].lastColumn == 20
    check Underline in h.colorSegments[1].style.modifiers

  test "Multiple segments - modifier spans partial overlap":
    # Two segments: cols 0..9 and 10..19, modifier covers 5..14
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 9,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        ),
        ColorSegment(
          firstRow: 0,
          firstColumn: 10,
          lastRow: 0,
          lastColumn: 19,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        ),
      ]
    )
    h.addModifier(0, 5, 0, 14, StyleModifier.Underline)
    check h.colorSegments.len == 4
    # seg0 before: 0..4
    check h.colorSegments[0].firstColumn == 0
    check h.colorSegments[0].lastColumn == 4
    check Underline notin h.colorSegments[0].style.modifiers
    # seg0 overlap: 5..9
    check h.colorSegments[1].firstColumn == 5
    check h.colorSegments[1].lastColumn == 9
    check Underline in h.colorSegments[1].style.modifiers
    # seg1 overlap: 10..14
    check h.colorSegments[2].firstColumn == 10
    check h.colorSegments[2].lastColumn == 14
    check Underline in h.colorSegments[2].style.modifiers
    # seg1 after: 15..19
    check h.colorSegments[3].firstColumn == 15
    check h.colorSegments[3].lastColumn == 19
    check Underline notin h.colorSegments[3].style.modifiers

  test "Preserves existing modifiers":
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: Style(modifiers: {StyleModifier.Bold}),
        )
      ]
    )
    h.addModifier(0, 0, 0, 10, StyleModifier.Underline)
    check h.colorSegments.len == 1
    check Bold in h.colorSegments[0].style.modifiers
    check Underline in h.colorSegments[0].style.modifiers

  test "Preserves color on split":
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 20,
          color: EditorColorPairIndex.keyword,
          style: defaultStyle,
        )
      ]
    )
    h.addModifier(0, 5, 0, 10, StyleModifier.Underline)
    check h.colorSegments.len == 3
    for seg in h.colorSegments:
      check seg.color == EditorColorPairIndex.keyword

  test "Multi-row segment - modifier starts at column 0 on a later row":
    # Segment spans rows 0..1, modifier range starts at (1, 0).
    # The before-segment should end at row 0 without using high(int).
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 5,
          lastRow: 1,
          lastColumn: 15,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.addModifier(1, 0, 1, 10, StyleModifier.Underline)
    check h.colorSegments.len == 3
    # Before: row 0 col 5 .. row 0 (no modifier)
    check h.colorSegments[0].firstRow == 0
    check h.colorSegments[0].firstColumn == 5
    check h.colorSegments[0].lastRow == 0
    check h.colorSegments[0].lastColumn <= 15 # Must not be high(int)
    check Underline notin h.colorSegments[0].style.modifiers
    # Overlap: (1,0)..(1,10) with modifier
    check h.colorSegments[1].firstRow == 1
    check h.colorSegments[1].firstColumn == 0
    check h.colorSegments[1].lastRow == 1
    check h.colorSegments[1].lastColumn == 10
    check Underline in h.colorSegments[1].style.modifiers
    # After: (1,11)..(1,15) no modifier
    check h.colorSegments[2].firstRow == 1
    check h.colorSegments[2].firstColumn == 11
    check h.colorSegments[2].lastRow == 1
    check h.colorSegments[2].lastColumn == 15
    check Underline notin h.colorSegments[2].style.modifiers

  test "Multi-row segment - modifier covers middle rows":
    # Segment spans rows 0..2, modifier covers row 1 entirely.
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 3,
          lastRow: 2,
          lastColumn: 8,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.addModifier(1, 0, 1, 20, StyleModifier.Underline)
    check h.colorSegments.len == 3
    # Before: row 0
    check h.colorSegments[0].firstRow == 0
    check h.colorSegments[0].lastRow == 0
    check Underline notin h.colorSegments[0].style.modifiers
    # Overlap: row 1
    check h.colorSegments[1].firstRow == 1
    check h.colorSegments[1].firstColumn == 0
    check h.colorSegments[1].lastRow == 1
    check h.colorSegments[1].lastColumn == 20
    check Underline in h.colorSegments[1].style.modifiers
    # After: row 1 col 21 .. row 2 col 8
    check h.colorSegments[2].firstRow == 1
    check h.colorSegments[2].firstColumn == 21
    check h.colorSegments[2].lastRow == 2
    check h.colorSegments[2].lastColumn == 8
    check Underline notin h.colorSegments[2].style.modifiers

suite "Highlight - overwrite":
  test "Empty highlight is unchanged":
    var h = Highlight(colorSegments: @[])
    h.overwrite(
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: 0,
        lastColumn: 10,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 0

  test "Non-intersecting segment is preserved":
    # Segment on row 0, overwrite on row 5
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.overwrite(
      ColorSegment(
        firstRow: 5,
        firstColumn: 0,
        lastRow: 5,
        lastColumn: 10,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 1
    check h.colorSegments[0].color == EditorColorPairIndex.default

  test "Overwrite segment fully contained — color replaced":
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    # overwrite range fully contains the existing segment
    h.overwrite(
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: 0,
        lastColumn: 20,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 1
    check h.colorSegments[0].color == EditorColorPairIndex.keyword
    check h.colorSegments[0].firstColumn == 0
    check h.colorSegments[0].lastColumn == 10

  test "Overwrite in the middle splits into 3":
    # existing 0..20, overwrite 5..10 — splits into [0..4, 5..10, 11..20]
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 20,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.overwrite(
      ColorSegment(
        firstRow: 0,
        firstColumn: 5,
        lastRow: 0,
        lastColumn: 10,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 3
    check h.colorSegments[0].firstColumn == 0
    check h.colorSegments[0].lastColumn == 4
    check h.colorSegments[0].color == EditorColorPairIndex.default
    check h.colorSegments[1].firstColumn == 5
    check h.colorSegments[1].lastColumn == 10
    check h.colorSegments[1].color == EditorColorPairIndex.keyword
    check h.colorSegments[2].firstColumn == 11
    check h.colorSegments[2].lastColumn == 20
    check h.colorSegments[2].color == EditorColorPairIndex.default

  test "Overwrite partial overlap from the left":
    # existing 5..15, overwrite 0..10 — yields [0..10 keyword, 11..15 default]
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 5,
          lastRow: 0,
          lastColumn: 15,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.overwrite(
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: 0,
        lastColumn: 10,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 2
    check h.colorSegments[0].color == EditorColorPairIndex.keyword
    check h.colorSegments[0].lastColumn == 10
    check h.colorSegments[1].color == EditorColorPairIndex.default
    check h.colorSegments[1].firstColumn == 11
    check h.colorSegments[1].lastColumn == 15

  test "Overwrite partial overlap from the right":
    # existing 0..10, overwrite 5..15 — yields [0..4 default, 5..10 keyword]
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )
    h.overwrite(
      ColorSegment(
        firstRow: 0,
        firstColumn: 5,
        lastRow: 0,
        lastColumn: 15,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 2
    check h.colorSegments[0].color == EditorColorPairIndex.default
    check h.colorSegments[0].lastColumn == 4
    check h.colorSegments[1].color == EditorColorPairIndex.keyword
    check h.colorSegments[1].firstColumn == 5
    check h.colorSegments[1].lastColumn == 10

  test "Overwrite preserves segments outside affected row range":
    # 5 segments on rows 0..4, overwrite only row 2
    var h = Highlight(colorSegments: @[])
    for r in 0 .. 4:
      h.colorSegments.add(
        ColorSegment(
          firstRow: r,
          firstColumn: 0,
          lastRow: r,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      )
    h.overwrite(
      ColorSegment(
        firstRow: 2,
        firstColumn: 0,
        lastRow: 2,
        lastColumn: 10,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 5
    check h.colorSegments[0].color == EditorColorPairIndex.default
    check h.colorSegments[1].color == EditorColorPairIndex.default
    check h.colorSegments[2].color == EditorColorPairIndex.keyword
    check h.colorSegments[3].color == EditorColorPairIndex.default
    check h.colorSegments[4].color == EditorColorPairIndex.default

  test "Overwrite spanning multiple rows":
    # Rows 0..3 each fully covered, overwrite spans rows 1..2 entirely.
    var h = Highlight(colorSegments: @[])
    for r in 0 .. 3:
      h.colorSegments.add(
        ColorSegment(
          firstRow: r,
          firstColumn: 0,
          lastRow: r,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      )
    h.overwrite(
      ColorSegment(
        firstRow: 1,
        firstColumn: 0,
        lastRow: 2,
        lastColumn: 10,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 4
    check h.colorSegments[0].color == EditorColorPairIndex.default
    check h.colorSegments[1].color == EditorColorPairIndex.keyword
    check h.colorSegments[2].color == EditorColorPairIndex.keyword
    check h.colorSegments[3].color == EditorColorPairIndex.default

  test "Overwrite same-row column-only no overlap is preserved":
    # Two segments on row 0 — left at 0..5, right at 20..30.
    # Overwrite range 10..15 is on row 0 but doesn't intersect either.
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 5,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        ),
        ColorSegment(
          firstRow: 0,
          firstColumn: 20,
          lastRow: 0,
          lastColumn: 30,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        ),
      ]
    )
    h.overwrite(
      ColorSegment(
        firstRow: 0,
        firstColumn: 10,
        lastRow: 0,
        lastColumn: 15,
        color: EditorColorPairIndex.keyword,
        style: defaultStyle,
      )
    )
    check h.colorSegments.len == 2
    check h.colorSegments[0].lastColumn == 5
    check h.colorSegments[0].color == EditorColorPairIndex.default
    check h.colorSegments[1].firstColumn == 20
    check h.colorSegments[1].color == EditorColorPairIndex.default

suite "Highlight - Progressive Initial Highlighting":
  test "continueInitialHighlight parses remaining lines":
    # A buffer larger than InitialChunkSize (1000 lines) should be
    # partially highlighted on load and completed via continueInitialHighlight.
    var buf = newTextBuffer()

    # Create a temp file with 2500 lines of Rust code
    let path = getTempDir() / "test_progressive_highlight.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 2500:
      content.add("let v" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    # After loadFile, only first 1000 lines should be parsed
    check buf.incrementalHighlight != nil
    check buf.incrementalHighlight.parsedUpTo == 999
    check buf.incrementalHighlight.lineStates.states.len == 1000

    # First call should parse next 1000 lines (1000..1999)
    check buf.continueInitialHighlight() == true
    check buf.incrementalHighlight.parsedUpTo == 1999

    # Second call should parse remaining 500 lines (2000..2499)
    check buf.continueInitialHighlight() == true
    check buf.incrementalHighlight.parsedUpTo == 2499

    # Third call should return false (complete)
    check buf.continueInitialHighlight() == false

  test "continueInitialHighlight hands CDATA state across the chunk boundary":
    # A CDATA section spanning the InitialChunkSize (1000 lines) boundary:
    # the initial chunk ends mid-CDATA and `continueInitialHighlight` must
    # resume from the carried `gtCData` state instead of re-tokenizing the
    # rest as markup. The fuzz corpus can never reach this boundary, so it
    # is pinned here deterministically.
    var buf = newTextBuffer()

    let path = getTempDir() / "moe_test_progressive_cdata.xml"
    defer:
      removeFile(path)
    var
      content = ""
      lines: seq[string]
    for i in 0 ..< 1100:
      let line =
        if i == 990:
          "<![CDATA["
        elif i == 1010:
          "]]>"
        else:
          "<item id=\"" & $i & "\"/>"
      lines.add(line)
      content.add(line & "\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    check buf.language == SourceLanguage.langXml
    check buf.incrementalHighlight.parsedUpTo == 999

    # Complete the progressive parse (lines 1000..1099).
    check buf.continueInitialHighlight() == true
    check buf.continueInitialHighlight() == false

    # Compare against a full one-shot parse. Whitespace columns are exempt
    # for the same reason as in the incremental fuzz: tokenizers may differ
    # on which adjacent token absorbs spaces, with no visible effect.
    var runes: seq[Runes]
    for line in lines:
      runes.add(line.toRunes)
    let full = initHighlight(runes, @[], SourceLanguage.langXml)

    var firstMismatch = (row: -1, col: -1)
    block compare:
      for row in 0 ..< lines.len:
        for col in 0 ..< lines[row].len: # ASCII-only: byte cols == rune cols
          if lines[row][col] in {' ', '\t'}:
            continue
          if buf.highlight.getColorPair(row, col) != full.getColorPair(row, col):
            firstMismatch = (row: row, col: col)
            break compare
    check firstMismatch == (row: -1, col: -1)

suite "Highlight - URI Underline on Load":
  test "loadFile applies URI underlines in initial chunk":
    var buf = newTextBuffer()

    let path = getTempDir() / "test_uri_highlight_initial.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 10:
      if i == 5:
        content.add("// see https://example.com/docs\n")
      else:
        content.add("let v" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    # Line 5 contains a URI; it should have Underline modifier
    let uriCol = "// see ".len
    let mods = buf.highlight.getSegmentModifiers(5, uriCol)
    check Underline in mods

  test "loadFile applies URI underlines for plain text":
    var buf = newTextBuffer()

    let path = getTempDir() / "test_uri_highlight_plain.txt"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 10:
      if i == 3:
        content.add("visit https://example.com/page\n")
      else:
        content.add("plain line " & $i & "\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    let uriCol = "visit ".len
    let mods = buf.highlight.getSegmentModifiers(3, uriCol)
    check Underline in mods

  test "continueUriScan applies URI underlines in later chunks":
    var buf = newTextBuffer()

    # Create file with URI beyond line 1000
    let path = getTempDir() / "test_uri_highlight_progressive.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 1500:
      if i == 1200:
        content.add("// see https://example.com/api\n")
      else:
        content.add("let v" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    # After loadFile, only first 1000 lines are scanned for URIs
    check buf.uriScanParsedUpTo == 999

    # Continue syntax highlighting first (creates color segments for lines 1000+)
    check buf.continueInitialHighlight() == true

    # Continue URI scanning - should cover line 1200 and apply URI underline
    check buf.continueUriScan() == true
    check buf.uriScanParsedUpTo == 1499

    let uriCol = "// see ".len
    let mods = buf.highlight.getSegmentModifiers(1200, uriCol)
    check Underline in mods

  test "continueUriScan applies URI underlines for plain text beyond 1000 lines":
    var buf = newTextBuffer()

    # Create plain text file with URI beyond line 1000
    let path = getTempDir() / "test_uri_highlight_plain_progressive.txt"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 1500:
      if i == 1200:
        content.add("visit https://example.com/page\n")
      else:
        content.add("plain line " & $i & "\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    # After loadFile, only first 1000 lines are scanned for URIs
    check buf.uriScanParsedUpTo == 999
    check buf.incrementalHighlight == nil # no syntax highlight for plain text

    # Continue URI scanning - should cover line 1200
    check buf.continueUriScan() == true
    check buf.uriScanParsedUpTo == 1499

    let uriCol = "visit ".len
    let mods = buf.highlight.getSegmentModifiers(1200, uriCol)
    check Underline in mods

  test "URI underlines survive incremental updateHighlight outside re-parse region":
    var buf = newTextBuffer()

    # Create file with URIs at line 5 and line 1500
    let path = getTempDir() / "test_uri_restore_before_edit.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 2000:
      if i == 5:
        content.add("// https://early.example.com\n")
      elif i == 1500:
        content.add("// https://late.example.com\n")
      else:
        content.add("let x = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    # Complete initial highlighting and URI scan
    while buf.continueInitialHighlight():
      discard
    while buf.uriScanParsedUpTo < buf.len - 1:
      discard buf.continueUriScan()

    # Verify both URIs have underlines
    let earlyCol = "// ".len
    check Underline in buf.highlight.getSegmentModifiers(5, earlyCol)
    check Underline in buf.highlight.getSegmentModifiers(1500, earlyCol)

    # Edit at line 500 — triggers incremental update around that line
    buf.lastChangedLines = 500
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()

    # URI modifiers outside the incremental re-parse region must survive —
    # they are persisted in incrementalHighlight.segments, not rebuilt from
    # scratch on every edit.
    check Underline in buf.highlight.getSegmentModifiers(5, earlyCol)
    check Underline in buf.highlight.getSegmentModifiers(1500, earlyCol)

    # Progressive scan should not need to rewind to the start of the file;
    # only the region around the change point is re-scanned.
    check buf.uriScanParsedUpTo >= 400

  test "continueUriScan returns false when no URIs found in chunk":
    var buf = newTextBuffer()

    # Create file with no URIs, 1500 lines
    let path = getTempDir() / "test_uri_scan_no_uri.rs"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 1500:
      content.add("let x = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)

    # Complete initial highlighting
    while buf.continueInitialHighlight():
      discard

    # URI scan should return false (no URIs found despite scanning)
    check buf.continueUriScan() == false

  test "updateHighlight applies URI underlines after edit":
    var buf = newTextBuffer()

    let path = getTempDir() / "test_uri_highlight_update.rs"
    defer:
      removeFile(path)
    var content = "let x = 1;\nlet y = 2;\nlet z = 3;\n"
    writeFile(path, content)
    discard buf.loadFile(path)

    # Edit line 1 to contain a URI
    discard buf.beginTransaction()
    discard buf.deleteLine(1)
    discard buf.insert(1, "// https://example.com")
    discard buf.commitTransaction()

    buf.updateHighlight()

    let uriCol = "// ".len
    let mods = buf.highlight.getSegmentModifiers(1, uriCol)
    check Underline in mods

suite "Highlight - Markdown Incremental":
  # Regression coverage for multi-line Markdown constructs whose highlighting
  # used to break after an edit because their state was not preserved across
  # line boundaries during incremental re-parsing.
  test "edit inside frontmatter keeps following lines highlighted":
    # The reported bug: editing a line after `---` broke the highlight of the
    # rest of the frontmatter block (and everything below it).
    var buffer = @[
      "---", "title: Hello", "author: Me", "date: 2024", "tags: a", "---", "",
      "# Heading", "body text",
    ]
    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langMarkdown
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

    # Edit a line in the middle of the frontmatter block.
    buffer[4] = "tags: ab"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      @[],
      SourceLanguage.langMarkdown,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

  test "edit after a thematic-break --- keeps lines highlighted":
    var buffer =
      @["# Title", "", "para one", "---", "para two", "more text", "even more"]
    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langMarkdown
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

    buffer[5] = "more text edited"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      5,
      @[],
      SourceLanguage.langMarkdown,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

  test "edit a second indented code line does not crash":
    # Previously asserted with "produced an empty token (indented code)".
    var buffer = @["text", "", "    code line one", "    code line two", "", "more"]
    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langMarkdown
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    buffer[3] = "    code line TWO"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      3,
      @[],
      SourceLanguage.langMarkdown,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

  test "edit far below an unclosed inline backtick":
    var buffer =
      @["a `code here", "line 1", "line 2", "line 3", "line 4", "line 5", "line 6"]
    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langMarkdown
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    buffer[5] = "line FIVE"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      5,
      @[],
      SourceLanguage.langMarkdown,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

  test "edit inside fenced code block with language keeps nested highlight":
    var buffer = @["# test", "", "```nim", "import std/io", "", "proc hello() =", "```"]
    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langMarkdown
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

    buffer[3] = "import std/strutils"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      3,
      @[],
      SourceLanguage.langMarkdown,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

  test "reparse from multi-line string inside fenced code block with backtick line":
    var buffer = @["```nim", "let x = \"\"\"", "```", "\"\"\"", "```"]
    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langMarkdown
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

    buffer[2] = "````"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      2,
      @[],
      SourceLanguage.langMarkdown,
    )
    checkMatchesFullParse(buffer, ih, SourceLanguage.langMarkdown)

suite "Highlight - Markdown isCodeBlockLine during multi-frame flight":
  test "line-count-changing edit trims stale line states past the flight frontier":
    # Regression: during a multi-frame flight after a line-count change,
    # rows past the frontier still held pre-edit tokenizer states bound to
    # now-shifted rows, so `isCodeBlockLine` returned the pre-edit answer
    # for a different row. The fresh flight must trim the tail states so
    # render-side consumers fall back to the safe default until
    # `refreshStateCache` refills.
    var content = ""
    for i in 0 ..< 100:
      content.add("intro line " & $i & "\n")
    content.add("```nim\n")
    for i in 0 ..< 50:
      content.add("let x" & $i & " = " & $i & "\n")
    content.add("```\n")
    for i in 0 ..< 200:
      content.add("outro line " & $i & "\n")
    let buf = newTextBuffer(content)
    buf.language = SourceLanguage.langMarkdown
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()
    check buf.isCodeBlockLine(100) # opening fence
    check buf.isCodeBlockLine(120) # interior
    check not buf.isCodeBlockLine(200) # outro

    # Insert a line at the top so rows shift by 1: the fence moves to
    # rows 101-151. A tiny per-call budget stalls the flight before it
    # refills the fence region's states.
    discard buf.insert(0, "new line")
    check buf.updateHighlight(5)
    check buf.incrementalHighlight.pendingReparse != nil

    # Post-edit row 100 is the old row 99 (regular text). Before the fix,
    # the stale states[99]/[100] carried the pre-edit fence boundary
    # (false OR true = true), a wrong "true". With the trim, the states
    # array is shorter than the query row, so the safe default (false)
    # is returned.
    check not buf.isCodeBlockLine(100)

  test "gap between load frontier and band flight fills with default state":
    # Pin the gap semantics: a flight that starts above the load's frontier
    # leaves rows [parsedUpTo+1, reparseStart) as default TokenizerState()
    # after completion. Consumers of per-language state must gate on
    # `parsedUpTo` for rows in that band; the invariant is fragile, so this
    # test locks it.
    let path = getTempDir() / "moe_test_gap_state_invariant.md"
    defer:
      removeFile(path)
    var content = ""
    for i in 0 ..< 100:
      content.add("intro line " & $i & "\n")
    content.add("```nim\n")
    for i in 0 ..< 50:
      content.add("let x" & $i & " = " & $i & "\n")
    content.add("```\n")
    for i in 0 ..< 3000:
      content.add("outro line " & $i & "\n")
    writeFile(path, content)
    var buf = newTextBuffer()
    discard buf.loadFile(path)
    # loadFile parses only the initial chunk; leave the rest unloaded.
    check buf.incrementalHighlight.parsedUpTo < buf.len - 1
    let loadFrontier = buf.incrementalHighlight.parsedUpTo

    # Edit far below the load frontier — the flight starts well past it.
    discard buf.beginTransaction()
    discard buf.insert(2500, "outro edit")
    discard buf.commitTransaction()
    while buf.updateHighlight(200):
      discard
    while buf.continueIncrementalHighlight(200):
      discard
    check buf.incrementalHighlight.pendingReparse == nil

    # parsedUpTo did NOT advance: the flight started above it, so the gap
    # [loadFrontier+1, reparseStart) was never covered by the load.
    check buf.incrementalHighlight.parsedUpTo == loadFrontier

    # A gap row's state is the default — pinned to catch a silent change
    # in the cache semantics; consumers of per-language state fields must
    # gate on `parsedUpTo` for rows in this band.
    let gapRow = loadFrontier + 100
    let states = buf.incrementalHighlight.lineStates.states
    check gapRow < states.len
    check states[gapRow] == TokenizerState()
    # And the current Markdown consumer keeps returning the safe default.
    check not buf.isCodeBlockLine(gapRow)

suite "Highlight - updateHighlight cache reuse":
  test "empty-line buffer reuses the incremental cache on re-edit":
    # All-blank buffer: `segments` stays empty but `lineStates` is populated.
    # Cache must be reused on the next edit, not rebuilt.
    var buf = newTextBuffer("\n\n")
    buf.language = SourceLanguage.langNim
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()

    check buf.incrementalHighlight != nil
    check buf.incrementalHighlight.segments.len == 0
    check buf.incrementalHighlight.lineStates.states.len == buf.len

    let cached = buf.incrementalHighlight
    buf.markLineChanged(0)
    buf.updateHighlight()

    check buf.incrementalHighlight == cached

suite "Highlight - line-length cap (synmaxcol)":
  test "buildBufferStrCapped truncates long lines and emits a default tail":
    let lines = @["short", "a".repeat(50)]
    let (str, tails) = buildBufferStrCapped(lines, 0, 1, 10)
    # First line untouched; second truncated to 10 runes.
    check str == "short\n" & "a".repeat(10)
    check tails.len == 1
    check tails[0].firstRow == 1
    check tails[0].lastRow == 1
    check tails[0].firstColumn == 10
    check tails[0].color == EditorColorPairIndex.default

  test "buildBufferStrCapped with cap 0 disables capping (no truncation, no tails)":
    let lines = @["x".repeat(5000), "y"]
    let (str, tails) = buildBufferStrCapped(lines, 0, 1, 0)
    check tails.len == 0
    check str == lines.join("\n") # full lines joined, nothing dropped

  test "cap counts runes, not bytes":
    # 5 multibyte runes = 15 bytes, under a 10-rune cap → not truncated.
    let lines = @["あ".repeat(5)]
    let (str, tails) = buildBufferStrCapped(lines, 0, 0, 10)
    check tails.len == 0
    check str == lines[0]
    # 20 runes (60 bytes) over the 10-rune cap → truncated to exactly 10 runes.
    let lines2 = @["あ".repeat(20)]
    let (str2, tails2) = buildBufferStrCapped(lines2, 0, 0, 10)
    check tails2.len == 1
    check tails2[0].firstColumn == 10
    check str2.runeLen == 10

  test "line with exactly cap runes (multibyte, byteLen > cap) is not truncated":
    # 10 multibyte runes = 30 bytes: byteLen (30) > cap (10) so the rune scan
    # runs, but runeLen (10) == cap, so the line must be kept whole with no tail.
    # Guards the boundary where a naive runeOffset(s, cap) would report -1.
    let lines = @["あ".repeat(10)]
    let (str, tails) = buildBufferStrCapped(lines, 0, 0, 10)
    check tails.len == 0
    check str == lines[0]

  test "absurdly large cap does not overflow the capacity hint":
    # maxLineLen * 4 would overflow int for a near-high(int) cap; the saturating
    # hint must keep newStringOfCap non-negative and leave the line untruncated.
    let lines = @["x".repeat(5000)]
    let (str, tails) = buildBufferStrCapped(lines, 0, 0, high(int))
    check tails.len == 0
    check str == lines[0]

  test "capped line: prefix highlighted, remainder rendered as default":
    let lines = @["# " & "a".repeat(50)] # Nim line comment, 52 chars
    let (segments, _) = initHighlightIncremental(
      lines, 0, 0, TokenizerState(), @[], SourceLanguage.langNim, 10
    )
    let hl = Highlight(colorSegments: segments)
    check hl.getColorPair(0, 0) == EditorColorPairIndex.comment # within cap
    check hl.getColorPair(0, 5) == EditorColorPairIndex.comment
    check hl.getColorPair(0, 25) == EditorColorPairIndex.default # past cap

  test "cap 0 leaves the whole long line highlighted":
    let lines = @["# " & "a".repeat(50)]
    let (segments, _) = initHighlightIncremental(
      lines, 0, 0, TokenizerState(), @[], SourceLanguage.langNim, 0
    )
    let hl = Highlight(colorSegments: segments)
    check hl.getColorPair(0, 40) == EditorColorPairIndex.comment

  test "multi-line state continues across a capped line":
    # A block comment opens within the cap on a long line; the boundary state
    # captured at the cap must carry the open construct so the next line stays
    # colored as a long comment.
    let lines = @["#[ " & "a".repeat(50), "x"]
    let (segments, _) = initHighlightIncremental(
      lines, 0, 1, TokenizerState(), @[], SourceLanguage.langNim, 10
    )
    let hl = Highlight(colorSegments: segments)
    check hl.getColorPair(0, 1) == EditorColorPairIndex.longComment # '[' of #[
    check hl.getColorPair(0, 5) == EditorColorPairIndex.longComment # within cap
    check hl.getColorPair(1, 0) == EditorColorPairIndex.longComment # continued

  test "incremental update stays consistent with a full capped parse":
    const cap = 10
    var buffer = @["# " & "a".repeat(40), "let x = 1", "let y = 2"]
    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim, cap
    )
    var ih =
      IncrementalHighlight(segments: seg0, lineStates: LineStateCache(states: ls0))
    # Edit a non-capped line; the capped line above must remain consistent.
    buffer[1] = "let x = 100"
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      1,
      @[],
      SourceLanguage.langNim,
      cap,
    )
    let (segFull, _) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim, cap
    )
    let incrHl = Highlight(colorSegments: ih.segments)
    let fullHl = Highlight(colorSegments: segFull)
    for row in 0 ..< buffer.len:
      for col in 0 ..< buffer[row].len:
        check incrHl.getColorPair(row, col) == fullHl.getColorPair(row, col)

  test "newTextBuffer defaults the cap and updateHighlight honors it":
    var buf = newTextBuffer("# " & "a".repeat(50))
    check buf.maxHighlightLineLength == DefaultMaxHighlightLineLength
    buf.language = SourceLanguage.langNim
    buf.setMaxHighlightLineLength(10)
    buf.updateHighlight()
    check buf.highlight.getColorPair(0, 0) == EditorColorPairIndex.comment
    check buf.highlight.getColorPair(0, 30) == EditorColorPairIndex.default

  test "loadFile honors the cap on the synchronous initial highlight":
    # Regression: buffer/file_io.loadFile builds the first-chunk highlight
    # directly and must pass maxHighlightLineLength, or a long line in the
    # first chunk is tokenized uncapped on every open/reload (the on-load
    # stall the cap exists to prevent).
    let path = getTempDir() / "moe_test_highlight_cap_load.nim"
    defer:
      removeFile(path)
    writeFile(path, "# " & "a".repeat(50) & "\n")
    var buf = newTextBuffer("")
    buf.setMaxHighlightLineLength(10)
    check buf.loadFile(path).isOk
    check buf.language == SourceLanguage.langNim
    # Built at load time (no updateHighlight call): within the cap stays a
    # comment, past the cap renders as default — proving the load path capped.
    check buf.highlight.getColorPair(0, 0) == EditorColorPairIndex.comment
    check buf.highlight.getColorPair(0, 30) == EditorColorPairIndex.default

  test "setMaxHighlightLineLength rebuild honors the frame budget":
    # Regression: the rebuild path (cache invalid) used to parse the whole
    # buffer in one call, ignoring the budget. It must chunk under a
    # non-zero budget; unlimited (0) keeps the synchronous rebuild.
    var content = ""
    for i in 0 ..< 3000:
      content.add("let v" & $i & " = " & $i & ";\n")
    var buf = newTextBuffer(content)
    buf.language = SourceLanguage.langRust
    buf.highlightNeedsUpdate = true
    buf.updateHighlight() # unlimited: prime the cache
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1

    buf.setMaxHighlightLineLength(80) # drops cache, sets highlightNeedsUpdate
    check buf.incrementalHighlight == nil
    discard buf.updateHighlight(1000)
    # First frame parses only one chunk instead of the whole file.
    check buf.incrementalHighlight != nil
    check buf.incrementalHighlight.parsedUpTo < buf.len - 1

    # Successive frames complete it via continueInitialHighlight.
    while buf.continueInitialHighlight(1000):
      discard
    check buf.incrementalHighlight.parsedUpTo == buf.len - 1

suite "Highlight - Semantic overlay":
  # Small legend used across the tests; index 0=variable, 1=function, 2=type.
  let legend = SemanticTokensLegend(
    tokenTypes: @["variable", "function", "type"], tokenModifiers: @[]
  )
  let colorTab = buildSemanticTypeColorTable(legend)

  proc mkResp(data: seq[int]): JsonNode =
    let arr = newJArray()
    for v in data:
      arr.add(newJInt(v))
    result = %*{"data": arr}

  test "buildSemanticTypeColorTable maps each type once":
    check colorTab.baseColors.len == 3
    check colorTab.baseColors[0] == EditorColorPairIndex.variable
    check colorTab.baseColors[1] == EditorColorPairIndex.function
    check colorTab.baseColors[2] == EditorColorPairIndex.typeName

  test "Empty data leaves an empty overlay":
    let h = Highlight(colorSegments: @[])
    let outcome = applySemanticTokens(h, mkResp(@[]), colorTab, 1)
    check outcome == saoDone
    check h.semantic.len == 0
    check h.semanticContentVersion == 1

  test "Single-row token becomes one overlay entry":
    # [deltaLine=0, deltaStart=2, len=3, type=1(function), mods=0]
    let h = Highlight(colorSegments: @[])
    let outcome = applySemanticTokens(h, mkResp(@[0, 2, 3, 1, 0]), colorTab, 5)
    check outcome == saoDone
    check h.semanticContentVersion == 5
    check h.semantic.len == 1
    check h.semantic[0].tokens.len == 1
    let t = h.semantic[0].tokens[0]
    check t.firstColumn == 2
    check t.length == 3
    check t.color == EditorColorPairIndex.function
    # Overlay wins over empty colorSegments.
    check h.getColorPair(0, 3) == EditorColorPairIndex.function
    check h.getColorPair(0, 5) == EditorColorPairIndex.default

  test "Delta encoding across rows produces separate SemanticOverlayLine":
    # Token A: line 0, col 0, len 2, type 0(variable)
    # Token B: line 2, col 4, len 3, type 2(type)
    let h = Highlight(colorSegments: @[])
    let outcome =
      applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 2, 4, 3, 2, 0]), colorTab, 1)
    check outcome == saoDone
    check h.semantic.len == 2
    check h.semantic[0].tokens[0].color == EditorColorPairIndex.variable
    check h.semantic[2].tokens[0].firstColumn == 4
    check h.semantic[2].tokens[0].color == EditorColorPairIndex.typeName
    # Row 1 has no overlay.
    check h.getColorPair(1, 0) == EditorColorPairIndex.default

  test "Overlay wins over syntax colorSegments":
    let h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 9,
          color: EditorColorPairIndex.keyword,
          style: defaultStyle,
        )
      ]
    )
    # Function token at col 2..4.
    let outcome = applySemanticTokens(h, mkResp(@[0, 2, 3, 1, 0]), colorTab, 1)
    check outcome == saoDone
    check h.getColorPair(0, 0) == EditorColorPairIndex.keyword
    check h.getColorPair(0, 3) == EditorColorPairIndex.function
    check h.getColorPair(0, 5) == EditorColorPairIndex.keyword

  test "Diagnostic overlay beats semantic overlay":
    # Regression: an earlier code path short-circuited on any semantic overlay
    # hit, so a diagnostic on a semantic-token-covered identifier stayed
    # invisible.
    let h = Highlight(colorSegments: @[])
    var diag: DiagnosticOverlayLine
    diag.cells.add(
      DiagnosticOverlayCell(
        firstColumn: 0,
        lastColumn: 9,
        color: EditorColorPairIndex.syntaxCheckErr,
        style: Style(modifiers: {StyleModifier.Undercurl}),
      )
    )
    h.diagnosticOverlay[0] = diag
    let outcome = applySemanticTokens(h, mkResp(@[0, 2, 3, 1, 0]), colorTab, 1)
    check outcome == saoDone
    check h.getColorPair(0, 3) == EditorColorPairIndex.syntaxCheckErr
    check h.getSegmentModifiers(0, 3) == {StyleModifier.Undercurl}

  test "getSegmentModifiers unions overlay + syntax modifiers":
    # Syntax segment has Undercurl (e.g. diagnostic); overlay carries Bold.
    var h = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 9,
          color: EditorColorPairIndex.default,
          style: Style(modifiers: {StyleModifier.Undercurl}),
        )
      ]
    )
    var line: SemanticOverlayLine
    line.tokens.add(
      SemanticOverlayToken(
        firstColumn: 2,
        length: 3,
        color: EditorColorPairIndex.function,
        style: Style(modifiers: {StyleModifier.Bold}),
      )
    )
    h.semantic[0] = line
    # Position under the overlay: colour switches, both modifiers survive.
    check h.getColorPair(0, 3) == EditorColorPairIndex.function
    check h.getSegmentModifiers(0, 3) == {StyleModifier.Undercurl, StyleModifier.Bold}
    # Outside the overlay: syntax only.
    check h.getColorPair(0, 6) == EditorColorPairIndex.default
    check h.getSegmentModifiers(0, 6) == {StyleModifier.Undercurl}

  test "Malformed data.len (not multiple of 5) is rejected":
    let h = Highlight(colorSegments: @[])
    h.semantic[0] = SemanticOverlayLine(tokens: @[])
    let outcome = applySemanticTokens(h, mkResp(@[0, 1, 2, 0]), colorTab, 1)
    check outcome == saoRejectedMalformed

  test "Out-of-range deltaLine/deltaStart/length are rejected (no OverflowDefect)":
    let h = Highlight(colorSegments: @[])
    let over = int(high(uint32)) + 1
    check applySemanticTokens(h, mkResp(@[over, 0, 3, 0, 0]), colorTab, 1) ==
      saoRejectedMalformed
    check applySemanticTokens(h, mkResp(@[0, over, 3, 0, 0]), colorTab, 1) ==
      saoRejectedMalformed
    check applySemanticTokens(h, mkResp(@[0, 0, over, 0, 0]), colorTab, 1) ==
      saoRejectedMalformed
    check applySemanticTokens(h, mkResp(@[0, 0, -1, 0, 0]), colorTab, 1) ==
      saoRejectedMalformed

  test "Response above MaxSemanticTokens cap is rejected without decoding":
    let h = Highlight(colorSegments: @[])
    # Craft an over-cap response cheaply: length = cap*5 + 5.
    let overCap = newSeq[int](MaxSemanticTokens * 5 + 5)
    let outcome = applySemanticTokens(h, mkResp(overCap), colorTab, 1)
    check outcome == saoRejectedCap
    # Overlay remains empty; version stays at the "no overlay applied yet"
    # sentinel (-1), distinct from a legitimate contentVersion of 0.
    check h.semantic.len == 0
    check h.semanticContentVersion == -1

  test "Second apply replaces the whole overlay":
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 0, 3, 0, 0]), colorTab, 1)
    check h.semantic.len == 1
    # Second response has one token on a different line.
    discard applySemanticTokens(h, mkResp(@[3, 0, 2, 1, 0]), colorTab, 2)
    check h.semantic.len == 1
    check 3 in h.semantic
    check 0 notin h.semantic

  test "Overlay in sync with contentVersion survives incremental reparse":
    # An LSP response applied at the current buffer.contentVersion must not be
    # wiped by a reparse that is not triggered by a real edit.
    var buf = newTextBuffer("let x = 1\nlet y = 2\n")
    buf.language = SourceLanguage.langNim
    buf.updateHighlight()
    check buf.highlight != nil
    let outcome = applySemanticTokens(
      buf.highlight, mkResp(@[0, 4, 1, 1, 0]), colorTab, buf.contentVersion
    )
    check outcome == saoDone
    check buf.highlight.getColorPair(0, 4) == EditorColorPairIndex.function

    # Reparse without an edit: contentVersion unchanged, overlay survives.
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()
    check buf.highlight.semantic.len == 1
    check buf.highlight.getColorPair(0, 4) == EditorColorPairIndex.function

  test "Forward edit preserves overlay via the extmark shift (design doc §6)":
    # Design doc §6: stale-but-close colouring beats flicker on every keystroke.
    # `pushUndoChange` calls `emitRowColRemapEvents`, which advances
    # `semanticContentVersion` so `updateHighlight`'s fallback clear stays quiet
    # for rows untouched by the edit.
    var buf = newTextBuffer("let x = 1\nlet y = 2\n")
    buf.language = SourceLanguage.langNim
    buf.updateHighlight()
    discard applySemanticTokens(
      buf.highlight, mkResp(@[0, 4, 1, 1, 0]), colorTab, buf.contentVersion
    )
    check buf.highlight.semantic.len == 1
    # Edit on row 1 (col 0) leaves row 0's token untouched.
    check buf.insertText(BufferPosition(line: 1, column: 0), "z").isOk
    buf.updateHighlight()
    check buf.highlight.semantic.len == 1
    check buf.highlight.getColorPair(0, 4) == EditorColorPairIndex.function
    check buf.highlight.semanticContentVersion == buf.contentVersion

  test "Undo triggers the safety-net clear (no extmark inversion)":
    # Undo/redo bypass `pushUndoChange`, so the safety net in
    # `buffer/highlight.updateHighlight` still clears the overlay on version
    # mismatch — this is intentional: undo can reshuffle many lines.
    var buf = newTextBuffer("let x = 1\nlet y = 2\n")
    buf.language = SourceLanguage.langNim
    buf.updateHighlight()
    # Prime an edit so there's something to undo.
    check buf.insertText(BufferPosition(line: 0, column: 0), "a").isOk
    discard applySemanticTokens(
      buf.highlight, mkResp(@[0, 4, 1, 1, 0]), colorTab, buf.contentVersion
    )
    check buf.highlight.semantic.len == 1
    check buf.undo().isOk
    buf.updateHighlight()
    check buf.highlight.semantic.len == 0
    check buf.highlight.getColorPair(0, 4) != EditorColorPairIndex.function

  test "loadFile clears any prior overlay":
    var buf = newTextBuffer("let x = 1\n")
    buf.language = SourceLanguage.langNim
    buf.updateHighlight()
    discard applySemanticTokens(buf.highlight, mkResp(@[0, 4, 1, 1, 0]), colorTab, 7)
    check buf.highlight.semantic.len == 1

    let path = getTempDir() / "moe_test_semantic_overlay_reload.nim"
    defer:
      removeFile(path)
    writeFile(path, "let y = 2\n")
    check buf.loadFile(path).isOk
    # `loadFile` replaces `b.highlight` with a fresh one; overlay is gone.
    check buf.highlight.semantic.len == 0
    check buf.highlight.getColorPair(0, 4) != EditorColorPairIndex.function

  test "Rejected apply preserves the prior overlay":
    let h = Highlight(colorSegments: @[])
    # Prime the overlay with a valid apply.
    discard applySemanticTokens(h, mkResp(@[0, 2, 3, 1, 0]), colorTab, 3)
    check h.semantic.len == 1
    let priorLen = h.semantic[0].tokens.len
    let priorColor = h.semantic[0].tokens[0].color
    let priorVersion = h.semanticContentVersion

    # Malformed response leaves the overlay untouched.
    let outcome = applySemanticTokens(h, mkResp(@[0, 1, 2, 0]), colorTab, 4)
    check outcome == saoRejectedMalformed
    check h.semantic.len == 1
    check h.semantic[0].tokens.len == priorLen
    check h.semantic[0].tokens[0].color == priorColor
    check h.semanticContentVersion == priorVersion

    # Over-cap response also leaves the overlay untouched.
    let overCap = newSeq[int](MaxSemanticTokens * 5 + 5)
    check applySemanticTokens(h, mkResp(overCap), colorTab, 5) == saoRejectedCap
    check h.semantic.len == 1
    check h.semantic[0].tokens[0].color == priorColor
    check h.semanticContentVersion == priorVersion

  test "findOverlayToken boundaries (start / end-exclusive / gap)":
    let h = Highlight(colorSegments: @[])
    # Two tokens: [2..4] variable, [6..8] function. Gap at col 5.
    discard applySemanticTokens(h, mkResp(@[0, 2, 3, 0, 0, 0, 4, 3, 1, 0]), colorTab, 1)
    check h.semantic[0].tokens.len == 2
    # Before the first token.
    check h.getColorPair(0, 0) == EditorColorPairIndex.default
    check h.getColorPair(0, 1) == EditorColorPairIndex.default
    # Exactly at token start.
    check h.getColorPair(0, 2) == EditorColorPairIndex.variable
    # Inside.
    check h.getColorPair(0, 3) == EditorColorPairIndex.variable
    # Last covered column (start + length - 1).
    check h.getColorPair(0, 4) == EditorColorPairIndex.variable
    # Gap between tokens (length is exclusive at the far end).
    check h.getColorPair(0, 5) == EditorColorPairIndex.default
    # Second token.
    check h.getColorPair(0, 6) == EditorColorPairIndex.function
    check h.getColorPair(0, 8) == EditorColorPairIndex.function
    # After all tokens.
    check h.getColorPair(0, 9) == EditorColorPairIndex.default

  test "Multiple tokens on one line stay sorted by firstColumn":
    let h = Highlight(colorSegments: @[])
    # Three in-order tokens on the same line (LSP delta encoding is monotonic).
    discard applySemanticTokens(
      h, mkResp(@[0, 0, 2, 0, 0, 0, 3, 2, 1, 0, 0, 3, 2, 2, 0]), colorTab, 1
    )
    let toks = h.semantic[0].tokens
    check toks.len == 3
    check toks[0].firstColumn < toks[1].firstColumn
    check toks[1].firstColumn < toks[2].firstColumn
    # Distinct colours in position order.
    check toks[0].color == EditorColorPairIndex.variable
    check toks[1].color == EditorColorPairIndex.function
    check toks[2].color == EditorColorPairIndex.typeName

  test "Empty legend preserves prior overlay and rejects":
    # A transiently-empty legend (mid registerCapability) must not wipe the
    # existing colouring.
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 0, 3, 0, 0]), colorTab, 1)
    check h.semantic.len == 1
    let priorVersion = h.semanticContentVersion
    let emptyTab = buildSemanticTypeColorTable(
      SemanticTokensLegend(tokenTypes: @[], tokenModifiers: @[])
    )
    let outcome = applySemanticTokens(h, mkResp(@[0, 0, 3, 0, 0]), emptyTab, 2)
    check outcome == saoRejectedNoLegend
    check h.semantic.len == 1
    check h.semanticContentVersion == priorVersion

  test "Unknown tokenType / non-positive length / default-colour type are skipped":
    let h = Highlight(colorSegments: @[])
    # Token A: tokenType=99 (out of range) — skipped.
    # Token B: length=0 — skipped.
    # Token C: tokenType=0(variable), length=2, col=6 — kept.
    # Delta encoding: A@col0 len1, B@col2 len0, C@col6 len2.
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 1, 99, 0, 0, 2, 0, 0, 0, 0, 4, 2, 0, 0]), colorTab, 1
    )
    check outcome == saoDone
    # Only C survives.
    check h.semantic.len == 1
    check h.semantic[0].tokens.len == 1
    check h.semantic[0].tokens[0].firstColumn == 6
    check h.semantic[0].tokens[0].color == EditorColorPairIndex.variable

    # A tokenType that maps to `default` colour is also skipped. Extend the
    # legend so a real (mapped) type is co-located with an unknown-name type
    # that resolves to `default`.
    let legendWithDefault = SemanticTokensLegend(
      tokenTypes: @["variable", "somethingUnknown"], tokenModifiers: @[]
    )
    let tabWithDefault = buildSemanticTypeColorTable(legendWithDefault)
    check tabWithDefault.baseColors[1] == EditorColorPairIndex.default

    let h2 = Highlight(colorSegments: @[])
    # Two tokens: type=1(default) at col 0, type=0(variable) at col 5.
    discard applySemanticTokens(
      h2, mkResp(@[0, 0, 3, 1, 0, 0, 5, 2, 0, 0]), tabWithDefault, 1
    )
    check h2.semantic.len == 1
    check h2.semantic[0].tokens.len == 1
    check h2.semantic[0].tokens[0].firstColumn == 5

  test "Multi-line token splits into per-row entries with getLineRuneCount":
    # Row 0 has 10 runes, row 1 has 8 runes, row 2 has 20 runes.
    let widths = @[10, 8, 20]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]

    let h = Highlight(colorSegments: @[])
    # length = 4 (row 0 tail) + 1\n + 8 (row 1) + 1\n + 3 (row 2 head) = 17.
    let outcome = applySemanticTokens(h, mkResp(@[0, 6, 17, 1, 0]), colorTab, 1, getLen)
    check outcome == saoDone
    # Row 0: cols 6..9 (4 runes to end of row).
    check h.semantic.len == 3
    check h.semantic[0].tokens.len == 1
    check h.semantic[0].tokens[0].firstColumn == 6
    check h.semantic[0].tokens[0].length == 4
    # Row 1: full row (0..7, 8 runes).
    check h.semantic[1].tokens[0].firstColumn == 0
    check h.semantic[1].tokens[0].length == 8
    # Row 2: 15 - 4 - 8 = 3 remaining runes at col 0.
    check h.semantic[2].tokens[0].firstColumn == 0
    check h.semantic[2].tokens[0].length == 3
    # All three carry the same colour.
    check h.semantic[0].tokens[0].color == EditorColorPairIndex.function
    check h.semantic[1].tokens[0].color == EditorColorPairIndex.function
    check h.semantic[2].tokens[0].color == EditorColorPairIndex.function

  test "Single-line tokens still work when getLineRuneCount is supplied":
    let widths = @[100]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 2, 3, 1, 0]), colorTab, 1, getLen)
    check h.semantic.len == 1
    check h.semantic[0].tokens.len == 1
    check h.semantic[0].tokens[0].firstColumn == 2
    check h.semantic[0].tokens[0].length == 3

  test "Multi-line token clipped when buffer ends mid-token":
    let widths = @[5, 3] # only 2 rows, 8 runes total starting from (0,0)
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]
    let h = Highlight(colorSegments: @[])
    # 20-rune token from (0,0) — buffer runs out at row 2.
    let outcome = applySemanticTokens(h, mkResp(@[0, 0, 20, 1, 0]), colorTab, 1, getLen)
    check outcome == saoDone
    check h.semantic.len == 2
    check h.semantic[0].tokens[0].length == 5
    check h.semantic[1].tokens[0].length == 3

  test "resolveTokenColor uses modifiers (readonly variable -> constParameter)":
    let modLegend = SemanticTokensLegend(
      tokenTypes: @["variable"], tokenModifiers: @["declaration", "readonly", "static"]
    )
    let tab = buildSemanticTypeColorTable(modLegend)
    # No modifiers: base variable colour.
    check tab.resolveTokenColor(0, 0).color == EditorColorPairIndex.variable
    # readonly bit set (bit 1 => value 2): switches to constParameter.
    check tab.resolveTokenColor(0, 2).color == EditorColorPairIndex.constParameter
    # static bit set (bit 2 => value 4): also constParameter.
    check tab.resolveTokenColor(0, 4).color == EditorColorPairIndex.constParameter
    # declaration only (bit 0 => value 1): still base variable.
    check tab.resolveTokenColor(0, 1).color == EditorColorPairIndex.variable
    # Cache hit: second call returns the same colour.
    check tab.resolveTokenColor(0, 2).color == EditorColorPairIndex.constParameter
    # `declaration` maps to Bold style modifier.
    check tab.resolveTokenColor(0, 1).style == {StyleModifier.Bold}

  test "applySemanticTokens threads modifiers through to the overlay":
    let modLegend = SemanticTokensLegend(
      tokenTypes: @["variable"], tokenModifiers: @["declaration", "readonly"]
    )
    let tab = buildSemanticTypeColorTable(modLegend)
    let h = Highlight(colorSegments: @[])
    # tokenModifiers = 2 (bit 1 = readonly)
    discard applySemanticTokens(h, mkResp(@[0, 0, 3, 0, 2]), tab, 1)
    check h.semantic.len == 1
    check h.semantic[0].tokens[0].color == EditorColorPairIndex.constParameter

  test "Empty full-doc reply clears the whole overlay":
    # Per LSP spec, {data: []} means "no tokens in this document" -- the
    # authoritative full-doc reply. Clear the overlay and adopt the reply's
    # contentVersion so ghost tokens don't linger after the server disables
    # semantic tokens or otherwise reports an empty file.
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 2, 3, 1, 0]), colorTab, 3)
    check h.semantic.len == 1
    let outcome = applySemanticTokens(h, mkResp(@[]), colorTab, 4)
    check outcome == saoDone
    check h.semantic.len == 0
    check h.semanticContentVersion == 4

  test "Non-JInt entry in data is rejected without corrupting the overlay":
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 2, 3, 1, 0]), colorTab, 1)
    let priorLen = h.semantic[0].tokens.len
    # data: [0, "bad", 3, 1, 0] — deltaStart is a JString.
    let badResp = %*{"data": [%0, %"bad", %3, %1, %0]}
    let outcome = applySemanticTokens(h, badResp, colorTab, 2)
    check outcome == saoRejectedMalformed
    check h.semantic[0].tokens.len == priorLen

  test "Multi-line token beyond 64 rows is not truncated (safety cap removed)":
    const rows = 200
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= rows: -1 else: 10
    let h = Highlight(colorSegments: @[])
    # length: 10 runes per row + 1 UTF-16 per row boundary (newline).
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 10 * rows + (rows - 1), 1, 0]), colorTab, 1, getLen
    )
    check outcome == saoDone
    check h.semantic.len == rows
    check h.semantic[rows - 1].tokens[0].length == 10

  test "Full-doc pathological length is bounded by MaxSemanticTokenRowSpan":
    # Guards against a buggy server sending length=2^31 in a full-doc reply:
    # without a per-token row-span cap the splitter would walk every row of
    # the buffer (500k+) in one frame.
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      # Unbounded synthetic buffer: every row has 1 rune.
      1
    let h = Highlight(colorSegments: @[])
    # length far exceeds MaxSemanticTokenRowSpan; splitter must stop.
    let outcome =
      applySemanticTokens(h, mkResp(@[0, 0, 1_000_000, 1, 0]), colorTab, 1, getLen)
    check outcome == saoDone
    # start row + up to MaxSemanticTokenRowSpan wrap rows.
    check h.semantic.len <= MaxSemanticTokenRowSpan + 1
    check h.semantic.len >= 2 # at least the wrap loop ran

  test "Stale-position multi-line token whose start is past EOL is dropped":
    let widths = @[3, 10]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]
    let h = Highlight(colorSegments: @[])
    let outcome = applySemanticTokens(h, mkResp(@[0, 5, 4, 1, 0]), colorTab, 1, getLen)
    check outcome == saoDone
    check h.semantic.len == 0

  test "Negative modBitmask returns default without poisoning the cache":
    # Negative bitmasks are spec violations. resolveTokenColor bails to
    # `default` (rather than folding into the zero-modifier base colour) and
    # never touches the modifier cache so a subsequent legitimate call still
    # resolves. Production callers (applySemanticTokens) reject the whole
    # response before this fallback fires; this exercises the direct API.
    let modLegend = SemanticTokensLegend(
      tokenTypes: @["variable"], tokenModifiers: @["declaration", "readonly"]
    )
    let tab = buildSemanticTypeColorTable(modLegend)
    check tab.resolveTokenColor(0, -1).color == EditorColorPairIndex.default
    check tab.resolveTokenColor(0, -1 shl 5).color == EditorColorPairIndex.default
    # Cache was not poisoned: a subsequent legitimate call still resolves.
    check tab.resolveTokenColor(0, 2).color == EditorColorPairIndex.constParameter

  test "Range-scoped apply preserves overlay entries outside the range":
    let h = Highlight(colorSegments: @[])
    # Prime rows 0 and 5 with a full-document apply.
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 5, 0, 3, 1, 0]), colorTab, 1)
    check h.semantic.len == 2
    check 0 in h.semantic
    check 5 in h.semantic
    # Range reply for rows 4..6 with a new token on row 5.
    let outcome =
      applySemanticTokens(h, mkResp(@[5, 0, 2, 2, 0]), colorTab, 2, nil, 4, 6)
    check outcome == saoDone
    # Row 0 (outside range) is preserved; row 5 is replaced.
    check 0 in h.semantic
    check h.semantic[0].tokens[0].color == EditorColorPairIndex.variable
    check 5 in h.semantic
    check h.semantic[5].tokens[0].color == EditorColorPairIndex.typeName

  test "Range-scoped empty reply clears the range but preserves outside rows":
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 5, 0, 3, 1, 0]), colorTab, 1)
    discard applySemanticTokens(h, mkResp(@[]), colorTab, 2, nil, 4, 6)
    check 0 in h.semantic
    check 5 notin h.semantic

  test "Full-document empty reply clears the whole overlay":
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 2, 3, 1, 0]), colorTab, 1)
    check h.semantic.len == 1
    discard applySemanticTokens(h, mkResp(@[]), colorTab, 2)
    check h.semantic.len == 0
    check h.semanticContentVersion == 2

  test "SemanticTypeColorTable retains its legend for invalidation checks":
    # LspIntegration.getSemanticTypeColorTable compares `cached.legend` to the
    # current server legend and rebuilds on mismatch. Guard that field.
    let legA = SemanticTokensLegend(tokenTypes: @["variable"], tokenModifiers: @[])
    let legB = SemanticTokensLegend(tokenTypes: @["function"], tokenModifiers: @[])
    let tabA = buildSemanticTypeColorTable(legA)
    check tabA.legend == legA
    check tabA.legend != legB

  test "In-flight edit race: apply with request-time version drops on next reparse":
    # Simulates the real caller race: user edits BEFORE the response arrives.
    # processSemanticTokensResponse must stamp with the REQUEST-time contentVersion
    # (captured when the request was sent) so updateHighlight's stale-drop fires
    # once buffer.contentVersion has advanced past that stamp. Passing the
    # response-time contentVersion instead would falsely mark the overlay fresh
    # and leave wrong-position colours until the next edit or response.
    var buf = newTextBuffer("let x = 1\nlet y = 2\n")
    buf.language = SourceLanguage.langNim
    buf.updateHighlight()
    let requestVersion = buf.contentVersion
    # Edit BEFORE the apply — simulates the buffer advancing while the LSP
    # request is in flight.
    check buf.insertText(BufferPosition(line: 1, column: 0), "z").isOk
    check buf.contentVersion > requestVersion
    # Apply with the OLDER (request-time) version, as the fixed caller does.
    let outcome = applySemanticTokens(
      buf.highlight, mkResp(@[0, 4, 1, 1, 0]), colorTab, requestVersion
    )
    check outcome == saoDone
    # Overlay is present but stamped with the older version.
    check buf.highlight.semantic.len == 1
    check buf.highlight.semanticContentVersion == requestVersion
    # updateHighlight's stale-drop fires because semanticContentVersion !=
    # buf.contentVersion, closing the visible-frame gap.
    buf.updateHighlight()
    check buf.highlight.semantic.len == 0

  test "Multi-line token starting exactly at EOL is dropped (F3)":
    # Guard is `>=` so a token whose start equals firstRowLen never enters the
    # split loop. The old `>` guard would push the token onto row+1 with a
    # wrong colour.
    let widths = @[5, 10]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]
    let h = Highlight(colorSegments: @[])
    # Token starts at (row=0, col=5) with length=4. col == firstRowLen(5).
    let outcome = applySemanticTokens(h, mkResp(@[0, 5, 4, 1, 0]), colorTab, 1, getLen)
    check outcome == saoDone
    # Neither row 0 nor row 1 should carry this token.
    check h.semantic.len == 0

  test "Multi-line splitter terminates on empty rows (F3 safety)":
    # A 10-rune buffer where every row is empty. A malformed token from a
    # buggy server (length=100 starting at row 0 col 0) must not iterate the
    # whole buffer at availOnRow=0 per row.
    const rows = 500
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= rows: -1 else: 0
    let h = Highlight(colorSegments: @[])
    # Empty first row: EOL guard drops the token (currentChar 0 >= firstRowLen 0).
    let outcome =
      applySemanticTokens(h, mkResp(@[0, 0, 100, 1, 0]), colorTab, 1, getLen)
    check outcome == saoDone
    check h.semantic.len == 0

  test "Negative deltaLine is rejected as malformed (F8)":
    let h = Highlight(colorSegments: @[])
    let outcome = applySemanticTokens(h, mkResp(@[-1, 0, 2, 1, 0]), colorTab, 1)
    check outcome == saoRejectedMalformed

  test "Negative deltaStart is rejected as malformed (F8)":
    let h = Highlight(colorSegments: @[])
    let outcome = applySemanticTokens(h, mkResp(@[0, -1, 2, 1, 0]), colorTab, 1)
    check outcome == saoRejectedMalformed

  test "Range apply preserves older semanticContentVersion when outside rows retained (F5)":
    # Prior full-doc apply populated rows 0 and 5 at version=5. A later range
    # apply for rows 4..6 at version=7 leaves row 0 in place; its coords are
    # still for version 5, so the OVERALL overlay is only as fresh as row 0.
    # Stamping the newer 7 would defeat updateHighlight's stale-drop on the
    # next edit.
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 5, 0, 3, 1, 0]), colorTab, 5)
    check h.semantic.len == 2
    check h.semanticContentVersion == 5
    # Range reply for rows 4..6 with a new token on row 5.
    let outcome =
      applySemanticTokens(h, mkResp(@[5, 0, 2, 2, 0]), colorTab, 7, nil, 4, 6)
    check outcome == saoDone
    check 0 in h.semantic
    check 5 in h.semantic
    # Stamp stays at 5 (the age of the surviving outside-range row).
    check h.semanticContentVersion == 5

  test "Range apply adopts new version when overlay had no outside rows (F5)":
    # No prior outside rows -> the range apply's rows are the only rows;
    # they're fresh at the new version, so the stamp advances.
    let h = Highlight(colorSegments: @[])
    let outcome =
      applySemanticTokens(h, mkResp(@[5, 0, 2, 2, 0]), colorTab, 7, nil, 4, 6)
    check outcome == saoDone
    check h.semantic.len == 1
    check h.semanticContentVersion == 7

  test "Empty range reply preserves stamp when outside rows retained (F5)":
    # Full-doc apply populates rows 0 and 5 at version=5.
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 5, 0, 3, 1, 0]), colorTab, 5)
    check h.semanticContentVersion == 5
    # Empty range reply for rows 4..6 clears row 5 but preserves row 0.
    let outcome = applySemanticTokens(h, mkResp(@[]), colorTab, 8, nil, 4, 6)
    check outcome == saoDone
    check 0 in h.semantic
    check 5 notin h.semantic
    # Stamp stays at 5 because row 0 (older data) still lives here.
    check h.semanticContentVersion == 5

  test "Multi-line unroll + overlapping single-line token stays disjoint":
    # A spec-noncompliant server (or a moe wrap that collides with a real
    # single-line token further along the same row) can produce two tokens
    # on the same row that overlap. `addOverlayToken` must truncate the
    # earlier one so `findOverlayToken`'s binary search stays correct.
    let widths = @[20, 20, 20]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]

    let h = Highlight(colorSegments: @[])
    # A: length = 3*20 + 2 newlines = 62. B: single-line at (row=2, col=15).
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 62, 0, 0, 2, 15, 3, 1, 0]), colorTab, 1, getLen
    )
    check outcome == saoDone
    # Three disjoint segments on row 2: A_head [0..14], B [15..17], A_tail [18..19].
    check h.semantic[2].tokens.len == 3
    let t0 = h.semantic[2].tokens[0]
    let t1 = h.semantic[2].tokens[1]
    let t2 = h.semantic[2].tokens[2]
    check t0.firstColumn + t0.length <= t1.firstColumn
    check t1.firstColumn + t1.length <= t2.firstColumn
    check t0.firstColumn == 0
    check t0.length == 15
    check t0.color == EditorColorPairIndex.variable
    check t1.firstColumn == 15
    check t1.length == 3
    check t1.color == EditorColorPairIndex.function
    check t2.firstColumn == 18
    check t2.length == 2
    check t2.color == EditorColorPairIndex.variable
    # getColorPair returns the right token for every column, including the tail.
    check h.getColorPair(2, 14) == EditorColorPairIndex.variable
    check h.getColorPair(2, 15) == EditorColorPairIndex.function
    check h.getColorPair(2, 17) == EditorColorPairIndex.function
    check h.getColorPair(2, 18) == EditorColorPairIndex.variable
    check h.getColorPair(2, 19) == EditorColorPairIndex.variable

  test "UTF-16 deltaStart is converted to rune index when getLineText is supplied":
    # Line: "let <U+1F600> = 1"  ('let '=4 runes, U+1F600=1 rune (2 UTF-16
    # units), ' = 1'=4 runes) -> 9 runes total / 10 UTF-16 units.
    # Server sends token for '=' at UTF-16 col 6 length 1. Without conversion
    # this lands at rune col 6 (' '), off by one; with conversion at rune 5.
    let lineText: LineTextFn = proc(row: int): string {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row == 0: "let \u{1F600} = 1" else: ""
    let lineRunes: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row == 0: 9 else: -1

    let h = Highlight(colorSegments: @[])
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 6, 1, 1, 0]), colorTab, 1, lineRunes, -1, -1, lineText
    )
    check outcome == saoDone
    check h.semantic[0].tokens.len == 1
    check h.semantic[0].tokens[0].firstColumn == 5
    check h.semantic[0].tokens[0].length == 1

  test "Multi-line token with getLineText still unrolls across rows":
    # Regression: earlier code clamped applyLen to the start row's rune count
    # when getLineText was supplied, defeating the multi-line splitter for the
    # production caller (which always supplies both callbacks).
    let widths = @[5, 5, 5]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]
    let lineText: LineTextFn = proc(row: int): string {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row == 0:
          "hello"
        elif row == 1:
          "world"
        elif row == 2:
          "again"
        else:
          ""

    let h = Highlight(colorSegments: @[])
    # length = 4 ("ello") + 1\n + 5 ("world") + 1\n + 3 ("aga") = 14.
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 1, 14, 1, 0]), colorTab, 1, getLen, -1, -1, lineText
    )
    check outcome == saoDone
    check h.semantic.len == 3
    check h.semantic[0].tokens[0].firstColumn == 1
    check h.semantic[0].tokens[0].length == 4
    check h.semantic[0].tokens[0].color == EditorColorPairIndex.function
    check h.semantic[1].tokens[0].firstColumn == 0
    check h.semantic[1].tokens[0].length == 5
    check h.semantic[1].tokens[0].color == EditorColorPairIndex.function
    check h.semantic[2].tokens[0].firstColumn == 0
    check h.semantic[2].tokens[0].length == 3
    check h.semantic[2].tokens[0].color == EditorColorPairIndex.function

  test "Multi-line token with getLineText and non-BMP start row unrolls correctly":
    # Start row contains a non-BMP character (emoji): UTF-16 length differs
    # from rune length. Later rows are ASCII. The overflow-as-runes approx
    # keeps the splitter working; the residual off-by-few on wrap rows is
    # only for non-BMP characters in those wrap rows (none here).
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row == 0:
          5
        elif row == 1:
          5
        else:
          -1
    let lineText: LineTextFn = proc(row: int): string {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row == 0:
          "he\u{1F600}lo" # 5 runes, 6 UTF-16 units
        elif row == 1:
          "world" # 5 runes, 5 UTF-16 units
        else:
          ""

    let h = Highlight(colorSegments: @[])
    # length = 6 ("he😀lo" UTF-16) + 1\n + 5 ("world") = 12.
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 12, 1, 0]), colorTab, 1, getLen, -1, -1, lineText
    )
    check outcome == saoDone
    check h.semantic.len == 2
    check h.semantic[0].tokens[0].firstColumn == 0
    check h.semantic[0].tokens[0].length == 5
    check h.semantic[1].tokens[0].firstColumn == 0
    check h.semantic[1].tokens[0].length == 5

  test "Multi-line token length includes the \\n boundary per LSP spec":
    # multilineTokenSupport=true: server counts each \n as 1 UTF-16 unit.
    # A token from row 0 col 0 with length 6 covers "hello" (5) + \n (1),
    # ending exactly at row 1's start — row 1 gets no paint.
    let widths = @[5, 5]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]
    let lineText: LineTextFn = proc(row: int): string {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row == 0:
          "hello"
        elif row == 1:
          "world"
        else:
          ""

    block ends_on_newline:
      let h = Highlight(colorSegments: @[])
      let outcome = applySemanticTokens(
        h, mkResp(@[0, 0, 6, 1, 0]), colorTab, 1, getLen, -1, -1, lineText
      )
      check outcome == saoDone
      check h.semantic.len == 1
      check h.semantic[0].tokens[0].length == 5

    block one_past_newline:
      let h = Highlight(colorSegments: @[])
      let outcome = applySemanticTokens(
        h, mkResp(@[0, 0, 7, 1, 0]), colorTab, 1, getLen, -1, -1, lineText
      )
      check outcome == saoDone
      check h.semantic.len == 2
      check h.semantic[0].tokens[0].length == 5
      check h.semantic[1].tokens[0].firstColumn == 0
      check h.semantic[1].tokens[0].length == 1

  test "Legend swap between two non-empty legends wipes prior overlay":
    # A range-scoped apply under L2 would otherwise leave rows outside the
    # request range coloured against L1's index-to-name mapping. Verify the
    # full prior overlay is dropped when the current legend differs.
    let legendA = SemanticTokensLegend(
      tokenTypes: @["variable", "function", "type"], tokenModifiers: @[]
    )
    let tabA = buildSemanticTypeColorTable(legendA)
    let h = Highlight(colorSegments: @[])
    # Populate rows 0 and 5 under legend A.
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 5, 0, 3, 1, 0]), tabA, 1)
    check h.semantic.len == 2

    # Server dynamically re-registers with a permuted legend B.
    let legendB = SemanticTokensLegend(
      tokenTypes: @["function", "type", "variable"], tokenModifiers: @[]
    )
    let tabB = buildSemanticTypeColorTable(legendB)
    # Range apply under B for rows 4..6 (only touches row 5).
    let outcome = applySemanticTokens(h, mkResp(@[5, 0, 2, 0, 0]), tabB, 2, nil, 4, 6)
    check outcome == saoDone
    # Row 0 (under legend A) is wiped by the legend-swap detection. Only the
    # newly applied row 5 under B survives.
    check 0 notin h.semantic
    check 5 in h.semantic
    check h.semantic[5].tokens[0].color == EditorColorPairIndex.function

  test "Mid-parse rejection under legend swap preserves prior overlay":
    # Regression: legend-swap wipe used to fire BEFORE the parse loop, so a
    # malformed byte mid-response wiped the whole prior overlay across the
    # buffer even though the caller expects rejected replies to preserve state.
    let legendA = SemanticTokensLegend(
      tokenTypes: @["variable", "function", "type"], tokenModifiers: @[]
    )
    let legendB = SemanticTokensLegend(
      tokenTypes: @["function", "type", "variable"], tokenModifiers: @[]
    )
    let tabA = buildSemanticTypeColorTable(legendA)
    let tabB = buildSemanticTypeColorTable(legendB)
    let h = Highlight(colorSegments: @[])
    # Populate under legend A.
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 5, 0, 3, 1, 0]), tabA, 1)
    check h.semantic.len == 2
    let priorVersion = h.semanticContentVersion
    # Response under legend B whose data is well-formed prefix but ends
    # on a non-multiple-of-5 tail -- rejected as malformed.
    let outcome = applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 5, 0, 3, 1]), tabB, 5)
    check outcome == saoRejectedMalformed
    # Prior overlay must survive; semanticLegend must NOT have flipped to B.
    check h.semantic.len == 2
    check h.semanticContentVersion == priorVersion
    check h.semanticLegend == legendA
    check h.semantic[0].tokens[0].color == EditorColorPairIndex.variable
    check h.semantic[5].tokens[0].color == EditorColorPairIndex.function

  test "Mid-parse non-JInt rejection under legend swap preserves prior overlay":
    # Same class as above, but the malformed byte fires inside the token
    # loop (line/deltaStart/etc kind check), not from the up-front length
    # check. Deferred legend-swap must not have mutated highlight yet.
    let legendA = SemanticTokensLegend(
      tokenTypes: @["variable", "function", "type"], tokenModifiers: @[]
    )
    let legendB = SemanticTokensLegend(
      tokenTypes: @["function", "type", "variable"], tokenModifiers: @[]
    )
    let tabA = buildSemanticTypeColorTable(legendA)
    let tabB = buildSemanticTypeColorTable(legendB)
    let h = Highlight(colorSegments: @[])
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0]), tabA, 1)
    check h.semantic.len == 1
    # Second token in the data array has a JString deltaStart.
    let badResp = %*{"data": [%0, %0, %2, %0, %0, %0, %"bad", %2, %1, %0]}
    let outcome = applySemanticTokens(h, badResp, tabB, 2)
    check outcome == saoRejectedMalformed
    check h.semantic.len == 1
    check h.semanticLegend == legendA
    check h.semantic[0].tokens[0].color == EditorColorPairIndex.variable

  test "Empty range reply against empty legend rejects noLegend and preserves rows":
    # Regression: empty-reply branch used to run BEFORE the noLegend check,
    # so a transiently-empty legend + empty range reply would delete rows in
    # the range and advance the version. Now the noLegend check fires first.
    let h = Highlight(colorSegments: @[])
    # Prime rows 0 and 5 with a real legend.
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0, 5, 0, 3, 1, 0]), colorTab, 1)
    check h.semantic.len == 2
    let priorVersion = h.semanticContentVersion
    let emptyTab = buildSemanticTypeColorTable(
      SemanticTokensLegend(tokenTypes: @[], tokenModifiers: @[])
    )
    # Empty range reply against empty legend -> rejected, no mutation.
    check applySemanticTokens(h, mkResp(@[]), emptyTab, 5, nil, 4, 6) ==
      saoRejectedNoLegend
    check h.semantic.len == 2
    check h.semanticContentVersion == priorVersion
    # Empty full-doc reply against empty legend -> rejected, no mutation.
    check applySemanticTokens(h, mkResp(@[]), emptyTab, 5) == saoRejectedNoLegend
    check h.semantic.len == 2
    check h.semanticContentVersion == priorVersion

  test "XOR range args (one -1, one non-negative) is rejected as malformed":
    let h = Highlight(colorSegments: @[])
    # Populate first so we can check the overlay was NOT mutated.
    discard applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0]), colorTab, 1)
    check h.semantic.len == 1
    let priorVersion = h.semanticContentVersion
    # (5, -1): first is a range, last is full-doc sentinel -> malformed.
    check applySemanticTokens(h, mkResp(@[5, 0, 2, 1, 0]), colorTab, 2, nil, 5, -1) ==
      saoRejectedMalformed
    check applySemanticTokens(h, mkResp(@[5, 0, 2, 1, 0]), colorTab, 2, nil, -1, 5) ==
      saoRejectedMalformed
    # Prior overlay preserved on both.
    check h.semantic.len == 1
    check h.semanticContentVersion == priorVersion

  test "Two later tokens carve two holes in a multi-line unroll":
    # Recursive splitting: A spans row 1 fully; B and C are two disjoint
    # single-line tokens carving holes into A on row 1. Expected: A_head,
    # B, A_mid, C, A_tail.
    let widths = @[20, 20]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]

    let h = Highlight(colorSegments: @[])
    # A: 2*20 + 1 newline = 41. B/C: single-line on row 1.
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 41, 0, 0, 1, 5, 3, 1, 0, 0, 5, 3, 2, 0]), colorTab, 1, getLen
    )
    check outcome == saoDone
    check h.semantic[1].tokens.len == 5
    check h.semantic[1].tokens[0].firstColumn == 0
    check h.semantic[1].tokens[0].length == 5
    check h.semantic[1].tokens[0].color == EditorColorPairIndex.variable
    check h.semantic[1].tokens[1].firstColumn == 5
    check h.semantic[1].tokens[1].length == 3
    check h.semantic[1].tokens[1].color == EditorColorPairIndex.function
    check h.semantic[1].tokens[2].firstColumn == 8
    check h.semantic[1].tokens[2].length == 2
    check h.semantic[1].tokens[2].color == EditorColorPairIndex.variable
    check h.semantic[1].tokens[3].firstColumn == 10
    check h.semantic[1].tokens[3].length == 3
    check h.semantic[1].tokens[3].color == EditorColorPairIndex.typeName
    check h.semantic[1].tokens[4].firstColumn == 13
    check h.semantic[1].tokens[4].length == 7
    check h.semantic[1].tokens[4].color == EditorColorPairIndex.variable

  test "Multi-line unroll fully consumed by a later same-start token":
    # Degenerate case exercised via applySemanticTokens: two tokens whose
    # positions collide at the same starting column on a wrap row. Prior
    # token would truncate to length 0 -> dropped.
    let widths = @[20, 20]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]

    let h = Highlight(colorSegments: @[])
    # A: 2*20 + 1 newline = 41. B collides at (row=1, col=0).
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 41, 0, 0, 1, 0, 3, 1, 0]), colorTab, 1, getLen
    )
    check outcome == saoDone
    check h.semantic[1].tokens.len == 2
    check h.semantic[1].tokens[0].firstColumn == 0
    check h.semantic[1].tokens[0].length == 3
    check h.semantic[1].tokens[0].color == EditorColorPairIndex.function
    check h.semantic[1].tokens[1].firstColumn == 3
    check h.semantic[1].tokens[1].length == 17
    check h.semantic[1].tokens[1].color == EditorColorPairIndex.variable

  test "Multi-line splitter continues past an empty middle row":
    # Regression: an empty middle row (blank line inside a block comment or
    # heredoc) used to break out of the splitter and drop every subsequent
    # row of the same multi-line token.
    let widths = @[10, 0, 15]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]

    let h = Highlight(colorSegments: @[])
    # Row 0: 10, row 1: empty, row 2: 15. length = 25 content + 2 newlines = 27.
    let outcome = applySemanticTokens(h, mkResp(@[0, 0, 27, 0, 0]), colorTab, 1, getLen)
    check outcome == saoDone
    check 0 in h.semantic
    check 2 in h.semantic
    check h.semantic[0].tokens[0].length == 10
    check h.semantic[2].tokens[0].length == 15

  test "Three-way same-row overlap keeps the sorted-disjoint invariant":
    # Regression: addOverlayToken only inspected tokens[^1], so a multi-line
    # unroll interleaved with two same-row single tokens produced overlapping
    # segments that broke findOverlayToken's binary search.
    let widths = @[20, 20]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]

    let h = Highlight(colorSegments: @[])
    # A: 2*20 + 1 newline = 41. B, C overlap on row 1.
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 41, 0, 0, 1, 5, 3, 1, 0, 0, 2, 3, 2, 0]), colorTab, 1, getLen
    )
    check outcome == saoDone
    let toks = h.semantic[1].tokens
    # Verify strictly sorted, strictly disjoint.
    for i in 0 ..< toks.high:
      check toks[i].firstColumn + toks[i].length <= toks[i + 1].firstColumn

  test "Row token count is capped at MaxSemanticTokensPerRow":
    # Bounds addOverlayToken slow-path cost: without the cap, a non-compliant
    # server sending many overlapping tokens on one row incurs O(k^2) work.
    let h = Highlight(colorSegments: @[])
    let n = MaxSemanticTokensPerRow + 128
    var data = newSeqOfCap[int](n * 5)
    # First token at (row=0, col=0, len=1); each subsequent one is disjoint at
    # the next column (deltaStart=1). Fast-path adds hit the cap; excess drops.
    data.add(@[0, 0, 1, 0, 0])
    for i in 1 ..< n:
      data.add(@[0, 1, 1, 0, 0])
    let outcome = applySemanticTokens(h, mkResp(data), colorTab, 1)
    check outcome == saoDone
    check h.semantic[0].tokens.len == MaxSemanticTokensPerRow

  test "Modifier `declaration` unions StyleModifier.Bold into overlay":
    let modLegend =
      SemanticTokensLegend(tokenTypes: @["variable"], tokenModifiers: @["declaration"])
    let tab = buildSemanticTypeColorTable(modLegend)
    let h = Highlight(colorSegments: @[])
    # deltaLine=0, deltaStart=0, length=3, tokenType=0 (variable),
    # tokenModifiers=1 (declaration bit).
    let outcome = applySemanticTokens(h, mkResp(@[0, 0, 3, 0, 1]), tab, 1)
    check outcome == saoDone
    check h.getSegmentModifiers(0, 0) == {StyleModifier.Bold}

  test "Inverted range (first > last) is rejected as malformed":
    let h = Highlight(colorSegments: @[])
    let outcome =
      applySemanticTokens(h, mkResp(@[0, 0, 2, 0, 0]), colorTab, 1, nil, 50, 10)
    check outcome == saoRejectedMalformed

  test "Negative tokenModifiers is rejected as malformed":
    let h = Highlight(colorSegments: @[])
    # tokenModifiers = -1 (spec violation).
    let outcome = applySemanticTokens(h, mkResp(@[0, 0, 2, 0, -1]), colorTab, 1)
    check outcome == saoRejectedMalformed
    # Overlay unchanged, sentinel preserved.
    check h.semantic.len == 0
    check h.semanticContentVersion == -1

  test "tokenModifiers past uint32 range is rejected as malformed":
    # (type<<32)|mods cache key would silently truncate; reject up front.
    let h = Highlight(colorSegments: @[])
    let bigMod = int(high(uint32)) + 1
    let outcome = applySemanticTokens(h, mkResp(@[0, 0, 2, 0, bigMod]), colorTab, 1)
    check outcome == saoRejectedMalformed

  test "No-legend response is reported before mod-5 check":
    # A transiently-empty legend must surface as saoRejectedNoLegend even when
    # the response is simultaneously malformed (length not a multiple of 5).
    let emptyLegend = SemanticTokensLegend(tokenTypes: @[], tokenModifiers: @[])
    let emptyTab = buildSemanticTypeColorTable(emptyLegend)
    let h = Highlight(colorSegments: @[])
    let outcome = applySemanticTokens(h, mkResp(@[0, 0, 2, 0]), emptyTab, 1)
    check outcome == saoRejectedNoLegend

  test "Fresh Highlight starts with semanticContentVersion == -1 sentinel":
    let h = Highlight(colorSegments: @[])
    check h.semanticContentVersion == -1
    # A contentVersion of 0 (fresh newTextBuffer) can still successfully apply.
    discard applySemanticTokens(h, mkResp(@[0, 0, 3, 0, 0]), colorTab, 0)
    check h.semanticContentVersion == 0

  test "Multi-line UTF-16 wrap distributes overflow per row not as runes":
    # Regression: applyLen fallback added UTF-16 overflow to a rune count and
    # split by runes, over-counting when wrap rows had non-BMP characters. The
    # new per-row conversion consumes exact UTF-16 units per wrap row.
    let widths = @[3, 3]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]
    # Row 0: 3 ASCII runes (3 UTF-16 units).
    # Row 1: emoji + ASCII = 3 runes but 4 UTF-16 units (surrogate pair).
    let lineText: LineTextFn = proc(row: int): string {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row == 0:
          "abc"
        elif row == 1:
          "\u{1F600}xy"
        else:
          ""

    let h = Highlight(colorSegments: @[])
    # length = 3 (row 0) + 1\n + 4 (row 1 UTF-16 = 3 runes) = 8.
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 8, 1, 0]), colorTab, 1, getLen, -1, -1, lineText
    )
    check outcome == saoDone
    check h.semantic[0].tokens[0].length == 3
    check h.semantic[1].tokens[0].length == 3

  test "getLineText without getLineRuneCount caps at start-row runes":
    # No splitter callback: paint the start-row portion only rather than
    # stamping a phantom oversized overlay entry pinned to `currentLine`.
    let lineText: LineTextFn = proc(row: int): string {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row == 0:
          "abc" # 3 runes, 3 UTF-16 units
        else:
          ""

    let h = Highlight(colorSegments: @[])
    # Length = 10 UTF-16 units spilling past start row; nil splitter callback.
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 10, 1, 0]), colorTab, 1, nil, -1, -1, lineText
    )
    check outcome == saoDone
    # Only row 0 gets an overlay; length is clipped to the row's rune count.
    check h.semantic.len == 1
    check 0 in h.semantic
    check h.semantic[0].tokens[0].length <= 3

  test "Small token inside a carved multi-line unroll keeps middle token's color":
    # Regression: addOverlayToken's back-walk assumed only the outermost prior
    # could extend past `newEnd`, so the tail was coloured from whichever prior
    # was walked first. When state was [A_head, B, A_tail] (a multi-line wrap
    # A carved by an inner single-line token B) and a smaller C landed inside
    # B, cols between C.end and B.end were painted A.color instead of B.color.
    let widths = @[10, 20]
    let getLen: LineRuneCountFn = proc(row: int): int {.gcsafe, raises: [].} =
      {.cast(gcsafe).}:
        if row < 0 or row >= widths.len:
          -1
        else:
          widths[row]

    let h = Highlight(colorSegments: @[])
    # A: 10 + 20 + 1 newline = 31. B carves A on row 1; C lands inside B.
    let outcome = applySemanticTokens(
      h, mkResp(@[0, 0, 31, 0, 0, 1, 5, 10, 1, 0, 0, 2, 2, 2, 0]), colorTab, 1, getLen
    )
    check outcome == saoDone
    let toks = h.semantic[1].tokens
    # Sorted-disjoint invariant.
    for i in 0 ..< toks.high:
      check toks[i].firstColumn + toks[i].length <= toks[i + 1].firstColumn
    check toks.len == 5
    check toks[0].firstColumn == 0
    check toks[0].length == 5
    check toks[0].color == EditorColorPairIndex.variable
    check toks[1].firstColumn == 5
    check toks[1].length == 2
    check toks[1].color == EditorColorPairIndex.function
    check toks[2].firstColumn == 7
    check toks[2].length == 2
    check toks[2].color == EditorColorPairIndex.typeName
    # The regression: this segment must be B (function), not A (variable).
    check toks[3].firstColumn == 9
    check toks[3].length == 6
    check toks[3].color == EditorColorPairIndex.function
    check toks[4].firstColumn == 15
    check toks[4].length == 5
    check toks[4].color == EditorColorPairIndex.variable
    # getColorPair spot-checks around the previously-miscoloured span.
    check h.getColorPair(1, 9) == EditorColorPairIndex.function
    check h.getColorPair(1, 14) == EditorColorPairIndex.function
    check h.getColorPair(1, 15) == EditorColorPairIndex.variable

suite "Highlight - Semantic overlay edit shift":
  # Helpers to build a Highlight with a known overlay so shift semantics can
  # be exercised without going through the full applySemanticTokens path.
  proc mkTok(
      col, len: int, color = EditorColorPairIndex.function
  ): SemanticOverlayToken =
    SemanticOverlayToken(
      firstColumn: col, length: len, color: color, style: defaultStyle
    )

  proc mkH(rows: openArray[(int, seq[SemanticOverlayToken])], version = 42): Highlight =
    result = Highlight(colorSegments: @[])
    for (row, toks) in rows:
      result.semantic[row] = SemanticOverlayLine(tokens: toks)
    result.semanticContentVersion = version

  test "single-line insert shifts tokens right of editCol":
    let h = mkH({0: @[mkTok(2, 3), mkTok(10, 4)]})
    # Insert 2 runes at col 5 on row 0. New line length: 20.
    h.semanticShiftForSingleLineEdit(0, 5, 2, 20)
    check h.semantic[0].tokens.len == 2
    check h.semantic[0].tokens[0].firstColumn == 2 # untouched
    check h.semantic[0].tokens[0].length == 3
    check h.semantic[0].tokens[1].firstColumn == 12 # shifted by +2
    check h.semantic[0].tokens[1].length == 4

  test "single-line delete shifts tokens left of editCol and drops straddler":
    # Row 0: tokens at [0..2), [5..9), [12..15). Delete 3 runes at col 6.
    # Straddler [5..9) drops. [12..15) shifts to [9..12).
    let h = mkH({0: @[mkTok(0, 2), mkTok(5, 4), mkTok(12, 3)]})
    h.semanticShiftForSingleLineEdit(0, 6, -3, 17)
    check h.semantic[0].tokens.len == 2
    check h.semantic[0].tokens[0].firstColumn == 0
    check h.semantic[0].tokens[1].firstColumn == 9
    check h.semantic[0].tokens[1].length == 3

  test "single-line straddling token dropped":
    # Token [4..10) straddles editCol=6 → dropped.
    let h = mkH({0: @[mkTok(4, 6)]})
    h.semanticShiftForSingleLineEdit(0, 6, 2, 12)
    check not h.semantic.hasKey(0)

  test "single-line shift clips token whose tail exceeds new line length":
    # Token [10..20), new line length 15 → clipped to length 5.
    let h = mkH({0: @[mkTok(10, 10)]})
    h.semanticShiftForSingleLineEdit(0, 5, -2, 15)
    # After shift: token at firstColumn=8, length would be 10, clipped to 7.
    check h.semantic[0].tokens.len == 1
    check h.semantic[0].tokens[0].firstColumn == 8
    check h.semantic[0].tokens[0].length == 7

  test "single-line shift drops token whose start pushed past new line end":
    let h = mkH({0: @[mkTok(10, 3)]})
    # Delete 12 runes starting at col 5; new line length 3. Token would shift
    # to firstColumn = -2 → drop.
    h.semanticShiftForSingleLineEdit(0, 5, -12, 3)
    check not h.semantic.hasKey(0)

  test "single-line no-op when colDelta is zero":
    let h = mkH({0: @[mkTok(0, 5)]})
    h.semanticShiftForSingleLineEdit(0, 0, 0, 5)
    check h.semantic[0].tokens[0].firstColumn == 0

  test "single-line no-op when row has no entry":
    let h = mkH({0: @[mkTok(0, 5)]})
    h.semanticShiftForSingleLineEdit(9, 0, 2, 10)
    check h.semantic.len == 1

  test "multi-line insert shifts rows below down":
    # Overlay on rows 0, 3, 7. Insert 2 rows at row 3 (splitting between).
    # firstAffected=3, lastAffectedBefore=3, lastAffectedAfter=5.
    # Row 3 dropped. Rows > 3 shift by +2. Row 0 stays.
    let h = mkH({0: @[mkTok(0, 3)], 3: @[mkTok(1, 2)], 7: @[mkTok(4, 5)]})
    h.semanticShiftForMultiLineEdit(3, 3, 5)
    check h.semantic.hasKey(0)
    check not h.semantic.hasKey(3)
    check not h.semantic.hasKey(7)
    check h.semantic.hasKey(9)
    check h.semantic[9].tokens[0].firstColumn == 4

  test "multi-line delete drops range and shifts rows below up":
    # Overlay on rows 0, 5, 6, 9. Delete rows 5..6 (range collapse).
    # firstAffected=5, lastAffectedBefore=6, lastAffectedAfter=5.
    # Rows 5 and 6 dropped. Row 9 shifts to 8 (delta = -1).
    let h =
      mkH({0: @[mkTok(0, 3)], 5: @[mkTok(0, 2)], 6: @[mkTok(0, 1)], 9: @[mkTok(2, 4)]})
    h.semanticShiftForMultiLineEdit(5, 6, 5)
    check h.semantic.hasKey(0)
    check not h.semantic.hasKey(5)
    check not h.semantic.hasKey(6)
    check not h.semantic.hasKey(9)
    check h.semantic.hasKey(8)
    check h.semantic[8].tokens[0].firstColumn == 2

  test "multi-line insert of a single new line shifts existing overlay":
    # ckInsertLine(idx=2): rows >= 2 shift by +1. Emulated with
    # firstAffected=2, lastAffectedBefore=1 (empty clear range),
    # lastAffectedAfter=2.
    let h = mkH({0: @[mkTok(0, 2)], 2: @[mkTok(1, 3)], 4: @[mkTok(5, 2)]})
    h.semanticShiftForMultiLineEdit(2, 1, 2)
    check h.semantic.hasKey(0) # unchanged
    check h.semantic.hasKey(3)
    check h.semantic.hasKey(5)
    check h.semantic[3].tokens[0].firstColumn == 1
    check h.semantic[5].tokens[0].firstColumn == 5

  test "multi-line delete of a single row drops it and shifts below":
    # ckDeleteLine(idx=2): row 2 dropped, rows > 2 shift by -1.
    let h = mkH({0: @[mkTok(0, 2)], 2: @[mkTok(1, 3)], 5: @[mkTok(5, 2)]})
    h.semanticShiftForMultiLineEdit(2, 2, 1)
    check h.semantic.hasKey(0)
    check not h.semantic.hasKey(2)
    check h.semantic.hasKey(4)
    check h.semantic[4].tokens[0].firstColumn == 5

  test "multi-line ckReplaceLine drops only that row":
    let h = mkH({0: @[mkTok(0, 2)], 3: @[mkTok(1, 3)], 5: @[mkTok(5, 2)]})
    h.semanticShiftForMultiLineEdit(3, 3, 3)
    check h.semantic.hasKey(0)
    check not h.semantic.hasKey(3)
    check h.semantic.hasKey(5)

  test "multi-line no-op on empty overlay":
    let h = Highlight(colorSegments: @[])
    h.semanticShiftForMultiLineEdit(1, 3, 5)
    check h.semantic.len == 0

  # Integration: verify pushUndoChange -> emitRowColRemapEvents keeps
  # the overlay consistent so updateHighlight's fallback clear stays quiet.
  test "insertText integration keeps unaffected rows and shifts columns":
    let b = newTextBuffer("hello\nworld\nfoo bar\n")
    b.highlight.semantic[0] = SemanticOverlayLine(tokens: @[mkTok(0, 5)])
    b.highlight.semantic[1] = SemanticOverlayLine(tokens: @[mkTok(0, 5)])
    b.highlight.semantic[2] = SemanticOverlayLine(tokens: @[mkTok(4, 3)])
    b.highlight.semanticContentVersion = b.contentVersion
    let priorVersion = b.contentVersion
    # Insert "XX" at row 1, col 2. Row 1 token straddles col 2 → dropped.
    let r = b.insertText(BufferPosition(line: 1, column: 2), "XX")
    check r.isOk
    check b.contentVersion == priorVersion + 1
    check b.highlight.semanticContentVersion == b.contentVersion
    check b.highlight.semantic.hasKey(0) # untouched
    check not b.highlight.semantic.hasKey(1) # straddler dropped
    check b.highlight.semantic.hasKey(2) # untouched
    check b.highlight.semantic[2].tokens[0].firstColumn == 4

  test "insertText with newline shifts rows below down":
    let b = newTextBuffer("hello\nworld\nfoo bar\n")
    b.highlight.semantic[0] = SemanticOverlayLine(tokens: @[mkTok(0, 5)])
    b.highlight.semantic[2] = SemanticOverlayLine(tokens: @[mkTok(4, 3)])
    b.highlight.semanticContentVersion = b.contentVersion
    # Split row 0 at col 3 by inserting \n. Row 0 -> row 0 (kept truncated),
    # rows >= 1 shift by +1.
    let r = b.insertText(BufferPosition(line: 0, column: 3), "\n")
    check r.isOk
    check b.highlight.semanticContentVersion == b.contentVersion
    check not b.highlight.semantic.hasKey(0) # the split row is dropped
    check not b.highlight.semantic.hasKey(2) # was shifted away
    check b.highlight.semantic.hasKey(3) # row 2 -> row 3
    check b.highlight.semantic[3].tokens[0].firstColumn == 4

  test "deleteLine integration drops that row and shifts below up":
    let b = newTextBuffer("aa\nbb\ncc\ndd\n")
    b.highlight.semantic[1] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semantic[3] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semanticContentVersion = b.contentVersion
    let r = b.deleteLine(1)
    check r.isOk
    check b.highlight.semanticContentVersion == b.contentVersion
    check not b.highlight.semantic.hasKey(1)
    check not b.highlight.semantic.hasKey(3)
    check b.highlight.semantic.hasKey(2) # row 3 -> row 2

  test "replaceLine integration clears only that row":
    let b = newTextBuffer("aa\nbb\ncc\n")
    b.highlight.semantic[0] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semantic[1] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semantic[2] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semanticContentVersion = b.contentVersion
    let r = b.replaceLine(1, "zz")
    check r.isOk
    check b.highlight.semanticContentVersion == b.contentVersion
    check b.highlight.semantic.hasKey(0)
    check not b.highlight.semantic.hasKey(1)
    check b.highlight.semantic.hasKey(2)

  test "deleteRange spanning multiple lines collapses and shifts below":
    let b = newTextBuffer("aa\nbb\ncc\ndd\nee\n")
    b.highlight.semantic[0] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semantic[1] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semantic[2] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semantic[4] = SemanticOverlayLine(tokens: @[mkTok(0, 2)])
    b.highlight.semanticContentVersion = b.contentVersion
    # Delete from (1,0) to (2,1) inclusive — collapses row 1 and 2.
    let r = b.deleteRange(
      BufferPosition(line: 1, column: 0), BufferPosition(line: 2, column: 1)
    )
    check r.isOk
    check b.highlight.semanticContentVersion == b.contentVersion
    check b.highlight.semantic.hasKey(0)
    check not b.highlight.semantic.hasKey(1)
    check not b.highlight.semantic.hasKey(2)
    check not b.highlight.semantic.hasKey(4)
    check b.highlight.semantic.hasKey(3) # row 4 -> row 3

suite "Highlight - diagnosticOverlay read path":
  # These construct a Highlight directly with only diagnosticOverlay populated
  # (no baked syntaxCheck* segments) so the read-time overlay path is exercised
  # in isolation from the bake. When Phase 3 removes the bake, existing
  # behavioural tests keep passing only if this path is correct.

  test "overlay-only single-line hit returns color and Undercurl":
    let h = Highlight(colorSegments: @[])
    var line: DiagnosticOverlayLine
    line.cells.add(
      DiagnosticOverlayCell(
        firstColumn: 2,
        lastColumn: 4,
        color: EditorColorPairIndex.syntaxCheckErr,
        style: Style(modifiers: {StyleModifier.Undercurl}),
      )
    )
    h.diagnosticOverlay[0] = line

    check h.getColorPair(0, 1) == EditorColorPairIndex.default
    check h.getColorPair(0, 2) == EditorColorPairIndex.syntaxCheckErr
    check h.getColorPair(0, 4) == EditorColorPairIndex.syntaxCheckErr
    check h.getColorPair(0, 5) == EditorColorPairIndex.default

    check h.getSegmentModifiers(0, 2) == {StyleModifier.Undercurl}
    check h.getSegmentModifiers(0, 5) == {}

  test "overlay-only overlapping cells: last cell wins":
    let h = Highlight(colorSegments: @[])
    var line: DiagnosticOverlayLine
    line.cells.add(
      DiagnosticOverlayCell(
        firstColumn: 0,
        lastColumn: 4,
        color: EditorColorPairIndex.syntaxCheckErr,
        style: Style(modifiers: {StyleModifier.Undercurl}),
      )
    )
    line.cells.add(
      DiagnosticOverlayCell(
        firstColumn: 2,
        lastColumn: 7,
        color: EditorColorPairIndex.syntaxCheckWarn,
        style: Style(modifiers: {StyleModifier.Undercurl}),
      )
    )
    h.diagnosticOverlay[0] = line

    check h.getColorPair(0, 0) == EditorColorPairIndex.syntaxCheckErr
    check h.getColorPair(0, 3) == EditorColorPairIndex.syntaxCheckWarn
    check h.getColorPair(0, 7) == EditorColorPairIndex.syntaxCheckWarn

  test "overlay beats semantic overlay":
    let h = Highlight(colorSegments: @[])
    var sem: SemanticOverlayLine
    sem.tokens.add(
      SemanticOverlayToken(
        firstColumn: 0,
        length: 5,
        color: EditorColorPairIndex.function,
        style: Style(modifiers: {StyleModifier.Bold}),
      )
    )
    h.semantic[0] = sem

    var diag: DiagnosticOverlayLine
    diag.cells.add(
      DiagnosticOverlayCell(
        firstColumn: 1,
        lastColumn: 3,
        color: EditorColorPairIndex.syntaxCheckErr,
        style: Style(modifiers: {StyleModifier.Undercurl}),
      )
    )
    h.diagnosticOverlay[0] = diag

    # Inside diagnostic: colour is diag, modifiers union with semantic.
    check h.getColorPair(0, 2) == EditorColorPairIndex.syntaxCheckErr
    check h.getSegmentModifiers(0, 2) == {StyleModifier.Undercurl, StyleModifier.Bold}
    # Outside diagnostic but inside semantic: semantic wins.
    check h.getColorPair(0, 4) == EditorColorPairIndex.function
    check h.getSegmentModifiers(0, 4) == {StyleModifier.Bold}

  test "overlay with lastColumn=int.high covers row to end":
    let h = Highlight(colorSegments: @[])
    var line: DiagnosticOverlayLine
    line.cells.add(
      DiagnosticOverlayCell(
        firstColumn: 3,
        lastColumn: int.high,
        color: EditorColorPairIndex.syntaxCheckErr,
        style: Style(modifiers: {StyleModifier.Undercurl}),
      )
    )
    h.diagnosticOverlay[1] = line

    check h.getColorPair(1, 2) == EditorColorPairIndex.default
    check h.getColorPair(1, 3) == EditorColorPairIndex.syntaxCheckErr
    check h.getColorPair(1, 10_000) == EditorColorPairIndex.syntaxCheckErr

  test "applyDiagnosticHighlights populates diagnosticOverlay":
    # Sanity: the write path in buffer/markers.nim projects buffer.diagnostics
    # onto the per-row overlay in addition to the bake.
    let buf = newTextBuffer("line0\nline1\nline2\nline3")
    buf.language = SourceLanguage.langNone
    buf.diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 2,
        endLine: 2,
        endCol: 3,
        severity: bdsError,
        message: "multi-line",
      )
    ]
    buf.diagnosticsDirty = true
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()

    check 0 in buf.highlight.diagnosticOverlay
    check 1 in buf.highlight.diagnosticOverlay
    check 2 in buf.highlight.diagnosticOverlay
    check 3 notin buf.highlight.diagnosticOverlay

    check buf.highlight.diagnosticOverlay[0].cells[0].firstColumn == 2
    check buf.highlight.diagnosticOverlay[0].cells[0].lastColumn == int.high
    check buf.highlight.diagnosticOverlay[1].cells[0].firstColumn == 0
    check buf.highlight.diagnosticOverlay[1].cells[0].lastColumn == int.high
    check buf.highlight.diagnosticOverlay[2].cells[0].firstColumn == 0
    check buf.highlight.diagnosticOverlay[2].cells[0].lastColumn == 2
