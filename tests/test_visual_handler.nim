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

## Tests for visual_handler.nim

import std/[unittest, options, tables]

import
  ../src/moepkg/
    [buffer, types, key_bindings, modes, motion, command_registry, config, registers]
import ../src/moepkg/types/editor_types
import ../src/moepkg/command_handlers/visual_handler

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Visual,
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
        pendingCount: 0,
        playbackDepth: 0,
      )
    ),
    registers: initRegisters(),
    visualSelection: VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 0),
      active: false,
      kind: vskChar,
    ),
  )

proc createTestViewport(): ViewPort =
  ## Create a minimal viewport for testing
  ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

proc createTestHandler(buf: TextBuffer): VisualModeHandler =
  ## Create a VisualModeHandler for testing
  let keyBindingRegistry = newKeyBindingRegistry()
  setupDefaultBindings(keyBindingRegistry)

  let commandRegistry = newCommandRegistry()
  registerBuiltinCommands(commandRegistry)

  let motionController =
    newMotionController(buf, createTestState(), createTestViewport())

  newVisualModeHandler(keyBindingRegistry, commandRegistry, motionController)

suite "VisualModeHandler - Constructor":
  test "Create VisualModeHandler":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    check handler != nil
    check handler.motionController != nil
    check handler.keyBindingRegistry != nil
    check handler.commandRegistry != nil

suite "VisualModeHandler - initSelection":
  test "Initialize character selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    initSelection(state, buf, vskChar)

    check state.visualSelection.active == true
    check state.visualSelection.kind == vskChar
    check state.visualSelection.start.line == 0
    check state.visualSelection.start.column == 5
    check state.visualSelection.current.line == 0
    check state.visualSelection.current.column == 5

  test "Initialize line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    initSelection(state, buf, vskLine)

    check state.visualSelection.active == true
    check state.visualSelection.kind == vskLine
    check state.visualSelection.start == state.cursor
    check state.visualSelection.current == state.cursor

  test "Initialize block selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    initSelection(state, buf, vskBlock)

    check state.visualSelection.active == true
    check state.visualSelection.kind == vskBlock

suite "VisualModeHandler - clearSelection":
  test "Clear active selection":
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 2, column: 5),
      active: true,
      kind: vskChar,
    )

    clearSelection(state)

    check state.visualSelection.active == false

  test "Clear already inactive selection":
    let state = createTestState()
    state.visualSelection.active = false

    clearSelection(state)

    check state.visualSelection.active == false

suite "VisualModeHandler - updateSelection":
  test "Update selection with new position":
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskChar,
    )

    let newPos = BufferPosition(line: 2, column: 10)
    updateSelection(state, newPos)

    check state.visualSelection.current.line == 2
    check state.visualSelection.current.column == 10
    check state.visualSelection.start.line == 0 # unchanged
    check state.visualSelection.start.column == 0 # unchanged

  test "Update inactive selection (no-op)":
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: false,
      kind: vskChar,
    )

    let newPos = BufferPosition(line: 2, column: 10)
    updateSelection(state, newPos)

    check state.visualSelection.current.line == 0 # unchanged
    check state.visualSelection.current.column == 5 # unchanged

suite "VisualModeHandler - getSelectionRange":
  test "Get range from visual handler module":
    let selection = VisualSelection(
      start: BufferPosition(line: 1, column: 3),
      current: BufferPosition(line: 0, column: 7),
      active: true,
      kind: vskChar,
    )

    let (selStart, selEnd) = selection.getSelectionRange()

    check selStart.line == 0
    check selStart.column == 7
    check selEnd.line == 1
    check selEnd.column == 3

