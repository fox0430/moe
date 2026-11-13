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

import std/[options, tables]

from std/strutils import replace, contains, count, join, rfind, split, strip

import pkg/results

import ../[primitives, unicode_utils]
from ../encoding import sanitizeInvalidUtf8
from ../highlight import SemanticOverlayLine
import core, internal_mutations, line_diff, undo
export LineEdit, LineDiff

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
  ## Make text a put brings in fit for `b`: CR line breaks become LF and
  ## invalid UTF-8 becomes U+FFFD; skipped for raw buffers.
  if b.allowsTextTransforms:
    text.sanitizeInvalidUtf8().normalizeNewlines()
  else:
    text

proc preparePastedRow*(b: TextBuffer, row: string): string =
  ## Make a block's row a put brings in fit for `b`, as `preparePastedText`
  ## does, but a CR breaks no line in a row: it goes, as no line of a decoded
  ## buffer holds one.
  b.preparePastedText(row).replace("\n", "")

# Editing operations
proc insertTextEnd*(
    b: TextBuffer,
    pos: BufferPosition,
    text: string,
    cursorByte: int = -1,
    openLine = olNone,
): Result[InsertOutcome, string] =
  ## Insert text at `pos`, handling newlines. CR normalized for decoded buffers only.
  ## Returns end and cursor positions, or error if out of bounds. `openLine`
  ## marks text opening whole lines beside `pos`; ignored where it does not
  ## apply.
  if b.readOnly:
    return err("Buffer is read-only")
  if text.len == 0:
    return ok(InsertOutcome(insertEnd: pos, cursor: pos, colDelta: 0))

  if pos.line < 0 or pos.line >= b.len:
    return err("Line position out of bounds: " & $pos.line)

  if pos.column < 0:
    return err("Column position cannot be negative: " & $pos.column)

  let
    normalized = b.normalizeNewlines(text)
    # Recorded before the mutation: afterwards this tail is indistinguishable
    # from the inserted text.
    splitTailLen = max(0, b.getLine(pos.line).charLen - pos.column)
    opened =
      case openLine
      of olBelow:
        if splitTailLen == 0 and normalized[0] == '\n': olBelow else: olNone
      of olAbove:
        if pos.column == 0 and normalized[^1] == '\n': olAbove else: olNone
      of olNone:
        olNone

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
      insertSplitTailLen: splitTailLen,
      insertOpenLine: opened,
    )
  )

  return ok(outcome)

proc insertText*(
    b: TextBuffer, pos: BufferPosition, text: string, openLine = olNone
): Result[(), string] =
  ## `insertTextEnd` for callers that place no cursor after the insertion.
  let r = b.insertTextEnd(pos, text, openLine = openLine)
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

  # Line arrays follow in pushUndoChange.
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

  # Line arrays follow in pushUndoChange.
  b.pushUndoChange(
    BufferChange(
      kind: ckDeleteLine, deleteLineIdx: lineIndex, deletedLineText: deletedContent
    )
  )

  return ok(())

proc hunksOf(b: TextBuffer, spans: openArray[LineEdit]): Result[seq[LineHunk], string] =
  ## The hunks that swap `spans`, ascending and apart, CR stripped for decoded
  ## buffers; empty when they change nothing, or why they are refused.
  if b.readOnly:
    return err("Buffer is read-only")
  var
    hunks = newSeqOfCap[LineHunk](spans.len)
    lenAfter = b.len
    shift = 0
    below = 0
  for span in spans:
    if span.start < below or span.start > b.len:
      return err(
        "Line index out of valid range [" & $below & ".." & $b.len & "]: " & $span.start
      )
    if span.delete < 0 or span.start + span.delete > b.len:
      return err("Line range out of bounds: " & $span.start & " + " & $span.delete)
    below = span.start + span.delete
    if span.delete == 0 and span.insert.len == 0:
      continue
    var hunk = LineHunk(
      start: span.start + shift,
      oldText: newSeqOfCap[string](span.delete),
      newText: newSeqOfCap[string](span.insert.len),
    )
    for i, line in span.insert:
      if '\n' in line:
        return err("Line " & $i & " of the replacement contains a line separator")
      hunk.newText.add b.stripCarriageReturns(line)
    for j in 0 ..< span.delete:
      hunk.oldText.add b.getLine(span.start + j)
    shift += span.insert.len - span.delete
    lenAfter += span.insert.len - span.delete
    hunks.add move(hunk)
  # A buffer always holds a line; clearing one means leaving a single empty one.
  if hunks.len > 0 and lenAfter == 0:
    return err("Replacing the whole buffer with nothing would leave it empty")
  ok(hunks)

