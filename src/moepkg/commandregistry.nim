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

import std/[tables, options, strutils, unicode]

import pkg/results

import
  types, buffer, motion, keybindings, modes, cursor, search_utils, clipboard, config,
  logger

import command_handlers/[visual_commands, insert_commands, normal_commands]

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
    clipboardConfig*: ClipboardConfig

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

proc executeOperatorOnRange(
    ctx: CommandContext,
    operatorType: OperatorType,
    range: OperatorRange,
    operatorCount: int,
): Result[(), string] =
  ## Execute an operator on the given range
  ## operatorCount: count before operator (e.g., "2" in "2d3w")

  logDebug(
    "operator",
    "executeOperatorOnRange: " & $operatorType & " on range " & $range.start & " to " &
      $range.endPos & ", linewise=" & $range.isLinewise,
  )

  case operatorType
  of OpYank:
    # Yank (copy) the range
    let text = extractRangeText(ctx.buffer, range)
    ctx.state.yankRegister = text
    ctx.state.yankIsLine = range.isLinewise

    # Also write to system clipboard if enabled
    if ctx.clipboardConfig.enable:
      discard writeToClipboard(ctx.clipboardConfig.tool, text)

    let lineCount =
      if range.isLinewise:
        range.endPos.line - range.start.line + 1
      else:
        0
    ctx.state.statusMessage =
      if range.isLinewise:
        "Yanked " & $lineCount & " line(s)"
      else:
        "Yanked " & $text.len & " character(s)"

    # Don't move cursor for yank
    return ok(())
  of OpDelete:
    # Delete the range (and yank it)
    let text = extractRangeText(ctx.buffer, range)
    ctx.state.yankRegister = text
    ctx.state.yankIsLine = range.isLinewise

    # Also write to system clipboard if enabled
    if ctx.clipboardConfig.enable:
      discard writeToClipboard(ctx.clipboardConfig.tool, text)

    # Delete the text
    let delResult = deleteRange(ctx.buffer, range)
    if delResult.isErr:
      return err(delResult.error)

    # Move cursor to start of deletion
    ctx.state.cursor = range.start
    # Clamp cursor to valid position
    if ctx.state.cursor.line >= ctx.buffer.len:
      ctx.state.cursor.line = max(0, ctx.buffer.len - 1)
    if ctx.state.cursor.line < ctx.buffer.len:
      let line = ctx.buffer.getLine(ctx.state.cursor.line)
      ctx.state.cursor.column = min(ctx.state.cursor.column, max(0, line.charLen - 1))

    ctx.state.needsFullRedraw = true
    return ok(())
  of OpChange:
    # Change the range (delete and enter insert mode)
    let text = extractRangeText(ctx.buffer, range)
    ctx.state.yankRegister = text
    ctx.state.yankIsLine = range.isLinewise

    # Delete the text
    let delResult = deleteRange(ctx.buffer, range)
    if delResult.isErr:
      return err(delResult.error)

    # Move cursor to start of change
    ctx.state.cursor = range.start
    # Clamp cursor
    if ctx.state.cursor.line >= ctx.buffer.len:
      ctx.state.cursor.line = max(0, ctx.buffer.len - 1)

    # Enter insert mode
    ctx.state.mode = EditorMode.Insert
    ctx.state.needsFullRedraw = true

    # Begin transaction for insert mode
    let transactionResult = ctx.buffer.beginTransaction("Change operation")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    return ok(())
  else:
    return err("Operator " & $operatorType & " not yet implemented")

proc executeCommand*(
    registry: CommandRegistry, ctx: CommandContext, cmd: keybindings.Command
): Result[(), string] =
  ## Execute a keybinding command
  case cmd.kind
  of ctMotion:
    # Handle motion commands directly - use count from command object
    let count = cmd.count

    logDebug("command", "Motion command: " & $cmd.motion & " with count=" & $count)

    let motionCmd = MotionCommand(motion: cmd.motion, count: count)

    # Check if we have a pending operator
    if ctx.state.pendingOperator.isSome:
      let op = ctx.state.pendingOperator.get
      logDebug(
        "operator",
        "Executing operator+motion: " & $op.operatorType & " with " & $cmd.motion,
      )

      # Execute motion to get end position
      let r = ctx.motionController.executeMotion(motionCmd, op.startPos)
      if r.isErr:
        ctx.state.pendingOperator = none(PendingOperator)
        return err(r.error)

      # Calculate the range affected by this operator+motion
      let range = calculateOperatorRange(ctx.buffer, op.startPos, r.value, cmd.motion)

      block:
        # Execute the operator on the range
        let r = executeOperatorOnRange(ctx, op.operatorType, range, op.operatorCount)
        ctx.state.pendingOperator = none(PendingOperator)
        if r.isErr:
          return err(r.error)

      return ok(())
    else:
      # No pending operator - just move cursor
      let r = ctx.motionController.executeMotion(motionCmd, ctx.state.cursor)
      if r.isErr:
        return err(r.error)
      ctx.state.cursor = r.value
      return Result[(), string].ok ()
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
    let count = cmd.count
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
      let r = ctx.motionController.executeMotion(motionCmd, ctx.state.cursor)
      if r.isErr:
        return err(r.error)
      ctx.state.cursor = r.value
      return Result[(), string].ok ()
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
      let r = ctx.motionController.executeMotion(motionCmd, ctx.state.cursor)
      if r.isErr:
        return err(r.error)
      ctx.state.cursor = r.value
      return Result[(), string].ok ()
    of "replace":
      # Execute replace character action
      # This would need to be implemented in the actual editor
      return Result[(), string].err "Replace command not yet implemented"
    else:
      return Result[(), string].err "Unknown operator type: " & cmd.operatorType
  of ctAction, ctTextObject, ctOperator, ctCustom:
    # Execute through registry - convert string to CommandId
    # Get count from command object
    let count = cmd.count

    # Debug: log the count
    logDebug("command", "Executing " & cmd.commandId & " with count=" & $count)

    # Prepare args with count as first argument if count > 1
    var finalArgs = cmd.args
    if count > 1:
      finalArgs = @[$count] & cmd.args
    logDebug("command", "finalArgs (count=" & $count & "): " & $finalArgs)

    # Clear the numeric prefix after using it
    if ctx.keyBindingRegistry != nil:
      ctx.keyBindingRegistry.sequenceState.numericPrefix = ""
      ctx.keyBindingRegistry.sequenceState.hasNumericPrefix = false

    # First try as alias, then as custom command
    let cmdResult = registry.findCommand(cmd.commandId)
    if cmdResult.isSome:
      # Found via alias or existing command
      return registry.execute(ctx, cmdResult.get.id, finalArgs)
    else:
      # Try as custom command
      return registry.execute(ctx, custom(cmd.commandId), finalArgs)

