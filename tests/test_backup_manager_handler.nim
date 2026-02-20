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

## Tests for backup_manager_handler.nim
## This module tests the Backup Manager mode command handler functionality.

import std/[unittest, times, os]

import ../src/moepkg/key_bindings {.all.}
import ../src/moepkg/backup_manager {.all.}
import ../src/moepkg/command_handlers/backup_manager_handler {.all.}

const TestViewportHeight = 24

proc charKey(c: string, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a character key combo
  KeyCombo(isSpecial: false, char: c, modifiers: mods)

proc specialKey(sk: SpecialKey, mods: set[KeyModifier] = {}): KeyCombo =
  ## Helper to create a special key combo
  KeyCombo(isSpecial: true, special: sk, fnNum: 0, modifiers: mods)

proc newTestBackupManagerState(entryCount: int = 10): BackupManagerState =
  ## Create a test BackupManagerState with mock entries
  result = newBackupManagerState()
  result.sourceFilePath = "/home/user/test.txt"
  result.baseBackupDir = "/home/user/.cache/moe/backups"
  result.backupDir = "/home/user/.cache/moe/backups/abc123"
  for i in 0 ..< entryCount:
    # Use hours and minutes to avoid day overflow
    let
      day = 1 + (i div 24) mod 28 # Stay within valid day range
      hour = i mod 24
    let timestamp = dateTime(2025, mJan, day, hour, 30, 45, zone = utc())
    result.entries.add(
      BackupEntry(
        filename: $timestamp,
        timestamp: timestamp,
        fullPath: result.backupDir / $timestamp,
      )
    )

suite "backup_manager_handler: newBackupManagerHandler":
  test "Create new handler":
    let handler = newBackupManagerHandler()
    check handler != nil
    check handler.waitingForG == false

suite "backup_manager_handler: handleBackupManagerModeKey - Basic movement keys":
  test "j key moves down":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    check bkState.selectedIndex == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("j"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 1

  test "k key moves up":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    bkState.selectedIndex = 3

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("k"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 2

  test "k key does not move above first entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    check bkState.selectedIndex == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("k"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0

  test "j key does not move below last entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    bkState.selectedIndex = 4

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("j"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 4

suite "backup_manager_handler: handleBackupManagerModeKey - Arrow keys":
  test "Down arrow moves down":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    check bkState.selectedIndex == 0

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, specialKey(skDown)
    )

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 1

  test "Up arrow moves up":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    bkState.selectedIndex = 3

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, specialKey(skUp))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 2

suite "backup_manager_handler: handleBackupManagerModeKey - gg and G commands":
  test "gg moves to first entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 5

    # First 'g' - starts waiting
    let result1 =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check result1.kind == bkmrHandled
    check handler.waitingForG == true
    check bkState.selectedIndex == 5 # Not moved yet

    # Second 'g' - executes gg
    let result2 =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check result2.kind == bkmrHandled
    check handler.waitingForG == false
    check bkState.selectedIndex == 0
    check bkState.topLine == 0

  test "g followed by non-g cancels and falls through":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 3

    # First 'g' - starts waiting
    let result1 =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check result1.kind == bkmrHandled
    check handler.waitingForG == true

    # Non-'g' key - cancels waiting and falls through to normal handling
    let result2 =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("j"))
    check handler.waitingForG == false
    # The key falls through and 'j' is handled normally
    check result2.kind == bkmrHandled
    check bkState.selectedIndex == 4 # moved down from 3 to 4

  test "G moves to last entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    check bkState.selectedIndex == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("G"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 9 # Last entry (0-indexed)

suite "backup_manager_handler: handleBackupManagerModeKey - Half page movement":
  test "Ctrl+d moves half page down":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(50)
    check bkState.selectedIndex == 0

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("d", {kmCtrl})
    )

    check result.kind == bkmrHandled
    # Half page is viewportHeight / 2 = 12
    check bkState.selectedIndex == TestViewportHeight div 2

  test "Ctrl+u moves half page up":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(50)
    bkState.selectedIndex = 30

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("u", {kmCtrl})
    )

    check result.kind == bkmrHandled
    # Half page is viewportHeight / 2 = 12
    check bkState.selectedIndex == 30 - (TestViewportHeight div 2)

  test "Ctrl+u does not go below 0":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 3

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("u", {kmCtrl})
    )

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0

  test "Ctrl+d does not exceed last entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 8

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("d", {kmCtrl})
    )

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 9 # Last entry

suite "backup_manager_handler: handleBackupManagerModeKey - Mode transitions":
  test ": enters command mode":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey(":"))

    check result.kind == bkmrEnterCommand

  test "q quits backup manager":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("q"))

    check result.kind == bkmrUnhandled

  test "Escape quits backup manager":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, specialKey(skEscape)
    )

    check result.kind == bkmrUnhandled