proc swapSpans(
    b: TextBuffer, spans: openArray[LineEdit], keepRows: bool, column: int
): Result[(), string] =
  ## Swap `spans`, top down and apart, as one change; see replaceLineSpans.
  var hunks = ?b.hunksOf(spans)
  if hunks.len == 0:
    return ok(())

  b.captureSnapshotIfNeeded()
  for i, hunk in hunks:
    let lenBefore = b.len
    try:
      b.backendReplaceLines(hunk.start, hunk.oldText.len, hunk.newText)
    except CatchableError, IndexDefect:
      # IndexDefect is internal inconsistency. A span takes several backend
      # calls, so a failure part way leaves part of it applied; put the old
      # text back, since nothing is recorded yet.
      let e = getCurrentException()
      var rolledBack = true
      try:
        b.backendReplaceLines(
          hunk.start, hunk.oldText.len + (b.len - lenBefore), hunk.oldText
        )
        for j in countdown(i - 1, 0):
          b.backendReplaceLines(hunks[j].start, hunks[j].newText.len, hunks[j].oldText)
      except CatchableError, IndexDefect:
        rolledBack = false
      b.discardPendingSnapshot()
      if not rolledBack:
        return err("Failed to replace lines, buffer left partially rewritten: " & e.msg)
      return err("Failed to replace lines: " & e.msg)

  # Line arrays follow in pushUndoChange.
  b.pushUndoChange(
    BufferChange(
      kind: ckReplaceLines,
      replaceLinesHunks: move hunks,
      replaceLinesColumn: column,
      replaceLinesKeepRows: keepRows,
    )
  )
  ok(())

proc replaceLines*(
    b: TextBuffer,
    start: int,
    delete: int,
    lines: openArray[string],
    keepRows: bool = true,
    column = 0,
): Result[(), string] =
  ## Swap the `delete` lines at `start` for `lines`, as one change recorded and
  ## reported to the row-remap subscribers once, so the per-line side arrays
  ## shift once instead of once per rewritten line.
  ##
  ## `keepRows = false` gives the old rows up: their markers, folds and
  ## bookmarks go with them instead of staying on unrelated replacement text.
  ## `column` is where the rewrite starts on the first line, which undo and the
  ## changelist report as the change's position.
  ##
  ## CR is stripped for decoded buffers; lines must not contain separators.
  b.swapSpans(
    [LineEdit(start: start, delete: delete, insert: @lines)], keepRows, column
  )

proc replaceLineSpans*(
    b: TextBuffer, spans: openArray[LineEdit], keepRows: bool = true
): Result[(), string] =
  ## Swap `spans`, ascending and apart, as one change: undo takes them back
  ## together, and the side arrays and semantic overlay shift once. `keepRows`
  ## and CR stripping are as for replaceLines.
  b.swapSpans(spans, keepRows, column = 0)

# A NoUndo swap skips undo and changeSeq and moves only what is drawn over the
# text, which revertNoUndo moves back. Marks, the last Visual area and jumps
# stay put; the per-line arrays shift unmarked with the rows it adds or drops.
const NoUndoFollowers = {efSemantic, efFolds, efBookmarks, efDiagnostics}

type NoUndoSwap* = object
  ## A swap replaceLineSpansNoUndo made, for revertNoUndo to take back.
  change: BufferChange
  semantic: seq[seq[Option[SemanticOverlayLine]]]
    ## The overlay on each hunk's replaced rows, which moving back across the
    ## swap cannot rebuild: it drops the tokens an edit cuts into.
  version: int ## The buffer's contentVersion just after the swap

