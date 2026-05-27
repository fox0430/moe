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

## Tests for recent_file_mode_handler.nim
## This module tests the Recent File mode command handler functionality.

import std/[unittest, options, strutils]

import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/recent_file_mode {.all.}
import ../src/moepkg/command_handlers/recent_file_mode_handler {.all.}

const TestViewportHeight = 24

proc charKey(c: string, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a character key combo
  KeyCombo(isSpecial: false, char: c, modifiers: mods)

proc specialKey(sk: SpecialKey, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a special key combo
  KeyCombo(isSpecial: true, special: sk, fnNum: 0, modifiers: mods)

proc createTestState(): RecentFileModeState =
  ## Create a state with test files
  let state = newRecentFileModeState()
  for i in 0 ..< 30:
    state.files.add RecentFileEntry(path: "/file" & $i & ".txt")
  state

suite "recent_file_mode_handler: newSubStateHandler":
  test "Create new handler":
    let handler = newSubStateHandler()
    check handler != nil
    check handler.waitingForG == false

suite "recent_file_mode_handler: handleRecentFileModeKey - Movement keys":
  test "j key moves down":
    let
      handler = newSubStateHandler()
      state = createTestState()
    check state.selectedIndex == 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 1

  test "k key moves up":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 5

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 4

  test "k key does not move above first line":
    let
      handler = newSubStateHandler()
      state = createTestState()
    check state.selectedIndex == 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

  test "j key does not move below last line":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.moveToLast()
    let lastIndex = state.selectedIndex

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == lastIndex

  test "Down arrow moves down":
    let
      handler = newSubStateHandler()
      state = createTestState()
    check state.selectedIndex == 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skDown))

    check result.kind == rfmrHandled
    check state.selectedIndex == 1

  test "Up arrow moves up":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 5

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skUp))

    check result.kind == rfmrHandled
    check state.selectedIndex == 4

suite "recent_file_mode_handler: handleRecentFileModeKey - No-op keys":
  test "h key is handled but does not move":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 5

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("h"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

  test "l key is handled but does not move":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 5

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("l"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

  test "Left arrow is handled but does not move":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 5

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skLeft))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

  test "Right arrow is handled but does not move":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 5

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skRight))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

  test "Backspace is handled but does not move":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 5

    let result = handler.handleRecentFileModeKey(
      state, TestViewportHeight, specialKey(skBackspace)
    )

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

suite "recent_file_mode_handler: handleRecentFileModeKey - gg and G commands":
  test "gg moves to first file":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 20

    # First 'g' - starts waiting
    let result1 =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result1.kind == rfmrHandled
    check handler.waitingForG == true
    check state.selectedIndex == 20 # Not moved yet

    # Second 'g' - executes gg
    let result2 =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result2.kind == rfmrHandled
    check handler.waitingForG == false
    check state.selectedIndex == 0

  test "g followed by non-g cancels and falls through":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 20

    # First 'g' - starts waiting
    let result1 =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result1.kind == rfmrHandled
    check handler.waitingForG == true

    # Non-'g' key - cancels waiting and falls through
    let result2 =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))
    check result2.kind == rfmrHandled # 'j' is handled as move down
    check handler.waitingForG == false
    check state.selectedIndex == 21 # Moved down by 'j'

  test "g followed by special key cancels and falls through":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 20

    # First 'g' - starts waiting
    let result1 =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result1.kind == rfmrHandled
    check handler.waitingForG == true

    # Special key - cancels waiting and falls through
    let result2 =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skDown))
    check result2.kind == rfmrHandled # Down arrow is handled
    check handler.waitingForG == false
    check state.selectedIndex == 21 # Moved down

  test "G moves to last file":
    let
      handler = newSubStateHandler()
      state = createTestState()
    check state.selectedIndex == 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))

    check result.kind == rfmrHandled
    check state.selectedIndex == state.files.high

suite "recent_file_mode_handler: handleRecentFileModeKey - Mode transitions":
  test "Escape is unhandled (quit handled at higher level)":
    let
      handler = newSubStateHandler()
      state = createTestState()

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEscape))

    check result.kind == rfmrUnhandled

  test ": enters command mode":
    let
      handler = newSubStateHandler()
      state = createTestState()

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey(":"))

    check result.kind == rfmrEnterCommand
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okCommand

