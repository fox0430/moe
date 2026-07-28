#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

import std/[options, unicode, monotimes, times]

import pkg/results

import types, unicode_utils, logger, render_utils, config, modes
import buffer/[core, edit, fold, undo]
import visible_rows

type
  # Motion command with count
  MotionCommand* = object
    motion*: Motion
    count*: int
    targetChar*: string # For find/till commands

  # Motion executor - handles only motion logic
  MotionExecutor* = ref object
    buffer*: core.TextBuffer

  # Viewport manager - handles viewport updates
  ViewportManager* = ref object
    viewport*: ViewPort
    wrapCountCache*: WrapCountCache
      # Bound to the active window's cache by syncActiveWindow.

  # Cursor manager - handles cursor positioning and clamping
  CursorManager* = ref object
    state*: EditorState

  # Main motion controller - coordinates between components
  MotionController* = ref object
    executor*: MotionExecutor
    viewportManager*: ViewportManager
    cursorManager*: CursorManager

const tagScanInitialRadius = 128
  ## Initial half-window (in lines) scanned around the cursor for it/at. The
  ## window quadruples until the enclosing pair is found, so the common case
  ## touches only nearby lines instead of flattening the whole buffer.

proc newMotionExecutor*(buffer: core.TextBuffer): MotionExecutor =
  MotionExecutor(buffer: buffer)

proc maxCursorColumn(lineCharLen: int, mode: EditorMode): int =
  ## Rightmost column the cursor may occupy on a line of `lineCharLen`
  ## characters. Insert/Replace let it rest one past the last character (end of
  ## line); other modes stop on the last character.
  if mode in {EditorMode.Insert, EditorMode.Replace}:
    lineCharLen
  else:
    max(0, lineCharLen - 1)

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
    e: MotionExecutor,
    currentPos: CursorPosition,
    count: int,
    mode: EditorMode = EditorMode.Normal,
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

    # Move right by character count, not byte count. Insert/Replace may rest one
    # past the last character (end of line); other modes stop on it.
    let maxPos = maxCursorColumn(lineCharLen, mode)
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
  var targetY = max(0, currentPos.y - count)

  # Skip over folded lines when moving up (with safety limit to prevent infinite loop)
  var iterations = 0
  let maxIterations = e.buffer.len + 1
  while targetY > 0 and e.buffer.foldState.isLineInCollapsedFold(targetY) and
      iterations < maxIterations:
    let newY = e.buffer.foldState.getPrevVisibleLine(targetY)
    if newY == targetY:
      # getPrevVisibleLine didn't make progress, break to prevent infinite loop
      break
    targetY = newY
    inc iterations

  result.y = targetY

proc moveDown(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  result = currentPos
  if e.buffer.len > 0:
    var targetY = min(e.buffer.len - 1, currentPos.y + count)

    # Skip over folded lines when moving down (with safety limit to prevent infinite loop)
    var iterations = 0
    let maxIterations = e.buffer.len + 1
    while targetY < e.buffer.len - 1 and
        e.buffer.foldState.isLineInCollapsedFold(targetY) and iterations < maxIterations:
      let newY = e.buffer.foldState.getNextVisibleLine(targetY, e.buffer.len - 1)
      if newY == targetY:
        # getNextVisibleLine didn't make progress, break to prevent infinite loop
        break
      targetY = newY
      inc iterations

    result.y = targetY
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

proc moveHalfPageUp(
    e: MotionExecutor, currentPos: CursorPosition, count: int, viewportHeight: int
): CursorPosition =
  result = currentPos
  let halfPageSize = max(1, (viewportHeight - 1) div 2) * count
  result.y = max(0, currentPos.y - halfPageSize)

proc moveHalfPageDown(
    e: MotionExecutor, currentPos: CursorPosition, count: int, viewportHeight: int
): CursorPosition =
  result = currentPos
  let halfPageSize = max(1, (viewportHeight - 1) div 2) * count
  if e.buffer.len > 0:
    result.y = min(e.buffer.len - 1, currentPos.y + halfPageSize)
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

proc moveEnd(
    e: MotionExecutor, currentPos: CursorPosition, mode: EditorMode = EditorMode.Normal
): CursorPosition =
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let lineCharLen = e.buffer.getLine(currentPos.y).charLen
    # Insert/Replace land at end of line; other modes on the last character.
    result.x = maxCursorColumn(lineCharLen, mode)

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
    e: MotionExecutor, currentPos: CursorPosition, count: int = 0
): CursorPosition =
  ## count == 0 means "no explicit prefix — go to last line" (bare G).
  ## count >= 1 means "go to line `count` (1-indexed, clamped)".
  result = currentPos
  if e.buffer.len == 0:
    return
  if count <= 0:
    result.y = e.buffer.len - 1
  else:
    result.y = min(count - 1, e.buffer.len - 1)
  result.x = 0

proc findChar(
    e: MotionExecutor, currentPos: CursorPosition, targetChar: string, count: int
): CursorPosition =
  ## Find next occurrence of character on current line
  result = currentPos
  if currentPos.y >= 0 and currentPos.y < e.buffer.len:
    let targetRunes = targetChar.toRunes
    if targetRunes.len != 1:
      return
    let
      target = targetRunes[0]
      runes = e.buffer.getLine(currentPos.y).toRunes
    var found = 0
    # Index a one-time rune copy of the line instead of rescanning from the
    # start per column (avoids O(n^2) on long lines).
    for charIdx in currentPos.x + 1 ..< runes.len:
      if runes[charIdx] == target:
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
    let targetRunes = targetChar.toRunes
    if targetRunes.len != 1:
      return
    let
      target = targetRunes[0]
      runes = e.buffer.getLine(currentPos.y).toRunes
    var found = 0
    for charIdx in countdown(min(currentPos.x - 1, runes.len - 1), 0):
      if runes[charIdx] == target:
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

proc isWhitespace(r: Rune): bool =
  ## Check if a character is whitespace
  let c = r.int32
  return c == ' '.ord or c == '\t'.ord or c == '\n'.ord or c == '\r'.ord

proc isSymbolChar(r: Rune): bool =
  ## Check if a character is a symbol (non-word, non-whitespace)
  return not isWordChar(r) and not isWhitespace(r)

proc skipWordForward*(runes: seq[Rune], startCol: int): int =
  ## Skip current word/symbol sequence and trailing whitespace from startCol.
  ## Returns the column position after skipping.
  ## Used by both moveWordForward and calculateOperatorRange.
  result = startCol
  if result < runes.len:
    let ch = runes[result]
    if isWordChar(ch):
      while result < runes.len and isWordChar(runes[result]):
        result += 1
    elif not isWhitespace(ch):
      while result < runes.len and not isWordChar(runes[result]) and
          not isWhitespace(runes[result]):
        result += 1
  while result < runes.len and isWhitespace(runes[result]):
    result += 1

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
    let pos = skipWordForward(runes, result.x)

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
    var currentLine: string
    var lineContent: string
    var runes: seq[Rune]

    template loadCurrentLine() =
      currentLine = e.buffer.getLine(result.y)
      lineContent =
        if currentLine.len > 0 and currentLine[^1] == '\n':
          currentLine[0 ..< ^1]
        else:
          currentLine
      runes = lineContent.toRunes()

    # Move back one position first
    if pos > 0:
      pos -= 1
      loadCurrentLine()
    elif result.y > 0:
      # Move to previous line
      result.y -= 1
      loadCurrentLine()
      pos = max(0, runes.len - 1)
    else:
      # At beginning of buffer
      break

    # Skip whitespace and empty lines backwards.
    while true:
      while pos > 0 and pos < runes.len and isWhitespace(runes[pos]):
        pos -= 1
      if (runes.len == 0 or (pos < runes.len and isWhitespace(runes[pos]))) and
          result.y > 0:
        result.y -= 1
        loadCurrentLine()
        pos = max(0, runes.len - 1)
      else:
        break

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

    # Skip whitespace and empty lines.
    while true:
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
      else:
        break

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

proc moveWordEndBackward(
    e: MotionExecutor, currentPos: CursorPosition, count: int
): CursorPosition =
  ## Move to the end of the previous word (ge motion)
  ## A "word end" is a position where the character is non-whitespace and the
  ## next character is whitespace, a different char type, or end of line.
  ## We search backward for the nearest such position before current.
  result = currentPos
  var iterCount = count

  template getLineRunes(lineIdx: int): seq[Rune] =
    let line = e.buffer.getLine(lineIdx)
    let content =
      if line.len > 0 and line[^1] == '\n':
        line[0 ..< ^1]
      else:
        line
    content.toRunes()

  template isWordEnd(runes: seq[Rune], pos: int): bool =
    pos < runes.len and not isWhitespace(runes[pos]) and (
      pos + 1 >= runes.len or isWhitespace(runes[pos + 1]) or
      isWordChar(runes[pos]) != isWordChar(runes[pos + 1])
    )

  while iterCount > 0:
    var pos = result.x - 1
    var y = result.y
    var found = false

    while not found:
      if pos < 0:
        if y > 0:
          y -= 1
          let runes = getLineRunes(y)
          pos = runes.len - 1
          if pos < 0:
            # Empty line - continue to previous line
            continue
        else:
          # Beginning of buffer
          break

      let runes = getLineRunes(y)
      if isWordEnd(runes, pos):
        found = true
      else:
        pos -= 1

    if found:
      result.x = pos
      result.y = y
    # If not found, stay at current position (beginning of buffer)

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

