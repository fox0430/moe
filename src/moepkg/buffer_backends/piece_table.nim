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

## Piece Tree buffer backend
##
## Stores text as a set of pieces referencing two buffers (original + add),
## organized in a Red-Black Tree for O(log n) operations.

import std/algorithm

type
  RBColor = enum
    rbRed
    rbBlack

  BufferIndex = enum
    biOriginal
    biAdd

  PieceBufferPosition = object
    line: int
    column: int

  PieceTreeNodeObj = object
    bufferIndex: BufferIndex
    start: PieceBufferPosition
    endPos: PieceBufferPosition
    length: int
    lineFeedCount: int

    color: RBColor
    left, right: PieceTreeNode

    # Subtree size metadata (total of entire subtree rooted at this node)
    subtreeLength: int
    subtreeLineFeedCount: int

  PieceTreeNode = ref PieceTreeNodeObj

  TextPieceBuffer = ref object
    value: string
    lineStarts: seq[int]

  PieceTable* = ref object
    buffers: array[BufferIndex, TextPieceBuffer]
    root: PieceTreeNode
    cachedLineCount*: int
    cachedByteLen*: int

  PieceNodeData = tuple[start, endPos: PieceBufferPosition, length, lineFeedCount: int]

  PieceTableSnapshot* = object
    root: PieceTreeNode
    buffers: array[BufferIndex, TextPieceBuffer] # ref copy (shared)
    cachedLineCount: int
    cachedByteLen: int

proc copyNode(n: PieceTreeNode): PieceTreeNode {.inline.} =
  ## Shallow copy for path-copying. Children are shared.
  PieceTreeNode(
    bufferIndex: n.bufferIndex,
    start: n.start,
    endPos: n.endPos,
    length: n.length,
    lineFeedCount: n.lineFeedCount,
    color: n.color,
    left: n.left,
    right: n.right,
    subtreeLength: n.subtreeLength,
    subtreeLineFeedCount: n.subtreeLineFeedCount,
  )

template leftLen(node: PieceTreeNode): int =
  if node.left.isNil: 0 else: node.left.subtreeLength

template leftLF(node: PieceTreeNode): int =
  if node.left.isNil: 0 else: node.left.subtreeLineFeedCount

proc updateSubtreeMetrics(node: PieceTreeNode) {.inline.} =
  ## Recompute subtreeLength and subtreeLineFeedCount from children + self
  let ll = if node.left.isNil: 0 else: node.left.subtreeLength
  let rl = if node.right.isNil: 0 else: node.right.subtreeLength
  node.subtreeLength = ll + node.length + rl

  let llf = if node.left.isNil: 0 else: node.left.subtreeLineFeedCount
  let rlf = if node.right.isNil: 0 else: node.right.subtreeLineFeedCount
  node.subtreeLineFeedCount = llf + node.lineFeedCount + rlf

proc computeLineStarts(s: string): seq[int] =
  result = @[0]
  for i in 0 ..< s.len:
    if s[i] == '\n':
      result.add(i + 1)

proc bufferOffset(buf: TextPieceBuffer, pos: PieceBufferPosition): int {.inline.} =
  buf.lineStarts[pos.line] + pos.column

proc bufferLineForOffset(buf: TextPieceBuffer, byteOffset: int): int {.inline.} =
  ## Find the line number in the buffer for a given byte offset.
  ## Uses binary search on lineStarts for O(log m) performance.
  upperBound(buf.lineStarts, byteOffset) - 1

proc newNodeFromData(
    data: PieceTreeNode, color: RBColor, left, right: PieceTreeNode
): PieceTreeNode {.inline.} =
  ## Create a new node with data's piece data. Recomputes subtree metrics.
  result = PieceTreeNode(
    bufferIndex: data.bufferIndex,
    start: data.start,
    endPos: data.endPos,
    length: data.length,
    lineFeedCount: data.lineFeedCount,
    color: color,
    left: left,
    right: right,
    subtreeLength: 0,
    subtreeLineFeedCount: 0,
  )
  result.updateSubtreeMetrics()

proc balancedTriple(x, y, z: PieceTreeNode, a, b, c, d: PieceTreeNode): PieceTreeNode =
  let left = newNodeFromData(x, rbBlack, a, b)
  let right = newNodeFromData(z, rbBlack, c, d)
  newNodeFromData(y, rbRed, left, right)

proc balance(color: RBColor, left, right, node: PieceTreeNode): PieceTreeNode =
  ## Okasaki balance: node = piece data holder, color/left/right = structure params
  if color == rbBlack:
    let l = left
    let r = right
    if not l.isNil and l.color == rbRed and not l.left.isNil and l.left.color == rbRed:
      # Case 1: left-left
      return balancedTriple(l.left, l, node, l.left.left, l.left.right, l.right, r)
    if not l.isNil and l.color == rbRed and not l.right.isNil and l.right.color == rbRed:
      # Case 2: left-right
      return balancedTriple(l, l.right, node, l.left, l.right.left, l.right.right, r)
    if not r.isNil and r.color == rbRed and not r.left.isNil and r.left.color == rbRed:
      # Case 3: right-left
      return balancedTriple(node, r.left, r, l, r.left.left, r.left.right, r.right)
    if not r.isNil and r.color == rbRed and not r.right.isNil and r.right.color == rbRed:
      # Case 4: right-right
      return balancedTriple(node, r, r.right, l, r.left, r.right.left, r.right.right)
  newNodeFromData(node, color, left, right)

