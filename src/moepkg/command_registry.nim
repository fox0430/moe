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

## Command registry and execution system
##
## This module provides a centralized command registry that decouples
## command definitions from key bindings, allowing flexible configuration.

import std/[tables, options, strutils, unicode]

import pkg/results

import
  types, buffer, motion, key_bindings, modes, search_utils, clipboard, config, logger,
  unicode_utils, registers, render_utils, git_conflict

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

# Forward declarations for register dispatch helpers
proc storeYankedText(ctx: CommandContext, text: string, isLine: bool)
proc storeDeletedText(ctx: CommandContext, text: string, isLine: bool)

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

    # Store in register system (respects pendingRegister)
    storeYankedText(ctx, text, range.isLinewise)

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

    # Store in register system (respects pendingRegister)
    storeDeletedText(ctx, text, range.isLinewise)

    # Delete the text
    let delResult = deleteRange(ctx.buffer, range)
    if delResult.isErr:
      return err(delResult.error)

    # Move cursor to start of deletion
    ctx.cursor = range.start
    # Clamp cursor to valid position
    if ctx.cursor.line >= ctx.buffer.len:
      ctx.cursor.line = max(0, ctx.buffer.len - 1)
    if ctx.cursor.line < ctx.buffer.len:
      let line = ctx.buffer.getLine(ctx.cursor.line)
      ctx.cursor.column = min(ctx.cursor.column, max(0, line.charLen - 1))

    # Restore viewport position to where it was before the operator started
    # Use savedViewportTopLine which was saved when operator (d/c/y) was pressed
    let newBufferLen = ctx.buffer.len
    let restoredTopLine = ctx.state.windowDisplay.savedViewportTopLine
    let cursorLine = ctx.cursor.line

    # Restore viewport, but ensure cursor remains visible
    # Cases:
    # 1. restoredTopLine >= newBufferLen: clamp to valid range
    # 2. cursor < restoredTopLine: use cursor position (e.g., dgg moves cursor up)
    # 3. otherwise: restore saved position
    if restoredTopLine >= newBufferLen:
      # Saved position is beyond new buffer size
      ctx.motionController.viewportManager.viewport.topLine =
        max(0, min(cursorLine, newBufferLen - 1))
    elif cursorLine < restoredTopLine:
      # Cursor is above saved viewport (e.g., dgg), use cursor position
      ctx.motionController.viewportManager.viewport.topLine = cursorLine
    else:
      # Restore to saved position
      ctx.motionController.viewportManager.viewport.topLine = restoredTopLine

    ctx.state.windowDisplay.needsFullRedraw = true
    return ok(())
  of OpChange:
    # Change the range (delete and enter insert mode)
    let text = extractRangeText(ctx.buffer, range)

    # Store in register system (respects pendingRegister)
    storeDeletedText(ctx, text, range.isLinewise)

    # Begin transaction for all change operations (delete + insert mode input)
    let transactionResult = ctx.buffer.beginTransaction("Change operation")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    # Delete the text
    let delResult = deleteRange(ctx.buffer, range)
    if delResult.isErr:
      discard ctx.buffer.commitTransaction()
      return err(delResult.error)

    # Move cursor to start of change
    ctx.cursor = range.start
    # Clamp cursor to valid position
    if ctx.cursor.line >= ctx.buffer.len:
      ctx.cursor.line = max(0, ctx.buffer.len - 1)
    if ctx.cursor.line < ctx.buffer.len:
      let line = ctx.buffer.getLine(ctx.cursor.line)
      # Insert mode allows cursor at charLen (append position)
      ctx.cursor.column = min(ctx.cursor.column, line.charLen)

    # Restore viewport position (same logic as OpDelete)
    let newBufferLen = ctx.buffer.len
    let restoredTopLine = ctx.state.windowDisplay.savedViewportTopLine
    let cursorLine = ctx.cursor.line

    # Restore viewport, but ensure cursor remains visible
    if restoredTopLine >= newBufferLen:
      # Saved position is beyond new buffer size
      ctx.motionController.viewportManager.viewport.topLine =
        max(0, min(cursorLine, newBufferLen - 1))
    elif cursorLine < restoredTopLine:
      # Cursor is above saved viewport (e.g., cgg), use cursor position
      ctx.motionController.viewportManager.viewport.topLine = cursorLine
    else:
      # Restore to saved position
      ctx.motionController.viewportManager.viewport.topLine = restoredTopLine

    # Enter insert mode (transaction remains open for insert mode input)
    ctx.state.mode = EditorMode.Insert
    ctx.state.windowDisplay.needsFullRedraw = true

    return ok(())
  of OpIndent:
    # Indent lines in the range
    # For character-wise ranges (e.g., i{), adjust start/end lines:
    # If start column is at/past end of line, content starts on the next line.
    # If end column is negative or end line has closing delimiter only, exclude it.
    var startLine = range.start.line
    var endLine = range.endPos.line
    if not range.isLinewise and startLine != endLine:
      if startLine < ctx.buffer.len:
        let startLineContent = ctx.buffer.getLine(startLine)
        if range.start.column >= startLineContent.charLen:
          startLine += 1
      if endLine < ctx.buffer.len and range.endPos.column < 0:
        endLine -= 1

    let transactionResult = ctx.buffer.beginTransaction("Indent lines")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    let indentStr = getIndentString(ctx.state)
    for lineNum in startLine .. endLine:
      if lineNum < ctx.buffer.len:
        let insertPos = BufferPosition(line: lineNum, column: 0)
        discard ctx.buffer.insertText(insertPos, indentStr)

    discard ctx.buffer.commitTransaction()

    # Move cursor to first non-blank of start line
    ctx.cursor.line = startLine
    ctx.cursor.column = 0
    if startLine < ctx.buffer.len:
      let line = ctx.buffer.getLine(startLine)
      for r in line.runes:
        if $r == " " or $r == "\t":
          ctx.cursor.column += 1
        else:
          break

    ctx.state.windowDisplay.needsFullRedraw = true
    return ok(())
  of OpOutdent:
    # Dedent lines in the range (same line adjustment as indent)
    var startLine = range.start.line
    var endLine = range.endPos.line
    if not range.isLinewise and startLine != endLine:
      if startLine < ctx.buffer.len:
        let startLineContent = ctx.buffer.getLine(startLine)
        if range.start.column >= startLineContent.charLen:
          startLine += 1
      if endLine < ctx.buffer.len and range.endPos.column < 0:
        endLine -= 1

    let transactionResult = ctx.buffer.beginTransaction("Dedent lines")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    let indentWidth = effectiveShiftWidth(ctx.state)
    for lineNum in startLine .. endLine:
      if lineNum < ctx.buffer.len:
        let lineContent = ctx.buffer.getLine(lineNum)
        let currentIndent = getLineIndent(lineContent)
        let removeCount = min(indentWidth, currentIndent.len)
        if removeCount > 0:
          for i in 1 .. removeCount:
            let deletePos = BufferPosition(line: lineNum, column: 0)
            discard ctx.buffer.deleteChar(deletePos)

    discard ctx.buffer.commitTransaction()

    # Move cursor to first non-blank of start line
    ctx.cursor.line = startLine
    ctx.cursor.column = 0
    if startLine < ctx.buffer.len:
      let outdentLine = ctx.buffer.getLine(startLine)
      for r in outdentLine.runes:
        if $r == " " or $r == "\t":
          ctx.cursor.column += 1
        else:
          break

    ctx.state.windowDisplay.needsFullRedraw = true
    return ok(())
  of OpLowerCase:
    # Convert text in range to lowercase
    let transactionResult = ctx.buffer.beginTransaction("Lowercase")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    if range.isLinewise:
      for lineNum in range.start.line .. range.endPos.line:
        if lineNum < ctx.buffer.len:
          let lineText = $ctx.buffer.getLine(lineNum)
          let lineCharLen = lineText.charLen
          if lineCharLen > 0:
            let lowerText = lineText.toLowerAscii()
            let startPos = BufferPosition(line: lineNum, column: 0)
            let endPos = BufferPosition(line: lineNum, column: lineCharLen - 1)
            discard ctx.buffer.deleteRange(startPos, endPos)
            discard ctx.buffer.insertText(startPos, lowerText)
    else:
      let text = extractRangeText(ctx.buffer, range)
      let lowerText = text.toLowerAscii()
      discard ctx.buffer.deleteRange(range.start, range.endPos)
      discard ctx.buffer.insertText(range.start, lowerText)

    discard ctx.buffer.commitTransaction()

    ctx.cursor = range.start
    ctx.state.windowDisplay.needsFullRedraw = true
    return ok(())
  of OpUpperCase:
    # Convert text in range to uppercase
    let transactionResult = ctx.buffer.beginTransaction("Uppercase")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    if range.isLinewise:
      for lineNum in range.start.line .. range.endPos.line:
        if lineNum < ctx.buffer.len:
          let lineText = $ctx.buffer.getLine(lineNum)
          let lineCharLen = lineText.charLen
          if lineCharLen > 0:
            let upperText = lineText.toUpperAscii()
            let startPos = BufferPosition(line: lineNum, column: 0)
            let endPos = BufferPosition(line: lineNum, column: lineCharLen - 1)
            discard ctx.buffer.deleteRange(startPos, endPos)
            discard ctx.buffer.insertText(startPos, upperText)
    else:
      let text = extractRangeText(ctx.buffer, range)
      let upperText = text.toUpperAscii()
      discard ctx.buffer.deleteRange(range.start, range.endPos)
      discard ctx.buffer.insertText(range.start, upperText)

    discard ctx.buffer.commitTransaction()

    ctx.cursor = range.start
    ctx.state.windowDisplay.needsFullRedraw = true
    return ok(())
  of OpSwapCase:
    return err("Operator " & $operatorType & " not yet implemented")

# Forward declaration for recordJump (defined below)
proc recordJump*(state: EditorState)

proc findAllCharPositions(buffer: TextBuffer, line: int, targetChar: string): seq[int] =
  ## Find all column positions of targetChar on the given line.
  ## Used for f/F/t/T match highlighting.
  if line >= 0 and line < buffer.len:
    let lineContent = buffer.getLine(line)
    var charIdx = 0
    for rune in lineContent.runes:
      if $rune == targetChar:
        result.add(charIdx)
      charIdx.inc

