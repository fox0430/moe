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

import ../src/moepkg/syntax/[tokenizer, syntax_astro]

suite "syntaxastro - frontmatter delimiter":
  test "frontmatter start delimiter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---")
    g.astroNextToken()
    check g.kind == gtDirective
    check g.length == 3

  test "frontmatter start with trailing newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n")
    g.astroNextToken()
    check g.kind == gtDirective
    # Includes newline as part of delimiter line
    check g.length == 3

  test "frontmatter end delimiter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n---")
    g.astroNextToken() # Start delimiter
    check g.kind == gtDirective
    check g.lang.astro.inFrontmatter == true

    g.astroNextToken() # Newline
    g.astroNextToken() # End delimiter
    check g.kind == gtDirective
    check g.lang.astro.inFrontmatter == false

suite "syntaxastro - frontmatter JavaScript content":
  test "JavaScript variable in frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\nconst x = 1;\n---")

    g.astroNextToken() # ---
    check g.kind == gtDirective
    check g.lang.astro.inFrontmatter == true

    g.astroNextToken() # \n
    check g.kind == gtWhitespace

    g.astroNextToken() # const
    check g.kind == gtKeyword

  test "JavaScript import in frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\nimport x from 'y';\n---")

    g.astroNextToken() # ---
    g.astroNextToken() # \n
    g.astroNextToken() # import
    check g.kind == gtKeyword

  test "JavaScript function in frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\nfunction test() {}\n---")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens # --- delimiters
    check gtKeyword in tokens # function

suite "syntaxastro - HTML content outside frontmatter":
  test "HTML tag after frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n---\n<div>")

    g.astroNextToken() # --- start
    check g.kind == gtDirective

    g.astroNextToken() # \n
    g.astroNextToken() # --- end
    check g.kind == gtDirective
    check g.lang.astro.inFrontmatter == false

    g.astroNextToken() # \n
    g.astroNextToken() # <div>
    check g.kind == gtTagStart

  test "HTML content without frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<html>")

    g.astroNextToken()
    check g.kind == gtTagStart

  test "HTML closing tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("</div>")

    g.astroNextToken()
    check g.kind == gtTagStart

  test "HTML comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!-- comment -->")

    g.astroNextToken()
    check g.kind == gtLongComment

suite "syntaxastro - JSX expressions":
  test "JSX expression with curly brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n---\n{value}")

    g.astroNextToken() # --- start
    g.astroNextToken() # \n
    g.astroNextToken() # --- end
    g.astroNextToken() # \n
    g.astroNextToken() # {
    check g.kind == gtPunctuation

  test "JSX expression in template":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n---\n<p>{text}</p>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens # --- delimiters
    check gtTagStart in tokens # <p>, </p>
    check gtPunctuation in tokens # {, }

suite "syntaxastro - complete Astro file":
  test "simple Astro component":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      """---
const title = "Hello";
---
<h1>{title}</h1>"""
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens # --- delimiters
    check gtKeyword in tokens # const
    check gtStringLit in tokens # "Hello"
    check gtTagStart in tokens # <h1>, </h1>

  test "Astro with import":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      """---
import Layout from './Layout.astro';
---
<Layout>content</Layout>"""
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens
    check gtKeyword in tokens # import, from

  test "Astro with multiple JavaScript statements":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      """---
const a = 1;
const b = 2;
const c = a + b;
---
<div>{c}</div>"""
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens
    check gtKeyword in tokens # const
    check gtDecNumber in tokens # 1, 2
    check gtOperator in tokens # =, +

suite "syntaxastro - state tracking":
  test "astroFirstLine resets at position 0":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---")
    g.astroNextToken()
    check g.lang.astro.firstLine == false
    check g.lang.astro.inFrontmatter == true

  test "astroInFrontmatter tracks state correctly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\ncode\n---")

    g.astroNextToken() # ---
    check g.lang.astro.inFrontmatter == true

    # Skip through content
    while g.kind != gtEof:
      if g.kind == gtDirective and g.lang.astro.inFrontmatter == false:
        break
      g.astroNextToken()

    check g.lang.astro.inFrontmatter == false

suite "syntaxastro - edge cases":
  test "empty file":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.astroNextToken()
    check g.kind == gtEof

  test "only frontmatter delimiters":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n---")

    g.astroNextToken() # ---
    check g.kind == gtDirective

    g.astroNextToken() # \n
    check g.kind == gtWhitespace

    g.astroNextToken() # ---
    check g.kind == gtDirective

  test "file without frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<html><body>Hello</body></html>")

    g.astroNextToken()
    check g.kind == gtTagStart
    check g.lang.astro.inFrontmatter == false

  test "text content in template":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n---\nHello World")

    g.astroNextToken() # ---
    g.astroNextToken() # \n
    g.astroNextToken() # ---
    g.astroNextToken() # \n
    g.astroNextToken() # Hello (as HTML text)
    # Text is handled by HTML tokenizer

  test "dashes not at start are not frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("text\n---")

    g.astroNextToken() # text handled by HTML
    check g.lang.astro.firstLine == false
    # The --- later is not treated as frontmatter since it's not at position 0

suite "syntaxastro - HTML elements":
  test "self-closing tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<br/>")

    g.astroNextToken()
    check g.kind == gtTagStart

  test "tag with attributes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div class=\"test\">")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens
    check gtStringLit in tokens # "test"

  test "nested tags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div><span>text</span></div>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens

suite "syntaxastro - JavaScript in frontmatter":
  test "arrow function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\nconst fn = () => {};\n---")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens
    check gtKeyword in tokens # const
    check gtOperator in tokens # =, =>

  test "async function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\nasync function fetch() {}\n---")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # async, function

  test "template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\nconst s = `template`;\n---")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens
    check gtKeyword in tokens

  test "JavaScript comments in frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n// comment\n---")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens
    check gtComment in tokens

  test "multi-line JavaScript comment in frontmatter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n/* multi\nline */\n---")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.astroNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens
    check gtLongComment in tokens