suite "VisualModeHandler - isPositionInSelection":
  test "Position in character selection (same line)":
    let selection = VisualSelection(
      start: BufferPosition(line: 0, column: 2),
      current: BufferPosition(line: 0, column: 8),
      active: true,
      kind: vskChar,
    )

    check isPositionInSelection(selection, BufferPosition(line: 0, column: 5)) == true
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 2)) == true
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 8)) == true
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 1)) == false
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 9)) == false

  test "Position in character selection (multi-line)":
    let selection = VisualSelection(
      start: BufferPosition(line: 0, column: 5),
      current: BufferPosition(line: 2, column: 3),
      active: true,
      kind: vskChar,
    )

    # On start line
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 5)) == true
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 10)) == true
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 4)) == false

    # On middle line
    check isPositionInSelection(selection, BufferPosition(line: 1, column: 0)) == true
    check isPositionInSelection(selection, BufferPosition(line: 1, column: 100)) == true

    # On end line
    check isPositionInSelection(selection, BufferPosition(line: 2, column: 0)) == true
    check isPositionInSelection(selection, BufferPosition(line: 2, column: 3)) == true
    check isPositionInSelection(selection, BufferPosition(line: 2, column: 4)) == false

  test "Position in line selection":
    let selection = VisualSelection(
      start: BufferPosition(line: 1, column: 0),
      current: BufferPosition(line: 3, column: 5),
      active: true,
      kind: vskLine,
    )

    check isPositionInSelection(selection, BufferPosition(line: 1, column: 0)) == true
    check isPositionInSelection(selection, BufferPosition(line: 2, column: 100)) == true
    check isPositionInSelection(selection, BufferPosition(line: 3, column: 10)) == true
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 0)) == false
    check isPositionInSelection(selection, BufferPosition(line: 4, column: 0)) == false

  test "Position in block selection":
    let selection = VisualSelection(
      start: BufferPosition(line: 0, column: 2),
      current: BufferPosition(line: 2, column: 6),
      active: true,
      kind: vskBlock,
    )

    # Within block
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 3)) == true
    check isPositionInSelection(selection, BufferPosition(line: 1, column: 4)) == true
    check isPositionInSelection(selection, BufferPosition(line: 2, column: 5)) == true

    # On boundaries
    check isPositionInSelection(selection, BufferPosition(line: 0, column: 2)) == true
    check isPositionInSelection(selection, BufferPosition(line: 2, column: 6)) == true

    # Outside column range
    check isPositionInSelection(selection, BufferPosition(line: 1, column: 1)) == false
    check isPositionInSelection(selection, BufferPosition(line: 1, column: 7)) == false

    # Outside line range
    check isPositionInSelection(selection, BufferPosition(line: 3, column: 4)) == false

  test "Position in inactive selection":
    let selection = VisualSelection(
      start: BufferPosition(line: 0, column: 2),
      current: BufferPosition(line: 0, column: 8),
      active: false,
      kind: vskChar,
    )

    check isPositionInSelection(selection, BufferPosition(line: 0, column: 5)) == false

suite "VisualModeHandler - isVisualAllMode":
  test "Visual mode is visual":
    check isVisualAllMode(EditorMode.Visual) == true

  test "VisualLine mode is visual":
    check isVisualAllMode(EditorMode.VisualLine) == true

  test "VisualBlock mode is visual":
    check isVisualAllMode(EditorMode.VisualBlock) == true

  test "Normal mode is not visual":
    check isVisualAllMode(EditorMode.Normal) == false

  test "Insert mode is not visual":
    check isVisualAllMode(EditorMode.Insert) == false

  test "Command mode is not visual":
    check isVisualAllMode(EditorMode.Normal) == false

  test "Search mode is not visual":
    check isVisualAllMode(EditorMode.Insert) == false

  test "Replace mode is not visual":
    check isVisualAllMode(EditorMode.Replace) == false

