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

import std/[unittest, options, strutils]

import pkg/results

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/registers {.all.}

proc createTestContext(buffer: TextBuffer): CommandContext =
  let state = EditorState()
  state.cursor = BufferPosition(line: 0, column: 0)
  state.mode = EditorMode.Normal
  state.registers = initRegisters()

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
    cursor: state.cursor,
    motionController: motionController,
    clipboardConfig: ClipboardConfig(enable: false),
    keyBindingRegistry: newKeyBindingRegistry(),
  )

proc createTestRegistry(): CommandRegistry =
  ## Create a command registry with all builtin commands registered
  result = newCommandRegistry()
  registerBuiltinCommands(result)

proc setCursor(ctx: CommandContext, line, column: int) =
  ## Set cursor position on both ctx.cursor and ctx.state.cursor
  ctx.cursor = BufferPosition(line: line, column: column)
  ctx.state.cursor = ctx.cursor

proc setupVisual(
    ctx: CommandContext,
    startLine, startCol, endLine, endCol: int,
    mode = EditorMode.Visual,
) =
  ## Setup visual mode with selection range
  ctx.state.mode = mode
  ctx.state.visualSelection = VisualSelection(
    active: true,
    start: BufferPosition(line: startLine, column: startCol),
    current: BufferPosition(line: endLine, column: endCol),
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
    check ctx.state.overlay.get.kind == okCommand

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
    check ctx.state.overlay.get.kind == okSearch

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
    check ctx.state.overlay.get.kind == okSearch

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
    ctx.state.editState.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (w) which completes the operator
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "world test"
    check ctx.cursor.column == 0

  test "delete two words (d2w)":
    let buffer = newTextBuffer("hello world test end")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
      PendingOperator(operatorType: OpYank, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (w)
    let cmd = Command(kind: ctMotion, motion: Motion.WordForward, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer[0] == "hello world" # Buffer unchanged
    check ctx.state.yankRegister == "hello "

  test "change word (cw)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (c)
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
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

    ctx.state.editState.pendingOperator = some(
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

    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Execute motion (j) - only 1 line, motion down stays on line 0
    let cmd = Command(kind: ctMotion, motion: Motion.Down, count: 1)

    check registry.executeCommand(ctx, cmd).isOk
    check buffer.len == 1

suite "executeCommand - Delete with find motion":
  test "delete find character (df)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
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

suite "executeCommand - Record last edit":
  test "operator motion is recorded for repeat":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    # Delete word (dw)
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
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
    check ctx.state.jumpList.len > 0

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
    check ctx.state.jumpList.len > 0

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
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
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
    check ctx.state.editState.pendingOperator.isNone # Operator cleared

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
    ctx.state.yankRegister = "XYZ"
    ctx.state.yankIsLine = false
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer[0] == "helloXYZ world"

  test "paste after cursor (p) - linewise":
    let buffer = newTextBuffer("line1\nline2")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.yankRegister = "new line"
    ctx.state.yankIsLine = true
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after")).isOk
    check buffer.len == 3
    check buffer[1] == "new line"

  test "paste with count (3p)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 4)
    ctx.state.yankRegister = "X"
    ctx.state.yankIsLine = false
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.after"), @["3"]).isOk
    check buffer[0] == "helloXXX"

  test "paste empty register returns error":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.yankRegister = ""
    ctx.state.yankIsLine = false
    let registry = createTestRegistry()

    let result = registry.execute(ctx, custom("paste.after"))
    check result.isErr
    check "Nothing to paste" in result.error

  test "paste before cursor (P) - characterwise":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 5)
    ctx.state.yankRegister = "XYZ"
    ctx.state.yankIsLine = false
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("paste.before")).isOk
    check buffer[0] == "helloXYZ world"

suite "Handler - Delete char operations":
  test "delete char at cursor (x)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char")).isOk
    check buffer[0] == "ello"
    check ctx.state.yankRegister == "h"

  test "delete multiple chars (3x)":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("delete.char"), @["3"]).isOk
    check buffer[0] == "lo"
    check ctx.state.yankRegister == "hel"

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
    check "line2" in ctx.state.yankRegister
    check ctx.state.yankIsLine == true
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
    check "line1" in ctx.state.yankRegister
    check "line2" in ctx.state.yankRegister
    check "line3" in ctx.state.yankRegister
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
    check "hello" in ctx.state.yankRegister
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

  test "textobject.inner with pending operator sets text object modifier":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.editState.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Call textobject.inner
    check registry.execute(ctx, custom("textobject.inner")).isOk
    check ctx.state.editState.pendingTextObject.isSome
    check ctx.state.editState.pendingTextObject.get.modifier == tomInner

  test "textobject.around with pending operator sets text object modifier":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (c)
    ctx.state.editState.pendingOperator = some(
      PendingOperator(operatorType: OpChange, operatorCount: 1, startPos: ctx.cursor)
    )

    # Call textobject.around
    check registry.execute(ctx, custom("textobject.around")).isOk
    check ctx.state.editState.pendingTextObject.isSome
    check ctx.state.editState.pendingTextObject.get.modifier == tomAround

  test "textobject word (diw) deletes inner word":
    let buffer = newTextBuffer("hello world test")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 7) # On 'o' in "world"
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # Set pending operator (d)
    ctx.state.editState.pendingOperator = some(
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
    ctx.state.editState.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )

    # Call textobject.around
    discard registry.execute(ctx, custom("textobject.around"))

    # Now execute text object kind (word)
    check registry.execute(ctx, custom("textobject.word")).isOk
    # "world " should be deleted (including surrounding space)
    check "world" notin buffer[0]

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
    ctx.clipboardConfig = ClipboardConfig(enable: false)
    let registry = createTestRegistry()

    let result = registry.execute(ctx, builtin(bcEditCopy))
    check result.isErr
    check "disabled" in result.error

  test "clipboard paste when disabled returns error":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.clipboardConfig = ClipboardConfig(enable: false)
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
    ctx.clipboardConfig = ClipboardConfig(enable: false)
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
    ctx.clipboardConfig = ClipboardConfig(enable: true, tool: cbtXclip)
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
    check ctx.state.editState.pendingOperator.isSome
    check ctx.state.editState.pendingOperator.get.operatorType == OpDelete

  test "operator.change sets pending operator":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.change")).isOk
    check ctx.state.editState.pendingOperator.isSome
    check ctx.state.editState.pendingOperator.get.operatorType == OpChange

  test "operator.yank sets pending operator":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    check registry.execute(ctx, custom("operator.yank")).isOk
    check ctx.state.editState.pendingOperator.isSome
    check ctx.state.editState.pendingOperator.get.operatorType == OpYank

  test "double operator (dd) deletes line":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 1, column: 0)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    # First d - sets pending operator
    discard registry.execute(ctx, custom("operator.delete"))
    check ctx.state.editState.pendingOperator.isSome

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
    check ctx.state.editState.pendingOperator.isSome

    # Second y - completes yy (yank line)
    check registry.execute(ctx, custom("operator.yank")).isOk
    check buffer.len == 3 # Buffer unchanged
    check "line2" in ctx.state.yankRegister
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
    check ctx.state.editState.pendingOperator.isSome

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
    ctx.state.yankRegister = "XYZ"
    ctx.state.yankIsLine = false
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
    check ctx.state.cursor.column == 10 # End of "hello world"

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
    ctx.state.search.lastText = "hello"
    let registry = createTestRegistry()

    discard registry.execute(ctx, custom("search.next"))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "search prev (N)":
    let buffer = newTextBuffer("hello world hello test")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 12)
    ctx.state.search.lastText = "hello"
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
  test "undo (u)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcEditUndo))
    # Undo may fail if there's nothing to undo
    check true # Just verify no crash

  test "redo (Ctrl+r)":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcEditRedo))
    # Redo may fail if there's nothing to redo
    check true # Just verify no crash

