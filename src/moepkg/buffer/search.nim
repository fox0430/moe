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

## Buffer search: regex-based forward/backward search, per-line match ranges,
## literal (* and #) / current-word match enumeration. Compiled regexes are
## memoised in a single private slot to avoid recompiling on every keystroke.

import std/[options, sequtils, strutils, unicode]

import pkg/regex

import ../[primitives, unicode_utils, char_case, char_class]
import core

type
  SearchMatch* = enum
    ## How a search pattern matches.
    smRegex ## As a regex (/ and ? and a typed :s)
    smLiteral ## As it is (g* and g#)
    smWord
      ## As it is, a word character at either end starting or ending a word, as
      ## the `\<` and `\>` Vim's * and # put around a keyword

  RegexPattern = ref object
    ## A pattern / and ? and a typed :s look for as a regex, compiled.
    text: string
    ignorecase: bool
    re: Option[Regex2] ## none when it does not compile

var regexCache: RegexPattern

proc regexPattern(text: string, ignorecase: bool): RegexPattern =
  ## `text`, not empty, compiled. The last one is kept, a failure too:
  ## callers match line by line, and a pattern still being typed often does
  ## not compile.
  assert text.len > 0, "an empty pattern matches nothing, and is not compiled"
  let c = regexCache
  if c != nil and c.text == text and c.ignorecase == ignorecase:
    return c
  let flags =
    if ignorecase:
      {regexCaseless}
    else:
      default(set[RegexFlag])
  result = RegexPattern(text: text, ignorecase: ignorecase)
  try:
    result.re = some(re2(text, flags))
  except RegexError:
    discard
  regexCache = result

proc isSearchable(pattern: string, ignorecase: bool, match: SearchMatch): bool =
  ## Whether `pattern` is one `match` can look for: not empty, and a regex
  ## that compiles when it reads one.
  pattern.len > 0 and (match != smRegex or regexPattern(pattern, ignorecase).re.isSome)

proc invalidRegex*(pattern: string, ignorecase: bool, match: SearchMatch): string =
  ## "Invalid regex: `pattern`" when `match` reads `pattern` as a regex that
  ## does not compile, empty otherwise.
  if pattern.len > 0 and not pattern.isSearchable(ignorecase, match):
    "Invalid regex: " & pattern
  else:
    ""

proc validUtf8Step(line: string, i: int): tuple[lineBytes, validBytes: int] =
  ## The character of `line` at byte `i` as `toValidUtf8` writes it: its bytes
  ## in `line` and in the result. An undecodable byte becomes U+FFFD.
  let size = max(line.runeSizeAt(i), 1)
  if size == 1 and line[i].uint8 >= 0x80'u8:
    (1, "\uFFFD".len)
  else:
    (size, size)

proc hasInvalidUtf8*(line: string): bool =
  ## Check if `line` has invalid UTF-8 per `runeSizeAt`/`charLen` model.
  ## Invalid lines must not be passed to `regex` (asserts in debug, UB in release).
  var i = 0
  while i < line.len:
    let step = line.validUtf8Step(i)
    if step.lineBytes != step.validBytes:
      return true
    i += step.lineBytes
  false

proc toValidUtf8(line: string): string =
  ## Return `line` with undecodable bytes replaced by U+FFFD so the result is
  ## valid UTF-8 for `regex`. Each undecodable byte becomes one character, so
  ## character indices (`charLen`, `byteToCharPos`) agree between `line` and
  ## the result; regex matches on the result translate back by character.
  if not line.hasInvalidUtf8:
    return line
  result = newStringOfCap(line.len)
  var i = 0
  while i < line.len:
    let step = line.validUtf8Step(i)
    if step.lineBytes == step.validBytes:
      result.add(line[i ..< i + step.lineBytes])
    else:
      result.add("\uFFFD")
    i += step.lineBytes

