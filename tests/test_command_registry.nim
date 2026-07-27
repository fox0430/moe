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

import std/[unittest, options, tables, strutils]

import pkg/results

import
  ../src/moepkg/[
    buffer, types, motion, command_registry, key_bindings, config, modes, git_conflict,
    registers,
  ]

suite "CommandRegistry - CommandId":
  test "builtin creates CommandId from BuiltinCommandId":
    let id = builtin(bcMotionLeft)
    check id.kind == ckBuiltin
    check id.builtin == bcMotionLeft

  test "custom creates CommandId from string":
    let id = custom("my.custom.command")
    check id.kind == ckCustom
    check id.custom == "my.custom.command"

  test "$ for builtin CommandId":
    let id = builtin(bcMotionRight)
    check $id == "motion.right"

  test "$ for custom CommandId":
    let id = custom("custom.test")
    check $id == "custom.test"

  test "== for same builtin CommandIds":
    let a = builtin(bcMotionUp)
    let b = builtin(bcMotionUp)
    check a == b

  test "== for different builtin CommandIds":
    let a = builtin(bcMotionUp)
    let b = builtin(bcMotionDown)
    check not (a == b)

  test "== for same custom CommandIds":
    let a = custom("test.command")
    let b = custom("test.command")
    check a == b

  test "== for different custom CommandIds":
    let a = custom("test.command1")
    let b = custom("test.command2")
    check not (a == b)

  test "== for different kinds":
    let a = builtin(bcMotionLeft)
    let b = custom("motion.left")
    check not (a == b)

suite "CommandRegistry - newCommandRegistry":
  test "creates empty registry":
    let registry = newCommandRegistry()
    check registry.commands.len == 0

  test "builtin commands array is initialized":
    let registry = newCommandRegistry()
    # All builtin commands should have empty handlers initially
    for id in BuiltinCommandId:
      let cmd = registry.builtinCommands[id]
      check cmd.handler.isNil

