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

import std/[unittest, os, strutils, times, options, unicode]

import pkg/[results, celina]

import ../src/moepkg/[buffer, highlight]

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
    let testFile = getTempDir() / "moe_test_trailing.txt"

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
    let testFile = getTempDir() / "moe_test_endofline.txt"

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

  test "insertText normalizes CRLF to LF":
    let buf = newTextBuffer("")
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\r\nb\r\nc")
    check buf.len == 3
    check buf[0] == "a"
    check buf[1] == "b"
    check buf[2] == "c"

  test "insertText normalizes lone CR to LF":
    let buf = newTextBuffer("")
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\rb\rc")
    check buf.len == 3
    check buf[0] == "a"
    check buf[1] == "b"
    check buf[2] == "c"

  test "insertText keeps no raw CR in line content":
    let buf = newTextBuffer("")
    discard buf.insertText(BufferPosition(line: 0, column: 0), "x\r\ny")
    check '\r' notin buf[0]
    check '\r' notin buf[1]

  test "insertText undo/redo never reintroduces CR":
    let buf = newTextBuffer("")
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\r\nb")
    discard buf.undo()
    discard buf.redo()
    check buf.len == 2
    check '\r' notin buf[0]
    check '\r' notin buf[1]

  test "normalizeNewlines leaves CR-free text untouched":
    check normalizeNewlines("plain text\nwith lf") == "plain text\nwith lf"
    check normalizeNewlines("") == ""

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

  test "insert strips stray CR from line content":
    let buf = newTextBuffer("Line1")
    discard buf.insert(1, "Line2\r")
    check buf.len == 2
    check buf[1] == "Line2"
    check '\r' notin buf[1]

  test "replaceLine strips stray CR from line content":
    let buf = newTextBuffer("Line1\nLine2")
    discard buf.replaceLine(0, "New\rLine")
    check buf[0] == "NewLine"
    check '\r' notin buf[0]

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
  test "isWordChar - ASCII alphanumeric and underscore":
    check 'a'.Rune.isWordChar
    check 'Z'.Rune.isWordChar
    check '0'.Rune.isWordChar
    check '9'.Rune.isWordChar
    check '_'.Rune.isWordChar

  test "isWordChar - non-word ASCII":
    check not ' '.Rune.isWordChar
    check not '\t'.Rune.isWordChar
    check not '.'.Rune.isWordChar
    check not ','.Rune.isWordChar
    check not '-'.Rune.isWordChar
    check not '('.Rune.isWordChar

  test "isWordChar - Unicode letters are word chars":
    # CJK ideographs
    check "日".runeAt(0).isWordChar
    check "本".runeAt(0).isWordChar
    check "語".runeAt(0).isWordChar
    # Hiragana / Katakana
    check "あ".runeAt(0).isWordChar
    check "ア".runeAt(0).isWordChar
    # Accented Latin
    check "é".runeAt(0).isWordChar
    check "ü".runeAt(0).isWordChar
    # Cyrillic / Greek
    check "Я".runeAt(0).isWordChar
    check "λ".runeAt(0).isWordChar

  test "isWordChar - non-ASCII digits stay non-word":
    # Digits are intentionally ASCII-only to match source-code conventions.
    # Arabic-Indic digit ٥ (U+0665) and Devanagari digit ५ (U+096B) are
    # Unicode digits but not Unicode letters, so they should NOT be word
    # characters under the current contract.
    check not "٥".runeAt(0).isWordChar
    check not "५".runeAt(0).isWordChar

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

  test "isPositionInWord - Unicode (CJK are word chars)":
    let buf = newTextBuffer("hello世界world")
    # CJK characters are word characters via Unicode-aware isAlpha,
    # so the entire "hello世界world" is treated as a single word.
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "hello") == false
    check buf.isPositionInWord(BufferPosition(line: 0, column: 5), "hello") == false
      # '世'
    check buf.isPositionInWord(BufferPosition(line: 0, column: 7), "world") == false
    check buf.isPositionInWord(BufferPosition(line: 0, column: 0), "hello世界world") ==
      true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 5), "hello世界world") ==
      true
    check buf.isPositionInWord(BufferPosition(line: 0, column: 9), "hello世界world") ==
      true

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
    check fold.get.startLine == 1
    check fold.get.endLine == 3
    check fold.get.collapsed == true

  test "addFold overlapping fails":
    let buf = newTextBuffer("Line1\nLine2\nLine3\nLine4\nLine5")
    check buf.foldState.addFold(1, 3) == true
    check buf.foldState.addFold(2, 4) == false # Overlaps

  test "openFold and closeFold":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    discard buf.foldState.addFold(0, 2)

    check buf.foldState.folds[0].collapsed == true
    # closeFold on an already-collapsed fold is a no-op and returns false
    # (symmetric with openFold on an already-open fold).
    check buf.foldState.closeFold(1) == false
    check buf.foldState.openFold(1) == true
    check buf.foldState.folds[0].collapsed == false
    check buf.foldState.openFold(1) == false
    check buf.foldState.closeFold(1) == true
    check buf.foldState.folds[0].collapsed == true
    check buf.foldState.closeFold(1) == false

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

  test "getPrevVisibleLine snaps a hidden line to the fold start":
    let buf = newTextBuffer("0\n1\n2\n3\n4")
    discard buf.foldState.addFold(1, 3, collapsed = true)
    # Lines hidden inside the collapsed fold snap back to its start line.
    check buf.foldState.getPrevVisibleLine(2) == 1
    check buf.foldState.getPrevVisibleLine(3) == 1
    # Visible lines (including the fold start) are unchanged.
    check buf.foldState.getPrevVisibleLine(1) == 1
    check buf.foldState.getPrevVisibleLine(0) == 0
    check buf.foldState.getPrevVisibleLine(4) == 4

  test "openFoldsInRange opens every collapsed fold overlapping the range":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7\n8\n9")
    discard buf.foldState.addFold(0, 2, collapsed = true) # A
    discard buf.foldState.addFold(4, 6, collapsed = true) # B
    discard buf.foldState.addFold(8, 9, collapsed = true) # C
    # Range [5, 8] overlaps B (4-6) and C (8-9) but not A (0-2).
    check buf.foldState.openFoldsInRange(5, 8) == true
    check buf.foldState.getFoldAt(0).get.collapsed == true # A untouched
    check buf.foldState.getFoldAt(4).get.collapsed == false # B opened
    check buf.foldState.getFoldAt(8).get.collapsed == false # C opened
    # A range overlapping no collapsed fold is a no-op.
    check buf.foldState.openFoldsInRange(3, 3) == false
    check buf.foldState.getFoldAt(0).get.collapsed == true

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

  test "addFold allows nested folds":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5")
    check buf.foldState.addFold(0, 5) == true # outer
    check buf.foldState.addFold(1, 3) == true # inner, contained
    check buf.foldState.addFold(4, 5) == true # contained, disjoint from inner
    check buf.foldState.folds.len == 3

  test "addFold rejects crossing folds":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5")
    check buf.foldState.addFold(2, 4) == true
    check buf.foldState.addFold(1, 3) == false # crosses (2, 4)
    check buf.foldState.addFold(3, 5) == false # crosses (2, 4)

  test "addFold rejects exact duplicate":
    let buf = newTextBuffer("0\n1\n2\n3")
    check buf.foldState.addFold(0, 2) == true
    check buf.foldState.addFold(0, 2) == false

  test "addFold keeps outer fold first on tie":
    let buf = newTextBuffer("0\n1\n2\n3")
    check buf.foldState.addFold(0, 1) == true # inner added first
    check buf.foldState.addFold(0, 3) == true # outer, same startLine
    # Outer (larger endLine) must come first so lookups return it first.
    check buf.foldState.folds[0].endLine == 3
    check buf.foldState.folds[1].endLine == 1

  test "addFold tags source (manual default, lsp explicit)":
    let buf = newTextBuffer("0\n1\n2\n3")
    check buf.foldState.addFold(0, 1) == true
    check buf.foldState.folds[0].source == fsManual
    check buf.foldState.addFold(2, 3, source = fsLsp) == true
    check buf.foldState.getFoldAt(2).get.source == fsLsp

  test "foldIndexAtInnermost returns the tightest fold":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5")
    discard buf.foldState.addFold(0, 5) # outer
    discard buf.foldState.addFold(1, 3) # inner
    let idx = buf.foldState.foldIndexAtInnermost(2)
    check idx.isSome
    check buf.foldState.folds[idx.get].startLine == 1
    check buf.foldState.folds[idx.get].endLine == 3
    # A line only covered by the outer fold returns the outer fold.
    let outerIdx = buf.foldState.foldIndexAtInnermost(5)
    check outerIdx.isSome
    check buf.foldState.folds[outerIdx.get].endLine == 5

  test "openFold/closeFold target the innermost fold":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5")
    discard buf.foldState.addFold(0, 5) # outer at idx 0
    discard buf.foldState.addFold(1, 3) # inner at idx 1
    # Opening at an inner line opens only the inner fold.
    check buf.foldState.openFold(2) == true
    check buf.foldState.folds[1].collapsed == false # inner opened
    check buf.foldState.folds[0].collapsed == true # outer untouched
    # Closing at an inner line closes only the inner fold again.
    check buf.foldState.closeFold(2) == true
    check buf.foldState.folds[1].collapsed == true

  test "deleteFold removes the innermost fold":
    let buf = newTextBuffer("0\n1\n2\n3\n4\n5")
    discard buf.foldState.addFold(0, 5)
    discard buf.foldState.addFold(1, 3)
    check buf.foldState.deleteFold(2) == true
    check buf.foldState.folds.len == 1
    check buf.foldState.folds[0].startLine == 0 # outer remains
    check buf.foldState.folds[0].endLine == 5

