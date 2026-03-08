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

## Tests for handler_manager.nim
## This module tests the unified handler manager functionality.

import std/[unittest, options, tables, strutils]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/command_line {.all.}
import ../src/moepkg/command_config {.all.}
import ../src/moepkg/command_handlers/handler_manager {.all.}
import ../src/moepkg/command_handlers/command_handler {.all.}
import ../src/moepkg/command_handlers/visual_handler {.all.}
import ../src/moepkg/command_handlers/insert_handler {.all.}

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  result = EditorState(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
  )
  result.registers = initRegisters()

proc createTestViewport(): ViewPort =
  ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80)

proc createTestManager(): HandlerManager =
  ## Create a HandlerManager for testing
  let keyBindingRegistry = newKeyBindingRegistry()
  keyBindingRegistry.setupDefaultBindings()

  let commandRegistry = newCommandRegistry()
  commandRegistry.registerBuiltinCommands()

  let motionController = MotionController()

  let normalHandler = NormalModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
  )

  let insertHandler = newInsertModeHandler(
    keyBindingRegistry, motionController, commandRegistry, autocompleteEnabled = false
  )

  let visualHandler = VisualModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
  )

  let replaceHandler = ReplaceModeHandler(keyBindingRegistry: keyBindingRegistry)

  let commandLineParser = newCommandLineParser()
  let commandConfig = newCommandConfig()
  commandConfig.loadDefaultConfig()
  commandConfig.applyToParser(commandLineParser)
  let commandHandler =
    newCommandModeHandler(commandLineParser, commandConfig, commandRegistry)

  HandlerManager(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
    normalHandler: normalHandler,
    insertHandler: insertHandler,
    commandHandler: commandHandler,
    visualHandler: visualHandler,
    replaceHandler: replaceHandler,
  )

suite "HandlerManager - Overlay Transitions":
  test "Colon key returns overlayTransition for command overlay":
    ## This test ensures that pressing ':' in Normal mode returns
    ## an overlayTransition to okCommand, not just a modeTransition.
    ## This was a bug where overlayTransition was not propagated.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    # Create ':' key combo
    let keyCombo = KeyCombo(isSpecial: false, char: ":", modifiers: {})

    let result = manager.handleNormalMode(buffer, state, viewport, keyCombo)

    check result.kind == hrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okCommand

  test "Forward slash key returns overlayTransition for search overlay":
    ## This test ensures that pressing '/' in Normal mode returns
    ## an overlayTransition to okSearch.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    # Create '/' key combo
    let keyCombo = KeyCombo(isSpecial: false, char: "/", modifiers: {})

    let result = manager.handleNormalMode(buffer, state, viewport, keyCombo)

    check result.kind == hrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okSearch

  test "Question mark key returns overlayTransition for backward search overlay":
    ## This test ensures that pressing '?' in Normal mode returns
    ## an overlayTransition to okSearch (backward direction).
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    # Create '?' key combo
    let keyCombo = KeyCombo(isSpecial: false, char: "?", modifiers: {})

    let result = manager.handleNormalMode(buffer, state, viewport, keyCombo)

    check result.kind == hrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okSearch

suite "HandlerManager - getOverlayTransition helper":
  test "getOverlayTransition returns overlay from hrHandled result":
    let result = HandlerResult(
      kind: hrHandled,
      modeTransition: none(EditorMode),
      overlayTransition: some(okCommand),
      statusMessage: "",
    )
    let transition = result.getOverlayTransition
    check transition.isSome
    check transition.get == okCommand

  test "getOverlayTransition returns none for hrHandled without overlay":
    let result = HandlerResult(
      kind: hrHandled,
      modeTransition: some(EditorMode.Insert),
      overlayTransition: none(OverlayKind),
      statusMessage: "",
    )
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for non-hrHandled results":
    let result = HandlerResult(kind: hrUnhandled)
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for hrQuit":
    let result = HandlerResult(kind: hrQuit, shouldQuit: true)
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for hrError":
    let result = HandlerResult(kind: hrError, errorMessage: "test error")
    let transition = result.getOverlayTransition
    check transition.isNone

