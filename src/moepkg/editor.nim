#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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
  lspintegration, completion, signaturehelp, backup, command_completion, motion,
  logviewer
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
    config*: EditorConfig # TOML configuration
    lsp*: LspIntegration # LSP client integration
    lastLspChangeSeq*: int # Track buffer changes for LSP notifications

proc buffer*(e: Editor): TextBuffer =
  e.textBuffer

proc activeBuffer*(e: Editor): TextBuffer =
  ## Get the currently active buffer (from active window if split, otherwise main buffer)
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.windowManager.windows[e.windowManager.activeWindowIndex].buffer
  else:
    e.textBuffer

proc saveActiveWindowState(e: Editor) =
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

proc syncActiveWindow(e: Editor) =
  ## Sync the active window's buffer and viewport with the executor and motion controller
  let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
  e.executer.buffer = activeWindow.buffer
  e.executer.motionController.executor.buffer = activeWindow.buffer
  e.executer.motionController.viewportManager.viewport = activeWindow.viewport
  e.restoreActiveWindowState()
  e.state.needsFullRedraw = true

proc calculateReservedLines(e: Editor, isBottomWindow: bool = true): int =
  ## Calculate number of reserved lines based on status line configuration
  if e.state.display.showStatusLine:
    if e.state.display.multiStatusLine:
      if isBottomWindow: StatusAndCommandReserve else: StatusLineReserve
    elif isBottomWindow:
      StatusAndCommandReserve
    else:
      0
  else:
    if isBottomWindow: CommandLineReserve else: 0

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

proc switchToNextBuffer*(e: Editor) =
  ## Switch to the next buffer (:bnext)
  ## In this editor, buffers are windows, so this switches to the next window
  if e.windowManager.windows.len <= 1:
    e.state.statusMessage = "No more buffers"
    return

  e.switchToNextWindow()
  e.state.statusMessage = ""

proc switchToPrevBuffer*(e: Editor) =
  ## Switch to the previous buffer (:bprev)
  ## In this editor, buffers are windows, so this switches to the previous window
  if e.windowManager.windows.len <= 1:
    e.state.statusMessage = "No more buffers"
    return

  e.switchToPrevWindow()
  e.state.statusMessage = ""

proc switchToFirstBuffer*(e: Editor) =
  ## Switch to the first buffer (:bfirst)
  ## In this editor, buffers are windows, so this switches to the first window
  if e.windowManager.windows.len <= 1:
    e.state.statusMessage = "Already at first buffer"
    return

  if e.windowManager.activeWindowIndex == 0:
    e.state.statusMessage = "Already at first buffer"
    return

  # Save current window state before switching
  e.saveActiveWindowState()

  # Switch to first window
  e.windowManager.activeWindowIndex = 0
  for i, window in e.windowManager.windows:
    window.active = (i == 0)

  # Sync and restore the new active window state
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  let activeWindow = e.windowManager.windows[0]
  e.setActiveWindowScreenCursor(activeWindow)
  e.state.statusMessage = ""

proc switchToLastBuffer*(e: Editor) =
  ## Switch to the last buffer (:blast)
  ## In this editor, buffers are windows, so this switches to the last window
  if e.windowManager.windows.len <= 1:
    e.state.statusMessage = "Already at last buffer"
    return

  let lastIndex = e.windowManager.windows.len - 1
  if e.windowManager.activeWindowIndex == lastIndex:
    e.state.statusMessage = "Already at last buffer"
    return

  # Save current window state before switching
  e.saveActiveWindowState()

  # Switch to last window
  e.windowManager.activeWindowIndex = lastIndex
  for i, window in e.windowManager.windows:
    window.active = (i == lastIndex)

  # Sync and restore the new active window state
  e.syncActiveWindow()

  # Update cursor position immediately to avoid visual glitch
  let activeWindow = e.windowManager.windows[lastIndex]
  e.setActiveWindowScreenCursor(activeWindow)
  e.state.statusMessage = ""

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
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer

  # Restore the new active window state
  e.restoreActiveWindowState()
  e.state.needsFullRedraw = true

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
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer

  # Restore the new active window state
  e.restoreActiveWindowState()
  e.state.needsFullRedraw = true

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

  let newBuffer = bufferResult.get
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer

  # Restore the new active window state
  e.restoreActiveWindowState()
  e.state.needsFullRedraw = true

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc enew*(e: Editor): Result[(), string] =
  ## Create a new empty buffer and replace the current one
  let newBuffer = newTextBuffer()

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

