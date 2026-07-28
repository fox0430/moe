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

import std/[options, strutils, unicode]

import pkg/results

import ../[types, registers, motion, modes, config, clipboard]
import ../buffer/[core, edit, fold, undo]
import insert_commands

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
      lines.add($line.runeSubStr(startCol))
    else:
      # Normal case
      lines.add($line.runeSubStr(startCol, endCol - startCol + 1))
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

proc visualYank*(buffer: TextBuffer, state: EditorState) =
  ## Yank (copy) visual selection to the yank register and return to previous mode
  if state.visualSelection.active:
    # Get normalized selection range
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    # Get the selected text based on selection kind
    let selectedText =
      case state.visualSelection.kind
      of vskBlock:
        getBlockText(buffer, state.visualSelection)
      of vskLine:
        getLineText(buffer, state.visualSelection)
      of vskChar:
        buffer.getTextInRange(selStart, selEnd)

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

proc storeVisualDeletedText(state: EditorState, text: string, isLine: bool) =
  ## Store deleted text in the register selected by pendingRegister.
  ## Call this only after the buffer change succeeded: registers are not covered
  ## by the buffer transaction, so a rollback would not undo them.
  if state.pendingInput.pendingRegister.isSome and
      state.pendingInput.pendingRegister.get != '\0':
    let regName = state.pendingInput.pendingRegister.get
    if regName.isNamedRegisterName:
      discard state.registers.setNamedRegister(regName, text, isLine)
    elif regName.isClipboardRegisterName:
      state.registers.setClipboardRegister(regName, text, isLine)
    else:
      state.registers.setDeletedRegister(text, isLine)
  else:
    state.registers.setDeletedRegister(text, isLine)

proc deleteBlockSelection(buffer: TextBuffer, state: EditorState): Result[(), string] =
  ## Delete a block (rectangular) selection
  let
    startLine =
      min(state.visualSelection.start.line, state.visualSelection.current.line)
    endLine = max(state.visualSelection.start.line, state.visualSelection.current.line)
    startCol =
      min(state.visualSelection.start.column, state.visualSelection.current.column)
    endCol =
      max(state.visualSelection.start.column, state.visualSelection.current.column)

  # Get text to yank first
  let deletedText = getBlockText(buffer, state.visualSelection)

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

  state.storeVisualDeletedText(deletedText, false)

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

proc deleteLineSelection(buffer: TextBuffer, state: EditorState): Result[(), string] =
  ## Delete a line-wise selection (entire lines)
  let
    startLine =
      min(state.visualSelection.start.line, state.visualSelection.current.line)
    endLine = max(state.visualSelection.start.line, state.visualSelection.current.line)

  # Get text to yank first
  let deletedText = getLineText(buffer, state.visualSelection)

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

  state.storeVisualDeletedText(deletedText, true)

  # Move cursor to start line (or last line if start was beyond buffer)
  let newLine = min(startLine, buffer.len - 1)
  state.cursor = BufferPosition(line: newLine, column: 0)

  return ok(())

