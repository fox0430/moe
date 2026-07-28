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

import std/[unittest, algorithm, random, sequtils, strutils]

import ../src/moepkg/syntax/[tokenizer, syntax_go]

proc tokens(code: string): seq[tuple[kind: TokenClass, text: string]] =
  ## Tokenize `code` as Go and return every non-whitespace token.
  var g: GeneralTokenizer
  g.initGeneralTokenizer(code)
  while true:
    g.getNextToken(langGo)
    if g.kind == gtEof:
      break
    if g.kind != gtWhitespace:
      result.add (g.kind, code[g.start ..< g.start + g.length])

proc firstToken(code: string): tuple[kind: TokenClass, text: string] =
  let ts = tokens(code)
  doAssert ts.len > 0, "no token produced for: " & code
  ts[0]

suite "syntax_go - keyword tables":
  test "every table is sorted (isKeyword uses a binary search)":
    check goKeywords.toSeq.isSorted
    check goBooleans.toSeq.isSorted
    check goBuiltins.toSeq.isSorted
    check goSpecialVars.toSeq.isSorted

  test "keywords cover control flow and declarations":
    for w in [
      "break", "case", "chan", "const", "continue", "default", "defer", "else",
      "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map",
      "package", "range", "return", "select", "struct", "switch", "type", "var",
    ]:
      check w in goKeywords

  test "booleans and nil are not in the keyword table":
    for w in ["true", "false", "nil"]:
      check w in goBooleans
      check w notin goKeywords

  test "iota is a special variable, not a keyword":
    check "iota" in goSpecialVars
    check "iota" notin goKeywords

  test "builtins cover predeclared types and functions":
    for w in [
      "int", "string", "byte", "rune", "error", "any", "len", "cap", "make", "new",
      "append", "print", "println", "panic", "recover",
    ]:
      check w in goBuiltins

suite "syntax_go - identifiers and keywords":
  test "keyword":
    check firstToken("func main()") == (gtKeyword, "func")

  test "boolean literal":
    check firstToken("true") == (gtBoolean, "true")
    check firstToken("nil") == (gtBoolean, "nil")

  test "special variable":
    check firstToken("iota") == (gtSpecialVar, "iota")

  test "builtin":
    check firstToken("len(x)") == (gtBuiltin, "len")
    check firstToken("string") == (gtBuiltin, "string")

  test "plain identifier":
    check firstToken("myVar") == (gtIdentifier, "myVar")

  test "a keyword prefix is not a keyword":
    check firstToken("funcy") == (gtIdentifier, "funcy")

suite "syntax_go - comments":
  test "line comment runs to end of line":
    check tokens("// hi\nvar x") ==
      @[(gtComment, "// hi"), (gtKeyword, "var"), (gtIdentifier, "x")]

  test "block comment on one line":
    check firstToken("/* hi */ x") == (gtLongComment, "/* hi */")

  test "block comment spans lines":
    check firstToken("/* a\nb\nc */ x") == (gtLongComment, "/* a\nb\nc */")

  test "unterminated block comment consumes the rest of the buffer":
    check tokens("/* a\nb") == @[(gtLongComment, "/* a\nb")]

  test "an operator does not swallow the `//` comment marker":
    # `/=` is a valid operator run — but `//` must open a comment. Without the
    # break in the operator loop, `x<//comment` would consume `<//` as one op.
    check tokens("x<//comment") ==
      @[(gtIdentifier, "x"), (gtOperator, "<"), (gtComment, "//comment")]
    check tokens("x>//comment") ==
      @[(gtIdentifier, "x"), (gtOperator, ">"), (gtComment, "//comment")]

  test "an operator does not swallow the `/*` block comment marker":
    check tokens("x</*c*/y") ==
      @[
        (gtIdentifier, "x"),
        (gtOperator, "<"),
        (gtLongComment, "/*c*/"),
        (gtIdentifier, "y"),
      ]

