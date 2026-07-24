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

import ../[buffer, types, registers, motion, modes, config, clipboard]
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

proc deleteBlockSelection(buffer: TextBuffer, state: EditorState) =
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

  # Store in register system
  if state.pendingInput.pendingRegister.isSome and
      state.pendingInput.pendingRegister.get != '\0':
    let regName = state.pendingInput.pendingRegister.get
    if regName.isNamedRegisterName:
      discard state.registers.setNamedRegister(regName, deletedText, false)
    elif regName.isClipboardRegisterName:
      state.registers.setClipboardRegister(regName, deletedText, false)
    else:
      state.registers.setDeletedRegister(deletedText, false)
  else:
    state.registers.setDeletedRegister(deletedText, false)

  # Delete from each line in reverse order to preserve line numbers
  for lineNum in countdown(endLine, startLine):
    let line = buffer.getLine(lineNum)
    let lineLen = line.charLen
    if startCol < lineLen:
      let actualEndCol = min(endCol, lineLen - 1)
      let startPos = BufferPosition(line: lineNum, column: startCol)
      let endPos = BufferPosition(line: lineNum, column: actualEndCol)
      discard buffer.deleteRange(startPos, endPos)

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

proc deleteLineSelection(buffer: TextBuffer, state: EditorState) =
  ## Delete a line-wise selection (entire lines)
  let
    startLine =
      min(state.visualSelection.start.line, state.visualSelection.current.line)
    endLine = max(state.visualSelection.start.line, state.visualSelection.current.line)

  # Get text to yank first
  let deletedText = getLineText(buffer, state.visualSelection)

  # Store in register system
  if state.pendingInput.pendingRegister.isSome and
      state.pendingInput.pendingRegister.get != '\0':
    let regName = state.pendingInput.pendingRegister.get
    if regName.isNamedRegisterName:
      discard state.registers.setNamedRegister(regName, deletedText, true)
    elif regName.isClipboardRegisterName:
      state.registers.setClipboardRegister(regName, deletedText, true)
    else:
      state.registers.setDeletedRegister(deletedText, true)
  else:
    state.registers.setDeletedRegister(deletedText, true)

  # Delete lines from end to start to preserve line numbers
  for lineNum in countdown(endLine, startLine):
    discard buffer.deleteLine(lineNum)

  # If buffer is empty after deletion, add an empty line
  if buffer.len == 0:
    discard buffer.insert(0, "")

  # Move cursor to start line (or last line if start was beyond buffer)
  let newLine = min(startLine, buffer.len - 1)
  state.cursor = BufferPosition(line: newLine, column: 0)

