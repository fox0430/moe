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

import ../[types, registers, motion, modes, config, unicode_utils]
import ../buffer/[core, edit, fold, undo]
import insert_commands

template checkVisualEdit(state: EditorState, r: Result[(), string]) =
  ## For use inside a withTransaction body of a Visual command: on an edit
  ## failure surface the error, leave Visual mode and return from the enclosing
  ## proc. The return makes withTransaction roll back, so no partially applied
  ## edit is committed.
  let checkVisualEditResult = r
  if checkVisualEditResult.isErr:
    state.statusMessage = checkVisualEditResult.error
    state.visualSelection.active = false
    state.mode = state.previousMode
    return

template checkVisualEditAt(
    state: EditorState, cursorBefore: BufferPosition, r: Result[(), string]
) =
  ## `checkVisualEdit` that restores cursor when loop aborts mid-selection.
  let checkVisualEditAtResult = r
  if checkVisualEditAtResult.isErr:
    state.cursor = cursorBefore
  checkVisualEdit(state, checkVisualEditAtResult)

template checkVisualEditErr(state: EditorState, r: Result[(), string]) =
  ## Like `checkVisualEdit` but returns error via Result for caller reporting.
  let checkVisualEditErrResult = r
  if checkVisualEditErrResult.isErr:
    state.visualSelection.active = false
    state.mode = state.previousMode
    return Result[(), string].err(checkVisualEditErrResult.error)

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

proc visualMoveLeft*(buffer: TextBuffer, state: EditorState) =
  ## Move left in visual mode and update selection
  if state.cursor.column > 0:
    state.cursor.column -= 1
    state.visualSelection.current = state.cursor

proc visualMoveRight*(buffer: TextBuffer, state: EditorState) =
  ## Move right in visual mode and update selection
  let lineLen = buffer.getLine(state.cursor.line).charLen
  if state.cursor.column < lineLen:
    state.cursor.column += 1
    state.visualSelection.current = state.cursor

proc visualMoveUp*(buffer: TextBuffer, state: EditorState) =
  ## Move up in visual mode and update selection
  if state.cursor.line > 0:
    var targetLine = state.cursor.line - 1
    # Skip to a collapsed fold's start so the selection crosses the whole fold
    # instead of stalling on a hidden interior line. getPrevVisibleLine always
    # returns a visible line.
    if buffer.foldState.isLineInCollapsedFold(targetLine):
      targetLine = buffer.foldState.getPrevVisibleLine(targetLine)
    state.cursor.line = targetLine
    # Clamp cursor to new line length
    let newLineLen = buffer.getLine(state.cursor.line).charLen
    if state.cursor.column > newLineLen:
      state.cursor.column = newLineLen
    state.visualSelection.current = state.cursor

proc visualMoveDown*(buffer: TextBuffer, state: EditorState) =
  ## Move down in visual mode and update selection
  if state.cursor.line < buffer.len - 1:
    var targetLine = state.cursor.line + 1
    # Skip past a collapsed fold so the selection crosses the whole fold instead
    # of stalling on a hidden interior line.
    if buffer.foldState.isLineInCollapsedFold(targetLine):
      targetLine = buffer.foldState.getNextVisibleLine(targetLine, buffer.len - 1)
    # A collapsed fold that runs to the buffer end can't be crossed; stay put.
    if not buffer.foldState.isLineInCollapsedFold(targetLine):
      state.cursor.line = targetLine
      # Clamp cursor to new line length
      let newLineLen = buffer.getLine(state.cursor.line).charLen
      if state.cursor.column > newLineLen:
        state.cursor.column = newLineLen
      state.visualSelection.current = state.cursor

proc getBlockText(buffer: TextBuffer, selection: VisualSelection): string =
  ## Get text from a block (rectangular) selection
  let
    startLine = min(selection.start.line, selection.current.line)
    endLine = max(selection.start.line, selection.current.line)
    startCol = min(selection.start.column, selection.current.column)
    endCol = max(selection.start.column, selection.current.column)

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
  let
    startLine = min(selection.start.line, selection.current.line)
    endLine = max(selection.start.line, selection.current.line)

  var lines: seq[string]
  for lineNum in startLine .. endLine:
    lines.add($buffer.getLine(lineNum))
  result = lines.join("\n")

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

