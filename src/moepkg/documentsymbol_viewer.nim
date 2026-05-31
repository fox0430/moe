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

import lsp/protocol/[types, enums]
import buffer
import picker/nav

import documentsymbol_viewer_types
export documentsymbol_viewer_types

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

  DocumentSymbolViewerState(
    items: items, selectedIndex: 0, topLine: 0, filePath: filePath
  )

proc itemCount*(state: DocumentSymbolViewerState): int =
  ## Get the number of items
  state.items.len

proc getItem*(state: DocumentSymbolViewerState, index: int): Option[SymbolItem] =
  ## Get a specific item
  if index >= 0 and index < state.items.len:
    some(state.items[index])
  else:
    none(SymbolItem)

proc getSelectedItem*(state: DocumentSymbolViewerState): Option[SymbolItem] =
  ## Get the currently selected item
  state.getItem(state.selectedIndex)

proc formatLine*(item: SymbolItem): string =
  ## Format a symbol item as a display line
  let indent = "  ".repeat(item.depth)
  let icon = symbolKindToIcon(item.kind)
  let lineNum = $(item.line + 1)
  if item.detail.len > 0:
    fmt"{indent}[{icon}] {item.name} ({item.detail}) :{lineNum}"
  else:
    fmt"{indent}[{icon}] {item.name} :{lineNum}"

proc getLine*(state: DocumentSymbolViewerState, index: int): string =
  ## Get a formatted line for display
  if index >= 0 and index < state.items.len:
    state.items[index].formatLine()
  else:
    ""

proc moveUp*(state: DocumentSymbolViewerState) =
  ## Move selection up
  pickerMoveUp(state.selectedIndex)

proc moveDown*(state: DocumentSymbolViewerState) =
  ## Move selection down
  pickerMoveDown(state.selectedIndex, state.items.len)

proc moveToFirst*(state: DocumentSymbolViewerState) =
  ## Move to first item
  pickerMoveToFirst(state.selectedIndex)

proc moveToLast*(state: DocumentSymbolViewerState) =
  ## Move to last item
  pickerMoveToLast(state.selectedIndex, state.items.len)

proc halfPageUp*(state: DocumentSymbolViewerState, viewportHeight: int) =
  ## Move up by half a page
  pickerHalfPageUp(state.selectedIndex, viewportHeight)

proc halfPageDown*(state: DocumentSymbolViewerState, viewportHeight: int) =
  ## Move down by half a page
  pickerHalfPageDown(state.selectedIndex, state.items.len, viewportHeight)

proc ensureSelectedVisible*(state: DocumentSymbolViewerState, viewportHeight: int) =
  ## Ensure the selected item is visible in the viewport
  pickerEnsureVisible(state.selectedIndex, state.topLine, viewportHeight)

proc createDocumentSymbolTextBuffer*(state: DocumentSymbolViewerState): TextBuffer =
  ## Create a TextBuffer from document symbols for rendering via the normal view path
  var content = "-- SYMBOLS (" & $state.itemCount() & ") --"
  for i in 0 ..< state.itemCount:
    content.add('\n')
    content.add(state.getLine(i))
  result = newTextBuffer(content)
  result.readOnly = true
