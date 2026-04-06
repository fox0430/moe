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

import std/[unittest, unicode, os]

import pkg/celina

import ../src/moepkg/highlight
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/buffer {.all.}

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
      segments: segments, lineStates: LineStateCache(states: lineStates, version: 0)
    )

    # Update after editing line 1 (no size change)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      1,
      1,
      @[],
      SourceLanguage.langRust,
    )

    check incrHighlight.segments.len > 0
    check incrHighlight.lineStates.states.len == 3
    check incrHighlight.lineStates.version == 1

  test "updateHighlightIncremental with buffer size increase":
    var buffer = @["line1", "line2", "line3"]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 2, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates, version: 0)
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
      1,
      @[],
      SourceLanguage.langRust,
    )

    # Line states should be resized to match buffer
    check incrHighlight.lineStates.states.len == 4
    check incrHighlight.lineStates.version == 1

  test "updateHighlightIncremental with buffer size decrease":
    var buffer = @["line1", "line2", "line3", "line4"]

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
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      2,
      1,
      @[],
      SourceLanguage.langRust,
    )

    # Line states should be resized to match buffer
    check incrHighlight.lineStates.states.len == 3
    check incrHighlight.lineStates.version == 1

  test "updateHighlightIncremental re-parses all lines from change point":
    let buffer = @["line0", "line1", "line2", "line3", "line4"]

    # Initialize
    let (segments, lineStates) = initHighlightIncremental(
      buffer, 0, 4, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments, lineStates: LineStateCache(states: lineStates, version: 0)
    )

    # Edit line 2 - should re-parse from line 0 (margin of 2) to end of file
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      2,
      1,
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
    var incrHighlight = IncrementalHighlight(
      segments: @[], lineStates: LineStateCache(states: @[], version: 0)
    )

    # Should not crash
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      0,
      1,
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
      segments: segments, lineStates: LineStateCache(states: lineStates, version: 0)
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
      1,
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
      segments: segments0, lineStates: LineStateCache(states: lineStates0, version: 0)
    )

    # Simulate editing line 1: "    let x = 5;" → "    let z = 5;"
    buffer[1] = "    let z = 5;"

    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      1,
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

  test "multiline comment edit propagates state to end of file":
    # Opening a multiline comment affects all subsequent lines.
    # The incremental highlighter must re-parse to the end.
    var buffer = @["fn a() {}", "fn b() {}", "fn c() {}", "fn d() {}"]

    let (segments0, lineStates0) = initHighlightIncremental(
      buffer, 0, 3, TokenizerState(), @[], SourceLanguage.langRust
    )
    var incrHighlight = IncrementalHighlight(
      segments: segments0, lineStates: LineStateCache(states: lineStates0, version: 0)
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
      1,
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
      segments: segments0, lineStates: LineStateCache(states: lineStates0, version: 0)
    )

    # Edit line 5 (well within the buffer, far from end)
    buffer[5] = "let changed = 999;"

    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      incrHighlight,
      5,
      1,
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

suite "Highlight - Nim Incremental Comment/String":
  # Helper to verify incremental and full parse produce identical results.
  proc checkIncrMatchesFull(
      buffer: seq[string], ih: IncrementalHighlight, label: string
  ) =
    let incrResult = Highlight(colorSegments: ih.segments)
    var runesBuffer: seq[Runes]
    for line in buffer:
      runesBuffer.add(line.toRunes)
    let fullResult = initHighlight(runesBuffer, @[], SourceLanguage.langNim)
    for row in 0 ..< buffer.len:
      for col in 0 ..< buffer[row].len:
        check incrResult.getColorPair(row, col) == fullResult.getColorPair(row, col)

  test "insert comment in Nim source":
    var buffer = @[
      "import std/os", "", "type", "  Foo = object", "    name: string",
      "    value: int", "", "proc bar(f: Foo): string =", "  result = f.name",
    ]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )
    checkIncrMatchesFull(buffer, ih, "initial")

    # Insert comment before proc bar
    buffer.insert("# Helper function", 7)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      7,
      1,
      @[],
      SourceLanguage.langNim,
    )
    checkIncrMatchesFull(buffer, ih, "after insert comment")

  test "multiline string then insert comment":
    var buffer = @["let s = \"\"\"", "hello", "world", "\"\"\"", "echo s"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )
    checkIncrMatchesFull(buffer, ih, "initial multiline")

    # Insert comment after the multiline string
    buffer.insert("# done", 5)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      5,
      1,
      @[],
      SourceLanguage.langNim,
    )
    checkIncrMatchesFull(buffer, ih, "after comment insert")

  test "simulate typing comment char by char":
    var buffer = @["import std/os", "", "proc main() =", "  echo \"hello\""]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langNim
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )
    var ver = 0
    checkIncrMatchesFull(buffer, ih, "initial")

    # Insert empty line at 3
    buffer.insert("", 3)
    ver.inc
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      3,
      ver,
      @[],
      SourceLanguage.langNim,
    )
    checkIncrMatchesFull(buffer, ih, "after o")

    # Type '#'
    buffer[3] = "#"
    ver.inc
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      3,
      ver,
      @[],
      SourceLanguage.langNim,
    )
    checkIncrMatchesFull(buffer, ih, "after #")

    # Type '# comment'
    buffer[3] = "# comment"
    ver.inc
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      3,
      ver,
      @[],
      SourceLanguage.langNim,
    )
    checkIncrMatchesFull(buffer, ih, "after # comment")

