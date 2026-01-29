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

## Window split and buffer management procedures

import std/options

import pkg/results

import editor_types, logger, render_utils, sidebar

# Window state management procedures

proc saveActiveWindowState*(e: Editor) =
  ## Save viewport scroll position to the active window before switching
  ## Note: cursor and mode are already stored directly in EditorWindow (single source of truth)
  ## For overlay modes (Command, Search, Rename), save the base mode instead
  ## This preserves the "real" mode (Filer, Normal, etc.) when splitting from command line
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    # Save viewport scroll position from motionController
    e.activeWindow.viewport.topLine =
      e.executer.motionController.viewportManager.viewport.topLine
    e.activeWindow.viewport.leftColumn =
      e.executer.motionController.viewportManager.viewport.leftColumn
    # For overlay modes, save the base mode to the window
    if e.state.hasOverlay:
      e.activeWindow.mode = e.state.baseMode

proc restoreActiveWindowState(e: Editor) =
  ## Restore viewport scroll position from the active window after switching
  ## Note: cursor and mode are accessed directly from EditorWindow
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    # Restore viewport scroll position to motionController
    e.executer.motionController.viewportManager.viewport.topLine =
      e.activeWindow.viewport.topLine
    e.executer.motionController.viewportManager.viewport.leftColumn =
      e.activeWindow.viewport.leftColumn

proc syncActiveWindow*(e: Editor) =
  ## Sync the active window's buffer and viewport with the executor and motion controller
  e.executer.buffer = e.activeWindow.buffer
  e.executer.motionController.executor.buffer = e.activeWindow.buffer
  e.executer.motionController.viewportManager.viewport = e.activeWindow.viewport
  e.restoreActiveWindowState()
  e.state.needsFullRedraw = true

proc calculateReservedLines*(e: Editor, isBottomWindow: bool = true): int =
  ## Calculate number of reserved lines based on status line configuration
  ## and multi-line status messages
  result =
    if e.state.display.showStatusLine:
      if e.state.display.multiStatusLine:
        if isBottomWindow: StatusAndCommandReserve else: StatusLineReserve
      elif isBottomWindow:
        StatusAndCommandReserve
      else:
        0
    else:
      if isBottomWindow: CommandLineReserve else: 0

  # Add extra lines for multi-line status messages (only for bottom window)
  if isBottomWindow:
    result += e.state.statusMessageExtraLines()

proc calculateWindowCursor*(
    e: Editor,
    buffer: TextBuffer,
    viewport: ViewPort,
    cursor: BufferPosition,
    lineNumOffset: int,
    reservedLines: int,
): CursorPosition =
  ## Calculate screen cursor position for a window
  ## Returns the absolute screen coordinates

  # Validate cursor is within buffer bounds
  if cursor.line < 0 or cursor.line >= buffer.len:
    return CursorPosition(x: 0, y: 0)

  # Cursor is above visible area
  if cursor.line < viewport.topLine:
    return CursorPosition(x: 0, y: 0)

  if e.state.display.lineWrap:
    # WRAP MODE: Calculate cursor position considering line wrapping
    let maxWidth = max(1, viewport.width - lineNumOffset)

    var screenY = 0
    let maxVisibleLine = min(cursor.line, viewport.topLine + viewport.height)

    for lineIdx in viewport.topLine ..< maxVisibleLine:
      if lineIdx >= 0 and lineIdx < buffer.len:
        let line = buffer.getLine(lineIdx)
        let lineCharLen = line.charLen

        if lineCharLen == 0:
          screenY += 1
        else:
          let wrappedLines = calculateWrapCount(lineCharLen, maxWidth)
          screenY += wrappedLines

        if screenY >= viewport.height - reservedLines:
          return CursorPosition(x: 0, y: 0)

    let
      cursorLineText = buffer.getLine(cursor.line)
      displayWidthUpToCursor =
        displayWidthUpToWithTabs(cursorLineText, cursor.column, e.state.display.tabStop)
      wrapLineIndex = displayWidthUpToCursor div maxWidth
      wrapLineColumn = displayWidthUpToCursor mod maxWidth

    screenY += wrapLineIndex

    if screenY < viewport.height - reservedLines:
      let finalX = viewport.x + lineNumOffset + wrapLineColumn
      let finalY = viewport.y + screenY
      return CursorPosition(x: finalX, y: finalY)
  else:
    # NO-WRAP MODE: Calculate cursor position with horizontal scrolling
    if cursor.line < viewport.topLine + viewport.height - reservedLines:
      let
        cursorLineText = buffer.getLine(cursor.line)
        displayWidthUpToCursor = displayWidthUpToWithTabs(
          cursorLineText, cursor.column, e.state.display.tabStop
        )
        displayWidthUpToLeftCol = displayWidthUpToWithTabs(
          cursorLineText, viewport.leftColumn, e.state.display.tabStop
        )
        screenY = viewport.y + (cursor.line - viewport.topLine)
        screenX =
          viewport.x + lineNumOffset +
          max(0, displayWidthUpToCursor - displayWidthUpToLeftCol)

      return CursorPosition(x: screenX, y: screenY)

  return CursorPosition(x: 0, y: 0)