suite "syntax_go - strings":
  test "interpreted string":
    check firstToken("\"hello\"") == (gtStringLit, "\"hello\"")

  test "escape is emitted as its own token":
    check tokens("\"a\\tb\"") ==
      @[(gtStringLit, "\"a"), (gtEscapeSequence, "\\t"), (gtStringLit, "b\"")]

  test "plain chars between two escapes stay gtStringLit":
    # Regression parallel to the Lua fix: the string-resume path must not
    # overwrite `kind` to gtEscapeSequence for the run before the second `\`.
    check tokens("\"a\\tXYZ\\nb\"") ==
      @[
        (gtStringLit, "\"a"),
        (gtEscapeSequence, "\\t"),
        (gtStringLit, "XYZ"),
        (gtEscapeSequence, "\\n"),
        (gtStringLit, "b\""),
      ]

  test "hex, unicode-4, unicode-8 escapes":
    check tokens("\"\\x41\"") ==
      @[(gtStringLit, "\""), (gtEscapeSequence, "\\x41"), (gtStringLit, "\"")]
    check tokens("\"\\u0041\"") ==
      @[(gtStringLit, "\""), (gtEscapeSequence, "\\u0041"), (gtStringLit, "\"")]
    check tokens("\"\\U00000041\"") ==
      @[(gtStringLit, "\""), (gtEscapeSequence, "\\U00000041"), (gtStringLit, "\"")]

  test "octal escape consumes at most three digits":
    check tokens("\"\\0778\"") ==
      @[(gtStringLit, "\""), (gtEscapeSequence, "\\077"), (gtStringLit, "8\"")]

  test "an escaped quote does not terminate the string":
    check tokens("\"a\\\"b\"") ==
      @[(gtStringLit, "\"a"), (gtEscapeSequence, "\\\""), (gtStringLit, "b\"")]

  test "an escaped backslash is one two-byte escape, not two singles":
    check tokens("\"a\\\\b\"") ==
      @[(gtStringLit, "\"a"), (gtEscapeSequence, "\\\\"), (gtStringLit, "b\"")]

  test "every Go escape shape in one string":
    # Regression: keep every escape form the tokenizer recognises exercised in
    # a single string, so a change to the resume path that breaks one form
    # (e.g. `\"` misread as the terminator, `\\` split into two escapes) trips
    # here rather than only on the isolated per-form tests.
    const code = "\"tab\\t nl\\n q\\\" bs\\\\ hex\\x41 u\\u0041 U\\U0001F600\""
    check tokens(code) ==
      @[
        (gtStringLit, "\"tab"),
        (gtEscapeSequence, "\\t"),
        (gtStringLit, " nl"),
        (gtEscapeSequence, "\\n"),
        (gtStringLit, " q"),
        (gtEscapeSequence, "\\\""),
        (gtStringLit, " bs"),
        (gtEscapeSequence, "\\\\"),
        (gtStringLit, " hex"),
        (gtEscapeSequence, "\\x41"),
        (gtStringLit, " u"),
        (gtEscapeSequence, "\\u0041"),
        (gtStringLit, " U"),
        (gtEscapeSequence, "\\U0001F600"),
        (gtStringLit, "\""),
      ]

  test "interpreted strings are line-bounded":
    check tokens("\"oops\nvar x") ==
      @[(gtStringLit, "\"oops"), (gtKeyword, "var"), (gtIdentifier, "x")]

  test "raw string on one line":
    check firstToken("`hello`") == (gtLongStringLit, "`hello`")

  test "raw string spans lines":
    check firstToken("`a\nb`") == (gtLongStringLit, "`a\nb`")

  test "raw string keeps `\\` as a literal byte, not an escape":
    check tokens("`a\\tb`") == @[(gtLongStringLit, "`a\\tb`")]

  test "unclosed raw string yields before a ``` fence at the next line":
    # scanRawString must stop past the newline so an outer markdown tokenizer
    # can close its code block on the fence instead of losing the first
    # backtick to the raw string body.
    let src = "`unclosed\n```\n"
    var g: GeneralTokenizer
    g.initGeneralTokenizer(src)
    g.getNextToken(langGo)
    check g.kind == gtLongStringLit
    check g.state == gtLongStringLit
    check src[g.start ..< g.start + g.length] == "`unclosed\n"

  test "``` fence detection also applies after up to 3 leading spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`x\n   ```\n")
    g.getNextToken(langGo)
    check g.kind == gtLongStringLit
    check g.state == gtLongStringLit

  test "rune literal":
    check firstToken("'a'") == (gtCharLit, "'a'")
    check firstToken("'\\n'") == (gtCharLit, "'\\n'")

  test "rune literal is line-bounded":
    check tokens("'oops\nvar x") ==
      @[(gtCharLit, "'oops"), (gtKeyword, "var"), (gtIdentifier, "x")]

