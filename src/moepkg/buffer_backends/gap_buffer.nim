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

## Line-based Gap Buffer implementation

const
  DEFAULT_GAP_SIZE = 32
  MIN_GAP_SIZE = 16
  GROWTH_FACTOR = 2

type
  GapBuffer* = ref object
    lines: seq[string] # Array of line contents
    gapStart: int # Gap start line index
    gapEnd: int # Gap end line index

  DeletionRange = object
    ## Represents the range of a deletion operation for internal use
    startLine: int
    startCol: int
    endLine: int
    endCol: int

# Core Gap Buffer operations

proc newGapBuffer*(initialCapacity: int = DEFAULT_GAP_SIZE): GapBuffer =
  let capacity = max(initialCapacity, MIN_GAP_SIZE)
  var lines = newSeq[string](capacity)
  # Always start with at least one empty line
  lines[0] = ""
  GapBuffer(lines: lines, gapStart: 1, gapEnd: capacity)

proc newGapBuffer*(text: sink string): GapBuffer =
  # Parse text into lines (POSIX standard: newline is line terminator, not separator)
  # The trailing newline is NOT stored as an empty line - it's managed by TextBuffer.endOfLine
  var
    linesList: seq[string]
    currentLine = ""

  for ch in text:
    if ch == '\n':
      linesList.add(currentLine)
      currentLine = ""
    else:
      currentLine.add(ch)

  # Add remaining content as last line only if:
  # - There's content in currentLine (text doesn't end with newline), OR
  # - The text is empty (need at least one line in buffer)
  # This ensures "hello\n" = 1 line, "hello" = 1 line, "hello\n\n" = 2 lines
  if currentLine.len > 0 or linesList.len == 0:
    linesList.add(currentLine)

  let
    lineCount = linesList.len
    capacity = max(lineCount + DEFAULT_GAP_SIZE, MIN_GAP_SIZE)

  var lines = newSeq[string](capacity)
  for i in 0 ..< lineCount:
    lines[i] = linesList[i]

  GapBuffer(lines: lines, gapStart: lineCount, gapEnd: capacity)

proc gapSize(gb: GapBuffer): int {.inline.} =
  gb.gapEnd - gb.gapStart

proc capacity(gb: GapBuffer): int {.inline.} =
  gb.lines.len

proc lineCount*(gb: GapBuffer): int {.inline.} =
  ## Count number of lines
  gb.capacity - gb.gapSize

proc len*(gb: GapBuffer): int {.inline.} =
  ## Return line count (alias for lineCount)
  gb.lineCount

proc logicalToPhysical(gb: GapBuffer, logicalLine: int): int {.inline.} =
  ## Convert logical line number to physical buffer line index
  if logicalLine < gb.gapStart:
    logicalLine
  else:
    logicalLine + gb.gapSize

proc ensureGapSize(gb: GapBuffer, minSize: int) =
  ## Ensure gap has at least minSize lines
  ##
  ## Performance: O(n) when resize needed (amortized O(1) with 2x growth).
  ## Under ORC `seq[string]` assignment deep-copies the payload, so the old
  ## buffer (replaced just below) is drained with `move`: each line's payload
  ## is transferred in O(1) rather than copying every line's bytes.
  if gb.gapSize >= minSize:
    return

  let
    currentCapacity = gb.capacity
    requiredSize = gb.lineCount + minSize
    newCapacity = max(currentCapacity * GROWTH_FACTOR, requiredSize + DEFAULT_GAP_SIZE)

  var newLines = newSeq[string](newCapacity)

  # Move prefix (before gap); the old buffer is discarded below, so this is safe.
  for i in 0 ..< gb.gapStart:
    newLines[i] = move(gb.lines[i])

  # Move suffix (after gap) to end of new buffer.
  let suffixStart = newCapacity - (gb.capacity() - gb.gapEnd)
  for i in gb.gapEnd ..< gb.capacity():
    newLines[suffixStart + (i - gb.gapEnd)] = move(gb.lines[i])

  gb.lines = newLines
  gb.gapEnd = suffixStart

