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

## Edit operations: operator / text_object / paste / delete / substitute /
## yank / join / case / increment / decrement handlers and registration.

import std/[options, strutils, unicode]

import pkg/results

import
  ../[
    cursor_util, types, motion, modes, registers, logger, unicode_utils,
    visual_selection, insert_record,
  ]
import ../buffer/[core, edit, fold, undo]

import core, operator_engine, operator_driver, insert_entry
from ../command_handlers/insert_commands import getLineIndent

proc finishPasteCursor(
    ctx: CommandContext,
    isFullLine, cursorAfter: bool,
    firstPastedChar: Option[BufferPosition],
    lastPastedEndLine: int,
) =
  ## p/P: first pasted char (characterwise). gp/gP: after the pasted text.
  if cursorAfter:
    if isFullLine:
      if ctx.buffer.len > 0:
        let afterLine = min(lastPastedEndLine + 1, ctx.buffer.len - 1)
        ctx.cursor.line = afterLine
        ctx.cursor.column = 0
    elif ctx.buffer.len > 0:
      clampCursorToLastChar(ctx.cursor, ctx.buffer.getLine(ctx.cursor.line).charLen)
  elif not isFullLine and firstPastedChar.isSome:
    ctx.cursor = firstPastedChar.get

proc pasteSource(
    ctx: CommandContext
): Result[tuple[text: string, isLine: bool], string] =
  ## What `p`/`P` put: the register this command names, else the unnamed one,
  ## made fit for the buffer. Linewise text ends in a line break.
  let name = ctx.register.get('"')
  if ctx.register.isSome:
    ctx.state.statusMessage = ""
  let reg = ?ctx.state.registers.textToPut(name, ctx.clipboardConfig)
  if reg.isEmpty:
    return err(nothingInRegister(name))
  let text = ctx.buffer.preparePastedText(reg.getContent)
  logDebug(
    "paste",
    "Using register '" & $name & "', length: " & $text.len & ", isLine=" & $reg.isLine,
  )
  ok((text, reg.isLine))

proc handlePasteAfter*(
    ctx: CommandContext, count: int = 1, cursorAfter: bool = false
): Result[(), string] =
  ## Paste after cursor (p). `cursorAfter` is gp. Uses register or clipboard fallback.
  logDebug("paste", "handlePasteAfter called with count=" & $count)
  if ctx.register.isSome and ctx.register.get.isBlackHoleRegisterName:
    # The black hole register reads as nothing, and nothing is put.
    return ok(())
  let actualCount = max(1, count)
  let (pasteText, isFullLine) = ?ctx.pasteSource()

  # Begin transaction if count > 1 to group all pastes into single undo entry
  if actualCount > 1:
    let txnResult = ctx.buffer.beginTransaction("paste " & $actualCount & " times")
    if txnResult.isErr:
      return err(txnResult.error)

  # Saved before the fold snap below: a failed paste must restore the cursor.
  let savedCursor = ctx.cursor

  # A closed fold is a unit: a linewise paste lands after its last line, not
  # after whichever of its lines the cursor sits on.
  if isFullLine:
    let fold = ctx.buffer.foldState.getCollapsedFoldAt(ctx.cursor.line)
    if fold.isSome:
      ctx.cursor.line = fold.get.endLine
  try:
    # Paste count times
    var firstPastedChar: Option[BufferPosition] = none(BufferPosition)
    var lastPastedEndLine = -1
    for i in 1 .. actualCount:
      if isFullLine:
        # Paste on new line below current line (Vim 'p' behavior for linewise yank)
        let currentLine = ctx.buffer.getLine(ctx.cursor.line)
        let pastePos =
          BufferPosition(line: ctx.cursor.line, column: currentLine.charLen)

        # The lines go after the current one's line break.
        let textToInsert = "\n" & pasteText.withoutLastLineBreak
        let insertResult = ctx.buffer.insertText(pastePos, textToInsert)
        if insertResult.isErr:
          # Rollback transaction on error
          if actualCount > 1:
            return rollbackAndPropagate(ctx, insertResult.error, some(savedCursor))
          ctx.cursor = savedCursor
          return err(insertResult.error)

        # Track last pasted line across count repeats.
        let n = textToInsert.count('\n')
        if lastPastedEndLine > ctx.cursor.line:
          lastPastedEndLine += n
        lastPastedEndLine = max(lastPastedEndLine, ctx.cursor.line + n)
        # Move cursor to the first non-whitespace character of pasted line
        ctx.cursor.line = ctx.cursor.line + 1
        ctx.cursor.column = firstNonBlankColumn(ctx.buffer.getLine(ctx.cursor.line))
      else:
        # Paste after cursor position (Vim 'p' behavior for characterwise yank)
        let lineContent = ctx.buffer.getLine(ctx.cursor.line)
        var pastePos = ctx.cursor

        # Move one character right if not at end of line (only for first paste)
        if i == 1 and ctx.cursor.column < lineContent.charLen:
          pastePos.column = ctx.cursor.column + 1

        if firstPastedChar.isNone:
          firstPastedChar = some(pastePos)

        let insertResult = ctx.buffer.insertText(pastePos, pasteText)
        if insertResult.isErr:
          # Rollback transaction on error
          if actualCount > 1:
            return rollbackAndPropagate(ctx, insertResult.error, some(savedCursor))
          ctx.cursor = savedCursor
          return err(insertResult.error)

        # Move the cursor to the end of the inserted text so the next
        # iteration inserts after it. For multi-line paste, land on the final
        # line at its column: '\n' must not count as a column-adding rune.
        let endPos = pasteEndPos(pastePos, pasteText)
        ctx.cursor.line = endPos.line
        ctx.cursor.column = endPos.column

    finishPasteCursor(ctx, isFullLine, cursorAfter, firstPastedChar, lastPastedEndLine)

    # Commit transaction if we started one
    if actualCount > 1:
      let txnResult = ctx.buffer.commitTransaction()
      if txnResult.isErr:
        return err(txnResult.error)
  except Exception as exc:
    if exc of Defect:
      # Defects stay fatal (codebase policy): roll back first, then re-raise.
      discard rollbackPasteOnException(ctx, exc.msg, actualCount, savedCursor)
      raise
    return rollbackPasteOnException(ctx, exc.msg, actualCount, savedCursor)

  # Record this command for repeat (.)
  ctx.recordChange(
    LastEditCommand(
      kind: lecPaste,
      pasteCount: actualCount,
      pasteBefore: false,
      pasteCursorAfter: cursorAfter,
    )
  )

  return Result[(), string].ok ()

proc handlePasteBefore*(
    ctx: CommandContext, count: int = 1, cursorAfter: bool = false
): Result[(), string] =
  ## Paste before cursor (P). `cursorAfter` is gP. Uses register or clipboard fallback.

  logDebug("paste", "handlePasteBefore called with count=" & $count)
  if ctx.register.isSome and ctx.register.get.isBlackHoleRegisterName:
    # The black hole register reads as nothing, and nothing is put.
    return ok(())
  let actualCount = max(1, count)
  let (pasteText, isFullLine) = ?ctx.pasteSource()

  # Begin transaction if count > 1 to group all pastes into single undo entry
  if actualCount > 1:
    let txnResult = ctx.buffer.beginTransaction("paste " & $actualCount & " times")
    if txnResult.isErr:
      return err(txnResult.error)

  # Saved before the fold snap below: a failed paste must restore the cursor.
  let savedCursor = ctx.cursor

  # A closed fold is a unit: a linewise paste lands above its first line, not
  # above whichever of its lines the cursor sits on.
  if isFullLine:
    let fold = ctx.buffer.foldState.getCollapsedFoldAt(ctx.cursor.line)
    if fold.isSome:
      ctx.cursor.line = fold.get.startLine
  try:
    # Paste count times
    var firstPastedChar: Option[BufferPosition] = none(BufferPosition)
    var lastPastedEndLine = -1
    for i in 1 .. actualCount:
      if isFullLine:
        # Paste on new line above current line (Vim 'P' behavior for linewise yank)
        let pastePos = BufferPosition(line: ctx.cursor.line, column: 0)

        # The lines go before the current one, each ending in a line break.
        let textToInsert = pasteText
        let insertResult = ctx.buffer.insertText(pastePos, textToInsert)
        if insertResult.isErr:
          # Rollback transaction on error
          if actualCount > 1:
            return rollbackAndPropagate(ctx, insertResult.error, some(savedCursor))
          ctx.cursor = savedCursor
          return err(insertResult.error)

        # Track last pasted line across count repeats.
        let n = textToInsert.count('\n')
        if lastPastedEndLine >= ctx.cursor.line:
          lastPastedEndLine += n
        lastPastedEndLine = max(lastPastedEndLine, ctx.cursor.line + n - 1)
        # Move cursor to the first non-whitespace character of pasted line
        ctx.cursor.column = firstNonBlankColumn(ctx.buffer.getLine(ctx.cursor.line))
      else:
        # Paste at cursor position (Vim 'P' behavior for characterwise yank)
        let pastePos = ctx.cursor

        if firstPastedChar.isNone:
          firstPastedChar = some(pastePos)

        let insertResult = ctx.buffer.insertText(pastePos, pasteText)
        if insertResult.isErr:
          # Rollback transaction on error
          if actualCount > 1:
            return rollbackAndPropagate(ctx, insertResult.error, some(savedCursor))
          ctx.cursor = savedCursor
          return err(insertResult.error)

        # Move the cursor to the end of the inserted text so the next
        # iteration inserts after it. For multi-line paste, land on the final
        # line at its column: '\n' must not count as a column-adding rune.
        let endPos = pasteEndPos(pastePos, pasteText)
        ctx.cursor.line = endPos.line
        ctx.cursor.column = endPos.column

    finishPasteCursor(ctx, isFullLine, cursorAfter, firstPastedChar, lastPastedEndLine)

    # Commit transaction if we started one
    if actualCount > 1:
      let txnResult = ctx.buffer.commitTransaction()
      if txnResult.isErr:
        return err(txnResult.error)
  except Exception as exc:
    if exc of Defect:
      # Defects stay fatal (codebase policy): roll back first, then re-raise.
      discard rollbackPasteOnException(ctx, exc.msg, actualCount, savedCursor)
      raise
    return rollbackPasteOnException(ctx, exc.msg, actualCount, savedCursor)

  # Record this command for repeat (.)
  ctx.recordChange(
    LastEditCommand(
      kind: lecPaste,
      pasteCount: actualCount,
      pasteBefore: true,
      pasteCursorAfter: cursorAfter,
    )
  )

  return Result[(), string].ok ()

