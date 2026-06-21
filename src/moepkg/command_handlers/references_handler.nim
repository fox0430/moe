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

## References viewer mode command handler
##
## This module handles commands specific to References Viewer mode.
## The references viewer displays LSP references, definitions, call hierarchy results.

import std/options

import ../[types, key_bindings, references_viewer]
import handler_types
export handler_types

type
  ReferencesResultKind* = enum
    rvrHandled # Command was handled successfully
    rvrEnterCommand # Enter command mode
    rvrJumpToReference # Jump to the selected reference
    rvrQuit # Close references viewer and return to previous mode
    rvrUnhandled # Command was not handled
    rvrError # Error occurred

  ReferencesResult* = object
    case kind*: ReferencesResultKind
    of rvrJumpToReference:
      targetItem*: ReferenceItem
    of rvrError:
      errorMessage*: string
    else:
      discard

proc handleReferencesModeKey*(
    refState: ReferencesViewerState, viewportHeight: int, keyCombo: KeyCombo
): ReferencesResult =
  ## Handle a key press in References Viewer mode
  ##
  ## Returns a ReferencesResult indicating what action should be taken

  case refState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    ReferencesResult(kind: rvrHandled)
  of lvaQuitKey, lvaEscape:
    ReferencesResult(kind: rvrQuit)
  of lvaEnterCommand:
    ReferencesResult(kind: rvrEnterCommand)
  of lvaSelect:
    # Jump to selected reference
    let item = refState.getSelectedItem()
    if item.isSome:
      ReferencesResult(kind: rvrJumpToReference, targetItem: item.get)
    else:
      ReferencesResult(kind: rvrError, errorMessage: "No reference selected")
  of lvaUnhandled:
    ReferencesResult(kind: rvrUnhandled)