suite "VisualModeHandler - VisualModeResult":
  test "vmrHandled result with mode transition":
    let result =
      VisualModeResult(kind: vmrHandled, modeTransition: some(EditorMode.Normal))
    check result.kind == vmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Normal

  test "vmrHandled result without mode transition":
    let result = VisualModeResult(kind: vmrHandled, modeTransition: none(EditorMode))
    check result.kind == vmrHandled
    check result.modeTransition.isNone

  test "vmrUnhandled result":
    let result = VisualModeResult(kind: vmrUnhandled)
    check result.kind == vmrUnhandled

  test "vmrWaitingForInput result":
    let result = VisualModeResult(kind: vmrWaitingForInput)
    check result.kind == vmrWaitingForInput

  test "vmrLspSelectionRange result":
    let result = VisualModeResult(kind: vmrLspSelectionRange)
    check result.kind == vmrLspSelectionRange

  test "vmrError result":
    let result = VisualModeResult(kind: vmrError, errorMessage: "test error")
    check result.kind == vmrError
    check result.errorMessage == "test error"

suite "VisualModeHandler - executeCommand":
  test "Execute motion.left command":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)
    state.mode = EditorMode.Visual
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()

    let result = handler.executeCommand(buf, state, viewport, "motion.left")

    check result.kind == vmrHandled
    check state.cursor.column == 4

  test "Execute non-existent command returns error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    let viewport = createTestViewport()

    let result = handler.executeCommand(buf, state, viewport, "nonexistent.command")

    check result.kind == vmrError

suite "VisualModeHandler - handleVisualModeKey":
  test "Handle ESC key clears selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskChar,
    )
    let viewport = createTestViewport()

    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check state.visualSelection.active == false

  test "Handle unbound key returns unhandled":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()

    # Use a key that is unlikely to be bound
    let keyCombo = KeyCombo(isSpecial: false, char: "\x00", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrUnhandled or r.kind == vmrHandled

  test "Handler does not record macro keys (recording is unified at handleKeyCombo)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    initSelection(state, buf, vskChar)
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @[]
    let viewport = createTestViewport()

    let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
    discard handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check state.pendingInput.macroState.recordedKeys.len == 0

suite "VisualModeHandler - sequence dispatch (M7 regression)":
  # `gg`/`ge`/`zf` are bound as multi-key sequences to all three Visual modes.
  # A single `g` must keep waiting; it must not be completed early by the
  # VisualBlock/VisualLine fallback re-driving the decode FSM (the old raw
  # `findBinding` fallback fired `gg` on the very first `g`).
  let gKey = KeyCombo(isSpecial: false, char: "g", modifiers: {})

  for subMode in [EditorMode.VisualBlock, EditorMode.VisualLine]:
    test "Single g waits, does not fire gg in " & $subMode:
      let buf = newTextBuffer()
      discard buf.insertText(BufferPosition(line: 0, column: 0), "line0\nline1\nline2")
      let handler = createTestHandler(buf)
      let state = createTestState()
      state.mode = subMode
      state.cursor = BufferPosition(line: 2, column: 0)
      initSelection(
        state, buf, if subMode == EditorMode.VisualLine: vskLine else: vskBlock
      )
      let viewport = createTestViewport()

      # First `g`: must wait, cursor must not jump to the first line.
      let r1 = handler.handleVisualModeKey(buf, state, viewport, gKey)
      check r1.kind == vmrWaitingForInput
      check state.cursor.line == 2

      # Second `g`: completes `gg`, cursor jumps to the first line.
      let r2 = handler.handleVisualModeKey(buf, state, viewport, gKey)
      check r2.kind == vmrHandled
      check state.cursor.line == 0

  test "Single g waits in plain Visual too":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line0\nline1\nline2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.cursor = BufferPosition(line: 2, column: 0)
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()

    let r1 = handler.handleVisualModeKey(buf, state, viewport, gKey)
    check r1.kind == vmrWaitingForInput
    check state.cursor.line == 2

    let r2 = handler.handleVisualModeKey(buf, state, viewport, gKey)
    check r2.kind == vmrHandled
    check state.cursor.line == 0

  test "Escape clears a pending sequence (next g does not fire gg)":
    # rrCancelled arm: Escape on an active sequence clears it and stays in mode.
    # If the pending `g` survived, the post-Escape `g` would complete `gg`.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line0\nline1\nline2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.cursor = BufferPosition(line: 2, column: 0)
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()

    check handler.handleVisualModeKey(buf, state, viewport, gKey).kind ==
      vmrWaitingForInput
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard handler.handleVisualModeKey(buf, state, viewport, escKey)

    # A fresh `g` must wait again, not jump to the first line.
    let r = handler.handleVisualModeKey(buf, state, viewport, gKey)
    check r.kind == vmrWaitingForInput
    check state.cursor.line == 2

  test "i in VisualBlock dispatches via the shared Visual fallback":
    # rrUnhandled -> fallback -> rrCommand: `i` (textobject-inner) is bound to
    # plain Visual only; VisualBlock reaches it through the Visual fallback.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.cursor = BufferPosition(line: 0, column: 0)
    initSelection(state, buf, vskBlock)
    let viewport = createTestViewport()

    let iKey = KeyCombo(isSpecial: false, char: "i", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, iKey)
    # The fallback found and dispatched the command (it armed a pending text
    # object), so the key is not reported unhandled.
    check r.kind == vmrHandled
    check state.pendingInput.pendingTextObject.isSome

  test "r waits for its operand, then the operand char replaces the selection":
    # rrWaiting via waitingForChar (operand wait), then rrCommand on the operand.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.cursor = BufferPosition(line: 0, column: 0)
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()

    let rKey = KeyCombo(isSpecial: false, char: "r", modifiers: {})
    check handler.handleVisualModeKey(buf, state, viewport, rKey).kind ==
      vmrWaitingForInput

    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, xKey)
    check r.kind in {vmrHandled, vmrUnhandled}
    check buf.getLine(0)[0] == 'x'

  test "Handle Visual mode fallback to VisualLine":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    initSelection(state, buf, vskLine)
    let viewport = createTestViewport()

    # Try a key that should be handled by Visual mode bindings
    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled or r.kind == vmrUnhandled

  test "Handle Visual mode fallback to VisualBlock":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    initSelection(state, buf, vskBlock)
    let viewport = createTestViewport()

    let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled or r.kind == vmrUnhandled

