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

## Tests for `gv` and the buffer's last Visual area.

import std/[unittest, options, strutils, deques]

import pkg/results

import
  ../src/moepkg/
    [buffer, types, modes, editor, config, key_bindings, handler, command_registry]
import visual_test_helper, clipboard_test_helper

proc pos(line, column: int): BufferPosition =
  BufferPosition(line: line, column: column)

proc area(start, cursor: BufferPosition, kind = vskLine): Option[VisualArea] =
  some(VisualArea(start: start, cursor: cursor, kind: kind))

suite "TextBuffer lastVisual":
  for backend in BufferBackend:
    test "follows lines inserted and deleted around it (" & $backend & ")":
      let b = newTextBuffer("a\nb\nc\nd\ne", backend = backend)
      b.lastVisual = area(pos(2, 0), pos(3, 0))

      check b.insert(0, "x").isOk
      check b.lastVisual == area(pos(3, 0), pos(4, 0))

      check b.insert(5, "y").isOk
      check b.lastVisual == area(pos(3, 0), pos(4, 0))

      check b.deleteLine(0).isOk
      check b.lastVisual == area(pos(2, 0), pos(3, 0))

    test "a deleted line moves its end to the deletion (" & $backend & ")":
      let b = newTextBuffer("a\nb\nc\nd\ne", backend = backend)
      b.lastVisual = area(pos(1, 0), pos(3, 0))

      check b.deleteLine(3).isOk
      check b.deleteLine(2).isOk
      check b.lastVisual == area(pos(1, 0), pos(2, 0))

    test "keeps its columns across an edit within a line (" & $backend & ")":
      let b = newTextBuffer("hello world", backend = backend)
      b.lastVisual = area(pos(0, 6), pos(0, 10), vskChar)

      check b.insertText(pos(0, 0), ">> ").isOk
      check b.lastVisual == area(pos(0, 6), pos(0, 10), vskChar)

    test "follows a line joined onto the one above (" & $backend & ")":
      let b = newTextBuffer("one\ntwo foo\nthree", backend = backend)
      b.lastVisual = area(pos(1, 4), pos(1, 6), vskChar)

      check b.deleteRange(pos(0, 3), pos(0, 3)).isOk
      check b.getLine(0) == "onetwo foo"
      check b.lastVisual == area(pos(0, 7), pos(0, 9), vskChar)

    test "moves the joined line's ends by the join column, as Vim does (" & $backend &
      ")":
      # Vim does not shift them back over the text deleted from that line.
      let b = newTextBuffer("one\nxtwo foo\nthree", backend = backend)
      b.lastVisual = area(pos(1, 5), pos(1, 7), vskChar)

      check b.deleteRange(pos(0, 1), pos(1, 1)).isOk
      check b.getLine(0) == "owo foo"
      check b.lastVisual == area(pos(0, 6), pos(0, 8), vskChar)

    test "an end in a deletion across lines keeps its column (" & $backend & ")":
      let b = newTextBuffer("one\ntwo\nthree", backend = backend)
      b.lastVisual = area(pos(0, 2), pos(1, 1), vskChar)

      check b.deleteRange(pos(0, 1), pos(1, 1)).isOk
      check b.lastVisual == area(pos(0, 2), pos(0, 2), vskChar)

    test "an end on a line a deletion drops goes to the joined line (" & $backend & ")":
      let b = newTextBuffer("abcd\nefgh\nijkl\nmnop", backend = backend)
      b.lastVisual = area(pos(1, 2), pos(2, 3), vskChar)

      check b.deleteRange(pos(0, 1), pos(2, 1)).isOk
      check b.getLine(0) == "akl"
      check b.lastVisual == area(pos(0, 3), pos(0, 4), vskChar)

    test "stays on its line across a line break, as Vim does (" & $backend & ")":
      let b = newTextBuffer("aaaaa foo", backend = backend)
      b.lastVisual = area(pos(0, 1), pos(0, 8), vskChar)

      check b.insertText(pos(0, 2), "\n").isOk
      check b.lastVisual == area(pos(0, 1), pos(0, 8), vskChar)

    test "follows the lines J joins (" & $backend & ")":
      let b = newTextBuffer("one\n  two foo\nthree", backend = backend)
      b.lastVisual = area(pos(0, 1), pos(1, 6), vskChar)

      check b.joinLines(0).isOk
      check b.getLine(0) == "one two foo"
      check b.lastVisual == area(pos(0, 1), pos(0, 8), vskChar)

    test "undo restores the area an edit was made with (" & $backend & ")":
      let b = newTextBuffer("a\nb\nc\nd", backend = backend)
      b.lastVisual = area(pos(1, 0), pos(2, 0))

      let txr = withTransaction(b, "delete"):
        check b.deleteLine(2).isOk
        check b.deleteLine(1).isOk
      check txr.isOk
      check b.lastVisual == area(pos(1, 0), pos(1, 0))

      check b.undo().isOk
      check b.lastVisual == area(pos(1, 0), pos(2, 0))

      check b.redo().isOk
      check b.lastVisual == area(pos(1, 0), pos(1, 0))

    if backend == PieceTable:
      test "a snapshot made with an area keeps no rows to replay":
        let b = newTextBuffer("a\nb\nc\nd", backend = backend)
        b.lastVisual = area(pos(1, 0), pos(2, 0))

        let txr = withTransaction(b, "delete"):
          check b.deleteLine(2).isOk
          check b.deleteLine(1).isOk
        check txr.isOk
        check b.undoStack.peekLast.kind == ckSnapshot
        check b.undoStack.peekLast.snapshotRows.len == 0

      test "rows kept for replay leave no capacity behind and are shared by undo":
        let b = newTextBuffer("a\nb\nc\nd\ne\nf", backend = backend)

        let txr = withTransaction(b, "delete"):
          for _ in 0 ..< 4:
            check b.deleteLine(1).isOk
        check txr.isOk
        check b.pendingSnapshotRows.capacity == 0
        let rows = b.undoStack.peekLast.snapshotRows
        check rows.len == 4

        check b.undo().isOk
        check b.redoStack.peekLast.snapshotRows.sharesStorage(rows)
        check b.redo().isOk
        check b.undoStack.peekLast.snapshotRows.sharesStorage(rows)

    test "rollback restores the area (" & $backend & ")":
      let b = newTextBuffer("a\nb\nc", backend = backend)
      b.lastVisual = area(pos(1, 0), pos(2, 0))

      check b.beginTransaction("delete").isOk
      check b.deleteLine(1).isOk
      check b.rollbackTransaction().isOk
      check b.lastVisual == area(pos(1, 0), pos(2, 0))

    test "a rewrite that gives its rows up keeps the area's lines (" & $backend & ")":
      let b = newTextBuffer("a\nb\nc\nd\ne", backend = backend)
      b.lastVisual = area(pos(1, 0), pos(3, 0))

      check b.replaceLines(0, 5, ["e", "d", "c", "b", "a"], keepRows = false).isOk
      check b.lastVisual == area(pos(1, 0), pos(3, 0))

      check b.replaceLines(0, 5, ["x", "y"], keepRows = false).isOk
      check b.lastVisual == area(pos(1, 0), pos(2, 0))

    test "undo moves an area saved after a rewrite (" & $backend & ")":
      let b = newTextBuffer("a\nb\nc\nd\ne", backend = backend)
      check b.replaceLines(1, 2, ["p", "q", "r"], keepRows = false).isOk
      b.lastVisual = area(pos(2, 0), pos(5, 0))

      check b.undo().isOk
      check b.lastVisual == area(pos(2, 0), pos(4, 0))

      check b.redo().isOk
      check b.lastVisual == area(pos(2, 0), pos(5, 0))

    test "undo moves an area saved after the edit (" & $backend & ")":
      let b = newTextBuffer("a\nb\nc\nd\ne\nf\ng", backend = backend)
      check b.deleteLine(0).isOk
      b.lastVisual = area(pos(3, 0), pos(4, 0))

      check b.undo().isOk
      check b.lastVisual == area(pos(4, 0), pos(5, 0))

      check b.redo().isOk
      check b.lastVisual == area(pos(3, 0), pos(4, 0))

    test "undo moves an area below a transaction's edits (" & $backend & ")":
      let b = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7\n8", backend = backend)
      let txr = withTransaction(b, "delete"):
        check b.deleteLine(0).isOk
        check b.deleteLine(3).isOk
      check txr.isOk
      b.lastVisual = area(pos(5, 0), pos(6, 0))

      check b.undo().isOk
      check b.lastVisual == area(pos(7, 0), pos(8, 0))

    test "undo moves an area between a transaction's edits (" & $backend & ")":
      let b = newTextBuffer("a\nb\nc\nd\ne\nf\ng", backend = backend)
      let txr = withTransaction(b, "insert"):
        check b.insert(1, "x").isOk
        check b.insert(6, "y").isOk
      check txr.isOk
      b.lastVisual = area(pos(4, 0), pos(4, 0))

      check b.undo().isOk
      check b.lastVisual == area(pos(3, 0), pos(3, 0))

      check b.redo().isOk
      check b.lastVisual == area(pos(4, 0), pos(4, 0))

    test "a line break with nothing after it leaves the area on its line (" & $backend &
      ")":
      let b = newTextBuffer("abc\n\nd", backend = backend)
      b.lastVisual = area(pos(0, 0), pos(0, 3), vskChar)

      check b.insertText(pos(0, 3), "\n").isOk
      check b.lastVisual == area(pos(0, 0), pos(0, 3), vskChar)

      b.lastVisual = area(pos(2, 0), pos(2, 0))
      check b.insertText(pos(2, 0), "\n").isOk
      check b.lastVisual == area(pos(2, 0), pos(2, 0))

    test "redo moves an end on a joined line onto the line above (" & $backend & ")":
      let b = newTextBuffer("\ntwo\nthree", backend = backend)
      check b.deleteRange(pos(0, 0), pos(0, 0)).isOk
      check b.getLine(0) == "two"
      check b.undo().isOk
      b.lastVisual = area(pos(1, 1), pos(1, 2), vskChar)

      check b.redo().isOk
      check b.lastVisual == area(pos(0, 1), pos(0, 2), vskChar)

    test "redo moves an end on a row a deletion across lines removed (" & $backend & ")":
      let b = newTextBuffer("aa\nbb\ncc\ndd", backend = backend)
      check b.deleteRange(pos(1, 1), pos(2, 0)).isOk
      check b.undo().isOk
      b.lastVisual = area(pos(0, 0), pos(2, 1), vskChar)

      check b.redo().isOk
      check b.getLine(1) == "bc"
      check b.lastVisual == area(pos(0, 0), pos(1, 1), vskChar)

    test "redo follows lines inserted and deleted in one transaction (" & $backend & ")":
      let b = newTextBuffer("0\n1\n2\n3\n4\n5\n6\n7", backend = backend)
      let txr = withTransaction(b, "edit"):
        check b.insert(5, "x").isOk
        check b.insert(6, "y").isOk
        check b.deleteLine(7).isOk
      check txr.isOk
      check b.undo().isOk
      b.lastVisual = area(pos(0, 0), pos(5, 0))

      check b.redo().isOk
      check b.lastVisual == area(pos(0, 0), pos(7, 0))

    test "a rewrite across lines that keeps the breaks keeps the area (" & $backend & ")":
      let b = newTextBuffer("a1 bcd\n  e2 fgh\nijk", backend = backend)
      b.lastVisual = area(pos(0, 3), pos(1, 4), vskChar)

      let txr = withTransaction(b, "uppercase"):
        check b.transformRange(pos(0, 3), pos(1, 4), "uppercase", toUpperAscii).isOk
      check txr.isOk
      check b.getLine(0) == "a1 BCD"
      check b.getLine(1) == "  E2 fgh"
      check b.lastVisual == area(pos(0, 3), pos(1, 4), vskChar)

      check b.undo().isOk
      check b.getLine(0) == "a1 bcd"
      check b.lastVisual == area(pos(0, 3), pos(1, 4), vskChar)

      check b.redo().isOk
      check b.getLine(1) == "  E2 fgh"
      check b.lastVisual == area(pos(0, 3), pos(1, 4), vskChar)

    test "a rewrite through the end of a line keeps the next line (" & $backend & ")":
      let b = newTextBuffer("abc\ndef\nghi", backend = backend)
      b.lastVisual = area(pos(1, 0), pos(1, 2), vskChar)

      let txr = withTransaction(b, "uppercase"):
        check b.transformRange(pos(0, 1), pos(0, 3), "uppercase", toUpperAscii).isOk
      check txr.isOk
      check b.len == 3
      check b.getLine(0) == "aBC"
      check b.getLine(1) == "def"
      check b.lastVisual == area(pos(1, 0), pos(1, 2), vskChar)

    if backend != PieceTable:
      test "a failed rollback still restores the area (" & $backend & ")":
        let b = newTextBuffer("a\nb\nc\nd", backend = backend)
        b.lastVisual = area(pos(1, 0), pos(2, 0))

        check b.beginTransaction("insert").isOk
        check b.insert(0, "x").isOk
        b.currentTransaction.get.changes.add BufferChange(
          kind: ckDeleteLine, deleteLineIdx: 99, deletedLineText: "z"
        )
        check b.rollbackTransaction().isErr
        check b.lastVisual == area(pos(1, 0), pos(2, 0))

