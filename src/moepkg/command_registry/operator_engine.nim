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

import std/[options, strutils]

import pkg/results

import
  ../[
    cursor_util, types, motion, modes, registers, logger, unicode_utils, pending_input
  ]
import ../buffer/[core, edit, undo]
import ../command_handlers/insert_commands

import core

proc rollbackAndPropagate*(
    ctx: CommandContext,
    primaryError: string,
    savedCursor: Option[BufferPosition] = none(BufferPosition),
): Result[(), string] =
  ## Roll back the open transaction and return `primaryError`. A failed
  ## rollback is logged and appended to the error; with `savedCursor`,
  ## restore the cursor after a successful rollback.
  let rollbackResult = ctx.buffer.rollbackTransaction()
  if rollbackResult.isErr:
    logError "operator", "Failed to rollback transaction: " & rollbackResult.error
    return err(primaryError & " (rollback failed: " & rollbackResult.error & ")")
  if savedCursor.isSome:
    ctx.cursor = savedCursor.get
  err(primaryError)

proc storeYankedText*(ctx: CommandContext, text: string, isLine: bool) =
  ## Store yanked text in the register this command names, else the yank register.
  if not ctx.state.registers.isNil:
    ctx.state.registers.storeYanked(ctx.register, text, isLine)

proc storeDeletedText*(
    ctx: CommandContext, text: string, isLine: bool, useRegOne = false
) =
  ## Store deleted text in the register this command names and the delete
  ## registers, as Vim's op_delete.
  if not ctx.state.registers.isNil:
    ctx.state.registers.storeDeleted(ctx.register, text, isLine, useRegOne)

proc moveToFirstNonBlank*(ctx: CommandContext, lineNum: int) =
  ## Put the cursor on the first non-blank of `lineNum` (vim's `^`), clamped to
  ## the last valid column so a blank-only line does not land past the end.
  if lineNum < 0 or lineNum >= ctx.buffer.len:
    return

  let line = ctx.buffer.getLine(lineNum)
  ctx.cursor.line = lineNum
  ctx.cursor.column = firstNonBlankColumn(line)

proc textRewriteAction*(operatorType: OperatorType): Option[string] =
  ## Rewrite name for operator, or none if safe. Listing marks byte-unsafe for raw buffers.
  case operatorType
  of OpIndent:
    some("indent")
  of OpOutdent:
    some("dedent")
  of OpLowerCase:
    some("lowercase")
  of OpUpperCase:
    some("uppercase")
  of OpSwapCase:
    some("toggle case")
  else:
    none(string)

proc refuseOnRawBytes(ctx: CommandContext, operatorType: OperatorType): Option[string] =
  ## Refusal for raw buffer, or none if safe. Checked before side effects.
  let action = textRewriteAction(operatorType)
  if action.isNone or ctx.buffer.allowsTextTransforms:
    return none(string)

  some(rawBytesRejection(action.get))

proc applyCaseOperator(
    ctx: CommandContext,
    range: OperatorRange,
    label: string,
    action: string,
    transform: proc(text: string): string {.closure, gcsafe.},
): Result[(), string] =
  ## Shared body of gu/gU/g~: rewrite the range's text through `transform`.
  ## The cursor stays where the driver put it, as Vim's op_tilde leaves it,
  ## and an undo brings it back there.
  let txr = withTransaction(ctx.buffer, label, some(ctx.cursor)):
    if range.isLinewise:
      for lineNum in range.start.line .. range.endPos.line:
        if lineNum < ctx.buffer.len:
          let lineCharLen = ctx.buffer.getLine(lineNum).charLen
          if lineCharLen > 0:
            let startPos = BufferPosition(line: lineNum, column: 0)
            let endPos = BufferPosition(line: lineNum, column: lineCharLen - 1)
            let res = ctx.buffer.transformRange(startPos, endPos, action, transform)
            if res.isErr:
              return err(res.error)
    else:
      let res = ctx.buffer.transformRange(range.start, range.endPos, action, transform)
      if res.isErr:
        return err(res.error)
  if txr.isErr:
    return err("Transaction failed: " & txr.error)
  ok(())