proc executeCommand*(
    registry: CommandRegistry, ctx: CommandContext, cmd: key_bindings.Command
): Result[(), string] =
  ## Execute a keybinding command

  # Clear f/F/t/T match highlight when executing a non-find/till command
  if cmd.kind != ctOperatorPending or cmd.operatorType notin ["find", "till"]:
    ctx.state.ui.findCharMatches = @[]
    ctx.state.ui.findCharMatchLine = 0

  case cmd.kind
  of ctMotion:
    # Check if we have a pending operator
    if ctx.state.editState.pendingOperator.isSome:
      let op = ctx.state.editState.pendingOperator.get

      # Multiply motion count by operator count for correct Vim behavior
      # e.g., 3dw = d3w (delete 3 words), 2d3w = 6 words
      let effectiveCount = cmd.count * op.operatorCount
      let motionCmd = MotionCommand(motion: cmd.motion, count: effectiveCount)

      # Execute motion to get end position
      # Suppress viewport updates to prevent visual scrolling during operator+motion
      let r = ctx.motionController.executeMotion(
        motionCmd, op.startPos, updateViewport = false
      )
      if r.isErr:
        ctx.state.editState.pendingOperator = none(PendingOperator)
        return err(r.error)

      # Calculate the range affected by this operator+motion
      let range = calculateOperatorRange(ctx.buffer, op.startPos, r.value, cmd.motion)

      block:
        # Execute the operator on the range
        let r = executeOperatorOnRange(ctx, op.operatorType, range, op.operatorCount)
        ctx.state.editState.pendingOperator = none(PendingOperator)
        if r.isErr:
          return err(r.error)

        # Record this command for repeat (.) - only if successful and not a yank
        # Yank is not a change operation, so it should not be repeatable
        if op.operatorType != OpYank:
          ctx.state.editState.lastEditCommand = some(
            LastEditCommand(
              kind: lecOperatorMotion,
              operator: op.operatorType,
              motion: cmd.motion,
              motionCount: cmd.count,
              operatorCount: op.operatorCount,
            )
          )

      return ok(())
    else:
      # No pending operator - just move cursor
      let motionCmd = MotionCommand(motion: cmd.motion, count: cmd.count)
      logDebug(
        "command",
        "Executing motion, current cursor=(" & $ctx.cursor.line & "," &
          $ctx.cursor.column & ")",
      )

      # Record jump before big movements (like gg, G, Ctrl-d, Ctrl-u, etc.)
      let shouldRecordJump =
        cmd.motion in {
          Motion.FirstLine, Motion.LastLine, Motion.PageUp, Motion.PageDown,
          Motion.HalfPageUp, Motion.HalfPageDown, Motion.ViewportHigh,
          Motion.ViewportMiddle, Motion.ViewportLow,
        }
      if shouldRecordJump:
        recordJump(ctx.state)

      # Check if this is a scroll motion for smooth scrolling
      let isScrollMotion =
        cmd.motion in
        {Motion.PageUp, Motion.PageDown, Motion.HalfPageUp, Motion.HalfPageDown}
      let prevTopLine = ctx.motionController.viewportManager.viewport.topLine
      let prevCursorLine = ctx.cursor.line

      # For smooth scroll motions, don't update viewport in executeMotion
      # The animation will handle viewport updates
      let skipViewportUpdate = isScrollMotion and ctx.smoothScrollConfig.enable
      let r = ctx.motionController.executeMotion(
        motionCmd, ctx.cursor, updateViewport = not skipViewportUpdate
      )
      if r.isErr:
        return err(r.error)
      logDebug(
        "command",
        "Motion returned cursor=(" & $r.value.line & "," & $r.value.column & ")",
      )

      let targetCursorLine = r.value.line

      # Start smooth scroll animation if this was a scroll motion
      if isScrollMotion and ctx.smoothScrollConfig.enable:
        # For page scroll motions, we want to scroll the full page amount, not just minimum to show cursor
        let viewportHeight = ctx.motionController.viewportManager.viewport.height
        let lineCount = ctx.motionController.executor.buffer.len
        let reservedLines =
          if ctx.state.display.showStatusLine:
            StatusAndCommandReserve
          else:
            CommandLineReserve
        let pageSize = max(1, viewportHeight - reservedLines - 1)
        let halfPageSize = max(1, pageSize div 2)

        # Calculate target topLine based on motion type
        var targetTopLine = prevTopLine
        case cmd.motion
        of Motion.PageDown:
          targetTopLine = min(
            max(0, lineCount - viewportHeight + reservedLines), prevTopLine + pageSize
          )
        of Motion.PageUp:
          targetTopLine = max(0, prevTopLine - pageSize)
        of Motion.HalfPageDown:
          targetTopLine = min(
            max(0, lineCount - viewportHeight + reservedLines),
            prevTopLine + halfPageSize,
          )
        of Motion.HalfPageUp:
          targetTopLine = max(0, prevTopLine - halfPageSize)
        else:
          discard

        if targetCursorLine != prevCursorLine:
          # Restore original cursor position - animation will interpolate from here
          ctx.cursor.line = prevCursorLine
          startScrollAnimation(
            ctx.state.windowDisplay.scrollAnimation, prevCursorLine, targetCursorLine,
            ctx.smoothScrollConfig,
          )
        else:
          # No scroll needed, just update cursor
          ctx.cursor = r.value
      elif isScrollMotion:
        # Smooth scroll disabled, just update cursor
        ctx.cursor = r.value
      else:
        ctx.cursor = r.value

      logDebug(
        "command",
        "Cursor after assignment=(" & $ctx.cursor.line & "," & $ctx.cursor.column & ")",
      )
      return Result[(), string].ok ()
  of ctModeSwitch:
    # Handle mode switching
    ctx.state.mode = cmd.targetMode
    # Clear any pending key sequences when switching modes
    if ctx.keyBindingRegistry != nil:
      ctx.keyBindingRegistry.clearSequence
    return ok(())
  of ctOverlaySwitch:
    # Handle overlay mode switching
    case cmd.targetOverlay
    of okCommand:
      ctx.state.enterCommandOverlay()
    of okSearch:
      # Search direction is determined by command name
      let direction = if cmd.name == "switch-to-search-backward": Backward else: Forward
      ctx.state.enterSearchOverlay(direction)
    of okRename:
      # Rename is typically entered via LSP, not keybinding
      discard
    ctx.state.statusMessage = "" # Clear any status message
    # Clear any pending key sequences when switching overlays
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

      # Check if we have a pending operator (e.g., df{char})
      if ctx.state.editState.pendingOperator.isSome:
        let op = ctx.state.editState.pendingOperator.get

        # Execute motion to get end position
        # Suppress viewport updates to prevent visual scrolling during operator+motion
        let r = ctx.motionController.executeMotion(
          motionCmd, op.startPos, updateViewport = false
        )
        if r.isErr:
          ctx.state.editState.pendingOperator = none(PendingOperator)
          return err(r.error)

        # Check if motion actually moved the cursor
        # If not (e.g., character not found), don't execute the operator
        if r.value.line == op.startPos.line and r.value.column == op.startPos.column:
          # Motion didn't move - clear operator and do nothing
          ctx.state.editState.pendingOperator = none(PendingOperator)
          return ok(())

        # Calculate the range affected by this operator+motion
        let motion = if cmd.reverse: Motion.FindCharBackward else: Motion.FindChar
        let range = calculateOperatorRange(ctx.buffer, op.startPos, r.value, motion)

        # Execute the operator on the range
        let opResult =
          executeOperatorOnRange(ctx, op.operatorType, range, op.operatorCount)
        ctx.state.editState.pendingOperator = none(PendingOperator)
        if opResult.isErr:
          return err(opResult.error)

        # Record this command for repeat (.) - only if successful and not a yank
        if op.operatorType != OpYank:
          ctx.state.editState.lastEditCommand = some(
            LastEditCommand(
              kind: lecOperatorMotion,
              operator: op.operatorType,
              motion: motion,
              motionCount: count,
              operatorCount: op.operatorCount,
            )
          )

        return ok(())
      else:
        # No pending operator - just move cursor
        let r = ctx.motionController.executeMotion(motionCmd, ctx.cursor)
        if r.isErr:
          return err(r.error)
        ctx.cursor = r.value

        # Highlight all matching characters on cursor line
        ctx.state.ui.findCharMatchLine = ctx.cursor.line
        ctx.state.ui.findCharMatches =
          findAllCharPositions(ctx.buffer, ctx.cursor.line, cmd.targetChar)

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

      # Check if we have a pending operator (e.g., dt{char})
      if ctx.state.editState.pendingOperator.isSome:
        let op = ctx.state.editState.pendingOperator.get

        # Execute motion to get end position
        # Suppress viewport updates to prevent visual scrolling during operator+motion
        let r = ctx.motionController.executeMotion(
          motionCmd, op.startPos, updateViewport = false
        )
        if r.isErr:
          ctx.state.editState.pendingOperator = none(PendingOperator)
          return err(r.error)

        # For till motion, the result may be the same as start position when the
        # target character is adjacent (e.g., cursor at pos 0, target at pos 1).
        # In this case, tillChar returns pos 0 (before pos 1), but we still need
        # to execute the operator. We check with findChar to see if the character
        # was actually found.
        var endPos = r.value
        if r.value.line == op.startPos.line and r.value.column == op.startPos.column:
          # tillChar returned start position - check if character was actually found
          let findMotionCmd =
            if cmd.reverse:
              MotionCommand(
                motion: Motion.FindCharBackward,
                targetChar: cmd.targetChar,
                count: count,
              )
            else:
              MotionCommand(
                motion: Motion.FindChar, targetChar: cmd.targetChar, count: count
              )
          let findResult = ctx.motionController.executeMotion(
            findMotionCmd, op.startPos, updateViewport = false
          )
          if findResult.isErr or (
            findResult.value.line == op.startPos.line and
            findResult.value.column == op.startPos.column
          ):
            # Character truly not found - clear operator and do nothing
            ctx.state.editState.pendingOperator = none(PendingOperator)
            return ok(())
          # Character was found at adjacent position - use findChar result as endPos
          # but adjust for till semantics (stop before the target character)
          endPos = findResult.value
          if not cmd.reverse and endPos.column > op.startPos.column:
            endPos.column -= 1
          elif cmd.reverse and endPos.column < op.startPos.column:
            endPos.column += 1

        # Calculate the range affected by this operator+motion
        let motion = if cmd.reverse: Motion.TillCharBackward else: Motion.TillChar
        let range = calculateOperatorRange(ctx.buffer, op.startPos, endPos, motion)

        # Execute the operator on the range
        let opResult =
          executeOperatorOnRange(ctx, op.operatorType, range, op.operatorCount)
        ctx.state.editState.pendingOperator = none(PendingOperator)
        if opResult.isErr:
          return err(opResult.error)

        # Record this command for repeat (.) - only if successful and not a yank
        if op.operatorType != OpYank:
          ctx.state.editState.lastEditCommand = some(
            LastEditCommand(
              kind: lecOperatorMotion,
              operator: op.operatorType,
              motion: motion,
              motionCount: count,
              operatorCount: op.operatorCount,
            )
          )

        return ok(())
      else:
        # No pending operator - just move cursor
        let r = ctx.motionController.executeMotion(motionCmd, ctx.cursor)
        if r.isErr:
          return err(r.error)
        ctx.cursor = r.value

        # Highlight all matching characters on cursor line
        ctx.state.ui.findCharMatchLine = ctx.cursor.line
        ctx.state.ui.findCharMatches =
          findAllCharPositions(ctx.buffer, ctx.cursor.line, cmd.targetChar)

        return Result[(), string].ok ()
    of "replace":
      # Execute replace character action (r command)
      # Replace count characters with the target character
      if cmd.targetChar.len == 0:
        return err("No character specified for replace")

      let actualCount = max(1, count)
      let lineContent = ctx.buffer.getLine(ctx.cursor.line)

      # Check if we're at or past the end of the line
      if ctx.cursor.column >= lineContent.charLen:
        return err("Nothing to replace")

      # Calculate how many characters we can actually replace
      let charsAvailable = lineContent.charLen - ctx.cursor.column
      let charsToReplace = min(actualCount, charsAvailable)

      # Begin transaction for all replace operations
      let txnResult =
        ctx.buffer.beginTransaction("replace " & $charsToReplace & " char(s)")
      if txnResult.isErr:
        return err(txnResult.error)

      # Replace each character
      for i in 0 ..< charsToReplace:
        let pos = BufferPosition(line: ctx.cursor.line, column: ctx.cursor.column + i)

        # Delete original character
        let delResult = ctx.buffer.deleteRange(pos, pos)
        if delResult.isErr:
          discard ctx.buffer.rollbackTransaction()
          return err(delResult.error)

        # Insert replacement character
        let insResult = ctx.buffer.insertText(pos, cmd.targetChar)
        if insResult.isErr:
          discard ctx.buffer.rollbackTransaction()
          return err(insResult.error)

      # Commit transaction
      let commitResult = ctx.buffer.commitTransaction()
      if commitResult.isErr:
        return err(commitResult.error)

      # Record this command for repeat (.)
      ctx.state.editState.lastEditCommand = some(
        LastEditCommand(
          kind: lecReplaceChar,
          replaceChar: cmd.targetChar,
          replaceCount: charsToReplace,
        )
      )

      # Move cursor to the last replaced character (Vim behavior)
      ctx.cursor.column += charsToReplace - 1

      # Clear the numeric prefix
      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.sequenceState.numericPrefix = ""
        ctx.keyBindingRegistry.sequenceState.hasNumericPrefix = false

      ctx.state.windowDisplay.needsFullRedraw = true
      return ok(())
    of "visual-replace":
      # Execute visual replace action (r command in visual mode)
      if cmd.targetChar.len == 0:
        return err("No character specified for replace")

      # Check if we're in visual mode with active selection
      if not ctx.state.visualSelection.active:
        return err("No visual selection active")

      # Call visualReplace with the target character
      visualReplace(ctx.buffer, ctx.state, cmd.targetChar[0])

      # Clear the numeric prefix after using it
      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.sequenceState.numericPrefix = ""
        ctx.keyBindingRegistry.sequenceState.hasNumericPrefix = false

      return ok(())
    of "visual-surround":
      # Execute visual surround action (S command in visual mode)
      if cmd.targetChar.len == 0:
        return err("No character specified for surround")

      if not ctx.state.visualSelection.active:
        return err("No visual selection active")

      visualSurround(ctx.buffer, ctx.state, cmd.targetChar[0])

      if ctx.keyBindingRegistry != nil:
        ctx.keyBindingRegistry.sequenceState.numericPrefix = ""
        ctx.keyBindingRegistry.sequenceState.hasNumericPrefix = false

      return ok(())
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

# Helper function to parse count from arguments safely
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

