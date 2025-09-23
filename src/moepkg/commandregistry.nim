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

## Command registry and execution system
##
## This module provides a centralized command registry that decouples
## command definitions from key bindings, allowing flexible configuration.

import std/[tables, options, strutils]

import pkg/results

import types, buffer, motion, keybindings, modes

type
  ## Built-in command identifiers
  BuiltinCommandId* = enum
    bcNone = ""
    # Motion commands
    bcMotionLeft = "motion.left"
    bcMotionRight = "motion.right"
    bcMotionUp = "motion.up"
    bcMotionDown = "motion.down"
    bcMotionPageUp = "motion.pageup"
    bcMotionPageDown = "motion.pagedown"
    bcMotionHome = "motion.home"
    bcMotionEnd = "motion.end"
    bcMotionFirstLine = "motion.firstline"
    bcMotionLastLine = "motion.lastline"
    bcMotionWord = "motion.word"
    bcMotionWordBack = "motion.word.back"
    bcMotionWordEnd = "motion.word.end"
    # Mode switching commands
    bcModeNormal = "mode.normal"
    bcModeInsert = "mode.insert"
    # File operations
    bcFileSave = "file.save"
    bcFileOpen = "file.open"
    bcFileNew = "file.new"
    bcFileClose = "file.close"
    # Edit operations
    bcEditUndo = "edit.undo"
    bcEditRedo = "edit.redo"
    bcEditCut = "edit.cut"
    bcEditCopy = "edit.copy"
    bcEditPaste = "edit.paste"

  ## Command ID can be builtin or custom
  CommandIdKind* = enum
    ckBuiltin
    ckCustom

  CommandId* = object
    case kind*: CommandIdKind
    of ckBuiltin:
      builtin*: BuiltinCommandId
    of ckCustom:
      custom*: string

  ## Context needed to execute commands
  CommandContext* = ref object
    buffer*: buffer.TextBuffer
    state*: EditorState
    viewport*: ViewPort
    motionController*: MotionController
    keyBindingRegistry*: keybindings.KeyBindingRegistry

  ## Function signature for command handlers
  CommandHandler* =
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] {.closure.}

  ## Command information stored in registry
  RegisteredCommand* = object
    id*: CommandId
    name*: string
    description*: string
    handler*: CommandHandler
    minArgs*: int
    maxArgs*: int

  ## Central command registry
  CommandRegistry* = ref object
    commands*: Table[string, RegisteredCommand]
    builtinCommands*: array[BuiltinCommandId, RegisteredCommand]
      ## Fast access for builtins
    aliases*: Table[string, CommandId] ## Alias -> command ID mapping

## Helper functions for CommandId
proc `$`*(id: CommandId): string =
  case id.kind
  of ckBuiltin:
    return $id.builtin
  of ckCustom:
    return id.custom

proc `==`*(a, b: CommandId): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of ckBuiltin:
    return a.builtin == b.builtin
  of ckCustom:
    return a.custom == b.custom

proc builtin*(id: BuiltinCommandId): CommandId =
  ## Create a CommandId from a builtin command
  CommandId(kind: ckBuiltin, builtin: id)

proc custom*(id: string): CommandId =
  ## Create a CommandId from a custom command string
  CommandId(kind: ckCustom, custom: id)

proc newCommandRegistry*(): CommandRegistry =
  ## Create a new command registry
  result = CommandRegistry(
    commands: initTable[string, RegisteredCommand](),
    aliases: initTable[string, CommandId](),
  )
  # Initialize builtin commands array with empty entries
  for i in BuiltinCommandId:
    result.builtinCommands[i] = RegisteredCommand(
      id: builtin(i), name: "", description: "", handler: nil, minArgs: 0, maxArgs: 0
    )

proc register*(
    registry: CommandRegistry,
    id: CommandId,
    name: string,
    description: string,
    handler: CommandHandler,
    minArgs = 0,
    maxArgs = 100,
) =
  ## Register a new command
  let cmd = RegisteredCommand(
    id: id,
    name: name,
    description: description,
    handler: handler,
    minArgs: minArgs,
    maxArgs: maxArgs,
  )

  # Store in appropriate location
  let idStr = $id
  registry.commands[idStr] = cmd

  # Also store in builtin array for fast access
  if id.kind == ckBuiltin and id.builtin != bcNone:
    registry.builtinCommands[id.builtin] = cmd

proc registerAlias*(registry: CommandRegistry, alias: string, commandId: CommandId) =
  ## Register an alias for a command
  let idStr = $commandId
  if idStr in registry.commands:
    registry.aliases[alias] = commandId

proc registerAlias*(
    registry: CommandRegistry, alias: string, builtinId: BuiltinCommandId
) =
  ## Convenience overload for builtin commands
  registry.registerAlias(alias, builtin(builtinId))

