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

## The column vertical moves aim for (Vim's curswant). It is a screen cell
## counted from the line start, so a tab or a wide character on the way does
## not shift where `j` and `k` land.

import std/unicode

import types, modes, render_utils, unicode_utils
import buffer/core

iterator cellsOf*(
    text: string, tabStop: int
): tuple[column: int, rune: Rune, cell, width, byte: int] =
  ## Each character of `text` with the cell it starts at, how many it takes
  ## and the byte it starts at.
  var
    column = 0
    cell = 0
    byte = 0
  for (rune, size) in text.chars:
    let width = rune.runeCells(cell, tabStop)
    yield (column, rune, cell, width, byte)
    cell += width
    column.inc
    byte += size

iterator glyphsOf*(
    text: string, tabStop: int
): tuple[column, next: int, rune: Rune, cell, width, byte: int] =
  ## Each character of `text` with the zero-width marks after it, which go
  ## with it as Vim's composing characters do: its column and the one after
  ## its marks, the cell it starts at, how many it takes and the byte it
  ## starts at. A mark that starts the text stands as a character.
  var
    glyph: tuple[column, next: int, rune: Rune, cell, width, byte: int]
    started = false
  for (column, rune, cell, width, byte) in text.cellsOf(tabStop):
    if width == 0 and started:
      glyph.next = column + 1
      continue
    if started:
      yield glyph
    glyph = (column, column + 1, rune, cell, width, byte)
    started = true
  if started:
    yield glyph

proc cellSpan*(text: string, column, tabStop: int): tuple[first, last: int] =
  ## The cells character `column` of `text` takes, as Vim's getvvcol: a
  ## combining mark's are those of the character it follows. Past the end, the
  ## one cell after the text.
  for g in text.glyphsOf(tabStop):
    if column < g.next:
      return (g.cell, g.cell + max(g.width, 1) - 1)
    result = (g.cell + g.width, g.cell + g.width)

proc shownFrom*(
    text: string, leftCell, width, tabStop: int
): tuple[column, cell, startByte, endByte: int] =
  ## The characters of `text`, with the marks after them, that a row `width`
  ## cells wide shows from `leftCell` on: the first one's column and the cell
  ## it starts at, and the bytes from it through the last one starting inside
  ## the row. Past the text, a column per cell after its end, starting at
  ## `leftCell`, and no bytes.
  result = (-1, leftCell, text.len, text.len)
  var columns, cells = 0
  for g in text.glyphsOf(tabStop):
    if result.column < 0:
      if g.cell + max(g.width, 1) > leftCell:
        result = (g.column, g.cell, g.byte, text.len)
    elif g.cell >= leftCell + width:
      result.endByte = g.byte
      return
    columns = g.next
    cells = g.cell + g.width
  if result.column < 0:
    result.column = columns + max(0, leftCell - cells)

proc columnStartingAt*(text: string, cell, tabStop: int): int =
  ## The character of `text` that starts at `cell`, or its end when the text
  ## ends there, else -1, as Vim's getvpos succeeds or fails. A combining mark
  ## starts nowhere, as it goes with the character it follows.
  var width = 0
  for g in text.glyphsOf(tabStop):
    if g.cell >= cell:
      return if g.cell == cell: g.column else: -1
    width = g.cell + g.width
  if width == cell: text.charLen else: -1

proc cursorCell*(text: string, column, tabStop: int, onTabEnd: bool): int =
  ## The cell character `column` of `text` starts at, or with `onTabEnd` its
  ## last cell when it is a tab. Past the end, the width of `text`.
  for (at, rune, cell, width, _) in text.cellsOf(tabStop):
    if at == column:
      return
        if onTabEnd and rune == TAB_CHAR:
          cell + width - 1
        else:
          cell
    result = cell + width

proc columnAtCell*(text: string, cell, tabStop: int, mode: EditorMode): int =
  ## The character of `text` that covers `cell`, as Vim's coladvance: on a
  ## shorter line the last character, or past it when the mode rests past it.
  let last = maxCursorColumn(text.charLen, mode)
  if cell == LineEnd:
    return last
  min(screenXToCharIndex(text, 0, cell, tabStop), last)

proc cursorCell*(s: EditorState): int =
  ## The cell the cursor shows on, as Vim's getvvcol: on a tab its last cell in
  ## Normal mode, and in Visual when the cursor is after the anchor.
  let win = s.activeWindow
  if win.buffer.isNil or win.cursor.line notin 0 ..< win.buffer.len:
    return win.cursor.column
  let onTabEnd =
    if win.mode.isVisualAllMode:
      win.cursor > win.visualAnchor
    else:
      win.mode notin {EditorMode.Insert, EditorMode.Replace}
  win.buffer.getLine(win.cursor.line).cursorCell(win.cursor.column, s.tabStop, onTabEnd)

proc aimedColumn*(s: EditorState): int =
  ## The cell vertical moves and scrolls aim for: the one kept, else the
  ## cursor's, as Vim's update_curswant.
  let wanted = s.preferredColumn
  if wanted < 0: s.cursorCell else: wanted

proc columnAtCell*(s: EditorState, line, cell: int): int =
  ## The column on `line` of the active buffer a vertical move aiming for
  ## `cell` lands on.
  let buffer = s.activeWindow.buffer
  if buffer.isNil or line notin 0 ..< buffer.len:
    return 0
  buffer.getLine(line).columnAtCell(cell, s.tabStop, s.mode)

proc scrollCursor*(s: EditorState, to: BufferPosition) =
  ## Move the cursor as a scroll does, which keeps the column it aimed for as
  ## the one vertical moves want, as Vim keeps curswant.
  if to == s.cursor:
    return
  let aimed = s.aimedColumn
  s.cursor = to
  s.preferredColumn = aimed

proc scrollCursor*(s: EditorState, line: int) =
  ## Move the cursor to `line` as a scroll does: onto the column it aims for,
  ## as Vim's coladvance(curswant).
  s.scrollCursor(
    BufferPosition(line: line, column: s.columnAtCell(line, s.aimedColumn))
  )
