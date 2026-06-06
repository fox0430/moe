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

import ../src/moepkg/syntax/[tokenizer, syntax_xml]

suite "syntax_xml - xmlNextToken tag start":
  test "opening tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<note>")
    g.xmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "closing tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("</note>")
    g.xmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "self-closing tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<empty/>")
    g.xmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "doctype tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!DOCTYPE note SYSTEM \"note.dtd\">")
    g.xmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "xml declaration tag start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<?xml version=\"1.0\"?>")
    g.xmlNextToken()
    check g.kind == gtTagStart
    check g.length == 1

  test "less than not followed by tag is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("< 5")
    g.xmlNextToken()
    check g.kind == gtOperator

  test "less than followed by number is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<5")
    g.xmlNextToken()
    check g.kind == gtOperator

suite "syntax_xml - xmlNextToken tag end":
  test "closing angle bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.xmlNextToken()
    check g.kind == gtTagEnd
    check g.length == 1

  test "self-closing tag end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/>")
    g.xmlNextToken()
    check g.kind == gtTagEnd
    check g.length == 2

  test "processing instruction end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?>")
    g.xmlNextToken()
    check g.kind == gtTagEnd
    check g.length == 2

suite "syntax_xml - xmlNextToken names":
  test "element name after < is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<note>")
    g.xmlNextToken() # <
    g.xmlNextToken() # note
    check g.kind == gtKeyword
    check g.length == 4

  test "element name after </ is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("</note>")
    g.xmlNextToken() # <
    g.xmlNextToken() # /
    g.xmlNextToken() # note
    check g.kind == gtKeyword
    check g.length == 4

  test "processing instruction name after <? is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<?xml version=\"1.0\"?>")
    g.xmlNextToken() # <
    g.xmlNextToken() # ?
    g.xmlNextToken() # xml
    check g.kind == gtKeyword
    check g.length == 3

  test "namespaced element name is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<x:item>")
    g.xmlNextToken() # <
    g.xmlNextToken() # x:item
    check g.kind == gtKeyword
    check g.length == 6

  test "attribute name is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<note priority=\"high\">")
    g.xmlNextToken() # <
    g.xmlNextToken() # note
    g.xmlNextToken() # whitespace
    g.xmlNextToken() # priority
    check g.kind == gtIdentifier
    check g.length == 8

  test "text content word is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("text")
    g.xmlNextToken()
    check g.kind == gtIdentifier

suite "syntax_xml - xmlNextToken declaration keywords":
  test "DOCTYPE after <! is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!DOCTYPE note>")
    g.xmlNextToken() # <
    g.xmlNextToken() # !
    g.xmlNextToken() # DOCTYPE
    check g.kind == gtKeyword
    check g.length == 7

  test "ELEMENT after <! is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!ELEMENT note (#PCDATA)>")
    g.xmlNextToken() # <
    g.xmlNextToken() # !
    g.xmlNextToken() # ELEMENT
    check g.kind == gtKeyword

  test "SYSTEM is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("SYSTEM")
    g.xmlNextToken()
    check g.kind == gtKeyword

  test "PUBLIC is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("PUBLIC")
    g.xmlNextToken()
    check g.kind == gtKeyword

  test "REQUIRED in attlist is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#REQUIRED")
    g.xmlNextToken() # #
    g.xmlNextToken() # REQUIRED
    check g.kind == gtKeyword

  test "lowercase doctype is not a DTD keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("doctype")
    g.xmlNextToken()
    check g.kind == gtIdentifier

suite "syntax_xml - xmlNextToken special pseudo-attributes":
  test "version is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("version")
    g.xmlNextToken()
    check g.kind == gtBuiltin

  test "encoding is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("encoding")
    g.xmlNextToken()
    check g.kind == gtBuiltin

  test "standalone is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("standalone")
    g.xmlNextToken()
    check g.kind == gtBuiltin

  test "xmlns is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("xmlns")
    g.xmlNextToken()
    check g.kind == gtBuiltin

  test "prefixed xmlns is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("xmlns:bk")
    g.xmlNextToken()
    check g.kind == gtBuiltin
    check g.length == 8

  test "element named version is still a tag keyword":
    # The positional element-name rule wins over the pseudo-attribute list.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<version>")
    g.xmlNextToken() # <
    g.xmlNextToken() # version
    check g.kind == gtKeyword

  test "ordinary attribute name stays identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("href")
    g.xmlNextToken()
    check g.kind == gtIdentifier