proc replaceLineSpansNoUndo*(
    b: TextBuffer, spans: openArray[LineEdit]
): Option[NoUndoSwap] =
  ## Swap `spans` like replaceLineSpans, without recording undo, and return
  ## the swap for revertNoUndo; none when nothing changes or it would refuse.
  let hunks = b.hunksOf(spans).valueOr:
    return none(NoUndoSwap)
  if hunks.len == 0:
    return none(NoUndoSwap)
  var semantic: seq[seq[Option[SemanticOverlayLine]]]
  if not b.highlight.isNil and b.highlight.semantic.len > 0:
    semantic.setLen(hunks.len)
    var shift = 0
    for k, hunk in hunks:
      let at = hunk.start - shift
      semantic[k].setLen(hunk.oldText.len)
      for i in 0 ..< hunk.oldText.len:
        b.highlight.semantic.withValue(at + i, line):
          semantic[k][i] = some(line[])
      shift += hunk.newText.len - hunk.oldText.len
  for hunk in hunks:
    b.backendReplaceLines(hunk.start, hunk.oldText.len, hunk.newText)
  b.advanceContentVersion()
  let change = BufferChange(
    kind: ckReplaceLines, replaceLinesHunks: hunks, replaceLinesKeepRows: true
  )
  b.followChange(change, NoUndoFollowers)
  b.shiftLineArraysUnmarked(change)
  some(NoUndoSwap(change: change, semantic: semantic, version: b.contentVersion))

proc replaceLinesNoUndo*(
    b: TextBuffer, start, delete: int, lines: openArray[string]
): Option[NoUndoSwap] =
  ## replaceLineSpansNoUndo of one span.
  b.replaceLineSpansNoUndo([LineEdit(start: start, delete: delete, insert: @lines)])

proc revertNoUndo*(b: TextBuffer, swap: NoUndoSwap): bool =
  ## Take back `swap` as undo does; false when the buffer changed since, as
  ## the swap no longer says where its rows are. Rows it dropped lose their
  ## folds and bookmarks, though previews drop none.
  if b.contentVersion != swap.version:
    return false
  let hunks = swap.change.replaceLinesHunks
  for i in countdown(hunks.high, 0):
    b.backendReplaceLines(hunks[i].start, hunks[i].newText.len, hunks[i].oldText)
  b.advanceContentVersion()
  b.followChange(swap.change, NoUndoFollowers, undone = true)
  b.shiftLineArraysUnmarked(swap.change, undone = true)
  if not b.highlight.isNil:
    var shift = 0
    for k, hunk in hunks:
      let at = hunk.start - shift
      for j in 0 ..< hunk.oldText.len:
        if k < swap.semantic.len and swap.semantic[k][j].isSome:
          b.highlight.semantic[at + j] = swap.semantic[k][j].get
        else:
          b.highlight.semantic.del(at + j)
      shift += hunk.newText.len - hunk.oldText.len
  true

proc lineBefore*(b: TextBuffer, swap: NoUndoSwap, index: int): string =
  ## Line `index` of the text as it was before `swap`; empty past its end.
  var shift = 0
  for hunk in swap.change.replaceLinesHunks:
    let at = hunk.start - shift
    if index < at:
      break
    if index < at + hunk.oldText.len:
      return hunk.oldText[index - at]
    shift += hunk.newText.len - hunk.oldText.len
  let row = index + shift
  if row >= 0 and row < b.len:
    b.getLine(row)
  else:
    ""

proc markAcross*(
    b: TextBuffer, pos: BufferPosition, swap: NoUndoSwap
): Option[BufferPosition] =
  ## Where `swap` took a mark at `pos`; none when it dropped its row.
  b.markAcross(pos, swap.change)

