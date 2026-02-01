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
import ../src/moepkg/references_viewer

suite "ReferencesViewer - State creation":
  test "newReferencesViewerState creates state with items":
    let items =
      @[
        ReferenceItem(path: "/path/to/file.nim", line: 10, column: 5, text: ""),
        ReferenceItem(path: "/path/to/other.nim", line: 20, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)

    check state.items.len == 2
    check state.selectedIndex == 0
    check state.topLine == 0
    check state.title == "References"

  test "newReferencesViewerState creates empty state":
    let state = newReferencesViewerState(@[])

    check state.items.len == 0
    check state.selectedIndex == 0
    check state.topLine == 0

  test "newReferencesViewerState with custom title":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items, "Definitions")

    check state.title == "Definitions"

  test "itemCount returns correct count":
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)

    check state.itemCount == 3

  test "itemCount returns 0 for empty state":
    let state = newReferencesViewerState(@[])
    check state.itemCount == 0

suite "ReferencesViewer - Item access":
  test "getItem returns item at valid index":
    let items =
      @[
        ReferenceItem(path: "/first.nim", line: 1, column: 2, text: "first"),
        ReferenceItem(path: "/second.nim", line: 3, column: 4, text: "second"),
      ]
    let state = newReferencesViewerState(items)

    let item = state.getItem(1)
    check item.isSome
    check item.get.path == "/second.nim"
    check item.get.line == 3
    check item.get.column == 4
    check item.get.text == "second"

  test "getItem returns none for negative index":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)

    check state.getItem(-1).isNone

  test "getItem returns none for out of range index":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)

    check state.getItem(5).isNone

  test "getItem returns none for empty state":
    let state = newReferencesViewerState(@[])
    check state.getItem(0).isNone

  test "getSelectedItem returns currently selected item":
    let items =
      @[
        ReferenceItem(path: "/first.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/second.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1

    let selected = state.getSelectedItem
    check selected.isSome
    check selected.get.path == "/second.nim"

  test "getSelectedItem returns none for empty state":
    let state = newReferencesViewerState(@[])
    check state.getSelectedItem.isNone

suite "ReferencesViewer - Formatting":
  test "formatLine formats item correctly":
    let item = ReferenceItem(path: "/path/to/file.nim", line: 9, column: 4, text: "")

    let formatted = item.formatLine
    check formatted == "/path/to/file.nim 10 Line 5 Col"

  test "formatLine uses 1-indexed line and column":
    let item = ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")

    let formatted = item.formatLine
    check formatted == "/file.nim 1 Line 1 Col"

  test "getLine returns formatted line at index":
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 5, column: 10, text: ""),
        ReferenceItem(path: "/b.nim", line: 15, column: 20, text: ""),
      ]
    let state = newReferencesViewerState(items)

    check state.getLine(0) == "/a.nim 6 Line 11 Col"
    check state.getLine(1) == "/b.nim 16 Line 21 Col"

  test "getLine returns empty string for invalid index":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)

    check state.getLine(-1) == ""
    check state.getLine(5) == ""

  test "getLine returns empty string for empty state":
    let state = newReferencesViewerState(@[])
    check state.getLine(0) == ""

suite "ReferencesViewer - Navigation":
  test "moveUp decreases selectedIndex":
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 2

    state.moveUp()
    check state.selectedIndex == 1

    state.moveUp()
    check state.selectedIndex == 0

  test "moveUp does nothing at index 0":
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0

    state.moveUp()
    check state.selectedIndex == 0

  test "moveUp does nothing on empty state":
    let state = newReferencesViewerState(@[])
    state.moveUp()
    check state.selectedIndex == 0

  test "moveDown increases selectedIndex":
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0

    state.moveDown()
    check state.selectedIndex == 1

    state.moveDown()
    check state.selectedIndex == 2

  test "moveDown does nothing at last index":
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 1

    state.moveDown()
    check state.selectedIndex == 1

  test "moveDown does nothing on empty state":
    let state = newReferencesViewerState(@[])
    state.moveDown()
    check state.selectedIndex == 0

  test "moveToFirst sets selectedIndex to 0":
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 2

    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToFirst on empty state":
    let state = newReferencesViewerState(@[])
    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToLast sets selectedIndex to last":
    let items =
      @[
        ReferenceItem(path: "/a.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/b.nim", line: 0, column: 0, text: ""),
        ReferenceItem(path: "/c.nim", line: 0, column: 0, text: ""),
      ]
    let state = newReferencesViewerState(items)
    state.selectedIndex = 0

    state.moveToLast()
    check state.selectedIndex == 2

  test "moveToLast on empty state":
    let state = newReferencesViewerState(@[])
    state.moveToLast()
    check state.selectedIndex == 0

suite "ReferencesViewer - Half page navigation":
  test "halfPageUp moves up by half viewport":
    let items: seq[ReferenceItem] = @[]
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 15

    state.halfPageUp(10)
    check state.selectedIndex == 10

  test "halfPageUp clamps to 0":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 10:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 2

    state.halfPageUp(10)
    check state.selectedIndex == 0

  test "halfPageUp on empty state":
    let state = newReferencesViewerState(@[])
    state.halfPageUp(10)
    check state.selectedIndex == 0

  test "halfPageDown moves down by half viewport":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 5

    state.halfPageDown(10)
    check state.selectedIndex == 10

  test "halfPageDown clamps to last item":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 10:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.selectedIndex = 7

    state.halfPageDown(10)
    check state.selectedIndex == 9

  test "halfPageDown on empty state":
    let state = newReferencesViewerState(@[])
    state.halfPageDown(10)
    check state.selectedIndex == 0

suite "ReferencesViewer - Viewport":
  test "ensureSelectedVisible scrolls up when selection above viewport":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.topLine = 10
    state.selectedIndex = 5

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible scrolls down when selection below viewport":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.topLine = 0
    state.selectedIndex = 15

    state.ensureSelectedVisible(10)
    check state.topLine == 6

  test "ensureSelectedVisible does not change when selection is visible":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.topLine = 5
    state.selectedIndex = 10

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible ensures topLine is not negative":
    let items = @[ReferenceItem(path: "/file.nim", line: 0, column: 0, text: "")]
    let state = newReferencesViewerState(items)
    state.topLine = -5
    state.selectedIndex = 0

    state.ensureSelectedVisible(10)
    check state.topLine == 0

  test "ensureSelectedVisible with selection at viewport boundary":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.topLine = 5
    state.selectedIndex = 14

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible when selection just outside viewport":
    var itemList: seq[ReferenceItem]
    for i in 0 ..< 20:
      itemList.add ReferenceItem(
        path: "/file" & $i & ".nim", line: i, column: 0, text: ""
      )

    let state = newReferencesViewerState(itemList)
    state.topLine = 5
    state.selectedIndex = 15

    state.ensureSelectedVisible(10)
    check state.topLine == 6
