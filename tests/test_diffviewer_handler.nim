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

## Tests for diffviewer_handler.nim
## This module tests the Diff Viewer mode command handler functionality.

import std/[unittest]

import ../src/moepkg/keybindings {.all.}
import ../src/moepkg/diffviewer {.all.}
import ../src/moepkg/command_handlers/diffviewer_handler {.all.}

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
    result.lines.add(DiffLine(text: "line " & $i, kind: kind))

suite "diffviewer_handler: newDiffViewerHandler":
  test "Create new handler":
    let handler = newDiffViewerHandler()
    check handler != nil
    check handler.waitingForG == false

suite "diffviewer_handler: handleDiffViewerModeKey - Basic movement keys":
  test "j key moves down":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    check dvState.selectedLine == 0

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 1

  test "k key moves up":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    dvState.selectedLine = 3

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 2

  test "k key does not move above first line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    check dvState.selectedLine == 0

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 0

  test "j key does not move below last line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    dvState.selectedLine = 4

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 4

suite "diffviewer_handler: handleDiffViewerModeKey - Arrow keys":
  test "Down arrow moves down":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    check dvState.selectedLine == 0

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skDown))

    check result.kind == dvrHandled
    check dvState.selectedLine == 1

  test "Up arrow moves up":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    dvState.selectedLine = 3

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skUp))

    check result.kind == dvrHandled
    check dvState.selectedLine == 2

suite "diffviewer_handler: handleDiffViewerModeKey - gg and G commands":
  test "gg moves to first line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    dvState.selectedLine = 5

    # First 'g' - starts waiting
    let result1 =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result1.kind == dvrHandled
    check handler.waitingForG == true
    check dvState.selectedLine == 5 # Not moved yet

    # Second 'g' - executes gg
    let result2 =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result2.kind == dvrHandled
    check handler.waitingForG == false
    check dvState.selectedLine == 0
    check dvState.topLine == 0

  test "g followed by non-g cancels and falls through":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    dvState.selectedLine = 3

    # First 'g' - starts waiting
    let result1 =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result1.kind == dvrHandled
    check handler.waitingForG == true

    # Non-'g' key - cancels waiting and falls through to normal handling
    let result2 =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))
    check handler.waitingForG == false
    # The key falls through and 'j' is handled normally
    check result2.kind == dvrHandled
    check dvState.selectedLine == 4 # moved down from line 3 to line 4

  test "G moves to last line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    check dvState.selectedLine == 0

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 9 # Last line (0-indexed)

suite "diffviewer_handler: handleDiffViewerModeKey - Half page movement":
  test "Ctrl+d moves half page down":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(50)
    check dvState.selectedLine == 0

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("d", {kmCtrl})
    )

    check result.kind == dvrHandled
    # Half page is viewportHeight / 2 = 12
    check dvState.selectedLine == TestViewportHeight div 2

  test "Ctrl+u moves half page up":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(50)
    dvState.selectedLine = 30

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("u", {kmCtrl})
    )

    check result.kind == dvrHandled
    # Half page is viewportHeight / 2 = 12
    check dvState.selectedLine == 30 - (TestViewportHeight div 2)

  test "Ctrl+u does not go below 0":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    dvState.selectedLine = 3

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("u", {kmCtrl})
    )

    check result.kind == dvrHandled
    check dvState.selectedLine == 0

  test "Ctrl+d does not exceed last line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    dvState.selectedLine = 8

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("d", {kmCtrl})
    )

    check result.kind == dvrHandled
    check dvState.selectedLine == 9 # Last line

suite "diffviewer_handler: handleDiffViewerModeKey - Mode transitions":
  test ": enters command mode":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey(":"))

    check result.kind == dvrEnterCommand

  test "q quits diff viewer":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("q"))

    check result.kind == dvrQuit

  test "Escape quits diff viewer":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skEscape))

    check result.kind == dvrQuit

suite "diffviewer_handler: handleDiffViewerModeKey - Unhandled keys":
  test "Unbound key returns unhandled":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("z"))

    check result.kind == dvrUnhandled

  test "Unbound special key returns unhandled":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skPageUp))

    check result.kind == dvrUnhandled

  test "Character with modifier returns unhandled":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)

    # Ctrl+X - not a standard binding
    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("x", {kmCtrl})
    )

    check result.kind == dvrUnhandled

