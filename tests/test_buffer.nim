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

import std/[unittest, os, strutils, times, options]
import pkg/[results, celina]
import ../src/moepkg/buffer
import ../src/moepkg/highlight

suite "Buffer - Trailing Empty Lines":
  test "Insert text with trailing empty lines preserves them":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello\n\n")

    check buf.len == 3
    check buf[0] == "Hello"
    check buf[1] == ""
    check buf[2] == ""

    let text = buf.getTextString()
    check text == "Hello\n\n\n" # Last empty line outputs as newline

  test "Manual line splits create empty lines":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello")
    discard buf.splitLine(BufferPosition(line: 0, column: 5)) # Enter after Hello
    discard buf.splitLine(BufferPosition(line: 1, column: 0)) # Enter on empty line

    check buf.len == 3
    check buf[0] == "Hello"
    check buf[1] == ""
    check buf[2] == ""

  test "Save and load preserves trailing empty lines":
    let testFile = "/tmp/moe_test_trailing.txt"

    # Create buffer with trailing empty lines
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "Hello\n\n")

    # Save
    let saveResult = buf1.saveFile(testFile)
    check saveResult.get() == ()

    # Check file content
    let savedContent = readFile(testFile)
    check savedContent == "Hello\n\n\n" # Trailing empty lines preserved + endOfLine

    # Load back
    let buf2 = newTextBuffer()
    let loadResult = buf2.loadFile(testFile)
    check loadResult.get() == ()

    # Verify empty lines are preserved
    check buf2.len == 3
    check buf2[0] == "Hello"
    check buf2[1] == ""
    check buf2[2] == ""

    removeFile(testFile)

  test "endOfLine flag controls trailing newline on save":
    let testFile = "/tmp/moe_test_endofline.txt"

    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "Hello\n\n")

    # With endOfLine=true (default)
    check buf.endOfLine == true
    discard buf.saveFile(testFile)
    var content = readFile(testFile)
    check content.endsWith("\n")

    # With endOfLine=false - removes ONE trailing newline
    buf.endOfLine = false
    discard buf.saveFile(testFile)
    content = readFile(testFile)
    # getTextString() gives "Hello\n\n\n", removing one \n gives "Hello\n\n"
    # which still ends with \n (from the second empty line)
    check content == "Hello\n\n"
    check content.endsWith("\n") # Still ends with \n from empty line

    removeFile(testFile)

suite "Buffer - Basic Operations":
  test "newTextBuffer creates empty buffer":
    let buf = newTextBuffer()
    check buf.len == 1
    check buf[0] == ""

  test "newTextBuffer with content":
    let buf = newTextBuffer("Hello\nWorld")
    check buf.len == 2
    check buf[0] == "Hello"
    check buf[1] == "World"

  test "getLine and [] operator":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    check buf.getLine(0) == "Line1"
    check buf[1] == "Line2"
    check buf[2] == "Line3"

  test "getLineLen returns character count":
    let buf = newTextBuffer("Hello\nあいう")
    check buf.getLineLen(0) == 5
    check buf.getLineLen(1) == 3 # 3 Unicode characters

  test "charLen returns character count":
    check charLen("Hello") == 5
    check charLen("あいう") == 3
    check charLen("") == 0

  test "getTextString":
    let buf = newTextBuffer("Hello\nWorld")
    # Verify line structure is correct
    check buf.len == 2
    check buf[0] == "Hello"
    check buf[1] == "World"
    # getTextString includes trailing newline from GapBuffer
    let text = buf.getTextString()
    check "Hello" in text
    check "World" in text

  test "[][] operator for character access":
    let buf = newTextBuffer("ABC")
    check buf[0][0] == 'A'
    check buf[0][1] == 'B'
    check buf[0][2] == 'C'

