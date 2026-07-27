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

## Tests for replace_handler.nim

import std/[unittest, options, tables]

import
  ../src/moepkg/
    [buffer, types, key_bindings, modes, motion, command_registry, registers, config]
import ../src/moepkg/types/editor_types
import ../src/moepkg/command_handlers/replace_handler

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Replace,
    previousMode: EditorMode.Normal,
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
  )
  EditorState(
    activeWindow: window,
    display:
      DisplaySettings(showLineCount: true, showLinePercentage: true, showEncoding: true),
    config: newEditorConfig(),
    editState: EditState(replaceHistory: @[]),
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
  )

proc createTestViewport(): ViewPort =
  ## Create a minimal viewport for testing
  ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

proc createTestHandler(buf: TextBuffer): ReplaceModeHandler =
  ## Create a ReplaceModeHandler for testing
  let keyBindingRegistry = newKeyBindingRegistry()
  setupDefaultBindings(keyBindingRegistry)

  let commandRegistry = newCommandRegistry()
  registerBuiltinCommands(commandRegistry)

  let motionController =
    newMotionController(buf, createTestState(), createTestViewport())

  newReplaceModeHandler(keyBindingRegistry, motionController, commandRegistry)

suite "ReplaceModeHandler - Constructor":
  test "Create ReplaceModeHandler":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    check handler != nil
    check handler.motionController != nil
    check handler.keyBindingRegistry != nil
    check handler.commandRegistry != nil

suite "ReplaceModeHandler - Character Replacement":
  test "Replace single character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleCharacterReplacement(buf, state, "x")

    check result.kind == rmrHandled
    check result.modeTransition.isNone
    check buf.getLine(0) == "xello"
    check state.cursor.column == 1
    check state.editState.replaceHistory.len == 1
    check state.editState.replaceHistory[0].originalChar == "h"

  test "Replace character in middle of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    let result = handler.handleCharacterReplacement(buf, state, "X")

    check result.kind == rmrHandled
    check buf.getLine(0) == "heXlo"
    check state.cursor.column == 3
    check state.editState.replaceHistory[0].originalChar == "l"

  test "Insert at end of line (append)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleCharacterReplacement(buf, state, "!")

    check result.kind == rmrHandled
    check buf.getLine(0) == "hello!"
    check state.cursor.column == 6
    check state.editState.replaceHistory[0].originalChar == ""

  test "Replace with multibyte character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleCharacterReplacement(buf, state, "あ")

    check result.kind == rmrHandled
    check buf.getLine(0) == "あello"
    check state.cursor.column == 1

  test "Replace multibyte character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "あいう")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 1)

    let result = handler.handleCharacterReplacement(buf, state, "x")

    check result.kind == rmrHandled
    check buf.getLine(0) == "あxう"
    check state.cursor.column == 2
    check state.editState.replaceHistory[0].originalChar == "い"

suite "ReplaceModeHandler - Backspace":
  test "Backspace restores original character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "xello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 1)
    state.editState.replaceHistory.add(
      ReplaceHistoryEntry(pos: BufferPosition(line: 0, column: 0), originalChar: "h")
    )

    let result = handler.handleBackspace(buf, state)

    check result.kind == rmrHandled
    check buf.getLine(0) == "hello"
    check state.cursor.column == 0
    check state.editState.replaceHistory.len == 0

  test "Backspace with no history moves cursor back":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let result = handler.handleBackspace(buf, state)

    check result.kind == rmrHandled
    check buf.getLine(0) == "hello"
    check state.cursor.column == 2

  test "Backspace at start of line with no history":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "first")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nsecond")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let result = handler.handleBackspace(buf, state)

    check result.kind == rmrHandled
    check state.cursor.line == 0
    check state.cursor.column == 5

  test "Backspace at very beginning does nothing":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleBackspace(buf, state)

    check result.kind == rmrHandled
    check state.cursor.line == 0
    check state.cursor.column == 0

  test "Backspace deletes inserted character (at end of line)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello!")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    state.editState.replaceHistory.add(
      ReplaceHistoryEntry(pos: BufferPosition(line: 0, column: 5), originalChar: "")
    )

    let result = handler.handleBackspace(buf, state)

    check result.kind == rmrHandled
    check buf.getLine(0) == "hello"
    check state.cursor.column == 5

