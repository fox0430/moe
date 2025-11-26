import unittest
import ../src/moepkg/gapbuffer

suite "Line-based Gap Buffer tests":
  test "Create empty buffer":
    let gb = newGapBuffer()
    check gb.lineCount() == 1 # Vim style: at least 1 line

  test "Create buffer from text":
    let text = "Hello\nWorld\nTest"
    let gb = newGapBuffer(text)
    check gb.lineCount() == 3
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    check gb.getLine(2) == "Test"

  test "Insert line":
    let gb = newGapBuffer()
    # Empty buffer starts with 1 empty line
    check gb.lineCount() == 1

    gb.insertLine(0, "First line")
    gb.insertLine(1, "Second line")
    check gb.lineCount() == 3 # Original empty line + 2 inserted
    check gb.getLine(0) == "First line"
    check gb.getLine(1) == "Second line"
    check gb.getLine(2) == "" # Original empty line

  test "Delete line":
    let gb = newGapBuffer("Line 1\nLine 2\nLine 3")
    check gb.lineCount() == 3
    gb.deleteLine(1)
    check gb.lineCount() == 2
    check gb.getLine(0) == "Line 1"
    check gb.getLine(1) == "Line 3"

  test "Character access":
    let gb = newGapBuffer("Hello\nWorld")
    check gb.charAt(0) == 'H'
    check gb.charAt(5) == '\n'
    check gb.charAt(6) == 'W'

  test "Insert text":
    let gb = newGapBuffer("Hello")
    gb.insert(5, " World")
    check gb.getLine(0) == "Hello World"

  test "Insert text with newline":
    let gb = newGapBuffer("Hello")
    gb.insert(5, "\nWorld")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"

  test "Delete characters":
    let gb = newGapBuffer("Hello World")
    gb.delete(5, 6) # Delete " World"
    check gb.getLine(0) == "Hello"

  test "Delete across lines":
    let gb = newGapBuffer("Line 1\nLine 2\nLine 3")
    gb.delete(4, 5) # Delete " 1\nLi" (positions 4-8: ' ', '1', '\n', 'L', 'i')
    # Result should be "Linene 2\nLine 3" (2 lines)
    check gb.lineCount() == 2
    check gb.getLine(0) == "Linene 2"
    check gb.getLine(1) == "Line 3"

  test "String conversion":
    let gb = newGapBuffer("Line 1\nLine 2\nLine 3")
    let text = $gb
    check text == "Line 1\nLine 2\nLine 3"

  test "Iterator chars":
    # POSIX semantics: "Hi\n" = 1 line "Hi" (newline is terminator)
    # For explicit trailing newline in iteration, use "Hi\n\n" (2 lines: "Hi", "")
    let gb = newGapBuffer("Hi\n")
    var chars: seq[char] = @[]
    for ch in gb.chars():
      chars.add(ch)
    check chars == @['H', 'i']

  test "Iterator lines":
    let gb = newGapBuffer("Line 1\nLine 2\nLine 3")
    var lines: seq[string] = @[]
    for line in gb.lines():
      lines.add(line)
    check lines == @["Line 1", "Line 2", "Line 3"]

  test "charAt for character access":
    let gb = newGapBuffer("Hello")
    check gb.charAt(0) == 'H'
    check gb.charAt(4) == 'o'

  test "Bracket operator for slicing":
    let gb = newGapBuffer("Hello World")
    check gb[0 .. 4] == "Hello"
    check gb[6 .. 10] == "World"

  test "Line operations performance - insert 1000 lines":
    let gb = newGapBuffer()
    for i in 0 ..< 1000:
      gb.insertLine(i, "Line " & $i)
    check gb.lineCount() == 1001 # 1000 inserted + 1 initial empty line
    check gb.getLine(500) == "Line 500"

  test "Line operations performance - access line 999 in 1000 line buffer":
    let gb = newGapBuffer()
    for i in 0 ..< 1000:
      gb.insertLine(i, "Line " & $i)
    # This should be O(1) with line-based gap buffer
    check gb.lineCount() == 1001
    check gb.getLine(999) == "Line 999"

  test "Gap info returns line-based metrics":
    let gb = newGapBuffer("Line 1\nLine 2\nLine 3")
    let info = gb.getGapInfo()
    check info.start >= 0 # Gap position in lines
    check info.size > 0 # Gap size in lines
    check info.capacity >= gb.lineCount()
