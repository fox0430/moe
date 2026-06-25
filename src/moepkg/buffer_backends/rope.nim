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

## B-tree Rope buffer backend
##
## Stores text as a balanced B-tree of UTF-8 chunks.
## All major operations are O(log n).

const
  MIN_CHILDREN* = 4
  MAX_CHILDREN* = 8
  MIN_LEAF_BYTES* = 256
  MAX_LEAF_BYTES* = 1024
  TARGET_LEAF_BYTES = 512

type
  RopeNodeKind* = enum
    rnkLeaf
    rnkInternal

  RopeNode* = ref object
    byteLen*: int
    lineBreakCount*: int
    case kind*: RopeNodeKind
    of rnkLeaf:
      text*: string
    of rnkInternal:
      children*: seq[RopeNode]

  Rope* = ref object
    root*: RopeNode
    cachedLineCount*: int

proc countLineBreaks(s: string): int =
  for ch in s:
    if ch == '\n':
      inc result

proc updateMetrics(node: RopeNode) =
  case node.kind
  of rnkLeaf:
    node.byteLen = node.text.len
    node.lineBreakCount = countLineBreaks(node.text)
  of rnkInternal:
    node.byteLen = 0
    node.lineBreakCount = 0
    for child in node.children:
      node.byteLen += child.byteLen
      node.lineBreakCount += child.lineBreakCount

proc newLeaf(text: string): RopeNode =
  result = RopeNode(kind: rnkLeaf, text: text)
  result.updateMetrics()

proc newInternal(children: seq[RopeNode]): RopeNode =
  result = RopeNode(kind: rnkInternal, children: children)
  result.updateMetrics()

proc newRope*(): Rope =
  ## Create an empty Rope buffer with a single empty line
  Rope(root: newLeaf(""), cachedLineCount: 1)

proc buildTree(leaves: seq[RopeNode]): RopeNode =
  ## Build a balanced B-tree bottom-up from a sequence of leaves
  if leaves.len == 0:
    return newLeaf("")
  if leaves.len == 1:
    return leaves[0]

  # Group leaves into internal nodes of MAX_CHILDREN
  var currentLevel = leaves
  while currentLevel.len > 1:
    var nextLevel: seq[RopeNode] = @[]
    var i = 0
    while i < currentLevel.len:
      let groupEnd = min(i + MAX_CHILDREN, currentLevel.len)
      # Ensure last group has at least MIN_CHILDREN if possible
      var actualEnd = groupEnd
      if groupEnd < currentLevel.len and currentLevel.len - groupEnd < MIN_CHILDREN and
          groupEnd - i > MIN_CHILDREN:
        # Leave enough for the next group to have MIN_CHILDREN
        actualEnd = groupEnd - (MIN_CHILDREN - (currentLevel.len - groupEnd))
        if actualEnd <= i:
          actualEnd = groupEnd
      nextLevel.add(newInternal(currentLevel[i ..< actualEnd]))
      i = actualEnd
    currentLevel = nextLevel
  currentLevel[0]

proc textToNode(text: string): RopeNode =
  ## Convert raw text to a properly chunked rope node subtree.
  ## For small text, returns a single leaf. For large text, builds a balanced tree.
  if text.len <= MAX_LEAF_BYTES:
    return newLeaf(text)

  var leaves: seq[RopeNode] = @[]
  var pos = 0
  while pos < text.len:
    var chunkEnd = min(pos + TARGET_LEAF_BYTES, text.len)

    if chunkEnd < text.len:
      var bestSplit = -1
      let searchEnd = min(chunkEnd + TARGET_LEAF_BYTES div 2, text.len)
      for i in chunkEnd ..< searchEnd:
        if text[i] == '\n':
          bestSplit = i + 1
          break
      if bestSplit < 0:
        for i in countdown(chunkEnd - 1, max(pos, chunkEnd - TARGET_LEAF_BYTES div 2)):
          if text[i] == '\n':
            bestSplit = i + 1
            break
      if bestSplit > pos:
        chunkEnd = bestSplit

    if chunkEnd - pos > MAX_LEAF_BYTES and chunkEnd < text.len:
      chunkEnd = pos + MAX_LEAF_BYTES

    leaves.add(newLeaf(text[pos ..< chunkEnd]))
    pos = chunkEnd

  buildTree(leaves)

