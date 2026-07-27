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

## Configuration mode module
## Provides a UI for viewing and editing configuration settings
##
## Design: Table-driven approach to avoid duplication between building
## the item list and applying changes.

import std/[options, strutils, unicode]

import pkg/results

import config, color, types, config_loader

import types/config_mode_types
export config_mode_types

type
  ## Getter/Setter closures for config values
  BoolGetter = proc(cfg: EditorConfig): bool {.noSideEffect.}
  BoolSetter = proc(cfg: EditorConfig, val: bool)
  IntGetter = proc(cfg: EditorConfig): int {.noSideEffect.}
  IntSetter = proc(cfg: EditorConfig, val: int)
  FloatGetter = proc(cfg: EditorConfig): float {.noSideEffect.}
  FloatSetter = proc(cfg: EditorConfig, val: float)
  EnumGetter = proc(cfg: EditorConfig): string {.noSideEffect.}
  EnumSetter = proc(cfg: EditorConfig, val: string)
  StringGetter = proc(cfg: EditorConfig): string {.noSideEffect.}
  StringSetter = proc(cfg: EditorConfig, val: string)

  ## Config item descriptor - defines how to read/write a config value
  ConfigItemDescriptor = object
    displayName: string
    section: string
    visibleWhen: proc(cfg: EditorConfig): bool {.noSideEffect.}
    case kind: ConfigValueKind
    of cvkBool:
      boolGet: BoolGetter
      boolSet: BoolSetter
    of cvkInt:
      intGet: IntGetter
      intSet: IntSetter
      intMin, intMax: int
    of cvkFloat:
      floatGet: FloatGetter
      floatSet: FloatSetter
      floatMin, floatMax: float
      floatStep: float # Increment/decrement step
    of cvkEnum:
      enumGet: EnumGetter
      enumSet: EnumSetter
      enumOptions: seq[string]
    of cvkString:
      stringGet: StringGetter
      stringSetter: StringSetter
    of cvkColor:
      discard # Color items are built directly, not via descriptors
    of cvkSection:
      discard

# Theme color entries that only have a background (no foreground).
const ColorBgOnlyEntries* =
  {EditorColorPairIndex.currentLineBg, EditorColorPairIndex.currentColumnBg}

# Config Item Descriptors - Single source of truth for config items

proc makeDescriptors(): seq[ConfigItemDescriptor] =
  ## Build the descriptor table. Each descriptor knows how to read/write
  ## a specific config field.
  result = @[]

  # Every {.cfgSection.} section of EditorConfig, in declaration order. A new
  # section reaches the UI without touching this proc.
  generateAllConfigDescriptors(result, EditorConfig)

  # Theme section
  result.add ConfigItemDescriptor(
    kind: cvkSection, displayName: "Theme", section: "Theme"
  )
  result.add ConfigItemDescriptor(
    kind: cvkEnum,
    displayName: "kind",
    section: "Theme",
    enumGet: proc(c: EditorConfig): string =
      $c.theme.kind,
    enumSet: proc(c: EditorConfig, v: string) =
      c.theme.kind = parseEnum[ThemeKind](v),
    enumOptions: @["default", "config", "vscode"],
  )
  result.add ConfigItemDescriptor(
    kind: cvkString,
    displayName: "path",
    section: "Theme",
    visibleWhen: proc(c: EditorConfig): bool =
      c.theme.kind == tkConfig,
    stringGet: proc(c: EditorConfig): string =
      c.theme.path,
    stringSetter: proc(c: EditorConfig, v: string) =
      c.theme.path = v,
  )

  # `[Lsp]` plus one section per feature sub-table. `[Lsp.<languageId>]` server
  # entries stay out of the UI: a dynamic keyspace, not fields of the type.
  generateSectionGroupDescriptors(result, lsp, LspConfig)

# Global descriptor table (built once)
let configDescriptors* = makeDescriptors()

# Item building and value application

proc colorValueString*(index: EditorColorPairIndex, isFg: bool): string =
  ## Current value of a theme color channel as "#rrggbb" or "termDefault"
  let pair = getThemeColor(index)
  let tc = if isFg: pair.foreground else: pair.background
  toHex(tc.rgb).get("termDefault")