proc editFile*(e: Editor, path: string): Result[(), string] =
  ## Load a file and replace the current buffer (like :e in Vim)
  ## If the file doesn't exist, create an empty buffer with the path set (new file)
  let newBuffer = newTextBuffer()

  if fileExists(path):
    # Load existing file
    let loadResult = newBuffer.loadFile(path)
    if loadResult.isErr:
      return err(loadResult.error)
  else:
    # New file: set the path for saving later
    newBuffer.filePath = some(path)

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

proc newEditor*(): Editor =
  # Load TOML configuration
  let editorConfig = loadConfig()

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
    state: EditorState(
      cursor: BufferPosition(line: 0, column: 0),
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
      ),
      # Search state (grouped in SearchState)
      search: SearchState(
        text: "",
        lastText: "",
        direction: Forward,
        history: loadSearchHistory(),
        historyIndex: -1,
        startPos: BufferPosition(line: 0, column: 0),
        ignorecase: true,
        smartcase: true,
        incsearch: true,
        hlsearch: true,
        hlsearchTempDisabled: false,
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
        locations: none(LspLocationsResult),
        lastCodeLensUpdate: getMonoTime(),
        codeLensUpdateInterval: 1000, # 1 second debounce
        lastDocumentHighlightUpdate: getMonoTime(),
        documentHighlightUpdateInterval: 200, # 200ms debounce
      ),
    ),
    viewport: ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 20, x: 0, y: 0),
    commandRegistry: cmdRegistry,
    keyBindingRegistry: keyRegistry,
    commandLineParser: cmdLineParser,
    commandConfig: cmdConfig,
    handlerManager: nil, # Will be set after executer is created
    windowManager: newEditorWindowManager(),
    config: editorConfig, # Store configuration
  )

  result.executer = newCommandExecutor(
    result.textBuffer,
    result.state,
    result.viewport,
    result.config.clipboard,
    some(cmdRegistry),
    some(keyRegistry),
  )

  # Create handler manager after executer (which creates motion controller)
  result.handlerManager = newHandlerManager(
    result.executer.motionController, keyRegistry, cmdLineParser, cmdConfig,
    cmdRegistry, result.config.clipboard, result.config.smoothScroll,
  )

  # Set clipboard tool for register system
  if result.config.clipboard.enable:
    result.state.registers.setClipboardTool(result.config.clipboard.tool)

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

proc loadFile*(e: Editor, path: string): Result[(), string] =
  ## Load text file
  logDebug("editor", "Loading file: " & path)
  let r = e.textBuffer.loadFile(path)
  if r.isErr:
    logError("editor", "Failed to load file " & path & ": " & r.error)
    return err r.error

  logInfo("editor", "Successfully loaded file: " & path)

  # Reset cursor to file start
  e.state.cursor = BufferPosition(line: 0, column: 0)

  # Reset viewport to start
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

  # Notify LSP that a document was opened
  if e.lsp.enabled:
    let lspResult = e.lsp.onBufferOpen(e.textBuffer)
    if lspResult.isErr:
      logDebug("editor", "LSP onBufferOpen failed for " & path & ": " & lspResult.error)
    else:
      e.lastLspChangeSeq = e.textBuffer.changeSeq

  ok(())

proc saveFile*(e: Editor, path: Option[string] = none(string)): Result[(), string] =
  ## Save the active buffer to file
  ## If path is provided, save to that path, otherwise use buffer's current file path
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
    if e.config.notification.autoSaveLogNotify:
      if savedCount == 1:
        logInfo("editor", "Auto saved: " & savedPaths[0])
      else:
        logInfo("editor", "Auto saved " & $savedCount & " files")

    # Screen notification (status message)
    if e.config.notification.autoSaveScreenNotify:
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
    if e.config.notification.autoBackupLogNotify:
      if backupCount == 1:
        logInfo("editor", "Auto backup: " & backupPaths[0])
      else:
        logInfo("editor", "Auto backup: " & $backupCount & " files")

    # Screen notification (status message)
    if e.config.notification.autoBackupScreenNotify:
      if backupCount == 1:
        e.state.statusMessage = "Auto backup created"
      else:
        e.state.statusMessage = "Auto backup: " & $backupCount & " files"

