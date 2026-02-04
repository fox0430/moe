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

suite "ReferencesHandler - Handler creation":
  test "newReferencesHandler creates handler":
    let handler = newReferencesHandler()

    check handler != nil
    check handler.waitingForG == false

suite "ReferencesHandler - Navigation keys":
  test "j key moves down":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    let keyCombo = toKeyCombo('j')

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

  test "k key moves up":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 2
    let keyCombo = toKeyCombo('k')

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

  test "Down arrow key moves down":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    let keyCombo = toSpecialKeyCombo(skDown)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

  test "Up arrow key moves up":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1
    let keyCombo = toSpecialKeyCombo(skUp)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 0

suite "ReferencesHandler - Go to first/last":
  test "gg moves to first item":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 2

    # First g
    let firstG = toKeyCombo('g')
    let result1 = handler.handleReferencesModeKey(state, 10, firstG)

    check result1.kind == rvrHandled
    check handler.waitingForG == true
    check state.selectedIndex == 2

    # Second g
    let secondG = toKeyCombo('g')
    let result2 = handler.handleReferencesModeKey(state, 10, secondG)

    check result2.kind == rvrHandled
    check handler.waitingForG == false
    check state.selectedIndex == 0

  test "G moves to last item":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('G')

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 2

  test "g followed by non-g cancels gg sequence":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 2

    # First g
    let firstG = toKeyCombo('g')
    discard handler.handleReferencesModeKey(state, 10, firstG)

    check handler.waitingForG == true

    # j instead of g - should cancel gg and move down
    let jKey = toKeyCombo('j')
    discard handler.handleReferencesModeKey(state, 10, jKey)

    check handler.waitingForG == false
    # The j key should be processed normally after gg cancellation
    # Position doesn't change because we're at last index (2) and moveDown does nothing

suite "ReferencesHandler - Half page navigation":
  test "Ctrl+d moves half page down":
    let handler = newReferencesHandler()
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 5
    let keyCombo = toKeyCombo('d', ctrl = true)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 10

  test "Ctrl+u moves half page up":
    let handler = newReferencesHandler()
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 15
    let keyCombo = toKeyCombo('u', ctrl = true)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 10

suite "ReferencesHandler - Quit commands":
  test "q key returns quit result":
    let handler = newReferencesHandler()
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toKeyCombo('q')

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrQuit

  test "Escape key returns quit result":
    let handler = newReferencesHandler()
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toSpecialKeyCombo(skEscape)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrQuit

suite "ReferencesHandler - Enter command mode":
  test ": key returns enter command result":
    let handler = newReferencesHandler()
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toKeyCombo(':')

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrEnterCommand

suite "ReferencesHandler - Jump to reference":
  test "Enter key returns jump result with selected item":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/first.nim", line: 10, column: 5, text: "first"),
        ReferenceItem(path: "/second.nim", line: 20, column: 10, text: "second"),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1
    let keyCombo = toSpecialKeyCombo(skEnter)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrJumpToReference
    check result.targetItem.path == "/second.nim"
    check result.targetItem.line == 20
    check result.targetItem.column == 10
    check result.targetItem.text == "second"

  test "Enter key on empty state returns error":
    let handler = newReferencesHandler()
    let state = newReferencesViewerState(@[])
    let keyCombo = toSpecialKeyCombo(skEnter)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrError
    check result.errorMessage == "No reference selected"

suite "ReferencesHandler - Unhandled keys":
  test "unhandled key returns unhandled result":
    let handler = newReferencesHandler()
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toKeyCombo('x') # x is not a handled key

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrUnhandled

  test "unhandled special key returns unhandled result":
    let handler = newReferencesHandler()
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    let keyCombo = toSpecialKeyCombo(skPageUp) # PageUp is not handled

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrUnhandled

suite "ReferencesHandler - Viewport scrolling":
  test "navigation ensures selected item is visible":
    let handler = newReferencesHandler()
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 30:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.topLine = 0
    state.selectedIndex = 0

    # Move down many times to go beyond viewport
    for _ in 0 ..< 15:
      let keyCombo = toKeyCombo('j')
      discard handler.handleReferencesModeKey(state, 10, keyCombo)

    check state.selectedIndex == 15
    # topLine should have scrolled to keep selection visible
    check state.topLine > 0
    check state.selectedIndex >= state.topLine
    check state.selectedIndex < state.topLine + 10

suite "ReferencesHandler - Boundary conditions":
  test "k at first item stays at first":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('k')

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 0

  test "j at last item stays at last":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1
    let keyCombo = toKeyCombo('j')

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

  test "Up arrow at first item stays at first":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0
    let keyCombo = toSpecialKeyCombo(skUp)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 0

  test "Down arrow at last item stays at last":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1
    let keyCombo = toSpecialKeyCombo(skDown)

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 1

suite "ReferencesHandler - gg with special key":
  test "g followed by Escape cancels gg and quits":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1

    # First g
    let firstG = toKeyCombo('g')
    discard handler.handleReferencesModeKey(state, 10, firstG)

    check handler.waitingForG == true

    # Escape - should cancel gg and quit
    let escKey = toSpecialKeyCombo(skEscape)
    let result = handler.handleReferencesModeKey(state, 10, escKey)

    check handler.waitingForG == false
    check result.kind == rvrQuit
    check state.selectedIndex == 1 # Position unchanged

  test "g followed by Enter cancels gg and jumps":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 1, column: 2, text: "target"),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1

    # First g
    let firstG = toKeyCombo('g')
    discard handler.handleReferencesModeKey(state, 10, firstG)

    check handler.waitingForG == true

    # Enter - should cancel gg and jump to reference
    let enterKey = toSpecialKeyCombo(skEnter)
    let result = handler.handleReferencesModeKey(state, 10, enterKey)

    check handler.waitingForG == false
    check result.kind == rvrJumpToReference
    check result.targetItem.path == "/b.nim"

  test "g followed by Down cancels gg and moves down":
    let handler = newReferencesHandler()
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0

    # First g
    let firstG = toKeyCombo('g')
    discard handler.handleReferencesModeKey(state, 10, firstG)

    check handler.waitingForG == true

    # Down arrow - should cancel gg and move down
    let downKey = toSpecialKeyCombo(skDown)
    let result = handler.handleReferencesModeKey(state, 10, downKey)

    check handler.waitingForG == false
    check result.kind == rvrHandled
    check state.selectedIndex == 1

suite "ReferencesHandler - G with viewport":
  test "G scrolls viewport to show last item":
    let handler = newReferencesHandler()
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 30:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.topLine = 0
    state.selectedIndex = 0
    let keyCombo = toKeyCombo('G')

    let result = handler.handleReferencesModeKey(state, 10, keyCombo)

    check result.kind == rvrHandled
    check state.selectedIndex == 29
    # topLine should have scrolled to show last item
    check state.topLine > 0
    check state.selectedIndex >= state.topLine
    check state.selectedIndex < state.topLine + 10
