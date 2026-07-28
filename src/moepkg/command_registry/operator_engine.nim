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

## Operator engine: executes operators (yank/delete/change/indent/case) on a
## range, plus register dispatch helpers and pending-operator state setter.

import std/[options, strutils, unicode]

import pkg/results

import ../[types, motion, modes, registers, logger]
import ../buffer/[core, edit, fold, undo]
import ../command_handlers/insert_commands

import core

## Helper for register dispatch
## These helpers check pendingRegister and route content to the correct register.

proc storeYankedText*(ctx: CommandContext, text: string, isLine: bool) =
  ## Store yanked text in the appropriate register, respecting pendingRegister.
  ## Also writes to the system clipboard when appropriate.
  if ctx.state.registers.isNil:
    return

  if ctx.state.pendingInput.pendingRegister.isSome and
      ctx.state.pendingInput.pendingRegister.get != '\0':
    let regName = ctx.state.pendingInput.pendingRegister.get
    if regName.isNamedRegisterName:
      discard ctx.state.registers.setNamedRegister(regName, text, isLine)
    elif regName.isClipboardRegisterName:
      ctx.state.registers.setClipboardRegister(regName, text, isLine)
    else:
      ctx.state.registers.setYankedRegister(text, isLine)
    ctx.state.pendingInput.pendingRegister = none(char)
  else:
    ctx.state.registers.setYankedRegister(text, isLine)

proc storeDeletedText*(ctx: CommandContext, text: string, isLine: bool) =
  ## Store deleted text in the appropriate register, respecting pendingRegister.
  ## Also writes to the system clipboard when appropriate.
  if ctx.state.registers.isNil:
    return

  if ctx.state.pendingInput.pendingRegister.isSome and
      ctx.state.pendingInput.pendingRegister.get != '\0':
    let regName = ctx.state.pendingInput.pendingRegister.get
    if regName.isNamedRegisterName:
      discard ctx.state.registers.setNamedRegister(regName, text, isLine)
    elif regName.isClipboardRegisterName:
      ctx.state.registers.setClipboardRegister(regName, text, isLine)
    else:
      ctx.state.registers.setDeletedRegister(text, isLine)
    ctx.state.pendingInput.pendingRegister = none(char)
  else:
    ctx.state.registers.setDeletedRegister(text, isLine)

proc moveToFirstNonBlank*(ctx: CommandContext, lineNum: int) =
  ## Put the cursor on the first non-blank of `lineNum` (vim's `^`), clamped to
  ## the last valid column so a blank-only line does not land past the end.
  if lineNum < 0 or lineNum >= ctx.buffer.len:
    return

  let line = ctx.buffer.getLine(lineNum)
  var column = 0
  for r in line.runes:
    if $r == " " or $r == "\t":
      column += 1
    else:
      break

  ctx.cursor.line = lineNum
  ctx.cursor.column = min(column, max(0, line.charLen - 1))

