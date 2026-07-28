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

## Tests for diff_viewer_handler.nim
## This module tests the Diff Viewer mode command handler functionality.

import std/[unittest]

import ../src/moepkg/[key_bindings, diff_viewer]
import ../src/moepkg/command_handlers/diff_viewer_handler

const TestViewportHeight = 24

proc charKey(c: string, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a character key combo
  KeyCombo(isSpecial: false, char: c, modifiers: mods)

proc specialKey(sk: SpecialKey, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a special key combo
  KeyCombo(isSpecial: true, special: sk, fnNum: 0, modifiers: mods)

proc newTestDiffViewerState(lineCount: int = 10): DiffViewerState =
  ## Create a test DiffViewerState with mock diff lines
  result = newDiffViewerState()
  for i in 0 ..< lineCount:
    let kind =
      if i == 0:
        dlkMeta
      elif i == 1:
        dlkHeader
      elif i mod 3 == 0:
        dlkAdded
      elif i mod 3 == 1:
        dlkDeleted
      else:
        dlkNormal
    result.items.add(DiffLine(text: "line " & $i, kind: kind))

suite "diff_viewer_handler: DiffViewerState construction":
  test "fresh DiffViewerState has waitingForG reset":
    let dvState = newTestDiffViewerState(5)
    check dvState.waitingForG == false

suite "diff_viewer_handler: handleDiffViewerModeKey - Basic movement keys":
  test "j key moves down":
    let dvState = newTestDiffViewerState(5)
    check dvState.selectedIndex == 0

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 1

  test "k key moves up":
    let dvState = newTestDiffViewerState(5)
    dvState.selectedIndex = 3

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 2

  test "k key does not move above first line":
    let dvState = newTestDiffViewerState(5)
    check dvState.selectedIndex == 0

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0

  test "j key does not move below last line":
    let dvState = newTestDiffViewerState(5)
    dvState.selectedIndex = 4

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 4

suite "diff_viewer_handler: handleDiffViewerModeKey - Arrow keys":
  test "Down arrow moves down":
    let dvState = newTestDiffViewerState(5)
    check dvState.selectedIndex == 0

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skDown))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 1

  test "Up arrow moves up":
    let dvState = newTestDiffViewerState(5)
    dvState.selectedIndex = 3

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skUp))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 2

suite "diff_viewer_handler: handleDiffViewerModeKey - gg and G commands":
  test "gg moves to first line":
    let dvState = newTestDiffViewerState(10)
    dvState.selectedIndex = 5

    # First 'g' - starts waiting
    let result1 = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result1.kind == dvrHandled
    check dvState.waitingForG == true
    check dvState.selectedIndex == 5 # Not moved yet

    # Second 'g' - executes gg
    let result2 = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result2.kind == dvrHandled
    check dvState.waitingForG == false
    check dvState.selectedIndex == 0

  test "g followed by non-g cancels and falls through":
    let dvState = newTestDiffViewerState(10)
    dvState.selectedIndex = 3

    # First 'g' - starts waiting
    let result1 = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result1.kind == dvrHandled
    check dvState.waitingForG == true

    # Non-'g' key - cancels waiting and falls through to normal handling
    let result2 = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))
    check dvState.waitingForG == false
    # The key falls through and 'j' is handled normally
    check result2.kind == dvrHandled
    check dvState.selectedIndex == 4 # moved down from line 3 to line 4

  test "G moves to last line":
    let dvState = newTestDiffViewerState(10)
    check dvState.selectedIndex == 0

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 9 # Last line (0-indexed)

suite "diff_viewer_handler: handleDiffViewerModeKey - Half page movement":
  test "Ctrl+d moves half page down":
    let dvState = newTestDiffViewerState(50)
    check dvState.selectedIndex == 0

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("d", {kmCtrl}))

    check result.kind == dvrHandled
    # Half page is viewportHeight / 2 = 12
    check dvState.selectedIndex == TestViewportHeight div 2

  test "Ctrl+u moves half page up":
    let dvState = newTestDiffViewerState(50)
    dvState.selectedIndex = 30

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("u", {kmCtrl}))

    check result.kind == dvrHandled
    # Half page is viewportHeight / 2 = 12
    check dvState.selectedIndex == 30 - (TestViewportHeight div 2)

  test "Ctrl+u does not go below 0":
    let dvState = newTestDiffViewerState(10)
    dvState.selectedIndex = 3

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("u", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0

  test "Ctrl+d does not exceed last line":
    let dvState = newTestDiffViewerState(10)
    dvState.selectedIndex = 8

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("d", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 9 # Last line

suite "diff_viewer_handler: handleDiffViewerModeKey - Mode transitions":
  test ": enters command mode":
    let dvState = newTestDiffViewerState(5)

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey(":"))

    check result.kind == dvrEnterCommand

  test "q quits diff viewer":
    let dvState = newTestDiffViewerState(5)

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("q"))

    check result.kind == dvrQuit

  test "Escape quits diff viewer":
    let dvState = newTestDiffViewerState(5)

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skEscape))

    check result.kind == dvrQuit