proc pInsertAtOffset(
    root: PieceTreeNode, offset: int, newNode: PieceTreeNode
): PieceTreeNode =
  if root.isNil:
    return newNode
  let ll = root.leftLen
  if offset <= ll:
    let newLeft = pInsertAtOffset(root.left, offset, newNode)
    return balance(root.color, newLeft, root.right, root)
  else:
    let newRight = pInsertAtOffset(root.right, offset - ll - root.length, newNode)
    return balance(root.color, root.left, newRight, root)

proc pInsert(root: PieceTreeNode, offset: int, newNode: PieceTreeNode): PieceTreeNode =
  result = pInsertAtOffset(root, offset, newNode)
  if not result.isNil and result.color != rbBlack:
    result.color = rbBlack

proc fixLeftDeficit(
    node: PieceTreeNode, left, right: PieceTreeNode
): tuple[tree: PieceTreeNode, deficit: bool] =
  ## Fix black-height deficit in the left subtree.
  let sib = right
  if sib.isNil:
    # Should not happen in a valid RB tree, but handle gracefully
    let n = newNodeFromData(node, rbBlack, left, right)
    return (n, true)

  if sib.color == rbRed:
    # Case 1: sibling is red -> rotate, recurse
    # After rotation, node effectively becomes Red (sib takes node's color)
    var redNode = copyNode(node)
    redNode.color = rbRed
    let (fixedInner, _) = fixLeftDeficit(redNode, left, sib.left)
    let r = newNodeFromData(sib, node.color, fixedInner, sib.right)
    return (r, false)

  # Sibling is black
  let slIsBlack = sib.left.isNil or sib.left.color == rbBlack
  let srIsBlack = sib.right.isNil or sib.right.color == rbBlack

  if slIsBlack and srIsBlack:
    # Case 2: both nephews black -> recolor sibling red, propagate deficit
    let newSib = copyNode(sib)
    newSib.color = rbRed
    let n = newNodeFromData(node, node.color, left, newSib)
    if node.color == rbRed:
      # Absorb deficit by making node black
      n.color = rbBlack
      return (n, false)
    else:
      return (n, true)

  if not srIsBlack:
    # Case 4: far nephew (right) is red -> single rotation
    let newLeft = newNodeFromData(node, rbBlack, left, sib.left)
    let newRight = copyNode(sib.right)
    newRight.color = rbBlack
    let r = newNodeFromData(sib, node.color, newLeft, newRight)
    return (r, false)

  # Case 3: near nephew (left) is red, far is black -> double rotation
  let sl = sib.left
  let newSibRight = newNodeFromData(sib, rbBlack, sl.right, sib.right)
  let newLeft = newNodeFromData(node, rbBlack, left, sl.left)
  let r = newNodeFromData(sl, node.color, newLeft, newSibRight)
  return (r, false)

proc fixRightDeficit(
    node: PieceTreeNode, left, right: PieceTreeNode
): tuple[tree: PieceTreeNode, deficit: bool] =
  ## Fix black-height deficit in the right subtree (mirror of fixLeftDeficit).
  let sib = left
  if sib.isNil:
    let n = newNodeFromData(node, rbBlack, left, right)
    return (n, true)

  if sib.color == rbRed:
    # Case 1: sibling is red -> rotate, recurse
    var redNode = copyNode(node)
    redNode.color = rbRed
    let (fixedInner, _) = fixRightDeficit(redNode, sib.right, right)
    let r = newNodeFromData(sib, node.color, sib.left, fixedInner)
    return (r, false)

  # Sibling is black
  let slIsBlack = sib.left.isNil or sib.left.color == rbBlack
  let srIsBlack = sib.right.isNil or sib.right.color == rbBlack

  if slIsBlack and srIsBlack:
    # Case 2: both nephews black -> recolor sibling red, propagate deficit
    let newSib = copyNode(sib)
    newSib.color = rbRed
    let n = newNodeFromData(node, node.color, newSib, right)
    if node.color == rbRed:
      n.color = rbBlack
      return (n, false)
    else:
      return (n, true)

  if not slIsBlack:
    # Case 4: far nephew (left) is red -> single rotation
    let newRight = newNodeFromData(node, rbBlack, sib.right, right)
    let newLeft = copyNode(sib.left)
    newLeft.color = rbBlack
    let r = newNodeFromData(sib, node.color, newLeft, newRight)
    return (r, false)

  # Case 3: near nephew (right) is red, far is black -> double rotation
  let sr = sib.right
  let newSibLeft = newNodeFromData(sib, rbBlack, sib.left, sr.left)
  let newRight = newNodeFromData(node, rbBlack, sr.right, right)
  let r = newNodeFromData(sr, node.color, newSibLeft, newRight)
  return (r, false)

proc pRemoveMin(
    root: PieceTreeNode
): tuple[tree: PieceTreeNode, removed: PieceTreeNode, deficit: bool] =
  ## Remove the minimum (leftmost) node. Returns (newTree, removedNode, deficit).
  if root.left.isNil:
    # This is the minimum
    let replacement = root.right
    let deficit = root.color == rbBlack and root.right.isNil
    if not replacement.isNil and root.color == rbBlack:
      let r = copyNode(replacement)
      r.color = rbBlack
      return (r, root, false)
    return (replacement, root, deficit)
  let (newLeft, removed, deficit) = pRemoveMin(root.left)
  if deficit:
    let (fixed, stillDeficit) = fixLeftDeficit(root, newLeft, root.right)
    return (fixed, removed, stillDeficit)
  else:
    let n = newNodeFromData(root, root.color, newLeft, root.right)
    return (n, removed, false)