proc deleteAllLines*(b: TextBuffer): Result[(), string] =
  ## Delete every line, leaving one empty line. The empty line is added below
  ## first so the old rows are all dropped: their marks, folds and bookmarks
  ## go (and come back on undo), and the last Visual area lands on line 0.
  if not b.inTransaction:
    return withTransaction(b, "delete all lines"):
      let r = b.deleteAllLines()
      if r.isErr:
        return r
  let count = b.len
  let inserted = b.insert(count, "")
  if inserted.isErr:
    return inserted
  b.replaceLines(0, count, [], keepRows = false)

proc linewiseText*(b: TextBuffer, first, last: int): string =
  ## Lines `first` to `last` as linewise register text: each ends in a line
  ## break.
  for lineIdx in first .. min(last, b.len - 1):
    result.add(b.getLine(lineIdx))
    result.add('\n')

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

  let rangeColDelta =
    if startPos.line == endPos.line and not joinedWithNext:
      b.getLine(startPos.line).charLen - startLine.charLen
    else:
      0

  # Line arrays follow in pushUndoChange.
  b.pushUndoChange(
    BufferChange(
      kind: ckDeleteRange,
      deleteStartPos: startPos,
      deleteEndPos: endPos,
      deletedRangeText: deletedText,
      deleteJoinedNextLine: joinedWithNext,
      deleteRangeByteOffset: startByte,
      deleteRangeColDelta: rangeColDelta,
    )
  )

  return ok(())

proc replaceSpan*(
    b: TextBuffer, first, last: BufferPosition, text: string
): Result[(), string] =
  ## Replace the text from `first` up to `last` (exclusive) with `text`, as
  ## Neovim's nvim_buf_set_text does for an API edit: the windows and jumps on
  ## the buffer follow the span replaced as a whole.
  var replaced = SpanEdit(start: first, oldEnd: first, newEnd: first)
  b.replacingSpan(replaced):
    if first < last:
      let lastIn =
        if last.column > 0:
          BufferPosition(line: last.line, column: last.column - 1)
        else:
          # The line break before `last`, which a column past the line covers.
          let
            above = last.line - 1
            column =
              if above in 0 ..< b.len:
                b.getLine(above).charLen
              else:
                0
          BufferPosition(line: above, column: column)
      let deleted = b.deleteRange(first, lastIn)
      if deleted.isErr:
        return err("Failed to delete range: " & deleted.error)
      replaced.oldEnd = last
    if text.len > 0:
      let inserted = b.insertTextEnd(first, text)
      if inserted.isErr:
        return err("Failed to insert text: " & inserted.error)
      replaced.newEnd = inserted.get.insertEnd
  ok(())

proc splitLine*(b: TextBuffer, pos: BufferPosition): Result[(), string] =
  ## Split line at the specified position by inserting a newline
  ## Returns error if position is out of bounds
  b.insertText(pos, "\n")

proc joinWithNextLine*(b: TextBuffer, line: int): Result[BufferPosition, string] =
  ## Join `line` and the next by deleting the break alone, so marks follow the
  ## join. ok is where the next line's text starts, measured after the merge:
  ## the joined text can complete a character `line` ended part of.
  if line < 0 or line + 1 >= b.len:
    return err("No line to join with")
  let
    prevLine = b.getLine(line)
    breakPos = BufferPosition(line: line, column: prevLine.charLen)
  let deleteResult = b.deleteRange(breakPos, breakPos)
  if deleteResult.isErr:
    return err(deleteResult.error)
  ok(BufferPosition(line: line, column: b.getLine(line).byteToCharPos(prevLine.len)))

