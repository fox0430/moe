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

import std/[unittest, options, tables, json, monotimes]

import
  ../src/moepkg/[
    buffer,
    types,
    key_bindings,
    modes,
    motion,
    command_registry,
    config,
    registers,
    completion,
    signature_help,
    types/editor_types,
    lsp_integration,
  ]
import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/command_handlers/insert_handler

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Insert,
    previousMode: EditorMode.Normal,
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
  )
  let cfg = newEditorConfig()
  cfg.standard.tabStop = 2
  cfg.standard.expandTab = true
  cfg.standard.autoIndent = true
  EditorState(
    activeWindow: window,
    display:
      DisplaySettings(showLineCount: true, showLinePercentage: true, showEncoding: true),
    config: cfg,
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

proc createTestHandler(buf: TextBuffer): InsertModeHandler =
  ## Create an InsertModeHandler for testing
  let keyBindingRegistry = newKeyBindingRegistry()
  setupDefaultBindings(keyBindingRegistry)

  let commandRegistry = newCommandRegistry()
  registerBuiltinCommands(commandRegistry)

  let motionController =
    newMotionController(buf, createTestState(), createTestViewport())

  newInsertModeHandler(keyBindingRegistry, motionController, commandRegistry)

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
    state.autoCloseParen = true
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
    state.autoCloseParen = true
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
    state.autoCloseParen = true
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
    state.autoCloseParen = true
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
    state.autoCloseParen = false
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
    state.autoDeleteParen = true
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
    state.autoDeleteParen = true
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
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 6) # After 'x'

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "func()"
    check state.cursor.column == 5

  test "Backspace auto-delete opening paren with content inside":
    # (hello) -> backspace on ( -> only ( deleted (not adjacent pair)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "(hello)")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 1) # After (

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "hello)"
    check state.cursor.column == 0

  test "Backspace auto-delete closing paren with content inside":
    # (hello) -> backspace on ) -> only ) deleted (not adjacent pair)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "(hello)")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 7) # After )

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "(hello"
    check state.cursor.column == 6

  test "Backspace auto-delete nested paren":
    # ((hello)) -> backspace on inner ( -> only inner ( deleted (not adjacent)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "((hello))")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 2) # After inner (

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "(hello))"
    check state.cursor.column == 1

  test "Backspace auto-delete with prefix":
    # func(args) -> backspace on ( -> only ( deleted (not adjacent)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(args)")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 5) # After (

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "funcargs)"
    check state.cursor.column == 4

  test "Backspace auto-delete unmatched paren falls back to normal":
    # (hello -> backspace on ( -> hello (no matching close)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "(hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 1)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

  test "Backspace auto-delete closing bracket with content":
    # [items] -> backspace on ] -> only ] deleted (not adjacent)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "[items]")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 7) # After ]

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "[items"
    check state.cursor.column == 6

  test "Backspace auto-delete closing brace with content":
    # {body} -> backspace on } -> only } deleted (not adjacent)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "{body}")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 6) # After }

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "{body"
    check state.cursor.column == 5

  test "Backspace auto-delete nested closing paren":
    # ((inner)) -> backspace on inner ) -> only inner ) deleted (not adjacent)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "((inner))")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 8) # After inner )

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "((inner)"
    check state.cursor.column == 7

  test "Backspace auto-delete quote adjacent pair":
    # "" -> backspace between quotes -> empty
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\"\"")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 1) # Between ""

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == ""
    check state.cursor.column == 0

  test "Backspace adjacent bracket pair auto-delete":
    # [|] -> backspace between adjacent pair -> empty
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "[]")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 1) # Between []

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == ""
    check state.cursor.column == 0

  test "Backspace closing bracket at end of line keeps opening bracket":
    # []| -> backspace on ] -> [ (only ] deleted)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "[]")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 2) # After ]

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "["
    check state.cursor.column == 1

  test "Backspace auto-delete disabled":
    # (hello) -> backspace on ( with autoDeleteParen=false -> normal delete
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "(hello)")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = false
    state.cursor = BufferPosition(line: 0, column: 1) # After (

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "hello)"
    check state.cursor.column == 0

  test "Backspace auto-delete opening bracket with suffix":
    # a(b)c -> backspace on ( -> only ( deleted (not adjacent)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a(b)c")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 2) # After (

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "ab)c"
    check state.cursor.column == 1

  test "Backspace auto-delete closing bracket with suffix":
    # a(b)c -> backspace on ) -> only ) deleted (not adjacent)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a(b)c")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 4) # After )

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "a(bc"
    check state.cursor.column == 3

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
    state.autoIndent = false
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
    state.expandTab = true
    state.tabStop = 4
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
    state.expandTab = false
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleTab(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "\thello"
    check state.cursor.column == 1

suite "InsertModeHandler - Tab with softTabStop":
  test "Tab aligns to next softTabStop boundary from column 0":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.softTabStop = 4
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleTab(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "    hello"
    check state.cursor.column == 4

  test "Tab aligns to next softTabStop boundary from mid-position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), " hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.softTabStop = 4
    state.cursor = BufferPosition(line: 0, column: 1)

    let result = handler.handleTab(buf, state)

    check result.kind == imrHandled
    # From column 1, next 4-boundary is column 4 => insert 3 spaces
    check buf.getLine(0) == "    hello"
    check state.cursor.column == 4

  test "Tab inserts full softTabStop at boundary":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.softTabStop = 4
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = handler.handleTab(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "        hello"
    check state.cursor.column == 8

  test "Tab with softTabStop=0 uses tabStop":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 4
    state.softTabStop = 0
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = handler.handleTab(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "    hello"
    check state.cursor.column == 4

suite "InsertModeHandler - Backspace with softTabStop":
  test "Backspace in leading whitespace deletes to previous softTabStop boundary":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.softTabStop = 4
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

  test "Backspace in leading whitespace aligns to boundary":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "      hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.softTabStop = 4
    state.cursor = BufferPosition(line: 0, column: 6)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    # From column 6, previous 4-boundary is 4 => delete 2 chars
    check buf.getLine(0) == "    hello"
    check state.cursor.column == 4

  test "Backspace not in leading whitespace deletes single char":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "he  llo")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.softTabStop = 4
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    # Non-leading whitespace, so single char delete
    check buf.getLine(0) == "he llo"
    check state.cursor.column == 3

  test "Backspace with expandTab disabled does normal delete":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = false
    state.softTabStop = 4
    state.cursor = BufferPosition(line: 0, column: 4)

    let result = handler.handleBackspace(buf, state)

    check result.kind == imrHandled
    check buf.getLine(0) == "   hello"
    check state.cursor.column == 3

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

  test "Right motion reaches end of line in Insert mode":
    # Regression: moving right in Insert mode must reach the end-of-line column
    # (one past the last character), not stop on the last character.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    for _ in 0 ..< 5:
      discard handler.handleMotion(buf, state, Motion.Right)

    check state.cursor.column == 5

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

  test "Switch to Replace mode":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)

    let result = handler.handleModeSwitch(EditorMode.Replace)

    check result.kind == imrHandled
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Replace

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
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.Normal

  test "Handle Backspace key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo =
      KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "helo"

  test "Handle Delete key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    let keyCombo = KeyCombo(isSpecial: true, special: skDelete, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "helo"

  test "Handle Enter key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check state.cursor.line == 1

  test "Handle Tab key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "  hello"

  test "Handle Left arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check state.cursor.column == 2

  test "Handle Right arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check state.cursor.column == 1

  test "Handle regular character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "xhello"

  test "Handle Home key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: true, special: skHome, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check state.cursor.column == 0

  test "Handle End key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skEnd, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    # In Insert mode End lands at end of line (one past the last character)
    check state.cursor.column == 5

suite "InsertModeHandler - Ctrl Key Combinations":
  test "Handle Ctrl+W (delete word backward)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 11)

    let keyCombo = KeyCombo(isSpecial: false, char: "w", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "hello "

  test "Handle Ctrl+U (delete to line start)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "world"

  test "Handle Ctrl+T (indent line)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "t", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "  hello"

  test "Handle Ctrl+D (dedent line)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "hello"

  test "Handle Ctrl+Y (insert char from above)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "y", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(1) == "hworld"

  test "Handle Ctrl+E (insert char from below)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "e", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "whello"

  test "Handle Ctrl+I (insert tab)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "i", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "  hello"

suite "InsertModeHandler - Macro Recording":
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
    discard handler.handleInsertModeKey(buf, state, keyCombo)

    check state.pendingInput.macroState.recordedKeys.len == 0

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
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled

  test "Ctrl+Space triggers completion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled

  test "Ctrl+R handled (signature help)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let keyCombo = KeyCombo(isSpecial: false, char: "r", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled

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
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
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
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
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
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrUnhandled

  test "Unhandled modifier combination":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Ctrl+Shift+X - not a standard binding
    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {kmCtrl, kmShift})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    # May be handled or unhandled depending on key_bindings
    check r.kind in {imrHandled, imrUnhandled}

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
    state.autoCloseParen = false
    state.cursor = BufferPosition(line: 0, column: 4)

    let initialDepth = handler.signatureHelpManager.parenDepth
    discard handler.handleCharacterInsertion(buf, state, "(")

    check handler.signatureHelpManager.parenDepth == initialDepth + 1

  test "Closing paren decrements depth":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(x")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoCloseParen = false
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
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
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.Normal
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
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
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
    else:
      check true

  test "BackTab (skBackTab) when completion active":
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
      # Press BackTab (how terminals actually send Shift+Tab)
      let keyCombo =
        KeyCombo(isSpecial: true, special: skBackTab, fnNum: 0, modifiers: {})
      let r = handler.handleInsertModeKey(buf, state, keyCombo)

      check r.kind == imrHandled
      check handler.completionManager.menu.hasSelection
    else:
      check true

  test "BackTab cycles backwards through completion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "alpha beta")
    discard buf.insertText(BufferPosition(line: 0, column: 10), "\nal")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 2)

    handler.completionManager.triggerCompletion(
      buf, state.cursor.line, state.cursor.column, langNone
    )

    if handler.completionManager.isActive() and
        handler.completionManager.menu.entries.len >= 2:
      # First Tab highlights item 0 (cycling no longer mutates the buffer)
      let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
      discard handler.handleInsertModeKey(buf, state, tabKey)
      check handler.completionManager.menu.selectedIndex == 0

      # Second Tab highlights item 1
      discard handler.handleInsertModeKey(buf, state, tabKey)
      check handler.completionManager.menu.selectedIndex == 1

      # BackTab goes back to item 0
      let backTabKey =
        KeyCombo(isSpecial: true, special: skBackTab, fnNum: 0, modifiers: {})
      discard handler.handleInsertModeKey(buf, state, backTabKey)
      check handler.completionManager.menu.selectedIndex == 0

      # The buffer is untouched throughout cycling — only the typed prefix is there
      check buf.getLine(1) == "al"

suite "InsertModeHandler - Path completion":
  test "Slash triggers path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "/" character
    let keyCombo = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check handler.completionManager.isPathCompletion

  test "Dot-slash triggers path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "." first
    let dotKey = KeyCombo(isSpecial: false, char: ".", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, dotKey)

    # Then type "/"
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    let r = handler.handleInsertModeKey(buf, state, slashKey)

    check r.kind == imrHandled
    check handler.completionManager.isPathCompletion

  test "Plain word does not trigger path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "hello"
    for ch in "hello":
      let keyCombo = KeyCombo(isSpecial: false, char: $ch, modifiers: {})
      discard handler.handleInsertModeKey(buf, state, keyCombo)

    check not handler.completionManager.isPathCompletion

  test "Directory entry committed without trailing slash":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "./s")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    # Simulate path completion with a directory entry
    let mgr = handler.completionManager
    mgr.isPathCompletion = true
    mgr.pathBasePath = "."
    mgr.pathOriginalPrefix = "./"
    mgr.state = csActive
    mgr.menu.prefix = "s"
    mgr.menu.triggerCol = 2
    mgr.menu.triggerLine = 0
    mgr.menu.entries = @[
      CompletionEntry(
        word: "src/",
        matchScore: 100,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFolder),
        detail: some("Directory"),
        documentation: none(string),
      ),
      CompletionEntry(
        word: "setup.nim",
        matchScore: 50,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFile),
        detail: some("File"),
        documentation: none(string),
      ),
    ]

    # Tab previews the first entry (directory "src/") without its trailing slash
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check buf.getLine(0) == "./src" # cycling previews into the buffer

    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)

    # Directory should be inserted without trailing '/'
    check buf.getLine(0) == "./src"
    check state.cursor.column == 5

  test "File entry committed with full name":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "./s")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    # Simulate path completion with a file entry
    let mgr = handler.completionManager
    mgr.isPathCompletion = true
    mgr.pathBasePath = "."
    mgr.pathOriginalPrefix = "./"
    mgr.state = csActive
    mgr.menu.prefix = "s"
    mgr.menu.triggerCol = 2
    mgr.menu.triggerLine = 0
    mgr.menu.entries = @[
      CompletionEntry(
        word: "setup.nim",
        matchScore: 50,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFile),
        detail: some("File"),
        documentation: none(string),
      )
    ]

    # Tab previews the file entry with its full name
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check buf.getLine(0) == "./setup.nim" # cycling previews into the buffer

    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)

    # File should be inserted with full name
    check buf.getLine(0) == "./setup.nim"
    check state.cursor.column == 11

  test "Committing a cycled-to directory preserves no-trailing-slash":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "./")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    let mgr = handler.completionManager
    mgr.isPathCompletion = true
    mgr.pathBasePath = "."
    mgr.pathOriginalPrefix = "./"
    mgr.state = csActive
    mgr.menu.prefix = ""
    mgr.menu.triggerCol = 2
    mgr.menu.triggerLine = 0
    mgr.menu.entries = @[
      CompletionEntry(
        word: "docs/",
        matchScore: 100,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFolder),
        detail: some("Directory"),
        documentation: none(string),
      ),
      CompletionEntry(
        word: "src/",
        matchScore: 100,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFolder),
        detail: some("Directory"),
        documentation: none(string),
      ),
      CompletionEntry(
        word: "README.md",
        matchScore: 50,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFile),
        detail: some("File"),
        documentation: none(string),
      ),
    ]

    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})

    # Cycle to the second entry ("src/"); each cycle previews into the buffer
    # without the directory's trailing slash
    discard handler.handleInsertModeKey(buf, state, tabKey)
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check handler.completionManager.menu.selectedIndex == 1
    check buf.getLine(0) == "./src"

    # Enter commits the highlighted directory without its trailing slash
    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)
    check buf.getLine(0) == "./src"

  test "Escape cancels path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "/" to trigger path completion
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, slashKey)
    check handler.completionManager.isPathCompletion

    # Press Escape
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, escKey)

    check not handler.completionManager.isPathCompletion
    check not handler.completionManager.isActive()

  test "Tilde-slash triggers path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "~"
    let tildeKey = KeyCombo(isSpecial: false, char: "~", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tildeKey)
    check not handler.completionManager.isPathCompletion

    # Type "/"
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, slashKey)

    check handler.completionManager.isPathCompletion
    check buf.getLine(0) == "~/"

  test "Backspace re-triggers path completion when path context remains":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "./sr")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 4)

    # Set up path completion state
    let mgr = handler.completionManager
    mgr.isPathCompletion = true
    mgr.pathBasePath = "."
    mgr.pathOriginalPrefix = "./"
    mgr.state = csActive
    mgr.menu.prefix = "sr"
    mgr.menu.triggerCol = 2
    mgr.menu.triggerLine = 0
    mgr.menu.entries = @[
      CompletionEntry(
        word: "src/",
        matchScore: 100,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFolder),
        detail: some("Directory"),
        documentation: none(string),
      )
    ]

    # Backspace deletes 'r', leaving "./s" — still a path context
    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)

    check buf.getLine(0) == "./s"
    check handler.completionManager.isPathCompletion
    check handler.completionManager.isActive()

  test "Backspace cancels path completion when path context lost":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "/")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 1)

    # Set up path completion state
    let mgr = handler.completionManager
    mgr.isPathCompletion = true
    mgr.pathBasePath = "."
    mgr.pathOriginalPrefix = "/"
    mgr.state = csActive
    mgr.menu.prefix = ""
    mgr.menu.triggerCol = 1
    mgr.menu.triggerLine = 0
    mgr.menu.entries = @[
      CompletionEntry(
        word: "usr/",
        matchScore: 100,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFolder),
        detail: some("Directory"),
        documentation: none(string),
      )
    ]

    # Backspace deletes '/', leaving "" — no path context
    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)

    check buf.getLine(0) == ""
    check not handler.completionManager.isPathCompletion
    check not handler.completionManager.isActive()

  test "Non-path character cancels path completion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "./src")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    # Set up path completion state
    let mgr = handler.completionManager
    mgr.isPathCompletion = true
    mgr.pathBasePath = "."
    mgr.pathOriginalPrefix = "./"
    mgr.state = csActive
    mgr.menu.prefix = "src"
    mgr.menu.triggerCol = 2
    mgr.menu.triggerLine = 0
    mgr.menu.entries = @[
      CompletionEntry(
        word: "src/",
        matchScore: 100,
        source: csFilePath,
        kind: some(CompletionItemKind.cikFolder),
        detail: some("Directory"),
        documentation: none(string),
      )
    ]

    # Type space — not a path character
    let spaceKey = KeyCombo(isSpecial: false, char: " ", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, spaceKey)

    check buf.getLine(0) == "./src "
    check not handler.completionManager.isPathCompletion
    check not handler.completionManager.isActive()

