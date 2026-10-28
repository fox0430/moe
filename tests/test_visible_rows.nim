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

import ../src/moepkg/[visible_rows, buffer, types, modes]

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

suite "botline / lastWholeRow":
  test "without wrap, the line below the window":
    check linesBuffer(50).noWrap.botline(10, 0, 17) == (27, 17)
    check linesBuffer(50).noWrap.lastWholeRow(10, 0, 17).line == 26

  test "a line sticking out at the bottom is not shown whole":
    var lines = newSeq[string](20)
    for i in 0 ..< lines.len:
      lines[i] = "x"
    lines[16] = "x".repeat(25)
    let buf = newTextBuffer(lines.join("\n"))
    check buf.wrapAt10.botline(0, 0, 17) == (16, 16)
    let row = buf.wrapAt10.lastWholeRow(0, 0, 17)
    check (row.line, row.wrapSeg) == (15, 0)

  test "a top line taller than the window counts as shown whole":
    let buf = newTextBuffer(@["a", "x".repeat(250), "c"].join("\n"))
    check buf.wrapAt10.botline(1, 0, 5) == (2, 5)
    let row = buf.wrapAt10.lastWholeRow(1, 3, 5)
    check (row.line, row.wrapSeg) == (1, 7)

  test "the buffer's end leaves rows unused":
    check linesBuffer(5).noWrap.botline(0, 0, 17) == (5, 5)
    check linesBuffer(5).noWrap.lastWholeRow(0, 0, 17).line == 4

  test "a closed fold is one row, and the line after it is below":
    let buf = linesBuffer(50)
    check buf.foldState.addFold(5, 30, collapsed = true)
    check buf.noWrap.botline(0, 0, 10) == (35, 10)
    let row = buf.noWrap.lastWholeRow(0, 0, 6)
    check row.line == 5
    check row.fold.isSome

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

  test "onTabEnd puts a cursor on a tab on its last cell":
    let buf = newTextBuffer("ab\tcd")
    let rl = buf.noWrap
    # The tab covers cells 2-3; 'c' is not a tab.
    check rl.cursorCell(0, 2, onTabEnd = true) == (0, 3)
    check rl.cursorCell(0, 3, onTabEnd = true) == (0, 4)
    # The left edge cuts the tab, whose last cell shows first.
    check rl.cursorCell(0, 2, leftCell = 3, onTabEnd = true) == (0, 0)

  test "onTabEnd measures a wrapped tab from its segment's start":
    # The tab does not fit after "abcdefgh", so it starts segment 1.
    let buf = newTextBuffer("abcdefgh\tx")
    check buf.wrapAt10.cursorCell(0, 8, onTabEnd = true) == (1, 3)

  test "onTabEnd cuts a wrapped tab wider than the row at its edge":
    let rl = initRowLayout(newTextBuffer("\tx"), nil, true, 3, 8)
    check rl.cursorCell(0, 0, onTabEnd = true) == (0, 2)

  test "onTabEnd leaves a tab right of the row where it is":
    # The tab covers cells 4-7, all past a row 3 cells wide.
    let rl = initRowLayout(newTextBuffer("abcd\tx"), nil, false, 3, 8)
    check rl.cursorCell(0, 4, onTabEnd = true) == (0, 7)

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

