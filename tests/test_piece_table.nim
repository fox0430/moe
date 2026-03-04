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

import std/[unittest, strutils, random, importutils]

import ../src/moepkg/buffer_backends/piece_table {.all.}

privateAccess(PieceTreeNode)
privateAccess(TextPieceBuffer)
privateAccess(PieceTable)
privateAccess(PieceTableSnapshot)

proc verifyMetricsNode(node: PieceTreeNode): bool =
  ## Verify subtreeLength and subtreeLineFeedCount are consistent
  ## with children + self for every node in the subtree.
  if node.isNil:
    return true
  if not verifyMetricsNode(node.left):
    return false
  if not verifyMetricsNode(node.right):
    return false

  let ll = if node.left.isNil: 0 else: node.left.subtreeLength
  let rl = if node.right.isNil: 0 else: node.right.subtreeLength
  let expectedLen = ll + node.length + rl
  if node.subtreeLength != expectedLen:
    return false

  let llf = if node.left.isNil: 0 else: node.left.subtreeLineFeedCount
  let rlf = if node.right.isNil: 0 else: node.right.subtreeLineFeedCount
  let expectedLF = llf + node.lineFeedCount + rlf
  if node.subtreeLineFeedCount != expectedLF:
    return false

  true

proc verifyMetrics(pt: PieceTable): bool =
  verifyMetricsNode(pt.root)

proc blackHeight(node: PieceTreeNode): int =
  ## Returns the black-height of the subtree, or -1 if invalid.
  if node.isNil:
    return 1 # nil leaves are black
  let lh = blackHeight(node.left)
  let rh = blackHeight(node.right)
  if lh == -1 or rh == -1 or lh != rh:
    return -1
  if node.color == rbBlack:
    lh + 1
  else:
    lh

proc verifyRBProperties(pt: PieceTable): bool =
  ## Verify Red-Black Tree invariants:
  ## 1. Root is black (or nil)
  ## 2. Red nodes have only black children
  ## 3. All paths from root to leaves have the same black-height
  if pt.root.isNil:
    return true
  # Property 1: Root is black
  if pt.root.color != rbBlack:
    return false
  # Check properties 2 and 3 recursively
  proc checkNode(node: PieceTreeNode): bool =
    if node.isNil:
      return true
    # Property 2: Red node's children must be black
    if node.color == rbRed:
      if (not node.left.isNil and node.left.color == rbRed):
        return false
      if (not node.right.isNil and node.right.color == rbRed):
        return false
    checkNode(node.left) and checkNode(node.right)

  if not checkNode(pt.root):
    return false
  # Property 3: Uniform black-height
  blackHeight(pt.root) != -1

proc verifyInOrder(pt: PieceTable): bool =
  ## Verify that in-order traversal of tree nodes produces
  ## text matching $pt (including the trailing newline logic).
  var text = ""
  # Stack-based in-order traversal (no parent pointers needed)
  var stack: seq[PieceTreeNode] = @[]
  var cur = pt.root
  while cur != nil or stack.len > 0:
    while cur != nil:
      stack.add(cur)
      cur = cur.left
    cur = stack.pop()
    let buf = pt.buffers[cur.bufferIndex]
    let sOff = buf.bufferOffset(cur.start)
    let eOff = buf.bufferOffset(cur.endPos)
    text.add(buf.value[sOff ..< eOff])
    cur = cur.right
  # Match $pt trailing newline behavior
  if pt.cachedLineCount > 1 and text.len > 0 and text[^1] == '\n':
    text.add('\n')
  text == $pt

proc verifyAll(pt: PieceTable): bool =
  ## Convenience: verify all RB properties, metrics, and in-order consistency.
  verifyRBProperties(pt) and verifyMetrics(pt) and verifyInOrder(pt)

suite "PieceTable - Basic Operations":
  test "newPieceTable creates empty buffer":
    let pt = newPieceTable()
    check pt.len == 1
    check pt[0] == ""

  test "newPieceTable with text":
    let pt = newPieceTable("hello\nworld")
    check pt.len == 2
    check pt[0] == "hello"
    check pt[1] == "world"

  test "newPieceTable with trailing newline":
    let pt = newPieceTable("hello\nworld\n")
    check pt.len == 2
    check pt[0] == "hello"
    check pt[1] == "world"

  test "len returns line count":
    let pt = newPieceTable("line1\nline2\nline3")
    check pt.len == 3

  test "empty string creates single empty line":
    let pt = newPieceTable("")
    check pt.len == 1
    check pt[0] == ""

  test "single newline creates one empty line":
    let pt = newPieceTable("\n")
    check pt.len == 1
    check pt[0] == ""

  test "double newline creates two lines":
    let pt = newPieceTable("\n\n")
    check pt.len == 2
    check pt[0] == ""
    check pt[1] == ""

suite "PieceTable - Line Access":
  test "getLine returns correct line":
    let pt = newPieceTable("hello\nworld\nfoo")
    check pt.getLine(0) == "hello"
    check pt.getLine(1) == "world"
    check pt.getLine(2) == "foo"

  test "getLine with invalid index":
    let pt = newPieceTable("hello")
    check pt.getLine(-1) == ""
    check pt.getLine(1) == ""

  test "bracket operator":
    let pt = newPieceTable("abc\ndef")
    check pt[0] == "abc"
    check pt[1] == "def"

  test "bracket assignment":
    let pt = newPieceTable("abc\ndef")
    pt[0] = "xyz"
    check pt[0] == "xyz"
    check pt[1] == "def"

suite "PieceTable - Character Access":
  test "charAtLineCol basic":
    let pt = newPieceTable("hello\nworld")
    check pt.charAtLineCol(0, 0) == 'h'
    check pt.charAtLineCol(0, 4) == 'o'
    check pt.charAtLineCol(1, 0) == 'w'

  test "charAtLineCol at end of line returns newline":
    let pt = newPieceTable("hello\nworld")
    check pt.charAtLineCol(0, 5) == '\n'

  test "charAt linear index":
    let pt = newPieceTable("ab\ncd")
    check pt.charAt(0) == 'a'
    check pt.charAt(1) == 'b'
    check pt.charAt(2) == '\n'
    check pt.charAt(3) == 'c'
    check pt.charAt(4) == 'd'

