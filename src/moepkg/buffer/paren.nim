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

## Matching paren/bracket/brace navigation (used by `%` and paren-highlight).

import std/options

import ../[primitives, unicode_utils]
import ./core

const
  openBrackets = ['(', '[', '{', '<']
  closeBrackets = [')', ']', '}', '>']

proc scanForward(
    line: string, fromByte: int, openChar, closeChar: char, depth: var int
): int =
  ## The byte in `line` at or after `fromByte` where `depth` drops to zero, or
  ## -1 when the line ends first.
  for i in fromByte ..< line.len:
    if line[i] == openChar:
      depth.inc
    elif line[i] == closeChar:
      depth.dec
      if depth == 0:
        return i
  -1

proc scanBackward(
    line: string, fromByte: int, openChar, closeChar: char, depth: var int
): int =
  ## The byte in `line` at or before `fromByte` where `depth` drops to zero,
  ## or -1 when the line starts first.
  var i = min(fromByte, line.high)
  while i >= 0:
    if line[i] == closeChar:
      depth.inc
    elif line[i] == openChar:
      depth.dec
      if depth == 0:
        return i
    i.dec
  -1

proc findMatchingParenPosition*(
    b: TextBuffer, cursor: BufferPosition, cursorLine: string, maxScanLines = 2000
): Option[BufferPosition] =
  ## Find the position of the matching parenthesis/bracket/brace
  ## Searches across multiple lines. Returns none if cursor is not on a bracket
  ## or no matching bracket is found within `maxScanLines` lines of the cursor.
  ## The line limit keeps this bounded for paren-highlight callers running on
  ## every frame against huge files (e.g. 40k-line JSON wrapped in a root
  ## object); matches further than the viewport cannot be seen anyway.
  ##
  ## `cursorLine` is the text of the cursor's line, which a per-frame caller
  ## reads once and shares, so a line of megabytes is not copied again here.
  ##
  ## Brackets are ASCII and an ASCII byte is always a character of its own, so
  ## the lines are scanned as bytes and only a hit is turned into a column.

  if cursor.line < 0 or cursor.line >= b.len or cursor.column < 0:
    return none(BufferPosition)

  # `cursor.column` is a buffer column, so it is counted with `runeSizeAt`.
  let cursorByte = cursorLine.charToBytePos(cursor.column)
  if cursorByte >= cursorLine.len:
    return none(BufferPosition)

  let charAtCursor = cursorLine[cursorByte]

  var openChar, closeChar: char
  var searchForward = false

  # Check if cursor is on a bracket
  if charAtCursor in openBrackets:
    openChar = charAtCursor
    closeChar = closeBrackets[openBrackets.find(charAtCursor)]
    searchForward = true
  elif charAtCursor in closeBrackets:
    closeChar = charAtCursor
    openChar = openBrackets[closeBrackets.find(charAtCursor)]
    searchForward = false
  else:
    return none(BufferPosition)

  var depth = 1
  if searchForward:
    let hit = cursorLine.scanForward(cursorByte + 1, openChar, closeChar, depth)
    if hit >= 0:
      return
        some(BufferPosition(line: cursor.line, column: cursorLine.byteToCharPos(hit)))
    for lineIndex in cursor.line + 1 .. min(b.len - 1, cursor.line + maxScanLines):
      let line = b.getLine(lineIndex)
      let hit = line.scanForward(0, openChar, closeChar, depth)
      if hit >= 0:
        return some(BufferPosition(line: lineIndex, column: line.byteToCharPos(hit)))
  else:
    let hit = cursorLine.scanBackward(cursorByte - 1, openChar, closeChar, depth)
    if hit >= 0:
      return
        some(BufferPosition(line: cursor.line, column: cursorLine.byteToCharPos(hit)))
    for lineIndex in countdown(cursor.line - 1, max(0, cursor.line - maxScanLines)):
      let line = b.getLine(lineIndex)
      let hit = line.scanBackward(line.high, openChar, closeChar, depth)
      if hit >= 0:
        return some(BufferPosition(line: lineIndex, column: line.byteToCharPos(hit)))

  return none(BufferPosition)

proc findMatchingParenPosition*(
    b: TextBuffer, cursor: BufferPosition, maxScanLines = 2000
): Option[BufferPosition] =
  ## `findMatchingParenPosition` reading the cursor's line from `b`.
  if cursor.line < 0 or cursor.line >= b.len:
    return none(BufferPosition)
  b.findMatchingParenPosition(cursor, b.getLine(cursor.line), maxScanLines)
