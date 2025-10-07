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

import pkg/results

import ../[buffer, cursor, modes, types, keybindings, commandregistry]

type
  VisualModeResultKind* = enum
    vmrHandled
    vmrUnhandled
    vmrError

  VisualModeHandler* = ref object ## Handler for Visual mode operations
    keyBindingRegistry*: KeyBindingRegistry
    commandRegistry*: CommandRegistry

  VisualModeResult* = object ## Result of visual mode command execution
    case kind*: VisualModeResultKind
    of vmrHandled:
      modeTransition*: Option[EditorMode]
    of vmrUnhandled:
      discard
    of vmrError:
      errorMessage*: string

proc newVisualModeHandler*(
    keyBindingRegistry: KeyBindingRegistry, commandRegistry: CommandRegistry
): VisualModeHandler =
  ## Create a new Visual mode handler
  VisualModeHandler(
    keyBindingRegistry: keyBindingRegistry, commandRegistry: commandRegistry
  )

proc initSelection*(state: EditorState, buffer: TextBuffer) =
  ## Initialize visual selection at current cursor position
  let cursorPos = state.cursor
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

proc executeCommand*(
    handler: VisualModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    commandId: string,
    args: seq[string] = @[],
): VisualModeResult =
  ## Execute a command using the CommandRegistry
  let ctx = CommandContext(
    buffer: buffer,
    state: state,
    viewport: viewport,
    motionController: nil, # Visual mode doesn't use motion controller
    keyBindingRegistry: handler.keyBindingRegistry,
  )

  let r = handler.commandRegistry.execute(ctx, commandId, args)
  if r.isOk:
    # Check if mode changed
    let modeTransition =
      if state.mode != EditorMode.Visual:
        some(state.mode)
      else:
        none(EditorMode)
    return VisualModeResult(kind: vmrHandled, modeTransition: modeTransition)
  else:
    return VisualModeResult(kind: vmrError, errorMessage: r.error)

proc handleVisualModeKey*(
    handler: VisualModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): VisualModeResult =
  ## Main entry point for handling Visual mode key presses

  # Special handling for ESC to clear selection
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    state.clearSelection()

  # Try to find a binding for this key
  let binding = handler.keyBindingRegistry.findBinding(EditorMode.Visual, keyCombo)

  if binding.isNone:
    return VisualModeResult(kind: vmrUnhandled)

  let cmd = binding.get

  # Create command context
  let ctx = CommandContext(
    buffer: buffer,
    state: state,
    viewport: viewport,
    motionController: nil, # Visual mode doesn't use motion controller
    keyBindingRegistry: handler.keyBindingRegistry,
  )

  # Execute command through registry
  let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)

  if cmdResult.isErr:
    return VisualModeResult(kind: vmrError, errorMessage: cmdResult.error)

  # Check for mode transition
  let modeTransition =
    if state.mode != EditorMode.Visual:
      some(state.mode)
    else:
      none(EditorMode)

  return VisualModeResult(kind: vmrHandled, modeTransition: modeTransition)
