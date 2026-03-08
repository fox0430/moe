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
import ../src/moepkg/syntax/syntaxlatex

proc collectTokens(code: string): seq[(TokenClass, string)] =
  var g: GeneralTokenizer
  g.initGeneralTokenizer(code)
  while true:
    g.latexNextToken()
    if g.kind == gtEof:
      break
    let text = code[g.start ..< g.start + g.length]
    result.add (g.kind, text)

suite "syntaxlatex - latexKeywords constant":
  test "latexKeywords contains structural commands":
    check "documentclass" in latexKeywords
    check "usepackage" in latexKeywords
    check "begin" in latexKeywords
    check "end" in latexKeywords
    check "section" in latexKeywords
    check "subsection" in latexKeywords
    check "chapter" in latexKeywords

  test "latexKeywords contains text formatting commands":
    check "textbf" in latexKeywords
    check "textit" in latexKeywords
    check "texttt" in latexKeywords
    check "emph" in latexKeywords
    check "underline" in latexKeywords

  test "latexKeywords contains reference commands":
    check "label" in latexKeywords
    check "ref" in latexKeywords
    check "cite" in latexKeywords
    check "pageref" in latexKeywords
    check "url" in latexKeywords
    check "href" in latexKeywords

suite "syntaxlatex - comments":
  test "line comment":
    let tokens = collectTokens("% this is a comment")
    check tokens.len == 1
    check tokens[0] == (gtComment, "% this is a comment")

  test "comment after text":
    let tokens = collectTokens("hello % comment")
    check tokens[0] == (gtIdentifier, "hello")
    # whitespace
    check tokens[2] == (gtComment, "% comment")

suite "syntaxlatex - commands":
  test "keyword command":
    let tokens = collectTokens("\\section")
    check tokens.len == 1
    check tokens[0] == (gtKeyword, "\\section")

  test "non-keyword command":
    let tokens = collectTokens("\\foo")
    check tokens.len == 1
    check tokens[0] == (gtBuiltin, "\\foo")

  test "begin command":
    let tokens = collectTokens("\\begin")
    check tokens.len == 1
    check tokens[0] == (gtKeyword, "\\begin")

  test "documentclass command":
    let tokens = collectTokens("\\documentclass")
    check tokens.len == 1
    check tokens[0] == (gtKeyword, "\\documentclass")

suite "syntaxlatex - escape sequences":
  test "escaped percent":
    let tokens = collectTokens("\\%")
    check tokens.len == 1
    check tokens[0] == (gtEscapeSequence, "\\%")

  test "escaped dollar":
    let tokens = collectTokens("\\$")
    check tokens.len == 1
    check tokens[0] == (gtEscapeSequence, "\\$")

  test "escaped ampersand":
    let tokens = collectTokens("\\&")
    check tokens.len == 1
    check tokens[0] == (gtEscapeSequence, "\\&")

  test "escaped hash":
    let tokens = collectTokens("\\#")
    check tokens.len == 1
    check tokens[0] == (gtEscapeSequence, "\\#")

  test "escaped underscore":
    let tokens = collectTokens("\\_")
    check tokens.len == 1
    check tokens[0] == (gtEscapeSequence, "\\_")

  test "escaped braces":
    let tokens = collectTokens("\\{\\}")
    check tokens.len == 2
    check tokens[0] == (gtEscapeSequence, "\\{")
    check tokens[1] == (gtEscapeSequence, "\\}")

suite "syntaxlatex - inline math mode":
  test "inline math on single line":
    let tokens = collectTokens("$x+y$")
    check tokens.len == 1
    check tokens[0] == (gtStringLit, "$x+y$")

  test "inline math with surrounding text":
    let tokens = collectTokens("the formula $E=mc^2$ is famous")
    # "the" identifier, space, "formula" identifier, space, "$E=mc^2$", space, ...
    var foundMath = false
    for t in tokens:
      if t[0] == gtStringLit and t[1] == "$E=mc^2$":
        foundMath = true
    check foundMath

suite "syntaxlatex - display math mode":
  test "display math on single line":
    let tokens = collectTokens("$$E=mc^2$$")
    check tokens.len == 1
    check tokens[0] == (gtLongStringLit, "$$E=mc^2$$")

suite "syntaxlatex - brackets and punctuation":
  test "curly braces":
    let tokens = collectTokens("{}")
    check tokens.len == 2
    check tokens[0] == (gtPunctuation, "{")
    check tokens[1] == (gtPunctuation, "}")

  test "square brackets":
    let tokens = collectTokens("[]")
    check tokens.len == 2
    check tokens[0] == (gtPunctuation, "[")
    check tokens[1] == (gtPunctuation, "]")

suite "syntaxlatex - special characters":
  test "ampersand":
    let tokens = collectTokens("&")
    check tokens.len == 1
    check tokens[0] == (gtOperator, "&")

  test "tilde":
    let tokens = collectTokens("~")
    check tokens.len == 1
    check tokens[0] == (gtOperator, "~")

  test "caret":
    let tokens = collectTokens("^")
    check tokens.len == 1
    check tokens[0] == (gtOperator, "^")

  test "underscore":
    let tokens = collectTokens("_")
    check tokens.len == 1
    check tokens[0] == (gtOperator, "_")

  test "hash":
    let tokens = collectTokens("#")
    check tokens.len == 1
    check tokens[0] == (gtOperator, "#")

suite "syntaxlatex - numbers":
  test "integer":
    let tokens = collectTokens("42")
    check tokens.len == 1
    check tokens[0] == (gtDecNumber, "42")

  test "float":
    let tokens = collectTokens("3.14")
    check tokens.len == 1
    check tokens[0] == (gtFloatNumber, "3.14")

suite "syntaxlatex - line break and math delimiters":
  test "double backslash":
    let tokens = collectTokens("\\\\")
    check tokens.len == 1
    check tokens[0] == (gtBuiltin, "\\\\")

  test "backslash bracket":
    let tokens = collectTokens("\\[")
    check tokens.len == 1
    check tokens[0] == (gtBuiltin, "\\[")

  test "backslash paren":
    let tokens = collectTokens("\\(")
    check tokens.len == 1
    check tokens[0] == (gtBuiltin, "\\(")

suite "syntaxlatex - multi-line math mode":
  test "inline math across lines":
    let tokens = collectTokens("$x+\ny$")
    # Should start math mode, then continue on next line
    var hasStringLit = false
    for t in tokens:
      if t[0] == gtStringLit:
        hasStringLit = true
    check hasStringLit

  test "display math across lines":
    let tokens = collectTokens("$$E=\nmc^2$$")
    var hasLongStringLit = false
    for t in tokens:
      if t[0] == gtLongStringLit:
        hasLongStringLit = true
    check hasLongStringLit

suite "syntaxlatex - complete document":
  test "simple LaTeX document":
    let code =
      "\\documentclass{article}\n\\usepackage{amsmath}\n\\begin{document}\nHello $x$ world\n\\end{document}"
    let tokens = collectTokens(code)
    # Should parse without errors and produce tokens
    check tokens.len > 0
    # First token should be \documentclass (keyword)
    check tokens[0] == (gtKeyword, "\\documentclass")