proc pRemoveAtOffset(
    root: PieceTreeNode, offset: int
): tuple[tree: PieceTreeNode, removed: PieceTreeNode, deficit: bool] =
  ## Remove the node at the given offset. Returns (newTree, removedNode, deficit).
  if root.isNil:
    return (nil, nil, false)

  let ll = root.leftLen
  if offset < ll:
    # Target is in left subtree
    let (newLeft, removed, deficit) = pRemoveAtOffset(root.left, offset)
    if deficit:
      let (fixed, stillDeficit) = fixLeftDeficit(root, newLeft, root.right)
      return (fixed, removed, stillDeficit)
    else:
      let n = newNodeFromData(root, root.color, newLeft, root.right)
      return (n, removed, false)
  elif offset < ll + root.length:
    # This is the target node
    if root.left.isNil and root.right.isNil:
      # Leaf
      let deficit = root.color == rbBlack
      return (nil, root, deficit)
    elif root.left.isNil:
      # Only right child
      if root.color == rbBlack:
        if not root.right.isNil:
          let r = copyNode(root.right)
          r.color = rbBlack
          return (r, root, false)
        return (nil, root, true)
      return (root.right, root, false)
    elif root.right.isNil:
      # Only left child
      if root.color == rbBlack:
        if not root.left.isNil:
          let l = copyNode(root.left)
          l.color = rbBlack
          return (l, root, false)
        return (nil, root, true)
      return (root.left, root, false)
    else:
      # Two children: replace with in-order successor (min of right subtree)
      let (newRight, successor, deficit) = pRemoveMin(root.right)
      if deficit:
        # successor takes root's color for balancing purposes
        var s = copyNode(successor)
        s.color = root.color
        let (fixed, stillDeficit) = fixRightDeficit(s, root.left, newRight)
        return (fixed, root, stillDeficit)
      else:
        let n = newNodeFromData(successor, root.color, root.left, newRight)
        return (n, root, false)
  else:
    # Target is in right subtree
    let (newRight, removed, deficit) =
      pRemoveAtOffset(root.right, offset - ll - root.length)
    if deficit:
      let (fixed, stillDeficit) = fixRightDeficit(root, root.left, newRight)
      return (fixed, removed, stillDeficit)
    else:
      let n = newNodeFromData(root, root.color, root.left, newRight)
      return (n, removed, false)

proc pDeleteAtOffset(root: PieceTreeNode, offset: int): PieceTreeNode =
  let (newRoot, _, _) = pRemoveAtOffset(root, offset)
  if not newRoot.isNil and newRoot.color != rbBlack:
    newRoot.color = rbBlack
  newRoot

proc pModifyAtOffset(
    root: PieceTreeNode, offset: int, modifier: proc(d: PieceNodeData): PieceNodeData
): PieceTreeNode =
  if root.isNil:
    return nil
  let ll = root.leftLen
  if offset < ll:
    let n = copyNode(root)
    n.left = pModifyAtOffset(root.left, offset, modifier)
    n.updateSubtreeMetrics()
    return n
  elif offset < ll + root.length:
    let oldData: PieceNodeData =
      (root.start, root.endPos, root.length, root.lineFeedCount)
    let newData = modifier(oldData)
    let n = copyNode(root)
    n.start = newData.start
    n.endPos = newData.endPos
    n.length = newData.length
    n.lineFeedCount = newData.lineFeedCount
    n.updateSubtreeMetrics()
    return n
  else:
    let n = copyNode(root)
    n.right = pModifyAtOffset(root.right, offset - ll - root.length, modifier)
    n.updateSubtreeMetrics()
    return n

proc canCoalesce(a, b: PieceTreeNode): bool {.inline.} =
  ## Two adjacent pieces can be coalesced if they reference the same buffer
  ## and a's end position equals b's start position.
  not a.isNil and not b.isNil and a.bufferIndex == b.bufferIndex and a.endPos == b.start

proc nodeByOffset(
    pt: PieceTable, offset: int
): tuple[node: PieceTreeNode, localOffset: int] =
  var remaining = offset
  var cur = pt.root
  while not cur.isNil:
    let ll = cur.leftLen
    if remaining < ll:
      cur = cur.left
    elif remaining < ll + cur.length:
      return (cur, remaining - ll)
    else:
      remaining -= ll + cur.length
      cur = cur.right
  (nil, 0)

proc tryCoalesceAtOffset(pt: PieceTable, offset: int) =
  ## Try to merge the node at offset with its in-order neighbors.
  ## Looks up node, predecessor, successor once upfront, then performs
  ## at most 1 modify + 2 deletes.
  if pt.root.isNil or pt.cachedByteLen == 0:
    return

  let clampedOff = min(offset, pt.cachedByteLen - 1)
  let (node, localOff) = pt.nodeByOffset(clampedOff)
  if node.isNil:
    return

  let nodeStart = clampedOff - localOff
  let nodeEnd = nodeStart + node.length

  # Look up predecessor and successor once
  var pred: PieceTreeNode = nil
  var predStart = 0
  if nodeStart > 0:
    let (p, pLocal) = pt.nodeByOffset(nodeStart - 1)
    pred = p
    if not pred.isNil:
      predStart = (nodeStart - 1) - pLocal

  var succ: PieceTreeNode = nil
  if nodeEnd < pt.cachedByteLen:
    let (s, _) = pt.nodeByOffset(nodeEnd)
    succ = s

  let coalescePred = canCoalesce(pred, node)
  let coalesceSucc = canCoalesce(node, succ)

  if coalescePred and coalesceSucc:
    # Three-way merge: extend pred to cover node + succ, delete node + succ
    let newEndPos = succ.endPos
    let addLength = node.length + succ.length
    let addLF = node.lineFeedCount + succ.lineFeedCount
    pt.root = pModifyAtOffset(
      pt.root,
      predStart,
      proc(d: PieceNodeData): PieceNodeData =
        (d.start, newEndPos, d.length + addLength, d.lineFeedCount + addLF),
    )
    let mergedLen = pred.length + addLength
    # After modify, both node and succ sit at the same offset (right after pred)
    pt.root = pDeleteAtOffset(pt.root, predStart + mergedLen)
    pt.root = pDeleteAtOffset(pt.root, predStart + mergedLen)
  elif coalesceSucc:
    # Merge node + succ
    let newEndPos = succ.endPos
    let addLength = succ.length
    let addLF = succ.lineFeedCount
    pt.root = pModifyAtOffset(
      pt.root,
      nodeStart,
      proc(d: PieceNodeData): PieceNodeData =
        (d.start, newEndPos, d.length + addLength, d.lineFeedCount + addLF),
    )
    pt.root = pDeleteAtOffset(pt.root, nodeStart + node.length + addLength)
  elif coalescePred:
    # Merge pred + node
    let newEndPos = node.endPos
    let addLength = node.length
    let addLF = node.lineFeedCount
    pt.root = pModifyAtOffset(
      pt.root,
      predStart,
      proc(d: PieceNodeData): PieceNodeData =
        (d.start, newEndPos, d.length + addLength, d.lineFeedCount + addLF),
    )
    pt.root = pDeleteAtOffset(pt.root, predStart + pred.length + addLength)

