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

## Sqrt Decomposition (Block List) buffer backend
##
## Stores lines in blocks of approximately √n lines each.
## All operations are O(√n). No gap movement needed for random access,
## making this suitable for large files with scattered edit patterns.

const
  DEFAULT_BLOCK_SIZE* = 256
  MAX_BLOCK_SIZE = 1024
  MERGE_THRESHOLD = 32

type
  Block = object
    lines: seq[string]

  SqrtDecomp* = ref object
    blocks: seq[Block]
    cachedLineCount: int
    cachedCharLen: int # Total character count including newlines between lines

proc recalcCharLen(sd: SqrtDecomp) =
  ## Recalculate total character length (including newlines between lines)
  sd.cachedCharLen = 0
  for b in sd.blocks:
    for line in b.lines:
      sd.cachedCharLen += line.len
  # Add newlines between lines (lineCount - 1 newlines for lineCount lines)
  if sd.cachedLineCount > 1:
    sd.cachedCharLen += sd.cachedLineCount - 1

proc newSqrtDecomp*(): SqrtDecomp =
  ## Create an empty SqrtDecomp buffer with a single empty line
  result =
    SqrtDecomp(blocks: @[Block(lines: @[""])], cachedLineCount: 1, cachedCharLen: 0)

proc newSqrtDecomp*(text: string): SqrtDecomp =
  ## Create a SqrtDecomp buffer from text string.
  ## Uses same line-parsing semantics as GapBuffer:
  ## - POSIX: newline is line terminator, not separator
  ## - "hello\n" = 1 line, "hello\n\n" = 2 lines
  ## - Trailing newline is NOT stored as empty line (managed by TextBuffer.endOfLine)
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
  if currentLine.len > 0 or linesList.len == 0:
    linesList.add(currentLine)

  # Distribute lines into blocks of DEFAULT_BLOCK_SIZE
  var blocks: seq[Block] = @[]
  var i = 0
  while i < linesList.len:
    let blockEnd = min(i + DEFAULT_BLOCK_SIZE, linesList.len)
    blocks.add(Block(lines: linesList[i ..< blockEnd]))
    i = blockEnd

  result = SqrtDecomp(blocks: blocks, cachedLineCount: linesList.len, cachedCharLen: 0)
  result.recalcCharLen()

proc findBlock(sd: SqrtDecomp, lineNumber: int): tuple[blockIdx, localIdx: int] =
  ## Find which block contains the given logical line number.
  ## Returns (blockIdx, localIdx) where localIdx is the index within the block.
  var accumulated = 0
  for i in 0 ..< sd.blocks.len:
    let blockLen = sd.blocks[i].lines.len
    if lineNumber < accumulated + blockLen:
      return (i, lineNumber - accumulated)
    accumulated += blockLen
  # Past end - return last position
  if sd.blocks.len > 0:
    let lastBlock = sd.blocks.len - 1
    return (lastBlock, sd.blocks[lastBlock].lines.len)
  return (0, 0)

proc maybeSplit(sd: SqrtDecomp, blockIdx: int) =
  ## Split a block if it exceeds MAX_BLOCK_SIZE
  if blockIdx >= sd.blocks.len:
    return
  if sd.blocks[blockIdx].lines.len <= MAX_BLOCK_SIZE:
    return

  let
    mid = sd.blocks[blockIdx].lines.len div 2
    secondHalf = sd.blocks[blockIdx].lines[mid .. ^1]

  sd.blocks[blockIdx].lines.setLen(mid)
  sd.blocks.insert(Block(lines: secondHalf), blockIdx + 1)

proc maybeMerge(sd: SqrtDecomp, blockIdx: int) =
  ## Merge a block with its neighbor if it's below MERGE_THRESHOLD
  if blockIdx >= sd.blocks.len:
    return
  if sd.blocks[blockIdx].lines.len >= MERGE_THRESHOLD:
    return
  if sd.blocks.len <= 1:
    return # Don't merge the last block

  # Try merging with next block
  if blockIdx < sd.blocks.len - 1:
    let combinedLen = sd.blocks[blockIdx].lines.len + sd.blocks[blockIdx + 1].lines.len
    if combinedLen <= MAX_BLOCK_SIZE:
      sd.blocks[blockIdx].lines.add(sd.blocks[blockIdx + 1].lines)
      sd.blocks.delete(blockIdx + 1)
      return

  # Try merging with previous block
  if blockIdx > 0:
    let combinedLen = sd.blocks[blockIdx - 1].lines.len + sd.blocks[blockIdx].lines.len
    if combinedLen <= MAX_BLOCK_SIZE:
      sd.blocks[blockIdx - 1].lines.add(sd.blocks[blockIdx].lines)
      sd.blocks.delete(blockIdx)

