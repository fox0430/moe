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

## Putting a register's text into a buffer, as Vim's do_put: what `p`, `P`,
## `gp` and `gP` do in Normal mode and, after deleting the selection, in
## Visual mode.

import std/[options, strutils, unicode]

import pkg/results

import
  ../[config, cursor_util, registers, render_utils, types, unicode_utils, wanted_column]
import ../buffer/[core, edit, fold]

type
  PutFlag* = enum
    pfCursorEnd ## Leave the cursor just after the new text (gp, gP)
    pfLines ## Put the text as lines whatever it holds (`p` over lines)
    pfSplitLine
      ## Lines go between the halves of the cursor's line, split after its
      ## character when putting forward (`p` over characters)

  PutArea* = object ## What a put brought in (Vim's '[ and '] marks)
    first*: BufferPosition ## Its first character
    last*: BufferPosition ## Its last character

proc putSource*(
    buffer: TextBuffer, registers: Registers, name: char, clipboard: ClipboardConfig
): Result[Register, string] =
  ## The register `name` as a put brings it into `buffer`, its text made fit
  ## for the buffer. Empty, it was never written and there is nothing to put
  ## (Vim's E353); what an empty yank left puts nothing, but quietly. Fails
  ## only when reading a system selection does.
  var reg = ?registers.textToPut(name, clipboard)
  case reg.kind
  of rkChars:
    for text in reg.buffer.mitems:
      text = buffer.preparePastedText(text)
  of rkLines:
    # Line by line, each with its break: a CR before it goes with it, as in
    # CRLF, and one within the line breaks it.
    var lines = newSeqOfCap[string](reg.buffer.len)
    for line in reg.buffer:
      lines.add buffer.preparePastedText(line & "\n").withoutLastLineBreak.split('\n')
    reg.buffer = lines
  of rkBlock:
    for row in reg.buffer.mitems:
      row = buffer.preparePastedRow(row)
  ok(reg)

template tryEdit(r: Result[(), string]) =
  ## Make the put fail with a buffer edit that does. (`discard ?` would read
  ## as a discarded edit to test_no_discard_buffer_edits.)
  let editResult = r
  if editResult.isErr:
    return err(editResult.error)

proc putBlock(
    buffer: TextBuffer,
    state: EditorState,
    rows: seq[string],
    width: int,
    forward: bool,
    count: int,
    cursorEnd: bool,
): Result[PutArea, string] =
  ## Put the block `rows`, `count` times side by side, as Vim's do_put does a
  ## MBLOCK register: each row on a line of its own from the cursor's line
  ## down, at the cell after the cursor's character when `forward`, else at
  ## its first. A line too short to reach that cell is padded with blanks, a
  ## tab across it is split into blanks, a character across it moves after
  ## the row, and lines are added past the end of the buffer. Each copy of a
  ## row is padded to `width` cells, but for the last when nothing follows.
  let
    tabStop = state.tabStop
    first = state.cursor.line
    top = buffer.getLine(first)
    span = top.cellSpan(state.cursor.column, tabStop)
  var
    column = state.cursor.column
    cell = span.first
  if forward and column < top.charLen:
    cell = span.last + 1
    # The next character, past the marks that go with the cursor's.
    for g in top.glyphsOf(tabStop):
      if column < g.next:
        column = g.next
        break
  var
    lines = newSeqOfCap[string](rows.len)
    area: PutArea
  for i, row in rows:
    let
      line = first + i
      text =
        if line < buffer.len:
          buffer.getLine(line)
        else:
          ""
    var
      reached = 0 ## The cell after the characters left of `cell` (vcol)
      textCol = 0
      lastCells = 0 ## Cells of the last of them (incr)
      lastColumn = 0
      lastRune: Rune
    for g in text.glyphsOf(tabStop):
      if reached >= cell:
        break
      reached = g.cell + g.width
      textCol = g.next
      lastCells = g.width
      lastColumn = g.column
      lastRune = g.rune
    let shortLine = reached < cell or (reached == cell and textCol >= text.charLen)
    var
      startSpaces = 0
      endSpaces = 0
      deleted = 0
    if reached < cell:
      startSpaces = cell - reached
    elif reached > cell:
      endSpaces = reached - cell
      startSpaces = lastCells - endSpaces
      textCol = lastColumn
      if lastRune == TAB_CHAR:
        deleted = 1
      else:
        # Only a tab splits into blanks; another character goes after the row.
        endSpaces = 0
    var rowCells = 0
    for (rune, _) in row.chars:
      # Each counted as if at the line start, as Vim does.
      rowCells += rune.runeCells(0, tabStop)
    let spaces = max(0, width - rowCells)
    if row.len + spaces > 0 and
        count > (high(int32) - startSpaces - endSpaces) div (row.len + spaces):
      return err("E1240: Resulting text too long")
    var middle = ' '.repeat(startSpaces)
    for j in 0 ..< count:
      middle.add row
      if (j < count - 1 or not shortLine) and spaces > 0:
        middle.add ' '.repeat(spaces)
    middle.add ' '.repeat(endSpaces)
    lines.add text.charSubStr(0, textCol) & middle & text.charSubStr(textCol + deleted)
    if i == 0:
      area.first = BufferPosition(line: first, column: column + startSpaces)
    area.last = BufferPosition(line: line, column: max(0, textCol + middle.charLen - 1))
  tryEdit buffer.replaceLines(first, min(rows.len, buffer.len - first), lines)
  state.cursor =
    if cursorEnd:
      BufferPosition(line: area.last.line, column: area.last.column + 1)
    else:
      area.first
  ok(area)