suite "PieceTable - Line Insert":
  test "insertLine at beginning":
    let pt = newPieceTable("world")
    pt.insertLine(0, "hello")
    check pt.len == 2
    check pt[0] == "hello"
    check pt[1] == "world"

  test "insertLine at end":
    let pt = newPieceTable("hello")
    pt.insertLine(1, "world")
    check pt.len == 2
    check pt[0] == "hello"
    check pt[1] == "world"

  test "insertLine in middle":
    let pt = newPieceTable("hello\nworld")
    pt.insertLine(1, "middle")
    check pt.len == 3
    check pt[0] == "hello"
    check pt[1] == "middle"
    check pt[2] == "world"

suite "PieceTable - Line Delete":
  test "deleteLine first":
    let pt = newPieceTable("hello\nworld")
    pt.deleteLine(0)
    check pt.len == 1
    check pt[0] == "world"

  test "deleteLine last":
    let pt = newPieceTable("hello\nworld")
    pt.deleteLine(1)
    check pt.len == 1
    check pt[0] == "hello"

  test "deleteLine middle":
    let pt = newPieceTable("a\nb\nc")
    pt.deleteLine(1)
    check pt.len == 2
    check pt[0] == "a"
    check pt[1] == "c"

  test "deleteLine only line":
    let pt = newPieceTable("hello")
    pt.deleteLine(0)
    check pt.len == 0

suite "PieceTable - Insert Into Line":
  test "insertIntoLine at beginning":
    let pt = newPieceTable("world")
    pt.insertIntoLine(0, 0, "hello ")
    check pt[0] == "hello world"

  test "insertIntoLine at end":
    let pt = newPieceTable("hello")
    pt.insertIntoLine(0, 5, " world")
    check pt[0] == "hello world"

  test "insertIntoLine in middle":
    let pt = newPieceTable("hllo")
    pt.insertIntoLine(0, 1, "e")
    check pt[0] == "hello"

suite "PieceTable - Delete At Line Col":
  test "deleteAtLineCol single char":
    let pt = newPieceTable("hello")
    pt.deleteAtLineCol(0, 0, 1)
    check pt[0] == "ello"

  test "deleteAtLineCol multiple chars":
    let pt = newPieceTable("hello world")
    pt.deleteAtLineCol(0, 5, 6)
    check pt[0] == "hello"

  test "deleteAtLineCol cross line":
    let pt = newPieceTable("hello\nworld")
    pt.deleteAtLineCol(0, 3, 5)
    check pt.len == 1
    check pt[0] == "helrld"

suite "PieceTable - Linear Index Insert":
  test "insert text without newline":
    let pt = newPieceTable("hllo")
    pt.insert(1, "e")
    check pt[0] == "hello"

  test "insert text with newline":
    let pt = newPieceTable("helloworld")
    pt.insert(5, "\n")
    check pt.len == 2
    check pt[0] == "hello"
    check pt[1] == "world"

  test "insert char":
    let pt = newPieceTable("hllo")
    pt.insert(1, 'e')
    check pt[0] == "hello"

suite "PieceTable - Linear Index Delete":
  test "delete single char":
    let pt = newPieceTable("hello")
    pt.delete(0)
    check pt[0] == "ello"

  test "delete newline":
    let pt = newPieceTable("hello\nworld")
    pt.delete(5, 1)
    check pt.len == 1
    check pt[0] == "helloworld"

  test "delete multiple chars":
    let pt = newPieceTable("hello world")
    pt.delete(5, 6)
    check pt[0] == "hello"

suite "PieceTable - Linear Index":
  test "findLineStart":
    let pt = newPieceTable("hello\nworld\nfoo")
    check pt.findLineStart(0) == 0
    check pt.findLineStart(1) == 6
    check pt.findLineStart(2) == 12

  test "findLineEnd":
    let pt = newPieceTable("hello\nworld\nfoo")
    check pt.findLineEnd(0) == 4
    check pt.findLineEnd(1) == 10
    check pt.findLineEnd(2) == 14

  test "indexToLineCol":
    let pt = newPieceTable("hello\nworld")
    check pt.indexToLineCol(0) == (0, 0)
    check pt.indexToLineCol(4) == (0, 4)
    check pt.indexToLineCol(5) == (0, 5)
    check pt.indexToLineCol(6) == (1, 0)
    check pt.indexToLineCol(10) == (1, 4)

suite "PieceTable - Substring":
  test "substring within line":
    let pt = newPieceTable("hello world")
    check pt.substring(0, 5) == "hello"
    check pt.substring(6, 5) == "world"

  test "substring across lines":
    let pt = newPieceTable("hello\nworld")
    check pt.substring(3, 5) == "lo\nwo"

  test "slice operator":
    let pt = newPieceTable("hello world")
    check pt[0 .. 4] == "hello"
    check pt[6 .. 10] == "world"

suite "PieceTable - Conversion":
  test "toString basic":
    let pt = newPieceTable("hello\nworld")
    check $pt == "hello\nworld"

  test "toString with empty last line":
    let pt = newPieceTable("hello\n\n")
    check $pt == "hello\n\n"

  test "clear":
    let pt = newPieceTable("hello\nworld")
    pt.clear()
    check pt.len == 1
    check pt[0] == ""

  test "chars iterator":
    let pt = newPieceTable("ab\ncd")
    var s = ""
    for ch in pt.chars:
      s.add(ch)
    check s == "ab\ncd"

  test "lines iterator":
    let pt = newPieceTable("hello\nworld")
    var result: seq[string] = @[]
    for line in pt.lines:
      result.add(line)
    check result == @["hello", "world"]

suite "PieceTable - Replace Line":
  test "replaceLine":
    let pt = newPieceTable("hello\nworld")
    pt.replaceLine(0, "hi")
    check pt[0] == "hi"
    check pt[1] == "world"

  test "modifyLineContent":
    let pt = newPieceTable("hello\nworld")
    pt.modifyLineContent(
      0,
      proc(s: var string) =
        s = s.toUpperAscii(),
    )
    check pt[0] == "HELLO"
    check pt[1] == "world"

suite "PieceTable - Memory and Info":
  test "estimateMemoryUsage":
    let pt = newPieceTable("hello\nworld")
    check pt.estimateMemoryUsage() > 0

  test "getTableInfo":
    let pt = newPieceTable("hello\nworld")
    let info = pt.getTableInfo()
    check info.totalBytes > 0
    check info.nodeCount >= 1