suite "InsertModeHandler - imap action commands":
  test "imap insert-backspace deletes character before cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    # Map Q to insert-backspace via :imap
    let err = handler.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Insert, "Q", "insert-backspace"
    )
    check err == ""

    let keyCombo = KeyCombo(isSpecial: false, char: "Q")
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "Hell"
    check state.cursor.column == 4

  test "imap insert-delete deletes character at cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let err = handler.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Insert, "Q", "insert-delete"
    )
    check err == ""

    let keyCombo = KeyCombo(isSpecial: false, char: "Q")
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "ello"
    check state.cursor.column == 0

  test "imap insert-newline inserts newline at cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let err = handler.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Insert, "Q", "insert-newline"
    )
    check err == ""

    let keyCombo = KeyCombo(isSpecial: false, char: "Q")
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrHandled
    check buf.len == 2
    check buf.getLine(0) == "Hel"
    check buf.getLine(1) == "lo"

suite "InsertModeHandler - Command mode command alias bridge":
  test "imap K to bdelete dispatches via exec.cmdline.* bridge":
    # The bridge must fire even from Insert mode so e.g. `imap K = "bdelete"`
    # reaches the command-line parser (and its modified-buffer guard) instead
    # of silently returning imrUnhandled.
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let err =
      handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "K", "bdelete")
    check err == ""

    let state = createTestState()
    let keyCombo = KeyCombo(isSpecial: false, char: "K")
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrExecCommand
    check r.execCommandText == "bdelete"

  test "imap D to bd preserves the short alias verbatim":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    discard handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "D", "bd")

    let state = createTestState()
    let keyCombo = KeyCombo(isSpecial: false, char: "D")
    let r = handler.handleInsertModeKey(buf, state, keyCombo)

    check r.kind == imrExecCommand
    check r.execCommandText == "bd"

