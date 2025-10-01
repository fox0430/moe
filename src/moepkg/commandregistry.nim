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

# Import visual mode helper functions - these don't have circular dependencies
from command_handlers/visual_handler import
  clearSelection, updateSelection, getSelectionRange

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
    bcModeCommand = "mode.command"
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
    # Insert mode operations
    bcInsertChar = "insert.char"
    bcInsertBackspace = "insert.backspace"
    bcInsertDelete = "insert.delete"
    bcInsertNewline = "insert.newline"
    bcInsertLineBelow = "insert.line.below"
    bcInsertLineAbove = "insert.line.above"
    bcInsertAppend = "insert.append"
    bcInsertAppendEnd = "insert.append.end"
    # Visual mode operations
    bcVisualMoveLeft = "visual.move.left"
    bcVisualMoveRight = "visual.move.right"
    bcVisualMoveUp = "visual.move.up"
    bcVisualMoveDown = "visual.move.down"
    bcVisualDelete = "visual.delete"

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
    # Initialize command text when entering Command mode
    if cmd.targetMode == EditorMode.Command:
      ctx.state.commandText = ":"
      ctx.state.statusMessage = "" # Clear any status message
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

## Command handler implementations
proc handleModeSwitch(ctx: CommandContext, targetMode: EditorMode): Result[(), string] =
  ## Handle switching between editor modes
  ctx.state.mode = targetMode
  # Clear any pending key sequences when switching modes
  if ctx.keyBindingRegistry != nil:
    ctx.keyBindingRegistry.clearSequence
  return ok(())