suite "PieceTable - Subtree Metrics Consistency":
  test "metrics valid after many inserts":
    let pt = newPieceTable()
    for i in 0 ..< 20:
      pt.insert(pt.cachedByteLen, "line" & $i & "\n")
    check verifyMetrics(pt)
    check verifyRBProperties(pt)

  test "metrics valid after many deletes":
    var text = ""
    for i in 0 ..< 20:
      text.add("line" & $i & "\n")
    let pt = newPieceTable(text)
    for i in countdown(pt.len - 1, 1):
      pt.deleteLine(i)
    check verifyMetrics(pt)
    check verifyRBProperties(pt)

  test "metrics valid after interleaved insert and delete":
    let pt = newPieceTable("start")
    for i in 0 ..< 15:
      pt.insert(pt.cachedByteLen, "x" & $i)
      if pt.cachedByteLen > 5:
        pt.delete(0, 2)
    check verifyMetrics(pt)
    check verifyRBProperties(pt)

  test "metrics valid after node-splitting inserts":
    let pt = newPieceTable("abcdefghij")
    # Insert in the middle to force splits
    pt.insert(5, "X")
    pt.insert(3, "Y")
    pt.insert(8, "Z")
    check verifyMetrics(pt)
    check verifyRBProperties(pt)
    check $pt == "abcYdeXfZghij"

  test "metrics valid after 15 consecutive operations with rotations":
    let pt = newPieceTable()
    for i in 0 ..< 15:
      pt.insert(0, $chr(ord('a') + (i mod 26)))
    check verifyMetrics(pt)
    check verifyRBProperties(pt)
    check verifyInOrder(pt)

  test "cachedByteLen matches root subtreeLength":
    let pt = newPieceTable("hello\nworld\ntest")
    pt.insert(5, "!!!")
    pt.delete(0, 2)
    if not pt.root.isNil:
      check pt.cachedByteLen == pt.root.subtreeLength

  test "cachedLineCount matches root subtreeLineFeedCount + 1":
    let pt = newPieceTable("a\nb\nc\nd")
    pt.insertLine(2, "new")
    pt.deleteLine(0)
    if not pt.root.isNil:
      check pt.cachedLineCount == pt.root.subtreeLineFeedCount + 1

suite "PieceTable - Stress Tests":
  test "100 consecutive inserts maintain RB properties":
    let pt = newPieceTable()
    for i in 0 ..< 100:
      pt.insert(pt.cachedByteLen, "item" & $i & "\n")
    check verifyAll(pt)
    check pt.len == 101 # 100 newlines + final line

  test "50 inserts + 50 deletes maintain RB properties":
    let pt = newPieceTable()
    for i in 0 ..< 50:
      pt.insert(pt.cachedByteLen, "data" & $i & "\n")
    for i in countdown(49, 0):
      pt.deleteLine(i)
    check verifyRBProperties(pt)
    check verifyMetrics(pt)

  test "random position insert/delete with content verification":
    var rng = initRand(42)
    let pt = newPieceTable("seed")
    var expected = "seed"
    for i in 0 ..< 50:
      if expected.len > 0 and rng.rand(1) == 0:
        # Insert
        let pos = rng.rand(expected.len)
        let ch = $chr(ord('a') + (i mod 26))
        pt.insert(pos, ch)
        expected.insert(ch, pos)
      elif expected.len > 1:
        # Delete
        let pos = rng.rand(expected.len - 1)
        pt.delete(pos, 1)
        expected.delete(pos .. pos)
    check $pt == expected
    check verifyAll(pt)

  test "many nodes - getLine accuracy":
    let pt = newPieceTable("base")
    for i in 0 ..< 25:
      pt.insertLine(pt.len, "line" & $i)
    for i in 0 ..< pt.len:
      let line = pt.getLine(i)
      if i == 0:
        check line == "base"
      else:
        check line == "line" & $(i - 1)

  test "many nodes - substring accuracy":
    let pt = newPieceTable()
    for i in 0 ..< 20:
      pt.insert(pt.cachedByteLen, $chr(ord('A') + i))
    let full = $pt
    for i in 0 ..< full.len:
      for length in 1 .. min(5, full.len - i):
        check pt.substring(i, length) == full[i ..< i + length]

  test "many nodes - indexToLineCol accuracy":
    let pt = newPieceTable()
    for i in 0 ..< 10:
      pt.insert(pt.cachedByteLen, "ln" & $i & "\n")
    let full = $pt
    for idx in 0 ..< full.len:
      let (line, col) = pt.indexToLineCol(idx)
      let lineStart = pt.lineStartByteOffset(line)
      check lineStart + col == idx

suite "PieceTable - charLen":
  test "empty buffer returns 0":
    let pt = newPieceTable()
    check pt.charLen == 0

  test "charLen after insert":
    let pt = newPieceTable("hello")
    check pt.charLen == 5

  test "charLen with newlines":
    let pt = newPieceTable("a\nb\nc")
    check pt.charLen == 5 # a + \n + b + \n + c

  test "charLen tracks insert and delete":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    check pt.charLen == 11
    pt.delete(0, 6) # delete "hello "
    check pt.charLen == 5 # "world"

  test "charLen after clear":
    let pt = newPieceTable("hello\nworld")
    pt.clear()
    check pt.charLen == 0

suite "PieceTable - Line Byte Offsets":
  test "lineStartByteOffset after edits":
    let pt = newPieceTable("aaa\nbbb\nccc")
    pt.insert(0, "X") # "Xaaa\nbbb\nccc"
    check pt.lineStartByteOffset(0) == 0
    check pt.lineStartByteOffset(1) == 5 # after "Xaaa\n"
    check pt.lineStartByteOffset(2) == 9 # after "bbb\n"

  test "lineStartByteOffset with empty lines":
    let pt = newPieceTable("a\n\nb")
    check pt.lineStartByteOffset(0) == 0
    check pt.lineStartByteOffset(1) == 2
    check pt.lineStartByteOffset(2) == 3

  test "lineEndByteOffset for last line":
    let pt = newPieceTable("abc\ndef")
    check pt.lineEndByteOffset(1) == pt.cachedByteLen # last line

  test "lineEndByteOffset for non-last line":
    let pt = newPieceTable("abc\ndef\nghi")
    # lineEndByteOffset for non-last line = lineStartByteOffset(next) - 1
    check pt.lineEndByteOffset(0) == 3 # points to position of '\n'
    check pt.lineEndByteOffset(1) == 7

  test "lineStartByteOffset out of range":
    let pt = newPieceTable("hello")
    check pt.lineStartByteOffset(-1) == 0
    check pt.lineStartByteOffset(100) == pt.cachedByteLen

  test "lineEndByteOffset out of range":
    let pt = newPieceTable("hello")
    check pt.lineEndByteOffset(-1) == pt.cachedByteLen
    check pt.lineEndByteOffset(100) == pt.cachedByteLen

