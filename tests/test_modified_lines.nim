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

import std/[options, unittest]

import pkg/celina

import ../src/moepkg/[buffer, sidebar]

suite "ModifiedLines - Basic Tracking":
  test "New buffer has all lines unmodified":
    let b = newTextBuffer("line1\nline2\nline3")
    for i in 0 ..< b.modifiedLines.len:
      check b.modifiedLines[i] == lmkUnmodified

  test "Editing a line marks it as modified":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.modifiedLines[0] == lmkModified

  test "Deleting a character marks line as modified":
    let b = newTextBuffer("hello")
    discard b.deleteChar(BufferPosition(line: 0, column: 4))
    check b.modifiedLines[0] == lmkModified

  test "Inserting a new line marks it as inserted":
    let b = newTextBuffer("line1")
    discard b.insert(1, "line2")
    check b.modifiedLines[1] == lmkInserted

  test "Inserting text with newline marks original as modified and new as inserted":
    let b = newTextBuffer("hello world")
    discard b.insertText(BufferPosition(line: 0, column: 5), "\nnew")
    # Original line split → modified
    check b.modifiedLines[0] == lmkModified
    # New line → inserted
    check b.modifiedLines[1] == lmkInserted

  test "Multiple newlines: original modified, all new lines inserted":
    let b = newTextBuffer("start end")
    discard b.insertText(BufferPosition(line: 0, column: 5), "\nline2\nline3\nline4")
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[1] == lmkInserted
    check b.modifiedLines[2] == lmkInserted
    check b.modifiedLines[3] == lmkInserted

  test "Editing an inserted line keeps it as inserted":
    let b = newTextBuffer("line1")
    discard b.insert(1, "line2")
    check b.modifiedLines[1] == lmkInserted
    # Edit the inserted line — should stay lmkInserted
    discard b.insertText(BufferPosition(line: 1, column: 5), "!")
    check b.modifiedLines[1] == lmkInserted

  test "Unmodified lines remain unmodified after editing other lines":
    let b = newTextBuffer("line1\nline2\nline3")
    discard b.insertText(BufferPosition(line: 1, column: 5), "!")
    check b.modifiedLines[0] == lmkUnmodified
    check b.modifiedLines[1] == lmkModified
    check b.modifiedLines[2] == lmkUnmodified

suite "ModifiedLines - markSaved clears all markers":
  test "markSaved resets all lines to unmodified":
    let b = newTextBuffer("line1\nline2")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    discard b.insert(2, "line3")
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[2] == lmkInserted

    b.markSaved()

    for i in 0 ..< b.modifiedLines.len:
      check b.modifiedLines[i] == lmkUnmodified

suite "ModifiedLines - Undo/Redo Restoration":
  test "Undo single edit restores modifiedLines":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

  test "Undo insert line restores modifiedLines":
    let b = newTextBuffer("line1")
    discard b.insert(1, "line2")
    check b.modifiedLines.len >= 2
    check b.modifiedLines[1] == lmkInserted

    discard b.undo()
    # After undo, line2 is gone and modifiedLines should be restored
    for i in 0 ..< b.modifiedLines.len:
      check b.modifiedLines[i] == lmkUnmodified

  test "Undo multi-line insert restores modifiedLines":
    let b = newTextBuffer("start")
    discard b.insertText(BufferPosition(line: 0, column: 5), "\nline2\nline3")
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[1] == lmkInserted
    check b.modifiedLines[2] == lmkInserted

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

  test "Redo restores modifiedLines":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

    discard b.redo()
    check b.modifiedLines[0] == lmkModified

  test "Redo multi-line insert restores modifiedLines":
    let b = newTextBuffer("start")
    discard b.insertText(BufferPosition(line: 0, column: 5), "\nline2\nline3")
    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

    discard b.redo()
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[1] == lmkInserted
    check b.modifiedLines[2] == lmkInserted

  test "Multiple undo/redo cycle preserves modifiedLines":
    let b = newTextBuffer("test")
    discard b.insertText(BufferPosition(line: 0, column: 4), "A")
    check b.modifiedLines[0] == lmkModified

    discard b.insertText(BufferPosition(line: 0, column: 5), "B")
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    # After undoing "B", line 0 should still be modified (from "A")
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    # After undoing "A", line 0 should be unmodified
    check b.modifiedLines[0] == lmkUnmodified

    discard b.redo()
    check b.modifiedLines[0] == lmkModified

    discard b.redo()
    check b.modifiedLines[0] == lmkModified

  test "Undo to saved state clears all markers":
    let b = newTextBuffer("hello")
    # savedSeq == 0 initially
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    # changeSeq == savedSeq → all markers should be cleared
    check b.modifiedLines[0] == lmkUnmodified

  test "Undo past saved state keeps markers from savedModifiedLines":
    let b = newTextBuffer("hello")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    b.markSaved()
    # Now savedSeq matches current changeSeq
    check b.modifiedLines[0] == lmkUnmodified

    discard b.insertText(BufferPosition(line: 0, column: 6), "?")
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    # Back to saved state → all clear
    check b.modifiedLines[0] == lmkUnmodified