suite "Buffer - Editing Operations":
  test "insertText single character":
    let buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")
    check buf[0] == "Hello!"

  test "insertText in middle":
    let buf = newTextBuffer("Hllo")
    discard buf.insertText(BufferPosition(line: 0, column: 1), "e")
    check buf[0] == "Hello"

  test "insertText with newline":
    let buf = newTextBuffer("HelloWorld")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\n")
    check buf.len == 2
    check buf[0] == "Hello"
    check buf[1] == "World"

  test "insertText error on invalid position":
    let buf = newTextBuffer("Hello")
    let result = buf.insertText(BufferPosition(line: 5, column: 0), "X")
    check result.isErr

  test "deleteChar single character":
    let buf = newTextBuffer("Hello")
    discard buf.deleteChar(BufferPosition(line: 0, column: 0))
    check buf[0] == "ello"

  test "deleteChar in middle":
    let buf = newTextBuffer("Hello")
    discard buf.deleteChar(BufferPosition(line: 0, column: 2))
    check buf[0] == "Helo"

  test "deleteChar error on invalid position":
    let buf = newTextBuffer("Hello")
    let result = buf.deleteChar(BufferPosition(line: 0, column: 10))
    check result.isErr

  test "insert new line":
    let buf = newTextBuffer("Line1\nLine3")
    discard buf.insert(1, "Line2")
    check buf.len == 3
    check buf[0] == "Line1"
    check buf[1] == "Line2"
    check buf[2] == "Line3"

  test "insert line at beginning":
    let buf = newTextBuffer("Line2")
    discard buf.insert(0, "Line1")
    check buf.len == 2
    check buf[0] == "Line1"
    check buf[1] == "Line2"

  test "insert line at end":
    let buf = newTextBuffer("Line1")
    discard buf.insert(1, "Line2")
    check buf.len == 2
    check buf[0] == "Line1"
    check buf[1] == "Line2"

  test "deleteLine":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    discard buf.deleteLine(1)
    check buf.len == 2
    check buf[0] == "Line1"
    check buf[1] == "Line3"

  test "deleteLine error on invalid index":
    let buf = newTextBuffer("Line1")
    let result = buf.deleteLine(5)
    check result.isErr

  test "getTextInRange single line":
    let buf = newTextBuffer("Hello World")
    let text = buf.getTextInRange(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 4)
    )
    check text == "Hello"

  test "getTextInRange multi line":
    let buf = newTextBuffer("Hello\nWorld\nTest")
    let text = buf.getTextInRange(
      BufferPosition(line: 0, column: 3), BufferPosition(line: 2, column: 2)
    )
    check text == "lo\nWorld\nTes"

  test "deleteRange single line":
    let buf = newTextBuffer("Hello World")
    discard buf.deleteRange(
      BufferPosition(line: 0, column: 5), BufferPosition(line: 0, column: 10)
    )
    check buf[0] == "Hello"

  test "deleteRange multi line":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    # Delete from "e1\nLin" (column 3 of line 0 to column 2 of line 1)
    # Result: "Lin" + "e2" = "Line2" on line 0, "Line3" on line 1
    discard buf.deleteRange(
      BufferPosition(line: 0, column: 3), BufferPosition(line: 1, column: 2)
    )
    check buf.len == 2
    check buf[0] == "Line2" # "Lin" (0:0-2) + "e2" (1:3-4)
    check buf[1] == "Line3"

  test "splitLine":
    let buf = newTextBuffer("HelloWorld")
    discard buf.splitLine(BufferPosition(line: 0, column: 5))
    check buf.len == 2
    check buf[0] == "Hello"
    check buf[1] == "World"

  test "joinLines":
    let buf = newTextBuffer("Hello\nWorld")
    discard buf.joinLines(0)
    check buf.len == 1
    check buf[0] == "Hello World"

  test "joinLines multiple":
    let buf = newTextBuffer("A\nB\nC\nD")
    discard buf.joinLines(0, 2)
    check buf.len == 2
    check buf[0] == "A B C"
    check buf[1] == "D"

suite "Buffer - Undo/Redo":
  test "undo insertText":
    let buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), " World")
    check buf[0] == "Hello World"

    let undoResult = buf.undo()
    check undoResult.isOk
    check buf[0] == "Hello"

  test "redo insertText":
    let buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), " World")
    discard buf.undo()
    check buf[0] == "Hello"

    let redoResult = buf.redo()
    check redoResult.isOk
    check buf[0] == "Hello World"

  test "undo deleteChar":
    let buf = newTextBuffer("Hello")
    discard buf.deleteChar(BufferPosition(line: 0, column: 4))
    check buf[0] == "Hell"

    discard buf.undo()
    check buf[0] == "Hello"

  test "undo deleteLine":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    discard buf.deleteLine(1)
    check buf.len == 2

    discard buf.undo()
    check buf.len == 3
    check buf[1] == "Line2"

  test "undo nothing to undo":
    let buf = newTextBuffer("Hello")
    let result = buf.undo()
    check result.isErr

  test "redo nothing to redo":
    let buf = newTextBuffer("Hello")
    let result = buf.redo()
    check result.isErr

  test "redo cleared after new change":
    let buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")
    discard buf.undo()

    # Make a new change
    discard buf.insertText(BufferPosition(line: 0, column: 5), "?")

    # Redo should fail
    let result = buf.redo()
    check result.isErr

suite "Buffer - Transaction":
  test "transaction groups changes for undo":
    let buf = newTextBuffer("Hello")

    discard buf.beginTransaction("test transaction")
    discard buf.insertText(BufferPosition(line: 0, column: 5), " ")
    discard buf.insertText(BufferPosition(line: 0, column: 6), "World")
    discard buf.commitTransaction()

    check buf[0] == "Hello World"

    # Single undo should revert the entire transaction
    discard buf.undo()
    check buf[0] == "Hello"

  test "rollback transaction":
    let buf = newTextBuffer("Hello")

    discard buf.beginTransaction("test")
    discard buf.insertText(BufferPosition(line: 0, column: 5), " World")
    check buf[0] == "Hello World"

    discard buf.rollbackTransaction()
    check buf[0] == "Hello"

  test "nested transaction error":
    let buf = newTextBuffer("Hello")
    discard buf.beginTransaction("outer")
    let result = buf.beginTransaction("inner")
    check result.isErr
    discard buf.commitTransaction()