proc newRope*(text: sink string): Rope =
  ## Create a Rope buffer from text string.
  ## Uses same line-parsing semantics as GapBuffer:
  ## - POSIX: newline is line terminator, not separator
  ## - "hello\n" = 1 line, "hello\n\n" = 2 lines
  ## - Trailing newline is NOT stored (managed by TextBuffer.endOfLine)

  # Strip trailing newline (same as GapBuffer/SqrtDecomp)
  var content = move text
  if content.len > 0 and content[^1] == '\n':
    content.setLen(content.len - 1)

  if content.len == 0:
    return Rope(root: newLeaf(""), cachedLineCount: 1)

  let root = textToNode(content)
  Rope(root: root, cachedLineCount: root.lineBreakCount + 1)

proc height(node: RopeNode): int =
  case node.kind
  of rnkLeaf:
    0
  of rnkInternal:
    if node.children.len == 0:
      0
    else:
      1 + node.children[0].height

proc splitLeaf(node: RopeNode, byteOffset: int): (RopeNode, RopeNode) =
  ## Split a leaf node at the given byte offset
  assert node.kind == rnkLeaf
  let offset = clamp(byteOffset, 0, node.text.len)
  (newLeaf(node.text[0 ..< offset]), newLeaf(node.text[offset ..< node.text.len]))

proc splitNode(node: RopeNode, byteOffset: int): (RopeNode, RopeNode) =
  ## Split a node at the given byte offset, returning (left, right)
  if byteOffset <= 0:
    return (newLeaf(""), node)
  if byteOffset >= node.byteLen:
    return (node, newLeaf(""))

  case node.kind
  of rnkLeaf:
    return splitLeaf(node, byteOffset)
  of rnkInternal:
    var accumulated = 0
    for i in 0 ..< node.children.len:
      let childLen = node.children[i].byteLen
      if byteOffset <= accumulated + childLen:
        let localOffset = byteOffset - accumulated
        let (childLeft, childRight) = splitNode(node.children[i], localOffset)

        var leftChildren: seq[RopeNode] = @[]
        for j in 0 ..< i:
          leftChildren.add(node.children[j])
        if childLeft.byteLen > 0:
          leftChildren.add(childLeft)

        var rightChildren: seq[RopeNode] = @[]
        if childRight.byteLen > 0:
          rightChildren.add(childRight)
        for j in (i + 1) ..< node.children.len:
          rightChildren.add(node.children[j])

        let left =
          if leftChildren.len == 0:
            newLeaf("")
          elif leftChildren.len == 1:
            leftChildren[0]
          else:
            newInternal(leftChildren)

        let right =
          if rightChildren.len == 0:
            newLeaf("")
          elif rightChildren.len == 1:
            rightChildren[0]
          else:
            newInternal(rightChildren)

        return (left, right)
      accumulated += childLen

    # Should not reach here
    return (node, newLeaf(""))

proc fixup(node: RopeNode): RopeNode =
  ## Fix up a node if it has too many or too few children
  case node.kind
  of rnkLeaf:
    return node
  of rnkInternal:
    if node.children.len == 0:
      return newLeaf("")
    if node.children.len == 1:
      return node.children[0]
    if node.children.len <= MAX_CHILDREN:
      return node

    # Too many children - split into groups
    var groups: seq[RopeNode] = @[]
    var i = 0
    while i < node.children.len:
      let groupEnd = min(i + MAX_CHILDREN, node.children.len)
      if node.children.len - groupEnd > 0 and node.children.len - groupEnd < MIN_CHILDREN:
        # Adjust to ensure last group has enough children
        let splitPoint = i + (node.children.len - i) div 2
        groups.add(newInternal(node.children[i ..< splitPoint]))
        groups.add(newInternal(node.children[splitPoint ..< node.children.len]))
        break
      else:
        groups.add(newInternal(node.children[i ..< groupEnd]))
        i = groupEnd
    if groups.len == 1:
      return groups[0]
    return newInternal(groups)

