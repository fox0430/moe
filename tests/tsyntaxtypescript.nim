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

import std/[unittest, strutils]

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
    token.getNextToken(SourceLanguage.langTypeScript)
    if token.kind == gtEof:
      break
    else:
      result.add TestToken(
        kind: token.kind,
        start: token.start,
        length: token.length,
        pos: token.pos,
        state: token.state,
      )

# Keep the old function for backwards compatibility
proc tokens(code: string): seq[TestToken] =
  testTokens(code)

suite "syntax: TypeScript":
  test "Basic TypeScript":
    const Code = "let x: number = 5;"
    let result = tokens(Code)
    # Debug: print actual tokens
    # for i, token in result:
    #   echo "Token ", i, ": ", token
    check result ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 3, pos: 3, state: gtEof),
        TestToken(kind: gtWhitespace, start: 3, length: 1, pos: 4, state: gtEof),
        TestToken(kind: gtKey, start: 4, length: 1, pos: 5, state: gtEof),
        TestToken(kind: gtPunctuation, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtWhitespace, start: 6, length: 1, pos: 7, state: gtEof),
        TestToken(kind: gtKeyword, start: 7, length: 6, pos: 13, state: gtEof),
        TestToken(kind: gtWhitespace, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtOperator, start: 14, length: 1, pos: 15, state: gtEof),
        TestToken(kind: gtWhitespace, start: 15, length: 1, pos: 16, state: gtEof),
        TestToken(kind: gtDecNumber, start: 16, length: 1, pos: 17, state: gtEof),
        TestToken(kind: gtPunctuation, start: 17, length: 1, pos: 18, state: gtEof),
      ]

  test "TypeScript Keywords":
    const Code = "type interface namespace declare readonly keyof"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 4, pos: 4, state: gtEof),
        TestToken(kind: gtWhitespace, start: 4, length: 1, pos: 5, state: gtEof),
        TestToken(kind: gtKeyword, start: 5, length: 9, pos: 14, state: gtEof),
        TestToken(kind: gtWhitespace, start: 14, length: 1, pos: 15, state: gtEof),
        TestToken(kind: gtKeyword, start: 15, length: 9, pos: 24, state: gtEof),
        TestToken(kind: gtWhitespace, start: 24, length: 1, pos: 25, state: gtEof),
        TestToken(kind: gtKeyword, start: 25, length: 7, pos: 32, state: gtEof),
        TestToken(kind: gtWhitespace, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtKeyword, start: 33, length: 8, pos: 41, state: gtEof),
        TestToken(kind: gtWhitespace, start: 41, length: 1, pos: 42, state: gtEof),
        TestToken(kind: gtKeyword, start: 42, length: 5, pos: 47, state: gtEof),
      ]

  test "TypeScript type keywords":
    const Code = "any unknown never string number bigint boolean symbol undefined"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 3, pos: 3, state: gtEof),
        TestToken(kind: gtWhitespace, start: 3, length: 1, pos: 4, state: gtEof),
        TestToken(kind: gtKeyword, start: 4, length: 7, pos: 11, state: gtEof),
        TestToken(kind: gtWhitespace, start: 11, length: 1, pos: 12, state: gtEof),
        TestToken(kind: gtKeyword, start: 12, length: 5, pos: 17, state: gtEof),
        TestToken(kind: gtWhitespace, start: 17, length: 1, pos: 18, state: gtEof),
        TestToken(kind: gtKeyword, start: 18, length: 6, pos: 24, state: gtEof),
        TestToken(kind: gtWhitespace, start: 24, length: 1, pos: 25, state: gtEof),
        TestToken(kind: gtKeyword, start: 25, length: 6, pos: 31, state: gtEof),
        TestToken(kind: gtWhitespace, start: 31, length: 1, pos: 32, state: gtEof),
        TestToken(kind: gtKeyword, start: 32, length: 6, pos: 38, state: gtEof),
        TestToken(kind: gtWhitespace, start: 38, length: 1, pos: 39, state: gtEof),
        TestToken(kind: gtKeyword, start: 39, length: 7, pos: 46, state: gtEof),
        TestToken(kind: gtWhitespace, start: 46, length: 1, pos: 47, state: gtEof),
        TestToken(kind: gtKeyword, start: 47, length: 6, pos: 53, state: gtEof),
        TestToken(kind: gtWhitespace, start: 53, length: 1, pos: 54, state: gtEof),
        TestToken(kind: gtKeyword, start: 54, length: 9, pos: 63, state: gtEof),
      ]

  test "Interface declaration":
    const Code = "interface Person { name: string; age?: number; }"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 9, pos: 9, state: gtEof),
        TestToken(kind: gtWhitespace, start: 9, length: 1, pos: 10, state: gtEof),
        TestToken(kind: gtIdentifier, start: 10, length: 6, pos: 16, state: gtEof),
        TestToken(kind: gtWhitespace, start: 16, length: 1, pos: 17, state: gtEof),
        TestToken(kind: gtPunctuation, start: 17, length: 1, pos: 18, state: gtEof),
        TestToken(kind: gtWhitespace, start: 18, length: 1, pos: 19, state: gtEof),
        TestToken(kind: gtKey, start: 19, length: 4, pos: 23, state: gtEof),
        TestToken(kind: gtPunctuation, start: 23, length: 1, pos: 24, state: gtEof),
        TestToken(kind: gtWhitespace, start: 24, length: 1, pos: 25, state: gtEof),
        TestToken(kind: gtKeyword, start: 25, length: 6, pos: 31, state: gtEof),
        TestToken(kind: gtPunctuation, start: 31, length: 1, pos: 32, state: gtEof),
        TestToken(kind: gtWhitespace, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtIdentifier, start: 33, length: 3, pos: 36, state: gtEof),
        TestToken(kind: gtOperator, start: 36, length: 1, pos: 37, state: gtEof),
        TestToken(kind: gtPunctuation, start: 37, length: 1, pos: 38, state: gtEof),
        TestToken(kind: gtWhitespace, start: 38, length: 1, pos: 39, state: gtEof),
        TestToken(kind: gtKeyword, start: 39, length: 6, pos: 45, state: gtEof),
        TestToken(kind: gtPunctuation, start: 45, length: 1, pos: 46, state: gtEof),
        TestToken(kind: gtWhitespace, start: 46, length: 1, pos: 47, state: gtEof),
        TestToken(kind: gtPunctuation, start: 47, length: 1, pos: 48, state: gtEof),
      ]

  test "Type alias":
    const Code = "type Status = 'active' | 'inactive';"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 4, pos: 4, state: gtEof),
        TestToken(kind: gtWhitespace, start: 4, length: 1, pos: 5, state: gtEof),
        TestToken(kind: gtIdentifier, start: 5, length: 6, pos: 11, state: gtEof),
        TestToken(kind: gtWhitespace, start: 11, length: 1, pos: 12, state: gtEof),
        TestToken(kind: gtOperator, start: 12, length: 1, pos: 13, state: gtEof),
        TestToken(kind: gtWhitespace, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtStringLit, start: 14, length: 8, pos: 22, state: gtEof),
        TestToken(kind: gtWhitespace, start: 22, length: 1, pos: 23, state: gtEof),
        TestToken(kind: gtOperator, start: 23, length: 1, pos: 24, state: gtEof),
        TestToken(kind: gtWhitespace, start: 24, length: 1, pos: 25, state: gtEof),
        TestToken(kind: gtStringLit, start: 25, length: 10, pos: 35, state: gtEof),
        TestToken(kind: gtPunctuation, start: 35, length: 1, pos: 36, state: gtEof),
      ]

  test "Generic type":
    const Code = "function identity<T>(value: T): T { return value; }"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 8, pos: 8, state: gtEof),
        TestToken(kind: gtWhitespace, start: 8, length: 1, pos: 9, state: gtEof),
        TestToken(kind: gtIdentifier, start: 9, length: 8, pos: 17, state: gtEof),
        TestToken(kind: gtOperator, start: 17, length: 1, pos: 18, state: gtEof),
        TestToken(kind: gtIdentifier, start: 18, length: 1, pos: 19, state: gtEof),
        TestToken(kind: gtOperator, start: 19, length: 1, pos: 20, state: gtEof),
        TestToken(kind: gtPunctuation, start: 20, length: 1, pos: 21, state: gtEof),
        TestToken(kind: gtKeyword, start: 21, length: 5, pos: 26, state: gtEof),
        TestToken(kind: gtPunctuation, start: 26, length: 1, pos: 27, state: gtEof),
        TestToken(kind: gtWhitespace, start: 27, length: 1, pos: 28, state: gtEof),
        TestToken(kind: gtIdentifier, start: 28, length: 1, pos: 29, state: gtEof),
        TestToken(kind: gtPunctuation, start: 29, length: 1, pos: 30, state: gtEof),
        TestToken(kind: gtPunctuation, start: 30, length: 1, pos: 31, state: gtEof),
        TestToken(kind: gtWhitespace, start: 31, length: 1, pos: 32, state: gtEof),
        TestToken(kind: gtIdentifier, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtWhitespace, start: 33, length: 1, pos: 34, state: gtEof),
        TestToken(kind: gtPunctuation, start: 34, length: 1, pos: 35, state: gtEof),
        TestToken(kind: gtWhitespace, start: 35, length: 1, pos: 36, state: gtEof),
        TestToken(kind: gtKeyword, start: 36, length: 6, pos: 42, state: gtEof),
        TestToken(kind: gtWhitespace, start: 42, length: 1, pos: 43, state: gtEof),
        TestToken(kind: gtKeyword, start: 43, length: 5, pos: 48, state: gtEof),
        TestToken(kind: gtPunctuation, start: 48, length: 1, pos: 49, state: gtEof),
        TestToken(kind: gtWhitespace, start: 49, length: 1, pos: 50, state: gtEof),
        TestToken(kind: gtPunctuation, start: 50, length: 1, pos: 51, state: gtEof),
      ]

  test "BigInt literal":
    const Code = "const big = 123n; const bigHex = 0xFFn;"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 5, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtIdentifier, start: 6, length: 3, pos: 9, state: gtEof),
        TestToken(kind: gtWhitespace, start: 9, length: 1, pos: 10, state: gtEof),
        TestToken(kind: gtOperator, start: 10, length: 1, pos: 11, state: gtEof),
        TestToken(kind: gtWhitespace, start: 11, length: 1, pos: 12, state: gtEof),
        TestToken(kind: gtDecNumber, start: 12, length: 4, pos: 16, state: gtEof),
        TestToken(kind: gtPunctuation, start: 16, length: 1, pos: 17, state: gtEof),
        TestToken(kind: gtWhitespace, start: 17, length: 1, pos: 18, state: gtEof),
        TestToken(kind: gtKeyword, start: 18, length: 5, pos: 23, state: gtEof),
        TestToken(kind: gtWhitespace, start: 23, length: 1, pos: 24, state: gtEof),
        TestToken(kind: gtIdentifier, start: 24, length: 6, pos: 30, state: gtEof),
        TestToken(kind: gtWhitespace, start: 30, length: 1, pos: 31, state: gtEof),
        TestToken(kind: gtOperator, start: 31, length: 1, pos: 32, state: gtEof),
        TestToken(kind: gtWhitespace, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtHexNumber, start: 33, length: 5, pos: 38, state: gtEof),
        TestToken(kind: gtPunctuation, start: 38, length: 1, pos: 39, state: gtEof),
      ]

  test "Optional chaining":
    const Code = "const value = obj?.prop?.method();"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 5, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtKeyword, start: 6, length: 5, pos: 11, state: gtEof),
        TestToken(kind: gtWhitespace, start: 11, length: 1, pos: 12, state: gtEof),
        TestToken(kind: gtOperator, start: 12, length: 1, pos: 13, state: gtEof),
        TestToken(kind: gtWhitespace, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtIdentifier, start: 14, length: 3, pos: 17, state: gtEof),
        TestToken(kind: gtOperator, start: 17, length: 2, pos: 19, state: gtEof),
        TestToken(kind: gtIdentifier, start: 19, length: 4, pos: 23, state: gtEof),
        TestToken(kind: gtOperator, start: 23, length: 2, pos: 25, state: gtEof),
        TestToken(kind: gtIdentifier, start: 25, length: 6, pos: 31, state: gtEof),
        TestToken(kind: gtPunctuation, start: 31, length: 1, pos: 32, state: gtEof),
        TestToken(kind: gtPunctuation, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtPunctuation, start: 33, length: 1, pos: 34, state: gtEof),
      ]

  test "Nullish coalescing":
    const Code = "const result = value ?? defaultValue;"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 5, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtIdentifier, start: 6, length: 6, pos: 12, state: gtEof),
        TestToken(kind: gtWhitespace, start: 12, length: 1, pos: 13, state: gtEof),
        TestToken(kind: gtOperator, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtWhitespace, start: 14, length: 1, pos: 15, state: gtEof),
        TestToken(kind: gtKeyword, start: 15, length: 5, pos: 20, state: gtEof),
        TestToken(kind: gtWhitespace, start: 20, length: 1, pos: 21, state: gtEof),
        TestToken(kind: gtOperator, start: 21, length: 2, pos: 23, state: gtEof),
        TestToken(kind: gtWhitespace, start: 23, length: 1, pos: 24, state: gtEof),
        TestToken(kind: gtIdentifier, start: 24, length: 12, pos: 36, state: gtEof),
        TestToken(kind: gtPunctuation, start: 36, length: 1, pos: 37, state: gtEof),
      ]

  test "Type assertion":
    const Code = "const element = document.getElementById('app') as HTMLDivElement;"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 5, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtIdentifier, start: 6, length: 7, pos: 13, state: gtEof),
        TestToken(kind: gtWhitespace, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtOperator, start: 14, length: 1, pos: 15, state: gtEof),
        TestToken(kind: gtWhitespace, start: 15, length: 1, pos: 16, state: gtEof),
        TestToken(kind: gtKeyword, start: 16, length: 8, pos: 24, state: gtEof),
        TestToken(kind: gtPunctuation, start: 24, length: 1, pos: 25, state: gtEof),
        TestToken(kind: gtIdentifier, start: 25, length: 14, pos: 39, state: gtEof),
        TestToken(kind: gtPunctuation, start: 39, length: 1, pos: 40, state: gtEof),
        TestToken(kind: gtStringLit, start: 40, length: 5, pos: 45, state: gtEof),
        TestToken(kind: gtPunctuation, start: 45, length: 1, pos: 46, state: gtEof),
        TestToken(kind: gtWhitespace, start: 46, length: 1, pos: 47, state: gtEof),
        TestToken(kind: gtKeyword, start: 47, length: 2, pos: 49, state: gtEof),
        TestToken(kind: gtWhitespace, start: 49, length: 1, pos: 50, state: gtEof),
        TestToken(kind: gtIdentifier, start: 50, length: 14, pos: 64, state: gtEof),
        TestToken(kind: gtPunctuation, start: 64, length: 1, pos: 65, state: gtEof),
      ]

  test "Spread operator":
    const Code = "const newArr = [...arr1, ...arr2];"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 5, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtIdentifier, start: 6, length: 6, pos: 12, state: gtEof),
        TestToken(kind: gtWhitespace, start: 12, length: 1, pos: 13, state: gtEof),
        TestToken(kind: gtOperator, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtWhitespace, start: 14, length: 1, pos: 15, state: gtEof),
        TestToken(kind: gtPunctuation, start: 15, length: 1, pos: 16, state: gtEof),
        TestToken(kind: gtOperator, start: 16, length: 3, pos: 19, state: gtEof),
        TestToken(kind: gtIdentifier, start: 19, length: 4, pos: 23, state: gtEof),
        TestToken(kind: gtPunctuation, start: 23, length: 1, pos: 24, state: gtEof),
        TestToken(kind: gtWhitespace, start: 24, length: 1, pos: 25, state: gtEof),
        TestToken(kind: gtOperator, start: 25, length: 3, pos: 28, state: gtEof),
        TestToken(kind: gtIdentifier, start: 28, length: 4, pos: 32, state: gtEof),
        TestToken(kind: gtPunctuation, start: 32, length: 1, pos: 33, state: gtEof),
        TestToken(kind: gtPunctuation, start: 33, length: 1, pos: 34, state: gtEof),
      ]

  test "Non-null assertion":
    const Code = "const value = obj!.prop;"
    check tokens(Code) ==
      @[
        TestToken(kind: gtKeyword, start: 0, length: 5, pos: 5, state: gtEof),
        TestToken(kind: gtWhitespace, start: 5, length: 1, pos: 6, state: gtEof),
        TestToken(kind: gtKeyword, start: 6, length: 5, pos: 11, state: gtEof),
        TestToken(kind: gtWhitespace, start: 11, length: 1, pos: 12, state: gtEof),
        TestToken(kind: gtOperator, start: 12, length: 1, pos: 13, state: gtEof),
        TestToken(kind: gtWhitespace, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtIdentifier, start: 14, length: 3, pos: 17, state: gtEof),
        TestToken(kind: gtOperator, start: 17, length: 1, pos: 18, state: gtEof),
        TestToken(kind: gtPunctuation, start: 18, length: 1, pos: 19, state: gtEof),
        TestToken(kind: gtIdentifier, start: 19, length: 4, pos: 23, state: gtEof),
        TestToken(kind: gtPunctuation, start: 23, length: 1, pos: 24, state: gtEof),
      ]

  test "TSX basic element":
    const Code = "<div className=\"test\">Hello World</div>"
    let tokenList = tokens(Code)
    check tokenList.len >= 6
    # Should recognize TSX tags as HTML elements
    var hasHtmlTokens = false
    for token in tokenList:
      if token.kind in {gtKeyword, gtOperator}:
        hasHtmlTokens = true
        break
    check hasHtmlTokens

  test "TSX with TypeScript expression":
    const Code = "<Component<Props> onClick={(e: MouseEvent) => handleClick(e)} />"
    let tokenList = tokens(Code)
    check tokenList.len >= 8
    # Should handle TSX with generic types and typed event handlers

  test "Template literal with TypeScript":
    const Code = "`Hello ${name as string}!`"
    check tokens(Code) ==
      @[
        TestToken(
          kind: gtLongStringLit, start: 0, length: 7, pos: 7, state: gtLongStringLit
        ),
        TestToken(kind: gtOperator, start: 7, length: 2, pos: 9, state: gtNone),
        TestToken(kind: gtIdentifier, start: 9, length: 4, pos: 13, state: gtNone),
        TestToken(kind: gtWhitespace, start: 13, length: 1, pos: 14, state: gtNone),
        TestToken(kind: gtKeyword, start: 14, length: 2, pos: 16, state: gtNone),
        TestToken(kind: gtWhitespace, start: 16, length: 1, pos: 17, state: gtNone),
        TestToken(kind: gtKeyword, start: 17, length: 6, pos: 23, state: gtNone),
        TestToken(
          kind: gtOperator, start: 23, length: 1, pos: 24, state: gtLongStringLit
        ),
        TestToken(kind: gtLongStringLit, start: 24, length: 2, pos: 26, state: gtNone),
      ]

  test "Satisfies operator":
    const Code = "const config = { port: 3000 } satisfies Config;"
    let tokenList = tokens(Code)
    # Check that 'satisfies' is recognized as a keyword
    var satisfiesFound = false
    for token in tokenList:
      if token.kind == gtKeyword:
        let tokenText = Code[token.start ..< token.start + token.length]
        if tokenText == "satisfies":
          satisfiesFound = true
          break
    check satisfiesFound

  test "Override modifier":
    const Code = "class Child extends Parent { override method() {} }"
    let tokenList = tokens(Code)
    # Check that 'override' is recognized as a keyword
    var overrideFound = false
    for token in tokenList:
      if token.kind == gtKeyword:
        let tokenText = Code[token.start ..< token.start + token.length]
        if tokenText == "override":
          overrideFound = true
          break
    check overrideFound

  test "Object literal key highlighting":
    const Code = """const user: User = {"name": "Bob", "age": 30, "active": true};"""

    let tokenList = tokens(Code)
    var nameKeyFound = false
    var ageKeyFound = false
    var activeKeyFound = false
    var bobValueFound = false

    for token in tokenList:
      let tokenText = Code[token.start ..< token.start + token.length]
      if token.kind == gtKey:
        if tokenText == "\"name\"":
          nameKeyFound = true
        elif tokenText == "\"age\"":
          ageKeyFound = true
        elif tokenText == "\"active\"":
          activeKeyFound = true
      elif token.kind == gtStringLit:
        if tokenText == "\"Bob\"":
          bobValueFound = true

    check nameKeyFound
    check ageKeyFound
    check activeKeyFound
    check bobValueFound

  test "Type annotation with object keys":
    const Code = """type Config = {"apiUrl": string; "timeout": number};"""

    let tokenList = tokens(Code)
    var apiUrlKeyFound = false
    var timeoutKeyFound = false

    for token in tokenList:
      let tokenText = Code[token.start ..< token.start + token.length]
      if token.kind == gtKey:
        if tokenText == "\"apiUrl\"":
          apiUrlKeyFound = true
        elif tokenText == "\"timeout\"":
          timeoutKeyFound = true

    check apiUrlKeyFound
    check timeoutKeyFound

  test "Interface with quoted property names":
    const Code =
      """interface API { "get-user": () => User; "post-data": (data: any) => void; }"""

    let tokenList = tokens(Code)
    var getUserKeyFound = false
    var postDataKeyFound = false

    for token in tokenList:
      let tokenText = Code[token.start ..< token.start + token.length]
      if token.kind == gtKey:
        if tokenText == "\"get-user\"":
          getUserKeyFound = true
        elif tokenText == "\"post-data\"":
          postDataKeyFound = true

    check getUserKeyFound
    check postDataKeyFound

  test "Extended key highlighting - all quote types":
    const Code = """const obj = {name: "Bob", "age": 30, 'active': true};"""
    
    let tokenList = tokens(Code)
    var unquotedKeyCount = 0
    var doubleQuotedKeyCount = 0
    var singleQuotedKeyCount = 0
    
    for token in tokenList:
      let tokenText = Code[token.start ..<  token.start + token.length]
      if token.kind == gtKey:
        if tokenText.startsWith("\""):
          doubleQuotedKeyCount += 1
        elif tokenText.startsWith("'"):
          singleQuotedKeyCount += 1
        elif not (tokenText.startsWith("\"") or tokenText.startsWith("'")):
          unquotedKeyCount += 1
    
    check unquotedKeyCount == 1    # name
    check doubleQuotedKeyCount == 1  # "age" 
    check singleQuotedKeyCount == 1  # 'active'
