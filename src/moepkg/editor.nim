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

import std/[strutils, strformat, options, tables]

import pkg/[celina, results]

import
  buffer, cursor, types, commands, keybindings, commandregistry, modes, commandline,
  commandconfig, statusline, windowmanager
import command_handlers/handler_manager

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

proc closeWindow*(e: Editor): bool =
  ## Close the active window
  ## Returns true if editor should quit (last window closed)

  let shouldQuit = e.windowManager.closeWindow()

  if shouldQuit:
    return true

  # Sync to the new active window
  e.syncActiveWindow()

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
  let bufferResult = e.windowManager.vsplit(e.textBuffer, e.viewport, filename)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer
  e.state.needsFullRedraw = true

  ok(())

proc hsplit*(e: Editor, filename: Option[string] = none(string)): Result[(), string] =
  ## Create a horizontal split window (top and bottom)
  let bufferResult = e.windowManager.hsplit(e.textBuffer, e.viewport, filename)
  if bufferResult.isErr:
    return err(bufferResult.error)

  let newBuffer = bufferResult.get
  e.executer.buffer = newBuffer
  e.executer.motionController.executor.buffer = newBuffer
  e.state.needsFullRedraw = true

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
      cursor: CursorPosition(x: 0, y: 0),
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

  # Reset both cursor positions to file start
  e.state.cursor = CursorPosition(x: 0, y: 0)
  e.textBuffer.cursor = BufferPosition(line: 0, column: 0)

  # Reset viewport to start
  e.viewport.topLine = 0
  e.viewport.leftColumn = 0

  ok(())

proc renderLineNumbers(e: Editor, buffer: var Buffer, textAreaWidth: int): int =
  ## Render line numbers and return max width of the line number text.

  # Guard against invalid text area width
  if textAreaWidth <= 0:
    return 0

  let
    lineLen = e.textBuffer.len
    maxLineNumWidth = len($lineLen) + 1

  let lineNumStyle = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Default),
    modifiers: {},
  )

  let currentLineStyle = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
    bg: ColorValue(kind: Default),
    modifiers: {StyleModifier.Bold},
  )

  let reservedLines = if e.state.showStatusLine: 2 else: 1
  var
    screenY = 0
    lineIndex = e.viewport.topLine

  while screenY < buffer.area.height - reservedLines and lineIndex < lineLen:
    # Render line numbers with wrapping support
    let
      line = e.textBuffer.getLine(lineIndex)
      isCurrentLine = lineIndex == e.textBuffer.cursor.line
      lineStyle = if isCurrentLine: currentLineStyle else: lineNumStyle

    if e.state.lineWrap and line.len > textAreaWidth:
      let
        # This line will wrap - calculate number of screen lines needed
        numWraps = (line.len + textAreaWidth - 1) div textAreaWidth
        # Render line number for first wrap
        lineNumStr = align($(lineIndex + 1), maxLineNumWidth - 1) & " "

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
      let lineNumStr = align($(lineIndex + 1), maxLineNumWidth - 1) & " "
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
  let
    lineCount = e.textBuffer.len
    normalStyle =
      Style(fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {})

  var
    screenY = 0
    lineIndex = e.viewport.topLine

  while screenY < area.height and lineIndex < lineCount:
    # Render file content with optional line wrapping
    let line = e.textBuffer.getLine(lineIndex)

    if e.state.lineWrap:
      # Line wrapping enabled - split long lines across multiple screen lines
      let
        maxWidth = area.width
        lineLen = line.len

      if lineLen == 0:
        # Empty line
        inc screenY
        inc lineIndex
        continue

      var startCol = 0
      while startCol < lineLen and screenY < area.height:
        let
          endCol = min(startCol + maxWidth, lineLen)
          displayLine = line[startCol ..< endCol]

        if displayLine.len > 0:
          buffer.setString(area.x, area.y + screenY, displayLine, normalStyle)

        inc screenY
        startCol += maxWidth
    else:
      # No line wrapping - use horizontal scrolling
      let displayLine =
        if e.viewport.leftColumn < line.len:
          line[e.viewport.leftColumn ..^ 1]
        else:
          ""

      if displayLine.len > 0:
        buffer.setString(area.x, area.y + screenY, displayLine, normalStyle)

      inc screenY

    inc lineIndex