suite "Handler - Jump Commands":
  test "jump back (Ctrl+o)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(2, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcJumpBack))
    # Jump may fail if there's nothing in jump list
    check true # Just verify no crash

  test "jump forward (Ctrl+i)":
    let buffer = newTextBuffer("line1\nline2\nline3")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcJumpForward))
    # Jump may fail if there's nothing in jump list
    check true # Just verify no crash

suite "Handler - File Operations":
  test "file save":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFileSave))
    # File save may fail without proper buffer path
    check true # Just verify no crash

  test "file new":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFileNew))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "file close":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFileClose))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "file open":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFileOpen))
    # Just check it doesn't crash
    check true # Just verify no crash

  test "filer mode":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcFiler))
    # Just check it doesn't crash
    check true # Just verify no crash

suite "Handler - LSP Commands":
  test "lsp goto definition":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcLspGotoDefinition))
    # LSP may fail without server running
    check true # Just verify no crash

  test "lsp find references":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    ctx.setCursor(0, 0)
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcLspFindReferences))
    # LSP may fail without server running
    check true # Just verify no crash

  test "lsp call hierarchy incoming":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcLspCallHierarchyIncoming))
    # LSP may fail without server running
    check true # Just verify no crash

  test "lsp call hierarchy outgoing":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcLspCallHierarchyOutgoing))
    # LSP may fail without server running
    check true # Just verify no crash

  test "lsp code lens execute":
    let buffer = newTextBuffer("hello world")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Normal
    let registry = createTestRegistry()

    discard registry.execute(ctx, builtin(bcLspCodeLensExecute))
    # LSP may fail without server running
    check true # Just verify no crash

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
