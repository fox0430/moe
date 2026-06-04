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
## Θ(sqrt n) blocks. Each block also caches the sum of its line lengths
## (`cachedCharLen`, content only — no newlines), which lets the linear char-index
## ops (charAt / indexToLineCol / substring / findLineStart) skip whole blocks in
## O(sqrt n). Line and char counts are cached for O(1).
##
## Flat-string semantics (POSIX terminator, newline BETWEEN lines, no trailing
## newline after the final line except the explicit empty-final-line case) are
## identical to GapBuffer.

import std/math

const MIN_REBALANCE_LINES = 4 # below this many lines, skip rebalancing (anti-thrash)

type
  Block = object
    lines: seq[string]
    cachedCharLen: int # Sum of this block's line lengths (content only, no newlines)

  SqrtDecomp* = ref object
    blocks: seq[Block]
    cachedLineCount: int
    cachedCharLen: int # Total character count including newlines between lines
    targetBlockSize: int # ≈ ceil(sqrt(cachedLineCount)); set at build and rebalance
    lineCountAtLastRebalance: int # cachedLineCount snapshot at the last rebalance

proc computeTargetBlockSize(lineCount: int): int =
  ## Target block size for a buffer of `lineCount` lines: ceil(sqrt(lineCount)).
  max(1, int(ceil(sqrt(lineCount.float))))

proc recalcCharLen(sd: SqrtDecomp) =
  ## Recompute the global cachedCharLen AND every block's cachedCharLen from scratch.
  sd.cachedCharLen = 0
  for bi in 0 ..< sd.blocks.len:
    var blockSum = 0
    for line in sd.blocks[bi].lines:
      blockSum += line.len
    sd.blocks[bi].cachedCharLen = blockSum
    sd.cachedCharLen += blockSum
  # Add newlines between lines (lineCount - 1 newlines for lineCount lines)
  if sd.cachedLineCount > 1:
    sd.cachedCharLen += sd.cachedLineCount - 1

proc newSqrtDecomp*(): SqrtDecomp =
  ## Create an empty SqrtDecomp buffer with a single empty line
  result = SqrtDecomp(
    blocks: @[Block(lines: @[""], cachedCharLen: 0)],
    cachedLineCount: 1,
    cachedCharLen: 0,
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
    cachedCharLen: 0,
    targetBlockSize: tbs,
    lineCountAtLastRebalance: linesList.len,
  )
  result.recalcCharLen() # also fills each block's cachedCharLen

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

  var secondSum = 0
  for s in secondHalf:
    secondSum += s.len
  let firstSum = sd.blocks[blockIdx].cachedCharLen - secondSum

  sd.blocks[blockIdx].lines.setLen(mid)
  sd.blocks[blockIdx].cachedCharLen = firstSum
  sd.blocks.insert(Block(lines: secondHalf, cachedCharLen: secondSum), blockIdx + 1)

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
      sd.blocks[blockIdx].cachedCharLen += sd.blocks[blockIdx + 1].cachedCharLen
      sd.blocks.delete(blockIdx + 1)
      return

  # Try merging with previous block
  if blockIdx > 0:
    let combinedLen = sd.blocks[blockIdx - 1].lines.len + sd.blocks[blockIdx].lines.len
    if combinedLen <= cap:
      sd.blocks[blockIdx - 1].lines.add(sd.blocks[blockIdx].lines)
      sd.blocks[blockIdx - 1].cachedCharLen += sd.blocks[blockIdx].cachedCharLen
      sd.blocks.delete(blockIdx)

proc blockSpan(sd: SqrtDecomp, bi: int): int =
  ## Number of flat-string char positions owned by block `bi` for index-math:
  ## its content plus a trailing newline per line, EXCEPT the buffer's final line
  ## (in the last block) has no trailing newline.
  let m = sd.blocks[bi].lines.len
  if bi < sd.blocks.len - 1:
    sd.blocks[bi].cachedCharLen + m # content + (m-1 internal + 1 trailing) newlines
  else:
    max(0, sd.blocks[bi].cachedCharLen + m - 1) # last block: no trailing newline

proc rebalance(sd: SqrtDecomp) =
  ## Re-chunk all lines into blocks of the freshly computed targetBlockSize and
  ## recompute each block's cachedCharLen. Pure structural op: leaves the global
  ## cachedLineCount / cachedCharLen untouched. O(n).
  sd.targetBlockSize = computeTargetBlockSize(sd.cachedLineCount)
  var flat = newSeqOfCap[string](sd.cachedLineCount)
  for b in sd.blocks:
    for line in b.lines:
      flat.add(line)

  var newBlocks: seq[Block] = @[]
  var i = 0
  while i < flat.len:
    let stop = min(i + sd.targetBlockSize, flat.len)
    var c = 0
    for k in i ..< stop:
      c += flat[k].len
    newBlocks.add(Block(lines: flat[i ..< stop], cachedCharLen: c))
    i = stop
  if newBlocks.len == 0:
    newBlocks = @[Block(lines: @[""], cachedCharLen: 0)]

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

proc charLen*(sd: SqrtDecomp): int =
  ## Return total character count (including newlines between lines)
  sd.cachedCharLen

