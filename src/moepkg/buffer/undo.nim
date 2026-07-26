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

## Undo / Redo system: transaction grouping, ckSnapshot fast path for
## PieceTable, and the inverse-application helpers used by both undo()
## and redo().

import std/[deques, options]

import pkg/results

import ../[primitives, unicode_utils, logger]
import ../buffer_backends/piece_table
import core, internal_mutations

# Forward declaration: undoChange calls redoChange for ckTransaction
# roll-forward on partial failure. The reverse direction (redoChange ->
# undoChange) does not need one because undoChange is defined first.
# NOTE: this signature must stay in sync with the redoChange definition
# below. Nim does not cross-check the two — editing one without the other
# will silently call the wrong overload or fail at link time.
proc redoChange(b: TextBuffer, change: BufferChange): Result[(), string]

proc undoChange(b: TextBuffer, change: BufferChange): Result[(), string] =
  ## Apply the inverse of a single change (internal helper)
  ## Returns error if the operation fails
  try:
    case change.kind
    of ckInsertText:
      # Undo insert by deleting the inserted text (all bytes at once)
      let line = b.getLine(change.insertPos.line)
      let bytePos = charToBytePos(line, change.insertPos.column)
      b.backendDeleteAtLineCol(change.insertPos.line, bytePos, change.insertText.len)
    of ckDeleteText:
      # Undo delete by inserting the deleted text
      let line = b.getLine(change.deletePos.line)
      let bytePos = charToBytePos(line, change.deletePos.column)
      b.backendInsertIntoLine(change.deletePos.line, bytePos, change.deletedText)
    of ckInsertLine:
      # Undo insert line by deleting it
      b.backendDeleteLine(change.insertLineIdx)
    of ckDeleteLine:
      # Undo delete line by inserting it
      b.backendInsertLine(change.deleteLineIdx, change.deletedLineText)
    of ckDeleteRange:
      # Undo delete range by inserting the deleted text
      # Handle both single-line and multi-line deletions correctly
      b.insertTextWithNewlines(change.deleteStartPos, change.deletedRangeText)
    of ckReplaceLine:
      b.backendReplaceLine(change.replaceLineIdx, change.replaceLineOldText)
    of ckTransaction:
      # Undo all changes in transaction in reverse order. If one fails partway,
      # roll forward (redo) the inner changes we already undid so the buffer
      # ends up back at the pre-undo state instead of an intermediate one.
      let n = change.transactionChanges.len
      var i = n - 1
      while i >= 0:
        let r = b.undoChange(change.transactionChanges[i])
        if r.isErr:
          # Roll forward indices (i+1 .. n-1) which we already reverted.
          for j in (i + 1) .. (n - 1):
            let rr = b.redoChange(change.transactionChanges[j])
            if rr.isErr:
              logError(
                "buffer",
                "Failed to roll forward after partial transaction undo: " & rr.error,
              )
          return r
        dec i
    of ckSnapshot:
      b.storage.pieceTable.restoreSnapshot(change.snapshotData)
      b.lineMarkers = change.snapshotLineMarkers
      # b.modifiedLines currently holds the post-mutation state; reverse it.
      applyUndo(b.modifiedLines, change.modifiedLinesDelta)
      b.foldState = change.snapshotFoldState
      b.bookmarks = change.snapshotBookmarks
      b.lastChangedLines = 0

    # Drive the row-remap subscribers backwards. ckSnapshot restored state
    # wholesale; ckTransaction recurses through its inner changes.
    # `includeSideArrays=false`: the wholesale savedLineMarkers /
    # savedModifiedLines restore below would clobber their output.
    if change.kind notin {ckSnapshot, ckTransaction}:
      b.emitRowColRemapEvents(change, reverse = true, includeSideArrays = false)

    # For non-snapshot: restore modifiedLines from pre-mutation snapshot
    if change.kind != ckSnapshot and change.savedModifiedLines.len > 0:
      b.modifiedLines = change.savedModifiedLines

    # For non-snapshot: restore lineMarkers from pre-mutation snapshot
    if change.kind != ckSnapshot and change.savedLineMarkers.len > 0:
      b.lineMarkers = change.savedLineMarkers

    # Ensure lineMarkers and modifiedLines stay in sync after undo operations
    b.ensureMarkersSize()
    b.ensureModifiedLinesSize()
    return ok(())
  except CatchableError, Defect:
    # Defect is included so that backend IndexDefect (out-of-range line/col)
    # surfaces as a Result err and triggers the ckTransaction roll-forward
    # path, instead of crashing the editor mid-undo.
    let e = getCurrentException()
    logError("buffer", "Undo operation failed: " & e.msg)
    return err("Failed to undo change: " & e.msg)

