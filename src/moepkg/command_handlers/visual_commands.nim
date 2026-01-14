#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import ../[buffer, types, cursor, registers, motion, modes]
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
    state.needsFullRedraw = true

proc visualMoveRight*(buffer: TextBuffer, state: EditorState) =
  ## Move right in visual mode and update selection
  let lineLen = buffer.getLine(state.cursor.line).charLen
  if state.cursor.column < lineLen:
    state.cursor.column += 1
    state.visualSelection.current = state.cursor
    state.needsFullRedraw = true

proc visualMoveUp*(buffer: TextBuffer, state: EditorState) =
  ## Move up in visual mode and update selection
  if state.cursor.line > 0:
    state.cursor.line -= 1
    # Clamp cursor to new line length
    let newLineLen = buffer.getLine(state.cursor.line).charLen
    if state.cursor.column > newLineLen:
      state.cursor.column = newLineLen
    state.visualSelection.current = state.cursor
    state.needsFullRedraw = true

proc visualMoveDown*(buffer: TextBuffer, state: EditorState) =
  ## Move down in visual mode and update selection
  if state.cursor.line < buffer.len - 1:
    state.cursor.line += 1
    # Clamp cursor to new line length
    let newLineLen = buffer.getLine(state.cursor.line).charLen
    if state.cursor.column > newLineLen:
      state.cursor.column = newLineLen
    state.visualSelection.current = state.cursor
    state.needsFullRedraw = true

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
      lines.add($line.substr(startCol))
    else:
      # Normal case
      lines.add($line.substr(startCol, endCol - startCol + 1))
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
    if state.pendingRegister.isSome and state.pendingRegister.get != '\0':
      # User specified a register with "
      let regName = state.pendingRegister.get
      if regName.isNamedRegisterName:
        discard state.registers.setNamedRegister(regName, selectedText, isLine)
      elif regName.isClipboardRegisterName:
        state.registers.setClipboardRegister(selectedText, isLine)
      else:
        # For other registers (including "), use yank register
        state.registers.setYankedRegister(selectedText, isLine)
      state.pendingRegister = none(char)
    else:
      # Default: use yank register (0) and unnamed register
      state.registers.setYankedRegister(selectedText, isLine)

    # Also update legacy yankRegister for backward compatibility
    state.yankRegister = selectedText
    state.yankIsLine = isLine

    # Move cursor to start of selection (Vim behavior)
    state.cursor = selStart

    # Clear selection and return to previous mode
    state.visualSelection.active = false
    state.needsFullRedraw = true
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
  if state.pendingRegister.isSome and state.pendingRegister.get != '\0':
    let regName = state.pendingRegister.get
    if regName.isNamedRegisterName:
      discard state.registers.setNamedRegister(regName, deletedText, false)
    elif regName.isClipboardRegisterName:
      state.registers.setClipboardRegister(deletedText, false)
    else:
      state.registers.setDeletedRegister(deletedText, false)
  else:
    state.registers.setDeletedRegister(deletedText, false)

  # Also update legacy yankRegister for backward compatibility
  state.yankRegister = deletedText
  state.yankIsLine = false

  # Delete from each line in reverse order to preserve line numbers
  for lineNum in countdown(endLine, startLine):
    let line = buffer.getLine(lineNum)
    let lineLen = line.charLen
    if startCol < lineLen:
      let actualEndCol = min(endCol, lineLen - 1)
      let startPos = BufferPosition(line: lineNum, column: startCol)
      let endPos = BufferPosition(line: lineNum, column: actualEndCol)
      discard buffer.deleteRange(startPos, endPos)

  # Move cursor to start of deleted block
  state.cursor = BufferPosition(line: startLine, column: startCol)

