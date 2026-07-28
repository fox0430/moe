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
import ../src/moepkg/[documentsymbol_viewer, key_bindings]
import ../src/moepkg/command_handlers/documentsymbol_handler

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

proc createTestState(symbolCount: int = 3): DocumentSymbolViewerState =
  ## Create a test state with multiple symbols
  var symbols: seq[lspTypes.DocumentSymbol] = @[]
  for i in 0 ..< symbolCount:
    symbols.add(makeDocumentSymbol("func" & $i, skFunction, i * 10, 0))
  let symResult = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
  newDocumentSymbolViewerState(symResult, "/path/to/file.nim")

proc createEmptyState(): DocumentSymbolViewerState =
  ## Create a test state with no symbols
  let symResult = lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: @[])
  newDocumentSymbolViewerState(symResult, "/path/to/file.nim")

proc charKeyCombo(ch: string): KeyCombo =
  ## Create a simple character key combo
  KeyCombo(isSpecial: false, char: ch, modifiers: {})

proc ctrlKeyCombo(ch: string): KeyCombo =
  ## Create a Ctrl+char key combo
  KeyCombo(isSpecial: false, char: ch, modifiers: {kmCtrl})

proc specialKeyCombo(key: SpecialKey): KeyCombo =
  ## Create a special key combo
  KeyCombo(isSpecial: true, special: key, modifiers: {})

suite "DocumentSymbolViewerState - waitingForG initial value":
  test "fresh DocumentSymbolViewerState has waitingForG reset":
    let state = createTestState()

    check state.waitingForG == false

suite "documentsymbol_handler: handleDocumentSymbolModeKey - Quit commands":
  test "Escape key quits":
    let state = createTestState()
    let keyCombo = specialKeyCombo(skEscape)

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrQuit

  test "'q' key quits":
    let state = createTestState()
    let keyCombo = charKeyCombo("q")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrQuit

suite "documentsymbol_handler: handleDocumentSymbolModeKey - Command mode":
  test "':' key enters command mode":
    let state = createTestState()
    let keyCombo = charKeyCombo(":")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrEnterCommand

suite "documentsymbol_handler: handleDocumentSymbolModeKey - Navigation with j/k":
  test "'j' key moves down":
    let state = createTestState()
    state.selectedIndex = 0
    let keyCombo = charKeyCombo("j")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 1

  test "'k' key moves up":
    let state = createTestState()
    state.selectedIndex = 2
    let keyCombo = charKeyCombo("k")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 1

  test "'j' at last item stays at last":
    let state = createTestState()
    state.selectedIndex = 2
    let keyCombo = charKeyCombo("j")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 2

  test "'k' at first item stays at first":
    let state = createTestState()
    state.selectedIndex = 0
    let keyCombo = charKeyCombo("k")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 0

suite "documentsymbol_handler: handleDocumentSymbolModeKey - Navigation with arrow keys":
  test "Down arrow moves down":
    let state = createTestState()
    state.selectedIndex = 0
    let keyCombo = specialKeyCombo(skDown)

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 1

  test "Up arrow moves up":
    let state = createTestState()
    state.selectedIndex = 2
    let keyCombo = specialKeyCombo(skUp)

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 1

suite "documentsymbol_handler: handleDocumentSymbolModeKey - G and gg commands":
  test "'G' moves to last":
    let state = createTestState()
    state.selectedIndex = 0
    let keyCombo = charKeyCombo("G")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 2

  test "'g' sets waitingForG":
    let state = createTestState()
    state.selectedIndex = 2
    let keyCombo = charKeyCombo("g")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.waitingForG == true

  test "'gg' moves to first":
    let state = createTestState()
    state.selectedIndex = 2
    let keyComboG = charKeyCombo("g")

    # First 'g'
    discard handleDocumentSymbolModeKey(state, 10, keyComboG)
    check state.waitingForG == true

    # Second 'g'
    let result = handleDocumentSymbolModeKey(state, 10, keyComboG)

    check result.kind == dsvrHandled
    check state.waitingForG == false
    check state.selectedIndex == 0

  test "'g' followed by other key resets state":
    let state = createTestState()
    state.selectedIndex = 2
    let keyComboG = charKeyCombo("g")
    let keyComboJ = charKeyCombo("j")

    # First 'g'
    discard handleDocumentSymbolModeKey(state, 10, keyComboG)
    check state.waitingForG == true

    # 'j' after 'g' - should reset waitingForG and handle j normally
    let result = handleDocumentSymbolModeKey(state, 10, keyComboJ)

    check state.waitingForG == false
    check result.kind == dsvrHandled
    # j should move down (but already at last, so stays at 2)
    check state.selectedIndex == 2

suite "documentsymbol_handler: handleDocumentSymbolModeKey - Enter key":
  test "Enter key jumps to selected symbol":
    let state = createTestState()
    state.selectedIndex = 1
    let keyCombo = specialKeyCombo(skEnter)

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrJumpToSymbol
    check result.targetItem.name == "func1"
    check result.targetItem.line == 10

  test "Enter key with empty state returns error":
    let state = createEmptyState()
    let keyCombo = specialKeyCombo(skEnter)

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrError
    check result.errorMessage == "No symbol selected"

suite "documentsymbol_handler: handleDocumentSymbolModeKey - Half page navigation":
  test "Ctrl+d moves half page down":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let symResult =
      lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(symResult, "/path/to/file.nim")
    state.selectedIndex = 5
    let keyCombo = ctrlKeyCombo("d")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 10

  test "Ctrl+u moves half page up":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let symResult =
      lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(symResult, "/path/to/file.nim")
    state.selectedIndex = 15
    let keyCombo = ctrlKeyCombo("u")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 10

  test "Ctrl+d at bottom stays at bottom":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let symResult =
      lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(symResult, "/path/to/file.nim")
    state.selectedIndex = 19
    let keyCombo = ctrlKeyCombo("d")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 19

  test "Ctrl+u at top stays at top":
    let state = createTestState()
    state.selectedIndex = 0
    let keyCombo = ctrlKeyCombo("u")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 0

suite "documentsymbol_handler: handleDocumentSymbolModeKey - Unhandled keys":
  test "Unknown character key returns unhandled":
    let state = createTestState()
    let keyCombo = charKeyCombo("x")

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrUnhandled

  test "Unknown special key returns unhandled":
    let state = createTestState()
    let keyCombo = specialKeyCombo(skDelete)

    let result = handleDocumentSymbolModeKey(state, 10, keyCombo)

    check result.kind == dsvrUnhandled

suite "documentsymbol_handler: handleDocumentSymbolModeKey - Navigation":
  test "G moves to the last symbol":
    var symbols: seq[lspTypes.DocumentSymbol] = @[]
    for i in 0 ..< 20:
      symbols.add(makeDocumentSymbol("func" & $i, skFunction, i, 0))
    let symResult =
      lspTypes.DocumentSymbolResult(isHierarchical: true, symbols: symbols)
    let state = newDocumentSymbolViewerState(symResult, "/path/to/file.nim")
    state.selectedIndex = 0
    let keyCombo = charKeyCombo("G")

    let result = handleDocumentSymbolModeKey(state, 5, keyCombo)

    check result.kind == dsvrHandled
    check state.selectedIndex == 19
