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
  ../[cursor_util, types, registers, modes, config, unicode_utils, visual_selection]
import ../buffer/[core, edit, undo]
import insert_commands, put_text

template checkVisualEdit(state: EditorState, r: Result[(), string]) =
  ## For use inside a withTransaction body of a Visual command: on an edit
  ## failure surface the error, leave Visual mode and return from the enclosing
  ## proc. The return makes withTransaction roll back, so no partially applied
  ## edit is committed.
  let checkVisualEditResult = r
  if checkVisualEditResult.isErr:
    state.statusMessage = checkVisualEditResult.error
    state.leaveVisual()
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

proc getBlockText(buffer: TextBuffer, selection: VisualSelection): string =
  ## Get text from a block (rectangular) selection
  let
    startLine = min(selection.start.line, selection.current.line)
    endLine = max(selection.start.line, selection.current.line)
    (startCol, endCol) = selection.blockColumns

  var lines: seq[string]
  for lineNum in startLine .. endLine:
    let line = buffer.getLine(lineNum)
    let lineLen = line.charLen
    if startCol >= lineLen:
      # Line is shorter than start column, add empty string
      lines.add("")
    elif endCol >= lineLen:
      # Line is shorter than end column, take from start to end of line
      lines.add(line.charSubStr(startCol))
    else:
      # Normal case
      lines.add(line.charSubStr(startCol, endCol - startCol + 1))
  result = lines.join("\n")

proc getLineText(buffer: TextBuffer, selection: VisualSelection): string =
  ## Get text from a line-wise selection (entire lines)
  buffer.linewiseText(
    min(selection.start.line, selection.current.line),
    max(selection.start.line, selection.current.line),
  )

proc getVisualSelectionText*(buffer: TextBuffer, selection: VisualSelection): string =
  ## Get the selected text respecting the selection kind.
  ## Char selections return the char range; line selections return whole
  ## lines; block selections return the rectangle. Returns "" when inactive.
  if not selection.active:
    return ""
  case selection.kind
  of vskBlock:
    getBlockText(buffer, selection)
  of vskLine:
    getLineText(buffer, selection)
  of vskChar:
    let (selStart, selEnd) = selection.getSelectionRange()
    buffer.getTextInRange(selStart, selEnd)

proc visualYank*(buffer: TextBuffer, state: EditorState, register = none(char)) =
  ## Yank (copy) visual selection to `register` (else the yank register) and
  ## return to previous mode
  let sel = state.operandSelection(buffer)
  if sel.active:
    # Get normalized selection range
    let (selStart, _) = sel.getSelectionRange()

    let selectedText = getVisualSelectionText(buffer, sel)

    let isLine = sel.kind == vskLine

    state.registers.storeYanked(register, selectedText, isLine)

    # Move cursor to start of selection (Vim behavior)
    state.cursor = selStart
    # Clamp column to valid range for Normal mode (last char, not past end)
    let lineLen = buffer.getLine(state.cursor.line).charLen
    if lineLen > 0:
      state.cursor.column = min(state.cursor.column, lineLen - 1)
    else:
      state.cursor.column = 0

    state.statusMessage = ""
    state.leaveVisual()

proc deleteBlockSelection(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    deletedText: var string,
): Result[(), string] =
  ## Delete block selection; caller stores deletedText after commit.
  let
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)
    (startCol, endCol) = sel.blockColumns

  # Get text to yank first
  deletedText = getBlockText(buffer, sel)

  # Delete from each line in reverse order to preserve line numbers
  for lineNum in countdown(endLine, startLine):
    let line = buffer.getLine(lineNum)
    let lineLen = line.charLen
    if startCol < lineLen:
      let actualEndCol = min(endCol, lineLen - 1)
      let startPos = BufferPosition(line: lineNum, column: startCol)
      let endPos = BufferPosition(line: lineNum, column: actualEndCol)
      let delResult = buffer.deleteRange(startPos, endPos)
      if delResult.isErr:
        return err(delResult.error)

  # Move cursor to start of deleted block, clamped to valid position
  state.cursor.line = startLine
  if buffer.len > 0:
    let line = buffer.getLine(startLine)
    if line.charLen > 0:
      state.cursor.column = min(startCol, line.charLen - 1)
    else:
      state.cursor.column = 0
  else:
    state.cursor.column = 0

  return ok(())

proc deleteLineSelection(
    buffer: TextBuffer,
    state: EditorState,
    sel: VisualSelection,
    deletedText: var string,
): Result[(), string] =
  ## Delete line-wise selection; caller stores deletedText after commit.
  let
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)

  # Get text to yank first
  deletedText = getLineText(buffer, sel)

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

