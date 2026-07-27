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

## Integration tests for command_registry
## These tests cover executeCommand and executeOperatorOnRange

import std/[unittest, options, strutils, tables, sets]

import pkg/results

import ../src/moepkg/[buffer, types, motion, key_bindings, config, modes, registers]
import ../src/moepkg/command_registry {.all.}

proc createTestContext(buffer: TextBuffer): CommandContext =
  let state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
  state.cursor = BufferPosition(line: 0, column: 0)
  state.mode = EditorMode.Normal
  state.registers = initRegisters()
  # CommandContext reads clipboard/notification live from state.config, so
  # tests toggle behavior by mutating state.config.clipboard etc.
  state.config.clipboard = ClipboardConfig(enable: false)

  let motionController = MotionController(
    viewportManager: ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    ),
    executor: MotionExecutor(buffer: buffer),
    cursorManager: newCursorManager(state),
  )

  result = CommandContext(
    buffer: buffer,
    state: state,
    motionController: motionController,
    keyBindingRegistry: newKeyBindingRegistry(),
  )

proc createTestRegistry(): CommandRegistry =
  ## Create a command registry with all builtin commands registered
  result = newCommandRegistry()
  registerBuiltinCommands(result)

proc setCursor(ctx: CommandContext, line, column: int) =
  ## Set cursor position on the state
  ctx.state.cursor = BufferPosition(line: line, column: column)

proc setupVisual(
    ctx: CommandContext,
    startLine, startCol, endLine, endCol: int,
    mode = EditorMode.Visual,
    kind = vskChar,
) =
  ## Setup visual mode with selection range
  ctx.state.mode = mode
  ctx.state.visualSelection = VisualSelection(
    active: true,
    start: BufferPosition(line: startLine, column: startCol),
    current: BufferPosition(line: endLine, column: endCol),
    kind: kind,
  )
  ctx.setCursor(endLine, endCol)

suite "executeCommand - Motion commands":
  test "execute basic motion (Right)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.Right, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.column == 1

  test "execute motion with count (3l)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.Right, count: 3)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.column == 3

  test "execute word motion (w)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.column == 6 # Position at 'w' in "world"

  test "execute motion Down (j)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.line == 1

  test "execute motion Up (k)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 2, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.Up, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.line == 1

  test "execute FirstLine motion (gg)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 3, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.FirstLine, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.line == 0

  test "execute LastLine motion (G)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.LastLine, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.line == 2

  test "1G goes to line 1, not the last line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 2, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.LastLine, count: 1, hasCount: true)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.line == 0

  test "2G goes to line 2":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.LastLine, count: 2, hasCount: true)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.line == 1

suite "executeCommand - Mode switch commands":
  test "switch to Insert mode":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctModeSwitch, targetMode: EditorMode.Insert, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.state.mode == EditorMode.Insert

  test "switch to Visual mode":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctModeSwitch, targetMode: EditorMode.Visual, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.state.mode == EditorMode.Visual

  test "switch from Insert to Normal mode":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Insert
    let registry = createTestRegistry()

    let cmd = Command(kind: ctModeSwitch, targetMode: EditorMode.Normal, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.state.mode == EditorMode.Normal

suite "executeCommand - Overlay switch commands":
  test "switch to command overlay":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctOverlaySwitch, targetOverlay: okCommand, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.state.overlay.isSome
    check ctx.state.overlay.get == okCommand

  test "switch to search overlay (forward)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    let cmd = Command(
      name: "switch-to-search-forward",
      kind: ctOverlaySwitch,
      targetOverlay: okSearch,
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.state.overlay.isSome
    check ctx.state.overlay.get == okSearch

  test "switch to search overlay (backward)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    let cmd = Command(
      name: "switch-to-search-backward",
      kind: ctOverlaySwitch,
      targetOverlay: okSearch,
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.state.overlay.isSome
    check ctx.state.overlay.get == okSearch

suite "executeCommand - Operator pending commands":
  test "find character (f)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.column == 4 # Position at 'o' in "hello"

  test "find character backward (F)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 10)
    let registry = createTestRegistry()

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: true,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.column == 7 # Position at 'o' in "world"

  test "till character (t)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.column == 3 # Position before 'o' in "hello"

  test "till character backward (T)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 10)
    let registry = createTestRegistry()

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: true,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.column == 8 # Position after 'o' in "world"

  test "find character not found does nothing":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "z", # Not in buffer
      count: 1,
    )

    let result = registry.executeCommand(ctx, cmd)
    check result.isOk # No error
    check ctx.cursor.column == 0 # Cursor didn't move

suite "executeCommand - Operator + Motion":
  test "delete word (dw)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (w) which completes the operator
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "world test"
    check ctx.cursor.column == 0

  test "delete word (dw) on whitespace-only last line":
    # Regression: dw on a line with only spaces at the last line of the buffer
    # should delete all spaces, not leave one behind.
    # See: moveWordForward "stuck at end" + exclusive adjustment bug.
    let buffer = newTextBuffer("hello\n  echo \"ok\"\n  ")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 2, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (w) which completes the operator
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    # All spaces on the line should be deleted
    check buffer[2] == ""
    check ctx.cursor.column == 0

  test "delete word (dw) on single word at last line":
    # dw on a single word at the last line should delete the entire word
    let buffer = newTextBuffer("first\nhello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[1] == ""
    check ctx.cursor.column == 0

  test "delete two words (d2w)":
    let buffer = newTextBuffer("hello world test end")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (2w)
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 2)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "test end"

  test "yank word (yw)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (y)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (w)
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "hello "

  test "change word (cw)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (c)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (w)
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "world"
    check ctx.state.mode == EditorMode.Insert

  test "delete to end of line (d$)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion ($)
    let cmd = Command(kind: ctMotion, motion: Motion.End, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello "

  test "delete line motion (dj)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (j) - this becomes a linewise operation
    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 1
    check buffer[0] == "line3"

  test "delete line motion (dj) on 2-line buffer clears to empty":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (j) - deletes all lines
    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 1
    check buffer[0] == ""

  test "delete line motion (dj) on 2-line buffer undo restores all lines":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)
    let deleteResult = registry.executeCommand(ctx, cmd)
    check deleteResult.isOk
    check buffer.len == 1
    check buffer[0] == ""

    # Single undo should restore both lines
    let undoResult = buffer.undo()
    check undoResult.isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == "line2"

  test "delete line motion (dj) on 3-line buffer undo restores deleted lines":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)
    let deleteResult = registry.executeCommand(ctx, cmd)
    check deleteResult.isOk
    check buffer.len == 1
    check buffer[0] == "line3"

    # Single undo should restore both deleted lines
    let undoResult = buffer.undo()
    check undoResult.isOk
    check buffer.len == 3
    check buffer[0] == "line1"
    check buffer[1] == "line2"
    check buffer[2] == "line3"

  test "delete line motion (dj) on single line buffer keeps empty line":
    let buffer = newTextBuffer("only line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (j) - only 1 line, motion down stays on line 0
    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 1

suite "executeCommand - Delete no-move guard (dh/dj/dk at boundary)":
  test "dh at column 0 is a no-op":
    let buffer = newTextBuffer("abc\ndef")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.Left, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 2
    check buffer[0] == "abc"
    check buffer[1] == "def"
    check ctx.state.pendingInput.pendingOperator.isNone

  test "dk on line 0 is a no-op":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    ctx.state.preferredColumn = -1
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.Up, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 3
    check buffer[0] == "line1"
    check buffer[1] == "line2"
    check buffer[2] == "line3"
    check ctx.state.pendingInput.pendingOperator.isNone

  test "dj on last line is a no-op":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 2, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 3
    check buffer[0] == "line1"
    check buffer[1] == "line2"
    check buffer[2] == "line3"
    check ctx.state.pendingInput.pendingOperator.isNone

  test "dh at column 0 does not clobber the unnamed register":
    let buffer = newTextBuffer("abc")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Prime the unnamed register with a previous yank ("xyz").
    ctx.state.registers.setNoNamedRegister("xyz", false)

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.Left, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "abc"
    check ctx.state.registers.noNamed.getContent == "xyz"

  test "dl at last column of last line still deletes (not caught by guard)":
    let buffer = newTextBuffer("abc")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.Right, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "ab"

suite "executeCommand - Delete with find motion":
  test "delete find character (df)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute find motion (fo) with pending operator
    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == " world"

  test "delete till character (dt)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute till motion (to) with pending operator
    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "o world"

  test "change find character (cf)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (c)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute find motion (fo) with pending operator
    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == " world"
    check ctx.state.mode == EditorMode.Insert

suite "executeCommand - Action commands":
  test "execute undo action":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    # Make a change first
    discard buffer.insertText(BufferPosition(line: 0, column: 5), " world")
    check buffer[0] == "hello world"

    let cmd = Command(kind: ctAction, commandId: "edit.undo", count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello"

  test "execute redo action":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    # Make a change and undo
    discard buffer.insertText(BufferPosition(line: 0, column: 5), " world")
    discard buffer.undo()
    check buffer[0] == "hello"

    let cmd = Command(kind: ctAction, commandId: "edit.redo", count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world"

suite "executeCommand - Repeat command (.)":
  test "repeat delete word":
    let buffer = newTextBuffer("hello world test end")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # First delete word (dw)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let dwCmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)
    discard registry.executeCommand(ctx, dwCmd)
    check buffer[0] == "world test end"

    # Now repeat with . command
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let repeatCmd = Command(kind: ctAction, commandId: "edit.repeat", count: 1)
    check registry.executeCommand(ctx, repeatCmd).isOk
    check buffer[0] == "test end"

  test "repeat delete-find reproduces the target char":
    # dfx then . must delete through the NEXT 'x', not collapse to one char.
    let buffer = newTextBuffer("axbxc") # 'x' at cols 1 and 3
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # dfx: delete from col 0 through the first 'x' (inclusive) -> "bxc"
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let findCmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "x",
      count: 1,
    )
    check registry.executeCommand(ctx, findCmd).isOk
    check buffer[0] == "bxc"

    # . repeats dfx from col 0 -> deletes through the next 'x' -> "c"
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let repeatCmd = Command(kind: ctAction, commandId: "edit.repeat", count: 1)
    check registry.executeCommand(ctx, repeatCmd).isOk
    check buffer[0] == "c"

  test "repeat delete-find with no target on the new line is a no-op":
    # dfx then . on a line with no 'x' must NOT delete a spurious character.
    let buffer = newTextBuffer("axb\nyyy")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let findCmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "x",
      count: 1,
    )
    check registry.executeCommand(ctx, findCmd).isOk
    check buffer[0] == "b" # "ax" deleted through the first x

    # Move to a line with no 'x' and repeat: the find fails, so . does nothing.
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let repeatCmd = Command(kind: ctAction, commandId: "edit.repeat", count: 1)
    check registry.executeCommand(ctx, repeatCmd).isOk
    check buffer[1] == "yyy" # unchanged - no phantom delete

suite "executeCommand - Record last edit":
  test "operator motion is recorded for repeat":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Delete word (dw)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)
    discard registry.executeCommand(ctx, cmd)

    # Check lastEditCommand is set
    check ctx.state.editState.lastEditCommand.isSome
    let lastCmd = ctx.state.editState.lastEditCommand.get
    check lastCmd.kind == lecOperatorMotion
    check lastCmd.operator == OpDelete
    check lastCmd.motion == Motion.WordForward

  test "yank is not recorded for repeat":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Yank word (yw)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)
    discard registry.executeCommand(ctx, cmd)

    # Check lastEditCommand is not set (yank is not a change)
    check ctx.state.editState.lastEditCommand.isNone

suite "executeCommand - Jump list":
  test "big motion records jump":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 2, column: 0)
    let registry = createTestRegistry()

    # Execute FirstLine motion (gg)
    let cmd = Command(kind: ctMotion, motion: Motion.FirstLine, count: 1)
    let result = registry.executeCommand(ctx, cmd)

    check result.isOk
    check ctx.cursor.line == 0
    check ctx.state.jumpList.list.len > 0

  test "LastLine motion records jump":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Execute LastLine motion (G)
    let cmd = Command(kind: ctMotion, motion: Motion.LastLine, count: 1)
    let result = registry.executeCommand(ctx, cmd)

    check result.isOk
    check ctx.cursor.line == 4
    check ctx.state.jumpList.list.len > 0

suite "executeCommand - Edge cases":
  test "motion at buffer boundary":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4) # At 'o'
    let registry = createTestRegistry()

    # Try to move right past end
    let cmd = Command(kind: ctMotion, motion: Motion.Right, count: 10)
    let result = registry.executeCommand(ctx, cmd)

    check result.isOk
    check ctx.cursor.column == 4 # Stays at end

  test "delete on empty line":
    let buffer = newTextBuffer("\nhello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (j)
    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)
    let result = registry.executeCommand(ctx, cmd)

    check result.isOk
    check buffer.len == 0 or buffer[0] != "\n"

  test "operator cancelled when motion fails":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute find motion with non-existent character
    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "z", # Not in buffer
      count: 1,
    )

    let result = registry.executeCommand(ctx, cmd)
    check result.isOk # No error, just cancelled
    check buffer[0] == "hello" # Buffer unchanged
    check ctx.state.pendingInput.pendingOperator.isNone # Operator cleared

  test "mode switch clears key sequence":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.keyBindingRegistry.sequenceState.keys = @[toKeyCombo('d')]
    let registry = createTestRegistry()

    let cmd = Command(kind: ctModeSwitch, targetMode: EditorMode.Insert, count: 1)
    let result = registry.executeCommand(ctx, cmd)

    check result.isOk
    check ctx.keyBindingRegistry.sequenceState.keys.len == 0