suite "ReplaceModeHandler - Newline":
  test "Insert newline":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleNewline(buf, state)

    check result.kind == rmrHandled
    check state.cursor.line == 1
    check state.cursor.column == 0
    check buf.len == 2

  test "Insert newline at end of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleNewline(buf, state)

    check result.kind == rmrHandled
    check state.cursor.line == 1
    check state.cursor.column == 0

suite "ReplaceModeHandler - Motion":
  test "Handle left motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let result = handler.handleMotion(buf, state, Motion.Left)

    check result.kind == rmrHandled
    check state.cursor.column == 2

  test "Handle right motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleMotion(buf, state, Motion.Right)

    check result.kind == rmrHandled
    check state.cursor.column == 1

  test "Handle up motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nline2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let result = handler.handleMotion(buf, state, Motion.Up)

    check result.kind == rmrHandled
    check state.cursor.line == 0

  test "Handle down motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nline2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleMotion(buf, state, Motion.Down)

    check result.kind == rmrHandled
    check state.cursor.line == 1

suite "ReplaceModeHandler - Mode Switch":
  test "Switch to Normal mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    let result = handler.handleModeSwitch(EditorMode.Normal)

    check result.kind == rmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Normal

  test "Switch to Insert mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    let result = handler.handleModeSwitch(EditorMode.Insert)

    check result.kind == rmrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Insert

suite "ReplaceModeHandler - Result Helpers":
  test "isHandled returns true for handled results":
    let result = ReplaceModeResult(kind: rmrHandled, modeTransition: none(EditorMode))
    check result.isHandled == true

  test "isHandled returns false for error results":
    let result = ReplaceModeResult(kind: rmrError, errorMessage: "test error")
    check result.isHandled == false

  test "isHandled returns false for unhandled results":
    let result = ReplaceModeResult(kind: rmrUnhandled)
    check result.isHandled == false

  test "hasError returns true for error results":
    let result = ReplaceModeResult(kind: rmrError, errorMessage: "test error")
    check result.hasError == true

  test "hasError returns false for handled results":
    let result = ReplaceModeResult(kind: rmrHandled, modeTransition: none(EditorMode))
    check result.hasError == false

  test "getModeTransition returns mode for handled with transition":
    let result =
      ReplaceModeResult(kind: rmrHandled, modeTransition: some(EditorMode.Normal))
    let transition = result.getModeTransition
    check transition.isSome
    check transition.get == EditorMode.Normal

  test "getModeTransition returns none for handled without transition":
    let result = ReplaceModeResult(kind: rmrHandled, modeTransition: none(EditorMode))
    let transition = result.getModeTransition
    check transition.isNone

  test "getModeTransition returns none for error results":
    let result = ReplaceModeResult(kind: rmrError, errorMessage: "error")
    let transition = result.getModeTransition
    check transition.isNone