proc moveToMatchingBracket(
    e: MotionExecutor, currentPos: CursorPosition
): CursorPosition =
  ## Move to matching bracket (% motion)
  ## Finds the matching bracket for (, ), {, }, [, ]
  result = currentPos

  # Bounds check
  if currentPos.y < 0 or currentPos.y >= e.buffer.len:
    return

  let currentLine = e.buffer.getLine(currentPos.y)
  if currentPos.x >= currentLine.charLen:
    return

  # Get character at cursor
  var charIdx = 0
  var currentRune: Rune
  for r in currentLine.runes:
    if charIdx == currentPos.x:
      currentRune = r
      break
    charIdx += 1

  if not currentRune.isBracket:
    return

  if currentRune.isOpenBracket:
    # Search forward for closing bracket
    let closeBracket = correspondingCloseBracket(currentRune)
    var depth = 1
    var lineIdx = currentPos.y
    var colIdx = currentPos.x + 1

    while lineIdx < e.buffer.len:
      # Index a one-time rune copy of the line instead of a skip scan plus a
      # sliced toRunes copy per line.
      let runes = e.buffer.getLine(lineIdx).toRunes
      var charPos = if lineIdx == currentPos.y: colIdx else: 0

      while charPos < runes.len:
        let r = runes[charPos]
        if r == currentRune:
          depth += 1
        elif r == closeBracket:
          depth -= 1
          if depth == 0:
            result.y = lineIdx
            result.x = charPos
            return
        charPos += 1

      lineIdx += 1
      colIdx = 0
  else:
    # Search backward for opening bracket
    let openBracket = correspondingOpenBracket(currentRune)
    var depth = 1
    var lineIdx = currentPos.y
    var colIdx = currentPos.x - 1

    while lineIdx >= 0:
      # Index a one-time rune copy of the line instead of rescanning from the
      # start per column (avoids O(n^2) on long lines).
      let runes = e.buffer.getLine(lineIdx).toRunes

      # Set starting column
      if lineIdx != currentPos.y:
        colIdx = runes.len - 1

      # Search backward for matching bracket
      while colIdx >= 0:
        let targetRune = runes[colIdx]
        if targetRune == currentRune:
          depth += 1
        elif targetRune == openBracket:
          depth -= 1
          if depth == 0:
            result.y = lineIdx
            result.x = colIdx
            return

        colIdx -= 1

      lineIdx -= 1

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
    reservedLines: int = steadyBottomAreaHeight(),
    mode: EditorMode = EditorMode.Normal,
): CursorPosition =
  ## Calculate new cursor position after motion, without modifying state.
  ## `mode` lets Insert/Replace rest one past the last character (end of line).
  case cmd.motion
  of Motion.Left:
    e.moveLeft(currentPos, cmd.count)
  of Motion.Right:
    e.moveRight(currentPos, cmd.count, mode)
  of Motion.Up:
    e.moveUp(currentPos, cmd.count)
  of Motion.Down:
    e.moveDown(currentPos, cmd.count)
  of Motion.PageUp:
    e.movePageUp(currentPos, cmd.count, viewportHeight)
  of Motion.PageDown:
    e.movePageDown(currentPos, cmd.count, viewportHeight)
  of Motion.HalfPageUp:
    e.moveHalfPageUp(currentPos, cmd.count, viewportHeight)
  of Motion.HalfPageDown:
    e.moveHalfPageDown(currentPos, cmd.count, viewportHeight)
  of Motion.Home:
    e.moveHome(currentPos)
  of Motion.FirstNonBlank:
    e.moveFirstNonBlank(currentPos)
  of Motion.LastNonBlank:
    e.moveLastNonBlank(currentPos)
  of Motion.End:
    e.moveEnd(currentPos, mode)
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
    e.moveWordEndBackward(currentPos, cmd.count)
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
  of Motion.MatchBracket:
    e.moveToMatchingBracket(currentPos)
  of Motion.RepeatFind, Motion.RepeatFindReverse:
    # Dispatch concepts, not real motions: executeCommand resolves these to a
    # concrete find/till motion before the motion path reaches here (see
    # command_registry.executeFindCharMotion). Arriving here means a caller
    # bypassed that resolution, so fail loudly instead of silently returning
    # currentPos (the former silent no-op masked such wiring mistakes).
    raiseAssert "RepeatFind must be resolved before calculateNewPosition"

proc newCursorManager*(state: EditorState): CursorManager =
  CursorManager(state: state)