proc joinLines*(
    b: TextBuffer, startLine: int, lines: int = 2, undoCursor = none(BufferPosition)
): Result[BufferPosition, string] =
  ## Join `lines` lines starting from startLine, as many as there are; one
  ## joins nothing, as Vim's do_join, but still fails where a join would.
  ## Undo puts the cursor at `undoCursor`, else at startLine's start.
  ## ok is the last join, on a character, where Vim's J leaves the cursor.

  if b.readOnly:
    return err("Buffer is read-only")
  if startLine < 0 or startLine >= b.len:
    return err("Line index out of bounds: " & $startLine)
  let linesToJoin = min(lines, b.len - startLine)
  if linesToJoin < 2:
    if lines < 2:
      return ok(BufferPosition(line: startLine, column: 0))
    return err("No line to join with")
  # Join modifies whitespace; refused for raw buffers.
  if not b.allowsTextTransforms:
    return err(rawBytesRejection("join lines"))

  var lastJoin = 0
  let txr = withTransaction(
    b,
    "join " & $linesToJoin & " lines",
    some(undoCursor.get(BufferPosition(line: startLine, column: 0))),
  ):
    for i in 1 ..< linesToJoin:
      let currentLine = b.getLine(startLine)
      let nextLine = b.getLine(startLine + 1)
      let
        marksBeforeJoin = b.namedMarks
        visualBeforeJoin = b.lastVisual

      # Blanks are space and tab alone, as Vim's.
      let trimmedCurrent = strip(currentLine, leading = false, chars = {' ', '\t'})
      let trimmedNext = strip(nextLine, trailing = false, chars = {' ', '\t'})
      let leadingTrim = nextLine.charLen - trimmedNext.charLen

      # Vim J: separate joined lines with a space, but not when the next line
      # begins with ')'.
      let separated =
        trimmedCurrent.len > 0 and trimmedNext.len > 0 and trimmedNext[0] != ')'
      # Where Vim's J starts the next line's text: it keeps trailing blanks and
      # then adds no space.
      let vimNextStart =
        currentLine.charLen + ord(separated and trimmedCurrent.len == currentLine.len)
      let joinAt = BufferPosition(line: startLine, column: trimmedCurrent.charLen)
      let joinedPrefixLen = joinAt.column + ord(separated)
      lastJoin =
        if trimmedCurrent.len < currentLine.len: joinedPrefixLen else: joinAt.column

      # Edit as text so followers on either side move with it, on undo too;
      # space goes in first.
      if separated:
        let insertResult = b.insertText(joinAt, " ")
        if insertResult.isErr:
          return err(insertResult.error)
      let blanksEnd =
        if leadingTrim > 0:
          BufferPosition(line: startLine + 1, column: leadingTrim - 1)
        else:
          BufferPosition(line: startLine, column: currentLine.charLen + ord(separated))
      let deleteResult = b.deleteRange(
        BufferPosition(line: startLine, column: joinedPrefixLen), blanksEnd
      )
      if deleteResult.isErr:
        return err(deleteResult.error)

      # Not clamped to the joined line, as in Vim: readers clamp. A column in
      # the trailing blanks trimmed here goes to the join; one past the line
      # end stays on the text Vim's J puts there.
      proc joined(pos: BufferPosition): Option[BufferPosition] =
        if pos.line == startLine:
          let column =
            if pos.column < currentLine.charLen:
              min(pos.column, joinedPrefixLen)
            else:
              pos.column + joinedPrefixLen - vimNextStart
          some(BufferPosition(line: startLine, column: column))
        elif pos.line == startLine + 1:
          some(
            BufferPosition(
              line: startLine,
              column: joinedPrefixLen + max(0, pos.column - leadingTrim),
            )
          )
        else:
          none(BufferPosition)

      for name in 'a' .. 'z':
        if marksBeforeJoin[name].isSome:
          let moved = joined(marksBeforeJoin[name].get)
          if moved.isSome:
            b.namedMarks[name] = moved
      if visualBeforeJoin.isSome:
        b.moveLastVisualEnds(
          joined(visualBeforeJoin.get.start), joined(visualBeforeJoin.get.cursor)
        )

  if txr.isErr:
    return err(txr.error)

  let lastColumn = max(0, b.getLine(startLine).charLen - 1)
  return ok(BufferPosition(line: startLine, column: min(lastJoin, lastColumn)))

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

  # A rewrite that leaves the line breaks in place keeps its rows, so what is
  # attached to them (marks, the last Visual area) stays where it was instead
  # of collapsing onto the start of a delete and insert.
  let rows = text.count('\n')
  if rows > 0 and newText.count('\n') == rows and startPos.line + rows < b.len:
    # The lines between are whole in `text`; only its two ends can be cut short.
    let
      firstLine = b.getLine(startPos.line)
      lastLine = b.getLine(startPos.line + rows)
      head = text[0 ..< text.find('\n')]
      tail = text[text.rfind('\n') + 1 .. ^1]
      prefix = firstLine.charSubStr(0, startPos.column)
      suffix = lastLine.charSubStr(tail.charLen)
    if firstLine == prefix & head and lastLine == tail & suffix:
      var lines = strutils.split(newText, '\n')
      lines[0] = prefix & lines[0]
      lines[^1].add suffix
      return b.replaceLines(startPos.line, rows + 1, lines, column = startPos.column)

  let deleteResult = b.deleteRange(startPos, endPos)
  if deleteResult.isErr:
    return err(deleteResult.error)

  if newText.len > 0:
    let insertResult = b.insertText(startPos, newText)
    if insertResult.isErr:
      return err(insertResult.error)

  ok(())