proc visualDelete*(buffer: TextBuffer, state: EditorState) =
  ## Delete visual selection and return to previous mode
  if state.visualSelection.active:
    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual delete")
    if transactionResult.isErr:
      # Failed to begin transaction, abort
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    var deleteError = ""

    case state.visualSelection.kind
    of vskBlock:
      deleteBlockSelection(buffer, state)
    of vskLine:
      deleteLineSelection(buffer, state)
    of vskChar:
      # Get normalized selection range
      let (selStart, selEnd) = state.visualSelection.getSelectionRange()

      # Get the text before deleting (Vim behavior)
      let selectedText = buffer.getTextInRange(selStart, selEnd)

      # Store in register system
      if state.pendingInput.pendingRegister.isSome and
          state.pendingInput.pendingRegister.get != '\0':
        let regName = state.pendingInput.pendingRegister.get
        if regName.isNamedRegisterName:
          discard state.registers.setNamedRegister(regName, selectedText, false)
        elif regName.isClipboardRegisterName:
          state.registers.setClipboardRegister(regName, selectedText, false)
        else:
          state.registers.setDeletedRegister(selectedText, false)
      else:
        state.registers.setDeletedRegister(selectedText, false)

      let result = buffer.deleteRange(selStart, selEnd)
      if result.isErr:
        deleteError = result.error
      else:
        # Move cursor to start of deleted range
        state.cursor = selStart

    # Clear pending register
    state.pendingInput.pendingRegister = none(char)

    # Commit transaction
    discard buffer.commitTransaction()

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
    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual indent")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    # Get line range
    let
      startLine =
        min(state.visualSelection.start.line, state.visualSelection.current.line)
      endLine =
        max(state.visualSelection.start.line, state.visualSelection.current.line)

    # Indent each line in the selection
    for lineNum in startLine .. endLine:
      state.cursor.line = lineNum
      state.cursor.column = 0
      indentLine(buffer, state, count)

    # Restore cursor to start of selection
    state.cursor.line = startLine
    state.cursor.column = 0

    # Commit transaction
    discard buffer.commitTransaction()

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc visualDedent*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Dedent all lines in visual selection and return to previous mode
  if state.visualSelection.active:
    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual dedent")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    # Get line range
    let
      startLine =
        min(state.visualSelection.start.line, state.visualSelection.current.line)
      endLine =
        max(state.visualSelection.start.line, state.visualSelection.current.line)

    # Dedent each line in the selection
    for lineNum in startLine .. endLine:
      state.cursor.line = lineNum
      state.cursor.column = 0
      dedentLine(buffer, state, count)

    # Restore cursor to start of selection
    state.cursor.line = startLine
    state.cursor.column = 0

    # Commit transaction
    discard buffer.commitTransaction()

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc visualLowercase*(buffer: TextBuffer, state: EditorState) =
  ## Convert visual selection to lowercase and return to previous mode
  if state.visualSelection.active:
    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual lowercase")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

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

    # Convert to lowercase
    let lowercaseText = selectedText.toLowerAscii()

    # Replace the selection with lowercase text
    case state.visualSelection.kind
    of vskBlock:
      # For block selection, convert each line's portion
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
          let blockText = buffer.getTextInRange(startPos, endPos)
          let lowerText = blockText.toLowerAscii()
          discard buffer.deleteRange(startPos, endPos)
          discard buffer.insertText(startPos, lowerText)
    of vskLine:
      # For line selection, replace entire lines
      let
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)

      for lineNum in startLine .. endLine:
        let lineText = $buffer.getLine(lineNum)
        let lowerText = lineText.toLowerAscii()
        # Delete and replace the line content
        let startPos = BufferPosition(line: lineNum, column: 0)
        let endPos = BufferPosition(line: lineNum, column: max(0, lineText.charLen - 1))
        if lineText.charLen > 0:
          discard buffer.deleteRange(startPos, endPos)
          discard buffer.insertText(startPos, lowerText)
    of vskChar:
      # Delete and insert lowercase text
      discard buffer.deleteRange(selStart, selEnd)
      discard buffer.insertText(selStart, lowercaseText)

    # Move cursor to start of selection
    state.cursor = selStart

    # Commit transaction
    discard buffer.commitTransaction()

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc visualUppercase*(buffer: TextBuffer, state: EditorState) =
  ## Convert visual selection to uppercase and return to previous mode
  if state.visualSelection.active:
    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual uppercase")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

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

    # Convert to uppercase
    let uppercaseText = selectedText.toUpperAscii()

    # Replace the selection with uppercase text
    case state.visualSelection.kind
    of vskBlock:
      # For block selection, convert each line's portion
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
          let blockText = buffer.getTextInRange(startPos, endPos)
          let upperText = blockText.toUpperAscii()
          discard buffer.deleteRange(startPos, endPos)
          discard buffer.insertText(startPos, upperText)
    of vskLine:
      # For line selection, replace entire lines
      let
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)

      for lineNum in startLine .. endLine:
        let lineText = $buffer.getLine(lineNum)
        let upperText = lineText.toUpperAscii()
        # Delete and replace the line content
        let startPos = BufferPosition(line: lineNum, column: 0)
        let endPos = BufferPosition(line: lineNum, column: max(0, lineText.charLen - 1))
        if lineText.charLen > 0:
          discard buffer.deleteRange(startPos, endPos)
          discard buffer.insertText(startPos, upperText)
    of vskChar:
      # Delete and insert uppercase text
      discard buffer.deleteRange(selStart, selEnd)
      discard buffer.insertText(selStart, uppercaseText)

    # Move cursor to start of selection
    state.cursor = selStart

    # Commit transaction
    discard buffer.commitTransaction()

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
    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual toggle case")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    # Get normalized selection range
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    # Replace the selection with toggled case text
    case state.visualSelection.kind
    of vskBlock:
      # For block selection, toggle each line's portion
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
          let blockText = buffer.getTextInRange(startPos, endPos)
          let toggledText = toggleCase(blockText)
          discard buffer.deleteRange(startPos, endPos)
          discard buffer.insertText(startPos, toggledText)
    of vskLine:
      # For line selection, replace entire lines
      let
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)

      for lineNum in startLine .. endLine:
        let lineText = $buffer.getLine(lineNum)
        let toggledText = toggleCase(lineText)
        # Delete and replace the line content
        let startPos = BufferPosition(line: lineNum, column: 0)
        let endPos = BufferPosition(line: lineNum, column: max(0, lineText.charLen - 1))
        if lineText.charLen > 0:
          discard buffer.deleteRange(startPos, endPos)
          discard buffer.insertText(startPos, toggledText)
    of vskChar:
      # Get selected text and toggle case
      let selectedText = buffer.getTextInRange(selStart, selEnd)
      let toggledText = toggleCase(selectedText)
      discard buffer.deleteRange(selStart, selEnd)
      discard buffer.insertText(selStart, toggledText)

    # Move cursor to start of selection
    state.cursor = selStart

    # Commit transaction
    discard buffer.commitTransaction()

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode

proc visualReplace*(buffer: TextBuffer, state: EditorState, ch: char) =
  ## Replace all characters in visual selection with specified character
  if state.visualSelection.active:
    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual replace")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    # Get normalized selection range
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    # Replace selection based on kind
    case state.visualSelection.kind
    of vskBlock:
      # For block selection, replace each line's portion
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
          let blockText = buffer.getTextInRange(startPos, endPos)
          # Create replacement string with same character count
          let replaceText = $ch.repeat(blockText.charLen)
          discard buffer.deleteRange(startPos, endPos)
          discard buffer.insertText(startPos, replaceText)
    of vskLine:
      # For line selection, replace all non-newline characters on each line
      let
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)

      for lineNum in startLine .. endLine:
        let lineText = $buffer.getLine(lineNum)
        if lineText.charLen > 0:
          # Create replacement string with same length
          let replaceText = $ch.repeat(lineText.charLen)
          let startPos = BufferPosition(line: lineNum, column: 0)
          let endPos =
            BufferPosition(line: lineNum, column: max(0, lineText.charLen - 1))
          discard buffer.deleteRange(startPos, endPos)
          discard buffer.insertText(startPos, replaceText)
    of vskChar:
      # Get the text and create replacement
      let selectedText = buffer.getTextInRange(selStart, selEnd)
      # Replace all non-newline characters with the replacement char
      var replaceText = ""
      for c in selectedText:
        if c == '\n':
          replaceText.add('\n')
        else:
          replaceText.add(ch)
      discard buffer.deleteRange(selStart, selEnd)
      discard buffer.insertText(selStart, replaceText)

    # Move cursor to start of selection
    state.cursor = selStart

    # Commit transaction
    discard buffer.commitTransaction()

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
    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual change")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    case state.visualSelection.kind
    of vskBlock:
      let startCol =
        min(state.visualSelection.start.column, state.visualSelection.current.column)
      let startLine =
        min(state.visualSelection.start.line, state.visualSelection.current.line)
      let endLine =
        max(state.visualSelection.start.line, state.visualSelection.current.line)
      deleteBlockSelection(buffer, state)
      # Position cursor at the start of the block
      state.cursor.line = startLine
      state.cursor.column = startCol
      # Set up context for text replication across block lines
      state.editState.visualBlockInsertContext = some(
        VisualBlockInsertContext(
          kind: vbiChange,
          startLine: startLine,
          endLine: endLine,
          insertColumn: startCol,
        )
      )
    of vskLine:
      # For line change, delete lines and leave one empty line
      let
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)

      # Delete all lines in the selection
      for _ in startLine .. endLine:
        discard buffer.deleteLine(startLine)

      # Insert an empty line where the selection was
      discard buffer.insert(startLine, "")
      state.cursor.line = startLine
      state.cursor.column = 0
    of vskChar:
      # Get normalized selection range
      let (selStart, selEnd) = state.visualSelection.getSelectionRange()

      # Delete the selected text
      discard buffer.deleteRange(selStart, selEnd)

      # Move cursor to start of deleted range
      state.cursor = selStart

    # Commit transaction
    discard buffer.commitTransaction()

    # Clear selection and enter insert mode
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

    # Begin transaction for undo support
    let transactionResult = buffer.beginTransaction("Visual paste")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    case state.visualSelection.kind
    of vskBlock:
      # For block selection, delete block first then insert
      deleteBlockSelection(buffer, state)
      let startCol =
        min(state.visualSelection.start.column, state.visualSelection.current.column)
      let startLine =
        min(state.visualSelection.start.line, state.visualSelection.current.line)
      state.cursor.line = startLine
      state.cursor.column = startCol
      discard buffer.insertText(state.cursor, pasteText)
    of vskLine:
      # For line selection, delete lines and insert paste content
      let
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)

      # Store deleted text in register
      let deletedText = getLineText(buffer, state.visualSelection)
      state.registers.setDeletedRegister(deletedText, true)

      # Delete all selected lines
      for _ in startLine .. endLine:
        discard buffer.deleteLine(startLine)

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
      # Get normalized selection range
      let (selStart, selEnd) = state.visualSelection.getSelectionRange()

      # Store deleted text in register
      let deletedText = buffer.getTextInRange(selStart, selEnd)
      let isMultiLine = selStart.line != selEnd.line
      state.registers.setDeletedRegister(deletedText, isMultiLine)

      # Delete selection
      discard buffer.deleteRange(selStart, selEnd)

      # Insert paste content at cursor
      state.cursor = selStart
      discard buffer.insertText(state.cursor, pasteText)

    # Clear pending register
    state.pendingInput.pendingRegister = none(char)

    # Commit transaction
    discard buffer.commitTransaction()

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
    let transactionResult = buffer.beginTransaction("Visual surround")
    if transactionResult.isErr:
      state.visualSelection.active = false
      state.mode = state.previousMode
      return

    let (openChar, closeChar) = getSurroundPair(ch)
    let (selStart, selEnd) = state.visualSelection.getSelectionRange()

    case state.visualSelection.kind
    of vskChar:
      # Insert close char after selection end, then open char before start
      # (reverse order to avoid position shift)
      let afterEnd = BufferPosition(line: selEnd.line, column: selEnd.column + 1)
      discard buffer.insertText(afterEnd, $closeChar)
      discard buffer.insertText(selStart, $openChar)
    of vskLine:
      let
        startLine =
          min(state.visualSelection.start.line, state.visualSelection.current.line)
        endLine =
          max(state.visualSelection.start.line, state.visualSelection.current.line)
      # Process lines in reverse to avoid position shift
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
        startCol =
          min(state.visualSelection.start.column, state.visualSelection.current.column)
        endCol =
          max(state.visualSelection.start.column, state.visualSelection.current.column)
      # Process lines in reverse to avoid position shift
      for lineNum in countdown(endLine, startLine):
        let lineLen = buffer.getLine(lineNum).charLen
        if startCol < lineLen:
          let actualEndCol = min(endCol, lineLen - 1)
          let afterEnd = BufferPosition(line: lineNum, column: actualEndCol + 1)
          discard buffer.insertText(afterEnd, $closeChar)
          let colStart = BufferPosition(line: lineNum, column: startCol)
          discard buffer.insertText(colStart, $openChar)

    state.cursor = selStart

    discard buffer.commitTransaction()

    state.visualSelection.active = false
    state.statusMessage = ""
    state.mode = state.previousMode