proc isOnCollapsedFold(ctx: CommandContext): bool =
  ctx.buffer.foldState.getCollapsedFoldAt(ctx.cursor.line).isSome

proc editWholeFoldAtCursor(
    ctx: CommandContext, operatorType: OperatorType
): Result[(), string] =
  ## x and s are dl and cl, and an operator takes a closed fold as a whole, so
  ## route them through the operator engine and let its range snapping widen.
  executeOperatorOnRange(
    ctx, operatorType, OperatorRange(start: ctx.cursor, endPos: ctx.cursor), 1
  )

proc handleDeleteChar*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete character(s) at cursor position (x command)
  ## count: number of characters to delete (default: 1)
  ## With autoDeleteParen enabled, deleting an opening paren also deletes matching closing paren

  logDebug("delete", "handleDeleteChar called with count=" & $count)
  if ctx.isOnCollapsedFold:
    let foldResult = ctx.editWholeFoldAtCursor(OpDelete)
    if foldResult.isOk:
      # `.` still repeats an `x`, not whatever edit came before it.
      ctx.recordChange(
        LastEditCommand(kind: lecDeleteChar, deleteCount: 1, deleteForward: true)
      )
    return foldResult
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    return err("Nothing to delete")

  # Auto-delete adjacent paren pairs only (e.g., [] () {} "" '')
  if ctx.state.autoDeleteParen and actualCount == 1:
    let cursorCol = ctx.cursor.column

    # Guard only the probe: keep withTransaction's untrustworthy-state raise visible.
    var isPair = false
    try:
      isPair = isAdjacentPair(lineContent, cursorCol)
    except CatchableError:
      discard

    if isPair:
      let txr =
        try:
          withTransaction(ctx.buffer, "delete paren pair"):
            # Delete opening char, then closing char (now at same position)
            for i in 0 ..< 2:
              let delResult = ctx.buffer.deleteRange(
                BufferPosition(line: ctx.cursor.line, column: cursorCol),
                BufferPosition(line: ctx.cursor.line, column: cursorCol),
              )
              if delResult.isErr:
                # Raise instead of returning so a failed rollback keeps this
                # original error in the TransactionRollbackError message.
                raise newException(ValueError, delResult.error)
        except ValueError as exc:
          if exc of TransactionRollbackError:
            return err(exc.msg & " (buffer state may be inconsistent)")
          return err(exc.msg)
      if txr.isErr:
        return err(txr.error)

      # Both chars were deleted, so both go in the register
      storeDeletedText(ctx, lineContent.charSubStr(cursorCol, 2), false)

      let updatedLineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
      if updatedLineLen > 0 and ctx.cursor.column >= updatedLineLen:
        ctx.cursor.column = updatedLineLen - 1

      return Result[(), string].ok ()

  # Normal delete logic
  # Calculate how many characters we can actually delete
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  let deletedText = lineContent.charSubStr(ctx.cursor.column, charsToDelete)

  if charsToDelete > 1:
    let txr = withTransaction(ctx.buffer, "delete " & $charsToDelete & " chars"):
      for i in 0 ..< charsToDelete:
        let endPos = ctx.cursor
        let delResult = ctx.buffer.deleteRange(ctx.cursor, endPos)
        if delResult.isErr:
          return err(delResult.error)
    if txr.isErr:
      return err(txr.error)
  else:
    let endPos = ctx.cursor
    let delResult = ctx.buffer.deleteRange(ctx.cursor, endPos)
    if delResult.isErr:
      return err(delResult.error)

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, deletedText, false)

  ctx.recordChange(
    LastEditCommand(
      kind: lecDeleteChar, deleteCount: charsToDelete, deleteForward: true
    )
  )

  # Adjust cursor if it's now past the end of the line (Vim behavior)
  let newLineContent = ctx.buffer.getLine(ctx.cursor.line)
  let newLineLen = newLineContent.charLen
  if newLineLen > 0 and ctx.cursor.column >= newLineLen:
    ctx.cursor.column = newLineLen - 1

  return Result[(), string].ok ()

proc handleDeleteCharBefore*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete character(s) before cursor position (X command)
  ## count: number of characters to delete (default: 1)
  ## With autoDeleteParen enabled, deleting a closing paren also deletes matching opening paren

  logDebug("delete", "handleDeleteCharBefore called with count=" & $count)
  let actualCount = max(1, count)

  # Check if we're at the beginning of the line
  if ctx.cursor.column == 0:
    return err("Nothing to delete")

  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Auto-delete adjacent paren pairs only (e.g., [] () {} "" '')
  if ctx.state.autoDeleteParen and actualCount == 1:
    let cursorCol = ctx.cursor.column

    # Guard only the probe: keep withTransaction's untrustworthy-state raise visible.
    var isPair = false
    try:
      # X deletes char before cursor; check if char at cursorCol-1 and cursorCol form a pair
      isPair = isAdjacentPair(lineContent, cursorCol - 1)
    except CatchableError:
      discard

    if isPair:
      let txr =
        try:
          withTransaction(ctx.buffer, "delete paren pair"):
            # Delete opening char, then closing char (now at same position)
            for i in 0 ..< 2:
              let delResult = ctx.buffer.deleteRange(
                BufferPosition(line: ctx.cursor.line, column: cursorCol - 1),
                BufferPosition(line: ctx.cursor.line, column: cursorCol - 1),
              )
              if delResult.isErr:
                # Raise instead of returning so a failed rollback keeps this
                # original error in the TransactionRollbackError message.
                raise newException(ValueError, delResult.error)
        except ValueError as exc:
          if exc of TransactionRollbackError:
            return err(exc.msg & " (buffer state may be inconsistent)")
          return err(exc.msg)
      if txr.isErr:
        return err(txr.error)

      # Both chars were deleted, so both go in the register
      storeDeletedText(ctx, lineContent.charSubStr(cursorCol - 1, 2), false)
      ctx.cursor.column = cursorCol - 1

      return Result[(), string].ok ()

  # Normal delete logic
  # Calculate how many characters we can actually delete
  let charsAvailable = ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Calculate the start position for deletion
  let startColumn = ctx.cursor.column - charsToDelete

  let deletedText = lineContent.charSubStr(startColumn, charsToDelete)

  if charsToDelete > 1:
    let txr = withTransaction(ctx.buffer, "delete " & $charsToDelete & " chars"):
      for i in 0 ..< charsToDelete:
        let startPos = BufferPosition(line: ctx.cursor.line, column: startColumn)
        let endPos = startPos
        let delResult = ctx.buffer.deleteRange(startPos, endPos)
        if delResult.isErr:
          return err(delResult.error)
    if txr.isErr:
      return err(txr.error)
  else:
    let startPos = BufferPosition(line: ctx.cursor.line, column: startColumn)
    let delResult = ctx.buffer.deleteRange(startPos, startPos)
    if delResult.isErr:
      return err(delResult.error)

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, deletedText, false)

  # Move cursor to the position where deletion started
  ctx.cursor.column = startColumn

  # Record this command for repeat (.)
  ctx.recordChange(
    LastEditCommand(
      kind: lecDeleteChar, deleteCount: charsToDelete, deleteForward: false
    )
  )

  return Result[(), string].ok ()

