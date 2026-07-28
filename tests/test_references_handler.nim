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

import std/unittest
import ../src/moepkg/references_viewer
import ../src/moepkg/command_handlers/references_handler
import ../src/moepkg/key_bindings

suite "references_handler: Handler creation":
  test "fresh ReferencesViewerState has waitingForG reset":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)

    check state.waitingForG == false

suite "references_handler: Navigation keys":
  test "j key moves down":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    let keyCombo = toKeyCombo('j')

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

  test "k key moves up":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 2
    let keyCombo = toKeyCombo('k')

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

  test "Down arrow key moves down":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    let keyCombo = toSpecialKeyCombo(skDown)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

  test "Up arrow key moves up":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1
    let keyCombo = toSpecialKeyCombo(skUp)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 0

suite "references_handler: Go to first/last":
  test "gg moves to first item":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 2

    # First g
    let firstG = toKeyCombo('g')
    let result1 = handleReferencesModeKey(state, 10, firstG)

    check result1.kind == rvrHandled
    check state.waitingForG == true
    check state.selectedIndex == 2

    # Second g
    let secondG = toKeyCombo('g')
    let result2 = handleReferencesModeKey(state, 10, secondG)

    check result2.kind == rvrHandled
    check state.waitingForG == false
    check state.selectedIndex == 0

  test "G moves to last item":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('G')

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 2

  test "g followed by non-g cancels gg sequence":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 2

    # First g
    let firstG = toKeyCombo('g')
    discard handleReferencesModeKey(state, 10, firstG)

    check state.waitingForG == true

    # j instead of g - should cancel gg and move down
    let jKey = toKeyCombo('j')
    discard handleReferencesModeKey(state, 10, jKey)

    check state.waitingForG == false
    # The j key should be processed normally after gg cancellation
    # Position doesn't change because we're at last index (2) and moveDown does nothing

suite "references_handler: Half page navigation":
  test "Ctrl+d moves half page down":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 5
    let keyCombo = toKeyCombo('d', ctrl = true)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 10

  test "Ctrl+u moves half page up":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 15
    let keyCombo = toKeyCombo('u', ctrl = true)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 10

suite "references_handler: Quit commands":
  test "q key returns quit result":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toKeyCombo('q')

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrQuit

  test "Escape key returns quit result":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toSpecialKeyCombo(skEscape)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrQuit

suite "references_handler: Enter command mode":
  test ": key returns enter command result":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toKeyCombo(':')

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrEnterCommand

suite "references_handler: Jump to reference":
  test "Enter key returns jump result with selected item":
    let items = @[
      ReferenceItem(path: "/first.nim", line: 10, column: 5, text: "first"),
      ReferenceItem(path: "/second.nim", line: 20, column: 10, text: "second"),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1
    let keyCombo = toSpecialKeyCombo(skEnter)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrJumpToReference
    check result.targetItem.path == "/second.nim"
    check result.targetItem.line == 20
    check result.targetItem.column == 10
    check result.targetItem.text == "second"

  test "Enter key on empty state returns error":
    let state = newReferencesViewerState(@[])
    let keyCombo = toSpecialKeyCombo(skEnter)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrError
    check result.errorMessage == "No reference selected"

suite "references_handler: Unhandled keys":
  test "unhandled key returns unhandled result":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toKeyCombo('x') # x is not a handled key

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrUnhandled

  test "unhandled special key returns unhandled result":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toSpecialKeyCombo(skDelete) # Delete is not handled

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrUnhandled

suite "references_handler: Navigation":
  test "repeated j advances the selection":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 30:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 0

    for _ in 0 ..< 15:
      let keyCombo = toKeyCombo('j')
      discard handleReferencesModeKey(state, 10, keyCombo)

    check state.selectedIndex == 15

suite "references_handler: Boundary conditions":
  test "k at first item stays at first":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('k')

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 0

  test "j at last item stays at last":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1
    let keyCombo = toKeyCombo('j')

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

  test "Up arrow at first item stays at first":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0
    let keyCombo = toSpecialKeyCombo(skUp)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 0

  test "Down arrow at last item stays at last":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1
    let keyCombo = toSpecialKeyCombo(skDown)

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

suite "references_handler: gg with special key":
  test "g followed by Escape cancels gg and quits":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1

    # First g
    let firstG = toKeyCombo('g')
    discard handleReferencesModeKey(state, 10, firstG)

    check state.waitingForG == true

    # Escape - should cancel gg and quit
    let escKey = toSpecialKeyCombo(skEscape)
    let result = handleReferencesModeKey(state, 10, escKey)

    check state.waitingForG == false
    check result.kind == rvrQuit
    check state.selectedIndex == 1 # Position unchanged

  test "g followed by Enter cancels gg and jumps":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 1, column: 2, text: "target"),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1

    # First g
    let firstG = toKeyCombo('g')
    discard handleReferencesModeKey(state, 10, firstG)

    check state.waitingForG == true

    # Enter - should cancel gg and jump to reference
    let enterKey = toSpecialKeyCombo(skEnter)
    let result = handleReferencesModeKey(state, 10, enterKey)

    check state.waitingForG == false
    check result.kind == rvrJumpToReference
    check result.targetItem.path == "/b.nim"

  test "g followed by Down cancels gg and moves down":
    let items = @[
      ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
    ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0

    # First g
    let firstG = toKeyCombo('g')
    discard handleReferencesModeKey(state, 10, firstG)

    check state.waitingForG == true

    # Down arrow - should cancel gg and move down
    let downKey = toSpecialKeyCombo(skDown)
    let result = handleReferencesModeKey(state, 10, downKey)

    check state.waitingForG == false
    check result.kind == rvrHandled
    check state.selectedIndex == 1

suite "references_handler: G moves to last":
  test "G selects the last item":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 30:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('G')

    let result = handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 29