suite "PieceTable - indexToLineCol After Edits":
  test "indexToLineCol after insert":
    let pt = newPieceTable("ab\ncd")
    pt.insert(2, "X") # "abX\ncd"
    check pt.indexToLineCol(0) == (0, 0) # a
    check pt.indexToLineCol(1) == (0, 1) # b
    check pt.indexToLineCol(2) == (0, 2) # X
    check pt.indexToLineCol(3) == (0, 3) # \n
    check pt.indexToLineCol(4) == (1, 0) # c
    check pt.indexToLineCol(5) == (1, 1) # d

  test "indexToLineCol after delete":
    let pt = newPieceTable("hello\nworld")
    pt.delete(5, 1) # delete \n -> "helloworld"
    check pt.indexToLineCol(0) == (0, 0)
    check pt.indexToLineCol(5) == (0, 5)
    check pt.indexToLineCol(9) == (0, 9)

  test "indexToLineCol empty buffer":
    let pt = newPieceTable()
    check pt.indexToLineCol(0) == (0, 0)

  test "indexToLineCol negative index":
    let pt = newPieceTable("hello")
    check pt.indexToLineCol(-1) == (-1, -1)

  test "indexToLineCol beyond end":
    let pt = newPieceTable("hello")
    let result = pt.indexToLineCol(100)
    check result.line == 0
    check result.col == 5 # past end of "hello"

suite "PieceTable - Iterator Edge Cases":
  test "chars on empty buffer":
    let pt = newPieceTable()
    var s = ""
    for ch in pt.chars:
      s.add(ch)
    check s == ""

  test "lines on empty buffer":
    let pt = newPieceTable()
    var result: seq[string] = @[]
    for line in pt.lines:
      result.add(line)
    check result == @[""]

  test "lines on single line":
    let pt = newPieceTable("hello")
    var result: seq[string] = @[]
    for line in pt.lines:
      result.add(line)
    check result == @["hello"]

  test "lines with empty lines":
    let pt = newPieceTable("a\n\nb")
    var result: seq[string] = @[]
    for line in pt.lines:
      result.add(line)
    check result == @["a", "", "b"]

  test "chars and $ agree after edits":
    let pt = newPieceTable("hello\nworld")
    pt.insert(5, "!!!")
    pt.delete(0, 2)
    var fromChars = ""
    for ch in pt.chars:
      fromChars.add(ch)
    check fromChars == $pt

  test "lines and getLine agree after edits":
    let pt = newPieceTable("alpha\nbeta\ngamma")
    pt.insertLine(1, "new")
    pt.deleteLine(3)
    var fromIter: seq[string] = @[]
    for line in pt.lines:
      fromIter.add(line)
    for i in 0 ..< pt.len:
      check fromIter[i] == pt.getLine(i)

suite "PieceTable - Node Split Details":
  test "insert in middle splits node":
    let pt = newPieceTable("abcdef")
    let infoBefore = pt.getTableInfo()
    pt.insert(3, "X") # "abcXdef"
    let infoAfter = pt.getTableInfo()
    check infoAfter.nodeCount > infoBefore.nodeCount
    check $pt == "abcXdef"

  test "split preserves content":
    let pt = newPieceTable("0123456789")
    pt.insert(5, "A")
    check $pt == "01234A56789"
    check pt.charLen == 11

  test "multiple splits increase node count":
    let pt = newPieceTable("abcdefghijklmnop")
    let initial = pt.getTableInfo().nodeCount
    pt.insert(4, "W")
    pt.insert(9, "X")
    pt.insert(14, "Y")
    let final_info = pt.getTableInfo()
    check final_info.nodeCount > initial
    check verifyAll(pt)

  test "delete from middle of node creates two pieces":
    let pt = newPieceTable("abcdefgh")
    let before = pt.getTableInfo().nodeCount
    pt.delete(3, 2) # delete "de" -> "abcfgh"
    check $pt == "abcfgh"
    # Middle delete splits node into left + right parts
    check pt.getTableInfo().nodeCount >= before

  test "split nodes have correct line feed counts":
    let pt = newPieceTable("aa\nbb\ncc\ndd")
    pt.insert(6, "X") # insert into "cc" -> "aa\nbb\nXcc\ndd"
    check verifyMetrics(pt)
    check pt.len == 4
    check pt[2] == "Xcc"

suite "PieceTable - Boundary Conditions":
  test "insert at index 0":
    let pt = newPieceTable("hello")
    pt.insert(0, "X")
    check $pt == "Xhello"

  test "insert at cachedByteLen":
    let pt = newPieceTable("hello")
    pt.insert(pt.cachedByteLen, "X")
    check $pt == "helloX"

  test "insert at negative index is no-op":
    let pt = newPieceTable("hello")
    pt.insert(-1, "X")
    check $pt == "hello"

  test "delete at index 0":
    let pt = newPieceTable("hello")
    pt.delete(0, 1)
    check $pt == "ello"

  test "delete at last byte":
    let pt = newPieceTable("hello")
    pt.delete(4, 1)
    check $pt == "hell"

  test "delete count exceeding remaining":
    let pt = newPieceTable("hello")
    pt.delete(3, 100)
    check $pt == "hel"

  test "deleteLine then insertLine on empty":
    let pt = newPieceTable("hello")
    pt.deleteLine(0)
    check pt.len == 0
    pt.insertLine(0, "world")
    check pt.len == 1
    check pt[0] == "world"

  test "bracket assign empty string":
    let pt = newPieceTable("hello\nworld")
    pt[0] = ""
    check pt[0] == ""
    check pt[1] == "world"

  test "bracket assign string with newline":
    let pt = newPieceTable("hello\nworld")
    pt[0] = "a\nb"
    # After replacing line 0 with "a\nb", we get 3 lines
    check pt.len == 3
    check pt[0] == "a"
    check pt[1] == "b"
    check pt[2] == "world"

  test "findLineStart out of range returns -1":
    let pt = newPieceTable("hello")
    check pt.findLineStart(-1) == -1
    check pt.findLineStart(1) == -1

  test "findLineEnd out of range returns -1":
    let pt = newPieceTable("hello")
    check pt.findLineEnd(-1) == -1
    check pt.findLineEnd(1) == -1

  test "delete at out of range is no-op":
    let pt = newPieceTable("hello")
    pt.delete(-1, 1)
    check $pt == "hello"
    pt.delete(10, 1)
    check $pt == "hello"

  test "insert empty string is no-op":
    let pt = newPieceTable("hello")
    pt.insert(2, "")
    check $pt == "hello"
    check pt.getTableInfo().nodeCount == 1

