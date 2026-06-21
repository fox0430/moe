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

## Call Hierarchy viewer mode command handler
##
## This module handles commands specific to Call Hierarchy Viewer mode.
## The viewer displays LSP call hierarchy results (incoming/outgoing calls).

import std/options

import ../[types, key_bindings, callhierarchy_viewer]
import ../lsp/protocol/types as lspTypes
import handler_types
export handler_types

type
  CallHierarchyResultKind* = enum
    chvrHandled ## Command was handled successfully
    chvrEnterCommand ## Enter command mode
    chvrQuit ## Close call hierarchy viewer and return to previous mode
    chvrJumpToItem ## Jump to the selected item
    chvrRequestIncoming ## Request incoming calls for selected item
    chvrRequestOutgoing ## Request outgoing calls for selected item
    chvrUnhandled ## Command was not handled
    chvrError ## Error occurred

  CallHierarchyResult* = object
    case kind*: CallHierarchyResultKind
    of chvrJumpToItem, chvrRequestIncoming, chvrRequestOutgoing:
      targetItem*: lspTypes.CallHierarchyItem
    of chvrError:
      errorMessage*: string
    else:
      discard

proc handleCallHierarchyModeKey*(
    chState: CallHierarchyViewerState, viewportHeight: int, keyCombo: KeyCombo
): CallHierarchyResult =
  ## Handle a key press in Call Hierarchy Viewer mode
  ##
  ## Returns a CallHierarchyResult indicating what action should be taken

  case chState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    return CallHierarchyResult(kind: chvrHandled)
  of lvaQuitKey, lvaEscape:
    return CallHierarchyResult(kind: chvrQuit)
  of lvaEnterCommand:
    return CallHierarchyResult(kind: chvrEnterCommand)
  of lvaSelect:
    # Jump to selected item
    let item = chState.getSelectedItem()
    if item.isSome:
      return CallHierarchyResult(kind: chvrJumpToItem, targetItem: item.get)
    else:
      return CallHierarchyResult(kind: chvrError, errorMessage: "No item selected")
  of lvaUnhandled:
    discard # fall through to call-hierarchy-specific keys

  # Call-hierarchy-specific keys: request incoming/outgoing calls for the item.
  if not keyCombo.isSpecial:
    case keyCombo.char
    of "i":
      let item = chState.getSelectedItem()
      if item.isSome:
        return CallHierarchyResult(kind: chvrRequestIncoming, targetItem: item.get)
      else:
        return CallHierarchyResult(kind: chvrError, errorMessage: "No item selected")
    of "o":
      let item = chState.getSelectedItem()
      if item.isSome:
        return CallHierarchyResult(kind: chvrRequestOutgoing, targetItem: item.get)
      else:
        return CallHierarchyResult(kind: chvrError, errorMessage: "No item selected")
    else:
      discard

  return CallHierarchyResult(kind: chvrUnhandled)
