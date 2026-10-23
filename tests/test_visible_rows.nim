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

import ../src/moepkg/[visible_rows, buffer, types]

proc linesBuffer(count: int, text: string = "x"): TextBuffer =
  var lines: seq[string]
  for _ in 0 ..< count:
    lines.add(text)
  newTextBuffer(lines.join("\n"))

proc noWrap(buf: TextBuffer): RowLayout =
  initRowLayout(buf, nil, false, 80, 4)

proc wrapAt10(buf: TextBuffer): RowLayout =
  initRowLayout(buf, nil, true, 10, 4)

suite "visibleLines":
  test "plain buffer yields one row per line":
    let rl = linesBuffer(5).noWrap
    var seen: seq[(int, int)]
    for vl in rl.visibleLines(0, 0):
      seen.add((vl.line, vl.startRow))
    check seen == @[(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)]

  test "maxRows bounds the walk":
    let rl = linesBuffer(100).noWrap
    var rows = 0
    for vl in rl.visibleLines(0, 0, 3):
      rows += vl.rows
    check rows == 3

  test "collapsed fold yields one marker row and hides the interior":
    let buf = linesBuffer(10)
    check buf.foldState.addFold(2, 5, collapsed = true)
    let rl = buf.noWrap
    var seen: seq[(int, int)]
    for vl in rl.visibleLines(0, 0):
      seen.add((vl.line, vl.startRow))
    # Lines 3..5 are hidden; line 2 is the marker, line 6 follows it.
    check seen == @[(0, 0), (1, 1), (2, 2), (6, 3), (7, 4), (8, 5), (9, 6)]

  test "the marker row carries its fold":
    let buf = linesBuffer(10)
    check buf.foldState.addFold(2, 5, collapsed = true)
    for vl in buf.noWrap.visibleLines(2, 0):
      check vl.fold.isSome
      check vl.fold.get.endLine == 5
      break

  test "a top inside a collapsed fold starts below the marker":
    let buf = linesBuffer(10)
    check buf.foldState.addFold(2, 5, collapsed = true)
    var first = -1
    for vl in buf.noWrap.visibleLines(3, 0):
      first = vl.line
      break
    check first == 6

  test "wrap expands a line to its segments":
    let buf = newTextBuffer(@["x", "x".repeat(25), "x"].join("\n"))
    var seen: seq[(int, int, int)]
    for vl in buf.wrapAt10.visibleLines(0, 0):
      seen.add((vl.line, vl.startRow, vl.rows))
    check seen == @[(0, 0, 1), (1, 1, 3), (2, 4, 1)]

  test "topWrapOffset drops leading segments of the first line only":
    let buf = newTextBuffer(@["x".repeat(25), "x".repeat(25)].join("\n"))
    var seen: seq[(int, int, int, int)]
    for vl in buf.wrapAt10.visibleLines(0, 2):
      seen.add((vl.line, vl.startRow, vl.skipSegments, vl.rows))
    check seen == @[(0, 0, 2, 1), (1, 1, 0, 3)]

  test "an out-of-range topWrapOffset is clamped to the last segment":
    let buf = newTextBuffer(@["x", "x"].join("\n"))
    var seen: seq[(int, int, int)]
    for vl in buf.wrapAt10.visibleLines(0, 5):
      seen.add((vl.line, vl.skipSegments, vl.rows))
    check seen == @[(0, 0, 1), (1, 0, 1)]

