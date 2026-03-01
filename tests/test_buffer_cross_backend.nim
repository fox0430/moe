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

## Cross-backend tests: verify TextBuffer behaves identically across
## all BufferBackend variants. Tests iterate over backends with fixed
## expected values so adding a new backend automatically gets coverage.

import std/[unittest, os, options, strutils]

import pkg/results

import ../src/moepkg/buffer {.all.}

proc buf(
    content: string = "",
    backend: BufferBackend,
    filePath: Option[string] = none(string),
): TextBuffer =
  ## Helper: create TextBuffer with explicit backend
  newTextBuffer(content, filePath, backend)

suite "CrossBackend - Basic Operations":
  for be in BufferBackend:
    test "empty buffer [" & $be & "]":
      let b = buf("", be)
      check b.len == 1
      check b[0] == ""

    test "buffer with content [" & $be & "]":
      let b = buf("Hello\nWorld", be)
      check b.len == 2
      check b[0] == "Hello"
      check b[1] == "World"

    test "getLine [" & $be & "]":
      let b = buf("Line1\nLine2\nLine3", be)
      check b.getLine(0) == "Line1"
      check b.getLine(1) == "Line2"
      check b.getLine(2) == "Line3"

    test "getLineLen [" & $be & "]":
      let b = buf("Hello\nあいう", be)
      check b.getLineLen(0) == 5
      check b.getLineLen(1) == 3

    test "getTextString [" & $be & "]":
      let b = buf("Hello\nWorld", be)
      let text = b.getTextString()
      check text.contains("Hello")
      check text.contains("World")

suite "CrossBackend - Editing Operations":
  for be in BufferBackend:
    test "insertText single character [" & $be & "]":
      let b = buf("Hello", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), "!")
      check b[0] == "Hello!"

    test "insertText in middle [" & $be & "]":
      let b = buf("Hllo", be)
      discard b.insertText(BufferPosition(line: 0, column: 1), "e")
      check b[0] == "Hello"

    test "insertText with newline [" & $be & "]":
      let b = buf("HelloWorld", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), "\n")
      check b.len == 2
      check b[0] == "Hello"
      check b[1] == "World"

    test "insertText multi-line [" & $be & "]":
      let b = buf("Start End", be)
      discard b.insertText(BufferPosition(line: 0, column: 6), "A\nB\n")
      check b.len == 3
      check b[0] == "Start A"
      check b[1] == "B"
      check b[2] == "End"

    test "deleteChar single character [" & $be & "]":
      let b = buf("Hello", be)
      discard b.deleteChar(BufferPosition(line: 0, column: 0))
      check b[0] == "ello"

    test "deleteChar in middle [" & $be & "]":
      let b = buf("Hello", be)
      discard b.deleteChar(BufferPosition(line: 0, column: 2))
      check b[0] == "Helo"

    test "insert new line [" & $be & "]":
      let b = buf("Line1\nLine3", be)
      discard b.insert(1, "Line2")
      check b.len == 3
      check b[0] == "Line1"
      check b[1] == "Line2"
      check b[2] == "Line3"

    test "deleteLine [" & $be & "]":
      let b = buf("Line1\nLine2\nLine3", be)
      discard b.deleteLine(1)
      check b.len == 2
      check b[0] == "Line1"
      check b[1] == "Line3"

    test "deleteRange single line [" & $be & "]":
      let b = buf("Hello World", be)
      discard b.deleteRange(
        BufferPosition(line: 0, column: 5), BufferPosition(line: 0, column: 10)
      )
      check b[0] == "Hello"

    test "deleteRange multi line [" & $be & "]":
      let b = buf("Line1\nLine2\nLine3", be)
      discard b.deleteRange(
        BufferPosition(line: 0, column: 3), BufferPosition(line: 1, column: 2)
      )
      check b.len == 2
      check b[0] == "Line2"
      check b[1] == "Line3"

    test "splitLine [" & $be & "]":
      let b = buf("HelloWorld", be)
      discard b.splitLine(BufferPosition(line: 0, column: 5))
      check b.len == 2
      check b[0] == "Hello"
      check b[1] == "World"

    test "joinLines [" & $be & "]":
      let b = buf("Hello\nWorld", be)
      discard b.joinLines(0)
      check b.len == 1
      check b[0] == "Hello World"

    test "joinLines multiple [" & $be & "]":
      let b = buf("A\nB\nC\nD", be)
      discard b.joinLines(0, 2)
      check b.len == 2
      check b[0] == "A B C"
      check b[1] == "D"

