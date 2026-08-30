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

proc findNext*(
    b: TextBuffer, searchText: string, startPos: BufferPosition, ignorecase = false
): Option[BufferPosition] =
  ## Find the next occurrence of searchText (regex) starting from startPos.
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

  let compiled = compileSearchRegex(searchText, ignorecase)
  if compiled.isNone:
    return none(BufferPosition)
  let re = compiled.get

  # Helper: find first regex match in line at or after startByteCol.
  # Returns character position or -1.
  proc searchLine(line: string, startCharCol = 0): int =
    if line.len == 0:
      return -1
    let lineCharLen = line.charLen
    if startCharCol >= lineCharLen:
      return -1
    let clampedStartCol = max(0, min(startCharCol, lineCharLen))
    let startByteCol = charToBytePos(line, clampedStartCol)
    if startByteCol > line.len:
      return -1
    var m = RegexMatch2()
    if find(line, re, m, startByteCol):
      return byteToCharPos(line, m.boundaries.a)
    return -1

  # Search rest of current line
  let currentLine = b.getLine(startPos.line)
  let currentLineCharLen = currentLine.charLen
  let searchStartCol =
    if startPos.column < 0:
      0
    else:
      min(startPos.column + 1, currentLineCharLen)

  let idx = searchLine(currentLine, searchStartCol)
  if idx >= 0 and (startPos.column < 0 or idx > startPos.column):
    return some(BufferPosition(line: startPos.line, column: idx))

  # Search remaining lines after current
  for lineIdx in (startPos.line + 1) ..< lineCount:
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue
    let idx = searchLine(line)
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
      let idx = searchLine(line, 0)
      if idx >= 0 and idx < startPos.column:
        return some(BufferPosition(line: lineIdx, column: idx))
    else:
      let idx = searchLine(line)
      if idx >= 0:
        return some(BufferPosition(line: lineIdx, column: idx))

  return none(BufferPosition)

