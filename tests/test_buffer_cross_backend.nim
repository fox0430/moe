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

import std/[unittest, os, options, strutils, deques]

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

    test "lines iterator matches getLine [" & $be & "]":
      for content in [
        "", "single", "Line1\nLine2\nLine3", "Hello\nあいう\n日本語",
        "trailing\n\n\n", "\n\nleading",
      ]:
        let b = buf(content, be)
        var collected = newSeq[string]()
        for line in b.lines:
          collected.add(line)
        check collected.len == b.len
        for i in 0 ..< b.len:
          check collected[i] == b.getLine(i)

    test "lines iterator matches getLine after edits [" & $be & "]":
      # Edits fragment tree/block backends into multiple pieces, exercising
      # the iterator's multi-segment traversal rather than the fresh-buffer path.
      let b = buf("Line1\nLine2\nLine3", be)
      discard b.insertText(BufferPosition(line: 1, column: 5), "あ\ninserted")
      discard b.deleteLine(0)
      discard b.insertText(BufferPosition(line: 0, column: 0), "head ")
      var collected = newSeq[string]()
      for line in b.lines:
        collected.add(line)
      check collected.len == b.len
      for i in 0 ..< b.len:
        check collected[i] == b.getLine(i)

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

    test "deleteRange join line from end [" & $be & "]":
      let b = buf("foo\nbar", be)
      discard b.deleteRange(
        BufferPosition(line: 0, column: 3), BufferPosition(line: 0, column: 3)
      )
      check b.len == 1
      check b[0] == "foobar"

    test "deleteRange at end of last line [" & $be & "]":
      let b = buf("foo", be)
      discard b.deleteRange(
        BufferPosition(line: 0, column: 3), BufferPosition(line: 0, column: 3)
      )
      check b.len == 1
      check b[0] == "foo"

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

    test "undo deleteRange join line from end [" & $be & "]":
      let b = buf("foo\nbar", be)
      discard b.deleteRange(
        BufferPosition(line: 0, column: 3), BufferPosition(line: 0, column: 3)
      )
      discard b.undo()
      check b.len == 2
      check b[0] == "foo"
      check b[1] == "bar"

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

    test "undo deleteLine restores lineMarkers at correct positions [" & $be & "]":
      let b = buf("aaa\nbbb\nccc", be)
      b.setLineMarker(2, SyntaxError)
      check b.lineMarkers[2] == some(SyntaxError)

      discard b.deleteLine(0)
      check b.lineMarkers.len == 2
      check b.lineMarkers[1] == some(SyntaxError)

      discard b.undo()
      check b.len == 3
      check b[0] == "aaa"
      check b[1] == "bbb"
      check b[2] == "ccc"
      check b.lineMarkers[0].isNone
      check b.lineMarkers[1].isNone
      check b.lineMarkers[2] == some(SyntaxError)

    test "undo deleteLine (variant) restores lineMarkers at correct positions [" & $be &
      "]":
      let b = buf("aaa\nbbb\nccc", be)
      b.setLineMarker(0, SyntaxError)
      b.setLineMarker(2, Bookmark)
      check b.lineMarkers[0] == some(SyntaxError)
      check b.lineMarkers[2] == some(Bookmark)

      discard b.deleteLine(1)
      check b.lineMarkers.len == 2
      check b.lineMarkers[0] == some(SyntaxError)
      check b.lineMarkers[1] == some(Bookmark)

      discard b.undo()
      check b.len == 3
      check b[0] == "aaa"
      check b[1] == "bbb"
      check b[2] == "ccc"
      check b.lineMarkers[0] == some(SyntaxError)
      check b.lineMarkers[1].isNone
      check b.lineMarkers[2] == some(Bookmark)

    test "undo insertLine restores lineMarkers at correct positions [" & $be & "]":
      let b = buf("aaa\nccc", be)
      b.setLineMarker(1, GitChanged)
      check b.lineMarkers[1] == some(GitChanged)

      discard b.insert(1, "bbb")
      check b.lineMarkers.len == 3
      check b.lineMarkers[2] == some(GitChanged)

      discard b.undo()
      check b.len == 2
      check b[0] == "aaa"
      check b[1] == "ccc"
      check b.lineMarkers[0].isNone
      check b.lineMarkers[1] == some(GitChanged)

    test "redo after undo restores lineMarkers to post-edit state [" & $be & "]":
      let b = buf("aaa\nbbb\nccc", be)
      b.setLineMarker(2, Bookmark)
      discard b.deleteLine(0)
      discard b.undo()
      check b.lineMarkers[2] == some(Bookmark)
      discard b.redo()
      check b.len == 2
      check b[0] == "bbb"
      check b[1] == "ccc"
      check b.lineMarkers[0].isNone
      check b.lineMarkers[1] == some(Bookmark)

  for be in BufferBackend:
    test "undo multi-line insertText shifts bookmarks back [" & $be & "]":
      let b = buf("l0\nl1\nl2\nl3\nl4", be)
      b.bookmarks = @[3]
      discard b.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
      check b.bookmarks == @[5]
      discard b.undo()
      check b.len == 5
      check b.bookmarks == @[3]

    test "undo/redo cycle does not drift bookmarks [" & $be & "]":
      let b = buf("l0\nl1\nl2\nl3\nl4", be)
      b.bookmarks = @[3]
      discard b.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
      for _ in 0 ..< 3:
        discard b.undo()
        check b.bookmarks == @[3]
        discard b.redo()
        check b.bookmarks == @[5]

    test "undo multi-line insertText shifts folds back [" & $be & "]":
      let b = buf("l0\nl1\nl2\nl3\nl4", be)
      b.foldState.folds.add(Fold(startLine: 3, endLine: 4, collapsed: false))
      discard b.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
      check b.foldState.folds[0].startLine == 5
      check b.foldState.folds[0].endLine == 6
      discard b.undo()
      check b.foldState.folds[0].startLine == 3
      check b.foldState.folds[0].endLine == 4

    test "undo insertLine restores bookmarks [" & $be & "]":
      let b = buf("l0\nl1\nl2", be)
      b.bookmarks = @[2]
      discard b.insert(0, "new")
      check b.bookmarks == @[3]
      discard b.undo()
      check b.len == 3
      check b.bookmarks == @[2]
      check b.hasBookmark(2)

    test "redo insertLine reshifts bookmarks [" & $be & "]":
      let b = buf("l0\nl1\nl2", be)
      b.bookmarks = @[2]
      discard b.insert(0, "new")
      discard b.undo()
      discard b.redo()
      check b.bookmarks == @[3]

    test "undo deleteLine restores bookmarks [" & $be & "]":
      let b = buf("l0\nl1\nl2", be)
      b.bookmarks = @[2]
      discard b.deleteLine(0)
      check b.bookmarks == @[1]
      discard b.undo()
      check b.bookmarks == @[2]

    test "transaction rollback restores bookmarks [" & $be & "]":
      let b = buf("l0\nl1\nl2", be)
      b.bookmarks = @[2]
      discard b.beginTransaction("test")
      discard b.insertText(BufferPosition(line: 0, column: 0), "a\nb\nc")
      check b.bookmarks == @[4]
      discard b.rollbackTransaction()
      check b.len == 3
      check b.bookmarks == @[2]

  # deleteRange single-line branch that ends past line end joins with next line.
  # This still shrinks line count by 1 and must shift folds/bookmarks like the
  # multi-line branch.
  for be in BufferBackend:
    test "deleteRange single-line joined with next shifts bookmarks [" & $be & "]":
      let b = buf("abc\n\ndef", be)
      b.bookmarks = @[2]
      discard b.deleteRange(
        BufferPosition(line: 0, column: 2), BufferPosition(line: 0, column: 4)
      )
      check b.len == 2
      check b[0] == "ab"
      check b[1] == "def"
      check b.bookmarks == @[1]

    test "deleteRange single-line joined with next shifts folds [" & $be & "]":
      let b = buf("abc\n\ndef\nghi", be)
      b.foldState.folds.add(Fold(startLine: 2, endLine: 3, collapsed: false))
      discard b.deleteRange(
        BufferPosition(line: 0, column: 2), BufferPosition(line: 0, column: 4)
      )
      check b.len == 3
      check b.foldState.folds[0].startLine == 1
      check b.foldState.folds[0].endLine == 2

    test "deleteRange single-line joined with next drops bookmark on merged line [" & $be &
      "]":
      let b = buf("abc\nlost\nkeep", be)
      b.bookmarks = @[1, 2]
      discard b.deleteRange(
        BufferPosition(line: 0, column: 2), BufferPosition(line: 0, column: 4)
      )
      check b.len == 2
      check b[0] == "ablost"
      check b[1] == "keep"
      check b.bookmarks == @[1]

    test "deleteRange single-line joined undo/redo cycle does not drift bookmarks [" &
      $be & "]":
      let b = buf("abc\n\ndef", be)
      b.bookmarks = @[2]
      discard b.deleteRange(
        BufferPosition(line: 0, column: 2), BufferPosition(line: 0, column: 4)
      )
      check b.bookmarks == @[1]
      for _ in 0 ..< 3:
        discard b.undo()
        check b.bookmarks == @[2]
        discard b.redo()
        check b.bookmarks == @[1]

    test "deleteRange single-line joined undo/redo cycle does not drift folds [" & $be &
      "]":
      let b = buf("abc\n\ndef\nghi", be)
      b.foldState.folds.add(Fold(startLine: 2, endLine: 3, collapsed: false))
      discard b.deleteRange(
        BufferPosition(line: 0, column: 2), BufferPosition(line: 0, column: 4)
      )
      check b.foldState.folds[0].startLine == 1
      check b.foldState.folds[0].endLine == 2
      for _ in 0 ..< 3:
        discard b.undo()
        check b.foldState.folds[0].startLine == 2
        check b.foldState.folds[0].endLine == 3
        discard b.redo()
        check b.foldState.folds[0].startLine == 1
        check b.foldState.folds[0].endLine == 2

