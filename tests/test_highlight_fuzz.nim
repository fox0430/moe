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

proc javascriptCorpus(): seq[seq[string]] =
  ## JavaScript snippets covering template literals (single and multi-line,
  ## with `${...}` interpolation that bumps `templateLiteralDepth`), block
  ## and doc comments, and arrow functions.
  result = @[
    @[
      "function greet(name) {", "  console.log(`Hello, ${name}!`);",
      "  return name.length;", "}", "", "greet('world');",
    ],
    @[
      "const sql = `", "  SELECT *", "  FROM users", "  WHERE id = ${userId}",
      "    AND status = 'active'", "`;", "console.log(sql);",
    ],
    @[
      "/* outer block", "   /* nested-looking but JS does not nest */",
      "   back to outer */", "function after() { return 0; }",
      "// trailing line comment",
    ],
    @[
      "/**", " * Doc comment for compute.", " * @param {number} x",
      " * @returns {Promise<number>}", " */", "async function compute(x) {",
      "  return await Promise.resolve(x * 2);", "}",
    ],
    @[
      "const xs = [1, 2, 3]", "  .map(n => `n=${n}`)",
      "  .filter(s => s.includes('2'))", "  .join(', ');",
    ],
  ]

proc typescriptCorpus(): seq[seq[string]] =
  ## TypeScript snippets covering generics, type annotations, template
  ## literals with interpolation, doc comments, and decorators.
  result = @[
    @[
      "interface User {", "  name: string;", "  age: number;", "}", "",
      "function greet(u: User): string {",
      "  return `Hello, ${u.name} (age ${u.age})`;", "}",
    ],
    @[
      "class Stack<T> {", "  private items: T[] = [];",
      "  push(item: T): void { this.items.push(item); }",
      "  pop(): T | undefined { return this.items.pop(); }", "}",
    ],
    @[
      "/* outer block", "   /* nested-looking but TS does not nest */",
      "   back to outer */", "type Id = number | string;", "// trailing line comment",
    ],
    @[
      "/**", " * Doc comment for fetch.", " * @template T", " */",
      "async function fetch<T>(url: string): Promise<T> {",
      "  const res = await window.fetch(url);", "  return res.json() as T;", "}",
    ],
    @[
      "const tag = (strings: TemplateStringsArray, ...values: unknown[]) => {",
      "  return strings.reduce((acc, s, i) => `${acc}${s}${values[i] ?? ''}`, '');",
      "};", "const result = tag`x=${1} y=${2}`;",
    ],
  ]

proc markdownCorpus(): seq[seq[string]] =
  ## Markdown snippets covering the state-heavy multi-line constructs:
  ## frontmatter (---...---), fenced and indented code blocks, and math
  ## ($...$, $$...$$). These all carry state across line boundaries, so an
  ## edit inside or after one must restore that state on incremental reparse.
  result = @[
    @[
      "---", "title: Hello World", "author: Me", "date: 2024-01-01", "tags:", "  - nim",
      "  - editor", "---", "", "# Heading", "", "Some body text here.",
    ],
    @[
      "---", "draft: true", "---", "## Section", "", "para one", "", "para two", "",
      "more text after frontmatter",
    ],
    @[
      "# Title", "", "Intro paragraph.", "", "---", "", "After a thematic break.",
      "Another line.", "Yet another.",
    ],
    @[
      "# Code", "", "```nim", "proc add(a, b: int): int =", "  result = a + b", "```",
      "", "And `inline code` too.",
    ],
    @[
      "Indented code follows:", "", "    let x = 1", "    let y = 2", "",
      "Back to normal text.",
    ],
    @[
      "Math: $a + b = c$ inline.", "", "$$", "\\sum_{i=0}^n i", "$$", "",
      "Done with math.",
    ],
    @[
      "---", "key: value", "---", "", "- item one", "- item two", "", "> a blockquote",
      "", "**bold** and *italic*",
    ],
  ]

