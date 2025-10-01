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

## Visual mode handler
##
## This module handles visual selection and provides the core selection
## functionality for Visual mode

import std/options

import ../[buffer, cursor, modes, types, keybindings]

type VisualModeHandler* = ref object ## Handler for Visual mode operations (stateless)

proc newVisualModeHandler*(): VisualModeHandler =
  ## Create a new Visual mode handler
  VisualModeHandler()

proc initSelection*(state: EditorState, buffer: TextBuffer) =
  ## Initialize visual selection at current cursor position
  let cursorPos = buffer.cursor
  state.visualSelection =
    VisualSelection(start: cursorPos, current: cursorPos, active: true)

proc clearSelection*(state: EditorState) =
  ## Clear the visual selection
  state.visualSelection.active = false

proc updateSelection*(state: EditorState, newPos: BufferPosition) =
  ## Update the current end of the selection
  if state.visualSelection.active:
    state.visualSelection.current = newPos

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

proc isPositionInSelection*(selection: VisualSelection, pos: BufferPosition): bool =
  ## Check if a position is within the current selection
  if not selection.active:
    return false

  let (selStart, selEnd) = selection.getSelectionRange()

  # Check if position is within range
  if pos.line < selStart.line or pos.line > selEnd.line:
    return false

  if pos.line == selStart.line and pos.line == selEnd.line:
    # Selection is on a single line
    return pos.column >= selStart.column and pos.column <= selEnd.column
  elif pos.line == selStart.line:
    # Position is on start line
    return pos.column >= selStart.column
  elif pos.line == selEnd.line:
    # Position is on end line
    return pos.column <= selEnd.column
  else:
    # Position is on a middle line
    return true

proc handleVisualModeInput*(
    handler: VisualModeHandler,
    state: EditorState,
    buffer: TextBuffer,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): ModeTransition =
  ## Handle input in Visual mode
  ## Returns mode transition if mode should change
  ## NOTE: Actual command logic is in commandregistry.nim to avoid circular dependencies

  if keyCombo.isSpecial and keyCombo.special == skEscape:
    # Handle ESC key
    state.clearSelection()
    return ModeTransition(newMode: some(state.previousMode), handled: true)

  if keyCombo.isSpecial or keyCombo.modifiers != {}:
    # Only handle regular character keys for movement
    return ModeTransition(newMode: none(EditorMode), handled: false)

  # Simple key mapping - delegates to command registry via handler_manager
  case keyCombo.char
  of 'h', 'l', 'j', 'k':
    # Movement keys - handled
    return ModeTransition(newMode: none(EditorMode), handled: true)
  of 'd', 'x':
    # Delete - switches mode
    return ModeTransition(newMode: some(state.previousMode), handled: true)
  else:
    # Unhandled key
    return ModeTransition(newMode: none(EditorMode), handled: false)
