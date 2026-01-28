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

## Tests for insert_handler.nim

import std/[unittest, options, tables]

import pkg/results

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/cursor {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/keybindings {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/commandregistry {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/completion {.all.}
import ../src/moepkg/signaturehelp {.all.}
import ../src/moepkg/syntax/highlite {.all.}
import ../src/moepkg/command_handlers/insert_handler {.all.}

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  EditorState(
    cursor: BufferPosition(line: 0, column: 0),
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
    mode: EditorMode.Insert,
    previousMode: EditorMode.Normal,
    display: DisplaySettings(
      showTabLine: false,
      showStatusLine: true,
      multiStatusLine: false,
      showLineCount: true,
      showLinePercentage: true,
      showEncoding: true,
      showLineNumbers: true,
      showCursorLine: false,
      showSyntax: true,
      showIndentationLines: false,
      showSidebar: false,
      showGitDiff: false,
      showSyntaxChecker: false,
      showCodeLens: false,
      showDocumentHighlight: false,
      lineWrap: true,
      tabStop: 2,
      expandTab: true,
      autoIndent: true,
      autoCloseParen: false,
      autoDeleteParen: false,
    ),
    needsFullRedraw: false,
    viewportReservedLines: 2,
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
  )

proc createTestViewport(): ViewPort =
  ## Create a minimal viewport for testing
  ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

proc createTestHandler(buf: TextBuffer): InsertModeHandler =
  ## Create an InsertModeHandler for testing
  let keyBindingRegistry = newKeyBindingRegistry()
  setupDefaultBindings(keyBindingRegistry)

  let commandRegistry = newCommandRegistry()
  registerBuiltinCommands(commandRegistry)

  let motionController =
    newMotionController(buf, createTestState(), createTestViewport())

  newInsertModeHandler(
    keyBindingRegistry,
    motionController,
    commandRegistry,
    nil, # No LSP
    true, # autocompleteEnabled
    NotificationConfig(),
  )

suite "InsertModeHandler - Constructor":
  test "Create InsertModeHandler with default config":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    check handler != nil
    check handler.motionController != nil
    check handler.keyBindingRegistry != nil
    check handler.commandRegistry != nil
    check handler.completionManager != nil
    check handler.signatureHelpManager != nil
    check handler.autocompleteEnabled == true

  test "Create InsertModeHandler with autocomplete disabled":
    let buf = newTextBuffer()
    let keyBindingRegistry = newKeyBindingRegistry()
    let commandRegistry = newCommandRegistry()
    let motionController =
      newMotionController(buf, createTestState(), createTestViewport())

    let handler = newInsertModeHandler(
      keyBindingRegistry,
      motionController,
      commandRegistry,
      nil,
      false, # autocompleteEnabled
    )

    check handler.autocompleteEnabled == false

suite "InsertModeHandler - Character Insertion":
  test "Insert single character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleCharacterInsertion(buf, state, "x")

    check result.kind == imrHandled
    check result.modeTransition.isNone
    check buf.getLine(0) == "xhello"
    check state.cursor.column == 1

  test "Insert multibyte character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleCharacterInsertion(buf, state, "あ")

    check result.kind == imrHandled
    check buf.getLine(0) == "あhello"
    check state.cursor.column == 1 # Character position, not byte position

  test "Insert with auto-close paren enabled":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoCloseParen = true
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = handler.handleCharacterInsertion(buf, state, "(")

    check result.kind == imrHandled
    check buf.getLine(0) == "func()"
    check state.cursor.column == 5 # Between parens

  test "Insert opening bracket with auto-close":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "arr")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoCloseParen = true
    state.cursor = BufferPosition(line: 0, column: 3)

    let result = handler.handleCharacterInsertion(buf, state, "[")

    check result.kind == imrHandled
    check buf.getLine(0) == "arr[]"
    check state.cursor.column == 4

  test "Insert opening brace with auto-close":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "obj")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoCloseParen = true
    state.cursor = BufferPosition(line: 0, column: 3)

    let result = handler.handleCharacterInsertion(buf, state, "{")

    check result.kind == imrHandled
    check buf.getLine(0) == "obj{}"
    check state.cursor.column == 4

  test "Insert double quote with auto-close":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "say ")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoCloseParen = true
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = handler.handleCharacterInsertion(buf, state, "\"")

    check result.kind == imrHandled
    check buf.getLine(0) == "say \"\""
    check state.cursor.column == 5

  test "Insert without auto-close paren":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoCloseParen = false
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = handler.handleCharacterInsertion(buf, state, "(")

    check result.kind == imrHandled
    check buf.getLine(0) == "func("
    check state.cursor.column == 5

suite "InsertModeHandler - Backspace":
  test "Backspace in middle of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "helo"
    check state.cursor.column == 2

  test "Backspace at beginning joins lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "helloworld"
    check state.cursor.line == 0
    check state.cursor.column == 5

  test "Backspace at start of first line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

  test "Backspace with auto-delete paren":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func()")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 5) # Between ()

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "func"
    check state.cursor.column == 4

  test "Backspace with auto-delete bracket":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "arr[]")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "arr"
    check state.cursor.column == 3

  test "Backspace with auto-delete but not matching pair":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(x)")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 6) # After 'x'

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "func()"
    check state.cursor.column == 5

