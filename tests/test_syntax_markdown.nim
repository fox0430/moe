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

import ../src/moepkg/syntax/[tokenizer, syntax_markdown]

proc collectTokens(input: string): seq[(TokenClass, string)] =
  var g: GeneralTokenizer
  g.initGeneralTokenizer(input)
  while true:
    g.markdownNextToken()
    if g.kind == gtEof:
      break
    result.add((g.kind, input[g.start ..< g.start + g.length]))

proc collectKinds(input: string): seq[TokenClass] =
  for (kind, _) in collectTokens(input):
    result.add(kind)

suite "syntax_markdown - EOF":
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

suite "syntax_markdown - backtick (inline code)":
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

  test "unclosed inline code does not span newline":
    # An unclosed backtick must stop at the end of the line rather than
    # bleeding into the next line; otherwise incremental re-parsing from a
    # later line cannot know it is inside a code span.
    let tokens = collectTokens("a `code\nnext line")
    check tokens[2] == (gtSpecialVar, "`code")
    check tokens[3][0] == gtWhitespace # newline, not part of the code span

suite "syntax_markdown - triple backtick (code block)":
  test "opening ``` emits gtSpecialVar":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("```\ncode\n```")
    g.markdownNextToken()
    check g.kind == gtSpecialVar
    check g.length == 3 # just the ```

  test "code block with language name":
    let tokens = collectTokens("```nim\necho 1\n```")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[1] == (gtKeyword, "nim")
    check tokens[2][0] == gtWhitespace # newline
    check tokens[3] == (gtLongStringLit, "echo 1")
    check tokens[4][0] == gtWhitespace # newline
    check tokens[5] == (gtSpecialVar, "```")

  test "code block without language name":
    let tokens = collectTokens("```\nsome code\n```")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[1][0] == gtWhitespace # newline
    check tokens[2] == (gtLongStringLit, "some code")
    check tokens[3][0] == gtWhitespace # newline
    check tokens[4] == (gtSpecialVar, "```")

  test "unclosed code block":
    let tokens = collectTokens("```\ncode")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[1][0] == gtWhitespace
    check tokens[2] == (gtLongStringLit, "code")

suite "syntax_markdown - hash (headings)":
  test "hash at line start is heading":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Heading")
    g.markdownNextToken()
    check g.kind == gtBuiltin

  test "hash after newline is heading":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("text\n# Heading")
    g.markdownNextToken() # 'text'
    g.markdownNextToken() # newline
    g.markdownNextToken() # heading
    check g.kind == gtBuiltin

  test "hash in middle of line is punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a#b")
    g.markdownNextToken() # 'a'
    g.markdownNextToken() # '#'
    check g.kind == gtPunctuation

suite "syntax_markdown - dash (frontmatter)":
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

suite "syntax_markdown - dash list marker":
  test "`- ` at line start is list marker":
    let tokens = collectTokens("- item")
    check tokens[0] == (gtOperator, "- ")
    check tokens[1] == (gtIdentifier, "item")

  test "`- ` after newline is list marker":
    let tokens = collectTokens("text\n- item")
    check tokens[0] == (gtIdentifier, "text")
    check tokens[1][0] == gtWhitespace
    check tokens[2] == (gtOperator, "- ")

suite "syntax_markdown - HTML comment":
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

suite "syntax_markdown - bold":
  test "**bold** with asterisks":
    let tokens = collectTokens("**bold**")
    check tokens[0] == (gtKeyword, "**bold**")

  test "__bold__ with underscores":
    let tokens = collectTokens("__bold__")
    check tokens[0] == (gtKeyword, "__bold__")

  test "unclosed **bold":
    let tokens = collectTokens("**unclosed")
    check tokens[0][0] == gtKeyword

  test "bold in sentence":
    let tokens = collectTokens("a **bold** b")
    check tokens[0] == (gtIdentifier, "a")
    check tokens[2] == (gtKeyword, "**bold**")
    check tokens[4] == (gtIdentifier, "b")

