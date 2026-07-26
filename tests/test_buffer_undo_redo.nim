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

import std/[unittest, strutils, options, deques]

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

  test "undo after multi-count redo unwinds most recent change first":
    let b = newTextBuffer("a")
    discard b.insertText(BufferPosition(line: 0, column: 1), "b")
    discard b.insertText(BufferPosition(line: 0, column: 2), "c")
    discard b.insertText(BufferPosition(line: 0, column: 3), "d")
    check b.getLine(0) == "abcd"

    discard b.undo(3)
    check b.getLine(0) == "a"

    let r = b.redo(3)
    check r.isOk
    check b.getLine(0) == "abcd"

    discard b.undo()
    check b.getLine(0) == "abc"
    discard b.undo()
    check b.getLine(0) == "ab"
    discard b.undo()
    check b.getLine(0) == "a"

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

suite "Buffer - withTransaction scope guard":
  test "normal completion commits and creates a single undo entry":
    let b = newTextBuffer("test")
    let r = withTransaction(b, "scoped commit"):
      discard b.insertText(BufferPosition(line: 0, column: 4), " 1")
      discard b.insertText(BufferPosition(line: 0, column: 6), " 2")
    check r.isOk
    check not b.inTransaction
    check b.getLine(0) == "test 1 2"

    let u = b.undo()
    check u.isOk
    check b.getLine(0) == "test"

  test "exception in body triggers rollback":
    let b = newTextBuffer("test")
    var raised = false
    try:
      discard withTransaction(b, "scoped rollback"):
        discard b.insertText(BufferPosition(line: 0, column: 4), " x")
        raise newException(ValueError, "boom")
    except ValueError:
      raised = true
    check raised
    check not b.inTransaction
    check b.getLine(0) == "test"
    check b.undo().isErr

  test "begin failure returns beginTransaction error, does not run body":
    let b = newTextBuffer("test")
    discard b.beginTransaction("outer")

    var bodyRan = false
    let r = withTransaction(b, "inner"):
      bodyRan = true
      discard b.insertText(BufferPosition(line: 0, column: 4), " y")
    check r.isErr
    check r.error.contains("Transaction already in progress")
    check not bodyRan
    check b.inTransaction

    discard b.rollbackTransaction()

  test "early return via helper proc rolls back":
    let b = newTextBuffer("test")

    proc runIt(b: TextBuffer): Result[(), string] =
      let r = withTransaction(b, "early return"):
        discard b.insertText(BufferPosition(line: 0, column: 4), " z")
        return err("early")
      r

    let outcome = runIt(b)
    check outcome.isErr
    check outcome.error == "early"
    check not b.inTransaction
    check b.getLine(0) == "test"
    check b.undo().isErr

  test "cursorPos overload records the anchor for undo":
    let b = newTextBuffer("hello")
    let anchor = BufferPosition(line: 0, column: 2)
    let r = withTransaction(b, "with anchor", some(anchor)):
      discard b.insertText(BufferPosition(line: 0, column: 5), "!!")
    check r.isOk
    check b.getLine(0) == "hello!!"

    let u = b.undo()
    check u.isOk
    check u.value == anchor