type
  LiteralChar = object
    ## A pattern's character, as Vim's regexp compiler splits a pattern.
    base: Rune # Folded when compared ignoring case
    floating: bool # No base: composing characters, which any character may hold
    composing: seq[Rune]

  LiteralPattern = ref object
    ## Text * and # (smWord) and g* and g# (smLiteral) look for as it is, ready
    ## to match against each line.
    text: string
    chars: seq[LiteralChar]
    ignorecase: bool
    match: SearchMatch
    boundsStart, boundsEnd: bool # Vim's `\<` and `\>`
    exact: bool # A match is `text` byte for byte
    notFirst: set[char] # ASCII characters no match starts with

var literalCache: LiteralPattern

proc literalChars(runes: openArray[Rune], ignorecase: bool): seq[LiteralChar] =
  ## `runes` as characters. As in Vim's match_composing(), only a character
  ## without composing characters folds, and one that starts with a composing
  ## character has no base.
  var i = 0
  while i < runes.len:
    let next = runes.nextCharColumn(i)
    var c = LiteralChar(base: runes[i], floating: runes[i].isComposing)
    c.composing = @(runes.toOpenArray(i + (if c.floating: 0 else: 1), next - 1))
    if ignorecase and c.composing.len == 0:
      c.base = c.base.utfFold
    result.add(c)
    i = next

proc takes(want: LiteralChar, r: Rune, ignorecase: bool): bool =
  ## Whether `want` can match a character of the line whose first rune is `r`,
  ## its composing characters aside.
  want.floating or
    (if ignorecase and want.composing.len == 0: r.utfFold else: r) == want.base

proc literalPattern(
    text: string, ignorecase: bool, match: SearchMatch
): LiteralPattern =
  ## `text` ready to match. A word character at its start gets smWord's `\<`
  ## and one at its end its `\>`, as Vim's * puts them only there (`->` gets
  ## neither). The last one is kept, as the highlighter asks once per line.
  let c = literalCache
  if c != nil and c.text == text and c.ignorecase == ignorecase and c.match == match:
    return c
  let runes = text.toCharRunes
  result = LiteralPattern(
    text: text,
    chars: runes.literalChars(ignorecase),
    ignorecase: ignorecase,
    match: match,
  )
  if runes.len > 0 and match == smWord:
    result.boundsStart = mbClass(runes[0]) >= 2
    result.boundsEnd = mbClass(runes[runes.baseColumn(runes.high)]) >= 2
  result.exact = not ignorecase and runes.allIt(not it.isComposing)
  if runes.len > 0:
    for c in '\0' .. '\x7f':
      if not result.chars[0].takes(Rune(c.ord), ignorecase):
        result.notFirst.incl(c)
  literalCache = result

type LiteralMatch = object
  endByte: int # The byte after the match, -1 when there is none
  length: int # How many characters of the line it takes
  last: Rune # The match's last character
  lastBase: Rune # The character that one is part of

proc holdsComposing(line: string, bytePos: int, want: openArray[Rune]): bool =
  ## Whether the character at `bytePos` holds each of the composing characters
  ## `want`, in any order, as in Vim's match_composing().
  for c in want:
    var
      pos = bytePos
      prev = Rune(0)
      found = false
    while pos < line.len and not found:
      let (r, size) = line.charAtByte(pos)
      if pos > bytePos:
        if not continuesChar(prev, r):
          break
        found = r == c
      prev = r
      pos += size
    if not found:
      return false
  true

proc literalMatchAt(line: string, bytePos: int, p: LiteralPattern): LiteralMatch =
  ## The match of `p` that starts at `bytePos`, if any. A pattern's character
  ## with composing characters takes all the line's character holds. One
  ## without takes only the base, which a composing character can't then follow.
  result = LiteralMatch(endByte: -1)
  var
    pos = bytePos
    length = 0
    last, lastBase: Rune
  for want in p.chars:
    if pos >= line.len:
      return
    let (r, size) = line.charAtByte(pos)
    let held = want.floating or want.composing.len > 0
    if not want.takes(r, p.ignorecase) or
        (held and not line.holdsComposing(pos, want.composing)):
      return
    lastBase = r
    last = r
    pos += size
    length.inc
    while held and pos < line.len:
      let (next, nextSize) = line.charAtByte(pos)
      if not continuesChar(last, next):
        break
      last = next
      pos += nextSize
      length.inc
  result = LiteralMatch(endByte: pos, length: length, last: last, lastBase: lastBase)

