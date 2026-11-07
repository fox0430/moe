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
    smRegex ## As a regex (/ and ?)
    smLiteral ## As it is (g* and g#)
    smPlain ## As it is, typed, so 'smartcase' holds (:s)
    smWord
      ## As it is, a word character at either end starting or ending a word, as
      ## the `\<` and `\>` Vim's * and # put around a keyword

  CachedRegex = object
    pattern: string
    ignorecase: bool
    compiled: Regex2

var regexCache: Option[CachedRegex]

proc compileSearchRegex*(pattern: string, ignorecase: bool): Option[Regex2] =
  ## Compile a search pattern as a regex.
  ## Returns none if the pattern is empty or invalid.
  ## Results are cached for repeated searches with the same pattern.
  if pattern.len == 0:
    return none(Regex2)
  if regexCache.isSome:
    let c = regexCache.get
    if c.pattern == pattern and c.ignorecase == ignorecase:
      return some(c.compiled)
  try:
    let flags =
      if ignorecase:
        {regexCaseless}
      else:
        default(set[RegexFlag])
    let compiled = re2(pattern, flags)
    regexCache =
      some(CachedRegex(pattern: pattern, ignorecase: ignorecase, compiled: compiled))
    return some(compiled)
  except RegexError:
    return none(Regex2)

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
    ## Text * and # (smWord), g* and g# (smLiteral) and :s (smPlain) look for as
    ## it is, ready to match against each line.
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

proc matchAt(line: string, bytePos: int, p: LiteralPattern): LiteralMatch =
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
        let m = line.matchAt(bytePos, p)
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

proc findSearchMatchRanges*(
    b: TextBuffer,
    lineIndex: int,
    searchText: string,
    ignorecase = false,
    match = smRegex,
): seq[ColumnRange] =
  ## Find all search match ranges on a given line, matching as `match` says.
  ## Returns a seq of ColumnRange (half-open [startCol, endCol)).

  if searchText.len == 0:
    return @[]

  if lineIndex < 0 or lineIndex >= b.len:
    return @[]

  let line = b.getLine(lineIndex)
  if line.len == 0:
    return @[]

  if match != smRegex:
    for r in literalMatchRanges(line, literalPattern(searchText, ignorecase, match)):
      result.add(ColumnRange(startCol: r.startCol, endCol: r.endCol))
  else:
    # Regex matching (undecodable bytes replaced for `regex` safety)
    let compiled = compileSearchRegex(searchText, ignorecase)
    if compiled.isNone:
      return @[]
    let re = compiled.get

    let searchable = line.toValidUtf8
    var searchBytePos = 0
    var m = RegexMatch2()
    while searchBytePos <= searchable.len:
      if not find(searchable, re, m, searchBytePos):
        break
      let startChar = byteToCharPos(searchable, m.boundaries.a)
      let endChar = byteToCharPos(searchable, m.boundaries.b + 1)
      result.add(ColumnRange(startCol: startChar, endCol: endChar))
      # Advance past match (avoid infinite loop on zero-width)
      searchBytePos = max(m.boundaries.a + 1, m.boundaries.b + 1)

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

iterator substituteRanges(
    line, pattern: string, ignorecase: bool, match: SearchMatch, withGroups = false
): LiteralRange =
  ## The matches of `pattern` :s replaces on `line`, left to right, matching as
  ## `match` says, with their groups when `withGroups`. As in Vim's do_sub, an
  ## empty regex match where the one before ended is skipped, and the line is
  ## done once the search reaches its end.
  if match != smRegex:
    for r in literalMatchRanges(line, literalPattern(pattern, ignorecase, match)):
      yield r
  else:
    let compiled = compileSearchRegex(pattern, ignorecase)
    if compiled.isSome:
      let
        re = compiled.get
        searchable = line.toValidUtf8
      var
        start = 0
        lastEnd = -1
        m = RegexMatch2()
        at = LineWalk()
      while (start == 0 or start < searchable.len) and find(searchable, re, m, start):
        let
          a = m.boundaries.a
          b = m.boundaries.b + 1
        if a == b and a == lastEnd:
          if a >= searchable.len:
            break
          start = a + max(searchable.runeSizeAt(a), 1)
          continue
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
        if b >= searchable.len:
          break
        start = b