suite "Buffer - Sidebar Markers":
  test "setLineMarker and getLineMarker":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    buf.setLineMarker(1, LineMarkerKind.GitAdded)

    check buf.getLineMarker(0).isNone
    check buf.getLineMarker(1).isSome
    check buf.getLineMarker(1).get == LineMarkerKind.GitAdded
    check buf.getLineMarker(2).isNone

  test "clearLineMarker":
    let buf = newTextBuffer("Line1\nLine2")
    buf.setLineMarker(0, LineMarkerKind.GitChanged)
    buf.clearLineMarker(0)
    check buf.getLineMarker(0).isNone

  test "clearAllMarkers":
    let buf = newTextBuffer("Line1\nLine2\nLine3")
    buf.setLineMarker(0, LineMarkerKind.GitAdded)
    buf.setLineMarker(1, LineMarkerKind.GitChanged)
    buf.setLineMarker(2, LineMarkerKind.GitDeleted)

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
    # Japanese characters ARE word characters via Unicode-aware isAlpha,
    # so the whole "hello世界test" is a single word.
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 0)) == "hello世界test"
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 5)) == "hello世界test"
    check buf.getWordAtPosition(BufferPosition(line: 0, column: 7)) == "hello世界test"

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
    let testFile = getTempDir() / "moe_test_nonexistent_" & $epochTime() & ".txt"
    let result = buf.loadFile(testFile)
    check result.isOk
    check buf.len == 1
    check buf[0] == ""

  test "saveFile and loadFile roundtrip":
    let testFile = getTempDir() / "moe_test_roundtrip.txt"

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
    let testFile = getTempDir() / "moe_test_modified.txt"
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
    let buf = newTextBuffer("hello", some(getTempDir() / "nonexistent_test_file_12345"))
    buf.lastFileModTime = some(getTime())
    check not buf.isExternallyModified()

  test "Returns false when lastFileModTime is none":
    let path = getTempDir() / "test_isExternallyModified_none.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer("hello", some(path))
    buf.lastFileModTime = none(Time)
    check not buf.isExternallyModified()

  test "Returns false when file has not been modified":
    let path = getTempDir() / "test_isExternallyModified_unmodified.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check not buf.isExternallyModified()

  test "Returns true when file is modified externally":
    let path = getTempDir() / "test_isExternallyModified_modified.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)

    # Set lastFileModTime to the past so any write will be newer
    buf.lastFileModTime = some(getTime() - initDuration(seconds = 2))
    writeFile(path, "modified")

    check buf.isExternallyModified()