proc findPrev*(
    b: TextBuffer, searchText: string, startPos: BufferPosition, ignorecase = false
): Option[BufferPosition] =
  ## Find the previous occurrence of searchText (regex) starting from startPos.
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

  let compiled = compileSearchRegex(searchText, ignorecase)
  if compiled.isNone:
    return none(BufferPosition)
  let re = compiled.get

  # Find last regex match in line where match start char < maxCharCol.
  # maxCharCol < 0 means no limit.
  proc findLastInLine(line: string, maxCharCol = -1): int =
    if line.len == 0:
      return -1
    let lineCharLen = line.charLen
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
    while searchBytePos <= line.len:
      if not find(line, re, m, searchBytePos):
        break
      let charIdx = byteToCharPos(line, m.boundaries.a)
      if maxCharCol >= 0 and charIdx >= searchCharLimit:
        break
      lastCharIdx = charIdx
      # Advance past this match (at least 1 byte to avoid infinite loop on zero-width)
      searchBytePos = max(m.boundaries.a + 1, m.boundaries.b + 1)
    return lastCharIdx

  # Search backwards in current line
  let currentLine = b.getLine(startPos.line)
  let currentLineCharLen = currentLine.charLen

  if startPos.column >= 0:
    let clampedColumn = min(startPos.column, currentLineCharLen)
    let lastIdx = findLastInLine(currentLine, clampedColumn)
    if lastIdx >= 0 and lastIdx < clampedColumn:
      return some(BufferPosition(line: startPos.line, column: lastIdx))

  # Search lines before current line (backwards)
  for lineIdx in countdown(startPos.line - 1, 0):
    let line = b.getLine(lineIdx)
    if line.len == 0:
      continue
    let lastIdx = findLastInLine(line)
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

      # Find last match after searchStartCharCol
      let startByteCol = charToBytePos(line, searchStartCharCol)
      var lastCharIdx = -1
      var searchBytePos = startByteCol
      var m = RegexMatch2()
      while searchBytePos <= line.len:
        if not find(line, re, m, searchBytePos):
          break
        let charIdx = byteToCharPos(line, m.boundaries.a)
        lastCharIdx = charIdx
        searchBytePos = max(m.boundaries.a + 1, m.boundaries.b + 1)

      if lastCharIdx >= 0 and (startPos.column < 0 or lastCharIdx > startPos.column):
        return some(BufferPosition(line: lineIdx, column: lastCharIdx))
    else:
      let lastIdx = findLastInLine(line)
      if lastIdx >= 0:
        return some(BufferPosition(line: lineIdx, column: lastIdx))

  return none(BufferPosition)

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

  let lineCharLen = line.charLen

  if wholeWord:
    # Literal matching with word boundary checks (for * and # commands)
    let searchTextPrepared = prepareSearchString(searchText, ignorecase)
    let linePrepared = prepareSearchString(line, ignorecase)
    let searchTextCharLen = searchText.charLen

    if searchTextCharLen > lineCharLen:
      return @[]

    # `charIdx` below is a `charLen` column, so the runes must be indexed in
    # the same model.
    let runes = line.toCharRunes()

    proc isWholeWordMatch(runes: seq[Rune], matchCol: int, matchLen: int): bool =
      if matchCol > 0:
        if isWordChar(runes[matchCol - 1]):
          return false
      let endCol = matchCol + matchLen
      if endCol < runes.len:
        if isWordChar(runes[endCol]):
          return false
      return true

    var searchCharPos = 0
    while searchCharPos <= lineCharLen:
      let searchBytePos = charToBytePos(line, searchCharPos)
      if searchBytePos > line.len:
        break
      let byteIdx = linePrepared.find(searchTextPrepared, searchBytePos)
      if byteIdx < 0:
        break
      let charIdx = byteToCharPos(line, byteIdx)
      if isWholeWordMatch(runes, charIdx, searchTextCharLen):
        result.add(ColumnRange(startCol: charIdx, endCol: charIdx + searchTextCharLen))
      searchCharPos = charIdx + 1
  else:
    # Regex matching
    let compiled = compileSearchRegex(searchText, ignorecase)
    if compiled.isNone:
      return @[]
    let re = compiled.get

    var searchBytePos = 0
    var m = RegexMatch2()
    while searchBytePos <= line.len:
      if not find(line, re, m, searchBytePos):
        break
      let startChar = byteToCharPos(line, m.boundaries.a)
      let endChar = byteToCharPos(line, m.boundaries.b + 1)
      result.add(ColumnRange(startCol: startChar, endCol: endChar))
      # Advance past this match (at least 1 byte to avoid infinite loop on zero-width)
      searchBytePos = max(m.boundaries.a + 1, m.boundaries.b + 1)

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
  ## Compare `line[startByte ..< endByte]` to `word` without allocating a
  ## substring. UTF-8 byte equality is exact string equality, so this stays
  ## correct for multibyte and is allocation-free on the render hot path.
  ##
  ## Expression-bodied (a `block` that yields its last value, no `return`) so it
  ## composes inside the larger boolean expressions at the call sites. Arguments
  ## are substituted, not bound, so pass only side-effect-free expressions — the
  ## call sites pass plain locals.
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

  # Scan characters left-to-right, tracking each maximal word run by its column
  # span [runStartCol, col) and byte span [runStartByte, bytePos). Comparing the
  # byte slice against `word` avoids materializing the line into a seq[Rune] and
  # building a fresh string for every candidate word — both of which the old
  # implementation allocated for every visible line, every frame.
  var
    col = 0
    bytePos = 0
    runStartCol = -1
    runStartByte = 0

  while bytePos < line.len:
    # `charAtByte` steps by the bytes the character actually occupies, so `col`
    # is the same column the buffer and the renderer count (`fastRuneAt` can
    # drift on a line holding a byte that does not decode).
    let charStartByte = bytePos
    let (r, size) = line.charAtByte(bytePos)
    bytePos += size
    if isWordChar(r):
      if runStartCol < 0:
        runStartCol = col
        runStartByte = charStartByte
    elif runStartCol >= 0:
      # Word run [runStartCol, col) ends here; emit it when it matches.
      if byteSliceEqualsWord(line, runStartByte, charStartByte, word) and
          not (excludeCol >= 0 and excludeCol >= runStartCol and excludeCol < col):
        result.add(ColumnRange(startCol: runStartCol, endCol: col))
      runStartCol = -1
    inc col

  # A word run reaching end-of-line is not closed by the loop above.
  if runStartCol >= 0 and byteSliceEqualsWord(line, runStartByte, bytePos, word) and
      not (excludeCol >= 0 and excludeCol >= runStartCol and excludeCol < col):
    result.add(ColumnRange(startCol: runStartCol, endCol: col))