suite "ModifiedLines - Transaction Undo/Redo":
  test "Undo transaction restores modifiedLines":
    let b = newTextBuffer("line1\nline2")
    discard b.beginTransaction("test")
    discard b.insertText(BufferPosition(line: 0, column: 5), "A")
    discard b.insertText(BufferPosition(line: 1, column: 5), "B")
    discard b.commitTransaction()
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[1] == lmkModified

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified
    check b.modifiedLines[1] == lmkUnmodified

  test "Redo transaction restores modifiedLines":
    let b = newTextBuffer("line1\nline2")
    discard b.beginTransaction("test")
    discard b.insertText(BufferPosition(line: 0, column: 5), "A")
    discard b.insertText(BufferPosition(line: 1, column: 5), "B")
    discard b.commitTransaction()
    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified
    check b.modifiedLines[1] == lmkUnmodified

    discard b.redo()
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[1] == lmkModified

suite "ModifiedLines - replaceLine":
  test "replaceLine marks line as modified":
    let b = newTextBuffer("hello\nworld")
    discard b.replaceLine(0, "goodbye")
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[1] == lmkUnmodified

  test "Undo replaceLine restores modifiedLines":
    let b = newTextBuffer("hello\nworld")
    discard b.replaceLine(0, "goodbye")
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

suite "ModifiedLines - deleteLine":
  test "deleteLine does not affect other lines' markers":
    let b = newTextBuffer("line1\nline2\nline3")
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.modifiedLines[0] == lmkModified

    discard b.deleteLine(1)
    # line0 still modified, line1 (previously line2) is unmodified
    check b.modifiedLines[0] == lmkModified

  test "Undo deleteLine restores modifiedLines":
    let b = newTextBuffer("line1\nline2\nline3")
    discard b.deleteLine(1)

    discard b.undo()
    for i in 0 ..< b.modifiedLines.len:
      check b.modifiedLines[i] == lmkUnmodified

suite "ModifiedLines - deleteRange":
  test "deleteRange marks line as modified":
    let b = newTextBuffer("hello world")
    discard b.deleteRange(
      BufferPosition(line: 0, column: 5), BufferPosition(line: 0, column: 10)
    )
    check b.modifiedLines[0] == lmkModified

  test "Undo deleteRange restores modifiedLines":
    let b = newTextBuffer("hello world")
    discard b.deleteRange(
      BufferPosition(line: 0, column: 5), BufferPosition(line: 0, column: 10)
    )
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

suite "ModifiedLines - joinLines":
  test "joinLines marks resulting line as inserted (delete+insert internally)":
    let b = newTextBuffer("line1\nline2\nline3")
    discard b.joinLines(0)
    # joinLines uses deleteLine×2 + insert, so the result is lmkInserted
    check b.modifiedLines[0] == lmkInserted

  test "Undo joinLines restores modifiedLines":
    let b = newTextBuffer("line1\nline2")
    discard b.joinLines(0)
    check b.modifiedLines[0] == lmkInserted

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified
    check b.modifiedLines[1] == lmkUnmodified

suite "ModifiedLines - PieceTable Backend":
  test "PieceTable: editing marks line as modified":
    let b = newTextBuffer("hello", backend = PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.modifiedLines[0] == lmkModified

  test "PieceTable: insert line marks as inserted":
    let b = newTextBuffer("line1", backend = PieceTable)
    discard b.insert(1, "line2")
    check b.modifiedLines[1] == lmkInserted

  test "PieceTable: multi-line insert marks modified and inserted":
    let b = newTextBuffer("start", backend = PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), "\nline2\nline3")
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[1] == lmkInserted
    check b.modifiedLines[2] == lmkInserted

  test "PieceTable: undo restores modifiedLines via snapshot":
    let b = newTextBuffer("hello", backend = PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

  test "PieceTable: redo restores modifiedLines via snapshot":
    let b = newTextBuffer("hello", backend = PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

    discard b.redo()
    check b.modifiedLines[0] == lmkModified

  test "PieceTable: undo multi-line insert restores modifiedLines":
    let b = newTextBuffer("start", backend = PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), "\nline2\nline3")
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[1] == lmkInserted
    check b.modifiedLines[2] == lmkInserted

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

  test "PieceTable: multiple undo/redo cycle":
    let b = newTextBuffer("test", backend = PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 4), "A")
    check b.modifiedLines[0] == lmkModified

    discard b.insertText(BufferPosition(line: 0, column: 5), "B")
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    check b.modifiedLines[0] == lmkModified

    discard b.undo()
    check b.modifiedLines[0] == lmkUnmodified

    discard b.redo()
    check b.modifiedLines[0] == lmkModified

  test "PieceTable: markSaved clears all markers":
    let b = newTextBuffer("line1\nline2", backend = PieceTable)
    discard b.insertText(BufferPosition(line: 0, column: 5), "!")
    discard b.insert(2, "line3")
    check b.modifiedLines[0] == lmkModified
    check b.modifiedLines[2] == lmkInserted

    b.markSaved()

    for i in 0 ..< b.modifiedLines.len:
      check b.modifiedLines[i] == lmkUnmodified

