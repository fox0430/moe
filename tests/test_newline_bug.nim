import unittest
import ../src/moepkg/gapbuffer

suite "Newline insertion bug tests":
  test "Insert newline in empty buffer":
    let gb = newGapBuffer()
    echo "Initial lineCount: ", gb.lineCount()
    echo "Initial content: '", $gb, "'"

    gb.insert(0, "\n")
    echo "After insert newline, lineCount: ", gb.lineCount()
    echo "After insert newline, content: '", $gb, "'"
    echo "Line 0: '", gb.getLine(0), "'"
    echo "Line 1: '", gb.getLine(1), "'"

    check gb.lineCount() == 2

  test "Insert newline after text":
    let gb = newGapBuffer("Hello")
    echo "\nInitial: '", $gb, "'"
    echo "Initial lineCount: ", gb.lineCount()

    gb.insert(5, "\n")
    echo "After insert newline: '", $gb, "'"
    echo "LineCount: ", gb.lineCount()
    echo "Line 0: '", gb.getLine(0), "'"
    echo "Line 1: '", gb.getLine(1), "'"

    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == ""

  test "Insert text then newline":
    let gb = newGapBuffer()
    gb.insert(0, "First")
    echo "\nAfter insert 'First': '", $gb, "'"
    echo "LineCount: ", gb.lineCount()

    gb.insert(5, "\n")
    echo "After insert newline: '", $gb, "'"
    echo "LineCount: ", gb.lineCount()
    echo "Line 0: '", gb.getLine(0), "'"
    echo "Line 1: '", gb.getLine(1), "'"

    gb.insert(6, "Second")
    echo "After insert 'Second': '", $gb, "'"
    echo "LineCount: ", gb.lineCount()
    echo "Line 0: '", gb.getLine(0), "'"
    echo "Line 1: '", gb.getLine(1), "'"

    check gb.lineCount() == 2
    check gb.getLine(0) == "First"
    check gb.getLine(1) == "Second"

  test "Character position after newline":
    let gb = newGapBuffer("Line1\nLine2")
    echo "\nInitial: '", $gb, "'"
    echo "Char at 0: '", gb.charAt(0), "'"
    echo "Char at 5: '", gb.charAt(5), "'"
    echo "Char at 6: '", gb.charAt(6), "'"

    check gb.charAt(0) == 'L'
    check gb.charAt(5) == '\n'
    check gb.charAt(6) == 'L'