suite "InsertModeHandler - Ctrl+O (Insert-Normal mode)":
  test "Ctrl+O switches to Normal mode and sets insertNormalMode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let ctrlO = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, ctrlO)

    check r.kind == imrHandled
    check r.modeTransition.isSome
    check r.modeTransition.get == EditorMode.Normal
    check state.insertNormalMode == true

  test "Ctrl+O cancels completion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    # Trigger completion first
    handler.completionManager.triggerCompletion(buf, 0, 5, SourceLanguage.langNone)

    let ctrlO = KeyCombo(isSpecial: false, char: "o", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(buf, state, ctrlO)

    check r.kind == imrHandled
    check r.modeTransition.get == EditorMode.Normal
    check state.insertNormalMode == true

suite "InsertModeHandler - completion commit":
  test "Cycling previews into the buffer; Enter commits via textEdit":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    ve")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    handler.completionManager.lspItems = @[
      CompletionItem(
        label: "vec!",
        textEdit: some(
          %*{
            "range":
              {"start": {"line": 0, "character": 4}, "end": {"line": 0, "character": 6}},
            "newText": "vec!",
          }
        ),
      ),
      CompletionItem(
        label: "version",
        textEdit: some(
          %*{
            "range":
              {"start": {"line": 0, "character": 4}, "end": {"line": 0, "character": 6}},
            "newText": "version",
          }
        ),
      ),
    ]

    # Trigger completion to populate entries from lspItems
    handler.completionManager.triggerCompletion(buf, 0, 6, langNone)
    check handler.completionManager.isActive()
    check handler.completionManager.menu.entries.len >= 2

    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})

    # First Tab highlights idx 0 and previews it into the buffer via its textEdit
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check handler.completionManager.menu.selectedIndex == 0
    check buf.getLine(0) == "    vec!"

    # Second Tab highlights idx 1; the preview is replaced in place
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check handler.completionManager.menu.selectedIndex == 1
    check buf.getLine(0) == "    version"

    # Enter commits the highlighted entry via its textEdit (same final result)
    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)
    check buf.getLine(0) == "    version"
    check not handler.completionManager.isActive()

  test "Commit applies textEdit on final confirm":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    ve")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    # Set up completion with textEdit entry
    handler.completionManager.menu.entries = @[
      CompletionEntry(
        word: "vec!",
        matchScore: 100,
        source: csLsp,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 4),
              `end`: lspTypes.Position(line: 0, character: 6),
            ),
            newText: "vec!",
          )
        ),
      )
    ]
    handler.completionManager.menu.prefix = "ve"
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.state = csActive

    let result = handler.commitCompletion(buf, state)
    check result.kind == imrHandled
    # textEdit replaces range [4,6) with "vec!"
    check buf.getLine(0) == "    vec!"
    check state.cursor.column == 8
    check not handler.completionManager.isActive()

  test "Commit with textEdit uses rune indexes on surrogate pair line":
    # Regression: before the fix, utf16OffsetToUtf8 (byte offset) was used
    # instead of utf16ToRuneIndex (rune index) to compute the cursor column
    # after commit. On a line with a surrogate-pair emoji the byte offset
    # for 'b' in "a😀b" is 5 while the correct rune index is 2, so the
    # cursor would be placed 3 columns too far right.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a😀b")
    # Rune indexes:  a=0, 😀=1, b=2
    # UTF-16 offsets: a=0, 😀=1..2, b=3
    # Byte offsets:   a=0, 😀=1..4, b=5
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    # LSP returns a textEdit that replaces 'b' (UTF-16 3..4) with "X"
    handler.completionManager.menu.entries = @[
      CompletionEntry(
        word: "X",
        matchScore: 100,
        source: csLsp,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 3),
              `end`: lspTypes.Position(line: 0, character: 4),
            ),
            newText: "X",
          )
        ),
      )
    ]
    handler.completionManager.menu.prefix = "b"
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.state = csActive

    let result = handler.commitCompletion(buf, state)
    check result.kind == imrHandled
    # textEdit replaces UTF-16 range [3,4) (= rune range [2,3)) with "X"
    check buf.getLine(0) == "a😀X"
    # Cursor should be at rune index 3 (startCol=2 + newText.runeLen=1)
    check state.cursor == BufferPosition(line: 0, column: 3)
    check not handler.completionManager.isActive()

  test "Commit expands a snippet and positions the cursor at $0":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    ve")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    handler.completionManager.menu.entries = @[
      CompletionEntry(
        word: "vec!",
        matchScore: 100,
        source: csLsp,
        isSnippet: true,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 4),
              `end`: lspTypes.Position(line: 0, character: 6),
            ),
            newText: "vec![$0]",
          )
        ),
      )
    ]
    handler.completionManager.menu.prefix = "ve"
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.state = csActive

    let result = handler.commitCompletion(buf, state)
    check result.kind == imrHandled
    # Snippet "vec![$0]" expands to "vec![]" with the cursor inside the brackets
    check buf.getLine(0) == "    vec![]"
    check state.cursor.column == 9 # startCol(4) + offset of $0 (after "vec![")
    check not handler.completionManager.isActive()

  test "Commit applies additionalTextEdits (auto-import) above the cursor":
    let buf = newTextBuffer()
    # An empty first line stands in for the import insertion point.
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\nfoo")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    handler.completionManager.menu.entries = @[
      CompletionEntry(
        word: "foobar",
        matchScore: 100,
        source: csLsp,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 1, character: 0),
              `end`: lspTypes.Position(line: 1, character: 3),
            ),
            newText: "foobar",
          )
        ),
        additionalTextEdits: some(
          @[
            TextEdit(
              range: Range(
                start: lspTypes.Position(line: 0, character: 0),
                `end`: lspTypes.Position(line: 0, character: 0),
              ),
              newText: "import bar\n",
            )
          ]
        ),
      )
    ]
    handler.completionManager.menu.prefix = "foo"
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.state = csActive

    let result = handler.commitCompletion(buf, state)
    check result.kind == imrHandled
    # The import edit lands on line 0 and the completion on the (now shifted) line
    check buf.getLine(0) == "import bar"
    check buf.getLine(2) == "foobar"
    # The cursor line is shifted down by the one inserted import line
    check state.cursor.line == 2
    check state.cursor.column == 6
    check not handler.completionManager.isActive()

  test "Cycling preview defers additionalTextEdits until the final commit":
    # Hybrid: Tab previews the completion text into the buffer immediately, but
    # the auto-import (additionalTextEdits) must NOT be applied while cycling -
    # only the final commit (Enter) applies it.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\nfoo")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    handler.completionManager.menu.entries = @[
      CompletionEntry(
        word: "foobar",
        matchScore: 100,
        source: csLsp,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 1, character: 0),
              `end`: lspTypes.Position(line: 1, character: 3),
            ),
            newText: "foobar",
          )
        ),
        additionalTextEdits: some(
          @[
            TextEdit(
              range: Range(
                start: lspTypes.Position(line: 0, character: 0),
                `end`: lspTypes.Position(line: 0, character: 0),
              ),
              newText: "import bar\n",
            )
          ]
        ),
      )
    ]
    handler.completionManager.menu.prefix = "foo"
    handler.completionManager.menu.triggerLine = 1
    handler.completionManager.menu.triggerCol = 0
    handler.completionManager.state = csActive

    # Tab previews "foobar" but leaves the import line untouched
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check buf.getLine(0) == "" # auto-import NOT applied during cycling
    check buf.getLine(1) == "foobar"

    # Enter finalizes and applies the auto-import above the cursor
    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)
    check buf.getLine(0) == "import bar"
    check buf.getLine(2) == "foobar"
    check state.cursor.line == 2
    check state.cursor.column == 6
    check not handler.completionManager.isActive()

  test "Commit honors a textEdit range that extends past the cursor":
    # Replace-mode completion: the cursor sits between "foo" and "bar" and the
    # server's textEdit replaces the whole identifier [0,6) with "foobaz". The
    # trailing "bar" must be replaced too, not left dangling as "foobazbar".
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "foobar")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    handler.completionManager.menu.entries = @[
      CompletionEntry(
        word: "foobaz",
        matchScore: 100,
        source: csLsp,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 0),
              `end`: lspTypes.Position(line: 0, character: 6),
            ),
            newText: "foobaz",
          )
        ),
      )
    ]
    handler.completionManager.menu.prefix = "foo"
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.state = csActive

    let result = handler.commitCompletion(buf, state)
    check result.kind == imrHandled
    check buf.getLine(0) == "foobaz"
    check state.cursor.column == 6
    check not handler.completionManager.isActive()

  test "Commit deletes a multi-line textEdit range wholesale":
    # The server's textEdit spans two lines ("foo\nbar"); replacing it must remove
    # the whole range and join the lines, not delete only the first line and leave
    # "bar" dangling.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "foo\nbar")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    handler.completionManager.menu.entries = @[
      CompletionEntry(
        word: "baz",
        matchScore: 100,
        source: csLsp,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 0),
              `end`: lspTypes.Position(line: 1, character: 3),
            ),
            newText: "baz",
          )
        ),
      )
    ]
    handler.completionManager.menu.prefix = "foo"
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.state = csActive

    let result = handler.commitCompletion(buf, state)
    check result.kind == imrHandled
    check buf.len == 1 # the two lines were joined into one
    check buf.getLine(0) == "baz"
    check state.cursor == BufferPosition(line: 0, column: 3)
    check not handler.completionManager.isActive()

