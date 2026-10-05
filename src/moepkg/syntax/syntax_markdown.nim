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

import tokenizer, syntax_latex

const SubLanguageCarryStates =
  {gtDocLongComment, gtLongStringLit, gtLongComment, gtStringLit, gtCData}
  ## Sub-language states whose token continues, so whitespace belongs to it
  ## rather than to Markdown.

proc skipBlanks(lexer: GeneralTokenizer, p, col: var int) =
  ## Advance `p` past spaces and tabs, moving `col` along with tab stops of 4.
  while true:
    case lexer.buf[p]
    of ' ':
      inc col
    of '\t':
      col = (col div 4 + 1) * 4
    else:
      break
    inc p

proc fenceBaseCol(lexer: GeneralTokenizer, pos: int): int =
  ## The column a fence at `pos` measures its closing fence's indent from, -1
  ## when the text before it on its line keeps it from opening a block. Only
  ## blanks and list markers may come before it: blanks alone put it at most
  ## 3 columns in and count from its own column, a list marker counts from the
  ## item's content.
  var lineStart = pos
  while lineStart > 0 and
      lexer.buf[lineStart - 1] in {' ', '\t', '-', '*', '+', '.', ')', '0' .. '9'}:
    dec lineStart
  if lineStart > 0 and lexer.buf[lineStart - 1] != '\n':
    return -1
  var
    p = lineStart
    col = 0
  lexer.skipBlanks(p, col)
  if p == pos:
    # It may be on a list item's continuation line, whose content column is
    # not tracked; the fence's own column stands in for it.
    return if col <= 3: col else: -1
  while p < pos:
    # A list marker, then 1 to 4 columns of blanks; more makes the fence
    # indented code in the item.
    let markerStart = p
    if lexer.buf[p] in {'-', '*', '+'}:
      inc p
    else:
      while lexer.buf[p] in {'0' .. '9'}:
        inc p
      if p == markerStart or lexer.buf[p] notin {'.', ')'}:
        return -1
      inc p
    col += p - markerStart
    let markerEnd = col
    lexer.skipBlanks(p, col)
    if col - markerEnd notin 1 .. 4:
      return -1
  col

proc openingFence(lexer: GeneralTokenizer, pos: int): tuple[len, baseCol: int] =
  ## The fence run at `pos` when it opens a code block, `len` 0 otherwise. A
  ## backtick fence's info string cannot contain a backtick.
  let fenceChar = lexer.buf[pos]
  var p = pos
  while lexer.buf[p] == fenceChar:
    inc p
  if p - pos < 3:
    return
  if fenceChar == '`':
    var q = p
    while lexer.buf[q] notin eolChars:
      if lexer.buf[q] == '`':
        return
      inc q
  let baseCol = lexer.fenceBaseCol(pos)
  if baseCol >= 0:
    result = (p - pos, baseCol)

proc isClosingFence(lexer: GeneralTokenizer, lineStart: int): bool =
  ## Whether the line at `lineStart` closes the open code block: blanks up to
  ## 3 columns past the block's base column, a run of the opening fence char
  ## at least as long, then blanks.
  let md = lexer.lang.markdown
  if md.fenceChar notin {'`', '~'}:
    return false
  var
    p = lineStart
    col = 0
  lexer.skipBlanks(p, col)
  if col > md.fenceBaseCol + 3:
    return false
  let runStart = p
  while lexer.buf[p] == md.fenceChar:
    inc p
  if p - runStart < md.fenceLen:
    return false
  while lexer.buf[p] in lwsChars:
    inc p
  lexer.buf[p] in eolChars

proc atClosingFence(lexer: GeneralTokenizer, pos: int): bool =
  ## Whether `pos` is in the indent of, or at the fence of, a closing fence
  ## line.
  let maxIndent = lexer.lang.markdown.fenceBaseCol + 3
  var lineStart = pos
  while lineStart > 0 and lexer.buf[lineStart - 1] in {' ', '\t'}:
    if pos - lineStart == maxIndent:
      return false
    dec lineStart
  (lineStart == 0 or lexer.buf[lineStart - 1] == '\n') and
    lexer.isClosingFence(lineStart)

