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

import std/[options, os, tables]

import pkg/results

import
  types/editor_types,
  logger,
  render_utils,
  editorconfig_helper,
  highlight_config,
  editor_window_layout,
  editor_lsp,
  git_cache,
  git_conflict,
  window_manager,
  buffer

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
  e.motionController.bindToWindow(e.activeWindow)
  # Keep state.windowDisplay.currentBufferId aligned with the active window's buffer so that
  # window-switch / split / close paths automatically refresh the Jump List
  # anchor without each call site having to remember to update it.
  e.state.windowDisplay.currentBufferId = e.activeWindow.buffer.id

proc setActiveWindowScreenCursor*(e: Editor, window: EditorWindow) =
  ## Calculate and set screen cursor position for the active window

  # Determine if this window is at the bottom of the screen
  var maxBottomY = 0
  for w in e.windowManager.windows:
    let bottomY = w.viewport.y + w.viewport.height
    if bottomY > maxBottomY:
      maxBottomY = bottomY

  # Calculate tab line offset
  let tabLineOffset = if e.showTabLine: TabLineHeight else: 0

  let
    windowBottomY = window.viewport.y + window.viewport.height
    isBottomWindow = (windowBottomY == maxBottomY)
    scrollbarWidth = e.calculateScrollbarWidth(window)
    # Steady reserve so the clamp agrees with the scroll (see steadyReservedLines).
    reservedLines = e.steadyReservedLines(isBottomWindow)

  var cursorPos = e.calculateWindowCursor(
    window.buffer,
    window.viewport,
    window.cursor,
    e.gutterWidth(window),
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
      termWidth, termHeight, e.screenSize.width, e.screenSize.height, e.multiStatusLine
    )
  else:
    # Set viewport to real terminal size with the command line row reserved
    # (status line and command line share it).
    let win = e.activeWindow
    win.viewport.width = termWidth
    win.viewport.height = termHeight - steadyBottomAreaHeight()

  # Sync screenSize so the subsequent render does NOT trigger resizeWindows,
  # which would ratio-scale from the initial default size and break the layout.
  e.screenSize.width = termWidth
  e.screenSize.height = termHeight
  e.screenSize.prevWidth = termWidth
  e.screenSize.prevHeight = termHeight

# Window split procedures

proc initLoadedBuffer*(e: Editor, buf: TextBuffer) =
  ## Per-buffer initialisation shared by every freshly loaded file regardless of
  ## how it is opened: `:e`, the FileTree opener and no-split startup go through
  ## `loadOrCreateBuffer`, while `:vsplit file`/`:split file` and auto-split
  ## startup go through `registerSplitBuffer`. Restore persisted bookmarks, seed
  ## the git-diff gutter, scan conflict markers and announce the document to the
  ## language server so a file looks identical whichever path reaches it.
  ## Cursor restore is intentionally omitted: it is handled per window (the
  ## window manager seeds the split cursor, loadFile restores the first file's).
  if buf.filePath.isSome:
    let absPath = absolutePath(buf.filePath.get)
    if e.config.persist.bookmarks and e.savedBookmarks.hasKey(absPath):
      buf.bookmarks = e.savedBookmarks[absPath]
    if e.showGitDiff:
      e.state.git.requestGitRefresh(buf)
  # Scan conflict markers regardless of the highlight config (like loadFile) so
  # conflict-navigation works as soon as this buffer becomes active.
  buf.refreshConflicts()
  # Announce the new document to the language server.
  e.openBufferWithLsp(buf)

proc registerSplitBuffer(
    e: Editor, newBuffer: TextBuffer, applyConfig: bool, context: string
) =
  ## Add a newly split buffer to the global buffer list if it isn't already
  ## tracked, then initialize syntax highlighting (and EditorConfig settings
  ## when requested) on it. `context` only labels the debug log.
  if newBuffer in e.buffers:
    return

  e.addBuffer(newBuffer)
  # Apply config-derived highlight settings to the new buffer
  applyHighlightConfig(newBuffer, e.config)
  # Apply EditorConfig settings to the new buffer
  if applyConfig:
    applyEditorConfigToBuffer(newBuffer, e.config)
    # A freshly loaded split file: give it the same per-buffer setup
    # (bookmarks, git diff, conflict markers, LSP didOpen) as loadOrCreateBuffer
    # so split-opened files — including the auto-split multi-file startup path —
    # look identical to no-split startup. WithBuffer splits (applyConfig = false)
    # show an existing or synthetic buffer and must not re-initialise it.
    e.initLoadedBuffer(newBuffer)
  logDebug("editor", context & ": buffer added, buffers.len: " & $e.buffers.len)

proc vsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a vertical split window
  # Save current window state before splitting
  e.saveActiveWindowState()

  let bufferResult =
    e.windowManager.vsplit(e.activeBuffer, e.viewport, e.cursor, filename)
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
    e.windowManager.vsplitWithBuffer(e.activeBuffer, e.viewport, e.cursor, buffer)
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
    e.activeBuffer, e.viewport, e.cursor, e.multiStatusLine, filename
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
    e.activeBuffer, e.viewport, e.cursor, e.multiStatusLine, buffer
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
  # Apply config-derived highlight settings to the new buffer
  applyHighlightConfig(newBuffer, e.config)
  logDebug("editor", "enew: buffer added, buffers.len: " & $e.buffers.len)

  # Replace the buffer in the active window
  e.activeWindow.buffer = newBuffer
  e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
  e.activeWindow.viewport.resetViewportTop()
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
  e.windowManager.equalizeAllWindows(e.multiStatusLine)
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

  let shouldQuit = e.windowManager.closeWindow(e.multiStatusLine)

  if shouldQuit:
    return true

  # Sync to the new active window (includes mode/cursor sync)
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  return false
