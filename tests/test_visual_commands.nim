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

## Tests for visual_commands.nim

import std/[unittest, options, tables, strutils, os, osproc]

import pkg/results

import ../src/moepkg/[buffer, types, modes, registers, config, clipboard]
import ../src/moepkg/command_handlers/visual_commands

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
      active: true,
      kind: vskChar,
    ),
  )

proc isToolAvailable(cmd: string): bool =
  try:
    let (_, exitCode) = execCmdEx("which " & cmd)
    result = exitCode == 0
  except CatchableError:
    result = false

proc getAvailableClipboardTool(): (bool, ClipboardTool) =
  if existsEnv("WAYLAND_DISPLAY") and isToolAvailable("wl-copy"):
    return (true, cbtWlClipboard)
  elif existsEnv("DISPLAY") and isToolAvailable("xsel"):
    return (true, cbtXsel)
  elif existsEnv("DISPLAY") and isToolAvailable("xclip"):
    return (true, cbtXclip)
  return (false, cbtXsel)

proc readClipboardWithRetry(
    tool: ClipboardTool, expected: string, maxRetries: int = 10, delayMs: int = 100
): Result[string, string] =
  ## Retry reading CLIPBOARD until the write is visible (may lag in CI).
  for i in 0 ..< maxRetries:
    result = readFromClipboardSync(tool)
    if result.isOk and result.get() == expected:
      return
    sleep(delayMs)
  return readFromClipboardSync(tool)

proc cleanupClipboardProcs(tool: ClipboardTool) =
  ## Kill lingering async clipboard-writer children spawned by this test proc.
  let pid = getCurrentProcessId()
  case tool
  of cbtXsel:
    discard execCmdEx("pkill -P " & $pid & " xsel")
  of cbtXclip:
    discard execCmdEx("pkill -P " & $pid & " xclip")
  else:
    discard
  sleep(100)

suite "Visual Commands - getSelectionRange":
  test "Get selection range when start equals current":
    let selection = VisualSelection(
      start: BufferPosition(line: 0, column: 5),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskChar,
    )
    let (selStart, selEnd) = selection.getSelectionRange()
    check selStart.line == 0
    check selStart.column == 5
    check selEnd.line == 0
    check selEnd.column == 5

  test "Get selection range when start is before current (same line)":
    let selection = VisualSelection(
      start: BufferPosition(line: 0, column: 2),
      current: BufferPosition(line: 0, column: 8),
      active: true,
      kind: vskChar,
    )
    let (selStart, selEnd) = selection.getSelectionRange()
    check selStart.line == 0
    check selStart.column == 2
    check selEnd.line == 0
    check selEnd.column == 8

  test "Get selection range when start is after current (same line)":
    let selection = VisualSelection(
      start: BufferPosition(line: 0, column: 8),
      current: BufferPosition(line: 0, column: 2),
      active: true,
      kind: vskChar,
    )
    let (selStart, selEnd) = selection.getSelectionRange()
    check selStart.line == 0
    check selStart.column == 2
    check selEnd.line == 0
    check selEnd.column == 8

  test "Get selection range when start is on earlier line":
    let selection = VisualSelection(
      start: BufferPosition(line: 1, column: 5),
      current: BufferPosition(line: 3, column: 2),
      active: true,
      kind: vskChar,
    )
    let (selStart, selEnd) = selection.getSelectionRange()
    check selStart.line == 1
    check selStart.column == 5
    check selEnd.line == 3
    check selEnd.column == 2

  test "Get selection range when start is on later line":
    let selection = VisualSelection(
      start: BufferPosition(line: 3, column: 2),
      current: BufferPosition(line: 1, column: 5),
      active: true,
      kind: vskChar,
    )
    let (selStart, selEnd) = selection.getSelectionRange()
    check selStart.line == 1
    check selStart.column == 5
    check selEnd.line == 3
    check selEnd.column == 2

  test "Get selection range when selection is not active":
    let selection = VisualSelection(
      start: BufferPosition(line: 0, column: 5),
      current: BufferPosition(line: 2, column: 10),
      active: false,
      kind: vskChar,
    )
    let (selStart, selEnd) = selection.getSelectionRange()
    check selStart.line == 0
    check selStart.column == 5
    check selEnd.line == 0
    check selEnd.column == 5

suite "Visual Commands - visualMoveLeft":
  test "Move left from middle of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)
    state.visualSelection.current = state.cursor

    visualMoveLeft(buf, state)

    check state.cursor.column == 4
    check state.visualSelection.current.column == 4

  test "Move left from beginning of line (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveLeft(buf, state)

    check state.cursor.column == 0
    check state.visualSelection.current.column == 0

suite "Visual Commands - visualMoveRight":
  test "Move right from middle of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)
    state.visualSelection.current = state.cursor

    visualMoveRight(buf, state)

    check state.cursor.column == 6
    check state.visualSelection.current.column == 6

  test "Move right at end of line (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 11)
    state.visualSelection.current = state.cursor

    visualMoveRight(buf, state)

    check state.cursor.column == 11

suite "Visual Commands - visualMoveUp":
  test "Move up from second line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 3)
    state.visualSelection.current = state.cursor

    visualMoveUp(buf, state)

    check state.cursor.line == 0
    check state.visualSelection.current.line == 0

  test "Move up from first line (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)
    state.visualSelection.current = state.cursor

    visualMoveUp(buf, state)

    check state.cursor.line == 0

  test "Move up clamps cursor to new line length":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "short")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nlonger line")
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 10)
    state.visualSelection.current = state.cursor

    visualMoveUp(buf, state)

    check state.cursor.line == 0
    check state.cursor.column == 5 # clamped to "short" length