proc buildItemList*(state: ConfigModeState) =
  ## Build the flat list of config items from EditorConfig using descriptors
  state.items = @[]
  let cfg = state.config

  for i, desc in configDescriptors:
    if desc.visibleWhen != nil and not desc.visibleWhen(cfg):
      continue
    case desc.kind
    of cvkSection:
      state.items.add ConfigItem(
        kind: cvkSection,
        displayName: desc.displayName,
        section: desc.section,
        depth: 0,
        descriptorIndex: -1,
      )
    of cvkBool:
      state.items.add ConfigItem(
        kind: cvkBool,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        boolValue: desc.boolGet(cfg),
      )
    of cvkInt:
      state.items.add ConfigItem(
        kind: cvkInt,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        intValue: desc.intGet(cfg),
        intMin: desc.intMin,
        intMax: desc.intMax,
      )
    of cvkFloat:
      state.items.add ConfigItem(
        kind: cvkFloat,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        floatValue: desc.floatGet(cfg),
        floatMin: desc.floatMin,
        floatMax: desc.floatMax,
        floatStep: desc.floatStep,
      )
    of cvkEnum:
      state.items.add ConfigItem(
        kind: cvkEnum,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        enumValue: desc.enumGet(cfg),
        enumOptions: desc.enumOptions,
      )
    of cvkString:
      state.items.add ConfigItem(
        kind: cvkString,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
        stringValue: desc.stringGet(cfg),
      )
    of cvkColor:
      discard # Color items are not produced by descriptors

  # Theme color items (editable only for the config theme, persisted on :w).
  # These live in the global `themeColors`, not in EditorConfig, so they are
  # built directly here instead of via descriptors. A path is required because
  # that is where `:w` writes the colors; without one there is nowhere to
  # persist them, so the items are hidden to avoid a silent no-op on save.
  if cfg.theme.kind == tkConfig and cfg.theme.path.len > 0:
    state.items.add ConfigItem(
      kind: cvkSection,
      displayName: "Theme Colors",
      section: "Theme Colors",
      depth: 0,
      descriptorIndex: -1,
    )
    for index in EditorColorPairIndex:
      if index notin ColorBgOnlyEntries:
        state.items.add ConfigItem(
          kind: cvkColor,
          displayName: $index & ".fg",
          section: "Theme Colors",
          depth: 1,
          descriptorIndex: -1,
          colorIndex: index,
          colorIsFg: true,
          colorValue: colorValueString(index, true),
        )
      state.items.add ConfigItem(
        kind: cvkColor,
        displayName: $index & ".bg",
        section: "Theme Colors",
        depth: 1,
        descriptorIndex: -1,
        colorIndex: index,
        colorIsFg: false,
        colorValue: colorValueString(index, false),
      )

proc applyChange*(state: ConfigModeState, editorState: EditorState, itemIndex: int) =
  ## Apply a change to the actual config using descriptors
  if itemIndex < 0 or itemIndex >= state.items.len:
    return

  let item = state.items[itemIndex]
  if item.descriptorIndex < 0:
    return # Section headers have no descriptor

  let desc = configDescriptors[item.descriptorIndex]
  let cfg = state.config

  # Skip no-op writes: confirming an unchanged value would otherwise flip
  # pendingApply and force handler.nim's applyConfigSettings to reread the
  # theme and re-highlight every buffer on each keystroke.
  let changed =
    case item.kind
    of cvkBool:
      desc.boolGet(cfg) != item.boolValue
    of cvkInt:
      desc.intGet(cfg) != item.intValue
    of cvkFloat:
      desc.floatGet(cfg) != item.floatValue
    of cvkEnum:
      desc.enumGet(cfg) != item.enumValue
    of cvkString:
      desc.stringGet(cfg) != item.stringValue
    else:
      false
  if not changed:
    return

  # Revert theme on load failure so UI never claims a kind whose colors
  # silently fell back to default.
  let isThemeChange = item.section == "Theme" and item.displayName in ["kind", "path"]
  let previousTheme = cfg.theme

  case item.kind
  of cvkBool:
    desc.boolSet(cfg, item.boolValue)
  of cvkInt:
    desc.intSet(cfg, item.intValue)
  of cvkFloat:
    desc.floatSet(cfg, item.floatValue)
  of cvkEnum:
    desc.enumSet(cfg, item.enumValue)
  of cvkString:
    desc.stringSetter(cfg, item.stringValue)
  else:
    discard

  if isThemeChange:
    var vr = newValidationResult()
    initTheme(cfg, vr)
    if vr.hasErrors:
      cfg.theme = previousTheme
      initTheme(cfg)
      editorState.statusMessage =
        "Failed to load theme: " & vr.toErrorMessages.join("; ")

  state.pendingApply = true

  # Rebuild to update conditional visibility
  let savedDescIdx = item.descriptorIndex
  state.buildItemList()
  var found = false
  for i, newItem in state.items:
    if newItem.descriptorIndex == savedDescIdx:
      state.selectedIndex = i
      found = true
      break
  if not found:
    # Item hidden by rebuild; anchor near its old slot instead of stale index.
    state.selectedIndex = clamp(itemIndex, 0, max(0, state.items.len - 1))

