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

import
  types/editor_types,
  path_key,
  persist,
  logger,
  editor_notify,
  editor_window_tab,
  syntax/tokenizer,
  search_utils

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

proc keepsCursorPosition*(language: SourceLanguage): bool =
  ## Temporary git files are not reopened to continue work.
  language notin {SourceLanguage.langGitRebaseTodo, SourceLanguage.langCommitEditMsg}

proc saveBufferCursorPosition*(e: Editor, buffer: TextBuffer) =
  ## Record where the cursor stands in `buffer` for the next save, if
  ## persist.cursorPosition is enabled and a window has shown it.
  if not e.config.persist.cursorPosition or buffer.filePath.isNone or
      not buffer.language.keepsCursorPosition:
    return
  let position = e.lastCursorIn(buffer)
  if position.isSome:
    e.persistedCursorPositions.record(
      pathKey(buffer.filePath.get),
      CursorPositionEntry(line: position.get.line, column: position.get.column),
    )

proc restoreCursorPosition*(e: Editor, buffer: TextBuffer) =
  ## Leave the position recorded for a freshly read `buffer` to the first window
  ## that shows it.
  if not e.config.persist.cursorPosition or buffer.filePath.isNone or
      not buffer.language.keepsCursorPosition:
    return
  let key = pathKey(buffer.filePath.get)
  let saved = e.savedCursorPosition(key)
  var position = BufferPosition(line: 0, column: 0)
  if saved.isSome:
    position =
      BufferPosition(line: saved.get.line, column: saved.get.column).keptInside(buffer)
    e.state.tabLines.add(
      TabLine(
        bufferId: buffer.id, line: position.line, column: position.column, saved: true
      )
    )
  e.persistedCursorPositions.markRestored(
    key, CursorPositionEntry(line: position.line, column: position.column)
  )

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

proc restoreLastSearch*(e: Editor) =
  ## Bring back the last search the previous session left, as Vim's viminfo
  ## brings `@/` back, so `n`, an empty `/` and an empty :s pattern replay it.
  ## Only the application calls this: tests must not read the user's cache.
  if not e.config.persist.search:
    return
  let saved = loadLastSearch()
  if saved.isSome:
    # As Vim's viminfo, a new session searches forward.
    e.state.input.search.last =
      SearchSpec(pattern: saved.get.pattern, match: saved.get.match, direction: Forward)
    # A restored pattern waits for the next search command: the first screen
    # stays clean, as after :noh, and `n`, an empty `/` and a :s show it again.
    e.state.hideSearchMatches()

proc rememberLastSearch*(e: Editor) =
  ## Keep this session's last search for the next one. Saving goes by
  ## 'persist.search', which the caller has checked.
  let last = e.state.input.search.last
  if last.pattern.len == 0:
    return
  let r = saveLastSearch(LastSearch(pattern: last.pattern, match: last.match))
  if r.isErr:
    logError("persist", "Failed to save the last search: " & r.error)