proc makeInverseSnapshotEntry(b: TextBuffer, change: BufferChange): BufferChange =
  ## Build the inverse ckSnapshot entry for undo()/redo(). The piece tree,
  ## markers and folds are captured from the CURRENT (pre-restore) buffer; the
  ## bidirectional modifiedLinesDelta is shared as-is so the same delta drives
  ## both directions.
  BufferChange(
    startSeq: change.startSeq,
    endSeq: change.endSeq,
    id: change.id, # preserve identity across undo/redo
    kind: ckSnapshot,
    snapshotData: b.storage.pieceTable.takeSnapshot(),
    snapshotCursorPos: change.snapshotCursorPos,
    snapshotLineMarkers: b.lineMarkers,
    modifiedLinesDelta: change.modifiedLinesDelta,
    snapshotFoldState: b.foldState,
    snapshotBookmarks: b.bookmarks,
  )

proc clearMarkersIfAtSavedState(b: TextBuffer) {.inline.} =
  ## After undo/redo lands on the saved undo-tree node the buffer matches disk,
  ## so no line is session-modified. The pre-delta code restored this implicitly
  ## via the wholesale modifiedLines copy; the delta-based restore must do it
  ## on BOTH paths (redo() previously lacked this).
  if b.isAtSavedState:
    for i in 0 ..< b.modifiedLines.len:
      b.modifiedLines[i] = lmkUnmodified

proc beginTransaction*(
    b: TextBuffer,
    description: string = "",
    cursorPos: Option[BufferPosition] = none(BufferPosition),
): Result[(), string] =
  ## Begin a transaction to group multiple changes
  ## If cursorPos is provided, it will be used as the cursor position when undoing
  ## Returns error if a transaction is already in progress
  if b.inTransaction:
    let currentDesc =
      if b.currentTransaction.isSome:
        b.currentTransaction.get.description
      else:
        "(unknown)"
    return err("Transaction already in progress: " & currentDesc)

  b.captureSnapshotIfNeeded()
  b.inTransaction = true
  b.currentTransaction = some(
    BufferTransaction(
      changes: @[],
      description: description,
      startSeq: b.changeSeq,
      cursorPos: cursorPos,
    )
  )
  return ok(())

proc commitTransaction*(b: TextBuffer): Result[(), string] =
  ## Commit the current transaction
  ## Returns error if no transaction is in progress
  if not b.inTransaction or b.currentTransaction.isNone:
    return err("No transaction in progress")

  let transaction = b.currentTransaction.get
  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)

  # Add transaction as a single undo entry if it has changes
  if transaction.changes.len > 0:
    # changeSeq was inc'd once per inner change in pushUndoChange. Snapshot the
    # post-commit value so undo() can restore the pre-transaction state in one
    # step, regardless of inner change count.
    let preTxnSeq = transaction.startSeq
    let postTxnSeq = b.changeSeq
    if b.pendingSnapshot.isSome:
      # PieceTable: single O(1) snapshot undo entry for entire transaction
      b.undoStack.addLast(
        BufferChange(
          startSeq: preTxnSeq,
          endSeq: postTxnSeq,
          id: b.allocateChangeId(),
          kind: ckSnapshot,
          snapshotData: b.pendingSnapshot.get,
          snapshotCursorPos:
            if transaction.cursorPos.isSome:
              transaction.cursorPos.get
            else:
              getChangePosition(transaction.changes[0]),
          snapshotLineMarkers: b.pendingSnapshotMarkers,
          modifiedLinesDelta:
            computeDelta(b.pendingSnapshotModifiedLines, b.modifiedLines),
          snapshotFoldState: b.pendingSnapshotFolds,
          snapshotBookmarks: b.pendingSnapshotBookmarks,
        )
      )
      # Pending snapshot state is now consumed into the entry; reset it all.
      b.discardPendingSnapshot()
    else:
      let transactionChange = BufferChange(
        startSeq: preTxnSeq,
        endSeq: postTxnSeq,
        id: b.allocateChangeId(),
        kind: ckTransaction,
        transactionChanges: transaction.changes,
        transactionDescription: transaction.description,
        transactionCursorPos: transaction.cursorPos,
      )
      b.undoStack.addLast(transactionChange)
    # Note: changeSeq was inc'd per inner change in pushUndoChange; preTxnSeq /
    # postTxnSeq above let undo() / redo() restore changeSeq atomically.
    # Note: redoStack was already cleared by the first change in pushUndoChange

    # Record transaction position in changelist
    b.recordChangePosition(getChangePosition(transaction.changes[0]))

    # No lastChangedLines recompute needed: pushUndoChange min-merged each
    # inner change's line into the pending anchor via markLineChanged.
  else:
    # Zero-change transaction: beginTransaction captured a pending snapshot that
    # no undo entry consumes here. Discard it so the next edit's ckSnapshot
    # doesn't reuse this stale base and desync markers / folds on undo.
    b.discardPendingSnapshot()

  return ok(())

