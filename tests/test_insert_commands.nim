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

## Tests for insert_commands.nim

import std/[unittest, options, tables]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/command_handlers/insert_commands {.all.}

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

suite "Insert Commands - getLineIndent":
  test "Get indent from line with spaces":
    let line = "    hello world"
    let indent = getLineIndent(line)
    check indent == "    "

  test "Get indent from line with tabs":
    let line = "\t\thello world"
    let indent = getLineIndent(line)
    check indent == "\t\t"

  test "Get indent from line with mixed spaces and tabs":
    let line = "  \t  hello world"
    let indent = getLineIndent(line)
    check indent == "  \t  "

  test "Get indent from line without indentation":
    let line = "hello world"
    let indent = getLineIndent(line)
    check indent == ""

  test "Get indent from empty line":
    let line = ""
    let indent = getLineIndent(line)
    check indent == ""

  test "Get indent from line with only whitespace":
    let line = "    "
    let indent = getLineIndent(line)
    check indent == "    "

suite "Insert Commands - getIndentString":
  test "Get indent string with expandTab enabled":
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 4
    let indentStr = getIndentString(state)
    check indentStr == "    "

  test "Get indent string with expandTab disabled":
    let state = createTestState()
    state.display.expandTab = false
    let indentStr = getIndentString(state)
    check indentStr == "\t"

  test "Get indent string with tabStop 2":
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    let indentStr = getIndentString(state)
    check indentStr == "  "

suite "Insert Commands - insertChar":
  test "Insert character at beginning of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    insertChar(buf, state, 'x')

    check buf.getLine(0) == "xhello"
    check state.cursor.column == 1

  test "Insert character in middle of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    insertChar(buf, state, 'x')

    check buf.getLine(0) == "hexllo"
    check state.cursor.column == 3

  test "Insert character at end of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    insertChar(buf, state, 'x')

    check buf.getLine(0) == "hellox"
    check state.cursor.column == 6

suite "Insert Commands - insertTab":
  test "Insert tab character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    insertTab(buf, state)

    check buf.getLine(0) == "\thello"
    check state.cursor.column == 1

suite "Insert Commands - insertBackspace":
  test "Backspace in middle of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    insertBackspace(buf, state)

    check buf.getLine(0) == "helo"
    check state.cursor.column == 2

  test "Backspace at beginning of line (join lines)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    insertBackspace(buf, state)

    check buf.getLine(0) == "helloworld"
    check state.cursor.line == 0
    check state.cursor.column == 5

  test "Backspace at beginning of first line (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    insertBackspace(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

suite "Insert Commands - insertDelete":
  test "Delete character at cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    insertDelete(buf, state)

    check buf.getLine(0) == "helo"
    check state.cursor.column == 2

  test "Delete at end of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    insertDelete(buf, state)

    # Should be a no-op or join with next line
    check state.cursor.column == 5

suite "Insert Commands - insertNewline":
  test "Insert newline without auto-indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.display.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    insertNewline(buf, state)

    check buf.getLine(0) == "hello"
    check buf.getLine(1) == " world"
    check state.cursor.line == 1
    check state.cursor.column == 0

  test "Insert newline with auto-indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello world")
    let state = createTestState()
    state.display.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    check buf.getLine(0) == "    hello"
    check buf.getLine(1) == "     world"
    check state.cursor.line == 1
    check state.cursor.column == 4

  test "Insert newline at end of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.display.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    insertNewline(buf, state)

    check buf.getLine(0) == "hello"
    check buf.len >= 2
    check state.cursor.line == 1

suite "Insert Commands - insertLineBelow":
  test "Insert line below with auto-indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.display.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineBelow(buf, state)

    check buf.len >= 2
    check state.cursor.line == 1
    check state.cursor.column == 4
    check state.mode == EditorMode.Insert

  test "Insert line below without indentation":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.display.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineBelow(buf, state)

    check buf.len >= 2
    check state.cursor.line == 1
    check state.cursor.column == 0
    check state.mode == EditorMode.Insert

