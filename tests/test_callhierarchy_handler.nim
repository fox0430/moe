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

suite "SubStateHandler - newSubStateHandler":
  test "Create new handler":
    let handler = newSubStateHandler()

    check handler.waitingForG == false

suite "SubStateHandler - handleCallHierarchyModeKey - Escape":
  test "Escape key returns chvrQuit":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toSpecialKeyCombo(skEscape)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrQuit

suite "SubStateHandler - handleCallHierarchyModeKey - q":
  test "q key returns chvrQuit":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo('q')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrQuit

suite "SubStateHandler - handleCallHierarchyModeKey - colon":
  test "Colon key returns chvrEnterCommand":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo(':')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrEnterCommand

suite "SubStateHandler - handleCallHierarchyModeKey - j":
  test "j key moves down":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo('j')

    check state.selectedIndex == 0

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

  test "j key at last item stays at last":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 2
    let keyCombo = toKeyCombo('j')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 2

suite "SubStateHandler - handleCallHierarchyModeKey - Down arrow":
  test "Down arrow key moves down":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toSpecialKeyCombo(skDown)

    check state.selectedIndex == 0

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

suite "SubStateHandler - handleCallHierarchyModeKey - k":
  test "k key moves up":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 2
    let keyCombo = toKeyCombo('k')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

  test "k key at first item stays at first":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo('k')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 0

suite "SubStateHandler - handleCallHierarchyModeKey - Up arrow":
  test "Up arrow key moves up":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 2
    let keyCombo = toSpecialKeyCombo(skUp)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

suite "SubStateHandler - handleCallHierarchyModeKey - gg":
  test "gg moves to first item":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 2
    let keyComboG = toKeyCombo('g')

    # First g
    let result1 = handler.handleCallHierarchyModeKey(state, 10, keyComboG)
    check result1.kind == chvrHandled
    check handler.waitingForG == true
    check state.selectedIndex == 2 # Not moved yet

    # Second g
    let result2 = handler.handleCallHierarchyModeKey(state, 10, keyComboG)
    check result2.kind == chvrHandled
    check handler.waitingForG == false
    check state.selectedIndex == 0

  test "g followed by non-g cancels and handles the key":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 1
    let keyComboG = toKeyCombo('g')
    let keyComboJ = toKeyCombo('j')

    # First g
    let result1 = handler.handleCallHierarchyModeKey(state, 10, keyComboG)
    check result1.kind == chvrHandled
    check handler.waitingForG == true

    # j instead of second g - should cancel gg and process j
    let result2 = handler.handleCallHierarchyModeKey(state, 10, keyComboJ)
    check result2.kind == chvrHandled
    check handler.waitingForG == false
    check state.selectedIndex == 2 # Moved down by j

suite "SubStateHandler - handleCallHierarchyModeKey - G":
  test "G moves to last item":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo('G')

    check state.selectedIndex == 0

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 2

suite "SubStateHandler - handleCallHierarchyModeKey - Enter":
  test "Enter key returns chvrJumpToItem with selected item":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 1
    let keyCombo = toSpecialKeyCombo(skEnter)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrJumpToItem
    check result.targetItem.name == "bar"

  test "Enter key with empty state returns chvrError":
    let handler = newSubStateHandler()
    let state = makeEmptyTestState()
    let keyCombo = toSpecialKeyCombo(skEnter)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrError
    check result.errorMessage == "No item selected"

suite "SubStateHandler - handleCallHierarchyModeKey - i":
  test "i key returns chvrRequestIncoming with selected item":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 1
    let keyCombo = toKeyCombo('i')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrRequestIncoming
    check result.targetItem.name == "bar"

  test "i key with empty state returns chvrError":
    let handler = newSubStateHandler()
    let state = makeEmptyTestState()
    let keyCombo = toKeyCombo('i')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrError
    check result.errorMessage == "No item selected"

suite "SubStateHandler - handleCallHierarchyModeKey - o":
  test "o key returns chvrRequestOutgoing with selected item":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 2
    let keyCombo = toKeyCombo('o')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrRequestOutgoing
    check result.targetItem.name == "baz"

  test "o key with empty state returns chvrError":
    let handler = newSubStateHandler()
    let state = makeEmptyTestState()
    let keyCombo = toKeyCombo('o')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrError
    check result.errorMessage == "No item selected"

suite "SubStateHandler - handleCallHierarchyModeKey - Ctrl+d":
  test "Ctrl+d moves half page down":
    let handler = newSubStateHandler()
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('d', ctrl = true)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 5 # Half of viewport height 10

suite "SubStateHandler - handleCallHierarchyModeKey - Ctrl+u":
  test "Ctrl+u moves half page up":
    let handler = newSubStateHandler()
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 15
    let keyCombo = toKeyCombo('u', ctrl = true)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 10 # 15 - (10 / 2)

suite "SubStateHandler - handleCallHierarchyModeKey - unhandled":
  test "Unhandled key returns chvrUnhandled":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo('x')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrUnhandled

  test "Unhandled special key returns chvrUnhandled":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toSpecialKeyCombo(skPageUp)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrUnhandled

suite "SubStateHandler - handleCallHierarchyModeKey - ensureSelectedVisible":
  test "Moving updates topLine to keep selection visible":
    let handler = newSubStateHandler()
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 0
    state.topLine = 0
    let viewportHeight = 5

    # Move to last with G
    let keyCombo = toKeyCombo('G')
    let result = handler.handleCallHierarchyModeKey(state, viewportHeight, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 19
    # topLine should be adjusted to keep selected visible
    check state.topLine == 15 # 19 - 5 + 1

suite "SubStateHandler - handleCallHierarchyModeKey - g followed by special key":
  test "g followed by Escape quits":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 2
    let keyComboG = toKeyCombo('g')
    let keyComboEsc = toSpecialKeyCombo(skEscape)

    # First g
    let result1 = handler.handleCallHierarchyModeKey(state, 10, keyComboG)
    check result1.kind == chvrHandled
    check handler.waitingForG == true

    # Escape - should cancel gg and process Escape (quit)
    let result2 = handler.handleCallHierarchyModeKey(state, 10, keyComboEsc)
    check result2.kind == chvrQuit
    check handler.waitingForG == false

  test "g followed by Up arrow moves up":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 2
    let keyComboG = toKeyCombo('g')
    let keyComboUp = toSpecialKeyCombo(skUp)

    # First g
    discard handler.handleCallHierarchyModeKey(state, 10, keyComboG)
    check handler.waitingForG == true

    # Up arrow - should cancel gg and process Up
    let result = handler.handleCallHierarchyModeKey(state, 10, keyComboUp)
    check result.kind == chvrHandled
    check handler.waitingForG == false
    check state.selectedIndex == 1

  test "g followed by Enter jumps to item":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 1
    let keyComboG = toKeyCombo('g')
    let keyComboEnter = toSpecialKeyCombo(skEnter)

    # First g
    discard handler.handleCallHierarchyModeKey(state, 10, keyComboG)

    # Enter - should cancel gg and process Enter
    let result = handler.handleCallHierarchyModeKey(state, 10, keyComboEnter)
    check result.kind == chvrJumpToItem
    check result.targetItem.name == "bar"
    check handler.waitingForG == false

suite "SubStateHandler - handleCallHierarchyModeKey - g followed by quit key":
  test "g followed by q quits":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyComboG = toKeyCombo('g')
    let keyComboQ = toKeyCombo('q')

    # First g
    discard handler.handleCallHierarchyModeKey(state, 10, keyComboG)
    check handler.waitingForG == true

    # q - should cancel gg and process q (quit)
    let result = handler.handleCallHierarchyModeKey(state, 10, keyComboQ)
    check result.kind == chvrQuit
    check handler.waitingForG == false

suite "SubStateHandler - handleCallHierarchyModeKey - modifier keys":
  test "Ctrl+x returns chvrUnhandled":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo('x', ctrl = true)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrUnhandled

  test "Alt+j still moves down (modifiers ignored for navigation)":
    # Note: Current implementation ignores Alt modifier for j/k keys
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo('j', alt = true)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 1

  test "Shift+G moves to last (modifiers ignored)":
    # Note: Current implementation handles uppercase G via char matching
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyCombo = toKeyCombo('G', shift = true)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 2

suite "SubStateHandler - multiple handlers independence":
  test "Multiple handlers have independent state":
    let handler1 = newSubStateHandler()
    let handler2 = newSubStateHandler()
    let state = makeTestState()
    let keyComboG = toKeyCombo('g')

    # Press g on handler1
    discard handler1.handleCallHierarchyModeKey(state, 10, keyComboG)

    check handler1.waitingForG == true
    check handler2.waitingForG == false

suite "SubStateHandler - handleCallHierarchyModeKey - g followed by unhandled special key":
  test "g followed by PageUp returns chvrUnhandled":
    let handler = newSubStateHandler()
    let state = makeTestState()
    let keyComboG = toKeyCombo('g')
    let keyComboPageUp = toSpecialKeyCombo(skPageUp)

    # First g
    discard handler.handleCallHierarchyModeKey(state, 10, keyComboG)
    check handler.waitingForG == true

    # PageUp - should cancel gg and fall through to unhandled
    let result = handler.handleCallHierarchyModeKey(state, 10, keyComboPageUp)
    check result.kind == chvrUnhandled
    check handler.waitingForG == false

suite "SubStateHandler - handleCallHierarchyModeKey - boundary conditions":
  test "Ctrl+d at last item stays at last":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 2 # Last item (3 items total)
    let keyCombo = toKeyCombo('d', ctrl = true)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 2

  test "Ctrl+u at first item stays at first":
    let handler = newSubStateHandler()
    let state = makeTestState()
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('u', ctrl = true)

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 0

  test "G with empty state":
    let handler = newSubStateHandler()
    let state = makeEmptyTestState()
    let keyCombo = toKeyCombo('G')

    let result = handler.handleCallHierarchyModeKey(state, 10, keyCombo)

    check result.kind == chvrHandled
    check state.selectedIndex == 0

  test "gg with empty state":
    let handler = newSubStateHandler()
    let state = makeEmptyTestState()
    let keyComboG = toKeyCombo('g')

    discard handler.handleCallHierarchyModeKey(state, 10, keyComboG)
    let result = handler.handleCallHierarchyModeKey(state, 10, keyComboG)

    check result.kind == chvrHandled
    check state.selectedIndex == 0
