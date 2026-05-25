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

import ../src/moepkg/syntax/[tokenizer, syntax_json]

suite "syntax_json - jsonNextToken keywords":
  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.jsonNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.jsonNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "null keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.jsonNextToken()
    check g.kind == gtKeyword
    check g.length == 4

suite "syntax_json - jsonNextToken identifiers":
  test "non-keyword identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("unknown")
    g.jsonNextToken()
    check g.kind == gtIdentifier
    check g.length == 7

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.jsonNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.jsonNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "uppercase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("TRUE")
    g.jsonNextToken()
    # Not a keyword (case sensitive)
    check g.kind == gtIdentifier
    check g.length == 4

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.jsonNextToken()
    check g.kind == gtIdentifier

suite "syntax_json - jsonNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.jsonNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.jsonNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.jsonNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

  test "negative number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-123")
    g.jsonNextToken()
    # '-' is parsed as operator, then 123 as number
    check g.kind == gtOperator
    check g.length == 1

    g.jsonNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

suite "syntax_json - jsonNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.jsonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.jsonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.jsonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.jsonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.jsonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

  test "float with capital E":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1E10")
    g.jsonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

suite "syntax_json - jsonNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntax_json - jsonNextToken key detection":
  test "string as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"name\": \"value\"")
    g.jsonNextToken()
    check g.kind == gtKey
    check g.length == 6

  test "string as value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"value\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "key with whitespace before colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"key\"  : \"value\"")
    g.jsonNextToken()
    check g.kind == gtKey
    check g.length == 5

  test "key in object":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"id\": 1}")

    g.jsonNextToken() # {
    check g.kind == gtPunctuation

    g.jsonNextToken() # "id"
    check g.kind == gtKey
    check g.length == 4

suite "syntax_json - jsonNextToken escape sequences":
  test "escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.jsonNextToken()
    check g.kind == gtEscapeSequence

  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

  test "escape at start of string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\ntest\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.jsonNextToken()
    check g.kind == gtEscapeSequence

  test "unicode escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\u0041\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.jsonNextToken()
    check g.kind == gtEscapeSequence

suite "syntax_json - jsonNextToken operators":
  test "colon operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.jsonNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntax_json - jsonNextToken punctuation":
  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.jsonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.jsonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.jsonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.jsonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.jsonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_json - jsonNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" ")
    g.jsonNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("    ")
    g.jsonNextToken()
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\t")
    g.jsonNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n")
    g.jsonNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

  test "mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \t\n ")
    g.jsonNextToken()
    check g.kind == gtWhitespace
    check g.length == 4

suite "syntax_json - jsonNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.jsonNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1")
    g.jsonNextToken() # 1
    g.jsonNextToken() # EOF
    check g.kind == gtEof

suite "syntax_json - jsonNextToken complete JSON":
  test "simple object":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"name\": \"John\"}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # {, }
    check gtKey in tokens # "name"
    check gtOperator in tokens # :
    check gtStringLit in tokens # "John"

  test "object with number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"age\": 30}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens # "age"
    check gtDecNumber in tokens # 30

  test "object with boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"active\": true}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens # "active"
    check gtKeyword in tokens # true

  test "object with null":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"data\": null}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens # "data"
    check gtKeyword in tokens # null

  test "simple array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[1, 2, 3]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # [, ], ,
    check gtDecNumber in tokens # 1, 2, 3

  test "array of strings":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[\"a\", \"b\", \"c\"]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # [, ], ,
    check gtStringLit in tokens # "a", "b", "c"

  test "nested object":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"person\": {\"name\": \"John\"}}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens # "person", "name"
    check gtStringLit in tokens # "John"

  test "array in object":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"items\": [1, 2]}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens # "items"
    check gtDecNumber in tokens # 1, 2

  test "complex JSON":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      """{"name": "test", "count": 42, "valid": true, "data": null}"""
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens # keys
    check gtStringLit in tokens # "test"
    check gtDecNumber in tokens # 42
    check gtKeyword in tokens # true, null

  test "float in object":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"pi\": 3.14159}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.jsonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens # "pi"
    check gtFloatNumber in tokens # 3.14159

suite "syntax_json - jsonNextToken edge cases":
  test "unterminated string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.jsonNextToken()
    check g.kind == gtStringLit

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\nnext")
    g.jsonNextToken()
    check g.kind == gtStringLit

  test "empty object":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{}")

    g.jsonNextToken() # {
    check g.kind == gtPunctuation

    g.jsonNextToken() # }
    check g.kind == gtPunctuation

  test "empty array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[]")

    g.jsonNextToken() # [
    check g.kind == gtPunctuation

    g.jsonNextToken() # ]
    check g.kind == gtPunctuation

  test "number followed by identifier splits cleanly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123abc")
    g.jsonNextToken()
    check g.kind == gtDecNumber
    check g.length == 3 # "123"

    g.jsonNextToken()
    check g.kind == gtIdentifier
    check g.length == 3 # "abc"

  test "unknown character":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`")
    g.jsonNextToken()
    check g.kind == gtNone

  test "escape at string end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.jsonNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone

suite "syntax_json - jsonNextToken adjacent strings (not triple-quoted)":
  test "two empty strings are tokenized separately":
    # JSON spec does not have triple-quoted strings: """" is just "" then "".
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"\"")
    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.length == 2

    g.jsonNextToken()
    check g.kind == gtStringLit
    check g.length == 2

suite "syntax_json - jsonNextToken string continuation":
  test "string continuation after escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.jsonNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.jsonNextToken() # \n
    check g.kind == gtEscapeSequence

    g.jsonNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "key with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\": \"value\"")
    g.jsonNextToken() # "hello
    check g.kind == gtKey
    check g.state == gtKey

    g.jsonNextToken() # \n
    check g.kind == gtEscapeSequence

    g.jsonNextToken() # world"
    check g.kind == gtKey
    check g.state == gtNone