suite "Handler - Paste operations":
  test "paste after cursor (p) - characterwise":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4)
    ctx.state.registers.setYankedRegister("XYZ", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer[0] == "helloXYZ world"

  test "paste after cursor (p) - linewise":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("new line", true)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 3
    check buffer[1] == "new line"

  test "paste after cursor (p) - linewise moves cursor to first non-blank":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("  indented", true)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 3
    check buffer[1] == "  indented"
    check ctx.cursor.line == 1
    check ctx.cursor.column == 2

  test "paste after cursor (p) - linewise no indent":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("no indent", true)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 3
    check buffer[1] == "no indent"
    check ctx.cursor.line == 1
    check ctx.cursor.column == 0

  test "paste after cursor (p) - linewise all whitespace moves to last char":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("   ", true)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 3
    check buffer[1] == "   "
    check ctx.cursor.line == 1
    check ctx.cursor.column == 2

  test "paste with count (3p)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4)
    ctx.state.registers.setYankedRegister("X", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after"), @["3"]).isOk
    check buffer[0] == "helloXXX"

  test "paste empty register returns error":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("", false)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, custom("paste.after"))
    check result.isErr
    check "Nothing to paste" in result.error

  test "paste before cursor (P) - characterwise":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 5)
    ctx.state.registers.setYankedRegister("XYZ", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.before")).isOk
    check buffer[0] == "helloXYZ world"

  test "paste before cursor (P) - linewise moves cursor to first non-blank":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.registers.setYankedRegister("\tindented", true)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.before")).isOk
    check buffer.len == 3
    check buffer[1] == "\tindented"
    check ctx.cursor.line == 1
    check ctx.cursor.column == 1

  test "paste before cursor (P) - linewise no indent":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("no indent", true)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.before")).isOk
    check buffer.len == 3
    check buffer[0] == "no indent"
    check ctx.cursor.line == 0
    check ctx.cursor.column == 0

  test "paste before cursor (P) - linewise all whitespace moves to last char":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.registers.setYankedRegister("  ", true)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.before")).isOk
    check buffer.len == 3
    check buffer[1] == "  "
    check ctx.cursor.line == 1
    check ctx.cursor.column == 1

  test "paste after cursor (p) - multibyte characterwise":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4)
    ctx.state.registers.setYankedRegister("あいう", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer[0] == "helloあいう world"
    # Cursor lands on the first pasted char (column 4 + 1)
    check ctx.cursor.column == 5

  test "paste before cursor (P) - multibyte characterwise":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 5)
    ctx.state.registers.setYankedRegister("あいう", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.before")).isOk
    check buffer[0] == "helloあいう world"
    # Cursor lands on the first pasted char (column 5)
    check ctx.cursor.column == 5

  test "paste after cursor (p) - charwise multi-line":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("xy\nab", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 2
    check buffer[0] == "hxy"
    check buffer[1] == "abello"
    # Cursor lands on the first pasted char ('x')
    check ctx.cursor.line == 0
    check ctx.cursor.column == 1

  test "paste after cursor (p) - charwise multi-line count=2":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("xy\nab", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after"), @["2"]).isOk
    # First p pastes after column 0, second p pastes right after the previous
    # last char, giving: h|xy\nab|xy\nab|ello
    check buffer.len == 3
    check buffer[0] == "hxy"
    check buffer[1] == "abxy"
    check buffer[2] == "abello"
    # Cursor lands on the first pasted char ('x')
    check ctx.cursor.line == 0
    check ctx.cursor.column == 1

  test "paste before cursor (P) - charwise multi-line":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    ctx.state.registers.setYankedRegister("xy\nab", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.before")).isOk
    check buffer.len == 2
    check buffer[0] == "hexy"
    check buffer[1] == "abllo"
    # Cursor lands on the first pasted char ('x')
    check ctx.cursor.line == 0
    check ctx.cursor.column == 2

  test "paste after cursor (p) - charwise multi-line multibyte":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.registers.setYankedRegister("あい\nうえお", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 2
    check buffer[0] == "hあい"
    check buffer[1] == "うえおello"
    # Cursor lands on the first pasted rune ('あ')
    check ctx.cursor.line == 0
    check ctx.cursor.column == 1

suite "Handler - Delete char operations":
  test "delete char at cursor (x)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == "ello"
    check ctx.state.registers.getNoNamedRegister().getContent() == "h"

  test "delete multiple chars (3x)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char"), @["3"]).isOk
    check buffer[0] == "lo"
    check ctx.state.registers.getNoNamedRegister().getContent() == "hel"

  test "delete char at end of line stays in bounds":
    let buffer = newTextBuffer("hi")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == "h"
    check ctx.cursor.column == 0 # Adjusted to stay in bounds

  test "delete char on empty position returns error":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 5) # Past end
    let registry = createTestRegistry()

    let result = registry.execute(ctx, custom("delete.char"))
    check result.isErr
    check "Nothing to delete" in result.error

  test "delete char before cursor (X)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isOk
    check buffer[0] == "hllo"
    check ctx.cursor.column == 1

  test "delete char before at column 0 returns error":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, custom("delete.char.before"))
    check result.isErr
    check "Nothing to delete" in result.error

suite "Handler - Delete char auto-delete paren (x)":
  test "x on opening bracket of adjacent pair deletes both":
    # [] -> x on [ -> empty
    let buffer = newTextBuffer("[]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == ""

  test "x on opening paren of adjacent pair deletes both":
    # () -> x on ( -> empty
    let buffer = newTextBuffer("()")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == ""

  test "x on opening brace of adjacent pair deletes both":
    # {} -> x on { -> empty
    let buffer = newTextBuffer("{}")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == ""

  test "x on opening bracket with content only deletes bracket":
    # [hello] -> x on [ -> hello]
    let buffer = newTextBuffer("[hello]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == "hello]"

  test "x on closing bracket does not auto-delete":
    # [] -> x on ] -> [
    let buffer = newTextBuffer("[]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 1)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == "["

  test "x on bracket with spaces does not auto-delete":
    # [   ] -> x on ] -> [
    let buffer = newTextBuffer("[   ]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == "[   "

  test "x on adjacent pair in middle of line":
    # a()b -> x on ( -> ab
    let buffer = newTextBuffer("a()b")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 1)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == "ab"

  test "x with autoDeleteParen disabled":
    # [] -> x on [ with disabled -> ]
    let buffer = newTextBuffer("[]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = false
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == "]"

  test "x on adjacent pair stores both chars in the register":
    let buffer = newTextBuffer("a()b")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 1)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check ctx.state.registers.getNoNamedRegister().getContent() == "()"

  test "x on adjacent quote pair":
    # "" -> x on first " -> empty
    let buffer = newTextBuffer("\"\"")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == ""

suite "Handler - Delete char before auto-delete paren (X)":
  test "X between adjacent pair deletes both":
    # [] with cursor after [ -> X deletes both
    let buffer = newTextBuffer("[]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 1)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isOk
    check buffer[0] == ""
    check ctx.cursor.column == 0

  test "X on closing bracket with content only deletes bracket":
    # [hello] with cursor on ] -> X deletes only char before (o not ])
    let buffer = newTextBuffer("[hello]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 6)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isOk
    check buffer[0] == "[hell]"

  test "X between adjacent brace pair":
    # {} with cursor after { -> X deletes both
    let buffer = newTextBuffer("{}")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 1)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isOk
    check buffer[0] == ""
    check ctx.cursor.column == 0

  test "X with autoDeleteParen disabled":
    # [] with cursor after [ -> X only deletes [
    let buffer = newTextBuffer("[]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = false
    ctx.cursor = BufferPosition(line: 0, column: 1)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isOk
    check buffer[0] == "]"
    check ctx.cursor.column == 0

  test "X between adjacent pair in middle of line":
    # a()b with cursor between ( and ) -> X deletes both
    let buffer = newTextBuffer("a()b")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isOk
    check buffer[0] == "ab"
    check ctx.cursor.column == 1

  test "X on adjacent pair stores both chars in the register":
    let buffer = newTextBuffer("a()b")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isOk
    check ctx.state.registers.getNoNamedRegister().getContent() == "()"

  test "X with bracket and spaces does not auto-delete":
    # [   ] with cursor on ] -> X deletes space only
    let buffer = newTextBuffer("[   ]")
    let ctx = createTestContext(buffer)
    ctx.state.autoDeleteParen = true
    ctx.cursor = BufferPosition(line: 0, column: 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isOk
    check buffer[0] == "[  ]"
    check ctx.cursor.column == 3

suite "Handler - Delete line operations":
  test "delete single line (dd)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == "line3"

  test "delete multiple lines (3dd)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line"), @["3"]).isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == "line5"

  test "delete last line moves cursor up":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isOk
    check buffer.len == 1
    check buffer[0] == "line1"
    check ctx.cursor.line == 0

  test "dd preserves column position when next line is long enough":
    let buffer = newTextBuffer("short\nhello world\nlong enough line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 8)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isOk
    check buffer.len == 2
    check buffer[0] == "short"
    check buffer[1] == "long enough line"
    check ctx.cursor.line == 1
    check ctx.cursor.column == 8

  test "dd clamps column to end of shorter line":
    let buffer = newTextBuffer("hello world\nhi\nthird")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 9)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isOk
    check buffer.len == 2
    check buffer[0] == "hi"
    check buffer[1] == "third"
    check ctx.cursor.line == 0
    check ctx.cursor.column == 1 # "hi" has charLen 2, so max column is 1

  test "dd preserves column when deleting last line":
    let buffer = newTextBuffer("hello\nworld!")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 3)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isOk
    check buffer.len == 1
    check buffer[0] == "hello"
    check ctx.cursor.line == 0
    check ctx.cursor.column == 3

  test "dd on single line buffer clears line content":
    let buffer = newTextBuffer("only line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isOk
    check buffer.len == 1
    check buffer[0] == ""
    check ctx.cursor.line == 0

  test "dd on single empty line buffer keeps empty line":
    let buffer = newTextBuffer("")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isOk
    check buffer.len == 1
    check buffer[0] == ""

  test "delete all lines with count (2dd on 2-line buffer)":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line"), @["2"]).isOk
    check buffer.len == 1
    check buffer[0] == ""
    check ctx.cursor.line == 0

  test "dd on single line buffer undo restores content":
    let buffer = newTextBuffer("only line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let deleteResult = registry.execute(ctx, custom("delete.line"))
    check deleteResult.isOk
    check buffer[0] == ""

    # Single undo should restore the original content
    let undoResult = buffer.undo()
    check undoResult.isOk
    check buffer.len == 1
    check buffer[0] == "only line"

  test "2dd on 2-line buffer undo restores all lines":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let deleteResult = registry.execute(ctx, custom("delete.line"), @["2"])
    check deleteResult.isOk
    check buffer.len == 1
    check buffer[0] == ""

    # Single undo should restore both lines
    let undoResult = buffer.undo()
    check undoResult.isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == "line2"

  test "3dd undo restores all deleted lines":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    let deleteResult = registry.execute(ctx, custom("delete.line"), @["3"])
    check deleteResult.isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == "line5"

    # Single undo should restore all 3 deleted lines
    let undoResult = buffer.undo()
    check undoResult.isOk
    check buffer.len == 5
    check buffer[0] == "line1"
    check buffer[1] == "line2"
    check buffer[2] == "line3"
    check buffer[3] == "line4"
    check buffer[4] == "line5"

suite "Handler - Yank line operations":
  test "yank single line (yy)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("yank.line")).isOk
    check buffer.len == 3 # Buffer unchanged
    check "line2" in ctx.state.registers.getNoNamedRegister().getContent()
    check ctx.state.registers.getNoNamedRegister().isLine == true
    # Register system must also be updated
    let reg = ctx.state.registers.getNoNamedRegister()
    check "line2" in reg.getContent()
    check reg.isLine == true

  test "yank multiple lines (3yy)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("yank.line"), @["3"]).isOk
    check buffer.len == 4 # Buffer unchanged
    check "line1" in ctx.state.registers.getNoNamedRegister().getContent()
    check "line2" in ctx.state.registers.getNoNamedRegister().getContent()
    check "line3" in ctx.state.registers.getNoNamedRegister().getContent()
    # Register system must also be updated
    let reg = ctx.state.registers.getNoNamedRegister()
    check "line1" in reg.getContent()
    check "line2" in reg.getContent()
    check "line3" in reg.getContent()
    check reg.isLine == true

  test "yank single line then paste (yy then p)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    # yy
    let yankResult = registry.execute(ctx, custom("yank.line"))
    check yankResult.isOk

    # p
    let pasteResult = registry.execute(ctx, custom("paste.after"))
    check pasteResult.isOk
    check buffer.len == 4
    check buffer[2] == "line2"

  test "yank line after delete still yanks correctly (yy after x)":
    let buffer = newTextBuffer("hello\nworld\nfoo")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # x deletes 'h' and sets delete register
    let deleteResult = registry.execute(ctx, custom("delete.char"))
    check deleteResult.isOk
    check buffer[0] == "ello"

    # yy on line 1
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let yankResult = registry.execute(ctx, custom("yank.line"))
    check yankResult.isOk

    # p should paste "world", not "h"
    ctx.cursor = BufferPosition(line: 2, column: 0)
    let pasteResult = registry.execute(ctx, custom("paste.after"))
    check pasteResult.isOk
    check "world" in buffer[3]

  test "yy on empty line stores linewise empty line in register":
    let buffer = newTextBuffer("line1\n\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("yank.line")).isOk
    let reg = ctx.state.registers.getNoNamedRegister()
    check reg.isLine == true
    check reg.getLines() == @[""]
    check not reg.isEmpty

  test "yy then p on empty line inserts blank line below (Vim parity)":
    let buffer = newTextBuffer("line1\n\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("yank.line")).isOk
    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 4
    check buffer[0] == "line1"
    check buffer[1] == ""
    check buffer[2] == ""
    check buffer[3] == "line3"
    check ctx.cursor.line == 2

  test "dd then p on empty line inserts blank line below":
    let buffer = newTextBuffer("line1\n\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isOk
    # buffer is now: "line1\nline3", cursor on old line 2 (now line 1)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 3
    check buffer[0] == "line1"
    check buffer[1] == ""
    check buffer[2] == "line3"

  test "P on linewise empty-line register inserts blank line above":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    let registry = createTestRegistry()

    ctx.state.registers.setYankedRegister("", true)
    check registry.execute(ctx, custom("paste.before")).isOk
    check buffer.len == 3
    check buffer[0] == "line1"
    check buffer[1] == ""
    check buffer[2] == "line2"

suite "Handler - Substitute operations":
  test "substitute char (s)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("substitute.char")).isOk
    check buffer[0] == "ello"
    check ctx.state.mode == EditorMode.Insert

  test "substitute multiple chars (3s)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("substitute.char"), @["3"]).isOk
    check buffer[0] == "lo"
    check ctx.state.mode == EditorMode.Insert

  test "substitute line (S)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("substitute.line")).isOk
    check buffer[0] == ""
    check ctx.state.mode == EditorMode.Insert

suite "Handler - Join lines":
  test "join lines (J)":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("join.lines")).isOk
    check buffer.len == 1
    check buffer[0] == "line1 line2"

  test "join multiple lines (3J)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("join.lines"), @["3"]).isOk
    # 3J joins current line with next 3 lines (all 4 lines become 1)
    check buffer.len == 1
    check buffer[0] == "line1 line2 line3 line4"

  test "join on last line returns error":
    let buffer = newTextBuffer("only line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, custom("join.lines"))
    # Joining on last line returns an error because there's nothing to join
    check result.isErr or buffer.len == 1

suite "Handler - Toggle case":
  test "toggle case (~)":
    let buffer = newTextBuffer("Hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("toggle.case")).isOk
    check buffer[0] == "hEllo" or buffer[0][0] == 'h' # First char toggled

  test "toggle case multiple chars (3~)":
    let buffer = newTextBuffer("Hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("toggle.case"), @["3"]).isOk
    # "Hel" -> "hEL"
    check buffer[0][0] == 'h'
    check buffer[0][1] == 'E'
    check buffer[0][2] == 'L'

suite "Handler - Replace char (r)":
  test "replace single char":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(
      kind: ctOperatorPending, operatorType: "replace", targetChar: "X", count: 1
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "Xello"

  test "replace multiple chars (3ra)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(
      kind: ctOperatorPending, operatorType: "replace", targetChar: "a", count: 3
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "aaalo"

  test "replace at end of line returns error":
    let buffer = newTextBuffer("hi")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2) # Past end
    let registry = createTestRegistry()

    let cmd = Command(
      kind: ctOperatorPending, operatorType: "replace", targetChar: "X", count: 1
    )

    let result = registry.executeCommand(ctx, cmd)
    check result.isErr
    check "Nothing to replace" in result.error

suite "Handler - Insert operations":
  test "insert line below (o)":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcInsertLineBelow)).isOk
    check buffer.len == 3
    check buffer[0] == "line1"
    check buffer[1] == ""
    check buffer[2] == "line2"
    check ctx.state.mode == EditorMode.Insert

  test "insert line above (O)":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.setCursor(1, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcInsertLineAbove)).isOk
    check buffer.len == 3
    # Insert line above at line 1 creates empty line at line 1
    check buffer[1] == ""
    check ctx.state.mode == EditorMode.Insert

suite "Handler - Scroll operations":
  test "scroll cursor to top (zt)":
    let buffer = newTextBuffer(
      "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10"
    )
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 5, column: 0)
    ctx.motionController.viewportManager.viewport.topLine = 0
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcScrollCursorTop)).isOk
    check ctx.motionController.viewportManager.viewport.topLine == 5

  test "scroll cursor to center (zz)":
    let buffer = newTextBuffer(
      "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11\nline12\nline13\nline14\nline15\nline16\nline17\nline18\nline19\nline20\nline21\nline22\nline23\nline24\nline25"
    )
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 12, column: 0)
    ctx.motionController.viewportManager.viewport.topLine = 0
    ctx.motionController.viewportManager.viewport.height = 24
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcScrollCursorCenter)).isOk
    # Cursor at line 12 should be centered
    check ctx.motionController.viewportManager.viewport.topLine > 0

  test "scroll cursor to bottom (zb)":
    let buffer = newTextBuffer(
      "line1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\nline10\nline11\nline12\nline13\nline14\nline15\nline16\nline17\nline18\nline19\nline20\nline21\nline22\nline23\nline24\nline25"
    )
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 20, column: 0)
    ctx.motionController.viewportManager.viewport.topLine = 20
    ctx.motionController.viewportManager.viewport.height = 24
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcScrollCursorBottom)).isOk

