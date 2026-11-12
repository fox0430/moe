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

import std/[unittest, options, tables, strutils, deques]

import pkg/results

import ../src/moepkg/[buffer, types, config, modes, registers]
import ../src/moepkg/command_handlers/insert_commands

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Insert,
    previousMode: EditorMode.Normal,
    screenCursor: CursorPosition(x: 0, y: 0),
  )
  EditorState(
    activeWindow: window,
    config: newEditorConfig(),
    windowDisplay: WindowDisplayState(viewportReservedLines: 2),
    pendingInput: PendingInputState(
      macroState: MacroState(
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
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

suite "Insert Commands - rebuiltIndent":
  test "a deeper indent gets 'shiftwidth' columns and is rebuilt, as Vim's smartindent":
    # Each row was checked against Vim 9.2 with `vim -u NONE` and `set si`.
    type Case = tuple[sw, ts: int, et: bool, indent, want: string]

    const cases: seq[Case] = @[
      (4, 8, false, "", "    "),
      (4, 8, false, "    ", "\t"),
      (4, 8, false, "\t", "\t    "),
      (4, 8, false, "  \t", "\t    "),
      (4, 8, false, "      ", "\t  "),
      (4, 8, true, "  ", "      "),
      (4, 8, true, "\t", "            "),
      (0, 2, false, "", "\t"),
      (0, 8, true, "", "        "),
      (2, 2, false, "  ", "\t\t"),
    ]
    for c in cases:
      let state = createTestState()
      state.shiftWidth = c.sw
      state.tabStop = c.ts
      state.expandTab = c.et

      checkpoint $c
      check state.rebuiltIndent(c.indent, deeper = true) == c.want

  test "an indent keeps its width and is rebuilt":
    type Case = tuple[ts: int, et: bool, indent, want: string]

    const cases: seq[Case] = @[
      (4, false, "    ", "\t"),
      (8, false, "    ", "    "),
      (4, false, "  \t  ", "\t  "),
      (4, true, "\t", "    "),
      (4, true, "", ""),
    ]
    for c in cases:
      let state = createTestState()
      state.tabStop = c.ts
      state.expandTab = c.et

      checkpoint $c
      check state.rebuiltIndent(c.indent) == c.want

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

suite "Insert Commands - shiftLines with shiftWidth":
  test "Indent uses shiftWidth when set":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.shiftWidth = 4

    check shiftLines(buf, state, 0, 0, left = false).isOk

    check buf.getLine(0) == "    hello"

suite "Insert Commands - raw buffer gates":
  test "shiftLines refuses a raw buffer and says why":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.keepRaw = true
    let state = createTestState()
    state.expandTab = true
    state.shiftWidth = 4

    let res = shiftLines(buf, state, 0, 0, left = false)

    check res.isErr
    check "raw undecodable bytes" in res.error
    check buf.getLine(0) == "hello"

  test "a left shiftLines refuses a raw buffer and says why":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    buf.keepRaw = true
    let state = createTestState()
    state.expandTab = true
    state.shiftWidth = 4

    let res = shiftLines(buf, state, 0, 0, left = true)

    check res.isErr
    check "raw undecodable bytes" in res.error
    check buf.getLine(0) == "    hello"

  test "Ctrl-U in a raw buffer deletes the indent too":
    # Auto-indent is off for raw buffers, so there is no indent to keep.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    foo")
    buf.keepRaw = true
    let state = createTestState()
    state.config.standard.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 7)

    deleteToLineStart(buf, state)

    check buf.getLine(0) == ""

  test "a refused Ctrl-T leaves where typing started":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    buf.keepRaw = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)
    let start = BufferPosition(line: 0, column: 6)
    state.insertStart = InsertStart(at: start, stop: start)

    check changeIndent(buf, state, deeper = true).isErr
    check state.insertStart.at == start

suite "Insert Commands - left shiftLines with shiftWidth":
  test "Dedent uses shiftWidth when set":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.shiftWidth = 4

    check shiftLines(buf, state, 0, 0, left = true).isOk

    check buf.getLine(0) == "hello"

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

  test "Backspace joining lines moves marks by the join column, as Vim does":
    let buf = newTextBuffer("abc\ndefgh")
    buf.namedMarks['a'] = some(BufferPosition(line: 1, column: 1))
    buf.lastVisual = some(
      VisualArea(
        start: BufferPosition(line: 1, column: 0),
        cursor: BufferPosition(line: 1, column: 1),
        kind: vskChar,
      )
    )
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    insertBackspace(buf, state)

    check buf.getLine(0) == "abcdefgh"
    check state.cursor == BufferPosition(line: 0, column: 3)
    check buf.namedMarks['a'] == some(BufferPosition(line: 0, column: 4))
    check buf.lastVisual.get.start == BufferPosition(line: 0, column: 3)
    check buf.lastVisual.get.cursor == BufferPosition(line: 0, column: 4)

  test "Backspace deletes an auto-paired pair, as the Insert key does":
    let buf = newTextBuffer("f()")
    let state = createTestState()
    state.autoDeleteParen = true
    state.cursor = BufferPosition(line: 0, column: 2)

    insertBackspace(buf, state)

    check buf.getLine(0) == "f"
    check state.cursor.column == 1

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

    # The blank carried down gives way to the indent, as in Vim.
    check buf.getLine(0) == "    hello"
    check buf.getLine(1) == "    world"
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

  test "Insert newline on a raw buffer skips auto-indent":
    # Copying the leading whitespace bytes would be an edit the user never
    # typed; the newline itself still splits the line.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    buf.keepRaw = true
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 7)

    insertNewline(buf, state)

    check buf.getLine(0) == "  hello"
    check buf.getLine(1) == ""
    check state.cursor == BufferPosition(line: 1, column: 0)

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

  test "bsmIndent indents the middle line 'shiftwidth' columns deeper, rebuilding the indent":
    let buf = newTextBuffer("    f()")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = false
    state.tabStop = 8
    state.shiftWidth = 4
    state.bracketSplit = bsmIndent
    state.cursor = BufferPosition(line: 0, column: 6)

    insertNewline(buf, state)

    check buf.getLine(0) == "    f("
    check buf.getLine(1) == "\t"
    check buf.getLine(2) == "    )"
    check state.cursor == BufferPosition(line: 1, column: 1)

  test "bsmIndent rebuilds the closing line's indent as the middle line's":
    # The closing line used to copy the indent while the middle line was
    # rebuilt, mixing tabs and spaces between the two.
    type Case = tuple[et: bool, line, middle, close: string]

    const cases: seq[Case] =
      @[(false, "    foo{}", "\t\t", "\t}"), (true, "\tfoo{}", "        ", "    }")]
    for c in cases:
      let buf = newTextBuffer(c.line)
      let state = createTestState()
      state.autoIndent = true
      state.expandTab = c.et
      state.tabStop = 4
      state.shiftWidth = 4
      state.bracketSplit = bsmIndent
      state.cursor = BufferPosition(line: 0, column: c.line.len - 1)

      insertNewline(buf, state)

      checkpoint $c
      check buf.getLine(0) == c.line[0 ..^ 2]
      check buf.getLine(1) == c.middle
      check buf.getLine(2) == c.close
      check state.cursor == BufferPosition(line: 1, column: c.middle.len)

  test "bracket split still fires on a line with an undecodable byte":
    # The bounds check counts columns with the same model the cursor uses, so a
    # lead byte whose advertised length overruns the line does not disable it.
    let buf = newTextBuffer()
    # 0xF0 advertises four bytes but only three remain, so it is one character.
    discard buf.insertText(BufferPosition(line: 0, column: 0), "x\xF0()")
    check buf.getLine(0).charLen == 4
    let state = createTestState()
    state.autoIndent = false
    state.bracketSplit = bsmNoIndent
    state.cursor = BufferPosition(line: 0, column: 3)

    insertNewline(buf, state)

    check buf.len == 3
    check buf.getLine(0) == "x\xF0("
    check buf.getLine(1) == ""
    check buf.getLine(2) == ")"

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

  test "with 'autoindent', the empty middle line bsmNoIndent leaves is auto-indented":
    # As after `o`, so an indent Ctrl-T adds there comes off on Escape.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    test[]")
    let state = createTestState()
    state.autoIndent = true
    state.expandTab = true
    state.tabStop = 4
    state.bracketSplit = bsmNoIndent
    state.cursor = BufferPosition(line: 0, column: 9)

    insertNewline(buf, state)
    check changeIndent(buf, state, deeper = true).isOk
    check buf.getLine(1) == "    "
    clearAutoIndentIfUnedited(buf, state)

    check buf.getLine(1) == ""

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

  test "bsmNoIndent without 'autoindent' does not register for Esc cleanup":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "f()")
    let state = createTestState()
    state.autoIndent = false
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

    check insertLineBelow(buf, state).isOk

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

    check insertLineBelow(buf, state).isOk

    check buf.len >= 2
    check state.cursor.line == 1
    check state.cursor.column == 0
    check state.mode == EditorMode.Insert

  test "Insert line below on a raw buffer skips auto-indent":
    # Copying the leading whitespace bytes would be an edit the user never
    # typed; the newline itself still splits the line.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    buf.keepRaw = true
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    check insertLineBelow(buf, state).isOk

    check buf.getLine(1) == ""
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

    check insertLineAbove(buf, state).isOk

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

    check insertLineAbove(buf, state).isOk

    check buf.len >= 2
    check state.cursor.line == 0
    check state.cursor.column == 0
    check state.mode == EditorMode.Insert

  test "Insert line above on a raw buffer skips auto-indent":
    # Copying the leading whitespace bytes would be an edit the user never
    # typed; the newline itself still splits the line.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    buf.keepRaw = true
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    check insertLineAbove(buf, state).isOk

    check buf.getLine(0) == ""
    check buf.getLine(1) == "  hello"
    check state.cursor.line == 0
    check state.cursor.column == 0
    check state.mode == EditorMode.Insert

