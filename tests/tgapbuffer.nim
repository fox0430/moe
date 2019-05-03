import unittest
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