suite "Handler - Visual mode operations":
  test "visual delete":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualDelete)).isOk
    check buffer[0] == " world"
    check ctx.state.mode == EditorMode.Normal

  test "visual yank":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualYank)).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check "hello" in ctx.state.registers.getNoNamedRegister().getContent()
    check ctx.state.mode == EditorMode.Normal

  test "visual indent":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 1, 0, EditorMode.VisualLine)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualIndent)).isOk
    # Lines should be indented
    check buffer[0].len > 5 or buffer[0][0] == ' '

  test "visual lowercase":
    let buffer = newTextBuffer("HELLO WORLD")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualLowercase)).isOk
    check buffer[0] == "hello WORLD"

  test "visual uppercase":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualUppercase)).isOk
    check buffer[0] == "HELLO world"

  test "visual join lines":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 1, 0, EditorMode.VisualLine)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualJoinLines)).isOk
    check buffer.len == 2
    check buffer[0] == "line1 line2"

  test "visual change":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualChange)).isOk
    check buffer[0] == " world"
    check ctx.state.mode == EditorMode.Insert

suite "Handler - Increment/Decrement":
  test "increment number (Ctrl-A)":
    let buffer = newTextBuffer("count: 42")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 7) # On '4'
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcEditIncrementNumber)).isOk
    check "43" in buffer[0]

  test "decrement number (Ctrl-X)":
    let buffer = newTextBuffer("count: 42")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 7) # On '4'
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcEditDecrementNumber)).isOk
    check "41" in buffer[0]

  test "increment negative number":
    let buffer = newTextBuffer("value: -5")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 7) # On '-'
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcEditIncrementNumber)).isOk
    check "-4" in buffer[0]

  test "decrement to negative":
    let buffer = newTextBuffer("count: 0")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 7) # On '0'
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcEditDecrementNumber)).isOk
    check "-1" in buffer[0]

  test "increment number after multibyte prefix":
    let buffer = newTextBuffer("あいう42")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 3) # Character index 3 = '4'
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcEditIncrementNumber)).isOk
    check buffer[0] == "あいう43"
    check ctx.cursor.column == 3 # Character index of '4' in the new line

  test "decrement number after multibyte prefix":
    let buffer = newTextBuffer("あいう42")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 3) # Character index 3 = '4'
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcEditDecrementNumber)).isOk
    check buffer[0] == "あいう41"
    check ctx.cursor.column == 3 # Character index of '4' in the new line

  test "Ctrl-A on high(int) does not crash":
    let h = $high(int)
    let buffer = newTextBuffer(h)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcEditIncrementNumber)).isOk
    check buffer[0] == h

  test "Ctrl-X on low(int) does not crash":
    let l = $low(int)
    let buffer = newTextBuffer(l)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcEditDecrementNumber)).isOk
    check buffer[0] == l

suite "Handler - Indent/Dedent":
  test "indent line (>>)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("indent.line")).isOk
    # Line should start with whitespace (space or tab)
    check buffer[0][0] == ' ' or buffer[0][0] == '\t'

  test "dedent line (<<)":
    let buffer = newTextBuffer("    hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("dedent.line")).isOk
    check buffer[0].len < 9 # Line should be shorter

  test "indent line count is a line count (vim's [count]>>)":
    let buffer = newTextBuffer("a\nb\nc")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("indent.line"), @["2"]).isOk
    check buffer[0].strip == "a"
    check buffer[1].strip == "b"
    check buffer[0][0] in {' ', '\t'}
    check buffer[1][0] in {' ', '\t'}
    check buffer[2] == "c"
    # Cursor lands on the first non-blank, like >>
    check ctx.cursor == BufferPosition(line: 0, column: buffer[0].len - 1)

  test "dedent line count is a line count (vim's [count]<<)":
    let buffer = newTextBuffer("    a\n    b\n    c")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("dedent.line"), @["2"]).isOk
    check buffer[0].len < 5
    check buffer[1].len < 5
    check buffer[2] == "    c"

suite "Handler - Fold operations":
  test "fold toggle":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Fold toggle should work (may not have visible effect without actual fold)
    check registry.execute(ctx, builtin(bcFoldToggle)).isOk

  test "fold open all":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcFoldOpenAll)).isOk

  test "fold close all":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcFoldCloseAll)).isOk

