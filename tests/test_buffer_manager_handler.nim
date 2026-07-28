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

## Tests for buffer_manager_handler.nim

import std/[unittest, options]

import ../src/moepkg/[buffer_manager, key_bindings]
import ../src/moepkg/command_handlers/buffer_manager_handler

proc createTestBufferManagerState(): BufferManagerState =
  ## Create a BufferManagerState with test entries
  let state = newBufferManagerState()
  let bufferInfos = @[
    BufferInfo(filePath: some("/file1.nim"), isModified: false, isActive: true),
    BufferInfo(filePath: some("/file2.nim"), isModified: true, isActive: false),
    BufferInfo(filePath: some("/file3.nim"), isModified: false, isActive: false),
  ]
  state.updateEntries(bufferInfos)
  result = state

suite "buffer_manager_handler: Constructor":
  test "fresh BufferManagerState has waitingForG reset":
    let bmState = newBufferManagerState()

    check bmState != nil
    check bmState.waitingForG == false

suite "buffer_manager_handler: Result Types":
  test "bmrHandled result":
    let result = BufferManagerResult(kind: bmrHandled)
    check result.kind == bmrHandled

  test "bmrSelectBuffer result":
    let result = BufferManagerResult(kind: bmrSelectBuffer, bufferIndex: 2)
    check result.kind == bmrSelectBuffer
    check result.bufferIndex == 2

  test "bmrDeleteBuffer result":
    let result = BufferManagerResult(kind: bmrDeleteBuffer, deleteBufferIndex: 1)
    check result.kind == bmrDeleteBuffer
    check result.deleteBufferIndex == 1

  test "bmrEnterCommand result":
    let result = BufferManagerResult(kind: bmrEnterCommand)
    check result.kind == bmrEnterCommand

  test "bmrQuit result":
    let result = BufferManagerResult(kind: bmrQuit)
    check result.kind == bmrQuit

  test "bmrUnhandled result":
    let result = BufferManagerResult(kind: bmrUnhandled)
    check result.kind == bmrUnhandled

  test "bmrError result with message":
    let result = BufferManagerResult(kind: bmrError, errorMessage: "test error")
    check result.kind == bmrError
    check result.errorMessage == "test error"

suite "buffer_manager_handler: Navigation":
  test "Move down with j":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == 1

  test "Move up with k":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 1

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == 0

  test "Move down with Down arrow":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == 1

  test "Move up with Up arrow":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 1

    let keyCombo = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == 0

  test "Move to last with G":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == bmState.items.len - 1

  test "Move to first with gg":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 2

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result1 = handleBufferManagerModeKey(bmState, 24, keyCombo1)

    check result1.kind == bmrHandled
    check bmState.waitingForG == true

    # Second 'g' completes the command
    let keyCombo2 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result2 = handleBufferManagerModeKey(bmState, 24, keyCombo2)

    check result2.kind == bmrHandled
    check bmState.selectedIndex == 0
    check bmState.waitingForG == false

  test "Half page down with Ctrl+d":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0
    let viewportHeight = 4
    let expectedMove = max(1, viewportHeight div 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result = handleBufferManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bmrHandled
    # Should move down by half page (capped by entries count)
    let expectedIndex = min(expectedMove, bmState.items.len - 1)
    check bmState.selectedIndex == expectedIndex

  test "Half page up with Ctrl+u":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 2
    let viewportHeight = 4
    let expectedMove = max(1, viewportHeight div 2)

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result = handleBufferManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bmrHandled
    # Should move up by half page
    let expectedIndex = max(0, 2 - expectedMove)
    check bmState.selectedIndex == expectedIndex

suite "buffer_manager_handler: Buffer Selection":
  test "Select buffer with Enter":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 1

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrSelectBuffer
    check result.bufferIndex == 1

  test "Open buffer with o":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 2

    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrSelectBuffer
    check result.bufferIndex == 2

  test "Select buffer with empty entries returns handled":
    let bmState = newBufferManagerState()
    # Empty state

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled

  test "Open buffer with o on empty entries returns handled":
    let bmState = newBufferManagerState()
    # Empty state

    let keyCombo = KeyCombo(isSpecial: false, char: "o", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled

suite "buffer_manager_handler: Buffer Deletion":
  test "Delete buffer with D":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 1

    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrDeleteBuffer
    check result.deleteBufferIndex == 1

  test "Delete buffer with D on empty entries returns handled":
    let bmState = newBufferManagerState()
    # Empty state

    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled

suite "buffer_manager_handler: Mode Transitions":
  test "Quit with Escape":
    let bmState = createTestBufferManagerState()

    let keyCombo = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrQuit

  test "Quit with q":
    let bmState = createTestBufferManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrQuit

  test "Enter command mode with :":
    let bmState = createTestBufferManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrEnterCommand

suite "buffer_manager_handler: Window Navigation (Unhandled)":
  test "Ctrl+k returns unhandled":
    let bmState = createTestBufferManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {kmCtrl})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrUnhandled

  test "Ctrl+j returns unhandled":
    let bmState = createTestBufferManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {kmCtrl})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrUnhandled

suite "buffer_manager_handler: Waiting for G State":
  test "First g sets waitingForG true":
    let bmState = createTestBufferManagerState()

    let keyCombo = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.waitingForG == true

  test "Waiting for G cancelled on non-g key":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBufferManagerModeKey(bmState, 24, keyCombo1)
    check bmState.waitingForG == true

    # Press something other than 'g' (j for move down)
    let keyCombo2 = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo2)

    # waitingForG should be cleared and j should be handled normally
    check bmState.waitingForG == false
    check result.kind == bmrHandled
    check bmState.selectedIndex == 1

  test "Waiting for G with special key cancels and handles key":
    let bmState = createTestBufferManagerState()

    # First 'g' starts waiting
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBufferManagerModeKey(bmState, 24, keyCombo1)
    check bmState.waitingForG == true

    # Press Escape
    let keyCombo2 =
      KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo2)

    check bmState.waitingForG == false
    check result.kind == bmrQuit

  test "Waiting for G cancelled when Ctrl-k passes through":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 2

    # First 'g' starts waiting
    discard handleBufferManagerModeKey(
      bmState, 24, KeyCombo(isSpecial: false, char: "g", modifiers: {})
    )
    check bmState.waitingForG == true

    # Ctrl-k is passed through for window switching; the pending 'gg' must clear.
    let result = handleBufferManagerModeKey(
      bmState, 24, KeyCombo(isSpecial: false, char: "k", modifiers: {kmCtrl})
    )
    check result.kind == bmrUnhandled
    check bmState.waitingForG == false
    check bmState.selectedIndex == 2

    # A later lone 'g' only re-arms gg; it must not jump to the first buffer.
    let result2 = handleBufferManagerModeKey(
      bmState, 24, KeyCombo(isSpecial: false, char: "g", modifiers: {})
    )
    check result2.kind == bmrHandled
    check bmState.waitingForG == true
    check bmState.selectedIndex == 2

