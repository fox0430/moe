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

## View rendering procedures (split view, single view, bottom lines)

import std/[options, strutils, unicode]

import pkg/celina

import
  types/editor_types,
  editor_window,
  editor_window_layout,
  editor_render_window,
  editor_render_modes,
  render_utils,
  status_line,
  tab_line,
  buffer,
  unicode_utils,
  command_completion,
  color

type WindowLayout = object
  ## Per-frame layout metrics for a window. A pure, idempotent projection of
  ## window + display state, independent of `viewport.topLine`, so it yields the
  ## same result whether computed before or after the viewport adjustment.
  lineNumOffset: int
  isBottomWindow: bool
  isActiveWindow: bool
  reservedLines: int
  adjustHeight: int
  textAreaWidth: int
  effectiveLineWrap: bool
  renderMode: EditorMode

proc updateViewportSize*(e: Editor, buffer: Buffer): bool =
  ## Update screen size from buffer area and return true if resized.
  ## Uses e.screenSize (not e.viewport) to avoid overwriting the active
  ## window's viewport dimensions in split mode.
  ## Stores previous dimensions in prevWidth/prevHeight for resize calculations.
  e.screenSize.prevWidth = e.screenSize.width
  e.screenSize.prevHeight = e.screenSize.height

  e.screenSize.width = buffer.area.width
  e.screenSize.height = buffer.area.height

  (e.screenSize.prevWidth != e.screenSize.width) or
    (e.screenSize.prevHeight != e.screenSize.height)

proc adjustViewportForCursor(
    viewport: ViewPort,
    cursor: BufferPosition,
    visibleHeight, textAreaWidth: int,
    lineWrap: bool,
    textBuffer: TextBuffer,
    tabStop: int,
    wrapCache: WrapCountCache,
) =
  ## Adjust viewport to keep cursor visible (scroll if cursor is off-screen)
  # Vertical adjustment
  if lineWrap and not textBuffer.isNil:
    let maxWidth = max(1, textAreaWidth)

    if cursor.line < viewport.topLine:
      viewport.topLine = cursor.line
    else:
      # Cursor is at or below topLine. Walk backward from the cursor line,
      # accumulating screen (wrapped) rows until we either reach visibleHeight
      # or run out of lines. The stopping line is the highest topLine that still
      # keeps the cursor visible — i.e. the minimal downward scroll, identical to
      # what the previous forward-sum loop produced. Bounding the walk by
      # visibleHeight makes this O(visibleHeight) per frame regardless of how far
      # the cursor jumped (e.g. `G` on a huge file), instead of
      # O(cursor.line - topLine), and only touches lines that become visible.
      #
      # Collapsed folds are fold-aware (matching renderWindow / calculateWindow-
      # Cursor): a collapsed fold's start line is a single marker row, its hidden
      # interior contributes no rows and is skipped to the fold start in one step.
      let cursorLine = min(cursor.line, textBuffer.len - 1)
      if cursorLine >= viewport.topLine:
        wrapCache.ensureFresh(textBuffer, maxWidth, tabStop)
        var
          screenLines =
            if textBuffer.foldState.getCollapsedFoldAt(cursorLine).isSome:
              1
            else:
              wrapCache.cachedWrapCount(textBuffer, cursorLine)
          newTopLine = cursorLine
        # Walk past the current topLine (bounded by visibleHeight) and only apply
        # a downward scroll, so a fold straddling topLine never scrolls up.
        while newTopLine > 0 and screenLines < visibleHeight:
          let prev = newTopLine - 1
          let prevFold = textBuffer.foldState.getCollapsedFoldAt(prev)
          let
            prevTop = if prevFold.isSome: prevFold.get.startLine else: prev
            prevCount =
              if prevFold.isSome:
                1
              else:
                wrapCache.cachedWrapCount(textBuffer, prev)
          if screenLines + prevCount > visibleHeight:
            break
          screenLines += prevCount
          newTopLine = prevTop
        if newTopLine > viewport.topLine:
          viewport.topLine = newTopLine
  elif textBuffer.isNil:
    # No buffer to consult for folds: fall back to raw line arithmetic.
    if cursor.line >= viewport.topLine + visibleHeight:
      viewport.topLine = max(0, cursor.line - visibleHeight + 1)
    elif cursor.line < viewport.topLine:
      viewport.topLine = cursor.line
  elif cursor.line < viewport.topLine:
    viewport.topLine = cursor.line
  else:
    # Cursor is at or below topLine. Walk backward from the cursor accumulating
    # visible (marker / non-folded) rows until the window fills, to find the
    # minimal downward scroll. Each collapsed fold collapses to a single marker
    # row and is skipped in one step, so this stays O(visibleHeight) per frame
    # even when the cursor jumps far (e.g. `G`) over a large fold. If we reach
    # the current topLine before filling, the cursor is already visible and
    # topLine is left untouched.
    let cursorLine = min(cursor.line, textBuffer.len - 1)
    if cursorLine >= viewport.topLine:
      var
        rows = 1 # the cursor line itself
        newTopLine = cursorLine
      while newTopLine > 0 and rows < visibleHeight:
        let prev = newTopLine - 1
        let fold = textBuffer.foldState.getCollapsedFoldAt(prev)
        if fold.isSome:
          # The whole collapsed fold is one marker row; jump over its interior.
          inc rows
          newTopLine = fold.get.startLine
        else:
          inc rows
          dec newTopLine
      if newTopLine > viewport.topLine:
        viewport.topLine = newTopLine

  # Horizontal adjustment (only when line wrap is disabled)
  if not lineWrap:
    if cursor.column >= viewport.leftColumn + textAreaWidth:
      viewport.leftColumn = max(0, cursor.column - textAreaWidth + 1)
    elif cursor.column < viewport.leftColumn:
      viewport.leftColumn = cursor.column

