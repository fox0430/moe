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
import gapbuffer, unicodeext, bufferstatus, window, independentutils

type
  SearchResult* = BufferPosition

  Direction* = enum
    forward = 0
    backward = 1

## Return true If the text matches.
proc compare(rune, sub: Runes, isIgnorecase, isSmartcase: bool): bool =
  if isIgnorecase and not isSmartcase:
    if cmpIgnoreCase($rune, $sub) == 0: return true
  elif isSmartcase and isIgnorecase:
    if isContainUpper(sub):
      return rune == sub
    else:
      if cmpIgnoreCase($rune, $sub) == 0: return true
  else:
    return rune == sub

## Return a position in a line if a keyword matches.
proc searchLine(
  line: Runes,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): Option[int] =

    for startPostion in 0 .. (line.len - keyword.len):
      let
        endPosition = startPostion + keyword.len
        runes = line[startPostion ..< endPosition]

      if compare(runes, keyword, isIgnorecase, isSmartcase):
        return startPostion.some

## Return a position in a line if a keyword matches.
proc searchLineReversely(
  line: Runes,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): Option[int] =

    for startPostion in countdown((line.len - keyword.len), 0):
      let
        endPosition = startPostion + keyword.len
        runes = line[startPostion ..< endPosition]

      if compare(runes, keyword, isIgnorecase, isSmartcase):
        return startPostion.some

## Return a buffer position if a keyword matches.
proc searchBuffer*(
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): Option[SearchResult] =

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

## Return a buffer position if a keyword matches.
proc searchBufferReversely*(
  bufStatus: BufferStatus,
  windowNode: WindowNode,
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): Option[SearchResult] =

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

## Return a buffer position if a keyword matches.
proc searchAllOccurrence*(
  buffer: GapBuffer[Runes],
  keyword: Runes,
  isIgnorecase, isSmartcase: bool): seq[SearchResult] =

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

## Add a keyword to the searchHistory.
proc addSearchHistory*(searchHistory: var seq[Runes], keyword: Runes) =
  if searchHistory.len == 0 or keyword != searchHistory[^1]:
    searchHistory.add(keyword)

## If `parenPosition` is an opening paren,
## search for the corresponding closing paren and return its position.
proc searchClosingParen(
  bufStatus: BufferStatus,
  parenPosition: BufferPosition): Option[SearchResult] =

    let
      buffer = bufStatus.buffer
      currentLine = parenPosition.line
      currentColumn = parenPosition.column

    if (buffer[currentLine].len < 1) or
       (not isOpenParen(buffer[currentLine][currentColumn])) or
       (buffer[currentLine][currentColumn] == ru'"') or
       (buffer[currentLine][currentColumn] == ru'\''): return

    var depth = 0
    let
      openParen = buffer[currentLine][currentColumn]
      closeParen = correspondingCloseParen(openParen)
    for i in currentLine ..< buffer.len:
      let startColumn =
        if i == currentLine: currentColumn
        else: 0

      for j in startColumn ..< buffer[i].len:
        if buffer[i][j] == openParen: inc(depth)
        elif buffer[i][j] == closeParen: dec(depth)
        if depth == 0:
          return SearchResult(line: i, column: j).some

## If `parenPosition` is an closing paren,
## search for the corresponding opening paren and return its position.
proc searchOpeningParen(
  bufStatus: BufferStatus,
  parenPosition: BufferPosition): Option[SearchResult] =

    let
      buffer = bufStatus.buffer
      currentLine = parenPosition.line
      currentColumn = parenPosition.column

    if (buffer[currentLine].len < 1) or
       (not isCloseParen(buffer[currentLine][currentColumn])) or
       (buffer[currentLine][currentColumn] == ru'"') or
       (buffer[currentLine][currentColumn] == ru'\''): return

    var depth = 0
    let
      closeParen = buffer[currentLine][currentColumn]
      openParen = correspondingOpenParen(closeParen)
    for i in countdown(currentLine, 0):
      let startColumn =
        if i == currentLine: currentColumn
        else: buffer[i].high

      for j in countdown(startColumn, 0):
        if buffer[i].len < 1: break
        if buffer[i][j] == closeParen: inc(depth)
        elif buffer[i][j] == openParen: dec(depth)
        if depth == 0:
          return SearchResult(line: i, column: j).some

## Return a position of the corresponding pair of paren.
proc matchingParenPair*(
  bufStatus: BufferStatus,
  parenPosition: BufferPosition): Option[SearchResult] =

    if bufStatus.buffer[parenPosition.line].len < 1: return

    let currentRune = bufStatus.buffer[parenPosition.line][parenPosition.column]
    if isOpenParen(currentRune):
      return bufStatus.searchClosingParen(parenPosition)
    elif isCloseParen(currentRune):
      return bufStatus.searchOpeningParen(parenPosition)