suite "syntax_markdown - italic":
  test "*italic* with asterisk":
    let tokens = collectTokens("*italic*")
    check tokens[0] == (gtStringLit, "*italic*")

  test "_italic_ with underscore":
    let tokens = collectTokens("_italic_")
    check tokens[0] == (gtStringLit, "_italic_")

  test "unclosed *italic":
    let tokens = collectTokens("*unclosed")
    check tokens[0][0] == gtStringLit

  test "italic in sentence":
    let tokens = collectTokens("a *italic* b")
    check tokens[0] == (gtIdentifier, "a")
    check tokens[2] == (gtStringLit, "*italic*")
    check tokens[4] == (gtIdentifier, "b")

suite "syntax_markdown - strikethrough":
  test "~~strikethrough~~":
    let tokens = collectTokens("~~struck~~")
    check tokens[0] == (gtComment, "~~struck~~")

  test "unclosed ~~strikethrough":
    let tokens = collectTokens("~~unclosed")
    check tokens[0][0] == gtComment

  test "single tilde is gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("~")
    g.markdownNextToken()
    check g.kind == gtNone

suite "syntax_markdown - block quote":
  test "> at line start is block quote":
    let tokens = collectTokens("> quoted text")
    check tokens[0][0] == gtComment
    check tokens[0][1] == "> quoted text"

  test "> after newline is block quote":
    let tokens = collectTokens("text\n> quote")
    check tokens[0] == (gtIdentifier, "text")
    check tokens[1][0] == gtWhitespace
    check tokens[2] == (gtComment, "> quote")

  test "> in middle of line is gtNone":
    let tokens = collectTokens("a > b")
    check tokens[0] == (gtIdentifier, "a")
    # > should not be a block quote in middle of line

suite "syntax_markdown - links":
  test "[text](url) link":
    let tokens = collectTokens("[link](url)")
    check tokens[0] == (gtKeyword, "[link]")
    check tokens[1] == (gtSpecialVar, "(url)")

  test "link in sentence":
    let tokens = collectTokens("see [here](http://example.com) for info")
    var hasKeyword = false
    var hasSpecialVar = false
    for (kind, _) in tokens:
      if kind == gtKeyword:
        hasKeyword = true
      if kind == gtSpecialVar:
        hasSpecialVar = true
    check hasKeyword
    check hasSpecialVar

  test "[ without matching ](url) is punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[text]")
    g.markdownNextToken()
    check g.kind == gtPunctuation

suite "syntax_markdown - images":
  test "![alt](url) image":
    let tokens = collectTokens("![alt](url)")
    check tokens[0] == (gtKeyword, "![alt]")
    check tokens[1] == (gtSpecialVar, "(url)")

  test "! alone is gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!")
    g.markdownNextToken()
    check g.kind == gtNone

suite "syntax_markdown - list markers":
  test "`* ` at line start":
    let tokens = collectTokens("* item")
    check tokens[0] == (gtOperator, "* ")
    check tokens[1] == (gtIdentifier, "item")

  test "`+ ` at line start":
    let tokens = collectTokens("+ item")
    check tokens[0] == (gtOperator, "+ ")
    check tokens[1] == (gtIdentifier, "item")

  test "ordered list `1. `":
    let tokens = collectTokens("1. item")
    check tokens[0] == (gtOperator, "1. ")
    check tokens[1] == (gtIdentifier, "item")

  test "ordered list `42. `":
    let tokens = collectTokens("42. item")
    check tokens[0] == (gtOperator, "42. ")
    check tokens[1] == (gtIdentifier, "item")

  test "number not followed by `. ` is gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("42")
    g.markdownNextToken()
    check g.kind == gtNone

  test "+ in middle of line is gtNone":
    let tokens = collectTokens("a+b")
    check tokens[0] == (gtIdentifier, "a")
    check tokens[1] == (gtNone, "+")

suite "syntax_markdown - symbols":
  test "lowercase symbol":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello")
    g.markdownNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "symbol with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello_world")
    g.markdownNextToken()
    check g.kind == gtIdentifier
    check g.length == 11

suite "syntax_markdown - punctuation":
  test "parentheses":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.markdownNextToken()
    check g.kind == gtPunctuation

  test "curly braces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.markdownNextToken()
    check g.kind == gtPunctuation

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.markdownNextToken()
    check g.kind == gtPunctuation