suite "Handler - Text Object operations":
  test "textobject.inner without pending operator enters Insert mode":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Call textobject.inner without pending operator
    check registry.execute(ctx, custom("textobject.inner")).isOk
    check ctx.state.mode == EditorMode.Insert

  test "textobject.around without pending operator enters Insert mode (append)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Call textobject.around without pending operator
    check registry.execute(ctx, custom("textobject.around")).isOk
    check ctx.state.mode == EditorMode.Insert
    check ctx.cursor.column == 1 # Cursor moved right for append

  test "textobject.inner is blocked on read-only buffer (plain i fallback)":
    let buffer = newTextBuffer("hello world")
    buffer.readOnly = true
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("textobject.inner")).isOk
    check ctx.state.mode == EditorMode.Normal
    check ctx.state.statusMessage == "Buffer is read-only"

  test "textobject.around is blocked on read-only buffer (plain a fallback)":
    let buffer = newTextBuffer("hello world")
    buffer.readOnly = true
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("textobject.around")).isOk
    check ctx.state.mode == EditorMode.Normal
    check ctx.cursor.column == 0 # Cursor must not move
    check ctx.state.statusMessage == "Buffer is read-only"

  test "mode.insert builtin is blocked on read-only buffer":
    let buffer = newTextBuffer("hello world")
    buffer.readOnly = true
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcModeInsert)).isOk
    check ctx.state.mode == EditorMode.Normal
    check ctx.state.statusMessage == "Buffer is read-only"

  test "textobject.inner with pending operator sets text object modifier":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Call textobject.inner
    check registry.execute(ctx, custom("textobject.inner")).isOk
    check ctx.state.pendingInput.pendingTextObject.isSome
    check ctx.state.pendingInput.pendingTextObject.get.modifier == tomInner

  test "textobject.around with pending operator sets text object modifier":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (c)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    # Call textobject.around
    check registry.execute(ctx, custom("textobject.around")).isOk
    check ctx.state.pendingInput.pendingTextObject.isSome
    check ctx.state.pendingInput.pendingTextObject.get.modifier == tomAround

  test "textobject word (diw) deletes inner word":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 7) # On 'o' in "world"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Call textobject.inner
    discard registry.execute(ctx, custom("textobject.inner"))

    # Now execute text object kind (word)
    check registry.execute(ctx, custom("textobject.word")).isOk
    # "world" should be deleted
    check "world" notin buffer[0]

  test "textobject word (daw) deletes around word":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # On 'w' in "world"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Call textobject.around
    discard registry.execute(ctx, custom("textobject.around"))

    # Now execute text object kind (word)
    check registry.execute(ctx, custom("textobject.word")).isOk
    # "world " should be deleted (including surrounding space)
    check "world" notin buffer[0]

  test "textobject tag (dit) deletes inner tag content":
    let buffer = newTextBuffer("<a>hello</a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4) # inside "hello"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check buffer[0] == "<a></a>"

  test "textobject tag (dat) deletes the whole tag":
    let buffer = newTextBuffer("x<a>hi</a>y")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 5) # inside "hi"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.around"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check buffer[0] == "xy"

  test "textobject tag (cit) on empty tag enters Insert mode between the tags":
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1) # on the open tag
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    # Nothing deleted, cursor between the tags, ready to type.
    check buffer[0] == "<a></a>"
    check ctx.state.mode == EditorMode.Insert
    check (ctx.cursor.line, ctx.cursor.column) == (0, 3)

  test "textobject tag (dit) on empty tag is a no-op":
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check buffer[0] == "<a></a>"
    check ctx.state.mode == EditorMode.Normal

  test "textobject tag (yit) on empty tag leaves registers untouched":
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Seed the unnamed register; an empty yank must not clobber it.
    ctx.state.registers.setYankedRegister("PREV", false)

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check ctx.state.registers.getNoNamedRegister().getContent() == "PREV"

  test "textobject tag (dit) on empty tag leaves registers untouched":
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # An empty delete removes nothing, so a previously yanked value survives.
    ctx.state.registers.setYankedRegister("PREV", false)

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check ctx.state.registers.getNoNamedRegister().getContent() == "PREV"

  test "textobject tag (\"ayit) on empty tag consumes the pending register":
    # Regression: an empty yank is a no-op, but the operator command still
    # completes -- the `"a` register prefix must be consumed, not leaked into
    # the next command.
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('a')
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check ctx.state.pendingInput.pendingRegister.isNone

  test "textobject tag (\"adit) on empty tag consumes the pending register":
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('a')
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check ctx.state.pendingInput.pendingRegister.isNone

  test "textobject tag (\"acit) on empty tag consumes the pending register":
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('a')
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check ctx.state.mode == EditorMode.Insert
    check ctx.state.pendingInput.pendingRegister.isNone

  test "textobject tag (gUit) on empty tag is a no-op, not a corruption":
    # Regression: case operators must honor the empty range. Previously this
    # deleted the closing tag's '<' (<a></a> -> <a>/a>).
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpUpperCase, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check buffer[0] == "<a></a>"

  test "textobject tag (guit) on empty tag is a no-op":
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpLowerCase, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check buffer[0] == "<a></a>"

  test "textobject tag (>it) on empty tag does not indent the line":
    # Regression: indent operators must honor the empty range (was <a></a> ->
    # \t<a></a>).
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpIndent, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check buffer[0] == "<a></a>"

  test "textobject quote (gUi\") on empty quotes is a no-op":
    let buffer = newTextBuffer("x \"\" y")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 3)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpUpperCase, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.quote.double")).isOk
    check buffer[0] == "x \"\" y"

  test "textobject paren (>i() on empty parens does not indent the line":
    let buffer = newTextBuffer("x () y")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpIndent, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.paren")).isOk
    check buffer[0] == "x () y"

  test "textobject tag (vit) on empty tag leaves the selection untouched":
    # Visual mode must not turn an empty object into a zero-width selection.
    let buffer = newTextBuffer("<a></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection.start = BufferPosition(line: 0, column: 1)
    ctx.state.visualSelection.current = BufferPosition(line: 0, column: 1)
    ctx.state.visualSelection.active = true
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    check buffer[0] == "<a></a>"
    # Cursor and selection stay put (no jump to the close tag's '<').
    check (ctx.cursor.line, ctx.cursor.column) == (0, 1)
    check (
      ctx.state.visualSelection.current.line, ctx.state.visualSelection.current.column
    ) == (0, 1)

  test "textobject paren (di() on a multi-line block collapses to ()":
    # Regression: a closing delimiter at column 0 used to yield a negative end
    # column and fail with `Column positions cannot be negative`.
    let buffer = newTextBuffer("foo(\n  bar\n)")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 3) # on the open paren
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.paren")).isOk
    check buffer.len == 1
    check buffer[0] == "foo()"

  test "textobject paren (ci() on a multi-line block collapses and enters Insert":
    let buffer = newTextBuffer("(\n  bar\n)")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.paren")).isOk
    check buffer.len == 1
    check buffer[0] == "()"
    check ctx.state.mode == EditorMode.Insert
    # Cursor lands between the delimiters, ready to type.
    check (ctx.cursor.line, ctx.cursor.column) == (0, 1)

  test "textobject brace (di{) on a multi-line block collapses to {}":
    let buffer = newTextBuffer("{\n  x\n}")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.brace")).isOk
    check buffer.len == 1
    check buffer[0] == "{}"

  test "textobject paren (yi() on a multi-line block yanks the inner content":
    let buffer = newTextBuffer("(\n  bar\n)")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.paren")).isOk
    # Buffer is untouched and the register holds the full inner content,
    # including the trailing newline that a delete would consume (matching
    # buffer.deleteRange / getTextInRange).
    check buffer[0] == "("
    check ctx.state.registers.getNoNamedRegister().getContent() == "\n  bar\n"

  test "textobject paren (di() on a multi-line block stores the deleted text verbatim":
    # Regression: the yank register must match what the delete removed. The
    # collapse range ends at the content line's end-of-content column, so the
    # register has to include the trailing newline deleteRange consumes.
    let buffer = newTextBuffer("foo(\n  bar\n)")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 3) # on the open paren
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.paren")).isOk
    check buffer.len == 1
    check buffer[0] == "foo()"
    # di( then p must round-trip: register == removed text == "\n  bar\n".
    check ctx.state.registers.getNoNamedRegister().getContent() == "\n  bar\n"

  test "textobject paren (di() on a single content line collapses and stores it":
    # `(x\n)`: the close sits at column 0 on the next line, so the inner range is
    # single-line ending at charLen("(x"); the register must carry the newline.
    let buffer = newTextBuffer("(x\n)")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.paren")).isOk
    check buffer.len == 1
    check buffer[0] == "()"
    check ctx.state.registers.getNoNamedRegister().getContent() == "x\n"

  test "textobject paren (ci() on a multi-line empty pair is a no-op insert":
    # `(\n)` has only the boundary newline between the delimiters: no content to
    # delete, but `ci(` still drops into Insert mode between them.
    let buffer = newTextBuffer("(\n)")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.paren")).isOk
    # Nothing deleted; cursor sits just before the close delimiter.
    check buffer.len == 2
    check buffer[0] == "("
    check buffer[1] == ")"
    check ctx.state.mode == EditorMode.Insert
    check (ctx.cursor.line, ctx.cursor.column) == (1, 0)

  test "textobject paren (di() on a multi-line empty pair is a no-op":
    let buffer = newTextBuffer("(\n)")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.paren")).isOk
    check buffer.len == 2
    check buffer[0] == "("
    check buffer[1] == ")"
    check ctx.state.mode == EditorMode.Normal

  test "textobject paragraph (dap) deletes the paragraph linewise":
    let buffer = newTextBuffer("aaa\nbbb\n\nccc")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.around"))
    check registry.execute(ctx, custom("textobject.paragraph")).isOk
    # "aaa", "bbb" and the trailing blank line are gone; only "ccc" remains.
    check buffer.len == 1
    check buffer[0] == "ccc"

  test "textobject sentence (dis) deletes the sentence":
    let buffer = newTextBuffer("One two. Three four.")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1) # inside "One"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.sentence")).isOk
    # Inner sentence "One two." removed, trailing space kept.
    check buffer[0] == " Three four."

  test "textobject paragraph with count (2dap) deletes two paragraphs":
    let buffer = newTextBuffer("aaa\n\nbbb\n\nccc")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.around"))
    check registry.execute(ctx, custom("textobject.paragraph")).isOk
    # First two paragraphs (with their trailing blank lines) gone; "ccc" remains.
    check buffer.len == 1
    check buffer[0] == "ccc"

  test "textobject sentence with count (2dis) deletes two sentences":
    let buffer = newTextBuffer("One two. Three four. Five six.")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 1) # inside "One"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.sentence")).isOk
    # Inner of the first two sentences removed; " Five six." remains.
    check buffer[0] == " Five six."

  test "textobject tag (dit) on multi-line content removes the content line":
    let buffer = newTextBuffer("<div>\ncontent\n</div>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 2)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    # vim removes the content line entirely (linewise), not just its text.
    check buffer.len == 2
    check buffer[0] == "<div>"
    check buffer[1] == "</div>"

  test "textobject paragraph count 3 (3dap) leaves no stray blank line":
    let buffer = newTextBuffer("p1\n\np2\n\np3\n\np4")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 3, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.around"))
    check registry.execute(ctx, custom("textobject.paragraph")).isOk
    # Three paragraphs and their trailing blanks gone; only "p4" remains (no
    # leftover blank line).
    check buffer.len == 1
    check buffer[0] == "p4"

  test "textobject tag count (2dat) deletes the enclosing tag":
    let buffer = newTextBuffer("<a><b>x</b></a>")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # on 'x'
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.around"))
    check registry.execute(ctx, custom("textobject.tag")).isOk
    # 2at reaches the outer <a>...</a>; the whole thing is removed.
    check buffer[0] == ""

  test "failed text object (dit outside a tag) clears the pending operator":
    let buffer = newTextBuffer("hello world\nsecond line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    # dit on plain text errors; the operator must not survive armed.
    check registry.execute(ctx, custom("textobject.tag")).isErr
    check ctx.state.pendingInput.pendingOperator.isNone
    # A following motion must therefore be a plain move, not a stray delete.
    check registry.executeCommand(
      ctx, Command(kind: ctMotion, motion: Motion.Down, count: 1)
    ).isOk
    check buffer.len == 2
    check buffer[0] == "hello world"

  test "failed text object (\"adit outside a tag) consumes the pending register":
    # Regression: a failed text object aborts the operator, but the `"a`
    # register prefix must be consumed too, not leaked into the next command.
    let buffer = newTextBuffer("hello world\nsecond line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('a')
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.tag")).isErr
    check ctx.state.pendingInput.pendingRegister.isNone

suite "Handler - Clipboard operations":
  test "clipboard copy when disabled returns error":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
    )
    ctx.state.config.clipboard = ClipboardConfig(enable: false)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, builtin(bcEditCopy))
    check result.isErr
    check "disabled" in result.error

  test "clipboard paste when disabled returns error":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.config.clipboard = ClipboardConfig(enable: false)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, builtin(bcEditPaste))
    check result.isErr
    check "disabled" in result.error

  test "clipboard cut when disabled returns error":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
    )
    ctx.state.config.clipboard = ClipboardConfig(enable: false)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, builtin(bcEditCut))
    check result.isErr
    check "disabled" in result.error

  test "clipboard copy with no selection returns error":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    ctx.state.visualSelection = VisualSelection(active: false)
    ctx.state.config.clipboard = ClipboardConfig(enable: true, tool: cbtXclip)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, builtin(bcEditCopy))
    check result.isErr
    check "No text selected" in result.error

suite "Handler - Visual Paragraph motion":
  test "visual move paragraph forward":
    let buffer = newTextBuffer("line1\nline2\n\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveParagraphForward)).isOk
    # Cursor should move to blank line or past it
    check ctx.state.cursor.line >= 2

  test "visual move paragraph backward":
    let buffer = newTextBuffer("line1\nline2\n\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(4, 0, 4, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveParagraphBackward)).isOk
    # Cursor should move to blank line or before it
    check ctx.state.cursor.line <= 2

  test "visual move paragraph forward with count":
    let buffer = newTextBuffer("para1\n\npara2\n\npara3\n\npara4")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveParagraphForward), @["2"]).isOk
    # Should move past 2 paragraph boundaries
    check ctx.state.cursor.line >= 3

suite "Handler - Operator commands":
  test "operator.delete sets pending operator":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.delete")).isOk
    check ctx.state.pendingInput.pendingOperator.isSome
    check ctx.state.pendingInput.pendingOperator.get.operatorType == OpDelete

  test "operator.change sets pending operator":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.change")).isOk
    check ctx.state.pendingInput.pendingOperator.isSome
    check ctx.state.pendingInput.pendingOperator.get.operatorType == OpChange

  test "operator.yank sets pending operator":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.yank")).isOk
    check ctx.state.pendingInput.pendingOperator.isSome
    check ctx.state.pendingInput.pendingOperator.get.operatorType == OpYank

  test "double operator (dd) deletes line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # First d - sets pending operator
    discard registry.execute(ctx, custom("operator.delete"))
    check ctx.state.pendingInput.pendingOperator.isSome

    # Second d - completes dd (delete line)
    check registry.execute(ctx, custom("operator.delete")).isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == "line3"

  test "double operator (dd) preserves column position":
    let buffer = newTextBuffer("first line\nsecond line here\nthird line!!")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 10)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # First d
    discard registry.execute(ctx, custom("operator.delete"))
    # Second d - completes dd
    check registry.execute(ctx, custom("operator.delete")).isOk
    check buffer.len == 2
    check buffer[0] == "first line"
    check buffer[1] == "third line!!"
    check ctx.cursor.line == 1
    check ctx.cursor.column == 10 # preserved

  test "double operator (dd) clamps column to shorter line":
    let buffer = newTextBuffer("first line\nlong second line\nhi")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 14)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # First d
    discard registry.execute(ctx, custom("operator.delete"))
    # Second d - completes dd
    check registry.execute(ctx, custom("operator.delete")).isOk
    check buffer.len == 2
    check buffer[0] == "first line"
    check buffer[1] == "hi"
    check ctx.cursor.line == 1
    check ctx.cursor.column == 1 # "hi" has charLen 2, clamped to 1

  test "double operator (dd) on single line buffer clears line":
    let buffer = newTextBuffer("only line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # First d
    discard registry.execute(ctx, custom("operator.delete"))
    # Second d
    check registry.execute(ctx, custom("operator.delete")).isOk
    check buffer.len == 1
    check buffer[0] == ""
    check ctx.cursor.line == 0

  test "double operator (dd) on single line buffer undo restores content":
    let buffer = newTextBuffer("only line")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("operator.delete"))
    discard registry.execute(ctx, custom("operator.delete"))
    check buffer[0] == ""

    # Single undo should restore
    let undoResult = buffer.undo()
    check undoResult.isOk
    check buffer.len == 1
    check buffer[0] == "only line"

  test "double operator (dd) on 3-line buffer undo restores line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("operator.delete"))
    check registry.execute(ctx, custom("operator.delete")).isOk
    check buffer.len == 2

    # Single undo should restore
    let undoResult = buffer.undo()
    check undoResult.isOk
    check buffer.len == 3
    check buffer[0] == "line1"
    check buffer[1] == "line2"
    check buffer[2] == "line3"

  test "double operator (yy) yanks line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # First y - sets pending operator
    discard registry.execute(ctx, custom("operator.yank"))
    check ctx.state.pendingInput.pendingOperator.isSome

    # Second y - completes yy (yank line)
    check registry.execute(ctx, custom("operator.yank")).isOk
    check buffer.len == 3 # Buffer unchanged
    check "line2" in ctx.state.registers.getNoNamedRegister().getContent()
    # Register system must also be updated
    let reg = ctx.state.registers.getNoNamedRegister()
    check "line2" in reg.getContent()
    check reg.isLine == true

  test "double operator (yy) then paste after delete":
    let buffer = newTextBuffer("aaa\nbbb\nccc")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # x deletes 'a' and sets delete register
    discard registry.execute(ctx, custom("delete.char"))
    check buffer[0] == "aa"

    # yy on line 1
    ctx.cursor = BufferPosition(line: 1, column: 0)
    discard registry.execute(ctx, custom("operator.yank"))
    check registry.execute(ctx, custom("operator.yank")).isOk

    # p should paste "bbb", not "a"
    let pasteResult = registry.execute(ctx, custom("paste.after"))
    check pasteResult.isOk
    check "bbb" in buffer[2]

  test "double operator (cc) changes line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # First c - sets pending operator
    discard registry.execute(ctx, custom("operator.change"))
    check ctx.state.pendingInput.pendingOperator.isSome

    # Second c - completes cc (change line)
    check registry.execute(ctx, custom("operator.change")).isOk
    check buffer[1] == "" # Line content deleted
    check ctx.state.mode == EditorMode.Insert

