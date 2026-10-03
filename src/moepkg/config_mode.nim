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

import std/[options, strutils]

import pkg/results

import config, color, types, config_loader, unicode_utils

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

  # `[Hook]`'s own switches. Its `[[Hook.entries]]` array is left out like
  # every repeated table: the UI edits one value per row.
  generateSectionGroupDescriptors(result, hooks, HookConfig)

# Global descriptor table (built once)
let configDescriptors* = makeDescriptors()

# Item building and value access

proc colorValueString*(index: EditorColorPairIndex, isFg: bool): string =
  ## Current value of a theme color channel as "#rrggbb" or "termDefault"
  let pair = getThemeColor(index)
  let tc = if isFg: pair.foreground else: pair.background
  toHex(tc.rgb).get("termDefault")

template descriptor(item: ConfigItem): ConfigItemDescriptor =
  configDescriptors[item.descriptorIndex]

proc boolValue*(item: ConfigItem, cfg: EditorConfig): bool =
  item.descriptor.boolGet(cfg)

proc intValue*(item: ConfigItem, cfg: EditorConfig): int =
  item.descriptor.intGet(cfg)

proc floatValue*(item: ConfigItem, cfg: EditorConfig): float =
  item.descriptor.floatGet(cfg)

proc enumValue*(item: ConfigItem, cfg: EditorConfig): string =
  item.descriptor.enumGet(cfg)

proc stringValue*(item: ConfigItem, cfg: EditorConfig): string =
  item.descriptor.stringGet(cfg)

proc colorValue*(item: ConfigItem): string =
  colorValueString(item.colorIndex, item.colorIsFg)

proc valueText*(item: ConfigItem, cfg: EditorConfig): string =
  ## The value as shown in the list and seeded into the edit field
  case item.kind
  of cvkBool:
    if item.boolValue(cfg): "true" else: "false"
  of cvkInt:
    $item.intValue(cfg)
  of cvkFloat:
    $item.floatValue(cfg)
  of cvkString:
    item.stringValue(cfg)
  of cvkEnum:
    item.enumValue(cfg)
  of cvkColor:
    item.colorValue
  of cvkSection:
    ""

proc buildItemList*(state: ConfigModeState) =
  ## Build the flat list of visible config items from the descriptors
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
      )
    of cvkInt:
      state.items.add ConfigItem(
        kind: cvkInt,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
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
        enumOptions: desc.enumOptions,
      )
    of cvkString:
      state.items.add ConfigItem(
        kind: cvkString,
        displayName: desc.displayName,
        section: desc.section,
        depth: 1,
        descriptorIndex: i,
      )
    of cvkColor:
      discard # Color items are not produced by descriptors

  # Theme colors live in global `themeColors`, not EditorConfig. Listed only
  # for `tkConfig` with a path, where `:w` can persist them.
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
        )
      state.items.add ConfigItem(
        kind: cvkColor,
        displayName: $index & ".bg",
        section: "Theme Colors",
        depth: 1,
        descriptorIndex: -1,
        colorIndex: index,
        colorIsFg: false,
      )

proc isSameRow(a, b: ConfigItem): bool =
  if a.kind != b.kind:
    false
  elif a.kind == cvkSection:
    a.section == b.section
  elif a.kind == cvkColor:
    a.colorIndex == b.colorIndex and a.colorIsFg == b.colorIsFg
  else:
    a.descriptorIndex == b.descriptorIndex

proc cancelEdit*(state: ConfigModeState) =
  ## Cancel editing and discard changes
  state.editMode = false
  state.editBuffer = ""
  state.editCursor = 0

proc closeEnumPopup*(state: ConfigModeState) =
  ## Close the enum selection popup without applying
  state.enumPopupOpen = false
  state.enumPopupIndex = 0

