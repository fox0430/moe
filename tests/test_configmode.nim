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

import std/[unittest, options, os, strutils, sets, tables, importutils]
import ../src/moepkg/[config, color, theme, types]
import ../src/moepkg/config_mode {.all.}
import config_test_helper

proc testEditorState(cfg: EditorConfig): EditorState =
  EditorState(config: cfg)

suite "ConfigMode - ConfigModeState initialization":
  test "newConfigModeState creates valid state":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    check state.selectedIndex == 0
    check state.editMode == false
    check state.editBuffer == ""
    check state.editCursor == 0
    check state.enumPopupOpen == false
    check state.enumPopupIndex == 0
    check state.items.len > 0

  test "buildItemList populates items from config":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Should have section headers and items
    var sectionCount = 0
    var itemCount = 0
    for item in state.items:
      if item.kind == cvkSection: sectionCount.inc else: itemCount.inc

    check sectionCount > 0
    check itemCount > 0

  test "Items have correct depth":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    for item in state.items:
      if item.kind == cvkSection:
        check item.depth == 0
      else:
        check item.depth == 1

suite "ConfigMode - getSelectedItem":
  test "getSelectedItem returns current item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    let item = state.getSelectedItem()
    check item.isSome
    check item.get.displayName == state.items[0].displayName

  test "getSelectedItemIndex returns correct index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    check state.getSelectedItemIndex() == 0

    state.selectedIndex = 5
    check state.getSelectedItemIndex() == 5

  test "getSelectedItem returns none for invalid index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    state.selectedIndex = -1

    check state.getSelectedItem().isNone

suite "ConfigMode - Navigation":
  test "moveDown increments selectedIndex":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.moveDown()
    check state.selectedIndex == 1

  test "moveDown stops at last item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    state.selectedIndex = state.items.len - 1

    state.moveDown()
    check state.selectedIndex == state.items.len - 1

  test "moveUp decrements selectedIndex":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    state.selectedIndex = 5

    state.moveUp()
    check state.selectedIndex == 4

  test "moveUp stops at first item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    state.selectedIndex = 0

    state.moveUp()
    check state.selectedIndex == 0

  test "moveToFirst goes to index 0":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    state.selectedIndex = 10

    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToLast goes to last item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.moveToLast()
    check state.selectedIndex == state.items.len - 1

suite "ConfigMode - Bool value manipulation":
  test "toggleBoolValue toggles bool item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    check boolIndex >= 0
    state.selectedIndex = boolIndex
    let originalValue = state.items[boolIndex].boolValue

    state.toggleBoolValue(testEditorState(cfg))
    check state.items[boolIndex].boolValue == not originalValue

    state.toggleBoolValue(testEditorState(cfg))
    check state.items[boolIndex].boolValue == originalValue

  test "toggleBoolValue does nothing for non-bool item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a section item
    var sectionIndex = -1
    for i, item in state.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    check sectionIndex >= 0
    state.selectedIndex = sectionIndex

    # Should not crash
    state.toggleBoolValue(testEditorState(cfg))

suite "ConfigMode - Int value manipulation":
  test "incrementIntValue increases int item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    check intIndex >= 0
    state.selectedIndex = intIndex
    let originalValue = state.items[intIndex].intValue

    state.incrementIntValue(testEditorState(cfg))
    check state.items[intIndex].intValue == originalValue + 1

  test "decrementIntValue decreases int item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item with value > min
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt and item.intValue > item.intMin:
        intIndex = i
        break

    check intIndex >= 0
    state.selectedIndex = intIndex
    let originalValue = state.items[intIndex].intValue

    state.decrementIntValue(testEditorState(cfg))
    check state.items[intIndex].intValue == originalValue - 1

  test "incrementIntValue respects max boundary":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item and set to max
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    check intIndex >= 0
    state.selectedIndex = intIndex
    state.items[intIndex].intValue = state.items[intIndex].intMax

    state.incrementIntValue(testEditorState(cfg))
    check state.items[intIndex].intValue == state.items[intIndex].intMax

  test "decrementIntValue respects min boundary":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item and set to min
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    check intIndex >= 0
    state.selectedIndex = intIndex
    state.items[intIndex].intValue = state.items[intIndex].intMin

    state.decrementIntValue(testEditorState(cfg))
    check state.items[intIndex].intValue == state.items[intIndex].intMin

suite "ConfigMode - Float value manipulation":
  test "incrementFloatValue increases float item by step":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a float item
    var floatIndex = -1
    for i, item in state.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    check floatIndex >= 0
    state.selectedIndex = floatIndex
    let originalValue = state.items[floatIndex].floatValue
    let step = state.items[floatIndex].floatStep

    state.incrementFloatValue(testEditorState(cfg))
    check state.items[floatIndex].floatValue == originalValue + step

  test "decrementFloatValue decreases float item by step":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a float item with value > min + step
    var floatIndex = -1
    for i, item in state.items:
      if item.kind == cvkFloat and item.floatValue > item.floatMin + item.floatStep:
        floatIndex = i
        break

    check floatIndex >= 0
    state.selectedIndex = floatIndex
    let originalValue = state.items[floatIndex].floatValue
    let step = state.items[floatIndex].floatStep

    state.decrementFloatValue(testEditorState(cfg))
    check state.items[floatIndex].floatValue == originalValue - step

  test "incrementFloatValue respects max boundary":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a float item and set to max
    var floatIndex = -1
    for i, item in state.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    check floatIndex >= 0
    state.selectedIndex = floatIndex
    state.items[floatIndex].floatValue = state.items[floatIndex].floatMax

    state.incrementFloatValue(testEditorState(cfg))
    check state.items[floatIndex].floatValue == state.items[floatIndex].floatMax

  test "decrementFloatValue respects min boundary":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a float item and set to min
    var floatIndex = -1
    for i, item in state.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    check floatIndex >= 0
    state.selectedIndex = floatIndex
    state.items[floatIndex].floatValue = state.items[floatIndex].floatMin

    state.decrementFloatValue(testEditorState(cfg))
    check state.items[floatIndex].floatValue == state.items[floatIndex].floatMin

suite "ConfigMode - Enum value manipulation":
  test "cycleEnumValue forward cycles through options":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    check enumIndex >= 0
    state.selectedIndex = enumIndex
    let item = state.items[enumIndex]
    let originalIdx = item.enumOptions.find(item.enumValue)
    let expectedIdx = (originalIdx + 1) mod item.enumOptions.len

    state.cycleEnumValue(testEditorState(cfg), forward = true)
    check state.items[enumIndex].enumValue == item.enumOptions[expectedIdx]

  test "cycleEnumValue backward cycles through options":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    check enumIndex >= 0
    state.selectedIndex = enumIndex
    let item = state.items[enumIndex]
    let originalIdx = item.enumOptions.find(item.enumValue)
    let expectedIdx = (originalIdx - 1 + item.enumOptions.len) mod item.enumOptions.len

    state.cycleEnumValue(testEditorState(cfg), forward = false)
    check state.items[enumIndex].enumValue == item.enumOptions[expectedIdx]

  test "cycleEnumValue wraps around at end":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    check enumIndex >= 0
    state.selectedIndex = enumIndex

    # Set to last option
    let lastOption = state.items[enumIndex].enumOptions[^1]
    state.items[enumIndex].enumValue = lastOption

    state.cycleEnumValue(testEditorState(cfg), forward = true)
    check state.items[enumIndex].enumValue == state.items[enumIndex].enumOptions[0]

