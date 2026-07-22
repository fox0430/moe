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

## Internal mutation helpers: backend-dispatch primitives and multi-line
## text mutation helpers used by edit.nim / undo.nim. These do NOT record
## undo entries — they are the lowest layer above the backend backends.

import std/[strutils, unicode]

import ../[primitives, unicode_utils]
import ../buffer_backends/[gap_buffer, sqrt_decomp, rope, piece_table]
import core

# Backend dispatch helpers for internal use (no undo recording)
proc backendInsertIntoLine*(b: TextBuffer, line, col: int, text: string) =
  case b.backendKind
  of GapBuffer:
    b.storage.gapBuffer.insertIntoLine(line, col, text)
  of SqrtDecomp:
    b.storage.sqrtDecomp.insertIntoLine(line, col, text)
  of Rope:
    b.storage.rope.insertIntoLine(line, col, text)
  of PieceTable:
    b.storage.pieceTable.insertIntoLine(line, col, text)

proc backendDeleteLine*(b: TextBuffer, lineNumber: int) =
  case b.backendKind
  of GapBuffer:
    b.storage.gapBuffer.deleteLine(lineNumber)
  of SqrtDecomp:
    b.storage.sqrtDecomp.deleteLine(lineNumber)
  of Rope:
    b.storage.rope.deleteLine(lineNumber)
  of PieceTable:
    b.storage.pieceTable.deleteLine(lineNumber)

proc backendInsertLine*(b: TextBuffer, lineNumber: int, content: string) =
  case b.backendKind
  of GapBuffer:
    b.storage.gapBuffer.insertLine(lineNumber, content)
  of SqrtDecomp:
    b.storage.sqrtDecomp.insertLine(lineNumber, content)
  of Rope:
    b.storage.rope.insertLine(lineNumber, content)
  of PieceTable:
    b.storage.pieceTable.insertLine(lineNumber, content)

proc backendReplaceLine*(b: TextBuffer, lineNumber: int, content: string) =
  case b.backendKind
  of GapBuffer:
    b.storage.gapBuffer.replaceLine(lineNumber, content)
  of SqrtDecomp:
    b.storage.sqrtDecomp.replaceLine(lineNumber, content)
  of Rope:
    b.storage.rope.replaceLine(lineNumber, content)
  of PieceTable:
    b.storage.pieceTable.replaceLine(lineNumber, content)

proc backendDeleteAtLineCol*(b: TextBuffer, line, col, count: int) =
  case b.backendKind
  of GapBuffer:
    b.storage.gapBuffer.deleteAtLineCol(line, col, count)
  of SqrtDecomp:
    b.storage.sqrtDecomp.deleteAtLineCol(line, col, count)
  of Rope:
    b.storage.rope.deleteAtLineCol(line, col, count)
  of PieceTable:
    b.storage.pieceTable.deleteAtLineCol(line, col, count)

proc insertTextWithNewlines*(b: TextBuffer, pos: BufferPosition, text: string) =
  ## Insert text that may contain newlines, properly splitting into multiple lines
  ## This is used internally for undo/redo operations
  if '\n' notin text:
    # Simple case: no newlines, just insert into current line
    let line = b.getLine(pos.line)
    let bytePos = charToBytePos(line, pos.column)
    b.backendInsertIntoLine(pos.line, bytePos, text)
  else:
    # Complex case: text contains newlines, need to split current line and insert multiple lines
    let
      currentLine = b.getLine(pos.line)
      currentLineLen = currentLine.charLen

    # Split current line at insertion position
    let
      prefix =
        if pos.column < currentLineLen:
          currentLine.runeSubStr(0, pos.column)
        else:
          currentLine
      suffix =
        if pos.column < currentLineLen:
          currentLine.runeSubStr(pos.column)
        else:
          ""

    # Split text to insert by newlines
    let insertedLines = text.split('\n')

    # Build new lines
    var newLines: seq[string] = @[]

    if insertedLines.len == 1:
      # Should not happen (we checked for \n above), but handle it
      newLines.add(prefix & insertedLines[0] & suffix)
    else:
      # First line: prefix + first inserted line
      newLines.add(prefix & insertedLines[0])

      # Middle lines: just the inserted lines
      for i in 1 ..< insertedLines.len - 1:
        newLines.add(insertedLines[i])

      # Last line: last inserted line + suffix
      newLines.add(insertedLines[^1] & suffix)

    # Replace current line with new lines
    b.backendDeleteLine(pos.line)
    for i, newLine in newLines:
      b.backendInsertLine(pos.line + i, newLine)

  # Side-array shifts and the modified-line mark are deferred to the
  # sideArrayCallbacks driven from pushUndoChange / undoChange / redoChange.

