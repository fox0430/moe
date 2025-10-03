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

## Line-based Gap Buffer implementation

import std/strutils

const
  DEFAULT_GAP_SIZE = 32
  MIN_GAP_SIZE = 16
  GROWTH_FACTOR = 2

type
  Line = ref object
    content: string # Line content without newline character

  GapBuffer* = ref object
    lines: seq[Line] # Array of lines
    gapStart: int # Gap start line index
    gapEnd: int # Gap end line index
    logicalLineCount: int # Number of logical lines (excluding gap)

# Core Gap Buffer operations

proc newGapBuffer*(initialCapacity: int = DEFAULT_GAP_SIZE): GapBuffer =
  let capacity = max(initialCapacity, MIN_GAP_SIZE)
  var lines = newSeq[Line](capacity)
  # Always start with at least one empty line
  lines[0] = Line(content: "")
  GapBuffer(lines: lines, gapStart: 1, gapEnd: capacity, logicalLineCount: 1)

proc newGapBuffer*(text: string): GapBuffer =
  # Parse text into lines
  var
    linesList: seq[string]
    currentLine = ""

  for ch in text:
    if ch == '\n':
      linesList.add(currentLine)
      currentLine = ""
    else:
      currentLine.add(ch)

  # Always add the last line (even if empty, which represents text ending with newline)
  linesList.add(currentLine)

  let
    lineCount = linesList.len
    capacity = max(lineCount + DEFAULT_GAP_SIZE, MIN_GAP_SIZE)

  var lines = newSeq[Line](capacity)
  for i in 0 ..< lineCount:
    lines[i] = Line(content: linesList[i])

  GapBuffer(
    lines: lines, gapStart: lineCount, gapEnd: capacity, logicalLineCount: lineCount
  )

proc gapSize(gb: GapBuffer): int {.inline.} =
  gb.gapEnd - gb.gapStart

proc capacity(gb: GapBuffer): int {.inline.} =
  gb.lines.len

proc logicalToPhysical(gb: GapBuffer, logicalLine: int): int {.inline.} =
  ## Convert logical line number to physical buffer line index
  if logicalLine < gb.gapStart:
    logicalLine
  else:
    logicalLine + gb.gapSize

proc ensureGapSize(gb: GapBuffer, minSize: int) =
  ## Ensure gap has at least minSize lines
  if gb.gapSize >= minSize:
    return

  let
    currentCapacity = gb.capacity
    requiredSize = gb.logicalLineCount + minSize
    newCapacity = max(currentCapacity * GROWTH_FACTOR, requiredSize + DEFAULT_GAP_SIZE)

  var newLines = newSeq[Line](newCapacity)

  # Copy prefix (before gap)
  for i in 0 ..< gb.gapStart:
    newLines[i] = gb.lines[i]

  # Copy suffix (after gap) to end of new buffer
  let suffixStart = newCapacity - (gb.capacity() - gb.gapEnd)
  for i in gb.gapEnd ..< gb.capacity():
    newLines[suffixStart + (i - gb.gapEnd)] = gb.lines[i]

  gb.lines = newLines
  gb.gapEnd = suffixStart

proc moveGapTo(gb: GapBuffer, lineNumber: int) =
  ## Move gap to specified logical line number
  let clampedLine = max(0, min(lineNumber, gb.logicalLineCount))

  if clampedLine == gb.gapStart:
    return

  if clampedLine < gb.gapStart:
    # Move gap left
    let
      moveCount = gb.gapStart - clampedLine
      srcStart = clampedLine
      dstStart = gb.gapEnd - moveCount

    # Move lines from before gap to after gap
    for i in countdown(moveCount - 1, 0):
      gb.lines[dstStart + i] = gb.lines[srcStart + i]

    gb.gapStart = clampedLine
    gb.gapEnd -= moveCount
  else:
    # Move gap right
    let
      moveCount = clampedLine - gb.gapStart
      srcStart = gb.gapEnd
      dstStart = gb.gapStart

    # Move lines from after gap to before gap
    for i in 0 ..< moveCount:
      gb.lines[dstStart + i] = gb.lines[srcStart + i]

    gb.gapStart = clampedLine
    gb.gapEnd += moveCount

# Character-based operations (for API compatibility)

proc positionToLineCol(gb: GapBuffer, position: int): tuple[line: int, col: int] =
  ## Convert character position to (line, column)
  var
    pos = position
    lineIdx = 0

  while lineIdx < gb.logicalLineCount:
    let
      physicalLine = gb.logicalToPhysical(lineIdx)
      line = gb.lines[physicalLine]
      lineLen = if line.isNil: 0 else: line.content.len

    if pos <= lineLen:
      return (lineIdx, pos)

    # +1 for newline character
    pos -= (lineLen + 1)
    inc lineIdx

  # Position beyond end of buffer
  if gb.logicalLineCount > 0:
    let
      lastPhysicalLine = gb.logicalToPhysical(gb.logicalLineCount - 1)
      lastLine = gb.lines[lastPhysicalLine]
      lastLineLen = if lastLine.isNil: 0 else: lastLine.content.len
    return (gb.logicalLineCount - 1, lastLineLen)
  else:
    return (0, 0)