suite "ConfigMode - formatItemForDisplay":
  test "Section item displays with brackets":
    let item = ConfigItem(
      kind: cvkSection,
      displayName: "Standard",
      section: "Standard",
      depth: 0,
      descriptorIndex: -1,
    )

    let result = formatItemForDisplay(item, 20)
    check result == "[Standard]"

  test "Bool item displays name and value":
    let item = ConfigItem(
      kind: cvkBool,
      displayName: "number",
      section: "Standard",
      depth: 1,
      descriptorIndex: 1,
      boolValue: true,
    )

    let result = formatItemForDisplay(item, 20)
    check "number" in result
    check "true" in result

  test "Int item displays name and value":
    let item = ConfigItem(
      kind: cvkInt,
      displayName: "tabStop",
      section: "Standard",
      depth: 1,
      descriptorIndex: 1,
      intValue: 4,
      intMin: 1,
      intMax: 16,
    )

    let result = formatItemForDisplay(item, 20)
    check "tabStop" in result
    check "4" in result

  test "Float item displays name and value":
    let item = ConfigItem(
      kind: cvkFloat,
      displayName: "friction",
      section: "SmoothScroll",
      depth: 1,
      descriptorIndex: 1,
      floatValue: 100.0,
      floatMin: 0.0,
      floatMax: 500.0,
      floatStep: 10.0,
    )

    let result = formatItemForDisplay(item, 20)
    check "friction" in result
    check "100" in result

  test "Enum item displays name and value":
    let item = ConfigItem(
      kind: cvkEnum,
      displayName: "colorMode",
      section: "Standard",
      depth: 1,
      descriptorIndex: 1,
      enumValue: "24bit",
      enumOptions: @["8", "16", "256", "24bit", "none"],
    )

    let result = formatItemForDisplay(item, 20)
    check "colorMode" in result
    check "24bit" in result

suite "ConfigMode - Edit mode for Int":
  test "startEdit initializes edit buffer for int":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    check intIndex >= 0
    state.selectedIndex = intIndex

    state.startEdit()
    check state.editMode == true
    check state.editBuffer == $state.items[intIndex].intValue
    check state.editCursor == state.editBuffer.len

  test "cancelEdit resets edit state":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.cancelEdit()

    check state.editMode == false
    check state.editBuffer == ""
    check state.editCursor == 0

  test "confirmEdit applies valid int value":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "5"
    state.editCursor = 1

    let result = state.confirmEdit(testEditorState(cfg))
    check result == true
    check state.items[intIndex].intValue == 5
    check state.editMode == false

  test "confirmEdit rejects out-of-range int value":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    let originalValue = state.items[intIndex].intValue
    state.startEdit()
    state.editBuffer = "99999" # Out of range

    let result = state.confirmEdit(testEditorState(cfg))
    check result == false
    # Value unchanged after failed edit
    check state.items[intIndex].intValue == originalValue

  test "confirmEdit rejects invalid int input":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    let originalValue = state.items[intIndex].intValue
    state.startEdit()
    state.editBuffer = "abc" # Invalid number

    let result = state.confirmEdit(testEditorState(cfg))
    check result == false
    check state.items[intIndex].intValue == originalValue

suite "ConfigMode - Edit mode for Float":
  test "startEdit initializes edit buffer for float":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a float item
    var floatIndex = -1
    for i, item in state.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    check floatIndex >= 0
    state.selectedIndex = floatIndex

    state.startEdit()
    check state.editMode == true
    check state.editBuffer == $state.items[floatIndex].floatValue
    check state.editCursor == state.editBuffer.len

  test "confirmEdit applies valid float value":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a float item
    var floatIndex = -1
    for i, item in state.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    state.selectedIndex = floatIndex
    state.startEdit()
    state.editBuffer = "50.5"
    state.editCursor = 4

    let result = state.confirmEdit(testEditorState(cfg))
    check result == true
    check state.items[floatIndex].floatValue == 50.5
    check state.editMode == false

  test "confirmEdit rejects out-of-range float value":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a float item
    var floatIndex = -1
    for i, item in state.items:
      if item.kind == cvkFloat:
        floatIndex = i
        break

    state.selectedIndex = floatIndex
    let originalValue = state.items[floatIndex].floatValue
    state.startEdit()
    state.editBuffer = "99999.0" # Out of range

    let result = state.confirmEdit(testEditorState(cfg))
    check result == false
    check state.items[floatIndex].floatValue == originalValue

suite "ConfigMode - Edit buffer manipulation":
  test "editInsertChar inserts at cursor":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "12"
    state.editCursor = 1

    state.editInsertChar("5")
    check state.editBuffer == "152"
    check state.editCursor == 2

  test "editBackspace deletes before cursor":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "123"
    state.editCursor = 2

    state.editBackspace()
    check state.editBuffer == "13"
    check state.editCursor == 1

  test "editBackspace does nothing at start":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "123"
    state.editCursor = 0

    state.editBackspace()
    check state.editBuffer == "123"
    check state.editCursor == 0

  test "editDelete removes at cursor":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "123"
    state.editCursor = 1

    state.editDelete()
    check state.editBuffer == "13"
    check state.editCursor == 1

  test "editDelete does nothing at end":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "123"
    state.editCursor = 3

    state.editDelete()
    check state.editBuffer == "123"
    check state.editCursor == 3

  test "editMoveCursorLeft moves cursor left":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "123"
    state.editCursor = 2

    state.editMoveCursorLeft()
    check state.editCursor == 1

  test "editMoveCursorRight moves cursor right":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "123"
    state.editCursor = 1

    state.editMoveCursorRight()
    check state.editCursor == 2

  test "editMoveCursorHome moves to start":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "123"
    state.editCursor = 2

    state.editMoveCursorHome()
    check state.editCursor == 0

  test "editMoveCursorEnd moves to end":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "123"
    state.editCursor = 1

    state.editMoveCursorEnd()
    check state.editCursor == 3

  test "isEditing returns correct state":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    check state.isEditing() == false

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    check state.isEditing() == true

    state.cancelEdit()
    check state.isEditing() == false

  test "getEditInfo returns buffer and cursor":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editBuffer = "test"
    state.editCursor = 2

    let info = state.getEditInfo()
    check info.buffer == "test"
    check info.cursor == 2