proc firstSubstituteMatch*(
    line, pattern: string, ignorecase: bool, match = smPlain
): Option[int] =
  ## The column of the first match of `pattern` :s would replace on `line`.
  for r in line.substituteRanges(pattern, ignorecase, match):
    return some(r.startCol)

proc countSubstituteMatches*(
    line, pattern: string, ignorecase, everyMatch: bool, match = smPlain
): int =
  ## How many matches of `pattern` :s would replace on `line`.
  for r in line.substituteRanges(pattern, ignorecase, match):
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

  ReplacementPiece = object
    case kind: ReplacementPieceKind
    of rpText:
      text: string
      asTyped: bool # No case change touches it, though it uses one of one up
    of rpGroup:
      group: int
    of rpCase:
      oneChar: bool # \u and \l
      to: LetterCase # lcKeep for \e and \E, which end both

  Replacement* = object ## The replacement of :s, as Vim's regsub() reads it
    pieces: seq[ReplacementPiece]
    usesGroups: bool # Has \1 to \9

proc parseReplacement*(s: string): Replacement =
  ## `s` as Vim reads a :s replacement with 'magic': `&` and `\0` are the
  ## match, `\1` to `\9` its groups, `\u` `\l` `\U` `\L` `\e` `\E` change
  ## the case, `\t` and `\b` are Tab and Ctrl-H, and a backslash before any
  ## other character takes it as it is. Unlike Vim, `~` is not the previous
  ## replacement, `\=` is a plain `=`, `\n` is a line break that doesn't
  ## split the line, and `\r` stays as typed, as moe can't split a line here.
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
      of 'n':
        text.add('\n')
      of 't':
        text.add('\t')
      of 'b':
        text.add('\b')
      of 'r':
        add(ReplacementPiece(kind: rpText, text: "\\r", asTyped: true))
      else:
        text.add(s[i])
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

proc expand(r: Replacement, line: string, m: LiteralRange): string =
  ## `r` for the match `m` on `line`. A case change of one character waits for
  ## the next character, wherever it comes from, and wins over one of all.
  var one, all = lcKeep
  for piece in r.pieces:
    case piece.kind
    of rpText:
      if piece.asTyped:
        result.add(piece.text)
        one = lcKeep
      else:
        result.emit(piece.text, one, all)
    of rpGroup:
      let span =
        if piece.group == 0:
          m.startByte ..< m.endByte
        elif piece.group <= m.groups.len:
          m.groups[piece.group - 1]
        else:
          1 .. 0
      if span.a <= span.b:
        result.emit(line[span], one, all)
    of rpCase:
      if piece.oneChar:
        one = piece.to
      else:
        all = piece.to
        if piece.to == lcKeep:
          one = lcKeep

proc substituteMatches*(
    line, pattern: string,
    replacement: Replacement,
    ignorecase, everyMatch: bool,
    match = smPlain,
): tuple[text: string, count: int] =
  ## `line` with the first match of `pattern`, or `everyMatch`, replaced, and
  ## how many were.
  var copied = 0
  let withGroups = replacement.usesGroups
  for r in line.substituteRanges(pattern, ignorecase, match, withGroups):
    result.text.add(line[copied ..< r.startByte])
    result.text.add(replacement.expand(line, r))
    result.count.inc
    copied = r.endByte
    if not everyMatch:
      break
  if result.count > 0:
    result.text.add(line[copied .. line.high])