proc syncSelectionCursor(window: EditorWindow) =
  ## Mirror a selection-list mode's selected index onto the window cursor so
  ## `renderWindow` highlights the right row. Modes that render a header at
  ## line 0 (BufferManager, BookmarkManager, ...) offset the index by 1; flat
  ## lists (Filer, FileTree, Help, DiffViewer, Debug) map 1:1. A no-op for any
  ## other modeState kind (mskNone/Config/Terminal/...), so it is safe to call
  ## unconditionally before `renderWindow`.
  case window.modeState.kind
  of mskFiler:
    window.cursor.line = window.modeState.filer.selectedIndex
  of mskFileTree:
    window.cursor.line = window.modeState.fileTree.selectedIndex
  of mskHelp:
    window.cursor.line = window.modeState.help.selectedIndex
  of mskDiffViewer:
    window.cursor.line = window.modeState.diffViewer.selectedIndex
  of mskDebug:
    window.cursor.line = window.modeState.debug.selectedLine
  of mskBufferManager:
    window.cursor.line = window.modeState.bufferManager.selectedIndex + 1
  of mskBookmarkManager:
    window.cursor.line = window.modeState.bookmarkManager.selectedIndex + 1
  of mskBackupManager:
    window.cursor.line = window.modeState.backupManager.selectedIndex + 1
  of mskReferences:
    window.cursor.line = window.modeState.references.selectedIndex + 1
  of mskDocumentSymbol:
    window.cursor.line = window.modeState.documentSymbol.selectedIndex + 1
  of mskCallHierarchy:
    window.cursor.line = window.modeState.callHierarchy.selectedIndex + 1
  of mskRecentFile:
    window.cursor.line = window.modeState.recentFile.selectedIndex + 1
  else:
    return
  window.cursor.column = 0

