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

## Visual mode command implementations
##
## This module provides Visual mode specific command implementations
## that are independent of CommandContext for better testability

import std/[options, strutils]

import pkg/results

import
  ../[
    cursor_util, types, registers, modes, config, unicode_utils, visual_selection,
    visual_block,
  ]
import ../buffer/[core, edit, undo]
import insert_commands, number_increment, put_text

template checkVisualEdit(state: EditorState, r: Result[(), string]) =
  ## For use inside a withTransaction body of a Visual command: on an edit
  ## failure surface the error, leave Visual mode and return from the enclosing
  ## proc, with the error when it returns a Result. The return makes
  ## withTransaction roll back, so no partially applied edit is committed.
  let checkVisualEditResult = r
  if checkVisualEditResult.isErr:
    state.statusMessage = checkVisualEditResult.error
    state.leaveVisual()
    when declared(result):
      return err(checkVisualEditResult.error)
    else:
      return

template checkVisualEditAt(
    state: EditorState, cursorBefore: BufferPosition, r: Result[(), string]
) =
  ## `checkVisualEdit` that restores cursor when loop aborts mid-selection.
  let checkVisualEditAtResult = r
  if checkVisualEditAtResult.isErr:
    state.cursor = cursorBefore
  checkVisualEdit(state, checkVisualEditAtResult)

proc getSelectionRange*(
    selection: VisualSelection
): tuple[start, endPos: BufferPosition] {.inline.} =
  ## Get the normalized selection range (start is always before end)
  ## Returns (start, end) where start <= end
  if not selection.active:
    return (selection.start, selection.start)

  # Normalize so start is always before end
  if selection.start.line < selection.current.line:
    return (selection.start, selection.current)
  elif selection.start.line > selection.current.line:
    return (selection.current, selection.start)
  else:
    # Same line - compare columns
    if selection.start.column <= selection.current.column:
      return (selection.start, selection.current)
    else:
      return (selection.current, selection.start)

proc getLineText(buffer: TextBuffer, selection: VisualSelection): string =
  ## Get text from a line-wise selection (entire lines)
  buffer.linewiseText(
    min(selection.start.line, selection.current.line),
    max(selection.start.line, selection.current.line),
  )

proc getVisualSelectionText*(
    buffer: TextBuffer, selection: VisualSelection, tabStop: int
): string =
  ## Get the selected text respecting the selection kind.
  ## Char selections return the char range; line selections return whole
  ## lines; block selections return a line for each of the block's, blanks
  ## standing for the cells of a character the block's edge cuts through or a
  ## line too short to reach its end. Returns "" when inactive.
  if not selection.active:
    return ""
  case selection.kind
  of vskBlock:
    buffer.blockText(buffer.blockArea(selection, tabStop), tabStop)
  of vskLine:
    getLineText(buffer, selection)
  of vskChar:
    let (selStart, selEnd) = selection.getSelectionRange()
    buffer.getTextInRange(selStart, selEnd)

proc selectedRegister*(
    buffer: TextBuffer, selection: VisualSelection, tabStop: int
): Register =
  ## What a yank of the active `selection` keeps: its text, as a block when
  ## it is one (Vim's MBLOCK).
  case selection.kind
  of vskBlock:
    buffer.takenBlock(buffer.blockArea(selection, tabStop), tabStop)
  of vskLine:
    toRegister(getLineText(buffer, selection), true)
  of vskChar:
    toRegister(getVisualSelectionText(buffer, selection, tabStop), false)

proc visualYank*(buffer: TextBuffer, state: EditorState, register = none(char)) =
  ## Yank (copy) visual selection to `register` (else the yank register) and
  ## return to previous mode
  let sel = state.operandSelection(buffer)
  if sel.active:
    state.registers.storeYanked(register, buffer.selectedRegister(sel, state.tabStop))
    # Vim puts the cursor on the start of what it took: a block's top left.
    state.cursor =
      if sel.kind == vskBlock:
        buffer.blockArea(sel, state.tabStop, measureWidest = false).topLeft
      else:
        sel.getSelectionRange()[0]
    # Clamp column to valid range for Normal mode (last char, not past end)
    let lineLen = buffer.getLine(state.cursor.line).charLen
    if lineLen > 0:
      state.cursor.column = min(state.cursor.column, lineLen - 1)
    else:
      state.cursor.column = 0

    state.statusMessage = ""
    state.leaveVisual()

