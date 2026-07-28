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
import ../src/moepkg/callhierarchy_viewer
import ../src/moepkg/command_handlers/callhierarchy_handler
import ../src/moepkg/key_bindings

proc makeCallHierarchyItem(
    name: string,
    uri: string,
    line: int,
    col: int,
    detail: Option[string] = none(string),
): lspTypes.CallHierarchyItem =
  ## Helper to create a CallHierarchyItem for testing
  result.name = name
  result.kind = skFunction
  result.uri = uri
  result.range = lspTypes.Range(
    start: lspTypes.Position(line: line, character: col),
    `end`: lspTypes.Position(line: line, character: col + name.len),
  )
  result.selectionRange = result.range
  result.detail = detail

proc makeTestState(): CallHierarchyViewerState =
  ## Create a test state with multiple items
  let items = @[
    makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
    makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
    makeCallHierarchyItem("baz", "file:///test.nim", 20, 0),
  ]
  newCallHierarchyViewerState(items, chvkPrepare)

proc makeEmptyTestState(): CallHierarchyViewerState =
  ## Create a test state with no items
  let items: seq[lspTypes.CallHierarchyItem] = @[]
  newCallHierarchyViewerState(items, chvkPrepare)

suite "CallHierarchyViewerState - waitingForG reset":
  test "fresh CallHierarchyViewerState has waitingForG reset":
    let state = makeTestState()

    check state.waitingForG == false

suite "callhierarchy_handler: handleCallHierarchyModeKey - Escape":
  test "Escape key returns chvrQuit":
    let state = makeTestState()
    let keyCombo = toSpecialKeyCombo(skEscape)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrQuit

suite "callhierarchy_handler: handleCallHierarchyModeKey - q":
  test "q key returns chvrQuit":
    let state = makeTestState()
    let keyCombo = toKeyCombo('q')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrQuit

suite "callhierarchy_handler: handleCallHierarchyModeKey - colon":
  test "Colon key returns chvrEnterCommand":
    let state = makeTestState()
    let keyCombo = toKeyCombo(':')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrEnterCommand

suite "callhierarchy_handler: handleCallHierarchyModeKey - j":
  test "j key moves down":
    let state = makeTestState()
    let keyCombo = toKeyCombo('j')

    check state.selectedIndex == 0

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

  test "j key at last item stays at last":
    let state = makeTestState()
    state.selectedIndex = 2
    let keyCombo = toKeyCombo('j')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 2

suite "callhierarchy_handler: handleCallHierarchyModeKey - Down arrow":
  test "Down arrow key moves down":
    let state = makeTestState()
    let keyCombo = toSpecialKeyCombo(skDown)

    check state.selectedIndex == 0

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

suite "callhierarchy_handler: handleCallHierarchyModeKey - k":
  test "k key moves up":
    let state = makeTestState()
    state.selectedIndex = 2
    let keyCombo = toKeyCombo('k')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

  test "k key at first item stays at first":
    let state = makeTestState()
    let keyCombo = toKeyCombo('k')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 0

suite "callhierarchy_handler: handleCallHierarchyModeKey - Up arrow":
  test "Up arrow key moves up":
    let state = makeTestState()
    state.selectedIndex = 2
    let keyCombo = toSpecialKeyCombo(skUp)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

suite "callhierarchy_handler: handleCallHierarchyModeKey - gg":
  test "gg moves to first item":
    let state = makeTestState()
    state.selectedIndex = 2
    let keyComboG = toKeyCombo('g')

    # First g
    let result1 = handleCallHierarchyModeKey(state, 10, keyComboG)
    check result1.kind == chvrHandled
    check state.waitingForG == true
    check state.selectedIndex == 2 # Not moved yet

    # Second g
    let result2 = handleCallHierarchyModeKey(state, 10, keyComboG)
    check result2.kind == chvrHandled
    check state.waitingForG == false
    check state.selectedIndex == 0

  test "g followed by non-g cancels and handles the key":
    let state = makeTestState()
    state.selectedIndex = 1
    let keyComboG = toKeyCombo('g')
    let keyComboJ = toKeyCombo('j')

    # First g
    let result1 = handleCallHierarchyModeKey(state, 10, keyComboG)
    check result1.kind == chvrHandled
    check state.waitingForG == true

    # j instead of second g - should cancel gg and process j
    let result2 = handleCallHierarchyModeKey(state, 10, keyComboJ)
    check result2.kind == chvrHandled
    check state.waitingForG == false
    check state.selectedIndex == 2 # Moved down by j