suite "CrossBackend - Undo/Redo":
  for be in BufferBackend:
    test "undo insertText [" & $be & "]":
      let b = buf("Hello", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), " World")
      discard b.undo()
      check b[0] == "Hello"

    test "redo insertText [" & $be & "]":
      let b = buf("Hello", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), " World")
      discard b.undo()
      discard b.redo()
      check b[0] == "Hello World"

    test "undo deleteChar [" & $be & "]":
      let b = buf("Hello", be)
      discard b.deleteChar(BufferPosition(line: 0, column: 4))
      discard b.undo()
      check b[0] == "Hello"

    test "undo deleteLine [" & $be & "]":
      let b = buf("Line1\nLine2\nLine3", be)
      discard b.deleteLine(1)
      discard b.undo()
      check b.len == 3
      check b[1] == "Line2"

    test "undo insertLine [" & $be & "]":
      let b = buf("Line1\nLine3", be)
      discard b.insert(1, "Line2")
      discard b.undo()
      check b.len == 2
      check b[0] == "Line1"
      check b[1] == "Line3"

    test "undo deleteRange [" & $be & "]":
      let b = buf("Hello World Test", be)
      discard b.deleteRange(
        BufferPosition(line: 0, column: 5), BufferPosition(line: 0, column: 10)
      )
      discard b.undo()
      check b[0] == "Hello World Test"

    test "undo deleteRange multi line [" & $be & "]":
      let b = buf("Line1\nLine2\nLine3", be)
      discard b.deleteRange(
        BufferPosition(line: 0, column: 3), BufferPosition(line: 1, column: 2)
      )
      discard b.undo()
      check b.len == 3
      check b[0] == "Line1"
      check b[1] == "Line2"
      check b[2] == "Line3"

    test "multiple undo/redo [" & $be & "]":
      let b = buf("Hello", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), " World")
      discard b.insertText(BufferPosition(line: 0, column: 11), "!")

      discard b.undo()
      discard b.undo()
      check b[0] == "Hello"

      discard b.redo()
      discard b.redo()
      check b[0] == "Hello World!"

suite "CrossBackend - Transaction":
  for be in BufferBackend:
    test "transaction undo [" & $be & "]":
      let b = buf("Hello", be)
      discard b.beginTransaction("test")
      discard b.insertText(BufferPosition(line: 0, column: 5), " ")
      discard b.insertText(BufferPosition(line: 0, column: 6), "World")
      discard b.commitTransaction()
      check b[0] == "Hello World"

      discard b.undo()
      check b[0] == "Hello"

    test "transaction rollback [" & $be & "]":
      let b = buf("Hello", be)
      discard b.beginTransaction("test")
      discard b.insertText(BufferPosition(line: 0, column: 5), " World")
      discard b.rollbackTransaction()
      check b[0] == "Hello"

suite "CrossBackend - isModified":
  for be in BufferBackend:
    test "new buffer not modified [" & $be & "]":
      let b = buf("Hello", be)
      check b.isModified == false

    test "modified after edit [" & $be & "]":
      let b = buf("Hello", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), "!")
      check b.isModified == true

    test "not modified after undo [" & $be & "]":
      let b = buf("Hello", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), "!")
      discard b.undo()
      check b.isModified == false

suite "CrossBackend - Search":
  for be in BufferBackend:
    test "findNext basic [" & $be & "]":
      let b = buf("Hello World Hello", be)
      let pos = b.findNext("Hello", BufferPosition(line: 0, column: -1))
      check pos.isSome
      check pos.get.line == 0
      check pos.get.column == 0

    test "findNext from position [" & $be & "]":
      let b = buf("Hello World Hello", be)
      let pos = b.findNext("Hello", BufferPosition(line: 0, column: 0))
      check pos.isSome
      check pos.get.column == 12

    test "findNext multiline [" & $be & "]":
      let b = buf("Line1\nHello\nLine3", be)
      let pos = b.findNext("Hello", BufferPosition(line: 0, column: 0))
      check pos.isSome
      check pos.get.line == 1
      check pos.get.column == 0

    test "findNext not found [" & $be & "]":
      let b = buf("Hello World", be)
      let pos = b.findNext("NotFound", BufferPosition(line: 0, column: 0))
      check pos.isNone

    test "findPrev basic [" & $be & "]":
      let b = buf("Hello World Hello", be)
      let pos = b.findPrev("Hello", BufferPosition(line: 0, column: 17))
      check pos.isSome
      check pos.get.column == 12

