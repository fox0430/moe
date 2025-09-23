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

## Command executor with text object support
##
## This module extends the command executor to handle text objects
## like iw, aw, i", a", i(, a(, etc.

import std/options

import pkg/results

import buffer, cursor, types

type
  # Motion command with count
  MotionCommand* = object
    motion*: Motion
    count*: int
    targetChar*: char # For find/till commands

  # Motion executor - handles only motion logic
  MotionExecutor* = ref object
    buffer*: buffer.TextBuffer

  # Viewport manager - handles viewport updates
  ViewportManager* = ref object
    viewport*: ViewPort

  # Cursor manager - handles cursor positioning and clamping
  CursorManager* = ref object
    state*: EditorState

  # Main motion controller - coordinates between components
  MotionController* = ref object
    executor*: MotionExecutor
    viewportManager*: ViewportManager
    cursorManager*: CursorManager

proc newMotionExecutor*(buffer: buffer.TextBuffer): MotionExecutor =
  MotionExecutor(buffer: buffer)

proc moveLeft(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    var newCol = currentPos.x
    for _ in 0 ..< count:
      if newCol > 0:
        newCol -= 1
        while newCol > 0 and ord(line[newCol]) >= 0x80 and ord(line[newCol]) < 0xC0:
          newCol -= 1
    result.x = max(0, newCol)

proc moveRight(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    var newCol = currentPos.x
    for _ in 0 ..< count:
      if newCol < line.len:
        if ord(line[newCol]) < 0x80:
          newCol += 1
        elif ord(line[newCol]) < 0xE0:
          newCol += 2
        elif ord(line[newCol]) < 0xF0:
          newCol += 3
        else:
          newCol += 4
    result.x = newCol

proc moveUp(e: MotionExecutor, currentPos: CursorPosition, count: int): CursorPosition =
  result = currentPos
  result.y = max(0, currentPos.y - count)

proc moveDown(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  result = currentPos
  if e.buffer.len > 0:
    result.y = min(e.buffer.len - 1, currentPos.y + count)
  else:
    result.y = 0

proc movePageUp(
    e: MotionExecutor, currentPos: CursorPosition, count: int, viewportHeight: int
): CursorPosition =
  result = currentPos
  let pageSize = max(1, viewportHeight - 1) * count
  result.y = max(0, currentPos.y - pageSize)

proc movePageDown(
    e: MotionExecutor, currentPos: CursorPosition, count: int, viewportHeight: int
): CursorPosition =
  result = currentPos
  let pageSize = max(1, viewportHeight - 1) * count
  if e.buffer.len > 0:
    result.y = min(e.buffer.len - 1, currentPos.y + pageSize)
  else:
    result.y = 0

proc moveHome(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  result = currentPos
  result.x = 0

proc moveEnd(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    result.x = line.len

proc moveFirstLine(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  result = currentPos
  result.y = 0
  result.x = 0

proc moveLastLine(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  result = currentPos
  if e.buffer.len > 0:
    result.y = e.buffer.len - 1
    result.x = 0

proc findChar(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: char, count: int
): CursorPosition =
  ## Find next occurrence of character on current line
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    var found = 0
    for i in currentPos.x + 1 ..< line.len:
      if line[i] == targetChar:
        found.inc
        if found == count:
          result.x = i
          break

proc findCharBackward(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: char, count: int
): CursorPosition =
  ## Find previous occurrence of character on current line
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    var found = 0
    for i in countdown(currentPos.x - 1, 0):
      if line[i] == targetChar:
        found.inc
        if found == count:
          result.x = i
          break

proc tillChar(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: char, count: int
): CursorPosition =
  ## Move till (before) next occurrence of character
  result = e.findChar(currentPos, targetChar, count)
  if result.x > currentPos.x:
    result.x = result.x - 1

proc tillCharBackward(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: char, count: int
): CursorPosition =
  ## Move till (after) previous occurrence of character
  result = e.findCharBackward(currentPos, targetChar, count)
  if result.x < currentPos.x:
    result.x = result.x + 1

proc calculateNewPosition*(
    e: MotionExecutor,
    currentPos: CursorPosition,
    cmd: MotionCommand,
    viewportHeight: int = 24,
): CursorPosition =
  ## Calculate new cursor position after motion, without modifying state
  case cmd.motion
  of Motion.Left:
    e.moveLeft(currentPos, cmd.count)
  of Motion.Right:
    e.moveRight(currentPos, cmd.count)
  of Motion.Up:
    e.moveUp(currentPos, cmd.count)
  of Motion.Down:
    e.moveDown(currentPos, cmd.count)
  of Motion.PageUp:
    e.movePageUp(currentPos, cmd.count, viewportHeight)
  of Motion.PageDown:
    e.movePageDown(currentPos, cmd.count, viewportHeight)
  of Motion.Home:
    e.moveHome(currentPos)
  of Motion.End:
    e.moveEnd(currentPos)
  of Motion.FirstLine:
    e.moveFirstLine(currentPos)
  of Motion.LastLine:
    e.moveLastLine(currentPos)
  of Motion.FindChar:
    e.findChar(currentPos, cmd.targetChar, cmd.count)
  of Motion.FindCharBackward:
    e.findCharBackward(currentPos, cmd.targetChar, cmd.count)
  of Motion.TillChar:
    e.tillChar(currentPos, cmd.targetChar, cmd.count)
  of Motion.TillCharBackward:
    e.tillCharBackward(currentPos, cmd.targetChar, cmd.count)

proc newCursorManager*(state: EditorState): CursorManager =
  CursorManager(state: state)

proc clampPosition*(
    mgr: CursorManager, pos: CursorPosition, buf: buffer.TextBuffer
): CursorPosition =
  ## Ensure cursor position is within valid bounds
  result = pos

  # Clamp line - don't allow cursor beyond last actual line
  if buf.len == 0:
    result.y = 0
    result.x = 0
    return

  # Vim behavior: cursor can't go beyond the last line with content
  if result.y >= buf.len:
    result.y = buf.len - 1
  elif result.y < 0:
    result.y = 0

  # Clamp column - ensure line index is valid before accessing
  if result.y >= 0 and result.y < buf.len:
    let lineLength = buf.getLine(result.y).len
    # Normal mode keeps cursor on last character
    if lineLength == 0:
      result.x = 0
    elif result.x >= lineLength:
      result.x = lineLength - 1
    elif result.x < 0:
      result.x = 0

proc applyCursorPosition*(mgr: CursorManager, pos: CursorPosition) =
  ## Update the actual cursor position in state
  mgr.state.cursor = pos

proc newViewportManager*(viewport: ViewPort): ViewportManager =
  ViewportManager(viewport: viewport)

proc updateViewport*(mgr: ViewportManager, cursorPos: CursorPosition, lineCount: int) =
  ## Update viewport to keep cursor visible with 1-line scrolling

  # Ensure we have valid data
  if lineCount <= 0:
    mgr.viewport.topLine = 0
    return

  # Vertical scrolling - always keep cursor visible
  if cursorPos.y < mgr.viewport.topLine:
    # Cursor moved above viewport - scroll up
    mgr.viewport.topLine = cursorPos.y
  elif cursorPos.y >= mgr.viewport.topLine + mgr.viewport.height - 1:
    # Cursor moved below viewport - scroll down (account for status line)
    let newTopLine = cursorPos.y - mgr.viewport.height + 2
    let maxTopLine = max(0, lineCount - mgr.viewport.height + 1)
    mgr.viewport.topLine = max(0, min(maxTopLine, newTopLine))

  # Horizontal scrolling - keep cursor visible
  if cursorPos.x < mgr.viewport.leftColumn:
    mgr.viewport.leftColumn = cursorPos.x
  elif cursorPos.x >= mgr.viewport.leftColumn + mgr.viewport.width:
    mgr.viewport.leftColumn = cursorPos.x - mgr.viewport.width + 1

proc newMotionController*(
    buf: buffer.TextBuffer, state: EditorState, viewport: ViewPort
): MotionController =
  MotionController(
    executor: newMotionExecutor(buf),
    viewportManager: viewport.newViewportManager,
    cursorManager: newCursorManager(state),
  )

proc executeMotion*(
    controller: MotionController, cmd: MotionCommand
): Result[(), string] =
  ## Execute a motion command - main entry point
  # Get current buffer position (logical position in file)
  let currentPos = CursorPosition(
    x: controller.executor.buffer.cursor.column,
    y: controller.executor.buffer.cursor.line,
  )
  var newPos = controller.executor.calculateNewPosition(
    currentPos, cmd, controller.viewportManager.viewport.height
  )

  # Clamp to valid buffer bounds
  newPos = controller.cursorManager.clampPosition(newPos, controller.executor.buffer)

  # Update buffer cursor (logical position)
  controller.executor.buffer.cursor = BufferPosition(line: newPos.y, column: newPos.x)

  # Update viewport to follow cursor
  let lineCount = controller.executor.buffer.len
  controller.viewportManager.updateViewport(newPos, lineCount)

  # Store last motion for repeat
  controller.cursorManager.state.lastMotion = some(cmd.motion)

  return Result[(), string].ok ()