proc createVisualTestState(mode: EditorMode): EditorState =
  ## Create an EditorState with visual selection active for testing
  result = EditorState(
    cursor: BufferPosition(line: 0, column: 0),
    mode: mode,
    previousMode: EditorMode.Normal,
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
    ),
    registers: initRegisters(),
    visualSelection: VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 3),
      active: true,
      kind:
        case mode
        of EditorMode.VisualBlock: vskBlock
        of EditorMode.VisualLine: vskLine
        else: vskChar
      ,
    ),
  )

suite "HandlerManager - Visual to Insert mode transaction":
  ## Tests for the bug fix: entering Insert mode from Visual modes
  ## must begin a transaction so that commitTransaction() succeeds
  ## when leaving Insert mode with Escape.

  test "Visual mode 'I' enters Insert with transaction, Escape exits cleanly":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createVisualTestState(EditorMode.Visual)
    let viewport = createTestViewport()

    # Press 'I' in Visual mode
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    let enterResult = manager.handleVisualMode(buffer, state, viewport, iKey)

    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction

    # Now press Escape in Insert mode to exit
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(buffer, state, escKey)

    check exitResult.kind == hrHandled
    check exitResult.modeTransition.isSome
    check exitResult.modeTransition.get == EditorMode.Normal

  test "VisualBlock mode 'I' enters Insert with transaction, Escape exits cleanly":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createVisualTestState(EditorMode.VisualBlock)
    let viewport = createTestViewport()

    # Press 'I' in VisualBlock mode
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    let enterResult = manager.handleVisualMode(buffer, state, viewport, iKey)

    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction

    # Now press Escape in Insert mode to exit
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(buffer, state, escKey)

    check exitResult.kind == hrHandled
    check exitResult.modeTransition.isSome
    check exitResult.modeTransition.get == EditorMode.Normal

  test "VisualLine mode 'I' enters Insert with transaction, Escape exits cleanly":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buffer.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createVisualTestState(EditorMode.VisualLine)
    let viewport = createTestViewport()

    # Press 'I' in VisualLine mode
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    let enterResult = manager.handleVisualMode(buffer, state, viewport, iKey)

    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction

    # Now press Escape in Insert mode to exit
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(buffer, state, escKey)

    check exitResult.kind == hrHandled
    check exitResult.modeTransition.isSome
    check exitResult.modeTransition.get == EditorMode.Normal

  test "Visual mode 'c' enters Insert with transaction, Escape exits cleanly":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createVisualTestState(EditorMode.Visual)
    let viewport = createTestViewport()

    # Press 'c' in Visual mode (change)
    let cKey = KeyCombo(isSpecial: false, char: "c", modifiers: {})
    let enterResult = manager.handleVisualMode(buffer, state, viewport, cKey)

    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction

    # Now press Escape in Insert mode to exit
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(buffer, state, escKey)

    check exitResult.kind == hrHandled
    check exitResult.modeTransition.isSome
    check exitResult.modeTransition.get == EditorMode.Normal

proc createBlockVisualTestState(
    startLine, startCol, endLine, endCol: int
): EditorState =
  ## Create an EditorState with visual block selection for testing
  result = EditorState(
    cursor: BufferPosition(line: endLine, column: endCol),
    mode: EditorMode.VisualBlock,
    previousMode: EditorMode.Normal,
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
    ),
    registers: initRegisters(),
    visualSelection: VisualSelection(
      start: BufferPosition(line: startLine, column: startCol),
      current: BufferPosition(line: endLine, column: endCol),
      active: true,
      kind: vskBlock,
    ),
  )

