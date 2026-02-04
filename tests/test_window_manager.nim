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

## Tests for window_manager.nim

import std/[unittest, options]
import pkg/results
import ../src/moepkg/[window_manager, types, buffer]

proc createTestWindow(x, y, width, height: int, active = false): EditorWindow =
  ## Create a test window with specified viewport
  let buf = newTextBuffer()
  discard buf.insertText(BufferPosition(line: 0, column: 0), "Test content")
  EditorWindow(
    buffer: buf,
    bufferList: @[buf], # Initialize with buffer (per-window tabs)
    viewport:
      ViewPort(topLine: 0, leftColumn: 0, width: width, height: height, x: x, y: y),
    cursor: BufferPosition(line: 0, column: 0),
    active: active,
  )

proc createSingleWindowManager(width = 80, height = 24): EditorWindowManager =
  ## Create a window manager with a single window
  let wm = newEditorWindowManager()
  wm.windows.add(createTestWindow(0, 0, width, height, active = true))
  wm.activeWindowIndex = 0
  wm

suite "EditorWindowManager - Constructor":
  test "newEditorWindowManager creates empty manager":
    let wm = newEditorWindowManager()

    check wm.windows.len == 0
    check wm.activeWindowIndex == 0

suite "EditorWindowManager - activeBuffer":
  test "activeBuffer returns buffer of active window":
    let wm = createSingleWindowManager()

    let buf = wm.activeBuffer()

    check buf.isSome
    check buf.get.len > 0

  test "activeBuffer returns none when no windows":
    let wm = newEditorWindowManager()

    let buf = wm.activeBuffer()

    check buf.isNone

  test "activeBuffer returns correct buffer with multiple windows":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = false))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = true))
    wm.activeWindowIndex = 1

    let buf = wm.activeBuffer()

    check buf.isSome
    check buf.get == wm.windows[1].buffer

suite "EditorWindowManager - Window Switching":
  test "switchToNextWindow with single window does nothing":
    let wm = createSingleWindowManager()

    wm.switchToNextWindow()

    check wm.activeWindowIndex == 0
    check wm.windows[0].active == true

  test "switchToNextWindow cycles through windows":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = true))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = false))
    wm.activeWindowIndex = 0

    wm.switchToNextWindow()

    check wm.activeWindowIndex == 1
    check wm.windows[0].active == false
    check wm.windows[1].active == true

  test "switchToNextWindow wraps around":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = false))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = true))
    wm.activeWindowIndex = 1

    wm.switchToNextWindow()

    check wm.activeWindowIndex == 0
    check wm.windows[0].active == true
    check wm.windows[1].active == false

  test "switchToPrevWindow with single window does nothing":
    let wm = createSingleWindowManager()

    wm.switchToPrevWindow()

    check wm.activeWindowIndex == 0
    check wm.windows[0].active == true

  test "switchToPrevWindow cycles through windows":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = false))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = true))
    wm.activeWindowIndex = 1

    wm.switchToPrevWindow()

    check wm.activeWindowIndex == 0
    check wm.windows[0].active == true
    check wm.windows[1].active == false

  test "switchToPrevWindow wraps around":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = true))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = false))
    wm.activeWindowIndex = 0

    wm.switchToPrevWindow()

    check wm.activeWindowIndex == 1
    check wm.windows[0].active == false
    check wm.windows[1].active == true

suite "EditorWindowManager - closeWindow":
  test "closeWindow returns true for last window":
    let wm = createSingleWindowManager()

    let shouldQuit = wm.closeWindow(multiStatusLine = false)

    check shouldQuit == true
    check wm.windows.len == 1 # Window is NOT removed

  test "closeWindow removes window and returns false":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = true))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = false))
    wm.activeWindowIndex = 0

    let shouldQuit = wm.closeWindow(multiStatusLine = false)

    check shouldQuit == false
    check wm.windows.len == 1

  test "closeWindow adjusts activeWindowIndex when closing last window":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = false))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = true))
    wm.activeWindowIndex = 1

    discard wm.closeWindow(multiStatusLine = false)

    check wm.activeWindowIndex == 0

  test "closeWindow activates remaining window":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = true))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = false))
    wm.activeWindowIndex = 0

    discard wm.closeWindow(multiStatusLine = false)

    check wm.windows.len == 1
    check wm.windows[0].active == true

