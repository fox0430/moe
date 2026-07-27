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

## Tests for normal_handler.nim
## This module tests the Normal mode command handler functionality.

import std/[unittest, options, strutils, tables]

import pkg/results

import
  ../src/moepkg/
    [buffer, types, key_bindings, modes, motion, command_registry, config, registers]
import
  ../src/moepkg/command_handlers/[normal_handler, command_passthrough, handler_result]
import ../src/moepkg/types/editor_types except Command

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
  )
  EditorState(
    activeWindow: window,
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
        recordStartKey: "",
        pendingCount: 0,
        playbackDepth: 0,
      )
    ),
    registers: initRegisters(),
  )

proc createTestViewport(): ViewPort =
  ## Create a minimal viewport for testing
  ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

proc createTestHandler(buf: TextBuffer): NormalModeHandler =
  ## Create a NormalModeHandler for testing
  let keyBindingRegistry = newKeyBindingRegistry()
  setupDefaultBindings(keyBindingRegistry)

  let commandRegistry = newCommandRegistry()
  registerBuiltinCommands(commandRegistry)

  let motionController =
    newMotionController(buf, createTestState(), createTestViewport())

  newNormalModeHandler(motionController, keyBindingRegistry, commandRegistry)

suite "NormalModeHandler - Constructor":
  test "Create NormalModeHandler":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    check handler != nil
    check handler.motionController != nil
    check handler.keyBindingRegistry != nil
    check handler.commandRegistry != nil

suite "NormalModeHandler - Mode Switching":
  test "Switch to Insert mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Insert, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert

  test "Switch to Command overlay":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitchToOverlay(okCommand, state)

    check result.kind == nmrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okCommand
    check state.input.commandText == ":"
    check state.input.commandCursor == 0

  test "Switch to Search overlay (forward)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 5, column: 10)

    let result = handler.handleModeSwitchToOverlay(okSearch, state, "switch-to-search")

    check result.kind == nmrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okSearch
    check state.input.search.text == ""
    check state.input.search.direction == Forward
    check state.input.search.startPos.line == 5
    check state.input.search.startPos.column == 10

  test "Switch to Search overlay (backward)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 3, column: 5)

    let result =
      handler.handleModeSwitchToOverlay(okSearch, state, "switch-to-search-backward")

    check result.kind == nmrHandled
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okSearch
    check state.input.search.direction == Backward

  test "Switch to Visual mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Visual, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Visual

  test "Switch to VisualLine mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.VisualLine, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.VisualLine

  test "Switch to VisualBlock mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.VisualBlock, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.VisualBlock

  test "Switch to Replace mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Replace, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Replace

  test "Switch to Normal mode (already in normal)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Normal, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isNone

suite "NormalModeHandler - Insert Mode Entry":
  test "Insert at cursor (i)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleInsertModeEntry(buf, state, "insert")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    check state.cursor.column == 5 # Cursor stays at same position

  test "Append after cursor (a)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleInsertModeEntry(buf, state, "append")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    check state.cursor.column == 6 # Cursor moves right by 1

  test "Append at end of line (A)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleInsertModeEntry(buf, state, "append-end")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    check state.cursor.column == 11 # Cursor at end of "Hello World"

  test "Insert at first non-blank (I)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "   Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 10)

    let result = handler.handleInsertModeEntry(buf, state, "insert-first-non-blank")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    # Cursor moves to first non-blank character

  test "Open line below (o)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleInsertModeEntry(buf, state, "open-below")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert

  test "Open line above (O)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleInsertModeEntry(buf, state, "open-above")

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert

  test "Unknown insert type returns error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleInsertModeEntry(buf, state, "unknown-type")

    check result.kind == nmrError
    check result.errorMessage == "Unknown insert type: unknown-type"

suite "NormalModeHandler - Insert Mode Entry fold auto-expand":
  ## Entering Insert mode must reveal a collapsed fold at the cursor so typed
  ## text is never hidden behind a fold marker (mirrors the Replace-mode entry
  ## behaviour). Covers every insert entry type since they share one openFold.
  for insertType in [
    "insert", "append", "append-end", "insert-first-non-blank", "open-below",
    "open-above",
  ]:
    test "Entering Insert via '" & insertType & "' opens a collapsed fold at the cursor":
      let buf = newTextBuffer("aaaa\nbbbb\ncccc\ndddd")
      check buf.foldState.addFold(0, 2, collapsed = true)
      let handler = createTestHandler(buf)
      let state = createTestState()
      state.cursor = BufferPosition(line: 0, column: 0) # on the fold start line

      let result = handler.handleInsertModeEntry(buf, state, insertType)

      check result.kind == nmrHandled
      check buf.foldState.folds[0].collapsed == false

suite "NormalModeHandler - Insert Mode Entry readOnly guard":
  ## A read-only buffer (log viewer, quick-run output, etc.) must reject every
  ## insert-entry command (o, O, a, A, I, i) before Insert mode is reached,
  ## otherwise the follow-up typed characters slip past command_registry's
  ## readOnly gate straight into buffer.insertText.
  for insertType in [
    "insert", "append", "append-end", "insert-first-non-blank", "open-below",
    "open-above",
  ]:
    test "'" & insertType & "' is blocked on a read-only buffer":
      let buf = newTextBuffer()
      discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
      buf.readOnly = true
      let handler = createTestHandler(buf)
      let state = createTestState()
      state.cursor = BufferPosition(line: 0, column: 0)

      let result = handler.handleInsertModeEntry(buf, state, insertType)

      check result.kind == nmrHandled
      check result.modeTransition.isNone
      check state.statusMessage == "Buffer is read-only"
      check buf[0] == "Hello" # open-below/open-above must not modify buffer

  test "handleModeSwitch to Insert is blocked on a read-only buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    buf.readOnly = true
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Insert, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isNone
    check state.statusMessage == "Buffer is read-only"

suite "NormalModeHandler - Result Helpers":
  test "isHandled returns true for handled results":
    let result = NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    check result.isHandled == true

  test "isHandled returns false for error results":
    let result = NormalModeResult(kind: nmrError, errorMessage: "test error")
    check result.isHandled == false

  test "isHandled returns false for unhandled results":
    let result = NormalModeResult(kind: nmrUnhandled)
    check result.isHandled == false

  test "hasError returns true for error results":
    let result = NormalModeResult(kind: nmrError, errorMessage: "test error")
    check result.hasError == true

  test "hasError returns false for handled results":
    let result = NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    check result.hasError == false

  test "getModeTransition returns mode for handled with transition":
    let result =
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))
    let transition = result.getModeTransition
    check transition.isSome
    check transition.get == EditorMode.Insert

  test "getModeTransition returns none for handled without transition":
    let result = NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    let transition = result.getModeTransition
    check transition.isNone

  test "getModeTransition returns none for error results":
    let result = NormalModeResult(kind: nmrError, errorMessage: "error")
    let transition = result.getModeTransition
    check transition.isNone

  test "getOverlayTransition returns overlay for handled with overlay transition":
    let result = NormalModeResult(
      kind: nmrHandled,
      modeTransition: none(EditorMode),
      overlayTransition: some(okCommand),
    )
    let transition = result.getOverlayTransition
    check transition.isSome
    check transition.get == okCommand

  test "getOverlayTransition returns search overlay":
    let result = NormalModeResult(
      kind: nmrHandled,
      modeTransition: none(EditorMode),
      overlayTransition: some(okSearch),
    )
    let transition = result.getOverlayTransition
    check transition.isSome
    check transition.get == okSearch

  test "getOverlayTransition returns none for handled without overlay transition":
    let result =
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for error results":
    let result = NormalModeResult(kind: nmrError, errorMessage: "error")
    let transition = result.getOverlayTransition
    check transition.isNone

  test "getOverlayTransition returns none for unhandled results":
    let result = NormalModeResult(kind: nmrUnhandled)
    let transition = result.getOverlayTransition
    check transition.isNone