proc moveGapTo(gb: GapBuffer, lineNumber: int) =
  ## Move gap to specified logical line number
  ##
  ## Performance:
  ## - Best case: O(1) - gap already at target position
  ## - Worst case: O(n) where n = distance to move
  ## - Amortized: O(1) with locality of reference
  ##
  ## Lines are relocated with `move()` (O(1) pointer transfer per line, no string
  ## payload copy). Left movement runs in reverse and right movement forward so the
  ## relocation stays correct even when src/dst overlap (i.e. moveCount > gapSize).
  let clampedLine = max(0, min(lineNumber, gb.lineCount))

  if clampedLine == gb.gapStart:
    return

  if clampedLine < gb.gapStart:
    # Move gap left
    let
      moveCount = gb.gapStart - clampedLine
      srcStart = clampedLine
      dstStart = gb.gapEnd - moveCount

    # Reverse order keeps move() correct when src/dst overlap (moveCount > gapSize)
    for i in countdown(moveCount - 1, 0):
      gb.lines[dstStart + i] = move(gb.lines[srcStart + i])

    gb.gapStart = clampedLine
    gb.gapEnd -= moveCount
  else:
    # Move gap right
    let
      moveCount = clampedLine - gb.gapStart
      srcStart = gb.gapEnd
      dstStart = gb.gapStart

    # Forward order keeps move() correct when src/dst overlap (dst < src here)
    for i in 0 ..< moveCount:
      gb.lines[dstStart + i] = move(gb.lines[srcStart + i])

    gb.gapStart = clampedLine
    gb.gapEnd += moveCount

proc insertIntoLine*(gb: GapBuffer, line, col: int, text: string) =
  ## Insert text into an existing line at (line, column) position
  ## Note: col is expected to be a byte position, not a character position
  ## Use buffer.nim's insertText for Unicode-aware insertion
  ##
  ## Raises IndexDefect if line or col is out of valid range
  ## Valid range: line [0..len), col [0..lineLen]
  if line < 0 or line >= gb.len:
    raise newException(IndexDefect, "GapBuffer line out of bounds: " & $line)

  let physicalLine = gb.logicalToPhysical(line)
  var lineObj = gb.lines[physicalLine]

  if col < 0 or col > lineObj.len:
    raise newException(
      IndexDefect,
      "GapBuffer column out of valid range [0.." & $lineObj.len & "]: " & $col,
    )

  lineObj.insert(text, col)
  gb.lines[physicalLine] = lineObj

proc findDeletionEndPos(gb: GapBuffer, line, col, count: int): DeletionRange =
  ## Calculate the end position for a deletion of 'count' bytes
  ## starting from (line, col)
  var
    endLine = line
    endCol = col
    remaining = count

  while remaining > 0 and endLine < gb.len:
    let
      physicalLine = gb.logicalToPhysical(endLine)
      lineObj = gb.lines[physicalLine]
      lineLen = lineObj.len

    let availableInLine = lineLen - endCol
    if remaining <= availableInLine:
      # Deletion ends within this line
      endCol += remaining
      remaining = 0
      break
    else:
      # Delete to end of line
      remaining -= availableInLine

      # Try to consume newline
      if remaining > 0 and endLine < gb.len - 1:
        remaining -= 1 # consume newline
        endCol = 0
        inc endLine
      else:
        # No more newlines, end at end of current line
        endCol = lineLen
        break

  # Clamp to valid positions
  if endLine >= gb.len:
    endLine = gb.len - 1

  let
    endPhysicalLine = gb.logicalToPhysical(endLine)
    endLineObj = gb.lines[endPhysicalLine]
    endLineLen = endLineObj.len

  if endCol > endLineLen:
    endCol = endLineLen

  DeletionRange(startLine: line, startCol: col, endLine: endLine, endCol: endCol)

