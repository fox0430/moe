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

## Tests for overlay state management (Command, Search, Rename modes)
## Overlay modes sit on top of base modes (Normal, Filer, etc.) without
## changing the underlying mode.

import std/[unittest, options, tables]

import ../src/moepkg/[types, config, modes, registers]

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  EditorState(
    activeWindow: EditorWindow(
      cursor: BufferPosition(line: 0, column: 0),
      preferredColumn: -1,
      screenCursor: CursorPosition(x: 0, y: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
    ),
    display:
      DisplaySettings(showLineCount: true, showLinePercentage: true, showEncoding: true),
    config: newEditorConfig(),
    windowDisplay: WindowDisplayState(viewportReservedLines: 2),
    pendingInput: PendingInputState(
      macroState: MacroState(
        isRecording: false,
        register: '\0',
        recordedKeys: @[],
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        waitingForRegister: false,
        commandType: "",
        pendingCount: 0,
        playbackDepth: 0,
      )
    ),
    registers: initRegisters(),
    overlay: none(OverlayKind),
  )

suite "Overlay - hasOverlay":
  test "Returns false when no overlay is active":
    let state = createTestState()
    check state.hasOverlay == false

  test "Returns true when command overlay is active":
    let state = createTestState()
    state.enterCommandOverlay()
    check state.hasOverlay == true

  test "Returns true when search overlay is active":
    let state = createTestState()
    state.enterSearchOverlay(Forward)
    check state.hasOverlay == true

  test "Returns true when rename overlay is active":
    let state = createTestState()
    state.enterRenameOverlay("test", 0, 0)
    check state.hasOverlay == true

suite "Overlay - isCommandOverlay":
  test "Returns false when no overlay is active":
    let state = createTestState()
    check state.isCommandOverlay == false

  test "Returns true when command overlay is active":
    let state = createTestState()
    state.enterCommandOverlay()
    check state.isCommandOverlay == true

  test "Returns false when search overlay is active":
    let state = createTestState()
    state.enterSearchOverlay(Forward)
    check state.isCommandOverlay == false

  test "Returns false when rename overlay is active":
    let state = createTestState()
    state.enterRenameOverlay("test", 0, 0)
    check state.isCommandOverlay == false

suite "Overlay - isSearchOverlay":
  test "Returns false when no overlay is active":
    let state = createTestState()
    check state.isSearchOverlay == false

  test "Returns false when command overlay is active":
    let state = createTestState()
    state.enterCommandOverlay()
    check state.isSearchOverlay == false

  test "Returns true when search overlay is active":
    let state = createTestState()
    state.enterSearchOverlay(Forward)
    check state.isSearchOverlay == true

  test "Returns false when rename overlay is active":
    let state = createTestState()
    state.enterRenameOverlay("test", 0, 0)
    check state.isSearchOverlay == false

suite "Overlay - isRenameOverlay":
  test "Returns false when no overlay is active":
    let state = createTestState()
    check state.isRenameOverlay == false

  test "Returns false when command overlay is active":
    let state = createTestState()
    state.enterCommandOverlay()
    check state.isRenameOverlay == false

  test "Returns false when search overlay is active":
    let state = createTestState()
    state.enterSearchOverlay(Forward)
    check state.isRenameOverlay == false

  test "Returns true when rename overlay is active":
    let state = createTestState()
    state.enterRenameOverlay("test", 0, 0)
    check state.isRenameOverlay == true

suite "Overlay - enterCommandOverlay":
  test "Sets overlay to command mode":
    let state = createTestState()
    state.enterCommandOverlay()

    check state.overlay.isSome
    check state.overlay.get == okCommand
    check state.input.commandText == ":"
    check state.input.commandCursor == 0

  test "Preserves base mode when entering command overlay":
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.enterCommandOverlay()

    check state.mode == EditorMode.Normal
    check state.isCommandOverlay == true

  test "Sets legacy commandText and commandCursor":
    let state = createTestState()
    state.enterCommandOverlay()

    check state.input.commandText == ":"
    check state.input.commandCursor == 0

  test "Preserves Filer as base mode":
    let state = createTestState()
    state.mode = EditorMode.Filer
    state.enterCommandOverlay()

    check state.mode == EditorMode.Filer
    check state.baseMode == EditorMode.Filer
    check state.isCommandOverlay == true

suite "Overlay - enterSearchOverlay":
  test "Sets overlay to search mode with Forward direction":
    let state = createTestState()
    state.cursor = BufferPosition(line: 5, column: 10)
    state.enterSearchOverlay(Forward)

    check state.overlay.isSome
    check state.overlay.get == okSearch
    check state.input.search.direction == Forward

  test "Sets overlay to search mode with Backward direction":
    let state = createTestState()
    state.enterSearchOverlay(Backward)

    check state.overlay.isSome
    check state.overlay.get == okSearch
    check state.input.search.direction == Backward

  test "Preserves base mode when entering search overlay":
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.enterSearchOverlay(Forward)

    check state.mode == EditorMode.Normal
    check state.isSearchOverlay == true

  test "Initializes search state":
    let state = createTestState()
    state.cursor = BufferPosition(line: 3, column: 7)
    state.enterSearchOverlay(Forward)

    check state.input.search.direction == Forward
    check state.input.search.text == ""
    check state.input.search.startPos == BufferPosition(line: 3, column: 7)
    check state.input.search.historyIndex == -1

  test "Resets hlsearchTempDisabled":
    let state = createTestState()
    state.input.search.hlsearchTempDisabled = true
    state.enterSearchOverlay(Forward)

    check state.input.search.hlsearchTempDisabled == false

  test "Preserves LogViewer as base mode":
    let state = createTestState()
    state.mode = EditorMode.LogViewer
    state.enterSearchOverlay(Forward)

    check state.mode == EditorMode.LogViewer
    check state.baseMode == EditorMode.LogViewer
    check state.isSearchOverlay == true

suite "Overlay - enterRenameOverlay":
  test "Sets overlay to rename mode":
    let state = createTestState()
    state.enterRenameOverlay("myVariable", 10, 5)

    check state.overlay.isSome
    check state.overlay.get == okRename
    check state.renameState.text == "myVariable"
    check state.renameState.originalWord == "myVariable"
    check state.renameState.cursorLine == 10
    check state.renameState.cursorColumn == 5

  test "Preserves base mode when entering rename overlay":
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.enterRenameOverlay("func", 0, 0)

    check state.mode == EditorMode.Normal
    check state.isRenameOverlay == true

  test "Sets legacy renameState":
    let state = createTestState()
    state.enterRenameOverlay("testFunc", 15, 20)

    check state.renameState.text == "testFunc"
    check state.renameState.originalWord == "testFunc"
    check state.renameState.cursorLine == 15
    check state.renameState.cursorColumn == 20

suite "Overlay - exitOverlay":
  test "Clears overlay from command overlay":
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.enterCommandOverlay()

    check state.mode == EditorMode.Normal
    check state.hasOverlay == true
    check state.isCommandOverlay == true

    state.exitOverlay()

    check state.hasOverlay == false
    check state.mode == EditorMode.Normal

  test "Clears overlay from search overlay":
    let state = createTestState()
    state.mode = EditorMode.Filer
    state.enterSearchOverlay(Forward)

    check state.mode == EditorMode.Filer
    check state.hasOverlay == true
    check state.isSearchOverlay == true

    state.exitOverlay()

    check state.hasOverlay == false
    check state.mode == EditorMode.Filer

  test "Clears overlay from rename overlay":
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.enterRenameOverlay("var", 1, 2)

    check state.mode == EditorMode.Normal
    check state.hasOverlay == true
    check state.isRenameOverlay == true

    state.exitOverlay()

    check state.hasOverlay == false
    check state.mode == EditorMode.Normal

  test "Clears legacy command text and cursor":
    let state = createTestState()
    state.enterCommandOverlay()
    state.input.commandText = ":wq"
    state.input.commandCursor = 2

    state.exitOverlay()

    check state.input.commandText == ""
    check state.input.commandCursor == 0

  test "Clears search text and history index":
    let state = createTestState()
    state.enterSearchOverlay(Forward)
    state.input.search.text = "pattern"
    state.input.search.historyIndex = 2

    state.exitOverlay()

    check state.input.search.text == ""
    check state.input.search.historyIndex == -1

  test "Does nothing when no overlay is active":
    let state = createTestState()
    state.mode = EditorMode.Normal

    state.exitOverlay()

    check state.mode == EditorMode.Normal
    check state.hasOverlay == false

suite "Overlay - baseMode":
  test "Returns current mode when no overlay is active":
    let state = createTestState()
    state.mode = EditorMode.Normal
    check state.baseMode == EditorMode.Normal

    state.mode = EditorMode.Filer
    check state.baseMode == EditorMode.Filer

    state.mode = EditorMode.Insert
    check state.baseMode == EditorMode.Insert

  test "Returns base mode when command overlay is active":
    let state = createTestState()
    state.mode = EditorMode.Filer
    state.enterCommandOverlay()

    check state.mode == EditorMode.Filer
    check state.baseMode == EditorMode.Filer

  test "Returns base mode when search overlay is active":
    let state = createTestState()
    state.mode = EditorMode.LogViewer
    state.enterSearchOverlay(Forward)

    check state.mode == EditorMode.LogViewer
    check state.baseMode == EditorMode.LogViewer

  test "Returns base mode when rename overlay is active":
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.enterRenameOverlay("test", 0, 0)

    check state.mode == EditorMode.Normal
    check state.baseMode == EditorMode.Normal

suite "Overlay - mode transitions":
  test "Normal -> Command -> Normal":
    let state = createTestState()
    state.mode = EditorMode.Normal

    # Enter command overlay
    state.enterCommandOverlay()
    check state.mode == EditorMode.Normal
    check state.baseMode == EditorMode.Normal
    check state.hasOverlay == true
    check state.isCommandOverlay == true

    # Exit overlay
    state.exitOverlay()
    check state.mode == EditorMode.Normal
    check state.hasOverlay == false

  test "Filer -> Command -> Filer":
    let state = createTestState()
    state.mode = EditorMode.Filer

    # Enter command overlay from Filer
    state.enterCommandOverlay()
    check state.mode == EditorMode.Filer
    check state.baseMode == EditorMode.Filer
    check state.hasOverlay == true
    check state.isCommandOverlay == true

    # Exit overlay - should return to Filer
    state.exitOverlay()
    check state.mode == EditorMode.Filer
    check state.hasOverlay == false

  test "Normal -> Search -> Normal":
    let state = createTestState()
    state.mode = EditorMode.Normal

    # Enter search overlay
    state.enterSearchOverlay(Forward)
    check state.mode == EditorMode.Normal
    check state.baseMode == EditorMode.Normal
    check state.hasOverlay == true
    check state.isSearchOverlay == true

    # Exit overlay
    state.exitOverlay()
    check state.mode == EditorMode.Normal
    check state.hasOverlay == false

  test "LogViewer -> Search -> LogViewer":
    let state = createTestState()
    state.mode = EditorMode.LogViewer

    # Enter search overlay from LogViewer
    state.enterSearchOverlay(Backward)
    check state.mode == EditorMode.LogViewer
    check state.baseMode == EditorMode.LogViewer
    check state.hasOverlay == true
    check state.isSearchOverlay == true

    # Exit overlay - should return to LogViewer
    state.exitOverlay()
    check state.mode == EditorMode.LogViewer
    check state.hasOverlay == false

  test "Normal -> Rename -> Normal":
    let state = createTestState()
    state.mode = EditorMode.Normal

    # Enter rename overlay
    state.enterRenameOverlay("myFunc", 10, 5)
    check state.mode == EditorMode.Normal
    check state.baseMode == EditorMode.Normal
    check state.hasOverlay == true
    check state.isRenameOverlay == true

    # Exit overlay
    state.exitOverlay()
    check state.mode == EditorMode.Normal
    check state.hasOverlay == false

  test "Switching overlay types clears previous overlay":
    let state = createTestState()
    state.mode = EditorMode.Normal

    # Enter command overlay
    state.enterCommandOverlay()
    check state.isCommandOverlay == true

    # Exit and enter search overlay
    state.exitOverlay()
    state.enterSearchOverlay(Forward)
    check state.isCommandOverlay == false
    check state.isSearchOverlay == true

    # Exit and enter rename overlay
    state.exitOverlay()
    state.enterRenameOverlay("test", 0, 0)
    check state.isSearchOverlay == false
    check state.isRenameOverlay == true

suite "Overlay - special mode transitions":
  test "Normal -> Command -> Config (simulated)":
    ## Simulates: Normal mode, enter :conf command, then enter Config mode
    let state = createTestState()
    state.mode = EditorMode.Normal

    # Enter command overlay (user types ":")
    state.enterCommandOverlay()
    check state.mode == EditorMode.Normal
    check state.baseMode == EditorMode.Normal
    check state.isCommandOverlay == true

    # Simulate executing :conf command
    # Handler should: save baseMode, exit overlay, set previousMode, enter Config
    let baseModeBeforeOverlay = state.baseMode
    state.exitOverlay()
    state.previousMode = baseModeBeforeOverlay
    state.mode = EditorMode.Config

    check state.mode == EditorMode.Config
    check state.previousMode == EditorMode.Normal
    check state.hasOverlay == false

    # Exit Config mode - should return to Normal
    state.mode = state.previousMode
    check state.mode == EditorMode.Normal

  test "Filer -> Command -> Config -> Filer (simulated)":
    ## Simulates: Filer mode, enter :conf, then exit Config back to Filer
    let state = createTestState()
    state.mode = EditorMode.Filer

    # Enter command overlay from Filer
    state.enterCommandOverlay()
    check state.mode == EditorMode.Filer
    check state.baseMode == EditorMode.Filer
    check state.isCommandOverlay == true

    # Simulate executing :conf command
    let baseModeBeforeOverlay = state.baseMode
    state.exitOverlay()
    state.previousMode = baseModeBeforeOverlay
    state.mode = EditorMode.Config

    check state.mode == EditorMode.Config
    check state.previousMode == EditorMode.Filer
    check state.hasOverlay == false

    # Exit Config mode - should return to Filer (not Normal!)
    state.mode = state.previousMode
    check state.mode == EditorMode.Filer

  test "Normal -> Command -> Help (simulated)":
    ## Simulates: Normal mode, enter :help, then enter Help mode
    let state = createTestState()
    state.mode = EditorMode.Normal

    # Enter command overlay
    state.enterCommandOverlay()
    check state.baseMode == EditorMode.Normal

    # Simulate executing :help command
    let baseModeBeforeOverlay = state.baseMode
    state.exitOverlay()
    state.previousMode = baseModeBeforeOverlay
    state.mode = EditorMode.Help

    check state.mode == EditorMode.Help
    check state.previousMode == EditorMode.Normal

  test "Normal -> Command -> BufferManager (simulated)":
    ## Simulates: Normal mode, enter :ls, then enter BufferManager mode
    let state = createTestState()
    state.mode = EditorMode.Normal

    state.enterCommandOverlay()
    let baseModeBeforeOverlay = state.baseMode
    state.exitOverlay()
    state.previousMode = baseModeBeforeOverlay
    state.mode = EditorMode.BufferManager

    check state.mode == EditorMode.BufferManager
    check state.previousMode == EditorMode.Normal

  test "LogViewer -> Search -> LogViewer (simulated)":
    ## Simulates: LogViewer mode, search with /, then cancel search
    let state = createTestState()
    state.mode = EditorMode.LogViewer

    # Enter search overlay
    state.enterSearchOverlay(Forward)
    check state.mode == EditorMode.LogViewer
    check state.baseMode == EditorMode.LogViewer
    check state.isSearchOverlay == true

    # Cancel search (ESC) - should return to LogViewer
    state.exitOverlay()
    check state.mode == EditorMode.LogViewer
    check state.hasOverlay == false

  test "Normal -> Command -> Normal (after :e command, simulated)":
    ## Simulates: Normal mode, enter :e filename, stay in Normal mode
    let state = createTestState()
    state.mode = EditorMode.Normal

    state.enterCommandOverlay()
    check state.baseMode == EditorMode.Normal

    # Simulate executing :e command (no mode transition, just exit overlay)
    state.exitOverlay()

    check state.mode == EditorMode.Normal
    check state.hasOverlay == false

suite "Overlay - edge cases":
  test "Multiple overlays in sequence":
    let state = createTestState()
    state.mode = EditorMode.Normal

    # First overlay: command
    state.enterCommandOverlay()
    check state.baseMode == EditorMode.Normal
    state.exitOverlay()
    check state.mode == EditorMode.Normal

    # Second overlay: search
    state.enterSearchOverlay(Forward)
    check state.baseMode == EditorMode.Normal
    state.exitOverlay()
    check state.mode == EditorMode.Normal

    # Third overlay: rename
    state.enterRenameOverlay("var", 1, 2)
    check state.baseMode == EditorMode.Normal
    state.exitOverlay()
    check state.mode == EditorMode.Normal

  test "Overlay after mode change":
    let state = createTestState()

    # Start in Normal
    state.mode = EditorMode.Normal

    # Change to Filer (without overlay)
    state.previousMode = state.mode
    state.mode = EditorMode.Filer

    # Enter command overlay from Filer
    state.enterCommandOverlay()
    check state.baseMode == EditorMode.Filer
    check state.mode == EditorMode.Filer
    check state.isCommandOverlay == true

    # Exit overlay
    state.exitOverlay()
    check state.mode == EditorMode.Filer

  test "baseMode returns correct mode for all overlay types":
    let state = createTestState()

    # Test with different base modes
    for baseMode in [
      EditorMode.Normal, EditorMode.Filer, EditorMode.LogViewer, EditorMode.Help,
      EditorMode.Config,
    ]:
      state.mode = baseMode
      state.overlay = none(OverlayKind)

      # Command overlay
      state.enterCommandOverlay()
      check state.baseMode == baseMode
      state.exitOverlay()

      # Search overlay
      state.mode = baseMode
      state.enterSearchOverlay(Forward)
      check state.baseMode == baseMode
      state.exitOverlay()

      # Rename overlay
      state.mode = baseMode
      state.enterRenameOverlay("test", 0, 0)
      check state.baseMode == baseMode
      state.exitOverlay()

  test "exitOverlay is idempotent":
    let state = createTestState()
    state.mode = EditorMode.Normal

    # Exit without overlay - should be safe
    state.exitOverlay()
    check state.mode == EditorMode.Normal

    # Enter and exit overlay
    state.enterCommandOverlay()
    state.exitOverlay()
    check state.mode == EditorMode.Normal

    # Exit again - should be safe
    state.exitOverlay()
    check state.mode == EditorMode.Normal

  test "Overlay state is independent of window mode":
    ## Overlay is stored in EditorState, not in EditorWindow
    ## This test verifies the overlay accessors work correctly
    let state = createTestState()
    state.mode = EditorMode.Filer

    state.enterCommandOverlay()

    # EditorState.mode stays at Filer (base mode)
    check state.mode == EditorMode.Filer
    # baseMode should also be Filer
    check state.baseMode == EditorMode.Filer
    # Overlay is active
    check state.isCommandOverlay == true
    # And overlay should be active
    check state.hasOverlay == true
    check state.isCommandOverlay == true
