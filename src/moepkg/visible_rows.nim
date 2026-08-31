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

import std/options

import types, buffer/[core, fold], render_utils

type
  RowLayout* = object
    ## Row-walk context for a window frame. `maxWidth` is used only with `lineWrap`.
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

proc textCell*(
    text: string, column: int, lineWrap: bool, maxWidth, tabStop, leftColumn: int
): tuple[wrapSeg, cellX: int] =
  ## Display cell of `text[column]`: (wrapSeg, cellX). Wrap-aware; no-wrap uses `leftColumn` origin.
  if lineWrap:
    cursorWrapPosition(text, column, maxWidth, tabStop)
  else:
    (0, displayWidthBetweenWithTabs(text, leftColumn, column, tabStop))

proc cursorCell*(
    rl: RowLayout, line, column: int, leftColumn: int = 0
): tuple[wrapSeg, cellX: int] =
  ## `textCell` for buffer position. Hidden fold line returns marker origin.
  if rl.buffer.isNil or line < 0 or line >= rl.lineCount:
    return (0, 0)
  if rl.buffer.foldState.getCollapsedFoldAt(line).isSome:
    return (0, 0)
  textCell(
    rl.buffer.getLine(line), column, rl.lineWrap, rl.maxWidth, rl.tabStop, leftColumn
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

proc cellToColumn*(rl: RowLayout, line, wrapSeg, cellX: int, leftColumn: int = 0): int =
  ## Char index at (`wrapSeg`, `cellX`). Inverse of `cursorCell`.
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

func wrapPosAbove*(aLine, aSeg, bLine, bSeg: int): bool {.inline.} =
  ## True if (aLine, aSeg) is above (bLine, bSeg) in wrapped order.
  aLine < bLine or (aLine == bLine and aSeg < bSeg)

proc scrollViewportToCursor*(
    rl: RowLayout, viewport: ViewPort, cursorLine, cursorColumn, visibleHeight: int
) =
  ## Keep cursor visible with minimal scroll. Shared by input and render paths.
  if rl.buffer.isNil or rl.lineCount == 0:
    viewport.topLine = 0
    viewport.topWrapOffset = 0
    return

  if not rl.lineWrap:
    viewport.topWrapOffset = 0
  elif viewport.topLine >= 0 and viewport.topLine < rl.lineCount:
    # Clamp stale offset after width change.
    viewport.topWrapOffset =
      max(0, min(viewport.topWrapOffset, rl.lineRows(viewport.topLine) - 1))

  let
    line = clamp(cursorLine, 0, rl.lineCount - 1)
    seg = rl.cursorCell(line, max(0, cursorColumn)).wrapSeg
    rows = max(1, visibleHeight)

  if wrapPosAbove(line, seg, viewport.topLine, viewport.topWrapOffset):
    viewport.restoreViewportTop(line, seg)
  else:
    let (latLine, latOff) = rl.walkBackRows(line, seg, rows - 1)
    if wrapPosAbove(viewport.topLine, viewport.topWrapOffset, latLine, latOff):
      viewport.restoreViewportTop(latLine, latOff)