suite "syntax_markdown - whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.markdownNextToken() # 'a'
    g.markdownNextToken() # space
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.markdownNextToken() # 'a'
    g.markdownNextToken() # newline
    check g.kind == gtWhitespace

suite "syntax_markdown - other characters":
  test "number alone is gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1")
    g.markdownNextToken()
    check g.kind == gtNone

  test "special character":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.markdownNextToken()
    check g.kind == gtNone

  test "asterisk alone is gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.markdownNextToken()
    check g.kind == gtNone

  test "asterisk followed by space is gtNone":
    let tokens = collectTokens("2 * 3")
    # * surrounded by spaces should NOT be italic
    check tokens[0] == (gtNone, "2")
    check tokens[2] == (gtNone, "*")

  test "equals sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.markdownNextToken()
    check g.kind == gtNone

suite "syntax_markdown - code block edge cases":
  test "code block with multiple content lines":
    let tokens = collectTokens("```\nline1\nline2\nline3\n```")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[2] == (gtLongStringLit, "line1")
    check tokens[4] == (gtLongStringLit, "line2")
    check tokens[6] == (gtLongStringLit, "line3")
    check tokens[8] == (gtSpecialVar, "```")

  test "code block content containing backticks (not closing)":
    let tokens = collectTokens("```\n`inline`\n``two``\n```")
    check tokens[0] == (gtSpecialVar, "```")
    # ` inside code block is content, not inline code
    check tokens[2] == (gtLongStringLit, "`inline`")
    check tokens[4] == (gtLongStringLit, "``two``")
    check tokens[6] == (gtSpecialVar, "```")

  test "code block followed by normal text":
    let tokens = collectTokens("```\ncode\n```\nnormal")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[2] == (gtLongStringLit, "code")
    check tokens[4] == (gtSpecialVar, "```")
    check tokens[6] == (gtIdentifier, "normal")

  test "empty code block":
    let tokens = collectTokens("```\n```")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[1][0] == gtWhitespace
    check tokens[2] == (gtSpecialVar, "```")

  test "code block with language name immediately followed by EOF":
    let tokens = collectTokens("```python")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[1] == (gtKeyword, "python")

  test "code block language name not detected after whitespace":
    # ```  nim → whitespace clears the gtSpecialVar state,
    # so "nim" becomes content, not language name
    let tokens = collectTokens("```  nim\ncode\n```")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[1][0] == gtWhitespace # spaces
    check tokens[2] == (gtLongStringLit, "nim")

  test "code block mdInCodeBlock flag cleared after closing":
    let tokens = collectTokens("```\nA\n```\n**bold**")
    var hasLongString = false
    var hasKeyword = false
    for (kind, _) in tokens:
      if kind == gtLongStringLit:
        hasLongString = true
      if kind == gtKeyword:
        hasKeyword = true
    check hasLongString # inside code block
    check hasKeyword # **bold** after code block

  test "single backtick inside code block line starting with backtick":
    let tokens = collectTokens("```\n`x\n```")
    check tokens[0] == (gtSpecialVar, "```")
    check tokens[2] == (gtLongStringLit, "`x")
    check tokens[4] == (gtSpecialVar, "```")

  test "double backtick inside code block is content":
    let tokens = collectTokens("```\n``not closing\n```")
    check tokens[2] == (gtLongStringLit, "``not closing")

  test "triple backticks with closing on same line is not code block":
    # ```abc``` is not a valid code fence (info string contains backticks)
    # Text after it should be highlighted normally
    let tokens = collectTokens("```abc```\ndef")
    check tokens[0] == (gtSpecialVar, "```abc```")
    check tokens[2] == (gtIdentifier, "def")

  test "triple backticks inline does not break subsequent highlighting":
    let tokens = collectTokens("# Title\n\n```abc```\n\n**bold**")
    # Find the bold token after the inline triple backticks
    var foundBold = false
    for (kind, text) in tokens:
      if kind == gtKeyword and text == "**bold**":
        foundBold = true
    check foundBold

