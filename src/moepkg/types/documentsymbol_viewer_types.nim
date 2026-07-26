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

## Lightweight type definitions for the document symbol viewer.
##
## Split out from `documentsymbol_viewer` so modules that only need its State
## type (notably `types` and its importers) do not transitively pull in
## `picker/nav` via the full `documentsymbol_viewer` module. `lsp/protocol/enums`
## is still required for `SymbolKind`.

import ../lsp/protocol/enums
import list_viewer_types
export list_viewer_types

type
  SymbolItem* = object
    name*: string # Symbol name
    kind*: SymbolKind # Symbol kind (function, class, etc.)
    line*: int # Line number (0-indexed)
    column*: int # Column number (0-indexed)
    detail*: string # Optional detail (e.g., signature)
    depth*: int # Nesting depth for indentation

  DocumentSymbolViewerState* = ref object of ListViewer[SymbolItem]
    ## items/selectedIndex/waitingForG/title are inherited.
    filePath*: string # File path for the symbols
