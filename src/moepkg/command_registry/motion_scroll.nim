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

import
  ../[
    types, motion, cursor_util, page_scroll, render_utils, visible_rows,
    visual_selection, wanted_column,
  ]
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
  registry.register(
    builtin(id),
    name,
    description,
    proc(ctx: CommandContext, args: seq[string]): Result[(), string] =
      # Record jump for big movements
      if shouldRecordJump:
        recordJump(ctx.state)

      let count =
        if not acceptsCount:
          1
        elif motion == Motion.LastLine:
          # Bare G goes to the last line; moveLastLine takes 0 for that.
          ctx.count
        else:
          ctx.count1
      let cmd = MotionCommand(motion: motion, count: count)
      ctx.moveByMotion(cmd)
      return Result[(), string].ok (),
    0,
    0,
  )

## Scroll commands

proc scrollVisibleHeight(ctx: CommandContext): int =
  max(
    1,
    ctx.motionController.viewportManager.viewport.height -
      ctx.state.motionReservedLines(),
  )

proc scrollRowLayout(ctx: CommandContext): RowLayout =
  ctx.motionController.rowLayout()

proc scrollCursorLineTo(ctx: CommandContext, spot: CursorLineSpot) =
  ## Put the cursor line at the top of the window, in its middle or at its
  ## bottom.
  if ctx.buffer.isNil or ctx.buffer.len == 0:
    return
  ctx.scrollRowLayout().scrollCursorLineTo(
    ctx.motionController.viewportManager.viewport,
    ctx.cursor.line,
    ctx.cursor.column,
    ctx.scrollVisibleHeight(),
    spot,
    not ctx.state.activeWindow.isNil and
      ctx.state.activeWindow.cursorOnTabEnd(ctx.cursor),
  )

proc handleScrollCursorTop*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Place cursor at viewport top (zt).

  ctx.scrollCursorLineTo(clsTop)
  return ok(())

proc handleScrollCursorCenter*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Center cursor in viewport (zz / z.).

  ctx.scrollCursorLineTo(clsMiddle)
  return ok(())

proc handleScrollCursorBottom*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Place cursor at viewport bottom (zb).

  ctx.scrollCursorLineTo(clsBottom)
  return ok(())

proc scrollTops(
    ctx: CommandContext, layout: RowLayout, visibleHeight: int
): tuple[current, last: RowSpot] =
  ## The window's top, or the last page's when it is past the buffer's end,
  ## and the last page's top, as far as Ctrl-E goes.
  let viewport = ctx.motionController.viewportManager.viewport
  result.last = layout.lastPageTop(visibleHeight)
  result.current =
    if viewport.topLine < layout.lineCount:
      (viewport.topLine, viewport.topWrapOffset)
    else:
      result.last

proc cursorRow(ctx: CommandContext, layout: RowLayout, visibleHeight: int): int =
  ## The cursor's screen row: negative above the viewport, `visibleHeight` or
  ## more below it.
  let
    viewport = ctx.motionController.viewportManager.viewport
    (cursorOffset, _) = layout.cursorCell(ctx.cursor.line, ctx.cursor.column)
  if (line: ctx.cursor.line, offset: cursorOffset) <
      (line: viewport.topLine, offset: viewport.topWrapOffset):
    return -1
  layout.rowOfLine(
    viewport.topLine, viewport.topWrapOffset, ctx.cursor.line, visibleHeight
  ) + cursorOffset

proc moveCursorToRow(
    ctx: CommandContext, layout: RowLayout, row: VisibleRow, visibleHeight: int
) =
  let
    state = ctx.state
    leftCell = ctx.motionController.viewportManager.viewport.leftCell
  template sameScreenColumn(): BufferPosition =
    let (_, cellX) = layout.cursorCell(
      state.cursor.line, state.cursor.column, leftCell,
      state.activeWindow.cursorOnTabEnd,
    )
    BufferPosition(
      line: row.line,
      column: layout.cellToColumn(row.line, row.wrapSeg, cellX, leftCell),
    )

  if row.fold.isSome:
    state.scrollCursor(BufferPosition(line: row.line, column: 0))
  else:
    state.scrollCursor(row.line)
    # A wrapped line may show only some of its rows: off them, stay on the row
    # at the same screen column.
    if ctx.cursorRow(layout, visibleHeight) notin 0 ..< visibleHeight:
      state.scrollCursor(sameScreenColumn())

