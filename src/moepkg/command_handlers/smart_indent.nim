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

## Language-aware smart indentation helpers.
##
## No buffer/state mutation. Used by Insert mode newline handlers when
## `smartIndent` is enabled. Every code language shares the bracket rules,
## read through the tokenizer from the highlighter's state; Nim adds its own.

import std/[options, strutils]
import ../syntax/[tokenizer, dispatch]
import ../highlight
import ../buffer/[core, highlight]
import ../unicode_utils

const
  NoIndentLanguages = {
    langNone, langCommitEditMsg, langDiff, langGitRebaseTodo, langGitignore, langHtml,
    langLatex, langLog, langMarkdown, langXml,
  } ## Prose, markup and line lists: brackets there are text, not structure.
  BracketTokens = {gtPunctuation, gtOperator, gtKeyword}
    ## What code brackets come out as; text, keys, strings and comments do not.
  CommentTokens = {gtComment, gtLongComment, gtDocComment, gtDocLongComment}
  LongTokens = {gtLongComment, gtDocLongComment, gtLongStringLit}
    ## Comments and strings that run over lines.
  MaxOpenerSearchLines = 1000
  MaxResumeLines = 1000
    ## How far above a line a known tokenizer state is looked for; past it,
    ## the line is read on its own.
  Openers = {'(', '[', '{'}
  Closers = {')', ']', '}'}
  NimContinuationKeywords = ["or", "and", "object", "tuple", "enum"]
  NimBlockDeclKeywords = ["var", "let", "const", "type"]

proc stripNimCodeOnly*(line: string): string =
  ## Return `line` with string literals (`"..."` / `'...'`) and backtick-
  ## quoted identifiers (`` `...` ``) replaced by spaces+`x`s, and any
  ## trailing `# ...` comment removed, so callers can do simple
  ## trailing-token checks without worrying about literals/comments.
  ##
  ## If the line contains a triple-quoted token (`"""`) we cannot determine
  ## from a single line whether we are inside or outside a long string, so
  ## we conservatively return an empty string (which disables all triggers
  ## for that line).
  if line.contains("\"\"\""):
    return ""

  result = newStringOfCap(line.len)
  var i = 0
  while i < line.len:
    let c = line[i]
    case c
    of '"':
      result.add(' ')
      inc i
      while i < line.len:
        let cc = line[i]
        if cc == '\\' and i + 1 < line.len:
          result.add('x')
          result.add('x')
          i += 2
          continue
        if cc == '"':
          result.add(' ')
          inc i
          break
        if cc == '\n':
          break
        result.add('x')
        inc i
    of '\'':
      result.add(' ')
      inc i
      while i < line.len:
        let cc = line[i]
        if cc == '\\' and i + 1 < line.len:
          result.add('x')
          result.add('x')
          i += 2
          continue
        if cc == '\'':
          result.add(' ')
          inc i
          break
        if cc == '\n':
          break
        result.add('x')
        inc i
    of '`':
      # Backtick-quoted identifier (e.g. `` `or` ``). No escape sequences
      # inside, so just consume until the next backtick or newline.
      result.add(' ')
      inc i
      while i < line.len:
        let cc = line[i]
        if cc == '`':
          result.add(' ')
          inc i
          break
        if cc == '\n':
          break
        result.add('x')
        inc i
    of '#':
      break
    else:
      result.add(c)
      inc i

proc isWordChar(c: char): bool {.inline.} =
  c.isAlphaNumeric or c == '_'

proc endsWithKeyword(stripped: string, kw: string): bool =
  ## Whole-word match: `stripped` ends with `kw` and the char before `kw`
  ## (if any) is a non-word character.
  if stripped.len < kw.len:
    return false
  if not stripped.endsWith(kw):
    return false
  let before = stripped.len - kw.len - 1
  if before < 0:
    return true
  return not isWordChar(stripped[before])

proc endsWithSingleEquals(stripped: string): bool =
  ## True when the line ends with a `=` that is not part of a comparison
  ## (`==`, `!=`, `<=`, `>=`) or compound assignment (`+=`, `-=`, `*=`,
  ## `/=`, `%=`, `&=`, `|=`, `^=`, etc). The stripped line is already
  ## free of trailing whitespace by the caller.
  if stripped.len == 0 or stripped[^1] != '=':
    return false
  if stripped.len == 1:
    return true
  # Operator characters per the Nim manual that can combine with `=`.
  const OperatorChars = {
    '=', '+', '-', '*', '/', '<', '>', '@', '$', '~', '&', '%', '|', '!', '?', '^', '.',
    ':', '\\',
  }
  return stripped[^2] notin OperatorChars