suite "syntax_markdown - bold edge cases":
  test "** followed by space is not bold":
    let tokens = collectTokens("** text**")
    # ** followed by space → first * is gtNone, second * is gtNone
    check tokens[0][0] == gtNone

  test "__ followed by space is not bold":
    let tokens = collectTokens("__ text__")
    # __ followed by space → falls to identifier
    check tokens[0][0] == gtIdentifier

  test "bold with single asterisk inside":
    let tokens = collectTokens("**a*b**")
    check tokens[0] == (gtKeyword, "**a*b**")

  test "bold with single underscore inside":
    let tokens = collectTokens("__a_b__")
    check tokens[0] == (gtKeyword, "__a_b__")

  test "unclosed __bold":
    let tokens = collectTokens("__unclosed")
    check tokens[0][0] == gtKeyword

suite "syntax_markdown - italic edge cases":
  test "_ followed by space is identifier":
    let tokens = collectTokens("_ text")
    check tokens[0][0] == gtIdentifier

  test "__ followed by space is identifier":
    let tokens = collectTokens("__ text")
    check tokens[0][0] == gtIdentifier

  test "unclosed _italic":
    let tokens = collectTokens("_unclosed")
    check tokens[0][0] == gtStringLit

  test "underscore in middle of word is identifier":
    let tokens = collectTokens("hello_world")
    check tokens[0] == (gtIdentifier, "hello_world")

  test "italic does not cross newline":
    let tokens = collectTokens("*open\nnext*")
    # *open stops at newline
    check tokens[0] == (gtStringLit, "*open")
    check tokens[1][0] == gtWhitespace

suite "syntax_markdown - strikethrough edge cases":
  test "strikethrough in sentence":
    let tokens = collectTokens("a ~~old~~ b")
    check tokens[0] == (gtIdentifier, "a")
    check tokens[2] == (gtComment, "~~old~~")
    check tokens[4] == (gtIdentifier, "b")

  test "~~ does not cross newline":
    let tokens = collectTokens("~~open\nnext~~")
    check tokens[0] == (gtComment, "~~open")
    check tokens[1][0] == gtWhitespace

  test "single tilde in middle of text":
    let tokens = collectTokens("a~b")
    check tokens[0] == (gtIdentifier, "a")
    check tokens[1] == (gtNone, "~")
    check tokens[2] == (gtIdentifier, "b")

suite "syntax_markdown - link edge cases":
  test "link with space between ] and ( is not a link URL":
    let tokens = collectTokens("[text] (url)")
    # [text] has ] not immediately followed by (, so [ is punctuation
    check tokens[0] == (gtPunctuation, "[")
    # ( after space should be punctuation, not specialVar
    var hasSpecialVar = false
    for (kind, text) in tokens:
      if kind == gtSpecialVar and text == "(url)":
        hasSpecialVar = true
    check not hasSpecialVar

  test "empty link text":
    let tokens = collectTokens("[](url)")
    check tokens[0] == (gtKeyword, "[]")
    check tokens[1] == (gtSpecialVar, "(url)")

  test "link with complex URL":
    let tokens = collectTokens("[click](https://example.com/path?q=1&r=2)")
    check tokens[0] == (gtKeyword, "[click]")
    check tokens[1] == (gtSpecialVar, "(https://example.com/path?q=1&r=2)")

  test "image with no closing bracket":
    let tokens = collectTokens("![unclosed")
    check tokens[0][0] == gtKeyword
    check tokens[0][1] == "![unclosed"

  test "[text] without (url) is punctuation":
    let tokens = collectTokens("[standalone]")
    check tokens[0] == (gtPunctuation, "[")

  test "( not preceded by ] is punctuation":
    let tokens = collectTokens("(standalone)")
    check tokens[0] == (gtPunctuation, "(")

