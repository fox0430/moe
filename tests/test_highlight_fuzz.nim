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

## Fuzz test for incremental highlighting.
##
## Verifies the invariant that
##   `updateHighlightIncremental` after a sequence of random edits
##     produces the SAME color at every (row, col) as
##   `initHighlight` (full reparse) on the resulting buffer.
##
## The convergence detection at highlight.nim:1063 assumes every
## `TokenizerState` field that affects future tokens is captured. If a future
## tokenizer adds a state field that escapes capture, the equality check at
## that line passes spuriously and incremental output silently diverges from
## the truth. This test catches that class of regression.
##
## Tuning via env vars:
##   MOE_FUZZ_HIGHLIGHT_ITERS   default 100 (per language)
##   MOE_FUZZ_HIGHLIGHT_SEED    default 0   (base seed; iteration N uses seed+N)

import std/[unittest, unicode, os, random, strformat, strutils]

import ../src/moepkg/highlight
import ../src/moepkg/syntax/tokenizer

type
  EditKind = enum
    ekInsertChar
    ekDeleteChar
    ekReplaceLine
    ekInsertLine
    ekDeleteLine

  Edit = object
    kind: EditKind
    row, col: int
    text: string

# Seed corpus

proc rustCorpus(): seq[seq[string]] =
  ## Hand-picked Rust snippets that exercise state-heavy tokenizer paths:
  ## nested block comments, raw strings with various hash depths, byte
  ## strings, attributes, and the lifetime/char-literal disambiguation.
  result = @[
    @[
      "fn main() {", "    let x: i32 = 42;", "    let s = \"hello\";",
      "    let r = r#\"raw with \"quotes\"\"#;", "    let b = b\"bytes\";",
      "    let c: char = 'x';", "    println!(\"{}\", x);", "}",
    ],
    @[
      "/* outer comment", "   /* nested", "      still inside */",
      "   back to outer */", "fn after() -> u32 { 0 }", "// trailing line comment",
    ],
    @[
      "#[derive(Debug, Clone)]", "struct Point<'a> {", "    name: &'a str,",
      "    x: f64,", "    y: f64,", "}", "", "impl<'a> Point<'a> {",
      "    fn new(name: &'a str) -> Self {", "        Self { name, x: 0.0, y: 0.0 }",
      "    }", "}",
    ],
    @[
      "fn raws() {", "    let a = r\"plain raw\";", "    let b = r#\"one hash\"#;",
      "    let c = r##\"two hash with #\"# inside\"##;", "    let d = b'\\n';",
      "    let e = 0x_FF_u32;", "    let f = 3.14f64;", "}",
    ],
    @[
      "#![allow(dead_code)]", "use std::collections::HashMap;", "",
      "fn parse(input: &str) -> Result<i32, String> {",
      "    input.trim().parse::<i32>().map_err(|e| e.to_string())", "}", "", "#[test]",
      "fn it_works() {", "    assert_eq!(parse(\"42\"), Ok(42));", "}",
    ],
  ]

proc nimCorpus(): seq[seq[string]] =
  ## Nim snippets covering nested block comments, triple-quoted strings,
  ## pragma blocks, and backtick identifiers.
  result = @[
    @[
      "proc add(a, b: int): int =", "  ## Add two integers.", "  result = a + b", "",
      "echo add(1, 2)",
    ],
    @[
      "#[ outer block", "   #[ nested block", "      still inside ]#",
      "   back to outer ]#", "proc after(): int = 0", "# trailing single-line comment",
    ],
    @["const greeting = \"\"\"", "Hello,", "world.", "\"\"\"", "", "echo greeting"],
    @[
      "{.push warning[Deprecated]: off.}", "proc legacy() {.deprecated.} =",
      "  discard", "{.pop.}", "", "type", "  Foo = object", "    `field-with-dash`: int",
    ],
    @[
      "import std/strutils", "", "proc main() =", "  let s = \"value=\" & $42",
      "  if s.startsWith(\"value\"):", "    echo s", "  else:", "    discard", "",
      "when isMainModule:", "  main()",
    ],
  ]

# Random edits

const PrintableAscii =
  " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`" &
  "abcdefghijklmnopqrstuvwxyz{|}~"

proc randomChar(rng: var Rand): string =
  $PrintableAscii[rng.rand(PrintableAscii.high)]

