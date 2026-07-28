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

## Tests for debug_handler.nim

import std/unittest

import ../src/moepkg/debug_viewer
import ../src/moepkg/key_bindings
import ../src/moepkg/command_handlers/debug_handler

proc createDebugState(lines: seq[string] = @[]): DebugViewerState =
  result = newDebugViewerState()
  result.items = lines

proc charKeyCombo(c: char): KeyCombo =
  KeyCombo(isSpecial: false, char: $c, modifiers: {})

proc ctrlKeyCombo(c: char): KeyCombo =
  KeyCombo(isSpecial: false, char: $c, modifiers: {kmCtrl})

proc specialKeyCombo(sk: SpecialKey): KeyCombo =
  KeyCombo(isSpecial: true, special: sk, modifiers: {})

suite "Debug handler - Navigation keys":
  test "j key scrolls down":
    let debugState = createDebugState(@["line1", "line2", "line3"])
    let keyCombo = charKeyCombo('j')
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 1

  test "k key scrolls up":
    let debugState = createDebugState(@["line1", "line2", "line3"])
    debugState.selectedIndex = 2
    let keyCombo = charKeyCombo('k')
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 1

  test "g key scrolls to top":
    let debugState = createDebugState(@["line1", "line2", "line3"])
    debugState.selectedIndex = 2
    let keyCombo = charKeyCombo('g')
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 0

  test "G key scrolls to bottom":
    let debugState = createDebugState(@["line1", "line2", "line3"])
    let keyCombo = charKeyCombo('G')
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 2

  test "Down arrow scrolls down":
    let debugState = createDebugState(@["line1", "line2", "line3"])
    let keyCombo = specialKeyCombo(skDown)
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 1

  test "Up arrow scrolls up":
    let debugState = createDebugState(@["line1", "line2", "line3"])
    debugState.selectedIndex = 2
    let keyCombo = specialKeyCombo(skUp)
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 1

  test "Home key scrolls to top":
    let debugState = createDebugState(@["line1", "line2", "line3"])
    debugState.selectedIndex = 2
    let keyCombo = specialKeyCombo(skHome)
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 0

  test "End key scrolls to bottom":
    let debugState = createDebugState(@["line1", "line2", "line3"])
    let keyCombo = specialKeyCombo(skEnd)
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 2

suite "Debug handler - Page navigation":
  test "Ctrl+d pages down":
    let debugState = createDebugState(
      @[
        "line1", "line2", "line3", "line4", "line5", "line6", "line7", "line8", "line9",
        "line10",
      ]
    )
    let keyCombo = ctrlKeyCombo('d')
    let viewportHeight = 5

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 4 # pageSize = max(1, 5-1) = 4

  test "Ctrl+u pages up":
    let debugState = createDebugState(
      @[
        "line1", "line2", "line3", "line4", "line5", "line6", "line7", "line8", "line9",
        "line10",
      ]
    )
    debugState.selectedIndex = 8
    let keyCombo = ctrlKeyCombo('u')
    let viewportHeight = 5

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 4

  test "PageDown key pages down":
    let debugState = createDebugState(
      @[
        "line1", "line2", "line3", "line4", "line5", "line6", "line7", "line8", "line9",
        "line10",
      ]
    )
    let keyCombo = specialKeyCombo(skPageDown)
    let viewportHeight = 5

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 4

  test "PageUp key pages up":
    let debugState = createDebugState(
      @[
        "line1", "line2", "line3", "line4", "line5", "line6", "line7", "line8", "line9",
        "line10",
      ]
    )
    debugState.selectedIndex = 8
    let keyCombo = specialKeyCombo(skPageUp)
    let viewportHeight = 5

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == 4

suite "Debug handler - Command mode":
  test ": key enters command mode":
    let debugState = createDebugState(@["line1"])
    let keyCombo = charKeyCombo(':')
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrEnterCommand

suite "Debug handler - Other keys":
  test "Escape key is handled but does nothing":
    let debugState = createDebugState(@["line1"])
    let initialLine = debugState.selectedIndex
    let keyCombo = specialKeyCombo(skEscape)
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
    check debugState.selectedIndex == initialLine

  test "Unknown key is handled":
    let debugState = createDebugState(@["line1"])
    let keyCombo = charKeyCombo('x')
    let viewportHeight = 10

    let result = handleDebugModeKey(debugState, viewportHeight, keyCombo)

    check result.kind == dvrHandled
