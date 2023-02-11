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

import std/strutils
import gapbuffer, movement, unicodeext, bufferstatus, window

type
  SearchResult* = tuple[line: int, column: int]

type Direction* = enum
  forward = 0
  backward = 1

proc compare(rune, sub: seq[Rune], ignorecase, smartcase: bool): bool =
  proc isContainUpper(sub: seq[Rune]): bool =
    for r in sub:
      let ch = ($r)[0]
      if isUpperAscii(ch): return true

  if ignorecase and not smartcase:
    if cmpIgnoreCase($rune, $sub) == 0: return true
  elif smartcase and ignorecase:
    if isContainUpper(sub):
      return rune == sub
    else:
      if cmpIgnoreCase($rune, $sub) == 0: return true
  else:
    return rune == sub

proc searchLine(line: seq[Rune],
                keyword: seq[Rune],
                ignorecase, smartcase: bool): int =

  result = -1
  for startPostion in 0 .. (line.len - keyword.len):
    let
      endPosition = startPostion + keyword.len
      rune = line[startPostion ..< endPosition]

    if compare(rune, keyword, ignorecase, smartcase): return startPostion

proc searchLineReversely(line: seq[Rune],
                         keyword: seq[Rune],
                         ignorecase, smartcase: bool): int =

  result = -1
  for startPostion in countdown((line.len - keyword.len), 0):
    let
      endPosition = startPostion + keyword.len
      rune = line[startPostion ..< endPosition]

    if compare(rune, keyword, ignorecase, smartcase): return startPostion

proc searchBuffer*(bufStatus: BufferStatus,
                   win: var WindowNode,
                   keyword: seq[Rune],
                   ignorecase, smartcase: bool): SearchResult =

  result = (-1, -1)
  let
    startLine = win.currentLine
    buffer = bufStatus.buffer
  for i in 0 ..< buffer.len:
    let
      lineNumber = (startLine + i) mod buffer.len
      begin = if lineNumber == startLine and
                 i == 0: win.currentColumn
              else: 0
      `end` = buffer[lineNumber].len
      line = buffer[lineNumber]
      position = searchLine(line[begin ..< `end`],
                            keyword,
                            ignorecase,
                            smartcase)

    if position > -1: return (lineNumber, begin + position)

proc searchBufferReversely*(bufStatus: BufferStatus,
                            win: WindowNode,
                            keyword: seq[Rune],
                            ignorecase, smartcase: bool): SearchResult =

  result = (-1, -1)
  let
    startLine = win.currentLine
    buffer = bufStatus.buffer
  for i in 0 ..< bufStatus.buffer.len + 1:
    var lineNumber = (startLine - i) mod buffer.len
    if lineNumber < 0: lineNumber = buffer.len - i
    let
      endPosition = if lineNumber == startLine and i == 0:
                      win.currentColumn
                    else:
                      buffer[lineNumber].len
      position = searchLineReversely(buffer[lineNumber][0 ..< endPosition],
                                     keyword,
                                     ignorecase,
                                     smartcase)

    if position > -1: return (lineNumber, position)

proc searchAllOccurrence*(buffer: GapBuffer[seq[Rune]],
                          keyword: seq[Rune],
                          ignorecase, smartcase: bool): seq[SearchResult] =

  if keyword.len < 1: return

  for lineNumber in 0 ..< buffer.len:
    var begin = 0
    while begin < buffer[lineNumber].len:
      let
        `end` = buffer[lineNumber].len
        line = buffer[lineNumber]
        position = searchLine(line[begin ..< `end`],
                              keyword,
                              ignorecase,
                              smartcase)
      if position == -1: break
      result.add((lineNumber, begin + position))
      begin += position + keyword.len

proc jumpToSearchForwardResults*(bufStatus: var BufferStatus,
                                 windowNode: var WindowNode,
                                 keyword: seq[Rune],
                                 ignorecase, smartcase: bool) =
  let
    searchResult = bufStatus.searchBuffer(windowNode, keyword, ignorecase, smartcase)
  if searchResult.line > -1:
    bufStatus.jumpLine(windowNode, searchResult.line)
    for column in 0 ..< searchResult.column:
      bufStatus.keyRight(windowNode)

proc jumpToSearchBackwordResults*(bufStatus: var BufferStatus,
                                  windowNode: var WindowNode,
                                  keyword: seq[Rune],
                                  ignorecase, smartcase: bool) =

  let
    searchResult = bufStatus.searchBufferReversely(
      windowNode, keyword, ignorecase, smartcase)
  if searchResult.line > -1:
    bufStatus.jumpLine(windowNode, searchResult.line)
    for column in 0 ..< searchResult.column:
      bufStatus.keyRight(windowNode)

proc addSearchHistory*(searchHistory: var seq[seq[Rune]],
                       keyword: seq[Rune]) =

  if searchHistory.len == 0 or keyword != searchHistory[^1]:
    searchHistory.add(keyword)