proc randomLineFromCorpus(corpus: seq[seq[string]], rng: var Rand): string =
  let snippet = corpus[rng.rand(corpus.high)]
  snippet[rng.rand(snippet.high)]

proc pickEdit(buf: seq[string], corpus: seq[seq[string]], rng: var Rand): Edit =
  ## Pick an edit applicable to the current buffer. Retries up to a bounded
  ## number of times if the dice roll lands on a noop combination (e.g.
  ## DeleteChar on an empty line); falls back to InsertChar as a guaranteed
  ## productive edit.
  for _ in 0 .. 9:
    let kind = EditKind(rng.rand(int(EditKind.high)))
    case kind
    of ekInsertChar:
      if buf.len == 0:
        continue
      let row = rng.rand(buf.high)
      let col = rng.rand(buf[row].len + 1) # inclusive end (append allowed)
      return Edit(kind: ekInsertChar, row: row, col: col, text: randomChar(rng))
    of ekDeleteChar:
      if buf.len == 0:
        continue
      let row = rng.rand(buf.high)
      if buf[row].len == 0:
        continue
      let col = rng.rand(buf[row].high)
      return Edit(kind: ekDeleteChar, row: row, col: col)
    of ekReplaceLine:
      if buf.len == 0:
        continue
      let row = rng.rand(buf.high)
      return Edit(
        kind: ekReplaceLine, row: row, col: 0, text: randomLineFromCorpus(corpus, rng)
      )
    of ekInsertLine:
      let row =
        if buf.len == 0:
          0
        else:
          rng.rand(buf.len) # inclusive end (append allowed)
      return Edit(
        kind: ekInsertLine, row: row, col: 0, text: randomLineFromCorpus(corpus, rng)
      )
    of ekDeleteLine:
      if buf.len <= 1:
        # Never empty the buffer entirely; the highlighter contract on a
        # zero-line buffer is not what this test targets.
        continue
      let row = rng.rand(buf.high)
      return Edit(kind: ekDeleteLine, row: row, col: 0)

  # Fallback: a guaranteed productive insert at (0, 0).
  if buf.len == 0:
    return Edit(kind: ekInsertLine, row: 0, col: 0, text: randomChar(rng))
  Edit(kind: ekInsertChar, row: 0, col: 0, text: randomChar(rng))

proc applyEdit(buf: var seq[string], e: Edit): int =
  ## Apply the edit in place. Returns `changedStartLine` to pass to
  ## `updateHighlightIncremental`.
  case e.kind
  of ekInsertChar:
    let line = buf[e.row]
    # substr is bounds-safe for the suffix (e.col may equal line.len for append).
    buf[e.row] = line.substr(0, e.col - 1) & e.text & line.substr(e.col)
    e.row
  of ekDeleteChar:
    let line = buf[e.row]
    buf[e.row] = line.substr(0, e.col - 1) & line.substr(e.col + 1)
    e.row
  of ekReplaceLine:
    buf[e.row] = e.text
    e.row
  of ekInsertLine:
    buf.insert(e.text, e.row)
    e.row
  of ekDeleteLine:
    buf.delete(e.row)
    # The deletion is observed at the same row index in the now-shorter
    # buffer; clamp to a valid index for downstream consumers.
    min(e.row, max(0, buf.len - 1))

# Comparison

proc fullHighlight(buf: seq[string], lang: SourceLanguage): Highlight =
  var runes: seq[Runes]
  for line in buf:
    runes.add(line.toRunes)
  initHighlight(runes, @[], lang)

proc firstDivergence(
    buf: seq[string], incr, full: Highlight
): tuple[ok: bool, row, col: int] =
  for row in 0 ..< buf.len:
    let lineLen = buf[row].len
    for col in 0 ..< lineLen:
      if incr.getColorPair(row, col) != full.getColorPair(row, col):
        return (false, row, col)
  (true, -1, -1)

# Diagnostics

proc editToString(e: Edit): string =
  case e.kind
  of ekInsertChar:
    &"InsertChar  row={e.row} col={e.col} text={e.text.escape}"
  of ekDeleteChar:
    &"DeleteChar  row={e.row} col={e.col}"
  of ekReplaceLine:
    &"ReplaceLine row={e.row} text={e.text.escape}"
  of ekInsertLine:
    &"InsertLine  row={e.row} text={e.text.escape}"
  of ekDeleteLine:
    &"DeleteLine  row={e.row}"