suite "syntax_xml - xmlNextToken attributes":
  test "attribute value in double quotes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"value\"")
    g.xmlNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "attribute value in single quotes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'value'")
    g.xmlNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "equals sign is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.xmlNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntax_xml - xmlNextToken comments":
  test "XML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- comment -->")
    g.xmlNextToken()
    check g.kind == gtLongComment
    check g.length == 16

  test "multiline XML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- line1\nline2 -->")
    g.xmlNextToken()
    check g.kind == gtLongComment

  test "unterminated XML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- unterminated")
    g.xmlNextToken()
    check g.kind == gtLongComment
    check g.state == gtLongComment

  test "comment continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- start")
    g.xmlNextToken()
    check g.kind == gtLongComment
    check g.state == gtLongComment

suite "syntax_xml - xmlNextToken CDATA":
  test "CDATA section":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<![CDATA[raw data]]>")
    g.xmlNextToken()
    check g.kind == gtCData
    check g.length == 20
    check g.state == gtNone

  test "CDATA section with markup characters":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<![CDATA[a < b && b > c]]>")
    g.xmlNextToken()
    check g.kind == gtCData
    check g.length == 26

  test "unterminated CDATA section":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<![CDATA[unterminated")
    g.xmlNextToken()
    check g.kind == gtCData
    check g.state == gtCData

  test "CDATA continuation across lines":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<![CDATA[line1\nline2]]>")
    g.xmlNextToken()
    check g.kind == gtCData
    check g.state == gtNone

  test "CDATA continuation from saved state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("still raw]]><next>")
    g.state = gtCData
    g.xmlNextToken()
    check g.kind == gtCData
    check g.length == 12
    check g.state == gtNone
    g.xmlNextToken()
    check g.kind == gtTagStart

  test "single ] inside CDATA does not end the section":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<![CDATA[a]b]]>")
    g.xmlNextToken()
    check g.kind == gtCData
    check g.length == 15
    check g.state == gtNone

suite "syntax_xml - xmlNextToken multibyte":
  test "multibyte element name is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<書名>")
    g.xmlNextToken() # <
    g.xmlNextToken() # 書名
    check g.kind == gtKeyword
    check g.length == "書名".len

  test "multibyte closing element name is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("</書名>")
    g.xmlNextToken() # <
    g.xmlNextToken() # /
    g.xmlNextToken() # 書名
    check g.kind == gtKeyword
    check g.length == "書名".len

  test "multibyte text content is a single token":
    # Byte-wise tokenization of multibyte runs would shift the rune-based
    # column bookkeeping in highlight.nim for everything after them.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("日本語のテキスト")
    g.xmlNextToken()
    check g.kind == gtIdentifier
    check g.length == "日本語のテキスト".len

  test "multibyte attribute value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"しょめい\"")
    g.xmlNextToken()
    check g.kind == gtStringLit
    check g.length == "\"しょめい\"".len

suite "syntax_xml - xmlNextToken entities":
  test "named entity":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&amp;")
    g.xmlNextToken()
    check g.kind == gtOperator
    check g.length == 5

  test "numeric entity":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&#65;")
    g.xmlNextToken()
    check g.kind == gtOperator
    check g.length == 5

  test "hex entity":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&#x41;")
    g.xmlNextToken()
    check g.kind == gtOperator
    check g.length == 6

  test "entity name may contain XML name chars":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&my.entity;")
    g.xmlNextToken()
    check g.kind == gtOperator
    check g.length == 11

  test "hash is only valid as a character reference prefix":
    # `&a#b;` is not a legal entity: the scan stops before `#`.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&a#b;")
    g.xmlNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntax_xml - xmlNextToken whitespace":
  test "space between tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("> <")
    g.xmlNextToken() # >
    g.xmlNextToken() # space
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline between tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">\n<")
    g.xmlNextToken() # >
    g.xmlNextToken() # newline
    check g.kind == gtWhitespace

suite "syntax_xml - xmlNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.xmlNextToken()
    check g.kind == gtEof

  test "EOF after token":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.xmlNextToken()
    g.xmlNextToken()
    check g.kind == gtEof

suite "syntax_xml - xmlNextToken complete XML":
  test "simple element":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<note>content</note>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.xmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens
    check gtKeyword in tokens # note
    check gtIdentifier in tokens # content
    check gtTagEnd in tokens

  test "element with attribute":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<note priority=\"high\">")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.xmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens
    check gtKeyword in tokens # note
    check gtIdentifier in tokens # priority
    check gtOperator in tokens # =
    check gtStringLit in tokens # "high"
    check gtTagEnd in tokens

  test "XML declaration":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<?xml version=\"1.0\" encoding=\"UTF-8\"?>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.xmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens
    check gtKeyword in tokens # xml
    check gtBuiltin in tokens # version, encoding
    check gtStringLit in tokens # "1.0", "UTF-8"
    check gtTagEnd in tokens # ?>

  test "XML with comment and CDATA":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<a><!-- c --><![CDATA[d]]></a>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.xmlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLongComment in tokens
    check gtCData in tokens
