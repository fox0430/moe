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

import ../src/moepkg/[key_bindings, modes, recent_file_mode]
import ../src/moepkg/command_handlers/recent_file_mode_handler

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
    state.items.add RecentFileEntry(path: "/file" & $i & ".txt")
  state

suite "recent_file_mode_handler: RecentFileModeState":
  test "fresh RecentFileModeState has waitingForG reset":
    let state = newRecentFileModeState()
    check state.waitingForG == false

suite "recent_file_mode_handler: handleRecentFileModeKey - Movement keys":
  test "j key moves down":
    let state = createTestState()
    check state.selectedIndex == 0

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 1

  test "k key moves up":
    let state = createTestState()
    state.selectedIndex = 5

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 4

  test "k key does not move above first line":
    let state = createTestState()
    check state.selectedIndex == 0

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

  test "j key does not move below last line":
    let state = createTestState()
    state.moveToLast()
    let lastIndex = state.selectedIndex

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == lastIndex

  test "Down arrow moves down":
    let state = createTestState()
    check state.selectedIndex == 0

    let result = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skDown))

    check result.kind == rfmrHandled
    check state.selectedIndex == 1

  test "Up arrow moves up":
    let state = createTestState()
    state.selectedIndex = 5

    let result = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skUp))

    check result.kind == rfmrHandled
    check state.selectedIndex == 4

suite "recent_file_mode_handler: handleRecentFileModeKey - No-op keys":
  test "h key is handled but does not move":
    let state = createTestState()
    state.selectedIndex = 5

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("h"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

  test "l key is handled but does not move":
    let state = createTestState()
    state.selectedIndex = 5

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("l"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

  test "Left arrow is handled but does not move":
    let state = createTestState()
    state.selectedIndex = 5

    let result = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skLeft))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

  test "Right arrow is handled but does not move":
    let state = createTestState()
    state.selectedIndex = 5

    let result = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skRight))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

  test "Backspace is handled but does not move":
    let state = createTestState()
    state.selectedIndex = 5

    let result =
      handleRecentFileModeKey(state, TestViewportHeight, specialKey(skBackspace))

    check result.kind == rfmrHandled
    check state.selectedIndex == 5

suite "recent_file_mode_handler: handleRecentFileModeKey - gg and G commands":
  test "gg moves to first file":
    let state = createTestState()
    state.selectedIndex = 20

    # First 'g' - starts waiting
    let result1 = handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result1.kind == rfmrHandled
    check state.waitingForG == true
    check state.selectedIndex == 20 # Not moved yet

    # Second 'g' - executes gg
    let result2 = handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result2.kind == rfmrHandled
    check state.waitingForG == false
    check state.selectedIndex == 0

  test "g followed by non-g cancels and falls through":
    let state = createTestState()
    state.selectedIndex = 20

    # First 'g' - starts waiting
    let result1 = handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result1.kind == rfmrHandled
    check state.waitingForG == true

    # Non-'g' key - cancels waiting and falls through
    let result2 = handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))
    check result2.kind == rfmrHandled # 'j' is handled as move down
    check state.waitingForG == false
    check state.selectedIndex == 21 # Moved down by 'j'

  test "g followed by special key cancels and falls through":
    let state = createTestState()
    state.selectedIndex = 20

    # First 'g' - starts waiting
    let result1 = handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result1.kind == rfmrHandled
    check state.waitingForG == true

    # Special key - cancels waiting and falls through
    let result2 = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skDown))
    check result2.kind == rfmrHandled # Down arrow is handled
    check state.waitingForG == false
    check state.selectedIndex == 21 # Moved down

  test "G moves to last file":
    let state = createTestState()
    check state.selectedIndex == 0

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))

    check result.kind == rfmrHandled
    check state.selectedIndex == state.items.high

suite "recent_file_mode_handler: handleRecentFileModeKey - Mode transitions":
  test "Escape is unhandled (quit handled at higher level)":
    let state = createTestState()

    let result =
      handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEscape))

    check result.kind == rfmrUnhandled

  test ": enters command mode":
    let state = createTestState()

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey(":"))

    check result.kind == rfmrEnterCommand
    check result.overlayTransition.isSome
    check result.overlayTransition.get == okCommand

suite "recent_file_mode_handler: handleRecentFileModeKey - File opening":
  test "Enter opens selected file":
    let state = createTestState()
    state.selectedIndex = 5

    let result = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEnter))

    check result.kind == rfmrOpenFile
    check result.filePath == "/file5.txt"
    check result.modeTransition.isSome
    check result.modeTransition.get == EditorMode.Normal

  test "Enter returns error when no file selected (empty state)":
    let state = newRecentFileModeState() # Empty state

    let result = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEnter))

    check result.kind == rfmrError
    check "No file selected" in result.errorMessage

