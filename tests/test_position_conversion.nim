import unittest
import ../src/moepkg/gapbuffer

suite "Position conversion tests (via charAt)":
  test "Character at every position matches original text":
    let text = "Hello\nWorld\nTest"
    let gb = newGapBuffer(text)

    for i in 0 ..< text.len:
      check gb.charAt(i) == text[i]

  test "Character access at newlines":
    let gb = newGapBuffer("A\nB\nC")
    # Positions: 0: A, 1: \n, 2: B, 3: \n, 4: C

    check gb.charAt(0) == 'A'
    check gb.charAt(1) == '\n'
    check gb.charAt(2) == 'B'
    check gb.charAt(3) == '\n'
    check gb.charAt(4) == 'C'

  test "Character access in empty lines":
    let gb = newGapBuffer("A\n\nB")
    # Positions: 0: A, 1: \n, 2: \n, 3: B

    check gb.charAt(0) == 'A'
    check gb.charAt(1) == '\n'
    check gb.charAt(2) == '\n'
    check gb.charAt(3) == 'B'

  test "Insert and charAt consistency":
    let gb = newGapBuffer()

    gb.insert(0, "Hello")
    check gb.charAt(0) == 'H'
    check gb.charAt(4) == 'o'

    gb.insert(5, "\n")
    check gb.charAt(5) == '\n'

    gb.insert(6, "World")
    check gb.charAt(6) == 'W'
    check gb.charAt(10) == 'd'

    # Verify full string
    check $gb == "Hello\nWorld"

  test "findLineStart and findLineEnd":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    # "Line1\nLine2\nLine3"
    # Line 0: "Line1" (positions 0-4)
    # Line 1: "Line2" (positions 6-10)
    # Line 2: "Line3" (positions 12-16)

    # Line 0 starts at position 0, ends at 4 (before newline)
    check gb.findLineStart(0) == 0
    check gb.findLineEnd(0) == 4

    # Line 1 starts at position 6, ends at 10
    check gb.findLineStart(1) == 6
    check gb.findLineEnd(1) == 10

    # Line 2 starts at position 12, ends at 16
    check gb.findLineStart(2) == 12
    check gb.findLineEnd(2) == 16

  test "Substring extraction":
    let gb = newGapBuffer("ABCDEF")

    check gb.substring(0, 3) == "ABC"
    check gb.substring(3, 3) == "DEF"
    check gb.substring(1, 4) == "BCDE"

  test "Substring across newlines":
    let gb = newGapBuffer("AB\nCD\nEF")
    # Text: A B \n C D \n E F
    # Pos:  0 1 2  3 4 5  6 7

    check gb.substring(0, 5) == "AB\nCD" # positions 0-4
    check gb.substring(3, 5) == "CD\nEF" # positions 3-7
    check gb.substring(1, 7) == "B\nCD\nEF" # positions 1-7 (7 chars)

  test "Slice operator":
    let gb = newGapBuffer("Hello\nWorld")

    check gb[0 .. 4] == "Hello"
    check gb[5 .. 5] == "\n"
    check gb[6 .. 10] == "World"
    check gb[0 .. 10] == "Hello\nWorld"