proc visualDelete*(
    buffer: TextBuffer, state: EditorState, sel: VisualSelection, register = none(char)
) =
  ## Delete `sel` into `register` (else the delete registers) and return to
  ## previous mode
  if sel.active:
    var deletedText = ""
    var deletedIsLine = false

    let txr = withTransaction(buffer, "Visual delete"):
      case sel.kind
      of vskBlock:
        checkVisualEdit(state, deleteBlockSelection(buffer, state, sel, deletedText))
      of vskLine:
        checkVisualEdit(state, deleteLineSelection(buffer, state, sel, deletedText))
        deletedIsLine = true
      of vskChar:
        let (selStart, selEnd) = sel.getSelectionRange()

        deletedText = buffer.getTextInRange(selStart, selEnd)

        checkVisualEdit(state, buffer.deleteRange(selStart, selEnd))
        state.cursor = selStart
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    # Registers are outside the buffer transaction, so store after commit.
    state.registers.storeDeleted(register, deletedText, deletedIsLine)

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

proc visualDelete*(buffer: TextBuffer, state: EditorState, register = none(char)) =
  ## Delete visual selection and return to previous mode
  visualDelete(buffer, state, state.operandSelection(buffer), register)

proc visualIndent*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Indent all lines in visual selection and return to previous mode
  let sel = state.operandSelection(buffer)
  if sel.active:
    let
      startLine = min(sel.start.line, sel.current.line)
      endLine = max(sel.start.line, sel.current.line)

    # indentLine reads the line to act on from the cursor, so the loop walks it.
    let cursorBefore = state.cursor

    let txr = withTransaction(buffer, "Visual indent"):
      for lineNum in startLine .. endLine:
        state.cursor.line = lineNum
        state.cursor.column = 0
        checkVisualEditAt(state, cursorBefore, indentLine(buffer, state, count))

      state.cursor.line = startLine
      state.cursor.column = 0
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    state.statusMessage = ""
    state.leaveVisual()

proc visualDedent*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Dedent all lines in visual selection and return to previous mode
  let sel = state.operandSelection(buffer)
  if sel.active:
    let
      startLine = min(sel.start.line, sel.current.line)
      endLine = max(sel.start.line, sel.current.line)

    # dedentLine reads the line to act on from the cursor, so the loop walks it.
    let cursorBefore = state.cursor

    let txr = withTransaction(buffer, "Visual dedent"):
      for lineNum in startLine .. endLine:
        state.cursor.line = lineNum
        state.cursor.column = 0
        checkVisualEditAt(state, cursorBefore, dedentLine(buffer, state, count))

      state.cursor.line = startLine
      state.cursor.column = 0
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    state.statusMessage = ""
    state.leaveVisual()

proc applyVisualTextTransform(
    buffer: TextBuffer,
    state: EditorState,
    label: string,
    action: string,
    transform: proc(text: string): string {.closure, gcsafe.},
) =
  ## Apply transform to selection; refused for raw buffers.
  let sel = state.operandSelection(buffer)
  if not sel.active:
    return

  let (selStart, selEnd) = sel.getSelectionRange()

  let txr = withTransaction(buffer, label):
    case sel.kind
    of vskBlock:
      let
        startLine = min(sel.start.line, sel.current.line)
        endLine = max(sel.start.line, sel.current.line)
        (startCol, endCol) = sel.blockColumns

      for lineNum in startLine .. endLine:
        let line = buffer.getLine(lineNum)
        let lineLen = line.charLen
        if startCol < lineLen:
          let actualEndCol = min(endCol, lineLen - 1)
          let startPos = BufferPosition(line: lineNum, column: startCol)
          let endPos = BufferPosition(line: lineNum, column: actualEndCol)
          checkVisualEdit(
            state, buffer.transformRange(startPos, endPos, action, transform)
          )
    of vskLine:
      let
        startLine = min(sel.start.line, sel.current.line)
        endLine = max(sel.start.line, sel.current.line)

      checkVisualEdit(
        state, buffer.replaceWholeLines(startLine, endLine, action, transform)
      )
    of vskChar:
      checkVisualEdit(state, buffer.transformRange(selStart, selEnd, action, transform))

    state.cursor = selStart
  if txr.isErr:
    if state.statusMessage.len == 0:
      state.statusMessage = txr.error
    state.leaveVisual()
    return

  state.statusMessage = ""
  state.leaveVisual()

