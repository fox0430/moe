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
## read through the tokenizer from the highlighter's state; Nim adds its own,
## and Bash and Zsh a table of block words.

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
  StringTokens = {gtStringLit, gtEscapeSequence, gtCharLit}
  MaxOpenerSearchLines = 1000
  MaxResumeLines = 1000
    ## How far above a line a known tokenizer state is looked for; past it,
    ## the line is read on its own.
  Openers = {'(', '[', '{'}
  Closers = {')', ']', '}'}
  NimContinuationKeywords = ["or", "and", "object", "tuple", "enum"]
  NimBlockDeclKeywords = ["var", "let", "const", "type"]

type
  MiddleWord = tuple[word: string, targets, stops: seq[string]]
    ## A word going on with a block: it lines up with the nearest of `targets`
    ## above, unless one of `stops` comes first.

  BlockWords = object ## The words of one kind of block.
    openers, closers: seq[string]
    middles: seq[MiddleWord]

const
  ShellIf = BlockWords(
    openers: @["if"],
    closers: @["fi"],
    middles: @[
      (word: "then", targets: @["if", "elif"], stops: @["then", "else"]),
      (word: "elif", targets: @["if"], stops: @["else"]),
      (word: "else", targets: @["if"], stops: @["else"]),
    ],
  )
  ShellLoopMiddles = @[(word: "do", targets: newSeq[string](), stops: @["do"])]
  ShellCase = BlockWords(openers: @["case"], closers: @["esac"])
  ShellBlocks = [
    ShellIf,
    BlockWords(
      openers: @["for", "while", "until", "select"],
      closers: @["done"],
      middles: ShellLoopMiddles,
    ),
    ShellCase,
  ]
  ZshBlocks = [
    ShellIf,
    BlockWords(
      openers: @["for", "while", "until", "select", "repeat", "foreach"],
      closers: @["done", "end"],
      middles: ShellLoopMiddles,
    ),
    ShellCase,
  ]
  BlockWordLanguages* = {langBash, langZsh}
  Blanks = {' ', '\t'}
  WordAfter = Blanks + {';', '&', '|', '<', '>', '(', ')', '`'}
    ## What may follow a block word.
  WordTokens = {gtKeyword, gtIdentifier}
  CommandLeads =
    ["if", "then", "do", "else", "elif", "while", "until", "time", "coproc"]
    ## Words another command, so another block word, may follow.
  NameLeads = ["function", "coproc", "always"]
    ## Words a `{` may follow, past a name or at once.
  BraceLoops = ["for", "select", "repeat", "foreach"]
    ## Loops whose body may be in braces, with no `do` and `done`.
  ZshTests = ["if", "elif", "while", "until"]
    ## Whose body may, in Zsh, be in braces or one command, right after a test
    ## that ends itself: `[[ ]]`, `(( ))` or `( )`.

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

  TokenLine = tuple[text: string, tokens: seq[LineToken], inString: bool]
    ## `inString` when it starts inside a string, but for a heredoc's body.

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
    let inHeredoc = g.state == gtLongStringLit and g.lang.shell.heredocMarker.len > 0
    g.getNextToken(buffer.syntaxLanguage)
    if g.kind == gtEof or g.start > text.high:
      break
    let
      # A heredoc's end marker, highlighted as a keyword, is text.
      kind = if inHeredoc: gtLongStringLit else: g.kind
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
          kind,
          b >= newline,
        )
      if b >= newline and kind in StringTokens and r + 1 < starts.len and
          start + r + 1 >= first:
        lines[start + r + 1 - first].inString = true
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

proc lastNonBlankBefore(text: string, stop: int): int =
  ## Byte of the last non-blank before `stop`; -1 for none.
  for i in countdown(min(stop, text.len) - 1, 0):
    if text[i] notin Whitespace:
      return i
  -1

proc endsAt(text, suffix: string, stop: int): bool =
  ## Whether `text` up to byte `stop` ends with `suffix`.
  stop >= suffix.len and text.continuesWith(suffix, stop - suffix.len)

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