proc lineColToPosition(gb: GapBuffer, line: int, col: int): int =
  ## Convert (line, column) to character position
  var pos = 0

  for i in 0 ..< min(line, gb.logicalLineCount):
    let
      physicalLine = gb.logicalToPhysical(i)
      lineObj = gb.lines[physicalLine]
      lineLen = if lineObj.isNil: 0 else: lineObj.content.len
    pos += lineLen + 1 # +1 for newline

  pos + col

proc insert*(gb: GapBuffer, position: int, text: string) =
  ## Insert text at the specified character position
  if text.len == 0:
    return

  let (targetLine, targetCol) = gb.positionToLineCol(position)

  # Split text into lines
  var
    newLines: seq[string]
    currentLine = ""

  for ch in text:
    if ch == '\n':
      newLines.add(currentLine)
      currentLine = ""
    else:
      currentLine.add(ch)

  if newLines.len == 0:
    # No newlines, simple insertion within a line
    if targetLine >= gb.logicalLineCount:
      # Insert at end, add new line
      gb.ensureGapSize(1)
      gb.moveGapTo(gb.logicalLineCount)
      gb.lines[gb.gapStart] = Line(content: text)
      gb.gapStart += 1
      gb.logicalLineCount += 1
    else:
      # Insert within existing line
      let physicalLine = gb.logicalToPhysical(targetLine)
      var line = gb.lines[physicalLine]
      if line.isNil:
        line = Line(content: "")
        gb.lines[physicalLine] = line

      let col = min(targetCol, line.content.len)
      line.content.insert(text, col)
  else:
    # Text contains newlines, need to split current line and insert multiple lines
    # newLines = text before each '\n', currentLine = text after last '\n'
    # Total lines created = newLines.len + 1

    if targetLine >= gb.logicalLineCount:
      # Appending at end - add all new lines
      let linesToAdd = newLines.len + 1
      gb.ensureGapSize(linesToAdd)
      gb.moveGapTo(gb.logicalLineCount)

      for i, lineText in newLines:
        gb.lines[gb.gapStart + i] = Line(content: lineText)

      # Always add final line after the newlines (even if empty)
      gb.lines[gb.gapStart + newLines.len] = Line(content: currentLine)

      gb.gapStart += linesToAdd
      gb.logicalLineCount += linesToAdd
    else:
      # Splitting existing line - replace 1 line with (newLines.len + 1) lines
      let physicalLine = gb.logicalToPhysical(targetLine)
      var originalLine = gb.lines[physicalLine]
      if originalLine.isNil:
        originalLine = Line(content: "")

      let
        col = min(targetCol, originalLine.content.len)
        prefix =
          if col > 0:
            originalLine.content[0 ..< col]
          else:
            ""
        suffix =
          if col < originalLine.content.len:
            originalLine.content[col .. ^1]
          else:
            ""

      # We replace current line and add newLines.len new lines
      let linesToAdd = newLines.len
      gb.ensureGapSize(linesToAdd)
      gb.moveGapTo(targetLine + 1) # Move gap to after current line

      # Update current line with prefix + first part of inserted text
      gb.lines[gb.logicalToPhysical(targetLine)] = Line(content: prefix & newLines[0])

      # Insert remaining lines
      var insertIdx = 0
      for i in 1 ..< newLines.len:
        gb.lines[gb.gapStart + insertIdx] = Line(content: newLines[i])
        inc insertIdx

      # Always add final line when splitting (continuation after last newline)
      gb.lines[gb.gapStart + insertIdx] = Line(content: currentLine & suffix)
      inc insertIdx

      gb.gapStart += insertIdx
      gb.logicalLineCount += insertIdx

proc insert*(gb: GapBuffer, position: int, ch: char) =
  ## Insert a single character at the specified position
  gb.insert(position, $ch)