proc newTestEditor(content: string): Editor =
  result = newEditor(newEditorConfig())
  let buf = newTextBuffer(content)
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.syncActiveWindow()
  result.state.mode = EditorMode.Normal

proc press(e: Editor, keys: varargs[string]) =
  for key in keys:
    check e.handleKeyCombo(parseKeyCombo(key).get)

proc selection(e: Editor): tuple[start, current: BufferPosition] =
  check e.state.visualSelection.active
  (e.state.visualSelection.start, e.state.visualSelection.current)

suite "gv":
  test "reselects the last area in its mode with the cursor on the same end":
    let e = newTestEditor("one\ntwo\nthree\nfour")
    e.press("j", "V", "j", "Esc", "g", "g")
    check e.state.mode == EditorMode.Normal

    e.press("g", "v")

    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(1, 0), pos(2, 0))
    check e.cursor == pos(2, 0)

    e.press("Esc")
    check e.state.mode == EditorMode.Normal

  test "keeps the cursor on the anchor's left after o":
    let e = newTestEditor("hello world")
    e.press("w", "v", "e", "o", "Esc", "0", "g", "v")

    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(0, 10), pos(0, 6))
    check e.cursor == pos(0, 6)

  test "restores a block selection":
    let e = newTestEditor("abc\ndef\nghi")
    e.press("l", "C-v", "j", "l", "Esc", "G", "g", "v")

    check e.state.mode == EditorMode.VisualBlock
    check e.selection == (pos(0, 1), pos(1, 2))

  test "from Visual mode exchanges the current and previous areas":
    let e = newTestEditor("one\ntwo\nthree")
    e.press("V", "j", "Esc", "G", "v", "l")

    e.press("g", "v")
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(0, 0), pos(1, 0))

    e.press("g", "v")
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(2, 0), pos(2, 1))

    e.press("Esc")
    check e.state.mode == EditorMode.Normal
    check not e.state.visualSelection.active

  test "reselects the area an operator worked on":
    let e = newTestEditor("a\nb\nc")
    e.press("V", "j", ">")
    check e.state.mode == EditorMode.Normal

    e.press("g", "v")
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(0, 0), pos(1, 0))

  test "follows lines opened above the area":
    let e = newTestEditor("aa\nbb\ncc")
    e.press("j", "v", "l", "Esc", "g", "g", "O", "x", "Esc", "g", "v")

    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(2, 0), pos(2, 1))

  test "after deleting the selected lines, selects the line that followed":
    let e = newTestEditor("a\nb\nc\nd")
    e.press("j", "V", "j", "d", "g", "v")

    check e.activeBuffer.len == 2
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(1, 0), pos(1, 0))

  test "after undo, reselects the area the undone change was made with":
    let e = newTestEditor("a\nb\nc\nd")
    e.press("j", "V", "j", "d", "g", "v", "Esc", "u", "g", "v")

    check e.activeBuffer.len == 4
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(1, 0), pos(2, 0))

  test "after a Visual put, selects the put text":
    let e = newTestEditor("ab cdef")
    e.press("v", "l", "y", "w", "v", "e", "p")
    check e.activeBuffer.getLine(0) == "ab ab"

    e.press("g", "v")
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(0, 3), pos(0, 4))

  test "after a linewise Visual put, selects the put lines":
    let e = newTestEditor("x\ny\nz")
    e.press("y", "y", "j", "V", "j", "p")
    check e.activeBuffer.len == 2

    e.press("g", "v")
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(1, 0), pos(1, 0))

  test "clamps an area past the end of its line":
    let e = newTestEditor("aaaa\nbb")
    e.press("l", "l", "v", "l", "Esc", "0", "D", "g", "v")

    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(0, 0), pos(0, 0))

  test "fails when the area starts past the last line":
    let e = newTestEditor("a\nb\nc")
    e.press("G", "V", "d", "g", "v")

    check e.state.mode == EditorMode.Normal
    check not e.state.visualSelection.active

  test "fails without a previous area":
    let e = newTestEditor("abc")
    e.press("g", "v")

    check e.state.mode == EditorMode.Normal
    check not e.state.visualSelection.active
    check e.state.statusMessage.contains("No previous visual selection")

  test "keeps the area on a line Ctrl-A rewrites":
    let e = newTestEditor("1\n2\n3\n4")
    e.press("V", "j", "j", "Esc", "g", "g", "C-a", "g", "v")

    check e.activeBuffer.getLine(0) == "2"
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(0, 0), pos(2, 0))

  test "after a linewise change, starts on the changed line":
    let e = newTestEditor("a\nb\nc\nd")
    e.press("V", "j", "c", "f", "o", "o", "Esc", "g", "v")

    check e.activeBuffer.getLine(0) == "foo"
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(0, 0), pos(1, 0))

  test "after deleting every line, selects the line left":
    let e = newTestEditor("a\nb\nc")
    e.press("V", "G", "d", "g", "v")

    check e.activeBuffer.len == 1
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(0, 0), pos(0, 0))

  test "deleting every line drops the marks on the last one":
    let e = newTestEditor("abc\ndef\nghi")
    e.press("l", "m", "a")
    e.activeBuffer.toggleBookmark(0)
    e.press("V", "G", "d")

    check e.activeBuffer.len == 1
    check e.activeBuffer.namedMarks['a'].isNone
    check e.activeBuffer.bookmarks.len == 0

  test "after a blockwise put, selects the put text blockwise":
    let e = newTestEditor("ab\ncd\n0123456789\n0123456789")
    e.press("v", "j", "l", "y", "j", "j")
    for _ in 0 ..< 5:
      e.press("l")
    e.press("C-v", "j", "p")
    check e.activeBuffer.getLine(2) == "01234ab"
    check e.activeBuffer.getLine(3) == "cd6789"

    e.press("g", "v")
    check e.state.mode == EditorMode.VisualBlock
    check e.selection == (pos(2, 5), pos(3, 1))

  test "vertical motion after gv keeps the column gv moved to":
    let e = newTestEditor("0123456789ab\n0123456789ab\n0123456789ab")
    for _ in 0 ..< 10:
      e.press("l")
    e.press("v", "Esc", "0", "l", "l", "j", "g", "v", "Esc", "j")

    check e.cursor == pos(1, 10)

  test "reselects the area yank worked on":
    let e = newTestEditor("abc")
    e.press("v", "l", "y", "g", "v")

    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(0, 0), pos(0, 1))

  test "reselects the area a fold was made from":
    let e = newTestEditor("a\nb\nc")
    e.press("V", "j", "z", "f", "G", "g", "v")

    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(0, 0), pos(1, 0))

  test "an edit that stays in Visual records the previous area for undo":
    let e = newTestEditor("1\n2\n3")
    e.press("V", "j", "Esc", "G", "v", "C-a")
    check e.state.mode == EditorMode.Visual
    check e.activeBuffer.getLine(2) == "4"

    e.press("Esc", "u", "g", "v")
    check e.activeBuffer.getLine(2) == "3"
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(0, 0), pos(1, 0))

  test "after J, reselects the text joined onto the line":
    let e = newTestEditor("one\ntwo foo\nthree")
    e.press("j", "w", "v", "e", "Esc", "k", "J", "g", "v")

    check e.activeBuffer.getLine(0) == "one two foo"
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(0, 8), pos(0, 10))

  test "after o, reselects the area on its line":
    let e = newTestEditor("a\n\nc")
    e.press("j", "V", "Esc", "o", "Esc", "g", "v")

    check e.activeBuffer.len == 4
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(1, 0), pos(1, 0))

  test "after a change across lines that keeps them, reselects the same area":
    for keys in [@["U"], @["u"], @["~"], @["r", "z"]]:
      let e = newTestEditor("a1 bcd\n  e2 fgh\nijk")
      e.press("l", "l", "l", "v", "j", "l")
      e.press(keys)
      check e.state.mode == EditorMode.Normal

      e.press("g", "v")
      check e.state.mode == EditorMode.Visual
      check e.selection == (pos(0, 3), pos(1, 4))

  test "undo of a change across lines returns to where it started":
    for keys in [@["U"], @["~"]]:
      let e = newTestEditor("abcdefgh\nabcdefgh\nabcdefgh")
      e.press("j", "l", "l", "l", "v", "j")
      e.press(keys)
      e.press("G", "$", "u")

      check e.activeBuffer.getLine(1) == "abcdefgh"
      check e.cursor == pos(1, 3)

  test "after redoing a join made before any selection, selects the joined text":
    let e = newTestEditor("\ntwo\nthree")
    e.press("d", "w", "u", "j", "l", "v", "l", "Esc", "C-r")
    check e.activeBuffer.getLine(0) == "two"

    e.press("g", "v")
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(0, 1), pos(0, 2))

  test "a line break before the area leaves it on its line, as Vim does":
    let e = newTestEditor("aaaaa foo")
    e.press("w", "v", "e", "Esc", "0", "l", "l", "i", "Enter", "Esc")

    check e.activeBuffer.getLine(1) == "aaa foo"
    check e.activeBuffer.lastVisual == area(pos(0, 6), pos(0, 8), vskChar)

    e.press("g", "v")

    # Vim selects one past the end of the shortened line.
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(0, 2), pos(0, 2))

  test "a binding that switches out of Visual mode saves the area":
    let e = newTestEditor("one\ntwo\nthree")
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Visual, "Q", "switch-to-normal"
    ) == ""
    e.press("j", "v", "j", "Q")
    check e.state.mode == EditorMode.Normal
    check not e.state.visualSelection.active

    e.press("g", "g", "g", "v")
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(1, 0), pos(2, 0))

  test "a command alias run from Visual mode saves the area":
    let e = newTestEditor("one\ntwo\nthree")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Visual, "K", "bfirst") == ""
    e.press("j", "v", "j", "K")
    check e.state.mode == EditorMode.Normal
    check not e.state.visualSelection.active

    e.press("g", "g", "g", "v")
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(1, 0), pos(2, 0))

  test "a command that fails and stays in Visual mode leaves the area alone":
    let e = newTestEditor("one\ntwo\nthree")
    e.state.config.clipboard.enable = false
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Visual, "Q", "clipboard-cut"
    ) == ""
    e.press("V", "Esc", "G", "v", "l", "Q")
    check e.activeBuffer.getLine(2) == "three"
    check e.state.mode == EditorMode.Visual

    e.press("g", "v")
    check e.state.mode == EditorMode.VisualLine
    check e.selection == (pos(0, 0), pos(0, 0))

  test "a cut on a read-only buffer copies nothing and saves the area":
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        let e = newTestEditor("one\ntwo\nthree")
        e.state.config.clipboard = ClipboardConfig(enable: true, tool: cbtXclip)
        check e.keyBindingRegistry.addRuntimeMapping(
          EditorMode.Visual, "Q", "clipboard-cut"
        ) == ""
        e.activeBuffer.readOnly = true
        e.press("j", "v", "l", "Q")

        check readFile(clipboardFilePath(fakeDir)) == fakeClipboardContent
        check e.activeBuffer.getLine(1) == "two"
        check e.state.statusMessage == "Buffer is read-only"
        check e.state.mode == EditorMode.Normal

        e.press("g", "g", "g", "v")
        check e.state.mode == EditorMode.Visual
        check e.selection == (pos(1, 0), pos(1, 1))
      finally:
        removeFakeClipboardTool(fakeDir)

  test "switching tabs from Visual mode saves the area":
    let e = newTestEditor("one\ntwo\nthree")
    let other = newTextBuffer("other")
    e.addBuffer(e.activeBuffer)
    e.addBuffer(other)
    e.addBufferToWindowList(other)
    e.press("j", "v", "l")
    check e.switchToWindowBuffer(1)
    check e.state.mode == EditorMode.Normal

    check e.switchToWindowBuffer(0)
    e.press("g", "v")
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(1, 0), pos(1, 1))

  test "after an operator on gn, selects the match":
    let e = newTestEditor("foo bar\nbaz qux\nfoo end")
    e.press("j", "v", "l", "Esc", "g", "g", "/", "f", "o", "o", "Enter")
    e.press("c", "g", "n", "X", "Esc", "g", "v")

    check e.activeBuffer.getLine(2) == "X end"
    check e.state.mode == EditorMode.Visual
    check e.selection == (pos(2, 0), pos(2, 2))

  test "an operator gn does not run leaves the area alone":
    for op in [@["g", "U"], @[">"]]:
      let e = newTestEditor("foo bar\nbaz qux\nfoo end")
      e.press("j", "v", "l", "Esc", "g", "g", "/", "f", "o", "o", "Enter")
      e.press(op)
      e.press("g", "n")
      check e.activeBuffer.getLine(2) == "foo end"

      e.press("g", "v")
      check e.state.mode == EditorMode.Visual
      check e.selection == (pos(1, 0), pos(1, 1))

  test "run as a command from Normal mode, returns to Normal on Esc":
    let e = newTestEditor("one\ntwo")
    e.press("V", "Esc")
    e.state.previousMode = EditorMode.Insert
    let ctx = CommandContext(buffer: e.activeBuffer, state: e.state)
    check e.commandRegistry.execute(ctx, "visual.reselect", @[]).isOk
    check e.state.mode == EditorMode.VisualLine

    e.press("Esc")
    check e.state.mode == EditorMode.Normal

  test "cancels a pending operator":
    let e = newTestEditor("abc")
    e.press("v", "l", "Esc", "d", "g", "v", "l")

    check e.state.mode == EditorMode.Normal
    check e.activeBuffer.getLine(0) == "abc"
    check e.state.pendingInput.pendingOperator.isNone
    check e.cursor == pos(0, 2)