proc deleteLineSelection(buffer: TextBuffer, state: EditorState) =
  ## Delete a line-wise selection (entire lines)
  let
    startLine =
      min(state.visualSelection.start.line, state.visualSelection.current.line)
    endLine = max(state.visualSelection.start.line, state.visualSelection.current.line)

  # Get text to yank first
  let deletedText = getLineText(buffer, state.visualSelection)

  # Store in register system
  if state.pendingRegister.isSome and state.pendingRegister.get != '\0':
    let regName = state.pendingRegister.get
    if regName.isNamedRegisterName:
      discard state.registers.setNamedRegister(regName, deletedText, true)
    elif regName.isClipboardRegisterName:
      state.registers.setClipboardRegister(deletedText, true)
    else:
      state.registers.setDeletedRegister(deletedText, true)
  else:
    state.registers.setDeletedRegister(deletedText, true)

  # Also update legacy yankRegister for backward compatibility
  state.yankRegister = deletedText
  state.yankIsLine = true

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
      let isMultiLine = selStart.line != selEnd.line

      # Store in register system
      if state.pendingRegister.isSome and state.pendingRegister.get != '\0':
        let regName = state.pendingRegister.get
        if regName.isNamedRegisterName:
          discard state.registers.setNamedRegister(regName, selectedText, false)
        elif regName.isClipboardRegisterName:
          state.registers.setClipboardRegister(selectedText, false)
        else:
          state.registers.setDeletedRegister(selectedText, isMultiLine)
      else:
        state.registers.setDeletedRegister(selectedText, isMultiLine)

      # Also update legacy yankRegister for backward compatibility
      state.yankRegister = selectedText
      state.yankIsLine = false

      let result = buffer.deleteRange(selStart, selEnd)
      if result.isErr:
        # TODO: Show error message to user
        discard
      else:
        # Move cursor to start of deleted range
        state.cursor = selStart

    # Clear pending register
    state.pendingRegister = none(char)

    # Commit transaction
    discard buffer.commitTransaction()

    state.visualSelection.active = false
    state.needsFullRedraw = true
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

    # Save original cursor
    let origCursor = state.cursor

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
    state.needsFullRedraw = true
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

    # Save original cursor
    let origCursor = state.cursor

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
    state.needsFullRedraw = true
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
        let endPos = BufferPosition(line: lineNum, column: max(0, lineText.len - 1))
        if lineText.len > 0:
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
    state.needsFullRedraw = true
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
        let endPos = BufferPosition(line: lineNum, column: max(0, lineText.len - 1))
        if lineText.len > 0:
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
    state.needsFullRedraw = true
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
        let endPos = BufferPosition(line: lineNum, column: max(0, lineText.len - 1))
        if lineText.len > 0:
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
    state.needsFullRedraw = true
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
          # Create replacement string with same length
          let replaceText = $ch.repeat(blockText.len)
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
        if lineText.len > 0:
          # Create replacement string with same length
          let replaceText = $ch.repeat(lineText.len)
          let startPos = BufferPosition(line: lineNum, column: 0)
          let endPos = BufferPosition(line: lineNum, column: max(0, lineText.len - 1))
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
    state.needsFullRedraw = true
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
      state.needsFullRedraw = true
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
    state.needsFullRedraw = true
    state.mode = state.previousMode

# Visual mode movement commands using motion executor

proc visualMoveHome*(buffer: TextBuffer, state: EditorState) =
  ## Move to beginning of line (0/Home) and update selection
  state.cursor.column = 0
  state.visualSelection.current = state.cursor
  state.needsFullRedraw = true

proc visualMoveEnd*(buffer: TextBuffer, state: EditorState) =
  ## Move to end of line ($) and update selection
  let lineLen = buffer.getLine(state.cursor.line).charLen
  if lineLen > 0:
    state.cursor.column = lineLen - 1
  else:
    state.cursor.column = 0
  state.visualSelection.current = state.cursor
  state.needsFullRedraw = true