suite "syntax_markdown - list marker edge cases":
  test "- not at line start is gtNone":
    let tokens = collectTokens("a - b")
    check tokens[0] == (gtIdentifier, "a")
    var hasDashNone = false
    for (kind, text) in tokens:
      if kind == gtNone and text == "-":
        hasDashNone = true
    check hasDashNone

  test "hyphen in quoted string is not a list marker":
    # "utf-8" — the `-` after `"utf` should not be treated as line-start
    let tokens = collectTokens("\"utf-8\"")
    var hasOperator = false
    for (kind, _) in tokens:
      if kind == gtOperator:
        hasOperator = true
    check not hasOperator

  test "hyphen after quote at line start is not a list marker":
    # "-x" — the `-` immediately after `"` at line start
    let tokens = collectTokens("\"-x\"")
    var hasOperator = false
    for (kind, _) in tokens:
      if kind == gtOperator:
        hasOperator = true
    check not hasOperator

  test "multiple list items":
    let tokens = collectTokens("- a\n- b\n- c")
    var operatorCount = 0
    for (kind, _) in tokens:
      if kind == gtOperator:
        inc operatorCount
    check operatorCount == 3

  test "ordered list after newline":
    let tokens = collectTokens("text\n1. first\n2. second")
    var operatorCount = 0
    for (kind, _) in tokens:
      if kind == gtOperator:
        inc operatorCount
    check operatorCount == 2

  test "* at line start without space is not list":
    let tokens = collectTokens("*word*")
    # Should be italic, not list marker
    check tokens[0][0] == gtStringLit

  test "+ at line start without space is gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+x")
    g.markdownNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "number with period but no space is not list":
    let tokens = collectTokens("3.14")
    check tokens[0][0] == gtNone # '3'

suite "syntax_markdown - block quote edge cases":
  test "nested block quotes":
    let tokens = collectTokens(">> nested")
    check tokens[0][0] == gtComment
    check tokens[0][1] == ">> nested"

  test "bare > at line start":
    let tokens = collectTokens(">")
    check tokens[0] == (gtComment, ">")

  test "multiple block quotes":
    let tokens = collectTokens("> a\n> b")
    check tokens[0] == (gtComment, "> a")
    check tokens[2] == (gtComment, "> b")

suite "syntax_markdown - heading edge cases":
  test "## level 2 heading":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("## Level 2")
    g.markdownNextToken()
    check g.kind == gtBuiltin
    check g.length == 10 # whole line

  test "### level 3 heading":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("### Level 3")
    g.markdownNextToken()
    check g.kind == gtBuiltin

  test "# alone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.markdownNextToken()
    check g.kind == gtBuiltin
    check g.length == 1

  test "multiple headings":
    let tokens = collectTokens("# H1\n## H2")
    check tokens[0][0] == gtBuiltin
    check tokens[0][1] == "# H1"
    check tokens[2][0] == gtBuiltin
    check tokens[2][1] == "## H2"

suite "syntax_markdown - HTML comment edge cases":
  test "<! not followed by -- is builtin":
    let tokens = collectTokens("<!DOCTYPE>")
    check tokens[0][0] == gtBuiltin

  test "<!- single dash is builtin":
    let tokens = collectTokens("<!-x")
    check tokens[0][0] == gtBuiltin

  test "HTML comment with extra dashes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<!--- comment --->")
    g.markdownNextToken()
    check g.kind == gtLongComment

suite "syntax_markdown - frontmatter edge cases":
  test "more than 3 dashes is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("----")
    g.markdownNextToken()
    check g.kind == gtBuiltin

  test "--- after content is a thematic break, not frontmatter":
    let tokens = collectTokens("a\n---\nb")
    # `---` is only frontmatter on the very first line of the document. Here it
    # follows content, so it is a thematic break (gtBuiltin) and must NOT flip
    # the rest of the document into preprocessor styling.
    check tokens[2] == (gtBuiltin, "---")
    check tokens[^1] == (gtIdentifier, "b")

  test "--- on first line is frontmatter":
    let tokens = collectTokens("---\ntitle: t\n---\nbody")
    # Opening fence, the body line, and the closing fence are all frontmatter;
    # content after the closing fence returns to normal markdown.
    check tokens[0] == (gtPreprocessor, "---")
    check tokens[2] == (gtPreprocessor, "title: t")
    check tokens[4] == (gtPreprocessor, "---")
    check tokens[^1] == (gtIdentifier, "body")

  test "blank line before --- is a thematic break, not frontmatter":
    # Frontmatter must be the very first line. A leading blank line demotes the
    # opening `---` to a thematic break and nothing becomes frontmatter.
    let tokens = collectTokens("\n---\ntitle: t\n---\nbody")
    check tokens[1] == (gtBuiltin, "---")
    for (kind, _) in tokens:
      check kind != gtPreprocessor

  test "leading spaces before --- is not frontmatter":
    # Frontmatter starts at column 0 of the first line; an indented `---` is
    # never a frontmatter opener.
    let tokens = collectTokens("   ---\nbody")
    for (kind, _) in tokens:
      check kind != gtPreprocessor

  test "closing fence must be exactly --- (4 dashes stays content)":
    # The closing fence mirrors the opening one: a `----` line is frontmatter
    # content, so the block stays open through the rest of the file.
    let tokens = collectTokens("---\ntitle: t\n----\nstill inside")
    check tokens[4] == (gtPreprocessor, "----")
    check tokens[^1] == (gtPreprocessor, "still inside")
    for (kind, _) in tokens:
      check kind != gtBuiltin

  test "thematic breaks do not leak frontmatter styling":
    # Regression: a document with no frontmatter but several `---` rules used to
    # alternate whole blocks into gtPreprocessor. Every `---` here is a thematic
    # break and the surrounding text stays normal markdown.
    let tokens = collectTokens("# H\n\n---\n\npara\n\n---\n\nmore")
    var dashCount, preprocessorCount = 0
    for (kind, lexeme) in tokens:
      if kind == gtBuiltin and lexeme == "---":
        inc dashCount
      if kind == gtPreprocessor:
        inc preprocessorCount
    check dashCount == 2
    check preprocessorCount == 0