suite "buffer_manager_handler: Unhandled Keys":
  test "Unhandled special key returns bmrUnhandled":
    let bmState = createTestBufferManagerState()

    # Delete is not handled
    let keyCombo = KeyCombo(isSpecial: true, special: skDelete, fnNum: 0, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrUnhandled

  test "Unhandled character key returns bmrUnhandled":
    let bmState = createTestBufferManagerState()

    # 'z' is not handled
    let keyCombo = KeyCombo(isSpecial: false, char: "z", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrUnhandled

  test "Unhandled function key returns bmrUnhandled":
    let bmState = createTestBufferManagerState()

    # F5 is not handled
    let keyCombo =
      KeyCombo(isSpecial: true, special: skFunction, fnNum: 5, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrUnhandled

suite "buffer_manager_handler: Edge Cases":
  test "Navigation at top boundary":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "k", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == 0 # Should stay at 0

  test "Navigation at bottom boundary":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = bmState.items.len - 1

    let keyCombo = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == bmState.items.len - 1 # Should stay at last

  test "G with empty entries":
    let bmState = newBufferManagerState()
    # Empty state

    let keyCombo = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == 0 # max(0, -1) = 0

  test "gg with empty entries":
    let bmState = newBufferManagerState()
    # Empty state

    # First 'g'
    let keyCombo1 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBufferManagerModeKey(bmState, 24, keyCombo1)

    # Second 'g'
    let keyCombo2 = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo2)

    check result.kind == bmrHandled
    check bmState.selectedIndex == 0

  test "Ctrl+d with large half page":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0
    # Large viewport - half page is larger than entries count
    let viewportHeight = 100

    let keyCombo = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result = handleBufferManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bmrHandled
    # Should be capped at last entry
    check bmState.selectedIndex == bmState.items.len - 1

  test "Ctrl+u at top":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0
    let viewportHeight = 4

    let keyCombo = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result = handleBufferManagerModeKey(bmState, viewportHeight, keyCombo)

    check result.kind == bmrHandled
    check bmState.selectedIndex == 0

  test "Select buffer at index 0":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrSelectBuffer
    check result.bufferIndex == 0

  test "Delete buffer at index 0":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    let keyCombo = KeyCombo(isSpecial: false, char: "D", modifiers: {})
    let result = handleBufferManagerModeKey(bmState, 24, keyCombo)

    check result.kind == bmrDeleteBuffer
    check result.deleteBufferIndex == 0

suite "buffer_manager_handler: Integration":
  test "Full workflow: navigate, select, quit":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    # Move down
    let keyJ = KeyCombo(isSpecial: false, char: "j", modifiers: {})
    let result1 = handleBufferManagerModeKey(bmState, 24, keyJ)
    check result1.kind == bmrHandled
    check bmState.selectedIndex == 1

    # Move down again
    let result2 = handleBufferManagerModeKey(bmState, 24, keyJ)
    check result2.kind == bmrHandled
    check bmState.selectedIndex == 2

    # Go to top with gg
    let keyG = KeyCombo(isSpecial: false, char: "g", modifiers: {})
    discard handleBufferManagerModeKey(bmState, 24, keyG)
    let result3 = handleBufferManagerModeKey(bmState, 24, keyG)
    check result3.kind == bmrHandled
    check bmState.selectedIndex == 0

    # Go to last with G
    let keyShiftG = KeyCombo(isSpecial: false, char: "G", modifiers: {})
    let result4 = handleBufferManagerModeKey(bmState, 24, keyShiftG)
    check result4.kind == bmrHandled
    check bmState.selectedIndex == 2

    # Select buffer
    let keyEnter = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let result5 = handleBufferManagerModeKey(bmState, 24, keyEnter)
    check result5.kind == bmrSelectBuffer
    check result5.bufferIndex == 2

  test "Navigate with arrow keys and half-page scrolling":
    let bmState = createTestBufferManagerState()
    bmState.selectedIndex = 0

    # Down arrow
    let keyDown = KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {})
    let result1 = handleBufferManagerModeKey(bmState, 24, keyDown)
    check result1.kind == bmrHandled
    check bmState.selectedIndex == 1

    # Up arrow
    let keyUp = KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {})
    let result2 = handleBufferManagerModeKey(bmState, 24, keyUp)
    check result2.kind == bmrHandled
    check bmState.selectedIndex == 0

    # Ctrl+d (half page down)
    let keyCtrlD = KeyCombo(isSpecial: false, char: "d", modifiers: {kmCtrl})
    let result3 = handleBufferManagerModeKey(bmState, 4, keyCtrlD)
    check result3.kind == bmrHandled
    check bmState.selectedIndex == 2 # Half of 4 = 2, but capped at last entry

    # Ctrl+u (half page up)
    let keyCtrlU = KeyCombo(isSpecial: false, char: "u", modifiers: {kmCtrl})
    let result4 = handleBufferManagerModeKey(bmState, 4, keyCtrlU)
    check result4.kind == bmrHandled
    check bmState.selectedIndex == 0 # Back to top

  test "Mode transitions workflow":
    let bmState = createTestBufferManagerState()

    # Enter command mode
    let keyColon = KeyCombo(isSpecial: false, char: ":", modifiers: {})
    let result1 = handleBufferManagerModeKey(bmState, 24, keyColon)
    check result1.kind == bmrEnterCommand

    # Quit with q
    let keyQ = KeyCombo(isSpecial: false, char: "q", modifiers: {})
    let result2 = handleBufferManagerModeKey(bmState, 24, keyQ)
    check result2.kind == bmrQuit

    # Quit with Escape
    let keyEsc = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    let result3 = handleBufferManagerModeKey(bmState, 24, keyEsc)
    check result3.kind == bmrQuit
