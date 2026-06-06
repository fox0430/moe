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

import editor_types, logger, render_utils, editorconfig_helper, editor_window_layout

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

proc syncActiveWindow*(e: Editor) =
  ## Refresh editor-level caches after the active window changes.
  ## The per-window buffer/viewport/wrapCountCache that the executor caches are
  ## re-aliased in a single place via `bindToWindow`, so split / navigation /
  ## close / resize paths only have to call this hook.
  e.state.activeWindow = e.activeWindow
  e.executer.bindToWindow(e.activeWindow)
  # Viewport is shared by reference - reassigning shares the active window's viewport
  e.viewport = e.activeWindow.viewport
  # Keep state.windowDisplay.currentBufferId aligned with the active window's buffer so that
  # window-switch / split / close paths automatically refresh the Jump List
  # anchor without each call site having to remember to update it.
  e.state.windowDisplay.currentBufferId = e.activeWindow.buffer.id
  e.state.windowDisplay.needsFullRedraw = true

  # Apply per-buffer EditorConfig overrides to display settings
  applyBufferEditorConfig(e.state.display, e.activeWindow.buffer, e.config)

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
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
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
    scrollbarWidth,
    window.wrapCountCache,
  )
  # Adjust cursor Y for tab line offset
  cursorPos.y += tabLineOffset
  e.state.screenCursor = cursorPos
  # Note: cursorVisible is set by each mode's render function

proc applyStartUpScreenSize*(e: Editor, termWidth, termHeight: int) =
  ## Apply the real terminal size on first render. The startup window layout
  ## (including splits from `moe file1 file2`) is built against the initial
  ## default screen size before the terminal size is known.
  if e.windowManager.windows.len > 1:
    # Rescale the whole split layout, same as a runtime terminal resize.
    e.windowManager.resizeWindows(
      termWidth, termHeight, e.screenSize.width, e.screenSize.height,
      e.state.display.multiStatusLine,
    )
  else:
    # Set viewport to real terminal size with the command line row reserved
    # (status line and command line share it).
    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = termHeight - CommandLineHeight

  # Sync screenSize so the subsequent render does NOT trigger resizeWindows,
  # which would ratio-scale from the initial default size and break the layout.
  e.screenSize.width = termWidth
  e.screenSize.height = termHeight
  e.screenSize.prevWidth = termWidth
  e.screenSize.prevHeight = termHeight

# Window split procedures

proc registerSplitBuffer(
    e: Editor, newBuffer: TextBuffer, applyConfig: bool, context: string
) =
  ## Add a newly split buffer to the global buffer list if it isn't already
  ## tracked, then initialize syntax highlighting (and EditorConfig settings
  ## when requested) on it. `context` only labels the debug log.
  if newBuffer in e.buffers:
    return

  e.addBuffer(newBuffer)
  # Set reserved words for syntax highlighting on new buffer
  newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
  # Apply EditorConfig settings to the new buffer
  if applyConfig:
    applyEditorConfigToBuffer(newBuffer, e.config)
  logDebug("editor", context & ": buffer added, buffers.len: " & $e.buffers.len)

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
  e.registerSplitBuffer(newBuffer, applyConfig = true, context = "vsplit")

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
  e.registerSplitBuffer(newBuffer, applyConfig = false, context = "vsplitWithBuffer")

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
  e.registerSplitBuffer(newBuffer, applyConfig = true, context = "hsplit")

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
  e.registerSplitBuffer(newBuffer, applyConfig = false, context = "hsplitWithBuffer")

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
  e.addBuffer(newBuffer)
  # Register in active window's per-window tab list
  if newBuffer.id notin e.activeWindow.bufferIds:
    e.activeWindow.bufferIds.add(newBuffer.id)
  # Set reserved words for syntax highlighting on new buffer
  newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
  logDebug("editor", "enew: buffer added, buffers.len: " & $e.buffers.len)

  # Replace the buffer in the active window
  e.activeWindow.buffer = newBuffer
  e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
  e.activeWindow.viewport.topLine = 0
  e.activeWindow.viewport.leftColumn = 0

  # Reset cursor
  e.cursor = BufferPosition(line: 0, column: 0)

  e.syncActiveWindow()

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

proc increaseWindowWidth*(e: Editor) =
  ## Increase the active window's width
  e.windowManager.increaseWindowWidth()
  e.syncActiveWindow()

proc decreaseWindowWidth*(e: Editor) =
  ## Decrease the active window's width
  e.windowManager.decreaseWindowWidth()
  e.syncActiveWindow()

proc increaseWindowHeight*(e: Editor) =
  ## Increase the active window's height
  e.windowManager.increaseWindowHeight()
  e.syncActiveWindow()

proc decreaseWindowHeight*(e: Editor) =
  ## Decrease the active window's height
  e.windowManager.decreaseWindowHeight()
  e.syncActiveWindow()

proc equalizeWindowSizes*(e: Editor) =
  ## Equalize all window sizes
  e.windowManager.equalizeAllWindows(e.state.display.multiStatusLine)
  e.syncActiveWindow()

proc swapWindow*(e: Editor) =
  ## Swap the active window with the next window
  e.windowManager.swapWindows()
  e.syncActiveWindow()

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

  # Sync to the new active window (includes mode/cursor sync)
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  return false
