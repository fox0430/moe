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

## Tests for editor_render_modes.nim

import std/[unittest, strutils]

import pkg/celina

import
  ../src/moepkg/[
    editor, config, config_loader, config_mode, render_utils, color, colorcode,
    unicode_utils,
  ]
import ../src/moepkg/editor_render_modes
import ../src/moepkg/types/config_mode_types

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  # Use the bundled default theme so the test is hermetic. Without this the
  # default config's tkConfig theme.path (~/.config/moe/themes/dark.toml) would
  # load the user's real theme file, making color assertions environment-
  # dependent (and break entirely if that file is missing or corrupted).
  config.theme.kind = tkDefault
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestBuffer(): Buffer =
  ## Create a minimal Celina Buffer for testing
  result = newBuffer(80, 24)
  result.area = Rect(x: 0, y: 0, width: 80, height: 24)

suite "renderConfig - Basic behavior":
  test "Render with no config state does nothing":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # ConfigModeState is mskNone by default
    check e.windowManager.windows[e.windowManager.activeWindowIndex].modeState.kind ==
      mskNone

    # Should not crash
    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render with config state":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Set up config mode state
    let configState = newConfigModeState(e.config)
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)

    # Should not crash
    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render config with selection":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let configState = newConfigModeState(e.config)
    configState.selectedIndex = 1
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)

    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render config with status line hidden":
    var config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.showStatusLine = false
    var buffer = createTestBuffer()

    let configState = newConfigModeState(e.config)
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)

    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render config with status line shown":
    var config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.showStatusLine = true
    var buffer = createTestBuffer()

    let configState = newConfigModeState(e.config)
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)

    e.renderConfig(buffer, e.activeWindow, true, 0)

suite "renderConfig - search highlight gating":
  proc countSearchHighlightCells(buffer: Buffer): int =
    ## Count cells painted with the search-result highlight background.
    let hlBg = searchHighlightStyle().bg
    result = 0
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        if buffer[x, y].style.bg == hlBg:
          inc result

  proc setupMatchingConfig(e: Editor): ConfigModeState =
    ## Config state whose committed query matches a non-section item, with the
    ## selection parked on a section header so the selected-line style never
    ## collides with the search highlight under test.
    let configState = newConfigModeState(e.config)
    var name = ""
    for item in configState.items:
      if item.kind != cvkSection:
        name = item.displayName
        break
    configState.setSearchQuery(name)
    configState.selectedIndex = 0
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)
    configState

  test "Matches highlighted when hlsearch is on":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    discard e.setupMatchingConfig()
    e.state.input.search.hlsearch = true
    e.state.input.search.hlsearchTempDisabled = false

    e.renderConfig(buffer, e.activeWindow, true, 0)
    check countSearchHighlightCells(buffer) > 0

  test "Only matched characters are highlighted, not the whole line":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let cfg = e.setupMatchingConfig()
    e.state.input.search.hlsearch = true
    e.state.input.search.hlsearchTempDisabled = false

    e.renderConfig(buffer, e.activeWindow, true, 0)
    let highlighted = countSearchHighlightCells(buffer)
    # Like buffer search: only the matched substring cells are painted, far
    # fewer than the full padded line width. Each occurrence contributes
    # exactly query.len cells.
    check highlighted > 0
    check highlighted < buffer.area.width
    check highlighted mod cfg.searchQuery.len == 0

  test "hlsearchTempDisabled hides matches (double-Escape / cross-mode clear)":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    discard e.setupMatchingConfig()
    e.state.input.search.hlsearch = true
    e.state.input.search.hlsearchTempDisabled = true

    e.renderConfig(buffer, e.activeWindow, true, 0)
    check countSearchHighlightCells(buffer) == 0

  test "hlsearch=false hides matches (:noh)":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    discard e.setupMatchingConfig()
    e.state.input.search.hlsearch = false
    e.state.input.search.hlsearchTempDisabled = false

    e.renderConfig(buffer, e.activeWindow, true, 0)
    check countSearchHighlightCells(buffer) == 0

