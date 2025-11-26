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

import ../[buffer, types, cursor, registers]

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
    let (selStart, selEnd) =
      if state.visualSelection.start.line < state.visualSelection.current.line:
        (state.visualSelection.start, state.visualSelection.current)
      elif state.visualSelection.start.line > state.visualSelection.current.line:
        (state.visualSelection.current, state.visualSelection.start)
      else:
        # Same line - compare columns
        if state.visualSelection.start.column <= state.visualSelection.current.column:
          (state.visualSelection.start, state.visualSelection.current)
        else:
          (state.visualSelection.current, state.visualSelection.start)

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
      let (selStart, selEnd) =
        if state.visualSelection.start.line < state.visualSelection.current.line:
          (state.visualSelection.start, state.visualSelection.current)
        elif state.visualSelection.start.line > state.visualSelection.current.line:
          (state.visualSelection.current, state.visualSelection.start)
        else:
          # Same line - compare columns
          if state.visualSelection.start.column <= state.visualSelection.current.column:
            (state.visualSelection.start, state.visualSelection.current)
          else:
            (state.visualSelection.current, state.visualSelection.start)

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
