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

import pkg/results

import types, buffer, motion, key_bindings, modes, logger, render_utils

import command_handlers/visual_commands

import
  command_registry/[core, operator_engine, clipboard, motion_scroll, visual, edit, misc]
export core, operator_engine, clipboard, motion_scroll, visual, edit, misc

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
        let reservedLines = steadyBottomAreaHeight()
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
    # The character should have been set by processKey, which also applied
    # the count and cleared the numeric prefix (applyCountToCommand) before
    # the command reached us — no prefix bookkeeping is needed here.
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

      return ok(())
    of "visual-surround":
      # Execute visual surround action (S command in visual mode)
      if cmd.targetChar.len == 0:
        return err("No character specified for surround")

      if not ctx.state.visualSelection.active:
        return err("No visual selection active")

      visualSurround(ctx.buffer, ctx.state, cmd.targetChar[0])

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

    # First try as alias, then as custom command
    let cmdResult = registry.findCommand(cmd.commandId)
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
  registry.registerCommonAliases()
