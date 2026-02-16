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

import std/[unittest, options]

import ../src/moepkg/lsp/protocol/types as lspTypes
import ../src/moepkg/documentsymbol_viewer

proc makeDocumentSymbol(
    name: string,
    kind: SymbolKind,
    line: int,
    col: int,
    detail: Option[string] = none(string),
    children: Option[seq[lspTypes.DocumentSymbol]] = none(seq[lspTypes.DocumentSymbol]),
): lspTypes.DocumentSymbol =
  ## Helper to create a DocumentSymbol for testing
  result.name = name
  result.kind = kind
  result.detail = detail
  result.range = lspTypes.Range(
    start: lspTypes.Position(line: line, character: col),
    `end`: lspTypes.Position(line: line + 5, character: col + name.len),
  )
  result.selectionRange = lspTypes.Range(
    start: lspTypes.Position(line: line, character: col),
    `end`: lspTypes.Position(line: line, character: col + name.len),
  )
  result.children = children

proc makeSymbolInformation(
    name: string,
    kind: SymbolKind,
    uri: string,
    line: int,
    col: int,
    containerName: Option[string] = none(string),
): lspTypes.SymbolInformation =
  ## Helper to create a SymbolInformation for testing
  result.name = name
  result.kind = kind
  result.location = lspTypes.Location(
    uri: uri,
    range: lspTypes.Range(
      start: lspTypes.Position(line: line, character: col),
      `end`: lspTypes.Position(line: line, character: col + name.len),
    ),
  )
  result.containerName = containerName

suite "DocumentSymbolViewer - symbolKindToString":
  test "Function kind":
    check symbolKindToString(skFunction) == "Func"

  test "Class kind":
    check symbolKindToString(skClass) == "Class"

  test "Method kind":
    check symbolKindToString(skMethod) == "Method"

  test "Variable kind":
    check symbolKindToString(skVariable) == "Var"

  test "Constant kind":
    check symbolKindToString(skConstant) == "Const"

  test "Struct kind":
    check symbolKindToString(skStruct) == "Struct"

  test "Enum kind":
    check symbolKindToString(skEnum) == "Enum"

  test "Interface kind":
    check symbolKindToString(skInterface) == "Iface"

  test "Module kind":
    check symbolKindToString(skModule) == "Mod"

  test "Constructor kind":
    check symbolKindToString(skConstructor) == "Ctor"

suite "DocumentSymbolViewer - symbolKindToIcon":
  test "Function icon":
    check symbolKindToIcon(skFunction) == "f"

  test "Method icon":
    check symbolKindToIcon(skMethod) == "f"

  test "Class icon":
    check symbolKindToIcon(skClass) == "c"

  test "Struct icon":
    check symbolKindToIcon(skStruct) == "c"

  test "Interface icon":
    check symbolKindToIcon(skInterface) == "i"

  test "Variable icon":
    check symbolKindToIcon(skVariable) == "v"

  test "Field icon":
    check symbolKindToIcon(skField) == "v"

  test "Property icon":
    check symbolKindToIcon(skProperty) == "v"

  test "Constant icon":
    check symbolKindToIcon(skConstant) == "C"

  test "Enum icon":
    check symbolKindToIcon(skEnum) == "e"

  test "EnumMember icon":
    check symbolKindToIcon(skEnumMember) == "e"

  test "Module icon":
    check symbolKindToIcon(skModule) == "m"

  test "Namespace icon":
    check symbolKindToIcon(skNamespace) == "m"

  test "Package icon":
    check symbolKindToIcon(skPackage) == "m"

  test "Constructor icon":
    check symbolKindToIcon(skConstructor) == "+"

  test "Other kinds return dash":
    check symbolKindToIcon(skFile) == "-"
    check symbolKindToIcon(skNull) == "-"
    check symbolKindToIcon(skBoolean) == "-"