proc lineStartByteOffset(pt: PieceTable, lineNumber: int): int =
  if lineNumber <= 0:
    return 0
  if lineNumber >= pt.cachedLineCount:
    return pt.cachedByteLen

  var linesRemaining = lineNumber
  var offset = 0
  var cur = pt.root
  while not cur.isNil:
    let ll = cur.leftLen
    let llf = cur.leftLF
    if linesRemaining <= llf:
      cur = cur.left
    elif linesRemaining <= llf + cur.lineFeedCount:
      let localLine = linesRemaining - llf
      let buf = pt.buffers[cur.bufferIndex]
      let sOff = buf.bufferOffset(cur.start)
      let targetLineInBuf = cur.start.line + localLine
      return offset + ll + (buf.lineStarts[targetLineInBuf] - sOff)
    else:
      linesRemaining -= llf + cur.lineFeedCount
      offset += ll + cur.length
      cur = cur.right

  pt.cachedByteLen

proc lineByteRange(pt: PieceTable, lineNumber: int): tuple[startOff: int, endOff: int] =
  ## Returns (startByteOffset, endByteOffset) for the given line in a single
  ## tree traversal when possible.
  if lineNumber < 0 or lineNumber >= pt.cachedLineCount:
    return (pt.cachedByteLen, pt.cachedByteLen)

  if lineNumber == pt.cachedLineCount - 1:
    return (pt.lineStartByteOffset(lineNumber), pt.cachedByteLen)

  if lineNumber <= 0:
    return (0, pt.lineStartByteOffset(1) - 1)

  # Tree walk to find line N start, opportunistically find N+1
  var linesRemaining = lineNumber
  var offset = 0
  var cur = pt.root
  while not cur.isNil:
    let ll = cur.leftLen
    let llf = cur.leftLF
    if linesRemaining <= llf:
      cur = cur.left
    elif linesRemaining <= llf + cur.lineFeedCount:
      let localLine = linesRemaining - llf
      let buf = pt.buffers[cur.bufferIndex]
      let sOff = buf.bufferOffset(cur.start)
      let targetLineInBuf = cur.start.line + localLine
      let startOff = offset + ll + (buf.lineStarts[targetLineInBuf] - sOff)
      if localLine < cur.lineFeedCount:
        # Next line also starts within this node
        let nextLineInBuf = targetLineInBuf + 1
        let endOff = offset + ll + (buf.lineStarts[nextLineInBuf] - sOff) - 1
        return (startOff, endOff)
      else:
        # Next line starts in a subsequent node, fallback
        let endOff = pt.lineStartByteOffset(lineNumber + 1) - 1
        return (startOff, endOff)
    else:
      linesRemaining -= llf + cur.lineFeedCount
      offset += ll + cur.length
      cur = cur.right

  (pt.cachedByteLen, pt.cachedByteLen)

proc substringBytes(pt: PieceTable, start, length: int): string =
  if length <= 0 or start >= pt.cachedByteLen:
    return ""
  let actualLen = min(length, pt.cachedByteLen - start)
  result = newStringOfCap(actualLen)
  var remaining = actualLen

  # Find the starting node using tree descent, building a stack for in-order
  var stack: array[64, PieceTreeNode]
  var sp = 0
  var cur = pt.root
  var pos = start
  var found = false

  while not found:
    if cur.isNil:
      break
    let ll = cur.leftLen
    if pos < ll:
      stack[sp] = cur
      inc sp
      cur = cur.left
    elif pos < ll + cur.length:
      # Found the starting node — process it
      let localOff = pos - ll
      let buf = pt.buffers[cur.bufferIndex]
      let sOff = buf.bufferOffset(cur.start)
      let take = min(remaining, cur.length - localOff)
      result.add(buf.value[sOff + localOff ..< sOff + localOff + take])
      remaining -= take
      # Continue in-order: go to right subtree, then pop stack
      cur = cur.right
      found = true
    else:
      pos -= ll + cur.length
      cur = cur.right

  # Continue collecting from subsequent nodes via stack-based in-order
  while remaining > 0:
    while not cur.isNil:
      stack[sp] = cur
      inc sp
      cur = cur.left
    if sp == 0:
      break
    dec sp
    cur = stack[sp]
    let b = pt.buffers[cur.bufferIndex]
    let s = b.bufferOffset(cur.start)
    let tk = min(remaining, cur.length)
    result.add(b.value[s ..< s + tk])
    remaining -= tk
    cur = cur.right