suite "PieceTable - Coalescing":
  test "consecutive appends coalesce into single node":
    let pt = newPieceTable("base")
    pt.insert(4, "a")
    pt.insert(5, "b")
    pt.insert(6, "c")
    check $pt == "baseabc"
    check pt.getTableInfo().nodeCount == 2 # original + coalesced add
    check verifyAll(pt)

  test "different buffer pieces don't coalesce":
    let pt = newPieceTable("hello")
    pt.insert(5, "!")
    check $pt == "hello!"
    check pt.getTableInfo().nodeCount == 2
    check verifyAll(pt)

  test "non-adjacent add buffer inserts don't coalesce with unrelated nodes":
    let pt = newPieceTable("abcd")
    pt.insert(0, "X")
    pt.insert(6, "Y")
    check $pt == "XabcdY"
    check pt.getTableInfo().nodeCount == 3 # X + abcd + Y
    check verifyAll(pt)

  test "delete allows recoalescing of split pieces":
    let pt = newPieceTable("abcdef")
    pt.insert(3, "X") # splits: [abc][X][def]
    let beforeDelete = pt.getTableInfo().nodeCount
    pt.delete(3, 1) # delete X: [abc][def] -> coalesce to [abcdef]
    let afterDelete = pt.getTableInfo().nodeCount
    check $pt == "abcdef"
    check afterDelete < beforeDelete
    check afterDelete == 1
    check verifyAll(pt)

  test "consecutive typing at cursor coalesces":
    let pt = newPieceTable()
    for i in 0 ..< 10:
      pt.insert(i, $chr(ord('a') + i))
    check $pt == "abcdefghij"
    check pt.getTableInfo().nodeCount == 1 # all coalesced into one
    check verifyAll(pt)

  test "coalescing preserves line feed count":
    let pt = newPieceTable("abc")
    pt.insert(3, "\n")
    pt.insert(4, "d")
    pt.insert(5, "\n")
    pt.insert(6, "e")
    # All consecutive add-buffer appends coalesce into one node
    check $pt == "abc\nd\ne"
    check pt.len == 3
    check pt.getTableInfo().nodeCount == 2 # original + coalesced add
    check pt[1] == "d"
    check pt[2] == "e"
    check verifyAll(pt)

  test "deletion at offset 0 coalesces boundary":
    # Two add-buffer pieces separated by an original piece at the start
    let pt = newPieceTable("X")
    pt.insert(0, "a") # [a(biAdd)][X(biOrig)]
    pt.insert(2, "b") # [a(biAdd)][X(biOrig)][b(biAdd)]
    pt.delete(1, 1) # delete X at pos 1: [a][b] -> coalesce
    check $pt == "ab"
    check pt.getTableInfo().nodeCount == 1
    check verifyAll(pt)

  test "reverse typing does not coalesce":
    let pt = newPieceTable("base")
    pt.insert(0, "c")
    pt.insert(0, "b")
    pt.insert(0, "a")
    # Each prepend is non-adjacent in the add buffer
    check $pt == "abcbase"
    check pt.getTableInfo().nodeCount == 4 # a + b + c + base
    check verifyAll(pt)

  test "random operations with coalescing maintain correctness":
    var rng = initRand(123)
    let pt = newPieceTable("line0\nline1\nline2")
    var expected = "line0\nline1\nline2"
    for i in 0 ..< 80:
      let op = rng.rand(2)
      if op == 0 and expected.len < 200:
        let pos = rng.rand(expected.len)
        let text =
          if rng.rand(3) == 0:
            "\n"
          else:
            $chr(ord('a') + (i mod 26))
        pt.insert(pos, text)
        expected.insert(text, pos)
      elif op == 1 and expected.len > 1:
        let pos = rng.rand(expected.len - 1)
        pt.delete(pos, 1)
        expected.delete(pos .. pos)
    check $pt == expected
    check verifyAll(pt)

suite "PieceTable - Compaction":
  test "flatten preserves text":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.delete(0, 2)
    let textBefore = $pt
    pt.flatten()
    check $pt == textBefore
    check verifyAll(pt)

  test "flatten results in single node with empty add buffer":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.flatten()
    check pt.buffers[biAdd].value == ""
    check pt.getTableInfo().nodeCount == 1

  test "flatten on empty table":
    let pt = newPieceTable()
    pt.flatten()
    check pt.len == 1
    check pt[0] == ""
    check pt.cachedByteLen == 0
    check verifyAll(pt)

  test "flatten with only add-buffer content":
    let pt = newPieceTable()
    pt.insert(0, "hello\nworld")
    pt.flatten()
    check $pt == "hello\nworld"
    check pt.len == 2
    check pt.buffers[biAdd].value == ""
    check pt.buffers[biOriginal].value == "hello\nworld"
    check pt.getTableInfo().nodeCount == 1
    check verifyAll(pt)

  test "flatten multi-line preserves line count":
    let pt = newPieceTable("aa\nbb\ncc")
    pt.insert(2, "X")
    pt.flatten()
    check pt.len == 3
    check pt[0] == "aaX"
    check pt[1] == "bb"
    check pt[2] == "cc"
    check verifyAll(pt)

  test "editing after flatten":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.flatten()
    pt.insert(11, "!")
    pt.insertLine(1, "second")
    check pt[0] == "hello world!"
    check pt[1] == "second"
    check verifyAll(pt)

  test "flatten is idempotent":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.flatten()
    let text1 = $pt
    pt.flatten()
    check $pt == text1
    check verifyAll(pt)

  test "wasteRatio accuracy":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.delete(0, 5)
    let ratio = pt.wasteRatio()
    # Total: 5 + 6 = 11, referenced: 6. Waste = 5/11 ≈ 0.4545
    check ratio > 0.4 and ratio < 0.5

  test "wasteRatio zero for no edits":
    let pt = newPieceTable("hello")
    check pt.wasteRatio() == 0.0

  test "wasteRatio zero for empty table":
    let pt = newPieceTable()
    check pt.wasteRatio() == 0.0

  test "wasteRatio zero after flatten":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.delete(0, 5)
    pt.flatten()
    check pt.wasteRatio() == 0.0

  test "maybeCompact triggers above threshold":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.delete(0, 5)
    pt.maybeCompact(0.3) # 0.45 > 0.3, triggers
    check pt.getTableInfo().nodeCount == 1
    check pt.buffers[biAdd].value == ""
    check verifyAll(pt)

  test "maybeCompact does not trigger below threshold":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.delete(0, 5)
    let nodesBefore = pt.getTableInfo().nodeCount
    pt.maybeCompact(0.5) # 0.45 < 0.5, does not trigger
    check pt.getTableInfo().nodeCount == nodesBefore

  test "maybeCompact with default threshold":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    pt.delete(0, 5)
    # wasteRatio ≈ 0.45 < default 0.5, should not trigger
    let nodesBefore = pt.getTableInfo().nodeCount
    pt.maybeCompact()
    check pt.getTableInfo().nodeCount == nodesBefore