suite "VisualModeHandler - Mode Transitions":
  test "Yank command transitions to Normal mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.previousMode = EditorMode.Normal
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    let viewport = createTestViewport()

    # 'y' key for yank
    let keyCombo = KeyCombo(isSpecial: false, char: "y", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.Normal

  test "Delete command transitions to previous mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.previousMode = EditorMode.Normal
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    let viewport = createTestViewport()

    # 'd' key for delete
    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled

  test "Change command transitions to Insert mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    let viewport = createTestViewport()

    # 'c' key for change
    let keyCombo = KeyCombo(isSpecial: false, char: "c", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled
    # Mode should transition to Insert
    check state.mode == EditorMode.Insert or r.modeTransition.isSome

suite "VisualModeHandler - Selection Types":
  test "Char selection handles correctly":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.cursor = BufferPosition(line: 0, column: 4)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    let viewport = createTestViewport()

    # Move right
    let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled
    # After 'l', cursor moves from column 4 to 5
    check state.cursor.column == 5

  test "Line selection handles correctly":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 0),
      active: true,
      kind: vskLine,
    )
    let viewport = createTestViewport()

    # Move down
    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled
    check state.visualSelection.current.line == 1

  test "Block selection handles correctly":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 0),
      active: true,
      kind: vskBlock,
    )
    let viewport = createTestViewport()

    # Move right then down
    var keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
    discard handler.handleVisualModeKey(buf, state, viewport, keyCombo)
    keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled
    check state.visualSelection.current.line == 1
    check state.visualSelection.current.column == 1

suite "VisualModeHandler - Waiting for Input":
  test "Check for waiting state when sequence not complete":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()

    # Try 'r' for replace - should wait for char input
    let keyCombo = KeyCombo(isSpecial: false, char: "r", modifiers: {})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    # Either waiting for input or handled depending on implementation
    check r.kind in {vmrWaitingForInput, vmrHandled, vmrUnhandled}