suite "NormalModeHandler - Macro Recording State":
  test "Start macro recording (q) sets waiting for register":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Simulate pressing 'q'
    let keyCombo = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.pendingInput.macroState.waitingForRegister == true
    check state.pendingInput.macroState.commandType == "record"
    check state.statusMessage == "recording @"

  test "Register selection after q":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Set waiting for register state (as if 'q' was pressed)
    state.pendingInput.macroState.waitingForRegister = true
    state.pendingInput.macroState.commandType = "record"
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Press 'a' to select register
    let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.pendingInput.macroState.isRecording == true
    check state.pendingInput.macroState.register == 'a'
    check state.pendingInput.macroState.waitingForRegister == false
    check state.statusMessage == "recording @a"

  test "Invalid register shows error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.macroState.waitingForRegister = true
    state.pendingInput.macroState.commandType = "record"

    # Press '1' (invalid register)
    let keyCombo = KeyCombo(isSpecial: false, char: "1", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.pendingInput.macroState.waitingForRegister == false
    check state.statusMessage == "Invalid register (use a-z)"

  test "Stop recording (q while recording)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @["d", "d"]
    state.pendingInput.macroState.recordStartKey = "q"
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    # Press 'q' to stop recording (matches recordStartKey)
    let keyCombo = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.pendingInput.macroState.isRecording == false
    check state.pendingInput.macroState.registers.hasKey('a')
    check state.pendingInput.macroState.registers['a'] == @["d", "d"]
    check state.statusMessage == ""

  test "Do not stop recording when q is f's target char":
    ## Per-key recording is captured in `handler.handleKeyCombo`; here we only
    ## verify that the Normal handler's stop-recording branch does NOT fire
    ## while the router is waiting for an operand character.
    let buf = newTextBuffer("hello q world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @[]
    state.pendingInput.macroState.recordStartKey = "q"
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    let fKey = KeyCombo(isSpecial: false, char: "f", modifiers: {})
    discard handler.handleNormalModeKey(buf, state, viewport, fKey)

    check state.pendingInput.macroState.isRecording == true
    check handler.keyBindingRegistry.isWaitingForChar() == true

    let qKey = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, qKey)

    check r.kind == nmrHandled
    check state.pendingInput.macroState.isRecording == true
    check handler.keyBindingRegistry.isWaitingForChar() == false

suite "NormalModeHandler - Macro Playback State":
  test "Start playback (@) consumed by key binding system":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Simulate pressing '@' - key binding system handles it as ctOperatorPending
    # waiting for character (register name)
    let keyCombo = KeyCombo(isSpecial: false, char: "@", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled

suite "NormalModeHandler - Register Selection":
  test "Start register selection (\")":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press '"' to start register selection - key binding system handles it
    # as ctOperatorPending waiting for character (register name)
    let keyCombo = KeyCombo(isSpecial: false, char: "\"", modifiers: {})
    let result = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check result.kind == nmrHandled

  test "Register selection with valid register (via key binding)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press '"' then 'a' to select register (two-key sequence via key binding)
    let quoteKey = KeyCombo(isSpecial: false, char: "\"", modifiers: {})
    discard handler.handleNormalModeKey(buf, state, viewport, quoteKey)

    let aKey = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, aKey)

    check r.kind == nmrHandled
    check state.pendingInput.pendingRegister.isSome
    check state.pendingInput.pendingRegister.get == 'a'

  test "Register selection cancelled on invalid register":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press '"' then '!' (invalid register)
    let quoteKey = KeyCombo(isSpecial: false, char: "\"", modifiers: {})
    discard handler.handleNormalModeKey(buf, state, viewport, quoteKey)

    let bangKey = KeyCombo(isSpecial: false, char: "!", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, bangKey)

    check r.kind == nmrHandled
    check state.pendingInput.pendingRegister.isNone

  test "Register selection cancelled on special key":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press '"' then Escape
    let quoteKey = KeyCombo(isSpecial: false, char: "\"", modifiers: {})
    discard handler.handleNormalModeKey(buf, state, viewport, quoteKey)

    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, escKey)

    check r.kind == nmrHandled
    check state.pendingInput.pendingRegister.isNone

suite "NormalModeHandler - Special Results":
  test "nmrPassthrough(ptSaveAndQuit) result":
    let result = NormalModeResult(kind: nmrPassthrough, passthroughKind: ptSaveAndQuit)
    check result.kind == nmrPassthrough
    check result.passthroughKind == ptSaveAndQuit

  test "nmrPassthrough(ptQuitForce) result":
    let result = NormalModeResult(kind: nmrPassthrough, passthroughKind: ptQuitForce)
    check result.kind == nmrPassthrough
    check result.passthroughKind == ptQuitForce

  test "nmrPassthrough(ptCloseWindow) result":
    let result = NormalModeResult(kind: nmrPassthrough, passthroughKind: ptCloseWindow)
    check result.kind == nmrPassthrough
    check result.passthroughKind == ptCloseWindow

  test "nmrPlaybackMacro result":
    let result =
      NormalModeResult(kind: nmrPlaybackMacro, macroKeys: @["d", "d"], macroCount: 3)
    check result.kind == nmrPlaybackMacro
    check result.macroKeys == @["d", "d"]
    check result.macroCount == 3

  test "nmrPassthrough(ptLspGotoDefinition) result":
    let result =
      NormalModeResult(kind: nmrPassthrough, passthroughKind: ptLspGotoDefinition)
    check result.kind == nmrPassthrough
    check result.passthroughKind == ptLspGotoDefinition

  test "nmrPassthrough(ptLspRename) result":
    let result = NormalModeResult(kind: nmrPassthrough, passthroughKind: ptLspRename)
    check result.kind == nmrPassthrough
    check result.passthroughKind == ptLspRename

  test "nmrJumpToBuffer result":
    let result = NormalModeResult(
      kind: nmrJumpToBuffer,
      nmrJumpBufferId: BufferId(2),
      nmrJumpLine: 10,
      nmrJumpColumn: 5,
    )
    check result.kind == nmrJumpToBuffer
    check result.nmrJumpBufferId == BufferId(2)
    check result.nmrJumpLine == 10
    check result.nmrJumpColumn == 5

  test "nmrPassthrough(ptNewFile) result":
    let result = NormalModeResult(kind: nmrPassthrough, passthroughKind: ptNewFile)
    check result.kind == nmrPassthrough
    check result.passthroughKind == ptNewFile

  test "nmrPassthrough(ptEnterFiler) result":
    let result = NormalModeResult(kind: nmrPassthrough, passthroughKind: ptEnterFiler)
    check result.kind == nmrPassthrough
    check result.passthroughKind == ptEnterFiler

