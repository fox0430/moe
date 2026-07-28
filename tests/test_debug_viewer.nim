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

import std/[unittest, options, strutils]

import ../src/moepkg/modes
import ../src/moepkg/debug_viewer {.all.}

suite "debug_viewer - DebugViewerState initialization":
  test "newDebugViewerState creates empty state":
    let state = newDebugViewerState()
    check state.items.len == 0
    check state.selectedIndex == 0

suite "debug_viewer - Format helpers":
  test "formatBool true":
    check formatBool(true) == "true"

  test "formatBool false":
    check formatBool(false) == "false"

  test "formatOption with some value":
    check formatOption(some(42)) == "42"

  test "formatOption with none":
    check formatOption(none(int)) == "none"

  test "formatOption with some string":
    check formatOption(some("hello")) == "hello"

suite "debug_viewer - Section and field helpers":
  test "addSection adds empty line and title":
    var lines: seq[string] = @[]
    lines.addSection("TestSection")
    check lines.len == 2
    check lines[0] == ""
    check lines[1] == "-- TestSection --"

  test "addField adds padded field line":
    var lines: seq[string] = @[]
    lines.addField("name", "value")
    check lines.len == 1
    check "name" in lines[0]
    check "value" in lines[0]
    check " : " in lines[0]

  test "addField pads name to 24 characters":
    var lines: seq[string] = @[]
    lines.addField("x", "val")
    # Format: "  " + name.alignLeft(24) + " : " + value
    check lines[0].startsWith("  x")
    check lines[0].len >= 24 + 2 + 3 + 3 # 2 leading + 24 name + " : " + "val"

suite "debug_viewer - Navigation":
  test "moveUp from top does nothing":
    let state = newDebugViewerState()
    state.items = @["a", "b", "c"]
    state.selectedIndex = 0
    state.moveUp()
    check state.selectedIndex == 0

  test "moveUp decrements selectedIndex":
    let state = newDebugViewerState()
    state.items = @["a", "b", "c"]
    state.selectedIndex = 2
    state.moveUp()
    check state.selectedIndex == 1

  test "moveDown increments selectedIndex":
    let state = newDebugViewerState()
    state.items = @["a", "b", "c"]
    state.selectedIndex = 0
    state.moveDown()
    check state.selectedIndex == 1

  test "moveDown at bottom does nothing":
    let state = newDebugViewerState()
    state.items = @["a", "b", "c"]
    state.selectedIndex = 2
    state.moveDown()
    check state.selectedIndex == 2

  test "moveToFirst resets to zero":
    let state = newDebugViewerState()
    state.items = @["a", "b", "c", "d", "e"]
    state.selectedIndex = 4
    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToLast goes to last line":
    let state = newDebugViewerState()
    state.items = @["a", "b", "c", "d", "e"]
    state.moveToLast()
    check state.selectedIndex == 4

  test "pageUp moves up by page size":
    let state = newDebugViewerState()
    state.items = @["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
    state.selectedIndex = 8
    state.pageUp(5)
    check state.selectedIndex == 4

  test "pageDown moves down by page size":
    let state = newDebugViewerState()
    state.items = @["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
    state.selectedIndex = 0
    state.pageDown(5)
    check state.selectedIndex == 4

suite "debug_viewer - generateEditorStateInfo":
  test "generates editor state section":
    var lines: seq[string] = @[]
    generateEditorStateInfo(
      lines,
      mode = EditorMode.Normal,
      previousMode = EditorMode.Insert,
      cursorLine = 10,
      cursorColumn = 5,
      commandText = ":w",
      statusMessage = "saved",
    )
    check lines.len > 0
    var found = false
    for line in lines:
      if "EditorState" in line:
        found = true
        break
    check found

  test "disabled generates nothing":
    var lines: seq[string] = @[]
    generateEditorStateInfo(
      lines,
      mode = EditorMode.Normal,
      previousMode = EditorMode.Insert,
      cursorLine = 0,
      cursorColumn = 0,
      commandText = "",
      statusMessage = "",
      enabled = false,
    )
    check lines.len == 0

suite "debug_viewer - generateSearchInfo":
  test "generates search section":
    var lines: seq[string] = @[]
    generateSearchInfo(
      lines,
      searchText = "foo",
      lastSearchText = "bar",
      searchDirection = "forward",
      historyLen = 5,
      ignorecase = true,
      smartcase = false,
      incsearch = true,
      hlsearch = true,
    )
    check lines.len > 0
    var foundSection = false
    for line in lines:
      if "SearchState" in line:
        foundSection = true
        break
    check foundSection

suite "debug_viewer - generateWindowInfo":
  test "generates window section":
    var lines: seq[string] = @[]
    generateWindowInfo(
      lines,
      windowIndex = 0,
      isActive = true,
      bufferIndex = 0,
      viewportX = 0,
      viewportY = 0,
      viewportWidth = 80,
      viewportHeight = 24,
      viewportTopLine = 0,
      viewportLeftColumn = 0,
      cursorLine = 10,
      cursorColumn = 5,
    )
    check lines.len > 0
    var foundSection = false
    for line in lines:
      if "Window 0" in line:
        foundSection = true
        break
    check foundSection

  test "disabled generates nothing":
    var lines: seq[string] = @[]
    generateWindowInfo(
      lines,
      windowIndex = 0,
      isActive = true,
      bufferIndex = 0,
      viewportX = 0,
      viewportY = 0,
      viewportWidth = 80,
      viewportHeight = 24,
      viewportTopLine = 0,
      viewportLeftColumn = 0,
      cursorLine = 0,
      cursorColumn = 0,
      enabled = false,
    )
    check lines.len == 0

suite "debug_viewer - createDebugTextBuffer":
  test "creates buffer from debug lines":
    let state = newDebugViewerState()
    state.items = @["line 1", "line 2", "line 3"]
    let buf = createDebugTextBuffer(state)
    check buf.readOnly == true

  test "creates buffer from empty lines":
    let state = newDebugViewerState()
    let buf = createDebugTextBuffer(state)
    check buf.readOnly == true