template withTransaction*(
    b: TextBuffer, description: string, cursorPos: Option[BufferPosition], body: untyped
): Result[(), string] =
  ## Scope-guarded begin/commit. Rolls back if `body` raises or returns from the
  ## enclosing proc, so `inTransaction` never leaks across edits.
  ## `body` runs inside a `block`, so a bare `break` escapes the template rather
  ## than an enclosing loop and leaves the result uninitialized: every `break` in
  ## `body` must belong to a loop `body` itself owns.
  block:
    let beginRes = b.beginTransaction(description, cursorPos)
    if beginRes.isErr:
      beginRes
    else:
      var completed = false
      try:
        body
        completed = true
      finally:
        if not completed:
          discard b.rollbackTransaction()
      b.commitTransaction()

template withTransaction*(
    b: TextBuffer, description: string, body: untyped
): Result[(), string] =
  withTransaction(b, description, none(BufferPosition), body)

proc rollbackTransaction*(b: TextBuffer): Result[(), string] =
  ## Rollback the current transaction by undoing all changes
  ## Restores changeSeq to its value at transaction start
  ## Returns error if no transaction is in progress
  if not b.inTransaction or b.currentTransaction.isNone:
    return err("No transaction in progress")

  # Undo all changes in transaction in reverse order
  let transaction = b.currentTransaction.get

  if b.pendingSnapshot.isSome:
    # PieceTable: O(1) restore from snapshot
    b.storage.pieceTable.restoreSnapshot(b.pendingSnapshot.get)
    b.lineMarkers = b.pendingSnapshotMarkers
    b.modifiedLines = b.pendingSnapshotModifiedLines
    b.foldState = b.pendingSnapshotFolds
    b.bookmarks = b.pendingSnapshotBookmarks
    # Drop every pending-snapshot artifact, matching commit/push cleanup, so a
    # later ckSnapshot delta is never computed against a rolled-back base.
    b.discardPendingSnapshot()
  else:
    for i in countdown(transaction.changes.len - 1, 0):
      let r = b.undoChange(transaction.changes[i])
      if r.isErr:
        # Clean up transaction state even if rollback partially fails
        b.inTransaction = false
        b.currentTransaction = none(BufferTransaction)
        return err("Failed to rollback transaction: " & r.error)

  # Restore changeSeq to its value at transaction start
  b.changeSeq = transaction.startSeq
  b.advanceContentVersion()

  # Mark highlight as needing update after rollback
  if transaction.changes.len > 0:
    var minLine = int.high
    for change in transaction.changes:
      minLine = min(minLine, getChangePosition(change).line)
    if minLine != int.high:
      b.markLineChanged(minLine)
    else:
      b.highlightNeedsUpdate = true

  b.inTransaction = false
  b.currentTransaction = none(BufferTransaction)
  return ok(())