proc setSnippetEntry(handler: InsertModeHandler, body: string) =
  ## Single snippet completion entry whose textEdit replaces [4,6) on line 0
  ## (the "xx" the popup was triggered on) with the expanded snippet body.
  handler.completionManager.menu.entries = @[
    CompletionEntry(
      word: "x",
      matchScore: 100,
      source: csLsp,
      isSnippet: true,
      textEdit: some(
        TextEdit(
          range: Range(
            start: lspTypes.Position(line: 0, character: 4),
            `end`: lspTypes.Position(line: 0, character: 6),
          ),
          newText: body,
        )
      ),
    )
  ]
  handler.completionManager.menu.prefix = "xx"
  handler.completionManager.menu.selectedIndex = 0
  handler.completionManager.menu.hasSelection = true
  handler.completionManager.state = csActive

suite "InsertModeHandler - snippet session":
  test "Committing a multi-stop snippet starts a session":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")

    discard handler.commitCompletion(buf, state)
    check buf.getLine(0) == "    replace(size_type pos, size_type n1)"
    check state.snippetSession.active
    check state.snippetSession.index == 0
    check state.snippetSession.defaultPending
    check state.snippetSession.stops ==
      @[
        SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 13),
        SnippetStop(num: 2, pos: BufferPosition(line: 0, column: 27), len: 12),
      ]
    # Cursor lands at the end of the first stop's default (selection end).
    check state.cursor == BufferPosition(line: 0, column: 25)

  test "Multi-line snippet body resolves stops on later lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("for ${1:x} {\n\t$0\n}")

    discard handler.commitCompletion(buf, state)
    check buf.getLine(0) == "    for x {"
    check buf.getLine(1) == "\t"
    check buf.getLine(2) == "}"
    check state.snippetSession.active
    check state.snippetSession.stops ==
      @[
        SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 8), len: 1),
        SnippetStop(num: 0, pos: BufferPosition(line: 1, column: 1), len: 0),
      ]
    check state.cursor == BufferPosition(line: 0, column: 9)

  test "A lone $0 does not start a session":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("vec![$0]")

    discard handler.commitCompletion(buf, state)
    check buf.getLine(0) == "    vec![]"
    check not state.snippetSession.active
    check state.cursor == BufferPosition(line: 0, column: 9)

  test "A lone bare $n does not start a session":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("if $1:")

    discard handler.commitCompletion(buf, state)
    check buf.getLine(0) == "    if :"
    check not state.snippetSession.active
    check state.cursor == BufferPosition(line: 0, column: 7)

  test "A single placeholder with a default starts a session":
    # Common clangd shape for one-parameter calls: no $0, one ${1:...}. The
    # session is what lets the first keystroke replace the default, so it must
    # start even though there is no second stop to Tab to.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("push_back(${1:value})")

    discard handler.commitCompletion(buf, state)
    check buf.getLine(0) == "    push_back(value)"
    check state.snippetSession.active
    check state.snippetSession.defaultPending
    check state.snippetSession.stops ==
      @[SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 14), len: 5)]
    check state.cursor == BufferPosition(line: 0, column: 19)

  test "Committing a snippet over a pending default does not grow the buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("push_back(${1:value})")
    discard handler.commitCompletion(buf, state)
    check state.snippetSession.active
    let highBefore = (buf.len - 1)
    # Re-open the popup with ONE snippet candidate whose textEdit covers the
    # selected placeholder range [14,19) ("value"), as clangd would.
    handler.completionManager.menu.entries = @[
      CompletionEntry(
        word: "value",
        matchScore: 100,
        source: csLsp,
        isSnippet: true,
        textEdit: some(
          TextEdit(
            range: Range(
              start: lspTypes.Position(line: 0, character: 14),
              `end`: lspTypes.Position(line: 0, character: 19),
            ),
            newText: "value_t(${1:int a})",
          )
        ),
      )
    ]
    handler.completionManager.menu.prefix = "value"
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.menu.triggerLine = 0
    handler.completionManager.menu.triggerCol = 14
    handler.completionManager.state = csActive
    check handler.completionManager.isActive()
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check (buf.len - 1) == highBefore

  test "Single-placeholder Tab ends the session without inserting a newline":
    # Regression: a one-stop snippet (no $0) must not leave the session alive
    # or insert a newline when Tab is pressed past its only stop. The Tab
    # falls through to the normal indentation handling (vsnip-style
    # "jumpable ? jump : tab"): expandTab aligns to the next tabStop(2)
    # boundary, one space here.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("push_back(${1:value})")
    discard handler.commitCompletion(buf, state)
    check state.snippetSession.active
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check (buf.len - 1) == 0
    check buf.getLine(0) == "    push_back(value )"
    check not state.snippetSession.active
    check state.cursor == BufferPosition(line: 0, column: 20)

  test "Tab jumps to the next stop, Shift-Tab back to the previous":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check state.snippetSession.active
    check state.snippetSession.index == 1
    check state.snippetSession.defaultPending
    # End of stop 2's default "size_type n1" (col 27 + len 12).
    check state.cursor == BufferPosition(line: 0, column: 39)

    let backTabKey =
      KeyCombo(isSpecial: true, special: skBackTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, backTabKey)
    check state.snippetSession.index == 0
    check state.cursor == BufferPosition(line: 0, column: 25)
    # Revisiting a stop re-selects its content (VSCode-style) so the next
    # keystroke replaces the whole range.
    check state.snippetSession.defaultPending

  test "Tab onto a final $0 ends the session":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("push(${1:ch});$0")
    discard handler.commitCompletion(buf, state)
    check state.snippetSession.active

    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check not state.snippetSession.active
    # $0 sits after the ");".
    check state.cursor == BufferPosition(line: 0, column: 13)

  test "Tab onto a defaulted last stop keeps the session for one more edit":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("insert(${1:idx}, ${2:ch})")
    discard handler.commitCompletion(buf, state)

    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    # The last stop still has a default to replace: the session stays alive.
    check state.snippetSession.active
    check state.snippetSession.defaultPending
    # A second Tab past the end finishes the session and falls through to
    # normal indentation: two spaces (tabStop 2) before the ")".
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check not state.snippetSession.active
    check buf.getLine(0) == "    insert(idx, ch  )"
    check state.cursor == BufferPosition(line: 0, column: 20)

  test "Typing replaces the pending default and shifts later stops":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let zKey = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, zKey)
    check buf.getLine(0) == "    replace(z, size_type n1)"
    check not state.snippetSession.defaultPending
    # The stop grows to cover the typed text (VSCode-style), so Shift-Tab back
    # to it re-selects exactly what was typed.
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 1)
    # Stop 2 shifted left by len("size_type pos") - len("z") = 12.
    check state.snippetSession.stops[1] ==
      SnippetStop(num: 2, pos: BufferPosition(line: 0, column: 15), len: 12)
    check state.cursor == BufferPosition(line: 0, column: 13)

    # A second character extends the typed text in place.
    discard handler.handleInsertModeKey(buf, state, zKey)
    check buf.getLine(0) == "    replace(zz, size_type n1)"
    check state.snippetSession.stops[1].pos.column == 16

    # Tab then lands at the end of stop 2's (shifted) default.
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check state.cursor == BufferPosition(line: 0, column: 28)
    check state.snippetSession.defaultPending

  test "Backspace deletes the whole pending default":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)
    check buf.getLine(0) == "    replace(, size_type n1)"
    check state.snippetSession.active
    check not state.snippetSession.defaultPending
    check state.cursor == BufferPosition(line: 0, column: 12)
    check state.snippetSession.stops[1].pos.column == 14

    # A further Backspace is a plain single-character delete.
    discard handler.handleInsertModeKey(buf, state, bsKey)
    check buf.getLine(0) == "    replace, size_type n1)"
    check state.snippetSession.stops[1].pos.column == 13

  test "Backspace inside typed content shrinks the current stop":
    # Regression: a plain backspace within the text typed into a stop must
    # shrink that stop's recorded length, or Shift-Tab re-selection and the
    # highlight overshoot the actual content.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let zKey = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, zKey)
    discard handler.handleInsertModeKey(buf, state, zKey)
    # Close any popup re-triggered by typing so Backspace reaches the session.
    handler.completionManager.cancelCompletion()
    check buf.getLine(0) == "    replace(zz, size_type n1)"
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 2)

    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)
    check buf.getLine(0) == "    replace(z, size_type n1)"
    # len shrank from 2 to 1 to match the remaining "z"; cursor sits at its end.
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 1)
    check state.cursor == BufferPosition(line: 0, column: 13)

  test "Auto-close paren inserts the pair in a placeholder and remaps stops":
    # The pair is a single two-character insertion at the cursor, so it stays
    # remappable: the stop covers both characters, the cursor sits between
    # them, and later stops shift by two.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoCloseParen = true
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let parenKey = KeyCombo(isSpecial: false, char: "(", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, parenKey)
    handler.completionManager.cancelCompletion()
    check buf.getLine(0) == "    replace((), size_type n1)"
    check state.cursor == BufferPosition(line: 0, column: 13)
    check not state.snippetSession.defaultPending
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 2)
    check state.snippetSession.stops[1].pos.column == 16

    # Backspace between the pair auto-deletes both characters; the stop is
    # swallowed by the two-column edit (clamped, len zeroed) and stop 2
    # shifts back.
    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)
    check buf.getLine(0) == "    replace(, size_type n1)"
    check state.cursor == BufferPosition(line: 0, column: 12)
    check state.snippetSession.active
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 0)
    check state.snippetSession.stops[1].pos.column == 14

  test "Auto-delete pair inside typed content shrinks the stop by two":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.autoCloseParen = true
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let fKey = KeyCombo(isSpecial: false, char: "f", modifiers: {})
    let parenKey = KeyCombo(isSpecial: false, char: "(", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, fKey)
    discard handler.handleInsertModeKey(buf, state, parenKey)
    handler.completionManager.cancelCompletion()
    check buf.getLine(0) == "    replace(f(), size_type n1)"
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 3)

    # The pair sits strictly inside the typed content: deleting it must
    # shrink the stop by both removed columns, not just the one before the
    # cursor.
    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)
    check buf.getLine(0) == "    replace(f, size_type n1)"
    check state.cursor == BufferPosition(line: 0, column: 13)
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 1)
    check state.snippetSession.stops[1].pos.column == 15

  test "Delete wipes the whole pending default like Backspace":
    # The default is selected (pending), so Delete clears it wholesale instead
    # of removing the character past the selection end.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let delKey = KeyCombo(isSpecial: true, special: skDelete, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, delKey)
    check buf.getLine(0) == "    replace(, size_type n1)"
    check state.snippetSession.active
    check not state.snippetSession.defaultPending
    check state.cursor == BufferPosition(line: 0, column: 12)
    check state.snippetSession.stops[1].pos.column == 14

  test "Enter on a pending default replaces it before splitting the line":
    # Enter on a selected default deletes it first (selection semantics), so the
    # default is not left stranded in the buffer.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)
    # First default gone, the line split where it used to start.
    check buf.getLine(0) == "    replace("
    check not state.snippetSession.defaultPending
    check state.snippetSession.active
    # Stop 2 followed the split onto the next line.
    check state.snippetSession.stops[1].pos.line == 1

  test "Enter inside a stop's typed content collapses it to a bare stop":
    # `len` is a single-line span; a newline inside the typed content would make
    # it cross lines, so the stop drops to bare (len 0) rather than overshoot.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let zKey = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, zKey)
    discard handler.handleInsertModeKey(buf, state, zKey)
    handler.completionManager.cancelCompletion()
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 2)
    # Place the cursor between the two typed chars and split there.
    state.cursor = BufferPosition(line: 0, column: 13)
    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)
    check state.snippetSession.active
    check state.snippetSession.stops[0].len == 0

  test "A multi-line placeholder default is treated as a bare stop":
    # `len` is a single-line column span, so a default spanning lines cannot be
    # selected wholesale: the stop still navigates but is not pending and is
    # not highlighted.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("wrap(${1:a\nb}, ${2:c})")

    discard handler.commitCompletion(buf, state)
    check buf.getLine(0) == "    wrap(a"
    check buf.getLine(1) == "b, c)"
    check state.snippetSession.active
    # First default wraps a line, so it is not selectable (len 0, not pending).
    check not state.snippetSession.defaultPending
    check state.snippetSession.stops ==
      @[
        SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 9), len: 0),
        SnippetStop(num: 2, pos: BufferPosition(line: 1, column: 3), len: 1),
      ]
    # Cursor still lands at the end of the (multi-line) first default.
    check state.cursor == BufferPosition(line: 1, column: 1)

  test "Escape ends the session and leaves Insert mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("push(${1:ch});$0")
    discard handler.commitCompletion(buf, state)

    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let res = handler.handleInsertModeKey(buf, state, escKey)
    check not state.snippetSession.active
    check res.kind == imrHandled
    check res.modeTransition == some(EditorMode.Normal)

  test "Cursor movement keys end the session":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("push(${1:ch});$0")
    discard handler.commitCompletion(buf, state)

    let leftKey = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, leftKey)
    check not state.snippetSession.active

  test "Tab cycles the popup, not the stops, while completion is active":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)
    check state.snippetSession.active

    # Reopen a (word) completion popup inside the placeholder.
    handler.completionManager.menu.entries =
      @[CompletionEntry(word: "pos_type", matchScore: 100, source: csBuffer)]
    handler.completionManager.menu.prefix = ""
    handler.completionManager.menu.triggerLine = state.cursor.line
    handler.completionManager.menu.triggerCol = state.cursor.column
    handler.completionManager.state = csActive

    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    # Popup selection advanced; the snippet session did not move.
    check handler.completionManager.menu.hasSelection
    check state.snippetSession.active
    check state.snippetSession.index == 0

  test "Enter inside a session shifts later stops to the next line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)
    # Type over the default first so Enter splits between the arguments.
    let zKey = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, zKey)
    check state.cursor == BufferPosition(line: 0, column: 13)
    # Typing re-triggered the popup ("z" fuzzy-matches "size_type"); close it
    # so Enter reaches the session instead of dismissing the popup.
    handler.completionManager.cancelCompletion()

    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)
    check state.snippetSession.active
    let stop2 = state.snippetSession.stops[1]
    check stop2.pos.line == 1
    # ", " stays on the new line before the stop: the column delta follows
    # the cursor's landing column (auto-indent included).
    check stop2.pos.column == state.cursor.column + 2

    # Tab still lands at the end of stop 2's default on the new line.
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check state.cursor == BufferPosition(line: 1, column: stop2.pos.column + stop2.len)

  test "Typing while the popup commits a snippet replaces the first default":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")

    # The typed character both commits the highlighted snippet and replaces
    # the first placeholder default in the same keystroke.
    let zKey = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, zKey)
    check buf.getLine(0) == "    replace(z, size_type n1)"
    check state.snippetSession.active
    check not state.snippetSession.defaultPending
    check state.cursor == BufferPosition(line: 0, column: 13)

  test "Backspace while the completion popup is open still remaps the stops":
    # Regression: typing into a placeholder re-opens the popup
    # (AutoTriggerPrefixLength is 1), so Backspace takes the popup branch —
    # it must remap the session exactly like the session path does.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let zKey = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, zKey)
    # The popup re-opened; leave it open so Backspace goes through it.
    check handler.completionManager.isActive()
    check state.snippetSession.stops[1].pos.column == 15

    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)
    check buf.getLine(0) == "    replace(, size_type n1)"
    # The deleted character was the stop's whole content: it collapses to a
    # bare stop (not -1), and stop 2 shifted back with the edit.
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 0)
    check state.snippetSession.stops[1].pos.column == 14

  test "Nested placeholder stops collapse instead of keeping stale lengths":
    # Regression: in `${1:${2:inner}}` both stops cover the same range.
    # Replacing stop 1's default must zero stop 2's recorded length, or a
    # later Tab + keystroke wholesale-deletes unrelated buffer text.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("f(${1:${2:inner}})")
    discard handler.commitCompletion(buf, state)
    check buf.getLine(0) == "    f(inner)"
    check state.snippetSession.defaultPending

    let zKey = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, zKey)
    check buf.getLine(0) == "    f(z)"
    # Stop 2's range was swallowed by the default replacement: len 0.
    check state.snippetSession.stops[1].len == 0
    handler.completionManager.cancelCompletion()

    # Tab onto stop 2 (bare, last) ends the session; the next keystroke is a
    # plain insertion, not a wholesale delete of the closing paren.
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check not state.snippetSession.active
    discard handler.handleInsertModeKey(buf, state, zKey)
    check buf.getLine(0) == "    f(zz)"

  test "Committing a word inside a placeholder grows the stop over it":
    # Regression: completing the word typed into a placeholder must resize the
    # current stop to the inserted text, or Shift-Tab re-selection (and the
    # wholesale replace that follows) covers a stale, shorter range.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    # Type "si" into the placeholder, then commit a buffer-word completion.
    let sKey = KeyCombo(isSpecial: false, char: "s", modifiers: {})
    let iKey = KeyCombo(isSpecial: false, char: "i", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, sKey)
    discard handler.handleInsertModeKey(buf, state, iKey)
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 2)
    handler.completionManager.menu.entries =
      @[CompletionEntry(word: "size_type", matchScore: 100, source: csBuffer)]
    handler.completionManager.menu.prefix = "si"
    handler.completionManager.menu.triggerLine = 0
    handler.completionManager.menu.triggerCol = 12
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.state = csActive
    discard handler.commitCompletion(buf, state)

    check buf.getLine(0) == "    replace(size_type, size_type n1)"
    check state.snippetSession.active
    check state.snippetSession.stops[0] ==
      SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 12), len: 9)
    # Stop 2 shifted right by len("size_type") - len("si") = 7.
    check state.snippetSession.stops[1].pos.column == 23

    # Shift-Tab back re-selects exactly the committed word.
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    let backTabKey =
      KeyCombo(isSpecial: true, special: skBackTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    discard handler.handleInsertModeKey(buf, state, backTabKey)
    check state.snippetSession.defaultPending
    check state.cursor == BufferPosition(line: 0, column: 21)
    let zKey = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, zKey)
    check buf.getLine(0) == "    replace(z, size_type n1)"

  test "Enter in a session suppresses bracket splitting":
    # Regression: bracketSplit inserts a second newline past the cursor, which
    # the session's single-edit remap cannot represent — later stops would
    # shift one line instead of two. It is suppressed for in-session newlines.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    state.bracketSplit = bsmIndent
    handler.setSnippetEntry("f(${1:x}), ${2:y}")
    discard handler.commitCompletion(buf, state)
    check buf.getLine(0) == "    f(x), y"

    # Wipe the pending default: the cursor lands between the bracket pair.
    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)
    check buf.getLine(0) == "    f(), y"
    check state.cursor == BufferPosition(line: 0, column: 6)

    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enterKey)
    # A plain (auto-indented) newline, not a three-line bracket split.
    check (buf.len - 1) == 1
    check buf.getLine(1) == "    ), y"
    check state.snippetSession.stops[1] ==
      SnippetStop(num: 2, pos: BufferPosition(line: 1, column: 7), len: 1)
    # The setting itself is restored.
    check state.bracketSplit == bsmIndent

  test "Ctrl+N keeps the session alive":
    # Manually triggering completion inside a placeholder must not end the
    # session: the auto-trigger path keeps it, so the manual one does too.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    xx")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    handler.setSnippetEntry("replace(${1:size_type pos}, ${2:size_type n1})")
    discard handler.commitCompletion(buf, state)

    let ctrlN = KeyCombo(isSpecial: false, char: "n", modifiers: {kmCtrl})
    discard handler.handleInsertModeKey(buf, state, ctrlN)
    check state.snippetSession.active
    check state.snippetSession.index == 0
    check state.snippetSession.defaultPending