suite "ReplaceModeHandler - Key Handling":
  test "Handle Escape key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.Normal

  test "Handle Backspace key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "xello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 1)
    state.editState.replaceHistory.add(
      ReplaceHistoryEntry(pos: BufferPosition(line: 0, column: 0), originalChar: "h")
    )

    let keyCombo =
      KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check buf.getLine(0) == "hello"

  test "Handle Enter key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check state.cursor.line == 1

  test "Handle Left arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check state.cursor.column == 2

  test "Handle Right arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check state.cursor.column == 1

  test "Handle Up arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nline2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check state.cursor.line == 0

  test "Handle Down arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nline2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check state.cursor.line == 1

  test "Handle Home key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: true, special: skHome, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check state.cursor.column == 0

  test "Handle End key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skEnd, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    # In Replace mode End lands at end of line (one past the last character)
    check state.cursor.column == 5

  test "Handle regular character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check buf.getLine(0) == "xello"

  test "Handle PageUp key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    for i in 1 .. 30:
      discard buf.insertText(BufferPosition(line: i - 1, column: 5), "\nline" & $i)
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 20, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check state.cursor.line < 20

  test "Handle PageDown key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    for i in 1 .. 30:
      discard buf.insertText(BufferPosition(line: i - 1, column: 5), "\nline" & $i)
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 5, column: 0)

    let keyCombo =
      KeyCombo(isSpecial: true, special: skPageDown, fnNum: 0, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check state.cursor.line > 5

suite "ReplaceModeHandler - Unhandled Keys":
  test "Unknown special key returns unhandled":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Function key (F1) - not typically handled in replace mode
    let keyCombo =
      KeyCombo(isSpecial: true, special: skFunction, fnNum: 1, modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrUnhandled

  test "Character with modifier returns unhandled":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Ctrl+X - not a standard binding in replace mode
    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {kmCtrl})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrUnhandled

suite "ReplaceModeHandler - Macro Recording":
  test "Handler does not record macro keys (recording is unified at handleKeyCombo)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.pendingInput.macroState.isRecording = true
    state.pendingInput.macroState.register = 'a'
    state.pendingInput.macroState.recordedKeys = @[]
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard handler.handleReplaceModeKey(buf, state, keyCombo)

    check state.pendingInput.macroState.recordedKeys.len == 0

suite "ReplaceModeHandler - Key Binding Motions":
  test "Handle h key replaces character (not motion in Replace mode)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: false, char: "h", modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    # In Replace mode, h replaces the character (not motion like Normal mode)
    check r.kind == rmrHandled
    check buf.getLine(0) == "helho"
    check state.cursor.column == 4

  test "Handle j key replaces character (not motion in Replace mode)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check buf.getLine(0) == "jine1"

  test "Handle k key replaces character (not motion in Replace mode)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check buf.getLine(0) == "kine1"

  test "Handle l key replaces character (not motion in Replace mode)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
    let r = handler.handleReplaceModeKey(buf, state, keyCombo)

    check r.kind == rmrHandled
    check buf.getLine(0) == "lello"

suite "ReplaceModeHandler - Empty Buffer":
  test "Replace in empty buffer inserts character":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleCharacterReplacement(buf, state, "x")

    check result.kind == rmrHandled
    check buf.getLine(0) == "x"
    check state.cursor.column == 1

  test "Backspace in empty buffer at start":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleBackspace(buf, state)

    check result.kind == rmrHandled
    check state.cursor.column == 0
    check state.cursor.line == 0

suite "ReplaceModeHandler - Newline Edge Cases":
  test "Newline in middle of line splits correctly":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "helloworld")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleNewline(buf, state)

    check result.kind == rmrHandled
    check buf.getLine(0) == "hello"
    check buf.getLine(1) == "world"
    check state.cursor.line == 1
    check state.cursor.column == 0

  test "Newline at start of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleNewline(buf, state)

    check result.kind == rmrHandled
    check buf.getLine(0) == ""
    check buf.getLine(1) == "hello"

suite "ReplaceModeHandler - Unicode Edge Cases":
  test "Replace in middle of unicode string":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "日本語テスト")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    let result = handler.handleCharacterReplacement(buf, state, "X")

    check result.kind == rmrHandled
    check buf.getLine(0) == "日本Xテスト"
    check state.editState.replaceHistory[0].originalChar == "語"

  test "Replace with emoji":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleCharacterReplacement(buf, state, "😀")

    check result.kind == rmrHandled
    check buf.getLine(0) == "😀ello"

  test "Backspace restores unicode character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "日X語")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)
    state.editState.replaceHistory.add(
      ReplaceHistoryEntry(pos: BufferPosition(line: 0, column: 1), originalChar: "本")
    )

    let result = handler.handleBackspace(buf, state)

    check result.kind == rmrHandled
    check buf.getLine(0) == "日本語"

suite "ReplaceModeHandler - Multiple Replacements":
  test "Replace multiple characters sequentially":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    discard handler.handleCharacterReplacement(buf, state, "a")
    discard handler.handleCharacterReplacement(buf, state, "b")
    discard handler.handleCharacterReplacement(buf, state, "c")

    check buf.getLine(0) == "abclo"
    check state.cursor.column == 3
    check state.editState.replaceHistory.len == 3
    check state.editState.replaceHistory[0].originalChar == "h"
    check state.editState.replaceHistory[1].originalChar == "e"
    check state.editState.replaceHistory[2].originalChar == "l"

  test "Undo multiple replacements with backspace":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    # Replace 3 characters
    discard handler.handleCharacterReplacement(buf, state, "a")
    discard handler.handleCharacterReplacement(buf, state, "b")
    discard handler.handleCharacterReplacement(buf, state, "c")

    check buf.getLine(0) == "abclo"

    # Undo with backspace
    discard handler.handleBackspace(buf, state)
    check buf.getLine(0) == "abllo"

    discard handler.handleBackspace(buf, state)
    check buf.getLine(0) == "aello"

    discard handler.handleBackspace(buf, state)
    check buf.getLine(0) == "hello"

    check state.editState.replaceHistory.len == 0
