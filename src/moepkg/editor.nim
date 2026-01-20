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

import std/[strutils, strformat, options, tables, unicode, monotimes, times, os, json]

import pkg/[celina, results]

import
  buffer, cursor, types, commands, keybindings, commandregistry, modes, commandline,
  commandconfig, statusline, windowmanager, unicode_utils, render_utils, sidebar,
  gitdiff, highlight, logger, config, configloader, keybindconfig, search_utils, filer,
  lspintegration, completion, signaturehelp, hoverpopup, backup, command_completion,
  motion, recentfilemode, color, gapbuffer, persist, debugviewer, messagelog
import lsp/protocol/types as lspTypes
import command_handlers/[handler_manager, visual_handler, insert_handler]

type
  IndentInfo = object
    ## Cached indentation analysis for a line to avoid O(n²) performance
    leadingWhitespaceEnd: int
      # Character index where leading whitespace ends (-1 if no content)
    hasContent: bool # Whether the line contains non-whitespace content

  RenderContext* = object
    ## Context for rendering operations to reduce parameter passing
    cursorLine*: int
    cursorCol*: int
    hasSelection*: bool
    selStart*: BufferPosition
    selEnd*: BufferPosition

  Editor* = ref object
    textBuffer*: TextBuffer
    state*: EditorState
    viewport*: ViewPort
    executer*: CommandExecutor
    commandRegistry*: CommandRegistry
    keyBindingRegistry*: KeyBindingRegistry
    commandLineParser*: CommandLineParser
    commandConfig*: CommandConfig
    handlerManager*: HandlerManager
    windowManager*: EditorWindowManager # Window manager for split windows
    buffers*: seq[TextBuffer] # Buffer list (like Vim's buffer list)
    config*: EditorConfig # TOML configuration
    lsp*: LspIntegration # LSP client integration
    lastLspChangeSeq*: int # Track buffer changes for LSP notifications
    recentFileModeState*: RecentFileModeState # State for Recent File mode
    app*: App # Celina application reference for suspend/resume
    cursorPositions*: Table[string, CursorPositionEntry] # Persisted cursor positions

proc buffer*(e: Editor): TextBuffer =
  e.textBuffer

proc activeBuffer*(e: Editor): TextBuffer =
  ## Get the currently active buffer (from active window if split, otherwise main buffer)
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.windowManager.windows[e.windowManager.activeWindowIndex].buffer
  else:
    e.textBuffer

proc saveActiveWindowState*(e: Editor) =
  ## Save current EditorState cursor and viewport to the active window
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    activeWindow.cursor = e.state.cursor
    # Also save viewport scroll position from motionController
    activeWindow.viewport.topLine =
      e.executer.motionController.viewportManager.viewport.topLine
    activeWindow.viewport.leftColumn =
      e.executer.motionController.viewportManager.viewport.leftColumn

proc restoreActiveWindowState(e: Editor) =
  ## Restore the active window's cursor and viewport to EditorState
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.state.cursor = activeWindow.cursor
    # Restore viewport scroll position to motionController
    e.executer.motionController.viewportManager.viewport.topLine =
      activeWindow.viewport.topLine
    e.executer.motionController.viewportManager.viewport.leftColumn =
      activeWindow.viewport.leftColumn

proc syncActiveWindow*(e: Editor) =
  ## Sync the active window's buffer and viewport with the executor and motion controller
  let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
  e.executer.buffer = activeWindow.buffer
  e.executer.motionController.executor.buffer = activeWindow.buffer
  e.executer.motionController.viewportManager.viewport = activeWindow.viewport
  e.restoreActiveWindowState()
  e.state.needsFullRedraw = true

proc calculateReservedLines(e: Editor, isBottomWindow: bool = true): int =
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

proc calculateWindowCursor(
    e: Editor,
    buffer: TextBuffer,
    viewport: ViewPort,
    cursor: BufferPosition,
    lineNumOffset: int,
    reservedLines: int,
): CursorPosition =
  ## Calculate screen cursor position for a window
  ## Returns the absolute screen coordinates
  ##
  ## Algorithm overview:
  ## - Validate cursor is within buffer and viewport
  ## - For wrapped mode: iterate through lines to count wrapped screen lines
  ## - For non-wrapped mode: use simple arithmetic with horizontal scroll offset
  ## - Return (0, 0) if cursor is not visible on screen
  ##
  ## Parameters:
  ## - buffer: TextBuffer containing the text
  ## - viewport: Current viewport configuration (position, size)
  ## - cursor: Logical cursor position (line, column)
  ## - lineNumOffset: Width of line number area
  ## - reservedLines: Lines reserved for status/command (at bottom)

  # Validate cursor is within buffer bounds
  if cursor.line < 0 or cursor.line >= buffer.len:
    return CursorPosition(x: 0, y: 0)

  # Cursor is above visible area
  if cursor.line < viewport.topLine:
    return CursorPosition(x: 0, y: 0)

  if e.state.display.lineWrap:
    # === WRAP MODE: Calculate cursor position considering line wrapping ===
    #
    # Strategy:
    # 1. Calculate available width for text (viewport width - line numbers)
    # 2. Count screen lines consumed by all logical lines BEFORE cursor line
    # 3. Within cursor line, calculate which wrapped line the cursor is on
    # 4. Calculate column within that wrapped line
    #
    # Performance optimization:
    # - Only iterate through visible lines (topLine to cursor.line)
    # - Early exit if we exceed visible height
    # - This keeps complexity O(visible_lines) instead of O(all_lines)

    let maxWidth = max(1, viewport.width - lineNumOffset)

    # Phase 1: Count screen lines consumed by lines BEFORE cursor line
    # This accounts for wrapped lines pushing cursor down the screen
    var screenY = 0
    let maxVisibleLine = min(cursor.line, viewport.topLine + viewport.height)

    for lineIdx in viewport.topLine ..< maxVisibleLine:
      if lineIdx >= 0 and lineIdx < buffer.len:
        let line = buffer.getLine(lineIdx)
        let lineCharLen = line.charLen

        if lineCharLen == 0:
          # Empty line takes 1 screen line
          screenY += 1
        else:
          # Calculate wrapped line count using formula:
          # wrappedLines = ceil(lineCharLen / maxWidth)
          #              = ((lineCharLen - 1) div maxWidth) + 1
          # Example: 100 chars with maxWidth=40 -> ((99 div 40) + 1) = 2 + 1 = 3 lines
          let wrappedLines = calculateWrapCount(lineCharLen, maxWidth)
          screenY += wrappedLines

        # Early exit if cursor would be off-screen (performance optimization)
        if screenY >= viewport.height - reservedLines:
          return CursorPosition(x: 0, y: 0)

    # Phase 2: Calculate cursor position WITHIN the cursor line
    # The cursor line itself may be wrapped across multiple screen lines
    let
      cursorLineText = buffer.getLine(cursor.line)

      # Get display width (accounting for wide characters like tabs, Unicode)
      # Example: "Hello\tWorld" with cursor at column 7
      # displayWidthUpToCursor accounts for tab width
      displayWidthUpToCursor =
        displayWidthUpToWithTabs(cursorLineText, cursor.column, e.state.display.tabStop)

      # Determine which wrapped line segment the cursor is on
      # Example: cursor at display width 95 with maxWidth=40
      # wrapLineIndex = 95 div 40 = 2 (3rd wrapped line, 0-indexed)
      # wrapLineColumn = 95 mod 40 = 15 (column 15 within that wrapped line)
      wrapLineIndex = displayWidthUpToCursor div maxWidth
      wrapLineColumn = displayWidthUpToCursor mod maxWidth

    # Add wrapped line count from cursor line to total screen Y
    screenY += wrapLineIndex

    # Final visibility check and coordinate calculation
    if screenY < viewport.height - reservedLines:
      # Cursor is visible - calculate absolute screen coordinates
      # x = viewport.x (window x) + lineNumOffset (line number width) + wrapLineColumn
      # y = viewport.y (window y) + screenY (lines from top)
      let finalX = viewport.x + lineNumOffset + wrapLineColumn
      let finalY = viewport.y + screenY
      return CursorPosition(x: finalX, y: finalY)
  else:
    # === NO-WRAP MODE: Calculate cursor position with horizontal scrolling ===
    #
    # Strategy:
    # - Each logical line = 1 screen line (no wrapping)
    # - Y position is simple: cursor.line - viewport.topLine
    # - X position accounts for horizontal scroll (viewport.leftColumn)
    #
    # Example: cursor at column 100, viewport.leftColumn = 60, maxWidth = 80
    # displayWidthUpToCursor = 100 (cursor position)
    # displayWidthUpToLeftCol = 60 (scroll offset)
    # screenX = 100 - 60 = 40 (cursor appears at column 40 on screen)

    # Check if cursor line is within visible vertical range
    if cursor.line < viewport.topLine + viewport.height - reservedLines:
      let
        cursorLineText = buffer.getLine(cursor.line)

        # Calculate display widths (accounting for tabs, wide characters)
        displayWidthUpToCursor = displayWidthUpToWithTabs(
          cursorLineText, cursor.column, e.state.display.tabStop
        )
        displayWidthUpToLeftCol = displayWidthUpToWithTabs(
          cursorLineText, viewport.leftColumn, e.state.display.tabStop
        )

        # Y position: simple offset from top of viewport
        screenY = viewport.y + (cursor.line - viewport.topLine)

        # X position: cursor position minus horizontal scroll offset
        # max(0, ...) ensures we don't go negative if cursor is left of scroll
        screenX =
          viewport.x + lineNumOffset +
          max(0, displayWidthUpToCursor - displayWidthUpToLeftCol)

      return CursorPosition(x: screenX, y: screenY)

  # Cursor is not visible (off-screen)
  return CursorPosition(x: 0, y: 0)

proc calculateSidebarWidth(e: Editor): int =
  ## Calculate the width occupied by the sidebar (0 if disabled)
  if e.state.display.showSidebar: DefaultSidebarWidth else: 0

proc setActiveWindowScreenCursor(e: Editor, window: EditorWindow) =
  ## Calculate and set screen cursor position for the active window

  # Determine if this window is at the bottom of the screen
  var maxBottomY = 0
  for w in e.windowManager.windows:
    let bottomY = w.viewport.y + w.viewport.height
    if bottomY > maxBottomY:
      maxBottomY = bottomY

  let
    windowBottomY = window.viewport.y + window.viewport.height
    isBottomWindow = (windowBottomY == maxBottomY)
    sidebarWidth = e.calculateSidebarWidth()
    lineNumOffset =
      calculateLineNumOffset(window.buffer, e.state.display.showLineNumbers) +
      sidebarWidth
    reservedLines = e.calculateReservedLines(isBottomWindow)

  e.state.screenCursor = e.calculateWindowCursor(
    window.buffer, window.viewport, window.cursor, lineNumOffset, reservedLines
  )

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
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

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
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

proc findBufferByPath*(e: Editor, path: string): int =
  ## Find a buffer in the buffer list by its file path
  ## Returns the buffer index (0-based) or -1 if not found
  let absPath = absolutePath(path)
  for i, buf in e.buffers:
    if buf.filePath.isSome and absolutePath(buf.filePath.get) == absPath:
      return i
  return -1

proc switchToBufferByIndex*(e: Editor, index: int) =
  ## Switch the current window to display the buffer at the given index
  logDebug("editor", "switchToBufferByIndex called with index: " & $index)
  logDebug("editor", "windows.len: " & $e.windowManager.windows.len)

  if index < 0 or index >= e.buffers.len:
    logDebug("editor", "Invalid index, returning")
    return

  let targetBuffer = e.buffers[index]
  let targetPath =
    if targetBuffer.filePath.isSome: targetBuffer.filePath.get else: "No Name"
  logDebug("editor", "Target buffer path: " & targetPath)

  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]

    # Don't switch if already on this buffer
    if activeWindow.buffer == targetBuffer:
      logDebug("editor", "Already on this buffer (window mode)")
      return

    activeWindow.buffer = targetBuffer
    activeWindow.cursor = BufferPosition(line: 0, column: 0)
    activeWindow.viewport.topLine = 0
    activeWindow.viewport.leftColumn = 0

    # Sync the executor and motion controller
    e.syncActiveWindow()

    # Update screen cursor
    e.setActiveWindowScreenCursor(activeWindow)
    logDebug("editor", "Switched buffer in window mode")
  else:
    # No windows, update the main buffer reference
    logDebug("editor", "Switching in single buffer mode")
    e.textBuffer = targetBuffer
    e.executer.buffer = targetBuffer
    e.executer.motionController.executor.buffer = targetBuffer
    e.state.cursor = BufferPosition(line: 0, column: 0)
    e.viewport.topLine = 0
    e.viewport.leftColumn = 0
    e.state.needsFullRedraw = true
    logDebug("editor", "Switched to buffer successfully")

proc currentBufferIndex*(e: Editor): int =
  ## Get the index of the current buffer in the buffer list
  ## Returns -1 if not found
  logDebug(
    "editor",
    "currentBufferIndex: windows.len=" & $e.windowManager.windows.len &
      " activeWindowIndex=" & $e.windowManager.activeWindowIndex,
  )
  let currentBuffer = e.activeBuffer()
  let currentPath =
    if currentBuffer.filePath.isSome: currentBuffer.filePath.get else: "[No Name]"
  logDebug("editor", "currentBufferIndex: activeBuffer path=" & currentPath)
  for i, buf in e.buffers:
    if buf == currentBuffer:
      logDebug("editor", "currentBufferIndex: found match at index " & $i)
      return i
  logDebug("editor", "currentBufferIndex: no match found, returning -1")
  return -1

proc switchToNextBuffer*(e: Editor) =
  ## Switch to the next buffer in the buffer list (:bnext)
  if e.buffers.len <= 1:
    e.state.statusMessage = "No more buffers"
    return

  let currentIdx = e.currentBufferIndex()
  let nextIdx = (currentIdx + 1) mod e.buffers.len
  e.switchToBufferByIndex(nextIdx)
  e.state.statusMessage = ""

proc switchToPrevBuffer*(e: Editor) =
  ## Switch to the previous buffer in the buffer list (:bprev)
  if e.buffers.len <= 1:
    e.state.statusMessage = "No more buffers"
    return

  let currentIdx = e.currentBufferIndex()
  let prevIdx =
    if currentIdx == 0:
      e.buffers.len - 1
    else:
      currentIdx - 1
  e.switchToBufferByIndex(prevIdx)
  e.state.statusMessage = ""

proc switchToFirstBuffer*(e: Editor) =
  ## Switch to the first buffer in the buffer list (:bfirst)
  if e.buffers.len <= 1:
    e.state.statusMessage = "Already at first buffer"
    return

  let currentIdx = e.currentBufferIndex()
  if currentIdx == 0:
    e.state.statusMessage = "Already at first buffer"
    return

  e.switchToBufferByIndex(0)
  e.state.statusMessage = ""

proc switchToLastBuffer*(e: Editor) =
  ## Switch to the last buffer in the buffer list (:blast)
  if e.buffers.len <= 1:
    e.state.statusMessage = "Already at last buffer"
    return

  let lastIdx = e.buffers.len - 1
  let currentIdx = e.currentBufferIndex()
  if currentIdx == lastIdx:
    e.state.statusMessage = "Already at last buffer"
    return

  e.switchToBufferByIndex(lastIdx)
  e.state.statusMessage = ""

proc switchToBuffer*(e: Editor, arg: string): bool =
  ## Switch to a buffer by number or name (:b N or :b name)
  ## Returns true if successful, false otherwise
  ## Uses the buffer list (not windows) like Vim

  logDebug("editor", "switchToBuffer called with arg: " & arg)
  logDebug("editor", "buffers.len: " & $e.buffers.len)
  # Log each buffer's path for debugging
  for i, buf in e.buffers:
    let path = if buf.filePath.isSome: buf.filePath.get else: "[No Name]"
    logDebug("editor", "  buffer[" & $i & "]: " & path)

  # Try to parse as a number first
  try:
    let bufNum = parseInt(arg)
    # Buffer numbers are 1-indexed in Vim
    let targetIndex = bufNum - 1

    logDebug(
      "editor", "Parsed buffer number: " & $bufNum & ", targetIndex: " & $targetIndex
    )

    if targetIndex < 0 or targetIndex >= e.buffers.len:
      e.state.statusMessage = "E86: Buffer " & $bufNum & " does not exist"
      logDebug("editor", "Buffer does not exist")
      return false

    let currentIdx = e.currentBufferIndex()
    logDebug("editor", "currentIdx: " & $currentIdx)
    if targetIndex == currentIdx:
      # Already at this buffer
      logDebug("editor", "Already at this buffer")
      return true

    # Switch to the buffer
    logDebug("editor", "Switching to buffer at index: " & $targetIndex)
    e.switchToBufferByIndex(targetIndex)
    e.state.statusMessage = ""
    return true
  except ValueError:
    discard # Not a number, try matching by name

  # Try to match by file name in buffer list
  for i, buf in e.buffers:
    if buf.filePath.isSome:
      let bufferPath = buf.filePath.get
      # Match against full path, file name, or partial match
      if bufferPath == arg or bufferPath.extractFilename == arg or
          bufferPath.contains(arg):
        let currentIdx = e.currentBufferIndex()
        if i == currentIdx:
          # Already at this buffer
          return true

        # Switch to the buffer
        e.switchToBufferByIndex(i)
        e.state.statusMessage = ""
        return true

  e.state.statusMessage = "E94: No matching buffer for " & arg
  return false

proc isBufferShared*(e: Editor, buffer: TextBuffer): bool =
  ## Check if the given buffer is shared across multiple windows
  ## Returns true if the buffer is open in more than one window
  for window in e.windowManager.windows:
    if window.buffer == buffer:
      if result:
        return true
      else:
        result = true

  # Buffer is not shared across multiple windows (0 or 1 window)
  return false

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
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  return false

proc addCommandAlias*(
    e: Editor, alias: string, action: CommandLineAction
): Result[(), string] =
  ## Add a new command alias
  e.commandConfig.addAlias(alias, action)
  e.commandConfig.applyToParser(e.commandLineParser)
  ok(())

proc removeCommandAlias*(e: Editor, alias: string): Result[(), string] =
  ## Remove a command alias
  if e.commandLineParser.aliases.hasKey(alias):
    e.commandLineParser.removeAlias(alias)
    # Note: This doesn't remove from config until save is called
    ok(())
  else:
    err fmt"Alias not found: {alias}"

proc toggleStatusLine*(e: Editor) =
  ## Toggle the visibility of the status line
  e.state.toggleStatusLine()

proc setStatusLineVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the status line
  e.state.setStatusLineVisible(visible)

proc toggleLineCount*(e: Editor) =
  ## Toggle the visibility of line count in status line
  e.state.toggleLineCount()

proc setLineCountVisible*(e: Editor, visible: bool) =
  ## Set the visibility of line count in status line
  e.state.setLineCountVisible(visible)

proc toggleLinePercentage*(e: Editor) =
  ## Toggle the visibility of line percentage in status line
  e.state.toggleLinePercentage()

proc setLinePercentageVisible*(e: Editor, visible: bool) =
  ## Set the visibility of line percentage in status line
  e.state.setLinePercentageVisible(visible)

proc toggleEncoding*(e: Editor) =
  ## Toggle the visibility of encoding in status line
  e.state.toggleEncoding()

proc setEncodingVisible*(e: Editor, visible: bool) =
  ## Set the visibility of encoding in status line
  e.state.setEncodingVisible(visible)

proc toggleLineWrap*(e: Editor) =
  ## Toggle line wrapping
  e.state.display.lineWrap = not e.state.display.lineWrap
  e.state.needsFullRedraw = true

proc setLineWrap*(e: Editor, enabled: bool) =
  ## Set line wrapping
  e.state.display.lineWrap = enabled
  e.state.needsFullRedraw = true

proc toggleMultiStatusLine*(e: Editor) =
  ## Toggle between single status line (at bottom) and multi status lines (per window)
  e.state.display.multiStatusLine = not e.state.display.multiStatusLine
  e.state.needsFullRedraw = true

proc setMultiStatusLine*(e: Editor, enabled: bool) =
  ## Set multi status line mode
  e.state.display.multiStatusLine = enabled
  e.state.needsFullRedraw = true