proc calculateSidebarWidth*(e: Editor): int =
  ## Calculate the width occupied by the sidebar (0 if disabled)
  if e.state.display.showSidebar: DefaultSidebarWidth else: 0

proc setActiveWindowScreenCursor*(e: Editor, window: EditorWindow) =
  ## Calculate and set screen cursor position for the active window

  # Determine if this window is at the bottom of the screen
  var maxBottomY = 0
  for w in e.windowManager.windows:
    let bottomY = w.viewport.y + w.viewport.height
    if bottomY > maxBottomY:
      maxBottomY = bottomY

  # Calculate tab line offset
  let tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0

  let
    windowBottomY = window.viewport.y + window.viewport.height
    isBottomWindow = (windowBottomY == maxBottomY)
    sidebarWidth = e.calculateSidebarWidth()
    lineNumOffset =
      calculateLineNumOffset(window.buffer, e.state.display.showLineNumbers) +
      sidebarWidth
    reservedLines = e.calculateReservedLines(isBottomWindow)

  var cursorPos = e.calculateWindowCursor(
    window.buffer,
    window.viewport,
    window.cursor,
    lineNumOffset,
    reservedLines + tabLineOffset,
  )
  # Adjust cursor Y for tab line offset
  cursorPos.y += tabLineOffset
  e.state.screenCursor = cursorPos
  # Note: cursorVisible is set by each mode's render function

# Window split procedures

proc vsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a vertical split window
  # Save current window state before splitting
  e.saveActiveWindowState()

  let bufferResult =
    e.windowManager.vsplit(e.textBuffer, e.viewport, e.cursor, filename)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  var found = false
  for buf in e.buffers:
    if buf == newBuffer:
      found = true
      break
  if not found:
    e.buffers.add(newBuffer)
    # Set reserved words for syntax highlighting on new buffer
    newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
    logDebug("editor", "vsplit: buffer added, buffers.len: " & $e.buffers.len)

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # New window is in Normal mode, so update state to match
  # This ensures command handler returns to Normal mode, not the previous special mode
  e.setMode(EditorMode.Normal)
  e.state.previousMode = EditorMode.Normal

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  ok(())

proc vsplitWithBuffer*(e: Editor, buffer: TextBuffer): Result[(), string] =
  ## Create a vertical split window with a specific buffer
  # Save current window state before splitting
  e.saveActiveWindowState()

  let bufferResult =
    e.windowManager.vsplitWithBuffer(e.textBuffer, e.viewport, e.cursor, buffer)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  var found = false
  for buf in e.buffers:
    if buf == newBuffer:
      found = true
      break
  if not found:
    e.buffers.add(newBuffer)
    # Set reserved words for syntax highlighting on new buffer
    newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
    logDebug("editor", "vsplitWithBuffer: buffer added, buffers.len: " & $e.buffers.len)

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # New window is in Normal mode, so update state to match
  # This ensures command handler returns to Normal mode, not the previous special mode
  e.setMode(EditorMode.Normal)
  e.state.previousMode = EditorMode.Normal

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  ok(())

