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
  SpanEdit* = object
    ## Text from `start` to `oldEnd` replaced by text from `start` to `newEnd`.
    start*, oldEnd*, newEnd*: BufferPosition
    atLineEnd*: bool
      ## Insertion at line end (or its deletion): a range starting there stays
      ## before it.
    guessed*: bool
      ## Guessed from a whole-line rewrite; may overlap surviving text, so it
      ## deletes nothing.
    rowsAtStart*: bool
      ## Added/dropped rows sit at `start`'s row, not below it: whole rows
      ## replaced, or a split at column 0 pushing the line down.

  Span* = object ## A range with an exclusive end.
    first*, last*: BufferPosition

  RowSpan* = object
    ## Rows `start ..< start + before` turned into `start ..< start + after`;
    ## rows below only shift.
    start*, before*, after*: int
    joinsAbove*: bool ## Dropped rows were joined onto the row above.

func reversed*(edit: SpanEdit): SpanEdit =
  SpanEdit(
    start: edit.start,
    oldEnd: edit.newEnd,
    newEnd: edit.oldEnd,
    atLineEnd: edit.atLineEnd,
    guessed: edit.guessed,
    rowsAtStart: edit.rowsAtStart,
  )

func isInsertion(edit: SpanEdit): bool =
  edit.oldEnd == edit.start

func inLine*(edit: SpanEdit): bool =
  ## Whether `edit` stays on one line with known columns.
  not edit.guessed and edit.oldEnd.line == edit.start.line and
    edit.newEnd.line == edit.start.line

func rows*(edit: SpanEdit): Option[RowSpan] =
  ## Rows `edit` adds or drops; none when it moves no row.
  let
    before = edit.oldEnd.line - edit.start.line
    after = edit.newEnd.line - edit.start.line
  if before > 0 or after > 0:
    some(
      RowSpan(
        start: edit.start.line + ord(not edit.rowsAtStart),
        before: before,
        after: after,
        joinsAbove: not edit.rowsAtStart,
      )
    )
  else:
    none(RowSpan)

iterator steps*(edit: SpanEdit): SpanEdit =
  ## Split a whole-row replacement into delete-then-insert so nothing lands on
  ## new text.
  if edit.rowsAtStart and not edit.isInsertion and edit.newEnd != edit.start:
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
        edit.atLineEnd == last.atLineEnd and edit.rowsAtStart == last.rowsAtStart:
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
