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

import std/[unittest, strutils]

import ../src/moepkg/[types, key_bindings, config_mode, config]
import ../src/moepkg/command_handlers/config_handler

proc createTestConfigState(): ConfigModeState =
  ## Create a minimal ConfigModeState for testing
  let config = newEditorConfig()
  result = newConfigModeState(config)

proc createTestEditorState(): EditorState =
  ## Minimal EditorState for tests that only need a valid config and
  ## statusMessage sink to satisfy handler signatures.
  EditorState(config: newEditorConfig())

suite "ConfigModeState - Key Sequence Flags":
  test "fresh ConfigModeState has key-sequence flags reset":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    check configState.waitingForG == false
    check configState.lastKeyWasEscape == false

suite "config_handler: Result Types":
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

suite "config_handler: Navigation":
  test "Move down with j":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let initialIndex = configState.selectedIndex

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == initialIndex + 1

  test "Move up with k":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    # Move down first to have room to move up
    configState.moveDown()
    let initialIndex = configState.selectedIndex

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == initialIndex - 1

  test "Move down with Down arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let initialIndex = configState.selectedIndex

    let keyCombo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == initialIndex + 1

  test "Move up with Up arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    configState.moveDown()
    let initialIndex = configState.selectedIndex

    let keyCombo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == initialIndex - 1

  test "Move to last with G":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    let keyCombo = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrHandled
    check configState.selectedIndex == configState.items.len - 1

  test "Move to first with gg":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    # Move to end first
    configState.moveToLast()

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result1 = handleConfigModeKey(configState, editorState, 24, keyCombo1)

    check result1.kind == cmrHandled
    check configState.waitingForG == true

    # Second 'g' completes the command
    let keyCombo2 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result2 = handleConfigModeKey(configState, editorState, 24, keyCombo2)

    check result2.kind == cmrHandled
    check configState.selectedIndex == 0
    check configState.waitingForG == false

  test "Half page down with Ctrl+d":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let initialIndex = configState.selectedIndex
    let viewportHeight = 20
    let expectedMove = max(1, viewportHeight div 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result = handleConfigModeKey(configState, editorState, viewportHeight, keyCombo)

    check result.kind == cmrHandled
    # Should move down by half page (capped by items count)
    let expectedIndex = min(initialIndex + expectedMove, configState.items.len - 1)
    check configState.selectedIndex == expectedIndex

  test "Half page up with Ctrl+u":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    # Move down first
    configState.moveToLast()
    let initialIndex = configState.selectedIndex
    let viewportHeight = 20
    let expectedMove = max(1, viewportHeight div 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result = handleConfigModeKey(configState, editorState, viewportHeight, keyCombo)

    check result.kind == cmrHandled
    # Should move up by half page
    let expectedIndex = max(0, initialIndex - expectedMove)
    check configState.selectedIndex == expectedIndex

suite "config_handler: Mode Transitions":
  test "Enter command mode with :":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    let keyCombo = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrEnterCommand

suite "config_handler: Boolean Value Editing":
  test "Toggle bool value with Enter":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[boolIndex].boolValue == (not originalValue)

  test "Toggle bool value with Space":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[boolIndex].boolValue == (not originalValue)

  test "Toggle bool value with l":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[boolIndex].boolValue == (not originalValue)

  test "Toggle bool value with Right arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[boolIndex].boolValue == (not originalValue)

suite "config_handler: Int Value Editing":
  test "Increment int value with Right arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue < configState.items[intIndex].intMax:
        check configState.items[intIndex].intValue == originalValue + 1

  test "Decrement int value with Left arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue > configState.items[intIndex].intMin:
        check configState.items[intIndex].intValue == originalValue - 1

  test "Decrement int value with h":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue > configState.items[intIndex].intMin:
        check configState.items[intIndex].intValue == originalValue - 1

  test "Start int edit mode with Enter":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

suite "config_handler: Float Value Editing":
  test "Increment float value with Right arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue + step <= configState.items[floatIndex].floatMax:
        check configState.items[floatIndex].floatValue == originalValue + step

  test "Decrement float value with Left arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue - step >= configState.items[floatIndex].floatMin:
        check configState.items[floatIndex].floatValue == originalValue - step

suite "config_handler: Enum Value Editing":
  test "Cycle enum value forward with Right arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[enumIndex].enumValue == options[expectedIdx]

  test "Cycle enum value backward with Left arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.items[enumIndex].enumValue == options[expectedIdx]

  test "Open enum popup with Enter":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == true

  test "Open enum popup with Space":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    if enumIndex >= 0:
      configState.selectedIndex = enumIndex

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == true

suite "config_handler: Edit Mode":
  test "Cancel edit with Escape":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == false

  test "Confirm edit with Enter":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == false

  test "Insert character in edit mode":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == "5"
      check configState.editCursor == 1

  test "Backspace in edit mode":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == "12"
      check configState.editCursor == 2

  test "Delete in edit mode":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == "13"
      check configState.editCursor == 1

  test "Move cursor left in edit mode":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editCursor == 1

  test "Move cursor right in edit mode":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editCursor == 2

  test "Move cursor to home in edit mode":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editCursor == 0

  test "Move cursor to end in edit mode":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editCursor == 3

suite "config_handler: Enum Popup":
  test "Close enum popup with Escape":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

  test "Confirm enum popup with Enter":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

  test "Move up in enum popup with Up arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      # Should move up or wrap to end
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move down in enum popup with Down arrow":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      # Should move down or wrap to start
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move down in enum popup with j":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move up in enum popup with k":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move down in enum popup with Tab":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Move up in enum popup with BackTab":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.enumPopupIndex != initialPopupIndex or
        configState.items[enumIndex].enumOptions.len == 1

  test "Confirm enum popup with Space":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

  test "Confirm enum popup with l":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

  test "Close enum popup with h":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == false

suite "config_handler: Section Headers":
  test "Enter on section header does nothing":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      # Nothing should happen for section headers
      check configState.isEditing() == false
      check configState.isEnumPopupOpen() == false

suite "config_handler: Waiting for G State":
  test "Waiting for G cancelled on non-g key":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleConfigModeKey(configState, editorState, 24, keyCombo1)
    check configState.waitingForG == true

    # Press something other than 'g'
    let keyCombo2 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo2)

    # waitingForG should be cleared and j should be handled normally
    check configState.waitingForG == false
    check result.kind == cmrHandled

suite "config_handler: Unhandled Keys":
  test "Unhandled special key returns cmrUnhandled":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    # F5 is not handled
    let keyCombo =
      KeyCombo(isSpecial: true, special: skFunction, fnNum: 5, modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrUnhandled

  test "Unhandled character key returns cmrUnhandled":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    # 'z' is not handled
    let keyCombo = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrUnhandled

suite "config_handler: Edit Mode Edge Cases":
  test "Other special key in edit mode is ignored":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == originalBuffer
      check configState.isEditing() == true

  test "Character with modifiers in edit mode is ignored":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == originalBuffer

  test "Empty char in edit mode":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.editBuffer == originalBuffer

suite "config_handler: Enum Popup Edge Cases":
  test "Other special key in enum popup is ignored":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == true
      check configState.enumPopupIndex == originalPopupIndex

  test "Other character in enum popup is ignored":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEnumPopupOpen() == true
      check configState.enumPopupIndex == originalPopupIndex

suite "config_handler: Float Value Editing Extended":
  test "Start float edit mode with Enter":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

  test "Start float edit mode with l":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

  test "Start float edit mode with Space":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var floatIndex = -1
    for i, item in configState.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    if floatIndex >= 0:
      configState.selectedIndex = floatIndex

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

  test "Decrement float value with h":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

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
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      if originalValue - step >= configState.items[floatIndex].floatMin:
        check configState.items[floatIndex].floatValue == originalValue - step

suite "config_handler: Int Value Editing Extended":
  test "Start int edit mode with l":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

  test "Start int edit mode with Space":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var intIndex = -1
    for i, item in configState.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    if intIndex >= 0:
      configState.selectedIndex = intIndex

      let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == true

suite "config_handler: Section Header Edge Cases":
  test "Left arrow on section does nothing":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled

  test "Right arrow on section does nothing":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo =
        KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled

  test "h key on section does nothing":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled

  test "l key on section does nothing":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var sectionIndex = -1
    for i, item in configState.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    if sectionIndex >= 0:
      configState.selectedIndex = sectionIndex

      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      check configState.isEditing() == false
      check configState.isEnumPopupOpen() == false

suite "config_handler: Bool Value Editing Extended":
  test "Left arrow on bool does nothing":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      # Bool value should NOT change with left arrow
      check configState.items[boolIndex].boolValue == originalValue

  test "h key on bool does nothing":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    var boolIndex = -1
    for i, item in configState.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    if boolIndex >= 0:
      configState.selectedIndex = boolIndex
      let originalValue = configState.items[boolIndex].boolValue

      let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
      let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

      check result.kind == cmrHandled
      # Bool value should NOT change with h
      check configState.items[boolIndex].boolValue == originalValue

suite "config_handler: Empty Items Edge Case":
  test "Handle key with empty items list":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    # Clear items to simulate empty state
    configState.items = @[]
    configState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    # Should handle gracefully without crash
    check result.kind == cmrHandled

  test "Navigation with empty items":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()

    configState.items = @[]
    configState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)

    check result.kind == cmrHandled

suite "config_handler: Search":
  test "'/' enters forward search":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let keyCombo = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)
    check result.kind == cmrEnterSearch

  test "'?' enters backward search":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let keyCombo = KeyCombo(isSpecial: false, char: "?", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)
    check result.kind == cmrEnterSearchBackward

  test "'n' repeats search forward":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let keyCombo = KeyCombo(isSpecial: false, char: "n", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)
    check result.kind == cmrHandled

  test "'N' repeats search backward":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let keyCombo = KeyCombo(isSpecial: false, char: "N", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, keyCombo)
    check result.kind == cmrHandled

  test "'n' moves selection to the next match":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    # Find the first editable item and search for its name.
    var idx = -1
    for i, item in configState.items:
      if item.kind != cvkSection:
        idx = i
        break
    check idx >= 0
    configState.setSearchQuery(configState.items[idx].displayName)
    configState.selectedIndex = 0
    let keyCombo = KeyCombo(isSpecial: false, char: "n", modifiers: {})
    discard handleConfigModeKey(configState, editorState, 24, keyCombo)
    check configState.isItemMatched(configState.selectedIndex)

  test "Single Escape is consumed and waits for a second":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let esc = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, esc)
    check result.kind == cmrHandled
    check configState.lastKeyWasEscape

  test "Double Escape requests highlight clear and keeps the query":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    configState.setSearchQuery("lsp")
    let esc = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard handleConfigModeKey(configState, editorState, 24, esc)
    let result = handleConfigModeKey(configState, editorState, 24, esc)
    check result.kind == cmrClearSearchHighlight
    # searchQuery is kept as the match target; display is gated by the global
    # hlsearch flags (set by the dispatcher), not by clearing the query here.
    check configState.hasSearchQuery
    check not configState.lastKeyWasEscape

  test "A non-Escape key resets the Escape counter":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    let esc = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard handleConfigModeKey(configState, editorState, 24, esc)
    check configState.lastKeyWasEscape
    let j = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    discard handleConfigModeKey(configState, editorState, 24, j)
    check not configState.lastKeyWasEscape

  test "'n' returns cmrRepeatSearch when a match is found":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    # A committed query with a match makes n/N request a highlight re-enable.
    var idx = -1
    for i, item in configState.items:
      if item.kind != cvkSection:
        idx = i
        break
    check idx >= 0
    configState.setSearchQuery(configState.items[idx].displayName)
    let n = KeyCombo(isSpecial: false, char: "n", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, n)
    check result.kind == cmrRepeatSearch

  test "'n' returns cmrHandled (not cmrRepeatSearch) without a query":
    # An empty query must not request a gate change — pressing n is a no-op.
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    check not configState.hasSearchQuery
    let n = KeyCombo(isSpecial: false, char: "n", modifiers: {})
    let result = handleConfigModeKey(configState, editorState, 24, n)
    check result.kind == cmrHandled

