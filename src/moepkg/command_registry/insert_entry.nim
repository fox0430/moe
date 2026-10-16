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

## i, a, A, I, o and O, and the Insert session every one of them starts.

import pkg/results

import ../[types, modes, insert_record, unicode_utils]
import ../buffer/core
import ../command_handlers/insert_commands

import core, operator_engine

proc enterInsert(ctx: CommandContext, entry: InsertEntry, count: int) =
  ctx.state.mode = EditorMode.Insert
  if entry.kind in {ieOpenBelow, ieOpenAbove}:
    # The typed text starts at the line start, indent and all, as Vim's edit()
    # with startln.
    ctx.state.insertStart.at.column = 0
    ctx.state.insertStart.stop.column = 0
  ctx.state.statusMessage = "-- INSERT --"
  ctx.state.startInsertRecord(entry, count, ctx.register)

proc beginInsert*(
    ctx: CommandContext, entry: InsertEntry, count: int
): Result[(), string] =
  ## Enter Insert at the cursor for `entry`.
  let begun = beginInsertModeSession(ctx.buffer, ctx.state)
  if begun.isErr:
    return err("Failed to begin transaction: " & begun.error)
  ctx.enterInsert(entry, count)
  ok(())

proc handleInsertAt*(
    ctx: CommandContext, kind: InsertEntryKind, count = 1
): Result[(), string] =
  ## Move the cursor where typing goes and enter Insert; the count types the
  ## text that many times (`3ifoo`, `2o`).
  if ctx.buffer.readOnly:
    ctx.state.statusMessage = "Buffer is read-only"
    return ok(())
  let line = ctx.buffer.getLine(ctx.cursor.line)
  case kind
  of ieInsert:
    discard
  of ieAppend:
    ctx.buffer.stepToAppend(ctx.state)
  of ieAppendEnd:
    ctx.cursor.column = line.charLen
  of ieInsertNonBlank:
    ctx.cursor.column = getLineIndent(line).len
  of ieOpenBelow, ieOpenAbove:
    let begun = beginInsertModeSession(ctx.buffer, ctx.state)
    if begun.isErr:
      return err("Failed to begin transaction: " & begun.error)
    let opened =
      if kind == ieOpenBelow:
        insertLineBelow(ctx.buffer, ctx.state)
      else:
        insertLineAbove(ctx.buffer, ctx.state)
    if opened.isErr:
      if begun.get:
        return rollbackAndPropagate(ctx, opened.error)
      return err(opened.error)
    # The session began before the line went in, so the line is part of it.
    ctx.enterInsert(InsertEntry(kind: kind), count)
    return ok(())
  of ieSubstitute, ieSubstituteLine, ieChangeToEnd, ieChange:
    return err("Not an insert command: " & $kind)
  ctx.beginInsert(InsertEntry(kind: kind), count)
