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

## Lightweight type definitions for the bookmark manager.
##
## Split out from `bookmark_manager` so modules that only need its State type
## (notably `types` and its importers) do not transitively pull in `picker/nav`
## via the full `bookmark_manager` module.

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