suite "Visual Commands - visualMoveDown":
  test "Move down from first line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)
    state.visualSelection.current = state.cursor

    visualMoveDown(buf, state)

    check state.cursor.line == 1
    check state.visualSelection.current.line == 1

  test "Move down from last line (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)
    state.visualSelection.current = state.cursor

    visualMoveDown(buf, state)

    check state.cursor.line == 0

  test "Move down clamps cursor to new line length":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "longer line")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nshort")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 10)
    state.visualSelection.current = state.cursor

    visualMoveDown(buf, state)

    check state.cursor.line == 1
    check state.cursor.column == 5 # clamped to "short" length

suite "Visual Commands - visualYank":
  test "Yank character selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 6)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualYank(buf, state)

    check state.registers.getNoNamedRegister().getContent() == "hello"
    check state.registers.getNoNamedRegister().isLine == false
    check state.visualSelection.active == false
    check state.cursor.column == 0 # cursor moves to start of selection
    check state.mode == EditorMode.Normal

  test "Yank line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 3),
      active: true,
      kind: vskLine,
    )

    visualYank(buf, state)

    check state.registers.getNoNamedRegister().getContent() == "line 1\nline 2"
    check state.registers.getNoNamedRegister().isLine == true
    check state.visualSelection.active == false

  test "Yank to named register":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    state.pendingInput.pendingRegister = some('a')

    visualYank(buf, state)

    check state.registers.getRegisterContent('a') == "hello"
    check state.pendingInput.pendingRegister.isNone

  test "Yank multiline clamps cursor column to line length":
    # When selection starts on a long line and extends downward to a shorter line,
    # cursor should be clamped to the start line's last character
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "short")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nthis is a long line")
    let state = createTestState()
    # Start selection at column 18 on short line (line 0), extend to long line (line 1)
    # This simulates: cursor on line 0 col 18 (past end), select down to line 1
    state.cursor = BufferPosition(line: 1, column: 18)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 18),
      current: BufferPosition(line: 1, column: 18),
      active: true,
      kind: vskChar,
    )

    visualYank(buf, state)

    check state.cursor.line == 0
    check state.cursor.column == 4 # "short" has 5 chars, last valid column is 4

  test "Yank multiline clamps cursor column on empty line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "")
    discard buf.insertText(BufferPosition(line: 0, column: 0), "\nsome text")
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 5)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 1, column: 5),
      current: BufferPosition(line: 0, column: 0),
      active: true,
      kind: vskChar,
    )

    visualYank(buf, state)

    check state.cursor.line == 0
    check state.cursor.column == 0

suite "Visual Commands - visualDelete":
  test "Delete character selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualDelete(buf, state)

    check buf.getLine(0) == " world"
    check state.registers.getNoNamedRegister().getContent() == "hello"
    check state.visualSelection.active == false
    check state.cursor.column == 0
    check state.mode == EditorMode.Normal

  test "Delete line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 3),
      active: true,
      kind: vskLine,
    )

    visualDelete(buf, state)

    check buf.len == 1
    check buf.getLine(0) == "line 3"
    check state.registers.getNoNamedRegister().isLine == true

  test "Delete inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection.active = false

    visualDelete(buf, state)

    check buf.getLine(0) == "hello world"

  test "Delete selection extending to column == lineLen removes line":
    # v l...l (to column == lineLen) + d should delete the entire line
    # including the newline, joining with the next line.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection = VisualSelection(
      start: state.cursor, current: state.cursor, active: true, kind: vskChar
    )

    for _ in 1 .. 5:
      visualMoveRight(buf, state)
    check state.cursor.column == 5 # == lineLen

    visualDelete(buf, state)

    check buf.len == 1
    check buf.getLine(0) == "world"

  test "v$d deletes the entire line including the newline":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection = VisualSelection(
      start: state.cursor, current: state.cursor, active: true, kind: vskChar
    )

    visualMoveEnd(buf, state)
    check state.cursor.column == 5 # == lineLen

    visualDelete(buf, state)

    check buf.len == 1
    check buf.getLine(0) == "world"

  test "Delete characterwise multiline selection stores as charwise register":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "abc")
    discard buf.insertText(BufferPosition(line: 0, column: 3), "\nde")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 1),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskChar,
    )

    visualDelete(buf, state)

    check state.registers.getNoNamedRegister().getContent() == "bc\nde\n"
    check state.registers.getNoNamedRegister().isLine == false

suite "Visual Commands - visualIndent":
  test "Indent single line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualIndent(buf, state)

    check buf.getLine(0) == "  hello"
    check state.visualSelection.active == false
    check state.mode == EditorMode.Normal

  test "Indent multiple line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 2, column: 3),
      active: true,
      kind: vskChar,
    )

    visualIndent(buf, state)

    check buf.getLine(0) == "  line 1"
    check buf.getLine(1) == "  line 2"
    check buf.getLine(2) == "  line 3"

  test "Indent with count":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualIndent(buf, state, 3)

    check buf.getLine(0) == "      hello"