suite "HandlerManager - Visual Block insert replication":
  test "Block I replicates inserted text to all selected lines":
    ## Pressing 'I' in visual block mode, typing text, then Escape
    ## should replicate the text to all lines in the block selection.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "aaaa\nbbbb\ncccc")
    # Select block from (0,0) to (2,1) — first 2 columns of 3 lines
    let state = createBlockVisualTestState(0, 0, 2, 1)
    let viewport = createTestViewport()

    # Press 'I' in VisualBlock mode
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    let enterResult = manager.handleVisualMode(buffer, state, viewport, iKey)
    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction
    check state.editState.visualBlockInsertContext.isSome

    # Type "XX" in insert mode
    state.mode = EditorMode.Insert
    let xKey = KeyCombo(isSpecial: false, char: "X", modifiers: {})
    discard manager.handleInsertMode(buffer, state, xKey)
    discard manager.handleInsertMode(buffer, state, xKey)

    # Press Escape to leave insert mode — triggers replication
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(buffer, state, escKey)
    check exitResult.kind == hrHandled

    # Verify all 3 lines have "XX" at column 0
    check buffer.getLine(0) == "XXaaaa"
    check buffer.getLine(1) == "XXbbbb"
    check buffer.getLine(2) == "XXcccc"

  test "Block I pads short lines with spaces":
    ## When a line is shorter than the insert column, spaces should be added.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "abcdef\nab\nabcdef")
    # Select block from (0,4) to (2,5) — columns 4-5 of 3 lines, but line 1 is short
    let state = createBlockVisualTestState(0, 4, 2, 5)
    let viewport = createTestViewport()

    # Press 'I' in VisualBlock mode
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    discard manager.handleVisualMode(buffer, state, viewport, iKey)

    # Type "Z" in insert mode
    state.mode = EditorMode.Insert
    let zKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleInsertMode(buffer, state, zKey)

    # Press Escape
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(buffer, state, escKey)

    # Verify line 0 and 2 have "Z" at col 4, line 1 is padded
    check buffer.getLine(0) == "abcdZef"
    check buffer.getLine(1) == "ab  Z"
    check buffer.getLine(2) == "abcdZef"

  test "Block A appends text after block end column on all lines":
    ## Pressing 'A' in visual block mode should insert text at endCol+1.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "aaaa\nbbbb\ncccc")
    # Select block from (0,0) to (2,1) — first 2 columns of 3 lines
    let state = createBlockVisualTestState(0, 0, 2, 1)
    let viewport = createTestViewport()

    # Press 'A' in VisualBlock mode
    let aKey = KeyCombo(isSpecial: false, char: "A", modifiers: {})
    let enterResult = manager.handleVisualMode(buffer, state, viewport, aKey)
    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert

    # Type "YY" in insert mode
    state.mode = EditorMode.Insert
    let yKey = KeyCombo(isSpecial: false, char: "Y", modifiers: {})
    discard manager.handleInsertMode(buffer, state, yKey)
    discard manager.handleInsertMode(buffer, state, yKey)

    # Press Escape
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(buffer, state, escKey)

    # Verify "YY" is inserted at column 2 on all lines
    check buffer.getLine(0) == "aaYYaa"
    check buffer.getLine(1) == "bbYYbb"
    check buffer.getLine(2) == "ccYYcc"

  test "Block c replicates text after block deletion":
    ## Pressing 'c' in visual block mode should delete the block, enter insert,
    ## and replicate typed text to all lines on Escape.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "aXXa\nbXXb\ncXXc")
    # Select block from (0,1) to (2,2) — columns 1-2 ("XX") of 3 lines
    let state = createBlockVisualTestState(0, 1, 2, 2)
    let viewport = createTestViewport()

    # Press 'c' in VisualBlock mode
    let cKey = KeyCombo(isSpecial: false, char: "c", modifiers: {})
    let enterResult = manager.handleVisualMode(buffer, state, viewport, cKey)
    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert

    # After 'c', "XX" should be deleted from all lines
    check buffer.getLine(0) == "aa"
    check buffer.getLine(1) == "bb"
    check buffer.getLine(2) == "cc"

    # Type "Z" in insert mode
    state.mode = EditorMode.Insert
    let zKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleInsertMode(buffer, state, zKey)

    # Press Escape
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(buffer, state, escKey)

    # Verify "Z" is at column 1 on all lines
    check buffer.getLine(0) == "aZa"
    check buffer.getLine(1) == "bZb"
    check buffer.getLine(2) == "cZc"

  test "Block I with no text typed clears context without replication":
    ## Pressing 'I' then immediately Escape should not replicate anything
    ## and should clear the visualBlockInsertContext.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "aaaa\nbbbb\ncccc")
    let state = createBlockVisualTestState(0, 0, 2, 1)
    let viewport = createTestViewport()

    # Press 'I' in VisualBlock mode
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    discard manager.handleVisualMode(buffer, state, viewport, iKey)
    check state.editState.visualBlockInsertContext.isSome

    # Immediately press Escape without typing anything
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(buffer, state, escKey)
    check exitResult.kind == hrHandled

    # Buffer should be unchanged
    check buffer.getLine(0) == "aaaa"
    check buffer.getLine(1) == "bbbb"
    check buffer.getLine(2) == "cccc"
    # Context must be cleared
    check state.editState.visualBlockInsertContext.isNone

  test "Block I with reversed selection (bottom-to-top)":
    ## Selecting from line 2 to line 0 (upward) should work correctly.
    ## min/max normalization ensures proper startLine/endLine.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "aaaa\nbbbb\ncccc")
    # Reversed: start at (2,1), current at (0,0)
    let state = createBlockVisualTestState(2, 1, 0, 0)
    let viewport = createTestViewport()

    # Press 'I' in VisualBlock mode
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    discard manager.handleVisualMode(buffer, state, viewport, iKey)

    # Verify cursor moved to normalized start (line 0, col 0)
    check state.cursor.line == 0
    check state.cursor.column == 0
    check state.editState.visualBlockInsertContext.isSome
    let ctx = state.editState.visualBlockInsertContext.get
    check ctx.startLine == 0
    check ctx.endLine == 2
    check ctx.insertColumn == 0

    # Type "X" and Escape
    state.mode = EditorMode.Insert
    let xKey = KeyCombo(isSpecial: false, char: "X", modifiers: {})
    discard manager.handleInsertMode(buffer, state, xKey)
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(buffer, state, escKey)

    check buffer.getLine(0) == "Xaaaa"
    check buffer.getLine(1) == "Xbbbb"
    check buffer.getLine(2) == "Xcccc"

  test "Block I on single line does not replicate":
    ## When block selection spans only one line, no replication should occur.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "aaaa\nbbbb\ncccc")
    # Single line selection: line 1, columns 0-1
    let state = createBlockVisualTestState(1, 0, 1, 1)
    let viewport = createTestViewport()

    # Press 'I'
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    discard manager.handleVisualMode(buffer, state, viewport, iKey)

    # Type "Z" and Escape
    state.mode = EditorMode.Insert
    let zKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleInsertMode(buffer, state, zKey)
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(buffer, state, escKey)

    # Only line 1 should be modified
    check buffer.getLine(0) == "aaaa"
    check buffer.getLine(1) == "Zbbbb"
    check buffer.getLine(2) == "cccc"

  test "Block A pads short lines with spaces":
    ## When a line is shorter than endCol+1, spaces should pad before appending.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "abcdef\nab\nabcdef")
    # Select block from (0,2) to (2,4) — endCol=4, append at col 5
    let state = createBlockVisualTestState(0, 2, 2, 4)
    let viewport = createTestViewport()

    # Press 'A' in VisualBlock mode
    let aKey = KeyCombo(isSpecial: false, char: "A", modifiers: {})
    discard manager.handleVisualMode(buffer, state, viewport, aKey)

    # Cursor should be at (0, 5)
    check state.cursor.column == 5

    # Type "Z" and Escape
    state.mode = EditorMode.Insert
    let zKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleInsertMode(buffer, state, zKey)
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(buffer, state, escKey)

    # Line 0 and 2 get Z at col 5, line 1 ("ab") gets padded to col 5
    check buffer.getLine(0) == "abcdeZf"
    check buffer.getLine(1) == "ab   Z"
    check buffer.getLine(2) == "abcdeZf"

  test "Non-block Visual I does not set visualBlockInsertContext":
    ## In character-wise visual mode, I should not create block context.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createVisualTestState(EditorMode.Visual)
    let viewport = createTestViewport()

    # Press 'I' in Visual (char) mode
    let iKey = KeyCombo(isSpecial: false, char: "I", modifiers: {})
    discard manager.handleVisualMode(buffer, state, viewport, iKey)

    # Context should NOT be set
    check state.editState.visualBlockInsertContext.isNone
    # Cursor should be at column 0 (non-block behavior)
    check state.cursor.column == 0

