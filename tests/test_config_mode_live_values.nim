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

## The Config view reads every value from EditorConfig (or the theme) when it
## shows or changes one, so a change made elsewhere is never written back over.

import std/[unittest, os, strutils]

import
  ../src/moepkg/[
    editor, config, config_loader, config_mode, color, types, key_bindings,
    setting_options, editor_config_reload,
  ]
import ../src/moepkg/command_handlers/[handler_result, result_processor, config_handler]

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  config.theme.kind = tkDefault
  newEditor(config, newValidationResult())

proc run(e: Editor, r: HandlerResult) =
  discard e.processResult(r, e.activeBuffer())

proc openConfig(e: Editor): EditorWindow =
  e.run(HandlerResult(kind: hrConfig))
  result = e.activeWindow
  require result.modeState.kind == mskConfig

proc state(win: EditorWindow): ConfigModeState =
  win.modeState.config

proc select(s: ConfigModeState, section, name: string): int =
  for i, item in s.items:
    if item.section == section and item.displayName == name:
      s.selectedIndex = i
      return i
  raiseAssert section & "." & name & " not listed"

proc press(e: Editor, win: EditorWindow, key: SpecialKey) =
  discard handleConfigModeKey(
    win.state, e.state, 20, KeyCombo(isSpecial: true, special: key, modifiers: {})
  )

proc type(e: Editor, win: EditorWindow, c: string): ConfigModeResult =
  handleConfigModeKey(
    win.state, e.state, 20, KeyCombo(isSpecial: false, char: c, modifiers: {})
  )

proc shown(s: ConfigModeState, index: int): string =
  formatItemForDisplay(s.items[index], s.config, 80)

suite "Config view - values changed elsewhere":
  test ":set while Config is open is not written back over":
    let e = createTestEditor()
    let win = e.openConfig()
    let idx = win.state.select("Standard", "tabStop")
    e.config.standard.tabStop = 2

    e.run(HandlerResult(kind: hrSetIntOption, intOption: isoTabStop, intValue: 8))

    check win.state.shown(idx).endsWith(" : 8")
    e.press(win, skRight)
    check e.config.standard.tabStop == 9

  test "a reload while Config is open is not written back over":
    let e = createTestEditor()
    let win = e.openConfig()
    let idx = win.state.select("Standard", "tabStop")
    e.config.standard.tabStop = 2
    let reloaded = newEditorConfig()
    reloaded.theme.kind = tkDefault
    reloaded.standard.tabStop = 8

    e.applyConfigSettings(reloaded)

    check win.state.shown(idx).endsWith(" : 8")
    e.press(win, skRight)
    check e.config.standard.tabStop == 9

  test "the edit field starts from the current value":
    let e = createTestEditor()
    let win = e.openConfig()
    discard win.state.select("Standard", "tabStop")
    e.run(HandlerResult(kind: hrSetIntOption, intOption: isoTabStop, intValue: 8))

    win.state.startEdit()

    check win.state.editBuffer == "8"

  test "the enum popup starts from the current value":
    let e = createTestEditor()
    let win = e.openConfig()
    let idx = win.state.select("Standard", "colorMode")
    let options = win.state.items[idx].enumOptions
    let other =
      options[(options.find($e.config.standard.colorMode) + 1) mod options.len]
    e.config.standard.colorMode = parseEnum[ColorMode](other)

    win.state.openEnumPopup()

    check options[win.state.enumPopupIndex] == other

  test "two copies of the view see each other's changes":
    let e = createTestEditor()
    let left = e.openConfig()
    e.run(HandlerResult(kind: hrVSplit))
    let right = e.activeWindow
    require right != left
    require right.modeState.kind == mskConfig
    require right.state != left.state
    let idx = left.state.select("Standard", "tabStop")
    discard right.state.select("Standard", "tabStop")
    e.config.standard.tabStop = 2

    e.press(left, skRight)
    e.press(left, skRight)
    check e.config.standard.tabStop == 4
    check right.state.shown(idx).endsWith(" : 4")

    e.press(right, skRight)
    check e.config.standard.tabStop == 5
    check left.state.shown(idx).endsWith(" : 5")

  test "a theme color shows the theme's current value":
    let e = createTestEditor()
    e.config.theme.kind = tkConfig
    e.config.theme.path = getTempDir() / "moe_config_live_theme.toml"
    let win = e.openConfig()
    let idx = win.state.select("Theme Colors", "keyword.fg")

    var colors = themeColors
    colors[EditorColorPairIndex.keyword].foreground = ThemeColor(rgb: rgb("#123456"))
    setThemeColors(colors)

    check win.state.shown(idx).endsWith(" : #123456")
    win.state.startEdit()
    check win.state.editBuffer == "#123456"

suite "Config view - rows shown or hidden by a change elsewhere":
  test "a key refreshes the rows and keeps the selection on its row":
    let e = createTestEditor()
    let win = e.openConfig()
    discard win.state.select("Theme", "kind")
    for item in win.state.items:
      check not (item.section == "Theme" and item.displayName == "path")

    e.config.theme.kind = tkConfig
    e.press(win, skDown)

    let selected = win.state.items[win.state.selectedIndex]
    check selected.section == "Theme"
    check selected.displayName == "path"

  test "an edit is dropped when its row is hidden":
    let e = createTestEditor()
    e.config.theme.kind = tkConfig
    let win = e.openConfig()
    discard win.state.select("Theme", "path")
    win.state.startEdit()
    require win.state.isEditing

    e.config.theme.kind = tkDefault
    discard win.state.refreshItems()

    check not win.state.isEditing
    check win.state.items[win.state.selectedIndex].section == "Theme"

  test "a key meant for a dropped edit does not reach the list":
    let e = createTestEditor()
    e.config.theme.kind = tkConfig
    let win = e.openConfig()
    discard win.state.select("Theme", "path")
    win.state.startEdit()
    require win.state.isEditing

    e.config.theme.kind = tkDefault
    let r = e.type(win, ":")

    check r.kind == cmrHandled
    check not win.state.isEditing
    check e.type(win, ":").kind == cmrEnterCommand

  test "a frame that drops an edit reports it and leaves the next key alone":
    let e = createTestEditor()
    e.config.theme.kind = tkConfig
    let win = e.openConfig()
    discard win.state.select("Theme", "path")
    win.state.startEdit()
    require win.state.isEditing

    e.config.theme.kind = tkDefault
    # The frame path has no key of its own to swallow, so it only reports.
    discard win.state.refreshItems(e.state)
    check not win.state.isEditing
    check e.state.statusMessage == "Setting disappeared; the edit was cancelled"
    check e.type(win, ":").kind == cmrEnterCommand

  test "the search anchor stays on its row":
    let e = createTestEditor()
    e.config.theme.kind = tkConfig
    let win = e.openConfig()
    let anchor = win.state.select("Theme", "path") + 1
    let row = win.state.items[anchor]
    win.state.searchStartIndex = anchor

    e.config.theme.kind = tkDefault
    discard win.state.refreshItems()

    check win.state.searchStartIndex == anchor - 1
    let item = win.state.items[win.state.searchStartIndex]
    check item.section == row.section
    check item.displayName == row.displayName
