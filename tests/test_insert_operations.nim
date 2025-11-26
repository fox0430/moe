import unittest
import ../src/moepkg/gapbuffer

suite "Insert operations comprehensive tests":
  test "Insert into empty buffer":
    let gb = newGapBuffer()
    check gb.lineCount() == 1
    check gb.getLine(0) == ""

    gb.insert(0, "Hello")
    check gb.lineCount() == 1
    check gb.getLine(0) == "Hello"
    check $gb == "Hello"

  test "Insert at beginning of line":
    let gb = newGapBuffer("World")
    gb.insert(0, "Hello ")
    check $gb == "Hello World"
    check gb.getLine(0) == "Hello World"

  test "Insert in middle of line":
    let gb = newGapBuffer("HWorld")
    gb.insert(1, "ello ")
    check $gb == "Hello World"

  test "Insert at end of line":
    let gb = newGapBuffer("Hello")
    gb.insert(5, " World")
    check $gb == "Hello World"

  test "Insert beyond buffer end":
    let gb = newGapBuffer("Hello")
    gb.insert(100, "World")
    # Position is clamped to end, appends to same line
    check gb.lineCount() == 1
    check $gb == "HelloWorld"

  test "Insert single newline in empty buffer":
    let gb = newGapBuffer()
    gb.insert(0, "\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == ""
    check gb.getLine(1) == ""
    # $ outputs trailing newline for empty final line
    check $gb == "\n\n"

  test "Insert single newline at line start":
    let gb = newGapBuffer("Hello")
    gb.insert(0, "\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == ""
    check gb.getLine(1) == "Hello"
    check $gb == "\nHello"

  test "Insert single newline in line middle":
    let gb = newGapBuffer("HelloWorld")
    gb.insert(5, "\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    check $gb == "Hello\nWorld"

  test "Insert single newline at line end":
    let gb = newGapBuffer("Hello")
    gb.insert(5, "\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == ""
    # $ outputs trailing newline for empty final line
    check $gb == "Hello\n\n"

  test "Insert multiple consecutive newlines":
    let gb = newGapBuffer("Text")
    gb.insert(4, "\n\n\n")
    check gb.lineCount() == 4
    check gb.getLine(0) == "Text"
    check gb.getLine(1) == ""
    check gb.getLine(2) == ""
    check gb.getLine(3) == ""
    # $ outputs trailing newline for empty final line
    check $gb == "Text\n\n\n\n"

  test "Insert text with newline at start":
    let gb = newGapBuffer("World")
    gb.insert(0, "Hello\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    check $gb == "Hello\nWorld"

  test "Insert text with newline in middle":
    let gb = newGapBuffer("HWorld")
    gb.insert(1, "ello\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    check $gb == "Hello\nWorld"

  test "Insert text with newline at end":
    let gb = newGapBuffer("Hello")
    gb.insert(5, "\nWorld")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    check $gb == "Hello\nWorld"

  test "Insert multi-line text":
    let gb = newGapBuffer("Start")
    gb.insert(5, "\nLine1\nLine2\nLine3")
    check gb.lineCount() == 4
    check gb.getLine(0) == "Start"
    check gb.getLine(1) == "Line1"
    check gb.getLine(2) == "Line2"
    check gb.getLine(3) == "Line3"

  test "Insert multi-line text in middle of line":
    let gb = newGapBuffer("StartEnd")
    gb.insert(5, "\nMiddle\n")
    check gb.lineCount() == 3
    check gb.getLine(0) == "Start"
    check gb.getLine(1) == "Middle"
    check gb.getLine(2) == "End"
    check $gb == "Start\nMiddle\nEnd"

  test "Sequential insertions":
    let gb = newGapBuffer()

    gb.insert(0, "A")
    check $gb == "A"

    gb.insert(1, "B")
    check $gb == "AB"

    gb.insert(2, "\n")
    # $ outputs trailing newline for empty final line
    check $gb == "AB\n\n"
    check gb.lineCount() == 2

    gb.insert(3, "C")
    check $gb == "AB\nC"

    gb.insert(4, "D")
    check $gb == "AB\nCD"

  test "Insert character method":
    let gb = newGapBuffer()
    gb.insert(0, 'H')
    gb.insert(1, 'i')
    check $gb == "Hi"

  test "Insert preserves content after gap":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    # Insert in first line, should preserve lines 2 and 3
    gb.insert(3, "XXX")
    check gb.lineCount() == 3
    check gb.getLine(0) == "LinXXXe1"
    check gb.getLine(1) == "Line2"
    check gb.getLine(2) == "Line3"

  test "Insert with newline preserves suffix":
    let gb = newGapBuffer("HelloWorld")
    gb.insert(5, "\n")
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    # Verify by char access
    check gb.charAt(0) == 'H'
    check gb.charAt(5) == '\n'
    check gb.charAt(6) == 'W'

  test "Empty string insertion does nothing":
    let gb = newGapBuffer("Test")
    gb.insert(2, "")
    check $gb == "Test"
    check gb.lineCount() == 1