proc codeBlockDelegate*(lexer: GeneralTokenizer): SourceLanguage =
  ## Language that lexes the next token: the code block's language for its
  ## body, `langNone` where Markdown lexes it (fences, language name,
  ## whitespace between tokens).
  let md = lexer.lang.markdown
  # These modes come first in `markdownNextToken`.
  if md.inDisplayMath or md.inMathMode or lexer.mdInIndentedCode:
    return langNone
  if not md.inCodeBlock or md.codeBlockLang == langNone:
    return langNone

  # The closing fence ends the block whatever its body left open; checked
  # last, only where the block's language would otherwise get the token.
  case lexer.buf[lexer.pos]
  of '\0':
    langNone
  of ' ', '\t' .. '\r':
    if lexer.state in SubLanguageCarryStates and not lexer.atClosingFence(lexer.pos):
      md.codeBlockLang
    else:
      langNone
  else:
    # gtSpecialVar: the language name after the opening fence.
    if lexer.state == gtSpecialVar or lexer.atClosingFence(lexer.pos):
      langNone
    else:
      md.codeBlockLang

proc boundCodeBlock(lexer: var GeneralTokenizer) =
  ## Find the span of the block `pos` is in, copying it when its closing
  ## fence comes before the end of the buffer.
  if lexer.pos >= lexer.mdBlockBase and lexer.pos < lexer.mdBlockEnd:
    return
  var base = lexer.pos
  while base > 0 and lexer.buf[base - 1] != '\n':
    dec base
  var blockEnd = lexer.pos
  while lexer.buf[blockEnd] != '\0':
    if lexer.buf[blockEnd] == '\n' and lexer.isClosingFence(blockEnd + 1):
      inc blockEnd
      break
    inc blockEnd
  lexer.mdBlockBase = base
  lexer.mdBlockEnd = blockEnd
  if lexer.buf[blockEnd] == '\0':
    lexer.mdBlockText = nil
  else:
    lexer.mdBlockText = new string
    lexer.mdBlockText[] = newString(blockEnd - base)
    copyMem(addr lexer.mdBlockText[][0], addr lexer.buf[base], blockEnd - base)

template lexCodeBlockBody*(lexer: var GeneralTokenizer, lexToken: untyped) =
  ## Run `lexToken`, the block language's lexer, on the block alone: a token
  ## the body leaves open (a raw string, a docstring) ends at the closing
  ## fence line instead of running past it.
  lexer.boundCodeBlock()
  if lexer.mdBlockText.isNil:
    lexToken
  else:
    let
      wholeBuf = lexer.buf
      base = lexer.mdBlockBase
    lexer.buf = lexer.mdBlockText[].cstring
    lexer.pos -= base
    lexToken
    lexer.buf = wholeBuf
    lexer.pos += base
    lexer.start += base

proc openCodeBlock(
    lexer: var GeneralTokenizer, position: var int, fence: tuple[len, baseCol: int]
) =
  lexer.kind = gtSpecialVar
  lexer.lang.markdown.inCodeBlock = true
  lexer.lang.markdown.fenceChar = lexer.buf[position]
  lexer.lang.markdown.fenceLen = fence.len
  lexer.lang.markdown.fenceBaseCol = fence.baseCol
  # Signals that the language name may follow.
  lexer.state = gtSpecialVar
  inc position, fence.len