proc visualMoveFirstNonBlank*(buffer: TextBuffer, state: EditorState) =
  ## Move to first non-whitespace character (^) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.FirstNonBlank, count: 1)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor
  state.needsFullRedraw = true

proc visualMoveFirstLine*(buffer: TextBuffer, state: EditorState) =
  ## Move to first line (gg) and update selection
  state.cursor.line = 0
  state.cursor.column = 0
  state.visualSelection.current = state.cursor
  state.needsFullRedraw = true

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
  state.needsFullRedraw = true

proc visualMoveWord*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Move to next word (w) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.WordForward, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor
  state.needsFullRedraw = true

proc visualMoveWordBack*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Move to previous word (b) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.WordBackward, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor
  state.needsFullRedraw = true

proc visualMoveWordEnd*(buffer: TextBuffer, state: EditorState, count: int = 1) =
  ## Move to end of word (e) and update selection
  let executor = newMotionExecutor(buffer)
  let currentPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
  let cmd = MotionCommand(motion: Motion.WordEnd, count: count)
  let newPos = executor.calculateNewPosition(currentPos, cmd)
  state.cursor.line = newPos.y
  state.cursor.column = newPos.x
  state.visualSelection.current = state.cursor
  state.needsFullRedraw = true

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
  state.needsFullRedraw = true

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
  state.needsFullRedraw = true

proc visualToInsertMode*(buffer: TextBuffer, state: EditorState) =
  ## Switch from visual mode to insert mode (I command)
  ## Moves cursor to the start of the selection (first line, column 0)

  # Move cursor to the start line of selection, column 0
  if state.visualSelection.active:
    let startLine =
      min(state.visualSelection.start.line, state.visualSelection.current.line)
    state.cursor.line = startLine
    state.cursor.column = 0

  # Clear visual selection
  state.visualSelection.active = false
  state.needsFullRedraw = true

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
      deleteBlockSelection(buffer, state)
      # Position cursor at the start of the block
      let startCol =
        min(state.visualSelection.start.column, state.visualSelection.current.column)
      let startLine =
        min(state.visualSelection.start.line, state.visualSelection.current.line)
      state.cursor.line = startLine
      state.cursor.column = startCol
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
    state.needsFullRedraw = true
    state.previousMode = EditorMode.Normal # c always returns to Normal on ESC
    state.mode = EditorMode.Insert

proc visualSwapSelection*(buffer: TextBuffer, state: EditorState) =
  ## Swap the cursor between the start and end of the selection (o command)
  if state.visualSelection.active:
    let temp = state.visualSelection.start
    state.visualSelection.start = state.visualSelection.current
    state.visualSelection.current = temp
    state.cursor = state.visualSelection.current
    state.needsFullRedraw = true

proc visualPaste*(buffer: TextBuffer, state: EditorState) =
  ## Delete selection and paste register content (p/P command)
  if state.visualSelection.active:
    # Get register content
    let regName =
      if state.pendingRegister.isSome and state.pendingRegister.get != '\0':
        state.pendingRegister.get
      else:
        '"' # Default unnamed register

    let pasteText = state.registers.getRegisterContent(regName)
    let isLinewise = state.registers.isRegisterLinewise(regName)

    if pasteText.len == 0:
      # Nothing to paste, just exit visual mode
      state.visualSelection.active = false
      state.needsFullRedraw = true
      state.pendingRegister = none(char)
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

      # Insert paste content
      if isLinewise:
        # Insert as new lines
        let lines = pasteText.split('\n')
        for i, line in lines:
          discard buffer.insert(startLine + i, line)
        state.cursor.line = startLine
        state.cursor.column = 0
      else:
        # Insert paste text as a single line
        discard buffer.insert(startLine, pasteText)
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
    state.pendingRegister = none(char)

    # Commit transaction
    discard buffer.commitTransaction()

    state.visualSelection.active = false
    state.needsFullRedraw = true
    state.statusMessage = ""
    state.mode = state.previousMode
