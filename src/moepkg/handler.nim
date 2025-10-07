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

import pkg/[celina, results]

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

  # Handle Escape to exit Command mode and return to previous mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.state.mode = e.state.previousMode
    e.state.commandText = ""
    return true

  # Handle Enter to execute command
  let isEnter =
    (keyCombo.isSpecial and keyCombo.special == skEnter) or
    (not keyCombo.isSpecial and (keyCombo.char == "\n" or keyCombo.char == "\r"))

  if isEnter:
    if e.state.commandText.len > 1: # Must have something after :
      # Use the command handler with active buffer
      let activeBuffer = e.activeBuffer()
      let r = e.handlerManager.handleCommandMode(activeBuffer, e.state.commandText)

      if r.shouldQuit():
        return false # Signal app should quit

      if r.shouldCloseWindow():
        # Handle window close - may also quit if last window
        let shouldQuit = e.closeWindow
        if shouldQuit:
          return false # Last window closed, quit editor

      if r.shouldGotoLine():
        # Jump to the specified line
        let lineNum = r.getLineNumber()
        if lineNum > 0 and lineNum <= activeBuffer.len:
          e.state.cursor.line = lineNum - 1 # Convert to 0-based
          e.state.cursor.column = 0

      if r.shouldVSplit():
        # Handle vertical split
        let splitResult = e.vsplit(r.getVSplitFilename())
        if splitResult.isErr:
          e.state.statusMessage = "Error: " & splitResult.error

      if r.shouldHSplit():
        # Handle horizontal split
        let splitResult = e.hsplit(r.getHSplitFilename())
        if splitResult.isErr:
          e.state.statusMessage = "Error: " & splitResult.error

      if r.shouldSetMultiStatusLine():
        # Handle multi status line setting
        e.setMultiStatusLine(r.getMultiStatusLineEnabled())

      # Handle mode transitions
      let modeTransition = r.getModeTransition()
      if modeTransition.isSome:
        e.state.previousMode = e.state.mode
        e.state.mode = modeTransition.get
      else:
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Normal # Default back to normal

      # Set status message if any
      let statusMsg = r.getStatusMessage()
      if statusMsg.len > 0:
        e.state.statusMessage = statusMsg
    else:
      # Empty command, just return to previous mode
      e.state.mode = e.state.previousMode

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

  # Check for Vim-style Ctrl-w prefix for window commands
  if e.state.mode == EditorMode.Normal and event.kind == EventKind.Key:
    let keyComboOpt = eventToKeyCombo(event)
    if keyComboOpt.isSome:
      let keyCombo = keyComboOpt.get

      # Check if we're in window command mode (waiting for second key after Ctrl-w)
      if e.state.command == "window_cmd":
        e.state.command = "" # Reset command state

        # Handle second key: j (down/prev) or k (up/next)
        if not keyCombo.isSpecial:
          if keyCombo.char == "j":
            e.switchToPrevWindow
            return true
          elif keyCombo.char == "k":
            e.switchToNextWindow
            return true
          else:
            # Unknown window command, just cancel
            return true

      # Check for Ctrl-w to enter window command mode
      if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers:
        if keyCombo.char == "w":
          e.state.command = "window_cmd"
          e.state.statusMessage = "-- (window) --"
          return true

  # For other modes, use the unified handler manager with active buffer
  let activeBuffer = e.activeBuffer

  # Get the active viewport if in split mode and sync with motion controller
  var activeViewport = e.viewport
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    activeViewport = e.windowManager.windows[e.windowManager.activeWindowIndex].viewport
    # Sync the motion controller's viewport with the active window's viewport
    e.executer.motionController.viewportManager.viewport = activeViewport

    # Set reserved lines for viewport calculations
    # Find the maximum bottom Y coordinate to determine bottom windows
    var maxBottomY = 0
    for window in e.windowManager.windows:
      let bottomY = window.viewport.y + window.viewport.height
      if bottomY > maxBottomY:
        maxBottomY = bottomY

    # A window is a bottom window if its bottom edge is at the maximum bottom Y
    let
      activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
      windowBottomY = activeWindow.viewport.y + activeWindow.viewport.height
      isBottomWindow = (windowBottomY == maxBottomY)

    e.state.viewportReservedLines =
      if isBottomWindow and e.state.showStatusLine: 2 else: 0
  else:
    # Single window mode - use default calculation
    e.state.viewportReservedLines = if e.state.showStatusLine: 2 else: 1

  let r = e.handlerManager.handleEvent(activeBuffer, e.state, activeViewport, event)

  # Sync viewport back from motion controller to active window
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.windowManager.windows[e.windowManager.activeWindowIndex].viewport =
      e.executer.motionController.viewportManager.viewport

  # Process the result
  if r.shouldQuit():
    return false # Signal app should quit

  if r.shouldGotoLine():
    # Jump to the specified line
    let lineNum = r.getLineNumber()
    if lineNum > 0 and lineNum <= activeBuffer.len:
      e.state.cursor.line = lineNum - 1 # Convert to 0-based
      e.state.cursor.column = 0

  # Handle mode transitions
  let modeTransition = r.getModeTransition()
  if modeTransition.isSome:
    e.state.previousMode = e.state.mode
    e.state.mode = modeTransition.get

  # Set status message if any
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.statusMessage = statusMsg

  return true # Continue running