suite "backup_manager_handler: handleBackupManagerModeKey - Backup actions":
  test "R returns restore with index when entry selected":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    bkState.selectedIndex = 2

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("R"))

    check result.kind == bkmrRestore
    check result.restoreIndex == 2

  test "R returns handled when no entries":
    let
      handler = newBackupManagerHandler()
      bkState = newBackupManagerState()
    check bkState.entries.len == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("R"))

    check result.kind == bkmrHandled

  test "D returns delete with index when entry selected":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    bkState.selectedIndex = 3

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("D"))

    check result.kind == bkmrDelete
    check result.deleteIndex == 3

  test "D returns handled when no entries":
    let
      handler = newBackupManagerHandler()
      bkState = newBackupManagerState()
    check bkState.entries.len == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("D"))

    check result.kind == bkmrHandled

  test "r returns refresh":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("r"))

    check result.kind == bkmrRefresh

  test "Enter returns openDiff with index when entry selected":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    bkState.selectedIndex = 1

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, specialKey(skEnter)
    )

    check result.kind == bkmrOpenDiff
    check result.diffIndex == 1

  test "Enter returns handled when no entries":
    let
      handler = newBackupManagerHandler()
      bkState = newBackupManagerState()
    check bkState.entries.len == 0

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, specialKey(skEnter)
    )

    check result.kind == bkmrHandled

suite "backup_manager_handler: handleBackupManagerModeKey - Window switching":
  test "Ctrl+k returns unhandled for window switching":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("k", {kmCtrl})
    )

    check result.kind == bkmrUnhandled

  test "Ctrl+j returns unhandled for window switching":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("j", {kmCtrl})
    )

    check result.kind == bkmrUnhandled

suite "backup_manager_handler: handleBackupManagerModeKey - Unhandled keys":
  test "Unbound key returns unhandled":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("z"))

    check result.kind == bkmrUnhandled

  test "Unbound special key returns unhandled":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, specialKey(skPageUp)
    )

    check result.kind == bkmrUnhandled

  test "Character with unbound modifier returns unhandled":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)

    # Ctrl+X - not a standard binding
    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("x", {kmCtrl})
    )

    check result.kind == bkmrUnhandled

suite "backup_manager_handler: handleBackupManagerModeKey - Edge cases":
  test "Empty state - j does not crash":
    let
      handler = newBackupManagerHandler()
      bkState = newBackupManagerState()
    check bkState.entries.len == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("j"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0

  test "Empty state - G stays at 0":
    let
      handler = newBackupManagerHandler()
      bkState = newBackupManagerState()
    check bkState.entries.len == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("G"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0

  test "Empty state - gg stays at 0":
    let
      handler = newBackupManagerHandler()
      bkState = newBackupManagerState()

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    # Second 'g'
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0

  test "g followed by special key cancels":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(5)
    bkState.selectedIndex = 3

    # First 'g' - starts waiting
    let result1 =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check result1.kind == bkmrHandled
    check handler.waitingForG == true

    # Special key - cancels waiting
    let result2 = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, specialKey(skDown)
    )
    check handler.waitingForG == false
    # Down arrow is handled
    check result2.kind == bkmrHandled
    check bkState.selectedIndex == 4

suite "backup_manager_handler: handleBackupManagerModeKey - Scroll position":
  test "k updates topLine when going above visible area":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(30)
    bkState.selectedIndex = 5
    bkState.topLine = 5 # First visible line is 5

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("k"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 4
    check bkState.topLine == 4 # topLine adjusted to keep cursor visible

  test "gg resets topLine to 0":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(30)
    bkState.selectedIndex = 20
    bkState.topLine = 15

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    # Second 'g'
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0
    check bkState.topLine == 0

suite "backup_manager_handler: BackupManagerResult kinds":
  test "bkmrHandled result":
    let result = BackupManagerResult(kind: bkmrHandled)
    check result.kind == bkmrHandled

  test "bkmrRestore result with index":
    let result = BackupManagerResult(kind: bkmrRestore, restoreIndex: 5)
    check result.kind == bkmrRestore
    check result.restoreIndex == 5

  test "bkmrDelete result with index":
    let result = BackupManagerResult(kind: bkmrDelete, deleteIndex: 3)
    check result.kind == bkmrDelete
    check result.deleteIndex == 3

  test "bkmrOpenDiff result with index":
    let result = BackupManagerResult(kind: bkmrOpenDiff, diffIndex: 2)
    check result.kind == bkmrOpenDiff
    check result.diffIndex == 2

  test "bkmrRefresh result":
    let result = BackupManagerResult(kind: bkmrRefresh)
    check result.kind == bkmrRefresh

  test "bkmrEnterCommand result":
    let result = BackupManagerResult(kind: bkmrEnterCommand)
    check result.kind == bkmrEnterCommand

  test "bkmrUnhandled result":
    let result = BackupManagerResult(kind: bkmrUnhandled)
    check result.kind == bkmrUnhandled

  test "bkmrError result with message":
    let result = BackupManagerResult(kind: bkmrError, errorMessage: "test error")
    check result.kind == bkmrError
    check result.errorMessage == "test error"

suite "backup_manager_handler: Multiple consecutive operations":
  test "Multiple j presses move cursor down":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)

    for i in 0 ..< 5:
      discard
        handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("j"))

    check bkState.selectedIndex == 5

  test "Multiple k presses move cursor up":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 8

    for i in 0 ..< 5:
      discard
        handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("k"))

    check bkState.selectedIndex == 3

  test "j at last entry followed by k moves up":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 9 # Last entry

    # j should not move
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("j"))
    check bkState.selectedIndex == 9

    # k should move up
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("k"))
    check bkState.selectedIndex == 8

  test "G followed by gg":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)

    # G moves to last entry
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("G"))
    check bkState.selectedIndex == 9

    # gg moves to first entry
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check bkState.selectedIndex == 0