proc closeCodeBlock(lexer: var GeneralTokenizer) =
  ## Also drops the block language's state: the body may have left a
  ## construct open, and the next block must not inherit it.
  var md = lexer.lang.markdown
  md.inCodeBlock = false
  md.codeBlockLang = langNone
  md.fenceChar = '\0'
  md.fenceLen = 0
  md.fenceBaseCol = 0
  lexer.lang = defaultLangState()
  lexer.lang.markdown = md
  lexer.state = gtNone
  lexer.mdBlockBase = 0
  lexer.mdBlockEnd = 0
  lexer.mdBlockText = nil

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
        lexer.lang.markdown.inDisplayMath = false
      else:
        # Single $ inside display math is just content
        lexer.kind = gtNone
        inc position
    else:
      # Closing $
      lexer.kind = gtStringLit
      inc position
      lexer.lang.markdown.inMathMode = false
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
  if lexer.lang.markdown.inDisplayMath:
    lexer.mathNextToken(position, doubleClose = true)

    lexer.length = position - lexer.pos
    if lexer.kind != gtEof and lexer.length <= 0:
      assert false, "markdownNextToken: produced an empty token (display math)"
    lexer.pos = position
    return

  # Inside inline math mode ($...$)
  if lexer.lang.markdown.inMathMode:
    lexer.mathNextToken(position, doubleClose = false)

    lexer.length = position - lexer.pos
    if lexer.kind != gtEof and lexer.length <= 0:
      assert false, "markdownNextToken: produced an empty token (inline math)"
    lexer.pos = position
    return

  # Inside an indented code block (4+ spaces at line start)
  if lexer.mdInIndentedCode:
    case lexer.buf[position]
    of '\0':
      lexer.kind = gtEof
      lexer.mdInIndentedCode = false
    else:
      lexer.kind = gtLongStringLit
      while lexer.buf[position] notin eolChars:
        inc position
      lexer.mdInIndentedCode = false

    lexer.length = position - lexer.pos
    if lexer.kind != gtEof and lexer.length <= 0:
      assert false, "markdownNextToken: produced an empty token (indented code)"
    lexer.pos = position
    return

  # Inside a code block: handle language name, content lines, and closing ```.
  # A labelled block's body is lexed by its own language (`codeBlockDelegate`).
  if lexer.lang.markdown.inCodeBlock:
    case lexer.buf[position]
    of '\0':
      lexer.kind = gtEof
    of ' ', '\t' .. '\r':
      lexer.kind = gtWhitespace
      while lexer.buf[position] in wsChars:
        if lexer.buf[position] == '\n':
          lexer.state = gtWhitespace
        elif lexer.state != gtSpecialVar:
          lexer.state = gtNone
        inc position
    else:
      # Check if this is the language name (right after opening ```)
      if lexer.state == gtSpecialVar:
        lexer.kind = gtKeyword
        var langName = ""
        while lexer.buf[position] notin wsChars and lexer.buf[position] notin eolChars:
          langName.add lexer.buf[position]
          inc position
        let lang = getSourceLanguage(langName)
        lexer.lang.markdown.codeBlockLang = if lang == langMarkdown: langNone else: lang
        lexer.state = gtNone
      elif lexer.atClosingFence(position):
        lexer.kind = gtSpecialVar
        position = lexer.endLine(position)
        lexer.closeCodeBlock()
      else:
        # Code block content
        lexer.kind = gtLongStringLit
        position = lexer.endLine(position)

    lexer.length = position - lexer.pos
    if lexer.kind != gtEof and lexer.length <= 0:
      assert false, "markdownNextToken: produced an empty token (code block)"
    lexer.pos = position
    return

  # Inside frontmatter (---...---): emit each line as gtPreprocessor until the
  # closing `---` line. Tracked line-by-line via `mdInFrontmatter` (rather than
  # consumed greedily in one token) so the state is captured at line boundaries
  # and incremental re-parsing can resume correctly from inside the block.
  if lexer.lang.markdown.inFrontmatter:
    case lexer.buf[position]
    of '\0':
      lexer.kind = gtEof
      lexer.lang.markdown.inFrontmatter = false
    of '\n', '\r':
      lexer.kind = gtWhitespace
      while lexer.buf[position] in {'\n', '\r'}:
        lexer.state = gtWhitespace
        inc position
    else:
      # Content line or the closing delimiter line. The closing fence mirrors
      # the opening one: exactly `---` closes the block, while a 4th `-` makes
      # it a frontmatter content line (matching the `buf[position] != '-'`
      # opening check in the `of '-'` branch, which rejects `----`).
      lexer.kind = gtPreprocessor
      if lexer.buf[position] == '-' and lexer.buf[position + 1] == '-' and
          lexer.buf[position + 2] == '-' and lexer.buf[position + 3] != '-':
        lexer.lang.markdown.inFrontmatter = false
      position = lexer.endLine(position)

    lexer.length = position - lexer.pos
    if lexer.kind != gtEof and lexer.length <= 0:
      assert false, "markdownNextToken: produced an empty token (frontmatter)"
    lexer.pos = position
    return

  # Normal markdown parsing
  case lexer.buf[position]
  of '\0':
    lexer.kind = gtEof
  of '`':
    let fence = lexer.openingFence(position)
    if fence.len > 0:
      # Emit just the fence; the language name is lexed on the next call.
      lexer.openCodeBlock(position, fence)
    elif lexer.buf[position + 1] == '`' and lexer.buf[position + 2] == '`':
      # Not a fence (mid-line, or ```abc```): inline code with a triple
      # backtick delimiter (```...```).
      lexer.kind = gtSpecialVar
      inc position, 3
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of '`':
          if lexer.buf[position + 1] == '`' and lexer.buf[position + 2] == '`':
            inc position, 3
            break
          else:
            inc position
        else:
          inc position
    else:
      # Inline code `...`. Stops at the closing backtick or the end of the
      # line: an unclosed span must not bleed into the following line. This
      # matches the triple-backtick inline case above and keeps the token
      # single-line, so incremental re-parsing from a later line stays correct.
      lexer.kind = gtSpecialVar
      inc position
      while true:
        case lexer.buf[position]
        of '\0', '\n', '\r':
          break
        of '`':
          inc position
          break
        else:
          inc position
  of '#':
    if lexer.isLineStart:
      # Emit only the leading `#` run so inline markers on the heading line
      # (`~~`, `**`, `` ` ``, ...) are still tokenized.
      lexer.kind = gtBuiltin
      lexer.state = gtBuiltin
      while lexer.buf[position] == '#':
        inc position
    else:
      lexer.kind = gtPunctuation
      inc position
  of '-':
    if lexer.isLineStart:
      if lexer.buf[position + 1] == '-' and lexer.buf[position + 2] == '-':
        inc position, 3
        if lexer.buf[position] != '-' and lexer.lang.markdown.firstLine:
          # Frontmatter start (--- on the very first line of the document).
          # YAML frontmatter is only valid at the document start; a `---` line
          # anywhere else is a thematic break (handled by the `else` below),
          # not frontmatter — otherwise every horizontal rule would flip the
          # rest of the file into preprocessor styling. Only the opening
          # delimiter line is emitted here; the `mdInFrontmatter` branch near
          # the top of this proc handles the body and the closing delimiter so
          # that the multi-line state survives incremental re-parsing.
          lexer.kind = gtPreprocessor
          lexer.lang.markdown.inFrontmatter = true
          position = lexer.endLine(position)
        else:
          # Thematic break / horizontal rule (`---`, `----`, ...).
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
      # Only treat `<` as an HTML tag / autolink opener when it looks like one:
      # `<letter...` or `</letter...`, with a matching `>` on the same line.
      # Without this check, a bare `<` (as in `a < b`) would always be
      # highlighted.
      let looksLikeTag =
        lexer.buf[position + 1] in {'a' .. 'z', 'A' .. 'Z'} or (
          lexer.buf[position + 1] == '/' and
          lexer.buf[position + 2] in {'a' .. 'z', 'A' .. 'Z'}
        )
      if looksLikeTag:
        var scan = position + 1
        var hasClose = false
        while lexer.buf[scan] notin {'\0', '\n', '\r', '<'}:
          if lexer.buf[scan] == '>':
            hasClose = true
            break
          inc scan
        if hasClose:
          lexer.kind = gtBuiltin
          inc position
        else:
          lexer.kind = gtPunctuation
          inc position
      else:
        lexer.kind = gtPunctuation
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
    let fence = lexer.openingFence(position)
    if fence.len > 0:
      lexer.openCodeBlock(position, fence)
    elif lexer.buf[position + 1] == '~':
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
    # Detect indented code block: 4+ spaces or tab at line start
    if not lexer.lang.markdown.inCodeBlock and lexer.buf[position] notin eolChars:
      # Count leading spaces/tabs after the last newline in the consumed whitespace
      var i = position - 1
      var spaceCount = 0
      while i >= lexer.start and lexer.buf[i] in {' ', '\t'}:
        if lexer.buf[i] == '\t':
          spaceCount = 4 # Tab counts as 4 spaces
          dec i
          break
        inc spaceCount
        dec i
      # Check that the indent follows a newline (or is at buffer start)
      if spaceCount >= 4 and (i < lexer.start or lexer.buf[i] == '\n'):
        lexer.mdInIndentedCode = true
  of '$':
    if lexer.buf[position + 1] == '$':
      # Opening $$ - emit just the delimiter
      lexer.kind = gtLongStringLit
      inc position, 2
      lexer.lang.markdown.inDisplayMath = true
    elif lexer.buf[position + 1] in {' ', '\t', '\n', '\r', '\0'}:
      # A `$` followed by whitespace/EOL is not a math delimiter (pandoc rule).
      lexer.kind = gtPunctuation
      inc position
    else:
      # Only enter inline math if a closing `$` exists on the same line;
      # otherwise an unclosed `$` would flip the rest of the document into
      # math styling.
      var scan = position + 1
      var hasClose = false
      while lexer.buf[scan] notin {'\0', '\n', '\r'}:
        if lexer.buf[scan] == '$':
          hasClose = true
          break
        inc scan
      if hasClose:
        lexer.kind = gtStringLit
        inc position
        lexer.lang.markdown.inMathMode = true
      else:
        lexer.kind = gtPunctuation
        inc position
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

  # After the document's first token the `---` frontmatter window has closed: any
  # later `---` is a thematic break, not frontmatter. The first call always lands
  # in this normal-parsing path (every continuation branch above returns early and
  # only runs once a multi-line state is already set), so clearing it here is enough.
  lexer.lang.markdown.firstLine = false

  lexer.length = position - lexer.pos

  if lexer.kind != gtEof and lexer.length <= 0:
    assert false, "markdownNextToken: produced an empty token"

  lexer.pos = position