suite "Visual Commands - visualDedent":
  test "Dedent single line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.cursor = BufferPosition(line: 0, column: 2)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 6),
      active: true,
      kind: vskChar,
    )

    visualDedent(buf, state)

    check buf.getLine(0) == "hello"
    check state.visualSelection.active == false

  test "Dedent line with no indentation (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.expandTab = true
    state.tabStop = 2
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualDedent(buf, state)

    check buf.getLine(0) == "hello"

suite "Visual Commands - visualLowercase":
  test "Convert selection to lowercase":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "HELLO World")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualLowercase(buf, state)

    check buf.getLine(0) == "hello World"
    check state.visualSelection.active == false
    check state.mode == EditorMode.Normal

  test "Lowercase line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "HELLO")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nWORLD")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 4),
      active: true,
      kind: vskLine,
    )

    visualLowercase(buf, state)

    check buf.getLine(0) == "hello"
    check buf.getLine(1) == "world"

suite "Visual Commands - visualUppercase":
  test "Convert selection to uppercase":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualUppercase(buf, state)

    check buf.getLine(0) == "HELLO world"
    check state.visualSelection.active == false

  test "Uppercase line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 4),
      active: true,
      kind: vskLine,
    )

    visualUppercase(buf, state)

    check buf.getLine(0) == "HELLO"
    check buf.getLine(1) == "WORLD"

suite "Visual Commands - visualToggleCase":
  test "Toggle case of selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "HeLLo WoRLd")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualToggleCase(buf, state)

    check buf.getLine(0) == "hEllO WoRLd"
    check state.visualSelection.active == false

  test "Toggle case preserves non-alphabetic characters":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello123World")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 12),
      active: true,
      kind: vskChar,
    )

    visualToggleCase(buf, state)

    check buf.getLine(0) == "hELLO123wORLD"

suite "Visual Commands - visualReplace":
  test "Replace selection with character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualReplace(buf, state, 'x')

    check buf.getLine(0) == "xxxxx world"
    check state.visualSelection.active == false

  test "Replace preserves newlines in character selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 4),
      active: true,
      kind: vskChar,
    )

    visualReplace(buf, state, 'x')

    check buf.getLine(0) == "xxxxx"
    check buf.getLine(1) == "xxxxx"

  test "Replace block selection with multibyte content":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "あいう world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualReplace(buf, state, 'x')

    # Should replace 3 characters, not 9 bytes worth
    check buf.getLine(0) == "xxx world"

suite "Visual Commands - visualJoinLines":
  test "Join two lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 4),
      active: true,
      kind: vskChar,
    )

    visualJoinLines(buf, state)

    check buf.len == 1
    check state.visualSelection.active == false
    check state.statusMessage == "1 lines joined"

  test "Join single line selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualJoinLines(buf, state)

    check buf.len == 1
    check buf.getLine(0) == "hello world"
    check state.visualSelection.active == false

  test "Join multiple lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 2, column: 3),
      active: true,
      kind: vskChar,
    )

    visualJoinLines(buf, state)

    check buf.len == 1
    check state.statusMessage == "2 lines joined"

suite "Visual Commands - visualMoveHome":
  test "Move to beginning of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5)
    state.visualSelection.current = state.cursor

    visualMoveHome(buf, state)

    check state.cursor.column == 0
    check state.visualSelection.current.column == 0

suite "Visual Commands - visualMoveEnd":
  test "Move to end of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveEnd(buf, state)

    # In Visual mode, cursor can go to column == lineLen (one past last char)
    # so that the selection includes the newline.
    check state.cursor.column == 11

  test "Move to end of empty line":
    let buf = newTextBuffer()
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveEnd(buf, state)

    check state.cursor.column == 0

suite "Visual Commands - visualMoveFirstNonBlank":
  test "Move to first non-blank character":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "   hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 10)
    state.visualSelection.current = state.cursor

    visualMoveFirstNonBlank(buf, state)

    check state.cursor.column == 3

suite "Visual Commands - visualMoveFirstLine":
  test "Move to first line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.cursor = BufferPosition(line: 2, column: 3)
    state.visualSelection.current = state.cursor

    visualMoveFirstLine(buf, state)

    check state.cursor.line == 0
    check state.cursor.column == 0
    check state.visualSelection.current.line == 0

suite "Visual Commands - visualMoveLastLine":
  test "Move to last line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 3)
    state.visualSelection.current = state.cursor

    visualMoveLastLine(buf, state)

    check state.cursor.line == 2
    check state.visualSelection.current.line == 2

  test "Move to specific line number":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveLastLine(buf, state, 2) # Go to line 2 (1-indexed)

    check state.cursor.line == 1

suite "Visual Commands - visualMoveWord":
  test "Move to next word":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world test")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveWord(buf, state)

    check state.cursor.column == 6 # start of "world"
    check state.visualSelection.current.column == 6

  test "Move word with count":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world test foo")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveWord(buf, state, 2)

    check state.cursor.column == 12 # start of "test"

suite "Visual Commands - visualMoveWordBack":
  test "Move to previous word":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world test")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 12)
    state.visualSelection.current = state.cursor

    visualMoveWordBack(buf, state)

    check state.cursor.column == 6 # start of "world"

suite "Visual Commands - visualMoveWordEnd":
  test "Move to end of word":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world test")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveWordEnd(buf, state)

    check state.cursor.column == 4 # end of "hello"

