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

## Configuration mode command handler
##
## This module handles commands specific to Configuration mode.
## Allows users to view and edit configuration settings.

import std/options

import ../[types, configmode, keybindings]

type
  ConfigModeResultKind* = enum
    cmrHandled # Command was handled successfully
    cmrEnterCommand # Enter command mode
    cmrSaveConfig # Save configuration to file
    cmrUnhandled # Command was not handled
    cmrError # Error occurred

  ConfigModeResult* = object
    case kind*: ConfigModeResultKind
    of cmrError:
      errorMessage*: string
    else:
      discard

  ConfigModeHandler* = ref object ## Handler for Configuration mode specific commands
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

proc newConfigModeHandler*(): ConfigModeHandler =
  ## Create a new Configuration mode handler
  ConfigModeHandler(waitingForG: false)

proc handleEditModeKey(
    configState: ConfigModeState, keyCombo: KeyCombo
): ConfigModeResult =
  ## Handle key press while in edit mode (editing Int or String value)
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      # Confirm edit
      discard configState.confirmEdit()
      return ConfigModeResult(kind: cmrHandled)
    of skEscape:
      # Cancel edit
      configState.cancelEdit()
      return ConfigModeResult(kind: cmrHandled)
    of skBackspace:
      configState.editBackspace()
      return ConfigModeResult(kind: cmrHandled)
    of skDelete:
      configState.editDelete()
      return ConfigModeResult(kind: cmrHandled)
    of skLeft:
      configState.editMoveCursorLeft()
      return ConfigModeResult(kind: cmrHandled)
    of skRight:
      configState.editMoveCursorRight()
      return ConfigModeResult(kind: cmrHandled)
    of skHome:
      configState.editMoveCursorHome()
      return ConfigModeResult(kind: cmrHandled)
    of skEnd:
      configState.editMoveCursorEnd()
      return ConfigModeResult(kind: cmrHandled)
    else:
      return ConfigModeResult(kind: cmrHandled) # Ignore other special keys
  else:
    # Insert character
    if keyCombo.char.len > 0 and keyCombo.modifiers == {}:
      configState.editInsertChar(keyCombo.char)
    return ConfigModeResult(kind: cmrHandled)

proc handleEnumPopupKey(
    configState: ConfigModeState, keyCombo: KeyCombo
): ConfigModeResult =
  ## Handle key press while enum popup is open
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      configState.enumPopupConfirm()
      return ConfigModeResult(kind: cmrHandled)
    of skEscape:
      configState.closeEnumPopup()
      return ConfigModeResult(kind: cmrHandled)
    of skUp:
      configState.enumPopupMoveUp()
      return ConfigModeResult(kind: cmrHandled)
    of skDown:
      configState.enumPopupMoveDown()
      return ConfigModeResult(kind: cmrHandled)
    of skTab:
      configState.enumPopupMoveDown()
      return ConfigModeResult(kind: cmrHandled)
    of skBackTab:
      configState.enumPopupMoveUp()
      return ConfigModeResult(kind: cmrHandled)
    else:
      return ConfigModeResult(kind: cmrHandled)
  else:
    case keyCombo.char
    of "j":
      configState.enumPopupMoveDown()
      return ConfigModeResult(kind: cmrHandled)
    of "k":
      configState.enumPopupMoveUp()
      return ConfigModeResult(kind: cmrHandled)
    of " ", "l":
      configState.enumPopupConfirm()
      return ConfigModeResult(kind: cmrHandled)
    of "h":
      configState.closeEnumPopup()
      return ConfigModeResult(kind: cmrHandled)
    else:
      return ConfigModeResult(kind: cmrHandled)