suite "recent_file_mode_handler: handleRecentFileModeKey - Navigation":
  test "j moves the selection down":
    let state = createTestState()
    state.selectedIndex = TestViewportHeight - 1

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == TestViewportHeight

  test "k moves the selection up":
    let state = createTestState()
    state.selectedIndex = 10

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 9

  test "G moves to the last item":
    let state = createTestState()

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))

    check result.kind == rfmrHandled
    check state.selectedIndex == state.items.high

suite "recent_file_mode_handler: handleRecentFileModeKey - Unhandled keys":
  test "Unbound key returns unhandled":
    let state = createTestState()

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("z"))

    check result.kind == rfmrUnhandled

  test "Unbound special key returns unhandled":
    let state = createTestState()

    # skDelete is not handled by recent file mode
    let result =
      handleRecentFileModeKey(state, TestViewportHeight, specialKey(skDelete))

    check result.kind == rfmrUnhandled

  test "Ctrl with unbound key returns unhandled":
    let state = createTestState()

    let result =
      handleRecentFileModeKey(state, TestViewportHeight, charKey("x", {kmCtrl}))

    check result.kind == rfmrUnhandled

suite "recent_file_mode_handler: handleRecentFileModeKey - Empty state":
  test "j key on empty state does not crash":
    let state = newRecentFileModeState() # Empty
    check state.selectedIndex == 0

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0 # No change

  test "k key on empty state does not crash":
    let state = newRecentFileModeState() # Empty
    check state.selectedIndex == 0

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0 # No change

  test "G key on empty state does not crash":
    let state = newRecentFileModeState() # Empty

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0 # No change

  test "gg on empty state does not crash":
    let state = newRecentFileModeState() # Empty

    discard handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

suite "recent_file_mode_handler: handleRecentFileModeKey - gg command edge cases":
  test "Escape while waiting for g cancels and quits":
    let state = createTestState()
    state.selectedIndex = 10

    # First 'g' - starts waiting
    discard handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check state.waitingForG == true

    # Escape - cancels waiting, unhandled (quit handled at higher level)
    let result =
      handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEscape))
    check result.kind == rfmrUnhandled
    check state.waitingForG == false
    check state.selectedIndex == 10 # Position unchanged

  test "G while waiting for g moves to last":
    let state = createTestState()
    state.selectedIndex = 10

    # First 'g' - starts waiting
    discard handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check state.waitingForG == true

    # 'G' (uppercase) - cancels waiting and moves to last
    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))
    check result.kind == rfmrHandled
    check state.waitingForG == false
    check state.selectedIndex == state.items.high

  test "Handler state is reset after gg command":
    let state = createTestState()
    state.selectedIndex = 20

    # Execute gg
    discard handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    discard handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check state.selectedIndex == 0
    check state.waitingForG == false

    # Next 'g' should start fresh waiting
    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("g"))
    check result.kind == rfmrHandled
    check state.waitingForG == true

suite "recent_file_mode_handler: handleRecentFileModeKey - Boundary conditions":
  test "Single file - j does not move":
    let state = newRecentFileModeState()
    state.items.add RecentFileEntry(path: "/only.txt")
    check state.selectedIndex == 0

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("j"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

  test "Single file - k does not move":
    let state = newRecentFileModeState()
    state.items.add RecentFileEntry(path: "/only.txt")
    check state.selectedIndex == 0

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("k"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

  test "Single file - G stays at 0":
    let state = newRecentFileModeState()
    state.items.add RecentFileEntry(path: "/only.txt")

    let result = handleRecentFileModeKey(state, TestViewportHeight, charKey("G"))

    check result.kind == rfmrHandled
    check state.selectedIndex == 0

  test "Single file - Enter opens file":
    let state = newRecentFileModeState()
    state.items.add RecentFileEntry(path: "/only.txt")

    let result = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEnter))

    check result.kind == rfmrOpenFile
    check result.filePath == "/only.txt"

  test "Out of range selectedIndex returns error on Enter":
    let state = newRecentFileModeState()
    state.items.add RecentFileEntry(path: "/file.txt")
    state.selectedIndex = 100 # Out of range

    let result = handleRecentFileModeKey(state, TestViewportHeight, specialKey(skEnter))

    check result.kind == rfmrError
    check "No file selected" in result.errorMessage