suite "Visual Commands - visualMoveParagraphForward":
  test "Move to next paragraph":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "paragraph 1")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\n")
    discard buf.insertText(BufferPosition(line: 1, column: 0), "\nparagraph 2")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveParagraphForward(buf, state)

    check state.cursor.line >= 1

suite "Visual Commands - visualMoveParagraphBackward":
  test "Move to previous paragraph":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "paragraph 1")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\n")
    discard buf.insertText(BufferPosition(line: 1, column: 0), "\nparagraph 2")
    let state = createTestState()
    state.cursor = BufferPosition(line: 2, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveParagraphBackward(buf, state)

    check state.cursor.line <= 1

suite "Visual Commands - visualToInsertMode":
  test "Switch from visual to insert mode":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 2),
      current: BufferPosition(line: 1, column: 3),
      active: true,
      kind: vskChar,
    )

    visualToInsertMode(buf, state)

    check state.mode == EditorMode.Insert
    check state.cursor.line == 0
    check state.cursor.column == 0
    check state.visualSelection.active == false

suite "Visual Commands - visualChange":
  test "Change character selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualChange(buf, state)

    check buf.getLine(0) == " world"
    check state.mode == EditorMode.Insert
    check state.visualSelection.active == false

  test "Change line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 3),
      active: true,
      kind: vskLine,
    )

    visualChange(buf, state)

    check buf.len == 2 # empty line + line 3
    check state.mode == EditorMode.Insert

suite "Visual Commands - visualSwapSelection":
  test "Swap selection endpoints":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 8)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 2),
      current: BufferPosition(line: 0, column: 8),
      active: true,
      kind: vskChar,
    )

    visualSwapSelection(buf, state)

    check state.visualSelection.start == BufferPosition(line: 0, column: 8)
    check state.visualSelection.current == BufferPosition(line: 0, column: 2)
    check state.cursor == BufferPosition(line: 0, column: 2)

  test "Swap inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection.active = false
    state.visualSelection.start = BufferPosition(line: 0, column: 2)
    state.visualSelection.current = BufferPosition(line: 0, column: 8)

    visualSwapSelection(buf, state)

    # Should not change anything since not active
    check state.visualSelection.start == BufferPosition(line: 0, column: 2)
    check state.visualSelection.current == BufferPosition(line: 0, column: 8)

suite "Visual Commands - visualPaste":
  test "Paste replaces character selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.registers.setYankedRegister("REPLACED", false)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualPaste(buf, state)

    check buf.getLine(0) == "REPLACED world"
    check state.visualSelection.active == false
    check state.mode == EditorMode.Normal

  test "Paste with empty register (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    # Don't set any register content
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualPaste(buf, state)

    check buf.getLine(0) == "hello world" # unchanged
    check state.visualSelection.active == false

  test "Paste from named register":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    discard state.registers.setNamedRegister('a', "NAMED", false)
    state.pendingInput.pendingRegister = some('a')
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualPaste(buf, state)

    check buf.getLine(0) == "NAMED world"
    check state.pendingInput.pendingRegister.isNone

  test "Paste block selection from named register preserves register content":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    discard buf.insertText(BufferPosition(line: 1, column: 7), "\ntest line")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    discard state.registers.setNamedRegister('a', "REG_A_CONTENT", false)
    state.pendingInput.pendingRegister = some('a')
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 2, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualPaste(buf, state)

    # Bug: deleteBlockSelection must NOT overwrite named register 'a'
    # with the deleted block text.
    check state.registers.getNamedRegister('a').getContent() == "REG_A_CONTENT"
    check state.pendingInput.pendingRegister.isNone
    check state.visualSelection.active == false

  test "V-mode paste of linewise empty register replaces line with blank line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1\nline2\nline3")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    # Linewise register holding a single empty line (Vim's dd on a blank line
    # or yy on an empty line produces this).
    state.registers.setYankedRegister("", true)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 1, column: 0),
      current: BufferPosition(line: 1, column: 5),
      active: true,
      kind: vskLine,
    )

    visualPaste(buf, state)

    check buf.getLine(0) == "line1"
    check buf.getLine(1) == ""
    check buf.getLine(2) == "line3"
    check state.visualSelection.active == false

  test "Charwise paste of linewise empty register is a no-op":
    # Non-line visual selections keep the pre-fix no-op behavior for empty
    # linewise registers — Vim's semantics there are gnarly and out of scope.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.registers.setYankedRegister("", true)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualPaste(buf, state)

    check buf.getLine(0) == "hello world" # unchanged
    check state.visualSelection.active == false

  test "visualPaste falls back to system clipboard when register empty":
    let (available, tool) = getAvailableClipboardTool()
    if not available:
      skip()
    else:
      let buf = newTextBuffer()
      discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
      let state = createTestState()
      # No register set — unnamed register is empty.

      let testText = "FROM_CLIPBOARD"
      check writeToClipboardSync(tool, testText).isOk
      let ready = readClipboardWithRetry(tool, testText)
      check ready.isOk and ready.get() == testText

      state.visualSelection = VisualSelection(
        start: BufferPosition(line: 0, column: 0),
        current: BufferPosition(line: 0, column: 4),
        active: true,
        kind: vskChar,
      )

      let cfg = ClipboardConfig(enable: true, tool: tool)
      visualPaste(buf, state, cfg)

      check buf.getLine(0) == "FROM_CLIPBOARD world"
      check state.visualSelection.active == false

      cleanupClipboardProcs(tool)