proc replaceWholeLines*(
    b: TextBuffer,
    startLine, endLine: int,
    action: string,
    fill: proc(text: string): string {.closure, gcsafe.},
): Result[(), string] =
  ## Replace each non-empty line in [startLine, endLine]. Call in a transaction.
  for lineNum in startLine .. endLine:
    let lineCharLen = b.getLine(lineNum).charLen
    if lineCharLen > 0:
      let res = b.transformRange(
        BufferPosition(line: lineNum, column: 0),
        BufferPosition(line: lineNum, column: lineCharLen - 1),
        action,
        fill,
      )
      if res.isErr:
        return err(res.error)
  ok(())

proc replaceAllLines*(
    b: TextBuffer,
    newLines: openArray[string],
    description: string = "replace lines",
    requireExact: bool = false,
): Result[LineDiff, string] =
  ## Make the buffer hold exactly `newLines`, as one undo entry described by
  ## `description`. Only the lines that actually differ are touched, so markers,
  ## folds and bookmarks on the rest survive; returns the hunks applied, empty
  ## when nothing changed. No replacement lines at all means one empty line.
  ##
  ## When the two sides are too far apart for a minimal edit, or share no line
  ## at all, a whole span is rewritten and what was attached to it is lost.
  ## `requireExact` refuses instead, for a caller that cannot afford that.
  ##
  ## `newLines` comes from outside the buffer, so it is sanitized like pasted
  ## text (CR stripped, invalid UTF-8 replaced) before it is diffed; raw buffers
  ## are refused.
  if b.readOnly:
    return err("Buffer is read-only")
  if not b.allowsTextTransforms:
    return err(rawBytesRejection("replace lines"))

  var normalized = newSeqOfCap[string](max(newLines.len, 1))
  for i, line in newLines:
    if '\n' in line:
      return err("Line " & $i & " of the replacement contains a line separator")
    normalized.add b.stripCarriageReturns(line.sanitizeInvalidUtf8())
  if normalized.len == 0:
    # An empty buffer holds one empty line, so a filter that answered with
    # nothing lands here rather than on an error.
    normalized.add ""

  var oldLines = newSeqOfCap[string](b.len)
  for line in b.lines:
    oldLines.add line

  let diff = diffLines(oldLines, normalized)
  if diff.hunks.len == 0:
    return ok(LineDiff(hunks: @[], exact: true, coarse: false))
  if requireExact and diff.coarse:
    return err("Replacement is too far from the buffer for a minimal edit")

  # All hunks as one change, so the side arrays shift once for the lot.
  let txr = withTransaction(b, description):
    # A coarse hunk puts unrelated text on the lines it covers, so what was
    # attached to them goes with the old lines; a line-by-line script keeps the
    # rows both sides share.
    let r = b.replaceLineSpans(diff.hunks, keepRows = not diff.coarse)
    if r.isErr:
      return err(r.error)
  if txr.isErr:
    return err(txr.error)

  ok(diff)