suite "rowOfLine / rowAt round trip":
  test "row of a line below a collapsed fold skips the hidden interior":
    let buf = linesBuffer(10)
    check buf.foldState.addFold(2, 5, collapsed = true)
    check buf.noWrap.rowOfLine(0, 0, 7) == 4

  test "a line hidden in a collapsed fold reports the marker row":
    let buf = linesBuffer(10)
    check buf.foldState.addFold(2, 5, collapsed = true)
    check buf.noWrap.rowOfLine(0, 0, 4) == 2

  test "the row of a scrolled-off segment is negative":
    let buf = newTextBuffer("x".repeat(25))
    check buf.wrapAt10.rowOfLine(0, 2, 0) == -2

  test "limit stops the walk instead of scanning the whole buffer":
    let rl = linesBuffer(100_000).noWrap
    check rl.rowOfLine(0, 0, 90_000, limit = 24) >= 24

  test "rowAt inverts rowOfLine over the visible rows":
    let buf = newTextBuffer(@["x", "x".repeat(25), "x", "x"].join("\n"))
    check buf.foldState.addFold(2, 3, collapsed = true)
    let rl = buf.wrapAt10
    for line in [0, 1, 2]:
      let row = rl.rowOfLine(0, 0, line)
      let at = rl.rowAt(0, 0, row)
      check at.isSome
      check at.get.line == line

  test "rowAt reports the wrap segment within the line":
    let buf = newTextBuffer("x".repeat(25))
    let at = buf.wrapAt10.rowAt(0, 0, 2)
    check at.isSome
    check (at.get.line, at.get.wrapSeg) == (0, 2)

  test "rowAt adds the skipped segments of the top line":
    let buf = newTextBuffer("x".repeat(25))
    let at = buf.wrapAt10.rowAt(0, 1, 0)
    check at.isSome
    check (at.get.line, at.get.wrapSeg) == (0, 1)

  test "rowAt returns none below the last row":
    check linesBuffer(3).noWrap.rowAt(0, 0, 5).isNone

suite "walkBackRows":
  test "walks back over plain lines":
    check linesBuffer(50).noWrap.walkBackRows(30, 0, 10) == (20, 0)

  test "clamps to the buffer top":
    check linesBuffer(50).noWrap.walkBackRows(3, 0, 10) == (0, 0)

  test "a collapsed fold costs a single row":
    let buf = linesBuffer(50)
    check buf.foldState.addFold(10, 20, collapsed = true)
    # Rows above line 30: 29, ..., 21 (9 rows) then the marker -> line 10.
    check buf.noWrap.walkBackRows(30, 0, 10) == (10, 0)

  test "stops inside a wrapped line":
    let buf = newTextBuffer(@["x".repeat(25), "x", "x"].join("\n"))
    # Two rows above line 2: line 1, then the last segment of line 0.
    check buf.wrapAt10.walkBackRows(2, 0, 2) == (0, 2)

suite "totalRows":
  test "counts rows strictly before stopLine":
    let rl = linesBuffer(20).noWrap
    check rl.totalRows(0) == 0
    check rl.totalRows(20) == 20

  test "a collapsed fold straddling stopLine contributes its marker":
    let buf = linesBuffer(30)
    check buf.foldState.addFold(5, 15, collapsed = true)
    check buf.noWrap.totalRows(10) == 6
    check buf.noWrap.totalRows(30) == 20

