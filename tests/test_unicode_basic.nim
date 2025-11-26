import unittest

import ../src/moepkg/buffer
import ../src/moepkg/cursor

suite "Basic Unicode buffer tests":
  test "Create buffer with Unicode text":
    var buf = newTextBuffer("日本")
    check buf.getTextString() == "日本"

  test "Create buffer with emoji":
    var buf = newTextBuffer("🎉")
    check buf.getTextString() == "🎉"

  test "Create buffer with mixed text":
    var buf = newTextBuffer("Hello 世界")
    check buf.getTextString() == "Hello 世界"

  test "Insert Unicode at position":
    var buf = newTextBuffer("日本")
    discard buf.insertText(BufferPosition(line: 0, column: 2), "🎉")
    echo "Result: ", buf.getTextString()
    echo "Expected: 日本🎉"
    check buf.getTextString() == "日本🎉"

  test "Get line with Unicode":
    var buf = newTextBuffer("こんにちは")
    let line = buf.getLine(0)
    echo "Line: ", line
    check line == "こんにちは"
