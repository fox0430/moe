import unittest
import pkg/results

import ../src/moepkg/buffer
import ../src/moepkg/cursor

suite "Buffer undo/redo tests":
  test "Basic insert and undo":
    var buf = newTextBuffer("Hello")
    let pos = BufferPosition(line: 0, column: 5)

    # Insert text
    discard buf.insertText(pos, " World")
    check buf.getTextString() == "Hello World"

    # Undo
    let undoResult = buf.undo()
    check undoResult.isOk
    check buf.getTextString() == "Hello"

  test "Basic insert, undo and redo":
    var buf = newTextBuffer("Hello")
    let pos = BufferPosition(line: 0, column: 5)

    # Insert text
    discard buf.insertText(pos, " World")
    check buf.getTextString() == "Hello World"

    # Undo
    let undoResult = buf.undo()
    check undoResult.isOk
    check buf.getTextString() == "Hello"

    # Redo
    let redoResult = buf.redo()
    check redoResult.isOk
    check buf.getTextString() == "Hello World"

  test "Multiple undos":
    var buf = newTextBuffer("A")

    discard buf.insertText(BufferPosition(line: 0, column: 1), "B")
    check buf.getTextString() == "AB"

    discard buf.insertText(BufferPosition(line: 0, column: 2), "C")
    check buf.getTextString() == "ABC"

    discard buf.insertText(BufferPosition(line: 0, column: 3), "D")
    check buf.getTextString() == "ABCD"

    # Undo 3 times
    discard buf.undo()
    check buf.getTextString() == "ABC"

    discard buf.undo()
    check buf.getTextString() == "AB"

    discard buf.undo()
    check buf.getTextString() == "A"

  test "Undo empty stack":
    var buf = newTextBuffer("Hello")
    let result = buf.undo()
    check result.isErr
    check result.error == "Nothing to undo"

  test "Redo empty stack":
    var buf = newTextBuffer("Hello")
    let result = buf.redo()
    check result.isErr
    check result.error == "Nothing to redo"

  test "New change clears redo stack":
    var buf = newTextBuffer("A")

    discard buf.insertText(BufferPosition(line: 0, column: 1), "B")
    check buf.getTextString() == "AB"

    # Undo
    discard buf.undo()
    check buf.getTextString() == "A"

    # Make a new change - this should clear the redo stack
    discard buf.insertText(BufferPosition(line: 0, column: 1), "C")
    check buf.getTextString() == "AC"

    # Redo should now fail
    let result = buf.redo()
    check result.isErr

  test "Transaction groups multiple changes":
    var buf = newTextBuffer("A")

    # Begin transaction
    discard buf.beginTransaction("Add BC")

    discard buf.insertText(BufferPosition(line: 0, column: 1), "B")
    check buf.getTextString() == "AB"

    discard buf.insertText(BufferPosition(line: 0, column: 2), "C")
    check buf.getTextString() == "ABC"

    # Commit transaction
    discard buf.commitTransaction()

    # Single undo should undo both changes in the transaction
    discard buf.undo()
    check buf.getTextString() == "A"

    # Single redo should redo both changes
    discard buf.redo()
    check buf.getTextString() == "ABC"

  test "Rollback transaction discards changes":
    var buf = newTextBuffer("A")

    # Begin transaction
    discard buf.beginTransaction("Test rollback")

    discard buf.insertText(BufferPosition(line: 0, column: 1), "B")
    check buf.getTextString() == "AB"

    discard buf.insertText(BufferPosition(line: 0, column: 2), "C")
    check buf.getTextString() == "ABC"

    # Rollback - buffer state remains changed but not recorded for undo
    discard buf.rollbackTransaction()

    # Undo should fail because transaction was rolled back
    let result = buf.undo()
    check result.isErr

  test "Insert mode transaction - simulate mode entry and exit":
    var buf = newTextBuffer("Hello")

    # Simulate entering Insert mode (transaction begins)
    discard buf.beginTransaction("Insert mode edit")

    # Simulate typing in Insert mode
    discard buf.insertText(BufferPosition(line: 0, column: 5), " ")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "W")
    discard buf.insertText(BufferPosition(line: 0, column: 7), "o")
    discard buf.insertText(BufferPosition(line: 0, column: 8), "r")
    discard buf.insertText(BufferPosition(line: 0, column: 9), "l")
    discard buf.insertText(BufferPosition(line: 0, column: 10), "d")
    check buf.getTextString() == "Hello World"

    # Simulate leaving Insert mode (transaction commits)
    discard buf.commitTransaction()

    # Single undo should undo all 6 character insertions
    discard buf.undo(6)
    check buf.getTextString() == "Hello"

    # Redo all changes
    discard buf.redo(6)
    check buf.getTextString() == "Hello World"
