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

import ../src/moepkg/syntax/[tokenizer, syntax_lua]

proc tokens(code: string): seq[tuple[kind: TokenClass, text: string]] =
  ## Tokenize `code` as Lua and return every non-whitespace token.
  var g: GeneralTokenizer
  g.initGeneralTokenizer(code)
  while true:
    g.getNextToken(langLua)
    if g.kind == gtEof:
      break
    if g.kind != gtWhitespace:
      result.add (g.kind, code[g.start ..< g.start + g.length])

proc firstToken(code: string): tuple[kind: TokenClass, text: string] =
  let ts = tokens(code)
  doAssert ts.len > 0, "no token produced for: " & code
  ts[0]

suite "syntax_lua - keyword tables":
  test "every table is sorted (isKeyword uses a binary search)":
    check luaKeywords.toSeq.isSorted
    check luaBooleans.toSeq.isSorted
    check luaBuiltins.toSeq.isSorted
    check luaSpecialVars.toSeq.isSorted

  test "keywords cover control flow and definitions":
    for w in [
      "and", "break", "do", "else", "elseif", "end", "for", "function", "goto", "if",
      "in", "local", "not", "or", "repeat", "return", "then", "until", "while",
    ]:
      check w in luaKeywords

  test "booleans and nil are not in the keyword table":
    for w in ["true", "false", "nil"]:
      check w in luaBooleans
      check w notin luaKeywords

  test "builtins cover the standard library":
    for w in ["print", "pairs", "ipairs", "require", "setmetatable", "table", "string"]:
      check w in luaBuiltins

suite "syntax_lua - identifiers and keywords":
  test "keyword":
    check firstToken("local x = 1") == (gtKeyword, "local")

  test "boolean literal":
    check firstToken("true") == (gtBoolean, "true")
    check firstToken("nil") == (gtBoolean, "nil")

  test "builtin":
    check firstToken("print(1)") == (gtBuiltin, "print")

  test "special variable":
    check firstToken("_G") == (gtSpecialVar, "_G")
    check firstToken("_ENV") == (gtSpecialVar, "_ENV")

  test "`self` is a convention, not a reserved name":
    # `self` is only the implicit first parameter of `obj:m()` — plain code
    # may use it as an ordinary local, and colouring it as gtSpecialVar
    # everywhere is misleading.
    check firstToken("self") == (gtIdentifier, "self")

  test "plain identifier":
    check firstToken("myVar") == (gtIdentifier, "myVar")

  test "a keyword prefix is not a keyword":
    check firstToken("endless") == (gtIdentifier, "endless")

suite "syntax_lua - comments":
  test "line comment runs to end of line":
    check tokens("-- hi\nlocal x") ==
      @[(gtComment, "-- hi"), (gtKeyword, "local"), (gtIdentifier, "x")]

  test "triple dash is still a line comment, not a long comment":
    check firstToken("---[[ not long") == (gtComment, "---[[ not long")

  test "long comment on one line":
    check firstToken("--[[ hi ]] x") == (gtLongComment, "--[[ hi ]]")

  test "long comment spans lines":
    check firstToken("--[[ a\nb\nc ]] x") == (gtLongComment, "--[[ a\nb\nc ]]")

  test "levelled long comment ignores a shorter terminator":
    check firstToken("--[==[ a ]] b ]==] c") == (gtLongComment, "--[==[ a ]] b ]==]")

  test "unterminated long comment consumes the rest of the buffer":
    check tokens("--[[ a\nb") == @[(gtLongComment, "--[[ a\nb")]

  test "a bare dash is an operator":
    check firstToken("a - b") == (gtIdentifier, "a")
    check tokens("a - b")[1] == (gtOperator, "-")

  test "an operator does not swallow the `--` comment marker":
    # Regression: the fallback operator branch used to consume `-` greedily,
    # eating the `--` that opens the comment.
    check tokens("x<--comment") ==
      @[(gtIdentifier, "x"), (gtOperator, "<"), (gtComment, "--comment")]
    check tokens("x>--comment") ==
      @[(gtIdentifier, "x"), (gtOperator, ">"), (gtComment, "--comment")]
    check tokens("a==--comment") ==
      @[(gtIdentifier, "a"), (gtOperator, "=="), (gtComment, "--comment")]
    check tokens("a~=--comment") ==
      @[(gtIdentifier, "a"), (gtOperator, "~="), (gtComment, "--comment")]

suite "syntax_lua - strings":
  test "double-quoted string":
    check firstToken("\"hello\"") == (gtStringLit, "\"hello\"")

  test "single-quoted string":
    check firstToken("'hello'") == (gtStringLit, "'hello'")

  test "escape is emitted as its own token":
    check tokens("\"a\\tb\"") ==
      @[(gtStringLit, "\"a"), (gtEscapeSequence, "\\t"), (gtStringLit, "b\"")]

  test "plain chars between two escapes stay gtStringLit":
    # Regression: the string-resume path used to overwrite `kind` to
    # gtEscapeSequence for the whole span up to the second `\`.
    check tokens("\"a\\tXYZ\\nb\"") ==
      @[
        (gtStringLit, "\"a"),
        (gtEscapeSequence, "\\t"),
        (gtStringLit, "XYZ"),
        (gtEscapeSequence, "\\n"),
        (gtStringLit, "b\""),
      ]

  test "decimal escape consumes at most three digits":
    check tokens("\"\\1234\"") ==
      @[(gtStringLit, "\""), (gtEscapeSequence, "\\123"), (gtStringLit, "4\"")]

  test "unicode escape":
    check tokens("\"\\u{1F600}\"") ==
      @[(gtStringLit, "\""), (gtEscapeSequence, "\\u{1F600}"), (gtStringLit, "\"")]

  test "quoted strings are line-bounded":
    check tokens("\"oops\nlocal x") ==
      @[(gtStringLit, "\"oops"), (gtKeyword, "local"), (gtIdentifier, "x")]

  test "the other quote inside a string is not a terminator":
    check firstToken("\"it's\"") == (gtStringLit, "\"it's\"")

  test "long string":
    check firstToken("[[hello]]") == (gtLongStringLit, "[[hello]]")

  test "long string spans lines":
    check firstToken("[[a\nb]]") == (gtLongStringLit, "[[a\nb]]")

  test "levelled long string":
    check firstToken("[==[ ]] ]==]") == (gtLongStringLit, "[==[ ]] ]==]")

  test "a bracket that is not a long bracket is punctuation":
    check firstToken("t[1]") == (gtIdentifier, "t")
    check tokens("t[1]")[1] == (gtPunctuation, "[")