proc lineCount*(sd: SqrtDecomp): int {.inline.} =
  ## Count number of lines
  sd.cachedLineCount

proc len*(sd: SqrtDecomp): int {.inline.} =
  ## Return line count (alias for lineCount)
  sd.cachedLineCount

proc charLen*(sd: SqrtDecomp): int =
  ## Return total character count (including newlines between lines)
  sd.cachedCharLen

proc findLineStart*(sd: SqrtDecomp, lineNumber: int): int =
  ## Return the linear index of the start of the given line
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    return -1

  result = 0
  var lineNum = 0
  for b in sd.blocks:
    for line in b.lines:
      if lineNum == lineNumber:
        return result
      result += line.len + 1 # +1 for newline
      inc lineNum

proc findLineEnd*(sd: SqrtDecomp, lineNumber: int): int =
  ## Return the linear index of the end of the given line (last character position)
  ## Returns -1 if lineNumber is invalid or line is empty
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    return -1

  let lineStart = sd.findLineStart(lineNumber)
  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  lineStart + sd.blocks[blockIdx].lines[localIdx].len - 1

proc getLine*(sd: SqrtDecomp, lineNumber: int): string =
  ## Get content of specific line (0-based, without newline)
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    return ""

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  sd.blocks[blockIdx].lines[localIdx]

proc `[]`*(sd: SqrtDecomp, lineNumber: int): string =
  ## Bracket operator for accessing lines by index
  sd.getLine(lineNumber)

proc `[]=`*(sd: SqrtDecomp, lineNumber: int, content: string) =
  ## Bracket operator for replacing line content
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  let oldLen = sd.blocks[blockIdx].lines[localIdx].len
  sd.blocks[blockIdx].lines[localIdx] = content
  sd.cachedCharLen += content.len - oldLen

proc replaceLine*(sd: SqrtDecomp, lineNumber: int, content: string) =
  ## Replace the content of a specific line
  ## Raises IndexDefect if lineNumber is out of bounds
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  let oldLen = sd.blocks[blockIdx].lines[localIdx].len
  sd.blocks[blockIdx].lines[localIdx] = content
  sd.cachedCharLen += content.len - oldLen

proc modifyLineContent*(sd: SqrtDecomp, lineNumber: int, f: proc(s: var string)) =
  ## Modify line content in-place using a function
  ## Raises IndexDefect if lineNumber is out of bounds
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  let oldLen = sd.blocks[blockIdx].lines[localIdx].len
  var line = sd.blocks[blockIdx].lines[localIdx]
  f(line)
  sd.blocks[blockIdx].lines[localIdx] = line
  sd.cachedCharLen += line.len - oldLen

proc charAtLineCol*(sd: SqrtDecomp, line: int, col: int): char =
  ## Get character at (line, column) position
  if line < 0 or line >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(line)
  let lineObj = sd.blocks[blockIdx].lines[localIdx]

  if col >= 0 and col < lineObj.len:
    return lineObj[col]
  elif col == lineObj.len and line < sd.cachedLineCount - 1:
    # At end of line (but not last line) - return newline
    return '\n'
  else:
    raise newException(IndexDefect, "SqrtDecomp column out of bounds")

proc charAt*(sd: SqrtDecomp, index: int): char =
  ## Get character at linear index position
  ## Treats buffer as a flat sequence of characters with newlines between lines
  if index < 0:
    raise newException(IndexDefect, "SqrtDecomp index out of bounds: " & $index)

  var remaining = index
  var lineNum = 0

  for b in sd.blocks:
    for line in b.lines:
      let lineLen = line.len

      if remaining < lineLen:
        return line[remaining]
      elif remaining == lineLen and lineNum < sd.cachedLineCount - 1:
        return '\n'
      else:
        remaining -= lineLen
        if lineNum < sd.cachedLineCount - 1:
          remaining -= 1 # Account for newline
      inc lineNum

  raise newException(IndexDefect, "SqrtDecomp index out of bounds: " & $index)

