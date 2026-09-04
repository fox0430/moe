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

import types, motion, key_bindings, modes, logger, render_utils
import buffer/[core, edit, fold, undo]

import command_handlers/visual_commands

import
  command_registry/[core, operator_engine, clipboard, motion_scroll, visual, edit, misc]
export core, operator_engine, clipboard, motion_scroll, visual, edit, misc

const EditCommandIds = [
  "delete.char", "delete.char.before", "delete.line", "delete.word",
  "operator.delete.to.end", "operator.change.to.end", "paste.after", "paste.before",
  "edit.paste", "join.lines", "substitute.char", "substitute.line", "toggle.case",
  "operator.delete", "operator.change", "operator.indent", "operator.outdent",
  "operator.lowercase", "operator.uppercase", "autoindent.line", "edit.increment",
  "edit.decrement", "edit.repeat",
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
  "visual.change", "visual.block.append", "visual.paste",
]
  ## Visual-mode command ids that modify the selection. The selection is snapped
  ## to fold boundaries before the edit, and gated on read-only buffers.

const VisualEditOperatorTypes = ["visual-replace", "visual-surround"]
  ## ctOperatorPending operatorTypes that modify the visual selection (`r`, `S`).
  ## Guarded the same way as EditOperatorTypes / VisualEditCommandIds.

const VisualSnapOnlyCommandIds = ["visual.yank"]
  ## Visual-mode command ids that consume the selection whole but leave the
  ## buffer untouched. They need the same fold snap as an edit, so `y` and `d`
  ## agree on the selection, but stay outside the read-only gate.

proc reverseFindMotion(m: Motion): Motion =
  ## The opposite-direction find/till motion, used by `,`.
  case m
  of Motion.FindChar: Motion.FindCharBackward
  of Motion.FindCharBackward: Motion.FindChar
  of Motion.TillChar: Motion.TillCharBackward
  of Motion.TillCharBackward: Motion.TillChar
  else: m

proc tillRepeatSkipDest(
    ctx: CommandContext,
    reverse: bool,
    targetChar: string,
    count: int,
    fromPos: BufferPosition,
): Option[BufferPosition] =
  ## Destination for ; / , repeating a t/T: the cursor is parked one cell before
  ## a target, so probe one cell further along with findChar (which, unlike
  ## tillChar, distinguishes "found adjacent" from "not found") and back off by
  ## one for till semantics. none() when there is no further target. Shared by
  ## the cursor-move and pending-operator repeat paths.
  let
    findMotion = if reverse: Motion.FindCharBackward else: Motion.FindChar
    probeCol =
      if reverse:
        fromPos.column - 1
      else:
        fromPos.column + 1
  if probeCol < 0:
    return none(BufferPosition)
  # Forward: a probe at or past the end of the line has no character ahead to
  # find. Without this guard executeMotion clamps the out-of-range probe back
  # onto the line and the "did it move?" check below misfires into a phantom
  # match -- a wrong cursor jump for ; and a spurious d; delete at end of line.
  if not reverse and probeCol >= ctx.buffer.getLine(fromPos.line).charLen:
    return none(BufferPosition)
  let probe = BufferPosition(line: fromPos.line, column: probeCol)
  let fr = ctx.motionController.executeMotion(
    MotionCommand(motion: findMotion, targetChar: targetChar, count: count),
    probe,
    updateViewport = false,
  )
  if fr.isOk and not (fr.value.line == probe.line and fr.value.column == probe.column):
    var dest = fr.value
    if reverse:
      dest.column += 1
    else:
      dest.column -= 1
    return some(dest)
  return none(BufferPosition)

