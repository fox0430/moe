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

import std/options

import pkg/celina

import editor, keybindings, modes, buffer
import command_handlers/handler_manager

proc handleCommandModeEvent(e: Editor, event: Event): bool =
  ## Handle Command mode events (special handling for text input)
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  let keyCombo = keyComboOpt.get

  # Handle Escape to exit Command mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.state.mode = EditorMode.Normal
    e.state.commandText = ""
    return true

  # Handle Enter to execute command
  let isEnter =
    (keyCombo.isSpecial and keyCombo.special == skEnter) or
    (not keyCombo.isSpecial and (keyCombo.char == '\n' or keyCombo.char == '\r'))

  if isEnter:
    if e.state.commandText.len > 1: # Must have something after :
      # Use the command handler
      let r = e.handlerManager.handleCommandMode(e.textBuffer, e.state.commandText)

      if r.shouldQuit():
        return false # Signal app should quit

      if r.shouldGotoLine():
        # Jump to the specified line
        let lineNum = r.getLineNumber()
        if lineNum > 0 and lineNum <= e.textBuffer.len:
          e.textBuffer.cursor.line = lineNum - 1 # Convert to 0-based
          e.textBuffer.cursor.column = 0

      # Handle mode transitions
      let modeTransition = r.getModeTransition()
      if modeTransition.isSome:
        e.state.mode = modeTransition.get
      else:
        e.state.mode = EditorMode.Normal # Default back to normal

      # Set status message if any
      let statusMsg = r.getStatusMessage()
      if statusMsg.len > 0:
        e.state.statusMessage = statusMsg
    else:
      # Empty command, just return to normal mode
      e.state.mode = EditorMode.Normal

    # Clear command text
    e.state.commandText = ""
    return true

  # Handle Backspace
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    if e.state.commandText.len > 1: # Keep the : prefix
      e.state.commandText = e.state.commandText[0 ..^ 2]
    return true

  # Handle character input
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    e.state.commandText.add(keyCombo.char)
    return true

  # Ignore other special keys
  return true

proc handleEvent*(e: Editor, event: Event): bool =
  ## Main event handler using the new handler manager system

  # Handle Command mode input differently (character by character)
  if e.state.mode == EditorMode.Command:
    return handleCommandModeEvent(e, event)

  # For other modes, use the unified handler manager
  let r = e.handlerManager.handleEvent(e.textBuffer, e.state, e.viewport, event)

  # Process the result
  if r.shouldQuit():
    return false # Signal app should quit

  if r.shouldGotoLine():
    # Jump to the specified line
    let lineNum = r.getLineNumber()
    if lineNum > 0 and lineNum <= e.textBuffer.len:
      e.textBuffer.cursor.line = lineNum - 1 # Convert to 0-based
      e.textBuffer.cursor.column = 0

  # Handle mode transitions
  let modeTransition = r.getModeTransition()
  if modeTransition.isSome:
    e.state.mode = modeTransition.get

  # Set status message if any
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.statusMessage = statusMsg

  return true # Continue running
