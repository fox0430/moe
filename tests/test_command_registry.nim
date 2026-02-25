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

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/command_registry {.all.}
import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/modes {.all.}

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
    check registry.aliases.len == 0

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

suite "CommandRegistry - registerAlias":
  test "register alias for builtin command":
    let registry = newCommandRegistry()

    registry.register(
      builtin(bcMotionLeft),
      "Left",
      "Move left",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    registry.registerAlias("h", builtin(bcMotionLeft))

    let cmd = registry.findCommand("h")
    check cmd.isSome
    check cmd.get.name == "Left"

  test "register alias with CommandId":
    let registry = newCommandRegistry()

    registry.register(
      custom("test.cmd"),
      "TestCmd",
      "Test command",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    registry.registerAlias("tc", custom("test.cmd"))

    let cmd = registry.findCommand("tc")
    check cmd.isSome
    check cmd.get.name == "TestCmd"

  test "alias for non-existent command is not registered":
    let registry = newCommandRegistry()

    # Try to register alias for command that doesn't exist
    registry.registerAlias("x", builtin(bcMotionLeft))

    let cmd = registry.findCommand("x")
    check cmd.isNone

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

  test "find command by alias":
    let registry = newCommandRegistry()

    registry.register(
      builtin(bcEditUndo),
      "Undo",
      "Undo edit",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    registry.registerAlias("u", builtin(bcEditUndo))

    let cmd = registry.findCommand("u")
    check cmd.isSome
    check cmd.get.name == "Undo"

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

  test "file commands have correct string values":
    check $bcFileSave == "file.save"
    check $bcFileOpen == "file.open"
    check $bcFileNew == "file.new"
    check $bcFileClose == "file.close"

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

  test "jump commands have correct string values":
    check $bcJumpBack == "jump.back"
    check $bcJumpForward == "jump.forward"

  test "LSP commands have correct string values":
    check $bcLspGotoDefinition == "lsp.goto.definition"
    check $bcLspFindReferences == "lsp.find.references"
    check $bcLspCodeLensExecute == "lsp.codelens.execute"

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
    let state = EditorState()
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
      cursor: state.cursor,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
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
  test "multiple aliases for same command":
    let registry = newCommandRegistry()
    registry.register(
      builtin(bcMotionLeft),
      "Left",
      "Move left",
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        ok(()),
    )

    registry.registerAlias("h", builtin(bcMotionLeft))
    registry.registerAlias("left", builtin(bcMotionLeft))
    registry.registerAlias("cursor-left", builtin(bcMotionLeft))

    check registry.findCommand("h").isSome
    check registry.findCommand("left").isSome
    check registry.findCommand("cursor-left").isSome

    # All should resolve to same command
    check registry.findCommand("h").get.name == "Left"
    check registry.findCommand("left").get.name == "Left"
    check registry.findCommand("cursor-left").get.name == "Left"

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
    let state = EditorState()
    state.cursor = BufferPosition(line: 0, column: 0)
    state.mode = EditorMode.Normal

    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, height: 24, width: 80, x: 0, y: 0)
    let motionController = newMotionController(buffer, state, viewport)

    result = CommandContext(
      buffer: buffer,
      state: state,
      cursor: state.cursor,
      motionController: motionController,
      clipboardConfig: ClipboardConfig(enable: false),
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
    check ctx.state.findCharMatches == @[0, 2, 4, 6]
    check ctx.state.findCharMatchLine == 0

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
    check ctx.state.findCharMatches == @[0, 2, 4, 6]
    check ctx.state.findCharMatchLine == 0

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
    check ctx.state.findCharMatches == @[3]
    check ctx.state.findCharMatchLine == 0

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
    check ctx.state.findCharMatches == @[3]
    check ctx.state.findCharMatchLine == 0

  test "Non-find/till command clears highlight":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    ctx.state.findCharMatches = @[0, 2, 4, 6]
    ctx.state.findCharMatchLine = 0
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
    check ctx.state.findCharMatches.len == 0

  test "Operator+find does not set highlight":
    let buffer = newTextBuffer("abacada")
    let ctx = createFindTestContext(buffer)
    ctx.state.registers = initRegisters()
    let registry = newCommandRegistry()
    registerBuiltinCommands(registry)

    # Set pending operator (simulate 'd')
    ctx.state.editState.pendingOperator = some(
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
    check ctx.state.findCharMatches.len == 0