suite "callhierarchy_handler: handleCallHierarchyModeKey - G":
  test "G moves to last item":
    let state = makeTestState()
    let keyCombo = toKeyCombo('G')

    check state.selectedIndex == 0

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 2

suite "callhierarchy_handler: handleCallHierarchyModeKey - Enter":
  test "Enter key returns chvrJumpToItem with selected item":
    let state = makeTestState()
    state.selectedIndex = 1
    let keyCombo = toSpecialKeyCombo(skEnter)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrJumpToItem
    check result.targetItem.name == "bar"

  test "Enter key with empty state returns chvrError":
    let state = makeEmptyTestState()
    let keyCombo = toSpecialKeyCombo(skEnter)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrError
    check result.errorMessage == "No item selected"

suite "callhierarchy_handler: handleCallHierarchyModeKey - i":
  test "i key returns chvrRequestIncoming with selected item":
    let state = makeTestState()
    state.selectedIndex = 1
    let keyCombo = toKeyCombo('i')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrRequestIncoming
    check result.targetItem.name == "bar"

  test "i key with empty state returns chvrError":
    let state = makeEmptyTestState()
    let keyCombo = toKeyCombo('i')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrError
    check result.errorMessage == "No item selected"

suite "callhierarchy_handler: handleCallHierarchyModeKey - o":
  test "o key returns chvrRequestOutgoing with selected item":
    let state = makeTestState()
    state.selectedIndex = 2
    let keyCombo = toKeyCombo('o')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrRequestOutgoing
    check result.targetItem.name == "baz"

  test "o key with empty state returns chvrError":
    let state = makeEmptyTestState()
    let keyCombo = toKeyCombo('o')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrError
    check result.errorMessage == "No item selected"

suite "callhierarchy_handler: handleCallHierarchyModeKey - Ctrl+d":
  test "Ctrl+d moves half page down":
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('d', ctrl = true)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 5 # Half of viewport height 10

suite "callhierarchy_handler: handleCallHierarchyModeKey - Ctrl+u":
  test "Ctrl+u moves half page up":
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 15
    let keyCombo = toKeyCombo('u', ctrl = true)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 10 # 15 - (10 / 2)

suite "callhierarchy_handler: handleCallHierarchyModeKey - unhandled":
  test "Unhandled key returns chvrUnhandled":
    let state = makeTestState()
    let keyCombo = toKeyCombo('x')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrUnhandled

  test "Unhandled special key returns chvrUnhandled":
    let state = makeTestState()
    let keyCombo = toSpecialKeyCombo(skDelete)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrUnhandled

suite "callhierarchy_handler: handleCallHierarchyModeKey - Navigation":
  test "G moves to the last item":
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 0
    let viewportHeight = 5

    # Move to last with G
    let keyCombo = toKeyCombo('G')
    let result = handleCallHierarchyModeKey(state, viewportHeight, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 19

suite "callhierarchy_handler: handleCallHierarchyModeKey - g followed by special key":
  test "g followed by Escape quits":
    let state = makeTestState()
    state.selectedIndex = 2
    let keyComboG = toKeyCombo('g')
    let keyComboEsc = toSpecialKeyCombo(skEscape)

    # First g
    let result1 = handleCallHierarchyModeKey(state, 10, keyComboG)
    check result1.kind == chvrHandled
    check state.waitingForG == true

    # Escape - should cancel gg and process Escape (quit)
    let result2 = handleCallHierarchyModeKey(state, 10, keyComboEsc)
    check result2.kind == chvrQuit
    check state.waitingForG == false

  test "g followed by Up arrow moves up":
    let state = makeTestState()
    state.selectedIndex = 2
    let keyComboG = toKeyCombo('g')
    let keyComboUp = toSpecialKeyCombo(skUp)

    # First g
    discard handleCallHierarchyModeKey(state, 10, keyComboG)
    check state.waitingForG == true

    # Up arrow - should cancel gg and process Up
    let result = handleCallHierarchyModeKey(state, 10, keyComboUp)
    check result.kind == chvrHandled
    check state.waitingForG == false
    check state.selectedIndex == 1

  test "g followed by Enter jumps to item":
    let state = makeTestState()
    state.selectedIndex = 1
    let keyComboG = toKeyCombo('g')
    let keyComboEnter = toSpecialKeyCombo(skEnter)

    # First g
    discard handleCallHierarchyModeKey(state, 10, keyComboG)

    # Enter - should cancel gg and process Enter
    let result = handleCallHierarchyModeKey(state, 10, keyComboEnter)
    check result.kind == chvrJumpToItem
    check result.targetItem.name == "bar"
    check state.waitingForG == false

suite "callhierarchy_handler: handleCallHierarchyModeKey - g followed by quit key":
  test "g followed by q quits":
    let state = makeTestState()
    let keyComboG = toKeyCombo('g')
    let keyComboQ = toKeyCombo('q')

    # First g
    discard handleCallHierarchyModeKey(state, 10, keyComboG)
    check state.waitingForG == true

    # q - should cancel gg and process q (quit)
    let result = handleCallHierarchyModeKey(state, 10, keyComboQ)
    check result.kind == chvrQuit
    check state.waitingForG == false

suite "callhierarchy_handler: handleCallHierarchyModeKey - modifier keys":
  test "Ctrl+x returns chvrUnhandled":
    let state = makeTestState()
    let keyCombo = toKeyCombo('x', ctrl = true)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrUnhandled

  test "Alt+j falls through so caller-level bindings can act on it":
    let state = makeTestState()
    let keyCombo = toKeyCombo('j', alt = true)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrUnhandled
    check state.selectedIndex == 0

  test "Shift+G falls through so caller-level bindings can act on it":
    # A terminal-typed uppercase G has empty modifiers (shift is baked into the
    # char); an explicit kmShift is unusual, so let it fall through.
    let state = makeTestState()
    let keyCombo = toKeyCombo('G', shift = true)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrUnhandled
    check state.selectedIndex == 0

suite "CallHierarchyViewerState - multiple states independence":
  test "Multiple states have independent waitingForG":
    let state1 = makeTestState()
    let state2 = makeTestState()
    let keyComboG = toKeyCombo('g')

    # Press g on state1
    discard handleCallHierarchyModeKey(state1, 10, keyComboG)

    check state1.waitingForG == true
    check state2.waitingForG == false

suite "callhierarchy_handler: handleCallHierarchyModeKey - g followed by unhandled special key":
  test "g followed by Delete returns chvrUnhandled":
    let state = makeTestState()
    let keyComboG = toKeyCombo('g')
    let keyComboPageUp = toSpecialKeyCombo(skDelete)

    # First g
    discard handleCallHierarchyModeKey(state, 10, keyComboG)
    check state.waitingForG == true

    # Delete - should cancel gg and fall through to unhandled
    let result = handleCallHierarchyModeKey(state, 10, keyComboPageUp)
    check result.kind == chvrUnhandled
    check state.waitingForG == false

suite "callhierarchy_handler: handleCallHierarchyModeKey - boundary conditions":
  test "Ctrl+d at last item stays at last":
    let state = makeTestState()
    state.selectedIndex = 2 # Last item (3 items total)
    let keyCombo = toKeyCombo('d', ctrl = true)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 2

  test "Ctrl+u at first item stays at first":
    let state = makeTestState()
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('u', ctrl = true)

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 0

  test "G with empty state":
    let state = makeEmptyTestState()
    let keyCombo = toKeyCombo('G')

    let result = handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 0

  test "gg with empty state":
    let state = makeEmptyTestState()
    let keyComboG = toKeyCombo('g')

    discard handleCallHierarchyModeKey(state, 10, keyComboG)
    let result = handleCallHierarchyModeKey(state, 10, keyComboG)

    check result.kind == chvrHandled
    check state.selectedIndex == 0