suite "diffviewer_handler: handleDiffViewerModeKey - Edge cases":
  test "Empty diff state - j does not crash":
    let
      handler = newDiffViewerHandler()
      dvState = newDiffViewerState()
    check dvState.lines.len == 0

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 0

  test "Empty diff state - G stays at 0":
    let
      handler = newDiffViewerHandler()
      dvState = newDiffViewerState()
    check dvState.lines.len == 0

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 0

  test "Empty diff state - gg stays at 0":
    let
      handler = newDiffViewerHandler()
      dvState = newDiffViewerState()

    # First 'g'
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    # Second 'g'
    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 0

  test "g followed by special key cancels":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    dvState.selectedLine = 3

    # First 'g' - starts waiting
    let result1 =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result1.kind == dvrHandled
    check handler.waitingForG == true

    # Special key - cancels waiting
    let result2 =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skDown))
    check handler.waitingForG == false
    # Down arrow is handled
    check result2.kind == dvrHandled
    check dvState.selectedLine == 4

suite "diffviewer_handler: handleDiffViewerModeKey - Scroll position":
  test "k updates topLine when going above visible area":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(30)
    dvState.selectedLine = 5
    dvState.topLine = 5 # First visible line is 5

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 4
    check dvState.topLine == 4 # topLine adjusted to keep cursor visible

  test "gg resets topLine to 0":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(30)
    dvState.selectedLine = 20
    dvState.topLine = 15

    # First 'g'
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    # Second 'g'
    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 0
    check dvState.topLine == 0

suite "diffviewer_handler: DiffViewerResult kinds":
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

suite "diffviewer_handler: Multiple consecutive operations":
  test "Multiple j presses move cursor down":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)

    for i in 0 ..< 5:
      discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check dvState.selectedLine == 5

  test "Multiple k presses move cursor up":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    dvState.selectedLine = 8

    for i in 0 ..< 5:
      discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check dvState.selectedLine == 3

  test "j at last line followed by k moves up":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    dvState.selectedLine = 9 # Last line

    # j should not move
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))
    check dvState.selectedLine == 9

    # k should move up
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))
    check dvState.selectedLine == 8

  test "G followed by gg":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)

    # G moves to last line
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))
    check dvState.selectedLine == 9

    # gg moves to first line
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check dvState.selectedLine == 0

suite "diffviewer_handler: Single line diff":
  test "j on single line diff":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(1)
    check dvState.lines.len == 1
    check dvState.selectedLine == 0

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("j"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 0 # Can't move down

  test "k on single line diff":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(1)
    check dvState.selectedLine == 0

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("k"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 0 # Can't move up

  test "G on single line diff":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(1)

    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))

    check result.kind == dvrHandled
    check dvState.selectedLine == 0 # Last line is also line 0

  test "Ctrl+d on single line diff":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(1)

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("d", {kmCtrl})
    )

    check result.kind == dvrHandled
    check dvState.selectedLine == 0 # Can't go beyond last line