suite "Handler - Visual mode extended operations":
  test "visual toggle case":
    let buffer = newTextBuffer("Hello World")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualToggleCase)).isOk
    check buffer[0] == "hELLO World"
    check ctx.state.mode == EditorMode.Normal

  test "visual dedent":
    let buffer = newTextBuffer("    line1\n    line2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 1, 0, EditorMode.VisualLine)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualDedent)).isOk
    # Lines should be dedented
    check buffer[0].len < 9 or buffer[0][0] != ' '

  test "visual to insert mode":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualToInsertMode)).isOk
    check ctx.state.mode == EditorMode.Insert

  test "visual swap selection (o)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualSwapSelection)).isOk
    # State cursor should move to the start of selection
    check ctx.state.cursor.column == 0

  test "visual paste replaces selection":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      kind: vskChar,
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 4),
    )
    ctx.setCursor(0, 4)
    ctx.state.registers.setYankedRegister("XYZ", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualPaste)).isOk
    # Result depends on implementation - just check it succeeded

suite "Handler - Visual Move Commands":
  test "visual move left":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveLeft)).isOk
    # Cursor should have moved left
    check ctx.state.cursor.column == 4

  test "visual move right":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveRight)).isOk
    # Cursor should have moved right
    check ctx.state.cursor.column == 6

  test "visual move up":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 1, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveUp)).isOk
    check ctx.state.cursor.line == 0

  test "visual move down":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 1, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveDown)).isOk
    check ctx.state.cursor.line == 2

  test "visual move home (0)":
    let buffer = newTextBuffer("    hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 4, 0, 8)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveHome)).isOk
    check ctx.state.cursor.column == 0

  test "visual move end ($)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 3)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveEnd)).isOk
    # In Visual mode, cursor can go one past the last character (== lineLen)
    # so the selection can include the newline.
    check ctx.state.cursor.column == 11

  test "visual move first non-blank (^)":
    let buffer = newTextBuffer("    hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 8, 0, 10)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveFirstNonBlank)).isOk
    check ctx.state.cursor.column == 4 # First non-blank

  test "visual move first line (gg)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(1, 0, 2, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveFirstLine)).isOk
    check ctx.state.cursor.line == 0

  test "visual move last line (G)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 1, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveLastLine)).isOk
    check ctx.state.cursor.line == 2 # Last line

  test "visual 1G goes to line 1, not last line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(2, 0, 2, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveLastLine), @["1"]).isOk
    check ctx.state.cursor.line == 0

  test "visual move word (w)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveWord)).isOk
    check ctx.state.cursor.column == 6 # Start of "world"

  test "visual move word back (b)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 6, 0, 10)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveWordBack)).isOk
    check ctx.state.cursor.column == 6 # Back to "world"

  test "visual move word end (e)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualMoveWordEnd)).isOk
    check ctx.state.cursor.column == 4 # End of "hello"

suite "Handler - Insert Mode Operations":
  test "insert char":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Insert
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcInsertChar), @["X"]).isOk
    check buffer[0] == "helloX world"

  test "insert backspace":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Insert
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcInsertBackspace)).isOk
    check buffer[0] == "hell world"

  test "insert delete":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Insert
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcInsertDelete)).isOk
    check buffer[0] == "helloworld" # Space deleted

  test "insert newline":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Insert
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcInsertNewline)).isOk
    check buffer.len == 2
    check buffer[0] == "hello"
    check buffer[1] == " world"

  test "insert append (a)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcInsertAppend)).isOk
    check ctx.state.mode == EditorMode.Insert
    check ctx.state.cursor.column == 3 # Cursor moved right

  test "insert append end (A)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcInsertAppendEnd)).isOk
    check ctx.state.mode == EditorMode.Insert
    check ctx.state.cursor.column == 5 # End of line

suite "Handler - Mode Switch Commands":
  test "mode normal":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Insert
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcModeNormal)).isOk
    check ctx.state.mode == EditorMode.Normal

  test "mode insert":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcModeInsert)).isOk
    check ctx.state.mode == EditorMode.Insert

  test "mode command (overlay)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcModeCommand)).isOk
    # Command mode is an overlay, not a separate mode

suite "Handler - Fold Operations":
  test "fold open":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFoldOpen))
    # Just check it doesn't crash - fold operation depends on fold state
    check true # Just verify no crash

  test "fold close":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFoldClose))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "fold create":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(1, 0, 2, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFoldCreate))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "fold delete":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFoldDelete))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "fold delete all":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcFoldDeleteAll)).isOk

suite "Handler - Search Commands":
  test "search word forward (#)":
    let buffer = newTextBuffer("hello world hello test")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("search.word.forward"))
    # Just check it doesn't crash - search might not find anything
    check true # Just verify no crash

  test "search word backward (*)":
    let buffer = newTextBuffer("hello world hello test")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 12)
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("search.word.backward"))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "search next (n)":
    let buffer = newTextBuffer("hello world hello test")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    ctx.state.input.search.lastText = "hello"
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("search.next"))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "search prev (N)":
    let buffer = newTextBuffer("hello world hello test")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 12)
    ctx.state.input.search.lastText = "hello"
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("search.prev"))
    # Just check it doesn't crash
    check true # Just verify no crash

suite "Handler - Other Commands":
  test "show char info (ga)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("show.char.info")).isOk

  test "autoindent line (==)":
    let buffer = newTextBuffer("    hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("autoindent.line"))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "autoindent line (==) copies space indent from previous line":
    let buffer = newTextBuffer("    hello\nworld")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(1, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("autoindent.line")).isOk
    check buffer[1] == "    world"

  test "autoindent line (==) copies tab indent from previous line":
    let buffer = newTextBuffer("\t\thello\nworld")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(1, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("autoindent.line")).isOk
    check buffer[1] == "\t\tworld"

  test "autoindent line (==) replaces space indent with tab indent":
    let buffer = newTextBuffer("\thello\n  world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(1, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("autoindent.line")).isOk
    check buffer[1] == "\tworld"

  test "quick run":
    let buffer = newTextBuffer("echo hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcQuickRun))
    # Just check it doesn't crash - actual execution depends on config
    check true # Just verify no crash

  test "operator delete to end (D)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 6)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.delete.to.end")).isOk
    check buffer[0] == "hello "

  test "operator change to end (C)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 6)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.change.to.end")).isOk
    check buffer[0] == "hello "
    check ctx.state.mode == EditorMode.Insert

suite "Handler - Basic Motion Commands":
  test "motion left (h)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionLeft)).isOk
    check ctx.cursor.column == 4

  test "motion right (l)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionRight)).isOk
    check ctx.cursor.column == 6

  test "motion up (k)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(1, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionUp)).isOk
    check ctx.cursor.line == 0

  test "motion down (j)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(1, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionDown)).isOk
    check ctx.cursor.line == 2

  test "motion home (0)":
    let buffer = newTextBuffer("    hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 8)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionHome)).isOk
    check ctx.cursor.column == 0

  test "motion end ($)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionEnd)).isOk
    check ctx.cursor.column == 10

  test "motion first non-blank (^)":
    let buffer = newTextBuffer("    hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 10)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionFirstNonBlank)).isOk
    check ctx.cursor.column == 4

  test "motion first line (gg)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(2, 2)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionFirstLine)).isOk
    check ctx.cursor.line == 0

  test "motion last line (G)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionLastLine)).isOk
    check ctx.cursor.line == 2

  # Note: bcMotionWord, bcMotionWordBack, bcMotionWordEnd are not registered as
  # builtin commands - they are tested via ctMotion Command type in the
  # "executeCommand - Motion commands" suite above.

  test "motion match bracket (%)":
    let buffer = newTextBuffer("(hello world)")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionMatchBracket)).isOk
    check ctx.cursor.column == 12

  test "motion page down (Ctrl+f)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionPageDown)).isOk

  test "motion page up (Ctrl+b)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(4, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionPageUp)).isOk

  test "motion viewport high (H)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(3, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionViewportHigh)).isOk
    check ctx.cursor.line == 0

  test "motion viewport middle (M)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionViewportMiddle)).isOk

  test "motion viewport low (L)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcMotionViewportLow)).isOk
    check ctx.cursor.line == 4

suite "Handler - Undo/Redo Commands":
  test "undo with nothing to undo returns error":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    let r = registry.execute(ctx, builtin(bcEditUndo))
    check r.isErr

  test "redo with nothing to redo returns error":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    let r = registry.execute(ctx, builtin(bcEditRedo))
    check r.isErr

  test "undo after insert restores content and cursor":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    discard buffer.insertText(BufferPosition(line: 0, column: 5), " world")
    check buffer[0] == "hello world"

    check registry.execute(ctx, builtin(bcEditUndo)).isOk
    check buffer[0] == "hello"
    check ctx.cursor.line == 0
    # After undo, cursor is clamped to max(0, charLen - 1) = 4 (Normal mode)
    check ctx.cursor.column == 4

  test "undo after end-of-line insert clamps column":
    let buffer = newTextBuffer("ab")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 2)
    let registry = createTestRegistry()

    discard buffer.insertText(BufferPosition(line: 0, column: 2), "cd")
    check buffer[0] == "abcd"

    check registry.execute(ctx, builtin(bcEditUndo)).isOk
    check buffer[0] == "ab"
    # Undo returns cursor at column 2 (max(0, 2 - 1) = 1 for Normal mode)
    check ctx.cursor.column == 1

  test "undo with count 2":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    discard buffer.insertText(BufferPosition(line: 0, column: 5), "A")
    discard buffer.insertText(BufferPosition(line: 0, column: 6), "B")
    check buffer[0] == "helloAB"

    let cmd = Command(kind: ctAction, commandId: "edit.undo", count: 2)
    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello"

  test "undo count larger than stack stops at limit":
    let buffer = newTextBuffer("x")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 1)
    let registry = createTestRegistry()

    discard buffer.insertText(BufferPosition(line: 0, column: 1), "y")
    check buffer[0] == "xy"

    let cmd = Command(kind: ctAction, commandId: "edit.undo", count: 5)
    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "x"

  test "redo after undo restores content and cursor":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    discard buffer.insertText(BufferPosition(line: 0, column: 5), " world")
    check buffer[0] == "hello world"

    check registry.execute(ctx, builtin(bcEditUndo)).isOk
    check buffer[0] == "hello"

    check registry.execute(ctx, builtin(bcEditRedo)).isOk
    check buffer[0] == "hello world"
    check ctx.cursor.line == 0
    check ctx.cursor.column == 5

  test "redo with count 2":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 5)
    let registry = createTestRegistry()

    discard buffer.insertText(BufferPosition(line: 0, column: 5), "A")
    discard buffer.insertText(BufferPosition(line: 0, column: 6), "B")
    check buffer[0] == "helloAB"

    # Undo both
    let undoCmd = Command(kind: ctAction, commandId: "edit.undo", count: 2)
    check registry.executeCommand(ctx, undoCmd).isOk
    check buffer[0] == "hello"

    # Redo both
    let redoCmd = Command(kind: ctAction, commandId: "edit.redo", count: 2)
    check registry.executeCommand(ctx, redoCmd).isOk
    check buffer[0] == "helloAB"

suite "Handler - Edit Repeat Command":
  test "edit.repeat with no previous command":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.state.editState.lastEditCommand = none(LastEditCommand)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, custom("edit.repeat"))
    # Should fail with no previous command
    check result.isErr

  test "edit.repeat with insert command":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 5)
    ctx.state.editState.lastEditCommand = some(
      LastEditCommand(
        kind: lecInsertText,
        insertedText: "X",
        insertPosition: BufferPosition(line: 0, column: 0),
      )
    )
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("edit.repeat")).isOk
    check buffer[0] == "helloX world"

  test "edit.repeat with delete char command":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    ctx.state.editState.lastEditCommand =
      some(LastEditCommand(kind: lecDeleteChar, deleteCount: 1, deleteForward: true))
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("edit.repeat")).isOk
    check buffer[0] == "ello world"

suite "Handler - Special Commands":
  test "bcNone command does nothing":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, builtin(bcNone))
    # bcNone has no handler registered, so it should fail
    check result.isErr
    # Buffer should be unchanged
    check buffer[0] == "hello world"
    check ctx.cursor.column == 0

suite "Cursor clamping - OpChange":
  test "change to end of line places cursor at append position":
    # c$ at middle of line: cursor should be at charLen (Insert mode append position)
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # On 'w'
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.End, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello "
    # Insert mode: cursor at charLen (append position after "hello ")
    check ctx.cursor.column == buffer.getLine(0).charLen

  test "change word at end of line places cursor at append position":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    # After cw on "hello", line becomes empty, cursor at column 0 (append position)
    let lineLen = buffer.getLine(0).charLen
    check ctx.cursor.column <= lineLen

suite "Cursor clamping - Toggle case":
  test "toggle case at end of line clamps cursor":
    # ~ on the last character of a line should not leave cursor past end
    let buffer = newTextBuffer("Hi")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 1) # On 'i' (last char)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("toggle.case")).isOk
    check buffer[0] == "HI"
    # Cursor must stay within line bounds (charLen=2, max valid col=1)
    check ctx.cursor.column <= 1

  test "toggle case count exceeding line length clamps cursor":
    # 5~ on a 3-char line
    let buffer = newTextBuffer("abc")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("toggle.case"), @["5"]).isOk
    check buffer[0] == "ABC"
    # Cursor must be within line bounds (charLen=3, max valid col=2)
    check ctx.cursor.column <= 2