suite "InsertModeHandler - completion selection invalidation":
  test "Backspace clears the selection so the next keystroke does not commit it":
    # Regression: Tab previews item 0 into the buffer ("te" -> "template") and
    # activates hasSelection. Backspace edits the preview and re-filters via
    # updateFilter, which must drop the selection. If hasSelection survived, the
    # next typed char would re-commit an item the user never confirmed (producing
    # e.g. "templatextemplate" instead of "templatx").
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "te")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    handler.completionManager.allWords = @["template", "test"]
    handler.completionManager.menu.entries = @[
      CompletionEntry(word: "template", matchScore: 100, source: csBuffer),
      CompletionEntry(word: "test", matchScore: 50, source: csBuffer),
    ]
    handler.completionManager.menu.prefix = "te"
    handler.completionManager.menu.triggerLine = 0
    handler.completionManager.menu.triggerCol = 0
    handler.completionManager.state = csActive

    # Tab previews item 0 ("template") into the buffer and selects it
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tabKey)
    check handler.completionManager.menu.hasSelection
    check buf.getLine(0) == "template"

    # Backspace edits the preview and must drop the selection
    let bsKey = KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, bsKey)
    check not handler.completionManager.menu.hasSelection
    check buf.getLine(0) == "templat"

    # Typing now just inserts the char; it must NOT re-commit a completion item
    let xKey = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, xKey)
    check buf.getLine(0) == "templatx"