proc executeFindCharMotion(
    ctx: CommandContext,
    motion: Motion,
    targetChar: string,
    count: int,
    isRepeat: bool = false,
): Result[(), string] =
  ## Shared execution for f/F/t/T and their ; / , repeats. Handles both the
  ## pending-operator case (df{char}, d;) and the plain cursor-move case (which
  ## also refreshes the match highlight). `motion` must be one of FindChar /
  ## FindCharBackward / TillChar / TillCharBackward.
  ##
  ## `isRepeat` is set for ; and , so the cursor-move case reproduces vim's
  ## behaviour of skipping the match a t/T repeat is already parked before.
  let
    isTill = motion in {Motion.TillChar, Motion.TillCharBackward}
    reverse = motion in {Motion.FindCharBackward, Motion.TillCharBackward}
    motionCmd = MotionCommand(motion: motion, targetChar: targetChar, count: count)

  if ctx.state.pendingInput.pendingOperator.isSome:
    let op = ctx.state.pendingInput.pendingOperator.get
    # Fold the operator count into the motion count (2df{c} == d2f{c}); the
    # charwise delete ignores operatorCount, so the multiplication must happen
    # here as it does on the generic operator+motion path.
    let motionCount = count * op.operatorCount

    var endPos: BufferPosition
    if isRepeat and isTill:
      # ; / , repeating a t/T must skip the match the cursor is parked before,
      # exactly like the cursor-move case below.
      let skipDest =
        tillRepeatSkipDest(ctx, reverse, targetChar, motionCount, op.startPos)
      if skipDest.isNone:
        # No further target - delete nothing.
        ctx.state.pendingInput.pendingOperator = none(PendingOperator)
        return ok(())
      endPos = skipDest.get
    else:
      let endOpt =
        findTillOperatorEndPos(ctx, motion, targetChar, motionCount, op.startPos)
      if endOpt.isNone:
        # Character not found - clear operator and do nothing.
        ctx.state.pendingInput.pendingOperator = none(PendingOperator)
        return ok(())
      endPos = endOpt.get

    # Apply the operator over the find/till span (shared with the generic
    # operator+motion path and the `.` repeat).
    let opResult = applyOperatorOverMotion(
      ctx, op.operatorType, op.operatorCount, op.startPos, endPos, motion
    )
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    if opResult.isErr:
      return err(opResult.error)

    # Record this command for repeat (.) - only if successful and not a yank.
    # motionCount stores the raw count; edit.repeat re-multiplies by operatorCount.
    if op.operatorType != OpYank:
      ctx.state.editState.lastEditCommand = some(
        LastEditCommand(
          kind: lecOperatorMotion,
          operator: op.operatorType,
          motion: motion,
          motionCount: count,
          operatorCount: op.operatorCount,
          targetChar: targetChar,
        )
      )
    return ok(())
  else:
    # No pending operator - just move cursor.
    var skipped = false
    if isRepeat and isTill:
      # Repeating t/T: vim advances past the match the cursor is parked before.
      # Falls through to the plain till (a no-op) when there is no further target.
      let skipDest = tillRepeatSkipDest(ctx, reverse, targetChar, count, ctx.cursor)
      if skipDest.isSome:
        ctx.cursor = skipDest.get
        skipped = true
    if not skipped:
      let r = ctx.motionController.executeMotion(motionCmd, ctx.cursor)
      if r.isErr:
        return err(r.error)
      ctx.cursor = r.value

    # Highlight all matching characters on cursor line
    ctx.state.ui.findCharMatchLine = ctx.cursor.line
    ctx.state.ui.findCharMatches =
      findAllCharPositions(ctx.buffer, ctx.cursor.line, targetChar)
    return ok(())

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
  let isVisualSnapCommand =
    isVisualEditCommand or (
      cmd.kind in {ctAction, ctOperator, ctTextObject, ctCustom} and
      cmd.commandId in VisualSnapOnlyCommandIds
    )
  # A selection reaching into a closed fold covers that fold whole, as operators
  # do. A whole fold is whole lines, so such a selection becomes linewise.
  if isVisualSnapCommand and ctx.state.visualSelection.active:
    let
      selLo = min(
        ctx.state.visualSelection.start.line, ctx.state.visualSelection.current.line
      )
      selHi = max(
        ctx.state.visualSelection.start.line, ctx.state.visualSelection.current.line
      )
      snapped = ctx.buffer.foldState.snapRangeToFolds(selLo, selHi)
    if ctx.buffer.foldState.touchesCollapsedFold(selLo, selHi):
      ctx.state.visualSelection.kind = vskLine
      ctx.state.visualSelection.start =
        BufferPosition(line: snapped.startLine, column: 0)
      ctx.state.visualSelection.current =
        BufferPosition(line: snapped.endLine, column: 0)
      # The mode has to follow the selection kind: handlers such as
      # `visualBlockAppend` key off both and would otherwise do nothing.
      if ctx.state.mode in {EditorMode.Visual, EditorMode.VisualBlock}:
        ctx.state.mode = EditorMode.VisualLine

  # Primitive-level checks in moepkg/buffer/edit.nim reject writes on readOnly
  # buffers at the choke point, and the operators now propagate those results.
  # Keep this gate as defense-in-depth: it centralizes the status message and
  # cancels any visual selection or pending operator in one place, instead of
  # leaving each handler to unwind its own state after a rejected edit.
  if (isEditCommand or isVisualEditCommand) and ctx.buffer.readOnly:
    # Only unwind a selection that exists.
    if isVisualEditCommand and ctx.state.visualSelection.active:
      ctx.state.visualSelection.active = false
      # `previousMode` may itself be a visual mode, which has no selection now.
      ctx.state.mode =
        if ctx.state.previousMode.isVisualAllMode:
          EditorMode.Normal
        else:
          ctx.state.previousMode
    ctx.state.pendingInput.pendingOperator = none(PendingOperator)
    ctx.state.statusMessage = "Buffer is read-only"
    return ok(())
  case cmd.kind
  of ctMotion:
    # ; / , replay the last f/F/t/T (resolved from editState), reusing the same
    # find/till execution path so d; / 3; work too.
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

    # Check if we have a pending operator
    if ctx.state.pendingInput.pendingOperator.isSome:
      let op = ctx.state.pendingInput.pendingOperator.get

      # Multiply motion count by operator count for correct Vim behavior
      # e.g., 3dw = d3w (delete 3 words), 2d3w = 6 words
      let effectiveCount =
        if cmd.motion == Motion.LastLine and not cmd.hasCount:
          0
        else:
          cmd.count * op.operatorCount
      let motionCmd = MotionCommand(motion: cmd.motion, count: effectiveCount)

      # Execute motion to get end position
      # Suppress viewport updates to prevent visual scrolling during operator+motion
      let r = ctx.motionController.executeMotion(
        motionCmd, op.startPos, updateViewport = false
      )
      if r.isErr:
        ctx.state.pendingInput.pendingOperator = none(PendingOperator)
        return err(r.error)

      # Boundary-clamped no-move motion (dh at col 0, dk on first line, dj on
      # last line): vim treats as no-op. Without this, calculateOperatorRange
      # returns a zero-move inclusive range and the operator eats one char/line.
      if r.value == op.startPos and cmd.motion in NoMoveNoOpMotions:
        ctx.state.pendingInput.pendingOperator = none(PendingOperator)
        return ok(())

      block:
        # Apply the operator over the motion span (range calc + fold opening +
        # operator execution are shared with the find/till and `.` paths).
        let r = applyOperatorOverMotion(
          ctx, op.operatorType, op.operatorCount, op.startPos, r.value, cmd.motion
        )
        ctx.state.pendingInput.pendingOperator = none(PendingOperator)
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
              motionHasCount: cmd.hasCount,
              operatorCount: op.operatorCount,
            )
          )

      return ok(())
    else:
      # No pending operator - just move cursor
      let motionCount =
        if cmd.motion == Motion.LastLine and not cmd.hasCount: 0 else: cmd.count
      let motionCmd = MotionCommand(motion: cmd.motion, count: motionCount)
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
    # The character should have been set by processKey, which also applied
    # the count and cleared the numeric prefix (applyCountToCommand) before
    # the command reached us — no prefix bookkeeping is needed here.
    let count = cmd.count
    case cmd.operatorType
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
      ctx.state.editState.lastEditCommand = some(
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
      if not ctx.state.visualSelection.active:
        return err("No visual selection active")

      # Record the selection shape for `.` (Vim-compatible sizes).
      # `$`-extended ends keep the raw column; repeat clamps to the line.
      let
        sel = ctx.state.visualSelection
        loLine = min(sel.start.line, sel.current.line)
        hiLine = max(sel.start.line, sel.current.line)
        loCol = min(sel.start.column, sel.current.column)
        hiCol = max(sel.start.column, sel.current.column)
      let visualRepeatCmd =
        case sel.kind
        of vskChar:
          if loLine == hiLine:
            LastEditCommand(
              kind: lecVisualReplace,
              visualReplaceChar: cmd.targetChar,
              visualReplaceKind: vskChar,
              visualReplaceRows: 1,
              visualReplaceCols: hiCol - loCol + 1,
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
            visualReplaceCols: hiCol - loCol + 1,
          )

      # Surface a failed rollback (untrustworthy buffer) as a status message
      # instead of letting it escape to the crash handler.
      try:
        visualReplace(ctx.buffer, ctx.state, cmd.targetChar)
      except TransactionRollbackError as exc:
        return err(exc.msg & " (buffer state may be inconsistent)")

      # Don't record refused replaces on raw buffers; nothing changed.
      if ctx.buffer.allowsTextTransforms:
        ctx.state.editState.lastEditCommand = some(visualRepeatCmd)

      return ok(())
    of "visual-surround":
      # Execute visual surround action (S command in visual mode)
      if cmd.targetChar.charLen != 1:
        return err("No character specified for surround")

      if not ctx.state.visualSelection.active:
        return err("No visual selection active")

      # Surface a failed rollback (untrustworthy buffer) as a status message
      # instead of letting it escape to the crash handler.
      try:
        visualSurround(ctx.buffer, ctx.state, cmd.targetChar)
      except TransactionRollbackError as exc:
        return err(exc.msg & " (buffer state may be inconsistent)")

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
