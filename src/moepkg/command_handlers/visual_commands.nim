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

import pkg/results

import ../[buffer, types, cursor]

proc visualMoveLeft*(buffer: TextBuffer, state: EditorState) =
  ## Move left in visual mode and update selection
  if buffer.cursor.column > 0:
    buffer.cursor.column -= 1
    state.visualSelection.current = buffer.cursor
    state.needsFullRedraw = true

proc visualMoveRight*(buffer: TextBuffer, state: EditorState) =
  ## Move right in visual mode and update selection
  if buffer.cursor.column < buffer.getCurrentLineLen:
    buffer.cursor.column += 1
    state.visualSelection.current = buffer.cursor
    state.needsFullRedraw = true

proc visualMoveUp*(buffer: TextBuffer, state: EditorState) =
  ## Move up in visual mode and update selection
  if buffer.cursor.line > 0:
    buffer.cursor.line -= 1
    # Clamp cursor to new line length
    let newLineLen = buffer.getCurrentLineLen
    if buffer.cursor.column > newLineLen:
      buffer.cursor.column = newLineLen
    state.visualSelection.current = buffer.cursor
    state.needsFullRedraw = true

proc visualMoveDown*(buffer: TextBuffer, state: EditorState) =
  ## Move down in visual mode and update selection
  if buffer.cursor.line < buffer.len - 1:
    buffer.cursor.line += 1
    # Clamp cursor to new line length
    let newLineLen = buffer.getCurrentLineLen
    if buffer.cursor.column > newLineLen:
      buffer.cursor.column = newLineLen
    state.visualSelection.current = buffer.cursor
    state.needsFullRedraw = true

proc visualDelete*(buffer: TextBuffer, state: EditorState) =
  ## Delete visual selection and return to previous mode
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

    let result = buffer.deleteRange(selStart, selEnd)
    if result.isErr:
      # TODO: Show error message to user
      discard
    else:
      # Move cursor to start of deleted range
      buffer.cursor = selStart
      state.visualSelection.active = false
      state.needsFullRedraw = true
    # Return to previous mode (before entering Visual mode)
    state.mode = state.previousMode