proc visualLowercase*(buffer: TextBuffer, state: EditorState) =
  ## Convert visual selection to lowercase and return to previous mode
  applyVisualTextTransform(buffer, state, "Visual lowercase", "lowercase", toLowerAscii)

proc visualUppercase*(buffer: TextBuffer, state: EditorState) =
  ## Convert visual selection to uppercase and return to previous mode
  applyVisualTextTransform(buffer, state, "Visual uppercase", "uppercase", toUpperAscii)

proc visualToggleCase*(buffer: TextBuffer, state: EditorState) =
  ## Toggle case of visual selection and return to previous mode
  applyVisualTextTransform(
    buffer, state, "Visual toggle case", "toggle case", toggleAsciiCase
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

  applyVisualTextTransform(buffer, state, "Visual replace", "replace", fill)

proc visualJoinLines*(buffer: TextBuffer, state: EditorState) =
  ## Join all lines in visual selection into one line (J command)
  let sel = state.operandSelection(buffer)
  if sel.active:
    # Get line range
    let
      startLine = min(sel.start.line, sel.current.line)
      endLine = max(sel.start.line, sel.current.line)

    # Need at least 2 lines to join
    if startLine == endLine:
      # Only one line selected, nothing to join
      state.statusMessage = ""
      state.leaveVisual()
      return

    # Calculate number of joins needed (lines - 1)
    let joinCount = endLine - startLine

    # Use buffer's joinLines which handles the transaction
    let result = buffer.joinLines(startLine, joinCount)
    if result.isErr:
      state.statusMessage = result.error
    else:
      state.statusMessage = $joinCount & " lines joined"

    # Move cursor to the start line
    state.cursor.line = startLine
    state.cursor.column = 0

    state.leaveVisual()

proc visualToInsertMode*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual mode to insert mode (I command)
  ## For block mode: moves cursor to (startLine, startCol) and sets up
  ## VisualBlockInsertContext for text replication across all selected lines.
  ## For other modes: moves cursor to (startLine, 0).
  let sel = state.operandSelection(buffer)

  if sel.active:
    let startLine = min(sel.start.line, sel.current.line)

    if sel.kind == vskBlock:
      let startCol = sel.blockColumns.startCol
      let endLine = max(sel.start.line, sel.current.line)
      state.cursor.line = startLine
      state.cursor.column = startCol
      state.editState.visualBlockInsertContext = some(
        VisualBlockInsertContext(
          kind: vbiInsert,
          startLine: startLine,
          endLine: endLine,
          insertColumn: startCol,
          firstLineLen: buffer.getLine(startLine).charLen,
        )
      )
    else:
      state.cursor.line = startLine
      state.cursor.column = 0

  # Save current mode for returning with ESC
  state.previousMode = state.mode

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc visualBlockAppend*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual block mode to insert mode at end of block (A command)
  ## Moves cursor to (startLine, endCol + 1), or to the first line's end after
  ## `<C-v>$`, and sets up VisualBlockInsertContext for text replication across
  ## all selected lines, each at its own end after `<C-v>$`.
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
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)
    firstLineLen = buffer.getLine(startLine).charLen
    insertColumn =
      if sel.extendsToLineEnd:
        firstLineLen
      else:
        sel.blockColumns.endCol + 1

  state.cursor.line = startLine
  state.cursor.column = insertColumn
  state.editState.visualBlockInsertContext = some(
    VisualBlockInsertContext(
      kind: vbiAppend,
      startLine: startLine,
      endLine: endLine,
      insertColumn: insertColumn,
      atLineEnd: sel.extendsToLineEnd,
      firstLineLen: firstLineLen,
    )
  )

  # Save current mode for returning with ESC
  state.previousMode = state.mode

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc visualChange*(buffer: TextBuffer, state: EditorState, register = none(char)) =
  ## Delete visual selection into `register` (else the delete registers) and
  ## enter insert mode (c command). The transaction stays open for what Insert
  ## types, so one undo takes back both.
  let sel = state.operandSelection(buffer)
  if sel.active:
    var deletedText = ""
    var deletedIsLine = false

    let
      startLine = min(sel.start.line, sel.current.line)
      endLine = max(sel.start.line, sel.current.line)

    # As Vim, undo returns to the top left of the selection, the first column
    # of a linewise one.
    let undoCursor =
      case sel.kind
      of vskBlock:
        BufferPosition(line: startLine, column: sel.blockColumns.startCol)
      of vskLine:
        BufferPosition(line: startLine, column: 0)
      of vskChar:
        sel.getSelectionRange()[0]
    let txr = withTransactionForInsert(buffer, "Visual change", undoCursor):
      case sel.kind
      of vskBlock:
        checkVisualEdit(state, deleteBlockSelection(buffer, state, sel, deletedText))
        # Insert may start past the last character, which the delete clamps.
        state.cursor.column = undoCursor.column
        state.editState.visualBlockInsertContext = some(
          VisualBlockInsertContext(
            kind: vbiChange,
            startLine: startLine,
            endLine: endLine,
            insertColumn: undoCursor.column,
            firstLineLen: buffer.getLine(startLine).charLen,
          )
        )
      of vskLine:
        deletedText = getLineText(buffer, sel)
        deletedIsLine = true

        checkVisualEdit(state, buffer.emptyLinesForChange(state, startLine, endLine))
      of vskChar:
        let selEnd = sel.getSelectionRange()[1]
        deletedText = buffer.getTextInRange(undoCursor, selEnd)

        checkVisualEdit(state, buffer.deleteRange(undoCursor, selEnd))

        state.cursor = undoCursor
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    # Registers are outside the buffer transaction, so store after the delete.
    state.registers.storeDeleted(register, deletedText, deletedIsLine)

    state.previousMode = EditorMode.Normal # c always returns to Normal on ESC
    state.mode = EditorMode.Insert