type
  MarkKind = enum
    mkWord ## A block word.
    mkImplied ## The end of a block that no word closes, as the word that would.
    mkOpen
    mkClose
    mkBreak ## `;;`, `;&` or `;;&`.
    mkLabel ## The `)` of a `case` pattern.

  Mark = tuple[column: int, kind: MarkKind, text: string]
    ## Something on a shell line that opens or closes a block.

  ShellLine = tuple[at: TokenLine, marks: seq[Mark]]

  ShellLines = object ## The lines from `first` on, the last the one asked for.
    first: int
    lines: seq[ShellLine]
    carried: seq[Mark] ## Of the text Enter carries down, when asked for.

  FrameKind = enum
    fkCommands ## `( )`, `$( )` or backquotes.
    fkData ## An array, a pattern's group: words and no commands, over lines.
    fkLineData ## `${ }`, a pattern's group: taken to end with the line.
    fkTest ## `(( ))`, `[[ ]]` and what nests in them: over lines.
    fkCaseWord ## `case` up to its `in`.
    fkPattern ## Where a `case` pattern may come.
    fkCaseBody

  Frame = tuple[kind: FrameKind, closer: char, commandAfter: bool]

  BraceKind = enum
    bkPlain
    bkIfBody ## A Zsh `if`'s body.
    bkCase ## The arms of a Zsh `case`.

  LoopHeader = object ## One of `BraceLoops` or `ZshTests` whose body has not begun.
    word: string # Empty for none
    depth: int # Frames around it
    args: int # Words after it, up to its `in` or separator
    listed: bool # The last code read was the `)` of its list
    separated: bool # After the `;` or line end that ends its words
    inTest: bool # The last code read at its depth begins a test
    tested: bool # The last code read was the end of a test

  ShellReader = object ## Reads a shell's lines from the top down.
    stack: seq[Frame]
    command: bool ## A command may start here.
    patternBegun: bool
    continued: bool ## The line above ended in a `\` continuation.
    naming: bool ## After one of `NameLeads`.
    loop: LoopHeader
    joined: bool ## The code so far ends where a `[[ ]]` goes on.
    lastCode: char ## The last character of the code above the line.
    braces: seq[BraceKind] ## The `{` open, but for `${`.
    braceOfIf: bool ## The `{` at hand begins a Zsh `if`'s body.
    ifBodyEnded: bool ## The last code read was the `}` of a Zsh `if`'s body.

proc blockOf(
    blocks: openArray[BlockWords], word: string
): tuple[index: int, opens, closes: bool] =
  ## The block `word` belongs to; neither opening nor closing it when a middle
  ## word, and -1 for no block word.
  for i, b in blocks:
    if word in b.openers:
      return (i, true, false)
    if word in b.closers:
      return (i, false, true)
    for m in b.middles:
      if m.word == word:
        return (i, false, false)
  (-1, false, false)

template withBlocks(buffer: TextBuffer, blocks, body: untyped) =
  if buffer.language == langZsh:
    const blocks {.inject.} = ZshBlocks
    body
  else:
    const blocks {.inject.} = ShellBlocks
    body

proc top(reader: ShellReader): FrameKind =
  if reader.stack.len > 0:
    reader.stack[^1].kind
  else:
    fkCommands

proc closeFrame(reader: var ShellReader, closer: char): bool =
  ## End the innermost frame `closer` ends, with the frames left open in it.
  for i in countdown(reader.stack.high, 0):
    if reader.stack[i].closer == closer:
      reader.command = reader.stack[i].commandAfter
      reader.stack.setLen(i)
      return true
  false

proc endCase(reader: var ShellReader) =
  for i in countdown(reader.stack.high, 0):
    if reader.stack[i].kind in {fkCaseWord, fkPattern, fkCaseBody}:
      reader.stack.setLen(i)
      return
    if reader.stack[i].kind == fkCommands:
      return

proc dropTests(reader: var ShellReader) =
  ## End the tests and arithmetic at hand, unfinished.
  while reader.top in {fkLineData, fkTest}:
    reader.stack.setLen(reader.stack.len - 1)

proc inBracketTest(reader: ShellReader): bool =
  ## Whether the test at hand is a `[[ ]]`.
  for i in countdown(reader.stack.high, 0):
    if reader.stack[i].kind != fkTest:
      return false
    if reader.stack[i].closer == ']':
      return true

proc startLine(reader: var ShellReader, text: string) =
  while reader.top == fkLineData:
    reader.stack.setLen(reader.stack.len - 1)
  let first = firstNonBlankAt(text, 0)
  if first >= 0 and text[first] != '#':
    # A `[[` with nothing to go on with is taken as unfinished.
    if not (reader.continued or reader.joined) and reader.inBracketTest and
        not (
          text[first] == ')' or text.continuesWith("]]", first) or
          text.continuesWith("&&", first) or text.continuesWith("||", first)
        ):
      reader.dropTests()
  if not reader.continued:
    reader.naming = false
    reader.loop.tested = false
    reader.ifBodyEnded = false
    reader.command = reader.top in {fkCommands, fkCaseBody}
  reader.continued = false

