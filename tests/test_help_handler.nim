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

## Tests for help_handler.nim
## This module tests the Help Viewer mode command handler functionality.

import std/unittest

import ../src/moepkg/[key_bindings, help_viewer]
import ../src/moepkg/command_handlers/help_handler

const TestViewportHeight = 24

proc charKey(c: string, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a character key combo
  KeyCombo(isSpecial: false, char: c, modifiers: mods)

proc specialKey(sk: SpecialKey, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a special key combo
  KeyCombo(isSpecial: true, special: sk, fnNum: 0, modifiers: mods)

suite "help_handler: HelpViewerState key-sequence flags":
  test "fresh HelpViewerState has key-sequence flags reset":
    let helpState = newHelpViewerState()
    check helpState.waitingForG == false
    check helpState.lastKeyWasEscape == false

suite "help_handler: handleHelpViewerModeKey - Movement keys":
  test "j key moves down":
    let helpState = newHelpViewerState()
    check helpState.selectedIndex == 0

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("j"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 1

  test "k key moves up":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 5

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("k"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 4

  test "k key does not move above first line":
    let helpState = newHelpViewerState()
    check helpState.selectedIndex == 0

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("k"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 0

  test "j key does not move below last line":
    let helpState = newHelpViewerState()
    helpState.moveToLast()
    let lastIndex = helpState.selectedIndex

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("j"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == lastIndex

  test "Down arrow moves down":
    let helpState = newHelpViewerState()
    check helpState.selectedIndex == 0

    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skDown))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 1

  test "Up arrow moves up":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 5

    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skUp))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 4

suite "help_handler: handleHelpViewerModeKey - gg and G commands":
  test "gg moves to first line":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 50

    # First 'g' - starts waiting
    let result1 = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("g"))
    check result1.kind == hvrHandled
    check helpState.waitingForG == true
    check helpState.selectedIndex == 50 # Not moved yet

    # Second 'g' - executes gg
    let result2 = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("g"))
    check result2.kind == hvrHandled
    check helpState.waitingForG == false
    check helpState.selectedIndex == 0

  test "g followed by non-g cancels":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 50

    # First 'g' - starts waiting
    let result1 = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("g"))
    check result1.kind == hvrHandled
    check helpState.waitingForG == true

    # Non-'g' key - cancels waiting
    let result2 = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("j"))
    check result2.kind == hvrUnhandled
    check helpState.waitingForG == false
    check helpState.selectedIndex == 50 # Position unchanged

  test "g followed by special key cancels":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 50

    # First 'g' - starts waiting
    let result1 = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("g"))
    check result1.kind == hvrHandled
    check helpState.waitingForG == true

    # Special key - cancels waiting
    let result2 =
      handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skDown))
    check result2.kind == hvrUnhandled
    check helpState.waitingForG == false
    check helpState.selectedIndex == 50 # Position unchanged

  test "G moves to last line":
    let helpState = newHelpViewerState()
    check helpState.selectedIndex == 0

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("G"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == helpState.lines.high

suite "help_handler: handleHelpViewerModeKey - Half page movement":
  test "Ctrl+d moves half page down":
    let helpState = newHelpViewerState()
    check helpState.selectedIndex == 0

    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("d", {kmCtrl}))

    check result.kind == hvrHandled
    check helpState.selectedIndex == TestViewportHeight div 2

  test "Ctrl+u moves half page up":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 50

    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("u", {kmCtrl}))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 50 - (TestViewportHeight div 2)

  test "Ctrl+u does not go below 0":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 5

    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("u", {kmCtrl}))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 0

  test "Ctrl+d does not exceed last line":
    let helpState = newHelpViewerState()
    # Move near end of document
    helpState.moveToLast()
    let lastIndex = helpState.selectedIndex
    helpState.selectedIndex = lastIndex - 3 # A few lines from end

    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("d", {kmCtrl}))

    check result.kind == hvrHandled
    check helpState.selectedIndex == lastIndex # Clamped to last line

suite "help_handler: handleHelpViewerModeKey - Mode transitions":
  test ": enters command mode":
    let helpState = newHelpViewerState()

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey(":"))

    check result.kind == hvrEnterCommand

  test "/ enters search mode":
    let helpState = newHelpViewerState()

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("/"))

    check result.kind == hvrEnterSearch

  test "? enters backward search mode":
    let helpState = newHelpViewerState()

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("?"))

    check result.kind == hvrEnterSearchBackward