proc handleInsertChar(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Handle character insertion in insert mode
  if args.len != 1 or args[0].len != 1:
    return err("Insert character requires exactly one character")

  let ch = args[0][0]
  let pos = ctx.buffer.cursor
  ctx.buffer.insertText(pos, $ch)

  # Move cursor right after insertion
  ctx.buffer.cursor.column += 1
  return ok(())

proc handleBackspace(ctx: CommandContext): Result[(), string] =
  ## Handle backspace key in insert mode
  let pos = ctx.buffer.cursor
  if pos.column > 0:
    # Move cursor back and delete
    ctx.buffer.cursor.column -= 1
    ctx.buffer.deleteChar(ctx.buffer.cursor)
  elif pos.line > 0:
    # At start of line, join with previous line
    let prevLine = ctx.buffer.getLine(pos.line - 1)
    ctx.buffer.cursor.line -= 1
    ctx.buffer.cursor.column = prevLine.len
    # Join lines by deleting the newline
    ctx.buffer.deleteChar(ctx.buffer.cursor)
  return ok(())

proc handleDelete(ctx: CommandContext): Result[(), string] =
  ## Handle delete key in insert mode
  ctx.buffer.deleteChar(ctx.buffer.cursor)
  return ok(())

proc handleNewline(ctx: CommandContext): Result[(), string] =
  ## Handle newline insertion
  let pos = ctx.buffer.cursor
  ctx.buffer.insertText(pos, "\n")

  # Move cursor to start of new line
  ctx.buffer.cursor.line += 1
  ctx.buffer.cursor.column = 0
  return ok(())

proc handleInsertLineBelow(ctx: CommandContext): Result[(), string] =
  ## Handle 'o' command - insert line below and enter insert mode
  let currentLine = ctx.buffer.cursor.line

  # Move to end of current line
  let lineContent = ctx.buffer.getLine(currentLine)
  ctx.buffer.cursor.column = lineContent.len

  # Insert newline
  ctx.buffer.insertText(ctx.buffer.cursor, "\n")

  # Move cursor to new line
  ctx.buffer.cursor.line = currentLine + 1
  ctx.buffer.cursor.column = 0

  # Switch to insert mode
  return handleModeSwitch(ctx, EditorMode.Insert)

proc handleInsertLineAbove(ctx: CommandContext): Result[(), string] =
  ## Handle 'O' command - insert line above and enter insert mode
  let currentLine = ctx.buffer.cursor.line

  # Move to start of current line
  ctx.buffer.cursor.column = 0

  # Insert newline
  ctx.buffer.insertText(ctx.buffer.cursor, "\n")

  # Move cursor to the new line (which is the current line)
  ctx.buffer.cursor.line = currentLine
  ctx.buffer.cursor.column = 0

  # Switch to insert mode
  return handleModeSwitch(ctx, EditorMode.Insert)

proc handleAppend(ctx: CommandContext): Result[(), string] =
  ## Handle 'a' command - move cursor right and enter insert mode
  let lineContent = ctx.buffer.getLine(ctx.buffer.cursor.line)

  # Only move right if not at end of line
  if ctx.buffer.cursor.column < lineContent.len:
    ctx.buffer.cursor.column += 1

  # Switch to insert mode
  return handleModeSwitch(ctx, EditorMode.Insert)

proc handleAppendEnd(ctx: CommandContext): Result[(), string] =
  ## Handle 'A' command - move to end of line and enter insert mode
  let lineContent = ctx.buffer.getLine(ctx.buffer.cursor.line)
  ctx.buffer.cursor.column = lineContent.len

  # Switch to insert mode
  return handleModeSwitch(ctx, EditorMode.Insert)

## Visual mode command handlers

proc handleVisualMoveLeft(ctx: CommandContext): Result[(), string] =
  ## Move left in visual mode and update selection
  if ctx.buffer.cursor.column > 0:
    ctx.buffer.cursor.column -= 1
    ctx.state.updateSelection(ctx.buffer.cursor)
    ctx.state.needsFullRedraw = true
  ok(())

proc handleVisualMoveRight(ctx: CommandContext): Result[(), string] =
  ## Move right in visual mode and update selection
  if ctx.buffer.cursor.column < ctx.buffer.getCurrentLineLen:
    ctx.buffer.cursor.column += 1
    ctx.state.updateSelection(ctx.buffer.cursor)
    ctx.state.needsFullRedraw = true
  ok(())

proc handleVisualMoveUp(ctx: CommandContext): Result[(), string] =
  ## Move up in visual mode and update selection
  if ctx.buffer.cursor.line > 0:
    ctx.buffer.cursor.line -= 1
    # Clamp cursor to new line length
    let newLineLen = ctx.buffer.getCurrentLineLen
    if ctx.buffer.cursor.column > newLineLen:
      ctx.buffer.cursor.column = newLineLen
    ctx.state.updateSelection(ctx.buffer.cursor)
    ctx.state.needsFullRedraw = true
  ok(())

proc handleVisualMoveDown(ctx: CommandContext): Result[(), string] =
  ## Move down in visual mode and update selection
  if ctx.buffer.cursor.line < ctx.buffer.len - 1:
    ctx.buffer.cursor.line += 1
    # Clamp cursor to new line length
    let newLineLen = ctx.buffer.getCurrentLineLen
    if ctx.buffer.cursor.column > newLineLen:
      ctx.buffer.cursor.column = newLineLen
    ctx.state.updateSelection(ctx.buffer.cursor)
    ctx.state.needsFullRedraw = true
  ok(())

proc handleVisualDelete(ctx: CommandContext): Result[(), string] =
  ## Delete visual selection
  if ctx.state.visualSelection.active:
    let (selStart, selEnd) = ctx.state.visualSelection.getSelectionRange()
    ctx.buffer.deleteRange(selStart, selEnd)
    # Move cursor to start of deleted range
    ctx.buffer.cursor = selStart
    ctx.state.clearSelection()
    ctx.state.needsFullRedraw = true
    # Return to previous mode
    ctx.state.previousMode = ctx.state.mode
    ctx.state.mode = ctx.state.previousMode
  ok(())

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
      handleModeSwitch(ctx, EditorMode.Normal),
    0,
    0,
  )

  registry.register(
    builtin(bcModeInsert),
    "Insert Mode",
    "Switch to insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleModeSwitch(ctx, EditorMode.Insert),
    0,
    0,
  )

  registry.register(
    builtin(bcModeCommand),
    "Command Mode",
    "Switch to command mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Clear command text when entering command mode
      ctx.state.commandText = ":"
      handleModeSwitch(ctx, EditorMode.Command),
    0,
    0,
  )

  # Insert mode character insertion
  registry.register(
    builtin(bcInsertChar),
    "Insert Character",
    "Insert a character at cursor position",
    handleInsertChar,
    1,
    1,
  )

  # Insert mode backspace
  registry.register(
    builtin(bcInsertBackspace),
    "Backspace",
    "Delete character before cursor",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleBackspace(ctx),
    0,
    0,
  )

  # Insert mode delete
  registry.register(
    builtin(bcInsertDelete),
    "Delete",
    "Delete character at cursor",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleDelete(ctx),
    0,
    0,
  )

  # Insert mode newline
  registry.register(
    builtin(bcInsertNewline),
    "Insert Newline",
    "Insert a newline at cursor position",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleNewline(ctx),
    0,
    0,
  )

  # Insert new line below and switch to insert mode (o command)
  registry.register(
    builtin(bcInsertLineBelow),
    "Insert Line Below",
    "Insert new line below current line and switch to insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleInsertLineBelow(ctx),
    0,
    0,
  )

  # Insert new line above and switch to insert mode (O command)
  registry.register(
    builtin(bcInsertLineAbove),
    "Insert Line Above",
    "Insert new line above current line and switch to insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleInsertLineAbove(ctx),
    0,
    0,
  )

  # Append command (a) - move cursor right and enter insert mode
  registry.register(
    builtin(bcInsertAppend),
    "Append",
    "Move cursor right and enter insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleAppend(ctx),
    0,
    0,
  )

  # Append at line end (A) - move to end of line and enter insert mode
  registry.register(
    builtin(bcInsertAppendEnd),
    "Append at End",
    "Move to end of line and enter insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleAppendEnd(ctx),
    0,
    0,
  )

  # Visual mode movement commands
  registry.register(
    builtin(bcVisualMoveLeft),
    "Visual Move Left",
    "Move left and update visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveLeft(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveRight),
    "Visual Move Right",
    "Move right and update visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveRight(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveUp),
    "Visual Move Up",
    "Move up and update visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveUp(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveDown),
    "Visual Move Down",
    "Move down and update visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveDown(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualDelete),
    "Visual Delete",
    "Delete visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualDelete(ctx),
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
