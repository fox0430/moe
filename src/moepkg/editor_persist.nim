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

## Per-file state restored when a file opens and saved when the editor exits.

import std/[options, sequtils]

import pkg/results

import types/editor_types, path_key, persist, logger, editor_notify

proc reportUnreadable[T](
    e: Editor, records: var PersistedRecords[T], what, error: string
) =
  ## Tell the user once that `what` will not be saved, since saving never
  ## replaces a file it cannot read.
  if records.unreadableReported:
    return
  records.unreadableReported = true
  logError("persist", error)
  e.notify(
    "Cannot read " & what & ", not saved until fixed or removed: " & error, nlError
  )

proc savedCursorPosition*(e: Editor, key: string): Option[CursorPositionEntry] =
  ## The cursor position recorded for the file at `key`.
  let saved = e.persistedCursorPositions.lookupCursorPosition(key)
  if saved.isErr:
    e.reportUnreadable(e.persistedCursorPositions, "cursor positions", saved.error)
    return none(CursorPositionEntry)
  saved.get

proc restoreBookmarks*(e: Editor, buffer: TextBuffer) =
  ## Give a freshly read `buffer` the bookmarks recorded for its file, minus
  ## lines past its end.
  if not e.config.persist.bookmarks or buffer.filePath.isNone:
    return
  let key = pathKey(buffer.filePath.get)
  let saved = e.persistedBookmarks.lookupBookmarks(key)
  if saved.isErr:
    e.reportUnreadable(e.persistedBookmarks, "bookmarks", saved.error)
  elif saved.get.isSome:
    buffer.bookmarks = saved.get.get.filterIt(it < buffer.len)
  e.persistedBookmarks.markRestored(key, buffer.bookmarks)

proc rememberBookmarks*(e: Editor, buffer: TextBuffer) =
  ## Record `buffer`'s bookmarks for the next save if they differ from what its
  ## file was opened with, so an untouched file never overwrites another
  ## session's newer entry. An empty list removes the entry.
  if not e.config.persist.bookmarks or buffer.filePath.isNone:
    return
  e.persistedBookmarks.record(pathKey(buffer.filePath.get), buffer.bookmarks)
