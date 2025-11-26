import unittest
import pkg/results

import ../src/moepkg/buffer
import ../src/moepkg/cursor

suite "Undo/Redo edge case tests":
  test "Insert at invalid line position":
    var buf = newTextBuffer("Line1")

    # Try to insert at line 10 (doesn't exist)
    let insertResult = buf.insertText(BufferPosition(line: 10, column: 0), "Text")

    # Insert at invalid position should fail, and no undo should be recorded
    check insertResult.isErr
    let undoResult = buf.undo()
    check undoResult.isErr

  test "Delete at invalid position":
    var buf = newTextBuffer("Test")

    # Try to delete at invalid position
    discard buf.deleteChar(BufferPosition(line: 10, column: 0))

    # Undo should fail (no change was made)
    let result = buf.undo()
    check result.isErr

  test "Undo/Redo with empty buffer":
    var buf = newTextBuffer("")

    discard buf.insertText(BufferPosition(line: 0, column: 0), "A")
    check buf.getTextString() == "A"

    discard buf.undo()
    check buf.getTextString() == ""

    discard buf.redo()
    check buf.getTextString() == "A"

  test "Undo/Redo with very long text":
    var buf = newTextBuffer("Start")

    # Insert 1000 characters
    var longText = ""
    for i in 0 ..< 1000:
      longText.add('X')

    discard buf.insertText(BufferPosition(line: 0, column: 5), longText)
    check buf.getTextString().len == 1005

    discard buf.undo()
    check buf.getTextString() == "Start"

    discard buf.redo()
    check buf.getTextString().len == 1005

  test "Undo/Redo with Unicode emoji sequence":
    var buf = newTextBuffer("Test")

    # Insert complex emoji with modifiers
    discard
      buf.insertText(BufferPosition(line: 0, column: 4), "👨‍👩‍👧‍👦")

    discard buf.undo()
    check buf.getTextString() == "Test"

    discard buf.redo()
    check buf.getTextString() == "Test👨‍👩‍👧‍👦"

  test "Interleaved undo/redo operations":
    var buf = newTextBuffer("A")

    discard buf.insertText(BufferPosition(line: 0, column: 1), "B")
    check buf.getTextString() == "AB"

    discard buf.undo()
    check buf.getTextString() == "A"

    discard buf.insertText(BufferPosition(line: 0, column: 1), "C")
    check buf.getTextString() == "AC"

    # Redo should fail (new change cleared redo stack)
    let result = buf.redo()
    check result.isErr

  test "Transaction with single change behaves correctly":
    var buf = newTextBuffer("Test")

    discard buf.beginTransaction("Single")
    discard buf.insertText(BufferPosition(line: 0, column: 4), "1")
    discard buf.commitTransaction()

    discard buf.undo()
    check buf.getTextString() == "Test"

    discard buf.redo()
    check buf.getTextString() == "Test1"

  test "Commit transaction while not in transaction":
    var buf = newTextBuffer("Test")

    # Commit without begin (should be safe/ignored)
    discard buf.commitTransaction()

    discard buf.insertText(BufferPosition(line: 0, column: 4), "1")

    # Normal undo should still work
    discard buf.undo()
    check buf.getTextString() == "Test"

  test "Rollback transaction while not in transaction":
    var buf = newTextBuffer("Test")

    # Rollback without begin (should be safe/ignored)
    discard buf.rollbackTransaction()

    discard buf.insertText(BufferPosition(line: 0, column: 4), "1")

    # Normal undo should still work
    discard buf.undo()
    check buf.getTextString() == "Test"
