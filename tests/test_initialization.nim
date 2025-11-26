import unittest
import ../src/moepkg/gapbuffer

suite "GapBuffer initialization tests":
  test "Empty buffer consistency":
    let gb1 = newGapBuffer()
    let gb2 = newGapBuffer("")

    # Both should produce the same result
    check gb1.lineCount() == gb2.lineCount()
    check $gb1 == $gb2
    check gb1.getLine(0) == gb2.getLine(0)

  test "Single line without newline":
    let gb = newGapBuffer("Hello")
    check gb.lineCount() == 1
    check gb.getLine(0) == "Hello"
    check $gb == "Hello"

  test "Single line with newline":
    # Trailing newline is line terminator, not separator (POSIX semantics)
    # "Hello\n" = 1 line terminated by newline
    # Note: trailing newline is managed by endOfLine flag in TextBuffer, not gapbuffer
    let gb = newGapBuffer("Hello\n")
    check gb.lineCount() == 1
    check gb.getLine(0) == "Hello"
    # $ operator doesn't include trailing newline (managed at TextBuffer level)
    check $gb == "Hello"

  test "Multiple lines without trailing newline":
    let gb = newGapBuffer("Line1\nLine2")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Line1"
    check gb.getLine(1) == "Line2"
    check $gb == "Line1\nLine2"

  test "Multiple lines with trailing newline":
    # Trailing newline is line terminator, not separator
    # "Line1\nLine2\n" = 2 lines, each terminated by newline
    # Note: trailing newline is managed by endOfLine flag in TextBuffer, not gapbuffer
    let gb = newGapBuffer("Line1\nLine2\n")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Line1"
    check gb.getLine(1) == "Line2"
    # $ operator doesn't include trailing newline
    check $gb == "Line1\nLine2"

  test "Empty lines in middle":
    let gb = newGapBuffer("Line1\n\nLine3")
    check gb.lineCount() == 3
    check gb.getLine(0) == "Line1"
    check gb.getLine(1) == ""
    check gb.getLine(2) == "Line3"
    check $gb == "Line1\n\nLine3"