proc clampPosition*(
    mgr: CursorManager, pos: CursorPosition, buf: core.TextBuffer
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

  # Vim behavior: a collapsed fold is a single unit. If the cursor is on any
  # line of a collapsed fold (its start line or a hidden interior line), pin it
  # to the fold's start line at column 0 so it can't roam the hidden content.
  let collapsedFold = buf.foldState.getCollapsedFoldAt(result.y)
  if collapsedFold.isSome:
    result.y = collapsedFold.get.startLine
    result.x = 0

  # Clamp column - ensure line index is valid before accessing
  if result.y >= 0 and result.y < buf.len:
    let lineCharLen = buf.getLine(result.y).charLen # character count, not bytes
    # Insert/Replace may rest one past the last character (end of line); other
    # modes keep the cursor on the last character.
    let maxCol = maxCursorColumn(lineCharLen, mgr.state.mode)
    if result.x > maxCol:
      result.x = maxCol
    elif result.x < 0:
      result.x = 0

proc newViewportManager*(viewport: ViewPort): ViewportManager =
  ViewportManager(viewport: viewport)

proc updateViewport*(
    mgr: ViewportManager,
    cursorPos: CursorPosition,
    lineCount: int,
    showStatusLine: bool = true,
    reservedLines: int = -1, # -1 means auto-calculate from showStatusLine
    lineWrap: bool = false,
    buffer: core.TextBuffer = nil,
    viewportOffset: int = 0,
    tabStop: int = 4,
) =
  ## Update viewport to keep cursor visible with 1-line scrolling.
  ## `viewportOffset` is every non-text cell of the window (line number +
  ## sidebar + scrollbar), from `viewportOffsetFor`.

  # Ensure we have valid data
  if lineCount <= 0:
    mgr.viewport.resetViewportTop()
    return

  let
    # Ensure cursor position is within valid bounds
    clampedCursorY = max(0, min(cursorPos.y, lineCount - 1))
    clampedCursorX = max(0, cursorPos.x)

    # Use the explicit parameter, or fall back to the steady bottom reserve
    actualReservedLines =
      if reservedLines >= 0:
        reservedLines
      else:
        steadyBottomAreaHeight()

  # Vertical scrolling - handle line wrap mode differently
  if lineWrap and not buffer.isNil:
    # Line wrap mode: calculate screen positions
    let
      maxWidth = wrapWidthFor(mgr.viewport.width, viewportOffset)
      visibleHeight = mgr.viewport.height - actualReservedLines

      rl = initRowLayout(buffer, mgr.wrapCountCache, lineWrap, maxWidth, tabStop)
      cursorWrapOffset = rl.cursorCell(clampedCursorY, clampedCursorX).wrapSeg

    # Cursor's screen row relative to topLine. The walk stops at visibleHeight
    # so a distant jump costs O(visibleHeight), not O(lines).
    let cursorScreenLine =
      rl.rowOfLine(mgr.viewport.topLine, 0, clampedCursorY, visibleHeight) +
      cursorWrapOffset

    # Scroll up if cursor is above viewport
    if cursorScreenLine < 0 or clampedCursorY < mgr.viewport.topLine:
      mgr.viewport.resetViewportTop(clampedCursorY)
    # Scroll down if cursor is below viewport
    elif cursorScreenLine >= visibleHeight:
      # Highest top that still shows the cursor on the last row. This viewport
      # only scrolls whole lines, so a top landing mid-line moves down one.
      mgr.viewport.resetViewportTop(
        rl.lineTopFor(clampedCursorY, cursorWrapOffset, max(0, visibleHeight - 1))
      )
  else:
    # No line wrap: simple logic
    if clampedCursorY < mgr.viewport.topLine:
      # Cursor moved above viewport - scroll up
      mgr.viewport.resetViewportTop(clampedCursorY)
    elif clampedCursorY >=
        mgr.viewport.topLine + mgr.viewport.height - actualReservedLines:
      # Cursor moved below viewport - scroll down (account for status and command lines)
      let
        newTopLine = clampedCursorY - mgr.viewport.height + actualReservedLines + 1
        maxTopLine = max(0, lineCount - mgr.viewport.height + actualReservedLines)
      mgr.viewport.resetViewportTop(max(0, min(maxTopLine, newTopLine)))

  # Horizontal scrolling - keep cursor visible (disabled in wrap mode)
  if not lineWrap:
    # Account for the gutters when calculating visible text width
    let visibleTextWidth = wrapWidthFor(mgr.viewport.width, viewportOffset)
    if clampedCursorX < mgr.viewport.leftColumn:
      mgr.viewport.leftColumn = clampedCursorX
    elif clampedCursorX >= mgr.viewport.leftColumn + visibleTextWidth:
      mgr.viewport.leftColumn = clampedCursorX - visibleTextWidth + 1

# Smooth scrolling functions (physics-based, compatible with vim comfortable-motion)
#
# Physics model from comfortable-motion.vim:
# - velocity += impulse (initial kick)
# - Each frame:
#   - velocity -= friction * dt (constant deceleration)
#   - velocity *= (1 - air_drag * dt) (velocity-proportional resistance)
#   - position += velocity * dt
#
# Default values (same as comfortable-motion):
# - friction: 80.0
# - air_drag: 2.0
# - interval: ~16.67ms (60 FPS)

const
  ScrollPhysicsInterval = 1000.0 / 60.0 # ~16.67ms per physics step (60 FPS)
  VelocityThreshold = 0.5 # Stop when velocity drops below this
  DefaultFriction = 80.0 # comfortable-motion default friction
  # Impulse multiplier calibrated to match comfortable-motion feel.
  # comfortable-motion uses flick(100) for ~15 lines (half page),
  # so impulse = distance * 7.0 gives similar behavior.
  ImpulseMultiplier = 7.0

proc cancelScrollAnimation*(anim: var ScrollAnimation) =
  ## Cancel any active scroll animation
  anim.active = false
  anim.velocity = 0.0

proc completeScrollAnimation*(
    anim: var ScrollAnimation
): tuple[completed: bool, cursorLine: int] =
  ## Complete a scroll animation immediately, returning the target position
  ## Returns (completed=false, 0) if no animation was active
  if not anim.active:
    return (false, 0)
  result = (true, anim.targetCursorLine)
  anim.active = false
  anim.velocity = 0.0

proc startScrollAnimation*(
    anim: var ScrollAnimation,
    currentCursorLine: int,
    targetCursorLine: int,
    config: SmoothScrollConfig,
) =
  ## Start a physics-based smooth scroll animation
  ## Compatible with vim comfortable-motion plugin
  ##
  ## The impulse is calculated to reach the target distance with the given
  ## friction and air_drag values.

  let distance = targetCursorLine - currentCursorLine
  if distance == 0:
    anim.active = false
    return

  # Calculate initial impulse to reach target.
  # Unlike comfortable-motion where flick and friction are independent,
  # we scale impulse by friction ratio to maintain consistent scroll distance
  # when friction is adjusted (higher friction = higher impulse needed).
  let frictionRatio = config.friction / DefaultFriction
  let impulse = distance.float * ImpulseMultiplier * frictionRatio

  anim.active = true
  anim.velocity = impulse
  anim.currentCursorLine = currentCursorLine.float
  anim.targetCursorLine = targetCursorLine
  anim.lastUpdateTime = getMonoTime()

proc updateScrollAnimation*(
    mgr: ViewportManager,
    anim: var ScrollAnimation,
    config: SmoothScrollConfig,
    reservedLines: int = steadyBottomAreaHeight(),
    bufferLen: int = int.high,
): tuple[active: bool, cursorLine: int] =
  ## Update physics-based scroll animation each frame.
  ## Returns (active, currentCursorLine).
  ## Uses friction and air_drag for comfortable-motion compatible physics.
  ## bufferLen is used to clamp cursor position within valid buffer bounds.
  if not anim.active:
    return (false, anim.targetCursorLine)

  if not config.enable:
    # Smooth scroll disabled, jump to target immediately
    anim.active = false
    return (false, anim.targetCursorLine)

  let now = getMonoTime()
  let elapsedMs = (now - anim.lastUpdateTime).inMicroseconds.float / 1000.0
  anim.lastUpdateTime = now

  # Physics simulation with fixed timestep for consistency
  # Always run at least one physics step per frame
  var remainingMs = max(elapsedMs, ScrollPhysicsInterval)
  let dt = ScrollPhysicsInterval / 1000.0 # Convert to seconds

  while remainingMs >= ScrollPhysicsInterval:
    # Apply friction (constant deceleration)
    if anim.velocity > 0:
      anim.velocity -= config.friction * dt
      if anim.velocity < 0:
        anim.velocity = 0
    elif anim.velocity < 0:
      anim.velocity += config.friction * dt
      if anim.velocity > 0:
        anim.velocity = 0

    # Apply air drag (velocity-proportional resistance)
    anim.velocity *= (1.0 - config.airDrag * dt)

    # Update position
    anim.currentCursorLine += anim.velocity * dt

    remainingMs -= ScrollPhysicsInterval

  # Clamp cursor position to valid buffer bounds
  let maxLine = max(0, bufferLen - 1).float
  if anim.currentCursorLine < 0:
    anim.currentCursorLine = 0
    anim.velocity = 0 # Stop at boundary
  elif anim.currentCursorLine > maxLine:
    anim.currentCursorLine = maxLine
    anim.velocity = 0 # Stop at boundary

  # Check if animation should end
  # Use distance to target instead of velocity direction
  let distanceToTarget = abs(anim.targetCursorLine.float - anim.currentCursorLine)
  let velocityStopped = abs(anim.velocity) < VelocityThreshold
  let closeEnough = distanceToTarget < 1.0

  if velocityStopped or closeEnough:
    # Animation complete - use current position, don't jump
    anim.active = false
    anim.velocity = 0.0
    # Use target if close enough, otherwise use current rounded position
    var finalCursorLine =
      if closeEnough: anim.targetCursorLine else: anim.currentCursorLine.int

    # Clamp final position to valid bounds
    finalCursorLine = clamp(finalCursorLine, 0, max(0, bufferLen - 1))

    # Update viewport to ensure cursor is visible
    let visibleHeight = max(1, mgr.viewport.height - reservedLines)
    if finalCursorLine > mgr.viewport.topLine + visibleHeight - 1:
      mgr.viewport.resetViewportTop(finalCursorLine - visibleHeight + 1)
    elif finalCursorLine < mgr.viewport.topLine:
      mgr.viewport.resetViewportTop(finalCursorLine)

    return (false, finalCursorLine)

  # Calculate current cursor line (rounded and clamped)
  let newCursorLine = clamp(anim.currentCursorLine.int, 0, max(0, bufferLen - 1))

  # Calculate viewport bounds
  let visibleHeight = max(1, mgr.viewport.height - reservedLines)

  # Viewport scrolls when cursor goes beyond screen edges
  var newTopLine = mgr.viewport.topLine
  let bottomEdge = newTopLine + visibleHeight - 1

  # Keep cursor visible - scroll viewport if cursor is outside visible area
  if newCursorLine > bottomEdge:
    # Cursor below viewport bottom - scroll down
    newTopLine = newCursorLine - visibleHeight + 1
  elif newCursorLine < newTopLine:
    # Cursor above viewport top - scroll up
    newTopLine = newCursorLine

  mgr.viewport.resetViewportTop(max(0, newTopLine))

  return (true, newCursorLine)

proc newMotionController*(
    buf: core.TextBuffer, state: EditorState, viewport: ViewPort
): MotionController =
  MotionController(
    executor: newMotionExecutor(buf),
    viewportManager: viewport.newViewportManager,
    cursorManager: newCursorManager(state),
  )

proc executeMotion*(
    controller: MotionController,
    cmd: MotionCommand,
    currentCursorPos: BufferPosition,
    updateViewport: bool = true,
): Result[BufferPosition, string] =
  ## Execute a motion command - main entry point
  ## Returns the new cursor position
  ## If updateViewport=false, skip viewport updates (useful for operator+motion combinations)

  # Check if this is a vertical motion (preserves preferred column)
  let isVerticalMotion =
    cmd.motion in {
      Motion.Up, Motion.Down, Motion.PageUp, Motion.PageDown, Motion.HalfPageUp,
      Motion.HalfPageDown,
    }

  # For vertical motion, use preferredColumn if set (>= 0)
  var effectiveX = currentCursorPos.column
  if isVerticalMotion and controller.cursorManager.state.preferredColumn >= 0:
    effectiveX = controller.cursorManager.state.preferredColumn

  # Convert to CursorPosition for internal calculations
  let currentPos = CursorPosition(x: effectiveX, y: currentCursorPos.line)

  # Calculate reserved lines (same logic as updateViewport)
  let actualReservedLines =
    if controller.cursorManager.state.windowDisplay.viewportReservedLines >= 0:
      controller.cursorManager.state.windowDisplay.viewportReservedLines
    else:
      steadyBottomAreaHeight()

  var newPos = controller.executor.calculateNewPosition(
    currentPos, cmd, controller.viewportManager.viewport.height,
    controller.viewportManager.viewport.topLine, actualReservedLines,
    controller.cursorManager.state.mode,
  )

  # Clamp to valid buffer bounds
  newPos = controller.cursorManager.clampPosition(newPos, controller.executor.buffer)

  # Get line wrap state (needed for viewport update and horizontal scroll)
  let lineWrap = controller.cursorManager.state.lineWrap

  # Update viewport to follow cursor with line wrap support (unless suppressed)
  if updateViewport:
    let
      lineCount = controller.executor.buffer.len
      viewportOffset =
        viewportOffsetFor(controller.executor.buffer, controller.cursorManager.state)

    controller.viewportManager.updateViewport(
      newPos, lineCount, controller.cursorManager.state.showStatusLine,
      controller.cursorManager.state.windowDisplay.viewportReservedLines, lineWrap,
      controller.executor.buffer, viewportOffset, controller.cursorManager.state.tabStop,
    )

  # Disable horizontal scrolling when line wrap is enabled
  if lineWrap:
    controller.viewportManager.viewport.leftColumn = 0

  # Update preferredColumn based on motion type
  if isVerticalMotion:
    # For vertical motion: preserve preferred column
    # If not set yet, initialize from original cursor position
    if controller.cursorManager.state.preferredColumn < 0:
      controller.cursorManager.state.preferredColumn = currentCursorPos.column
  else:
    # For non-vertical motion: reset preferred column to -1
    # Next vertical motion will initialize from current position
    controller.cursorManager.state.preferredColumn = -1

  # Return the new cursor position
  return ok(BufferPosition(line: newPos.y, column: newPos.x))

## Operator+motion classification.
##
## Linewise vs exclusive vs (default) inclusive determines how a motion
## combines with an operator (`d`, `y`, `c`, ...). These sets are the single
## source of truth -- `calculateOperatorRange` below and any external callers
## should consult `isLinewiseMotion`/`isExclusiveMotion` instead of re-listing
## the motions.

const LinewiseMotions* = {
  Motion.Up, Motion.Down, Motion.FirstLine, Motion.LastLine, Motion.PageUp,
  Motion.PageDown, Motion.HalfPageUp, Motion.HalfPageDown, Motion.ParagraphForward,
  Motion.ParagraphBackward, Motion.NextLineFirstNonBlank,
  Motion.PreviousLineFirstNonBlank,
}

const ExclusiveMotions* = {
  Motion.WordForward, # w
  Motion.WordBackward, # b
  Motion.Right, # l (when used with operator)
  Motion.Left, # h (when used with operator)
  Motion.Home, # 0
  Motion.FirstNonBlank, # ^
}

const NoMoveNoOpMotions* =
  LinewiseMotions + {
    Motion.Left, Motion.Home, Motion.FirstNonBlank, Motion.WordBackward
  }
  ## Motions whose "no move" outcome must be treated as a no-op by an operator
  ## (vim rings the bell). Excludes forward inclusive/right-exclusive motions
  ## (`l`, `w`, `e`, `$`) where the char under cursor is still a valid target.

func isLinewiseMotion*(motion: Motion): bool {.inline.} =
  ## True if the motion operates on whole lines for operator+motion semantics
  ## (e.g. `dj` deletes both lines fully). Vim-compatible classification.
  motion in LinewiseMotions

func isExclusiveMotion*(motion: Motion): bool {.inline.} =
  ## True if the motion is exclusive for operator+motion semantics
  ## (the character at endPos is NOT included). Vim-compatible classification.
  motion in ExclusiveMotions

proc lineContentNoNewline(buffer: TextBuffer, lineIdx: int): string =
  ## Get the content of a line excluding any trailing newline.
  ## Returns empty string when lineIdx is out of range.
  if lineIdx < 0 or lineIdx >= buffer.len:
    return ""
  let line = buffer.getLine(lineIdx)
  if line.len > 0 and line[^1] == '\n':
    line[0 ..< ^1]
  else:
    line

proc wordForwardReachesEol(buffer: TextBuffer, pos: BufferPosition): bool =
  ## True if `w` from `pos` runs past the last character on its line. When
  ## this happens, `dw` should delete through the last character instead of
  ## applying the usual exclusive (decrement-by-1) adjustment -- this is the
  ## "w stuck at last line of buffer" special case in Vim.
  if pos.line < 0 or pos.line >= buffer.len:
    return false
  let runes = lineContentNoNewline(buffer, pos.line).toRunes()
  skipWordForward(runes, pos.column) >= runes.len

proc calculateOperatorRange*(
    buffer: TextBuffer, startPos: BufferPosition, endPos: BufferPosition, motion: Motion
): OperatorRange =
  ## Calculate the range affected by an operator+motion combination
  ## Returns OperatorRange with proper start/end and linewise flag

  let isLinewise = motion.isLinewiseMotion()
  let isExclusive = motion.isExclusiveMotion()

  var range = OperatorRange(start: startPos, endPos: endPos, isLinewise: isLinewise)

  # Ensure start comes before end
  if range.start.line > range.endPos.line or (
    range.start.line == range.endPos.line and range.start.column > range.endPos.column
  ):
    swap(range.start, range.endPos)

  # For exclusive motions in characterwise mode, exclude the endPos character
  # by moving endPos back by 1 column (this matches Vim's behavior)
  if isExclusive and not isLinewise:
    # For WordForward (dw), if the motion crosses lines, stop at end of current line
    # Vim's dw does NOT delete the newline - it only deletes to end of line
    if motion == Motion.WordForward and range.endPos.line > range.start.line:
      range.endPos.line = range.start.line
      if range.start.line < buffer.len:
        let endCol = lineContentNoNewline(buffer, range.start.line).charLen - 1
        range.endPos.column = max(range.start.column, endCol)
    # Only adjust if we're not at the start of the range
    elif range.endPos.line == range.start.line and
        range.endPos.column > range.start.column:
      if motion == Motion.WordForward and wordForwardReachesEol(buffer, range.start):
        # w "stuck" at last line - delete to EOL without exclusive adjustment
        let endCol = lineContentNoNewline(buffer, range.start.line).charLen - 1
        range.endPos.column = max(range.start.column, endCol)
      else:
        # Standard exclusive adjustment (covers non-WordForward motions and
        # WordForward with a real next word on this line)
        range.endPos.column -= 1
    elif range.endPos.line > range.start.line and range.endPos.column > 0:
      # Different line - move column back
      range.endPos.column -= 1
    elif range.endPos.line > range.start.line and range.endPos.column == 0:
      # endPos.column == 0 on a different line: move to previous line's end
      range.endPos.line -= 1
      if range.endPos.line >= 0 and range.endPos.line < buffer.len:
        let endCol = lineContentNoNewline(buffer, range.endPos.line).charLen - 1
        range.endPos.column = max(0, endCol)

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

  if range.isEmpty:
    # An empty range (e.g. the inner of <a></a>) spans no characters.
    return ""

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
      let lineLen = line.charLen
      let startCol = min(range.start.column, lineLen)
      let endCol = min(range.endPos.column, lineLen)
      if endCol >= lineLen:
        # Range reaches the line end: include the trailing newline so the yanked
        # text matches what buffer.deleteRange removes (it joins the next line).
        if startCol < lineLen:
          text.add(line.runeSubStr(startCol))
        text.add("\n")
      elif startCol < lineLen:
        # Inclusive range to match buffer.deleteRange behavior.
        text.add(line.runeSubStr(startCol, endCol - startCol + 1))
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
            # Last line: from start to endPos.column (inclusive). When the range
            # reaches the line end, include the trailing newline so the yanked
            # text matches what buffer.deleteRange removes (it joins the lines).
            let lineLen = line.charLen
            let endCol = min(range.endPos.column, lineLen)
            if endCol >= lineLen:
              text.add(line)
              text.add("\n")
            else:
              text.add(line.runeSubStr(0, endCol + 1))
          else:
            # Middle lines: entire line
            text.add(line)
            if line.len == 0 or line[^1] != '\n':
              text.add("\n")

  return text

proc deleteLinesInRange(buffer: TextBuffer, range: OperatorRange): Result[(), string] =
  ## Delete every line the linewise range covers, keeping the buffer at one line.
  var brokeEarly = false
  for i in 0 .. (range.endPos.line - range.start.line):
    if range.start.line < buffer.len:
      if buffer.len == 1:
        brokeEarly = true
        break
      let deleteResult = buffer.deleteLine(range.start.line)
      if deleteResult.isErr:
        return err(deleteResult.error)

  if brokeEarly:
    let lastLine = buffer.getLine(0)
    if lastLine.len > 0:
      let clearResult = buffer.deleteRange(
        BufferPosition(line: 0, column: 0),
        BufferPosition(line: 0, column: lastLine.charLen - 1),
      )
      if clearResult.isErr:
        return err(clearResult.error)
  ok(())

proc deleteRange*(buffer: TextBuffer, range: OperatorRange): Result[(), string] =
  ## Delete text in the given range
  ## Used for delete and change operations

  if range.isEmpty:
    # An empty range deletes nothing (e.g. `cit`/`dit` on <a></a>).
    return ok(())

  if range.isLinewise:
    # Delete entire lines
    let lineCount = range.endPos.line - range.start.line + 1

    if lineCount > 1:
      let txr = withTransaction(buffer, "delete " & $lineCount & " lines"):
        let r = buffer.deleteLinesInRange(range)
        if r.isErr:
          return err(r.error)
      if txr.isErr:
        return err(txr.error)
    else:
      let r = buffer.deleteLinesInRange(range)
      if r.isErr:
        return err(r.error)
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

  # Case 1: Cursor is on whitespace
  if isWhitespace(runes[cursorCol]):
    if inner:
      # Inner whitespace: select the whitespace sequence
      var startCol = cursorCol
      while startCol > 0 and isWhitespace(runes[startCol - 1]):
        startCol.dec
      var endCol = cursorCol
      while endCol + 1 < runes.len and isWhitespace(runes[endCol + 1]):
        endCol.inc
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol),
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )
    else:
      # Around: skip whitespace and include the next word
      var wordStart = cursorCol
      while wordStart < runes.len and isWhitespace(runes[wordStart]):
        wordStart.inc

      if wordStart >= runes.len:
        # No word after whitespace on this line - search subsequent lines
        var foundLine = -1
        var nextCol = 0
        var nextEndCol = 0
        for searchLine in (cursor.line + 1) ..< buffer.len:
          let searchLineStr = buffer.getLine(searchLine)
          let searchRunes = searchLineStr.toRunes()
          var col = 0
          # Skip leading whitespace
          while col < searchRunes.len and isWhitespace(searchRunes[col]):
            col.inc
          if col < searchRunes.len:
            # Found a non-whitespace character
            foundLine = searchLine
            nextCol = col
            nextEndCol = col
            if isWordChar(searchRunes[col]):
              while nextEndCol + 1 < searchRunes.len and
                  isWordChar(searchRunes[nextEndCol + 1]):
                nextEndCol.inc
            elif isSymbolChar(searchRunes[col]):
              while nextEndCol + 1 < searchRunes.len and
                  isSymbolChar(searchRunes[nextEndCol + 1]):
                nextEndCol.inc
            break

        if foundLine >= 0:
          # Include leading whitespace on current line
          var startCol = cursorCol
          while startCol > 0 and isWhitespace(runes[startCol - 1]):
            startCol.dec
          return ok(
            TextObjectRange(
              start: BufferPosition(line: cursor.line, column: startCol),
              endPos: BufferPosition(line: foundLine, column: nextEndCol),
              isLinewise: false,
            )
          )

        # No word/WORD anywhere ahead: Vim's "aw"/"aW" needs a word to anchor the
        # surrounding whitespace, so it fails (no-op) here rather than selecting
        # the surrounding whitespace on its own. ("iw"/"iW" on whitespace still
        # selects the run via the inner branch above.)
        return err("No word for text object after whitespace")

      # Found word on same line after whitespace
      var endCol = wordStart
      if isWordChar(runes[wordStart]):
        while endCol + 1 < runes.len and isWordChar(runes[endCol + 1]):
          endCol.inc
      elif isSymbolChar(runes[wordStart]):
        while endCol + 1 < runes.len and isSymbolChar(runes[endCol + 1]):
          endCol.inc

      # Include leading whitespace
      var startCol = cursorCol
      while startCol > 0 and isWhitespace(runes[startCol - 1]):
        startCol.dec
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol),
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )

  # Case 2: Cursor is on a word character
  if isWordChar(runes[cursorCol]):
    var startCol = cursorCol
    while startCol > 0 and isWordChar(runes[startCol - 1]):
      startCol.dec

    var endCol = cursorCol
    while endCol + 1 < runes.len and isWordChar(runes[endCol + 1]):
      endCol.inc

    if inner:
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol),
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )
    else:
      # Around word: word + trailing whitespace
      var extendedEnd = endCol + 1
      while extendedEnd < runes.len and isWhitespace(runes[extendedEnd]):
        extendedEnd.inc

      if extendedEnd > endCol + 1:
        # Has trailing whitespace
        return ok(
          TextObjectRange(
            start: BufferPosition(line: cursor.line, column: startCol),
            endPos: BufferPosition(line: cursor.line, column: extendedEnd - 1),
            isLinewise: false,
          )
        )

      # No trailing whitespace, try leading
      if startCol > 0:
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
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )

  # Case 3: Cursor is on a symbol character
  if isSymbolChar(runes[cursorCol]):
    var startCol = cursorCol
    while startCol > 0 and isSymbolChar(runes[startCol - 1]):
      startCol.dec

    var endCol = cursorCol
    while endCol + 1 < runes.len and isSymbolChar(runes[endCol + 1]):
      endCol.inc

    if inner:
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol),
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )
    else:
      # Around symbol: symbols + trailing whitespace
      var extendedEnd = endCol + 1
      while extendedEnd < runes.len and isWhitespace(runes[extendedEnd]):
        extendedEnd.inc

      if extendedEnd > endCol + 1:
        return ok(
          TextObjectRange(
            start: BufferPosition(line: cursor.line, column: startCol),
            endPos: BufferPosition(line: cursor.line, column: extendedEnd - 1),
            isLinewise: false,
          )
        )

      # No trailing whitespace, try leading
      if startCol > 0:
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
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )

  return err("Unexpected character class")

