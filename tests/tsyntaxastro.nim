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

type TestToken = object
  kind: TokenClass
  start, length: int
  pos: int
  state: TokenClass

proc toTestToken(gt: GeneralTokenizer): TestToken =
  TestToken(
    kind: gt.kind, start: gt.start, length: gt.length, pos: gt.pos, state: gt.state
  )

proc tokens(code: string): seq[TestToken] =
  var token = GeneralTokenizer()
  token.initGeneralTokenizer(code)

  while true:
    token.getNextToken(SourceLanguage.langAstro)
    if token.kind == gtEof:
      break
    else:
      result.add token.toTestToken()

suite "syntax: Astro":
  test "Basic frontmatter only":
    const Code =
      """---
const a = 'hello';
---"""
    check tokens(Code) ==
      @[
        TestToken(kind: gtDirective, start: 0, length: 3, pos: 3, state: gtEof),
        TestToken(kind: gtWhitespace, start: 3, length: 1, pos: 4, state: gtEof),
        TestToken(kind: gtKeyword, start: 4, length: 5, pos: 9, state: gtEof),
        TestToken(kind: gtWhitespace, start: 9, length: 1, pos: 10, state: gtEof),
        TestToken(kind: gtIdentifier, start: 10, length: 1, pos: 11, state: gtEof),
        TestToken(kind: gtWhitespace, start: 11, length: 1, pos: 12, state: gtEof),
        TestToken(kind: gtOperator, start: 12, length: 1, pos: 13, state: gtEof),
        TestToken(kind: gtWhitespace, start: 13, length: 1, pos: 14, state: gtEof),
        TestToken(kind: gtStringLit, start: 14, length: 7, pos: 21, state: gtEof),
        TestToken(kind: gtPunctuation, start: 21, length: 1, pos: 22, state: gtEof),
        TestToken(kind: gtWhitespace, start: 22, length: 1, pos: 23, state: gtEof),
        TestToken(kind: gtDirective, start: 23, length: 3, pos: 26, state: gtEof),
      ]

  test "Simple Astro component":
    const Code =
      """---
const message = 'Hello World';
---

<div>{message}</div>"""

    let result = tokens(Code)

    # Test basic structure: frontmatter delimiters and content
    check result[0].kind == gtDirective
    check result[0].length == 3

    # Find the closing delimiter
    var foundClosingDelimiter = false
    for token in result:
      if token.kind == gtDirective and token.start > 10:
        foundClosingDelimiter = true
        break
    check foundClosingDelimiter

  test "Frontmatter with imports":
    const Code =
      """---
import { Component } from 'astro:components';
const title = 'My Page';
---"""

    let result = tokens(Code)

    # Test frontmatter delimiters
    check result[0].kind == gtDirective
    check result[0].length == 3

    # Test that import keyword is recognized
    var hasImport = false
    var hasConst = false
    for token in result:
      if token.kind == gtKeyword:
        if token.start == 4 and token.length == 6: # "import"
          hasImport = true
        elif token.length == 5: # "const"
          hasConst = true

    check hasImport
    check hasConst

  test "JSX template with expressions":
    const Code =
      """---
const name = 'Astro';
const items = ['a', 'b', 'c'];
---

<div>
  <h1>Hello {name}!</h1>
  <ul>
    {items.map(item => <li>{item}</li>)}
  </ul>
</div>"""
    # Test that frontmatter delimiters are properly recognized
    let result = tokens(Code)

    # First token should be the opening frontmatter delimiter
    check result[0].kind == gtDirective
    check result[0].length == 3

    # Find the closing frontmatter delimiter
    var closingDelimiterFound = false
    for token in result:
      if token.kind == gtDirective and token.start > 10:
        closingDelimiterFound = true
        break
    check closingDelimiterFound

  test "Frontmatter with TypeScript":
    const Code =
      """---
interface Props {
  title: string;
  count?: number;
}

const { title, count = 0 }: Props = Astro.props;
---

<h1>{title}</h1>
<p>Count: {count}</p>"""

    let result = tokens(Code)

    # Should start with frontmatter delimiter
    check result[0].kind == gtDirective

    # Should contain keywords from frontmatter
    var hasInterface = false
    for token in result:
      if token.kind == gtKeyword and token.length == 9: # "interface"
        hasInterface = true
        break
    check hasInterface

  test "HTML template without frontmatter":
    const Code =
      """<div>
  <h1>Hello World</h1>
  <p>This is just HTML</p>
</div>"""

    let result = tokens(Code)

    # Should parse as HTML (no frontmatter delimiters)
    check result[0].kind == gtOperator # <
    check result[1].kind == gtKeyword # div is recognized as HTML keyword

  test "Complex Astro component":
    const Code =
      """---
export interface Props {
  title: string;
  subtitle?: string;
}

const { title, subtitle = 'Default subtitle' } = Astro.props as Props;
const greeting = `Hello, ${title}!`;
---

<Layout title={title}>
  <main>
    <h1>{greeting}</h1>
    {subtitle && <p>{subtitle}</p>}
  </main>
</Layout>"""

    let result = tokens(Code)

    # Verify structure: frontmatter start, content, frontmatter end, template
    check result[0].kind == gtDirective # Opening ---

    # Find closing delimiter
    var closingFound = false
    var afterClosing = false
    for i, token in result:
      if token.kind == gtDirective and token.start > 10:
        closingFound = true
        # Check that we have template content after closing
        if i + 1 < result.len:
          afterClosing = true
        break

    check closingFound
    check afterClosing

  test "Empty frontmatter":
    const Code =
      """---
---

<div>Content</div>"""

    let result = tokens(Code)

    check result[0].kind == gtDirective # Opening ---
    check result[1].kind == gtWhitespace # newline
    check result[2].kind == gtDirective # Closing ---

  test "Frontmatter with comments":
    const Code =
      """---
// This is a comment
const value = 42; /* block comment */
---

<div>{value}</div>"""

    let result = tokens(Code)

    # Should contain comment tokens
    var hasComment = false
    var hasBlockComment = false

    for token in result:
      if token.kind == gtComment:
        hasComment = true
      elif token.kind == gtLongComment:
        hasBlockComment = true

    check hasComment
    check hasBlockComment

  test "Template with template literals":
    const Code =
      """---
const message = `Hello ${name}!`;
---

<div>{message}</div>"""

    let result = tokens(Code)

    # Should handle template literals in frontmatter
    var hasTemplateLiteral = false
    for token in result:
      if token.kind == gtLongStringLit:
        hasTemplateLiteral = true
        break

    check hasTemplateLiteral