suite "DocumentSymbolViewer - newDocumentSymbolViewerState with hierarchical symbols":
  test "Create state with single symbol":
    let symbols = @[makeDocumentSymbol("myFunc", skFunction, 10, 0)]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.items.len == 1
    check state.items[0].name == "myFunc"
    check state.items[0].kind == skFunction
    check state.items[0].line == 10
    check state.items[0].column == 0
    check state.items[0].depth == 0
    check state.selectedIndex == 0
    check state.topLine == 0
    check state.filePath == "/path/to/file.nim"

  test "Create state with nested symbols":
    let childSymbols = @[
      makeDocumentSymbol("method1", skMethod, 5, 4),
      makeDocumentSymbol("method2", skMethod, 10, 4),
    ]
    let parentSymbol =
      makeDocumentSymbol("MyClass", skClass, 0, 0, children = some(childSymbols))
    let result =
      lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: @[parentSymbol])
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.items.len == 3
    check state.items[0].name == "MyClass"
    check state.items[0].depth == 0
    check state.items[1].name == "method1"
    check state.items[1].depth == 1
    check state.items[2].name == "method2"
    check state.items[2].depth == 1

  test "Create state with deeply nested symbols":
    let grandchildSymbols = @[makeDocumentSymbol("innerFunc", skFunction, 10, 8)]
    let childSymbols = @[
      makeDocumentSymbol(
        "nestedClass", skClass, 5, 4, children = some(grandchildSymbols)
      )
    ]
    let parentSymbol =
      makeDocumentSymbol("OuterClass", skClass, 0, 0, children = some(childSymbols))
    let result =
      lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: @[parentSymbol])
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.items.len == 3
    check state.items[0].name == "OuterClass"
    check state.items[0].depth == 0
    check state.items[1].name == "nestedClass"
    check state.items[1].depth == 1
    check state.items[2].name == "innerFunc"
    check state.items[2].depth == 2

  test "Create state with empty symbols":
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: @[])
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.items.len == 0
    check state.selectedIndex == 0
    check state.topLine == 0

  test "Create state with symbol that has detail":
    let symbols = @[
      makeDocumentSymbol(
        "myFunc", skFunction, 0, 0, detail = some("proc(a: int): string")
      )
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.items[0].detail == "proc(a: int): string"

suite "DocumentSymbolViewer - newDocumentSymbolViewerState with SymbolInformation":
  test "Create state with flat symbol information":
    let infos = @[
      makeSymbolInformation("func1", skFunction, "file:///test.nim", 0, 0),
      makeSymbolInformation("func2", skFunction, "file:///test.nim", 10, 0),
    ]
    let result =
      lspTypes.DocumentSymbolResult(isHierarchical: false, symbolInfos: infos)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.items.len == 2
    check state.items[0].name == "func1"
    check state.items[0].depth == 0
    check state.items[1].name == "func2"
    check state.items[1].depth == 0

  test "Create state with symbol information that has containerName":
    let infos = @[
      makeSymbolInformation(
        "myMethod", skMethod, "file:///test.nim", 5, 4, containerName = some("MyClass")
      )
    ]
    let result =
      lspTypes.DocumentSymbolResult(isHierarchical: false, symbolInfos: infos)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.items[0].detail == "MyClass"

suite "DocumentSymbolViewer - itemCount":
  test "Get item count with multiple items":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
      makeDocumentSymbol("baz", skFunction, 20, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.itemCount == 3

  test "Get item count with empty items":
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: @[])
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    check state.itemCount == 0

suite "DocumentSymbolViewer - getItem":
  test "Get item at valid index":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    let item = state.getItem(1)
    check item.isSome
    check item.get.name == "bar"

  test "Get item at negative index returns none":
    let symbols = @[makeDocumentSymbol("foo", skFunction, 0, 0)]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    let item = state.getItem(-1)
    check item.isNone

  test "Get item at out of bounds index returns none":
    let symbols = @[makeDocumentSymbol("foo", skFunction, 0, 0)]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    let item = state.getItem(5)
    check item.isNone

suite "DocumentSymbolViewer - getSelectedItem":
  test "Get selected item":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    let item = state.getSelectedItem()
    check item.isSome
    check item.get.name == "foo"

  test "Get selected item from empty state returns none":
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: @[])
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    let item = state.getSelectedItem()
    check item.isNone

suite "DocumentSymbolViewer - formatLine":
  test "Format line without detail":
    let item = SymbolItem(
      name: "myFunc", kind: skFunction, line: 9, column: 0, detail: "", depth: 0
    )
    let line = formatLine(item)

    check line == "[f] myFunc :10"

  test "Format line with detail":
    let item = SymbolItem(
      name: "myFunc",
      kind: skFunction,
      line: 9,
      column: 0,
      detail: "proc(a: int): string",
      depth: 0,
    )
    let line = formatLine(item)

    check line == "[f] myFunc (proc(a: int): string) :10"

  test "Format line with indentation":
    let item = SymbolItem(
      name: "method", kind: skMethod, line: 4, column: 4, detail: "", depth: 2
    )
    let line = formatLine(item)

    check line == "    [f] method :5"

  test "Format line with class icon":
    let item = SymbolItem(
      name: "MyClass", kind: skClass, line: 0, column: 0, detail: "", depth: 0
    )
    let line = formatLine(item)

    check line == "[c] MyClass :1"