proc putText*(
    buffer: TextBuffer,
    state: EditorState,
    source: Register,
    forward: bool,
    count = 1,
    flags: set[PutFlag] = {},
    blockEnd = -1,
    blockAnchor = BufferPosition(),
    byFolds = true,
): Result[PutArea, string] =
  ## Put `source` (from `putSource`) `count` times at the cursor, as Vim's
  ## do_put, and return what it brought in. Linewise text goes on lines of
  ## its own below the cursor's line when `forward`, else above it;
  ## `byFolds`, below or above the closed fold the cursor is on. A block goes
  ## as `putBlock` puts it. Other text goes after the cursor's character when
  ## `forward`, else before it, and text within a line also into the lines
  ## below down to `blockEnd` (a Visual block) at the first line's screen
  ## cell, passing over a line where no character starts there, as Vim does.
  ## A tab gives its last cell when the put comes after where the block
  ## started (`blockAnchor`), as Vim's getvcol puts the cursor there.
  ##
  ## The cursor lands on the first non-blank of the first line put, the last
  ## character of text within a line, or the start of text across lines or of
  ## a block. With `pfCursorEnd` it goes just after the text, as it does after
  ## text within a line while Insert waits to resume (Ctrl-o `p`). Only while
  ## Insert waits may it rest past the end of its line. The caller holds the
  ## transaction.
  let
    count = max(1, count)
    asBlock = source.kind == rkBlock and pfLines notin flags
  var
    text = if asBlock: "" else: source.getContent
    isLine = source.isLine
    forward = forward
    cursor = state.cursor
    area: PutArea
  if pfLines in flags and not isLine:
    isLine = true
    text.add '\n'
  # A block put measures each of its rows instead.
  if not asBlock and text.len > 0 and count > high(int32) div text.len:
    return err("E1240: Resulting text too long")

  if source.kind == rkLines and pfSplitLine in flags:
    let line = buffer.getLine(cursor.line)
    var at = cursor.column
    if forward and at < line.charLen:
      inc at
    tryEdit buffer.insertText(BufferPosition(line: cursor.line, column: at), "\n")
    forward = true

  if isLine:
    var line = cursor.line
    let fold = buffer.foldState.getCollapsedFoldAt(line)
    if byFolds and fold.isSome:
      line = if forward: fold.get.endLine else: fold.get.startLine
    let
      first =
        if forward:
          line + 1
        else:
          line
      last = first + count * text.count('\n') - 1
    # Below a line, the lines start after its line break and drop their last.
    var lines = newStringOfCap(text.len * count + 1)
    if forward:
      lines.add '\n'
    for _ in 1 .. count:
      lines.add text
    if forward:
      lines.setLen(lines.len - 1)
      let lineEnd = BufferPosition(line: line, column: buffer.getLine(line).charLen)
      tryEdit buffer.insertText(lineEnd, lines, openLine = olBelow)
    else:
      tryEdit buffer.insertText(
        BufferPosition(line: line, column: 0), lines, openLine = olAbove
      )
    area = PutArea(
      first: BufferPosition(line: first, column: 0),
      last: BufferPosition(line: last, column: max(0, buffer.getLine(last).charLen - 1)),
    )
    cursor =
      if pfCursorEnd in flags:
        BufferPosition(line: min(last + 1, buffer.len - 1), column: 0)
      else:
        BufferPosition(line: first, column: firstNonBlankColumn(buffer.getLine(first)))
  elif asBlock:
    area = ?buffer.putBlock(
      state, source.buffer, source.width, forward, count, pfCursorEnd in flags
    )
    cursor = state.cursor
  elif text.len == 0:
    area = PutArea(first: cursor, last: cursor)
  else:
    if forward and cursor.column < buffer.getLine(cursor.line).charLen:
      inc cursor.column
    let
      start = cursor
      putting = text.repeat(count)
    area = PutArea(first: start, last: start)
    if '\n' notin text:
      let cell =
        if blockEnd > start.line:
          buffer.getLine(start.line).cursorCell(
            start.column, state.tabStop, onTabEnd = start > blockAnchor
          )
        else:
          0
      tryEdit buffer.insertText(start, putting)
      if blockEnd > start.line:
        for line in start.line + 1 .. blockEnd:
          let column = buffer.getLine(line).columnStartingAt(cell, state.tabStop)
          if column >= 0:
            tryEdit buffer.insertText(
              BufferPosition(line: line, column: column), putting
            )
      cursor.column = start.column + text.charLen * count - 1
      area.last = cursor
      if pfCursorEnd in flags or state.resumesInsert:
        inc cursor.column
    else:
      tryEdit buffer.insertText(start, putting)
      let afterText = pasteEndPos(start, putting)
      area.last =
        BufferPosition(line: afterText.line, column: max(0, afterText.column - 1))
      if pfCursorEnd in flags:
        cursor = afterText

  let lineLen = buffer.getLine(cursor.line).charLen
  cursor.column = min(cursor.column, lineLen)
  if not state.resumesInsert:
    clampCursorToLastChar(cursor, lineLen)
  state.cursor = cursor
  ok(area)
