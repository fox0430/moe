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

## Tests for bookmark_manager_handler.nim

import std/[unittest, options]

import ../src/moepkg/[bookmark_manager, key_bindings]
import ../src/moepkg/buffer/core
import ../src/moepkg/command_handlers/bookmark_manager_handler

proc createTestBookmarkManagerState(): BookmarkManagerState =
  ## Create a BookmarkManagerState with test entries from buffers
  let state = newBookmarkManagerState()
  var buf1 = newTextBuffer("line 0\nline 1\nline 2\nline 3")
  buf1.filePath = some("/file1.nim")
  buf1.toggleBookmark(1)
  buf1.toggleBookmark(3)

  var buf2 = newTextBuffer("alpha\nbeta")
  buf2.filePath = some("/file2.nim")
  buf2.toggleBookmark(0)

  state.updateEntries(@[buf1, buf2])
  result = state

suite "bookmark_manager_handler: Constructor":
  test "fresh BookmarkManagerState has waitingForG reset":
    let bmState = newBookmarkManagerState()

    check bmState != nil
    check bmState.waitingForG == false

suite "bookmark_manager_handler: Result Types":
  test "bkmrHandled result":
    let result = BookmarkManagerResult(kind: bkmrHandled)
    check result.kind == bkmrHandled

  test "bkmrJumpToBookmark result":
    let result = BookmarkManagerResult(
      kind: bkmrJumpToBookmark, jumpBufferId: BufferId(42), jumpLine: 5
    )
    check result.kind == bkmrJumpToBookmark
    check result.jumpBufferId == BufferId(42)
    check result.jumpLine == 5

  test "bkmrDeleteBookmark result":
    let result = BookmarkManagerResult(kind: bkmrDeleteBookmark, deleteEntryIndex: 1)
    check result.kind == bkmrDeleteBookmark
    check result.deleteEntryIndex == 1

  test "bkmrEnterCommand result":
    let result = BookmarkManagerResult(kind: bkmrEnterCommand)
    check result.kind == bkmrEnterCommand

  test "bkmrQuit result":
    let result = BookmarkManagerResult(kind: bkmrQuit)
    check result.kind == bkmrQuit

  test "bkmrUnhandled result":
    let result = BookmarkManagerResult(kind: bkmrUnhandled)
    check result.kind == bkmrUnhandled

  test "bkmrError result with message":
    let result = BookmarkManagerResult(kind: bkmrError, errorMessage: "test error")
    check result.kind == bkmrError
    check result.errorMessage == "test error"

suite "bookmark_manager_handler: Navigation":
  test "Move down with j":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 1

  test "Move up with k":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 1

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "Move down with Down arrow":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 1

  test "Move up with Up arrow":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 1

    let keyCombo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "Move to last with G":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == bmState.items.len - 1

  test "Move to first with gg":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 2

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result1 = handleBookmarkManagerModeKey(bmState, 24, keyCombo1)

    check result1.kind == bkmrHandled
    check bmState.waitingForG == true

    # Second 'g' completes the command
    let keyCombo2 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result2 = handleBookmarkManagerModeKey(bmState, 24, keyCombo2)

    check result2.kind == bkmrHandled
    check bmState.selectedIndex == 0
    check bmState.waitingForG == false

  test "Half page down with Ctrl+d":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0
    let viewportHeight = 4
    let expectedMove = max(1, viewportHeight div 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result = handleBookmarkManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bkmrHandled
    let expectedIndex = min(expectedMove, bmState.items.len - 1)
    check bmState.selectedIndex == expectedIndex

  test "Half page up with Ctrl+u":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 2
    let viewportHeight = 4
    let expectedMove = max(1, viewportHeight div 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result = handleBookmarkManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bkmrHandled
    let expectedIndex = max(0, 2 - expectedMove)
    check bmState.selectedIndex == expectedIndex

suite "bookmark_manager_handler: Jump to Bookmark":
  test "Jump to bookmark with Enter":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 1 # file1.nim line 3

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrJumpToBookmark
    check result.jumpBufferId == bmState.items[1].bufferId
    check result.jumpLine == 3

  test "Jump to bookmark in second buffer":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 2 # file2.nim line 0

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrJumpToBookmark
    check result.jumpBufferId == bmState.items[2].bufferId
    check result.jumpLine == 0

  test "Enter with empty entries returns handled":
    let bmState = newBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled

suite "bookmark_manager_handler: Delete Bookmark":
  test "Delete bookmark with D":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 1

    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrDeleteBookmark
    check result.deleteEntryIndex == 1

  test "Delete with D on empty entries returns handled":
    let bmState = newBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled

suite "bookmark_manager_handler: Mode Transitions":
  test "Quit with Escape":
    let bmState = createTestBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrQuit

  test "Quit with q":
    let bmState = createTestBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrQuit

  test "Enter command mode with :":
    let bmState = createTestBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrEnterCommand

suite "bookmark_manager_handler: Window Navigation (Unhandled)":
  test "Ctrl+k returns unhandled":
    let bmState = createTestBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {kmCtrl})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrUnhandled

  test "Ctrl+j returns unhandled":
    let bmState = createTestBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {kmCtrl})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrUnhandled

suite "bookmark_manager_handler: Waiting for G State":
  test "First g sets waitingForG true":
    let bmState = createTestBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.waitingForG == true

  test "Waiting for G cancelled on non-g key":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBookmarkManagerModeKey(bmState, 24, keyCombo1)
    check bmState.waitingForG == true

    # Press something other than 'g' (j for move down)
    let keyCombo2 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo2)

    check bmState.waitingForG == false
    check result.kind == bkmrHandled
    check bmState.selectedIndex == 1

  test "Waiting for G cancelled on colon enters command mode":
    let bmState = createTestBookmarkManagerState()

    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBookmarkManagerModeKey(bmState, 24, keyCombo1)
    check bmState.waitingForG == true

    let keyCombo2 = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo2)

    check bmState.waitingForG == false
    check result.kind == bkmrEnterCommand

  test "Waiting for G cancelled on D triggers delete":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 1

    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBookmarkManagerModeKey(bmState, 24, keyCombo1)
    check bmState.waitingForG == true

    let keyCombo2 = KeyCombo(isSpecial: false, char: "D", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo2)

    check bmState.waitingForG == false
    check result.kind == bkmrDeleteBookmark
    check result.deleteEntryIndex == 1

  test "Waiting for G with Escape cancels and quits":
    let bmState = createTestBookmarkManagerState()

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBookmarkManagerModeKey(bmState, 24, keyCombo1)
    check bmState.waitingForG == true

    # Press Escape
    let keyCombo2 =
      KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo2)

    check bmState.waitingForG == false
    check result.kind == bkmrQuit

  test "Waiting for G cancelled when Ctrl-k passes through":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 2

    # First 'g' starts waiting
    discard handleBookmarkManagerModeKey(
      bmState, 24, KeyCombo(isSpecial: false, char: "g", modifiers: {})
    )
    check bmState.waitingForG == true

    # Ctrl-k is passed through for window switching; the pending 'gg' must clear.
    let result = handleBookmarkManagerModeKey(
      bmState, 24, KeyCombo(isSpecial: false, char: "k", modifiers: {kmCtrl})
    )
    check result.kind == bkmrUnhandled
    check bmState.waitingForG == false
    check bmState.selectedIndex == 2

    # A later lone 'g' only re-arms gg; it must not jump to the first bookmark.
    let result2 = handleBookmarkManagerModeKey(
      bmState, 24, KeyCombo(isSpecial: false, char: "g", modifiers: {})
    )
    check result2.kind == bkmrHandled
    check bmState.waitingForG == true
    check bmState.selectedIndex == 2