proc colorIndexToStyle(colorIdx: EditorColorPairIndex): Style =
  ## Convert EditorColorPairIndex to Celina Style based on dark.toml theme
  case colorIdx
  of keyword:
    # #87d7ff - Light blue
    Style(fg: rgb(0x87, 0xd7, 0xff), bg: ColorValue(kind: Default), modifiers: {})
  of builtin:
    # #add8e6 - Light blue
    Style(fg: rgb(0xad, 0xd8, 0xe6), bg: ColorValue(kind: Default), modifiers: {})
  of boolean:
    # #add8e6 - Light blue
    Style(fg: rgb(0xad, 0xd8, 0xe6), bg: ColorValue(kind: Default), modifiers: {})
  of specialVar:
    # #0090a8 - Dark cyan
    Style(fg: rgb(0x00, 0x90, 0xa8), bg: ColorValue(kind: Default), modifiers: {})
  of stringLit, charLit:
    # #add8e6 - Light blue
    Style(fg: rgb(0xad, 0xd8, 0xe6), bg: ColorValue(kind: Default), modifiers: {})
  of decNumber, binNumber, hexNumber, octNumber, floatNumber:
    # #add8e6 - Light blue
    Style(fg: rgb(0xad, 0xd8, 0xe6), bg: ColorValue(kind: Default), modifiers: {})
  of comment, longComment:
    # #808080 - Gray
    Style(fg: rgb(0x80, 0x80, 0x80), bg: ColorValue(kind: Default), modifiers: {})
  of preprocessor:
    # #0090a8 - Dark cyan
    Style(fg: rgb(0x00, 0x90, 0xa8), bg: ColorValue(kind: Default), modifiers: {})
  of functionName:
    # #00b7ce - Cyan
    Style(fg: rgb(0x00, 0xb7, 0xce), bg: ColorValue(kind: Default), modifiers: {})
  of typeName:
    # #00ffff - Cyan
    Style(fg: rgb(0x00, 0xff, 0xff), bg: ColorValue(kind: Default), modifiers: {})
  of identifier:
    # Use default foreground color
    normalStyle
  of operator:
    # #00b7ce - Cyan
    Style(fg: rgb(0x00, 0xb7, 0xce), bg: ColorValue(kind: Default), modifiers: {})
  of pragma:
    # #0090a8 - Dark cyan
    Style(fg: rgb(0x00, 0x90, 0xa8), bg: ColorValue(kind: Default), modifiers: {})
  of whitespace:
    # #808080 - Gray
    Style(fg: rgb(0x80, 0x80, 0x80), bg: ColorValue(kind: Default), modifiers: {})
  of table:
    # #0090a8 - Dark cyan
    Style(fg: rgb(0x00, 0x90, 0xa8), bg: ColorValue(kind: Default), modifiers: {})
  of date:
    # #0090a8 - Dark cyan
    Style(fg: rgb(0x00, 0x90, 0xa8), bg: ColorValue(kind: Default), modifiers: {})
  of property:
    # #00b7ce - Cyan
    Style(fg: rgb(0x00, 0xb7, 0xce), bg: ColorValue(kind: Default), modifiers: {})
  of selectArea:
    visualStyle
  else:
    normalStyle

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
    documentHighlightReadStyle
  of 3: # Write
    documentHighlightWriteStyle
  else: # Text or unknown
    documentHighlightTextStyle

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

  if hasSelection and e.state.visualSelection.isPositionInSelection(pos):
    visualStyle
  elif isCursorPos:
    # Cursor position: always use gray foreground color
    cursorCharStyle
  elif e.state.search.hlsearch and not e.state.search.hlsearchTempDisabled:
    # Determine which search pattern to use:
    # - In Search mode with text: use current searchText (incremental highlight)
    # - In Search mode without text: no highlight (user is starting a new search)
    # - Not in Search mode: use lastSearchText (persistent highlight from previous search)
    let searchPattern =
      if e.state.mode == EditorMode.Search:
        # In Search mode: only highlight if user has typed something
        if e.state.search.text.len > 0:
          e.state.search.text
        else:
          "" # No highlight when starting a new search
      else:
        # Not in Search mode: use last search pattern
        e.state.search.lastText

    # Only apply highlight if we have a valid search pattern
    if searchPattern.len > 0:
      # Apply smartcase logic
      let shouldIgnoreCase = shouldIgnoreCase(
        searchPattern, e.state.search.ignorecase, e.state.search.smartcase
      )

      if buffer.isPositionInSearchMatch(pos, searchPattern, shouldIgnoreCase):
        searchHighlightStyle
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
          style.bg = cursorLineHighlightStyle.bg
        style
      else:
        # Check document highlight first
        let highlightKind = e.isPositionInDocumentHighlight(pos)
        if highlightKind.isSome:
          getDocumentHighlightStyle(highlightKind.get)
        elif e.state.display.showCursorLine and pos.line == cursorLine:
          cursorLineHighlightStyle
        else:
          normalStyle
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
        style.bg = cursorLineHighlightStyle.bg
      style
    else:
      # Check document highlight first
      let highlightKind = e.isPositionInDocumentHighlight(pos)
      if highlightKind.isSome:
        getDocumentHighlightStyle(highlightKind.get)
      elif e.state.display.showCursorLine and pos.line == cursorLine:
        cursorLineHighlightStyle
      else:
        normalStyle
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
      style.bg = cursorLineHighlightStyle.bg
    style
  else:
    # Check document highlight first
    let highlightKind = e.isPositionInDocumentHighlight(pos)
    if highlightKind.isSome:
      getDocumentHighlightStyle(highlightKind.get)
    elif e.state.display.showCursorLine and pos.line == cursorLine:
      cursorLineHighlightStyle
    else:
      normalStyle

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
          trailingSpacesStyle
        else:
          style
      # Render spaces instead of tab character
      for i in 0 ..< spacesToNextTab:
        if screenX + displayX < buffer.area.width:
          # Check if we should show indentation guide at this position
          if e.shouldShowIndentationGuide(indentInfo, displayX, col):
            buffer.setString(screenX + displayX, screenY, "│", indentationLineStyle)
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
        renderStyle = indentationLineStyle

      # Highlight full-width space if enabled
      if rune == FULLWIDTH_SPACE and e.config.highlight.fullWidthSpace:
        renderStyle = fullWidthSpaceStyle

      # Highlight trailing spaces if enabled
      if e.config.highlight.trailingSpaces and col >= trailingSpaceStart:
        if rune == ' '.Rune or rune == TAB_CHAR or rune == FULLWIDTH_SPACE:
          renderStyle = trailingSpacesStyle

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
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle)
      displayX += 1

