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

import std/unittest

import ../src/moepkg/syntax/[tokenizer, flags, lexer]

suite "lexer - lexBacktick basic tests":
  test "backtick without flags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`code`")
    let flags: TokenizerFlags = {}
    let endPos = g.lexBacktick(0, flags)
    check endPos == 1
    check g.kind == gtPunctuation

  test "backtick with hasBacktickFramedExpressions":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`code`")
    let flags: TokenizerFlags = {hasBacktickFramedExpressions}
    let endPos = g.lexBacktick(0, flags)
    check endPos == 6
    check g.kind == gtSpecialVar

  test "double backtick with hasBacktickFramedExpressions":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("``code``")
    let flags: TokenizerFlags = {hasBacktickFramedExpressions}
    let endPos = g.lexBacktick(0, flags)
    # Double backtick is not specially handled - returns after ``
    check endPos == 2
    check g.kind == gtSpecialVar

  test "triple backtick without hasTripleBacktickFramedExpressions":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```code```")
    let flags: TokenizerFlags = {hasBacktickFramedExpressions}
    let endPos = g.lexBacktick(0, flags)
    # Without triple flag, returns after ``` only
    check endPos == 3
    check g.kind == gtSpecialVar

  test "triple backtick with hasTripleBacktickFramedExpressions":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```code```")
    let flags: TokenizerFlags =
      {hasBacktickFramedExpressions, hasTripleBacktickFramedExpressions}
    let endPos = g.lexBacktick(0, flags)
    check endPos == 10
    check g.kind == gtSpecialVar

  test "triple backtick multiline":
    var g: GeneralTokenizer
    let s = "```\ncode\nmore```"
    g.initGeneralTokenizer(s)
    let flags: TokenizerFlags =
      {hasBacktickFramedExpressions, hasTripleBacktickFramedExpressions}
    let endPos = g.lexBacktick(0, flags)
    check endPos == s.len
    check g.kind == gtSpecialVar

  test "unterminated backtick":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`code")
    let flags: TokenizerFlags = {hasBacktickFramedExpressions}
    let endPos = g.lexBacktick(0, flags)
    check endPos == 5
    check g.kind == gtSpecialVar

  test "unterminated triple backtick":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```code")
    let flags: TokenizerFlags =
      {hasBacktickFramedExpressions, hasTripleBacktickFramedExpressions}
    let endPos = g.lexBacktick(0, flags)
    check endPos == 7
    check g.kind == gtSpecialVar

  test "not starting at backtick":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x`code`")
    let flags: TokenizerFlags = {hasBacktickFramedExpressions}
    let endPos = g.lexBacktick(0, flags)
    check endPos == 0

suite "lexer - lexCurlyOpen basic tests":
  test "curly open without flags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    let flags: TokenizerFlags = {}
    let endPos = g.lexCurlyOpen(0, flags)
    check endPos == 1
    check g.kind == gtPunctuation

  test "curly open with hasCurlyDashComments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- comment -}")
    let endPos = g.lexCurlyOpen(0, flagsHaskell)
    check endPos == 13
    check g.kind == gtLongComment

  test "curly open not followed by dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{ code }")
    let endPos = g.lexCurlyOpen(0, flagsHaskell)
    check endPos == 1
    check g.kind == gtPunctuation

  test "curly open with dash but no hasCurlyDashComments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- not a comment -}")
    let flags: TokenizerFlags = {}
    let endPos = g.lexCurlyOpen(0, flags)
    check endPos == 1
    check g.kind == gtPunctuation

  test "not starting at curly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x{")
    let endPos = g.lexCurlyOpen(0, flagsHaskell)
    check endPos == 0

