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

## Visible-row traversal: maps logical lines to screen rows.
## Handles collapsed folds (one marker row) and line wrap (multiple segments
## + `topWrapOffset`). All views derive row arithmetic from `visibleLines`.

import std/[options, unicode]

import types, buffer/[core, fold], render_utils, unicode_utils, wanted_column

type
  RowLayout* = object
    ## Row-walk context for a window frame. `maxWidth` is the text area's width.
    buffer*: TextBuffer
    wrapCache*: WrapCountCache
    lineWrap*: bool
    maxWidth*: int
    tabStop*: int

  VisibleLine* = object ## One logical line's contribution to the screen.
    line*: int ## Logical line (a fold marker reports its start line)
    startRow*: int ## Screen row of this line's first visible row
    skipSegments*: int ## Leading wrap segments scrolled off the top
    rows*: int ## Screen rows this line occupies (>= 1)
    fold*: Option[Fold] ## Set when the row is a collapsed-fold marker

  VisibleRow* = object ## A single screen row's source position.
    line*: int
    wrapSeg*: int
    fold*: Option[Fold]

proc initRowLayout*(
    buffer: TextBuffer,
    wrapCache: WrapCountCache,
    lineWrap: bool,
    maxWidth, tabStop: int,
): RowLayout =
  ## Build layout and refresh wrap cache for this frame.
  result = RowLayout(
    buffer: buffer,
    wrapCache: wrapCache,
    lineWrap: lineWrap,
    maxWidth: max(1, maxWidth),
    tabStop: tabStop,
  )
  if lineWrap and wrapCache != nil and buffer != nil:
    wrapCache.ensureFresh(buffer, result.maxWidth, tabStop)

proc lineCount*(rl: RowLayout): int =
  if rl.buffer.isNil: 0 else: rl.buffer.len

proc lineRows*(rl: RowLayout, line: int): int =
  ## Screen rows a logical line occupies, ignoring fold hiding.
  if not rl.lineWrap:
    1
  elif rl.wrapCache != nil:
    rl.wrapCache.cachedWrapCount(rl.buffer, line)
  else:
    calculateWrapCount(rl.buffer.getLine(line), rl.maxWidth, rl.tabStop)

proc rowsOf*(rl: RowLayout, line: int): int =
  ## The rows `line` takes on the screen, one when it is in a closed fold.
  if rl.buffer.foldState.getCollapsedFoldAt(line).isSome:
    1
  else:
    rl.lineRows(line)

iterator visibleLines*(
    rl: RowLayout, topLine, topWrapOffset: int, maxRows: int = high(int)
): VisibleLine =
  ## Walk lines from (`topLine`, `topWrapOffset`) downwards, up to `maxRows` rows.
  ## Skips hidden fold interiors; yields marker once. Handles mid-line top.
  let folds =
    if rl.buffer.isNil:
      @[]
    else:
      rl.buffer.foldState.folds
  var
    line = max(0, topLine)
    row = 0
    skip = max(0, topWrapOffset)
    foldIdx = 0
  while line < rl.lineCount and row < maxRows:
    # `folds` is sorted by startLine, so the index only moves forward.
    while foldIdx < folds.len and
        (not folds[foldIdx].collapsed or folds[foldIdx].endLine < line):
      inc foldIdx
    if foldIdx < folds.len and folds[foldIdx].startLine <= line:
      let fold = folds[foldIdx]
      if fold.startLine == line:
        yield VisibleLine(
          line: line, startRow: row, skipSegments: 0, rows: 1, fold: some(fold)
        )
        inc row
      # Starting below the marker: the whole fold is off-screen above.
      line = fold.endLine + 1
      inc foldIdx
    else:
      let
        total = rl.lineRows(line)
        skipped = min(skip, max(0, total - 1))
      yield VisibleLine(
        line: line,
        startRow: row,
        skipSegments: skipped,
        rows: total - skipped,
        fold: none(Fold),
      )
      row += total - skipped
      inc line
    skip = 0