proc applyColorChange*(
    state: ConfigModeState, editorState: EditorState, itemIndex: int
) =
  ## Apply a theme color change to the global `themeColors` (live preview).
  ## Persisted to the theme file by the normal `:w` save path only when the
  ## active theme is `tkConfig`; other kinds keep the edit in memory but
  ## silently drop it on `:writeconf`. Surface that once via statusMessage
  ## so the user isn't left wondering why the change didn't stick.
  if itemIndex < 0 or itemIndex >= state.items.len:
    return

  let item = state.items[itemIndex]
  if item.kind != cvkColor:
    return

  let parsed = parseThemeColor(item.colorValue)
  if parsed.isErr:
    return # Caller validates before calling

  var colors = themeColors
  if item.colorIsFg:
    colors[item.colorIndex].foreground = ThemeColor(rgb: parsed.get)
  else:
    colors[item.colorIndex].background = ThemeColor(rgb: parsed.get)
  setThemeColors(colors)

  if editorState.config.theme.kind != tkConfig:
    editorState.statusMessage =
      "Theme color preview only; run :theme <name> or set [Theme].path to persist"

  # Rebuild and re-select by (colorIndex, colorIsFg) identity
  let
    savedIdx = item.colorIndex
    savedIsFg = item.colorIsFg
  state.buildItemList()
  var found = false
  for i, newItem in state.items:
    if newItem.kind == cvkColor and newItem.colorIndex == savedIdx and
        newItem.colorIsFg == savedIsFg:
      state.selectedIndex = i
      found = true
      break
  if not found:
    # Item hidden by rebuild; anchor near its old slot instead of stale index.
    state.selectedIndex = clamp(itemIndex, 0, max(0, state.items.len - 1))

# State management

proc newConfigModeState*(config: EditorConfig): ConfigModeState =
  ## Create a new Configuration mode state
  result = ConfigModeState(
    items: @[],
    selectedIndex: 0,
    editMode: false,
    editBuffer: "",
    editCursor: 0,
    enumPopupOpen: false,
    enumPopupIndex: 0,
    searchQuery: "",
    searchStartIndex: 0,
    config: config,
    pendingApply: false,
  )
  result.buildItemList()

proc getSelectedItem*(state: ConfigModeState): Option[ConfigItem] =
  ## Get the currently selected item
  if state.selectedIndex >= 0 and state.selectedIndex < state.items.len:
    some(state.items[state.selectedIndex])
  else:
    none(ConfigItem)

proc getSelectedItemIndex*(state: ConfigModeState): int =
  ## Get the index of currently selected item
  if state.selectedIndex >= 0 and state.selectedIndex < state.items.len:
    state.selectedIndex
  else:
    -1

proc moveUp*(state: ConfigModeState) =
  ## Move selection up
  if state.selectedIndex > 0:
    state.selectedIndex.dec

proc moveDown*(state: ConfigModeState) =
  ## Move selection down
  if state.selectedIndex < state.items.len - 1:
    state.selectedIndex.inc

proc moveToFirst*(state: ConfigModeState) =
  ## Move to first item
  state.selectedIndex = 0

proc moveToLast*(state: ConfigModeState) =
  ## Move to last item
  state.selectedIndex = max(0, state.items.len - 1)

# Search