proc indexToLineCol*(sd: SqrtDecomp, index: int): tuple[line: int, col: int] =
  ## Convert linear index to (line, column) position
  ## Returns (-1, -1) for invalid index
  if index < 0:
    return (-1, -1)

  var
    remaining = index
    lineNum = 0

  for b in sd.blocks:
    for line in b.lines:
      let lineLen = line.len

      if remaining <= lineLen:
        return (lineNum, remaining)
      else:
        remaining -= lineLen
        if lineNum < sd.cachedLineCount - 1:
          remaining -= 1 # Account for newline
      inc lineNum

  # Past end of buffer - return position at end of last line
  if sd.cachedLineCount > 0:
    let lastLine = sd.cachedLineCount - 1
    let (blockIdx, localIdx) = sd.findBlock(lastLine)
    return (lastLine, sd.blocks[blockIdx].lines[localIdx].len)
  return (0, 0)

proc substring*(sd: SqrtDecomp, start: int, length: int): string =
  ## Extract a substring starting at linear index 'start' with given 'length'
  if length <= 0 or start < 0:
    return ""

  let (startLine, startCol) = sd.indexToLineCol(start)
  if startLine < 0:
    return ""

  var
    remaining = length
    globalLine = 0

  for bi in 0 ..< sd.blocks.len:
    for li in 0 ..< sd.blocks[bi].lines.len:
      if globalLine < startLine:
        inc globalLine
        continue
      if remaining <= 0:
        return result

      let lineObj = sd.blocks[bi].lines[li]
      let lineLen = lineObj.len

      if globalLine == startLine:
        # First line - start from startCol
        let available = lineLen - startCol
        if remaining <= available:
          result.add(lineObj[startCol ..< startCol + remaining])
          return
        else:
          if startCol < lineLen:
            result.add(lineObj[startCol .. ^1])
          remaining -= available
          # Add newline if not last line
          if globalLine < sd.cachedLineCount - 1 and remaining > 0:
            result.add('\n')
            remaining -= 1
      else:
        # Subsequent lines - start from beginning
        if remaining <= lineLen:
          result.add(lineObj[0 ..< remaining])
          return
        else:
          result.add(lineObj)
          remaining -= lineLen
          # Add newline if not last line
          if globalLine < sd.cachedLineCount - 1 and remaining > 0:
            result.add('\n')
            remaining -= 1

      inc globalLine

proc `[]`*[T, U: Ordinal](sd: SqrtDecomp, x: HSlice[T, U]): string =
  ## Slice operator for extracting substring by linear index range
  ## Returns substring from x.a to x.b (inclusive)
  let
    start = x.a.int
    endIdx = x.b.int
  if start < 0 or endIdx < start:
    return ""
  let length = endIdx - start + 1
  sd.substring(start, length)

proc insertLine*(sd: SqrtDecomp, lineNumber: int, content: string) =
  ## Insert a new line at the specified line number
  ## Raises IndexDefect if lineNumber is out of valid range [0..len]
  if lineNumber < 0 or lineNumber > sd.cachedLineCount:
    raise newException(
      IndexDefect,
      "SqrtDecomp line index out of valid range [0.." & $sd.cachedLineCount & "]",
    )

  if lineNumber == sd.cachedLineCount:
    # Append to the last block
    let lastBlock = sd.blocks.len - 1
    sd.blocks[lastBlock].lines.add(content)
    sd.cachedLineCount += 1
    # Update charLen: add the line content + 1 newline (between previous last and new)
    sd.cachedCharLen += content.len
    if sd.cachedLineCount > 1:
      sd.cachedCharLen += 1 # newline between lines
    sd.maybeSplit(lastBlock)
  else:
    let (blockIdx, localIdx) = sd.findBlock(lineNumber)
    sd.blocks[blockIdx].lines.insert(content, localIdx)
    sd.cachedLineCount += 1
    sd.cachedCharLen += content.len
    if sd.cachedLineCount > 1:
      sd.cachedCharLen += 1
    sd.maybeSplit(blockIdx)

proc deleteLine*(sd: SqrtDecomp, lineNumber: int) =
  ## Delete the specified line
  ## Raises IndexDefect if lineNumber is out of bounds
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  let deletedLen = sd.blocks[blockIdx].lines[localIdx].len
  sd.blocks[blockIdx].lines.delete(localIdx)
  sd.cachedLineCount -= 1
  sd.cachedCharLen -= deletedLen
  if sd.cachedLineCount > 0:
    sd.cachedCharLen -= 1 # Remove newline between lines

  # Remove empty block (unless it's the only one)
  if sd.blocks[blockIdx].lines.len == 0:
    if sd.blocks.len > 1:
      sd.blocks.delete(blockIdx)
    # else: keep the empty block so blocks is never empty
  else:
    sd.maybeMerge(blockIdx)

