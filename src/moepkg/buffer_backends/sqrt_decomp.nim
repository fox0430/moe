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

## Sqrt-decomposition (block list) buffer backend
##
## Lines are partitioned into blocks whose size is kept at ≈ ceil(sqrt(lineCount)).
## The target block size is recomputed and the whole structure rebalanced whenever
## the line count doubles or halves; between rebalances blocks split (when they
## exceed 2*target) and merge (when they fall below target/2) per edit. Thus there
## are Θ(sqrt n) blocks of Θ(sqrt n) lines at all times, so `findBlock` scans
## Θ(sqrt n) blocks. The line count is cached for O(1).
##
## Flat-string semantics (POSIX terminator, newline BETWEEN lines, no trailing
## newline after the final line except the explicit empty-final-line case) are
## identical to GapBuffer.

import std/math

const MIN_REBALANCE_LINES = 4 # below this many lines, skip rebalancing (anti-thrash)

type
  Block = object
    lines: seq[string]

  SqrtDecomp* = ref object
    blocks: seq[Block]
    cachedLineCount: int
    targetBlockSize: int # ≈ ceil(sqrt(cachedLineCount)); set at build and rebalance
    lineCountAtLastRebalance: int # cachedLineCount snapshot at the last rebalance

proc computeTargetBlockSize(lineCount: int): int =
  ## Target block size for a buffer of `lineCount` lines: ceil(sqrt(lineCount)).
  max(1, int(ceil(sqrt(lineCount.float))))

proc newSqrtDecomp*(): SqrtDecomp =
  ## Create an empty SqrtDecomp buffer with a single empty line
  result = SqrtDecomp(
    blocks: @[Block(lines: @[""])],
    cachedLineCount: 1,
    targetBlockSize: 1,
    lineCountAtLastRebalance: 1,
  )

proc newSqrtDecomp*(text: sink string): SqrtDecomp =
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

  # Distribute lines into blocks of the sqrt-sized target
  let tbs = computeTargetBlockSize(linesList.len)
  var blocks: seq[Block] = @[]
  var i = 0
  while i < linesList.len:
    let blockEnd = min(i + tbs, linesList.len)
    blocks.add(Block(lines: linesList[i ..< blockEnd]))
    i = blockEnd

  result = SqrtDecomp(
    blocks: blocks,
    cachedLineCount: linesList.len,
    targetBlockSize: tbs,
    lineCountAtLastRebalance: linesList.len,
  )

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
  ## Split a block in half when it grows beyond 2*targetBlockSize.
  if blockIdx >= sd.blocks.len:
    return
  if sd.blocks[blockIdx].lines.len <= 2 * sd.targetBlockSize:
    return

  let
    mid = sd.blocks[blockIdx].lines.len div 2
    secondHalf = sd.blocks[blockIdx].lines[mid .. ^1]

  sd.blocks[blockIdx].lines.setLen(mid)
  sd.blocks.insert(Block(lines: secondHalf), blockIdx + 1)

proc maybeMerge(sd: SqrtDecomp, blockIdx: int) =
  ## Merge an under-full block (< target/2 lines) with a neighbor, provided the
  ## combined block stays within 2*targetBlockSize.
  if blockIdx >= sd.blocks.len:
    return
  if sd.blocks[blockIdx].lines.len >= max(1, sd.targetBlockSize div 2):
    return
  if sd.blocks.len <= 1:
    return # Don't merge the last block

  let cap = 2 * sd.targetBlockSize

  # Try merging with next block
  if blockIdx < sd.blocks.len - 1:
    let combinedLen = sd.blocks[blockIdx].lines.len + sd.blocks[blockIdx + 1].lines.len
    if combinedLen <= cap:
      sd.blocks[blockIdx].lines.add(sd.blocks[blockIdx + 1].lines)
      sd.blocks.delete(blockIdx + 1)
      return

  # Try merging with previous block
  if blockIdx > 0:
    let combinedLen = sd.blocks[blockIdx - 1].lines.len + sd.blocks[blockIdx].lines.len
    if combinedLen <= cap:
      sd.blocks[blockIdx - 1].lines.add(sd.blocks[blockIdx].lines)
      sd.blocks.delete(blockIdx)

proc rebalance(sd: SqrtDecomp) =
  ## Re-chunk all lines into blocks of the freshly computed targetBlockSize.
  ## Pure structural op: leaves cachedLineCount untouched. O(n).
  sd.targetBlockSize = computeTargetBlockSize(sd.cachedLineCount)
  var flat = newSeqOfCap[string](sd.cachedLineCount)
  for b in sd.blocks:
    for line in b.lines:
      flat.add(line)

  var newBlocks: seq[Block] = @[]
  var i = 0
  while i < flat.len:
    let stop = min(i + sd.targetBlockSize, flat.len)
    newBlocks.add(Block(lines: flat[i ..< stop]))
    i = stop
  if newBlocks.len == 0:
    newBlocks = @[Block(lines: @[""])]

  sd.blocks = newBlocks
  sd.lineCountAtLastRebalance = sd.cachedLineCount