proc executeOperatorOnRange*(
    ctx: CommandContext,
    operatorType: OperatorType,
    range: OperatorRange,
    operatorCount: int,
): Result[(), string] =
  ## Execute an operator on the given range
  ## operatorCount: count before operator (e.g., "2" in "2d3w")

  logDebug(
    "operator",
    "executeOperatorOnRange: " & $operatorType & " on range " & $range.start & " to " &
      $range.endPos & ", linewise=" & $range.isLinewise,
  )

  if range.isEmpty and operatorType != OpChange:
    # Empty object (e.g. yit/dit on <a></a>, gUi" on "", >i( on ()): the range
    # spans no characters, so every operator is a no-op and the registers stay
    # untouched. Only `c` still acts -- it drops into Insert between the
    # delimiters -- so OpChange falls through to its branch below.
    # The operator command still completes, so consume any pending register
    # prefix (e.g. `"ayit`) rather than leaking it into the next command.
    ctx.state.pendingInput.pendingRegister = none(char)
    return ok(())

  case operatorType
  of OpYank:
    # Yank (copy) the range
    let text = extractRangeText(ctx.buffer, range)

    # Store in register system (respects pendingRegister)
    storeYankedText(ctx, text, range.isLinewise)

    let lineCount =
      if range.isLinewise:
        range.endPos.line - range.start.line + 1
      else:
        0
    ctx.state.statusMessage =
      if range.isLinewise:
        "Yanked " & $lineCount & " line(s)"
      else:
        "Yanked " & $text.len & " character(s)"

    # Don't move cursor for yank
    return ok(())
  of OpDelete:
    # Delete the range (and yank it)
    let text = extractRangeText(ctx.buffer, range)

    # Delete the text
    let delResult = deleteRange(ctx.buffer, range)
    if delResult.isErr:
      return err(delResult.error)

    # Store in register only after the buffer change succeeded (registers are not
    # covered by the buffer transaction, so a rollback would not undo them)
    storeDeletedText(ctx, text, range.isLinewise)

    # Move cursor to start of deletion
    ctx.cursor = range.start
    # Clamp cursor to valid position
    if ctx.cursor.line >= ctx.buffer.len:
      ctx.cursor.line = max(0, ctx.buffer.len - 1)
    if ctx.cursor.line < ctx.buffer.len:
      let line = ctx.buffer.getLine(ctx.cursor.line)
      ctx.cursor.column = min(ctx.cursor.column, max(0, line.charLen - 1))

    # Restore viewport position to where it was before the operator started
    # Use savedViewportTopLine which was saved when operator (d/c/y) was pressed
    let newBufferLen = ctx.buffer.len
    let restoredTopLine = ctx.state.windowDisplay.savedViewportTopLine
    let cursorLine = ctx.cursor.line

    # Restore viewport, but ensure cursor remains visible
    # Cases:
    # 1. restoredTopLine >= newBufferLen: clamp to valid range
    # 2. cursor < restoredTopLine: use cursor position (e.g., dgg moves cursor up)
    # 3. otherwise: restore saved position
    if restoredTopLine >= newBufferLen:
      # Saved position is beyond new buffer size
      ctx.motionController.viewportManager.viewport.resetViewportTop(
        max(0, min(cursorLine, newBufferLen - 1))
      )
    elif cursorLine < restoredTopLine:
      # Cursor is above saved viewport (e.g., dgg), use cursor position
      ctx.motionController.viewportManager.viewport.resetViewportTop(cursorLine)
    else:
      # Restore to saved position
      ctx.motionController.viewportManager.viewport.resetViewportTop(restoredTopLine)

    return ok(())
  of OpChange:
    # Change the range (delete and enter insert mode)
    let text = extractRangeText(ctx.buffer, range)

    if range.isEmpty:
      # Empty change still completes the operator command (it drops into Insert
      # between the delimiters), so consume any pending register prefix rather
      # than leaking it into the next command.
      ctx.state.pendingInput.pendingRegister = none(char)

    # Begin transaction for all change operations (delete + insert mode input)
    let transactionResult = ctx.buffer.beginTransaction("Change operation")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    # Delete the text
    let delResult = deleteRange(ctx.buffer, range)
    if delResult.isErr:
      discard ctx.buffer.rollbackTransaction()
      return err(delResult.error)

    if not range.isEmpty:
      # Store in register only after the buffer change succeeded (registers are
      # not covered by the transaction). An empty object (e.g. cit on <a></a>)
      # removes nothing, so leave the registers untouched.
      storeDeletedText(ctx, text, range.isLinewise)

    # Move cursor to start of change
    ctx.cursor = range.start
    # Clamp cursor to valid position
    if ctx.cursor.line >= ctx.buffer.len:
      ctx.cursor.line = max(0, ctx.buffer.len - 1)
    if ctx.cursor.line < ctx.buffer.len:
      let line = ctx.buffer.getLine(ctx.cursor.line)
      # Insert mode allows cursor at charLen (append position)
      ctx.cursor.column = min(ctx.cursor.column, line.charLen)

    # Restore viewport position (same logic as OpDelete)
    let newBufferLen = ctx.buffer.len
    let restoredTopLine = ctx.state.windowDisplay.savedViewportTopLine
    let cursorLine = ctx.cursor.line

    # Restore viewport, but ensure cursor remains visible
    if restoredTopLine >= newBufferLen:
      # Saved position is beyond new buffer size
      ctx.motionController.viewportManager.viewport.resetViewportTop(
        max(0, min(cursorLine, newBufferLen - 1))
      )
    elif cursorLine < restoredTopLine:
      # Cursor is above saved viewport (e.g., cgg), use cursor position
      ctx.motionController.viewportManager.viewport.resetViewportTop(cursorLine)
    else:
      # Restore to saved position
      ctx.motionController.viewportManager.viewport.resetViewportTop(restoredTopLine)

    # Enter insert mode (transaction remains open for insert mode input)
    ctx.state.mode = EditorMode.Insert

    return ok(())
  of OpIndent:
    # Indent lines in the range
    # For character-wise ranges (e.g., i{), adjust start/end lines:
    # If start column is at/past end of line, content starts on the next line.
    # If end column is negative or end line has closing delimiter only, exclude it.
    var startLine = range.start.line
    var endLine = range.endPos.line
    if not range.isLinewise and startLine != endLine:
      if startLine < ctx.buffer.len:
        let startLineContent = ctx.buffer.getLine(startLine)
        if range.start.column >= startLineContent.charLen:
          startLine += 1
      if endLine < ctx.buffer.len and range.endPos.column < 0:
        endLine -= 1

    let txr = withTransaction(ctx.buffer, "Indent lines"):
      let indentStr = getIndentString(ctx.state)
      for lineNum in startLine .. endLine:
        if lineNum < ctx.buffer.len:
          let insertPos = BufferPosition(line: lineNum, column: 0)
          discard ctx.buffer.insertText(insertPos, indentStr)
    if txr.isErr:
      return err("Transaction failed: " & txr.error)

    moveToFirstNonBlank(ctx, startLine)

    return ok(())
  of OpOutdent:
    # Dedent lines in the range (same line adjustment as indent)
    var startLine = range.start.line
    var endLine = range.endPos.line
    if not range.isLinewise and startLine != endLine:
      if startLine < ctx.buffer.len:
        let startLineContent = ctx.buffer.getLine(startLine)
        if range.start.column >= startLineContent.charLen:
          startLine += 1
      if endLine < ctx.buffer.len and range.endPos.column < 0:
        endLine -= 1

    let txr = withTransaction(ctx.buffer, "Dedent lines"):
      let indentWidth = effectiveShiftWidth(ctx.state)
      for lineNum in startLine .. endLine:
        if lineNum < ctx.buffer.len:
          let lineContent = ctx.buffer.getLine(lineNum)
          let currentIndent = getLineIndent(lineContent)
          let removeCount = min(indentWidth, currentIndent.len)
          if removeCount > 0:
            for i in 1 .. removeCount:
              let deletePos = BufferPosition(line: lineNum, column: 0)
              discard ctx.buffer.deleteChar(deletePos)
    if txr.isErr:
      return err("Transaction failed: " & txr.error)

    moveToFirstNonBlank(ctx, startLine)

    return ok(())
  of OpLowerCase:
    let txr = withTransaction(ctx.buffer, "Lowercase"):
      if range.isLinewise:
        for lineNum in range.start.line .. range.endPos.line:
          if lineNum < ctx.buffer.len:
            let lineText = $ctx.buffer.getLine(lineNum)
            let lineCharLen = lineText.charLen
            if lineCharLen > 0:
              let lowerText = lineText.toLowerAscii()
              let startPos = BufferPosition(line: lineNum, column: 0)
              let endPos = BufferPosition(line: lineNum, column: lineCharLen - 1)
              discard ctx.buffer.deleteRange(startPos, endPos)
              discard ctx.buffer.insertText(startPos, lowerText)
      else:
        let text = extractRangeText(ctx.buffer, range)
        let lowerText = text.toLowerAscii()
        discard ctx.buffer.deleteRange(range.start, range.endPos)
        discard ctx.buffer.insertText(range.start, lowerText)
    if txr.isErr:
      return err("Transaction failed: " & txr.error)

    ctx.cursor = range.start
    if range.isLinewise:
      # guu/gUU land on the first non-blank (matches >>/<<)
      moveToFirstNonBlank(ctx, range.start.line)
    return ok(())
  of OpUpperCase:
    let txr = withTransaction(ctx.buffer, "Uppercase"):
      if range.isLinewise:
        for lineNum in range.start.line .. range.endPos.line:
          if lineNum < ctx.buffer.len:
            let lineText = $ctx.buffer.getLine(lineNum)
            let lineCharLen = lineText.charLen
            if lineCharLen > 0:
              let upperText = lineText.toUpperAscii()
              let startPos = BufferPosition(line: lineNum, column: 0)
              let endPos = BufferPosition(line: lineNum, column: lineCharLen - 1)
              discard ctx.buffer.deleteRange(startPos, endPos)
              discard ctx.buffer.insertText(startPos, upperText)
      else:
        let text = extractRangeText(ctx.buffer, range)
        let upperText = text.toUpperAscii()
        discard ctx.buffer.deleteRange(range.start, range.endPos)
        discard ctx.buffer.insertText(range.start, upperText)
    if txr.isErr:
      return err("Transaction failed: " & txr.error)

    ctx.cursor = range.start
    if range.isLinewise:
      moveToFirstNonBlank(ctx, range.start.line)
    return ok(())
  of OpSwapCase:
    return err("Operator " & $operatorType & " not yet implemented")

