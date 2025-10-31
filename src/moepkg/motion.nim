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

import buffer, cursor, types, unicode_utils, logger, render_utils

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

proc moveFirstNonBlank(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  ## Move to the first non-whitespace character on the current line (^ command)
  result = currentPos
  result.x = 0

  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    let runes = line.toRunes()

    # Find first non-whitespace character
    for i, r in runes:
      if not isWhitespace(r):
        result.x = i
        break

proc moveLastNonBlank(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  ## Move to the last non-whitespace character on the current line (g_ command)
  result = currentPos
  result.x = 0

  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    let runes = line.toRunes()

    # Find last non-whitespace character by scanning backwards
    for i in countdown(runes.len - 1, 0):
      if not isWhitespace(runes[i]):
        result.x = i
        break

proc moveEnd(e: MotionExecutor, currentPos: CursorPosition): CursorPosition =
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let line = e.buffer.getLine(currentPos.y)
    let lineCharLen = line.charLen
    # In normal mode, cursor should be on the last character, not after it
    result.x = max(0, lineCharLen - 1)

proc moveNextLineFirstNonBlank(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to next line's first non-whitespace character (Enter/+ key in normal mode)
  ## This is like pressing j followed by ^
  result = currentPos

  # Move down by count lines
  if e.buffer.len > 0:
    result.y = min(e.buffer.len - 1, currentPos.y + count)
  else:
    result.y = 0

  # Move to first non-whitespace character on the new line
  result.x = 0
  if result.y >= 0 and result.y < e.buffer.len:
    let line = e.buffer.getLine(result.y)
    let runes = line.toRunes()
    # Find first non-whitespace character
    for i, r in runes:
      if not isWhitespace(r):
        result.x = i
        break

proc movePreviousLineFirstNonBlank(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to previous line's first non-whitespace character (- key in normal mode)
  ## This is like pressing k followed by ^
  result = currentPos

  # Move up by count lines
  result.y = max(0, currentPos.y - count)

  # Move to first non-whitespace character on the new line
  result.x = 0
  if result.y >= 0 and result.y < e.buffer.len:
    let line = e.buffer.getLine(result.y)
    let runes = line.toRunes()
    # Find first non-whitespace character
    for i, r in runes:
      if not isWhitespace(r):
        result.x = i
        break

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

# Helper functions for word motion
proc isWordChar(r: Rune): bool =
  ## Check if a character is part of a word (alphanumeric or underscore)
  let c = r.int32
  return
    (c >= 'a'.ord and c <= 'z'.ord) or (c >= 'A'.ord and c <= 'Z'.ord) or
    (c >= '0'.ord and c <= '9'.ord) or c == '_'.ord

proc isWhitespace(r: Rune): bool =
  ## Check if a character is whitespace
  let c = r.int32
  return c == ' '.ord or c == '\t'.ord or c == '\n'.ord or c == '\r'.ord

proc moveWordForward(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to the start of the next word (w motion)
  ## In Vim, a word is either:
  ## 1. A sequence of word characters (letters, digits, underscore)
  ## 2. A sequence of non-word, non-whitespace characters (symbols)
  ##
  ## Note: Uses toRunes() for simplicity. For most lines (<1000 chars),
  ## the overhead is negligible compared to the clarity and correctness.
  result = currentPos
  var iterCount = count

  while iterCount > 0:
    # Get current line
    if result.y >= e.buffer.len:
      break

    let line = e.buffer.getLine(result.y)
    # Remove trailing newline if present for proper rune processing
    let lineContent =
      if line.len > 0 and line[^1] == '\n':
        line[0 ..< ^1]
      else:
        line
    let runes = lineContent.toRunes()
    var pos = result.x

    # Skip current word/symbol sequence
    if pos < runes.len:
      let firstCh = runes[pos]
      if isWordChar(firstCh):
        # Skip word characters
        while pos < runes.len and isWordChar(runes[pos]):
          pos += 1
      elif not isWhitespace(firstCh):
        # Skip symbol characters (non-word, non-whitespace)
        while pos < runes.len and not isWordChar(runes[pos]) and
            not isWhitespace(runes[pos]):
          pos += 1

    # Skip whitespace after the word/symbols
    while pos < runes.len and isWhitespace(runes[pos]):
      pos += 1

    # If we reached end of line, move to next line
    if pos >= runes.len:
      if result.y + 1 < e.buffer.len:
        result.y += 1
        result.x = 0
        # Skip leading whitespace on new line
        let nextLine = e.buffer.getLine(result.y)
        let nextContent =
          if nextLine.len > 0 and nextLine[^1] == '\n':
            nextLine[0 ..< ^1]
          else:
            nextLine
        let nextRunes = nextContent.toRunes()
        while result.x < nextRunes.len and isWhitespace(nextRunes[result.x]):
          result.x += 1
      else:
        # At last line, stay at end
        result.x = max(0, runes.len - 1)
    else:
      result.x = pos

    iterCount -= 1

proc moveWordBackward(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to the start of the previous word (b motion)
  ## Same word definition as moveWordForward
  result = currentPos
  var iterCount = count

  while iterCount > 0:
    if result.y < 0:
      break

    var pos = result.x

    # Move back one position first
    if pos > 0:
      pos -= 1
    elif result.y > 0:
      # Move to previous line
      result.y -= 1
      let prevLine = e.buffer.getLine(result.y)
      let prevContent =
        if prevLine.len > 0 and prevLine[^1] == '\n':
          prevLine[0 ..< ^1]
        else:
          prevLine
      let prevRunes = prevContent.toRunes()
      pos = max(0, prevRunes.len - 1)
    else:
      # At beginning of buffer
      break

    let currentLine = e.buffer.getLine(result.y)
    let lineContent =
      if currentLine.len > 0 and currentLine[^1] == '\n':
        currentLine[0 ..< ^1]
      else:
        currentLine
    let runes = lineContent.toRunes()

    # Skip whitespace backwards
    while pos > 0 and isWhitespace(runes[pos]):
      pos -= 1

    # Now we're on a non-whitespace character
    # Skip backwards through the word/symbol sequence to find its start
    if pos >= 0 and pos < runes.len:
      if isWordChar(runes[pos]):
        # Skip word characters backwards
        while pos > 0 and isWordChar(runes[pos - 1]):
          pos -= 1
      elif not isWhitespace(runes[pos]):
        # Skip symbol characters backwards
        while pos > 0 and not isWordChar(runes[pos - 1]) and
            not isWhitespace(runes[pos - 1]):
          pos -= 1

    result.x = pos
    iterCount -= 1

proc moveWordEnd(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to the end of the next word (e motion)
  ## Same word definition as moveWordForward
  result = currentPos
  var iterCount = count

  while iterCount > 0:
    if result.y >= e.buffer.len:
      break

    var pos = result.x
    var currentLine = e.buffer.getLine(result.y)
    var lineContent =
      if currentLine.len > 0 and currentLine[^1] == '\n':
        currentLine[0 ..< ^1]
      else:
        currentLine
    var runes = lineContent.toRunes()

    # Move forward one position first
    if pos + 1 < runes.len:
      pos += 1
    elif result.y + 1 < e.buffer.len:
      # Move to next line
      result.y += 1
      pos = 0
      currentLine = e.buffer.getLine(result.y)
      lineContent =
        if currentLine.len > 0 and currentLine[^1] == '\n':
          currentLine[0 ..< ^1]
        else:
          currentLine
      runes = lineContent.toRunes()
    else:
      # At end of buffer
      break

    # Skip whitespace
    while pos < runes.len and isWhitespace(runes[pos]):
      pos += 1
      if pos >= runes.len and result.y + 1 < e.buffer.len:
        result.y += 1
        pos = 0
        currentLine = e.buffer.getLine(result.y)
        lineContent =
          if currentLine.len > 0 and currentLine[^1] == '\n':
            currentLine[0 ..< ^1]
          else:
            currentLine
        runes = lineContent.toRunes()

    # Move to end of word/symbol sequence
    if pos < runes.len:
      if isWordChar(runes[pos]):
        # Move to end of word characters
        while pos + 1 < runes.len and isWordChar(runes[pos + 1]):
          pos += 1
      elif not isWhitespace(runes[pos]):
        # Move to end of symbol characters
        while pos + 1 < runes.len and not isWordChar(runes[pos + 1]) and
            not isWhitespace(runes[pos + 1]):
          pos += 1

    result.x = pos
    iterCount -= 1

proc isBlankLine(line: string): bool =
  ## Check if a line is blank (empty or contains only whitespace)
  let content =
    if line.len > 0 and line[^1] == '\n':
      line[0 ..< ^1]
    else:
      line

  if content.len == 0:
    return true

  # Check if all characters are whitespace
  for r in content.toRunes():
    if not isWhitespace(r):
      return false
  return true

proc moveParagraphForward(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to next paragraph (} motion)
  ## A paragraph is defined as a block of text separated by blank lines
  result = currentPos
  var iterCount = count

  while iterCount > 0:
    var lineIdx = result.y

    # If we're on a blank line, skip blank lines
    if lineIdx < e.buffer.len and isBlankLine(e.buffer.getLine(lineIdx)):
      while lineIdx < e.buffer.len - 1 and isBlankLine(e.buffer.getLine(lineIdx)):
        lineIdx += 1

    # Now find the next blank line
    while lineIdx < e.buffer.len - 1:
      lineIdx += 1
      if isBlankLine(e.buffer.getLine(lineIdx)):
        break

    result.y = lineIdx
    result.x = 0
    iterCount -= 1

proc moveParagraphBackward(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to previous paragraph ({ motion)
  ## A paragraph is defined as a block of text separated by blank lines
  result = currentPos
  var iterCount = count

  while iterCount > 0:
    var lineIdx = result.y

    # If we're on a blank line, skip blank lines going backward
    if lineIdx > 0 and isBlankLine(e.buffer.getLine(lineIdx)):
      while lineIdx > 0 and isBlankLine(e.buffer.getLine(lineIdx)):
        lineIdx -= 1

    # Now find the previous blank line
    while lineIdx > 0:
      lineIdx -= 1
      if isBlankLine(e.buffer.getLine(lineIdx)):
        break

    result.y = lineIdx
    result.x = 0
    iterCount -= 1

proc moveViewportHigh(
    e: MotionExecutor, currentPos: CursorPosition, viewportTopLine: int, count: int = 1
): CursorPosition =
  ## Move to top line of viewport (H motion)
  ## count specifies offset from top (e.g., 2H moves to second line from top)
  result = currentPos
  let targetLine = viewportTopLine + (count - 1)
  result.y = min(targetLine, e.buffer.len - 1)
  result.x = 0

proc moveViewportMiddle(
    e: MotionExecutor,
    currentPos: CursorPosition,
    viewportTopLine: int,
    viewportHeight: int,
    reservedLines: int,
): CursorPosition =
  ## Move to middle line of viewport (M motion)
  result = currentPos
  # Calculate the middle line of the visible area (excluding reserved lines)
  let visibleHeight = viewportHeight - reservedLines
  let middleLine = viewportTopLine + (visibleHeight div 2)
  result.y = min(middleLine, e.buffer.len - 1)
  result.x = 0

proc moveViewportLow(
    e: MotionExecutor,
    currentPos: CursorPosition,
    viewportTopLine: int,
    viewportHeight: int,
    reservedLines: int,
    count: int = 1,
): CursorPosition =
  ## Move to bottom line of viewport (L motion)
  ## count specifies offset from bottom (e.g., 2L moves to second line from bottom)
  result = currentPos
  # Calculate the target line (bottom of viewport minus count, excluding reserved lines)
  let visibleHeight = viewportHeight - reservedLines
  let bottomLine = viewportTopLine + visibleHeight - 1
  let targetLine = bottomLine - (count - 1)
  result.y = min(max(0, targetLine), e.buffer.len - 1)
  result.x = 0

proc calculateNewPosition*(
    e: MotionExecutor,
    currentPos: CursorPosition,
    cmd: MotionCommand,
    viewportHeight: int = 24,
    viewportTopLine: int = 0,
    reservedLines: int = 2,
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
  of Motion.FirstNonBlank:
    e.moveFirstNonBlank(currentPos)
  of Motion.LastNonBlank:
    e.moveLastNonBlank(currentPos)
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
  of Motion.WordForward:
    e.moveWordForward(currentPos, cmd.count)
  of Motion.WordBackward:
    e.moveWordBackward(currentPos, cmd.count)
  of Motion.WordEnd:
    e.moveWordEnd(currentPos, cmd.count)
  of Motion.WordEndBackward:
    # Not implemented yet, just return current position
    currentPos
  of Motion.ParagraphForward:
    e.moveParagraphForward(currentPos, cmd.count)
  of Motion.ParagraphBackward:
    e.moveParagraphBackward(currentPos, cmd.count)
  of Motion.ViewportHigh:
    e.moveViewportHigh(currentPos, viewportTopLine, cmd.count)
  of Motion.ViewportMiddle:
    e.moveViewportMiddle(currentPos, viewportTopLine, viewportHeight, reservedLines)
  of Motion.ViewportLow:
    e.moveViewportLow(
      currentPos, viewportTopLine, viewportHeight, reservedLines, cmd.count
    )
  of Motion.NextLineFirstNonBlank:
    e.moveNextLineFirstNonBlank(currentPos, cmd.count)
  of Motion.PreviousLineFirstNonBlank:
    e.movePreviousLineFirstNonBlank(currentPos, cmd.count)

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
    logDebug("viewport", "updateViewport: LINE WRAP MODE")
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
    logDebug("viewport", "updateViewport: NO WRAP MODE")
    # No line wrap: simple logic
    if clampedCursorY < mgr.viewport.topLine:
      # Cursor moved above viewport - scroll up
      logDebug(
        "viewport",
        "Cursor above viewport: clampedCursorY=" & $clampedCursorY & " topLine=" &
          $mgr.viewport.topLine,
      )
      mgr.viewport.topLine = clampedCursorY
    elif clampedCursorY >=
        mgr.viewport.topLine + mgr.viewport.height - actualReservedLines:
      # Cursor moved below viewport - scroll down (account for status and command lines)
      logDebug(
        "viewport",
        "Cursor below viewport: clampedCursorY=" & $clampedCursorY & " threshold=" &
          $(mgr.viewport.topLine + mgr.viewport.height - actualReservedLines),
      )
      let
        newTopLine = clampedCursorY - mgr.viewport.height + actualReservedLines + 1
        maxTopLine = max(0, lineCount - mgr.viewport.height + actualReservedLines)
      logDebug(
        "viewport",
        "Calculated newTopLine=" & $newTopLine & " maxTopLine=" & $maxTopLine,
      )
      mgr.viewport.topLine = max(0, min(maxTopLine, newTopLine))
      logDebug("viewport", "Final topLine=" & $mgr.viewport.topLine)
    else:
      logDebug(
        "viewport",
        "Cursor within viewport: clampedCursorY=" & $clampedCursorY & " range=[" &
          $mgr.viewport.topLine & ", " &
          $(mgr.viewport.topLine + mgr.viewport.height - actualReservedLines - 1) & "]",
      )

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

  # Calculate reserved lines (same logic as updateViewport)
  let actualReservedLines =
    if controller.cursorManager.state.viewportReservedLines >= 0:
      controller.cursorManager.state.viewportReservedLines
    else:
      (if controller.cursorManager.state.showStatusLine: 2 else: 1)

  var newPos = controller.executor.calculateNewPosition(
    currentPos, cmd, controller.viewportManager.viewport.height,
    controller.viewportManager.viewport.topLine, actualReservedLines,
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
    showLineNumbers = controller.cursorManager.state.showLineNumbers
    lineNumOffset = calculateLineNumOffset(controller.executor.buffer, showLineNumbers)

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

## Operator range calculation utilities

proc calculateOperatorRange*(
    buffer: TextBuffer, startPos: BufferPosition, endPos: BufferPosition, motion: Motion
): OperatorRange =
  ## Calculate the range affected by an operator+motion combination
  ## Returns OperatorRange with proper start/end and linewise flag

  # Determine if this is a linewise motion
  let isLinewise =
    motion in {
      Motion.Up, Motion.Down, Motion.FirstLine, Motion.LastLine, Motion.PageUp,
      Motion.PageDown, Motion.ParagraphForward, Motion.ParagraphBackward,
      Motion.NextLineFirstNonBlank, Motion.PreviousLineFirstNonBlank,
    }

  # Determine if this is an exclusive motion (Vim behavior)
  # Exclusive motions do NOT include the character at endPos
  let isExclusive =
    motion in {
      Motion.WordForward, # w
      Motion.WordEnd, # e
      Motion.WordBackward, # b
      Motion.WordEndBackward, # ge
      Motion.Right, # l (when used with operator)
      Motion.Left, # h (when used with operator)
    }

  var range = OperatorRange(start: startPos, endPos: endPos, isLinewise: isLinewise)

  # Ensure start comes before end
  if range.start.line > range.endPos.line or
      (
        range.start.line == range.endPos.line and
        range.start.column > range.endPos.column
      ):
    swap(range.start, range.endPos)

  # For exclusive motions in characterwise mode, exclude the endPos character
  # by moving endPos back by 1 column (this matches Vim's behavior)
  if isExclusive and not isLinewise:
    # Only adjust if we're not at the start of the range
    if range.endPos.line == range.start.line and range.endPos.column > range.start.column:
      # Same line - just move column back
      range.endPos.column -= 1
    elif range.endPos.line > range.start.line and range.endPos.column > 0:
      # Different line - move column back
      range.endPos.column -= 1
    # Note: If endPos.column is 0 and we're on a different line,
    # we need to move to the previous line's end
    elif range.endPos.line > range.start.line and range.endPos.column == 0:
      range.endPos.line -= 1
      if range.endPos.line >= 0 and range.endPos.line < buffer.len:
        let prevLine = buffer.getLine(range.endPos.line)
        let prevContent =
          if prevLine.len > 0 and prevLine[^1] == '\n':
            prevLine[0 ..< ^1]
          else:
            prevLine
        range.endPos.column = max(0, prevContent.charLen - 1)

  # For linewise operations, extend to full lines
  if isLinewise:
    range.start.column = 0
    if range.endPos.line < buffer.len:
      let endLine = buffer.getLine(range.endPos.line)
      range.endPos.column = endLine.charLen

  return range

proc extractRangeText*(buffer: TextBuffer, range: OperatorRange): string =
  ## Extract text from the given range
  ## Used for yank operations

  var text = ""

  if range.isLinewise:
    # Extract entire lines
    for lineIdx in range.start.line .. range.endPos.line:
      if lineIdx < buffer.len:
        let lineContent = buffer.getLine(lineIdx)
        text.add(lineContent)
        if lineContent.len == 0 or lineContent[^1] != '\n':
          text.add("\n")
  else:
    # Extract character range
    if range.start.line == range.endPos.line:
      # Single line extraction
      let line = buffer.getLine(range.start.line)
      let startCol = min(range.start.column, line.charLen)
      let endCol = min(range.endPos.column, line.charLen)
      if startCol < line.charLen:
        let runes = line.toRunes()
        for i in startCol ..< endCol:
          if i < runes.len:
            text.add($runes[i])
    else:
      # Multi-line extraction
      for lineIdx in range.start.line .. range.endPos.line:
        if lineIdx < buffer.len:
          let line = buffer.getLine(lineIdx)
          if lineIdx == range.start.line:
            # First line: from startCol to end
            if range.start.column < line.charLen:
              let runes = line.toRunes()
              for i in range.start.column ..< runes.len:
                text.add($runes[i])
            text.add("\n")
          elif lineIdx == range.endPos.line:
            # Last line: from start to endCol
            let runes = line.toRunes()
            let endCol = min(range.endPos.column, runes.len)
            for i in 0 ..< endCol:
              text.add($runes[i])
          else:
            # Middle lines: entire line
            text.add(line)
            if line.len == 0 or line[^1] != '\n':
              text.add("\n")

  return text

proc deleteRange*(buffer: TextBuffer, range: OperatorRange): Result[(), string] =
  ## Delete text in the given range
  ## Used for delete and change operations

  if range.isLinewise:
    # Delete entire lines
    for i in 0 .. (range.endPos.line - range.start.line):
      if range.start.line < buffer.len:
        let deleteResult = buffer.deleteLine(range.start.line)
        if deleteResult.isErr:
          return err(deleteResult.error)
  else:
    # Delete character range using buffer.deleteRange
    let deleteResult = buffer.deleteRange(range.start, range.endPos)
    if deleteResult.isErr:
      return err(deleteResult.error)

  return ok(())

## Text object range calculation

proc findWordBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool
): Result[TextObjectRange, string] =
  ## Find word boundaries for iw (inner word) or aw (a word)
  ## inner=true: just the word
  ## inner=false: word + trailing whitespace (or leading if no trailing)

  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  let line = buffer.getLine(cursor.line)
  let runes = line.toRunes()

  if runes.len == 0:
    return err("Empty line")

  let cursorCol = min(cursor.column, runes.len - 1)

  # Find start of word
  var startCol = cursorCol
  # If cursor is on whitespace, move to next word
  if isWhitespace(runes[startCol]):
    while startCol < runes.len and isWhitespace(runes[startCol]):
      startCol.inc
    if startCol >= runes.len:
      return err("No word found")

  # Now find the actual word start
  while startCol > 0 and isWordChar(runes[startCol - 1]):
    startCol.dec

  # Find end of word
  var endCol = startCol
  while endCol < runes.len and isWordChar(runes[endCol]):
    endCol.inc

  if inner:
    # Inner word: just the word itself
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol),
        endPos: BufferPosition(line: cursor.line, column: endCol),
        isLinewise: false,
      )
    )
  else:
    # Around word: word + trailing whitespace
    var extendedEnd = endCol
    while extendedEnd < runes.len and isWhitespace(runes[extendedEnd]):
      extendedEnd.inc

    # If no trailing whitespace, try leading
    if extendedEnd == endCol and startCol > 0:
      var extendedStart = startCol
      while extendedStart > 0 and isWhitespace(runes[extendedStart - 1]):
        extendedStart.dec
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: extendedStart),
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )

    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol),
        endPos: BufferPosition(line: cursor.line, column: extendedEnd),
        isLinewise: false,
      )
    )

proc findQuotedBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, quoteChar: char, inner: bool
): Result[TextObjectRange, string] =
  ## Find quoted string boundaries for i" or a"
  ## inner=true: content inside quotes
  ## inner=false: content + quotes

  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  let line = buffer.getLine(cursor.line)
  let runes = line.toRunes()

  if runes.len == 0:
    return err("Empty line")

  let cursorCol = min(cursor.column, runes.len - 1)

  # Find opening quote (search backward from cursor)
  var startCol = -1
  var i = cursorCol
  while i >= 0:
    if $runes[i] == $quoteChar:
      # Check if it's escaped
      var escaped = false
      if i > 0 and $runes[i - 1] == "\\":
        escaped = true
      if not escaped:
        startCol = i
        break
    i.dec

  if startCol < 0:
    return err("No opening quote found")

  # Find closing quote (search forward from opening quote)
  var endCol = -1
  i = startCol + 1
  while i < runes.len:
    if $runes[i] == $quoteChar:
      # Check if it's escaped
      var escaped = false
      if i > 0 and $runes[i - 1] == "\\":
        escaped = true
      if not escaped:
        endCol = i
        break
    i.inc

  if endCol < 0:
    return err("No closing quote found")

  if inner:
    # Inner: content only (exclude quotes)
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol + 1),
        endPos: BufferPosition(line: cursor.line, column: endCol),
        isLinewise: false,
      )
    )
  else:
    # Around: content + quotes
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol),
        endPos: BufferPosition(line: cursor.line, column: endCol + 1),
        isLinewise: false,
      )
    )