suite "syntax_markdown - left-flanking delimiter guards":
  test "** with space after is not bold":
    let tokens = collectTokens("** ")
    # First * is gtNone, second * is also gtNone (not a list marker)
    check tokens[0] == (gtNone, "*")
    check tokens[1] == (gtNone, "*")

  test "__ with space after is identifier":
    let tokens = collectTokens("__ ")
    check tokens[0][0] == gtIdentifier

  test "* with space after is gtNone":
    let tokens = collectTokens("a * b")
    check tokens[2] == (gtNone, "*")

  test "_ with space after is identifier":
    let tokens = collectTokens("a _ b")
    check tokens[2][0] == gtIdentifier

  test "~~ with space after is still strikethrough":
    # ~~ does not have a left-flanking guard (by design)
    let tokens = collectTokens("~~ text~~")
    check tokens[0][0] == gtComment

suite "syntax_markdown - complete markdown":
  test "heading with text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Hello World")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.markdownNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtBuiltin in tokens

  test "inline code in text":
    let kinds = collectKinds("Use `code` here")
    check gtIdentifier in kinds
    check gtSpecialVar in kinds
    check gtWhitespace in kinds

  test "markdown with HTML comment":
    let kinds = collectKinds("text <!-- comment --> more")
    check gtIdentifier in kinds
    check gtLongComment in kinds

  test "frontmatter and content":
    let kinds = collectKinds("---\ntitle: test\n---\n# Content")
    check gtPreprocessor in kinds
    check gtBuiltin in kinds

  test "code block with content":
    let kinds = collectKinds("```\ncode\n```")
    check gtSpecialVar in kinds # ``` markers
    check gtLongStringLit in kinds # code content

  test "full document with mixed features":
    let tokens = collectTokens(
      "# Title\n\nSome **bold** and *italic* text.\n\n" & "- item 1\n- item 2\n\n" &
        "> A quote\n\n" & "[link](url)\n\n" & "```nim\necho 1\n```\n\n" & "~~old~~"
    )
    var kinds: set[TokenClass]
    for (kind, _) in tokens:
      kinds.incl(kind)
    check gtBuiltin in kinds # heading
    check gtKeyword in kinds # bold / link text / lang name
    check gtStringLit in kinds # italic
    check gtOperator in kinds # list markers
    check gtComment in kinds # blockquote / strikethrough
    check gtSpecialVar in kinds # ``` / link URL
    check gtLongStringLit in kinds # code block content
    check gtIdentifier in kinds # normal text

  test "code block between paragraphs preserves state":
    let tokens = collectTokens("Hello\n```\ncode\n```\nWorld")
    # Before code block
    check tokens[0] == (gtIdentifier, "Hello")
    # Code block
    var hasLongStr = false
    var hasSpecialVar = false
    for (kind, _) in tokens:
      if kind == gtLongStringLit:
        hasLongStr = true
      if kind == gtSpecialVar:
        hasSpecialVar = true
    check hasLongStr
    check hasSpecialVar
    # After code block — "World" should be identifier, not code content
    check tokens[^1] == (gtIdentifier, "World")

