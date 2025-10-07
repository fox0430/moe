#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, options, strutils]

import pkg/results

import ../src/moepkg/[buffer, cursor]

suite "Buffer - Undo/Redo Basic Operations":
  test "undo insertText single character":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.getLine(0) == "hello!"

    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "hello"

  test "undo insertText multiple characters":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), " line")
    check b.getLine(0) == "test line"

    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "test"

  test "undo deleteChar":
    let b = newTextBuffer("hello")
    discard b.deleteChar(BufferPosition(line: 0, column: 4))
    check b.getLine(0) == "hell"

    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "hello"

  test "undo insert line":
    let b = newTextBuffer("line1\nline3")
    discard b.insert(1, "line2")
    check b.len == 3
    check b.getLine(1) == "line2"

    let r = b.undo()
    check r.isOk
    check b.len == 2
    check b.getLine(1) == "line3"

  test "undo delete line":
    let b = newTextBuffer("line1\nline2\nline3")
    discard b.deleteLine(1)
    check b.len == 2
    check b.getLine(1) == "line3"

    let r = b.undo()
    check r.isOk
    check b.len == 3
    check b.getLine(1) == "line2"

  test "undo deleteRange single line":
    let b = newTextBuffer("hello world")
    discard b.deleteRange(
      BufferPosition(line: 0, column: 5), BufferPosition(line: 0, column: 10)
    )
    check b.getLine(0) == "hello"

    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "hello world"

  test "undo deleteRange multi-line":
    let b = newTextBuffer("line1\nline2\nline3")
    # Delete from end of line1 (inclusive) to first char of line3 (inclusive)
    # This should delete: "\nline2\nl" and join "line1" with "ine3"
    discard b.deleteRange(
      BufferPosition(line: 0, column: 5), BufferPosition(line: 2, column: 0)
    )
    # After delete, should be "line1ine3" on one line
    check b.len == 1
    check b.getLine(0) == "line1ine3"

    let r = b.undo()
    check r.isOk
    check b.len == 3
    check b.getLine(0) == "line1"
    check b.getLine(1) == "line2"
    check b.getLine(2) == "line3"

  test "undo with nothing to undo":
    let b = newTextBuffer("test")
    let r = b.undo()
    check r.isErr
    check r.error == "Nothing to undo"

suite "Buffer - Redo Operations":
  test "redo insertText":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    discard b.undo()
    check b.getLine(0) == "hello"

    let r = b.redo()
    check r.isOk
    check b.getLine(0) == "hello!"

  test "redo deleteChar":
    let b = newTextBuffer("hello")
    discard b.deleteChar(BufferPosition(line: 0, column: 4))
    discard b.undo()
    check b.getLine(0) == "hello"

    let r = b.redo()
    check r.isOk
    check b.getLine(0) == "hell"

  test "redo with nothing to redo":
    let b = newTextBuffer("test")
    let r = b.redo()
    check r.isErr
    check r.error == "Nothing to redo"

  test "redo stack cleared after new change":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), "1")
    discard b.undo()
    discard b.insertText(BufferPosition(line: 0, column: 4), "2")

    let r = b.redo()
    check r.isErr
    check r.error == "Nothing to redo"

suite "Buffer - Multiple Undo/Redo":
  test "multiple undo":
    let b = newTextBuffer("a")
    discard b.insertText(BufferPosition(line: 0, column: 1), "b")
    discard b.insertText(BufferPosition(line: 0, column: 2), "c")
    discard b.insertText(BufferPosition(line: 0, column: 3), "d")
    check b.getLine(0) == "abcd"

    let r = b.undo(2)
    check r.isOk
    check b.getLine(0) == "ab"

  test "multiple redo":
    let b = newTextBuffer("a")
    discard b.insertText(BufferPosition(line: 0, column: 1), "b")
    discard b.insertText(BufferPosition(line: 0, column: 2), "c")
    discard b.undo(2)
    check b.getLine(0) == "a"

    let r = b.redo(2)
    check r.isOk
    check b.getLine(0) == "abc"

  test "undo/redo sequence":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), " 1")
    discard b.insertText(BufferPosition(line: 0, column: 6), " 2")
    discard b.insertText(BufferPosition(line: 0, column: 8), " 3")
    check b.getLine(0) == "test 1 2 3"

    discard b.undo()
    check b.getLine(0) == "test 1 2"
    discard b.undo()
    check b.getLine(0) == "test 1"
    discard b.redo()
    check b.getLine(0) == "test 1 2"
    discard b.redo()
    check b.getLine(0) == "test 1 2 3"