proc toggleSidebar*(e: Editor) =
  ## Toggle the visibility of the sidebar
  e.state.display.showSidebar = not e.state.display.showSidebar
  e.state.needsFullRedraw = true

proc setSidebarVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the sidebar
  e.state.display.showSidebar = visible
  e.state.needsFullRedraw = true

proc toggleGitDiff*(e: Editor) =
  ## Toggle git diff indicators in sidebar
  e.state.display.showGitDiff = not e.state.display.showGitDiff

  # Update git diff information when enabled
  if e.state.display.showGitDiff:
    discard updateBufferWithGitDiff(e.textBuffer)

  e.state.needsFullRedraw = true

proc setGitDiffVisible*(e: Editor, visible: bool) =
  ## Set git diff indicators visibility in sidebar
  e.state.display.showGitDiff = visible

  # Update git diff information when enabled
  if visible:
    discard updateBufferWithGitDiff(e.textBuffer)

  e.state.needsFullRedraw = true

proc toggleSyntaxChecker*(e: Editor) =
  ## Toggle syntax checker results in sidebar
  e.state.display.showSyntaxChecker = not e.state.display.showSyntaxChecker
  e.state.needsFullRedraw = true

proc setSyntaxCheckerVisible*(e: Editor, visible: bool) =
  ## Set syntax checker results visibility in sidebar
  e.state.display.showSyntaxChecker = visible
  e.state.needsFullRedraw = true

proc vsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a vertical split window
  # Save current window state before splitting (if windows already exist)
  if e.windowManager.windows.len > 0:
    e.saveActiveWindowState()

  let bufferResult =
    e.windowManager.vsplit(e.textBuffer, e.viewport, e.state.cursor, filename)
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

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc vsplitWithBuffer*(e: Editor, buffer: TextBuffer): Result[(), string] =
  ## Create a vertical split window with a specific buffer
  # Save current window state before splitting (if windows already exist)
  if e.windowManager.windows.len > 0:
    e.saveActiveWindowState()

  let bufferResult =
    e.windowManager.vsplitWithBuffer(e.textBuffer, e.viewport, e.state.cursor, buffer)
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

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc hsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a horizontal split window (top and bottom)
  # Save current window state before splitting (if windows already exist)
  if e.windowManager.windows.len > 0:
    e.saveActiveWindowState()

  let bufferResult = e.windowManager.hsplit(
    e.textBuffer, e.viewport, e.state.cursor, e.state.display.multiStatusLine, filename
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

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc hsplitWithBuffer*(e: Editor, buffer: TextBuffer): Result[(), string] =
  ## Create a horizontal split window with a specific buffer
  # Save current window state before splitting (if windows already exist)
  if e.windowManager.windows.len > 0:
    e.saveActiveWindowState()

  let bufferResult = e.windowManager.hsplitWithBuffer(
    e.textBuffer, e.viewport, e.state.cursor, e.state.display.multiStatusLine, buffer
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

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc enew*(e: Editor): Result[(), string] =
  ## Create a new empty buffer and add it to the buffer list
  let newBuffer = newTextBuffer()

  # Add the new buffer to the buffer list
  e.buffers.add(newBuffer)
  # Set reserved words for syntax highlighting on new buffer
  newBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))
  logDebug("editor", "enew: buffer added, buffers.len: " & $e.buffers.len)

  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    # Replace the buffer in the active window
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    activeWindow.buffer = newBuffer
    activeWindow.cursor = BufferPosition(line: 0, column: 0)
    activeWindow.viewport.topLine = 0
    activeWindow.viewport.leftColumn = 0

    # Update executor and motion controller references
    e.executer.buffer = newBuffer
    e.executer.motionController.executor.buffer = newBuffer
    e.executer.motionController.viewportManager.viewport = activeWindow.viewport

    # Reset cursor
    e.state.cursor = BufferPosition(line: 0, column: 0)
  else:
    # No windows, replace the main buffer
    e.textBuffer = newBuffer
    e.executer.buffer = newBuffer
    e.executer.motionController.executor.buffer = newBuffer
    e.state.cursor = BufferPosition(line: 0, column: 0)
    e.viewport.topLine = 0
    e.viewport.leftColumn = 0

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

proc editFile*(e: Editor, path: string): Result[(), string] =
  ## Load a file and switch to it (like :e in Vim)
  ## If the buffer already exists in the buffer list, switch to it
  ## If the file doesn't exist, create an empty buffer with the path set (new file)

  logDebug("editor", "editFile called with path: " & path)
  logDebug("editor", "Current buffers.len: " & $e.buffers.len)

  # Check if buffer already exists in the buffer list
  let existingIndex = e.findBufferByPath(path)
  if existingIndex >= 0:
    # Buffer already exists, switch to it
    logDebug("editor", "Buffer already exists at index: " & $existingIndex)
    e.switchToBufferByIndex(existingIndex)
    return ok(())

  # Create new buffer
  let newBuffer = newTextBuffer()

  if fileExists(path):
    # Load existing file
    let loadResult = newBuffer.loadFile(path)
    if loadResult.isErr:
      return err(loadResult.error)
  else:
    # New file: set the path for saving later
    newBuffer.filePath = some(path)

  # Add new buffer to the buffer list
  e.buffers.add(newBuffer)
  logDebug("editor", "Added new buffer, buffers.len now: " & $e.buffers.len)

  # Switch to the new buffer
  e.switchToBufferByIndex(e.buffers.len - 1)
  ok(())

proc newEditor*(): Editor =
  # Load TOML configuration
  let loadResult = loadConfig()
  var editorConfig: EditorConfig
  if loadResult.isOk:
    let (config, vr) = loadResult.get
    editorConfig = config
    if vr.hasErrors:
      for msg in vr.toErrorMessages:
        stderr.writeLine "Config warning: " & msg
  else:
    stderr.writeLine "Config error: " & loadResult.error
    editorConfig = newEditorConfig()

  # Set color mode from configuration
  globalColorMode =
    case editorConfig.standard.colorMode
    of cm24bit: cmk24bit
    of cm8bit: cmk8bit
    of cmNone: cmkNone

  # Initialize theme from configuration
  initTheme(editorConfig)

  # Create registries and configuration first
  let
    cmdRegistry = newCommandRegistry()
    keyRegistry = newKeyBindingRegistry()
    cmdConfig = newCommandConfig()
    cmdLineParser = newCommandLineParser()

  # Register built-in commands and default bindings
  cmdRegistry.registerBuiltinCommands
  keyRegistry.setupDefaultBindings

  # Load custom keybindings from TOML
  keyRegistry.loadDefaultKeybindings()

  # Load command configuration
  cmdConfig.loadDefaultConfig

  # Apply configuration to parser
  cmdConfig.applyToParser(cmdLineParser)

  # Initialize LSP integration with current working directory as workspace root
  let lspIntegration = newLspIntegration(getCurrentDir())

  result = Editor(
    textBuffer: newTextBuffer(),
    lsp: lspIntegration,
    lastLspChangeSeq: 0,
    recentFileModeState: newRecentFileModeState(),
    state: EditorState(
      cursor: BufferPosition(line: 0, column: 0),
      preferredColumn: -1,
        # -1 means not set, will be initialized on first vertical move
      screenCursor: CursorPosition(x: 0, y: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
      # Display settings (grouped in DisplaySettings)
      display: DisplaySettings(
        showStatusLine: editorConfig.standard.statusLine,
        multiStatusLine: editorConfig.statusLine.multipleStatusLine,
        showLineCount: true,
        showLinePercentage: true,
        showEncoding: true,
        showLineNumbers: editorConfig.standard.number,
        showCurrentLineNumber: editorConfig.standard.currentNumber,
        showCursorLine: editorConfig.standard.cursorLine,
        showSyntax: editorConfig.standard.syntax,
        showIndentationLines: editorConfig.standard.indentationLines,
        showSidebar: editorConfig.standard.sidebar,
        showGitDiff: editorConfig.git.showChangedLine,
        showSyntaxChecker: editorConfig.syntaxChecker.enable,
        showCodeLens: true,
        showDocumentHighlight: true,
        lineWrap: true,
        tabStop: editorConfig.standard.tabStop,
        expandTab: editorConfig.standard.expandTab,
        autoIndent: editorConfig.standard.autoIndent,
        autoCloseParen: editorConfig.standard.autoCloseParen,
        autoDeleteParen: editorConfig.standard.autoDeleteParen,
      ),
      needsFullRedraw: true, # Initial render needs full draw
      viewportReservedLines: 2, # Default for single window mode with status line
      # Timing state (grouped in TimingState)
      timing: TimingState(
        lastResizeTime: getMonoTime(),
        lastGitDiffUpdate: getMonoTime(),
        lastGitDiffChangeSeq: 0,
        gitDiffUpdateInterval: editorConfig.git.updateInterval,
        lastAutoSave: getMonoTime(),
        lastAutoBackup: getMonoTime(),
        lastInputTime: getMonoTime(),
        lastFileModCheck: getMonoTime(),
        fileModCheckInterval: 1000, # Check file modification every 1 second
        lastConfigCheck: getMonoTime(),
        lastConfigModTime: times.Time(), # Will be set properly after initialization
        configCheckInterval: 2000, # Check config modification every 2 seconds
      ),
      # Search state (grouped in SearchState)
      search: SearchState(
        text: "",
        lastText: "",
        direction: Forward,
        history:
          if editorConfig.persist.search:
            loadSearchHistory(editorConfig.persist.searchHistoryLimit)
          else:
            @[],
        historyIndex: -1,
        startPos: BufferPosition(line: 0, column: 0),
        ignorecase: editorConfig.standard.ignorecase,
        smartcase: editorConfig.standard.smartcase,
        incsearch: editorConfig.standard.incrementalSearch,
        hlsearch: true,
        hlsearchTempDisabled: false,
      ),
      # Command state (grouped in CommandState)
      commandState: CommandState(
        history:
          if editorConfig.persist.exCommand:
            loadCommandHistory(editorConfig.persist.exCommandHistoryLimit)
          else:
            @[],
        historyIndex: -1,
      ),
      # Macro state (grouped in MacroState)
      macroState: MacroState(
        isRecording: false,
        register: '\0',
        recordedKeys: @[],
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        waitingForRegister: false,
        commandType: "",
        pendingCount: 1,
        playbackDepth: 0,
      ),
      lastKeyWasEscape: false, # Track double-Escape for clearing highlight
      # Edit operation state (grouped in EditState)
      editState: EditState(
        lastMotion: none(Motion),
        lastEditCommand: none(LastEditCommand),
        pendingOperator: none(PendingOperator),
        pendingTextObject: none(PendingTextObject),
        substituteContext: none(SubstituteContext),
        replaceHistory: @[],
        insertModeStartPos: none(BufferPosition),
      ),
      savedViewportTopLine: 0, # Saved viewport position for operators
      # Yank register (internal clipboard) - DEPRECATED
      yankRegister: "", # Empty initially
      yankIsLine: false, # Not linewise initially
      # Full register system
      registers: initRegisters(),
      pendingRegister: none(char),
      # Jump list
      jumpList: @[], # Empty jump list initially
      jumpListIndex: -1, # Not navigating jump list initially
      # Command mode completion
      commandCompletionManager: newCommandCompletionManager(),
      # LSP cache state (grouped in LspCacheState)
      lspCache: LspCacheState(
        codeLensCache: CodeLensCache(isValid: false),
        codeLensPicker: CodeLensPicker(isActive: false),
        documentHighlightCache: DocumentHighlightCache(isValid: false),
        semanticTokensCache: SemanticTokensCache(isValid: false),
        hoverPopup: newHoverPopupManager(),
        locations: none(LspLocationsResult),
        lastCodeLensUpdate: getMonoTime(),
        codeLensUpdateInterval: 1000, # 1 second debounce
        lastDocumentHighlightUpdate: getMonoTime(),
        documentHighlightUpdateInterval: 200, # 200ms debounce
        lastSemanticTokensUpdate: getMonoTime(),
        semanticTokensUpdateInterval: 500, # 500ms debounce for semantic tokens
      ),
    ),
    viewport: ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 20, x: 0, y: 0),
    commandRegistry: cmdRegistry,
    keyBindingRegistry: keyRegistry,
    commandLineParser: cmdLineParser,
    commandConfig: cmdConfig,
    handlerManager: nil, # Will be set after executer is created
    windowManager: newEditorWindowManager(),
    buffers: @[], # Will be initialized below
    config: editorConfig, # Store configuration
    cursorPositions:
      if editorConfig.persist.cursorPosition:
        loadCursorPositions()
      else:
        initTable[string, CursorPositionEntry](),
  )

  # Add initial buffer to buffer list
  result.buffers.add(result.textBuffer)
  logDebug("editor", "Initial buffer added, buffers.len: " & $result.buffers.len)

  # Set reserved words for syntax highlighting on initial buffer
  result.textBuffer.setReservedWords(
    toReservedWords(editorConfig.highlight.reservedWord)
  )

  result.executer = newCommandExecutor(
    result.textBuffer,
    result.state,
    result.viewport,
    result.config.clipboard,
    result.config.notification,
    some(cmdRegistry),
    some(keyRegistry),
  )

  # Create handler manager after executer (which creates motion controller)
  result.handlerManager = newHandlerManager(
    result.executer.motionController, keyRegistry, cmdLineParser, cmdConfig,
    cmdRegistry, result.config.clipboard, result.config.smoothScroll,
    result.config.notification, result.lsp, result.config.autocomplete.enable,
  )

  # Set clipboard tool for register system
  if result.config.clipboard.enable:
    result.state.registers.setClipboardTool(result.config.clipboard.tool)

  # Apply LSP enable setting from config
  result.lsp.setEnabled(result.config.lsp.enable)

  # Initialize config file modification time for liveReloadOfConf
  let configPath = getConfigPath()
  if fileExists(configPath):
    try:
      result.state.timing.lastConfigModTime = getFileInfo(configPath).lastWriteTime
    except OSError:
      discard

proc refreshGitDiff*(e: Editor, useBuffer: bool = true) =
  ## Refresh git diff information for the active buffer
  ## This should be called after saving a file or buffer modifications
  ##
  ## Parameters:
  ## - useBuffer: If true, compare buffer contents with HEAD (real-time)
  ##              If false, compare disk file with working tree (saved only)
  if e.state.display.showGitDiff:
    let activeBuffer = e.activeBuffer()
    let diffResult = updateBufferWithGitDiff(activeBuffer, useBuffer)

    if diffResult.isOk:
      e.state.timing.lastGitDiffUpdate = getMonoTime()
      e.state.timing.lastGitDiffChangeSeq = activeBuffer.changeSeq
      e.state.needsFullRedraw = true

