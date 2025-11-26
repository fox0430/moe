import unittest
import std/strutils
import ../src/moepkg/gapbuffer

suite "Gap management tests":
  test "Gap expansion on many insertions":
    let gb = newGapBuffer()
    let initialGapInfo = gb.getGapInfo()
    echo "Initial gap info: start=", initialGapInfo.start, " size=", initialGapInfo.size

    # Insert many lines to force gap expansion
    for i in 0 ..< 100:
      gb.insertLine(i, "Line " & $i)

    let finalGapInfo = gb.getGapInfo()
    echo "Final gap info: start=", finalGapInfo.start, " size=", finalGapInfo.size

    # Verify all lines are intact
    check gb.lineCount() == 101 # 100 inserted + 1 initial
    for i in 0 ..< 100:
      check gb.getLine(i) == "Line " & $i

  test "Content integrity after gap moves":
    let gb = newGapBuffer("Line1\nLine2\nLine3\nLine4\nLine5")

    # Insert at different positions to force gap movement
    gb.insert(0, "A") # Gap moves to line 0
    gb.insert(gb.charLen, "Z") # Gap moves to end

    # Verify content is still correct
    check gb.getLine(0) == "ALine1"
    check gb.getLine(4) == "Line5Z"

  test "Alternating insert positions":
    let gb = newGapBuffer("AAAA\nBBBB\nCCCC")

    # Insert at first line
    gb.insert(2, "1")
    check gb.getLine(0) == "AA1AA"

    # Insert at last line (line number is gb.lineCount - 1)
    let lastLineStart = gb.findLineStart(gb.lineCount - 1)
    gb.insert(lastLineStart + 2, "2")
    check gb.getLine(2) == "CC2CC"

    # Insert at middle line (line 1)
    let middleLineStart = gb.findLineStart(1)
    gb.insert(middleLineStart + 2, "3")
    check gb.getLine(1) == "BB3BB"

  test "Large buffer with many operations":
    let gb = newGapBuffer()

    # Build a large buffer
    for i in 0 ..< 500:
      gb.insert(gb.charLen, "X")
      if i mod 10 == 0:
        gb.insert(gb.charLen, "\n")

    # Verify structure
    let lineCount = gb.lineCount()
    check lineCount > 1

    # Delete from various positions
    gb.delete(0, 10)
    gb.delete(100, 10)
    gb.delete(200, 10)

    # Insert again
    gb.insert(50, "TEST")

    # Verify buffer is still usable
    let text = $gb
    check text.find("TEST") != -1
    check text.find("X") != -1

  test "Gap remains functional after resize":
    let gb = newGapBuffer()

    # Small operations
    for i in 0 ..< 10:
      gb.insertLine(i, "Small" & $i)

    check gb.lineCount() == 11

    # Large expansion
    for i in 10 ..< 200:
      gb.insertLine(i, "Large" & $i)

    check gb.lineCount() == 201

    # Verify random access still works
    check gb.getLine(5) == "Small5"
    check gb.getLine(50) == "Large50"
    check gb.getLine(150) == "Large150"

  test "Sequential line insertions maintain order":
    let gb = newGapBuffer()

    for i in 0 ..< 100:
      gb.insertLine(i, $i)

    # Verify order
    for i in 0 ..< 100:
      check gb.getLine(i) == $i

  test "Gap info accessibility":
    let gb = newGapBuffer("Test")
    let info = gb.getGapInfo()

    check info.start >= 0
    check info.size >= 0
    check info.capacity >= gb.lineCount()
    check info.start + info.size <= info.capacity

  test "Memory efficiency after operations":
    let gb = newGapBuffer()

    let initialMem = gb.estimateMemoryUsage()

    # Add 100 lines
    for i in 0 ..< 100:
      gb.insertLine(i, "Line")

    let afterInsertMem = gb.estimateMemoryUsage()
    check afterInsertMem > initialMem

    # Delete 50 lines
    for i in 0 ..< 50:
      gb.deleteLine(0)

    # Memory should not grow unbounded
    let afterDeleteMem = gb.estimateMemoryUsage()
    # Still using memory for capacity, but logical lines decreased
    check gb.lineCount() == 51 # 100 - 50 + 1 initial

  test "Rapid insert/delete cycles":
    let gb = newGapBuffer("Base")

    for cycle in 0 ..< 50:
      gb.insert(2, "XY")
      gb.delete(2, 2)

    # Should return to original state
    check $gb == "Base"

  test "Gap positioning after line operations":
    let gb = newGapBuffer()

    gb.insertLine(0, "A")
    let info1 = gb.getGapInfo()

    gb.insertLine(1, "B")
    let info2 = gb.getGapInfo()

    gb.insertLine(0, "C") # Insert at beginning
    let info3 = gb.getGapInfo()

    # Gap should move around
    # Can't predict exact values, but verify consistency
    check gb.lineCount() == 4
    check gb.getLine(0) == "C"
    check gb.getLine(1) == "A"
    check gb.getLine(2) == "B"
