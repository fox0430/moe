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

## Page scrolls as Vim's pagescroll: Ctrl-D/Ctrl-U scroll the window and take
## the cursor along as many rows, Ctrl-F/Ctrl-B scroll by pages and put the
## cursor on an edge of the window. Smooth scrolling then shows the window's
## top on its way there (`ScrollAnimation`).

import std/[math, monotimes, options, times]

import types, visible_rows, cursor_util
import types/config_types
import buffer/[core, fold]

type
  RowSpot* = tuple[line, offset: int]
    ## A screen row: its line and the wrapped row in it. A closed fold is one
    ## row at its start line. They order as the rows: `a < b` when `a` is
    ## above.

  PageScroll* = object
    top*: RowSpot ## Where the window's top goes
    cursorLine*: int ## Where the cursor goes, before it moves to the indent
    moved*: bool ## The window or the cursor moved (Vim beeps otherwise)

const FrameSeconds = 1.0 / 60.0
  ## The least time a frame shows of a scroll, so each frame moves it on

proc foldStart(rl: RowLayout, line: int): int =
  let fold = rl.buffer.foldState.getCollapsedFoldAt(line)
  if fold.isSome: fold.get.startLine else: line

proc spot(rl: RowLayout, pos: BufferPosition): RowSpot =
  ## The row the cursor at `pos` is on.
  (rl.foldStart(pos.line), rl.cursorCell(pos.line, pos.column).wrapSeg)

proc rowsOf(rl: RowLayout, line: int): int =
  ## The rows `line` takes on the screen, one when it is in a closed fold.
  if rl.buffer.foldState.getCollapsedFoldAt(line).isSome:
    1
  else:
    rl.lineRows(line)

proc lastRow(rl: RowLayout): RowSpot =
  let last = rl.lineCount - 1
  if rl.buffer.foldState.getCollapsedFoldAt(last).isSome:
    (rl.foldStart(last), 0)
  else:
    (last, rl.lineRows(last) - 1)

proc down(rl: RowLayout, spot: RowSpot, rows: int): RowSpot =
  ## The row `rows` rows below `spot`, or the last one.
  let row = rl.rowAt(spot.line, spot.offset, rows)
  if row.isSome:
    (row.get.line, row.get.wrapSeg)
  else:
    rl.lastRow

proc up(rl: RowLayout, spot: RowSpot, rows: int): RowSpot =
  ## The row `rows` rows above `spot`, or the first one.
  rl.walkBackRows(spot.line, spot.offset, rows)

proc go(rl: RowLayout, spot: RowSpot, rows: int, forward: bool): RowSpot =
  if forward:
    rl.down(spot, rows)
  else:
    rl.up(spot, rows)

proc rowsBetween(rl: RowLayout, a, b: RowSpot): int =
  ## Rows from `a` down to `b`, which is not above it.
  rl.rowOfLine(a.line, a.offset, b.line) + b.offset

proc rowsToEnd(rl: RowLayout, top: RowSpot, limit: int): int =
  ## Rows from `top` to the end of the buffer, counted as far as `limit`.
  for vl in rl.visibleLines(top.line, top.offset, limit):
    result = vl.startRow + vl.rows

proc botline(rl: RowLayout, top: RowSpot, height: int): int =
  ## The first line below `top` the window does not show whole, or the line
  ## count when it shows the rest of the buffer (Vim's w_botline). The top
  ## line counts as whole even when it is taller than the window.
  result = top.line
  for vl in rl.visibleLines(top.line, top.offset, height):
    if vl.startRow > 0 and vl.startRow + vl.rows > height:
      return vl.line
    result = (if vl.fold.isSome: vl.fold.get.endLine else: vl.line) + 1