proc setCursorPosition*(e: Editor, lineNumOffset: int) =
  ## Calculate the cursor screen position from buffer's logical position
  let
    cursorLine = e.textBuffer.cursor.line
    cursorColumn = e.textBuffer.cursor.column

  # Only set screen cursor if the buffer cursor is within visible viewport
  let reservedLines = if e.state.showStatusLine: 2 else: 1
    # Status line + command line or just command line
  if cursorLine >= e.viewport.topLine and
      cursorLine < e.viewport.topLine + e.viewport.height - reservedLines:
    let
      screenY = cursorLine - e.viewport.topLine
      screenX = lineNumOffset + max(0, cursorColumn - e.viewport.leftColumn)

    # Set the screen cursor position for display
    e.state.cursor.x = screenX
    e.state.cursor.y = screenY

proc renderWindow(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    isBottomWindow: bool,
    isActiveWindow: bool,
) =
  ## Render a single window with line numbers
  let
    lineCount = window.buffer.len
    # Reserve space for status line based on mode:
    # - Multi-status line mode:
    #   - Bottom windows: reserve 2 lines (status line + command line)
    #   - Non-bottom windows: reserve 1 line (status line)
    # - Single-status line mode: reserve 2 lines only for bottom windows (status + command line)
    reservedLines =
      if e.state.showStatusLine:
        if e.state.multiStatusLine:
          if isBottomWindow:
            2 # Reserve for status line + command line
          else:
            1 # Reserve for window's own status line
        elif isBottomWindow:
          2 # Reserve for status + command line in single-status-line mode
        else:
          0
      else:
        if isBottomWindow:
          1 # Reserve for command line even without status line
        else:
          0
    visibleHeight = window.viewport.height - reservedLines

  let normalStyle =
    Style(fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {})

  let lineNumStyle = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
    bg: ColorValue(kind: Default),
    modifiers: {},
  )

  let currentLineStyle = Style(
    fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
    bg: ColorValue(kind: Default),
    modifiers: {StyleModifier.Bold},
  )

  var
    screenY = 0
    lineIndex = window.viewport.topLine

  while screenY < visibleHeight and lineIndex < lineCount:
    # Render line numbers and text content with optional line wrapping
    let
      actualScreenY = window.viewport.y + screenY
      line = window.buffer.getLine(lineIndex)

    # Skip if outside window bounds
    if actualScreenY >= window.viewport.y + window.viewport.height:
      break

    if e.state.lineWrap:
      # Line wrapping enabled - split long lines across multiple screen lines
      let
        maxWidth = window.viewport.width - lineNumOffset
        lineLen = line.len
        isCurrentLine = (lineIndex == window.buffer.cursor.line and window.active)
        lineStyle = if isCurrentLine: currentLineStyle else: lineNumStyle
        lineNumScreenX = window.viewport.x

      if lineLen == 0:
        # Empty line - just render line number
        let lineNumStr = align($(lineIndex + 1), lineNumOffset - 1) & " "
        if lineNumScreenX + lineNumStr.len <= buffer.area.width:
          buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)
        inc screenY
        inc lineIndex
        continue

      var
        startCol = 0
        wrapLineCount = 0
      while startCol < lineLen and screenY < visibleHeight:
        let
          endCol = min(startCol + maxWidth, lineLen)
          displayLine = line[startCol ..< endCol]
          textScreenX = window.viewport.x + lineNumOffset
          currentActualScreenY = window.viewport.y + screenY

        # Render line number for first wrap, empty space for others
        if wrapLineCount == 0:
          let lineNumStr = align($(lineIndex + 1), lineNumOffset - 1) & " "
          if lineNumScreenX + lineNumStr.len <= buffer.area.width:
            buffer.setString(
              lineNumScreenX, currentActualScreenY, lineNumStr, lineStyle
            )
        else:
          if lineNumScreenX + lineNumOffset <= buffer.area.width:
            let emptyLineNumStr = spaces(lineNumOffset)
            buffer.setString(
              lineNumScreenX, currentActualScreenY, emptyLineNumStr, lineNumStyle
            )

        if displayLine.len > 0 and textScreenX < buffer.area.width:
          let displayWidth = min(displayLine.len, maxWidth)
          if displayWidth > 0:
            buffer.setString(
              textScreenX,
              currentActualScreenY,
              displayLine[0 ..< displayWidth],
              normalStyle,
            )

        inc screenY
        inc wrapLineCount
        startCol += maxWidth

        if screenY >= visibleHeight:
          break
    else:
      # No line wrapping - use horizontal scrolling
      let
        isCurrentLine = (lineIndex == window.buffer.cursor.line and window.active)
        lineStyle = if isCurrentLine: currentLineStyle else: lineNumStyle

      # Render line number
      let
        lineNumStr = align($(lineIndex + 1), lineNumOffset - 1) & " "
        lineNumScreenX = window.viewport.x

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
          buffer.setString(
            textScreenX, actualScreenY, displayLine[0 ..< maxWidth], normalStyle
          )

      inc screenY

    inc lineIndex