proc visualDelete*(buffer: TextBuffer, state: EditorState) =
  ## Delete visual selection and return to previous mode
  if state.visualSelection.active:
    var deleteError = ""

    let txr = withTransaction(buffer, "Visual delete"):
      case state.visualSelection.kind
      of vskBlock:
        let delResult = deleteBlockSelection(buffer, state)
        if delResult.isErr:
          deleteError = delResult.error
      of vskLine:
        let delResult = deleteLineSelection(buffer, state)
        if delResult.isErr:
          deleteError = delResult.error
      of vskChar:
        let (selStart, selEnd) = state.visualSelection.getSelectionRange()

        let selectedText = buffer.getTextInRange(selStart, selEnd)

        let delResult = buffer.deleteRange(selStart, selEnd)
        if delResult.isErr:
          deleteError = delResult.error
        else:
          state.cursor = selStart
          state.storeVisualDeletedText(selectedText, false)

      state.pendingInput.pendingRegister = none(char)
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

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
    if deleteError.len > 0:
      state.statusMessage = "Error: " & deleteError
    else:
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

    let txr = withTransaction(buffer, "Visual indent"):
      for lineNum in startLine .. endLine:
        state.cursor.line = lineNum
        state.cursor.column = 0
        indentLine(buffer, state, count)

      state.cursor.line = startLine
      state.cursor.column = 0
    if txr.isErr:
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

    let txr = withTransaction(buffer, "Visual dedent"):
      for lineNum in startLine .. endLine:
        state.cursor.line = lineNum
        state.cursor.column = 0
        dedentLine(buffer, state, count)

      state.cursor.line = startLine
      state.cursor.column = 0
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc visualLowercase*(buffer: TextBuffer, state: EditorState) =
  ## Convert visual selection to lowercase and return to previous mode
  if state.visualSelection.active:
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    let selectedText =
      case state.visualSelection.kind
      of vskBlock:
        getBlockText(buffer, state.visualSelection)
      of vskLine:
        getLineText(buffer, state.visualSelection)
      of vskChar:
        buffer.getTextInRange(selStart, selEnd)

    let lowercaseText = selectedText.toLowerAscii()

    let txr = withTransaction(buffer, "Visual lowercase"):
      case state.visualSelection.kind
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

        for lineNum in startLine .. endLine:
          let line = buffer.getLine(lineNum)
          let lineLen = line.charLen
          if startCol < lineLen:
            let actualEndCol = min(endCol, lineLen - 1)
            let startPos = BufferPosition(line: lineNum, column: startCol)
            let endPos = BufferPosition(line: lineNum, column: actualEndCol)
            let blockText = buffer.getTextInRange(startPos, endPos)
            let lowerText = blockText.toLowerAscii()
            discard buffer.deleteRange(startPos, endPos)
            discard buffer.insertText(startPos, lowerText)
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)

        for lineNum in startLine .. endLine:
          let lineText = $buffer.getLine(lineNum)
          let lowerText = lineText.toLowerAscii()
          let startPos = BufferPosition(line: lineNum, column: 0)
          let endPos =
            BufferPosition(line: lineNum, column: max(0, lineText.charLen - 1))
          if lineText.charLen > 0:
            discard buffer.deleteRange(startPos, endPos)
            discard buffer.insertText(startPos, lowerText)
      of vskChar:
        discard buffer.deleteRange(selStart, selEnd)
        discard buffer.insertText(selStart, lowercaseText)

      state.cursor = selStart
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc visualUppercase*(buffer: TextBuffer, state: EditorState) =
  ## Convert visual selection to uppercase and return to previous mode
  if state.visualSelection.active:
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    let selectedText =
      case state.visualSelection.kind
      of vskBlock:
        getBlockText(buffer, state.visualSelection)
      of vskLine:
        getLineText(buffer, state.visualSelection)
      of vskChar:
        buffer.getTextInRange(selStart, selEnd)

    let uppercaseText = selectedText.toUpperAscii()

    let txr = withTransaction(buffer, "Visual uppercase"):
      case state.visualSelection.kind
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

        for lineNum in startLine .. endLine:
          let line = buffer.getLine(lineNum)
          let lineLen = line.charLen
          if startCol < lineLen:
            let actualEndCol = min(endCol, lineLen - 1)
            let startPos = BufferPosition(line: lineNum, column: startCol)
            let endPos = BufferPosition(line: lineNum, column: actualEndCol)
            let blockText = buffer.getTextInRange(startPos, endPos)
            let upperText = blockText.toUpperAscii()
            discard buffer.deleteRange(startPos, endPos)
            discard buffer.insertText(startPos, upperText)
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)

        for lineNum in startLine .. endLine:
          let lineText = $buffer.getLine(lineNum)
          let upperText = lineText.toUpperAscii()
          let startPos = BufferPosition(line: lineNum, column: 0)
          let endPos =
            BufferPosition(line: lineNum, column: max(0, lineText.charLen - 1))
          if lineText.charLen > 0:
            discard buffer.deleteRange(startPos, endPos)
            discard buffer.insertText(startPos, upperText)
      of vskChar:
        discard buffer.deleteRange(selStart, selEnd)
        discard buffer.insertText(selStart, uppercaseText)

      state.cursor = selStart
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc toggleCase(s: string): string =
  ## Toggle case of each character in the string
  result = ""
  for c in s:
    if c.isUpperAscii:
      result.add(c.toLowerAscii)
    elif c.isLowerAscii:
      result.add(c.toUpperAscii)
    else:
      result.add(c)

