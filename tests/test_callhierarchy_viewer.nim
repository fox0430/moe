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

import std/[unittest, options, os, strutils]

import ../src/moepkg/buffer
import ../src/moepkg/lsp/protocol/types as lspTypes
import ../src/moepkg/callhierarchy_viewer

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

suite "CallHierarchyViewer - newCallHierarchyViewerState":
  test "Create state with chvkPrepare":
    let items = @[makeCallHierarchyItem("foo", "file:///test.nim", 0, 0)]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    check state.items.len == 1
    check state.selectedIndex == 0
    check state.viewKind == chvkPrepare
    check state.title == "Call Hierarchy"

  test "Create state with chvkIncoming":
    let items = @[makeCallHierarchyItem("bar", "file:///test.nim", 10, 5)]
    let state = newCallHierarchyViewerState(items, chvkIncoming)

    check state.viewKind == chvkIncoming
    check state.title == "Incoming Calls"

  test "Create state with chvkOutgoing":
    let items = @[makeCallHierarchyItem("baz", "file:///test.nim", 20, 0)]
    let state = newCallHierarchyViewerState(items, chvkOutgoing)

    check state.viewKind == chvkOutgoing
    check state.title == "Outgoing Calls"

  test "Create state with empty items":
    let items: seq[lspTypes.CallHierarchyItem] = @[]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    check state.items.len == 0
    check state.selectedIndex == 0

suite "CallHierarchyViewer - itemCount":
  test "Get item count with multiple items":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
      makeCallHierarchyItem("baz", "file:///test.nim", 20, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    check state.itemCount == 3

  test "Get item count with empty items":
    let items: seq[lspTypes.CallHierarchyItem] = @[]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    check state.itemCount == 0

suite "CallHierarchyViewer - getItem":
  test "Get item at valid index":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    let item = state.getItem(1)
    check item.isSome
    check item.get.name == "bar"

  test "Get item at negative index returns none":
    let items = @[makeCallHierarchyItem("foo", "file:///test.nim", 0, 0)]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    let item = state.getItem(-1)
    check item.isNone

  test "Get item at out of bounds index returns none":
    let items = @[makeCallHierarchyItem("foo", "file:///test.nim", 0, 0)]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    let item = state.getItem(5)
    check item.isNone

suite "CallHierarchyViewer - getSelectedItem":
  test "Get selected item":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    let item = state.getSelectedItem()
    check item.isSome
    check item.get.name == "foo"

  test "Get selected item from empty state returns none":
    let items: seq[lspTypes.CallHierarchyItem] = @[]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    let item = state.getSelectedItem()
    check item.isNone

suite "CallHierarchyViewer - formatLine":
  test "Format line without detail":
    let item = makeCallHierarchyItem("myFunc", "file:///path/to/file.nim", 9, 4)
    let line = formatLine(item)

    check line == "myFunc (/path/to/file.nim:10:5)"

  test "Format line with detail":
    let item = makeCallHierarchyItem(
      "myFunc", "file:///path/to/file.nim", 9, 4, some("proc(a: int): string")
    )
    let line = formatLine(item)

    check line == "myFunc proc(a: int): string (/path/to/file.nim:10:5)"

  test "Format line with non-file URI":
    let item = makeCallHierarchyItem("myFunc", "untitled:Untitled-1", 0, 0)
    let line = formatLine(item)

    check line == "myFunc (untitled:Untitled-1:1:1)"

  test "Format line converts UTF-16 offset to rune column via lineText":
    # 2 CJK runes (each 1 UTF-16 code unit in the BMP) followed by `foo`;
    # the LSP-style UTF-16 offset 2 lands on the 'f' of `foo`, which is
    # rune column 2 (0-based) / 3 (1-based).
    let item = makeCallHierarchyItem("foo", "file:///cjk.nim", 0, 2)
    let line = formatLine(item, "あいfoo")

    check line == "foo (/cjk.nim:1:3)"

  test "Format line with supplementary-plane rune (2 UTF-16 units per rune)":
    # A single non-BMP rune (U+1F600) counts as 2 UTF-16 code units. The
    # LSP offset 2 sits immediately after it, at rune column 1 (0-based) /
    # 2 (1-based).
    let item = makeCallHierarchyItem("foo", "file:///emoji.nim", 0, 2)
    let line = formatLine(item, "\u{1F600}foo")

    check line == "foo (/emoji.nim:1:2)"

  test "Format line with empty lineText falls back to raw UTF-16 offset":
    let item = makeCallHierarchyItem("foo", "file:///test.nim", 0, 7)
    let line = formatLine(item, "")

    check line == "foo (/test.nim:1:8)"

suite "CallHierarchyViewer - createCallHierarchyTextBuffer CJK":
  test "Display column is rune-based when the target file has CJK":
    # Write a real file so createCallHierarchyTextBuffer's per-file cache can
    # read it; the LSP UTF-16 offset 2 should land on rune column 3 (1-based).
    let tmpPath = getTempDir() / "moe_callhierarchy_cjk_test.nim"
    writeFile(tmpPath, "あいfoo\n")
    defer:
      removeFile(tmpPath)

    let uri = "file://" & tmpPath
    let items = @[makeCallHierarchyItem("foo", uri, 0, 2)]
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    let tb = state.createCallHierarchyTextBuffer()

    var body = ""
    for i in 0 ..< tb.len:
      if i > 0:
        body.add('\n')
      body.add(tb.getLine(i))
    let bodyLines = body.splitLines()
    check bodyLines.len == 2
    check bodyLines[1] == "foo (" & tmpPath & ":1:3)"

suite "CallHierarchyViewer - getItem + formatLine":
  test "Get formatted line at valid index":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 5),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    check state.getItem(1).get.formatLine == "bar (/test.nim:11:6)"