proc findMatchingParen(
    buffer: TextBuffer,
    cursor: BufferPosition,
    openChar: char,
    closeChar: char,
    inner: bool,
): Result[TextObjectRange, string] =
  ## Find matching parenthesis/bracket/brace boundaries
  ## inner=true: content inside delimiters
  ## inner=false: content + delimiters

  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  let line = buffer.getLine(cursor.line)
  let runes = line.toRunes()

  if runes.len == 0:
    return err("Empty line")

  let cursorCol = min(cursor.column, runes.len - 1)

  # Find opening delimiter (search backward from cursor)
  var startCol = -1
  var depth = 0
  var i = cursorCol

  # If cursor is on a closing delimiter, start from before it
  if $runes[i] == $closeChar:
    depth = 1
    i.dec

  while i >= 0:
    if $runes[i] == $closeChar:
      depth.inc
    elif $runes[i] == $openChar:
      if depth == 0:
        startCol = i
        break
      else:
        depth.dec
    i.dec

  if startCol < 0:
    return err("No opening delimiter found")

  # Find closing delimiter (search forward from opening)
  var endCol = -1
  depth = 0
  i = startCol + 1
  while i < runes.len:
    if $runes[i] == $openChar:
      depth.inc
    elif $runes[i] == $closeChar:
      if depth == 0:
        endCol = i
        break
      else:
        depth.dec
    i.inc

  if endCol < 0:
    return err("No closing delimiter found")

  if inner:
    # Inner: content only (exclude delimiters)
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol + 1),
        endPos: BufferPosition(line: cursor.line, column: endCol),
        isLinewise: false,
      )
    )
  else:
    # Around: content + delimiters
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol),
        endPos: BufferPosition(line: cursor.line, column: endCol + 1),
        isLinewise: false,
      )
    )

proc calculateTextObjectRange*(
    buffer: TextBuffer,
    cursor: BufferPosition,
    kind: TextObjectKind,
    modifier: TextObjectModifier,
): Result[TextObjectRange, string] =
  ## Calculate the range of a text object
  ## Returns TextObjectRange with start and end positions

  let inner = (modifier == tomInner)

  case kind
  of toWord:
    return findWordBoundaries(buffer, cursor, inner)
  of toQuotedDouble:
    return findQuotedBoundaries(buffer, cursor, '"', inner)
  of toQuotedSingle:
    return findQuotedBoundaries(buffer, cursor, '\'', inner)
  of toQuotedBacktick:
    return findQuotedBoundaries(buffer, cursor, '`', inner)
  of toParenthesis:
    return findMatchingParen(buffer, cursor, '(', ')', inner)
  of toBracket:
    return findMatchingParen(buffer, cursor, '[', ']', inner)
  of toBrace:
    return findMatchingParen(buffer, cursor, '{', '}', inner)
  of toAngleBracket:
    return findMatchingParen(buffer, cursor, '<', '>', inner)
  else:
    return err("Text object " & $kind & " not yet implemented")