proc handleSubstituteChar*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Substitute character(s) at cursor position (s command)
  ## Deletes character(s) and enters Insert mode
  ## count: number of characters to substitute (default: 1)

  logDebug("substitute", "handleSubstituteChar called with count=" & $count)
  if ctx.isOnCollapsedFold:
    let foldResult = ctx.editWholeFoldAtCursor(OpChange)
    if foldResult.isErr:
      return foldResult
    # Recorded as `s`, so a repeat on a closed fold widens again.
    return ctx.beginInsert(InsertEntry(kind: ieSubstitute), count)
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    # At end of line, just enter insert mode
    return ctx.beginInsert(InsertEntry(kind: ieSubstitute), count)

  # Calculate how many characters we can actually delete
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  let deletedText = lineContent.charSubStr(ctx.cursor.column, charsToDelete)

  # Begin transaction for delete + insert mode (all in one undo unit)
  let txnResult =
    ctx.buffer.beginTransaction("substitute " & $charsToDelete & " char(s)")
  if txnResult.isErr:
    return err(txnResult.error)

  # Delete the characters
  for i in 0 ..< charsToDelete:
    let endPos = ctx.cursor
    let delResult = ctx.buffer.deleteRange(ctx.cursor, endPos)
    if delResult.isErr:
      return rollbackAndPropagate(ctx, delResult.error)

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, deletedText, false)

  # The transaction stays open for what is typed in Insert mode.
  ctx.beginInsert(InsertEntry(kind: ieSubstitute), count)

proc cursorLineRange(
    ctx: CommandContext, count: int
): tuple[startLine, endLine, lineCount: int] =
  ## Inclusive line range for a count-prefixed linewise command at the cursor,
  ## widened so every closed fold it touches is covered whole, as dd/yy/S do.
  let first = ctx.cursor.line
  if first < 0 or first >= ctx.buffer.len:
    # A stale cursor names no line. `snapRangeToFolds` normalizes a reversed
    # range, so it would turn the empty request into a valid-looking one.
    return (first, first - 1, 0)
  let
    last = min(first + max(1, count) - 1, ctx.buffer.len - 1)
    (lo, hi) = ctx.buffer.foldState.snapRangeToFolds(first, last)
  (lo, hi, hi - lo + 1)

proc handleSubstituteLine*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Substitute line(s) (S command or cc)
  ## Deletes line content and enters Insert mode
  ## count: number of lines to substitute (default: 1)

  logDebug("substitute", "handleSubstituteLine called with count=" & $count)
  let (startLine, endLine, _) = ctx.cursorLineRange(count)

  let text = ctx.buffer.linewiseText(startLine, endLine)

  # Get indent; skipped for raw buffers.
  var indent =
    if ctx.buffer.allowsTextTransforms:
      getLineIndent(ctx.buffer.getLine(startLine))
    else:
      ""

  # Begin transaction for all substitute operations (delete + insert mode input)
  let transactionResult = ctx.buffer.beginTransaction("Substitute line")
  if transactionResult.isErr:
    return err("Failed to begin transaction: " & transactionResult.error)

  # Delete all but first line
  for i in 0 ..< (endLine - startLine):
    if startLine + 1 < ctx.buffer.len:
      let deleteResult = ctx.buffer.deleteLine(startLine + 1)
      if deleteResult.isErr:
        return rollbackAndPropagate(ctx, "Failed to delete line: " & deleteResult.error)

  # Clear the first line but preserve indent
  if startLine < ctx.buffer.len:
    let line = ctx.buffer.getLine(startLine)
    # Delete all characters in the line
    for i in 0 ..< line.charLen:
      let deleteResult = ctx.buffer.deleteRange(
        BufferPosition(line: startLine, column: 0),
        BufferPosition(line: startLine, column: 0),
      )
      if deleteResult.isErr:
        return rollbackAndPropagate(ctx, "Failed to clear line: " & deleteResult.error)

    # Insert indent if auto-indent is enabled
    if ctx.state.autoIndent and indent.len > 0:
      let insertResult =
        ctx.buffer.insertText(BufferPosition(line: startLine, column: 0), indent)
      if insertResult.isErr:
        return
          rollbackAndPropagate(ctx, "Failed to insert indent: " & insertResult.error)
    else:
      indent = ""

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, text, true)

  # Move cursor to beginning of line (after indent)
  ctx.cursor.line = startLine
  ctx.cursor.column = indent.len

  # The transaction stays open for what is typed in Insert mode. `.` repeats the
  # typed count, not the count widened for a closed fold.
  ctx.beginInsert(InsertEntry(kind: ieSubstituteLine), count)

proc handleToggleCase*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Toggle case of character(s) at cursor position (~ command)
  ## Changes uppercase to lowercase and vice versa, then moves cursor right
  ## count: number of characters to toggle (default: 1)

  logDebug("toggle", "handleToggleCase called with count=" & $count)

  # Refused for raw buffers.
  if not ctx.buffer.allowsTextTransforms:
    return err(rawBytesRejection("toggle case"))

  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    return err("Nothing to toggle")

  # Calculate how many characters we can actually toggle
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToToggle = min(actualCount, charsAvailable)

  # Sliced byte-exactly, so a byte that does not decode keeps the bytes it had.
  let
    target = lineContent.charSubStr(ctx.cursor.column, charsToToggle)
    toggled = target.toggleAsciiCase

  if toggled != target:
    let
      startPos = BufferPosition(line: ctx.cursor.line, column: ctx.cursor.column)
      endPos = BufferPosition(
        line: ctx.cursor.line, column: ctx.cursor.column + charsToToggle - 1
      )
    let txr = withTransaction(ctx.buffer, "toggle " & $charsToToggle & " char(s)"):
      let res =
        ctx.buffer.transformRange(startPos, endPos, "toggle case", toggleAsciiCase)
      if res.isErr:
        return err(res.error)
    if txr.isErr:
      return err(txr.error)

  # Move cursor to the right by the number of characters toggled
  ctx.cursor.column += charsToToggle

  # Keep cursor within line bounds (in Normal mode, cursor can't be on newline)
  let finalLineContent = ctx.buffer.getLine(ctx.cursor.line)
  if ctx.cursor.column >= finalLineContent.charLen:
    ctx.cursor.column = max(0, finalLineContent.charLen - 1)

  # Record this command for repeat (.)
  ctx.recordChange(LastEditCommand(kind: lecToggleCase, toggleCaseCount: charsToToggle))

  return Result[(), string].ok ()

proc handleDeleteLine*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete current line(s) and store in yank register (dd command)
  ## count: number of lines to delete (default: 1)

  logDebug("delete", "handleDeleteLine called with count=" & $count)
  let (startLine, endLine, lineCount) = ctx.cursorLineRange(count)

  let deletedText = ctx.buffer.linewiseText(startLine, endLine)

  var clearedWholeBuffer = false
  let txr = withTransaction(ctx.buffer, "Delete " & $lineCount & " line(s)"):
    var brokeEarly = false
    for i in 1 .. lineCount:
      if startLine < ctx.buffer.len:
        if ctx.buffer.len == 1:
          brokeEarly = true
          break
        let delResult = ctx.buffer.deleteLine(startLine)
        if delResult.isErr:
          return err(delResult.error)

    if brokeEarly:
      let lastLine = ctx.buffer.getLine(0)
      if lastLine.len > 0:
        let clearResult = ctx.buffer.deleteRange(
          BufferPosition(line: 0, column: 0),
          BufferPosition(line: 0, column: lastLine.charLen - 1),
        )
        if clearResult.isErr:
          return err(clearResult.error)
      clearedWholeBuffer = true
  if txr.isErr:
    return err("Transaction failed: " & txr.error)

  # Clearing the last line is not a deletion, so the fold shift never sees it go
  # and every fold is now empty. Dropped after the commit: fold state is outside
  # the transaction.
  if clearedWholeBuffer:
    ctx.buffer.foldState.deleteAllFolds()

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  storeDeletedText(ctx, deletedText, true)

  # A closed fold can put `startLine` above the cursor, so the cursor follows
  # the range rather than its own old line.
  ctx.cursor.line = startLine
  if ctx.cursor.line >= ctx.buffer.len:
    ctx.cursor.line = max(0, ctx.buffer.len - 1)
  # Preserve column position, clamped to end of new current line
  let newLine = ctx.buffer.getLine(ctx.cursor.line)
  if newLine.charLen > 0:
    ctx.cursor.column = min(ctx.cursor.column, newLine.charLen - 1)
  else:
    ctx.cursor.column = 0

  # Record this command for repeat (.)
  ctx.recordChange(LastEditCommand(kind: lecDeleteLine, deleteLineCount: max(1, count)))

  # Delete screen notification (controlled by config)
  if ctx.notificationConfig.screenNotifications and
      ctx.notificationConfig.deleteScreenNotify:
    ctx.notify("Deleted " & $lineCount & " line(s)")

  # Delete log notification (controlled by config)
  if ctx.notificationConfig.logNotifications and ctx.notificationConfig.deleteLogNotify:
    logInfo("delete", "Deleted " & $lineCount & " line(s)")

  return Result[(), string].ok ()