suite "Buffer - Transaction lastChangedLines":
  test "commitTransaction updates lastChangedLines to minimum line":
    # Regression test: commitTransaction must set lastChangedLines to the
    # minimum changed line so incremental highlighting re-parses correctly.
    let b = newTextBuffer("line0\nline1\nline2\nline3\nline4")
    check b.len == 5

    discard b.beginTransaction("multi-line delete")
    # Delete from multiple lines (simulating visual block delete)
    discard b.deleteRange(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 3)
    )
    discard b.deleteRange(
      BufferPosition(line: 1, column: 0), BufferPosition(line: 1, column: 3)
    )
    discard b.deleteRange(
      BufferPosition(line: 2, column: 0), BufferPosition(line: 2, column: 3)
    )
    discard b.commitTransaction()

    # lastChangedLines should be 0 (minimum), not 2 (last change)
    check b.lastChangedLines == 0

  test "commitTransaction with single change":
    let b = newTextBuffer("hello\nworld")

    discard b.beginTransaction("single")
    discard b.insertText(BufferPosition(line: 1, column: 5), "!")
    discard b.commitTransaction()

    check b.lastChangedLines == 1

  test "commitTransaction with empty transaction":
    let b = newTextBuffer("hello")
    let valBefore = b.lastChangedLines

    discard b.beginTransaction("empty")
    discard b.commitTransaction()

    # lastChangedLines should be unchanged
    check b.lastChangedLines == valBefore

  test "consecutive edits keep minimum lastChangedLines while pending":
    # Regression test: a second edit further down before updateHighlight
    # consumes the pending anchor must not move the anchor past the first
    # edit, or the first edit's line keeps a stale highlight.
    let b = newTextBuffer("l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10")

    discard b.insertText(BufferPosition(line: 2, column: 0), "x")
    discard b.insertText(BufferPosition(line: 10, column: 0), "y")

    check b.highlightNeedsUpdate
    check b.lastChangedLines == 2

  test "edit after consumed update starts a fresh anchor":
    let b = newTextBuffer("l0\nl1\nl2\nl3\nl4\nl5")

    discard b.insertText(BufferPosition(line: 1, column: 0), "x")
    check b.lastChangedLines == 1

    # Simulate updateHighlight consuming the pending update.
    b.highlightNeedsUpdate = false

    discard b.insertText(BufferPosition(line: 4, column: 0), "y")
    check b.lastChangedLines == 4

  test "commitTransaction keeps pending pre-transaction anchor":
    let b = newTextBuffer("l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9\nl10\nl11\nl12")

    discard b.insertText(BufferPosition(line: 2, column: 0), "x")
    discard b.beginTransaction("later lines")
    discard b.insertText(BufferPosition(line: 10, column: 0), "y")
    discard b.insertText(BufferPosition(line: 12, column: 0), "z")
    discard b.commitTransaction()

    check b.lastChangedLines == 2

  test "undo after consumed update re-anchors at the undone line":
    let b = newTextBuffer("l0\nl1\nl2\nl3\nl4\nl5")

    discard b.insertText(BufferPosition(line: 0, column: 0), "x")
    b.highlightNeedsUpdate = false
    b.lastChangedLines = 0

    discard b.insertText(BufferPosition(line: 4, column: 0), "y")
    b.highlightNeedsUpdate = false

    let r = b.undo()
    check r.isOk
    check b.highlightNeedsUpdate
    check b.lastChangedLines == 4

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

  test "isModified false after undo of multi-change transaction":
    # Regression: changeSeq is inc'd per inner change in pushUndoChange but
    # undo() used to dec only once, leaving isModified true after a single undo
    # of a multi-change transaction. Now BufferChange.startSeq is restored.
    let b = newTextBuffer("test")
    check not b.isModified

    discard b.beginTransaction("multi")
    discard b.insertText(BufferPosition(line: 0, column: 4), "a")
    discard b.insertText(BufferPosition(line: 0, column: 5), "b")
    discard b.insertText(BufferPosition(line: 0, column: 6), "c")
    discard b.insertText(BufferPosition(line: 0, column: 7), "d")
    discard b.insertText(BufferPosition(line: 0, column: 8), "e")
    discard b.commitTransaction()
    check b.getLine(0) == "testabcde"
    check b.isModified

    let r = b.undo()
    check r.isOk
    check b.getLine(0) == "test"
    check b.changeSeq == b.savedSeq
    check not b.isModified

  test "isModified true after redo of multi-change transaction":
    let b = newTextBuffer("test")
    discard b.beginTransaction("multi")
    discard b.insertText(BufferPosition(line: 0, column: 4), "a")
    discard b.insertText(BufferPosition(line: 0, column: 5), "b")
    discard b.commitTransaction()
    discard b.undo()
    check not b.isModified

    let r = b.redo()
    check r.isOk
    check b.getLine(0) == "testab"
    check b.isModified

  test "changeSeq restored exactly across undo/redo cycle":
    let b = newTextBuffer("test")
    discard b.beginTransaction("multi")
    discard b.insertText(BufferPosition(line: 0, column: 4), "a")
    discard b.insertText(BufferPosition(line: 0, column: 5), "b")
    discard b.insertText(BufferPosition(line: 0, column: 6), "c")
    discard b.commitTransaction()
    let postCommitSeq = b.changeSeq

    discard b.undo()
    check b.changeSeq == 0
    discard b.redo()
    check b.changeSeq == postCommitSeq

  test "isModified false after undo of multi-change transaction (PieceTable)":
    setConfiguredBackend(PieceTable)
    defer:
      setConfiguredBackend(GapBuffer)
    let b = newTextBuffer("test")
    discard b.beginTransaction("multi")
    discard b.insertText(BufferPosition(line: 0, column: 4), "a")
    discard b.insertText(BufferPosition(line: 0, column: 5), "b")
    discard b.insertText(BufferPosition(line: 0, column: 6), "c")
    discard b.commitTransaction()
    check b.isModified

    discard b.undo()
    check b.getLine(0) == "test"
    check b.changeSeq == b.savedSeq
    check not b.isModified

  test "isModified after save -> undo -> different edit (savedSeq collision)":
    # Regression: undo restores changeSeq, so a subsequent different edit can
    # re-hit the saved value and mask a dirty buffer (silent loss on :q).
    let b = newTextBuffer("")
    discard b.insertText(BufferPosition(line: 0, column: 0), "A")
    discard b.insertText(BufferPosition(line: 0, column: 1), "B")
    discard b.insertText(BufferPosition(line: 0, column: 2), "C")
    check b.getLine(0) == "ABC"
    b.markSaved()
    check not b.isModified

    discard b.undo()
    check b.getLine(0) == "AB"
    check b.isModified

    discard b.insertText(BufferPosition(line: 0, column: 2), "D")
    check b.getLine(0) == "ABD"
    check b.isModified

  test "isModified restored to false after undo/redo lands on saved state":
    let b = newTextBuffer("")
    discard b.insertText(BufferPosition(line: 0, column: 0), "A")
    discard b.insertText(BufferPosition(line: 0, column: 1), "B")
    b.markSaved()
    check not b.isModified

    discard b.undo()
    check b.isModified

    discard b.redo()
    check b.getLine(0) == "AB"
    check not b.isModified

  test "isModified after save -> undo -> different edit (PieceTable)":
    setConfiguredBackend(PieceTable)
    defer:
      setConfiguredBackend(GapBuffer)
    let b = newTextBuffer("")
    discard b.insertText(BufferPosition(line: 0, column: 0), "A")
    discard b.insertText(BufferPosition(line: 0, column: 1), "B")
    discard b.insertText(BufferPosition(line: 0, column: 2), "C")
    b.markSaved()
    check not b.isModified

    discard b.undo()
    check b.isModified

    discard b.insertText(BufferPosition(line: 0, column: 2), "D")
    check b.getLine(0) == "ABD"
    check b.isModified

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

  test "undo transaction with cursorPos returns saved cursor position":
    let b = newTextBuffer("hello world")
    let savedCursor = BufferPosition(line: 0, column: 3)
    discard b.beginTransaction("with cursor", cursorPos = some(savedCursor))
    # Insert at end of line (simulating 'o' command behavior)
    discard b.insertText(BufferPosition(line: 0, column: 11), "\n")
    discard b.commitTransaction()

    check b.len == 2

    let r = b.undo()
    check r.isOk
    check b.len == 1
    # Should return saved cursor position, not the insertion point (end of line)
    check r.value.line == 0
    check r.value.column == 3

  test "undo transaction without cursorPos falls back to first change":
    let b = newTextBuffer("hello")
    discard b.beginTransaction("no cursor")
    discard b.insertText(BufferPosition(line: 0, column: 2), "X")
    discard b.commitTransaction()

    let r = b.undo()
    check r.isOk
    # Falls back to first change position
    check r.value.line == 0
    check r.value.column == 2

  test "redo transaction with cursorPos returns saved cursor position":
    let b = newTextBuffer("hello world")
    let savedCursor = BufferPosition(line: 0, column: 5)
    discard b.beginTransaction("with cursor", cursorPos = some(savedCursor))
    discard b.insertText(BufferPosition(line: 0, column: 11), "!")
    discard b.commitTransaction()

    discard b.undo()
    let r = b.redo()
    check r.isOk
    # Redo should also use the saved cursor position
    check r.value.line == 0
    check r.value.column == 5

  test "undo transaction with cursorPos clamps to valid range after line deletion":
    let b = newTextBuffer("line1\nline2\nline3")
    # Save cursor on line 2, but the undo will remove lines
    let savedCursor = BufferPosition(line: 2, column: 3)
    discard b.beginTransaction("delete lines", cursorPos = some(savedCursor))
    discard b.deleteLine(2)
    discard b.deleteLine(1)
    discard b.commitTransaction()
    check b.len == 1

    # Undo restores lines
    let r = b.undo()
    check r.isOk
    check b.len == 3
    # cursorPos is returned as-is (clamping is done by the handler)
    check r.value.line == 2
    check r.value.column == 3

  test "undo multiple transactions returns each transaction cursorPos":
    let b = newTextBuffer("hello")
    # First transaction with cursorPos
    discard
      b.beginTransaction("tx1", cursorPos = some(BufferPosition(line: 0, column: 1)))
    discard b.insertText(BufferPosition(line: 0, column: 5), " world")
    discard b.commitTransaction()
    # Second transaction with cursorPos
    discard
      b.beginTransaction("tx2", cursorPos = some(BufferPosition(line: 0, column: 3)))
    discard b.insertText(BufferPosition(line: 0, column: 11), "!")
    discard b.commitTransaction()

    # Undo second transaction
    let r1 = b.undo()
    check r1.isOk
    check r1.value.column == 3

    # Undo first transaction
    let r2 = b.undo()
    check r2.isOk
    check r2.value.column == 1

  test "empty transaction with cursorPos does not push to undo stack":
    let b = newTextBuffer("hello")
    discard
      b.beginTransaction("empty", cursorPos = some(BufferPosition(line: 0, column: 2)))
    # No changes made
    discard b.commitTransaction()

    let r = b.undo()
    check r.isErr # Nothing to undo

  test "changeList records change position not cursorPos for transaction":
    let b = newTextBuffer("hello world")
    let savedCursor = BufferPosition(line: 0, column: 2)
    discard b.beginTransaction("with cursor", cursorPos = some(savedCursor))
    discard b.insertText(BufferPosition(line: 0, column: 11), "!")
    discard b.commitTransaction()

    # changeList should record the actual change position, not the saved cursor
    check b.changeList.len == 1
    check b.changeList[0].column == 11 # insert position, not savedCursor.column

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