suite "Visual Commands - Block Selection":
  test "Delete block selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    discard buf.insertText(BufferPosition(line: 1, column: 7), "\ntest line")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 2, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualDelete(buf, state)

    check buf.getLine(0) == "lo world"
    check buf.getLine(1) == " bar"
    check buf.getLine(2) == "t line"
    check state.visualSelection.active == false

  test "Yank block selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualYank(buf, state)

    check state.registers.getNoNamedRegister().getContent() == "hel\nwor"
    check state.visualSelection.active == false

  test "Lowercase block selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "HELLO WORLD")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nFOO BAR")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualLowercase(buf, state)

    # Block selection columns 0-2 (inclusive) = 3 characters
    check buf.getLine(0) == "helLO WORLD"
    check buf.getLine(1) == "foo BAR"

  test "Uppercase block selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualUppercase(buf, state)

    # Block selection columns 0-2 (inclusive) = 3 characters
    check buf.getLine(0) == "HELlo world"
    check buf.getLine(1) == "FOO bar"

  test "Toggle case block selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "HeLLo world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nFoO bar")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualToggleCase(buf, state)

    # Block selection columns 0-2 (inclusive) = 3 characters
    # "HeL" -> "hEl", "FoO" -> "fOo"
    check buf.getLine(0) == "hElLo world"
    check buf.getLine(1) == "fOo bar"

  test "Replace block selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualReplace(buf, state, 'x')

    # Block selection columns 0-2 (inclusive) = 3 characters
    check buf.getLine(0) == "xxxlo world"
    check buf.getLine(1) == "xxx bar"

  test "Replace line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskLine,
    )

    visualReplace(buf, state, 'x')

    check buf.getLine(0) == "xxxxx"
    check buf.getLine(1) == "xxxxx"

  test "Paste line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    discard buf.insertText(BufferPosition(line: 1, column: 6), "\nline 3")
    let state = createTestState()
    state.registers.setYankedRegister("REPLACED", false)
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 3),
      active: true,
      kind: vskLine,
    )

    visualPaste(buf, state)

    check buf.len == 2
    check buf.getLine(0) == "REPLACED"
    check buf.getLine(1) == "line 3"

  test "Paste linewise content into line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "old line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 10), "\nold line 2")
    discard buf.insertText(BufferPosition(line: 1, column: 10), "\nold line 3")
    let state = createTestState()
    state.registers.setYankedRegister("new line A\nnew line B", true)
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskLine,
    )

    visualPaste(buf, state)

    check buf.len == 4
    check buf.getLine(0) == "new line A"
    check buf.getLine(1) == "new line B"

  test "Paste linewise content normalizes CRLF to LF":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "old line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 10), "\nold line 2")
    let state = createTestState()
    state.registers.setYankedRegister("new line A\r\nnew line B", true)
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskLine,
    )

    visualPaste(buf, state)

    check buf.len == 3
    check buf.getLine(0) == "new line A"
    check buf.getLine(1) == "new line B"
    check buf.getLine(2) == "old line 2"
    # No raw CR should leak into line content.
    check '\r' notin buf.getLine(0)
    check '\r' notin buf.getLine(1)

  test "Paste linewise content with trailing newline does not insert blank line":
    # Regression: real yy stores linewise content with a trailing \n.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "old line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 10), "\nold line 2")
    discard buf.insertText(BufferPosition(line: 1, column: 10), "\nold line 3")
    let state = createTestState()
    state.registers.setYankedRegister("new line A\nnew line B\n", true)
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskLine,
    )

    visualPaste(buf, state)

    check buf.len == 4
    check buf.getLine(0) == "new line A"
    check buf.getLine(1) == "new line B"
    check buf.getLine(2) == "old line 2"
    check buf.getLine(3) == "old line 3"

  test "Paste single-line linewise register over line selection":
    # Regression: single-line yy stores "foo\n".
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "old line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 10), "\nold line 2")
    let state = createTestState()
    state.registers.setYankedRegister("foo\n", true)
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskLine,
    )

    visualPaste(buf, state)

    check buf.len == 2
    check buf.getLine(0) == "foo"
    check buf.getLine(1) == "old line 2"

  test "Paste charwise multi-line content over line selection splits into lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "old line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 10), "\nold line 2")
    let state = createTestState()
    # Charwise register (isLine = false) whose content still spans lines.
    state.registers.setYankedRegister("frag A\nfrag B", false)
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskLine,
    )

    visualPaste(buf, state)

    check buf.len == 3
    check buf.getLine(0) == "frag A"
    check buf.getLine(1) == "frag B"
    check buf.getLine(2) == "old line 2"
    # No raw \n should be stored inside a single line.
    check '\n' notin buf.getLine(0)
    check '\n' notin buf.getLine(1)

  # Regression: substr(startCol, endCol - startCol + 1) passed length as end
  # index to substr (which expects last index), producing empty string when
  # startCol > 0. Also used byte offsets for rune-based column indices.
  test "Yank block selection from non-zero start column (substr regression)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar baz")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 4),
      current: BufferPosition(line: 1, column: 6),
      active: true,
      kind: vskBlock,
    )

    visualYank(buf, state)

    # Old code: substr(4, 6-4+1) = substr(4, 3) → first>last → ""
    # Correct: 3 runes from col 4 → "o w" and "bar"
    check state.registers.getNoNamedRegister().getContent() == "o w\nbar"

  test "Yank block selection with multibyte characters (rune offset regression)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "abcあいうdef")
    discard buf.insertText(BufferPosition(line: 0, column: 9), "\nghiかきくjkl")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 3),
      current: BufferPosition(line: 1, column: 5),
      active: true,
      kind: vskBlock,
    )

    visualYank(buf, state)

    # Old code: substr(3, 3) → byte at index 3 (first byte of 3-byte UTF-8 char)
    # Correct: 3 runes from col 3 → "あいう" and "かきく"
    check state.registers.getNoNamedRegister().getContent() == "あいう\nかきく"

  test "Delete block selection from non-zero start column (substr regression)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 2),
      current: BufferPosition(line: 1, column: 4),
      active: true,
      kind: vskBlock,
    )

    visualDelete(buf, state)

    # Deletes columns 2-4 (inclusive) → 3 chars per line
    # "hello world": delete 'l','l','o' → "he world"
    # "foo bar":     delete 'o',' ','b' → "foar"
    check buf.getLine(0) == "he world"
    check buf.getLine(1) == "foar"

  test "Lowercase block selection from non-zero start column (substr regression)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "HELLO WORLD")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nFOO BAR")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 4),
      current: BufferPosition(line: 1, column: 6),
      active: true,
      kind: vskBlock,
    )

    visualLowercase(buf, state)

    # Lowercase columns 4-6 → "O W" → "o w" and "BAR" → "bar"
    check buf.getLine(0) == "HELLo wORLD"
    check buf.getLine(1) == "FOO bar"

  test "Uppercase block selection from non-zero start column (substr regression)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 4),
      current: BufferPosition(line: 1, column: 6),
      active: true,
      kind: vskBlock,
    )

    visualUppercase(buf, state)

    # Uppercase columns 4-6 → "o w" → "O W" and "bar" → "BAR"
    check buf.getLine(0) == "hellO World"
    check buf.getLine(1) == "foo BAR"