suite "Insert Commands - shiftLines":
  test "Indent line with spaces (expandTab)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 3)

    check shiftLines(buf, state, 0, 0, left = false).isOk

    check buf.getLine(0) == "  hello"
    check state.cursor == BufferPosition(line: 0, column: 3)

  test "Indent line with tabs":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = false

    check shiftLines(buf, state, 0, 0, left = false).isOk

    check buf.getLine(0) == "\thello"

  test "Indent line multiple times":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2

    check shiftLines(buf, state, 0, 0, left = false, amount = 2).isOk

    check buf.getLine(0) == "    hello"

  test "Dedent line with spaces":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2

    check shiftLines(buf, state, 0, 0, left = true).isOk

    check buf.getLine(0) == "  hello"

  test "Dedent line with no indentation":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2

    check shiftLines(buf, state, 0, 0, left = true).isOk

    check buf.getLine(0) == "hello"

  test "An empty line stays empty":
    let buf = newTextBuffer()
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2

    check shiftLines(buf, state, 0, 0, left = false).isOk

    check buf.getLine(0) == ""

  test "the indent moves by columns and is rebuilt, as Vim's shift_line":
    # Each row was checked against Vim 9.2 with `vim -u NONE`.
    type Case =
      tuple[sw, ts: int, et: bool, line: string, left: bool, amount: int, want: string]

    const cases: seq[Case] = @[
      (4, 8, false, "x", false, 1, "    x"),
      (4, 8, false, "    x", false, 1, "\tx"),
      (4, 8, false, "\t\t\t\tx", true, 1, "\t\t\t    x"),
      (4, 8, false, "   \t)", false, 1, "\t    )"),
      (8, 8, false, "   \t)", false, 1, "\t\t)"),
      (4, 8, false, "  \tx", true, 1, "    x"),
      (4, 8, false, "\t", false, 1, "\t    "),
      (4, 8, false, "\t", true, 1, "    "),
      (4, 8, false, "    x", true, 1, "x"),
      (4, 8, false, "\t\tx", true, 3, "    x"),
      (4, 8, false, "\ty", true, 3, "y"),
      (4, 4, false, "\t  x", true, 1, "  x"),
      (4, 4, false, "    x", false, 1, "\t\tx"),
      (0, 4, false, "x", false, 1, "\tx"),
      (4, 8, true, "\tx", false, 1, "            x"),
      (4, 8, true, "  ", false, 1, "      "),
      (4, 8, true, "      x", true, 1, "  x"),
      (4, 8, true, "   x", true, 1, "x"),
    ]
    for c in cases:
      let buf = newTextBuffer(c.line)
      let state = createTestState()
      state.shiftWidth = c.sw
      state.tabStop = c.ts
      state.expandTab = c.et

      check shiftLines(buf, state, 0, 0, c.left, c.amount).isOk

      checkpoint $c
      check buf.getLine(0) == c.want

  test "the lines shift as one change that one undo takes back":
    let buf = newTextBuffer("a\n\n  b\nc")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 8
    state.shiftWidth = 4
    let before = buf.undoStack.len

    check shiftLines(buf, state, 0, 3, left = false).isOk

    check buf.undoStack.len == before + 1
    check buf.getLine(0) == "    a"
    check buf.getLine(1) == ""
    check buf.getLine(2) == "      b"
    check buf.getLine(3) == "    c"

    check buf.undo().isOk
    check buf.getLine(0) == "a"
    check buf.getLine(2) == "  b"
    check buf.getLine(3) == "c"

  test "nothing to shift records no change":
    let buf = newTextBuffer("a\n\nb")
    let state = createTestState()
    let before = buf.undoStack.len

    check shiftLines(buf, state, 0, 2, left = true).isOk

    check buf.undoStack.len == before

  test "a line starting with # shifts even with smart indent":
    # Vim's op_shift skips it for C preprocessor lines; in Nim it is a comment.
    let buf = newTextBuffer("# note\nx")
    let state = createTestState()
    state.config.standard.smartIndent = true
    state.expandTab = true
    state.shiftWidth = 2

    check shiftLines(buf, state, 0, 1, left = false).isOk

    check buf.getLine(0) == "  # note"
    check buf.getLine(1) == "  x"

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

    check insertLineBelow(buf, state).isOk

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

    check insertLineBelow(buf, state).isOk

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

    check insertLineAbove(buf, state).isOk

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

    check insertLineBelow(buf, state).isOk

    check state.editState.autoIndentedLine.isNone

  test "No indentation on source line, tracked with nothing to remove":
    # As Vim's did_ai, so an indent Ctrl-T adds there comes off on Escape.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    check insertLineBelow(buf, state).isOk

    check state.editState.autoIndentedLine.isSome
    let version = buf.contentVersion
    clearAutoIndentIfUnedited(buf, state)
    check buf.getLine(1) == ""
    check buf.contentVersion == version

  test "o unedited exit uses replaceLine to remove indent in transaction":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    let state = createTestState()
    state.autoIndent = true
    state.cursor = BufferPosition(line: 0, column: 2)

    # Start transaction (as normal_handler would do for o/O)
    discard buf.beginTransaction("Insert mode edit")
    check insertLineBelow(buf, state).isOk

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
    check insertLineAbove(buf, state).isOk

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
    check insertLineBelow(buf, state).isOk

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
    check insertLineAbove(buf, state).isOk

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
    check insertLineBelow(buf, state).isOk

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
    check insertLineBelow(buf, state).isOk

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
    check insertLineAbove(buf, state).isOk

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
    check insertLineBelow(buf, state).isOk
    discard buf.commitTransaction()

    discard buf.undo()
    check buf.len == 1

    let r = buf.redo()
    check r.isOk
    check buf.len == 2
    # Redo returns the saved cursor position
    check r.value.line == 0
    check r.value.column == 2