proc operandArea*(
    buffer: TextBuffer, state: EditorState
): tuple[sel: VisualSelection, area: BlockArea] =
  ## The selection an operator acts on, and its block when blockwise.
  result.sel = state.operandSelection(buffer)
  if result.sel.kind == vskBlock:
    result.area = buffer.blockArea(result.sel, state.tabStop)

proc undoCursor(sel: VisualSelection, area: BlockArea): BufferPosition =
  ## Where undo puts the cursor back after an operator over `sel`, as Vim's: the
  ## top left of the selection, the first column of a linewise one.
  case sel.kind
  of vskBlock:
    area.topLeft
  of vskLine:
    BufferPosition(line: min(sel.start.line, sel.current.line), column: 0)
  of vskChar:
    sel.getSelectionRange()[0]

proc keepsRegisters(taken: Register, change = false): bool =
  ## A Visual delete or change that took `taken` leaves the registers as they
  ## were, as Vim's op_delete does over an empty region (`v` on the empty last
  ## line, oap->empty) and for a delete, not a change, within one empty line
  ## (`<C-v>d`; `<C-v>c` writes them).
  taken.holdsNoText and (not change or taken.kind == rkChars)

proc deleteBlockSelection(
    buffer: TextBuffer, state: EditorState, area: BlockArea, yanked: var Register
): Result[(), string] =
  ## Delete the block `area`; caller stores `yanked` after commit. As
  ## Vim's op_delete, a character the block's edge cuts through goes whole and
  ## leaves blanks for its cells outside the block, and the cursor goes where
  ## the block started on the first line.
  let tabStop = state.tabStop
  yanked = buffer.takenBlock(area, tabStop)

  let first = area.blockLine(buffer.getLine(area.firstLine), tabStop, buDelete)
  let deleted = buffer.rewriteTaken(
    area,
    tabStop,
    buDelete,
    proc(cut: BlockLine, taken: string): string =
      ' '.repeat(cut.startSpaces + cut.endSpaces),
  )
  if deleted.isErr:
    return deleted

  state.cursor = area.topLeft
  if first.textLen > 0:
    state.cursor.column = first.textCol + first.startSpaces
  clampCursorToLastChar(state.cursor, buffer.getLine(area.firstLine).charLen)
  ok(())

proc deleteLineSelection(
    buffer: TextBuffer, state: EditorState, sel: VisualSelection, yanked: var Register
): Result[(), string] =
  ## Delete line-wise selection; caller stores `yanked` after commit.
  let
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)

  # Get text to yank first
  yanked = toRegister(getLineText(buffer, sel), true)

  if startLine == 0 and endLine >= buffer.len - 1:
    let delResult = buffer.deleteAllLines()
    if delResult.isErr:
      return err(delResult.error)
  else:
    # Delete lines from end to start to preserve line numbers.
    for lineNum in countdown(endLine, startLine):
      let delResult = buffer.deleteLine(lineNum)
      if delResult.isErr:
        return err(delResult.error)

  # Vim lands on the first non-blank of the line that takes the deleted
  # range's place, the new last line when it ran to the end of the buffer.
  # Leaving Visual mode then drops the old curswant, as Vim does here.
  let newLine = max(0, min(startLine, buffer.len - 1))
  state.cursor =
    BufferPosition(line: newLine, column: firstNonBlankColumn(buffer.getLine(newLine)))

  return ok(())

template failedVisualEdit(state: EditorState, txr: Result[(), string]) =
  ## After a Visual operator's transaction: on a failure surface the error,
  ## leave Visual mode and return it from the enclosing proc.
  if txr.isErr:
    if state.statusMessage.len == 0:
      state.statusMessage = txr.error
    state.leaveVisual()
    return err(txr.error)

