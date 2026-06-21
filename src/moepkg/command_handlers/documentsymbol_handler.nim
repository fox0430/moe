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

proc handleDocumentSymbolModeKey*(
    symState: DocumentSymbolViewerState, viewportHeight: int, keyCombo: KeyCombo
): DocumentSymbolResult =
  ## Handle a key press in Document Symbol Viewer mode
  ##
  ## Returns a DocumentSymbolResult indicating what action should be taken

  case symState.handleListNavKey(viewportHeight, keyCombo)
  of lvaConsumed:
    DocumentSymbolResult(kind: dsvrHandled)
  of lvaQuitKey, lvaEscape:
    DocumentSymbolResult(kind: dsvrQuit)
  of lvaEnterCommand:
    DocumentSymbolResult(kind: dsvrEnterCommand)
  of lvaSelect:
    # Jump to selected symbol
    let item = symState.getSelectedItem()
    if item.isSome:
      DocumentSymbolResult(kind: dsvrJumpToSymbol, targetItem: item.get)
    else:
      DocumentSymbolResult(kind: dsvrError, errorMessage: "No symbol selected")
  of lvaUnhandled:
    DocumentSymbolResult(kind: dsvrUnhandled)
