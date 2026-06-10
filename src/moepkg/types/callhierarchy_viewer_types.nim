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

## Lightweight type definitions for the call hierarchy viewer.
##
## Split out from `callhierarchy_viewer` so modules that only need its State
## type (notably `types` and its importers) do not transitively pull in
## `picker/nav` via the full `callhierarchy_viewer` module. `lsp/protocol/types`
## is still required for `CallHierarchyItem`.

import ../lsp/protocol/types as lspTypes
import ../primitives

type
  CallHierarchyViewKind* = enum
    chvkPrepare ## Initial prepare result
    chvkIncoming ## Incoming calls view
    chvkOutgoing ## Outgoing calls view

  CallHierarchyViewerState* = ref object
    items*: seq[lspTypes.CallHierarchyItem] ## Call hierarchy items to display
    selectedIndex*: int ## Currently selected item index
    topLine*: int ## Scroll position (first visible line)
    viewKind*: CallHierarchyViewKind ## Type of view (prepare/incoming/outgoing)
    title*: string ## Title for the list
    waitingForG*: bool ## Waiting for second 'g' for 'gg' command
    ## Cursor/viewport of the underlying buffer captured on entry, so quitting
    ## the viewer restores the position instead of leaving it at (0, 0).
    originCursor*: BufferPosition
    originTopLine*: int
    originLeftColumn*: int