proc concatNodes(left, right: RopeNode): RopeNode =
  ## Concatenate two nodes into a balanced tree
  if left.byteLen == 0:
    return right
  if right.byteLen == 0:
    return left

  # Both are leaves and small enough to merge
  if left.kind == rnkLeaf and right.kind == rnkLeaf and
      left.text.len + right.text.len <= MAX_LEAF_BYTES:
    return newLeaf(left.text & right.text)

  # Same height - create parent
  let lh = left.height
  let rh = right.height

  if lh == rh:
    # Try to merge children if both are internal
    if left.kind == rnkInternal and right.kind == rnkInternal and
        left.children.len + right.children.len <= MAX_CHILDREN:
      return newInternal(left.children & right.children)
    result = newInternal(@[left, right])
    result = fixup(result)
    return

  # Different heights - push the shorter one down into the taller one
  if lh > rh:
    if left.kind == rnkInternal:
      let lastChild = left.children[^1]
      let merged = concatNodes(lastChild, right)
      var newChildren = left.children[0 ..< ^1]
      if merged.kind == rnkInternal and merged.height == lastChild.height + 1:
        # merged grew a level, add its children
        for c in merged.children:
          newChildren.add(c)
      else:
        newChildren.add(merged)
      result = newInternal(newChildren)
      result = fixup(result)
      return
  else:
    if right.kind == rnkInternal:
      let firstChild = right.children[0]
      let merged = concatNodes(left, firstChild)
      var newChildren: seq[RopeNode] = @[]
      if merged.kind == rnkInternal and merged.height == firstChild.height + 1:
        for c in merged.children:
          newChildren.add(c)
      else:
        newChildren.add(merged)
      for i in 1 ..< right.children.len:
        newChildren.add(right.children[i])
      result = newInternal(newChildren)
      result = fixup(result)
      return

  # Fallback: just create a parent
  result = newInternal(@[left, right])
  result = fixup(result)

proc lineStartByteOffset*(rope: Rope, lineNumber: int): int =
  ## Return the byte offset of the start of the given line number (0-based)
  ## Line 0 starts at byte 0.
  if lineNumber <= 0:
    return 0
  if lineNumber >= rope.cachedLineCount:
    return rope.root.byteLen

  # Walk the tree counting newlines to find the N-th newline
  var linesRemaining = lineNumber
  var offset = 0

  proc walk(node: RopeNode) =
    if linesRemaining <= 0:
      return
    case node.kind
    of rnkLeaf:
      for i in 0 ..< node.text.len:
        if node.text[i] == '\n':
          dec linesRemaining
          if linesRemaining == 0:
            offset += i + 1
            return
      offset += node.text.len
    of rnkInternal:
      for child in node.children:
        if linesRemaining <= 0:
          return
        if child.lineBreakCount < linesRemaining:
          # Skip this entire subtree
          linesRemaining -= child.lineBreakCount
          offset += child.byteLen
        else:
          # The target newline is in this subtree
          walk(child)

  walk(rope.root)
  offset

proc lineEndByteOffset*(rope: Rope, lineNumber: int): int =
  ## Return the byte offset past the end of the given line (before the '\n' or at buffer end)
  if lineNumber < 0 or lineNumber >= rope.cachedLineCount:
    return rope.root.byteLen

  if lineNumber == rope.cachedLineCount - 1:
    # Last line - ends at buffer end
    return rope.root.byteLen

  # The '\n' is at nextLineStart - 1
  let nextLineStart = rope.lineStartByteOffset(lineNumber + 1)
  nextLineStart - 1

proc substringBytes(node: RopeNode, start, length: int): string =
  ## Extract a substring by byte offset from the tree
  if length <= 0 or start >= node.byteLen:
    return ""

  case node.kind
  of rnkLeaf:
    let s = max(0, start)
    let e = min(node.text.len, start + length)
    if s >= e:
      return ""
    return node.text[s ..< e]
  of rnkInternal:
    var remaining = length
    var pos = start
    for child in node.children:
      if remaining <= 0:
        break
      if pos >= child.byteLen:
        pos -= child.byteLen
        continue
      if pos < 0:
        pos = 0
      let take = min(remaining, child.byteLen - pos)
      result.add(substringBytes(child, pos, take))
      remaining -= take
      pos = 0

proc byteAt(node: RopeNode, byteOffset: int): char =
  ## Read a single byte from the tree at the given offset. O(log n).
  case node.kind
  of rnkLeaf:
    return node.text[byteOffset]
  of rnkInternal:
    var remaining = byteOffset
    for child in node.children:
      if remaining < child.byteLen:
        return byteAt(child, remaining)
      remaining -= child.byteLen
    raise newException(IndexDefect, "byteAt: offset past end")

proc countNewlinesBefore(node: RopeNode, byteOffset: int): int =
  ## Count '\n' characters in bytes [0, byteOffset). O(log n).
  if byteOffset <= 0:
    return 0
  case node.kind
  of rnkLeaf:
    let scanEnd = min(byteOffset, node.text.len)
    for i in 0 ..< scanEnd:
      if node.text[i] == '\n':
        inc result
  of rnkInternal:
    var remaining = byteOffset
    for child in node.children:
      if remaining <= 0:
        break
      if remaining >= child.byteLen:
        result += child.lineBreakCount
        remaining -= child.byteLen
      else:
        result += countNewlinesBefore(child, remaining)
        break