suite "PieceTable - lineByteRange":
  test "matches lineStartByteOffset and lineEndByteOffset":
    let pt = newPieceTable("hello\nworld\nfoo\nbar")
    for i in 0 ..< pt.len:
      let (s, e) = pt.lineByteRange(i)
      check s == pt.lineStartByteOffset(i)
      check e == pt.lineEndByteOffset(i)

  test "matches after edits":
    let pt = newPieceTable("hello\nworld\nfoo")
    pt.insert(0, "X")
    pt.insertLine(1, "new")
    for i in 0 ..< pt.len:
      let (s, e) = pt.lineByteRange(i)
      check s == pt.lineStartByteOffset(i)
      check e == pt.lineEndByteOffset(i)

  test "out of range":
    let pt = newPieceTable("hello")
    check pt.lineByteRange(-1) == (pt.cachedByteLen, pt.cachedByteLen)
    check pt.lineByteRange(1) == (pt.cachedByteLen, pt.cachedByteLen)

  test "single line buffer":
    let pt = newPieceTable("hello")
    let (s, e) = pt.lineByteRange(0)
    check s == 0
    check e == pt.cachedByteLen

  test "fast path - both lines in same original node":
    # Single node with multiple newlines: lineByteRange for middle lines
    # should find both start and end within the same node (D1 path)
    let pt = newPieceTable("aaa\nbbb\nccc\nddd")
    for i in 0 ..< pt.len:
      let (s, e) = pt.lineByteRange(i)
      check s == pt.lineStartByteOffset(i)
      check e == pt.lineEndByteOffset(i)
    # Verify specific values for line 1 (middle of single node)
    check pt.lineByteRange(1) == (4, 7)
    check pt.lineByteRange(2) == (8, 11)

  test "with empty lines":
    let pt = newPieceTable("a\n\n\nb")
    for i in 0 ..< pt.len:
      let (s, e) = pt.lineByteRange(i)
      check s == pt.lineStartByteOffset(i)
      check e == pt.lineEndByteOffset(i)
    # Empty line 1: start == end
    let (s1, e1) = pt.lineByteRange(1)
    check e1 - s1 == 0

suite "PieceTable - Optimized Lines Iterator":
  test "lines matches getLine after complex edits":
    let pt = newPieceTable("alpha\nbeta\ngamma\ndelta")
    pt.insertLine(2, "inserted")
    pt.deleteLine(0)
    pt.insert(0, "X")
    pt[1] = "modified"
    var fromIter: seq[string] = @[]
    for line in pt.lines:
      fromIter.add(line)
    check fromIter.len == pt.len
    for i in 0 ..< pt.len:
      check fromIter[i] == pt.getLine(i)

  test "lines on zero-line state yields nothing":
    let pt = newPieceTable("hello")
    pt.deleteLine(0) # cachedLineCount becomes 0
    var count = 0
    for line in pt.lines:
      inc count
    check count == 0

  test "lines with line spanning 3+ nodes":
    # Create a single line whose content is split across multiple nodes
    let pt = newPieceTable("abcdef")
    pt.insert(2, "X") # [ab][X][cdef] - 3 nodes
    pt.insert(5, "Y") # [ab][X][cd][Y][ef] - 5 nodes
    # All on one line, iterator must accumulate across nodes
    var fromIter: seq[string] = @[]
    for line in pt.lines:
      fromIter.add(line)
    check fromIter == @["abXcdYef"]
    check fromIter[0] == pt.getLine(0)

  test "lines after flatten":
    let pt = newPieceTable("hello\nworld\nfoo")
    pt.insert(5, "!")
    pt.flatten()
    var fromIter: seq[string] = @[]
    for line in pt.lines:
      fromIter.add(line)
    check fromIter == @["hello!", "world", "foo"]

  test "lines with trailing newline added by edit":
    let pt = newPieceTable("abc\ndef")
    pt.insert(pt.cachedByteLen, "\n")
    pt.insert(pt.cachedByteLen, "ghi")
    # "abc\ndef\nghi" - 3 lines
    var fromIter: seq[string] = @[]
    for line in pt.lines:
      fromIter.add(line)
    check fromIter.len == pt.len
    for i in 0 ..< pt.len:
      check fromIter[i] == pt.getLine(i)