proc visualDelete*(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    area: BlockArea,
    register = none(char),
): Result[(), string] =
  ## Delete `sel`, the cells of `area` when blockwise, into `register` (else
  ## the delete registers) and return to previous mode
  if not sel.active:
    return ok(())
  var deleted: Register

  let txr = withTransaction(buffer, "Visual delete", some(undoCursor(sel, area))):
    case sel.kind
    of vskBlock:
      checkVisualEdit(state, deleteBlockSelection(buffer, state, area, deleted))
    of vskLine:
      checkVisualEdit(state, deleteLineSelection(buffer, state, sel, deleted))
    of vskChar:
      let (selStart, selEnd) = sel.getSelectionRange()

      deleted = toRegister(buffer.getTextInRange(selStart, selEnd), false)

      checkVisualEdit(state, buffer.deleteRange(selStart, selEnd))
      state.cursor = selStart
  failedVisualEdit(state, txr)

  # Registers are outside the buffer transaction, so store after commit.
  if not deleted.keepsRegisters:
    state.registers.storeDeleted(register, deleted)

  # Clamp cursor to valid position after deletion
  if state.cursor.line >= buffer.len:
    state.cursor.line = max(0, buffer.len - 1)
  if buffer.len > 0:
    let line = buffer.getLine(state.cursor.line)
    if line.charLen > 0:
      state.cursor.column = min(state.cursor.column, line.charLen - 1)
    else:
      state.cursor.column = 0

  state.statusMessage = ""
  state.leaveVisual()
  ok(())

proc shiftLines(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    area: BlockArea,
    label: string,
    shift: proc(buffer: TextBuffer, state: EditorState, count: int): Result[(), string],
    count: int,
): Result[(), string] =
  ## Shift the lines of `sel` by `count` with `shift`, which reads the line to
  ## act on from the cursor, and return to previous mode. The cursor goes to
  ## the first line's first non-blank, as Vim's op_shift.
  if not sel.active:
    return ok(())
  let
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)
    cursorBefore = state.cursor

  let txr = withTransaction(buffer, label, some(undoCursor(sel, area))):
    for lineNum in startLine .. endLine:
      state.cursor = BufferPosition(line: lineNum, column: 0)
      checkVisualEditAt(state, cursorBefore, shift(buffer, state, count))

    state.cursor = BufferPosition(
      line: startLine, column: firstNonBlankColumn(buffer.getLine(startLine))
    )
  failedVisualEdit(state, txr)

  state.statusMessage = ""
  state.leaveVisual()
  ok(())

proc visualIndent*(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    area: BlockArea,
    count: int = 1,
): Result[(), string] =
  ## Indent the lines of `sel`, whose block is `area` when blockwise, and
  ## return to previous mode
  shiftLines(buffer, state, sel, area, "Visual indent", indentLine, count)

proc visualDedent*(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    area: BlockArea,
    count: int = 1,
): Result[(), string] =
  ## Dedent the lines of `sel`, whose block is `area` when blockwise, and
  ## return to previous mode
  shiftLines(buffer, state, sel, area, "Visual dedent", dedentLine, count)

proc applyVisualTextTransform(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    area: BlockArea,
    label: string,
    action: string,
    transform: proc(text: string): string {.closure, gcsafe.},
    blockFill = "",
): Result[(), string] =
  ## Apply transform to selection; refused for raw buffers. A block's lines
  ## get `transform` of the characters wholly inside it, or with `blockFill`
  ## their cells filled with it, as `r` does.
  if not sel.active:
    return ok(())

  let (selStart, selEnd) = sel.getSelectionRange()

  let txr = withTransaction(buffer, label, some(undoCursor(sel, area))):
    case sel.kind
    of vskBlock:
      if not buffer.allowsTextTransforms:
        checkVisualEdit(state, Result[(), string].err(rawBytesRejection(action)))
      checkVisualEdit(
        state,
        if blockFill.len > 0:
          buffer.replaceBlock(area, state.tabStop, blockFill)
        else:
          buffer.rewriteTaken(
            area,
            state.tabStop,
            buTake,
            proc(cut: BlockLine, taken: string): string =
              transform(taken),
          ),
      )
      # Vim leaves the cursor on the block's top left.
      state.cursor = area.topLeft
      clampCursorToLastChar(state.cursor, buffer.getLine(area.firstLine).charLen)
    of vskLine:
      let
        startLine = min(sel.start.line, sel.current.line)
        endLine = max(sel.start.line, sel.current.line)

      checkVisualEdit(
        state, buffer.replaceWholeLines(startLine, endLine, action, transform)
      )
    of vskChar:
      checkVisualEdit(state, buffer.transformRange(selStart, selEnd, action, transform))

    if sel.kind != vskBlock:
      state.cursor = selStart
  failedVisualEdit(state, txr)

  state.statusMessage = ""
  state.leaveVisual()
  ok(())