suite "Insert Commands - read-only failure keeps cursor and reports":
  test "insertChar on read-only buffer keeps cursor and sets message":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    insertChar(buf, state, 'x')

    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 2)
    check state.statusMessage.len > 0

  test "insertBackspace on read-only buffer keeps cursor (pre-move type)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)

    insertBackspace(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 3)
    check state.statusMessage.len > 0

  test "insertBackspace line-join on read-only buffer keeps lines and cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello\nworld")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    insertBackspace(buf, state)

    check buf.len == 2
    check buf.getLine(0) == "hello"
    check buf.getLine(1) == "world"
    check state.cursor == BufferPosition(line: 1, column: 0)
    check state.statusMessage.len > 0

  test "deleteWordBackward on read-only buffer keeps cursor (pre-move type)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "foo bar")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 7)

    deleteWordBackward(buf, state)

    check buf.getLine(0) == "foo bar"
    check state.cursor == BufferPosition(line: 0, column: 7)
    check state.statusMessage.len > 0

  test "deleteToLineStart on read-only buffer keeps cursor (pre-move type)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 4)

    deleteToLineStart(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 4)
    check state.statusMessage.len > 0

  test "insertNewline on read-only buffer keeps cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.readOnly = true
    let state = createTestState()
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 2)

    insertNewline(buf, state)

    check buf.len == 1
    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 2)
    check state.statusMessage.len > 0

  test "shiftLines on read-only buffer keeps cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    let res = shiftLines(buf, state, 0, 0, left = false)

    check res.isErr
    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 2)

  test "a left shiftLines on read-only buffer keeps cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "    hello")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)

    let res = shiftLines(buf, state, 0, 0, left = true)

    check res.isErr
    check buf.getLine(0) == "    hello"
    check state.cursor == BufferPosition(line: 0, column: 6)

  test "insertCharFromAbove on read-only buffer keeps cursor":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "ab\ncd")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)

    let inserted = insertCharFromAbove(buf, state)

    check not inserted
    check buf.getLine(1) == "cd"
    check state.cursor == BufferPosition(line: 1, column: 0)

  test "insertLineBelow on read-only buffer keeps cursor and mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.readOnly = true
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 2)

    let r = insertLineBelow(buf, state)

    check r.isErr
    check "read-only" in r.error
    check buf.len == 1
    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 2)
    check state.mode == EditorMode.Normal

  test "insertLineAbove on read-only buffer keeps cursor and mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.readOnly = true
    let state = createTestState()
    state.mode = EditorMode.Normal
    state.autoIndent = false
    state.cursor = BufferPosition(line: 0, column: 2)

    let r = insertLineAbove(buf, state)

    check r.isErr
    check "read-only" in r.error
    check buf.len == 1
    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 2)
    check state.mode == EditorMode.Normal

  test "insertDelete at end of line is a silent no-op":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)

    insertDelete(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 5)
    check state.statusMessage.len == 0

  test "insertDelete on read-only buffer reports error":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    buf.readOnly = true
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 2)

    insertDelete(buf, state)

    check buf.getLine(0) == "hello"
    check state.cursor == BufferPosition(line: 0, column: 2)
    check state.statusMessage.len > 0
