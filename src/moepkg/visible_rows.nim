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

## Visible-row traversal: the single walker mapping logical lines to screen
## rows and back.
##
## Two rules make the mapping non-trivial and both live here only:
## a collapsed fold renders as one marker row and hides its interior, and with
## line wrap a logical line expands to its wrap-segment count while the first
## visible line may start mid-line (`topWrapOffset`). The renderer, the screen
## cursor, the viewport scroll, the scrollbar and the mouse hit-test all derive
## their row arithmetic from `visibleLines` so they cannot drift apart.

import std/options

import types, buffer/[core, fold], render_utils

type
  RowLayout* = object
    ## Everything the row walk needs from a window's frame.
    ## `maxWidth` is the wrap width the renderer used; it is only consulted
    ## when `lineWrap` is set.
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
  ## Build the walk context and refresh the wrap cache for this frame, so
  ## callers never have to remember the `ensureFresh` / `cachedWrapCount`
  ## pairing.
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

iterator visibleLines*(
    rl: RowLayout, topLine, topWrapOffset: int, maxRows: int = high(int)
): VisibleLine =
  ## Walk the logical lines drawn from (`topLine`, `topWrapOffset`) downwards,
  ## at most `maxRows` screen rows. Lines hidden inside a collapsed fold are
  ## skipped; the fold's start line is yielded once as a marker row. A `topLine`
  ## that sits inside a collapsed fold starts below the marker, matching the
  ## renderer.
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
  ## Screen row of `targetLine`'s first wrap segment, relative to the viewport
  ## top. Negative when the segment is scrolled off the top (the row of segment
  ## `topWrapOffset` is 0); the fold-marker row when `targetLine` is hidden
  ## inside a collapsed fold. `limit` bounds the walk: a target at or below that
  ## row returns a value `>= limit` instead of scanning the rest of the buffer.
  ## `targetLine` must not be above `topLine` — callers reject that earlier.
  for vl in rl.visibleLines(topLine, topWrapOffset, limit):
    if vl.fold.isSome:
      if targetLine <= vl.fold.get.endLine:
        return vl.startRow
    elif vl.line == targetLine:
      return vl.startRow - vl.skipSegments
    result = vl.startRow + vl.rows

proc rowAt*(rl: RowLayout, topLine, topWrapOffset, screenRow: int): Option[VisibleRow] =
  ## Inverse of `rowOfLine`: the position drawn on `screenRow`. `none` when the
  ## row is below the last line of the buffer.
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
  ## The top (line, wrapOffset) sitting exactly `budget` visible rows above
  ## (`line`, `wrapSeg`) — the highest top that keeps that position on the last
  ## of `budget + 1` rows. Clamps to (0, 0) at the buffer top.
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

proc lineTopFor*(rl: RowLayout, line, wrapSeg, budget: int): int =
  ## `walkBackRows` for viewports that only scroll whole lines: the highest
  ## logical line that keeps (`line`, `wrapSeg`) within `budget` rows of the top
  ## without starting mid-line. A backward walk landing inside a line moves down
  ## to the next visible one, since starting at that line would push the target
  ## below the last row.
  let (top, offset) = rl.walkBackRows(line, wrapSeg, budget)
  if offset == 0 or top >= line:
    return top
  let fold = rl.buffer.foldState.getCollapsedFoldAt(top)
  min(
    if fold.isSome:
      fold.get.endLine + 1
    else:
      top + 1,
    line,
  )

proc totalRows*(rl: RowLayout, stopLine: int): int =
  ## Screen rows the logical lines [0, `stopLine`) occupy. A collapsed fold
  ## straddling `stopLine` contributes its marker row.
  for vl in rl.visibleLines(0, 0):
    if vl.line >= stopLine:
      break
    result = vl.startRow + vl.rows

proc textCell*(
    text: string, column: int, lineWrap: bool, maxWidth, tabStop, leftColumn: int
): tuple[wrapSeg, cellX: int] =
  ## Where a character index of `text` is drawn: its wrap segment and the
  ## display column within that segment. Without wrap the segment is always 0
  ## and the column is measured from `leftColumn`, the origin the renderer
  ## slices and expands tabs from. The single definition of the character
  ## index -> display cell direction.
  if lineWrap:
    cursorWrapPosition(text, column, maxWidth, tabStop)
  else:
    (0, displayWidthBetweenWithTabs(text, leftColumn, column, tabStop))

proc cursorCell*(
    rl: RowLayout, line, column: int, leftColumn: int = 0
): tuple[wrapSeg, cellX: int] =
  ## `textCell` for a buffer position. A position hidden inside a collapsed
  ## fold reports the marker row's origin, since that is what is drawn there.
  if rl.buffer.isNil or line < 0 or line >= rl.lineCount:
    return (0, 0)
  if rl.buffer.foldState.getCollapsedFoldAt(line).isSome:
    return (0, 0)
  textCell(
    rl.buffer.getLine(line), column, rl.lineWrap, rl.maxWidth, rl.tabStop, leftColumn
  )

proc segmentStartColumn*(rl: RowLayout, line, wrapSeg: int): int =
  ## Character index the given wrap segment of `line` starts at.
  if not rl.lineWrap or wrapSeg <= 0:
    return 0
  let text = rl.buffer.getLine(line)
  for _ in 0 ..< wrapSeg:
    let (charCount, _) =
      displayWidthSubstrWithTabs(text, result, rl.maxWidth, rl.tabStop)
    result += max(1, charCount)

proc cellToColumn*(rl: RowLayout, line, wrapSeg, cellX: int, leftColumn: int = 0): int =
  ## Inverse of `cursorCell`: the character index drawn at display column
  ## `cellX` of the given row. Tabs are expanded from the origin the renderer
  ## sliced at (the segment start with wrap, `leftColumn` without), so a click
  ## lands on the character actually painted there.
  if rl.buffer.isNil or line < 0 or line >= rl.lineCount:
    return 0
  let
    text = rl.buffer.getLine(line)
    start =
      if rl.lineWrap:
        rl.segmentStartColumn(line, wrapSeg)
      else:
        leftColumn
  clamp(
    start + screenXToCharIndex(text, start, cellX, rl.tabStop),
    0,
    max(0, text.charLen - 1),
  )