proc fillCursorLineBackground(
    e: Editor, buffer: var Buffer, screenX, screenY: int, lineIndex, cursorLine: int
) =
  ## Fill the rest of the line with cursor line background if on cursor line
  if e.state.display.showCursorLine and lineIndex == cursorLine:
    var displayX = 0
    while screenX + displayX < buffer.area.width:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle)
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
    buffer.setString(screenX + displayX, screenY, $ch, codeLensStyle)
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
    normalStyle = Style(
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

    let style = if itemIdx == selectedIdx: selectedStyle else: normalStyle

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
          currentLineStyle
        else:
          lineNumStyle

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
          lineNumX, buffer.area.y + screenY, emptyLineNumStr, lineNumStyle
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
    buffer.setString(lineNumX, buffer.area.y + screenY, emptyLineNumStr, lineNumStyle)
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
        currentLineStyle
      else:
        lineNumStyle
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
            lineNumScreenX, currentActualScreenY, emptyLineNumStr, lineNumStyle
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
        currentLineStyle
      else:
        lineNumStyle
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
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineNumStyle)

  # Render fold text
  if textScreenX < buffer.area.width:
    let maxWidth = buffer.area.width - textScreenX
    let displayText =
      if foldText.len > maxWidth:
        foldText[0 ..< maxWidth]
      else:
        foldText
    buffer.setString(textScreenX, actualScreenY, displayText, foldStyle)

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
          buffer.setString(sepX, y, "│", separatorStyle)
  elif not e.state.display.multiStatusLine:
    # Horizontal split - draw horizontal separator at window boundary
    # ONLY when using a single status line
    let sepY = window.viewport.y + window.viewport.height
    if sepY < buffer.area.height:
      # Draw separator for the width of this window
      for x in window.viewport.x ..< (window.viewport.x + window.viewport.width):
        if x < buffer.area.width:
          buffer.setString(x, sepY, "─", separatorStyle)

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

    e.renderWindow(buffer, window, lineNumOffset, isBottomWindow, isActiveWindow)

    # Render per-window status line if multi-status line mode is enabled
    if e.state.display.showStatusLine and e.state.display.multiStatusLine:
      let statusLineY = calculateWindowStatusLineY(window, isBottomWindow)
      e.state.renderWindowStatusLine(
        window.buffer, buffer, statusLineY, window.viewport.x, window.viewport.width,
        isActiveWindow,
      )

    # Draw separator between windows (except for last window)
    if i < e.windowManager.windows.len - 1:
      let nextWindow = e.windowManager.windows[i + 1]
      e.renderWindowSeparator(buffer, window, nextWindow, isBottomWindow)

  # Set cursor to active window position
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