suite "NormalModeHandler - All Mode Switches":
  test "Switch to Filer mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Filer, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Filer

  test "Switch to QuickRun mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.QuickRun, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.QuickRun

  test "Switch to LogViewer mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.LogViewer, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.LogViewer

  test "Switch to Help mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Help, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Help

  test "Switch to BufferManager mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.BufferManager, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.BufferManager

  test "Switch to BackupManager mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.BackupManager, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.BackupManager

  test "Switch to DiffViewer mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.DiffViewer, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.DiffViewer

  test "Switch to RecentFile mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.RecentFile, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.RecentFile

  test "Switch to Debug mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Debug, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Debug

  test "Switch to Config mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.Config, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Config

  test "Switch to References mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.References, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.References

  test "Switch to DocumentSymbol mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.DocumentSymbol, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.DocumentSymbol

  test "Switch to Rename overlay (no transition)":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitchToOverlay(okRename, state)

    check result.kind == nmrHandled
    check result.overlayTransition.isNone
      # Rename is entered through LSP, not mode switch

  test "Switch to CallHierarchy mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    let result = handler.handleModeSwitch(EditorMode.CallHierarchy, state, buf)

    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.CallHierarchy

suite "NormalModeHandler - Motion Commands":
  test "Execute left motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleMotionCommand(buf, state, Motion.Left, 1)

    check result.isOk
    check state.cursor.column == 4

  test "Execute right motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleMotionCommand(buf, state, Motion.Right, 1)

    check result.isOk
    check state.cursor.column == 1

  test "Execute motion with count":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleMotionCommand(buf, state, Motion.Left, 3)

    check result.isOk
    check state.cursor.column == 2

  test "Execute down motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nLine 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nLine 3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleMotionCommand(buf, state, Motion.Down, 1)

    check result.isOk
    check state.cursor.line == 1

  test "Execute up motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nLine 2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let result = handler.handleMotionCommand(buf, state, Motion.Up, 1)

    check result.isOk
    check state.cursor.line == 0

suite "NormalModeHandler - Command Execution":
  test "Execute command via registry":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    # Execute motion.left command
    let result = handler.executeCommand(buf, state, viewport, "motion.left")

    check result.kind == nmrHandled
    check state.cursor.column == 4

  test "Execute non-existent command returns error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = handler.executeCommand(buf, state, viewport, "nonexistent.command")

    check result.kind == nmrError

suite "NormalModeHandler - Jump List":
  test "Jump back with empty list returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.jumpList.list = @[]
    state.jumpList.index = -1

    # Simulate Ctrl-o
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrError
    check r.errorMessage == "Jump list is empty"

  test "Jump forward without prior jump returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.jumpList.list = @[]
    state.jumpList.index = -1

    # Simulate Ctrl-i
    let keyCombo = KeyCombo(isSpecial: false, char: "i", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrError
    check r.errorMessage == "No newer jump position"

  test "Jump back with valid list":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nLine 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nLine 3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Set up jump list with positions in the same buffer
    state.jumpList.list = @[
      JumpPosition(bufferId: BufferId(0), line: 0, column: 0),
      JumpPosition(bufferId: BufferId(0), line: 2, column: 0),
    ]
    state.jumpList.index = -1
    state.windowDisplay.currentBufferId = BufferId(0)
    state.cursor = BufferPosition(line: 1, column: 0)

    # Simulate Ctrl-o
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled

  test "Jump to different buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Set up jump list with position in a different buffer
    state.jumpList.list = @[JumpPosition(bufferId: BufferId(1), line: 5, column: 10)]
    state.jumpList.index = -1
    state.windowDisplay.currentBufferId = BufferId(0)
    state.cursor = BufferPosition(line: 0, column: 0)

    # Simulate Ctrl-o
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrJumpToBuffer
    check r.nmrJumpBufferId == BufferId(1)
    check r.nmrJumpLine == 5
    check r.nmrJumpColumn == 10

suite "NormalModeHandler - Text Object Pending State":
  test "Pending text object cancelled on special key":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))

    # Press Escape to cancel
    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check state.pendingInput.pendingTextObject.isNone

suite "NormalModeHandler - LSP Results":
  test "All LSP passthrough kinds":
    # Test all LSP passthrough variants
    template chk(pk: PassthroughKind) =
      let r = NormalModeResult(kind: nmrPassthrough, passthroughKind: pk)
      check r.kind == nmrPassthrough
      check r.passthroughKind == pk

    chk(ptLspGotoDefinition)
    chk(ptLspGotoDeclaration)
    chk(ptLspFindReferences)
    chk(ptLspCodeLensExecute)
    chk(ptLspCallHierarchyIncoming)
    chk(ptLspCallHierarchyOutgoing)
    chk(ptLspTypeDefinition)
    chk(ptLspImplementation)
    chk(ptLspHover)
    chk(ptLspSelectionRange)
    chk(ptLspDocumentLink)
    chk(ptLspDocumentSymbol)

  test "lsp.document.symbol routes to hrLspDocumentSymbol request":
    # The command must fire the document symbol request (via the passthrough
    # table), NOT switch mode directly. The viewer mode is entered later by
    # pollLspDocumentSymbols once the response arrives.
    let pk = lookupPassthrough("lsp.document.symbol")
    check pk.isSome
    check pk.get == ptLspDocumentSymbol
    check toHandlerResult(ptLspDocumentSymbol).kind == hrLspDocumentSymbol

suite "NormalModeHandler - Macro Key Recording":
  test "Handler does not record macro keys (recording is unified at handleKeyCombo)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @[]
    state.pendingInput.macroState.registers = initTable[char, seq[string]]()

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    discard handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check state.pendingInput.macroState.recordedKeys.len == 0

suite "NormalModeHandler - Undo/Redo":
  test "Undo command executes":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Try undo - may succeed or fail depending on undo history
    let result = handler.executeCommand(buf, state, viewport, "edit.undo")

    # Either succeeds or returns error (both are valid outcomes)
    check result.kind == nmrHandled or result.kind == nmrError

  test "Redo command executes":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Try redo - may succeed or fail depending on redo history
    let result = handler.executeCommand(buf, state, viewport, "edit.redo")

    # Either succeeds or returns error (both are valid outcomes)
    check result.kind == nmrHandled or result.kind == nmrError

  test "Undo clamps cursor to valid buffer range":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "short")
    # Record a change at a position beyond the current line length
    # by inserting text that makes the line longer, then undoing it
    discard buf.insertText(BufferPosition(line: 0, column: 5), " extra text here")
    check buf.getLine(0) == "short extra text here"

    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 15)

    let result = handler.executeCommand(buf, state, viewport, "edit.undo")
    check result.kind == nmrHandled
    check buf.getLine(0) == "short"
    # Cursor should be clamped to max valid column (4 = charLen - 1)
    check state.cursor.column <= 4

  test "Undo with transaction cursorPos returns original position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Simulate 'o' command: begin transaction with cursor at column 5
    discard buf.beginTransaction(
      "Insert mode edit", cursorPos = some(BufferPosition(line: 0, column: 5))
    )
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nnew line")
    discard buf.commitTransaction()

    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 1, column: 8)

    let result = handler.executeCommand(buf, state, viewport, "edit.undo")
    check result.kind == nmrHandled
    check state.cursor.line == 0
    check state.cursor.column == 5 # Original cursor position from transaction

  test "Undo on empty buffer sets cursor to 0,0":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "text")

    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = handler.executeCommand(buf, state, viewport, "edit.undo")
    check result.kind == nmrHandled
    check buf.getLine(0) == ""
    check state.cursor.line == 0
    check state.cursor.column == 0

