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

import tokenizer

const latexKeywords* = [
  "author", "begin", "caption", "chapter", "cite", "date", "def", "documentclass",
  "emph", "end", "frac", "href", "include", "input", "item", "label", "left", "let",
  "maketitle", "newcommand", "pageref", "paragraph", "part", "ref", "renewcommand",
  "right", "section", "sqrt", "subparagraph", "subsection", "subsubsection", "textbf",
  "textit", "texttt", "title", "underline", "url", "usepackage",
]

proc latexNextToken*(g: var GeneralTokenizer) =
  const symCharsLocal = {'A' .. 'Z', 'a' .. 'z'}

  var pos = g.pos
  g.start = g.pos

  # Handle continued display math mode ($$...$$)
  if g.latexInDisplayMath:
    case g.buf[pos]
    of '\0':
      g.kind = gtEof
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc pos
    of '$':
      if g.buf[pos + 1] == '$':
        # Closing $$
        g.kind = gtLongStringLit
        inc pos, 2
        g.latexInDisplayMath = false
      else:
        g.kind = gtLongStringLit
        inc pos
    else:
      g.kind = gtLongStringLit
      while g.buf[pos] notin {'\0', '\n', '\r', '$'}:
        inc pos

    g.length = pos - g.pos
    if g.kind != gtEof and g.length <= 0:
      assert false, "latexNextToken: produced an empty token (display math)"
    g.pos = pos
    return

  # Handle continued inline math mode ($...$)
  if g.latexInMathMode:
    case g.buf[pos]
    of '\0':
      g.kind = gtEof
    of ' ', '\t' .. '\r':
      g.kind = gtWhitespace
      while g.buf[pos] in {' ', '\t' .. '\r'}:
        inc pos
    of '$':
      # Closing $
      g.kind = gtStringLit
      inc pos
      g.latexInMathMode = false
    else:
      g.kind = gtStringLit
      while g.buf[pos] notin {'\0', '\n', '\r', '$'}:
        inc pos

    g.length = pos - g.pos
    if g.kind != gtEof and g.length <= 0:
      assert false, "latexNextToken: produced an empty token (inline math)"
    g.pos = pos
    return

  # Normal mode parsing
  case g.buf[pos]
  of '\0':
    g.kind = gtEof
  of ' ', '\t' .. '\r':
    g.kind = gtWhitespace
    while g.buf[pos] in {' ', '\t' .. '\r'}:
      inc pos
  of '%':
    # Comment: % to end of line
    g.kind = gtComment
    while g.buf[pos] notin {'\0', '\n', '\r'}:
      inc pos
  of '\\':
    # Backslash command
    inc pos
    case g.buf[pos]
    of '\0':
      g.kind = gtBuiltin
    of '\\':
      # \\ line break
      inc pos
      g.kind = gtBuiltin
    of '[', ']', '(', ')':
      # \[, \], \(, \) - math delimiters
      inc pos
      g.kind = gtBuiltin
    of '%', '$', '&', '#', '_', '~', '^', '{', '}':
      # Escaped special characters
      inc pos
      g.kind = gtEscapeSequence
    of 'A' .. 'Z', 'a' .. 'z':
      # Command name: \commandname
      var id = ""
      while g.buf[pos] in symCharsLocal:
        id.add g.buf[pos]
        inc pos
      if isKeyword(latexKeywords, id) >= 0:
        g.kind = gtKeyword
      else:
        g.kind = gtBuiltin
    else:
      # Unknown escape: treat as builtin
      inc pos
      g.kind = gtBuiltin
  of '$':
    if g.buf[pos + 1] == '$':
      # Display math mode: $$...$$
      g.kind = gtLongStringLit
      inc pos, 2
      g.latexInDisplayMath = true
      # Consume content until $$ or end of line
      while g.buf[pos] notin {'\0', '\n', '\r', '$'}:
        inc pos
      # Check for closing $$ on same line
      if g.buf[pos] == '$' and g.buf[pos + 1] == '$':
        inc pos, 2
        g.latexInDisplayMath = false
    else:
      # Inline math mode: $...$
      g.kind = gtStringLit
      inc pos
      g.latexInMathMode = true
      # Consume content until $ or end of line
      while g.buf[pos] notin {'\0', '\n', '\r', '$'}:
        inc pos
      # Check for closing $ on same line
      if g.buf[pos] == '$':
        inc pos
        g.latexInMathMode = false
  of '{', '}', '[', ']':
    g.kind = gtPunctuation
    inc pos
  of '&', '~', '^', '_', '#':
    g.kind = gtOperator
    inc pos
  of '0' .. '9':
    pos = generalNumber(g, pos)
  of 'A' .. 'Z', 'a' .. 'z', '\x80' .. '\xFF':
    g.kind = gtIdentifier
    while g.buf[pos] in {'A' .. 'Z', 'a' .. 'z', '0' .. '9', '_', '\x80' .. '\xFF'}:
      inc pos
  else:
    g.kind = gtNone
    inc pos

  g.length = pos - g.pos
  if g.kind != gtEof and g.length <= 0:
    assert false, "latexNextToken: produced an empty token"
  g.pos = pos