type LiteralRange = object
  startCol, endCol: int # Half-open, in characters
  startByte, endByte: int # Half-open
  groups: seq[Slice[int]] # A regex match's groups, bytes in the line; empty when unset

iterator literalMatchRanges(line: string, p: LiteralPattern): LiteralRange =
  ## Matches of `p` on `line`, left to right. Each one is looked for after the
  ## one before ends, as Vim's search does with 'cpoptions' c. A character and
  ## its composing characters are one, as in Vim: no match starts or ends
  ## between them. Vim's `\<` takes a match that starts with a word character
  ## (mb_get_class 2 or more) of another class than the character before it,
  ## and `\>` one that ends with a word character of another class than the
  ## character after it.
  ## Walks the line without materialising a folded copy or its rune seq:
  ## callers that only need the first or last match stop early.
  if p.chars.len > 0 and not (p.exact and line.find(p.text) < 0):
    var
      bytePos = 0
      charIdx = 0
      free = 0 # The first column a match may start at
      prev = Rune(0)
      prevBase = Rune(0) # The character before
    while bytePos < line.len:
      if line[bytePos] in p.notFirst:
        prev = Rune(line[bytePos].ord)
        prevBase = prev
        inc bytePos
        inc charIdx
        continue
      let (r, size) = line.charAtByte(bytePos)
      if size == 0:
        break
      let composed = charIdx > 0 and continuesChar(prev, r)
      if not composed and charIdx >= free and p.chars[0].takes(r, p.ignorecase):
        let m = line.literalMatchAt(bytePos, p)
        var matches = m.endByte >= 0
        if matches and p.boundsStart:
          let class = mbClass(r)
          matches = class >= 2 and (charIdx == 0 or mbClass(prevBase) != class)
        if matches and m.endByte < line.len:
          let next = line.charAtByte(m.endByte)[0]
          matches = not continuesChar(m.last, next)
          if matches and p.boundsEnd:
            let class = mbClass(m.lastBase)
            matches = class >= 2 and mbClass(next) != class
        elif matches and p.boundsEnd:
          matches = mbClass(m.lastBase) >= 2
        if matches:
          yield LiteralRange(
            startCol: charIdx,
            endCol: charIdx + m.length,
            startByte: bytePos,
            endByte: m.endByte,
          )
          free = charIdx + m.length
      if not composed:
        prevBase = r
      prev = r
      bytePos += size
      inc charIdx

type LineWalk = object ## A place reached walking `line` and its `toValidUtf8` together.
  valid, pos, col: int # Bytes in the valid text and in `line`, and the column

proc walkTo(w: var LineWalk, line: string, valid: int) =
  ## `w` moved forward to the character starting at byte `valid` of the valid
  ## text.
  while w.valid < valid and w.pos < line.len:
    let step = line.validUtf8Step(w.pos)
    w.valid += step.validBytes
    w.pos += step.lineBytes
    w.col.inc

type MatchWalk = enum
  ## How a walk over a line's matches goes on from each, as Vim's
  mwSearch ## searchit does with 'cpoptions' c
  mwHighlight ## hlsearch does (next_search_hl)
  mwSubstitute ## do_sub does