proc visualYank*(buffer: TextBuffer, state: EditorState) =
  ## Yank (copy) visual selection to the yank register and return to previous mode
  if state.visualSelection.active:
    # Get normalized selection range
    let (selStart, _) = state.visualSelection.getSelectionRange()

    let selectedText = getVisualSelectionText(buffer, state.visualSelection)

    let isLine = state.visualSelection.kind == vskLine

    # Store in register system
    if state.pendingInput.pendingRegister.isSome and
        state.pendingInput.pendingRegister.get != '\0':
      # User specified a register with "
      let regName = state.pendingInput.pendingRegister.get
      if regName.isNamedRegisterName:
        discard state.registers.setNamedRegister(regName, selectedText, isLine)
      elif regName.isClipboardRegisterName:
        state.registers.setClipboardRegister(regName, selectedText, isLine)
      else:
        # For other registers (including "), use yank register
        state.registers.setYankedRegister(selectedText, isLine)
      state.pendingInput.pendingRegister = none(char)
    else:
      # Default: use yank register (0) and unnamed register
      state.registers.setYankedRegister(selectedText, isLine)

    # Move cursor to start of selection (Vim behavior)
    state.cursor = selStart
    # Clamp column to valid range for Normal mode (last char, not past end)
    let lineLen = buffer.getLine(state.cursor.line).charLen
    if lineLen > 0:
      state.cursor.column = min(state.cursor.column, lineLen - 1)
    else:
      state.cursor.column = 0

    # Clear selection and return to previous mode
    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc storeVisualDeletedText(
    state: EditorState, reg: Option[char], text: string, isLine: bool
) =
  ## Store deleted text in register `reg` (captured before edit); call only after commit.
  if reg.isSome and reg.get != '\0':
    let regName = reg.get
    if regName.isNamedRegisterName:
      discard state.registers.setNamedRegister(regName, text, isLine)
    elif regName.isClipboardRegisterName:
      state.registers.setClipboardRegister(regName, text, isLine)
    else:
      state.registers.setDeletedRegister(text, isLine)
  else:
    state.registers.setDeletedRegister(text, isLine)

proc deleteBlockSelection(
    buffer: TextBuffer, state: EditorState, deletedText: var string
): Result[(), string] =
  ## Delete block selection; caller stores deletedText after commit.
  let
    startLine =
      min(state.visualSelection.start.line, state.visualSelection.current.line)
    endLine = max(state.visualSelection.start.line, state.visualSelection.current.line)
    startCol =
      min(state.visualSelection.start.column, state.visualSelection.current.column)
    endCol =
      max(state.visualSelection.start.column, state.visualSelection.current.column)

  # Get text to yank first
  deletedText = getBlockText(buffer, state.visualSelection)

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
    buffer: TextBuffer, state: EditorState, deletedText: var string
): Result[(), string] =
  ## Delete line-wise selection; caller stores deletedText after commit.
  let
    startLine =
      min(state.visualSelection.start.line, state.visualSelection.current.line)
    endLine = max(state.visualSelection.start.line, state.visualSelection.current.line)

  # Get text to yank first
  deletedText = getLineText(buffer, state.visualSelection)

  # Delete lines from end to start to preserve line numbers
  for lineNum in countdown(endLine, startLine):
    let delResult = buffer.deleteLine(lineNum)
    if delResult.isErr:
      return err(delResult.error)

  # If buffer is empty after deletion, add an empty line
  if buffer.len == 0:
    let insResult = buffer.insert(0, "")
    if insResult.isErr:
      return err(insResult.error)

  # Move cursor to start line (or last line if start was beyond buffer)
  let newLine = min(startLine, buffer.len - 1)
  state.cursor = BufferPosition(line: newLine, column: 0)

  return ok(())