proc matchEndCol*(
    b: TextBuffer,
    pos: BufferPosition,
    searchText: string,
    ignorecase = false,
    match = smRegex,
): Option[int] =
  ## The end column (exclusive) of the match that starts at `pos`, which
  ## findNext can land on when it overlaps a match findSearchMatchRanges took.
  if searchText.len == 0 or pos.line < 0 or pos.line >= b.len:
    return none(int)
  let line = b.getLine(pos.line)
  if match != smRegex:
    for r in literalMatchRanges(line, literalPattern(searchText, ignorecase, match)):
      if r.startCol == pos.column:
        return some(r.endCol)
    return none(int)
  let compiled = compileSearchRegex(searchText, ignorecase)
  if compiled.isNone:
    return none(int)
  let
    searchable = line.toValidUtf8
    start = charToBytePos(searchable, pos.column)
  var m = RegexMatch2()
  if find(searchable, compiled.get, m, start) and m.boundaries.a == start:
    some(byteToCharPos(searchable, m.boundaries.b + 1))
  else:
    none(int)

proc findNext*(
    b: TextBuffer,
    searchText: string,
    startPos: BufferPosition,
    ignorecase = false,
    match = smRegex,
): Option[BufferPosition] =
  ## Find the next occurrence of searchText starting from startPos, matching as
  ## `match` says, the definition findSearchMatchRanges highlights with.
  ## Returns the position of the match or none if not found.
  ## The search wraps around from the beginning if not found after startPos,
  ## up to and including startPos: the only match is found again, as Vim does.
  ## Unicode-aware: All positions are in character (rune) indices, not byte indices.
  if searchText.len == 0:
    return none(BufferPosition)

  let lineCount = b.len
  if lineCount == 0:
    return none(BufferPosition)

  if startPos.line < 0 or startPos.line >= lineCount:
    return none(BufferPosition)

  var
    re: Regex2
    literal: LiteralPattern
  if match == smRegex:
    let compiled = compileSearchRegex(searchText, ignorecase)
    if compiled.isNone:
      return none(BufferPosition)
    re = compiled.get
  else:
    literal = literalPattern(searchText, ignorecase, match)

  # Find first match in `line` at or after startCharCol, or -1.
  # Undecodable bytes are replaced with U+FFFD so `regex` only sees valid UTF-8.
  proc searchLine(line: string, startCharCol = 0): int =
    if line.len == 0:
      return -1
    let lineCharLen = line.charLen
    if startCharCol >= lineCharLen:
      return -1
    let clampedStartCol = max(0, min(startCharCol, lineCharLen))
    let searchable = line.toValidUtf8
    let startByteCol = charToBytePos(searchable, clampedStartCol)
    if startByteCol > searchable.len:
      return -1
    var m = RegexMatch2()
    if find(searchable, re, m, startByteCol):
      return byteToCharPos(searchable, m.boundaries.a)
    return -1

  proc firstMatchCol(line: string, startCharCol: int): int =
    ## First match start column at or after startCharCol, or -1.
    if match != smRegex:
      for r in literalMatchRanges(line, literal):
        if r.startCol >= startCharCol:
          return r.startCol
      return -1
    searchLine(line, startCharCol)

  # Search rest of current line
  let currentLine = b.getLine(startPos.line)
  let currentLineCharLen = currentLine.charLen
  let searchStartCol =
    if startPos.column < 0:
      0
    else:
      min(startPos.column + 1, currentLineCharLen)

  let idx = firstMatchCol(currentLine, searchStartCol)
  if idx >= 0 and (startPos.column < 0 or idx > startPos.column):
    return some(BufferPosition(line: startPos.line, column: idx))

  # Search remaining lines after current
  for lineIdx in (startPos.line + 1) ..< lineCount:
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue
    let idx = firstMatchCol(line, 0)
    if idx >= 0:
      return some(BufferPosition(line: lineIdx, column: idx))

  # Wrap around to the current line, taking that one whole as the second round
  # of Vim's searchit does: a match after startPos would have been found first.
  # From before the line (column -1), the first pass took it whole already.
  for lineIdx in 0 .. (if startPos.column < 0: startPos.line - 1
  else: startPos.line):
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue
    let idx = firstMatchCol(line, 0)
    if idx >= 0:
      return some(BufferPosition(line: lineIdx, column: idx))

  return none(BufferPosition)