proc lineCount*(rope: Rope): int {.inline.} =
  rope.cachedLineCount

proc len*(rope: Rope): int {.inline.} =
  rope.cachedLineCount

proc getLine*(rope: Rope, lineNumber: int): string =
  ## Get content of specific line (0-based, without newline)
  if lineNumber < 0 or lineNumber >= rope.cachedLineCount:
    return ""

  let start = rope.lineStartByteOffset(lineNumber)
  let endOff = rope.lineEndByteOffset(lineNumber)
  let length = endOff - start
  if length <= 0:
    return ""
  substringBytes(rope.root, start, length)

proc `[]`*(rope: Rope, lineNumber: int): string =
  rope.getLine(lineNumber)

proc byteLen*(rope: Rope): int {.inline.} =
  ## Total byte count of buffer content (lines + newlines between lines).
  ## The rope stores text with embedded newlines, so byteLen is the total.
  rope.root.byteLen

proc `[]=`*(rope: Rope, lineNumber: int, content: string) =
  if lineNumber < 0 or lineNumber >= rope.cachedLineCount:
    raise newException(IndexDefect, "Rope line out of bounds")

  let start = rope.lineStartByteOffset(lineNumber)
  let endOff = rope.lineEndByteOffset(lineNumber)
  let oldLen = endOff - start

  let (leftPart, rest) = splitNode(rope.root, start)
  let (_, rightPart) = splitNode(rest, oldLen)
  let newContent = newLeaf(content)
  rope.root = concatNodes(concatNodes(leftPart, newContent), rightPart)
  rope.cachedLineCount = rope.root.lineBreakCount + 1

proc replaceLine*(rope: Rope, lineNumber: int, content: string) =
  if lineNumber < 0 or lineNumber >= rope.cachedLineCount:
    raise newException(IndexDefect, "Rope line out of bounds")
  rope[lineNumber] = content

proc modifyLineContent*(rope: Rope, lineNumber: int, f: proc(s: var string)) =
  if lineNumber < 0 or lineNumber >= rope.cachedLineCount:
    raise newException(IndexDefect, "Rope line out of bounds")
  var line = rope.getLine(lineNumber)
  f(line)
  rope[lineNumber] = line

proc insertLine*(rope: Rope, lineNumber: int, content: string) =
  ## Insert a new line at the specified line number
  if lineNumber < 0 or lineNumber > rope.cachedLineCount:
    raise newException(
      IndexDefect,
      "Rope line index out of valid range [0.." & $rope.cachedLineCount & "]",
    )

  if rope.cachedLineCount == 0:
    # Inserting into empty buffer (0 lines, intermediate state after all lines deleted)
    rope.root = newLeaf(content)
    rope.cachedLineCount = 1
    return

  if lineNumber == rope.cachedLineCount:
    # Append after last line: add "\n" + content at end
    let newText = newLeaf("\n" & content)
    rope.root = concatNodes(rope.root, newText)
  else:
    # Insert before lineNumber: insert content + "\n" at the start of that line
    let offset = rope.lineStartByteOffset(lineNumber)
    let (left, right) = splitNode(rope.root, offset)
    let newText = newLeaf(content & "\n")
    rope.root = concatNodes(concatNodes(left, newText), right)

  rope.cachedLineCount = rope.root.lineBreakCount + 1

proc deleteLine*(rope: Rope, lineNumber: int) =
  ## Delete the specified line
  if lineNumber < 0 or lineNumber >= rope.cachedLineCount:
    raise newException(IndexDefect, "Rope line out of bounds")

  if rope.cachedLineCount == 1:
    # Deleting the only line → 0 lines (intermediate state, matches GapBuffer/SqrtDecomp)
    rope.root = newLeaf("")
    rope.cachedLineCount = 0
    return

  let start = rope.lineStartByteOffset(lineNumber)

  if lineNumber == rope.cachedLineCount - 1:
    # Deleting last line - also remove the preceding '\n'
    let (left, _) = splitNode(rope.root, start - 1)
    rope.root = left
  else:
    # Not the last line - remove up to and including the '\n'
    let endOff = rope.lineStartByteOffset(lineNumber + 1)
    let (left, rest) = splitNode(rope.root, start)
    let (_, right) = splitNode(rest, endOff - start)
    rope.root = concatNodes(left, right)

  if rope.root.byteLen == 0 and rope.root.kind != rnkLeaf:
    rope.root = newLeaf("")

  rope.cachedLineCount = rope.root.lineBreakCount + 1