suite "Buffer - isModified":
  test "new buffer is not modified":
    let buf = newTextBuffer("Hello")
    check buf.isModified == false

  test "buffer modified after edit":
    let buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")
    check buf.isModified == true

  test "buffer not modified after undo":
    let buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")
    discard buf.undo()
    check buf.isModified == false

  test "buffer modified after redo":
    let buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")
    discard buf.undo()
    discard buf.redo()
    check buf.isModified == true

suite "Buffer - Search":
  test "findNext basic":
    let buf = newTextBuffer("Hello World Hello")
    let pos = buf.findNext("Hello", BufferPosition(line: 0, column: -1))
    check pos.isSome
    check pos.get.line == 0
    check pos.get.column == 0

  test "findNext from position":
    let buf = newTextBuffer("Hello World Hello")
    let pos = buf.findNext("Hello", BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.line == 0
    check pos.get.column == 12

  test "findNext wraps around":
    let buf = newTextBuffer("Hello World")
    let pos = buf.findNext("Hello", BufferPosition(line: 0, column: 5))
    check pos.isSome
    check pos.get.line == 0
    check pos.get.column == 0

  test "findNext multiline":
    let buf = newTextBuffer("Line1\nHello\nLine3")
    let pos = buf.findNext("Hello", BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.line == 1
    check pos.get.column == 0

  test "findNext not found":
    let buf = newTextBuffer("Hello World")
    let pos = buf.findNext("NotFound", BufferPosition(line: 0, column: 0))
    check pos.isNone

  test "findNext case insensitive":
    let buf = newTextBuffer("Hello World")
    let pos =
      buf.findNext("hello", BufferPosition(line: 0, column: -1), ignorecase = true)
    check pos.isSome
    check pos.get.column == 0

  test "findPrev basic":
    let buf = newTextBuffer("Hello World Hello")
    let pos = buf.findPrev("Hello", BufferPosition(line: 0, column: 17))
    check pos.isSome
    check pos.get.column == 12

  test "findPrev wraps around":
    let buf = newTextBuffer("Hello World")
    let pos = buf.findPrev("World", BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.column == 6

  test "isPositionInSearchMatch":
    let buf = newTextBuffer("Hello World")
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 0), "Hello") ==
      true
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 2), "Hello") ==
      true
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 5), "Hello") ==
      false
    check buf.isPositionInSearchMatch(BufferPosition(line: 0, column: 6), "World") ==
      true