suite "Markdown - inline math mode":
  test "inline math $x+y$":
    let tokens = collectTokens("$x+y$")
    # Opening $, content, closing $
    check tokens[0] == (gtStringLit, "$")
    check tokens[^1] == (gtStringLit, "$")

  test "inline math with LaTeX command":
    let tokens = collectTokens("$\\alpha + \\beta$")
    check tokens[0] == (gtStringLit, "$")
    var foundKeyword = false
    for t in tokens:
      if t[0] == gtBuiltin and t[1] == "\\alpha":
        foundKeyword = true
    check foundKeyword
    check tokens[^1] == (gtStringLit, "$")

  test "inline math with keyword command":
    let tokens = collectTokens("$\\frac{a}{b}$")
    check tokens[0] == (gtStringLit, "$")
    var foundFrac = false
    for t in tokens:
      if t[0] == gtKeyword and t[1] == "\\frac":
        foundFrac = true
    check foundFrac

  test "inline math with surrounding text":
    let tokens = collectTokens("the formula $E=mc^2$ is famous")
    var hasMathOpen = false
    var hasMathClose = false
    for i, t in tokens:
      if t == (gtStringLit, "$"):
        if not hasMathOpen:
          hasMathOpen = true
        else:
          hasMathClose = true
    check hasMathOpen
    check hasMathClose

  test "inline math across lines":
    let tokens = collectTokens("$x+\ny$")
    var hasStringLit = false
    for t in tokens:
      if t[0] == gtStringLit:
        hasStringLit = true
    check hasStringLit

suite "Markdown - display math mode":
  test "display math $$E=mc^2$$":
    let tokens = collectTokens("$$E=mc^2$$")
    check tokens[0] == (gtLongStringLit, "$$")
    check tokens[^1] == (gtLongStringLit, "$$")

  test "display math with LaTeX command":
    let tokens = collectTokens("$$\\int_0^1 f(x) dx$$")
    check tokens[0] == (gtLongStringLit, "$$")
    var foundBuiltin = false
    for t in tokens:
      if t[0] == gtBuiltin and t[1] == "\\int":
        foundBuiltin = true
    check foundBuiltin
    check tokens[^1] == (gtLongStringLit, "$$")

  test "display math across lines":
    let tokens = collectTokens("$$\n\\sum_{i=1}^n\n$$")
    var hasKeyword = false
    for t in tokens:
      if t[0] == gtBuiltin and t[1] == "\\sum":
        hasKeyword = true
    check hasKeyword

  test "display math with surrounding text":
    let tokens = collectTokens("before $$x$$ after")
    var openCount = 0
    for t in tokens:
      if t == (gtLongStringLit, "$$"):
        inc openCount
    check openCount == 2