proc renderSingleViewSidebar(buffer: var Buffer, sidebar: Sidebar, screenY: int) =
  ## Render a single line of the sidebar for single view mode
  if screenY >= 0 and screenY < sidebar.buffer.len:
    for x in 0 ..< sidebar.width:
      let item = sidebar.buffer[screenY][x]
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

  # Render sidebar if enabled
  if maybeSidebar.isSome:
    let sidebar = maybeSidebar.get
    var screenY = 0
    var lineIndex = e.viewport.topLine
    while screenY < buffer.area.height - reservedLines and lineIndex < e.textBuffer.len:
      renderSingleViewSidebar(buffer, sidebar, screenY)
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
  # - Multi-window mode: only render if multiStatusLine is disabled (single status line mode)
  if e.windowManager.windows.len == 0 or not e.state.display.multiStatusLine:
    e.state.renderStatusLine(e.activeBuffer(), buffer, statusLineY)

  # Handle command line
  if e.state.mode == EditorMode.Command:
    buffer.setString(buffer.area.x, commandLineY, e.state.commandText, commandStyle)
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
    buffer.setString(buffer.area.x, commandLineY, searchPrompt, commandStyle)
    e.state.screenCursor.x = searchPrompt.len
    e.state.screenCursor.y = buffer.area.height - 1
  else:
    if e.state.statusMessage.len > 0:
      buffer.setString(buffer.area.x, commandLineY, e.state.statusMessage, commandStyle)

proc renderFiler(e: Editor, buffer: var Buffer) =
  ## Render the file explorer view
  if e.state.filerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom = if e.state.display.showStatusLine: 2 else: 1

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
      fg: rgb(0xff, 0xd7, 0x00),
      bg: ColorValue(kind: Default),
      modifiers: {StyleModifier.Bold},
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
    let prefix = if isSelected: "> " else: "  "

    let icon =
      case entry.kind
      of fekDirectory: "▸ "
      of fekSymlink: "@ "
      of fekFile: "  "

    let name =
      if entry.isDirectory:
        entry.name & "/"
      else:
        entry.name

    displayLine = prefix & icon & name

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Apply style
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif entry.kind == fekDirectory:
        Style(
          fg: rgb(0x5f, 0x87, 0xff),
          bg: ColorValue(kind: Default),
          modifiers: {StyleModifier.Bold},
        )
      elif entry.kind == fekSymlink:
        # Symlinks: cyan for files, magenta for directories
        if entry.targetKind == fekDirectory:
          Style(
            fg: rgb(0xaf, 0x5f, 0xff),
            bg: ColorValue(kind: Default),
            modifiers: {StyleModifier.Bold},
          )
        else:
          Style(fg: rgb(0x00, 0xff, 0xff), bg: ColorValue(kind: Default), modifiers: {})
      elif entry.isHidden:
        Style(fg: rgb(0x80, 0x80, 0x80), bg: ColorValue(kind: Default), modifiers: {})
      else:
        Style(
          fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {}
        )

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in filer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (filerState.selectedIndex - filerState.topLine)

proc renderLogViewer(e: Editor, buffer: var Buffer) =
  ## Render the log viewer view
  if e.state.logViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom = if e.state.display.showStatusLine: 2 else: 1

  let
    logState = e.state.logViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- LOG --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00),
      bg: ColorValue(kind: Default),
      modifiers: {StyleModifier.Bold},
    ),
  )

  # Ensure selected line is visible
  logState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render log lines
  var screenY = listStartY
  for i in logState.topLine ..< logState.lineCount:
    if screenY >= listEndY:
      break

    let
      line = logState.getLine(i)
      isSelected = i == logState.selectedIndex

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        Style(
          fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {}
        )

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in log viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (logState.selectedIndex - logState.topLine)

