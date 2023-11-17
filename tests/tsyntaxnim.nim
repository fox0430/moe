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
    token.getNextToken(SourceLanguage.langNim)
    if token.kind == gtEof: break
    else:
      result.add token
      # Clear token.buf
      result[^1].buf = ""

suite "syntax: Nim":
  test "Basic":
    const Code = """
import std/strformat

proc sum(a, b: int): int {.inline.} =
  result = a + b

proc showAndReturn(s: string): string =
  ## Comment1
  ## Comment2

  echo fmt"{s}"
  # Comment3
  return s

echo sum(1, 2)
let s = "str"
showAndReturn(s)
"""
    check tokens(Code) == @[
      GT(kind: gtKeyword, start: 0, length: 6, buf: "", pos: 6, state: gtEof),
      GT(kind: gtWhitespace, start: 6, length: 1, buf: "", pos: 7, state: gtEof),
      GT(kind: gtBuiltin, start: 7, length: 3, buf: "", pos: 10, state: gtEof),
      GT(kind: gtOperator, start: 10, length: 1, buf: "", pos: 11, state: gtEof),
      GT(kind: gtBuiltin, start: 11, length: 9, buf: "", pos: 20, state: gtEof),
      GT(kind: gtWhitespace, start: 20, length: 2, buf: "", pos: 22, state: gtEof),
      GT(kind: gtKeyword, start: 22, length: 4, buf: "", pos: 26, state: gtEof),
      GT(kind: gtWhitespace, start: 26, length: 1, buf: "", pos: 27, state: gtEof),
      GT(kind: gtFunctionName, start: 27, length: 3, buf: "", pos: 30, state: gtEof),
      GT(kind: gtPunctuation, start: 30, length: 1, buf: "", pos: 31, state: gtEof),
      GT(kind: gtIdentifier, start: 31, length: 1, buf: "", pos: 32, state: gtEof),
      GT(kind: gtPunctuation, start: 32, length: 1, buf: "", pos: 33, state: gtEof),
      GT(kind: gtWhitespace, start: 33, length: 1, buf: "", pos: 34, state: gtEof),
      GT(kind: gtIdentifier, start: 34, length: 1, buf: "", pos: 35, state: gtEof),
      GT(kind: gtPunctuation, start: 35, length: 1, buf: "", pos: 36, state: gtEof),
      GT(kind: gtWhitespace, start: 36, length: 1, buf: "", pos: 37, state: gtEof),
      GT(kind: gtBuiltin, start: 37, length: 3, buf: "", pos: 40, state: gtEof),
      GT(kind: gtPunctuation, start: 40, length: 1, buf: "", pos: 41, state: gtEof),
      GT(kind: gtPunctuation, start: 41, length: 1, buf: "", pos: 42, state: gtEof),
      GT(kind: gtWhitespace, start: 42, length: 1, buf: "", pos: 43, state: gtEof),
      GT(kind: gtBuiltin, start: 43, length: 3, buf: "", pos: 46, state: gtEof),
      GT(kind: gtWhitespace, start: 46, length: 1, buf: "", pos: 47, state: gtEof),
      GT(kind: gtPunctuation, start: 47, length: 1, buf: "", pos: 48, state: gtEof),
      GT(kind: gtOperator, start: 48, length: 1, buf: "", pos: 49, state: gtEof),
      GT(kind: gtPragma, start: 49, length: 6, buf: "", pos: 55, state: gtEof),
      GT(kind: gtOperator, start: 55, length: 1, buf: "", pos: 56, state: gtEof),
      GT(kind: gtPunctuation, start: 56, length: 1, buf: "", pos: 57, state: gtEof),
      GT(kind: gtWhitespace, start: 57, length: 1, buf: "", pos: 58, state: gtEof),
      GT(kind: gtOperator, start: 58, length: 1, buf: "", pos: 59, state: gtEof),
      GT(kind: gtWhitespace, start: 59, length: 3, buf: "", pos: 62, state: gtEof),
      GT(kind: gtSpecialVar, start: 62, length: 6, buf: "", pos: 68, state: gtEof),
      GT(kind: gtWhitespace, start: 68, length: 1, buf: "", pos: 69, state: gtEof),
      GT(kind: gtOperator, start: 69, length: 1, buf: "", pos: 70, state: gtEof),
      GT(kind: gtWhitespace, start: 70, length: 1, buf: "", pos: 71, state: gtEof),
      GT(kind: gtIdentifier, start: 71, length: 1, buf: "", pos: 72, state: gtEof),
      GT(kind: gtWhitespace, start: 72, length: 1, buf: "", pos: 73, state: gtEof),
      GT(kind: gtOperator, start: 73, length: 1, buf: "", pos: 74, state: gtEof),
      GT(kind: gtWhitespace, start: 74, length: 1, buf: "", pos: 75, state: gtEof),
      GT(kind: gtIdentifier, start: 75, length: 1, buf: "", pos: 76, state: gtEof),
      GT(kind: gtWhitespace, start: 76, length: 2, buf: "", pos: 78, state: gtEof),
      GT(kind: gtKeyword, start: 78, length: 4, buf: "", pos: 82, state: gtEof),
      GT(kind: gtWhitespace, start: 82, length: 1, buf: "", pos: 83, state: gtEof),
      GT(kind: gtFunctionName, start: 83, length: 13, buf: "", pos: 96, state: gtEof),
      GT(kind: gtPunctuation, start: 96, length: 1, buf: "", pos: 97, state: gtEof),
      GT(kind: gtIdentifier, start: 97, length: 1, buf: "", pos: 98, state: gtEof),
      GT(kind: gtPunctuation, start: 98, length: 1, buf: "", pos: 99, state: gtEof),
      GT(kind: gtWhitespace, start: 99, length: 1, buf: "", pos: 100, state: gtEof),
      GT(kind: gtBuiltin, start: 100, length: 6, buf: "", pos: 106, state: gtEof),
      GT(kind: gtPunctuation, start: 106, length: 1, buf: "", pos: 107, state: gtEof),
      GT(kind: gtPunctuation, start: 107, length: 1, buf: "", pos: 108, state: gtEof),
      GT(kind: gtWhitespace, start: 108, length: 1, buf: "", pos: 109, state: gtEof),
      GT(kind: gtBuiltin, start: 109, length: 6, buf: "", pos: 115, state: gtEof),
      GT(kind: gtWhitespace, start: 115, length: 1, buf: "", pos: 116, state: gtEof),
      GT(kind: gtOperator, start: 116, length: 1, buf: "", pos: 117, state: gtEof),
      GT(kind: gtWhitespace, start: 117, length: 3, buf: "", pos: 120, state: gtEof),
      GT(kind: gtComment, start: 120, length: 11, buf: "", pos: 131, state: gtEof),
      GT(kind: gtWhitespace, start: 131, length: 3, buf: "", pos: 134, state: gtEof),
      GT(kind: gtComment, start: 134, length: 11, buf: "", pos: 145, state: gtEof),
      GT(kind: gtWhitespace, start: 145, length: 4, buf: "", pos: 149, state: gtEof),
      GT(kind: gtBuiltin, start: 149, length: 4, buf: "", pos: 153, state: gtEof),
      GT(kind: gtWhitespace, start: 153, length: 1, buf: "", pos: 154, state: gtEof),
      GT(kind: gtBuiltin, start: 154, length: 3, buf: "", pos: 157, state: gtEof),
      GT(kind: gtStringLit, start: 157, length: 5, buf: "", pos: 162, state: gtEof),
      GT(kind: gtWhitespace, start: 162, length: 3, buf: "", pos: 165, state: gtEof),
      GT(kind: gtComment, start: 165, length: 10, buf: "", pos: 175, state: gtEof),
      GT(kind: gtWhitespace, start: 175, length: 3, buf: "", pos: 178, state: gtEof),
      GT(kind: gtKeyword, start: 178, length: 6, buf: "", pos: 184, state: gtEof),
      GT(kind: gtWhitespace, start: 184, length: 1, buf: "", pos: 185, state: gtEof),
      GT(kind: gtIdentifier, start: 185, length: 1, buf: "", pos: 186, state: gtEof),
      GT(kind: gtWhitespace, start: 186, length: 2, buf: "", pos: 188, state: gtEof),
      GT(kind: gtBuiltin, start: 188, length: 4, buf: "", pos: 192, state: gtEof),
      GT(kind: gtWhitespace, start: 192, length: 1, buf: "", pos: 193, state: gtEof),
      GT(kind: gtFunctionName, start: 193, length: 3, buf: "", pos: 196, state: gtEof),
      GT(kind: gtPunctuation, start: 196, length: 1, buf: "", pos: 197, state: gtEof),
      GT(kind: gtDecNumber, start: 197, length: 1, buf: "", pos: 198, state: gtEof),
      GT(kind: gtPunctuation, start: 198, length: 1, buf: "", pos: 199, state: gtEof),
      GT(kind: gtWhitespace, start: 199, length: 1, buf: "", pos: 200, state: gtEof),
      GT(kind: gtDecNumber, start: 200, length: 1, buf: "", pos: 201, state: gtEof),
      GT(kind: gtPunctuation, start: 201, length: 1, buf: "", pos: 202, state: gtEof),
      GT(kind: gtWhitespace, start: 202, length: 1, buf: "", pos: 203, state: gtEof),
      GT(kind: gtKeyword, start: 203, length: 3, buf: "", pos: 206, state: gtEof),
      GT(kind: gtWhitespace, start: 206, length: 1, buf: "", pos: 207, state: gtEof),
      GT(kind: gtIdentifier, start: 207, length: 1, buf: "", pos: 208, state: gtEof),
      GT(kind: gtWhitespace, start: 208, length: 1, buf: "", pos: 209, state: gtEof),
      GT(kind: gtOperator, start: 209, length: 1, buf: "", pos: 210, state: gtEof),
      GT(kind: gtWhitespace, start: 210, length: 1, buf: "", pos: 211, state: gtEof),
      GT(kind: gtStringLit, start: 211, length: 5, buf: "", pos: 216, state: gtEof),
      GT(kind: gtWhitespace, start: 216, length: 1, buf: "", pos: 217, state: gtEof),
      GT(kind: gtFunctionName, start: 217, length: 13, buf: "", pos: 230, state: gtEof),
      GT(kind: gtPunctuation, start: 230, length: 1, buf: "", pos: 231, state: gtEof),
      GT(kind: gtIdentifier, start: 231, length: 1, buf: "", pos: 232, state: gtEof),
      GT(kind: gtPunctuation, start: 232, length: 1, buf: "", pos: 233, state: gtEof),
      GT(kind: gtWhitespace, start: 233, length: 1, buf: "", pos: 234, state: gtEof)
    ]

  test "fmt":
    const Code = "echo fmt\"{value}\""
    check tokens(Code) == @[
      GT(kind: gtBuiltin, start: 0, length: 4, buf: "", pos: 4, state: gtEof),
      GT(kind: gtWhitespace, start: 4, length: 1, buf: "", pos: 5, state: gtEof),
      GT(kind: gtBuiltin, start: 5, length: 3, buf: "", pos: 8, state: gtEof),
      GT(kind: gtStringLit, start: 8, length: 9, buf: "", pos: 17, state: gtEof)
    ]

  test "Comment":
    const Code = "# Comment"
    check tokens(Code) == @[
      GT(kind: gtComment, start: 0, length: 9, buf: "", pos: 9, state: gtEof),
    ]

  test "Comment 2":
    const Code = "## Comment"
    check tokens(Code) == @[
      GT(kind: gtComment, start: 0, length: 10, buf: "", pos: 10, state: gtEof),
    ]

  test "Comment 3":
    const Code = "#[ Line1\n   Line2 ]#"
    check tokens(Code) == @[
      GT(kind: gtLongComment, start: 0, length: 20, buf: "", pos: 20, state: gtEof),
    ]