proc pythonCorpus(): seq[seq[string]] =
  ## Python snippets covering the cross-line state carried in `commentDepth`:
  ## triple-quoted strings with both `"""` and `'''` delimiters (docstrings),
  ## plus line comments and f-strings.
  result = @[
    @[
      "def add(a, b):", "    \"\"\"Add two integers.\"\"\"", "    return a + b", "",
      "print(add(1, 2))",
    ],
    @[
      "x = \"\"\"", "multi-line", "string spanning", "several lines", "\"\"\"",
      "print(x)",
    ],
    @[
      "y = '''", "another multi-line", "with 'single' quotes inside", "'''",
      "# trailing line comment", "z = 42",
    ],
    @[
      "class Point:", "    '''A point in 2D space.'''", "    def __init__(self, x, y):",
      "        self.x = x", "        self.y = y", "", "    def __repr__(self):",
      "        return f\"Point({self.x}, {self.y})\"",
    ],
    @[
      "import os", "", "def parse(s):", "    # parse the value",
      "    n = int(s.strip())", "    return n * 2", "", "if __name__ == '__main__':",
      "    print(parse(\"21\"))",
    ],
  ]

proc latexCorpus(): seq[seq[string]] =
  ## LaTeX snippets covering math-mode state across lines (`latexInMathMode`,
  ## `latexInDisplayMath`): inline math ($...$), display math ($$...$$),
  ## environments, and line comments (%).
  result = @[
    @[
      "\\documentclass{article}", "\\begin{document}", "Hello, \\LaTeX{}.",
      "Inline math $a + b = c$ here.", "\\end{document}",
    ],
    @[
      "$$", "\\sum_{i=0}^{n} i = \\frac{n(n+1)}{2}", "$$", "",
      "% trailing comment line", "Some text after display math.",
    ],
    @[
      "\\begin{equation}", "  E = mc^2", "\\end{equation}", "",
      "The famous equation above.",
    ],
    @[
      "\\section{Intro}", "% a comment", "Text with $x^2 + y^2 = r^2$ inline.", "",
      "\\begin{itemize}", "  \\item first", "  \\item second", "\\end{itemize}",
    ],
    @[
      "Mixed: $\\alpha$ then", "$$", "\\int_0^1 f(x)\\,dx", "$$",
      "and back to $\\beta$ inline.",
    ],
  ]

proc lispCorpus(): seq[seq[string]] =
  ## Lisp snippets covering nested block comments (#| |#, which nest via
  ## `commentDepth`), line comments (;), and string literals.
  result = @[
    @[
      "(defun add (a b)", "  \"Add two numbers.\"", "  (+ a b))", "",
      "(princ (add 1 2))",
    ],
    @[
      "#| outer comment", "   #| nested", "      still inside |#",
      "   back to outer |#", "(defun after () 0)", "; trailing line comment",
    ],
    @[
      "(defstruct point", "  (x 0.0)", "  (y 0.0))", "",
      "(defparameter *origin* (make-point))",
    ],
    @[
      "(let ((xs '(1 2 3)))", "  (mapcar (lambda (n) (* n 2)) xs))", "",
      "; double each element", "(defvar *count* 0)",
    ],
    @[
      "(defun factorial (n)", "  (if (<= n 1)", "      1",
      "      (* n (factorial (- n 1)))))", "", "(format t \"~a~%\" (factorial 5))",
    ],
  ]

proc cCorpus(): seq[seq[string]] =
  ## C snippets covering the cross-line state carried in `gtLongComment` /
  ## `gtDocLongComment`: multi-line block comments and doc comments (C block
  ## comments do NOT nest), plus line comments, preprocessor directives with
  ## line continuation, and string/char literals.
  result = @[
    @[
      "#include <stdio.h>", "", "int main(void) {", "    int x = 42;",
      "    char c = 'x';", "    printf(\"value = %d\\n\", x);", "    return 0;", "}",
    ],
    @[
      "/* outer block comment", "   /* C does not nest these */",
      "   still inside the first */", "int after(void) { return 0; }",
      "// trailing line comment",
    ],
    @[
      "/**", " * Doc comment for add.", " * @param a first operand",
      " * @param b second operand", " */", "int add(int a, int b) {",
      "    return a + b;", "}",
    ],
    @[
      "#define SQUARE(x) ((x) * (x))", "#define LONG_MACRO(a, b) \\",
      "    do {              \\", "        (a) += (b);   \\", "    } while (0)", "",
      "static const char *msg = \"hello\";",
    ],
    @[
      "#include <string.h>", "", "struct Point {", "    double x;", "    double y;",
      "};", "", "enum Color { RED, GREEN, BLUE };", "typedef unsigned long size_type;",
    ],
  ]