## Helper function to parse count from arguments safely
proc parseCount(
    args: seq[string], default: int = 1, minVal: int = 1, maxVal: int = 999999
): int =
  ## Parse count from arguments with validation
  ## - Returns default if no args or parsing fails
  ## - Clamps value to [minVal, maxVal] range
  ## - Ensures positive counts for motions
  logDebug("parse", "parseCount called with args.len=" & $args.len & ", args=" & $args)
  if args.len > 0 and args[0].len > 0:
    try:
      let val = parseInt(args[0])
      # Clamp to valid range
      let parsedCount =
        if val < minVal:
          minVal
        elif val > maxVal:
          maxVal
        else:
          val
      logDebug("parse", "parseCount returning: " & $parsedCount)
      return parsedCount
    except ValueError:
      logDebug("parse", "parseCount returning default (parse error): " & $default)
      return default
  else:
    logDebug("parse", "parseCount returning default (no args): " & $default)
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
      let r = ctx.motionController.executeMotion(cmd, ctx.state.cursor)
      if r.isErr:
        return err(r.error)
      ctx.state.cursor = r.value
      return Result[(), string].ok (),
    0,
    maxArgs,
  )

## Command handler wrappers (delegate to mode-specific command modules)

proc handleModeSwitch(ctx: CommandContext, targetMode: EditorMode): Result[(), string] =
  ## Handle switching between editor modes
  switchMode(ctx.state, targetMode, ctx.keyBindingRegistry)
  Result[(), string].ok ()