proc matchesSearchQuery*(item: ConfigItem, query: string): bool =
  ## Case-insensitive match of `query` against an item's display name and value
  if query.len == 0:
    return false
  let q = query.toLowerAscii
  if item.displayName.toLowerAscii.contains(q):
    return true
  case item.kind
  of cvkBool:
    (if item.boolValue: "true" else: "false").contains(q)
  of cvkInt:
    ($item.intValue).contains(q)
  of cvkFloat:
    ($item.floatValue).contains(q)
  of cvkString:
    item.stringValue.toLowerAscii.contains(q)
  of cvkEnum:
    item.enumValue.toLowerAscii.contains(q)
  of cvkColor:
    item.colorValue.toLowerAscii.contains(q)
  of cvkSection:
    false

proc setSearchQuery*(state: ConfigModeState, query: string) =
  ## Set the active search query
  state.searchQuery = query

proc clearSearch*(state: ConfigModeState) =
  ## Clear the active search query
  state.searchQuery = ""

proc hasSearchQuery*(state: ConfigModeState): bool =
  ## Whether a search query is currently active
  state.searchQuery.len > 0

proc isItemMatched*(state: ConfigModeState, index: int): bool =
  ## Whether the item at `index` matches the active search query
  if not state.hasSearchQuery:
    return false
  if index < 0 or index >= state.items.len:
    return false
  state.items[index].matchesSearchQuery(state.searchQuery)

proc searchItems*(
    state: ConfigModeState, query: string, startIndex: int, forward: bool
): Option[int] =
  ## Scan items for `query` starting at `startIndex` (inclusive), wrapping around
  ## the list. Moves `selectedIndex` to the first match and returns its index.
  if query.len == 0 or state.items.len == 0:
    return none(int)

  let n = state.items.len
  for offset in 0 ..< n:
    let i =
      if forward:
        (startIndex + offset) mod n
      else:
        ((startIndex - offset) mod n + n) mod n
    if state.items[i].matchesSearchQuery(query):
      state.selectedIndex = i
      return some(i)
  none(int)

proc searchForward*(state: ConfigModeState): Option[int] =
  ## Move to the next match after the current selection (wraps around)
  state.searchItems(state.searchQuery, state.selectedIndex + 1, true)

proc searchBackward*(state: ConfigModeState): Option[int] =
  ## Move to the previous match before the current selection (wraps around)
  state.searchItems(state.searchQuery, state.selectedIndex - 1, false)

# Value manipulation

proc toggleBoolValue*(state: ConfigModeState, editorState: EditorState) =
  ## Toggle a boolean value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkBool:
    state.items[itemIndex].boolValue = not state.items[itemIndex].boolValue
    state.applyChange(editorState, itemIndex)

proc cycleEnumValue*(
    state: ConfigModeState, editorState: EditorState, forward: bool = true
) =
  ## Cycle through enum options
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum and item.enumOptions.len > 0:
    var currentIdx = item.enumOptions.find(item.enumValue)
    if currentIdx < 0:
      currentIdx = 0
    if forward:
      currentIdx = (currentIdx + 1) mod item.enumOptions.len
    else:
      currentIdx = (currentIdx - 1 + item.enumOptions.len) mod item.enumOptions.len
    state.items[itemIndex].enumValue = item.enumOptions[currentIdx]
    state.applyChange(editorState, itemIndex)

proc incrementIntValue*(state: ConfigModeState, editorState: EditorState) =
  ## Increment integer value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkInt:
    let item = state.items[itemIndex]
    if item.intValue < item.intMax:
      state.items[itemIndex].intValue = item.intValue + 1
      state.applyChange(editorState, itemIndex)

proc decrementIntValue*(state: ConfigModeState, editorState: EditorState) =
  ## Decrement integer value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkInt:
    let item = state.items[itemIndex]
    if item.intValue > item.intMin:
      state.items[itemIndex].intValue = item.intValue - 1
      state.applyChange(editorState, itemIndex)

proc incrementFloatValue*(state: ConfigModeState, editorState: EditorState) =
  ## Increment float value by step
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkFloat:
    let item = state.items[itemIndex]
    let newValue = item.floatValue + item.floatStep
    if newValue <= item.floatMax:
      state.items[itemIndex].floatValue = newValue
      state.applyChange(editorState, itemIndex)