proc visualDelete*(buffer: TextBuffer, state: EditorState) =
  ## Delete visual selection and return to previous mode
  if state.visualSelection.active:
    # Capture the pending register before the edit: the store happens only after
    # the transaction commits (registers are outside buffer transactions), and
    # it must be consumed even if the edit fails.
    let pendingReg = state.pendingInput.pendingRegister
    state.pendingInput.pendingRegister = none(char)

    var deletedText = ""
    var deletedIsLine = false

    let txr = withTransaction(buffer, "Visual delete"):
      case state.visualSelection.kind
      of vskBlock:
        checkVisualEdit(state, deleteBlockSelection(buffer, state, deletedText))
      of vskLine:
        checkVisualEdit(state, deleteLineSelection(buffer, state, deletedText))
        deletedIsLine = true
      of vskChar:
        let (selStart, selEnd) = state.visualSelection.getSelectionRange()

        deletedText = buffer.getTextInRange(selStart, selEnd)

        checkVisualEdit(state, buffer.deleteRange(selStart, selEnd))
        state.cursor = selStart
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    # Registers are outside the buffer transaction, so store after commit.
    state.storeVisualDeletedText(pendingReg, deletedText, deletedIsLine)

    # Clamp cursor to valid position after deletion
    if state.cursor.line >= buffer.len:
      state.cursor.line = max(0, buffer.len - 1)
    if buffer.len > 0:
      let line = buffer.getLine(state.cursor.line)
      if line.charLen > 0:
        state.cursor.column = min(state.cursor.column, line.charLen - 1)
      else:
        state.cursor.column = 0

    state.visualSelection.active = false
    state.statusMessage = ""
    # Return to previous mode (before entering Visual mode)
    state.mode = state.previousMode

proc visualIndent*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Indent all lines in visual selection and return to previous mode
  if state.visualSelection.active:
    let
      startLine =
        min(state.visualSelection.start.line, state.visualSelection.current.line)
      endLine =
        max(state.visualSelection.start.line, state.visualSelection.current.line)

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
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc visualDedent*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Dedent all lines in visual selection and return to previous mode
  if state.visualSelection.active:
    let
      startLine =
        min(state.visualSelection.start.line, state.visualSelection.current.line)
      endLine =
        max(state.visualSelection.start.line, state.visualSelection.current.line)

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
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc applyVisualTextTransform(
    buffer: TextBuffer,
    state: EditorState,
    label: string,
    action: string,
    transform: proc(text: string): string {.closure, gcsafe.},
) =
  ## Apply transform to selection; refused for raw buffers.
  if not state.visualSelection.active:
    return

  let (selStart, selEnd) = state.visualSelection.getSelectionRange()

  let txr = withTransaction(buffer, label):
    case state.visualSelection.kind
    of vskBlock:
      let
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)
        startCol =
          min(state.visualSelection.start.column, state.visualSelection.current.column)
        endCol =
          max(state.visualSelection.start.column, state.visualSelection.current.column)

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
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)

      for lineNum in startLine .. endLine:
        let lineCharLen = buffer.getLine(lineNum).charLen
        if lineCharLen > 0:
          let startPos = BufferPosition(line: lineNum, column: 0)
          let endPos = BufferPosition(line: lineNum, column: lineCharLen - 1)
          checkVisualEdit(
            state, buffer.transformRange(startPos, endPos, action, transform)
          )
    of vskChar:
      checkVisualEdit(state, buffer.transformRange(selStart, selEnd, action, transform))

    state.cursor = selStart
  if txr.isErr:
    if state.statusMessage.len == 0:
      state.statusMessage = txr.error
    state.visualSelection.active = false
    state.mode = state.previousMode
    return

  state.visualSelection.active = false
  state.statusMessage = ""
  state.mode = state.previousMode

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
  if state.visualSelection.active:
    # Get line range
    let
      startLine =
        min(state.visualSelection.start.line, state.visualSelection.current.line)
      endLine =
        max(state.visualSelection.start.line, state.visualSelection.current.line)

    # Need at least 2 lines to join
    if startLine == endLine:
      # Only one line selected, nothing to join
      state.visualSelection.active = false
      state.statusMessage = ""
      state.mode = state.previousMode
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

    state.visualSelection.active = false
    state.mode = state.previousMode