proc maybeReloadExternallyModifiedFile*(e: Editor) =
  ## Check if files were modified externally and reload them if:
  ##   - liveReloadOfFile is enabled in config
  ##   - Buffer has no unsaved changes (if modified, just show a message)
  ##   - Enough time has passed since last check (debouncing)

  if not e.config.standard.liveReloadOfFile:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastFileModCheck
  let threshold = initDuration(milliseconds = e.state.timing.fileModCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastFileModCheck = now

  # Check the active buffer
  let activeBuffer = e.activeBuffer()
  if not activeBuffer.isExternallyModified():
    return

  let filePath =
    if activeBuffer.filePath.isSome:
      activeBuffer.filePath.get
    else:
      return

  # If buffer has unsaved changes, warn the user instead of reloading
  if activeBuffer.isModified:
    e.state.setStatusMessage(
      "Warning: " & filePath & " changed on disk (buffer has unsaved changes)"
    )
    # Update lastFileModTime to avoid repeated warnings
    try:
      activeBuffer.lastFileModTime = some(getFileInfo(filePath).lastWriteTime)
    except OSError:
      discard
    return

  # Reload the file
  logInfo("editor", "File externally modified, reloading: " & filePath)
  let reloadResult = activeBuffer.reloadFile()
  if reloadResult.isOk:
    e.state.setStatusMessage("File reloaded: " & filePath)
    e.state.needsFullRedraw = true
    # Update git diff after reload
    e.refreshGitDiff(useBuffer = false)
  else:
    e.state.setStatusMessage("Failed to reload file: " & reloadResult.error)

proc applyConfigSettings(e: Editor, newConfig: EditorConfig) =
  ## Apply configuration settings to the editor
  ## Updates display settings, search settings, and other runtime state
  ## Note: Some settings require editor restart to take effect

  # Update display settings from config
  e.state.display.showStatusLine = newConfig.standard.statusLine
  e.state.display.multiStatusLine = newConfig.statusLine.multipleStatusLine
  e.state.display.showLineNumbers = newConfig.standard.number
  e.state.display.showCurrentLineNumber = newConfig.standard.currentNumber
  e.state.display.showCursorLine = newConfig.standard.cursorLine
  e.state.display.showSyntax = newConfig.standard.syntax
  e.state.display.showIndentationLines = newConfig.standard.indentationLines
  e.state.display.showSidebar = newConfig.standard.sidebar
  e.state.display.showGitDiff = newConfig.git.showChangedLine
  e.state.display.showSyntaxChecker = newConfig.syntaxChecker.enable
  e.state.display.tabStop = newConfig.standard.tabStop
  e.state.display.expandTab = newConfig.standard.expandTab
  e.state.display.autoIndent = newConfig.standard.autoIndent
  e.state.display.autoCloseParen = newConfig.standard.autoCloseParen
  e.state.display.autoDeleteParen = newConfig.standard.autoDeleteParen

  # Update search settings
  e.state.search.ignorecase = newConfig.standard.ignorecase
  e.state.search.smartcase = newConfig.standard.smartcase
  e.state.search.incsearch = newConfig.standard.incrementalSearch

  # Update timing intervals
  e.state.timing.gitDiffUpdateInterval = newConfig.git.updateInterval

  # Update color mode
  globalColorMode =
    case newConfig.standard.colorMode
    of cm24bit: cmk24bit
    of cm8bit: cmk8bit
    of cmNone: cmkNone

  # Update clipboard tool if enabled
  if newConfig.clipboard.enable:
    e.state.registers.setClipboardTool(newConfig.clipboard.tool)

  # Update reserved words on all buffers
  let reservedWords = toReservedWords(newConfig.highlight.reservedWord)
  for buf in e.buffers:
    buf.setReservedWords(reservedWords)

  # Reload theme if configured
  initTheme(newConfig)

  # Update LSP enable/disable
  e.lsp.setEnabled(newConfig.lsp.enable)

  # Store the new config
  e.config = newConfig

proc maybeReloadConfig*(e: Editor) =
  ## Check if config file was modified and reload if:
  ##   - liveReloadOfConf is enabled in config
  ##   - Enough time has passed since last check (debouncing)
  ##   - Config file modification time has changed

  if not e.config.standard.liveReloadOfConf:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastConfigCheck
  let threshold = initDuration(milliseconds = e.state.timing.configCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastConfigCheck = now

  # Check if config file exists and has been modified
  let configPath = getConfigPath()
  if not fileExists(configPath):
    return

  var currentModTime: times.Time
  try:
    currentModTime = getFileInfo(configPath).lastWriteTime
  except OSError:
    return

  # Compare modification times
  if currentModTime == e.state.timing.lastConfigModTime:
    return

  # Config file was modified, reload it
  logInfo("editor", "Config file modified, reloading: " & configPath)
  let loadResult = loadConfigFromToml(configPath)
  if loadResult.isErr:
    logError("editor", "Failed to reload config: " & loadResult.error)
    return

  let (newConfig, vr) = loadResult.get
  if vr.hasErrors:
    for msg in vr.toErrorMessages:
      logWarn("editor", "Config warning: " & msg)

  # Apply the new settings
  e.applyConfigSettings(newConfig)

  # Update last known modification time
  e.state.timing.lastConfigModTime = currentModTime

  e.state.setStatusMessage("Configuration reloaded")
  e.state.needsFullRedraw = true

proc maybeUpdateGitDiff*(e: Editor) =
  ## Update git diff if buffer was modified and enough time has passed (debouncing)
  ## This should be called after buffer modifications to provide real-time updates

  if not e.state.display.showGitDiff:
    return

  let activeBuffer = e.activeBuffer()

  # Only update if buffer has changed since last update
  if activeBuffer.changeSeq == e.state.timing.lastGitDiffChangeSeq:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastGitDiffUpdate

  # Compare with threshold duration (500ms)
  let threshold = initDuration(milliseconds = e.state.timing.gitDiffUpdateInterval)

  if elapsed >= threshold:
    e.refreshGitDiff(useBuffer = true)

proc enterRecentFileMode*(e: Editor): Result[void, string] =
  ## Enter Recent File mode by loading recently used files
  let loadResult = e.recentFileModeState.loadRecentFiles()
  if loadResult.isErr:
    return err(loadResult.error)
  ok()

proc loadFile*(e: Editor, path: string): Result[(), string] =
  ## Load text file
  logDebug("editor", "Loading file: " & path)
  let r = e.textBuffer.loadFile(path)
  if r.isErr:
    logError("editor", "Failed to load file " & path & ": " & r.error)
    return err r.error

  logInfo("editor", "Successfully loaded file: " & path)

  # Set reserved words for syntax highlighting from config
  e.textBuffer.setReservedWords(toReservedWords(e.config.highlight.reservedWord))

  # Restore cursor position if persisted, otherwise reset to file start
  let absPath = absolutePath(path)
  if e.config.persist.cursorPosition and e.cursorPositions.hasKey(absPath):
    let savedPos = e.cursorPositions[absPath]
    # Ensure cursor position is within buffer bounds
    let line = min(savedPos.line, max(0, e.textBuffer.len - 1))
    let col =
      if line < e.textBuffer.len:
        min(savedPos.column, max(0, e.textBuffer.getLine(line).charLen - 1))
      else:
        0
    e.state.cursor = BufferPosition(line: line, column: col)
    logDebug("editor", fmt"Restored cursor position for {path}: line={line}, col={col}")
  else:
    e.state.cursor = BufferPosition(line: 0, column: 0)

  # Reset viewport to start (will be adjusted by motion controller)
  e.viewport.topLine = 0
  e.viewport.leftColumn = 0

  # Update git diff information if sidebar and git diff are enabled
  # Use useBuffer=false to compare disk file with working tree (not buffer with HEAD)
  if e.state.display.showGitDiff:
    let diffResult = updateBufferWithGitDiff(e.textBuffer, useBuffer = false)
    if diffResult.isErr:
      # Log error but don't fail the file load
      # (file might not be in a git repository)
      logDebug("editor", "Git diff not available for " & path & ": " & diffResult.error)
    else:
      # Update lastGitDiffChangeSeq to prevent immediate re-check
      e.state.timing.lastGitDiffChangeSeq = e.textBuffer.changeSeq

  # LSP initialization - non-blocking, will start in background
  if e.lsp.enabled:
    let lspResult = e.lsp.onBufferOpen(e.textBuffer)
    if lspResult.isErr:
      logDebug("editor", "LSP onBufferOpen failed for " & path & ": " & lspResult.error)
    else:
      e.lastLspChangeSeq = e.textBuffer.changeSeq

  ok(())

proc saveBufferCursorPosition*(e: Editor, buffer: TextBuffer) =
  ## Save cursor position for a buffer if persist.cursorPosition is enabled
  if not e.config.persist.cursorPosition:
    return
  if buffer.filePath.isNone:
    return
  let absPath = absolutePath(buffer.filePath.get)
  e.cursorPositions[absPath] =
    CursorPositionEntry(line: e.state.cursor.line, column: e.state.cursor.column)

proc addCommandToHistory*(e: Editor, command: string) =
  ## Add a command to the command history
  ## Skips empty commands and duplicates of the last entry
  if command.len == 0:
    return
  # Skip if same as last entry
  if e.state.commandState.history.len > 0 and e.state.commandState.history[0] == command:
    return
  # Add to beginning (most recent first)
  e.state.commandState.history.insert(command, 0)
  # Trim to limit
  let limit = e.config.persist.exCommandHistoryLimit
  if e.state.commandState.history.len > limit:
    e.state.commandState.history.setLen(limit)

proc savePersistData*(e: Editor) =
  ## Save all persist data (search history, command history, cursor positions)
  ## Called on shutdown

  # Save search history
  if e.config.persist.search:
    let r =
      saveSearchHistory(e.state.search.history, e.config.persist.searchHistoryLimit)
    if r.isErr:
      logError("editor", "Failed to save search history: " & r.error)

  # Save command history
  if e.config.persist.exCommand:
    let r = saveCommandHistory(
      e.state.commandState.history, e.config.persist.exCommandHistoryLimit
    )
    if r.isErr:
      logError("editor", "Failed to save command history: " & r.error)

  # Save cursor positions
  if e.config.persist.cursorPosition:
    # Save current buffer's cursor position first
    let activeBuffer = e.activeBuffer()
    e.saveBufferCursorPosition(activeBuffer)
    # Save all positions
    let r = saveCursorPositions(e.cursorPositions)
    if r.isErr:
      logError("editor", "Failed to save cursor positions: " & r.error)

proc saveFile*(
    e: Editor, path: Option[string] = none(string), force: bool = false
): Result[(), string] =
  ## Save the active buffer to file
  ## If path is provided, save to that path, otherwise use buffer's current file path
  ## If force is false, check if file was modified externally and refuse to save
  let activeBuffer = e.activeBuffer()

  # Determine the file path to save to
  let savePath =
    if path.isSome:
      path.get
    elif activeBuffer.filePath.isSome:
      activeBuffer.filePath.get
    else:
      logError("editor", "Save failed: No file path specified")
      return err("No file path specified")

  # Check for external modification (unless force is true)
  if not force and activeBuffer.isExternallyModified():
    logError("editor", "Save failed: File was modified externally: " & savePath)
    return err("File was modified externally. Use :w! to force save, or :e! to reload.")

  # Save the file
  logDebug("editor", "Saving file: " & savePath)
  let saveResult = activeBuffer.saveFile(savePath)
  if saveResult.isErr:
    logError("editor", "Failed to save file " & savePath & ": " & saveResult.error)
    return err(saveResult.error)

  logInfo("editor", "Successfully saved file: " & savePath)

  # Update git diff information after saving (use disk file for comparison)
  e.refreshGitDiff(useBuffer = false)

  # Notify LSP that a document was saved
  if e.lsp.enabled:
    let lspResult = e.lsp.onBufferSave(activeBuffer)
    if lspResult.isErr:
      logDebug(
        "editor", "LSP onBufferSave failed for " & savePath & ": " & lspResult.error
      )

  ok(())

proc autoSave*(e: Editor) =
  ## Automatically save modified buffers if auto save is enabled and interval has passed
  ## This should be called periodically (e.g., from render loop)
  ##
  ## Conditions for auto save:
  ## - autoSave.enable is true in config
  ## - Buffer has been modified (isModified)
  ## - Buffer has a file path
  ## - Enough time has passed since last auto save (interval in minutes)

  if not e.config.autoSave.enable:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastAutoSave

  # Convert interval from minutes to Duration
  let intervalMinutes = e.config.autoSave.interval
  let threshold = initDuration(minutes = intervalMinutes)

  if elapsed < threshold:
    return

  # Check all windows for modified buffers and save them
  var savedCount = 0
  var savedPaths: seq[string] = @[]

  if e.windowManager.windows.len > 0:
    # Multi-window mode: check each window's buffer
    var savedBuffers: seq[TextBuffer] =
      @[] # Track already saved buffers to avoid duplicates

    for window in e.windowManager.windows:
      let buffer = window.buffer

      # Skip if already saved (same buffer in multiple windows)
      if buffer in savedBuffers:
        continue

      # Check if buffer is modified and has a file path
      if buffer.isModified and buffer.filePath.isSome:
        let savePath = buffer.filePath.get

        # Skip externally modified files to avoid overwriting external changes
        if buffer.isExternallyModified():
          logDebug(
            "editor", "Skipping auto save for externally modified file: " & savePath
          )
          continue

        let saveResult = buffer.saveFile(savePath)

        if saveResult.isOk:
          savedBuffers.add(buffer)
          savedCount += 1
          savedPaths.add(savePath)

          # Refresh git diff after saving
          if e.state.display.showGitDiff:
            discard updateBufferWithGitDiff(buffer, useBuffer = false)

          # Notify LSP that a document was saved
          if e.lsp.enabled:
            discard e.lsp.onBufferSave(buffer)
        else:
          logError(
            "editor", "Auto save failed for " & savePath & ": " & saveResult.error
          )
  else:
    # Single window mode: check the main buffer
    if e.textBuffer.isModified and e.textBuffer.filePath.isSome:
      let savePath = e.textBuffer.filePath.get

      # Skip externally modified files to avoid overwriting external changes
      if e.textBuffer.isExternallyModified():
        logDebug(
          "editor", "Skipping auto save for externally modified file: " & savePath
        )
        return

      let saveResult = e.textBuffer.saveFile(savePath)

      if saveResult.isOk:
        savedCount += 1
        savedPaths.add(savePath)

        # Refresh git diff after saving
        e.refreshGitDiff(useBuffer = false)

        # Notify LSP that a document was saved
        if e.lsp.enabled:
          discard e.lsp.onBufferSave(e.textBuffer)
      else:
        logError("editor", "Auto save failed for " & savePath & ": " & saveResult.error)

  # Update last auto save time
  e.state.timing.lastAutoSave = now

  # Show notification if any files were saved
  if savedCount > 0:
    # Log notification
    if e.config.notification.logNotifications and e.config.notification.autoSaveLogNotify:
      if savedCount == 1:
        logInfo("editor", "Auto saved: " & savedPaths[0])
      else:
        logInfo("editor", "Auto saved " & $savedCount & " files")

    # Screen notification (status message)
    if e.config.notification.screenNotifications and
        e.config.notification.autoSaveScreenNotify:
      if savedCount == 1:
        e.state.statusMessage = "Auto saved: " & savedPaths[0]
      else:
        e.state.statusMessage = "Auto saved " & $savedCount & " files"

proc updateInputTime*(e: Editor) =
  ## Update the last input time (called when user provides input)
  e.state.timing.lastInputTime = getMonoTime()

proc autoBackup*(e: Editor) =
  ## Automatically backup modified buffers if auto backup is enabled
  ## This should be called periodically (e.g., from render loop)
  ##
  ## Conditions for auto backup:
  ## - autoBackup.enable is true in config
  ## - User has been idle for idleTime seconds
  ## - Enough time has passed since last backup (interval in minutes)

  if not e.config.autoBackup.enable:
    return

  let now = getMonoTime()

  # Check idle time (user must be idle for idleTime seconds)
  let idleElapsed = now - e.state.timing.lastInputTime
  let idleThreshold = initDuration(seconds = e.config.autoBackup.idleTime)

  if idleElapsed < idleThreshold:
    return

  # Check backup interval (must have passed interval minutes since last backup)
  let backupElapsed = now - e.state.timing.lastAutoBackup
  let backupThreshold = initDuration(minutes = e.config.autoBackup.interval)

  if backupElapsed < backupThreshold:
    return

  # Backup all modified buffers
  var backupCount = 0
  var backupPaths: seq[string] = @[]

  if e.windowManager.windows.len > 0:
    # Multi-window mode: backup each window's buffer
    var backedUpBuffers: seq[TextBuffer] =
      @[] # Track already backed up buffers to avoid duplicates

    for window in e.windowManager.windows:
      let buffer = window.buffer

      # Skip if already backed up (same buffer in multiple windows)
      if buffer in backedUpBuffers:
        continue

      # Only backup modified buffers with a file path
      if buffer.isModified and buffer.filePath.isSome:
        let backupResult = backupBuffer(buffer, e.config.autoBackup)

        if backupResult.isOk:
          backedUpBuffers.add(buffer)
          backupCount += 1
          backupPaths.add(backupResult.get)
        elif backupResult.error != "No changes since last backup":
          logError("editor", "Auto backup failed: " & backupResult.error)
  else:
    # Single window mode: backup the main buffer
    if e.textBuffer.isModified and e.textBuffer.filePath.isSome:
      let backupResult = backupBuffer(e.textBuffer, e.config.autoBackup)

      if backupResult.isOk:
        backupCount += 1
        backupPaths.add(backupResult.get)
      elif backupResult.error != "No changes since last backup":
        logError("editor", "Auto backup failed: " & backupResult.error)

  # Show notification and update last backup time only if any files were backed up
  if backupCount > 0:
    # Update last backup time only when backup actually occurred
    e.state.timing.lastAutoBackup = now

    # Log notification
    if e.config.notification.logNotifications and
        e.config.notification.autoBackupLogNotify:
      if backupCount == 1:
        logInfo("editor", "Auto backup: " & backupPaths[0])
      else:
        logInfo("editor", "Auto backup: " & $backupCount & " files")

    # Screen notification (status message)
    if e.config.notification.screenNotifications and
        e.config.notification.autoBackupScreenNotify:
      if backupCount == 1:
        e.state.statusMessage = "Auto backup created"
      else:
        e.state.statusMessage = "Auto backup: " & $backupCount & " files"

proc colorIndexToStyle(colorIdx: EditorColorPairIndex): Style =
  ## Convert EditorColorPairIndex to Celina Style using theme colors
  getThemeStyle(colorIdx)

proc analyzeIndentation(lineText: string): IndentInfo =
  ## Analyze a line once to determine indentation properties
  ## Returns cached information to avoid repeated line scanning (O(n) instead of O(n²))
  result.leadingWhitespaceEnd = -1
  result.hasContent = false

  var charIdx = 0
  for rune in lineText.runes:
    if rune != ' '.Rune and rune != TAB_CHAR:
      # Found first non-whitespace character
      result.leadingWhitespaceEnd = charIdx - 1
      result.hasContent = true
      break
    charIdx += 1

proc shouldShowIndentationGuide(
    e: Editor, indentInfo: IndentInfo, displayX: int, charIdx: int
): bool =
  ## Check if an indentation guide should be shown at this position
  ## Uses cached indentInfo to avoid O(n²) performance
  ## displayX: the display column position (accounting for tabs)
  ## charIdx: the character index in the line
  if not e.state.display.showIndentationLines:
    return false

  # Don't show indentation guides in utility buffers (jumplist, log, etc.)
  if e.activeBuffer().isUtilityBuffer:
    return false

  # Only show guides at indent levels (multiples of tabStop)
  if displayX mod e.state.display.tabStop != 0:
    return false

  # Don't show on column 0
  if displayX == 0:
    return false

  # Check if this position is within leading whitespace
  if charIdx < 0:
    return false

  # Use cached indentation info: O(1) instead of O(n)
  # Show guide only if we're within leading whitespace and line has content
  return indentInfo.hasContent and charIdx <= indentInfo.leadingWhitespaceEnd

proc isPositionInDocumentHighlight(e: Editor, pos: BufferPosition): Option[int] =
  ## Check if position is within any document highlight range
  ## Returns the highlight kind (1=Text, 2=Read, 3=Write) if found, none otherwise
  ## Uses O(1) line lookup + O(m) column search where m is highlights on that line
  if not e.state.display.showDocumentHighlight or
      not e.state.lspCache.documentHighlightCache.isValid:
    return none(int)

  # O(1) lookup by line
  let items =
    e.state.lspCache.documentHighlightCache.itemsByLine.getOrDefault(pos.line, @[])
  for item in items:
    if pos.column >= item.startColumn and pos.column < item.endColumn:
      return some(item.kind)

  return none(int)

proc getDocumentHighlightStyle(kind: int): Style =
  ## Get the style for a document highlight based on its kind
  case kind
  of 2: # Read
    documentHighlightReadStyle()
  of 3: # Write
    documentHighlightWriteStyle()
  else: # Text or unknown
    documentHighlightTextStyle()

proc extractSubstitutePattern*(commandText: string): string =
  ## Extract the search pattern from a substitute command
  ## Supports formats like :%s/pattern/replacement/flags or :s/pattern/...
  ## Returns empty string if not a substitute command or pattern is incomplete
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid:
    # Return raw pattern without escape processing (for display/matching)
    return parsed.pattern
  return ""

proc extractSubstituteReplacement*(
    commandText: string
): tuple[replacement: string, hasReplacement: bool] =
  ## Extract the replacement text from a substitute command
  ## Returns (replacement, true) if replacement section exists (even if empty)
  ## Returns ("", false) if we haven't reached the replacement section yet
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid and parsed.hasReplacement:
    return (parsed.replacement, true)
  return ("", false)

proc extractSubstituteFlags*(commandText: string): string =
  ## Extract the flags from a substitute command
  let parsed = parseSubstituteCommand(commandText)
  if parsed.isValid:
    return parsed.flags
  return ""

proc startSubstitutePreview*(e: Editor) =
  ## Start substitute preview by saving the current buffer content
  if e.state.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  e.state.substitutePreview.originalLines = @[]
  for i in 0 ..< buffer.len:
    e.state.substitutePreview.originalLines.add(buffer.getLine(i))
  e.state.substitutePreview.isActive = true
  e.state.substitutePreview.lastPattern = ""
  e.state.substitutePreview.lastReplacement = ""

proc restoreFromPreview(e: Editor) =
  ## Restore buffer content from preview snapshot
  if not e.state.substitutePreview.isActive:
    return

  let buffer = e.activeBuffer()
  # Restore all lines from snapshot
  for i in 0 ..< e.state.substitutePreview.originalLines.len:
    if i < buffer.len:
      buffer.gapBuffer.replaceLine(i, e.state.substitutePreview.originalLines[i])

  # Handle line count differences
  while buffer.len > e.state.substitutePreview.originalLines.len:
    buffer.gapBuffer.deleteLine(buffer.len - 1)
  while buffer.len < e.state.substitutePreview.originalLines.len:
    buffer.gapBuffer.insertLine(
      buffer.len, e.state.substitutePreview.originalLines[buffer.len]
    )

  buffer.highlightNeedsUpdate = true

proc cancelSubstitutePreview*(e: Editor) =
  ## Cancel substitute preview and restore original content
  if not e.state.substitutePreview.isActive:
    return

  e.restoreFromPreview()
  e.state.substitutePreview.isActive = false
  e.state.substitutePreview.originalLines = @[]
  e.state.needsFullRedraw = true

proc commitSubstitutePreview*(e: Editor) =
  ## Commit substitute preview (discard snapshot, keep current changes)
  e.state.substitutePreview.isActive = false
  e.state.substitutePreview.originalLines = @[]

proc updateSubstitutePreview*(
    e: Editor, pattern: string, replacement: string, isGlobalFlag: bool = true
) =
  ## Update substitute preview with new pattern and replacement
  ## isGlobalFlag: if true, replace all occurrences per line; if false, only first occurrence
  if not e.state.substitutePreview.isActive:
    return

  # Skip if nothing changed
  if pattern == e.state.substitutePreview.lastPattern and
      replacement == e.state.substitutePreview.lastReplacement:
    return

  e.state.substitutePreview.lastPattern = pattern
  e.state.substitutePreview.lastReplacement = replacement

  # Restore from snapshot first
  e.restoreFromPreview()

  if pattern.len == 0:
    e.state.needsFullRedraw = true
    return

  # Process escape sequences in replacement using common utility
  let processedReplacement = processEscapeSequences(replacement)

  # Apply substitute to buffer
  let buffer = e.activeBuffer()
  for lineIdx in 0 ..< buffer.len:
    var line = buffer.getLine(lineIdx)
    var newLine = ""
    var searchPos = 0
    var modified = false

    while searchPos <= line.len:
      let idx = line.find(pattern, searchPos)
      if idx < 0:
        newLine.add(line[searchPos ..^ 1])
        break

      if idx > searchPos:
        newLine.add(line[searchPos ..< idx])

      newLine.add(processedReplacement)
      modified = true
      searchPos = idx + pattern.len

      # If not global flag, only replace first occurrence per line
      if not isGlobalFlag:
        newLine.add(line[searchPos ..^ 1])
        break

    if modified:
      buffer.gapBuffer.replaceLine(lineIdx, newLine)

  buffer.highlightNeedsUpdate = true
  e.state.needsFullRedraw = true

proc getSelectionStyle(
    e: Editor,
    buffer: TextBuffer,
    hasSelection: bool,
    pos: BufferPosition,
    cursorLine: int,
    cursorCol: int,
): Style =
  ## Get the appropriate style for a character based on selection state and syntax
  # Check if this is the cursor position
  let isCursorPos = (pos.line == cursorLine and pos.column == cursorCol)

  # Check if this position is the matching paren (highlight matching paren)
  let isMatchingParen =
    e.state.matchingParenPos.isSome and e.state.matchingParenPos.get.line == pos.line and
    e.state.matchingParenPos.get.column == pos.column

  # Check if this position is part of the current word (highlight all occurrences)
  # Skip the word under cursor itself - only highlight other occurrences
  # Also skip in Search mode to avoid interfering with search highlighting
  let isInSameWordAsCursor =
    pos.line == cursorLine and e.state.currentWord.len > 0 and
    buffer.isPositionInWord(pos, e.state.currentWord)

  let isInCurrentWord =
    e.state.mode != EditorMode.Search and e.state.currentWord.len > 0 and
    not isInSameWordAsCursor and buffer.isPositionInWord(pos, e.state.currentWord)

  if hasSelection and e.state.visualSelection.isPositionInSelection(pos):
    visualStyle()
  elif isMatchingParen:
    # Highlight matching paren with special style
    parenPairStyle()
  elif isCursorPos:
    # Cursor position: always use gray foreground color
    cursorCharStyle()
  elif isInCurrentWord:
    # Highlight other occurrences of the current word
    # (disabled in Search mode to avoid interfering with search highlighting)
    currentWordStyle()
  elif e.state.search.hlsearch and not e.state.search.hlsearchTempDisabled:
    # Determine which search pattern to use:
    # - In Search mode with text: use current searchText (incremental highlight)
    # - In Search mode without text: no highlight (user is starting a new search)
    # - In Command mode with substitute command: use substitute pattern (incremental highlight)
    # - Not in Search mode: use lastSearchText (persistent highlight from previous search)
    let searchPattern =
      if e.state.mode == EditorMode.Search:
        # In Search mode: only highlight if user has typed something
        if e.state.search.text.len > 0:
          e.state.search.text
        else:
          "" # No highlight when starting a new search
      elif e.state.mode == EditorMode.Command:
        # In Command mode: check for substitute command pattern
        let subPattern = extractSubstitutePattern(e.state.commandText)
        if subPattern.len > 0: subPattern else: e.state.search.lastText
      else:
        # Not in Search mode: use last search pattern
        e.state.search.lastText

    # Only apply highlight if we have a valid search pattern
    if searchPattern.len > 0:
      # Apply smartcase logic
      let shouldIgnoreCase = shouldIgnoreCase(
        searchPattern, e.state.search.ignorecase, e.state.search.smartcase
      )

      if buffer.isPositionInSearchMatch(
        pos, searchPattern, shouldIgnoreCase, e.state.search.wholeWord
      ):
        searchHighlightStyle()
      elif e.state.display.showSyntax and not buffer.highlight.isNil:
        # Apply syntax highlighting from buffer
        # Update highlight if needed (after text edits)
        buffer.updateHighlight()
        let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
        var style = colorIndexToStyle(colorPair)
        # Apply document highlight or cursor line highlighting
        let highlightKind = e.isPositionInDocumentHighlight(pos)
        if highlightKind.isSome:
          style.bg = getDocumentHighlightStyle(highlightKind.get).bg
        elif e.state.display.showCursorLine and pos.line == cursorLine:
          style.bg = cursorLineHighlightStyle().bg
        style
      else:
        # Check document highlight first
        let highlightKind = e.isPositionInDocumentHighlight(pos)
        if highlightKind.isSome:
          getDocumentHighlightStyle(highlightKind.get)
        elif e.state.display.showCursorLine and pos.line == cursorLine:
          cursorLineHighlightStyle()
        else:
          normalStyle()
    elif e.state.display.showSyntax and not buffer.highlight.isNil:
      # Apply syntax highlighting from buffer
      # Update highlight if needed (after text edits)
      buffer.updateHighlight()
      let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
      var style = colorIndexToStyle(colorPair)
      # Apply document highlight or cursor line highlighting
      let highlightKind = e.isPositionInDocumentHighlight(pos)
      if highlightKind.isSome:
        style.bg = getDocumentHighlightStyle(highlightKind.get).bg
      elif e.state.display.showCursorLine and pos.line == cursorLine:
        style.bg = cursorLineHighlightStyle().bg
      style
    else:
      # Check document highlight first
      let highlightKind = e.isPositionInDocumentHighlight(pos)
      if highlightKind.isSome:
        getDocumentHighlightStyle(highlightKind.get)
      elif e.state.display.showCursorLine and pos.line == cursorLine:
        cursorLineHighlightStyle()
      else:
        normalStyle()
  elif e.state.display.showSyntax and not buffer.highlight.isNil:
    # Apply syntax highlighting from buffer
    # Update highlight if needed (after text edits)
    buffer.updateHighlight()
    let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
    var style = colorIndexToStyle(colorPair)
    # Apply document highlight or cursor line highlighting
    let highlightKind = e.isPositionInDocumentHighlight(pos)
    if highlightKind.isSome:
      style.bg = getDocumentHighlightStyle(highlightKind.get).bg
    elif e.state.display.showCursorLine and pos.line == cursorLine:
      style.bg = cursorLineHighlightStyle().bg
    style
  else:
    # Check document highlight first
    let highlightKind = e.isPositionInDocumentHighlight(pos)
    if highlightKind.isSome:
      getDocumentHighlightStyle(highlightKind.get)
    elif e.state.display.showCursorLine and pos.line == cursorLine:
      cursorLineHighlightStyle()
    else:
      normalStyle()

proc isVisualMode(mode: EditorMode): bool {.inline.} =
  ## Check if the mode is any visual mode variant
  mode in {EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine}

proc getVisualSelection(
    e: Editor, windowActive: bool = true
): tuple[hasSelection: bool, selStart, selEnd: BufferPosition] =
  ## Get visual selection range if active
  ## windowActive: only show selection in active window (default true for compatibility)
  let hasSelection =
    isVisualMode(e.state.mode) and e.state.visualSelection.active and windowActive

  if hasSelection:
    let (start, endPos) = e.state.visualSelection.getSelectionRange()
    result = (hasSelection: true, selStart: start, selEnd: endPos)
  else:
    result = (
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
    )

proc renderLineSegmentWithSelection(
    e: Editor,
    textBuffer: TextBuffer,
    buffer: var Buffer,
    displayLine: string,
    screenX, screenY: int,
    lineIndex: int,
    startColumn: int,
    ctx: RenderContext,
    useRunes: bool = true,
) =
  ## Render a line segment with selection highlighting and syntax highlighting
  ## useRunes: true for wrapped mode (character-based), false for byte-based rendering
  ## ctx: RenderContext containing cursor position and selection information

  # Get the full line for indentation guide checking
  let fullLine = textBuffer.getLine(lineIndex)
  # Analyze indentation once (O(n)) to avoid repeated scanning (O(n²))
  let indentInfo = analyzeIndentation(fullLine)
  # Find where trailing spaces start (for highlighting)
  let trailingSpaceStart = findTrailingSpaceStart(fullLine)

  # Always render character by character to apply syntax highlighting
  var displayX = 0

  # Template to render a single character (eliminates code duplication)
  # Using template instead of proc to avoid closure capture issues
  template renderChar(rune: Rune, col: int, style: Style) =
    # Handle tab character specially
    if rune == TAB_CHAR:
      # Calculate how many spaces until next tab stop
      let spacesToNextTab =
        e.state.display.tabStop - (displayX mod e.state.display.tabStop)
      # Determine style for tab (trailing space highlighting takes priority)
      let tabStyle =
        if e.config.highlight.trailingSpaces and col >= trailingSpaceStart:
          trailingSpacesStyle()
        else:
          style
      # Render spaces instead of tab character
      for i in 0 ..< spacesToNextTab:
        if screenX + displayX < buffer.area.width:
          # Check if we should show indentation guide at this position
          if e.shouldShowIndentationGuide(indentInfo, displayX, col):
            buffer.setString(screenX + displayX, screenY, "│", indentationLineStyle())
          else:
            buffer.setString(screenX + displayX, screenY, " ", tabStyle)
        displayX += 1
    else:
      # Normal character
      var charStr = $rune
      var renderStyle = style

      # Check if this is a space and should show indentation guide
      if rune == ' '.Rune and e.shouldShowIndentationGuide(indentInfo, displayX, col):
        charStr = "│"
        renderStyle = indentationLineStyle()

      # Highlight full-width space if enabled
      if rune == FULLWIDTH_SPACE and e.config.highlight.fullWidthSpace:
        renderStyle = fullWidthSpaceStyle()

      # Highlight trailing spaces if enabled
      if e.config.highlight.trailingSpaces and col >= trailingSpaceStart:
        if rune == ' '.Rune or rune == TAB_CHAR or rune == FULLWIDTH_SPACE:
          renderStyle = trailingSpacesStyle()

      if screenX + displayX < buffer.area.width:
        buffer.setString(screenX + displayX, screenY, charStr, renderStyle)
      # Account for character width (wide characters like CJK are width 2)
      displayX += runeWidth(rune)

  if useRunes:
    # Character-based rendering (for wrapped mode)
    var charIdx = startColumn
    for rune in displayLine.runes:
      let
        pos = BufferPosition(line: lineIndex, column: charIdx)
        style = e.getSelectionStyle(
          textBuffer, ctx.hasSelection, pos, ctx.cursorLine, ctx.cursorCol
        )
      renderChar(rune, charIdx, style)
      charIdx += 1
  else:
    # Byte-based rendering (for non-wrapped mode)
    var charIdx = 0
    for rune in displayLine.runes:
      let
        col = startColumn + charIdx
        pos = BufferPosition(line: lineIndex, column: col)
        style = e.getSelectionStyle(
          textBuffer, ctx.hasSelection, pos, ctx.cursorLine, ctx.cursorCol
        )
      renderChar(rune, col, style)
      charIdx += 1

  # Fill the rest of the line with cursor line highlight if on cursor line
  if e.state.display.showCursorLine and lineIndex == ctx.cursorLine:
    while screenX + displayX < buffer.area.width:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle())
      displayX += 1

proc fillCursorLineBackground(
    e: Editor, buffer: var Buffer, screenX, screenY: int, lineIndex, cursorLine: int
) =
  ## Fill the rest of the line with cursor line background if on cursor line
  if e.state.display.showCursorLine and lineIndex == cursorLine:
    var displayX = 0
    while screenX + displayX < buffer.area.width:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle())
      displayX += 1