proc shiftedLines(buffer: TextBuffer, range: OperatorRange): (int, int) =
  ## The lines `>`/`<` shift over `range`: those it touches. A text object
  ## that starts at the end of a line (a sentence after one) touches nothing
  ## of that line.
  result = (range.start.line, range.endPos.line)
  if not range.isLinewise and range.start.line < range.endPos.line and
      range.start.column >= buffer.getLine(range.start.line).charLen:
    result[0] += 1

proc restoreTopLine(ctx: CommandContext, topLine: int) =
  ## Put the viewport's top line back after a change, clamped so the cursor
  ## stays in view.
  let
    bufferLen = ctx.buffer.len
    cursorLine = ctx.cursor.line
  if topLine >= bufferLen:
    ctx.motionController.viewportManager.viewport.resetViewportTop(
      max(0, min(cursorLine, bufferLen - 1))
    )
  elif cursorLine < topLine:
    ctx.motionController.viewportManager.viewport.resetViewportTop(cursorLine)
  else:
    ctx.motionController.viewportManager.viewport.resetViewportTop(topLine)

proc lineCount(range: OperatorRange): int =
  range.endPos.line - range.start.line + 1

proc report(ctx: CommandContext, operatorType: OperatorType, msg: string) =
  ## Tell of a yank or a delete as the notification settings ask.
  let cfg = ctx.notificationConfig
  let (screen, log, tag) =
    if operatorType == OpYank:
      (cfg.yankScreenNotify, cfg.yankLogNotify, "yank")
    else:
      (cfg.deleteScreenNotify, cfg.deleteLogNotify, "delete")
  if cfg.screenNotifications and screen:
    ctx.notify(msg)
  if cfg.logNotifications and log:
    logInfo(tag, msg)

proc executeOperatorOnRange*(
    ctx: CommandContext,
    operatorType: OperatorType,
    range: OperatorRange,
    operatorCount: int,
    topLine = none(int),
): Result[(), string] =
  ## Execute an operator on the given range, as `operator_driver` takes it in
  ## (closed folds included)
  ## operatorCount: count before operator (e.g., "2" in "2d3w")
  ## topLine: viewport top line when the operator started, put back after the
  ## change; the current one when no motion ran since

  let topLine = topLine.get(ctx.motionController.viewportManager.viewport.topLine)

  logDebug(
    "operator",
    "executeOperatorOnRange: " & $operatorType & " on range " & $range.start & " to " &
      $range.endPos & ", linewise=" & $range.isLinewise,
  )

  let rejection = refuseOnRawBytes(ctx, operatorType)
  if rejection.isSome:
    return err(rejection.get)

  # Vim's operators drop curswant, even ones that leave the cursor and text or
  # take no text (`yl` on an empty line).
  ctx.state.preferredColumn = -1

  if range.isEmpty and operatorType notin {OpYank, OpChange, OpIndent, OpOutdent}:
    # Empty object (e.g. dit on <a></a>, gUi" on ""): the range spans no
    # characters, so the operator is a no-op and the registers stay untouched.
    # A yank still keeps the empty text, as Vim's op_yank does (`yl` on an
    # empty line); `c` still drops into Insert between the delimiters, and
    # `>`/`<` still shift the line, as Vim's op_shift does (`>i(` on `()`).
    return ok(())

  case operatorType
  of OpYank:
    # Yank (copy) the range
    let text = extractRangeText(ctx.buffer, range)

    storeYankedText(ctx, text, range.isLinewise)

    ctx.report(
      OpYank,
      if range.isLinewise:
        "Yanked " & $range.lineCount & " line(s)"
      else:
        "Yanked " & $text.len & " character(s)",
    )

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
    storeDeletedText(ctx, text, range.isLinewise, range.useRegOne)

    # Move cursor to start of deletion
    ctx.cursor = range.start
    # Clamp cursor to valid position
    if ctx.cursor.line >= ctx.buffer.len:
      ctx.cursor.line = max(0, ctx.buffer.len - 1)
    if range.isLinewise:
      # Vim's op_delete lands on the first non-blank of the line that follows.
      moveToFirstNonBlank(ctx, ctx.cursor.line)
    elif ctx.cursor.line < ctx.buffer.len:
      let line = ctx.buffer.getLine(ctx.cursor.line)
      ctx.cursor.column = min(ctx.cursor.column, max(0, line.charLen - 1))

    if range.isLinewise:
      ctx.report(OpDelete, "Deleted " & $range.lineCount & " line(s)")
    ctx.restoreTopLine(topLine)
    return ok(())
  of OpChange:
    # Change the range (delete and enter insert mode)
    let text = extractRangeText(ctx.buffer, range)

    let undoCursor =
      if range.isLinewise:
        ctx.buffer.linewiseChangeStart(range.start.line)
      else:
        range.start
    let txr = withTransactionForInsert(ctx.buffer, "Change operation", undoCursor):
      if range.isLinewise:
        let emptied =
          ctx.buffer.emptyLinesForChange(ctx.state, range.start.line, range.endPos.line)
        if emptied.isErr:
          return err(emptied.error)
      else:
        let delResult = deleteRange(ctx.buffer, range)
        if delResult.isErr:
          return err(delResult.error)
        ctx.cursor = range.start
        ctx.cursor.line = min(ctx.cursor.line, max(0, ctx.buffer.len - 1))
        # Insert mode allows cursor at charLen (append position).
        ctx.cursor.column =
          min(ctx.cursor.column, ctx.buffer.getLine(ctx.cursor.line).charLen)
    if txr.isErr:
      return err("Failed to begin transaction: " & txr.error)

    if not range.isEmpty:
      # Store in register only after the buffer change succeeded (registers are
      # not covered by the transaction). An empty object (e.g. cit on <a></a>)
      # removes nothing, so leave the registers untouched.
      storeDeletedText(ctx, text, range.isLinewise, range.useRegOne)

    ctx.restoreTopLine(topLine)

    # Enter insert mode (transaction remains open for insert mode input)
    ctx.state.mode = EditorMode.Insert

    return ok(())
  of OpIndent, OpOutdent:
    let
      (startLine, endLine) = ctx.buffer.shiftedLines(range)
      left = operatorType == OpOutdent

    # The driver put the cursor where the operated text starts, which undo
    # brings it back to, as Vim's u_undoredo with uh_cursor.
    let txr = withTransaction(
      ctx.buffer, if left: "Dedent lines" else: "Indent lines", some(ctx.cursor)
    ):
      let shifted = ctx.buffer.shiftLines(ctx.state, startLine, endLine, left)
      if shifted.isErr:
        return err(shifted.error)
    if txr.isErr:
      return err("Transaction failed: " & txr.error)

    moveToFirstNonBlank(ctx, startLine)

    return ok(())
  of OpLowerCase:
    return applyCaseOperator(ctx, range, "Lowercase", "lowercase", toLowerAscii)
  of OpUpperCase:
    return applyCaseOperator(ctx, range, "Uppercase", "uppercase", toUpperAscii)
  of OpSwapCase:
    return applyCaseOperator(ctx, range, "Toggle case", "toggle case", toggleAsciiCase)