iterator matchRanges(
    line, pattern: string,
    ignorecase: bool,
    match: SearchMatch,
    walk: MatchWalk,
    withGroups = false,
): LiteralRange =
  ## The matches of `pattern` on `line`, left to right, matching as `match`
  ## says, with a regex match's groups when `withGroups`. Each one is looked
  ## for where the one before ends, a character on after an empty one, and the
  ## end of the line only from its start, so an empty line has its empty
  ## match. After a match mwHighlight looks at the end of the line too, and
  ## mwSubstitute skips an empty match where the one before ended. An empty
  ## pattern has no matches.
  if pattern.len == 0:
    discard
  elif match != smRegex:
    for r in literalMatchRanges(line, literalPattern(pattern, ignorecase, match)):
      yield r
  else:
    let p = regexPattern(pattern, ignorecase)
    if p.re.isSome:
      let searchable = line.toValidUtf8
      var
        start = 0
        lastEnd = -1
        m = RegexMatch2()
        at = LineWalk()
      while (start == 0 or start < searchable.len or walk == mwHighlight) and
          find(searchable, p.re.get, m, start):
        let
          a = m.boundaries.a
          b = m.boundaries.b + 1
        if not (walk == mwSubstitute and a == b and a == lastEnd):
          at.walkTo(line, a)
          var to = at
          to.walkTo(line, b)
          var groups: seq[Slice[int]]
          if withGroups:
            groups = newSeqOfCap[Slice[int]](m.groupsCount)
            for g in 0 ..< m.groupsCount:
              let s = m.group(g)
              if s.a < 0 or s.a > s.b:
                groups.add(1 .. 0)
              else:
                # A group inside a lookbehind may start before the match.
                var first =
                  if s.a >= a:
                    at
                  else:
                    LineWalk()
                first.walkTo(line, s.a)
                var last = first
                last.walkTo(line, s.b + 1)
                groups.add(first.pos .. last.pos - 1)
          yield LiteralRange(
            startCol: at.col,
            endCol: to.col,
            startByte: at.pos,
            endByte: to.pos,
            groups: groups,
          )
          at = to
          lastEnd = b
        if a == b and b >= searchable.len:
          break
        start =
          if a == b:
            b + max(searchable.runeSizeAt(b), 1)
          else:
            b

proc cursorColumn(r: LiteralRange, line: string): int =
  ## The column the cursor goes to on match `r` of `line`. As in Vim's
  ## searchit, one at the end of the line counts as on its last character.
  if r.startByte == line.len and line.len > 0:
    r.startCol - 1
  else:
    r.startCol

proc findSearchMatchRanges*(
    b: TextBuffer,
    lineIndex: int,
    searchText: string,
    ignorecase = false,
    match = smRegex,
): seq[ColumnRange] =
  ## The matches of `searchText` on line `lineIndex` hlsearch highlights,
  ## matching as `match` says. Each is half-open [startCol, endCol), empty for
  ## an empty match.
  if lineIndex < 0 or lineIndex >= b.len:
    return @[]
  for r in b.getLine(lineIndex).matchRanges(searchText, ignorecase, match, mwHighlight):
    result.add(ColumnRange(startCol: r.startCol, endCol: r.endCol))

proc firstSubstituteMatch*(
    line, pattern: string, ignorecase: bool, match: SearchMatch
): Option[ColumnRange] =
  ## The columns of the first match of `pattern` :s would replace on `line`.
  for r in line.matchRanges(pattern, ignorecase, match, mwSubstitute):
    return some(ColumnRange(startCol: r.startCol, endCol: r.endCol))

proc countSubstituteMatches*(
    line, pattern: string, ignorecase, everyMatch: bool, match: SearchMatch
): int =
  ## How many matches of `pattern` :s would replace on `line`.
  for r in line.matchRanges(pattern, ignorecase, match, mwSubstitute):
    result.inc
    if not everyMatch:
      break

type
  LetterCase = enum
    lcKeep
    lcUpper
    lcLower

  ReplacementPieceKind = enum
    rpText
    rpGroup ## & and \0 to \9
    rpCase ## \u \l \U \L \e \E
    rpLineBreak ## \r and a typed CR

  ReplacementPiece = object
    case kind: ReplacementPieceKind
    of rpText:
      text: string
    of rpGroup:
      group: int
    of rpCase:
      oneChar: bool # \u and \l
      to: LetterCase # lcKeep for \e and \E, which end both
    of rpLineBreak:
      discard

  Replacement* = object ## The replacement of :s, as Vim's regsub() reads it
    pieces: seq[ReplacementPiece]
    usesGroups: bool # Has \1 to \9