proc insertIntoLine*(sd: SqrtDecomp, line, col: int, text: string) =
  ## Insert text into an existing line at (line, column) position
  ## Note: col is expected to be a byte position, not a character position
  if line < 0 or line >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds: " & $line)

  let (blockIdx, localIdx) = sd.findBlock(line)
  var lineObj = sd.blocks[blockIdx].lines[localIdx]

  if col < 0 or col > lineObj.len:
    raise newException(
      IndexDefect,
      "SqrtDecomp column out of valid range [0.." & $lineObj.len & "]: " & $col,
    )

  lineObj.insert(text, col)
  sd.blocks[blockIdx].lines[localIdx] = lineObj
  sd.cachedCharLen += text.len

proc deleteAtLineCol*(sd: SqrtDecomp, line: int, col: int, count: int = 1) =
  ## Delete 'count' bytes starting from (line, column) position
  ## Note: 'col' and 'count' are in bytes, not characters
  ## Handles cross-line deletion (merging lines when deleting newlines)
  if count <= 0:
    raise newException(IndexDefect, "SqrtDecomp delete count must be > 0")
  if line < 0 or line >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds: " & $line)

  # Find the range of the deletion
  var
    endLine = line
    endCol = col
    remaining = count

  while remaining > 0 and endLine < sd.cachedLineCount:
    let (bi, li) = sd.findBlock(endLine)
    let lineObj = sd.blocks[bi].lines[li]
    let lineLen = lineObj.len

    let availableInLine = lineLen - endCol
    if remaining <= availableInLine:
      endCol += remaining
      remaining = 0
      break
    else:
      remaining -= availableInLine
      if remaining > 0 and endLine < sd.cachedLineCount - 1:
        remaining -= 1 # consume newline
        endCol = 0
        inc endLine
      else:
        endCol = lineLen
        break

  # Clamp
  if endLine >= sd.cachedLineCount:
    endLine = sd.cachedLineCount - 1
  let (endBi, endLi) = sd.findBlock(endLine)
  let endLineLen = sd.blocks[endBi].lines[endLi].len
  if endCol > endLineLen:
    endCol = endLineLen

  if line == endLine:
    # Single line deletion
    let (bi, li) = sd.findBlock(line)
    let lineObj = sd.blocks[bi].lines[li]
    let prefix =
      if col > 0 and col <= lineObj.len:
        lineObj[0 ..< col]
      else:
        ""
    let suffix =
      if endCol < lineObj.len:
        lineObj[endCol .. ^1]
      else:
        ""
    let oldLen = lineObj.len
    sd.blocks[bi].lines[li] = prefix & suffix
    sd.cachedCharLen -= (oldLen - sd.blocks[bi].lines[li].len)
  else:
    # Multi-line deletion
    let (startBi, startLi) = sd.findBlock(line)
    let startLineObj = sd.blocks[startBi].lines[startLi]
    let (endBi2, endLi2) = sd.findBlock(endLine)
    let endLineObj = sd.blocks[endBi2].lines[endLi2]

    let prefix =
      if col > 0 and col <= startLineObj.len:
        startLineObj[0 ..< col]
      else:
        ""
    let suffix =
      if endCol < endLineObj.len:
        endLineObj[endCol .. ^1]
      else:
        ""

    # Replace start line with merged content
    let mergedLine = prefix & suffix
    let (bi, li) = sd.findBlock(line)
    sd.blocks[bi].lines[li] = mergedLine

    # Delete lines from line+1 to endLine (inclusive) in reverse order
    let linesToDelete = endLine - line
    for i in countdown(linesToDelete, 1):
      let delLine = line + i
      if delLine < sd.cachedLineCount:
        let (dBi, dLi) = sd.findBlock(delLine)
        let deletedLen = sd.blocks[dBi].lines[dLi].len
        sd.blocks[dBi].lines.delete(dLi)
        sd.cachedLineCount -= 1
        sd.cachedCharLen -= deletedLen
        if sd.cachedLineCount > 0:
          sd.cachedCharLen -= 1 # newline

        # Remove empty blocks
        if sd.blocks[dBi].lines.len == 0 and sd.blocks.len > 1:
          sd.blocks.delete(dBi)

    # Update charLen for the start line replacement
    sd.cachedCharLen -= (startLineObj.len - mergedLine.len)

    # Rebalance the block containing the start line
    let (finalBi, _) = sd.findBlock(line)
    sd.maybeMerge(finalBi)