proc handleYankLine*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Yank (copy) the current line(s) to internal register and optionally to system clipboard
  ## count: number of lines to yank (default: 1)

  logDebug("yank", "handleYankLine called with count=" & $count)
  # The cursor stays, but Vim's operators drop curswant.
  ctx.state.preferredColumn = -1
  let (startLine, endLine, lineCount) = ctx.cursorLineRange(count)
  logDebug("yank", "lineCount=" & $lineCount)

  let yankText = ctx.buffer.linewiseText(startLine, endLine)

  # Debug: log the yanked text
  logDebug("yank", "Yanking " & $lineCount & " line(s), total length: " & $yankText.len)
  logDebug("yank", "Yanked text: '" & yankText & "'")

  storeYankedText(ctx, yankText, true)

  let storedReg = ctx.state.registers.noNamed
  logDebug(
    "yank",
    "Stored in register: '" & storedReg.getContent() & "', isLine=" & $storedReg.isLine,
  )

  # Yank screen notification (controlled by config)
  if ctx.notificationConfig.screenNotifications and
      ctx.notificationConfig.yankScreenNotify:
    ctx.notify("Yanked " & $lineCount & " line(s)")

  # Yank log notification (controlled by config)
  if ctx.notificationConfig.logNotifications and ctx.notificationConfig.yankLogNotify:
    logInfo("yank", "Yanked " & $lineCount & " line(s)")

  return Result[(), string].ok ()

proc handleJoinLines*(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Join lines starting from current line (J command)
  ## count: number of additional lines to join (default: 1, meaning join 2 lines total)
  ## Example: count=1 joins current and next line, count=2 joins 3 lines, etc.

  logDebug("join", "handleJoinLines called with count=" & $count)
  let actualCount = max(1, count)

  # J is not an operator: on a closed fold it joins the fold's first two lines
  # and leaves the fold closed, so the range is deliberately not widened.
  let joinResult = ctx.buffer.joinLines(ctx.cursor.line, actualCount)
  if joinResult.isErr:
    return err(joinResult.error)

  # Record this command for repeat (.)
  ctx.recordChange(LastEditCommand(kind: lecJoinLines, joinLinesCount: actualCount))

  let totalLines = actualCount + 1
  ctx.state.statusMessage = "Joined " & $totalLines & " line(s)"
  return Result[(), string].ok ()

proc handleShowCharInfo*(ctx: CommandContext): Result[(), string] =
  ## Show ASCII/Unicode value of character under cursor (ga command)
  ## Displays character info in status message

  logDebug("charinfo", "handleShowCharInfo called")
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if cursor is at valid position
  if ctx.cursor.column >= lineContent.charLen:
    ctx.state.statusMessage = "No character under cursor"
    return Result[(), string].ok ()

  # Get the character at cursor position
  let runes = lineContent.toCharRunes()
  if ctx.cursor.column < runes.len:
    let ch = runes[ctx.cursor.column]
    # An undecodable byte has no code point: show the byte itself, the way
    # vim does, rather than a replacement character's value.
    let
      codepoint = if ch.isInvalidByteRune: ch.invalidByteValue.int32 else: ch.int32
      shown =
        if ch.isInvalidByteRune:
          invalidByteText(ch)
        else:
          "<" & $ch & ">"

    # Format the message like Vim: <c>  123,  Hex 7b,  Oct 173
    var msg = shown
    msg &= "  " & $codepoint & ","
    msg &= "  Hex " & toHex(codepoint, 2) & ","
    msg &= "  Oct " & toOct(codepoint, 3)

    ctx.state.statusMessage = msg
  else:
    ctx.state.statusMessage = "No character under cursor"

  return Result[(), string].ok ()

proc handleOperatorYank*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Yank operator - waits for motion (y2w, y$, etc.) or yy for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (yy for yank line)
  let lines = ctx.takeDoubledOperator(OpYank, count)
  if lines.isSome:
    # Execute line yank. The cursor stays, but Vim's operators drop curswant.
    ctx.state.preferredColumn = -1
    let startLine = ctx.cursor.line
    let endLine = min(startLine + lines.get - 1, ctx.buffer.len - 1)

    let text = ctx.buffer.linewiseText(startLine, endLine)

    storeYankedText(ctx, text, true)

    let lineCount = endLine - startLine + 1
    # Yank screen notification (controlled by config)
    if ctx.notificationConfig.screenNotifications and
        ctx.notificationConfig.yankScreenNotify:
      ctx.notify("Yanked " & $lineCount & " line(s)")
    # Yank log notification (controlled by config)
    if ctx.notificationConfig.logNotifications and ctx.notificationConfig.yankLogNotify:
      logInfo("yank", "Yanked " & $lineCount & " line(s)")
    return ok(())
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpYank, count, countGiven, "y")
    return ok(())

proc handleOperatorDelete*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Delete operator - waits for motion (d2w, d$, etc.) or dd for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (dd for delete line)
  let lines = ctx.takeDoubledOperator(OpDelete, count)
  if lines.isSome:
    # Execute line deletion
    let startLine = ctx.cursor.line
    let endLine = min(startLine + lines.get - 1, ctx.buffer.len - 1)
    let lineCount = endLine - startLine + 1

    let text = ctx.buffer.linewiseText(startLine, endLine)

    let txr = withTransaction(ctx.buffer, "Delete " & $lineCount & " line(s)"):
      var brokeEarly = false
      for i in 0 ..< lineCount:
        if startLine < ctx.buffer.len:
          if ctx.buffer.len == 1:
            brokeEarly = true
            break
          let deleteResult = ctx.buffer.deleteLine(startLine)
          if deleteResult.isErr:
            return err("Failed to delete line: " & deleteResult.error)

      if brokeEarly:
        let lastLine = ctx.buffer.getLine(0)
        if lastLine.len > 0:
          let clearResult = ctx.buffer.deleteRange(
            BufferPosition(line: 0, column: 0),
            BufferPosition(line: 0, column: lastLine.charLen - 1),
          )
          if clearResult.isErr:
            return err("Failed to clear last line: " & clearResult.error)
    if txr.isErr:
      return err("Transaction failed: " & txr.error)

    # Store in register only after the buffer change succeeded (registers are not
    # covered by the buffer transaction, so a rollback would not undo them)
    storeDeletedText(ctx, text, true)

    # Move cursor to start line, preserve column position
    ctx.cursor.line = min(startLine, ctx.buffer.len - 1)
    # Preserve column position, clamped to end of new current line
    let newLine = ctx.buffer.getLine(ctx.cursor.line)
    if newLine.charLen > 0:
      ctx.cursor.column = min(ctx.cursor.column, newLine.charLen - 1)
    else:
      ctx.cursor.column = 0

    # Record this command for repeat (.)
    ctx.recordChange(LastEditCommand(kind: lecDeleteLine, deleteLineCount: lineCount))

    # Delete screen notification (controlled by config)
    if ctx.notificationConfig.screenNotifications and
        ctx.notificationConfig.deleteScreenNotify:
      ctx.notify("Deleted " & $lineCount & " line(s)")
    # Delete log notification (controlled by config)
    if ctx.notificationConfig.logNotifications and ctx.notificationConfig.deleteLogNotify:
      logInfo("delete", "Deleted " & $lineCount & " line(s)")
    return ok(())
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpDelete, count, countGiven, "d")
    return ok(())

proc handleOperatorChange*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Change operator - waits for motion (c2w, c$, etc.) or cc for line
  ## count: number of times to apply the operator (default: 1)

  # cc changes lines as S does
  let lines = ctx.takeDoubledOperator(OpChange, count)
  if lines.isSome:
    return handleSubstituteLine(ctx, lines.get)
  setPendingOperator(ctx, OpChange, count, countGiven, "c")
  ok(())