suite "diff_viewer_handler: handleDiffViewerModeKey - Unhandled keys":
  test "Unbound key returns unhandled":
    let dvState = newTestDiffViewerState(5)

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("z"))

    check result.kind == dvrUnhandled

  test "Unbound special key returns unhandled":
    let dvState = newTestDiffViewerState(5)

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skDelete))

    check result.kind == dvrUnhandled

  test "Character with modifier returns unhandled":
    let dvState = newTestDiffViewerState(5)

    # Ctrl+X - not a standard binding
    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("x", {kmCtrl}))

    check result.kind == dvrUnhandled

suite "diff_viewer_handler: handleDiffViewerModeKey - Edge cases":
  test "Empty diff state - j does not crash":
    let dvState = newDiffViewerState()
    check dvState.items.len == 0

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0

  test "Empty diff state - G stays at 0":
    let dvState = newDiffViewerState()
    check dvState.items.len == 0

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0

  test "Empty diff state - gg stays at 0":
    let dvState = newDiffViewerState()

    # First 'g'
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    # Second 'g'
    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0

  test "g followed by special key cancels":
    let dvState = newTestDiffViewerState(5)
    dvState.selectedIndex = 3

    # First 'g' - starts waiting
    let result1 = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result1.kind == dvrHandled
    check dvState.waitingForG == true

    # Special key - cancels waiting
    let result2 =
      handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skDown))
    check dvState.waitingForG == false
    # Down arrow is handled
    check result2.kind == dvrHandled
    check dvState.selectedIndex == 4

suite "diff_viewer_handler: DiffViewerResult kinds":
  test "dvrHandled result":
    let result = DiffViewerResult(kind: dvrHandled)
    check result.kind == dvrHandled

  test "dvrEnterCommand result":
    let result = DiffViewerResult(kind: dvrEnterCommand)
    check result.kind == dvrEnterCommand

  test "dvrQuit result":
    let result = DiffViewerResult(kind: dvrQuit)
    check result.kind == dvrQuit

  test "dvrUnhandled result":
    let result = DiffViewerResult(kind: dvrUnhandled)
    check result.kind == dvrUnhandled

  test "dvrError result with message":
    let result = DiffViewerResult(kind: dvrError, errorMessage: "test error")
    check result.kind == dvrError
    check result.errorMessage == "test error"

suite "diff_viewer_handler: Multiple consecutive operations":
  test "Multiple j presses move cursor down":
    let dvState = newTestDiffViewerState(10)

    for i in 0 ..< 5:
      discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check dvState.selectedIndex == 5

  test "Multiple k presses move cursor up":
    let dvState = newTestDiffViewerState(10)
    dvState.selectedIndex = 8

    for i in 0 ..< 5:
      discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check dvState.selectedIndex == 3

  test "j at last line followed by k moves up":
    let dvState = newTestDiffViewerState(10)
    dvState.selectedIndex = 9 # Last line

    # j should not move
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))
    check dvState.selectedIndex == 9

    # k should move up
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))
    check dvState.selectedIndex == 8

  test "G followed by gg":
    let dvState = newTestDiffViewerState(10)

    # G moves to last line
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))
    check dvState.selectedIndex == 9

    # gg moves to first line
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check dvState.selectedIndex == 0