suite "HandlerManager - Map list commands":
  test ":nmap with no args and no mappings shows No mapping":
    let manager = createTestManager()
    let buffer = newTextBuffer()

    let result = manager.handleCommandMode(buffer, ":nmap")
    check result.kind == hrHandled
    check result.statusMessage == "No mapping"

  test ":nmap with no args lists existing mappings":
    let manager = createTestManager()
    let buffer = newTextBuffer()

    discard
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "C-a", "g g")

    let result = manager.handleCommandMode(buffer, ":nmap")
    check result.kind == hrHandled
    check "NORMAL" in result.statusMessage
    check "C-a -> g g" in result.statusMessage

  test ":map with no args lists mappings from all modes":
    let manager = createTestManager()
    let buffer = newTextBuffer()

    discard
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "C-a", "g g")
    discard
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "jj", "Escape")

    let result = manager.handleCommandMode(buffer, ":map")
    check result.kind == hrHandled
    check "NORMAL" in result.statusMessage
    check "INSERT" in result.statusMessage

suite "HandlerManager - executeCommandDirect":
  # Existing ctAction commands
  test "window.next returns hrNextWindow":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("window-next")
    check r.isSome
    check r.get.kind == hrNextWindow

  test "file.save returns hrSave":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("save")
    check r.isSome
    check r.get.kind == hrSave

  test "buffer.next.tab returns hrBufferNext":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("buffer-next-tab")
    check r.isSome
    check r.get.kind == hrBufferNext

  # New ctAction LSP commands
  test "lsp.format returns hrLspFormat":
    let manager = createTestManager()
    # Register a test command for lsp.format (not in default key bindings)
    manager.keyBindingRegistry.registerCommand(
      Command(
        name: "test-lsp-format",
        description: "Format (LSP)",
        kind: ctAction,
        commandId: "lsp.format",
        args: @[],
      )
    )
    let r = manager.executeCommandDirect("test-lsp-format")
    check r.isSome
    check r.get.kind == hrLspFormat

  test "lsp.restart returns hrLspRestart":
    let manager = createTestManager()
    manager.keyBindingRegistry.registerCommand(
      Command(
        name: "test-lsp-restart",
        description: "Restart LSP",
        kind: ctAction,
        commandId: "lsp.restart",
        args: @[],
      )
    )
    let r = manager.executeCommandDirect("test-lsp-restart")
    check r.isSome
    check r.get.kind == hrLspRestart

  test "lsp.fold returns hrLspFold":
    let manager = createTestManager()
    manager.keyBindingRegistry.registerCommand(
      Command(
        name: "test-lsp-fold",
        description: "Fold (LSP)",
        kind: ctAction,
        commandId: "lsp.fold",
        args: @[],
      )
    )
    let r = manager.executeCommandDirect("test-lsp-fold")
    check r.isSome
    check r.get.kind == hrLspFold

  # ctCustom commands
  test "lsp.goto.definition returns hrLspGotoDefinition":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-goto-definition")
    check r.isSome
    check r.get.kind == hrLspGotoDefinition

  test "lsp.goto.declaration returns hrLspGotoDeclaration":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-goto-declaration")
    check r.isSome
    check r.get.kind == hrLspGotoDeclaration

  test "lsp.find.references returns hrLspFindReferences":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-find-references")
    check r.isSome
    check r.get.kind == hrLspFindReferences

  test "lsp.codelens.execute returns hrLspCodeLensExecute":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-codelens-execute")
    check r.isSome
    check r.get.kind == hrLspCodeLensExecute

  test "lsp.callhierarchy.incoming returns hrLspCallHierarchyIncoming":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-call-hierarchy")
    check r.isSome
    check r.get.kind == hrLspCallHierarchyIncoming

  test "lsp.callhierarchy.outgoing returns hrLspCallHierarchyOutgoing":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-call-hierarchy-outgoing")
    check r.isSome
    check r.get.kind == hrLspCallHierarchyOutgoing

  test "lsp.goto.type.definition returns hrLspTypeDefinition":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-goto-type-definition")
    check r.isSome
    check r.get.kind == hrLspTypeDefinition

  test "lsp.goto.implementation returns hrLspImplementation":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-goto-implementation")
    check r.isSome
    check r.get.kind == hrLspImplementation

  test "lsp.hover returns hrLspHover":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-hover")
    check r.isSome
    check r.get.kind == hrLspHover

  test "lsp.rename returns hrLspRename with empty newName":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-rename")
    check r.isSome
    check r.get.kind == hrLspRename
    check r.get.hrLspNewName == ""

  test "lsp.selection.range returns hrLspSelectionRange":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-selection-range")
    check r.isSome
    check r.get.kind == hrLspSelectionRange

  test "lsp.document.link returns hrLspDocumentLink":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("lsp-document-link")
    check r.isSome
    check r.get.kind == hrLspDocumentLink

  test "quickrun returns hrQuickRun":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("quickrun")
    check r.isSome
    check r.get.kind == hrQuickRun

  # Unsupported commands (context-dependent) return none
  test "motion command returns none":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("move-left")
    check r.isNone

  test "operator command returns none":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("operator-delete")
    check r.isNone

  # Unknown command returns none
  test "unknown command returns none":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("nonexistent-command")
    check r.isNone

  # ctModeSwitch
  test "mode switch command returns modeTransition":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("switch-to-insert")
    check r.isSome
    check r.get.kind == hrHandled
    check r.get.modeTransition.isSome
    check r.get.modeTransition.get == EditorMode.Insert

  # ctOverlaySwitch
  test "overlay switch command returns overlayTransition":
    let manager = createTestManager()
    let r = manager.executeCommandDirect("switch-to-command")
    check r.isSome
    check r.get.kind == hrHandled
    check r.get.overlayTransition.isSome
    check r.get.overlayTransition.get == okCommand