proc rowOfLine*(
    rl: RowLayout, topLine, topWrapOffset, targetLine: int, limit: int = high(int)
): int =
  ## Screen row of `targetLine` from viewport top. Negative if above top.
  ## Returns `>= limit` when beyond limit without full scan. Requires `targetLine >= topLine`.
  for vl in rl.visibleLines(topLine, topWrapOffset, limit):
    if vl.fold.isSome:
      if targetLine <= vl.fold.get.endLine:
        return vl.startRow
    elif vl.line == targetLine:
      return vl.startRow - vl.skipSegments
    result = vl.startRow + vl.rows

proc rowAt*(rl: RowLayout, topLine, topWrapOffset, screenRow: int): Option[VisibleRow] =
  ## Position drawn on `screenRow` (inverse of `rowOfLine`). `none` if past buffer end.
  if screenRow < 0:
    return none(VisibleRow)
  for vl in rl.visibleLines(topLine, topWrapOffset, screenRow + 1):
    if screenRow < vl.startRow + vl.rows:
      return some(
        VisibleRow(
          line: vl.line,
          wrapSeg: vl.skipSegments + (screenRow - vl.startRow),
          fold: vl.fold,
        )
      )

proc walkBackRows*(
    rl: RowLayout, line, wrapSeg, budget: int
): tuple[line, offset: int] =
  ## Top position `budget` rows above (`line`, `wrapSeg`). Clamps to (0, 0).
  var remaining = budget
  if wrapSeg >= remaining:
    return (line, wrapSeg - remaining)
  remaining -= wrapSeg
  var l = line - 1
  while l >= 0:
    let fold = rl.buffer.foldState.getCollapsedFoldAt(l)
    let
      top = if fold.isSome: fold.get.startLine else: l
      rows =
        if fold.isSome:
          1
        else:
          rl.lineRows(l)
    if remaining <= rows:
      return (top, rows - remaining)
    remaining -= rows
    l = top - 1
  return (0, 0)

proc totalRows*(rl: RowLayout, stopLine: int): int =
  ## Screen rows for lines [0, `stopLine`). Fold straddling `stopLine` counts as one row.
  for vl in rl.visibleLines(0, 0):
    if vl.line >= stopLine:
      break
    result = vl.startRow + vl.rows

proc botline*(
    rl: RowLayout, topLine, topWrapOffset, height: int
): tuple[line, rows: int] =
  ## In a window `height` rows high from (`topLine`, `topWrapOffset`), the
  ## first line below the ones it shows whole, or the line count, and the rows
  ## those take (Vim's w_botline, and the rows over w_empty_rows). A top line
  ## taller than the window counts as shown whole.
  result = (topLine, 0)
  for vl in rl.visibleLines(topLine, topWrapOffset, height):
    let rows =
      if vl.startRow == 0:
        min(vl.rows, height)
      else:
        vl.rows
    if result.rows + rows > height:
      return
    result.rows += rows
    result.line = (if vl.fold.isSome: vl.fold.get.endLine else: vl.line) + 1

proc lastWholeRow*(rl: RowLayout, topLine, topWrapOffset, height: int): VisibleRow =
  ## The last row of the last line a window `height` rows high from
  ## (`topLine`, `topWrapOffset`) shows whole.
  let rows = rl.botline(topLine, topWrapOffset, height).rows
  rl.rowAt(topLine, topWrapOffset, max(0, rows - 1)).get(
    VisibleRow(line: topLine, wrapSeg: topWrapOffset)
  )

proc textCell*(
    text: string,
    column: int,
    lineWrap: bool,
    maxWidth, tabStop, leftCell: int,
    onTabEnd = false,
): tuple[wrapSeg, cellX: int] =
  ## Display cell of `text[column]`: (wrapSeg, cellX). Wrap-aware; without wrap
  ## the cell from the line start less `leftCell`, negative when scrolled off
  ## the left. With `onTabEnd`, a tab's last cell, in a wrapped row cut at its
  ## right edge.
  if lineWrap:
    let (wrapSeg, cellX) = cursorWrapPosition(text, column, maxWidth, tabStop)
    if onTabEnd and text.getCharAtPos(column)[0] == TAB_CHAR:
      # A wrapped row measures its tabs from its own start.
      (wrapSeg, min(cellX + tabAdvance(cellX, tabStop), maxWidth) - 1)
    else:
      (wrapSeg, cellX)
  else:
    (0, text.cursorCell(column, tabStop, onTabEnd) - leftCell)