proc endsWithBlockColon(stripped: string): bool =
  ## True when the line ends with a single `:` (block opener: if/while/
  ## for/elif/else/of/try/except/finally/block/defer/proc-body, etc.).
  ## Excludes `::` defensively even though it is not Nim syntax.
  if stripped.len == 0 or stripped[^1] != ':':
    return false
  if stripped.len >= 2 and stripped[^2] == ':':
    return false
  return true

proc unclosedBracketDepth(stripped: string): int =
  ## Count `(` + `[` + `{` minus their matching closers across `stripped`.
  ## Negative results are clamped to 0 (defensive — should not normally
  ## happen on a single syntactically-balanced-so-far line).
  var depth = 0
  for c in stripped:
    case c
    of '(', '[', '{':
      inc depth
    of ')', ']', '}':
      if depth > 0:
        dec depth
    else:
      discard
  result = depth

proc nimNeedsExtraIndent(line: string): bool =
  let code = stripNimCodeOnly(line)
  if code.len == 0:
    return false
  let stripped = code.strip(leading = false, trailing = true)
  if stripped.len == 0:
    return false

  let trimmed = stripped.strip()
  for kw in NimBlockDeclKeywords:
    if trimmed == kw:
      return true

  for kw in NimContinuationKeywords:
    if endsWithKeyword(stripped, kw):
      return true

  if endsWithBlockColon(stripped):
    return true

  if endsWithSingleEquals(stripped):
    return true

  if unclosedBracketDepth(stripped) > 0:
    return true

  return false

type
  LineToken = tuple[first, last: int, kind: TokenClass, continues: bool]
    ## A token's bytes on one line; `continues` when it runs past the line.

  TokenLine = tuple[text: string, tokens: seq[LineToken]]

  NewLineIndent* = tuple[steps, alignTo: int]
    ## The new line takes the indent of line `alignTo` (-1: of the text before
    ## the cursor), `steps` 'shiftwidth's deeper.

proc tokenLines(buffer: TextBuffer, first, last: int): seq[TokenLine] =
  ## Lines `first` to `last` and their tokens, read as a full parse does so a
  ## line inside a long comment or string reads as one: each line only up to
  ## 'synmaxcol', past which nothing is code. With no known state within
  ## `MaxResumeLines` (see `resumePoint`), read from `first` on its own, as
  ## code: a line inside a long comment or string then reads as code.
  let
    resume = buffer.resumePoint(first, MaxResumeLines)
    start = if resume.isSome: resume.get.line else: first
  var
    lines = newSeq[TokenLine](last - first + 1)
    text = ""
    starts: seq[int] ## Where each line starts in `text`.
  let cap = buffer.maxHighlightLineLength
  for l in start .. last:
    let lineText = buffer.getLine(l)
    starts.add text.len
    if cap > 0 and lineText.len > cap:
      text.add lineText.charSubStr(0, cap)
    else:
      text.add lineText
    text.add '\n'
    if l >= first:
      lines[l - first].text = lineText

  var g = GeneralTokenizer()
  g.initGeneralTokenizer(text)
  if resume.isSome and start > 0:
    g.restoreTokenizerState(resume.get.state)
  var row = 0
  while true:
    g.getNextToken(buffer.syntaxLanguage)
    if g.kind == gtEof or g.start > text.high:
      break
    let
      a = max(0, g.start)
      b = min(g.start + g.length - 1, text.high)
    while row + 1 < starts.len and starts[row + 1] <= a:
      inc row
    var r = row
    while r < starts.len and starts[r] <= b:
      let newline =
        if r + 1 < starts.len:
          starts[r + 1] - 1
        else:
          text.high
      if start + r >= first and min(b, newline - 1) >= max(a, starts[r]):
        lines[start + r - first].tokens.add (
          max(a, starts[r]) - starts[r],
          min(b, newline - 1) - starts[r],
          g.kind,
          b >= newline,
        )
      inc r
  lines

proc tokenLine(buffer: TextBuffer, line: int): TokenLine =
  buffer.tokenLines(line, line)[0]

proc isCodeBracket(tokens: seq[LineToken], text: string, i: int): bool =
  ## Whether byte `i` of `text` is a bracket in code.
  if text[i] notin Openers + Closers:
    return false
  for t in tokens:
    if i in t.first .. t.last:
      return t.kind in BracketTokens
  false

iterator codeBrackets(
    tokens: seq[LineToken], text: string, before = int.high
): tuple[column: int, ch: char] =
  ## The code brackets of `text` before byte `before`.
  for t in tokens:
    if t.kind in BracketTokens:
      for i in t.first .. min(t.last, before - 1):
        if text[i] in Openers + Closers:
          yield (i, text[i])

proc firstNonBlankAt(text: string, start: int): int =
  ## Byte of the first non-blank at or after `start`; -1 for none.
  for i in start ..< text.len:
    if text[i] notin {' ', '\t'}:
      return i
  -1