suite "Buffer - saveFile external modification guard":
  test "Refuses save when checkExternalMod and file changed externally":
    let path = getTempDir() / "moe_test_saveFile_toctou_refuse.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)

    # Simulate external modification after load.
    buf.lastFileModTime = some(getTime() - initDuration(seconds = 2))
    writeFile(path, "external change")

    discard buf.insertText(BufferPosition(line: 0, column: 0), "mine ")
    let res = buf.saveFile(path, checkExternalMod = true)
    check res.isErr
    check res.error == ExternalModErrorMsg
    # On-disk content must be left untouched.
    check readFile(path) == "external change"

  test "Default save ignores external modification":
    let path = getTempDir() / "moe_test_saveFile_toctou_default.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    buf.lastFileModTime = some(getTime() - initDuration(seconds = 2))
    writeFile(path, "external change")

    # checkExternalMod defaults to false, so the write proceeds.
    let res = buf.saveFile(path)
    check res.isOk

  test "checkExternalMod does not block save-as to a different path":
    let original = getTempDir() / "moe_test_saveFile_toctou_orig.txt"
    let target = getTempDir() / "moe_test_saveFile_toctou_target.txt"
    writeFile(original, "hello")
    defer:
      removeFile(original)
      if fileExists(target):
        removeFile(target)

    let buf = newTextBuffer()
    discard buf.loadFile(original)
    # The original file changes externally...
    buf.lastFileModTime = some(getTime() - initDuration(seconds = 2))
    writeFile(original, "external change")

    # ...but we are saving to a different path, so it must not be blocked.
    let res = buf.saveFile(target, checkExternalMod = true)
    check res.isOk
    check fileExists(target)

suite "Buffer - reloadFile":
  test "Returns error when buffer has no file path":
    let buf = newTextBuffer("hello")
    let res = buf.reloadFile()
    check res.isErr

  test "Reloads file content from disk":
    let path = getTempDir() / "test_reloadFile.txt"
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
    let path = getTempDir() / "test_reloadFile_modtime.txt"
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
    let path = getTempDir() / "test_externalModWarned_doesnt_mask.txt"
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
    let path = getTempDir() / "test_externalModWarned_load.txt"
    writeFile(path, "hello")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    buf.externalModWarned = true
    discard buf.loadFile(path)
    check buf.externalModWarned == false

  test "saveFile resets externalModWarned":
    let path = getTempDir() / "test_externalModWarned_save.txt"
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

