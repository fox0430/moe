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

import pkg/results

import ../src/moepkg/[buffer, types, config, modes, registers]
import ../src/moepkg/command_handlers/insert_commands

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
    state.expandTab = true
    state.tabStop = 4
    let indentStr = getIndentString(state)
    check indentStr == "    "

  test "Get indent string with expandTab disabled":
    let state = createTestState()
    state.expandTab = false
    let indentStr = getIndentString(state)
    check indentStr == "\t"

  test "Get indent string with tabStop 2":
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    let indentStr = getIndentString(state)
    check indentStr == "  "

suite "Insert Commands - effectiveShiftWidth":
  test "Returns shiftWidth when set":
    let state = createTestState()
    state.tabStop = 8
    state.shiftWidth = 4
    check effectiveShiftWidth(state) == 4

  test "Falls back to tabStop when shiftWidth is 0":
    let state = createTestState()
    state.tabStop = 8
    state.shiftWidth = 0
    check effectiveShiftWidth(state) == 8

suite "Insert Commands - effectiveSoftTabStop":
  test "Returns softTabStop when set":
    let state = createTestState()
    state.tabStop = 8
    state.softTabStop = 4
    check effectiveSoftTabStop(state) == 4

  test "Falls back to tabStop when softTabStop is 0":
    let state = createTestState()
    state.tabStop = 8
    state.softTabStop = 0
    check effectiveSoftTabStop(state) == 8

suite "Insert Commands - getIndentString with shiftWidth":
  test "Uses shiftWidth instead of tabStop when set":
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.shiftWidth = 4
    let indentStr = getIndentString(state)
    check indentStr == "    "

  test "Falls back to tabStop when shiftWidth is 0":
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.shiftWidth = 0
    let indentStr = getIndentString(state)
    check indentStr == "        "

suite "Insert Commands - indentLine with shiftWidth":
  test "Indent uses shiftWidth when set":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.shiftWidth = 4
    state.cursor = BufferPosition(line: 0, column: 0)

    indentLine(buf, state)

    check buf.getLine(0) == "    hello"
    check state.cursor.column == 4

suite "Insert Commands - dedentLine with shiftWidth":
  test "Dedent uses shiftWidth when set":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.shiftWidth = 4
    state.cursor = BufferPosition(line: 0, column: 4)

    dedentLine(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

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
    state.autoIndent = false
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
    state.autoIndent = true
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
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    insertNewline(buf, state)

    check buf.getLine(0) == "hello"
    check buf.len >= 2
    check state.cursor.line == 1

suite "Insert Commands - insertNewline bracket split":
  test "bsmDisable keeps existing behavior inside []":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "test[]")
    let state = createTestState()
    state.autoIndent = true
    state.bracketSplit = bsmDisable
    state.cursor = BufferPosition(line: 0, column: 5)

    insertNewline(buf, state)

    check buf.getLine(0) == "test["
    check buf.getLine(1) == "]"
    check buf.len == 2
    check state.cursor.line == 1
    check state.cursor.column == 0

  test "bsmIndent splits [] onto three lines with deeper middle indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    test[]")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = true
    state.tabStop = 4
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    check buf.getLine(0) == "    test["
    check buf.getLine(1) == "        "
    check buf.getLine(2) == "    ]"
    check buf.len == 3
    check state.cursor.line == 1
    check state.cursor.column == 8

  test "bsmNoIndent splits [] onto three lines without indentation":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    test[]")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = true
    state.tabStop = 4
    state.bracketSplit = bsmNoIndent
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    check buf.getLine(0) == "    test["
    check buf.getLine(1) == ""
    check buf.getLine(2) == "]"
    check buf.len == 3
    check state.cursor.line == 1
    check state.cursor.column == 0

  test "bsmIndent splits () pair":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "f()")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = true
    state.tabStop = 2
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 2)

    insertNewline(buf, state)

    check buf.getLine(0) == "f("
    check buf.getLine(1) == "  "
    check buf.getLine(2) == ")"
    check state.cursor.line == 1
    check state.cursor.column == 2

  test "bsmIndent splits {} pair":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "{}")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = true
    state.tabStop = 2
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 1)

    insertNewline(buf, state)

    check buf.getLine(0) == "{"
    check buf.getLine(1) == "  "
    check buf.getLine(2) == "}"

  test "quote pair is not split":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\"\"")
    let state = createTestState()
    state.autoIndent = true
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 1)

    insertNewline(buf, state)

    # Falls through to existing behavior (single newline, no split)
    check buf.getLine(0) == "\""
    check buf.getLine(1) == "\""
    check buf.len == 2

  test "no split at start of line before []":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "[]")
    let state = createTestState()
    state.autoIndent = true
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 0)

    insertNewline(buf, state)

    # column == 0 -> existing behavior
    check buf.getLine(0) == ""
    check buf.getLine(1) == "[]"
    check buf.len == 2

  test "no split when opening bracket has no matching close after cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "test[")
    let state = createTestState()
    state.autoIndent = true
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 5)

    insertNewline(buf, state)

    # Cursor at end (after [), no closing -> existing behavior
    check buf.getLine(0) == "test["
    check buf.len == 2

  test "no split when bracket pair is mismatched":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "[)")
    let state = createTestState()
    state.autoIndent = true
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 1)

    insertNewline(buf, state)

    # [ and ) are not a matching pair
    check buf.getLine(0) == "["
    check buf.getLine(1) == ")"
    check buf.len == 2

  test "nested bracket pair splits only the inner pair":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "[[]]")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = true
    state.tabStop = 2
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 2)

    insertNewline(buf, state)

    check buf.getLine(0) == "[["
    check buf.getLine(1) == "  "
    check buf.getLine(2) == "]]"
    check buf.len == 3
    check state.cursor.line == 1
    check state.cursor.column == 2

  test "bsmIndent with autoIndent=false uses no base indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    test[]")
    let state = createTestState()
    state.autoIndent = false
    state.expandTab = true
    state.tabStop = 4
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    check buf.getLine(0) == "    test["
    check buf.getLine(1) == "    "
    check buf.getLine(2) == "]"
    check state.cursor.column == 4

  test "bsmIndent uses tab character when expandTab=false":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\ttest[]")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = false
    state.tabStop = 4
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 6)

    insertNewline(buf, state)

    check buf.getLine(0) == "\ttest["
    check buf.getLine(1) == "\t\t"
    check buf.getLine(2) == "\t]"

  test "bsmIndent handles multibyte characters before the bracket":
    # Indent detection only looks at leading ASCII whitespace, but a multibyte
    # character before [] must not break rune-index arithmetic.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "あ[]")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = true
    state.tabStop = 2
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 2)

    insertNewline(buf, state)

    check buf.getLine(0) == "あ["
    check buf.getLine(1) == "  "
    check buf.getLine(2) == "]"
    check state.cursor.line == 1
    check state.cursor.column == 2

  test "bsmIndent registers middle line for Esc cleanup":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    f()")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = true
    state.tabStop = 2
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 6)

    insertNewline(buf, state)

    # Leaving Insert mode without typing should clear the inserted whitespace
    # on the middle line while keeping the bracket pair intact.
    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(0) == "    f("
    check buf.getLine(1) == ""
    check buf.getLine(2) == "    )"
    check state.cursor.column == 0

  test "bsmNoIndent does not register for Esc cleanup":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "f()")
    let state = createTestState()
    state.autoIndent = true
    state.bracketSplit = bsmNoIndent
    state.cursor = BufferPosition(line: 0, column: 2)

    insertNewline(buf, state)

    check state.editState.autoIndentedLine.isNone