suite "CrossBackend - Unicode":
  for be in BufferBackend:
    test "insertText unicode [" & $be & "]":
      let b = buf("こんにちは", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), "世界")
      check b[0] == "こんにちは世界"

    test "deleteChar unicode [" & $be & "]":
      let b = buf("あいうえお", be)
      discard b.deleteChar(BufferPosition(line: 0, column: 2))
      check b[0] == "あいえお"

    test "undo insertText unicode [" & $be & "]":
      let b = buf("こんにちは", be)
      discard b.insertText(BufferPosition(line: 0, column: 5), "世界")
      discard b.undo()
      check b[0] == "こんにちは"

    test "deleteRange unicode multi line [" & $be & "]":
      let b = buf("あいう\nえおか", be)
      # Deletes from (0,1) to (1,1) inclusive: "いう\nえ" + "お" → "あ" + "か"
      discard b.deleteRange(
        BufferPosition(line: 0, column: 1), BufferPosition(line: 1, column: 1)
      )
      check b.len == 1
      check b[0] == "あか"

suite "CrossBackend - Trailing Empty Lines":
  for be in BufferBackend:
    test "insert text with trailing empty lines [" & $be & "]":
      let b = buf("", be)
      discard b.insertText(BufferPosition(line: 0, column: 0), "Hello\n\n")
      check b.len == 3
      check b[0] == "Hello"
      check b[1] == ""
      check b[2] == ""

    test "insert text with single trailing newline [" & $be & "]":
      let b = buf("", be)
      discard b.insertText(BufferPosition(line: 0, column: 0), "Hello\n")
      check b.len == 2
      check b[0] == "Hello"
      check b[1] == ""

    test "multiple insertions with trailing newlines [" & $be & "]":
      let b = buf("", be)
      discard b.insertText(BufferPosition(line: 0, column: 0), "Line1\n")
      discard b.insertText(BufferPosition(line: 1, column: 0), "Line2\n")
      check b.len == 3
      check b[0] == "Line1"
      check b[1] == "Line2"
      check b[2] == ""

suite "CrossBackend - NoUndo Procs":
  for be in BufferBackend:
    test "replaceLineNoUndo [" & $be & "]":
      let b = buf("hello\nworld", be)
      b.replaceLineNoUndo(0, "replaced")
      check b[0] == "replaced"
      check b[1] == "world"

    test "deleteLineNoUndo [" & $be & "]":
      let b = buf("line1\nline2\nline3", be)
      b.deleteLineNoUndo(1)
      check b.len == 2
      check b[0] == "line1"
      check b[1] == "line3"

    test "insertLineNoUndo [" & $be & "]":
      let b = buf("line1\nline3", be)
      b.insertLineNoUndo(1, "line2")
      check b.len == 3
      check b[0] == "line1"
      check b[1] == "line2"
      check b[2] == "line3"

suite "CrossBackend - Word Detection":
  for be in BufferBackend:
    test "getWordAtPosition [" & $be & "]":
      let b = buf("Hello World", be)
      check b.getWordAtPosition(BufferPosition(line: 0, column: 0)) == "Hello"
      check b.getWordAtPosition(BufferPosition(line: 0, column: 6)) == "World"

suite "CrossBackend - Matching Paren":
  for be in BufferBackend:
    test "findMatchingParenPosition forward [" & $be & "]":
      let b = buf("(hello)", be)
      let pos = b.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
      check pos.isSome
      check pos.get.column == 6

    test "findMatchingParenPosition multiline [" & $be & "]":
      let b = buf("(\n  content\n)", be)
      let pos = b.findMatchingParenPosition(BufferPosition(line: 0, column: 0))
      check pos.isSome
      check pos.get.line == 2
      check pos.get.column == 0