suite "Buffer - CRLF Line Ending Handling":
  test "loadFile CRLF: line ending detected":
    let path = getTempDir() / "moe_test_crlf_detect.txt"
    writeFile(path, "line1\r\nline2\r\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CRLF

  test "loadFile CRLF: \\r stripped from line content":
    let path = getTempDir() / "moe_test_crlf_strip.txt"
    writeFile(path, "hello\r\nworld\r\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.len == 2
    check buf[0] == "hello"
    check buf[1] == "world"

  test "loadFile CRLF: single line":
    let path = getTempDir() / "moe_test_crlf_single.txt"
    writeFile(path, "const = 'a';\r\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.len == 1
    check buf[0] == "const = 'a';"
    check buf.lineEnding == CRLF

  test "loadFile CR-only: line ending detected and normalized":
    let path = getTempDir() / "moe_test_cr.txt"
    writeFile(path, "line1\rline2\r")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CR
    check buf.len == 2
    check buf[0] == "line1"
    check buf[1] == "line2"

  test "loadFile LF: no modification":
    let path = getTempDir() / "moe_test_lf.txt"
    writeFile(path, "line1\nline2\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == LF
    check buf.len == 2
    check buf[0] == "line1"
    check buf[1] == "line2"

  test "saveFile CRLF: roundtrip preserves line endings":
    let path = getTempDir() / "moe_test_crlf_roundtrip.txt"
    let original = "hello\r\nworld\r\n"
    writeFile(path, original)
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CRLF
    check buf[0] == "hello"
    check buf[1] == "world"

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == original

  test "saveFile CR: roundtrip preserves line endings":
    let path = getTempDir() / "moe_test_cr_roundtrip.txt"
    let original = "hello\rworld\r"
    writeFile(path, original)
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CR

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == original

  test "saveFile LF: roundtrip preserves line endings":
    let path = getTempDir() / "moe_test_lf_roundtrip.txt"
    let original = "hello\nworld\n"
    writeFile(path, original)
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == LF

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == original

  test "CRLF file with empty lines":
    let path = getTempDir() / "moe_test_crlf_empty.txt"
    writeFile(path, "line1\r\n\r\nline3\r\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.len == 3
    check buf[0] == "line1"
    check buf[1] == ""
    check buf[2] == "line3"

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == "line1\r\n\r\nline3\r\n"

  test "CRLF endOfLine detection":
    let path = getTempDir() / "moe_test_crlf_eol.txt"
    # File without trailing newline
    writeFile(path, "hello\r\nworld")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CRLF
    check buf.endOfLine == false
    check buf[0] == "hello"
    check buf[1] == "world"

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == "hello\r\nworld"

  test "CRLF roundtrip after inserting a line":
    let path = getTempDir() / "moe_test_crlf_insert.txt"
    writeFile(path, "aaa\r\nbbb\r\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    discard buf.insert(1, "ccc")
    check buf.len == 3

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == "aaa\r\nccc\r\nbbb\r\n"

  test "CRLF roundtrip after deleting a line":
    let path = getTempDir() / "moe_test_crlf_delete.txt"
    writeFile(path, "aaa\r\nbbb\r\nccc\r\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    discard buf.deleteLine(1)
    check buf.len == 2

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == "aaa\r\nccc\r\n"

  test "CRLF roundtrip after replacing a line":
    let path = getTempDir() / "moe_test_crlf_replace.txt"
    writeFile(path, "aaa\r\nbbb\r\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    discard buf.replaceLine(0, "zzz")

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == "zzz\r\nbbb\r\n"

  test "CR roundtrip after editing":
    let path = getTempDir() / "moe_test_cr_edit.txt"
    writeFile(path, "aaa\rbbb\r")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    discard buf.insert(1, "new")

    discard buf.saveFile(path)
    let saved = readFile(path)
    check saved == "aaa\rnew\rbbb\r"

  test "mixed CRLF + standalone CR: standalone CR becomes a line break":
    # CRLF-first file with an isolated CR in the middle: the CR must produce
    # its own line break instead of being silently stripped.
    let path = getTempDir() / "moe_test_mixed_crlf_first.txt"
    writeFile(path, "a\r\nb\rc")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CRLF
    check buf.len == 3
    check buf[0] == "a"
    check buf[1] == "b"
    check buf[2] == "c"

  test "mixed CR + embedded CRLF: CRLF stays a single line break":
    # CR-first file with an embedded CRLF: the CRLF pair must not double
    # into two line breaks.
    let path = getTempDir() / "moe_test_mixed_cr_first.txt"
    writeFile(path, "a\rb\r\nc")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CRLF
    check buf.len == 3
    check buf[0] == "a"
    check buf[1] == "b"
    check buf[2] == "c"

  test "mixed line endings: consecutive CRLF-CR-CRLF produces three breaks":
    let path = getTempDir() / "moe_test_mixed_triple.txt"
    writeFile(path, "a\r\nb\rc\r\nd")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CRLF
    check buf.len == 4
    check buf[0] == "a"
    check buf[1] == "b"
    check buf[2] == "c"
    check buf[3] == "d"

  test "consecutive standalone CRs produce consecutive line breaks":
    let path = getTempDir() / "moe_test_double_cr.txt"
    writeFile(path, "a\r\rb")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CR
    check buf.len == 3
    check buf[0] == "a"
    check buf[1] == ""
    check buf[2] == "b"

  test "trailing CR at end of buffer is treated as a line break":
    let path = getTempDir() / "moe_test_trailing_cr.txt"
    writeFile(path, "a\r")
    defer:
      removeFile(path)

    let buf = newTextBuffer()
    discard buf.loadFile(path)
    check buf.lineEnding == CR
    check buf.endOfLine
    check buf.len == 1
    check buf[0] == "a"

suite "Buffer - contentVersion monotonicity":
  # contentVersion is the completion cache's invalidation key. Unlike changeSeq
  # (restored by undo, reset to 0 by reload) it must only ever increase, so a
  # reverted or reloaded buffer is never mistaken for an older cached state.

  test "NoUndo line mutators advance contentVersion":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "alpha\nbeta\n")
    var v = buf.contentVersion

    buf.replaceLineNoUndo(0, "gamma")
    check buf.contentVersion > v
    v = buf.contentVersion

    buf.insertLineNoUndo(1, "delta")
    check buf.contentVersion > v
    v = buf.contentVersion

    buf.deleteLineNoUndo(1)
    check buf.contentVersion > v

  test "Undo and redo never roll contentVersion back":
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "alpha\n")
    let vEdit = buf.contentVersion

    check buf.undo().isOk
    check buf.changeSeq == 0 # changeSeq restored to the saved value
    check buf.contentVersion > vEdit # contentVersion kept climbing
    let vUndo = buf.contentVersion

    check buf.redo().isOk
    check buf.contentVersion > vUndo

  test "Reload across a backend swap keeps contentVersion monotonic":
    # Pin the backend choice so the swap branch is taken regardless of any
    # global config left over from other tests, and restore it afterwards.
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)
    defer:
      setAutoBackendMode(false)
      setConfiguredBackend(GapBuffer)

    let path = getTempDir() / "moe_test_contentversion_swap.txt"
    writeFile(path, "alpha beta\n") # small file -> GapBuffer
    defer:
      removeFile(path)

    # Start on PieceTable so the reload swaps the backend to GapBuffer; the swap
    # must still keep contentVersion monotonic rather than reset it.
    let buf = newTextBuffer(backend = PieceTable)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "aaa\n")
    discard buf.insertText(BufferPosition(line: 0, column: 0), "bbb\n")
    let vBefore = buf.contentVersion

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened
    check buf.changeSeq == 0 # reload resets changeSeq
    check buf.contentVersion > vBefore # but contentVersion only advances

  test "NoUndo mutators leave changeSeq unchanged":
    # Regression guard for LSP format/rename stale-guard: NoUndo operations
    # (used by substitute preview etc.) change the buffer content and advance
    # contentVersion but skip changeSeq. A stale-guard keyed on changeSeq would
    # miss the content change and accept a stale LSP response.
    let buf = newTextBuffer()
    discard buf.insertText(BufferPosition(line: 0, column: 0), "hello\nworld\n")
    let cs = buf.changeSeq
    let cv = buf.contentVersion

    buf.replaceLineNoUndo(0, "salut")
    check buf.changeSeq == cs
    check buf.contentVersion > cv

    buf.insertLineNoUndo(1, "monde")
    check buf.changeSeq == cs
    check buf.contentVersion > cv

    buf.deleteLineNoUndo(2)
    check buf.changeSeq == cs
    check buf.contentVersion > cv

  test "Reload then edit makes changeSeq re-ascend but contentVersion monotonic":
    # Regression guard for LSP format/rename stale-guard: reload resets
    # changeSeq to 0, then subsequent edits can bring it back to a value
    # that matches a pre-reload snapshot, letting a stale guard pass.
    # contentVersion never resets, so it always catches the change.
    let path = getTempDir() / "moe_test_changeseq_aba.txt"
    writeFile(path, "fresh\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "abc\n")
    let cvPre = buf.contentVersion

    # Reload resets changeSeq to 0 but contentVersion only advances.
    check buf.loadFile(path).isOk
    check buf.changeSeq == 0
    check buf.contentVersion > cvPre

    # A subsequent edit pushes changeSeq back up. It can (by ABA) land
    # on csPre again; contentVersion, being monotonic, cannot repeat.
    discard buf.insertText(BufferPosition(line: 0, column: 5), " edited\n")
    check buf.contentVersion > cvPre

suite "Buffer - reload preserves identity across a backend swap":
  # A reload that changes the backend reassigns only TextBuffer.storage, leaving
  # every sibling field in place. Identity and detected state must survive the
  # swap; only content-keyed state (undo stacks, etc.) is reset, on both paths.

  setup:
    # Pin the backend choice so a PieceTable buffer reliably swaps to GapBuffer.
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)

  teardown:
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)

  test "id, bookmarks, displayName and readOnly survive the swap":
    let path = getTempDir() / "moe_test_identity_swap.txt"
    writeFile(path, "one\ntwo\nthree\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "x\ny\nz\n")
    buf.toggleBookmark(1)
    buf.toggleBookmark(2)
    buf.displayName = some("scratch")
    buf.readOnly = true
    let idBefore = buf.id

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    check buf.id == idBefore # was reset to a fresh genBufferId() before the fix
    check buf.bookmarks == @[1, 2]
    check buf.displayName == some("scratch")
    check buf.readOnly

  test "detected CRLF line ending survives the swap":
    let path = getTempDir() / "moe_test_crlf_swap.txt"
    writeFile(path, "aaa\r\nbbb\r\n") # CRLF file
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    # The swap must not clobber the freshly detected CRLF back to LF: a save
    # round-trips CRLF rather than silently converting the whole file to LF.
    discard buf.saveFile(path)
    check readFile(path) == "aaa\r\nbbb\r\n"

  test "reservedWords survive the swap":
    # reservedWords is config-derived (TODO/NOTE highlighting). A same-backend
    # reload keeps it; the swap path must not silently empty it, or TODO/NOTE
    # highlighting would stop until the next full config reload.
    let path = getTempDir() / "moe_test_reservedwords_swap.txt"
    writeFile(path, "code\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    buf.setReservedWords(
      @[ReservedWord(word: "TODO", color: EditorColorPairIndex.default)]
    )

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    check buf.reservedWords.len == 1
    check buf.reservedWords[0].word == "TODO"

  test "manual folds survive the swap":
    let path = getTempDir() / "moe_test_folds_swap.txt"
    writeFile(path, "a\nb\nc\nd\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "1\n2\n3\n4\n")
    check buf.foldState.addFold(0, 2)

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    check buf.foldState.folds.len == 1
    check buf.foldState.folds[0].startLine == 0
    check buf.foldState.folds[0].endLine == 2

  test "diagnostics are cleared on reload (not part of identity)":
    # Diagnostics are NOT identity: their line positions go stale when the content
    # is replaced, and a reload sends no didChange for the server to re-publish.
    # loadFile clears them on both paths; without that, updateHighlight would
    # re-apply stale undercurls at the old positions after the next edit.
    let path = getTempDir() / "moe_test_diagnostics_swap.txt"
    writeFile(path, "x\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    buf.diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 1,
        severity: bdsError,
        message: "boom",
      )
    ]

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    check buf.diagnostics.len == 0

  test "conflictBlocks are cleared on reload (not part of identity)":
    # conflictBlocks holds line ranges into the OLD content, so a reload makes them
    # stale; like diagnostics they are cleared on both paths and the caller
    # re-scans. Without the clear, a same-backend reload would keep stale ranges
    # while the swap path wiped them — a backend-dependent result.
    let path = getTempDir() / "moe_test_conflicts_swap.txt"
    writeFile(path, "clean\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    buf.conflictBlocks = @[
      ConflictBlock(
        startLine: 0,
        baseMarkerLine: none(int),
        separatorLine: 1,
        endLine: 2,
        oursLabel: "HEAD",
        theirsLabel: "branch",
      )
    ]

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    check buf.conflictBlocks.len == 0

  test "changelist is cleared on reload (not part of identity)":
    # The changelist holds positions into the OLD content, and undo (which it
    # parallels) is dropped on reload, so it is cleared on both paths — matching
    # vim, which resets the changelist on :e!.
    let path = getTempDir() / "moe_test_changelist_swap.txt"
    writeFile(path, "y\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    buf.changeList = @[BufferPosition(line: 1, column: 2)]
    buf.changeListIndex = 0

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    check buf.changeList.len == 0
    check buf.changeListIndex == 0

  test "editorConfig and isUtilityBuffer survive the swap":
    let path = getTempDir() / "moe_test_editorconfig_swap.txt"
    writeFile(path, "z\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    buf.editorConfig = some(BufferEditorConfig(tabStop: some(8)))
    buf.isUtilityBuffer = true

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    check buf.editorConfig.isSome
    check buf.editorConfig.get.tabStop == some(8)
    check buf.isUtilityBuffer

  test "detected missing trailing newline survives the swap":
    let path = getTempDir() / "moe_test_eol_swap.txt"
    writeFile(path, "abc") # no trailing newline
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = PieceTable)
    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # the swap happened

    # endOfLine was detected as false; the swap must not reset it to the default,
    # or saving would append a spurious trailing newline.
    check not buf.endOfLine
    discard buf.saveFile(path)
    check readFile(path) == "abc"

suite "Buffer - reload resets stale content-keyed state":
  # A reload replaces the content wholesale. State keyed on the OLD content (the
  # char->byte cursor cache, undo/redo history) is stale and is reset on loadFile's
  # single reload path, so a reload's result never depends on whether the file size
  # happened to cross the backend-swap threshold.

  setup:
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)

  teardown:
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)

  test "same-backend reload invalidates the cursor cache":
    # charToBytePosCached keys on (line, charPos, changeSeq) and returns the cached
    # bytePos WITHOUT re-reading the line. loadFile resets changeSeq to 0, so a hit
    # recorded at changeSeq 0 (the first edit after a load) must not survive a
    # reload, or it would return a byte offset computed from the OLD content and
    # corrupt the edit when a multibyte char shifts column.
    let path = getTempDir() / "moe_test_cursorcache_reload.txt"
    writeFile(path, "world héllo\n") # multibyte (é) before column 7
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    check buf.loadFile(path).isOk
    # First post-load edit at column>0 records a cache entry at changeSeq 0.
    discard buf.deleteChar(BufferPosition(line: 0, column: 7))
    check buf.cursorCache.line != -1 # cache populated

    # Reload a DIFFERENT content where char 7 sits at another byte offset.
    writeFile(path, "héllo world\n") # é now before column 7, 'o' at char 7
    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # same-backend path, no swap
    check buf.cursorCache.line == -1 # cache invalidated by the reload
    check buf.cursorCache.changeSeq == -1

    # A fresh edit must read the NEW content's byte layout, not the stale offset.
    discard buf.deleteChar(BufferPosition(line: 0, column: 7))
    check buf.getLine(0) == "héllo wrld" # char 7 ('o') removed cleanly

  test "reload clears undo and redo history":
    # Undo entries store positions into the OLD content, so a reload invalidates
    # them. loadFile clears them on its single reload path (clearUndoRedoState),
    # or `u` after a reload replays a change against mismatched content.
    let path = getTempDir() / "moe_test_undo_reload.txt"
    writeFile(path, "ground truth\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "scratch\n")
    discard buf.deleteChar(BufferPosition(line: 0, column: 0))
    check buf.undo().isOk # there is undo history before the reload

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # same-backend path, no swap
    check buf.getLine(0) == "ground truth"

    # Undo/redo must be no-ops now: the history was discarded with the old content.
    check buf.undo().isErr
    check buf.redo().isErr

  test "same-backend reload clears stale diagnostics":
    # The same-backend path previously kept diagnostics (loadFile never reset
    # them), so updateHighlight would re-apply them at stale line positions after
    # the next edit. loadFile now clears them on this path too.
    let path = getTempDir() / "moe_test_diagnostics_sameback.txt"
    writeFile(path, "code\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    buf.diagnostics = @[
      BufferDiagnostic(
        startLine: 0,
        startCol: 0,
        endLine: 0,
        endCol: 1,
        severity: bdsError,
        message: "stale",
      )
    ]

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # same-backend path, no swap
    check buf.diagnostics.len == 0

  test "same-backend reload keeps contentVersion monotonic":
    # loadFile advances contentVersion once on its single reload path; a reload
    # must keep it strictly increasing even though changeSeq resets to 0.
    let path = getTempDir() / "moe_test_contentversion_sameback.txt"
    writeFile(path, "fresh\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "edit\n")
    let vBefore = buf.contentVersion

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # no swap
    check buf.changeSeq == 0 # reload resets changeSeq
    check buf.contentVersion > vBefore # but contentVersion only advances

  test "same-backend reload clears stale conflictBlocks":
    # conflictBlocks holds line ranges into the OLD content; loadFile clears them
    # on its single reload path, or g]/[ conflict navigation would point into
    # content that no longer exists.
    let path = getTempDir() / "moe_test_conflicts_sameback.txt"
    writeFile(path, "clean\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    buf.conflictBlocks = @[
      ConflictBlock(
        startLine: 0,
        baseMarkerLine: none(int),
        separatorLine: 1,
        endLine: 2,
        oursLabel: "HEAD",
        theirsLabel: "branch",
      )
    ]

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # same-backend path, no swap
    check buf.conflictBlocks.len == 0

  test "same-backend reload resets lastChangedLines":
    # lastChangedLines seeds the next incremental-highlight pass. After an edit at
    # a higher line it points there; loadFile resets it to 0 on its single reload
    # path, or the highlight seed would carry over from the replaced content.
    let path = getTempDir() / "moe_test_lastchanged_sameback.txt"
    writeFile(path, "seed\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\nd\n")
    discard buf.insertText(BufferPosition(line: 3, column: 0), "X")
    check buf.lastChangedLines > 0 # the edit moved the seed off line 0

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # same-backend path, no swap
    check buf.lastChangedLines == 0

  test "same-backend reload clears the changelist":
    # The changelist parallels undo (cleared on reload) and holds positions into
    # the old content, so the same-backend path drops it too — g;/g, start fresh.
    let path = getTempDir() / "moe_test_changelist_sameback.txt"
    writeFile(path, "fresh\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    discard buf.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc\n")
    check buf.changeList.len > 0 # edits recorded changelist entries

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # same-backend path, no swap
    check buf.changeList.len == 0
    check buf.changeListIndex == 0

  test "shrinking reload clamps stale folds and bookmarks":
    # Folds and bookmarks survive a reload (identity), but a reload that shrinks
    # the buffer must not leave them referencing lines that no longer exist: a
    # fold extending past the new end is clamped, one starting past it is dropped,
    # and out-of-range bookmarks are removed.
    let path = getTempDir() / "moe_test_clamp_reload.txt"
    writeFile(path, "a\nb\nc\nd\ne\n") # 5 lines
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    check buf.loadFile(path).isOk
    check buf.foldState.addFold(1, 3) # partial: clamped after the shrink
    check buf.foldState.addFold(4, 4) # fully past the new end: dropped
    buf.toggleBookmark(0)
    buf.toggleBookmark(1)
    buf.toggleBookmark(4)

    # Reload a 2-line version (lines 0,1 only); same-backend path.
    writeFile(path, "x\ny\n")
    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # no swap

    check buf.foldState.folds.len == 1
    check buf.foldState.folds[0].startLine == 1
    check buf.foldState.folds[0].endLine == 1 # clamped from 3 to len-1
    check buf.bookmarks == @[0, 1] # 4 dropped, 0 and 1 kept

  test "same-backend reload preserves identity fields":
    # The swap suite covers identity survival across a backend swap; this is the
    # positive coverage for the common same-backend path, where loadFile must
    # leave these untouched (it neither captures/restores nor resets them).
    let path = getTempDir() / "moe_test_identity_sameback.txt"
    writeFile(path, "one\ntwo\nthree\n")
    defer:
      removeFile(path)

    let buf = newTextBuffer(backend = GapBuffer)
    check buf.loadFile(path).isOk
    let idBefore = buf.id
    buf.toggleBookmark(1)
    buf.displayName = some("scratch")
    buf.readOnly = true
    buf.setReservedWords(
      @[ReservedWord(word: "TODO", color: EditorColorPairIndex.default)]
    )
    buf.editorConfig = some(BufferEditorConfig(tabStop: some(4)))
    buf.isUtilityBuffer = true

    check buf.loadFile(path).isOk
    check buf.backendKind == GapBuffer # same-backend path, no swap

    check buf.id == idBefore
    check buf.bookmarks == @[1]
    check buf.displayName == some("scratch")
    check buf.readOnly
    check buf.reservedWords.len == 1
    check buf.editorConfig.isSome
    check buf.editorConfig.get.tabStop == some(4)
    check buf.isUtilityBuffer

suite "Buffer - reload path convergence":
  # Path-independence guard: a backend-swap reload and a same-backend reload must
  # leave the buffer in the SAME state field-by-field. Since the backend variant
  # now lives in the embedded `storage` field, loadFile reassigns only that field
  # and runs one reset/recompute tail unconditionally, so the two paths are
  # structurally identical. fieldPairs walks every TextBuffer field, so a new
  # persistent field is covered automatically — re-introduce a swap-only split and
  # this fails. It checks convergence, not the correctness of each field's chosen
  # behavior; keep the targeted per-field tests above for that.

  setup:
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)

  teardown:
    setAutoBackendMode(false)
    setConfiguredBackend(GapBuffer)

  test "swap and same-backend reload converge field-by-field":
    let path = getTempDir() / "moe_test_reload_converge.txt"
    writeFile(path, "alpha\nbeta\n")
    defer:
      removeFile(path)

    proc populate(b: TextBuffer) =
      discard b.insertText(BufferPosition(line: 0, column: 0), "x\ny\nz\n")
      b.toggleBookmark(0)
      discard b.foldState.addFold(0, 1)
      b.displayName = some("n")
      b.readOnly = true

    let same = newTextBuffer(backend = GapBuffer)
    same.populate()
    let swap = newTextBuffer(backend = PieceTable)
    swap.populate()

    check same.loadFile(path).isOk # same-backend path (GapBuffer -> GapBuffer)
    check swap.loadFile(path).isOk # swap path (PieceTable -> GapBuffer)
    check same.backendKind == swap.backendKind

    # CowSeq's default `==` compares the underlying node by reference, so two
    # logically-equal markers arrays never compare equal; compare by content.
    proc sameContent(a, b: CowSeq[Option[LineMarkerKind]]): bool =
      if a.len != b.len:
        return false
      for i in 0 ..< a.len:
        if a[i] != b[i]:
          return false
      true

    check sameContent(same.lineMarkers, swap.lineMarkers)
    check sameContent(same.pendingSnapshotMarkers, swap.pendingSnapshotMarkers)

    # Deque[BufferChange] and Option[BufferTransaction] have no usable structural
    # `==`, so the generic walk below cannot compare them. A reload clears all
    # three via clearUndoRedoState, so assert convergence on their emptiness — the
    # realistic regression is one path forgetting to clear them.
    check same.undoStack.len == swap.undoStack.len
    check same.redoStack.len == swap.redoStack.len
    check same.currentTransaction.isSome == swap.currentTransaction.isSome

    # Fields deliberately not compared by the generic `==` walk below. Each is
    # excluded for a stated reason; the walk additionally fails (via `uncomparable`)
    # on any NON-excluded field whose `==` does not compile, so a silent gap can't
    # reopen:
    #   - id: a fresh genBufferId() per buffer, so it legitimately differs;
    #   - storage: holds the backend (refs/by-ref `==`), covered by the per-backend
    #     tests above;
    #   - highlight / incrementalHighlight: content-derived (one a ref);
    #   - lineMarkers / pendingSnapshotMarkers: CowSeq has a by-reference `==`, so
    #     they are compared by content via `sameContent` above instead;
    #   - undoStack / redoStack / currentTransaction: no usable `==`, compared by
    #     emptiness above.
    const Excluded = [
      "id", "storage", "highlight", "incrementalHighlight", "lineMarkers",
      "pendingSnapshotMarkers", "undoStack", "redoStack", "currentTransaction",
    ]
    # Walk every TextBuffer field. A non-excluded field whose type has no usable
    # `==` would otherwise be skipped silently by `when compiles`, leaving a hole
    # in the guard; collect those in `uncomparable` and fail, forcing a new field
    # to be either compared here or added to `Excluded` with a reason.
    var diverged, uncomparable: seq[string]
    for name, va, vb in fieldPairs(same[], swap[]):
      # `fields` loops forbid `continue`, so gate on the exclusion instead.
      if name notin Excluded:
        when compiles(va == vb):
          if va != vb:
            diverged.add(name)
        else:
          uncomparable.add(name)
    if diverged.len > 0:
      checkpoint("diverged fields: " & $diverged)
    if uncomparable.len > 0:
      checkpoint(
        "uncomparable, uncovered fields (compare by content or exclude): " &
          $uncomparable
      )
    check diverged.len == 0
    check uncomparable.len == 0

suite "Buffer - UTF-16/32 file transcoding":
  test "UTF-16LE BOM file with CRLF survives load/save round-trip":
    # "ab\r\ncd\r\n" in UTF-16 LE with BOM. Before transcoding, the \r byte
    # of each CRLF (`0D 00 0A 00`) was classified as a lone \r on the raw
    # bytes and the file was corrupted by a plain open + save.
    let original = "\xFF\xFE" & "a\x00b\x00\x0D\x00\x0A\x00c\x00d\x00\x0D\x00\x0A\x00"
    let testFile = getTempDir() / "moe_test_utf16le_crlf.txt"
    writeFile(testFile, original)
    defer:
      removeFile(testFile)

    let buf = newTextBuffer()
    check buf.loadFile(testFile).isOk
    check buf.encoding == CharacterEncoding.utf16Le
    check buf.hasBom
    check buf.lineEnding == CRLF
    check buf.endOfLine
    check buf.len == 2
    check buf[0] == "ab"
    check buf[1] == "cd"
    check buf.getFileContent == original

  test "UTF-16BE BOM file survives load/save round-trip":
    # "あ\ni\n" in UTF-16 BE with BOM
    let original = "\xFE\xFF" & "\x30\x42\x00\x0A\x00\x69\x00\x0A"
    let testFile = getTempDir() / "moe_test_utf16be.txt"
    writeFile(testFile, original)
    defer:
      removeFile(testFile)

    let buf = newTextBuffer()
    check buf.loadFile(testFile).isOk
    check buf.encoding == CharacterEncoding.utf16Be
    check buf.lineEnding == LF
    check buf[0] == "あ"
    check buf[1] == "i"
    check buf.getFileContent == original

  test "UTF-32LE BOM file survives load/save round-trip":
    # "a\r\nb\r\n" in UTF-32 LE with BOM
    let original =
      "\xFF\xFE\x00\x00" & "\x61\x00\x00\x00\x0D\x00\x00\x00\x0A\x00\x00\x00" &
      "\x62\x00\x00\x00\x0D\x00\x00\x00\x0A\x00\x00\x00"
    let testFile = getTempDir() / "moe_test_utf32le.txt"
    writeFile(testFile, original)
    defer:
      removeFile(testFile)

    let buf = newTextBuffer()
    check buf.loadFile(testFile).isOk
    check buf.encoding == CharacterEncoding.utf32Le
    check buf.hasBom
    check buf.lineEnding == CRLF
    check buf[0] == "a"
    check buf[1] == "b"
    check buf.getFileContent == original

  test "BOM-less UTF-16LE detected via validation decodes and round-trips":
    # "Ø\nØ" in UTF-16 LE without BOM: invalid as UTF-8 and as UTF-16 BE
    # (D800 would be an unpaired surrogate), so detection resolves utf16Le.
    let original = "\xD8\x00\x0A\x00\xD8\x00"
    let testFile = getTempDir() / "moe_test_utf16le_nobom.txt"
    writeFile(testFile, original)
    defer:
      removeFile(testFile)

    let buf = newTextBuffer()
    check buf.loadFile(testFile).isOk
    check buf.encoding == CharacterEncoding.utf16Le
    check not buf.hasBom
    check buf[0] == "Ø"
    check buf[1] == "Ø"
    check buf.getFileContent == original

  test "Editing a UTF-16LE buffer saves valid UTF-16LE bytes":
    let original = "\xFF\xFE" & "a\x00\x0D\x00\x0A\x00"
    let testFile = getTempDir() / "moe_test_utf16le_edit.txt"
    writeFile(testFile, original)
    defer:
      removeFile(testFile)

    let buf = newTextBuffer()
    check buf.loadFile(testFile).isOk
    discard buf.insertText(BufferPosition(line: 0, column: 1), "😀")
    check buf.saveFile(testFile).isOk
    # "a😀\r\n" in UTF-16 LE with BOM (😀 = D83D DE00)
    check readFile(testFile) == "\xFF\xFE" & "a\x00\x3D\xD8\x00\xDE\x0D\x00\x0A\x00"

  test "Undecodable UTF-16 BOM file falls back to raw bytes":
    # BOM claims UTF-16 LE but the payload has an odd byte count
    let original = "\xFF\xFE\x41"
    let testFile = getTempDir() / "moe_test_utf16_invalid.txt"
    writeFile(testFile, original)
    defer:
      removeFile(testFile)

    let buf = newTextBuffer()
    check buf.loadFile(testFile).isOk
    check buf.encoding == CharacterEncoding.unknown
    check not buf.hasBom
    check buf.getFileContent == original