proc remapRow(
    state: ConfigModeState, old: seq[ConfigItem], index: int
): tuple[index: int, kept: bool] =
  ## Where the row at `old[index]` is now. When it is gone, a surviving
  ## neighbor in its section.
  if index < 0 or index >= old.len:
    return (clamp(index, 0, max(0, state.items.len - 1)), true)

  let row = old[index]
  for i, item in state.items:
    if item.isSameRow(row):
      return (i, true)

  var best = -1
  for i, item in state.items:
    if item.section == row.section:
      best = i
      if item.descriptorIndex >= row.descriptorIndex:
        break
  if best < 0:
    best = clamp(index, 0, max(0, state.items.len - 1))
  (best, false)

proc refreshItems*(state: ConfigModeState, editorState: EditorState = nil): bool =
  ## Rebuild rows for live values, keeping selection and search anchor.
  ## Drops an edit/popup whose row is gone; reports it via return value and
  ## `editorState` message so the caller can swallow the orphaned key.
  let old = move state.items
  state.buildItemList()

  state.searchStartIndex = state.remapRow(old, state.searchStartIndex).index
  let selected = state.remapRow(old, state.selectedIndex)
  state.selectedIndex = selected.index
  if selected.kept or not (state.editMode or state.enumPopupOpen):
    return false
  state.cancelEdit()
  state.closeEnumPopup()
  if editorState != nil:
    editorState.statusMessage = "Setting disappeared; the edit was cancelled"
  true

proc commitChange(
    state: ConfigModeState, editorState: EditorState, item: ConfigItem, write: proc()
) =
  ## Write a changed value, reloading the theme when it names one
  let cfg = state.config
  # Revert theme on load failure so UI never claims a kind whose colors
  # silently fell back to default.
  let isThemeChange = item.section == "Theme" and item.displayName in ["kind", "path"]
  let previousTheme = cfg.theme

  write()

  if isThemeChange:
    var vr = newValidationResult()
    initTheme(cfg, vr)
    if vr.hasErrors:
      cfg.theme = previousTheme
      initTheme(cfg)
      editorState.statusMessage =
        "Failed to load theme: " & vr.toErrorMessages.join("; ")

  state.pendingApply = true
  discard state.refreshItems(editorState)

proc hasItem(
    state: ConfigModeState, itemIndex: int, kinds: set[ConfigValueKind]
): bool =
  itemIndex >= 0 and itemIndex < state.items.len and state.items[itemIndex].kind in kinds

# Skip no-op writes to avoid useless theme reloads and re-highlights.

proc setBoolValue*(
    state: ConfigModeState, editorState: EditorState, itemIndex: int, value: bool
) =
  if not state.hasItem(itemIndex, {cvkBool}):
    return
  let item = state.items[itemIndex]
  let desc = item.descriptor
  if desc.boolGet(state.config) != value:
    state.commitChange(
      editorState,
      item,
      proc() =
        desc.boolSet(state.config, value),
    )

proc setIntValue*(
    state: ConfigModeState, editorState: EditorState, itemIndex: int, value: int
) =
  if not state.hasItem(itemIndex, {cvkInt}):
    return
  let item = state.items[itemIndex]
  let desc = item.descriptor
  if desc.intGet(state.config) != value:
    state.commitChange(
      editorState,
      item,
      proc() =
        desc.intSet(state.config, value),
    )

proc setFloatValue*(
    state: ConfigModeState, editorState: EditorState, itemIndex: int, value: float
) =
  if not state.hasItem(itemIndex, {cvkFloat}):
    return
  let item = state.items[itemIndex]
  let desc = item.descriptor
  if desc.floatGet(state.config) != value:
    state.commitChange(
      editorState,
      item,
      proc() =
        desc.floatSet(state.config, value),
    )

proc setTextValue*(
    state: ConfigModeState, editorState: EditorState, itemIndex: int, value: string
) =
  ## Set an enum or string item
  if not state.hasItem(itemIndex, {cvkEnum, cvkString}):
    return
  let item = state.items[itemIndex]
  let desc = item.descriptor
  case item.kind
  of cvkEnum:
    if desc.enumGet(state.config) != value:
      state.commitChange(
        editorState,
        item,
        proc() =
          desc.enumSet(state.config, value),
      )
  of cvkString:
    if desc.stringGet(state.config) != value:
      state.commitChange(
        editorState,
        item,
        proc() =
          desc.stringSetter(state.config, value),
      )
  else:
    discard