suite "CommandRegistry - register":
  test "register builtin command":
    let registry = newCommandRegistry()
    var called = false

    registry.register(
      builtin(bcMotionLeft),
      "Left",
      "Move cursor left",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        called = true
        ok(()),
      0,
      0,
    )

    let cmd = registry.findCommand(builtin(bcMotionLeft))
    check cmd.isSome
    check cmd.get.name == "Left"
    check cmd.get.description == "Move cursor left"
    check cmd.get.minArgs == 0
    check cmd.get.maxArgs == 0

  test "register custom command":
    let registry = newCommandRegistry()

    registry.register(
      custom("my.command"),
      "MyCommand",
      "A custom command",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
      1,
      2,
    )

    let cmd = registry.findCommand(custom("my.command"))
    check cmd.isSome
    check cmd.get.name == "MyCommand"
    check cmd.get.description == "A custom command"
    check cmd.get.minArgs == 1
    check cmd.get.maxArgs == 2

  test "register overwrites existing command":
    let registry = newCommandRegistry()

    registry.register(
      builtin(bcMotionUp),
      "Up",
      "First description",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    registry.register(
      builtin(bcMotionUp),
      "UpUpdated",
      "Second description",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    let cmd = registry.findCommand(builtin(bcMotionUp))
    check cmd.isSome
    check cmd.get.name == "UpUpdated"
    check cmd.get.description == "Second description"

suite "CommandRegistry - findCommand":
  test "find builtin command by CommandId":
    let registry = newCommandRegistry()

    registry.register(
      builtin(bcMotionRight),
      "Right",
      "Move right",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    let cmd = registry.findCommand(builtin(bcMotionRight))
    check cmd.isSome
    check cmd.get.name == "Right"

  test "find custom command by CommandId":
    let registry = newCommandRegistry()

    registry.register(
      custom("custom.cmd"),
      "CustomCmd",
      "Custom command",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    let cmd = registry.findCommand(custom("custom.cmd"))
    check cmd.isSome
    check cmd.get.name == "CustomCmd"

  test "find command by string":
    let registry = newCommandRegistry()

    registry.register(
      custom("string.lookup"),
      "StringLookup",
      "Lookup by string",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    let cmd = registry.findCommand("string.lookup")
    check cmd.isSome
    check cmd.get.name == "StringLookup"

  test "find non-existent command returns none":
    let registry = newCommandRegistry()

    let cmd = registry.findCommand(builtin(bcMotionLeft))
    check cmd.isNone

  test "find non-existent string returns none":
    let registry = newCommandRegistry()

    let cmd = registry.findCommand("nonexistent.command")
    check cmd.isNone

  test "find bcNone returns none":
    let registry = newCommandRegistry()

    let cmd = registry.findCommand(builtin(bcNone))
    check cmd.isNone

suite "CommandRegistry - execute":
  test "execute command by CommandId":
    let registry = newCommandRegistry()
    var executedWith: seq[string] = @[]

    registry.register(
      builtin(bcMotionDown),
      "Down",
      "Move down",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        executedWith = args
        ok(()),
    )

    let result = registry.execute(nil, builtin(bcMotionDown), @["arg1", "arg2"])
    check result.isOk
    check executedWith == @["arg1", "arg2"]

  test "execute command by string":
    let registry = newCommandRegistry()
    var executed = false

    registry.register(
      custom("exec.test"),
      "ExecTest",
      "Test execution",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        executed = true
        ok(()),
    )

    let result = registry.execute(nil, "exec.test")
    check result.isOk
    check executed

  test "execute non-existent command returns error":
    let registry = newCommandRegistry()

    let result = registry.execute(nil, builtin(bcMotionLeft))
    check result.isErr
    check result.error == "Command not found"

  test "execute with too few arguments returns error":
    let registry = newCommandRegistry()

    registry.register(
      custom("args.test"),
      "ArgsTest",
      "Args test",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
      minArgs = 2,
    )

    let result = registry.execute(nil, "args.test", @["one"])
    check result.isErr
    check "Too few arguments" in result.error

  test "execute with too many arguments returns error":
    let registry = newCommandRegistry()

    registry.register(
      custom("maxargs.test"),
      "MaxArgsTest",
      "Max args test",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
      maxArgs = 1,
    )

    let result = registry.execute(nil, "maxargs.test", @["one", "two", "three"])
    check result.isErr
    check "Too many arguments" in result.error

  test "execute command that returns error":
    let registry = newCommandRegistry()

    registry.register(
      custom("error.test"),
      "ErrorTest",
      "Error test",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        err("Custom error message"),
    )

    let result = registry.execute(nil, "error.test")
    check result.isErr
    check result.error == "Custom error message"

suite "CommandRegistry - BuiltinCommandId":
  test "bcNone has empty string value":
    check $bcNone == ""

  test "motion commands have correct string values":
    check $bcMotionLeft == "motion.left"
    check $bcMotionRight == "motion.right"
    check $bcMotionUp == "motion.up"
    check $bcMotionDown == "motion.down"
    check $bcMotionPageUp == "motion.pageup"
    check $bcMotionPageDown == "motion.pagedown"

  test "edit commands have correct string values":
    check $bcEditUndo == "edit.undo"
    check $bcEditRedo == "edit.redo"
    check $bcEditCut == "edit.cut"
    check $bcEditCopy == "edit.copy"
    check $bcEditPaste == "edit.paste"

  test "mode commands have correct string values":
    check $bcModeNormal == "mode.normal"
    check $bcModeInsert == "mode.insert"
    check $bcModeCommand == "mode.command"

  test "insert commands have correct string values":
    check $bcInsertChar == "insert.char"
    check $bcInsertBackspace == "insert.backspace"
    check $bcInsertDelete == "insert.delete"
    check $bcInsertNewline == "insert.newline"
    check $bcInsertLineBelow == "insert.line.below"
    check $bcInsertLineAbove == "insert.line.above"
    check $bcInsertAppend == "insert.append"
    check $bcInsertAppendEnd == "insert.append.end"

  test "visual commands have correct string values":
    check $bcVisualMoveLeft == "visual.move.left"
    check $bcVisualMoveRight == "visual.move.right"
    check $bcVisualMoveUp == "visual.move.up"
    check $bcVisualMoveDown == "visual.move.down"
    check $bcVisualDelete == "visual.delete"
    check $bcVisualYank == "visual.yank"
    check $bcVisualIndent == "visual.indent"
    check $bcVisualDedent == "visual.dedent"

  test "scroll commands have correct string values":
    check $bcScrollCursorTop == "scroll.cursor.top"
    check $bcScrollCursorCenter == "scroll.cursor.center"
    check $bcScrollCursorBottom == "scroll.cursor.bottom"

  test "fold commands have correct string values":
    check $bcFoldOpen == "fold.open"
    check $bcFoldClose == "fold.close"
    check $bcFoldToggle == "fold.toggle"
    check $bcFoldOpenAll == "fold.open.all"
    check $bcFoldCloseAll == "fold.close.all"
    check $bcFoldCreate == "fold.create"
    check $bcFoldDelete == "fold.delete"
    check $bcFoldDeleteAll == "fold.delete.all"

suite "CommandRegistry - registerBuiltinCommands":
  test "registers all motion commands":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    # Check motion commands are registered
    check registry.findCommand(builtin(bcMotionLeft)).isSome
    check registry.findCommand(builtin(bcMotionRight)).isSome
    check registry.findCommand(builtin(bcMotionUp)).isSome
    check registry.findCommand(builtin(bcMotionDown)).isSome
    check registry.findCommand(builtin(bcMotionPageUp)).isSome
    check registry.findCommand(builtin(bcMotionPageDown)).isSome
    check registry.findCommand(builtin(bcMotionHome)).isSome
    check registry.findCommand(builtin(bcMotionEnd)).isSome
    check registry.findCommand(builtin(bcMotionFirstLine)).isSome
    check registry.findCommand(builtin(bcMotionLastLine)).isSome

  test "registers all mode switch commands":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.findCommand(builtin(bcModeNormal)).isSome
    check registry.findCommand(builtin(bcModeInsert)).isSome
    check registry.findCommand(builtin(bcModeCommand)).isSome

  test "registers all edit commands":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.findCommand(builtin(bcEditUndo)).isSome
    check registry.findCommand(builtin(bcEditRedo)).isSome
    check registry.findCommand(builtin(bcEditCut)).isSome
    check registry.findCommand(builtin(bcEditCopy)).isSome
    check registry.findCommand(builtin(bcEditPaste)).isSome
    check registry.findCommand(builtin(bcEditIncrementNumber)).isSome
    check registry.findCommand(builtin(bcEditDecrementNumber)).isSome

  test "registers all insert mode commands":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.findCommand(builtin(bcInsertChar)).isSome
    check registry.findCommand(builtin(bcInsertBackspace)).isSome
    check registry.findCommand(builtin(bcInsertDelete)).isSome
    check registry.findCommand(builtin(bcInsertNewline)).isSome
    check registry.findCommand(builtin(bcInsertLineBelow)).isSome
    check registry.findCommand(builtin(bcInsertLineAbove)).isSome
    check registry.findCommand(builtin(bcInsertAppend)).isSome
    check registry.findCommand(builtin(bcInsertAppendEnd)).isSome

  test "registers all visual mode commands":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.findCommand(builtin(bcVisualMoveLeft)).isSome
    check registry.findCommand(builtin(bcVisualMoveRight)).isSome
    check registry.findCommand(builtin(bcVisualMoveUp)).isSome
    check registry.findCommand(builtin(bcVisualMoveDown)).isSome
    check registry.findCommand(builtin(bcVisualDelete)).isSome
    check registry.findCommand(builtin(bcVisualYank)).isSome
    check registry.findCommand(builtin(bcVisualIndent)).isSome
    check registry.findCommand(builtin(bcVisualDedent)).isSome

  test "registers all scroll commands":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.findCommand(builtin(bcScrollCursorTop)).isSome
    check registry.findCommand(builtin(bcScrollCursorCenter)).isSome
    check registry.findCommand(builtin(bcScrollCursorBottom)).isSome

  test "registers all fold commands":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.findCommand(builtin(bcFoldOpen)).isSome
    check registry.findCommand(builtin(bcFoldClose)).isSome
    check registry.findCommand(builtin(bcFoldToggle)).isSome
    check registry.findCommand(builtin(bcFoldOpenAll)).isSome
    check registry.findCommand(builtin(bcFoldCloseAll)).isSome
    check registry.findCommand(builtin(bcFoldCreate)).isSome
    check registry.findCommand(builtin(bcFoldDelete)).isSome
    check registry.findCommand(builtin(bcFoldDeleteAll)).isSome

  test "registers quickrun command":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.findCommand(builtin(bcQuickRun)).isSome

  test "registered commands have non-nil handlers":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    # Spot check that handlers are not nil
    let leftCmd = registry.findCommand(builtin(bcMotionLeft))
    check leftCmd.isSome
    check not leftCmd.get.handler.isNil

    let undoCmd = registry.findCommand(builtin(bcEditUndo))
    check undoCmd.isSome
    check not undoCmd.get.handler.isNil

  test "registered commands have proper metadata":
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let cmd = registry.findCommand(builtin(bcMotionLeft))
    check cmd.isSome
    check cmd.get.name.len > 0
    check cmd.get.description.len > 0

suite "CommandRegistry - Command execution with context":
  proc createTestContext(buffer: TextBuffer): CommandContext =
    let state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let motionController = MotionController(
      viewportManager: ViewportManager(
        viewport: ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
      ),
      executor: MotionExecutor(buffer: buffer),
    )

    result = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: newKeyBindingRegistry(),
    )

  test "execute mode switch to insert":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let result = registry.execute(ctx, builtin(bcModeInsert))
    check result.isOk
    check ctx.state.mode == EditorMode.Insert

  test "execute mode switch to normal":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.state.mode = EditorMode.Insert
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let result = registry.execute(ctx, builtin(bcModeNormal))
    check result.isOk
    check ctx.state.mode == EditorMode.Normal

  test "execute insert line below":
    let buffer = newTextBuffer("line1")
    let ctx = createTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let result = registry.execute(ctx, builtin(bcInsertLineBelow))
    check result.isOk
    check buffer.len == 2
    check buffer[0] == "line1"
    check buffer[1] == ""
    check ctx.state.mode == EditorMode.Insert

  test "execute insert line above":
    let buffer = newTextBuffer("line1")
    let ctx = createTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let result = registry.execute(ctx, builtin(bcInsertLineAbove))
    check result.isOk
    check buffer.len == 2
    check buffer[0] == ""
    check buffer[1] == "line1"
    check ctx.state.mode == EditorMode.Insert

  test "execute append enters insert mode":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 2)
    ctx.state.cursor = ctx.cursor
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let result = registry.execute(ctx, builtin(bcInsertAppend))
    check result.isOk
    # Handler updates ctx.state.cursor, not ctx.cursor
    check ctx.state.cursor.column == 3
    check ctx.state.mode == EditorMode.Insert

  test "execute append at end enters insert mode at line end":
    let buffer = newTextBuffer("hello")
    let ctx = createTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.cursor = ctx.cursor
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let result = registry.execute(ctx, builtin(bcInsertAppendEnd))
    check result.isOk
    # Handler updates ctx.state.cursor, not ctx.cursor
    check ctx.state.cursor.column == 5 # After 'o' in "hello"
    check ctx.state.mode == EditorMode.Insert

suite "CommandRegistry - Edge cases":
  test "execute with exact min args":
    let registry = newCommandRegistry()
    var receivedArgs: seq[string] = @[]

    registry.register(
      custom("exact.args"),
      "ExactArgs",
      "Test exact args",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        receivedArgs = args
        ok(()),
      minArgs = 2,
      maxArgs = 2,
    )

    let result = registry.execute(nil, "exact.args", @["a", "b"])
    check result.isOk
    check receivedArgs == @["a", "b"]

  test "execute with zero args when zero required":
    let registry = newCommandRegistry()
    var executed = false

    registry.register(
      custom("zero.args"),
      "ZeroArgs",
      "No args required",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        executed = true
        check args.len == 0
        ok(()),
      minArgs = 0,
      maxArgs = 0,
    )

    let result = registry.execute(nil, "zero.args", @[])
    check result.isOk
    check executed

  test "command with optional args":
    let registry = newCommandRegistry()
    var callCount = 0

    registry.register(
      custom("optional.args"),
      "OptionalArgs",
      "Optional args",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        callCount += 1
        ok(()),
      minArgs = 0,
      maxArgs = 3,
    )

    check registry.execute(nil, "optional.args", @[]).isOk
    check registry.execute(nil, "optional.args", @["one"]).isOk
    check registry.execute(nil, "optional.args", @["one", "two"]).isOk
    check registry.execute(nil, "optional.args", @["one", "two", "three"]).isOk
    check callCount == 4

    # Too many args should fail
    check registry.execute(nil, "optional.args", @["1", "2", "3", "4"]).isErr

suite "CommandRegistry - readOnly buffer guard":
  proc createReadOnlyTestContext(buffer: TextBuffer): CommandContext =
    let state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal
    state.previousMode = EditorMode.LogViewer

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    result = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: newKeyBindingRegistry(),
    )

  test "delete-char is blocked on read-only buffer":
    let buffer = newTextBuffer("hello")
    buffer.readOnly = true
    let ctx = createReadOnlyTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let cmd = Command(
      name: "delete-char",
      description: "Delete character",
      kind: ctAction,
      commandId: "delete.char",
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)

    check r.isOk
    check buffer[0] == "hello"
    check ctx.state.statusMessage == "Buffer is read-only"

  test "visual-delete is blocked and exits visual mode":
    let buffer = newTextBuffer("hello")
    buffer.readOnly = true
    let ctx = createReadOnlyTestContext(buffer)
    ctx.state.mode = EditorMode.Visual
    ctx.state.visualSelection = VisualSelection(
      start: BufferPosition(line: 0, column: 0),
      current: BufferPosition(line: 0, column: 2),
      active: true,
      kind: vskChar,
    )
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let cmd = Command(
      name: "visual-delete",
      description: "Delete selection",
      kind: ctAction,
      commandId: "visual.delete",
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)

    check r.isOk
    check buffer[0] == "hello"
    check not ctx.state.visualSelection.active
    check ctx.state.mode == EditorMode.LogViewer
    check ctx.state.statusMessage == "Buffer is read-only"

  test "motion command still works on read-only buffer":
    let buffer = newTextBuffer("hello world")
    buffer.readOnly = true
    let ctx = createReadOnlyTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let cmd = Command(
      name: "motion-right",
      description: "Move right",
      kind: ctMotion,
      motion: Motion.Right,
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)

    check r.isOk
    check ctx.state.statusMessage != "Buffer is read-only"

suite "findAllCharPositions":
  test "Single occurrence":
    let buffer = newTextBuffer("abcdef")
    let positions = findAllCharPositions(buffer, 0, "c")
    check positions == @[2]

  test "Multiple occurrences":
    let buffer = newTextBuffer("abacada")
    let positions = findAllCharPositions(buffer, 0, "a")
    check positions == @[0, 2, 4, 6]

  test "No occurrences":
    let buffer = newTextBuffer("abcdef")
    let positions = findAllCharPositions(buffer, 0, "z")
    check positions.len == 0

  test "Empty line":
    let buffer = newTextBuffer("")
    let positions = findAllCharPositions(buffer, 0, "a")
    check positions.len == 0

  test "Invalid line (negative)":
    let buffer = newTextBuffer("abc")
    let positions = findAllCharPositions(buffer, -1, "a")
    check positions.len == 0

  test "Invalid line (beyond buffer)":
    let buffer = newTextBuffer("abc")
    let positions = findAllCharPositions(buffer, 5, "a")
    check positions.len == 0

  test "Multi-line buffer, specific line":
    let buffer = newTextBuffer("abc\naxaya\nxyz")
    let positions = findAllCharPositions(buffer, 1, "a")
    check positions == @[0, 2, 4]

suite "f/F/t/T highlight - executeCommand sets findCharMatches":
  proc createFindTestContext(buffer: TextBuffer): CommandContext =
    let state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    result = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: newKeyBindingRegistry(),
    )

  test "find-char sets highlight positions":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let cmd = Command(
      name: "find-char",
      description: "Find character forward",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "a",
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)
    check r.isOk
    check ctx.state.ui.findCharMatches == @[0, 2, 4, 6]
    check ctx.state.ui.findCharMatchLine == 0

  test "find-char-backward sets highlight positions":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let cmd = Command(
      name: "find-char-backward",
      description: "Find character backward",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: true,
      targetChar: "a",
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)
    check r.isOk
    check ctx.state.ui.findCharMatches == @[0, 2, 4, 6]
    check ctx.state.ui.findCharMatchLine == 0

  test "till-char sets highlight positions":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let cmd = Command(
      name: "till-char",
      description: "Till character forward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "c",
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)
    check r.isOk
    # "abacada": c is at position 3
    check ctx.state.ui.findCharMatches == @[3]
    check ctx.state.ui.findCharMatchLine == 0

  test "till-char-backward sets highlight positions":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let cmd = Command(
      name: "till-char-backward",
      description: "Till character backward",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: true,
      targetChar: "c",
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)
    check r.isOk
    # "abacada": c is at position 3
    check ctx.state.ui.findCharMatches == @[3]
    check ctx.state.ui.findCharMatchLine == 0

  test "Non-find/till command clears highlight":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    ctx.state.ui.findCharMatches = @[0, 2, 4, 6]
    ctx.state.ui.findCharMatchLine = 0
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    # Execute a motion command (right) to clear the highlight
    let cmd = Command(
      name: "motion-right",
      description: "Move right",
      kind: ctMotion,
      motion: Motion.Right,
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)
    check r.isOk
    check ctx.state.ui.findCharMatches.len == 0

  test "Operator+find does not set highlight":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    ctx.state.registers = initRegisters()
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    # Set pending operator (simulate 'd')
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )

    let cmd = Command(
      name: "find-char",
      description: "Find character forward",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "c",
      count: 1,
    )
    let r = registry.executeCommand(ctx, cmd)
    check r.isOk
    # With pending operator, highlight should not be set
    check ctx.state.ui.findCharMatches.len == 0