proc visualToggleCase*(buffer: TextBuffer, state: EditorState) =
  ## Toggle case of visual selection and return to previous mode
  if state.visualSelection.active:
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    let txr = withTransaction(buffer, "Visual toggle case"):
      case state.visualSelection.kind
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

        for lineNum in startLine .. endLine:
          let line = buffer.getLine(lineNum)
          let lineLen = line.charLen
          if startCol < lineLen:
            let actualEndCol = min(endCol, lineLen - 1)
            let startPos = BufferPosition(line: lineNum, column: startCol)
            let endPos = BufferPosition(line: lineNum, column: actualEndCol)
            let blockText = buffer.getTextInRange(startPos, endPos)
            let toggledText = toggleCase(blockText)
            discard buffer.deleteRange(startPos, endPos)
            discard buffer.insertText(startPos, toggledText)
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)

        for lineNum in startLine .. endLine:
          let lineText = $buffer.getLine(lineNum)
          let toggledText = toggleCase(lineText)
          let startPos = BufferPosition(line: lineNum, column: 0)
          let endPos =
            BufferPosition(line: lineNum, column: max(0, lineText.charLen - 1))
          if lineText.charLen > 0:
            discard buffer.deleteRange(startPos, endPos)
            discard buffer.insertText(startPos, toggledText)
      of vskChar:
        let selectedText = buffer.getTextInRange(selStart, selEnd)
        let toggledText = toggleCase(selectedText)
        discard buffer.deleteRange(selStart, selEnd)
        discard buffer.insertText(selStart, toggledText)

      state.cursor = selStart
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc visualReplace*(buffer: TextBuffer, state: EditorState, ch: char) =
  ## Replace all characters in visual selection with specified character
  if state.visualSelection.active:
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    let txr = withTransaction(buffer, "Visual replace"):
      case state.visualSelection.kind
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

        for lineNum in startLine .. endLine:
          let line = buffer.getLine(lineNum)
          let lineLen = line.charLen
          if startCol < lineLen:
            let actualEndCol = min(endCol, lineLen - 1)
            let startPos = BufferPosition(line: lineNum, column: startCol)
            let endPos = BufferPosition(line: lineNum, column: actualEndCol)
            let blockText = buffer.getTextInRange(startPos, endPos)
            let replaceText = $ch.repeat(blockText.charLen)
            discard buffer.deleteRange(startPos, endPos)
            discard buffer.insertText(startPos, replaceText)
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)

        for lineNum in startLine .. endLine:
          let lineText = $buffer.getLine(lineNum)
          if lineText.charLen > 0:
            let replaceText = $ch.repeat(lineText.charLen)
            let startPos = BufferPosition(line: lineNum, column: 0)
            let endPos =
              BufferPosition(line: lineNum, column: max(0, lineText.charLen - 1))
            discard buffer.deleteRange(startPos, endPos)
            discard buffer.insertText(startPos, replaceText)
      of vskChar:
        let selectedText = buffer.getTextInRange(selStart, selEnd)
        var replaceText = ""
        for c in selectedText:
          if c == '\n':
            replaceText.add('\n')
          else:
            replaceText.add(ch)
        discard buffer.deleteRange(selStart, selEnd)
        discard buffer.insertText(selStart, replaceText)

      state.cursor = selStart
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

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
  if state.visualSelection.active and state.visualSelection.kind == vskBlock:
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
        kind: vbiAppend,
        startLine: startLine,
        endLine: endLine,
        insertColumn: endCol + 1,
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
    let txr = withTransaction(buffer, "Visual change"):
      case state.visualSelection.kind
      of vskBlock:
        let startCol =
          min(state.visualSelection.start.column, state.visualSelection.current.column)
        let startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        let endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)
        discard deleteBlockSelection(buffer, state)
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

        for _ in startLine .. endLine:
          discard buffer.deleteLine(startLine)

        discard buffer.insert(startLine, "")
        state.cursor.line = startLine
        state.cursor.column = 0
      of vskChar:
        let (selStart, selEnd) = state.visualSelection.getSelectionRange()

        discard buffer.deleteRange(selStart, selEnd)

        state.cursor = selStart
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

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
) =
  ## Delete selection and paste register content (p/P command)
  if state.visualSelection.active:
    # Get register content
    let regName =
      if state.pendingInput.pendingRegister.isSome and
          state.pendingInput.pendingRegister.get != '\0':
        state.pendingInput.pendingRegister.get
      else:
        '"' # Default unnamed register

    let reg = state.registers.getRegister(regName)
    var pasteText = reg.getContent().normalizeNewlines()
    let isFullLine = reg.isLine
    let registerEmpty = reg.isEmpty

    # Clear pending register immediately so downstream delete operations
    # (e.g. deleteBlockSelection) don't overwrite the named/clipboard register
    # that we just read from.
    state.pendingInput.pendingRegister = none(char)

    # If register is truly empty, try system clipboard (if enabled).
    # A linewise register with a single empty line ([""]) is not empty — it
    # represents one empty line and must not trigger the clipboard fallback.
    if registerEmpty and clipboardConfig.enable:
      let readResult = readFromClipboardSync(clipboardConfig.tool)
      if readResult.isOk:
        pasteText = readResult.get.normalizeNewlines()

    # Linewise paste of an empty line is legitimate for line-visual selection
    # (Vim inserts a blank line). All other empty combinations are a no-op.
    let allowEmptyLinewise = isFullLine and state.visualSelection.kind == vskLine
    if pasteText.len == 0 and not allowEmptyLinewise:
      # Nothing to paste, just exit visual mode
      state.visualSelection.active = false
      state.pendingInput.pendingRegister = none(char)
      state.mode = state.previousMode
      return

    let txr = withTransaction(buffer, "Visual paste"):
      case state.visualSelection.kind
      of vskBlock:
        discard deleteBlockSelection(buffer, state)
        let startCol =
          min(state.visualSelection.start.column, state.visualSelection.current.column)
        let startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        state.cursor.line = startLine
        state.cursor.column = startCol
        discard buffer.insertText(state.cursor, pasteText)
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)

        let deletedText = getLineText(buffer, state.visualSelection)

        var deleted = true
        for _ in startLine .. endLine:
          if buffer.deleteLine(startLine).isErr:
            deleted = false
            break

        # Registers are not covered by the buffer transaction, so write the
        # replaced text only after the buffer change went through
        if deleted:
          state.registers.setDeletedRegister(deletedText, true)

        # Linewise register stores a trailing \n, so split yields an empty tail
        # element -- drop it or an extra blank line gets inserted.
        var lines = pasteText.split('\n')
        if lines.len > 1 and lines[^1].len == 0:
          lines.setLen(lines.len - 1)
        for i, line in lines:
          discard buffer.insert(startLine + i, line)
        state.cursor.line = startLine
        state.cursor.column = 0
      of vskChar:
        let (selStart, selEnd) = state.visualSelection.getSelectionRange()

        let deletedText = buffer.getTextInRange(selStart, selEnd)
        let isMultiLine = selStart.line != selEnd.line

        let delResult = buffer.deleteRange(selStart, selEnd)
        if delResult.isOk:
          # Registers are not covered by the buffer transaction, so write the
          # replaced text only after the buffer change went through
          state.registers.setDeletedRegister(deletedText, isMultiLine)

        state.cursor = selStart
        discard buffer.insertText(state.cursor, pasteText)

      state.pendingInput.pendingRegister = none(char)
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc getSurroundPair(ch: char): tuple[open, close: char] =
  ## Get the open/close pair for a surround character.
  const
    openBrackets = ['(', '[', '{', '<']
    closeBrackets = [')', ']', '}', '>']
  let openIdx = openBrackets.find(ch)
  if openIdx >= 0:
    return (openBrackets[openIdx], closeBrackets[openIdx])
  let closeIdx = closeBrackets.find(ch)
  if closeIdx >= 0:
    return (openBrackets[closeIdx], closeBrackets[closeIdx])
  # Quotes and other characters: same for open and close
  return (ch, ch)