proc delete*(gb: GapBuffer, position: int, count: int = 1) =
  ## Delete count characters starting from position
  if count <= 0:
    return

  let (startLine, startCol) = gb.positionToLineCol(position)
  let (endLine, endCol) = gb.positionToLineCol(position + count)

  if startLine == endLine:
    # Delete within single line
    if startLine >= gb.logicalLineCount:
      return

    let physicalLine = gb.logicalToPhysical(startLine)
    var line = gb.lines[physicalLine]
    if line.isNil:
      return

    let
      actualStartCol = min(startCol, line.content.len)
      actualEndCol = min(endCol, line.content.len)

    if actualStartCol < actualEndCol:
      # Delete characters by reconstructing string
      let
        prefix =
          if actualStartCol > 0:
            line.content[0 ..< actualStartCol]
          else:
            ""
        suffix =
          if actualEndCol < line.content.len:
            line.content[actualEndCol .. ^1]
          else:
            ""
      line.content = prefix & suffix
  else:
    # Delete spans multiple lines
    # Get content before moving gap
    let
      startPhysicalLine = gb.logicalToPhysical(startLine)
      endPhysicalLine = gb.logicalToPhysical(endLine)

    var startLineObj = gb.lines[startPhysicalLine]
    if startLineObj.isNil:
      startLineObj = Line(content: "")

    var endLineObj = gb.lines[endPhysicalLine]
    if endLineObj.isNil:
      endLineObj = Line(content: "")

    let
      startActualCol = min(startCol, startLineObj.content.len)
      endActualCol = min(endCol, endLineObj.content.len)

    # Merge start line prefix with end line suffix
    let
      prefix =
        if startActualCol > 0:
          startLineObj.content[0 ..< startActualCol]
        else:
          ""
      suffix =
        if endActualCol < endLineObj.content.len:
          endLineObj.content[endActualCol .. ^1]
        else:
          ""

    # Move gap and update
    gb.moveGapTo(startLine + 1)

    # Update start line with merged content
    gb.lines[gb.logicalToPhysical(startLine)] = Line(content: prefix & suffix)

    # Delete lines in between (including endLine)
    let linesToDelete = endLine - startLine
    if linesToDelete > 0:
      gb.gapEnd += linesToDelete
      gb.logicalLineCount -= linesToDelete

proc len*(gb: GapBuffer): int =
  ## Get total character length (including newlines)
  result = 0
  for i in 0 ..< gb.logicalLineCount:
    let physicalLine = gb.logicalToPhysical(i)
    let line = gb.lines[physicalLine]
    if not line.isNil:
      result += line.content.len
    # Add newline for all lines except the last
    if i < gb.logicalLineCount - 1:
      inc result

proc charAt*(gb: GapBuffer, position: int): char =
  ## Get character at character position
  # Validate position is within valid range
  # Allow position == len() for virtual newline at end of last line
  if position < 0 or position > gb.len():
    raise newException(IndexDefect, "GapBuffer index out of bounds")

  let (line, col) = gb.positionToLineCol(position)

  if line >= gb.logicalLineCount:
    raise newException(IndexDefect, "GapBuffer index out of bounds")

  let
    physicalLine = gb.logicalToPhysical(line)
    lineObj = gb.lines[physicalLine]

  if lineObj.isNil or col >= lineObj.content.len:
    if col == lineObj.content.len:
      # Return newline at end of line (including virtual newline at end of last line)
      return '\n'
    raise newException(IndexDefect, "GapBuffer index out of bounds")

  lineObj.content[col]

proc substring*(gb: GapBuffer, start: int, length: int): string =
  ## Extract substring from start position with given length
  if length <= 0:
    return ""

  result = ""

  for i in 0 ..< length:
    if start + i >= gb.len:
      break
    result.add(gb.charAt(start + i))

proc `$`*(gb: GapBuffer): string =
  ## Convert entire buffer to string
  if gb.logicalLineCount == 0:
    return ""

  for i in 0 ..< gb.logicalLineCount:
    let
      physicalLine = gb.logicalToPhysical(i)
      line = gb.lines[physicalLine]

    if not line.isNil:
      result.add(line.content)

    if i < gb.logicalLineCount - 1:
      result.add('\n')

proc clear*(gb: GapBuffer) =
  ## Clear all content
  gb.gapStart = 0
  gb.gapEnd = gb.capacity()
  gb.logicalLineCount = 0

proc findChar*(gb: GapBuffer, ch: char, start: int = 0): int =
  ## Find first occurrence of character starting from start position
  ## Returns -1 if not found
  var pos = start
  let (startLine, startCol) = gb.positionToLineCol(start)

  for lineIdx in startLine ..< gb.logicalLineCount:
    let
      physicalLine = gb.logicalToPhysical(lineIdx)
      line = gb.lines[physicalLine]

    if line.isNil:
      if ch == '\n':
        return pos
      inc pos
      continue

    let searchStart = if lineIdx == startLine: startCol else: 0

    for i in searchStart ..< line.content.len:
      if line.content[i] == ch:
        return pos + (i - searchStart)

    pos += line.content.len - searchStart

    if ch == '\n' and lineIdx < gb.logicalLineCount - 1:
      return pos

    inc pos # For newline

  return -1

proc findString*(gb: GapBuffer, pattern: string, start: int = 0): int =
  ## Find first occurrence of pattern starting from start position
  ## Returns -1 if not found
  if pattern.len == 0:
    return start

  # Convert to string and search (simple implementation)
  let
    text = $gb
    found = text.find(pattern, start)
  return found