proc findWideWordBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool
): Result[TextObjectRange, string] =
  ## Find WORD boundaries for iW (inner WORD) or aW (a WORD)
  ## WORD is any sequence of non-whitespace characters
  ## inner=true: just the WORD
  ## inner=false: WORD + trailing whitespace (or leading if no trailing)

  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  let line = buffer.getLine(cursor.line)
  let runes = line.toRunes()

  if runes.len == 0:
    return err("Empty line")

  let cursorCol = min(cursor.column, runes.len - 1)

  # Case 1: Cursor is on whitespace
  if isWhitespace(runes[cursorCol]):
    if inner:
      # Inner whitespace: select the whitespace sequence
      var startCol = cursorCol
      while startCol > 0 and isWhitespace(runes[startCol - 1]):
        startCol.dec
      var endCol = cursorCol
      while endCol + 1 < runes.len and isWhitespace(runes[endCol + 1]):
        endCol.inc
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol),
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )
    else:
      # Around: skip whitespace and include the next WORD
      var wordStart = cursorCol
      while wordStart < runes.len and isWhitespace(runes[wordStart]):
        wordStart.inc

      if wordStart >= runes.len:
        # No WORD after whitespace on this line - search subsequent lines
        var foundLine = -1
        var nextCol = 0
        var nextEndCol = 0
        for searchLine in (cursor.line + 1) ..< buffer.len:
          let searchLineStr = buffer.getLine(searchLine)
          let searchRunes = searchLineStr.toRunes()
          var col = 0
          while col < searchRunes.len and isWhitespace(searchRunes[col]):
            col.inc
          if col < searchRunes.len:
            foundLine = searchLine
            nextCol = col
            nextEndCol = col
            while nextEndCol + 1 < searchRunes.len and
                not isWhitespace(searchRunes[nextEndCol + 1]):
              nextEndCol.inc
            break

        if foundLine >= 0:
          var startCol = cursorCol
          while startCol > 0 and isWhitespace(runes[startCol - 1]):
            startCol.dec
          return ok(
            TextObjectRange(
              start: BufferPosition(line: cursor.line, column: startCol),
              endPos: BufferPosition(line: foundLine, column: nextEndCol),
              isLinewise: false,
            )
          )

        # No word/WORD anywhere ahead: Vim's "aw"/"aW" needs a word to anchor the
        # surrounding whitespace, so it fails (no-op) here rather than selecting
        # the surrounding whitespace on its own. ("iw"/"iW" on whitespace still
        # selects the run via the inner branch above.)
        return err("No word for text object after whitespace")

      # Found WORD on same line after whitespace
      var endCol = wordStart
      while endCol + 1 < runes.len and not isWhitespace(runes[endCol + 1]):
        endCol.inc

      var startCol = cursorCol
      while startCol > 0 and isWhitespace(runes[startCol - 1]):
        startCol.dec
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol),
          endPos: BufferPosition(line: cursor.line, column: endCol),
          isLinewise: false,
        )
      )

  # Case 2: Cursor is on a non-whitespace character (WORD)
  var startCol = cursorCol
  while startCol > 0 and not isWhitespace(runes[startCol - 1]):
    startCol.dec

  var endCol = cursorCol
  while endCol + 1 < runes.len and not isWhitespace(runes[endCol + 1]):
    endCol.inc

  if inner:
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol),
        endPos: BufferPosition(line: cursor.line, column: endCol),
        isLinewise: false,
      )
    )
  else:
    # Around WORD: WORD + trailing whitespace
    var extendedEnd = endCol + 1
    while extendedEnd < runes.len and isWhitespace(runes[extendedEnd]):
      extendedEnd.inc

    if extendedEnd > endCol + 1:
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol),
          endPos: BufferPosition(line: cursor.line, column: extendedEnd - 1),
          isLinewise: false,
        )
      )

    # No trailing whitespace, try leading
    if startCol > 0:
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
        endPos: BufferPosition(line: cursor.line, column: endCol),
        isLinewise: false,
      )
    )

