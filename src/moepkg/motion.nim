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

import std/[options, unicode]

import pkg/results

import buffer, cursor, types, unicode_utils, logger

type
  # Motion command with count
  MotionCommand* = object
    motion*: Motion
    count*: int
    targetChar*: string # For find/till commands

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
  logDebug(
    "motion",
    "moveLeft: currentPos=(" & $currentPos.y & "," & $currentPos.x & ") count=" & $count,
  )

  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    # Move left by character count, not byte count
    let newX = max(0, currentPos.x - count)
    logDebug("motion", "moveLeft: newX=" & $newX)
    result.x = newX

proc moveRight(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  result = currentPos
  logDebug(
    "motion",
    "moveRight: currentPos=(" & $currentPos.y & "," & $currentPos.x & ") count=" & $count &
      " bufLen=" & $e.buffer.len,
  )

  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    let lineCharLen = line.charLen
    let lineByteLen = line.len
    logDebug(
      "motion",
      "moveRight: line='" & line & "' charLen=" & $lineCharLen & " byteLen=" &
        $lineByteLen,
    )

    # Move right by character count, not byte count
    # In normal mode, don't allow cursor to go beyond the last character
    let maxPos = max(0, lineCharLen - 1)
    let newX = min(currentPos.x + count, maxPos)
    logDebug(
      "motion",
      "moveRight: currentPos.x=" & $currentPos.x & " newX=" & $newX & " maxPos=" &
        $maxPos,
    )
    result.x = newX
  else:
    logDebug("motion", "moveRight: buffer bounds check failed")

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
    let lineCharLen = line.charLen
    # In normal mode, cursor should be on the last character, not after it
    result.x = max(0, lineCharLen - 1)

proc moveFirstLine(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  result = currentPos
  result.y = 0
  result.x = 0

proc moveLastLine(
    e: MotionExecutor, currentPos: CursorPosition, count: int = 1
): CursorPosition =
  result = currentPos
  if count == 1:
    # G without number: go to last line
    if e.buffer.len > 0:
      result.y = e.buffer.len - 1
      result.x = 0
  else:
    # 123G: go to specific line number (count), but clamp to buffer bounds
    if e.buffer.len > 0:
      result.y = min(count - 1, e.buffer.len - 1) # Convert to 0-based and clamp
      result.x = 0
    else:
      result.y = 0
      result.x = 0

proc findChar(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: string, count: int
): CursorPosition =
  ## Find next occurrence of character on current line
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    let lineCharLen = line.charLen
    var found = 0
    # Search character by character, not byte by byte
    for charIdx in currentPos.x + 1 ..< lineCharLen:
      # Get the character at this character position
      let (rune, _) = getCharAtPos(line, charIdx)
      if toUTF8(rune) == targetChar:
        found.inc
        if found == count:
          result.x = charIdx
          break

proc findCharBackward(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: string, count: int
): CursorPosition =
  ## Find previous occurrence of character on current line
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    var found = 0
    # Search character by character backward, not byte by byte
    for charIdx in countdown(currentPos.x - 1, 0):
      # Get the character at this character position
      let (rune, _) = getCharAtPos(line, charIdx)
      if toUTF8(rune) == targetChar:
        found.inc
        if found == count:
          result.x = charIdx
          break

proc tillChar(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: string, count: int
): CursorPosition =
  ## Move till (before) next occurrence of character
  result = e.findChar(currentPos, targetChar, count)
  if result.x > currentPos.x:
    result.x = result.x - 1

proc tillCharBackward(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: string, count: int
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
    e.moveLastLine(currentPos, cmd.count)
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
    let line = buf.getLine(result.y)
    let lineCharLen = line.charLen # Use character count, not byte count
    # Normal mode keeps cursor on last character, not after it
    if lineCharLen == 0:
      result.x = 0
    elif result.x >= lineCharLen:
      # Clamp to last valid character position
      result.x = max(0, lineCharLen - 1)
    elif result.x < 0:
      result.x = 0

proc applyCursorPosition*(mgr: CursorManager, pos: BufferPosition) =
  ## Update the actual cursor position in state
  mgr.state.cursor = pos

proc newViewportManager*(viewport: ViewPort): ViewportManager =
  ViewportManager(viewport: viewport)

proc calculateScreenLine(
    buffer: buffer.TextBuffer,
    startLine: int,
    targetLine: int,
    lineWrap: bool,
    maxWidth: int,
): int =
  ## Calculate screen line position of targetLine starting from startLine
  ## Returns the number of screen lines from startLine to targetLine
  result = 0
  for lineIdx in startLine ..< targetLine:
    if lineIdx >= 0 and lineIdx < buffer.len:
      if lineWrap:
        let line = buffer.getLine(lineIdx)
        let lineCharLen = line.charLen
        if lineCharLen == 0:
          result += 1
        else:
          let wrappedLines = ((lineCharLen - 1) div maxWidth) + 1
          result += wrappedLines
      else:
        result += 1

proc updateViewport*(
    mgr: ViewportManager,
    cursorPos: CursorPosition,
    lineCount: int,
    showStatusLine: bool = true,
    reservedLines: int = -1, # -1 means auto-calculate from showStatusLine
    lineWrap: bool = false,
    buffer: buffer.TextBuffer = nil,
    lineNumOffset: int = 0,
) =
  ## Update viewport to keep cursor visible with 1-line scrolling

  # Ensure we have valid data
  if lineCount <= 0:
    mgr.viewport.topLine = 0
    return

  let
    # Ensure cursor position is within valid bounds
    clampedCursorY = max(0, min(cursorPos.y, lineCount - 1))
    clampedCursorX = max(0, cursorPos.x)

    # Calculate reserved lines based on status line visibility or explicit parameter
    actualReservedLines =
      if reservedLines >= 0:
        reservedLines
      else:
        (if showStatusLine: 2 else: 1)

  # Vertical scrolling - handle line wrap mode differently
  if lineWrap and not buffer.isNil:
    # Line wrap mode: calculate screen positions
    let maxWidth = max(1, mgr.viewport.width - lineNumOffset)

    # Calculate cursor's screen line position relative to topLine
    var cursorScreenLine = calculateScreenLine(
      buffer, mgr.viewport.topLine, clampedCursorY, lineWrap, maxWidth
    )

    # Add offset within the cursor's wrapped line
    if clampedCursorY >= 0 and clampedCursorY < buffer.len:
      let wrapLineIndex = clampedCursorX div maxWidth
      cursorScreenLine += wrapLineIndex

    let visibleHeight = mgr.viewport.height - actualReservedLines

    # Scroll up if cursor is above viewport
    if cursorScreenLine < 0 or clampedCursorY < mgr.viewport.topLine:
      mgr.viewport.topLine = clampedCursorY
    # Scroll down if cursor is below viewport
    elif cursorScreenLine >= visibleHeight:
      # If cursor is far below viewport (e.g., G command), jump directly
      if cursorScreenLine >= visibleHeight + 10:
        # Calculate a reasonable topLine to place cursor near bottom
        # Simple heuristic: start from a few lines above cursor
        mgr.viewport.topLine = max(0, clampedCursorY - (visibleHeight div 2))
      else:
        # Smooth scroll: move topLine down by one logical line
        if mgr.viewport.topLine < clampedCursorY:
          mgr.viewport.topLine += 1
  else:
    # No line wrap: simple logic
    if clampedCursorY < mgr.viewport.topLine:
      # Cursor moved above viewport - scroll up
      mgr.viewport.topLine = clampedCursorY
    elif clampedCursorY >=
        mgr.viewport.topLine + mgr.viewport.height - actualReservedLines:
      # Cursor moved below viewport - scroll down (account for status and command lines)
      let
        newTopLine = clampedCursorY - mgr.viewport.height + actualReservedLines + 1
        maxTopLine = max(0, lineCount - mgr.viewport.height + actualReservedLines)
      mgr.viewport.topLine = max(0, min(maxTopLine, newTopLine))

  # Horizontal scrolling - keep cursor visible (disabled in wrap mode)
  if not lineWrap:
    if clampedCursorX < mgr.viewport.leftColumn:
      mgr.viewport.leftColumn = clampedCursorX
    elif clampedCursorX >= mgr.viewport.leftColumn + mgr.viewport.width:
      mgr.viewport.leftColumn = clampedCursorX - mgr.viewport.width + 1

proc newMotionController*(
    buf: buffer.TextBuffer, state: EditorState, viewport: ViewPort
): MotionController =
  MotionController(
    executor: newMotionExecutor(buf),
    viewportManager: viewport.newViewportManager,
    cursorManager: newCursorManager(state),
  )

proc executeMotion*(
    controller: MotionController, cmd: MotionCommand, currentCursorPos: BufferPosition
): Result[BufferPosition, string] =
  ## Execute a motion command - main entry point
  ## Returns the new cursor position
  # Convert to CursorPosition for internal calculations
  let currentPos = CursorPosition(x: currentCursorPos.column, y: currentCursorPos.line)

  logDebug(
    "motion",
    "Executing " & $cmd.motion & " from (" & $currentPos.y & "," & $currentPos.x & ")",
  )

  var newPos = controller.executor.calculateNewPosition(
    currentPos, cmd, controller.viewportManager.viewport.height
  )

  logDebug("motion", "Calculated newPos: (" & $newPos.y & "," & $newPos.x & ")")

  # Clamp to valid buffer bounds
  newPos = controller.cursorManager.clampPosition(newPos, controller.executor.buffer)

  logDebug("motion", "After clamp: (" & $newPos.y & "," & $newPos.x & ")")

  # Update viewport to follow cursor with line wrap support
  let
    lineCount = controller.executor.buffer.len
    lineWrap = controller.cursorManager.state.lineWrap
    # Calculate line number offset for viewport calculation (matches renderLineNumbers)
    lineNumOffset =
      if lineCount > 0:
        len($lineCount) + 1
      else:
        0

  controller.viewportManager.updateViewport(
    newPos, lineCount, controller.cursorManager.state.showStatusLine,
    controller.cursorManager.state.viewportReservedLines, lineWrap,
    controller.executor.buffer, lineNumOffset,
  )

  # Disable horizontal scrolling when line wrap is enabled
  if lineWrap:
    controller.viewportManager.viewport.leftColumn = 0

  # Store last motion for repeat
  controller.cursorManager.state.lastMotion = some(cmd.motion)

  # Return the new cursor position
  return ok(BufferPosition(line: newPos.y, column: newPos.x))