suite "Markdown - math mode LaTeX tokens":
  test "braces in math":
    let tokens = collectTokens("${a}$")
    var foundPunct = false
    for t in tokens:
      if t == (gtPunctuation, "{"):
        foundPunct = true
    check foundPunct

  test "operators in math":
    let tokens = collectTokens("$x^2_n$")
    var foundCaret = false
    var foundUnderscore = false
    for t in tokens:
      if t == (gtOperator, "^"):
        foundCaret = true
      if t == (gtOperator, "_"):
        foundUnderscore = true
    check foundCaret
    check foundUnderscore

  test "escape sequence in math":
    let tokens = collectTokens("$\\$$")
    # $ opens, \$ is escape, $ closes
    check tokens[0] == (gtStringLit, "$")
    check tokens[1] == (gtEscapeSequence, "\\$")
    check tokens[2] == (gtStringLit, "$")

  test "numbers in math":
    let tokens = collectTokens("$3.14$")
    var foundFloat = false
    for t in tokens:
      if t[0] == gtFloatNumber and t[1] == "3.14":
        foundFloat = true
    check foundFloat

  test "double backslash in math":
    let tokens = collectTokens("$a \\\\ b$")
    var foundLineBreak = false
    for t in tokens:
      if t[0] == gtBuiltin and t[1] == "\\\\":
        foundLineBreak = true
    check foundLineBreak

  test "math delimiters \\[ \\] \\( \\) in math":
    let tokens = collectTokens("$\\[$")
    check tokens[1] == (gtBuiltin, "\\[")

  test "single dollar inside display math is not closing":
    let tokens = collectTokens("$$a$b$$")
    # $ inside $$ should be gtNone, not close display math
    check tokens[0] == (gtLongStringLit, "$$")
    var foundNoneDollar = false
    for t in tokens:
      if t == (gtNone, "$"):
        foundNoneDollar = true
    check foundNoneDollar
    check tokens[^1] == (gtLongStringLit, "$$")

  test "empty display math $$$$":
    let tokens = collectTokens("$$$$")
    check tokens.len == 2
    check tokens[0] == (gtLongStringLit, "$$")
    check tokens[1] == (gtLongStringLit, "$$")

  test "unclosed inline math at EOF":
    let tokens = collectTokens("$x+y")
    check tokens[0] == (gtStringLit, "$")
    # Content is parsed but no closing $
    check tokens.len >= 2
    for t in tokens:
      check t[0] != gtEof

  test "unclosed display math at EOF":
    let tokens = collectTokens("$$x+y")
    check tokens[0] == (gtLongStringLit, "$$")
    check tokens.len >= 2
    for t in tokens:
      check t[0] != gtEof

suite "Markdown - math mode does not interfere with other elements":
  test "dollar inside code block is not math":
    let tokens = collectTokens("```\n$100\n```")
    var hasMathDelim = false
    for t in tokens:
      if t == (gtStringLit, "$"):
        hasMathDelim = true
    check not hasMathDelim

  test "dollar inside inline code is not math":
    let tokens = collectTokens("`$x$`")
    check tokens.len == 1
    check tokens[0][0] == gtSpecialVar

  test "markdown heading after math":
    let tokens = collectTokens("$x$\n# Heading")
    check tokens[^1][0] == gtBuiltin # heading

  test "list after display math":
    let tokens = collectTokens("$$x$$\n- item")
    var foundListMarker = false
    for t in tokens:
      if t[0] == gtOperator and t[1] == "- ":
        foundListMarker = true
    check foundListMarker

  test "bold after inline math":
    let tokens = collectTokens("$x$ **bold**")
    var foundKeyword = false
    for t in tokens:
      if t[0] == gtKeyword and t[1] == "**bold**":
        foundKeyword = true
    check foundKeyword

suite "Markdown - indented code blocks":
  test "4-space indented code block":
    let tokens = collectTokens("    code line")
    # Whitespace followed by code content
    var foundCode = false
    for t in tokens:
      if t[0] == gtLongStringLit and t[1] == "code line":
        foundCode = true
    check foundCode

  test "tab indented code block":
    let tokens = collectTokens("\tcode line")
    var foundCode = false
    for t in tokens:
      if t[0] == gtLongStringLit and t[1] == "code line":
        foundCode = true
    check foundCode

  test "less than 4 spaces is not code":
    let tokens = collectTokens("   not code")
    var foundCode = false
    for t in tokens:
      if t[0] == gtLongStringLit:
        foundCode = true
    check not foundCode

  test "indented code block after normal text":
    let tokens = collectTokens("Hello\n    code here\nWorld")
    var foundCode = false
    for t in tokens:
      if t[0] == gtLongStringLit and t[1] == "code here":
        foundCode = true
    check foundCode
    # "World" should be normal text
    check tokens[^1] == (gtIdentifier, "World")

  test "multiple indented code lines":
    let tokens = collectTokens("    line1\n    line2")
    var codeCount = 0
    for t in tokens:
      if t[0] == gtLongStringLit:
        inc codeCount
    check codeCount == 2

  test "indented code does not trigger inside fenced code block":
    let tokens = collectTokens("```\n    indented\n```")
    # The "    indented" should be gtLongStringLit from the fenced code block handler,
    # not from the indented code detection
    var hasSpecialVar = false
    for t in tokens:
      if t[0] == gtSpecialVar:
        hasSpecialVar = true
    check hasSpecialVar