proc isEscaped(runes: seq[Rune], idx: int): bool =
  ## Check if the character at idx is escaped by counting preceding backslashes
  var backslashCount = 0
  var i = idx - 1
  while i >= 0 and $runes[i] == "\\":
    backslashCount.inc
    i.dec
  # Odd number of backslashes means the character is escaped
  return backslashCount mod 2 == 1

proc findQuotedBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, quoteChar: char, inner: bool
): Result[TextObjectRange, string] =
  ## Find quoted string boundaries for i" or a"
  ## inner=true: content inside quotes
  ## inner=false: content + quotes
  ##
  ## Vim behavior:
  ## - If cursor is inside quotes, select that quoted region
  ## - If cursor is on a quote, select the region containing that quote
  ## - If cursor is outside quotes, search forward for next quote pair on the line

  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  let line = buffer.getLine(cursor.line)
  let runes = line.toRunes()

  if runes.len == 0:
    return err("Empty line")

  let cursorCol = min(cursor.column, runes.len - 1)

  # Collect all unescaped quote positions on the line
  var quotePositions: seq[int] = @[]
  for i in 0 ..< runes.len:
    if $runes[i] == $quoteChar and not isEscaped(runes, i):
      quotePositions.add(i)

  if quotePositions.len < 2:
    return err("No quote pair found")

  # Find which quote pair contains the cursor, or the next pair after cursor
  var startCol = -1
  var endCol = -1

  # Check each consecutive pair (0-1, 2-3, 4-5, ...)
  var pairIdx = 0
  while pairIdx + 1 < quotePositions.len:
    let pairStart = quotePositions[pairIdx]
    let pairEnd = quotePositions[pairIdx + 1]

    # Cursor is inside or on this pair
    if cursorCol >= pairStart and cursorCol <= pairEnd:
      startCol = pairStart
      endCol = pairEnd
      break

    # Cursor is before this pair - use this pair (Vim forward search behavior)
    if cursorCol < pairStart:
      startCol = pairStart
      endCol = pairEnd
      break

    pairIdx += 2

  if startCol < 0 or endCol < 0:
    return err("No quote pair found for cursor position")

  if inner:
    # Inner: content only (exclude quotes)
    if endCol <= startCol + 1:
      # Empty quotes like "": vim's `ci"` still enters Insert mode between
      # the quotes, so return an empty (no-op) range there.
      return ok(
        TextObjectRange(
          start: BufferPosition(line: cursor.line, column: startCol + 1),
          endPos: BufferPosition(line: cursor.line, column: startCol + 1),
          isLinewise: false,
          isEmpty: true,
        )
      )
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol + 1),
        endPos: BufferPosition(line: cursor.line, column: endCol - 1),
        isLinewise: false,
      )
    )
  else:
    # Around: content + quotes (deleteRange is inclusive, so endCol is correct)
    return ok(
      TextObjectRange(
        start: BufferPosition(line: cursor.line, column: startCol),
        endPos: BufferPosition(line: cursor.line, column: endCol),
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
  ## Find matching parenthesis/bracket/brace boundaries across multiple lines
  ## inner=true: content inside delimiters
  ## inner=false: content + delimiters

  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  # Search backward for opening delimiter
  var depth = 0
  var startLine = cursor.line
  var startCol = -1

  # Check if cursor is on a closing delimiter
  let cursorLine = buffer.getLine(cursor.line)
  let cursorRunes = cursorLine.toRunes()
  let cursorCol = min(cursor.column, max(0, cursorRunes.len - 1))

  if cursorRunes.len > 0 and cursorCol < cursorRunes.len and
      $cursorRunes[cursorCol] == $closeChar:
    depth = 1

  # Search backward from cursor position
  var searchLine = cursor.line
  var searchCol = cursorCol - (if depth > 0: 1 else: 0)

  block searchBackward:
    while searchLine >= 0:
      let line = buffer.getLine(searchLine)
      let runes = line.toRunes()

      # Adjust starting column for each line
      if searchLine < cursor.line:
        searchCol = runes.len - 1

      while searchCol >= 0:
        if searchCol < runes.len:
          if $runes[searchCol] == $closeChar:
            depth.inc
          elif $runes[searchCol] == $openChar:
            if depth == 0:
              startLine = searchLine
              startCol = searchCol
              break searchBackward
            else:
              depth.dec
              if depth == 0:
                startLine = searchLine
                startCol = searchCol
                break searchBackward
        searchCol.dec

      searchLine.dec
      if searchLine >= 0:
        let nextLine = buffer.getLine(searchLine)
        searchCol = nextLine.toRunes().len - 1

  if startCol < 0:
    return err("No opening delimiter found")

  # Search forward for closing delimiter
  var endLine = -1
  var endCol = -1
  depth = 0

  searchLine = startLine
  searchCol = startCol + 1

  block searchForward:
    while searchLine < buffer.len:
      let line = buffer.getLine(searchLine)
      let runes = line.toRunes()

      # Adjust starting column for each line
      if searchLine > startLine:
        searchCol = 0

      while searchCol < runes.len:
        if $runes[searchCol] == $openChar:
          depth.inc
        elif $runes[searchCol] == $closeChar:
          if depth == 0:
            endLine = searchLine
            endCol = searchCol
            break searchForward
          else:
            depth.dec
        searchCol.inc

      searchLine.inc
      searchCol = 0

  if endCol < 0:
    return err("No closing delimiter found")

  if inner:
    # Inner: content only (exclude delimiters)
    let startPos = BufferPosition(line: startLine, column: startCol + 1)
    if startLine == endLine:
      if endCol <= startCol + 1:
        # Empty delimiters like (): vim's `ci(` still enters Insert mode between
        # the delimiters, so return an empty (no-op) range there.
        return ok(
          TextObjectRange(
            start: startPos, endPos: startPos, isLinewise: false, isEmpty: true
          )
        )
      return ok(
        TextObjectRange(
          start: startPos,
          endPos: BufferPosition(line: endLine, column: endCol - 1),
          isLinewise: false,
        )
      )
    # Multi-line inner. When the close delimiter sits at column 0 the inner
    # content ends with the line break before it, so the inclusive end is the
    # previous line's end-of-content column -- deleting through that position
    # also consumes the trailing newline and joins the lines, collapsing a block
    # like `(\n  x\n)` to `()`. A naive `endCol - 1` here would be -1 and the
    # delete would fail. Otherwise the close shares a line with content and the
    # end is `endCol - 1` as usual.
    if endCol == 0 and startLine + 1 == endLine and
        startCol + 1 >= buffer.getLine(startLine).charLen:
      # Only the boundary newline lies between the delimiters (e.g. `(\n)`); the
      # inclusive range can't delete just that newline without clipping a
      # delimiter, so return an empty (no-op) range -- `ci(` still inserts here.
      let pos = BufferPosition(line: endLine, column: endCol)
      return
        ok(TextObjectRange(start: pos, endPos: pos, isLinewise: false, isEmpty: true))
    let endPos =
      if endCol == 0:
        BufferPosition(line: endLine - 1, column: buffer.getLine(endLine - 1).charLen)
      else:
        BufferPosition(line: endLine, column: endCol - 1)
    return ok(TextObjectRange(start: startPos, endPos: endPos, isLinewise: false))
  else:
    # Around: content + delimiters (deleteRange is inclusive, so endCol is correct)
    return ok(
      TextObjectRange(
        start: BufferPosition(line: startLine, column: startCol),
        endPos: BufferPosition(line: endLine, column: endCol),
        isLinewise: false,
      )
    )

proc lineRunesNoNl(buffer: TextBuffer, line: int): seq[Rune] =
  ## The line's runes with any trailing newline stripped. Out-of-range lines
  ## yield an empty seq (via lineContentNoNewline's bounds check).
  lineContentNoNewline(buffer, line).toRunes()

proc findParagraphBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool
): Result[TextObjectRange, string] =
  ## Paragraph text object (ip/ap). A paragraph is a run of non-blank lines
  ## delimited by blank lines; the object is linewise.
  if buffer.len == 0:
    return err("Empty buffer")
  if cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")

  let onBlank = isBlankLine(buffer.getLine(cursor.line))

  # Extend over the run of lines of the same kind (blank vs non-blank).
  var startLine = cursor.line
  while startLine > 0 and isBlankLine(buffer.getLine(startLine - 1)) == onBlank:
    startLine.dec
  var endLine = cursor.line
  while endLine < buffer.len - 1 and isBlankLine(buffer.getLine(endLine + 1)) == onBlank:
    endLine.inc

  if not inner:
    # Around: also take the following run of the opposite kind, or the preceding
    # run when there is nothing after (matches vim's ap).
    let prevEnd = endLine
    while endLine < buffer.len - 1 and
        isBlankLine(buffer.getLine(endLine + 1)) != onBlank:
      endLine.inc
    if endLine == prevEnd:
      while startLine > 0 and isBlankLine(buffer.getLine(startLine - 1)) != onBlank:
        startLine.dec

  return ok(
    TextObjectRange(
      start: BufferPosition(line: startLine, column: 0),
      endPos: BufferPosition(
        line: endLine, column: max(0, lineRunesNoNl(buffer, endLine).len - 1)
      ),
      isLinewise: true,
    )
  )

proc findSentenceBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool
): Result[TextObjectRange, string] =
  ## Sentence text object (is/as). A sentence ends at . ! ? (optionally followed
  ## by closing quotes/brackets) then whitespace or end of line, and never
  ## crosses a blank line. Charwise. Whitespace ownership follows vim: `is` on a
  ## space is the whitespace run; `as` keeps trailing whitespace or, for the last
  ## sentence, the leading whitespace. Trailing whitespace across a line break
  ## (the newline itself) is not pulled in.
  if buffer.len == 0 or cursor.line < 0 or cursor.line >= buffer.len:
    return err("Cursor position out of bounds")
  if isBlankLine(buffer.getLine(cursor.line)):
    return err("No sentence on a blank line")

  # Paragraph bounds — sentences never cross blank lines.
  var paraStart = cursor.line
  while paraStart > 0 and not isBlankLine(buffer.getLine(paraStart - 1)):
    paraStart.dec
  var paraEnd = cursor.line
  while paraEnd < buffer.len - 1 and not isBlankLine(buffer.getLine(paraEnd + 1)):
    paraEnd.inc

  # Flatten the paragraph into runes; inter-line breaks become a single space
  # separator. Instead of a BufferPosition per rune, keep per-line start offsets
  # (O(lines)) and map flat indices back on demand.
  let numLines = paraEnd - paraStart + 1
  var
    flat: seq[Rune]
    segStart = newSeq[int](numLines)
    lineLens = newSeq[int](numLines)
  for ln in paraStart .. paraEnd:
    let k = ln - paraStart
    segStart[k] = flat.len
    let lr = lineRunesNoNl(buffer, ln)
    lineLens[k] = lr.len
    for c in 0 ..< lr.len:
      flat.add lr[c]
    if ln < paraEnd:
      flat.add Rune(' ') # synthetic line-break separator

  if flat.len == 0:
    return err("Empty sentence")

  proc segmentOf(idx: int): int =
    ## Paragraph line (0-based) whose flat segment contains idx.
    var lo = 0
    var hi = numLines - 1
    while lo < hi:
      let mid = (lo + hi + 1) div 2
      if segStart[mid] <= idx:
        lo = mid
      else:
        hi = mid - 1
    lo

  proc flatToPos(idx: int): BufferPosition =
    let k = segmentOf(idx)
    BufferPosition(line: paraStart + k, column: idx - segStart[k])

  proc isSynthetic(idx: int): bool =
    ## True for a synthetic line-break separator (the cell right after a
    ## non-last line's content).
    let k = segmentOf(idx)
    k < numLines - 1 and idx - segStart[k] == lineLens[k]

  # Cursor index within the flattened paragraph, clamping a column past
  # end-of-line to the line's last index rather than snapping onto the next.
  var cursorIdx =
    if cursor.line < paraStart:
      0
    elif cursor.line > paraEnd:
      flat.len - 1
    else:
      let k = cursor.line - paraStart
      let maxCol =
        if k < numLines - 1:
          lineLens[k] # may land on the synthetic separator
        else:
          max(0, lineLens[k] - 1)
      segStart[k] + min(max(0, cursor.column), maxCol)

  proc isEnd(r: Rune): bool =
    let c = r.int32
    c == '.'.int32 or c == '!'.int32 or c == '?'.int32

  proc isCloser(r: Rune): bool =
    let c = r.int32
    c == ')'.int32 or c == ']'.int32 or c == '"'.int32 or c == '\''.int32

  # Sentence start indices within the paragraph.
  var starts = @[0]
  var i = 0
  while i < flat.len:
    if isEnd(flat[i]):
      var k = i + 1
      while k < flat.len and isCloser(flat[k]):
        k.inc
      if k < flat.len and isWhitespace(flat[k]):
        while k < flat.len and isWhitespace(flat[k]):
          k.inc
        if k < flat.len:
          starts.add k
        i = k
        continue
    i.inc

  # The sentence containing the cursor spans [s, nextStart - 1]. `starts` is
  # increasing, so a single pass finds both the last start <= cursor and the
  # first start past it.
  var s = 0
  var nextStart = flat.len
  for st in starts:
    if st <= cursorIdx:
      s = st
    else:
      nextStart = st
      break

  # Last non-whitespace char of this sentence (its terminator).
  var textEnd = nextStart - 1
  while textEnd > s and isWhitespace(flat[textEnd]):
    textEnd.dec

  # A cursor sitting on the whitespace run *between* two sentences is its own
  # object in vim: `is` is the whitespace, `as` is the whitespace plus the
  # following sentence. (Leading whitespace of the first sentence is part of its
  # text -- s is 0 there -- so this only fires between sentences. A synthetic
  # line break is excluded so a cursor clamped past end-of-line still selects
  # the sentence on its own line.)
  if cursorIdx > textEnd and nextStart < flat.len and not isSynthetic(cursorIdx):
    let wsStart = textEnd + 1
    if inner:
      var wsEnd = nextStart - 1
      while wsEnd > wsStart and isSynthetic(wsEnd):
        wsEnd.dec
      return ok(
        TextObjectRange(
          start: flatToPos(wsStart), endPos: flatToPos(wsEnd), isLinewise: false
        )
      )
    else:
      # Around: whitespace + the next sentence's text (without its own trailing).
      var nextEnd = flat.len - 1
      for st in starts:
        if st > nextStart:
          nextEnd = st - 1
          break
      while nextEnd > nextStart and isWhitespace(flat[nextEnd]):
        nextEnd.dec
      return ok(
        TextObjectRange(
          start: flatToPos(wsStart), endPos: flatToPos(nextEnd), isLinewise: false
        )
      )

  var endIdx = nextStart - 1
  if inner:
    # Inner drops trailing whitespace (and the synthetic line separators).
    while endIdx > s and isWhitespace(flat[endIdx]):
      endIdx.dec
  else:
    # Around keeps trailing whitespace but not a synthetic line-break edge.
    while endIdx > s and isSynthetic(endIdx):
      endIdx.dec
    # vim's `as`: when the last sentence has no trailing whitespace, include the
    # *leading* whitespace instead. Stay on the same line (skip synthetics).
    if endIdx == textEnd and nextStart == flat.len:
      while s > 0 and not isSynthetic(s - 1) and isWhitespace(flat[s - 1]):
        s.dec
  if endIdx < s:
    endIdx = s

  return ok(
    TextObjectRange(start: flatToPos(s), endPos: flatToPos(endIdx), isLinewise: false)
  )