suite "renderConfig - enum popup border":
  let
    borderBg = getThemeStyle(EditorColorPairIndex.configModePopupBg).bg
    selectedBg = getThemeStyle(EditorColorPairIndex.configModePopupSelected).bg

  proc openEnumPopupOnFirstEnum(e: Editor): ConfigModeState =
    ## Park the selection on the first enum item and open its popup, returning
    ## the config state (or nil if the config has no enum items at all).
    let configState = newConfigModeState(e.config)
    var enumIndex = -1
    for i, item in configState.items:
      if item.kind == cvkEnum and item.enumOptions.len >= 2:
        enumIndex = i
        break
    if enumIndex < 0:
      return nil
    configState.selectedIndex = enumIndex
    configState.openEnumPopup()
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)
    configState

  test "Popup background and selected colors differ (theme sanity)":
    # The regression below is only meaningful if the two colors are distinct.
    check borderBg != selectedBg

  test "Side border cells keep the border style on every row":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let configState = e.openEnumPopupOnFirstEnum()
    if configState.isNil:
      skip()
    else:
      check configState.isEnumPopupOpen()
      e.renderConfig(buffer, e.activeWindow, true, 0)

      # Every vertical border character must use the border background, never
      # the selected-row highlight. This is the actual regression: the selected
      # row used to paint its "│" borders with the highlight background, making
      # the highlight bleed into the frame.
      var borderCells = 0
      for y in 0 ..< buffer.area.height:
        for x in 0 ..< buffer.area.width:
          if buffer[x, y].symbol == "│":
            inc borderCells
            check buffer[x, y].style.bg == borderBg
            check buffer[x, y].style.bg != selectedBg
      # Ensure we actually rendered side borders so the check above wasn't
      # vacuous.
      check borderCells > 0

  test "Selected row highlight is applied to the inner content, not the frame":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let configState = e.openEnumPopupOnFirstEnum()
    if configState.isNil:
      skip()
    else:
      e.renderConfig(buffer, e.activeWindow, true, 0)

      # The highlight itself must still be drawn (on the content cells), and it
      # must never land on a "│" border cell.
      var highlightCells = 0
      var highlightOnBorder = 0
      for y in 0 ..< buffer.area.height:
        for x in 0 ..< buffer.area.width:
          if buffer[x, y].style.bg == selectedBg:
            inc highlightCells
            if buffer[x, y].symbol == "│":
              inc highlightOnBorder
      check highlightCells > 0
      check highlightOnBorder == 0

suite "renderConfig - narrow viewport / multibyte":
  test "Narrow viewport width does not crash":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let configState = newConfigModeState(e.config)
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)
    for w in [0, 1, 2, 3, 4]:
      e.activeWindow.viewport.width = w
      e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Multibyte string value truncates without crashing":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let configState = newConfigModeState(e.config)
    var mbIdx = -1
    for i, item in configState.items:
      if item.kind == cvkString:
        configState.items[i].stringValue =
          "あいうえおかきくけこさしすせそ"
        mbIdx = i
        break
    if mbIdx < 0:
      skip()
    else:
      configState.selectedIndex = mbIdx
      e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
        ModeState(kind: mskConfig, config: configState)
      for w in [4, 8, 12]:
        e.activeWindow.viewport.width = w
        e.renderConfig(buffer, e.activeWindow, true, 0)

