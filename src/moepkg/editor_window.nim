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
  ## Save mode state to the active window before switching
  ## Note: cursor and mode are already stored directly in EditorWindow (single source of truth)
  ## Viewport is shared by reference, so no field copying is needed
  ## For overlay modes (Command, Search, Rename), save the base mode instead
  ## This preserves the "real" mode (Filer, Normal, etc.) when splitting from command line
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    # For overlay modes, save the base mode to the window
    if e.state.hasOverlay:
      e.activeWindow.mode = e.state.baseMode

proc restoreActiveWindowState(e: Editor) =
  ## Share the active window's viewport reference with motionController and editor
  ## Note: cursor and mode are accessed directly from EditorWindow
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.executer.motionController.viewportManager.viewport = e.activeWindow.viewport
    e.viewport = e.activeWindow.viewport

proc syncActiveWindow*(e: Editor) =
  ## Sync the active window's buffer and viewport with the executor and motion controller
  ## Viewport is shared by reference - reassigning shares the active window's viewport
  e.executer.buffer = e.activeWindow.buffer
  e.executer.motionController.executor.buffer = e.activeWindow.buffer
  e.executer.motionController.viewportManager.viewport = e.activeWindow.viewport
  e.viewport = e.activeWindow.viewport
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

        let wrappedLines = calculateWrapCount(line, maxWidth, e.state.display.tabStop)
        screenY += wrappedLines

        if screenY >= viewport.height - reservedLines:
          return CursorPosition(x: 0, y: 0)

    let
      cursorLineText = buffer.getLine(cursor.line)
      (wrapLineIndex, wrapLineColumn) = cursorWrapPosition(
        cursorLineText, cursor.column, maxWidth, e.state.display.tabStop
      )

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

proc calculateSidebarWidth*(e: Editor, mode: EditorMode): int =
  ## Calculate the width occupied by the sidebar (0 if disabled)
  if mode.isFileEditMode and e.state.display.showSidebar: DefaultSidebarWidth else: 0

proc restoreOriginalBuffer*(win: EditorWindow, mode: EditorMode) =
  ## Restore the original buffer for modes that replace the window buffer.
  case mode
  of EditorMode.Filer:
    if win.filerState.isSome and win.filerState.get.originalBuffer != nil:
      win.buffer = win.filerState.get.originalBuffer
  of EditorMode.BufferManager:
    if win.bufferManagerState.isSome and win.bufferManagerState.get.originalBuffer != nil:
      win.buffer = win.bufferManagerState.get.originalBuffer
  of EditorMode.DiffViewer:
    if win.diffViewerState.isSome and win.diffViewerState.get.originalBuffer != nil:
      win.buffer = win.diffViewerState.get.originalBuffer
  of EditorMode.References:
    if win.referencesViewerState.isSome and
        win.referencesViewerState.get.originalBuffer != nil:
      win.buffer = win.referencesViewerState.get.originalBuffer
  of EditorMode.DocumentSymbol:
    if win.documentSymbolViewerState.isSome and
        win.documentSymbolViewerState.get.originalBuffer != nil:
      win.buffer = win.documentSymbolViewerState.get.originalBuffer
  of EditorMode.CallHierarchy:
    if win.callHierarchyViewerState.isSome and
        win.callHierarchyViewerState.get.originalBuffer != nil:
      win.buffer = win.callHierarchyViewerState.get.originalBuffer
  else:
    discard

proc clearModeState*(win: EditorWindow, mode: EditorMode) =
  ## Restore original buffer (if any) and clear the mode state field.
  win.restoreOriginalBuffer(mode)

  case mode
  of EditorMode.Filer:
    win.filerState = none(FilerState)
  of EditorMode.LogViewer:
    win.logViewerState = none(LogViewerState)
  of EditorMode.Help:
    win.helpViewerState = none(HelpViewerState)
  of EditorMode.BufferManager:
    win.bufferManagerState = none(BufferManagerState)
  of EditorMode.BackupManager:
    win.backupManagerState = none(BackupManagerState)
  of EditorMode.DiffViewer:
    win.diffViewerState = none(DiffViewerState)
  of EditorMode.Debug:
    win.debugViewerState = none(DebugViewerState)
  of EditorMode.Config:
    win.configModeState = none(ConfigModeState)
  of EditorMode.References:
    win.referencesViewerState = none(ReferencesViewerState)
  of EditorMode.DocumentSymbol:
    win.documentSymbolViewerState = none(DocumentSymbolViewerState)
  of EditorMode.CallHierarchy:
    win.callHierarchyViewerState = none(CallHierarchyViewerState)
  of EditorMode.RecentFile:
    win.recentFileModeState = none(RecentFileModeState)
  else:
    discard

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
    sidebarWidth = e.calculateSidebarWidth(window.mode)
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

  # Add the new buffer to the global buffer list if it's not already there
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

  # Note: New window's bufferList is initialized in window_manager.vsplit
  # with only the new buffer (per-window tabs)

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

  # Add the new buffer to the global buffer list
  e.buffers.add(newBuffer)
  # Set reserved words for syntax highlighting on new buffer
  newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
  logDebug("editor", "enew: buffer added, buffers.len: " & $e.buffers.len)

  # Add the new buffer to the active window's bufferList
  e.activeWindow.bufferList.add(newBuffer)
  logDebug(
    "editor",
    "enew: buffer added to window bufferList, len: " & $e.activeWindow.bufferList.len,
  )

  # Replace the buffer in the active window
  e.activeWindow.buffer = newBuffer
  e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
  e.activeWindow.viewport.topLine = 0
  e.activeWindow.viewport.leftColumn = 0

  # Update executor and motion controller buffer references
  # Viewport is shared by reference, so field changes above are already reflected
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer

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
