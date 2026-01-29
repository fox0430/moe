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

## Tests for config_handler.nim

import std/[unittest, options, tables]

import ../src/moepkg/cursor {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/keybindings {.all.}
import ../src/moepkg/configmode {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/command_handlers/config_handler {.all.}

proc createTestConfigState(): ConfigModeState =
  ## Create a minimal ConfigModeState for testing
  let config = newEditorConfig()
  result = newConfigModeState(config)

suite "ConfigModeHandler - Constructor":
  test "Create ConfigModeHandler":
    let handler = newConfigModeHandler()

    check handler != nil
    check handler.waitingForG == false

suite "ConfigModeHandler - Result Types":
  test "cmrHandled result":
    let result = ConfigModeResult(kind: cmrHandled)
    check result.kind == cmrHandled

  test "cmrEnterCommand result":
    let result = ConfigModeResult(kind: cmrEnterCommand)
    check result.kind == cmrEnterCommand

  test "cmrSaveConfig result":
    let result = ConfigModeResult(kind: cmrSaveConfig)
    check result.kind == cmrSaveConfig

  test "cmrUnhandled result":
    let result = ConfigModeResult(kind: cmrUnhandled)
    check result.kind == cmrUnhandled

  test "cmrError result with message":
    let result = ConfigModeResult(kind: cmrError, errorMessage: "test error")
    check result.kind == cmrError
    check result.errorMessage == "test error"

suite "ConfigModeHandler - Navigation":
  test "Move down with j":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()
    let initialIndex = configState.selectedIndex

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == initialIndex + 1

  test "Move up with k":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()
    # Move down first to have room to move up
    configState.moveDown()
    let initialIndex = configState.selectedIndex

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == initialIndex - 1

  test "Move down with Down arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()
    let initialIndex = configState.selectedIndex

    let keyCombo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == initialIndex + 1

  test "Move up with Up arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()
    configState.moveDown()
    let initialIndex = configState.selectedIndex

    let keyCombo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == initialIndex - 1

  test "Move to last with G":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    let keyCombo = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == configState.items.len - 1

  test "Move to first with gg":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()
    # Move to end first
    configState.moveToLast()

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result1 = handler.handleConfigModeKey(configState, 24, keyCombo1)

    check result1.kind == cmrHandled
    check handler.waitingForG == true

    # Second 'g' completes the command
    let keyCombo2 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result2 = handler.handleConfigModeKey(configState, 24, keyCombo2)

    check result2.kind == cmrHandled
    check configState.selectedIndex == 0
    check handler.waitingForG == false

  test "Half page down with Ctrl+d":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()
    let initialIndex = configState.selectedIndex
    let viewportHeight = 20
    let expectedMove = max(1, viewportHeight div 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result = handler.handleConfigModeKey(configState, viewportHeight, keyCombo)

    check result.kind == cmrHandled
    # Should move down by half page (capped by items count)
    let expectedIndex = min(initialIndex + expectedMove, configState.items.len - 1)
    check configState.selectedIndex == expectedIndex

  test "Half page up with Ctrl+u":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()
    # Move down first
    configState.moveToLast()
    let initialIndex = configState.selectedIndex
    let viewportHeight = 20
    let expectedMove = max(1, viewportHeight div 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result = handler.handleConfigModeKey(configState, viewportHeight, keyCombo)

    check result.kind == cmrHandled
    # Should move up by half page
    let expectedIndex = max(0, initialIndex - expectedMove)
    check configState.selectedIndex == expectedIndex

suite "ConfigModeHandler - Mode Transitions":
  test "Enter command mode with :":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    let keyCombo = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrEnterCommand

  test "Save config with w":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    let keyCombo = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrSaveConfig

  test "Save config with W":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    let keyCombo = KeyCombo(isSpecial: false, char: "W", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrSaveConfig

suite "ConfigModeHandler - Boolean Value Editing":
  test "Toggle bool value with Enter":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    # Find first bool item
    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[boolIndex].boolValue == (not originalValue)

  test "Toggle bool value with Space":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[boolIndex].boolValue == (not originalValue)

  test "Toggle bool value with l":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[boolIndex].boolValue == (not originalValue)

  test "Toggle bool value with Right arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo =
        KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[boolIndex].boolValue == (not originalValue)

suite "ConfigModeHandler - Int Value Editing":
  test "Increment int value with Right arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      let originalValue = configState.items[intIndex].intValue

      let keyCombo =
        KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue < configState.items[intIndex].intMax:
        check configState.items[intIndex].intValue == originalValue + 1

  test "Decrement int value with Left arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      # Increment first to make sure we can decrement
      configState.incrementIntValue()
      let originalValue = configState.items[intIndex].intValue

      let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue > configState.items[intIndex].intMin:
        check configState.items[intIndex].intValue == originalValue - 1

  test "Decrement int value with h":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.incrementIntValue()
      let originalValue = configState.items[intIndex].intValue

      let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue > configState.items[intIndex].intMin:
        check configState.items[intIndex].intValue == originalValue - 1

  test "Start int edit mode with Enter":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

suite "ConfigModeHandler - Float Value Editing":
  test "Increment float value with Right arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex
      let originalValue = configState.items[floatIndex].floatValue
      let step = configState.items[floatIndex].floatStep

      let keyCombo =
        KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue + step <= configState.items[floatIndex].floatMax:
        check configState.items[floatIndex].floatValue == originalValue + step

  test "Decrement float value with Left arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex
      # Increment first to make sure we can decrement
      configState.incrementFloatValue()
      let originalValue = configState.items[floatIndex].floatValue
      let step = configState.items[floatIndex].floatStep

      let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue - step >= configState.items[floatIndex].floatMin:
        check configState.items[floatIndex].floatValue == originalValue - step

suite "ConfigModeHandler - Enum Value Editing":
  test "Cycle enum value forward with Right arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      let originalValue = configState.items[enumIndex].enumValue
      let options = configState.items[enumIndex].enumOptions
      var currentIdx = options.find(originalValue)
      if currentIdx < 0:
        currentIdx = 0
      let expectedIdx = (currentIdx + 1) mod options.len

      let keyCombo =
        KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[enumIndex].enumValue == options[expectedIdx]

  test "Cycle enum value backward with Left arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      let originalValue = configState.items[enumIndex].enumValue
      let options = configState.items[enumIndex].enumOptions
      var currentIdx = options.find(originalValue)
      if currentIdx < 0:
        currentIdx = 0
      let expectedIdx = (currentIdx - 1 + options.len) mod options.len

      let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[enumIndex].enumValue == options[expectedIdx]

  test "Open enum popup with Enter":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == true

  test "Open enum popup with Space":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == true

suite "ConfigModeHandler - Edit Mode":
  test "Cancel edit with Escape":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    # Find int item and start editing
    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      check configState.isEditing() == true

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == false

  test "Confirm edit with Enter":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      check configState.isEditing() == true

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == false

  test "Insert character in edit mode":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = ""
      configState.editCursor = 0

      let keyCombo = KeyCombo(isSpecial: false, char: "5", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == "5"
      check configState.editCursor == 1

  test "Backspace in edit mode":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      configState.editCursor = 3

      let keyCombo =
        KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == "12"
      check configState.editCursor == 2

  test "Delete in edit mode":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      configState.editCursor = 1

      let keyCombo =
        KeyCombo(isSpecial: true, special: skDelete, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == "13"
      check configState.editCursor == 1

  test "Move cursor left in edit mode":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      configState.editCursor = 2

      let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editCursor == 1

  test "Move cursor right in edit mode":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      configState.editCursor = 1

      let keyCombo =
        KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editCursor == 2

  test "Move cursor to home in edit mode":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      configState.editCursor = 2

      let keyCombo = KeyCombo(isSpecial: true, special: skHome, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editCursor == 0

  test "Move cursor to end in edit mode":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      configState.editCursor = 1

      let keyCombo = KeyCombo(isSpecial: true, special: skEnd, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editCursor == 3

suite "ConfigModeHandler - Enum Popup":
  test "Close enum popup with Escape":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      check configState.isEnumPopupOpen() == true

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

  test "Confirm enum popup with Enter":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      check configState.isEnumPopupOpen() == true

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

  test "Move up in enum popup with Up arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      configState.enumPopupMoveDown() # Move down first
      let initialPopupIndex = configState.enumPopupIndex

      let keyCombo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      # Should move up or wrap to end
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move down in enum popup with Down arrow":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      let initialPopupIndex = configState.enumPopupIndex

      let keyCombo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      # Should move down or wrap to start
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move down in enum popup with j":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      let initialPopupIndex = configState.enumPopupIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move up in enum popup with k":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      configState.enumPopupMoveDown()
      let initialPopupIndex = configState.enumPopupIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move down in enum popup with Tab":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      let initialPopupIndex = configState.enumPopupIndex

      let keyCombo = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move up in enum popup with BackTab":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      configState.enumPopupMoveDown()
      let initialPopupIndex = configState.enumPopupIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skBackTab, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Confirm enum popup with Space":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      check configState.isEnumPopupOpen() == true

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

  test "Confirm enum popup with l":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      check configState.isEnumPopupOpen() == true

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

  test "Close enum popup with h":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      check configState.isEnumPopupOpen() == true

      let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

suite "ConfigModeHandler - Section Headers":
  test "Enter on section header does nothing":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    # First item should be a section
    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      # Nothing should happen for section headers
      check configState.isEditing() == false
      check configState.isEnumPopupOpen() == false

suite "ConfigModeHandler - Waiting for G State":
  test "Waiting for G cancelled on non-g key":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handler.handleConfigModeKey(configState, 24, keyCombo1)
    check handler.waitingForG == true

    # Press something other than 'g'
    let keyCombo2 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo2)

    # waitingForG should be cleared and j should be handled normally
    check handler.waitingForG == false
    check result.kind == cmrHandled

suite "ConfigModeHandler - Unhandled Keys":
  test "Unhandled special key returns cmrUnhandled":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    # F5 is not handled
    let keyCombo =
      KeyCombo(isSpecial: true, special: skFunction, fnNum: 5, modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrUnhandled

  test "Unhandled character key returns cmrUnhandled":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    # 'z' is not handled
    let keyCombo = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrUnhandled

suite "ConfigModeHandler - Edit Mode Edge Cases":
  test "Other special key in edit mode is ignored":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      let originalBuffer = configState.editBuffer

      # PageUp should be ignored
      let keyCombo =
        KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == originalBuffer
      check configState.isEditing() == true

  test "Character with modifiers in edit mode is ignored":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      configState.editCursor = 3
      let originalBuffer = configState.editBuffer

      # Ctrl+a should not insert anything
      let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {kmCtrl})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == originalBuffer

  test "Empty char in edit mode":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex
      configState.startEdit()
      configState.editBuffer = "123"
      let originalBuffer = configState.editBuffer

      let keyCombo = KeyCombo(isSpecial: false, char: "", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == originalBuffer

suite "ConfigModeHandler - Enum Popup Edge Cases":
  test "Other special key in enum popup is ignored":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      let originalPopupIndex = configState.enumPopupIndex

      # PageDown should be ignored
      let keyCombo =
        KeyCombo(isSpecial: true, special: skPageDown, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == true
      check configState.enumPopupIndex == originalPopupIndex

  test "Other character in enum popup is ignored":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex
      configState.openEnumPopup()
      let originalPopupIndex = configState.enumPopupIndex

      # 'x' should be ignored
      let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == true
      check configState.enumPopupIndex == originalPopupIndex

suite "ConfigModeHandler - Float Value Editing Extended":
  test "Start float edit mode with Enter":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

  test "Start float edit mode with l":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

  test "Start float edit mode with Space":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

  test "Decrement float value with h":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex
      configState.incrementFloatValue()
      let originalValue = configState.items[floatIndex].floatValue
      let step = configState.items[floatIndex].floatStep

      let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue - step >= configState.items[floatIndex].floatMin:
        check configState.items[floatIndex].floatValue == originalValue - step

suite "ConfigModeHandler - Int Value Editing Extended":
  test "Start int edit mode with l":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

  test "Start int edit mode with Space":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

suite "ConfigModeHandler - Section Header Edge Cases":
  test "Left arrow on section does nothing":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled

  test "Right arrow on section does nothing":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled

  test "h key on section does nothing":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled

  test "l key on section does nothing":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == false
      check configState.isEnumPopupOpen() == false

suite "ConfigModeHandler - Bool Value Editing Extended":
  test "Left arrow on bool does nothing":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      # Bool value should NOT change with left arrow
      check configState.items[boolIndex].boolValue == originalValue

  test "h key on bool does nothing":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
      let result = handler.handleConfigModeKey(configState, 24, keyCombo)

      check result.kind == cmrHandled
      # Bool value should NOT change with h
      check configState.items[boolIndex].boolValue == originalValue

suite "ConfigModeHandler - Empty Items Edge Case":
  test "Handle key with empty items list":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    # Clear items to simulate empty state
    configState.items = @[]
    configState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    # Should handle gracefully without crash
    check result.kind == cmrHandled

  test "Navigation with empty items":
    let handler = newConfigModeHandler()
    let configState = createTestConfigState()

    configState.items = @[]
    configState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handler.handleConfigModeKey(configState, 24, keyCombo)

    check result.kind == cmrHandled
