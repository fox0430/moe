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
import ../src/moepkg/syntax/syntaxhtml

suite "syntaxhtml - htmlKeywords constant":
  test "htmlKeywords contains common tags":
    check "div" in htmlKeywords
    check "span" in htmlKeywords
    check "p" in htmlKeywords
    check "a" in htmlKeywords
    check "img" in htmlKeywords
    check "input" in htmlKeywords
    check "button" in htmlKeywords
    check "form" in htmlKeywords

  test "htmlKeywords contains heading tags":
    check "h1" in htmlKeywords
    check "h2" in htmlKeywords
    check "h3" in htmlKeywords
    check "h4" in htmlKeywords
    check "h5" in htmlKeywords
    check "h6" in htmlKeywords

  test "htmlKeywords contains structural tags":
    check "html" in htmlKeywords
    check "head" in htmlKeywords
    check "body" in htmlKeywords
    check "header" in htmlKeywords
    check "footer" in htmlKeywords
    check "main" in htmlKeywords
    check "nav" in htmlKeywords
    check "section" in htmlKeywords
    check "article" in htmlKeywords
    check "aside" in htmlKeywords

  test "htmlKeywords contains list tags":
    check "ul" in htmlKeywords
    check "ol" in htmlKeywords
    check "li" in htmlKeywords

  test "htmlKeywords contains table tags":
    check "table" in htmlKeywords
    check "thead" in htmlKeywords
    check "tbody" in htmlKeywords
    check "tfoot" in htmlKeywords
    check "tr" in htmlKeywords
    check "th" in htmlKeywords
    check "td" in htmlKeywords

  test "htmlKeywords contains media tags":
    check "video" in htmlKeywords
    check "audio" in htmlKeywords
    check "source" in htmlKeywords
    check "picture" in htmlKeywords
    check "canvas" in htmlKeywords

  test "htmlKeywords contains meta tags":
    check "meta" in htmlKeywords
    check "link" in htmlKeywords
    check "title" in htmlKeywords
    check "script" in htmlKeywords
    check "style" in htmlKeywords

suite "syntaxhtml - htmlNextToken tag start":
  test "opening tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div>")
    g.htmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "closing tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("</div>")
    g.htmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "self-closing tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<br/>")
    g.htmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "doctype tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!DOCTYPE html>")
    g.htmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "less than not followed by tag is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("< 5")
    g.htmlNextToken()
    check g.kind == gtOperator

  test "less than followed by number is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<5")
    g.htmlNextToken()
    check g.kind == gtOperator

suite "syntaxhtml - htmlNextToken tag end":
  test "closing angle bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.htmlNextToken()
    check g.kind == gtTagEnd
    check g.length == 1

  test "self-closing tag end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/>")
    g.htmlNextToken()
    check g.kind == gtTagEnd
    check g.length == 2

suite "syntaxhtml - htmlNextToken tag names":
  test "known tag name is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("div")
    g.htmlNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "unknown tag name is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("mycomponent")
    g.htmlNextToken()
    check g.kind == gtIdentifier

  test "attribute name is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class")
    g.htmlNextToken()
    check g.kind == gtIdentifier

suite "syntaxhtml - htmlNextToken attributes":
  test "attribute value in double quotes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"value\"")
    g.htmlNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "attribute value in single quotes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'value'")
    g.htmlNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "equals sign is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.htmlNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntaxhtml - htmlNextToken comments":
  test "HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- comment -->")
    g.htmlNextToken()
    check g.kind == gtLongComment
    check g.length == 16

  test "multiline HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- line1\nline2 -->")
    g.htmlNextToken()
    check g.kind == gtLongComment

  test "unterminated HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- unterminated")
    g.htmlNextToken()
    check g.kind == gtLongComment
    check g.state == gtLongComment

  test "comment continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- start")
    g.htmlNextToken()
    check g.kind == gtLongComment
    check g.state == gtLongComment
    check g.inComment == true

suite "syntaxhtml - htmlNextToken entities":
  test "named entity":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&nbsp;")
    g.htmlNextToken()
    check g.kind == gtOperator
    check g.length == 6

  test "numeric entity":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&#65;")
    g.htmlNextToken()
    check g.kind == gtOperator
    check g.length == 5

  test "hex entity":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&#x41;")
    g.htmlNextToken()
    check g.kind == gtOperator
    check g.length == 6

suite "syntaxhtml - htmlNextToken whitespace":
  test "space between tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("> <")
    g.htmlNextToken() # >
    g.htmlNextToken() # space
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces between tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">    <")
    g.htmlNextToken() # >
    g.htmlNextToken() # spaces
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab between tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">\t<")
    g.htmlNextToken() # >
    g.htmlNextToken() # tab
    check g.kind == gtWhitespace

  test "newline between tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">\n<")
    g.htmlNextToken() # >
    g.htmlNextToken() # newline
    check g.kind == gtWhitespace

suite "syntaxhtml - htmlNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.htmlNextToken()
    check g.kind == gtEof

  test "EOF after token":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.htmlNextToken()
    g.htmlNextToken()
    check g.kind == gtEof

suite "syntaxhtml - htmlNextToken complete HTML":
  test "simple tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div>content</div>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.htmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens
    check gtKeyword in tokens # div
    check gtTagEnd in tokens

  test "tag with attribute":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div class=\"test\">")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.htmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens
    check gtKeyword in tokens # div
    check gtIdentifier in tokens # class
    check gtOperator in tokens # =
    check gtStringLit in tokens # "test"
    check gtTagEnd in tokens

  test "self-closing tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<br/>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.htmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens
    check gtKeyword in tokens # br
    check gtTagEnd in tokens

  test "nested tags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div><span>text</span></div>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.htmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens
    check gtKeyword in tokens # div, span
    check gtTagEnd in tokens

  test "HTML with comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div><!-- comment --></div>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.htmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLongComment in tokens