suite "config_handler: applyColorChange persistence warning":
  proc findFirstColorItem(configState: ConfigModeState): int =
    for i, item in configState.items:
      if item.kind == cvkColor:
        return i
    return -1

  test "tkDefault: warning appears when a color is edited":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    editorState.config.theme.kind = tkDefault
    editorState.statusMessage = ""
    let idx = findFirstColorItem(configState)
    check idx >= 0
    configState.items[idx].colorValue = "#123456"

    configState.applyColorChange(editorState, idx)

    check editorState.statusMessage.len > 0
    check "preview only" in editorState.statusMessage
    check ":theme" in editorState.statusMessage

  test "tkConfig: no warning (edit will persist on :writeconf)":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    editorState.config.theme.kind = tkConfig
    editorState.config.theme.path = "/tmp/moe_test_theme_persist.toml"
    editorState.statusMessage = ""
    let idx = findFirstColorItem(configState)
    check idx >= 0
    configState.items[idx].colorValue = "#654321"

    configState.applyColorChange(editorState, idx)

    check editorState.statusMessage == ""

  test "tkVscode: warning appears (edit will not persist)":
    let configState = createTestConfigState()
    let editorState = createTestEditorState()
    editorState.config.theme.kind = tkVscode
    editorState.statusMessage = ""
    let idx = findFirstColorItem(configState)
    check idx >= 0
    configState.items[idx].colorValue = "#abcdef"

    configState.applyColorChange(editorState, idx)

    check "preview only" in editorState.statusMessage