proc undo*(b: TextBuffer, count: int = 1): Result[BufferPosition, string] =
  ## Undo the last 'count' changes (or all changes in a transaction group)
  ## Returns the suggested cursor position for the first undone change
  ## Returns error if nothing to undo or if the undo operation fails
  if b.readOnly:
    return Result[BufferPosition, string].err "Buffer is read-only"
  if b.undoStack.len == 0:
    return Result[BufferPosition, string].err "Nothing to undo"

  var undoneChanges: seq[BufferChange] = @[]

  # Undo 'count' changes
  for i in 0 ..< count:
    if b.undoStack.len == 0:
      break

    let change = b.undoStack.popLast()

    # For snapshot undo: capture current (post) tree/markers/folds before
    # restoring. modifiedLinesDelta is bidirectional, so the same delta drives
    # the redo entry — no full-array recapture needed.
    var redoEntry =
      if change.kind == ckSnapshot:
        b.makeInverseSnapshotEntry(change)
      else:
        change
    # For non-snapshot: save current modifiedLines and lineMarkers so redo can undo back
    if change.kind != ckSnapshot:
      redoEntry.savedModifiedLines = b.modifiedLines
      redoEntry.savedLineMarkers = b.lineMarkers

    let r = b.undoChange(change)
    if r.isErr:
      # Restore the change to undo stack if undo failed
      b.undoStack.addLast(change)
      # Restore previously undone changes to undo stack
      for j in countdown(undoneChanges.len - 1, 0):
        b.undoStack.addLast(undoneChanges[j])
      return err("Undo failed: " & r.error)

    undoneChanges.add(redoEntry)

    # Restore changeSeq to the pre-mutation value. For transactions this
    # collapses N inc'd changes back to the saved value in one step, fixing
    # the stale isModified-after-multi-change-undo bug.
    b.changeSeq = change.startSeq
    b.advanceContentVersion()

    # Adjust changelist index
    if b.changeListIndex > 0:
      b.changeListIndex.dec

  # Add all undone changes to redo stack in the order they were undone
  # This ensures redo applies them in the correct reverse order
  for change in undoneChanges:
    b.redoStack.addLast(change)

  # Mark highlight as needing update after undo
  if undoneChanges.len > 0:
    # Compute first changed line from undone changes for incremental highlighting
    var minLine = int.high

    proc findMinLine(change: BufferChange) =
      case change.kind
      of ckTransaction:
        for innerChange in change.transactionChanges:
          findMinLine(innerChange)
      else:
        minLine = min(minLine, getChangePosition(change).line)

    for change in undoneChanges:
      findMinLine(change)

    if minLine != int.high:
      b.markLineChanged(minLine)
    else:
      b.highlightNeedsUpdate = true

  # If undo brought us back to saved state, clear all modification markers
  b.clearMarkersIfAtSavedState()

  # Return suggested cursor position for the last undone change (Vim behavior)
  if undoneChanges.len > 0:
    return ok(getChangePosition(undoneChanges[^1]))
  else:
    return ok(BufferPosition(line: 0, column: 0))

proc redoChange(b: TextBuffer, change: BufferChange): Result[(), string] =
  ## Re-apply a single change (internal helper)
  ## Returns error if the operation fails
  try:
    case change.kind
    of ckInsertText:
      # Use insertTextWithNewlines to handle newlines correctly during redo
      b.insertTextWithNewlines(change.insertPos, change.insertText)
    of ckDeleteText:
      let line = b.getLine(change.deletePos.line)
      let bytePos = charToBytePos(line, change.deletePos.column)
      b.backendDeleteAtLineCol(change.deletePos.line, bytePos, change.deletedText.len)
    of ckInsertLine:
      b.backendInsertLine(change.insertLineIdx, change.insertLineText)
    of ckDeleteLine:
      b.backendDeleteLine(change.deleteLineIdx)
    of ckDeleteRange:
      # Re-apply delete range using the same logic as the original deleteRange
      # Handle both single-line and multi-line deletions correctly
      let startPos = change.deleteStartPos
      let endPos = change.deleteEndPos

      if startPos.line == endPos.line:
        discard b.deleteRangeSingleLine(b.getLine(startPos.line), startPos, endPos)
      else:
        discard b.deleteRangeMultiLine(startPos, endPos)
    of ckReplaceLine:
      b.backendReplaceLine(change.replaceLineIdx, change.replaceLineNewText)
    of ckTransaction:
      # Redo all changes in transaction in forward order. On partial failure,
      # roll back (undo) the inner changes we already applied so the buffer is
      # restored to the pre-redo state.
      let n = change.transactionChanges.len
      var i = 0
      while i < n:
        let r = b.redoChange(change.transactionChanges[i])
        if r.isErr:
          for j in countdown(i - 1, 0):
            let rr = b.undoChange(change.transactionChanges[j])
            if rr.isErr:
              logError(
                "buffer",
                "Failed to roll back after partial transaction redo: " & rr.error,
              )
          return r
        inc i
    of ckSnapshot:
      b.storage.pieceTable.restoreSnapshot(change.snapshotData)
      b.lineMarkers = change.snapshotLineMarkers
      # b.modifiedLines currently holds the pre-mutation state; re-apply it.
      applyRedo(b.modifiedLines, change.modifiedLinesDelta)
      b.foldState = change.snapshotFoldState
      b.bookmarks = change.snapshotBookmarks
      b.lastChangedLines = 0

    # Drive the row-remap subscribers forward. Symmetric to undoChange:
    # ckSnapshot/ckTransaction opt out; savedLineMarkers / savedModifiedLines
    # below overwrite the two per-line arrays so `includeSideArrays=false`.
    if change.kind notin {ckSnapshot, ckTransaction}:
      b.emitRowColRemapEvents(change, includeSideArrays = false)

    # For non-snapshot: restore modifiedLines from pre-mutation snapshot
    if change.kind != ckSnapshot and change.savedModifiedLines.len > 0:
      b.modifiedLines = change.savedModifiedLines

    # For non-snapshot: restore lineMarkers from pre-mutation snapshot
    if change.kind != ckSnapshot and change.savedLineMarkers.len > 0:
      b.lineMarkers = change.savedLineMarkers

    # Ensure lineMarkers and modifiedLines stay in sync after redo operations
    b.ensureMarkersSize()
    b.ensureModifiedLinesSize()
    return ok(())
  except CatchableError, Defect:
    # Defect is included so that backend IndexDefect (out-of-range line/col)
    # surfaces as a Result err and triggers the ckTransaction roll-back path,
    # instead of crashing the editor mid-redo.
    let e = getCurrentException()
    logError("buffer", "Redo operation failed: " & e.msg)
    return err("Failed to redo change: " & e.msg)