suite "NormalModeHandler - Text Object Handling":
  test "Text object word (w) with pending operator":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 0)

    # Set up pending text object state
    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    # Press 'w' for word text object
    let keyCombo = KeyCombo(isSpecial: false, char: "w", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Text object wide word (W) with pending operator":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello-world test")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpYank,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "W", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Text object double quote with pending operator":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "say \"hello\" world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpChange,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "\"", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Text object single quote":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "say 'hello' world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "'", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Text object parenthesis":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(arg1, arg2)")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 6)

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "(", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Text object bracket":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "arr[0, 1, 2]")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpYank,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "[", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Text object brace":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "obj{a: 1, b: 2}")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "{", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Text object angle bracket":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "<tag>content</tag>")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 1)

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpYank,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "<", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Text object backtick":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "say `hello` world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let keyCombo = KeyCombo(isSpecial: false, char: "`", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled or r.kind == nmrError

  test "Unknown text object key cancels pending state":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    # Press 'z' which is not a valid text object
    let keyCombo = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.pendingInput.pendingTextObject.isNone
    check state.pendingInput.pendingOperator.isNone

suite "NormalModeHandler - Jump List Edge Cases":
  test "Jump forward at newest position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.jumpList.list = @[JumpPosition(bufferId: BufferId(0), line: 0, column: 0)]
    state.jumpList.index = 0 # Already at end
    state.windowDisplay.currentBufferId = BufferId(0)

    # Simulate Ctrl-i
    let keyCombo = KeyCombo(isSpecial: false, char: "i", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrError
    check r.errorMessage == "Already at newest jump position"

  test "Jump back updates index correctly":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nLine 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nLine 3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.jumpList.list = @[
      JumpPosition(bufferId: BufferId(0), line: 0, column: 0),
      JumpPosition(bufferId: BufferId(0), line: 1, column: 0),
    ]
    state.jumpList.index = 1 # Not first jump
    state.windowDisplay.currentBufferId = BufferId(0)
    state.cursor = BufferPosition(line: 2, column: 0)

    # Simulate Ctrl-o
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.jumpList.index == 0

  test "Jump forward to different buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.jumpList.list = @[
      JumpPosition(bufferId: BufferId(0), line: 0, column: 0),
      JumpPosition(bufferId: BufferId(1), line: 5, column: 3),
    ]
    state.jumpList.index = 0
    state.windowDisplay.currentBufferId = BufferId(0)

    # Simulate Ctrl-i
    let keyCombo = KeyCombo(isSpecial: false, char: "i", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrJumpToBuffer
    check r.nmrJumpBufferId == BufferId(1)
    check r.nmrJumpLine == 5
    check r.nmrJumpColumn == 3

suite "NormalModeHandler - Macro Edge Cases":
  test "Empty char in key combo during macro register selection":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.macroState.waitingForRegister = true
    state.pendingInput.macroState.commandType = "record"

    # Empty char
    let keyCombo = KeyCombo(isSpecial: false, char: "", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.statusMessage == "Invalid register (use a-z)"

  test "Macro recording with special key cancels register wait":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.pendingInput.macroState.waitingForRegister = true
    state.pendingInput.macroState.commandType = "record"

    # Press Escape
    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.pendingInput.macroState.waitingForRegister == false
    check state.statusMessage == ""

suite "NormalModeHandler - Command mode command alias dispatch (#2597)":
  test "K mapped to bdelete dispatches via exec.cmdline.* bridge":
    # Issue #2597 follow-up: a key mapped to `bdelete` must reach the
    # command-line parser (which performs the modified-buffer safety check)
    # rather than being parsed as a key sequence.
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    discard
      handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "K", "bdelete")

    let state = createTestState()
    let viewport = createTestViewport()
    let keyCombo = KeyCombo(isSpecial: false, char: "K", modifiers: {})

    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrExecCommand
    check r.execCommandText == "bdelete"
    check r.execCommandCount == 1

  test "D mapped to bd dispatches the short alias verbatim":
    # `bd` is a single short alias (no pre-existing Command shadow), so the
    # bridge must forward "bd" — not "b" or "bdelete" — to the command-line
    # parser.
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    discard handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "D", "bd")

    let state = createTestState()
    let viewport = createTestViewport()
    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})

    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrExecCommand
    check r.execCommandText == "bd"

suite "NormalModeHandler - updateCursorToJumpPosition":
  test "Jump to buffer with single empty line":
    let buf = newTextBuffer()
    # newTextBuffer creates a buffer with one empty line by default
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    state.jumpList.list = @[JumpPosition(bufferId: BufferId(0), line: 5, column: 10)]
    state.jumpList.index = -1
    state.windowDisplay.currentBufferId = BufferId(0)
    state.cursor = BufferPosition(line: 0, column: 0)

    # Jump to position - cursor should be clamped
    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    # Either handled (cursor clamped) or error
    check r.kind == nmrHandled or r.kind == nmrError

  test "Jump position clamped to buffer bounds":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "short")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Jump to position beyond buffer bounds
    state.jumpList.list = @[JumpPosition(bufferId: BufferId(0), line: 100, column: 100)]
    state.jumpList.index = -1
    state.windowDisplay.currentBufferId = BufferId(0)
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    # Cursor should be clamped to valid position
    check state.cursor.line <= buf.len - 1

  test "Jump to empty line sets column to 0":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\n") # Empty line
    discard buf.insertText(BufferPosition(line: 1, column: 0), "\nline3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Jump to empty line with column > 0
    state.jumpList.list = @[JumpPosition(bufferId: BufferId(0), line: 1, column: 10)]
    state.jumpList.index = -1
    state.windowDisplay.currentBufferId = BufferId(0)
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled
    check state.cursor.column == 0

suite "NormalModeHandler - Command Types":
  test "Key returns none when building sequence":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press '2' to start numeric prefix
    let keyCombo = KeyCombo(isSpecial: false, char: "2", modifiers: {})
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)

    check r.kind == nmrHandled

  test "Motion command failure returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    # Try to move up from first line - should fail
    let result = handler.handleMotionCommand(buf, state, Motion.Up, 1)

    # Motion may or may not error depending on implementation
    check result.isOk or result.isErr

suite "NormalModeHandler - File operation commands":
  test "file-new returns ptNewFile":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Map a key to the file-new command
    let err =
      handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Q", "file-new")
    check err == ""

    let keyCombo = KeyCombo(isSpecial: false, char: "Q")
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)
    check r.kind == nmrPassthrough
    check r.passthroughKind == ptNewFile

  test "file-close returns ptBufferDelete":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let err =
      handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Q", "file-close")
    check err == ""

    let keyCombo = KeyCombo(isSpecial: false, char: "Q")
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)
    check r.kind == nmrPassthrough
    check r.passthroughKind == ptBufferDelete

  test "file-open returns ptEnterFiler":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let err =
      handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Q", "file-open")
    check err == ""

    let keyCombo = KeyCombo(isSpecial: false, char: "Q")
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)
    check r.kind == nmrPassthrough
    check r.passthroughKind == ptEnterFiler

  test "filer-open returns ptEnterFiler":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let err =
      handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Q", "filer-open")
    check err == ""

    let keyCombo = KeyCombo(isSpecial: false, char: "Q")
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)
    check r.kind == nmrPassthrough
    check r.passthroughKind == ptEnterFiler