proc handleOperatorOnLines*(
    ctx: CommandContext, operatorType: OperatorType, count: int = 1
): Result[(), string] =
  ## Apply a doubled operator (>>, <<, guu, gUU) to whole lines and record it
  ## for repeat (.)
  ## operatorType: OpIndent, OpOutdent, OpLowerCase or OpUpperCase
  ## count: number of lines (default: 1)

  let
    lineCount = max(1, count)
    startLine = ctx.cursor.line
    endLine = min(startLine + lineCount - 1, ctx.buffer.len - 1)
    range = OperatorRange(
      start: BufferPosition(line: startLine, column: 0),
      endPos: BufferPosition(line: endLine, column: 0),
      isLinewise: true,
    )

  let opResult = executeOperatorOnRange(ctx, operatorType, range, 1)
  if opResult.isErr:
    return opResult

  # Record this command for repeat (.)
  ctx.recordChange(
    LastEditCommand(
      kind: lecOperatorLines, linesOperator: operatorType, operatorLineCount: lineCount
    )
  )

  return ok(())

proc handleOperatorIndent*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Indent operator - waits for motion (>2w, >$, etc.) or >> for line
  ## count: number of times to apply the operator (default: 1)

  # Counts on both halves multiply (2>3> is six lines)
  let lines = ctx.takeDoubledOperator(OpIndent, count)
  if lines.isSome:
    return handleOperatorOnLines(ctx, OpIndent, lines.get)
  setPendingOperator(ctx, OpIndent, count, countGiven, ">")
  ok(())

proc handleOperatorOutdent*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Outdent operator - waits for motion (<2w, <$, etc.) or << for line
  ## count: number of times to apply the operator (default: 1)

  # Counts on both halves multiply (2<3< is six lines)
  let lines = ctx.takeDoubledOperator(OpOutdent, count)
  if lines.isSome:
    return handleOperatorOnLines(ctx, OpOutdent, lines.get)
  setPendingOperator(ctx, OpOutdent, count, countGiven, "<")
  ok(())

proc handleOperatorLowerCase*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Lowercase operator - waits for motion (guw, gu$, etc.) or guu/gugu for line
  ## count: number of times to apply the operator (default: 1)

  # Counts on both halves multiply (2gu3u is six lines)
  let lines = ctx.takeDoubledOperator(OpLowerCase, count)
  if lines.isSome:
    return handleOperatorOnLines(ctx, OpLowerCase, lines.get)
  setPendingOperator(ctx, OpLowerCase, count, countGiven, "gu")
  ok(())

proc handleOperatorUpperCase*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Uppercase operator - waits for motion (gUw, gU$, etc.) or gUU/gUgU for line
  ## count: number of times to apply the operator (default: 1)

  # Counts on both halves multiply (2gU3U is six lines)
  let lines = ctx.takeDoubledOperator(OpUpperCase, count)
  if lines.isSome:
    return handleOperatorOnLines(ctx, OpUpperCase, lines.get)
  setPendingOperator(ctx, OpUpperCase, count, countGiven, "gU")
  ok(())

proc handleChangeToEnd*(
    registry: CommandRegistry, ctx: CommandContext, count = 1
): Result[(), string] =
  ## C: change to the end of the line, or over the count's lines (`2C`), as
  ## `c$` does.
  if count > 1:
    ctx.startOperator(OpChange)
    return registry.finishOperator(
      ctx, Operand(kind: odMotion, motion: Motion.End, count: count, countGiven: true)
    )
  let
    startPos = ctx.cursor
    lineLen = ctx.buffer.getLine(startPos.line).charLen
  # Empty line or cursor at/past end: just enter insert mode without deleting
  if lineLen == 0 or startPos.column >= lineLen:
    return ctx.beginInsert(InsertEntry(kind: ieChangeToEnd), 1)
  let range = OperatorRange(
    start: startPos,
    endPos: BufferPosition(line: startPos.line, column: lineLen - 1),
    isLinewise: false,
  )
  let changed = executeOperatorOnRange(ctx, OpChange, range, 1)
  if changed.isOk:
    ctx.state.startInsertRecord(InsertEntry(kind: ieChangeToEnd), 1, ctx.register)
  changed

## Text object command handlers

