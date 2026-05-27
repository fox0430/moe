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

import std/[unittest, options]
import pkg/celina
import ../src/moepkg/[editor, config, config_loader, config_mode, render_utils]
import ../src/moepkg/editor_render_modes

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
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
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.display.showStatusLine = false
    var buffer = createTestBuffer()

    let configState = newConfigModeState(e.config)
    e.windowManager.windows[e.windowManager.activeWindowIndex].modeState =
      ModeState(kind: mskConfig, config: configState)

    e.renderConfig(buffer, e.activeWindow, true, 0)

  test "Render config with status line shown":
    var config = newEditorConfig()
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    e.state.display.showStatusLine = true
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
    e.state.search.hlsearch = true
    e.state.search.hlsearchTempDisabled = false

    e.renderConfig(buffer, e.activeWindow, true, 0)
    check countSearchHighlightCells(buffer) > 0

  test "Only matched characters are highlighted, not the whole line":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    let cfg = e.setupMatchingConfig()
    e.state.search.hlsearch = true
    e.state.search.hlsearchTempDisabled = false

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
    e.state.search.hlsearch = true
    e.state.search.hlsearchTempDisabled = true

    e.renderConfig(buffer, e.activeWindow, true, 0)
    check countSearchHighlightCells(buffer) == 0

  test "hlsearch=false hides matches (:noh)":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    discard e.setupMatchingConfig()
    e.state.search.hlsearch = false
    e.state.search.hlsearchTempDisabled = false

    e.renderConfig(buffer, e.activeWindow, true, 0)
    check countSearchHighlightCells(buffer) == 0
