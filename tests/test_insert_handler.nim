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

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/completion {.all.}
import ../src/moepkg/signature_help {.all.}
import ../src/moepkg/syntax/tokenizer {.all.}
import ../src/moepkg/window_manager {.all.}
import ../src/moepkg/editor_types {.all.}
import ../src/moepkg/lsp_integration {.all.}
import ../src/moepkg/command_handlers/insert_handler {.all.}

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Insert,
    previousMode: EditorMode.Normal,
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
  )
  EditorState(
    activeWindow: window,
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
      shiftWidth: 0,
      softTabStop: 0,
      expandTab: true,
      autoIndent: true,
      autoCloseParen: false,
      autoDeleteParen: false,
    ),
    windowDisplay: WindowDisplayState(needsFullRedraw: false, viewportReservedLines: 2),
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

proc createTestEditor(buf: TextBuffer, state: EditorState): Editor =
  ## Create a minimal Editor wrapping the given buffer/state for testing
  state.activeWindow.buffer = buf
  Editor(
    textBuffer: buf,
    state: state,
    viewport: createTestViewport(),
    windowManager:
      EditorWindowManager(windows: @[state.activeWindow], activeWindowIndex: 0),
  )

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

  test "Backspace auto-delete opening paren with content inside":
    # (hello) -> backspace on ( -> only ( deleted (not adjacent pair)
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "(hello)")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = false
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
    state.display.autoDeleteParen = true
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
    state.display.autoDeleteParen = true
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

suite "InsertModeHandler - Tab with softTabStop":
  test "Tab aligns to next softTabStop boundary from column 0":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 8
    state.display.softTabStop = 4
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
    state.display.expandTab = true
    state.display.tabStop = 8
    state.display.softTabStop = 4
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
    state.display.expandTab = true
    state.display.tabStop = 8
    state.display.softTabStop = 4
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
    state.display.expandTab = true
    state.display.tabStop = 4
    state.display.softTabStop = 0
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
    state.display.expandTab = true
    state.display.tabStop = 8
    state.display.softTabStop = 4
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
    state.display.expandTab = true
    state.display.tabStop = 8
    state.display.softTabStop = 4
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
    state.display.expandTab = true
    state.display.tabStop = 8
    state.display.softTabStop = 4
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
    state.display.expandTab = false
    state.display.softTabStop = 4
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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "helo"

  test "Handle Delete key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    let keyCombo = KeyCombo(isSpecial: true, special: skDelete, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "helo"

  test "Handle Enter key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.display.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "  hello"

  test "Handle Left arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check state.cursor.column == 2

  test "Handle Right arrow key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check state.cursor.column == 1

  test "Handle regular character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "xhello"

  test "Handle Home key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: true, special: skHome, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check state.cursor.column == 0

  test "Handle End key":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let keyCombo = KeyCombo(isSpecial: true, special: skEnd, fnNum: 0, modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check buf.getLine(0) == "hello "

  test "Handle Ctrl+U (delete to line start)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
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
    discard handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled

  test "Ctrl+Space triggers completion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hel")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let keyCombo = KeyCombo(isSpecial: false, char: " ", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled

  test "Ctrl+R handled (signature help)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "func(")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    let keyCombo = KeyCombo(isSpecial: false, char: "r", modifiers: {kmCtrl})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrUnhandled

  test "Unhandled modifier combination":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Ctrl+Shift+X - not a standard binding
    let keyCombo = KeyCombo(isSpecial: false, char: "x", modifiers: {kmCtrl, kmShift})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
      # First Tab selects item 0
      let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
      discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)
      let firstWord = handler.completionManager.menu.entries[0].word

      # Second Tab selects item 1
      discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)

      # BackTab goes back to item 0
      let backTabKey =
        KeyCombo(isSpecial: true, special: skBackTab, fnNum: 0, modifiers: {})
      discard handler.handleInsertModeKey(createTestEditor(buf, state), backTabKey)

      check buf.getLine(1) == firstWord
    else:
      check true

