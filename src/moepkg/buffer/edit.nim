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

## Public editing API: insertText / deleteChar / insert / deleteLine /
## deleteRange / replaceLine / splitLine / NoUndo bypass procs.

import std/unicode

from std/strutils import replace, contains

import pkg/results

import ../[primitives, unicode_utils]
from ../encoding import sanitizeInvalidUtf8
import core, internal_mutations, undo

# NoUndo procs: skip undo/changeSeq but must shift semantic overlay / folds /
# bookmarks. lineMarkers/modifiedLines are held back via includeSideArrays=false
# so substitute-preview does not mark previewed lines as modified in the sidebar.
proc replaceLineNoUndo*(b: TextBuffer, lineNumber: int, content: string) =
  ## Replace line content without recording undo. Used by substitute preview etc.
  if b.readOnly:
    return
  b.backendReplaceLine(lineNumber, content)
  b.advanceContentVersion()
  b.emitRowColRemapEvents(
    BufferChange(kind: ckReplaceLine, replaceLineIdx: lineNumber),
    includeSideArrays = false,
  )

proc deleteLineNoUndo*(b: TextBuffer, lineNumber: int) =
  ## Delete a line without recording undo. Used by substitute preview etc.
  if b.readOnly:
    return
  b.backendDeleteLine(lineNumber)
  b.advanceContentVersion()
  b.emitRowColRemapEvents(
    BufferChange(kind: ckDeleteLine, deleteLineIdx: lineNumber),
    includeSideArrays = false,
  )

proc insertLineNoUndo*(b: TextBuffer, lineNumber: int, content: string) =
  ## Insert a line without recording undo. Used by substitute preview etc.
  if b.readOnly:
    return
  b.backendInsertLine(lineNumber, content)
  b.advanceContentVersion()
  b.emitRowColRemapEvents(
    BufferChange(kind: ckInsertLine, insertLineIdx: lineNumber),
    includeSideArrays = false,
  )

proc stripCarriageReturns(b: TextBuffer, content: string): string =
  ## Strip CR to avoid rendering corruption; skipped for raw buffers.
  if b.allowsTextTransforms:
    content.replace("\r", "")
  else:
    content

proc replaceLine*(b: TextBuffer, lineNumber: int, content: string): Result[(), string] =
  ## Replace line content with undo recording. CR stripped only for decoded buffers.
  ## Line must not contain separators.
  if b.readOnly:
    return err("Buffer is read-only")
  if lineNumber < 0 or lineNumber >= b.len:
    return err("Line index out of bounds: " & $lineNumber)
  let oldContent = b.getLine(lineNumber)
  let normalizedContent = b.stripCarriageReturns(content)
  b.captureSnapshotIfNeeded()
  try:
    b.backendReplaceLine(lineNumber, normalizedContent)
  except CatchableError as e:
    b.discardPendingSnapshot()
    return err("Failed to replace line: " & e.msg)
  b.pushUndoChange(
    BufferChange(
      kind: ckReplaceLine,
      replaceLineIdx: lineNumber,
      replaceLineOldText: oldContent,
      replaceLineNewText: normalizedContent,
    )
  )
  return ok(())

proc normalizeNewlines*(text: string): string =
  ## Normalize CR/CRLF to LF for external text (paste/clipboard). No-op if no CR.
  if '\r' notin text:
    return text
  text.replace("\r\n", "\n").replace("\r", "\n")

proc normalizeNewlines*(b: TextBuffer, text: string): string =
  ## Normalize newlines for `b`; skipped for raw buffers.
  if b.allowsTextTransforms:
    normalizeNewlines(text)
  else:
    text

proc preparePastedText*(b: TextBuffer, text: string): string =
  ## Sanitize external text (CR, invalid UTF-8) for `b`; skipped for raw buffers.
  ## Register contents use `normalizeNewlines` instead.
  if b.allowsTextTransforms:
    text.sanitizeInvalidUtf8().normalizeNewlines()
  else:
    text