# Helper function to parse boolean argument
proc parseBoolArg(
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

# Helper function to register motion commands
proc registerMotionCommand(
    registry: CommandRegistry,
    id: BuiltinCommandId,
    name: string,
    description: string,
    motion: Motion,
    acceptsCount: bool = true,
    shouldRecordJump: bool = false,
) =
  ## Register a motion command with common handler pattern
  ## If shouldRecordJump is true, the current position will be recorded in the jump list
  let maxArgs = if acceptsCount: 1 else: 0

  registry.register(
    builtin(id),
    name,
    description,
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Record jump for big movements
      if shouldRecordJump:
        recordJump(ctx.state)

      let count =
        if acceptsCount:
          parseCount(args)
        else:
          1
      let cmd = MotionCommand(motion: motion, count: count)
      let r = ctx.motionController.executeMotion(cmd, ctx.cursor)
      if r.isErr:
        return err(r.error)
      ctx.cursor = r.value
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
  # Begin transaction for line insertion + insert mode input (all in one undo unit)
  let txnResult = ctx.buffer.beginTransaction("Insert line below")
  if txnResult.isErr:
    return err("Failed to begin transaction: " & txnResult.error)

  insertLineBelow(ctx.buffer, ctx.state)
  Result[(), string].ok ()

proc handleInsertLineAbove(ctx: CommandContext): Result[(), string] =
  ## Handle 'O' command - insert line above and enter insert mode
  # Begin transaction for line insertion + insert mode input (all in one undo unit)
  let txnResult = ctx.buffer.beginTransaction("Insert line above")
  if txnResult.isErr:
    return err("Failed to begin transaction: " & txnResult.error)

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
  ctx.cursor = ctx.state.cursor # Sync ctx.cursor from state
  Result[(), string].ok ()

proc handleVisualMoveRight(ctx: CommandContext): Result[(), string] =
  ## Move right in visual mode and update selection
  visualMoveRight(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor # Sync ctx.cursor from state
  Result[(), string].ok ()

proc handleVisualMoveUp(ctx: CommandContext): Result[(), string] =
  ## Move up in visual mode and update selection
  visualMoveUp(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor # Sync ctx.cursor from state
  Result[(), string].ok ()

proc handleVisualMoveDown(ctx: CommandContext): Result[(), string] =
  ## Move down in visual mode and update selection
  visualMoveDown(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor # Sync ctx.cursor from state
  Result[(), string].ok ()

proc handleVisualDelete(ctx: CommandContext): Result[(), string] =
  ## Delete visual selection
  visualDelete(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualYank(ctx: CommandContext): Result[(), string] =
  ## Yank (copy) visual selection
  visualYank(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualIndent(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Indent visual selection
  visualIndent(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualDedent(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Dedent visual selection
  visualDedent(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualLowercase(ctx: CommandContext): Result[(), string] =
  ## Convert visual selection to lowercase
  visualLowercase(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualUppercase(ctx: CommandContext): Result[(), string] =
  ## Convert visual selection to uppercase
  visualUppercase(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualToggleCase(ctx: CommandContext): Result[(), string] =
  ## Toggle case of visual selection
  visualToggleCase(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualJoinLines(ctx: CommandContext): Result[(), string] =
  ## Join lines in visual selection
  visualJoinLines(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveHome(ctx: CommandContext): Result[(), string] =
  ## Move to beginning of line in visual mode
  visualMoveHome(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveEnd(ctx: CommandContext): Result[(), string] =
  ## Move to end of line in visual mode
  visualMoveEnd(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveFirstNonBlank(ctx: CommandContext): Result[(), string] =
  ## Move to first non-blank character in visual mode
  visualMoveFirstNonBlank(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveFirstLine(ctx: CommandContext): Result[(), string] =
  ## Move to first line in visual mode
  visualMoveFirstLine(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveLastLine(ctx: CommandContext, count: int = 0): Result[(), string] =
  ## Move to last line (or specific line number) in visual mode
  visualMoveLastLine(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveWord(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Move to next word in visual mode
  visualMoveWord(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveWordBack(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Move to previous word in visual mode
  visualMoveWordBack(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveWordEnd(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Move to end of word in visual mode
  visualMoveWordEnd(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveWordEndBackward(
    ctx: CommandContext, count: int = 1
): Result[(), string] =
  ## Move to end of previous word in visual mode
  visualMoveWordEndBackward(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveParagraphForward(
    ctx: CommandContext, count: int = 1
): Result[(), string] =
  ## Move to next paragraph in visual mode
  visualMoveParagraphForward(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualMoveParagraphBackward(
    ctx: CommandContext, count: int = 1
): Result[(), string] =
  ## Move to previous paragraph in visual mode
  visualMoveParagraphBackward(ctx.buffer, ctx.state, count)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualToInsertMode(ctx: CommandContext): Result[(), string] =
  ## Switch from visual mode to insert mode
  visualToInsertMode(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualBlockAppend(ctx: CommandContext): Result[(), string] =
  ## Append after visual block selection (A command)
  visualBlockAppend(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualChange(ctx: CommandContext): Result[(), string] =
  ## Delete selection and enter insert mode
  visualChange(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualSwapSelection(ctx: CommandContext): Result[(), string] =
  ## Swap cursor between start and end of selection
  visualSwapSelection(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

proc handleVisualPaste(ctx: CommandContext): Result[(), string] =
  ## Paste over selection
  visualPaste(ctx.buffer, ctx.state)
  ctx.cursor = ctx.state.cursor
  Result[(), string].ok ()

## Helper for register dispatch
## These helpers check pendingRegister and route content to the correct register.

proc storeYankedText(ctx: CommandContext, text: string, isLine: bool) =
  ## Store yanked text in the appropriate register, respecting pendingRegister.
  ## Also writes to the system clipboard when appropriate.
  if ctx.state.registers.isNil:
    return

  if ctx.state.pendingRegister.isSome and ctx.state.pendingRegister.get != '\0':
    let regName = ctx.state.pendingRegister.get
    if regName.isNamedRegisterName:
      discard ctx.state.registers.setNamedRegister(regName, text, isLine)
    elif regName.isClipboardRegisterName:
      ctx.state.registers.setClipboardRegister(regName, text, isLine)
    else:
      ctx.state.registers.setYankedRegister(text, isLine)
    ctx.state.pendingRegister = none(char)
  else:
    ctx.state.registers.setYankedRegister(text, isLine)

proc storeDeletedText(ctx: CommandContext, text: string, isLine: bool) =
  ## Store deleted text in the appropriate register, respecting pendingRegister.
  ## Also writes to the system clipboard when appropriate.
  if ctx.state.registers.isNil:
    return

  if ctx.state.pendingRegister.isSome and ctx.state.pendingRegister.get != '\0':
    let regName = ctx.state.pendingRegister.get
    if regName.isNamedRegisterName:
      discard ctx.state.registers.setNamedRegister(regName, text, isLine)
    elif regName.isClipboardRegisterName:
      ctx.state.registers.setClipboardRegister(regName, text, isLine)
    else:
      ctx.state.registers.setDeletedRegister(text, isLine)
    ctx.state.pendingRegister = none(char)
  else:
    ctx.state.registers.setDeletedRegister(text, isLine)

## Helper for clipboard operations

proc getSelectedText(state: EditorState, buffer: TextBuffer): string =
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

## Clipboard command handlers

proc handleClipboardCopy(ctx: CommandContext): Result[(), string] =
  ## Copy selected text to system clipboard
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # Get selected text
  let selectedText = getSelectedText(ctx.state, ctx.buffer)
  if selectedText.len == 0:
    return err("No text selected")

  # Write to clipboard (fire-and-forget)
  writeToClipboardAsync(ctx.clipboardConfig.tool, selectedText)

  return Result[(), string].ok ()

proc handleClipboardPaste(ctx: CommandContext): Result[(), string] =
  ## Paste text from system clipboard at cursor position
  if not ctx.clipboardConfig.enable:
    return err("Clipboard integration is disabled")

  # Read from clipboard
  let readResult = readFromClipboardSync(ctx.clipboardConfig.tool)
  if readResult.isErr:
    return err(readResult.error)

  let clipboardText = readResult.value
  if clipboardText.len == 0:
    return Result[(), string].ok () # Nothing to paste

  # Insert text at cursor position
  let insertResult = ctx.buffer.insertText(ctx.cursor, clipboardText)
  if insertResult.isErr:
    return err(insertResult.error)

  # Update cursor position to end of pasted text
  # Note: For simplicity, we'll keep cursor at original position for now
  # A more sophisticated implementation would move cursor to end of paste

  ctx.state.windowDisplay.needsFullRedraw = true
  return Result[(), string].ok ()

proc firstNonBlankColumn(line: seq[Rune]): int =
  ## Return the column of the first non-whitespace character.
  ## If the line is all whitespace, return the last valid column (Vim behavior).
  for i, r in line:
    if not r.isWhiteSpace:
      return i
  if line.len > 0:
    return line.len - 1
  return 0

proc handlePasteAfter(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Paste text from internal register or system clipboard after cursor (p command)
  ## Mimics Vim's 'p' behavior
  ## count: number of times to paste (default: 1)

  logDebug("paste", "handlePasteAfter called with count=" & $count)
  let actualCount = max(1, count)

  # Get content from register system
  var pasteText: string
  var isFullLine: bool

  if ctx.state.pendingRegister.isSome and ctx.state.pendingRegister.get != '\0':
    # User specified a register with "
    let regName = ctx.state.pendingRegister.get
    let reg = ctx.state.registers.getRegister(regName)
    pasteText = reg.getContent()
    isFullLine = reg.isLine
    ctx.state.pendingRegister = none(char)
    ctx.state.statusMessage = ""
    logDebug("paste", "Using register '" & $regName & "', length: " & $pasteText.len)
  else:
    # Use unnamed register (most recent yank/delete)
    let reg = ctx.state.registers.getNoNamedRegister()
    pasteText = reg.getContent()
    isFullLine = reg.isLine
    logDebug("paste", "Using unnamed register, length: " & $pasteText.len)

  logDebug(
    "paste", "Paste content length: " & $pasteText.len & ", isLine=" & $isFullLine
  )

  # If register is empty, try system clipboard (if enabled)
  if pasteText.len == 0 and ctx.clipboardConfig.enable:
    logDebug("paste", "Register empty, trying clipboard")
    let readResult = readFromClipboardSync(ctx.clipboardConfig.tool)
    if readResult.isErr:
      return err(
        "Nothing to paste (register empty and clipboard error: " & readResult.error & ")"
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
      let currentLine = ctx.buffer.getLine(ctx.cursor.line)
      let pastePos = BufferPosition(line: ctx.cursor.line, column: currentLine.charLen)

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

      # Move cursor to the first non-whitespace character of pasted line
      ctx.cursor.line = ctx.cursor.line + 1
      ctx.cursor.column =
        firstNonBlankColumn(ctx.buffer.getLine(ctx.cursor.line).toRunes())
    else:
      # Paste after cursor position (Vim 'p' behavior for characterwise yank)
      let lineContent = ctx.buffer.getLine(ctx.cursor.line)
      var pastePos = ctx.cursor

      # Move one character right if not at end of line (only for first paste)
      if i == 1 and ctx.cursor.column < lineContent.charLen:
        pastePos.column = ctx.cursor.column + 1

      let insertResult = ctx.buffer.insertText(pastePos, pasteText)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.commitTransaction()
        return err(insertResult.error)

      # Update cursor position for next paste
      ctx.cursor.column = pastePos.column + pasteText.charLen

  # Adjust cursor to last character of pasted text
  if not isFullLine and pasteText.charLen > 0:
    ctx.cursor.column = ctx.cursor.column - 1

  # Commit transaction if we started one
  if actualCount > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecPaste, pasteCount: actualCount, pasteBefore: false))

  ctx.state.windowDisplay.needsFullRedraw = true
  return Result[(), string].ok ()

proc handlePasteBefore(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Paste text from internal register or system clipboard before cursor (P command)
  ## Mimics Vim's 'P' behavior
  ## count: number of times to paste (default: 1)

  logDebug("paste", "handlePasteBefore called with count=" & $count)
  let actualCount = max(1, count)

  # Get content from register system
  var pasteText: string
  var isFullLine: bool

  if ctx.state.pendingRegister.isSome and ctx.state.pendingRegister.get != '\0':
    # User specified a register with "
    let regName = ctx.state.pendingRegister.get
    let reg = ctx.state.registers.getRegister(regName)
    pasteText = reg.getContent()
    isFullLine = reg.isLine
    ctx.state.pendingRegister = none(char)
    ctx.state.statusMessage = ""
    logDebug("paste", "Using register '" & $regName & "', length: " & $pasteText.len)
  else:
    # Use unnamed register (most recent yank/delete)
    let reg = ctx.state.registers.getNoNamedRegister()
    pasteText = reg.getContent()
    isFullLine = reg.isLine
    logDebug("paste", "Using unnamed register, length: " & $pasteText.len)

  logDebug(
    "paste", "Paste content length: " & $pasteText.len & ", isLine=" & $isFullLine
  )

  # If register is empty, try system clipboard (if enabled)
  if pasteText.len == 0 and ctx.clipboardConfig.enable:
    logDebug("paste", "Register empty, trying clipboard")
    let readResult = readFromClipboardSync(ctx.clipboardConfig.tool)
    if readResult.isErr:
      return err(
        "Nothing to paste (register empty and clipboard error: " & readResult.error & ")"
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
      let pastePos = BufferPosition(line: ctx.cursor.line, column: 0)

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

      # Move cursor to the first non-whitespace character of pasted line
      ctx.cursor.column =
        firstNonBlankColumn(ctx.buffer.getLine(ctx.cursor.line).toRunes())
    else:
      # Paste at cursor position (Vim 'P' behavior for characterwise yank)
      let pastePos = ctx.cursor

      let insertResult = ctx.buffer.insertText(pastePos, pasteText)
      if insertResult.isErr:
        # Rollback transaction on error
        if actualCount > 1:
          discard ctx.buffer.commitTransaction()
        return err(insertResult.error)

      # Update cursor position for next paste
      ctx.cursor.column = pastePos.column + pasteText.charLen

  # Adjust cursor to last character of pasted text
  if not isFullLine and pasteText.charLen > 0:
    ctx.cursor.column = ctx.cursor.column - 1

  # Commit transaction if we started one
  if actualCount > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecPaste, pasteCount: actualCount, pasteBefore: true))

  ctx.state.windowDisplay.needsFullRedraw = true
  return Result[(), string].ok ()

proc handleDeleteChar(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete character(s) at cursor position (x command)
  ## count: number of characters to delete (default: 1)
  ## With autoDeleteParen enabled, deleting an opening paren also deletes matching closing paren

  logDebug("delete", "handleDeleteChar called with count=" & $count)
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    return err("Nothing to delete")

  # Auto-delete adjacent paren pairs only (e.g., [] () {} "" '')
  if ctx.state.display.autoDeleteParen and actualCount == 1:
    let cursorCol = ctx.cursor.column

    try:
      if isAdjacentPair(lineContent, cursorCol):
        let txnResult = ctx.buffer.beginTransaction("delete paren pair")
        if txnResult.isErr:
          return err(txnResult.error)

        # Delete opening char, then closing char (now at same position)
        for i in 0 ..< 2:
          let delResult = ctx.buffer.deleteRange(
            BufferPosition(line: ctx.cursor.line, column: cursorCol),
            BufferPosition(line: ctx.cursor.line, column: cursorCol),
          )
          if delResult.isErr:
            discard ctx.buffer.commitTransaction()
            return err(delResult.error)

        let commitResult = ctx.buffer.commitTransaction()
        if commitResult.isErr:
          return err(commitResult.error)

        storeDeletedText(ctx, $lineContent.runeAtPos(cursorCol), false)

        # Adjust cursor if past end of line
        let updatedLineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
        if updatedLineLen > 0 and ctx.cursor.column >= updatedLineLen:
          ctx.cursor.column = updatedLineLen - 1

        ctx.state.windowDisplay.needsFullRedraw = true
        return Result[(), string].ok ()
    except CatchableError:
      # If auto-delete fails, fall through to normal delete
      discard

  # Normal delete logic
  # Calculate how many characters we can actually delete
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Extract the characters to be deleted (for yank register)
  # Get the line content and extract the substring
  let runes = lineContent.toRunes()
  var deletedText = ""
  for i in 0 ..< charsToDelete:
    let runeIdx = ctx.cursor.column + i
    if runeIdx < runes.len:
      deletedText.add($runes[runeIdx])

  # Store in register system (respects pendingRegister)
  storeDeletedText(ctx, deletedText, false)

  # Begin transaction if deleting multiple characters
  if charsToDelete > 1:
    let txnResult = ctx.buffer.beginTransaction("delete " & $charsToDelete & " chars")
    if txnResult.isErr:
      return err(txnResult.error)

  # Delete the characters
  for i in 0 ..< charsToDelete:
    # deleteRange is inclusive, so endPos should be at the same column as cursor
    # to delete only one character
    let endPos = ctx.cursor
    let delResult = ctx.buffer.deleteRange(ctx.cursor, endPos)
    if delResult.isErr:
      if charsToDelete > 1:
        discard ctx.buffer.commitTransaction()
      return err(delResult.error)

  # Commit transaction if we started one
  if charsToDelete > 1:
    let txnResult = ctx.buffer.commitTransaction()
    if txnResult.isErr:
      return err(txnResult.error)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand = some(
    LastEditCommand(
      kind: lecDeleteChar, deleteCount: charsToDelete, deleteForward: true
    )
  )

  # Adjust cursor if it's now past the end of the line (Vim behavior)
  let newLineContent = ctx.buffer.getLine(ctx.cursor.line)
  let newLineLen = newLineContent.charLen
  if newLineLen > 0 and ctx.cursor.column >= newLineLen:
    ctx.cursor.column = newLineLen - 1

  ctx.state.windowDisplay.needsFullRedraw = true
  return Result[(), string].ok ()

proc handleDeleteCharBefore(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete character(s) before cursor position (X command)
  ## count: number of characters to delete (default: 1)
  ## With autoDeleteParen enabled, deleting a closing paren also deletes matching opening paren

  logDebug("delete", "handleDeleteCharBefore called with count=" & $count)
  let actualCount = max(1, count)

  # Check if we're at the beginning of the line
  if ctx.cursor.column == 0:
    return err("Nothing to delete")

  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Auto-delete adjacent paren pairs only (e.g., [] () {} "" '')
  if ctx.state.display.autoDeleteParen and actualCount == 1:
    let cursorCol = ctx.cursor.column

    try:
      # X deletes char before cursor; check if char at cursorCol-1 and cursorCol form a pair
      if isAdjacentPair(lineContent, cursorCol - 1):
        let txnResult = ctx.buffer.beginTransaction("delete paren pair")
        if txnResult.isErr:
          return err(txnResult.error)

        # Delete opening char, then closing char (now at same position)
        for i in 0 ..< 2:
          let delResult = ctx.buffer.deleteRange(
            BufferPosition(line: ctx.cursor.line, column: cursorCol - 1),
            BufferPosition(line: ctx.cursor.line, column: cursorCol - 1),
          )
          if delResult.isErr:
            discard ctx.buffer.commitTransaction()
            return err(delResult.error)

        let commitResult = ctx.buffer.commitTransaction()
        if commitResult.isErr:
          return err(commitResult.error)

        storeDeletedText(ctx, $lineContent.runeAtPos(cursorCol - 1), false)
        ctx.cursor.column = cursorCol - 1

        ctx.state.windowDisplay.needsFullRedraw = true
        return Result[(), string].ok ()
    except CatchableError:
      # If auto-delete fails, fall through to normal delete
      discard

  # Normal delete logic
  # Calculate how many characters we can actually delete
  let charsAvailable = ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Calculate the start position for deletion
  let startColumn = ctx.cursor.column - charsToDelete

  # Extract the characters to be deleted (for yank register)
  # Get the line content and extract the substring
  let runes = lineContent.toRunes()
  var deletedText = ""
  for i in 0 ..< charsToDelete:
    let runeIdx = startColumn + i
    if runeIdx < runes.len:
      deletedText.add($runes[runeIdx])

  # Store in register system (respects pendingRegister)
  storeDeletedText(ctx, deletedText, false)

  # Begin transaction if deleting multiple characters
  if charsToDelete > 1:
    let txnResult = ctx.buffer.beginTransaction("delete " & $charsToDelete & " chars")
    if txnResult.isErr:
      return err(txnResult.error)

  # Delete the characters (delete from startColumn multiple times)
  for i in 0 ..< charsToDelete:
    let startPos = BufferPosition(line: ctx.cursor.line, column: startColumn)
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
  ctx.cursor.column = startColumn

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand = some(
    LastEditCommand(
      kind: lecDeleteChar, deleteCount: charsToDelete, deleteForward: false
    )
  )

  ctx.state.windowDisplay.needsFullRedraw = true
  return Result[(), string].ok ()

proc handleSubstituteChar(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Substitute character(s) at cursor position (s command)
  ## Deletes character(s) and enters Insert mode
  ## count: number of characters to substitute (default: 1)

  logDebug("substitute", "handleSubstituteChar called with count=" & $count)
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    # At end of line, just enter insert mode
    ctx.state.mode = EditorMode.Insert
    let transactionResult = ctx.buffer.beginTransaction("Substitute")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)
    ctx.state.statusMessage = "-- INSERT --"
    return Result[(), string].ok ()

  # Calculate how many characters we can actually delete
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToDelete = min(actualCount, charsAvailable)

  # Extract the characters to be deleted (for yank register)
  let runes = lineContent.toRunes()
  var deletedText = ""
  for i in 0 ..< charsToDelete:
    let runeIdx = ctx.cursor.column + i
    if runeIdx < runes.len:
      deletedText.add($runes[runeIdx])

  # Store in register system (respects pendingRegister)
  storeDeletedText(ctx, deletedText, false)

  # Begin transaction for delete + insert mode (all in one undo unit)
  let txnResult =
    ctx.buffer.beginTransaction("substitute " & $charsToDelete & " char(s)")
  if txnResult.isErr:
    return err(txnResult.error)

  # Delete the characters
  for i in 0 ..< charsToDelete:
    let endPos = ctx.cursor
    let delResult = ctx.buffer.deleteRange(ctx.cursor, endPos)
    if delResult.isErr:
      discard ctx.buffer.rollbackTransaction()
      return err(delResult.error)

  # Enter Insert mode (transaction remains open for insert mode input)
  ctx.state.mode = EditorMode.Insert

  # Record substitute context so Insert mode exit can properly record the command
  ctx.state.editState.substituteContext =
    some(SubstituteContext(kind: skChar, deleteCount: charsToDelete))

  ctx.state.windowDisplay.needsFullRedraw = true
  ctx.state.statusMessage = "-- INSERT --"
  return Result[(), string].ok ()

proc handleSubstituteLine(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Substitute line(s) (S command or cc)
  ## Deletes line content and enters Insert mode
  ## count: number of lines to substitute (default: 1)

  logDebug("substitute", "handleSubstituteLine called with count=" & $count)
  let actualCount = max(1, count)
  let startLine = ctx.cursor.line
  let endLine = min(startLine + actualCount - 1, ctx.buffer.len - 1)

  # Extract lines for yank register
  var text = ""
  for lineIdx in startLine .. endLine:
    if lineIdx < ctx.buffer.len:
      let lineContent = ctx.buffer.getLine(lineIdx)
      text.add(lineContent)
      if lineContent.len == 0 or lineContent[^1] != '\n':
        text.add("\n")

  # Store in register system (respects pendingRegister)
  storeDeletedText(ctx, text, true)

  # Get indent from first line (for auto-indent)
  let firstLine = ctx.buffer.getLine(startLine)
  var indent = ""
  for rune in firstLine.toRunes():
    let ch = $rune
    if ch == " " or ch == "\t":
      indent.add(ch)
    else:
      break

  # Begin transaction for all substitute operations (delete + insert mode input)
  let transactionResult = ctx.buffer.beginTransaction("Substitute line")
  if transactionResult.isErr:
    return err("Failed to begin transaction: " & transactionResult.error)

  # Delete all but first line
  for i in 0 ..< (endLine - startLine):
    if startLine + 1 < ctx.buffer.len:
      let deleteResult = ctx.buffer.deleteLine(startLine + 1)
      if deleteResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err("Failed to delete line: " & deleteResult.error)

  # Clear the first line but preserve indent
  if startLine < ctx.buffer.len:
    let line = ctx.buffer.getLine(startLine)
    # Delete all characters in the line
    for i in 0 ..< line.charLen:
      let deleteResult = ctx.buffer.deleteRange(
        BufferPosition(line: startLine, column: 0),
        BufferPosition(line: startLine, column: 0),
      )
      if deleteResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err("Failed to clear line: " & deleteResult.error)

    # Insert indent if auto-indent is enabled
    if ctx.state.display.autoIndent and indent.len > 0:
      let insertResult =
        ctx.buffer.insertText(BufferPosition(line: startLine, column: 0), indent)
      if insertResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err("Failed to insert indent: " & insertResult.error)

  # Move cursor to beginning of line (after indent)
  ctx.cursor.line = startLine
  ctx.cursor.column = indent.len

  # Enter Insert mode (transaction remains open for insert mode input)
  ctx.state.mode = EditorMode.Insert

  # Record substitute context so Insert mode exit can properly record the command
  let lineCount = endLine - startLine + 1
  ctx.state.editState.substituteContext =
    some(SubstituteContext(kind: skLine, deleteCount: lineCount))

  ctx.state.windowDisplay.needsFullRedraw = true
  ctx.state.statusMessage = "-- INSERT --"
  return Result[(), string].ok ()

proc handleToggleCase(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Toggle case of character(s) at cursor position (~ command)
  ## Changes uppercase to lowercase and vice versa, then moves cursor right
  ## count: number of characters to toggle (default: 1)

  logDebug("toggle", "handleToggleCase called with count=" & $count)
  let actualCount = max(1, count)
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if we're at or past the end of the line
  if ctx.cursor.column >= lineContent.charLen:
    return err("Nothing to toggle")

  # Calculate how many characters we can actually toggle
  let charsAvailable = lineContent.charLen - ctx.cursor.column
  let charsToToggle = min(actualCount, charsAvailable)

  # Begin transaction for all toggle operations (to group as single undo)
  let txnResult = ctx.buffer.beginTransaction("toggle " & $charsToToggle & " char(s)")
  if txnResult.isErr:
    return err(txnResult.error)

  # Toggle each character
  let runes = lineContent.toRunes()
  for i in 0 ..< charsToToggle:
    let runeIdx = ctx.cursor.column + i
    if runeIdx < runes.len:
      let originalChar = $runes[runeIdx]

      # Toggle case: convert to uppercase if lowercase, lowercase if uppercase
      var toggledChar: string
      if originalChar == originalChar.toUpperAscii():
        # Character is uppercase (or non-alphabetic), convert to lowercase
        toggledChar = originalChar.toLowerAscii()
      else:
        # Character is lowercase, convert to uppercase
        toggledChar = originalChar.toUpperAscii()

      # Only perform replacement if the character actually changed
      if originalChar != toggledChar:
        let pos = BufferPosition(line: ctx.cursor.line, column: ctx.cursor.column + i)

        # Delete original character
        let delResult = ctx.buffer.deleteRange(pos, pos)
        if delResult.isErr:
          discard ctx.buffer.commitTransaction()
          return err(delResult.error)

        # Insert toggled character
        let insResult = ctx.buffer.insertText(pos, toggledChar)
        if insResult.isErr:
          discard ctx.buffer.commitTransaction()
          return err(insResult.error)

  # Commit transaction
  let commitResult = ctx.buffer.commitTransaction()
  if commitResult.isErr:
    return err(commitResult.error)

  # Move cursor to the right by the number of characters toggled
  ctx.cursor.column += charsToToggle

  # Keep cursor within line bounds (in Normal mode, cursor can't be on newline)
  let finalLineContent = ctx.buffer.getLine(ctx.cursor.line)
  if ctx.cursor.column >= finalLineContent.charLen:
    ctx.cursor.column = max(0, finalLineContent.charLen - 1)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecToggleCase, toggleCaseCount: charsToToggle))

  ctx.state.windowDisplay.needsFullRedraw = true
  return Result[(), string].ok ()

proc handleDeleteLine(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete current line(s) and store in yank register (dd command)
  ## count: number of lines to delete (default: 1)

  logDebug("delete", "handleDeleteLine called with count=" & $count)
  let actualCount = max(1, count)
  let startLine = ctx.cursor.line
  let endLine = min(startLine + actualCount - 1, ctx.buffer.len - 1)

  # Build text from lines to be deleted (for yank register)
  var deletedText = ""
  for lineIdx in startLine .. endLine:
    if lineIdx < ctx.buffer.len:
      let lineContent = ctx.buffer.getLine(lineIdx)
      deletedText.add(lineContent)
      if lineIdx < endLine or (lineContent.len > 0 and lineContent[^1] != '\n'):
        deletedText.add("\n")

  # Store in register system (respects pendingRegister)
  storeDeletedText(ctx, deletedText, true)

  # Begin transaction for line deletions
  let transactionResult =
    ctx.buffer.beginTransaction("Delete " & $actualCount & " line(s)")
  if transactionResult.isErr:
    return err("Failed to begin transaction: " & transactionResult.error)

  # Delete the lines (keep at least one line in the buffer)
  var brokeEarly = false
  for i in 1 .. actualCount:
    if startLine < ctx.buffer.len:
      if ctx.buffer.len == 1:
        brokeEarly = true
        break
      let delResult = ctx.buffer.deleteLine(startLine)
      if delResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err(delResult.error)

  # If we stopped because the buffer was down to 1 line, clear its content
  if brokeEarly:
    let lastLine = ctx.buffer.getLine(0)
    if lastLine.len > 0:
      let clearResult = ctx.buffer.deleteRange(
        BufferPosition(line: 0, column: 0),
        BufferPosition(line: 0, column: lastLine.charLen - 1),
      )
      if clearResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err(clearResult.error)

  # Commit transaction
  let commitResult = ctx.buffer.commitTransaction()
  if commitResult.isErr:
    return err("Failed to commit transaction: " & commitResult.error)

  # Adjust cursor position if needed
  if ctx.cursor.line >= ctx.buffer.len:
    ctx.cursor.line = max(0, ctx.buffer.len - 1)
  # Preserve column position, clamped to end of new current line
  let newLine = ctx.buffer.getLine(ctx.cursor.line)
  if newLine.charLen > 0:
    ctx.cursor.column = min(ctx.cursor.column, newLine.charLen - 1)
  else:
    ctx.cursor.column = 0

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecDeleteLine, deleteLineCount: actualCount))

  ctx.state.windowDisplay.needsFullRedraw = true
  # Delete screen notification (controlled by config)
  if ctx.notificationConfig.screenNotifications and
      ctx.notificationConfig.deleteScreenNotify:
    ctx.notify("Deleted " & $actualCount & " line(s)")

  # Delete log notification (controlled by config)
  if ctx.notificationConfig.logNotifications and ctx.notificationConfig.deleteLogNotify:
    logInfo("delete", "Deleted " & $actualCount & " line(s)")

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
  let startLine = ctx.cursor.line
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

  # Store in register system (respects pendingRegister)
  storeYankedText(ctx, yankText, true)

  let storedReg = ctx.state.registers.getNoNamedRegister()
  logDebug(
    "yank",
    "Stored in register: '" & storedReg.getContent() & "', isLine=" & $storedReg.isLine,
  )

  # Yank screen notification (controlled by config)
  if ctx.notificationConfig.screenNotifications and
      ctx.notificationConfig.yankScreenNotify:
    ctx.notify("Yanked " & $actualCount & " line(s)")

  # Yank log notification (controlled by config)
  if ctx.notificationConfig.logNotifications and ctx.notificationConfig.yankLogNotify:
    logInfo("yank", "Yanked " & $actualCount & " line(s)")

  return Result[(), string].ok ()

proc handleJoinLines(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Join lines starting from current line (J command)
  ## count: number of additional lines to join (default: 1, meaning join 2 lines total)
  ## Example: count=1 joins current and next line, count=2 joins 3 lines, etc.

  logDebug("join", "handleJoinLines called with count=" & $count)
  let actualCount = max(1, count)

  # Join lines using the buffer's joinLines function
  let joinResult = ctx.buffer.joinLines(ctx.cursor.line, actualCount)
  if joinResult.isErr:
    return err(joinResult.error)

  # Record this command for repeat (.)
  ctx.state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecJoinLines, joinLinesCount: actualCount))

  ctx.state.windowDisplay.needsFullRedraw = true
  let totalLines = actualCount + 1
  ctx.state.statusMessage = "Joined " & $totalLines & " line(s)"
  return Result[(), string].ok ()

proc handleShowCharInfo(ctx: CommandContext): Result[(), string] =
  ## Show ASCII/Unicode value of character under cursor (ga command)
  ## Displays character info in status message

  logDebug("charinfo", "handleShowCharInfo called")
  let lineContent = ctx.buffer.getLine(ctx.cursor.line)

  # Check if cursor is at valid position
  if ctx.cursor.column >= lineContent.charLen:
    ctx.state.statusMessage = "No character under cursor"
    return Result[(), string].ok ()

  # Get the character at cursor position
  let runes = lineContent.toRunes()
  if ctx.cursor.column < runes.len:
    let ch = runes[ctx.cursor.column]
    let codepoint = ch.int32

    # Format the message like Vim: <c>  123,  Hex 7b,  Oct 173
    var msg = "<" & $ch & ">"
    msg &= "  " & $codepoint & ","
    msg &= "  Hex " & toHex(codepoint, 2) & ","
    msg &= "  Oct " & toOct(codepoint, 3)

    ctx.state.statusMessage = msg
  else:
    ctx.state.statusMessage = "No character under cursor"

  return Result[(), string].ok ()

## Operator command handlers
## Use setPendingOperator() for all operators to save viewport position
## before motion execution. This prevents unwanted scrolling.

proc setPendingOperator(
    ctx: CommandContext, operatorType: OperatorType, count: int, statusMsg: string
) =
  ## Set pending operator and save viewport position for operator+motion commands
  ctx.state.windowDisplay.savedViewportTopLine =
    ctx.motionController.viewportManager.viewport.topLine
  ctx.state.editState.pendingOperator = some(
    PendingOperator(
      operatorType: operatorType, operatorCount: count, startPos: ctx.cursor
    )
  )
  ctx.state.statusMessage = statusMsg

proc handleOperatorYank(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Yank operator - waits for motion (y2w, y$, etc.) or yy for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (yy for yank line)
  if ctx.state.editState.pendingOperator.isSome and
      ctx.state.editState.pendingOperator.get.operatorType == OpYank:
    # Execute line yank
    let startLine = ctx.cursor.line
    let operatorCount = ctx.state.editState.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)

    # Extract lines for yank register
    var text = ""
    for lineIdx in startLine .. endLine:
      if lineIdx < ctx.buffer.len:
        let lineContent = ctx.buffer.getLine(lineIdx)
        text.add(lineContent)
        if lineContent.len == 0 or lineContent[^1] != '\n':
          text.add("\n")

    # Store in register system (respects pendingRegister)
    storeYankedText(ctx, text, true)

    # Clear operator state
    ctx.state.editState.pendingOperator = none(PendingOperator)
    let lineCount = endLine - startLine + 1
    # Yank screen notification (controlled by config)
    if ctx.notificationConfig.screenNotifications and
        ctx.notificationConfig.yankScreenNotify:
      ctx.notify("Yanked " & $lineCount & " line(s)")
    # Yank log notification (controlled by config)
    if ctx.notificationConfig.logNotifications and ctx.notificationConfig.yankLogNotify:
      logInfo("yank", "Yanked " & $lineCount & " line(s)")
    return ok(())
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpYank, count, "y")
    return ok(())

proc handleOperatorDelete(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Delete operator - waits for motion (d2w, d$, etc.) or dd for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (dd for delete line)
  if ctx.state.editState.pendingOperator.isSome and
      ctx.state.editState.pendingOperator.get.operatorType == OpDelete:
    # Execute line deletion
    let startLine = ctx.cursor.line
    let operatorCount = ctx.state.editState.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)
    let lineCount = endLine - startLine + 1

    # Begin transaction for all line deletions
    let transactionResult =
      ctx.buffer.beginTransaction("Delete " & $lineCount & " line(s)")
    if transactionResult.isErr:
      return err("Failed to begin transaction: " & transactionResult.error)

    # Extract lines for yank register
    var text = ""
    for lineIdx in startLine .. endLine:
      if lineIdx < ctx.buffer.len:
        let lineContent = ctx.buffer.getLine(lineIdx)
        text.add(lineContent)
        if lineContent.len == 0 or lineContent[^1] != '\n':
          text.add("\n")

    # Store in register system (respects pendingRegister)
    storeDeletedText(ctx, text, true)

    # Delete lines (keep at least one line in the buffer)
    var brokeEarly = false
    for i in 0 ..< lineCount:
      if startLine < ctx.buffer.len:
        if ctx.buffer.len == 1:
          brokeEarly = true
          break
        let deleteResult = ctx.buffer.deleteLine(startLine)
        if deleteResult.isErr:
          discard ctx.buffer.rollbackTransaction()
          return err("Failed to delete line: " & deleteResult.error)

    # If we stopped because the buffer was down to 1 line, clear its content
    if brokeEarly:
      let lastLine = ctx.buffer.getLine(0)
      if lastLine.len > 0:
        let clearResult = ctx.buffer.deleteRange(
          BufferPosition(line: 0, column: 0),
          BufferPosition(line: 0, column: lastLine.charLen - 1),
        )
        if clearResult.isErr:
          discard ctx.buffer.rollbackTransaction()
          return err("Failed to clear last line: " & clearResult.error)

    # Commit transaction
    let commitResult = ctx.buffer.commitTransaction()
    if commitResult.isErr:
      return err("Failed to commit transaction: " & commitResult.error)

    # Move cursor to start line, preserve column position
    ctx.cursor.line = min(startLine, ctx.buffer.len - 1)
    # Preserve column position, clamped to end of new current line
    let newLine = ctx.buffer.getLine(ctx.cursor.line)
    if newLine.charLen > 0:
      ctx.cursor.column = min(ctx.cursor.column, newLine.charLen - 1)
    else:
      ctx.cursor.column = 0

    # Record this command for repeat (.)
    ctx.state.editState.lastEditCommand =
      some(LastEditCommand(kind: lecDeleteLine, deleteLineCount: lineCount))

    # Clear operator state
    ctx.state.editState.pendingOperator = none(PendingOperator)
    # Delete screen notification (controlled by config)
    if ctx.notificationConfig.screenNotifications and
        ctx.notificationConfig.deleteScreenNotify:
      ctx.notify("Deleted " & $lineCount & " line(s)")
    # Delete log notification (controlled by config)
    if ctx.notificationConfig.logNotifications and ctx.notificationConfig.deleteLogNotify:
      logInfo("delete", "Deleted " & $lineCount & " line(s)")
    return ok(())
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpDelete, count, "d")
    return ok(())

proc handleOperatorChange(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Change operator - waits for motion (c2w, c$, etc.) or cc for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (cc for change line)
  if ctx.state.editState.pendingOperator.isSome and
      ctx.state.editState.pendingOperator.get.operatorType == OpChange:
    # Execute line change using handleSubstituteLine (same as S command)
    let operatorCount = ctx.state.editState.pendingOperator.get.operatorCount
    # Clear operator state before calling handleSubstituteLine
    ctx.state.editState.pendingOperator = none(PendingOperator)
    return handleSubstituteLine(ctx, operatorCount)
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpChange, count, "c")
    return ok(())

proc handleOperatorIndent(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Indent operator - waits for motion (>2w, >$, etc.) or >> for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (>> for indent line)
  if ctx.state.editState.pendingOperator.isSome and
      ctx.state.editState.pendingOperator.get.operatorType == OpIndent:
    let startLine = ctx.cursor.line
    let operatorCount = ctx.state.editState.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)
    ctx.state.editState.pendingOperator = none(PendingOperator)

    let range = OperatorRange(
      start: BufferPosition(line: startLine, column: 0),
      endPos: BufferPosition(line: endLine, column: 0),
      isLinewise: true,
    )
    return executeOperatorOnRange(ctx, OpIndent, range, 1)
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpIndent, count, ">")
    return ok(())

proc handleOperatorOutdent(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Outdent operator - waits for motion (<2w, <$, etc.) or << for line
  ## count: number of times to apply the operator (default: 1)

  # Check if same operator was pressed (<< for dedent line)
  if ctx.state.editState.pendingOperator.isSome and
      ctx.state.editState.pendingOperator.get.operatorType == OpOutdent:
    let startLine = ctx.cursor.line
    let operatorCount = ctx.state.editState.pendingOperator.get.operatorCount
    let endLine = min(startLine + operatorCount - 1, ctx.buffer.len - 1)
    ctx.state.editState.pendingOperator = none(PendingOperator)

    let range = OperatorRange(
      start: BufferPosition(line: startLine, column: 0),
      endPos: BufferPosition(line: endLine, column: 0),
      isLinewise: true,
    )
    return executeOperatorOnRange(ctx, OpOutdent, range, 1)
  else:
    # Set pending operator for motion
    setPendingOperator(ctx, OpOutdent, count, "<")
    return ok(())

proc handleOperatorLowerCase(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Lowercase operator - waits for motion (guw, gu$, etc.)
  ## count: number of times to apply the operator (default: 1)

  # Set pending operator for motion
  setPendingOperator(ctx, OpLowerCase, count, "gu")
  return ok(())

proc handleOperatorUpperCase(ctx: CommandContext, count: int = 1): Result[(), string] =
  ## Uppercase operator - waits for motion (gUw, gU$, etc.)
  ## count: number of times to apply the operator (default: 1)

  # Set pending operator for motion
  setPendingOperator(ctx, OpUpperCase, count, "gU")
  return ok(())

## Text object command handlers

proc handleTextObjectInner(ctx: CommandContext): Result[(), string] =
  ## Handle inner text object (iw, i", i(, etc.) or enter Insert mode

  # Check if we have a pending operator
  if ctx.state.editState.pendingOperator.isSome:
    # We have a pending operator - set text object modifier
    let operatorCount = ctx.state.editState.pendingOperator.get.operatorCount
    ctx.state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: operatorCount))
    ctx.state.statusMessage =
      $ctx.state.editState.pendingOperator.get.operatorType & "i"
    return ok(())
  elif isVisualAllMode(ctx.state.mode):
    # In Visual mode - set text object modifier for visual selection
    ctx.state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomInner, operatorCount: 1))
    return ok(())
  else:
    # No pending operator - enter Insert mode
    ctx.state.mode = EditorMode.Insert
    # Begin transaction for insert mode edit (guard for insert-normal mode)
    if not ctx.buffer.inTransaction:
      let transactionResult = ctx.buffer.beginTransaction("Insert mode edit")
      if transactionResult.isErr:
        return err("Failed to begin transaction: " & transactionResult.error)
    ctx.state.statusMessage = "-- INSERT --"
    return ok(())

proc handleTextObjectAround(ctx: CommandContext): Result[(), string] =
  ## Handle around text object (aw, a", a(, etc.) or enter Append mode

  # Check if we have a pending operator
  if ctx.state.editState.pendingOperator.isSome:
    # We have a pending operator - set text object modifier
    let operatorCount = ctx.state.editState.pendingOperator.get.operatorCount
    ctx.state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: operatorCount))
    ctx.state.statusMessage =
      $ctx.state.editState.pendingOperator.get.operatorType & "a"
    return ok(())
  elif isVisualAllMode(ctx.state.mode):
    # In Visual mode - set text object modifier for visual selection
    ctx.state.editState.pendingTextObject =
      some(PendingTextObject(modifier: tomAround, operatorCount: 1))
    return ok(())
  else:
    # No pending operator - enter Append mode (move cursor right, then Insert)
    # Move cursor one position to the right if not at end of line
    if ctx.cursor.line < ctx.buffer.len:
      let currentLine = ctx.buffer.getLine(ctx.cursor.line)
      # Use charLen for proper multi-byte character support
      if ctx.cursor.column < currentLine.charLen:
        ctx.cursor.column += 1
    # Enter Insert mode
    ctx.state.mode = EditorMode.Insert
    # Begin transaction for insert mode edit (guard for insert-normal mode)
    if not ctx.buffer.inTransaction:
      let transactionResult = ctx.buffer.beginTransaction("Append mode edit")
      if transactionResult.isErr:
        return err("Failed to begin transaction: " & transactionResult.error)
    ctx.state.statusMessage = "-- INSERT --"
    return ok(())

## Scroll commands

proc handleScrollCursorTop(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Scroll the viewport to place cursor line at the top (zt command)
  ## Cursor position doesn't change, only the viewport

  ctx.motionController.viewportManager.viewport.topLine = ctx.cursor.line
  return ok(())

proc handleScrollCursorCenter(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Scroll the viewport to place cursor line at the center (z. or zz command)
  ## Cursor position doesn't change, only the viewport

  # Calculate reserved lines (status line + command line share same row)
  let reservedLines =
    if ctx.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve
  let visibleHeight =
    ctx.motionController.viewportManager.viewport.height - reservedLines

  # Center the cursor line
  let targetTopLine = ctx.cursor.line - (visibleHeight div 2)

  # Clamp to valid range
  ctx.motionController.viewportManager.viewport.topLine = max(0, targetTopLine)

  return ok(())

proc handleScrollCursorBottom(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Scroll the viewport to place cursor line at the bottom (zb command)
  ## Cursor position doesn't change, only the viewport

  # Calculate reserved lines (status line + command line share same row)
  let reservedLines =
    if ctx.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve
  let visibleHeight =
    ctx.motionController.viewportManager.viewport.height - reservedLines

  # Place cursor at the bottom of viewport
  let targetTopLine = ctx.cursor.line - visibleHeight + 1

  # Clamp to valid range
  ctx.motionController.viewportManager.viewport.topLine = max(0, targetTopLine)

  return ok(())

## Fold commands

proc handleFoldOpen(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Open fold at cursor position (zo command)
  if ctx.buffer.foldState.openFold(ctx.cursor.line):
    ctx.state.windowDisplay.needsFullRedraw = true
    return ok(())
  else:
    ctx.state.statusMessage = "No fold found"
    return ok(())

proc handleFoldClose(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Close fold at cursor position (zc command)
  if ctx.buffer.foldState.closeFold(ctx.cursor.line):
    ctx.state.windowDisplay.needsFullRedraw = true
    # Ensure cursor is not on a hidden line after closing
    if ctx.buffer.foldState.isLineInCollapsedFold(ctx.cursor.line):
      ctx.cursor.line = ctx.buffer.foldState.getPrevVisibleLine(ctx.cursor.line)
      # Clamp column to new line's length
      let lineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
      ctx.cursor.column = min(ctx.cursor.column, max(0, lineLen - 1))
    return ok(())
  else:
    ctx.state.statusMessage = "No fold found"
    return ok(())

proc handleFoldToggle(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Toggle fold at cursor position (za command)
  if ctx.buffer.foldState.toggleFold(ctx.cursor.line):
    ctx.state.windowDisplay.needsFullRedraw = true
    # Ensure cursor is not on a hidden line after closing
    if ctx.buffer.foldState.isLineInCollapsedFold(ctx.cursor.line):
      ctx.cursor.line = ctx.buffer.foldState.getPrevVisibleLine(ctx.cursor.line)
      let lineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
      ctx.cursor.column = min(ctx.cursor.column, max(0, lineLen - 1))
    return ok(())
  else:
    ctx.state.statusMessage = "No fold found"
    return ok(())

proc handleFoldOpenAll(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Open all folds (zR command)
  ctx.buffer.foldState.openAllFolds()
  ctx.state.windowDisplay.needsFullRedraw = true
  return ok(())

proc handleFoldCloseAll(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Close all folds (zM command)
  ctx.buffer.foldState.closeAllFolds()
  ctx.state.windowDisplay.needsFullRedraw = true
  # Ensure cursor is not on a hidden line
  if ctx.buffer.foldState.isLineInCollapsedFold(ctx.cursor.line):
    ctx.cursor.line = ctx.buffer.foldState.getPrevVisibleLine(ctx.cursor.line)
    # Clamp column to new line's length
    let lineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
    ctx.cursor.column = min(ctx.cursor.column, max(0, lineLen - 1))
  return ok(())

proc handleFoldCreate(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Create fold from visual selection (zf command)
  ## This is called from visual mode with the selection range
  if not ctx.state.visualSelection.active:
    ctx.state.statusMessage = "No selection"
    return ok(())

  let
    startLine =
      min(ctx.state.visualSelection.start.line, ctx.state.visualSelection.current.line)
    endLine =
      max(ctx.state.visualSelection.start.line, ctx.state.visualSelection.current.line)

  if ctx.buffer.foldState.addFold(startLine, endLine):
    ctx.state.statusMessage = "Fold created"
    ctx.state.windowDisplay.needsFullRedraw = true
    # Exit visual mode
    ctx.state.visualSelection.active = false
    ctx.state.mode = EditorMode.Normal
  else:
    ctx.state.statusMessage = "Cannot create overlapping fold"

  return ok(())

proc handleFoldDelete(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Delete fold at cursor position (zd command)
  if ctx.buffer.foldState.deleteFold(ctx.cursor.line):
    ctx.state.statusMessage = "Fold deleted"
    ctx.state.windowDisplay.needsFullRedraw = true
    return ok(())
  else:
    ctx.state.statusMessage = "No fold found"
    return ok(())

proc handleFoldDeleteAll(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Delete all folds (zD command)
  let foldCount = ctx.buffer.foldState.folds.len
  if foldCount > 0:
    ctx.buffer.foldState.deleteAllFolds()
    ctx.state.statusMessage = $foldCount & " fold(s) deleted"
    ctx.state.windowDisplay.needsFullRedraw = true
  else:
    ctx.state.statusMessage = "No folds to delete"
  return ok(())

proc handleQuickRun(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Run current buffer (\r command)
  ## Sets requestQuickRun flag which is handled by the main event loop
  ctx.state.requestQuickRun = true
  return ok(())

proc findNumberAtOrAfterColumn(
    line: string, startCol: int
): tuple[found: bool, startPos: int, endPos: int, value: int] =
  ## Find a number at or after the given column in the line
  ## Returns (found, startPos, endPos, value) where positions are byte indices
  var col = startCol
  let lineLen = line.len

  # Skip to start column
  if col >= lineLen:
    return (false, 0, 0, 0)

  # Skip non-digit characters (but stop at digit or minus sign before digit)
  while col < lineLen:
    if line[col] >= '0' and line[col] <= '9':
      break
    elif line[col] == '-' and col + 1 < lineLen and line[col + 1] >= '0' and
        line[col + 1] <= '9':
      break
    col += 1

  if col >= lineLen:
    return (false, 0, 0, 0)

  # Found start of number
  let startPos = col
  var numStr = ""

  # Handle optional minus sign
  if line[col] == '-':
    numStr.add('-')
    col += 1

  # Collect digits
  while col < lineLen and line[col] >= '0' and line[col] <= '9':
    numStr.add(line[col])
    col += 1

  # Parse the number
  try:
    let value = parseInt(numStr)
    return (true, startPos, col - 1, value)
  except ValueError:
    return (false, 0, 0, 0)

proc handleIncrementNumber(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Increment the number at or after cursor (Ctrl-A command)
  if ctx.cursor.line >= ctx.buffer.len:
    return err("Cursor out of bounds")

  let line = ctx.buffer.getLine(ctx.cursor.line)
  let byteCol = charToBytePos(line, ctx.cursor.column)

  # Find number at or after cursor position (byte space)
  let (found, startPos, endPos, value) = findNumberAtOrAfterColumn(line, byteCol)

  if not found:
    return err("No number found")

  # Increment the number
  let newValue = value + 1
  let newNumStr = $newValue

  # Replace the number in the line
  let newLine =
    line[0 ..< startPos] & newNumStr &
    (if endPos + 1 < line.len: line[endPos + 1 ..^ 1] else: "")

  # Update the buffer using transaction
  let txnResult = ctx.buffer.beginTransaction("Increment number")
  if txnResult.isErr:
    return err(txnResult.error)

  let lineIdx = ctx.cursor.line
  let delResult = ctx.buffer.deleteLine(lineIdx)
  if delResult.isErr:
    discard ctx.buffer.rollbackTransaction()
    return err(delResult.error)

  let insResult = ctx.buffer.insert(lineIdx, newLine)
  if insResult.isErr:
    discard ctx.buffer.rollbackTransaction()
    return err(insResult.error)

  let commitResult = ctx.buffer.commitTransaction()
  if commitResult.isErr:
    return err(commitResult.error)

  # Move cursor to start of the number (convert byte pos to char pos)
  ctx.cursor.column = byteToCharPos(newLine, startPos)

  return ok(())

proc handleDecrementNumber(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Decrement the number at or after cursor (Ctrl-X command)
  if ctx.cursor.line >= ctx.buffer.len:
    return err("Cursor out of bounds")

  let line = ctx.buffer.getLine(ctx.cursor.line)
  let byteCol = charToBytePos(line, ctx.cursor.column)

  # Find number at or after cursor position (byte space)
  let (found, startPos, endPos, value) = findNumberAtOrAfterColumn(line, byteCol)

  if not found:
    return err("No number found")

  # Decrement the number
  let newValue = value - 1
  let newNumStr = $newValue

  # Replace the number in the line
  let newLine =
    line[0 ..< startPos] & newNumStr &
    (if endPos + 1 < line.len: line[endPos + 1 ..^ 1] else: "")

  # Update the buffer using transaction
  let txnResult = ctx.buffer.beginTransaction("Decrement number")
  if txnResult.isErr:
    return err(txnResult.error)

  let lineIdx = ctx.cursor.line
  let delResult = ctx.buffer.deleteLine(lineIdx)
  if delResult.isErr:
    discard ctx.buffer.rollbackTransaction()
    return err(delResult.error)

  let insResult = ctx.buffer.insert(lineIdx, newLine)
  if insResult.isErr:
    discard ctx.buffer.rollbackTransaction()
    return err(insResult.error)

  let commitResult = ctx.buffer.commitTransaction()
  if commitResult.isErr:
    return err(commitResult.error)

  # Move cursor to start of the number (convert byte pos to char pos)
  ctx.cursor.column = byteToCharPos(newLine, startPos)

  return ok(())

proc jumpCursorToLine(ctx: CommandContext, line: int) =
  ## Record a jump, move the cursor to `line` at column 0, and refresh the
  ## viewport. Shared by commands that jump to non-adjacent lines (git change
  ## hunks, conflict blocks).
  recordJump(ctx.state)
  ctx.cursor = BufferPosition(line: line, column: 0)
  let lineNumOffset = calculateViewportOffset(
    ctx.buffer, ctx.state.display.showLineNumbers, ctx.state.display.showSidebar,
    ctx.state.display.scrollbar, ctx.state.display.scrollbarWidth,
  )
  ctx.motionController.viewportManager.updateViewport(
    CursorPosition(x: 0, y: line),
    ctx.buffer.len,
    ctx.state.display.showStatusLine,
    ctx.state.windowDisplay.viewportReservedLines,
    ctx.state.display.lineWrap,
    ctx.buffer,
    lineNumOffset,
    ctx.state.display.tabStop,
  )
  ctx.state.windowDisplay.needsFullRedraw = true

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
    bcMotionPageUp, "Page Up", "Scroll page up", Motion.PageUp, shouldRecordJump = true
  )
  registry.registerMotionCommand(
    bcMotionPageDown,
    "Page Down",
    "Scroll page down",
    Motion.PageDown,
    shouldRecordJump = true,
  )
  registry.registerMotionCommand(
    bcMotionHome, "Home", "Move to beginning of line", Motion.Home, false
  )
  registry.registerMotionCommand(
    bcMotionFirstNonBlank, "First Non-Blank", "Move to first non-whitespace character",
    Motion.FirstNonBlank, false,
  )
  registry.registerMotionCommand(
    bcMotionEnd, "End", "Move to end of line", Motion.End, false
  )
  registry.registerMotionCommand(
    bcMotionFirstLine,
    "First Line",
    "Move to first line",
    Motion.FirstLine,
    false,
    shouldRecordJump = true,
  )
  registry.registerMotionCommand(
    bcMotionLastLine,
    "Last Line",
    "Move to last line",
    Motion.LastLine,
    false,
    shouldRecordJump = true,
  )
  registry.registerMotionCommand(
    bcMotionViewportHigh,
    "Viewport High",
    "Move to top of viewport",
    Motion.ViewportHigh,
    true,
    shouldRecordJump = true,
  )
  registry.registerMotionCommand(
    bcMotionViewportMiddle,
    "Viewport Middle",
    "Move to middle of viewport",
    Motion.ViewportMiddle,
    false,
    shouldRecordJump = true,
  )
  registry.registerMotionCommand(
    bcMotionViewportLow,
    "Viewport Low",
    "Move to bottom of viewport",
    Motion.ViewportLow,
    true,
    shouldRecordJump = true,
  )
  registry.registerMotionCommand(
    bcMotionMatchBracket,
    "Match Bracket",
    "Jump to matching bracket (%)",
    Motion.MatchBracket,
    false,
    shouldRecordJump = true,
  )

  # Word motion commands
  registry.registerMotionCommand(
    bcMotionWord, "Move Word", "Move to start of next word", Motion.WordForward
  )
  registry.registerMotionCommand(
    bcMotionWordBack, "Move Word Back", "Move to start of previous word",
    Motion.WordBackward,
  )
  registry.registerMotionCommand(
    bcMotionWordEnd, "Move Word End", "Move to end of next word", Motion.WordEnd
  )

  # Scroll commands
  registry.register(
    builtin(bcScrollCursorTop),
    "Scroll Cursor Top",
    "Scroll viewport to place cursor line at top (zt)",
    handleScrollCursorTop,
    0,
    0,
  )

  registry.register(
    builtin(bcScrollCursorCenter),
    "Scroll Cursor Center",
    "Scroll viewport to place cursor line at center (z. or zz)",
    handleScrollCursorCenter,
    0,
    0,
  )

  registry.register(
    builtin(bcScrollCursorBottom),
    "Scroll Cursor Bottom",
    "Scroll viewport to place cursor line at bottom (zb)",
    handleScrollCursorBottom,
    0,
    0,
  )

  # Fold commands
  registry.register(
    builtin(bcFoldOpen),
    "Fold Open",
    "Open fold at cursor position (zo)",
    handleFoldOpen,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldClose),
    "Fold Close",
    "Close fold at cursor position (zc)",
    handleFoldClose,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldToggle),
    "Fold Toggle",
    "Toggle fold at cursor position (za)",
    handleFoldToggle,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldOpenAll),
    "Fold Open All",
    "Open all folds (zR)",
    handleFoldOpenAll,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldCloseAll),
    "Fold Close All",
    "Close all folds (zM)",
    handleFoldCloseAll,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldCreate),
    "Fold Create",
    "Create fold from visual selection (zf)",
    handleFoldCreate,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldDelete),
    "Fold Delete",
    "Delete fold at cursor position (zd)",
    handleFoldDelete,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldDeleteAll),
    "Fold Delete All",
    "Delete all folds (zD)",
    handleFoldDeleteAll,
    0,
    0,
  )

  # QuickRun command
  registry.register(
    builtin(bcQuickRun), "QuickRun", "Run current buffer (\\r)", handleQuickRun, 0, 0
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
      ctx.state.enterCommandOverlay()
      ok(()),
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

  registry.register(
    builtin(bcVisualYank),
    "Visual Yank",
    "Yank (copy) visual selection",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualYank(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualIndent),
    "Visual Indent",
    "Indent visual selection (> command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualIndent(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    builtin(bcVisualDedent),
    "Visual Dedent",
    "Dedent visual selection (< command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualDedent(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    builtin(bcVisualLowercase),
    "Visual Lowercase",
    "Convert visual selection to lowercase (u command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualLowercase(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualUppercase),
    "Visual Uppercase",
    "Convert visual selection to uppercase (U command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualUppercase(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualToggleCase),
    "Visual Toggle Case",
    "Toggle case of visual selection (~ command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualToggleCase(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualJoinLines),
    "Visual Join Lines",
    "Join lines in visual selection (J command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualJoinLines(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveHome),
    "Visual Move Home",
    "Move to beginning of line in visual mode (0 command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveHome(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveEnd),
    "Visual Move End",
    "Move to end of line in visual mode ($ command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveEnd(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveFirstNonBlank),
    "Visual Move First Non-Blank",
    "Move to first non-blank character in visual mode (^ command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveFirstNonBlank(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveFirstLine),
    "Visual Move First Line",
    "Move to first line in visual mode (gg command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualMoveFirstLine(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualMoveLastLine),
    "Visual Move Last Line",
    "Move to last line in visual mode (G command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 0)
      handleVisualMoveLastLine(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveWord),
    "Visual Move Word",
    "Move to next word in visual mode (w command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveWord(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveWordBack),
    "Visual Move Word Back",
    "Move to previous word in visual mode (b command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveWordBack(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveWordEnd),
    "Visual Move Word End",
    "Move to end of word in visual mode (e command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveWordEnd(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveWordEndBackward),
    "Visual Move Word End Backward",
    "Move to end of previous word in visual mode (ge command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveWordEndBackward(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveParagraphForward),
    "Visual Move Paragraph Forward",
    "Move to next paragraph in visual mode (} command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveParagraphForward(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualMoveParagraphBackward),
    "Visual Move Paragraph Backward",
    "Move to previous paragraph in visual mode ({ command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleVisualMoveParagraphBackward(ctx, count),
    0,
    1,
  )

  registry.register(
    builtin(bcVisualToInsertMode),
    "Visual to Insert Mode",
    "Switch from visual mode to insert mode (I command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualToInsertMode(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualBlockAppend),
    "Visual Block Append",
    "Append after visual block selection (A command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualBlockAppend(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualChange),
    "Visual Change",
    "Delete selection and enter insert mode (c command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualChange(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualSwapSelection),
    "Visual Swap Selection",
    "Swap cursor between start and end of selection (o command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualSwapSelection(ctx),
    0,
    0,
  )

  registry.register(
    builtin(bcVisualPaste),
    "Visual Paste",
    "Paste over selection (p/P command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleVisualPaste(ctx),
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
    custom("substitute.char"),
    "Substitute Character",
    "Substitute character(s) at cursor (s command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleSubstituteChar(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("substitute.line"),
    "Substitute Line",
    "Substitute line(s) (S command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleSubstituteLine(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("toggle.case"),
    "Toggle Case",
    "Toggle case of character(s) at cursor (~ command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleToggleCase(ctx, count),
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

  registry.register(
    custom("indent.line"),
    "Indent Line",
    "Indent current line (>> command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      indentLine(ctx.buffer, ctx.state, count)
      # Record this command for repeat (.)
      ctx.state.editState.lastEditCommand =
        some(LastEditCommand(kind: lecIndent, indentCount: count))
      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("dedent.line"),
    "Dedent Line",
    "Dedent current line (<< command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      dedentLine(ctx.buffer, ctx.state, count)
      # Record this command for repeat (.)
      ctx.state.editState.lastEditCommand =
        some(LastEditCommand(kind: lecDedent, dedentCount: count))
      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("autoindent.line"),
    "Auto Indent Line",
    "Auto indent current line to match previous line (== command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let currentLine = ctx.cursor.line

      # Can't auto indent first line or empty line
      if currentLine == 0:
        return Result[(), string].ok ()

      let lineContent = ctx.buffer.getLine(currentLine)
      if lineContent.len == 0:
        return Result[(), string].ok ()

      # Get previous line indent (count leading spaces)
      let prevLine = ctx.buffer.getLine(currentLine - 1)
      var prevIndent = 0
      for i in 0 ..< prevLine.len:
        if prevLine[i] == ' ':
          inc prevIndent
        else:
          break

      # Count current line's leading spaces
      var currentIndent = 0
      for i in 0 ..< lineContent.len:
        if lineContent[i] == ' ':
          inc currentIndent
        else:
          break

      # No change needed if indents are equal
      if prevIndent == currentIndent:
        return Result[(), string].ok ()

      # Create new line with correct indent
      var newContent = ""
      for i in 0 ..< prevIndent:
        newContent.add(' ')

      # Add non-whitespace content from current line
      for i in currentIndent ..< lineContent.len:
        newContent.add(lineContent[i])

      # Begin transaction
      let txnResult = ctx.buffer.beginTransaction("auto indent line")
      if txnResult.isErr:
        return err(txnResult.error)

      # Delete current line content and insert new
      let lineStart = BufferPosition(line: currentLine, column: 0)
      let lineEnd = BufferPosition(line: currentLine, column: lineContent.charLen - 1)

      let delResult = ctx.buffer.deleteRange(lineStart, lineEnd)
      if delResult.isErr:
        discard ctx.buffer.rollbackTransaction()
        return err(delResult.error)

      if newContent.len > 0:
        let insResult = ctx.buffer.insertText(lineStart, newContent)
        if insResult.isErr:
          discard ctx.buffer.rollbackTransaction()
          return err(insResult.error)

      let commitResult = ctx.buffer.commitTransaction()
      if commitResult.isErr:
        return err(commitResult.error)

      # Move cursor to first non-blank character
      ctx.cursor.column = prevIndent
      ctx.state.windowDisplay.needsFullRedraw = true

      return Result[(), string].ok (),
    0,
    0, # No arguments
  )

  registry.register(
    custom("join.lines"),
    "Join Lines",
    "Join current line with next line(s) (J command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleJoinLines(ctx, count),
    0,
    1, # Accept optional count argument
  )

  registry.register(
    custom("show.char.info"),
    "Show Character Info",
    "Show ASCII/Unicode value of character under cursor (ga command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      handleShowCharInfo(ctx),
    0,
    0, # No arguments
  )

  # Note: change.word is now handled by operator+motion system (c+w)
  # The operator.change handler sets pendingOperator, then Motion.WordForward
  # is executed, and executeOperatorOnRange is called automatically

  # Undo/Redo commands
  proc clampCursorToBuffer(ctx: CommandContext) =
    ## Clamp cursor position to valid buffer range
    if ctx.buffer.len == 0:
      ctx.cursor = BufferPosition(line: 0, column: 0)
    else:
      if ctx.cursor.line >= ctx.buffer.len:
        ctx.cursor.line = ctx.buffer.len - 1
      let line = ctx.buffer.getLine(ctx.cursor.line)
      let maxCol = max(0, line.charLen - 1)
      if ctx.cursor.column > maxCol:
        ctx.cursor.column = maxCol

  registry.register(
    builtin(bcEditUndo),
    "Undo",
    "Undo the last change(s)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      var lastCursorPos: Option[BufferPosition] = none(BufferPosition)
      for i in 1 .. count:
        let r = ctx.buffer.undo()
        if r.isErr:
          if i == 1:
            return err(r.error)
          else:
            break # Stop if we can't undo anymore
        lastCursorPos = some(r.value)

      if lastCursorPos.isSome:
        ctx.cursor = lastCursorPos.get
        clampCursorToBuffer(ctx)

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
      var lastCursorPos: Option[BufferPosition] = none(BufferPosition)
      for i in 1 .. count:
        let r = ctx.buffer.redo()
        if r.isErr:
          if i == 1:
            return err(r.error)
          else:
            break # Stop if we can't redo anymore
        lastCursorPos = some(r.value)

      if lastCursorPos.isSome:
        ctx.cursor = lastCursorPos.get
        clampCursorToBuffer(ctx)

      return Result[(), string].ok (),
    0,
    1, # Accept optional count argument
  )

  # Increment/Decrement number commands
  registry.register(
    builtin(bcEditIncrementNumber),
    "Increment Number",
    "Increment the number at or after cursor (Ctrl-A)",
    handleIncrementNumber,
    0,
    0,
  )

  registry.register(
    builtin(bcEditDecrementNumber),
    "Decrement Number",
    "Decrement the number at or after cursor (Ctrl-X)",
    handleDecrementNumber,
    0,
    0,
  )

  # Repeat last change command (.)
  registry.register(
    custom("edit.repeat"),
    "Repeat Last Change",
    "Repeat the last change command (. command)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Check if we have a last edit command
      if ctx.state.editState.lastEditCommand.isNone:
        return err("No previous change to repeat")

      let lastCmd = ctx.state.editState.lastEditCommand.get

      case lastCmd.kind
      of lecOperatorMotion:
        # Repeat operator+motion command (e.g., dw, c2w, y$)
        # Create a pending operator
        ctx.state.editState.pendingOperator = some(
          PendingOperator(
            operatorType: lastCmd.operator,
            operatorCount: lastCmd.operatorCount,
            startPos: ctx.cursor,
          )
        )
        # Save viewport position for restoration after operator
        ctx.state.windowDisplay.savedViewportTopLine =
          ctx.motionController.viewportManager.viewport.topLine

        # Execute the motion with combined count (motionCount * operatorCount)
        let effectiveCount = lastCmd.motionCount * lastCmd.operatorCount
        let motionCmd = MotionCommand(motion: lastCmd.motion, count: effectiveCount)
        let r = ctx.motionController.executeMotion(
          motionCmd, ctx.cursor, updateViewport = false
        )
        if r.isErr:
          ctx.state.editState.pendingOperator = none(PendingOperator)
          return err(r.error)

        # Calculate the range
        let range =
          calculateOperatorRange(ctx.buffer, ctx.cursor, r.value, lastCmd.motion)

        # Execute the operator on the range
        let op = ctx.state.editState.pendingOperator.get
        ctx.state.editState.pendingOperator = none(PendingOperator)
        let execResult =
          executeOperatorOnRange(ctx, op.operatorType, range, op.operatorCount)
        if execResult.isErr:
          return err(execResult.error)

        # Note: We don't update lastEditCommand here because we're repeating the same command
        return ok(())
      of lecDeleteChar:
        # Repeat character deletion (x or X)
        if lastCmd.deleteForward:
          # x command - delete forward
          return handleDeleteChar(ctx, lastCmd.deleteCount)
        else:
          # X command - delete backward
          return handleDeleteCharBefore(ctx, lastCmd.deleteCount)
      of lecDeleteLine:
        # Repeat line deletion (dd)
        return handleDeleteLine(ctx, lastCmd.deleteLineCount)
      of lecPaste:
        # Repeat paste operation (p or P)
        if lastCmd.pasteBefore:
          # P command - paste before
          return handlePasteBefore(ctx, lastCmd.pasteCount)
        else:
          # p command - paste after
          return handlePasteAfter(ctx, lastCmd.pasteCount)
      of lecToggleCase:
        # Repeat toggle case (~)
        return handleToggleCase(ctx, lastCmd.toggleCaseCount)
      of lecSubstitute:
        # Repeat substitute (s/S/cc)
        # Delete + insert the recorded text without entering Insert mode
        case lastCmd.substituteKind
        of skChar:
          # Repeat s command - delete characters then insert text
          let lineContent = ctx.buffer.getLine(ctx.cursor.line)

          # Check if we're at or past the end of the line
          if ctx.cursor.column >= lineContent.charLen:
            # At end of line, just insert text
            let insertResult = ctx.buffer.insertText(ctx.cursor, lastCmd.substituteText)
            if insertResult.isErr:
              return err("Failed to insert text: " & insertResult.error)
          else:
            # Delete characters
            let charsAvailable = lineContent.charLen - ctx.cursor.column
            let charsToDelete = min(lastCmd.substituteCount, charsAvailable)

            # Begin transaction
            let txnResult =
              ctx.buffer.beginTransaction("substitute " & $charsToDelete & " char(s)")
            if txnResult.isErr:
              return err(txnResult.error)

            # Delete the characters
            for i in 0 ..< charsToDelete:
              let delResult = ctx.buffer.deleteRange(ctx.cursor, ctx.cursor)
              if delResult.isErr:
                discard ctx.buffer.rollbackTransaction()
                return err(delResult.error)

            # Insert the recorded text
            let insertResult = ctx.buffer.insertText(ctx.cursor, lastCmd.substituteText)
            if insertResult.isErr:
              discard ctx.buffer.rollbackTransaction()
              return err("Failed to insert text: " & insertResult.error)

            # Commit transaction
            let commitResult = ctx.buffer.commitTransaction()
            if commitResult.isErr:
              return err(commitResult.error)

          # Move cursor to last inserted character (Vim behavior)
          let numNewlines = lastCmd.substituteText.count('\n')
          if numNewlines > 0:
            ctx.cursor.line += numNewlines
            let lines = lastCmd.substituteText.split('\n')
            let lastLine = lines[^1]
            # Position cursor on last character (or at column 0 if empty)
            ctx.cursor.column = max(0, lastLine.charLen - 1)
          else:
            # Single line - move cursor to last inserted character
            ctx.cursor.column += lastCmd.substituteText.charLen
            if ctx.cursor.column > 0:
              ctx.cursor.column -= 1 # Stay on last inserted character

          ctx.state.windowDisplay.needsFullRedraw = true
          return ok(())
        of skLine:
          # Repeat S or cc command - delete lines then insert text
          let startLine = ctx.cursor.line
          let endLine = min(startLine + lastCmd.substituteCount - 1, ctx.buffer.len - 1)

          # Begin transaction
          let transactionResult = ctx.buffer.beginTransaction("Substitute line")
          if transactionResult.isErr:
            return err("Failed to begin transaction: " & transactionResult.error)

          # Delete all but first line
          for i in 0 ..< (endLine - startLine):
            if startLine + 1 < ctx.buffer.len:
              let deleteResult = ctx.buffer.deleteLine(startLine + 1)
              if deleteResult.isErr:
                discard ctx.buffer.rollbackTransaction()
                return err("Failed to delete line: " & deleteResult.error)

          # Clear the first line
          if startLine < ctx.buffer.len:
            let line = ctx.buffer.getLine(startLine)
            for i in 0 ..< line.charLen:
              let deleteResult = ctx.buffer.deleteRange(
                BufferPosition(line: startLine, column: 0),
                BufferPosition(line: startLine, column: 0),
              )
              if deleteResult.isErr:
                discard ctx.buffer.rollbackTransaction()
                return err("Failed to clear line: " & deleteResult.error)

          # Insert the recorded text at the beginning of the line
          let insertResult = ctx.buffer.insertText(
            BufferPosition(line: startLine, column: 0), lastCmd.substituteText
          )
          if insertResult.isErr:
            discard ctx.buffer.rollbackTransaction()
            return err("Failed to insert text: " & insertResult.error)

          # Commit transaction
          let commitResult = ctx.buffer.commitTransaction()
          if commitResult.isErr:
            return err(commitResult.error)

          # Move cursor to last inserted character (Vim behavior)
          let numNewlines = lastCmd.substituteText.count('\n')
          if numNewlines > 0:
            ctx.cursor.line = startLine + numNewlines
            let lines = lastCmd.substituteText.split('\n')
            let lastLine = lines[^1]
            # Position cursor on last character (or at column 0 if empty)
            ctx.cursor.column = max(0, lastLine.charLen - 1)
          else:
            ctx.cursor.line = startLine
            # Position cursor on last character (or at column 0 if empty)
            ctx.cursor.column = max(0, lastCmd.substituteText.charLen - 1)

          ctx.state.windowDisplay.needsFullRedraw = true
          return ok(())
      of lecInsertText:
        # Repeat insert text
        let insertResult = ctx.buffer.insertText(ctx.cursor, lastCmd.insertedText)
        if insertResult.isErr:
          return err("Failed to repeat insert: " & insertResult.error)

        # Move cursor to last inserted character (Vim behavior: cursor on last char, not after)
        # Count newlines to handle multi-line insertion
        let numNewlines = lastCmd.insertedText.count('\n')
        if numNewlines > 0:
          # Multi-line insertion - move to last line
          ctx.cursor.line += numNewlines
          let lines = lastCmd.insertedText.split('\n')
          let lastLine = lines[^1]
          # Position cursor on last character (or at column 0 if last line is empty)
          ctx.cursor.column = max(0, lastLine.charLen - 1)
        else:
          # Single line insertion - move cursor to last inserted character
          if lastCmd.insertedText.len > 0:
            ctx.cursor.column += lastCmd.insertedText.charLen
            # Move back one to be on the last character, not after it
            if ctx.cursor.column > 0:
              ctx.cursor.column -= 1
          # If empty string, cursor stays at current position

        ctx.state.windowDisplay.needsFullRedraw = true
        return ok(())
      of lecReplaceChar:
        # Repeat replace character (r command)
        let lineContent = ctx.buffer.getLine(ctx.cursor.line)

        # Check if we're at or past the end of the line
        if ctx.cursor.column >= lineContent.charLen:
          return err("Nothing to replace")

        # Calculate how many characters we can actually replace
        let charsAvailable = lineContent.charLen - ctx.cursor.column
        let charsToReplace = min(lastCmd.replaceCount, charsAvailable)

        # Begin transaction
        let txnResult =
          ctx.buffer.beginTransaction("replace " & $charsToReplace & " char(s)")
        if txnResult.isErr:
          return err(txnResult.error)

        # Replace each character
        for i in 0 ..< charsToReplace:
          let pos = BufferPosition(line: ctx.cursor.line, column: ctx.cursor.column + i)
          let delResult = ctx.buffer.deleteRange(pos, pos)
          if delResult.isErr:
            discard ctx.buffer.rollbackTransaction()
            return err(delResult.error)

          let insResult = ctx.buffer.insertText(pos, lastCmd.replaceChar)
          if insResult.isErr:
            discard ctx.buffer.rollbackTransaction()
            return err(insResult.error)

        # Commit transaction
        let commitResult = ctx.buffer.commitTransaction()
        if commitResult.isErr:
          return err(commitResult.error)

        # Move cursor to the last replaced character
        ctx.cursor.column += charsToReplace - 1
        ctx.state.windowDisplay.needsFullRedraw = true
        return ok(())
      of lecJoinLines:
        # Repeat join lines (J command)
        return handleJoinLines(ctx, lastCmd.joinLinesCount)
      of lecIndent:
        # Repeat indent (>>)
        indentLine(ctx.buffer, ctx.state, lastCmd.indentCount)
        return ok(())
      of lecDedent:
        # Repeat dedent (<<)
        dedentLine(ctx.buffer, ctx.state, lastCmd.dedentCount)
        return ok(())
      of lecChangeLine:
        # Note: This case should not be reached anymore as cc now uses lecSubstitute
        # Kept for backwards compatibility if old state exists
        return err("Repeating cc command is not yet implemented (use latest version)"),
    0,
    0,
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

  registry.register(
    custom("operator.indent"),
    "Indent Operator",
    "Indent operator - waits for motion (>w, >$, etc.) or >> for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorIndent(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.outdent"),
    "Outdent Operator",
    "Outdent operator - waits for motion (<w, <$, etc.) or << for line",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorOutdent(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.lowercase"),
    "Lowercase Operator",
    "Lowercase operator - waits for motion (guw, gu$, etc.)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorLowerCase(ctx, count),
    0,
    1, # Accept optional count
  )

  registry.register(
    custom("operator.uppercase"),
    "Uppercase Operator",
    "Uppercase operator - waits for motion (gUw, gU$, etc.)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let count = parseCount(args, default = 1)
      handleOperatorUpperCase(ctx, count),
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
      let startPos = ctx.cursor
      let line = ctx.buffer.getLine(startPos.line)
      let lineLen = line.charLen

      # Empty line or cursor at/past end: nothing to delete
      if lineLen == 0 or startPos.column >= lineLen:
        return ok(())

      # End at last character (same as d$ / Motion.End)
      let endPos = BufferPosition(line: startPos.line, column: lineLen - 1)

      let range = OperatorRange(start: startPos, endPos: endPos, isLinewise: false)

      # Execute delete operation
      let r = executeOperatorOnRange(ctx, OpDelete, range, 1)
      if r.isOk:
        # Record this command for repeat (.)
        ctx.state.editState.lastEditCommand = some(
          LastEditCommand(
            kind: lecOperatorMotion,
            operator: OpDelete,
            motion: End,
            motionCount: 1,
            operatorCount: 1,
          )
        )
      return r,
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
      let startPos = ctx.cursor
      let line = ctx.buffer.getLine(startPos.line)
      let lineLen = line.charLen

      # Empty line or cursor at/past end: just enter insert mode without deleting
      if lineLen == 0 or startPos.column >= lineLen:
        ctx.state.mode = EditorMode.Insert
        return ok(())

      # End at last character (same as c$ / Motion.End)
      let endPos = BufferPosition(line: startPos.line, column: lineLen - 1)

      let range = OperatorRange(start: startPos, endPos: endPos, isLinewise: false)

      # Execute change operation
      let r = executeOperatorOnRange(ctx, OpChange, range, 1)
      if r.isOk:
        # Record this command for repeat (.)
        ctx.state.editState.lastEditCommand = some(
          LastEditCommand(
            kind: lecOperatorMotion,
            operator: OpChange,
            motion: End,
            motionCount: 1,
            operatorCount: 1,
          )
        )
      return r,
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
        if ctx.state.editState.pendingTextObject.isNone:
          # No text object modifier - ignore this key press
          # (In the future, we should fallback to the key's normal function)
          return ok(())

        let textObj = ctx.state.editState.pendingTextObject.get
        ctx.state.editState.pendingTextObject = none(PendingTextObject)

        # Calculate text object range
        let rangeResult =
          calculateTextObjectRange(ctx.buffer, ctx.cursor, kind, textObj.modifier)
        if rangeResult.isErr:
          return err(rangeResult.error)

        var toRange = rangeResult.value

        # Count extension for word/WORD text objects (e.g., d2iw, d3aw)
        # textObj.operatorCount already contains the count from the pending operator
        let effectiveCount = max(textObj.operatorCount, 1)

        if effectiveCount > 1 and kind in {toWord, toWideWord}:
          for i in 1 ..< effectiveCount:
            # Move cursor past current range end
            var nextLine = toRange.endPos.line
            var nextCol = toRange.endPos.column + 1
            let lineRunes = ctx.buffer.getLine(nextLine).toRunes()
            if nextCol >= lineRunes.len:
              # Move to next line
              nextLine.inc
              nextCol = 0
              if nextLine >= ctx.buffer.len:
                break

            # Use inner for intermediate words, original modifier for last
            let modifier = if i == effectiveCount - 1: textObj.modifier else: tomInner

            let nextCursor = BufferPosition(line: nextLine, column: nextCol)
            let nextResult =
              calculateTextObjectRange(ctx.buffer, nextCursor, kind, modifier)
            if nextResult.isErr:
              break
            toRange.endPos = nextResult.value.endPos

        # Convert TextObjectRange to OperatorRange
        let opRange = OperatorRange(
          start: toRange.start, endPos: toRange.endPos, isLinewise: toRange.isLinewise
        )

        # Check if we have a pending operator
        if ctx.state.editState.pendingOperator.isSome:
          let op = ctx.state.editState.pendingOperator.get
          ctx.state.editState.pendingOperator = none(PendingOperator)

          # Execute operator on text object
          return executeOperatorOnRange(ctx, op.operatorType, opRange, op.operatorCount)
        elif isVisualAllMode(ctx.state.mode):
          # In Visual mode - update selection to text object range
          ctx.state.visualSelection.start = toRange.start
          ctx.state.visualSelection.current = toRange.endPos
          ctx.state.visualSelection.active = true
          ctx.cursor = toRange.endPos
          ctx.state.windowDisplay.needsFullRedraw = true
          return ok(())
        else:
          return err("Text objects require an operator or Visual mode"),
      0,
      0,
    )

  # Register text object kinds
  registerTextObjectKind(
    registry, "textobject.word", "Word Text Object", "Word text object (iw/aw)", toWord
  )
  registerTextObjectKind(
    registry, "textobject.wideword", "WORD Text Object",
    "WORD text object - space-separated (iW/aW)", toWideWord,
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
  registerTextObjectKind(
    registry, "textobject.angle", "Angle Bracket Text Object", "Angle brackets (i</a<)",
    toAngleBracket,
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
    let shouldIgnoreCase = shouldIgnoreCase(
      searchText, ctx.state.search.ignorecase, ctx.state.search.smartcase
    )

    # Validate regex
    if compileSearchRegex(searchText, shouldIgnoreCase).isNone:
      ctx.state.statusMessage = "Invalid regex: " & searchText
      return err("Invalid regex")

    # Execute the search (findNext or findPrev)
    let searchResult = searchProc(ctx.buffer, searchText, ctx.cursor, shouldIgnoreCase)

    if searchResult.isSome:
      let newPos = searchResult.get
      ctx.cursor = newPos

      # Update viewport to follow cursor
      let
        lineCount = ctx.buffer.len
        cursorPos = CursorPosition(x: newPos.column, y: newPos.line)
        lineNumOffset = calculateViewportOffset(
          ctx.buffer, ctx.state.display.showLineNumbers, ctx.state.display.showSidebar,
          ctx.state.display.scrollbar, ctx.state.display.scrollbarWidth,
        )

      ctx.motionController.viewportManager.updateViewport(
        cursorPos, lineCount, ctx.state.display.showStatusLine,
        ctx.state.windowDisplay.viewportReservedLines, ctx.state.display.lineWrap,
        ctx.buffer, lineNumOffset, ctx.state.display.tabStop,
      )

      ctx.state.statusMessage = "Found: " & searchText
      ctx.state.windowDisplay.needsFullRedraw = true
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
      if ctx.state.search.lastText.len == 0:
        return err("No previous search")

      # Record jump before searching
      recordJump(ctx.state)

      # Re-enable highlight when using n/N
      ctx.state.search.hlsearchTempDisabled = false

      return executeSearch(ctx, ctx.state.search.lastText, findNext),
    0,
    0,
  )

  registry.register(
    custom("search.prev"),
    "Search Previous",
    "Find previous occurrence of last search",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      if ctx.state.search.lastText.len == 0:
        return err("No previous search")

      # Record jump before searching
      recordJump(ctx.state)

      # Re-enable highlight when using n/N
      ctx.state.search.hlsearchTempDisabled = false

      return executeSearch(ctx, ctx.state.search.lastText, findPrev),
    0,
    0,
  )

  # Git change navigation commands
  registry.register(
    custom("navigate.git.next"),
    "Next Git Change",
    "Jump to next git change hunk",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let nextLine = ctx.buffer.findNextGitChange(ctx.cursor.line)
      if nextLine.isSome:
        jumpCursorToLine(ctx, nextLine.get)
        return Result[(), string].ok ()
      else:
        ctx.state.statusMessage = "No more git changes"
        return err("No more git changes"),
    0,
    0,
  )

  registry.register(
    custom("navigate.git.prev"),
    "Previous Git Change",
    "Jump to previous git change hunk",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let prevLine = ctx.buffer.findPrevGitChange(ctx.cursor.line)
      if prevLine.isSome:
        jumpCursorToLine(ctx, prevLine.get)
        return Result[(), string].ok ()
      else:
        ctx.state.statusMessage = "No more git changes"
        return err("No more git changes"),
    0,
    0,
  )

  # Git merge conflict block navigation commands
  registry.register(
    custom("navigate.conflict.next"),
    "Next Git Conflict",
    "Jump to next git merge conflict block",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let nxt = ctx.buffer.findNextConflict(ctx.cursor.line)
      if nxt.isSome:
        jumpCursorToLine(ctx, nxt.get.startLine)
        return Result[(), string].ok ()
      else:
        ctx.state.statusMessage = "No more git conflicts"
        return err("No more git conflicts"),
    0,
    0,
  )

  registry.register(
    custom("navigate.conflict.prev"),
    "Previous Git Conflict",
    "Jump to previous git merge conflict block",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let prv = ctx.buffer.findPrevConflict(ctx.cursor.line)
      if prv.isSome:
        jumpCursorToLine(ctx, prv.get.startLine)
        return Result[(), string].ok ()
      else:
        ctx.state.statusMessage = "No more git conflicts"
        return err("No more git conflicts"),
    0,
    0,
  )

  # Helper proc to get the word under cursor
  # Helper type for word bounds
  type WordInfo = object
    word: string
    startCol: int
    endCol: int

  proc getWordInfoUnderCursor(
      buffer: TextBuffer, cursor: BufferPosition
  ): Option[WordInfo] =
    if cursor.line < 0 or cursor.line >= buffer.len:
      return none(WordInfo)

    let line = buffer.getLine(cursor.line)
    if line.len == 0 or cursor.column >= line.charLen:
      return none(WordInfo)

    let runes = line.toRunes()
    if cursor.column >= runes.len:
      return none(WordInfo)

    # Check if cursor is on a word character
    let charAtCursor = $runes[cursor.column]
    if not (charAtCursor[0].isAlphaNumeric or charAtCursor[0] == '_'):
      return none(WordInfo)

    # Find word start
    var startCol = cursor.column
    while startCol > 0:
      let ch = $runes[startCol - 1]
      if not (ch[0].isAlphaNumeric or ch[0] == '_'):
        break
      startCol.dec

    # Find word end
    var endCol = cursor.column
    while endCol < runes.len:
      let ch = $runes[endCol]
      if not (ch[0].isAlphaNumeric or ch[0] == '_'):
        break
      endCol.inc

    # Extract word
    var word = ""
    for i in startCol ..< endCol:
      word.add($runes[i])

    return some(WordInfo(word: word, startCol: startCol, endCol: endCol))

  # Helper proc to check if a rune is a word character
  proc isWordChar(r: Rune): bool =
    let code = int(r)
    r.isAlpha or (code >= ord('0') and code <= ord('9')) or r == Rune('_')

  proc isWholeWordMatch(buffer: TextBuffer, pos: BufferPosition, wordLen: int): bool =
    ## Helper proc to check if a match is at word boundary
    if pos.line < 0 or pos.line >= buffer.len:
      return false

    let line = buffer.getLine(pos.line)
    let runes = line.toRunes()

    # Check bounds
    if pos.column < 0 or pos.column >= runes.len:
      return false

    # Check character before match (must not be word char or at start)
    if pos.column > 0:
      if isWordChar(runes[pos.column - 1]):
        return false

    # Check character after match (must not be word char or at end)
    let endCol = pos.column + wordLen
    if endCol < runes.len:
      if isWordChar(runes[endCol]):
        return false

    return true

  proc findMatchingBracketAtCursor(
      buffer: TextBuffer, cursor: BufferPosition
  ): Result[BufferPosition, string] =
    ## Helper proc to find matching bracket at cursor
    if cursor.line < 0 or cursor.line >= buffer.len:
      return err("Invalid cursor position")

    let line = buffer.getLine(cursor.line)
    if line.len == 0 or cursor.column >= line.charLen:
      return err("No bracket at cursor")

    let runes = line.toRunes()
    if cursor.column >= runes.len:
      return err("No bracket at cursor")

    let charAtCursor = ($runes[cursor.column])[0]

    # Define bracket pairs
    const openBrackets = ['(', '[', '{', '<']
    const closeBrackets = [')', ']', '}', '>']

    var openChar, closeChar: char
    var searchForward = false

    # Check if cursor is on a bracket
    if charAtCursor in openBrackets:
      openChar = charAtCursor
      closeChar = closeBrackets[openBrackets.find(charAtCursor)]
      searchForward = true
    elif charAtCursor in closeBrackets:
      closeChar = charAtCursor
      openChar = openBrackets[closeBrackets.find(charAtCursor)]
      searchForward = false
    else:
      return err("No bracket at cursor")

    if searchForward:
      # Search forward for closing bracket
      var depth = 1
      var col = cursor.column + 1
      while col < runes.len:
        let ch = ($runes[col])[0]
        if ch == openChar:
          depth.inc
        elif ch == closeChar:
          depth.dec
          if depth == 0:
            return ok(BufferPosition(line: cursor.line, column: col))
        col.inc
    else:
      # Search backward for opening bracket
      var depth = 1
      var col = cursor.column - 1
      while col >= 0:
        let ch = ($runes[col])[0]
        if ch == closeChar:
          depth.inc
        elif ch == openChar:
          depth.dec
          if depth == 0:
            return ok(BufferPosition(line: cursor.line, column: col))
        col.dec

    return err("No matching bracket found")

  # % - Jump to matching bracket
  registry.register(
    custom("motion.match.bracket"),
    "Match Bracket",
    "Jump to matching bracket (%)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let matchResult = findMatchingBracketAtCursor(ctx.buffer, ctx.cursor)
      if matchResult.isErr:
        return err(matchResult.error)

      # Record jump before moving to matching bracket
      recordJump(ctx.state)

      ctx.cursor = matchResult.value
      return Result[(), string].ok (),
    0,
    0,
  )

  # * - Search word under cursor forward
  registry.register(
    custom("search.word.forward"),
    "Search Word Forward",
    "Search for word under cursor forward (*)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let wordInfo = getWordInfoUnderCursor(ctx.buffer, ctx.cursor)
      if wordInfo.isNone:
        return err("No word under cursor")

      let info = wordInfo.get
      let wordLen = info.word.runeLen

      # Record jump before searching
      recordJump(ctx.state)

      # Update last search text and set whole word mode
      ctx.state.search.lastText = info.word
      ctx.state.search.hlsearchTempDisabled = false
      ctx.state.search.wholeWord = true

      # Remember original word position to skip it after wrap-around
      let originalWordPos = BufferPosition(line: ctx.cursor.line, column: info.startCol)

      # Search from word end position to skip current word
      var searchPos = BufferPosition(line: ctx.cursor.line, column: info.endCol)
      let ignoreCase = shouldIgnoreCase(
        info.word, ctx.state.search.ignorecase, ctx.state.search.smartcase
      )
      var wrapped = false

      # Loop until we find a whole word match
      while true:
        let searchResult = findNext(ctx.buffer, info.word, searchPos, ignoreCase)
        if searchResult.isNone:
          ctx.state.statusMessage = "Pattern not found: " & info.word
          return err("Pattern not found")

        let newPos = searchResult.get

        # Check if we've wrapped back to start
        if newPos.line < searchPos.line or
            (newPos.line == searchPos.line and newPos.column < searchPos.column):
          wrapped = true

        # Skip if this is the original word position (after wrap-around)
        if wrapped and newPos.line == originalWordPos.line and
            newPos.column == originalWordPos.column:
          ctx.state.statusMessage = "Pattern not found: " & info.word
          return err("Pattern not found")

        # Check if this is a whole word match
        if isWholeWordMatch(ctx.buffer, newPos, wordLen):
          ctx.cursor = newPos

          # Update viewport to follow cursor
          let
            lineCount = ctx.buffer.len
            cursorPos = CursorPosition(x: newPos.column, y: newPos.line)
            lineNumOffset = calculateViewportOffset(
              ctx.buffer, ctx.state.display.showLineNumbers,
              ctx.state.display.showSidebar,
            )

          ctx.motionController.viewportManager.updateViewport(
            cursorPos, lineCount, ctx.state.display.showStatusLine,
            ctx.state.windowDisplay.viewportReservedLines, ctx.state.display.lineWrap,
            ctx.buffer, lineNumOffset, ctx.state.display.tabStop,
          )

          ctx.state.statusMessage = "Found: " & info.word
          ctx.state.windowDisplay.needsFullRedraw = true
          return Result[(), string].ok ()

        # Continue searching from after this match
        searchPos = BufferPosition(line: newPos.line, column: newPos.column + 1)

      # No whole word match found
      ctx.state.statusMessage = "Pattern not found: " & info.word
      return err("Pattern not found"),
    0,
    0,
  )

  # # - Search word under cursor backward
  registry.register(
    custom("search.word.backward"),
    "Search Word Backward",
    "Search for word under cursor backward (#)",
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      let wordInfo = getWordInfoUnderCursor(ctx.buffer, ctx.cursor)
      if wordInfo.isNone:
        return err("No word under cursor")

      let info = wordInfo.get
      let wordLen = info.word.runeLen

      # Record jump before searching
      recordJump(ctx.state)

      # Update last search text and set whole word mode
      ctx.state.search.lastText = info.word
      ctx.state.search.hlsearchTempDisabled = false
      ctx.state.search.wholeWord = true

      # Remember original word position to skip it after wrap-around
      let originalWordPos = BufferPosition(line: ctx.cursor.line, column: info.startCol)

      # Search from word start position to skip current word
      var searchPos = BufferPosition(line: ctx.cursor.line, column: info.startCol)
      let ignoreCase = shouldIgnoreCase(
        info.word, ctx.state.search.ignorecase, ctx.state.search.smartcase
      )
      var wrapped = false

      # Loop until we find a whole word match
      while true:
        let searchResult = findPrev(ctx.buffer, info.word, searchPos, ignoreCase)
        if searchResult.isNone:
          ctx.state.statusMessage = "Pattern not found: " & info.word
          return err("Pattern not found")

        let newPos = searchResult.get

        # Check if we've wrapped back to start
        if newPos.line > searchPos.line or
            (newPos.line == searchPos.line and newPos.column > searchPos.column):
          wrapped = true

        # Skip if this is the original word position (after wrap-around)
        if wrapped and newPos.line == originalWordPos.line and
            newPos.column == originalWordPos.column:
          ctx.state.statusMessage = "Pattern not found: " & info.word
          return err("Pattern not found")

        # Check if this is a whole word match
        if isWholeWordMatch(ctx.buffer, newPos, wordLen):
          ctx.cursor = newPos

          # Update viewport to follow cursor
          let
            lineCount = ctx.buffer.len
            cursorPos = CursorPosition(x: newPos.column, y: newPos.line)
            lineNumOffset = calculateViewportOffset(
              ctx.buffer, ctx.state.display.showLineNumbers,
              ctx.state.display.showSidebar,
            )

          ctx.motionController.viewportManager.updateViewport(
            cursorPos, lineCount, ctx.state.display.showStatusLine,
            ctx.state.windowDisplay.viewportReservedLines, ctx.state.display.lineWrap,
            ctx.buffer, lineNumOffset, ctx.state.display.tabStop,
          )

          ctx.state.statusMessage = "Found: " & info.word
          ctx.state.windowDisplay.needsFullRedraw = true
          return Result[(), string].ok ()

        # Continue searching from before this match
        searchPos = BufferPosition(line: newPos.line, column: newPos.column)

      # No whole word match found
      ctx.state.statusMessage = "Pattern not found: " & info.word
      return err("Pattern not found"),
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