suite "Sidebar - Session Modified/Inserted Markers":
  test "sessionModifiedStyle has yellow foreground":
    let style = sessionModifiedStyle()
    check style.fg.kind == Indexed
    check style.fg.indexed == Color.Yellow

  test "sessionInsertedStyle has green foreground":
    let style = sessionInsertedStyle()
    check style.fg.kind == Indexed
    check style.fg.indexed == Color.Green

  test "generateSidebarFromBuffer shows SessionModified fallback":
    let buf = newTextBuffer("line1\nline2\nline3")
    # Simulate editing line 1
    discard buf.insertText(BufferPosition(line: 1, column: 5), "!")

    let sidebar = generateSidebarFromBuffer(
      buf, 0, 3, modifiedLines = buf.modifiedLines, showModifiedLines = true
    )

    check sidebar.buffer[0][0].kind.isNone
    check sidebar.buffer[1][0].kind == some(SessionModified)
    check sidebar.buffer[2][0].kind.isNone

  test "generateSidebarFromBuffer shows SessionInserted fallback":
    let buf = newTextBuffer("line1")
    discard buf.insert(1, "line2")

    let sidebar = generateSidebarFromBuffer(
      buf, 0, 2, modifiedLines = buf.modifiedLines, showModifiedLines = true
    )

    check sidebar.buffer[0][0].kind.isNone
    check sidebar.buffer[1][0].kind == some(SessionInserted)

  test "generateSidebarFromBuffer shows both Modified and Inserted":
    let buf = newTextBuffer("hello world")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "\nnew line")

    let sidebar = generateSidebarFromBuffer(
      buf, 0, 2, modifiedLines = buf.modifiedLines, showModifiedLines = true
    )

    check sidebar.buffer[0][0].kind == some(SessionModified)
    check sidebar.buffer[1][0].kind == some(SessionInserted)

  test "generateSidebarFromBuffer hides session markers when showModifiedLines is false":
    let buf = newTextBuffer("line1\nline2")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")

    let sidebar = generateSidebarFromBuffer(
      buf, 0, 2, modifiedLines = buf.modifiedLines, showModifiedLines = false
    )

    check sidebar.buffer[0][0].kind.isNone
    check sidebar.buffer[1][0].kind.isNone

  test "Git marker takes priority over session modified marker":
    let buf = newTextBuffer("line1\nline2")
    # Edit line to make it modified
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")
    check buf.modifiedLines[0] == lmkModified

    # Set git marker on same line
    buf.setLineMarker(0, GitAdded)

    let sidebar = generateSidebarFromBuffer(
      buf, 0, 2, modifiedLines = buf.modifiedLines, showModifiedLines = true
    )

    # Git marker should win
    check sidebar.buffer[0][0].kind == some(GitAdded)
    check sidebar.buffer[1][0].kind.isNone

  test "Syntax marker takes priority over session modified marker":
    let buf = newTextBuffer("line1\nline2")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")
    buf.setLineMarker(0, SyntaxError)

    let sidebar = generateSidebarFromBuffer(
      buf, 0, 2, modifiedLines = buf.modifiedLines, showModifiedLines = true
    )

    check sidebar.buffer[0][0].kind == some(SyntaxError)

  test "Session markers with topLine offset":
    let buf = newTextBuffer("line1\nline2\nline3\nline4")
    discard buf.insertText(BufferPosition(line: 2, column: 5), "!")

    let sidebar = generateSidebarFromBuffer(
      buf, 1, 3, modifiedLines = buf.modifiedLines, showModifiedLines = true
    )

    # Screen line 0 = buffer line 1 (unmodified)
    check sidebar.buffer[0][0].kind.isNone
    # Screen line 1 = buffer line 2 (modified)
    check sidebar.buffer[1][0].kind == some(SessionModified)
    # Screen line 2 = buffer line 3 (unmodified)
    check sidebar.buffer[2][0].kind.isNone

  test "Session marker text matches config":
    let buf = newTextBuffer("line1\nline2")
    discard buf.insertText(BufferPosition(line: 0, column: 5), "!")
    discard buf.insert(2, "line3")

    let sidebar = generateSidebarFromBuffer(
      buf, 0, 3, modifiedLines = buf.modifiedLines, showModifiedLines = true
    )

    # SessionModified uses "~ " marker
    check sidebar.buffer[0][0].text == "~"
    check sidebar.buffer[0][1].text == " "
    # SessionInserted uses "+ " marker
    check sidebar.buffer[2][0].text == "+"
    check sidebar.buffer[2][1].text == " "

  test "Empty modifiedLines seq does not crash":
    let buf = newTextBuffer("line1")

    let sidebar = generateSidebarFromBuffer(
      buf, 0, 1, modifiedLines = @[], showModifiedLines = true
    )

    check sidebar.buffer[0][0].kind.isNone
