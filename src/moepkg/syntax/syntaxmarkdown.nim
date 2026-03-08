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

import tokenizer, syntaxlatex

template isLineStart(lexer: GeneralTokenizer): bool =
  lexer.state in {gtWhitespace, low(TokenClass)}

proc endLine(lexer: GeneralTokenizer, position: int): int =
  result = position
  while lexer.buf[result] notin eolChars:
    inc result

proc mathNextToken(lexer: var GeneralTokenizer, position: var int, doubleClose: bool) =
  ## Parse a single token inside math mode.
  ## doubleClose distinguishes $$...$$ from $...$.
  const symCharsLocal = {'A' .. 'Z', 'a' .. 'z'}

  case lexer.buf[position]
  of '\0':
    lexer.kind = gtEof
  of ' ', '\t' .. '\r':
    lexer.kind = gtWhitespace
    while lexer.buf[position] in wsChars:
      inc position
  of '$':
    if doubleClose:
      if lexer.buf[position + 1] == '$':
        # Closing $$
        lexer.kind = gtLongStringLit
        inc position, 2
        lexer.mdInDisplayMath = false
      else:
        # Single $ inside display math is just content
        lexer.kind = gtNone
        inc position
    else:
      # Closing $
      lexer.kind = gtStringLit
      inc position
      lexer.mdInMathMode = false
  of '\\':
    inc position
    case lexer.buf[position]
    of '\0':
      lexer.kind = gtBuiltin
    of '\\':
      inc position
      lexer.kind = gtBuiltin
    of '[', ']', '(', ')':
      inc position
      lexer.kind = gtBuiltin
    of '%', '$', '&', '#', '_', '~', '^', '{', '}':
      inc position
      lexer.kind = gtEscapeSequence
    of 'A' .. 'Z', 'a' .. 'z':
      var id = ""
      while lexer.buf[position] in symCharsLocal:
        id.add lexer.buf[position]
        inc position
      if isKeyword(latexKeywords, id) >= 0:
        lexer.kind = gtKeyword
      else:
        lexer.kind = gtBuiltin
    else:
      inc position
      lexer.kind = gtBuiltin
  of '{', '}', '[', ']':
    lexer.kind = gtPunctuation
    inc position
  of '&', '~', '^', '_', '#':
    lexer.kind = gtOperator
    inc position
  of '0' .. '9':
    position = generalNumber(lexer, position)
  else:
    lexer.kind = gtNone
    while lexer.buf[position] notin {
      '\0',
      '\n',
      '\r',
      '$',
      '\\',
      '{',
      '}',
      '[',
      ']',
      '&',
      '~',
      '^',
      '_',
      '#',
      '0' .. '9',
      ' ',
      '\t' .. '\r',
    }
    :
      inc position

