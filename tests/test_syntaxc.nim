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

import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/syntax/syntaxc

suite "syntaxc - cKeywords constant":
  test "cKeywords contains type keywords":
    check "char" in cKeywords
    check "int" in cKeywords
    check "short" in cKeywords
    check "long" in cKeywords
    check "float" in cKeywords
    check "double" in cKeywords
    check "void" in cKeywords
    check "signed" in cKeywords
    check "unsigned" in cKeywords

  test "cKeywords contains storage class keywords":
    check "auto" in cKeywords
    check "static" in cKeywords
    check "extern" in cKeywords
    check "register" in cKeywords
    check "typedef" in cKeywords

  test "cKeywords contains control flow keywords":
    check "if" in cKeywords
    check "else" in cKeywords
    check "switch" in cKeywords
    check "case" in cKeywords
    check "default" in cKeywords
    check "for" in cKeywords
    check "while" in cKeywords
    check "do" in cKeywords
    check "break" in cKeywords
    check "continue" in cKeywords
    check "return" in cKeywords
    check "goto" in cKeywords

  test "cKeywords contains type modifier keywords":
    check "const" in cKeywords
    check "volatile" in cKeywords
    check "restrict" in cKeywords
    check "inline" in cKeywords

  test "cKeywords contains composite type keywords":
    check "struct" in cKeywords
    check "union" in cKeywords
    check "enum" in cKeywords

  test "cKeywords contains C99 keywords":
    check "_Bool" in cKeywords
    check "_Complex" in cKeywords
    check "_Imaginary" in cKeywords

  test "cKeywords contains sizeof":
    check "sizeof" in cKeywords

  test "cKeywords is sorted":
    for i in 0 ..< cKeywords.len - 1:
      check cKeywords[i] < cKeywords[i + 1]

suite "syntaxc - cNextToken keywords":
  test "int keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int")
    g.cNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "void keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("void")
    g.cNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "struct keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("struct")
    g.cNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.cNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "for keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for")
    g.cNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "while keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("while")
    g.cNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.cNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "sizeof keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("sizeof")
    g.cNextToken()
    check g.kind == gtKeyword
    check g.length == 6

suite "syntaxc - cNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.cNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.cNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.cNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.cNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

suite "syntaxc - cNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.cNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.cNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.cNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntaxc - cNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.cNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.cNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.cNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntaxc - cNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.cNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.cNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

suite "syntaxc - cNextToken octal numbers":
  test "octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.cNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

suite "syntaxc - cNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

suite "syntaxc - cNextToken string literals":
  test "simple string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.cNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.cNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.cNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with escape triggers state change":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.cNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntaxc - cNextToken character literals":
  test "simple char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a'")
    g.cNextToken()
    check g.kind == gtCharLit
    check g.length == 3

  test "escaped char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\n'")
    g.cNextToken()
    check g.kind == gtCharLit
    check g.length == 4

  test "hex escaped char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\x41'")
    g.cNextToken()
    check g.kind == gtCharLit
    check g.length == 6

suite "syntaxc - cNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// this is a comment")
    g.cNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "empty line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("//")
    g.cNextToken()
    check g.kind == gtComment
    check g.length == 2

  test "block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.cNextToken()
    check g.kind == gtLongComment
    check g.length == 13

  test "multiline block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* line1\nline2 */")
    g.cNextToken()
    check g.kind == gtLongComment

suite "syntaxc - cNextToken preprocessor":
  test "include directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#include")
    g.cNextToken()
    check g.kind == gtPreprocessor
    check g.length == 8

  test "define directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#define")
    g.cNextToken()
    check g.kind == gtPreprocessor
    check g.length == 7

  test "ifdef directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#ifdef")
    g.cNextToken()
    check g.kind == gtPreprocessor
    check g.length == 6

  test "endif directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#endif")
    g.cNextToken()
    check g.kind == gtPreprocessor
    check g.length == 6

  test "pragma directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#pragma")
    g.cNextToken()
    check g.kind == gtPreprocessor
    check g.length == 7

suite "syntaxc - cNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "division alone is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/ x")
    g.cNextToken()
    check g.kind == gtOperator

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comparison operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "arrow operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("->")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "ampersand operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "pipe operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntaxc - cNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxc - cNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.cNextToken() # 'a'
    g.cNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.cNextToken() # 'a'
    g.cNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.cNextToken() # 'a'
    g.cNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.cNextToken() # 'a'
    g.cNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

suite "syntaxc - cNextToken escape sequences":
  test "escape in string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.cNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.cNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.cNextToken()
    check g.state == gtStringLit

    g.cNextToken()
    check g.kind == gtEscapeSequence

suite "syntaxc - cNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.cNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.cNextToken() # 'x'
    g.cNextToken() # EOF
    check g.kind == gtEof

suite "syntaxc - cNextToken complete code":
  test "simple function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int main() { return 0; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # int, return
    check gtIdentifier in tokens # main
    check gtPunctuation in tokens # (, ), {, }, ;
    check gtDecNumber in tokens # 0

  test "variable declaration":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int x = 10;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # int
    check gtIdentifier in tokens # x
    check gtOperator in tokens # =
    check gtDecNumber in tokens # 10
    check gtPunctuation in tokens # ;

  test "preprocessor with include":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#include <stdio.h>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPreprocessor in tokens # #include

  test "for loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for (int i = 0; i < 10; i++)")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # for, int
    check gtIdentifier in tokens # i
    check gtDecNumber in tokens # 0, 10
    check gtOperator in tokens # =, <, ++