suite "PieceTable - Persistence / Snapshots":
  test "snapshot + edit + restore recovers text":
    let pt = newPieceTable("hello\nworld")
    let snap = pt.takeSnapshot()
    pt.insert(5, "!!!")
    check $pt == "hello!!!\nworld"
    pt.restoreSnapshot(snap)
    check $pt == "hello\nworld"
    check pt.len == 2

  test "multiple snapshots with correct restore":
    let pt = newPieceTable("base")
    let snap0 = pt.takeSnapshot()
    pt.insert(4, "A")
    let snap1 = pt.takeSnapshot()
    pt.insert(5, "B")
    let snap2 = pt.takeSnapshot()
    check $pt == "baseAB"
    pt.restoreSnapshot(snap1)
    check $pt == "baseA"
    pt.restoreSnapshot(snap0)
    check $pt == "base"
    pt.restoreSnapshot(snap2)
    check $pt == "baseAB"

  test "editing after restore works":
    let pt = newPieceTable("abc")
    let snap = pt.takeSnapshot()
    pt.insert(3, "DEF")
    pt.restoreSnapshot(snap)
    pt.insert(1, "X")
    check $pt == "aXbc"
    check verifyAll(pt)

  test "snapshot + flatten + restore (buffer ref independence)":
    let pt = newPieceTable("hello")
    pt.insert(5, " world")
    let snap = pt.takeSnapshot()
    pt.flatten()
    check $pt == "hello world"
    pt.restoreSnapshot(snap)
    check $pt == "hello world"
    check verifyAll(pt)

  test "snapshot + deleteLine + restore":
    let pt = newPieceTable("line0\nline1\nline2")
    let snap = pt.takeSnapshot()
    pt.deleteLine(1)
    check pt.len == 2
    check pt[0] == "line0"
    check pt[1] == "line2"
    pt.restoreSnapshot(snap)
    check pt.len == 3
    check pt[1] == "line1"
    check verifyAll(pt)

  test "stress: 50 snapshots, reverse restore":
    let pt = newPieceTable("start")
    var snaps: seq[PieceTableSnapshot] = @[]
    var texts: seq[string] = @[]
    for i in 0 ..< 50:
      snaps.add(pt.takeSnapshot())
      texts.add($pt)
      pt.insert(pt.cachedByteLen, $chr(ord('a') + (i mod 26)))
    # Restore in reverse order
    for i in countdown(49, 0):
      pt.restoreSnapshot(snaps[i])
      check $pt == texts[i]
      check verifyAll(pt)

  test "snapshot preserves cachedLineCount and cachedByteLen":
    let pt = newPieceTable("a\nb\nc")
    let snap = pt.takeSnapshot()
    pt.deleteLine(0)
    check pt.len == 2
    pt.restoreSnapshot(snap)
    check pt.len == 3
    check pt.charLen == 5

suite "PieceTable - Persistent RB Properties":
  test "continuous inserts maintain RB properties":
    let pt = newPieceTable()
    for i in 0 ..< 30:
      pt.insert(pt.cachedByteLen, "item" & $i & "\n")
      check verifyAll(pt)

  test "continuous deletes maintain RB properties":
    var text = ""
    for i in 0 ..< 20:
      text.add("line" & $i & "\n")
    let pt = newPieceTable(text)
    for i in countdown(pt.len - 1, 1):
      pt.deleteLine(i)
      check verifyAll(pt)

  test "snapshot + edit + both trees valid":
    let pt = newPieceTable("hello\nworld")
    let snap = pt.takeSnapshot()
    pt.insert(5, "!!!")
    pt.delete(0, 2)
    check verifyAll(pt)
    # Restore and verify old tree still valid
    pt.restoreSnapshot(snap)
    check verifyAll(pt)

suite "PieceTable - Multi-Node Deletion":
  test "delete spanning multiple nodes":
    let pt = newPieceTable("abcdef")
    pt.insert(2, "X") # [ab][X][cdef] — 3 nodes
    pt.insert(5, "Y") # [ab][X][cd][Y][ef] — 5 nodes
    pt.delete(1, 6) # delete "bXcdYe" spanning 4+ nodes
    check $pt == "af"
    check verifyAll(pt)

  test "delete spanning all nodes":
    let pt = newPieceTable("abc")
    pt.insert(1, "X") # [a][X][bc]
    pt.insert(4, "Y") # [a][X][bc][Y]
    pt.delete(0, pt.cachedByteLen)
    check pt.charLen == 0
    check verifyAll(pt)

  test "delete spanning nodes with newlines":
    let pt = newPieceTable("aa\nbb")
    pt.insert(3, "X\nY") # "aa\nX\nYbb" — 3 lines: aa / X / Ybb
    check pt.len == 3
    pt.delete(1, 6) # delete "a\nX\nYb" → "ab"
    check $pt == "ab"
    check pt.len == 1
    check verifyAll(pt)

  test "large multi-node delete":
    let pt = newPieceTable("base")
    # Create many nodes by inserting at different positions
    for i in 0 ..< 10:
      pt.insert(i * 2, $chr(ord('A') + i))
    let before = $pt
    let info = pt.getTableInfo()
    check info.nodeCount > 5
    # Delete a large range spanning many nodes
    let mid = before.len div 4
    let delLen = before.len div 2
    let expected = before[0 ..< mid] & before[mid + delLen ..< before.len]
    pt.delete(mid, delLen)
    check $pt == expected
    check verifyAll(pt)

suite "PieceTable - Multi-Newline Insert":
  test "insert text with multiple newlines":
    let pt = newPieceTable("start")
    pt.insert(5, "\nline2\nline3\nline4")
    check pt.len == 4
    check pt[0] == "start"
    check pt[1] == "line2"
    check pt[2] == "line3"
    check pt[3] == "line4"
    check verifyAll(pt)

  test "insert block of empty lines":
    let pt = newPieceTable("ab")
    pt.insert(1, "\n\n\n")
    check pt.len == 4
    check pt[0] == "a"
    check pt[1] == ""
    check pt[2] == ""
    check pt[3] == "b"
    check verifyAll(pt)

  test "insert multi-newline at beginning":
    let pt = newPieceTable("hello")
    pt.insert(0, "a\nb\nc\n")
    check pt.len == 4
    check pt[0] == "a"
    check pt[1] == "b"
    check pt[2] == "c"
    check pt[3] == "hello"
    check verifyAll(pt)