suite "screen cells - counted along a line's rows, as gj and gk aim":
  # Rows of 10: "abcdefghi" takes 9 cells, so あ goes on to the next row.
  let pushed = newTextBuffer("abcdefghiあx").wrapAt10

  test "screenCellOf counts each row before the cursor's as maxWidth":
    check newTextBuffer("x".repeat(25)).wrapAt10.screenCellOf(0, 12, false) == 12
    check pushed.screenCellOf(0, 9, false) == 10
    check pushed.screenCellOf(0, 10, false) == 12

  test "a cell from the line start stands for the same character's":
    check pushed.screenCellOfLineCell(0, 8) == 8
    check pushed.screenCellOfLineCell(0, 9) == 10
    check pushed.screenCellOfLineCell(0, 10) == 11
    check pushed.screenCellOfLineCell(0, 11) == 12
    # Past the end, as far past it
    check pushed.screenCellOfLineCell(0, 15) == 16

  test "the cell past a short row stands for the character that went on":
    check pushed.lineCellOfScreenCell(0, 9) == 9
    check pushed.lineCellOfScreenCell(0, 10) == 9
    check pushed.lineCellOfScreenCell(0, 11) == 10
    check pushed.lineCellOfScreenCell(0, 12) == 11
    check pushed.lineCellOfScreenCell(0, 16) == 15

  test "a wrapped tab measures from its row's start, the line cell from the line's":
    # The tab does not fit after "abcdefgh", so it takes cells 0-3 of row 1;
    # from the line start it takes 8-11.
    let rl = newTextBuffer("abcdefgh\tx").wrapAt10
    check rl.screenCellOfLineCell(0, 9) == 11
    check rl.lineCellOfScreenCell(0, 11) == 9
    check rl.lineCellOfScreenCell(0, 8) == 8
    check rl.screenCellOfLineCell(0, 12) == 14

  test "columnAtScreenCell lands on the character covering the cell":
    check pushed.columnAtScreenCell(0, 3, EditorMode.Normal) == 3
    check pushed.columnAtScreenCell(0, 9, EditorMode.Normal) == 9
    check pushed.columnAtScreenCell(0, 11, EditorMode.Normal) == 9
    check pushed.columnAtScreenCell(0, 12, EditorMode.Normal) == 10
    # Past the end, the last character, or past it in Visual
    check pushed.columnAtScreenCell(0, 25, EditorMode.Normal) == 10
    check pushed.columnAtScreenCell(0, 25, EditorMode.Visual) == 11

suite "scrollViewportToCursor - sideways":
  proc noWrapAt10(buf: TextBuffer): RowLayout =
    initRowLayout(buf, nil, false, 10, 8)

  proc scrolledTo(
      rl: RowLayout, line, column: int, leftCell = 0, onTabEnd = false
  ): int =
    ## `leftCell` after keeping (`line`, `column`) in view from `leftCell`.
    let viewport = ViewPort(width: 10, height: 20, leftCell: leftCell)
    rl.scrollViewportToCursor(viewport, line, column, 20, onTabEnd)
    viewport.leftCell

  test "a cursor less than half the window off scrolls by as many cells":
    let rl = newTextBuffer("x".repeat(40)).noWrapAt10
    # Column 13 sticks out of cells 0-9 by 4, column 16 out of 20-29 by 4.
    check rl.scrolledTo(0, 13) == 4
    check rl.scrolledTo(0, 16, leftCell = 20) == 16

  test "a cursor half the window or more off comes to the middle":
    let rl = newTextBuffer("x".repeat(40)).noWrapAt10
    check rl.scrolledTo(0, 14) == 9
    check rl.scrolledTo(0, 30) == 25
    check rl.scrolledTo(0, 15, leftCell = 20) == 10

  test "the middle stops at the line's start":
    check newTextBuffer("x".repeat(40)).noWrapAt10.scrolledTo(0, 2, leftCell = 20) == 0

  test "a cursor past tabs scrolls by the cells it is drawn at":
    # Each "x\t" takes 8 cells, so column 4 is drawn at cell 16.
    check newTextBuffer("x\tx\tx\tx").noWrapAt10.scrolledTo(0, 4, leftCell = 4) == 7

  test "all cells of a wide character come into view":
    # か (column 5) takes cells 10-11.
    check newTextBuffer("あいうえおかき").noWrapAt10.scrolledTo(0, 5) == 2

  test "all cells of a tab come into view":
    # The second tab (column 3) takes cells 9-15.
    check newTextBuffer("x\tx\tx").noWrapAt10.scrolledTo(0, 3, leftCell = 3) == 6

  test "scrolling back stops at the character's first cell":
    check newTextBuffer("x\tx\tx").noWrapAt10.scrolledTo(0, 1, leftCell = 4) == 1

  test "a tab comes to the middle on the cell the cursor shows on":
    # The second tab (column 3) takes cells 9-15.
    let rl = newTextBuffer("x\tx\tx\tx").noWrapAt10
    check rl.scrolledTo(0, 3) == 4
    check rl.scrolledTo(0, 3, onTabEnd = true) == 10

  test "a character as wide as the window comes to the middle":
    # The tab takes cells 2-7, as many as the window has, and sticks out by
    # 2, less than half of it.
    let rl = initRowLayout(newTextBuffer("ab\tx"), nil, false, 6, 8)
    check rl.scrolledTo(0, 2) == 0
    check rl.scrolledTo(0, 2, onTabEnd = true) == 4

  test "a tab wider than the window shows the cell the cursor is on":
    let rl = initRowLayout(newTextBuffer("\tx"), nil, false, 3, 8)
    let leftCell = rl.scrolledTo(0, 0, onTabEnd = true)
    check leftCell == 6
    check rl.cursorCell(0, 0, leftCell, onTabEnd = true) == (0, 1)

  test "a cursor in view does not scroll":
    check newTextBuffer("x".repeat(30)).noWrapAt10.scrolledTo(0, 12, leftCell = 5) == 5

  test "past the line's end, the cell after it comes into view":
    check newTextBuffer("x".repeat(30)).noWrapAt10.scrolledTo(0, 30, leftCell = 18) == 21

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