suite "DocumentSymbolViewer - getLine":
  test "Get line at valid index":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 5),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    let line = state.getLine(1)
    check line == "[f] bar :11"

  test "Get line at negative index returns empty string":
    let symbols = @[makeDocumentSymbol("foo", skFunction, 0, 0)]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    let line = state.getLine(-1)
    check line == ""

  test "Get line at out of bounds index returns empty string":
    let symbols = @[makeDocumentSymbol("foo", skFunction, 0, 0)]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    let line = state.getLine(10)
    check line == ""

suite "DocumentSymbolViewer - moveUp":
  test "Move up from middle":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
      makeDocumentSymbol("baz", skFunction, 20, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.selectedIndex = 2

    state.moveUp()

    check state.selectedIndex == 1

  test "Move up from first item does nothing":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    state.moveUp()

    check state.selectedIndex == 0

suite "DocumentSymbolViewer - moveDown":
  test "Move down from first":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
      makeDocumentSymbol("baz", skFunction, 20, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    state.moveDown()

    check state.selectedIndex == 1

  test "Move down from last item does nothing":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.selectedIndex = 1

    state.moveDown()

    check state.selectedIndex == 1

suite "DocumentSymbolViewer - moveToFirst":
  test "Move to first from middle":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
      makeDocumentSymbol("baz", skFunction, 20, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.selectedIndex = 2

    state.moveToFirst()

    check state.selectedIndex == 0

  test "Move to first when already at first":
    let symbols = @[makeDocumentSymbol("foo", skFunction, 0, 0)]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    state.moveToFirst()

    check state.selectedIndex == 0

suite "DocumentSymbolViewer - moveToLast":
  test "Move to last from first":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
      makeDocumentSymbol("baz", skFunction, 20, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    state.moveToLast()

    check state.selectedIndex == 2

  test "Move to last with empty items":
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: @[])
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    state.moveToLast()

    check state.selectedIndex == 0

  test "Move to last when already at last":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.selectedIndex = 1

    state.moveToLast()

    check state.selectedIndex == 1

suite "DocumentSymbolViewer - halfPageUp":
  test "Half page up from middle":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.selectedIndex = 15

    state.halfPageUp(10)

    check state.selectedIndex == 10

  test "Half page up near top":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.selectedIndex = 2

    state.halfPageUp(10)

    check state.selectedIndex == 0

  test "Half page up at top does nothing":
    let symbols = @[
      makeDocumentSymbol("foo", skFunction, 0, 0),
      makeDocumentSymbol("bar", skFunction, 10, 0),
    ]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    state.halfPageUp(10)

    check state.selectedIndex == 0

suite "DocumentSymbolViewer - halfPageDown":
  test "Half page down from middle":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.selectedIndex = 5

    state.halfPageDown(10)

    check state.selectedIndex == 10

  test "Half page down near bottom":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.selectedIndex = 17

    state.halfPageDown(10)

    check state.selectedIndex == 19

  test "Half page down with empty items":
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: @[])
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")

    state.halfPageDown(10)

    check state.selectedIndex == 0

suite "DocumentSymbolViewer - ensureSelectedVisible":
  test "Selected above viewport scrolls up":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.topLine = 10
    state.selectedIndex = 5

    state.ensureSelectedVisible(5)

    check state.topLine == 5

  test "Selected below viewport scrolls down":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.topLine = 0
    state.selectedIndex = 10

    state.ensureSelectedVisible(5)

    check state.topLine == 6

  test "Selected within viewport does not change topLine":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.topLine = 5
    state.selectedIndex = 7

    state.ensureSelectedVisible(5)

    check state.topLine == 5

  test "Negative topLine is corrected to zero":
    let symbols = @[makeDocumentSymbol("foo", skFunction, 0, 0)]
    let result = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(result, "/path/to/file.nim")
    state.topLine = -5
    state.selectedIndex = 0

    state.ensureSelectedVisible(10)

    check state.topLine == 0
