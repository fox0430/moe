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

import std/[strutils, strformat, options, tables, unicode, monotimes, times]

import pkg/[celina, results]

import
  buffer, cursor, types, commands, keybindings, commandregistry, modes, commandline,
  commandconfig, statusline, windowmanager, unicode_utils, render_utils, sidebar,
  gitdiff, highlight, logger, config, configloader, keybindconfig, search_utils
import command_handlers/[handler_manager, visual_handler]

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
  if e.state.showStatusLine:
    if e.state.multiStatusLine:
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

  if e.state.lineWrap:
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
        displayWidthUpToWithTabs(cursorLineText, cursor.column, e.state.tabStop)

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
        displayWidthUpToCursor =
          displayWidthUpToWithTabs(cursorLineText, cursor.column, e.state.tabStop)
        displayWidthUpToLeftCol =
          displayWidthUpToWithTabs(cursorLineText, viewport.leftColumn, e.state.tabStop)

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
  if e.state.showSidebar: DefaultSidebarWidth else: 0

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
      calculateLineNumOffset(window.buffer, e.state.showLineNumbers) + sidebarWidth
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

  let shouldQuit = e.windowManager.closeWindow(e.state.multiStatusLine)

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
  e.state.lineWrap = not e.state.lineWrap
  e.state.needsFullRedraw = true

proc setLineWrap*(e: Editor, enabled: bool) =
  ## Set line wrapping
  e.state.lineWrap = enabled
  e.state.needsFullRedraw = true

proc toggleMultiStatusLine*(e: Editor) =
  ## Toggle between single status line (at bottom) and multi status lines (per window)
  e.state.multiStatusLine = not e.state.multiStatusLine
  e.state.needsFullRedraw = true

proc setMultiStatusLine*(e: Editor, enabled: bool) =
  ## Set multi status line mode
  e.state.multiStatusLine = enabled
  e.state.needsFullRedraw = true

proc toggleSidebar*(e: Editor) =
  ## Toggle the visibility of the sidebar
  e.state.showSidebar = not e.state.showSidebar
  e.state.needsFullRedraw = true

proc setSidebarVisible*(e: Editor, visible: bool) =
  ## Set the visibility of the sidebar
  e.state.showSidebar = visible
  e.state.needsFullRedraw = true

proc toggleGitDiff*(e: Editor) =
  ## Toggle git diff indicators in sidebar
  e.state.showGitDiff = not e.state.showGitDiff

  # Update git diff information when enabled
  if e.state.showGitDiff:
    discard updateBufferWithGitDiff(e.textBuffer)

  e.state.needsFullRedraw = true

proc setGitDiffVisible*(e: Editor, visible: bool) =
  ## Set git diff indicators visibility in sidebar
  e.state.showGitDiff = visible

  # Update git diff information when enabled
  if visible:
    discard updateBufferWithGitDiff(e.textBuffer)

  e.state.needsFullRedraw = true

proc toggleSyntaxChecker*(e: Editor) =
  ## Toggle syntax checker results in sidebar
  e.state.showSyntaxChecker = not e.state.showSyntaxChecker
  e.state.needsFullRedraw = true

