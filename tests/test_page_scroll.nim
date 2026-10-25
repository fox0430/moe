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

import std/[unittest, strutils, monotimes, times]

import pkg/results

import ../src/moepkg/[page_scroll, visible_rows, buffer, types]
import ../src/moepkg/types/config_types

# Where Vim 9.2 puts the window and the cursor, measured in a window 17 rows
# high and 40 cells wide (0-based here). The lines Ctrl-D/Ctrl-U scroll are
# half the window, 8.

const Height = 17

proc numbered(count: int): TextBuffer =
  var lines: seq[string]
  for i in 1 .. count:
    lines.add "line " & $i
  newTextBuffer(lines.join("\n"))

proc longEvery(count, every, width: int): TextBuffer =
  ## Every `every`th line is `width` cells, the others short.
  var lines: seq[string]
  for i in 1 .. count:
    lines.add(
      if i mod every == 0:
        "x".repeat(width)
      else:
        "line " & $i
    )
  newTextBuffer(lines.join("\n"))

proc noWrap(buf: TextBuffer): RowLayout =
  initRowLayout(buf, nil, false, 40, 8)

proc wrapped(buf: TextBuffer, width = 40): RowLayout =
  initRowLayout(buf, nil, true, width, 8)

proc at(line: int): BufferPosition =
  BufferPosition(line: line, column: 0)

proc check(scroll: PageScroll, top: RowSpot, cursorLine: int, moved = true): bool =
  scroll.top == top and scroll.cursorLine == cursorLine and scroll.moved == moved

suite "halfPage - without wrap":
  let rl = numbered(200).noWrap

  test "scrolls and takes the cursor as many rows":
    check rl.halfPage((0, 0), at(0), Height, 8, true).check((8, 0), 8)
    check rl.halfPage((0, 0), at(5), Height, 8, true).check((8, 0), 13)
    check rl.halfPage((0, 0), at(0), Height, 3, true).check((3, 0), 3)

  test "Ctrl-D stops when the last line shows at the bottom, the cursor goes on":
    check rl.halfPage((180, 0), at(180), Height, 8, true).check((183, 0), 188)
    check rl.halfPage((183, 0), at(188), Height, 8, true).check((183, 0), 196)

  test "on the last line neither moves":
    check rl.halfPage((183, 0), at(199), Height, 8, true).check(
      (183, 0), 199, moved = false
    )

  test "Ctrl-U at the top moves only the cursor":
    check rl.halfPage((0, 0), at(10), Height, 8, false).check((0, 0), 2)
    check rl.halfPage((0, 0), at(0), Height, 8, false).check((0, 0), 0, moved = false)

  test "Ctrl-U from the end":
    check rl.halfPage((183, 0), at(199), Height, 8, false).check((175, 0), 191)

suite "page - without wrap":
  let rl = numbered(200).noWrap

  test "Ctrl-F keeps two lines and puts the cursor on the top line":
    check rl.page((0, 0), at(0), Height, 1, true).check((15, 0), 15)
    check rl.page((180, 0), at(180), Height, 1, true).check((195, 0), 195)

  test "a count scrolls as many pages":
    check rl.page((0, 0), at(0), Height, 2, true).check((30, 0), 30)

  test "Ctrl-B puts the cursor on the last line it shows":
    check rl.page((15, 0), at(15), Height, 1, false).check((0, 0), 16)
    check rl.page((183, 0), at(199), Height, 1, false).check((168, 0), 184)

  test "Ctrl-F scrolls on until the last line is at the top":
    check rl.page((183, 0), at(199), Height, 1, true).check((199, 0), 199)
    check rl.page((199, 0), at(199), Height, 1, true).check(
      (199, 0), 199, moved = false
    )

  test "Ctrl-B at the top moves nothing":
    check rl.page((0, 0), at(5), Height, 1, false).check((0, 0), 5, moved = false)