proc handleConfigModeKey*(
    handler: ConfigModeHandler,
    configState: ConfigModeState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): ConfigModeResult =
  ## Handle a key press in Configuration mode
  ##
  ## Returns a ConfigModeResult indicating what action should be taken

  # If in edit mode, handle separately
  if configState.isEditing():
    return handleEditModeKey(configState, keyCombo)

  # If enum popup is open, handle separately
  if configState.isEnumPopupOpen():
    return handleEnumPopupKey(configState, keyCombo)

  # Handle 'gg' command (two g presses)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      configState.moveToFirst()
      return ConfigModeResult(kind: cmrHandled)
    # If not 'g', fall through to normal handling

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      # Edit the value
      let item = configState.getSelectedItem()
      if item.isSome:
        case item.get.kind
        of cvkSection:
          discard # Section headers are not interactive
        of cvkBool:
          configState.toggleBoolValue()
        of cvkEnum:
          configState.openEnumPopup()
        of cvkInt, cvkFloat, cvkString:
          # Start edit mode for Int, Float and String
          configState.startEdit()
      return ConfigModeResult(kind: cmrHandled)
    of skUp:
      configState.moveUp()
      configState.ensureSelectedVisible(viewportHeight)
      return ConfigModeResult(kind: cmrHandled)
    of skDown:
      configState.moveDown()
      configState.ensureSelectedVisible(viewportHeight)
      return ConfigModeResult(kind: cmrHandled)
    of skLeft:
      # Cycle enum backward or decrement int/float
      let item = configState.getSelectedItem()
      if item.isSome:
        case item.get.kind
        of cvkEnum:
          configState.cycleEnumValue(false)
        of cvkInt:
          configState.decrementIntValue()
        of cvkFloat:
          configState.decrementFloatValue()
        else:
          discard
      return ConfigModeResult(kind: cmrHandled)
    of skRight:
      # Cycle enum forward or increment int/float
      let item = configState.getSelectedItem()
      if item.isSome:
        case item.get.kind
        of cvkEnum:
          configState.cycleEnumValue(true)
        of cvkInt:
          configState.incrementIntValue()
        of cvkFloat:
          configState.incrementFloatValue()
        of cvkBool:
          configState.toggleBoolValue()
        else:
          discard
      return ConfigModeResult(kind: cmrHandled)
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        configState.moveDown()
      configState.ensureSelectedVisible(viewportHeight)
      return ConfigModeResult(kind: cmrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      let halfPage = max(1, viewportHeight div 2)
      for i in 0 ..< halfPage:
        configState.moveUp()
      configState.ensureSelectedVisible(viewportHeight)
      return ConfigModeResult(kind: cmrHandled)

    case keyCombo.char
    of ":":
      return ConfigModeResult(kind: cmrEnterCommand)
    of "j":
      configState.moveDown()
      configState.ensureSelectedVisible(viewportHeight)
      return ConfigModeResult(kind: cmrHandled)
    of "k":
      configState.moveUp()
      configState.ensureSelectedVisible(viewportHeight)
      return ConfigModeResult(kind: cmrHandled)
    of "g":
      # Start waiting for second 'g'
      handler.waitingForG = true
      return ConfigModeResult(kind: cmrHandled)
    of "G":
      configState.moveToLast()
      configState.ensureSelectedVisible(viewportHeight)
      return ConfigModeResult(kind: cmrHandled)
    of "l", " ":
      # Edit/toggle value
      let item = configState.getSelectedItem()
      if item.isSome:
        case item.get.kind
        of cvkSection:
          discard # Section headers are not interactive
        of cvkBool:
          configState.toggleBoolValue()
        of cvkEnum:
          configState.openEnumPopup()
        of cvkInt, cvkFloat, cvkString:
          # Start edit mode for Int, Float and String
          configState.startEdit()
      return ConfigModeResult(kind: cmrHandled)
    of "h":
      # Cycle backward / decrement
      let item = configState.getSelectedItem()
      if item.isSome:
        case item.get.kind
        of cvkEnum:
          configState.cycleEnumValue(false)
        of cvkInt:
          configState.decrementIntValue()
        of cvkFloat:
          configState.decrementFloatValue()
        else:
          discard
      return ConfigModeResult(kind: cmrHandled)
    of "w", "W":
      # Save config
      return ConfigModeResult(kind: cmrSaveConfig)
    else:
      discard

  return ConfigModeResult(kind: cmrUnhandled)