suite "CrossBackend - replaceLine Undo/Redo":
  for be in BufferBackend:
    test "undo replaceLine [" & $be & "]":
      let b = buf("hello\nworld", be)
      discard b.replaceLine(0, "HELLO")
      check b[0] == "HELLO"
      discard b.undo()
      check b[0] == "hello"

    test "redo replaceLine [" & $be & "]":
      let b = buf("hello\nworld", be)
      discard b.replaceLine(0, "HELLO")
      discard b.undo()
      discard b.redo()
      check b[0] == "HELLO"

    test "replaceLine out of bounds [" & $be & "]":
      let b = buf("hello", be)
      check b.replaceLine(-1, "x").isErr
      check b.replaceLine(1, "x").isErr
      check b[0] == "hello"

    test "replaceLine isModified [" & $be & "]":
      let b = buf("hello", be)
      check b.isModified == false
      discard b.replaceLine(0, "HELLO")
      check b.isModified == true
      discard b.undo()
      check b.isModified == false

    test "transaction with replaceLine [" & $be & "]":
      let b = buf("aaa\nbbb\nccc", be)
      discard b.beginTransaction("test")
      discard b.replaceLine(0, "AAA")
      discard b.replaceLine(1, "BBB")
      discard b.commitTransaction()
      check b[0] == "AAA"
      check b[1] == "BBB"

      discard b.undo()
      check b[0] == "aaa"
      check b[1] == "bbb"

      discard b.redo()
      check b[0] == "AAA"
      check b[1] == "BBB"

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
      let testFile = getTempDir() / "moe_test_cross_" & $be & "_roundtrip.txt"
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
      let testFile = getTempDir() / "moe_test_cross_" & $be & "_load.txt"
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

