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

const
  DEFAULT_GAP_SIZE = 1024
  MIN_GAP_SIZE = 512
  GROWTH_FACTOR = 1.5

type GapBuffer* = ref object
  buffer: seq[char]
  gapStart: int
  gapEnd: int
  length: int # Logical length (excluding gap)

proc newGapBuffer*(initialCapacity: int = DEFAULT_GAP_SIZE): GapBuffer =
  let capacity = max(initialCapacity, MIN_GAP_SIZE)
  GapBuffer(buffer: newSeq[char](capacity), gapStart: 0, gapEnd: capacity, length: 0)

proc newGapBuffer*(text: string): GapBuffer =
  let textLen = text.len
  let capacity = max(textLen + DEFAULT_GAP_SIZE, MIN_GAP_SIZE)

  result = GapBuffer(
    buffer: newSeq[char](capacity), gapStart: textLen, gapEnd: capacity, length: textLen
  )

  # Copy text before gap
  for i in 0 ..< textLen:
    result.buffer[i] = text[i]

proc gapSize(gb: GapBuffer): int {.inline.} =
  gb.gapEnd - gb.gapStart

proc capacity(gb: GapBuffer): int {.inline.} =
  gb.buffer.len

proc logicalToPhysical(gb: GapBuffer, logicalPos: int): int {.inline.} =
  ## Convert logical position to physical buffer position
  if logicalPos < gb.gapStart:
    logicalPos
  else:
    logicalPos + gb.gapSize()

proc ensureGapSize(gb: GapBuffer, minSize: int) =
  ## Ensure gap has at least minSize characters
  if gb.gapSize() >= minSize:
    return

  let currentCapacity = gb.capacity()
  let requiredSize = gb.length + minSize
  let newCapacity =
    max(int(float(currentCapacity) * GROWTH_FACTOR), requiredSize + DEFAULT_GAP_SIZE)

  var newBuffer = newSeq[char](newCapacity)

  # Copy prefix (before gap)
  for i in 0 ..< gb.gapStart:
    newBuffer[i] = gb.buffer[i]

  # Copy suffix (after gap) to end of new buffer
  let suffixStart = newCapacity - (gb.capacity() - gb.gapEnd)
  for i in gb.gapEnd ..< gb.capacity():
    newBuffer[suffixStart + (i - gb.gapEnd)] = gb.buffer[i]

  gb.buffer = newBuffer
  gb.gapEnd = suffixStart

proc moveGapTo(gb: GapBuffer, position: int) =
  ## Move gap to specified logical position
  let clampedPos = max(0, min(position, gb.length))

  if clampedPos == gb.gapStart:
    return

  if clampedPos < gb.gapStart:
    # Move gap left
    let moveCount = gb.gapStart - clampedPos
    let srcStart = clampedPos
    let dstStart = gb.gapEnd - moveCount

    # Move characters from before gap to after gap
    for i in countdown(moveCount - 1, 0):
      gb.buffer[dstStart + i] = gb.buffer[srcStart + i]

    gb.gapStart = clampedPos
    gb.gapEnd -= moveCount
  else:
    # Move gap right
    let moveCount = clampedPos - gb.gapStart
    let srcStart = gb.gapEnd
    let dstStart = gb.gapStart

    # Move characters from after gap to before gap
    for i in 0 ..< moveCount:
      gb.buffer[dstStart + i] = gb.buffer[srcStart + i]

    gb.gapStart = clampedPos
    gb.gapEnd += moveCount

proc insert*(gb: GapBuffer, position: int, text: string) =
  ## Insert text at the specified position
  if text.len == 0:
    return

  let clampedPos = max(0, min(position, gb.length))

  # Ensure gap is large enough
  gb.ensureGapSize(text.len)

  # Move gap to insertion point
  gb.moveGapTo(clampedPos)

  # Insert characters into gap
  for i, ch in text:
    gb.buffer[gb.gapStart + i] = ch

  gb.gapStart += text.len
  gb.length += text.len

proc insert*(gb: GapBuffer, position: int, ch: char) =
  ## Insert a single character at the specified position
  let clampedPos = max(0, min(position, gb.length))

  gb.ensureGapSize(1)
  gb.moveGapTo(clampedPos)

  gb.buffer[gb.gapStart] = ch
  gb.gapStart += 1
  gb.length += 1

proc delete*(gb: GapBuffer, position: int, count: int = 1) =
  ## Delete count characters starting from position
  if count <= 0:
    return

  let clampedPos = max(0, min(position, gb.length))
  let actualCount = min(count, gb.length - clampedPos)

  if actualCount <= 0:
    return

  # Move gap to deletion point
  gb.moveGapTo(clampedPos)

  # Expand gap to include deleted characters
  gb.gapEnd += actualCount
  gb.length -= actualCount

proc charAt*(gb: GapBuffer, position: int): char =
  ## Get character at logical position
  if position < 0 or position >= gb.length:
    raise newException(IndexDefect, "GapBuffer index out of bounds")

  let physicalPos = gb.logicalToPhysical(position)
  gb.buffer[physicalPos]

proc substring*(gb: GapBuffer, start: int, length: int): string =
  ## Extract substring from start position with given length
  if start < 0 or start >= gb.length or length <= 0:
    return ""

  let actualLength = min(length, gb.length - start)
  result = newString(actualLength)

  for i in 0 ..< actualLength:
    result[i] = gb.charAt(start + i)