proc endsPattern(text: string, first: int): bool =
  ## Whether a `case` pattern ends at or after byte `first`, at its `)` or
  ## through more patterns after a `|`.
  var i = first
  while true:
    while i < text.len and text[i] in Blanks:
      inc i
    if i >= text.len or text[i] notin {')', '|'}:
      return false
    if text[i] == ')':
      return true
    inc i
    while i < text.len and text[i] in Blanks:
      inc i
    let word = i
    while i < text.len and text[i] notin Blanks + {';', '&', '|', '(', ')', '<', '>'}:
      inc i
    if i == word:
      return false

proc isOperand(reader: ShellReader, text: string, last: int): bool =
  ## Whether the word first on its line, up to byte `last`, is a variable of the
  ## arithmetic at hand: after an operator, or before one no command begins with.
  if reader.inBracketTest:
    return false
  if reader.lastCode in {',', '=', '+', '-', '*', '/', '%', '<', '>', '?', ':', '^'}:
    return true
  let i = firstNonBlankAt(text, last + 1)
  if i < 0:
    return false
  let next =
    if i < text.high:
      text[i + 1]
    else:
      ' '
  case text[i]
  of '=', ',', '^':
    true
  of '+', '-', '*', '/', '%', '?':
    next in Blanks + {'='}
  of '!', '<', '>', '|', '&':
    next == '='
  else:
    false

proc readWord(
    reader: var ShellReader,
    blocks: openArray[BlockWords],
    zsh: bool,
    text: string,
    first, last: int,
    marks: var seq[Mark],
) =
  const WordBefore = Blanks + {';', '&', '|', '(', ')', '{', '`', '!'}
  let
    word = text[first .. last]
    after =
      if last < text.high:
        text[last + 1]
      else:
        ' '
    alone =
      (first == 0 or text[first - 1] in WordBefore) and
      (after in WordAfter or (zsh and after == '}'))
    found = blocks.blockOf(word)
    lineStart = firstNonBlankAt(text, 0) == first
  case reader.top
  of fkCaseWord:
    reader.command = false
    if alone and word == "in":
      reader.stack[^1].kind = fkPattern
      reader.patternBegun = false
      return
    if not (lineStart and found.index >= 0):
      return
    # The `case` is not finished: go on as if it were not there.
    reader.stack.setLen(reader.stack.len - 1)
    reader.command = true
  of fkPattern:
    let ends =
      alone and not reader.patternBegun and after notin {')', '|'} and
      not text.endsPattern(last + 1)
    if alone and word == "esac" and not reader.patternBegun:
      reader.endCase()
      marks.add (first, mkWord, word)
      reader.command = true
      return
    if not (ends and lineStart and found.closes):
      reader.patternBegun = true
      return
    # An `esac` is missing: the block around the `case` ends.
    reader.endCase()
    reader.command = true
  of fkTest:
    reader.command = false
    if not (alone and lineStart and found.index >= 0) or reader.isOperand(text, last):
      return
    # The test is not finished.
    reader.dropTests()
    if reader.top notin {fkCommands, fkCaseBody}:
      return
    reader.command = true
  of fkData, fkLineData:
    reader.command = false
    return
  of fkCommands, fkCaseBody:
    discard
  if alone and word == "do" and reader.loop.word in ["for", "select", "repeat"] and
      reader.loop.args >= 2 and reader.stack.len == reader.loop.depth:
    # Right after the loop's name or count.
    reader.command = true
  let goesOnAfterBody = reader.ifBodyEnded
  reader.ifBodyEnded = false
  if alone and reader.command and word in NameLeads:
    reader.naming = true
  if alone and reader.command and reader.stack.len <= reader.loop.depth and
      (reader.loop.word notin ZshTests or found.index >= 0):
    # A command, or a block word: the body of a loop has begun. A test is
    # commands too.
    reader.loop.word = ""
  if not (alone and reader.command) or found.index < 0 or
  # A pattern whose `case` is out of sight.
  (found.opens and after == ')'):
    reader.command = alone and reader.command and word in CommandLeads
    return
  reader.command = found.closes or word in CommandLeads
  if goesOnAfterBody and word in ["elif", "else"]:
    # Of an `if` whose braces close it.
    if word == "elif":
      reader.loop = LoopHeader(word: word, depth: reader.stack.len)
    return
  marks.add (first, mkWord, word)
  if word in BraceLoops or (zsh and found.opens and word in ZshTests):
    reader.loop = LoopHeader(word: word, depth: reader.stack.len)
  if word == "case":
    reader.stack.add (fkCaseWord, '\0', false)
  elif word == "esac":
    reader.endCase()
    reader.command = true