suite "page scrolls over a closed fold":
  proc folded(first, last: int): RowLayout =
    let buf = numbered(200)
    check buf.foldState.addFold(first, last)
    buf.noWrap

  test "it is one row":
    check folded(4, 9).halfPage((0, 0), at(0), Height, 8, true).check((13, 0), 13)
    let rl = folded(19, 24)
    var scroll = PageScroll(top: (0, 0), cursorLine: 0)
    for _ in 1 .. 3:
      scroll = rl.halfPage(scroll.top, at(scroll.cursorLine), Height, 8, true)
    check scroll.check((29, 0), 29)
    check folded(4, 9).page((0, 0), at(0), Height, 1, true).check((20, 0), 20)

  test "a page keeps the lines below it":
    check folded(14, 24).page((0, 0), at(0), Height, 1, true).check((25, 0), 25)
    check folded(14, 24).page((25, 0), at(25), Height, 1, false).check((0, 0), 26)
    check folded(4, 9).page((20, 0), at(20), Height, 1, false).check((0, 0), 21)

suite "page scrolls with wrap":
  # Every third line takes three rows.
  let rl = longEvery(120, 3, 95).wrapped

  test "they end on a line's start":
    check rl.halfPage((0, 0), at(0), Height, 8, true).check((5, 0), 5)
    check rl.halfPage((0, 0), at(0), Height, 3, true).check((2, 0), 2)
    check rl.halfPage((0, 0), at(5), Height, 8, true).check((5, 0), 8)
    check rl.halfPage((9, 0), at(9), Height, 8, false).check((5, 0), 5)
    check rl.halfPage((54, 0), at(54), Height, 8, true).check((59, 0), 59)

  test "a page counts rows":
    check rl.page((0, 0), at(0), Height, 1, true).check((9, 0), 9)
    check rl.page((9, 0), at(9), Height, 1, false).check((0, 0), 10)
    check rl.page((0, 0), at(0), Height, 6, true).check((54, 0), 54)

  test "back to a line's start, Vim counts one row short from its third row":
    # Every fourth line takes four rows; 5 rows from the top stop on the
    # third row of line 3. Vim takes 4 off the cursor's rows, not 3.
    let tall = longEvery(80, 4, 150).wrapped
    check tall.halfPage((0, 0), at(0), Height, 8, true).check((5, 0), 5)
    check tall.halfPage((0, 0), at(7), Height, 5, true).check((3, 0), 8)
    check tall.halfPage((0, 0), at(6), Height, 5, true).check((3, 0), 7)

  test "a page keeps fewer lines when they are tall":
    # A window 6 rows high and 10 cells wide.
    let keepsOne = newTextBuffer(
        ["x".repeat(25), "x", "x", "x".repeat(15)].join("\n") & "\ny".repeat(20)
      )
      .wrapped(10)
    check keepsOne.page((0, 0), at(0), 6, 1, true).check((3, 0), 3)
    check keepsOne.page((3, 0), at(3), 6, 1, false).check((1, 0), 5)
    check keepsOne.page((3, 0), at(3), 6, 1, true).check((6, 0), 6)

    let keepsNone = newTextBuffer(
        ["x", "x", "x", "x", "x", "x".repeat(45)].join("\n") & "\ny".repeat(20)
      )
      .wrapped(10)
    check keepsNone.page((0, 0), at(0), 6, 1, true).check((5, 0), 5)
    check keepsNone.page((5, 0), at(5), 6, 1, false).check((0, 0), 4)
    check keepsNone.page((5, 0), at(5), 6, 1, true).check((7, 0), 7)

  test "Ctrl-B counts a top line taller than the window as whole":
    # Line 30 takes 50 rows.
    var lines: seq[string]
    for i in 1 .. 60:
      lines.add(
        if i == 31:
          "x".repeat(2000)
        else:
          "line " & $i
      )
    let rl = newTextBuffer(lines.join("\n")).wrapped
    check rl.page((31, 0), at(31), Height, 1, false).check((30, 0), 30)
    check rl.page((30, 0), at(30), Height, 1, false).check((13, 0), 29)