# Editing operations
proc insertTextEnd*(
    b: TextBuffer, pos: BufferPosition, text: string, cursorByte: int = -1
): Result[InsertOutcome, string] =
  ## Insert text at `pos`, handling newlines. CR normalized for decoded buffers only.
  ## Returns end and cursor positions, or error if out of bounds.
  if b.readOnly:
    return err("Buffer is read-only")
  if text.len == 0:
    return ok(InsertOutcome(insertEnd: pos, cursor: pos, colDelta: 0))

  if pos.line < 0 or pos.line >= b.len:
    return err("Line position out of bounds: " & $pos.line)

  if pos.column < 0:
    return err("Column position cannot be negative: " & $pos.column)

  let normalized = b.normalizeNewlines(text)

  b.captureSnapshotIfNeeded()

  var outcome: InsertOutcome
  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      # Use insertTextWithNewlines to handle newlines correctly
      outcome = b.insertTextWithNewlines(pos, normalized, cursorByte)
    except IndexDefect as e:
      b.discardPendingSnapshot()
      return err("Failed to insert text: " & e.msg)

  # Record actual bytes for redo.
  b.pushUndoChange(
    BufferChange(
      kind: ckInsertText,
      insertPos: pos,
      insertText: normalized,
      insertColDelta: outcome.colDelta,
      insertByteOffset: outcome.byteOffset,
    )
  )

  return ok(outcome)

proc insertText*(b: TextBuffer, pos: BufferPosition, text: string): Result[(), string] =
  ## `insertTextEnd` for callers that place no cursor after the insertion.
  let r = b.insertTextEnd(pos, text)
  if r.isErr:
    return err(r.error)
  ok(())

proc deleteChar*(b: TextBuffer, pos: BufferPosition): Result[(), string] =
  ## Delete a single Unicode character at the specified position
  ## Returns error if position is out of bounds
  if b.readOnly:
    return err("Buffer is read-only")
  if pos.line < 0 or pos.line >= b.len:
    return err("Line position out of bounds: " & $pos.line)

  if pos.column < 0:
    return err("Column position cannot be negative: " & $pos.column)

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    let line = b.getLine(pos.line)
    if pos.column >= line.charLen:
      b.discardPendingSnapshot()
      return err("Column position out of bounds: " & $pos.column)

    try:
      # Slice the source bytes rather than re-encoding the decoded rune: an
      # undecodable byte re-encodes wider than it is, which would delete a
      # neighbouring byte.
      let
        bytePos = charToBytePos(line, pos.column)
        charSize = line.runeSizeAt(bytePos)
        deletedChar = line[bytePos ..< bytePos + charSize]

      # Delete character at byte position
      b.backendDeleteAtLineCol(pos.line, bytePos, charSize)

      # One column lost, unless a lead byte before the hole absorbs the
      # following bytes. Check only the seam (≤3 bytes) instead of
      # re-measuring the whole line.
      let mergesAtSeam =
        line.mayAbsorbAtSeam(bytePos) and bytePos + charSize < line.len and
        line[bytePos + charSize].isContinuationByte

      # Record the byte the hole was made at along with those columns: neither
      # can be re-derived from `deletedChar` once the line has merged.
      b.pushUndoChange(
        BufferChange(
          kind: ckDeleteText,
          deletePos: pos,
          deletedText: deletedChar,
          deleteColDelta:
            if mergesAtSeam:
              b.getLine(pos.line).charLen - line.charLen
            else:
              -1,
          deleteByteOffset: bytePos,
        )
      )
    except IndexDefect as e:
      b.discardPendingSnapshot()
      return err("Failed to delete character: " & e.msg)

  return ok(())

proc insert*(b: TextBuffer, lineIndex: int, content: string): Result[(), string] =
  ## Insert a new line at `lineIndex`. CR stripped only for decoded buffers.
  ## Line must not contain separators.
  if b.readOnly:
    return err("Buffer is read-only")
  if lineIndex < 0 or lineIndex > b.len:
    return err("Line index out of valid range [0.." & $b.len & "]: " & $lineIndex)

  let normalizedContent = b.stripCarriageReturns(content)

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      b.backendInsertLine(lineIndex, normalizedContent)
    except IndexDefect as e:
      b.discardPendingSnapshot()
      return err("Failed to insert line: " & e.msg)

  # Side-array shifts run via the emitRowColRemapEvents subscribers.
  b.pushUndoChange(
    BufferChange(
      kind: ckInsertLine, insertLineIdx: lineIndex, insertLineText: normalizedContent
    )
  )

  return ok(())