proc newPieceTable*(): PieceTable =
  PieceTable(
    buffers: [
      TextPieceBuffer(value: "", lineStarts: @[0]),
      TextPieceBuffer(value: "", lineStarts: @[0]),
    ],
    root: nil,
    cachedLineCount: 1,
    cachedByteLen: 0,
  )

proc newPieceTable*(text: sink string): PieceTable =
  var content = move text
  if content.len > 0 and content[^1] == '\n':
    content.setLen(content.len - 1)

  if content.len == 0:
    return PieceTable(
      buffers: [
        TextPieceBuffer(value: "", lineStarts: @[0]),
        TextPieceBuffer(value: "", lineStarts: @[0]),
      ],
      root: nil,
      cachedLineCount: 1,
      cachedByteLen: 0,
    )

  let lineStarts = computeLineStarts(content)
  let lfCount = lineStarts.len - 1

  let endLine = lineStarts.len - 1
  let contentLen = content.len
  let endCol = contentLen - lineStarts[endLine]

  let node = PieceTreeNode(
    bufferIndex: biOriginal,
    start: PieceBufferPosition(line: 0, column: 0),
    endPos: PieceBufferPosition(line: endLine, column: endCol),
    length: contentLen,
    lineFeedCount: lfCount,
    color: rbBlack,
    left: nil,
    right: nil,
    subtreeLength: contentLen,
    subtreeLineFeedCount: lfCount,
  )

  PieceTable(
    buffers: [
      TextPieceBuffer(value: move content, lineStarts: lineStarts),
      TextPieceBuffer(value: "", lineStarts: @[0]),
    ],
    root: node,
    cachedLineCount: lfCount + 1,
    cachedByteLen: contentLen,
  )

proc lineCount*(pt: PieceTable): int {.inline.} =
  pt.cachedLineCount

proc len*(pt: PieceTable): int {.inline.} =
  pt.cachedLineCount

proc getLine*(pt: PieceTable, lineNumber: int): string =
  if lineNumber < 0 or lineNumber >= pt.cachedLineCount:
    return ""
  let (start, endOff) = pt.lineByteRange(lineNumber)
  let length = endOff - start
  if length <= 0:
    return ""
  pt.substringBytes(start, length)

proc `[]`*(pt: PieceTable, lineNumber: int): string =
  pt.getLine(lineNumber)

proc addToAddBuffer(
    pt: PieceTable, text: string
): tuple[start: PieceBufferPosition, endPos: PieceBufferPosition, lfCount: int] =
  let buf = pt.buffers[biAdd]
  let startOff = buf.value.len
  let startLine = buf.lineStarts.len - 1
  let startCol = startOff - buf.lineStarts[startLine]

  buf.value.add(text)

  var lfCount = 0
  for i in 0 ..< text.len:
    if text[i] == '\n':
      inc lfCount
      buf.lineStarts.add(startOff + i + 1)

  let endLine = buf.lineStarts.len - 1
  let endCol = buf.value.len - buf.lineStarts[endLine]

  (
    PieceBufferPosition(line: startLine, column: startCol),
    PieceBufferPosition(line: endLine, column: endCol),
    lfCount,
  )

proc newPieceNode(
    pt: PieceTable,
    bufIdx: BufferIndex,
    start, endPos: PieceBufferPosition,
    length, lfCount: int,
): PieceTreeNode =
  PieceTreeNode(
    bufferIndex: bufIdx,
    start: start,
    endPos: endPos,
    length: length,
    lineFeedCount: lfCount,
    color: rbRed,
    left: nil,
    right: nil,
    subtreeLength: length,
    subtreeLineFeedCount: lfCount,
  )

proc insertTextAt(pt: PieceTable, offset: int, text: string) =
  if text.len == 0:
    return

  let (start, endPos, lfCount) = pt.addToAddBuffer(text)
  let newNode = pt.newPieceNode(biAdd, start, endPos, text.len, lfCount)

  if pt.root.isNil:
    pt.root = newNode
    newNode.color = rbBlack
    pt.cachedByteLen = text.len
    pt.cachedLineCount = lfCount + 1
    return

  let clampedOffset = min(offset, pt.cachedByteLen)

  if clampedOffset == 0 or clampedOffset >= pt.cachedByteLen:
    # Insert at boundary — no split needed
    pt.root = pInsert(pt.root, clampedOffset, newNode)
  else:
    let (node, localOff) = pt.nodeByOffset(clampedOffset)
    if node.isNil:
      pt.root = pInsert(pt.root, clampedOffset, newNode)
    elif localOff == 0:
      # Node boundary — no split needed
      pt.root = pInsert(pt.root, clampedOffset, newNode)
    else:
      # Split the node: trim existing to left half, insert new + right half
      let buf = pt.buffers[node.bufferIndex]
      let nodeStartOff = buf.bufferOffset(node.start)
      let leftEndOff = nodeStartOff + localOff
      let leftEndLine = buf.bufferLineForOffset(leftEndOff)
      let leftEndCol = leftEndOff - buf.lineStarts[leftEndLine]
      let leftEnd = PieceBufferPosition(line: leftEndLine, column: leftEndCol)
      let leftLF = leftEndLine - node.start.line

      let rightStart = leftEnd
      let rightLF = node.lineFeedCount - leftLF
      let rightLen = node.length - localOff

      let nodeBufIdx = node.bufferIndex
      let oldEnd = node.endPos
      let leftLen = localOff

      # Step 1: Trim existing node to left half via pModifyAtOffset
      pt.root = pModifyAtOffset(
        pt.root,
        clampedOffset - localOff,
        proc(d: PieceNodeData): PieceNodeData =
          (d.start, leftEnd, leftLen, leftLF),
      )

      # Step 2: Insert new piece after left half
      pt.root = pInsert(pt.root, clampedOffset - localOff + leftLen, newNode)

      # Step 3: Insert right half after new piece
      let rightNode = pt.newPieceNode(nodeBufIdx, rightStart, oldEnd, rightLen, rightLF)
      pt.root =
        pInsert(pt.root, clampedOffset - localOff + leftLen + text.len, rightNode)

  pt.cachedByteLen += text.len
  pt.cachedLineCount += lfCount
  pt.tryCoalesceAtOffset(clampedOffset)