suite "HandlerManager - o/O open line with auto-indent":
  proc createAutoIndentState(): EditorState =
    ## Create EditorState with autoIndent enabled
    result = EditorState(
      cursor: BufferPosition(line: 0, column: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
      display: DisplaySettings(autoIndent: true, tabStop: 2, expandTab: true),
    )
    result.registers = initRegisters()

  let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
  let oKey = KeyCombo(isSpecial: false, char: "o", modifiers: {})

  test "o enters Insert mode with transaction and auto-indent":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    let result = manager.handleNormalMode(buffer, state, viewport, oKey)

    check result.kind == hrHandled
    check result.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction
    check buffer.len == 2
    check buffer.getLine(1) == "  "
    check state.cursor.line == 1
    check state.cursor.column == 2

  test "o Escape cleans auto-indent":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    discard manager.handleNormalMode(buffer, state, viewport, oKey)
    state.mode = EditorMode.Insert
    let exitResult = manager.handleInsertMode(buffer, state, escKey)

    check exitResult.kind == hrHandled
    check exitResult.modeTransition.get == EditorMode.Normal
    check buffer.getLine(1) == ""
    check not buffer.inTransaction

  test "o Escape undo removes line in single step":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    discard manager.handleNormalMode(buffer, state, viewport, oKey)
    state.mode = EditorMode.Insert
    discard manager.handleInsertMode(buffer, state, escKey)

    # Single undo should restore original buffer
    discard buffer.undo()
    check buffer.len == 1
    check buffer.getLine(0) == "  hello"

  test "o type text Escape preserves indent and text":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    discard manager.handleNormalMode(buffer, state, viewport, oKey)
    state.mode = EditorMode.Insert

    # Type 'x' in Insert mode
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard manager.handleInsertMode(buffer, state, xKey)
    discard manager.handleInsertMode(buffer, state, escKey)

    check buffer.getLine(1) == "  x"

  test "o type text Escape undo removes everything in single step":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    discard manager.handleNormalMode(buffer, state, viewport, oKey)
    state.mode = EditorMode.Insert
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard manager.handleInsertMode(buffer, state, xKey)
    discard manager.handleInsertMode(buffer, state, escKey)

    # Single undo should restore original buffer
    discard buffer.undo()
    check buffer.len == 1
    check buffer.getLine(0) == "  hello"

  test "O Escape cleans auto-indent and single undo removes line":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    # Press O
    let bigOKey = KeyCombo(isSpecial: false, char: "O", modifiers: {})
    discard manager.handleNormalMode(buffer, state, viewport, bigOKey)
    state.mode = EditorMode.Insert
    discard manager.handleInsertMode(buffer, state, escKey)

    check buffer.getLine(0) == ""
    check buffer.getLine(1) == "  hello"

    discard buffer.undo()
    check buffer.len == 1
    check buffer.getLine(0) == "  hello"

  test "i Escape without auto-indent tracking":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    # Press i (simple insert, no line creation)
    let iKey = KeyCombo(isSpecial: false, char: "i", modifiers: {})
    discard manager.handleNormalMode(buffer, state, viewport, iKey)
    state.mode = EditorMode.Insert
    discard manager.handleInsertMode(buffer, state, escKey)

    check buffer.len == 1
    check buffer.getLine(0) == "  hello"

  test "o on line without indent creates empty line":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    discard manager.handleNormalMode(buffer, state, viewport, oKey)
    state.mode = EditorMode.Insert
    discard manager.handleInsertMode(buffer, state, escKey)

    check buffer.len == 2
    check buffer.getLine(1) == ""

    discard buffer.undo()
    check buffer.len == 1
    check buffer.getLine(0) == "hello"

suite "HandlerManager - Repeat last Command mode command (@:)":
  test "@: returns hrExecCommand with command text":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    # Set up command history (":set number" was the last command)
    state.commandState.history = @["set number"]

    # Simulate @: via keybinding registry: @ builds sequence, : completes it
    let atKey = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let atResult = manager.handleNormalMode(buffer, state, viewport, atKey)
    # @ is building a sequence in the keybinding registry (waiting for target char)
    check atResult.kind == hrHandled

    let colonKey = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let colonResult = manager.handleNormalMode(buffer, state, viewport, colonKey)

    # hrExecCommand is returned for handler.nim to execute with full Editor context
    check colonResult.kind == hrExecCommand
    check colonResult.execCommandText == "set number"
    check colonResult.execCommandCount == 1

  test "@: with no command history shows error":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    state.commandState.history = @[]

    let atKey = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    discard manager.handleNormalMode(buffer, state, viewport, atKey)

    let colonKey = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let colonResult = manager.handleNormalMode(buffer, state, viewport, colonKey)

    check colonResult.kind == hrHandled
    check state.statusMessage == "No previous Command mode command"

  test "@: with count passes count in result":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    state.commandState.history = @["set number"]

    # Type "3@:" (count 3, then @:)
    let threeKey = KeyCombo(isSpecial: false, char: "3", modifiers: {})
    discard manager.handleNormalMode(buffer, state, viewport, threeKey)

    let atKey = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    discard manager.handleNormalMode(buffer, state, viewport, atKey)

    let colonKey = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let result = manager.handleNormalMode(buffer, state, viewport, colonKey)

    check result.kind == hrExecCommand
    check result.execCommandText == "set number"
    check result.execCommandCount == 3