suite "lexer - lexDash basic tests":
  test "single dash with hasDashFunction":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    let flags: TokenizerFlags = {hasDashFunction}
    let endPos = g.lexDash(0, flags)
    check endPos == 1
    check g.kind == gtFunctionName

  test "single dash with hasDashPunctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    let flags: TokenizerFlags = {hasDashPunctuation}
    let endPos = g.lexDash(0, flags)
    check endPos == 1
    check g.kind == gtPunctuation

  test "single dash without special flags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    let flags: TokenizerFlags = {}
    let endPos = g.lexDash(0, flags)
    check endPos == 1
    check g.kind == gtBuiltin

  test "double dash with hasDoubleDashComments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-- comment")
    let flags: TokenizerFlags = {hasDoubleDashComments}
    let endPos = g.lexDash(0, flags)
    check endPos == 10
    check g.kind == gtComment

  test "double dash followed by space and caret":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-- ^ doc")
    let flags: TokenizerFlags = {hasDoubleDashCaretComments}
    let endPos = g.lexDash(0, flags)
    check endPos == 8
    check g.kind == gtStringLit

  test "double dash with space but no caret":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-- comment")
    let flags: TokenizerFlags = {hasDoubleDashCaretComments}
    let endPos = g.lexDash(0, flags)
    check endPos == 10
    check g.kind == gtComment

  test "not starting at dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x-")
    let flags: TokenizerFlags = {hasDashFunction}
    let endPos = g.lexDash(0, flags)
    check endPos == 0

suite "lexer - lexDash triple dash preprocessor":
  test "triple dash with hasTripleDashPreprocessor and hasPreprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---front matter---")
    let flags: TokenizerFlags = {hasTripleDashPreprocessor, hasPreprocessor}
    let endPos = g.lexDash(0, flags)
    check endPos == 18
    check g.kind == gtPreprocessor

  test "triple dash with hasTripleDashPreprocessor without hasPreprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---front matter---")
    let flags: TokenizerFlags = {hasTripleDashPreprocessor}
    let endPos = g.lexDash(0, flags)
    check endPos == 18
    check g.kind == gtStringLit

  test "triple dash multiline":
    var g: GeneralTokenizer
    let s = "---\nkey: value\n---"
    g.initGeneralTokenizer(s)
    let flags: TokenizerFlags = {hasTripleDashPreprocessor, hasPreprocessor}
    let endPos = g.lexDash(0, flags)
    check endPos == s.len
    check g.kind == gtPreprocessor

  test "unterminated triple dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---unterminated")
    let flags: TokenizerFlags = {hasTripleDashPreprocessor, hasPreprocessor}
    let endPos = g.lexDash(0, flags)
    check endPos == 15
    check g.kind == gtPreprocessor

  test "quad dash is not triple dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("----")
    let flags: TokenizerFlags = {hasTripleDashPreprocessor, hasPreprocessor}
    let endPos = g.lexDash(0, flags)
    # Four dashes: buf[3] == '-', so condition `buf[result] != '-'` is false
    # This means it doesn't enter the triple dash preprocessor mode
    # Returns after reading --- only
    check endPos == 3

suite "lexer - lexHash basic tests":
  test "hash with hasHashComments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    let flags: TokenizerFlags = {hasHashComments}
    let endPos = g.lexHash(0, flags)
    check endPos == 9
    check g.kind == gtComment

  test "hash with hasHashHeadings at line start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# heading")
    g.state = gtWhitespace
    let flags: TokenizerFlags = {hasHashHeadings}
    let endPos = g.lexHash(0, flags)
    check endPos == 9
    check g.kind == gtBuiltin

  test "hash with hasHashHeadings not at line start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# not heading")
    g.state = gtIdentifier
    let flags: TokenizerFlags = {hasHashHeadings}
    let endPos = g.lexHash(0, flags)
    check endPos == 1
    check g.kind == gtPunctuation

  test "hash without flags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    let flags: TokenizerFlags = {}
    let endPos = g.lexHash(0, flags)
    check endPos == 1
    check g.kind == gtPunctuation

  test "not starting at hash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x#")
    let flags: TokenizerFlags = {hasHashComments}
    let endPos = g.lexHash(0, flags)
    check endPos == 0

suite "lexer - lexSharp basic tests":
  test "sharp with hasSharpFunction":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    let flags: TokenizerFlags = {hasSharpFunction}
    let endPos = g.lexSharp(0, flags)
    check endPos == 1
    check g.kind == gtFunctionName

  test "sharp with hasSharpOperator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    let flags: TokenizerFlags = {hasSharpOperator}
    let endPos = g.lexSharp(0, flags)
    check endPos == 1
    check g.kind == gtOperator

  test "sharp with hasSharpPunctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    let flags: TokenizerFlags = {hasSharpPunctuation}
    let endPos = g.lexSharp(0, flags)
    check endPos == 1
    check g.kind == gtPunctuation

  test "sharp without flags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    let flags: TokenizerFlags = {}
    let endPos = g.lexSharp(0, flags)
    check endPos == 1
    check g.kind == gtBuiltin

  test "not starting at sharp":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x<")
    let flags: TokenizerFlags = {hasSharpFunction}
    let endPos = g.lexSharp(0, flags)
    check endPos == 0