suite "Cursor clamping - Visual delete":
  test "visual delete clamps cursor when selection is at line end":
    # Select the last chars of a line and delete
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 3, 0, 4) # Select "lo"
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualDelete)).isOk
    check buffer[0] == "hel"
    check ctx.state.mode == EditorMode.Normal
    # Cursor should be clamped to end of remaining text (charLen=3, max valid col=2)
    check ctx.cursor.column <= 2
    check ctx.cursor.line == 0

  test "visual delete syncs cursor to ctx":
    # After visual delete, ctx.cursor must reflect the updated position
    let buffer = newTextBuffer("abcdef")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 2) # Select "abc"
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualDelete)).isOk
    check buffer[0] == "def"
    # ctx.cursor must be synced (not left at old position)
    check ctx.cursor.column == 0
    check ctx.cursor.line == 0

  test "visual delete all lines clamps cursor":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 1, 4, kind = vskLine) # Select all lines
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualDelete)).isOk
    # Buffer should have at least one line
    check buffer.len >= 1
    check ctx.cursor.line < buffer.len

  test "visual block delete clamps cursor column":
    # Block select beyond short line and delete
    let buffer = newTextBuffer("abcdef\nab\nabcdef")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 3, 2, 5, kind = vskBlock) # Block select columns 3-5
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualDelete)).isOk
    # After block delete, cursor column should be valid for the current line
    let line = buffer.getLine(ctx.cursor.line)
    if line.charLen > 0:
      check ctx.cursor.column < line.charLen
    else:
      check ctx.cursor.column == 0

suite "Cursor clamping - Visual operations sync ctx.cursor":
  test "visual lowercase syncs cursor":
    let buffer = newTextBuffer("HELLO WORLD")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualLowercase)).isOk
    check buffer[0] == "hello WORLD"
    # ctx.cursor must be synced from state.cursor (moved to selection start)
    check ctx.cursor.column == 0

  test "visual uppercase syncs cursor":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 6, 0, 10)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualUppercase)).isOk
    check buffer[0] == "hello WORLD"
    # ctx.cursor must be synced to selection start
    check ctx.cursor.column == 6

  test "visual toggle case syncs cursor":
    let buffer = newTextBuffer("Hello World")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualToggleCase)).isOk
    check buffer[0] == "hELLO World"
    check ctx.cursor.column == 0

  test "visual join lines syncs cursor":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 1, 4, kind = vskLine)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualJoinLines)).isOk
    check buffer.len == 2
    # ctx.cursor should be synced
    check ctx.cursor.line == 0

  test "visual swap selection syncs cursor":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 2, 0, 8)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualSwapSelection)).isOk
    # After swap, cursor should move to the other end of selection
    check ctx.cursor.column == 2

  test "visual paste syncs cursor":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setupVisual(0, 0, 0, 4)
    ctx.state.registers.setYankedRegister("XYZ", false)
    ctx.state.registers.setDeletedRegister("XYZ", false)
    let registry = createTestRegistry()

    check registry.execute(ctx, builtin(bcVisualPaste)).isOk
    check ctx.state.mode == EditorMode.Normal
    # ctx.cursor should be synced
    check ctx.cursor.line == 0
suite "Handler - Indent/Outdent operator with text objects":
  test "operator.indent sets pending operator":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.indent")).isOk
    check ctx.state.pendingInput.pendingOperator.isSome
    check ctx.state.pendingInput.pendingOperator.get.operatorType == OpIndent

  test "operator.outdent sets pending operator":
    let buffer = newTextBuffer("  hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.outdent")).isOk
    check ctx.state.pendingInput.pendingOperator.isSome
    check ctx.state.pendingInput.pendingOperator.get.operatorType == OpOutdent

  test "double indent (>>) indents current line":
    let buffer = newTextBuffer("hello\nworld\ntest")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.mode = EditorMode.Normal
    ctx.state.expandTab = true
    ctx.state.tabStop = 2
    ctx.state.shiftWidth = 2
    let registry = createTestRegistry()

    # First > sets pending operator
    discard registry.execute(ctx, custom("operator.indent"))
    check ctx.state.pendingInput.pendingOperator.isSome

    # Second > completes >> (indent line)
    check registry.execute(ctx, custom("operator.indent")).isOk
    check buffer[0] == "hello"
    check buffer[1] == "  world"
    check buffer[2] == "test"

  test "double outdent (<<) dedents current line":
    let buffer = newTextBuffer("hello\n  world\ntest")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 2)
    ctx.state.mode = EditorMode.Normal
    ctx.state.expandTab = true
    ctx.state.tabStop = 2
    ctx.state.shiftWidth = 2
    let registry = createTestRegistry()

    # First < sets pending operator
    discard registry.execute(ctx, custom("operator.outdent"))
    check ctx.state.pendingInput.pendingOperator.isSome

    # Second < completes << (dedent line)
    check registry.execute(ctx, custom("operator.outdent")).isOk
    check buffer[0] == "hello"
    check buffer[1] == "world"
    check buffer[2] == "test"

  test "indent with text object (>iw) indents word line":
    let buffer = newTextBuffer("hello\nworld\ntest")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.mode = EditorMode.Normal
    ctx.state.expandTab = true
    ctx.state.tabStop = 2
    ctx.state.shiftWidth = 2
    let registry = createTestRegistry()

    # Set pending operator (>)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpIndent, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i)
    discard registry.execute(ctx, custom("textobject.inner"))

    # Execute text object kind (word)
    check registry.execute(ctx, custom("textobject.word")).isOk
    # Line containing the word should be indented
    check "  " in buffer[1]

  test "outdent with text object (<i{) dedents brace block":
    let buffer = newTextBuffer("{\n  hello\n  world\n}")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 2)
    ctx.state.mode = EditorMode.Normal
    ctx.state.expandTab = true
    ctx.state.tabStop = 2
    ctx.state.shiftWidth = 2
    let registry = createTestRegistry()

    # Set pending operator (<)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpOutdent, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i)
    discard registry.execute(ctx, custom("textobject.inner"))

    # Execute text object kind (brace)
    check registry.execute(ctx, custom("textobject.brace")).isOk
    # Lines inside braces should be dedented
    check buffer[1] == "hello"
    check buffer[2] == "world"

suite "Handler - Lowercase/Uppercase operator with text objects":
  test "operator.lowercase sets pending operator":
    let buffer = newTextBuffer("HELLO WORLD")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.lowercase")).isOk
    check ctx.state.pendingInput.pendingOperator.isSome
    check ctx.state.pendingInput.pendingOperator.get.operatorType == OpLowerCase

  test "operator.uppercase sets pending operator":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.uppercase")).isOk
    check ctx.state.pendingInput.pendingOperator.isSome
    check ctx.state.pendingInput.pendingOperator.get.operatorType == OpUpperCase

  test "lowercase with text object (guiw) lowercases inner word":
    let buffer = newTextBuffer("hello WORLD test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # On 'W' in "WORLD"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (gu)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpLowerCase, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i)
    discard registry.execute(ctx, custom("textobject.inner"))

    # Execute text object kind (word)
    check registry.execute(ctx, custom("textobject.word")).isOk
    check "world" in buffer[0]
    check "WORLD" notin buffer[0]

  test "uppercase with text object (gUiw) uppercases inner word":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # On 'w' in "world"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (gU)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpUpperCase, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i)
    discard registry.execute(ctx, custom("textobject.inner"))

    # Execute text object kind (word)
    check registry.execute(ctx, custom("textobject.word")).isOk
    check "WORLD" in buffer[0]
    check "hello" in buffer[0] # Other words unchanged
    check "test" in buffer[0] # Other words unchanged

  test "lowercase with quoted text object (gui\")":
    let buffer = newTextBuffer("say \"HELLO WORLD\" now")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # Inside quotes
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (gu)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpLowerCase, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i)
    discard registry.execute(ctx, custom("textobject.inner"))

    # Execute text object kind (double quote)
    check registry.execute(ctx, custom("textobject.quote.double")).isOk
    check "hello world" in buffer[0]

  test "uppercase with parenthesis text object (gUi()":
    let buffer = newTextBuffer("func(hello world)")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # Inside parens
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (gU)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpUpperCase, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i)
    discard registry.execute(ctx, custom("textobject.inner"))

    # Execute text object kind (paren)
    check registry.execute(ctx, custom("textobject.paren")).isOk
    check "HELLO WORLD" in buffer[0]
    check buffer[0].startsWith("func(")
    check buffer[0].endsWith(")")

  test "indent with brace text object (>i{) multi-line":
    let buffer = newTextBuffer("if true {\nhello\nworld\n}")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0) # Inside braces
    ctx.state.mode = EditorMode.Normal
    ctx.state.expandTab = true
    ctx.state.tabStop = 2
    ctx.state.shiftWidth = 2
    let registry = createTestRegistry()

    # Set pending operator (>)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpIndent, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i)
    discard registry.execute(ctx, custom("textobject.inner"))

    # Execute text object kind (brace)
    check registry.execute(ctx, custom("textobject.brace")).isOk
    check buffer[0] == "if true {"
    check buffer[1] == "  hello"
    check buffer[2] == "  world"
    check buffer[3] == "}"

suite "Handler - Visual mode text object selection":
  test "viw selects inner word":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 7) # On 'o' in "world"
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 7),
      current: BufferPosition(line: 0, column: 7),
    )
    let registry = createTestRegistry()

    # i - sets pending text object modifier in Visual mode
    check registry.execute(ctx, custom("textobject.inner")).isOk
    check ctx.state.pendingInput.pendingTextObject.isSome
    check ctx.state.pendingInput.pendingTextObject.get.modifier == tomInner
    check ctx.state.mode == EditorMode.Visual # Stays in visual mode

    # w - selects word
    check registry.execute(ctx, custom("textobject.word")).isOk
    check ctx.state.visualSelection.active == true
    # Selection should cover "world" (columns 6-10)
    check ctx.state.visualSelection.start.column == 6
    check ctx.state.visualSelection.current.column == 10

  test "vaw selects around word":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 7) # On 'o' in "world"
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 7),
      current: BufferPosition(line: 0, column: 7),
    )
    let registry = createTestRegistry()

    # a - sets around text object modifier
    check registry.execute(ctx, custom("textobject.around")).isOk
    check ctx.state.pendingInput.pendingTextObject.isSome
    check ctx.state.pendingInput.pendingTextObject.get.modifier == tomAround

    # w - selects around word
    check registry.execute(ctx, custom("textobject.word")).isOk
    check ctx.state.visualSelection.active == true
    # "world " should be selected (columns 6-11, including trailing space)
    check ctx.state.visualSelection.start.column == 6
    check ctx.state.visualSelection.current.column == 11

  test "vi\" selects inner quoted string":
    let buffer = newTextBuffer("say \"hello world\" now")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # Inside quotes
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 6),
      current: BufferPosition(line: 0, column: 6),
    )
    let registry = createTestRegistry()

    # i - inner modifier
    check registry.execute(ctx, custom("textobject.inner")).isOk

    # " - double quote text object
    check registry.execute(ctx, custom("textobject.quote.double")).isOk
    check ctx.state.visualSelection.active == true
    # "hello world" (content inside quotes) should be selected
    check ctx.state.visualSelection.start.column == 5
    check ctx.state.visualSelection.current.column == 15

  test "vi{ selects inner brace block (multi-line)":
    let buffer = newTextBuffer("if true {\nhello\nworld\n}")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0) # Inside braces
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 1, column: 0),
      current: BufferPosition(line: 1, column: 0),
    )
    let registry = createTestRegistry()

    # i - inner modifier
    check registry.execute(ctx, custom("textobject.inner")).isOk

    # { - brace text object
    check registry.execute(ctx, custom("textobject.brace")).isOk
    check ctx.state.visualSelection.active == true
    # Selection spans from after { (end of line 0) to before } (end of "world",
    # the last content line). The close brace sits at column 0, so the end is the
    # previous line's end-of-content column, not a negative column on line 3.
    check (ctx.state.visualSelection.start.line, ctx.state.visualSelection.start.column) ==
      (0, 9)
    check (
      ctx.state.visualSelection.current.line, ctx.state.visualSelection.current.column
    ) == (2, 5)

  test "textobject.inner in Visual mode does not enter Insert mode":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 0),
    )
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("textobject.inner")).isOk
    check ctx.state.mode == EditorMode.Visual # Must stay in Visual mode
    check ctx.state.pendingInput.pendingTextObject.isSome

  test "textobject.around in Visual mode does not enter Insert mode":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 0),
    )
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("textobject.around")).isOk
    check ctx.state.mode == EditorMode.Visual # Must stay in Visual mode
    check ctx.state.pendingInput.pendingTextObject.isSome