proc renderHelpViewer(e: Editor, buffer: var Buffer) =
  ## Render the help viewer view
  if e.state.helpViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom = if e.state.display.showStatusLine: 2 else: 1

  let
    helpState = e.state.helpViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- HELP --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00),
      bg: ColorValue(kind: Default),
      modifiers: {StyleModifier.Bold},
    ),
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

    # Apply style
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif isHeader:
        Style(
          fg: rgb(0x5f, 0xaf, 0xff),
          bg: ColorValue(kind: Default),
          modifiers: {StyleModifier.Bold},
        )
      else:
        Style(
          fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {}
        )

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
  if not e.lsp.enabled:
    return

  if e.state.mode != EditorMode.Insert:
    return

  let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
  if sigHelpMgr.parenDepth == 0 and not sigHelpMgr.isActive():
    return

  let activeBuffer = e.activeBuffer()
  let sigHelpResult =
    e.lsp.requestSignatureHelp(activeBuffer, e.state.cursor.line, e.state.cursor.column)

  if sigHelpResult.isOk:
    let sigHelpOpt = sigHelpResult.get
    if sigHelpOpt.isSome:
      let sigHelp = sigHelpOpt.get
      sigHelpMgr.show(sigHelp, e.state.cursor.line, e.state.cursor.column)
    else:
      # No signature help available
      if sigHelpMgr.parenDepth == 0:
        sigHelpMgr.hide()

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
    # Multiple locations - jump to first and store all for reference
    var items: seq[LspLocationItem] = @[]
    for loc in locations:
      let path = lspservice.uriToPath(loc.uri)
      items.add(
        LspLocationItem(
          uri: loc.uri,
          path: path,
          line: loc.range.start.line,
          column: loc.range.start.character,
          text: "",
        )
      )
    e.state.lspCache.locations =
      some(LspLocationsResult(items: items, selectedIndex: 0, title: title))

    # Jump to the first location
    discard e.jumpToLspLocation(locations[0], singularName)
    e.state.statusMessage =
      $locations.len & " " & title.toLowerAscii() & " found (showing first)"
    return true

proc requestLspGotoDefinition*(e: Editor): bool =
  ## Request LSP goto definition at current cursor position
  ## Returns true if successful and location was found
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()
  let defResult =
    e.lsp.requestDefinition(activeBuffer, e.state.cursor.line, e.state.cursor.column)

  if defResult.isErr:
    e.state.statusMessage = "LSP goto definition failed: " & defResult.error
    return false

  return e.handleLspLocations(defResult.get, "Definitions", "Definition")

proc requestLspGotoDeclaration*(e: Editor): bool =
  ## Request LSP goto declaration at current cursor position
  ## Returns true if successful and location was found
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()
  let declResult =
    e.lsp.requestDeclaration(activeBuffer, e.state.cursor.line, e.state.cursor.column)

  if declResult.isErr:
    e.state.statusMessage = "LSP goto declaration failed: " & declResult.error
    return false

  return e.handleLspLocations(declResult.get, "Declarations", "Declaration")

proc requestLspReferences*(e: Editor): bool =
  ## Request LSP find references at current cursor position
  ## Returns true if successful and references were found
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()
  let refsResult =
    e.lsp.requestReferences(activeBuffer, e.state.cursor.line, e.state.cursor.column)

  if refsResult.isErr:
    e.state.statusMessage = "LSP find references failed: " & refsResult.error
    return false

  return e.handleLspLocations(refsResult.get, "References", "Reference")

proc requestLspCallHierarchyIncoming*(e: Editor): bool =
  ## Request LSP incoming calls (callers) at current cursor position
  ## Returns true if successful and callers were found
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()

  # First, prepare call hierarchy to get the item at cursor
  let prepareResult = e.lsp.requestCallHierarchyPrepare(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )

  if prepareResult.isErr:
    e.state.statusMessage = "LSP call hierarchy failed: " & prepareResult.error
    return false

  let items = prepareResult.get
  if items.len == 0:
    e.state.statusMessage = "No callable symbol at cursor"
    return false

  # Get incoming calls for the first item
  let incomingResult = e.lsp.requestCallHierarchyIncomingCalls(activeBuffer, items[0])

  if incomingResult.isErr:
    e.state.statusMessage = "LSP incoming calls failed: " & incomingResult.error
    return false

  let calls = incomingResult.get
  if calls.len == 0:
    e.state.statusMessage = "No incoming calls found"
    return false

  # Convert CallHierarchyIncomingCall to Location for display
  var locations: seq[lspTypes.Location] = @[]
  for call in calls:
    locations.add(
      lspTypes.Location(uri: call.`from`.uri, range: call.`from`.selectionRange)
    )

  return e.handleLspLocations(locations, "Incoming Calls", "Caller")