proc charAtLineCol*(rope: Rope, line: int, col: int): char =
  if line < 0 or line >= rope.cachedLineCount:
    raise newException(IndexDefect, "Rope line out of bounds")

  let lineStart = rope.lineStartByteOffset(line)
  let lineEnd = rope.lineEndByteOffset(line)
  let lineLen = lineEnd - lineStart

  if col >= 0 and col < lineLen:
    return byteAt(rope.root, lineStart + col)
  elif col == lineLen and line < rope.cachedLineCount - 1:
    return '\n'
  else:
    raise newException(IndexDefect, "Rope column out of bounds")

proc charAt*(rope: Rope, index: int): char =
  if index < 0 or index >= rope.root.byteLen:
    raise newException(IndexDefect, "Rope index out of bounds: " & $index)
  byteAt(rope.root, index)

proc findLineStart*(rope: Rope, lineNumber: int): int =
  ## Return the linear index of the start of the given line. O(log n).
  if lineNumber < 0 or lineNumber >= rope.cachedLineCount:
    return -1
  rope.lineStartByteOffset(lineNumber)

proc findLineEnd*(rope: Rope, lineNumber: int): int =
  ## Return the linear index of the end of the given line (last character position). O(log n).
  if lineNumber < 0 or lineNumber >= rope.cachedLineCount:
    return -1
  rope.lineEndByteOffset(lineNumber) - 1

proc indexToLineCol*(rope: Rope, index: int): tuple[line: int, col: int] =
  ## Convert a linear byte index to (line, col). O(log n).
  if index < 0:
    return (-1, -1)
  if rope.cachedLineCount == 0:
    return (0, 0)

  if index >= rope.root.byteLen:
    # Past end
    let lastLine = rope.cachedLineCount - 1
    let lastLineStart = rope.lineStartByteOffset(lastLine)
    return (lastLine, rope.root.byteLen - lastLineStart)

  let line = countNewlinesBefore(rope.root, index)
  let lineStart = rope.lineStartByteOffset(line)
  (line, index - lineStart)

proc insertIntoLine*(rope: Rope, line, col: int, text: string) =
  ## Insert text into an existing line at (line, column) byte position
  if line < 0 or line >= rope.cachedLineCount:
    raise newException(IndexDefect, "Rope line out of bounds: " & $line)

  let lineStart = rope.lineStartByteOffset(line)
  let lineEnd = rope.lineEndByteOffset(line)
  let lineLen = lineEnd - lineStart

  if col < 0 or col > lineLen:
    raise newException(
      IndexDefect, "Rope column out of valid range [0.." & $lineLen & "]: " & $col
    )

  let byteOffset = lineStart + col
  let (left, right) = splitNode(rope.root, byteOffset)
  let newText = textToNode(text)
  rope.root = concatNodes(concatNodes(left, newText), right)
  rope.cachedLineCount = rope.root.lineBreakCount + 1

proc deleteAtLineCol*(rope: Rope, line: int, col: int, count: int = 1) =
  ## Delete 'count' bytes starting from (line, column) position. O(log n).
  if count <= 0:
    raise newException(IndexDefect, "Rope delete count must be > 0")
  if line < 0 or line >= rope.cachedLineCount:
    raise newException(IndexDefect, "Rope line out of bounds: " & $line)

  let byteOffset = rope.lineStartByteOffset(line) + col
  if byteOffset >= rope.root.byteLen:
    return

  let actualCount = min(count, rope.root.byteLen - byteOffset)
  let (left, rest) = splitNode(rope.root, byteOffset)
  let (_, right) = splitNode(rest, actualCount)
  rope.root = concatNodes(left, right)
  if rope.root.byteLen == 0:
    rope.root = newLeaf("")
  rope.cachedLineCount = rope.root.lineBreakCount + 1

proc insert*(rope: Rope, index: int, text: string) =
  ## Insert text at linear byte index position. O(log n).
  if text.len == 0:
    return
  if index < 0:
    return

  let byteOffset = min(index, rope.root.byteLen)
  let (left, right) = splitNode(rope.root, byteOffset)
  let middle = textToNode(text)
  rope.root = concatNodes(concatNodes(left, middle), right)
  rope.cachedLineCount = rope.root.lineBreakCount + 1