proc deleteSingleLine(gb: GapBuffer, line, startCol, endCol: int) =
  ## Delete within a single line from startCol to endCol (byte positions)
  let
    physicalLine = gb.logicalToPhysical(line)
    lineObj = gb.lines[physicalLine]
    prefix =
      if startCol > 0 and startCol <= lineObj.len:
        lineObj[0 ..< startCol]
      else:
        ""
    suffix =
      if endCol < lineObj.len:
        lineObj[endCol .. ^1]
      else:
        ""

  gb.lines[physicalLine] = prefix & suffix

proc deleteMultiLine(gb: GapBuffer, range: DeletionRange) =
  ## Delete across multiple lines, merging start and end lines
  let
    startPhysicalLine = gb.logicalToPhysical(range.startLine)
    startLineObj = gb.lines[startPhysicalLine]
    endPhysicalLine = gb.logicalToPhysical(range.endLine)
    endLineObj = gb.lines[endPhysicalLine]

  # Build the merged line
  let prefix =
    if range.startCol > 0 and range.startCol <= startLineObj.len:
      startLineObj[0 ..< range.startCol]
    else:
      ""

  let suffix =
    if range.endCol < endLineObj.len:
      endLineObj[range.endCol .. ^1]
    else:
      ""

  # Move gap to after start line
  gb.moveGapTo(range.startLine + 1)

  # Update start line with merged content
  gb.lines[gb.logicalToPhysical(range.startLine)] = prefix & suffix

  # Delete all lines from startLine+1 to endLine (inclusive)
  let linesToDelete = range.endLine - range.startLine
  if linesToDelete > 0:
    gb.gapEnd += linesToDelete

proc deleteAtLineCol*(gb: GapBuffer, line: int, col: int, count: int = 1) =
  ## Delete 'count' bytes starting from (line, column) position
  ## Note: 'col' and 'count' are in bytes, not characters
  ## Use buffer.nim's deleteChar for Unicode-aware deletion
  ##
  ## Performance:
  ## - Single line: O(1) amortized
  ## - Multi-line: O(k) where k = number of lines deleted
  ## Valid range: line [0..len), col [0..lineLen], count >= 1
  if count <= 0:
    raise newException(IndexDefect, "GapBuffer delete count must be > 0")
  if line < 0 or line >= gb.len:
    raise newException(IndexDefect, "GapBuffer line out of bounds: " & $line)

  let range = gb.findDeletionEndPos(line, col, count)

  if range.startLine == range.endLine:
    gb.deleteSingleLine(range.startLine, range.startCol, range.endCol)
  else:
    gb.deleteMultiLine(range)

proc `$`*(gb: GapBuffer): string =
  ## Convert entire buffer to string
  ## Each line gets a newline EXCEPT the final line (unless it's empty)
  ## Empty final line represents explicit trailing newline in the original content
  if gb.len == 0:
    return ""

  for i in 0 ..< gb.len:
    let
      physicalLine = gb.logicalToPhysical(i)
      line = gb.lines[physicalLine]

    result.add(line)
    # Add newline: between all lines, and after last line if it's empty
    let isLastLine = i == gb.len - 1
    if not isLastLine or (isLastLine and line.len == 0 and gb.len > 1):
      result.add('\n')

proc clear*(gb: GapBuffer) =
  ## Clear all content and reset to single empty line
  gb.lines[0] = ""
  gb.gapStart = 1
  gb.gapEnd = gb.capacity()

proc getLine*(gb: GapBuffer, lineNumber: int): string =
  ## Get content of specific line (0-based, without newline)
  if lineNumber < 0 or lineNumber >= gb.len:
    return ""

  let physicalLine = gb.logicalToPhysical(lineNumber)
  gb.lines[physicalLine]

proc charAtLineCol*(gb: GapBuffer, line: int, col: int): char =
  ## Get the byte at (line, col) position (col is a byte offset)
  if line < 0 or line >= gb.len:
    raise newException(IndexDefect, "GapBuffer line out of bounds")

  let
    physicalLine = gb.logicalToPhysical(line)
    lineObj = gb.lines[physicalLine]

  if col >= 0 and col < lineObj.len:
    return lineObj[col]
  elif col == lineObj.len and line < gb.len - 1:
    # At end of line (but not last line) - return newline
    return '\n'
  else:
    raise newException(IndexDefect, "GapBuffer column out of bounds")