suite "CrossBackend - File Operations":
  for be in BufferBackend:
    test "saveFile and loadFile roundtrip [" & $be & "]":
      let testFile = "/tmp/moe_test_cross_" & $be & "_roundtrip.txt"
      defer:
        removeFile(testFile)

      let b1 = buf("", be)
      discard b1.insertText(
        BufferPosition(line: 0, column: 0), "Test content\nWith multiple lines"
      )
      discard b1.saveFile(testFile)

      let b2 = buf("", be)
      discard b2.loadFile(testFile)
      check b2.len == 2
      check b2[0] == "Test content"
      check b2[1] == "With multiple lines"

    test "loadFile [" & $be & "]":
      let testFile = "/tmp/moe_test_cross_" & $be & "_load.txt"
      defer:
        removeFile(testFile)
      writeFile(testFile, "Hello\nWorld\nTest\n")

      let b = buf("", be)
      discard b.loadFile(testFile)
      check b.len == 3
      check b[0] == "Hello"
      check b[1] == "World"
      check b[2] == "Test"

suite "CrossBackend - Performance Stats":
  for be in BufferBackend:
    test "estimateMemoryUsage [" & $be & "]":
      let b = buf("Hello World", be)
      check b.estimateMemoryUsage() > 0

    test "getPerformanceStats [" & $be & "]":
      let b = buf("Line1\nLine2", be)
      let stats = b.getPerformanceStats()
      check stats.backend == $be
      check stats.memoryUsage > 0
      check stats.length == 2

suite "CrossBackend - Complex Operation Sequences":
  for be in BufferBackend:
    test "edit-undo-edit-redo sequence [" & $be & "]":
      let b = buf("abc\ndef\nghi", be)

      discard b.insertText(BufferPosition(line: 0, column: 3), "X")
      check b[0] == "abcX"

      discard b.undo()
      check b[0] == "abc"

      discard b.insertText(BufferPosition(line: 1, column: 0), "Y")
      check b[1] == "Ydef"

      check b.redo().isErr

    test "insert-delete-insert across lines [" & $be & "]":
      let b = buf("start", be)

      discard b.insertText(BufferPosition(line: 0, column: 5), "\nmiddle\nend")
      check b.len == 3
      check b[0] == "start"
      check b[1] == "middle"
      check b[2] == "end"

      discard b.deleteLine(1)
      check b.len == 2
      check b[0] == "start"
      check b[1] == "end"

      discard b.insert(1, "new middle")
      check b.len == 3
      check b[1] == "new middle"

    test "deleteRange then undo [" & $be & "]":
      let b = buf("AAAA\nBBBB\nCCCC\nDDDD", be)

      discard b.deleteRange(
        BufferPosition(line: 0, column: 2), BufferPosition(line: 2, column: 1)
      )
      check b.len == 2

      discard b.undo()
      check b.len == 4
      check b[0] == "AAAA"
      check b[1] == "BBBB"
      check b[2] == "CCCC"
      check b[3] == "DDDD"

    test "many operations with undo/redo [" & $be & "]":
      let b = buf("hello", be)

      discard b.insertText(BufferPosition(line: 0, column: 5), " world")
      discard b.insertText(BufferPosition(line: 0, column: 11), "\nsecond line")
      discard b.deleteChar(BufferPosition(line: 0, column: 0))

      # Undo all
      discard b.undo()
      discard b.undo()
      discard b.undo()
      check b.len == 1
      check b[0] == "hello"

      # Redo all
      discard b.redo()
      discard b.redo()
      discard b.redo()
      check b.len == 2
      check b[0] == "ello world"
      check b[1] == "second line"

suite "setConfiguredBackend":
  test "default backend is GapBuffer":
    setConfiguredBackend(GapBuffer)
    let b = newTextBuffer("hello")
    check b.backendKind == GapBuffer

  test "setConfiguredBackend to SqrtDecomp":
    setConfiguredBackend(SqrtDecomp)
    let b = newTextBuffer("hello")
    check b.backendKind == SqrtDecomp
    # Reset to default
    setConfiguredBackend(GapBuffer)

  test "setConfiguredBackend affects subsequent newTextBuffer calls":
    setConfiguredBackend(SqrtDecomp)
    let b1 = newTextBuffer("first")
    check b1.backendKind == SqrtDecomp

    setConfiguredBackend(GapBuffer)
    let b2 = newTextBuffer("second")
    check b2.backendKind == GapBuffer

  test "explicit backend parameter overrides configuredBackend":
    setConfiguredBackend(GapBuffer)
    let b = newTextBuffer("hello", backend = SqrtDecomp)
    check b.backendKind == SqrtDecomp
    # Reset
    setConfiguredBackend(GapBuffer)