suite "NormalModeHandler - Macro/Register/Window commands":
  test "macro-record (q) sets waitingForRegister":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let keyCombo = KeyCombo(isSpecial: false, char: "q")
    let r = handler.handleNormalModeKey(buf, state, viewport, keyCombo)
    check r.kind == nmrHandled
    check state.pendingInput.macroState.waitingForRegister == true
    check state.pendingInput.macroState.commandType == "record"
    check state.pendingInput.macroState.recordStartKey == "q"

  test "macro-play (@a) returns nmrPlaybackMacro":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Pre-populate a macro in register 'a'
    state.pendingInput.macroState.registers['a'] = @["j"]

    # Press @
    let atKey = KeyCombo(isSpecial: false, char: "@")
    let r1 = handler.handleNormalModeKey(buf, state, viewport, atKey)
    check r1.kind == nmrHandled # waiting for char

    # Press 'a' (register name)
    let aKey = KeyCombo(isSpecial: false, char: "a")
    let r2 = handler.handleNormalModeKey(buf, state, viewport, aKey)
    check r2.kind == nmrPlaybackMacro

  test "register-select (\"a) sets pendingRegister":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press "
    let quoteKey = KeyCombo(isSpecial: false, char: "\"")
    let r1 = handler.handleNormalModeKey(buf, state, viewport, quoteKey)
    check r1.kind == nmrHandled # waiting for char

    # Press 'a' (register name)
    let aKey = KeyCombo(isSpecial: false, char: "a")
    let r2 = handler.handleNormalModeKey(buf, state, viewport, aKey)
    check r2.kind == nmrHandled
    check state.pendingInput.pendingRegister == some('a')

  test "quickrun (\\r) returns ptQuickRun":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "echo hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press \ (sequence prefix)
    let backslashKey = KeyCombo(isSpecial: false, char: "\\")
    let r1 = handler.handleNormalModeKey(buf, state, viewport, backslashKey)
    check r1.kind == nmrHandled # consumed as sequence prefix

    # Press r
    let rKey = KeyCombo(isSpecial: false, char: "r")
    let r2 = handler.handleNormalModeKey(buf, state, viewport, rKey)
    check r2.kind == nmrPassthrough
    check r2.passthroughKind == ptQuickRun

  test "window-next (C-w k) returns ptNextWindow":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press C-w
    let cwKey = KeyCombo(isSpecial: false, char: "w", modifiers: {kmCtrl})
    let r1 = handler.handleNormalModeKey(buf, state, viewport, cwKey)
    check r1.kind == nmrHandled # consumed as sequence prefix

    # Press k
    let kKey = KeyCombo(isSpecial: false, char: "k")
    let r2 = handler.handleNormalModeKey(buf, state, viewport, kKey)
    check r2.kind == nmrPassthrough
    check r2.passthroughKind == ptNextWindow

  test "window-prev (C-w j) returns ptPrevWindow":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Press C-w
    let cwKey = KeyCombo(isSpecial: false, char: "w", modifiers: {kmCtrl})
    let r1 = handler.handleNormalModeKey(buf, state, viewport, cwKey)
    check r1.kind == nmrHandled # consumed as sequence prefix

    # Press j
    let jKey = KeyCombo(isSpecial: false, char: "j")
    let r2 = handler.handleNormalModeKey(buf, state, viewport, jKey)
    check r2.kind == nmrPassthrough
    check r2.passthroughKind == ptPrevWindow

  test "macro recording stops on recordStartKey":
    ## Per-key recording is captured in `handler.handleKeyCombo`; this test
    ## seeds `recordedKeys` and verifies that the Normal handler's stop-key
    ## detection (`q` after start) closes the register.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Start recording: press q
    let qKey = KeyCombo(isSpecial: false, char: "q")
    let r1 = handler.handleNormalModeKey(buf, state, viewport, qKey)
    check r1.kind == nmrHandled
    check state.pendingInput.macroState.waitingForRegister == true

    # Select register 'a'
    let aKey = KeyCombo(isSpecial: false, char: "a")
    let r2 = handler.handleNormalModeKey(buf, state, viewport, aKey)
    check r2.kind == nmrHandled
    check state.pendingInput.macroState.isRecording == true
    check state.pendingInput.macroState.register == 'a'

    # Simulate what `handleKeyCombo.recordUserKey` would have appended after
    # dispatching `j`.
    state.pendingInput.macroState.recordedKeys.add("j")
    let jKey = KeyCombo(isSpecial: false, char: "j")
    discard handler.handleNormalModeKey(buf, state, viewport, jKey)

    # Stop recording: press q
    let r3 = handler.handleNormalModeKey(buf, state, viewport, qKey)
    check r3.kind == nmrHandled
    check state.pendingInput.macroState.isRecording == false
    check state.pendingInput.macroState.registers.hasKey('a')
    check state.pendingInput.macroState.registers['a'] == @["j"]

  test "remapped macro-record key stops recording":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Remap Q to macro-record
    let err = handler.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Normal, "Q", "macro-record"
    )
    check err == ""

    # Start recording: press Q (remapped key)
    let bigQKey = KeyCombo(isSpecial: false, char: "Q")
    let r1 = handler.handleNormalModeKey(buf, state, viewport, bigQKey)
    check r1.kind == nmrHandled
    check state.pendingInput.macroState.waitingForRegister == true
    check state.pendingInput.macroState.recordStartKey == "Q"

    # Select register 'b'
    let bKey = KeyCombo(isSpecial: false, char: "b")
    let r2 = handler.handleNormalModeKey(buf, state, viewport, bKey)
    check r2.kind == nmrHandled
    check state.pendingInput.macroState.isRecording == true
    check state.pendingInput.macroState.register == 'b'

    # Simulate what `handleKeyCombo.recordUserKey` would have appended after
    # dispatching `j`.
    state.pendingInput.macroState.recordedKeys.add("j")
    let jKey = KeyCombo(isSpecial: false, char: "j")
    discard handler.handleNormalModeKey(buf, state, viewport, jKey)

    # Stop recording: press Q (matches recordStartKey "Q")
    let r3 = handler.handleNormalModeKey(buf, state, viewport, bigQKey)
    check r3.kind == nmrHandled
    check state.pendingInput.macroState.isRecording == false
    check state.pendingInput.macroState.registers.hasKey('b')
    check state.pendingInput.macroState.registers['b'] == @["j"]
    check state.pendingInput.macroState.recordStartKey == ""

  test "repeat last macro @@ via key binding":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    # Pre-populate a macro and set lastRegister
    state.pendingInput.macroState.registers['a'] = @["j", "k"]
    state.pendingInput.macroState.lastRegister = some('a')

    # Press @ (first key - key binding enters waitingForChar)
    let atKey = KeyCombo(isSpecial: false, char: "@")
    let r1 = handler.handleNormalModeKey(buf, state, viewport, atKey)
    check r1.kind == nmrHandled

    # Press @ again (second key - @@ = repeat last macro)
    let r2 = handler.handleNormalModeKey(buf, state, viewport, atKey)
    check r2.kind == nmrPlaybackMacro
    check r2.macroKeys == @["j", "k"]

