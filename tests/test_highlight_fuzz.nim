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

proc jsxCorpus(): seq[seq[string]] =
  ## JSX snippets exercising `jslike.inJsxMode` / `jslike.jsxTagDepth`, which
  ## plain JS never enters. Covers tag open/close across lines, nested tags,
  ## expression embedding `{...}` (exits JSX; a `}` followed by `<` re-enters),
  ## `${...}` template literals nested inside JSX expressions, and fragments.
  result = @[
    @[
      "function App() {", "  return (", "    <div className=\"root\">",
      "      <h1>Hello</h1>", "      <p>world</p>", "    </div>", "  );", "}",
    ],
    # Self-closing tags must not push jsxTagDepth.
    @[
      "const view = (", "  <section>", "    <header>", "      <Title />",
      "    </header>", "    <main>", "      <Item />", "      <Item />", "    </main>",
      "  </section>", ");",
    ],
    @[
      "const greet = (name) => (", "  <div>", "    <span>Hello, {name}!</span>",
      "    <span>Count: {items.length}</span>", "  </div>", ");",
    ],
    # Nesting: JSX -> `{` expr -> `${...}` template. braceDepthStack must
    # return the closing `}` to the template, not to JSX.
    @[
      "const badge = (n) => (", "  <span title={`count=${n}`}>", "    {`items: ${n}`}",
      "  </span>", ");",
    ],
    # Fragment `<>...</>` + JSX comment + `<` as a less-than operator inside
    # an expression container (must not mistrigger JSX).
    @[
      "const list = (xs) => (", "  <>", "    {/* render items */}",
      "    {xs.filter((x) => x < 10).map((x) => (", "      <li key={x}>{x}</li>",
      "    ))}", "  </>", ");",
    ],
  ]

