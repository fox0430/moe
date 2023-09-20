#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[strutils, options]
import gapbuffer, unicodeext, bufferstatus, windownode, independentutils

type
  SearchResult* = BufferPosition

  Direction* = enum
    forward = 0
    backward = 1

proc compare(rune, sub: Runes, isIgnorecase, isSmartcase: bool): bool =
  ## Return true If the text matches.

  if isIgnorecase and not isSmartcase:
    if cmpIgnoreCase($rune, $sub) == 0: return true
  elif isSmartcase and isIgnorecase:
    if isContainUpper(sub):
      return rune == sub
    else:
      if cmpIgnoreCase($rune, $sub) == 0: return true
  else:
    return rune == sub

proc searchLine(
  line: Runes,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): Option[int] =
    ## Return a position in a line if a keyword matches.

    for startPostion in 0 .. (line.len - keyword.len):
      let
        endPosition = startPostion + keyword.len
        runes = line[startPostion ..< endPosition]

      if compare(runes, keyword, isIgnorecase, isSmartcase):
        return startPostion.some

proc searchLineReversely(
  line: Runes,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): Option[int] =
    ## Return a position in a line if a keyword matches.

    for startPostion in countdown((line.len - keyword.len), 0):
      let
        endPosition = startPostion + keyword.len
        runes = line[startPostion ..< endPosition]

      if compare(runes, keyword, isIgnorecase, isSmartcase):
        return startPostion.some

proc searchBuffer*(
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): Option[SearchResult] =
    ## Return a buffer position if a keyword matches.

    let startLine = windowNode.currentLine
    for i in 0 ..< bufStatus.buffer.len:
      let
        lineNumber = (startLine + i) mod bufStatus.buffer.len

        first =
          if lineNumber == startLine and i == 0: windowNode.currentColumn
          else: 0
        last = bufStatus.buffer[lineNumber].len

        line = bufStatus.buffer[lineNumber]

        position = searchLine(
          line[first ..< last],
          keyword,
          isIgnorecase,
          isSmartcase)

      if position.isSome:
        return SearchResult(line: lineNumber, column: first + position.get).some

proc searchBufferReversely*(
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): Option[SearchResult] =
    ## Return a buffer position if a keyword matches.

    let
      startLine = windowNode.currentLine
      buffer = bufStatus.buffer
    for i in 0 ..< bufStatus.buffer.len + 1:
      var lineNumber = (startLine - i) mod buffer.len
      if lineNumber < 0: lineNumber = buffer.len - i
      let
        endPosition =
          if lineNumber == startLine and i == 0:
            windowNode.currentColumn
          else:
            buffer[lineNumber].len

        position = searchLineReversely(
          buffer[lineNumber][0 ..< endPosition],
          keyword,
          isIgnorecase,
          isSmartcase)

      if position.isSome:
        return SearchResult(line: lineNumber, column: position.get).some

proc searchAllOccurrence*(
  buffer: seq[Runes],
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): seq[SearchResult] =
    ## Return a buffer position if a keyword matches.

    if keyword.len < 1: return

    for lineNumber in 0 ..< buffer.len:
      var first = 0
      while first < buffer[lineNumber].len:
        let
          last = buffer[lineNumber].len
          line = buffer[lineNumber]
          position = searchLine(
            line[first ..< last],
            keyword,
            isIgnorecase,
            isSmartcase)

        if position.isNone: break

        result.add SearchResult(line: lineNumber, column: first + position.get)
        first += position.get + keyword.len

proc searchAllOccurrence*(
  buffer: seq[Runes],
  keyword: Runes): seq[SearchResult] {.inline.} =
    ## Return a buffer position if a keyword matches.

    searchAllOccurrence(buffer, keyword, false, false)

proc saveSearchHistory*(
  searchHistory: var seq[Runes],
  keyword: Runes,
  limit: int) =
    ## Save a keyword to the searchHistory.
    ## If the size exceeds the limit, the oldest will be deleted.

    if limit < 1 or keyword.len == 0: return

    if searchHistory.len == 0:
      searchHistory.add keyword
    elif keyword != searchHistory[^1]:
      searchHistory.add keyword

      if searchHistory.len > limit:
        let
          first = searchHistory.len - limit
          last = first + limit - 1
        searchHistory = searchHistory[first .. last]

