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

import ../[types, keybindings, callhierarchy_viewer]
import ../lsp/protocol/types as lspTypes

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

  CallHierarchyHandler* = ref object
    ## Handler for Call Hierarchy Viewer mode specific commands
    waitingForG*: bool ## Waiting for second 'g' for 'gg' command

proc newCallHierarchyHandler*(): CallHierarchyHandler =
  ## Create a new Call Hierarchy Viewer mode handler
  CallHierarchyHandler(waitingForG: false)

proc handleCallHierarchyModeKey*(
    handler: CallHierarchyHandler,
    state: EditorState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): CallHierarchyResult =
  ## Handle a key press in Call Hierarchy Viewer mode
  ##
  ## Returns a CallHierarchyResult indicating what action should be taken

  if state.callHierarchyViewerState.isNone:
    return CallHierarchyResult(
      kind: chvrError, errorMessage: "Call hierarchy viewer state not initialized"
    )

  let chState = state.callHierarchyViewerState.get

  # Handle 'gg' command (two g presses)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      chState.moveToFirst()
      chState.ensureSelectedVisible(viewportHeight)
      return CallHierarchyResult(kind: chvrHandled)
    # If not 'g', fall through to normal handling

  # Escape or q to quit
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return CallHierarchyResult(kind: chvrQuit)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skUp:
      chState.moveUp()
      chState.ensureSelectedVisible(viewportHeight)
      return CallHierarchyResult(kind: chvrHandled)
    of skDown:
      chState.moveDown()
      chState.ensureSelectedVisible(viewportHeight)
      return CallHierarchyResult(kind: chvrHandled)
    of skEnter:
      # Jump to selected item
      let item = chState.getSelectedItem()
      if item.isSome:
        return CallHierarchyResult(kind: chvrJumpToItem, targetItem: item.get)
      else:
        return CallHierarchyResult(kind: chvrError, errorMessage: "No item selected")
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      chState.halfPageDown(viewportHeight)
      chState.ensureSelectedVisible(viewportHeight)
      return CallHierarchyResult(kind: chvrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      chState.halfPageUp(viewportHeight)
      chState.ensureSelectedVisible(viewportHeight)
      return CallHierarchyResult(kind: chvrHandled)

    case keyCombo.char
    of ":":
      return CallHierarchyResult(kind: chvrEnterCommand)
    of "q":
      return CallHierarchyResult(kind: chvrQuit)
    of "j":
      chState.moveDown()
      chState.ensureSelectedVisible(viewportHeight)
      return CallHierarchyResult(kind: chvrHandled)
    of "k":
      chState.moveUp()
      chState.ensureSelectedVisible(viewportHeight)
      return CallHierarchyResult(kind: chvrHandled)
    of "g":
      # Start waiting for second 'g'
      handler.waitingForG = true
      return CallHierarchyResult(kind: chvrHandled)
    of "G":
      chState.moveToLast()
      chState.ensureSelectedVisible(viewportHeight)
      return CallHierarchyResult(kind: chvrHandled)
    of "i":
      # Request incoming calls for selected item
      let item = chState.getSelectedItem()
      if item.isSome:
        return CallHierarchyResult(kind: chvrRequestIncoming, targetItem: item.get)
      else:
        return CallHierarchyResult(kind: chvrError, errorMessage: "No item selected")
    of "o":
      # Request outgoing calls for selected item
      let item = chState.getSelectedItem()
      if item.isSome:
        return CallHierarchyResult(kind: chvrRequestOutgoing, targetItem: item.get)
      else:
        return CallHierarchyResult(kind: chvrError, errorMessage: "No item selected")
    else:
      discard

  return CallHierarchyResult(kind: chvrUnhandled)