suite "Buffer - Word Detection":
  test "getWordAtPosition":
    let buf = newTextBuffer("Hello World")
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 0)) == "Hello"
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 2)) == "Hello"
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 6)) == "World"

  test "getWordAtPosition on non-word character":
    let buf = newTextBuffer("Hello World")
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 5)) == ""

  test "isPositionInWord":
    let buf = newTextBuffer("Hello World Hello")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "Hello") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 6), "World") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 12), "Hello") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "World") == false

  test "isPositionInWord - empty word":
    let buf = newTextBuffer("Hello")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "") == false

  test "isPositionInWord - empty line":
    let buf = newTextBuffer("")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "Hello") == false

  test "isPositionInWord - invalid line":
    let buf = newTextBuffer("Hello")
    check buf.isPositionInWord(BufferPosition(line: -1, column: 0), "Hello") == false
    check buf.isPositionInWord(BufferPosition(line: 1, column: 0), "Hello") == false

  test "isPositionInWord - invalid column":
    let buf = newTextBuffer("Hello")
    check buf.isPositionInWord(BufferPosition(line: 0, column: -1), "Hello") == false
    check buf.isPositionInWord(BufferPosition(line: 0, column: 5), "Hello") == false

  test "isPositionInWord - position on non-word character":
    let buf = newTextBuffer("Hello World")
    # Space between words
    check buf.isPositionInWord(BufferPosition(line: 0, column: 5), "Hello") == false

  test "isPositionInWord - punctuation as separator":
    let buf = newTextBuffer("foo.bar(baz)")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "foo") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 2), "foo") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 3), "foo") == false # '.'
    check buf.isPositionInWord(BufferPosition(line: 0, column: 4), "bar") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 7), "bar") == false # '('
    check buf.isPositionInWord(BufferPosition(line: 0, column: 8), "baz") == true

  test "isPositionInWord - underscore in word":
    let buf = newTextBuffer("foo_bar baz")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "foo_bar") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 3), "foo_bar") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 6), "foo_bar") == true
    # Partial match should fail
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "foo") == false

  test "isPositionInWord - digits in word":
    let buf = newTextBuffer("var123 test")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "var123") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 5), "var123") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "var") == false

  test "isPositionInWord - word at line boundaries":
    let buf = newTextBuffer("Hello")
    # First character
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "Hello") == true
    # Last character
    check buf.isPositionInWord(BufferPosition(line: 0, column: 4), "Hello") == true

  test "isPositionInWord - middle of word":
    let buf = newTextBuffer("Hello World")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 1), "Hello") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 3), "Hello") == true

  test "isPositionInWord - multiline buffer":
    let buf = newTextBuffer("Hello\nWorld\nHello")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "Hello") == true
    check buf.isPositionInWord(BufferPosition(line: 1, column: 0), "World") == true
    check buf.isPositionInWord(BufferPosition(line: 2, column: 0), "Hello") == true
    check buf.isPositionInWord(BufferPosition(line: 1, column: 0), "Hello") == false

  test "isPositionInWord - single character word":
    let buf = newTextBuffer("a b c")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "a") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 2), "b") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "b") == false

  test "isPositionInWord - Unicode (CJK not word chars)":
    let buf = newTextBuffer("hello世界world")
    # CJK characters are not word characters (isWordChar checks alphanumeric + underscore)
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "hello") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 5), "hello") == false
      # '世'
    check buf.isPositionInWord(BufferPosition(line: 0, column: 7), "world") == true

  test "isPositionInWord - tabs and special whitespace":
    let buf = newTextBuffer("hello\tworld")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "hello") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 5), "hello") == false
      # tab
    check buf.isPositionInWord(BufferPosition(line: 0, column: 6), "world") == true

  test "isPositionInWord - case sensitive":
    let buf = newTextBuffer("Hello hello")
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "Hello") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "hello") == false
    check buf.isPositionInWord(BufferPosition(line: 0, column: 6), "hello") == true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 6), "Hello") == false

suite "Buffer - Matching Paren":
  test "findMatchingParenPosition forward":
    let buf = newTextBuffer("(hello)")
    let pos = buf.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.column == 6

  test "findMatchingParenPosition backward":
    let buf = newTextBuffer("(hello)")
    let pos = buf.findMatchingParenPosition(BufferPosition(line: 0, column: 6))
    check pos.isSome
    check pos.get.column == 0

  test "findMatchingParenPosition nested":
    let buf = newTextBuffer("((inner))")
    let pos = buf.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.column == 8

  test "findMatchingParenPosition multiline":
    let buf = newTextBuffer("(\n  content\n)")
    let pos = buf.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.line == 2
    check pos.get.column == 0

  test "findMatchingParenPosition brackets":
    let buf = newTextBuffer("[a, b, c]")
    let pos = buf.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.column == 8

  test "findMatchingParenPosition braces":
    let buf = newTextBuffer("{key: value}")
    let pos = buf.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.column == 11

  test "findMatchingParenPosition not on bracket":
    let buf = newTextBuffer("hello")
    let pos = buf.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
    check pos.isNone

  test "findMatchingParenPosition unmatched":
    let buf = newTextBuffer("(hello")
    let pos = buf.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
    check pos.isNone

suite "Buffer - Folding":
  test "addFold and getFoldAt":
    let buf = newTextBuffer("Line1\nLine2\nLine3\nLine4\nLine5")
    check buf.foldState.addFold(1, 3) == true

    let fold = buf.foldState.getFoldAt(2)
    check fold.isSome
    check fold.get[].startLine == 1
    check fold.get[].endLine == 3
    check fold.get[].collapsed == true

  test "addFold overlapping fails":
    let buf = newTextBuffer("Line1\nLine2\nLine3\nLine4\nLine5")
    check buf.foldState.addFold(1, 3) == true
    check buf.foldState.addFold(2, 4) == false # Overlaps

  test "openFold and closeFold":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    discard buf.foldState.addFold(0, 2)

    check buf.foldState.folds[0].collapsed == true
    check buf.foldState.openFold(1) == true
    check buf.foldState.folds[0].collapsed == false
    check buf.foldState.closeFold(1) == true
    check buf.foldState.folds[0].collapsed == true

  test "toggleFold":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    discard buf.foldState.addFold(0, 2)

    check buf.foldState.folds[0].collapsed == true
    check buf.foldState.toggleFold(1) == true
    check buf.foldState.folds[0].collapsed == false
    check buf.foldState.toggleFold(1) == true
    check buf.foldState.folds[0].collapsed == true

  test "deleteFold":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    discard buf.foldState.addFold(0, 2)

    check buf.foldState.folds.len == 1
    check buf.foldState.deleteFold(1) == true
    check buf.foldState.folds.len == 0

  test "isLineInCollapsedFold":
    let buf = newTextBuffer("Line1\nLine2\nLine3\nLine4")
    discard buf.foldState.addFold(1, 2)

    check buf.foldState.isLineInCollapsedFold(0) == false
    check buf.foldState.isLineInCollapsedFold(1) == false # Start line
    check buf.foldState.isLineInCollapsedFold(2) == true # Inside fold
    check buf.foldState.isLineInCollapsedFold(3) == false

  test "deleteAllFolds":
    let buf = newTextBuffer("Line1\nLine2\nLine3\nLine4\nLine5")
    discard buf.foldState.addFold(0, 1)
    discard buf.foldState.addFold(3, 4)

    check buf.foldState.folds.len == 2
    buf.foldState.deleteAllFolds()
    check buf.foldState.folds.len == 0

  test "formatFoldText":
    let buf = newTextBuffer("func foo() {\n  body\n}")
    discard buf.foldState.addFold(0, 2)
    let text = buf.formatFoldText(buf.foldState.folds[0])
    check text.contains("3 lines")
    check text.contains("func foo()")

suite "Buffer - Sidebar Markers":
  test "setLineMarker and getLineMarker":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    buf.setLineMarker(1, SidebarItemKind.GitAdded)

    check buf.getLineMarker(0).isNone
    check buf.getLineMarker(1).isSome
    check buf.getLineMarker(1).get == SidebarItemKind.GitAdded
    check buf.getLineMarker(2).isNone

  test "clearLineMarker":
    let buf = newTextBuffer("Line1\nLine2")
    buf.setLineMarker(0, SidebarItemKind.GitChanged)
    buf.clearLineMarker(0)
    check buf.getLineMarker(0).isNone

  test "clearAllMarkers":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    buf.setLineMarker(0, SidebarItemKind.GitAdded)
    buf.setLineMarker(1, SidebarItemKind.GitChanged)
    buf.setLineMarker(2, SidebarItemKind.GitDeleted)

    buf.clearAllMarkers()
    check buf.getLineMarker(0).isNone
    check buf.getLineMarker(1).isNone
    check buf.getLineMarker(2).isNone

  test "marker out of bounds":
    let buf = newTextBuffer("Line1")
    check buf.getLineMarker(10).isNone

suite "Buffer - Unicode":
  test "insertText Unicode":
    let buf = newTextBuffer("こんにちは")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "世界")
    check buf[0] == "こんにちは世界"

  test "deleteChar Unicode":
    let buf = newTextBuffer("あいうえお")
    discard buf.deleteChar(BufferPosition(line: 0, column: 2))
    check buf[0] == "あいえお"

  test "getWordAtPosition Unicode":
    let buf = newTextBuffer("hello世界test")
    # Note: Japanese characters are not word characters by default
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 0)) == "hello"
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 7)) == "test"

  test "findNext Unicode":
    let buf = newTextBuffer("日本語テスト日本語")
    # String: 日(0)本(1)語(2)テ(3)ス(4)ト(5)日(6)本(7)語(8)
    # findNext from column 0 finds second occurrence at column 6
    let pos = buf.findNext("日本語", BufferPosition(line: 0, column: 0))
    check pos.isSome
    check pos.get.column == 6

suite "Buffer - File Operations":
  test "loadFile non-existent creates empty buffer":
    let buf = newTextBuffer()
    let testFile = "/tmp/moe_test_nonexistent_" & $epochTime() & ".txt"
    let result = buf.loadFile(testFile)
    check result.isOk
    check buf.len == 1
    check buf[0] == ""

  test "saveFile and loadFile roundtrip":
    let testFile = "/tmp/moe_test_roundtrip.txt"

    let buf1 = newTextBuffer()
    discard buf1.insertText(
      BufferPosition(line: 0, column: 0), "Test content\nWith multiple lines"
    )
    discard buf1.saveFile(testFile)

    let buf2 = newTextBuffer()
    discard buf2.loadFile(testFile)

    check buf2.len == 2
    check buf2[0] == "Test content"
    check buf2[1] == "With multiple lines"

    removeFile(testFile)

  test "isModified false after save":
    let testFile = "/tmp/moe_test_modified.txt"
    let buf = newTextBuffer("Hello")
    discard buf.insertText(BufferPosition(line: 0, column: 5), " World")
    check buf.isModified == true

    discard buf.saveFile(testFile)
    check buf.isModified == false

    removeFile(testFile)

suite "Buffer - Performance Stats":
  test "estimateMemoryUsage":
    let buf = newTextBuffer("Hello World")
    let mem = buf.estimateMemoryUsage()
    check mem > 0

  test "getPerformanceStats":
    let buf = newTextBuffer("Line1\nLine2")
    let stats = buf.getPerformanceStats()
    check stats.backend == "GapBuffer"
    check stats.memoryUsage > 0
    check stats.length == 2

