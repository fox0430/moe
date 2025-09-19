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

import buffer, cursor, types

type
  # Motion command with count
  MotionCommand* = object
    motion*: Motion
    count*: int

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

proc parseMotion*(key: char, repeatCount: int = 0): Option[MotionCommand] =
  ## Parse a single character into a motion command
  let count = if repeatCount <= 0: 1 else: repeatCount

  case key
  of 'h':
    return some(MotionCommand(motion: Motion.Left, count: count))
  of 'l':
    return some(MotionCommand(motion: Motion.Right, count: count))
  of 'j':
    return some(MotionCommand(motion: Motion.Down, count: count))
  of 'k':
    return some(MotionCommand(motion: Motion.Up, count: count))
  else:
    return none(MotionCommand)

proc newMotionExecutor*(buffer: buffer.TextBuffer): MotionExecutor =
  MotionExecutor(buffer: buffer)

proc calculateNewPosition*(
    e: MotionExecutor,
    currentPos: CursorPosition,
    cmd: MotionCommand,
    viewportHeight: int = 24,
): CursorPosition =
  ## Calculate new cursor position after motion, without modifying state
  result = currentPos

  case cmd.motion
  of Motion.Left:
    # Ensure we don't access beyond buffer bounds
    if currentPos.y >= 0 and currentPos.y < e.buffer.len:
      let line = e.buffer.getLine(currentPos.y)
      var newCol = currentPos.x
      for _ in 0 ..< cmd.count:
        if newCol > 0:
          newCol -= 1
          # Handle UTF-8 properly
          while newCol > 0 and ord(line[newCol]) >= 0x80 and ord(line[newCol]) < 0xC0:
            newCol -= 1
      result.x = max(0, newCol)
  of Motion.Right:
    # Ensure we don't access beyond buffer bounds
    if currentPos.y >= 0 and currentPos.y < e.buffer.len:
      let line = e.buffer.getLine(currentPos.y)
      var newCol = currentPos.x
      for _ in 0 ..< cmd.count:
        if newCol < line.len:
          # Move forward by one character (handling UTF-8)
          if ord(line[newCol]) < 0x80:
            newCol += 1
          elif ord(line[newCol]) < 0xE0:
            newCol += 2
          elif ord(line[newCol]) < 0xF0:
            newCol += 3
          else:
            newCol += 4
      result.x = newCol
  of Motion.Up:
    result.y = max(0, currentPos.y - cmd.count)
  of Motion.Down:
    if e.buffer.len > 0:
      # Don't allow movement beyond last line of file
      result.y = min(e.buffer.len - 1, currentPos.y + cmd.count)
    else:
      result.y = 0
  of Motion.PageUp:
    # Move up by viewport height lines (minus 1 for status line)
    let pageSize = max(1, viewportHeight - 1) * cmd.count
    result.y = max(0, currentPos.y - pageSize)
  of Motion.PageDown:
    # Move down by viewport height lines (minus 1 for status line)
    let pageSize = max(1, viewportHeight - 1) * cmd.count
    if e.buffer.len > 0:
      result.y = min(e.buffer.len - 1, currentPos.y + pageSize)
    else:
      result.y = 0

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

proc executeMotion*(controller: MotionController, cmd: MotionCommand): bool =
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

  return true

proc executeMotionKey*(
    controller: MotionController, key: char, repeatCount: int = 0
): bool =
  ## Convenience method to execute motion from a key press
  let cmd = parseMotion(key, repeatCount)
  if cmd.isSome:
    return controller.executeMotion(cmd.get())
  return false
