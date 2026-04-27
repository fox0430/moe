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

## Document Symbol viewer mode command handler
##
## This module handles commands specific to Document Symbol Viewer mode.
## The document symbol viewer displays symbols (functions, classes, etc.) in the current file.

import std/options

import ../[types, key_bindings, documentsymbol_viewer]
import handler_types
export handler_types

type
  DocumentSymbolResultKind* = enum
    dsvrHandled # Command was handled successfully
    dsvrEnterCommand # Enter command mode
    dsvrQuit # Close document symbol viewer and return to previous mode
    dsvrJumpToSymbol # Jump to the selected symbol
    dsvrUnhandled # Command was not handled
    dsvrError # Error occurred

  DocumentSymbolResult* = object
    case kind*: DocumentSymbolResultKind
    of dsvrJumpToSymbol:
      targetItem*: SymbolItem
    of dsvrError:
      errorMessage*: string
    else:
      discard

proc newDocumentSymbolHandler*(): DocumentSymbolHandler =
  ## Create a new Document Symbol Viewer mode handler
  DocumentSymbolHandler(waitingForG: false)

proc handleDocumentSymbolModeKey*(
    handler: DocumentSymbolHandler,
    symState: DocumentSymbolViewerState,
    viewportHeight: int,
    keyCombo: KeyCombo,
): DocumentSymbolResult =
  ## Handle a key press in Document Symbol Viewer mode
  ##
  ## Returns a DocumentSymbolResult indicating what action should be taken

  # Handle 'gg' command (two g presses)
  if handler.waitingForG:
    handler.waitingForG = false
    if not keyCombo.isSpecial and keyCombo.char == "g":
      symState.moveToFirst()
      return DocumentSymbolResult(kind: dsvrHandled)
    # If not 'g', fall through to normal handling

  # Escape or q to quit
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    return DocumentSymbolResult(kind: dsvrQuit)

  # Check for special keys first
  if keyCombo.isSpecial:
    case keyCombo.special
    of skUp:
      symState.moveUp()
      symState.ensureSelectedVisible(viewportHeight)
      return DocumentSymbolResult(kind: dsvrHandled)
    of skDown:
      symState.moveDown()
      symState.ensureSelectedVisible(viewportHeight)
      return DocumentSymbolResult(kind: dsvrHandled)
    of skEnter:
      # Jump to selected symbol
      let item = symState.getSelectedItem()
      if item.isSome:
        return DocumentSymbolResult(kind: dsvrJumpToSymbol, targetItem: item.get)
      else:
        return DocumentSymbolResult(kind: dsvrError, errorMessage: "No symbol selected")
    else:
      discard
  else:
    # Character keys
    # Check for Ctrl+d (half page down)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "d":
      symState.halfPageDown(viewportHeight)
      symState.ensureSelectedVisible(viewportHeight)
      return DocumentSymbolResult(kind: dsvrHandled)

    # Check for Ctrl+u (half page up)
    if kmCtrl in keyCombo.modifiers and keyCombo.char == "u":
      symState.halfPageUp(viewportHeight)
      symState.ensureSelectedVisible(viewportHeight)
      return DocumentSymbolResult(kind: dsvrHandled)

    case keyCombo.char
    of ":":
      return DocumentSymbolResult(kind: dsvrEnterCommand)
    of "q":
      return DocumentSymbolResult(kind: dsvrQuit)
    of "j":
      symState.moveDown()
      symState.ensureSelectedVisible(viewportHeight)
      return DocumentSymbolResult(kind: dsvrHandled)
    of "k":
      symState.moveUp()
      symState.ensureSelectedVisible(viewportHeight)
      return DocumentSymbolResult(kind: dsvrHandled)
    of "g":
      # Start waiting for second 'g'
      handler.waitingForG = true
      return DocumentSymbolResult(kind: dsvrHandled)
    of "G":
      symState.moveToLast()
      symState.ensureSelectedVisible(viewportHeight)
      return DocumentSymbolResult(kind: dsvrHandled)
    else:
      discard

  return DocumentSymbolResult(kind: dsvrUnhandled)