proc findPrev*(
    b: TextBuffer,
    searchText: string,
    startPos: BufferPosition,
    ignorecase = false,
    match = smRegex,
): Option[BufferPosition] =
  ## Find the previous occurrence of searchText starting from startPos,
  ## matching as `match` says, the definition findSearchMatchRanges highlights
  ## with. Returns the position of the match or none if not found.
  ## The search wraps around from the end if not found before startPos, down
  ## to and including startPos: the only match is found again, as Vim does.
  ## Unicode-aware: All positions are in character (rune) indices, not byte indices.
  if searchText.len == 0:
    return none(BufferPosition)

  let lineCount = b.len
  if lineCount == 0:
    return none(BufferPosition)

  if startPos.line < 0 or startPos.line >= lineCount:
    return none(BufferPosition)

  var
    re: Regex2
    literal: LiteralPattern
  if match == smRegex:
    let compiled = compileSearchRegex(searchText, ignorecase)
    if compiled.isNone:
      return none(BufferPosition)
    re = compiled.get
  else:
    literal = literalPattern(searchText, ignorecase, match)

  # Find last match with start < maxCharCol (<0 = no limit).
  proc findLastInLine(line: string, maxCharCol = -1): int =
    if line.len == 0:
      return -1
    let searchable = line.toValidUtf8
    let lineCharLen = searchable.charLen
    let searchCharLimit =
      if maxCharCol < 0:
        lineCharLen
      elif maxCharCol == 0:
        0
      else:
        min(maxCharCol, lineCharLen)

    var lastCharIdx = -1
    var searchBytePos = 0
    var m = RegexMatch2()
    while searchBytePos <= searchable.len:
      if not find(searchable, re, m, searchBytePos):
        break
      let charIdx = byteToCharPos(searchable, m.boundaries.a)
      if maxCharCol >= 0 and charIdx >= searchCharLimit:
        break
      lastCharIdx = charIdx
      # Advance past match (avoid infinite loop on zero-width)
      searchBytePos = max(m.boundaries.a + 1, m.boundaries.b + 1)
    return lastCharIdx

  proc lastMatchCol(line: string, maxCharCol: int): int =
    ## Last match start column before maxCharCol (<0 = no limit), or -1.
    if match != smRegex:
      result = -1
      for r in literalMatchRanges(line, literal):
        if maxCharCol >= 0 and r.startCol >= maxCharCol:
          break
        result = r.startCol
      return
    findLastInLine(line, maxCharCol)

  # Search backwards in current line
  let currentLine = b.getLine(startPos.line)
  let currentLineCharLen = currentLine.charLen

  if startPos.column >= 0:
    let clampedColumn = min(startPos.column, currentLineCharLen)
    let lastIdx = lastMatchCol(currentLine, clampedColumn)
    if lastIdx >= 0 and lastIdx < clampedColumn:
      return some(BufferPosition(line: startPos.line, column: lastIdx))

  # Search lines before current line (backwards)
  for lineIdx in countdown(startPos.line - 1, 0):
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue
    let lastIdx = lastMatchCol(line, -1)
    if lastIdx >= 0:
      return some(BufferPosition(line: lineIdx, column: lastIdx))

  # Wrap around: search from end to current line, taking that one whole as the
  # second round of Vim's searchit does: a match before startPos would have
  # been found first.
  for lineIdx in countdown(lineCount - 1, startPos.line):
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue
    let lastIdx = lastMatchCol(line, -1)
    if lastIdx >= 0:
      return some(BufferPosition(line: lineIdx, column: lastIdx))

  return none(BufferPosition)

proc isPositionInSearchMatch*(
    b: TextBuffer,
    pos: BufferPosition,
    searchText: string,
    ignorecase = false,
    match = smRegex,
): bool =
  ## Check if the given position is within a search match.
  if searchText.len == 0:
    return false
  if pos.line < 0 or pos.line >= b.len:
    return false

  let ranges = b.findSearchMatchRanges(pos.line, searchText, ignorecase, match)
  for r in ranges:
    if pos.column >= r.startCol and pos.column < r.endCol:
      return true
    if r.startCol > pos.column:
      return false
  return false

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