suite "Insert Commands - insertLineAbove":
  test "Insert line above with auto-indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.display.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineAbove(buf, state)

    check buf.len >= 2
    check state.cursor.line == 0
    check state.cursor.column == 4
    check state.mode == EditorMode.Insert

  test "Insert line above without indentation":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.display.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineAbove(buf, state)

    check buf.len >= 2
    check state.cursor.line == 0
    check state.cursor.column == 0
    check state.mode == EditorMode.Insert

suite "Insert Commands - insertAppend":
  test "Append after cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.cursor = BufferPosition(line: 0, column: 2)

    insertAppend(buf, state)

    check state.cursor.column == 3
    check state.mode == EditorMode.Insert

  test "Append at end of line (no cursor move)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.cursor = BufferPosition(line: 0, column: 5)

    insertAppend(buf, state)

    check state.cursor.column == 5
    check state.mode == EditorMode.Insert

suite "Insert Commands - insertAppendEnd":
  test "Append at end of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.cursor = BufferPosition(line: 0, column: 0)

    insertAppendEnd(buf, state)

    check state.cursor.column == 11
    check state.mode == EditorMode.Insert

suite "Insert Commands - indentLine":
  test "Indent line with spaces (expandTab)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    indentLine(buf, state)

    check buf.getLine(0) == "  hello"
    check state.cursor.column == 2

  test "Indent line with tabs":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.display.expandTab = false
    state.cursor = BufferPosition(line: 0, column: 0)

    indentLine(buf, state)

    check buf.getLine(0) == "\thello"
    check state.cursor.column == 1

  test "Indent line multiple times":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    indentLine(buf, state, 2)

    check buf.getLine(0) == "    hello"
    check state.cursor.column == 4

suite "Insert Commands - dedentLine":
  test "Dedent line with spaces":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 4)

    dedentLine(buf, state)

    check buf.getLine(0) == "  hello"
    check state.cursor.column == 2

  test "Dedent line with no indentation":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    dedentLine(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

  test "Dedent line cursor adjustment":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createTestState()
    state.display.expandTab = true
    state.display.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 1) # Cursor in indent

    dedentLine(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

suite "Insert Commands - deleteWordBackward":
  test "Delete word backward":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 11)

    deleteWordBackward(buf, state)

    check buf.getLine(0) == "hello "
    check state.cursor.column == 6

  test "Delete word backward with whitespace":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello   world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 13)

    deleteWordBackward(buf, state)

    check buf.getLine(0) == "hello   "
    check state.cursor.column == 8

  test "Delete word backward at start of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    deleteWordBackward(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

  test "Delete word backward with symbols":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello++world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 7)

    deleteWordBackward(buf, state)

    check buf.getLine(0) == "helloworld"

suite "Insert Commands - deleteToLineStart":
  test "Delete to line start":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    deleteToLineStart(buf, state)

    check buf.getLine(0) == "world"
    check state.cursor.column == 0

  test "Delete to line start at beginning":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    deleteToLineStart(buf, state)

    check buf.getLine(0) == "hello world"
    check state.cursor.column == 0

  test "Delete to line start at end":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    deleteToLineStart(buf, state)

    check buf.getLine(0) == ""
    check state.cursor.column == 0

suite "Insert Commands - insertCharFromAbove":
  test "Insert char from line above":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let result = insertCharFromAbove(buf, state)

    check result == true
    check buf.getLine(1) == "hworld"
    check state.cursor.column == 1

  test "Insert char from line above - no line above":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = insertCharFromAbove(buf, state)

    check result == false
    check buf.getLine(0) == "hello"

  test "Insert char from line above - column out of range":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hi")
    discard buf.insertText(BufferPosition(line: 0, column: 2), "\nworld")
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)

    let result = insertCharFromAbove(buf, state)

    check result == false
    check buf.getLine(1) == "world"

suite "Insert Commands - insertCharFromBelow":
  test "Insert char from line below":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = insertCharFromBelow(buf, state)

    check result == true
    check buf.getLine(0) == "whello"
    check state.cursor.column == 1

  test "Insert char from line below - no line below":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)

    let result = insertCharFromBelow(buf, state)

    check result == false
    check buf.getLine(0) == "hello"

  test "Insert char from line below - column out of range":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nhi")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    let result = insertCharFromBelow(buf, state)

    check result == false
    check buf.getLine(0) == "hello"