proc deleteNodeAt(pt: PieceTable, offset: int, count: int) =
  if count <= 0 or offset >= pt.cachedByteLen:
    return

  let actualCount = min(count, pt.cachedByteLen - offset)
  var remaining = actualCount
  var pos = offset

  while remaining > 0 and not pt.root.isNil:
    let (node, localOff) = pt.nodeByOffset(pos)
    if node.isNil:
      break

    let availableInNode = node.length - localOff
    let deleteFromNode = min(remaining, availableInNode)

    if localOff == 0 and deleteFromNode == node.length:
      # Delete entire node
      pt.root = pDeleteAtOffset(pt.root, pos)
      remaining -= deleteFromNode
    elif localOff == 0:
      # Delete from beginning of node — trim start
      let buf = pt.buffers[node.bufferIndex]
      let nodeStartOff = buf.bufferOffset(node.start)
      let newStartOff = nodeStartOff + deleteFromNode
      let newStartLine = buf.bufferLineForOffset(newStartOff)
      let newStartCol = newStartOff - buf.lineStarts[newStartLine]
      let deletedLF = newStartLine - node.start.line
      let newLen = node.length - deleteFromNode
      let newLFC = node.lineFeedCount - deletedLF

      let newStart = PieceBufferPosition(line: newStartLine, column: newStartCol)
      pt.root = pModifyAtOffset(
        pt.root,
        pos,
        proc(d: PieceNodeData): PieceNodeData =
          (newStart, d.endPos, newLen, newLFC),
      )
      remaining -= deleteFromNode
    elif localOff + deleteFromNode == node.length:
      # Delete from end of node — trim end
      let buf = pt.buffers[node.bufferIndex]
      let nodeStartOff = buf.bufferOffset(node.start)
      let newEndOff = nodeStartOff + localOff
      let newEndLine = buf.bufferLineForOffset(newEndOff)
      let newEndCol = newEndOff - buf.lineStarts[newEndLine]
      let newLen = localOff
      let deletedLF = node.endPos.line - newEndLine
      let newLFC = node.lineFeedCount - deletedLF
      let nodeAbsStart = pos - localOff

      let newEnd = PieceBufferPosition(line: newEndLine, column: newEndCol)
      pt.root = pModifyAtOffset(
        pt.root,
        nodeAbsStart,
        proc(d: PieceNodeData): PieceNodeData =
          (d.start, newEnd, newLen, newLFC),
      )
      remaining -= deleteFromNode
    else:
      # Delete from middle — split into left + right, removing middle
      let buf = pt.buffers[node.bufferIndex]
      let nodeStartOff = buf.bufferOffset(node.start)
      let nodeAbsStart = pos - localOff

      let leftEndOff = nodeStartOff + localOff
      let leftEndLine = buf.bufferLineForOffset(leftEndOff)
      let leftEndCol = leftEndOff - buf.lineStarts[leftEndLine]
      let leftEnd = PieceBufferPosition(line: leftEndLine, column: leftEndCol)
      let leftLF = leftEndLine - node.start.line
      let leftLen = localOff

      let rightStartOff = nodeStartOff + localOff + deleteFromNode
      let rightStartLine = buf.bufferLineForOffset(rightStartOff)
      let rightStartCol = rightStartOff - buf.lineStarts[rightStartLine]
      let rightStart = PieceBufferPosition(line: rightStartLine, column: rightStartCol)

      let deletedLF = rightStartLine - leftEndLine
      let rightLF = node.lineFeedCount - leftLF - deletedLF
      let rightLen = node.length - localOff - deleteFromNode
      let oldEnd = node.endPos
      let nodeBufIdx = node.bufferIndex

      # Trim existing node to left piece
      pt.root = pModifyAtOffset(
        pt.root,
        nodeAbsStart,
        proc(d: PieceNodeData): PieceNodeData =
          (d.start, leftEnd, leftLen, leftLF),
      )

      # Insert right piece after left piece
      let rightNode = pt.newPieceNode(nodeBufIdx, rightStart, oldEnd, rightLen, rightLF)
      pt.root = pInsert(pt.root, nodeAbsStart + leftLen, rightNode)

      remaining -= deleteFromNode

  pt.cachedByteLen -= actualCount
  pt.cachedLineCount =
    if pt.root.isNil:
      1
    else:
      pt.root.subtreeLineFeedCount + 1

  # Try to coalesce at the deletion boundary
  if not pt.root.isNil and pt.cachedByteLen > 0:
    let boundaryPos = min(offset, pt.cachedByteLen - 1)
    pt.tryCoalesceAtOffset(boundaryPos)

proc `[]=`*(pt: PieceTable, lineNumber: int, content: string) =
  if lineNumber < 0 or lineNumber >= pt.cachedLineCount:
    raise newException(IndexDefect, "PieceTable line out of bounds")
  let (start, endOff) = pt.lineByteRange(lineNumber)
  let oldLen = endOff - start
  if oldLen > 0:
    pt.deleteNodeAt(start, oldLen)
  if content.len > 0:
    pt.insertTextAt(start, content)

proc replaceLine*(pt: PieceTable, lineNumber: int, content: string) =
  if lineNumber < 0 or lineNumber >= pt.cachedLineCount:
    raise newException(IndexDefect, "PieceTable line out of bounds")
  pt[lineNumber] = content