suite "diff_viewer_handler: Single line diff":
  test "j on single line diff":
    let dvState = newTestDiffViewerState(1)
    check dvState.items.len == 1
    check dvState.selectedIndex == 0

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0 # Can't move down

  test "k on single line diff":
    let dvState = newTestDiffViewerState(1)
    check dvState.selectedIndex == 0

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0 # Can't move up

  test "G on single line diff":
    let dvState = newTestDiffViewerState(1)

    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0 # Last line is also line 0

  test "Ctrl+d on single line diff":
    let dvState = newTestDiffViewerState(1)

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("d", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0 # Can't go beyond last line

suite "diff_viewer_handler: Small viewport":
  # Half page moves by `viewportHeight div 2`, shared with every other list
  # viewer, so a degenerate viewport (0 or 1 rows) is a no-op.
  test "Ctrl+d with viewportHeight = 1 is a no-op":
    let dvState = newTestDiffViewerState(10)
    check dvState.selectedIndex == 0

    let result = handleDiffViewerModeKey(dvState, 1, charKey("d", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0 # 1 div 2 = 0

  test "Ctrl+u with viewportHeight = 1 is a no-op":
    let dvState = newTestDiffViewerState(10)
    dvState.selectedIndex = 5

    let result = handleDiffViewerModeKey(dvState, 1, charKey("u", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 5 # 1 div 2 = 0

  test "Ctrl+d with viewportHeight = 0 is a no-op":
    let dvState = newTestDiffViewerState(10)
    check dvState.selectedIndex == 0

    let result = handleDiffViewerModeKey(dvState, 0, charKey("d", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedIndex == 0 # 0 div 2 = 0

suite "diff_viewer_handler: waitingForG with modifier keys":
  test "g followed by Ctrl+d cancels g and executes Ctrl+d":
    let dvState = newTestDiffViewerState(30)
    dvState.selectedIndex = 5

    # First 'g' - starts waiting
    let result1 = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result1.kind == dvrHandled
    check dvState.waitingForG == true
    check dvState.selectedIndex == 5

    # Ctrl+d - cancels waiting and executes half page down
    let result2 =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("d", {kmCtrl}))
    check dvState.waitingForG == false
    check result2.kind == dvrHandled
    check dvState.selectedIndex == 5 + (TestViewportHeight div 2)

  test "g followed by Ctrl+u cancels g and executes Ctrl+u":
    let dvState = newTestDiffViewerState(30)
    dvState.selectedIndex = 20

    # First 'g' - starts waiting
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check dvState.waitingForG == true

    # Ctrl+u - cancels waiting and executes half page up
    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("u", {kmCtrl}))
    check dvState.waitingForG == false
    check result.kind == dvrHandled
    check dvState.selectedIndex == 20 - (TestViewportHeight div 2)

  test "g followed by : cancels g and enters command mode":
    let dvState = newTestDiffViewerState(10)

    # First 'g'
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check dvState.waitingForG == true

    # : - cancels waiting and enters command mode
    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey(":"))
    check dvState.waitingForG == false
    check result.kind == dvrEnterCommand

  test "g followed by q cancels g and quits":
    let dvState = newTestDiffViewerState(10)

    # First 'g'
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check dvState.waitingForG == true

    # q - cancels waiting and quits
    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("q"))
    check dvState.waitingForG == false
    check result.kind == dvrQuit

  test "g followed by G cancels g and moves to last line":
    let dvState = newTestDiffViewerState(10)
    dvState.selectedIndex = 3

    # First 'g'
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check dvState.waitingForG == true

    # G - cancels waiting and moves to last line
    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))
    check dvState.waitingForG == false
    check result.kind == dvrHandled
    check dvState.selectedIndex == 9

  test "g followed by Escape cancels g and quits":
    let dvState = newTestDiffViewerState(10)

    # First 'g'
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check dvState.waitingForG == true

    # Escape - cancels waiting and quits
    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skEscape))
    check dvState.waitingForG == false
    check result.kind == dvrQuit

  test "g followed by unknown key cancels g and returns unhandled":
    let dvState = newTestDiffViewerState(10)

    # First 'g'
    discard handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check dvState.waitingForG == true

    # Unknown key - cancels waiting and returns unhandled
    let result = handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("z"))
    check dvState.waitingForG == false
    check result.kind == dvrUnhandled

suite "diff_viewer_handler: Other modifier combinations":
  # Only Ctrl+d and Ctrl+u are consumed with a modifier; every other modified
  # char key falls through so caller-level bindings (e.g. `C-q = quit-force`)
  # still reach the router.

  test "Ctrl+j falls through and does not move selection":
    let dvState = newTestDiffViewerState(5)
    check dvState.selectedIndex == 0

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j", {kmCtrl}))

    check result.kind == dvrUnhandled
    check dvState.selectedIndex == 0

  test "Ctrl+k falls through and does not move selection":
    let dvState = newTestDiffViewerState(5)
    dvState.selectedIndex = 3

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k", {kmCtrl}))

    check result.kind == dvrUnhandled
    check dvState.selectedIndex == 3

  test "Alt+j falls through and does not move selection":
    let dvState = newTestDiffViewerState(5)
    check dvState.selectedIndex == 0

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j", {kmAlt}))

    check result.kind == dvrUnhandled
    check dvState.selectedIndex == 0

  test "Shift modifier on special key is ignored":
    let dvState = newTestDiffViewerState(5)
    dvState.selectedIndex = 3

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skUp, {kmShift}))

    # Implementation ignores Shift modifier for arrow keys
    check result.kind == dvrHandled
    check dvState.selectedIndex == 2

  test "Ctrl+G falls through and does not move to last":
    let dvState = newTestDiffViewerState(10)
    check dvState.selectedIndex == 0

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G", {kmCtrl}))

    check result.kind == dvrUnhandled
    check dvState.selectedIndex == 0

  test "Ctrl+q falls through instead of quitting":
    let dvState = newTestDiffViewerState(5)

    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("q", {kmCtrl}))

    check result.kind == dvrUnhandled

  test "Unknown key with Ctrl modifier returns unhandled":
    let dvState = newTestDiffViewerState(5)

    # Ctrl+x is not bound (only Ctrl+d and Ctrl+u are)
    let result =
      handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("x", {kmCtrl}))

    check result.kind == dvrUnhandled
