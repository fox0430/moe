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

## Tests for repeat last change command (.)
## This test suite verifies that the . command correctly repeats
## edit operations made in Normal mode. Changes made in Insert mode are
## covered through keys in test_dot_repeat_insert.

import std/[unittest, options]

import pkg/results

import
  ../src/moepkg/[buffer, types, motion, command_registry, key_bindings, modes, config]

suite "Repeat Command (.) - Delete Operations":
  test "repeat delete char (x)":
    # Setup
    let buffer = newTextBuffer("hello world")
    var state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    # Simulate: x (delete 'h')
    state.editState.lastEditCommand =
      some(LastEditCommand(kind: lecDeleteChar, deleteCount: 1, deleteForward: true))

    # Execute repeat command (.) - should delete 'e'
    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let motionController = MotionController(
      viewportManager: ViewportManager(
        viewport: ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
      )
    )

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: keyBindingRegistry,
    )

    let result = registry.execute(ctx, custom("edit.repeat"), @[])

    # Verify
    check result.isOk
    check buffer[0] == "ello world"

  test "repeat delete line (dd)":
    # Setup
    let buffer = newTextBuffer("line1\nline2\nline3")
    var state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 1, column: 0)
    state.mode = EditorMode.Normal

    # Simulate: dd (delete line)
    state.editState.lastEditCommand = some(
      LastEditCommand(
        kind: lecOperatorMotion,
        operator: OpDelete,
        operand: Operand(kind: odLines, count: 1),
      )
    )

    # Execute repeat command (.) - should delete line2
    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let motionController = MotionController(
      viewportManager: ViewportManager(
        viewport: ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
      )
    )

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: keyBindingRegistry,
    )

    let result = registry.execute(ctx, custom("edit.repeat"), @[])

    # Verify
    check result.isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == "line3"

suite "Repeat Command (.) - Replace Char":
  test "repeat replace char (r)":
    # Setup
    let buffer = newTextBuffer("hello world")
    var state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 0, column: 1)
    state.mode = EditorMode.Normal

    # Simulate: rx (replace 'h' with 'x')
    state.editState.lastEditCommand =
      some(LastEditCommand(kind: lecReplaceChar, replaceChar: "x", replaceCount: 1))

    # Execute repeat command (.) - should replace 'e' with 'x'
    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let motionController = MotionController(
      viewportManager: ViewportManager(
        viewport: ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
      )
    )

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: keyBindingRegistry,
    )

    let result = registry.execute(ctx, custom("edit.repeat"), @[])

    # Verify
    check result.isOk
    check buffer[0] == "hxllo world"
    check state.cursor.column == 1 # On 'x'

suite "Repeat Command (.) - Edge Cases":
  test "no previous command returns error":
    # Setup
    let buffer = newTextBuffer("hello world")
    var state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal
    state.editState.lastEditCommand = none(LastEditCommand)

    # Execute repeat command (.) without previous command
    let registry = newCommandRegistry()
    let keyBindingRegistry = newKeyBindingRegistry()
    registerBuiltinCommands(registry)

    let motionController = MotionController(
      viewportManager: ViewportManager(
        viewport: ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
      )
    )

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: keyBindingRegistry,
    )

    let result = registry.execute(ctx, custom("edit.repeat"), @[])

    # Verify
    check result.isErr
    check result.error == "No previous change to repeat"
