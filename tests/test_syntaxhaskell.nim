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
import ../src/moepkg/syntax/syntaxhaskell

suite "syntaxhaskell - haskellKeywords constant":
  test "haskellKeywords contains control flow keywords":
    check "if" in haskellKeywords
    check "then" in haskellKeywords
    check "else" in haskellKeywords
    check "case" in haskellKeywords
    check "of" in haskellKeywords

  test "haskellKeywords contains definition keywords":
    check "let" in haskellKeywords
    check "where" in haskellKeywords
    check "do" in haskellKeywords
    check "module" in haskellKeywords
    check "import" in haskellKeywords

  test "haskellKeywords contains type keywords":
    check "type" in haskellKeywords
    check "data" in haskellKeywords
    check "newtype" in haskellKeywords
    check "class" in haskellKeywords
    check "instance" in haskellKeywords
    check "deriving" in haskellKeywords

  test "haskellKeywords contains fixity keywords":
    check "infix" in haskellKeywords
    check "infixl" in haskellKeywords
    check "infixr" in haskellKeywords

  test "haskellKeywords contains other keywords":
    check "_" in haskellKeywords
    check "default" in haskellKeywords

suite "syntaxhaskell - haskellNextToken keywords":
  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "then keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("then")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "else keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("else")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "case keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("case")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "of keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("of")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "let keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "where keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("where")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "do keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("do")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "module keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("module")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "import keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "data keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("data")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "type keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "newtype keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("newtype")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "class keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "instance keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("instance")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "deriving keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("deriving")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "infix keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("infix")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "infixl keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("infixl")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "infixr keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("infixr")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "default keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("default")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "underscore keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_")
    g.haskellNextToken()
    check g.kind == gtKeyword
    check g.length == 1

suite "syntaxhaskell - haskellNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.haskellNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.haskellNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.haskellNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.haskellNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "camelCase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVariableName")
    g.haskellNextToken()
    check g.kind == gtIdentifier
    check g.length == 14

  test "PascalCase identifier (type name)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MyType")
    g.haskellNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.haskellNextToken()
    check g.kind == gtIdentifier

suite "syntaxhaskell - haskellNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.haskellNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.haskellNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.haskellNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntaxhaskell - haskellNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.haskellNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.haskellNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.haskellNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFa")
    g.haskellNextToken()
    check g.kind == gtHexNumber
    check g.length == 5

suite "syntaxhaskell - haskellNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.haskellNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.haskellNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010a")
    g.haskellNextToken()
    check g.kind == gtBinNumber
    check g.length == 7

suite "syntaxhaskell - haskellNextToken octal numbers":
  test "octal number with 0o prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755")
    g.haskellNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "octal number legacy style":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.haskellNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

  test "octal with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755a")
    g.haskellNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

suite "syntaxhaskell - haskellNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.haskellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.haskellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.haskellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.haskellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.haskellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

suite "syntaxhaskell - haskellNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.haskellNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.haskellNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.haskellNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with escape triggers state change":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.haskellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntaxhaskell - haskellNextToken character literals":
  test "simple char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a'")
    g.haskellNextToken()
    check g.kind == gtStringLit
    check g.length == 3

  test "char with escape triggers state change":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\n'")
    g.haskellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntaxhaskell - haskellNextToken escape sequences":
  test "escape in string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.haskellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.haskellNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.haskellNextToken()
    check g.state == gtStringLit

    g.haskellNextToken()
    check g.kind == gtEscapeSequence

  test "numeric escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")
    g.haskellNextToken()
    check g.state == gtStringLit

    g.haskellNextToken()
    check g.kind == gtEscapeSequence

  test "escape at end of input":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.haskellNextToken()
    check g.state == gtStringLit

    g.haskellNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone

suite "syntaxhaskell - haskellNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-- this is a comment")
    g.haskellNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "empty line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--")
    g.haskellNextToken()
    check g.kind == gtComment
    check g.length == 2

  test "line comment without space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--comment")
    g.haskellNextToken()
    check g.kind == gtComment
    check g.length == 9

  test "block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- comment -}")
    g.haskellNextToken()
    check g.kind == gtLongComment
    check g.length == 13

  test "multiline block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- line1\nline2 -}")
    g.haskellNextToken()
    check g.kind == gtLongComment

  test "empty block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{--}")
    g.haskellNextToken()
    check g.kind == gtLongComment
    check g.length == 4