proc visualLowercase*(
    buffer: TextBuffer, state: EditorState, sel: VisualSelection, area: BlockArea
): Result[(), string] =
  ## Convert `sel` to lowercase and return to previous mode
  applyVisualTextTransform(
    buffer, state, sel, area, "Visual lowercase", "lowercase", toLowerAscii
  )

proc visualUppercase*(
    buffer: TextBuffer, state: EditorState, sel: VisualSelection, area: BlockArea
): Result[(), string] =
  ## Convert `sel` to uppercase and return to previous mode
  applyVisualTextTransform(
    buffer, state, sel, area, "Visual uppercase", "uppercase", toUpperAscii
  )

proc visualToggleCase*(
    buffer: TextBuffer, state: EditorState, sel: VisualSelection, area: BlockArea
): Result[(), string] =
  ## Toggle the case of `sel` and return to previous mode
  applyVisualTextTransform(
    buffer, state, sel, area, "Visual toggle case", "toggle case", toggleAsciiCase
  )

proc visualReplace*(buffer: TextBuffer, state: EditorState, ch: string) =
  ## Replace selection with `ch` (one char). Refused for raw buffers.
  # Registry validates `ch`; this guard is for direct callers.
  if ch.charLen != 1:
    return

  # One `ch` per character; preserve newlines for multi-line selections.
  let fill = proc(text: string): string =
    var first = true
    for segment in text.split('\n'):
      if not first:
        result.add('\n')
      first = false
      result.add(ch.repeat(segment.charLen))

  let (sel, area) = buffer.operandArea(state)
  discard applyVisualTextTransform(
    buffer, state, sel, area, "Visual replace", "replace", fill, blockFill = ch
  )

proc visualJoinLines*(
    buffer: TextBuffer, state: EditorState, sel: VisualSelection, area: BlockArea
): Result[(), string] =
  ## Join the lines of `sel`, whose block is `area` when blockwise, into one
  ## line (J command), and the next line with a single one, as Vim's.
  if not sel.active:
    return ok(())
  let
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)
    joinCount = max(1, endLine - startLine)

  # Use buffer's joinLines which handles the transaction
  result = buffer.joinLines(startLine, joinCount, some(undoCursor(sel, area)))
  if result.isErr:
    state.statusMessage = result.error
    state.cursor = undoCursor(sel, area)
  else:
    state.statusMessage = "Joined " & $(joinCount + 1) & " line(s)"
    state.cursor = BufferPosition(line: startLine, column: 0)

  state.leaveVisual()

proc visualAddToNumbers*(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    area: BlockArea,
    delta: int,
    progressive = false,
): Result[(), string] =
  ## Add `delta` to the first number on each line of `sel`, among the
  ## characters wholly inside `area` when blockwise, and leave Visual with the
  ## cursor at the start of `sel`, as Vim's v_CTRL-A. `progressive` adds
  ## `delta` more on each further line with a number (v_g_CTRL-A).
  if not sel.active:
    return ok(())
  let (selStart, selEnd) = sel.getSelectionRange()
  var amount = delta

  let txr = withTransaction(buffer, "Visual increment", some(undoCursor(sel, area))):
    for lineNum in selStart.line .. selEnd.line:
      let
        line = buffer.getLine(lineNum)
        (first, stop) =
          case sel.kind
          of vskLine:
            (0, line.len)
          of vskBlock:
            let cut = area.blockLine(line, state.tabStop, buTake)
            (
              charToBytePos(line, cut.textCol),
              charToBytePos(line, cut.textCol + cut.textLen),
            )
          of vskChar:
            (
              (
                if lineNum == selStart.line: charToBytePos(line, selStart.column)
                else: 0
              ),
              (
                if lineNum == selEnd.line: charToBytePos(line, selEnd.column + 1)
                else: line.len
              ),
            )
        change = addToNumber(line, first, stop, amount)
      if change.isSome:
        if change.get.line != line:
          checkVisualEdit(state, buffer.replaceLine(lineNum, change.get.line))
        if progressive:
          amount += delta

    state.cursor = undoCursor(sel, area)
    clampCursorToLastChar(state.cursor, buffer.getLine(state.cursor.line).charLen)
  failedVisualEdit(state, txr)

  state.statusMessage = ""
  state.leaveVisual()
  ok(())

