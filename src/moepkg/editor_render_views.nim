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
  editor_types, editor_window, editor_window_layout, editor_render_window,
  editor_render_modes, render_utils, status_line, tab_line, buffer, unicode_utils

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
    textBuffer: TextBuffer = nil,
    tabStop: int = 4,
) =
  ## Adjust viewport to keep cursor visible (scroll if cursor is off-screen)
  # Vertical adjustment
  if lineWrap and not textBuffer.isNil:
    let maxWidth = max(1, textAreaWidth)

    if cursor.line < viewport.topLine:
      viewport.topLine = cursor.line
    else:
      # Count screen lines from topLine through cursor.line (inclusive)
      var totalScreenLines = 0
      for lineIdx in viewport.topLine .. min(cursor.line, textBuffer.len - 1):
        totalScreenLines +=
          calculateWrapCount(textBuffer.getLine(lineIdx), maxWidth, tabStop)

      if totalScreenLines > visibleHeight:
        # Cursor is below viewport — scroll down incrementally (O(n))
        var newTopLine = viewport.topLine
        while totalScreenLines > visibleHeight and newTopLine < cursor.line:
          totalScreenLines -=
            calculateWrapCount(textBuffer.getLine(newTopLine), maxWidth, tabStop)
          newTopLine += 1
        viewport.topLine = newTopLine
  else:
    if cursor.line >= viewport.topLine + visibleHeight:
      viewport.topLine = max(0, cursor.line - visibleHeight + 1)
    elif cursor.line < viewport.topLine:
      viewport.topLine = cursor.line

  # Horizontal adjustment (only when line wrap is disabled)
  if not lineWrap:
    if cursor.column >= viewport.leftColumn + textAreaWidth:
      viewport.leftColumn = max(0, cursor.column - textAreaWidth + 1)
    elif cursor.column < viewport.leftColumn:
      viewport.leftColumn = cursor.column

proc renderSplitView*(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render split window view

  # If terminal was resized, rebuild window layout
  if wasResized and e.screenSize.prevWidth > 0 and e.screenSize.prevHeight > 0 and
      e.screenSize.width > 0 and e.screenSize.height > 0:
    # Note: cursor is now stored directly in EditorWindow (single source of truth)

    e.windowManager.resizeWindows(
      e.screenSize.width, e.screenSize.height, e.screenSize.prevWidth,
      e.screenSize.prevHeight, e.state.display.multiStatusLine,
    )

  # Find the maximum bottom Y coordinate (to determine bottom windows)
  let maxBottomY = findMaxBottomY(e.windowManager.windows)

  # Calculate tab line offset (1 if tab line is shown, 0 otherwise)
  let tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0

  # Render all split windows
  for i, window in e.windowManager.windows:
    # Calculate line number offset dynamically based on buffer size
    let lineNumOffset =
      calculateLineNumOffset(window.buffer, e.state.display.showLineNumbers)

    # Determine if this is a bottom window (needs status line reservation)
    # A window is a bottom window if its bottom edge is at the maximum bottom Y
    let
      windowBottomY = window.viewport.y + window.viewport.height
      isBottomWindow = (windowBottomY == maxBottomY)
      isActiveWindow = (i == e.windowManager.activeWindowIndex)
      reservedLines = e.calculateReservedLines(isBottomWindow)
      visibleHeight = max(1, window.viewport.height - reservedLines - tabLineOffset)
      sidebarWidth = e.calculateSidebarWidth(window.mode)
      scrollbarWidth = e.calculateScrollbarWidth(window.mode)
      textAreaWidth =
        max(0, window.viewport.width - sidebarWidth - scrollbarWidth - lineNumOffset)

    # Adjust viewport to keep cursor visible
    adjustViewportForCursor(
      window.viewport, window.cursor, visibleHeight, textAreaWidth,
      e.state.display.lineWrap, window.buffer, e.state.display.tabStop,
    )

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
        isActiveWindow,
      )

    # Render window content based on window's mode
    # Special modes only render when active (they use activeWindow state internally)
    # For overlay modes (Command, Search, Rename), use the base mode for background rendering
    let renderMode =
      if isActiveWindow and e.state.hasOverlay:
        e.state.baseMode # Use the underlying mode when overlay is active
      else:
        window.mode

    # Render based on mode - some special modes support per-window rendering
    case renderMode
    of EditorMode.Filer:
      # Filer uses virtual buffer pattern (like BufferManager)
      if window.modeState.kind == mskFiler:
        window.cursor.line = window.modeState.filer.selectedIndex
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.Config:
      # Config supports per-window rendering
      e.renderConfig(buffer, window, isBottomWindow, tabLineOffset)
    of EditorMode.Help:
      # Sync help viewer selection to window cursor
      if window.modeState.kind == mskHelp:
        window.cursor.line = window.modeState.help.selectedIndex
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.BufferManager:
      # Sync buffer manager selection to window cursor (header at line 0)
      if window.modeState.kind == mskBufferManager:
        window.cursor.line = window.modeState.bufferManager.selectedIndex + 1
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.BookmarkManager:
      # Sync bookmark manager selection to window cursor (header at line 0)
      if window.modeState.kind == mskBookmarkManager:
        window.cursor.line = window.modeState.bookmarkManager.selectedIndex + 1
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.BackupManager:
      # Sync backup manager selection to window cursor (header at line 0)
      if window.modeState.kind == mskBackupManager:
        window.cursor.line = window.modeState.backupManager.selectedIndex + 1
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.DiffViewer:
      # Sync diff viewer selection to window cursor for normal view rendering
      if window.modeState.kind == mskDiffViewer:
        window.cursor.line = window.modeState.diffViewer.selectedLine
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.Debug:
      # Sync debug viewer selection to window cursor
      if window.modeState.kind == mskDebug:
        window.cursor.line = window.modeState.debug.selectedLine
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.References:
      # Sync references selection to window cursor (header at line 0)
      if window.modeState.kind == mskReferences:
        window.cursor.line = window.modeState.references.selectedIndex + 1
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.DocumentSymbol:
      # Sync document symbol selection to window cursor (header at line 0)
      if window.modeState.kind == mskDocumentSymbol:
        window.cursor.line = window.modeState.documentSymbol.selectedIndex + 1
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.CallHierarchy:
      # Sync call hierarchy selection to window cursor (header at line 0)
      if window.modeState.kind == mskCallHierarchy:
        window.cursor.line = window.modeState.callHierarchy.selectedIndex + 1
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.RecentFile:
      # Sync recent file selection to window cursor (header at line 0)
      if window.modeState.kind == mskRecentFile:
        window.cursor.line = window.modeState.recentFile.selectedIndex + 1
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    of EditorMode.Terminal:
      # Terminal mode renders grid directly in Input sub-mode,
      # or uses standard window rendering in Normal sub-mode
      if window.modeState.kind == mskTerminal and
          window.modeState.terminal.subMode == tsmInput:
        e.renderTerminal(buffer, window, isBottomWindow, tabLineOffset)
      else:
        e.renderWindow(
          buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
        )
    of EditorMode.FileTree:
      # FileTree uses virtual buffer pattern (like Filer)
      if window.modeState.kind == mskFileTree:
        window.cursor.line = window.modeState.fileTree.selectedIndex
        window.cursor.column = 0
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )
    else:
      # Normal buffer rendering (Normal, Insert, Visual, Command, Search, etc.)
      e.renderWindow(
        buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
      )

    # Render per-window status line if multi-status line mode is enabled
    # (and merge is disabled - merge shows only one status line at bottom)
    if e.state.display.showStatusLine and e.state.display.multiStatusLine and
        not e.config.statusLine.merge:
      let statusLineY = calculateWindowStatusLineY(window, isBottomWindow)
      e.state.renderWindowStatusLine(
        window.buffer, buffer, statusLineY, window.viewport.x, window.viewport.width,
        isActiveWindow, window.mode, e.config.statusLine,
      )

    # Draw separator between windows (except for last window)
    if i < e.windowManager.windows.len - 1:
      let nextWindow = e.windowManager.windows[i + 1]
      e.renderWindowSeparator(buffer, window, nextWindow, isBottomWindow)

  # Set cursor to active window position
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    # Terminal-Input mode manages its own screen cursor from the grid,
    # so skip the standard cursor calculation that would overwrite it.
    let isTerminalInput =
      e.activeWindow.mode == EditorMode.Terminal and
      e.activeWindow.modeState.kind == mskTerminal and
      e.activeWindow.modeState.terminal.subMode == tsmInput

    if not isTerminalInput:
      e.setActiveWindowScreenCursor(e.activeWindow)

    # Set cursor visibility based on mode
    # Special modes (Filer, Config, etc.) set cursorVisible in their render functions
    # Normal modes need cursor visible
    case e.activeWindow.mode
    of EditorMode.Filer:
      e.state.cursorVisible = e.state.hasOverlay
    of EditorMode.Config:
      # Config mode sets cursorVisible in renderWindowConfig based on edit state
      discard
    of EditorMode.BufferManager, EditorMode.BookmarkManager, EditorMode.Help,
        EditorMode.BackupManager, EditorMode.DiffViewer, EditorMode.Debug,
        EditorMode.References, EditorMode.DocumentSymbol, EditorMode.CallHierarchy,
        EditorMode.RecentFile, EditorMode.FileTree:
      # Show cursor when an overlay (command/search/rename) is active
      e.state.cursorVisible = e.state.hasOverlay
    of EditorMode.Terminal:
      # Terminal mode sets cursorVisible in renderTerminal
      discard
    else:
      # Normal, Insert, Visual, etc. - cursor should be visible
      e.state.cursorVisible = true

proc renderBottomLines*(e: Editor, buffer: var Buffer) =
  ## Render status line and command line at the bottom of the screen.
  ## The status line and command line share the last row (y = height - 1).
  ## When a command/search/rename overlay is active, it overwrites the status line.
  let bottomY = buffer.area.y + buffer.area.height - 1

  # Render global status line at the bottom:
  # - When multiStatusLine is disabled: single status line for all windows
  # - When merge is enabled: merged status line at bottom
  # When multiStatusLine is enabled (and merge is off), per-window status lines
  # are rendered in renderSplitView instead.
  if not e.state.display.multiStatusLine or e.config.statusLine.merge:
    e.state.renderStatusLine(e.activeBuffer(), buffer, bottomY, e.config.statusLine)

  # Handle command line based on overlay state.
  # Overlays render at the same bottomY, overwriting the status line.
  if e.state.isCommandOverlay:
    buffer.setString(buffer.area.x, bottomY, e.state.commandText, commandStyle())
    # Cursor position: display width of commandText up to cursor
    e.state.screenCursor.x =
      displayWidthUpTo(e.state.commandText, e.state.commandCursor + 1)
    e.state.screenCursor.y = bottomY

    # Render command completion popup if active
    if e.state.commandCompletionManager.isActive():
      let popupPos = calculateCommandPopupPosition(
        e.state.commandCursor, buffer.area.width, buffer.area.height,
        e.state.commandCompletionManager.menu.entries,
        e.state.commandCompletionManager.menu.maxVisible,
        e.state.commandCompletionManager.argStartX,
      )
      renderCommandCompletionPopup(
        buffer, e.state.commandCompletionManager.menu, popupPos
      )
  elif e.state.isSearchOverlay:
    let searchChar = if e.state.search.direction == Forward: "/" else: "?"
    let searchPrompt = searchChar & e.state.search.text
    buffer.setString(buffer.area.x, bottomY, searchPrompt, commandStyle())
    # Cursor position: 1 for the prompt char ("/" or "?", always ASCII)
    # plus the display width of the search text up to the cursor.
    e.state.screenCursor.x =
      1 + displayWidthUpTo(e.state.search.text, e.state.search.cursor)
    e.state.screenCursor.y = bottomY
  elif e.state.isRenameOverlay:
    let renamePrompt = "Rename: " & e.state.renameState.text
    buffer.setString(buffer.area.x, bottomY, renamePrompt, commandStyle())
    e.state.screenCursor.x = displayWidth(renamePrompt)
    e.state.screenCursor.y = bottomY
  else:
    let lineCount = e.state.statusMessageLineCount()
    if lineCount == 1:
      # Single line: overwrite the status line
      buffer.setString(buffer.area.x, bottomY, e.state.statusMessage, commandStyle())
    elif lineCount > 1:
      # Multi-line: move status line up, expand message area downward to bottomY
      let
        allLines = e.state.statusMessage.split('\n')
        # Limit to MaxStatusMessageLines, show last N lines if exceeded
        lines =
          if allLines.len > MaxStatusMessageLines:
            allLines[allLines.len - MaxStatusMessageLines .. ^1]
          else:
            allLines
        # Status line moves up to make room for all message lines
        newStatusLineY = max(0, buffer.area.height - 1 - lines.len)
        messageStartY = newStatusLineY + 1

      # Re-render status line at new position
      e.state.renderStatusLine(
        e.activeBuffer(), buffer, newStatusLineY, e.config.statusLine
      )

      # Render message lines from messageStartY to bottomY
      for i, line in lines:
        let y = messageStartY + i
        if y >= messageStartY and y <= bottomY:
          buffer.setString(
            buffer.area.x, y, " ".repeat(buffer.area.width), commandStyle()
          )
          buffer.setString(buffer.area.x, y, line, commandStyle())

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
    # White background style for border
    whiteBorderStyle = Style(
      fg: ColorValue(kind: Default),
      bg: ColorValue(kind: Indexed, indexed: Color.White),
      modifiers: {},
    )
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

  # Position cursor at the end of the prompt
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = promptY

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

  # Define styles
  let
    borderStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
      bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 30, g: 30, b: 30)),
      modifiers: {},
    )
    popupNormalStyle = Style(
      fg: ColorValue(kind: Default),
      bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 30, g: 30, b: 30)),
      modifiers: {},
    )
    selectedStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.Black),
      bg: ColorValue(kind: Indexed, indexed: Color.Cyan),
      modifiers: {},
    )
    scrollIndicatorStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
      bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 30, g: 30, b: 30)),
      modifiers: {},
    )

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
        fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
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
