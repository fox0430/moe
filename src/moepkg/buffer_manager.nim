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

## Buffer Manager module
## Provides a UI for viewing and switching between open buffers

import std/options

import buffer/core, list_viewer
import types/buffer_manager_types

export buffer_manager_types
export list_viewer

proc newBufferManagerState*(): BufferManagerState =
  BufferManagerState(items: @[], selectedIndex: 0)

proc initBufferManagerEntries*(bufferInfos: seq[BufferInfo]): seq[BufferEntry] =
  ## Create buffer entries from buffer information
  result = @[]
  for i, info in bufferInfos:
    let name = if info.filePath.isSome: info.filePath.get else: "No Name"
    result.add(
      BufferEntry(
        index: i, name: name, modified: info.isModified, active: info.isActive
      )
    )

  # If no buffers, add a placeholder
  if result.len == 0:
    result.add(BufferEntry(index: 0, name: "No Name", modified: false, active: true))

proc updateEntries*(state: BufferManagerState, bufferInfos: seq[BufferInfo]) =
  ## Update the buffer manager entries from buffer information
  state.items = initBufferManagerEntries(bufferInfos)
  # Clamp selectedIndex to valid range
  if state.selectedIndex >= state.items.len:
    state.selectedIndex = max(0, state.items.len - 1)

proc formatLine*(entry: BufferEntry): string =
  ## Format a buffer entry for display
  let
    modifiedMark = if entry.modified: "[+] " else: "    "
    activeMark = if entry.active: "* " else: "  "
    indexStr = $entry.index & ": "
  result = activeMark & indexStr & modifiedMark & entry.name

proc createBufferManagerTextBuffer*(state: BufferManagerState): TextBuffer =
  ## Create a TextBuffer from buffer manager entries for rendering via the normal view path
  state.toListTextBuffer("-- Buffer Manager --", formatLine)
