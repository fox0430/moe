import unittest
import pkg/results

import ../src/moepkg/buffer
import ../src/moepkg/cursor

suite "Undo/Redo error handling tests":
  test "Undo with empty stack returns error":
    var buf = newTextBuffer("Hello")
    let result = buf.undo()
    check result.isErr
    check result.error == "Nothing to undo"

  test "Redo with empty stack returns error":
    var buf = newTextBuffer("Hello")
    let result = buf.redo()
    check result.isErr
    check result.error == "Nothing to redo"

  test "Multiple undos beyond stack size":
    var buf = newTextBuffer("A")
    discard buf.insertText(BufferPosition(line: 0, column: 1), "B")

    # Undo once (should succeed)
    check buf.undo().isOk

    # Undo again (should fail)
    let result = buf.undo()
    check result.isErr

  test "Nested transaction is rejected":
    var buf = newTextBuffer("Test")

    # Begin first transaction
    discard buf.beginTransaction("First")

    # Try to begin nested transaction (should be ignored)
    discard buf.beginTransaction("Nested")

    # Make changes
    discard buf.insertText(BufferPosition(line: 0, column: 4), "1")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "2")

    # Commit (should commit the first transaction)
    discard buf.commitTransaction()

    # Undo should undo both changes as one transaction
    discard buf.undo()
    check buf.getTextString() == "Test"

  test "Transaction rollback doesn't add to undo stack":
    var buf = newTextBuffer("Test")

    discard buf.beginTransaction("Rollback test")
    discard buf.insertText(BufferPosition(line: 0, column: 4), "123")
    discard buf.rollbackTransaction()

    # Undo should fail since transaction was rolled back
    let result = buf.undo()
    check result.isErr

  test "Undo with count larger than stack size":
    var buf = newTextBuffer("A")
    discard buf.insertText(BufferPosition(line: 0, column: 1), "B")
    discard buf.insertText(BufferPosition(line: 0, column: 2), "C")

    # Try to undo 10 times (only 2 changes exist)
    let result = buf.undo(10)
    check result.isOk
    check buf.getTextString() == "A"

  test "Redo with count larger than stack size":
    var buf = newTextBuffer("A")
    discard buf.insertText(BufferPosition(line: 0, column: 1), "B")
    discard buf.undo()

    # Try to redo 10 times (only 1 change in redo stack)
    let result = buf.redo(10)
    check result.isOk
    check buf.getTextString() == "AB"

  test "Undo/Redo maintains buffer consistency":
    var buf = newTextBuffer("Start")

    # Make multiple changes
    discard buf.insertText(BufferPosition(line: 0, column: 5), " Middle")
    discard buf.insertText(BufferPosition(line: 0, column: 12), " End")

    # Undo all
    discard buf.undo()
    discard buf.undo()
    check buf.getTextString() == "Start"

    # Redo all
    discard buf.redo()
    discard buf.redo()
    check buf.getTextString() == "Start Middle End"

  test "Undo count of 0 does nothing":
    var buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), " World")

    let result = buf.undo(0)
    check result.isOk
    check buf.getTextString() == "Hello World"

  test "Transaction with no changes commits empty":
    var buf = newTextBuffer("Test")

    discard buf.beginTransaction("Empty")
    # Don't make any changes
    discard buf.commitTransaction()

    # Undo should fail (no changes to undo)
    let result = buf.undo()
    check result.isErr