proc maybeRebalance(sd: SqrtDecomp) =
  ## Rebalance when the line count has doubled or halved since the last rebalance.
  ## Amortized O(1): a rebalance is O(n) and only fires after Θ(n) line-count ops.
  if sd.cachedLineCount < MIN_REBALANCE_LINES:
    return
  if sd.cachedLineCount >= 2 * sd.lineCountAtLastRebalance or
      sd.cachedLineCount * 2 <= sd.lineCountAtLastRebalance:
    sd.rebalance()

proc lineCount*(sd: SqrtDecomp): int {.inline.} =
  ## Count number of lines
  sd.cachedLineCount

proc len*(sd: SqrtDecomp): int {.inline.} =
  ## Return line count (alias for lineCount)
  sd.cachedLineCount

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
  sd.blocks[blockIdx].lines[localIdx] = content

proc replaceLine*(sd: SqrtDecomp, lineNumber: int, content: string) =
  ## Replace the content of a specific line
  ## Raises IndexDefect if lineNumber is out of bounds
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  sd.blocks[blockIdx].lines[localIdx] = content

proc modifyLineContent*(sd: SqrtDecomp, lineNumber: int, f: proc(s: var string)) =
  ## Modify line content in-place using a function
  ## Raises IndexDefect if lineNumber is out of bounds
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  var line = sd.blocks[blockIdx].lines[localIdx]
  f(line)
  sd.blocks[blockIdx].lines[localIdx] = line

proc charAtLineCol*(sd: SqrtDecomp, line: int, col: int): char =
  ## Get the byte at (line, col) position (col is a byte offset)
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

proc insertLineCore(sd: SqrtDecomp, lineNumber: int, content: string) =
  ## insertLine without the trailing maybeRebalance, so a multi-line insert(text)
  ## pays for at most one O(n) rebalance (at the op end) instead of one per line.
  ## Each call re-resolves its block via findBlock, so the deferral is purely an
  ## efficiency choice, not a correctness requirement.
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
    sd.maybeSplit(lastBlock)
  else:
    let (blockIdx, localIdx) = sd.findBlock(lineNumber)
    sd.blocks[blockIdx].lines.insert(content, localIdx)
    sd.cachedLineCount += 1
    sd.maybeSplit(blockIdx)

proc insertLine*(sd: SqrtDecomp, lineNumber: int, content: string) =
  ## Insert a new line at the specified line number
  ## Raises IndexDefect if lineNumber is out of valid range [0..len]
  sd.insertLineCore(lineNumber, content)
  sd.maybeRebalance()

proc deleteLineCore(sd: SqrtDecomp, lineNumber: int) =
  ## deleteLine without the trailing maybeRebalance, so a caller doing several
  ## line deletes can rebalance once at the end instead of per line.
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  sd.blocks[blockIdx].lines.delete(localIdx)
  sd.cachedLineCount -= 1

  # Remove empty block (unless it's the only one)
  if sd.blocks[blockIdx].lines.len == 0:
    if sd.blocks.len > 1:
      sd.blocks.delete(blockIdx)
    # else: keep the empty block so blocks is never empty
  else:
    sd.maybeMerge(blockIdx)

proc deleteLine*(sd: SqrtDecomp, lineNumber: int) =
  ## Delete the specified line
  ## Raises IndexDefect if lineNumber is out of bounds
  sd.deleteLineCore(lineNumber)
  sd.maybeRebalance()

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
    sd.blocks[bi].lines[li] = prefix & suffix
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
        sd.blocks[dBi].lines.delete(dLi)
        sd.cachedLineCount -= 1

        # Remove empty blocks
        if sd.blocks[dBi].lines.len == 0 and sd.blocks.len > 1:
          sd.blocks.delete(dBi)

    # Both ends of the splice can be left under-full: the block holding the start
    # line (it lost its trailing lines) and the block now holding the following
    # line (it lost its leading lines). Merge each if needed; findBlock is
    # re-resolved between the two because the first merge may delete a block and
    # shift indices.
    let (finalBi, _) = sd.findBlock(line)
    sd.maybeMerge(finalBi)
    if line + 1 < sd.cachedLineCount:
      let (afterBi, _) = sd.findBlock(line + 1)
      sd.maybeMerge(afterBi)

  sd.maybeRebalance()

proc clear*(sd: SqrtDecomp) =
  ## Clear all content and reset to single empty line
  sd.blocks = @[Block(lines: @[""])]
  sd.cachedLineCount = 1
  sd.targetBlockSize = 1
  sd.lineCountAtLastRebalance = 1

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
  ## Iterate over each byte in the buffer, including newlines
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