proc computeWindowLayout(
    e: Editor, window: EditorWindow, i, maxBottomY, tabLineOffset: int
): WindowLayout =
  ## Compute a window's layout metrics. Shared by `advanceLayoutForFrame` (to
  ## feed the viewport pass) and `renderSplitView` (to paint); calling it in both
  ## phases is cheap and produces identical results.
  let
    lineNumOffset =
      calculateLineNumOffset(window.buffer, e.state.display.showLineNumbers)
    windowBottomY = window.viewport.y + window.viewport.height
    isBottomWindow = (windowBottomY == maxBottomY)
    isActiveWindow = (i == e.windowManager.activeWindowIndex)
    reservedLines = e.calculateReservedLines(isBottomWindow)
    # Viewport scrolling (topLine) is persistent state, so it must use the
    # steady bottom reserve: a transiently grown command-line area (wrapped
    # overlay input, multi-line status message) would otherwise scroll the view
    # up and never scroll it back once the area shrinks again.
    steadyReservedLines =
      if isBottomWindow:
        steadyBottomAreaHeight()
      else:
        reservedLines
    adjustHeight = max(1, window.viewport.height - steadyReservedLines - tabLineOffset)
    sidebarWidth = e.calculateSidebarWidth(window.mode)
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
    textAreaWidth =
      max(0, window.viewport.width - sidebarWidth - scrollbarWidth - lineNumOffset)
    # Utility windows (Filer / Help / BufferManager / ...) render in no-wrap mode
    # regardless of the global lineWrap setting.
    effectiveLineWrap = e.state.display.lineWrap and window.mode.isFileEditMode
    # For overlay modes (Command, Search, Rename) over the active window, paint
    # the underlying base mode as background.
    renderMode =
      if isActiveWindow and e.state.hasOverlay: e.state.baseMode else: window.mode
  WindowLayout(
    lineNumOffset: lineNumOffset,
    isBottomWindow: isBottomWindow,
    isActiveWindow: isActiveWindow,
    reservedLines: reservedLines,
    adjustHeight: adjustHeight,
    textAreaWidth: textAreaWidth,
    effectiveLineWrap: effectiveLineWrap,
    renderMode: renderMode,
  )

proc advanceLayoutForFrame*(e: Editor, buffer: Buffer, wasResized: bool) =
  ## Advance per-frame window-layout state so the draw pass can be a read-only
  ## projection: rebuild the layout on resize, sync selection-list cursors,
  ## adjust each viewport to follow its cursor, and set the screen cursor and
  ## visibility. Config / Terminal-Input position their own cursor inline with
  ## their specialized draw (see renderConfig / renderTerminal), so they are
  ## skipped here.

  # If terminal was resized, rebuild window layout.
  if wasResized and e.screenSize.prevWidth > 0 and e.screenSize.prevHeight > 0 and
      e.screenSize.width > 0 and e.screenSize.height > 0:
    e.windowManager.resizeWindows(
      e.screenSize.width, e.screenSize.height, e.screenSize.prevWidth,
      e.screenSize.prevHeight, e.state.display.multiStatusLine,
    )

  let
    maxBottomY = findMaxBottomY(e.windowManager.windows)
    tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0

  for i, window in e.windowManager.windows:
    let layout = e.computeWindowLayout(window, i, maxBottomY, tabLineOffset)
    # Mirror a selection-list mode's selected index onto the cursor *before* the
    # viewport pass so the viewport tracks the selection on the same frame
    # (e.g. resuming a long backup list after closing a diff). No-op for modes
    # whose modeState isn't a selection list.
    window.syncSelectionCursor()
    adjustViewportForCursor(
      window.viewport, window.cursor, layout.adjustHeight, layout.textAreaWidth,
      layout.effectiveLineWrap, window.buffer, e.state.display.tabStop,
      window.wrapCountCache,
    )

  # Set screen cursor to active window position.
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    # Terminal-Input manages its own screen cursor from the grid; Config
    # positions it at the edit field. Both do so during the draw, so skip the
    # standard buffer-cursor calculation that would overwrite them.
    let
      isTerminalInput =
        e.activeWindow.mode == EditorMode.Terminal and
        e.activeWindow.modeState.kind == mskTerminal and
        e.activeWindow.modeState.terminal.subMode == tsmInput
      isConfig = e.activeWindow.mode == EditorMode.Config

    if not isTerminalInput and not isConfig:
      e.setActiveWindowScreenCursor(e.activeWindow)

    # Set cursor visibility based on mode. Config and Terminal set cursorVisible
    # in their render functions (the documented draw-side exceptions).
    case e.activeWindow.mode
    of EditorMode.Filer:
      e.state.cursorVisible = e.state.hasOverlay
    of EditorMode.Config:
      discard
    of EditorMode.BufferManager, EditorMode.BookmarkManager, EditorMode.Help,
        EditorMode.BackupManager, EditorMode.DiffViewer, EditorMode.Debug,
        EditorMode.References, EditorMode.DocumentSymbol, EditorMode.CallHierarchy,
        EditorMode.RecentFile, EditorMode.FileTree:
      # Show cursor when an overlay (command/search/rename) is active
      e.state.cursorVisible = e.state.hasOverlay
    of EditorMode.Terminal:
      discard
    else:
      # Normal, Insert, Visual, etc. - cursor should be visible
      e.state.cursorVisible = true

  # Screen-cursor override. Higher-priority owners set the cursor last, so the
  # final precedence is tempMessage > overlay > window (matching the former
  # draw-order of renderWrappedInput / renderTempMessages). Config / Terminal
  # defer to these via a guard in their render procs.
  let width = buffer.area.width
  if e.state.hasOverlay:
    let
      screenBottomY = buffer.area.y + buffer.area.height - 1
      areaH = min(e.state.commandLineAreaHeight(width), buffer.area.height)
      areaTopY = screenBottomY - areaH + 1
      (text, cursorChar) = e.state.overlayInput()
      (totalRows, cRow, cCol) = wrappedInputGrid(text, cursorChar, width)
      firstRow = max(0, min(cRow, totalRows - areaH))
    e.state.screenCursor.x = buffer.area.x + cCol
    e.state.screenCursor.y = areaTopY + (cRow - firstRow)

  if e.state.ui.tempMessages.len > 0:
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = buffer.area.height - 1