suite "diffviewer_handler: Small viewport":
  test "Ctrl+d with viewportHeight = 1 moves at least 1 line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    check dvState.selectedLine == 0

    let result = handler.handleDiffViewerModeKey(dvState, 1, charKey("d", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedLine == 1 # max(1, 1 div 2) = 1

  test "Ctrl+u with viewportHeight = 1 moves at least 1 line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    dvState.selectedLine = 5

    let result = handler.handleDiffViewerModeKey(dvState, 1, charKey("u", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedLine == 4 # max(1, 1 div 2) = 1

  test "Ctrl+d with viewportHeight = 0 moves at least 1 line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    check dvState.selectedLine == 0

    let result = handler.handleDiffViewerModeKey(dvState, 0, charKey("d", {kmCtrl}))

    check result.kind == dvrHandled
    check dvState.selectedLine == 1 # max(1, 0 div 2) = 1

suite "diffviewer_handler: waitingForG with modifier keys":
  test "g followed by Ctrl+d cancels g and executes Ctrl+d":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(30)
    dvState.selectedLine = 5

    # First 'g' - starts waiting
    let result1 =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check result1.kind == dvrHandled
    check handler.waitingForG == true
    check dvState.selectedLine == 5

    # Ctrl+d - cancels waiting and executes half page down
    let result2 = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("d", {kmCtrl})
    )
    check handler.waitingForG == false
    check result2.kind == dvrHandled
    check dvState.selectedLine == 5 + (TestViewportHeight div 2)

  test "g followed by Ctrl+u cancels g and executes Ctrl+u":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(30)
    dvState.selectedLine = 20

    # First 'g' - starts waiting
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # Ctrl+u - cancels waiting and executes half page up
    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("u", {kmCtrl})
    )
    check handler.waitingForG == false
    check result.kind == dvrHandled
    check dvState.selectedLine == 20 - (TestViewportHeight div 2)

  test "g followed by : cancels g and enters command mode":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)

    # First 'g'
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # : - cancels waiting and enters command mode
    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey(":"))
    check handler.waitingForG == false
    check result.kind == dvrEnterCommand

  test "g followed by q cancels g and quits":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)

    # First 'g'
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # q - cancels waiting and quits
    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("q"))
    check handler.waitingForG == false
    check result.kind == dvrQuit

  test "g followed by G cancels g and moves to last line":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    dvState.selectedLine = 3

    # First 'g'
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # G - cancels waiting and moves to last line
    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("G"))
    check handler.waitingForG == false
    check result.kind == dvrHandled
    check dvState.selectedLine == 9

  test "g followed by Escape cancels g and quits":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)

    # First 'g'
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # Escape - cancels waiting and quits
    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, specialKey(skEscape))
    check handler.waitingForG == false
    check result.kind == dvrQuit

  test "g followed by unknown key cancels g and returns unhandled":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)

    # First 'g'
    discard handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # Unknown key - cancels waiting and returns unhandled
    let result =
      handler.handleDiffViewerModeKey(dvState, TestViewportHeight, charKey("z"))
    check handler.waitingForG == false
    check result.kind == dvrUnhandled

suite "diffviewer_handler: Other modifier combinations":
  # Note: The implementation ignores modifiers for most keys except Ctrl+d and Ctrl+u
  # This is intentional - modifiers are not checked for j/k/etc.

  test "Ctrl+j is treated as j (modifier ignored)":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    check dvState.selectedLine == 0

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("j", {kmCtrl})
    )

    # Implementation ignores Ctrl modifier for 'j'
    check result.kind == dvrHandled
    check dvState.selectedLine == 1

  test "Ctrl+k is treated as k (modifier ignored)":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    dvState.selectedLine = 3

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("k", {kmCtrl})
    )

    # Implementation ignores Ctrl modifier for 'k'
    check result.kind == dvrHandled
    check dvState.selectedLine == 2

  test "Alt+j is treated as j (modifier ignored)":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    check dvState.selectedLine == 0

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("j", {kmAlt})
    )

    # Implementation ignores Alt modifier for 'j'
    check result.kind == dvrHandled
    check dvState.selectedLine == 1

  test "Shift modifier on special key is ignored":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)
    dvState.selectedLine = 3

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, specialKey(skUp, {kmShift})
    )

    # Implementation ignores Shift modifier for arrow keys
    check result.kind == dvrHandled
    check dvState.selectedLine == 2

  test "Ctrl+G is treated as G (modifier ignored)":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(10)
    check dvState.selectedLine == 0

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("G", {kmCtrl})
    )

    # Implementation ignores Ctrl modifier for 'G'
    check result.kind == dvrHandled
    check dvState.selectedLine == 9

  test "Ctrl+q is treated as q (modifier ignored)":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)

    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("q", {kmCtrl})
    )

    # Implementation ignores Ctrl modifier for 'q'
    check result.kind == dvrQuit

  test "Unknown key with Ctrl modifier returns unhandled":
    let
      handler = newDiffViewerHandler()
      dvState = newTestDiffViewerState(5)

    # Ctrl+x is not bound (only Ctrl+d and Ctrl+u are)
    let result = handler.handleDiffViewerModeKey(
      dvState, TestViewportHeight, charKey("x", {kmCtrl})
    )

    check result.kind == dvrUnhandled