suite "; / , repeat last find":
  proc createFindTestContext(buffer: TextBuffer): CommandContext =
    let state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal
    state.registers = initRegisters()

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    result = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: newKeyBindingRegistry(),
    )

  let findA = Command(
    name: "find-char",
    description: "Find character forward",
    kind: ctOperatorPending,
    operatorType: "find",
    reverse: false,
    targetChar: "a",
    count: 1,
  )
  let repeatFind =
    Command(name: "repeat-find", kind: ctMotion, motion: Motion.RepeatFind, count: 1)
  let repeatFindReverse = Command(
    name: "repeat-find-reverse",
    kind: ctMotion,
    motion: Motion.RepeatFindReverse,
    count: 1,
  )

  test "; repeats the last find forward":
    let buffer = newTextBuffer("abacada") # 'a' at 0,2,4,6
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.executeCommand(ctx, findA).isOk
    check ctx.cursor.column == 2
    check registry.executeCommand(ctx, repeatFind).isOk
    check ctx.cursor.column == 4
    check registry.executeCommand(ctx, repeatFind).isOk
    check ctx.cursor.column == 6

  test ", repeats the last find reversed":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    ctx.cursor = BufferPosition(line: 0, column: 6)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    # Seed last find by finding 'a' forward (no match after col 6, cursor stays).
    check registry.executeCommand(ctx, findA).isOk
    check registry.executeCommand(ctx, repeatFindReverse).isOk
    check ctx.cursor.column == 4

  test "; keeps the match highlight":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.executeCommand(ctx, findA).isOk
    check registry.executeCommand(ctx, repeatFind).isOk
    check ctx.state.ui.findCharMatches == @[0, 2, 4, 6]
    check ctx.state.ui.findCharMatchLine == 0

  test "d; deletes through the repeated find":
    let buffer = newTextBuffer("abacada") # 'c' at 3
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    # Seed last find with 'c', then reset cursor and delete via d;.
    let findC = Command(
      name: "find-char",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: "c",
      count: 1,
    )
    check registry.executeCommand(ctx, findC).isOk
    ctx.cursor = BufferPosition(line: 0, column: 0)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 0),
      )
    )
    check registry.executeCommand(ctx, repeatFind).isOk
    check buffer.getLine(0) == "ada"

  test "; with no previous find is a no-op with feedback":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    check registry.executeCommand(ctx, repeatFind).isOk
    check ctx.cursor.column == 0
    check ctx.state.statusMessage == "No previous find"

  test "; after t advances past the adjacent match":
    let buffer = newTextBuffer("abzcz") # 'z' at cols 2 and 4
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let tillZ = Command(
      name: "till-char",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: "z",
      count: 1,
    )
    check registry.executeCommand(ctx, tillZ).isOk
    check ctx.cursor.column == 1 # just before the first z
    # ; skips the z it is parked before and lands before the next z.
    check registry.executeCommand(ctx, repeatFind).isOk
    check ctx.cursor.column == 3
    # No further z: ; stays put rather than getting stuck in a loop.
    check registry.executeCommand(ctx, repeatFind).isOk
    check ctx.cursor.column == 3

  test "d; repeating a till skips the adjacent match like a bare ;":
    let buffer = newTextBuffer("ab,cd,ef") # commas at cols 2 and 5
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let tillComma = Command(
      name: "till-char",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: ",",
      count: 1,
    )
    check registry.executeCommand(ctx, tillComma).isOk
    check ctx.cursor.column == 1 # parked before the first comma
    # d; must advance past the adjacent comma and delete through to just before
    # the next one (b,cd), not collapse to a single char.
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 1, startPos: ctx.cursor)
    )
    check registry.executeCommand(ctx, repeatFind).isOk
    check buffer.getLine(0) == "a,ef"

  test "2df, deletes through the second occurrence":
    let buffer = newTextBuffer("a,b,c,d") # commas at cols 1, 3, 5
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    # 2df, == d2f, : the operator count must fold into the find count.
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(operatorType: OpDelete, operatorCount: 2, startPos: ctx.cursor)
    )
    let findComma = Command(
      name: "find-char",
      kind: ctOperatorPending,
      operatorType: "find",
      reverse: false,
      targetChar: ",",
      count: 1,
    )
    check registry.executeCommand(ctx, findComma).isOk
    check buffer.getLine(0) == "c,d"

  test "; repeating a till at end-of-line with no target ahead stays put":
    let buffer = newTextBuffer("a.b") # '.' at col 1
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let tillDot = Command(
      name: "till-char",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: ".",
      count: 1,
    )
    check registry.executeCommand(ctx, tillDot).isOk
    check ctx.cursor.column == 0 # parked before the only '.'
    # Move to the last column, where no '.' lies ahead; ; must not jump.
    ctx.cursor = BufferPosition(line: 0, column: 2)
    check registry.executeCommand(ctx, repeatFind).isOk
    check ctx.cursor.column == 2

  test "d; repeating a till at end-of-line deletes nothing":
    let buffer = newTextBuffer("a.b")
    let ctx = createFindTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let tillDot = Command(
      name: "till-char",
      kind: ctOperatorPending,
      operatorType: "till",
      reverse: false,
      targetChar: ".",
      count: 1,
    )
    check registry.executeCommand(ctx, tillDot).isOk
    # Cursor at the last column with the operator armed: the missing target
    # must leave the buffer untouched, not delete a spurious range.
    ctx.cursor = BufferPosition(line: 0, column: 2)
    ctx.state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 0, column: 2),
      )
    )
    check registry.executeCommand(ctx, repeatFind).isOk
    check buffer.getLine(0) == "a.b"

