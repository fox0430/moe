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

## Call Hierarchy viewer state management
##
## This module provides the data structures and operations for the call hierarchy viewer mode.
## Used to display and navigate LSP call hierarchy results (incoming/outgoing calls).

import std/[strformat, strutils, options]

import lsp/protocol/types as lspTypes
import buffer
import picker/nav

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
    originalBuffer*: TextBuffer ## Saved original buffer (restored on exit)

proc newCallHierarchyViewerState*(
    items: seq[lspTypes.CallHierarchyItem], viewKind: CallHierarchyViewKind
): CallHierarchyViewerState =
  ## Create a new call hierarchy viewer state
  let title =
    case viewKind
    of chvkPrepare: "Call Hierarchy"
    of chvkIncoming: "Incoming Calls"
    of chvkOutgoing: "Outgoing Calls"
  CallHierarchyViewerState(
    items: items, selectedIndex: 0, topLine: 0, viewKind: viewKind, title: title
  )

proc itemCount*(state: CallHierarchyViewerState): int =
  ## Get the number of items
  state.items.len

proc getItem*(
    state: CallHierarchyViewerState, index: int
): Option[lspTypes.CallHierarchyItem] =
  ## Get a specific item
  if index >= 0 and index < state.items.len:
    some(state.items[index])
  else:
    none(lspTypes.CallHierarchyItem)

proc getSelectedItem*(
    state: CallHierarchyViewerState
): Option[lspTypes.CallHierarchyItem] =
  ## Get the currently selected item
  state.getItem(state.selectedIndex)

proc uriToPath(uri: string): string =
  ## Convert file:// URI to path
  if uri.startsWith("file://"):
    return uri[7 ..^ 1]
  return uri

proc formatLine*(item: lspTypes.CallHierarchyItem): string =
  ## Format a call hierarchy item as a display line
  let path = uriToPath(item.uri)
  let detail =
    if item.detail.isSome:
      " " & item.detail.get
    else:
      ""
  let line = item.selectionRange.start.line + 1
  let col = item.selectionRange.start.character + 1
  fmt"{item.name}{detail} ({path}:{line}:{col})"

proc getLine*(state: CallHierarchyViewerState, index: int): string =
  ## Get a formatted line for display
  if index >= 0 and index < state.items.len:
    state.items[index].formatLine()
  else:
    ""

proc moveUp*(state: CallHierarchyViewerState) =
  ## Move selection up
  pickerMoveUp(state.selectedIndex)

proc moveDown*(state: CallHierarchyViewerState) =
  ## Move selection down
  pickerMoveDown(state.selectedIndex, state.items.len)

proc moveToFirst*(state: CallHierarchyViewerState) =
  ## Move to first item
  pickerMoveToFirst(state.selectedIndex)

proc moveToLast*(state: CallHierarchyViewerState) =
  ## Move to last item
  pickerMoveToLast(state.selectedIndex, state.items.len)

proc halfPageUp*(state: CallHierarchyViewerState, viewportHeight: int) =
  ## Move up by half a page
  pickerHalfPageUp(state.selectedIndex, viewportHeight)

proc halfPageDown*(state: CallHierarchyViewerState, viewportHeight: int) =
  ## Move down by half a page
  pickerHalfPageDown(state.selectedIndex, state.items.len, viewportHeight)

proc ensureSelectedVisible*(state: CallHierarchyViewerState, viewportHeight: int) =
  ## Ensure the selected item is visible in the viewport
  pickerEnsureVisible(state.selectedIndex, state.topLine, viewportHeight)

proc createCallHierarchyTextBuffer*(state: CallHierarchyViewerState): TextBuffer =
  ## Create a TextBuffer from call hierarchy items for rendering via the normal view path
  var content = "-- " & state.title & " (" & $state.itemCount() & ") --"
  for i in 0 ..< state.itemCount:
    content.add('\n')
    content.add(state.getLine(i))
  result = newTextBuffer(content)
  result.readOnly = true