suite "ConfigMode - Multibyte edit buffer":
  # editCursor is a rune index. These guard against byte/rune confusion that
  # corrupted multibyte values (e.g. bookmarkMarker) while editing.
  proc stringEditState(): ConfigModeState =
    let cfg = newEditorConfig()
    result = newConfigModeState(cfg)
    var strIndex = -1
    for i, item in result.items:
      if item.kind == cvkString:
        strIndex = i
        break
    check strIndex >= 0
    result.selectedIndex = strIndex
    result.startEdit()

  test "editInsertChar inserts a multibyte rune at the end":
    let state = stringEditState()
    state.editBuffer = "あ"
    state.editCursor = 1

    state.editInsertChar("い")
    check state.editBuffer == "あい"
    check state.editCursor == 2

  test "editInsertChar inserts between multibyte runes":
    let state = stringEditState()
    state.editBuffer = "あう"
    state.editCursor = 1

    state.editInsertChar("い")
    check state.editBuffer == "あいう"
    check state.editCursor == 2

  test "editInsertChar mixes ascii and multibyte":
    let state = stringEditState()
    state.editBuffer = "a日c"
    state.editCursor = 2

    state.editInsertChar("X")
    check state.editBuffer == "a日Xc"
    check state.editCursor == 3

  test "editBackspace deletes a whole multibyte rune":
    let state = stringEditState()
    state.editBuffer = "あいう"
    state.editCursor = 2

    state.editBackspace()
    check state.editBuffer == "あう"
    check state.editCursor == 1

  test "editBackspace at end deletes the last multibyte rune":
    let state = stringEditState()
    state.editBuffer = "テスト"
    state.editCursor = 3

    state.editBackspace()
    check state.editBuffer == "テス"
    check state.editCursor == 2

  test "editDelete removes a whole multibyte rune at cursor":
    let state = stringEditState()
    state.editBuffer = "あいう"
    state.editCursor = 1

    state.editDelete()
    check state.editBuffer == "あう"
    check state.editCursor == 1

  test "editDelete does nothing past the last rune":
    let state = stringEditState()
    state.editBuffer = "あい"
    state.editCursor = 2

    state.editDelete()
    check state.editBuffer == "あい"
    check state.editCursor == 2

  test "editMoveCursorRight stops at rune length, not byte length":
    let state = stringEditState()
    state.editBuffer = "あい"
    state.editCursor = 0

    state.editMoveCursorRight()
    check state.editCursor == 1
    state.editMoveCursorRight()
    check state.editCursor == 2
    state.editMoveCursorRight()
    check state.editCursor == 2

  test "editMoveCursorEnd uses rune length":
    let state = stringEditState()
    state.editBuffer = "あいう"
    state.editCursor = 0

    state.editMoveCursorEnd()
    check state.editCursor == 3

  test "edit sequence keeps a multibyte value intact":
    let state = stringEditState()
    state.editBuffer = "→"
    state.editMoveCursorEnd()

    state.editInsertChar("☆")
    state.editMoveCursorHome()
    state.editInsertChar("★")
    check state.editBuffer == "★→☆"
    check state.editCursor == 1

suite "ConfigMode - Enum popup":
  test "openEnumPopup opens popup for enum item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    check enumIndex >= 0
    state.selectedIndex = enumIndex

    state.openEnumPopup()
    check state.enumPopupOpen == true
    check state.enumPopupIndex >= 0

  test "openEnumPopup does nothing for non-enum item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    state.selectedIndex = boolIndex
    state.openEnumPopup()
    check state.enumPopupOpen == false

  test "closeEnumPopup resets popup state":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.openEnumPopup()
    state.closeEnumPopup()

    check state.enumPopupOpen == false
    check state.enumPopupIndex == 0

  test "enumPopupMoveUp decrements index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.openEnumPopup()
    state.enumPopupIndex = 2

    state.enumPopupMoveUp()
    check state.enumPopupIndex == 1

  test "enumPopupMoveUp wraps to last at first":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.openEnumPopup()
    state.enumPopupIndex = 0

    state.enumPopupMoveUp()
    check state.enumPopupIndex == state.items[enumIndex].enumOptions.len - 1

  test "enumPopupMoveDown increments index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.openEnumPopup()
    state.enumPopupIndex = 0

    state.enumPopupMoveDown()
    check state.enumPopupIndex == 1

  test "enumPopupMoveDown wraps to first at last":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.openEnumPopup()
    state.enumPopupIndex = state.items[enumIndex].enumOptions.len - 1

    state.enumPopupMoveDown()
    check state.enumPopupIndex == 0

  test "enumPopupConfirm applies selected value":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.openEnumPopup()
    state.enumPopupIndex = 1
    let expectedValue = state.items[enumIndex].enumOptions[1]

    state.enumPopupConfirm(testEditorState(cfg))
    check state.items[enumIndex].enumValue == expectedValue
    check state.enumPopupOpen == false

  test "isEnumPopupOpen returns correct state":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    check state.isEnumPopupOpen() == false

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.openEnumPopup()
    check state.isEnumPopupOpen() == true

    state.closeEnumPopup()
    check state.isEnumPopupOpen() == false

  test "getEnumPopupInfo returns options and index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.openEnumPopup()
    state.enumPopupIndex = 2

    let info = state.getEnumPopupInfo()
    check info.options == state.items[enumIndex].enumOptions
    check info.selectedIndex == 2

suite "ConfigMode - applyChange":
  test "applyChange updates config for bool":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find the "number" bool item (standard.number)
    var numberIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool and item.displayName == "number":
        numberIndex = i
        break

    check numberIndex >= 0
    state.selectedIndex = numberIndex
    let originalValue = cfg.standard.number

    state.toggleBoolValue(testEditorState(cfg))
    check cfg.standard.number == not originalValue

  test "applyChange updates config for lineWrap":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find the "lineWrap" bool item (standard.lineWrap)
    var lineWrapIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool and item.displayName == "lineWrap":
        lineWrapIndex = i
        break

    check lineWrapIndex >= 0
    state.selectedIndex = lineWrapIndex
    check cfg.standard.lineWrap == true

    state.toggleBoolValue(testEditorState(cfg))
    check cfg.standard.lineWrap == false

    state.toggleBoolValue(testEditorState(cfg))
    check cfg.standard.lineWrap == true

  test "applyChange updates config for int":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find the "tabStop" int item
    var tabStopIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt and item.displayName == "tabStop":
        tabStopIndex = i
        break

    check tabStopIndex >= 0
    state.selectedIndex = tabStopIndex
    let originalValue = cfg.standard.tabStop

    state.incrementIntValue(testEditorState(cfg))
    check cfg.standard.tabStop == originalValue + 1

  test "applyChange updates config for shiftWidth":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    var swIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt and item.displayName == "shiftWidth":
        swIndex = i
        break

    check swIndex >= 0
    state.selectedIndex = swIndex
    let originalValue = cfg.standard.shiftWidth

    state.incrementIntValue(testEditorState(cfg))
    check cfg.standard.shiftWidth == originalValue + 1

  test "applyChange updates config for softTabStop":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    var stsIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt and item.displayName == "softTabStop":
        stsIndex = i
        break

    check stsIndex >= 0
    state.selectedIndex = stsIndex
    let originalValue = cfg.standard.softTabStop

    state.incrementIntValue(testEditorState(cfg))
    check cfg.standard.softTabStop == originalValue + 1

  test "applyChange updates config for float":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a float item (friction)
    var frictionIndex = -1
    for i, item in state.items:
      if item.kind == cvkFloat and item.displayName == "friction":
        frictionIndex = i
        break

    check frictionIndex >= 0
    state.selectedIndex = frictionIndex
    let originalValue = cfg.smoothScroll.friction
    let step = state.items[frictionIndex].floatStep

    state.incrementFloatValue(testEditorState(cfg))
    check cfg.smoothScroll.friction == originalValue + step

  test "applyChange updates config for enum":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item (colorMode)
    var colorModeIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum and item.displayName == "colorMode":
        colorModeIndex = i
        break

    check colorModeIndex >= 0
    state.selectedIndex = colorModeIndex

    state.cycleEnumValue(testEditorState(cfg), forward = true)
    # The value should have changed in the config
    check $cfg.standard.colorMode == state.items[colorModeIndex].enumValue