proc replaceLine*(gb: GapBuffer, lineNumber: int, content: string) =
  ## Replace the content of a specific line
  ## Raises IndexDefect if lineNumber is out of bounds
  if lineNumber < 0 or lineNumber >= gb.len:
    raise newException(IndexDefect, "GapBuffer line out of bounds")

  let physicalLine = gb.logicalToPhysical(lineNumber)
  gb.lines[physicalLine] = content

proc `[]`*(gb: GapBuffer, lineNumber: int): string =
  ## Bracket operator for accessing lines by index
  gb.getLine(lineNumber)

proc `[]=`*(gb: GapBuffer, lineNumber: int, content: string) =
  ## Bracket operator for replacing line content
  gb.replaceLine(lineNumber, content)

proc insertLine*(gb: GapBuffer, lineNumber: int, content: string) =
  ## Insert a new line at the specified line number
  ## Raises IndexDefect if lineNumber is out of valid range [0..len]
  ##
  ## Performance: O(1) amortized - may trigger gap resize O(n)
  ## Valid range: [0..len] (inclusive of len for appending)
  if lineNumber < 0 or lineNumber > gb.len:
    raise newException(
      IndexDefect, "GapBuffer line index out of valid range [0.." & $gb.len & "]"
    )

  gb.ensureGapSize(1)

  gb.moveGapTo(lineNumber)

  gb.lines[gb.gapStart] = content
  gb.gapStart += 1

proc deleteLine*(gb: GapBuffer, lineNumber: int) =
  ## Delete the specified line
  ## Raises IndexDefect if lineNumber is out of bounds
  ##
  ## Performance: O(1) amortized
  ## Valid range: [0..len) (exclusive of len)
  if lineNumber < 0 or lineNumber >= gb.len:
    raise newException(IndexDefect, "GapBuffer line out of bounds")

  gb.moveGapTo(lineNumber)

  # Expand gap to include the line
  gb.gapEnd += 1

proc modifyLineContent*(gb: GapBuffer, lineNumber: int, f: proc(s: var string)) =
  ## Modify line content in-place using a function
  ## Raises IndexDefect if lineNumber is out of bounds
  if lineNumber < 0 or lineNumber >= gb.len:
    raise newException(IndexDefect, "GapBuffer line out of bounds")

  let physicalLine = gb.logicalToPhysical(lineNumber)
  var line = gb.lines[physicalLine]
  f(line)
  gb.lines[physicalLine] = line

# Iterator support

iterator chars*(gb: GapBuffer): char =
  ## Iterate over each byte in the buffer, including newlines
  ## Consistent with $ operator: newlines between lines, trailing newline only for explicit empty final line
  for i in 0 ..< gb.len:
    let
      physicalLine = gb.logicalToPhysical(i)
      line = gb.lines[physicalLine]

    for ch in line:
      yield ch

    # Add newline: between all lines, and after last line if it's empty
    let isLastLine = i == gb.len - 1
    if not isLastLine or (isLastLine and line.len == 0 and gb.len > 1):
      yield '\n'

iterator lines*(gb: GapBuffer): string =
  for i in 0 ..< gb.len:
    yield gb.getLine(i)

# Memory usage

proc estimateMemoryUsage*(gb: GapBuffer): int =
  ## Estimate memory usage in bytes
  ## `capacity * sizeof(string)` already covers every slot's inline string
  ## header (used + gap), so the per-line term counts only the heap content
  ## bytes — adding sizeof(string) again here would double-count the header.
  result = sizeof(GapBuffer) + gb.capacity * sizeof(string)

  for i in 0 ..< gb.len:
    let
      physicalLine = gb.logicalToPhysical(i)
      line = gb.lines[physicalLine]
    result += line.len

# Debug information

proc getGapInfo*(gb: GapBuffer): tuple[start: int, size: int, capacity: int] =
  ## Get gap information for debugging (in lines, not characters)
  (start: gb.gapStart, size: gb.gapSize, capacity: gb.capacity)
