#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

import ../src/moepkg/buffer
import ../src/moepkg/syntax/tokenizer

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

suite "Buffer - Redo with Newlines and Highlighting":
  test "redo insertText with newline updates buffer length":
    # Regression test for bug where redo did not handle newlines correctly
    let b = newTextBuffer("line1\nline2\nline3")
    check b.len == 3

    # Insert text with newline at line 1, column 0
    discard b.insertText(BufferPosition(line: 1, column: 0), "new\n")
    check b.len == 4
    check b.getLine(0) == "line1"
    check b.getLine(1) == "new"
    check b.getLine(2) == "line2"
    check b.getLine(3) == "line3"

    # Undo the insertion
    discard b.undo()
    check b.len == 3
    check b.getLine(0) == "line1"
    check b.getLine(1) == "line2"
    check b.getLine(2) == "line3"

    # Redo should correctly handle the newline and restore buffer to 4 lines
    let r = b.redo()
    check r.isOk
    check b.len == 4
    check b.getLine(0) == "line1"
    check b.getLine(1) == "new"
    check b.getLine(2) == "line2"
    check b.getLine(3) == "line3"

  test "redo insertText with multiple newlines":
    let b = newTextBuffer("first\nlast")
    check b.len == 2

    # Insert multiple lines at the end of first line
    discard b.insertText(BufferPosition(line: 0, column: 5), "\nmiddle1\nmiddle2")
    check b.len == 4
    check b.getLine(0) == "first"
    check b.getLine(1) == "middle1"
    check b.getLine(2) == "middle2"
    check b.getLine(3) == "last"

    # Undo
    discard b.undo()
    check b.len == 2
    check b.getLine(0) == "first"
    check b.getLine(1) == "last"

    # Redo should restore all 4 lines
    let r = b.redo()
    check r.isOk
    check b.len == 4
    check b.getLine(0) == "first"
    check b.getLine(1) == "middle1"
    check b.getLine(2) == "middle2"
    check b.getLine(3) == "last"

  test "redo with highlighting maintains consistency":
    # Regression test: ensure buffer length and highlight segments stay in sync
    let b = newTextBuffer("func test() {")
    b.language = SourceLanguage.langNim
    check b.len == 1

    # Insert newline to create second line
    discard b.insertText(BufferPosition(line: 0, column: 13), "\n  return")
    check b.len == 2
    check b.getLine(0) == "func test() {"
    check b.getLine(1) == "  return"

    # Update highlighting to ensure it's initialized
    b.updateHighlight()

    # Undo the insertion
    discard b.undo()
    check b.len == 1
    check b.getLine(0) == "func test() {"

    # Update highlighting after undo
    b.updateHighlight()

    # Redo should maintain buffer and highlight consistency
    let r = b.redo()
    check r.isOk
    check b.len == 2
    check b.getLine(0) == "func test() {"
    check b.getLine(1) == "  return"

    # Update highlighting after redo - should not crash or create invalid segments
    b.updateHighlight()

    # Verify highlight segments don't reference invalid line numbers
    if b.highlight.colorSegments.len > 0:
      for seg in b.highlight.colorSegments:
        # All segments should reference lines within buffer bounds
        check seg.firstRow < b.len
        check seg.lastRow < b.len

  test "multiple redo with newlines":
    let b = newTextBuffer("start")

    # Make multiple insertions with newlines
    discard b.insertText(BufferPosition(line: 0, column: 5), "\nline1")
    discard b.insertText(BufferPosition(line: 1, column: 5), "\nline2")
    discard b.insertText(BufferPosition(line: 2, column: 5), "\nline3")
    check b.len == 4

    # Undo all
    discard b.undo(3)
    check b.len == 1
    check b.getLine(0) == "start"

    # Redo all
    let r = b.redo(3)
    check r.isOk
    check b.len == 4
    check b.getLine(0) == "start"
    check b.getLine(1) == "line1"
    check b.getLine(2) == "line2"
    check b.getLine(3) == "line3"

suite "Buffer - Undo/Redo Edge Cases":
  test "undo/redo with empty buffer":
    let b = newTextBuffer("")
    discard b.insertText(BufferPosition(line: 0, column: 0), "A")
    check b.getLine(0) == "A"

    discard b.undo()
    check b.getLine(0) == ""

    discard b.redo()
    check b.getLine(0) == "A"

  test "insert at invalid line returns error":
    let b = newTextBuffer("Line1")
    let r = b.insertText(BufferPosition(line: 10, column: 0), "Text")
    check r.isErr
    # No undo entry should be recorded for failed operation
    check b.undo().isErr

  test "delete at invalid position":
    let b = newTextBuffer("Test")
    discard b.deleteChar(BufferPosition(line: 10, column: 0))
    # No change was made, so undo should fail
    check b.undo().isErr

  test "undo/redo with very long text":
    let b = newTextBuffer("Start")
    var longText = ""
    for i in 0 ..< 1000:
      longText.add('X')

    discard b.insertText(BufferPosition(line: 0, column: 5), longText)
    check b.getLine(0).len == 1005

    discard b.undo()
    check b.getLine(0) == "Start"

    discard b.redo()
    check b.getLine(0).len == 1005

  test "undo/redo with complex emoji sequence":
    let b = newTextBuffer("Test")
    # Family emoji with ZWJ (zero-width joiner)
    discard
      b.insertText(BufferPosition(line: 0, column: 4), "👨‍👩‍👧‍👦")

    discard b.undo()
    check b.getLine(0) == "Test"

    discard b.redo()
    check b.getLine(0) == "Test👨‍👩‍👧‍👦"

  test "undo count of 0 does nothing":
    let b = newTextBuffer("Hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), " World")
    check b.getLine(0) == "Hello World"

    let r = b.undo(0)
    check r.isOk
    check b.getLine(0) == "Hello World"

  test "undo count larger than stack size":
    let b = newTextBuffer("A")
    discard b.insertText(BufferPosition(line: 0, column: 1), "B")
    discard b.insertText(BufferPosition(line: 0, column: 2), "C")
    check b.getLine(0) == "ABC"

    # Try to undo 10 times (only 2 changes exist)
    let r = b.undo(10)
    check r.isOk
    check b.getLine(0) == "A"

  test "redo count larger than stack size":
    let b = newTextBuffer("A")
    discard b.insertText(BufferPosition(line: 0, column: 1), "B")
    discard b.undo()
    check b.getLine(0) == "A"

    # Try to redo 10 times (only 1 change in redo stack)
    let r = b.redo(10)
    check r.isOk
    check b.getLine(0) == "AB"

  test "interleaved undo/redo clears redo stack on new change":
    let b = newTextBuffer("A")
    discard b.insertText(BufferPosition(line: 0, column: 1), "B")
    check b.getLine(0) == "AB"

    discard b.undo()
    check b.getLine(0) == "A"

    # Make a new change - this clears the redo stack
    discard b.insertText(BufferPosition(line: 0, column: 1), "C")
    check b.getLine(0) == "AC"

    # Redo should now fail
    check b.redo().isErr

suite "Buffer - Cursor Position Details":
  test "undo multiple changes returns last undo position":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), " one")
    discard b.insertText(BufferPosition(line: 0, column: 8), " two")
    discard b.insertText(BufferPosition(line: 0, column: 12), " three")
    check b.getLine(0) == "test one two three"

    # Undo 2 changes - should return position of last (2nd) undo
    let r = b.undo(2)
    check r.isOk
    check r.value.line == 0
    check r.value.column == 8 # Position of " two" insertion

  test "redo multiple changes returns last redo position":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), " one")
    discard b.insertText(BufferPosition(line: 0, column: 8), " two")
    discard b.undo(2)
    check b.getLine(0) == "test"

    # Redo 2 changes - should return position of last (2nd) redo
    let r = b.redo(2)
    check r.isOk
    check r.value.line == 0
    check r.value.column == 8 # Position of " two" insertion

  test "undo delete returns deletion position":
    let b = newTextBuffer("hello world")
    discard b.deleteRange(
      BufferPosition(line: 0, column: 5), BufferPosition(line: 0, column: 10)
    )
    check b.getLine(0) == "hello"

    let r = b.undo()
    check r.isOk
    check r.value.line == 0
    check r.value.column == 5 # Start of deleted range

  test "undo line deletion returns line position":
    let b = newTextBuffer("line1\nline2\nline3")
    discard b.deleteLine(1)
    check b.len == 2

    let r = b.undo()
    check r.isOk
    check r.value.line == 1
    check r.value.column == 0

  test "undo transaction returns first change position":
    let b = newTextBuffer("test")
    discard b.beginTransaction("multi")
    discard b.insertText(BufferPosition(line: 0, column: 0), "A")
    discard b.insertText(BufferPosition(line: 0, column: 5), "B")
    discard b.commitTransaction()

    let r = b.undo()
    check r.isOk
    # Returns position of first change in transaction
    check r.value.line == 0
    check r.value.column == 0

suite "Buffer - joinLines Undo/Redo":
  test "undo joinLines":
    let b = newTextBuffer("line1\nline2\nline3")
    check b.len == 3

    discard b.joinLines(0)
    check b.len == 2
    check b.getLine(0) == "line1 line2"

    let r = b.undo()
    check r.isOk
    check b.len == 3
    check b.getLine(0) == "line1"
    check b.getLine(1) == "line2"

  test "redo joinLines":
    let b = newTextBuffer("line1\nline2")
    discard b.joinLines(0)
    discard b.undo()
    check b.len == 2

    let r = b.redo()
    check r.isOk
    check b.len == 1
    check b.getLine(0) == "line1 line2"

  test "joinLines at last line does nothing":
    let b = newTextBuffer("only line")
    let r = b.joinLines(0)
    check r.isErr
    # No undo entry should be created
    check b.undo().isErr