proc cppCorpus(): seq[seq[string]] =
  ## C++ snippets covering multi-line block/doc comments (no nesting), line
  ## comments, preprocessor directives, templates, namespaces, and string/char
  ## literals. C++ shares the C tokenizer path, so the same cross-line block
  ## comment state is the primary target.
  result = @[
    @[
      "#include <iostream>", "", "int main() {", "    int x = 42;",
      "    std::cout << \"value = \" << x << std::endl;", "    return 0;", "}",
    ],
    @[
      "/* outer block comment", "   /* C++ does not nest these */",
      "   still inside the first */", "int after() { return 0; }",
      "// trailing line comment",
    ],
    @[
      "/**", " * Doc comment for a templated max.", " * @tparam T element type", " */",
      "template <typename T>", "T maxValue(T a, T b) {", "    return a > b ? a : b;",
      "}",
    ],
    @[
      "#pragma once", "namespace geom {", "", "class Point {", "public:",
      "    Point(double x, double y) : x_(x), y_(y) {}", "private:",
      "    double x_, y_;", "};", "", "}  // namespace geom",
    ],
    @[
      "#include <vector>", "#include <string>", "",
      "auto greet(const std::string &name) -> std::string {",
      "    return \"Hello, \" + name + '!';", "}", "",
      "std::vector<int> xs = {1, 2, 3};",
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
  ## Compare colors at every non-whitespace position. Whitespace positions
  ## are skipped because tokenizers legitimately differ on which adjacent
  ## token absorbs surrounding spaces (e.g. whether `  await` carries the
  ## leading two spaces in the whitespace segment or the keyword segment);
  ## those boundary choices have no visible effect to the user.
  for row in 0 ..< buf.len:
    let line = buf[row]
    for col in 0 ..< line.len:
      if line[col] in {' ', '\t'}:
        continue
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

    try:
      for _ in 0 ..< nEdits:
        let e = pickEdit(buf, corpus, rng)
        history.add e
        let changedLine = applyEdit(buf, e)
        inc version

        let getLine = proc(i: int): string =
          buf[i]
        updateHighlightIncremental(
          buf.len, getLine, ih, changedLine, version, @[], lang
        )

        let incr = Highlight(colorSegments: ih.segments)
        let full = fullHighlight(buf, lang)
        let (ok, r, c) = firstDivergence(buf, incr, full)
        if not ok:
          dumpFailure(lang, seed, it, history, buf, r, c, incr, full)
          return false
    except Exception as exc:
      # Tokenizer-level crash (e.g. `doAssert false` for empty-token) or any
      # other runtime defect. Log enough context for repro and re-raise so
      # the unittest harness shows the original stack.
      echo "=== TOKENIZER CRASH ==="
      echo &"Language:  {lang}"
      echo &"Seed:      {seed}"
      echo &"Iteration: {it}"
      echo &"Reproduce: MOE_FUZZ_HIGHLIGHT_SEED={seed} MOE_FUZZ_HIGHLIGHT_ITERS=1"
      echo &"Edits ({history.len}):"
      for i, e in history:
        echo &"  [{i}] {editToString(e)}"
      echo &"Buffer ({buf.len} lines):"
      for i, line in buf:
        echo &"  {i:>3}: {line}"
      echo &"Exception: {exc.name}: {exc.msg}"
      echo "======================"
      raise
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

  test "JavaScript: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langJavaScript, javascriptCorpus(), iters, baseSeed)

  test "TypeScript: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langTypeScript, typescriptCorpus(), iters, baseSeed)

  test "Markdown: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langMarkdown, markdownCorpus(), iters, baseSeed)

  test "Python: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langPython, pythonCorpus(), iters, baseSeed)

  test "LaTeX: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langLatex, latexCorpus(), iters, baseSeed)

  test "Lisp: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langLisp, lispCorpus(), iters, baseSeed)

  test "C: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langC, cCorpus(), iters, baseSeed)

  test "C++: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langCpp, cppCorpus(), iters, baseSeed)
