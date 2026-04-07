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

import ../src/moepkg/syntax/[tokenizer, syntax_toml]

suite "syntax_toml - tomlNextToken booleans":
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

suite "syntax_toml - tomlNextToken identifiers":
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

suite "syntax_toml - tomlNextToken decimal numbers":
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

suite "syntax_toml - tomlNextToken hex, octal, binary numbers":
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

suite "syntax_toml - tomlNextToken float numbers":
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

suite "syntax_toml - tomlNextToken date and time":
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

suite "syntax_toml - tomlNextToken string literals":
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

suite "syntax_toml - tomlNextToken escape sequences":
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
    check g.length == 4 # \x41 is 4 characters

  test "hex escape followed by text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\x41BC\"")
    g.tomlNextToken() # "
    check g.kind == gtStringLit

    g.tomlNextToken() # \x41
    check g.kind == gtEscapeSequence
    check g.length == 4

    g.tomlNextToken() # BC"
    check g.kind == gtStringLit

suite "syntax_toml - tomlNextToken tables":
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

suite "syntax_toml - tomlNextToken comments":
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

suite "syntax_toml - tomlNextToken whitespace":
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

suite "syntax_toml - tomlNextToken operators":
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

suite "syntax_toml - tomlNextToken EOF":
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

suite "syntax_toml - tomlNextToken complete TOML":
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

suite "syntax_toml - tomlNextToken edge cases":
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

suite "syntax_toml - standard escape sequences":
  test "escape backslash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\\\b\"")
    g.tomlNextToken() # "a
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tomlNextToken() # \\
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # b"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "escape double quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\\"b\"")
    g.tomlNextToken() # "a
    check g.kind == gtStringLit

    g.tomlNextToken() # \"
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # b"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "escape newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\"")
    g.tomlNextToken() # "a
    check g.kind == gtStringLit

    g.tomlNextToken() # \n
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # b"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "escape tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\tb\"")
    g.tomlNextToken() # "a
    check g.kind == gtStringLit

    g.tomlNextToken() # \t
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # b"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "escape carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\rb\"")
    g.tomlNextToken() # "a
    check g.kind == gtStringLit

    g.tomlNextToken() # \r
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # b"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "escape backspace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\bb\"")
    g.tomlNextToken() # "a
    check g.kind == gtStringLit

    g.tomlNextToken() # \b
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # b"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "escape form feed":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\fb\"")
    g.tomlNextToken() # "a
    check g.kind == gtStringLit

    g.tomlNextToken() # \f
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # b"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "multiple escape sequences":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\n\\t\\r\"")

    g.tomlNextToken() # "
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tomlNextToken() # \n
    check g.kind == gtEscapeSequence

    # Consecutive escapes don't have string tokens between them
    g.tomlNextToken() # \t
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # \r
    check g.kind == gtEscapeSequence

    g.tomlNextToken() # "
    check g.kind == gtStringLit
    check g.state == gtNone

suite "syntax_toml - unicode escape sequences":
  test "unicode 4 digit escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\u0041\"")
    g.tomlNextToken() # "
    check g.kind == gtStringLit

    g.tomlNextToken() # \u0041
    check g.kind == gtEscapeSequence
    check g.length == 6 # \u0041 is 6 characters

    g.tomlNextToken() # "
    check g.kind == gtStringLit
    check g.state == gtNone

  test "unicode 8 digit escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\U0001F600\"")
    g.tomlNextToken() # "
    check g.kind == gtStringLit

    g.tomlNextToken() # \U0001F600
    check g.kind == gtEscapeSequence
    check g.length == 10 # \U0001F600 is 10 characters

    g.tomlNextToken() # "
    check g.kind == gtStringLit
    check g.state == gtNone

  test "unicode escape followed by text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\u0041hello\"")
    g.tomlNextToken() # "
    check g.kind == gtStringLit

    g.tomlNextToken() # \u0041
    check g.kind == gtEscapeSequence
    check g.length == 6

    g.tomlNextToken() # hello"
    check g.kind == gtStringLit

