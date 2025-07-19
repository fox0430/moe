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

proc tokens(code: string): seq[GT] =
  var token = GeneralTokenizer()
  token.initGeneralTokenizer(code)

  while true:
    token.getNextToken(SourceLanguage.langHtml)
    if token.kind == gtEof:
      break
    else:
      result.add token
      # Clear token.buf and reset state fields for comparison
      result[^1].buf = ""
      result[^1].templateLiteralDepth = 0
      result[^1].braceDepthStack = @[]
      result[^1].inJsxMode = false
      result[^1].jsxTagDepth = 0
      result[^1].inComment = false
      result[^1].commentDepth = 0
      result[^1].inScript = false
      result[^1].inStyle = false
      result[^1].astroInFrontmatter = false
      result[^1].astroFirstLine = true

suite "syntax: HTML":
  test "Basic HTML tag":
    const Code = "<div>"
    let tokenList = tokens(Code)
    check tokenList.len == 3
    check tokenList[0].kind == gtOperator # <
    check tokenList[1].kind == gtKeyword # div (should be recognized as keyword)
    check tokenList[2].kind == gtOperator # >

  test "HTML keywords":
    const Code = "<html>"
    let tokenList = tokens(Code)
    check tokenList.len == 3
    check tokenList[0].kind == gtOperator # <
    check tokenList[1].kind == gtKeyword # html (should be recognized as keyword)
    check tokenList[2].kind == gtOperator # >

  test "HTML comment":
    const Code = "<!-- comment -->"
    let tokenList = tokens(Code)
    check tokenList.len == 1
    check tokenList[0].kind == gtLongComment

  test "HTML attributes with quotes":
    const Code = "<div class=\"container\" id='main'>"
    let tokenList = tokens(Code)
    check tokenList.len >= 8
    check tokenList[0].kind == gtOperator # <
    check tokenList[1].kind == gtKeyword # div
    check tokenList[2].kind == gtWhitespace # space
    check tokenList[3].kind == gtIdentifier # class
    check tokenList[4].kind == gtOperator # =
    check tokenList[5].kind == gtStringLit # "container"

  test "Self-closing tag":
    const Code = "<img src=\"test.jpg\" />"
    let tokenList = tokens(Code)
    check tokenList.len >= 6
    check tokenList[0].kind == gtOperator # <
    check tokenList[1].kind == gtKeyword # img
    # Should have attributes and self-closing />

  test "DOCTYPE declaration":
    const Code = "<!DOCTYPE html>"
    let tokenList = tokens(Code)
    check tokenList.len >= 4
    check tokenList[0].kind == gtOperator # <
    # DOCTYPE should be handled appropriately

  test "Nested HTML tags":
    const Code = "<div><p>Hello <span>world</span></p></div>"
    let tokenList = tokens(Code)
    check tokenList.len >= 10
    # Check that opening and closing tags are properly tokenized
    var operatorCount = 0
    var keywordCount = 0
    for token in tokenList:
      if token.kind == gtOperator:
        inc operatorCount
      elif token.kind == gtKeyword:
        inc keywordCount
    check operatorCount >= 8 # < > < > < </ > </ >
    check keywordCount >= 4 # div p span p div

  test "HTML entities":
    const Code = "&lt;div&gt; &amp; &nbsp;"
    let tokenList = tokens(Code)
    check tokenList.len >= 7
    # HTML entities should be recognized as operators

  test "HTML with text content":
    const Code = "<p>This is text content</p>"
    let tokenList = tokens(Code)
    check tokenList.len >= 5
    check tokenList[0].kind == gtOperator # <
    check tokenList[1].kind == gtKeyword # p
    check tokenList[2].kind == gtOperator # >
    # Text content should be present
    # Closing tag should be present

  test "Multi-line HTML":
    const Code =
      """<div>
  <p>
    Hello World
  </p>
</div>"""
    let tokenList = tokens(Code)
    check tokenList.len >= 8
    # Should handle whitespace and newlines properly
    var whitespaceCount = 0
    for token in tokenList:
      if token.kind == gtWhitespace:
        inc whitespaceCount
    check whitespaceCount >= 3

  test "HTML with multiple attributes":
    const Code =
      "<input type=\"text\" name=\"username\" placeholder=\"Enter name\" required disabled>"
    let tokenList = tokens(Code)
    check tokenList.len >= 12
    check tokenList[0].kind == gtOperator # <
    check tokenList[1].kind == gtKeyword # input
    # Should have multiple attribute-value pairs

  test "HTML comment multi-line":
    const Code =
      """<!-- This is a
    multi-line
    comment -->"""
    let tokenList = tokens(Code)
    check tokenList.len == 1
    check tokenList[0].kind == gtLongComment

  test "Unknown custom tags":
    const Code = "<custom-element data-value=\"test\">content</custom-element>"
    let tokenList = tokens(Code)
    check tokenList.len >= 6
    check tokenList[0].kind == gtOperator # <
    check tokenList[1].kind == gtIdentifier # custom-element (not a standard HTML tag)

  test "Empty tags":
    const Code = "<div></div>"
    let tokenList = tokens(Code)
    check tokenList.len == 7
    check tokenList[0].kind == gtOperator # <
    check tokenList[1].kind == gtKeyword # div
    check tokenList[2].kind == gtOperator # >
    check tokenList[3].kind == gtOperator # <
    check tokenList[4].kind == gtOperator # /
    check tokenList[5].kind == gtKeyword # div
    check tokenList[6].kind == gtOperator # >

  test "HTML5 semantic elements":
    const Code = "<article><header><nav><main><section><aside><footer>"
    let tokenList = tokens(Code)
    check tokenList.len >= 14
    # All HTML5 semantic elements should be recognized as keywords
    var keywordCount = 0
    for token in tokenList:
      if token.kind == gtKeyword:
        inc keywordCount
    check keywordCount == 7 # article, header, nav, main, section, aside, footer

  test "Mixed quotes in attributes":
    const Code = """<div title="Hello 'World'" data-info='Test "value"'>"""
    let tokenList = tokens(Code)
    check tokenList.len >= 8
    # Should handle nested quotes properly in string literals