suite "ScrollAnimation":
  type Frame = tuple[top, cursor: int]

  proc config(friction = 80.0, airDrag = 2.0): SmoothScrollConfig =
    SmoothScrollConfig(enable: true, friction: friction, airDrag: airDrag)

  let
    buf = numbered(200)
    rl = buf.noWrap

  proc scrolled(
      a: var ScrollAnimation, fromTop, fromCursor, toTop, toCursor: int, c = config()
  ): tuple[window: EditorWindow, view: ViewPort] =
    ## A scroll that put the top on `toTop` and the cursor on `toCursor` in a
    ## window 17 rows high, shown from `fromTop` and `fromCursor`.
    result.view = ViewPort(topLine: toTop, width: 40, height: 20)
    result.window = EditorWindow(cursor: at(toCursor))
    a.startPageScroll(
      rl, result.window, result.view, ((fromTop, 0), at(fromCursor)), 17, c
    )

  proc run(a: var ScrollAnimation): seq[Frame] =
    ## The top and the cursor line each frame shows, a frame a sixtieth of a
    ## second.
    let (window, view) = (a.window, a.viewport)
    var now = getMonoTime()
    while a.active and result.len < 10_000:
      now = now + initDuration(milliseconds = 16)
      a.advancePageScroll(rl, now)
      result.add (view.topLine, window.cursor.line)

  proc split(frames: seq[Frame], top: int): tuple[moving, scrolling: seq[Frame]] =
    ## The frames before the top leaves `top`, and the ones after.
    for f in frames:
      if f.top == top and result.scrolling.len == 0:
        result.moving.add f
      else:
        result.scrolling.add f

  test "it stops where the last line shows on the bottom row":
    check rl.lastPageTop(17) == (183, 0)
    check longEvery(120, 3, 95).wrapped.lastPageTop(17) == (110, 1)

  test "it leaves the cursor on the window's edge it scrolls to":
    check rl.edgeCursor((8, 0), 17, true) == at(24)
    check rl.edgeCursor((32, 0), 17, false) == at(32)
    check rl.edgeCursor((199, 0), 17, true) == at(199)

  test "Ctrl-D: the cursor goes to the bottom row, then stays on it as the top walks":
    var a: ScrollAnimation
    let (window, view) = a.scrolled(0, 3, 8, 24)
    check a.active
    check view.topLine == 0
    check view.detachedFromCursor

    let
      frames = a.run()
      (moving, scrolling) = frames.split(0)
    check frames[^1] == (8, 24)
    check window.cursor == at(24)
    check not view.detachedFromCursor
    check moving.len > 1
    check scrolling.len > 1
    check moving[^1].cursor == 16
    for f in scrolling:
      check f.cursor - f.top == 16
    for i in 1 ..< frames.len:
      check frames[i].top >= frames[i - 1].top
      check frames[i].cursor >= frames[i - 1].cursor
    # It slows down: the cursor goes faster than the top comes after it.
    check moving[1].cursor - moving[0].cursor >= scrolling[^1].top - scrolling[^2].top

  test "from the bottom row the top goes at once":
    var a: ScrollAnimation
    discard a.scrolled(0, 16, 8, 24)
    let frames = a.run()
    check frames[^1] == (8, 24)
    for f in frames:
      check f.cursor - f.top == 16

  test "upwards the cursor goes to the top row":
    var a: ScrollAnimation
    discard a.scrolled(40, 43, 32, 32)
    let
      frames = a.run()
      (moving, scrolling) = frames.split(40)
    check frames[^1] == (32, 32)
    check moving[^1].cursor == 40
    for f in scrolling:
      check f.cursor == f.top
    for i in 1 ..< frames.len:
      check frames[i].top <= frames[i - 1].top

  test "past the end the cursor stays on the last line":
    var a: ScrollAnimation
    discard a.scrolled(183, 183, 199, 199)
    let frames = a.run()
    check frames[^1] == (199, 199)
    for f in frames:
      check f.cursor <= 199

  test "the cursor goes on its own when the top stays":
    var a: ScrollAnimation
    discard a.scrolled(183, 183, 183, 191)
    check a.active
    let frames = a.run()
    # Not where it ends before it gets there.
    check frames[0] == (183, 183)
    check frames[^1] == (183, 191)
    check frames.len > 2
    for i in 1 ..< frames.len:
      check frames[i].top == 183
      check frames[i].cursor >= frames[i - 1].cursor

  test "with drag alone, or friction alone, it still stops there":
    for c in [config(friction = 0.0), config(airDrag = 0.0)]:
      var a: ScrollAnimation
      discard a.scrolled(0, 0, 15, 31, c)
      check a.active
      check a.run()[^1] == (15, 31)

  test "with neither, both stay where the scroll put them":
    var a: ScrollAnimation
    let (window, view) = a.scrolled(0, 0, 15, 31, config(0.0, 0.0))
    check not a.active
    check view.topLine == 15
    check window.cursor == at(31)
    check not view.detachedFromCursor

  test "finishing puts both where it ends":
    var a: ScrollAnimation
    let (window, view) = a.scrolled(0, 0, 15, 31)
    a.advancePageScroll(rl, getMonoTime() + initDuration(milliseconds = 16))
    check window.cursor.line in 0 ..< 31
    a.finishPageScroll()
    check not a.active
    check view.topLine == 15
    check window.cursor == at(31)
    check not view.detachedFromCursor

  test "stopping leaves the top where it shows, the cursor where it ends":
    var a: ScrollAnimation
    let (window, view) = a.scrolled(0, 0, 15, 31)
    var now = getMonoTime()
    while view.topLine == 0 and a.active:
      now = now + initDuration(milliseconds = 16)
      a.advancePageScroll(rl, now)
    let shown = view.topLine
    check shown in 1 ..< 15
    a.stopPageScroll()
    check not a.active
    check view.topLine == shown
    check window.cursor == at(31)
    check not view.detachedFromCursor

  test "it leaves a window someone else scrolled alone":
    var a: ScrollAnimation
    let (window, view) = a.scrolled(0, 0, 15, 31)
    view.topLine = 100
    a.advancePageScroll(rl, getMonoTime() + initDuration(milliseconds = 16))
    check not a.active
    check view.topLine == 100
    check window.cursor == at(31)
    check view.detachedFromCursor

  for finish in [false, true]:
    test "a cursor someone else moved takes the window from where it shows (finish: " &
      $finish & ")":
      var a: ScrollAnimation
      let (window, view) = a.scrolled(0, 0, 15, 31)
      let now = getMonoTime() + initDuration(milliseconds = 16)
      a.advancePageScroll(rl, now)
      let shown = view.topLine
      window.cursor = at(50)
      if finish:
        a.finishPageScroll()
      else:
        a.advancePageScroll(rl, now + initDuration(milliseconds = 16))
      check not a.active
      check view.topLine == shown
      check window.cursor == at(50)
      check not view.detachedFromCursor

  test "it lets go of the window and the buffer once it ends":
    proc released(a: ScrollAnimation): bool =
      not a.active and a.window.isNil and a.viewport.isNil and a.buffer.isNil

    var a: ScrollAnimation
    discard a.scrolled(0, 0, 15, 31)
    discard a.run()
    check a.released

    discard a.scrolled(0, 0, 15, 31)
    a.finishPageScroll()
    check a.released

    discard a.scrolled(0, 0, 15, 31)
    a.stopPageScroll()
    check a.released

    discard a.scrolled(0, 0, 15, 31, config(0.0, 0.0))
    check a.released

  test "it stops when the buffer changes":
    var a: ScrollAnimation
    let (_, view) = a.scrolled(0, 0, 15, 31)
    check buf.insertText(BufferPosition(line: 0, column: 0), "x").isOk
    a.finishPageScroll()
    check not a.active
    check view.topLine == 0
    check not view.detachedFromCursor