suite "ConfigMode - pendingApply":
  test "pendingApply defaults to false":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    check state.pendingApply == false

  test "toggleBoolValue sets pendingApply":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    var idx = -1
    for i, item in state.items:
      if item.kind == cvkBool and item.displayName == "number":
        idx = i
        break
    check idx >= 0
    state.selectedIndex = idx
    state.toggleBoolValue(testEditorState(cfg))
    check state.pendingApply == true

  test "incrementIntValue sets pendingApply":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    var idx = -1
    for i, item in state.items:
      if item.kind == cvkInt and item.displayName == "tabStop":
        idx = i
        break
    check idx >= 0
    state.selectedIndex = idx
    state.incrementIntValue(testEditorState(cfg))
    check state.pendingApply == true

  test "cycleEnumValue sets pendingApply":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    var idx = -1
    for i, item in state.items:
      if item.kind == cvkEnum and item.displayName == "colorMode":
        idx = i
        break
    check idx >= 0
    state.selectedIndex = idx
    state.cycleEnumValue(testEditorState(cfg), forward = true)
    check state.pendingApply == true

  test "moveDown / moveUp leave pendingApply false":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    state.moveDown()
    state.moveDown()
    state.moveUp()
    check state.pendingApply == false

  test "applyChange on section item leaves pendingApply false":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    var sectionIdx = -1
    for i, item in state.items:
      if item.kind == cvkSection:
        sectionIdx = i
        break
    check sectionIdx >= 0
    state.applyChange(testEditorState(cfg), sectionIdx)
    check state.pendingApply == false

  test "confirmEdit with unchanged value leaves pendingApply false":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    var idx = -1
    for i, item in state.items:
      if item.kind == cvkInt and item.displayName == "tabStop":
        idx = i
        break
    check idx >= 0
    state.selectedIndex = idx
    state.startEdit()
    check state.confirmEdit(testEditorState(cfg)) == true
    check state.pendingApply == false

  test "applyColorChange does not set pendingApply":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    var colorIdx = -1
    for i, item in state.items:
      if item.kind == cvkColor:
        colorIdx = i
        break
    check colorIdx >= 0
    state.items[colorIdx].colorValue = "#ff0000"
    state.applyColorChange(testEditorState(cfg), colorIdx)
    check state.pendingApply == false

suite "ConfigMode - Item coverage":
  test "State contains all value kinds":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    var sectionCount = 0
    var boolCount = 0
    var intCount = 0
    var floatCount = 0
    var enumCount = 0

    for item in state.items:
      case item.kind
      of cvkSection: sectionCount.inc
      of cvkBool: boolCount.inc
      of cvkInt: intCount.inc
      of cvkFloat: floatCount.inc
      of cvkEnum: enumCount.inc
      of cvkString: discard
      of cvkColor: discard

    check sectionCount > 0
    check boolCount > 0
    check intCount > 0
    check floatCount > 0
    check enumCount > 0

  test "All items have valid descriptorIndex":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    for item in state.items:
      if item.kind in {cvkSection, cvkColor}:
        # Sections and theme-color items are built without descriptors.
        check item.descriptorIndex == -1
      else:
        check item.descriptorIndex >= 0

suite "ConfigMode - cfgEnumStrings descriptor":
  # Notification.popupPosition is a `string` field constrained via
  # `{.cfgEnumStrings: [...].}`. The descriptor macro must render it as
  # `cvkEnum` (fixed choice list) rather than `cvkString` (free text) so the
  # UI cannot write values the loader would silently reset on next reload.
  proc findPopupPosition(state: ConfigModeState): int =
    result = -1
    for i, item in state.items:
      if item.section == "Notification" and item.displayName == "popupPosition":
        return i

  test "popupPosition renders as cvkEnum, not cvkString":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)
    let idx = findPopupPosition(state)
    check idx >= 0
    check state.items[idx].kind == cvkEnum
    check state.items[idx].enumOptions ==
      @["bottomRight", "topRight", "topLeft", "bottomLeft"]
    check state.items[idx].enumValue == cfg.notification.popupPosition

  test "cycling popupPosition writes back to the string field":
    let cfg = newEditorConfig()
    cfg.notification.popupPosition = "bottomRight"
    let state = newConfigModeState(cfg)
    let idx = findPopupPosition(state)
    check idx >= 0
    state.selectedIndex = idx
    state.cycleEnumValue(testEditorState(cfg), forward = true)
    check cfg.notification.popupPosition == "topRight"
    check state.items[idx].enumValue == "topRight"