proc visualSwapSelection*(buffer: TextBuffer, state: EditorState) =
  ## Swap the cursor between the start and end of the selection (o command).
  ## Vertical moves then aim for the cursor's new column, even when it did not
  ## move, as Vim's v_swap_corners sets w_set_curswant.
  let sel = state.activeWindow.visualSelection
  if sel.active:
    state.selectVisualRange(anchor = sel.current, focus = sel.start)
    state.preferredColumn = -1

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
    putsNothing = source.isNothing and not regName.isBlackHoleRegisterName
    cursorBeforePaste = state.cursor
    wantedColumn = state.preferredColumn
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)
    # Deleting every line leaves one empty line, which goes after the put.
    emptied = sel.kind == vskLine and startLine == 0 and endLine >= buffer.len - 1

  var
    deletedText = ""
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
  let undoCursor =
    case sel.kind
    of vskChar:
      sel.getSelectionRange()[0]
    of vskLine:
      if sel.current < sel.start:
        sel.current
      else:
        BufferPosition(line: sel.start.line, column: 0)
    of vskBlock:
      BufferPosition(line: startLine, column: sel.blockColumns.startCol)
  let txr = withTransaction(buffer, "Visual paste", some(undoCursor)):
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
      checkPasteErr(deleteBlockSelection(buffer, state, sel, deletedText))
      forward = state.cursor.column < sel.blockColumns.startCol
      blockEnd = endLine
      if source.isLine and not before:
        # Lines go below the line the cursor ended on (Vim's b_visual.vi_end),
        # which can be the top one.
        state.cursor = BufferPosition(line: sel.current.line, column: 0)
        forward = true
    of vskLine:
      checkPasteErr(deleteLineSelection(buffer, state, sel, deletedText))
      forward = state.cursor.line < startLine
      flags.incl pfLines
    of vskChar:
      let (selStart, selEnd) = sel.getSelectionRange()
      deletedText = buffer.getTextInRange(selStart, selEnd)
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
        source.text,
        source.isLine,
        forward,
        count,
        flags,
        blockEnd,
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
  # replaced text only after the transaction committed. Like Vim, deleting
  # nothing (an empty line, the only one) leaves them as they were.
  if not keepRegisters and (deletedText.len > 0 or sel.kind == vskLine):
    state.registers.storeDeleted(none(char), deletedText, sel.kind == vskLine)

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
        let
          startLine = min(sel.start.line, sel.current.line)
          endLine = max(sel.start.line, sel.current.line)
          (startCol, endCol) = sel.blockColumns
        for lineNum in countdown(endLine, startLine):
          let lineLen = buffer.getLine(lineNum).charLen
          if startCol < lineLen:
            let actualEndCol = min(endCol, lineLen - 1)
            let afterEnd = BufferPosition(line: lineNum, column: actualEndCol + 1)
            checkVisualEdit(state, buffer.insertText(afterEnd, closeChar))
            let colStart = BufferPosition(line: lineNum, column: startCol)
            checkVisualEdit(state, buffer.insertText(colStart, openChar))

      state.cursor = selStart
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.leaveVisual()
      return

    state.statusMessage = ""
    state.leaveVisual()