proc renderCodeLensInline(
    e: Editor,
    buffer: var Buffer,
    screenX, screenY: int,
    lineIndex: int,
    lineDisplayWidth: int,
) =
  ## Render CodeLens text inline at the end of a line
  ## Shows CodeLens items after the line content with dimmed style
  if not e.state.display.showCodeLens or not e.state.lspCache.codeLensCache.isValid:
    return

  # Get CodeLens items for this line from cache (O(1) lookup)
  let items = e.state.lspCache.codeLensCache.itemsByLine.getOrDefault(lineIndex, @[])
  if items.len == 0:
    return

  var texts: seq[string] = @[]
  for item in items:
    if item.title.len > 0:
      texts.add(item.title)

  if texts.len == 0:
    return

  let codeLensText = texts.join(" | ")

  # Calculate position: after line content with some padding
  let padding = 2
  var displayX = lineDisplayWidth + padding

  # Add separator before CodeLens text
  let separator = "  "
  let displayText = separator & codeLensText

  # Render the CodeLens text
  for ch in displayText:
    if screenX + displayX >= buffer.area.width:
      break
    buffer.setString(screenX + displayX, screenY, $ch, codeLensStyle())
    displayX += 1

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

proc renderLineNumbers(
    e: Editor, buffer: var Buffer, textAreaWidth: int, sidebarWidth: int = 0
): int =
  ## Render line numbers and return max width of the line number text.

  # Guard against invalid text area width
  if textAreaWidth <= 0:
    return 0

  let
    lineLen = e.textBuffer.len
    maxLineNumWidth = len($lineLen) + LineNumberSpacer
    reservedLines = e.calculateReservedLines(isBottomWindow = true)
    lineNumX = buffer.area.x + sidebarWidth
  var
    screenY = 0
    lineIndex = e.viewport.topLine

  while screenY < buffer.area.height - reservedLines and lineIndex < lineLen:
    # Render line numbers with wrapping support
    let
      line = e.textBuffer.getLine(lineIndex)
      isCurrentLine = lineIndex == e.state.cursor.line
      # Apply currentNumber setting: highlight current line number only if enabled
      lineStyle =
        if isCurrentLine and e.state.display.showCurrentLineNumber:
          currentLineStyle()
        else:
          lineNumStyle()

    if e.state.display.lineWrap:
      let
        lineCharLen = line.charLen # Use character count, not byte count
        numWraps = calculateWrapCount(lineCharLen, textAreaWidth)
        lineNumStr = formatLineNumber(lineIndex, maxLineNumWidth)

      buffer.setString(lineNumX, buffer.area.y + screenY, lineNumStr, lineStyle)
      inc screenY

      for _ in 1 ..< numWraps:
        # Render empty space for wrapped parts (no line number)
        if screenY >= buffer.area.height - reservedLines:
          break
        let emptyLineNumStr = spaces(maxLineNumWidth)
        buffer.setString(
          lineNumX, buffer.area.y + screenY, emptyLineNumStr, lineNumStyle()
        )
        inc screenY
    else:
      # Normal single-line display
      let lineNumStr = formatLineNumber(lineIndex, maxLineNumWidth)
      buffer.setString(lineNumX, buffer.area.y + screenY, lineNumStr, lineStyle)
      inc screenY

    inc lineIndex

  while screenY < buffer.area.height - reservedLines:
    # Clear remaining line number area to prevent artifacts
    let emptyLineNumStr = spaces(maxLineNumWidth)
    buffer.setString(lineNumX, buffer.area.y + screenY, emptyLineNumStr, lineNumStyle())
    inc screenY

  return maxLineNumWidth

proc renderTextBuffer(e: Editor, buffer: var Buffer, area: Rect) =
  # Get visual selection range if active
  let (hasSelection, selStart, selEnd) = e.getVisualSelection()

  # Create render context
  let ctx = RenderContext(
    cursorLine: e.state.cursor.line,
    cursorCol: e.state.cursor.column,
    hasSelection: hasSelection,
    selStart: selStart,
    selEnd: selEnd,
  )

  var
    screenY = 0
    lineIndex = e.viewport.topLine

  while screenY < area.height and lineIndex < e.textBuffer.len:
    # Render file content with optional line wrapping
    let line = e.textBuffer.getLine(lineIndex)

    if e.state.display.lineWrap:
      # Line wrapping enabled - split long lines across multiple screen lines
      let
        maxWidth = area.width
        lineCharLen = line.charLen # Use character count, not byte count

      if lineCharLen == 0:
        # Empty line - fill with cursor line highlight if on cursor line
        e.fillCursorLineBackground(
          buffer, area.x, area.y + screenY, lineIndex, e.state.cursor.line
        )
        # Render CodeLens on empty lines
        e.renderCodeLensInline(buffer, area.x, area.y + screenY, lineIndex, 0)
        inc screenY
        inc lineIndex
        continue

      var startCharCol = 0 # Character position, not byte position
      var isFirstWrappedLine = true
        # Track if this is the first screen line for this logical line
      while startCharCol < lineCharLen and screenY < area.height:
        # Calculate how many characters fit in maxWidth display columns
        # This properly handles wide characters (CJK, etc.)
        let (charCount, _) = displayWidthSubstr(line, startCharCol, maxWidth)
        let
          endCharCol = startCharCol + charCount
          # Convert character positions to byte positions for slicing
          startBytePos = charToBytePos(line, startCharCol)
          endBytePos = charToBytePos(line, endCharCol)
          displayLine = line[startBytePos ..< endBytePos]

        if displayLine.len > 0:
          # Render with selection highlighting if in visual mode
          e.renderLineSegmentWithSelection(
            e.textBuffer,
            buffer,
            displayLine,
            area.x,
            area.y + screenY,
            lineIndex,
            startCharCol,
            ctx,
            useRunes = true,
          )

          # Render CodeLens only on the first wrapped line
          if isFirstWrappedLine:
            let lineDisplayWidth =
              displayWidthWithTabs(displayLine, e.state.display.tabStop)
            e.renderCodeLensInline(
              buffer, area.x, area.y + screenY, lineIndex, lineDisplayWidth
            )
            isFirstWrappedLine = false

        inc screenY
        startCharCol += charCount # Use actual character count, not maxWidth
    else:
      # No line wrapping - use horizontal scrolling
      # Use character-based slicing (not byte-based) for multibyte character support
      let displayLine =
        if e.viewport.leftColumn < line.charLen:
          line.runeSubStr(e.viewport.leftColumn)
        else:
          ""

      if displayLine.len > 0:
        # Render with selection highlighting if in visual mode
        e.renderLineSegmentWithSelection(
          e.textBuffer,
          buffer,
          displayLine,
          area.x,
          area.y + screenY,
          lineIndex,
          e.viewport.leftColumn,
          ctx,
          useRunes = false,
        )

        # Render CodeLens inline after line content
        let lineDisplayWidth =
          displayWidthWithTabs(displayLine, e.state.display.tabStop)
        e.renderCodeLensInline(
          buffer, area.x, area.y + screenY, lineIndex, lineDisplayWidth
        )
      else:
        # Empty line or scrolled past line end - fill with cursor line highlight if on cursor line
        e.fillCursorLineBackground(
          buffer, area.x, area.y + screenY, lineIndex, e.state.cursor.line
        )

        # Render CodeLens even on empty lines
        e.renderCodeLensInline(buffer, area.x, area.y + screenY, lineIndex, 0)

      inc screenY

    inc lineIndex

proc renderWindowLineWrapped(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    ctx: RenderContext,
    screenY: var int,
    lineIndex: var int,
    visibleHeight: int,
) =
  ## Render a single line with wrapping enabled
  let
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth()
    maxWidth = window.viewport.width - sidebarWidth - lineNumOffset
    lineCharLen = line.charLen
    isCurrentLine = (lineIndex == window.cursor.line)
    # Apply currentNumber setting: highlight current line number only if enabled
    lineStyle =
      if isCurrentLine and e.config.standard.currentNumber:
        currentLineStyle()
      else:
        lineNumStyle()
    lineNumScreenX = window.viewport.x + sidebarWidth

  if lineCharLen == 0:
    # Empty line - just render line number (if enabled)
    if lineNumOffset > 0:
      let lineNumStr = formatLineNumber(lineIndex, lineNumOffset)
      if lineNumScreenX + lineNumStr.len <= buffer.area.width:
        buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)
    # Fill with cursor line highlight if on cursor line
    let textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    e.fillCursorLineBackground(
      buffer, textScreenX, actualScreenY, lineIndex, window.cursor.line
    )
    inc screenY
    inc lineIndex
    return

  var
    startCharCol = 0
    wrapLineCount = 0

  while startCharCol < lineCharLen and screenY < visibleHeight:
    let
      endCharCol = min(startCharCol + maxWidth, lineCharLen)
      startBytePos = charToBytePos(line, startCharCol)
      endBytePos = charToBytePos(line, endCharCol)
      displayLine = line[startBytePos ..< endBytePos]
      textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
      currentActualScreenY = window.viewport.y + screenY

    # Render line number for first wrap, empty space for others (if enabled)
    if lineNumOffset > 0:
      if wrapLineCount == 0:
        let lineNumStr = formatLineNumber(lineIndex, lineNumOffset)
        if lineNumScreenX + lineNumStr.len <= buffer.area.width:
          buffer.setString(lineNumScreenX, currentActualScreenY, lineNumStr, lineStyle)
      else:
        if lineNumScreenX + lineNumOffset <= buffer.area.width:
          let emptyLineNumStr = spaces(lineNumOffset)
          buffer.setString(
            lineNumScreenX, currentActualScreenY, emptyLineNumStr, lineNumStyle()
          )

    if displayLine.len > 0 and textScreenX < buffer.area.width:
      let displayCharCount = endCharCol - startCharCol
      if displayCharCount > 0:
        # Render with selection highlighting if in visual mode
        e.renderLineSegmentWithSelection(
          window.buffer,
          buffer,
          displayLine,
          textScreenX,
          currentActualScreenY,
          lineIndex,
          startCharCol,
          ctx,
          useRunes = true,
        )

    inc screenY
    inc wrapLineCount
    startCharCol += maxWidth

    if screenY >= visibleHeight:
      break

  inc lineIndex