proc searchClosingParen*(
  buffer: seq[Runes],
  openParenPosition: BufferPosition): Option[SearchResult] =
    ## If `parenPosition` is an opening paren,
    ## search for the corresponding closing paren and return its position.

    if openParenPosition.line > buffer.high or
       openParenPosition.column > buffer[openParenPosition.line].high:
         return

    let openParen = buffer[openParenPosition.line][openParenPosition.column]

    if (openParen == ru'"') or (openParen == ru'\''): return

    var depth = 0
    let closeParen = correspondingCloseParen(openParen)
    for i in openParenPosition.line .. buffer.high:
      if buffer[i].len > 0:
        let
          startColumn =
            if i == openParenPosition.line: openParenPosition.column
            else: 0
          endColumn = buffer[i].high

        for j in startColumn .. endColumn:
          if buffer[i][j] == openParen: depth.inc
          elif buffer[i][j] == closeParen: depth.dec

          if depth == 0:
            return SearchResult(line: i, column: j).some

proc searchOpeningParen*(
  buffer: seq[Runes],
  closeParenPosition: BufferPosition): Option[SearchResult] =
    ## If `parenPosition` is an closing paren,
    ## Search for the corresponding opening paren and return its position.

    if closeParenPosition.line > buffer.high or
       closeParenPosition.column > buffer[closeParenPosition.line].high:
         return

    let closeParen = buffer[closeParenPosition.line][closeParenPosition.column]

    if (closeParen  == ru'"') or (closeParen == ru'\''): return

    var depth = 0
    let openParen = correspondingOpenParen(closeParen)
    for i in countdown(closeParenPosition.line, 0):
      if buffer[i].len > 0:
        let
          startColumn = 0
          endColumn =
            if i == closeParenPosition.line: closeParenPosition.column
            else: buffer[i].high

        for j in countdown(endColumn, startColumn):
          if buffer[i][j] == closeParen: depth.inc
          elif buffer[i][j] == openParen: depth.dec

          if depth == 0:
            return SearchResult(line: i, column: j).some

proc assertRange(range: BufferRange) =
  doAssert range.first.line >= 0
  doAssert range.first.column >= 0

  doAssert range.last.line >= 0
  doAssert range.first.line >= 0

proc searchClosingParen(
  bufStatus: BufferStatus,
  range: BufferRange,
  openParen: Rune): Option[SearchResult] =
    ## If `parenPosition` is an opening paren,
    ## search for the corresponding closing paren and return its position.

    when not defined(release): range.assertRange

    if (openParen == ru'"') or (openParen == ru'\''): return

    let
      buffer = bufStatus.buffer
      openParenLine = range.first.line
      openParenColumn = range.first.column

    var depth = 1
    let closeParen = correspondingCloseParen(openParen)
    for i in openParenLine .. range.last.line:
      let
        startColumn =
          if i == openParenLine: openParenColumn
          else: 0
        endColumn =
          if i == range.last.line: range.last.column
          else: buffer[i].high

      for j in startColumn .. endColumn:
        if buffer[i].len < 1: break
        elif buffer[i][j] == openParen: inc(depth)
        elif buffer[i][j] == closeParen: dec(depth)

        if depth == 0:
          return SearchResult(line: i, column: j).some

proc searchOpeningParen(
  bufStatus: BufferStatus,
  range: BufferRange,
  closeParen: Rune): Option[SearchResult] =
    ## If `parenPosition` is an closing paren,
    ## Search for the corresponding opening paren and return its position.

    when not defined(release): range.assertRange

    if (closeParen  == ru'"') or (closeParen == ru'\''): return

    let
      buffer = bufStatus.buffer
      closeParenLine = range.first.line
      closeParenColumn = range.first.column

    var depth = 1
    let openParen = correspondingOpenParen(closeParen)
    for i in countdown(closeParenLine, range.last.line):
      let
        startColumn =
          if i == closeParenLine: closeParenColumn
          else: buffer[i].high
        endColumn =
          if i == range.last.line: range.last.column
          else: 0

      for j in countdown(startColumn, endColumn):
        if buffer[i].len < 1: break
        elif buffer[i][j] == closeParen: inc(depth)
        elif buffer[i][j] == openParen: dec(depth)

        if depth == 0:
          return SearchResult(line: i, column: j).some