proc setColorValue*(state: ConfigModeState, itemIndex: int, value: string) =
  ## Apply a theme color to global `themeColors`; `:w` persists it.
  if not state.hasItem(itemIndex, {cvkColor}):
    return
  let item = state.items[itemIndex]

  let parsed = parseThemeColor(value)
  if parsed.isErr:
    return # Caller validates before calling

  var colors = themeColors
  if item.colorIsFg:
    colors[item.colorIndex].foreground = ThemeColor(rgb: parsed.get)
  else:
    colors[item.colorIndex].background = ThemeColor(rgb: parsed.get)
  setThemeColors(colors)

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

proc matchesSearchQuery*(item: ConfigItem, cfg: EditorConfig, query: string): bool =
  ## Case-insensitive match of `query` against an item's display name and value
  if query.len == 0:
    return false
  let q = query.toLowerAscii
  item.displayName.toLowerAscii.contains(q) or
    item.valueText(cfg).toLowerAscii.contains(q)

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
  state.items[index].matchesSearchQuery(state.config, state.searchQuery)

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
    if state.items[i].matchesSearchQuery(state.config, query):
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
    let item = state.items[itemIndex]
    state.setBoolValue(editorState, itemIndex, not item.boolValue(state.config))

proc cycleEnumValue*(
    state: ConfigModeState, editorState: EditorState, forward: bool = true
) =
  ## Cycle through enum options
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind == cvkEnum and item.enumOptions.len > 0:
    var currentIdx = item.enumOptions.find(item.enumValue(state.config))
    if currentIdx < 0:
      currentIdx = 0
    if forward:
      currentIdx = (currentIdx + 1) mod item.enumOptions.len
    else:
      currentIdx = (currentIdx - 1 + item.enumOptions.len) mod item.enumOptions.len
    state.setTextValue(editorState, itemIndex, item.enumOptions[currentIdx])

proc incrementIntValue*(state: ConfigModeState, editorState: EditorState) =
  ## Increment integer value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkInt:
    let
      item = state.items[itemIndex]
      value = item.intValue(state.config)
    if value < item.intMax:
      state.setIntValue(editorState, itemIndex, value + 1)

proc decrementIntValue*(state: ConfigModeState, editorState: EditorState) =
  ## Decrement integer value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkInt:
    let
      item = state.items[itemIndex]
      value = item.intValue(state.config)
    if value > item.intMin:
      state.setIntValue(editorState, itemIndex, value - 1)

proc incrementFloatValue*(state: ConfigModeState, editorState: EditorState) =
  ## Increment float value by step
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkFloat:
    let
      item = state.items[itemIndex]
      newValue = item.floatValue(state.config) + item.floatStep
    if newValue <= item.floatMax:
      state.setFloatValue(editorState, itemIndex, newValue)

proc decrementFloatValue*(state: ConfigModeState, editorState: EditorState) =
  ## Decrement float value by step
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex >= 0 and state.items[itemIndex].kind == cvkFloat:
    let
      item = state.items[itemIndex]
      newValue = item.floatValue(state.config) - item.floatStep
    if newValue >= item.floatMin:
      state.setFloatValue(editorState, itemIndex, newValue)

# Display formatting

proc itemNamePrefix*(item: ConfigItem, maxNameWidth: int): string =
  ## The indented, padded name column and its separator, in display columns.
  ## Cut to `maxNameWidth` so the value column stays inside a narrow pane.
  let
    indentWidth = min(item.depth * 2, max(0, maxNameWidth))
    nameWidth = max(0, maxNameWidth - indentWidth)
    # No ellipsis when the column is too narrow to hold one.
    name = item.displayName.truncateToWidthWithSuffix(
      nameWidth, if nameWidth > 3: "..." else: ""
    )
  ' '.repeat(indentWidth) & name.alignLeftDisplay(nameWidth) & " : "

proc formatItemForDisplay*(
    item: ConfigItem, cfg: EditorConfig, maxNameWidth: int
): string =
  ## Format a config item for display
  if item.kind == cvkSection:
    "[" & item.displayName & "]"
  else:
    itemNamePrefix(item, maxNameWidth) & item.valueText(cfg)