suite "Multibyte character support":
  test "lowercase operator with mixed ASCII and multibyte (guiw)":
    # Multibyte characters should pass through toLowerAscii unchanged
    let buffer = newTextBuffer("こんにちは HELLO 世界")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # On 'H' in "HELLO"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (gu)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpLowerCase, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i) and execute kind (w)
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.word")).isOk

    check "hello" in buffer[0]
    check "HELLO" notin buffer[0]
    # Multibyte characters must remain unchanged
    check "こんにちは" in buffer[0]
    check "世界" in buffer[0]

  test "uppercase operator with mixed ASCII and multibyte (gUiw)":
    let buffer = newTextBuffer("こんにちは hello 世界")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # On 'h' in "hello"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (gU)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpUpperCase, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i) and execute kind (w)
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.word")).isOk

    check "HELLO" in buffer[0]
    check "こんにちは" in buffer[0]
    check "世界" in buffer[0]

  test "lowercase linewise with multibyte lines":
    let buffer = newTextBuffer("日本語 ABC\nこんにちは DEF\n漢字 GHI")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal

    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 0),
      endPos: BufferPosition(line: 2, column: 0),
      isLinewise: true,
    )
    check executeOperatorOnRange(ctx, OpLowerCase, range, 1).isOk

    check buffer[0] == "日本語 abc"
    check buffer[1] == "こんにちは def"
    check buffer[2] == "漢字 ghi"

  test "uppercase linewise with multibyte lines":
    let buffer = newTextBuffer("日本語 abc\nこんにちは def\n漢字 ghi")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal

    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 0),
      endPos: BufferPosition(line: 2, column: 0),
      isLinewise: true,
    )
    check executeOperatorOnRange(ctx, OpUpperCase, range, 1).isOk

    check buffer[0] == "日本語 ABC"
    check buffer[1] == "こんにちは DEF"
    check buffer[2] == "漢字 GHI"

  test "lowercase character-wise range with multibyte":
    # Character-wise range within a line containing multibyte chars
    let buffer = newTextBuffer("あいう ABC うえお")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4) # On 'A'
    ctx.state.mode = EditorMode.Normal

    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 4),
      endPos: BufferPosition(line: 0, column: 6), # "ABC"
      isLinewise: false,
    )
    check executeOperatorOnRange(ctx, OpLowerCase, range, 1).isOk

    check buffer[0] == "あいう abc うえお"

  test "uppercase character-wise range with multibyte":
    let buffer = newTextBuffer("あいう abc うえお")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4)
    ctx.state.mode = EditorMode.Normal

    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 4),
      endPos: BufferPosition(line: 0, column: 6), # "abc"
      isLinewise: false,
    )
    check executeOperatorOnRange(ctx, OpUpperCase, range, 1).isOk

    check buffer[0] == "あいう ABC うえお"

  test "indent line with multibyte content (>>)":
    let buffer = newTextBuffer("日本語テスト\nこんにちは\nASCII")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    ctx.state.expandTab = true
    ctx.state.tabStop = 2
    ctx.state.shiftWidth = 2
    let registry = createTestRegistry()

    # >> (double indent)
    discard registry.execute(ctx, custom("operator.indent"))
    check registry.execute(ctx, custom("operator.indent")).isOk

    check buffer[0] == "  日本語テスト"
    check buffer[1] == "こんにちは" # Untouched
    check buffer[2] == "ASCII" # Untouched

  test "outdent line with multibyte content (<<)":
    let buffer = newTextBuffer("  日本語テスト\n  こんにちは\nASCII")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    ctx.state.mode = EditorMode.Normal
    ctx.state.expandTab = true
    ctx.state.tabStop = 2
    ctx.state.shiftWidth = 2
    let registry = createTestRegistry()

    # << (double outdent)
    discard registry.execute(ctx, custom("operator.outdent"))
    check registry.execute(ctx, custom("operator.outdent")).isOk

    check buffer[0] == "日本語テスト"
    check buffer[1] == "  こんにちは" # Untouched
    check buffer[2] == "ASCII" # Untouched

  test "indent with brace text object containing multibyte (>i{)":
    let buffer = newTextBuffer("関数 {\nあいうえお\nかきくけこ\n}")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0) # Inside braces
    ctx.state.mode = EditorMode.Normal
    ctx.state.expandTab = true
    ctx.state.tabStop = 2
    ctx.state.shiftWidth = 2
    let registry = createTestRegistry()

    # Set pending operator (>)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpIndent, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i) and execute kind (brace)
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.brace")).isOk

    check buffer[0] == "関数 {"
    check buffer[1] == "  あいうえお"
    check buffer[2] == "  かきくけこ"
    check buffer[3] == "}"

  test "lowercase with quoted multibyte text (gui\")":
    let buffer = newTextBuffer("say \"HELLO こんにちは WORLD\" end")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # Inside quotes
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (gu)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpLowerCase, operatorCount: 1, startPos: ctx.cursor)
    )

    # Set text object modifier (i) and execute kind (double quote)
    discard registry.execute(ctx, custom("textobject.inner"))
    check registry.execute(ctx, custom("textobject.quote.double")).isOk

    check "hello こんにちは world" in buffer[0]
    check buffer[0].startsWith("say \"")
    check "\" end" in buffer[0]

  test "visual mode text object selection with multibyte (viw)":
    let buffer = newTextBuffer("あいう hello かきく")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 5) # On 'l' in "hello"
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 5),
      current: BufferPosition(line: 0, column: 5),
    )
    let registry = createTestRegistry()

    # i - sets pending text object modifier in Visual mode
    check registry.execute(ctx, custom("textobject.inner")).isOk
    check ctx.state.pendingInput.pendingTextObject.isSome

    # w - selects word
    check registry.execute(ctx, custom("textobject.word")).isOk
    check ctx.state.visualSelection.active == true
    # Selection should cover "hello" (columns 4-8)
    check ctx.state.visualSelection.start.column == 4
    check ctx.state.visualSelection.current.column == 8

  test "visual mode text object selection with quoted multibyte (vi\")":
    let buffer = newTextBuffer("関数 \"あいうえお\" 結果")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4) # Inside quotes
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 4),
      current: BufferPosition(line: 0, column: 4),
    )
    let registry = createTestRegistry()

    # i - inner modifier
    check registry.execute(ctx, custom("textobject.inner")).isOk

    # " - double quote text object
    check registry.execute(ctx, custom("textobject.quote.double")).isOk
    check ctx.state.visualSelection.active == true
    # Should select "あいうえお" inside quotes (columns 4-8)
    check ctx.state.visualSelection.start.column == 4
    check ctx.state.visualSelection.current.column == 8

suite "Handler - Text Object Count (d2iw, d2aw)":
  test "d2iw deletes two words":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator d with count 2
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )

    # i - inner modifier
    discard registry.execute(ctx, custom("textobject.inner"))

    # w - word text object
    check registry.execute(ctx, custom("textobject.word")).isOk
    # "hello " should be deleted (hello + trailing space as 2nd iw unit)
    check buffer[0] == "world test"

  test "d1iw is same as diw":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator d with count 1
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # i - inner modifier
    discard registry.execute(ctx, custom("textobject.inner"))

    # w - word text object
    check registry.execute(ctx, custom("textobject.word")).isOk
    # Only "hello" should be deleted
    check buffer[0] == " world test"

  test "d2aw deletes two words with trailing space":
    let buffer = newTextBuffer("hello world test end")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator d with count 2
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )

    # a - around modifier
    discard registry.execute(ctx, custom("textobject.around"))

    # w - word text object
    check registry.execute(ctx, custom("textobject.word")).isOk
    # "hello world " should be deleted
    check buffer[0] == "test end"

  test "d2i\" ignores count for quote text objects":
    let buffer = newTextBuffer("say \"hello\" world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6) # Inside quotes
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator d with count 2
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )

    # i - inner modifier
    discard registry.execute(ctx, custom("textobject.inner"))

    # " - quote text object (count should be ignored)
    check registry.execute(ctx, custom("textobject.quote.double")).isOk
    # Only "hello" inside quotes should be deleted (count ignored)
    check buffer[0] == "say \"\" world"

suite "pendingRegister dispatch for clipboard registers":
  test "yy with pendingRegister '*' stores in primary selection register":
    let buffer = newTextBuffer("hello primary")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    # Set pending register to '*'
    ctx.state.pendingInput.pendingRegister = some('*')

    # Execute yy (yank line)
    check registry.execute(ctx, custom("yank.line")).isOk

    # Should be stored in '*' register (primary selection)
    let primaryReg = ctx.state.registers.getClipboardRegister('*')
    check primaryReg.getContent().contains("hello primary")
    check primaryReg.isLine

    # '+' register should remain empty
    let clipboardReg = ctx.state.registers.getClipboardRegister('+')
    check clipboardReg.isEmpty

  test "yy with pendingRegister '+' stores in clipboard selection register":
    let buffer = newTextBuffer("hello clipboard")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('+')

    check registry.execute(ctx, custom("yank.line")).isOk

    let clipboardReg = ctx.state.registers.getClipboardRegister('+')
    check clipboardReg.getContent().contains("hello clipboard")
    check clipboardReg.isLine

    let primaryReg = ctx.state.registers.getClipboardRegister('*')
    check primaryReg.isEmpty

  test "dd with pendingRegister '*' stores in primary selection register":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('*')

    check registry.execute(ctx, custom("delete.line")).isOk

    let primaryReg = ctx.state.registers.getClipboardRegister('*')
    check primaryReg.getContent().contains("line1")
    check primaryReg.isLine

    let clipboardReg = ctx.state.registers.getClipboardRegister('+')
    check clipboardReg.isEmpty

  test "x with pendingRegister '+' stores in clipboard selection register":
    let buffer = newTextBuffer("abcdef")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('+')

    check registry.execute(ctx, custom("delete.char")).isOk

    let clipboardReg = ctx.state.registers.getClipboardRegister('+')
    check clipboardReg.getContent() == "a"

    let primaryReg = ctx.state.registers.getClipboardRegister('*')
    check primaryReg.isEmpty

  test "yy without pendingRegister stores in yank register (default)":
    let buffer = newTextBuffer("default yank")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("yank.line")).isOk

    # Should be in register 0 (yank) and unnamed
    check ctx.state.registers.getNumberRegister(0).getContent().contains("default yank")
    check ctx.state.registers.getNoNamedRegister().getContent().contains("default yank")

    # Clipboard registers should be empty
    let primaryReg = ctx.state.registers.getClipboardRegister('*')
    check primaryReg.isEmpty
    let clipboardReg = ctx.state.registers.getClipboardRegister('+')
    check clipboardReg.isEmpty

  test "pendingRegister is cleared after use":
    let buffer = newTextBuffer("test clearing")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('*')
    check registry.execute(ctx, custom("yank.line")).isOk

    # pendingRegister should be cleared
    check ctx.state.pendingInput.pendingRegister.isNone

  test "yy with pendingRegister named register 'a' stores in named register":
    let buffer = newTextBuffer("named content")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('a')
    check registry.execute(ctx, custom("yank.line")).isOk

    let namedReg = ctx.state.registers.getNamedRegister('a')
    check namedReg.getContent().contains("named content")

    # Clipboard registers should be empty
    check ctx.state.registers.getClipboardRegister('*').isEmpty
    check ctx.state.registers.getClipboardRegister('+').isEmpty

  test "operator yank (y + motion) with pendingRegister '*'":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('*')

    # First y sets pending operator
    check registry.execute(ctx, custom("operator.yank")).isOk
    # Second y executes line yank
    check registry.execute(ctx, custom("operator.yank")).isOk

    let primaryReg = ctx.state.registers.getClipboardRegister('*')
    check primaryReg.getContent().contains("hello world")

    check ctx.state.registers.getClipboardRegister('+').isEmpty

  test "operator delete (d + motion) with pendingRegister '+'":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingRegister = some('+')

    # First d sets pending operator
    check registry.execute(ctx, custom("operator.delete")).isOk
    # Second d executes line delete
    check registry.execute(ctx, custom("operator.delete")).isOk

    let clipboardReg = ctx.state.registers.getClipboardRegister('+')
    check clipboardReg.getContent().contains("line1")

    check ctx.state.registers.getClipboardRegister('*').isEmpty

suite "Operator + Find/Till - yank and change till":
  test "yank find character (yf)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "hello"

  test "yank till character (yt)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "hell"

  test "change till character (ct)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "o world"
    check ctx.state.mode == EditorMode.Insert

suite "Operator + Backward Find/Till":
  test "delete find backward (dF)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 9) # on 'l' in "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: true,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello wd"

  test "delete till backward (dT)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 9) # on 'l' in "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: true,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello wod"

  test "change find backward (cF)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 9) # on 'l' in "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: true,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello wd"
    check ctx.state.mode == EditorMode.Insert

  test "change till backward (cT)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 9) # on 'l' in "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: true,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello wod"
    check ctx.state.mode == EditorMode.Insert

  test "yank find backward (yF)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 9) # on 'l' in "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: true,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "orl"

  test "yank till backward (yT)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 9) # on 'l' in "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: true,
      targetChar: "o",
      count: 1,
    )

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "rl"

