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

import std/[options, strutils]

import pkg/results

import ../[config, cursor_util, registers, types, unicode_utils]
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

  PutSource* = object ## What a put of a register brings in
    text*: string ## Made fit for the buffer; linewise text ends in a line break
    isLine*: bool

proc putSource*(
    buffer: TextBuffer, registers: Registers, name: char, clipboard: ClipboardConfig
): Result[PutSource, string] =
  ## What a put of the register `name` brings into `buffer`. Fails only when
  ## reading a system selection does.
  let reg = ?registers.textToPut(name, clipboard)
  ok(PutSource(text: buffer.preparePastedText(reg.getContent), isLine: reg.isLine))

proc isNothing*(source: PutSource): bool =
  ## There is nothing to put (Vim's E353), as from an empty register.
  source.text.len == 0 and not source.isLine

template tryEdit(r: Result[(), string]) =
  ## Make the put fail with a buffer edit that does. (`discard ?` would read
  ## as a discarded edit to test_no_discard_buffer_edits.)
  let editResult = r
  if editResult.isErr:
    return err(editResult.error)

proc putText*(
    buffer: TextBuffer,
    state: EditorState,
    text: string,
    isLine: bool,
    forward: bool,
    count = 1,
    flags: set[PutFlag] = {},
    blockEnd = -1,
    byFolds = true,
): Result[PutArea, string] =
  ## Put `text` `count` times at the cursor, as Vim's do_put, and return what
  ## it brought in. Linewise `text` (`isLine`, ending in a line break) goes on
  ## lines of its own below the cursor's line when `forward`, else above it;
  ## `byFolds`, below or above the closed fold the cursor is on. Other text
  ## goes after the cursor's character when `forward`, else before it, and
  ## text within a line also into the lines below down to `blockEnd` (a
  ## Visual block) at the same character index, passing over lines too short
  ## for it (Vim takes the first line's screen column).
  ##
  ## The cursor lands on the first non-blank of the first line put, the last
  ## character of text within a line, or the start of text across lines. With
  ## `pfCursorEnd` it goes just after the text, as it does after text within a
  ## line while Insert waits to resume (Ctrl-o `p`). Only while Insert waits
  ## may it rest past the end of its line. The caller holds the transaction.
  let count = max(1, count)
  if text.len > 0 and count > high(int32) div text.len:
    return err("E1240: Resulting text too long")
  var
    text = text
    isLine = isLine
    forward = forward
    cursor = state.cursor
    area: PutArea

  if isLine and pfSplitLine in flags:
    let line = buffer.getLine(cursor.line)
    var at = cursor.column
    if forward and at < line.charLen:
      inc at
    tryEdit buffer.insertText(BufferPosition(line: cursor.line, column: at), "\n")
    forward = true
  if pfLines in flags and not isLine:
    isLine = true
    text.add '\n'

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
      for line in start.line .. max(start.line, blockEnd):
        if start.column <= buffer.getLine(line).charLen:
          tryEdit buffer.insertText(
            BufferPosition(line: line, column: start.column), putting
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
