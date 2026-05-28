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

import buffer
import picker/nav

type
  BookmarkEntry* = object ## Represents a bookmark entry in the bookmark manager list
    bufferIndex*: int # Index in the buffer list
    filePath*: string # File path ("No Name" if none)
    line*: int # Line number (0-based)
    text*: string # Line text preview (truncated to 50 chars)

  BookmarkManagerState* = ref object ## State for the bookmark manager UI
    entries*: seq[BookmarkEntry] # List of bookmark entries
    selectedIndex*: int # Currently selected entry index
    topLine*: int # Scroll position (first visible line)
    previousWindowIndex*: int # Window index to return to when closing
    waitingForG*: bool # Waiting for second 'g' for 'gg' command

proc newBookmarkManagerState*(): BookmarkManagerState =
  BookmarkManagerState(
    entries: @[], selectedIndex: 0, topLine: 0, previousWindowIndex: 0
  )

proc updateEntries*(state: BookmarkManagerState, buffers: seq[TextBuffer]) =
  ## Update the bookmark manager entries by scanning all buffers for bookmarks
  state.entries = @[]
  for i, buf in buffers:
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
      state.entries.add(
        BookmarkEntry(bufferIndex: i, filePath: filePath, line: bline, text: text)
      )

  # Clamp selectedIndex to valid range
  if state.entries.len == 0:
    state.selectedIndex = 0
  elif state.selectedIndex >= state.entries.len:
    state.selectedIndex = max(0, state.entries.len - 1)

proc moveUp*(state: BookmarkManagerState) =
  ## Move selection up
  pickerMoveUp(state.selectedIndex)
  if state.selectedIndex < state.topLine:
    state.topLine = state.selectedIndex

proc moveDown*(state: BookmarkManagerState) =
  ## Move selection down
  pickerMoveDown(state.selectedIndex, state.entries.len)

proc getSelectedItem*(state: BookmarkManagerState): Option[BookmarkEntry] =
  ## Get the currently selected bookmark entry
  if state.selectedIndex >= 0 and state.selectedIndex < state.entries.len:
    some(state.entries[state.selectedIndex])
  else:
    none(BookmarkEntry)

proc formatLine*(entry: BookmarkEntry): string =
  ## Format a bookmark entry for display
  let lineNum = $(entry.line + 1)
  result = "  " & entry.filePath & ":" & lineNum & "  " & entry.text

proc createBookmarkManagerTextBuffer*(state: BookmarkManagerState): TextBuffer =
  ## Create a TextBuffer from bookmark manager entries for rendering
  var content = "-- Bookmark Manager --"
  if state.entries.len == 0:
    content.add("\n  No bookmarks")
  else:
    for entry in state.entries:
      content.add('\n')
      content.add(formatLine(entry))
  result = newTextBuffer(content)
  result.readOnly = true

proc deleteSelectedBookmark*(state: BookmarkManagerState, buffers: seq[TextBuffer]) =
  ## Delete the currently selected bookmark and refresh entries
  let entry = state.getSelectedItem()
  if entry.isSome:
    let e = entry.get
    if e.bufferIndex >= 0 and e.bufferIndex < buffers.len:
      buffers[e.bufferIndex].toggleBookmark(e.line)
    state.updateEntries(buffers)
