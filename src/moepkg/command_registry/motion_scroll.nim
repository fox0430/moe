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

## Motion / scroll / fold commands and registration.

import std/options

import pkg/results

import ../[types, motion, modes, render_utils]
import ../buffer/[core, fold]

import core

# Helper function to register motion commands
proc registerMotionCommand*(
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
          # LastLine treats "no arg" as bare G (go to last line); moveLastLine
          # takes count=0 as that sentinel and count>=1 as an explicit line.
          let defaultCount = if motion == Motion.LastLine: 0 else: 1
          parseCount(args, default = defaultCount)
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

## Scroll commands

proc handleScrollCursorTop*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Scroll the viewport to place cursor line at the top (zt command)
  ## Cursor position doesn't change, only the viewport

  ctx.motionController.viewportManager.viewport.resetViewportTop(ctx.cursor.line)
  return ok(())

proc handleScrollCursorCenter*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Scroll the viewport to place cursor line at the center (z. or zz command)
  ## Cursor position doesn't change, only the viewport

  # Reserved lines (status line + command line share same row)
  let reservedLines = steadyBottomAreaHeight()
  let visibleHeight =
    ctx.motionController.viewportManager.viewport.height - reservedLines

  # Center the cursor line
  let targetTopLine = ctx.cursor.line - (visibleHeight div 2)

  # Clamp to valid range
  ctx.motionController.viewportManager.viewport.resetViewportTop(max(0, targetTopLine))

  return ok(())

proc handleScrollCursorBottom*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Scroll the viewport to place cursor line at the bottom (zb command)
  ## Cursor position doesn't change, only the viewport

  # Reserved lines (status line + command line share same row)
  let reservedLines = steadyBottomAreaHeight()
  let visibleHeight =
    ctx.motionController.viewportManager.viewport.height - reservedLines

  # Place cursor at the bottom of viewport
  let targetTopLine = ctx.cursor.line - visibleHeight + 1

  # Clamp to valid range
  ctx.motionController.viewportManager.viewport.resetViewportTop(max(0, targetTopLine))

  return ok(())

## Fold commands

proc handleFoldOpen*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Open fold at cursor position (zo command)
  if ctx.buffer.foldState.openFold(ctx.cursor.line):
    discard
  elif ctx.buffer.foldState.foldIndexAt(ctx.cursor.line).isNone:
    # Distinguish "no fold here" from "fold already open" (the latter is a
    # silent no-op, matching vim).
    ctx.state.statusMessage = "No fold found"
  return ok(())

proc handleFoldClose*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Close fold at cursor position (zc command)
  if ctx.buffer.foldState.closeFold(ctx.cursor.line):
    # Ensure cursor is not on a hidden line after closing
    if ctx.buffer.foldState.isLineInCollapsedFold(ctx.cursor.line):
      ctx.cursor.line = ctx.buffer.foldState.getPrevVisibleLine(ctx.cursor.line)
      # Clamp column to new line's length
      let lineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
      ctx.cursor.column = min(ctx.cursor.column, max(0, lineLen - 1))
  elif ctx.buffer.foldState.foldIndexAt(ctx.cursor.line).isNone:
    # Distinguish "no fold here" from "fold already closed" (the latter is a
    # silent no-op, matching vim and handleFoldOpen).
    ctx.state.statusMessage = "No fold found"
  return ok(())

proc handleFoldToggle*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Toggle fold at cursor position (za command)
  if ctx.buffer.foldState.toggleFold(ctx.cursor.line):
    # Ensure cursor is not on a hidden line after closing
    if ctx.buffer.foldState.isLineInCollapsedFold(ctx.cursor.line):
      ctx.cursor.line = ctx.buffer.foldState.getPrevVisibleLine(ctx.cursor.line)
      let lineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
      ctx.cursor.column = min(ctx.cursor.column, max(0, lineLen - 1))
    return ok(())
  else:
    ctx.state.statusMessage = "No fold found"
    return ok(())

proc handleFoldOpenAll*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Open all folds (zR command)
  ctx.buffer.foldState.openAllFolds()
  return ok(())

proc handleFoldCloseAll*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Close all folds (zM command)
  ctx.buffer.foldState.closeAllFolds()
  # Ensure cursor is not on a hidden line
  if ctx.buffer.foldState.isLineInCollapsedFold(ctx.cursor.line):
    ctx.cursor.line = ctx.buffer.foldState.getPrevVisibleLine(ctx.cursor.line)
    # Clamp column to new line's length
    let lineLen = ctx.buffer.getLine(ctx.cursor.line).charLen
    ctx.cursor.column = min(ctx.cursor.column, max(0, lineLen - 1))
  return ok(())

proc handleFoldCreate*(ctx: CommandContext, args: seq[string]): Result[(), string] =
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
    # Exit visual mode
    ctx.state.visualSelection.active = false
    ctx.state.mode = EditorMode.Normal
  else:
    ctx.state.statusMessage = "Cannot create overlapping fold"

  return ok(())

proc handleFoldDelete*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Delete fold at cursor position (zd command)
  if ctx.buffer.foldState.deleteFold(ctx.cursor.line):
    ctx.state.statusMessage = "Fold deleted"
    return ok(())
  else:
    ctx.state.statusMessage = "No fold found"
    return ok(())

proc handleFoldDeleteAll*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Delete all folds (zD command)
  let foldCount = ctx.buffer.foldState.folds.len
  if foldCount > 0:
    ctx.buffer.foldState.deleteAllFolds()
    ctx.state.statusMessage = $foldCount & " fold(s) deleted"
  else:
    ctx.state.statusMessage = "No folds to delete"
  return ok(())

proc registerMotionAndScrollCommands*(registry: CommandRegistry) =
  ## Register motion + scroll + fold commands.

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
    acceptsCount = true,
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
