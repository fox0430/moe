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
import ../src/moepkg/syntax/syntaxtoml

suite "syntaxtoml - tomlNextToken booleans":
  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.tomlNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.tomlNextToken()
    check g.kind == gtBoolean
    check g.length == 5

suite "syntaxtoml - tomlNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("mykey")
    g.tomlNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_key")
    g.tomlNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key123")
    g.tomlNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "uppercase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("TRUE")
    g.tomlNextToken()
    # Not a boolean (case sensitive)
    check g.kind == gtIdentifier
    check g.length == 4

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.tomlNextToken()
    check g.kind == gtIdentifier

suite "syntaxtoml - tomlNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

  test "number with underscores":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1_000_000")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 9

  test "positive number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+123")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

  test "negative number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-123")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

suite "syntaxtoml - tomlNextToken hex, octal, binary numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xdeadbeef")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xDEADBEEF")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

  test "octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 5

  test "binary number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b11010110")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntaxtoml - tomlNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

  test "float with capital E":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1E10")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "positive infinity":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+inf")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "negative infinity":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-inf")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "inf without sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("inf")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "nan":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("nan")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "positive nan":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+nan")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "negative nan":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-nan")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

suite "syntaxtoml - tomlNextToken date and time":
  test "date only":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15")
    g.tomlNextToken()
    check g.kind == gtDate
    check g.length == 10

  test "datetime with T separator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T10:30:00")
    g.tomlNextToken()
    check g.kind == gtDate
    check g.length == 19

  test "datetime with space separator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15 10:30:00")
    g.tomlNextToken()
    check g.kind == gtDate
    check g.length == 19

  test "datetime with timezone z":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T10:30:00z")
    g.tomlNextToken()
    check g.kind == gtDate
    check g.length == 20

  test "datetime with milliseconds":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T10:30:00.123")
    g.tomlNextToken()
    check g.kind == gtDate
    check g.length == 23

  test "time only":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("10:30:00")
    g.tomlNextToken()
    check g.kind == gtDate
    check g.length == 8

suite "syntaxtoml - tomlNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "single quoted string (literal)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.length == 13

suite "syntaxtoml - tomlNextToken escape sequences":
  test "escape in double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

  test "escape continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.tomlNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tomlNextToken() # \n
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "hex escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\x41\"")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tomlNextToken()
    check g.kind == gtEscapeSequence

suite "syntaxtoml - tomlNextToken tables":
  test "simple table":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[section]")
    g.tomlNextToken()
    check g.kind == gtTable
    check g.length == 9

  test "dotted table":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[section.subsection]")
    g.tomlNextToken()
    check g.kind == gtTable
    check g.length == 20

  test "array of tables":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[[products]]")
    g.tomlNextToken()
    check g.kind == gtTable
    check g.length == 12

  test "array of tables with dots":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[[products.item]]")
    g.tomlNextToken()
    check g.kind == gtTable
    check g.length == 17

suite "syntaxtoml - tomlNextToken comments":
  test "comment line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.tomlNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "comment after whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("  # comment")

    g.tomlNextToken() # whitespace
    check g.kind == gtWhitespace

    g.tomlNextToken() # comment
    check g.kind == gtComment

suite "syntaxtoml - tomlNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" ")
    g.tomlNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("    ")
    g.tomlNextToken()
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\t")
    g.tomlNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n")
    g.tomlNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

  test "mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \t\n ")
    g.tomlNextToken()
    check g.kind == gtWhitespace
    check g.length == 4

suite "syntaxtoml - tomlNextToken operators":
  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.tomlNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "dot operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.tomlNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntaxtoml - tomlNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.tomlNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1")
    g.tomlNextToken() # 1
    g.tomlNextToken() # EOF
    check g.kind == gtEof

suite "syntaxtoml - tomlNextToken complete TOML":
  test "key-value pair with string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("name = \"John\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # name
    check gtOperator in tokens # =
    check gtStringLit in tokens # "John"

  test "key-value pair with number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("count = 42")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # count
    check gtDecNumber in tokens # 42

  test "key-value pair with boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("enabled = true")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # enabled
    check gtBoolean in tokens # true

  test "section with key-value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[server]\nhost = \"localhost\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTable in tokens # [server]
    check gtIdentifier in tokens # host
    check gtStringLit in tokens # "localhost"

  test "array value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("ports = [8080, 8081]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # ports
    check gtPunctuation in tokens # [, ], ,
    check gtDecNumber in tokens # 8080, 8081

  test "dotted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("server.host = \"localhost\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # server, host
    check gtOperator in tokens # ., =
    check gtStringLit in tokens # "localhost"

  test "inline table":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("point = {x = 1, y = 2}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # point, x, y
    check gtDecNumber in tokens # 1, 2

  test "float value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("pi = 3.14159")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # pi
    check gtFloatNumber in tokens # 3.14159

  test "date value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("date = 2024-01-15")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # date
    check gtDate in tokens # 2024-01-15

  test "complex TOML":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      """
[database]
server = "192.168.1.1"
ports = [8001, 8002]
enabled = true
"""
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTable in tokens # [database]
    check gtIdentifier in tokens # server, ports, enabled
    check gtStringLit in tokens # "192.168.1.1"
    check gtDecNumber in tokens # 8001, 8002
    check gtBoolean in tokens # true

suite "syntaxtoml - tomlNextToken edge cases":
  test "unterminated string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.tomlNextToken()
    check g.kind == gtStringLit

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\nnext")
    g.tomlNextToken()
    check g.kind == gtStringLit

  test "empty array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[]")

    g.tomlNextToken() # [
    check g.kind == gtPunctuation
    check g.length == 1

    g.tomlNextToken() # ]
    check g.kind == gtPunctuation
    check g.length == 1

  test "table not closed":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[section")
    g.tomlNextToken()
    check g.kind == gtTable

  test "unknown character":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`")
    g.tomlNextToken()
    check g.kind == gtNone

  test "escape at string end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tomlNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone
