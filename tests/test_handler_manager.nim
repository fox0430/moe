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

import std/[unittest, options, tables]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/command_handlers/handler_manager {.all.}
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

  HandlerManager(
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    motionController: motionController,
    normalHandler: normalHandler,
    insertHandler: insertHandler,
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