proc requestLspCallHierarchyOutgoing*(e: Editor): bool =
  ## Request LSP outgoing calls (callees) at current cursor position
  ## Returns true if successful and callees were found
  if not e.lsp.enabled:
    e.state.statusMessage = "LSP is not enabled"
    return false

  let activeBuffer = e.activeBuffer()

  # First, prepare call hierarchy to get the item at cursor
  let prepareResult = e.lsp.requestCallHierarchyPrepare(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )

  if prepareResult.isErr:
    e.state.statusMessage = "LSP call hierarchy failed: " & prepareResult.error
    return false

  let items = prepareResult.get
  if items.len == 0:
    e.state.statusMessage = "No callable symbol at cursor"
    return false

  # Get outgoing calls for the first item
  let outgoingResult = e.lsp.requestCallHierarchyOutgoingCalls(activeBuffer, items[0])

  if outgoingResult.isErr:
    e.state.statusMessage = "LSP outgoing calls failed: " & outgoingResult.error
    return false

  let calls = outgoingResult.get
  if calls.len == 0:
    e.state.statusMessage = "No outgoing calls found"
    return false

  # Convert CallHierarchyOutgoingCall to Location for display
  var locations: seq[lspTypes.Location] = @[]
  for call in calls:
    locations.add(lspTypes.Location(uri: call.to.uri, range: call.to.selectionRange))

  return e.handleLspLocations(locations, "Outgoing Calls", "Callee")

proc hasCodeLensSupport*(e: Editor): bool =
  ## Check if CodeLens is supported for the current buffer
  if not e.lsp.enabled:
    return false
  let activeBuffer = e.activeBuffer()
  return e.lsp.hasCodeLensSupport(activeBuffer)

proc doUpdateCodeLensCache(e: Editor) =
  ## Internal: Actually perform the CodeLens cache update
  ## This makes LSP requests and should be called with debouncing
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let filePath = activeBuffer.filePath.get

  # Check if CodeLens is supported
  if not e.lsp.hasCodeLensSupport(activeBuffer):
    e.state.lspCache.codeLensCache = CodeLensCache(isValid: false)
    return

  # Request CodeLenses from LSP
  let lensesResult = e.lsp.requestCodeLens(activeBuffer)
  if lensesResult.isErr:
    e.state.lspCache.codeLensCache = CodeLensCache(isValid: false)
    return

  # Convert to cached items grouped by line (Table for O(1) lookup)
  var itemsByLine: Table[int, seq[CodeLensItem]]
  for lens in lensesResult.get:
    var item = CodeLensItem(line: lens.range.start.line)

    if lens.command.isSome:
      let cmd = lens.command.get
      item.title = cmd.title
      item.command = cmd.command
      if cmd.arguments.isSome:
        for arg in cmd.arguments.get:
          item.arguments.add($arg)
    else:
      # Need to resolve
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

proc updateCodeLensCache*(e: Editor) =
  ## Update the CodeLens cache for the current buffer (with debouncing)
  ## Only updates if enough time has passed since last update and buffer changed
  if not e.lsp.enabled or not e.state.display.showCodeLens:
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

  let filePath = activeBuffer.filePath.get

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

proc doUpdateDocumentHighlightCache(e: Editor) =
  ## Internal: Actually perform the Document Highlight cache update
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    e.invalidateDocumentHighlightCache()
    return

  # Request Document Highlights from LSP
  let highlightsResult = e.lsp.requestDocumentHighlight(
    activeBuffer, e.state.cursor.line, e.state.cursor.column
  )
  if highlightsResult.isErr:
    e.invalidateDocumentHighlightCache()
    return

  # Convert LSP DocumentHighlight to our cached format
  # Handle multi-line highlights by creating an item for each line
  # Group by line for O(1) lookup during rendering
  var itemsByLine: Table[int, seq[DocumentHighlightItem]]
  for highlight in highlightsResult.get:
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

