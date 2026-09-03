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

import std/strutils

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

proc deletableBytesFrom(b: TextBuffer, line, col, atLeast: int): int =
  ## Bytes from (line, col) to the buffer end, newlines included. Stops once
  ## `atLeast` is reached to avoid walking a large buffer.
  result = b.getLine(line).len - col
  var i = line + 1
  while result < atLeast and i < b.len:
    result += 1 + b.getLine(i).len
    inc i

proc backendDeleteAtLineCol*(b: TextBuffer, line, col, count: int) =
  ## Delete `count` bytes from (line, col), crossing line ends. `col` and
  ## `count` are byte offsets, not columns. Raises IndexDefect for a range the
  ## buffer does not hold, because the backends disagree about one.
  if count <= 0:
    raise newException(IndexDefect, "Delete count must be > 0: " & $count)
  if line < 0 or line >= b.len:
    raise newException(IndexDefect, "Delete line out of bounds: " & $line)

  let lineLen = b.getLine(line).len
  if col < 0 or col > lineLen:
    raise newException(
      IndexDefect, "Delete column out of bounds: " & $col & " of " & $lineLen
    )
  # A deletion inside the line cannot reach past the buffer end.
  if count > lineLen - col and count > b.deletableBytesFrom(line, col, count):
    raise newException(
      IndexDefect, "Delete count reaches past the end of the buffer: " & $count
    )

  case b.backendKind
  of GapBuffer:
    b.storage.gapBuffer.deleteAtLineCol(line, col, count)
  of SqrtDecomp:
    b.storage.sqrtDecomp.deleteAtLineCol(line, col, count)
  of Rope:
    b.storage.rope.deleteAtLineCol(line, col, count)
  of PieceTable:
    b.storage.pieceTable.deleteAtLineCol(line, col, count)

proc insertTextWithNewlines*(
    b: TextBuffer,
    pos: BufferPosition,
    text: string,
    cursorByte: int = -1,
    atByte: int = -1,
): InsertOutcome {.discardable.} =
  ## Insert text that may contain newlines, properly splitting into multiple
  ## lines. Reports where the insertion ends, where a cursor following it
  ## belongs and how many columns the line gained -- all measured on the line
  ## as it now stands, because a lead byte completed over a seam cannot be
  ## re-derived from `text` alone. The line is already in hand here, so no
  ## caller has to fetch it again.
  ##
  ## `cursorByte` is a byte offset into `text` for callers that wrote more than
  ## the cursor should move past (auto-closed pairs, completion tabstops); it
  ## defaults to the end of the text. This is also used internally for
  ## undo/redo operations.
  ##
  ## `atByte` overrides where in the line the text is written, for undo putting
  ## bytes back into a hole it recorded: after the edit that made the hole,
  ## `pos.column` may no longer walk to it.
  if '\n' notin text:
    # Simple case: no newlines, just insert into current line
    let line = b.getLine(pos.line)
    let bytePos =
      if atByte >= 0:
        atByte
      else:
        charToBytePos(line, pos.column)
    b.backendInsertIntoLine(pos.line, bytePos, text)

    let cursorOffset = if cursorByte < 0: text.len else: cursorByte
    # A seam absorbs only where a lead byte still waiting for its continuation
    # bytes meets continuation bytes (the line's tail meeting the text, or the
    # text's tail meeting the rest of the line).
    let absorbs =
      absorbsAtSeam(line, bytePos, text) or
      (text.mayAbsorbAtSeam and bytePos < line.len and line[bytePos].isContinuationByte)
    if not absorbs:
      let gained = text.charLen
      return InsertOutcome(
        insertEnd: BufferPosition(line: pos.line, column: pos.column + gained),
        cursor: BufferPosition(
          line: pos.line, column: pos.column + text.byteToCharPos(cursorOffset)
        ),
        colDelta: gained,
        byteOffset: bytePos,
      )

    # Read the line back rather than rebuilding it here: the backend owns what
    # it stored, and a second copy of its insert semantics could drift from it.
    let merged = b.getLine(pos.line)
    return InsertOutcome(
      insertEnd:
        BufferPosition(line: pos.line, column: merged.byteToCharPos(bytePos + text.len)),
      cursor: BufferPosition(
        line: pos.line, column: merged.byteToCharPos(bytePos + cursorOffset)
      ),
      colDelta: merged.charLen - line.charLen,
      byteOffset: bytePos,
    )
  else:
    # Complex case: text contains newlines, need to split current line and insert multiple lines
    let
      currentLine = b.getLine(pos.line)
      currentLineLen = currentLine.charLen

    # Split current line at insertion position
    let splitByte =
      if atByte >= 0:
        atByte
      elif pos.column < currentLineLen:
        charToBytePos(currentLine, pos.column)
      else:
        currentLine.len
    let
      prefix = currentLine[0 ..< splitByte]
      suffix = currentLine[splitByte .. ^1]

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

    # A byte offset into the written text, as a position on the line that byte
    # ended up on. Each line is measured whole, so a seam counts once, not
    # twice; the first line carries the prefix before the written bytes.
    proc positionAtWrittenByte(target: int): BufferPosition =
      var lineStart = 0
      for i, part in insertedLines:
        if target <= lineStart + part.len or i == insertedLines.high:
          let onLine = target - lineStart
          let leading = if i == 0: prefix.len else: 0
          return BufferPosition(
            line: pos.line + i, column: newLines[i].byteToCharPos(leading + onLine)
          )
        # +1 for the newline that separated this part from the next.
        lineStart += part.len + 1

    let endPos = positionAtWrittenByte(text.len)
    # colDelta describes a single-line edit; a multi-line insert is reported to
    # subscribers as whole rows moving.
    result = InsertOutcome(
      insertEnd: endPos,
      cursor:
        if cursorByte < 0 or cursorByte >= text.len:
          endPos
        else:
          positionAtWrittenByte(cursorByte),
      colDelta: 0,
      byteOffset: prefix.len,
    )

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
          line.charSubStr(0, startPos.column)
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
          line.charSubStr(0, startPos.column)
        else:
          ""
      b.backendDeleteLine(startPos.line)
      b.backendInsertLine(startPos.line, newLine)
  elif startPos.column < lineLen and endPos.column < lineLen:
    # Normal single-line deletion within bounds
    # Build new line by concatenating prefix and suffix using Unicode-safe substring
    let prefix = line.charSubStr(0, startPos.column)
    let suffix = line.charSubStr(endPos.column + 1)
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
      startLine.charSubStr(0, startPos.column)
    else:
      ""

  # Build suffix (chars after selection end)
  var suffix = ""
  var extraLineToDelete = -1

  if endPos.column < endLineLen:
    # Selection ends within the line - keep remaining chars
    suffix = endLine.charSubStr(endPos.column + 1)
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
