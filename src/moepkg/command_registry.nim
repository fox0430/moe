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

## Command registry and execution system (facade).
##
## Re-exports the public API from command_registry/* sub-modules and owns the
## central key-binding dispatcher (executeCommand) and the thin
## registerBuiltinCommands wrapper that delegates to per-category registrars.

import std/options
from std/strutils import repeat

import pkg/results

import types, motion, key_bindings, modes, logger, visual_selection, wanted_column
import buffer/[core, edit, undo]

import command_handlers/visual_commands

import
  command_registry/[
    core, operator_engine, operator_driver, clipboard, motion_scroll, visual, edit,
    misc, macro_record,
  ]
export
  core, operator_engine, operator_driver, clipboard, motion_scroll, visual, edit, misc,
  macro_record

const EditCommandIds = [
  "delete.char", "delete.char.before", "delete.line", "delete.word",
  "operator.delete.to.end", "operator.change.to.end", "paste.after", "paste.before",
  "paste.after.end", "paste.before.end", "edit.paste", "join.lines", "substitute.char",
  "substitute.line", "toggle.case", "operator.delete", "operator.change",
  "operator.indent", "operator.outdent", "operator.lowercase", "operator.uppercase",
  "autoindent.line", "edit.increment", "edit.decrement", "edit.repeat",
]
  ## Built-in command ids (dotted form, as carried by Command.commandId) that
  ## modify the buffer at the cursor, used to classify a command for the
  ## read-only gate. The `r` replace command is handled separately via its
  ## ctOperatorPending operatorType (EditOperatorTypes).
  ##
  ## NOTE: when adding a new buffer-modifying command, add its id here too, or
  ## it will bypass the read-only gate. A guard test ("read-only gate allowlists
  ## stay in sync" in test_command_registry_integration) asserts every id below
  ## is a real registered command, so renames/removals fail loudly — but it
  ## cannot catch a *missing* addition.

const EditOperatorTypes = ["replace"]
  ## ctOperatorPending operatorTypes (see Command.operatorType) that modify the
  ## buffer at the cursor — currently just `r`. Kept as a named const, like
  ## EditCommandIds, so the same guard test can assert each value is a real
  ## registered operatorType: renaming the operatorType in the dispatch below
  ## without updating this list then fails loudly instead of silently skipping
  ## the read-only gate.

const VisualEditCommandIds = [
  "visual.delete", "visual.indent", "visual.dedent", "visual.lowercase",
  "visual.uppercase", "visual.togglecase", "visual.joinlines", "visual.to.insert",
  "visual.change", "visual.block.append", "visual.paste", "visual.paste.before",
  "visual.paste.end", "visual.paste.before.end", "edit.cut",
]
  ## Visual-mode command ids that modify the selection, gated on read-only
  ## buffers.

const VisualEditOperatorTypes = ["visual-replace", "visual-surround"]
  ## ctOperatorPending operatorTypes that modify the visual selection (`r`, `S`).
  ## Guarded the same way as EditOperatorTypes / VisualEditCommandIds.

const VisualConsumeOnlyCommandIds = ["visual.yank"]
  ## Command ids that end Visual by acting on the selection without editing
  ## it, outside the read-only gate.

proc executeFindCharMotion(
    ctx: CommandContext,
    motion: Motion,
    targetChar: string,
    count: int,
    isRepeat: bool = false,
): Result[(), string] =
  ## Move the cursor by f/F/t/T or their ; / , repeats (`isRepeat`) and refresh
  ## the match highlight. `motion` must be one of FindChar / FindCharBackward /
  ## TillChar / TillCharBackward.
  let r = ctx.motionController.moveCursorByMotion(
    ctx.state,
    MotionCommand(
      motion: motion, targetChar: targetChar, count: count, repeat: isRepeat
    ),
  )
  if r.isErr:
    return err(r.error)

  # Highlight all matching characters on cursor line
  ctx.state.ui.findCharMatchLine = ctx.cursor.line
  ctx.state.ui.findCharMatches =
    findAllCharPositions(ctx.buffer, ctx.cursor.line, targetChar)
  ok(())

