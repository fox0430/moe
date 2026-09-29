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
  editor_window_tab,
  editor_window_state,
  editor_lsp,
  git_cache,
  git_conflict,
  window_manager,
  motion,
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
  # A viewer's positions are in its listing, which no buffer id resolves to, so
  # a jump taken there cannot land in the tab it covers.
  let win = e.activeWindow
  e.state.windowDisplay.currentBufferId =
    if win.viewerEntry.isSome: win.buffer.id else: win.tabBufferId

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

proc vsplitWithBuffer*(e: Editor, buffer: TextBuffer): Result[(), string]
proc hsplitWithBuffer*(e: Editor, buffer: TextBuffer): Result[(), string]

proc loadSplitBuffer(e: Editor, path: string): Result[TextBuffer, string] =
  ## Buffer for a split on `path`: reuse the holder if open, else load a new one.
  let existing = bufferHoldingPath(e.buffers, path)
  if existing.isSome:
    return ok(existing.get)

  let buf = newTextBuffer()
  # Inherit the highlight cap from the current buffer BEFORE loadFile builds
  # the first chunk; otherwise the applyHighlightConfig below nils the
  # progressive cache when the cap differs, forcing a full reparse on open
  # (mirrors the :e seed-before-load).
  buf.maxHighlightLineLength = e.activeBuffer.maxHighlightLineLength
  e.addBuffer(buf)

  let loadResult = buf.loadFile(path)
  if loadResult.isErr:
    e.unregisterBufferNoLsp(buf)
    return err(loadResult.error)

  applyHighlightConfig(buf, e.config)
  applyEditorConfigToBuffer(buf, e.config)
  e.initLoadedBuffer(buf)
  ok(buf)

proc viewerOrigin*(
    e: Editor, entry: ViewerEntry, buf: TextBuffer, mode: EditorMode
): tuple[cursor: BufferPosition, topLine: int] =
  ## The view `entry` covered, moved inside `buf` for `mode`: `buf` may have
  ## shrunk while the viewer was up.
  let clamped = e.motionController.cursorManager.clampPosition(
    CursorPosition(x: entry.originCursor.column, y: entry.originCursor.line),
    buf,
    some(mode),
  )
  (
    BufferPosition(line: clamped.y, column: clamped.x),
    min(entry.originTopLine, max(0, buf.len - 1)),
  )

proc splitOrigin(e: Editor): tuple[viewport: ViewPort, cursor: BufferPosition] =
  ## Where a split of the active window's tab starts. A viewer's own position
  ## is in its listing; the tab's is in its entry while the window is still on
  ## that tab.
  let win = e.activeWindow
  if win.viewerEntry.isNone:
    return (win.viewport, win.cursor)
  let entry = win.viewerEntry.get
  if win.tabBufferId != entry.returnTab:
    return (ViewPort(), BufferPosition(line: 0, column: 0))
  # A split starts in Normal.
  let origin = e.viewerOrigin(entry, e.tabBuffer(win), EditorMode.Normal)
  (ViewPort(topLine: origin.topLine, leftColumn: entry.originLeftColumn), origin.cursor)

const MinNewWindowWidth* = 10
  ## Minimum width (in columns) required when spawning a new split window.

proc sidebarTarget*(e: Editor): int =
  ## Index of the window the FileTree sidebar opens files in: the one last
  ## focused, as Vim's `wincmd p`, else the first other one; -1 when the sidebar
  ## is alone.
  let prev = e.windowManager.previousWindow
  if prev != nil and not prev.isSidebar:
    let i = e.windowManager.windows.find(prev)
    if i >= 0:
      return i
  for i, win in e.windowManager.windows:
    if not win.isSidebar:
      return i
  -1

proc roomBesideSidebar*(e: Editor): Result[int, string] =
  ## Width of a window opened right of the active sidebar. Measured to the
  ## screen's edge: a resize shrinks a lone sidebar to its fixed width.
  let side = e.activeWindow
  if not side.isSidebar:
    return err("active window is not the FileTree sidebar")
  let width =
    e.screenSize.width - side.viewport.x - side.fixedWidth.get - WindowSeparatorWidth
  if width < MinNewWindowWidth:
    return err("not enough space to open a new window")
  ok(width)