proc calcMaxNameWidth*(items: seq[ConfigItem], maxWidth: int): int =
  ## Calculate the maximum name width for config item layout, in display columns.
  for item in items:
    if item.kind != cvkSection:
      result = max(result, charDisplayWidth(item.displayName) + item.depth * 2)
  result = min(result + 4, maxWidth div 2)

# Edit mode (Int/String editing)

proc startEdit*(state: ConfigModeState) =
  ## Start editing the current value
  let itemIndex = state.getSelectedItemIndex()
  if itemIndex < 0:
    return

  let item = state.items[itemIndex]
  if item.kind in {cvkInt, cvkFloat, cvkString, cvkColor}:
    state.editMode = true
    state.editBuffer = item.valueText(state.config)
    state.editCursor = state.editBuffer.charLen

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
        state.setIntValue(editorState, itemIndex, newValue)
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
        state.setFloatValue(editorState, itemIndex, newValue)
        state.cancelEdit()
        return true
      else:
        return false # Value out of range
    except ValueError:
      return false # Invalid number
  of cvkString:
    state.setTextValue(editorState, itemIndex, state.editBuffer)
    state.cancelEdit()
    return true
  of cvkColor:
    if parseThemeColor(state.editBuffer).isErr:
      return false # Invalid hex / not "termDefault"; keep editing
    state.setColorValue(itemIndex, state.editBuffer)
    state.cancelEdit()
    return true
  else:
    state.cancelEdit()
    return false

# editCursor is a character index, not a byte offset. Edits recompute it from a
# byte offset because neighbouring bytes can merge into one character.

proc byteOffsetAtCursor(state: ConfigModeState): int =
  ## Byte offset of the character at editCursor, or the buffer end at the tail.
  state.editBuffer.charToBytePos(state.editCursor)

proc editInsertChar*(state: ConfigModeState, c: string) =
  ## Insert a character at cursor position in edit buffer
  if not state.editMode:
    return
  let bytePos = state.byteOffsetAtCursor
  state.editBuffer.insert(c, bytePos)
  state.editCursor = byteToCharPos(state.editBuffer, bytePos + c.len)

proc editBackspace*(state: ConfigModeState) =
  ## Delete the character before the cursor
  if not state.editMode or state.editCursor <= 0:
    return
  let
    endByte = state.byteOffsetAtCursor
    startByte = state.editBuffer.charToBytePos(state.editCursor - 1)
  state.editBuffer.delete(startByte ..< endByte)
  state.editCursor = byteToCharPos(state.editBuffer, startByte)

proc editDelete*(state: ConfigModeState) =
  ## Delete the character at the cursor
  if not state.editMode or state.editCursor >= state.editBuffer.charLen:
    return
  let
    startByte = state.byteOffsetAtCursor
    endByte = startByte + state.editBuffer.runeSizeAt(startByte)
  state.editBuffer.delete(startByte ..< endByte)
  state.editCursor = byteToCharPos(state.editBuffer, startByte)

proc editMoveCursorLeft*(state: ConfigModeState) =
  ## Move cursor left in edit buffer
  if state.editMode and state.editCursor > 0:
    state.editCursor.dec

proc editMoveCursorRight*(state: ConfigModeState) =
  ## Move cursor right in edit buffer
  if state.editMode and state.editCursor < state.editBuffer.charLen:
    state.editCursor.inc

proc editMoveCursorHome*(state: ConfigModeState) =
  ## Move cursor to beginning of edit buffer
  if state.editMode:
    state.editCursor = 0

proc editMoveCursorEnd*(state: ConfigModeState) =
  ## Move cursor to end of edit buffer
  if state.editMode:
    state.editCursor = state.editBuffer.charLen

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
  state.enumPopupIndex = item.enumOptions.find(item.enumValue(state.config))
  if state.enumPopupIndex < 0:
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
    state.setTextValue(editorState, itemIndex, item.enumOptions[state.enumPopupIndex])

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