proc endLoopAt(
    reader: var ShellReader, zsh: bool, text: string, first: int, marks: var seq[Mark]
) =
  ## When the code at byte `first` is the body of a loop with no `do`, or of a
  ## Zsh `if` with no `then`, mark the block as closed: nothing else will.
  if reader.loop.word.len == 0 or reader.stack.len > reader.loop.depth:
    return
  if reader.stack.len < reader.loop.depth:
    reader.loop.word = ""
    return
  let
    c = text[first]
    blankBefore = first == 0 or text[first - 1] in Blanks
    braced =
      c == '{' and reader.command and
      (zsh or first == text.high or text[first + 1] in Blanks)
  if reader.loop.word in ZshTests:
    let tested = reader.loop.tested
    reader.loop.tested = false
    reader.loop.inTest =
      reader.command and (c == '(' or text.continuesWith("[[", first))
    if not tested:
      return
    var last = first
    while last < text.high and text[last + 1] notin WordAfter:
      inc last
    let short =
      c notin Digits + {';', '&', '|', '<', '>', '(', ')', '{', '}', '`', '\\', '!'} and
      text[first .. last] notin ["then", "do"]
    if braced or short:
      case reader.loop.word
      of "if":
        marks.add (first, mkImplied, "fi")
      of "elif":
        # The `if` is marked as closed already.
        discard
      else:
        marks.add (first, mkImplied, "done")
      reader.braceOfIf = braced and reader.loop.word in ["if", "elif"]
      reader.loop.word = ""
      reader.command = true
    return
  let body = reader.loop.separated and reader.command and reader.loop.word != "foreach"
    ## A command here, past the separator, is the body.
  if c == ';':
    reader.loop.separated = true
  if c in {';', '&', '|'}:
    # Only a `do` or a `{` is the body from here on.
    reader.loop.args = low(int)
  var short = false
  if zsh and body and c == '(':
    short = true
  elif not braced and c notin {';', '&', '|', '<', '>', '(', ')', '\\'}:
    var last = first
    while last < text.high and text[last + 1] notin WordAfter:
      inc last
    let isDo = text[first .. last] == "do"
    if text[first .. last] == "in":
      # A `)` in the words after it ends no list, and a `do` is one of them.
      reader.loop.args = low(int)
    elif blankBefore:
      inc reader.loop.args
    if not zsh:
      reader.loop.listed = false
      return
    if reader.loop.word == "repeat" and blankBefore:
      short = reader.loop.args == 2 and not isDo
    elif reader.loop.word in ["for", "select"]:
      short = reader.loop.listed and not isDo
    if body and c != '}' and text[first .. last] notin ["do", "done", "in"]:
      short = true
  reader.loop.listed = false
  if braced or short:
    marks.add (first, mkImplied, "done")
    reader.loop.word = ""
    reader.command = true