proc executeCommand*(
    registry: CommandRegistry, ctx: CommandContext, cmd: key_bindings.Command
): Result[(), string] =
  ## Execute a keybinding command

  # Clear f/F/t/T match highlight when executing a non-find/till command
  if cmd.kind != ctOperatorPending or cmd.operatorType notin ["find", "till"]:
    ctx.state.ui.findCharMatches = @[]
    ctx.state.ui.findCharMatchLine = 0

  # Buffer-modifying commands, classified for the read-only gate below. Folds
  # are not opened here: an operator widens its own range over a closed fold.
  let isEditCommand =
    (
      ctx.state.pendingInput.pendingOperator.isSome and
      ctx.state.pendingInput.pendingOperator.get.operatorType != OpYank
    ) or (cmd.kind == ctOperatorPending and cmd.operatorType in EditOperatorTypes) or (
      cmd.kind in {ctAction, ctOperator, ctTextObject, ctCustom} and
      cmd.commandId in EditCommandIds
    )
  let isVisualEditCommand =
    (
      cmd.kind in {ctAction, ctOperator, ctTextObject, ctCustom} and
      cmd.commandId in VisualEditCommandIds
    ) or (cmd.kind == ctOperatorPending and cmd.operatorType in VisualEditOperatorTypes)
  # A command acting on the selection ends Visual, so like Vim it saves the area
  # for `gv` first; its edit then moves the area and the undo entry restores it.
  let consumer =
    if ctx.state.mode.isVisualAllMode and (
      isVisualEditCommand or (
        cmd.kind in {ctAction, ctOperator, ctTextObject, ctCustom} and
        cmd.commandId in VisualConsumeOnlyCommandIds
      )
    ): ctx.state.activeWindow else: nil
  let replacedArea =
    if consumer != nil:
      consumer.saveLastVisualAhead()
    else:
      none(VisualArea)
  defer:
    if consumer != nil:
      consumer.settleLastVisual(replacedArea)

  # Primitive-level checks in moepkg/buffer/edit.nim reject writes on readOnly
  # buffers at the choke point, and the operators now propagate those results.
  # Keep this gate as defense-in-depth: it centralizes the status message and
  # cancels any visual selection or pending operator in one place, instead of
  # leaving each handler to unwind its own state after a rejected edit.
  if (isEditCommand or isVisualEditCommand) and ctx.buffer.readOnly:
    if isVisualEditCommand:
      ctx.state.leaveVisual()
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    ctx.state.statusMessage = "Buffer is read-only"
    return ok(())

  let op = ctx.state.pendingInput.pendingOperator
  if op.isSome and registry.isMotion(cmd):
    return registry.finishOperator(ctx, operandFor(op.get, cmd))

  case cmd.kind
  of ctMotion:
    # ; / , replay the last f/F/t/T (resolved from editState) through the
    # find/till move, so 3; works too.
    if cmd.motion in {Motion.RepeatFind, Motion.RepeatFindReverse}:
      if ctx.state.editState.lastFindChar.isNone:
        ctx.state.statusMessage = "No previous find"
        return ok(())
      let last = ctx.state.editState.lastFindChar.get
      let motion =
        if cmd.motion == Motion.RepeatFindReverse:
          reverseFindMotion(last.motion)
        else:
          last.motion
      return executeFindCharMotion(
        ctx, motion, last.targetChar, max(1, cmd.count), isRepeat = true
      )

    # Bare G targets the last line, so a missing count is the 0 sentinel;
    # bare gg and 1gg both target line 1, so FirstLine needs no such case.
    let motionCount =
      if cmd.motion == Motion.LastLine and not cmd.hasCount: 0 else: cmd.count
    let motionCmd = MotionCommand(motion: cmd.motion, count: motionCount)
    logDebug(
      "command",
      "Executing motion, current cursor=(" & $ctx.cursor.line & "," & $ctx.cursor.column &
        ")",
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
    let isScrollMotion = cmd.motion in ScrollMotions
    let prevCursorLine = ctx.cursor.line

    # For smooth scroll motions, don't update viewport in executeMotion
    # The animation will handle viewport updates
    let skipViewportUpdate = isScrollMotion and ctx.smoothScrollConfig.enable
    let r = ctx.motionController.moveCursorByMotion(
      ctx.state, motionCmd, updateViewport = not skipViewportUpdate
    )
    if r.isErr:
      return err(r.error)
    logDebug(
      "command",
      "Motion returned cursor=(" & $r.value.line & "," & $r.value.column & ")",
    )

    let targetCursorLine = r.value.line

    # Start smooth scroll animation if this was a scroll motion
    if skipViewportUpdate and targetCursorLine != prevCursorLine:
      # Scroll the cursor back to where the animation starts, keeping the
      # column the move aimed for.
      ctx.state.scrollCursor(prevCursorLine)
      startScrollAnimation(
        ctx.state.windowDisplay.scrollAnimation, prevCursorLine, targetCursorLine,
        ctx.smoothScrollConfig,
      )

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
    # The character should have been set by processKey, which also applied
    # the count and cleared the numeric prefix (applyCountToCommand) before
    # the command reached us — no prefix bookkeeping is needed here.
    let count = cmd.count
    case cmd.operatorType
    of "mark-set", "mark-line", "mark-exact":
      if cmd.targetChar.len != 1 or cmd.targetChar[0] notin {'a' .. 'z'}:
        return err("Invalid mark (use a-z)")
      let name = cmd.targetChar[0]
      if cmd.operatorType == "mark-set":
        ctx.buffer.namedMarks[name] = some(ctx.cursor)
        return ok(())
      let linewise = cmd.operatorType == "mark-line"
      let dest = ctx.namedMarkPosition(name)
      if dest.isErr:
        return err(dest.error)
      recordJump(ctx.state)
      ctx.cursor = dest.get
      if linewise:
        moveToFirstNonBlank(ctx, ctx.cursor.line)
      return ok(())
    of "find":
      # Remember this find so ; and , can repeat it, then run the shared motion.
      let motion = if cmd.reverse: Motion.FindCharBackward else: Motion.FindChar
      ctx.state.editState.lastFindChar =
        some(LastFindChar(motion: motion, targetChar: cmd.targetChar))
      return executeFindCharMotion(ctx, motion, cmd.targetChar, count)
    of "till":
      let motion = if cmd.reverse: Motion.TillCharBackward else: Motion.TillChar
      ctx.state.editState.lastFindChar =
        some(LastFindChar(motion: motion, targetChar: cmd.targetChar))
      return executeFindCharMotion(ctx, motion, cmd.targetChar, count)
    of "replace":
      # Execute replace character action (r command)
      # Replace count characters with the target character
      if cmd.targetChar.charLen != 1:
        return err("No character specified for replace")

      let actualCount = max(1, count)
      let lineContent = ctx.buffer.getLine(ctx.cursor.line)

      # Check if we're at or past the end of the line
      if ctx.cursor.column >= lineContent.charLen:
        return err("Nothing to replace")

      # Calculate how many characters we can actually replace
      let charsAvailable = lineContent.charLen - ctx.cursor.column
      let charsToReplace = min(actualCount, charsAvailable)

      # Count via transformRange; refused for raw buffers.
      let targetChar = cmd.targetChar
      let repeatTarget = proc(text: string): string =
        targetChar.repeat(text.charLen)

      let startPos = BufferPosition(line: ctx.cursor.line, column: ctx.cursor.column)
      let endPos = BufferPosition(
        line: ctx.cursor.line, column: ctx.cursor.column + charsToReplace - 1
      )

      let txr =
        try:
          withTransaction(ctx.buffer, "replace " & $charsToReplace & " char(s)"):
            let res = ctx.buffer.transformRange(
              startPos, endPos, "replace characters", repeatTarget
            )
            if res.isErr:
              return err(res.error)
        except TransactionRollbackError as exc:
          # Surface a failed rollback (untrustworthy buffer) as a status message.
          return err(exc.msg & " (buffer state may be inconsistent)")
      if txr.isErr:
        return err(txr.error)

      # Record this command for repeat (.)
      ctx.recordChange(
        LastEditCommand(
          kind: lecReplaceChar,
          replaceChar: cmd.targetChar,
          replaceCount: charsToReplace,
        )
      )

      # Move cursor to the last replaced character (Vim behavior)
      ctx.cursor.column += charsToReplace - 1

      return ok(())
    of "visual-replace":
      # Execute visual replace action (r command in visual mode)
      if cmd.targetChar.charLen != 1:
        return err("No character specified for replace")

      # Check if we're in visual mode with active selection
      if not ctx.state.mode.isVisualAllMode:
        return err("No visual selection active")

      # Record the selection shape for `.` (Vim-compatible sizes). A charwise
      # `$` end keeps its raw column and repeat clamps it to the line; a block
      # after `<C-v>$` repeats to each line's end, as Vim's MAXCOL.
      let
        sel = ctx.state.operandSelection(ctx.buffer)
        loLine = min(sel.start.line, sel.current.line)
        hiLine = max(sel.start.line, sel.current.line)
      let visualRepeatCmd =
        case sel.kind
        of vskChar:
          if loLine == hiLine:
            LastEditCommand(
              kind: lecVisualReplace,
              visualReplaceChar: cmd.targetChar,
              visualReplaceKind: vskChar,
              visualReplaceRows: 1,
              visualReplaceCols: abs(sel.current.column - sel.start.column) + 1,
            )
          else:
            let lastCol =
              if sel.start.line <= sel.current.line:
                sel.current.column
              else:
                sel.start.column
            LastEditCommand(
              kind: lecVisualReplace,
              visualReplaceChar: cmd.targetChar,
              visualReplaceKind: vskChar,
              visualReplaceRows: hiLine - loLine + 1,
              visualReplaceCols: lastCol + 1,
            )
        of vskLine:
          LastEditCommand(
            kind: lecVisualReplace,
            visualReplaceChar: cmd.targetChar,
            visualReplaceKind: vskLine,
            visualReplaceRows: hiLine - loLine + 1,
            visualReplaceCols: 0,
          )
        of vskBlock:
          LastEditCommand(
            kind: lecVisualReplace,
            visualReplaceChar: cmd.targetChar,
            visualReplaceKind: vskBlock,
            visualReplaceRows: hiLine - loLine + 1,
            visualReplaceCols: abs(sel.current.column - sel.start.column) + 1,
            visualReplaceToLineEnd: sel.extendsToLineEnd,
          )

      # Surface a failed rollback (untrustworthy buffer) as a status message
      # instead of letting it escape to the crash handler.
      try:
        visualReplace(ctx.buffer, ctx.state, cmd.targetChar)
      except TransactionRollbackError as exc:
        return err(exc.msg & " (buffer state may be inconsistent)")

      # Don't record refused replaces on raw buffers; nothing changed.
      if ctx.buffer.allowsTextTransforms:
        ctx.recordChange(visualRepeatCmd)

      return ok(())
    of "visual-surround":
      # Execute visual surround action (S command in visual mode)
      if cmd.targetChar.charLen != 1:
        return err("No character specified for surround")

      if not ctx.state.mode.isVisualAllMode:
        return err("No visual selection active")

      # Surface a failed rollback (untrustworthy buffer) as a status message
      # instead of letting it escape to the crash handler.
      try:
        visualSurround(ctx.buffer, ctx.state, cmd.targetChar)
      except TransactionRollbackError as exc:
        return err(exc.msg & " (buffer state may be inconsistent)")

      return ok(())
    of "macro-record":
      return startMacroRecording(ctx, cmd.targetChar)
    of "register-select":
      # The key router keeps a valid `"x` as a prefix of the next command, so
      # only an invalid name comes here. Vim beeps and runs the keys after it.
      ctx.state.statusMessage = "Invalid register"
      return ok(())
    else:
      return Result[(), string].err "Unknown operator type: " & cmd.operatorType
  of ctAction, ctTextObject, ctOperator, ctCustom:
    # Execute through registry - convert string to CommandId
    # Get count from command object
    let count = cmd.count

    # Debug: log the count
    logDebug("command", "Executing " & cmd.commandId & " with count=" & $count)

    # First try as alias, then as custom command
    let cmdResult = registry.findCommand(cmd.commandId)

    # Pass count as arg when explicitly typed, so `1G` (visual) reaches the
    # handler as count=1 instead of falling back to the "no count" default.
    # Only prepend for handlers that accept an argument (maxArgs >= 1);
    # maxArgs=0 handlers (e.g. visual.yank, scroll.cursor.*) reject the
    # prefixed count with "Too many arguments".
    var finalArgs = cmd.args
    if cmdResult.isSome and cmdResult.get.maxArgs >= 1 and
        (count > 1 or (cmd.hasCount and count > 0)):
      finalArgs = @[$count] & cmd.args
    logDebug("command", "finalArgs (count=" & $count & "): " & $finalArgs)

    if cmdResult.isSome:
      # Found via alias or existing command
      return registry.execute(ctx, cmdResult.get.id, finalArgs)
    else:
      # Try as custom command
      return registry.execute(ctx, custom(cmd.commandId), finalArgs)

## Register built-in commands
proc registerBuiltinCommands*(registry: CommandRegistry) =
  ## Register all built-in commands by delegating to per-category registrars.
  registry.registerMotionAndScrollCommands()
  registry.registerVisualCommands()
  registry.registerEditCommands()
  registry.registerClipboardCommands()
  registry.registerMiscCommands()
  registry.registerMacroCommands()