proc parseReplacement*(s: string): Replacement =
  ## `s` as Vim reads a :s replacement with 'magic': `&` and `\0` are the
  ## match, `\1` to `\9` its groups, `\u` `\l` `\U` `\L` `\e` `\E` change
  ## the case, `\r` and a typed CR break the line, `\n` and a typed NUL are a
  ## NUL, `\t` and `\b` are Tab and Ctrl-H, and a backslash before any
  ## other character takes it as it is. Unlike Vim, `~` is not the previous
  ## replacement and `\=` is a plain `=`.
  var text = ""
  template flush() =
    if text.len > 0:
      result.pieces.add(ReplacementPiece(kind: rpText, text: text))
      text = ""

  template add(piece: ReplacementPiece) =
    flush()
    result.pieces.add(piece)

  template caseChange(one: bool, letterCase: LetterCase) =
    add(ReplacementPiece(kind: rpCase, oneChar: one, to: letterCase))

  var i = 0
  while i < s.len:
    let c = s[i]
    if c == '&':
      add(ReplacementPiece(kind: rpGroup, group: 0))
    elif c == '\\' and i + 1 < s.len:
      i.inc
      case s[i]
      of '0' .. '9':
        add(ReplacementPiece(kind: rpGroup, group: s[i].ord - '0'.ord))
        if s[i] != '0':
          result.usesGroups = true
      of 'u':
        caseChange(true, lcUpper)
      of 'l':
        caseChange(true, lcLower)
      of 'U':
        caseChange(false, lcUpper)
      of 'L':
        caseChange(false, lcLower)
      of 'e', 'E':
        caseChange(false, lcKeep)
      of 'n', '\n':
        text.add('\0')
      of 't':
        text.add('\t')
      of 'b':
        text.add('\b')
      of 'r':
        add(ReplacementPiece(kind: rpLineBreak))
      else:
        text.add(s[i])
    elif c == '\r':
      add(ReplacementPiece(kind: rpLineBreak))
    elif c == '\n':
      # A NUL typed on the command line, which keeps one as a line feed.
      text.add('\0')
    else:
      text.add(c)
    i.inc
  flush()

proc emit(res: var string, s: string, one: var LetterCase, all: LetterCase) =
  ## `s` added to `res` with the pending case changes applied. A byte that is
  ## not a character uses up a change of one, as in Vim, but stays as it is.
  if one == lcKeep and all == lcKeep:
    res.add(s)
    return
  var i = 0
  while i < s.len:
    let
      (rune, size) = s.charAtByte(i)
      change = if one != lcKeep: one else: all
    one = lcKeep
    if rune.isInvalidByteRune:
      res.add(s[i])
    else:
      case change
      of lcKeep:
        res.add(s[i ..< i + size])
      of lcUpper:
        res.add($rune.toUpper)
      of lcLower:
        res.add($rune.toLower)
    i += size

proc expand(r: Replacement, line: string, m: LiteralRange, lines: var seq[string]) =
  ## `r` for the match `m` on `line`, appended to `lines` with a line break
  ## starting a new one. A one-character case change waits for the next
  ## character and wins over an all-case change; a line break uses it up.
  var one, all = lcKeep
  for piece in r.pieces:
    case piece.kind
    of rpText:
      lines[^1].emit(piece.text, one, all)
    of rpGroup:
      let span =
        if piece.group == 0:
          m.startByte ..< m.endByte
        elif piece.group <= m.groups.len:
          m.groups[piece.group - 1]
        else:
          1 .. 0
      if span.a <= span.b:
        lines[^1].emit(line[span], one, all)
    of rpCase:
      if piece.oneChar:
        one = piece.to
      else:
        all = piece.to
        if piece.to == lcKeep:
          one = lcKeep
    of rpLineBreak:
      one = lcKeep
      lines.add("")

proc substituteMatches*(
    line, pattern: string,
    replacement: Replacement,
    ignorecase, everyMatch: bool,
    match: SearchMatch,
): tuple[lines: seq[string], count: int] =
  ## The lines `line` becomes with the first match, or every match, replaced,
  ## and how many; no lines when none.
  var copied = 0
  let withGroups = replacement.usesGroups
  for r in line.matchRanges(pattern, ignorecase, match, mwSubstitute, withGroups):
    if result.count == 0:
      result.lines = @[""]
    result.lines[^1].add(line[copied ..< r.startByte])
    replacement.expand(line, r, result.lines)
    result.count.inc
    copied = r.endByte
    if not everyMatch:
      break
  if result.count > 0:
    result.lines[^1].add(line[copied .. line.high])

