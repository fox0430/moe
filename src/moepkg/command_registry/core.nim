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

## Command registry core: types, primitive registry operations, common helpers.

import std/[tables, options, strutils, unicode]

import pkg/results

import ../[types, buffer, motion, key_bindings, modes, clipboard, config, logger]

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
    bcMotionFirstNonBlank = "motion.firstnonblank"
    bcMotionEnd = "motion.end"
    bcMotionFirstLine = "motion.firstline"
    bcMotionLastLine = "motion.lastline"
    bcMotionWord = "motion.word"
    bcMotionWordBack = "motion.word.back"
    bcMotionWordEnd = "motion.word.end"
    bcMotionViewportHigh = "motion.viewport.high"
    bcMotionViewportMiddle = "motion.viewport.middle"
    bcMotionViewportLow = "motion.viewport.low"
    bcMotionMatchBracket = "motion.match.bracket" # % - jump to matching bracket
    # Scroll commands
    bcScrollCursorTop = "scroll.cursor.top"
    bcScrollCursorCenter = "scroll.cursor.center"
    bcScrollCursorBottom = "scroll.cursor.bottom"
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
    bcEditIncrementNumber = "edit.increment"
    bcEditDecrementNumber = "edit.decrement"
    # Jump list operations
    bcJumpBack = "jump.back" # Ctrl-o
    bcJumpForward = "jump.forward" # Ctrl-i
    # Change list operations
    bcChangeListPrev = "changelist.prev" # g;
    bcChangeListNext = "changelist.next" # g,
    # Bookmark operations
    bcBookmarkToggle = "bookmark.toggle"
    bcBookmarkNext = "bookmark.next"
    bcBookmarkPrev = "bookmark.prev"
    bcBookmarkClear = "bookmark.clear"
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
    bcVisualYank = "visual.yank"
    bcVisualIndent = "visual.indent"
    bcVisualDedent = "visual.dedent"
    bcVisualLowercase = "visual.lowercase"
    bcVisualUppercase = "visual.uppercase"
    bcVisualToggleCase = "visual.togglecase"
    bcVisualJoinLines = "visual.joinlines"
    bcVisualMoveHome = "visual.move.home"
    bcVisualMoveEnd = "visual.move.end"
    bcVisualMoveFirstNonBlank = "visual.move.firstnonblank"
    bcVisualMoveFirstLine = "visual.move.firstline"
    bcVisualMoveLastLine = "visual.move.lastline"
    bcVisualMoveWord = "visual.move.word"
    bcVisualMoveWordBack = "visual.move.word.back"
    bcVisualMoveWordEnd = "visual.move.word.end"
    bcVisualMoveWordEndBackward = "visual.move.word.end.backward"
    bcVisualMoveParagraphForward = "visual.move.paragraph.forward"
    bcVisualMoveParagraphBackward = "visual.move.paragraph.backward"
    bcVisualToInsertMode = "visual.to.insert"
    bcVisualBlockAppend = "visual.block.append"
    bcVisualChange = "visual.change"
    bcVisualSwapSelection = "visual.swap.selection"
    bcVisualPaste = "visual.paste"
    # Filer operations
    bcFiler = "filer.open"
    # LSP operations
    bcLspGotoDefinition = "lsp.goto.definition"
    bcLspFindReferences = "lsp.find.references"
    bcLspCodeLensExecute = "lsp.codelens.execute"
    bcLspCallHierarchyIncoming = "lsp.callhierarchy.incoming"
    bcLspCallHierarchyOutgoing = "lsp.callhierarchy.outgoing"
    # Fold operations
    bcFoldOpen = "fold.open" # zo - open fold at cursor
    bcFoldClose = "fold.close" # zc - close fold at cursor
    bcFoldToggle = "fold.toggle" # za - toggle fold at cursor
    bcFoldOpenAll = "fold.open.all" # zR - open all folds
    bcFoldCloseAll = "fold.close.all" # zM - close all folds
    bcFoldCreate = "fold.create" # zf - create fold from selection
    bcFoldDelete = "fold.delete" # zd - delete fold at cursor
    bcFoldDeleteAll = "fold.delete.all" # zD - delete all folds
    # QuickRun
    bcQuickRun = "quickrun" # \r - run current buffer

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
    keyBindingRegistry*: key_bindings.KeyBindingRegistry
    clipboardConfig*: ClipboardConfig
    smoothScrollConfig*: SmoothScrollConfig
    notificationConfig*: NotificationConfig

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