suite "help_handler: handleHelpViewerModeKey - Search navigation":
  test "n searches forward":
    let helpState = newHelpViewerState()
    helpState.setSearchQuery("Visual")
    check helpState.selectedIndex == 0

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("n"))

    # A match jump requests a highlight re-enable (like Vim's n after :noh).
    check result.kind == hvrRepeatSearch
    # Should find the first occurrence of "Visual" after line 0
    check helpState.selectedIndex > 0
    check helpState.isLineMatched(helpState.selectedIndex)

  test "N searches backward":
    let helpState = newHelpViewerState()
    helpState.setSearchQuery("Normal")
    # Move to end of document
    helpState.moveToLast()
    let lastIndex = helpState.selectedIndex

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("N"))

    # "Normal" has matches, so the backward jump succeeds and requests a
    # highlight re-enable; the selection moves before the starting position.
    check result.kind == hvrRepeatSearch
    check helpState.selectedIndex < lastIndex

  test "n with no search query does not crash":
    let helpState = newHelpViewerState()
    # No search query set

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("n"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 0

  test "N with no search query does not crash":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 50
    # No search query set

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("N"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 50 # Position unchanged

suite "help_handler: handleHelpViewerModeKey - Section navigation":
  test "} jumps to the next top-level section":
    let helpState = newHelpViewerState()
    check helpState.selectedIndex == 0

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("}"))

    check result.kind == hvrHandled
    check helpState.selectedIndex > 0
    check helpState.lines[helpState.selectedIndex].len >= 2
    check helpState.lines[helpState.selectedIndex][0 .. 1] == "# "

  test "{ jumps to the previous top-level section":
    let helpState = newHelpViewerState()
    helpState.moveToLast()
    let startIdx = helpState.selectedIndex

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("{"))

    check result.kind == hvrHandled
    check helpState.selectedIndex < startIdx
    check helpState.lines[helpState.selectedIndex].len >= 2
    check helpState.lines[helpState.selectedIndex][0 .. 1] == "# "

  test "} at last section stays on last section":
    let helpState = newHelpViewerState()

    # Find the last top-level "# " line.
    var lastSectionIdx = -1
    for i, line in helpState.lines:
      if line.len >= 2 and line[0 .. 1] == "# ":
        lastSectionIdx = i
    check lastSectionIdx >= 0

    helpState.selectedIndex = lastSectionIdx
    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("}"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == lastSectionIdx

  test "{ at first section stays on first section":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 0

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("{"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 0

  test "} adjusts topLine to keep target visible":
    let helpState = newHelpViewerState()
    helpState.selectedIndex = 0
    helpState.topLine = 0

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("}"))

    check result.kind == hvrHandled
    check helpState.topLine <= helpState.selectedIndex
    check helpState.topLine + TestViewportHeight > helpState.selectedIndex

suite "help_handler: handleHelpViewerModeKey - Scroll adjustment":
  test "Moving down adjusts topLine when cursor goes below viewport":
    let helpState = newHelpViewerState()
    # Set position at the bottom edge of viewport
    helpState.selectedIndex = TestViewportHeight - 1
    helpState.topLine = 0

    # Move down should trigger scroll adjustment
    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("j"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == TestViewportHeight
    check helpState.topLine == 1 # topLine adjusted to keep cursor visible

  test "Moving up adjusts topLine when cursor goes above viewport":
    let helpState = newHelpViewerState()
    # Set position at top of viewport (which is scrolled down)
    helpState.selectedIndex = 30
    helpState.topLine = 30

    # Move up should trigger scroll adjustment
    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("k"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == 29
    check helpState.topLine == 29 # topLine adjusted to keep cursor visible

  test "G command scrolls to make last line visible":
    let helpState = newHelpViewerState()
    helpState.topLine = 0

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("G"))

    check result.kind == hvrHandled
    check helpState.selectedIndex == helpState.lines.high
    # topLine should be adjusted so selected line is visible
    check helpState.topLine <= helpState.selectedIndex
    check helpState.topLine + TestViewportHeight > helpState.selectedIndex

suite "help_handler: handleHelpViewerModeKey - Double-Escape clears search highlight":
  test "First Escape returns handled and marks lastKeyWasEscape":
    let helpState = newHelpViewerState()

    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skEscape))

    check result.kind == hvrHandled
    check helpState.lastKeyWasEscape == true

  test "Second Escape returns clearSearchHighlight":
    let helpState = newHelpViewerState()
    helpState.setSearchQuery("Visual")

    # First Escape
    discard handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skEscape))

    # Second Escape
    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skEscape))

    check result.kind == hvrClearSearchHighlight
    check helpState.lastKeyWasEscape == false
    check helpState.searchQuery == ""

  test "Escape followed by non-Escape resets lastKeyWasEscape":
    let helpState = newHelpViewerState()

    # First Escape
    discard handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skEscape))
    check helpState.lastKeyWasEscape == true

    # Non-Escape key
    discard handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("j"))
    check helpState.lastKeyWasEscape == false

  test "Double-Escape clears search query":
    let helpState = newHelpViewerState()
    helpState.setSearchQuery("Insert")
    check helpState.hasSearchQuery == true

    # Double Escape
    discard handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skEscape))
    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skEscape))

    check result.kind == hvrClearSearchHighlight
    check helpState.hasSearchQuery == false

  test "Double-Escape without active search still returns clearSearchHighlight":
    let helpState = newHelpViewerState()
    check helpState.hasSearchQuery == false

    # Double Escape
    discard handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skEscape))
    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skEscape))

    check result.kind == hvrClearSearchHighlight

suite "help_handler: handleHelpViewerModeKey - Unhandled keys":
  test "Unbound key returns unhandled":
    let helpState = newHelpViewerState()

    let result = handleHelpViewerModeKey(helpState, TestViewportHeight, charKey("z"))

    check result.kind == hvrUnhandled

  test "Unbound special key returns unhandled":
    let helpState = newHelpViewerState()

    # skHome is not handled by help viewer
    let result =
      handleHelpViewerModeKey(helpState, TestViewportHeight, specialKey(skHome))

    check result.kind == hvrUnhandled