proc onLineStart(
    rl: RowLayout, before, after: RowSpot, forward: bool
): tuple[top, vimTop: RowSpot, cursorRows: int] =
  ## Vim without 'smoothscroll' does not stop a scroll inside a line: it goes
  ## back to the line's start once the scroll left the line it began on (two
  ## lines when scrolling up), and on to the next line otherwise. `vimTop` is
  ## the top Vim keeps, which tells whether it scrolled, and `cursorRows` what
  ## it adds to the rows the cursor moves (scroll_with_sms).
  if not rl.lineWrap or after.offset == 0:
    return (after, after, 0)
  let back = abs(after.line - before.line) > (if forward: 0 else: 1)
  if forward == back:
    # Vim counts the rows back as 1 + (skipcol - width1 - 1) / width2, one
    # short from the third row on. The window still shows the line's start.
    let rows = max(1, after.offset - 1)
    result.vimTop = (after.line, after.offset - rows)
    result.top = (after.line, 0)
    result.cursorRows =
      if forward:
        -rows
      else:
        rows
  else:
    let rows = rl.lineRows(after.line) - after.offset
    result.vimTop = rl.down(after, rows)
    result.top = (result.vimTop.line, 0)
    result.cursorRows =
      if forward:
        rows
      else:
        -rows

proc halfPage*(
    rl: RowLayout,
    top: RowSpot,
    cursor: BufferPosition,
    height, rows: int,
    forward: bool,
): PageScroll =
  ## Ctrl-D (`forward`) or Ctrl-U: scroll the window `rows` rows, Ctrl-D only
  ## until the last line shows at the bottom, and move the cursor as many rows.
  var
    scrolled = rows
    cursorRows = rows
    vimTop = top
  result.top = top
  if forward:
    let left = rl.rowsToEnd(top, height + scrolled)
    if left < height + scrolled:
      scrolled = left - height
  if scrolled > 0:
    let fixed = rl.onLineStart(top, rl.go(top, scrolled, forward), forward)
    result.top = fixed.top
    vimTop = fixed.vimTop
    cursorRows += fixed.cursorRows
  let
    start = rl.spot(cursor)
    landed = rl.go(start, max(0, cursorRows), forward)
  result.cursorLine = landed.line
  result.moved = vimTop != top or landed != start

proc pageRows(rl: RowLayout, top: RowSpot, height: int, forward: bool): int =
  ## The rows a page scrolls: the window's height less the lines it keeps in
  ## view, two when they are short enough (Vim's get_scroll_overlap).
  let
    least = height - 2
    bot = rl.botline(top, height)
  if (not forward and top.line == 0) or (forward and bot >= rl.lineCount):
    return height

  var line =
    if forward:
      bot
    else:
      top.line - 1
  proc next(): int =
    ## The rows of the line one further from the edge, or high(int) past the
    ## buffer (Vim's topline_back and botline_forw).
    if forward:
      line = rl.foldStart(line - 1)
      if line < 0:
        high(int)
      else:
        rl.rowsOf(line)
    else:
      let fold = rl.buffer.foldState.getCollapsedFoldAt(line)
      line = (if fold.isSome: fold.get.endLine else: line) + 1
      if line >= rl.lineCount:
        high(int)
      else:
        rl.rowsOf(line)

  let h1 = rl.rowsOf(line)
  if h1 > least:
    return height
  let h2 = next()
  if h2 == high(int) or h2 + h1 > least:
    return height
  let h3 = next()
  if h3 == high(int) or h3 + h2 > least:
    return height
  let h4 = next()
  if h4 == high(int) or h4 + h3 + h2 > least or h3 + h2 + h1 > least:
    least + 1
  else:
    least

proc page*(
    rl: RowLayout,
    top: RowSpot,
    cursor: BufferPosition,
    height, count: int,
    forward: bool,
): PageScroll =
  ## Ctrl-F (`forward`) or Ctrl-B: scroll the window `count` pages and put the
  ## cursor on its top line or its last whole one.
  let fixed = rl.onLineStart(
    top, rl.go(top, count * rl.pageRows(top, height, forward), forward), forward
  )
  result.top = fixed.top
  result.moved = fixed.vimTop != top
  result.cursorLine =
    if not result.moved:
      cursor.line
    elif forward:
      fixed.top.line
    else:
      rl.foldStart(max(0, rl.botline(fixed.top, height) - 1))

proc stopDistance(speed, friction, airDrag: float): float =
  ## Rows a scroll launched at `speed` rows a second goes until it stops.
  if airDrag <= 0:
    speed * speed / (2 * friction)
  else:
    speed / airDrag - friction / (airDrag * airDrag) * ln(
      1 + airDrag * speed / friction
    )