proc decrementFloatValue*(state: ConfigModeState, editorState: EditorState) =
  ## Decrement float value by step
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkFloat:
    let item = state.items[itemIndex]
    let newValue = item.floatValue - item.floatStep
    if newValue >= item.floatMin:
      state.items[itemIndex].floatValue = newValue
      state.applyChange(editorState, itemIndex)

# Display formatting

proc formatItemForDisplay*(item: ConfigItem, maxNameWidth: int): string =
  ## Format a config item for display
  let indent = "  ".repeat(item.depth)
  let name = item.displayName.alignLeft(max(0, maxNameWidth - item.depth * 2))

  case item.kind
  of cvkSection:
    return "[" & item.displayName & "]"
  of cvkBool:
    return indent & name & " : " & (if item.boolValue: "true" else: "false")
  of cvkInt:
    return indent & name & " : " & $item.intValue
  of cvkFloat:
    return indent & name & " : " & $item.floatValue
  of cvkString:
    return indent & name & " : " & item.stringValue
  of cvkEnum:
    return indent & name & " : " & item.enumValue
  of cvkColor:
    return indent & name & " : " & item.colorValue

proc calcMaxNameWidth*(items: seq[ConfigItem], maxWidth: int): int =
  ## Calculate the maximum display name width for config item layout.
  for item in items:
    if item.kind != cvkSection:
      result = max(result, item.displayName.len + item.depth * 2)
  result = min(result + 4, maxWidth div 2)

# Edit mode (Int/String editing)

proc startEdit*(state: ConfigModeState) =
  ## Start editing the current value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  case item.kind
  of cvkInt:
    state.editMode = true
    state.editBuffer = $item.intValue
    state.editCursor = state.editBuffer.runeLen
  of cvkFloat:
    state.editMode = true
    state.editBuffer = $item.floatValue
    state.editCursor = state.editBuffer.runeLen
  of cvkString:
    state.editMode = true
    state.editBuffer = item.stringValue
    state.editCursor = state.editBuffer.runeLen
  of cvkColor:
    state.editMode = true
    state.editBuffer = item.colorValue
    state.editCursor = state.editBuffer.runeLen
  else:
    discard

proc cancelEdit*(state: ConfigModeState) =
  ## Cancel editing and discard changes
  state.editMode = false
  state.editBuffer = ""
  state.editCursor = 0

proc confirmEdit*(state: ConfigModeState, editorState: EditorState): bool =
  ## Confirm the edit and apply the value
  ## Returns true if successful
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    state.cancelEdit()
    return false

  let item = state.items[itemIndex]
  case item.kind
  of cvkInt:
    try:
      let newValue = parseInt(state.editBuffer)
      if newValue >= item.intMin and newValue <= item.intMax:
        state.items[itemIndex].intValue = newValue
        state.applyChange(editorState, itemIndex)
        state.cancelEdit()
        return true
      else:
        return false # Value out of range
    except ValueError:
      return false # Invalid number
  of cvkFloat:
    try:
      let newValue = parseFloat(state.editBuffer)
      if newValue >= item.floatMin and newValue <= item.floatMax:
        state.items[itemIndex].floatValue = newValue
        state.applyChange(editorState, itemIndex)
        state.cancelEdit()
        return true
      else:
        return false # Value out of range
    except ValueError:
      return false # Invalid number
  of cvkString:
    state.items[itemIndex].stringValue = state.editBuffer
    state.applyChange(editorState, itemIndex)
    state.cancelEdit()
    return true
  of cvkColor:
    if parseThemeColor(state.editBuffer).isErr:
      return false # Invalid hex / not "termDefault"; keep editing
    state.items[itemIndex].colorValue = state.editBuffer
    state.applyColorChange(editorState, itemIndex)
    state.cancelEdit()
    return true
  else:
    state.cancelEdit()
    return false

# editCursor is a rune (character) index, not a byte offset, so multibyte
# values (e.g. bookmarkMarker) stay intact while editing. String ops below
# convert it to a byte offset via runeOffset just before mutating editBuffer.

proc byteOffsetAtCursor(state: ConfigModeState): int =
  ## Byte offset of the rune at editCursor (or buffer end when at the tail).
  if state.editCursor >= state.editBuffer.runeLen:
    state.editBuffer.len
  else:
    state.editBuffer.runeOffset(state.editCursor)