suite "EditorWindowManager - Window Grouping":
  test "groupWindowsByY groups windows with same Y":
    let wm = newEditorWindowManager()
    # Two windows at y=0
    wm.windows.add(createTestWindow(0, 0, 40, 12))
    wm.windows.add(createTestWindow(41, 0, 39, 12))
    # One window at y=13
    wm.windows.add(createTestWindow(0, 13, 80, 11))

    let groups = wm.groupWindowsByY()

    check groups.len == 2
    # First group has windows at y=0
    check groups[0].len == 2
    # Second group has window at y=13
    check groups[1].len == 1

  test "groupWindowsByXAndWidth groups windows with same X and width":
    let wm = newEditorWindowManager()
    # Two windows at x=0, width=80
    wm.windows.add(createTestWindow(0, 0, 80, 12))
    wm.windows.add(createTestWindow(0, 13, 80, 11))

    let groups = wm.groupWindowsByXAndWidth()

    check groups.len == 1
    check groups[0].len == 2

  test "groupAdjacentWindowsHorizontally groups side-by-side windows":
    let wm = newEditorWindowManager()
    # Two horizontally adjacent windows
    wm.windows.add(createTestWindow(0, 0, 40, 24))
    wm.windows.add(createTestWindow(41, 0, 39, 24))

    let groups = wm.groupAdjacentWindowsHorizontally()

    check groups.len == 1
    check groups[0].len == 2

  test "groupAdjacentWindowsVertically groups stacked windows":
    let wm = newEditorWindowManager()
    # Two vertically adjacent windows
    wm.windows.add(createTestWindow(0, 0, 80, 12))
    wm.windows.add(createTestWindow(0, 13, 80, 11))

    let groups = wm.groupAdjacentWindowsVertically()

    check groups.len == 1
    check groups[0].len == 2

suite "EditorWindowManager - Equalize":
  test "equalizeWidthsInGroup with single window does nothing":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 24))

    wm.equalizeWidthsInGroup(@[0], 80, 0)

    check wm.windows[0].viewport.width == 80

  test "equalizeWidthsInGroup distributes width evenly":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows.add(createTestWindow(31, 0, 49, 24))

    wm.equalizeWidthsInGroup(@[0, 1], 80, 0)

    # With separator width of 1, total available = 80 - 1 = 79
    # Each window gets 79 / 2 = 39
    check wm.windows[0].viewport.width == 39
    # Last window gets remaining
    check wm.windows[1].viewport.width == 80 - 39 - 1

  test "equalizeHeightsInGroup with single window does nothing":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 24))

    wm.equalizeHeightsInGroup(@[0], 24, 0, multiStatusLine = false)

    check wm.windows[0].viewport.height == 24

  test "equalizeHeightsInGroup distributes height evenly":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 10))
    wm.windows.add(createTestWindow(0, 11, 80, 13))

    wm.equalizeHeightsInGroup(@[0, 1], 24, 0, multiStatusLine = false)

    # Heights should be roughly equal after equalization
    check wm.windows[0].viewport.y == 0
    check wm.windows[1].viewport.y > 0