suite "syntaxc - cNextToken edge cases":
  test "unterminated block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* unterminated")
    g.cNextToken()
    check g.kind == gtLongComment
    check g.length == 15

  test "unterminated string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.cNextToken()
    check g.kind == gtStringLit

  test "unterminated char literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'x")
    g.cNextToken()
    check g.kind == gtCharLit

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\nworld\"")
    g.cNextToken()
    check g.kind == gtStringLit
    # String is terminated at newline (includes opening quote)
    check g.length == 6

  test "string terminated by carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\rworld\"")
    g.cNextToken()
    check g.kind == gtStringLit
    check g.length == 6

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.cNextToken()
    check g.kind == gtIdentifier

  test "identifier with high bytes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("café")
    g.cNextToken()
    check g.kind == gtIdentifier

suite "syntaxc - cNextToken number suffixes":
  test "integer with L suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123L")
    g.cNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

  test "integer with LL suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123LL")
    g.cNextToken()
    check g.kind == gtDecNumber
    check g.length == 5

  test "integer with u suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123u")
    g.cNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

  test "integer with UL suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123UL")
    g.cNextToken()
    check g.kind == gtDecNumber
    check g.length == 5

  test "hex with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFu")
    g.cNextToken()
    check g.kind == gtHexNumber
    check g.length == 5

  test "binary with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010L")
    g.cNextToken()
    check g.kind == gtBinNumber
    check g.length == 7

  test "octal with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755u")
    g.cNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "float with f suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14f")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

  test "float with L suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14L")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

suite "syntaxc - cNextToken string continuation":
  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

  test "escape sequence continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")

    # First token: string part before escape
    g.cNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    # Second token: escape sequence
    g.cNextToken()
    check g.kind == gtEscapeSequence

    # Third token: rest of string
    g.cNextToken()
    check g.kind == gtStringLit
    check g.state == gtNone

  test "hex escape sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\x41\"")

    g.cNextToken() # empty string before escape
    check g.state == gtStringLit

    g.cNextToken() # \x41
    check g.kind == gtEscapeSequence
    check g.length == 4

  test "numeric escape sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")

    g.cNextToken()
    check g.state == gtStringLit

    g.cNextToken()
    check g.kind == gtEscapeSequence

  test "escape at end of input":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")

    g.cNextToken()
    check g.state == gtStringLit

    g.cNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone

suite "syntaxc - cNextToken colon handling":
  test "single colon is punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.cNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "double colon is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("::")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "colon in ternary operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a ? b : c")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # :
    check gtOperator in tokens # ?

suite "syntaxc - cNextToken additional edge cases":
  test "empty block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**/")
    g.cNextToken()
    check g.kind == gtLongComment
    check g.length == 4

  test "block comment with asterisks":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/****/")
    g.cNextToken()
    check g.kind == gtLongComment
    check g.length == 6

  test "block comment with nested slash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* a / b */")
    g.cNextToken()
    check g.kind == gtLongComment
    check g.length == 11

  test "preprocessor with extra spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#  include")
    g.cNextToken()
    check g.kind == gtPreprocessor
    check g.length == 10

  test "preprocessor with tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#\tdefine")
    g.cNextToken()
    check g.kind == gtPreprocessor
    check g.length == 8

suite "syntaxc - cNextToken compound operators":
  test "increment operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("++")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "decrement operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "plus equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "minus equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "multiply equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "divide equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "modulo equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "left shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<<")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "right shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "left shift equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<<=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "right shift equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "bitwise and equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "bitwise or equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "bitwise xor equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("^=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical and operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&&")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical or operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("||")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "less than or equal operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "greater than or equal operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">=")
    g.cNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxc - cNextToken float edge cases":
  test "float starting with dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".5")
    g.cNextToken()
    # Dot is punctuation, 5 is separate number
    check g.kind == gtPunctuation
    check g.length == 1

  test "float ending with dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5.")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 2

  test "float with only exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5e3")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5e-3")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5e+3")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159f")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 8

  test "float exponent with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10L")
    g.cNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

suite "syntaxc - cNextToken special cases":
  test "division vs comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a / b")

    g.cNextToken() # a
    check g.kind == gtIdentifier

    g.cNextToken() # space
    check g.kind == gtWhitespace

    g.cNextToken() # /
    check g.kind == gtOperator
    check g.length == 1

  test "star vs pointer vs multiply":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int *p = a * b")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # int
    check gtOperator in tokens # *, =
    check gtIdentifier in tokens # p, a, b

  test "hash not preprocessor when no flag":
    # This test is not applicable since C always has hasPreprocessor
    # But we test the preprocessor directive parsing
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#pragma once")
    g.cNextToken()
    check g.kind == gtPreprocessor

  test "multiline block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* line1\nline2\nline3 */")
    g.cNextToken()
    check g.kind == gtLongComment

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x = 1; // comment")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x
    check gtOperator in tokens # =
    check gtDecNumber in tokens # 1
    check gtPunctuation in tokens # ;
    check gtComment in tokens # // comment