proc readLine(
    reader: var ShellReader, blocks: openArray[BlockWords], zsh: bool, at: TokenLine
): seq[Mark] =
  ## The marks of the next line: block words where a command starts, brackets,
  ## and what separates the arms of a `case`.
  let text = at.text
  if at.inString:
    reader.continued = true
  if not reader.continued:
    reader.loop.listed = false
    reader.loop.separated =
      reader.loop.separated or reader.stack.len == reader.loop.depth
    if reader.loop.word == "repeat" and reader.loop.args > 0:
      reader.loop.args = low(int)
  reader.startLine(text)
  var
    done = 0 # Bytes before it are dealt with
    lastCode = reader.lastCode
  defer:
    reader.lastCode = lastCode

  template charAt(i: int): char =
    if i >= 0 and i < text.len:
      text[i]
    else:
      ' '

  template push(frame: FrameKind, ends: char, after: bool) =
    reader.stack.add (frame, ends, after)

  for t in at.tokens:
    if t.kind == gtWhitespace or t.kind in CommentTokens:
      continue
    let code = text.lastNonBlankBefore(t.last + 1)
    lastCode = charAt(code)
    reader.joined =
      t.continues or lastCode == '(' or
      (lastCode in {'&', '|'} and charAt(code - 1) == lastCode)
    if t.last < done:
      continue
    if text[t.first] == '\\' and t.first == text.high:
      reader.continued = true
      continue
    if t.kind in StringTokens + {gtLongStringLit} or text[t.first] == '\\':
      reader.endLoopAt(zsh, text, t.first, result)
      reader.command = false
      reader.patternBegun = true
      reader.ifBodyEnded = false
      continue
    if t.kind in WordTokens and text[t.first].isAlphaAscii:
      reader.endLoopAt(zsh, text, t.first, result)
      reader.readWord(blocks, zsh, text, t.first, t.last, result)
      continue
    for i in max(t.first, done) .. t.last:
      if i < done or text[i] in Blanks:
        continue
      reader.endLoopAt(zsh, text, i, result)
      let
        c = text[i]
        before = charAt(i - 1)
        next = charAt(i + 1)
        # Not a command's place, so nothing in here separates commands.
        data = reader.top in {fkData, fkLineData, fkTest, fkCaseWord, fkPattern}
        inExpansion = reader.stack.len > 0 and reader.stack[^1].closer == '}'
      reader.ifBodyEnded = false
      if c in {';', '|', '&'}:
        reader.naming = false
      case c
      of '(':
        if reader.top == fkPattern and not reader.patternBegun:
          # The optional `(` before a pattern.
          reader.patternBegun = true
          continue
        if inExpansion and before notin {'$', '<', '>'}:
          # Text, as in `${x%(}`.
          continue
        if t.kind in BracketTokens:
          result.add (i, mkOpen, "(")
        let
          nextCode = firstNonBlankAt(text, i + 1)
          empty = nextCode >= 0 and text[nextCode] == ')'
        if before == '$' or
            (before in {'<', '>'} and reader.top notin {fkLineData, fkTest}):
          push((if next == '(': fkTest else: fkCommands), ')', false)
        elif reader.top == fkTest or (next == '(' and not data):
          # A reserved word may follow `(( ))`, as a command's or a `for`'s.
          push(fkTest, ')', not data and before notin {'$', '='})
        elif reader.top == fkLineData:
          push(fkLineData, ')', false)
        elif reader.top in {fkData, fkPattern} or empty or before == '=':
          push(fkData, ')', empty and before != '=')
        elif reader.command:
          push(fkCommands, ')', true)
        elif reader.loop.word.len > 0:
          # The list of a Zsh loop.
          push(fkData, ')', before in Blanks)
        else:
          push(fkLineData, ')', before in Blanks)
        reader.command = reader.top == fkCommands
        reader.patternBegun = true
      of ')':
        if reader.top == fkPattern:
          result.add (i, mkLabel, ")")
          reader.stack[^1].kind = fkCaseBody
          reader.command = true
        elif inExpansion:
          discard
        else:
          result.add (i, mkClose, ")")
          if not reader.closeFrame(')'):
            reader.command = false
          let atLoop = reader.stack.len == reader.loop.depth
          reader.loop.listed = reader.loop.args >= 0 and atLoop
          reader.loop.tested = reader.loop.inTest and atLoop
      of ';':
        if reader.top in {fkCommands, fkCaseBody} and
            (next in {';', '&'} or (zsh and next == '|')):
          result.add (i, mkBreak, ";;")
          done = i + 2
          if charAt(done) == '&':
            inc done
          if reader.top == fkCaseBody:
            reader.stack[^1].kind = fkPattern
          else:
            # The `case` is out of sight.
            push(fkPattern, '\0', false)
          reader.patternBegun = false
          reader.command = false
        else:
          reader.command = not data
      of '|', '&':
        reader.command = not data and before notin {'<', '>'}
      of '{':
        if t.kind in BracketTokens:
          result.add (i, mkOpen, "{")
        if before == '$':
          push(fkLineData, '}', false)
        elif not data:
          reader.braces.add (if reader.braceOfIf: bkIfBody else: bkPlain)
        elif zsh and reader.top == fkCaseWord and before in Blanks:
          # As `in`.
          reader.stack[^1].kind = fkPattern
          reader.patternBegun = false
          reader.braces.add bkCase
        reader.braceOfIf = false
        reader.command =
          not data and (reader.command or reader.naming) and
          before in Blanks + {')', ';'} and (zsh or next in Blanks)
        reader.naming = false
      of '}':
        if t.kind in BracketTokens:
          result.add (i, mkClose, "}")
        let command = reader.command
        if not data and reader.braces.len > 0 or
            reader.top == fkPattern and not reader.patternBegun and reader.braces.len > 0 and
            reader.braces[^1] == bkCase:
          reader.command = command and before in Blanks + {';'}
          case reader.braces.pop
          of bkPlain:
            discard
          of bkIfBody:
            reader.ifBodyEnded = true
            reader.command = true
          of bkCase:
            reader.endCase()
            # No `esac` will close it.
            result.add (i, mkImplied, "esac")
            reader.command = true
        elif not reader.closeFrame('}'):
          reader.command = command and before in Blanks + {';'}
      of '[':
        if t.kind in BracketTokens:
          result.add (i, mkOpen, "[")
        if next == '[' and charAt(i + 2) in Blanks and reader.command and
            reader.top in {fkCommands, fkCaseBody}:
          push(fkTest, ']', true)
        reader.command = false
        reader.patternBegun = true
      of ']':
        if t.kind in BracketTokens:
          result.add (i, mkClose, "]")
        reader.command = false
        if before == ']' and charAt(i - 2) in Blanks + {')'} and
            next in WordAfter + {'}'} and reader.inBracketTest:
          # A `]]` in a pattern or a subscript is no word of its own.
          discard reader.closeFrame(']')
          reader.loop.tested =
            reader.loop.inTest and reader.stack.len == reader.loop.depth
      of '-':
        # `time -p` and `time --` are still before a command.
        let lead = text.lastNonBlankBefore(i) + 1
        if reader.command and next in {'p', '-'} and charAt(i + 2) in Blanks and
            (text.endsAt("time", lead) or text.endsAt("time -p", lead)):
          done = i + 2
        else:
          reader.command = false
          reader.patternBegun = true
      of '!':
        reader.command = reader.command and next in Blanks
        reader.patternBegun = true
      of '`':
        if not reader.closeFrame('`'):
          push(fkCommands, '`', false)
          reader.command = true
      else:
        reader.command = false
        reader.patternBegun = true

