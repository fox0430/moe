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

import std/strutils

import pkg/[celina, results]

import buffer, cursor, types, commands

type Editor* = ref object
  textBuffer*: TextBuffer
  state*: EditorState
  viewport*: ViewPort
  executer*: CommandExecutor

proc newEditor*(): Editor =
  result = Editor(
    textBuffer: newTextBuffer(),
    state: EditorState(cursor: CursorPosition(x: 0, y: 0)),
    viewport: ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24),
  )

  result.executer = newCommandExecutor(result.textBuffer, result.state, result.viewport)

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

  return ok(())

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

    # Clear the entire line first, then set content
    for x in 0 ..< area.width:
      buffer[area.x + x, area.y + y] = cell(" ", normalStyle)

    # Set the actual line content
    if displayLine.len > 0:
      buffer.setString(area.x, area.y + y, displayLine, normalStyle)

  # Clear remaining lines to prevent artifacts
  for y in visibleLines ..< area.height:
    for x in 0 ..< area.width:
      buffer[area.x + x, area.y + y] = cell(" ", normalStyle)

proc setCursorPosition*(e: Editor, lineNumOffset: int) =
  ## Calculate the cursor screen position from buffer's logical position
  let
    cursorLine = e.textBuffer.cursor.line
    cursorColumn = e.textBuffer.cursor.column

  # Only set screen cursor if the buffer cursor is within visible viewport
  if cursorLine >= e.viewport.topLine and
      cursorLine < e.viewport.topLine + e.viewport.height - 1: # -1 for status line
    let
      screenY = cursorLine - e.viewport.topLine
      screenX = lineNumOffset + max(0, cursorColumn - e.viewport.leftColumn)

    # Set the screen cursor position for display
    e.state.cursor.x = screenX
    e.state.cursor.y = screenY

proc render*(e: Editor, buffer: var Buffer) =
  # Update viewport size from buffer area (but preserve topLine and leftColumn)
  e.viewport.width = buffer.area.width
  e.viewport.height = buffer.area.height

  # Sync viewport with motion controller (both directions)
  e.executer.motionController.viewportManager.viewport.width = e.viewport.width
  e.executer.motionController.viewportManager.viewport.height = e.viewport.height
  e.viewport = e.executer.motionController.viewportManager.viewport

  let
    lineNumOffset = e.renderLineNumbers(buffer)

    textArea = Rect(
      x: buffer.area.x + lineNumOffset,
      y: buffer.area.y,
      width: buffer.area.width - lineNumOffset,
      height: buffer.area.height - 1,
    )

  e.renderTextBuffer(buffer, textArea)
  e.setCursorPosition(lineNumOffset)