proc editInsertChar*(state: ConfigModeState, c: string) =
  ## Insert a character at cursor position in edit buffer
  if not state.editMode:
    return
  state.editBuffer.insert(c, state.byteOffsetAtCursor)
  state.editCursor += c.runeLen

proc editBackspace*(state: ConfigModeState) =
  ## Delete the rune before the cursor
  if not state.editMode or state.editCursor <= 0:
    return
  let
    endByte = state.byteOffsetAtCursor
    startByte = state.editBuffer.runeOffset(state.editCursor - 1)
  state.editBuffer.delete(startByte ..< endByte)
  state.editCursor.dec

proc editDelete*(state: ConfigModeState) =
  ## Delete the rune at the cursor
  if not state.editMode or state.editCursor >= state.editBuffer.runeLen:
    return
  let
    startByte = state.byteOffsetAtCursor
    endByte = startByte + runeLenAt(state.editBuffer, startByte)
  state.editBuffer.delete(startByte ..< endByte)

proc editMoveCursorLeft*(state: ConfigModeState) =
  ## Move cursor left in edit buffer
  if state.editMode and state.editCursor > 0:
    state.editCursor.dec

proc editMoveCursorRight*(state: ConfigModeState) =
  ## Move cursor right in edit buffer
  if state.editMode and state.editCursor < state.editBuffer.runeLen:
    state.editCursor.inc

proc editMoveCursorHome*(state: ConfigModeState) =
  ## Move cursor to beginning of edit buffer
  if state.editMode:
    state.editCursor = 0

proc editMoveCursorEnd*(state: ConfigModeState) =
  ## Move cursor to end of edit buffer
  if state.editMode:
    state.editCursor = state.editBuffer.runeLen

proc isEditing*(state: ConfigModeState): bool =
  ## Check if currently in edit mode
  state.editMode

proc getEditInfo*(state: ConfigModeState): tuple[buffer: string, cursor: int] =
  ## Get edit buffer and cursor position
  (state.editBuffer, state.editCursor)

# Enum popup

proc isEnumPopupOpen*(state: ConfigModeState): bool =
  ## Check if enum selection popup is open
  state.enumPopupOpen

proc openEnumPopup*(state: ConfigModeState) =
  ## Open the enum selection popup for the current item
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind != cvkEnum:
    return

  state.enumPopupOpen = true
  state.enumPopupIndex = item.enumOptions.find(item.enumValue)
  if state.enumPopupIndex < 0:
    state.enumPopupIndex = 0

proc closeEnumPopup*(state: ConfigModeState) =
  ## Close the enum selection popup without applying
  state.enumPopupOpen = false
  state.enumPopupIndex = 0

proc enumPopupMoveUp*(state: ConfigModeState) =
  ## Move selection up in enum popup (wraps to last item at top)
  if not state.enumPopupOpen:
    return

  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum:
    if state.enumPopupIndex > 0:
      state.enumPopupIndex.dec
    else:
      state.enumPopupIndex = item.enumOptions.len - 1

proc enumPopupMoveDown*(state: ConfigModeState) =
  ## Move selection down in enum popup (wraps to first item at bottom)
  if not state.enumPopupOpen:
    return

  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum:
    if state.enumPopupIndex < item.enumOptions.len - 1:
      state.enumPopupIndex.inc
    else:
      state.enumPopupIndex = 0

proc enumPopupConfirm*(state: ConfigModeState, editorState: EditorState) =
  ## Confirm selection in enum popup
  if not state.enumPopupOpen:
    return

  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    state.closeEnumPopup()
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum and state.enumPopupIndex < item.enumOptions.len:
    state.items[itemIndex].enumValue = item.enumOptions[state.enumPopupIndex]
    state.applyChange(editorState, itemIndex)

  state.closeEnumPopup()

proc getEnumPopupInfo*(
    state: ConfigModeState
): tuple[options: seq[string], selectedIndex: int] =
  ## Get enum popup options and selected index
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return (@[], 0)

  let item = state.items[itemIndex]
  if item.kind == cvkEnum:
    return (item.enumOptions, state.enumPopupIndex)
  else:
    return (@[], 0)