suite "Visual Commands - Edge Cases":
  test "Yank with inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection.active = false
    state.registers.setYankedRegister("", false)

    visualYank(buf, state)

    check state.registers.getNoNamedRegister().getContent() == ""

  test "Indent inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.visualSelection.active = false

    visualIndent(buf, state)

    check buf.getLine(0) == "hello"

  test "Dedent inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "  hello")
    let state = createTestState()
    state.visualSelection.active = false

    visualDedent(buf, state)

    check buf.getLine(0) == "  hello"

  test "Lowercase inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "HELLO")
    let state = createTestState()
    state.visualSelection.active = false

    visualLowercase(buf, state)

    check buf.getLine(0) == "HELLO"

  test "Uppercase inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.visualSelection.active = false

    visualUppercase(buf, state)

    check buf.getLine(0) == "hello"

  test "Toggle case inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "HeLLo")
    let state = createTestState()
    state.visualSelection.active = false

    visualToggleCase(buf, state)

    check buf.getLine(0) == "HeLLo"

  test "Replace inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.visualSelection.active = false

    visualReplace(buf, state, 'x')

    check buf.getLine(0) == "hello"

  test "Change inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.mode = EditorMode.Visual
    state.visualSelection.active = false

    visualChange(buf, state)

    check buf.getLine(0) == "hello"
    check state.mode == EditorMode.Visual

  test "Paste inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.registers.setYankedRegister("REPLACED", false)
    state.visualSelection.active = false

    visualPaste(buf, state)

    check buf.getLine(0) == "hello"

  test "Delete all lines leaves empty buffer":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "only line")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 5),
      active: true,
      kind: vskLine,
    )

    visualDelete(buf, state)

    check buf.len == 1
    check buf.getLine(0) == ""

  test "Block selection with line shorter than start column":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhi")
    discard buf.insertText(BufferPosition(line: 1, column: 2), "\ntest line")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 5),
      current: BufferPosition(line: 2, column: 8),
      active: true,
      kind: vskBlock,
    )

    visualYank(buf, state)

    # Second line "hi" is shorter than column 5, so it contributes empty string.
    # Old bug: substr(5, 4) with first>last also produced "" for lines 0 and 2.
    let lines = state.registers.getNoNamedRegister().getContent().split('\n')
    check lines.len == 3
    check lines[0] == " wor"
    check lines[1] == ""
    check lines[2] == "line"

  test "visualMoveRight at exact line length":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 5) # At end
    state.visualSelection.current = state.cursor

    visualMoveRight(buf, state)

    check state.cursor.column == 5 # Should not move past end

  test "visualMoveDown at buffer end":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "only line")
    let state = createTestState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.visualSelection.current = state.cursor

    visualMoveDown(buf, state)

    check state.cursor.line == 0 # Should stay on same line

  test "Join lines with inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line 1")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nline 2")
    let state = createTestState()
    state.visualSelection.active = false

    visualJoinLines(buf, state)

    check buf.len == 2