proc dumpFailure(
    lang: SourceLanguage,
    seed, iter: int,
    history: seq[Edit],
    buf: seq[string],
    divRow, divCol: int,
    incr, full: Highlight,
) =
  let header = "=== INCREMENTAL HIGHLIGHT MISMATCH ==="
  echo header
  echo &"Language:    {lang}"
  echo &"Seed:        {seed}"
  echo &"Iteration:   {iter}"
  echo &"Reproduce:   MOE_FUZZ_HIGHLIGHT_SEED={seed} MOE_FUZZ_HIGHLIGHT_ITERS=1"
  echo &"Edits ({history.len}):"
  for i, e in history:
    echo &"  [{i}] {editToString(e)}"
  echo &"First divergence: row={divRow} col={divCol}"
  echo &"  Incremental color: {incr.getColorPair(divRow, divCol)}"
  echo &"  Full reparse:      {full.getColorPair(divRow, divCol)}"
  echo &"Buffer ({buf.len} lines):"
  for i, line in buf:
    echo &"  {i:>3}: {line}"
  echo '='.repeat(header.len)

  # Best-effort artifact dump for post-mortem inspection.
  try:
    let path = getTempDir() / &"moe_highlight_fuzz_{lang}_seed{seed}.txt"
    var f = open(path, fmWrite)
    defer:
      f.close()
    f.writeLine(&"# Language: {lang}")
    f.writeLine(&"# Seed: {seed}  Iteration: {iter}")
    f.writeLine(&"# Edits:")
    for i, e in history:
      f.writeLine(&"#   [{i}] {editToString(e)}")
    f.writeLine(&"# Divergence at row={divRow} col={divCol}")
    f.writeLine(&"# Incremental: {incr.getColorPair(divRow, divCol)}")
    f.writeLine(&"# Full:        {full.getColorPair(divRow, divCol)}")
    f.writeLine("")
    for line in buf:
      f.writeLine(line)
    echo &"Artifact:    {path}"
  except IOError, OSError:
    discard # diagnostic dump is best-effort; failure here must not mask the test failure

# Test driver

proc runFuzz(
    lang: SourceLanguage, corpus: seq[seq[string]], iters, baseSeed: int
): bool =
  ## Returns true on success, false on first detected divergence (after dumping
  ## diagnostics). The caller asserts on the boolean so the unittest harness
  ## reports a single failure with a useful trailing log.
  for it in 0 ..< iters:
    let seed = baseSeed + it
    var rng = initRand(seed.int64 + 1) # +1 because initRand(0) is invalid
    var buf = corpus[rng.rand(corpus.high)]

    # Build initial incremental cache from a clean slate.
    let (segs0, states0) =
      initHighlightIncremental(buf, 0, buf.high, TokenizerState(), @[], lang)
    var ih = IncrementalHighlight(
      segments: segs0, lineStates: LineStateCache(states: states0, version: 0)
    )

    var history: seq[Edit]
    var version = 0
    let nEdits = 5 + rng.rand(8) # 5..12 inclusive

    for _ in 0 ..< nEdits:
      let e = pickEdit(buf, corpus, rng)
      history.add e
      let changedLine = applyEdit(buf, e)
      inc version

      let getLine = proc(i: int): string =
        buf[i]
      updateHighlightIncremental(buf.len, getLine, ih, changedLine, version, @[], lang)

      let incr = Highlight(colorSegments: ih.segments)
      let full = fullHighlight(buf, lang)
      let (ok, r, c) = firstDivergence(buf, incr, full)
      if not ok:
        dumpFailure(lang, seed, it, history, buf, r, c, incr, full)
        return false
  true

# Test suite

suite "Incremental Highlight Fuzz":
  const DefaultIters = 100
  let iters = parseInt(getEnv("MOE_FUZZ_HIGHLIGHT_ITERS", $DefaultIters))
  let baseSeed = parseInt(getEnv("MOE_FUZZ_HIGHLIGHT_SEED", "0"))

  test "Rust: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langRust, rustCorpus(), iters, baseSeed)

  test "Nim: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langNim, nimCorpus(), iters, baseSeed)