suite "syntax_toml - multiline strings":
  test "multiline basic string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"hello\nworld\"\"\"")
    g.tomlNextToken()
    check g.kind == gtLongStringLit

  test "multiline literal string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'''hello\nworld'''")
    g.tomlNextToken()
    check g.kind == gtLongStringLit

  test "empty multiline basic string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"\"\"\"")
    g.tomlNextToken()
    check g.kind == gtLongStringLit

  test "empty multiline literal string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''''''")
    g.tomlNextToken()
    check g.kind == gtLongStringLit

suite "syntax_toml - invalid number suffixes":
  test "invalid binary digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b102")
    g.tomlNextToken()
    # Should still tokenize (syntax highlighter is lenient)
    check g.kind == gtDecNumber

  test "invalid hex digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xGHI")
    g.tomlNextToken()
    check g.kind == gtDecNumber

  test "invalid octal digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o89")
    g.tomlNextToken()
    check g.kind == gtDecNumber

  test "binary with trailing letter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b11abc")
    g.tomlNextToken()
    check g.kind == gtDecNumber

  test "hex with trailing invalid":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFzzz")
    g.tomlNextToken()
    check g.kind == gtDecNumber

  test "octal with trailing letter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o77xyz")
    g.tomlNextToken()
    check g.kind == gtDecNumber

suite "syntax_toml - single quote string handling":
  test "single quote does not process escape":
    # In TOML, single-quoted strings are literal (no escape processing)
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello\\nworld'")
    g.tomlNextToken()
    # Should consume entire string as one token (no escape processing)
    check g.kind == gtStringLit
    check g.length == 14

  test "single quote with backslash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'C:\\path\\to\\file'")
    g.tomlNextToken()
    check g.kind == gtStringLit

  test "single quote preserves content":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\t\\n\\r'")
    g.tomlNextToken()
    check g.kind == gtStringLit
    check g.length == 8

suite "syntax_toml - quoted table names":
  test "table with quoted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[\"table.name\"]")
    g.tomlNextToken()
    check g.kind == gtTable

  test "table with single quoted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("['table.name']")
    g.tomlNextToken()
    check g.kind == gtTable

  test "array of tables with quoted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[[\"array.name\"]]")
    g.tomlNextToken()
    check g.kind == gtTable

  test "table with mixed quoted and unquoted":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[section.\"sub.key\"]")
    g.tomlNextToken()
    check g.kind == gtTable

suite "syntax_toml - tomlNumberAndDate helper":
  test "positive sign only returns identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+abc")
    g.tomlNextToken()
    check g.kind == gtIdentifier

  test "negative sign only returns identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-abc")
    g.tomlNextToken()
    check g.kind == gtIdentifier

  test "positive inf":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+inf")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "negative inf":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-inf")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

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

  test "number with underscore separators":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1_000_000")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 9

  test "float with exponent and sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("6.022e+23")
    g.tomlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 9

suite "syntax_toml - isTableHeader helper":
  test "array start is not table header":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[1, 2, 3]")
    g.tomlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "empty brackets not table":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[]")
    g.tomlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "table with space after bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[ section ]")
    g.tomlNextToken()
    check g.kind == gtTable

  test "array of tables detection":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[[ items ]]")
    g.tomlNextToken()
    check g.kind == gtTable

suite "syntax_toml - tomlTable helper":
  test "table closes at newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[section]\nkey = 1")
    g.tomlNextToken()
    check g.kind == gtTable
    check g.length == 9

  test "array of tables closes properly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[[items]]\nname = \"x\"")
    g.tomlNextToken()
    check g.kind == gtTable
    check g.length == 9 # [[items]] is 9 characters (indices 0-8)

  test "nested table name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[a.b.c.d]")
    g.tomlNextToken()
    check g.kind == gtTable
    check g.length == 9

