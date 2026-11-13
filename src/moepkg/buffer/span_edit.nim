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

## An edit's effect on the text, which followers track.

import std/options

import ../primitives

type
  RowsAt* = enum
    ## Where the rows an edit adds or drops sit.
    raBelow ## Below `start`'s row, which the edit starts inside.
    raStart ## At `start`'s row: whole rows replaced.
    raSplitStart
      ## A split at column 0: at `start`'s row for what follows the text down
      ## (folds, line markers), below it for Vim's marks, which open_line
      ## leaves on the row it splits.

  SpanEdit* = object
    ## Text from `start` to `oldEnd` replaced by text from `start` to `newEnd`.
    start*, oldEnd*, newEnd*: BufferPosition
    atLineEnd*: bool
      ## Insertion at line end (or its deletion): a range starting there stays
      ## before it.
    guessed*: bool
      ## Guessed from a whole-line rewrite; may overlap surviving text, so it
      ## deletes nothing.
    rowsAt*: RowsAt

  Span* = object ## A range with an exclusive end.
    first*, last*: BufferPosition

  RowSpan* = object
    ## Rows `start ..< start + before` turned into `start ..< start + after`;
    ## rows below only shift.
    start*, before*, after*: int

  RowMoveKind = enum
    rmCommand ## An edit a command made, as Vim's mark_adjust takes it.
    rmReplace
      ## A span replaced as a whole from outside the commands, as Neovim's
      ## nvim_buf_set_text takes an API edit.
    rmRestore ## Undo/redo putting rows back, as Vim's u_undoredo.

  RowMove* = object
    ## Rows an edit or undo/redo moved, as mark_adjust takes them: rows
    ## `first ..< last` go, and the rows from `last` on shift by `shift`. With
    ## none gone, rows came in just above `last`.
    first, last, shift: int
    case kind: RowMoveKind
    of rmCommand, rmReplace:
      edit: SpanEdit
    of rmRestore:
      discard

func reversed*(edit: SpanEdit): SpanEdit =
  SpanEdit(
    start: edit.start,
    oldEnd: edit.newEnd,
    newEnd: edit.oldEnd,
    atLineEnd: edit.atLineEnd,
    guessed: edit.guessed,
    rowsAt: edit.rowsAt,
  )

func goesTopDown*(edits: openArray[SpanEdit]): bool =
  ## Whether `edits`, taken in order, go top down: each starts at or below
  ## where the one before it ended.
  for i in 1 ..< edits.len:
    if edits[i].start < edits[i - 1].newEnd:
      return false
  true

func isInsertion(edit: SpanEdit): bool =
  edit.oldEnd == edit.start

func inLine*(edit: SpanEdit): bool =
  ## Whether `edit` stays on one line with known columns.
  not edit.guessed and edit.oldEnd.line == edit.start.line and
    edit.newEnd.line == edit.start.line

func rowsFrom(edit: SpanEdit, start: int): Option[RowSpan] =
  let
    before = edit.oldEnd.line - edit.start.line
    after = edit.newEnd.line - edit.start.line
  if before > 0 or after > 0:
    some(RowSpan(start: start, before: before, after: after))
  else:
    none(RowSpan)

func rows*(edit: SpanEdit): Option[RowSpan] =
  ## Rows `edit` adds or drops; none when it moves no row.
  edit.rowsFrom(edit.start.line + ord(edit.rowsAt == raBelow))

func rowMove*(edit: SpanEdit): Option[RowMove] =
  ## The rows `edit` moves, as Vim's mark_adjust takes them; none when it adds
  ## or drops none. Rows come and go after the rewritten ones.
  let rows = edit.rowsFrom(edit.start.line + ord(edit.rowsAt != raStart))
  if rows.isNone:
    return none(RowMove)
  let
    r = rows.get
    shift = r.after - r.before
    first =
      if shift >= 0:
        r.start + r.before
      else:
        r.start + r.after
  some(
    RowMove(
      first: first, last: r.start + r.before, shift: shift, kind: rmCommand, edit: edit
    )
  )

func replaceMove*(edit: SpanEdit): RowMove =
  ## The rows `edit` moves as a span replaced as a whole, as Neovim's
  ## nvim_buf_set_text takes them: the rows it starts on and goes over go to
  ## its start, and the rows from its last on shift.
  RowMove(
    first: edit.start.line,
    last: edit.oldEnd.line,
    shift: edit.newEnd.line - edit.oldEnd.line,
    kind: rmReplace,
    edit: edit,
  )

func restoreMove*(rows: RowSpan): RowMove =
  ## Undo/redo putting `rows` back, as Vim's u_undoredo moves marks: the rows
  ## it saved go, unless as many come back.
  let shift = rows.after - rows.before
  RowMove(
    first: rows.start,
    last:
      if shift == 0:
        rows.start
      else:
        rows.start + rows.before,
    shift: shift,
    kind: rmRestore,
  )

func joinsAbove(move: RowMove): bool =
  ## Whether the rows `move` drops were joined onto the row above them.
  move.kind == rmCommand and move.edit.rowsAt != raStart

func moved*(line: int, move: RowMove): int =
  ## Where a mark on `line` goes across `move`, as Vim's mark_adjust keeps it:
  ## rows that go send it to the row after them, or onto the row they joined.
  if line >= move.last:
    line + move.shift
  elif line >= move.first:
    if move.joinsAbove:
      move.first - 1
    else:
      move.first
  else:
    line

