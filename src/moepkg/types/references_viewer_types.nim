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

## Lightweight type definitions for the references viewer.
##
## Split out from `references_viewer` so modules that only need its State type
## (notably `types` and its importers) do not transitively pull in `picker/nav`
## via the full `references_viewer` module.

import list_viewer_types
export list_viewer_types

type
  ReferenceItem* = object
    path*: string # File path
    line*: int # Line number (0-indexed)
    column*: int # Column number (0-indexed)
    text*: string # Optional context text

  ReferencesViewerState* = ref object of ListViewer[ReferenceItem]
    ## items/selectedIndex/waitingForG/title are inherited.
    # When true, jumping to a selected item opens a new vertical split window
    # instead of reusing the current one (goto features' openWindow option).
    openWindowOnJump*: bool