proc splitAt(at: TokenLine, split: int): tuple[head, tail: TokenLine] =
  ## `at` as two lines; the tail keeps its columns.
  result.head.inString = at.inString
  result.head.text = at.text[0 ..< split]
  result.tail.text = " ".repeat(split) & at.text[split ..^ 1]
  for t in at.tokens:
    if t.first < split:
      result.head.tokens.add (t.first, min(t.last, split - 1), t.kind, t.continues)
    if t.last >= split:
      result.tail.tokens.add (max(t.first, split), t.last, t.kind, t.continues)

proc shellLines(buffer: TextBuffer, line: int, split = -1): ShellLines =
  ## `line` and up to `MaxOpenerSearchLines` above it, read in one pass; `line`
  ## only up to byte `split` when given, as Enter there leaves it.
  result.first = max(0, line - MaxOpenerSearchLines)
  var reader: ShellReader
  withBlocks(buffer, blocks):
    let zsh = buffer.language == langZsh
    var tokens = buffer.tokenLines(result.first, line)
    var tail: TokenLine
    if split >= 0:
      (tokens[^1], tail) = tokens[^1].splitAt(split)
    for at in tokens:
      let marks = reader.readLine(blocks, zsh, at)
      result.lines.add (at, marks)
    if split >= 0:
      result.carried = reader.readLine(blocks, zsh, tail)

iterator marksBefore(read: ShellLines, column: int): tuple[line: int, mark: Mark] =
  ## The marks before byte `column` of the last line, upward.
  for i in countdown(read.lines.high, 0):
    let marks = read.lines[i].marks
    for j in countdown(marks.high, 0):
      if i < read.lines.high or marks[j].column < column:
        yield (read.first + i, marks[j])

proc openerLine(read: ShellLines, column: int, closer: char): int =
  ## The line of the opener that `closer`, at byte `column` of the last line
  ## read, closes; else -1.
  let opener =
    case closer
    of ')': '('
    of ']': '['
    else: '{'
  var depth = 0
  for (l, m) in read.marksBefore(column):
    if m.kind == mkClose and m.text[0] == closer:
      inc depth
    elif m.kind == mkOpen and m.text[0] == opener:
      if depth == 0:
        return l
      dec depth
  -1

proc leavesBlockOpen(
    read: ShellLines, blocks: openArray[BlockWords], column: int, closer: char
): bool =
  ## Whether a block, or an arm of a `case`, is open at byte `column` of the last
  ## line read, inside the bracket that `closer` closes there.
  let opener =
    case closer
    of ')': '('
    of ']': '['
    else: '{'
  var
    depth = 0
    closed = newSeq[int](blocks.len)
  for (l, m) in read.marksBefore(column):
    if m.kind == mkClose and m.text[0] == closer:
      inc depth
    elif m.kind == mkOpen and m.text[0] == opener:
      if depth == 0:
        return false
      dec depth
    elif depth == 0 and m.kind in {mkWord, mkImplied}:
      let found = blocks.blockOf(m.text)
      if found.closes:
        inc closed[found.index]
      elif found.opens:
        if closed[found.index] == 0:
          return true
        dec closed[found.index]
    elif depth == 0 and m.kind in {mkLabel, mkBreak} and
        closed[blocks.blockOf("case").index] == 0:
      return true
  false

proc matchingOpenerLine(buffer: TextBuffer, line, column: int, at: TokenLine): int =
  ## The line of the opener the closer at byte `column` of `line` closes, as
  ## Vim's searchpair(); -1 when there is none within `MaxOpenerSearchLines`.
  ## Lines above are read in growing windows, so a near opener reads few; a
  ## shell's are read in one pass, from the top down.
  let
    closer = at.text[column]
    opener =
      case closer
      of ')': '('
      of ']': '['
      else: '{'
  var depth = 0
  if buffer.language in BlockWordLanguages:
    let read = buffer.shellLines(line)
    for m in read.lines[^1].marks:
      if m.column == column and m.kind == mkLabel:
        return -1
    return read.openerLine(column, closer)

  template scan(l: int, lineAt: TokenLine, before: int) =
    var brackets: seq[char]
    for b in codeBrackets(lineAt.tokens, lineAt.text, before):
      brackets.add b.ch
    for j in countdown(brackets.high, 0):
      if brackets[j] == closer:
        inc depth
      elif brackets[j] == opener:
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