proc deleteLine*(b: TextBuffer, lineIndex: int): Result[(), string] =
  ## Delete the line at the specified index
  ## Returns error if lineIndex is out of bounds
  if b.readOnly:
    return err("Buffer is read-only")
  if lineIndex < 0 or lineIndex >= b.len:
    return err("Line index out of bounds: " & $lineIndex)

  # Save line content before deleting for undo
  let deletedContent = b.getLine(lineIndex)

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      b.backendDeleteLine(lineIndex)
    except IndexDefect as e:
      b.discardPendingSnapshot()
      return err("Failed to delete line: " & e.msg)

  # Side-array shifts run via the emitRowColRemapEvents subscribers.
  b.pushUndoChange(
    BufferChange(
      kind: ckDeleteLine, deleteLineIdx: lineIndex, deletedLineText: deletedContent
    )
  )

  return ok(())

proc getTextInRange*(b: TextBuffer, startPos, endPos: BufferPosition): string =
  ## Get text from startPos to endPos (inclusive)
  ## Both positions use character indices (not byte indices)
  ## If positions are out of bounds, they are clamped to valid range
  if startPos.line == endPos.line:
    # Single line case
    let line = b[startPos.line]
    let lineLen = line.charLen

    # Clamp positions to valid range
    let
      startCol = min(startPos.column, lineLen)
      endCol = min(endPos.column, lineLen)

    if endCol >= lineLen:
      # Include the trailing newline only if a next line exists — otherwise
      # undo would insert a phantom byte that was never actually deleted.
      let tail = if startPos.line < b.len - 1: "\n" else: ""
      if startCol >= lineLen:
        result = tail
      else:
        result = line.charSubStr(startCol) & tail
    else:
      # Selection within line
      if startCol >= lineLen:
        result = ""
      else:
        # charSubStr slices the source bytes; `$runeAtPos` would re-encode an
        # undecodable byte into a wider sequence.
        result = line.charSubStr(startCol, endCol - startCol + 1)
  else:
    # Multi-line range
    for lineIdx in startPos.line .. endPos.line:
      let line = b.getLine(lineIdx)
      let lineLen = line.charLen

      if lineIdx == startPos.line:
        # First line: from startPos.column to end
        let startCol = min(startPos.column, lineLen)
        if startCol >= lineLen:
          result &= "\n"
        else:
          result &= line.charSubStr(startCol) & "\n"
      elif lineIdx == endPos.line:
        # Skip the trailing "\n" when no next line exists, to avoid a phantom
        # empty line on undo.
        let endCol = min(endPos.column, lineLen)
        let tail = if lineIdx < b.len - 1: "\n" else: ""
        if endCol >= lineLen:
          result &= line & tail
        else:
          result &= line.charSubStr(0, endCol + 1)
      else:
        # Middle lines: entire line
        result &= line & "\n"