# Visual mode movement commands using motion executor

proc visualMoveHome*(buffer: TextBuffer, state: EditorState) =
  ## Move to beginning of line (0/Home) and update selection
  state.cursor.column = 0
  state.visualSelection.current = state.cursor

proc visualMoveEnd*(buffer: TextBuffer, state: EditorState) =
  ## Move to end of line ($) and update selection.
  ## In Visual mode, cursor can be placed one past the last character
  ## (at column == lineLen) so the selection can include the newline
  ## and `d` can delete the entire line.
  let lineLen = buffer.getLine(state.cursor.line).charLen
  state.cursor.column = lineLen
  state.visualSelection.current = state.cursor

proc visualMoveFirstNonBlank*(buffer: TextBuffer, state: EditorState) =
  ## Move to first non-whitespace character (^) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.FirstNonBlank, count: 1)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor

proc visualMoveFirstLine*(buffer: TextBuffer, state: EditorState) =
  ## Move to first line (gg) and update selection
  state.cursor.line = 0
  state.cursor.column = 0
  state.visualSelection.current = state.cursor

proc visualMoveLastLine*(buffer: TextBuffer, state: EditorState, count: int = 0) =
  ## Move to last line (G) or specific line number and update selection
  if count > 0:
    # Go to specific line (1-indexed)
    state.cursor.line = min(count - 1, buffer.len - 1)
  else:
    # Go to last line
    state.cursor.line = max(0, buffer.len - 1)
  state.cursor.column = 0
  state.visualSelection.current = state.cursor

proc visualMoveWord*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Move to next word (w) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.WordForward, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor

proc visualMoveWordBack*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Move to previous word (b) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.WordBackward, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor

proc visualMoveWordEnd*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Move to end of word (e) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.WordEnd, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor

proc visualMoveWordEndBackward*(
    buffer: TextBuffer, state: EditorState, count: int = 1
) =
  ## Move to end of previous word (ge) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.WordEndBackward, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor

proc visualMoveParagraphForward*(
    buffer: TextBuffer, state: EditorState, count: int = 1
) =
  ## Move to next paragraph (}) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.ParagraphForward, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor

proc visualMoveParagraphBackward*(
    buffer: TextBuffer, state: EditorState, count: int = 1
) =
  ## Move to previous paragraph ({) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.ParagraphBackward, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor

proc visualToInsertMode*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual mode to insert mode (I command)
  ## For block mode: moves cursor to (startLine, startCol) and sets up
  ## VisualBlockInsertContext for text replication across all selected lines.
  ## For other modes: moves cursor to (startLine, 0).

  if state.visualSelection.active:
    let startLine =
      min(state.visualSelection.start.line, state.visualSelection.current.line)

    if state.visualSelection.kind == vskBlock:
      let startCol =
        min(state.visualSelection.start.column, state.visualSelection.current.column)
      let endLine =
        max(state.visualSelection.start.line, state.visualSelection.current.line)
      state.cursor.line = startLine
      state.cursor.column = startCol
      state.editState.visualBlockInsertContext = some(
        VisualBlockInsertContext(
          kind: vbiInsert,
          startLine: startLine,
          endLine: endLine,
          insertColumn: startCol,
        )
      )
    else:
      state.cursor.line = startLine
      state.cursor.column = 0

  # Clear visual selection
  state.visualSelection.active = false

  # Save current mode for returning with ESC
  state.previousMode = state.mode

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc visualBlockAppend*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual block mode to insert mode at end of block (A command)
  ## Moves cursor to (startLine, endCol + 1) and sets up
  ## VisualBlockInsertContext for text replication across all selected lines.
  ## A selection a closed fold turned line-shaped has no block columns to
  ## replicate into, so it appends at the end of the last selected line.
  if not state.visualSelection.active:
    return

  if state.visualSelection.kind != vskBlock:
    let endLine =
      max(state.visualSelection.start.line, state.visualSelection.current.line)
    state.cursor.line = endLine
    state.cursor.column = buffer.getLine(endLine).charLen
    state.visualSelection.active = false
    state.previousMode = state.mode
    state.mode = EditorMode.Insert
    return

  let startLine =
    min(state.visualSelection.start.line, state.visualSelection.current.line)
  let endLine =
    max(state.visualSelection.start.line, state.visualSelection.current.line)
  let endCol =
    max(state.visualSelection.start.column, state.visualSelection.current.column)

  state.cursor.line = startLine
  state.cursor.column = endCol + 1
  state.editState.visualBlockInsertContext = some(
    VisualBlockInsertContext(
      kind: vbiAppend, startLine: startLine, endLine: endLine, insertColumn: endCol + 1
    )
  )

  # Clear visual selection
  state.visualSelection.active = false

  # Save current mode for returning with ESC
  state.previousMode = state.mode

  # Switch to insert mode
  state.mode = EditorMode.Insert

