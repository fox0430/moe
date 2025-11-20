#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Tests for operator+motion commands (dt, df, dw, etc.)
## This test suite verifies that operator+motion combinations work correctly

import std/[unittest, options]

import pkg/results

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/cursor {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/commandregistry {.all.}
import ../src/moepkg/commandconfig {.all.}
import ../src/moepkg/keybindings {.all.}
import ../src/moepkg/clipboard {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/config {.all.}

suite "Operator+Motion - TillChar (dt)":
  test "dt{char} deletes till character on same line":
    # Setup: "abcxyz" with cursor at 'a'
    let buffer = newTextBuffer("abcxyz")
    var state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
      keyBindingRegistry: keyBindingRegistry,
    )

    # Execute: d (operator.delete)
    var result = registry.execute(ctx, custom("operator.delete"), @[])
    check result.isOk
    check state.pendingOperator.isSome
    check state.pendingOperator.get.operatorType == OpDelete

    # Execute: t (till-char) - this should wait for character
    let tillCmd = Command(
      name: "till-char",
      description: "Till character forward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "x",
      count: 1,
    )
    result = registry.executeCommand(ctx, tillCmd)

    # Verify: "abc" should be deleted, leaving "xyz"
    check result.isOk
    check buffer[0] == "xyz"
    check state.cursor.line == 0
    check state.cursor.column == 0
    check state.pendingOperator.isNone

  test "dt{char} with character not found does nothing":
    # Setup: "abcdef" with cursor at 'a'
    let buffer = newTextBuffer("abcdef")
    var state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
      keyBindingRegistry: keyBindingRegistry,
    )

    # Execute: d
    var result = registry.execute(ctx, custom("operator.delete"), @[])
    check result.isOk

    # Execute: tz (character 'z' not found)
    let tillCmd = Command(
      name: "till-char",
      description: "Till character forward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "z",
      count: 1,
    )
    result = registry.executeCommand(ctx, tillCmd)

    # Verify: nothing should change (character not found, cursor didn't move)
    check buffer[0] == "abcdef"
    check state.cursor.line == 0
    check state.cursor.column == 0

  test "dt{char} from middle of line":
    # Setup: "hello world" with cursor at 'l' (column 3)
    let buffer = newTextBuffer("hello world")
    var state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 3)
    state.mode = EditorMode.Normal

    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
      keyBindingRegistry: keyBindingRegistry,
    )

    # Execute: dtw (delete till 'w')
    var result = registry.execute(ctx, custom("operator.delete"), @[])
    check result.isOk

    let tillCmd = Command(
      name: "till-char",
      description: "Till character forward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "w",
      count: 1,
    )
    result = registry.executeCommand(ctx, tillCmd)

    # Verify: "lo " should be deleted, leaving "helworld"
    check result.isOk
    check buffer[0] == "helworld"
    check state.cursor.line == 0
    check state.cursor.column == 3

suite "Operator+Motion - FindChar (df)":
  test "df{char} deletes including character":
    # Setup: "abcxyz" with cursor at 'a'
    let buffer = newTextBuffer("abcxyz")
    var state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
      keyBindingRegistry: keyBindingRegistry,
    )

    # Execute: d
    var result = registry.execute(ctx, custom("operator.delete"), @[])
    check result.isOk

    # Execute: fx (find 'x')
    let findCmd = Command(
      name: "find-char",
      description: "Find character forward",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "x",
      count: 1,
    )
    result = registry.executeCommand(ctx, findCmd)

    # Verify: "abcx" should be deleted, leaving "yz"
    check result.isOk
    check buffer[0] == "yz"
    check state.cursor.line == 0
    check state.cursor.column == 0

  test "df{char} vs dt{char} difference":
    # Setup: "123x456"
    # Test df deletes including 'x', dt deletes up to (not including) 'x'

    # First test df
    var buffer = newTextBuffer("123x456")
    var state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    var registry = newCommandRegistry()
    var keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    var viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    var motionController = newMotionController(buffer, state, viewport)

    var ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
      keyBindingRegistry: keyBindingRegistry,
    )

    var result = registry.execute(ctx, custom("operator.delete"), @[])
    let findCmd = Command(
      name: "find-char",
      description: "Find character forward",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "x",
      count: 1,
    )
    result = registry.executeCommand(ctx, findCmd)

    check buffer[0] == "456" # dfx deleted "123x"

    # Now test dt
    buffer = newTextBuffer("123x456")
    state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    registry = newCommandRegistry()
    keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    viewport = ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    motionController = newMotionController(buffer, state, viewport)

    ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
      keyBindingRegistry: keyBindingRegistry,
    )

    result = registry.execute(ctx, custom("operator.delete"), @[])
    let tillCmd = Command(
      name: "till-char",
      description: "Till character forward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "x",
      count: 1,
    )
    result = registry.executeCommand(ctx, tillCmd)

    check buffer[0] == "x456" # dtx deleted "123", leaving "x456"

suite "Operator+Motion - Change with TillChar (ct)":
  test "ct{char} deletes till character and enters insert mode":
    # Setup: "abcxyz" with cursor at 'a'
    let buffer = newTextBuffer("abcxyz")
    var state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
      keyBindingRegistry: keyBindingRegistry,
    )

    # Execute: c (operator.change)
    var result = registry.execute(ctx, custom("operator.change"), @[])
    check result.isOk

    # Execute: tx
    let tillCmd = Command(
      name: "till-char",
      description: "Till character forward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "x",
      count: 1,
    )
    result = registry.executeCommand(ctx, tillCmd)

    # Verify: "abc" deleted, mode changed to Insert
    check result.isOk
    check buffer[0] == "xyz"
    check state.mode == EditorMode.Insert
    check state.cursor.column == 0

suite "Operator+Motion - Yank with TillChar (yt)":
  test "yt{char} yanks till character":
    # Setup: "abcxyz" with cursor at 'a'
    let buffer = newTextBuffer("abcxyz")
    var state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
      keyBindingRegistry: keyBindingRegistry,
    )

    # Execute: y (operator.yank)
    var result = registry.execute(ctx, custom("operator.yank"), @[])
    check result.isOk

    # Execute: tx
    let tillCmd = Command(
      name: "till-char",
      description: "Till character forward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "x",
      count: 1,
    )
    result = registry.executeCommand(ctx, tillCmd)

    # Verify: "abc" yanked, buffer unchanged
    check result.isOk
    check buffer[0] == "abcxyz" # Buffer unchanged
    check state.yankRegister == "abc" # "abc" was yanked
    check state.yankIsLine == false # Character-wise yank
