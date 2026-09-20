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

## Small cursor helpers shared between `handler.nim` and the command-handler
## result processor. Isolated here to avoid a circular import.

import std/strutils

import unicode_utils
import primitives

proc adjustCursorAfterInsertExit*(cursor: var BufferPosition, lineCharLen: int) =
  ## Adjust cursor position when transitioning from Insert to Normal mode.
  ## Vim moves cursor one position to the left (unless at column 0 or empty line).
  if lineCharLen == 0:
    cursor.column = 0
  elif cursor.column > 0:
    cursor.column = min(cursor.column - 1, lineCharLen - 1)

proc pasteEndPos*(startPos: BufferPosition, pasteText: string): BufferPosition =
  ## Position just after inserting `pasteText` at `startPos`. Newlines start a new line.
  let nlCount = pasteText.count('\n')
  if nlCount == 0:
    BufferPosition(line: startPos.line, column: startPos.column + pasteText.charLen)
  else:
    let lastSeg = pasteText.substr(pasteText.rfind('\n') + 1)
    BufferPosition(line: startPos.line + nlCount, column: lastSeg.charLen)

proc clampCursorToLastChar*(cursor: var BufferPosition, lineCharLen: int) =
  ## Normal mode cannot rest one past the last character (unlike Insert).
  if cursor.column >= lineCharLen:
    cursor.column = max(0, lineCharLen - 1)