proc findLineStart*(sd: SqrtDecomp, lineNumber: int): int =
  ## Return the linear index of the start of the given line
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    return -1

  result = 0
  var lineNum = 0
  for bi in 0 ..< sd.blocks.len:
    let m = sd.blocks[bi].lines.len
    # Skip whole blocks before the target line (O(sqrt n)). A fully-skipped block
    # is never the last block, so every one of its lines has a trailing newline.
    if lineNumber >= lineNum + m:
      result += sd.blocks[bi].cachedCharLen + m
      lineNum += m
      continue
    for line in sd.blocks[bi].lines:
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
  sd.blocks[blockIdx].cachedCharLen += content.len - oldLen

proc replaceLine*(sd: SqrtDecomp, lineNumber: int, content: string) =
  ## Replace the content of a specific line
  ## Raises IndexDefect if lineNumber is out of bounds
  if lineNumber < 0 or lineNumber >= sd.cachedLineCount:
    raise newException(IndexDefect, "SqrtDecomp line out of bounds")

  let (blockIdx, localIdx) = sd.findBlock(lineNumber)
  let oldLen = sd.blocks[blockIdx].lines[localIdx].len
  sd.blocks[blockIdx].lines[localIdx] = content
  sd.cachedCharLen += content.len - oldLen
  sd.blocks[blockIdx].cachedCharLen += content.len - oldLen

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
  sd.blocks[blockIdx].cachedCharLen += line.len - oldLen

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

  for bi in 0 ..< sd.blocks.len:
    # Skip whole blocks the index lies past (O(sqrt n)).
    let span = sd.blockSpan(bi)
    if remaining >= span:
      remaining -= span
      lineNum += sd.blocks[bi].lines.len
      continue
    for line in sd.blocks[bi].lines:
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

  for bi in 0 ..< sd.blocks.len:
    # Skip whole blocks the index lies strictly past (O(sqrt n)).
    let span = sd.blockSpan(bi)
    if remaining > span:
      remaining -= span
      lineNum += sd.blocks[bi].lines.len
      continue
    for line in sd.blocks[bi].lines:
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
    # Skip whole blocks that end before startLine (O(sqrt n)).
    let m = sd.blocks[bi].lines.len
    if startLine >= globalLine + m:
      globalLine += m
      continue
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
    sd.blocks[lastBlock].cachedCharLen += content.len
    sd.cachedLineCount += 1
    # Update charLen: add the line content + 1 newline (between previous last and new)
    sd.cachedCharLen += content.len
    if sd.cachedLineCount > 1:
      sd.cachedCharLen += 1 # newline between lines
    sd.maybeSplit(lastBlock)
  else:
    let (blockIdx, localIdx) = sd.findBlock(lineNumber)
    sd.blocks[blockIdx].lines.insert(content, localIdx)
    sd.blocks[blockIdx].cachedCharLen += content.len
    sd.cachedLineCount += 1
    sd.cachedCharLen += content.len
    if sd.cachedLineCount > 1:
      sd.cachedCharLen += 1
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
  let deletedLen = sd.blocks[blockIdx].lines[localIdx].len
  sd.blocks[blockIdx].lines.delete(localIdx)
  sd.blocks[blockIdx].cachedCharLen -= deletedLen
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
  sd.cachedCharLen += text.len
  sd.blocks[blockIdx].cachedCharLen += text.len

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
    sd.blocks[bi].cachedCharLen -= (oldLen - sd.blocks[bi].lines[li].len)
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
    # (bi stays valid through the loop below: intermediate deletes target lines
    #  after `line`, so they never empty or shift the start line's block.)
    sd.blocks[bi].cachedCharLen -= (startLineObj.len - mergedLine.len)

    # Delete lines from line+1 to endLine (inclusive) in reverse order
    let linesToDelete = endLine - line
    for i in countdown(linesToDelete, 1):
      let delLine = line + i
      if delLine < sd.cachedLineCount:
        let (dBi, dLi) = sd.findBlock(delLine)
        let deletedLen = sd.blocks[dBi].lines[dLi].len
        sd.blocks[dBi].lines.delete(dLi)
        sd.blocks[dBi].cachedCharLen -= deletedLen
        sd.cachedLineCount -= 1
        sd.cachedCharLen -= deletedLen
        if sd.cachedLineCount > 0:
          sd.cachedCharLen -= 1 # newline

        # Remove empty blocks
        if sd.blocks[dBi].lines.len == 0 and sd.blocks.len > 1:
          sd.blocks.delete(dBi)

    # Update charLen for the start line replacement
    sd.cachedCharLen -= (startLineObj.len - mergedLine.len)

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
    let firstDelta = sd.blocks[blockIdx].lines[localIdx].len - oldLen
    sd.cachedCharLen += firstDelta
    sd.blocks[blockIdx].cachedCharLen += firstDelta

    # Insert new lines for content between newlines. Use the *Core variant so the
    # whole multi-line insert triggers at most one rebalance (below) rather than
    # one per line; each call re-resolves its own block via findBlock.
    for i in 1 ..< parts.len:
      sd.insertLineCore(line + i, parts[i])

    # Insert final new line with remaining content + suffix
    sd.insertLineCore(line + parts.len, currentPart & suffix)
    sd.maybeRebalance()

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
  sd.blocks = @[Block(lines: @[""], cachedCharLen: 0)]
  sd.cachedLineCount = 1
  sd.cachedCharLen = 0
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