proc markdownNextToken*(lexer: var GeneralTokenizer) =
  ## The lexing logic for Markdown.
  var position = lexer.pos
  lexer.start = lexer.pos

  # Inside display math mode ($$...$$)
  if lexer.mdInDisplayMath:
    lexer.mathNextToken(position, doubleClose = true)

    lexer.length = position - lexer.pos
    if lexer.kind != gtEof and lexer.length <= 0:
      assert false, "markdownNextToken: produced an empty token (display math)"
    lexer.pos = position
    return

  # Inside inline math mode ($...$)
  if lexer.mdInMathMode:
    lexer.mathNextToken(position, doubleClose = false)

    lexer.length = position - lexer.pos
    if lexer.kind != gtEof and lexer.length <= 0:
      assert false, "markdownNextToken: produced an empty token (inline math)"
    lexer.pos = position
    return

  # Inside a code block: handle language name, content lines, and closing ```
  if lexer.mdInCodeBlock:
    case lexer.buf[position]
    of '\0':
      lexer.kind = gtEof
    of ' ', '\t' .. '\r':
      lexer.kind = gtWhitespace
      while lexer.buf[position] in wsChars:
        if lexer.buf[position] == '\n':
          lexer.state = gtWhitespace
        else:
          lexer.state = gtNone
        inc position
    of '`':
      if lexer.buf[position + 1] == '`' and lexer.buf[position + 2] == '`':
        # Closing ```
        lexer.kind = gtSpecialVar
        inc position, 3
        while lexer.buf[position] notin eolChars:
          inc position
        lexer.mdInCodeBlock = false
      else:
        # Regular content
        lexer.kind = gtLongStringLit
        while lexer.buf[position] notin eolChars:
          inc position
    else:
      # Check if this is the language name (right after opening ```)
      if lexer.state == gtSpecialVar:
        # Language name on the same line as opening ```
        lexer.kind = gtKeyword
        while lexer.buf[position] notin eolChars:
          inc position
      else:
        # Code block content
        lexer.kind = gtLongStringLit
        while lexer.buf[position] notin eolChars:
          inc position

    lexer.length = position - lexer.pos
    if lexer.kind != gtEof and lexer.length <= 0:
      assert false, "markdownNextToken: produced an empty token (code block)"
    lexer.pos = position
    return

  # Normal markdown parsing
  case lexer.buf[position]
  of '\0':
    lexer.kind = gtEof
  of '`':
    if lexer.buf[position + 1] == '`' and lexer.buf[position + 2] == '`':
      # Opening ``` - emit just the backticks
      lexer.kind = gtSpecialVar
      inc position, 3
      lexer.mdInCodeBlock = true
      # state = gtSpecialVar signals that lang name may follow
      lexer.state = gtSpecialVar
      # If there's content on this line, it will be lexed as lang name on next call
      # If we're at EOL, state will be reset by whitespace handler
    else:
      # Inline code `...`
      lexer.kind = gtSpecialVar
      inc position
      while true:
        case lexer.buf[position]
        of '\0':
          break
        of '`':
          inc position
          break
        else:
          inc position
  of '#':
    if lexer.isLineStart:
      lexer.kind = gtBuiltin
      lexer.state = gtBuiltin
      position = lexer.endLine(position)
    else:
      lexer.kind = gtPunctuation
      inc position
  of '-':
    if lexer.isLineStart:
      if lexer.buf[position + 1] == '-' and lexer.buf[position + 2] == '-':
        inc position, 3
        if lexer.buf[position] != '-':
          # Frontmatter ---...---
          lexer.kind = gtPreprocessor
          while true:
            case lexer.buf[position]
            of '\0':
              break
            of '-':
              inc position
              if lexer.buf[position] == '-':
                inc position
                if lexer.buf[position] == '-':
                  inc position
                  break
            else:
              inc position
        else:
          lexer.kind = gtBuiltin
          while lexer.buf[position] == '-':
            inc position
      elif lexer.buf[position + 1] == ' ':
        # `- ` list marker
        lexer.kind = gtOperator
        inc position, 2
      else:
        lexer.kind = gtBuiltin
        inc position
        if lexer.buf[position] == '-':
          inc position
    else:
      lexer.kind = gtNone
      inc position
  of '<':
    if lexer.buf[position + 1] == '!':
      inc position, 2
      if lexer.buf[position] == '-':
        inc position
        if lexer.buf[position] == '-':
          inc position
          lexer.kind = gtLongComment
          while true:
            case lexer.buf[position]
            of '\0':
              break
            of '-':
              inc position
              if lexer.buf[position] == '-':
                while lexer.buf[position] == '-':
                  inc position
                if lexer.buf[position] == '>':
                  inc position
                  break
            else:
              inc position
        else:
          lexer.kind = gtBuiltin
      else:
        lexer.kind = gtBuiltin
    else:
      lexer.kind = gtBuiltin
      inc position
  of '*':
    if lexer.isLineStart and lexer.buf[position + 1] == ' ':
      # `* ` list marker
      lexer.kind = gtOperator
      inc position, 2
    elif lexer.buf[position + 1] == '*' and
        lexer.buf[position + 2] notin {' ', '\t', '\0', '\n', '\r'}:
      # **bold** - opening ** must be followed by non-whitespace
      lexer.kind = gtKeyword
      inc position, 2
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of '*':
          if lexer.buf[position + 1] == '*':
            inc position, 2
            break
          else:
            inc position
        else:
          inc position
    elif lexer.buf[position + 1] notin {' ', '\t', '\0', '\n', '\r', '*'}:
      # *italic* - opening * must be followed by non-whitespace, non-asterisk
      lexer.kind = gtStringLit
      inc position
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of '*':
          inc position
          break
        else:
          inc position
    else:
      lexer.kind = gtNone
      inc position
  of '_':
    if lexer.buf[position + 1] == '_' and
        lexer.buf[position + 2] notin {' ', '\t', '\0', '\n', '\r'}:
      # __bold__ - opening __ must be followed by non-whitespace
      lexer.kind = gtKeyword
      inc position, 2
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of '_':
          if lexer.buf[position + 1] == '_':
            inc position, 2
            break
          else:
            inc position
        else:
          inc position
    elif lexer.buf[position + 1] notin {' ', '\t', '\0', '\n', '\r', '_'}:
      # _italic_ - opening _ must be followed by non-whitespace, non-underscore
      lexer.kind = gtStringLit
      inc position
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of '_':
          inc position
          break
        else:
          inc position
    else:
      lexer.kind = gtIdentifier
      lexer.state = gtIdentifier
      inc position
      while lexer.buf[position] in symChars:
        inc position
  of '~':
    if lexer.buf[position + 1] == '~':
      # ~~strikethrough~~
      lexer.kind = gtComment
      inc position, 2
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of '~':
          if lexer.buf[position + 1] == '~':
            inc position, 2
            break
          else:
            inc position
        else:
          inc position
    else:
      lexer.kind = gtNone
      inc position
  of '>':
    if lexer.isLineStart:
      # Block quote
      lexer.kind = gtComment
      position = lexer.endLine(position)
    else:
      lexer.kind = gtNone
      inc position
  of '!':
    if lexer.buf[position + 1] == '[':
      # ![alt](url) - image alt text
      lexer.kind = gtKeyword
      inc position, 2
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of ']':
          inc position
          break
        else:
          inc position
    else:
      lexer.kind = gtNone
      inc position
  of '[':
    # Check if this is a link [text](url)
    var lookAhead = position + 1
    var foundClose = false
    while lexer.buf[lookAhead] notin {'\0', '\n', '\r'}:
      if lexer.buf[lookAhead] == ']':
        foundClose = true
        break
      inc lookAhead

    if foundClose and lexer.buf[lookAhead + 1] == '(':
      # Link text
      lexer.kind = gtKeyword
      inc position
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of ']':
          inc position
          break
        else:
          inc position
    else:
      lexer.kind = gtPunctuation
      inc position
  of '(':
    # Check if this follows ] (link URL part)
    if lexer.start > 0 and lexer.buf[lexer.start - 1] == ']':
      lexer.kind = gtSpecialVar
      inc position
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of ')':
          inc position
          break
        else:
          inc position
    else:
      lexer.kind = gtPunctuation
      inc position
  of '+':
    if lexer.isLineStart and lexer.buf[position + 1] == ' ':
      # `+ ` list marker
      lexer.kind = gtOperator
      inc position, 2
    else:
      lexer.kind = gtNone
      inc position
  of '0' .. '9':
    if lexer.isLineStart:
      var numEnd = position
      while lexer.buf[numEnd] in {'0' .. '9'}:
        inc numEnd
      if lexer.buf[numEnd] == '.' and lexer.buf[numEnd + 1] == ' ':
        # Ordered list marker: `1. `
        lexer.kind = gtOperator
        position = numEnd + 2
      else:
        lexer.kind = gtNone
        inc position
    else:
      lexer.kind = gtNone
      inc position
  of 'a' .. 'z', 'A' .. 'Z', '\x80' .. '\xFF':
    lexer.kind = gtIdentifier
    lexer.state = gtIdentifier
    while lexer.buf[position] in symChars:
      inc position
  of ' ', '\t' .. '\r':
    lexer.kind = gtWhitespace
    while lexer.buf[position] in wsChars:
      if lexer.buf[position] == '\n':
        lexer.state = gtWhitespace
      else:
        lexer.state = gtNone
      inc position
  of '$':
    if lexer.buf[position + 1] == '$':
      # Opening $$ - emit just the delimiter
      lexer.kind = gtLongStringLit
      inc position, 2
      lexer.mdInDisplayMath = true
    else:
      # Opening $ - emit just the delimiter
      lexer.kind = gtStringLit
      inc position
      lexer.mdInMathMode = true
  of ')', ']', '{', '}', ':', ',', ';', '.', '/', '\'', '\"':
    lexer.kind = gtPunctuation
    inc position
  else:
    lexer.kind = gtNone
    inc position

  if lexer.kind notin {gtWhitespace, gtEof}:
    # Update state for non-whitespace tokens so that isLineStart works correctly.
    # Without this, tokens like punctuation (`"`, `)`, etc.) leave state unchanged,
    # causing a subsequent `-` to be incorrectly treated as a line-start list marker.
    lexer.state = lexer.kind

  lexer.length = position - lexer.pos

  if lexer.kind != gtEof and lexer.length <= 0:
    assert false, "markdownNextToken: produced an empty token"

  lexer.pos = position