proc findTagBoundariesInRange(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool, loLine, hiLine: int
): Result[TextObjectRange, string] =
  ## Windowed core of the tag text object: runs the same scan as
  ## findTagBoundaries but only over lines [loLine, hiLine]. A pair straddling
  ## the window edge is treated as unterminated here and picked up once the
  ## window grows to enclose it, so the result matches a full-buffer scan.

  # Flatten the window into runes (newlines kept so tags may span lines). `flat`
  # is O(window runes); the position map is only per-line start offsets
  # (window-local) with flat indices mapped back to absolute positions on demand
  # -- avoiding a BufferPosition per rune.
  let winLen = hiLine - loLine + 1
  var
    flat: seq[Rune]
    lineStart = newSeq[int](winLen + 1)
  for k in 0 ..< winLen:
    lineStart[k] = flat.len
    let lr = lineRunesNoNl(buffer, loLine + k)
    for c in 0 ..< lr.len:
      flat.add lr[c]
    flat.add Rune('\n')
  lineStart[winLen] = flat.len

  proc flatToPos(idx: int): BufferPosition =
    # Largest window line whose start offset is <= idx; column is the remainder.
    # The trailing newline of a line maps to column == line length (as before).
    var lo = 0
    var hi = winLen - 1
    while lo < hi:
      let mid = (lo + hi + 1) div 2
      if lineStart[mid] <= idx:
        lo = mid
      else:
        hi = mid - 1
    BufferPosition(line: loLine + lo, column: idx - lineStart[lo])

  proc isNameChar(r: Rune): bool =
    let c = r.int32
    isWordChar(r) or c == '-'.ord or c == ':'.ord or c == '.'.ord

  type
    TagKind = enum
      tkOpen
      tkClose

    Tag = object
      kind: TagKind
      name: string
      ltIdx: int # index of '<'
      gtIdx: int # index of '>'

  # Collect tag tokens.
  var tags: seq[Tag]
  let n = flat.len
  var i = 0
  while i < n:
    if flat[i].int32 == '<'.ord and i + 1 < n:
      let ltIdx = i
      var j = i + 1
      var kind = tkOpen
      if flat[j].int32 == '/'.ord:
        kind = tkClose
        j.inc
      elif flat[j].int32 == '!'.ord or flat[j].int32 == '?'.ord:
        # <!-- comment -->, <!doctype …>, <? … ?>: skip to '>' and ignore.
        while j < n and flat[j].int32 != '>'.ord:
          j.inc
        i = j + 1
        continue
      # Read the tag name. A '<' not followed by a tag name (a '<' used as a
      # less-than operator, or a lone '</') is not a tag -- treat it as a
      # literal char so it never swallows the real markup that follows.
      var name = ""
      while j < n and isNameChar(flat[j]):
        name.add $flat[j]
        j.inc
      if name.len == 0:
        i = ltIdx + 1
        continue
      # Scan to '>' honouring quotes; track self-closing.
      var selfClose = false
      while j < n and flat[j].int32 != '>'.ord:
        let c = flat[j].int32
        if c == '"'.ord or c == '\''.ord:
          j.inc
          while j < n and flat[j].int32 != c:
            j.inc
          if j < n:
            j.inc
        elif c == '/'.ord:
          selfClose = true
          j.inc
        else:
          if c != ' '.ord and c != '\t'.ord and c != '\n'.ord:
            selfClose = false
          j.inc
      if j >= n:
        # Unterminated tag (e.g. an unclosed quote ran to end of buffer):
        # recover by treating the '<' as a literal instead of dropping every
        # tag collected after it.
        i = ltIdx + 1
        continue
      let gtIdx = j
      if name.len > 0 and not selfClose:
        tags.add Tag(kind: kind, name: name, ltIdx: ltIdx, gtIdx: gtIdx)
      i = gtIdx + 1
    else:
      i.inc

  # Cursor index within the flattened window. Column is clamped to the line's
  # last *content* index (not its newline) so a position at/past end-of-line
  # never snaps onto the next line yet still falls inside a tag that ends the
  # line -- e.g. it/at with the cursor on the closing '>'.
  var cursorIdx =
    if cursor.line < 0:
      0
    elif cursor.line >= buffer.len:
      n - 1
    else:
      let k = clamp(cursor.line - loLine, 0, winLen - 1)
      let contentLen = lineStart[k + 1] - lineStart[k] - 1
      lineStart[k] + min(max(0, cursor.column), max(0, contentLen - 1))

  # Match open/close pairs with a stack; the first popped pair that encloses the
  # cursor is the innermost (closers pop inner pairs before outer ones).
  var stack: seq[Tag]
  var bestOpen, bestClose: Tag
  var found = false
  block matchTags:
    for t in tags:
      if t.kind == tkOpen:
        stack.add t
      else:
        # Find the nearest matching open. A stray closer (no matching open, e.g.
        # an orphan </br>) is ignored rather than discarding the still-open
        # enclosing tags; only the inner unmatched opens above a real match are
        # dropped (improperly nested markup).
        var matchIdx = -1
        for k in countdown(stack.high, 0):
          if stack[k].name == t.name:
            matchIdx = k
            break
        if matchIdx < 0:
          continue
        let mOpen = stack[matchIdx]
        stack.setLen(matchIdx)
        if mOpen.ltIdx <= cursorIdx and cursorIdx <= t.gtIdx:
          bestOpen = mOpen
          bestClose = t
          found = true
          break matchTags
  if not found:
    return err("Cursor is not inside a tag")

  if not inner:
    return ok(
      TextObjectRange(
        start: flatToPos(bestOpen.ltIdx),
        endPos: flatToPos(bestClose.gtIdx),
        isLinewise: false,
      )
    )
  else:
    # Inner: between the open tag's '>' and the close tag's '<'.
    let rawS = bestOpen.gtIdx + 1
    let rawE = bestClose.ltIdx - 1
    if rawS > rawE:
      # Empty tag like <a></a>: no inner content. vim's `cit` still works --
      # it drops the cursor between the tags and enters Insert mode -- so return
      # an empty (no-op) range at that position rather than failing the object.
      let pos = flatToPos(bestClose.ltIdx)
      return
        ok(TextObjectRange(start: pos, endPos: pos, isLinewise: false, isEmpty: true))
    # When the content occupies whole lines -- the open '>' is immediately
    # followed by a newline and the close '</' immediately preceded by one --
    # vim's `it` is linewise and `dit` removes the content lines rather than
    # leaving them blank.
    let wholeLines = flat[rawS].int32 == '\n'.ord and flat[rawE].int32 == '\n'.ord
    # Trim the boundary newlines so single-line content maps exactly.
    var s = rawS
    var e = rawE
    while s <= e and flat[s].int32 == '\n'.ord:
      s.inc
    while e >= s and flat[e].int32 == '\n'.ord:
      e.dec
    if s > e:
      # Multi-line empty tag like <a>\n</a>: the inner content is only
      # newlines. Treat it the same as <a></a> so `cit`/`dit`/`yit` work.
      let pos = flatToPos(bestClose.ltIdx)
      return
        ok(TextObjectRange(start: pos, endPos: pos, isLinewise: false, isEmpty: true))
    if wholeLines:
      return ok(
        TextObjectRange(
          start: BufferPosition(line: flatToPos(s).line, column: 0),
          endPos: flatToPos(e),
          isLinewise: true,
        )
      )
    return
      ok(TextObjectRange(start: flatToPos(s), endPos: flatToPos(e), isLinewise: false))