proc wordAlignLine(
    buffer: TextBuffer, read: ShellLines, column: int, word: string
): int =
  ## The line the block word `word`, at byte `column` of the last line read,
  ## lines up with; -1 when it continues or closes no block above.
  withBlocks(buffer, blocks):
    let found = blocks.blockOf(word)
    if found.index < 0 or found.opens:
      return -1
    let words = blocks[found.index]
    var
      targets = words.openers
      stops: seq[string]
    for m in words.middles:
      if m.word == word:
        if m.targets.len > 0:
          targets = m.targets
        stops = m.stops
    var depth = 0
    for (l, m) in read.marksBefore(column):
      if m.kind notin {mkWord, mkImplied}:
        continue
      if m.text in words.closers:
        inc depth
      elif depth == 0 and m.text in targets:
        return l
      elif depth == 0 and m.text in stops:
        return -1
      elif m.text in words.openers:
        if depth == 0:
          return -1
        dec depth
  -1

proc wordAt(marks: seq[Mark], column: int): string =
  ## The block word at byte `column`; empty for none.
  for m in marks:
    if m.kind == mkWord and m.column == column:
      return m.text

proc leadingWord(read: ShellLines): string =
  let (at, marks) = read.lines[^1]
  marks.wordAt(firstNonBlankAt(at.text, 0))

proc leadingWordAlignLine(buffer: TextBuffer, read: ShellLines): int =
  let first = firstNonBlankAt(read.lines[^1].at.text, 0)
  buffer.wordAlignLine(read, first, read.leadingWord)

proc leadingWordAlignLine*(buffer: TextBuffer, line: int): int =
  ## The line `line` lines up with when it starts with a word continuing or
  ## closing a block; else -1.
  buffer.leadingWordAlignLine(buffer.shellLines(line))

proc patternAlignment(read: ShellLines, column: int): NewLineIndent =
  ## The indent of the pattern after the `;;` at byte `column`: of the line the
  ## nearest pattern above starts, or a step in from a `case` with none.
  result = (0, -1)
  var
    depth = 0
    label = -1
  for (l, m) in read.marksBefore(column):
    if label >= 0 and l != label:
      return (0, label)
    if m.kind in {mkWord, mkImplied} and m.text == "esac":
      inc depth
    elif m.kind == mkWord and m.text == "case":
      if depth == 0:
        return (1, l)
      dec depth
    elif depth == 0 and m.kind == mkLabel:
      label = l
    elif depth == 0 and m.kind == mkBreak:
      # A pattern after it on its line is not at the line's start.
      label = -1
  if label >= 0:
    result.alignTo = label