proc visualChange*(buffer: TextBuffer, state: EditorState) =
  ## Delete visual selection and enter insert mode (c command)
  if state.visualSelection.active:
    # Capture the pending register before the edit: the store happens only after
    # the transaction commits (registers are outside buffer transactions), and
    # it must be consumed even if the edit fails.
    let pendingReg = state.pendingInput.pendingRegister
    state.pendingInput.pendingRegister = none(char)

    var deletedText = ""
    var deletedIsLine = false

    let txr = withTransaction(buffer, "Visual change"):
      case state.visualSelection.kind
      of vskBlock:
        let startCol =
          min(state.visualSelection.start.column, state.visualSelection.current.column)
        let startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        let endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)
        checkVisualEdit(state, deleteBlockSelection(buffer, state, deletedText))
        state.cursor.line = startLine
        state.cursor.column = startCol
        state.editState.visualBlockInsertContext = some(
          VisualBlockInsertContext(
            kind: vbiChange,
            startLine: startLine,
            endLine: endLine,
            insertColumn: startCol,
          )
        )
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)

        deletedText = getLineText(buffer, state.visualSelection)
        deletedIsLine = true

        for _ in startLine .. endLine:
          checkVisualEdit(state, buffer.deleteLine(startLine))

        checkVisualEdit(state, buffer.insert(startLine, ""))
        state.cursor.line = startLine
        state.cursor.column = 0
      of vskChar:
        let (selStart, selEnd) = state.visualSelection.getSelectionRange()

        deletedText = buffer.getTextInRange(selStart, selEnd)

        checkVisualEdit(state, buffer.deleteRange(selStart, selEnd))

        state.cursor = selStart
    if txr.isErr:
      if state.statusMessage.len == 0:
        state.statusMessage = txr.error
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    # Registers are outside the buffer transaction, so store after commit.
    state.storeVisualDeletedText(pendingReg, deletedText, deletedIsLine)

    state.visualSelection.active = false
    state.previousMode = EditorMode.Normal # c always returns to Normal on ESC
    state.mode = EditorMode.Insert

proc visualSwapSelection*(buffer: TextBuffer, state: EditorState) =
  ## Swap the cursor between the start and end of the selection (o command)
  if state.visualSelection.active:
    let temp = state.visualSelection.start
    state.visualSelection.start = state.visualSelection.current
    state.visualSelection.current = temp
    state.cursor = state.visualSelection.current