proc renderSplitView*(e: Editor, buffer: var Buffer) =
  ## Paint the split window view. Read-only: viewport scrolling, selection-list
  ## cursor sync, and screen cursor/visibility are advanced beforehand in
  ## `advanceLayoutForFrame`; this proc only draws.

  let
    maxBottomY = findMaxBottomY(e.windowManager.windows)
    tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0

  for i, window in e.windowManager.windows:
    let layout = e.computeWindowLayout(window, i, maxBottomY, tabLineOffset)

    # Render tab line for this window if enabled.
    # Resolve the window's per-window tab list (BufferIds) to TextBuffer refs.
    # Stale ids (deleted buffers) are skipped silently.
    if e.state.display.showTabLine:
      var buffersToShow: seq[TextBuffer] = @[]
      for id in window.bufferIds:
        let bufOpt = e.bufferById(id)
        if bufOpt.isSome:
          buffersToShow.add(bufOpt.get)
      if buffersToShow.len == 0:
        buffersToShow = @[window.buffer]
      renderWindowTabLine(
        buffersToShow, window.buffer, window.mode, buffer, window.viewport.y,
        window.viewport.x, window.viewport.width, e.state.display.showTabLine,
        layout.isActiveWindow,
      )

    # Render based on mode - some special modes support per-window rendering.
    # Selection-list modes (Filer/Help/managers/viewers) share one path and
    # render normally; their cursor was already synced from the selected index
    # in advanceLayoutForFrame. Config and Terminal-Input are the only modes
    # that need a dedicated render proc.
    case layout.renderMode
    of EditorMode.Filer, EditorMode.FileTree, EditorMode.Help, EditorMode.BufferManager,
        EditorMode.BookmarkManager, EditorMode.BackupManager, EditorMode.DiffViewer,
        EditorMode.Debug, EditorMode.References, EditorMode.DocumentSymbol,
        EditorMode.CallHierarchy, EditorMode.RecentFile:
      e.renderWindow(
        buffer, window, layout.lineNumOffset, layout.isBottomWindow,
        layout.isActiveWindow, tabLineOffset,
      )
    of EditorMode.Config:
      # Config supports per-window rendering
      e.renderConfig(buffer, window, layout.isBottomWindow, tabLineOffset)
    of EditorMode.Terminal:
      # Terminal mode renders grid directly in Input sub-mode,
      # or uses standard window rendering in Normal sub-mode
      if window.modeState.kind == mskTerminal and
          window.modeState.terminal.subMode == tsmInput:
        e.renderTerminal(buffer, window, layout.isBottomWindow, tabLineOffset)
      else:
        e.renderWindow(
          buffer, window, layout.lineNumOffset, layout.isBottomWindow,
          layout.isActiveWindow, tabLineOffset,
        )
    else:
      # Normal buffer rendering (Normal, Insert, Visual, Command, Search, etc.)
      e.renderWindow(
        buffer, window, layout.lineNumOffset, layout.isBottomWindow,
        layout.isActiveWindow, tabLineOffset,
      )

    # Render per-window status line if multi-status line mode is enabled
    # (and merge is disabled - merge shows only one status line at bottom)
    if e.state.display.showStatusLine and e.state.display.multiStatusLine and
        not e.config.statusLine.merge:
      # Bottom windows: a grown command-line area reserves its own status row
      # above it (bottomAreaHeight = grown rows + 1), so shift the status line
      # up by the grown rows; steady state (reservedLines == 1) is unshifted
      # and keeps sharing the bottom row with the command line.
      let statusLineY =
        if layout.isBottomWindow:
          max(
            window.viewport.y,
            calculateWindowStatusLineY(window, layout.isBottomWindow) -
              (layout.reservedLines - 1),
          )
        else:
          calculateWindowStatusLineY(window, layout.isBottomWindow)
      e.state.renderWindowStatusLine(
        window.buffer, buffer, statusLineY, window.viewport.x, window.viewport.width,
        layout.isActiveWindow, window.mode, e.config.statusLine,
      )

    # Draw separator between windows (except for last window)
    if i < e.windowManager.windows.len - 1:
      let nextWindow = e.windowManager.windows[i + 1]
      e.renderWindowSeparator(buffer, window, nextWindow, layout.isBottomWindow)

proc renderWrappedInput(
    buffer: var Buffer,
    areaTopY, areaH, width: int,
    text: string,
    grid: tuple[totalRows, cursorRow, cursorCol: int],
) =
  ## Render overlay input text wrapped across the command-line area. When the
  ## input exceeds the area (height cap), scrolls within the wrap grid keeping
  ## the cursor row visible, biased to the tail like Vim. Read-only: the screen
  ## cursor is placed in advanceLayoutForFrame from the same wrap grid.
  let
    style = commandStyle()
    (totalRows, cRow, _) = grid
    firstRow = max(0, min(cRow, totalRows - areaH))

  if areaH > 1:
    # Grown area: clear all rows (they cover window content).
    # The steady single row keeps the overlay-styled status line beneath the
    # input, matching the previous shared-row rendering.
    buffer.fill(
      Rect(x: buffer.area.x, y: areaTopY, width: buffer.area.width, height: areaH),
      cell(" ", style),
    )

  # Walk the wrap segments once and draw the visible ones. Same grid as
  # wrappedInputRowCount/wrappedInputCursor: shared boundary rule
  # (startsNewWrapSegment inside displayWidthSubstrFromByte) and tab stop.
  var
    bytePos = 0
    row = 0
  while bytePos < text.len and row < firstRow + areaH:
    let (_, _, endByte) =
      displayWidthSubstrFromByte(text, bytePos, width, InputWrapTabStop)
    if row >= firstRow:
      buffer.setString(
        buffer.area.x, areaTopY + (row - firstRow), text[bytePos ..< endByte], style
      )
    bytePos = endByte
    row.inc

proc renderBottomLines*(e: Editor, buffer: var Buffer) =
  ## Render status line and the command-line area at the bottom of the screen.
  ## The area height is dynamic (commandLineAreaHeight): in the steady state
  ## it is the single row shared by the status line and the command line
  ## (overlays overwrite the status line). Wrapped overlay input and
  ## multi-line status messages grow the area upward, pushing the status line
  ## onto its own row above it.
  let
    width = buffer.area.width
    screenBottomY = buffer.area.y + buffer.area.height - 1
    areaH = min(e.state.commandLineAreaHeight(width), buffer.area.height)
    areaTopY = screenBottomY - areaH + 1
    grown = areaH > 1

  # Render global status line:
  # - When multiStatusLine is disabled: single status line for all windows
  # - When merge is enabled: merged status line at bottom
  # When multiStatusLine is enabled (and merge is off), per-window status lines
  # are rendered in renderSplitView instead (bottom windows shift theirs above
  # a grown area there, so the grown branch must not add a global one on top).
  if not e.state.display.multiStatusLine or e.config.statusLine.merge:
    if grown:
      # Pushed up onto its own row above the grown area
      let statusY = areaTopY - 1
      if statusY >= buffer.area.y:
        e.state.renderStatusLine(e.activeBuffer(), buffer, statusY, e.config.statusLine)
    else:
      e.state.renderStatusLine(
        e.activeBuffer(), buffer, screenBottomY, e.config.statusLine
      )

  if e.state.hasOverlay:
    let
      (text, cursorChar) = e.state.overlayInput()
      grid = wrappedInputGrid(text, cursorChar, width)
    renderWrappedInput(buffer, areaTopY, areaH, width, text, grid)

    # Render command completion popup if active
    if e.state.isCommandOverlay and e.state.commandCompletionManager.isActive():
      let popupPos = calculateCommandPopupPosition(
        e.state.input.commandCursor,
        buffer.area.width,
        buffer.area.height,
        e.state.commandCompletionManager.menu.entries,
        e.state.commandCompletionManager.menu.maxVisible,
        e.state.commandCompletionManager.argStartX,
        # Full bottom reserve, so the popup also clears the status line
        # pushed above a grown area
        bottomAreaRows = e.state.bottomAreaHeight(width),
      )
      renderCommandCompletionPopup(
        buffer, e.state.commandCompletionManager.menu, popupPos
      )
  else:
    let lineCount = e.state.statusMessageLineCount()
    if lineCount == 1:
      # Single line: overwrite the status line on the shared row
      buffer.setString(
        buffer.area.x, screenBottomY, e.state.statusMessage, commandStyle()
      )
    elif lineCount > 1:
      # Multi-line: render the last areaH message lines into the grown area
      let
        allLines = e.state.statusMessage.split('\n')
        lines =
          if allLines.len > areaH:
            allLines[allLines.len - areaH .. ^1]
          else:
            allLines
      buffer.fill(
        Rect(x: buffer.area.x, y: areaTopY, width: buffer.area.width, height: lines.len),
        cell(" ", commandStyle()),
      )
      for i, line in lines:
        buffer.setString(buffer.area.x, areaTopY + i, line, commandStyle())

proc renderTempMessages*(e: Editor, buffer: var Buffer) =
  ## Render temporary messages at the bottom of screen (like Vim's :jumps output)
  ## Overwrites the buffer content from bottom up, with a border at top
  if e.state.ui.tempMessages.len == 0:
    return

  let
    # +2 for border line and "Press ENTER..." prompt
    totalLines = e.state.ui.tempMessages.len + 2
    startY = max(0, buffer.area.height - totalLines)
    borderLine = " ".repeat(buffer.area.width)
    whiteBorderStyle = getThemeStyle(EditorColorPairIndex.tempMessageBorder)
    theNormalStyle = normalStyle()

  # Clear the area where messages will be displayed
  for y in startY ..< buffer.area.height:
    buffer.setString(buffer.area.x, y, " ".repeat(buffer.area.width), theNormalStyle)

  # Render border line at top (white background)
  buffer.setString(buffer.area.x, startY, borderLine, whiteBorderStyle)

  # Render each message line
  for i, msg in e.state.ui.tempMessages:
    let y = startY + 1 + i # +1 to skip border
    if y < buffer.area.height - 1: # Leave last line for prompt
      buffer.setString(buffer.area.x, y, msg, theNormalStyle)

  # Render the prompt on the last line
  let promptY = buffer.area.height - 1
  buffer.setString(
    buffer.area.x, promptY, "Press ENTER or type command to continue", commandStyle()
  )
  # Read-only: the screen cursor for this prompt is placed in
  # advanceLayoutForFrame.

proc renderCodeLensPicker*(e: Editor, buffer: var Buffer) =
  ## Render CodeLens picker popup when multiple items are available
  if not e.state.lspCache.codeLensPicker.isActive or
      e.state.lspCache.codeLensPicker.items.len == 0:
    return

  let
    items = e.state.lspCache.codeLensPicker.items
    selectedIdx = e.state.lspCache.codeLensPicker.selectedIndex
    scrollOffset = e.state.lspCache.codeLensPicker.scrollOffset
    maxVisibleItems = e.state.lspCache.codeLensPicker.maxVisibleItems

  # Calculate how many items to actually show
  let visibleCount = min(maxVisibleItems, items.len - scrollOffset)

  # Check if scroll indicators are needed
  let hasMoreAbove = scrollOffset > 0
  let hasMoreBelow = scrollOffset + visibleCount < items.len

  # Calculate popup dimensions using display width for multi-byte characters
  var maxDisplayWidth = 0
  for item in items:
    let w = displayWidth(item.title)
    if w > maxDisplayWidth:
      maxDisplayWidth = w
  # Add padding (2 chars each side) + number prefix (3 chars: "N. ") and limit to screen width
  let contentWidth = min(maxDisplayWidth + 2 + 3, buffer.area.width - 6)
  let popupWidth = contentWidth + 2 # +2 for border

  let popupHeight = visibleCount + 2 # +2 for border

  # Position popup near cursor
  var
    popupX = e.state.screenCursor.x
    popupY = e.state.screenCursor.y + 1

  # Adjust if popup goes off screen
  if popupX + popupWidth > buffer.area.width:
    popupX = max(0, buffer.area.width - popupWidth)
  if popupY + popupHeight > buffer.area.height - 2:
    popupY = max(0, e.state.screenCursor.y - popupHeight)

  # Define styles (derived from the current theme)
  let
    borderStyle = getThemeStyle(EditorColorPairIndex.popupWindowBorder)
    popupNormalStyle = getThemeStyle(EditorColorPairIndex.popupWindow)
    selectedStyle = getThemeStyle(EditorColorPairIndex.popupWinCurrentLine)
    scrollIndicatorStyle = getThemeStyle(EditorColorPairIndex.popupWindowScrollBar)

  # Draw top border with scroll indicator if needed
  if popupY >= 0 and popupY < buffer.area.height:
    buffer.setString(popupX, popupY, "┌", borderStyle)
    for x in 1 ..< popupWidth - 1:
      if popupX + x < buffer.area.width:
        buffer.setString(popupX + x, popupY, "─", borderStyle)
    # Show scroll up indicator in top-right corner
    if hasMoreAbove and popupX + popupWidth - 2 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 2, popupY, "▲", scrollIndicatorStyle)
    if popupX + popupWidth - 1 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 1, popupY, "┐", borderStyle)

  # Draw visible items (based on scroll offset)
  for displayIdx in 0 ..< visibleCount:
    let itemIdx = scrollOffset + displayIdx
    if itemIdx >= items.len:
      break

    let item = items[itemIdx]
    let y = popupY + 1 + displayIdx
    if y >= buffer.area.height - 1:
      break

    let style = if itemIdx == selectedIdx: selectedStyle else: popupNormalStyle

    # Left border
    buffer.setString(popupX, y, "│", borderStyle)

    # Fill background first
    for x in 1 ..< popupWidth - 1:
      if popupX + x < buffer.area.width:
        buffer.setString(popupX + x, y, " ", style)

    # Draw number prefix for items 1-9
    var textX = popupX + 2
    if itemIdx < 9:
      let numStr = $(itemIdx + 1) & "."
      let numStyle = Style(
        fg: getThemeStyle(EditorColorPairIndex.popupWindowScrollBar).fg,
        bg: style.bg,
        modifiers: {},
      )
      buffer.setString(textX, y, numStr, numStyle)
      textX += 2
      buffer.setString(textX, y, " ", style)
      textX += 1

    # Draw item text with proper multi-byte character handling
    let maxTextX = popupX + popupWidth - 2
    var currentWidth = 0
    # Adjust maxContentWidth for number prefix (3 chars: "N. ")
    let prefixWidth = if itemIdx < 9: 3 else: 0
    let maxContentWidth = contentWidth - 2 - prefixWidth
      # Leave space for padding and prefix

    for rune in item.title.runes:
      let runeW = runeWidth(rune)
      # Check if we need to truncate (leave space for ellipsis)
      if currentWidth + runeW > maxContentWidth - 1 and
          currentWidth + runeW < displayWidth(item.title):
        # Add ellipsis and stop
        if textX < maxTextX and textX < buffer.area.width:
          buffer.setString(textX, y, "…", style)
        break

      if textX + runeW <= maxTextX and textX < buffer.area.width:
        buffer.setString(textX, y, $rune, style)
        textX += runeW
        currentWidth += runeW
      else:
        break

    # Right border
    if popupX + popupWidth - 1 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 1, y, "│", borderStyle)

  # Draw bottom border with scroll indicator if needed
  let bottomY = popupY + visibleCount + 1
  if bottomY < buffer.area.height:
    buffer.setString(popupX, bottomY, "└", borderStyle)
    for x in 1 ..< popupWidth - 1:
      if popupX + x < buffer.area.width:
        buffer.setString(popupX + x, bottomY, "─", borderStyle)
    # Show scroll down indicator in bottom-right corner
    if hasMoreBelow and popupX + popupWidth - 2 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 2, bottomY, "▼", scrollIndicatorStyle)
    if popupX + popupWidth - 1 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 1, bottomY, "┘", borderStyle)