suite "EditorWindowManager - Vertical Split":
  test "vsplit creates two side-by-side windows":
    let wm = createSingleWindowManager(80, 24)

    let result = wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    check result.isOk
    check wm.windows.len == 2
    check wm.activeWindowIndex == 1 # New window is active

    # Windows should be side by side
    check wm.windows[0].viewport.x == 0
    check wm.windows[1].viewport.x > wm.windows[0].viewport.width

  test "vsplit without filename shares buffer":
    let wm = createSingleWindowManager()
    let originalBuffer = wm.windows[0].buffer

    let result = wm.vsplit(
      originalBuffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    check result.isOk
    check result.get == originalBuffer
    check wm.windows[1].buffer == originalBuffer

  test "vsplit deactivates original window":
    let wm = createSingleWindowManager()
    check wm.windows[0].active == true

    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    check wm.windows[0].active == false
    check wm.windows[1].active == true

suite "EditorWindowManager - Horizontal Split":
  test "hsplit creates two stacked windows":
    let wm = createSingleWindowManager(80, 24)

    let result = wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )

    check result.isOk
    check wm.windows.len == 2
    check wm.activeWindowIndex == 1 # New window is active

    # Windows should be stacked
    check wm.windows[0].viewport.y == 0
    check wm.windows[1].viewport.y > wm.windows[0].viewport.height

  test "hsplit without filename shares buffer":
    let wm = createSingleWindowManager()
    let originalBuffer = wm.windows[0].buffer

    let result = wm.hsplit(
      originalBuffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )

    check result.isOk
    check result.get == originalBuffer

  test "hsplit deactivates original window":
    let wm = createSingleWindowManager()
    check wm.windows[0].active == true

    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )

    check wm.windows[0].active == false
    check wm.windows[1].active == true

  test "hsplit with multiStatusLine":
    let wm = createSingleWindowManager(80, 24)

    let result = wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = true,
    )

    check result.isOk
    check wm.windows.len == 2

suite "EditorWindowManager - vsplitWithBuffer":
  test "vsplitWithBuffer uses provided buffer":
    let wm = createSingleWindowManager()
    let newBuf = newTextBuffer()
    discard newBuf.insertText(BufferPosition(line: 0, column: 0), "New buffer content")

    let result = wm.vsplitWithBuffer(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      newBuf,
    )

    check result.isOk
    check result.get == newBuf
    check wm.windows[1].buffer == newBuf

suite "EditorWindowManager - hsplitWithBuffer":
  test "hsplitWithBuffer uses provided buffer":
    let wm = createSingleWindowManager()
    let newBuf = newTextBuffer()
    discard newBuf.insertText(BufferPosition(line: 0, column: 0), "New buffer content")

    let result = wm.hsplitWithBuffer(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
      newBuf,
    )

    check result.isOk
    check result.get == newBuf
    check wm.windows[1].buffer == newBuf

suite "EditorWindowManager - resizeWindows":
  test "resizeWindows with invalid dimensions does nothing":
    let wm = createSingleWindowManager(80, 24)
    let originalWidth = wm.windows[0].viewport.width

    wm.resizeWindows(0, 0, 80, 24, multiStatusLine = false)

    check wm.windows[0].viewport.width == originalWidth

  test "resizeWindows scales single window":
    let wm = createSingleWindowManager(80, 24)

    wm.resizeWindows(160, 48, 80, 24, multiStatusLine = false)

    # Window should be scaled proportionally
    check wm.windows[0].viewport.width > 80
    check wm.windows[0].viewport.height > 24

  test "resizeWindows shrinks windows":
    let wm = createSingleWindowManager(80, 24)

    wm.resizeWindows(40, 12, 80, 24, multiStatusLine = false)

    # Window should be scaled down
    check wm.windows[0].viewport.width <= 80
    check wm.windows[0].viewport.height <= 24

  test "resizeWindows handles multiple windows":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24, active = true))
    wm.windows.add(createTestWindow(41, 0, 39, 24, active = false))

    wm.resizeWindows(160, 48, 80, 24, multiStatusLine = false)

    # Both windows should be resized
    check wm.windows[0].viewport.width > 0
    check wm.windows[1].viewport.width > 0

  test "resizeWindows clamps topLine to buffer size":
    let wm = createSingleWindowManager(80, 24)
    wm.windows[0].viewport.topLine = 100 # Beyond buffer size

    wm.resizeWindows(80, 24, 80, 24, multiStatusLine = false)

    check wm.windows[0].viewport.topLine < wm.windows[0].buffer.len

