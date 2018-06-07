import moepkg/gapbuffer

var buffer = initGapBuffer[string]()

doAssert(buffer.empty)

buffer.insert("0", 0)
buffer.insert("1", 0)
buffer.insert("2", 2)

doAssert(buffer[0] == "1")
doAssert(buffer[1] == "0")
doAssert(buffer[2] == "2")

buffer[0] = "0"
buffer[1] = "1"
buffer[2] = "2"
buffer.add("3")
buffer.add("4")
buffer.add("5")
buffer.add("6")
buffer.add("7")
buffer.add("8")
buffer.add("99")

buffer.delete(0, 2)
doAssert(buffer.len == 8)
doAssert(buffer[0] == "2")

buffer.delete(2, 5)
doAssert(buffer.len == 5)
doAssert(buffer[0] == "2")
doAssert(buffer[1] == "3")
doAssert(buffer[2] == "7")
doAssert(buffer[3] == "8")
doAssert(buffer[4] == "99")

doAssert(buffer.next(3, 0) == (4, 0))
doAssert(buffer.next(4, 0) == (4, 1))
doAssert(buffer.next(4, 1) == (4, 1))

doAssert(buffer.prev(1, 0) == (0, 0))
doAssert(buffer.prev(0, 0) == (0, 0))

buffer.delete(0, 5)
doAssert(buffer.empty)
doAssert(buffer.len == 0)
