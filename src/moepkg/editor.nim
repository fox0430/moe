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

import std/[strutils, strformat, options, tables, unicode]

import pkg/[celina, results]

import
  buffer, cursor, types, commands, keybindings, commandregistry, modes, commandline,
  commandconfig, statusline, windowmanager, unicode_utils, render_utils
import command_handlers/[handler_manager, visual_handler]

type Editor* = ref object
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

proc buffer*(e: Editor): TextBuffer =
  e.textBuffer

proc activeBuffer*(e: Editor): TextBuffer =
  ## Get the currently active buffer (from active window if split, otherwise main buffer)
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.windowManager.windows[e.windowManager.activeWindowIndex].buffer
  else:
    e.textBuffer

proc syncActiveWindow(e: Editor) =
  ## Sync the active window's buffer and viewport with the executor and motion controller
  let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
  e.executer.buffer = activeWindow.buffer
  e.executer.motionController.executor.buffer = activeWindow.buffer
  e.executer.motionController.viewportManager.viewport = activeWindow.viewport
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
      displayWidthUpToCursor = displayWidthUpTo(cursorLineText, cursor.column)

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
      return CursorPosition(
        x: viewport.x + lineNumOffset + wrapLineColumn, y: viewport.y + screenY
      )
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
        displayWidthUpToCursor = displayWidthUpTo(cursorLineText, cursor.column)
        displayWidthUpToLeftCol = displayWidthUpTo(cursorLineText, viewport.leftColumn)

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
    lineNumOffset = calculateLineNumOffset(window.buffer)
    reservedLines = e.calculateReservedLines(isBottomWindow)

  e.state.screenCursor = e.calculateWindowCursor(
    window.buffer, window.viewport, window.cursor, lineNumOffset, reservedLines
  )

proc switchToNextWindow*(e: Editor) =
  ## Switch to the next window (Ctrl-w, k)
  if e.windowManager.windows.len <= 1:
    return

  # Deactivate all windows
  for i in 0 ..< e.windowManager.windows.len:
    e.windowManager.windows[i].active = false

  e.windowManager.activeWindowIndex =
    (e.windowManager.activeWindowIndex + 1) mod e.windowManager.windows.len

  # Activate the new window
  e.windowManager.windows[e.windowManager.activeWindowIndex].active = true
  e.syncActiveWindow

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

proc switchToPrevWindow*(e: Editor) =
  ## Switch to the previous window (Ctrl-w, j)
  if e.windowManager.windows.len <= 1:
    return

  # Deactivate all windows
  for i in 0 ..< e.windowManager.windows.len:
    e.windowManager.windows[i].active = false

  e.windowManager.activeWindowIndex =
    (e.windowManager.activeWindowIndex - 1 + e.windowManager.windows.len) mod
    e.windowManager.windows.len

  # Activate the new window
  e.windowManager.windows[e.windowManager.activeWindowIndex].active = true
  e.syncActiveWindow

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

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

proc vsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a vertical split window
  let bufferResult =
    e.windowManager.vsplit(e.textBuffer, e.viewport, e.state.cursor, filename)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer
  e.state.needsFullRedraw = true

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc hsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a horizontal split window (top and bottom)
  let bufferResult = e.windowManager.hsplit(
    e.textBuffer, e.viewport, e.state.cursor, e.state.multiStatusLine, filename
  )
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer
  e.state.needsFullRedraw = true

  # Update cursor position immediately to avoid visual glitch
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

  ok(())

proc newEditor*(): Editor =
  # Create registries and configuration first
  let
    cmdRegistry = newCommandRegistry()
    keyRegistry = newKeyBindingRegistry()
    cmdConfig = newCommandConfig()
    cmdLineParser = newCommandLineParser()

  # Register built-in commands and default bindings
  cmdRegistry.registerBuiltinCommands
  keyRegistry.setupDefaultBindings

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
      showStatusLine: true,
      multiStatusLine: true, # Default to multiple status line
      showLineCount: true,
      showLinePercentage: true,
      showEncoding: true,
      needsFullRedraw: true, # Initial render needs full draw
      viewportReservedLines: 2, # Default for single window mode with status line
      lineWrap: true, # Default to wrapping
    ),
    viewport: ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 20, x: 0, y: 0),
    commandRegistry: cmdRegistry,
    keyBindingRegistry: keyRegistry,
    commandLineParser: cmdLineParser,
    commandConfig: cmdConfig,
    handlerManager: nil, # Will be set after executer is created
    windowManager: newEditorWindowManager(),
  )

  result.executer = newCommandExecutor(
    result.textBuffer,
    result.state,
    result.viewport,
    some(cmdRegistry),
    some(keyRegistry),
  )

  # Create handler manager after executer (which creates motion controller)
  result.handlerManager = newHandlerManager(
    result.executer.motionController, keyRegistry, cmdLineParser, cmdConfig, cmdRegistry
  )