suite "Insert Commands - insertLineBelow":
  test "Insert line below with auto-indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = true
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
    state.autoIndent = true
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
    state.autoIndent = true
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
    state.autoIndent = true
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
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    indentLine(buf, state)

    check buf.getLine(0) == "  hello"
    check state.cursor.column == 2

  test "Indent line with tabs":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = false
    state.cursor = BufferPosition(line: 0, column: 0)

    indentLine(buf, state)

    check buf.getLine(0) == "\thello"
    check state.cursor.column == 1

  test "Indent line multiple times":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    indentLine(buf, state, 2)

    check buf.getLine(0) == "    hello"
    check state.cursor.column == 4

suite "Insert Commands - dedentLine":
  test "Dedent line with spaces":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 4)

    dedentLine(buf, state)

    check buf.getLine(0) == "  hello"
    check state.cursor.column == 2

  test "Dedent line with no indentation":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 0)

    dedentLine(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor.column == 0

  test "Dedent line cursor adjustment":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
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

suite "Insert Commands - clearAutoIndentIfUnedited":
  test "o with auto-indent, unedited exit removes indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineBelow(buf, state)

    # New line should have auto-indent
    check buf.getLine(1) == "    "
    check state.cursor.line == 1
    check state.cursor.column == 4
    check state.editState.autoIndentedLine.isSome

    # Simulate exiting Insert mode without editing
    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0
    check state.editState.autoIndentedLine.isNone

  test "o with auto-indent, edited line preserves content":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineBelow(buf, state)

    # Simulate user typing on the new line
    insertChar(buf, state, 'x')

    check buf.getLine(1) == "    x"

    # Exiting Insert mode should NOT remove indent since line was edited
    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == "    x"
    check state.editState.autoIndentedLine.isNone

  test "O with auto-indent, unedited exit removes indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineAbove(buf, state)

    # New line (line 0) should have auto-indent
    check buf.getLine(0) == "    "
    check state.cursor.line == 0
    check state.cursor.column == 4
    check state.editState.autoIndentedLine.isSome

    # Simulate exiting Insert mode without editing
    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(0) == ""
    check state.cursor.column == 0

  test "Enter with auto-indent, unedited exit removes indent":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)

    # New line (line 1) should have auto-indent
    check buf.getLine(1) == "    "
    check state.cursor.line == 1
    check state.cursor.column == 4
    check state.editState.autoIndentedLine.isSome

    # Simulate exiting Insert mode without editing
    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

  test "Auto-indent disabled, no tracking":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineBelow(buf, state)

    check state.editState.autoIndentedLine.isNone

  test "No indentation on source line, no tracking":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertLineBelow(buf, state)

    check state.editState.autoIndentedLine.isNone

  test "o unedited exit uses replaceLine to remove indent in transaction":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    # Start transaction (as normal_handler would do for o/O)
    discard buf.beginTransaction("Insert mode edit")
    insertLineBelow(buf, state)

    # New line should have auto-indent
    check buf.getLine(1) == "    "

    # clearAutoIndentIfUnedited clears indent via replaceLine (in transaction)
    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == ""
    check state.cursor.column == 0

    # Commit and undo should restore original buffer in a single step
    discard buf.commitTransaction()
    discard buf.undo()
    check buf.len == 1
    check buf.getLine(0) == "    hello"

  test "O unedited exit uses replaceLine to remove indent in transaction":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    # Start transaction (as normal_handler would do for o/O)
    discard buf.beginTransaction("Insert mode edit")
    insertLineAbove(buf, state)

    # New line (line 0) should have auto-indent
    check buf.getLine(0) == "    "

    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(0) == ""
    check state.cursor.column == 0

    # Commit and undo should restore original in a single step
    discard buf.commitTransaction()
    discard buf.undo()
    check buf.len == 1
    check buf.getLine(0) == "    hello"