proc replace*(gb: GapBuffer, start: int, length: int, replacement: string) =
  ## Replace length characters at start with replacement text
  gb.delete(start, length)
  gb.insert(start, replacement)

# Line-based operations

proc findLineStart*(gb: GapBuffer, position: int): int =
  ## Find start of line containing position
  let (line, _) = gb.positionToLineCol(position)
  gb.lineColToPosition(line, 0)

proc findLineEnd*(gb: GapBuffer, position: int): int =
  ## Find end of line containing position
  let (line, _) = gb.positionToLineCol(position)

  if line >= gb.logicalLineCount:
    return position

  let
    physicalLine = gb.logicalToPhysical(line)
    lineObj = gb.lines[physicalLine]
    lineLen = if lineObj.isNil: 0 else: lineObj.content.len

  gb.lineColToPosition(line, lineLen)

proc getLine*(gb: GapBuffer, lineNumber: int): string =
  ## Get content of specific line (0-based, without newline)
  if lineNumber < 0 or lineNumber >= gb.logicalLineCount:
    return ""

  let physicalLine = gb.logicalToPhysical(lineNumber)
  let line = gb.lines[physicalLine]

  if line.isNil:
    return ""

  line.content

proc lineCount*(gb: GapBuffer): int =
  ## Count number of lines
  gb.logicalLineCount

proc insertLine*(gb: GapBuffer, lineNumber: int, content: string) =
  ## Insert a new line at the specified line number
  gb.ensureGapSize(1)

  let targetLine = max(0, min(lineNumber, gb.logicalLineCount))
  gb.moveGapTo(targetLine)

  gb.lines[gb.gapStart] = Line(content: content)
  gb.gapStart += 1
  gb.logicalLineCount += 1

proc deleteLine*(gb: GapBuffer, lineNumber: int) =
  ## Delete the specified line
  if lineNumber < 0 or lineNumber >= gb.logicalLineCount:
    return

  gb.moveGapTo(lineNumber)

  # Expand gap to include the line
  gb.gapEnd += 1
  gb.logicalLineCount -= 1

# Iterator support

iterator chars*(gb: GapBuffer): char =
  for i in 0 ..< gb.logicalLineCount:
    let
      physicalLine = gb.logicalToPhysical(i)
      line = gb.lines[physicalLine]

    if not line.isNil:
      for ch in line.content:
        yield ch

    if i < gb.logicalLineCount - 1:
      yield '\n'

iterator lines*(gb: GapBuffer): string =
  for i in 0 ..< gb.logicalLineCount:
    yield gb.getLine(i)

# Bracket operators for convenient access

proc `[]`*(gb: GapBuffer, position: int): char =
  ## Get character at logical position using [] operator
  gb.charAt(position)

proc `[]`*(gb: GapBuffer, slice: HSlice[int, int]): string =
  ## Get substring using slice notation gb[start..end]
  let
    start = max(0, slice.a)
    endPos = slice.b

  if start > endPos:
    return ""

  let length = endPos - start + 1
  gb.substring(start, length)

proc `[]=`*(gb: GapBuffer, position: int, ch: char) =
  ## Set character at logical position using [] operator
  let (line, col) = gb.positionToLineCol(position)

  if line >= gb.logicalLineCount:
    raise newException(IndexDefect, "GapBuffer index out of bounds")

  let physicalLine = gb.logicalToPhysical(line)
  var lineObj = gb.lines[physicalLine]

  if lineObj.isNil:
    lineObj = Line(content: "")
    gb.lines[physicalLine] = lineObj

  if col >= lineObj.content.len:
    raise newException(IndexDefect, "GapBuffer index out of bounds")

  lineObj.content[col] = ch

proc `[]=`*(gb: GapBuffer, slice: HSlice[int, int], text: string) =
  ## Replace range with text using slice notation gb[start..end] = text
  let
    start = max(0, slice.a)
    endPos = slice.b

  if start > endPos:
    gb.insert(start, text)
  else:
    let deleteLength = endPos - start + 1
    gb.replace(start, deleteLength, text)

# Memory usage

proc estimateMemoryUsage*(gb: GapBuffer): int =
  ## Estimate memory usage in bytes
  result = sizeof(GapBuffer) + gb.capacity * sizeof(Line)

  for i in 0 ..< gb.logicalLineCount:
    let
      physicalLine = gb.logicalToPhysical(i)
      line = gb.lines[physicalLine]
    if not line.isNil:
      result += sizeof(Line) + line.content.len

# Debug information

proc getGapInfo*(gb: GapBuffer): tuple[start: int, size: int, capacity: int] =
  ## Get gap information for debugging (in lines, not characters)
  (start: gb.gapStart, size: gb.gapSize, capacity: gb.capacity)