proc buildMergedLine*(prefix: string, suffix: string): string {.inline.} =
  ## Helper to build a merged line from prefix and suffix
  prefix & suffix

proc deleteRangeSingleLine*(
    b: TextBuffer, line: string, startPos, endPos: BufferPosition
): bool {.discardable.} =
  ## Handle single-line deletion.
  ## Returns true if the deletion joined this line with the next one
  ## (so callers can shift folds/bookmarks accordingly).
  let lineLen = line.charLen
  var joinedWithNext = false

  # Check if selection extends to or past line end (includes newline)
  if endPos.column >= lineLen:
    # Delete from startPos to end of line, then join with next line
    if endPos.line < b.len - 1:
      # Multi-line: join with next line
      let nextLine = b.getLine(endPos.line + 1)
      let prefix =
        if startPos.column <= lineLen:
          line.runeSubStr(0, startPos.column)
        else:
          ""
      let newLine = buildMergedLine(prefix, nextLine)

      # Delete current and next line, insert combined
      b.backendDeleteLine(endPos.line + 1)
      b.backendDeleteLine(startPos.line)
      b.backendInsertLine(startPos.line, newLine)
      joinedWithNext = true
    else:
      # Last line: just delete to end
      let newLine =
        if startPos.column <= lineLen:
          line.runeSubStr(0, startPos.column)
        else:
          ""
      b.backendDeleteLine(startPos.line)
      b.backendInsertLine(startPos.line, newLine)
  elif startPos.column < lineLen and endPos.column < lineLen:
    # Normal single-line deletion within bounds
    # Build new line by concatenating prefix and suffix using Unicode-safe substring
    let prefix = line.runeSubStr(0, startPos.column)
    let suffix = line.runeSubStr(endPos.column + 1)
    let newLine = buildMergedLine(prefix, suffix)

    b.backendDeleteLine(startPos.line)
    b.backendInsertLine(startPos.line, newLine)

  # Side-array shifts deferred (see insertTextWithNewlines).

  return joinedWithNext

proc deleteRangeMultiLine*(
    b: TextBuffer, startPos, endPos: BufferPosition
): bool {.discardable.} =
  ## Handle multi-line deletion. Returns true when the range also consumed
  ## `endPos.line + 1` (the join case).
  let
    startLine = b.getLine(startPos.line)
    endLine = b.getLine(endPos.line)
    endLineLen = endLine.charLen

  # Build prefix (chars before selection start)
  let prefix =
    if startPos.column <= startLine.charLen:
      startLine.runeSubStr(0, startPos.column)
    else:
      ""

  # Build suffix (chars after selection end)
  var suffix = ""
  var extraLineToDelete = -1

  if endPos.column < endLineLen:
    # Selection ends within the line - keep remaining chars
    suffix = endLine.runeSubStr(endPos.column + 1)
  elif endPos.line < b.len - 1:
    # Selection extends to/past line end - join with next line instead
    suffix = b.getLine(endPos.line + 1)
    extraLineToDelete = endPos.line + 1

  # Delete extra line if needed
  if extraLineToDelete >= 0:
    b.backendDeleteLine(extraLineToDelete)

  # Replace startPos.line with the merged line
  b.backendDeleteLine(startPos.line)
  b.backendInsertLine(startPos.line, buildMergedLine(prefix, suffix))

  # Delete lines between startPos and endPos (if any)
  if endPos.line > startPos.line:
    for i in countdown(endPos.line, startPos.line + 1):
      b.backendDeleteLine(i)

  # Side-array shifts deferred (see insertTextWithNewlines).

  return extraLineToDelete >= 0