proc loadFile*(e: Editor, path: string): Result[(), string] =
  ## Load text file
  let r = e.textBuffer.loadFile(path)
  if r.isErr:
    return err r.error

  # Reset cursor to file start
  e.state.cursor = BufferPosition(line: 0, column: 0)

  # Reset viewport to start
  e.viewport.topLine = 0
  e.viewport.leftColumn = 0

  ok(())

proc getSelectionStyle(e: Editor, hasSelection: bool, pos: BufferPosition): Style =
  ## Get the appropriate style for a character based on selection state
  if hasSelection and e.state.visualSelection.isPositionInSelection(pos):
    visualStyle
  else:
    normalStyle

proc getVisualSelection(
    e: Editor, windowActive: bool = true
): tuple[hasSelection: bool, selStart, selEnd: BufferPosition] =
  ## Get visual selection range if active
  ## windowActive: only show selection in active window (default true for compatibility)
  let hasSelection =
    e.state.mode == EditorMode.Visual and e.state.visualSelection.active and windowActive

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
    buffer: var Buffer,
    displayLine: string,
    screenX, screenY: int,
    lineIndex: int,
    startColumn: int,
    hasSelection: bool,
    selStart, selEnd: BufferPosition,
    useRunes: bool = true,
) =
  ## Render a line segment with selection highlighting
  ## useRunes: true for wrapped mode (character-based), false for byte-based rendering
  if not hasSelection or lineIndex < selStart.line or lineIndex > selEnd.line:
    # No selection - fast path
    buffer.setString(screenX, screenY, displayLine, normalStyle)
    return

  if useRunes:
    # Character-based rendering (for wrapped mode)
    var displayX = 0
    var charIdx = startColumn
    for rune in displayLine.runes:
      let
        pos = BufferPosition(line: lineIndex, column: charIdx)
        style = e.getSelectionStyle(hasSelection, pos)
        charStr = $rune
      if screenX + displayX < buffer.area.width:
        buffer.setString(screenX + displayX, screenY, charStr, style)
      displayX += 1
      charIdx += 1
  else:
    # Byte-based rendering (for non-wrapped mode)
    for i in 0 ..< displayLine.len:
      let
        col = startColumn + i
        pos = BufferPosition(line: lineIndex, column: col)
        style = e.getSelectionStyle(hasSelection, pos)
        charStr = $displayLine[i]
      if screenX + i < buffer.area.width:
        buffer.setString(screenX + i, screenY, charStr, style)