suite "CommandRegistry - Git conflict navigation (]x / [x)":
  const ConflictContent =
    "before\n<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\nmiddle\n" &
    "<<<<<<< A\na\n=======\nb\n>>>>>>> B\nafter\n"
    # Lines: 0:before 1:<<<< 2:ours 3:=== 4:theirs 5:>>>> 6:middle
    #        7:<<<< 8:a 9:=== 10:b 11:>>>> 12:after

  proc createConflictTestContext(buffer: TextBuffer): CommandContext =
    let state = EditorState(activeWindow: EditorWindow(), config: newEditorConfig())
    state.config.clipboard = ClipboardConfig(enable: false)
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    result = CommandContext(
      buffer: buffer,
      state: state,
      motionController: motionController,
      keyBindingRegistry: newKeyBindingRegistry(),
    )

  test "navigate.conflict.next jumps from before first to first conflict":
    let buffer = newTextBuffer(ConflictContent)
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let r = registry.execute(ctx, custom("navigate.conflict.next"))
    check r.isOk
    check ctx.cursor.line == 1
    check ctx.cursor.column == 0

  test "navigate.conflict.next advances from inside first to second":
    let buffer = newTextBuffer(ConflictContent)
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    ctx.cursor = BufferPosition(line: 3, column: 0)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let r = registry.execute(ctx, custom("navigate.conflict.next"))
    check r.isOk
    check ctx.cursor.line == 7

  test "navigate.conflict.next past last conflict returns error":
    let buffer = newTextBuffer(ConflictContent)
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    ctx.cursor = BufferPosition(line: 12, column: 0)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let r = registry.execute(ctx, custom("navigate.conflict.next"))
    check r.isErr
    check ctx.cursor.line == 12
    check ctx.state.statusMessage == "No more git conflicts"

  test "navigate.conflict.prev jumps from after last to last conflict":
    let buffer = newTextBuffer(ConflictContent)
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    ctx.cursor = BufferPosition(line: 12, column: 0)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let r = registry.execute(ctx, custom("navigate.conflict.prev"))
    check r.isOk
    check ctx.cursor.line == 7

  test "navigate.conflict.prev from inside second returns second's start":
    # From inside a conflict block, [x jumps to the start of that block
    # (matches vim [c behavior for diff mode).
    let buffer = newTextBuffer(ConflictContent)
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    ctx.cursor = BufferPosition(line: 9, column: 0)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let r = registry.execute(ctx, custom("navigate.conflict.prev"))
    check r.isOk
    check ctx.cursor.line == 7

  test "navigate.conflict.prev from second's start jumps to first":
    let buffer = newTextBuffer(ConflictContent)
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    ctx.cursor = BufferPosition(line: 7, column: 0)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let r = registry.execute(ctx, custom("navigate.conflict.prev"))
    check r.isOk
    check ctx.cursor.line == 1

  test "navigate.conflict.prev before first conflict returns error":
    let buffer = newTextBuffer(ConflictContent)
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let r = registry.execute(ctx, custom("navigate.conflict.prev"))
    check r.isErr
    check ctx.cursor.line == 0
    check ctx.state.statusMessage == "No more git conflicts"

  test "navigate.conflict.next in buffer without conflicts returns error":
    let buffer = newTextBuffer("plain\ntext\nno markers\n")
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let r = registry.execute(ctx, custom("navigate.conflict.next"))
    check r.isErr

  test "navigate.conflict.next records a jump":
    let buffer = newTextBuffer(ConflictContent)
    applyConflictsToBuffer(buffer, scanBufferForConflicts(buffer))
    let ctx = createConflictTestContext(buffer)
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    let before = ctx.state.jumpList.list.len
    discard registry.execute(ctx, custom("navigate.conflict.next"))
    check ctx.state.jumpList.list.len == before + 1

suite "KeyBindings - ]x / [x resolve to conflict navigation":
  test "] x maps to navigate-conflict-next":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    check registry.processKey(EditorMode.Normal, toKeyCombo(']')).isNone
    let r = registry.processKey(EditorMode.Normal, toKeyCombo('x'))
    check r.isSome
    check r.get.name == "navigate-conflict-next"
    check r.get.commandId == "navigate.conflict.next"

  test "[ x maps to navigate-conflict-prev":
    let registry = newKeyBindingRegistry()
    registry.setupDefaultBindings()

    check registry.processKey(EditorMode.Normal, toKeyCombo('[')).isNone
    let r = registry.processKey(EditorMode.Normal, toKeyCombo('x'))
    check r.isSome
    check r.get.name == "navigate-conflict-prev"
    check r.get.commandId == "navigate.conflict.prev"
