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

## The record of an Insert session that `.`, `[count]i` and Ctrl-A type again:
## the command that entered Insert, its count and what was typed. A key that
## changed the text goes on it; one that only moved the cursor ends it, as Vim's
## arrow keys do, and takes the untouched auto-indent with it.

import std/options

import pkg/results

import types, buffer, unicode_utils

proc repeatsTyped*(entry: InsertEntry): bool =
  ## Whether the entry's count types the text again (`3ifoo`, `2o`) rather than
  ## going to the command (`3s`, `3cw`).
  entry.kind in
    {ieInsert, ieAppend, ieAppendEnd, ieInsertNonBlank, ieOpenBelow, ieOpenAbove}

proc settleTyping*(state: EditorState) =
  ## Note where the last judged key left the cursor and the text, so the next
  ## key can tell whether anything else moved them (a click, a server edit).
  let buffer = state.activeWindow.buffer
  state.editState.typing.lastCursor = state.cursor
  state.editState.typing.lastVersion = if buffer.isNil: 0 else: buffer.contentVersion

proc keepChangeBefore(state: EditorState) =
  ## Keep what `.` repeats as the change before the record that starts now.
  state.editState.changeBefore =
    (state.editState.lastEditCommand, state.editState.insertRecord)

proc swapChangeBefore*(state: EditorState) =
  ## Trade what `.` repeats for the change before it and back, which `.` typed
  ## during the Ctrl-o pause reads.
  swap(state.editState.lastEditCommand, state.editState.changeBefore.command)
  swap(state.editState.insertRecord, state.editState.changeBefore.record)

proc startInsertRecord*(
    state: EditorState, entry: InsertEntry, count: int, register = none(char)
) =
  ## Begin recording the Insert session `entry` starts. Call once the command
  ## has moved the cursor and made its own edits.
  let count = max(1, count)
  state.keepChangeBefore()
  state.editState.insertRecord = InsertRecord(entry: entry, count: count)
  let repeats =
    if entry.repeatsTyped:
      count - 1
    else:
      0
  let buffer = state.activeWindow.buffer
  state.editState.typing = InsertTyping(
    open: true,
    repeatsLeft: repeats,
    linesBelow:
      if buffer.isNil:
        0
      else:
        buffer.len - 1 - state.cursor.line,
  )
  state.settleTyping()
  state.editState.lastEditCommand =
    some(LastEditCommand(kind: lecInsert, register: register))

proc closeInsertRecord*(state: EditorState) =
  ## End what the session adds to the record: Ctrl-A types it from now on and
  ## Escape no longer types it again.
  if state.editState.typing.open:
    state.editState.typing.open = false
    state.editState.lastInserted = some(state.editState.insertRecord.typed)
  state.editState.typing.repeatsLeft = 0

proc endInsertRecord*(state: EditorState) =
  state.closeInsertRecord()
  state.editState.typing.repeating = false

proc addTyped(record: var InsertRecord, typed: TypedInput) =
  ## Add `typed` to the record. Text that replaces the whole of the text put in
  ## just before it (a completion cycled through) takes its place, so `.` types
  ## only the last.
  if typed.kind == tiText and record.typed.len == 0 and typed.text.len == 0:
    return
  if typed.kind == tiText and record.typed.len > 0:
    let last = record.typed[^1]
    if last.kind == tiText and last.cursorAt == last.text.charLen and
        typed.removeBefore >= last.cursorAt:
      record.typed[^1] = TypedInput(
        kind: tiText,
        removeBefore: last.removeBefore + typed.removeBefore - last.cursorAt,
        removeAfter: last.removeAfter + typed.removeAfter,
        text: typed.text,
        cursorAt: typed.cursorAt,
      )
      return
  record.typed.add typed

proc noteTyped*(state: EditorState, typed: openArray[TypedInput]) =
  ## Add what a key typed, as a plain insert when nothing is being recorded.
  ## The count's repeats type what is recorded already.
  if state.editState.typing.repeating:
    return
  if not state.editState.typing.open:
    state.keepChangeBefore()
    state.editState.insertRecord =
      InsertRecord(entry: InsertEntry(kind: ieInsert), count: 1)
    state.editState.typing.open = true
    state.editState.lastEditCommand = some(LastEditCommand(kind: lecInsert))
  for t in typed:
    state.editState.insertRecord.addTyped(t)

proc untouchedAutoIndent*(buffer: TextBuffer, state: EditorState): Option[int] =
  ## The line holding only the indent Insert gave it, while nothing has changed
  ## the buffer since. Typing there keeps the indent, even when deleted again.
  let marked = state.editState.autoIndentedLine
  if marked.isSome and marked.get.version == buffer.contentVersion and
      marked.get.line < buffer.len:
    some(marked.get.line)
  else:
    none(int)

proc noteMove(state: EditorState) =
  ## The cursor moved without typing: the record ends, and the auto-indent
  ## nothing was typed after comes off the line if the cursor left it.
  state.closeInsertRecord()
  let buffer = state.activeWindow.buffer
  if not buffer.isNil:
    let untouched = buffer.untouchedAutoIndent(state)
    if untouched.isSome and untouched.get != state.cursor.line:
      let cleared = buffer.replaceLine(untouched.get, "")
      if cleared.isErr:
        state.statusMessage = cleared.error
  state.editState.autoIndentedLine = none(AutoIndentedLine)

proc noteOutsideChange*(state: EditorState) =
  ## End the record when something other than the keys moved the cursor or the
  ## text since the last key (a click, a server edit).
  let
    typing = state.editState.typing
    buffer = state.activeWindow.buffer
  if not typing.repeating and (
    state.cursor != typing.lastCursor or
    (not buffer.isNil and buffer.contentVersion != typing.lastVersion)
  ):
    state.noteMove()

proc noteKey*(
    state: EditorState,
    buffer: TextBuffer,
    key: KeyCombo,
    typedBefore: openArray[TypedInput],
    keyConsumed, moves: bool,
    cursorBefore: BufferPosition,
    versionBefore: int,
) =
  ## Record what a key did: what it typed, the key itself when it changed the
  ## text, or the end of the record when it only moved the cursor.
  if state.editState.typing.repeating:
    return
  if typedBefore.len > 0:
    state.noteTyped(typedBefore)
    if not keyConsumed:
      state.noteTyped([TypedInput(kind: tiKey, key: key)])
  elif buffer.contentVersion != versionBefore:
    state.noteTyped([TypedInput(kind: tiKey, key: key)])
  elif moves or state.cursor != cursorBefore:
    state.noteMove()

proc noteTypedText*(state: EditorState, text: string) =
  state.noteTyped([TypedInput(kind: tiText, text: text, cursorAt: text.charLen)])
  state.settleTyping()