proc handleInsertChar(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Handle character insertion in insert mode
  if args.len != 1 or args[0].len != 1:
    return err("Insert character requires exactly one character")
  insertChar(ctx.buffer, ctx.state, args[0][0])
  Result[(), string].ok ()

proc handleBackspace(ctx: CommandContext): Result[(), string] =
  ## Handle backspace key in insert mode
  insertBackspace(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleDelete(ctx: CommandContext): Result[(), string] =
  ## Handle delete key in insert mode
  insertDelete(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleNewline(ctx: CommandContext): Result[(), string] =
  ## Handle newline insertion
  insertNewline(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleInsertLineBelow(ctx: CommandContext): Result[(), string] =
  ## Handle 'o' command - insert line below and enter insert mode
  insertLineBelow(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleInsertLineAbove(ctx: CommandContext): Result[(), string] =
  ## Handle 'O' command - insert line above and enter insert mode
  insertLineAbove(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleAppend(ctx: CommandContext): Result[(), string] =
  ## Handle 'a' command - move cursor right and enter insert mode
  insertAppend(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleAppendEnd(ctx: CommandContext): Result[(), string] =
  ## Handle 'A' command - move to end of line and enter insert mode
  insertAppendEnd(ctx.buffer, ctx.state)
  Result[(), string].ok ()

## Visual mode command handlers (wrappers for visual_handler functions)

proc handleVisualMoveLeft(ctx: CommandContext): Result[(), string] =
  ## Move left in visual mode and update selection
  visualMoveLeft(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleVisualMoveRight(ctx: CommandContext): Result[(), string] =
  ## Move right in visual mode and update selection
  visualMoveRight(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleVisualMoveUp(ctx: CommandContext): Result[(), string] =
  ## Move up in visual mode and update selection
  visualMoveUp(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleVisualMoveDown(ctx: CommandContext): Result[(), string] =
  ## Move down in visual mode and update selection
  visualMoveDown(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleVisualDelete(ctx: CommandContext): Result[(), string] =
  ## Delete visual selection
  visualDelete(ctx.buffer, ctx.state)
  Result[(), string].ok ()

## Clipboard command handlers

proc handleClipboardCopy(ctx: CommandContext): Result[(), string] =
  ## Copy selected text to system clipboard
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # Get selected text
  let selectedText = getSelectedText(ctx.state, ctx.buffer)
  if selectedText.len == 0:
    return err("No text selected")

  # Write to clipboard
  let writeResult = writeToClipboard(ctx.clipboardConfig.tool, selectedText)
  if writeResult.isErr:
    return err(writeResult.error)

  return Result[(), string].ok ()

proc handleClipboardPaste(ctx: CommandContext): Result[(), string] =
  ## Paste text from system clipboard at cursor position
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # Read from clipboard
  let readResult = readFromClipboard(ctx.clipboardConfig.tool)
  if readResult.isErr:
    return err(readResult.error)

  let clipboardText = readResult.value
  if clipboardText.len == 0:
    return Result[(), string].ok () # Nothing to paste

  # Insert text at cursor position
  let insertResult = ctx.buffer.insertText(ctx.state.cursor, clipboardText)
  if insertResult.isErr:
    return err(insertResult.error)

  # Update cursor position to end of pasted text
  # Note: For simplicity, we'll keep cursor at original position for now
  # A more sophisticated implementation would move cursor to end of paste

  ctx.state.needsFullRedraw = true
  return Result[(), string].ok ()

proc handlePasteAfter(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Paste text from internal register or system clipboard after cursor (p command)
  ## Mimics Vim's 'p' behavior
  ## count: number of times to paste (default: 1)

  logDebug("paste", "handlePasteAfter called with count=" & $count)
  let actualCount = max(1, count)

  # First try to use internal yank register
  var pasteText = ctx.state.yankRegister
  var isFullLine = ctx.state.yankIsLine

  logDebug(
    "paste",
    "Using internal register, length: " & $pasteText.len & ", isLine=" & $isFullLine,
  )

  # If internal register is empty, try system clipboard (if enabled)
  if pasteText.len == 0 and ctx.clipboardConfig.enable:
    logDebug("paste", "Internal register empty, trying clipboard")
    let readResult = readFromClipboard(ctx.clipboardConfig.tool)
    if readResult.isErr:
      return err(
        "Nothing to paste (yank register empty and clipboard error: " & readResult.error &
          ")"
      )

    pasteText = readResult.value
    # Detect if it's a full line from clipboard
    isFullLine = pasteText.len > 0 and pasteText[^1] == '\n'
    logDebug("paste", "Got from clipboard, length: " & $pasteText.len)

  if pasteText.len == 0:
    return err("Nothing to paste")

  # Begin transaction if count > 1 to group all pastes into single undo entry
  if actualCount > 1:
    let txnResult = ctx.buffer.beginTransaction("paste " & $actualCount & " times")
    if txnResult.isErr:
      return err(txnResult.error)

  # Paste count times
  for i in 1 .. actualCount:
    if isFullLine:
      # Paste on new line below current line (Vim 'p' behavior for linewise yank)
      let currentLine = ctx.buffer.getLine(ctx.state.cursor.line)
      let pastePos =
        BufferPosition(line: ctx.state.cursor.line, column: currentLine.charLen)

      # Insert the paste content
      # Remove trailing newline from pasteText and add newline prefix
      let textToInsert =
        "\n" & pasteText.strip(leading = false, trailing = true, chars = {'\n'})
      let insertResult = ctx.buffer.insertText(pastePos, textToInsert)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.commitTransaction()
        return err(insertResult.error)

      # Move cursor to the start of pasted line (next line)
      ctx.state.cursor.line = ctx.state.cursor.line + 1
      ctx.state.cursor.column = 0
    else:
      # Paste after cursor position (Vim 'p' behavior for characterwise yank)
      let lineContent = ctx.buffer.getLine(ctx.state.cursor.line)
      var pastePos = ctx.state.cursor

      # Move one character right if not at end of line (only for first paste)
      if i == 1 and ctx.state.cursor.column < lineContent.charLen:
        pastePos.column = ctx.state.cursor.column + 1

      let insertResult = ctx.buffer.insertText(pastePos, pasteText)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.commitTransaction()
        return err(insertResult.error)

      # Update cursor position for next paste
      ctx.state.cursor.column = pastePos.column + pasteText.len

  # Commit transaction if we started one
  if actualCount > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  ctx.state.needsFullRedraw = true
  return Result[(), string].ok ()

proc handlePasteBefore(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Paste text from internal register or system clipboard before cursor (P command)
  ## Mimics Vim's 'P' behavior
  ## count: number of times to paste (default: 1)

  logDebug("paste", "handlePasteBefore called with count=" & $count)
  let actualCount = max(1, count)

  # First try to use internal yank register
  var pasteText = ctx.state.yankRegister
  var isFullLine = ctx.state.yankIsLine

  logDebug(
    "paste",
    "Using internal register, length: " & $pasteText.len & ", isLine=" & $isFullLine,
  )

  # If internal register is empty, try system clipboard (if enabled)
  if pasteText.len == 0 and ctx.clipboardConfig.enable:
    logDebug("paste", "Internal register empty, trying clipboard")
    let readResult = readFromClipboard(ctx.clipboardConfig.tool)
    if readResult.isErr:
      return err(
        "Nothing to paste (yank register empty and clipboard error: " & readResult.error &
          ")"
      )

    pasteText = readResult.value
    # Detect if it's a full line from clipboard
    isFullLine = pasteText.len > 0 and pasteText[^1] == '\n'
    logDebug("paste", "Got from clipboard, length: " & $pasteText.len)

  if pasteText.len == 0:
    return err("Nothing to paste")

  # Begin transaction if count > 1 to group all pastes into single undo entry
  if actualCount > 1:
    let txnResult = ctx.buffer.beginTransaction("paste " & $actualCount & " times")
    if txnResult.isErr:
      return err(txnResult.error)

  # Paste count times
  for i in 1 .. actualCount:
    if isFullLine:
      # Paste on new line above current line (Vim 'P' behavior for linewise yank)
      let pastePos = BufferPosition(line: ctx.state.cursor.line, column: 0)

      # Insert the paste content
      # Remove trailing newline from pasteText and add newline suffix
      let textToInsert =
        pasteText.strip(leading = false, trailing = true, chars = {'\n'}) & "\n"
      let insertResult = ctx.buffer.insertText(pastePos, textToInsert)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.commitTransaction()
        return err(insertResult.error)

      # Cursor stays at current line (which is now the pasted content)
      ctx.state.cursor.column = 0
    else:
      # Paste at cursor position (Vim 'P' behavior for characterwise yank)
      let pastePos = ctx.state.cursor

      let insertResult = ctx.buffer.insertText(pastePos, pasteText)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.commitTransaction()
        return err(insertResult.error)

      # Update cursor position for next paste
      ctx.state.cursor.column = pastePos.column + pasteText.len

  # Commit transaction if we started one
  if actualCount > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  ctx.state.needsFullRedraw = true
  return Result[(), string].ok ()

proc handleDeleteChar(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete character(s) at cursor position (x command)
  ## count: number of characters to delete (default: 1)

  logDebug("delete", "handleDeleteChar called with count=" & $count)
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.state.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.state.cursor.column >= lineContent.charLen:
    return err("Nothing to delete")

  # Calculate how many characters we can actually delete
  let charsAvailable = lineContent.charLen - ctx.state.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Extract the characters to be deleted (for yank register)
  # Get the line content and extract the substring
  let runes = lineContent.toRunes()
  var deletedText = ""
  for i in 0 ..< charsToDelete:
    let runeIdx = ctx.state.cursor.column + i
    if runeIdx < runes.len:
      deletedText.add($runes[runeIdx])

  # Store in yank register before deleting
  ctx.state.yankRegister = deletedText
  ctx.state.yankIsLine = false

  # Begin transaction if deleting multiple characters
  if charsToDelete > 1:
    let txnResult = ctx.buffer.beginTransaction("delete " & $charsToDelete & " chars")
    if txnResult.isErr:
      return err(txnResult.error)

  # Delete the characters
  for i in 0 ..< charsToDelete:
    # deleteRange is inclusive, so endPos should be at the same column as cursor
    # to delete only one character
    let endPos = ctx.state.cursor
    let delResult = ctx.buffer.deleteRange(ctx.state.cursor, endPos)
    if delResult.isErr:
      if charsToDelete > 1:
        discard ctx.buffer.commitTransaction()
      return err(delResult.error)

  # Commit transaction if we started one
  if charsToDelete > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  # Also write to system clipboard if enabled
  if ctx.clipboardConfig.enable:
    discard writeToClipboard(ctx.clipboardConfig.tool, deletedText)

  ctx.state.needsFullRedraw = true
  return Result[(), string].ok ()

proc handleDeleteCharBefore(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete character(s) before cursor position (X command)
  ## count: number of characters to delete (default: 1)

  logDebug("delete", "handleDeleteCharBefore called with count=" & $count)
  let actualCount = max(1, count)

  # Check if we're at the beginning of the line
  if ctx.state.cursor.column == 0:
    return err("Nothing to delete")

  # Calculate how many characters we can actually delete
  let charsAvailable = ctx.state.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Calculate the start position for deletion
  let startColumn = ctx.state.cursor.column - charsToDelete

  # Extract the characters to be deleted (for yank register)
  # Get the line content and extract the substring
  let lineContent = ctx.buffer.getLine(ctx.state.cursor.line)
  let runes = lineContent.toRunes()
  var deletedText = ""
  for i in 0 ..< charsToDelete:
    let runeIdx = startColumn + i
    if runeIdx < runes.len:
      deletedText.add($runes[runeIdx])

  # Store in yank register before deleting
  ctx.state.yankRegister = deletedText
  ctx.state.yankIsLine = false

  # Begin transaction if deleting multiple characters
  if charsToDelete > 1:
    let txnResult = ctx.buffer.beginTransaction("delete " & $charsToDelete & " chars")
    if txnResult.isErr:
      return err(txnResult.error)

  # Delete the characters (delete from startColumn multiple times)
  for i in 0 ..< charsToDelete:
    let startPos = BufferPosition(line: ctx.state.cursor.line, column: startColumn)
    # deleteRange is inclusive, so endPos should be the same as startPos
    # to delete only one character
    let endPos = startPos
    let delResult = ctx.buffer.deleteRange(startPos, endPos)
    if delResult.isErr:
      if charsToDelete > 1:
        discard ctx.buffer.commitTransaction()
      return err(delResult.error)

  # Commit transaction if we started one
  if charsToDelete > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  # Move cursor to the position where deletion started
  ctx.state.cursor.column = startColumn

  # Also write to system clipboard if enabled
  if ctx.clipboardConfig.enable:
    discard writeToClipboard(ctx.clipboardConfig.tool, deletedText)

  ctx.state.needsFullRedraw = true
  return Result[(), string].ok ()

proc handleDeleteLine(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete current line(s) and store in yank register (dd command)
  ## count: number of lines to delete (default: 1)

  logDebug("delete", "handleDeleteLine called with count=" & $count)
  let actualCount = max(1, count)
  let startLine = ctx.state.cursor.line
  let endLine = min(startLine + actualCount - 1, ctx.buffer.len - 1)

  # Build text from lines to be deleted (for yank register)
  var deletedText = ""
  for lineIdx in startLine .. endLine:
    if lineIdx < ctx.buffer.len:
      let lineContent = ctx.buffer.getLine(lineIdx)
      deletedText.add(lineContent)
      if lineIdx < endLine or (lineContent.len > 0 and lineContent[^1] != '\n'):
        deletedText.add("\n")

  # Store in yank register before deleting
  ctx.state.yankRegister = deletedText
  ctx.state.yankIsLine = true

  # Delete the lines
  for i in 1 .. actualCount:
    if startLine < ctx.buffer.len:
      let delResult = ctx.buffer.deleteLine(startLine)
      if delResult.isErr:
        return err(delResult.error)

  # Adjust cursor position if needed
  if ctx.state.cursor.line >= ctx.buffer.len:
    ctx.state.cursor.line = max(0, ctx.buffer.len - 1)
  ctx.state.cursor.column = 0

  # Also write to system clipboard if enabled
  if ctx.clipboardConfig.enable:
    discard writeToClipboard(ctx.clipboardConfig.tool, deletedText)

  ctx.state.needsFullRedraw = true
  ctx.state.statusMessage = "Deleted " & $actualCount & " line(s)"
  return Result[(), string].ok ()

proc handleClipboardCut(ctx: CommandContext): Result[(), string] =
  ## Cut selected text to system clipboard (copy + delete)
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # First, copy to clipboard
  let copyResult = handleClipboardCopy(ctx)
  if copyResult.isErr:
    return copyResult

  # Then delete the selection
  if ctx.state.visualSelection.active:
    visualDelete(ctx.buffer, ctx.state)

  return Result[(), string].ok ()

proc handleYankLine(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Yank (copy) the current line(s) to internal register and optionally to system clipboard
  ## count: number of lines to yank (default: 1)

  logDebug("yank", "handleYankLine called with count=" & $count)
  let actualCount = max(1, count) # Ensure at least 1 line
  logDebug("yank", "actualCount=" & $actualCount)
  let startLine = ctx.state.cursor.line
  let endLine = min(startLine + actualCount - 1, ctx.buffer.len - 1)

  # Build text from multiple lines
  var yankText = ""
  for lineIdx in startLine .. endLine:
    if lineIdx < ctx.buffer.len:
      let lineContent = ctx.buffer.getLine(lineIdx)
      yankText.add(lineContent)
      # Add newline if not the last line or if the line itself doesn't end with one
      if lineIdx < endLine or (lineContent.len > 0 and lineContent[^1] != '\n'):
        yankText.add("\n")

  # Debug: log the yanked text
  logDebug(
    "yank", "Yanking " & $actualCount & " line(s), total length: " & $yankText.len
  )
  logDebug("yank", "Yanked text: '" & yankText & "'")

  if yankText.len == 0:
    return err("No text to yank")

  # Store in internal yank register
  ctx.state.yankRegister = yankText
  ctx.state.yankIsLine = true

  logDebug(
    "yank",
    "Stored in register: '" & ctx.state.yankRegister & "', isLine=" &
      $ctx.state.yankIsLine,
  )

  # Also write to system clipboard if enabled
  if ctx.clipboardConfig.enable:
    let writeResult = writeToClipboard(ctx.clipboardConfig.tool, yankText)
    if writeResult.isErr:
      # Don't fail the operation if clipboard write fails
      ctx.state.statusMessage =
        "Yanked " & $actualCount & " line(s) (clipboard error: " & writeResult.error &
        ")"
      return Result[(), string].ok ()

  ctx.state.statusMessage = "Yanked " & $actualCount & " line(s)"
  return Result[(), string].ok ()

## Operator command handlers

proc handleOperatorYank(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Yank operator - waits for motion (y2w, y$, etc.) or yy for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (yy for yank line)
  if ctx.state.pendingOperator.isSome and
      ctx.state.pendingOperator.get.operatorType == OpYank:
    # Execute line yank
    let startLine = ctx.state.cursor.line
    let operatorCount = ctx.state.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)

    # Extract lines for yank register
    var text = ""
    for lineIdx in startLine .. endLine:
      if lineIdx < ctx.buffer.len:
        let lineContent = ctx.buffer.getLine(lineIdx)
        text.add(lineContent)
        if lineContent.len == 0 or lineContent[^1] != '\n':
          text.add("\n")

    ctx.state.yankRegister = text
    ctx.state.yankIsLine = true

    # Clear operator state
    ctx.state.pendingOperator = none(PendingOperator)
    let lineCount = endLine - startLine + 1
    ctx.state.statusMessage = "Yanked " & $lineCount & " line(s)"
    return ok(())
  else:
    # Set pending operator for motion
    ctx.state.pendingOperator = some(
      PendingOperator(
        operatorType: OpYank, operatorCount: count, startPos: ctx.state.cursor
      )
    )
    ctx.state.statusMessage = "y"
    return ok(())

proc handleOperatorDelete(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete operator - waits for motion (d2w, d$, etc.) or dd for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (dd for delete line)
  if ctx.state.pendingOperator.isSome and
      ctx.state.pendingOperator.get.operatorType == OpDelete:
    # Execute line deletion
    let startLine = ctx.state.cursor.line
    let operatorCount = ctx.state.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)

    # Extract lines for yank register
    var text = ""
    for lineIdx in startLine .. endLine:
      if lineIdx < ctx.buffer.len:
        let lineContent = ctx.buffer.getLine(lineIdx)
        text.add(lineContent)
        if lineContent.len == 0 or lineContent[^1] != '\n':
          text.add("\n")

    ctx.state.yankRegister = text
    ctx.state.yankIsLine = true

    # Delete lines
    for i in 0 ..< (endLine - startLine + 1):
      if startLine < ctx.buffer.len:
        let deleteResult = ctx.buffer.deleteLine(startLine)
        if deleteResult.isErr:
          return err("Failed to delete line: " & deleteResult.error)

    # Move cursor to beginning of line
    ctx.state.cursor.line = min(startLine, ctx.buffer.len - 1)
    ctx.state.cursor.column = 0

    # Clear operator state
    ctx.state.pendingOperator = none(PendingOperator)
    let lineCount = endLine - startLine + 1
    ctx.state.statusMessage = "Deleted " & $lineCount & " line(s)"
    return ok(())
  else:
    # Set pending operator for motion
    ctx.state.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete, operatorCount: count, startPos: ctx.state.cursor
      )
    )
    ctx.state.statusMessage = "d"
    return ok(())

proc handleOperatorChange(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Change operator - waits for motion (c2w, c$, etc.) or cc for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (cc for change line)
  if ctx.state.pendingOperator.isSome and
      ctx.state.pendingOperator.get.operatorType == OpChange:
    # Execute line change
    let startLine = ctx.state.cursor.line
    let operatorCount = ctx.state.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)

    # Extract lines for yank register
    var text = ""
    for lineIdx in startLine .. endLine:
      if lineIdx < ctx.buffer.len:
        let lineContent = ctx.buffer.getLine(lineIdx)
        text.add(lineContent)
        if lineContent.len == 0 or lineContent[^1] != '\n':
          text.add("\n")

    ctx.state.yankRegister = text
    ctx.state.yankIsLine = true

    # Delete all but first line
    for i in 0 ..< (endLine - startLine):
      if startLine + 1 < ctx.buffer.len:
        let deleteResult = ctx.buffer.deleteLine(startLine + 1)
        if deleteResult.isErr:
          return err("Failed to delete line: " & deleteResult.error)

    # Clear the first line
    if startLine < ctx.buffer.len:
      let line = ctx.buffer.getLine(startLine)
      for i in 0 ..< line.charLen:
        let deleteResult = ctx.buffer.deleteRange(
          BufferPosition(line: startLine, column: 0),
          BufferPosition(line: startLine, column: 1),
        )
        if deleteResult.isErr:
          return err("Failed to clear line: " & deleteResult.error)

    # Move cursor to beginning of line and enter Insert mode
    ctx.state.cursor.line = startLine
    ctx.state.cursor.column = 0
    ctx.state.mode = EditorMode.Insert

    # Begin transaction for change
    let transactionResult = ctx.buffer.beginTransaction("Change line")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    # Clear operator state
    ctx.state.pendingOperator = none(PendingOperator)
    ctx.state.statusMessage = "-- INSERT --"
    return ok(())
  else:
    # Set pending operator for motion
    ctx.state.pendingOperator = some(
      PendingOperator(
        operatorType: OpChange, operatorCount: count, startPos: ctx.state.cursor
      )
    )
    ctx.state.statusMessage = "c"
    return ok(())

## Text object command handlers

proc handleTextObjectInner(ctx: CommandContext): Result[(), string] =
  ## Handle inner text object (iw, i", i(, etc.) or enter Insert mode

  # Check if we have a pending operator
  if ctx.state.pendingOperator.isSome:
    # We have a pending operator - set text object modifier
    let operatorCount = ctx.state.pendingOperator.get.operatorCount
    ctx.state.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: operatorCount))
    ctx.state.statusMessage = $ctx.state.pendingOperator.get.operatorType & "i"
    return ok(())
  else:
    # No pending operator - enter Insert mode
    ctx.state.mode = EditorMode.Insert
    # Begin transaction for insert mode edit
    let transactionResult = ctx.buffer.beginTransaction("Insert mode edit")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)
    ctx.state.statusMessage = "-- INSERT --"
    return ok(())

proc handleTextObjectAround(ctx: CommandContext): Result[(), string] =
  ## Handle around text object (aw, a", a(, etc.) or enter Append mode

  # Check if we have a pending operator
  if ctx.state.pendingOperator.isSome:
    # We have a pending operator - set text object modifier
    let operatorCount = ctx.state.pendingOperator.get.operatorCount
    ctx.state.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: operatorCount))
    ctx.state.statusMessage = $ctx.state.pendingOperator.get.operatorType & "a"
    return ok(())
  else:
    # No pending operator - enter Append mode (move cursor right, then Insert)
    # Move cursor one position to the right if not at end of line
    if ctx.state.cursor.line < ctx.buffer.len:
      let currentLine = ctx.buffer.getLine(ctx.state.cursor.line)
      if ctx.state.cursor.column < currentLine.len:
        ctx.state.cursor.column += 1
    # Enter Insert mode
    ctx.state.mode = EditorMode.Insert
    # Begin transaction for insert mode edit
    let transactionResult = ctx.buffer.beginTransaction("Append mode edit")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)
    ctx.state.statusMessage = "-- INSERT --"
    return ok(())

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

  # Note: delete.word is now handled by operator+motion system (d+w)
  # The operator.delete handler sets pendingOperator, then Motion.WordForward
  # is executed, and executeOperatorOnRange is called automatically

  registry.register(
    custom("delete.line"),
    "Delete Line",
    "Delete current line(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("delete.char"),
    "Delete Character",
    "Delete character(s) at cursor (x command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteChar(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("delete.char.before"),
    "Delete Character Before",
    "Delete character(s) before cursor (X command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleDeleteCharBefore(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("yank.line"),
    "Yank Line",
    "Yank (copy) current line(s) to clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleYankLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("paste.after"),
    "Paste After",
    "Paste clipboard content after cursor (p command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handlePasteAfter(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("paste.before"),
    "Paste Before",
    "Paste clipboard content before cursor (P command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handlePasteBefore(ctx, count),
    0,
    1, # Accept optional count argument
  )

  # Note: change.word is now handled by operator+motion system (c+w)
  # The operator.change handler sets pendingOperator, then Motion.WordForward
  # is executed, and executeOperatorOnRange is called automatically

  # Undo/Redo commands
  registry.register(
    builtin(bcEditUndo),
    "Undo",
    "Undo the last change(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      for i in 1 .. count:
        let r = ctx.buffer.undo()
        if r.isErr:
          if i == 1:
            return err(r.error)
          else:
            break # Stop if we can't undo anymore
      # TODO: Apply cursor position from r.value to active window
      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    builtin(bcEditRedo),
    "Redo",
    "Redo the last undone change(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      for i in 1 .. count:
        let r = ctx.buffer.redo()
        if r.isErr:
          if i == 1:
            return err(r.error)
          else:
            break # Stop if we can't redo anymore
      # TODO: Apply cursor position from r.value to active window
      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  # Clipboard commands
  registry.register(
    builtin(bcEditCopy),
    "Copy",
    "Copy selected text to system clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleClipboardCopy(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcEditPaste),
    "Paste",
    "Paste text from system clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleClipboardPaste(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcEditCut),
    "Cut",
    "Cut selected text to system clipboard",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleClipboardCut(ctx),
    0,
    0,
  )

  # Operator commands (d, c, y) - these wait for motion/text object
  registry.register(
    custom("operator.delete"),
    "Delete Operator",
    "Delete operator - waits for motion (d2w, d$, etc.) or dd for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorDelete(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.change"),
    "Change Operator",
    "Change operator - waits for motion (c2w, c$, etc.) or cc for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorChange(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.yank"),
    "Yank Operator",
    "Yank operator - waits for motion (y2w, y$, etc.) or yy for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorYank(ctx, count),
    0,
    1, # Accept optional count
  )

  # D - Delete to end of line (equivalent to d$)
  registry.register(
    custom("operator.delete.to.end"),
    "Delete To End Of Line",
    "Delete from cursor to end of line (D command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Calculate range from cursor to end of line
      let startPos = ctx.state.cursor
      let line = ctx.buffer.getLine(startPos.line)
      let endPos = BufferPosition(line: startPos.line, column: line.charLen)

      let range = OperatorRange(start: startPos, endPos: endPos, isLinewise: false)

      # Execute delete operation
      return executeOperatorOnRange(ctx, OpDelete, range, 1),
    0,
    0,
  )

  # C - Change to end of line (equivalent to c$)
  registry.register(
    custom("operator.change.to.end"),
    "Change To End Of Line",
    "Change from cursor to end of line (C command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Calculate range from cursor to end of line
      let startPos = ctx.state.cursor
      let line = ctx.buffer.getLine(startPos.line)
      let endPos = BufferPosition(line: startPos.line, column: line.charLen)

      let range = OperatorRange(start: startPos, endPos: endPos, isLinewise: false)

      # Execute change operation
      return executeOperatorOnRange(ctx, OpChange, range, 1),
    0,
    0,
  )

  # Text object commands (i, a) - wait for text object kind
  registry.register(
    custom("textobject.inner"),
    "Inner Text Object",
    "Select inner text object (iw, i\", i(, etc.) or enter Insert mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleTextObjectInner(ctx),
    0,
    0,
  )

  registry.register(
    custom("textobject.around"),
    "Around Text Object",
    "Select around text object (aw, a\", a(, etc.) or enter Append mode",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleTextObjectAround(ctx),
    0,
    0,
  )

  # Text object kind commands (w, ", (, etc.)
  proc registerTextObjectKind(
      reg: CommandRegistry, id: string, name: string, desc: string, kind: TextObjectKind
  ) =
    reg.register(
      custom(id),
      name,
      desc,
      proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
        # Check if we have a pending text object modifier
        if ctx.state.pendingTextObject.isNone:
          # No text object modifier - ignore this key press
          # (In the future, we should fallback to the key's normal function)
          return ok(())

        let textObj = ctx.state.pendingTextObject.get
        ctx.state.pendingTextObject = none(PendingTextObject)

        # Calculate text object range
        let rangeResult =
          calculateTextObjectRange(ctx.buffer, ctx.state.cursor, kind, textObj.modifier)
        if rangeResult.isErr:
          return err(rangeResult.error)

        let toRange = rangeResult.value

        # Convert TextObjectRange to OperatorRange
        let opRange = OperatorRange(
          start: toRange.start, endPos: toRange.endPos, isLinewise: toRange.isLinewise
        )

        # Check if we have a pending operator
        if ctx.state.pendingOperator.isSome:
          let op = ctx.state.pendingOperator.get
          ctx.state.pendingOperator = none(PendingOperator)

          # Execute operator on text object
          return executeOperatorOnRange(ctx, op.operatorType, opRange, op.operatorCount)
        else:
          # No operator - just select the text object in visual mode (future feature)
          return err("Text objects without operators not yet implemented"),
      0,
      0,
    )

  # Register text object kinds
  registerTextObjectKind(
    registry, "textobject.word", "Word Text Object", "Word text object (iw/aw)", toWord
  )
  registerTextObjectKind(
    registry, "textobject.quote.double", "Double Quote Text Object",
    "Double-quoted string (i\"/a\")", toQuotedDouble,
  )
  registerTextObjectKind(
    registry, "textobject.quote.single", "Single Quote Text Object",
    "Single-quoted string (i'/a')", toQuotedSingle,
  )
  registerTextObjectKind(
    registry, "textobject.quote.backtick", "Backtick Text Object",
    "Backtick string (i`/a`)", toQuotedBacktick,
  )
  registerTextObjectKind(
    registry, "textobject.paren", "Parenthesis Text Object", "Parentheses (i(/a()",
    toParenthesis,
  )
  registerTextObjectKind(
    registry, "textobject.bracket", "Bracket Text Object", "Square brackets (i[/a[)",
    toBracket,
  )
  registerTextObjectKind(
    registry, "textobject.brace", "Brace Text Object", "Curly braces (i{/a{)", toBrace
  )

  # Helper proc for executing search and updating cursor/viewport
  # Reduces code duplication between search.next and search.prev
  proc executeSearch(
      ctx: CommandContext,
      searchText: string,
      searchProc: proc(
        b: TextBuffer, text: string, pos: BufferPosition, ignorecase: bool
      ): Option[BufferPosition],
  ): Result[(), string] =
    # Apply smartcase logic
    let shouldIgnoreCase =
      shouldIgnoreCase(searchText, ctx.state.ignorecase, ctx.state.smartcase)

    # Execute the search (findNext or findPrev)
    let searchResult =
      searchProc(ctx.buffer, searchText, ctx.state.cursor, shouldIgnoreCase)

    if searchResult.isSome:
      let newPos = searchResult.get
      ctx.state.cursor = newPos

      # Update viewport to follow cursor
      let lineCount = ctx.buffer.len
      let cursorPos = CursorPosition(x: newPos.column, y: newPos.line)

      ctx.motionController.viewportManager.updateViewport(
        cursorPos,
        lineCount,
        ctx.state.showStatusLine,
        ctx.state.viewportReservedLines,
        false, # Force immediate scroll for search
        ctx.buffer,
        0, # lineNumOffset
      )

      ctx.state.statusMessage = "Found: " & searchText
      ctx.state.needsFullRedraw = true
      return Result[(), string].ok ()
    else:
      ctx.state.statusMessage = "Pattern not found: " & searchText
      return err("Pattern not found")

  # Search navigation commands
  registry.register(
    custom("search.next"),
    "Search Next",
    "Find next occurrence of last search",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      if ctx.state.lastSearchText.len == 0:
        return err("No previous search")

      # Re-enable highlight when using n/N
      ctx.state.hlsearchTempDisabled = false

      return executeSearch(ctx, ctx.state.lastSearchText, findNext),
    0,
    0,
  )

  registry.register(
    custom("search.prev"),
    "Search Previous",
    "Find previous occurrence of last search",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      if ctx.state.lastSearchText.len == 0:
        return err("No previous search")

      # Re-enable highlight when using n/N
      ctx.state.hlsearchTempDisabled = false

      return executeSearch(ctx, ctx.state.lastSearchText, findPrev),
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
  registry.registerAlias("u", bcEditUndo)
  registry.registerAlias("C-r", bcEditRedo)
