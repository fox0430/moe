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
import ../src/moepkg/[editor, config, config_loader, config_mode]
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