suite "syntaxhaskell - haskellNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "divide operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comparison operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/=")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "less than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "greater than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "arrow operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("->")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "left arrow operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<-")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "fat arrow operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=>")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "append operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("++")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "cons operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "bind operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>=")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "then operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "function composition operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "dollar operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "at operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "tilde operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("~")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "backslash (lambda)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "pipe operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "ampersand operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.haskellNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntaxhaskell - haskellNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.haskellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxhaskell - haskellNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.haskellNextToken() # 'a'
    g.haskellNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.haskellNextToken() # 'a'
    g.haskellNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.haskellNextToken() # 'a'
    g.haskellNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.haskellNextToken() # 'a'
    g.haskellNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

  test "mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a \t\n b")
    g.haskellNextToken() # 'a'
    g.haskellNextToken() # ' \t\n '
    check g.kind == gtWhitespace
    check g.length == 4

suite "syntaxhaskell - haskellNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.haskellNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.haskellNextToken() # 'x'
    g.haskellNextToken() # EOF
    check g.kind == gtEof

suite "syntaxhaskell - haskellNextToken complete code":
  test "simple function definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("add x y = x + y")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # add, x, y
    check gtOperator in tokens # =, +

  test "function with type signature":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("add :: Int -> Int -> Int")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # add, Int
    check gtOperator in tokens # ::, ->

  test "data type definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("data Maybe a = Nothing | Just a")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # data
    check gtIdentifier in tokens # Maybe, a, Nothing, Just
    check gtOperator in tokens # =, |

  test "module declaration":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("module Main where")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # module, where
    check gtIdentifier in tokens # Main

  test "import statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import Data.List")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # import
    check gtIdentifier in tokens # Data, List

  test "if then else expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if x > 0 then x else -x")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # if, then, else
    check gtIdentifier in tokens # x
    check gtOperator in tokens # >
    check gtDecNumber in tokens # 0

  test "case expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("case x of { 0 -> \"zero\"; _ -> \"other\" }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # case, of, _
    check gtDecNumber in tokens # 0
    check gtStringLit in tokens # "zero", "other"
    check gtOperator in tokens # ->
    check gtPunctuation in tokens # {, }, ;

  test "do notation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("do { x <- getLine; return x }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # do
    check gtIdentifier in tokens # x, getLine, return
    check gtOperator in tokens # <-
    check gtPunctuation in tokens # {, }, ;

  test "let expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let x = 5 in x + 1")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # let
    check gtIdentifier in tokens # x, in
    check gtDecNumber in tokens # 5, 1
    check gtOperator in tokens # =, +

  test "lambda expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\x -> x + 1")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtOperator in tokens # \, ->, +
    check gtIdentifier in tokens # x
    check gtDecNumber in tokens # 1

  test "list comprehension":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[x * 2 | x <- [1..10], x > 5]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x
    check gtOperator in tokens # *, |, <-, >, ..
    check gtDecNumber in tokens # 2, 1, 10, 5
    check gtPunctuation in tokens # [, ], ,

  test "class definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class Eq a where")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class, where
    check gtIdentifier in tokens # Eq, a

  test "instance declaration":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("instance Eq Bool where")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # instance, where
    check gtIdentifier in tokens # Eq, Bool

  test "deriving clause":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("data Color = Red | Blue deriving (Eq, Show)")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # data, deriving
    check gtIdentifier in tokens # Color, Red, Blue, Eq, Show

suite "syntaxhaskell - haskellNextToken edge cases":
  test "unterminated block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- unterminated")
    g.haskellNextToken()
    check g.kind == gtLongComment

  test "unterminated string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.haskellNextToken()
    check g.kind == gtStringLit

  test "string can contain newline":
    # Haskell strings can span multiple lines (unlike some languages)
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\nnext\"")
    g.haskellNextToken()
    check g.kind == gtStringLit
    check g.length == 11 # includes quotes and newline

  test "string terminated by carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\x0Dnext")
    g.haskellNextToken()
    check g.kind == gtStringLit

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x = 1 -- comment")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x
    check gtOperator in tokens # =
    check gtDecNumber in tokens # 1
    check gtComment in tokens # -- comment

  test "minus as operator vs comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x - y")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x, y
    check gtOperator in tokens # -

  test "curly brace as punctuation vs comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{ x }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # {, }
    check gtIdentifier in tokens # x

suite "syntaxhaskell - haskellNextToken string continuation":
  test "string continuation after escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.haskellNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.haskellNextToken() # \n
    check g.kind == gtEscapeSequence

    g.haskellNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.haskellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens
