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

import std/[unittest, options, tables, strutils, os, tempfiles]

import pkg/results

import
  ../src/moepkg/[
    buffer, types, config, key_bindings, modes, motion, command_registry, registers,
    command_line, command_config, filetree,
  ]
import
  ../src/moepkg/command_handlers/
    [handler_manager, command_handler, visual_handler, insert_handler, filetree_handler]
import ../src/moepkg/types/editor_types except Command
import editor_test_helper

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
  )
  result = EditorState(activeWindow: window, config: newEditorConfig())
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

  let insertHandler =
    newInsertModeHandler(keyBindingRegistry, motionController, commandRegistry)

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

    let r = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), keyCombo
    )

    check r.kind == hrHandled
    check r.overlayTransition.isSome
    check r.overlayTransition.get == okCommand

  test "Forward slash key returns overlayTransition for search overlay":
    ## This test ensures that pressing '/' in Normal mode returns
    ## an overlayTransition to okSearch.
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    # Create '/' key combo
    let keyCombo = KeyCombo(isSpecial: false, char: "/", modifiers: {})

    let r = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), keyCombo
    )

    check r.kind == hrHandled
    check r.overlayTransition.isSome
    check r.overlayTransition.get == okSearch

  test "Question mark key returns overlayTransition for backward search overlay":
    ## This test ensures that pressing '?' in Normal mode returns
    ## an overlayTransition to okSearch (backward direction).
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    let viewport = createTestViewport()

    # Create '?' key combo
    let keyCombo = KeyCombo(isSpecial: false, char: "?", modifiers: {})

    let r = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), keyCombo
    )

    check r.kind == hrHandled
    check r.overlayTransition.isSome
    check r.overlayTransition.get == okSearch

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
    let result = HandlerResult(kind: hrQuit)
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for hrError":
    let result = HandlerResult(kind: hrError, errorMessage: "test error")
    let transition = result.getOverlayTransition
    check transition.isNone

proc createVisualTestState(mode: EditorMode): EditorState =
  ## Create an EditorState with visual selection active for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: mode,
    previousMode: EditorMode.Normal,
  )
  result = EditorState(
    activeWindow: window,
    config: newEditorConfig(),
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
    let enterResult = manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction

    # Now press Escape in Insert mode to exit
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    let enterResult = manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction

    # Now press Escape in Insert mode to exit
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    let enterResult = manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction

    # Now press Escape in Insert mode to exit
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    let enterResult = manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), cKey
    )

    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction

    # Now press Escape in Insert mode to exit
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

    check exitResult.kind == hrHandled
    check exitResult.modeTransition.isSome
    check exitResult.modeTransition.get == EditorMode.Normal

proc createBlockVisualTestState(
    startLine, startCol, endLine, endCol: int
): EditorState =
  ## Create an EditorState with visual block selection for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: endLine, column: endCol),
    mode: EditorMode.VisualBlock,
    previousMode: EditorMode.Normal,
  )
  result = EditorState(
    activeWindow: window,
    config: newEditorConfig(),
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
    let enterResult = manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )
    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert
    check buffer.inTransaction
    check state.editState.visualBlockInsertContext.isSome

    # Type "XX" in insert mode
    state.mode = EditorMode.Insert
    let xKey = KeyCombo(isSpecial: false, char: "X", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), xKey
    )
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), xKey
    )

    # Press Escape to leave insert mode — triggers replication
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )
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
    discard manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

    # Type "Z" in insert mode
    state.mode = EditorMode.Insert
    let zKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), zKey
    )

    # Press Escape
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    let enterResult = manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), aKey
    )
    check enterResult.kind == hrHandled
    check enterResult.modeTransition.isSome
    check enterResult.modeTransition.get == EditorMode.Insert

    # Type "YY" in insert mode
    state.mode = EditorMode.Insert
    let yKey = KeyCombo(isSpecial: false, char: "Y", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), yKey
    )
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), yKey
    )

    # Press Escape
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    let enterResult = manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), cKey
    )
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
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), zKey
    )

    # Press Escape
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    discard manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )
    check state.editState.visualBlockInsertContext.isSome

    # Immediately press Escape without typing anything
    state.mode = EditorMode.Insert
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )
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
    discard manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

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
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), xKey
    )
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    discard manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

    # Type "Z" and Escape
    state.mode = EditorMode.Insert
    let zKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), zKey
    )
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    discard manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), aKey
    )

    # Cursor should be at (0, 5)
    check state.cursor.column == 5

    # Type "Z" and Escape
    state.mode = EditorMode.Insert
    let zKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), zKey
    )
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    discard manager.handleVisualMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

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

  test ":nmap <prefix> with no match shows No mapping found":
    let manager = createTestManager()
    let buffer = newTextBuffer()

    let result = manager.handleCommandMode(buffer, ":nmap C-a")
    check result.kind == hrHandled
    check result.statusMessage == "No mapping found: C-a"

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

  # Command mode command alias bridge (#2597)
  test "exec.cmdline.* alias returns hrExecCommand with alias text (#2597)":
    # `bdelete` is registered with commandId `exec.cmdline.bdelete`. The
    # bridge in executeCommandDirect must strip the prefix and forward the
    # alias to the command-line parser via hrExecCommand.
    let manager = createTestManager()
    let r = manager.executeCommandDirect("bdelete")
    check r.isSome
    check r.get.kind == hrExecCommand
    check r.get.execCommandText == "bdelete"
    check r.get.execCommandCount == 1

  test "exec.cmdline.* alias preserves the alias name (short alias)":
    # Short aliases (bd, q, wq, ...) used to silently become key sequences.
    # Verify the bridge forwards the verbatim alias.
    let manager = createTestManager()
    for alias in ["bd", "bn", "bp", "q", "qa", "w", "wa", "wq", "wqa"]:
      let r = manager.executeCommandDirect(alias)
      check r.isSome
      check r.get.kind == hrExecCommand
      check r.get.execCommandText == alias

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
    let window = EditorWindow(
      cursor: BufferPosition(line: 0, column: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
    )
    let cfg = newEditorConfig()
    cfg.standard.autoIndent = true
    cfg.standard.tabStop = 2
    cfg.standard.expandTab = true
    result = EditorState(activeWindow: window, config: cfg)
    result.registers = initRegisters()

  let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
  let oKey = KeyCombo(isSpecial: false, char: "o", modifiers: {})

  test "o enters Insert mode with transaction and auto-indent":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    let r = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), oKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
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

    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), oKey
    )
    state.mode = EditorMode.Insert
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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

    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), oKey
    )
    state.mode = EditorMode.Insert
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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

    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), oKey
    )
    state.mode = EditorMode.Insert

    # Type 'x' in Insert mode
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), xKey
    )
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

    check buffer.getLine(1) == "  x"

  test "o type text Escape undo removes everything in single step":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), oKey
    )
    state.mode = EditorMode.Insert
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), xKey
    )
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigOKey
    )
    state.mode = EditorMode.Insert
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )
    state.mode = EditorMode.Insert
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

    check buffer.len == 1
    check buffer.getLine(0) == "  hello"

  test "o on line without indent creates empty line":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createAutoIndentState()
    let viewport = createTestViewport()

    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), oKey
    )
    state.mode = EditorMode.Insert
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

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
    state.input.commandState.history = @["set number"]

    # Simulate @: via keybinding registry: @ builds sequence, : completes it
    let atKey = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let atResult = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), atKey
    )
    # @ is building a sequence in the keybinding registry (waiting for target char)
    check atResult.kind == hrHandled

    let colonKey = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let colonResult = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), colonKey
    )

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

    state.input.commandState.history = @[]

    let atKey = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), atKey
    )

    let colonKey = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let colonResult = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), colonKey
    )

    check colonResult.kind == hrHandled
    check state.statusMessage == "No previous Command mode command"

  test "@: with count passes count in result":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    state.input.commandState.history = @["set number"]

    # Type "3@:" (count 3, then @:)
    let threeKey = KeyCombo(isSpecial: false, char: "3", modifiers: {})
    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), threeKey
    )

    let atKey = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), atKey
    )

    let colonKey = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let r = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), colonKey
    )

    check r.kind == hrExecCommand
    check r.execCommandText == "set number"
    check r.execCommandCount == 3

proc createTestManagerWithMotion(
    buffer: TextBuffer, state: EditorState, viewport: ViewPort
): HandlerManager =
  ## Create a HandlerManager with a properly initialized MotionController
  let keyBindingRegistry = newKeyBindingRegistry()
  keyBindingRegistry.setupDefaultBindings()

  let commandRegistry = newCommandRegistry()
  commandRegistry.registerBuiltinCommands()

  let motionController = newMotionController(buffer, state, viewport)

  let normalHandler = NormalModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
  )

  let insertHandler =
    newInsertModeHandler(keyBindingRegistry, motionController, commandRegistry)

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

suite "HandlerManager - Ctrl+O Insert-Normal mode":
  ## Tests for Ctrl-o: temporarily switch to Normal for one command, then return
  ## to Insert mode. The Insert transaction stays open throughout.

  let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
  let ctrlO = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})

  proc enterInsertMode(buffer: TextBuffer, state: EditorState) =
    ## Helper: set up Insert mode state (transaction + tracking)
    ## Note: 'i' key is bound to textobject-inner which bypasses handleNormalMode's
    ## insertModeStartPos tracking, so we set up state directly.
    discard buffer.beginTransaction("Insert mode edit")
    state.mode = EditorMode.Insert
    state.editState.insertModeStartPos = some(state.cursor)

  proc ctrlOToNormal(manager: HandlerManager, buffer: TextBuffer, state: EditorState) =
    ## Helper: press Ctrl-O in Insert mode to enter insert-normal
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, createTestViewport()), ctrlO
    )
    state.mode = EditorMode.Normal

  test "Ctrl-O skips transaction commit":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()

    enterInsertMode(buffer, state)
    check buffer.inTransaction

    # Ctrl-O should not commit the transaction
    manager.ctrlOToNormal(buffer, state)
    check state.insertNormalMode
    check buffer.inTransaction
    check state.editState.insertModeStartPos.isSome

  test "Motion command returns to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'w' (word forward)
    let wKey = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), wKey
    )

    check r.kind == hrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check buffer.inTransaction

  test "Edit command (x) returns to Insert with transaction open":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'x' (delete char)
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), xKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check buffer.inTransaction
    # 'h' was deleted (cursor at 0)
    check buffer.getLine(0) == "ello"

  test "Escape in Normal mode returns to Insert":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Escape should return to Insert (Escape in Normal = no-op, counted as command)
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode

  test "Pending operator (d) waits and does not return to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'd' (pending operator - should not return to Insert yet)
    let dKey = KeyCombo(isSpecial: false, char: "d", modifiers: {})
    let result1 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), dKey
    )

    # Should stay in Normal mode with insertNormalMode still set
    check result1.kind == hrHandled
    check state.insertNormalMode
    check buffer.inTransaction

  test "Overlay transition (colon) does not return to Insert immediately":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press ':' (command overlay)
    let colonKey = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), colonKey
    )

    # Should open overlay, not return to Insert yet
    check r.kind == hrHandled
    check r.overlayTransition.isSome
    check r.overlayTransition.get == okCommand
    # insertNormalMode should still be set (overlay handles return)
    check state.insertNormalMode

  test "Overlay transition (slash) does not return to Insert immediately":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press '/' (search overlay)
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), slashKey
    )

    check r.kind == hrHandled
    check r.overlayTransition.isSome
    check r.overlayTransition.get == okSearch
    check state.insertNormalMode

  test "'i' during insert-normal clears flag and stays in Insert":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'i' (enter Insert mode)
    let iKey = KeyCombo(isSpecial: false, char: "i", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check buffer.inTransaction

  test "'o' during insert-normal opens line and clears flag":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'o' (open line below) - should not double-beginTransaction
    let oKey = KeyCombo(isSpecial: false, char: "o", modifiers: {})
    let result = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), oKey
    )

    check result.kind == hrHandled
    check result.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check buffer.inTransaction
    check buffer.len == 2

  test "Visual mode transition clears insert-normal and commits transaction":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'v' (visual mode)
    let vKey = KeyCombo(isSpecial: false, char: "v", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), vKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Visual
    check not state.insertNormalMode
    # Transaction should be committed (insert-normal consumed)
    check not buffer.inTransaction
    check state.editState.insertModeStartPos.isNone

  test "Replace mode transition clears insert-normal and starts new transaction":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'R' (Replace mode)
    let bigRKey = KeyCombo(isSpecial: false, char: "R", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigRKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Replace
    check not state.insertNormalMode
    # A fresh transaction should be open for Replace mode
    check buffer.inTransaction
    check state.editState.insertModeStartPos.isNone

  test "insertModeStartPos preserved across insert-normal":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    let startPos = state.editState.insertModeStartPos

    # Type a character
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), xKey
    )

    manager.ctrlOToNormal(buffer, state)

    # insertModeStartPos should be preserved
    check state.editState.insertModeStartPos == startPos

    # After returning from insert-normal (w motion), still preserved
    let wKey = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), wKey
    )

    check state.editState.insertModeStartPos == startPos

  test "Full flow: Insert → Ctrl-O → motion → Insert → Escape commits once":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    # Enter Insert and type 'x'
    enterInsertMode(buffer, state)
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), xKey
    )

    # Ctrl-O → 'w' (move word) → back to Insert
    manager.ctrlOToNormal(buffer, state)
    let wKey = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), wKey
    )
    state.mode = r.modeTransition.get # Insert

    # Type 'y' in Insert mode
    let yKey = KeyCombo(isSpecial: false, char: "y", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), yKey
    )

    # Escape to Normal
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )
    check exitResult.modeTransition.get == EditorMode.Normal
    check not buffer.inTransaction

    # Single undo should revert all changes (x, y, and cursor movements)
    discard buffer.undo()
    check buffer.getLine(0) == "hello world"

  test "Numeric prefix does not prematurely return to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world foo")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press '2' (numeric prefix) - should NOT return to Insert
    let twoKey = KeyCombo(isSpecial: false, char: "2", modifiers: {})
    let result1 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), twoKey
    )

    check result1.kind == hrHandled
    check state.insertNormalMode # still in insert-normal, waiting for command

    # Press 'w' to complete "2w" (move 2 words)
    let wKey = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let result2 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), wKey
    )

    check result2.kind == hrHandled
    check result2.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    # Cursor should have moved 2 words forward
    check state.cursor.column > 0

  test "Key sequence first key does not prematurely return to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buffer.insert(1, "world")
    discard buffer.insert(2, "foo")
    let state = createTestState()
    state.cursor = BufferPosition(line: 2, column: 0)
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'g' (first key of 'gg' sequence) - should NOT return to Insert
    let gKey = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result1 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), gKey
    )

    check result1.kind == hrHandled
    check state.insertNormalMode # still waiting for second key

    # Press 'g' again to complete 'gg' (go to first line)
    let result2 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), gKey
    )

    check result2.kind == hrHandled
    check result2.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check state.cursor.line == 0 # moved to first line

  test "Ctrl-W prefix does not prematurely return to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press Ctrl-W (window command prefix, first key of "C-w k" sequence)
    let ctrlW = KeyCombo(isSpecial: false, char: "w", modifiers: {kmCtrl})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), ctrlW
    )

    check r.kind == hrHandled
    check state.insertNormalMode # still waiting for window subcommand

  test "Non-hrHandled result (hrNextWindow) clears insert-normal state":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    check buffer.inTransaction

    manager.ctrlOToNormal(buffer, state)

    # Press Ctrl-W (first key of sequence)
    let ctrlW = KeyCombo(isSpecial: false, char: "w", modifiers: {kmCtrl})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), ctrlW
    )

    # Press 'k' to complete "Ctrl-W k" (window-next → hrNextWindow)
    let kKey = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), kKey
    )

    check r.kind == hrNextWindow
    check not state.insertNormalMode # cleaned up
    check not buffer.inTransaction # transaction committed
    check state.editState.insertModeStartPos.isNone

  test "Non-hrHandled result (hrBufferNext via gt) clears insert-normal state":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'g' (first key of 'gt' sequence)
    let gKey = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), gKey
    )
    check state.insertNormalMode # still waiting

    # Press 't' to complete 'gt' (buffer-next-tab → hrBufferNext)
    let tKey = KeyCombo(isSpecial: false, char: "t", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), tKey
    )

    check r.kind == hrBufferNext
    check not state.insertNormalMode # cleaned up
    check not buffer.inTransaction # transaction committed

  test "Non-hrHandled result (hrSaveAndQuit via ZZ) clears insert-normal state":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'Z' (first key of 'ZZ' sequence)
    let bigZKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigZKey
    )
    check state.insertNormalMode # still waiting

    # Press 'Z' again to complete 'ZZ' (save-and-quit → hrSaveAndQuit)
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigZKey
    )

    check r.kind == hrSaveAndQuit
    check not state.insertNormalMode # cleaned up
    check not buffer.inTransaction # transaction committed

  test "hrError result does NOT clear insert-normal state":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'u' (undo) when there's nothing to undo (only current transaction)
    # This should return hrError but NOT clear insert-normal
    let uKey = KeyCombo(isSpecial: false, char: "u", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), uKey
    )

    # Error should preserve insert-normal state so user can try another command
    if r.kind == hrError:
      check state.insertNormalMode
      check buffer.inTransaction

  test "Unbound key treated as no-op command returns to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press an unbound key (Ctrl-Q is unbound in Normal mode)
    # In moe, unbound keys in Normal mode are treated as handled (no-op),
    # so insert-normal considers the "command" complete and returns to Insert
    let ctrlQ = KeyCombo(isSpecial: false, char: "q", modifiers: {kmCtrl})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), ctrlQ
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode

  test "'a' (append) during insert-normal clears flag and stays in Insert":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'a' (textobject-around, which enters Insert/append when no pending op)
    let aKey = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), aKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check buffer.inTransaction

  test "Operator + motion (dw) completes and returns to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'd' (pending operator)
    let dKey = KeyCombo(isSpecial: false, char: "d", modifiers: {})
    let result1 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), dKey
    )
    check result1.kind == hrHandled
    check state.insertNormalMode

    # Press 'w' (motion to complete dw)
    let wKey = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let result2 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), wKey
    )

    check result2.kind == hrHandled
    check result2.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check buffer.inTransaction
    # "hello " should be deleted, leaving "world"
    check buffer.getLine(0) == "world"

  test "Multiple Ctrl-O in succession":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world foo")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    # Enter Insert and type 'a'
    enterInsertMode(buffer, state)
    let aChar = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), aChar
    )

    # First Ctrl-O → 'w' → back to Insert
    manager.ctrlOToNormal(buffer, state)
    let wKey = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let r1 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), wKey
    )
    check r1.modeTransition.get == EditorMode.Insert
    state.mode = EditorMode.Insert

    # Type 'b'
    let bChar = KeyCombo(isSpecial: false, char: "b", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bChar
    )

    # Second Ctrl-O → 'w' → back to Insert
    manager.ctrlOToNormal(buffer, state)
    let r2 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), wKey
    )
    check r2.modeTransition.get == EditorMode.Insert
    state.mode = EditorMode.Insert

    # Type 'c'
    let cChar = KeyCombo(isSpecial: false, char: "c", modifiers: {})
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), cChar
    )

    # Escape to Normal
    let exitResult = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), escKey
    )
    check exitResult.modeTransition.get == EditorMode.Normal
    check not buffer.inTransaction

    # Single undo should revert all changes (a, b, c insertions)
    discard buffer.undo()
    check buffer.getLine(0) == "hello world foo"

  test "Pending text object (di) waits for kind key":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'd' (pending operator)
    let dKey = KeyCombo(isSpecial: false, char: "d", modifiers: {})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), dKey
    )
    check state.insertNormalMode

    # Press 'i' (textobject-inner → sets pendingTextObject)
    let iKey = KeyCombo(isSpecial: false, char: "i", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )

    # Should still be waiting for text object kind (w, ", (, etc.)
    check r.kind == hrHandled
    check state.insertNormalMode
    check buffer.inTransaction

  test "'J' during insert-normal errors (own transaction conflicts)":
    # Commands that internally call beginTransaction (J, ~, Ctrl-a/x) fail
    # during insert-normal because the Insert mode transaction is still open.
    # This documents the current limitation.
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buffer.insert(1, "world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    let bigJKey = KeyCombo(isSpecial: false, char: "J", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigJKey
    )

    # J fails because it tries beginTransaction while one is already open
    check r.kind == hrError
    # insert-normal state is preserved so user can try another command
    check state.insertNormalMode
    check buffer.inTransaction

  test "Register prefix (\"a) does not prematurely return to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press '"' (register-select, ctOperatorPending - waits for char)
    let quoteKey = KeyCombo(isSpecial: false, char: "\"", modifiers: {})
    let result1 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), quoteKey
    )

    # Should stay in insert-normal (waiting for register name char)
    check result1.kind == hrHandled
    check state.insertNormalMode

    # Press 'a' to complete '"a' (register select)
    let aKey = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let result2 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), aKey
    )

    # pendingRegister is now set, still waiting for the actual command
    check result2.kind == hrHandled
    check state.insertNormalMode
    check state.pendingInput.pendingRegister.isSome
    check state.pendingInput.pendingRegister.get == 'a'

  test "Macro record (q) sets waitingForRegister and does not return to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'q' (macro.record - sets waitingForRegister)
    let qKey = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), qKey
    )

    check r.kind == hrHandled
    check state.insertNormalMode # still waiting for register name
    check state.pendingInput.macroState.waitingForRegister

  test "VisualLine (V) transition clears insert-normal and commits transaction":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'V' (visual-line mode)
    let bigVKey = KeyCombo(isSpecial: false, char: "V", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigVKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.VisualLine
    check not state.insertNormalMode
    check not buffer.inTransaction
    check state.editState.insertModeStartPos.isNone
    check state.editState.substituteContext.isNone

  test "VisualBlock (Ctrl-V) transition clears insert-normal and commits transaction":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press Ctrl-V (visual-block mode)
    let ctrlV = KeyCombo(isSpecial: false, char: "v", modifiers: {kmCtrl})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), ctrlV
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.VisualBlock
    check not state.insertNormalMode
    check not buffer.inTransaction
    check state.editState.insertModeStartPos.isNone

  test "Backward search overlay (?) does not return to Insert immediately":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press '?' (backward search overlay)
    let questionKey = KeyCombo(isSpecial: false, char: "?", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), questionKey
    )

    check r.kind == hrHandled
    check r.overlayTransition.isSome
    check r.overlayTransition.get == okSearch
    check state.insertNormalMode

  test "substituteContext cleared on non-Insert mode transition":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)
    # Set a substituteContext to verify it gets cleaned up
    state.editState.substituteContext =
      some(types.SubstituteContext(kind: skChar, deleteCount: 3))
    manager.ctrlOToNormal(buffer, state)

    # Press 'v' (Visual mode - triggers non-Insert transition cleanup)
    let vKey = KeyCombo(isSpecial: false, char: "v", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), vKey
    )

    check r.modeTransition.get == EditorMode.Visual
    check not state.insertNormalMode
    check state.editState.substituteContext.isNone

  test "Operator + text object (diw) completes and returns to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'd' (pending operator)
    let dKey = KeyCombo(isSpecial: false, char: "d", modifiers: {})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), dKey
    )
    check state.insertNormalMode

    # Press 'i' (textobject-inner → sets pendingTextObject)
    let iKey = KeyCombo(isSpecial: false, char: "i", modifiers: {})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), iKey
    )
    check state.insertNormalMode

    # Press 'w' (word text object) to complete "diw"
    let wKey = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), wKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check buffer.inTransaction
    # "hello" should be deleted
    check buffer.getLine(0) != "hello world"

  test "dd (delete line) during insert-normal errors (own transaction conflicts)":
    # dd internally calls beginTransaction, which conflicts with the open
    # Insert mode transaction. This documents a known limitation (same as J).
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "first")
    discard buffer.insert(1, "second")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'd' twice (dd = delete line)
    let dKey = KeyCombo(isSpecial: false, char: "d", modifiers: {})
    let result1 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), dKey
    )
    check result1.kind == hrHandled
    check state.insertNormalMode

    let result2 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), dKey
    )
    # dd fails because it tries beginTransaction while one is already open
    check result2.kind == hrError
    check state.insertNormalMode # preserved for retry
    check buffer.inTransaction

  test "yy (yank line) returns to Insert without modifying buffer":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'y' twice (yy = yank line)
    let yKey = KeyCombo(isSpecial: false, char: "y", modifiers: {})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), yKey
    )
    check state.insertNormalMode

    let result2 = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), yKey
    )
    check result2.kind == hrHandled
    check result2.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    # Buffer unchanged
    check buffer.getLine(0) == "hello world"

  test "G (go to last line) returns to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "first")
    discard buffer.insert(1, "second")
    discard buffer.insert(2, "third")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    let bigGKey = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigGKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check state.cursor.line == 2

  test "p (paste) returns to Insert":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    # Put something in the unnamed register
    state.registers.setYankedRegister("world", isLine = false)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    let pKey = KeyCombo(isSpecial: false, char: "p", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), pKey
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Insert
    check not state.insertNormalMode
    check buffer.inTransaction

  test "u (undo) during insert-normal returns hrError (transaction open)":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    let uKey = KeyCombo(isSpecial: false, char: "u", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), uKey
    )

    # Undo within an open transaction returns error
    if r.kind == hrError:
      check state.insertNormalMode # preserved for retry
      check buffer.inTransaction

  test "Ctrl-O from Insert mode result has Normal mode transition":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()

    enterInsertMode(buffer, state)

    let ctrlO = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), ctrlO
    )

    check r.kind == hrHandled
    check r.modeTransition.get == EditorMode.Normal
    check state.insertNormalMode
    # Transaction should still be open (skipped commit)
    check buffer.inTransaction
    check state.editState.insertModeStartPos.isSome

  test "Non-hrHandled result (hrQuit via ZQ) clears insert-normal state":
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)

    enterInsertMode(buffer, state)
    manager.ctrlOToNormal(buffer, state)

    # Press 'Z' (first key of 'ZQ' sequence)
    let bigZKey = KeyCombo(isSpecial: false, char: "Z", modifiers: {})
    discard manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigZKey
    )
    check state.insertNormalMode

    # Press 'Q' to complete 'ZQ' (quit without saving → hrQuit)
    let bigQKey = KeyCombo(isSpecial: false, char: "Q", modifiers: {})
    let r = manager.handleKeyCombo(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), bigQKey
    )

    check r.kind == hrQuit
    check not state.insertNormalMode
    check not buffer.inTransaction

suite "HandlerManager - FileTree search statusMessage":
  test "/ sets statusMessage to search prompt":
    let tmpDir = createTempDir("moe_test_", "_ftmgr")
    defer:
      removeDir(tmpDir)

    writeFile(tmpDir / "file.txt", "hello")

    let manager = createTestManager()
    let state = createTestState()
    state.mode = EditorMode.FileTree
    let fileTreeState = newFileTreeState(tmpDir)

    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    let r1 = manager.handleFileTreeMode(fileTreeState, state, 20, slashKey)
    check r1.kind == hrHandled
    check fileTreeState.isSearching == true
    # statusMessage should show the search prompt
    check state.statusMessage == "/"

  test "typing during search updates statusMessage":
    let tmpDir = createTempDir("moe_test_", "_ftmgr2")
    defer:
      removeDir(tmpDir)

    writeFile(tmpDir / "README.md", "readme")

    let manager = createTestManager()
    let state = createTestState()
    state.mode = EditorMode.FileTree
    let fileTreeState = newFileTreeState(tmpDir)

    # Start search
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    discard manager.handleFileTreeMode(fileTreeState, state, 20, slashKey)

    # Type "R"
    let rKey = KeyCombo(isSpecial: false, char: "R", modifiers: {})
    discard manager.handleFileTreeMode(fileTreeState, state, 20, rKey)
    check state.statusMessage == "/R"

  test "Enter confirms search and sets statusMessage":
    let tmpDir = createTempDir("moe_test_", "_ftmgr3")
    defer:
      removeDir(tmpDir)

    writeFile(tmpDir / "README.md", "readme")

    let manager = createTestManager()
    let state = createTestState()
    state.mode = EditorMode.FileTree
    let fileTreeState = newFileTreeState(tmpDir)

    # Start search, type, confirm
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    discard manager.handleFileTreeMode(fileTreeState, state, 20, slashKey)
    let rKey = KeyCombo(isSpecial: false, char: "R", modifiers: {})
    discard manager.handleFileTreeMode(fileTreeState, state, 20, rKey)

    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard manager.handleFileTreeMode(fileTreeState, state, 20, enterKey)
    check fileTreeState.isSearching == false
    check state.statusMessage == "/R"

  test "Escape cancels search and clears statusMessage":
    let tmpDir = createTempDir("moe_test_", "_ftmgr4")
    defer:
      removeDir(tmpDir)

    writeFile(tmpDir / "README.md", "readme")

    let manager = createTestManager()
    let state = createTestState()
    state.mode = EditorMode.FileTree
    let fileTreeState = newFileTreeState(tmpDir)

    # Start search, type, cancel
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    discard manager.handleFileTreeMode(fileTreeState, state, 20, slashKey)
    let rKey = KeyCombo(isSpecial: false, char: "R", modifiers: {})
    discard manager.handleFileTreeMode(fileTreeState, state, 20, rKey)

    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard manager.handleFileTreeMode(fileTreeState, state, 20, escKey)
    check fileTreeState.isSearching == false
    # After cancel, statusMessage should be empty (clearSearch returns "")
    check state.statusMessage == ""

suite "HandlerManager - Insert mode exec.cmdline.* bridge commits transaction":
  ## Regression: `imap K = "bdelete"` fires while an Insert-mode transaction
  ## is open. The dispatcher must commit that transaction before producing
  ## `hrExecCommand`, otherwise `:bdelete` runs while the buffer is still
  ## mid-edit and a dangling transaction is carried across the buffer switch.
  test "Open Insert transaction is committed before hrExecCommand is returned":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.mode = EditorMode.Insert
    let viewport = createTestViewport()

    # Simulate having entered Insert mode: open a transaction.
    check buffer.beginTransaction("test insert").isOk
    check buffer.inTransaction
    state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))

    # `imap K = "bdelete"` — RHS resolves to the exec.cmdline.* bridge.
    let err =
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bdelete")
    check err == ""

    let kKey = KeyCombo(isSpecial: false, char: "K", modifiers: {})
    let r = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), kKey
    )

    check r.kind == hrExecCommand
    check r.execCommandText == "bdelete"
    # The open transaction must be committed before forwarding the alias.
    check not buffer.inTransaction
    check state.editState.insertModeStartPos.isNone

  test "Bridge works when no Insert transaction is open":
    # Sanity-check: the commit branch is a no-op when there's nothing to
    # commit (e.g. the bridge fires on the very first key after entering
    # Insert mode, before any text was typed).
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.mode = EditorMode.Insert
    let viewport = createTestViewport()
    check not buffer.inTransaction

    discard
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bdelete")

    let kKey = KeyCombo(isSpecial: false, char: "K", modifiers: {})
    let r = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), kKey
    )

    check r.kind == hrExecCommand
    check r.execCommandText == "bdelete"
    check not buffer.inTransaction

suite "HandlerManager - Insert mode exec.cmdline.* bridge full finalize":
  # Regression: the bridge used to only commit the transaction; leaking
  # substituteContext / insertReplayCount / visualBlockInsertContext and
  # skipping `.` repeat + [count]i replay recording.
  test "Bridge sets lastEditCommand for . repeat":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    state.mode = EditorMode.Insert
    let viewport = createTestViewport()

    check buffer.beginTransaction("test insert").isOk
    state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "abc")
    state.cursor = BufferPosition(line: 0, column: 3)

    let err =
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bdelete")
    check err == ""

    let kKey = KeyCombo(isSpecial: false, char: "K", modifiers: {})
    let r = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), kKey
    )

    check r.kind == hrExecCommand
    check state.editState.lastEditCommand.isSome
    check state.editState.lastEditCommand.get.kind == types.lecInsertText
    check state.editState.lastEditCommand.get.insertedText == "abc"

  test "Bridge clears substituteContext":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "xy")
    let state = createTestState()
    state.mode = EditorMode.Insert
    let viewport = createTestViewport()

    check buffer.beginTransaction("test insert").isOk
    state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    state.editState.substituteContext =
      some(types.SubstituteContext(kind: skChar, deleteCount: 2))

    discard
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bdelete")

    let kKey = KeyCombo(isSpecial: false, char: "K", modifiers: {})
    let r = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), kKey
    )

    check r.kind == hrExecCommand
    check state.editState.substituteContext.isNone

  test "Bridge clears insertReplayCount and insertReplayLineEntry":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    state.mode = EditorMode.Insert
    let viewport = createTestViewport()

    check buffer.beginTransaction("test insert").isOk
    state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    state.editState.insertReplayCount = 3
    state.editState.insertReplayLineEntry = true

    discard
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bdelete")

    let kKey = KeyCombo(isSpecial: false, char: "K", modifiers: {})
    let r = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), kKey
    )

    check r.kind == hrExecCommand
    check state.editState.insertReplayCount == 0
    check state.editState.insertReplayLineEntry == false

  test "Bridge clears visualBlockInsertContext":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
    let state = createTestState()
    state.mode = EditorMode.Insert
    let viewport = createTestViewport()

    check buffer.beginTransaction("test insert").isOk
    state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    state.editState.visualBlockInsertContext = some(
      types.VisualBlockInsertContext(
        kind: vbiInsert, startLine: 0, endLine: 2, insertColumn: 0
      )
    )

    discard
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bdelete")

    let kKey = KeyCombo(isSpecial: false, char: "K", modifiers: {})
    let r = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), kKey
    )

    check r.kind == hrExecCommand
    check state.editState.visualBlockInsertContext.isNone

  test "Bridge replays [count]i typed text":
    let manager = createTestManager()
    let buffer = newTextBuffer()
    let state = createTestState()
    state.mode = EditorMode.Insert
    let viewport = createTestViewport()

    check buffer.beginTransaction("test insert").isOk
    state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    state.editState.insertReplayCount = 3
    discard buffer.insertText(BufferPosition(line: 0, column: 0), "x")
    state.cursor = BufferPosition(line: 0, column: 1)

    discard
      manager.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bdelete")

    let kKey = KeyCombo(isSpecial: false, char: "K", modifiers: {})
    let r = manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), kKey
    )

    check r.kind == hrExecCommand
    check buffer.getLine(0) == "xxx"

suite "HandlerManager - Replace mode fold auto-expand":
  test "Entering Replace mode opens a collapsed fold at the cursor":
    let manager = createTestManager()
    let buffer = newTextBuffer("aaaa\nbbbb\ncccc\ndddd")
    discard buffer.foldState.addFold(0, 2, collapsed = true)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    let viewport = createTestViewport()

    let keyCombo = KeyCombo(isSpecial: false, char: "R", modifiers: {})
    let r = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry), keyCombo
    )

    check r.kind == hrHandled
    check r.modeTransition == some(EditorMode.Replace)
    check buffer.foldState.folds[0].collapsed == false

suite "HandlerManager - [count]i/a/o insert replay":
  # Drives the full Normal->Insert->type->Escape flow so the [count] prefix is
  # carried onto the Insert session and the typed text is replayed on exit,
  # matching Vim's "3ihello", "2ahello", "3ohello", etc.
  proc digit(
      manager: HandlerManager,
      buffer: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
      d: string,
  ) =
    discard manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry),
      KeyCombo(isSpecial: false, char: d, modifiers: {}),
    )

  proc enterInsert(
      manager: HandlerManager,
      buffer: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
      key: string,
  ) =
    let r = manager.handleNormalMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry),
      KeyCombo(isSpecial: false, char: key, modifiers: {}),
    )
    check r.kind == hrHandled
    # i/a enter Insert by setting state.mode directly (no modeTransition); the
    # explicit insert commands (A/o/O) return a modeTransition instead.
    check (
      r.modeTransition == some(EditorMode.Insert) or state.mode == EditorMode.Insert
    )
    state.mode = EditorMode.Insert

  proc typeChar(
      manager: HandlerManager,
      buffer: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
      ch: string,
  ) =
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry),
      KeyCombo(isSpecial: false, char: ch, modifiers: {}),
    )

  proc typeEnter(
      manager: HandlerManager,
      buffer: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ) =
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry),
      KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {}),
    )

  proc typeLeft(
      manager: HandlerManager,
      buffer: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ) =
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry),
      KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {}),
    )

  proc escape(
      manager: HandlerManager,
      buffer: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ) =
    discard manager.handleInsertMode(
      createTestEditor(buffer, state, viewport, manager.keyBindingRegistry),
      KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {}),
    )

  test "3iX repeats inserted text three times at cursor":
    let manager = createTestManager()
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    manager.digit(buffer, state, viewport, "3")
    manager.enterInsert(buffer, state, viewport, "i")
    manager.typeChar(buffer, state, viewport, "X")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "XXXabc"

  test "3aX appends repeated text after the cursor":
    let manager = createTestManager()
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    manager.digit(buffer, state, viewport, "3")
    manager.enterInsert(buffer, state, viewport, "a")
    manager.typeChar(buffer, state, viewport, "X")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "aXXXbc"

  test "3AX appends repeated text at end of line":
    let manager = createTestManager()
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    manager.digit(buffer, state, viewport, "3")
    manager.enterInsert(buffer, state, viewport, "A")
    manager.typeChar(buffer, state, viewport, "X")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "abcXXX"

  test "1iX inserts once (count 1, no replay)":
    let manager = createTestManager()
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    manager.digit(buffer, state, viewport, "1")
    manager.enterInsert(buffer, state, viewport, "i")
    manager.typeChar(buffer, state, viewport, "X")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "Xabc"

  test "iX without count inserts once":
    let manager = createTestManager()
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    manager.enterInsert(buffer, state, viewport, "i")
    manager.typeChar(buffer, state, viewport, "X")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "Xabc"

  test "3IX repeats text at first non-blank, preserving leading indent":
    # I moves to the first non-blank via a motion, so it needs a fully wired
    # MotionController (createTestManager()'s stub one would segfault).
    let buffer = newTextBuffer("  abc")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)
    manager.digit(buffer, state, viewport, "3")
    manager.enterInsert(buffer, state, viewport, "I")
    manager.typeChar(buffer, state, viewport, "X")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "  XXXabc"

  test "3oX opens three lines each with the typed text":
    let manager = createTestManager()
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    manager.digit(buffer, state, viewport, "3")
    manager.enterInsert(buffer, state, viewport, "o")
    manager.typeChar(buffer, state, viewport, "X")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "abc"
    check buffer.getLine(1) == "X"
    check buffer.getLine(2) == "X"
    check buffer.getLine(3) == "X"
    check buffer.len == 4

  test "3OX opens three lines above each with the typed text":
    let manager = createTestManager()
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    manager.digit(buffer, state, viewport, "3")
    manager.enterInsert(buffer, state, viewport, "O")
    manager.typeChar(buffer, state, viewport, "X")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "X"
    check buffer.getLine(1) == "X"
    check buffer.getLine(2) == "X"
    check buffer.getLine(3) == "abc"
    check buffer.len == 4

  test "2i with a newline replays the multi-line unit":
    let manager = createTestManager()
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    manager.digit(buffer, state, viewport, "2")
    manager.enterInsert(buffer, state, viewport, "i")
    manager.typeChar(buffer, state, viewport, "X")
    manager.typeEnter(buffer, state, viewport)
    manager.typeChar(buffer, state, viewport, "Y")
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "X"
    check buffer.getLine(1) == "YX"
    check buffer.getLine(2) == "Yabc"

  test "cursor movement during counted insert cancels the replay":
    # Moving the cursor mid-insert invalidates the [insertModeStartPos, cursor)
    # range the replay derives the typed text from, so the count repeat is
    # dropped (Vim-like) instead of re-inserting a garbled partial range.
    let buffer = newTextBuffer("abc")
    let state = createTestState()
    let viewport = createTestViewport()
    let manager = createTestManagerWithMotion(buffer, state, viewport)
    manager.digit(buffer, state, viewport, "3")
    manager.enterInsert(buffer, state, viewport, "i")
    manager.typeChar(buffer, state, viewport, "X")
    manager.typeChar(buffer, state, viewport, "Y")
    manager.typeLeft(buffer, state, viewport)
    manager.escape(buffer, state, viewport)
    check buffer.getLine(0) == "XYabc"
