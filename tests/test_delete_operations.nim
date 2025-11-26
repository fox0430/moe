import unittest
import ../src/moepkg/gapbuffer

suite "Delete operations comprehensive tests":
  test "Delete single character from line":
    let gb = newGapBuffer("Hello")
    gb.delete(1, 1) # Delete 'e'
    check $gb == "Hllo"
    check gb.lineCount() == 1

  test "Delete from beginning of line":
    let gb = newGapBuffer("Hello")
    gb.delete(0, 2) # Delete "He"
    check $gb == "llo"

  test "Delete from end of line":
    let gb = newGapBuffer("Hello")
    gb.delete(3, 2) # Delete "lo"
    check $gb == "Hel"

  test "Delete entire line content":
    let gb = newGapBuffer("Hello")
    gb.delete(0, 5)
    check $gb == ""
    check gb.lineCount() == 1 # Line still exists but empty

  test "Delete newline character":
    let gb = newGapBuffer("Hello\nWorld")
    check gb.lineCount() == 2

    gb.delete(5, 1) # Delete the newline
    check $gb == "HelloWorld"
    check gb.lineCount() == 1

  test "Delete across two lines":
    let gb = newGapBuffer("Hello\nWorld")
    gb.delete(3, 5) # Delete "lo\nWo"
    check $gb == "Helrld"
    check gb.lineCount() == 1

  test "Delete entire first line including newline":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    gb.delete(0, 6) # Delete "Line1\n"
    check $gb == "Line2\nLine3"
    check gb.lineCount() == 2
    check gb.getLine(0) == "Line2"

  test "Delete middle line completely":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    gb.delete(6, 6) # Delete "Line2\n"
    check $gb == "Line1\nLine3"
    check gb.lineCount() == 2

  test "Delete across three lines":
    let gb = newGapBuffer("Line1\nLine2\nLine3")
    gb.delete(3, 11) # Delete "e1\nLine2\nLi"
    check $gb == "Linne3"
    check gb.lineCount() == 1

  test "Delete from middle to end":
    let gb = newGapBuffer("Hello\nWorld\nTest")
    gb.delete(7, 100) # Delete from 'o' in World to end
    check $gb == "Hello\nW"
    check gb.lineCount() == 2

  test "Delete beyond buffer does nothing extra":
    let gb = newGapBuffer("Test")
    gb.delete(2, 100) # Delete from position 2 to end
    check $gb == "Te"

  test "Delete with count 0 does nothing":
    let gb = newGapBuffer("Hello")
    gb.delete(2, 0)
    check $gb == "Hello"

  test "Delete with negative count does nothing":
    let gb = newGapBuffer("Hello")
    gb.delete(2, -5)
    check $gb == "Hello"

  test "Delete from invalid position does nothing":
    let gb = newGapBuffer("Hello")
    gb.delete(100, 5)
    check $gb == "Hello"

  test "Delete empty lines":
    let gb = newGapBuffer("A\n\nB")
    check gb.lineCount() == 3

    gb.delete(2, 1) # Delete second newline
    check $gb == "A\nB"
    check gb.lineCount() == 2

  test "Sequential deletes":
    let gb = newGapBuffer("ABCDEF")

    gb.delete(2, 1) # Delete 'C' -> "ABDEF"
    check $gb == "ABDEF"

    gb.delete(2, 1) # Delete 'D' -> "ABEF"
    check $gb == "ABEF"

    gb.delete(1, 2) # Delete 'BE' -> "AF"
    check $gb == "AF"

  test "Delete and insert combination":
    let gb = newGapBuffer("Hello World")

    gb.delete(5, 6) # Delete " World" -> "Hello"
    check $gb == "Hello"

    gb.insert(5, "\nNim") # Insert newline and "Nim"
    check $gb == "Hello\nNim"
    check gb.lineCount() == 2

  test "Delete preserves content before and after":
    let gb = newGapBuffer("AAA\nBBB\nCCC\nDDD")

    gb.delete(8, 4) # Delete "CCC\n"
    check gb.lineCount() == 3
    check gb.getLine(0) == "AAA"
    check gb.getLine(1) == "BBB"
    check gb.getLine(2) == "DDD"

  test "Delete entire buffer except last line":
    let gb = newGapBuffer("A\nB\nC")
    gb.delete(0, 4) # Delete "A\nB\n"
    check $gb == "C"
    check gb.lineCount() == 1

  test "Delete in empty buffer does nothing":
    let gb = newGapBuffer()
    gb.delete(0, 5)
    check gb.lineCount() == 1
    check $gb == ""

  test "Delete single char with charAt verification":
    let gb = newGapBuffer("ABCDE")
    check gb.charAt(2) == 'C'

    gb.delete(2, 1)
    check gb.charAt(2) == 'D'
    check $gb == "ABDE"

  test "Delete newline merges lines correctly":
    let gb = newGapBuffer("First\nSecond")
    let origLineCount = gb.lineCount()
    check origLineCount == 2

    gb.delete(5, 1) # Delete newline at position 5
    check gb.lineCount() == 1
    check gb.getLine(0) == "FirstSecond"