suite "Buffer - isExternallyModified":
  test "Returns false when buffer has no file path":
    let buf = newTextBuffer("hello")
    check not buf.isExternallyModified()

  test "Returns false when file does not exist":
    let buf = newTextBuffer("hello", some("/tmp/nonexistent_test_file_12345"))
    buf.lastFileModTime = some(getTime())
    check not buf.isExternallyModified()

  test "Returns false when lastFileModTime is none":
    let path = "/tmp/test_isExternallyModified_none.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer("hello", some(path))
    buf.lastFileModTime = none(Time)
    check not buf.isExternallyModified()

  test "Returns false when file has not been modified":
    let path = "/tmp/test_isExternallyModified_unmodified.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check not buf.isExternallyModified()

  test "Returns true when file is modified externally":
    let path = "/tmp/test_isExternallyModified_modified.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)

    # Set lastFileModTime to the past so any write will be newer
    buf.lastFileModTime = some(getTime() - initDuration(seconds = 2))
    writeFile(path, "modified")

    check buf.isExternallyModified()

suite "Buffer - reloadFile":
  test "Returns error when buffer has no file path":
    let buf = newTextBuffer("hello")
    let res = buf.reloadFile()
    check res.isErr

  test "Reloads file content from disk":
    let path = "/tmp/test_reloadFile.txt"
    writeFile(path, "original")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf[0] == "original"

    writeFile(path, "updated")
    let res = buf.reloadFile()
    check res.isOk
    check buf[0] == "updated"

  test "Updates lastFileModTime after reload":
    let path = "/tmp/test_reloadFile_modtime.txt"
    writeFile(path, "v1")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)

    # Force old timestamp
    buf.lastFileModTime = some(getTime() - initDuration(seconds = 2))
    writeFile(path, "v2")

    check buf.isExternallyModified()
    discard buf.reloadFile()
    check not buf.isExternallyModified()

suite "Buffer - externalModWarned":
  test "externalModWarned does not affect isExternallyModified":
    let path = "/tmp/test_externalModWarned_doesnt_mask.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)

    # Simulate external modification
    buf.lastFileModTime = some(getTime() - initDuration(seconds = 2))
    writeFile(path, "modified")

    buf.externalModWarned = true
    # isExternallyModified should still return true even when warned
    check buf.isExternallyModified()

  test "loadFile resets externalModWarned":
    let path = "/tmp/test_externalModWarned_load.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    buf.externalModWarned = true
    discard buf.loadFile(path)
    check buf.externalModWarned == false

  test "saveFile resets externalModWarned":
    let path = "/tmp/test_externalModWarned_save.txt"
    defer:
      removeFile(path)

    let buf = newTextBuffer("hello")
    buf.externalModWarned = true
    discard buf.saveFile(path)
    check buf.externalModWarned == false

suite "Git Change Navigation - findNextGitChange":
  test "No markers at all":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1\nline2\nline3\n")
    check buf.findNextGitChange(0).isNone

  test "Find next change from unmarked line":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne\n")
    buf.setLineMarker(2, GitAdded)
    buf.setLineMarker(3, GitAdded)
    let result = buf.findNextGitChange(0)
    check result.isSome
    check result.get == 2

  test "Skip current change block":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne\nf\ng\n")
    buf.setLineMarker(1, GitChanged)
    buf.setLineMarker(2, GitChanged)
    buf.setLineMarker(5, GitAdded)
    let result = buf.findNextGitChange(1)
    check result.isSome
    check result.get == 5

  test "No more changes after current block":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\n")
    buf.setLineMarker(1, GitAdded)
    buf.setLineMarker(2, GitAdded)
    check buf.findNextGitChange(1).isNone

  test "Mixed marker types":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne\n")
    buf.setLineMarker(0, GitDeleted)
    buf.setLineMarker(3, GitChangedAndDeleted)
    let result = buf.findNextGitChange(0)
    check result.isSome
    check result.get == 3

  test "Non-git markers are ignored":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\n")
    buf.setLineMarker(1, SyntaxError)
    buf.setLineMarker(3, GitAdded)
    let result = buf.findNextGitChange(0)
    check result.isSome
    check result.get == 3

suite "Git Change Navigation - findPrevGitChange":
  test "No markers at all":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "line1\nline2\nline3\n")
    check buf.findPrevGitChange(2).isNone

  test "Find previous change block":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne\n")
    buf.setLineMarker(1, GitAdded)
    buf.setLineMarker(2, GitAdded)
    let result = buf.findPrevGitChange(4)
    check result.isSome
    check result.get == 1

  test "Jump to start of previous block":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne\nf\ng\n")
    buf.setLineMarker(1, GitChanged)
    buf.setLineMarker(2, GitChanged)
    buf.setLineMarker(3, GitChanged)
    buf.setLineMarker(5, GitAdded)
    let result = buf.findPrevGitChange(5)
    check result.isSome
    check result.get == 1

  test "No previous change":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\n")
    buf.setLineMarker(2, GitAdded)
    check buf.findPrevGitChange(2).isNone

  test "Skip current block backwards":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\ne\nf\n")
    buf.setLineMarker(0, GitDeleted)
    buf.setLineMarker(3, GitChanged)
    buf.setLineMarker(4, GitChanged)
    let result = buf.findPrevGitChange(3)
    check result.isSome
    check result.get == 0

  test "From line 0 returns none":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\n")
    buf.setLineMarker(0, GitAdded)
    check buf.findPrevGitChange(0).isNone