suite "Buffer - Unicode Undo/Redo":
  test "undo insert unicode character":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "日本語")
    check b.getLine(0) == "hello日本語"

    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "hello"

  test "undo delete unicode character":
    let b = newTextBuffer("こんにちは")
    discard b.deleteChar(BufferPosition(line: 0, column: 0))
    check b.getLine(0) == "んにちは"

    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "こんにちは"

  test "undo deleteRange with unicode":
    let b = newTextBuffer("Hello世界World")
    discard b.deleteRange(
      BufferPosition(line: 0, column: 5), BufferPosition(line: 0, column: 6)
    )

    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "Hello世界World"

suite "Buffer - Transaction Support":
  test "transaction commit creates single undo entry":
    let b = newTextBuffer("test")
    discard b.beginTransaction("multi-edit")
    discard b.insertText(BufferPosition(line: 0, column: 4), " 1")
    discard b.insertText(BufferPosition(line: 0, column: 6), " 2")
    discard b.insertText(BufferPosition(line: 0, column: 8), " 3")
    discard b.commitTransaction()
    check b.getLine(0) == "test 1 2 3"

    # Single undo should undo all changes in transaction
    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "test"

  test "transaction rollback reverts all changes":
    let b = newTextBuffer("test")
    discard b.beginTransaction("test-rollback")
    discard b.insertText(BufferPosition(line: 0, column: 4), " 1")
    discard b.insertText(BufferPosition(line: 0, column: 6), " 2")
    check b.getLine(0) == "test 1 2"

    let r = b.rollbackTransaction()
    check r.isOk
    check b.getLine(0) == "test"

    # No undo entry should be created
    let undoResult = b.undo()
    check undoResult.isErr

  test "nested transaction fails":
    let b = newTextBuffer("test")
    discard b.beginTransaction("outer")
    let r = b.beginTransaction("inner")
    check r.isErr
    check r.error.contains("Transaction already in progress")

  test "commit without transaction fails":
    let b = newTextBuffer("test")
    let r = b.commitTransaction()
    check r.isErr
    check r.error.contains("No transaction in progress")

  test "rollback without transaction fails":
    let b = newTextBuffer("test")
    let r = b.rollbackTransaction()
    check r.isErr
    check r.error.contains("No transaction in progress")

suite "Buffer - Modified Flag":
  test "isModified returns false for new buffer":
    let b = newTextBuffer("test")
    check not b.isModified

  test "isModified returns true after change":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), "!")
    check b.isModified

  test "isModified returns false after undo to saved state":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), "!")
    discard b.undo()
    check not b.isModified

  test "isModified with transaction":
    let b = newTextBuffer("test")
    discard b.beginTransaction("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), "!")
    discard b.commitTransaction()
    check b.isModified

  test "isModified during transaction":
    let b = newTextBuffer("test")
    check not b.isModified

    discard b.beginTransaction("test")
    check not b.isModified # Still not modified before any changes

    discard b.insertText(BufferPosition(line: 0, column: 4), "!")
    check b.isModified # Should be modified immediately

    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.isModified # Still modified

    discard b.commitTransaction()
    check b.isModified # Still modified after commit

  test "isModified after transaction rollback":
    let b = newTextBuffer("test")
    check not b.isModified

    discard b.beginTransaction("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), "!")
    check b.isModified # Modified during transaction

    discard b.rollbackTransaction()
    check not b.isModified # Should be unmodified after rollback
    check b.getLine(0) == "test" # Content should be restored

  test "isModified with nested edits and rollback":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), " 1")
    check b.isModified
    let seq1 = b.changeSeq

    discard b.beginTransaction("test")
    discard b.insertText(BufferPosition(line: 0, column: 6), " 2")
    discard b.insertText(BufferPosition(line: 0, column: 8), " 3")
    check b.changeSeq == seq1 + 2 # Two changes in transaction

    discard b.rollbackTransaction()
    check b.changeSeq == seq1 # Should be restored to seq1
    check b.isModified # Still modified (original " 1" is still there)
    check b.getLine(0) == "test 1" # Only original change remains

suite "Buffer - Cursor Position Suggestion":
  test "undo returns suggested cursor position":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), " line")

    let r = b.undo()
    check r.isOk
    check r.value.line == 0
    check r.value.column == 4

  test "redo returns suggested cursor position":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), "!")
    discard b.undo()

    let r = b.redo()
    check r.isOk
    check r.value.line == 0
    check r.value.column == 4