proc keepCursorInScrolledViewport(
    ctx: CommandContext, layout: RowLayout, visibleHeight: int
) =
  ## Bring the cursor back into the scrolled window, as Vim's scrollup and
  ## scrolldown do: to the top row when it went off the top, to the last row
  ## of the last line shown whole when it went past that. In a top line
  ## taller than the window, that is the window's last row.
  let
    viewport = ctx.motionController.viewportManager.viewport
    row = ctx.cursorRow(layout, visibleHeight)
    lastRow =
      layout.botline(viewport.topLine, viewport.topWrapOffset, visibleHeight).rows - 1
  if row in 0 .. lastRow:
    return
  let spot = layout.rowAt(
    viewport.topLine,
    viewport.topWrapOffset,
    if row < 0:
      0
    else:
      max(0, lastRow),
  )
  if spot.isSome:
    ctx.moveCursorToRow(layout, spot.get, visibleHeight)

proc handleScrollLineDown*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Scroll viewport down by screen rows (Ctrl-E). Keeps cursor visible.
  let
    count = ctx.givenCount(args)
    visibleHeight = ctx.scrollVisibleHeight()
    layout = ctx.scrollRowLayout()
    viewport = ctx.motionController.viewportManager.viewport
    (currentTop, maxTop) = ctx.scrollTops(layout, visibleHeight)
    row = layout.rowAt(currentTop.line, currentTop.offset, count)
    candidate: RowSpot =
      if row.isSome:
        (row.get.line, row.get.wrapSeg)
      else:
        maxTop
    targetTop = max(currentTop, min(maxTop, candidate))

  viewport.restoreViewportTop(targetTop.line, targetTop.offset)
  ctx.keepCursorInScrolledViewport(layout, visibleHeight)

  return ok(())

proc handleScrollLineUp*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Scroll viewport up by screen rows (Ctrl-Y). Keeps cursor visible.
  let
    count = ctx.givenCount(args)
    visibleHeight = ctx.scrollVisibleHeight()
    layout = ctx.scrollRowLayout()
    viewport = ctx.motionController.viewportManager.viewport
    currentTop = ctx.scrollTops(layout, visibleHeight).current
    targetTop = layout.walkBackRows(currentTop.line, currentTop.offset, count)

  viewport.restoreViewportTop(targetTop.line, targetTop.offset)
  ctx.keepCursorInScrolledViewport(layout, visibleHeight)

  return ok(())

proc scrollPage(
    ctx: CommandContext, args: seq[string], forward, half: bool
): Result[(), string] =
  ## Scroll the window as Vim's pagescroll and take the cursor to the indent
  ## of the line it lands on, as 'startofline' does. A smooth scroll that
  ## moves the window leaves the cursor on the window's edge instead, stops
  ## once the last line reaches the bottom row, and shows the way there over
  ## frames.
  if ctx.buffer.isNil or ctx.buffer.len == 0:
    return ok(())
  let
    state = ctx.state
    viewport = ctx.motionController.viewportManager.viewport
    visibleHeight = ctx.scrollVisibleHeight()
    layout = ctx.scrollRowLayout()
    start: RowSpot = (viewport.topLine, viewport.topWrapOffset)
    startCursor = ctx.cursor
    scroll =
      if half:
        let count = ctx.givenCount(args, default = 0)
        if count > 0:
          viewport.keepHalfPageRows(min(visibleHeight, count))
        layout.halfPage(
          start,
          ctx.cursor,
          visibleHeight,
          viewport.halfPageRows(visibleHeight),
          forward,
        )
      else:
        layout.page(start, ctx.cursor, visibleHeight, ctx.givenCount(args), forward)
  let
    smooth = ctx.smoothScrollConfig.animates
    down = start < scroll.top
    top =
      if smooth and down:
        # A smooth scroll stops once the last line reaches the bottom row.
        max(start, min(scroll.top, layout.lastPageTop(visibleHeight)))
      else:
        scroll.top
  if not scroll.moved or
      (smooth and down and top == start and scroll.cursorLine == startCursor.line):
    # Neither the window nor the cursor moves: Vim's pagescroll beeps. So
    # does a smooth scroll that the last line already stops.
    state.beep()
    return ok(())
  viewport.restoreViewportTop(top.line, top.offset)
  let
    landing =
      if smooth and top != start:
        # A smooth scroll takes the cursor to the edge it scrolls to and keeps
        # it there.
        layout.edgeCursor(top, visibleHeight, down)
      else:
        BufferPosition(
          line: scroll.cursorLine,
          column: firstNonBlankColumn(ctx.buffer.getLine(scroll.cursorLine)),
        )
    cursor = ctx.motionController.cursorManager.clampPosition(
      CursorPosition(x: landing.column, y: landing.line), ctx.buffer
    )
  state.cursor = BufferPosition(line: cursor.y, column: cursor.x)
  state.preferredColumn = -1
  # Sideways too, as the cursor goes.
  ctx.motionController.viewportManager.updateViewport(state, ctx.buffer, state.cursor)
  if smooth:
    state.windowDisplay.scrollAnimation.startPageScroll(
      layout,
      state.activeWindow,
      viewport,
      (start, startCursor),
      visibleHeight,
      ctx.smoothScrollConfig,
    )
  ok(())