proc findTagBoundaries(
    buffer: TextBuffer, cursor: BufferPosition, inner: bool
): Result[TextObjectRange, string] =
  ## Tag text object (it/at). Matches the innermost <tag>…</tag> pair enclosing
  ## the cursor, honouring nesting, multi-line tags and quotes within a tag.
  ## Self-closing tags do not enclose. Note: inner content trims boundary
  ## newlines, so `dit` on multi-line tags removes the inner text but keeps the
  ## surrounding line breaks.
  ##
  ## Scans a window of lines centred on the cursor, quadrupling it until the
  ## enclosing pair is found or the whole buffer has been covered. A window can
  ## only miss tags, never invent a closer pair, so growing it reproduces the
  ## full-buffer result while keeping the common case proportional to the
  ## enclosing tag's size rather than the file's.
  if buffer.len == 0:
    return err("Empty buffer")

  let center = clamp(cursor.line, 0, buffer.len - 1)
  var radius = tagScanInitialRadius
  while true:
    let
      loLine = max(0, center - radius)
      hiLine = min(buffer.len - 1, center + radius)
    let res = findTagBoundariesInRange(buffer, cursor, inner, loLine, hiLine)
    if res.isOk or (loLine == 0 and hiLine == buffer.len - 1):
      return res
    # Quadruple rather than double: when the enclosing pair is far (or absent in
    # a huge buffer) this reaches the full buffer in fewer re-scans, bounding the
    # wasted re-tokenisation to ~1/3 of the final window instead of ~1x.
    radius *= 4