iterator steps*(edit: SpanEdit): SpanEdit =
  ## Split a whole-row replacement into delete-then-insert so nothing lands on
  ## new text.
  if edit.rowsAt != raBelow and not edit.isInsertion and edit.newEnd != edit.start:
    yield SpanEdit(start: edit.start, oldEnd: edit.oldEnd, newEnd: edit.start)
    yield SpanEdit(start: edit.start, oldEnd: edit.start, newEnd: edit.newEnd)
  else:
    yield edit

proc record*(edits: var seq[SpanEdit], edit: SpanEdit) =
  ## Append `edit`, merging with the last one when typing continues it.
  ## Deletions never merge.
  if edits.len > 0:
    let last = edits[^1]
    if last.isInsertion and edit.isInsertion and edit.start == last.newEnd and
        edit.atLineEnd == last.atLineEnd and edit.rowsAt == last.rowsAt:
      edits[^1].newEnd = edit.newEnd
      return
  edits.add edit

func moved(
    pos: BufferPosition, edit: SpanEdit, staysAtInsertion: bool
): BufferPosition =
  if pos < edit.start or (staysAtInsertion and pos == edit.start):
    pos
  elif pos < edit.oldEnd:
    edit.start
  elif pos.line == edit.oldEnd.line:
    BufferPosition(
      line: edit.newEnd.line,
      column: edit.newEnd.column + pos.column - edit.oldEnd.column,
    )
  else:
    BufferPosition(
      line: pos.line + edit.newEnd.line - edit.oldEnd.line, column: pos.column
    )

func joins(move: RowMove, line: int): bool =
  ## Whether `move` joins `line`, the last of the rows it drops, onto the row
  ## above, as `J` does.
  move.joinsAbove and move.first < move.last and line == move.edit.oldEnd.line

func replacedCursorMoved(pos: BufferPosition, edit: SpanEdit): BufferPosition =
  ## Where a window's cursor goes across `edit` replacing its span, as
  ## Neovim's nvim_buf_set_text moves it: with the text after the span, or
  ## kept in what replaced it, on its last character at most.
  if pos.line < edit.start.line:
    pos
  elif pos.line > edit.oldEnd.line:
    BufferPosition(
      line: pos.line + edit.newEnd.line - edit.oldEnd.line, column: pos.column
    )
  elif pos >= edit.oldEnd:
    pos.moved(edit, staysAtInsertion = false)
  elif pos.line < edit.newEnd.line or
      (pos.line == edit.newEnd.line and pos.column <= edit.newEnd.column):
    pos
  else:
    let lineStart = if edit.newEnd.line == edit.start.line: edit.start.column else: 0
    BufferPosition(
      line: edit.newEnd.line,
      column: edit.newEnd.column - ord(edit.newEnd.column > lineStart),
    )

func windowCursorMoved*(pos: BufferPosition, move: RowMove): BufferPosition =
  ## Where the cursor of a window other than the current one goes across
  ## `move`, as Vim's mark_adjust moves it: with the rows below, onto the line
  ## a join took its own into, or to the start of the line above rows deleted
  ## under it. A line split or rewritten keeps it, past its end if need be. A
  ## replaced span moves it as Neovim does.
  if move.kind == rmReplace:
    pos.replacedCursorMoved(move.edit)
  elif move.joins(pos.line):
    pos.moved(move.edit, staysAtInsertion = false)
  elif pos.line >= move.last:
    BufferPosition(line: pos.line + move.shift, column: pos.column)
  elif pos.line >= move.first:
    BufferPosition(line: max(move.first - 1, 0))
  else:
    pos

func keepsRows(move: RowMove): bool =
  ## Whether `move` replaces a span with text over more than one row, which
  ## Neovim leaves a top line in.
  move.kind == rmReplace and move.edit.newEnd.line > move.edit.start.line

func moveTopAcross*(top, wrapOffset: var int, move: RowMove) =
  ## Move `top`, the top line of a window other than the current one, across
  ## `move` as Vim's mark_adjust moves it. Lines an edit puts just above it
  ## come into view. A line it no longer shows starts at its first screen row.
  ## A replaced span moves it as Neovim does, except that it stays on the
  ## rows the span has left: Neovim waits for its cursor to bring it back,
  ## which a window scrolled away from its cursor never does here.
  if top >= move.first and top < move.last:
    top =
      if move.keepsRows:
        min(top, move.edit.newEnd.line)
      else:
        max(move.first - 1, 0)
    wrapOffset = 0
  elif top > move.last or
      (top == move.last and (move.kind == rmRestore or move.first < move.last)):
    top += move.shift
  elif top == move.last and move.shift > 0:
    wrapOffset = 0

func deletes*(edit: SpanEdit, span: Span): bool =
  ## Whether `edit` deletes all of `span`, or the line an empty one is on.
  if edit.guessed:
    false
  elif span.first == span.last:
    not (edit.atLineEnd and span.first == edit.start) and
      edit.start <= BufferPosition(line: span.first.line) and
      BufferPosition(line: span.first.line + 1) <= edit.oldEnd
  else:
    edit.start <= span.first and span.last <= edit.oldEnd

func moved*(span: Span, edit: SpanEdit): Span =
  ## Where `span` goes across `edit`; inserted text at either edge stays out.
  result = span
  for step in edit.steps:
    result.first = result.first.moved(step, staysAtInsertion = step.atLineEnd)
    result.last = result.last.moved(step, staysAtInsertion = true)
    if result.last < result.first:
      result.last = result.first
