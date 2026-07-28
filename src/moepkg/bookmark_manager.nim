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

import std/[options, unicode]

import buffer/core, list_viewer
import types/bookmark_manager_types

export bookmark_manager_types
export list_viewer

proc newBookmarkManagerState*(): BookmarkManagerState =
  BookmarkManagerState(items: @[], selectedIndex: 0)

proc updateEntries*(state: BookmarkManagerState, buffers: seq[TextBuffer]) =
  ## Update the bookmark manager entries by scanning all buffers for bookmarks
  state.items = @[]
  for buf in buffers:
    let filePath = if buf.filePath.isSome: buf.filePath.get else: "No Name"
    for bline in buf.bookmarks:
      let text =
        if bline < buf.len:
          let line = buf.getLine(bline)
          if line.runeLen > 50:
            line.runeSubStr(0, 50) & "..."
          else:
            line
        else:
          ""
      state.items.add(
        BookmarkEntry(bufferId: buf.id, filePath: filePath, line: bline, text: text)
      )

  # Clamp selectedIndex to valid range
  if state.items.len == 0:
    state.selectedIndex = 0
  elif state.selectedIndex >= state.items.len:
    state.selectedIndex = max(0, state.items.len - 1)

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
  ## Delete the currently selected bookmark and refresh entries.
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
    state.updateEntries(buffers)