suite "ConfigMode - Edge cases and guard conditions":
  test "startEdit does nothing for bool item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    state.selectedIndex = boolIndex
    state.startEdit()
    check state.editMode == false

  test "startEdit does nothing for section item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a section item
    var sectionIndex = -1
    for i, item in state.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    state.selectedIndex = sectionIndex
    state.startEdit()
    check state.editMode == false

  test "startEdit does nothing for enum item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    state.startEdit()
    check state.editMode == false

  test "startEdit does nothing for invalid index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.selectedIndex = -1
    state.startEdit()
    check state.editMode == false

  test "editInsertChar does nothing when not in edit mode":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.editMode = false
    state.editBuffer = ""
    state.editInsertChar("x")
    check state.editBuffer == ""

  test "editBackspace does nothing when not in edit mode":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.editMode = false
    state.editBuffer = "test"
    state.editCursor = 2
    state.editBackspace()
    check state.editBuffer == "test"

  test "editDelete does nothing when not in edit mode":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.editMode = false
    state.editBuffer = "test"
    state.editCursor = 2
    state.editDelete()
    check state.editBuffer == "test"

  test "editMoveCursorLeft does nothing when not in edit mode":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.editMode = false
    state.editCursor = 5
    state.editMoveCursorLeft()
    check state.editCursor == 5

  test "editMoveCursorLeft stops at position 0":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item and start edit
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editCursor = 0
    state.editMoveCursorLeft()
    check state.editCursor == 0

  test "editMoveCursorRight does nothing when not in edit mode":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.editMode = false
    state.editCursor = 0
    state.editMoveCursorRight()
    check state.editCursor == 0

  test "editMoveCursorRight stops at buffer length":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an int item and start edit
    var intIndex = -1
    for i, item in state.items:
      if item.kind == cvkInt:
        intIndex = i
        break

    state.selectedIndex = intIndex
    state.startEdit()
    state.editCursor = state.editBuffer.len
    state.editMoveCursorRight()
    check state.editCursor == state.editBuffer.len

  test "editMoveCursorHome does nothing when not in edit mode":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.editMode = false
    state.editCursor = 5
    state.editMoveCursorHome()
    check state.editCursor == 5

  test "editMoveCursorEnd does nothing when not in edit mode":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.editMode = false
    state.editCursor = 0
    state.editBuffer = "test"
    state.editMoveCursorEnd()
    check state.editCursor == 0

  test "cycleEnumValue does nothing for non-enum item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    state.selectedIndex = boolIndex
    let originalValue = state.items[boolIndex].boolValue
    state.cycleEnumValue(testEditorState(cfg), forward = true)
    check state.items[boolIndex].boolValue == originalValue

  test "cycleEnumValue does nothing for invalid index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.selectedIndex = -1
    # Should not crash
    state.cycleEnumValue(testEditorState(cfg), forward = true)

  test "incrementIntValue does nothing for non-int item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    state.selectedIndex = boolIndex
    # Should not crash
    state.incrementIntValue(testEditorState(cfg))

  test "decrementIntValue does nothing for non-int item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    state.selectedIndex = boolIndex
    # Should not crash
    state.decrementIntValue(testEditorState(cfg))

  test "incrementFloatValue does nothing for non-float item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    state.selectedIndex = boolIndex
    # Should not crash
    state.incrementFloatValue(testEditorState(cfg))

  test "decrementFloatValue does nothing for non-float item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    state.selectedIndex = boolIndex
    # Should not crash
    state.decrementFloatValue(testEditorState(cfg))

  test "applyChange does nothing for invalid index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Should not crash
    state.applyChange(testEditorState(cfg), -1)
    state.applyChange(testEditorState(cfg), state.items.len + 100)

  test "applyChange does nothing for section item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a section item
    var sectionIndex = -1
    for i, item in state.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    # Should not crash
    state.applyChange(testEditorState(cfg), sectionIndex)

  test "enumPopupMoveUp does nothing when popup is closed":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.enumPopupOpen = false
    state.enumPopupIndex = 2
    state.enumPopupMoveUp()
    check state.enumPopupIndex == 2

  test "enumPopupMoveDown does nothing when popup is closed":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.enumPopupOpen = false
    state.enumPopupIndex = 0
    state.enumPopupMoveDown()
    check state.enumPopupIndex == 0

  test "enumPopupConfirm does nothing when popup is closed":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find an enum item
    var enumIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum:
        enumIndex = i
        break

    state.selectedIndex = enumIndex
    let originalValue = state.items[enumIndex].enumValue
    state.enumPopupOpen = false
    state.enumPopupConfirm(testEditorState(cfg))
    check state.items[enumIndex].enumValue == originalValue

  test "openEnumPopup does nothing for invalid index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.selectedIndex = -1
    state.openEnumPopup()
    check state.enumPopupOpen == false

  test "getEnumPopupInfo returns empty for non-enum item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a bool item
    var boolIndex = -1
    for i, item in state.items:
      if item.kind == cvkBool:
        boolIndex = i
        break

    state.selectedIndex = boolIndex
    let info = state.getEnumPopupInfo()
    check info.options.len == 0
    check info.selectedIndex == 0

  test "getEnumPopupInfo returns empty for invalid index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.selectedIndex = -1
    let info = state.getEnumPopupInfo()
    check info.options.len == 0

  test "getSelectedItemIndex returns -1 for out of bounds index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.selectedIndex = state.items.len + 10
    check state.getSelectedItemIndex() == -1

  test "confirmEdit returns false for invalid index":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    state.selectedIndex = -1
    state.editMode = true
    let result = state.confirmEdit(testEditorState(cfg))
    check result == false
    check state.editMode == false

  test "confirmEdit returns false for non-editable item":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    # Find a section item
    var sectionIndex = -1
    for i, item in state.items:
      if item.kind == cvkSection:
        sectionIndex = i
        break

    state.selectedIndex = sectionIndex
    state.editMode = true
    state.editBuffer = "test"
    let result = state.confirmEdit(testEditorState(cfg))
    check result == false
    check state.editMode == false

suite "ConfigMode - formatItemForDisplay cvkString":
  test "String item displays name and value":
    let item = ConfigItem(
      kind: cvkString,
      displayName: "myString",
      section: "Test",
      depth: 1,
      descriptorIndex: 1,
      stringValue: "hello world",
    )

    let result = formatItemForDisplay(item, 20)
    check "myString" in result
    check "hello world" in result