proc render*(e: Editor, buffer: var Buffer) =
  # Early return if buffer area is too small
  if buffer.area.width <= 0 or buffer.area.height <= 0:
    return

  # Always clear the entire buffer to prevent artifacts
  let clearStyle =
    Style(fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {})

  for y in 0 ..< buffer.area.height:
    for x in 0 ..< buffer.area.width:
      buffer[x, y] = cell(" ", clearStyle)

  # Reset the full redraw flag if it was set
  if e.state.needsFullRedraw:
    e.state.needsFullRedraw = false

  # Update viewport size from buffer area
  let oldWidth = e.viewport.width
  let oldHeight = e.viewport.height
  e.viewport.width = buffer.area.width
  e.viewport.height = buffer.area.height

  # Check if terminal was resized
  let wasResized = (oldWidth != e.viewport.width) or (oldHeight != e.viewport.height)

  # Check if we have split windows
  if e.windowManager.windows.len > 0:
    # If terminal was resized, rebuild window layout
    if wasResized and oldWidth > 0 and oldHeight > 0 and e.viewport.width > 0 and
        e.viewport.height > 0:
      e.windowManager.resizeWindows(
        e.viewport.width, e.viewport.height, oldWidth, oldHeight
      )
    # Sync active window's cursor with buffer cursor
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
      # Update window cursor from buffer
      e.windowManager.windows[e.windowManager.activeWindowIndex].cursor =
        activeWindow.buffer.cursor

    # Find the maximum bottom Y coordinate (to determine bottom windows)
    var maxBottomY = 0
    for window in e.windowManager.windows:
      let bottomY = window.viewport.y + window.viewport.height
      if bottomY > maxBottomY:
        maxBottomY = bottomY

    # Render all split windows
    for i, window in e.windowManager.windows:
      # Note: Don't override viewport dimensions here as they're set by split logic

      # Render line numbers for this window (simplified for split view)
      let lineNumOffset = 4 # Fixed width for now

      # Determine if this is a bottom window (needs status line reservation)
      # A window is a bottom window if its bottom edge is at the maximum bottom Y
      let windowBottomY = window.viewport.y + window.viewport.height
      let isBottomWindow = (windowBottomY == maxBottomY)
      let isActiveWindow = (i == e.windowManager.activeWindowIndex)

      e.renderWindow(buffer, window, lineNumOffset, isBottomWindow, isActiveWindow)

      # Render per-window status line if multi-status line mode is enabled
      if e.state.showStatusLine and e.state.multiStatusLine:
        # For bottom windows, place status line above command line (height - 2)
        # For non-bottom windows, place at window bottom (height - 1)
        let statusLineY =
          if isBottomWindow:
            window.viewport.y + window.viewport.height - 2
          else:
            window.viewport.y + window.viewport.height - 1
        e.state.renderWindowStatusLine(
          window.buffer, buffer, statusLineY, window.viewport.x, window.viewport.width,
          isActiveWindow,
        )

      # Draw separator between windows (except for last window)
      if i < e.windowManager.windows.len - 1:
        let sepStyle = Style(
          fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
          bg: ColorValue(kind: Default),
          modifiers: {},
        )
        let nextWindow = e.windowManager.windows[i + 1]

        # Check if windows are side by side (vertical split) or top/bottom (horizontal split)
        if window.viewport.y == nextWindow.viewport.y:
          # Vertical split - draw vertical separator at window boundary
          let sepX = window.viewport.x + window.viewport.width
          if sepX < buffer.area.width:
            # Calculate separator height (exclude status line and command line)
            let sepHeight =
              if e.state.showStatusLine:
                if e.state.multiStatusLine:
                  if isBottomWindow:
                    window.viewport.height - 2 # Exclude status line and command line
                  else:
                    window.viewport.height - 1 # Exclude per-window status line
                elif isBottomWindow:
                  window.viewport.height - 2 # Exclude status line and command line
                else:
                  window.viewport.height
              else:
                if isBottomWindow:
                  window.viewport.height - 1 # Exclude command line
                else:
                  window.viewport.height

            # Draw separator for the content height of this window
            for y in window.viewport.y ..< (window.viewport.y + sepHeight):
              if y < buffer.area.height:
                buffer.setString(sepX, y, "│", sepStyle)
        else:
          # Horizontal split - draw horizontal separator at window boundary
          let sepY = window.viewport.y + window.viewport.height
          if sepY < buffer.area.height:
            # Draw separator for the width of this window
            for x in window.viewport.x ..< (window.viewport.x + window.viewport.width):
              if x < buffer.area.width:
                buffer.setString(x, sepY, "─", sepStyle)

    # Set cursor to active window position
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
      let screenY =
        activeWindow.viewport.y +
        (activeWindow.cursor.line - activeWindow.viewport.topLine)
      let screenX =
        activeWindow.viewport.x + 4 +
        max(0, activeWindow.cursor.column - activeWindow.viewport.leftColumn)
      e.state.cursor.x = screenX
      e.state.cursor.y = screenY
  else:
    # No split windows - render single buffer as before
    # Sync viewport with motion controller (both directions)
    e.executer.motionController.viewportManager.viewport.width = e.viewport.width
    e.executer.motionController.viewportManager.viewport.height = e.viewport.height
    e.viewport = e.executer.motionController.viewportManager.viewport

    let
      reservedLines = if e.state.showStatusLine: 2 else: 1
      textAreaWidth = max(0, buffer.area.width - (len($e.textBuffer.len) + 2))
      lineNumOffset = e.renderLineNumbers(buffer, textAreaWidth)
      textArea = Rect(
        x: buffer.area.x + lineNumOffset,
        y: buffer.area.y,
        width: max(0, buffer.area.width - lineNumOffset),
        height: max(0, buffer.area.height - reservedLines),
      )

    e.renderTextBuffer(buffer, textArea)
    e.setCursorPosition(lineNumOffset)

  # Calculate line positions based on status line visibility
  let
    statusLineY = buffer.area.y + buffer.area.height - 2
    commandLineY = buffer.area.y + buffer.area.height - 1
    commandStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.White),
      bg: ColorValue(kind: Default),
      modifiers: {StyleModifier.Bold},
    )

  # Render status line using active buffer
  # - Single window mode: always render status line at bottom
  # - Multi-window mode: only render if multiStatusLine is disabled (single status line mode)
  if e.windowManager.windows.len == 0 or not e.state.multiStatusLine:
    e.state.renderStatusLine(e.activeBuffer(), buffer, statusLineY)

  # Handle command line
  if e.state.mode == EditorMode.Command:
    buffer.setString(buffer.area.x, commandLineY, e.state.commandText, commandStyle)
    e.state.cursor.x = e.state.commandText.len
    e.state.cursor.y = buffer.area.height - 1
  else:
    if e.state.statusMessage.len > 0:
      buffer.setString(buffer.area.x, commandLineY, e.state.statusMessage, commandStyle)
      e.state.statusMessage = ""