suite "InsertModeHandler - Path completion":
  test "Slash triggers path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "/" character
    let keyCombo = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrHandled
    check handler.completionManager.isPathCompletion

  test "Dot-slash triggers path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "." first
    let dotKey = KeyCombo(isSpecial: false, char: ".", modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), dotKey)

    # Then type "/"
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), slashKey)

    check r.kind == imrHandled
    check handler.completionManager.isPathCompletion

  test "Plain word does not trigger path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "hello"
    for ch in "hello":
      let keyCombo = KeyCombo(isSpecial: false, char: $ch, modifiers: {})
      discard handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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

    # Tab selects first entry (directory "src/")
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)

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

    # Tab selects file entry
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)

    # File should be inserted with full name
    check buf.getLine(0) == "./setup.nim"
    check state.cursor.column == 11

  test "Cycling path entries preserves no-trailing-slash for directories":
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

    # First Tab: selects "docs/" -> inserts "docs"
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)
    check buf.getLine(0) == "./docs"

    # Second Tab: selects "src/" -> inserts "src"
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)
    check buf.getLine(0) == "./src"

    # Third Tab: selects "README.md" -> inserts full name
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)
    check buf.getLine(0) == "./README.md"

  test "Escape cancels path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "/" to trigger path completion
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), slashKey)
    check handler.completionManager.isPathCompletion

    # Press Escape
    let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), escKey)

    check not handler.completionManager.isPathCompletion
    check not handler.completionManager.isActive()

  test "Tilde-slash triggers path completion":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    let state = createTestState()

    # Type "~"
    let tildeKey = KeyCombo(isSpecial: false, char: "~", modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tildeKey)
    check not handler.completionManager.isPathCompletion

    # Type "/"
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), slashKey)

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
    discard handler.handleInsertModeKey(createTestEditor(buf, state), bsKey)

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
    discard handler.handleInsertModeKey(createTestEditor(buf, state), bsKey)

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
    discard handler.handleInsertModeKey(createTestEditor(buf, state), spaceKey)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

    check r.kind == imrExecCommand
    check r.execCommandText == "bdelete"

  test "imap D to bd preserves the short alias verbatim":
    let buf = newTextBuffer()
    let handler = createTestHandler(buf)
    discard handler.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "D", "bd")

    let state = createTestState()
    let keyCombo = KeyCombo(isSpecial: false, char: "D")
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), keyCombo)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), ctrlO)

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
    let r = handler.handleInsertModeKey(createTestEditor(buf, state), ctrlO)

    check r.kind == imrHandled
    check r.modeTransition.get == EditorMode.Normal
    check state.insertNormalMode == true

suite "InsertModeHandler - textEdit with keepPopupOpen":
  test "Tab cycling with textEdit uses prefix-deletion, not textEdit":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    ve")
    let handler = createTestHandler(buf)
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    # Set up LSP items with textEdit
    let lspRange = Range(
      start: lspTypes.Position(line: 0, character: 4),
      `end`: lspTypes.Position(line: 0, character: 6),
    )
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

    # First Tab: activates selection (idx=0 "vec!")
    let tabKey = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)
    check buf.getLine(0) == "    vec!"

    # Second Tab: selects next (idx=1 "version")
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)
    check buf.getLine(0) == "    version"

    # Third Tab: wraps back (idx=0 "vec!")
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tabKey)
    check buf.getLine(0) == "    vec!"

  test "Commit with textEdit applies textEdit on final confirm":
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
            newText: "vec![$0]",
          )
        ),
      )
    ]
    handler.completionManager.menu.prefix = "ve"
    handler.completionManager.menu.selectedIndex = 0
    handler.completionManager.menu.hasSelection = true
    handler.completionManager.state = csActive

    # Final commit (keepPopupOpen=false) should use textEdit
    let result = handler.commitCompletion(buf, state, keepPopupOpen = false)
    check result.kind == imrHandled
    # textEdit replaces range [4,6) with "vec![$0]"
    check buf.getLine(0) == "    vec![$0]"
    check not handler.completionManager.isActive()

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
    let handler = newInsertModeHandler(
      keyBindingRegistry,
      motionController,
      commandRegistry,
      lsp,
      true,
      NotificationConfig(),
    )

    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    # Type 't' at col 0 of a fresh line — first call, no debounce
    let typeT = KeyCombo(isSpecial: false, char: "t", modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), typeT)
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
    discard handler.handleInsertModeKey(createTestEditor(buf, state), typeE)
    check handler.completionManager.menu.prefix == "te"

    let tab = KeyCombo(isSpecial: true, special: skTab, fnNum: 0, modifiers: {})
    discard handler.handleInsertModeKey(createTestEditor(buf, state), tab)

    check buf.getLine(1) == "template"
    check state.cursor.column == 8