proc runVisualOperator*(
    buffer: TextBuffer,
    state: EditorState,
    op: VisualOperator,
    sel: VisualSelection,
    area: BlockArea,
    count = 1,
    register = none(char),
): Result[(), string] =
  ## Act with `op` over `sel`, the cells of `area` when blockwise.
  case op
  of voDelete:
    visualDelete(buffer, state, sel, area, register)
  of voIndent:
    visualIndent(buffer, state, sel, area, count)
  of voDedent:
    visualDedent(buffer, state, sel, area, count)
  of voLowerCase:
    visualLowercase(buffer, state, sel, area)
  of voUpperCase:
    visualUppercase(buffer, state, sel, area)
  of voToggleCase:
    visualToggleCase(buffer, state, sel, area)
  of voJoin:
    visualJoinLines(buffer, state, sel, area)
  of voIncrement:
    visualAddToNumbers(buffer, state, sel, area, count)
  of voDecrement:
    visualAddToNumbers(buffer, state, sel, area, -count)
  of voIncrementProgressive:
    visualAddToNumbers(buffer, state, sel, area, count, progressive = true)
  of voDecrementProgressive:
    visualAddToNumbers(buffer, state, sel, area, -count, progressive = true)

proc visualToInsertMode*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual mode to insert mode (I command)
  ## For block mode: moves cursor to (startLine, startCol) and sets up
  ## VisualBlockInsertContext for text replication across all selected lines.
  ## For other modes: moves cursor to (startLine, 0).
  let sel = state.operandSelection(buffer)

  if sel.active:
    if sel.kind == vskBlock:
      let area = buffer.blockArea(sel, state.tabStop)
      state.cursor = area.topLeft
      state.editState.visualBlockInsertContext = some(
        VisualBlockInsertContext(
          kind: vbiInsert,
          area: area,
          insertColumn: area.topLeft.column,
          firstLineLen: buffer.getLine(area.firstLine).charLen,
        )
      )
    else:
      state.cursor.line = min(sel.start.line, sel.current.line)
      state.cursor.column = 0

  # Save current mode for returning with ESC
  state.previousMode = state.mode

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc visualBlockAppend*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual block mode to insert mode right of the block (A
  ## command), or at the first line's end after `<C-v>$`, and set up
  ## VisualBlockInsertContext for text replication across all selected lines.
  ## As Vim's op_insert, a first line too short to reach the block's end is
  ## padded out to it first.
  ## A selection a closed fold turned line-shaped has no block columns to
  ## replicate into, so it appends at the end of the last selected line.
  let sel = state.operandSelection(buffer)
  if not sel.active:
    return

  if sel.kind != vskBlock:
    let endLine = max(sel.start.line, sel.current.line)
    state.cursor.line = endLine
    state.cursor.column = buffer.getLine(endLine).charLen
    state.previousMode = state.mode
    state.mode = EditorMode.Insert
    return

  let
    area = buffer.blockArea(sel, state.tabStop)
    first = buffer.getLine(area.firstLine)
    cut = area.blockLine(first, state.tabStop, buAppend)
  let appendAt = BufferPosition(
    line: area.firstLine,
    column: max(area.topLeft.column, min(first.charLen, cut.textCol + cut.textLen)),
  )
  var typingAt = appendAt
  if cut.isShort and not area.toLineEnd and cut.endSpaces > 0:
    # The padding goes back with what Insert types. It rewrites the line rather
    # than inserting, so the change list takes where typing starts.
    typingAt.column += cut.endSpaces
    let txr = withTransactionForInsert(buffer, "Visual block append", appendAt):
      checkVisualEdit(
        state,
        buffer.replaceLines(
          area.firstLine,
          1,
          [first & ' '.repeat(cut.endSpaces)],
          column = typingAt.column,
        ),
      )
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return
  state.cursor = typingAt

  state.editState.visualBlockInsertContext = some(
    VisualBlockInsertContext(
      kind: vbiAppend,
      area: area,
      insertColumn: state.cursor.column,
      firstLineLen: buffer.getLine(area.firstLine).charLen,
    )
  )

  # Save current mode for returning with ESC
  state.previousMode = state.mode

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc visualChange*(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    area: BlockArea,
    register = none(char),
) =
  ## Delete `sel`, the cells of `area` when blockwise, into `register` (else
  ## the delete registers) and enter insert mode (c command). The transaction
  ## stays open for what Insert types, so one undo takes back both.
  if sel.active:
    var deleted: Register

    let
      startLine = min(sel.start.line, sel.current.line)
      endLine = max(sel.start.line, sel.current.line)

    let undoAt = undoCursor(sel, area)
    let txr = withTransactionForInsert(buffer, "Visual change", undoAt):
      case sel.kind
      of vskBlock:
        checkVisualEdit(state, deleteBlockSelection(buffer, state, area, deleted))
        # Typing starts where the block was, past the last character when the
        # block reached the line's end, as Vim's op_change.
        let lineLen = buffer.getLine(startLine).charLen
        if area.topLeft.column > state.cursor.column and lineLen > 0:
          state.cursor.column.inc
        state.editState.visualBlockInsertContext = some(
          VisualBlockInsertContext(
            kind: vbiChange,
            area: area,
            insertColumn: state.cursor.column,
            firstLineLen: lineLen,
          )
        )
      of vskLine:
        deleted = toRegister(getLineText(buffer, sel), true)

        checkVisualEdit(state, buffer.emptyLinesForChange(state, startLine, endLine))
      of vskChar:
        let selEnd = sel.getSelectionRange()[1]
        deleted = toRegister(buffer.getTextInRange(undoAt, selEnd), false)

        checkVisualEdit(state, buffer.deleteRange(undoAt, selEnd))

        state.cursor = undoAt
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    # Registers are outside the buffer transaction, so store after the delete.
    if not deleted.keepsRegisters(change = true):
      state.registers.storeDeleted(register, deleted)

    state.previousMode = EditorMode.Normal # c always returns to Normal on ESC
    state.mode = EditorMode.Insert

proc visualChange*(buffer: TextBuffer, state: EditorState, register = none(char)) =
  ## Change the Visual selection (c command).
  let (sel, area) = buffer.operandArea(state)
  visualChange(buffer, state, sel, area, register)

proc visualSwapSelection*(buffer: TextBuffer, state: EditorState) =
  ## Swap the cursor between the start and end of the selection (o command).
  ## Vertical moves then aim for the cursor's new column, even when it did not
  ## move, as Vim's v_swap_corners sets w_set_curswant.
  let sel = state.activeWindow.visualSelection
  if sel.active:
    state.selectVisualRange(anchor = sel.current, focus = sel.start)

proc reselectVisual*(
    buffer: TextBuffer, state: EditorState
): Result[EditorMode, string] =
  ## `gv`: select the buffer's last Visual area again, in the mode it had and
  ## with the column vertical moves aimed for, and return that mode. From
  ## Visual mode the current and last areas swap.
  if buffer.lastVisual.isNone or buffer.lastVisual.get.start.line >= buffer.len:
    return Result[EditorMode, string].err "No previous visual selection"

  let area = buffer.lastVisual.get
  if state.mode.isVisualAllMode:
    state.activeWindow.saveLastVisual()

  proc clamped(pos: BufferPosition): BufferPosition =
    # Visual mode lets the column rest one past the end of the line.
    let line = min(pos.line, buffer.len - 1)
    BufferPosition(line: line, column: min(pos.column, buffer.getLine(line).charLen))

  state.enterVisual(area.kind, clamped(area.start), clamped(area.cursor))
  state.preferredColumn = area.wantedColumn
  Result[EditorMode, string].ok area.kind.visualMode

proc visualPaste*(
    buffer: TextBuffer,
    state: EditorState,
    clipboardConfig: ClipboardConfig = ClipboardConfig(enable: false, tool: cbtXclip),
    cursorAfter: bool = false,
    register = none(char),
    keepRegisters = false,
    before = false,
    count = 1,
): Result[(), string] =
  ## Vim's v_p: delete the selection, then put the content `register` (else
  ## the unnamed one) held before it `count` times where the selection was.
  ## The deleted text goes to the registers as a delete's does, unless
  ## `keepRegisters` (`P`). `cursorAfter` is `gp`/`gP`, and `before` (`P`,
  ## `gP`) puts lines above a block rather than below it. The next `gv`
  ## selects the put text, or where it would have gone.
  let sel = state.operandSelection(buffer)
  result = Result[(), string].ok ()
  if not sel.active:
    return
  let regName = register.get('"')
  let source = buffer.putSource(state.registers, regName, clipboardConfig).valueOr:
    state.leaveVisual()
    return Result[(), string].err(error)
  let
    # Like Vim, the selection goes even when there is nothing to put. The
    # black hole register puts an empty string, which over whole lines is a
    # blank line.
    putsNothing = source.isEmpty and not regName.isBlackHoleRegisterName
    cursorBeforePaste = state.cursor
    wantedColumn = state.preferredColumn
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)
    cells =
      if sel.kind == vskBlock:
        buffer.blockArea(sel, state.tabStop)
      else:
        BlockArea()
    # Deleting every line leaves one empty line, which goes after the put.
    emptied = sel.kind == vskLine and startLine == 0 and endLine >= buffer.len - 1

  var
    deleted: Register
    area = PutArea()

  template failPaste(error: string) =
    ## Leave Visual mode with the cursor where it was, as a rollback leaves
    ## the buffer, and return `error`.
    state.cursor = cursorBeforePaste
    state.leaveVisual()
    return Result[(), string].err(error)

  template checkPasteErr(r: Result[(), string]) =
    let checkPasteErrResult = r
    if checkPasteErrResult.isErr:
      failPaste(checkPasteErrResult.error)

  # Undo puts the cursor back where Vim's delete starts: over lines, at the
  # cursor when it is above where Visual started, else at the start of the
  # line it started on.
  let undoAt =
    case sel.kind
    of vskChar:
      sel.getSelectionRange()[0]
    of vskLine:
      if sel.current < sel.start:
        sel.current
      else:
        BufferPosition(line: sel.start.line, column: 0)
    of vskBlock:
      cells.topLeft
  let txr = withTransaction(buffer, "Visual paste", some(undoAt)):
    var
      flags: set[PutFlag]
      forward = false
      blockEnd = -1
    if cursorAfter:
      flags.incl pfCursorEnd
    # As Vim, the put goes after the cursor when the delete left it before
    # where the selection started: at the end of the line, or of the buffer.
    case sel.kind
    of vskBlock:
      checkPasteErr(deleteBlockSelection(buffer, state, cells, deleted))
      forward = state.cursor.column < cells.topLeft.column
      blockEnd = endLine
      if source.kind == rkLines and not before:
        # Lines go below the line the cursor ended on (Vim's b_visual.vi_end),
        # which can be the top one.
        state.cursor = BufferPosition(line: sel.current.line, column: 0)
        forward = true
    of vskLine:
      checkPasteErr(deleteLineSelection(buffer, state, sel, deleted))
      forward = state.cursor.line < startLine
      flags.incl pfLines
    of vskChar:
      let (selStart, selEnd) = sel.getSelectionRange()
      deleted = toRegister(buffer.getTextInRange(selStart, selEnd), false)
      checkPasteErr(buffer.deleteRange(selStart, selEnd))
      state.cursor = selStart
      clampCursorToLastChar(state.cursor, buffer.getLine(selStart.line).charLen)
      forward = state.cursor.column < selStart.column
      flags.incl pfSplitLine

    if putsNothing:
      area = PutArea(first: state.cursor, last: state.cursor)
    else:
      # Vim leaves folding off for the put, as the delete may have opened one.
      area = buffer.putText(
        state,
        source,
        forward,
        count,
        flags,
        blockEnd,
        blockAnchor = sel.start,
        byFolds = false,
      ).valueOr:
        failPaste(error)
      if emptied and buffer.len > 1 and buffer.getLine(buffer.len - 1).len == 0:
        checkPasteErr(buffer.deleteLine(buffer.len - 1))
        if state.cursor.line >= buffer.len:
          let last = buffer.len - 1
          state.cursor =
            BufferPosition(line: last, column: max(0, buffer.getLine(last).charLen - 1))
  if txr.isErr:
    failPaste(txr.error)

  # Registers are not covered by the buffer transaction, so write the
  # replaced text only after the transaction committed.
  if not keepRegisters and not deleted.keepsRegisters:
    state.registers.storeDeleted(none(char), deleted)

  state.statusMessage = ""
  # Ctrl-o `p` leaves the cursor past the text for Insert to resume there.
  let cursor = state.cursor
  state.leaveVisual()
  state.cursor = cursor
  buffer.lastVisual = some(
    VisualArea(
      start: area.first, cursor: area.last, kind: sel.kind, wantedColumn: wantedColumn
    )
  )
  if putsNothing:
    result = Result[(), string].err(nothingInRegister(regName))