suite "scrollViewportToCursor - up and down":
  # The expected tops are Vim 9.2's in a window 17 rows high.
  proc scrolledTo(
      rl: RowLayout, line: int, column = 0, top = 0, skip = 0, height = 17
  ): tuple[top, skip: int] =
    ## The window's top after keeping (`line`, `column`) in view from `top`.
    let viewport = ViewPort(width: rl.maxWidth, height: height, topLine: top)
    viewport.topWrapOffset = skip
    rl.scrollViewportToCursor(viewport, line, column, height)
    (viewport.topLine, viewport.topWrapOffset)

  test "a cursor in view does not scroll":
    check linesBuffer(200).noWrap.scrolledTo(30, top = 20) == (20, 0)

  test "a cursor just below the window comes to the bottom":
    check linesBuffer(200).noWrap.scrolledTo(17) == (1, 0)

  test "a cursor near below the window comes to the bottom":
    check linesBuffer(200).noWrap.scrolledTo(25) == (9, 0)

  test "a cursor far below the window comes to the middle":
    check linesBuffer(200).noWrap.scrolledTo(26) == (18, 0)
    check linesBuffer(200).noWrap.scrolledTo(49) == (41, 0)

  test "the last line comes to the bottom":
    check linesBuffer(200).noWrap.scrolledTo(199) == (183, 0)
    check linesBuffer(200).noWrap.scrolledTo(194) == (183, 0)

  test "a cursor near above the window comes to the top":
    check linesBuffer(200).noWrap.scrolledTo(35, top = 41) == (35, 0)

  test "a cursor far above the window comes to the middle":
    check linesBuffer(200).noWrap.scrolledTo(34, top = 41) == (26, 0)

  test "a closed fold counts as one line":
    let buf = linesBuffer(200)
    check buf.foldState.addFold(29, 49, collapsed = true)
    # Eight lines above 54 are 53-50, the fold and 28-26.
    check buf.noWrap.scrolledTo(54) == (26, 0)
    check buf.noWrap.scrolledTo(56) == (28, 0)

  test "a top inside a closed fold goes to the fold's start":
    let buf = linesBuffer(200)
    check buf.foldState.addFold(29, 49, collapsed = true)
    check buf.noWrap.scrolledTo(52, top = 40) == (29, 0)

  test "a wrapped line sticking out at the bottom comes into view whole":
    var lines = newSeq[string](20)
    for i in 0 ..< lines.len:
      lines[i] = "x"
    lines[16] = "x".repeat(25)
    let buf = newTextBuffer(lines.join("\n"))
    check buf.wrapAt10.scrolledTo(16) == (2, 0)

  test "a top line taller than the window scrolls to the cursor":
    let buf = newTextBuffer(@["a", "b", "x".repeat(250), "c"].join("\n"))
    check buf.wrapAt10.scrolledTo(2, height = 5) == (2, 0)
    check buf.wrapAt10.scrolledTo(2, 120, top = 2, height = 5) == (2, 8)
    # Back up the line, the cursor comes to the top row.
    check buf.wrapAt10.scrolledTo(2, 30, top = 2, skip = 8, height = 5) == (2, 3)

  test "scrolling off a top line with rows scrolled off frees only the rest":
    # The top line shows its last 2 of 10 rows, then "a", then 2 rows of "b";
    # the cursor is on the last row of "c", 3 rows high.
    let buf =
      newTextBuffer(@["x".repeat(100), "a", "x".repeat(15), "x".repeat(25)].join("\n"))
    check buf.wrapAt10.scrolledTo(3, 20, skip = 8, height = 5) == (2, 0)

  test "a top moved to a closed fold's start drops the rows scrolled off":
    var lines = newSeq[string](200)
    for i in 0 ..< lines.len:
      lines[i] = "x"
    lines[29] = "x".repeat(25)
    lines[40] = "x".repeat(25)
    let buf = newTextBuffer(lines.join("\n"))
    check buf.foldState.addFold(29, 49, collapsed = true)
    check buf.wrapAt10.scrolledTo(52, top = 40, skip = 2) == (29, 0)
    check buf.wrapAt10.scrolledTo(52, top = 29, skip = 2) == (29, 0)

  test "rows scrolled off a top line that fits stay above the cursor":
    let buf = newTextBuffer(@["x".repeat(50), "a", "b"].join("\n"))
    check buf.wrapAt10.scrolledTo(0, 35, skip = 2, height = 5) == (0, 2)
    check buf.wrapAt10.scrolledTo(0, 5, skip = 2, height = 5) == (0, 0)