suite "Visual Commands - Unicode support":
  test "Lowercase line selection with multibyte characters":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "ABCあいう")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nDEFかきく")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 5),
      active: true,
      kind: vskLine,
    )

    visualLowercase(buf, state)

    check buf.getLine(0) == "abcあいう"
    check buf.getLine(1) == "defかきく"

  test "Uppercase line selection with multibyte characters":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "abcあいう")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\ndefかきく")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 5),
      active: true,
      kind: vskLine,
    )

    visualUppercase(buf, state)

    check buf.getLine(0) == "ABCあいう"
    check buf.getLine(1) == "DEFかきく"

  test "Toggle case line selection with multibyte characters":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "AbCあいう")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nDeFかきく")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 5),
      active: true,
      kind: vskLine,
    )

    visualToggleCase(buf, state)

    check buf.getLine(0) == "aBcあいう"
    check buf.getLine(1) == "dEfかきく"

  test "Replace line selection with multibyte characters":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "ABCあいう")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nDEFかきく")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 5),
      active: true,
      kind: vskLine,
    )

    visualReplace(buf, state, 'x')

    check buf.getLine(0) == "xxxxxx"
    check buf.getLine(1) == "xxxxxx"

suite "Visual Commands - Cursor clamping after delete":
  test "Delete at end of line clamps cursor column":
    # Select the last characters of a line and delete
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 3),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )
    state.cursor = BufferPosition(line: 0, column: 4)

    visualDelete(buf, state)

    check buf.getLine(0) == "hel"
    # Cursor must be clamped: charLen=3, max valid col=2
    check state.cursor.column <= 2
    check state.cursor.line == 0

  test "Delete entire line content clamps cursor to column 0":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "abc")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 2),
      active: true,
      kind: vskChar,
    )
    state.cursor = BufferPosition(line: 0, column: 2)

    visualDelete(buf, state)

    # Line should be empty or buffer has minimal content
    check state.cursor.column == 0

  test "Delete all lines clamps cursor line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nline2")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 4),
      active: true,
      kind: vskLine,
    )
    state.cursor = BufferPosition(line: 1, column: 4)

    visualDelete(buf, state)

    check buf.len >= 1
    check state.cursor.line < buf.len

  test "Block delete clamps cursor when column exceeds line length":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "abcdef")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "\nab")
    discard buf.insertText(BufferPosition(line: 1, column: 2), "\nabcdef")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 3),
      current: BufferPosition(line: 2, column: 5),
      active: true,
      kind: vskBlock,
    )
    state.cursor = BufferPosition(line: 0, column: 3)

    visualDelete(buf, state)

    # Cursor column must be valid for the current line
    let line = buf.getLine(state.cursor.line)
    if line.charLen > 0:
      check state.cursor.column < line.charLen
    else:
      check state.cursor.column == 0

suite "Visual Commands - visualSurround":
  test "Surround char selection with parentheses":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '(')

    check buf.getLine(0) == "(hello) world"
    check state.visualSelection.active == false
    check state.cursor == BufferPosition(line: 0, column: 0)

  test "Surround char selection with close bracket":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, ')')

    check buf.getLine(0) == "(hello) world"

  test "Surround char selection with square brackets":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '[')

    check buf.getLine(0) == "[hello] world"

  test "Surround char selection with curly braces":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '{')

    check buf.getLine(0) == "{hello} world"

  test "Surround char selection with angle brackets":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '<')

    check buf.getLine(0) == "<hello> world"

  test "Surround char selection with double quotes":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '"')

    check buf.getLine(0) == "\"hello\" world"

  test "Surround char selection with single quotes":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '\'')

    check buf.getLine(0) == "'hello' world"

  test "Surround char selection with backticks":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '`')

    check buf.getLine(0) == "`hello` world"

  test "Surround line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskLine,
    )

    visualSurround(buf, state, '(')

    check buf.getLine(0) == "(hello)"
    check buf.getLine(1) == "(world)"
    check state.visualSelection.active == false

  test "Surround block selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualSurround(buf, state, '[')

    check buf.getLine(0) == "[hel]lo world"
    check buf.getLine(1) == "[foo] bar"

  test "Surround inactive selection (no-op)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.visualSelection.active = false

    visualSurround(buf, state, '(')

    check buf.getLine(0) == "hello"

  test "Surround middle of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world foo")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 6),
      current: BufferPosition(line: 0, column: 10),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '"')

    check buf.getLine(0) == "hello \"world\" foo"
    check state.cursor == BufferPosition(line: 0, column: 6)

  test "Surround char selection spanning multiple lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nworld")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 2),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '(')

    check buf.getLine(0) == "he(llo"
    check buf.getLine(1) == "wor)ld"
    check state.cursor == BufferPosition(line: 0, column: 2)

  test "Surround block selection with short line":
    # Second line is shorter than the block selection columns
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nhi")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 4),
      active: true,
      kind: vskBlock,
    )

    visualSurround(buf, state, '{')

    # Line 0: columns 0-4 surrounded
    check buf.getLine(0) == "{hello} world"
    # Line 1: only 2 chars (0-1), so actualEndCol=1
    check buf.getLine(1) == "{hi}"

  test "Surround line selection with multibyte characters":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "あいう")
    discard buf.insertText(BufferPosition(line: 0, column: 3), "\nかきく")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskLine,
    )

    visualSurround(buf, state, '[')

    check buf.getLine(0) == "[あいう]"
    check buf.getLine(1) == "[かきく]"

  test "Surround char selection at end of line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    let state = createTestState()
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '(')

    check buf.getLine(0) == "(hello)"

  test "Surround empty line in line selection":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\n")
    discard buf.insertText(BufferPosition(line: 1, column: 0), "\nworld")
    let state = createTestState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 2, column: 2),
      active: true,
      kind: vskLine,
    )

    visualSurround(buf, state, '(')

    check buf.getLine(0) == "(hello)"
    check buf.getLine(1) == "()"
    check buf.getLine(2) == "(world)"

  test "Surround with reverse selection (current before start)":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    let state = createTestState()
    # current (col 2) is before start (col 8) — reverse direction
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 8),
      current: BufferPosition(line: 0, column: 2),
      active: true,
      kind: vskChar,
    )

    visualSurround(buf, state, '(')

    check buf.getLine(0) == "he(llo wor)ld"
    # cursor should be at normalized start (column 2)
    check state.cursor == BufferPosition(line: 0, column: 2)

  test "Surround block selection with multibyte characters":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "あいう world")
    discard buf.insertText(BufferPosition(line: 0, column: 9), "\nかきく bar")
    let state = createTestState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualSurround(buf, state, '[')

    check buf.getLine(0) == "[あいう] world"
    check buf.getLine(1) == "[かきく] bar"