proc opensLast(tokens: seq[LineToken], text: string, before: int): bool =
  ## Whether the last code before byte `before` is an opener.
  for j in countdown(tokens.high, 0):
    let t = tokens[j]
    if t.first >= before or t.kind == gtWhitespace or t.kind in CommentTokens:
      continue
    var last = min(t.last, before - 1)
    while last >= t.first and text[last] in {' ', '\t'}:
      dec last
    if last < t.first:
      continue
    return t.kind in BracketTokens and text[last] in Openers
  false

proc inLongToken(tokens: seq[LineToken], split: int): bool =
  ## Whether byte `split` is inside a comment or string that runs over lines,
  ## or one left open at the end of the line.
  for t in tokens:
    if t.kind in LongTokens and t.first < split and (t.last >= split or t.continues):
      return true
  false

proc leavesOpen(tokens: seq[LineToken], text: string, before: int): bool =
  ## Whether an opener before byte `before` is left unclosed.
  var depth = 0
  for b in codeBrackets(tokens, text, before):
    if b.ch in Openers:
      inc depth
    elif depth > 0:
      dec depth
  depth > 0

proc matchingOpenerLine(buffer: TextBuffer, line, column: int, at: TokenLine): int =
  ## The line of the opener the closer at byte `column` of `line` closes, as
  ## Vim's searchpair(); -1 when there is none within `MaxOpenerSearchLines`.
  ## Lines above are read in growing windows, so a near opener reads few.
  let
    closer = at.text[column]
    opener =
      case closer
      of ')': '('
      of ']': '['
      else: '{'
  var depth = 0

  template scan(l: int, lineAt: TokenLine, before: int) =
    var brackets: seq[tuple[column: int, ch: char]]
    for b in codeBrackets(lineAt.tokens, lineAt.text, before):
      brackets.add(b)
    for j in countdown(brackets.high, 0):
      if brackets[j].ch == closer:
        inc depth
      elif brackets[j].ch == opener:
        if depth == 0:
          return l
        dec depth

  scan(line, at, column)
  let lowest = max(0, line - MaxOpenerSearchLines)
  var
    top = line
    window = 16
  while top > lowest:
    var first = max(lowest, top - window)
    let resume = buffer.resumePoint(first, MaxResumeLines)
    # Reading from far above costs more than the window: read the rest at once.
    if resume.isSome and resume.get.line < first - window:
      first = lowest
    let lines = buffer.tokenLines(first, top - 1)
    for l in countdown(top - 1, first):
      scan(l, lines[l - first], int.high)
    top = first
    window *= 2
  -1

proc closerAlignLine*(buffer: TextBuffer, line, column: int): int =
  ## When the code bracket at byte `column` of `line` is a closer starting the
  ## line, the line of the opener it closes; else -1.
  if buffer.language in NoIndentLanguages:
    return -1
  let text = buffer.getLine(line)
  if column >= text.len or firstNonBlankAt(text, 0) != column or
      text[column] notin Closers:
    return -1
  let at = buffer.tokenLine(line)
  if not at.tokens.isCodeBracket(text, column):
    return -1
  buffer.matchingOpenerLine(line, column, at)

proc enterIndent*(buffer: TextBuffer, line, split: int): NewLineIndent =
  ## The indent of the line Enter opens at byte `split` of `line` (its end for
  ## `o`). An opener left unclosed indents it. A carried closer steps in right
  ## after an opener, as Vim's 'smartindent', so typing goes on at the inner
  ## depth; and otherwise goes to the line of the opener it closes, as Neovim's
  ## indent scripts.
  ##
  ## Which rules apply goes by the file's language, as Vim's indent goes by
  ## 'filetype'; the tokens come from the language highlighting reads, so
  ## `:set syntax=` changes what is code but not the rules.
  result = (0, -1)
  let language = buffer.language
  if language in NoIndentLanguages:
    return
  let
    (text, tokens) = buffer.tokenLine(line)
    carried = firstNonBlankAt(text, split)
  if carried >= 0 and text[carried] in Closers and tokens.isCodeBracket(text, carried):
    if tokens.opensLast(text, split):
      return (1, -1)
    return (0, buffer.matchingOpenerLine(line, carried, (text, tokens)))
  if language == langNim:
    if not tokens.inLongToken(split):
      result.steps = ord(nimNeedsExtraIndent(text[0 ..< split]))
  else:
    result.steps = ord(tokens.leavesOpen(text, split))

proc opensAboveDeeper*(buffer: TextBuffer, line: int): bool =
  ## Whether `O` on `line` indents the new line one step deeper: `line` starts
  ## with a closer, as Vim's 'smartindent'.
  if buffer.language in NoIndentLanguages:
    return false
  let
    text = buffer.getLine(line)
    first = firstNonBlankAt(text, 0)
  if first < 0 or text[first] notin Closers:
    return false
  buffer.tokenLine(line).tokens.isCodeBracket(text, first)