proc visualPaste*(
    buffer: TextBuffer,
    state: EditorState,
    clipboardConfig: ClipboardConfig = ClipboardConfig(enable: false, tool: cbtXclip),
): Result[(), string] =
  ## Delete selection and paste register content.
  result = Result[(), string].ok ()
  if state.visualSelection.active:
    let regName =
      if state.pendingInput.pendingRegister.isSome and
          state.pendingInput.pendingRegister.get != '\0':
        state.pendingInput.pendingRegister.get
      else:
        '"'
    let reg = state.registers.getRegister(regName)
    var pasteText = buffer.normalizeNewlines(reg.getContent())
    let isFullLine = reg.isLine
    let registerEmpty = reg.isEmpty

    # Clear early so deletes don't overwrite the source register.
    state.pendingInput.pendingRegister = none(char)

    # Fallback to system clipboard if register empty; empty linewise is not empty.
    if registerEmpty and clipboardConfig.enable:
      let readResult =
        state.registers.clipboardFallbackRead(clipboardConfig.tool, regName)
      if readResult.isErr:
        state.visualSelection.active = false
        state.mode = state.previousMode
        # The clipboard layer already names the operation; a second prefix here
        # would double the sentence on the status line.
        return Result[(), string].err(readResult.error)
      pasteText = buffer.preparePastedText(readResult.get)

    # Empty linewise paste is valid for line-visual mode.
    let allowEmptyLinewise = isFullLine and state.visualSelection.kind == vskLine
    if pasteText.len == 0 and not allowEmptyLinewise:
      # Nothing to paste, just exit visual mode
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    var deletedText = ""
    var deletedIsLine = false
    let cursorBeforePaste = state.cursor

    template checkPasteErr(r: Result[(), string]) =
      ## Like checkVisualEditErr but also restores cursor for rollback.
      let checkPasteErrResult = r
      if checkPasteErrResult.isErr:
        state.cursor = cursorBeforePaste
        checkVisualEditErr(state, checkPasteErrResult)

    let txr = withTransaction(buffer, "Visual paste"):
      case state.visualSelection.kind
      of vskBlock:
        checkPasteErr(deleteBlockSelection(buffer, state, deletedText))
        let startCol =
          min(state.visualSelection.start.column, state.visualSelection.current.column)
        let startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        state.cursor.line = startLine
        state.cursor.column = startCol
        checkPasteErr(buffer.insertText(state.cursor, pasteText))
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)

        deletedText = getLineText(buffer, state.visualSelection)
        deletedIsLine = true

        for _ in startLine .. endLine:
          checkPasteErr(buffer.deleteLine(startLine))

        # Linewise register stores a trailing \n, so split yields an empty tail
        # element -- drop it or an extra blank line gets inserted.
        var lines = pasteText.split('\n')
        if lines.len > 1 and lines[^1].len == 0:
          lines.setLen(lines.len - 1)
        for i, line in lines:
          checkPasteErr(buffer.insert(startLine + i, line))
        state.cursor.line = startLine
        state.cursor.column = 0
      of vskChar:
        let (selStart, selEnd) = state.visualSelection.getSelectionRange()

        deletedText = buffer.getTextInRange(selStart, selEnd)
        deletedIsLine = selStart.line != selEnd.line

        checkPasteErr(buffer.deleteRange(selStart, selEnd))

        state.cursor = selStart
        checkPasteErr(buffer.insertText(state.cursor, pasteText))
    if txr.isErr:
      # The transaction rolled the buffer back, so the paste anchor is gone.
      state.cursor = cursorBeforePaste
      state.visualSelection.active = false
      state.mode = state.previousMode
      return Result[(), string].err(txr.error)

    # Registers are not covered by the buffer transaction, so write the
    # replaced text only after the transaction committed.
    state.registers.setDeletedRegister(deletedText, deletedIsLine)

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

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
  # Registry validates `ch`; this guard is for direct callers (see visualReplace).
  if ch.charLen != 1:
    return

  if state.visualSelection.active:
    let (openChar, closeChar) = getSurroundPair(ch)
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    let txr = withTransaction(buffer, "Visual surround"):
      case state.visualSelection.kind
      of vskChar:
        let afterEnd = BufferPosition(line: selEnd.line, column: selEnd.column + 1)
        checkVisualEdit(state, buffer.insertText(afterEnd, closeChar))
        checkVisualEdit(state, buffer.insertText(selStart, openChar))
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)
        for lineNum in countdown(endLine, startLine):
          let lineLen = buffer.getLine(lineNum).charLen
          let lineEnd = BufferPosition(line: lineNum, column: lineLen)
          checkVisualEdit(state, buffer.insertText(lineEnd, closeChar))
          let lineStart = BufferPosition(line: lineNum, column: 0)
          checkVisualEdit(state, buffer.insertText(lineStart, openChar))
      of vskBlock:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)
          startCol = min(
            state.visualSelection.start.column, state.visualSelection.current.column
          )
          endCol = max(
            state.visualSelection.start.column, state.visualSelection.current.column
          )
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
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode
