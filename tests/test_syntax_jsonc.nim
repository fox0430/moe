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

import ../src/moepkg/syntax/[tokenizer, syntax_jsonc]

suite "syntax_jsonc - jsoncNextToken keywords":
  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.jsoncNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.jsoncNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "null keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.jsoncNextToken()
    check g.kind == gtKeyword
    check g.length == 4

suite "syntax_jsonc - jsoncNextToken numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.jsoncNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.jsoncNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "number followed by identifier splits cleanly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123abc")
    g.jsoncNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

    g.jsoncNextToken()
    check g.kind == gtIdentifier
    check g.length == 3

suite "syntax_jsonc - jsoncNextToken strings":
  test "simple string value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.jsoncNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "string with slash content is not a comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a/b//c\"")
    g.jsoncNextToken()
    check g.kind == gtStringLit
    check g.length == 8

  test "key detection (string followed by colon)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"key\":")
    g.jsoncNextToken()
    check g.kind == gtKey
    check g.length == 5

  test "key detection with block comment between key and colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"key\" /* note */ : 1")
    g.jsoncNextToken()
    check g.kind == gtKey
    check g.length == 5

  test "key detection with line comment between key and colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"key\" // note\n  : 1")
    g.jsoncNextToken()
    check g.kind == gtKey
    check g.length == 5

  test "string value remains stringLit when no colon follows":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"value\" /* note */ ,")
    g.jsoncNextToken()
    check g.kind == gtStringLit
    check g.length == 7

suite "syntax_jsonc - jsoncNextToken punctuation":
  test "opening brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.jsoncNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.jsoncNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.jsoncNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_jsonc - jsoncNextToken line comments":
  test "line comment alone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// this is a comment")
    g.jsoncNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "line comment terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// abc\nrest")
    g.jsoncNextToken()
    check g.kind == gtComment
    check g.length == 6
    # Next token should be the newline as whitespace
    g.jsoncNextToken()
    check g.kind == gtWhitespace

  test "line comment after value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("42 // tail")
    g.jsoncNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

    g.jsoncNextToken()
    check g.kind == gtWhitespace

    g.jsoncNextToken()
    check g.kind == gtComment
    check g.length == 7

  test "empty line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("//")
    g.jsoncNextToken()
    check g.kind == gtComment
    check g.length == 2

suite "syntax_jsonc - jsoncNextToken block comments":
  test "single-line block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* hi */")
    g.jsoncNextToken()
    check g.kind == gtLongComment
    check g.length == 8
    check g.state == gtNone

  test "block comment containing slashes and stars":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* a/b * c */")
    g.jsoncNextToken()
    check g.kind == gtLongComment
    check g.length == 13
    check g.state == gtNone

  test "block comment with newline (consumed in one call)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* line1\nline2 */")
    g.jsoncNextToken()
    check g.kind == gtLongComment
    check g.state == gtNone

  test "unterminated block comment sets state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* unterminated")
    g.jsoncNextToken()
    check g.kind == gtLongComment
    check g.state == gtLongComment

  test "block comment continuation across buffers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* part1")
    g.jsoncNextToken()
    check g.kind == gtLongComment
    check g.state == gtLongComment

    # Simulate continuation: re-init buffer but keep state.
    let savedState = g.state
    g.initGeneralTokenizer("more */")
    g.state = savedState
    g.jsoncNextToken()
    check g.kind == gtLongComment
    check g.state == gtNone

  test "empty block comment /**/":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**/")
    g.jsoncNextToken()
    check g.kind == gtLongComment
    check g.length == 4
    check g.state == gtNone

suite "syntax_jsonc - mixed JSON + comments":
  test "object with comment between key and value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{\"k\": /* c */ 1}")

    g.jsoncNextToken()
    check g.kind == gtPunctuation # {

    g.jsoncNextToken()
    check g.kind == gtKey # "k"

    g.jsoncNextToken()
    check g.kind == gtOperator # :

    g.jsoncNextToken()
    check g.kind == gtWhitespace

    g.jsoncNextToken()
    check g.kind == gtLongComment # /* c */

    g.jsoncNextToken()
    check g.kind == gtWhitespace

    g.jsoncNextToken()
    check g.kind == gtDecNumber # 1

    g.jsoncNextToken()
    check g.kind == gtPunctuation # }

  test "array with line comment between elements":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[1, // c\n2]")

    g.jsoncNextToken()
    check g.kind == gtPunctuation # [
    g.jsoncNextToken()
    check g.kind == gtDecNumber # 1
    g.jsoncNextToken()
    check g.kind == gtPunctuation # ,
    g.jsoncNextToken()
    check g.kind == gtWhitespace
    g.jsoncNextToken()
    check g.kind == gtComment # // c
    g.jsoncNextToken()
    check g.kind == gtWhitespace # \n
    g.jsoncNextToken()
    check g.kind == gtDecNumber # 2
    g.jsoncNextToken()
    check g.kind == gtPunctuation # ]

  test "slash as operator when not start of comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/x")
    g.jsoncNextToken()
    check g.kind == gtOperator
    check g.length == 1
