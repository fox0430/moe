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

## The Buffer Manager and Bookmark Manager list what the buffers hold, so their
## rows are kept derived from the buffers.

import types/editor_types, editor_window, buffer_manager, bookmark_manager, buffer

export buffer_manager.BufferInfo

proc getBufferInfos*(e: Editor, activeTabId: BufferId): seq[BufferInfo] =
  ## Extract buffer information from the buffer list for BufferManager.
  ## Active means the given tab, not what an overlay viewer shows.
  for buf in e.buffers:
    result.add(buf.toBufferInfo(buf.id == activeTabId))

proc showListing(win: EditorWindow, view: TextBuffer, selectedIndex: int) =
  win.setView(view)
  # Below the header. The list may have shrunk under the old cursor.
  win.cursor = BufferPosition(line: selectedIndex + 1, column: 0)

proc syncBufferListings*(e: Editor) =
  ## Bring every listing up to the buffers, however they changed. Rows that still
  ## match keep their view, and the scroll with it. Runs after each result, so
  ## the next key of a mapping sees the new rows, and each frame.
  var rebind = false
  for win in e.windowManager.windows:
    case win.modeState.kind
    of mskBufferManager:
      let state = win.modeState.bufferManager
      let entries = initBufferManagerEntries(e.getBufferInfos(e.tabBuffer(win).id))
      if entries == state.items:
        continue
      state.setEntries(entries)
      win.showListing(state.createBufferManagerTextBuffer(), state.selectedIndex)
    of mskBookmarkManager:
      let state = win.modeState.bookmarkManager
      let entries = bookmarkEntries(e.buffers)
      if entries == state.items:
        continue
      state.setEntries(entries)
      win.showListing(state.createBookmarkManagerTextBuffer(), state.selectedIndex)
    else:
      continue
    rebind = rebind or win == e.activeWindow
  if rebind:
    e.syncActiveWindow()