proc insert*(sd: SqrtDecomp, index: int, text: string) =
  ## Insert text at linear index position
  ## Handles newlines by splitting into multiple lines
  if text.len == 0:
    return

  if index < 0:
    return

  let (line, col) = sd.indexToLineCol(index)
  if line < 0:
    return

  # Parse text for newlines
  var
    parts: seq[string] = @[]
    currentPart = ""

  for ch in text:
    if ch == '\n':
      parts.add(currentPart)
      currentPart = ""
    else:
      currentPart.add(ch)

  if parts.len == 0:
    # No newlines - simple insert into line
    sd.insertIntoLine(line, col, text)
  else:
    # Has newlines - need to split lines
    let (blockIdx, localIdx) = sd.findBlock(line)
    let originalLine = sd.blocks[blockIdx].lines[localIdx]
    let prefix =
      if col <= originalLine.len:
        originalLine[0 ..< col]
      else:
        originalLine
    let suffix =
      if col < originalLine.len:
        originalLine[col .. ^1]
      else:
        ""

    # Update first line with prefix + content before first newline
    let oldLen = sd.blocks[blockIdx].lines[localIdx].len
    sd.blocks[blockIdx].lines[localIdx] = prefix & parts[0]
    sd.cachedCharLen += sd.blocks[blockIdx].lines[localIdx].len - oldLen

    # Insert new lines for content between newlines
    for i in 1 ..< parts.len:
      sd.insertLine(line + i, parts[i])

    # Insert final new line with remaining content + suffix
    sd.insertLine(line + parts.len, currentPart & suffix)

proc insert*(sd: SqrtDecomp, index: int, ch: char) =
  ## Insert a single character at linear index position
  sd.insert(index, $ch)

proc delete*(sd: SqrtDecomp, index: int, count: int = 1) =
  ## Delete 'count' characters starting at linear index position
  if count <= 0 or index < 0:
    return

  let (line, col) = sd.indexToLineCol(index)
  if line < 0 or line >= sd.cachedLineCount:
    return

  # Clamp col to valid range
  let (blockIdx, localIdx) = sd.findBlock(line)
  let lineLen = sd.blocks[blockIdx].lines[localIdx].len
  if col > lineLen:
    return

  sd.deleteAtLineCol(line, col, count)

proc clear*(sd: SqrtDecomp) =
  ## Clear all content and reset to single empty line
  sd.blocks = @[Block(lines: @[""])]
  sd.cachedLineCount = 1
  sd.cachedCharLen = 0

proc `$`*(sd: SqrtDecomp): string =
  ## Convert entire buffer to string
  ## Each line gets a newline EXCEPT the final line (unless it's empty)
  ## Empty final line represents explicit trailing newline in the original content
  if sd.cachedLineCount == 0:
    return ""

  var lineNum = 0
  for b in sd.blocks:
    for line in b.lines:
      result.add(line)
      # Add newline: between all lines, and after last line if it's empty
      let isLastLine = lineNum == sd.cachedLineCount - 1
      if not isLastLine or (isLastLine and line.len == 0 and sd.cachedLineCount > 1):
        result.add('\n')
      inc lineNum

iterator chars*(sd: SqrtDecomp): char =
  ## Iterate over all characters in the buffer, including newlines
  ## Consistent with $ operator
  var lineNum = 0
  for b in sd.blocks:
    for line in b.lines:
      for ch in line:
        yield ch

      let isLastLine = lineNum == sd.cachedLineCount - 1
      if not isLastLine or (isLastLine and line.len == 0 and sd.cachedLineCount > 1):
        yield '\n'
      inc lineNum

iterator lines*(sd: SqrtDecomp): string =
  ## Iterate over all lines
  for b in sd.blocks:
    for line in b.lines:
      yield line

proc estimateMemoryUsage*(sd: SqrtDecomp): int =
  ## Estimate memory usage in bytes
  result = sizeof(SqrtDecomp)
  for b in sd.blocks:
    result += sizeof(Block) + b.lines.len * sizeof(string)
    for line in b.lines:
      result += sizeof(string) + line.len

proc getBlockInfo*(
    sd: SqrtDecomp
): tuple[blockCount: int, totalLines: int, avgBlockSize: float] =
  ## Get block structure info for debugging
  let total = sd.cachedLineCount
  let avg =
    if sd.blocks.len > 0:
      total.float / sd.blocks.len.float
    else:
      0.0
  (blockCount: sd.blocks.len, totalLines: total, avgBlockSize: avg)