suite "scrollCursorLineTo - zt, zz and zb":
  # The expected tops are Vim 9.2's: with 'smoothscroll' for rows scrolled off
  # a line that fits, as moe's <C-e> scrolls by rows, and without it for a
  # line taller than the window.
  proc placed(
      rl: RowLayout, spot: CursorLineSpot, line, column: int, top = 0, skip = 0
  ): tuple[top, skip: int] =
    ## The window's top after `spot` and the redraw after it, 5 rows high.
    let viewport = ViewPort(width: rl.maxWidth, height: 5, topLine: top)
    viewport.topWrapOffset = skip
    rl.scrollCursorLineTo(viewport, line, column, 5, spot)
    rl.scrollViewportToCursor(viewport, line, column, 5)
    (viewport.topLine, viewport.topWrapOffset)

  let
    fits = newTextBuffer(@["x".repeat(30), "a", "b", "c", "d", "e"].join("\n"))
    tall = newTextBuffer(@["a", "b", "x".repeat(250), "c"].join("\n"))

  test "zz and zb show a top line that fits from its head":
    check fits.wrapAt10.placed(clsMiddle, 0, 15, skip = 1) == (0, 0)
    check fits.wrapAt10.placed(clsBottom, 0, 15, skip = 1) == (0, 0)

  test "zt keeps the rows scrolled off while the cursor is past them":
    check fits.wrapAt10.placed(clsTop, 0, 15, skip = 1) == (0, 1)
    # On the first cell after them, as Vim's w_skipcol >= w_virtcol.
    check fits.wrapAt10.placed(clsTop, 0, 10, skip = 1) == (0, 0)

  test "zt and zz keep the rows scrolled off a line taller than the window":
    check tall.wrapAt10.placed(clsTop, 2, 85, top = 2, skip = 8) == (2, 8)
    check tall.wrapAt10.placed(clsTop, 2, 80, top = 2, skip = 8) == (2, 8)
    check tall.wrapAt10.placed(clsMiddle, 2, 85, top = 2, skip = 8) == (2, 8)

  test "zb in a line taller than the window brings the cursor's row to the bottom":
    check tall.wrapAt10.placed(clsBottom, 2, 85, top = 2, skip = 8) == (2, 4)

  test "zt in a closed fold puts the fold's start at the top":
    let buf = linesBuffer(200)
    check buf.foldState.addFold(10, 20, collapsed = true)
    check buf.noWrap.placed(clsTop, 15, 0) == (10, 0)