suite "Insert Commands - Undo Cursor Position":
  test "undo after o returns original cursor position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    # Simulate 'o' command: save cursor pos, begin transaction, insert line below
    let originalCursor = state.cursor
    discard buf.beginTransaction("Insert mode edit", cursorPos = some(originalCursor))
    insertLineBelow(buf, state)

    check buf.len == 2
    check state.cursor.line == 1
    check state.cursor.column == 0

    # Commit transaction (simulates ESC from insert mode)
    discard buf.commitTransaction()

    # Undo should return original cursor position, not end of line
    let r = buf.undo()
    check r.isOk
    check buf.len == 1
    check r.value.line == 0
    check r.value.column == 5 # Original cursor, NOT lineContent.charLen (11)

  test "undo after O returns original cursor position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 3)

    let originalCursor = state.cursor
    discard buf.beginTransaction("Insert mode edit", cursorPos = some(originalCursor))
    insertLineAbove(buf, state)

    check buf.len == 2
    check state.cursor.line == 0
    check state.cursor.column == 0

    discard buf.commitTransaction()

    let r = buf.undo()
    check r.isOk
    check buf.len == 1
    check r.value.line == 0
    check r.value.column == 3 # Original cursor position

  test "undo after o with auto-indent returns original cursor position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    indented")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 6)

    let originalCursor = state.cursor
    discard buf.beginTransaction("Insert mode edit", cursorPos = some(originalCursor))
    insertLineBelow(buf, state)

    check buf.len == 2
    check buf.getLine(1) == "    " # auto-indented new line

    discard buf.commitTransaction()

    let r = buf.undo()
    check r.isOk
    check buf.len == 1
    check buf.getLine(0) == "    indented"
    check r.value.line == 0
    check r.value.column == 6 # Original cursor, not end of line

  test "undo after o with text typed returns original cursor position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 5)

    let originalCursor = state.cursor
    discard buf.beginTransaction("Insert mode edit", cursorPos = some(originalCursor))
    insertLineBelow(buf, state)

    # Simulate typing "new text" in insert mode
    discard buf.insertText(state.cursor, "new text")
    state.cursor.column += 8

    check buf.len == 2
    check buf.getLine(1) == "new text"

    discard buf.commitTransaction()

    let r = buf.undo()
    check r.isOk
    check buf.len == 1
    check buf.getLine(0) == "hello world"
    check r.value.line == 0
    check r.value.column == 5 # Original cursor, not end of line or typed text pos

  test "undo after O with text typed returns original cursor position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 7)

    let originalCursor = state.cursor
    discard buf.beginTransaction("Insert mode edit", cursorPos = some(originalCursor))
    insertLineAbove(buf, state)

    # Simulate typing "above" in insert mode on line 0
    discard buf.insertText(state.cursor, "above")
    state.cursor.column += 5

    check buf.len == 2
    check buf.getLine(0) == "above"

    discard buf.commitTransaction()

    let r = buf.undo()
    check r.isOk
    check buf.len == 1
    check buf.getLine(0) == "hello world"
    check r.value.line == 0
    check r.value.column == 7 # Original cursor position

  test "redo after undo of o restores cursor position":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 2)

    let originalCursor = state.cursor
    discard buf.beginTransaction("Insert mode edit", cursorPos = some(originalCursor))
    insertLineBelow(buf, state)
    discard buf.commitTransaction()

    discard buf.undo()
    check buf.len == 1

    let r = buf.redo()
    check r.isOk
    check buf.len == 2
    # Redo returns the saved cursor position
    check r.value.line == 0
    check r.value.column == 2