proc renderWindowLineNoWrap(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    ctx: RenderContext,
    screenY: int,
    lineIndex: int,
) =
  ## Render a single line without wrapping (horizontal scrolling)
  let
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth()
    isCurrentLine = (lineIndex == window.cursor.line)
    # Apply currentNumber setting: highlight current line number only if enabled
    lineStyle =
      if isCurrentLine and e.config.standard.currentNumber:
        currentLineStyle()
      else:
        lineNumStyle()
    lineNumScreenX = window.viewport.x + sidebarWidth

  # Render line number (if enabled)
  if lineNumOffset > 0:
    let lineNumStr = formatLineNumber(lineIndex, lineNumOffset)
    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)

  # Render text content
  # Use character-based slicing (not byte-based) for multibyte character support
  let
    displayLine =
      if window.viewport.leftColumn < line.charLen:
        line.runeSubStr(window.viewport.leftColumn)
      else:
        ""
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset

  if displayLine.len > 0 and textScreenX < buffer.area.width:
    let maxWidth = min(displayLine.len, window.viewport.width - lineNumOffset)
    if maxWidth > 0:
      # Render with selection highlighting if in visual mode
      e.renderLineSegmentWithSelection(
        window.buffer,
        buffer,
        displayLine[0 ..< maxWidth],
        textScreenX,
        actualScreenY,
        lineIndex,
        window.viewport.leftColumn,
        ctx,
        useRunes = false,
      )
  else:
    # Empty line or scrolled past line end - fill with cursor line highlight if on cursor line
    e.fillCursorLineBackground(
      buffer, textScreenX, actualScreenY, lineIndex, window.cursor.line
    )

proc renderWindowSidebar(
    buffer: var Buffer,
    window: EditorWindow,
    sidebar: Sidebar,
    screenY: int,
    sidebarOffset: int,
) =
  ## Render a single line of the sidebar
  let actualScreenY = window.viewport.y + screenY

  if screenY >= 0 and screenY < sidebar.buffer.len:
    for x in 0 ..< sidebar.width:
      let
        item = sidebar.buffer[screenY][x]
        screenX = window.viewport.x + sidebarOffset + x
      if screenX < buffer.area.width and actualScreenY < buffer.area.height:
        buffer.setString(screenX, actualScreenY, item.text, item.style)

proc renderFoldLine(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    screenY: int,
    fold: Fold,
) =
  ## Render a collapsed fold marker line (vim-style)
  let
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth()
    lineNumScreenX = window.viewport.x + sidebarWidth
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    foldText = window.buffer.formatFoldText(fold)

  # Render line number (if enabled)
  if lineNumOffset > 0:
    let lineNumStr = formatLineNumber(fold.startLine, lineNumOffset)
    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineNumStyle())

  # Render fold text
  if textScreenX < buffer.area.width:
    let maxWidth = buffer.area.width - textScreenX
    let displayText =
      if foldText.len > maxWidth:
        foldText[0 ..< maxWidth]
      else:
        foldText
    buffer.setString(textScreenX, actualScreenY, displayText, foldStyle())

proc renderWindow(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    isBottomWindow: bool,
    isActiveWindow: bool,
) =
  ## Render a single window with sidebar, line numbers and text content
  let
    lineCount = window.buffer.len
    reservedLines = e.calculateReservedLines(isBottomWindow)
    visibleHeight = window.viewport.height - reservedLines

  # Generate sidebar dynamically from buffer markers if enabled
  let maybeSidebar =
    if e.state.display.showSidebar:
      some(
        generateSidebarFromBuffer(window.buffer, window.viewport.topLine, visibleHeight)
      )
    else:
      none(Sidebar)

  # Get visual selection range if active
  let (hasSelection, selStart, selEnd) = e.getVisualSelection(window.active)

  # Create render context for this window
  let ctx = RenderContext(
    cursorLine: window.cursor.line,
    cursorCol: window.cursor.column,
    hasSelection: hasSelection,
    selStart: selStart,
    selEnd: selEnd,
  )

  var
    screenY = 0
    lineIndex = window.viewport.topLine

  while screenY < visibleHeight and lineIndex < lineCount:
    # Check if this line is inside a collapsed fold (but not the start line)
    if window.buffer.foldState.isLineInCollapsedFold(lineIndex):
      # Skip this line (it's hidden inside a fold)
      inc lineIndex
      continue

    # Check if this line is the start of a collapsed fold
    let foldOpt = window.buffer.foldState.getCollapsedFoldAt(lineIndex)
    if foldOpt.isSome and foldOpt.get.startLine == lineIndex:
      # Render the fold marker
      if maybeSidebar.isSome:
        renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, 0)
      e.renderFoldLine(buffer, window, lineNumOffset, screenY, foldOpt.get)
      # Skip to the line after the fold
      lineIndex = foldOpt.get.endLine + 1
      inc screenY
      continue

    # Normal line rendering
    # Render sidebar if enabled
    if maybeSidebar.isSome:
      renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, 0)

    if e.state.display.lineWrap:
      e.renderWindowLineWrapped(
        buffer, window, lineNumOffset, ctx, screenY, lineIndex, visibleHeight
      )
    else:
      e.renderWindowLineNoWrap(buffer, window, lineNumOffset, ctx, screenY, lineIndex)
      inc screenY
      inc lineIndex

proc renderWindowSeparator(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    nextWindow: EditorWindow,
    isBottomWindow: bool,
) =
  ## Draw separator between adjacent windows (vertical or horizontal)
  # Check if windows are side by side (vertical split) or top/bottom (horizontal split)
  if window.viewport.y == nextWindow.viewport.y:
    # Vertical split - draw vertical separator at window boundary
    let sepX = window.viewport.x + window.viewport.width
    if sepX < buffer.area.width:
      # Calculate separator height using helper
      let
        sepHeight = e.calculateReservedLines(isBottomWindow)
        actualSepHeight = window.viewport.height - sepHeight

      # Draw separator for the content height of this window
      for y in window.viewport.y ..< (window.viewport.y + actualSepHeight):
        if y < buffer.area.height:
          buffer.setString(sepX, y, "│", separatorStyle())
  elif not e.state.display.multiStatusLine:
    # Horizontal split - draw horizontal separator at window boundary
    # ONLY when using a single status line
    let sepY = window.viewport.y + window.viewport.height
    if sepY < buffer.area.height:
      # Draw separator for the width of this window
      for x in window.viewport.x ..< (window.viewport.x + window.viewport.width):
        if x < buffer.area.width:
          buffer.setString(x, sepY, "─", separatorStyle())

proc updateViewportSize(e: Editor, buffer: Buffer): bool =
  ## Update viewport size from buffer area and return true if resized
  let
    oldWidth = e.viewport.width
    oldHeight = e.viewport.height

  e.viewport.width = buffer.area.width
  e.viewport.height = buffer.area.height

  (oldWidth != e.viewport.width) or (oldHeight != e.viewport.height)

proc renderSplitView(e: Editor, buffer: var Buffer, wasResized: bool) =
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

    # Render window (LogViewer uses normal buffer rendering now)
    e.renderWindow(buffer, window, lineNumOffset, isBottomWindow, isActiveWindow)

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

