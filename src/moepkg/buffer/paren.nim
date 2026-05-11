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

import std/[options, unicode]

import ../primitives
import ./core

const
  openBrackets = [Rune('('), Rune('['), Rune('{'), Rune('<')]
  closeBrackets = [Rune(')'), Rune(']'), Rune('}'), Rune('>')]

proc findMatchingParenPosition*(
    b: TextBuffer, cursor: BufferPosition, maxScanLines: int = 2000
): Option[BufferPosition] =
  ## Find the position of the matching parenthesis/bracket/brace
  ## Searches across multiple lines. Returns none if cursor is not on a bracket
  ## or no matching bracket is found within `maxScanLines` lines of the cursor.
  ## The line limit keeps this bounded for paren-highlight callers running on
  ## every frame against huge files (e.g. 40k-line JSON wrapped in a root
  ## object); matches further than the viewport cannot be seen anyway.

  if cursor.line < 0 or cursor.line >= b.len:
    return none(BufferPosition)

  let line = b.getLine(cursor.line)
  let runes = line.toRunes()

  if runes.len == 0 or cursor.column >= runes.len:
    return none(BufferPosition)

  let charAtCursor = runes[cursor.column]

  var openChar, closeChar: Rune
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
  var searchLine = cursor.line
  var curRunes = runes
  if searchForward:
    var searchCol = cursor.column + 1
    let scanUntil = min(b.len - 1, cursor.line + maxScanLines)
    while searchLine <= scanUntil:
      while searchCol < curRunes.len:
        let ch = curRunes[searchCol]
        if ch == openChar:
          depth.inc
        elif ch == closeChar:
          depth.dec
          if depth == 0:
            return some(BufferPosition(line: searchLine, column: searchCol))
        searchCol.inc
      searchLine.inc
      if searchLine <= scanUntil:
        curRunes = b.getLine(searchLine).toRunes()
        searchCol = 0
  else:
    var searchCol = cursor.column - 1
    let scanUntil = max(0, cursor.line - maxScanLines)
    while searchLine >= scanUntil:
      while searchCol >= 0:
        let ch = curRunes[searchCol]
        if ch == closeChar:
          depth.inc
        elif ch == openChar:
          depth.dec
          if depth == 0:
            return some(BufferPosition(line: searchLine, column: searchCol))
        searchCol.dec
      searchLine.dec
      if searchLine >= scanUntil:
        curRunes = b.getLine(searchLine).toRunes()
        searchCol = curRunes.len - 1

  return none(BufferPosition)