proc renderLineNumbers(e: Editor, buffer: var Buffer, textAreaWidth: int): int =
  ## Render line numbers and return max width of the line number text.

  # Guard against invalid text area width
  if textAreaWidth <= 0:
    return 0

  let
    lineLen = e.textBuffer.len
    maxLineNumWidth = len($lineLen) + LineNumberSpacer
    reservedLines = e.calculateReservedLines(isBottomWindow = true)
  var
    screenY = 0
    lineIndex = e.viewport.topLine

  while screenY < buffer.area.height - reservedLines and lineIndex < lineLen:
    # Render line numbers with wrapping support
    let
      line = e.textBuffer.getLine(lineIndex)
      isCurrentLine = lineIndex == e.state.cursor.line
      lineStyle = if isCurrentLine: currentLineStyle else: lineNumStyle

    if e.state.lineWrap:
      let
        lineCharLen = line.charLen # Use character count, not byte count
        numWraps = calculateWrapCount(lineCharLen, textAreaWidth)
        lineNumStr = formatLineNumber(lineIndex, maxLineNumWidth)

      buffer.setString(buffer.area.x, buffer.area.y + screenY, lineNumStr, lineStyle)
      inc screenY

      for _ in 1 ..< numWraps:
        # Render empty space for wrapped parts (no line number)
        if screenY >= buffer.area.height - reservedLines:
          break
        let emptyLineNumStr = spaces(maxLineNumWidth)
        buffer.setString(
          buffer.area.x, buffer.area.y + screenY, emptyLineNumStr, lineNumStyle
        )
        inc screenY
    else:
      # Normal single-line display
      let lineNumStr = formatLineNumber(lineIndex, maxLineNumWidth)
      buffer.setString(buffer.area.x, buffer.area.y + screenY, lineNumStr, lineStyle)
      inc screenY

    inc lineIndex

  while screenY < buffer.area.height - reservedLines:
    # Clear remaining line number area to prevent artifacts
    let emptyLineNumStr = spaces(maxLineNumWidth)
    buffer.setString(
      buffer.area.x, buffer.area.y + screenY, emptyLineNumStr, lineNumStyle
    )
    inc screenY

  return maxLineNumWidth

proc renderTextBuffer(e: Editor, buffer: var Buffer, area: Rect) =
  # Get visual selection range if active
  let (hasSelection, selStart, selEnd) = e.getVisualSelection()

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
        # Empty line
        inc screenY
        inc lineIndex
        continue

      var startCharCol = 0 # Character position, not byte position
      while startCharCol < lineCharLen and screenY < area.height:
        let
          endCharCol = min(startCharCol + maxWidth, lineCharLen)
          # Convert character positions to byte positions for slicing
          startBytePos = charToBytePos(line, startCharCol)
          endBytePos = charToBytePos(line, endCharCol)
          displayLine = line[startBytePos ..< endBytePos]

        if displayLine.len > 0:
          # Render with selection highlighting if in visual mode
          e.renderLineSegmentWithSelection(
            buffer,
            displayLine,
            area.x,
            area.y + screenY,
            lineIndex,
            startCharCol,
            hasSelection,
            selStart,
            selEnd,
            useRunes = true,
          )

        inc screenY
        startCharCol += maxWidth
    else:
      # No line wrapping - use horizontal scrolling
      let displayLine =
        if e.viewport.leftColumn < line.len:
          line[e.viewport.leftColumn ..^ 1]
        else:
          ""

      if displayLine.len > 0:
        # Render with selection highlighting if in visual mode
        e.renderLineSegmentWithSelection(
          buffer,
          displayLine,
          area.x,
          area.y + screenY,
          lineIndex,
          e.viewport.leftColumn,
          hasSelection,
          selStart,
          selEnd,
          useRunes = false,
        )

      inc screenY

    inc lineIndex

proc renderWindowLineWrapped(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    hasSelection: bool,
    selStart, selEnd: BufferPosition,
    screenY: var int,
    lineIndex: var int,
    visibleHeight: int,
) =
  ## Render a single line with wrapping enabled
  let
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    maxWidth = window.viewport.width - lineNumOffset
    lineCharLen = line.charLen
    isCurrentLine = (lineIndex == window.cursor.line and window.active)
    lineStyle = if isCurrentLine: currentLineStyle else: lineNumStyle
    lineNumScreenX = window.viewport.x

  if lineCharLen == 0:
    # Empty line - just render line number
    let lineNumStr = formatLineNumber(lineIndex, lineNumOffset)
    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)
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
      textScreenX = window.viewport.x + lineNumOffset
      currentActualScreenY = window.viewport.y + screenY

    # Render line number for first wrap, empty space for others
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
          buffer,
          displayLine,
          textScreenX,
          currentActualScreenY,
          lineIndex,
          startCharCol,
          hasSelection,
          selStart,
          selEnd,
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
    hasSelection: bool,
    selStart, selEnd: BufferPosition,
    screenY: int,
    lineIndex: int,
) =
  ## Render a single line without wrapping (horizontal scrolling)
  let
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    isCurrentLine = (lineIndex == window.cursor.line and window.active)
    lineStyle = if isCurrentLine: currentLineStyle else: lineNumStyle
    lineNumStr = formatLineNumber(lineIndex, lineNumOffset)
    lineNumScreenX = window.viewport.x

  # Render line number
  if lineNumScreenX + lineNumStr.len <= buffer.area.width:
    buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)

  # Render text content
  let
    displayLine =
      if window.viewport.leftColumn < line.len:
        line[window.viewport.leftColumn ..^ 1]
      else:
        ""
    textScreenX = window.viewport.x + lineNumOffset

  if displayLine.len > 0 and textScreenX < buffer.area.width:
    let maxWidth = min(displayLine.len, window.viewport.width - lineNumOffset)
    if maxWidth > 0:
      # Render with selection highlighting if in visual mode
      e.renderLineSegmentWithSelection(
        buffer,
        displayLine[0 ..< maxWidth],
        textScreenX,
        actualScreenY,
        lineIndex,
        window.viewport.leftColumn,
        hasSelection,
        selStart,
        selEnd,
        useRunes = false,
      )