proc cursorCell*(
    rl: RowLayout, line, column: int, leftCell: int = 0, onTabEnd = false
): tuple[wrapSeg, cellX: int] =
  ## `textCell` for buffer position. Hidden fold line returns marker origin.
  if rl.buffer.isNil or line < 0 or line >= rl.lineCount:
    return (0, 0)
  if rl.buffer.foldState.getCollapsedFoldAt(line).isSome:
    return (0, 0)
  textCell(
    rl.buffer.getLine(line),
    column,
    rl.lineWrap,
    rl.maxWidth,
    rl.tabStop,
    leftCell,
    onTabEnd,
  )

proc segmentStartColumn*(rl: RowLayout, line, wrapSeg: int): int =
  ## Char index of `line`'s `wrapSeg` start.
  if not rl.lineWrap or wrapSeg <= 0:
    return 0
  let text = rl.buffer.getLine(line)
  for _ in 0 ..< wrapSeg:
    let (charCount, _) =
      displayWidthSubstrWithTabs(text, result, rl.maxWidth, rl.tabStop)
    result += max(1, charCount)

proc cellToColumn*(rl: RowLayout, line, wrapSeg, cellX: int, leftCell: int = 0): int =
  ## Char index at (`wrapSeg`, `cellX`). Inverse of `cursorCell`.
  if rl.buffer.isNil or line < 0 or line >= rl.lineCount:
    return 0
  let
    text = rl.buffer.getLine(line)
    (start, cell) =
      if rl.lineWrap:
        (rl.segmentStartColumn(line, wrapSeg), cellX)
      else:
        (0, leftCell + cellX)
  clamp(
    start + screenXToCharIndex(text, start, cell, rl.tabStop),
    0,
    max(0, text.charLen - 1),
  )

func wrapPosAbove*(aLine, aSeg, bLine, bSeg: int): bool {.inline.} =
  ## True if (aLine, aSeg) is above (bLine, bSeg) in wrapped order.
  aLine < bLine or (aLine == bLine and aSeg < bSeg)

proc scrollLeftCellToCursor(
    rl: RowLayout, viewport: ViewPort, line, column: int, onTabEnd: bool
) =
  ## Bring the cells the cursor is drawn over into view, as Vim's curs_columns
  ## does with 'sidescroll' 1 and 'sidescrolloff' 0: by as many cells as they
  ## stick out, or, when that is half the window or more or the character is
  ## as wide as the window, so that the cell the cursor shows on (`onTabEnd`)
  ## is in the middle. A cursor in a closed fold does not scroll.
  if rl.lineWrap:
    viewport.leftCell = 0
    return
  if rl.buffer.foldState.getCollapsedFoldAt(line).isSome:
    return
  let
    text = rl.buffer.getLine(line)
    (first, last) = text.cellsAt(column, rl.tabStop)
    offLeft = first - viewport.leftCell
    offRight = last - (viewport.leftCell + rl.maxWidth) + 1
  if offLeft >= 0 and offRight <= 0:
    return
  let
    diff =
      if offLeft < 0:
        -offLeft
      else:
        offRight
    half = rl.maxWidth div 2
  viewport.leftCell =
    if diff >= half or offRight >= offLeft:
      max(0, text.cursorCell(column, rl.tabStop, onTabEnd) - half)
    elif offLeft < 0:
      first
    else:
      viewport.leftCell + diff

type TopWindow = object
  ## The window's top as Vim's update_topline moves it, with 'scrolloff' 0 and
  ## 'scrolljump' 1. `skip` is the rows of `top` scrolled off (w_skipcol).
  rl: RowLayout
  height, top, skip: int