proc renderSingleView(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render single buffer view (no split windows)
  # Sync viewport with motion controller (both directions)
  e.executer.motionController.viewportManager.viewport.width = e.viewport.width
  e.executer.motionController.viewportManager.viewport.height = e.viewport.height
  e.viewport = e.executer.motionController.viewportManager.viewport

  let
    reservedLines = e.calculateReservedLines(isBottomWindow = true)
    sidebarWidth = e.calculateSidebarWidth()
    lineNumOffset =
      calculateLineNumOffset(e.textBuffer, e.state.display.showLineNumbers)
    textAreaWidth =
      max(0, buffer.area.width - sidebarWidth - lineNumOffset - LineNumberPadding)
    textArea = Rect(
      x: buffer.area.x + sidebarWidth + lineNumOffset,
      y: buffer.area.y,
      width: max(0, buffer.area.width - sidebarWidth - lineNumOffset),
      height: max(0, buffer.area.height - reservedLines),
    )

  # Generate sidebar dynamically from buffer markers if enabled
  let maybeSidebar =
    if e.state.display.showSidebar:
      some(
        generateSidebarFromBuffer(
          e.textBuffer, e.viewport.topLine, buffer.area.height - reservedLines
        )
      )
    else:
      none(Sidebar)

  # If terminal was resized, adjust viewport to keep cursor visible
  if wasResized:
    let visibleHeight = max(1, e.viewport.height - reservedLines)

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
    var screenY = 0
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
    discard e.renderLineNumbers(buffer, textAreaWidth, sidebarWidth)
  e.renderTextBuffer(buffer, textArea)

  # Calculate and set cursor position (including sidebar width)
  e.state.screenCursor = e.calculateWindowCursor(
    e.textBuffer,
    e.viewport,
    e.state.cursor,
    sidebarWidth + lineNumOffset,
    reservedLines,
  )

proc renderBottomLines(e: Editor, buffer: var Buffer) =
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

proc renderTempMessages(e: Editor, buffer: var Buffer) =
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

proc pathToIcon(entry: FileEntry): string =
  ## Get an emoji icon for a file entry based on its type and extension
  if entry.kind == fekDirectory or entry.targetKind == fekDirectory:
    return "📁 "

  if entry.isExecutable:
    return "🏃 "

  let filename = entry.name
  # Check for Dockerfile
  if filename == "Dockerfile" or filename.startsWith("Dockerfile."):
    return "🐳 "

  # Get extension
  let dotPos = filename.rfind('.')
  if dotPos < 0:
    return "📄 "

  let ext = filename[dotPos + 1 .. ^1].toLower()
  case ext
  of "nim": "👑 "
  of "nimble", "rpm", "deb": "📦 "
  of "py": "🐍 "
  of "ui", "glade": "🏠 "
  of "txt", "md", "rst": "📝 "
  of "cpp", "cxx", "hpp", "cc": "⧺ "
  of "c", "h": "🅒 "
  of "java": "🍵 "
  of "php": "🙈 "
  of "js", "json", "mjs", "cjs": "🙉 "
  of "ts", "tsx": "📘 "
  of "rs": "🦀 "
  of "go": "🐹 "
  of "html", "xhtml", "htm": "🏄 "
  of "css", "scss", "sass": "👚 "
  of "xml": "༕ "
  of "cfg", "ini", "conf": "🍳 "
  of "sh", "bash", "zsh", "fish": "🐚 "
  of "pdf", "doc", "docx", "odf", "ods", "odt": "🍞 "
  of "wav", "mp3", "ogg", "flac", "m4a": "🎼 "
  of "zip", "bz2", "xz", "gz", "tgz", "zst", "tar", "7z", "rar": "🚢 "
  of "exe", "bin", "elf": "🏃 "
  of "mp4", "webm", "avi", "mpeg", "mkv", "mov": "🎞 "
  of "patch", "diff": "💊 "
  of "lock": "🔒 "
  of "pem", "crt", "key": "🔏 "
  of "png", "jpeg", "jpg", "bmp", "gif", "svg", "webp", "ico": "🎨 "
  of "toml", "yaml", "yml": "⚙ "
  of "nix": "❄ "
  of "hs", "lhs": "λ "
  of "lua": "🌙 "
  of "rb": "💎 "
  of "pl", "pm": "🐪 "
  of "sql": "🗃 "
  of "vim": "📗 "
  of "el", "lisp", "scm": "λ "
  else: "📄 "

proc renderFiler(e: Editor, buffer: var Buffer) =
  ## Render the file explorer view
  if e.state.filerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    filerState = e.state.filerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header (current path)
  let headerText =
    if filerState.currentPath.len > width - 2:
      "..." & filerState.currentPath[^(width - 5) .. ^1]
    else:
      filerState.currentPath
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected entry is visible (pass total reserved: 1 header + reservedBottom)
  filerState.ensureSelectedVisible(buffer.area.height, 1 + reservedBottom)

  # Render file entries
  var screenY = listStartY
  for i in filerState.topLine ..< filerState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = filerState.entries[i]
      isSelected = i == filerState.selectedIndex

    # Build display line
    var displayLine: string

    let icon =
      if e.config.filer.showIcons:
        pathToIcon(entry)
      else:
        case entry.kind
        of fekDirectory: "▸ "
        of fekSymlink: "@ "
        of fekFile: "  "

    let name =
      if entry.isDirectory:
        entry.name & "/"
      else:
        entry.name

    displayLine = " " & icon & name

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Pad to full width for selected line (so background color fills entire line)
    if isSelected and displayLine.len < width:
      displayLine = displayLine & " ".repeat(width - displayLine.len)

    # Apply style (use theme background color to match clearBuffer)
    let themeBg = normalStyle().bg
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif entry.kind == fekDirectory:
        Style(fg: rgb(0x5f, 0x87, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif entry.kind == fekSymlink:
        # Symlinks: cyan for files, magenta for directories
        if entry.targetKind == fekDirectory:
          Style(fg: rgb(0xaf, 0x5f, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
        else:
          Style(fg: rgb(0x00, 0xff, 0xff), bg: themeBg, modifiers: {})
      elif entry.isHidden:
        Style(fg: rgb(0x80, 0x80, 0x80), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in filer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (filerState.selectedIndex - filerState.topLine)

proc renderBufferManager(e: Editor, buffer: var Buffer) =
  ## Render the buffer manager view
  if e.state.bufferManagerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    bmState = e.state.bufferManagerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- Buffer Manager --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  if bmState.selectedIndex >= bmState.topLine + visibleLines:
    bmState.topLine = bmState.selectedIndex - visibleLines + 1
  if bmState.selectedIndex < bmState.topLine:
    bmState.topLine = bmState.selectedIndex

  # Render buffer entries
  var screenY = listStartY
  for i in bmState.topLine ..< bmState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = bmState.entries[i]
      isSelected = i == bmState.selectedIndex

    # Build display line
    var displayLine: string
    let prefix = if isSelected: "> " else: "  "
    let activeMark = if entry.active: "* " else: "  "
    let modifiedMark = if entry.modified: "[+] " else: "    "
    let indexStr = $entry.index & ": "

    displayLine = prefix & activeMark & indexStr & modifiedMark & entry.name

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Pad to full width for selected line (so background color fills entire line)
    if isSelected and displayLine.len < width:
      displayLine = displayLine & " ".repeat(width - displayLine.len)

    # Apply style (use theme background color to match clearBuffer)
    let themeBg = normalStyle().bg
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif entry.active:
        Style(fg: rgb(0x5f, 0xff, 0x5f), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif entry.modified:
        Style(fg: rgb(0xff, 0x87, 0x00), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in buffer manager mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (bmState.selectedIndex - bmState.topLine)

proc renderConfigMode(e: Editor, buffer: var Buffer) =
  ## Render the configuration mode view
  if e.state.configModeState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    configState = e.state.configModeState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  var headerText = "-- Configuration --"
  if headerText.len < width:
    headerText = headerText & ' '.repeat(width - headerText.len)
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Calculate max name width for alignment
  var maxNameWidth = 0
  for item in configState.items:
    if item.kind != cvkSection:
      maxNameWidth = max(maxNameWidth, item.displayName.len + item.depth * 2)
  maxNameWidth = min(maxNameWidth + 4, width div 2) # Limit to half of width

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  configState.ensureSelectedVisible(visibleLines)

  # Render config entries
  var screenY = listStartY
  let isEditMode = configState.isEditing()
  let editInfo = configState.getEditInfo()
  let themeBg = normalStyle().bg

  for i in configState.topLine ..< configState.items.len:
    if screenY >= listEndY:
      break

    let
      item = configState.items[i]
      isSelected = i == configState.selectedIndex
      isBeingEdited = isSelected and isEditMode and item.kind in {cvkInt, cvkString}

    # Build display line
    var displayLine: string
    if isBeingEdited:
      # Show edit buffer
      let indent = "  ".repeat(item.depth)
      let name = item.displayName.alignLeft(maxNameWidth - item.depth * 2)
      displayLine = indent & name & " : " & editInfo.buffer
    else:
      displayLine = formatItemForDisplay(item, maxNameWidth)

    # Truncate if too long, or pad to full width for consistent background
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."
    elif displayLine.len < width:
      displayLine = displayLine & ' '.repeat(width - displayLine.len)

    # Apply style (use theme background color to match clearBuffer)
    let style =
      if isBeingEdited:
        # Edit mode style - yellow background
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xd7, 0x00), modifiers: {})
      elif isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif item.kind == cvkSection:
        Style(fg: rgb(0x5f, 0xff, 0x5f), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif item.kind == cvkBool:
        if item.boolValue:
          Style(fg: rgb(0x5f, 0xaf, 0x5f), bg: themeBg, modifiers: {})
        else:
          Style(fg: rgb(0xaf, 0x5f, 0x5f), bg: themeBg, modifiers: {})
      elif item.kind == cvkEnum:
        Style(fg: rgb(0x87, 0xaf, 0xd7), bg: themeBg, modifiers: {})
      elif item.kind == cvkInt:
        Style(fg: rgb(0xd7, 0xaf, 0x5f), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Clear remaining lines (when sections are collapsed)
  let emptyLine = ' '.repeat(width)
  while screenY < listEndY:
    buffer.setString(buffer.area.x, screenY, emptyLine, normalStyle())
    inc screenY

  # Render enum popup if open
  let isEnumPopupOpen = configState.isEnumPopupOpen()
  if isEnumPopupOpen:
    let enumInfo = configState.getEnumPopupInfo()
    if enumInfo.options.len > 0:
      # Calculate popup dimensions
      var popupWidth = 0
      for opt in enumInfo.options:
        popupWidth = max(popupWidth, opt.len)
      popupWidth += 4 # padding and border
      let popupHeight = enumInfo.options.len + 2 # options + border

      # Calculate popup position (near the value display position)
      let selectedY = listStartY + (configState.selectedIndex - configState.topLine)
      let selectedItem = configState.getSelectedItem()
      var valueX = maxNameWidth + 5 # indent + name + " : "
      if selectedItem.isSome:
        valueX =
          selectedItem.get.depth * 2 + maxNameWidth - selectedItem.get.depth * 2 + 3

      var popupX = valueX
      var popupY = selectedY + 1
      # Adjust if popup goes off screen
      if popupX + popupWidth > width:
        popupX = max(0, width - popupWidth)
      if popupY + popupHeight > listEndY:
        popupY = max(listStartY, selectedY - popupHeight)
      if popupX < 0:
        popupX = 0

      let
        popupBg = rgb(0x30, 0x30, 0x30)
        popupFg = rgb(0xff, 0xff, 0xff)
        selectedBg = rgb(0x00, 0x5f, 0xaf)
        borderStyle = Style(fg: popupFg, bg: popupBg, modifiers: {})
        normalStyle = Style(fg: popupFg, bg: popupBg, modifiers: {})
        selectedStyle =
          Style(fg: popupFg, bg: selectedBg, modifiers: {StyleModifier.Bold})

      # Draw top border
      let topBorder = "┌" & "─".repeat(popupWidth - 2) & "┐"
      buffer.setString(buffer.area.x + popupX, popupY, topBorder, borderStyle)

      # Draw options
      for i, opt in enumInfo.options:
        let
          y = popupY + 1 + i
          isSelected = i == enumInfo.selectedIndex
          style = if isSelected: selectedStyle else: normalStyle
          line = "│ " & opt.alignLeft(popupWidth - 4) & " │"
        buffer.setString(buffer.area.x + popupX, y, line, style)

      # Draw bottom border
      let bottomBorder = "└" & "─".repeat(popupWidth - 2) & "┘"
      buffer.setString(
        buffer.area.x + popupX, popupY + popupHeight - 1, bottomBorder, borderStyle
      )

  # Set cursor position - only visible in edit mode
  if isEditMode:
    # Position cursor within the edit buffer
    let selectedItem = configState.getSelectedItem()
    if selectedItem.isSome:
      let item = selectedItem.get
      let indent = item.depth * 2
      let nameWidth = maxNameWidth - item.depth * 2
      # cursor x = indent + name + " : " + edit cursor position
      e.state.screenCursor.x = indent + nameWidth + 3 + editInfo.cursor
      e.state.screenCursor.y =
        listStartY + (configState.selectedIndex - configState.topLine)
  else:
    # Hide cursor by moving it off-screen
    e.state.screenCursor.x = -1
    e.state.screenCursor.y = -1

proc renderBackupManager(e: Editor, buffer: var Buffer) =
  ## Render the backup manager view
  if e.state.backupManagerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    bkState = e.state.backupManagerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- Backup Manager: " & bkState.sourceFilePath & " --"
  buffer.setString(
    buffer.area.x,
    headerY,
    if headerText.len > width:
      headerText[0 ..< width]
    else:
      headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Handle empty list
  if bkState.entries.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No backup files found",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: normalStyle().bg, modifiers: {}),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  if bkState.selectedIndex >= bkState.topLine + visibleLines:
    bkState.topLine = bkState.selectedIndex - visibleLines + 1
  if bkState.selectedIndex < bkState.topLine:
    bkState.topLine = bkState.selectedIndex

  # Render backup entries
  var screenY = listStartY
  for i in bkState.topLine ..< bkState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = bkState.entries[i]
      isSelected = i == bkState.selectedIndex

    # Build display line with formatted timestamp
    let prefix = if isSelected: "> " else: "  "
    let displayLine = prefix & formatEntry(entry)

    # Apply style (use theme background color to match clearBuffer)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (bkState.selectedIndex - bkState.topLine)

proc renderDiffViewer(e: Editor, buffer: var Buffer) =
  ## Render the diff viewer view
  if e.state.diffViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    dvState = e.state.diffViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText =
    "-- Diff: " & extractFilename(dvState.sourceFilePath) & " vs backup --"
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    if headerText.len > width:
      headerText[0 ..< width]
    else:
      headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
  )

  # Handle empty diff
  if dvState.lines.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No diff content",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: themeBg, modifiers: {}),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Ensure selected line is visible
  let visibleLines = listEndY - listStartY
  if dvState.selectedLine >= dvState.topLine + visibleLines:
    dvState.topLine = dvState.selectedLine - visibleLines + 1
  if dvState.selectedLine < dvState.topLine:
    dvState.topLine = dvState.selectedLine

  # Render diff lines
  var screenY = listStartY
  for i in dvState.topLine ..< dvState.lines.len:
    if screenY >= listEndY:
      break

    let
      line = dvState.lines[i]
      isSelected = i == dvState.selectedLine

    # Truncate line if too long
    let displayText =
      if line.text.len > width:
        line.text[0 ..< width]
      else:
        line.text

    # Apply style based on diff line kind and selection (use theme background)
    let style =
      if isSelected:
        # Highlighted/selected line
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        case line.kind
        of dlkAdded:
          # Added lines in green
          Style(fg: rgb(0x00, 0xd7, 0x00), bg: themeBg, modifiers: {})
        of dlkDeleted:
          # Deleted lines in red
          Style(fg: rgb(0xff, 0x5f, 0x5f), bg: themeBg, modifiers: {})
        of dlkHeader:
          # Header lines (@@, ---, +++) in cyan/bold
          Style(fg: rgb(0x00, 0xd7, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
        of dlkMeta:
          # Meta lines (diff --git, index) in yellow
          Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {})
        of dlkNormal:
          # Normal context lines
          normalStyle()

    buffer.setString(buffer.area.x, screenY, displayText, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (dvState.selectedLine - dvState.topLine)

proc renderRecentFileMode(e: Editor, buffer: var Buffer) =
  ## Render the recent file selection view
  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    state = e.recentFileModeState
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width
    viewportHeight = listEndY - listStartY

  # Render header
  let headerText = "-- Recent Files --"
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
  )

  # Handle empty list
  if state.files.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No recent files found",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: themeBg, modifiers: {}),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Adjust viewport to keep selected visible
  state.adjustViewport(viewportHeight)

  # Render file entries
  let visibleFiles = state.getVisibleFiles(viewportHeight)
  var screenY = listStartY
  for i, entry in visibleFiles:
    if screenY >= listEndY:
      break

    let
      actualIndex = state.topLine + i
      isSelected = actualIndex == state.selectedIndex

    # Build display line
    let prefix = if isSelected: "> " else: "  "
    var displayLine = prefix & entry.path

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Apply style - check if file exists (use theme background)
    let exists = fileExists(entry.path)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif not exists:
        # Non-existent files in dim gray
        Style(fg: rgb(0x60, 0x60, 0x60), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (state.selectedIndex - state.topLine)

proc renderDebugMode(e: Editor, buffer: var Buffer) =
  ## Render the debug viewer
  if e.state.debugViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    debugState = e.state.debugViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width
    viewportHeight = listEndY - listStartY

  # Get theme colors
  let
    defaultStyle = getThemeStyle(EditorColorPairIndex.default)
    defaultBg = defaultStyle.bg

  # Fill entire area with default background first
  let emptyLine = spaces(width)
  for y in buffer.area.y ..< listEndY:
    buffer.setString(buffer.area.x, y, emptyLine, defaultStyle)

  # Render header
  let headerText = "-- DEBUG --"
  let headerStyle =
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: defaultBg, modifiers: {StyleModifier.Bold})
  buffer.setString(buffer.area.x, headerY, headerText, headerStyle)

  # Handle empty list
  if debugState.lines.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No debug information available",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: defaultBg, modifiers: {}),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Render debug lines
  var screenY = listStartY
  for i in debugState.topLine ..<
      min(debugState.lines.len, debugState.topLine + viewportHeight):
    if screenY >= listEndY:
      break

    let
      line = debugState.lines[i]
      isSelected = i == debugState.selectedLine

    # Truncate if too long
    var displayLine = line
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Apply style based on content
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif line.startsWith("--"):
        # Section headers
        Style(fg: rgb(0x87, 0xaf, 0xff), bg: defaultBg, modifiers: {StyleModifier.Bold})
      else:
        defaultStyle

    # Pad line to fill width for consistent background
    let paddedLine = displayLine & spaces(max(0, width - displayLine.len))
    buffer.setString(buffer.area.x, screenY, paddedLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (debugState.selectedLine - debugState.topLine)

proc renderReferencesViewer(e: Editor, buffer: var Buffer) =
  ## Render the references viewer view
  if e.state.referencesViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    refState = e.state.referencesViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header with title
  let headerText =
    "-- " & refState.title.toUpperAscii() & " (" & $refState.itemCount() & ") --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0x00, 0xaf, 0xff), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected line is visible
  refState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render reference lines
  var screenY = listStartY
  for i in refState.topLine ..< refState.itemCount:
    if screenY >= listEndY:
      break

    let
      line = refState.getLine(i)
      isSelected = i == refState.selectedIndex

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in references viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (refState.selectedIndex - refState.topLine)

proc renderDocumentSymbolViewer(e: Editor, buffer: var Buffer) =
  ## Render the document symbol viewer view
  if e.state.documentSymbolViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    symState = e.state.documentSymbolViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header with title
  let headerText = "-- SYMBOLS (" & $symState.itemCount() & ") --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xaf, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected line is visible
  symState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render symbol lines
  var screenY = listStartY
  for i in symState.topLine ..< symState.itemCount:
    if screenY >= listEndY:
      break

    let
      line = symState.getLine(i)
      isSelected = i == symState.selectedIndex

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in document symbol viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (symState.selectedIndex - symState.topLine)

proc renderHelpViewer(e: Editor, buffer: var Buffer) =
  ## Render the help viewer view
  if e.state.helpViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    helpState = e.state.helpViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- HELP --"
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
  )

  # Ensure selected line is visible
  helpState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render help lines
  var screenY = listStartY
  for i in helpState.topLine ..< helpState.lineCount:
    if screenY >= listEndY:
      break

    let
      line = helpState.getLine(i)
      isSelected = i == helpState.selectedIndex
      isHeader = line.len > 0 and line[0] == '#'

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif isHeader:
        Style(fg: rgb(0x5f, 0xaf, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in help viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (helpState.selectedIndex - helpState.topLine)

proc maybeUpdateLsp*(e: Editor) =
  ## Update LSP if buffer was modified
  ## This notifies the LSP server of document changes for real-time diagnostics
  if not e.lsp.enabled:
    return

  let activeBuffer = e.activeBuffer()

  # Only notify LSP if buffer has changed since last notification
  if activeBuffer.changeSeq != e.lastLspChangeSeq:
    let lspResult = e.lsp.onBufferChange(activeBuffer)
    if lspResult.isOk:
      e.lastLspChangeSeq = activeBuffer.changeSeq

proc requestSignatureHelpFromLsp*(e: Editor) =
  ## Request signature help from LSP if in insert mode with paren depth > 0
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled:
    return

  if e.state.mode != EditorMode.Insert:
    return

  let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
  if sigHelpMgr.parenDepth == 0 and not sigHelpMgr.isActive():
    return

  let activeBuffer = e.activeBuffer()

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingSignatureHelpRequestId != 0:
    let (status, resultOpt, _) =
      e.lsp.checkResponse(e.state.lspCache.pendingSignatureHelpRequestId)
    case status
    of lrsPending:
      # Still waiting for response, continue
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingSignatureHelpRequestId = 0
      if resultOpt.isSome:
        let sigHelpOpt = parseSignatureHelpResponse(resultOpt.get)
        if sigHelpOpt.isSome:
          sigHelpMgr.show(sigHelpOpt.get, e.state.cursor.line, e.state.cursor.column)
        else:
          if sigHelpMgr.parenDepth == 0:
            sigHelpMgr.hide()
    of lrsError, lrsTimeout:
      # Request failed or timed out, clear and try again next time
      e.state.lspCache.pendingSignatureHelpRequestId = 0
      return

  # Start a new request
  let reqResult = e.lsp.startSignatureHelpRequest(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )
  if reqResult.isOk:
    e.state.lspCache.pendingSignatureHelpRequestId = reqResult.get

proc pollLspCompletion*(e: Editor) =
  ## Poll for pending LSP completion responses
  ## This should be called from the main event loop
  if not e.lsp.enabled:
    return

  if e.state.mode != EditorMode.Insert:
    return

  # Call the insert handler's poll function
  e.handlerManager.insertHandler.pollLspCompletion()

proc addToJumpList(e: Editor) =
  ## Add current cursor position to jump list before a jump
  let jumpPos = JumpPosition(line: e.state.cursor.line, column: e.state.cursor.column)

  # Don't add if same as last position
  if e.state.jumpList.len > 0:
    let lastPos = e.state.jumpList[^1]
    if lastPos.line == jumpPos.line and lastPos.column == jumpPos.column:
      return

  e.state.jumpList.add(jumpPos)
  # Keep jump list at reasonable size (max 100 entries)
  if e.state.jumpList.len > 100:
    e.state.jumpList.delete(0)
  # Reset jump list index when adding new position
  e.state.jumpListIndex = -1

proc jumpToLspLocation(e: Editor, loc: lspTypes.Location, resultKind: string): bool =
  ## Jump to a single LSP location
  ## Returns true if successful
  let activeBuffer = e.activeBuffer()
  let path = lspservice.uriToPath(loc.uri)

  # Add current position to jump list before jumping
  e.addToJumpList()

  # Check if it's the same file
  if activeBuffer.filePath.isSome and activeBuffer.filePath.get == path:
    # Same file - just move cursor with boundary checks
    let targetLine = min(loc.range.start.line, max(0, activeBuffer.len - 1))
    let lineLen =
      if activeBuffer.len > 0:
        activeBuffer[targetLine].len
      else:
        0
    let targetCol = min(loc.range.start.character, max(0, lineLen - 1))
    e.state.cursor.line = targetLine
    e.state.cursor.column = max(0, targetCol)
    e.state.statusMessage = resultKind & " at line " & $(targetLine + 1)
  else:
    # Different file - open it
    let loadResult = e.loadFile(path)
    if loadResult.isErr:
      e.state.statusMessage = "Failed to open file: " & loadResult.error
      return false
    # Set cursor with boundary checks (loadFile already loaded into e.textBuffer)
    let targetLine = min(loc.range.start.line, max(0, e.textBuffer.len - 1))
    let lineLen =
      if e.textBuffer.len > 0:
        e.textBuffer[targetLine].len
      else:
        0
    let targetCol = min(loc.range.start.character, max(0, lineLen - 1))
    e.state.cursor.line = targetLine
    e.state.cursor.column = max(0, targetCol)
    e.state.statusMessage = resultKind & " in " & path

  # Update viewport to follow cursor
  e.state.needsFullRedraw = true
  return true

proc handleLspLocations(
    e: Editor, locations: seq[lspTypes.Location], title: string, singularName: string
): bool =
  ## Handle LSP location results (shared by definition and references)
  ## Returns true if successful
  if locations.len == 0:
    e.state.statusMessage = "No " & title.toLowerAscii() & " found"
    return false

  if locations.len == 1:
    # Single location - jump directly
    return e.jumpToLspLocation(locations[0], singularName)
  else:
    # Multiple locations - open References viewer mode
    var items: seq[ReferenceItem] = @[]
    for loc in locations:
      let path = lspservice.uriToPath(loc.uri)
      items.add(
        ReferenceItem(
          path: path,
          line: loc.range.start.line,
          column: loc.range.start.character,
          text: "",
        )
      )

    # Enter References mode
    e.state.previousMode = e.state.mode
    e.state.mode = EditorMode.References
    e.state.referencesViewerState = some(newReferencesViewerState(items, title))
    e.state.statusMessage = $locations.len & " " & title.toLowerAscii() & " found"
    return true

proc openFileAndJumpTo*(e: Editor, path: string, line, column: int): bool =
  ## Open a file and jump to a specific location
  ## Returns true if successful
  let activeBuffer = e.activeBuffer()

  # Add current position to jump list before jumping
  e.addToJumpList()

  # Check if it's the same file
  if activeBuffer.filePath.isSome and activeBuffer.filePath.get == path:
    # Same file - just move cursor with boundary checks
    let targetLine = min(line, max(0, activeBuffer.len - 1))
    let lineLen =
      if activeBuffer.len > 0:
        activeBuffer[targetLine].len
      else:
        0
    let targetCol = min(column, max(0, lineLen - 1))
    e.state.cursor.line = targetLine
    e.state.cursor.column = max(0, targetCol)
  else:
    # Different file - open it
    let loadResult = e.loadFile(path)
    if loadResult.isErr:
      e.state.statusMessage = "Failed to open file: " & loadResult.error
      return false
    # Set cursor with boundary checks (loadFile already loaded into e.textBuffer)
    let targetLine = min(line, max(0, e.textBuffer.len - 1))
    let lineLen =
      if e.textBuffer.len > 0:
        e.textBuffer[targetLine].len
      else:
        0
    let targetCol = min(column, max(0, lineLen - 1))
    e.state.cursor.line = targetLine
    e.state.cursor.column = max(0, targetCol)

  # Update viewport to follow cursor
  e.state.needsFullRedraw = true
  return true

proc startLspLocationRequest(e: Editor, kind: LspLocationRequestKind): bool =
  ## Start an async LSP location request (definition, declaration, references, etc.)
  ## Returns true if request was started successfully
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending location request
  e.state.lspCache.pendingLocationRequestId = 0
  e.state.lspCache.pendingLocationRequestKind = lrkNone

  let activeBuffer = e.activeBuffer()
  let line = e.state.cursor.line
  let col = e.state.cursor.column

  let reqResult =
    case kind
    of lrkDefinition:
      e.lsp.startDefinitionRequest(activeBuffer, line, col)
    of lrkDeclaration:
      e.lsp.startDeclarationRequest(activeBuffer, line, col)
    of lrkReferences:
      e.lsp.startReferencesRequest(activeBuffer, line, col)
    of lrkTypeDefinition:
      e.lsp.startTypeDefinitionRequest(activeBuffer, line, col)
    of lrkImplementation:
      e.lsp.startImplementationRequest(activeBuffer, line, col)
    of lrkNone:
      return false

  if reqResult.isErr:
    let kindName =
      case kind
      of lrkDefinition: "definition"
      of lrkDeclaration: "declaration"
      of lrkReferences: "references"
      of lrkTypeDefinition: "type definition"
      of lrkImplementation: "implementation"
      of lrkNone: ""
    e.state.statusMessage = "LSP " & kindName & " failed: " & reqResult.error
    return false

  e.state.lspCache.pendingLocationRequestId = reqResult.get
  e.state.lspCache.pendingLocationRequestKind = kind
  return true

proc pollLspLocationRequest*(e: Editor) =
  ## Poll for pending LSP location request response
  ## This should be called from the main event loop (tick function)
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingLocationRequestId
  if requestId == 0:
    return

  let kind = e.state.lspCache.pendingLocationRequestKind
  if kind == lrkNone:
    return

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingLocationRequestId = 0
    e.state.lspCache.pendingLocationRequestKind = lrkNone
    if resultOpt.isSome:
      let locations = parseLocationsResponse(resultOpt.get)
      let (pluralName, singularName) =
        case kind
        of lrkDefinition:
          ("Definitions", "Definition")
        of lrkDeclaration:
          ("Declarations", "Declaration")
        of lrkReferences:
          ("References", "Reference")
        of lrkTypeDefinition:
          ("Type Definitions", "Type Definition")
        of lrkImplementation:
          ("Implementations", "Implementation")
        of lrkNone:
          ("", "")
      discard e.handleLspLocations(locations, pluralName, singularName)
    else:
      e.state.statusMessage = "No results found"
  of lrsError:
    e.state.lspCache.pendingLocationRequestId = 0
    e.state.lspCache.pendingLocationRequestKind = lrkNone
    if errorOpt.isSome:
      e.state.statusMessage = "LSP request failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingLocationRequestId = 0
    e.state.lspCache.pendingLocationRequestKind = lrkNone
    e.state.statusMessage = "LSP request timed out"

proc requestLspGotoDefinition*(e: Editor): bool =
  ## Request LSP goto definition at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkDefinition)

proc requestLspGotoDeclaration*(e: Editor): bool =
  ## Request LSP goto declaration at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkDeclaration)

proc requestLspReferences*(e: Editor): bool =
  ## Request LSP find references at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkReferences)

proc startCallHierarchyRequest(e: Editor, kind: CallHierarchyRequestKind): bool =
  ## Start an async call hierarchy request (2-stage: prepare -> incoming/outgoing)
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()

  if not e.lsp.hasCallHierarchySupport(activeBuffer):
    e.state.statusMessage = "Call hierarchy not supported"
    return false

  # Cancel any pending call hierarchy request
  e.state.lspCache.pendingCallHierarchyRequestId = 0
  e.state.lspCache.pendingCallHierarchyKind = chrkNone
  e.state.lspCache.pendingCallHierarchyPrepareResult = none(JsonNode)

  # Start with prepare request
  let reqResult = e.lsp.startCallHierarchyPrepareRequest(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )

  if reqResult.isErr:
    e.state.statusMessage = "LSP call hierarchy failed: " & reqResult.error
    return false

  e.state.lspCache.pendingCallHierarchyRequestId = reqResult.get
  e.state.lspCache.pendingCallHierarchyKind = kind
  return true

proc pollLspCallHierarchy*(e: Editor) =
  ## Poll for pending call hierarchy request response
  ## Handles 2-stage request: prepare -> incoming/outgoing
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingCallHierarchyRequestId
  if requestId == 0:
    return

  let kind = e.state.lspCache.pendingCallHierarchyKind
  if kind == chrkNone:
    return

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    let activeBuffer = e.activeBuffer()

    case kind
    of chrkPrepareIncoming, chrkPrepareOutgoing:
      # First stage complete - parse prepare result and start second stage
      if resultOpt.isSome:
        let prepareItems = parseCallHierarchyPrepareResponse(resultOpt.get)
        if prepareItems.len == 0:
          e.state.lspCache.pendingCallHierarchyRequestId = 0
          e.state.lspCache.pendingCallHierarchyKind = chrkNone
          e.state.statusMessage = "No callable symbol at cursor"
          return

        # Start second stage request
        let item = prepareItems[0]
        let secondReqResult =
          if kind == chrkPrepareIncoming:
            e.lsp.startCallHierarchyIncomingCallsRequest(activeBuffer, item)
          else:
            e.lsp.startCallHierarchyOutgoingCallsRequest(activeBuffer, item)

        if secondReqResult.isErr:
          e.state.lspCache.pendingCallHierarchyRequestId = 0
          e.state.lspCache.pendingCallHierarchyKind = chrkNone
          e.state.statusMessage = "LSP call hierarchy failed: " & secondReqResult.error
          return

        e.state.lspCache.pendingCallHierarchyRequestId = secondReqResult.get
        e.state.lspCache.pendingCallHierarchyKind =
          if kind == chrkPrepareIncoming: chrkIncomingCalls else: chrkOutgoingCalls
      else:
        e.state.lspCache.pendingCallHierarchyRequestId = 0
        e.state.lspCache.pendingCallHierarchyKind = chrkNone
        e.state.statusMessage = "No callable symbol at cursor"
    of chrkIncomingCalls:
      # Second stage complete - show incoming calls
      e.state.lspCache.pendingCallHierarchyRequestId = 0
      e.state.lspCache.pendingCallHierarchyKind = chrkNone

      if resultOpt.isSome:
        let calls = parseCallHierarchyIncomingCallsResponse(resultOpt.get)
        if calls.len == 0:
          e.state.statusMessage = "No incoming calls found"
          return

        var locations: seq[lspTypes.Location] = @[]
        for call in calls:
          locations.add(
            lspTypes.Location(uri: call.`from`.uri, range: call.`from`.selectionRange)
          )
        discard e.handleLspLocations(locations, "Incoming Calls", "Caller")
      else:
        e.state.statusMessage = "No incoming calls found"
    of chrkOutgoingCalls:
      # Second stage complete - show outgoing calls
      e.state.lspCache.pendingCallHierarchyRequestId = 0
      e.state.lspCache.pendingCallHierarchyKind = chrkNone

      if resultOpt.isSome:
        let calls = parseCallHierarchyOutgoingCallsResponse(resultOpt.get)
        if calls.len == 0:
          e.state.statusMessage = "No outgoing calls found"
          return

        var locations: seq[lspTypes.Location] = @[]
        for call in calls:
          locations.add(
            lspTypes.Location(uri: call.to.uri, range: call.to.selectionRange)
          )
        discard e.handleLspLocations(locations, "Outgoing Calls", "Callee")
      else:
        e.state.statusMessage = "No outgoing calls found"
    of chrkNone:
      discard
  of lrsError:
    e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone
    if errorOpt.isSome:
      e.state.statusMessage = "LSP call hierarchy failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone
    e.state.statusMessage = "LSP call hierarchy timed out"

proc requestLspCallHierarchyIncoming*(e: Editor): bool =
  ## Request LSP incoming calls at current cursor position (async)
  ## Returns true if request was started
  e.startCallHierarchyRequest(chrkPrepareIncoming)

proc requestLspCallHierarchyOutgoing*(e: Editor): bool =
  ## Request LSP outgoing calls at current cursor position (async)
  ## Returns true if request was started
  e.startCallHierarchyRequest(chrkPrepareOutgoing)

proc requestLspTypeDefinition*(e: Editor): bool =
  ## Request LSP goto type definition at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkTypeDefinition)

proc requestLspImplementation*(e: Editor): bool =
  ## Request LSP goto implementation at current cursor position (async)
  ## Returns true if request was started
  e.startLspLocationRequest(lrkImplementation)

proc startLspHover*(e: Editor): bool =
  ## Start async LSP hover request at current cursor position
  ## Returns true if request was started successfully
  ## Results will be polled by pollLspHover in the tick function
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending hover request
  e.state.lspCache.pendingHoverRequestId = 0

  let activeBuffer = e.activeBuffer()
  let reqResult =
    e.lsp.startHoverRequest(activeBuffer, e.state.cursor.line, e.state.cursor.column)

  if reqResult.isErr:
    e.state.statusMessage = "LSP hover failed: " & reqResult.error
    return false

  e.state.lspCache.pendingHoverRequestId = reqResult.get
  return true

proc pollLspHover*(e: Editor) =
  ## Poll for pending LSP hover response
  ## This should be called from the main event loop (tick function)
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingHoverRequestId
  if requestId == 0:
    return

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingHoverRequestId = 0
    if resultOpt.isSome:
      let hoverOpt = parseHoverResponse(resultOpt.get)
      if hoverOpt.isSome:
        let hoverText = getHoverText(hoverOpt.get)
        if hoverText.len > 0:
          e.state.lspCache.hoverPopup.show(
            hoverText, e.state.cursor.line, e.state.cursor.column
          )
        else:
          e.state.statusMessage = "No hover information available"
      else:
        e.state.statusMessage = "No hover information available"
    else:
      e.state.statusMessage = "No hover information available"
  of lrsError:
    e.state.lspCache.pendingHoverRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP hover failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingHoverRequestId = 0
    e.state.statusMessage = "LSP hover timed out"

proc requestLspHover*(e: Editor): bool =
  ## Request LSP hover information at current cursor position (async)
  ## Returns true if request was started
  ## The hover popup will be shown when the response arrives
  e.startLspHover()

proc hideHoverPopup*(e: Editor) =
  ## Hide the hover popup
  e.state.lspCache.hoverPopup.hide()

proc hoverPopupScrollDown*(e: Editor) =
  ## Scroll hover popup down
  e.state.lspCache.hoverPopup.scrollDown()

proc hoverPopupScrollUp*(e: Editor) =
  ## Scroll hover popup up
  e.state.lspCache.hoverPopup.scrollUp()

proc hoverPopupScrollRight*(e: Editor) =
  ## Scroll hover popup right
  e.state.lspCache.hoverPopup.scrollRight()

proc hoverPopupScrollLeft*(e: Editor) =
  ## Scroll hover popup left
  e.state.lspCache.hoverPopup.scrollLeft()

proc startLspSelectionRange*(e: Editor): bool =
  ## Start async LSP selection range request at current cursor position
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Cancel any pending selection range request
  e.state.lspCache.pendingSelectionRangeRequestId = 0

  let activeBuffer = e.activeBuffer()
  let reqResult = e.lsp.startSelectionRangeRequest(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )

  if reqResult.isErr:
    e.state.statusMessage = "LSP selection range failed: " & reqResult.error
    return false

  e.state.lspCache.pendingSelectionRangeRequestId = reqResult.get
  return true

proc pollLspSelectionRange*(e: Editor) =
  ## Poll for pending selection range response
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingSelectionRangeRequestId
  if requestId == 0:
    return

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingSelectionRangeRequestId = 0
    if resultOpt.isSome:
      let ranges = parseSelectionRangeResponse(resultOpt.get)
      if ranges.len > 0:
        let selRange = ranges[0]
        # Enter visual mode and set selection to the range
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Visual
        e.state.visualSelection = VisualSelection(
          kind: vskChar,
          start: BufferPosition(
            line: selRange.range.start.line, column: selRange.range.start.character
          ),
          current: BufferPosition(
            line: selRange.range.`end`.line, column: selRange.range.`end`.character
          ),
          active: true,
        )
        e.state.cursor = BufferPosition(
          line: selRange.range.`end`.line, column: selRange.range.`end`.character
        )
      else:
        e.state.statusMessage = "No selection range available"
    else:
      e.state.statusMessage = "No selection range available"
  of lrsError:
    e.state.lspCache.pendingSelectionRangeRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP selection range failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingSelectionRangeRequestId = 0
    e.state.statusMessage = "LSP selection range timed out"

proc requestLspSelectionRange*(e: Editor): bool =
  ## Request LSP selection range at current cursor position (async)
  ## Returns true if request was started
  e.startLspSelectionRange()

proc startLspDocumentSymbols*(e: Editor): bool =
  ## Start async document symbols request
  ## Returns true if request was started
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.state.statusMessage = "No file path for current buffer"
    return false

  # Check if document symbol is supported
  if not e.lsp.hasDocumentSymbolSupport(activeBuffer):
    e.state.statusMessage = "Document symbols not supported"
    return false

  # Cancel any pending request
  e.state.lspCache.pendingDocumentSymbolsRequestId = 0

  let reqResult = e.lsp.startDocumentSymbolsRequest(activeBuffer)
  if reqResult.isErr:
    e.state.statusMessage = "LSP document symbols failed: " & reqResult.error
    return false

  e.state.lspCache.pendingDocumentSymbolsRequestId = reqResult.get
  return true

proc pollLspDocumentSymbols*(e: Editor) =
  ## Poll for pending document symbols response
  if not e.lsp.enabled:
    return

  let requestId = e.state.lspCache.pendingDocumentSymbolsRequestId
  if requestId == 0:
    return

  # Poll LSP service for events
  e.lsp.poll(0)

  # Check for response
  let (status, resultOpt, errorOpt) = e.lsp.checkResponse(requestId)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    e.state.lspCache.pendingDocumentSymbolsRequestId = 0
    if resultOpt.isSome:
      let activeBuffer = e.activeBuffer()
      if activeBuffer.filePath.isNone:
        return

      let path = activeBuffer.filePath.get
      let symResult = parseDocumentSymbolsResponse(resultOpt.get)
      let viewerState = newDocumentSymbolViewerState(symResult, path)
      let symbolCount = viewerState.itemCount()

      if symbolCount == 0:
        e.state.statusMessage = "No symbols found"
        return

      # Enter DocumentSymbol mode
      e.state.previousMode = e.state.mode
      e.state.mode = EditorMode.DocumentSymbol
      e.state.documentSymbolViewerState = some(viewerState)
      e.state.statusMessage = $symbolCount & " symbols found"
    else:
      e.state.statusMessage = "No symbols found"
  of lrsError:
    e.state.lspCache.pendingDocumentSymbolsRequestId = 0
    if errorOpt.isSome:
      e.state.statusMessage = "LSP document symbols failed: " & errorOpt.get
  of lrsTimeout:
    e.state.lspCache.pendingDocumentSymbolsRequestId = 0
    e.state.statusMessage = "LSP document symbols timed out"

proc requestDocumentSymbols*(e: Editor): bool =
  ## Request document symbols (async)
  ## Returns true if request was started
  e.startLspDocumentSymbols()

proc hasCodeLensSupport*(e: Editor): bool =
  ## Check if CodeLens is supported for the current buffer
  if not e.lsp.enabled:
    return false
  let activeBuffer = e.activeBuffer()
  return e.lsp.hasCodeLensSupport(activeBuffer)

proc processCodeLensResponse(e: Editor, lenses: seq[CodeLens]) =
  ## Internal: Process code lens response from LSP
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let filePath = activeBuffer.filePath.get

  # Convert to cached items grouped by line (Table for O(1) lookup)
  var itemsByLine: Table[int, seq[CodeLensItem]]
  for lens in lenses:
    var item = CodeLensItem(line: lens.range.start.line)

    if lens.command.isSome:
      let cmd = lens.command.get
      item.title = cmd.title
      item.command = cmd.command
      if cmd.arguments.isSome:
        for arg in cmd.arguments.get:
          item.arguments.add($arg)
    else:
      # Need to resolve - this is still blocking but only for lenses that need it
      let resolveResult = e.lsp.requestCodeLensResolve(activeBuffer, lens)
      if resolveResult.isOk:
        let resolved = resolveResult.get
        if resolved.command.isSome:
          let cmd = resolved.command.get
          item.title = cmd.title
          item.command = cmd.command
          if cmd.arguments.isSome:
            for arg in cmd.arguments.get:
              item.arguments.add($arg)

    if item.title.len > 0:
      # Group by line number
      if item.line notin itemsByLine:
        itemsByLine[item.line] = @[]
      itemsByLine[item.line].add(item)

  e.state.lspCache.codeLensCache = CodeLensCache(
    itemsByLine: itemsByLine,
    changeSeq: activeBuffer.changeSeq,
    filePath: filePath,
    isValid: true,
  )

  # Update timestamp after successful update
  e.state.lspCache.lastCodeLensUpdate = getMonoTime()

proc doUpdateCodeLensCache(e: Editor) =
  ## Internal: Start an async CodeLens request (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  # Check if CodeLens is supported
  if not e.lsp.hasCodeLensSupport(activeBuffer):
    e.state.lspCache.codeLensCache = CodeLensCache(isValid: false)
    return

  # Start async request
  let reqResult = e.lsp.startCodeLensRequest(activeBuffer)
  if reqResult.isOk:
    e.state.lspCache.pendingCodeLensRequestId = reqResult.get
  else:
    e.state.lspCache.codeLensCache = CodeLensCache(isValid: false)

proc updateCodeLensCache*(e: Editor) =
  ## Update the CodeLens cache for the current buffer (with debouncing)
  ## Only updates if enough time has passed since last update and buffer changed
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled or not e.state.display.showCodeLens:
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let filePath = activeBuffer.filePath.get

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingCodeLensRequestId != 0:
    let (status, resultOpt, _) =
      e.lsp.checkResponse(e.state.lspCache.pendingCodeLensRequestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingCodeLensRequestId = 0
      if resultOpt.isSome:
        let lenses = parseCodeLensResponse(resultOpt.get)
        e.processCodeLensResponse(lenses)
      # Continue to check if we need to start a new request (buffer might have changed)
    of lrsError, lrsTimeout:
      # Request failed or timed out, mark cache as valid but empty to prevent retry loop
      e.state.lspCache.pendingCodeLensRequestId = 0
      e.state.lspCache.codeLensCache = CodeLensCache(
        isValid: true, filePath: filePath, changeSeq: activeBuffer.changeSeq
      )
      e.state.lspCache.lastCodeLensUpdate = getMonoTime()
      return

  # Check if cache is still valid (no changes needed)
  if e.state.lspCache.codeLensCache.isValid and
      e.state.lspCache.codeLensCache.filePath == filePath and
      e.state.lspCache.codeLensCache.changeSeq == activeBuffer.changeSeq:
    return

  # Debounce: check if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastCodeLensUpdate
  let threshold = initDuration(milliseconds = e.state.lspCache.codeLensUpdateInterval)

  if elapsed >= threshold:
    e.doUpdateCodeLensCache()

proc getCodeLensItemsForLine*(e: Editor, line: int): seq[CodeLensItem] =
  ## Get cached CodeLens items for a specific line (O(1) lookup)
  if not e.state.lspCache.codeLensCache.isValid:
    return @[]

  e.state.lspCache.codeLensCache.itemsByLine.getOrDefault(line, @[])

proc getCodeLensItemsForCurrentLine*(e: Editor): seq[CodeLensItem] =
  ## Get cached CodeLens items for the current cursor line
  e.getCodeLensItemsForLine(e.state.cursor.line)

proc executeCodeLensItem*(e: Editor, item: CodeLensItem): Result[void, string] =
  ## Execute a cached CodeLens item's command
  if not e.lsp.enabled:
    return err("LSP is not enabled")

  if item.command.len == 0:
    return err("CodeLens has no command")

  let activeBuffer = e.activeBuffer()

  # Convert arguments back to JsonNode
  var args: seq[JsonNode] = @[]
  for argStr in item.arguments:
    try:
      args.add(parseJson(argStr))
    except JsonParsingError:
      args.add(%argStr)

  let execResult = e.lsp.requestExecuteCommand(activeBuffer, item.command, args)
  if execResult.isErr:
    return err("Failed to execute command: " & execResult.error)

  e.state.statusMessage = "Executed: " & item.title
  return ok()

proc invalidateCodeLensCache*(e: Editor) =
  ## Invalidate the CodeLens cache (call when buffer changes significantly)
  e.state.lspCache.codeLensCache.isValid = false

# Document Highlight support
proc invalidateDocumentHighlightCache*(e: Editor) =
  ## Invalidate the Document Highlight cache
  e.state.lspCache.documentHighlightCache.isValid = false
  e.state.lspCache.documentHighlightCache.itemsByLine.clear()

proc processDocumentHighlightResponse(e: Editor, highlights: seq[DocumentHighlight]) =
  ## Internal: Process document highlights from LSP response
  let activeBuffer = e.activeBuffer()

  # Convert LSP DocumentHighlight to our cached format
  # Handle multi-line highlights by creating an item for each line
  # Group by line for O(1) lookup during rendering
  var itemsByLine: Table[int, seq[DocumentHighlightItem]]
  for highlight in highlights:
    let kind =
      if highlight.kind.isSome:
        highlight.kind.get.int
      else:
        1 # Default to Text

    let startLine = highlight.range.start.line
    let endLine = highlight.range.`end`.line

    if startLine == endLine:
      # Single line highlight
      let item = DocumentHighlightItem(
        line: startLine,
        startColumn: highlight.range.start.character,
        endColumn: highlight.range.`end`.character,
        kind: kind,
      )
      if startLine notin itemsByLine:
        itemsByLine[startLine] = @[]
      itemsByLine[startLine].add(item)
    else:
      # Multi-line highlight: create an item for each line
      for line in startLine .. endLine:
        let startCol = if line == startLine: highlight.range.start.character else: 0
        # For end column, use a large value for middle/last lines
        # (will be clamped during rendering)
        let endCol = if line == endLine: highlight.range.`end`.character else: int.high
        let item = DocumentHighlightItem(
          line: line, startColumn: startCol, endColumn: endCol, kind: kind
        )
        if line notin itemsByLine:
          itemsByLine[line] = @[]
        itemsByLine[line].add(item)

  e.state.lspCache.documentHighlightCache = DocumentHighlightCache(
    itemsByLine: itemsByLine,
    cursorLine: e.state.cursor.line,
    cursorColumn: e.state.cursor.column,
    changeSeq: activeBuffer.changeSeq,
    isValid: true,
  )
  e.state.lspCache.lastDocumentHighlightUpdate = getMonoTime()

proc doUpdateDocumentHighlightCache(e: Editor) =
  ## Internal: Start an async Document Highlight request (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.invalidateDocumentHighlightCache()
    return

  # Start async request
  let reqResult = e.lsp.startDocumentHighlightRequest(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )
  if reqResult.isOk:
    e.state.lspCache.pendingDocumentHighlightRequestId = reqResult.get
  else:
    e.invalidateDocumentHighlightCache()

proc updateDocumentHighlightCache*(e: Editor) =
  ## Update the Document Highlight cache (with debouncing)
  ## Called during render to update highlights when cursor moves
  ## Only updates in Normal/Visual modes - cleared in Insert/Replace modes
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled or not e.state.display.showDocumentHighlight:
    return

  # In Insert/Replace modes, clear highlights to avoid distraction
  if e.state.mode in {EditorMode.Insert, EditorMode.Replace}:
    if e.state.lspCache.documentHighlightCache.isValid:
      e.invalidateDocumentHighlightCache()
    e.state.lspCache.pendingDocumentHighlightRequestId = 0
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingDocumentHighlightRequestId != 0:
    let (status, resultOpt, _) =
      e.lsp.checkResponse(e.state.lspCache.pendingDocumentHighlightRequestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingDocumentHighlightRequestId = 0
      if resultOpt.isSome:
        let highlights = parseDocumentHighlightResponse(resultOpt.get)
        e.processDocumentHighlightResponse(highlights)
      # Continue to check if we need to start a new request (cursor might have moved)
    of lrsError, lrsTimeout:
      # Request failed or timed out, clear and continue
      e.state.lspCache.pendingDocumentHighlightRequestId = 0

  # Check if cursor position changed
  # (same line and column means no need to update)
  if e.state.lspCache.documentHighlightCache.isValid and
      e.state.lspCache.documentHighlightCache.cursorLine == e.state.cursor.line and
      e.state.lspCache.documentHighlightCache.cursorColumn == e.state.cursor.column and
      e.state.lspCache.documentHighlightCache.changeSeq == activeBuffer.changeSeq:
    return

  # Debounce - only update if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastDocumentHighlightUpdate
  let threshold =
    initDuration(milliseconds = e.state.lspCache.documentHighlightUpdateInterval)
  if elapsed >= threshold:
    e.doUpdateDocumentHighlightCache()

# =============================================================================
# Semantic Tokens (LSP-based syntax highlighting)
# =============================================================================

proc invalidateSemanticTokensCache*(e: Editor) =
  ## Invalidate the semantic tokens cache, forcing re-request on next update
  e.state.lspCache.semanticTokensCache = SemanticTokensCache(isValid: false)
  e.state.lspCache.pendingSemanticTokensRequestId = 0

proc processSemanticTokensResponse(e: Editor, resp: JsonNode) =
  ## Process semantic tokens response and apply to buffer's highlight
  let activeBuffer = e.activeBuffer()
  if activeBuffer.isNil or activeBuffer.highlight.isNil:
    return

  let legendOpt = e.lsp.getSemanticTokensLegend(activeBuffer)
  if legendOpt.isNone:
    logDebug("editor", "Semantic tokens: no legend available")
    return

  # Parse and apply semantic tokens
  let tokens = parseSemanticTokens(resp)
  applySemanticTokens(activeBuffer.highlight, tokens, legendOpt.get)

  # Mark cache as valid
  e.state.lspCache.semanticTokensCache = SemanticTokensCache(
    changeSeq: activeBuffer.changeSeq,
    filePath: activeBuffer.filePath.get(""),
    isValid: true,
    topLine: e.viewport.topLine,
    bottomLine: e.viewport.topLine + e.viewport.height,
  )
  e.state.lspCache.lastSemanticTokensUpdate = getMonoTime()

proc doUpdateSemanticTokensCache(e: Editor) =
  ## Internal: Start an async semantic tokens request (non-blocking)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.invalidateSemanticTokensCache()
    return

  # Request semantic tokens for visible range (with margin)
  let topLine = max(0, e.viewport.topLine - 10)
  let bottomLine =
    min(e.viewport.topLine + e.viewport.height + 10, activeBuffer.len - 1)

  # Start async request
  let reqResult = e.lsp.startSemanticTokensRequest(activeBuffer, topLine, bottomLine)
  if reqResult.isOk:
    e.state.lspCache.pendingSemanticTokensRequestId = reqResult.get
  else:
    logDebug("editor", "Semantic tokens request failed: " & reqResult.error)
    e.invalidateSemanticTokensCache()

proc updateSemanticTokensCache*(e: Editor) =
  ## Update the semantic tokens cache (with debouncing)
  ## Called during render to update LSP-based syntax highlighting
  ## Uses non-blocking async pattern to avoid freezing the UI
  if not e.lsp.enabled:
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let path = activeBuffer.filePath.get
  let langIdOpt = e.lsp.service.getLanguageIdFromPath(path)
  if langIdOpt.isNone:
    return

  # Check if semantic tokens is supported
  if not e.lsp.service.hasSemanticTokensSupport(langIdOpt.get):
    return

  # Check if there's a pending request - try to get response
  if e.state.lspCache.pendingSemanticTokensRequestId != 0:
    let (status, resultOpt, _) =
      e.lsp.checkResponse(e.state.lspCache.pendingSemanticTokensRequestId)
    case status
    of lrsPending:
      # Still waiting for response, don't start a new request
      return
    of lrsSuccess:
      # Got response, process it
      e.state.lspCache.pendingSemanticTokensRequestId = 0
      if resultOpt.isSome and resultOpt.get.kind != JNull:
        e.processSemanticTokensResponse(resultOpt.get)
      # Continue to check if we need to start a new request
    of lrsError, lrsTimeout:
      # Request failed or timed out, clear and continue
      logDebug("editor", "Semantic tokens request failed or timed out")
      e.state.lspCache.pendingSemanticTokensRequestId = 0

  # Check if cache is still valid
  let cache = e.state.lspCache.semanticTokensCache
  if cache.isValid and cache.changeSeq == activeBuffer.changeSeq and
      cache.filePath == path and cache.topLine <= e.viewport.topLine and
      cache.bottomLine >= e.viewport.topLine + e.viewport.height:
    # Cache is valid and covers current viewport
    return

  # Debounce - only update if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.lspCache.lastSemanticTokensUpdate
  let threshold =
    initDuration(milliseconds = e.state.lspCache.semanticTokensUpdateInterval)
  if elapsed >= threshold:
    e.doUpdateSemanticTokensCache()

proc getCodeLensDisplayText*(e: Editor, line: int): string =
  ## Get display text for CodeLens on a specific line
  ## Returns empty string if no CodeLens on this line
  let items = e.getCodeLensItemsForLine(line)
  if items.len == 0:
    return ""

  var texts: seq[string] = @[]
  for item in items:
    if item.title.len > 0:
      texts.add(item.title)

  return texts.join(" | ")

proc showCodeLensPicker*(e: Editor, items: seq[CodeLensItem]) =
  ## Show the CodeLens picker with the given items
  # Calculate max visible items based on viewport height
  # Reserve space for borders (2) and some margin (4)
  let maxVisible = max(1, e.viewport.height - 6)
  e.state.lspCache.codeLensPicker = CodeLensPicker(
    items: items,
    selectedIndex: 0,
    scrollOffset: 0,
    maxVisibleItems: min(items.len, maxVisible),
    isActive: true,
  )

proc hideCodeLensPicker*(e: Editor) =
  ## Hide the CodeLens picker
  e.state.lspCache.codeLensPicker.isActive = false
  e.state.lspCache.codeLensPicker.items = @[]

proc codeLensPickerSelectNext*(e: Editor) =
  ## Move selection down in CodeLens picker
  if not e.state.lspCache.codeLensPicker.isActive:
    return
  if e.state.lspCache.codeLensPicker.selectedIndex <
      e.state.lspCache.codeLensPicker.items.len - 1:
    e.state.lspCache.codeLensPicker.selectedIndex += 1
    # Adjust scroll offset if selection goes below visible area
    let maxVisible = e.state.lspCache.codeLensPicker.maxVisibleItems
    if e.state.lspCache.codeLensPicker.selectedIndex >=
        e.state.lspCache.codeLensPicker.scrollOffset + maxVisible:
      e.state.lspCache.codeLensPicker.scrollOffset =
        e.state.lspCache.codeLensPicker.selectedIndex - maxVisible + 1

proc codeLensPickerSelectPrev*(e: Editor) =
  ## Move selection up in CodeLens picker
  if not e.state.lspCache.codeLensPicker.isActive:
    return
  if e.state.lspCache.codeLensPicker.selectedIndex > 0:
    e.state.lspCache.codeLensPicker.selectedIndex -= 1
    # Adjust scroll offset if selection goes above visible area
    if e.state.lspCache.codeLensPicker.selectedIndex <
        e.state.lspCache.codeLensPicker.scrollOffset:
      e.state.lspCache.codeLensPicker.scrollOffset =
        e.state.lspCache.codeLensPicker.selectedIndex

proc codeLensPickerSelectByNumber*(e: Editor, num: int): bool =
  ## Select and execute CodeLens item by number (1-9)
  ## Returns true if successfully executed
  if not e.state.lspCache.codeLensPicker.isActive or
      e.state.lspCache.codeLensPicker.items.len == 0:
    return false

  let index = num - 1 # Convert 1-based to 0-based index
  if index < 0 or index >= e.state.lspCache.codeLensPicker.items.len:
    return false

  let item = e.state.lspCache.codeLensPicker.items[index]
  e.hideCodeLensPicker()

  let execResult = e.executeCodeLensItem(item)
  if execResult.isErr:
    e.state.statusMessage = execResult.error
    return false

  return true

proc codeLensPickerConfirm*(e: Editor): bool =
  ## Confirm selection and execute the selected CodeLens item
  ## Returns true if successfully executed
  if not e.state.lspCache.codeLensPicker.isActive or
      e.state.lspCache.codeLensPicker.items.len == 0:
    return false

  let item =
    e.state.lspCache.codeLensPicker.items[e.state.lspCache.codeLensPicker.selectedIndex]
  e.hideCodeLensPicker()

  let execResult = e.executeCodeLensItem(item)
  if execResult.isErr:
    e.state.statusMessage = execResult.error
    return false

  return true

proc executeCurrentLineCodeLens*(e: Editor): bool =
  ## Execute CodeLens on current line
  ## If multiple CodeLens items exist, show picker to choose
  ## Returns true if successfully executed (or picker shown)
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  # Force update cache (bypass debouncing for explicit user action)
  if e.state.display.showCodeLens:
    e.doUpdateCodeLensCache()

  if not e.state.lspCache.codeLensCache.isValid:
    e.state.statusMessage = "No CodeLens available"
    return false

  # Get CodeLens items for current line
  let items = e.getCodeLensItemsForCurrentLine()
  if items.len == 0:
    e.state.statusMessage = "No CodeLens on current line"
    return false

  # If only one item, execute directly
  if items.len == 1:
    let execResult = e.executeCodeLensItem(items[0])
    if execResult.isErr:
      e.state.statusMessage = execResult.error
      return false
    return true

  # Multiple items - show picker
  e.showCodeLensPicker(items)
  e.state.statusMessage =
    "Select CodeLens (1-9: select, j/k: navigate, Enter: confirm, Esc: cancel)"
  return true

proc shutdown*(e: Editor) =
  ## Shutdown editor and clean up resources (including LSP servers)
  e.lsp.shutdown()

proc maybeUpdateDebugBuffer*(e: Editor) =
  ## Update debug buffer content periodically if it's displayed in a window
  ## This provides auto-refresh functionality for the debug viewer
  if e.state.debugBuffer == nil:
    return

  # Check if the debug buffer is still displayed in a window
  var foundWindow: EditorWindow = nil
  for window in e.windowManager.windows:
    if window.buffer == e.state.debugBuffer:
      foundWindow = window
      break

  if foundWindow == nil:
    # Debug buffer is no longer displayed, clear the reference
    e.state.debugBuffer = nil
    return

  # Check if enough time has passed since last update
  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastDebugUpdate
  let threshold = initDuration(milliseconds = e.state.timing.debugUpdateInterval)

  if elapsed < threshold:
    return

  # Generate fresh debug info based on config settings
  var debugLines: seq[string] = @[]
  let debugConfig = e.config.debug

  for i, window in e.windowManager.windows:
    generateWindowInfo(
      debugLines,
      i,
      i == e.windowManager.activeWindowIndex,
      e.buffers.find(window.buffer),
      window.viewport.x,
      window.viewport.y,
      window.viewport.width,
      window.viewport.height,
      window.viewport.topLine,
      window.viewport.leftColumn,
      window.cursor.line,
      window.cursor.column,
      debugConfig.windowNode.enable,
    )

  for i, buf in e.buffers:
    generateBufferInfo(
      debugLines,
      i,
      buf.filePath,
      buf.isModified,
      buf.readOnly,
      $buf.language,
      $buf.encoding,
      buf.len,
      buf.changeSeq,
      debugConfig.bufferStatus.enable,
    )

  generateEditorStateInfo(
    debugLines, e.state.mode, e.state.previousMode, e.state.cursor.line,
    e.state.cursor.column, e.state.commandText, e.state.statusMessage,
    debugConfig.editorView.enable,
  )

  generateSearchInfo(
    debugLines,
    e.state.search.text,
    e.state.search.lastText,
    $e.state.search.direction,
    e.state.search.history.len,
    e.state.search.ignorecase,
    e.state.search.smartcase,
    e.state.search.incsearch,
    e.state.search.hlsearch,
    debugConfig.search.enable,
  )

  generateDisplayInfo(
    debugLines, e.state.display.showStatusLine, e.state.display.multiStatusLine,
    e.state.display.showLineNumbers, e.state.display.showCursorLine,
    e.state.display.showSyntax, e.state.display.showIndentationLines,
    e.state.display.showSidebar, e.state.display.lineWrap, e.state.display.tabStop,
    debugConfig.editorView.enable,
  )

  generateMacroInfo(
    debugLines, e.state.macroState.isRecording, e.state.macroState.register,
    e.state.macroState.registers.len, e.state.macroState.playbackDepth,
    debugConfig.macroState.enable,
  )

  generateVisualInfo(
    debugLines,
    e.state.visualSelection.active,
    $e.state.visualSelection.kind,
    e.state.visualSelection.start.line,
    e.state.visualSelection.start.column,
    e.state.visualSelection.current.line,
    e.state.visualSelection.current.column,
    debugConfig.visual.enable,
  )

  generateJumpListInfo(
    debugLines, e.state.jumpList.len, e.state.jumpListIndex, debugConfig.jumpList.enable
  )

  generateLspInfo(
    debugLines, e.state.lspCache.codeLensCache.itemsByLine.len,
    e.state.lspCache.locations.isSome, e.state.lspCache.codeLensCache.isValid,
    debugConfig.lsp.enable,
  )

  # Create new buffer with updated content
  let debugContent = debugLines.join("\n")
  let newDebugBuffer = newTextBuffer(debugContent)
  newDebugBuffer.readOnly = true

  # Preserve scroll position
  let savedTopLine = foundWindow.viewport.topLine
  let savedLeftColumn = foundWindow.viewport.leftColumn

  # Replace buffer in the window
  foundWindow.buffer = newDebugBuffer

  # Restore scroll position (clamped to valid range)
  foundWindow.viewport.topLine = min(savedTopLine, max(0, newDebugBuffer.len - 1))
  foundWindow.viewport.leftColumn = savedLeftColumn

  # Update the reference in state
  e.state.debugBuffer = newDebugBuffer
  e.state.timing.lastDebugUpdate = now
  e.state.needsFullRedraw = true

proc tick*(e: Editor) =
  ## Background processing: LSP, file watching, autosave, etc.
  ## Should be called each frame before rendering.

  # Poll LSP for messages (non-blocking)
  e.lsp.poll(0)

  # Cleanup stale progress entries (handles missing 'end' notifications)
  e.lsp.cleanupStaleProgress()

  # Update LSP progress display
  let progressOpt = e.lsp.getLatestActiveProgress()
  if progressOpt.isSome:
    e.state.lspProgressText = getProgressText(progressOpt.get)
  else:
    e.state.lspProgressText = ""

  # Display any pending LSP status messages
  let lspMessages = e.lsp.getAndClearMessages()
  if lspMessages.len > 0:
    # Store LSP messages for the log viewer
    addLspMessageLog(lspMessages)
    if e.config.notification.screenNotifications and
        e.config.notification.lspScreenNotify:
      e.state.setStatusMessage(lspMessages[^1])
    if e.config.notification.logNotifications and e.config.notification.lspLogNotify:
      for msg in lspMessages:
        logInfo("lsp", msg)

  # Update LSP if buffer was modified
  e.maybeUpdateLsp()

  # Update LSP caches
  e.updateCodeLensCache()
  e.updateDocumentHighlightCache()
  # Note: updateSemanticTokensCache is called in prepareFrame after updateHighlight
  e.requestSignatureHelpFromLsp()
  e.pollLspCompletion()
  e.pollLspHover()
  e.pollLspLocationRequest()
  e.pollLspCallHierarchy()
  e.pollLspSelectionRange()
  e.pollLspDocumentSymbols()

  # File and config monitoring
  e.maybeReloadExternallyModifiedFile()
  e.maybeReloadConfig()

  # Git and debug updates
  e.maybeUpdateGitDiff()
  e.maybeUpdateDebugBuffer()

  # Auto save/backup
  e.autoSave()
  e.autoBackup()

proc prepareFrame(e: Editor, buffer: var Buffer): bool =
  ## Prepare for rendering: clear buffer, update animations, prepare highlights.
  ## Returns true if viewport was resized.

  clearBuffer(buffer)

  # Update smooth scroll animation
  if e.state.scrollAnimation.active:
    let reservedLines =
      if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve
    let bufferLen = e.activeBuffer().len
    let (active, cursorLine) = e.executer.motionController.viewportManager.updateScrollAnimation(
      e.state.scrollAnimation, e.config.smoothScroll, reservedLines, bufferLen
    )
    e.state.cursor.line = cursorLine

  if e.state.needsFullRedraw:
    e.state.needsFullRedraw = false

  # Update highlight state (skip for debug buffer)
  let isDebugBuffer =
    e.state.debugBuffer != nil and e.activeBuffer() == e.state.debugBuffer

  if e.config.highlight.pairOfParen and not isDebugBuffer:
    e.state.matchingParenPos =
      findMatchingParenPosition(e.activeBuffer(), e.state.cursor)
  else:
    e.state.matchingParenPos = none(BufferPosition)

  if e.config.highlight.currentWord and not isDebugBuffer:
    e.state.currentWord = getWordAtPosition(e.activeBuffer(), e.state.cursor)
  else:
    e.state.currentWord = ""

  # Update syntax highlight before rendering (so semantic tokens can be applied on top)
  if not isDebugBuffer:
    let activeBuffer = e.activeBuffer()
    let needsHighlightUpdate = activeBuffer.highlightNeedsUpdate
    activeBuffer.updateHighlight()
    # If highlight was regenerated, we need to re-apply semantic tokens
    if needsHighlightUpdate:
      e.invalidateSemanticTokensCache()
    # Apply semantic tokens after local highlight is ready
    e.updateSemanticTokensCache()

  result = e.updateViewportSize(buffer)

proc renderSpecialMode(e: Editor, buffer: var Buffer): bool =
  ## Render special modes (Filer, LogViewer, Help, etc.).
  ## Returns true if a special mode was rendered, false otherwise.

  template tryRender(
      targetMode: EditorMode, isActiveInCmd: bool, renderProc: untyped
  ): bool =
    if e.state.mode == targetMode or
        (e.state.mode == EditorMode.Command and isActiveInCmd):
      e.renderProc(buffer)
      e.renderBottomLines(buffer)
      true
    else:
      false

  let prev = e.state.previousMode

  if tryRender(EditorMode.Filer, e.state.filerState.isSome, renderFiler):
    return true
  # LogViewer uses split window with actual TextBuffer, rendered via renderSplitView
  if tryRender(
    EditorMode.References, e.state.referencesViewerState.isSome, renderReferencesViewer
  ):
    return true
  if tryRender(
    EditorMode.DocumentSymbol, e.state.documentSymbolViewerState.isSome,
    renderDocumentSymbolViewer,
  ):
    return true
  if tryRender(EditorMode.Help, e.state.helpViewerState.isSome, renderHelpViewer):
    return true
  if tryRender(
    EditorMode.BufferManager, e.state.bufferManagerState.isSome, renderBufferManager
  ):
    return true
  if tryRender(EditorMode.Config, e.state.configModeState.isSome, renderConfigMode):
    return true
  if tryRender(
    EditorMode.BackupManager, e.state.backupManagerState.isSome, renderBackupManager
  ):
    return true
  if tryRender(EditorMode.DiffViewer, e.state.diffViewerState.isSome, renderDiffViewer):
    return true
  if tryRender(
    EditorMode.RecentFile, prev == EditorMode.RecentFile, renderRecentFileMode
  ):
    return true
  if tryRender(EditorMode.Debug, prev == EditorMode.Debug, renderDebugMode):
    return true

  return false

proc renderMainContent(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render the main editor view (single or split).
  if e.windowManager.windows.len > 0:
    e.renderSplitView(buffer, wasResized)
  else:
    e.renderSingleView(buffer, wasResized)

  e.renderBottomLines(buffer)
  e.renderTempMessages(buffer)

proc renderOverlays(e: Editor, buffer: var Buffer) =
  ## Render overlay popups (completion, signature help, CodeLens picker, hover popup).

  if e.state.mode == EditorMode.Insert:
    let completionMgr = e.handlerManager.insertHandler.completionManager
    if completionMgr.isActive():
      let popupPos = calculatePopupPosition(
        e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
        buffer.area.height, completionMgr.menu.entries, completionMgr.menu.maxVisible,
      )
      renderCompletionPopup(
        buffer, completionMgr.menu, popupPos, e.config.autocomplete.windowBorder
      )

    let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
    if sigHelpMgr.isActive():
      let popupPos = calculateSignatureHelpPosition(
        e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
        buffer.area.height, sigHelpMgr.display.signature.len,
      )
      renderSignatureHelpPopup(buffer, sigHelpMgr.display, popupPos, true)

  if e.state.lspCache.codeLensPicker.isActive:
    e.renderCodeLensPicker(buffer)

  # Render hover popup (Normal mode)
  if e.state.lspCache.hoverPopup.isActive():
    let hoverMgr = e.state.lspCache.hoverPopup
    let popupPos = calculateHoverPopupPosition(
      e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
      buffer.area.height, hoverMgr,
    )
    renderHoverPopup(buffer, hoverMgr, popupPos, true)

proc render*(e: Editor, buffer: var Buffer) =
  ## Main render procedure - orchestrates the rendering of all editor components.
  if buffer.area.width <= 0 or buffer.area.height <= 0:
    return

  e.tick()
  let wasResized = e.prepareFrame(buffer)

  if not e.renderSpecialMode(buffer):
    e.renderMainContent(buffer, wasResized)

  e.renderOverlays(buffer)
