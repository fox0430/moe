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
import ../src/moepkg/helpviewer

suite "HelpViewer - State creation":
  test "newHelpViewerState creates state with lines":
    let state = newHelpViewerState()

    check state.lines.len > 0
    check state.selectedIndex == 0
    check state.topLine == 0
    check state.searchQuery == ""

  test "lineCount returns correct count":
    let state = newHelpViewerState()

    check state.lineCount == state.lines.len
    check state.lineCount > 0

suite "HelpViewer - Line access":
  test "getLine returns line at valid index":
    let state = newHelpViewerState()

    let line = state.getLine(0)
    check line == state.lines[0]

  test "getLine returns empty string for negative index":
    let state = newHelpViewerState()

    check state.getLine(-1) == ""

  test "getLine returns empty string for out of range index":
    let state = newHelpViewerState()

    check state.getLine(state.lines.len) == ""
    check state.getLine(state.lines.len + 100) == ""

suite "HelpViewer - Navigation":
  test "moveUp decreases selectedIndex":
    let state = newHelpViewerState()
    state.selectedIndex = 5

    state.moveUp()
    check state.selectedIndex == 4

    state.moveUp()
    check state.selectedIndex == 3

  test "moveUp does nothing at index 0":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    state.moveUp()
    check state.selectedIndex == 0

  test "moveDown increases selectedIndex":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    state.moveDown()
    check state.selectedIndex == 1

    state.moveDown()
    check state.selectedIndex == 2

  test "moveDown does nothing at last index":
    let state = newHelpViewerState()
    state.selectedIndex = state.lines.high

    state.moveDown()
    check state.selectedIndex == state.lines.high

  test "moveToFirst sets selectedIndex to 0":
    let state = newHelpViewerState()
    state.selectedIndex = 10

    state.moveToFirst()
    check state.selectedIndex == 0

  test "moveToLast sets selectedIndex to last":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    state.moveToLast()
    check state.selectedIndex == state.lines.high

suite "HelpViewer - Half page navigation":
  test "halfPageUp moves up by half viewport":
    let state = newHelpViewerState()
    state.selectedIndex = 20

    state.halfPageUp(10)
    check state.selectedIndex == 15

  test "halfPageUp clamps to 0":
    let state = newHelpViewerState()
    state.selectedIndex = 2

    state.halfPageUp(10)
    check state.selectedIndex == 0

  test "halfPageDown moves down by half viewport":
    let state = newHelpViewerState()
    state.selectedIndex = 5

    state.halfPageDown(10)
    check state.selectedIndex == 10

  test "halfPageDown clamps to last line":
    let state = newHelpViewerState()
    state.selectedIndex = state.lines.high - 2

    state.halfPageDown(10)
    check state.selectedIndex == state.lines.high

suite "HelpViewer - Viewport":
  test "ensureSelectedVisible scrolls up when selection above viewport":
    let state = newHelpViewerState()
    state.topLine = 10
    state.selectedIndex = 5

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible scrolls down when selection below viewport":
    let state = newHelpViewerState()
    state.topLine = 0
    state.selectedIndex = 15

    state.ensureSelectedVisible(10)
    check state.topLine == 6

  test "ensureSelectedVisible does not change when selection is visible":
    let state = newHelpViewerState()
    state.topLine = 5
    state.selectedIndex = 10

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible ensures topLine is not negative":
    let state = newHelpViewerState()
    state.topLine = -5
    state.selectedIndex = 0

    state.ensureSelectedVisible(10)
    check state.topLine == 0

  test "ensureSelectedVisible with selection at viewport boundary":
    let state = newHelpViewerState()
    state.topLine = 5
    state.selectedIndex = 14

    state.ensureSelectedVisible(10)
    check state.topLine == 5

  test "ensureSelectedVisible when selection just outside viewport":
    let state = newHelpViewerState()
    state.topLine = 5
    state.selectedIndex = 15

    state.ensureSelectedVisible(10)
    check state.topLine == 6

suite "HelpViewer - Search query":
  test "setSearchQuery sets the query":
    let state = newHelpViewerState()

    state.setSearchQuery("test")
    check state.searchQuery == "test"

  test "clearSearch clears the query":
    let state = newHelpViewerState()
    state.setSearchQuery("test")

    state.clearSearch()
    check state.searchQuery == ""

  test "hasSearchQuery returns true when query exists":
    let state = newHelpViewerState()
    state.setSearchQuery("test")

    check state.hasSearchQuery == true

  test "hasSearchQuery returns false when query is empty":
    let state = newHelpViewerState()

    check state.hasSearchQuery == false

  test "hasSearchQuery returns false after clearSearch":
    let state = newHelpViewerState()
    state.setSearchQuery("test")
    state.clearSearch()

    check state.hasSearchQuery == false