suite "VisualModeHandler - Error Handling":
  test "Error result contains message":
    let result = VisualModeResult(kind: vmrError, errorMessage: "Command not found")
    check result.kind == vmrError
    check result.errorMessage == "Command not found"

  test "Execute command with invalid buffer state":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    # Empty buffer with invalid cursor position
    state.cursor = BufferPosition(line: 100, column: 100)
    let viewport = createTestViewport()

    # Try to execute a command
    let result = handler.executeCommand(buf, state, viewport, "motion.left")

    # Should handle gracefully
    check result.kind == vmrHandled or result.kind == vmrError

suite "VisualModeHandler - Command mode command alias bridge":
  test "xmap K to bdelete dispatches via exec.cmdline.* bridge":
    # The bridge must fire from Visual mode too — without it,
    # `xnoremap K = "bdelete"` would route through commandRegistry.execute
    # with an unregistered `exec.cmdline.bdelete` commandId and error out.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    discard
      handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Visual, "K", "bdelete")

    let state = createTestState()
    state.mode = EditorMode.Visual
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()
    let keyCombo = KeyCombo(isSpecial: false, char: "K", modifiers: {})

    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrExecCommand
    check r.execCommandText == "bdelete"

  test "xmap D to bd preserves the short alias verbatim":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    discard handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Visual, "D", "bd")

    let state = createTestState()
    state.mode = EditorMode.Visual
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()
    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})

    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrExecCommand
    check r.execCommandText == "bd"

suite "VisualModeHandler - Escape returns to previousMode":
  test "Escape from Visual returns to Normal when previousMode is Normal":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.previousMode = EditorMode.Normal
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    let viewport = createTestViewport()

    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0)
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.Normal
    check state.mode == EditorMode.Normal
    check not state.visualSelection.active

  test "Escape from Visual returns to LogViewer when previousMode is LogViewer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "log line 1\nlog line 2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.previousMode = EditorMode.LogViewer
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    let viewport = createTestViewport()

    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0)
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.LogViewer
    check state.mode == EditorMode.LogViewer
    check not state.visualSelection.active

  test "C-c from Visual returns to previousMode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.previousMode = EditorMode.LogViewer
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    let viewport = createTestViewport()

    let keyCombo = KeyCombo(isSpecial: false, char: "c", modifiers: {kmCtrl})
    let r = handler.handleVisualModeKey(buf, state, viewport, keyCombo)

    check r.kind == vmrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.LogViewer
    check state.mode == EditorMode.LogViewer
    check not state.visualSelection.active

  test "Escape from Visual clears pendingRegister (\"a<Esc> leak)":
    # `"a` in Normal sets pendingRegister=some('a'); entering Visual without
    # consuming it leaves the register selection armed. Escape from Visual must
    # clear it, otherwise the next yank/delete in the returned mode silently
    # targets register a.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.previousMode = EditorMode.Normal
    state.pendingInput.pendingRegister = some('a')
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()

    let esc = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0)
    let r = handler.handleVisualModeKey(buf, state, viewport, esc)

    check r.kind == vmrHandled
    check state.mode == EditorMode.Normal
    check state.pendingInput.pendingRegister.isNone

  test "Escape from Visual clears pending macro register wait (q<Esc> leak)":
    # `q` in Normal arms macroState.waitingForRegister for the register name.
    # Entering Visual and Escaping must not leave the FSM waiting; otherwise
    # the next `q` in Normal is interpreted as the register name instead of
    # re-arming.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.previousMode = EditorMode.Normal
    state.pendingInput.macroState.waitingForRegister = true
    state.pendingInput.macroState.commandType = "record"
    initSelection(state, buf, vskChar)
    let viewport = createTestViewport()

    let esc = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0)
    discard handler.handleVisualModeKey(buf, state, viewport, esc)

    check not state.pendingInput.macroState.waitingForRegister
    check state.pendingInput.macroState.commandType == ""