suite "renderConfig - search highlight with multibyte displayName":
  proc findHighlightedXs(buffer: Buffer, hlBg: ColorValue): seq[int] =
    ## Find X positions of all cells drawn with the search highlight background.
    ## Only returns cells on the first screen row that has any highlighted cells.
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        if buffer[x, y].style.bg == hlBg:
          result.add x

  test "Highlight positioned by display columns, not byte offsets":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let configState = newConfigModeState(e.config)

    # Give the first string item a CJK displayName (multibyte / wide chars)
    # and a short distinctive value so the search match lands after the wide
    # section where byte offset ≠ display columns.
    var strIdx = -1
    for i, item in configState.items:
      if item.kind == cvkString:
        configState.items[i].displayName = "あいう"
        configState.items[i].stringValue = "XY"
        strIdx = i
        break

    if strIdx < 0:
      skip()
    else:
      let maxNameWidth = calcMaxNameWidth(configState.items, buffer.area.width)

      configState.selectedIndex = strIdx
      configState.topLine = strIdx
      configState.setSearchQuery("XY")
      e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
        ModeState(kind: mskConfig, config: configState)
      e.state.input.search.hlsearch = true
      e.state.input.search.hlsearchTempDisabled = false

      e.renderConfig(buffer, e.activeWindow, true, 0)

      let hlBg = searchHighlightStyle().bg
      let hlXs = buffer.findHighlightedXs(hlBg)

      check hlXs.len == 2 # "XY" = 2 characters

      # Compute the expected screen X of the first highlighted cell using the
      # same display-width-aware conversion the fix applies.
      let displayedLine = formatItemForDisplay(configState.items[strIdx], maxNameWidth)
      let byteIdx = displayedLine.find("XY")
      check byteIdx > 0
      let charIdx = displayedLine.byteToCharPos(byteIdx)
      let expectedX = displayWidthUpTo(displayedLine, charIdx)

      check expectedX != byteIdx
        # Precondition: CJK chars make byte offset ≠ display cols
      check hlXs.len > 0
      check hlXs[0] == expectedX

  test "Highlight handles zero-width and combining characters":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let configState = newConfigModeState(e.config)

    # displayName with combining acute accent (U+0301, 2 bytes, 0 cols) and
    # zero-width space (U+200B, 3 bytes, 0 cols). Together these add 5 bytes
    # that contribute 0 display columns, creating a byte/column mismatch.
    var strIdx = -1
    for i, item in configState.items:
      if item.kind == cvkString:
        configState.items[i].displayName = "a\u0301\u200Bb"
        configState.items[i].stringValue = "XY"
        strIdx = i
        break

    if strIdx < 0:
      skip()
    else:
      let maxNameWidth = calcMaxNameWidth(configState.items, buffer.area.width)

      configState.selectedIndex = strIdx
      configState.topLine = strIdx
      configState.setSearchQuery("XY")
      e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
        ModeState(kind: mskConfig, config: configState)
      e.state.input.search.hlsearch = true
      e.state.input.search.hlsearchTempDisabled = false

      e.renderConfig(buffer, e.activeWindow, true, 0)

      let hlBg = searchHighlightStyle().bg
      let hlXs = buffer.findHighlightedXs(hlBg)

      check hlXs.len == 2

      let displayedLine = formatItemForDisplay(configState.items[strIdx], maxNameWidth)
      let byteIdx = displayedLine.find("XY")
      check byteIdx > 0
      let charIdx = displayedLine.byteToCharPos(byteIdx)
      let expectedX = displayWidthUpTo(displayedLine, charIdx)

      check expectedX != byteIdx # Precondition: zero-width/combining chars create gap
      check hlXs.len > 0
      check hlXs[0] == expectedX

suite "renderConfig - color value highlight with multibyte displayName":
  test "Color swatch positioned by display columns, not byte offsets":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let configState = newConfigModeState(e.config)

    configState.items.add ConfigItem(
      kind: cvkColor,
      displayName: "あいう",
      section: "Theme Colors",
      depth: 1,
      descriptorIndex: -1,
      colorIsFg: true,
      colorValue: "#ff0000",
    )
    let colorIdx = configState.items.high

    let maxNameWidth = calcMaxNameWidth(configState.items, buffer.area.width)

    configState.selectedIndex = colorIdx
    configState.topLine = colorIdx
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)

    e.renderConfig(buffer, e.activeWindow, true, 0)

    let swatchBg = colorCodeStyle(parseThemeColor("#ff0000").get).bg
    var swatchXs: seq[int]
    for x in 0 ..< buffer.area.width:
      if buffer[x, 0].style.bg == swatchBg:
        swatchXs.add x

    let displayedLine = formatItemForDisplay(configState.items[colorIdx], maxNameWidth)
    let expectedX = displayWidth(displayedLine) - displayWidth("#ff0000")
    let byteBasedX = displayedLine.len - "#ff0000".len

    check expectedX != byteBasedX # Precondition: CJK chars make byte != display cols
    check swatchXs.len == "#ff0000".len
    check swatchXs[0] == expectedX