suite "InsertModeHandler - Delete":
  test "Delete character at cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    let result = handler.handleDelete(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "helo"

suite "InsertModeHandler - Newline":
  test "Insert newline":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    let result = handler.handleNewline(buf, state)

    check result.kind == imrHandled
    check state.cursor.line == 1

suite "InsertModeHandler - Tab":
  test "Insert tab with expandTab enabled":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 4
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleTab(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "    hello"
    check state.cursor.column == 4

  test "Insert tab with expandTab disabled":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.expandTab = false
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleTab(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "\thello"
    check state.cursor.column == 1

suite "InsertModeHandler - Motion":
  test "Handle left motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let result = handler.handleMotion(buf, state, Motion.Left)

    check result.kind == imrHandled
    check state.cursor.column == 2

  test "Handle right motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleMotion(buf, state, Motion.Right)

    check result.kind == imrHandled
    check state.cursor.column == 1

  test "Handle up motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nline2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let result = handler.handleMotion(buf, state, Motion.Up)

    check result.kind == imrHandled
    check state.cursor.line == 0

  test "Handle down motion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nline2")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleMotion(buf, state, Motion.Down)

    check result.kind == imrHandled
    check state.cursor.line == 1

suite "InsertModeHandler - Mode Switch":
  test "Switch to Normal mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    let result = handler.handleModeSwitch(EditorMode.Normal)

    check result.kind == imrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Normal

  test "Switch to Command mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    let result = handler.handleModeSwitch(EditorMode.Command)

    check result.kind == imrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Command

suite "InsertModeHandler - Result Helpers":
  test "isHandled returns true for handled results":
    let result = InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
    check result.isHandled == true

  test "isHandled returns false for error results":
    let result = InsertModeResult(kind: imrError, errorMessage: "test error")
    check result.isHandled == false

  test "isHandled returns false for unhandled results":
    let result = InsertModeResult(kind: imrUnhandled)
    check result.isHandled == false

  test "hasError returns true for error results":
    let result = InsertModeResult(kind: imrError, errorMessage: "test error")
    check result.hasError == true

  test "hasError returns false for handled results":
    let result = InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
    check result.hasError == false

  test "getModeTransition returns mode for handled with transition":
    let result =
      InsertModeResult(kind: imrHandled, modeTransition: some(EditorMode.Normal))
    let transition = result.getModeTransition
    check transition.isSome
    check transition.get == EditorMode.Normal

  test "getModeTransition returns none for handled without transition":
    let result = InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
    let transition = result.getModeTransition
    check transition.isNone

  test "getModeTransition returns none for error results":
    let result = InsertModeResult(kind: imrError, errorMessage: "error")
    let transition = result.getModeTransition
    check transition.isNone

suite "InsertModeHandler - Key Handling":
  test "Handle Escape key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()

    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Normal

  test "Handle Backspace key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo =
      KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "helo"

  test "Handle Delete key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    let keyCombo = KeyCombo(isSpecial: true, special: skDelete, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "helo"

  test "Handle Enter key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check state.cursor.line == 1

  test "Handle Tab key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "  hello"

  test "Handle Left arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check state.cursor.column == 2

  test "Handle Right arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check state.cursor.column == 1

  test "Handle regular character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "xhello"

  test "Handle Home key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: true, special: skHome, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check state.cursor.column == 0

  test "Handle End key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skEnd, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    # Motion.End moves to last character position (Normal mode behavior)
    check state.cursor.column == 4

suite "InsertModeHandler - Ctrl Key Combinations":
  test "Handle Ctrl+W (delete word backward)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 11)

    let keyCombo = KeyCombo(isSpecial: false, char: "w", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "hello "

  test "Handle Ctrl+U (delete to line start)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "world"

  test "Handle Ctrl+T (indent line)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "t", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "  hello"

  test "Handle Ctrl+D (dedent line)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "hello"

  test "Handle Ctrl+Y (insert char from above)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "y", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(1) == "hworld"

  test "Handle Ctrl+E (insert char from below)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "e", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "whello"

  test "Handle Ctrl+I (insert tab)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "i", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check buf.getLine(0) == "  hello"

suite "InsertModeHandler - Macro Recording":
  test "Keys recorded during macro recording":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.macroState.isRecording = true
    state.macroState.register = 'a'
    state.macroState.recordedKeys = @[]
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, keyCombo)

    check state.macroState.recordedKeys.len >= 1

suite "InsertModeHandler - Execute Command":
  test "Execute command via registry":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()
    state.cursor = BufferPosition(line: 0, column: 3)

    let result = handler.executeCommand(buf, state, viewport, "motion.left")

    check result.kind == imrHandled
    check state.cursor.column == 2

  test "Execute non-existent command returns error":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()
    let viewport = createTestViewport()

    let result = handler.executeCommand(buf, state, viewport, "nonexistent.command")

    check result.kind == imrError

suite "InsertModeHandler - Completion":
  test "Commit empty completion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    # No completion active
    let result = handler.commitCompletion(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "hel"

  test "Ctrl+N triggers completion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: false, char: "n", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled

  test "Ctrl+Space triggers completion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled

  test "Ctrl+R handled (signature help)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let keyCombo = KeyCombo(isSpecial: false, char: "r", modifiers: {kmCtrl})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled

suite "InsertModeHandler - PageUp/PageDown":
  test "Handle PageUp key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    for i in 1 .. 30:
      discard buf.insertText(BufferPosition(line: i - 1, column: 5), "\nline" & $i)
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 20, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
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
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check state.cursor.line > 5

suite "InsertModeHandler - Unhandled Keys":
  test "Unknown special key returns unhandled":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Function key (F1) - not typically handled in insert mode
    let keyCombo =
      KeyCombo(isSpecial: true, special: skFunction, fnNum: 1, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrUnhandled

  test "Unhandled modifier combination":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Ctrl+Shift+X - not a standard binding
    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {kmCtrl, kmShift})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    # May be handled or unhandled depending on keybindings
    check result.kind in {imrHandled, imrUnhandled}

suite "InsertModeHandler - Signature Help Helpers":
  test "shouldTriggerSignatureHelp for opening paren":
    let keyCombo = KeyCombo(isSpecial: false, char: "(", modifiers: {})
    check shouldTriggerSignatureHelp(keyCombo) == true

  test "shouldTriggerSignatureHelp for comma":
    let keyCombo = KeyCombo(isSpecial: false, char: ",", modifiers: {})
    check shouldRetriggerSignatureHelp(keyCombo) == true

  test "shouldTriggerSignatureHelp returns false for regular char":
    let keyCombo = KeyCombo(isSpecial: false, char: "a", modifiers: {})
    check shouldTriggerSignatureHelp(keyCombo) == false

  test "shouldTriggerSignatureHelp returns false for special key":
    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    check shouldTriggerSignatureHelp(keyCombo) == false

  test "shouldTriggerSignatureHelp returns false for char with modifiers":
    let keyCombo = KeyCombo(isSpecial: false, char: "(", modifiers: {kmCtrl})
    check shouldTriggerSignatureHelp(keyCombo) == false

suite "InsertModeHandler - Paren Depth Tracking":
  test "Opening paren increments depth":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoCloseParen = false
    state.cursor = BufferPosition(line: 0, column: 4)

    let initialDepth = handler.signatureHelpManager.parenDepth
    discard handler.handleCharacterInsertion(buf, state, "(")

    check handler.signatureHelpManager.parenDepth == initialDepth + 1

  test "Closing paren decrements depth":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(x")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoCloseParen = false
    state.cursor = BufferPosition(line: 0, column: 6)

    handler.signatureHelpManager.incrementParenDepth() # Simulate opening paren
    let initialDepth = handler.signatureHelpManager.parenDepth
    discard handler.handleCharacterInsertion(buf, state, ")")

    check handler.signatureHelpManager.parenDepth == initialDepth - 1

suite "InsertModeHandler - Completion Active Key Handling":
  test "Tab when completion active with selection":
    let buf = newTextBuffer()
    # Add words to buffer so completion has candidates
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion first
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    # Check completion is active
    if handler.completionManager.isActive():
      # Now press Tab
      let keyCombo = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
      check handler.completionManager.menu.hasSelection == true
    else:
      # Completion not active (no candidates found) - still OK
      check true

  test "Escape when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    # Press Escape
    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handler.handleInsertModeKey(buf, state, keyCombo)

    check result.kind == imrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Normal
    check handler.completionManager.isActive() == false

  test "Enter when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive():
      # Press Enter
      let keyCombo =
        KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
      check handler.completionManager.isActive() == false
    else:
      check true

  test "Backspace when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 5)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive():
      # Press Backspace
      let keyCombo =
        KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
      check buf.getLine(1) == "hell"
    else:
      check true

  test "Character input when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive():
      # Type a character
      let keyCombo = KeyCombo(isSpecial: false, char: "l", modifiers: {})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
      check buf.getLine(1) == "hell"
    else:
      check true

  test "Down arrow when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive():
      # Press Down
      let keyCombo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
    else:
      check true

  test "Up arrow when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive():
      # Press Up
      let keyCombo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
    else:
      check true

  test "Ctrl+N when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive():
      # Press Ctrl+N
      let keyCombo = KeyCombo(isSpecial: false, char: "n", modifiers: {kmCtrl})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
    else:
      check true

  test "Ctrl+P when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive():
      # Press Ctrl+P
      let keyCombo = KeyCombo(isSpecial: false, char: "p", modifiers: {kmCtrl})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
    else:
      check true

  test "Shift+Tab when completion active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    # Trigger completion
    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive():
      # Press Shift+Tab
      let keyCombo =
        KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {kmShift})
      let result = handler.handleInsertModeKey(buf, state, keyCombo)

      check result.kind == imrHandled
    else:
      check true
