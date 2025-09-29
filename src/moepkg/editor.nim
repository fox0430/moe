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

type
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
      showLineCount: true,
      showLinePercentage: true,
      showEncoding: true,
      needsFullRedraw: true, # Initial render needs full draw
      viewportReservedLines: 2, # Default for single window mode with status line
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

proc renderLineNumbers(e: Editor, buffer: var Buffer): int =
  ## Render line numbers and return max width of the line number text.
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

  let visibleLineNums = min(buffer.area.height - 1, lineLen - e.viewport.topLine)

  # Render line numbers for visible lines
  for y in 0 ..< visibleLineNums:
    let
      lineNum = e.viewport.topLine + y
      lineNumStr = align($(lineNum + 1), maxLineNumWidth - 1) & " "

    let style =
      if lineNum == e.textBuffer.cursor.line: currentLineStyle else: lineNumStyle

    buffer.setString(buffer.area.x, buffer.area.y + y, lineNumStr, style)

  # Clear remaining line number area to prevent artifacts
  for y in visibleLineNums ..< buffer.area.height - 1:
    let emptyLineNumStr = spaces(maxLineNumWidth)
    buffer.setString(buffer.area.x, buffer.area.y + y, emptyLineNumStr, lineNumStyle)

  return maxLineNumWidth

proc renderTextBuffer(e: Editor, buffer: var Buffer, area: Rect) =
  let
    lineCount = e.textBuffer.len
    visibleLines = min(area.height, lineCount - e.viewport.topLine)

  # Default background
  let normalStyle =
    Style(fg: ColorValue(kind: Default), bg: ColorValue(kind: Default), modifiers: {})

  # Render actual file content
  for y in 0 ..< visibleLines:
    let
      lineIndex = e.viewport.topLine + y
      line = e.textBuffer.getLine(lineIndex)

    let displayLine =
      if e.viewport.leftColumn < line.len:
        line[e.viewport.leftColumn ..^ 1]
      else:
        ""

    # Set the actual line content (no need to clear as buffer is already cleared)
    if displayLine.len > 0:
      buffer.setString(area.x, area.y + y, displayLine, normalStyle)

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
    isLastWindow: bool,
) =
  ## Render a single window with line numbers
  let
    lineCount = window.buffer.len
    # Only the last window needs to reserve space for status line
    reservedLines = if isLastWindow and e.state.showStatusLine: 2 else: 0
    visibleHeight = window.viewport.height - reservedLines
    visibleLines = min(visibleHeight, lineCount - window.viewport.topLine)

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

  # Render line numbers and text content for this window
  for y in 0 ..< visibleLines:
    let
      lineIndex = window.viewport.topLine + y
      screenY = window.viewport.y + y

    # Skip if outside window bounds
    if screenY >= window.viewport.y + window.viewport.height:
      break

    # Render line number
    let
      lineNumStr = align($(lineIndex + 1), lineNumOffset - 1) & " "
      lineNumScreenX = window.viewport.x
      isCurrentLine = (lineIndex == window.buffer.cursor.line and window.active)
      lineStyle = if isCurrentLine: currentLineStyle else: lineNumStyle

    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, screenY, lineNumStr, lineStyle)

    # Render text content
    let
      line = window.buffer.getLine(lineIndex)
      displayLine =
        if window.viewport.leftColumn < line.len:
          line[window.viewport.leftColumn ..^ 1]
        else:
          ""
      textScreenX = window.viewport.x + lineNumOffset

    if displayLine.len > 0 and textScreenX < buffer.area.width:
      let maxWidth = min(displayLine.len, window.viewport.width - lineNumOffset)
      if maxWidth > 0:
        buffer.setString(textScreenX, screenY, displayLine[0 ..< maxWidth], normalStyle)

proc render*(e: Editor, buffer: var Buffer) =
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
    if wasResized and oldWidth > 0 and oldHeight > 0:
      e.windowManager.resizeWindows(e.viewport.width, e.viewport.height, oldWidth, oldHeight)
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

      e.renderWindow(buffer, window, lineNumOffset, isBottomWindow)

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
            # Calculate separator height (exclude status line space for bottom windows)
            let sepHeight =
              if isBottomWindow and e.state.showStatusLine:
                window.viewport.height - 2 # Exclude status line and command line
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
      lineNumOffset = e.renderLineNumbers(buffer)
      reservedLines = if e.state.showStatusLine: 2 else: 1
      textArea = Rect(
        x: buffer.area.x + lineNumOffset,
        y: buffer.area.y,
        width: buffer.area.width - lineNumOffset,
        height: buffer.area.height - reservedLines,
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
