#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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
import moepkg/syntax/highlite

type
  GT = GeneralTokenizer

proc tokens(code: string): seq[GT] =
  var token = GeneralTokenizer()
  token.initGeneralTokenizer(code)

  while true:
    token.getNextToken(SourceLanguage.langToml)
    if token.kind == gtEof: break
    else:
      result.add token
      # Clear token.buf
      result[^1].buf = ""

suite "syntax: Toml":

  test "Basic":
    const Code = """
[table]
# Comment1
str = "value" # Comment2
bool1 = true
bool2 = false
dec = 1
float = 1.0
inlineTasble = { name = "Tom" }
date = 1979-05-27T07:32:00Z

[table2]
str2 = '''Here are two quotation marks: "". Simple enough.'''
"""
    check tokens(Code) == @[
      Gt(kind: gtTable, start: 0, length: 7, buf: "", pos: 7, state: gtEof),
      Gt(kind: gtWhitespace, start: 7, length: 1, buf: "", pos: 8, state: gtEof),
      Gt(kind: gtComment, start: 8, length: 10, buf: "", pos: 18, state: gtEof),
      Gt(kind: gtWhitespace, start: 18, length: 1, buf: "", pos: 19, state: gtEof),
      Gt(kind: gtIdentifier, start: 19, length: 3, buf: "", pos: 22, state: gtEof),
      Gt(kind: gtWhitespace, start: 22, length: 1, buf: "", pos: 23, state: gtEof),
      Gt(kind: gtOperator, start: 23, length: 1, buf: "", pos: 24, state: gtEof),
      Gt(kind: gtWhitespace, start: 24, length: 1, buf: "", pos: 25, state: gtEof),
      Gt(kind: gtStringLit, start: 25, length: 7, buf: "", pos: 32, state: gtEof),
      Gt(kind: gtWhitespace, start: 32, length: 1, buf: "", pos: 33, state: gtEof),
      Gt(kind: gtComment, start: 33, length: 10, buf: "", pos: 43, state: gtEof),
      Gt(kind: gtWhitespace, start: 43, length: 1, buf: "", pos: 44, state: gtEof),
      Gt(kind: gtIdentifier, start: 44, length: 5, buf: "", pos: 49, state: gtEof),
      Gt(kind: gtWhitespace, start: 49, length: 1, buf: "", pos: 50, state: gtEof),
      Gt(kind: gtOperator, start: 50, length: 1, buf: "", pos: 51, state: gtEof),
      Gt(kind: gtWhitespace, start: 51, length: 1, buf: "", pos: 52, state: gtEof),
      Gt(kind: gtBoolean, start: 52, length: 4, buf: "", pos: 56, state: gtEof),
      Gt(kind: gtWhitespace, start: 56, length: 1, buf: "", pos: 57, state: gtEof),
      Gt(kind: gtIdentifier, start: 57, length: 5, buf: "", pos: 62, state: gtEof),
      Gt(kind: gtWhitespace, start: 62, length: 1, buf: "", pos: 63, state: gtEof),
      Gt(kind: gtOperator, start: 63, length: 1, buf: "", pos: 64, state: gtEof),
      Gt(kind: gtWhitespace, start: 64, length: 1, buf: "", pos: 65, state: gtEof),
      Gt(kind: gtBoolean, start: 65, length: 5, buf: "", pos: 70, state: gtEof),
      Gt(kind: gtWhitespace, start: 70, length: 1, buf: "", pos: 71, state: gtEof),
      Gt(kind: gtIdentifier, start: 71, length: 3, buf: "", pos: 74, state: gtEof),
      Gt(kind: gtWhitespace, start: 74, length: 1, buf: "", pos: 75, state: gtEof),
      Gt(kind: gtOperator, start: 75, length: 1, buf: "", pos: 76, state: gtEof),
      Gt(kind: gtWhitespace, start: 76, length: 1, buf: "", pos: 77, state: gtEof),
      Gt(kind: gtDecNumber, start: 77, length: 1, buf: "", pos: 78, state: gtEof),
      Gt(kind: gtWhitespace, start: 78, length: 1, buf: "", pos: 79, state: gtEof),
      Gt(kind: gtIdentifier, start: 79, length: 5, buf: "", pos: 84, state: gtEof),
      Gt(kind: gtWhitespace, start: 84, length: 1, buf: "", pos: 85, state: gtEof),
      Gt(kind: gtOperator, start: 85, length: 1, buf: "", pos: 86, state: gtEof),
      Gt(kind: gtWhitespace, start: 86, length: 1, buf: "", pos: 87, state: gtEof),
      Gt(kind: gtFloatNumber, start: 87, length: 3, buf: "", pos: 90, state: gtEof),
      Gt(kind: gtWhitespace, start: 90, length: 1, buf: "", pos: 91, state: gtEof),
      Gt(kind: gtIdentifier, start: 91, length: 12, buf: "", pos: 103, state: gtEof),
      Gt(kind: gtWhitespace, start: 103, length: 1, buf: "", pos: 104, state: gtEof),
      Gt(kind: gtOperator, start: 104, length: 1, buf: "", pos: 105, state: gtEof),
      Gt(kind: gtWhitespace, start: 105, length: 1, buf: "", pos: 106, state: gtEof),
      Gt(kind: gtNone, start: 106, length: 1, buf: "", pos: 107, state: gtEof),
      Gt(kind: gtWhitespace, start: 107, length: 1, buf: "", pos: 108, state: gtEof),
      Gt(kind: gtIdentifier, start: 108, length: 4, buf: "", pos: 112, state: gtEof),
      Gt(kind: gtWhitespace, start: 112, length: 1, buf: "", pos: 113, state: gtEof),
      Gt(kind: gtOperator, start: 113, length: 1, buf: "", pos: 114, state: gtEof),
      Gt(kind: gtWhitespace, start: 114, length: 1, buf: "", pos: 115, state: gtEof),
      Gt(kind: gtStringLit, start: 115, length: 5, buf: "", pos: 120, state: gtEof),
      Gt(kind: gtWhitespace, start: 120, length: 1, buf: "", pos: 121, state: gtEof),
      Gt(kind: gtNone, start: 121, length: 1, buf: "", pos: 122, state: gtEof),
      Gt(kind: gtWhitespace, start: 122, length: 1, buf: "", pos: 123, state: gtEof),
      Gt(kind: gtIdentifier, start: 123, length: 4, buf: "", pos: 127, state: gtEof),
      Gt(kind: gtWhitespace, start: 127, length: 1, buf: "", pos: 128, state: gtEof),
      Gt(kind: gtOperator, start: 128, length: 1, buf: "", pos: 129, state: gtEof),
      Gt(kind: gtWhitespace, start: 129, length: 1, buf: "", pos: 130, state: gtEof),
      Gt(kind: gtDate, start: 130, length: 20, buf: "", pos: 150, state: gtEof),
      Gt(kind: gtWhitespace, start: 150, length: 2, buf: "", pos: 152, state: gtEof),
      Gt(kind: gtTable, start: 152, length: 8, buf: "", pos: 160, state: gtEof),
      Gt(kind: gtWhitespace, start: 160, length: 1, buf: "", pos: 161, state: gtEof),
      Gt(kind: gtIdentifier, start: 161, length: 4, buf: "", pos: 165, state: gtEof),
      Gt(kind: gtWhitespace, start: 165, length: 1, buf: "", pos: 166, state: gtEof),
      Gt(kind: gtOperator, start: 166, length: 1, buf: "", pos: 167, state: gtEof),
      Gt(kind: gtWhitespace, start: 167, length: 1, buf: "", pos: 168, state: gtEof),
      Gt(kind: gtStringLit, start: 168, length: 2, buf: "", pos: 170, state: gtEof),
      Gt(kind: gtStringLit, start: 170, length: 32, buf: "", pos: 202, state: gtEof),
      Gt(kind: gtStringLit, start: 202, length: 18, buf: "", pos: 220, state: gtEof),
      Gt(kind: gtStringLit, start: 220, length: 2, buf: "", pos: 222, state: gtEof),
      Gt(kind: gtWhitespace, start: 222, length: 1, buf: "", pos: 223, state: gtEof)
    ]

  test "Comment":
    const Code = "# comment"
    check tokens(Code) == @[
      GT(kind: gtComment, start: 0, length: 9, buf: "", pos: 9, state: gtEof)
    ]

  test "Comment 2":
    const Code = """key = "value" # comment"""
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtStringLit, start: 6, length: 7, buf: "", pos: 13, state: gtEof),
      GT(kind: gtWhitespace, start: 13, length: 1, buf: "", pos: 14, state: gtEof),
      GT(kind: gtComment, start: 14, length: 9, buf: "", pos: 23, state: gtEof)
    ]

  test "String":
    const Code = """str = "val""""
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtStringLit, start: 6, length: 5, buf: "", pos: 11, state: gtEof)
    ]

  test "String 2":
    const Code = "str = \"\"\"val\"\"\""
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtStringLit, start: 6, length: 2, buf: "", pos: 8, state: gtEof),
      GT(kind: gtStringLit, start: 8, length: 5, buf: "", pos: 13, state: gtEof),
      GT(kind: gtStringLit, start: 13, length: 2, buf: "", pos: 15, state: gtEof)
    ]

  test "String 3":
    const Code = "str = \"\"\"line1\nline2\"\"\""
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtStringLit, start: 6, length: 2, buf: "", pos: 8, state: gtEof),
      GT(kind: gtStringLit, start: 8, length: 13, buf: "", pos: 21, state: gtEof),
      GT(kind: gtStringLit, start: 21, length: 2, buf: "", pos: 23, state: gtEof)
    ]

  test "Incomplete String":
    const Code = """str = "a"""
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtStringLit, start: 6, length: 2, buf: "", pos: 8, state: gtEof)
    ]

  test "Number":
    const Code = "num = 1"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtDecNumber, start: 6, length: 1, buf: "", pos: 7, state: gtEof)
    ]

  test "Number 2":
    const Code = "num = 132"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtDecNumber, start: 6, length: 3, buf: "", pos: 9, state: gtEof)
    ]

  test "Float":
    const Code = "num = 1.0"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 3, buf: "", pos: 9, state: gtEof)
    ]

  test "Positive":
    const Code = "num = +1"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtDecNumber, start: 6, length: 2, buf: "", pos: 8, state: gtEof)
    ]

  test "Positive float":
    const Code = "num = +1.0"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 4, buf: "", pos: 10, state: gtEof)
    ]

  test "Incomplete positive":
    const Code = "num = +"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtIdentifier, start: 6, length: 1, buf: "", pos: 7, state: gtEof)
    ]

  test "Negative":
    const Code = "num = -1"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtDecNumber, start: 6, length: 2, buf: "", pos: 8, state: gtEof)
    ]

  test "Negative float":
    const Code = "num = -1.0"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 4, buf: "", pos: 10, state: gtEof)
    ]

  test "Incomplete negative":
    const Code = "num = -"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtIdentifier, start: 6, length: 1, buf: "", pos: 7, state: gtEof)
    ]

  test "Exponent":
    const Code = "num = 1e+1"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 4, buf: "", pos: 10, state: gtEof)
    ]

  test "Exponent 2":
    const Code = "num = 1E+1"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 4, buf: "", pos: 10, state: gtEof)
    ]

  test "Exponent 3":
    const Code = "num = 1.e+1"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 5, buf: "", pos: 11, state: gtEof)
    ]

  test "Positive exponent":
    const Code = "num = +1e+1"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 5, buf: "", pos: 11, state: gtEof)
    ]

  test "Negative exponent":
    const Code = "num = -1e+1"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 5, buf: "", pos: 11, state: gtEof)
    ]

  test "Under score":
    const Code = "num = 1_2"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtDecNumber, start: 6, length: 3, buf: "", pos: 9, state: gtEof)
    ]

  test "Under score 2":
    const Code = "num = 1_2_3"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtDecNumber, start: 6, length: 5, buf: "", pos: 11, state: gtEof)
    ]

  test "Inf":
    const Code = "num = inf"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 3, buf: "", pos: 9, state: gtEof)
    ]

  test "Positive inf":
    const Code = "num = +inf"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 4, buf: "", pos: 10, state: gtEof)
    ]

  test "Negative inf":
    const Code = "num = -inf"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 4, buf: "", pos: 10, state: gtEof)
    ]

  test "Nan":
    const Code = "num = nan"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 3, buf: "", pos: 9, state: gtEof)
    ]

  test "Positive nan":
    const Code = "num = +nan"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 4, buf: "", pos: 10, state: gtEof)
    ]

  test "Negative nan":
    const Code = "num = -nan"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 3, buf: "", pos: 3, state: gtEof),
      GT(kind: gtWhitespace, start: 3, length: 1, buf: "", pos: 4, state: gtEof),
      GT(kind: gtOperator, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtWhitespace, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtFloatNumber, start: 6, length: 4, buf: "", pos: 10, state: gtEof)
    ]

  test "Date":
    const Code = "date = 1979-05-27T07:32:00Z"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtOperator, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtDate, start: 7, length: 20, buf: "", pos: 27, state: gtEof)
    ]

  test "Date 2":
    const Code = "date = 1979-05-27T00:32:00-07:00"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtOperator, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtDate, start: 7, length: 25, buf: "", pos: 32, state: gtEof)
    ]

  test "Date 3":
    const Code = "date = 1979-05-27T00:32:00.999999-07:00"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtOperator, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtDate, start: 7, length: 32, buf: "", pos: 39, state: gtEof)
    ]

  test "Date 4":
    const Code = "date = 1979-05-27 07:32:00Z"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtOperator, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtDate, start: 7, length: 20, buf: "", pos: 27, state: gtEof)
    ]

  test "Date 5":
    const Code = "date = 1979-05-27T07:32:00"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtOperator, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtDate, start: 7, length: 19, buf: "", pos: 26, state: gtEof)
    ]

  test "Date 6":
    const Code = "date = 1979-05-27T07:32:00.999999"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtOperator, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtDate, start: 7, length: 26, buf: "", pos: 33, state: gtEof)
    ]

  test "Date 7":
    const Code = "date = 1979-05-27"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtOperator, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtDate, start: 7, length: 10, buf: "", pos: 17, state: gtEof)
    ]

  test "Date 8":
    const Code = "date = 1979-05-27.999999"
    check tokens(Code) == @[
      GT(kind: gtIdentifier, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtOperator, start: 5, length: 1, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtDate, start: 7, length: 17, buf: "", pos: 24, state: gtEof)
    ]
