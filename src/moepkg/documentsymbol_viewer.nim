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

## Document Symbol viewer state management
##
## This module provides the data structures and operations for the document symbol viewer mode.
## Used to display and navigate LSP document symbols (functions, classes, variables, etc.)

import std/[strformat, strutils, options]

import buffer/core, list_viewer
import lsp/protocol/[types, enums]
import types/documentsymbol_viewer_types

export documentsymbol_viewer_types
export list_viewer

proc symbolKindToString*(kind: SymbolKind): string =
  ## Convert SymbolKind to a short display string
  case kind
  of skFile: "File"
  of skModule: "Mod"
  of skNamespace: "NS"
  of skPackage: "Pkg"
  of skClass: "Class"
  of skMethod: "Method"
  of skProperty: "Prop"
  of skField: "Field"
  of skConstructor: "Ctor"
  of skEnum: "Enum"
  of skInterface: "Iface"
  of skFunction: "Func"
  of skVariable: "Var"
  of skConstant: "Const"
  of skString: "Str"
  of skNumber: "Num"
  of skBoolean: "Bool"
  of skArray: "Array"
  of skObject: "Obj"
  of skKey: "Key"
  of skNull: "Null"
  of skEnumMember: "EnumM"
  of skStruct: "Struct"
  of skEvent: "Event"
  of skOperator: "Op"
  of skTypeParameter: "TypeP"

proc symbolKindToIcon*(kind: SymbolKind): string =
  ## Convert SymbolKind to an icon character
  case kind
  of skFunction, skMethod: "f"
  of skClass, skStruct: "c"
  of skInterface: "i"
  of skVariable, skField, skProperty: "v"
  of skConstant: "C"
  of skEnum, skEnumMember: "e"
  of skModule, skNamespace, skPackage: "m"
  of skConstructor: "+"
  else: "-"

proc flattenDocumentSymbols(
    symbols: seq[DocumentSymbol], depth: int = 0
): seq[SymbolItem] =
  ## Flatten hierarchical DocumentSymbol to a flat list with depth info
  for sym in symbols:
    var item = SymbolItem(
      name: sym.name,
      kind: sym.kind,
      line: sym.selectionRange.start.line,
      column: sym.selectionRange.start.character,
      detail: if sym.detail.isSome: sym.detail.get else: "",
      depth: depth,
    )
    result.add(item)

    # Recursively add children
    if sym.children.isSome:
      result.add(flattenDocumentSymbols(sym.children.get, depth + 1))

proc flattenSymbolInformations(infos: seq[SymbolInformation]): seq[SymbolItem] =
  ## Convert flat SymbolInformation to SymbolItem list
  for info in infos:
    result.add(
      SymbolItem(
        name: info.name,
        kind: info.kind,
        line: info.location.range.start.line,
        column: info.location.range.start.character,
        detail: if info.containerName.isSome: info.containerName.get else: "",
        depth: 0,
      )
    )

proc newDocumentSymbolViewerState*(
    symbolResult: DocumentSymbolResult, filePath: string
): DocumentSymbolViewerState =
  ## Create a new document symbol viewer state from LSP result
  let items =
    if symbolResult.isHierarchical:
      flattenDocumentSymbols(symbolResult.symbols)
    else:
      flattenSymbolInformations(symbolResult.symbolInfos)

  DocumentSymbolViewerState(items: items, selectedIndex: 0, filePath: filePath)

proc formatLine*(item: SymbolItem): string =
  ## Format a symbol item as a display line
  let indent = "  ".repeat(item.depth)
  let icon = symbolKindToIcon(item.kind)
  let lineNum = $(item.line + 1)
  if item.detail.len > 0:
    fmt"{indent}[{icon}] {item.name} ({item.detail}) :{lineNum}"
  else:
    fmt"{indent}[{icon}] {item.name} :{lineNum}"

proc createDocumentSymbolTextBuffer*(state: DocumentSymbolViewerState): TextBuffer =
  ## Create a TextBuffer from document symbols for rendering via the normal view path
  let header = "-- SYMBOLS (" & $state.itemCount() & ") --"
  state.toListTextBuffer(header, formatLine)