suite "cursorCell / cellToColumn":
  test "no wrap counts cells from the line start less leftCell":
    let buf = newTextBuffer("ab\tcd")
    let rl = buf.noWrap
    # Tab at char 2 advances to the next stop (col 4), so 'c' is drawn at 4.
    check rl.cursorCell(0, 3) == (0, 4)
    # Scrolled sideways, the tab keeps the stop it has on the line.
    check rl.cursorCell(0, 3, leftCell = 2) == (0, 2)
    check rl.cursorCell(0, 4, leftCell = 3) == (0, 2)

  test "wrap reports the segment and the column inside it":
    let buf = newTextBuffer("x".repeat(25))
    check buf.wrapAt10.cursorCell(0, 12) == (1, 2)

  test "a folded line reports the marker origin":
    let buf = linesBuffer(10, "hello")
    check buf.foldState.addFold(2, 5, collapsed = true)
    check buf.noWrap.cursorCell(4, 3) == (0, 0)

  test "cellToColumn inverts cursorCell without wrap":
    let buf = newTextBuffer("ab\tcd")
    let rl = buf.noWrap
    for column in 0 .. 4:
      let cell = rl.cursorCell(0, column)
      check rl.cellToColumn(0, 0, cell.cellX) == column

  test "cellToColumn inverts cursorCell with wrap":
    let buf = newTextBuffer("あい\tうえおかきくけこ")
    let rl = buf.wrapAt10
    for column in 0 .. 5:
      let cell = rl.cursorCell(0, column)
      check rl.cellToColumn(0, cell.wrapSeg, cell.cellX) == column

  test "cellToColumn clamps past the end of the line":
    let buf = newTextBuffer("abc")
    check buf.noWrap.cellToColumn(0, 0, 99) == 2

  test "cellToColumn counts cells from the line start":
    let buf = newTextBuffer("\tabc")
    # Scrolled 1 cell, the row starts inside the tab, which covers cell 2.
    check buf.noWrap.cellToColumn(0, 0, 1, leftCell = 1) == 0
    # Scrolled past the tab, the row starts with 'a', so cell 1 is 'b'.
    check buf.noWrap.cellToColumn(0, 0, 1, leftCell = 4) == 2

suite "scrollViewportToCursor - sideways":
  proc noWrapAt10(buf: TextBuffer): RowLayout =
    initRowLayout(buf, nil, false, 10, 8)

  proc scrolledTo(rl: RowLayout, line, column: int, leftCell = 0): int =
    ## `leftCell` after keeping (`line`, `column`) in view from `leftCell`.
    let viewport = ViewPort(width: 10, height: 20, leftCell: leftCell)
    rl.scrollViewportToCursor(viewport, line, column, 20)
    viewport.leftCell

  test "a cursor past tabs scrolls by the cells it is drawn at":
    # Each "x\t" takes 8 cells, so column 4 is drawn at cell 16.
    check newTextBuffer("x\tx\tx\tx").noWrapAt10.scrolledTo(0, 4) == 7

  test "all cells of a wide character come into view":
    # か (column 5) takes cells 10-11.
    check newTextBuffer("あいうえおかき").noWrapAt10.scrolledTo(0, 5) == 2

  test "all cells of a tab come into view":
    # The second tab (column 3) takes cells 9-15.
    check newTextBuffer("x\tx\tx").noWrapAt10.scrolledTo(0, 3) == 6

  test "scrolling back stops at the character's first cell":
    check newTextBuffer("x\tx\tx").noWrapAt10.scrolledTo(0, 1, leftCell = 12) == 1

  test "a character wider than the window keeps its first cell in view":
    let rl = initRowLayout(newTextBuffer("x\tx"), nil, false, 4, 8)
    check rl.scrolledTo(0, 1) == 1

  test "a cursor in view does not scroll":
    check newTextBuffer("x".repeat(30)).noWrapAt10.scrolledTo(0, 12, leftCell = 5) == 5

  test "past the line's end, the cell after it comes into view":
    check newTextBuffer("x".repeat(30)).noWrapAt10.scrolledTo(0, 30) == 21

  test "with wrap, nothing is scrolled off the left":
    let rl = initRowLayout(newTextBuffer("x".repeat(30)), nil, true, 10, 8)
    check rl.scrolledTo(0, 25, leftCell = 7) == 0

  test "a cursor on a combining mark scrolls by the cell it is drawn at":
    # The mark folds into 'e' at cell 9, but the cursor on it shows at 10.
    check newTextBuffer("a".repeat(9) & "e\u0301").noWrapAt10.scrolledTo(0, 10) == 1

  test "a cursor in a closed fold does not scroll":
    let buf = linesBuffer(10, "x".repeat(30))
    check buf.foldState.addFold(2, 5, collapsed = true)
    check buf.noWrapAt10.scrolledTo(3, 25, leftCell = 4) == 4