proc applyOperatorOverMotion*(
    ctx: CommandContext,
    operatorType: OperatorType,
    operatorCount: int,
    startPos, endPos: BufferPosition,
    motion: Motion,
): Result[(), string] =
  ## Apply an operator over a motion's span: build the [startPos, endPos] range,
  ## open any folds it covers (vim keeps folds closed for a pure yank), then run
  ## the operator. Shared by the generic operator+motion path, the find/till
  ## path and the `.` repeat so all three calculate the range and handle folds
  ## identically. The caller owns clearing pendingOperator and recording the
  ## command for `.`.
  let range = calculateOperatorRange(ctx.buffer, startPos, endPos, motion)
  if operatorType != OpYank:
    discard ctx.buffer.foldState.openFoldsInRange(range.start.line, range.endPos.line)
  executeOperatorOnRange(ctx, operatorType, range, operatorCount)

## Operator command helpers
## Use setPendingOperator() for all operators to save viewport position
## before motion execution. This prevents unwanted scrolling.

proc setPendingOperator*(
    ctx: CommandContext, operatorType: OperatorType, count: int, statusMsg: string
) =
  ## Set pending operator and save viewport position for operator+motion commands
  ctx.state.windowDisplay.savedViewportTopLine =
    ctx.motionController.viewportManager.viewport.topLine
  ctx.state.pendingInput.pendingOperator = some(
    PendingOperator(
      operatorType: operatorType, operatorCount: count, startPos: ctx.cursor
    )
  )
  ctx.state.statusMessage = statusMsg