proc findCommand*(registry: CommandRegistry, id: CommandId): Option[RegisteredCommand] =
  ## Find a command by CommandId
  # Fast path for builtin commands
  if id.kind == ckBuiltin and id.builtin != bcNone:
    let cmd = registry.builtinCommands[id.builtin]
    if not cmd.handler.isNil:
      return some(cmd)

  # General path
  let idStr = $id
  if idStr in registry.commands:
    return some(registry.commands[idStr])

  return none(RegisteredCommand)

proc findCommand*(
    registry: CommandRegistry, idOrAlias: string
): Option[RegisteredCommand] =
  ## Find a command by string ID or alias
  if idOrAlias in registry.commands:
    return some(registry.commands[idOrAlias])

  if idOrAlias in registry.aliases:
    let id = registry.aliases[idOrAlias]
    return registry.findCommand(id)

  return none(RegisteredCommand)

proc execute*(
    registry: CommandRegistry,
    ctx: CommandContext,
    commandId: CommandId,
    args: seq[string] = @[],
): Result[(), string] =
  ## Execute a command by CommandId
  let cmd = registry.findCommand(commandId)
  if cmd.isNone:
    return Result[(), string].err "Command not found"

  let command = cmd.get
  if args.len < command.minArgs:
    return Result[(), string].err "Too few arguments: expected at least " &
      $command.minArgs & ", got " & $args.len
  if args.len > command.maxArgs:
    return Result[(), string].err "Too many arguments: expected at most " &
      $command.maxArgs & ", got " & $args.len

  return command.handler(ctx, args)

proc execute*(
    registry: CommandRegistry,
    ctx: CommandContext,
    commandIdStr: string,
    args: seq[string] = @[],
): Result[(), string] =
  ## Execute a command by string ID (for backward compatibility)
  let cmd = registry.findCommand(commandIdStr)
  if cmd.isNone:
    return Result[(), string].err "Command not found"

  let command = cmd.get
  if args.len < command.minArgs:
    return Result[(), string].err "Too few arguments: expected at least " &
      $command.minArgs & ", got " & $args.len
  if args.len > command.maxArgs:
    return Result[(), string].err "Too many arguments: expected at most " &
      $command.maxArgs & ", got " & $args.len

  return command.handler(ctx, args)

proc executeCommand*(
    registry: CommandRegistry, ctx: CommandContext, cmd: keybindings.Command
): Result[(), string] =
  ## Execute a keybinding command
  case cmd.kind
  of ctMotion:
    # Handle motion commands directly - use numeric prefix if available
    let count =
      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.getNumericPrefix()
      else:
        1
    let motionCmd = MotionCommand(motion: cmd.motion, count: count)
    # Clear the numeric prefix after using it
    if ctx.keyBindingRegistry != nil:
      ctx.keyBindingRegistry.sequenceState.numericPrefix = ""
      ctx.keyBindingRegistry.sequenceState.hasNumericPrefix = false
    return ctx.motionController.executeMotion(motionCmd)
  of ctModeSwitch:
    # Handle mode switching
    ctx.state.mode = cmd.targetMode
    # Clear any pending key sequences when switching modes
    if ctx.keyBindingRegistry != nil:
      ctx.keyBindingRegistry.clearSequence
    return ok(())
  of ctOperatorPending:
    # Handle operators that need character input (f, t, r, etc)
    # The character should have been set by processKey
    let count =
      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.getNumericPrefix()
      else:
        1
    case cmd.operatorType
    of "find":
      # Execute find character motion
      let motionCmd =
        if cmd.reverse:
          MotionCommand(
            motion: Motion.FindCharBackward, targetChar: cmd.targetChar, count: count
          )
        else:
          MotionCommand(
            motion: Motion.FindChar, targetChar: cmd.targetChar, count: count
          )
      # Clear the numeric prefix after using it
      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.sequenceState.numericPrefix = ""
        ctx.keyBindingRegistry.sequenceState.hasNumericPrefix = false
      return ctx.motionController.executeMotion(motionCmd)
    of "till":
      # Execute till character motion
      let motionCmd =
        if cmd.reverse:
          MotionCommand(
            motion: Motion.TillCharBackward, targetChar: cmd.targetChar, count: count
          )
        else:
          MotionCommand(
            motion: Motion.TillChar, targetChar: cmd.targetChar, count: count
          )
      # Clear the numeric prefix after using it
      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.sequenceState.numericPrefix = ""
        ctx.keyBindingRegistry.sequenceState.hasNumericPrefix = false
      return ctx.motionController.executeMotion(motionCmd)
    of "replace":
      # Execute replace character action
      # This would need to be implemented in the actual editor
      return Result[(), string].err "Replace command not yet implemented"
    else:
      return Result[(), string].err "Unknown operator type: " & cmd.operatorType
  of ctAction, ctTextObject, ctOperator, ctCustom:
    # Execute through registry - convert string to CommandId
    # First try as alias, then as custom command
    let cmdResult = registry.findCommand(cmd.commandId)
    if cmdResult.isSome:
      # Found via alias or existing command
      return registry.execute(ctx, cmdResult.get.id, cmd.args)
    else:
      # Try as custom command
      return registry.execute(ctx, custom(cmd.commandId), cmd.args)