proc hsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a horizontal split window (top and bottom)
  # Save current window state before splitting
  e.saveActiveWindowState()

  let bufferResult = e.windowManager.hsplit(
    e.textBuffer, e.viewport, e.cursor, e.state.display.multiStatusLine, filename
  )
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  var found = false
  for buf in e.buffers:
    if buf == newBuffer:
      found = true
      break
  if not found:
    e.buffers.add(newBuffer)
    # Set reserved words for syntax highlighting on new buffer
    newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
    logDebug("editor", "hsplit: buffer added, buffers.len: " & $e.buffers.len)

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # New window is in Normal mode, so update state to match
  # This ensures command handler returns to Normal mode, not the previous special mode
  e.setMode(EditorMode.Normal)
  e.state.previousMode = EditorMode.Normal

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  ok(())

proc hsplitWithBuffer*(e: Editor, buffer: TextBuffer): Result[(), string] =
  ## Create a horizontal split window with a specific buffer
  # Save current window state before splitting
  e.saveActiveWindowState()

  let bufferResult = e.windowManager.hsplitWithBuffer(
    e.textBuffer, e.viewport, e.cursor, e.state.display.multiStatusLine, buffer
  )
  if bufferResult.isErr:
    return err(bufferResult.error)

  logDebug(
    "editor",
    "hsplitWithBuffer: after wm.hsplitWithBuffer, activeWindowIndex=" &
      $e.windowManager.activeWindowIndex & " windows.len=" & $e.windowManager.windows.len,
  )

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  var found = false
  for buf in e.buffers:
    if buf == newBuffer:
      found = true
      break
  if not found:
    e.buffers.add(newBuffer)
    # Set reserved words for syntax highlighting on new buffer
    newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
    logDebug("editor", "hsplitWithBuffer: buffer added, buffers.len: " & $e.buffers.len)

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # New window is in Normal mode, so update state to match
  # This ensures command handler returns to Normal mode, not the previous special mode
  e.setMode(EditorMode.Normal)
  e.state.previousMode = EditorMode.Normal

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  ok(())

proc enew*(e: Editor): Result[(), string] =
  ## Create a new empty buffer and add it to the buffer list
  let newBuffer = newTextBuffer()

  # Add the new buffer to the buffer list
  e.buffers.add(newBuffer)
  # Set reserved words for syntax highlighting on new buffer
  newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
  logDebug("editor", "enew: buffer added, buffers.len: " & $e.buffers.len)

  # Replace the buffer in the active window
  e.activeWindow.buffer = newBuffer
  e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
  e.activeWindow.viewport.topLine = 0
  e.activeWindow.viewport.leftColumn = 0

  # Update executor and motion controller references
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer
  e.executer.motionController.viewportManager.viewport = e.activeWindow.viewport

  # Reset cursor
  e.cursor = BufferPosition(line: 0, column: 0)

  e.state.needsFullRedraw = true
  ok(())

proc new*(e: Editor): Result[(), string] =
  ## Create a new empty buffer in a horizontal split (like :new in Vim)
  let newBuffer = newTextBuffer()
  return e.hsplitWithBuffer(newBuffer)

proc vnew*(e: Editor): Result[(), string] =
  ## Create a new empty buffer in a vertical split (like :vnew in Vim)
  let newBuffer = newTextBuffer()
  return e.vsplitWithBuffer(newBuffer)

# Window navigation procedures

proc switchToNextWindow*(e: Editor) =
  ## Switch to the next window (Ctrl-w, k)
  if e.windowManager.windows.len <= 1:
    return

  # Save current window state before switching
  e.saveActiveWindowState()

  # Switch to next window using window manager
  e.windowManager.switchToNextWindow()

  # Sync and restore the new active window state
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

proc switchToPrevWindow*(e: Editor) =
  ## Switch to the previous window (Ctrl-w, j)
  if e.windowManager.windows.len <= 1:
    return

  # Save current window state before switching
  e.saveActiveWindowState()

  # Switch to previous window using window manager
  e.windowManager.switchToPrevWindow()

  # Sync and restore the new active window state
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

proc closeWindow*(e: Editor): bool =
  ## Close the active window
  ## Returns true if editor should quit (last window closed)

  logDebug(
    "editor",
    "closeWindow called: windows.len=" & $e.windowManager.windows.len &
      " activeWindowIndex=" & $e.windowManager.activeWindowIndex,
  )

  let shouldQuit = e.windowManager.closeWindow(e.state.display.multiStatusLine)

  if shouldQuit:
    return true

  # Sync to the new active window
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  return false
