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
import pkg/results
import ../src/moepkg/buffer

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