proc topWindow(rl: RowLayout, viewport: ViewPort, height: int): TopWindow =
  ## The window `viewport` shows, `height` rows high. An offset left from
  ## another width is cut to the top line.
  if not rl.lineWrap:
    viewport.topWrapOffset = 0
  elif viewport.topLine >= 0 and viewport.topLine < rl.lineCount:
    viewport.topWrapOffset =
      max(0, min(viewport.topWrapOffset, rl.lineRows(viewport.topLine) - 1))
  let top = clamp(viewport.topLine, 0, rl.lineCount - 1)
  TopWindow(
    rl: rl,
    height: max(1, height),
    top: top,
    skip: if top == viewport.topLine: viewport.topWrapOffset else: 0,
  )

proc store(w: TopWindow, viewport: ViewPort) =
  ## Move `viewport` to `w`'s top.
  if w.top != viewport.topLine or w.skip != viewport.topWrapOffset:
    viewport.restoreViewportTop(w.top, w.skip)

proc heightOf(w: TopWindow, line: int): int =
  ## Rows of `line` cut at the window height; a closed fold is one row.
  min(w.rl.rowsOf(line), w.height)

proc above(w: TopWindow, line: var int): int =
  ## Step `line` one line up (topline_back): the rows it takes, or `high(int)`
  ## above the first line.
  dec line
  if line < 0:
    return high(int)
  line = w.rl.buffer.foldStart(line)
  w.heightOf(line)

proc below(w: TopWindow, line: var int): int =
  ## Step `line` one line down (botline_forw), as `above`.
  inc line
  if line >= w.rl.lineCount:
    return high(int)
  result = w.heightOf(line)
  line = w.rl.buffer.foldEnd(line)

proc botline(w: TopWindow): tuple[line, emptyRows: int] =
  ## The line just below the last one drawn whole, and the rows left under
  ## the lines drawn whole (comp_botline).
  let (line, rows) = w.rl.botline(w.top, w.skip, w.height)
  (line, w.height - rows)

proc addRows(a, b: int): int =
  if a == high(int) or b == high(int):
    high(int)
  else:
    a + b

proc scrollCursorHalfway(
    w: var TopWindow, line: int, preferAbove: bool, atEnd = false
) =
  ## Put the cursor line in the middle of the window. With `atEnd`, the "~"
  ## rows past the last line take room too, as for zz.
  var
    up = w.rl.buffer.foldStart(line)
    down = w.rl.buffer.foldEnd(line)
    used = w.heightOf(up)
    topline = up
    above, below = 0
  block walk:
    while topline > 0:
      for round in 1 .. 2:
        let addBelow =
          if preferAbove:
            round == 2 and below < above
          else:
            round == 1 and below <= above
        if addBelow:
          if down < w.rl.lineCount - 1:
            let rows = w.below(down)
            used = addRows(used, rows)
            if used > w.height:
              break walk
            below += rows
          else:
            inc below # a "~" row
            if atEnd:
              inc used
        let addAbove =
          if preferAbove:
            round == 1 and below >= above
          else:
            round == 1 and below > above
        if addAbove:
          let rows = w.above(up)
          used = addRows(used, rows)
          if used > w.height:
            break walk
          above += rows
          topline = up
  let top = w.rl.buffer.foldStart(topline)
  # Vim keeps rows scrolled off only in a line taller than the window. A line
  # that fits shows from its head, as with 'smoothscroll'.
  if top != w.top or w.rl.rowsOf(top) <= w.height:
    w.top = top
    w.skip = 0

proc scrollCursorTop(w: var TopWindow, line: int) =
  ## Scroll down so that the cursor line, above the window, is at the top.
  var
    used = w.heightOf(line)
    scrolled = if line < w.top: used else: 0
    up = w.rl.buffer.foldStart(line)
    newTop = up
  while up > 0:
    let rows = w.above(up)
    if up < w.top:
      scrolled += rows
    if newTop >= w.top or scrolled > 1:
      break
    used += rows
    if used > w.height:
      break
    newTop = up
  if used > w.height:
    w.scrollCursorHalfway(line, false)
    return
  let top = min(min(newTop, w.top), line)
  if top != w.top:
    w.top = top
    w.skip = 0