proc shellEnterIndent(
    buffer: TextBuffer, line, split, carried: int, at: TokenLine, closing: bool
): NewLineIndent =
  ## `enterIndent` for the shells: a block left open indents, a word closing
  ## one lines up with its opener, as Neovim's indent/sh.vim. After a `;;` the
  ## line goes to the patterns' depth at once, where sh.vim waits for the `)`.
  ## A block or bracket begun on a line above counts from there, wherever on the
  ## line its `then`, `fi` or closer is. A code closer carried down, at byte
  ## `carried` when `closing`, goes to its opener's line unless a block is open
  ## inside it: the line is then as without the closer.
  result = (0, -1)
  for t in at.tokens:
    if t.kind in LongTokens + {gtStringLit} and t.first < split and
        (t.last >= split or t.continues):
      return
  let read = buffer.shellLines(line, split)
  withBlocks(buffer, blocks):
    var word = read.carried.wordAt(carried)
    if carried >= 0 and at.text[carried] == '{':
      # A body in braces lines up, as what closes the block would.
      for m in read.carried:
        if m.kind == mkImplied and m.column == carried:
          word = m.text
    if word.len > 0:
      let alignTo = buffer.wordAlignLine(read, split, word)
      if alignTo >= 0:
        return (0, alignTo)
    let head = firstNonBlankAt(at.text, 0)
    var
      open: seq[string] # What closes each block left open
      lastBreak = -1
    for m in read.lines[^1].marks:
      template close(closer: string): bool =
        var closed = false
        for i in countdown(open.high, 0):
          if open[i] == closer:
            open.setLen(i)
            closed = true
            break
        closed

      case m.kind
      of mkOpen:
        open.add(
          if m.text == "(":
            ")"
          elif m.text == "[":
            "]"
          else:
            "}"
        )
      of mkClose:
        if not close(m.text) and m.column != head:
          let alignTo = read.openerLine(m.column, m.text[0])
          if alignTo >= 0:
            result.alignTo = alignTo
      of mkLabel:
        open.add ";;"
      of mkBreak:
        discard close(";;")
        lastBreak = m.column
      of mkWord, mkImplied:
        let
          found = blocks.blockOf(m.text)
          closer = blocks[found.index].closers[0]
        if found.opens:
          open.add closer
          continue
        let known =
          if found.closes:
            close(closer)
          else:
            closer in open
        if not known:
          if m.column != head:
            let alignTo = buffer.wordAlignLine(read, m.column, m.text)
            # A word that follows its block's opener on this line is at home.
            if alignTo >= 0 and alignTo != line:
              result.alignTo = alignTo
          if not found.closes:
            open.add closer
    if closing:
      if read.carried.len > 0 and read.carried[0].kind == mkLabel and
          not at.text[0 ..< split].strip(leading = false).endsWith(" in"):
        return (0, -1)
      if open.len > 0 and open[^1] notin [")", "]", "}"]:
        return (1, -1)
      let closer = at.text[carried]
      if open.len > 0 or not read.leavesBlockOpen(blocks, split, closer):
        return (0, read.openerLine(split, closer))
    if lastBreak >= 0:
      var last = -1
      for t in at.tokens:
        if t.first < split and t.kind != gtWhitespace and t.kind notin CommentTokens:
          last = min(t.last, split - 1)
      if at.text[lastBreak .. last].allCharsInSet({';', '&', '|'}):
        let pattern = read.patternAlignment(lastBreak)
        if pattern.alignTo >= 0:
          return pattern
    result.steps = ord(open.len > 0)

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
    at = buffer.tokenLine(line)
    (text, tokens) = (at.text, at.tokens)
    carried = firstNonBlankAt(text, split)
  let closing =
    carried >= 0 and text[carried] in Closers and tokens.isCodeBracket(text, carried)
  if closing and tokens.opensLast(text, split):
    return (1, -1)
  if language in BlockWordLanguages:
    return buffer.shellEnterIndent(line, split, carried, at, closing)
  if closing:
    return (0, buffer.matchingOpenerLine(line, carried, at))
  if language == langNim:
    if not tokens.inLongToken(split):
      result.steps = ord(nimNeedsExtraIndent(text[0 ..< split]))
  else:
    result.steps = ord(tokens.leavesOpen(text, split))

proc aboveIndent*(buffer: TextBuffer, line: int): NewLineIndent =
  ## The indent of the line `O` opens above `line`: a step deeper than one that
  ## starts with a closer, as Vim's 'smartindent', or a word that closes a
  ## block; above an `esac`, that of the patterns, as Enter after a `;;`.
  result = (0, -1)
  if buffer.language in NoIndentLanguages:
    return
  let
    text = buffer.getLine(line)
    first = firstNonBlankAt(text, 0)
  if first < 0:
    return
  if buffer.language in BlockWordLanguages and text[first].isAlphaAscii:
    let read = buffer.shellLines(line)
    if buffer.leadingWordAlignLine(read) < 0:
      return
    if read.leadingWord == "esac":
      return read.patternAlignment(first)
    return (1, -1)
  if text[first] in Closers and buffer.tokenLine(line).tokens.isCodeBracket(text, first):
    return (1, -1)

proc isBlockWord*(buffer: TextBuffer, word: string): bool =
  ## Whether `word` continues or closes a block in `buffer`'s language.
  if buffer.language notin BlockWordLanguages:
    return false
  withBlocks(buffer, blocks):
    let found = blocks.blockOf(word)
    return found.index >= 0 and not found.opens

proc typedAlignLine*(buffer: TextBuffer, line, column: int): int =
  ## The line whose indent `line` takes once the character before byte `column`
  ## is typed, as Vim's 'indentkeys': a closer or a word that closes a block,
  ## first on the line, lines up with its opener. -1 for none.
  let
    text = buffer.getLine(line)
    first = firstNonBlankAt(text, 0)
  if first < 0 or column <= first or column > text.len:
    return -1
  if column == first + 1 and text[first] in Closers:
    return buffer.closerAlignLine(line, first)
  if not buffer.isBlockWord(text[first ..< column]):
    return -1
  # A `}` right after the cursor is of an auto-closed pair: no part of the word.
  let split = if column < text.len and text[column] == '}': column else: -1
  buffer.leadingWordAlignLine(buffer.shellLines(line, split))