iterator substitutions*(
    b: TextBuffer,
    rows: Slice[int],
    pattern: string,
    replacement: Replacement,
    ignorecase, everyMatch: bool,
    match: SearchMatch,
): tuple[line: int, lines: seq[string], count: int] =
  ## What :s makes of each line of `rows` it changes, top down. The buffer
  ## must not change while it runs; the caller writes them all at once.
  for row in max(rows.a, 0) .. min(rows.b, b.len - 1):
    var s = b.getLine(row).substituteMatches(
        pattern, replacement, ignorecase, everyMatch, match
      )
    if s.count > 0:
      yield (line: row, lines: move s.lines, count: s.count)

proc matchAt*(
    b: TextBuffer,
    pos: BufferPosition,
    searchText: string,
    ignorecase = false,
    match = smRegex,
): Option[ColumnRange] =
  ## The match of `searchText` a search goes through that the cursor at `pos`
  ## is on, matching as `match` says: one it stands in, an empty one where it
  ## stands, or one at the end of the line when it is on the last character,
  ## with its composing characters, where a search puts it.
  if pos.line < 0 or pos.line >= b.len or pos.column < 0:
    return none(ColumnRange)
  let
    line = b.getLine(pos.line)
    charEnd = line.toCharRunes.nextCharColumn(pos.column)
  for r in line.matchRanges(searchText, ignorecase, match, mwSearch):
    let cols = ColumnRange(startCol: r.startCol, endCol: r.endCol)
    if cols.covers(pos.column) or r.cursorColumn(line) in pos.column ..< charEnd:
      return some(cols)
    if r.startCol > pos.column:
      break
  none(ColumnRange)

type LineMatch* = object ## A match a search reaches
  line*: int
  cols*: ColumnRange

proc start*(m: LineMatch): BufferPosition =
  ## Where `m` starts.
  BufferPosition(line: m.line, column: m.cols.startCol)

proc findMatchFrom*(
    b: TextBuffer,
    searchText: string,
    startPos: BufferPosition,
    ignorecase: bool,
    match: SearchMatch,
    direction: SearchDirection,
): Option[LineMatch] =
  ## The match of `searchText` a search from `startPos` reaches first, going
  ## `direction`, of those it goes through (`matchRanges`). It wraps around up
  ## to and including the start line, which it takes whole as the second
  ## round of Vim's searchit does: the only match is found again.
  if startPos.line < 0 or startPos.line >= b.len or
      not searchText.isSearchable(ignorecase, match):
    return none(LineMatch)

  let forward = direction == Forward
  proc pick(row, limit: int): Option[LineMatch] =
    ## The first match on `row` past the character at column `limit` going
    ## forward, the last one before it going back; any when `limit` is
    ## negative. As in Vim's searchit, the character takes its composing
    ## characters with it.
    let
      line = b.getLine(row)
      past =
        if forward and limit >= 0:
          line.toCharRunes.nextCharColumn(limit)
        else:
          0
    for r in line.matchRanges(searchText, ignorecase, match, mwSearch):
      let found =
        LineMatch(line: row, cols: ColumnRange(startCol: r.startCol, endCol: r.endCol))
      if forward:
        if r.cursorColumn(line) >= past:
          return some(found)
      elif limit < 0 or r.startCol < limit:
        result = some(found)
      else:
        break

  # Going back from a negative column, nothing on the start line comes
  # before. Going forward from one, the first pick takes the line whole.
  let
    limit =
      if forward:
        startPos.column
      else:
        max(startPos.column, 0)
    rounds =
      if forward and startPos.column < 0:
        b.len - 1
      else:
        b.len
  result = pick(startPos.line, limit)
  for i in 1 .. rounds:
    if result.isSome:
      break
    result = pick((startPos.line + (if forward: i else: b.len - i)) mod b.len, -1)

