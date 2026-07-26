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

proc replaceLine*(b: TextBuffer, lineNumber: int, content: string): Result[(), string] =
  ## Replace line content with undo recording.
  ## Line content must not contain line separators; any stray CR is stripped
  ## defensively so it cannot corrupt terminal rendering.
  if b.readOnly:
    return err("Buffer is read-only")
  if lineNumber < 0 or lineNumber >= b.len:
    return err("Line index out of bounds: " & $lineNumber)
  let oldContent = b.getLine(lineNumber)
  let normalizedContent = content.replace("\r", "")
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
  ## Normalize CRLF and lone CR to LF so a stray \r never reaches line content.
  ## Backends treat only \n as a line separator (an embedded \r corrupts
  ## terminal rendering). Note this converts CR into a line break, unlike the
  ## line-level replaceLine/insert which strip it (line content must hold no
  ## separator). Returns the input untouched when it has no \r (the common
  ## per-keystroke case) to avoid allocating.
  if '\r' notin text:
    return text
  text.replace("\r\n", "\n").replace("\r", "\n")

# Editing operations
proc insertText*(b: TextBuffer, pos: BufferPosition, text: string): Result[(), string] =
  ## Insert text at the specified position
  ## Handles newlines by splitting lines as needed
  ## CRLF / lone CR in `text` are normalized to LF (matching loadFile) so pasted
  ## or LSP-supplied content never embeds a raw \r in line content.
  ## Returns error if position is out of bounds
  if b.readOnly:
    return err("Buffer is read-only")
  if text.len == 0:
    return ok(())

  if pos.line < 0 or pos.line >= b.len:
    return err("Line position out of bounds: " & $pos.line)

  if pos.column < 0:
    return err("Column position cannot be negative: " & $pos.column)

  let normalized = normalizeNewlines(text)

  b.captureSnapshotIfNeeded()

  case b.backendKind
  of GapBuffer, SqrtDecomp, Rope, PieceTable:
    try:
      # Use insertTextWithNewlines to handle newlines correctly
      b.insertTextWithNewlines(pos, normalized)
    except IndexDefect as e:
      b.discardPendingSnapshot()
      return err("Failed to insert text: " & e.msg)

  # Record normalized text for undo so redo never reintroduces a raw \r
  b.pushUndoChange(
    BufferChange(kind: ckInsertText, insertPos: pos, insertText: normalized)
  )

  return ok(())

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
      # Get the character that will be deleted for undo
      let
        deletedChar = line.runeAtPos(pos.column)
        charSize = len($deletedChar)
        bytePos = charToBytePos(line, pos.column)

      # Delete character at byte position
      b.backendDeleteAtLineCol(pos.line, bytePos, charSize)

      # Record change for undo
      b.pushUndoChange(
        BufferChange(kind: ckDeleteText, deletePos: pos, deletedText: $deletedChar)
      )
    except IndexDefect as e:
      b.discardPendingSnapshot()
      return err("Failed to delete character: " & e.msg)

  return ok(())

proc insert*(b: TextBuffer, lineIndex: int, content: string): Result[(), string] =
  ## Insert a new line at the specified index
  ## Returns error if lineIndex is out of valid range [0..len]
  ## Line content must not contain line separators; any stray CR is stripped
  ## defensively so it cannot corrupt terminal rendering.
  if b.readOnly:
    return err("Buffer is read-only")
  if lineIndex < 0 or lineIndex > b.len:
    return err("Line index out of valid range [0.." & $b.len & "]: " & $lineIndex)

  let normalizedContent = content.replace("\r", "")

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
      # Selection extends to/past line end - include newline
      if startCol >= lineLen:
        result = "\n"
      else:
        result = line.runeSubStr(startCol) & "\n"
    else:
      # Selection within line
      if startCol >= lineLen:
        result = ""
      elif startCol == endCol:
        # Single character
        result = $line.runeAtPos(startCol)
      else:
        result = line.runeSubStr(startCol, endCol - startCol + 1)
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
          result &= line.runeSubStr(startCol) & "\n"
      elif lineIdx == endPos.line:
        # Last line: from beginning to endPos.column
        let endCol = min(endPos.column, lineLen)
        if endCol >= lineLen:
          result &= line & "\n"
        else:
          result &= line.runeSubStr(0, endCol + 1)
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

  # Save deleted text for undo
  let deletedText = b.getTextInRange(startPos, endPos)

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
