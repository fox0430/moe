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

import std/strutils

import pkg/celina

import
  editor_types, editor_window, editor_render_window, editor_render_modes, render_utils,
  status_line, tab_line, buffer

proc updateViewportSize*(e: Editor, buffer: Buffer): bool =
  ## Update viewport size from buffer area and return true if resized
  let
    oldWidth = e.viewport.width
    oldHeight = e.viewport.height

  e.viewport.width = buffer.area.width
  e.viewport.height = buffer.area.height

  (oldWidth != e.viewport.width) or (oldHeight != e.viewport.height)

proc adjustViewportForCursor(
    viewport: var ViewPort,
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

  # For single window mode, sync window viewport size with editor viewport
  # This ensures the window has the correct screen size (especially on first render)
  # Also sync motionController viewport since ViewPort is a value type (copies on assignment)
  if e.windowManager.windows.len == 1:
    let window = e.windowManager.windows[0]
    if window.viewport.width != e.viewport.width or
        window.viewport.height != e.viewport.height:
      window.viewport.width = e.viewport.width
      window.viewport.height = e.viewport.height
      # Also update motionController viewport size (ViewPort is value type, not shared)
      e.executer.motionController.viewportManager.viewport.width = e.viewport.width
      e.executer.motionController.viewportManager.viewport.height = e.viewport.height

  let
    oldWidth = e.viewport.width
    oldHeight = e.viewport.height

  # If terminal was resized, rebuild window layout
  if wasResized and oldWidth > 0 and oldHeight > 0 and e.viewport.width > 0 and
      e.viewport.height > 0:
    # Note: cursor is now stored directly in EditorWindow (single source of truth)

    e.windowManager.resizeWindows(
      e.viewport.width, e.viewport.height, oldWidth, oldHeight,
      e.state.display.multiStatusLine,
    )

    # After resize, sync viewport from window to motion controller
    # (ViewPort is value type, so must sync all fields)
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      e.executer.motionController.viewportManager.viewport.topLine =
        e.activeWindow.viewport.topLine
      e.executer.motionController.viewportManager.viewport.leftColumn =
        e.activeWindow.viewport.leftColumn
      e.executer.motionController.viewportManager.viewport.width =
        e.activeWindow.viewport.width
      e.executer.motionController.viewportManager.viewport.height =
        e.activeWindow.viewport.height
  # Note: In normal case, cursor is already in EditorWindow (single source of truth)

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
      sidebarWidth = e.calculateSidebarWidth()
      textAreaWidth = max(0, window.viewport.width - sidebarWidth - lineNumOffset)

    # Adjust viewport to keep cursor visible
    adjustViewportForCursor(
      window.viewport, window.cursor, visibleHeight, textAreaWidth,
      e.state.display.lineWrap, window.buffer, e.state.display.tabStop,
    )

    # Render tab line for this window if enabled
    # Use window-local buffer list (per-window tabs)
    if e.state.display.showTabLine:
      let buffersToShow =
        if window.bufferList.len > 0:
          window.bufferList
        else:
          @[window.buffer]
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
      # Filer supports per-window rendering
      e.renderFiler(buffer, window, isBottomWindow, tabLineOffset)
    of EditorMode.Config:
      # Config supports per-window rendering
      e.renderConfig(buffer, window, isBottomWindow, tabLineOffset)
    of EditorMode.BufferManager:
      # These modes use activeWindow internally, only render when active
      if isActiveWindow:
        e.renderBufferManager(buffer)
      else:
        e.renderWindow(
          buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
        )
    of EditorMode.Help:
      # Help supports per-window rendering
      e.renderHelpViewer(buffer, window, isBottomWindow, tabLineOffset)
    of EditorMode.BackupManager:
      if isActiveWindow:
        e.renderBackupManager(buffer)
      else:
        e.renderWindow(
          buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
        )
    of EditorMode.DiffViewer:
      if isActiveWindow:
        e.renderDiffViewer(buffer)
      else:
        e.renderWindow(
          buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
        )
    of EditorMode.Debug:
      e.renderDebugMode(buffer, window, isBottomWindow, tabLineOffset)
    of EditorMode.References:
      if isActiveWindow:
        e.renderReferencesViewer(buffer)
      else:
        e.renderWindow(
          buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
        )
    of EditorMode.DocumentSymbol:
      if isActiveWindow:
        e.renderDocumentSymbolViewer(buffer)
      else:
        e.renderWindow(
          buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
        )
    of EditorMode.CallHierarchy:
      if isActiveWindow:
        e.renderCallHierarchyViewer(buffer)
      else:
        e.renderWindow(
          buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
        )
    of EditorMode.RecentFile:
      if isActiveWindow:
        e.renderRecentFileMode(buffer)
      else:
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
        isActiveWindow, e.config.statusLine,
      )

    # Draw separator between windows (except for last window)
    if i < e.windowManager.windows.len - 1:
      let nextWindow = e.windowManager.windows[i + 1]
      e.renderWindowSeparator(buffer, window, nextWindow, isBottomWindow)

  # Set cursor to active window position
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

    # Set cursor visibility based on mode
    # Special modes (Filer, Config, etc.) set cursorVisible in their render functions
    # Normal modes need cursor visible
    case e.activeWindow.mode
    of EditorMode.Filer:
      e.state.cursorVisible = false
    of EditorMode.Config:
      # Config mode sets cursorVisible in renderWindowConfig based on edit state
      discard
    of EditorMode.BufferManager, EditorMode.Help, EditorMode.BackupManager,
        EditorMode.DiffViewer, EditorMode.Debug, EditorMode.References,
        EditorMode.DocumentSymbol, EditorMode.CallHierarchy, EditorMode.RecentFile:
      e.state.cursorVisible = false
    else:
      # Normal, Insert, Visual, etc. - cursor should be visible
      e.state.cursorVisible = true

proc renderBottomLines*(e: Editor, buffer: var Buffer) =
  ## Render status line and command line at the bottom of the screen
  let
    statusLineY = buffer.area.y + buffer.area.height - 2
    commandLineY = buffer.area.y + buffer.area.height - 1

  # Render status line using active buffer
  # - Single window mode: always render status line at bottom
  # - Multi-window mode: only render if multiStatusLine is disabled OR merge is enabled
  if e.windowManager.windows.len == 1 or not e.state.display.multiStatusLine or
      e.config.statusLine.merge:
    e.state.renderStatusLine(e.activeBuffer(), buffer, statusLineY, e.config.statusLine)

  # Handle command line based on overlay state
  if e.state.isCommandOverlay:
    buffer.setString(buffer.area.x, commandLineY, e.state.commandText, commandStyle())
    # Cursor position: ":" + commandCursor (0-based after ":")
    e.state.screenCursor.x = 1 + e.state.commandCursor
    e.state.screenCursor.y = buffer.area.height - 1

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
    buffer.setString(buffer.area.x, commandLineY, searchPrompt, commandStyle())
    e.state.screenCursor.x = searchPrompt.len
    e.state.screenCursor.y = buffer.area.height - 1
  elif e.state.isRenameOverlay:
    let renamePrompt = "Rename: " & e.state.renameState.text
    buffer.setString(buffer.area.x, commandLineY, renamePrompt, commandStyle())
    e.state.screenCursor.x = renamePrompt.len
    e.state.screenCursor.y = buffer.area.height - 1
  else:
    let lineCount = e.state.statusMessageLineCount()
    if lineCount == 1:
      # Single line: render as before
      buffer.setString(
        buffer.area.x, commandLineY, e.state.statusMessage, commandStyle()
      )
    elif lineCount > 1:
      # Multi-line: move status line up, expand command line area
      let
        allLines = e.state.statusMessage.split('\n')
        # Limit to MaxStatusMessageLines, show last N lines if exceeded
        lines =
          if allLines.len > MaxStatusMessageLines:
            allLines[allLines.len - MaxStatusMessageLines .. ^1]
          else:
            allLines
        extraLines = lines.len - 1
        newStatusLineY = max(0, statusLineY - extraLines)
        messageStartY = newStatusLineY + 1

      # Re-render status line at new position
      e.state.renderStatusLine(
        e.activeBuffer(), buffer, newStatusLineY, e.config.statusLine
      )

      # Render message lines from messageStartY to commandLineY
      for i, line in lines:
        let y = messageStartY + i
        if y >= messageStartY and y <= commandLineY:
          buffer.setString(
            buffer.area.x, y, " ".repeat(buffer.area.width), commandStyle()
          )
          buffer.setString(buffer.area.x, y, line, commandStyle())

proc renderTempMessages*(e: Editor, buffer: var Buffer) =
  ## Render temporary messages at the bottom of screen (like Vim's :jumps output)
  ## Overwrites the buffer content from bottom up, with a border at top
  if e.state.tempMessages.len == 0:
    return

  let
    # +2 for border line and "Press ENTER..." prompt
    totalLines = e.state.tempMessages.len + 2
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
  for i, msg in e.state.tempMessages:
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