suite "Visual Commands - fold-aware movement":
  test "visualMoveDown crosses a collapsed fold":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5\n6")
    discard buf.foldState.addFold(2, 4, collapsed = true)
    let state = createTestState()
    state.cursor = BufferPosition(line: 1, column: 0)
    state.visualSelection.current = state.cursor
    # j onto the fold start line.
    visualMoveDown(buf, state)
    check state.cursor.line == 2
    # j again crosses the whole collapsed fold to the line after it.
    visualMoveDown(buf, state)
    check state.cursor.line == 5
    check state.visualSelection.current.line == 5

  test "visualMoveUp crosses a collapsed fold":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5\n6")
    discard buf.foldState.addFold(2, 4, collapsed = true)
    let state = createTestState()
    state.cursor = BufferPosition(line: 5, column: 0)
    state.visualSelection.current = state.cursor
    # k from below the fold jumps to the fold start.
    visualMoveUp(buf, state)
    check state.cursor.line == 2
    check state.visualSelection.current.line == 2
    visualMoveUp(buf, state)
    check state.cursor.line == 1

  test "visualMoveDown stays put on a fold running to the buffer end":
    let buf = newTextBuffer("0\n1\n2\n3\n4")
    discard buf.foldState.addFold(2, 4, collapsed = true)
    let state = createTestState()
    state.cursor = BufferPosition(line: 2, column: 0)
    state.visualSelection.current = state.cursor
    visualMoveDown(buf, state)
    check state.cursor.line == 2

suite "Visual delete - register/buffer atomicity":
  # A read-only buffer rejects the delete, so nothing was removed: the registers
  # must keep their previous content (they are outside the buffer transaction
  # and a rollback would not restore them).

  proc newReadOnlyState(): (TextBuffer, EditorState) =
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 11), "\nfoo bar")
    let state = createTestState()
    # Linewise / multiline deletes land in number register 1, single-line
    # charwise deletes in the small delete register
    state.registers.setDeletedRegister("SEED_LINE\n", true)
    state.registers.setDeletedRegister("SEED", false)
    discard state.registers.setNamedRegister('a', "SEED_A", false)
    buf.readOnly = true
    (buf, state)

  test "charwise visual delete keeps registers when the delete fails":
    let (buf, state) = newReadOnlyState()
    state.mode = EditorMode.Visual
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualDelete(buf, state)

    check state.registers.getSmallDeleteRegister().getContent() == "SEED"
    check buf.getLine(0) == "hello world"

  test "linewise visual delete keeps registers when the delete fails":
    let (buf, state) = newReadOnlyState()
    state.mode = EditorMode.VisualLine
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 0),
      active: true,
      kind: vskLine,
    )

    visualDelete(buf, state)

    check state.registers.getNumberRegister(1).getContent() == "SEED_LINE\n"
    check buf.len == 2

  test "blockwise visual delete keeps registers when the delete fails":
    let (buf, state) = newReadOnlyState()
    state.mode = EditorMode.VisualBlock
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 1, column: 2),
      active: true,
      kind: vskBlock,
    )

    visualDelete(buf, state)

    check state.registers.getNumberRegister(1).getContent() == "SEED_LINE\n"
    check buf.getLine(0) == "hello world"

  test "named pending register survives a failed visual delete":
    let (buf, state) = newReadOnlyState()
    state.mode = EditorMode.Visual
    state.pendingInput.pendingRegister = some('a')
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualDelete(buf, state)

    check state.registers.getNamedRegister('a').getContent() == "SEED_A"

  test "charwise visual paste keeps registers when the delete fails":
    let (buf, state) = newReadOnlyState()
    state.mode = EditorMode.Visual
    state.registers.setYankedRegister("XYZ", false)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskChar,
    )

    visualPaste(buf, state)

    check state.registers.getSmallDeleteRegister().getContent() == "SEED"
    check buf.getLine(0) == "hello world"

  test "linewise visual paste keeps registers when the delete fails":
    let (buf, state) = newReadOnlyState()
    state.mode = EditorMode.VisualLine
    state.registers.setYankedRegister("XYZ\n", true)
    state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
      active: true,
      kind: vskLine,
    )

    visualPaste(buf, state)

    check state.registers.getNumberRegister(1).getContent() == "SEED_LINE\n"
    check buf.getLine(0) == "hello world"