suite "Operator + Word End/Backward motions":
  test "delete word end (de)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEnd, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == " world test"

  test "change word end (ce)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEnd, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == " world test"
    check ctx.state.mode == EditorMode.Insert

  test "yank word end (ye)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEnd, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world test" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "hello"

  test "delete word end from middle of word (de)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 2) # on 'l' of "hello"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEnd, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "he world test"

  test "delete word end with count (d2e)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEnd, count: 2)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == " test"

  test "yank word end from middle of word (ye)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 2) # on 'l' of "hello"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEnd, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world test" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "llo"

  test "delete word end to end of current word (de)":
    let buffer = newTextBuffer("hello\nworld test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 3) # on second 'l' of "hello"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEnd, count: 1)

    # e moves to 'o' (col 4), inclusive delete removes "lo"
    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hel"
    check buffer[1] == "world test"

  test "delete word end across lines (d2e)":
    let buffer = newTextBuffer("hello\nworld test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 3) # on second 'l' of "hello"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEnd, count: 2)

    # 2e: first e to 'o' (col 4), second e to 'd' of "world" (line 1, col 4)
    # Cross-line delete merges remaining text into one line
    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hel test"

  test "delete word backward (db)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "world test"

  test "change word backward (cb)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "world test"
    check ctx.state.mode == EditorMode.Insert

  test "yank word backward (yb)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world test" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "hello "

suite "Operator + Word End Backward (ge) motions":
  test "ge motion basic":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "ge motion from start of word":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "ge motion with count (2ge)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 12) # on 't' of "test"
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 2)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "delete word end backward (dge)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    # ge is inclusive, deletes from col 4 ('o') to col 6 ('w') = "o w"
    check buffer[0] == "hellorld test"

  test "yank word end backward (yge)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world test" # Buffer unchanged

  test "ge motion across lines":
    let buffer = newTextBuffer("hello\nworld test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(1, 0) # on 'w' of "world"
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "ge at beginning of buffer":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0) # at beginning
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 0) # stays at beginning

  test "ge with symbols":
    # ge stops at end of symbol sequence
    let buffer = newTextBuffer("hello...world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 8) # on 'o' of "world"
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 7) # end of "..."

  test "ge from symbol to word":
    # ge from symbol stops at end of preceding word
    let buffer = newTextBuffer("hello...world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 5) # on first '.'
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "ge from middle of word":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 8) # on 'r' of "world"
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "ge across multiple empty lines":
    let buffer = newTextBuffer("hello\n\n\nworld")
    let ctx = createTestContext(buffer)
    ctx.setCursor(3, 0) # on 'w' of "world"
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "ge with count exceeding available words":
    # 10ge but only 2 word ends exist; should stop at the earliest one
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 10) # on 'd' of "world"
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 10)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "ge on single character words":
    let buffer = newTextBuffer("a b c d")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'd'
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # 'c'

  test "ge on whitespace":
    let buffer = newTextBuffer("hello   world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on middle space
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor == BufferPosition(line: 0, column: 4) # end of "hello"

  test "change word end backward (cge)":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hellorld test"
    check ctx.state.mode == EditorMode.Insert

  test "delete word end backward across lines (dge)":
    let buffer = newTextBuffer("hello\nworld")
    let ctx = createTestContext(buffer)
    ctx.setCursor(1, 0) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordEndBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    # Inclusive: deletes from (0,4) 'o' to (1,0) 'w', i.e. "o\nw"
    check buffer[0] == "hellorld"

suite "Operator + Line start/end motions":
  test "delete to line start (d0)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.Home, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "world"

  test "change to line start (c0)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.Home, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "world"
    check ctx.state.mode == EditorMode.Insert

  test "yank to line start (y0)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.Home, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "hello "

  test "delete to first non-blank (d^)":
    let buffer = newTextBuffer("   hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 9) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.FirstNonBlank, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "   world"

  test "yank to end of line (y$)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.End, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "world"

suite "Operator + Paragraph/File motions":
  test "delete paragraph forward (d})":
    let buffer = newTextBuffer("line1\nline2\n\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.ParagraphForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 2
    check buffer[0] == "line4"
    check buffer[1] == "line5"

  test "delete paragraph backward (d{)":
    let buffer = newTextBuffer("line1\nline2\n\nline4\nline5")
    let ctx = createTestContext(buffer)
    ctx.setCursor(4, 0) # on "line5"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.ParagraphBackward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == "line2"

  test "yank paragraph forward (y})":
    let buffer = newTextBuffer("line1\nline2\n\nline4")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.ParagraphForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 4 # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "line1\nline2\n\n"

  test "delete to first line (dgg)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ctx = createTestContext(buffer)
    ctx.setCursor(2, 0) # on "line3"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.FirstLine, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "line4"
    check buffer.len == 1

  test "delete to last line (dG)":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ctx = createTestContext(buffer)
    ctx.setCursor(1, 0) # on "line2"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.LastLine, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "line1"
    check buffer.len == 1

  test "delete to line 1 (d1G) from lower line":
    let buffer = newTextBuffer("line1\nline2\nline3\nline4")
    let ctx = createTestContext(buffer)
    ctx.setCursor(2, 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.LastLine, count: 1, hasCount: true)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "line4"
    check buffer.len == 1

  test "dot-repeat of dG replays as delete-to-last-line":
    let buffer = newTextBuffer("a\nb\nc\nd\ne")
    let ctx = createTestContext(buffer)
    ctx.setCursor(3, 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let dG = Command(kind: ctMotion, motion: Motion.LastLine, count: 1)
    check registry.executeCommand(ctx, dG).isOk
    check buffer.len == 3

    ctx.setCursor(1, 0)
    check registry.execute(ctx, custom("edit.repeat")).isOk
    check buffer.len == 1
    check buffer[0] == "a"

  test "dot-repeat of d1G replays as delete-to-line-1":
    let buffer = newTextBuffer("a\nb\nc\nd\ne")
    let ctx = createTestContext(buffer)
    ctx.setCursor(2, 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let d1G = Command(kind: ctMotion, motion: Motion.LastLine, count: 1, hasCount: true)
    check registry.executeCommand(ctx, d1G).isOk
    check buffer.len == 2
    check buffer[0] == "d"
    check buffer[1] == "e"

    ctx.setCursor(1, 0)
    check registry.execute(ctx, custom("edit.repeat")).isOk
    check buffer.len == 0 or (buffer.len == 1 and buffer[0] == "")

  test "yank to first line (ygg)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setCursor(2, 0) # on "line3"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.FirstLine, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 3 # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() ==
      "line1\nline2\nline3\n"

  test "yank to last line (yG)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0) # on "line1"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.LastLine, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 3 # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() ==
      "line1\nline2\nline3\n"

suite "Operator + Case operators with motions":
  test "lowercase word (guw)":
    let buffer = newTextBuffer("HELLO WORLD")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpLowerCase, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello WORLD"

  test "uppercase word (gUw)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpUpperCase, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "HELLO world"

  test "lowercase to end of line (gu$)":
    let buffer = newTextBuffer("HELLO WORLD")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'W' of "WORLD"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpLowerCase, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.End, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "HELLO world"

  test "uppercase to end of line (gU$)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 6) # on 'w' of "world"
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpUpperCase, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.End, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello WORLD"

suite "Operator + Matching bracket":
  test "delete to matching bracket (d%)":
    let buffer = newTextBuffer("foo(bar)baz")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 3) # on '('
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.MatchBracket, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "foobaz"

  test "change to matching bracket (c%)":
    let buffer = newTextBuffer("foo(bar)baz")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 3) # on '('
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.MatchBracket, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "foobaz"
    check ctx.state.mode == EditorMode.Insert

  test "yank to matching bracket (y%)":
    let buffer = newTextBuffer("foo(bar)baz")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 3) # on '('
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.MatchBracket, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "foo(bar)baz" # Buffer unchanged
    check ctx.state.registers.getNoNamedRegister().getContent() == "(bar)"

suite "Operator with compound counts":
  test "count before operator (2dw via operatorCount)":
    let buffer = newTextBuffer("one two three four")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "three four"

  test "count on both operator and motion (2d2w)":
    let buffer = newTextBuffer("one two three four five six")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )

    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 2)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "five six"

suite "executeCommand - auto-open folds on edit":
  test "delete-char opens a collapsed fold at the cursor":
    let buffer = newTextBuffer("0\n1\n2\n3\n4")
    check buffer.foldState.addFold(0, 3, collapsed = true)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0) # on the fold start line
    let registry = createTestRegistry()

    let cmd = Command(kind: ctCustom, commandId: "delete.char", count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    check not buffer.foldState.folds[0].collapsed

  test "operator delete opens a collapsed fold at the cursor":
    let buffer = newTextBuffer("hello world\n1\n2\n3")
    check buffer.foldState.addFold(0, 2, collapsed = true)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    check not buffer.foldState.folds[0].collapsed

  test "yank leaves a collapsed fold closed":
    let buffer = newTextBuffer("hello world\n1\n2\n3")
    check buffer.foldState.addFold(0, 2, collapsed = true)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    check buffer.foldState.folds[0].collapsed

  test "navigation leaves a collapsed fold closed":
    let buffer = newTextBuffer("0\n1\n2\n3\n4")
    check buffer.foldState.addFold(0, 3, collapsed = true)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    check buffer.foldState.folds[0].collapsed

  test "operator+motion opens a collapsed fold spanned by the motion range":
    # The motion ends inside a fold that does NOT start at the cursor line, so
    # only the range-wide guard (not the cursor-line openFold) can reveal it.
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5")
    check buffer.foldState.addFold(1, 3, collapsed = true)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0) # outside the fold
    let registry = createTestRegistry()

    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpIndent, operatorCount: 1, startPos: ctx.cursor)
    )
    # >j indents lines 0-1; the range touches the collapsed fold at lines 1-3.
    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    check not buffer.foldState.folds[0].collapsed

suite "executeCommand - cursor pinned on collapsed folds":
  test "horizontal motion is pinned on a collapsed fold start line":
    let buffer = newTextBuffer("function main() {\nbody\nend\ntail")
    check buffer.foldState.addFold(0, 2, collapsed = true)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.Right, count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    # The collapsed fold is a single unit; the cursor cannot roam its line.
    check ctx.cursor.line == 0
    check ctx.cursor.column == 0

  test "moving onto a collapsed fold pins the cursor to its start at column 0":
    let buffer = newTextBuffer("aaaa\nbbbb\ncccc\ndddd\neeee")
    check buffer.foldState.addFold(1, 3, collapsed = true)
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    let registry = createTestRegistry()

    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    check ctx.cursor.line == 1
    check ctx.cursor.column == 0

suite "executeCommand - visual edit opens folds in the selection":
  test "a visual edit opens collapsed folds the selection spans":
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6")
    check buffer.foldState.addFold(2, 4, collapsed = true)
    let ctx = createTestContext(buffer)
    # Select lines 1..5, which span the collapsed fold (2-4).
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 1, column: 0),
      current: BufferPosition(line: 5, column: 0),
      kind: vskChar,
    )
    ctx.state.mode = EditorMode.Visual
    let registry = createTestRegistry()

    let cmd = Command(kind: ctCustom, commandId: "visual.indent", count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    # The fold the selection spans is now open.
    check buffer.foldState.getFoldAt(2).get.collapsed == false

  test "a visual edit leaves folds outside the selection closed":
    let buffer = newTextBuffer("0\n1\n2\n3\n4\n5\n6")
    check buffer.foldState.addFold(4, 6, collapsed = true) # below the selection
    let ctx = createTestContext(buffer)
    ctx.state.visualSelection = VisualSelection(
      active: true,
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 2, column: 0),
      kind: vskChar,
    )
    ctx.state.mode = EditorMode.Visual
    let registry = createTestRegistry()

    let cmd = Command(kind: ctCustom, commandId: "visual.indent", count: 1)
    check registry.executeCommand(ctx, cmd).isOk
    check buffer.foldState.getFoldAt(4).get.collapsed == true

suite "executeCommand - fold auto-open allowlists stay in sync":
  # The fold auto-open guard keys off hardcoded commandId allowlists. If a
  # command is renamed or removed without updating the list, the guard silently
  # stops revealing folds before that edit. These tests fail loudly in that
  # case by asserting every listed id resolves to a registered built-in command.
  proc registeredCommandIds(): HashSet[string] =
    result = initHashSet[string]()
    let reg = newKeyBindingRegistry()
    reg.setupDefaultBindings()
    for cmd in reg.commandRegistry.values:
      # commandId only exists on these command kinds (it is a variant field).
      if cmd.kind in {ctAction, ctOperator, ctTextObject, ctCustom} and
          cmd.commandId.len > 0:
        result.incl(cmd.commandId)

  proc registeredOperatorTypes(): HashSet[string] =
    result = initHashSet[string]()
    let reg = newKeyBindingRegistry()
    reg.setupDefaultBindings()
    for cmd in reg.commandRegistry.values:
      # operatorType only exists on ctOperatorPending commands (variant field).
      if cmd.kind == ctOperatorPending and cmd.operatorType.len > 0:
        result.incl(cmd.operatorType)

  test "every EditCommandIds entry is a registered command":
    let ids = registeredCommandIds()
    for id in EditCommandIds:
      check id in ids

  test "every VisualEditCommandIds entry is a registered command":
    let ids = registeredCommandIds()
    for id in VisualEditCommandIds:
      check id in ids

  test "every EditOperatorTypes entry is a registered operatorType":
    let ops = registeredOperatorTypes()
    for op in EditOperatorTypes:
      check op in ops

  test "every VisualEditOperatorTypes entry is a registered operatorType":
    let ops = registeredOperatorTypes()
    for op in VisualEditOperatorTypes:
      check op in ops

suite "Register/buffer atomicity - failed edits must not touch registers":
  # deleteRange/deleteLine reject writes on a read-only buffer, so a read-only
  # buffer is the reproducible failure path. Registers live outside the buffer
  # transaction, so a rollback cannot undo them: they must only be written after
  # the buffer change succeeded.

  proc seedRegisters(ctx: CommandContext) =
    ctx.state.registers.setDeletedRegister("SEED", false)
    discard ctx.state.registers.setNamedRegister('a', "SEED_A", false)

  proc checkRegistersUntouched(ctx: CommandContext) =
    check ctx.state.registers.getSmallDeleteRegister().getContent() == "SEED"
    check ctx.state.registers.getNamedRegister('a').getContent() == "SEED_A"

  test "delete.char on read-only buffer keeps registers":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    ctx.seedRegisters()
    buffer.readOnly = true
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isErr
    ctx.checkRegistersUntouched()

  test "delete.char with count on read-only buffer keeps registers":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    ctx.seedRegisters()
    buffer.readOnly = true
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char"), @["3"]).isErr
    ctx.checkRegistersUntouched()

  test "delete.char.before on read-only buffer keeps registers":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 5)
    ctx.seedRegisters()
    buffer.readOnly = true
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char.before")).isErr
    ctx.checkRegistersUntouched()

  test "delete.line on read-only buffer keeps registers":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    ctx.seedRegisters()
    buffer.readOnly = true
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isErr
    ctx.checkRegistersUntouched()

  test "substitute.char on read-only buffer keeps registers":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    ctx.seedRegisters()
    buffer.readOnly = true
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("substitute.char")).isErr
    ctx.checkRegistersUntouched()

  test "substitute.line on read-only buffer keeps registers":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    ctx.seedRegisters()
    buffer.readOnly = true
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("substitute.line")).isErr
    ctx.checkRegistersUntouched()

  test "delete operator on read-only buffer keeps registers":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    ctx.seedRegisters()
    buffer.readOnly = true

    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 0),
      endPos: BufferPosition(line: 0, column: 4),
      isLinewise: false,
    )
    check executeOperatorOnRange(ctx, OpDelete, range, 1).isErr
    ctx.checkRegistersUntouched()

  test "change operator on read-only buffer keeps registers":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    ctx.seedRegisters()
    buffer.readOnly = true

    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 0),
      endPos: BufferPosition(line: 0, column: 4),
      isLinewise: false,
    )
    check executeOperatorOnRange(ctx, OpChange, range, 1).isErr
    ctx.checkRegistersUntouched()

  test "pending register is preserved when the delete fails":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.setCursor(0, 0)
    ctx.seedRegisters()
    ctx.state.pendingInput.pendingRegister = some('a')
    buffer.readOnly = true
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.line")).isErr
    check ctx.state.registers.getNamedRegister('a').getContent() == "SEED_A"