proc redo*(b: TextBuffer, count: int = 1): Result[BufferPosition, string] =
  ## Redo the last 'count' undone changes
  ## Returns the suggested cursor position for the first redone change
  ## Returns error if nothing to redo or if the redo operation fails
  if b.readOnly:
    return Result[BufferPosition, string].err "Buffer is read-only"
  if b.redoStack.len == 0:
    return Result[BufferPosition, string].err "Nothing to redo"

  var redoneChanges: seq[BufferChange] = @[]

  # Redo 'count' changes
  for i in 0 ..< count:
    if b.redoStack.len == 0:
      break

    let change = b.redoStack.popLast()

    # For snapshot redo: capture current (pre) tree/markers/folds before
    # re-applying. modifiedLinesDelta is bidirectional, so the same delta drives
    # the undo entry — no full-array recapture needed.
    var undoEntry =
      if change.kind == ckSnapshot:
        b.makeInverseSnapshotEntry(change)
      else:
        change
    # For non-snapshot: save current modifiedLines and lineMarkers so undo can restore
    if change.kind != ckSnapshot:
      undoEntry.savedModifiedLines = b.modifiedLines
      undoEntry.savedLineMarkers = b.lineMarkers

    let r = b.redoChange(change)
    if r.isErr:
      # Restore the change to redo stack if redo failed
      b.redoStack.addLast(change)
      # Restore previously redone changes to redo stack
      for j in countdown(redoneChanges.len - 1, 0):
        b.redoStack.addLast(redoneChanges[j])
      return err("Redo failed: " & r.error)

    redoneChanges.add(undoEntry)

    # Restore changeSeq to the post-mutation value (symmetric with undo()).
    b.changeSeq = change.endSeq
    b.advanceContentVersion()

    # Adjust changelist index
    if b.changeListIndex < b.changeList.len - 1:
      b.changeListIndex.inc

  # Symmetric with undo(): push in the order the changes were redone so the
  # last-applied change sits on top of undoStack.
  for change in redoneChanges:
    b.undoStack.addLast(change)

  # Mark highlight as needing update after redo
  if redoneChanges.len > 0:
    # Compute first changed line from redone changes for incremental highlighting
    var minLine = int.high

    proc findMinLine(change: BufferChange) =
      case change.kind
      of ckTransaction:
        for innerChange in change.transactionChanges:
          findMinLine(innerChange)
      else:
        minLine = min(minLine, getChangePosition(change).line)

    for change in redoneChanges:
      findMinLine(change)
    if minLine != int.high:
      b.markLineChanged(minLine)
    else:
      b.highlightNeedsUpdate = true

  # If redo landed back on the saved state, clear all modification markers
  # (symmetric with undo(); the delta restore otherwise leaves stale markers).
  b.clearMarkersIfAtSavedState()

  # Return suggested cursor position for the last redone change (Vim behavior)
  if redoneChanges.len > 0:
    return ok(getChangePosition(redoneChanges[^1]))
  else:
    return ok(BufferPosition(line: 0, column: 0))