suite "Buffer - Change List":
  test "changeList is empty on new buffer":
    let b = newTextBuffer("hello")
    check b.changeList.len == 0
    check b.changeListIndex == 0

  test "insertText records position in changeList":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.changeList.len == 1
    check b.changeList[0].line == 0
    check b.changeList[0].column == 5
    check b.changeListIndex == 0

  test "multiple changes grow changeList":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 0), "A")
    discard b.insertText(BufferPosition(line: 0, column: 3), "B")
    discard b.insertText(BufferPosition(line: 0, column: 6), "C")
    check b.changeList.len == 3
    check b.changeListIndex == 2

  test "deleteLine records position in changeList":
    let b = newTextBuffer("")
    discard b.insert(1, "line2")
    let initialLen = b.changeList.len
    discard b.deleteLine(1)
    check b.changeList.len == initialLen + 1
    check b.changeList[^1].line == 1

  test "transaction records single entry in changeList":
    let b = newTextBuffer("hello world")
    discard b.beginTransaction("test")
    discard b.insertText(BufferPosition(line: 0, column: 0), "A")
    discard b.insertText(BufferPosition(line: 0, column: 2), "B")
    discard b.commitTransaction()
    # Transaction should add one entry (not one per sub-change)
    check b.changeList.len == 1
    check b.changeList[0].line == 0
    check b.changeList[0].column == 0

  test "undo decrements changeListIndex":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    discard b.insertText(BufferPosition(line: 0, column: 0), "?")
    check b.changeListIndex == 1

    discard b.undo()
    check b.changeListIndex == 0
    check b.changeList.len == 2 # List itself doesn't shrink

  test "redo increments changeListIndex":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    discard b.insertText(BufferPosition(line: 0, column: 0), "?")
    discard b.undo()
    check b.changeListIndex == 0

    discard b.redo()
    check b.changeListIndex == 1

  test "changeListIndex does not go below 0 on undo":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.changeListIndex == 0

    discard b.undo()
    check b.changeListIndex == 0

  test "changeListIndex does not exceed len-1 on redo":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.changeListIndex == 0

    # Already at the end, redo should fail but index stays in bounds
    let r = b.redo()
    check r.isErr
    check b.changeListIndex == 0

  test "changeList limited to 100 entries":
    let b = newTextBuffer("hello")
    for i in 0 ..< 110:
      discard b.insertText(BufferPosition(line: 0, column: 0), "x")
    check b.changeList.len == 100
    check b.changeListIndex == 99

  test "new edit truncates changeList after undo":
    # Regression: pushUndoChange used to leave stale changeList entries past
    # changeListIndex, so g; / g, could navigate to positions whose undo
    # entries were already discarded.
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 0), "a") # idx 0
    discard b.insertText(BufferPosition(line: 0, column: 1), "b") # idx 1
    discard b.insertText(BufferPosition(line: 0, column: 2), "c") # idx 2
    check b.changeList.len == 3
    check b.changeListIndex == 2

    discard b.undo()
    discard b.undo()
    check b.changeListIndex == 0

    # New edit must drop the abandoned changeList tail (idx 1, 2).
    discard b.insertText(BufferPosition(line: 0, column: 0), "z")
    check b.changeList.len == 2
    check b.changeListIndex == 1
    check b.changeList[^1].column == 0

  test "transaction commit after undo also truncates changeList":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 0), "a")
    discard b.insertText(BufferPosition(line: 0, column: 1), "b")
    discard b.insertText(BufferPosition(line: 0, column: 2), "c")
    discard b.undo()
    discard b.undo()
    check b.changeListIndex == 0

    discard b.beginTransaction("late")
    discard b.insertText(BufferPosition(line: 0, column: 0), "z")
    discard b.insertText(BufferPosition(line: 0, column: 1), "y")
    discard b.commitTransaction()
    check b.changeList.len == 2
    check b.changeListIndex == 1

