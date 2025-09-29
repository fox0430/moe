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
  commandconfig, statusline
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

proc buffer*(e: Editor): TextBuffer =
  e.textBuffer

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
    ),
    viewport: ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24),
    commandRegistry: cmdRegistry,
    keyBindingRegistry: keyRegistry,
    commandLineParser: cmdLineParser,
    commandConfig: cmdConfig,
    handlerManager: nil, # Will be set after executer is created
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

proc render*(e: Editor, buffer: var Buffer) =
  # Always clear the entire buffer to prevent artifacts
  # TODO: Clear when resize
  let clearStyle = Style(
    fg: ColorValue(kind: Default),
    bg: ColorValue(kind: Default),
    modifiers: {}
  )

  for y in 0..<buffer.area.height:
    for x in 0..<buffer.area.width:
      buffer[x, y] = cell(" ", clearStyle)

  # Reset the full redraw flag if it was set
  if e.state.needsFullRedraw:
    e.state.needsFullRedraw = false

  # Update viewport size from buffer area (but preserve topLine and leftColumn)
  e.viewport.width = buffer.area.width
  e.viewport.height = buffer.area.height

  # Sync viewport with motion controller (both directions)
  e.executer.motionController.viewportManager.viewport.width = e.viewport.width
  e.executer.motionController.viewportManager.viewport.height = e.viewport.height
  e.viewport = e.executer.motionController.viewportManager.viewport

  let
    lineNumOffset = e.renderLineNumbers(buffer)

    # Calculate text area height based on status line visibility
    reservedLines = if e.state.showStatusLine: 2 else: 1
      # Status line + command line or just command line
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

  # Render status line using the dedicated statusline module
  e.state.renderStatusLine(e.textBuffer, buffer, statusLineY)

  # Handle command line (bottom line)
  if e.state.mode == EditorMode.Command:
    # Show command text in command line
    buffer.setString(buffer.area.x, commandLineY, e.state.commandText, commandStyle)
    # Set cursor at the end of command text
    e.state.cursor.x = e.state.commandText.len
    e.state.cursor.y = buffer.area.height - 1
  else:
    # Check if there's a status message to display in command line
    if e.state.statusMessage.len > 0:
      buffer.setString(buffer.area.x, commandLineY, e.state.statusMessage, commandStyle)
      # Clear status message after displaying
      e.state.statusMessage = ""
