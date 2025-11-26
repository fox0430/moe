import unittest
import pkg/results

import ../src/moepkg/buffer
import ../src/moepkg/cursor

suite "Buffer undo/redo Unicode tests":
  test "Undo Unicode character insertion":
    var buf = newTextBuffer("Hello")
    let pos = BufferPosition(line: 0, column: 5)

    # Insert Japanese character "あ" (3 bytes in UTF-8: E3 81 82)
    discard buf.insertText(pos, "あ")
    check buf.getTextString() == "Helloあ"

    # Undo should remove the entire character
    let undoResult = buf.undo()
    check undoResult.isOk
    check buf.getTextString() == "Hello"

  test "Undo multiple Unicode characters":
    var buf = newTextBuffer("日本")
    let pos = BufferPosition(line: 0, column: 2)

    # Insert emoji "🎉" (4 bytes in UTF-8)
    discard buf.insertText(pos, "🎉")
    check buf.getTextString() == "日本🎉"

    # Undo
    let undoResult = buf.undo()
    check undoResult.isOk
    check buf.getTextString() == "日本"

  test "Undo Unicode string insertion":
    var buf = newTextBuffer("Test")
    let pos = BufferPosition(line: 0, column: 4)

    # Insert mixed Unicode string
    discard buf.insertText(pos, " こんにちは世界")
    check buf.getTextString() == "Test こんにちは世界"

    # Undo
    let undoResult = buf.undo()
    check undoResult.isOk
    check buf.getTextString() == "Test"

  test "Undo and redo with Unicode":
    var buf = newTextBuffer("Hello")
    let pos = BufferPosition(line: 0, column: 5)

    # Insert
    discard buf.insertText(pos, " 世界")
    check buf.getTextString() == "Hello 世界"

    # Undo
    discard buf.undo()
    check buf.getTextString() == "Hello"

    # Redo
    let redoResult = buf.redo()
    check redoResult.isOk
    check buf.getTextString() == "Hello 世界"

  test "Delete Unicode character and undo":
    var buf = newTextBuffer("こんにちは")
    # Delete the first character "こ"
    discard buf.deleteChar(BufferPosition(line: 0, column: 0))
    check buf.getTextString() == "んにちは"

    # Undo should restore "こ"
    let undoResult = buf.undo()
    check undoResult.isOk
    check buf.getTextString() == "こんにちは"