suite "ConfigMode - Theme section":
  test "Theme section header exists":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    var found = false
    for item in state.items:
      if item.kind == cvkSection and item.displayName == "Theme":
        found = true
        break
    check found

  test "Theme kind enum has correct value":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    var kindIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum and item.section == "Theme" and item.displayName == "kind":
        kindIndex = i
        break

    check kindIndex >= 0
    check state.items[kindIndex].enumValue == $cfg.theme.kind
    check state.items[kindIndex].enumOptions == @["default", "config", "vscode"]

  test "Theme kind enum change applies to config":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    var kindIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum and item.section == "Theme" and item.displayName == "kind":
        kindIndex = i
        break

    check kindIndex >= 0
    state.selectedIndex = kindIndex
    # Use "default" (never fails) so this doesn't depend on VSCode being
    # installed. Failure-revert coverage lives in its own test below.
    state.items[kindIndex].enumValue = "default"
    state.applyChange(testEditorState(cfg), kindIndex)
    check cfg.theme.kind == tkDefault

  test "Theme path string has correct value":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    var pathIndex = -1
    for i, item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        pathIndex = i
        break

    check pathIndex >= 0
    check state.items[pathIndex].stringValue == cfg.theme.path

  test "Theme path string edit applies to config":
    let cfg = newEditorConfig()
    let state = newConfigModeState(cfg)

    var pathIndex = -1
    for i, item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        pathIndex = i
        break

    check pathIndex >= 0
    state.selectedIndex = pathIndex

    # Test editing via startEdit/confirmEdit
    state.startEdit()
    check state.editMode == true
    check state.editBuffer == cfg.theme.path

    # Use a writable temp path so initTheme's bootstrap can seed it and the
    # revert-on-failure guard doesn't roll back a legitimate edit.
    let tmpPath = getTempDir() / "moe_configmode_theme_test.toml"
    defer:
      try:
        removeFile(tmpPath)
      except OSError:
        discard
    state.editBuffer = tmpPath
    state.editCursor = state.editBuffer.len
    let result = state.confirmEdit(testEditorState(cfg))
    check result == true
    check cfg.theme.path == tmpPath

  test "Theme path is visible when kind is config":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)

    var found = false
    for item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        found = true
        break
    check found

  test "Theme path is hidden when kind is default":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkDefault
    let state = newConfigModeState(cfg)

    var found = false
    for item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        found = true
        break
    check not found

  test "Theme path is hidden when kind is vscode":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkVscode
    let state = newConfigModeState(cfg)

    var found = false
    for item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        found = true
        break
    check not found

  test "Changing kind to config shows path":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkDefault
    let state = newConfigModeState(cfg)

    # path should not exist
    var pathFound = false
    for item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        pathFound = true
        break
    check not pathFound

    # Change kind to config
    var kindIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum and item.section == "Theme" and item.displayName == "kind":
        kindIndex = i
        break

    check kindIndex >= 0
    state.selectedIndex = kindIndex
    state.items[kindIndex].enumValue = "config"
    state.applyChange(testEditorState(cfg), kindIndex)

    # Now path should be visible
    pathFound = false
    for item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        pathFound = true
        break
    check pathFound

  test "Theme change reverts on load failure and surfaces status":
    # Point Theme.path at an unwritable location so initTheme's bootstrap
    # (saveThemeToToml) fails; applyChange must roll cfg.theme back to the
    # working baseline and reach statusMessage.
    let workingPath = getTempDir() / "moe_configmode_theme_baseline.toml"
    defer:
      try:
        removeFile(workingPath)
      except OSError:
        discard

    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    cfg.theme.path = workingPath
    let state = newConfigModeState(cfg)

    var pathIndex = -1
    for i, item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        pathIndex = i
        break
    check pathIndex >= 0

    let editorState = testEditorState(cfg)
    editorState.statusMessage = ""
    state.selectedIndex = pathIndex
    # /proc/1/... is unwritable for non-root — createDir fails, so bootstrap fails.
    state.items[pathIndex].stringValue = "/proc/1/moe_theme_should_fail.toml"
    state.applyChange(editorState, pathIndex)

    check cfg.theme.path == workingPath
    check editorState.statusMessage.len > 0
    check "Failed to load theme" in editorState.statusMessage

  test "Changing kind from config hides path":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)

    # path should exist
    var pathFound = false
    for item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        pathFound = true
        break
    check pathFound

    # Change kind to default (never fails, unlike vscode which depends on
    # a working VSCode install being present).
    var kindIndex = -1
    for i, item in state.items:
      if item.kind == cvkEnum and item.section == "Theme" and item.displayName == "kind":
        kindIndex = i
        break

    check kindIndex >= 0
    state.selectedIndex = kindIndex
    state.items[kindIndex].enumValue = "default"
    state.applyChange(testEditorState(cfg), kindIndex)

    # Now path should be hidden
    pathFound = false
    for item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        pathFound = true
        break
    check not pathFound

suite "ConfigMode - Bool value edge case":
  test "Bool item displays false correctly":
    let item = ConfigItem(
      kind: cvkBool,
      displayName: "testBool",
      section: "Test",
      depth: 1,
      descriptorIndex: 1,
      boolValue: false,
    )

    let result = formatItemForDisplay(item, 20)
    check "false" in result

suite "ConfigMode - descriptor completeness":
  privateAccess ConfigItemDescriptor

  # Collect simple (non-nested-object) field names from a config section.
  # When a new field is added to any config struct, fieldPairs automatically
  # includes it, so the test detects missing descriptors.
  template collectFieldNames(
      obj: typed, section: string, fields: var HashSet[(string, string)]
  ) =
    for name, value in fieldPairs(obj):
      when value is bool:
        fields.incl((section, name))
      elif value is int:
        fields.incl((section, name))
      elif value is float:
        fields.incl((section, name))
      elif value is string:
        fields.incl((section, name))
      elif value is Option[string]:
        fields.incl((section, name))
      elif value is seq[string]:
        fields.incl((section, name))
      elif value is enum:
        fields.incl((section, name))

  test "All EditorConfig sections are accounted for":
    ## If a new section is added to EditorConfig, this test fails until it is
    ## added to either `tested` or `excluded`.
    let tested = [
      "standard", "bufferBackend", "clipboard", "buildOnSave", "tabLine", "statusLine",
      "highlight", "autoBackup", "quickRun", "notification", "filer", "fileTree",
      "autocomplete", "autoSave", "persist", "git", "syntaxChecker", "smoothScroll",
      "startUpFileOpen", "startUpFileTree", "editorConfig", "log", "theme", "lsp",
    ].toHashSet
    let excluded = [
      "debug", "keyMapping", "shellCommands", "commandAliases", "disabledCommandAliases"
    ].toHashSet

    var cfg = newEditorConfig()
    for name, value in fieldPairs(cfg[]):
      if name notin tested and name notin excluded:
        echo "EditorConfig section not accounted for: " & name
      check name in tested or name in excluded

  test "Every {.cfgSection.} section has a section descriptor":
    ## The descriptors are generated from EditorConfig's section fields, so
    ## sections that were previously forgotten by hand (BuildOnSave, TabLine,
    ## QuickRun, FileTree, Persist, StartUp.*, EditorConfig, Log) must be there.
    var sections: HashSet[string]
    for desc in configDescriptors:
      if desc.kind == cvkSection:
        sections.incl(desc.section)

    for name in [
      "Standard", "BufferBackend", "Clipboard", "BuildOnSave", "TabLine", "StatusLine",
      "Highlight", "AutoBackup", "QuickRun", "Notification", "Filer", "FileTree",
      "Autocomplete", "AutoSave", "Persist", "Git", "SyntaxChecker", "SmoothScroll",
      "StartUp.FileOpen", "StartUp.FileTree", "EditorConfig", "Log", "Theme", "Lsp",
    ]:
      check name in sections

  test "Every Lsp feature sub-table has a section descriptor with its fields":
    ## The `[Lsp.<Feature>]` tables used to be absent from the UI entirely.
    var sections: HashSet[string]
    var descriptorFields: HashSet[(string, string)]
    for desc in configDescriptors:
      if desc.kind == cvkSection:
        sections.incl(desc.section)
      else:
        descriptorFields.incl((desc.section, desc.displayName))

    for name in LspFeatureTableNames:
      let section = "Lsp." & name
      check section in sections
      check (section, "enable") in descriptorFields

    # And nothing beyond them: a sub-table added to `LspConfig` but not to
    # `LspFeatureTableNames` would otherwise never be asserted on.
    var lspSubSections = 0
    for s in sections:
      if s.startsWith("Lsp."):
        inc lspSubSections
    check lspSubSections == LspFeatureTableNames.len

    # Non-`enable` fields of the wider sub-table shapes are there too.
    check ("Lsp.Definition", "openWindow") in descriptorFields
    check ("Lsp.Diagnostics", "autoHover") in descriptorFields
    check ("Lsp.Diagnostics", "autoHoverDelay") in descriptorFields

  test "Lsp sub-table descriptors address their own field":
    ## A shared getter or a copy-pasted accessor would make several tables
    ## move together. Clear them all, then flip exactly one.
    let cfg = newEditorConfig()
    proc enableDescriptors(): seq[ConfigItemDescriptor] =
      for desc in configDescriptors:
        if desc.kind == cvkBool and desc.section.startsWith("Lsp.") and
            desc.displayName == "enable":
          result.add desc

    for desc in enableDescriptors():
      desc.boolSet(cfg, false)
    check not cfg.lsp.hover.enable
    check not cfg.lsp.completion.enable

    for desc in enableDescriptors():
      if desc.section == "Lsp.Hover":
        desc.boolSet(cfg, true)
    check cfg.lsp.hover.enable
    check not cfg.lsp.completion.enable
    check not cfg.lsp.codeLens.enable

  test "All config fields have descriptors or are explicitly excluded":
    ## If a new field is added to a config struct in a tested section, this
    ## test fails until a descriptor is added to makeDescriptors() or the
    ## field is added to the excluded set.
    var cfg = newEditorConfig()

    # Collect all simple fields from sections that config mode covers
    var allFields: HashSet[(string, string)]
    collectFieldNames(cfg.standard, "Standard", allFields)
    collectFieldNames(cfg.bufferBackend, "BufferBackend", allFields)
    collectFieldNames(cfg.clipboard, "Clipboard", allFields)
    collectFieldNames(cfg.buildOnSave, "BuildOnSave", allFields)
    collectFieldNames(cfg.tabLine, "TabLine", allFields)
    collectFieldNames(cfg.statusLine, "StatusLine", allFields)
    collectFieldNames(cfg.highlight, "Highlight", allFields)
    collectFieldNames(cfg.autoBackup, "AutoBackup", allFields)
    collectFieldNames(cfg.quickRun, "QuickRun", allFields)
    collectFieldNames(cfg.notification, "Notification", allFields)
    collectFieldNames(cfg.filer, "Filer", allFields)
    collectFieldNames(cfg.fileTree, "FileTree", allFields)
    collectFieldNames(cfg.autocomplete, "Autocomplete", allFields)
    collectFieldNames(cfg.autoSave, "AutoSave", allFields)
    collectFieldNames(cfg.persist, "Persist", allFields)
    collectFieldNames(cfg.git, "Git", allFields)
    collectFieldNames(cfg.syntaxChecker, "SyntaxChecker", allFields)
    collectFieldNames(cfg.smoothScroll, "SmoothScroll", allFields)
    collectFieldNames(cfg.startUpFileOpen, "StartUp.FileOpen", allFields)
    collectFieldNames(cfg.startUpFileTree, "StartUp.FileTree", allFields)
    collectFieldNames(cfg.editorConfig, "EditorConfig", allFields)
    collectFieldNames(cfg.log, "Log", allFields)
    collectFieldNames(cfg.theme, "Theme", allFields)
    collectFieldNames(cfg.lsp, "Lsp", allFields)

    # Collect (section, displayName) from configDescriptors
    var descriptorFields: HashSet[(string, string)]
    for desc in configDescriptors:
      if desc.kind != cvkSection:
        descriptorFields.incl((desc.section, desc.displayName))

    # Fields intentionally not in config mode UI
    # (complex types, dir paths that need filesystem validation, etc.)
    let excluded = [
      ("StatusLine", "setupText"),
      ("Highlight", "reservedWord"),
      ("AutoBackup", "backupDir"),
      ("AutoBackup", "dirToExclude"),
      ("BuildOnSave", "workspaceRoot"),
      ("BuildOnSave", "command"),
      ("QuickRun", "command"),
      ("QuickRun", "nimAdvancedCommand"),
      ("QuickRun", "clangOptions"),
      ("QuickRun", "cppOptions"),
      ("QuickRun", "nimOptions"),
      ("QuickRun", "shOptions"),
      ("QuickRun", "bashOptions"),
    ].toHashSet

    let missing = allFields - descriptorFields - excluded
    if missing.len > 0:
      echo "Fields missing from config mode (add descriptor or exclude):"
      for item in missing:
        echo "  " & item[0] & "." & item[1]
    check missing.len == 0

