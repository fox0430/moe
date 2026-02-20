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
import ../src/moepkg/syntax/syntaxmarkdown

suite "syntaxmarkdown - markdownNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.markdownNextToken()
    check g.kind == gtEof

  test "EOF after token":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a")
    g.markdownNextToken()
    g.markdownNextToken()
    check g.kind == gtEof

suite "syntaxmarkdown - markdownNextToken backtick (inline code)":
  test "single backtick inline code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`code`")
    g.markdownNextToken()
    check g.kind == gtSpecialVar
    check g.length == 6

  test "inline code with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello world`")
    g.markdownNextToken()
    check g.kind == gtSpecialVar
    check g.length == 13

  test "unclosed inline code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`unclosed")
    g.markdownNextToken()
    check g.kind == gtSpecialVar

suite "syntaxmarkdown - markdownNextToken triple backtick (code block)":
  test "triple backtick code block":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```nim\necho 1\n```")
    g.markdownNextToken()
    check g.kind == gtSpecialVar

  test "triple backtick code block single line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```code```")
    g.markdownNextToken()
    check g.kind == gtSpecialVar

  test "unclosed triple backtick":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```unclosed")
    g.markdownNextToken()
    check g.kind == gtSpecialVar

suite "syntaxmarkdown - markdownNextToken hash (headings)":
  test "hash at line start is heading":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Heading")
    g.markdownNextToken()
    check g.kind == gtBuiltin

  test "hash after newline is heading":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("text\n# Heading")

    # Skip 'text'
    g.markdownNextToken()
    # Skip newline whitespace
    g.markdownNextToken()
    # Hash for heading
    g.markdownNextToken()
    check g.kind == gtBuiltin

  test "hash in middle of line is punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a#b")

    g.markdownNextToken() # 'a'
    g.markdownNextToken() # '#'
    check g.kind == gtPunctuation

suite "syntaxmarkdown - markdownNextToken dash (frontmatter)":
  test "triple dash frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\ntitle: test\n---")
    g.markdownNextToken()
    check g.kind == gtPreprocessor

  test "single dash is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.markdownNextToken()
    check g.kind == gtBuiltin

  test "double dash is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--")
    g.markdownNextToken()
    check g.kind == gtBuiltin

suite "syntaxmarkdown - markdownNextToken HTML comment":
  test "HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- comment -->")
    g.markdownNextToken()
    check g.kind == gtLongComment

  test "multiline HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- line1\nline2 -->")
    g.markdownNextToken()
    check g.kind == gtLongComment

  test "unclosed HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- unclosed")
    g.markdownNextToken()
    check g.kind == gtLongComment

  test "less than not followed by comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div>")
    g.markdownNextToken()
    check g.kind == gtBuiltin

suite "syntaxmarkdown - markdownNextToken symbols":
  test "lowercase symbol":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello")
    g.markdownNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "uppercase symbol":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Hello")
    g.markdownNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "mixed case symbol":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("HelloWorld")
    g.markdownNextToken()
    check g.kind == gtIdentifier
    check g.length == 10

  test "symbol with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello_world")
    g.markdownNextToken()
    check g.kind == gtIdentifier
    check g.length == 11

  test "symbol with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("test123")
    g.markdownNextToken()
    check g.kind == gtIdentifier
    check g.length == 7

suite "syntaxmarkdown - markdownNextToken punctuation":
  test "parentheses":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "closing parenthesis":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "square brackets":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "closing square bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "curly braces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "closing curly brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "period":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "forward slash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "single quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "double quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"")
    g.markdownNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxmarkdown - markdownNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.markdownNextToken() # 'a'
    g.markdownNextToken() # space
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.markdownNextToken() # 'a'
    g.markdownNextToken() # spaces
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.markdownNextToken() # 'a'
    g.markdownNextToken() # tab
    check g.kind == gtWhitespace

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.markdownNextToken() # 'a'
    g.markdownNextToken() # newline
    check g.kind == gtWhitespace

  test "mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a \t\n b")
    g.markdownNextToken() # 'a'
    g.markdownNextToken() # mixed whitespace
    check g.kind == gtWhitespace

suite "syntaxmarkdown - markdownNextToken other characters":
  test "number alone is gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1")
    g.markdownNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "special character":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.markdownNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "asterisk":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.markdownNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "plus sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.markdownNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "equals sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.markdownNextToken()
    check g.kind == gtNone
    check g.length == 1

suite "syntaxmarkdown - markdownNextToken complete markdown":
  test "heading with text":
    # Note: heading is lexed as a single token until end of line
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Hello World")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.markdownNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtBuiltin in tokens # entire heading line

  test "inline code in text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Use `code` here")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.markdownNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # Use, here
    check gtSpecialVar in tokens # `code`
    check gtWhitespace in tokens

  test "link syntax":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[link](url)")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.markdownNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # [, ], (, )
    check gtIdentifier in tokens # link, url

  test "markdown with HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("text <!-- comment --> more")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.markdownNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # text, more
    check gtLongComment in tokens # <!-- comment -->
    check gtWhitespace in tokens

  test "frontmatter and content":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\ntitle: test\n---\n# Content")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.markdownNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPreprocessor in tokens # frontmatter
    check gtBuiltin in tokens # heading

  test "code block":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```\ncode\n```")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.markdownNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtSpecialVar in tokens # code block
