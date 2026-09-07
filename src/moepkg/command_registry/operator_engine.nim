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

import ../[types, motion, modes, registers, logger, unicode_utils]
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

proc rollbackPasteOnException*(
    ctx: CommandContext, excMsg: string, actualCount: int, savedCursor: BufferPosition
): Result[(), string] =
  ## Exception-safety tail for the paste loops: on an unexpected error, roll
  ## back the paste's own transaction (`actualCount > 1`) and restore the
  ## cursor; a joined outer transaction is left for its own commit path.
  if actualCount > 1 and ctx.buffer.inTransaction:
    let rollbackResult = ctx.buffer.rollbackTransaction()
    if rollbackResult.isErr:
      logError "paste", "Failed to rollback transaction: " & rollbackResult.error
      return err(
        "Paste failed: " & excMsg & " (rollback failed: " & rollbackResult.error & ")"
      )
    ctx.cursor = savedCursor
  elif ctx.buffer.inTransaction:
    return err(
      "Paste failed: " & excMsg &
        " (joined transaction: earlier edits may remain applied)"
    )
  err("Paste failed: " & excMsg)

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
  for (r, _) in line.chars:
    if $r == " " or $r == "\t":
      column += 1
    else:
      break

  ctx.cursor.line = lineNum
  ctx.cursor.column = min(column, max(0, line.charLen - 1))

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
  else:
    none(string)

proc refuseOnRawBytes(ctx: CommandContext, operatorType: OperatorType): Option[string] =
  ## Refusal for raw buffer, or none if safe. Checked before side effects.
  let action = textRewriteAction(operatorType)
  if action.isNone or ctx.buffer.allowsTextTransforms:
    return none(string)

  ctx.state.pendingInput.pendingRegister = none(char)
  some(rawBytesRejection(action.get))

proc applyCaseOperator(
    ctx: CommandContext,
    range: OperatorRange,
    label: string,
    action: string,
    transform: proc(text: string): string {.closure, gcsafe.},
): Result[(), string] =
  ## Shared body of gu/gU: rewrite the range's text through `transform`.
  let txr = withTransaction(ctx.buffer, label):
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

  ctx.cursor = range.start
  if range.isLinewise:
    # guu/gUU land on the first non-blank (matches >>/<<)
    moveToFirstNonBlank(ctx, range.start.line)
  ok(())

proc changeLinesInRange(ctx: CommandContext, range: OperatorRange): Result[(), string] =
  ## Linewise change: vim empties the range down to a single blank line to type
  ## on rather than removing its lines outright. The kept line's indent survives
  ## under autoindent, matching `cc`/`S`.
  let startLine = range.start.line
  if startLine >= ctx.buffer.len:
    return ok(())

  var indent = ""
  if ctx.state.autoIndent and ctx.buffer.allowsTextTransforms:
    for (rune, _) in ctx.buffer.getLine(startLine).chars:
      let ch = $rune
      if ch != " " and ch != "\t":
        break
      indent.add(ch)

  for _ in 0 ..< (range.endPos.line - startLine):
    if startLine + 1 >= ctx.buffer.len:
      break
    let delResult = ctx.buffer.deleteLine(startLine + 1)
    if delResult.isErr:
      return err(delResult.error)

  let line = ctx.buffer.getLine(startLine)
  if line.charLen > 0:
    let clearResult = ctx.buffer.deleteRange(
      BufferPosition(line: startLine, column: 0),
      BufferPosition(line: startLine, column: line.charLen - 1),
    )
    if clearResult.isErr:
      return err(clearResult.error)

  if indent.len > 0:
    let insResult =
      ctx.buffer.insertText(BufferPosition(line: startLine, column: 0), indent)
    if insResult.isErr:
      return err(insResult.error)

  ok(())

proc executeOperatorOnRange*(
    ctx: CommandContext,
    operatorType: OperatorType,
    rawRange: OperatorRange,
    operatorCount: int,
): Result[(), string] =
  ## Execute an operator on the given range
  ## operatorCount: count before operator (e.g., "2" in "2d3w")

  # The one place a closed fold widens an operator range, so every operator path
  # (motion spans, text objects, visual selections) consumes folds whole.
  let range = ctx.buffer.snapOperatorRange(rawRange)

  logDebug(
    "operator",
    "executeOperatorOnRange: " & $operatorType & " on range " & $range.start & " to " &
      $range.endPos & ", linewise=" & $range.isLinewise,
  )

  let rejection = refuseOnRawBytes(ctx, operatorType)
  if rejection.isSome:
    return err(rejection.get)

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
    let delResult =
      if range.isLinewise:
        ctx.changeLinesInRange(range)
      else:
        deleteRange(ctx.buffer, range)
    if delResult.isErr:
      return rollbackAndPropagate(ctx, delResult.error)

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
      # Insert mode allows cursor at charLen (append position). A linewise
      # change leaves only the kept indent, so typing starts after it.
      ctx.cursor.column =
        if range.isLinewise:
          line.charLen
        else:
          min(ctx.cursor.column, line.charLen)

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
          let insertResult = ctx.buffer.insertText(insertPos, indentStr)
          if insertResult.isErr:
            return err(insertResult.error)
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
              let deleteResult = ctx.buffer.deleteChar(deletePos)
              if deleteResult.isErr:
                return err(deleteResult.error)
    if txr.isErr:
      return err("Transaction failed: " & txr.error)

    moveToFirstNonBlank(ctx, startLine)

    return ok(())
  of OpLowerCase:
    return applyCaseOperator(ctx, range, "Lowercase", "lowercase", toLowerAscii)
  of OpUpperCase:
    return applyCaseOperator(ctx, range, "Uppercase", "uppercase", toUpperAscii)
  of OpSwapCase:
    # Rewrites nothing yet, so it is absent from textRewriteAction; add it
    # there along with the applyCaseOperator call that implements it.
    return err("Operator " & $operatorType & " not yet implemented")

proc applyOperatorOverMotion*(
    ctx: CommandContext,
    operatorType: OperatorType,
    operatorCount: int,
    startPos, endPos: BufferPosition,
    motion: Motion,
): Result[(), string] =
  ## Apply operator over motion span.
  # Refuse before any buffer change; restore cursor if rejected.
  let rejection = refuseOnRawBytes(ctx, operatorType)
  if rejection.isSome:
    ctx.cursor = startPos
    return err(rejection.get)

  let range = calculateOperatorRange(ctx.buffer, startPos, endPos, motion)
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

proc applyOperatorToMark*(
    ctx: CommandContext, op: PendingOperator, name: char, linewise: bool
): Result[(), string] =
  ## Apply an operator to a named mark; backtick motions exclude the endpoint.
  let dest = ctx.namedMarkPosition(name)
  if dest.isErr:
    ctx.state.pendingInput.pendingRegister = none(char)
    return err(dest.error)
  var range = calculateOperatorRange(
    ctx.buffer, op.startPos, dest.get, if linewise: Motion.Down else: Motion.Right
  )
  if not linewise and op.startPos == dest.get:
    range.isEmpty = true
  executeOperatorOnRange(ctx, op.operatorType, range, op.operatorCount)