proc setSyntaxCheckerVisible*(e: Editor, visible: bool) =
  ## Set syntax checker results visibility in sidebar
  e.state.showSyntaxChecker = visible
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
    e.textBuffer, e.viewport, e.state.cursor, e.state.multiStatusLine, filename
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

  result = Editor(
    textBuffer: newTextBuffer(),
    state: EditorState(
      cursor: BufferPosition(line: 0, column: 0),
      screenCursor: CursorPosition(x: 0, y: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
      showStatusLine: editorConfig.standard.statusLine,
      multiStatusLine: editorConfig.statusLine.multipleStatusLine,
      showLineCount: true,
      showLinePercentage: true,
      showEncoding: true,
      needsFullRedraw: true, # Initial render needs full draw
      viewportReservedLines: 2, # Default for single window mode with status line
      lineWrap: true, # Default to wrapping
      lastResizeTime: getMonoTime(), # Initialize to current time
      # Sidebar defaults
      showSidebar: editorConfig.standard.sidebar,
      showGitDiff: editorConfig.git.showChangedLine,
      showSyntaxChecker: editorConfig.syntaxChecker.enable,
      lastGitDiffUpdate: getMonoTime(), # Initialize to current time
      lastGitDiffChangeSeq: 0, # Initialize to 0 (no changes yet)
      gitDiffUpdateInterval: editorConfig.git.updateInterval,
      # Editor behavior
      tabStop: editorConfig.standard.tabStop,
      expandTab: editorConfig.standard.expandTab,
      autoIndent: editorConfig.standard.autoIndent,
      autoCloseParen: editorConfig.standard.autoCloseParen,
      autoDeleteParen: editorConfig.standard.autoDeleteParen,
      showLineNumbers: editorConfig.standard.number,
      showCurrentLineNumber: editorConfig.standard.currentNumber,
      showCursorLine: editorConfig.standard.cursorLine,
      showSyntax: editorConfig.standard.syntax,
      showIndentationLines: editorConfig.standard.indentationLines,
      # Search settings
      ignorecase: true,
      smartcase: true,
      incsearch: true, # Enable incremental search by default
      hlsearch: true, # Enable search highlighting by default
      hlsearchTempDisabled: false, # Highlight is not disabled initially
      lastKeyWasEscape: false, # Track double-Escape for clearing highlight
      searchStartPos: BufferPosition(line: 0, column: 0),
        # Will be set when entering search mode
      searchDirection: Forward, # Default to forward search
      searchHistory: loadSearchHistory(), # Load search history from disk
      searchHistoryIndex: -1, # Not navigating history initially
      pendingOperator: none(PendingOperator), # No pending operator initially
      pendingTextObject: none(PendingTextObject), # No pending text object initially
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
    cmdRegistry, result.config.clipboard,
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
  if e.state.showGitDiff:
    let activeBuffer = e.activeBuffer()
    let diffResult = updateBufferWithGitDiff(activeBuffer, useBuffer)

    if diffResult.isOk:
      e.state.lastGitDiffUpdate = getMonoTime()
      e.state.lastGitDiffChangeSeq = activeBuffer.changeSeq
      e.state.needsFullRedraw = true

proc maybeUpdateGitDiff*(e: Editor) =
  ## Update git diff if buffer was modified and enough time has passed (debouncing)
  ## This should be called after buffer modifications to provide real-time updates

  if not e.state.showGitDiff:
    return

  let activeBuffer = e.activeBuffer()

  # Only update if buffer has changed since last update
  if activeBuffer.changeSeq == e.state.lastGitDiffChangeSeq:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.lastGitDiffUpdate

  # Compare with threshold duration (500ms)
  let threshold = initDuration(milliseconds = e.state.gitDiffUpdateInterval)

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
  if e.state.showGitDiff:
    let diffResult = updateBufferWithGitDiff(e.textBuffer, useBuffer = false)
    if diffResult.isErr:
      # Log error but don't fail the file load
      # (file might not be in a git repository)
      logDebug("editor", "Git diff not available for " & path & ": " & diffResult.error)
    else:
      # Update lastGitDiffChangeSeq to prevent immediate re-check
      e.state.lastGitDiffChangeSeq = e.textBuffer.changeSeq

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

  ok(())

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
  if not e.state.showIndentationLines:
    return false

  # Only show guides at indent levels (multiples of tabStop)
  if displayX mod e.state.tabStop != 0:
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
  elif e.state.hlsearch and not e.state.hlsearchTempDisabled:
    # Determine which search pattern to use:
    # - In Search mode with text: use current searchText (incremental highlight)
    # - In Search mode without text: no highlight (user is starting a new search)
    # - Not in Search mode: use lastSearchText (persistent highlight from previous search)
    let searchPattern =
      if e.state.mode == EditorMode.Search:
        # In Search mode: only highlight if user has typed something
        if e.state.searchText.len > 0:
          e.state.searchText
        else:
          "" # No highlight when starting a new search
      else:
        # Not in Search mode: use last search pattern
        e.state.lastSearchText

    # Only apply highlight if we have a valid search pattern
    if searchPattern.len > 0:
      # Apply smartcase logic
      let shouldIgnoreCase =
        shouldIgnoreCase(searchPattern, e.state.ignorecase, e.state.smartcase)

      if buffer.isPositionInSearchMatch(pos, searchPattern, shouldIgnoreCase):
        searchHighlightStyle
      elif e.state.showSyntax and not buffer.highlight.isNil:
        # Apply syntax highlighting from buffer
        # Update highlight if needed (after text edits)
        buffer.updateHighlight()
        let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
        var style = colorIndexToStyle(colorPair)
        # Apply cursor line highlighting if enabled and on cursor line
        if e.state.showCursorLine and pos.line == cursorLine:
          style.bg = cursorLineHighlightStyle.bg
        style
      else:
        # Apply cursor line highlighting if enabled and on cursor line
        if e.state.showCursorLine and pos.line == cursorLine:
          cursorLineHighlightStyle
        else:
          normalStyle
    elif e.state.showSyntax and not buffer.highlight.isNil:
      # Apply syntax highlighting from buffer
      # Update highlight if needed (after text edits)
      buffer.updateHighlight()
      let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
      var style = colorIndexToStyle(colorPair)
      # Apply cursor line highlighting if enabled and on cursor line
      if e.state.showCursorLine and pos.line == cursorLine:
        style.bg = cursorLineHighlightStyle.bg
      style
    else:
      # Apply cursor line highlighting if enabled and on cursor line
      if e.state.showCursorLine and pos.line == cursorLine:
        cursorLineHighlightStyle
      else:
        normalStyle
  elif e.state.showSyntax and not buffer.highlight.isNil:
    # Apply syntax highlighting from buffer
    # Update highlight if needed (after text edits)
    buffer.updateHighlight()
    let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
    var style = colorIndexToStyle(colorPair)
    # Apply cursor line highlighting if enabled and on cursor line
    if e.state.showCursorLine and pos.line == cursorLine:
      style.bg = cursorLineHighlightStyle.bg
    style
  else:
    # Apply cursor line highlighting if enabled and on cursor line
    if e.state.showCursorLine and pos.line == cursorLine:
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

  # Always render character by character to apply syntax highlighting
  var displayX = 0

  # Template to render a single character (eliminates code duplication)
  # Using template instead of proc to avoid closure capture issues
  template renderChar(rune: Rune, col: int, style: Style) =
    # Handle tab character specially
    if rune == TAB_CHAR:
      # Calculate how many spaces until next tab stop
      let spacesToNextTab = e.state.tabStop - (displayX mod e.state.tabStop)
      # Render spaces instead of tab character
      for i in 0 ..< spacesToNextTab:
        if screenX + displayX < buffer.area.width:
          # Check if we should show indentation guide at this position
          if e.shouldShowIndentationGuide(indentInfo, displayX, col):
            buffer.setString(screenX + displayX, screenY, "│", indentationLineStyle)
          else:
            buffer.setString(screenX + displayX, screenY, " ", style)
        displayX += 1
    else:
      # Normal character
      var charStr = $rune
      var renderStyle = style

      # Check if this is a space and should show indentation guide
      if rune == ' '.Rune and e.shouldShowIndentationGuide(indentInfo, displayX, col):
        charStr = "│"
        renderStyle = indentationLineStyle

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
  if e.state.showCursorLine and lineIndex == ctx.cursorLine:
    while screenX + displayX < buffer.area.width:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle)
      displayX += 1

proc fillCursorLineBackground(
    e: Editor, buffer: var Buffer, screenX, screenY: int, lineIndex, cursorLine: int
) =
  ## Fill the rest of the line with cursor line background if on cursor line
  if e.state.showCursorLine and lineIndex == cursorLine:
    var displayX = 0
    while screenX + displayX < buffer.area.width:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle)
      displayX += 1

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
        if isCurrentLine and e.state.showCurrentLineNumber:
          currentLineStyle
        else:
          lineNumStyle

    if e.state.lineWrap:
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

    if e.state.lineWrap:
      # Line wrapping enabled - split long lines across multiple screen lines
      let
        maxWidth = area.width
        lineCharLen = line.charLen # Use character count, not byte count

      if lineCharLen == 0:
        # Empty line - fill with cursor line highlight if on cursor line
        e.fillCursorLineBackground(
          buffer, area.x, area.y + screenY, lineIndex, e.state.cursor.line
        )
        inc screenY
        inc lineIndex
        continue

      var startCharCol = 0 # Character position, not byte position
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
      else:
        # Empty line or scrolled past line end - fill with cursor line highlight if on cursor line
        e.fillCursorLineBackground(
          buffer, area.x, area.y + screenY, lineIndex, e.state.cursor.line
        )

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
    if e.state.showSidebar:
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
    # Render sidebar if enabled
    if maybeSidebar.isSome:
      renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, 0)

    if e.state.lineWrap:
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
  elif not e.state.multiStatusLine:
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
      e.viewport.width, e.viewport.height, oldWidth, oldHeight, e.state.multiStatusLine
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
    let lineNumOffset = calculateLineNumOffset(window.buffer, e.state.showLineNumbers)

    # Determine if this is a bottom window (needs status line reservation)
    # A window is a bottom window if its bottom edge is at the maximum bottom Y
    let
      windowBottomY = window.viewport.y + window.viewport.height
      isBottomWindow = (windowBottomY == maxBottomY)
      isActiveWindow = (i == e.windowManager.activeWindowIndex)

    e.renderWindow(buffer, window, lineNumOffset, isBottomWindow, isActiveWindow)

    # Render per-window status line if multi-status line mode is enabled
    if e.state.showStatusLine and e.state.multiStatusLine:
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
    lineNumOffset = calculateLineNumOffset(e.textBuffer, e.state.showLineNumbers)
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
    if e.state.showSidebar:
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
  if e.state.showLineNumbers:
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
  if e.windowManager.windows.len == 0 or not e.state.multiStatusLine:
    e.state.renderStatusLine(e.activeBuffer(), buffer, statusLineY)

  # Handle command line
  if e.state.mode == EditorMode.Command:
    buffer.setString(buffer.area.x, commandLineY, e.state.commandText, commandStyle)
    e.state.screenCursor.x = e.state.commandText.len
    e.state.screenCursor.y = buffer.area.height - 1
  elif e.state.mode == EditorMode.Search:
    let searchChar = if e.state.searchDirection == Forward: "/" else: "?"
    let searchPrompt = searchChar & e.state.searchText
    buffer.setString(buffer.area.x, commandLineY, searchPrompt, commandStyle)
    e.state.screenCursor.x = searchPrompt.len
    e.state.screenCursor.y = buffer.area.height - 1
  else:
    if e.state.statusMessage.len > 0:
      buffer.setString(buffer.area.x, commandLineY, e.state.statusMessage, commandStyle)

proc render*(e: Editor, buffer: var Buffer) =
  ## Main render procedure - orchestrates the rendering of all editor components
  # Early return if buffer area is too small
  if buffer.area.width <= 0 or buffer.area.height <= 0:
    return

  # Update git diff if buffer was modified (with debouncing)
  e.maybeUpdateGitDiff()

  # Clear buffer to prevent artifacts
  clearBuffer(buffer)

  # Reset the full redraw flag if it was set
  if e.state.needsFullRedraw:
    e.state.needsFullRedraw = false

  # Update viewport size and check if resized
  let wasResized = e.updateViewportSize(buffer)

  # Render appropriate view based on window configuration
  if e.windowManager.windows.len > 0:
    e.renderSplitView(buffer, wasResized)
  else:
    e.renderSingleView(buffer, wasResized)

  # Render bottom lines (status and command lines)
  e.renderBottomLines(buffer)