suite "Buffer - Pending Snapshot Cleanup":
  test "failed insertText does not leak pending modifiedLines snapshot":
    # If the snapshot is not discarded on failure, the next successful edit
    # attaches an outdated pre-mutation snapshot, and undo restores stale state.
    let b = newTextBuffer("hello")
    let badPos = BufferPosition(line: 99, column: 0)
    let bad = b.insertText(badPos, "x")
    check bad.isErr

    let good = b.insertText(BufferPosition(line: 0, column: 5), "!")
    check good.isOk
    check b.getLine(0) == "hello!"

    let u = b.undo()
    check u.isOk
    check b.getLine(0) == "hello"
    check not b.isModified

  test "replaceLine out-of-bounds returns err and keeps undo healthy":
    let b = newTextBuffer("hello")
    let bad = b.replaceLine(99, "world")
    check bad.isErr

    let good = b.replaceLine(0, "world")
    check good.isOk
    check b.getLine(0) == "world"

    discard b.undo()
    check b.getLine(0) == "hello"
    check not b.isModified

  test "PieceTable: failed edit does not leak pendingSnapshot":
    setConfiguredBackend(PieceTable)
    defer:
      setConfiguredBackend(GapBuffer)
    let b = newTextBuffer("hello")
    let bad = b.insertText(BufferPosition(line: 42, column: 0), "x")
    check bad.isErr

    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    discard b.undo()
    check b.getLine(0) == "hello"
    check not b.isModified

  test "PieceTable: zero-change transaction does not leak pendingSnapshot":
    # Regression: an empty transaction captured a pending snapshot that commit
    # never discarded, so a later edit reused that stale base and undo restored
    # the old fold/marker state.
    setConfiguredBackend(PieceTable)
    defer:
      setConfiguredBackend(GapBuffer)
    let b = newTextBuffer("aaa\nbbb\nccc\nddd")

    # Empty transaction: captures a pending snapshot, makes no change, commits.
    check b.beginTransaction("noop").isOk
    check b.commitTransaction().isOk

    # Fold and marker state established AFTER the (now-leaked) snapshot.
    check b.foldState.addFold(1, 2)
    b.setLineMarker(0, SessionModified)

    # A real edit must capture the current fold/marker state, not the stale one.
    discard b.insertText(BufferPosition(line: 0, column: 3), "X")
    check b.getLine(0) == "aaaX"

    # Undo restores the pre-edit text; folds and markers must come back intact.
    discard b.undo()
    check b.getLine(0) == "aaa"
    check b.foldState.folds.len == 1
    check b.foldState.folds[0].startLine == 1
    check b.foldState.folds[0].endLine == 2
    check b.getLineMarker(0) == some(SessionModified)

suite "Buffer - Transaction Partial Failure Recovery":
  # These tests verify that the roll-forward / roll-back paths added in
  # undo.nim for ckTransaction actually restore the buffer to the pre-call
  # state when an inner undoChange/redoChange fails partway. We can't easily
  # trigger an inner failure through the public API, so we hand-craft a
  # ckTransaction undo entry whose inner changes are designed to make exactly
  # one undoChange/redoChange raise (out-of-range line index → backend
  # delete/insert raises → caught by the try/except in undoChange/redoChange).

  test "undo rolls forward inner changes when a partway undoChange fails":
    let b = newTextBuffer("Xabc")
    let baselineSeq = b.changeSeq
    let preLine = b.getLine(0)

    # undo() walks transactionChanges in reverse:
    #   inner[1] (valid)  → undoChange removes the leading "X" → succeeds
    #   inner[0] (bad)    → undoChange calls backendDeleteLine(999) → raises
    # Roll-forward path should redoChange inner[1] (re-insert "X").
    let txn = BufferChange(
      startSeq: baselineSeq,
      endSeq: baselineSeq + 2,
      kind: ckTransaction,
      transactionChanges: @[
        BufferChange(
          startSeq: baselineSeq,
          endSeq: baselineSeq + 1,
          kind: ckInsertLine,
          insertLineIdx: 999,
          insertLineText: "x",
        ),
        BufferChange(
          startSeq: baselineSeq + 1,
          endSeq: baselineSeq + 2,
          kind: ckInsertText,
          insertPos: BufferPosition(line: 0, column: 0),
          insertText: "X",
        ),
      ],
      transactionDescription: "test",
    )
    b.undoStack.addLast(txn)
    let stackLenBefore = b.undoStack.len

    let r = b.undo()
    check r.isErr
    # Roll-forward restored "X" — buffer content is back to pre-undo state.
    check b.getLine(0) == preLine
    # undo() restored the failed entry to the stack so future undo() works.
    check b.undoStack.len == stackLenBefore

  test "redo rolls back inner changes when a partway redoChange fails":
    let b = newTextBuffer("abc")
    let baselineSeq = b.changeSeq
    let preLine = b.getLine(0)

    # redo() walks transactionChanges forward:
    #   inner[0] (valid) → redoChange inserts "X" at (0,0) → succeeds
    #   inner[1] (bad)   → redoChange calls backendInsertLine at idx 999 → raises
    # Roll-back path should undoChange inner[0] (remove the "X" just added).
    let txn = BufferChange(
      startSeq: baselineSeq,
      endSeq: baselineSeq + 2,
      kind: ckTransaction,
      transactionChanges: @[
        BufferChange(
          startSeq: baselineSeq,
          endSeq: baselineSeq + 1,
          kind: ckInsertText,
          insertPos: BufferPosition(line: 0, column: 0),
          insertText: "X",
        ),
        BufferChange(
          startSeq: baselineSeq + 1,
          endSeq: baselineSeq + 2,
          kind: ckInsertLine,
          insertLineIdx: 999,
          insertLineText: "x",
        ),
      ],
      transactionDescription: "test",
    )
    b.redoStack.addLast(txn)
    let stackLenBefore = b.redoStack.len

    let r = b.redo()
    check r.isErr
    # Roll-back removed the "X" that inner[0] had inserted.
    check b.getLine(0) == preLine
    check b.redoStack.len == stackLenBefore

