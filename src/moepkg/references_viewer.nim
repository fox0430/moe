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

import std/[strformat, strutils, options]

import buffer
import picker/nav

import references_viewer_types
export references_viewer_types

proc newReferencesViewerState*(
    items: seq[ReferenceItem], title: string = "References"
): ReferencesViewerState =
  ## Create a new references viewer state
  ReferencesViewerState(items: items, selectedIndex: 0, topLine: 0, title: title)

proc itemCount*(state: ReferencesViewerState): int =
  ## Get the number of items
  state.items.len

proc getItem*(state: ReferencesViewerState, index: int): Option[ReferenceItem] =
  ## Get a specific item
  if index >= 0 and index < state.items.len:
    some(state.items[index])
  else:
    none(ReferenceItem)

proc getSelectedItem*(state: ReferencesViewerState): Option[ReferenceItem] =
  ## Get the currently selected item
  state.getItem(state.selectedIndex)

proc formatLine*(item: ReferenceItem): string =
  ## Format a reference item as a display line
  fmt"{item.path} {item.line + 1} Line {item.column + 1} Col"

proc getLine*(state: ReferencesViewerState, index: int): string =
  ## Get a formatted line for display
  if index >= 0 and index < state.items.len:
    state.items[index].formatLine()
  else:
    ""

proc moveUp*(state: ReferencesViewerState) =
  ## Move selection up
  pickerMoveUp(state.selectedIndex)

proc moveDown*(state: ReferencesViewerState) =
  ## Move selection down
  pickerMoveDown(state.selectedIndex, state.items.len)

proc moveToFirst*(state: ReferencesViewerState) =
  ## Move to first item
  pickerMoveToFirst(state.selectedIndex)

proc moveToLast*(state: ReferencesViewerState) =
  ## Move to last item
  pickerMoveToLast(state.selectedIndex, state.items.len)

proc halfPageUp*(state: ReferencesViewerState, viewportHeight: int) =
  ## Move up by half a page
  pickerHalfPageUp(state.selectedIndex, viewportHeight)

proc halfPageDown*(state: ReferencesViewerState, viewportHeight: int) =
  ## Move down by half a page
  pickerHalfPageDown(state.selectedIndex, state.items.len, viewportHeight)

proc ensureSelectedVisible*(state: ReferencesViewerState, viewportHeight: int) =
  ## Ensure the selected item is visible in the viewport
  pickerEnsureVisible(state.selectedIndex, state.topLine, viewportHeight)

proc createReferencesTextBuffer*(state: ReferencesViewerState): TextBuffer =
  ## Create a TextBuffer from references for rendering via the normal view path
  var content = "-- " & state.title.toUpperAscii() & " (" & $state.itemCount() & ") --"
  for i in 0 ..< state.itemCount:
    content.add('\n')
    content.add(state.getLine(i))
  result = newTextBuffer(content)
  result.readOnly = true