suite "PieceTable - Snapshot Edge Cases":
  test "snapshot of empty table":
    let pt = newPieceTable()
    let snap = pt.takeSnapshot()
    pt.insert(0, "hello\nworld")
    check pt.len == 2
    pt.restoreSnapshot(snap)
    check pt.len == 1
    check pt.charLen == 0
    check pt[0] == ""
    check verifyAll(pt)

  test "snapshot → delete all content → restore":
    let pt = newPieceTable("hello\nworld\nfoo")
    let snap = pt.takeSnapshot()
    pt.delete(0, pt.cachedByteLen)
    check pt.charLen == 0
    pt.restoreSnapshot(snap)
    check $pt == "hello\nworld\nfoo"
    check pt.len == 3
    check verifyAll(pt)

  test "snapshot → clear → restore":
    let pt = newPieceTable("abc\ndef")
    let snap = pt.takeSnapshot()
    pt.clear()
    check pt.len == 1
    check pt.charLen == 0
    pt.restoreSnapshot(snap)
    check $pt == "abc\ndef"
    check pt.len == 2
    check verifyAll(pt)

  test "snapshot + bracket assign + restore":
    let pt = newPieceTable("aaa\nbbb\nccc")
    let snap = pt.takeSnapshot()
    pt[1] = "XXX"
    check pt[1] == "XXX"
    pt.restoreSnapshot(snap)
    check pt[1] == "bbb"
    check verifyAll(pt)

  test "mixed snapshot chain with insert/delete/replace":
    let pt = newPieceTable("base\ntext")
    let s0 = pt.takeSnapshot()
    pt.insertLine(1, "new")
    let s1 = pt.takeSnapshot()
    pt.deleteLine(0)
    pt[0] = "modified"
    let s2 = pt.takeSnapshot()
    # Restore oldest, edit, then restore newer snapshots
    pt.restoreSnapshot(s0)
    check $pt == "base\ntext"
    pt.insert(0, "X")
    check verifyAll(pt)
    pt.restoreSnapshot(s2)
    check pt[0] == "modified"
    check verifyAll(pt)
    pt.restoreSnapshot(s1)
    check pt[0] == "base"
    check pt[1] == "new"
    check pt[2] == "text"
    check verifyAll(pt)

  test "snapshot after clear then edit":
    let pt = newPieceTable("hello")
    pt.clear()
    let snap = pt.takeSnapshot()
    pt.insert(0, "world")
    check $pt == "world"
    pt.restoreSnapshot(snap)
    check pt.charLen == 0
    check pt.len == 1
    check verifyAll(pt)

  test "double restore to same snapshot":
    let pt = newPieceTable("abc")
    let snap = pt.takeSnapshot()
    pt.insert(3, "DEF")
    pt.restoreSnapshot(snap)
    check $pt == "abc"
    pt.insert(0, "X")
    pt.restoreSnapshot(snap)
    check $pt == "abc"
    check verifyAll(pt)

  test "snapshot + deleteLine all + restore":
    let pt = newPieceTable("a\nb\nc")
    let snap = pt.takeSnapshot()
    pt.deleteLine(2)
    pt.deleteLine(1)
    pt.deleteLine(0)
    check pt.len == 0
    pt.restoreSnapshot(snap)
    check pt.len == 3
    check pt[0] == "a"
    check pt[1] == "b"
    check pt[2] == "c"
    check verifyAll(pt)

suite "PieceTable - Path-Copying Isolation":
  test "snapshot root is not mutated by edits":
    let pt = newPieceTable("abcdefghij")
    let snap = pt.takeSnapshot()
    let origRoot = snap.root
    let origText = $pt
    # Many edits that trigger path-copying on different paths
    pt.insert(5, "XXXXX")
    pt.delete(0, 3)
    pt.insert(pt.cachedByteLen, "YYYYY")
    pt.delete(2, 4)
    # Restore and verify original root pointer is unchanged
    pt.restoreSnapshot(snap)
    check pt.root == origRoot
    check $pt == origText
    check verifyAll(pt)

  test "independent edits after snapshot don't interfere":
    let pt = newPieceTable("hello\nworld")
    let snap = pt.takeSnapshot()
    # Perform many operations creating new paths
    for i in 0 ..< 20:
      pt.insert(pt.cachedByteLen, $chr(ord('a') + (i mod 26)))
    for i in countdown(9, 0):
      pt.delete(i, 1)
    check verifyAll(pt)
    # Restore and verify snapshot is intact
    pt.restoreSnapshot(snap)
    check $pt == "hello\nworld"
    check verifyAll(pt)

suite "PieceTable - Successor Coalesce":
  test "coalesce with successor in mid-tree":
    # Create: [ab(add)] [M(orig)] [cd(add)]
    # Delete M → [ab(add)] [cd(add)]
    # If ab.endPos == cd.start (adjacent in add buffer), they coalesce
    let pt = newPieceTable("M")
    pt.insert(0, "ab") # add buffer: "ab"
    pt.insert(3, "cd") # add buffer: "abcd"
    # Now: [ab(add,0..2)] [M(orig)] [cd(add,2..4)]
    check pt.getTableInfo().nodeCount == 3
    pt.delete(2, 1) # delete M
    check $pt == "abcd"
    # ab and cd are adjacent in add buffer → should coalesce
    check pt.getTableInfo().nodeCount == 1
    check verifyAll(pt)

  test "coalesce with successor when predecessor not eligible":
    let pt = newPieceTable("XY")
    pt.insert(1, "ab") # add buffer: "ab"
    pt.insert(4, "cd") # add buffer: "abcd"
    # [X(orig)] [ab(add,0..2)] [Y(orig)] [cd(add,2..4)]
    pt.delete(3, 1) # delete Y
    # [X(orig)] [ab(add)] [cd(add)] → ab+cd coalesce
    check $pt == "Xabcd"
    check verifyAll(pt)

suite "PieceTable - Tree Height Bounds":
  test "height stays logarithmic after many inserts":
    let pt = newPieceTable()
    for i in 0 ..< 500:
      pt.insert(pt.cachedByteLen, "item" & $i & "\n")
    let info = pt.getTableInfo()
    # RB tree: height ≤ 2·log₂(n+1); for coalesced tree, fewer nodes
    # but height should still be bounded
    check info.height <= 40
    check verifyAll(pt)

  test "height stays logarithmic after inserts at random positions":
    var rng = initRand(999)
    let pt = newPieceTable("seed")
    for i in 0 ..< 200:
      let pos = rng.rand(pt.cachedByteLen)
      pt.insert(pos, $chr(ord('a') + (i mod 26)))
    let info = pt.getTableInfo()
    # Random inserts create more nodes (less coalescing)
    check info.height <= 40
    check verifyAll(pt)

  test "height stays bounded after mixed insert/delete":
    var rng = initRand(7777)
    let pt = newPieceTable("initial content here")
    for i in 0 ..< 300:
      if pt.cachedByteLen < 5 or rng.rand(2) != 0:
        let pos = rng.rand(pt.cachedByteLen)
        pt.insert(pos, $chr(ord('A') + (i mod 26)))
      else:
        let pos = rng.rand(pt.cachedByteLen - 1)
        pt.delete(pos, 1)
    let info = pt.getTableInfo()
    check info.height <= 40
    check verifyAll(pt)