const SurroundPairs = [
  ("(", ")"),
  ("[", "]"),
  ("{", "}"),
  ("<", ">"),
  ("「", "」"),
  ("『", "』"),
  ("（", "）"),
  ("［", "］"),
  ("｛", "｝"),
  ("〈", "〉"),
  ("《", "》"),
  ("【", "】"),
  ("〔", "〕"),
  ("“", "”"),
  ("‘", "’"),
] ## Paired brackets with distinct open/close; either side selects the pair.

proc getSurroundPair(ch: string): tuple[open, close: string] =
  ## Get the open/close pair for a surround character.
  for pair in SurroundPairs:
    if ch == pair[0] or ch == pair[1]:
      return pair
  # Quotes and other characters: same for open and close
  return (ch, ch)

proc visualSurround*(buffer: TextBuffer, state: EditorState, ch: string) =
  ## Surround selection with `ch`'s pair; multi-byte brackets stay intact.
  let sel = state.operandSelection(buffer)
  # Registry validates `ch`; this guard is for direct callers (see visualReplace).
  if ch.charLen != 1:
    return

  if sel.active:
    let (openChar, closeChar) = getSurroundPair(ch)
    let (selStart, selEnd) = sel.getSelectionRange()

    let txr = withTransaction(buffer, "Visual surround"):
      case sel.kind
      of vskChar:
        let afterEnd = BufferPosition(line: selEnd.line, column: selEnd.column + 1)
        checkVisualEdit(state, buffer.insertText(afterEnd, closeChar))
        checkVisualEdit(state, buffer.insertText(selStart, openChar))
      of vskLine:
        let
          startLine = min(sel.start.line, sel.current.line)
          endLine = max(sel.start.line, sel.current.line)
        for lineNum in countdown(endLine, startLine):
          let lineLen = buffer.getLine(lineNum).charLen
          let lineEnd = BufferPosition(line: lineNum, column: lineLen)
          checkVisualEdit(state, buffer.insertText(lineEnd, closeChar))
          let lineStart = BufferPosition(line: lineNum, column: 0)
          checkVisualEdit(state, buffer.insertText(lineStart, openChar))
      of vskBlock:
        let area = buffer.blockArea(sel, state.tabStop)
        checkVisualEdit(
          state,
          buffer.rewriteTaken(
            area,
            state.tabStop,
            buTake,
            proc(cut: BlockLine, taken: string): string =
              openChar & taken & closeChar,
          ),
        )
        state.cursor = area.topLeft
        clampCursorToLastChar(state.cursor, buffer.getLine(area.firstLine).charLen)

      if sel.kind != vskBlock:
        state.cursor = selStart
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    state.statusMessage = ""
    state.leaveVisual()