proc insert*(rope: Rope, index: int, ch: char) =
  rope.insert(index, $ch)

proc delete*(rope: Rope, index: int, count: int = 1) =
  ## Delete 'count' bytes starting at linear byte index position. O(log n).
  if count <= 0 or index < 0:
    return
  if index >= rope.root.byteLen:
    return

  let actualCount = min(count, rope.root.byteLen - index)
  let (left, rest) = splitNode(rope.root, index)
  let (_, right) = splitNode(rest, actualCount)
  rope.root = concatNodes(left, right)
  if rope.root.byteLen == 0:
    rope.root = newLeaf("")
  rope.cachedLineCount = rope.root.lineBreakCount + 1

proc substring*(rope: Rope, start: int, length: int): string =
  ## Extract substring by linear byte index. O(log n + L).
  if length <= 0 or start < 0:
    return ""
  substringBytes(rope.root, start, length)

proc `[]`*[T, U: Ordinal](rope: Rope, x: HSlice[T, U]): string =
  let
    start = x.a.int
    endIdx = x.b.int
  if start < 0 or endIdx < start:
    return ""
  let length = endIdx - start + 1
  rope.substring(start, length)

proc clear*(rope: Rope) =
  rope.root = newLeaf("")
  rope.cachedLineCount = 1

proc appendLeaves(node: RopeNode, acc: var string) =
  ## In-order walk emitting each leaf's raw bytes (newlines included).
  case node.kind
  of rnkLeaf:
    acc.add(node.text)
  of rnkInternal:
    for child in node.children:
      appendLeaves(child, acc)

proc `$`*(rope: Rope): string =
  ## Convert entire buffer to string.
  ## Leaves store the lines joined by '\n', so an in-order leaf walk rebuilds the
  ## buffer in O(n) (no per-line tree descent). An empty final line keeps no
  ## separator newline in storage; re-add it to match the flat-string convention.
  if rope.cachedLineCount == 0:
    return ""

  result = newStringOfCap(rope.root.byteLen + 1)
  appendLeaves(rope.root, result)
  if rope.cachedLineCount > 1 and rope.getLine(rope.cachedLineCount - 1).len == 0:
    result.add('\n')

iterator chars*(rope: Rope): char =
  ## In-order leaf walk yielding each byte; O(n), matches `$` (incl. empty final
  ## line) without per-line tree descent.
  if rope.cachedLineCount > 0:
    var stack = @[rope.root]
    while stack.len > 0:
      let node = stack.pop()
      case node.kind
      of rnkLeaf:
        for ch in node.text:
          yield ch
      of rnkInternal:
        for i in countdown(node.children.len - 1, 0):
          stack.add(node.children[i])
    # empty final line keeps no separator newline in storage; re-add it
    if rope.cachedLineCount > 1 and rope.getLine(rope.cachedLineCount - 1).len == 0:
      yield '\n'

iterator lines*(rope: Rope): string =
  ## In-order leaf walk splitting on '\n'; O(n), yields exactly cachedLineCount
  ## lines (leaves store the lines joined by '\n').
  var cur = ""
  var stack = @[rope.root]
  while stack.len > 0:
    let node = stack.pop()
    case node.kind
    of rnkLeaf:
      for ch in node.text:
        if ch == '\n':
          yield cur
          cur.setLen(0)
        else:
          cur.add(ch)
    of rnkInternal:
      for i in countdown(node.children.len - 1, 0):
        stack.add(node.children[i])
  yield cur

proc estimateMemoryUsageNode(node: RopeNode): int =
  result = sizeof(RopeNode)
  case node.kind
  of rnkLeaf:
    result += sizeof(string) + node.text.len
  of rnkInternal:
    result += sizeof(seq[RopeNode]) + node.children.len * sizeof(RopeNode)
    for child in node.children:
      result += estimateMemoryUsageNode(child)

proc estimateMemoryUsage*(rope: Rope): int =
  result = sizeof(Rope)
  result += estimateMemoryUsageNode(rope.root)

proc getTreeInfo*(rope: Rope): tuple[height: int, leafCount: int, totalBytes: int] =
  var leafCount = 0
  proc countLeaves(node: RopeNode) =
    case node.kind
    of rnkLeaf:
      inc leafCount
    of rnkInternal:
      for child in node.children:
        countLeaves(child)

  countLeaves(rope.root)
  (height: rope.root.height, leafCount: leafCount, totalBytes: rope.root.byteLen)
