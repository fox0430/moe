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

type
  ReferenceItem* = object
    path*: string # File path
    line*: int # Line number (0-indexed)
    column*: int # Column number (0-indexed)
    text*: string # Optional context text

  ReferencesViewerState* = ref object
    items*: seq[ReferenceItem] # Reference items to display
    selectedIndex*: int # Currently selected item index
    topLine*: int # Scroll position (first visible line)
    title*: string # Title for the list (e.g., "References", "Definitions")
    originalBuffer*: TextBuffer # Saved original buffer (restored on exit)

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
  if state.selectedIndex > 0:
    state.selectedIndex.dec

proc moveDown*(state: ReferencesViewerState) =
  ## Move selection down
  if state.selectedIndex < state.items.high:
    state.selectedIndex.inc

proc moveToFirst*(state: ReferencesViewerState) =
  ## Move to first item
  state.selectedIndex = 0

proc moveToLast*(state: ReferencesViewerState) =
  ## Move to last item
  if state.items.len > 0:
    state.selectedIndex = state.items.high
  else:
    state.selectedIndex = 0

proc halfPageUp*(state: ReferencesViewerState, viewportHeight: int) =
  ## Move up by half a page
  let halfPage = viewportHeight div 2
  state.selectedIndex = max(0, state.selectedIndex - halfPage)

proc halfPageDown*(state: ReferencesViewerState, viewportHeight: int) =
  ## Move down by half a page
  let halfPage = viewportHeight div 2
  if state.items.len > 0:
    state.selectedIndex = min(state.items.high, state.selectedIndex + halfPage)

proc ensureSelectedVisible*(state: ReferencesViewerState, viewportHeight: int) =
  ## Ensure the selected item is visible in the viewport
  # Adjust topLine to keep selected item visible
  if state.selectedIndex < state.topLine:
    state.topLine = state.selectedIndex
  elif state.selectedIndex >= state.topLine + viewportHeight:
    state.topLine = state.selectedIndex - viewportHeight + 1

  # Ensure topLine is not negative
  if state.topLine < 0:
    state.topLine = 0

proc createReferencesTextBuffer*(state: ReferencesViewerState): TextBuffer =
  ## Create a TextBuffer from references for rendering via the normal view path
  var content = "-- " & state.title.toUpperAscii() & " (" & $state.itemCount() & ") --"
  for i in 0 ..< state.itemCount:
    content.add('\n')
    content.add(state.getLine(i))
  result = newTextBuffer(content)
  result.readOnly = true