suite "lexer - lexSharp HTML comment":
  test "HTML comment with hasSharpBangDoubleDashComments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- comment -->")
    let flags: TokenizerFlags = {hasSharpBangDoubleDashComments}
    let endPos = g.lexSharp(0, flags)
    check endPos == 16
    check g.kind == gtLongComment

  test "multiline HTML comment":
    var g: GeneralTokenizer
    let s = "<!--\nmultiline\ncomment\n-->"
    g.initGeneralTokenizer(s)
    let flags: TokenizerFlags = {hasSharpBangDoubleDashComments}
    let endPos = g.lexSharp(0, flags)
    check endPos == s.len
    check g.kind == gtLongComment

  test "unterminated HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- unterminated")
    let flags: TokenizerFlags = {hasSharpBangDoubleDashComments}
    let endPos = g.lexSharp(0, flags)
    check endPos == 17
    check g.kind == gtLongComment

  test "nested HTML comments with hasNestedComments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- outer <!-- inner --> outer -->")
    let flags: TokenizerFlags = {hasSharpBangDoubleDashComments, hasNestedComments}
    let endPos = g.lexSharp(0, flags)
    check endPos == 35
    check g.kind == gtLongComment

  test "nested HTML comments without hasNestedComments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- outer <!-- inner --> outer -->")
    let flags: TokenizerFlags = {hasSharpBangDoubleDashComments}
    let endPos = g.lexSharp(0, flags)
    # Without nesting, stops at first -->
    check endPos == 25
    check g.kind == gtLongComment

  test "HTML comment with multiple dashes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- --- -->")
    let flags: TokenizerFlags = {hasSharpBangDoubleDashComments}
    let endPos = g.lexSharp(0, flags)
    check endPos == 12
    check g.kind == gtLongComment

  test "partial HTML comment start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-")
    let flags: TokenizerFlags = {hasSharpBangDoubleDashComments}
    let endPos = g.lexSharp(0, flags)
    # Doesn't become a comment, stays as builtin
    check endPos == 3
    check g.kind == gtBuiltin

suite "lexer - lexSymbol basic tests":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello")
    let endPos = g.lexSymbol(0)
    check endPos == 5
    check g.kind == gtIdentifier
    check g.state == gtIdentifier

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello_world")
    let endPos = g.lexSymbol(0)
    check endPos == 11
    check g.kind == gtIdentifier

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    let endPos = g.lexSymbol(0)
    check endPos == 6
    check g.kind == gtIdentifier

  test "identifier starting with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    let endPos = g.lexSymbol(0)
    check endPos == 8
    check g.kind == gtIdentifier

  test "single character":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    let endPos = g.lexSymbol(0)
    check endPos == 1
    check g.kind == gtIdentifier

  test "identifier followed by space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello world")
    let endPos = g.lexSymbol(0)
    check endPos == 5
    check g.kind == gtIdentifier

  test "identifier followed by operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x+y")
    let endPos = g.lexSymbol(0)
    check endPos == 1
    check g.kind == gtIdentifier

  test "not starting at symbol char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+hello")
    let endPos = g.lexSymbol(0)
    check endPos == 0

  test "unicode high bytes":
    var g: GeneralTokenizer
    let s = "日本語"
    g.initGeneralTokenizer(s)
    let endPos = g.lexSymbol(0)
    # symChars includes '\x80' .. '\xFF', so UTF-8 bytes are symbols
    check endPos == s.len
    check g.kind == gtIdentifier

