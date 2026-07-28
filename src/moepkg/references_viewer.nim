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

## References viewer state management
##
## This module provides the data structures and operations for the references viewer mode.
## Used to display and navigate LSP references, definitions, call hierarchy results.
##
## Selection/scroll navigation comes from the generic `ListViewer` base; only
## the reference-specific construction and formatting live here.

import std/[strformat, strutils]

import buffer/core, list_viewer
import types/references_viewer_types

export references_viewer_types
export list_viewer

proc newReferencesViewerState*(
    items: seq[ReferenceItem], title: string = "References"
): ReferencesViewerState =
  ## Create a new references viewer state
  ReferencesViewerState(items: items, selectedIndex: 0, title: title)

proc formatLine*(item: ReferenceItem): string =
  ## Format a reference item as a display line
  fmt"{item.path} {item.line + 1} Line {item.column + 1} Col"

proc createReferencesTextBuffer*(state: ReferencesViewerState): TextBuffer =
  ## Create a TextBuffer from references for rendering via the normal view path
  let header = "-- " & state.title.toUpperAscii() & " (" & $state.itemCount() & ") --"
  state.toListTextBuffer(header, formatLine)