proc travelled(a: ScrollAnimation, t: float): float =
  ## Rows the scroll has gone after `t` seconds, slowed by a constant friction
  ## and a drag that grows with the speed.
  if a.friction <= 0:
    a.speed * (1 - exp(-a.airDrag * t)) / a.airDrag
  elif a.airDrag <= 0:
    a.speed * t - a.friction * t * t / 2
  else:
    (a.speed + a.friction / a.airDrag) * (1 - exp(-a.airDrag * t)) / a.airDrag -
      a.friction / a.airDrag * t

proc distance(a: ScrollAnimation): int =
  ## Rows the cursor and then the top go.
  a.cursorRows + a.topRows

proc launch(a: var ScrollAnimation) =
  ## The speed and the time that stop the scroll after `a.distance` rows.
  ## Without friction drag alone never stops it, so it is launched half a row
  ## further and ends on the row; without either the scroll shows no way.
  let rows = a.distance.float
  if a.friction <= 0 and a.airDrag <= 0:
    a.duration = 0
  elif a.friction <= 0:
    a.speed = a.airDrag * (rows + 0.5)
    a.duration = ln(2 * rows + 1) / a.airDrag
  else:
    var
      slow = 0.0
      fast = 1.0
    while stopDistance(fast, a.friction, a.airDrag) < rows:
      fast *= 2
    for _ in 0 ..< 64:
      let mid = (slow + fast) / 2
      if stopDistance(mid, a.friction, a.airDrag) < rows:
        slow = mid
      else:
        fast = mid
    a.speed = fast
    a.duration =
      if a.airDrag <= 0:
        fast / a.friction
      else:
        ln(1 + a.airDrag * fast / a.friction) / a.airDrag

proc indentOn(rl: RowLayout, row: RowSpot): int =
  ## Where the cursor shows passing `row`: on the line's indent, where the
  ## scroll leaves it, or at the start of a wrapped row before or after it.
  if rl.buffer.foldState.getCollapsedFoldAt(row.line).isSome:
    return 0
  let
    indent = firstNonBlankColumn(rl.buffer.getLine(row.line))
    indentRow = rl.cursorCell(row.line, indent).wrapSeg
  if row.offset == indentRow:
    indent
  else:
    rl.segmentStartColumn(row.line, row.offset)

proc edgeRow(rl: RowLayout, top: RowSpot, height: int, forward: bool): RowSpot =
  ## The window's last row when it scrolls down, else its first.
  if forward:
    rl.down(top, height - 1)
  else:
    top

proc onRow(rl: RowLayout, row: RowSpot): BufferPosition =
  BufferPosition(line: row.line, column: rl.indentOn(row))

proc lastPageTop*(rl: RowLayout, height: int): RowSpot =
  ## The top that shows the last line on the window's bottom row, where a
  ## smooth scroll stops.
  rl.up(rl.lastRow, height - 1)

proc edgeCursor*(
    rl: RowLayout, top: RowSpot, height: int, forward: bool
): BufferPosition =
  ## Where a smooth scroll leaves the cursor once the window shows from `top`:
  ## on the window's edge it scrolled to, its last row when it went down.
  rl.onRow(rl.edgeRow(top, height, forward))

proc animates*(config: SmoothScrollConfig): bool =
  ## Smooth scrolling is on and something slows a scroll down, so it shows on
  ## its way.
  config.enable and (config.friction > 0 or config.airDrag > 0)

proc startPageScroll*(
    a: var ScrollAnimation,
    rl: RowLayout,
    window: EditorWindow,
    viewport: ViewPort,
    start: tuple[top: RowSpot, cursor: BufferPosition],
    height: int,
    config: SmoothScrollConfig,
) =
  ## Show the scroll from `start` to where `viewport`'s top and `window`'s
  ## cursor are now, which is `edgeCursor` when the top moved. Leaves them
  ## there when that takes no time.
  let
    target: RowSpot = (viewport.topLine, viewport.topWrapOffset)
    forward = start.top < target
    cursorFrom = rl.spot(start.cursor)
    edge =
      if target == start.top:
        rl.spot(window.cursor)
      else:
        rl.edgeRow(start.top, height, forward)
    cursorForward = cursorFrom < edge
  a = ScrollAnimation(
    window: window,
    viewport: viewport,
    buffer: rl.buffer,
    version: rl.buffer.contentVersion,
    forward: forward,
    target: target,
    shown: start.top,
    topRows:
      if forward:
        rl.rowsBetween(start.top, target)
      else:
        rl.rowsBetween(target, start.top),
    cursor: window.cursor,
    cursorStart: start.cursor,
    edge: edge,
    cursorRows:
      if cursorForward:
        rl.rowsBetween(cursorFrom, edge)
      else:
        rl.rowsBetween(edge, cursorFrom),
    cursorForward: cursorForward,
    cursorSpot: cursorFrom,
    shownCursor: window.cursor,
    height: height,
    friction: config.friction,
    airDrag: config.airDrag,
    lastFrame: getMonoTime(),
  )
  a.launch()
  if a.distance <= 0 or a.duration <= 0:
    a = ScrollAnimation()
    return
  a.active = true
  viewport.restoreViewportTop(start.top.line, start.top.offset)
  # The frames move the window and the cursor: keep the window from
  # following the cursor on its own.
  viewport.detachedFromCursor = true

