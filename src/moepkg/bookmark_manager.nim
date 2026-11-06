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

## Bookmark Manager module
## Provides a UI for viewing and managing bookmarks across all open buffers

import std/options

import buffer/core, list_viewer, unicode_utils
import types/bookmark_manager_types

export bookmark_manager_types
export list_viewer

proc newBookmarkManagerState*(): BookmarkManagerState =
  BookmarkManagerState(items: @[], selectedIndex: 0)

proc bookmarkEntries*(buffers: seq[TextBuffer]): seq[BookmarkEntry] =
  ## One entry for each bookmark in `buffers`.
  for buf in buffers:
    let filePath = if buf.filePath.isSome: buf.filePath.get else: "No Name"
    for bline in buf.bookmarks:
      let text =
        if bline < buf.len:
          buf.getLine(bline).truncateToCharsWithSuffix(50)
        else:
          ""
      result.add(
        BookmarkEntry(bufferId: buf.id, filePath: filePath, line: bline, text: text)
      )

proc setEntries*(state: BookmarkManagerState, entries: seq[BookmarkEntry]) =
  ## Replace the entries. The selection stays on its bookmark, found as the nth
  ## of its buffer since edits move lines; if that is gone, on its row.
  let selected = state.getSelectedItem
  var nth = 0
  if selected.isSome:
    for item in state.items[0 ..< state.selectedIndex]:
      if item.bufferId == selected.get.bufferId:
        inc nth
  state.items = entries
  state.keepSelection(
    selected,
    proc(a, b: BookmarkEntry): bool =
      if a.bufferId != b.bufferId:
        return false
      dec nth
      nth < 0,
  )

proc updateEntries*(state: BookmarkManagerState, buffers: seq[TextBuffer]) =
  ## Update the entries by scanning all buffers for bookmarks.
  state.setEntries(bookmarkEntries(buffers))

proc formatLine*(entry: BookmarkEntry): string =
  ## Format a bookmark entry for display
  let lineNum = $(entry.line + 1)
  result = "  " & entry.filePath & ":" & lineNum & "  " & entry.text

proc createBookmarkManagerTextBuffer*(state: BookmarkManagerState): TextBuffer =
  ## Create a TextBuffer from bookmark manager entries for rendering
  state.toListTextBuffer(
    "-- Bookmark Manager --", formatLine, emptyPlaceholder = "  No bookmarks"
  )

proc deleteSelectedBookmark*(state: BookmarkManagerState, buffers: seq[TextBuffer]) =
  ## Delete the currently selected bookmark; the listing follows the buffers.
  ## Resolves the buffer by BufferId to survive re-indexing of `buffers`.
  let entry = state.getSelectedItem()
  if entry.isSome:
    let e = entry.get
    for buf in buffers:
      if buf.id == e.bufferId:
        # hasBookmark guard: a stale entry would otherwise re-add via toggle.
        if buf.hasBookmark(e.line):
          buf.toggleBookmark(e.line)
        break