proc openWindowBesideSidebar*(e: Editor, buf: TextBuffer): Result[void, string] =
  ## Open a window on `buf`'s tab right of the active sidebar and focus it, for
  ## when the sidebar is the only window.
  let width = ?e.roomBesideSidebar()
  let side = e.activeWindow
  let sideWidth = side.fixedWidth.get
  side.viewport.width = sideWidth
  e.windowManager.deactivateAllWindows()

  let win = EditorWindow(
    viewBuffer: buf,
    tabBufferId: buf.id,
    bufferIds: @[buf.id],
    viewport: ViewPort(
      width: width,
      height: side.viewport.height,
      x: side.viewport.x + sideWidth + WindowSeparatorWidth,
      y: side.viewport.y,
    ),
    active: true,
    mode: EditorMode.Normal,
    wrapCountCache: WrapCountCache(),
  )
  let sideIndex = e.windowManager.activeWindowIndex
  e.windowManager.previousWindow = side
  e.windowManager.windows.insert(win, sideIndex + 1)
  e.windowManager.activeWindowIndex = sideIndex + 1

  e.syncActiveWindow()
  e.deriveTabMode(win)
  e.state.previousMode = EditorMode.Normal
  e.setActiveWindowScreenCursor(win)
  ok()

proc vsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a vertical split window, showing `filename` when one is given and
  ## the current buffer otherwise.
  if filename.isSome:
    let loaded = e.loadSplitBuffer(filename.get)
    if loaded.isErr:
      return err(loaded.error)
    return e.vsplitWithBuffer(loaded.get)

  # Save current window state before splitting
  e.saveActiveWindowState()

  # Split the tab, not a mode-swapped view.
  let origin = e.splitOrigin()
  let bufferResult =
    e.windowManager.vsplit(e.tabBuffer(e.activeWindow), origin.viewport, origin.cursor)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get

  # Add the new buffer to the global buffer list if it's not already there
  e.registerSplitBuffer(newBuffer, applyConfig = true, context = "vsplit")

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # Derive the new window's mode from its tab.
  e.deriveTabMode(e.activeWindow)
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

  # Derive the new window's mode from its tab.
  e.deriveTabMode(e.activeWindow)
  e.state.previousMode = EditorMode.Normal

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  ok(())

proc hsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a horizontal split window (top and bottom), showing `filename` when
  ## one is given and the current buffer otherwise.
  if filename.isSome:
    let loaded = e.loadSplitBuffer(filename.get)
    if loaded.isErr:
      return err(loaded.error)
    return e.hsplitWithBuffer(loaded.get)

  # Save current window state before splitting
  e.saveActiveWindowState()

  # Split the tab, not a mode-swapped view.
  let origin = e.splitOrigin()
  let bufferResult = e.windowManager.hsplit(
    e.tabBuffer(e.activeWindow), origin.viewport, origin.cursor, e.multiStatusLine
  )
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get

  # Add the new buffer to the buffer list if it's not already there
  e.registerSplitBuffer(newBuffer, applyConfig = true, context = "hsplit")

  # Sync active window state (buffer, viewport, cursor) with executor
  e.syncActiveWindow()

  # Derive the new window's mode from its tab.
  e.deriveTabMode(e.activeWindow)
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

  # Derive the new window's mode from its tab.
  e.deriveTabMode(e.activeWindow)
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

  # Shared tab transition.
  discard e.moveWindowToTab(e.activeWindow, newBuffer)

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
  ## Switch to the next window (Ctrl-w, w)
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
  ## Switch to the last accessed window (Ctrl-w, p)
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

proc moveToWindowDirection*(e: Editor, direction: WindowDirection) =
  ## Move the focus to the nearest window in `direction` (Ctrl-w h/j/k/l)
  if e.windowManager.windows.len <= 1:
    return

  # Save current window state before switching
  e.saveActiveWindowState()

  if not e.windowManager.moveToWindowDirection(direction):
    return

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

proc maximizeWindowHeight*(e: Editor) =
  ## Maximize the active window's height within its vertical group
  e.windowManager.maximizeWindowHeight(
    e.multiStatusLine, e.showTabLine, e.showStatusLine
  )
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

  # Pass screen dimensions so the post-close check can flag out-of-screen re-tiles.
  let shouldQuit = e.windowManager.closeWindow(
    e.multiStatusLine,
    screenWidth = e.screenSize.width,
    screenHeight = e.screenSize.height,
  )

  if shouldQuit:
    return true

  # Sync to the new active window (includes mode/cursor sync)
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.setActiveWindowScreenCursor(e.activeWindow)

  return false