proc visualSurround*(buffer: TextBuffer, state: EditorState, ch: char) =
  ## Surround visual selection with the specified character pair.
  if state.visualSelection.active:
    let (openChar, closeChar) = getSurroundPair(ch)
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    let txr = withTransaction(buffer, "Visual surround"):
      case state.visualSelection.kind
      of vskChar:
        let afterEnd = BufferPosition(line: selEnd.line, column: selEnd.column + 1)
        discard buffer.insertText(afterEnd, $closeChar)
        discard buffer.insertText(selStart, $openChar)
      of vskLine:
        let
          startLine =
            min(state.visualSelection.start.line, state.visualSelection.current.line)
          endLine =
            max(state.visualSelection.start.line, state.visualSelection.current.line)
        for lineNum in countdown(endLine, startLine):
          let lineLen = buffer.getLine(lineNum).charLen
          let lineEnd = BufferPosition(line: lineNum, column: lineLen)
          discard buffer.insertText(lineEnd, $closeChar)
          let lineStart = BufferPosition(line: lineNum, column: 0)
          discard buffer.insertText(lineStart, $openChar)
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
            discard buffer.insertText(afterEnd, $closeChar)
            let colStart = BufferPosition(line: lineNum, column: startCol)
            discard buffer.insertText(colStart, $openChar)

      state.cursor = selStart
    if txr.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode
