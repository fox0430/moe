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

import std/[options, strutils]

import pkg/celina

import
  editor_types, editor_window, editor_render_window, render_utils, statusline,
  tabline, sidebar

proc updateViewportSize*(e: Editor, buffer: Buffer): bool =
  ## Update viewport size from buffer area and return true if resized
  let
    oldWidth = e.viewport.width
    oldHeight = e.viewport.height

  e.viewport.width = buffer.area.width
  e.viewport.height = buffer.area.height

  (oldWidth != e.viewport.width) or (oldHeight != e.viewport.height)

proc renderSplitView*(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render split window view
  let
    oldWidth = e.viewport.width
    oldHeight = e.viewport.height

  # If terminal was resized, rebuild window layout
  if wasResized and oldWidth > 0 and oldHeight > 0 and e.viewport.width > 0 and
      e.viewport.height > 0:
    # Save current state to window before resize
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      e.windowManager.windows[e.windowManager.activeWindowIndex].cursor = e.state.cursor

    e.windowManager.resizeWindows(
      e.viewport.width, e.viewport.height, oldWidth, oldHeight,
      e.state.display.multiStatusLine,
    )

    # After resize, restore viewport scroll position from window to motion controller
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
      e.executer.motionController.viewportManager.viewport.topLine =
        activeWindow.viewport.topLine
      e.executer.motionController.viewportManager.viewport.leftColumn =
        activeWindow.viewport.leftColumn
  else:
    # Normal case: sync active window's cursor with state cursor
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      # Update window cursor from editor state
      e.windowManager.windows[e.windowManager.activeWindowIndex].cursor = e.state.cursor

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

    # Render tab line for this window if enabled
    if e.state.display.showTabLine:
      let buffersToShow =
        if e.buffers.len > 0:
          e.buffers
        else:
          @[e.textBuffer]
      renderWindowTabLine(
        buffersToShow, window.buffer, buffer, window.viewport.y, window.viewport.x,
        window.viewport.width, e.state.display.showTabLine,
      )

    # Render window (LogViewer uses normal buffer rendering now)
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
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

proc renderSingleViewSidebar(
    buffer: var Buffer, sidebar: Sidebar, sidebarLineIndex: int, screenY: int
) =
  ## Render a single line of the sidebar for single view mode
  ## sidebarLineIndex: index into sidebar.buffer (logical line based)
  ## screenY: actual screen Y coordinate for rendering
  if sidebarLineIndex >= 0 and sidebarLineIndex < sidebar.buffer.len:
    for x in 0 ..< sidebar.width:
      let item = sidebar.buffer[sidebarLineIndex][x]
      if x < buffer.area.width and screenY < buffer.area.height:
        buffer.setString(x, screenY, item.text, item.style)

proc renderSingleView*(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render single buffer view (no split windows)
  # Sync viewport with motion controller (both directions)
  e.executer.motionController.viewportManager.viewport.width = e.viewport.width
  e.executer.motionController.viewportManager.viewport.height = e.viewport.height
  e.viewport = e.executer.motionController.viewportManager.viewport

  # Calculate tab line offset (1 if tab line is shown, 0 otherwise)
  let tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0

  let
    reservedLines = e.calculateReservedLines(isBottomWindow = true)
    sidebarWidth = e.calculateSidebarWidth()
    lineNumOffset =
      calculateLineNumOffset(e.textBuffer, e.state.display.showLineNumbers)
    textAreaWidth =
      max(0, buffer.area.width - sidebarWidth - lineNumOffset - LineNumberPadding)
    textArea = Rect(
      x: buffer.area.x + sidebarWidth + lineNumOffset,
      y: buffer.area.y + tabLineOffset,
      width: max(0, buffer.area.width - sidebarWidth - lineNumOffset),
      height: max(0, buffer.area.height - reservedLines - tabLineOffset),
    )

  # Calculate visible height accounting for tab line
  let visibleHeight = max(1, buffer.area.height - reservedLines - tabLineOffset)

  # Generate sidebar dynamically from buffer markers if enabled
  let maybeSidebar =
    if e.state.display.showSidebar:
      some(generateSidebarFromBuffer(e.textBuffer, e.viewport.topLine, visibleHeight))
    else:
      none(Sidebar)

  # If terminal was resized, adjust viewport to keep cursor visible
  if wasResized:
    # If cursor is now below the visible area, adjust topLine
    if e.state.cursor.line >= e.viewport.topLine + visibleHeight:
      let newTopLine = max(0, e.state.cursor.line - visibleHeight + 1)
      e.viewport.topLine = newTopLine
      e.executer.motionController.viewportManager.viewport.topLine = newTopLine
    # If cursor is above the visible area
    elif e.state.cursor.line < e.viewport.topLine:
      e.viewport.topLine = e.state.cursor.line
      e.executer.motionController.viewportManager.viewport.topLine = e.state.cursor.line

  # Render sidebar if enabled (with line wrap support)
  if maybeSidebar.isSome:
    let sidebar = maybeSidebar.get
    var screenY = tabLineOffset
    var lineIndex = e.viewport.topLine
    while screenY < buffer.area.height - reservedLines and lineIndex < e.textBuffer.len:
      let sidebarLineIndex = lineIndex - e.viewport.topLine

      if e.state.display.lineWrap:
        let
          line = e.textBuffer.getLine(lineIndex)
          lineCharLen = line.charLen
          numWraps = calculateWrapCount(lineCharLen, textAreaWidth)

        # Render sidebar marker for first screen line of this logical line
        renderSingleViewSidebar(buffer, sidebar, sidebarLineIndex, screenY)
        inc screenY

        # For wrapped continuation lines, render empty sidebar
        for _ in 1 ..< numWraps:
          if screenY >= buffer.area.height - reservedLines:
            break
          inc screenY
      else:
        renderSingleViewSidebar(buffer, sidebar, sidebarLineIndex, screenY)
        inc screenY

      inc lineIndex

  # Render line numbers only if enabled
  if e.state.display.showLineNumbers:
    discard e.renderLineNumbers(buffer, textAreaWidth, sidebarWidth, tabLineOffset)
  e.renderTextBuffer(buffer, textArea)

  # Calculate and set cursor position (including sidebar width)
  var cursorPos = e.calculateWindowCursor(
    e.textBuffer,
    e.viewport,
    e.state.cursor,
    sidebarWidth + lineNumOffset,
    reservedLines + tabLineOffset,
  )
  # Adjust cursor Y for tab line offset
  cursorPos.y += tabLineOffset
  e.state.screenCursor = cursorPos

proc renderBottomLines*(e: Editor, buffer: var Buffer) =
  ## Render status line and command line at the bottom of the screen
  let
    statusLineY = buffer.area.y + buffer.area.height - 2
    commandLineY = buffer.area.y + buffer.area.height - 1

  # Render status line using active buffer
  # - Single window mode: always render status line at bottom
  # - Multi-window mode: only render if multiStatusLine is disabled OR merge is enabled
  if e.windowManager.windows.len == 0 or not e.state.display.multiStatusLine or
      e.config.statusLine.merge:
    e.state.renderStatusLine(e.activeBuffer(), buffer, statusLineY, e.config.statusLine)

  # Handle command line
  if e.state.mode == EditorMode.Command:
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
  elif e.state.mode == EditorMode.Search:
    let searchChar = if e.state.search.direction == Forward: "/" else: "?"
    let searchPrompt = searchChar & e.state.search.text
    buffer.setString(buffer.area.x, commandLineY, searchPrompt, commandStyle())
    e.state.screenCursor.x = searchPrompt.len
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