template byteSliceEqualsWord(
    line: string, startByte, endByte: int, word: string
): bool =
  ## Compare `line[startByte..<endByte]` to `word` without allocation.
  ## Byte equality holds for UTF-8; allocation-free for render hot path.
  ## `block` expression (no `return`) — pass side-effect-free args only.
  block:
    var eq = endByte - startByte == word.len
    if eq:
      for k in 0 ..< word.len:
        if line[startByte + k] != word[k]:
          eq = false
          break
    eq

proc findWordMatchRanges*(
    b: TextBuffer, lineIndex: int, word: string, excludeCol: int = -1
): seq[ColumnRange] =
  ## Find all occurrences of `word` on a given line, returning ColumnRange results.
  ## If `excludeCol` >= 0, the word containing that column is excluded from results.
  ## This allows O(1) per-character lookup instead of O(n) per character.

  if word.len == 0:
    return @[]

  if lineIndex < 0 or lineIndex >= b.len:
    return @[]

  let line = b.getLine(lineIndex)
  if line.len == 0:
    return @[]

  # Scan word runs by column [runStartCol, col) and bytes [runStartByte, bytePos).
  # Byte-slice compare avoids allocating seq[Rune]/strings per frame.
  var
    col = 0
    bytePos = 0
    runStartCol = -1
    runStartByte = 0

  while bytePos < line.len:
    # `charAtByte` keeps `col` in sync with buffer/renderer.
    let charStartByte = bytePos
    let (r, size) = line.charAtByte(bytePos)
    bytePos += size
    if isWordChar(r):
      if runStartCol < 0:
        runStartCol = col
        runStartByte = charStartByte
    elif runStartCol >= 0:
      # Word run ends; emit if matches.
      if byteSliceEqualsWord(line, runStartByte, charStartByte, word) and
          not (excludeCol >= 0 and excludeCol >= runStartCol and excludeCol < col):
        result.add(ColumnRange(startCol: runStartCol, endCol: col))
      runStartCol = -1
    inc col

  # Emit trailing word run at EOL.
  if runStartCol >= 0 and byteSliceEqualsWord(line, runStartByte, bytePos, word) and
      not (excludeCol >= 0 and excludeCol >= runStartCol and excludeCol < col):
    result.add(ColumnRange(startCol: runStartCol, endCol: col))

proc identInLine*(line: string, column: int, ident = true): Option[ColumnRange] =
  ## The text * and # search for, as Vim's find_ident_under_cursor() finds it
  ## in `line`: the keyword under or after `column`, else the non-blank text
  ## there. A keyword is a run of word characters of one class (mb_get_class),
  ## so `日本` in `abc日本def` is one; the text runs on to a blank. A character
  ## takes its composing characters with it. Without `ident`, the whole run of
  ## non-blanks there (FIND_STRING alone).
  let runes = line.toCharRunes

  proc class(col: int): int =
    if col < runes.len:
      mbClass(runes[runes.baseColumn(col)])
    else:
      0

  let start =
    if column < runes.len:
      runes.baseColumn(max(column, 0))
    else:
      runes.len
  var
    col = start
    keyword = ident
  if ident:
    while col < runes.len and class(col) < 2:
      col = runes.nextCharColumn(col)
  if not ident or col >= runes.len:
    keyword = false
    col = start
    while col < runes.len and class(col) == 0:
      col = runes.nextCharColumn(col)
    if col >= runes.len:
      return none(ColumnRange)

  let startClass = class(col)
  proc sameRun(col: int): bool =
    if ident:
      class(col) == startClass
    else:
      class(col) != 0

  while col > 0 and sameRun(col - 1):
    col = runes.baseColumn(col - 1)
  var endCol = col
  while endCol < runes.len and
      (if keyword: class(endCol) == startClass else: class(endCol) != 0):
    endCol = runes.nextCharColumn(endCol)
  some(ColumnRange(startCol: col, endCol: endCol))

proc identUnderCursor*(b: TextBuffer, pos: BufferPosition): Option[ColumnRange] =
  ## `identInLine` on the line of `pos`.
  if pos.line < 0 or pos.line >= b.len:
    return none(ColumnRange)
  b.getLine(pos.line).identInLine(pos.column)