suite "HelpViewer - Line matching":
  test "isLineMatched returns true for matching line":
    let state = newHelpViewerState()
    state.setSearchQuery("Normal mode")

    # Find a line containing "Normal mode"
    var foundIndex = -1
    for i, line in state.lines:
      if "Normal mode" in line:
        foundIndex = i
        break

    check foundIndex >= 0
    check state.isLineMatched(foundIndex) == true

  test "isLineMatched is case insensitive":
    let state = newHelpViewerState()
    state.setSearchQuery("normal MODE")

    var foundIndex = -1
    for i, line in state.lines:
      if "Normal mode" in line:
        foundIndex = i
        break

    check foundIndex >= 0
    check state.isLineMatched(foundIndex) == true

  test "isLineMatched returns false for non-matching line":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123")

    check state.isLineMatched(0) == false

  test "isLineMatched returns false when no search query":
    let state = newHelpViewerState()

    check state.isLineMatched(0) == false

  test "isLineMatched returns false for negative index":
    let state = newHelpViewerState()
    state.setSearchQuery("test")

    check state.isLineMatched(-1) == false

  test "isLineMatched returns false for out of range index":
    let state = newHelpViewerState()
    state.setSearchQuery("test")

    check state.isLineMatched(state.lines.len) == false

suite "HelpViewer - Search forward":
  test "searchForward finds next matching line":
    let state = newHelpViewerState()
    state.setSearchQuery(":w")
    state.selectedIndex = 0

    let result = state.searchForward()
    check result.isSome
    check state.selectedIndex > 0
    check ":w" in state.lines[state.selectedIndex].toLowerAscii or
      ":W" in state.lines[state.selectedIndex]

  test "searchForward wraps around to beginning":
    let state = newHelpViewerState()
    state.setSearchQuery("Exiting")

    # Set selectedIndex to after the "Exiting" section
    state.selectedIndex = state.lines.high

    let result = state.searchForward()
    check result.isSome
    # Should wrap around and find "Exiting" near the beginning
    check state.selectedIndex < state.lines.high

  test "searchForward returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456")
    state.selectedIndex = 0

    let result = state.searchForward()
    check result.isNone

  test "searchForward returns none when no search query":
    let state = newHelpViewerState()
    state.selectedIndex = 0

    let result = state.searchForward()
    check result.isNone

suite "HelpViewer - Search backward":
  test "searchBackward finds previous matching line":
    let state = newHelpViewerState()
    state.setSearchQuery("mode")
    state.selectedIndex = state.lines.high

    let result = state.searchBackward()
    check result.isSome
    check state.selectedIndex < state.lines.high

  test "searchBackward wraps around to end":
    let state = newHelpViewerState()
    state.setSearchQuery("jumps")
    state.selectedIndex = 0

    let result = state.searchBackward()
    check result.isSome
    # Should wrap around and find "jumps" near the end
    check state.selectedIndex > 0

  test "searchBackward returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456")
    state.selectedIndex = 10

    let result = state.searchBackward()
    check result.isNone

  test "searchBackward returns none when no search query":
    let state = newHelpViewerState()
    state.selectedIndex = 10

    let result = state.searchBackward()
    check result.isNone

suite "HelpViewer - Search first":
  test "searchFirst finds first matching line from beginning":
    let state = newHelpViewerState()
    state.setSearchQuery("Exiting")
    state.selectedIndex = state.lines.high

    let result = state.searchFirst()
    check result.isSome
    # Should find "Exiting" near the beginning
    check state.selectedIndex < state.lines.high

  test "searchFirst returns none when no match":
    let state = newHelpViewerState()
    state.setSearchQuery("xyznonexistent123456")
    state.selectedIndex = 0

    let result = state.searchFirst()
    check result.isNone

  test "searchFirst returns none when no search query":
    let state = newHelpViewerState()

    let result = state.searchFirst()
    check result.isNone

  test "searchFirst always starts from line 0":
    let state = newHelpViewerState()
    state.setSearchQuery("# Exiting")
    state.selectedIndex = 50

    let result = state.searchFirst()
    check result.isSome
    # The first match should be the "# Exiting" header near the beginning
    check state.selectedIndex < 10