proc modifyLineContent*(pt: PieceTable, lineNumber: int, f: proc(s: var string)) =
  if lineNumber < 0 or lineNumber >= pt.cachedLineCount:
    raise newException(IndexDefect, "PieceTable line out of bounds")
  var line = pt.getLine(lineNumber)
  f(line)
  pt[lineNumber] = line

proc insertLine*(pt: PieceTable, lineNumber: int, content: string) =
  if lineNumber < 0 or lineNumber > pt.cachedLineCount:
    raise newException(
      IndexDefect,
      "PieceTable line index out of valid range [0.." & $pt.cachedLineCount & "]",
    )
  if pt.cachedLineCount == 0:
    pt.insertTextAt(0, content)
    if not pt.root.isNil:
      pt.cachedLineCount = pt.root.subtreeLineFeedCount + 1
    else:
      pt.cachedLineCount = 1
    return
  if lineNumber == pt.cachedLineCount:
    pt.insertTextAt(pt.cachedByteLen, "\n" & content)
  else:
    let offset = pt.lineStartByteOffset(lineNumber)
    pt.insertTextAt(offset, content & "\n")

proc deleteLine*(pt: PieceTable, lineNumber: int) =
  if lineNumber < 0 or lineNumber >= pt.cachedLineCount:
    raise newException(IndexDefect, "PieceTable line out of bounds")
  if pt.cachedLineCount == 1:
    if pt.cachedByteLen > 0:
      pt.deleteNodeAt(0, pt.cachedByteLen)
    # Override deleteNodeAt's default (cachedLineCount=1 for empty tree)
    # to indicate "no lines" state; insertLine handles this at cachedLineCount==0
    pt.cachedLineCount = 0
    return
  let start = pt.lineStartByteOffset(lineNumber)
  if lineNumber == pt.cachedLineCount - 1:
    pt.deleteNodeAt(start - 1, pt.cachedByteLen - start + 1)
  else:
    let endOff = pt.lineStartByteOffset(lineNumber + 1)
    pt.deleteNodeAt(start, endOff - start)

proc charAtLineCol*(pt: PieceTable, line: int, col: int): char =
  if line < 0 or line >= pt.cachedLineCount:
    raise newException(IndexDefect, "PieceTable line out of bounds")
  let (lineStart, lineEnd) = pt.lineByteRange(line)
  let lineLen = lineEnd - lineStart
  if col >= 0 and col < lineLen:
    let text = pt.substringBytes(lineStart + col, 1)
    if text.len > 0:
      return text[0]
    raise newException(IndexDefect, "PieceTable: failed to read byte")
  elif col == lineLen and line < pt.cachedLineCount - 1:
    return '\n'
  else:
    raise newException(IndexDefect, "PieceTable column out of bounds")

proc insertIntoLine*(pt: PieceTable, line, col: int, text: string) =
  if line < 0 or line >= pt.cachedLineCount:
    raise newException(IndexDefect, "PieceTable line out of bounds: " & $line)
  let (lineStart, lineEnd) = pt.lineByteRange(line)
  let lineLen = lineEnd - lineStart
  if col < 0 or col > lineLen:
    raise newException(
      IndexDefect, "PieceTable column out of valid range [0.." & $lineLen & "]: " & $col
    )
  pt.insertTextAt(lineStart + col, text)

proc deleteAtLineCol*(pt: PieceTable, line: int, col: int, count: int = 1) =
  if count <= 0:
    raise newException(IndexDefect, "PieceTable delete count must be > 0")
  if line < 0 or line >= pt.cachedLineCount:
    raise newException(IndexDefect, "PieceTable line out of bounds: " & $line)
  let byteOffset = pt.lineStartByteOffset(line) + col
  if byteOffset >= pt.cachedByteLen:
    return
  let actualCount = min(count, pt.cachedByteLen - byteOffset)
  pt.deleteNodeAt(byteOffset, actualCount)

proc clear*(pt: PieceTable) =
  pt.root = nil
  pt.buffers[biOriginal] = TextPieceBuffer(value: "", lineStarts: @[0])
  pt.buffers[biAdd] = TextPieceBuffer(value: "", lineStarts: @[0])
  pt.cachedLineCount = 1
  pt.cachedByteLen = 0

proc flatten*(pt: PieceTable) =
  ## Rebuild the piece table with a single original-buffer piece.
  ## Clears the add buffer and removes all fragmentation.
  let text = pt.substringBytes(0, pt.cachedByteLen)

  pt.root = nil

  if text.len == 0:
    pt.buffers[biOriginal] = TextPieceBuffer(value: "", lineStarts: @[0])
    pt.buffers[biAdd] = TextPieceBuffer(value: "", lineStarts: @[0])
    pt.cachedLineCount = 1
    pt.cachedByteLen = 0
    return

  let lineStarts = computeLineStarts(text)
  let lfCount = lineStarts.len - 1
  let endLine = lineStarts.len - 1
  let endCol = text.len - lineStarts[endLine]

  let node = PieceTreeNode(
    bufferIndex: biOriginal,
    start: PieceBufferPosition(line: 0, column: 0),
    endPos: PieceBufferPosition(line: endLine, column: endCol),
    length: text.len,
    lineFeedCount: lfCount,
    color: rbBlack,
    left: nil,
    right: nil,
    subtreeLength: text.len,
    subtreeLineFeedCount: lfCount,
  )

  pt.buffers[biOriginal] = TextPieceBuffer(value: text, lineStarts: lineStarts)
  pt.buffers[biAdd] = TextPieceBuffer(value: "", lineStarts: @[0])
  pt.root = node
  pt.cachedLineCount = lfCount + 1
  pt.cachedByteLen = text.len

