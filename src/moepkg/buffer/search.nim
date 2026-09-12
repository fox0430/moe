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
## whole-word / current-word match enumeration. Compiled regexes are memoised
## in a single private slot to avoid recompiling on every keystroke.

import std/[options, strutils, unicode]

import pkg/regex

import ../[primitives, search_utils, unicode_utils]
import core

type CachedRegex = object
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

proc hasInvalidUtf8*(line: string): bool =
  ## Check if `line` has invalid UTF-8 per `runeSizeAt`/`charLen` model.
  ## Invalid lines must not be passed to `regex` (asserts in debug, UB in release).
  var i = 0
  while i < line.len:
    let sz = line.runeSizeAt(i)
    if sz == 0:
      # Defensive: unreachable while `i < line.len`.
      return true
    if sz == 1 and line[i].uint8 >= 0x80'u8:
      return true
    i += sz
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
    let sz = line.runeSizeAt(i)
    if sz == 0:
      # Defensive: a zero step would loop forever.
      break
    if sz == 1 and line[i].uint8 >= 0x80'u8:
      result.add("\uFFFD")
      inc i
    else:
      result.add(line[i ..< i + sz])
      i += sz

proc matchesPreparedAt(
    line: string, needle: string, bytePos: int, ignorecase: bool
): bool =
  ## Compare `needle` (already lowered when ignorecase) against `line` at
  ## `bytePos` without lowering a copy of the whole line.
  if bytePos + needle.len > line.len:
    return false
  for k in 0 ..< needle.len:
    let c =
      if ignorecase:
        line[bytePos + k].toLowerAscii
      else:
        line[bytePos + k]
    if c != needle[k]:
      return false
  true

iterator wholeWordMatchRanges(
    line: string, searchText: string, ignorecase: bool
): ColumnRange =
  ## Whole-word matches on `line`, left to right, without materialising a
  ## lowercased copy of the line or its rune seq: callers that only need the
  ## first or last match stop early instead of collecting every match.
  let needle = prepareSearchString(searchText, ignorecase)
  let needleCharLen = searchText.charLen
  if needle.len > 0 and needleCharLen > 0:
    var bytePos = 0
    var charIdx = 0
    var prevIsWordChar = false
    while bytePos + needle.len <= line.len:
      let size = line.runeSizeAt(bytePos)
      if size == 0:
        break
      if not prevIsWordChar and line.matchesPreparedAt(needle, bytePos, ignorecase):
        # Step the end in the line's own character model, as `charLen` counts.
        var endByte = bytePos
        for _ in 0 ..< needleCharLen:
          if endByte >= line.len:
            break
          endByte += line.runeSizeAt(endByte)
        let endIsWordChar =
          endByte < line.len and isWordChar(line.charAtByte(endByte)[0])
        if not endIsWordChar:
          yield ColumnRange(startCol: charIdx, endCol: charIdx + needleCharLen)
      prevIsWordChar = isWordChar(line.charAtByte(bytePos)[0])
      bytePos += size
      inc charIdx

proc findSearchMatchRanges*(
    b: TextBuffer,
    lineIndex: int,
    searchText: string,
    ignorecase = false,
    wholeWord = false,
): seq[ColumnRange] =
  ## Find all search match ranges on a given line.
  ## Returns a seq of ColumnRange (half-open [startCol, endCol)).
  ## When wholeWord is true, uses literal matching with word boundary checks.
  ## Otherwise uses regex matching.

  if searchText.len == 0:
    return @[]

  if lineIndex < 0 or lineIndex >= b.len:
    return @[]

  let line = b.getLine(lineIndex)
  if line.len == 0:
    return @[]

  if wholeWord:
    # Literal matching with word boundary checks (for * and # commands)
    for r in wholeWordMatchRanges(line, searchText, ignorecase):
      result.add(r)
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