suite "CallHierarchyViewer - moveUp":
  test "Move up from middle":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
      makeCallHierarchyItem("baz", "file:///test.nim", 20, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 2

    state.moveUp()

    check state.selectedIndex == 1

  test "Move up from first item does nothing":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    state.moveUp()

    check state.selectedIndex == 0

suite "CallHierarchyViewer - moveDown":
  test "Move down from first":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
      makeCallHierarchyItem("baz", "file:///test.nim", 20, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    state.moveDown()

    check state.selectedIndex == 1

  test "Move down from last item does nothing":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 1

    state.moveDown()

    check state.selectedIndex == 1

suite "CallHierarchyViewer - moveToFirst":
  test "Move to first from middle":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
      makeCallHierarchyItem("baz", "file:///test.nim", 20, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 2

    state.moveToFirst()

    check state.selectedIndex == 0

  test "Move to first when already at first":
    let items = @[makeCallHierarchyItem("foo", "file:///test.nim", 0, 0)]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    state.moveToFirst()

    check state.selectedIndex == 0

suite "CallHierarchyViewer - moveToLast":
  test "Move to last from first":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
      makeCallHierarchyItem("baz", "file:///test.nim", 20, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    state.moveToLast()

    check state.selectedIndex == 2

  test "Move to last with empty items":
    let items: seq[lspTypes.CallHierarchyItem] = @[]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    state.moveToLast()

    check state.selectedIndex == 0

  test "Move to last when already at last":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 1

    state.moveToLast()

    check state.selectedIndex == 1

suite "CallHierarchyViewer - halfPageUp":
  test "Half page up from middle":
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 15

    state.halfPageUp(10)

    check state.selectedIndex == 10

  test "Half page up near top":
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 2

    state.halfPageUp(10)

    check state.selectedIndex == 0

  test "Half page up at top does nothing":
    let items = @[
      makeCallHierarchyItem("foo", "file:///test.nim", 0, 0),
      makeCallHierarchyItem("bar", "file:///test.nim", 10, 0),
    ]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    state.halfPageUp(10)

    check state.selectedIndex == 0

suite "CallHierarchyViewer - halfPageDown":
  test "Half page down from middle":
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 5

    state.halfPageDown(10)

    check state.selectedIndex == 10

  test "Half page down near bottom":
    var items: seq[lspTypes.CallHierarchyItem] = @[]
    for i in 0 ..< 20:
      items.add(makeCallHierarchyItem("func" & $i, "file:///test.nim", i, 0))
    let state = newCallHierarchyViewerState(items, chvkPrepare)
    state.selectedIndex = 17

    state.halfPageDown(10)

    check state.selectedIndex == 19

  test "Half page down with empty items":
    let items: seq[lspTypes.CallHierarchyItem] = @[]
    let state = newCallHierarchyViewerState(items, chvkPrepare)

    state.halfPageDown(10)

    check state.selectedIndex == 0