proc wasteRatio*(pt: PieceTable): float =
  ## Returns the ratio of unreferenced bytes to total buffer size.
  ## 0.0 means no waste, 1.0 means all waste.
  let totalBufSize = pt.buffers[biOriginal].value.len + pt.buffers[biAdd].value.len
  if totalBufSize == 0:
    return 0.0
  1.0 - (pt.cachedByteLen.float / totalBufSize.float)

proc maybeCompact*(pt: PieceTable, threshold: float = 0.5) =
  ## Flatten the piece table if the waste ratio exceeds the threshold.
  if pt.wasteRatio() > threshold:
    pt.flatten()

proc `$`*(pt: PieceTable): string =
  ## Returns text with the implicit trailing newline restored for file I/O.
  ## For logical lines, use `lines` iterator or `getLine` instead.
  if pt.cachedLineCount == 0:
    return ""
  result = newStringOfCap(pt.cachedByteLen + 1)
  # Stack-based in-order traversal
  var stack: array[64, PieceTreeNode]
  var sp = 0
  var cur = pt.root
  while cur != nil or sp > 0:
    while cur != nil:
      stack[sp] = cur
      inc sp
      cur = cur.left
    dec sp
    cur = stack[sp]
    let buf = pt.buffers[cur.bufferIndex]
    let sOff = buf.bufferOffset(cur.start)
    let eOff = buf.bufferOffset(cur.endPos)
    result.add(buf.value[sOff ..< eOff])
    cur = cur.right
  # Add trailing newline for multi-line buffer with empty last line
  if pt.cachedLineCount > 1 and result.len > 0 and result[^1] == '\n':
    result.add('\n')

iterator chars*(pt: PieceTable): char =
  ## Yields each byte matching `$` output (includes implicit trailing newline).
  var stack: array[64, PieceTreeNode]
  var sp = 0
  var cur = pt.root
  var lastCharWasLF = false
  while cur != nil or sp > 0:
    while cur != nil:
      stack[sp] = cur
      inc sp
      cur = cur.left
    dec sp
    cur = stack[sp]
    let buf = pt.buffers[cur.bufferIndex]
    let sOff = buf.bufferOffset(cur.start)
    let eOff = buf.bufferOffset(cur.endPos)
    for i in sOff ..< eOff:
      lastCharWasLF = buf.value[i] == '\n'
      yield buf.value[i]
    cur = cur.right
  # Add trailing newline for multi-line buffer with empty last line
  if pt.cachedLineCount > 1 and lastCharWasLF:
    yield '\n'

iterator lines*(pt: PieceTable): string =
  ## Yields cachedLineCount logical lines matching `getLine`.
  ## Does not include the trailing newline that `$` / `chars` add.
  if pt.cachedLineCount == 0:
    discard
  else:
    var currentLine = ""
    var stack: array[64, PieceTreeNode]
    var sp = 0
    var cur = pt.root
    while cur != nil or sp > 0:
      while cur != nil:
        stack[sp] = cur
        inc sp
        cur = cur.left
      dec sp
      cur = stack[sp]
      let buf = pt.buffers[cur.bufferIndex]
      let sOff = buf.bufferOffset(cur.start)
      let eOff = buf.bufferOffset(cur.endPos)
      var pos = sOff
      while pos < eOff:
        var nlPos = -1
        for j in pos ..< eOff:
          if buf.value[j] == '\n':
            nlPos = j
            break
        if nlPos >= 0:
          currentLine.add(buf.value[pos ..< nlPos])
          yield currentLine
          currentLine = ""
          pos = nlPos + 1
        else:
          currentLine.add(buf.value[pos ..< eOff])
          break
      cur = cur.right
    yield currentLine

proc estimateMemoryUsage*(pt: PieceTable): int =
  result = sizeof(PieceTable)
  result += pt.buffers[biOriginal].value.len
  result += pt.buffers[biAdd].value.len
  result += pt.buffers[biOriginal].lineStarts.len * sizeof(int)
  result += pt.buffers[biAdd].lineStarts.len * sizeof(int)
  # Stack-based in-order traversal for node count
  var stack: array[64, PieceTreeNode]
  var sp = 0
  var cur = pt.root
  while cur != nil or sp > 0:
    while cur != nil:
      stack[sp] = cur
      inc sp
      cur = cur.left
    dec sp
    cur = stack[sp]
    result += sizeof(PieceTreeNodeObj)
    cur = cur.right

proc getTableInfo*(
    pt: PieceTable
): tuple[height: int, nodeCount: int, totalBytes: int] =
  var nodeCount = 0
  var maxDepth = 0
  proc countNodes(node: PieceTreeNode, depth: int) =
    if node.isNil:
      return
    inc nodeCount
    if depth > maxDepth:
      maxDepth = depth
    countNodes(node.left, depth + 1)
    countNodes(node.right, depth + 1)

  countNodes(pt.root, 0)

  return (height: maxDepth, nodeCount: nodeCount, totalBytes: pt.cachedByteLen)

proc takeSnapshot*(pt: PieceTable): PieceTableSnapshot =
  ## O(1) snapshot: saves root pointer and buffer refs.
  ## Safe because buffers are append-only and tree is persistent (path-copying).
  PieceTableSnapshot(
    root: pt.root,
    buffers: pt.buffers,
    cachedLineCount: pt.cachedLineCount,
    cachedByteLen: pt.cachedByteLen,
  )

proc restoreSnapshot*(pt: PieceTable, snap: PieceTableSnapshot) =
  ## O(1) restore: replaces root and buffer refs.
  pt.root = snap.root
  pt.buffers = snap.buffers
  pt.cachedLineCount = snap.cachedLineCount
  pt.cachedByteLen = snap.cachedByteLen