suite "bookmark_manager_handler: Unhandled Keys":
  test "Unhandled special key returns bkmrUnhandled":
    let bmState = createTestBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: true, special: skDelete, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrUnhandled

  test "Unhandled character key returns bkmrUnhandled":
    let bmState = createTestBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrUnhandled

  test "Unhandled function key returns bkmrUnhandled":
    let bmState = createTestBookmarkManagerState()

    let keyCombo =
      KeyCombo(isSpecial: true, special: skFunction, fnNum: 5, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrUnhandled

suite "bookmark_manager_handler: Edge Cases":
  test "Navigation at top boundary":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "Navigation at bottom boundary":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = bmState.items.len - 1

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == bmState.items.len - 1

  test "G with empty entries":
    let bmState = newBookmarkManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "gg with empty entries":
    let bmState = newBookmarkManagerState()

    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBookmarkManagerModeKey(bmState, 24, keyCombo1)

    let keyCombo2 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo2)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "Ctrl+d with viewport height 1 is a no-op":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0
    let viewportHeight = 1 # 1 div 2 = 0, shared with every other list viewer

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result = handleBookmarkManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0 # no move

  test "Ctrl+u with viewport height 1 is a no-op":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 2
    let viewportHeight = 1

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result = handleBookmarkManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 2 # no move

  test "Single entry - j does not move":
    let bmState = newBookmarkManagerState()
    var buf = newTextBuffer("only line")
    buf.toggleBookmark(0)
    bmState.updateEntries(@[buf])
    check bmState.items.len == 1

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "Single entry - k does not move":
    let bmState = newBookmarkManagerState()
    var buf = newTextBuffer("only line")
    buf.toggleBookmark(0)
    bmState.updateEntries(@[buf])

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "Single entry - Enter returns correct jump":
    let bmState = newBookmarkManagerState()
    var buf = newTextBuffer("only line")
    buf.filePath = some("single.nim")
    buf.toggleBookmark(0)
    bmState.updateEntries(@[buf])

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrJumpToBookmark
    check result.jumpBufferId == buf.id
    check result.jumpLine == 0

  test "Single entry - D returns correct delete":
    let bmState = newBookmarkManagerState()
    var buf = newTextBuffer("only line")
    buf.toggleBookmark(0)
    bmState.updateEntries(@[buf])

    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrDeleteBookmark
    check result.deleteEntryIndex == 0

  test "Ctrl+d with large half page":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0
    let viewportHeight = 100

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result = handleBookmarkManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == bmState.items.len - 1

  test "Ctrl+u at top":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0
    let viewportHeight = 4

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result = handleBookmarkManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "Jump to bookmark at index 0":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrJumpToBookmark
    check result.jumpBufferId == bmState.items[0].bufferId
    check result.jumpLine == 1

  test "Delete bookmark at index 0":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})
    let result = handleBookmarkManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bkmrDeleteBookmark
    check result.deleteEntryIndex == 0

suite "bookmark_manager_handler: Integration":
  test "Full workflow: navigate, jump, quit":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    # Move down
    let keyJ = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result1 = handleBookmarkManagerModeKey(bmState, 24, keyJ)
    check result1.kind == bkmrHandled
    check bmState.selectedIndex == 1

    # Move down again
    let result2 = handleBookmarkManagerModeKey(bmState, 24, keyJ)
    check result2.kind == bkmrHandled
    check bmState.selectedIndex == 2

    # Go to top with gg
    let keyG = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBookmarkManagerModeKey(bmState, 24, keyG)
    let result3 = handleBookmarkManagerModeKey(bmState, 24, keyG)
    check result3.kind == bkmrHandled
    check bmState.selectedIndex == 0

    # Go to last with G
    let keyShiftG = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let result4 = handleBookmarkManagerModeKey(bmState, 24, keyShiftG)
    check result4.kind == bkmrHandled
    check bmState.selectedIndex == 2

    # Jump to bookmark
    let keyEnter = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result5 = handleBookmarkManagerModeKey(bmState, 24, keyEnter)
    check result5.kind == bkmrJumpToBookmark
    check result5.jumpBufferId == bmState.items[2].bufferId
    check result5.jumpLine == 0

  test "Navigate with arrow keys and half-page scrolling":
    let bmState = createTestBookmarkManagerState()
    bmState.selectedIndex = 0

    # Down arrow
    let keyDown = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
    let result1 = handleBookmarkManagerModeKey(bmState, 24, keyDown)
    check result1.kind == bkmrHandled
    check bmState.selectedIndex == 1

    # Up arrow
    let keyUp = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
    let result2 = handleBookmarkManagerModeKey(bmState, 24, keyUp)
    check result2.kind == bkmrHandled
    check bmState.selectedIndex == 0

    # Ctrl+d (half page down with viewport=4 -> move 2)
    let keyCtrlD = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result3 = handleBookmarkManagerModeKey(bmState, 4, keyCtrlD)
    check result3.kind == bkmrHandled
    check bmState.selectedIndex == 2

    # Ctrl+u (half page up)
    let keyCtrlU = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result4 = handleBookmarkManagerModeKey(bmState, 4, keyCtrlU)
    check result4.kind == bkmrHandled
    check bmState.selectedIndex == 0

  test "Mode transitions workflow":
    let bmState = createTestBookmarkManagerState()

    # Enter command mode
    let keyColon = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let result1 = handleBookmarkManagerModeKey(bmState, 24, keyColon)
    check result1.kind == bkmrEnterCommand

    # Quit with q
    let keyQ = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let result2 = handleBookmarkManagerModeKey(bmState, 24, keyQ)
    check result2.kind == bkmrQuit

    # Quit with Escape
    let keyEsc = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result3 = handleBookmarkManagerModeKey(bmState, 24, keyEsc)
    check result3.kind == bkmrQuit