## Operator command helpers

proc startOperator*(
    ctx: CommandContext, operatorType: OperatorType, count = 1, countGiven = false
) =
  ## Wait for the operand of `operatorType`, keeping the top line the change
  ## puts back.
  ctx.state.pendingInput.pendingOperator = some(
    PendingOperator(
      operatorType: operatorType,
      operatorCount: max(1, count),
      countGiven: countGiven,
      startPos: ctx.cursor,
      register: ctx.register,
      topLine: ctx.motionController.viewportManager.viewport.topLine,
    )
  )

proc setPendingOperator*(
    ctx: CommandContext,
    operatorType: OperatorType,
    count: int,
    countGiven: bool,
    statusMsg: string,
) =
  ## Start the typed operator `operatorType`, cancelling one of another kind
  ## already waiting (`dyw` neither deletes nor yanks).
  if ctx.state.pendingInput.cancelOperatorPending():
    ctx.state.statusMessage = ""
    return
  ctx.startOperator(operatorType, count, countGiven)
  ctx.state.statusMessage = statusMsg

proc namedMarkPosition*(
    ctx: CommandContext, name: char
): Result[BufferPosition, string] =
  ## Resolve a buffer-local mark, clamping its column after line replacements.
  if name notin {'a' .. 'z'}:
    return err("Invalid mark (use a-z)")
  let mark = ctx.buffer.namedMarks[name]
  if mark.isNone or mark.get.line >= ctx.buffer.len:
    return err("Mark not set: " & $name)
  var pos = mark.get
  pos.column = min(pos.column, max(0, ctx.buffer.getLine(pos.line).charLen - 1))
  ok(pos)