proc `$`*(gb: GapBuffer): string =
  ## Convert entire buffer to string
  if gb.length == 0:
    return ""

  result = newString(gb.length)
  var resultIndex = 0

  # Copy prefix (before gap)
  for i in 0 ..< gb.gapStart:
    result[resultIndex] = gb.buffer[i]
    inc resultIndex

  # Copy suffix (after gap)
  for i in gb.gapEnd ..< gb.capacity():
    result[resultIndex] = gb.buffer[i]
    inc resultIndex

proc clear*(gb: GapBuffer) =
  ## Clear all content
  gb.gapStart = 0
  gb.gapEnd = gb.capacity()
  gb.length = 0

proc len*(gb: GapBuffer): int {.inline.} =
  ## Get logical length of buffer
  gb.length

proc findChar*(gb: GapBuffer, ch: char, start: int = 0): int =
  ## Find first occurrence of character starting from start position
  ## Returns -1 if not found
  for i in start ..< gb.length:
    if gb.charAt(i) == ch:
      return i
  return -1

proc findString*(gb: GapBuffer, pattern: string, start: int = 0): int =
  ## Find first occurrence of pattern starting from start position
  ## Returns -1 if not found
  if pattern.len == 0:
    return start

  for i in start ..< (gb.length - pattern.len + 1):
    var match = true
    for j in 0 ..< pattern.len:
      if gb.charAt(i + j) != pattern[j]:
        match = false
        break
    if match:
      return i

  return -1

proc replace*(gb: GapBuffer, start: int, length: int, replacement: string) =
  ## Replace length characters at start with replacement text
  gb.delete(start, length)
  gb.insert(start, replacement)

# Line-based operations
proc findLineStart*(gb: GapBuffer, position: int): int =
  ## Find start of line containing position
  var pos = min(position, gb.length - 1)
  while pos > 0 and gb.charAt(pos - 1) != '\n':
    dec pos
  pos

proc findLineEnd*(gb: GapBuffer, position: int): int =
  ## Find end of line containing position
  var pos = min(position, gb.length - 1)
  while pos < gb.length and gb.charAt(pos) != '\n':
    inc pos
  pos

proc getLine*(gb: GapBuffer, lineNumber: int): string =
  ## Get content of specific line (0-based, without newline)
  var currentLine = 0
  var lineStart = 0

  # Find start of target line
  while lineStart < gb.length and currentLine < lineNumber:
    if gb.charAt(lineStart) == '\n':
      inc currentLine
      inc lineStart
    else:
      inc lineStart

  if currentLine < lineNumber:
    return "" # Line doesn't exist

  # Find end of line
  var lineEnd = lineStart
  while lineEnd < gb.length and gb.charAt(lineEnd) != '\n':
    inc lineEnd

  if lineEnd > lineStart:
    gb.substring(lineStart, lineEnd - lineStart)
  else:
    ""

proc lineCount*(gb: GapBuffer): int =
  ## Count number of lines
  result = 1
  for i in 0 ..< gb.length:
    if gb.charAt(i) == '\n':
      inc result

proc insertLine*(gb: GapBuffer, lineNumber: int, content: string) =
  ## Insert a new line at the specified line number
  if lineNumber <= 0:
    gb.insert(0, content & "\n")
  else:
    var currentLine = 0
    var pos = 0

    # Find insertion point
    while pos < gb.length and currentLine < lineNumber:
      if gb.charAt(pos) == '\n':
        inc currentLine
      inc pos

    if currentLine == lineNumber:
      gb.insert(pos, content & "\n")
    else:
      # Line number beyond end, append
      gb.insert(gb.length, "\n" & content)

proc deleteLine*(gb: GapBuffer, lineNumber: int) =
  ## Delete the specified line
  var currentLine = 0
  var lineStart = 0

  # Find start of target line
  while lineStart < gb.length and currentLine < lineNumber:
    if gb.charAt(lineStart) == '\n':
      inc currentLine
      inc lineStart
    else:
      inc lineStart

  if currentLine < lineNumber:
    return # Line doesn't exist

  # Determine if this is the last line
  var isLastLine = true
  var tempPos = lineStart
  while tempPos < gb.length:
    if gb.charAt(tempPos) == '\n':
      isLastLine = false
      break
    inc tempPos

  # Determine deletion strategy to ensure line count decreases by exactly 1
  var lineEnd = lineStart

  # Find end of line content
  while lineEnd < gb.length and gb.charAt(lineEnd) != '\n':
    inc lineEnd

  if lineNumber == 0:
    # First line: always include trailing newline if it exists to maintain structure
    if lineEnd < gb.length and gb.charAt(lineEnd) == '\n':
      inc lineEnd
  else:
    # For non-first lines, we need to delete exactly one line separator
    # Strategy: always include the preceding newline, never the trailing one
    if lineStart > 0:
      dec lineStart

  gb.delete(lineStart, lineEnd - lineStart)

# Iterator support
iterator chars*(gb: GapBuffer): char =
  for i in 0 ..< gb.length:
    yield gb.charAt(i)

iterator lines*(gb: GapBuffer): string =
  let numLines = gb.lineCount()
  for i in 0 ..< numLines:
    yield gb.getLine(i)

# Memory usage
proc estimateMemoryUsage*(gb: GapBuffer): int =
  ## Estimate memory usage in bytes
  sizeof(GapBuffer) + gb.capacity() * sizeof(char)

# Debug information
proc getGapInfo*(gb: GapBuffer): tuple[start: int, size: int, capacity: int] =
  ## Get gap information for debugging
  (start: gb.gapStart, size: gb.gapSize(), capacity: gb.capacity())
