import std/unittest
import moepkg/gapbuffer

test "empty":
  let buffer = initGapBuffer[string]()

  check(buffer.empty)

test "insert":
  var buffer = initGapBuffer[string]()
  buffer.insert("0", 0)
  buffer.insert("1", 0)
  buffer.insert("2", 2)

  check(buffer.len == 3)
  check(buffer[0] == "1")
  check(buffer[1] == "0")
  check(buffer[2] == "2")
  check($buffer == "1\n0\n2\n")

test "delete(basic)":
  var buffer = initGapBuffer[string]()
  buffer.add("0")
  buffer.add("1")
  buffer.add("2")
  buffer.add("3")
  buffer.add("4")
  buffer.add("5")
  buffer.add("6")
  buffer.add("7")
  buffer.add("8")
  buffer.add("99")

  buffer.delete(0, 1)
  check(buffer.len == 8)
  check(buffer[0] == "2")

  buffer.delete(2, 4)
  check(buffer.len == 5)
  check(buffer[0] == "2")
  check(buffer[1] == "3")
  check(buffer[2] == "7")
  check(buffer[3] == "8")
  check(buffer[4] == "99")

test "delete(all)":
  var buffer = initGapBuffer[string]()
  buffer.add("1")
  buffer.add("2")
  buffer.add("3")
  buffer.add("4")
  buffer.add("5")
  buffer.delete(0, 4)

  check(buffer.empty)
  check(buffer.len == 0)

test "next":
  var buffer = initGapBuffer[string]()
  buffer.add("2")
  buffer.add("3")
  buffer.add("7")
  buffer.add("8")
  buffer.add("99")

  check(buffer.next(3, 0) == (4, 0))
  check(buffer.next(4, 0) == (4, 1))
  check(buffer.next(4, 1) == (4, 1))

test "prev":
  var buffer = initGapBuffer[string]()
  buffer.add("2")
  buffer.add("3")
  buffer.add("7")
  buffer.add("8")
  buffer.add("99")

  check(buffer.prev(1, 0) == (0, 0))
  check(buffer.prev(0, 0) == (0, 0))

proc insertAndLockSuit(buffer: var GapBuffer[string], s: string, i: Natural) =
  buffer.insert(s, i)
  buffer.beginNewSuitIfNeeded

proc deleteAndLockSuit(buffer: var GapBuffer[string], i: Natural) =
  buffer.delete(i)
  buffer.beginNewSuitIfNeeded

proc assignAndLockSuit(buffer: var GapBuffer[string], s: string, i: Natural) =
  buffer[i] = s
  buffer.beginNewSuitIfNeeded

test "undo/redo(only construction)":
  var buffer = initGapBuffer[string]()
  check(not buffer.canUndo)
  check(not buffer.canRedo)
  check($buffer == "")

test "undo/redo(insert)":
  var buffer = initGapBuffer[string]()
  buffer.insertAndLockSuit("0", 0) # ["0"]
  buffer.insertAndLockSuit("1", 0) # ["1", "0"]
  buffer.insertAndLockSuit("2", 1) # ["1", "2", "0"]
  buffer.insertAndLockSuit("3", 3) # ["1", "2", "0", "3"]

  check(not buffer.canRedo)

  check($buffer == "1\n2\n0\n3\n")

  buffer.undo # ["1", "2", "0"]
  check($buffer == "1\n2\n0\n")

  buffer.undo # ["1", "0"]
  check($buffer == "1\n0\n")

  buffer.undo # ["0"]
  check($buffer == "0\n")

  buffer.undo # []
  check($buffer == "")

  check(not buffer.canUndo)

  buffer.redo # ["0"]
  check($buffer == "0\n")

  buffer.redo # ["1", "0"]
  check($buffer == "1\n0\n")

  buffer.redo # ["1", "2", "0"]
  check($buffer == "1\n2\n0\n")

  buffer.redo # ["1", "2", "0", "3"]
  check($buffer == "1\n2\n0\n3\n")

  check(not buffer.canRedo)

test "undo/redo(delete)":
  var buffer = initGapBuffer[string]()
  buffer.insertAndLockSuit("0", 0) # ["0"]
  buffer.deleteAndLockSuit(0) # []

  check(not buffer.canRedo)

  check($buffer == "")

  buffer.undo # ["0"]
  check($buffer == "0\n")

  buffer.undo # []
  check($buffer == "")

  check(not buffer.canUndo)

  buffer.redo # ["0"]
  check($buffer == "0\n")

  buffer.redo # []
  check($buffer == "")

  check(not buffer.canRedo)

test "undo/redo(assign)":
  var buffer = initGapBuffer[string]()
  buffer.insertAndLockSuit("0", 0) # ["0"]
  buffer.assignAndLockSuit("1", 0) # ["1"]

  check(not buffer.canRedo)

  check($buffer == "1\n")

  buffer.undo # ["0"]
  check($buffer == "0\n")

  buffer.undo # []
  check($buffer == "")

  check(not buffer.canUndo)

  buffer.redo # ["0"]
  check($buffer == "0\n")

  buffer.redo # ["1"]
  check($buffer == "1\n")

  check(not buffer.canRedo)

test "calcIndexInEntireBuffer (without containing newlines)":
  let buffer = initGapBuffer[string](@["0", "12", "345"])
  check buffer.calcIndexInEntireBuffer(0, 0, false) == 0
  check buffer.calcIndexInEntireBuffer(1, 0, false) == 1
  check buffer.calcIndexInEntireBuffer(1, 1, false) == 2
  check buffer.calcIndexInEntireBuffer(2, 0, false) == 3
  check buffer.calcIndexInEntireBuffer(2, 1, false) == 4
  check buffer.calcIndexInEntireBuffer(2, 2, false) == 5

test "calcIndexInEntireBuffer (with containing newlines)":
  let buffer = initGapBuffer[string](@["0", "12", "345"])
  check buffer.calcIndexInEntireBuffer(0, 0, true) == 0
  check buffer.calcIndexInEntireBuffer(1, 0, true) == 2
  check buffer.calcIndexInEntireBuffer(1, 1, true) == 3
  check buffer.calcIndexInEntireBuffer(2, 0, true) == 5
  check buffer.calcIndexInEntireBuffer(2, 1, true) == 6
  check buffer.calcIndexInEntireBuffer(2, 2, true) == 7