proc tsxCorpus(): seq[seq[string]] =
  ## TSX layers TypeScript's generic `<T>` disambiguation on top of JSX: a `<`
  ## preceded by an identifier character is a generic, not a tag. Mixes
  ## `Array<T>`, `useState<number>()`, and `<Component>` so an edit that
  ## shifts the preceding token must re-classify every downstream `<`.
  result = @[
    @[
      "interface Props { name: string; count: number; }",
      "const Card: React.FC<Props> = ({ name, count }) => (", "  <div>",
      "    <span>{name}</span>", "    <b>{count}</b>", "  </div>", ");",
    ],
    @[
      "import { useState } from \"react\";", "export function Counter() {",
      "  const [n, setN] = useState<number>(0);", "  return (",
      "    <div onClick={() => setN(n + 1)}>", "      <span>count: {n}</span>",
      "    </div>", "  );", "}",
    ],
    # `<T,>` trailing comma disambiguates a generic arrow from JSX.
    @[
      "const first = <T,>(xs: T[]): T | undefined => xs[0];",
      "const view = (items: number[]) => (", "  <>", "    {items.map((x: number) => (",
      "      <li key={x}>{first<number>([x])}</li>", "    ))}", "  </>", ");",
    ],
    @[
      "const rows: Array<string> = [\"a\", \"b\"];", "const table = (", "  <table>",
      "    {rows.map((r) => (", "      <tr title={`row=${r}`}><td>{r}</td></tr>",
      "    ))}", "  </table>", ");",
    ],
    # `@decorator` is TS-only and must not perturb the following JSX.
    @[
      "@Component({ selector: \"app-root\" })", "class Root {", "  render() {",
      "    return (", "      <section>", "        <h2>title</h2>", "      </section>",
      "    );", "  }", "}",
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

proc haskellCorpus(): seq[seq[string]] =
  ## Haskell snippets stressing the line-bounded string/char literals and the
  ## `\` escape split carried in `commentDepth` (1 = ", 2 = '): strings with
  ## apostrophes, char literals next to identifiers, escaped quotes, plus
  ## nested {- -} block comments and -- line comments.
  result = @[
    @["module Main where", "", "main :: IO ()", "main = putStrLn \"it's a test\""],
    @[
      "greet :: String -> String", "greet name = \"Hello, \" ++ name ++ \"!\"",
      "-- a line comment", "sep = '\\n'",
    ],
    @[
      "{- outer comment", "   {- nested -}", "   still inside -}", "quote = '\\''",
      "esc = \"a\\\"b\"",
    ],
    @[
      "chars :: [Char]", "chars = ['a', 'b', '\\t', '\\'']", "", "tab = '\\t'",
      "x = 1 -- trailing",
    ],
    @[
      "data Color = Red | Green | Blue", "", "describe :: Color -> String",
      "describe Red = \"can't be redder\"", "describe _ = \"some color\"",
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

proc htmlCorpus(): seq[seq[string]] =
  ## HTML snippets covering the cross-line state carried in `inComment` /
  ## `gtLongComment`: multi-line `<!-- ... -->` comments, plus tags,
  ## attributes with quoted values, DOCTYPE, and entities.
  result = @[
    @[
      "<!DOCTYPE html>", "<html lang=\"en\">", "  <head>", "    <title>Hello</title>",
      "  </head>", "  <body>", "    <h1>Hi</h1>", "  </body>", "</html>",
    ],
    @[
      "<!-- outer comment", "   still inside the comment", "   third line -->",
      "<p>back to markup</p>", "<!-- single line comment -->",
    ],
    @[
      "<div class=\"box\" id='main'>", "  <a href=\"https://example.com\">link</a>",
      "  <img src=\"pic.png\" alt=\"a picture\" />", "</div>",
    ],
    @[
      "<ul>", "  <li>first &amp; foremost</li>", "  <li>second &lt; third</li>",
      "  <li>&#169; 2024</li>", "</ul>",
    ],
    @[
      "<form action=\"/submit\" method=\"post\">", "  <!-- TODO: validate",
      "       these inputs", "       before submit -->",
      "  <input type=\"text\" name=\"q\" />", "  <button>Go</button>", "</form>",
    ],
  ]

proc xmlCorpus(): seq[seq[string]] =
  ## XML snippets covering the cross-line state carried in `g.state`:
  ## `gtLongComment` (multi-line `<!-- ... -->` comments) and `gtCData`
  ## (multi-line `<![CDATA[ ... ]]>` sections), plus the XML declaration,
  ## DOCTYPE, namespaced tags, attributes with quoted values, and entities.
  result = @[
    @[
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<note priority=\"high\">",
      "  <to>Alice</to>", "  <from>Bob</from>",
      "  <body>Don't forget &amp; remember!</body>", "</note>",
    ],
    @[
      "<!-- outer comment", "   still inside the comment", "   third line -->",
      "<config enabled=\"true\" />", "<!-- single line comment -->",
    ],
    @[
      "<script>", "  <![CDATA[", "    if (a < b && b > c) {", "      print(\"raw\");",
      "    }", "  ]]>", "</script>",
    ],
    @[
      "<!DOCTYPE note SYSTEM \"note.dtd\">", "<items xmlns:x=\"http://example.com\">",
      "  <x:item id='1'>first &lt; second</x:item>",
      "  <x:item id='2'>&#169; 2024</x:item>", "</items>",
    ],
    @[
      "<data><![CDATA[inline cdata]]></data>", "<mixed>text <b>bold</b> tail</mixed>",
      "<empty/>", "<?target instruction?>",
    ],
    @[
      "<?xml version=\"1.0\" encoding=\"UTF-8\"?>", "<蔵書 管理者=\"司書\">",
      "  <書名 ふりがな=\"にほんご\">日本語のテキスト &amp; 実体</書名>",
      "  <!-- 複数行コメント", "       まだコメントの中 -->",
      "  <データ><![CDATA[生データ < & >]]></データ>", "</蔵書>",
    ],
  ]

proc astroCorpus(): seq[seq[string]] =
  ## Astro snippets covering the cross-line state carried in
  ## `astroInFrontmatter` / `astroFirstLine`, plus the state delegated to the
  ## JavaScript tokenizer inside frontmatter (`templateLiteralDepth`,
  ## `commentDepth`) and to the HTML tokenizer in the template (`inComment`,
  ## `inScript`, `inStyle`). The `---...---` frontmatter fence and the
  ## frontmatter/template boundary are the primary targets.
  result = @[
    @[
      "---", "const name = \"world\";", "const items = [1, 2, 3];", "---", "<html>",
      "  <body>", "    <h1>Hello, {name}!</h1>", "  </body>", "</html>",
    ],
    @[
      "---", "import Layout from \"../layouts/Layout.astro\";", "/* outer block",
      "   still inside */", "const sql = `", "  SELECT * FROM users",
      "  WHERE id = ${id}", "`;", "---", "<p set:html={sql}></p>",
    ],
    @[
      "---", "const title = \"Page\";", "---", "<!-- outer comment",
      "     still inside", "     third line -->", "<main>", "  <h1>{title}</h1>",
      "</main>",
    ],
    @[
      "---", "const color = \"red\";", "---", "<style>", "  body { color: var(--c); }",
      "</style>", "<script>", "  console.log(`loaded`);", "</script>",
    ],
    @[
      "---", "const xs = [1, 2, 3];", "---", "<ul>", "  {xs.map((n) => (",
      "    <li>item {n}</li>", "  ))}", "</ul>",
    ],
  ]

proc yamlCorpus(): seq[seq[string]] =
  ## YAML snippets covering the state-heavy multi-line constructs: block
  ## scalars (`|`, `>` with chomping/indent indicators, which carry `gtCommand`
  ## then `gtLongStringLit` across lines), multi-line double-quoted (`gtStringLit`)
  ## and single-quoted (`gtCharLit`) strings, the document-marker state toggle
  ## (`---`/`...` flipping between the in-document `gtOther` and out-of-document
  ## states), directives, and the `yamlIsKey` flag set on quoted keys.
  result = @[
    @[
      "key: value", "name: example", "description: |",
      "  This is a literal block scalar.", "  It spans multiple lines.",
      "  Indentation determines the end.", "trailing: done",
    ],
    @[
      "---", "config: >-", "  folded scalar text", "  that wraps across lines", "list:",
      "  - one", "  - two", "...",
    ],
    @[
      "multi: \"this string", "  continues on the next line\"",
      "single: 'it''s got an escaped quote", "  and wraps too'",
      "plain: just a plain scalar",
    ],
    @[
      "%YAML 1.2", "---", "anchored: &id value", "ref: *id", "tagged: !!str 123",
      "nested:", "  inner: !<tag:example.com,2002:foo> bar",
    ],
    @[
      "steps:", "  - name: build", "    run: |", "      echo \"building\"",
      "      make all", "  # comment after the block scalar", "  - name: test",
      "    run: |", "      make test",
    ],
    @[
      "flags: [true, false, null]", "matrix: {x: 1, y: 2.5, z: 0xFF}",
      "when: 2024-01-01", "ratio: .inf", "empty: ~",
    ],
    @[
      "data: |2", "    indented content", "    more content", "after: value",
      "literal: |+", "  keep trailing", "", "", "next: done",
    ],
  ]

proc shellCorpus(): seq[seq[string]] =
  ## Shell snippets exercising the string state machine: multi-line and
  ## single-line double/single-quoted strings (`gtStringLit`), in-string
  ## escapes (`gtEscapeSequence`, which parks `gtStringLit` across the
  ## backslash), backslash line continuation, comments, keywords and the
  ## numeric bases. The multi-line strings pin the line-bounded string fix:
  ## a `"`/`'` opened on one line must not become one token spanning the
  ## newline (its interior boundary state would be `gtNone`, breaking resume).
  result = @[
    @[
      "#!/bin/bash", "echo \"hello world\"", "name='single quoted'",
      "if [ -f file ]; then", "  echo \"found\"", "fi",
    ],
    @["msg=\"this string", "continues on the next line\"", "echo \"$msg\"", "ls -la"],
    @[
      "path=\"/usr/local/bin\"", "echo \"tab\\there\"", "printf '%s\\n' \"$path\"",
      "x=0xFF", "y=017", "z=0b1010",
    ],
    @["long=\"part one \\", "part two\"", "for i in 1 2 3; do", "  echo $i", "done"],
    @["# a comment line", "export VAR='value'", "unset OTHER", "func() { return 0; }"],
  ]

proc zshCorpus(): seq[seq[string]] =
  ## Zsh shares the shell string machine; same multi-line string coverage
  ## plus zsh-only keywords.
  result = @[
    @[
      "autoload -U compinit", "echo \"hello $USER\"", "setopt no_beep",
      "alias ll='ls -la'",
    ],
    @[
      "greeting=\"line one", "line two\"", "print -r -- \"$greeting\"", "typeset -i n=5"
    ],
    @[
      "local str='single", "spanning'", "zstyle ':completion:*' menu select",
      "integer x=0xAB",
    ],
    @["cont=\"a \\", "b\"", "for f in *.txt; do", "  echo $f", "done"],
  ]

proc fishCorpus(): seq[seq[string]] =
  ## Fish strings: double-quoted carry escapes; single-quoted are literal
  ## (no escape handling). Both must stay line-bounded.
  result = @[
    @["function greet", "    echo \"hello $argv\"", "end", "set name 'fish shell'"],
    @["set msg \"line one", "line two\"", "echo $msg", "set -l n 42"],
    @["set lit 'raw", "text'", "for i in (seq 1 3)", "    echo $i", "end"],
    @["# comment", "set x 0xFF", "string join \\n a b c", "test -f file.txt"],
  ]

proc tclCorpus(): seq[seq[string]] =
  ## Tcl double-quoted strings (the only quote form here) with escapes and
  ## multi-line continuation, plus `$var`/`${var}` references and braces.
  result = @[
    @["proc greet {name} {", "    puts \"Hello, $name\"", "}", "set x 0xFF"],
    @["set msg \"line one", "line two\"", "puts $msg", "incr count"],
    @["set s \"tab\\there\"", "set v ${some_var}", "if {$x > 0} {", "  puts yes", "}"],
    @["# a comment", "set cont \"a \\", "b\"", "foreach i {1 2 3} {puts $i}"],
  ]

proc goCorpus(): seq[seq[string]] =
  ## Go raw strings (backtick-delimited) span lines and resume through
  ## `g.state == gtLongStringLit`, so an edit to the opening backtick has to
  ## re-colour every line to the matching terminator. Also covers block
  ## comments across lines, interpreted strings with escapes (line-bounded),
  ## rune literals, and prefixed / hex-exponent numbers with `_` separators.
  result = @[
    @[
      "package main", "", "import \"fmt\"", "",
      "func main() { fmt.Println(\"hello\", 0xFF, 1_000) }",
    ],
    @[
      "package p", "var doc = `raw", "multi line", "value` + \"end\"",
      "const c = 0b1010",
    ],
    @[
      "/* block", " * comment body */", "func f() int { return 0o755 }", "",
      "// line comment",
    ],
    @[
      "package p", "var s = \"tab\\there\\x41\"", "var r = '\\u0041'",
      "for i := 0; i < 3; i++ { _ = i }", "var h = 0x1p-4",
    ],
    # Adversarial raw-string shapes: nested-looking backticks (Go does not
    # nest — the first ` closes), an empty raw string, and an opening
    # delimiter with nothing after it on its line.
    @["var a = `outer ` + \"middle\" + `still`", "var b = ``", "var c = `", "", "`"],
    # Interpreted strings are line-bounded, so a trailing backslash ends the
    # string and the next line resumes as code.
    @[
      "package p", "var s = \"trailing \\", "still code here", "var n = len(s)",
      "func g() {}",
    ],
  ]

proc luaCorpus(): seq[seq[string]] =
  ## Lua long brackets are the interesting part: `[[ ]]` strings and
  ## `--[==[ ]==]` comments span lines and resume through
  ## `lang.lua.longBracketLevel`, so an edit to the opening delimiter has to
  ## re-colour every line to the matching terminator. Also covers quoted
  ## strings with escapes (line-bounded), `::labels::`, hex/exponent numbers
  ## and the `#` length operator.
  result = @[
    @[
      "local function greet(name)", "  print(\"Hello, \" .. name)", "end",
      "greet('world')",
    ],
    @[
      "local doc = [[", "multi line", "long string]]", "local n = #doc",
      "print(n, 0xFF, 1e-3)",
    ],
    @[
      "--[==[ a long", "comment body ]] not the end", "]==]", "local t = {1, 2, 3}",
      "for i, v in ipairs(t) do print(i, v) end",
    ],
    @[
      "-- a line comment", "local s = \"tab\\there\\65\"", "::top::",
      "if x ~= nil then goto top end", "local h = 0x1p-4",
    ],
    # Adversarial long-bracket shapes: a `]]` that does not terminate a
    # levelled bracket, an empty long comment, an opening delimiter with
    # nothing after it on its line, and a nested-looking `[[` (Lua does not
    # nest — the first matching close wins).
    @[
      "local a = [=[ ]] still inside", "]] and still", "]=]", "local b = --[[]] 1",
      "local c = [[", "", "]]",
    ],
    # Quoted strings are line-bounded, so a trailing backslash ends the string
    # and the next line resumes as code. The `#!` shebang and a bare `#`
    # length operator share a first byte and must not be confused by an edit.
    @[
      "#!/usr/bin/lua", "local s = \"trailing \\", "still code here", "local n = #s",
      "return n",
    ],
  ]

proc commitEditMsgCorpus(): seq[seq[string]] =
  ## COMMIT_EDITMSG snippets exercising the per-file `commit.subjectSeen`
  ## flag and the mid-line Conventional Commits / trailer sub-token machines.
  ## `subjectSeen` only flips on the first non-comment, non-empty line, so
  ## edits that swap a subject line for a comment (or vice versa) must
  ## reparse the whole rest of the message — the class of divergence this
  ## fuzz targets. Snippets cover: full conventional (scope + bang), body +
  ## trailers, comment/status-marker prelude before the subject, comments and
  ## empty lines only (subject never appears), non-conventional plain
  ## subject, and subject immediately followed by a trailer.
  result = @[
    @[
      "feat(auth)!: rework login flow", "",
      "BREAKING CHANGE: sessions are now stateless.",
      "Signed-off-by: Dev <dev@example.com>",
    ],
    @[
      "fix(parser): handle empty input", "",
      "Previously crashed on an empty file; now returns Ok(None).", "Refs: #123",
      "Reviewed-by: Alice <alice@example.com>",
    ],
    @[
      "# Please enter the commit message for your changes.", "#", "# On branch develop",
      "# Changes to be committed:", "#\tmodified:   src/main.nim", "#",
      "docs: update readme",
    ],
    @[
      "#",
      "# Please enter the commit message. Lines starting with '#' will be ignored.",
      "#", "# On branch main", "# Untracked files:", "#\tnotes.txt",
    ],
    @[
      "Fix the offset regression", "",
      "The previous version dropped chars past the newline.",
      "Signed-off-by: Bob <bob@example.com>",
    ],
    @["chore: bump version", "Signed-off-by: Bot <bot@example.com>"],
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
  ##
  ## Char edit columns are RUNE positions, not byte positions. The real
  ## editor's buffer is `seq[Runes]`, so lines reaching the highlighter are
  ## always valid UTF-8; byte-positioned edits could split a multibyte
  ## sequence and create invalid UTF-8 that the editor cannot produce
  ## (and that the full-reparse path, which round-trips through `toRunes`,
  ## would see as a *different* string than the incremental path).
  ## For pure-ASCII lines `runeLen == len`, so existing seeds reproduce
  ## identically.
  for _ in 0 .. 9:
    let kind = EditKind(rng.rand(int(EditKind.high)))
    case kind
    of ekInsertChar:
      if buf.len == 0:
        continue
      let row = rng.rand(buf.high)
      let col = rng.rand(buf[row].runeLen + 1) # inclusive end (append allowed)
      return Edit(kind: ekInsertChar, row: row, col: col, text: randomChar(rng))
    of ekDeleteChar:
      if buf.len == 0:
        continue
      let row = rng.rand(buf.high)
      if buf[row].len == 0:
        continue
      let col = rng.rand(buf[row].runeLen - 1)
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
  ## `updateHighlightIncremental`. Char edit columns are rune positions
  ## (see `pickEdit`); they are converted to byte offsets here so multibyte
  ## sequences are never split.
  case e.kind
  of ekInsertChar:
    let line = buf[e.row]
    let byteCol =
      if e.col >= line.runeLen:
        line.len # append
      else:
        line.runeOffset(e.col)
    # substr is bounds-safe for the suffix (byteCol may equal line.len for append).
    buf[e.row] = line.substr(0, byteCol - 1) & e.text & line.substr(byteCol)
    e.row
  of ekDeleteChar:
    let line = buf[e.row]
    let byteCol = line.runeOffset(e.col)
    let runeSize = line.runeLenAt(byteCol)
    buf[e.row] = line.substr(0, byteCol - 1) & line.substr(byteCol + runeSize)
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
  ##
  ## Columns are RUNE positions: ColorSegment columns count one per rune, so
  ## iterating bytes would misalign on multibyte lines (a divergence at a
  ## multibyte column could be masked by a space at the same BYTE index, and
  ## the whitespace exemption would miss spaces whose byte index holds a
  ## UTF-8 continuation byte).
  for row in 0 ..< buf.len:
    let runes = buf[row].toRunes
    for col in 0 ..< runes.len:
      if runes[col] == Rune(' ') or runes[col] == Rune('\t'):
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
    var ih =
      IncrementalHighlight(segments: segs0, lineStates: LineStateCache(states: states0))

    var history: seq[Edit]
    let nEdits = 5 + rng.rand(8) # 5..12 inclusive

    try:
      for _ in 0 ..< nEdits:
        let e = pickEdit(buf, corpus, rng)
        history.add e
        let changedLine = applyEdit(buf, e)

        let getLine = proc(i: int): string =
          buf[i]
        updateHighlightIncremental(buf.len, getLine, ih, changedLine, @[], lang)

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

  test "JSX: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langJsx, jsxCorpus(), iters, baseSeed)

  test "TSX: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langTsx, tsxCorpus(), iters, baseSeed)

  test "Markdown: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langMarkdown, markdownCorpus(), iters, baseSeed)

  test "Python: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langPython, pythonCorpus(), iters, baseSeed)

  test "LaTeX: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langLatex, latexCorpus(), iters, baseSeed)

  test "Lisp: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langLisp, lispCorpus(), iters, baseSeed)

  test "Haskell: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langHaskell, haskellCorpus(), iters, baseSeed)

  test "C: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langC, cCorpus(), iters, baseSeed)

  test "C++: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langCpp, cppCorpus(), iters, baseSeed)

  test "HTML: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langHtml, htmlCorpus(), iters, baseSeed)

  test "XML: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langXml, xmlCorpus(), iters, baseSeed)

  test "Astro: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langAstro, astroCorpus(), iters, baseSeed)

  test "YAML: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langYaml, yamlCorpus(), iters, baseSeed)

  test "Shell: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langShell, shellCorpus(), iters, baseSeed)

  test "Zsh: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langZsh, zshCorpus(), iters, baseSeed)

  test "Fish: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langFish, fishCorpus(), iters, baseSeed)

  test "Tcl: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langTcl, tclCorpus(), iters, baseSeed)

  test "Go: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langGo, goCorpus(), iters, baseSeed)

  test "Lua: incremental output matches full reparse under random edits":
    check runFuzz(SourceLanguage.langLua, luaCorpus(), iters, baseSeed)

  test "CommitEditMsg: incremental output matches full reparse under random edits":
    check runFuzz(
      SourceLanguage.langCommitEditMsg, commitEditMsgCorpus(), iters, baseSeed
    )

# Deterministic chunk-boundary tests
#
# The fuzz corpus buffers all stay well under 100 lines, so the random walk
# is structurally unable to reach the chunk boundaries of the incremental
# machinery: `updateHighlightIncremental` re-parses in 100-line chunks with a
# tokenizer-state handoff in between, plus an early convergence check.
# Multi-line constructs spanning those boundaries are pinned here instead,
# using XML, whose CDATA sections and comments carry plain `g.state` across
# lines.

proc checkChunkEquivalence(
    buf: seq[string], incr, full: Highlight, what: string
): bool =
  let (ok, r, c) = firstDivergence(buf, incr, full)
  if not ok:
    echo &"{what}: divergence at row={r} col={c}: " &
      &"incr={incr.getColorPair(r, c)} full={full.getColorPair(r, c)}"
  ok

suite "Incremental Highlight Chunk Boundary":
  test "XML: opening a >100-line CDATA section hands state across the chunk boundary":
    # Line 2 initially holds plain markup; the edit replaces it with
    # `<![CDATA[`, so the reparse runs from the top, ends chunk 1 (lines
    # 0..99) mid-CDATA and must hand `gtCData` over to chunk 2 for lines
    # 100..150 to come out as raw data instead of markup.
    var buf = @["<?xml version=\"1.0\"?>", "<data>", "<open-me>"]
    for i in 3 .. 149:
      buf.add(&"  <item id=\"{i}\">value &amp; more</item>")
    buf.add("]]>")
    buf.add("</data>")

    let lang = SourceLanguage.langXml
    let (segs0, states0) =
      initHighlightIncremental(buf, 0, buf.high, TokenizerState(), @[], lang)
    var ih =
      IncrementalHighlight(segments: segs0, lineStates: LineStateCache(states: states0))

    buf[2] = "<![CDATA["
    let getLine = proc(i: int): string =
      buf[i]
    updateHighlightIncremental(buf.len, getLine, ih, 2, @[], lang)

    check checkChunkEquivalence(
      buf, Highlight(colorSegments: ih.segments), fullHighlight(buf, lang), "CDATA open"
    )

  test "XML: edit >100 lines below a comment opening is not skipped by convergence":
    # Regression test for the convergence guard: the MultiLineKinds rewind
    # moves reparseStart to the comment opening (line 0), more than a chunk
    # above the edit. Chunk 1 (lines 0..99) re-parses identical pre-edit
    # content, so its end state matches the cache; the convergence check
    # must not break before the reparse has passed the changed line 110.
    var buf = @["<!-- comment opens"]
    for i in 1 .. 120:
      buf.add(&"   comment body line {i}")
    buf.add("-->")
    buf.add("<root attr=\"v\"/>")

    let lang = SourceLanguage.langXml
    let (segs0, states0) =
      initHighlightIncremental(buf, 0, buf.high, TokenizerState(), @[], lang)
    var ih =
      IncrementalHighlight(segments: segs0, lineStates: LineStateCache(states: states0))

    # Close the comment early: everything at and below line 110 changes
    # color from comment to markup — but only if the reparse reaches it.
    buf[110] = "--> <root attr=\"v\">"
    let getLine = proc(i: int): string =
      buf[i]
    updateHighlightIncremental(buf.len, getLine, ih, 110, @[], lang)

    check checkChunkEquivalence(
      buf,
      Highlight(colorSegments: ih.segments),
      fullHighlight(buf, lang),
      "comment early close",
    )

# Deterministic line-bounded string regression
#
# A double-quoted string opened on one line and closed on the next must be
# two line-bounded tokens, not one multi-line `gtStringLit` whose interior
# boundary state (gtNone) is wrong for resume. With the multi-line token,
# editing a line below the continuation reparses it from gtNone as code, so
# the incremental color (identifier) diverges from full reparse (stringLit).
# Reverting the `\n`/`\r` break in syntax_shell/zsh/fish/tcl fails this.

suite "Incremental Highlight Line-Bounded Strings":
  proc checkResumeEquivalence(
      lines: seq[string],
      editRow: int,
      editText: string,
      lang: SourceLanguage,
      what: string,
  ): bool =
    ## Build the incremental cache, edit one line, then assert the incremental
    ## colors match a full reparse. `editRow` is chosen >= 2 below the line
    ## that opens the multi-line construct so the reparse enters the spanned
    ## lines from their cached boundary state.
    var buf = lines
    let (segs0, states0) =
      initHighlightIncremental(buf, 0, buf.high, TokenizerState(), @[], lang)
    var ih =
      IncrementalHighlight(segments: segs0, lineStates: LineStateCache(states: states0))

    buf[editRow] = editText
    let getLine = proc(i: int): string =
      buf[i]
    updateHighlightIncremental(buf.len, getLine, ih, editRow, @[], lang)

    checkChunkEquivalence(
      buf, Highlight(colorSegments: ih.segments), fullHighlight(buf, lang), what
    )

  const MultiLineString =
    @["echo \"first part", "second part\"", "ls -la", "pwd", "echo done"]

  # A string whose last content is an escape sequence ending exactly at EOL
  # (`"a \6`). The escape parks gtStringLit with pos on the newline; the next
  # resume must not emit an empty token (it used to trip the empty-token
  # assert in full and incremental parse alike). The string is line-bounded,
  # so the lines below resume as code.
  const EscapeBeforeEol = @["x=\"a \\6", "more\"", "ls -la", "pwd", "echo done"]

  test "Shell: editing below a two-line string resumes line-bounded":
    check checkResumeEquivalence(MultiLineString, 3, "cd /tmp", langShell, "shell")

  test "Zsh: editing below a two-line string resumes line-bounded":
    check checkResumeEquivalence(MultiLineString, 3, "cd /tmp", langZsh, "zsh")

  test "Fish: editing below a two-line string resumes line-bounded":
    check checkResumeEquivalence(MultiLineString, 3, "cd /tmp", langFish, "fish")

  test "Tcl: editing below a two-line string resumes line-bounded":
    check checkResumeEquivalence(MultiLineString, 3, "cd /tmp", langTcl, "tcl")

  test "Shell: escape ending at EOL does not emit an empty token":
    check checkResumeEquivalence(EscapeBeforeEol, 3, "cd /tmp", langShell, "shell esc")

  test "Zsh: escape ending at EOL does not emit an empty token":
    check checkResumeEquivalence(EscapeBeforeEol, 3, "cd /tmp", langZsh, "zsh esc")

  test "Fish: escape ending at EOL does not emit an empty token":
    check checkResumeEquivalence(EscapeBeforeEol, 3, "cd /tmp", langFish, "fish esc")

  test "Tcl: escape ending at EOL does not emit an empty token":
    check checkResumeEquivalence(EscapeBeforeEol, 3, "cd /tmp", langTcl, "tcl esc")

  test "Go: editing below a multi-line raw string resumes inside it":
    let buf = @["var doc = `", "line one", "line two", "line three`", "var _ = doc"]
    check checkResumeEquivalence(buf, 2, "edited line", langGo, "go raw string")

  test "Go: editing below a multi-line block comment resumes inside it":
    let buf = @["/* opens", "still body", "more body", "still body */", "var x = 1"]
    check checkResumeEquivalence(buf, 2, "edited line", langGo, "go block comment")

  test "Go: escape ending at EOL does not emit an empty token":
    let buf = @["var s = \"a \\", "more\"", "var n = len(s)", "var _ = n", "var _ = s"]
    check checkResumeEquivalence(buf, 3, "var y = 1", langGo, "go esc")

  test "Lua: editing inside a levelled long comment keeps the bracket level":
    # The reparse enters line 3 from its cached boundary state, which must
    # still carry `longBracketLevel == 2` — otherwise the `]]` on line 2 is
    # mistaken for the terminator and everything below is re-coloured as code.
    let buf =
      @["--[==[ open", "a ]] not the end", "b ]] still not", "]==]", "local x = 1"]
    check checkResumeEquivalence(buf, 2, "c ]=] nor this", langLua, "lua long comment")

  test "Lua: editing below a multi-line long string resumes inside it":
    let buf = @["local doc = [[", "line one", "line two", "line three]]", "print(doc)"]
    check checkResumeEquivalence(buf, 2, "edited line", langLua, "lua long string")

  test "Lua: escape ending at EOL does not emit an empty token":
    let buf = @["local s = \"a \\", "more\"", "local n = #s", "print(n)", "return s"]
    check checkResumeEquivalence(buf, 3, "print(1)", langLua, "lua esc")

  test "Tcl: an unclosed ${ brace reference is line-bounded":
    # `${some_var` (no closing brace) must not swallow the newline into one
    # gtSpecialVar token; the lines below resume as code, not variable.
    let buf = @["set v ${some_var", "set cont value", "puts hi", "incr n", "exit"]
    check checkResumeEquivalence(buf, 3, "set n 0", langTcl, "tcl brace")

# Monotonic-advance guard (tokenizer.nim getNextToken)
#
# A non-EOF token must make progress: consume input (`pos` advances) or, for
# YAML's zero-consume document/scalar transitions, change `state`. The guard
# forces gtEof when it does neither, so the consumer loops cannot spin under
# `-d:danger`, where the per-tokenizer empty-token `assert` is compiled out.
# These pin both halves: the guard must NOT fire on legitimate state-only
# progress, and progress must be monotonic so the loop always terminates.

proc tokenizesMonotonically(lang: SourceLanguage, src: string, maxSteps: int): bool =
  ## Drive getNextToken to gtEof, checking forward progress at every step
  ## (`pos` advanced or `state` changed). Returns whether it terminated within
  ## `maxSteps`; a guard regression fails this finite bound instead of hanging.
  var g: GeneralTokenizer
  g.initGeneralTokenizer(src)
  for _ in 0 ..< maxSteps:
    let
      prevPos = g.pos
      prevState = g.state
    g.getNextToken(lang)
    if g.kind == gtEof:
      return true
    check (g.pos > prevPos or g.state != prevState)
  false

suite "Monotonic-advance guard":
  test "YAML zero-consume advances by state change, not pos (guard does not fire)":
    # The document-start arm emits gtNone with length 0 and flips gtEof->gtOther
    # (syntax_yaml.nim). The guard must let it through on the state change; a
    # length-only guard would force gtEof here and drop the rest of the line.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.getNextToken(langYaml)
    check g.kind == gtNone # not gtEof: the guard did not fire
    check g.length == 0 # zero-consume
    check g.state == gtOther # progress came from the state flip
    # The next call now advances `pos` and parses the key.
    let before = g.pos
    g.getNextToken(langYaml)
    check g.pos > before

  test "every tokenizer makes monotonic progress over the corpus (terminates)":
    let corpora: seq[(SourceLanguage, seq[seq[string]])] = @[
      (SourceLanguage.langYaml, yamlCorpus()),
      (SourceLanguage.langRust, rustCorpus()),
      (SourceLanguage.langNim, nimCorpus()),
      (SourceLanguage.langJavaScript, javascriptCorpus()),
      (SourceLanguage.langTypeScript, typescriptCorpus()),
      (SourceLanguage.langJsx, jsxCorpus()),
      (SourceLanguage.langTsx, tsxCorpus()),
      (SourceLanguage.langMarkdown, markdownCorpus()),
      (SourceLanguage.langPython, pythonCorpus()),
      (SourceLanguage.langLatex, latexCorpus()),
      (SourceLanguage.langLisp, lispCorpus()),
      (SourceLanguage.langC, cCorpus()),
      (SourceLanguage.langCpp, cppCorpus()),
      (SourceLanguage.langHtml, htmlCorpus()),
      (SourceLanguage.langXml, xmlCorpus()),
      (SourceLanguage.langAstro, astroCorpus()),
      (SourceLanguage.langShell, shellCorpus()),
      (SourceLanguage.langZsh, zshCorpus()),
      (SourceLanguage.langFish, fishCorpus()),
      (SourceLanguage.langTcl, tclCorpus()),
      (SourceLanguage.langLua, luaCorpus()),
      (SourceLanguage.langGo, goCorpus()),
    ]
    for (lang, corpus) in corpora:
      for buf in corpus:
        let src = buf.join("\n")
        # `2 * len` headroom for the few zero-consume steps; a true infinite
        # loop blows any finite bound.
        check tokenizesMonotonically(lang, src, 2 * src.len + 64)