proc findNext*(
    b: TextBuffer,
    searchText: string,
    startPos: BufferPosition,
    ignorecase = false,
    wholeWord = false,
): Option[BufferPosition] =
  ## Find the next occurrence of searchText (regex) starting from startPos.
  ## When wholeWord is true, matches literally with word boundaries instead,
  ## the definition findSearchMatchRanges highlights with.
  ## Returns the position of the match or none if not found.
  ## The search wraps around from the beginning if not found after startPos.
  ## Unicode-aware: All positions are in character (rune) indices, not byte indices.
  if searchText.len == 0:
    return none(BufferPosition)

  let lineCount = b.len
  if lineCount == 0:
    return none(BufferPosition)

  if startPos.line < 0 or startPos.line >= lineCount:
    return none(BufferPosition)

  var re: Regex2
  if not wholeWord:
    let compiled = compileSearchRegex(searchText, ignorecase)
    if compiled.isNone:
      return none(BufferPosition)
    re = compiled.get

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
    if wholeWord:
      for r in wholeWordMatchRanges(line, searchText, ignorecase):
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

  # Wrap around
  for lineIdx in 0 .. startPos.line:
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue
    if lineIdx == startPos.line:
      if startPos.column < 0:
        continue
      let idx = firstMatchCol(line, 0)
      if idx >= 0 and idx < startPos.column:
        return some(BufferPosition(line: lineIdx, column: idx))
    else:
      let idx = firstMatchCol(line, 0)
      if idx >= 0:
        return some(BufferPosition(line: lineIdx, column: idx))

  return none(BufferPosition)

proc findPrev*(
    b: TextBuffer,
    searchText: string,
    startPos: BufferPosition,
    ignorecase = false,
    wholeWord = false,
): Option[BufferPosition] =
  ## Find the previous occurrence of searchText (regex) starting from startPos.
  ## When wholeWord is true, matches literally with word boundaries instead,
  ## the definition findSearchMatchRanges highlights with.
  ## Returns the position of the match or none if not found.
  ## The search wraps around from the end if not found before startPos.
  ## Unicode-aware: All positions are in character (rune) indices, not byte indices.
  if searchText.len == 0:
    return none(BufferPosition)

  let lineCount = b.len
  if lineCount == 0:
    return none(BufferPosition)

  if startPos.line < 0 or startPos.line >= lineCount:
    return none(BufferPosition)

  var re: Regex2
  if not wholeWord:
    let compiled = compileSearchRegex(searchText, ignorecase)
    if compiled.isNone:
      return none(BufferPosition)
    re = compiled.get

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
    if wholeWord:
      result = -1
      for r in wholeWordMatchRanges(line, searchText, ignorecase):
        if maxCharCol >= 0 and r.startCol >= maxCharCol:
          break
        result = r.startCol
      return
    findLastInLine(line, maxCharCol)

  proc lastMatchColFrom(line: string, minCharCol: int): int =
    ## Last match start column at or after minCharCol, or -1.
    result = -1
    if wholeWord:
      for r in wholeWordMatchRanges(line, searchText, ignorecase):
        if r.startCol >= minCharCol:
          result = r.startCol
      return

    let searchable = line.toValidUtf8
    var searchBytePos = charToBytePos(searchable, minCharCol)
    var m = RegexMatch2()
    while searchBytePos <= searchable.len:
      if not find(searchable, re, m, searchBytePos):
        break
      result = byteToCharPos(searchable, m.boundaries.a)
      # Advance past match (avoid infinite loop on zero-width)
      searchBytePos = max(m.boundaries.a + 1, m.boundaries.b + 1)

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

  # Wrap around: search from end to current line
  for lineIdx in countdown(lineCount - 1, startPos.line):
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue

    if lineIdx == startPos.line:
      let lineCharLen = line.charLen
      let searchStartCharCol =
        if startPos.column < 0:
          0
        else:
          min(startPos.column + 1, lineCharLen)
      if searchStartCharCol >= lineCharLen:
        continue

      let lastCharIdx = lastMatchColFrom(line, searchStartCharCol)
      if lastCharIdx >= 0 and (startPos.column < 0 or lastCharIdx > startPos.column):
        return some(BufferPosition(line: lineIdx, column: lastCharIdx))
    else:
      let lastIdx = lastMatchCol(line, -1)
      if lastIdx >= 0:
        return some(BufferPosition(line: lineIdx, column: lastIdx))

  return none(BufferPosition)

proc isPositionInSearchMatch*(
    b: TextBuffer,
    pos: BufferPosition,
    searchText: string,
    ignorecase = false,
    wholeWord = false,
): bool =
  ## Check if the given position is within a search match.
  ## Uses regex matching unless wholeWord is true (literal match).
  if searchText.len == 0:
    return false
  if pos.line < 0 or pos.line >= b.len:
    return false

  let ranges = b.findSearchMatchRanges(pos.line, searchText, ignorecase, wholeWord)
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