proc scrollCursorBot(w: var TopWindow, line, botline, emptyRows: int) =
  ## Scroll up so that the cursor line, at or below `botline`, is at the
  ## bottom.
  var
    used = w.heightOf(line)
    scrolled = 0
    up = w.rl.buffer.foldStart(line)
    down = w.rl.buffer.foldEnd(line)
  if line >= botline:
    scrolled = used
    if line == botline:
      scrolled -= emptyRows
  while up > 0 and up > botline:
    let rows = w.above(up)
    used = addRows(used, rows)
    if used > w.height:
      break
    if up >= botline:
      scrolled += rows
      if up == botline:
        scrolled -= emptyRows
    if down < w.rl.lineCount - 1:
      let rows = w.below(down)
      used = addRows(used, rows)
      if used > w.height:
        break
      if scrolled < 1 and down >= botline:
        scrolled += rows
        if down == botline:
          scrolled -= emptyRows
  var lines = 0
  if scrolled <= 0:
    lines = 0
  elif used > w.height:
    lines = used
  else:
    # Scrolling the top line off frees only the rows it still shows. Vim
    # counts all its rows, which after a <C-e> by rows would scroll too few.
    var
      off = w.rl.buffer.foldEnd(w.top)
      freed = min(w.rl.rowsOf(w.top) - w.skip, w.height)
    lines = 1
    while freed < scrolled and off < botline:
      freed = addRows(freed, w.below(off))
      inc lines
    if freed < scrolled:
      lines = 9999
  if lines >= w.height and lines > 1:
    w.scrollCursorHalfway(line, true)
  elif lines > 0:
    var top = w.top
    for _ in 0 ..< lines:
      let last = w.rl.buffer.foldEnd(top)
      if last >= w.rl.lineCount - 1:
        break
      top = last + 1
    w.top = top
    w.skip = 0

proc scrollCursorTopSet(w: var TopWindow, line, seg, cellX: int) =
  ## Put the cursor line at the top, as Vim's scroll_cursor_top with always
  ## does for zt. Rows scrolled off the top line stay while the cursor, on
  ## row `seg` at `cellX`, is past their end, and always in a line taller
  ## than the window (Vim puts that one in the middle).
  let top = w.rl.buffer.foldStart(line)
  if top != w.top:
    w.top = top
    w.skip = 0
  elif line == top and w.rl.rowsOf(line) <= w.height and
      (seg < w.skip or (seg == w.skip and cellX == 0)):
    w.skip = 0

proc scrollCursorBotSet(w: var TopWindow, line: int) =
  ## Put the cursor line at the bottom, as Vim's scroll_cursor_bot with
  ## set_topbot does for zb: the top is the first of the most whole lines
  ## that fit down to it, with no rows scrolled off. A cursor line taller
  ## than the window keeps the top line; `scrollTallTopLine` then scrolls
  ## inside it to the cursor's row.
  var
    up = line + 1
    used = 0
  while up > 0:
    up = w.rl.buffer.foldStart(up - 1)
    let rows = w.rl.rowsOf(up)
    if used + rows > w.height:
      break
    used += rows
    w.top = up
  w.skip = 0