suite "Buffer - Transaction Cursor Cache Staleness":
  test "redo of a transaction does not reuse a stale char->byte cache":
    # Default backend is GapBuffer, so a committed transaction is stored as a
    # ckTransaction with inner edits replayed under a constant changeSeq. Mixing
    # a text edit (populates the cursor cache for line 0) with a whole-line
    # replace (changes line 0's bytes WITHOUT touching the cache) leaves a cache
    # whose (line, changeSeq) still matches but whose bytePos is stale. A later
    # forward text edit on the same line would then scan from a mid-rune / past
    # the end byte offset on the multibyte original. Normal editing bumps
    # changeSeq per edit so it self-heals; only undo/redo holds changeSeq fixed.
    let b = newTextBuffer("あいうえおかきくけこ")
    discard b.beginTransaction("stale-cache")
    discard b.deleteChar(BufferPosition(line: 0, column: 7)) # populate cache @ ku
    discard b.replaceLine(0, "ABCDEFGHIJKLMN") # rewrite bytes, cache untouched
    discard b.deleteChar(BufferPosition(line: 0, column: 9)) # delete 'J'
    discard b.commitTransaction()
    # Forward editing self-heals via changeSeq bumps, so the commit is correct.
    check b.getLine(0) == "ABCDEFGHIKLMN"

    let u = b.undo()
    check u.isOk
    check b.getLine(0) == "あいうえおかきくけこ"

    # Redo replays the inner edits with changeSeq held constant: without cache
    # invalidation the final deleteChar reads a stale byte offset and corrupts
    # the line (or fails and rolls the whole redo back).
    let r = b.redo()
    check r.isOk
    check b.getLine(0) == "ABCDEFGHIKLMN"

suite "Buffer - readOnly guard on undo/redo":
  # buffer/edit rejects mutations on readOnly buffers, but undo()/redo() used to
  # replay history without checking the flag — so a buffer set readOnly AFTER
  # edits were recorded could still be mutated through the history stacks. The
  # guards below complete "readOnly rejects on every mutation path".
  test "undo on a readOnly buffer returns err and leaves content unchanged":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.getLine(0) == "hello!"
    let undoLenBefore = b.undoStack.len
    let redoLenBefore = b.redoStack.len

    b.readOnly = true
    let r = b.undo()
    check r.isErr
    check r.error == "Buffer is read-only"
    check b.getLine(0) == "hello!"
    check b.undoStack.len == undoLenBefore
    check b.redoStack.len == redoLenBefore

  test "redo on a readOnly buffer returns err and leaves content unchanged":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    let u = b.undo()
    check u.isOk
    check b.getLine(0) == "hello"
    let undoLenBefore = b.undoStack.len
    let redoLenBefore = b.redoStack.len

    b.readOnly = true
    let r = b.redo()
    check r.isErr
    check r.error == "Buffer is read-only"
    check b.getLine(0) == "hello"
    check b.undoStack.len == undoLenBefore
    check b.redoStack.len == redoLenBefore

  test "undo err on readOnly precedes the 'nothing to undo' err":
    # Guard ordering matters: readOnly must reject even before we look at the
    # stacks, so a fresh readOnly buffer reports the right reason (not
    # "Nothing to undo").
    let b = newTextBuffer("hello")
    b.readOnly = true
    let ru = b.undo()
    check ru.isErr
    check ru.error == "Buffer is read-only"
    let rr = b.redo()
    check rr.isErr
    check rr.error == "Buffer is read-only"