proc deleteRange*(b: TextBuffer, startPos, endPos: BufferPosition): Result[(), string] =
  ## Delete text from startPos to endPos (inclusive)
  ## Assumes startPos <= endPos (normalized range)
  ## If selection extends to/past line end, includes the newline
  ## Returns error if positions are out of bounds

  if b.readOnly:
    return err("Buffer is read-only")
  if startPos.line < 0 or startPos.line >= b.len:
    return err("Start line position out of bounds: " & $startPos.line)

  if endPos.line < 0 or endPos.line >= b.len:
    return err("End line position out of bounds: " & $endPos.line)

  if startPos.column < 0 or endPos.column < 0:
    return err("Column positions cannot be negative")

  let startLine = b.getLine(startPos.line)
  if startPos.column > startLine.charLen:
    return err("Start column out of bounds: " & $startPos.column)

  # Save deleted text for undo, along with the byte the range starts at: after
  # the deletion the merged line may count its columns differently.
  let
    deletedText = b.getTextInRange(startPos, endPos)
    startByte = charToBytePos(startLine, startPos.column)

  b.captureSnapshotIfNeeded()

  var joinedWithNext = false
  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      if startPos.line == endPos.line:
        joinedWithNext =
          b.deleteRangeSingleLine(b.getLine(startPos.line), startPos, endPos)
      else:
        joinedWithNext = b.deleteRangeMultiLine(startPos, endPos)
    except IndexDefect as e:
      b.discardPendingSnapshot()
      return err("Failed to delete range: " & e.msg)

  # Side-array shifts run via the emitRowColRemapEvents subscribers.
  b.pushUndoChange(
    BufferChange(
      kind: ckDeleteRange,
      deleteStartPos: startPos,
      deleteEndPos: endPos,
      deletedRangeText: deletedText,
      deleteJoinedNextLine: joinedWithNext,
      deleteRangeByteOffset: startByte,
    )
  )

  return ok(())

proc splitLine*(b: TextBuffer, pos: BufferPosition): Result[(), string] =
  ## Split line at the specified position by inserting a newline
  ## Returns error if position is out of bounds
  b.insertText(pos, "\n")

proc joinLines*(b: TextBuffer, startLine: int, count: int = 1): Result[(), string] =
  ## Join lines starting from startLine
  ## count: number of lines to join (default: 1, meaning join current line with next)
  ## Example: count=1 joins 2 lines, count=2 joins 3 lines, etc.
  ## Returns error if there aren't enough lines to join

  if b.readOnly:
    return err("Buffer is read-only")
  # Join modifies whitespace; refused for raw buffers.
  if not b.allowsTextTransforms:
    return err(rawBytesRejection("join lines"))
  if startLine < 0 or startLine >= b.len:
    return err("Line index out of bounds: " & $startLine)

  # Need at least one more line to join with
  if startLine + 1 >= b.len:
    return err("No line to join with")

  # Calculate actual number of lines to join
  let linesToJoin = min(count + 1, b.len - startLine)
  if linesToJoin < 2:
    return err("Not enough lines to join")

  let txr = withTransaction(b, "join " & $linesToJoin & " lines"):
    for i in 1 ..< linesToJoin:
      let currentLine = b.getLine(startLine)
      let nextLine = b.getLine(startLine + 1)

      var trimmedCurrent = currentLine.strip(leading = false, trailing = true)
      let trimmedNext = nextLine.strip(leading = true, trailing = false)

      # Vim J: separate joined lines with a space, but not when the next line
      # begins with ')'.
      if trimmedCurrent.len > 0 and trimmedNext.len > 0 and trimmedNext[0] != ')':
        trimmedCurrent.add(' ')

      let joinedLine = trimmedCurrent & trimmedNext

      let deleteResult = b.deleteLine(startLine)
      if deleteResult.isErr:
        return err(deleteResult.error)

      let deleteNextResult = b.deleteLine(startLine)
      if deleteNextResult.isErr:
        return err(deleteNextResult.error)

      let insertResult = b.insert(startLine, joinedLine)
      if insertResult.isErr:
        return err(insertResult.error)

  if txr.isErr:
    return err(txr.error)

  return ok(())

proc transformRange*(
    b: TextBuffer,
    startPos, endPos: BufferPosition,
    action: string,
    transform: proc(text: string): string {.closure, gcsafe.},
): Result[(), string] =
  ## Replace range [startPos, endPos] via `transform`. Refused for raw buffers.
  ## Must run inside a transaction.
  if not b.allowsTextTransforms:
    return err(rawBytesRejection(action))

  if not b.inTransaction:
    return err("Cannot " & action & ": edit is not inside a transaction")

  let text = b.getTextInRange(startPos, endPos)
  let newText = transform(text)

  let deleteResult = b.deleteRange(startPos, endPos)
  if deleteResult.isErr:
    return err(deleteResult.error)

  if newText.len > 0:
    let insertResult = b.insertText(startPos, newText)
    if insertResult.isErr:
      return err(insertResult.error)

  ok(())