suite "syntax_lua - numbers":
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

suite "syntax_lua - operators and punctuation":
  test "concat is an operator, a single dot is punctuation":
    check tokens("a .. b")[1] == (gtOperator, "..")
    check tokens("a.b")[1] == (gtPunctuation, ".")

  test "an operator does not swallow a following dot":
    check tokens("-.5") == @[(gtOperator, "-"), (gtFloatNumber, ".5")]
    check tokens("x=.5") ==
      @[(gtIdentifier, "x"), (gtOperator, "="), (gtFloatNumber, ".5")]
    check tokens("a==.5") ==
      @[(gtIdentifier, "a"), (gtOperator, "=="), (gtFloatNumber, ".5")]
    check tokens("f=..x") ==
      @[(gtIdentifier, "f"), (gtOperator, "="), (gtOperator, ".."), (gtIdentifier, "x")]
    check tokens("y=obj:m()")[3] == (gtPunctuation, ":")

  test "multi-char operators still lex as one token":
    for op in ["==", "~=", "<=", ">=", "//", "<<", ">>"]:
      check tokens("a " & op & " b")[1] == (gtOperator, op)

  test "vararg":
    check firstToken("...") == (gtOperator, "...")

  test "length operator":
    check firstToken("#t") == (gtOperator, "#")

  test "shebang is a comment":
    check firstToken("#!/usr/bin/lua\nlocal x") == (gtComment, "#!/usr/bin/lua")

  test "goto label":
    check firstToken("::top::") == (gtLabel, "::top::")

  test "a method call colon is punctuation":
    check tokens("obj:m()")[1] == (gtPunctuation, ":")

suite "syntax_lua - structural invariants":
  ## The incremental-vs-full fuzz test in test_highlight_fuzz.nim compares two
  ## paths that share this tokenizer, so any bug where both paths agree on the
  ## wrong output is invisible to it (Findings 1/2 of the code review were
  ## exactly this shape). The tests here check *structural* invariants of the
  ## token stream — properties that hold regardless of the reference output —
  ## so they can catch that class of regression on random inputs too.

  proc randomLuaSource(rng: var Rand, minLen, maxLen: int): string =
    ## Draw from a small alphabet biased toward the bug-adjacent shapes:
    ## comment markers, escape backslashes, quotes, operator chars. This is
    ## deliberately not a Lua grammar — the invariants below must hold on any
    ## input, not just legal programs.
    const alphabet = "-\\\"'<>=~!/*+%&|^:.[]() \tabc012"
    let n = minLen + rng.rand(maxLen - minLen)
    result = newStringOfCap(n)
    for _ in 0 ..< n:
      result.add(alphabet[rng.rand(alphabet.high)])

  test "no gtOperator token contains `--` (would open a comment)":
    for src in ["x<--c", "y>--c", "a==--c", "x~=--c", "b=-2", "n= -1", "x<-y", "x>-y"]:
      for (kind, text) in tokens(src):
        if kind == gtOperator:
          check "--" notin text

  test "no gtOperator token contains `[[` (would open a long string)":
    for src in ["x=[[a]]", "y=--[[c]]", "*[[a]]"]:
      for (kind, text) in tokens(src):
        if kind == gtOperator:
          check "[[" notin text

  test "every gtEscapeSequence token starts with `\\`":
    # Regression: the string-resume path used to relabel a run of ordinary chars
    # as gtEscapeSequence when a later `\` appeared.
    for src in [
      "\"a\\tb\"", "\"a\\tXYZ\\nb\"", "'x\\ny'", "\"\\u{1F600}\"", "\"\\123abc\""
    ]:
      for (kind, text) in tokens(src):
        if kind == gtEscapeSequence:
          check text.len >= 1
          check text[0] == '\\'

  test "random inputs satisfy the operator/escape invariants":
    var rng = initRand(0xB0BAF37Cu64.int64)
    for _ in 0 ..< 500:
      let src = randomLuaSource(rng, 4, 40)
      for (kind, text) in tokens(src):
        case kind
        of gtOperator:
          check "--" notin text
          check "[[" notin text
        of gtEscapeSequence:
          check text.len >= 1
          check text[0] == '\\'
        else:
          discard

suite "syntax_lua - dispatch":
  test "getSourceLanguage resolves Lua":
    check getSourceLanguage("Lua") == langLua
    check getSourceLanguage("lua") == langLua
    check getSourceLanguage("luau") == langLua

  test "full tokenization of a small program":
    const Code = """
local M = {}

--[[ module doc ]]
function M.greet(name)
  return "Hello, " .. name
end

return M
"""
    for t in tokens(Code):
      check t.kind != gtNone
