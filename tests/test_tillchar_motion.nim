## Debug test for tillChar motion

import std/unittest

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/cursor {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/motion {.all.}

suite "TillChar Motion Debug":
  test "tillChar moves to correct position":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")
    let executor = newMotionExecutor(buffer)

    # Start at 'a' (column 0), find 'x' (column 3)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.tillChar(currentPos, "x", 1)

    echo "Input: 'abcxyz', cursor at column 0"
    echo "TillChar 'x' result: column ", result.x
    echo "Expected: column 2 (one before 'x' at column 3)"

    check result.y == 0
    check result.x == 2 # Should be at 'c', which is column 2

  test "findChar moves to correct position":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")
    let executor = newMotionExecutor(buffer)

    # Start at 'a' (column 0), find 'x' (column 3)
    let currentPos = CursorPosition(x: 0, y: 0)
    let result = executor.findChar(currentPos, "x", 1)

    echo "Input: 'abcxyz', cursor at column 0"
    echo "FindChar 'x' result: column ", result.x
    echo "Expected: column 3 (at 'x')"

    check result.y == 0
    check result.x == 3 # Should be at 'x', which is column 3

  test "calculateOperatorRange for TillChar":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")

    # Simulate dtx: start at column 0, tillChar moves to column 2
    let startPos = BufferPosition(line: 0, column: 0)
    let endPos = BufferPosition(line: 0, column: 2)

    let range = calculateOperatorRange(buffer, startPos, endPos, Motion.TillChar)

    echo "Input: 'abcxyz'"
    echo "Start: column 0, End: column 2 (tillChar result)"
    echo "Range: start.column=",
      range.start.column, " endPos.column=", range.endPos.column
    echo "Expected: start=0, endPos=2 (to delete columns 0,1,2 with inclusive semantics)"

    check range.start.column == 0
    check range.endPos.column == 2

  test "extractRangeText for TillChar range":
    # Setup: "abcxyz"
    let buffer = newTextBuffer("abcxyz")

    # Range from calculateOperatorRange (with inclusive semantics)
    let range = OperatorRange(
      start: BufferPosition(line: 0, column: 0),
      endPos: BufferPosition(line: 0, column: 2),
      isLinewise: false,
    )

    let text = extractRangeText(buffer, range)

    echo "Input: 'abcxyz'"
    echo "Range: column 0 to 2 (inclusive)"
    echo "Extracted text: '", text, "'"
    echo "Expected: 'abc'"

    check text == "abc"