suite "backup_manager_handler: Single entry state":
  test "j on single entry state":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(1)
    check bkState.entries.len == 1
    check bkState.selectedIndex == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("j"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0 # Can't move down

  test "k on single entry state":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(1)
    check bkState.selectedIndex == 0

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("k"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0 # Can't move up

  test "G on single entry state":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(1)

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("G"))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0 # Last entry is also entry 0

  test "Ctrl+d on single entry state":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(1)

    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("d", {kmCtrl})
    )

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 0 # Can't go beyond last entry

  test "R on single entry state returns restore":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(1)

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("R"))

    check result.kind == bkmrRestore
    check result.restoreIndex == 0

  test "D on single entry state returns delete":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(1)

    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("D"))

    check result.kind == bkmrDelete
    check result.deleteIndex == 0

suite "backup_manager_handler: Small viewport":
  test "Ctrl+d with viewportHeight = 1 moves at least 1 entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    check bkState.selectedIndex == 0

    let result = handler.handleBackupManagerModeKey(bkState, 1, charKey("d", {kmCtrl}))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 1 # max(1, 1 div 2) = 1

  test "Ctrl+u with viewportHeight = 1 moves at least 1 entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 5

    let result = handler.handleBackupManagerModeKey(bkState, 1, charKey("u", {kmCtrl}))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 4 # max(1, 1 div 2) = 1

  test "Ctrl+d with viewportHeight = 0 moves at least 1 entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    check bkState.selectedIndex == 0

    let result = handler.handleBackupManagerModeKey(bkState, 0, charKey("d", {kmCtrl}))

    check result.kind == bkmrHandled
    check bkState.selectedIndex == 1 # max(1, 0 div 2) = 1

suite "backup_manager_handler: waitingForG with modifier keys":
  test "g followed by Ctrl+d cancels g and executes Ctrl+d":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(30)
    bkState.selectedIndex = 5

    # First 'g' - starts waiting
    let result1 =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check result1.kind == bkmrHandled
    check handler.waitingForG == true
    check bkState.selectedIndex == 5

    # Ctrl+d - cancels waiting and executes half page down
    let result2 = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("d", {kmCtrl})
    )
    check handler.waitingForG == false
    check result2.kind == bkmrHandled
    check bkState.selectedIndex == 5 + (TestViewportHeight div 2)

  test "g followed by Ctrl+u cancels g and executes Ctrl+u":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(30)
    bkState.selectedIndex = 20

    # First 'g' - starts waiting
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # Ctrl+u - cancels waiting and executes half page up
    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, charKey("u", {kmCtrl})
    )
    check handler.waitingForG == false
    check result.kind == bkmrHandled
    check bkState.selectedIndex == 20 - (TestViewportHeight div 2)

  test "g followed by : cancels g and enters command mode":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # : - cancels waiting and enters command mode
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey(":"))
    check handler.waitingForG == false
    check result.kind == bkmrEnterCommand

  test "g followed by q cancels g and quits":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # q - cancels waiting and quits
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("q"))
    check handler.waitingForG == false
    check result.kind == bkmrUnhandled

  test "g followed by G cancels g and moves to last entry":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 3

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # G - cancels waiting and moves to last entry
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("G"))
    check handler.waitingForG == false
    check result.kind == bkmrHandled
    check bkState.selectedIndex == 9

  test "g followed by Escape cancels g and quits":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # Escape - cancels waiting and quits
    let result = handler.handleBackupManagerModeKey(
      bkState, TestViewportHeight, specialKey(skEscape)
    )
    check handler.waitingForG == false
    check result.kind == bkmrUnhandled

  test "g followed by unknown key cancels g and returns unhandled":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # Unknown key - cancels waiting and returns unhandled
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("z"))
    check handler.waitingForG == false
    check result.kind == bkmrUnhandled

  test "g followed by R cancels g and returns restore":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 5

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # R - cancels waiting and returns restore
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("R"))
    check handler.waitingForG == false
    check result.kind == bkmrRestore
    check result.restoreIndex == 5

  test "g followed by D cancels g and returns delete":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)
    bkState.selectedIndex = 7

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # D - cancels waiting and returns delete
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("D"))
    check handler.waitingForG == false
    check result.kind == bkmrDelete
    check result.deleteIndex == 7

  test "g followed by r cancels g and returns refresh":
    let
      handler = newBackupManagerHandler()
      bkState = newTestBackupManagerState(10)

    # First 'g'
    discard
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("g"))
    check handler.waitingForG == true

    # r - cancels waiting and returns refresh
    let result =
      handler.handleBackupManagerModeKey(bkState, TestViewportHeight, charKey("r"))
    check handler.waitingForG == false
    check result.kind == bkmrRefresh