proc matchingParenPair*(
  bufStatus: BufferStatus,
  range: BufferRange,
  paren: Rune): Option[SearchResult] =
    ## Return a position of the corresponding pair of paren.

    if bufStatus.buffer.high < range.first.line: return

    if isOpenParen(paren):
      return bufStatus.searchClosingParen(range, paren)
    elif isCloseParen(paren):
      return bufStatus.searchOpeningParen(range, paren)

proc matchingParenPair*(
  bufStatus: BufferStatus,
  parenPosition: BufferPosition): Option[SearchResult] =
    ## Return a position of the corresponding pair of paren.
    ## Search from the `parenPosition` to the end or the buffer (if opening paren) or
    ## The first of the buffer (if closing paren).

    if bufStatus.buffer[parenPosition.line].len < 1: return

    let currentRune = bufStatus.buffer[parenPosition.line][parenPosition.column]
    if isOpenParen(currentRune):
      # Search from the next position in the place of `parenPosition`
      # to the end position of the buffer.
      if parenPosition.line == bufStatus.buffer.high and
         parenPosition.column == bufStatus.buffer[parenPosition.line].high:
           return

      let
        # TODO: Add bufStatus.next or gapbuffer.next and replace with it.
        firstPositionLine =
          if parenPosition.column + 1 < bufStatus.buffer[parenPosition.line].len:
            parenPosition.line
          else:
            parenPosition.line + 1
        firstPositionColumn =
          if firstPositionLine == parenPosition.line: parenPosition.column + 1
          else:
            if bufStatus.buffer[firstPositionLine].high >= 0:
              bufStatus.buffer[firstPositionLine].high
            else:
              0
        firstPosition = BufferPosition(
          line: firstPositionLine,
          column: firstPositionColumn)

        range = BufferRange(
          first: firstPosition,
          last: bufStatus.positionEndOfBuffer)

      return bufStatus.searchClosingParen(range, currentRune)

    elif isCloseParen(currentRune):
      # Search from the prev position in the place of `parenPosition`
      # to the first position of the buffer.
      if parenPosition.line == 0 and parenPosition.column == 0: return

      let
        # TODO: Add bufStatus.prev or gapbuffer.prev and replace with it.
        firstPositionLine =
          if parenPosition.column > 0: parenPosition.line
          else: parenPosition.line - 1
        firstPositionColumn =
          if firstPositionLine == parenPosition.line: parenPosition.column - 1
          else:
            if bufStatus.buffer[firstPositionLine].high >= 0:
              bufStatus.buffer[firstPositionLine].high
            else:
              0
        firstPosition = BufferPosition(
          line: firstPositionLine,
          column: firstPositionColumn)

        range = BufferRange(
          first: firstPosition,
          last: BufferPosition(line: 0, column: 0))

      return bufStatus.searchOpeningParen(range, currentRune)

proc currentWord*(
  buffer: seq[Runes],
  currentPosition: BufferPosition): tuple[word: Runes, position: int] =
    ## Return the word with position on the current cursor position.
    ## Ignore symbols and spaces.

    template lineBuffer: Runes = buffer[currentPosition.line]

    template currentRune: Rune = lineBuffer[currentPosition.column]

    proc isIgnoreRune(r: Rune): bool {.inline.} =
       (r != '_' and isPunct(r)) or isSpace(r)

    if
       buffer.len < 1 or
       lineBuffer.len < 1 or
       currentPosition.column > lineBuffer.high or
       isIgnoreRune(currentRune):
         return

    var
      startCol = currentPosition.column
      endCol = currentPosition.column

    # Find the start col
    for i in countdown(currentPosition.column - 1, 0):
      if isIgnoreRune(lineBuffer[i]): break
      else: startCol.dec

    # Find the end col
    for i in currentPosition.column + 1 .. lineBuffer.high:
      if isIgnoreRune(lineBuffer[i]): break
      else: endCol.inc

    return (word: lineBuffer[startCol .. endCol],
            position: startCol)