suite "syntax_go - numbers":
  test "decimal":
    check firstToken("42") == (gtDecNumber, "42")

  test "float":
    check firstToken("3.14") == (gtFloatNumber, "3.14")

  test "leading dot float":
    check firstToken(".5") == (gtFloatNumber, ".5")

  test "exponent":
    check firstToken("1e-3") == (gtFloatNumber, "1e-3")

  test "hex":
    check firstToken("0xFF") == (gtHexNumber, "0xFF")

  test "hex float with binary exponent":
    check firstToken("0x1.8p-4") == (gtFloatNumber, "0x1.8p-4")

  test "binary":
    check firstToken("0b1010") == (gtBinNumber, "0b1010")

  test "octal with 0o prefix":
    check firstToken("0o755") == (gtOctNumber, "0o755")

  test "digit separators are absorbed":
    check firstToken("1_000_000") == (gtDecNumber, "1_000_000")
    check firstToken("0x_DEAD_BEEF") == (gtHexNumber, "0x_DEAD_BEEF")

  test "imaginary suffix is part of the number":
    check firstToken("1i") == (gtDecNumber, "1i")
    check firstToken("1.5i") == (gtFloatNumber, "1.5i")

suite "syntax_go - operators and punctuation":
  test "a single dot is punctuation, `...` is an operator":
    check tokens("a.b")[1] == (gtPunctuation, ".")
    check firstToken("...") == (gtOperator, "...")

  test "an operator does not swallow a following dot":
    check tokens("-.5") == @[(gtOperator, "-"), (gtFloatNumber, ".5")]
    check tokens("x=.5") ==
      @[(gtIdentifier, "x"), (gtOperator, "="), (gtFloatNumber, ".5")]

  test "channel operator is one token":
    check tokens("c<-x") ==
      @[(gtIdentifier, "c"), (gtOperator, "<-"), (gtIdentifier, "x")]

  test "short variable declaration `:=`":
    check tokens("i:=0") ==
      @[(gtIdentifier, "i"), (gtOperator, ":="), (gtDecNumber, "0")]

  test "a bare colon is punctuation":
    check tokens("case 1:")[2] == (gtPunctuation, ":")

  test "multi-char operators still lex as one token":
    for op in ["==", "!=", "<=", ">=", "<<", ">>", "&&", "||", "&^"]:
      check tokens("a " & op & " b")[1] == (gtOperator, op)

  test "brackets are punctuation":
    check tokens("[]int{1}")[0] == (gtPunctuation, "[")
    check tokens("[]int{1}")[1] == (gtPunctuation, "]")
    check tokens("[]int{1}")[3] == (gtPunctuation, "{")

suite "syntax_go - structural invariants":
  ## Random-input invariants that hold regardless of expected token output —
  ## catches the class of bug where both incremental and full reparse agree
  ## on wrong output, which the fuzz differential cannot see.

  proc randomGoSource(rng: var Rand, minLen, maxLen: int): string =
    # Small alphabet biased toward the bug-adjacent shapes: comment markers,
    # escape backslashes, quotes (all three), operator chars, dots and colons.
    const alphabet = "/`\"'\\<>=!+-*&|^%:.,()[]{} \tabc012"
    let n = minLen + rng.rand(maxLen - minLen)
    result = newStringOfCap(n)
    for _ in 0 ..< n:
      result.add(alphabet[rng.rand(alphabet.high)])

  test "no gtOperator token contains `//` (would open a comment)":
    for src in ["x<//c", "y>//c", "a=//c", "b/=1", "n= /1", "x</y"]:
      for (kind, text) in tokens(src):
        if kind == gtOperator:
          check "//" notin text

  test "no gtOperator token contains `/*` (would open a block comment)":
    for src in ["x</*c*/y", "a=/*hi*/b", "*/*x*/y"]:
      for (kind, text) in tokens(src):
        if kind == gtOperator:
          check "/*" notin text

  test "every gtEscapeSequence token starts with `\\`":
    for src in ["\"a\\tb\"", "\"a\\tXYZ\\nb\"", "'x\\ny'", "\"\\u0041\"", "\"\\0778\""]:
      for (kind, text) in tokens(src):
        if kind == gtEscapeSequence:
          check text.len >= 1
          check text[0] == '\\'

  test "random inputs satisfy the operator/escape invariants":
    var rng = initRand(0xB0BAF37Cu64.int64)
    for _ in 0 ..< 500:
      let src = randomGoSource(rng, 4, 40)
      for (kind, text) in tokens(src):
        case kind
        of gtOperator:
          check "//" notin text
          check "/*" notin text
        of gtEscapeSequence:
          check text.len >= 1
          check text[0] == '\\'
        else:
          discard

suite "syntax_go - dispatch":
  test "getSourceLanguage resolves Go":
    check getSourceLanguage("Go") == langGo
    check getSourceLanguage("go") == langGo
    check getSourceLanguage("golang") == langGo

  test "full tokenization of a small program":
    const Code = """
package main

import "fmt"

/* a doc comment
   spanning lines */
func main() {
  const msg = `raw
string`
  fmt.Println(msg, 0xFF, 1_000)
}
"""
    for t in tokens(Code):
      check t.kind != gtNone