suite "syntax_toml - complex nested structures":
  test "nested inline tables":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("data = {inner = {value = 1}}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens
    check gtDecNumber in tokens

  test "array of inline tables":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("items = [{a = 1}, {b = 2}]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens
    check gtDecNumber in tokens
    check gtPunctuation in tokens

  test "mixed array types":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("mixed = [1, \"two\", 3.0, true]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDecNumber in tokens
    check gtStringLit in tokens
    check gtFloatNumber in tokens
    check gtBoolean in tokens

  test "deeply nested sections":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[a.b.c.d.e.f]")
    g.tomlNextToken()
    check g.kind == gtTable
    check g.length == 13

suite "syntax_toml - gtNone state handling":
  test "at sign produces gtOperator":
    # @ is in opChars, so it's treated as an operator
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.tomlNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "backtick produces gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`")
    g.tomlNextToken()
    check g.kind == gtNone

  test "tilde produces operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("~")
    g.tomlNextToken()
    # ~ is in opChars
    check g.kind == gtOperator

  test "recovery after gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("` valid")
    g.tomlNextToken() # `
    check g.kind == gtNone

    g.tomlNextToken() # space
    check g.kind == gtWhitespace

    g.tomlNextToken() # valid
    check g.kind == gtIdentifier

suite "syntax_toml - array handling":
  test "simple array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[1, 2, 3]")

    g.tomlNextToken() # [
    check g.kind == gtPunctuation
    check g.length == 1

    g.tomlNextToken() # 1
    check g.kind == gtDecNumber

    g.tomlNextToken() # ,
    check g.kind == gtPunctuation

    g.tomlNextToken() # space
    check g.kind == gtWhitespace

    g.tomlNextToken() # 2
    check g.kind == gtDecNumber

  test "nested array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("matrix = [[1, 2], [3, 4]]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # matrix
    check gtPunctuation in tokens # [, ], ,
    check gtDecNumber in tokens # 1, 2, 3, 4

  test "string array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[\"a\", \"b\", \"c\"]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens
    check gtStringLit in tokens

  test "date array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[2024-01-01, 2024-01-02]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens
    check gtDate in tokens

  test "trailing comma in array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[1, 2, 3,]")

    var tokens: seq[TokenClass] = @[]
    var punctCount = 0
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtPunctuation:
        punctCount.inc
      tokens.add(g.kind)

    # [, 3 commas, ] = 5 punctuation marks
    check punctCount == 5

  test "multiline array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      """[
  1,
  2,
  3
]"""
    )

    var tokens: seq[TokenClass] = @[]
    var numCount = 0
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtDecNumber:
        numCount.inc
      tokens.add(g.kind)

    check numCount == 3
    check gtWhitespace in tokens

  test "array with comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      """[
  1, # first
  2, # second
]"""
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtComment in tokens
    check gtDecNumber in tokens

  test "empty nested array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("arr = [[]]")

    var tokens: seq[TokenClass] = @[]
    var punctCount = 0
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtPunctuation:
        punctCount.inc
      tokens.add(g.kind)

    # = [, [, ], ] = 4 punctuation (= is operator)
    check punctCount == 4

  test "array vs table header distinction":
    # [section] is table, [1] is array
    var g1: GeneralTokenizer
    g1.initGeneralTokenizer("[section]")
    g1.tomlNextToken()
    check g1.kind == gtTable

    var g2: GeneralTokenizer
    g2.initGeneralTokenizer("[1]")
    g2.tomlNextToken()
    check g2.kind == gtPunctuation # [ as array start

  test "float array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[1.0, 2.5, 3.14]")

    var tokens: seq[TokenClass] = @[]
    var floatCount = 0
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtFloatNumber:
        floatCount.inc
      tokens.add(g.kind)

    check floatCount == 3

  test "boolean array":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[true, false, true]")

    var tokens: seq[TokenClass] = @[]
    var boolCount = 0
    while true:
      g.tomlNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtBoolean:
        boolCount.inc
      tokens.add(g.kind)

    check boolCount == 3

suite "syntax_toml - escape sequence edge cases":
  test "incomplete hex escape \\x with no digits":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\x\"")
    g.tomlNextToken() # "
    check g.kind == gtStringLit

    g.tomlNextToken() # \x
    check g.kind == gtEscapeSequence
    check g.length == 2 # Just \x

  test "incomplete hex escape \\x with one digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\x4\"")
    g.tomlNextToken() # "
    g.tomlNextToken() # \x4
    check g.kind == gtEscapeSequence
    check g.length == 3 # \x4

  test "hex escape with invalid char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xGG\"")
    g.tomlNextToken() # "
    g.tomlNextToken() # \x (G is not hex)
    check g.kind == gtEscapeSequence
    check g.length == 2

  test "incomplete unicode \\u with less than 4 digits":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\u00\"")
    g.tomlNextToken() # "
    g.tomlNextToken() # \u00
    check g.kind == gtEscapeSequence
    check g.length == 4 # \u00

  test "incomplete unicode \\U with less than 8 digits":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\U0001\"")
    g.tomlNextToken() # "
    g.tomlNextToken() # \U0001
    check g.kind == gtEscapeSequence
    check g.length == 6 # \U0001

  test "escape at end of input":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\")
    g.tomlNextToken() # "
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tomlNextToken() # \
    check g.kind == gtEscapeSequence

  test "double backslash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\\\\"")
    g.tomlNextToken() # "
    g.tomlNextToken() # \\
    check g.kind == gtEscapeSequence
    check g.length == 2

    g.tomlNextToken() # "
    check g.kind == gtStringLit
    check g.state == gtNone

suite "syntax_toml - multiline string edge cases":
  test "empty multiline basic string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"\"\"\"")
    g.tomlNextToken()
    check g.kind == gtLongStringLit
    check g.length == 6

  test "empty multiline literal string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''''''")
    g.tomlNextToken()
    check g.kind == gtLongStringLit
    check g.length == 6

  test "multiline with single quote inside":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"say \"hello\"\"\"\"")
    g.tomlNextToken()
    check g.kind == gtLongStringLit

  test "multiline with double quote inside":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'''say ''wow'''")
    g.tomlNextToken()
    check g.kind == gtLongStringLit

  test "unterminated multiline basic string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"unclosed")
    g.tomlNextToken()
    check g.kind == gtLongStringLit
    # Should consume until EOF

  test "unterminated multiline literal string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'''unclosed")
    g.tomlNextToken()
    check g.kind == gtLongStringLit

  test "multiline with only newlines":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"\n\n\n\"\"\"")
    g.tomlNextToken()
    check g.kind == gtLongStringLit

suite "syntax_toml - number edge cases":
  test "positive zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+0")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

  test "negative zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-0")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

  test "leading zeros in hex":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0x00FF")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 6

  test "single underscore between digits":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1_2")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "multiple underscores":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1__2")
    g.tomlNextToken()
    check g.kind == gtDecNumber

  test "float with leading dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".5")
    g.tomlNextToken()
    # Leading dot is operator, not number
    check g.kind == gtOperator

  test "exponent only":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e")
    g.tomlNextToken()
    check g.kind == gtFloatNumber

  test "very large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("99999999999999999999")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 20

  test "binary all ones":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b11111111")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

  test "octal max":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o777")
    g.tomlNextToken()
    check g.kind == gtDecNumber
    check g.length == 5

suite "syntax_toml - table edge cases":
  test "table with spaces in name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[\"key with spaces\"]")
    g.tomlNextToken()
    check g.kind == gtTable

  test "deeply nested dotted table":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[a.b.c.d.e.f.g.h]")
    g.tomlNextToken()
    check g.kind == gtTable

  test "array of tables deeply nested":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[[a.b.c.d]]")
    g.tomlNextToken()
    check g.kind == gtTable

  test "table followed immediately by key":
    # Note: tomlTable reads until newline, so key=1 is included in table token
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[section]\nkey=1")

    g.tomlNextToken() # [section]
    check g.kind == gtTable
    check g.length == 9

    g.tomlNextToken() # newline
    check g.kind == gtWhitespace

    g.tomlNextToken() # key
    check g.kind == gtIdentifier

  test "empty table name":
    # [\"\"] is technically valid TOML with empty quoted key
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[\"\"]")
    g.tomlNextToken()
    check g.kind == gtTable

suite "syntax_toml - comment edge cases":
  test "empty comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.tomlNextToken()
    check g.kind == gtComment
    check g.length == 1

  test "comment with only spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#   ")
    g.tomlNextToken()
    check g.kind == gtComment
    check g.length == 4

  test "comment with hash inside":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment ## more")
    g.tomlNextToken()
    check g.kind == gtComment

  test "multiple comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# line1\n# line2")

    g.tomlNextToken() # # line1
    check g.kind == gtComment

    g.tomlNextToken() # newline
    check g.kind == gtWhitespace

    g.tomlNextToken() # # line2
    check g.kind == gtComment

suite "syntax_toml - identifier edge cases":
  test "single character identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a")
    g.tomlNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

  test "identifier starting with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.tomlNextToken()
    check g.kind == gtIdentifier

  test "identifier with many underscores":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("__double__underscore__")
    g.tomlNextToken()
    check g.kind == gtIdentifier

  test "identifier resembling keyword prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("trueish")
    g.tomlNextToken()
    check g.kind == gtIdentifier # Not boolean

  test "identifier resembling keyword prefix false":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("falsehood")
    g.tomlNextToken()
    check g.kind == gtIdentifier

  test "CJK identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("日本語キー")
    g.tomlNextToken()
    check g.kind == gtIdentifier

  test "mixed ascii and unicode":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key_キー_123")
    g.tomlNextToken()
    check g.kind == gtIdentifier

suite "syntax_toml - operator and punctuation edge cases":
  test "consecutive operators":
    # Note: + and - are handled by tomlNumberAndDate, so use other operators
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*/&|")
    g.tomlNextToken()
    check g.kind == gtOperator
    check g.length == 4

  test "all punctuation marks":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[]{},")

    g.tomlNextToken() # [
    check g.kind == gtPunctuation
    g.tomlNextToken() # ]
    check g.kind == gtPunctuation
    g.tomlNextToken() # {
    check g.kind == gtPunctuation
    g.tomlNextToken() # }
    check g.kind == gtPunctuation
    g.tomlNextToken() # ,
    check g.kind == gtPunctuation

  test "equals sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.tomlNextToken()
    check g.kind == gtOperator

  test "dot as operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.tomlNextToken()
    check g.kind == gtOperator

suite "syntax_toml - whitespace edge cases":
  test "only whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   \t\t\n\n")
    g.tomlNextToken()
    check g.kind == gtWhitespace

  test "carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\r\n")
    g.tomlNextToken()
    check g.kind == gtWhitespace

  test "mixed whitespace types":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \t \n \r\n ")
    g.tomlNextToken()
    check g.kind == gtWhitespace

suite "syntax_toml - date/time edge cases":
  test "date with timezone offset":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T10:30:00+09:00")
    g.tomlNextToken()
    check g.kind == gtDate

  test "date with negative timezone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-15T10:30:00-05:00")
    g.tomlNextToken()
    check g.kind == gtDate

  test "time with microseconds":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("10:30:00.123456")
    g.tomlNextToken()
    check g.kind == gtDate

  test "minimal date":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-01")
    g.tomlNextToken()
    check g.kind == gtDate
    check g.length == 10

  test "minimal time":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("00:00:00")
    g.tomlNextToken()
    check g.kind == gtDate
    check g.length == 8