suite "ConfigMode - Search":
  proc firstItemIndex(state: ConfigModeState): int =
    ## Index of the first editable (non-section) item.
    for i, item in state.items:
      if item.kind != cvkSection:
        return i
    -1

  test "No search query by default":
    let state = newConfigModeState(newEditorConfig())
    check not state.hasSearchQuery
    check state.searchQuery == ""

  test "setSearchQuery / clearSearch":
    let state = newConfigModeState(newEditorConfig())
    state.setSearchQuery("lsp")
    check state.hasSearchQuery
    check state.searchQuery == "lsp"
    state.clearSearch()
    check not state.hasSearchQuery

  test "matchesSearchQuery is case-insensitive on display name":
    let state = newConfigModeState(newEditorConfig())
    let idx = state.firstItemIndex
    let name = state.items[idx].displayName
    check state.items[idx].matchesSearchQuery(name.toUpperAscii)
    check state.items[idx].matchesSearchQuery(name.toLowerAscii)
    check not state.items[idx].matchesSearchQuery("zzz_no_such_field")

  test "matchesSearchQuery with empty query never matches":
    let state = newConfigModeState(newEditorConfig())
    check not state.items[0].matchesSearchQuery("")

  test "searchItems moves selection to the first match":
    let state = newConfigModeState(newEditorConfig())
    let idx = state.firstItemIndex
    let name = state.items[idx].displayName
    let found = state.searchItems(name, 0, true)
    check found.isSome
    check state.items[found.get].matchesSearchQuery(name)
    check state.selectedIndex == found.get

  test "searchItems returns none when nothing matches":
    let state = newConfigModeState(newEditorConfig())
    let before = state.selectedIndex
    check state.searchItems("zzz_no_such_field", 0, true).isNone
    check state.selectedIndex == before

  test "isItemMatched reflects the committed query":
    let state = newConfigModeState(newEditorConfig())
    let idx = state.firstItemIndex
    let name = state.items[idx].displayName
    check not state.isItemMatched(idx) # no query yet
    state.setSearchQuery(name)
    check state.isItemMatched(idx)
    check not state.isItemMatched(-1)
    check not state.isItemMatched(state.items.len)

  test "searchForward wraps around to a match before the cursor":
    let state = newConfigModeState(newEditorConfig())
    let idx = state.firstItemIndex
    state.setSearchQuery(state.items[idx].displayName)
    # Place the cursor after the match, then search forward: it must wrap.
    state.selectedIndex = state.items.high
    let found = state.searchForward()
    check found.isSome
    check state.items[found.get].matchesSearchQuery(state.searchQuery)

  test "searchBackward wraps around to a match after the cursor":
    let state = newConfigModeState(newEditorConfig())
    let idx = state.firstItemIndex
    state.setSearchQuery(state.items[idx].displayName)
    # Place the cursor before the match, then search backward: it must wrap.
    state.selectedIndex = 0
    let found = state.searchBackward()
    check found.isSome

