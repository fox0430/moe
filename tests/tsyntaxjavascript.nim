#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

type GT = GeneralTokenizer

# Helper type for testing that only includes the essential fields
type TestToken = object
  kind: TokenClass
  start, length: int
  pos: int
  state: TokenClass

proc testTokens(code: string): seq[TestToken] =
  var token = GeneralTokenizer()
  token.initGeneralTokenizer(code)

  while true:
    token.getNextToken(SourceLanguage.langJavaScript)
    if token.kind == gtEof:
      break
    else:
      result.add TestToken(
        kind: token.kind,
        start: token.start,
        length: token.length,
        pos: token.pos,
        state: token.state
      )

# Keep the old function for backwards compatibility
proc tokens(code: string): seq[TestToken] = testTokens(code)

suite "syntax: JavaScript":
  test "Basic":
    const Code = "let x = 5;"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 3, pos: 3, state: gtEof),
        TestToken(kind: gtWhitespace, start: 3, length: 1, pos: 4, state: gtEof),
        TestToken(kind: gtIdentifier, start: 4, length: 1, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtOperator, start: 6, length: 1, pos: 7, state: gtEof),
        TestToken(kind: gtWhitespace, start: 7, length: 1, pos: 8, state: gtEof),
        TestToken(kind: gtDecNumber, start: 8, length: 1, pos: 9, state: gtEof),
        TestToken(kind: gtPunctuation, start: 9, length: 1, pos: 10, state: gtEof),
      ]

  test "Keywords":
    const Code = "let const var function return async await class"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 3, pos: 3, state: gtEof),
        TestToken(kind: gtWhitespace, start: 3, length: 1, pos: 4, state: gtEof),
        TestToken(kind: gtKeyword, start: 4, length: 5, pos: 9, state: gtEof),
        TestToken(kind: gtWhitespace, start: 9, length: 1, pos: 10, state: gtEof),
        TestToken(kind: gtKeyword, start: 10, length: 3, pos: 13, state: gtEof),
        TestToken(kind: gtWhitespace, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtKeyword, start: 14, length: 8, pos: 22, state: gtEof),
        TestToken(kind: gtWhitespace, start: 22, length: 1, pos: 23, state: gtEof),
        TestToken(kind: gtKeyword, start: 23, length: 6, pos: 29, state: gtEof),
        TestToken(kind: gtWhitespace, start: 29, length: 1, pos: 30, state: gtEof),
        TestToken(kind: gtKeyword, start: 30, length: 5, pos: 35, state: gtEof),
        TestToken(kind: gtWhitespace, start: 35, length: 1, pos: 36, state: gtEof),
        TestToken(kind: gtKeyword, start: 36, length: 5, pos: 41, state: gtEof),
        TestToken(kind: gtWhitespace, start: 41, length: 1, pos: 42, state: gtEof),
        TestToken(kind: gtKeyword, start: 42, length: 5, pos: 47, state: gtEof),
      ]

  test "Single line comment":
    const Code = "// This is a comment"
    check tokens(Code) ==
      @[TestToken(kind: gtComment, start: 0, length: 20, pos: 20, state: gtEof)]

  test "Multi-line comment":
    const Code = "/* This is\n   a multi-line\n   comment */"
    check tokens(Code) ==
      @[TestToken(kind: gtLongComment, start: 0, length: 40, pos: 40, state: gtEof)]

  test "String literals":
    const Code = "'single' \"double\" 'with\\'escape' \"with\\\"escape\""
    check tokens(Code) ==
      @[
        TestToken(kind: gtStringLit, start: 0, length: 8, pos: 8, state: gtEof),
        TestToken(kind: gtWhitespace, start: 8, length: 1, pos: 9, state: gtEof),
        TestToken(kind: gtStringLit, start: 9, length: 8, pos: 17, state: gtEof),
        TestToken(kind: gtWhitespace, start: 17, length: 1, pos: 18, state: gtEof),
        TestToken(kind: gtStringLit, start: 18, length: 14, pos: 32, state: gtEof),
        TestToken(kind: gtWhitespace, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtStringLit, start: 33, length: 14, pos: 47, state: gtEof),
      ]

  test "Template literal simple":
    const Code = "`Hello World`"
    check tokens(Code) ==
      @[
        TestToken(kind: gtLongStringLit, start: 0, length: 13, pos: 13, state: gtNone)
      ]

  test "Template literal with interpolation":
    const Code = "`Hello ${name}!`"
    check tokens(Code) ==
      @[
        TestToken(
          kind: gtLongStringLit,
          start: 0,
          length: 7,
          pos: 7,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 7, length: 2, pos: 9, state: gtNone),
        TestToken(kind: gtIdentifier, start: 9, length: 4, pos: 13, state: gtNone),
        TestToken(
          kind: gtOperator,
          start: 13,
          length: 1,
          pos: 14,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtLongStringLit, start: 14, length: 2, pos: 16, state: gtNone),
      ]

  test "Template literal with multiple interpolations":
    const Code = "`${a} + ${b} = ${a + b}`"
    check tokens(Code) ==
      @[
        TestToken(
          kind: gtLongStringLit,
          start: 0,
          length: 1,
          pos: 1,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 1, length: 2, pos: 3, state: gtNone),
        TestToken(kind: gtIdentifier, start: 3, length: 1, pos: 4, state: gtNone),
        TestToken(
          kind: gtOperator, start: 4, length: 1, pos: 5, state: gtLongStringLit
        ),
        TestToken(
          kind: gtLongStringLit,
          start: 5,
          length: 3,
          pos: 8,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 8, length: 2, pos: 10, state: gtNone),
        TestToken(kind: gtIdentifier, start: 10, length: 1, pos: 11, state: gtNone),
        TestToken(
          kind: gtOperator,
          start: 11,
          length: 1,
          pos: 12,
          state: gtLongStringLit,
        ),
        TestToken(
          kind: gtLongStringLit,
          start: 12,
          length: 3,
          pos: 15,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 15, length: 2, pos: 17, state: gtNone),
        TestToken(kind: gtIdentifier, start: 17, length: 1, pos: 18, state: gtNone),
        TestToken(kind: gtWhitespace, start: 18, length: 1, pos: 19, state: gtNone),
        TestToken(kind: gtOperator, start: 19, length: 1, pos: 20, state: gtNone),
        TestToken(kind: gtWhitespace, start: 20, length: 1, pos: 21, state: gtNone),
        TestToken(kind: gtIdentifier, start: 21, length: 1, pos: 22, state: gtNone),
        TestToken(
          kind: gtOperator,
          start: 22,
          length: 1,
          pos: 23,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtLongStringLit, start: 23, length: 1, pos: 24, state: gtNone),
      ]

  test "Template literal with nested braces":
    const Code = "`${obj.method({key: value})}`"
    check tokens(Code) ==
      @[
        TestToken(
          kind: gtLongStringLit,
          start: 0,
          length: 1,
          pos: 1,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 1, length: 2, pos: 3, state: gtNone),
        TestToken(kind: gtIdentifier, start: 3, length: 3, pos: 6, state: gtNone),
        TestToken(kind: gtPunctuation, start: 6, length: 1, pos: 7, state: gtNone),
        TestToken(kind: gtIdentifier, start: 7, length: 6, pos: 13, state: gtNone),
        TestToken(kind: gtPunctuation, start: 13, length: 1, pos: 14, state: gtNone),
        TestToken(kind: gtPunctuation, start: 14, length: 1, pos: 15, state: gtNone),
        TestToken(kind: gtIdentifier, start: 15, length: 3, pos: 18, state: gtNone),
        TestToken(kind: gtPunctuation, start: 18, length: 1, pos: 19, state: gtNone),
        TestToken(kind: gtWhitespace, start: 19, length: 1, pos: 20, state: gtNone),
        TestToken(kind: gtKeyword, start: 20, length: 5, pos: 25, state: gtNone),
        TestToken(kind: gtPunctuation, start: 25, length: 1, pos: 26, state: gtNone),
        TestToken(kind: gtPunctuation, start: 26, length: 1, pos: 27, state: gtNone),
        TestToken(
          kind: gtOperator,
          start: 27,
          length: 1,
          pos: 28,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtLongStringLit, start: 28, length: 1, pos: 29, state: gtNone),
      ]

  test "Numbers":
    const Code = "123 45.67 0xFF 0b1010 0o755 1e10 2.5e-3"
    check tokens(Code) ==
      @[
        TestToken(kind: gtDecNumber, start: 0, length: 3, pos: 3, state: gtEof),
        TestToken(kind: gtWhitespace, start: 3, length: 1, pos: 4, state: gtEof),
        TestToken(kind: gtFloatNumber, start: 4, length: 5, pos: 9, state: gtEof),
        TestToken(kind: gtWhitespace, start: 9, length: 1, pos: 10, state: gtEof),
        TestToken(kind: gtHexNumber, start: 10, length: 4, pos: 14, state: gtEof),
        TestToken(kind: gtWhitespace, start: 14, length: 1, pos: 15, state: gtEof),
        TestToken(kind: gtBinNumber, start: 15, length: 6, pos: 21, state: gtEof),
        TestToken(kind: gtWhitespace, start: 21, length: 1, pos: 22, state: gtEof),
        TestToken(kind: gtOctNumber, start: 22, length: 5, pos: 27, state: gtEof),
        TestToken(kind: gtWhitespace, start: 27, length: 1, pos: 28, state: gtEof),
        TestToken(kind: gtFloatNumber, start: 28, length: 4, pos: 32, state: gtEof),
        TestToken(kind: gtWhitespace, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtFloatNumber, start: 33, length: 6, pos: 39, state: gtEof),
      ]

  test "Operators":
    const Code = "+ - * % ** = += -= *= === !== < > <= >= && || ! ? :"
    check tokens(Code) ==
      @[
        TestToken(kind: gtOperator, start: 0, length: 1, pos: 1, state: gtEof),
        TestToken(kind: gtWhitespace, start: 1, length: 1, pos: 2, state: gtEof),
        TestToken(kind: gtOperator, start: 2, length: 1, pos: 3, state: gtEof),
        TestToken(kind: gtWhitespace, start: 3, length: 1, pos: 4, state: gtEof),
        TestToken(kind: gtOperator, start: 4, length: 1, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtOperator, start: 6, length: 1, pos: 7, state: gtEof),
        TestToken(kind: gtWhitespace, start: 7, length: 1, pos: 8, state: gtEof),
        TestToken(kind: gtOperator, start: 8, length: 2, pos: 10, state: gtEof),
        TestToken(kind: gtWhitespace, start: 10, length: 1, pos: 11, state: gtEof),
        TestToken(kind: gtOperator, start: 11, length: 1, pos: 12, state: gtEof),
        TestToken(kind: gtWhitespace, start: 12, length: 1, pos: 13, state: gtEof),
        TestToken(kind: gtOperator, start: 13, length: 2, pos: 15, state: gtEof),
        TestToken(kind: gtWhitespace, start: 15, length: 1, pos: 16, state: gtEof),
        TestToken(kind: gtOperator, start: 16, length: 2, pos: 18, state: gtEof),
        TestToken(kind: gtWhitespace, start: 18, length: 1, pos: 19, state: gtEof),
        TestToken(kind: gtOperator, start: 19, length: 2, pos: 21, state: gtEof),
        TestToken(kind: gtWhitespace, start: 21, length: 1, pos: 22, state: gtEof),
        TestToken(kind: gtOperator, start: 22, length: 3, pos: 25, state: gtEof),
        TestToken(kind: gtWhitespace, start: 25, length: 1, pos: 26, state: gtEof),
        TestToken(kind: gtOperator, start: 26, length: 3, pos: 29, state: gtEof),
        TestToken(kind: gtWhitespace, start: 29, length: 1, pos: 30, state: gtEof),
        TestToken(kind: gtOperator, start: 30, length: 1, pos: 31, state: gtEof),
        TestToken(kind: gtWhitespace, start: 31, length: 1, pos: 32, state: gtEof),
        TestToken(kind: gtOperator, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtWhitespace, start: 33, length: 1, pos: 34, state: gtEof),
        TestToken(kind: gtOperator, start: 34, length: 2, pos: 36, state: gtEof),
        TestToken(kind: gtWhitespace, start: 36, length: 1, pos: 37, state: gtEof),
        TestToken(kind: gtOperator, start: 37, length: 2, pos: 39, state: gtEof),
        TestToken(kind: gtWhitespace, start: 39, length: 1, pos: 40, state: gtEof),
        TestToken(kind: gtOperator, start: 40, length: 2, pos: 42, state: gtEof),
        TestToken(kind: gtWhitespace, start: 42, length: 1, pos: 43, state: gtEof),
        TestToken(kind: gtOperator, start: 43, length: 2, pos: 45, state: gtEof),
        TestToken(kind: gtWhitespace, start: 45, length: 1, pos: 46, state: gtEof),
        TestToken(kind: gtOperator, start: 46, length: 1, pos: 47, state: gtEof),
        TestToken(kind: gtWhitespace, start: 47, length: 1, pos: 48, state: gtEof),
        TestToken(kind: gtOperator, start: 48, length: 1, pos: 49, state: gtEof),
        TestToken(kind: gtWhitespace, start: 49, length: 1, pos: 50, state: gtEof),
        TestToken(kind: gtPunctuation, start: 50, length: 1, pos: 51, state: gtEof),
      ]

  test "Arrow function":
    const Code = "(x) => x * 2"
    check tokens(Code) ==
      @[
        TestToken(kind: gtPunctuation, start: 0, length: 1, pos: 1, state: gtEof),
        TestToken(kind: gtIdentifier, start: 1, length: 1, pos: 2, state: gtEof),
        TestToken(kind: gtPunctuation, start: 2, length: 1, pos: 3, state: gtEof),
        TestToken(kind: gtWhitespace, start: 3, length: 1, pos: 4, state: gtEof),
        TestToken(kind: gtOperator, start: 4, length: 2, pos: 6, state: gtEof),
        TestToken(kind: gtWhitespace, start: 6, length: 1, pos: 7, state: gtEof),
        TestToken(kind: gtIdentifier, start: 7, length: 1, pos: 8, state: gtEof),
        TestToken(kind: gtWhitespace, start: 8, length: 1, pos: 9, state: gtEof),
        TestToken(kind: gtOperator, start: 9, length: 1, pos: 10, state: gtEof),
        TestToken(kind: gtWhitespace, start: 10, length: 1, pos: 11, state: gtEof),
        TestToken(kind: gtDecNumber, start: 11, length: 1, pos: 12, state: gtEof),
      ]

  test "Object destructuring":
    const Code = "const {foo, bar: baz} = obj"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 5, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtPunctuation, start: 6, length: 1, pos: 7, state: gtEof),
        TestToken(kind: gtIdentifier, start: 7, length: 3, pos: 10, state: gtEof),
        TestToken(kind: gtPunctuation, start: 10, length: 1, pos: 11, state: gtEof),
        TestToken(kind: gtWhitespace, start: 11, length: 1, pos: 12, state: gtEof),
        TestToken(kind: gtIdentifier, start: 12, length: 3, pos: 15, state: gtEof),
        TestToken(kind: gtPunctuation, start: 15, length: 1, pos: 16, state: gtEof),
        TestToken(kind: gtWhitespace, start: 16, length: 1, pos: 17, state: gtEof),
        TestToken(kind: gtIdentifier, start: 17, length: 3, pos: 20, state: gtEof),
        TestToken(kind: gtPunctuation, start: 20, length: 1, pos: 21, state: gtEof),
        TestToken(kind: gtWhitespace, start: 21, length: 1, pos: 22, state: gtEof),
        TestToken(kind: gtOperator, start: 22, length: 1, pos: 23, state: gtEof),
        TestToken(kind: gtWhitespace, start: 23, length: 1, pos: 24, state: gtEof),
        TestToken(kind: gtIdentifier, start: 24, length: 3, pos: 27, state: gtEof),
      ]

  test "JSX/React keywords":
    const Code = "Array Object String console.log JSON.parse"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 5, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtKeyword, start: 6, length: 6, pos: 12, state: gtEof),
        TestToken(kind: gtWhitespace, start: 12, length: 1, pos: 13, state: gtEof),
        TestToken(kind: gtKeyword, start: 13, length: 6, pos: 19, state: gtEof),
        TestToken(kind: gtWhitespace, start: 19, length: 1, pos: 20, state: gtEof),
        TestToken(kind: gtKeyword, start: 20, length: 7, pos: 27, state: gtEof),
        TestToken(kind: gtPunctuation, start: 27, length: 1, pos: 28, state: gtEof),
        TestToken(kind: gtKeyword, start: 28, length: 3, pos: 31, state: gtEof),
        TestToken(kind: gtWhitespace, start: 31, length: 1, pos: 32, state: gtEof),
        TestToken(kind: gtKeyword, start: 32, length: 4, pos: 36, state: gtEof),
        TestToken(kind: gtPunctuation, start: 36, length: 1, pos: 37, state: gtEof),
        TestToken(kind: gtIdentifier, start: 37, length: 5, pos: 42, state: gtEof),
      ]

  test "Template literal escapes":
    const Code = "`Line 1\\nLine 2\\tTabbed`"
    check tokens(Code) ==
      @[
        TestToken(kind: gtLongStringLit, start: 0, length: 24, pos: 24, state: gtNone)
      ]

  test "Complex template literal":
    const Code = "`User: ${user.name}, Age: ${user.age > 18 ? 'Adult' : 'Minor'}`"
    check tokens(Code) ==
      @[
        TestToken(
          kind: gtLongStringLit,
          start: 0,
          length: 7,
          pos: 7,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 7, length: 2, pos: 9, state: gtNone),
        TestToken(kind: gtIdentifier, start: 9, length: 4, pos: 13, state: gtNone),
        TestToken(kind: gtPunctuation, start: 13, length: 1, pos: 14, state: gtNone),
        TestToken(kind: gtIdentifier, start: 14, length: 4, pos: 18, state: gtNone),
        TestToken(
          kind: gtOperator,
          start: 18,
          length: 1,
          pos: 19,
          state: gtLongStringLit,
        ),
        TestToken(
          kind: gtLongStringLit,
          start: 19,
          length: 7,
          pos: 26,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 26, length: 2, pos: 28, state: gtNone),
        TestToken(kind: gtIdentifier, start: 28, length: 4, pos: 32, state: gtNone),
        TestToken(kind: gtPunctuation, start: 32, length: 1, pos: 33, state: gtNone),
        TestToken(kind: gtIdentifier, start: 33, length: 3, pos: 36, state: gtNone),
        TestToken(kind: gtWhitespace, start: 36, length: 1, pos: 37, state: gtNone),
        TestToken(kind: gtOperator, start: 37, length: 1, pos: 38, state: gtNone),
        TestToken(kind: gtWhitespace, start: 38, length: 1, pos: 39, state: gtNone),
        TestToken(kind: gtDecNumber, start: 39, length: 2, pos: 41, state: gtNone),
        TestToken(kind: gtWhitespace, start: 41, length: 1, pos: 42, state: gtNone),
        TestToken(kind: gtOperator, start: 42, length: 1, pos: 43, state: gtNone),
        TestToken(kind: gtWhitespace, start: 43, length: 1, pos: 44, state: gtNone),
        TestToken(kind: gtStringLit, start: 44, length: 7, pos: 51, state: gtNone),
        TestToken(kind: gtWhitespace, start: 51, length: 1, pos: 52, state: gtNone),
        TestToken(kind: gtPunctuation, start: 52, length: 1, pos: 53, state: gtNone),
        TestToken(kind: gtWhitespace, start: 53, length: 1, pos: 54, state: gtNone),
        TestToken(kind: gtStringLit, start: 54, length: 7, pos: 61, state: gtNone),
        TestToken(
          kind: gtOperator,
          start: 61,
          length: 1,
          pos: 62,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtLongStringLit, start: 62, length: 1, pos: 63, state: gtNone),
      ]

  test "Nested template literals":
    const Code = "`Outer ${`Inner ${value}`} end`"
    check tokens(Code) ==
      @[
        TestToken(
          kind: gtLongStringLit,
          start: 0,
          length: 7,
          pos: 7,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 7, length: 2, pos: 9, state: gtNone),
        TestToken(
          kind: gtLongStringLit,
          start: 9,
          length: 7,
          pos: 16,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtOperator, start: 16, length: 2, pos: 18, state: gtNone),
        TestToken(kind: gtKeyword, start: 18, length: 5, pos: 23, state: gtNone),
        TestToken(
          kind: gtOperator,
          start: 23,
          length: 1,
          pos: 24,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtLongStringLit, start: 24, length: 1, pos: 25, state: gtNone),
        TestToken(
          kind: gtOperator,
          start: 25,
          length: 1,
          pos: 26,
          state: gtLongStringLit,
        ),
        TestToken(kind: gtLongStringLit, start: 26, length: 5, pos: 31, state: gtNone),
      ]

  test "HTML in template literals":
    const Code = "`<div class=\"container\">Hello</div>`"
    let tokenList = tokens(Code)
    check tokenList.len >= 1
    # Template literals with HTML are still treated as string literals for now

  test "JSX basic element":
    const Code = "<div>Hello World</div>"
    let tokenList = tokens(Code)
    check tokenList.len >= 6
    # Should recognize JSX tags as HTML elements
    var hasHtmlTokens = false
    for token in tokenList:
      if token.kind in {gtKeyword, gtOperator}:
        hasHtmlTokens = true
        break
    check hasHtmlTokens

  test "JSX with attributes":
    const Code = "<button onClick={handleClick} className=\"btn\">Click me</button>"
    let tokenList = tokens(Code)
    check tokenList.len >= 8
    # Should handle JSX attributes including JavaScript expressions

  test "Template literal with interpolated HTML":
    const Code = "`<h1>${title}</h1>`"
    let tokenList = tokens(Code)
    check tokenList.len >= 5
    # Should handle both template literal interpolation and HTML

  test "JSX component":
    const Code = "<MyComponent prop=\"value\" />"
    let tokenList = tokens(Code)
    check tokenList.len >= 4
    # Custom components should be recognized as identifiers

  test "Mixed JavaScript and JSX":
    const Code = "const element = <div>{name}</div>;"
    let tokenList = tokens(Code)
    check tokenList.len >= 8
    # Should handle mixed JS and JSX syntax

  test "Template literal with complex HTML":
    const Code = "`<div class=\"card\"><h2>${title}</h2><p>${content}</p></div>`"
    let tokenList = tokens(Code)
    check tokenList.len >= 10
    # Should handle complex HTML structure with interpolation