proc holdsTop(a: ScrollAnimation): bool =
  ## The window still shows the top the scroll put there, kept from following
  ## the cursor.
  a.viewport.detachedFromCursor and a.viewport.topLine == a.shown.line and
    a.viewport.topWrapOffset == a.shown.offset

proc owned(a: ScrollAnimation): bool =
  ## The scroll holds the top, the cursor is where it put it, and the buffer
  ## is as the scroll found it.
  a.holdsTop and a.window.cursor == a.shownCursor and
    a.buffer.contentVersion == a.version

proc finishPageScroll*(a: var ScrollAnimation) =
  ## Put the top and the cursor where the scroll ends, as a key that comes
  ## before then finds them. When something else moved the cursor or changed
  ## the buffer, the window follows the cursor again from where it shows.
  if not a.active:
    return
  if a.owned:
    a.viewport.restoreViewportTop(a.target.line, a.target.offset)
    a.window.cursor = a.cursor
  elif a.holdsTop:
    a.viewport.detachedFromCursor = false
  a = ScrollAnimation()

proc stopPageScroll*(a: var ScrollAnimation) =
  ## Leave the top where it shows now, for input that acts on what is drawn
  ## (the pointer). The cursor still ends where the scroll put it, unless
  ## something else moved it.
  if not a.active:
    return
  if a.owned:
    a.window.cursor = a.cursor
  if a.holdsTop:
    a.viewport.detachedFromCursor = false
  a = ScrollAnimation()

proc walkTo(
    rl: RowLayout, spot: RowSpot, rows: int, forward: bool, last: RowSpot
): RowSpot =
  ## `rows` rows from `spot`, never past `last`: a resize may change the rows
  ## on the way.
  result = rl.go(spot, rows, forward)
  if (forward and last < result) or (not forward and result < last):
    result = last

proc advancePageScroll*(
    a: var ScrollAnimation, rl: RowLayout, now: MonoTime = getMonoTime()
) =
  ## Move the cursor, then the top, on by what the time since the last frame
  ## gives, at least a frame's worth. `rl` lays out the active window; the
  ## scroll ends when that no longer shows the scroll's buffer, or something
  ## else moved the top or the cursor.
  if not a.active:
    return
  if rl.buffer != a.buffer or not a.owned:
    a.stopPageScroll()
    return
  a.elapsed += max((now - a.lastFrame).inNanoseconds.float / 1e9, FrameSeconds)
  a.lastFrame = now
  if a.elapsed >= a.duration:
    a.finishPageScroll()
    return
  let
    gone = clamp(a.travelled(a.elapsed).int, 0, a.distance)
    cursorRows = min(gone, a.cursorRows)
    topRows = gone - cursorRows
  if cursorRows > a.cursorWalked:
    a.cursorSpot =
      rl.walkTo(a.cursorSpot, cursorRows - a.cursorWalked, a.cursorForward, a.edge)
    a.cursorWalked = cursorRows
  if topRows > a.topWalked:
    a.shown = rl.walkTo(a.shown, topRows - a.topWalked, a.forward, a.target)
    a.topWalked = topRows
  a.shownCursor =
    if gone == a.distance:
      a.cursor
    elif a.topWalked > 0:
      rl.onRow(rl.edgeRow(a.shown, a.height, a.forward))
    elif a.cursorWalked > 0:
      rl.onRow(a.cursorSpot)
    else:
      a.cursorStart
  a.viewport.topLine = a.shown.line
  a.viewport.topWrapOffset = a.shown.offset
  a.window.cursor = a.shownCursor