suite "lexer - lexWhitespace basic tests":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" ")
    let endPos = g.lexWhitespace(0)
    check endPos == 1
    check g.kind == gtWhitespace

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("    ")
    let endPos = g.lexWhitespace(0)
    check endPos == 4
    check g.kind == gtWhitespace

  test "single tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\t")
    let endPos = g.lexWhitespace(0)
    check endPos == 1
    check g.kind == gtWhitespace

  test "mixed spaces and tabs":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("  \t  \t")
    let endPos = g.lexWhitespace(0)
    check endPos == 6
    check g.kind == gtWhitespace

  test "newline sets state to gtWhitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n")
    let endPos = g.lexWhitespace(0)
    check endPos == 1
    check g.kind == gtWhitespace
    check g.state == gtWhitespace

  test "space sets state to gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" x")
    let endPos = g.lexWhitespace(0)
    check endPos == 1
    check g.kind == gtWhitespace
    check g.state == gtNone

  test "carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\r")
    let endPos = g.lexWhitespace(0)
    check endPos == 1
    check g.kind == gtWhitespace

  test "vertical tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\v")
    let endPos = g.lexWhitespace(0)
    check endPos == 1
    check g.kind == gtWhitespace

  test "form feed":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\f")
    let endPos = g.lexWhitespace(0)
    check endPos == 1
    check g.kind == gtWhitespace

  test "whitespace before text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   hello")
    let endPos = g.lexWhitespace(0)
    check endPos == 3
    check g.kind == gtWhitespace

  test "not starting at whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello")
    let endPos = g.lexWhitespace(0)
    check endPos == 0

suite "lexer - lexWhitespace state transitions":
  test "newline followed by space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n ")
    let endPos = g.lexWhitespace(0)
    check endPos == 2
    # Last char was space, so state is gtNone
    check g.state == gtNone

  test "space followed by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \n")
    let endPos = g.lexWhitespace(0)
    check endPos == 2
    # Last char was newline, so state is gtWhitespace
    check g.state == gtWhitespace

  test "multiple newlines":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n\n\n")
    let endPos = g.lexWhitespace(0)
    check endPos == 3
    check g.state == gtWhitespace

  test "CRLF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\r\n")
    let endPos = g.lexWhitespace(0)
    check endPos == 2
    # Last char was \n, so state is gtWhitespace
    check g.state == gtWhitespace

suite "lexer - integration with flagsMarkdown":
  test "backtick in markdown":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`code`")
    let endPos = g.lexBacktick(0, flagsMarkdown)
    check endPos == 6
    check g.kind == gtSpecialVar

  test "triple backtick in markdown":
    var g: GeneralTokenizer
    let s = "```nim\ncode\n```"
    g.initGeneralTokenizer(s)
    let endPos = g.lexBacktick(0, flagsMarkdown)
    check endPos == s.len
    check g.kind == gtSpecialVar

  test "triple dash in markdown":
    var g: GeneralTokenizer
    let s = "---\ntitle: Test\n---"
    g.initGeneralTokenizer(s)
    let endPos = g.lexDash(0, flagsMarkdown)
    check endPos == s.len
    check g.kind == gtPreprocessor

  test "hash heading in markdown":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Heading")
    g.state = gtWhitespace
    let endPos = g.lexHash(0, flagsMarkdown)
    check endPos == 9
    check g.kind == gtBuiltin

suite "lexer - integration with flagsHaskell":
  test "curly dash comment in haskell":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- comment -}")
    let endPos = g.lexCurlyOpen(0, flagsHaskell)
    check endPos == 13
    check g.kind == gtLongComment

  test "double dash comment in haskell":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-- comment")
    let endPos = g.lexDash(0, flagsHaskell)
    check endPos == 10
    check g.kind == gtComment

  test "dash function in haskell":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-x")
    let endPos = g.lexDash(0, flagsHaskell)
    check endPos == 1
    check g.kind == gtFunctionName

  test "sharp function in haskell":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    let endPos = g.lexSharp(0, flagsHaskell)
    check endPos == 1
    check g.kind == gtFunctionName

suite "lexer - integration with flagsYaml":
  test "dash punctuation in yaml":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    let endPos = g.lexDash(0, flagsYaml)
    check endPos == 1
    check g.kind == gtPunctuation

  test "hash comment in yaml":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    let endPos = g.lexHash(0, flagsYaml)
    check endPos == 9
    check g.kind == gtComment

suite "lexer - integration with flagsShell":
  test "hash comment in shell":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    let endPos = g.lexHash(0, flagsShell)
    check endPos == 9
    check g.kind == gtComment
