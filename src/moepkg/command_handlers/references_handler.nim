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

  # Handle 'gg' command (two g presses)
  if refState.waitingForG:
    refState.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      refState.moveToFirst()
      return ReferencesResult(kind: rvrHandled)
    # If not 'g', fall through to normal handling

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skUp:
      refState.moveUp()
      refState.ensureSelectedVisible(viewportHeight)
      return ReferencesResult(kind: rvrHandled)
    of skDown:
      refState.moveDown()
      refState.ensureSelectedVisible(viewportHeight)
      return ReferencesResult(kind: rvrHandled)
    of skEnter:
      # Jump to selected reference
      let item = refState.getSelectedItem()
      if item.isSome:
        return ReferencesResult(kind: rvrJumpToReference, targetItem: item.get)
      else:
        return ReferencesResult(kind: rvrError, errorMessage: "No reference selected")
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      refState.halfPageDown(viewportHeight)
      return ReferencesResult(kind: rvrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      refState.halfPageUp(viewportHeight)
      return ReferencesResult(kind: rvrHandled)

    case keyCombo.char
    of ":":
      return ReferencesResult(kind: rvrEnterCommand)
    of "j":
      refState.moveDown()
      refState.ensureSelectedVisible(viewportHeight)
      return ReferencesResult(kind: rvrHandled)
    of "k":
      refState.moveUp()
      refState.ensureSelectedVisible(viewportHeight)
      return ReferencesResult(kind: rvrHandled)
    of "g":
      # Start waiting for second 'g'
      refState.waitingForG = true
      return ReferencesResult(kind: rvrHandled)
    of "G":
      refState.moveToLast()
      refState.ensureSelectedVisible(viewportHeight)
      return ReferencesResult(kind: rvrHandled)
    else:
      discard

  return ReferencesResult(kind: rvrUnhandled)