proc updateDocumentHighlightCache*(e: Editor) =
  ## Update the Document Highlight cache (with debouncing)
  ## Called during render to update highlights when cursor moves
  ## Only updates in Normal/Visual modes - cleared in Insert/Replace modes
  if not e.lsp.enabled or not e.state.display.showDocumentHighlight:
    return

  # In Insert/Replace modes, clear highlights to avoid distraction
  if e.state.mode in {EditorMode.Insert, EditorMode.Replace}:
    if e.state.lspCache.documentHighlightCache.isValid:
      e.invalidateDocumentHighlightCache()
    return

  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return

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

proc render*(e: Editor, buffer: var Buffer) =
  ## Main render procedure - orchestrates the rendering of all editor components
  # Early return if buffer area is too small
  if buffer.area.width <= 0 or buffer.area.height <= 0:
    return

  # Poll LSP for messages (non-blocking)
  e.lsp.poll(0)

  # Update LSP if buffer was modified
  e.maybeUpdateLsp()

  # Update CodeLens cache if needed
  e.updateCodeLensCache()

  # Update Document Highlight cache if needed
  e.updateDocumentHighlightCache()

  # Request signature help from LSP if in insert mode
  e.requestSignatureHelpFromLsp()

  # Update git diff if buffer was modified (with debouncing)
  e.maybeUpdateGitDiff()

  # Auto save if enabled and interval has passed
  e.autoSave()

  # Auto backup if enabled and conditions are met
  e.autoBackup()

  # Clear buffer to prevent artifacts
  clearBuffer(buffer)

  # Update smooth scroll animation
  if e.state.scrollAnimation.active:
    let reservedLines = if e.state.display.showStatusLine: 2 else: 1
    let (active, cursorLine) = e.executer.motionController.viewportManager.updateScrollAnimation(
      e.state.scrollAnimation, e.config.smoothScroll, reservedLines
    )
    # Update cursor line during animation
    e.state.cursor.line = cursorLine

  # Reset the full redraw flag if it was set
  if e.state.needsFullRedraw:
    e.state.needsFullRedraw = false

  # Update viewport size and check if resized
  let wasResized = e.updateViewportSize(buffer)

  # Handle Filer mode rendering separately
  # Also render filer when in Command mode but came from Filer (filerState is active)
  if e.state.mode == EditorMode.Filer or
      (e.state.mode == EditorMode.Command and e.state.filerState.isSome):
    e.renderFiler(buffer)
    e.renderBottomLines(buffer)
    return

  # Handle LogViewer mode rendering separately
  # Also render log viewer when in Command mode but came from LogViewer (logViewerState is active)
  if e.state.mode == EditorMode.LogViewer or
      (e.state.mode == EditorMode.Command and e.state.logViewerState.isSome):
    e.renderLogViewer(buffer)
    e.renderBottomLines(buffer)
    return

  # Handle Help mode rendering separately
  # Also render help viewer when in Command mode but came from Help (helpViewerState is active)
  if e.state.mode == EditorMode.Help or
      (e.state.mode == EditorMode.Command and e.state.helpViewerState.isSome):
    e.renderHelpViewer(buffer)
    e.renderBottomLines(buffer)
    return

  # Render appropriate view based on window configuration
  if e.windowManager.windows.len > 0:
    e.renderSplitView(buffer, wasResized)
  else:
    e.renderSingleView(buffer, wasResized)

  # Render bottom lines (status and command lines)
  e.renderBottomLines(buffer)

  # Render completion popup if active (must be after other rendering)
  if e.state.mode == EditorMode.Insert:
    let completionMgr = e.handlerManager.insertHandler.completionManager
    if completionMgr.isActive():
      # Use already-calculated screen cursor position
      # This correctly accounts for line wrapping and viewport scrolling
      let popupPos = calculatePopupPosition(
        e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
        buffer.area.height, completionMgr.menu.entries, completionMgr.menu.maxVisible,
      )

      # Render the popup
      renderCompletionPopup(
        buffer, completionMgr.menu, popupPos, e.config.autocomplete.windowBorder
      )

    # Render signature help popup if active
    let sigHelpMgr = e.handlerManager.insertHandler.signatureHelpManager
    if sigHelpMgr.isActive():
      let popupPos = calculateSignatureHelpPosition(
        e.state.screenCursor.x, e.state.screenCursor.y, buffer.area.width,
        buffer.area.height, sigHelpMgr.display.signature.len,
      )
      renderSignatureHelpPopup(buffer, sigHelpMgr.display, popupPos, true)

  # Render CodeLens picker popup if active
  if e.state.lspCache.codeLensPicker.isActive:
    e.renderCodeLensPicker(buffer)
