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

## Lightweight type definitions for the buffer manager.
##
## Split out from `buffer_manager` so modules that only need its State type
## (notably `types` and its importers) do not transitively pull in `picker/nav`
## via the full `buffer_manager` module.

import std/options

import list_viewer_types
export list_viewer_types

type
  BufferEntry* = object ## Represents a buffer entry in the buffer manager list
    number*: int
      ## Stable buffer number (`BufferId`), what `:b N` takes and what the
      ## manager's own select/delete act on. Deliberately not a list
      ## position: the list is rebuilt after every deletion.
    name*: string # Raw buffer name; the display boundary sanitizes it
    modified*: bool # Whether buffer has unsaved changes
    active*: bool # Whether this is the currently active buffer

  BufferManagerState* = ref object of ListViewer[BufferEntry]
    ## State for the buffer manager UI.
    ## items (buffer entries)/selectedIndex/waitingForG are inherited.

  BufferInfo* = object ## Information about a buffer for initializing buffer manager
    number*: int ## Stable buffer number (BufferId)
    filePath*: Option[string]
    displayName*: Option[string] = none(string)
      ## Tab label override (e.g. Terminal sessions). Shown instead of filePath.
    isModified*: bool
    isActive*: bool