suite "Buffer - Bookmarks - toggleBookmark":
  test "Toggle on empty buffer adds bookmark":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    buf.toggleBookmark(1)
    check buf.bookmarks == @[1]

  test "Toggle same line twice removes bookmark":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    buf.toggleBookmark(1)
    buf.toggleBookmark(1)
    check buf.bookmarks.len == 0

  test "Multiple bookmarks are sorted":
    let buf = newTextBuffer("a\nb\nc\nd\ne")
    buf.toggleBookmark(3)
    buf.toggleBookmark(0)
    buf.toggleBookmark(4)
    buf.toggleBookmark(1)
    check buf.bookmarks == @[0, 1, 3, 4]

  test "Toggle middle bookmark removes only that one":
    let buf = newTextBuffer("a\nb\nc\nd\ne")
    buf.toggleBookmark(0)
    buf.toggleBookmark(2)
    buf.toggleBookmark(4)
    buf.toggleBookmark(2)
    check buf.bookmarks == @[0, 4]

suite "Buffer - Bookmarks - hasBookmark":
  test "hasBookmark returns true for bookmarked line":
    let buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(1)
    check buf.hasBookmark(1) == true

  test "hasBookmark returns false for non-bookmarked line":
    let buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(1)
    check buf.hasBookmark(0) == false
    check buf.hasBookmark(2) == false

  test "hasBookmark returns false on empty bookmarks":
    let buf = newTextBuffer("a\nb\nc")
    check buf.hasBookmark(0) == false

suite "Buffer - Bookmarks - clearBookmarks":
  test "clearBookmarks removes all bookmarks":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(0)
    buf.toggleBookmark(2)
    buf.toggleBookmark(3)
    buf.clearBookmarks()
    check buf.bookmarks.len == 0

  test "clearBookmarks on empty is no-op":
    let buf = newTextBuffer("a\nb")
    buf.clearBookmarks()
    check buf.bookmarks.len == 0

suite "Buffer - Bookmarks - findNextBookmark":
  test "Find next bookmark after current line":
    let buf = newTextBuffer("a\nb\nc\nd\ne")
    buf.toggleBookmark(1)
    buf.toggleBookmark(3)
    check buf.findNextBookmark(0) == some(1)
    check buf.findNextBookmark(1) == some(3)
    check buf.findNextBookmark(2) == some(3)

  test "Wraps around to first bookmark":
    let buf = newTextBuffer("a\nb\nc\nd\ne")
    buf.toggleBookmark(1)
    buf.toggleBookmark(3)
    check buf.findNextBookmark(3) == some(1)
    check buf.findNextBookmark(4) == some(1)

  test "Single bookmark always returns it":
    let buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(1)
    check buf.findNextBookmark(0) == some(1)
    check buf.findNextBookmark(1) == some(1) # wraps to self
    check buf.findNextBookmark(2) == some(1)

  test "No bookmarks returns none":
    let buf = newTextBuffer("a\nb\nc")
    check buf.findNextBookmark(0).isNone

suite "Buffer - Bookmarks - findPrevBookmark":
  test "Find prev bookmark before current line":
    let buf = newTextBuffer("a\nb\nc\nd\ne")
    buf.toggleBookmark(1)
    buf.toggleBookmark(3)
    check buf.findPrevBookmark(4) == some(3)
    check buf.findPrevBookmark(3) == some(1)
    check buf.findPrevBookmark(2) == some(1)

  test "Wraps around to last bookmark":
    let buf = newTextBuffer("a\nb\nc\nd\ne")
    buf.toggleBookmark(1)
    buf.toggleBookmark(3)
    check buf.findPrevBookmark(1) == some(3)
    check buf.findPrevBookmark(0) == some(3)

  test "Single bookmark always returns it":
    let buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(1)
    check buf.findPrevBookmark(2) == some(1)
    check buf.findPrevBookmark(1) == some(1) # wraps to self
    check buf.findPrevBookmark(0) == some(1)

  test "No bookmarks returns none":
    let buf = newTextBuffer("a\nb\nc")
    check buf.findPrevBookmark(0).isNone

suite "Buffer - Bookmarks - adjustBookmarksForInsert":
  test "Insert before bookmarks shifts them":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(1)
    buf.toggleBookmark(3)
    buf.adjustBookmarksForInsert(0)
    check buf.bookmarks == @[2, 4]

  test "Insert at bookmark line shifts it":
    let buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(1)
    buf.adjustBookmarksForInsert(1)
    check buf.bookmarks == @[2]

  test "Insert after bookmarks does not shift":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(0)
    buf.toggleBookmark(1)
    buf.adjustBookmarksForInsert(3)
    check buf.bookmarks == @[0, 1]

  test "Insert multiple lines":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(2)
    buf.adjustBookmarksForInsert(1, 3)
    check buf.bookmarks == @[5]

suite "Buffer - Bookmarks - adjustBookmarksForDelete":
  test "Delete before bookmarks shifts them down":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(2)
    buf.toggleBookmark(3)
    buf.adjustBookmarksForDelete(0)
    check buf.bookmarks == @[1, 2]

  test "Delete bookmarked line removes it":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(1)
    buf.toggleBookmark(3)
    buf.adjustBookmarksForDelete(1)
    check buf.bookmarks == @[2]

  test "Delete after bookmarks does not shift":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(0)
    buf.toggleBookmark(1)
    buf.adjustBookmarksForDelete(3)
    check buf.bookmarks == @[0, 1]

  test "Delete range removes bookmarks within range":
    let buf = newTextBuffer("a\nb\nc\nd\ne")
    buf.toggleBookmark(0)
    buf.toggleBookmark(1)
    buf.toggleBookmark(2)
    buf.toggleBookmark(3)
    buf.toggleBookmark(4)
    buf.adjustBookmarksForDelete(1, 3)
    check buf.bookmarks == @[0, 1] # 0 unchanged, 4 shifted to 1

  test "Delete all bookmarked lines clears bookmarks":
    let buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(0)
    buf.toggleBookmark(1)
    buf.toggleBookmark(2)
    buf.adjustBookmarksForDelete(0, 3)
    check buf.bookmarks.len == 0

suite "Buffer - Bookmarks - line insert/delete integration":
  test "Inserting a line adjusts bookmarks":
    let buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(1)
    buf.toggleBookmark(2)
    discard buf.insert(0, "new")
    check buf.bookmarks == @[2, 3]

  test "Deleting a line adjusts bookmarks":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(2)
    buf.toggleBookmark(3)
    discard buf.deleteLine(0)
    check buf.bookmarks == @[1, 2]

  test "Deleting a bookmarked line removes it":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(1)
    buf.toggleBookmark(3)
    discard buf.deleteLine(1)
    check buf.bookmarks == @[2]

  test "Undo insert restores bookmarks":
    let buf = newTextBuffer("a\nb\nc")
    buf.toggleBookmark(1)
    buf.toggleBookmark(2)
    discard buf.insert(0, "new")
    check buf.bookmarks == @[2, 3]
    discard buf.undo()
    check buf.bookmarks == @[1, 2]

  test "Undo delete restores bookmarks":
    let buf = newTextBuffer("a\nb\nc\nd")
    buf.toggleBookmark(2)
    buf.toggleBookmark(3)
    discard buf.deleteLine(0)
    check buf.bookmarks == @[1, 2]
    discard buf.undo()
    check buf.bookmarks == @[2, 3]

suite "Buffer - Diagnostic Highlights":
  test "updateHighlight applies diagnostic underlines":
    let buf = newTextBuffer("hello world")
    buf.language = SourceLanguage.langNone
    buf.diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 5,
        severity: bdsError,
        message: "test error",
      )
    ]
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()

    # The diagnostic range should have Underline modifier
    check buf.highlight.getSegmentModifiers(0, 0) == {StyleModifier.Undercurl}
    check buf.highlight.getSegmentModifiers(0, 3) == {StyleModifier.Undercurl}

    # The color should be syntaxCheckErr
    check buf.highlight.getColorPair(0, 0) == EditorColorPairIndex.syntaxCheckErr

  test "updateHighlight with warning diagnostic":
    let buf = newTextBuffer("hello world")
    buf.language = SourceLanguage.langNone
    buf.diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 6,
        endLine: 0,
        endCol: 11,
        severity: bdsWarning,
        message: "test warning",
      )
    ]
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()

    check buf.highlight.getColorPair(0, 6) == EditorColorPairIndex.syntaxCheckWarn
    check buf.highlight.getSegmentModifiers(0, 6) == {StyleModifier.Undercurl}

    # Outside diagnostic range should have no underline
    check buf.highlight.getSegmentModifiers(0, 0) == {}

  test "updateHighlight with no diagnostics does not add underlines":
    let buf = newTextBuffer("hello world")
    buf.language = SourceLanguage.langNone
    buf.highlightNeedsUpdate = true
    buf.updateHighlight()

    check buf.highlight.getSegmentModifiers(0, 0) == {}