proc handleTextObjectInner*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Handle inner text object (iw, i", i(, etc.) or enter Insert mode.
  ## `count` is the [count] prefix; plain `i` types the text that many times.

  # Check if we have a pending operator
  if ctx.state.pendingInput.pendingOperator.isSome:
    # We have a pending operator - set text object modifier
    ctx.state.pendingInput.pendingTextObject = some(
      PendingTextObject(
        modifier: tomInner, count: max(1, count), countGiven: countGiven
      )
    )
    ctx.state.statusMessage =
      $ctx.state.pendingInput.pendingOperator.get.operatorType & "i"
    return ok(())
  elif isVisualAllMode(ctx.state.mode):
    # In Visual mode - set text object modifier for visual selection
    ctx.state.pendingInput.pendingTextObject = some(
      PendingTextObject(
        modifier: tomInner, count: max(1, count), countGiven: countGiven
      )
    )
    return ok(())
  else:
    # No pending operator - enter Insert mode
    return ctx.handleInsertAt(ieInsert, count)

proc handleTextObjectAround*(
    ctx: CommandContext, count: int = 1, countGiven = false
): Result[(), string] =
  ## Handle around text object (aw, a", a(, etc.) or enter Append mode.
  ## `count` is the [count] prefix; plain `a` types the text that many times.

  # Check if we have a pending operator
  if ctx.state.pendingInput.pendingOperator.isSome:
    # We have a pending operator - set text object modifier
    ctx.state.pendingInput.pendingTextObject = some(
      PendingTextObject(
        modifier: tomAround, count: max(1, count), countGiven: countGiven
      )
    )
    ctx.state.statusMessage =
      $ctx.state.pendingInput.pendingOperator.get.operatorType & "a"
    return ok(())
  elif isVisualAllMode(ctx.state.mode):
    # In Visual mode - set text object modifier for visual selection
    ctx.state.pendingInput.pendingTextObject = some(
      PendingTextObject(
        modifier: tomAround, count: max(1, count), countGiven: countGiven
      )
    )
    return ok(())
  else:
    # No pending operator - append after the cursor
    return ctx.handleInsertAt(ieAppend, count)

proc findNumberAtOrAfterColumn*(
    line: string, startCol: int
): tuple[found: bool, startPos: int, endPos: int, value: int] =
  ## Find a number at or after the given column in the line
  ## Returns (found, startPos, endPos, value) where positions are byte indices
  var col = startCol
  let lineLen = line.len

  # Skip to start column
  if col >= lineLen:
    return (false, 0, 0, 0)

  # Skip non-digit characters (but stop at digit or minus sign before digit)
  while col < lineLen:
    if line[col] >= '0' and line[col] <= '9':
      break
    elif line[col] == '-' and col + 1 < lineLen and line[col + 1] >= '0' and
        line[col + 1] <= '9':
      break
    col += 1

  if col >= lineLen:
    return (false, 0, 0, 0)

  # Found start of number
  let startPos = col
  var numStr = ""

  # Handle optional minus sign
  if line[col] == '-':
    numStr.add('-')
    col += 1

  # Collect digits
  while col < lineLen and line[col] >= '0' and line[col] <= '9':
    numStr.add(line[col])
    col += 1

  # Parse the number
  try:
    let value = parseInt(numStr)
    return (true, startPos, col - 1, value)
  except ValueError:
    return (false, 0, 0, 0)

proc handleIncrementNumber*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Increment the number at or after cursor (Ctrl-A command)
  if ctx.cursor.line >= ctx.buffer.len:
    return err("Cursor out of bounds")

  let line = ctx.buffer.getLine(ctx.cursor.line)
  let byteCol = charToBytePos(line, ctx.cursor.column)

  # Find number at or after cursor position (byte space)
  let (found, startPos, endPos, value) = findNumberAtOrAfterColumn(line, byteCol)

  if not found:
    return err("No number found")

  # Increment the number (saturate at high(int) to avoid overflow)
  let newValue =
    if value == high(int):
      value
    else:
      value + 1
  let newNumStr = $newValue

  # Replace the number in the line
  let newLine =
    line[0 ..< startPos] & newNumStr &
    (if endPos + 1 < line.len: line[endPos + 1 ..^ 1] else: "")

  let replaceResult = ctx.buffer.replaceLine(ctx.cursor.line, newLine)
  if replaceResult.isErr:
    return err(replaceResult.error)

  # Move cursor to start of the number (convert byte pos to char pos)
  ctx.cursor.column = byteToCharPos(newLine, startPos)

  return ok(())

proc handleDecrementNumber*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Decrement the number at or after cursor (Ctrl-X command)
  if ctx.cursor.line >= ctx.buffer.len:
    return err("Cursor out of bounds")

  let line = ctx.buffer.getLine(ctx.cursor.line)
  let byteCol = charToBytePos(line, ctx.cursor.column)

  # Find number at or after cursor position (byte space)
  let (found, startPos, endPos, value) = findNumberAtOrAfterColumn(line, byteCol)

  if not found:
    return err("No number found")

  # Decrement the number (saturate at low(int) to avoid overflow)
  let newValue =
    if value == low(int):
      value
    else:
      value - 1
  let newNumStr = $newValue

  # Replace the number in the line
  let newLine =
    line[0 ..< startPos] & newNumStr &
    (if endPos + 1 < line.len: line[endPos + 1 ..^ 1] else: "")

  let replaceResult = ctx.buffer.replaceLine(ctx.cursor.line, newLine)
  if replaceResult.isErr:
    return err(replaceResult.error)

  # Move cursor to start of the number (convert byte pos to char pos)
  ctx.cursor.column = byteToCharPos(newLine, startPos)

  return ok(())

proc registerEditCommands*(registry: CommandRegistry) =
  ## Register all edit-category commands (delete/substitute/paste/yank/operator/text_object/increment).
  # Note: delete.word is now handled by operator+motion system (d+w)
  # The operator.delete handler sets pendingOperator, then Motion.WordForward
  # is executed, and executeOperatorOnRange is called automatically

  registry.register(
    custom("delete.line"),
    "Delete Line",
    "Delete current line(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("delete.char"),
    "Delete Character",
    "Delete character(s) at cursor (x command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteChar(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("delete.char.before"),
    "Delete Character Before",
    "Delete character(s) before cursor (X command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteCharBefore(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("substitute.char"),
    "Substitute Character",
    "Substitute character(s) at cursor (s command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleSubstituteChar(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("substitute.line"),
    "Substitute Line",
    "Substitute line(s) (S command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleSubstituteLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("toggle.case"),
    "Toggle Case",
    "Toggle case of character(s) at cursor (~ command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleToggleCase(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("yank.line"),
    "Yank Line",
    "Yank (copy) current line(s) to clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleYankLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("paste.after"),
    "Paste After",
    "Paste clipboard content after cursor (p command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handlePasteAfter(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("paste.before"),
    "Paste Before",
    "Paste clipboard content before cursor (P command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handlePasteBefore(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("paste.after.end"),
    "Paste After End",
    "Paste clipboard content after cursor and leave cursor after pasted text (gp)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handlePasteAfter(ctx, count, cursorAfter = true),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("paste.before.end"),
    "Paste Before End",
    "Paste clipboard content before cursor and leave cursor after pasted text (gP)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handlePasteBefore(ctx, count, cursorAfter = true),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("indent.line"),
    "Indent Line",
    "Indent current line (>> command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Count is a line count, like vim's [count]>>
      handleOperatorOnLines(ctx, OpIndent, parseCount(args, default = 1)),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("dedent.line"),
    "Dedent Line",
    "Dedent current line (<< command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorOnLines(ctx, OpOutdent, parseCount(args, default = 1)),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("autoindent.line"),
    "Auto Indent Line",
    "Auto indent current line to match previous line (== command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let currentLine = ctx.cursor.line

      # Can't auto indent first line or empty line
      if currentLine == 0:
        return Result[(), string].ok ()

      let lineContent = ctx.buffer.getLine(currentLine)
      if lineContent.len == 0:
        return Result[(), string].ok ()

      # Get previous line indent (leading spaces and tabs)
      let prevLine = ctx.buffer.getLine(currentLine - 1)
      var prevIndent = 0
      for i in 0 ..< prevLine.len:
        if prevLine[i] == ' ' or prevLine[i] == '\t':
          inc prevIndent
        else:
          break

      # Count current line's leading whitespace
      var currentIndent = 0
      for i in 0 ..< lineContent.len:
        if lineContent[i] == ' ' or lineContent[i] == '\t':
          inc currentIndent
        else:
          break

      # No change needed if the indents are identical (compare the whitespace
      # itself, so "\t\t" vs "  " counts as a change)
      if prevLine[0 ..< prevIndent] == lineContent[0 ..< currentIndent]:
        return Result[(), string].ok ()

      # Rebuild the line with the previous line's indent (copied verbatim to
      # keep tabs) in front of the current line's non-whitespace content.
      let newIndent = prevLine[0 ..< prevIndent]
      let reindent = proc(text: string): string =
        newIndent & text[min(currentIndent, text.len) ..^ 1]

      let lineStart = BufferPosition(line: currentLine, column: 0)
      let lineEnd = BufferPosition(line: currentLine, column: lineContent.charLen - 1)

      let txr = withTransaction(ctx.buffer, "auto indent line"):
        let res = ctx.buffer.transformRange(lineStart, lineEnd, "auto indent", reindent)
        if res.isErr:
          return err(res.error)
      if txr.isErr:
        return err(txr.error)

      # Move cursor to first non-blank character
      ctx.cursor.column = prevIndent

      return Result[(), string].ok (),
    0,
    0, # No arguments
  )

  registry.register(
    custom("join.lines"),
    "Join Lines",
    "Join current line with next line(s) (J command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleJoinLines(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("show.char.info"),
    "Show Character Info",
    "Show ASCII/Unicode value of character under cursor (ga command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleShowCharInfo(ctx),
    0,
    0, # No arguments
  )

  # Note: change.word is now handled by operator+motion system (c+w)
  # The operator.change handler sets pendingOperator, then Motion.WordForward
  # is executed, and executeOperatorOnRange is called automatically

  # Undo/Redo commands
  proc clampCursorToBuffer(ctx: CommandContext) =
    ## Clamp cursor position to valid buffer range (delegates to CursorManager)
    let mgr = ctx.motionController.cursorManager
    let pos = CursorPosition(y: ctx.cursor.line, x: ctx.cursor.column)
    let clamped = mgr.clampPosition(pos, ctx.buffer)
    ctx.cursor = BufferPosition(line: clamped.y, column: clamped.x)

  registry.register(
    builtin(bcEditUndo),
    "Undo",
    "Undo the last change(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      var lastCursorPos: Option[BufferPosition] = none(BufferPosition)
      for i in 1 .. count:
        let r = ctx.buffer.undo()
        if r.isErr:
          if i == 1:
            return err(r.error)
          else:
            break # Stop if we can't undo anymore
        lastCursorPos = some(r.value)

      if lastCursorPos.isSome:
        ctx.cursor = lastCursorPos.get
        clampCursorToBuffer(ctx)

      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    builtin(bcEditRedo),
    "Redo",
    "Redo the last undone change(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      var lastCursorPos: Option[BufferPosition] = none(BufferPosition)
      for i in 1 .. count:
        let r = ctx.buffer.redo()
        if r.isErr:
          if i == 1:
            return err(r.error)
          else:
            break # Stop if we can't redo anymore
        lastCursorPos = some(r.value)

      if lastCursorPos.isSome:
        ctx.cursor = lastCursorPos.get
        clampCursorToBuffer(ctx)

      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  # Increment/Decrement number commands
  registry.register(
    builtin(bcEditIncrementNumber),
    "Increment Number",
    "Increment the number at or after cursor (Ctrl-A)",
    handleIncrementNumber,
    0,
    0,
  )

  registry.register(
    builtin(bcEditDecrementNumber),
    "Decrement Number",
    "Decrement the number at or after cursor (Ctrl-X)",
    handleDecrementNumber,
    0,
    0,
  )

  # Repeat last change command (.)
  registry.register(
    custom("edit.repeat"),
    "Repeat Last Change",
    "Repeat the last change command (. command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Check if we have a last edit command
      if ctx.state.editState.lastEditCommand.isNone:
        return err("No previous change to repeat")

      var lastCmd = ctx.state.editState.lastEditCommand.get
      # The change goes to the register it used again, a numbered one counting
      # up (`"1p..` puts "1, "2, "3), as Vim's. One that used none takes the
      # register named before `.` and keeps it for the next `.`.
      if lastCmd.register.isSome:
        var name = lastCmd.register.get
        if name in '1' .. '8':
          name = succ(name)
        ctx.register = some(name)
      lastCmd.register = ctx.register
      # A count given to `.` replaces the change's own, and the next `.` keeps
      # it: `dw` then `3.` is `3dw`. An Insert change takes it below.
      if args.len > 0:
        let count = parseCount(args)
        case lastCmd.kind
        of lecOperatorMotion:
          lastCmd.operand.count = count
          lastCmd.operand.countGiven = true
        of lecReplaceChar:
          lastCmd.replaceCount = count
        of lecDeleteChar:
          lastCmd.deleteCount = count
        of lecDeleteLine:
          lastCmd.deleteLineCount = count
        of lecPaste:
          lastCmd.pasteCount = count
        of lecToggleCase:
          lastCmd.toggleCaseCount = count
        of lecJoinLines:
          lastCmd.joinLinesCount = count
        of lecOperatorLines:
          lastCmd.operatorLineCount = count
        of lecInsert, lecVisualReplace:
          discard
      ctx.state.editState.lastEditCommand = some(lastCmd)

      case lastCmd.kind
      of lecOperatorMotion:
        # The operator acts again over what its operand finds from here (`dw`,
        # `diw`, `dn` then `.`).
        ctx.startOperator(lastCmd.operator)
        return registry.finishOperator(ctx, lastCmd.operand)
      of lecDeleteChar:
        # Repeat character deletion (x or X)
        if lastCmd.deleteForward:
          # x command - delete forward
          return handleDeleteChar(ctx, lastCmd.deleteCount)
        else:
          # X command - delete backward
          return handleDeleteCharBefore(ctx, lastCmd.deleteCount)
      of lecDeleteLine:
        # Repeat line deletion (dd)
        return handleDeleteLine(ctx, lastCmd.deleteLineCount)
      of lecPaste:
        # Repeat paste operation (p, P, gp, or gP)
        if lastCmd.pasteBefore:
          return handlePasteBefore(ctx, lastCmd.pasteCount, lastCmd.pasteCursorAfter)
        else:
          return handlePasteAfter(ctx, lastCmd.pasteCount, lastCmd.pasteCursorAfter)
      of lecToggleCase:
        # Repeat toggle case (~)
        return handleToggleCase(ctx, lastCmd.toggleCaseCount)
      of lecInsert:
        # The command that entered Insert runs again, with the count given to
        # `.`, and the caller types the record after it.
        let record = ctx.state.editState.insertRecord
        let count =
          if args.len > 0:
            parseCount(args)
          else:
            record.count
        case record.entry.kind
        of ieInsert, ieAppend, ieAppendEnd, ieInsertNonBlank, ieOpenBelow, ieOpenAbove:
          return ctx.handleInsertAt(record.entry.kind, count)
        of ieSubstitute:
          return handleSubstituteChar(ctx, count)
        of ieSubstituteLine:
          return handleSubstituteLine(ctx, count)
        of ieChangeToEnd:
          return registry.handleChangeToEnd(ctx, count)
        of ieChange:
          var operand = record.entry.operand
          if args.len > 0:
            operand.count = count
            operand.countGiven = true
          ctx.startOperator(OpChange)
          return registry.finishOperator(ctx, operand)
      of lecVisualReplace:
        # Repeat Visual `r` from the cursor with the recorded shape.
        # Ignores count; cursor stays put. Fails on raw buffers.
        let repChar = lastCmd.visualReplaceChar
        let repFill = proc(text: string): string =
          repChar.repeat(text.charLen)
        case lastCmd.visualReplaceKind
        of vskChar:
          if lastCmd.visualReplaceRows <= 1:
            # Single-line charwise: the same character count from the cursor,
            # or the whole fold linewise when the cursor sits in a closed one.
            let line = ctx.cursor.line
            if line < 0 or line >= ctx.buffer.len:
              return err("Nothing to replace")
            if ctx.buffer.foldState.endsInCollapsedFold(line, line):
              let (snapLo, snapHi) = ctx.buffer.foldState.snapRangeToFolds(line, line)
              let txr = withTransaction(ctx.buffer, "repeat visual replace"):
                let res = ctx.buffer.replaceWholeLines(
                  snapLo, snapHi, "replace characters", repFill
                )
                if res.isErr:
                  return err(res.error)
              if txr.isErr:
                return err(txr.error)
              return ok(())
            let lineContent = ctx.buffer.getLine(line)
            if ctx.cursor.column >= lineContent.charLen:
              return err("Nothing to replace")
            let charsAvailable = lineContent.charLen - ctx.cursor.column
            let charsToReplace = min(lastCmd.visualReplaceCols, charsAvailable)
            let txr = withTransaction(ctx.buffer, "repeat visual replace"):
              let res = ctx.buffer.transformRange(
                ctx.cursor,
                BufferPosition(
                  line: ctx.cursor.line, column: ctx.cursor.column + charsToReplace - 1
                ),
                "replace characters",
                repFill,
              )
              if res.isErr:
                return err(res.error)
            if txr.isErr:
              return err(txr.error)
            return ok(())
          # Multi-line charwise: first line cursor to EOL, middle lines
          # whole, last line `visualReplaceCols` chars from column 0.
          let firstLine = ctx.cursor.line
          if firstLine < 0 or firstLine >= ctx.buffer.len:
            return err("Nothing to replace")
          let lastLine =
            min(firstLine + lastCmd.visualReplaceRows - 1, ctx.buffer.len - 1)
          let (snapLo, snapHi) =
            ctx.buffer.foldState.snapRangeToFolds(firstLine, lastLine)
          let txr = withTransaction(ctx.buffer, "repeat visual replace"):
            # A closed fold at either end repeats whole, linewise. One the range
            # ends exactly on does not widen it, so test the ends, not a widening.
            if ctx.buffer.foldState.endsInCollapsedFold(firstLine, lastLine):
              let res = ctx.buffer.replaceWholeLines(
                snapLo, snapHi, "replace characters", repFill
              )
              if res.isErr:
                return err(res.error)
            else:
              let firstContent = ctx.buffer.getLine(firstLine)
              if ctx.cursor.column < firstContent.charLen:
                let res = ctx.buffer.transformRange(
                  ctx.cursor,
                  BufferPosition(line: firstLine, column: firstContent.charLen - 1),
                  "replace characters",
                  repFill,
                )
                if res.isErr:
                  return err(res.error)
              for lineNum in firstLine + 1 ..< lastLine:
                let lineCharLen = ctx.buffer.getLine(lineNum).charLen
                if lineCharLen > 0:
                  let res = ctx.buffer.transformRange(
                    BufferPosition(line: lineNum, column: 0),
                    BufferPosition(line: lineNum, column: lineCharLen - 1),
                    "replace characters",
                    repFill,
                  )
                  if res.isErr:
                    return err(res.error)
              if lastLine > firstLine:
                let lastContent = ctx.buffer.getLine(lastLine)
                if lastContent.charLen > 0:
                  let lastCount = min(lastCmd.visualReplaceCols, lastContent.charLen)
                  let res = ctx.buffer.transformRange(
                    BufferPosition(line: lastLine, column: 0),
                    BufferPosition(line: lastLine, column: lastCount - 1),
                    "replace characters",
                    repFill,
                  )
                  if res.isErr:
                    return err(res.error)
          if txr.isErr:
            return err(txr.error)
          return ok(())
        of vskLine:
          # Linewise: same line count from the cursor, whole lines.
          let (startLine, endLine, lineCount) =
            ctx.cursorLineRange(lastCmd.visualReplaceRows)
          if lineCount <= 0:
            return err("Nothing to replace")
          let txr = withTransaction(ctx.buffer, "repeat visual replace"):
            let res = ctx.buffer.replaceWholeLines(
              startLine, endLine, "replace characters", repFill
            )
            if res.isErr:
              return err(res.error)
          if txr.isErr:
            return err(txr.error)
          return ok(())
        of vskBlock:
          # Blockwise: same rows x columns from the cursor, clamped per line.
          let firstLine = ctx.cursor.line
          if firstLine < 0 or firstLine >= ctx.buffer.len:
            return err("Nothing to replace")
          let
            startCol = ctx.cursor.column
            endCol = startCol + max(1, lastCmd.visualReplaceCols) - 1
            lastLine =
              min(firstLine + max(1, lastCmd.visualReplaceRows) - 1, ctx.buffer.len - 1)
          let (snapLo, snapHi) =
            ctx.buffer.foldState.snapRangeToFolds(firstLine, lastLine)
          let txr = withTransaction(ctx.buffer, "repeat visual replace"):
            # A closed fold at either end repeats whole, linewise. One the range
            # ends exactly on does not widen it, so test the ends, not a widening.
            if ctx.buffer.foldState.endsInCollapsedFold(firstLine, lastLine):
              let res = ctx.buffer.replaceWholeLines(
                snapLo, snapHi, "replace characters", repFill
              )
              if res.isErr:
                return err(res.error)
            else:
              for lineNum in firstLine .. lastLine:
                let lineLen = ctx.buffer.getLine(lineNum).charLen
                if startCol < lineLen:
                  let actualEndCol = min(endCol, lineLen - 1)
                  let res = ctx.buffer.transformRange(
                    BufferPosition(line: lineNum, column: startCol),
                    BufferPosition(line: lineNum, column: actualEndCol),
                    "replace characters",
                    repFill,
                  )
                  if res.isErr:
                    return err(res.error)
          if txr.isErr:
            return err(txr.error)
          return ok(())
      of lecReplaceChar:
        # Repeat replace character (r command)
        let lineContent = ctx.buffer.getLine(ctx.cursor.line)

        # Check if we're at or past the end of the line
        if ctx.cursor.column >= lineContent.charLen:
          return err("Nothing to replace")

        # Calculate how many characters we can actually replace
        let charsAvailable = lineContent.charLen - ctx.cursor.column
        let charsToReplace = min(lastCmd.replaceCount, charsAvailable)

        let txr = withTransaction(ctx.buffer, "replace " & $charsToReplace & " char(s)"):
          for i in 0 ..< charsToReplace:
            let pos =
              BufferPosition(line: ctx.cursor.line, column: ctx.cursor.column + i)
            let delResult = ctx.buffer.deleteRange(pos, pos)
            if delResult.isErr:
              return err(delResult.error)

            let insResult = ctx.buffer.insertText(pos, lastCmd.replaceChar)
            if insResult.isErr:
              return err(insResult.error)
        if txr.isErr:
          return err(txr.error)

        # Move cursor to the last replaced character
        ctx.cursor.column += charsToReplace - 1
        return ok(())
      of lecJoinLines:
        # Repeat join lines (J command)
        return handleJoinLines(ctx, lastCmd.joinLinesCount)
      of lecOperatorLines:
        # Repeat a doubled linewise operator (>> / << / guu / gUU)
        return
          handleOperatorOnLines(ctx, lastCmd.linesOperator, lastCmd.operatorLineCount),
    0,
    1,
  )

  # Operator commands (d, c, y) - these wait for motion/text object
  registry.register(
    custom("operator.delete"),
    "Delete Operator",
    "Delete operator - waits for motion (d2w, d$, etc.) or dd for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorDelete(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.change"),
    "Change Operator",
    "Change operator - waits for motion (c2w, c$, etc.) or cc for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorChange(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.yank"),
    "Yank Operator",
    "Yank operator - waits for motion (y2w, y$, etc.) or yy for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorYank(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.indent"),
    "Indent Operator",
    "Indent operator - waits for motion (>w, >$, etc.) or >> for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorIndent(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.outdent"),
    "Outdent Operator",
    "Outdent operator - waits for motion (<w, <$, etc.) or << for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorOutdent(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.lowercase"),
    "Lowercase Operator",
    "Lowercase operator - waits for motion (guw, gu$, etc.)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorLowerCase(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.uppercase"),
    "Uppercase Operator",
    "Uppercase operator - waits for motion (gUw, gU$, etc.)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleOperatorUpperCase(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1, # Accept optional count
  )

  # D - Delete to end of line (equivalent to d$)
  registry.register(
    custom("operator.delete.to.end"),
    "Delete To End Of Line",
    "Delete from cursor to end of line (D command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Calculate range from cursor to end of line
      let startPos = ctx.cursor
      let line = ctx.buffer.getLine(startPos.line)
      let lineLen = line.charLen

      # Empty line or cursor at/past end: nothing to delete
      if lineLen == 0 or startPos.column >= lineLen:
        return ok(())

      # End at last character (same as d$ / Motion.End)
      let endPos = BufferPosition(line: startPos.line, column: lineLen - 1)

      let range = OperatorRange(start: startPos, endPos: endPos, isLinewise: false)

      # Execute delete operation
      let r = executeOperatorOnRange(ctx, OpDelete, range, 1)
      if r.isOk:
        # Record this command for repeat (.)
        ctx.recordChange(
          LastEditCommand(
            kind: lecOperatorMotion,
            operator: OpDelete,
            operand: Operand(count: 1, kind: odMotion, motion: Motion.End),
          )
        )
      return r,
    0,
    0,
  )

  # C - Change to end of line (equivalent to c$)
  registry.register(
    custom("operator.change.to.end"),
    "Change To End Of Line",
    "Change from cursor to end of line (C command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      registry.handleChangeToEnd(ctx, parseCount(args)),
    0,
    1,
  )

  # Text object commands (i, a) - wait for text object kind
  registry.register(
    custom("textobject.inner"),
    "Inner Text Object",
    "Select inner text object (iw, i\", i(, etc.) or enter Insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # When `i` resolves to Insert mode, args[0] (present for count > 1) carries
      # the [count] prefix for replay; as a text object the count is ignored.
      handleTextObjectInner(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1,
  )

  registry.register(
    custom("textobject.around"),
    "Around Text Object",
    "Select around text object (aw, a\", a(, etc.) or enter Append mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleTextObjectAround(ctx, parseCount(args), countGiven = args.len > 0),
    0,
    1,
  )

  # Text object kind commands (w, ", (, etc.)
  proc registerTextObjectKind(
      reg: CommandRegistry, id: string, name: string, desc: string, kind: TextObjectKind
  ) =
    reg.register(
      custom(id),
      name,
      desc,
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        # Check if we have a pending text object modifier
        if ctx.state.pendingInput.pendingTextObject.isNone:
          # No text object modifier - ignore this key press
          # (In the future, we should fallback to the key's normal function)
          return ok(())

        let textObj = ctx.state.pendingInput.pendingTextObject.get
        let op = ctx.state.pendingInput.pendingOperator
        if op.isSome:
          return reg.finishOperator(
            ctx,
            Operand(
              count: op.get.operandCount(textObj.count),
              countGiven: op.get.countGiven or textObj.countGiven,
              kind: odTextObject,
              textObjectModifier: textObj.modifier,
              textObjectKind: kind,
            ),
          )
        ctx.state.pendingInput.pendingTextObject = none(PendingTextObject)

        let rangeResult = calculateTextObjectRange(
          ctx.buffer, ctx.cursor, kind, textObj.modifier, textObj.count
        )
        if rangeResult.isErr:
          return err(rangeResult.error)
        let toRange = rangeResult.value

        if isVisualAllMode(ctx.state.mode):
          if toRange.isEmpty:
            # Empty object (e.g. vit on <a></a>): nothing to select, so leave
            # the current selection untouched like vim.
            return ok(())
          # In Visual mode - update selection to text object range
          ctx.state.selectVisualRange(toRange.start, toRange.lastCell(ctx.buffer))
          return ok(())
        else:
          return err("Text objects require an operator or Visual mode"),
      0,
      0,
    )

  # Register text object kinds
  registerTextObjectKind(
    registry, "textobject.word", "Word Text Object", "Word text object (iw/aw)", toWord
  )
  registerTextObjectKind(
    registry, "textobject.wideword", "WORD Text Object",
    "WORD text object - space-separated (iW/aW)", toWideWord,
  )
  registerTextObjectKind(
    registry, "textobject.quote.double", "Double Quote Text Object",
    "Double-quoted string (i\"/a\")", toQuotedDouble,
  )
  registerTextObjectKind(
    registry, "textobject.quote.single", "Single Quote Text Object",
    "Single-quoted string (i'/a')", toQuotedSingle,
  )
  registerTextObjectKind(
    registry, "textobject.quote.backtick", "Backtick Text Object",
    "Backtick string (i`/a`)", toQuotedBacktick,
  )
  registerTextObjectKind(
    registry, "textobject.paren", "Parenthesis Text Object", "Parentheses (i(/a()",
    toParenthesis,
  )
  registerTextObjectKind(
    registry, "textobject.bracket", "Bracket Text Object", "Square brackets (i[/a[)",
    toBracket,
  )
  registerTextObjectKind(
    registry, "textobject.brace", "Brace Text Object", "Curly braces (i{/a{)", toBrace
  )
  registerTextObjectKind(
    registry, "textobject.angle", "Angle Bracket Text Object", "Angle brackets (i</a<)",
    toAngleBracket,
  )
  registerTextObjectKind(
    registry, "textobject.tag", "Tag Text Object", "HTML/XML tag (it/at)", toTag
  )
  registerTextObjectKind(
    registry, "textobject.sentence", "Sentence Text Object", "Sentence (is/as)",
    toSentence,
  )
  registerTextObjectKind(
    registry, "textobject.paragraph", "Paragraph Text Object", "Paragraph (ip/ap)",
    toParagraph,
  )