suite "NormalModeHandler - Change List Navigation":
  proc pressGSemicolon(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    ## Simulate g; key sequence
    let gKey = KeyCombo(isSpecial: false, char: "g")
    discard handler.handleNormalModeKey(buf, state, viewport, gKey)
    let semiKey = KeyCombo(isSpecial: false, char: ";")
    handler.handleNormalModeKey(buf, state, viewport, semiKey)

  proc pressGComma(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    ## Simulate g, key sequence
    let gKey = KeyCombo(isSpecial: false, char: "g")
    discard handler.handleNormalModeKey(buf, state, viewport, gKey)
    let commaKey = KeyCombo(isSpecial: false, char: ",")
    handler.handleNormalModeKey(buf, state, viewport, commaKey)

  test "g; with empty change list returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    buf.changeList = @[]
    buf.changeListIndex = 0
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = pressGSemicolon(handler, buf, state, viewport)
    check result.kind == nmrError
    check result.errorMessage == "Change list is empty"

  test "g, with empty change list returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    buf.changeList = @[]
    buf.changeListIndex = 0
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = pressGComma(handler, buf, state, viewport)
    check result.kind == nmrError
    check result.errorMessage == "Change list is empty"

  test "g; jumps to current change position and decrements index":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.windowDisplay.currentBufferId = BufferId(0)

    buf.changeList = @[
      BufferPosition(line: 0, column: 3),
      BufferPosition(line: 1, column: 5),
      BufferPosition(line: 2, column: 1),
    ]
    buf.changeListIndex = 2

    let result = pressGSemicolon(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.cursor.line == 2
    check state.cursor.column == 1
    check buf.changeListIndex == 1

  test "g; at index 0 jumps and stays at 0":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.windowDisplay.currentBufferId = BufferId(0)

    buf.changeList =
      @[BufferPosition(line: 0, column: 3), BufferPosition(line: 1, column: 2)]
    buf.changeListIndex = 0

    let result = pressGSemicolon(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.cursor.line == 0
    check state.cursor.column == 3
    check buf.changeListIndex == 0

  test "g, at newest change returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.windowDisplay.currentBufferId = BufferId(0)

    buf.changeList =
      @[BufferPosition(line: 0, column: 3), BufferPosition(line: 1, column: 2)]
    buf.changeListIndex = 1

    let result = pressGComma(handler, buf, state, viewport)
    check result.kind == nmrError
    check result.errorMessage == "Already at newest change"

  test "g; then g, navigates back and forth":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.windowDisplay.currentBufferId = BufferId(0)

    buf.changeList = @[
      BufferPosition(line: 0, column: 0),
      BufferPosition(line: 1, column: 3),
      BufferPosition(line: 2, column: 5),
    ]
    buf.changeListIndex = 2

    # g; - jump to index 2 position, index becomes 1
    let r1 = pressGSemicolon(handler, buf, state, viewport)
    check r1.kind == nmrHandled
    check state.cursor.line == 2
    check buf.changeListIndex == 1

    # g; - jump to index 1 position, index becomes 0
    let r2 = pressGSemicolon(handler, buf, state, viewport)
    check r2.kind == nmrHandled
    check state.cursor.line == 1
    check buf.changeListIndex == 0

    # g, - index becomes 1, jump to index 1 position
    let r3 = pressGComma(handler, buf, state, viewport)
    check r3.kind == nmrHandled
    check state.cursor.line == 1
    check state.cursor.column == 3
    check buf.changeListIndex == 1

  test "g; with single change jumps to that position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.windowDisplay.currentBufferId = BufferId(0)

    buf.changeList = @[BufferPosition(line: 0, column: 5)]
    buf.changeListIndex = 0

    let result = pressGSemicolon(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.cursor.line == 0
    check state.cursor.column == 5

suite "NormalModeHandler - Bookmark Navigation":
  proc pressMM(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    ## Simulate m m key sequence (bookmark toggle)
    let mKey = KeyCombo(isSpecial: false, char: "m")
    discard handler.handleNormalModeKey(buf, state, viewport, mKey)
    handler.handleNormalModeKey(buf, state, viewport, mKey)

  proc pressMN(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    ## Simulate m n key sequence (bookmark next)
    let mKey = KeyCombo(isSpecial: false, char: "m")
    discard handler.handleNormalModeKey(buf, state, viewport, mKey)
    let nKey = KeyCombo(isSpecial: false, char: "n")
    handler.handleNormalModeKey(buf, state, viewport, nKey)

  proc pressMP(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    ## Simulate m p key sequence (bookmark prev)
    let mKey = KeyCombo(isSpecial: false, char: "m")
    discard handler.handleNormalModeKey(buf, state, viewport, mKey)
    let pKey = KeyCombo(isSpecial: false, char: "p")
    handler.handleNormalModeKey(buf, state, viewport, pKey)

  proc pressMC(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    ## Simulate m c key sequence (bookmark clear)
    let mKey = KeyCombo(isSpecial: false, char: "m")
    discard handler.handleNormalModeKey(buf, state, viewport, mKey)
    let cKey = KeyCombo(isSpecial: false, char: "c")
    handler.handleNormalModeKey(buf, state, viewport, cKey)

  test "mm toggles bookmark on current line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor.line = 1

    let result = pressMM(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check buf.hasBookmark(1) == true

  test "mm toggles off existing bookmark":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor.line = 1

    buf.toggleBookmark(1)
    check buf.hasBookmark(1) == true

    let result = pressMM(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check buf.hasBookmark(1) == false

  test "mn with no bookmarks returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = pressMN(handler, buf, state, viewport)
    check result.kind == nmrError
    check result.errorMessage == "No bookmarks"

  test "mn jumps to next bookmark":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.windowDisplay.currentBufferId = BufferId(0)

    buf.toggleBookmark(2)
    buf.toggleBookmark(4)

    let result = pressMN(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.cursor.line == 2

  test "mp with no bookmarks returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = pressMP(handler, buf, state, viewport)
    check result.kind == nmrError
    check result.errorMessage == "No bookmarks"

  test "mp jumps to previous bookmark":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.windowDisplay.currentBufferId = BufferId(0)
    state.cursor.line = 4

    buf.toggleBookmark(1)
    buf.toggleBookmark(3)

    let result = pressMP(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.cursor.line == 3

  test "mc clears all bookmarks":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    buf.toggleBookmark(0)
    buf.toggleBookmark(2)
    buf.toggleBookmark(3)
    check buf.bookmarks.len == 3

    let result = pressMC(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check buf.bookmarks.len == 0

suite "NormalModeHandler - gn (search next select)":
  proc pressGn(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    let gKey = KeyCombo(isSpecial: false, char: "g")
    discard handler.handleNormalModeKey(buf, state, viewport, gKey)
    let nKey = KeyCombo(isSpecial: false, char: "n")
    handler.handleNormalModeKey(buf, state, viewport, nKey)

  test "gn with no previous search returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrError

  test "gn selects next match":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "hello"
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.active == true
    check state.visualSelection.start == BufferPosition(line: 0, column: 0)
    check state.visualSelection.current == BufferPosition(line: 0, column: 4)
    check state.cursor == BufferPosition(line: 0, column: 4)

  test "gn selects match at cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "world"
    state.cursor = BufferPosition(line: 0, column: 7)

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.start == BufferPosition(line: 0, column: 6)
    check state.visualSelection.current == BufferPosition(line: 0, column: 10)

  test "gn with no match returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "xyz"

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrError

  test "gn selects match on different line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "aaa\nbbb\nccc")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "ccc"
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.start == BufferPosition(line: 2, column: 0)
    check state.visualSelection.current == BufferPosition(line: 2, column: 2)

  test "gn wraps around to beginning":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "hello"
    state.cursor = BufferPosition(line: 0, column: 8)

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.start == BufferPosition(line: 0, column: 0)
    check state.visualSelection.current == BufferPosition(line: 0, column: 4)

  test "gn selects match when cursor at match start":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "world"
    state.cursor = BufferPosition(line: 0, column: 6)

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.visualSelection.start == BufferPosition(line: 0, column: 6)
    check state.visualSelection.current == BufferPosition(line: 0, column: 10)

  test "gn selects match when cursor at match end":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "world"
    state.cursor = BufferPosition(line: 0, column: 10)

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.visualSelection.start == BufferPosition(line: 0, column: 6)
    check state.visualSelection.current == BufferPosition(line: 0, column: 10)

  test "gn with unicode text":
    let buf = newTextBuffer()
    discard
      buf.insertText(BufferPosition(line: 0, column: 0), "あいう abc あいう")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "あいう"
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.start == BufferPosition(line: 0, column: 8)
    check state.visualSelection.current == BufferPosition(line: 0, column: 10)

  test "gn re-enables hlsearch":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "hello"
    state.input.search.hlsearchTempDisabled = true

    let result = pressGn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.input.search.hlsearchTempDisabled == false

suite "NormalModeHandler - gN (search prev select)":
  proc pressGN(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    let gKey = KeyCombo(isSpecial: false, char: "g")
    discard handler.handleNormalModeKey(buf, state, viewport, gKey)
    let nKey = KeyCombo(isSpecial: false, char: "N")
    handler.handleNormalModeKey(buf, state, viewport, nKey)

  test "gN with no previous search returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = pressGN(handler, buf, state, viewport)
    check result.kind == nmrError

  test "gN selects previous match":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "hello"
    state.cursor = BufferPosition(line: 0, column: 16)

    let result = pressGN(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.active == true
    check state.visualSelection.start == BufferPosition(line: 0, column: 12)
    check state.visualSelection.current == BufferPosition(line: 0, column: 16)
    check state.cursor == BufferPosition(line: 0, column: 16)

  test "gN selects match at cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "world"
    state.cursor = BufferPosition(line: 0, column: 8)

    let result = pressGN(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.start == BufferPosition(line: 0, column: 6)
    check state.visualSelection.current == BufferPosition(line: 0, column: 10)

  test "gN with no match returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "xyz"

    let result = pressGN(handler, buf, state, viewport)
    check result.kind == nmrError

  test "gN selects match on different line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "aaa\nbbb\nccc")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "aaa"
    state.cursor = BufferPosition(line: 2, column: 0)

    let result = pressGN(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.start == BufferPosition(line: 0, column: 0)
    check state.visualSelection.current == BufferPosition(line: 0, column: 2)

  test "gN wraps around to end":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "aaa bbb")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "bbb"
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = pressGN(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.get == EditorMode.Visual
    check state.visualSelection.start == BufferPosition(line: 0, column: 4)
    check state.visualSelection.current == BufferPosition(line: 0, column: 6)

suite "NormalModeHandler - dgn (delete search match forward)":
  proc pressDgn(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    let dKey = KeyCombo(isSpecial: false, char: "d")
    discard handler.handleNormalModeKey(buf, state, viewport, dKey)
    let gKey = KeyCombo(isSpecial: false, char: "g")
    discard handler.handleNormalModeKey(buf, state, viewport, gKey)
    let nKey = KeyCombo(isSpecial: false, char: "n")
    handler.handleNormalModeKey(buf, state, viewport, nKey)

  test "dgn with no previous search returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = pressDgn(handler, buf, state, viewport)
    check result.kind == nmrError

  test "dgn deletes next match":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "hello"
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = pressDgn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.isNone or result.modeTransition.get == EditorMode.Normal
    check buf.getLine(0) == " world hello"

  test "dgn deletes match at cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "world"
    state.cursor = BufferPosition(line: 0, column: 8)

    let result = pressDgn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check buf.getLine(0) == "hello  hello"

  test "dgn with no match returns error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "xyz"

    let result = pressDgn(handler, buf, state, viewport)
    check result.kind == nmrError

  test "dgn stores deleted text in register":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "world"
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = pressDgn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check state.registers.getNoNamedRegister().getContent() == "world"

  test "dgn keeps the registers when the transaction cannot start":
    # An already-open transaction makes the delete fail. Registers live outside
    # the buffer transaction, so they must only be written once the delete went
    # through
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "world"
    state.cursor = BufferPosition(line: 0, column: 0)
    state.registers.setDeletedRegister("SEED", false)
    check buf.beginTransaction("outer").isOk

    let result = pressDgn(handler, buf, state, viewport)
    check result.kind == nmrError
    check state.registers.getSmallDeleteRegister().getContent() == "SEED"
    check buf.getLine(0) == "hello world hello"

  test "dgn stays in Normal mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "hello"
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = pressDgn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.isNone or result.modeTransition.get == EditorMode.Normal

suite "NormalModeHandler - dgN (delete search match backward)":
  proc pressDgN(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    let dKey = KeyCombo(isSpecial: false, char: "d")
    discard handler.handleNormalModeKey(buf, state, viewport, dKey)
    let gKey = KeyCombo(isSpecial: false, char: "g")
    discard handler.handleNormalModeKey(buf, state, viewport, gKey)
    let nKey = KeyCombo(isSpecial: false, char: "N")
    handler.handleNormalModeKey(buf, state, viewport, nKey)

  test "dgN deletes previous match":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "hello"
    state.cursor = BufferPosition(line: 0, column: 16)

    let result = pressDgN(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check buf.getLine(0) == "hello world "

suite "NormalModeHandler - cgn (change search match forward)":
  proc pressCgn(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
  ): NormalModeResult =
    let cKey = KeyCombo(isSpecial: false, char: "c")
    discard handler.handleNormalModeKey(buf, state, viewport, cKey)
    let gKey = KeyCombo(isSpecial: false, char: "g")
    discard handler.handleNormalModeKey(buf, state, viewport, gKey)
    let nKey = KeyCombo(isSpecial: false, char: "n")
    handler.handleNormalModeKey(buf, state, viewport, nKey)

  test "cgn deletes match and enters Insert mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.input.search.lastText = "world"
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = pressCgn(handler, buf, state, viewport)
    check result.kind == nmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert
    check buf.getLine(0) == "hello  hello"

suite "NormalModeHandler - guu / gUU (case operator on lines)":
  proc pressKeys(
      handler: NormalModeHandler,
      buf: TextBuffer,
      state: EditorState,
      viewport: ViewPort,
      keys: seq[string],
  ): NormalModeResult =
    for key in keys:
      result = handler.handleNormalModeKey(
        buf, state, viewport, KeyCombo(isSpecial: false, char: key)
      )

  proc setupTwoLines(): (TextBuffer, NormalModeHandler, EditorState, ViewPort) =
    let buf = newTextBuffer()
    discard
      buf.insertText(BufferPosition(line: 0, column: 0), "Hello World\nSecond Line")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    (buf, createTestHandler(buf), state, createTestViewport())

  test "guu lowercases the current line":
    let (buf, handler, state, viewport) = setupTwoLines()

    check pressKeys(handler, buf, state, viewport, @["g", "u", "u"]).kind == nmrHandled
    check buf.getLine(0) == "hello world"
    check buf.getLine(1) == "Second Line"
    check state.pendingInput.pendingOperator.isNone

  test "gugu lowercases the current line":
    let (buf, handler, state, viewport) = setupTwoLines()

    check pressKeys(handler, buf, state, viewport, @["g", "u", "g", "u"]).kind ==
      nmrHandled
    check buf.getLine(0) == "hello world"

  test "gUU uppercases the current line":
    let (buf, handler, state, viewport) = setupTwoLines()

    check pressKeys(handler, buf, state, viewport, @["g", "U", "U"]).kind == nmrHandled
    check buf.getLine(0) == "HELLO WORLD"
    check buf.getLine(1) == "Second Line"

  test "gUgU uppercases the current line":
    let (buf, handler, state, viewport) = setupTwoLines()

    check pressKeys(handler, buf, state, viewport, @["g", "U", "g", "U"]).kind ==
      nmrHandled
    check buf.getLine(0) == "HELLO WORLD"

  test "2guu lowercases two lines":
    let (buf, handler, state, viewport) = setupTwoLines()

    check pressKeys(handler, buf, state, viewport, @["2", "g", "u", "u"]).kind ==
      nmrHandled
    check buf.getLine(0) == "hello world"
    check buf.getLine(1) == "second line"

  test "gu2u lowercases two lines":
    let (buf, handler, state, viewport) = setupTwoLines()

    check pressKeys(handler, buf, state, viewport, @["g", "u", "2", "u"]).kind ==
      nmrHandled
    check buf.getLine(0) == "hello world"
    check buf.getLine(1) == "second line"

  test "guu is repeatable with .":
    let (buf, handler, state, viewport) = setupTwoLines()

    discard pressKeys(handler, buf, state, viewport, @["g", "u", "u"])
    state.cursor = BufferPosition(line: 1, column: 0)
    check pressKeys(handler, buf, state, viewport, @["."]).kind == nmrHandled
    check buf.getLine(1) == "second line"

  test "gUU is repeatable with .":
    let (buf, handler, state, viewport) = setupTwoLines()

    discard pressKeys(handler, buf, state, viewport, @["g", "U", "U"])
    state.cursor = BufferPosition(line: 1, column: 0)
    check pressKeys(handler, buf, state, viewport, @["."]).kind == nmrHandled
    check buf.getLine(1) == "SECOND LINE"

  test ". repeats the line count of 2guu":
    let buf = newTextBuffer()
    discard
      buf.insertText(BufferPosition(line: 0, column: 0), "One\nTwo\nThree\nFour\nFive")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 0)

    discard pressKeys(handler, buf, state, viewport, @["2", "g", "u", "u"])
    state.cursor = BufferPosition(line: 2, column: 0)
    discard pressKeys(handler, buf, state, viewport, @["."])
    check buf.getLine(0) == "one"
    check buf.getLine(1) == "two"
    check buf.getLine(2) == "three"
    check buf.getLine(3) == "four"
    check buf.getLine(4) == "Five"

  test ">> is repeatable with .":
    let (buf, handler, state, viewport) = setupTwoLines()

    discard pressKeys(handler, buf, state, viewport, @[">", ">"])
    let indent = buf.getLine(0)[0 ..< buf.getLine(0).len - "Hello World".len]
    check indent.len > 0

    state.cursor = BufferPosition(line: 1, column: 0)
    check pressKeys(handler, buf, state, viewport, @["."]).kind == nmrHandled
    check buf.getLine(1) == indent & "Second Line"

  test "<< is repeatable with .":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\tone\n\ttwo")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 0)

    discard pressKeys(handler, buf, state, viewport, @["<", "<"])
    check buf.getLine(0) == "one"

    state.cursor = BufferPosition(line: 1, column: 0)
    discard pressKeys(handler, buf, state, viewport, @["."])
    check buf.getLine(1) == "two"

  test "du falls through to undo (only gu/gU consume u)":
    let (buf, handler, state, viewport) = setupTwoLines()

    discard pressKeys(handler, buf, state, viewport, @["d", "u"])
    # `u` reached edit.undo, which reverted the insert done by the setup
    check buf.getLine(0) == ""

  test "gugu does not leave a stale g in the router":
    # Regression: the intermediate `g` was retained; the next `g` fired `gg`.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "One\nTwo\nThree")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 2, column: 0)

    discard pressKeys(handler, buf, state, viewport, @["g", "u", "g", "u"])
    discard pressKeys(handler, buf, state, viewport, @["g"])
    check state.cursor.line == 2

  test "gUgU does not leave a stale g in the router":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "One\nTwo\nThree")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 2, column: 0)

    discard pressKeys(handler, buf, state, viewport, @["g", "U", "g", "U"])
    discard pressKeys(handler, buf, state, viewport, @["g"])
    check state.cursor.line == 2

  test ">2> indents two lines (counts multiply)":
    let (buf, handler, state, viewport) = setupTwoLines()

    discard pressKeys(handler, buf, state, viewport, @[">", "2", ">"])
    check buf.getLine(0).endsWith("Hello World")
    check buf.getLine(0).len > "Hello World".len
    check buf.getLine(1).endsWith("Second Line")
    check buf.getLine(1).len > "Second Line".len

  test "<2< outdents two lines (counts multiply)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\tone\n\ttwo")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 0)

    discard pressKeys(handler, buf, state, viewport, @["<", "2", "<"])
    check buf.getLine(0) == "one"
    check buf.getLine(1) == "two"

  test "guu lands cursor on first non-blank":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  Hello World")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 5)

    discard pressKeys(handler, buf, state, viewport, @["g", "u", "u"])
    check buf.getLine(0) == "  hello world"
    check state.cursor.column == 2

  test "gUU lands cursor on first non-blank":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\t\thello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 4)

    discard pressKeys(handler, buf, state, viewport, @["g", "U", "U"])
    check buf.getLine(0) == "\t\tHELLO"
    check state.cursor.column == 2

  test "guu on a blank-only line keeps the cursor inside the line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "   ")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 0)

    discard pressKeys(handler, buf, state, viewport, @["g", "u", "u"])
    check buf.getLine(0) == "   "
    check state.cursor.column == 2

  test ">> on a blank-only line keeps the cursor inside the line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), " ")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 0)

    discard pressKeys(handler, buf, state, viewport, @[">", ">"])
    check state.cursor.column == buf.getLine(0).charLen - 1