proc calculateBaseTextObjectRange(
    buffer: TextBuffer,
    cursor: BufferPosition,
    kind: TextObjectKind,
    modifier: TextObjectModifier,
): Result[TextObjectRange, string] =
  ## Range of a single text object (no count extension). See
  ## calculateTextObjectRange for the counted entry point.

  let inner = (modifier == tomInner)

  case kind
  of toWord:
    return findWordBoundaries(buffer, cursor, inner)
  of toWideWord:
    return findWideWordBoundaries(buffer, cursor, inner)
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
  of toSentence:
    return findSentenceBoundaries(buffer, cursor, inner)
  of toParagraph:
    return findParagraphBoundaries(buffer, cursor, inner)
  of toTag:
    return findTagBoundaries(buffer, cursor, inner)

proc nextObjectProbe(
    buffer: TextBuffer, fromLine, fromCol: int
): Option[BufferPosition] =
  ## Cursor position one cell past (fromLine, fromCol), wrapping to the next
  ## line's start at end of line. none() when that runs past the buffer.
  var line = fromLine
  var col = fromCol + 1
  if col >= buffer.getLine(line).toRunes().len:
    line.inc
    col = 0
  if line >= buffer.len:
    return none(BufferPosition)
  some(BufferPosition(line: line, column: col))

proc posBeforeTagOpen(buffer: TextBuffer, pos: BufferPosition): Option[BufferPosition] =
  ## Position one cell before pos, wrapping to the previous line's last column.
  ## none() at the very start of the buffer. Steps just outside the current tag
  ## so the enclosing tag is matched for the counted it/at object.
  if pos.column > 0:
    return some(BufferPosition(line: pos.line, column: pos.column - 1))
  if pos.line > 0:
    let prevLen = buffer.getLine(pos.line - 1).charLen
    return some(BufferPosition(line: pos.line - 1, column: max(0, prevLen - 1)))
  none(BufferPosition)

proc calculateTextObjectRange*(
    buffer: TextBuffer,
    cursor: BufferPosition,
    kind: TextObjectKind,
    modifier: TextObjectModifier,
    count: int = 1,
): Result[TextObjectRange, string] =
  ## Range of a text object, extended over `count` objects (d2iw, 2dap, d3is,
  ## 2dat). `count <= 1` is a single object. Counts are honoured for word/WORD,
  ## paragraph, sentence and tag; the bracket/quote kinds ignore it.
  let base = calculateBaseTextObjectRange(buffer, cursor, kind, modifier)
  if base.isErr or count <= 1:
    return base
  var toRange = base.value

  case kind
  of toWord, toWideWord:
    # Word/WORD model the gap (whitespace run) as its own counted object, so
    # stepping one cell past the current end lands in the next object. Inner for
    # the intermediate objects, the original modifier for the last.
    for i in 1 ..< count:
      let probe = nextObjectProbe(buffer, toRange.endPos.line, toRange.endPos.column)
      if probe.isNone:
        break
      let m = if i == count - 1: modifier else: tomInner
      let nextResult = calculateBaseTextObjectRange(buffer, probe.get, kind, m)
      if nextResult.isErr:
        break
      toRange.endPos = nextResult.value.endPos
  of toParagraph:
    # Each count selects one more whole paragraph of the SAME modifier (Nap = N
    # paragraphs incl. their trailing blank runs; Nip = N alternating runs).
    for i in 1 ..< count:
      let probe = nextObjectProbe(buffer, toRange.endPos.line, toRange.endPos.column)
      if probe.isNone:
        break
      let nextResult = calculateBaseTextObjectRange(buffer, probe.get, kind, modifier)
      if nextResult.isErr:
        break
      toRange.endPos = nextResult.value.endPos
  of toTag:
    # Tags nest, so each count selects the tag one level out (2at = the tag and
    # its parent). Re-probe from just before the current tag's '<'.
    for i in 1 ..< count:
      let around = calculateBaseTextObjectRange(buffer, toRange.start, kind, tomAround)
      if around.isErr:
        break
      let outer = posBeforeTagOpen(buffer, around.value.start)
      if outer.isNone:
        break
      let m = if i == count - 1: modifier else: tomAround
      let nextResult = calculateBaseTextObjectRange(buffer, outer.get, kind, m)
      if nextResult.isErr:
        break
      toRange = nextResult.value
  of toSentence:
    # A sentence owns its trailing whitespace, so walk forward by each segment's
    # *around* extent (one finder call per step); for an inner request, recompute
    # only the final segment as inner.
    var endAround = toRange.endPos
    var lastStart = toRange.start
    block sentenceCount:
      let firstAround =
        calculateBaseTextObjectRange(buffer, toRange.start, kind, tomAround)
      if firstAround.isErr:
        break sentenceCount
      endAround = firstAround.value.endPos
      var reached = 1
      while reached < count:
        let probe = nextObjectProbe(buffer, endAround.line, endAround.column)
        if probe.isNone:
          break
        let nextA = calculateBaseTextObjectRange(buffer, probe.get, kind, tomAround)
        if nextA.isErr:
          break
        endAround = nextA.value.endPos
        lastStart = nextA.value.start
        reached.inc
      if modifier == tomInner:
        let lastInner = calculateBaseTextObjectRange(buffer, lastStart, kind, tomInner)
        toRange.endPos = if lastInner.isOk: lastInner.value.endPos else: endAround
      else:
        toRange.endPos = endAround
  else:
    discard # bracket/quote kinds: count is not supported

  return ok(toRange)