suite "PieceTable - Snapshot Undo/Redo Integration":
  test "undo stack contains ckSnapshot entries":
    let b = buf("Hello", PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), " World")
    check b.undoStack.len == 1
    check b.undoStack.peekLast.kind == ckSnapshot

  test "redo stack contains ckSnapshot entries after undo":
    let b = buf("Hello", PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), " World")
    discard b.undo()
    check b[0] == "Hello"
    check b.redoStack.len == 1
    check b.redoStack.peekLast.kind == ckSnapshot

  test "undo stack restored after redo":
    let b = buf("Hello", PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), " World")
    discard b.undo()
    discard b.redo()
    check b[0] == "Hello World"
    check b.undoStack.len == 1
    check b.undoStack.peekLast.kind == ckSnapshot

  test "multiple edits each create separate ckSnapshot entries":
    let b = buf("abc", PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 3), "1")
    discard b.insertText(BufferPosition(line: 0, column: 4), "2")
    discard b.deleteChar(BufferPosition(line: 0, column: 0))
    check b.undoStack.len == 3
    for i in 0 ..< b.undoStack.len:
      check b.undoStack[i].kind == ckSnapshot

  test "non-PieceTable backends still use operation-based undo":
    let b = buf("Hello", GapBuffer)
    discard b.insertText(BufferPosition(line: 0, column: 5), " World")
    check b.undoStack.len == 1
    check b.undoStack.peekLast.kind == ckInsertText

  test "lineMarkers preserved across undo/redo":
    let b = buf("line0\nline1\nline2", PieceTable)
    b.setLineMarker(1, SyntaxError)
    check b.lineMarkers[1] == some(SyntaxError)

    # Edit and record snapshot (captures markers with SyntaxError on line 1)
    discard b.replaceLine(0, "CHANGED")
    check b[0] == "CHANGED"

    # Clear marker after edit
    b.clearLineMarker(1)
    check b.lineMarkers[1].isNone

    # Undo should restore the snapshot (which had SyntaxError on line 1)
    discard b.undo()
    check b[0] == "line0"
    check b.lineMarkers[1] == some(SyntaxError)

  test "foldState preserved across undo/redo":
    let b = buf("line0\nline1\nline2\nline3", PieceTable)
    b.foldState.folds.add(Fold(startLine: 0, endLine: 2, collapsed: true))
    check b.foldState.folds.len == 1

    # Edit captures snapshot with fold
    discard b.replaceLine(0, "CHANGED")

    # Remove fold after edit
    b.foldState.folds = @[]
    check b.foldState.folds.len == 0

    # Undo should restore the snapshot (which had the fold)
    discard b.undo()
    check b[0] == "line0"
    check b.foldState.folds.len == 1
    check b.foldState.folds[0].startLine == 0
    check b.foldState.folds[0].endLine == 2
    check b.foldState.folds[0].collapsed == true

  test "transaction creates single ckSnapshot entry":
    let b = buf("aaa\nbbb\nccc", PieceTable)
    discard b.beginTransaction("test")
    discard b.replaceLine(0, "AAA")
    discard b.replaceLine(1, "BBB")
    discard b.replaceLine(2, "CCC")
    discard b.commitTransaction()

    # Should be a single snapshot entry, not a ckTransaction
    check b.undoStack.len == 1
    check b.undoStack.peekLast.kind == ckSnapshot

    # Undo restores all three lines at once
    discard b.undo()
    check b[0] == "aaa"
    check b[1] == "bbb"
    check b[2] == "ccc"

  test "transaction redo after undo":
    let b = buf("aaa\nbbb", PieceTable)
    discard b.beginTransaction("test")
    discard b.replaceLine(0, "AAA")
    discard b.replaceLine(1, "BBB")
    discard b.commitTransaction()

    discard b.undo()
    check b[0] == "aaa"
    check b[1] == "bbb"

    discard b.redo()
    check b[0] == "AAA"
    check b[1] == "BBB"

  test "rollback uses O(1) snapshot restore":
    let b = buf("Hello\nWorld", PieceTable)
    discard b.beginTransaction("test")
    discard b.replaceLine(0, "HELLO")
    discard b.replaceLine(1, "WORLD")
    discard b.rollbackTransaction()

    check b[0] == "Hello"
    check b[1] == "World"
    # Rollback should not push anything to undo stack
    check b.undoStack.len == 0

  test "rollback preserves lineMarkers":
    let b = buf("line0\nline1", PieceTable)
    b.setLineMarker(0, GitAdded)

    discard b.beginTransaction("test")
    discard b.replaceLine(0, "CHANGED")
    b.setLineMarker(0, SyntaxError)
    discard b.rollbackTransaction()

    check b[0] == "line0"
    check b.lineMarkers[0] == some(GitAdded)

  test "snapshot cursorPos tracks change position":
    let b = buf("Hello\nWorld", PieceTable)
    discard b.insertText(BufferPosition(line: 1, column: 5), "!")
    let entry = b.undoStack.peekLast
    check entry.kind == ckSnapshot
    check entry.snapshotCursorPos == BufferPosition(line: 1, column: 5)

  test "undo/redo cycle preserves content across multiple rounds":
    let b = buf("original", PieceTable)
    discard b.replaceLine(0, "modified")
    check b[0] == "modified"

    # Round 1
    discard b.undo()
    check b[0] == "original"
    discard b.redo()
    check b[0] == "modified"

    # Round 2
    discard b.undo()
    check b[0] == "original"
    discard b.redo()
    check b[0] == "modified"

    # Round 3
    discard b.undo()
    check b[0] == "original"

  test "new edit after undo clears redo stack":
    let b = buf("abc", PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 3), "1")
    discard b.undo()
    check b.redoStack.len == 1

    discard b.insertText(BufferPosition(line: 0, column: 3), "2")
    check b.redoStack.len == 0
    check b[0] == "abc2"

  test "pendingSnapshot cleared on error":
    let b = buf("Hello", PieceTable)
    # Attempt invalid operation
    let r = b.deleteChar(BufferPosition(line: 0, column: 99))
    check r.isErr
    check b.pendingSnapshot.isNone
    # Buffer should be unchanged
    check b[0] == "Hello"
    check b.undoStack.len == 0