proc cursor*(ctx: CommandContext): var BufferPosition {.inline.} =
  ## Cursor position forwarded to EditorState (which delegates to activeWindow)
  ctx.state.cursor

proc `cursor=`*(ctx: CommandContext, pos: BufferPosition) {.inline.} =
  ctx.state.cursor = pos

proc notify*(ctx: CommandContext, msg: string, level: NotificationLevel = nlInfo) =
  ## Send a notification via popup or status line based on config.
  if ctx.notificationConfig.popupNotifications:
    ctx.state.notificationPopup.addNotification(msg, level)
  else:
    ctx.state.statusMessage = msg

# Helper functions for CommandId
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

proc findAllCharPositions*(
    buffer: TextBuffer, line: int, targetChar: string
): seq[int] =
  ## Find all column positions of targetChar on the given line.
  ## Used for f/F/t/T match highlighting.
  if line >= 0 and line < buffer.len:
    let lineContent = buffer.getLine(line)
    var charIdx = 0
    for rune in lineContent.runes:
      if $rune == targetChar:
        result.add(charIdx)
      charIdx.inc

# Helper function to parse count from arguments safely
proc parseCount*(
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

# Helper function to parse boolean argument
proc parseBoolArg*(
    args: seq[string], index: int = 0, default: bool = false
): bool {.used.} =
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

## Jump list management functions
proc recordJump*(state: EditorState) =
  ## Record current cursor position as a jump point
  ## This should be called before jumping to a different location
  let currentPos = JumpPosition(
    bufferId: state.windowDisplay.currentBufferId,
    line: state.cursor.line,
    column: state.cursor.column,
  )

  # Don't record if the position is the same as the last jump in the list
  if state.jumpList.len > 0:
    let lastPos = state.jumpList[^1]
    if lastPos.bufferId == currentPos.bufferId and lastPos.line == currentPos.line and
        lastPos.column == currentPos.column:
      # Same position as last jump - don't record duplicate
      return

  # If we're navigating the jump list, truncate everything after current position
  if state.jumpListIndex >= 0 and state.jumpListIndex < state.jumpList.len - 1:
    state.jumpList.setLen(state.jumpListIndex + 1)

  # Add new position to the end
  state.jumpList.add(currentPos)

  # Keep jump list to a reasonable size (100 entries like Vim)
  const MaxJumpListSize = 100
  while state.jumpList.len > MaxJumpListSize:
    state.jumpList.delete(0)

  # Reset index to indicate we're not navigating the list
  state.jumpListIndex = -1

## Helper for clipboard operations
proc getSelectedText*(state: EditorState, buffer: TextBuffer): string =
  ## Get the currently selected text in visual mode
  ## Returns empty string if no active selection
  if not state.visualSelection.active:
    return ""

  # Normalize selection range (ensure start <= end)
  let (selStart, selEnd) =
    if state.visualSelection.start.line < state.visualSelection.current.line:
      (state.visualSelection.start, state.visualSelection.current)
    elif state.visualSelection.start.line > state.visualSelection.current.line:
      (state.visualSelection.current, state.visualSelection.start)
    else:
      # Same line - compare columns
      if state.visualSelection.start.column <= state.visualSelection.current.column:
        (state.visualSelection.start, state.visualSelection.current)
      else:
        (state.visualSelection.current, state.visualSelection.start)

  return buffer.getTextInRange(selStart, selEnd)