## Helper function to parse count from arguments safely
proc parseCount(
    args: seq[string], default: int = 1, minVal: int = 1, maxVal: int = 999999
): int =
  ## Parse count from arguments with validation
  ## - Returns default if no args or parsing fails
  ## - Clamps value to [minVal, maxVal] range
  ## - Ensures positive counts for motions
  if args.len > 0 and args[0].len > 0:
    try:
      let val = parseInt(args[0])
      # Clamp to valid range
      if val < minVal:
        return minVal
      elif val > maxVal:
        return maxVal
      else:
        return val
    except ValueError:
      return default
  else:
    return default

## Helper function to parse optional string argument
proc parseStringArg(args: seq[string], index: int = 0, default: string = ""): string =
  ## Safely get string argument at index, return default if not available
  if args.len > index:
    return args[index]
  else:
    return default

## Helper function to parse boolean argument
proc parseBoolArg(args: seq[string], index: int = 0, default: bool = false): bool =
  ## Parse boolean argument (true/false, yes/no, 1/0)
  if args.len > index:
    let arg = args[index].toLowerAscii()
    case arg
    of "true", "yes", "1", "on":
      return true
    of "false", "no", "0", "off":
      return false
    else:
      return default
  else:
    return default

## Helper function to register motion commands
proc registerMotionCommand(
    registry: CommandRegistry,
    id: BuiltinCommandId,
    name: string,
    description: string,
    motion: Motion,
    acceptsCount: bool = true,
) =
  ## Register a motion command with common handler pattern
  let maxArgs = if acceptsCount: 1 else: 0

  registry.register(
    builtin(id),
    name,
    description,
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count =
        if acceptsCount:
          parseCount(args)
        else:
          1
      let cmd = MotionCommand(motion: motion, count: count)
      return ctx.motionController.executeMotion(cmd),
    0,
    maxArgs,
  )

## Register built-in commands
proc registerBuiltinCommands*(registry: CommandRegistry) =
  ## Register all built-in commands

  # Motion commands - Using helper function
  registry.registerMotionCommand(
    bcMotionLeft, "Move Left", "Move cursor left", Motion.Left
  )
  registry.registerMotionCommand(
    bcMotionRight, "Move Right", "Move cursor right", Motion.Right
  )
  registry.registerMotionCommand(bcMotionUp, "Move Up", "Move cursor up", Motion.Up)
  registry.registerMotionCommand(
    bcMotionDown, "Move Down", "Move cursor down", Motion.Down
  )
  registry.registerMotionCommand(
    bcMotionPageUp, "Page Up", "Scroll page up", Motion.PageUp
  )
  registry.registerMotionCommand(
    bcMotionPageDown, "Page Down", "Scroll page down", Motion.PageDown
  )
  registry.registerMotionCommand(
    bcMotionHome, "Home", "Move to beginning of line", Motion.Home, false
  )
  registry.registerMotionCommand(
    bcMotionEnd, "End", "Move to end of line", Motion.End, false
  )
  registry.registerMotionCommand(
    bcMotionFirstLine, "First Line", "Move to first line", Motion.FirstLine, false
  )
  registry.registerMotionCommand(
    bcMotionLastLine, "Last Line", "Move to last line", Motion.LastLine, false
  )

  # Mode switching commands
  registry.register(
    builtin(bcModeNormal),
    "Normal Mode",
    "Switch to normal mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.state.mode = EditorMode.Normal
      # Clear any pending key sequences when switching modes
      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.clearSequence
      return ok(()),
    0,
    0,
  )

  registry.register(
    builtin(bcModeInsert),
    "Insert Mode",
    "Switch to insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      ctx.state.mode = EditorMode.Insert
      # Clear any pending key sequences when switching modes
      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.clearSequence
      return ok(()),
    0,
    0,
  )

  # Register mock delete commands for testing sequences
  registry.register(
    custom("delete.word"),
    "Delete Word",
    "Delete word under cursor",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Mock implementation
      echo "DELETE WORD (mock)"
      return ok(()),
    0,
    0,
  )

  registry.register(
    custom("delete.line"),
    "Delete Line",
    "Delete current line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Mock implementation
      echo "DELETE LINE (mock)"
      return ok(()),
    0,
    0,
  )

  registry.register(
    custom("change.word"),
    "Change Word",
    "Change word under cursor",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Mock implementation
      echo "CHANGE WORD (mock)"
      ctx.state.mode = EditorMode.Insert
      return ok(()),
    0,
    0,
  )

  # Register common aliases
  registry.registerAlias("h", bcMotionLeft)
  registry.registerAlias("l", bcMotionRight)
  registry.registerAlias("j", bcMotionDown)
  registry.registerAlias("k", bcMotionUp)
  registry.registerAlias("w", bcMotionWord)
  registry.registerAlias("b", bcMotionWordBack)
  registry.registerAlias("e", bcMotionWordEnd)
  registry.registerAlias("gg", bcMotionFirstLine)
  registry.registerAlias("G", bcMotionLastLine)
