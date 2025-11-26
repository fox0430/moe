import unittest
import ../src/moepkg/gapbuffer

suite "Edge cases and boundary conditions":
  test "Empty buffer operations":
    let gb = newGapBuffer()

    # charAt on empty buffer should fail (no characters)
    expect(IndexDefect):
      discard gb.charAt(0)

    # getLine on empty returns empty string
    check gb.getLine(0) == ""

    # String conversion
    check $gb == ""

    # Length
    check gb.charLen == 0 # No actual characters
    check gb.lineCount() == 1 # One empty line

  test "Single character buffer":
    let gb = newGapBuffer("A")

    check gb.len == 1
    check gb.charAt(0) == 'A'
    check $gb == "A"

    # Delete it
    gb.delete(0, 1)
    check $gb == ""

  test "Buffer with only newlines":
    let gb = newGapBuffer("\n\n\n")

    # Trailing newline is line terminator, not separator
    # So "\n\n\n" = 3 empty lines (each terminated by newline)
    check gb.lineCount() == 3
    for i in 0 ..< 3:
      check gb.getLine(i) == ""

  test "Very long line":
    var longText = ""
    for i in 0 ..< 10000:
      longText.add('X')

    let gb = newGapBuffer(longText)
    check gb.lineCount() == 1
    check gb.getLine(0).len == 10000
    check gb.charLen == 10000

  test "Many empty lines":
    let gb = newGapBuffer()
    for i in 0 ..< 1000:
      gb.insertLine(i, "")

    check gb.lineCount() == 1001 # 1000 + initial
    for i in 0 ..< 1000:
      check gb.getLine(i) == ""

  test "Unicode characters":
    let gb = newGapBuffer("Hello 世界 🌍")

    # Can access all characters
    let text = $gb
    check text == "Hello 世界 🌍"

    # Insert Unicode
    gb.insert(6, "日本")
    check $gb == "Hello 日本世界 🌍"

  test "Boundary: charAt at line boundaries":
    let gb = newGapBuffer("AB\nCD")
    # Positions: A(0) B(1) \n(2) C(3) D(4)

    check gb.charAt(0) == 'A'
    check gb.charAt(1) == 'B'
    check gb.charAt(2) == '\n'
    check gb.charAt(3) == 'C'
    check gb.charAt(4) == 'D'

    # Beyond end
    expect(IndexDefect):
      discard gb.charAt(5)

  test "Boundary: insert at every position":
    let gb = newGapBuffer("ABC")

    # Insert at each position
    gb.insert(0, "0") # "0ABC"
    gb.insert(2, "1") # "0A1BC"
    gb.insert(5, "2") # "0A1BC2"

    check $gb == "0A1BC2"

  test "Boundary: delete at boundaries":
    let gb = newGapBuffer("ABCDEF")

    # Delete from start
    gb.delete(0, 1)
    check $gb == "BCDEF"

    # Delete from current end
    gb.delete(4, 1)
    check $gb == "BCDE"

  test "Zero-length operations":
    let gb = newGapBuffer("Test")

    # Insert zero-length string
    gb.insert(2, "")
    check $gb == "Test"

    # Delete zero count
    gb.delete(2, 0)
    check $gb == "Test"

  test "Negative values":
    let gb = newGapBuffer("Test")

    # Negative delete count
    gb.delete(2, -5)
    check $gb == "Test"

  test "Out of bounds access":
    let gb = newGapBuffer("Test")

    # charAt beyond (but within last line's virtual newline might succeed)
    # Position 4 is the virtual newline, 5+ should fail
    expect(IndexDefect):
      discard gb.charAt(100)

    # getLine beyond
    check gb.getLine(100) == ""

    # delete beyond does partial delete
    gb.delete(2, 100)
    check $gb == "Te"

  test "Alternating line/character operations":
    let gb = newGapBuffer()
    # Initial: 1 empty line

    # Line operation - insert at line 0, pushes empty line to line 1
    gb.insertLine(0, "Line1")
    check gb.lineCount() == 2 # "Line1" + original empty line

    # Character operation - insert newline after "Line1"
    gb.insert(5, "\n")
    check gb.lineCount() == 3 # "Line1" + "" + original empty line

    # Line operation - insert at line 2
    gb.insertLine(2, "Line2")
    check gb.lineCount() == 4 # "Line1" + "" + "Line2" + original empty line

    # Verify
    check gb.getLine(0) == "Line1"
    check gb.getLine(2) == "Line2"

  test "Clear and reuse":
    let gb = newGapBuffer("Initial content")

    gb.clear()
    # After clear, buffer has one empty line (vim-style)
    check gb.lineCount() == 1
    check gb.charLen == 0
    check $gb == ""

    gb.insert(0, "New content")
    check $gb == "New content"

  test "Maximum line number access":
    let gb = newGapBuffer("L1\nL2\nL3")

    let maxLine = gb.lineCount() - 1
    check gb.getLine(maxLine) == "L3"

    # One beyond max
    check gb.getLine(maxLine + 1) == ""

  test "Insert then immediate delete":
    let gb = newGapBuffer("Base")

    let originalLen = gb.len
    gb.insert(2, "XYZ")
    gb.delete(2, 3)

    check gb.len == originalLen
    check $gb == "Base"

  test "Substring boundaries":
    let gb = newGapBuffer("ABCDE")

    # Full substring
    check gb.substring(0, 5) == "ABCDE"

    # Partial from start
    check gb.substring(0, 3) == "ABC"

    # Partial from end
    check gb.substring(2, 3) == "CDE"

    # Beyond end
    check gb.substring(3, 100) == "DE"

    # Start beyond end
    check gb.substring(100, 5) == ""

  test "Line iterator on edge cases":
    # Empty buffer
    let gb1 = newGapBuffer()
    var count1 = 0
    for line in gb1.lines():
      inc count1
    check count1 == 1

    # Single line
    let gb2 = newGapBuffer("Test")
    var lines2: seq[string] = @[]
    for line in gb2.lines():
      lines2.add(line)
    check lines2.len == 1

  test "Character iterator completeness":
    # POSIX semantics: "A\nB\n" = 2 lines "A" and "B" (trailing newline is terminator)
    # chars() iterator is consistent with $ operator
    let text = "A\nB\n"
    let gb = newGapBuffer(text)

    var reconstructed = ""
    for ch in gb.chars():
      reconstructed.add(ch)

    # Trailing newline is not preserved (POSIX terminator semantics)
    check reconstructed == "A\nB"
    check reconstructed == $gb

  test "Slice operator boundaries":
    let gb = newGapBuffer("ABCDE")

    # Normal slice
    check gb[0 .. 2] == "ABC"

    # Slice to end
    check gb[2 .. 4] == "CDE"

    # Single character slice
    check gb[2 .. 2] == "C"

    # Beyond end
    check gb[3 .. 100] == "DE"