proc updateTopline(w: var TopWindow, line: int) =
  ## Scroll the window to the cursor on `line` as Vim's update_topline: to
  ## its top or bottom when it is near, else so that it is in the middle. A
  ## line that sticks out at the bottom is a line below.
  var checkBot = false
  if line < w.top:
    let halfHeight = max(2, w.height div 2 - 1)
    var
      n = 0
      l = line
    while l < w.top:
      inc n
      if l >= w.rl.lineCount - 1 or n >= halfHeight:
        break
      l = w.rl.buffer.foldEnd(l) + 1
    if n >= halfHeight:
      w.scrollCursorHalfway(line, false)
    else:
      w.scrollCursorTop(line)
      checkBot = true
  else:
    # A closed fold shows from its start, with no rows scrolled off.
    let fold = w.rl.buffer.foldState.getCollapsedFoldAt(w.top)
    if fold.isSome:
      w.top = fold.get.startLine
      w.skip = 0
    checkBot = true

  if checkBot:
    let (botline, emptyRows) = w.botline
    if botline < w.rl.lineCount and line >= botline:
      var
        lines = 0
        l = line
      while l >= botline:
        inc lines
        if l < 0 or lines > w.height + 1:
          break
        l = w.rl.buffer.foldStart(l) - 1
      if lines <= w.height + 1:
        w.scrollCursorBot(line, botline, emptyRows)
      else:
        w.scrollCursorHalfway(line, false)

proc scrollTallTopLine(w: var TopWindow, line, seg: int) =
  ## When the cursor is in the top line, scroll inside it by as few rows as
  ## bring the cursor's row `seg` into view, as Vim's curs_columns does with
  ## 'scrolloff' 0 for a line taller than the window. Also a line that fits
  ## can have rows scrolled off, by a scroll by rows such as <C-e>.
  if line != w.top or w.rl.buffer.foldState.getCollapsedFoldAt(line).isSome:
    return
  if seg < w.skip:
    w.skip = seg
  elif seg - w.skip >= w.height:
    w.skip = seg - w.height + 1

proc followCursor(
    w: var TopWindow, viewport: ViewPort, line, column: int, onTabEnd: bool
) =
  ## Scroll `w` down or up to the cursor as Vim's update_topline, store it in
  ## `viewport` and scroll that sideways.
  w.updateTopline(line)
  w.scrollTallTopLine(line, w.rl.cursorCell(line, column).wrapSeg)
  w.store(viewport)
  w.rl.scrollLeftCellToCursor(viewport, line, column, onTabEnd)

proc scrollViewportToCursor*(
    rl: RowLayout,
    viewport: ViewPort,
    cursorLine, cursorColumn, visibleHeight: int,
    onTabEnd = false,
) =
  ## Keep the cursor in view: down and up as Vim's update_topline does
  ## (`updateTopline`), sideways as `scrollLeftCellToCursor`. Shared by input
  ## and render paths.
  if rl.buffer.isNil or rl.lineCount == 0:
    viewport.topLine = 0
    viewport.topWrapOffset = 0
    viewport.leftCell = 0
    return

  let line = clamp(cursorLine, 0, rl.lineCount - 1)
  var w = rl.topWindow(viewport, visibleHeight)
  w.followCursor(viewport, line, max(0, cursorColumn), onTabEnd)

type CursorLineSpot* = enum
  ## Where zt, zz and zb put the cursor line in the window.
  clsTop
  clsMiddle
  clsBottom

proc scrollCursorLineTo*(
    rl: RowLayout,
    viewport: ViewPort,
    cursorLine, cursorColumn, visibleHeight: int,
    spot: CursorLineSpot,
    onTabEnd = false,
) =
  ## Put the cursor line at the top of the window (zt), in its middle (zz)
  ## or at its bottom (zb), as Vim's nv_zet does, with the last line in the
  ## middle too. Then keep the cursor in view as the redraw after nv_zet
  ## does, which scrolls a line taller than the window to the cursor's row.
  if rl.buffer.isNil or rl.lineCount == 0:
    return
  let
    line = clamp(cursorLine, 0, rl.lineCount - 1)
    column = max(0, cursorColumn)
  var w = rl.topWindow(viewport, visibleHeight)
  case spot
  of clsTop:
    let cell = rl.cursorCell(line, column, onTabEnd = onTabEnd)
    w.scrollCursorTopSet(line, cell.wrapSeg, cell.cellX)
  of clsMiddle:
    w.scrollCursorHalfway(line, preferAbove = false, atEnd = true)
  of clsBottom:
    w.scrollCursorBotSet(line)
  w.followCursor(viewport, line, column, onTabEnd)