suite "EditorWindowManager - Integration":
  test "Multiple vsplits create equal width windows":
    let wm = createSingleWindowManager(80, 24)

    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    check wm.windows.len == 2

    # Both windows should have roughly equal widths
    let totalWidth =
      wm.windows[0].viewport.width + wm.windows[1].viewport.width + WindowSeparatorWidth
    check totalWidth == 80

  test "Multiple hsplits create stacked windows":
    let wm = createSingleWindowManager(80, 24)

    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )

    check wm.windows.len == 2
    check wm.windows[0].viewport.y < wm.windows[1].viewport.y

  test "Close all but one window":
    let wm = createSingleWindowManager(80, 24)

    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )
    discard wm.vsplit(
      wm.windows[1].buffer, wm.windows[1].viewport, BufferPosition(line: 0, column: 0)
    )

    check wm.windows.len == 3

    # Close windows until one remains
    discard wm.closeWindow(multiStatusLine = false)
    check wm.windows.len == 2

    discard wm.closeWindow(multiStatusLine = false)
    check wm.windows.len == 1

    # Last window should return true (quit)
    let shouldQuit = wm.closeWindow(multiStatusLine = false)
    check shouldQuit == true
    check wm.windows.len == 1 # Still 1, not removed

  test "Switch through all windows":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 26, 24, active = true))
    wm.windows.add(createTestWindow(27, 0, 26, 24, active = false))
    wm.windows.add(createTestWindow(54, 0, 26, 24, active = false))
    wm.activeWindowIndex = 0

    wm.switchToNextWindow()
    check wm.activeWindowIndex == 1

    wm.switchToNextWindow()
    check wm.activeWindowIndex == 2

    wm.switchToNextWindow()
    check wm.activeWindowIndex == 0 # Wrapped around

    wm.switchToPrevWindow()
    check wm.activeWindowIndex == 2 # Wrapped back

suite "EditorWindowManager - bufferList in splits":
  test "vsplit initializes new window with single buffer in bufferList":
    let wm = createSingleWindowManager(80, 24)

    let splitResult = wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    check splitResult.isOk
    check wm.windows.len == 2
    # New window (index 1) should have bufferList with only the split buffer
    check wm.windows[1].bufferList.len == 1
    check wm.windows[1].bufferList[0] == wm.windows[1].buffer

  test "hsplit initializes new window with single buffer in bufferList":
    let wm = createSingleWindowManager(80, 24)

    let splitResult = wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )

    check splitResult.isOk
    check wm.windows.len == 2
    # New window (index 1) should have bufferList with only the split buffer
    check wm.windows[1].bufferList.len == 1
    check wm.windows[1].bufferList[0] == wm.windows[1].buffer

  test "vsplitWithBuffer initializes new window with provided buffer in bufferList":
    let wm = createSingleWindowManager(80, 24)
    let newBuffer = newTextBuffer()
    discard
      newBuffer.insertText(BufferPosition(line: 0, column: 0), "New buffer content")

    let splitResult = wm.vsplitWithBuffer(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      newBuffer,
    )

    check splitResult.isOk
    check wm.windows.len == 2
    check wm.windows[1].buffer == newBuffer
    check wm.windows[1].bufferList.len == 1
    check wm.windows[1].bufferList[0] == newBuffer

  test "hsplitWithBuffer initializes new window with provided buffer in bufferList":
    let wm = createSingleWindowManager(80, 24)
    let newBuffer = newTextBuffer()
    discard
      newBuffer.insertText(BufferPosition(line: 0, column: 0), "New buffer content")

    let splitResult = wm.hsplitWithBuffer(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
      newBuffer,
    )

    check splitResult.isOk
    check wm.windows.len == 2
    check wm.windows[1].buffer == newBuffer
    check wm.windows[1].bufferList.len == 1
    check wm.windows[1].bufferList[0] == newBuffer

  test "Original window bufferList unchanged after split":
    let wm = createSingleWindowManager(80, 24)
    let originalBufferListLen = wm.windows[0].bufferList.len

    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    # Original window's bufferList should be unchanged
    check wm.windows[0].bufferList.len == originalBufferListLen
