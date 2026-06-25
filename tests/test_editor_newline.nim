## Integration test: verify newlines work in editor context
import unittest
import ../src/moepkg/buffer_backends/gap_buffer

suite "Editor newline integration tests":
  test "Simulate typing in Insert mode":
    let gb = newGapBuffer()

    # Start with empty buffer (1 empty line)
    check gb.lineCount() == 1
    check gb.getLine(0) == ""

    # Type "Hello"
    gb.insertIntoLine(0, 0, "Hello")
    check $gb == "Hello"
    check gb.lineCount() == 1

    # Press Enter (split line 0 at its end -> new empty line follows)
    gb.insertLine(1, "")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == ""

    # Type "World"
    gb.insertIntoLine(1, 0, "World")
    check gb.lineCount() == 2
    check gb.getLine(0) == "Hello"
    check gb.getLine(1) == "World"
    check $gb == "Hello\nWorld"

  test "Simulate Normal mode 'o' command":
    let gb = newGapBuffer("First line")
    check gb.lineCount() == 1

    # Insert empty line after the first line (like 'o' command)
    gb.insertLine(1, "")

    check gb.lineCount() == 2
    check gb.getLine(0) == "First line"
    check gb.getLine(1) == ""

  test "Simulate Normal mode 'O' command":
    let gb = newGapBuffer("Second line")
    check gb.lineCount() == 1

    # Insert empty line before the first line (like 'O' command)
    gb.insertLine(0, "")

    check gb.lineCount() == 2
    check gb.getLine(0) == ""
    check gb.getLine(1) == "Second line"

  test "Multiple newlines in sequence":
    let gb = newGapBuffer()

    gb.insertLine(1, "")
    check gb.lineCount() == 2

    gb.insertLine(2, "")
    check gb.lineCount() == 3

    gb.insertLine(3, "")
    check gb.lineCount() == 4

    # All lines should be empty
    check gb.getLine(0) == ""
    check gb.getLine(1) == ""
    check gb.getLine(2) == ""
    check gb.getLine(3) == ""