proc renderWindow(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    isBottomWindow: bool,
    isActiveWindow: bool,
) =
  ## Render a single window with line numbers and text content
  let
    lineCount = window.buffer.len
    reservedLines = e.calculateReservedLines(isBottomWindow)
    visibleHeight = window.viewport.height - reservedLines

  # Get visual selection range if active
  let (hasSelection, selStart, selEnd) = e.getVisualSelection(window.active)

  var
    screenY = 0
    lineIndex = window.viewport.topLine

  while screenY < visibleHeight and lineIndex < lineCount:
    if e.state.lineWrap:
      e.renderWindowLineWrapped(
        buffer, window, lineNumOffset, hasSelection, selStart, selEnd, screenY,
        lineIndex, visibleHeight,
      )
    else:
      e.renderWindowLineNoWrap(
        buffer, window, lineNumOffset, hasSelection, selStart, selEnd, screenY,
        lineIndex,
      )
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
    e.windowManager.resizeWindows(
      e.viewport.width, e.viewport.height, oldWidth, oldHeight, e.state.multiStatusLine
    )

  # Sync active window's cursor with state cursor
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    # Update window cursor from editor state
    e.windowManager.windows[e.windowManager.activeWindowIndex].cursor = e.state.cursor

  # Find the maximum bottom Y coordinate (to determine bottom windows)
  let maxBottomY = findMaxBottomY(e.windowManager.windows)

  # Render all split windows
  for i, window in e.windowManager.windows:
    # Calculate line number offset dynamically based on buffer size
    let lineNumOffset = calculateLineNumOffset(window.buffer)

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

proc renderSingleView(e: Editor, buffer: var Buffer) =
  ## Render single buffer view (no split windows)
  # Sync viewport with motion controller (both directions)
  e.executer.motionController.viewportManager.viewport.width = e.viewport.width
  e.executer.motionController.viewportManager.viewport.height = e.viewport.height
  e.viewport = e.executer.motionController.viewportManager.viewport

  let
    reservedLines = e.calculateReservedLines(isBottomWindow = true)
    lineNumOffset = calculateLineNumOffset(e.textBuffer)
    textAreaWidth = max(0, buffer.area.width - lineNumOffset - LineNumberPadding)
    textArea = Rect(
      x: buffer.area.x + lineNumOffset,
      y: buffer.area.y,
      width: max(0, buffer.area.width - lineNumOffset),
      height: max(0, buffer.area.height - reservedLines),
    )

  discard e.renderLineNumbers(buffer, textAreaWidth)
  e.renderTextBuffer(buffer, textArea)

  # Calculate and set cursor position
  e.state.screenCursor = e.calculateWindowCursor(
    e.textBuffer, e.viewport, e.state.cursor, lineNumOffset, reservedLines
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
  else:
    if e.state.statusMessage.len > 0:
      buffer.setString(buffer.area.x, commandLineY, e.state.statusMessage, commandStyle)

proc render*(e: Editor, buffer: var Buffer) =
  ## Main render procedure - orchestrates the rendering of all editor components
  # Early return if buffer area is too small
  if buffer.area.width <= 0 or buffer.area.height <= 0:
    return

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
    e.renderSingleView(buffer)

  # Render bottom lines (status and command lines)
  e.renderBottomLines(buffer)