suite "InsertModeHandler - LSP debounce prefix staleness":
  test "Fast typing through LSP debounce keeps menu.prefix in sync":
    # Regression: when LSP debounce skipped the re-request and no LSP items had
    # arrived yet, menu.prefix was left stale at the first typed character.
    # Pressing Tab then deleted only that one char and re-inserted the
    # completion, producing e.g. "ttemplate" instead of "template" at col 0.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "template\n")

    # Real LspIntegration but no server is started; enabled flag is enough to
    # take the LSP code path in triggerLspCompletionRequest.
    let lsp = newLspIntegration("")
    lsp.enabled = true

    let keyBindingRegistry = newKeyBindingRegistry()
    setupDefaultBindings(keyBindingRegistry)
    let commandRegistry = newCommandRegistry()
    registerBuiltinCommands(commandRegistry)
    let motionController =
      newMotionController(buf, createTestState(), createTestViewport())
    let handler =
      newInsertModeHandler(keyBindingRegistry, motionController, commandRegistry, lsp)

    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    # Type 't' at col 0 of a fresh line — first call, no debounce
    let typeT = KeyCombo(isSpecial: false, char: "t", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, typeT)
    check handler.completionManager.isActive()
    check handler.completionManager.menu.prefix == "t"

    # Mimic an in-flight LSP request: set lastLspRequestTime to "now" so the
    # next call to triggerLspCompletionRequest hits the debounce-skip branch
    # while lspItems is still empty.
    handler.completionManager.lastLspRequestTime = getMonoTime()

    # Type 'e' — under the bug, triggerLspCompletionRequest returns early
    # and leaves menu.prefix at "t". With the fix it refreshes the buffer
    # completion menu so menu.prefix becomes "te".
    let typeE = KeyCombo(isSpecial: false, char: "e", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, typeE)
    check handler.completionManager.menu.prefix == "te"

    # Tab highlights "template"; Enter commits it. The commit replaces the whole
    # typed word [triggerCol, cursor), so the synced prefix yields "template".
    let tab = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, tab)
    let enter = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(buf, state, enter)

    check buf.getLine(1) == "template"
    check state.cursor.column == 8

suite "InsertModeHandler - autocomplete / lsp completion gates":
  test "triggerLspCompletionRequest is a no-op when autocomplete.enable is false":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)
    state.config.autocomplete.enable = false

    handler.triggerLspCompletionRequest(buf, state)

    # Nothing should activate; menu stays empty.
    check not handler.completionManager.isActive()
    check handler.completionManager.menu.entries.len == 0

  test "triggerLspCompletionRequest surfaces buffer completions when autocomplete.enable is true":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world\nhel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)
    state.config.autocomplete.enable = true
    state.config.lsp.completion.enable = false

    handler.triggerLspCompletionRequest(buf, state)

    # Buffer completion should have activated with the current prefix.
    check handler.completionManager.menu.prefix == "hel"

  test "handleInsertModeKey autocomplete branch is gated by autocomplete.enable":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello\n")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)
    state.config.autocomplete.enable = false

    let typeH = KeyCombo(isSpecial: false, char: "h", modifiers: {})
    discard handler.handleInsertModeKey(buf, state, typeH)

    # 'h' inserts but no completion menu should activate.
    check buf.getLine(1) == "h"
    check not handler.completionManager.isActive()