suite "Highlight - Block Comment Multiline State":
  # Helper to verify incremental and full parse produce identical results.
  proc checkBlockCommentMatch(
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

  test "C: insert after multiline block comment":
    var buffer = @["int x = 1;", "/* this is", "   a comment", "*/", "int y = 2;"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langC
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )

    buffer.insert("int z = 3;", 5)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      5,
      1,
      @[],
      SourceLanguage.langC,
    )
    checkBlockCommentMatch(buffer, ih, SourceLanguage.langC)

  test "Rust: insert after multiline block comment":
    var buffer = @["fn main() {", "/* block", "   comment */", "let x = 1;", "}"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langRust
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )

    buffer.insert("let z = 2;", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      1,
      @[],
      SourceLanguage.langRust,
    )
    checkBlockCommentMatch(buffer, ih, SourceLanguage.langRust)

  test "JavaScript: insert after multiline block comment":
    var buffer = @["let x = 1;", "/* block", "   comment */", "let y = 2;"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langJavaScript
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )

    buffer.insert("let z = 3;", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      1,
      @[],
      SourceLanguage.langJavaScript,
    )
    checkBlockCommentMatch(buffer, ih, SourceLanguage.langJavaScript)

  test "TypeScript: insert after multiline block comment":
    var buffer =
      @["let x: number = 1;", "/* block", "   comment */", "let y: number = 2;"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langTypeScript
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )

    buffer.insert("let z: number = 3;", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      1,
      @[],
      SourceLanguage.langTypeScript,
    )
    checkBlockCommentMatch(buffer, ih, SourceLanguage.langTypeScript)

  test "Haskell: insert after multiline block comment":
    var buffer =
      @["module Main where", "{- block", "   comment -}", "main = putStrLn \"hello\""]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langHaskell
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )

    buffer.insert("foo = 1", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      1,
      @[],
      SourceLanguage.langHaskell,
    )
    checkBlockCommentMatch(buffer, ih, SourceLanguage.langHaskell)

  test "TOML: insert after multiline string":
    var buffer = @["name = \"\"\"", "hello", "world\"\"\"", "value = 42"]

    let (seg0, ls0) = initHighlightIncremental(
      buffer, 0, buffer.high, TokenizerState(), @[], SourceLanguage.langToml
    )
    var ih = IncrementalHighlight(
      segments: seg0, lineStates: LineStateCache(states: ls0, version: 0)
    )

    buffer.insert("other = 1", 4)
    updateHighlightIncremental(
      buffer.len,
      proc(i: int): string =
        buffer[i],
      ih,
      4,
      1,
      @[],
      SourceLanguage.langToml,
    )
    checkBlockCommentMatch(buffer, ih, SourceLanguage.langToml)

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

suite "Highlight - Progressive Initial Highlighting":
  test "continueInitialHighlight parses remaining lines":
    # A buffer larger than InitialChunkSize (1000 lines) should be
    # partially highlighted on load and completed via continueInitialHighlight.
    var buf = newTextBuffer()

    # Create a temp file with 2500 lines of Rust code
    let path = "/tmp/test_progressive_highlight.rs"
    var content = ""
    for i in 0 ..< 2500:
      content.add("let v" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    removeFile(path)

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

suite "Highlight - URI Underline on Load":
  test "loadFile applies URI underlines in initial chunk":
    var buf = newTextBuffer()

    let path = "/tmp/test_uri_highlight_initial.rs"
    var content = ""
    for i in 0 ..< 10:
      if i == 5:
        content.add("// see https://example.com/docs\n")
      else:
        content.add("let v" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    removeFile(path)

    # Line 5 contains a URI; it should have Underline modifier
    let uriCol = "// see ".len
    let mods = buf.highlight.getSegmentModifiers(5, uriCol)
    check Underline in mods

  test "loadFile applies URI underlines for plain text":
    var buf = newTextBuffer()

    let path = "/tmp/test_uri_highlight_plain.txt"
    var content = ""
    for i in 0 ..< 10:
      if i == 3:
        content.add("visit https://example.com/page\n")
      else:
        content.add("plain line " & $i & "\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    removeFile(path)

    let uriCol = "visit ".len
    let mods = buf.highlight.getSegmentModifiers(3, uriCol)
    check Underline in mods

  test "continueInitialHighlight applies URI underlines in later chunks":
    var buf = newTextBuffer()

    # Create file with URI beyond line 1000
    let path = "/tmp/test_uri_highlight_progressive.rs"
    var content = ""
    for i in 0 ..< 1500:
      if i == 1200:
        content.add("// see https://example.com/api\n")
      else:
        content.add("let v" & $i & " = " & $i & ";\n")
    writeFile(path, content)
    discard buf.loadFile(path)
    removeFile(path)

    # After loadFile, only first 1000 lines are parsed - line 1200 is not yet
    check buf.incrementalHighlight.parsedUpTo == 999

    # Continue parsing - should cover line 1200 and apply URI underline
    check buf.continueInitialHighlight() == true
    check buf.incrementalHighlight.parsedUpTo == 1499

    let uriCol = "// see ".len
    let mods = buf.highlight.getSegmentModifiers(1200, uriCol)
    check Underline in mods

  test "updateHighlight applies URI underlines after edit":
    var buf = newTextBuffer()

    let path = "/tmp/test_uri_highlight_update.rs"
    var content = "let x = 1;\nlet y = 2;\nlet z = 3;\n"
    writeFile(path, content)
    discard buf.loadFile(path)
    removeFile(path)

    # Edit line 1 to contain a URI
    discard buf.beginTransaction()
    discard buf.deleteLine(1)
    discard buf.insert(1, "// https://example.com")
    discard buf.commitTransaction()

    buf.updateHighlight()

    let uriCol = "// ".len
    let mods = buf.highlight.getSegmentModifiers(1, uriCol)
    check Underline in mods