suite "ConfigMode - Theme Colors":
  proc findColorItem(state: ConfigModeState, name: string): int =
    result = -1
    for i, item in state.items:
      if item.kind == cvkColor and item.displayName == name:
        return i

  proc selectColorItem(state: ConfigModeState, name: string) =
    state.selectedIndex = state.findColorItem(name)

  setup:
    # Deterministic global theme state for each test.
    setThemeColors(DefaultColors)

  test "color items present and section header shown when kind is config":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)

    var hasSection = false
    var hasColor = false
    for item in state.items:
      if item.kind == cvkSection and item.section == "Theme Colors":
        hasSection = true
      if item.kind == cvkColor and item.section == "Theme Colors":
        hasColor = true
    check hasSection
    check hasColor

  test "color items hidden when kind is default":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkDefault
    let state = newConfigModeState(cfg)
    for item in state.items:
      check item.kind != cvkColor
      check item.section != "Theme Colors"

  test "color items hidden when kind is vscode":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkVscode
    let state = newConfigModeState(cfg)
    for item in state.items:
      check item.kind != cvkColor

  test "color items hidden when config theme has no path":
    # Without a path there is nowhere for :w to persist the colors, so the
    # items must not be shown (otherwise editing them is a silent no-op).
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    cfg.theme.path = ""
    let state = newConfigModeState(cfg)
    for item in state.items:
      check item.kind != cvkColor
      check item.section != "Theme Colors"

  test "normal entry exposes both fg and bg":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    check state.findColorItem("keyword.fg") >= 0
    check state.findColorItem("keyword.bg") >= 0

  test "bg-only entries omit the fg item":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    check state.findColorItem("currentLineBg.fg") < 0
    check state.findColorItem("currentLineBg.bg") >= 0
    check state.findColorItem("currentColumnBg.fg") < 0
    check state.findColorItem("currentColumnBg.bg") >= 0

  test "colorValue reflects the active theme as lowercase hex":
    var colors = DefaultColors
    colors[EditorColorPairIndex.keyword].foreground = ThemeColor(rgb: rgb("#abcdef"))
    setThemeColors(colors)

    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    let idx = state.findColorItem("keyword.fg")
    check idx >= 0
    check state.items[idx].colorValue == "#abcdef"

  test "colorValue is termDefault for the terminal default color":
    var colors = DefaultColors
    colors[EditorColorPairIndex.keyword].foreground =
      ThemeColor(rgb: TerminalDefaultRgb)
    setThemeColors(colors)

    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    let idx = state.findColorItem("keyword.fg")
    check state.items[idx].colorValue == "termDefault"

  test "editing applies a valid hex color":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    state.selectColorItem("keyword.fg")

    state.startEdit()
    check state.editMode
    state.editBuffer = "#ff0000"
    check state.confirmEdit(testEditorState(cfg))
    check getThemeColor(EditorColorPairIndex.keyword).foreground.rgb == rgb("#ff0000")

  test "editing accepts hex without the # prefix":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    state.selectColorItem("keyword.fg")

    state.startEdit()
    state.editBuffer = "00ff00"
    check state.confirmEdit(testEditorState(cfg))
    check getThemeColor(EditorColorPairIndex.keyword).foreground.rgb == rgb("#00ff00")

  test "editing accepts termDefault":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    state.selectColorItem("keyword.fg")

    state.startEdit()
    state.editBuffer = "termDefault"
    check state.confirmEdit(testEditorState(cfg))
    check getThemeColor(EditorColorPairIndex.keyword).foreground.rgb.isTermDefaultColor

  test "invalid hex is rejected and editing continues":
    var colors = DefaultColors
    colors[EditorColorPairIndex.keyword].foreground = ThemeColor(rgb: rgb("#123456"))
    setThemeColors(colors)

    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    state.selectColorItem("keyword.fg")

    state.startEdit()
    state.editBuffer = "nothex"
    check not state.confirmEdit(testEditorState(cfg))
    check state.editMode # still editing
    check getThemeColor(EditorColorPairIndex.keyword).foreground.rgb == rgb("#123456")

  test "editing a bg item writes the background channel":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    let fgBefore = getThemeColor(EditorColorPairIndex.keyword).foreground.rgb
    state.selectColorItem("keyword.bg")

    state.startEdit()
    state.editBuffer = "#0000ff"
    check state.confirmEdit(testEditorState(cfg))
    check getThemeColor(EditorColorPairIndex.keyword).background.rgb == rgb("#0000ff")
    check getThemeColor(EditorColorPairIndex.keyword).foreground.rgb == fgBefore

  test "selection stays on the same color item after editing":
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    state.selectColorItem("keyword.fg")

    state.startEdit()
    state.editBuffer = "#ff0000"
    check state.confirmEdit(testEditorState(cfg))
    let item = state.items[state.selectedIndex]
    check item.kind == cvkColor
    check item.colorIndex == EditorColorPairIndex.keyword
    check item.colorIsFg

  test "search matches color name and value":
    var colors = DefaultColors
    colors[EditorColorPairIndex.keyword].foreground = ThemeColor(rgb: rgb("#ff0000"))
    setThemeColors(colors)

    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    let state = newConfigModeState(cfg)
    let idx = state.findColorItem("keyword.fg")
    check state.items[idx].matchesSearchQuery("keyword")
    check state.items[idx].matchesSearchQuery("ff0000")

  test "applyColorChange snaps selection to itemIndex when color items become hidden":
    # Regression: if a rebuild hides the edited color item (e.g. the config
    # theme path was cleared out from under it), selection recovery must not
    # leave selectedIndex pointing at whatever unrelated row it held before.
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    cfg.theme.path = "somepath"
    let state = newConfigModeState(cfg)

    let idx = state.findColorItem("keyword.fg")
    check idx > 0

    # Force the next rebuild to drop every color item.
    cfg.theme.path = ""
    state.selectedIndex = 0

    state.applyColorChange(testEditorState(cfg), idx)

    for item in state.items:
      check item.kind != cvkColor
    check state.selectedIndex == clamp(idx, 0, max(0, state.items.len - 1))

suite "ConfigMode - applyChange hidden recovery":
  test "selection snaps to itemIndex when the edited item becomes hidden":
    # Regression: if the item being edited is hidden by the post-edit rebuild
    # (e.g. its visibleWhen predicate now returns false), the recovery loop
    # cannot find its descriptor. Selection must fall back to the neighborhood
    # of the edited slot, not the stale selectedIndex.
    let cfg = newEditorConfig()
    cfg.theme.kind = tkConfig
    cfg.theme.path = "somepath"
    let state = newConfigModeState(cfg)

    var pathIdx = -1
    for i, item in state.items:
      if item.kind == cvkString and item.section == "Theme" and
          item.displayName == "path":
        pathIdx = i
        break
    check pathIdx > 0

    # Preload the rebuild so Theme.path (visibleWhen kind == tkConfig) is hidden,
    # and stage a real value change so applyChange doesn't early-return.
    cfg.theme.kind = tkDefault
    state.items[pathIdx].stringValue = "newpath"
    state.selectedIndex = 0

    state.applyChange(testEditorState(cfg), pathIdx)

    for item in state.items:
      check not (
        item.kind == cvkString and item.section == "Theme" and item.displayName == "path"
      )
    check state.selectedIndex == clamp(pathIdx, 0, max(0, state.items.len - 1))