proc handleScrollPageDown*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Scroll [count] pages down (Ctrl-F).
  ctx.scrollPage(args, forward = true, half = false)

proc handleScrollPageUp*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Scroll [count] pages up (Ctrl-B).
  ctx.scrollPage(args, forward = false, half = false)

proc handleScrollHalfPageDown*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Scroll half a window down, or [count] rows from now on (Ctrl-D).
  ctx.scrollPage(args, forward = true, half = true)

proc handleScrollHalfPageUp*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Scroll half a window up, or [count] rows from now on (Ctrl-U).
  ctx.scrollPage(args, forward = false, half = true)

## Fold commands

proc repeatFold(ctx: CommandContext, step: proc(): bool): bool =
  ## Run `step` up to count1 times, stopping when it does nothing (Vim's
  ## setFoldRepeat). Returns true if it did anything.
  for _ in 1 .. ctx.count1:
    if not step():
      break
    result = true

proc openFoldsAtCursor(ctx: CommandContext): bool =
  ## Open count1 levels of closed folds at the cursor, outermost first.
  let line = ctx.cursor.line
  ctx.repeatFold(
    proc(): bool =
      ctx.buffer.foldState.openFold(line)
  )

proc closeFoldsAtCursor(ctx: CommandContext): bool =
  ## Close count1 levels of open folds at the cursor, innermost first.
  let line = ctx.cursor.line
  ctx.repeatFold(
    proc(): bool =
      ctx.buffer.foldState.closeFold(line)
  )

proc reportNoFold(ctx: CommandContext) =
  ## A fold already open or closed is a silent no-op, as in Vim; only a line
  ## without any fold reports.
  if ctx.buffer.foldState.foldIndexAt(ctx.cursor.line).isNone:
    ctx.state.statusMessage = "No fold found"

proc handleFoldOpen*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Open the fold at the cursor, [count] levels deep (zo command)
  if not ctx.openFoldsAtCursor():
    ctx.reportNoFold()
  return ok(())

proc handleFoldClose*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Close the fold at the cursor, [count] levels deep (zc command)
  if not ctx.closeFoldsAtCursor():
    ctx.reportNoFold()
  return ok(())

proc handleFoldToggle*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Open [count] levels on a closed fold, else close [count] (za command)
  let toggled =
    if ctx.buffer.foldState.getCollapsedFoldAt(ctx.cursor.line).isSome:
      ctx.openFoldsAtCursor()
    else:
      ctx.closeFoldsAtCursor()
  if not toggled:
    ctx.reportNoFold()
  return ok(())

proc handleFoldOpenRecursive*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Open the closed fold at the cursor and every fold in it (zO command)
  if not ctx.buffer.foldState.openFoldRecursive(ctx.cursor.line):
    ctx.reportNoFold()
  return ok(())

proc handleFoldCloseRecursive*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## Close every fold at the cursor (zC command)
  if not ctx.buffer.foldState.closeFoldRecursive(ctx.cursor.line):
    ctx.reportNoFold()
  return ok(())

proc handleFoldToggleRecursive*(
    ctx: CommandContext, args: seq[string]
): Result[(), string] =
  ## zO on a closed fold, else zC (zA command)
  let toggled =
    if ctx.buffer.foldState.getCollapsedFoldAt(ctx.cursor.line).isSome:
      ctx.buffer.foldState.openFoldRecursive(ctx.cursor.line)
    else:
      ctx.buffer.foldState.closeFoldRecursive(ctx.cursor.line)
  if not toggled:
    ctx.reportNoFold()
  return ok(())

proc setFoldLevel(ctx: CommandContext, level: int) =
  ## Set 'foldlevel' and re-apply it to every fold.
  ctx.buffer.foldLevel = level
  ctx.buffer.foldState.applyFoldLevel(level)

proc handleFoldReduce*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Add [count] to 'foldlevel', at most the deepest nesting (zr command).
  ## Unchanged, it leaves folds opened or closed by hand alone, as in Vim.
  let level =
    min(ctx.buffer.foldLevel + ctx.count1, ctx.buffer.foldState.deepestNesting)
  if level != ctx.buffer.foldLevel:
    ctx.setFoldLevel(level)
  return ok(())

proc handleFoldMore*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Subtract [count] from 'foldlevel', at least 0 (zm command). Always
  ## re-applies the level, as Vim forces the update.
  ctx.setFoldLevel(max(0, ctx.buffer.foldLevel - ctx.count1))
  return ok(())

proc handleFoldOpenAll*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Set 'foldlevel' to the deepest nesting, opening every fold (zR command)
  ctx.setFoldLevel(ctx.buffer.foldState.deepestNesting)
  return ok(())

proc handleFoldCloseAll*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Set 'foldlevel' to 0, closing every fold (zM command)
  ctx.setFoldLevel(0)
  return ok(())

proc handleFoldCreate*(ctx: CommandContext, args: seq[string]): Result[(), string] =
  ## Create fold from visual selection (zf command)
  ## This is called from visual mode with the selection range
  let sel = ctx.state.operandSelection
  if not sel.active:
    ctx.state.statusMessage = "No selection"
    return ok(())

  let
    startLine = min(sel.start.line, sel.current.line)
    endLine = max(sel.start.line, sel.current.line)

  if ctx.buffer.foldState.addFold(startLine, endLine):
    ctx.state.statusMessage = "Fold created"
    ctx.state.leaveVisual()
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
    bcMotionBackspace, "Move Backspace",
    "Move cursor left, wrapping to the previous line", Motion.Backspace,
  )
  registry.registerMotionCommand(
    bcMotionRight, "Move Right", "Move cursor right", Motion.Right
  )
  registry.registerMotionCommand(bcMotionUp, "Move Up", "Move cursor up", Motion.Up)
  registry.registerMotionCommand(
    bcMotionDown, "Move Down", "Move cursor down", Motion.Down
  )
  registry.registerMotionCommand(
    bcMotionHome, "Home", "Move to beginning of line", Motion.Home, false
  )
  registry.registerMotionCommand(
    bcMotionFirstNonBlank, "First Non-Blank", "Move to first non-whitespace character",
    Motion.FirstNonBlank, false,
  )
  registry.registerMotionCommand(bcMotionEnd, "End", "Move to end of line", Motion.End)
  registry.registerMotionCommand(
    bcMotionScreenColumn, "Screen Column", "Move to screen column", Motion.ScreenColumn
  )
  registry.registerMotionCommand(
    bcMotionFirstLine,
    "First Line",
    "Move to first line",
    Motion.FirstLine,
    acceptsCount = true,
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

  registry.register(
    builtin(bcScrollLineDown),
    "Scroll Line Down",
    "Scroll viewport one line down (Ctrl-E)",
    handleScrollLineDown,
    0,
    1,
  )

  registry.register(
    builtin(bcScrollLineUp),
    "Scroll Line Up",
    "Scroll viewport one line up (Ctrl-Y)",
    handleScrollLineUp,
    0,
    1,
  )

  registry.register(
    builtin(bcScrollPageDown),
    "Scroll Page Down",
    "Scroll [count] pages down (Ctrl-F)",
    handleScrollPageDown,
    0,
    1,
  )

  registry.register(
    builtin(bcScrollPageUp),
    "Scroll Page Up",
    "Scroll [count] pages up (Ctrl-B)",
    handleScrollPageUp,
    0,
    1,
  )

  registry.register(
    builtin(bcScrollHalfPageDown),
    "Scroll Half Page Down",
    "Scroll half a window down, or [count] rows from now on (Ctrl-D)",
    handleScrollHalfPageDown,
    0,
    1,
  )

  registry.register(
    builtin(bcScrollHalfPageUp),
    "Scroll Half Page Up",
    "Scroll half a window up, or [count] rows from now on (Ctrl-U)",
    handleScrollHalfPageUp,
    0,
    1,
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
    builtin(bcFoldOpenRecursive),
    "Fold Open Recursive",
    "Open the fold at cursor and all folds in it (zO)",
    handleFoldOpenRecursive,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldCloseRecursive),
    "Fold Close Recursive",
    "Close all folds at cursor (zC)",
    handleFoldCloseRecursive,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldToggleRecursive),
    "Fold Toggle Recursive",
    "Toggle all folds at cursor (zA)",
    handleFoldToggleRecursive,
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
    builtin(bcFoldReduce),
    "Fold Reduce",
    "Add [count] to 'foldlevel' (zr)",
    handleFoldReduce,
    0,
    0,
  )

  registry.register(
    builtin(bcFoldMore),
    "Fold More",
    "Subtract [count] from 'foldlevel' (zm)",
    handleFoldMore,
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