suite "recent_file_mode_handler: handleRecentFileModeKey - File opening":
  test "Enter opens selected file":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 5

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEnter))

    check result.kind == rfmrOpenFile
    check result.filePath == "/file5.txt"
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Normal

  test "Enter returns error when no file selected (empty state)":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState() # Empty state

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEnter))

    check result.kind == rfmrError
    check "No file selected" in result.errorMessage

suite "recent_file_mode_handler: handleRecentFileModeKey - Scroll adjustment":
  test "Moving down adjusts topLine when cursor goes below viewport":
    let
      handler = newSubStateHandler()
      state = createTestState()
    # Set position at the bottom edge of viewport
    state.selectedIndex = TestViewportHeight - 1
    state.topLine = 0

    # Move down should trigger scroll adjustment
    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == TestViewportHeight
    check state.topLine == 1 # topLine adjusted to keep cursor visible

  test "Moving up adjusts topLine when cursor goes above viewport":
    let
      handler = newSubStateHandler()
      state = createTestState()
    # Set position at top of viewport (which is scrolled down)
    state.selectedIndex = 10
    state.topLine = 10

    # Move up should trigger scroll adjustment
    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 9
    check state.topLine == 9 # topLine adjusted to keep cursor visible

  test "G command scrolls to make last line visible":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.topLine = 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))

    check result.kind == rfmrHandled
    check state.selectedIndex == state.files.high
    # topLine should be adjusted so selected line is visible
    check state.topLine <= state.selectedIndex
    check state.topLine + TestViewportHeight > state.selectedIndex

suite "recent_file_mode_handler: handleRecentFileModeKey - Unhandled keys":
  test "Unbound key returns unhandled":
    let
      handler = newSubStateHandler()
      state = createTestState()

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("z"))

    check result.kind == rfmrUnhandled

  test "Unbound special key returns unhandled":
    let
      handler = newSubStateHandler()
      state = createTestState()

    # skHome is not handled by recent file mode
    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skHome))

    check result.kind == rfmrUnhandled

  test "Ctrl with unbound key returns unhandled":
    let
      handler = newSubStateHandler()
      state = createTestState()

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("x", {kmCtrl}))

    check result.kind == rfmrUnhandled

suite "recent_file_mode_handler: handleRecentFileModeKey - Empty state":
  test "j key on empty state does not crash":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState() # Empty
    check state.selectedIndex == 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0 # No change

  test "k key on empty state does not crash":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState() # Empty
    check state.selectedIndex == 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0 # No change

  test "G key on empty state does not crash":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState() # Empty

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0 # No change

  test "gg on empty state does not crash":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState() # Empty

    discard handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

suite "recent_file_mode_handler: handleRecentFileModeKey - gg command edge cases":
  test "Escape while waiting for g cancels and quits":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 10

    # First 'g' - starts waiting
    discard handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # Escape - cancels waiting, unhandled (quit handled at higher level)
    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEscape))
    check result.kind == rfmrUnhandled
    check handler.waitingForG == false
    check state.selectedIndex == 10 # Position unchanged

  test "G while waiting for g moves to last":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 10

    # First 'g' - starts waiting
    discard handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # 'G' (uppercase) - cancels waiting and moves to last
    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))
    check result.kind == rfmrHandled
    check handler.waitingForG == false
    check state.selectedIndex == state.files.high

  test "Handler state is reset after gg command":
    let
      handler = newSubStateHandler()
      state = createTestState()
    state.selectedIndex = 20

    # Execute gg
    discard handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    discard handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check state.selectedIndex == 0
    check handler.waitingForG == false

    # Next 'g' should start fresh waiting
    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result.kind == rfmrHandled
    check handler.waitingForG == true

suite "recent_file_mode_handler: handleRecentFileModeKey - Boundary conditions":
  test "Single file - j does not move":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/only.txt")
    check state.selectedIndex == 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

  test "Single file - k does not move":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/only.txt")
    check state.selectedIndex == 0

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

  test "Single file - G stays at 0":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/only.txt")

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

  test "Single file - Enter opens file":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/only.txt")

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEnter))

    check result.kind == rfmrOpenFile
    check result.filePath == "/only.txt"

  test "Out of range selectedIndex returns error on Enter":
    let
      handler = newSubStateHandler()
      state = newRecentFileModeState()
    state.files.add RecentFileEntry(path: "/file.txt")
    state.selectedIndex = 100 # Out of range

    let result =
      handler.handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEnter))

    check result.kind == rfmrError
    check "No file selected" in result.errorMessage
