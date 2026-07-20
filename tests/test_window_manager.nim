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
import ../src/moepkg/window_manager {.all.}
import ../src/moepkg/[types, buffer, render_utils]

proc createTestWindow(x, y, width, height: int, active = false): EditorWindow =
  ## Create a test window with specified viewport
  let buf = newTextBuffer()
  discard buf.insertText(BufferPosition(line: 0, column: 0), "Test content")
  EditorWindow(
    buffer: buf,
    bufferIds: @[buf.id],
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
    check wm.activeWindowIndex == 0 # New window is active (inserted before original)

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

    check wm.windows[0].active == true # New window (left) is active
    check wm.windows[1].active == false # Original window (right) is inactive

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
    check wm.activeWindowIndex == 0 # New window is active (inserted before original)

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

    check wm.windows[0].active == true # New window (top) is active
    check wm.windows[1].active == false # Original window (bottom) is inactive

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

  test "hsplit with extremely small terminal height (single status line)":
    let wm = createSingleWindowManager(80, 2)
    let result = wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )
    check result.isOk
    check wm.windows.len == 2
    for i, win in wm.windows:
      check win.viewport.height >= 0

  test "hsplit with extremely small terminal height (multi status line)":
    let wm = createSingleWindowManager(80, 3)
    let result = wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = true,
    )
    check result.isOk
    check wm.windows.len == 2
    for i, win in wm.windows:
      check win.viewport.height >= 0

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
    check wm.windows[0].buffer == newBuf

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
    check wm.windows[0].buffer == newBuf

  test "hsplitWithBuffer with extremely small terminal height (single status line)":
    let wm = createSingleWindowManager(80, 2)
    let newBuf = newTextBuffer()
    let result = wm.hsplitWithBuffer(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
      newBuf,
    )
    check result.isOk
    check wm.windows.len == 2
    for i, win in wm.windows:
      check win.viewport.height >= 0

  test "hsplitWithBuffer with extremely small terminal height (multi status line)":
    let wm = createSingleWindowManager(80, 3)
    let newBuf = newTextBuffer()
    let result = wm.hsplitWithBuffer(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = true,
      newBuf,
    )
    check result.isOk
    check wm.windows.len == 2
    for i, win in wm.windows:
      check win.viewport.height >= 0

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

  test "vsplit layout survives large upscale without overlap":
    # Regression test: integer truncation during ratio-scaling used to
    # widen the separator gap beyond the ±1 adjacency tolerance, so the
    # windows were no longer grouped and each was stretched to the full
    # screen width (visible when startup splits from `moe file1 file2`
    # were rescaled from the default 80x20 to the real terminal size).
    let wm = newEditorWindowManager()
    # Geometry produced by vsplit at the default 80x20 screen size
    wm.windows.add(createTestWindow(0, 0, 39, 20))
    wm.windows.add(createTestWindow(40, 0, 40, 20, active = true))
    wm.activeWindowIndex = 1

    wm.resizeWindows(180, 45, 80, 20, multiStatusLine = false)

    let
      left = wm.windows[0]
      right = wm.windows[1]
    # No overlap and full-width tiling
    check left.viewport.x == 0
    check right.viewport.x >= left.viewport.x + left.viewport.width
    check right.viewport.x + right.viewport.width == 180
    # Roughly equal widths
    check abs(left.viewport.width - right.viewport.width) <= WindowSeparatorWidth + 1
    # Both span the full height above the command line
    for win in [left, right]:
      check win.viewport.y == 0
      check win.viewport.height == 45 - steadyBottomAreaHeight()

  test "hsplit layout survives large upscale without overlap":
    let wm = newEditorWindowManager()
    # Geometry produced by hsplit at the default 80x20 screen size
    wm.windows.add(createTestWindow(0, 0, 80, 9, active = true))
    wm.windows.add(createTestWindow(0, 10, 80, 10))
    wm.activeWindowIndex = 0

    wm.resizeWindows(180, 45, 80, 20, multiStatusLine = false)

    let
      top = wm.windows[0]
      bottom = wm.windows[1]
    # No overlap and full-height tiling above the command line row
    check top.viewport.y == 0
    check bottom.viewport.y >= top.viewport.y + top.viewport.height
    check bottom.viewport.y + bottom.viewport.height == 45 - steadyBottomAreaHeight()
    # Both span the full width
    for win in [top, bottom]:
      check win.viewport.x == 0
      check win.viewport.width == 180

  test "downscale keeps vsplit windows tiled":
    let wm = newEditorWindowManager()
    # Even tiling at 180x45
    wm.windows.add(createTestWindow(0, 0, 89, 44))
    wm.windows.add(createTestWindow(90, 0, 90, 44, active = true))
    wm.activeWindowIndex = 1

    wm.resizeWindows(100, 30, 180, 45, multiStatusLine = false)

    let
      left = wm.windows[0]
      right = wm.windows[1]
    check left.viewport.x == 0
    check right.viewport.x >= left.viewport.x + left.viewport.width
    check right.viewport.x + right.viewport.width == 100
    for win in [left, right]:
      check win.viewport.y == 0
      check win.viewport.height == 30 - steadyBottomAreaHeight()

  test "tall-left + stacked-right upscale keeps neighbors visible":
    # Regression: equalizeWidthsForResize used to stretch single-element
    # groups to newWidth, overlapping mismatched-height right neighbors.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 20, active = true))
    wm.windows.add(createTestWindow(41, 0, 39, 10))
    wm.windows.add(createTestWindow(41, 11, 39, 9))
    wm.activeWindowIndex = 0

    wm.resizeWindows(180, 45, 80, 20, multiStatusLine = false)

    let
      tall = wm.windows[0]
      top = wm.windows[1]
      bot = wm.windows[2]
    check tall.viewport.x == 0
    check tall.viewport.x + tall.viewport.width <= top.viewport.x
    check tall.viewport.x + tall.viewport.width <= bot.viewport.x
    check top.viewport.x + top.viewport.width == 180
    check bot.viewport.x + bot.viewport.width == 180

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

  test "Close middle window of 3 hsplits re-equalizes without overlap":
    let wm = createSingleWindowManager(80, 30)

    # Create 3 horizontal splits
    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )
    discard wm.hsplit(
      wm.windows[1].buffer,
      wm.windows[1].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )
    check wm.windows.len == 3

    # Close the middle window
    wm.deactivateAllWindows()
    wm.activateWindow(1)
    discard wm.closeWindow(multiStatusLine = false)
    check wm.windows.len == 2

    # Verify no overlapping: window 0's bottom should not exceed window 1's top
    let
      w0End = wm.windows[0].viewport.y + wm.windows[0].viewport.height
      w1Start = wm.windows[1].viewport.y
    check w0End <= w1Start

    # Verify total coverage: windows span the full height
    check wm.windows[0].viewport.y == 0
    check wm.windows[1].viewport.y + wm.windows[1].viewport.height == 30

  test "Close middle window of 3 vsplits re-equalizes without overlap":
    let wm = createSingleWindowManager(80, 24)

    # Create 3 vertical splits
    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )
    discard wm.vsplit(
      wm.windows[1].buffer, wm.windows[1].viewport, BufferPosition(line: 0, column: 0)
    )
    check wm.windows.len == 3

    # Close the middle window
    wm.deactivateAllWindows()
    wm.activateWindow(1)
    discard wm.closeWindow(multiStatusLine = false)
    check wm.windows.len == 2

    # Verify no overlapping
    let
      w0End = wm.windows[0].viewport.x + wm.windows[0].viewport.width
      w1Start = wm.windows[1].viewport.x
    check w0End < w1Start # gap for separator

    # Verify total coverage
    check wm.windows[0].viewport.x == 0
    check wm.windows[1].viewport.x + wm.windows[1].viewport.width == 80

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

suite "EditorWindowManager - bufferIds in splits":
  test "vsplit initializes new window with single buffer in bufferIds":
    let wm = createSingleWindowManager(80, 24)

    let splitResult = wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    check splitResult.isOk
    check wm.windows.len == 2
    # New window (index 0) should have bufferIds with only the split buffer's id
    check wm.windows[0].bufferIds.len == 1
    check wm.windows[0].bufferIds[0] == wm.windows[0].buffer.id

  test "hsplit initializes new window with single buffer in bufferIds":
    let wm = createSingleWindowManager(80, 24)

    let splitResult = wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )

    check splitResult.isOk
    check wm.windows.len == 2
    check wm.windows[0].bufferIds.len == 1
    check wm.windows[0].bufferIds[0] == wm.windows[0].buffer.id

  test "vsplitWithBuffer initializes new window with provided buffer in bufferIds":
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
    check wm.windows[0].buffer == newBuffer
    check wm.windows[0].bufferIds.len == 1
    check wm.windows[0].bufferIds[0] == newBuffer.id

  test "hsplitWithBuffer initializes new window with provided buffer in bufferIds":
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
    check wm.windows[0].buffer == newBuffer
    check wm.windows[0].bufferIds.len == 1
    check wm.windows[0].bufferIds[0] == newBuffer.id

  test "Original window bufferIds unchanged after split":
    let wm = createSingleWindowManager(80, 24)
    let originalLen = wm.windows[0].bufferIds.len

    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    # Original window (now at index 1) bufferIds should be unchanged
    check wm.windows[1].bufferIds.len == originalLen

suite "EditorWindowManager - Split Size Proportions":
  # vsplit size checks

  test "2 vsplits produce equal widths totalling original":
    let wm = createSingleWindowManager(80, 24)

    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )

    check wm.windows.len == 2
    # availableWidth = 80 - 1(sep) = 79, each = 79 div 2 = 39, last = 80 - 40 = 40
    check wm.windows[0].viewport.x == 0
    check wm.windows[0].viewport.width == 39
    check wm.windows[1].viewport.x == 40
    check wm.windows[1].viewport.width == 40
    check wm.windows[0].viewport.width + WindowSeparatorWidth +
      wm.windows[1].viewport.width == 80

  test "3 vsplits produce equal widths totalling original":
    let wm = createSingleWindowManager(80, 24)

    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )
    discard wm.vsplit(
      wm.windows[1].buffer, wm.windows[1].viewport, BufferPosition(line: 0, column: 0)
    )

    check wm.windows.len == 3
    # availableWidth = 80 - 2(sep) = 78, each = 78 div 3 = 26, last = 80 - 54 = 26
    check wm.windows[0].viewport.x == 0
    check wm.windows[0].viewport.width == 26
    check wm.windows[1].viewport.x == 27
    check wm.windows[1].viewport.width == 26
    check wm.windows[2].viewport.x == 54
    check wm.windows[2].viewport.width == 26
    check wm.windows[0].viewport.width + WindowSeparatorWidth +
      wm.windows[1].viewport.width + WindowSeparatorWidth + wm.windows[2].viewport.width ==
      80

  # hsplit size checks (single status line)

  test "2 hsplits produce correct heights (single status line)":
    let wm = createSingleWindowManager(80, 24)

    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )

    check wm.windows.len == 2
    # totalContent = 24 - 1(sep) - 1(status) - 1(cmd) = 21, each = 21 div 2 = 10
    # Window 0: height=10 (content only), Window 1: height = 24 - 11 = 13
    check wm.windows[0].viewport.y == 0
    check wm.windows[0].viewport.height == 10
    check wm.windows[1].viewport.y == 11
    check wm.windows[1].viewport.height == 13
    check wm.windows[0].viewport.height + WindowSeparatorHeight +
      wm.windows[1].viewport.height == 24

  test "3 hsplits produce correct heights (single status line)":
    let wm = createSingleWindowManager(80, 24)

    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )
    discard wm.hsplit(
      wm.windows[1].buffer,
      wm.windows[1].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )

    check wm.windows.len == 3
    # totalContent = 24 - 2(sep) - 1(status) - 1(cmd) = 20, each = 20 div 3 = 6
    # W0: h=6, W1: h=6, W2: h = 24 - 14 = 10
    check wm.windows[0].viewport.y == 0
    check wm.windows[0].viewport.height == 6
    check wm.windows[1].viewport.y == 7
    check wm.windows[1].viewport.height == 6
    check wm.windows[2].viewport.y == 14
    check wm.windows[2].viewport.height == 10
    check wm.windows[0].viewport.height + WindowSeparatorHeight +
      wm.windows[1].viewport.height + WindowSeparatorHeight +
      wm.windows[2].viewport.height == 24

  # hsplit size checks (multi status line)

  test "2 hsplits produce correct heights (multi status line)":
    let wm = createSingleWindowManager(80, 24)

    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = true,
    )

    check wm.windows.len == 2
    # totalContent = 24 - 0(sep) - 2(status) - 1(cmd) = 21, each = 21 div 2 = 10
    # W0: h = 10 + 1(status) = 11, W1: h = 24 - 11 = 13
    check wm.windows[0].viewport.y == 0
    check wm.windows[0].viewport.height == 11
    check wm.windows[1].viewport.y == 11
    check wm.windows[1].viewport.height == 13
    check wm.windows[0].viewport.height + wm.windows[1].viewport.height == 24

  test "3 hsplits produce correct heights (multi status line)":
    let wm = createSingleWindowManager(80, 24)

    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = true,
    )
    discard wm.hsplit(
      wm.windows[1].buffer,
      wm.windows[1].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = true,
    )

    check wm.windows.len == 3
    # totalContent = 24 - 0(sep) - 3(status) - 1(cmd) = 20, each = 20 div 3 = 6
    # W0: h = 6 + 1 = 7, W1: h = 6 + 1 = 7, W2: h = 24 - 14 = 10
    check wm.windows[0].viewport.y == 0
    check wm.windows[0].viewport.height == 7
    check wm.windows[1].viewport.y == 7
    check wm.windows[1].viewport.height == 7
    check wm.windows[2].viewport.y == 14
    check wm.windows[2].viewport.height == 10
    check wm.windows[0].viewport.height + wm.windows[1].viewport.height +
      wm.windows[2].viewport.height == 24

  # close + re-equalize size checks

  test "Close middle of 3 vsplits produces same sizes as fresh 2 vsplit":
    let wm = createSingleWindowManager(80, 24)

    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )
    discard wm.vsplit(
      wm.windows[1].buffer, wm.windows[1].viewport, BufferPosition(line: 0, column: 0)
    )
    check wm.windows.len == 3

    wm.deactivateAllWindows()
    wm.activateWindow(1)
    discard wm.closeWindow(multiStatusLine = false)
    check wm.windows.len == 2

    # Should match a fresh 2-vsplit layout
    check wm.windows[0].viewport.x == 0
    check wm.windows[0].viewport.width == 39
    check wm.windows[1].viewport.x == 40
    check wm.windows[1].viewport.width == 40

  test "Close middle of 3 hsplits produces same sizes as fresh 2 hsplit":
    let wm = createSingleWindowManager(80, 24)

    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )
    discard wm.hsplit(
      wm.windows[1].buffer,
      wm.windows[1].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )
    check wm.windows.len == 3

    wm.deactivateAllWindows()
    wm.activateWindow(1)
    discard wm.closeWindow(multiStatusLine = false)
    check wm.windows.len == 2

    # Should match a fresh 2-hsplit layout
    check wm.windows[0].viewport.y == 0
    check wm.windows[0].viewport.height == 10
    check wm.windows[1].viewport.y == 11
    check wm.windows[1].viewport.height == 13

suite "EditorWindowManager - Split inherits cursor position for same buffer":
  test "vsplit same buffer inherits cursor position":
    let wm = createSingleWindowManager(80, 24)
    wm.windows[0].cursor = BufferPosition(line: 5, column: 10)
    wm.windows[0].viewport.topLine = 3
    wm.windows[0].viewport.leftColumn = 2

    let result = wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 5, column: 10)
    )

    check result.isOk
    check wm.windows[0].cursor.line == 5
    check wm.windows[0].cursor.column == 10
    check wm.windows[0].viewport.topLine == 3
    check wm.windows[0].viewport.leftColumn == 2

  test "vsplit different file starts at position 0":
    let wm = createSingleWindowManager(80, 24)
    wm.windows[0].cursor = BufferPosition(line: 5, column: 10)
    wm.windows[0].viewport.topLine = 3
    wm.windows[0].viewport.leftColumn = 2

    let newBuf = newTextBuffer()
    discard newBuf.insertText(BufferPosition(line: 0, column: 0), "New content")

    let result = wm.vsplitWithBuffer(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 5, column: 10),
      newBuf,
    )

    check result.isOk
    check wm.windows[0].cursor.line == 0
    check wm.windows[0].cursor.column == 0
    check wm.windows[0].viewport.topLine == 0
    check wm.windows[0].viewport.leftColumn == 0

  test "hsplit same buffer inherits cursor position":
    let wm = createSingleWindowManager(80, 24)
    wm.windows[0].cursor = BufferPosition(line: 5, column: 10)
    wm.windows[0].viewport.topLine = 3
    wm.windows[0].viewport.leftColumn = 2

    let result = wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 5, column: 10),
      multiStatusLine = false,
    )

    check result.isOk
    check wm.windows[0].cursor.line == 5
    check wm.windows[0].cursor.column == 10
    check wm.windows[0].viewport.topLine == 3
    check wm.windows[0].viewport.leftColumn == 2

  test "hsplit different file starts at position 0":
    let wm = createSingleWindowManager(80, 24)
    wm.windows[0].cursor = BufferPosition(line: 5, column: 10)
    wm.windows[0].viewport.topLine = 3
    wm.windows[0].viewport.leftColumn = 2

    let newBuf = newTextBuffer()
    discard newBuf.insertText(BufferPosition(line: 0, column: 0), "New content")

    let result = wm.hsplitWithBuffer(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 5, column: 10),
      multiStatusLine = false,
      newBuf,
    )

    check result.isOk
    check wm.windows[0].cursor.line == 0
    check wm.windows[0].cursor.column == 0
    check wm.windows[0].viewport.topLine == 0
    check wm.windows[0].viewport.leftColumn == 0

  test "vsplitWithBuffer same buffer inherits cursor position":
    let wm = createSingleWindowManager(80, 24)
    let originalBuffer = wm.windows[0].buffer
    wm.windows[0].cursor = BufferPosition(line: 5, column: 10)
    wm.windows[0].viewport.topLine = 3
    wm.windows[0].viewport.leftColumn = 2

    let result = wm.vsplitWithBuffer(
      originalBuffer,
      wm.windows[0].viewport,
      BufferPosition(line: 5, column: 10),
      originalBuffer,
    )

    check result.isOk
    check wm.windows[0].cursor.line == 5
    check wm.windows[0].cursor.column == 10
    check wm.windows[0].viewport.topLine == 3
    check wm.windows[0].viewport.leftColumn == 2

  test "hsplitWithBuffer same buffer inherits cursor position":
    let wm = createSingleWindowManager(80, 24)
    let originalBuffer = wm.windows[0].buffer
    wm.windows[0].cursor = BufferPosition(line: 5, column: 10)
    wm.windows[0].viewport.topLine = 3
    wm.windows[0].viewport.leftColumn = 2

    let result = wm.hsplitWithBuffer(
      originalBuffer,
      wm.windows[0].viewport,
      BufferPosition(line: 5, column: 10),
      multiStatusLine = false,
      originalBuffer,
    )

    check result.isOk
    check wm.windows[0].cursor.line == 5
    check wm.windows[0].cursor.column == 10
    check wm.windows[0].viewport.topLine == 3
    check wm.windows[0].viewport.leftColumn == 2

suite "EditorWindowManager - Window Resize":
  test "increaseWindowWidth with single window does nothing":
    let wm = createSingleWindowManager(80, 24)
    let origWidth = wm.windows[0].viewport.width
    wm.increaseWindowWidth()
    check wm.windows[0].viewport.width == origWidth

  test "decreaseWindowWidth with single window does nothing":
    let wm = createSingleWindowManager(80, 24)
    let origWidth = wm.windows[0].viewport.width
    wm.decreaseWindowWidth()
    check wm.windows[0].viewport.width == origWidth

  test "increaseWindowHeight with single window does nothing":
    let wm = createSingleWindowManager(80, 24)
    let origHeight = wm.windows[0].viewport.height
    wm.increaseWindowHeight()
    check wm.windows[0].viewport.height == origHeight

  test "decreaseWindowHeight with single window does nothing":
    let wm = createSingleWindowManager(80, 24)
    let origHeight = wm.windows[0].viewport.height
    wm.decreaseWindowHeight()
    check wm.windows[0].viewport.height == origHeight

  test "increaseWindowWidth with two horizontal windows":
    let wm = newEditorWindowManager()
    # Left window: active
    wm.windows.add(createTestWindow(0, 0, 39, 24, active = true))
    # Right window
    wm.windows.add(createTestWindow(40, 0, 40, 24, active = false))
    wm.activeWindowIndex = 0

    wm.increaseWindowWidth()

    check wm.windows[0].viewport.width == 40
    check wm.windows[1].viewport.width == 39
    check wm.windows[1].viewport.x == 41

  test "decreaseWindowWidth with two horizontal windows":
    let wm = newEditorWindowManager()
    # Left window: active
    wm.windows.add(createTestWindow(0, 0, 39, 24, active = true))
    # Right window
    wm.windows.add(createTestWindow(40, 0, 40, 24, active = false))
    wm.activeWindowIndex = 0

    wm.decreaseWindowWidth()

    check wm.windows[0].viewport.width == 38
    check wm.windows[1].viewport.width == 41
    check wm.windows[1].viewport.x == 39

  test "increaseWindowHeight with two vertical windows":
    let wm = newEditorWindowManager()
    # Top window: active
    wm.windows.add(createTestWindow(0, 0, 80, 11, active = true))
    # Bottom window
    wm.windows.add(createTestWindow(0, 12, 80, 12, active = false))
    wm.activeWindowIndex = 0

    wm.increaseWindowHeight()

    check wm.windows[0].viewport.height == 12
    check wm.windows[1].viewport.height == 11
    check wm.windows[1].viewport.y == 13

  test "decreaseWindowHeight with two vertical windows":
    let wm = newEditorWindowManager()
    # Top window: active
    wm.windows.add(createTestWindow(0, 0, 80, 11, active = true))
    # Bottom window
    wm.windows.add(createTestWindow(0, 12, 80, 12, active = false))
    wm.activeWindowIndex = 0

    wm.decreaseWindowHeight()

    check wm.windows[0].viewport.height == 10
    check wm.windows[1].viewport.height == 13
    check wm.windows[1].viewport.y == 11

  test "increaseWindowWidth respects minimum width":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 78, 24, active = true))
    wm.windows.add(createTestWindow(79, 0, 1, 24, active = false))
    wm.activeWindowIndex = 0

    # Neighbor has width 1, cannot shrink further
    wm.increaseWindowWidth()
    check wm.windows[0].viewport.width == 78
    check wm.windows[1].viewport.width == 1

  test "decreaseWindowWidth respects minimum width":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 1, 24, active = true))
    wm.windows.add(createTestWindow(2, 0, 78, 24, active = false))
    wm.activeWindowIndex = 0

    # Active window has width 1, cannot shrink further
    wm.decreaseWindowWidth()
    check wm.windows[0].viewport.width == 1
    check wm.windows[1].viewport.width == 78

  test "increaseWindowHeight respects minimum height":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 22, active = true))
    wm.windows.add(createTestWindow(0, 23, 80, 1, active = false))
    wm.activeWindowIndex = 0

    # Neighbor has height 1, cannot shrink further
    wm.increaseWindowHeight()
    check wm.windows[0].viewport.height == 22
    check wm.windows[1].viewport.height == 1

  test "decreaseWindowHeight respects minimum height":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 1, active = true))
    wm.windows.add(createTestWindow(0, 2, 80, 22, active = false))
    wm.activeWindowIndex = 0

    # Active window has height 1, cannot shrink further
    wm.decreaseWindowHeight()
    check wm.windows[0].viewport.height == 1
    check wm.windows[1].viewport.height == 22

  test "equalizeAllWindows with two horizontal windows":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 20, 24, active = true))
    wm.windows.add(createTestWindow(21, 0, 59, 24, active = false))
    wm.activeWindowIndex = 0

    wm.equalizeAllWindows(multiStatusLine = false)

    # Both windows should have roughly equal widths
    # Total width = 80, separator = 1, available = 79, each = 39 or 40
    check wm.windows[0].viewport.width >= 39
    check wm.windows[0].viewport.width <= 40
    check wm.windows[1].viewport.width >= 39
    check wm.windows[1].viewport.width <= 40

suite "EditorWindowManager - Only Window":
  test "onlyWindow with single window does nothing":
    let wm = createSingleWindowManager(80, 24)
    wm.onlyWindow(80, 24)

    check wm.windows.len == 1
    check wm.activeWindowIndex == 0
    check wm.windows[0].viewport.width == 80
    check wm.windows[0].viewport.height == 24

  test "onlyWindow closes all other windows after vsplit":
    let wm = createSingleWindowManager(80, 24)
    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )
    check wm.windows.len == 2

    wm.onlyWindow(80, 24)

    check wm.windows.len == 1
    check wm.activeWindowIndex == 0
    check wm.windows[0].active == true
    check wm.windows[0].viewport.x == 0
    check wm.windows[0].viewport.y == 0
    check wm.windows[0].viewport.width == 80
    check wm.windows[0].viewport.height == 23 # screenHeight - steadyBottomAreaHeight()

  test "onlyWindow closes all other windows after hsplit":
    let wm = createSingleWindowManager(80, 24)
    discard wm.hsplit(
      wm.windows[0].buffer,
      wm.windows[0].viewport,
      BufferPosition(line: 0, column: 0),
      multiStatusLine = false,
    )
    check wm.windows.len == 2

    wm.onlyWindow(80, 24)

    check wm.windows.len == 1
    check wm.activeWindowIndex == 0
    check wm.windows[0].viewport.width == 80
    check wm.windows[0].viewport.height == 23 # screenHeight - steadyBottomAreaHeight()

  test "onlyWindow keeps the active window":
    let wm = createSingleWindowManager(80, 24)
    let origBuffer = wm.windows[0].buffer

    # Create a second window with a different buffer
    discard
      wm.vsplit(origBuffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0))

    # Switch to the second window (right side, index 1)
    wm.activateWindow(1)
    wm.activeWindowIndex = 1
    let activeBuffer = wm.windows[1].buffer

    wm.onlyWindow(80, 24)

    check wm.windows.len == 1
    check wm.windows[0].buffer == activeBuffer

  test "onlyWindow with multiple splits":
    let wm = createSingleWindowManager(80, 24)
    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )
    discard wm.vsplit(
      wm.windows[0].buffer, wm.windows[0].viewport, BufferPosition(line: 0, column: 0)
    )
    check wm.windows.len == 3

    wm.onlyWindow(80, 24)

    check wm.windows.len == 1
    check wm.windows[0].viewport.x == 0
    check wm.windows[0].viewport.y == 0
    check wm.windows[0].viewport.width == 80
    check wm.windows[0].viewport.height == 23 # screenHeight - steadyBottomAreaHeight()

  test "equalizeAllWindows with single window does nothing":
    let wm = createSingleWindowManager(80, 24)
    let origWidth = wm.windows[0].viewport.width
    let origHeight = wm.windows[0].viewport.height
    wm.equalizeAllWindows(multiStatusLine = false)
    check wm.windows[0].viewport.width == origWidth
    check wm.windows[0].viewport.height == origHeight

suite "EditorWindowManager - swapWindows":
  test "swapWindows with single window does nothing":
    let wm = createSingleWindowManager(80, 24)
    let origBuffer = wm.windows[0].buffer

    wm.swapWindows()

    check wm.windows.len == 1
    check wm.activeWindowIndex == 0
    check wm.windows[0].buffer == origBuffer

  test "swapWindows swaps two vsplit windows":
    let wm = newEditorWindowManager()
    let buf0 = newTextBuffer()
    discard buf0.insertText(BufferPosition(line: 0, column: 0), "Buffer 0")
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "Buffer 1")

    wm.windows.add(
      EditorWindow(
        buffer: buf0,
        viewport: ViewPort(x: 0, y: 0, width: 39, height: 24, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 3),
        active: true,
      )
    )
    wm.windows.add(
      EditorWindow(
        buffer: buf1,
        viewport:
          ViewPort(x: 40, y: 0, width: 40, height: 24, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 5),
        active: false,
      )
    )
    wm.activeWindowIndex = 0

    wm.swapWindows()

    # Active window (buf0) should now be at index 1 with the right viewport position
    check wm.activeWindowIndex == 1
    check wm.windows[1].buffer == buf0
    check wm.windows[1].viewport.x == 40
    check wm.windows[1].viewport.width == 40
    check wm.windows[1].cursor.column == 3

    # The other window (buf1) should be at index 0 with the left viewport position
    check wm.windows[0].buffer == buf1
    check wm.windows[0].viewport.x == 0
    check wm.windows[0].viewport.width == 39
    check wm.windows[0].cursor.column == 5

  test "swapWindows swaps two hsplit windows":
    let wm = newEditorWindowManager()
    let buf0 = newTextBuffer()
    discard buf0.insertText(BufferPosition(line: 0, column: 0), "Top buffer")
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "Bottom buffer")

    wm.windows.add(
      EditorWindow(
        buffer: buf0,
        viewport: ViewPort(x: 0, y: 0, width: 80, height: 11, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        active: true,
      )
    )
    wm.windows.add(
      EditorWindow(
        buffer: buf1,
        viewport:
          ViewPort(x: 0, y: 12, width: 80, height: 12, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        active: false,
      )
    )
    wm.activeWindowIndex = 0

    wm.swapWindows()

    # buf0 moved to bottom position (index 1)
    check wm.activeWindowIndex == 1
    check wm.windows[1].buffer == buf0
    check wm.windows[1].viewport.y == 12
    check wm.windows[1].viewport.height == 12

    # buf1 moved to top position (index 0)
    check wm.windows[0].buffer == buf1
    check wm.windows[0].viewport.y == 0
    check wm.windows[0].viewport.height == 11

  test "swapWindows wraps around from last window":
    let wm = newEditorWindowManager()
    let buf0 = newTextBuffer()
    let buf1 = newTextBuffer()
    let buf2 = newTextBuffer()

    wm.windows.add(
      EditorWindow(
        buffer: buf0,
        viewport: ViewPort(x: 0, y: 0, width: 26, height: 24, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        active: false,
      )
    )
    wm.windows.add(
      EditorWindow(
        buffer: buf1,
        viewport:
          ViewPort(x: 27, y: 0, width: 26, height: 24, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        active: false,
      )
    )
    wm.windows.add(
      EditorWindow(
        buffer: buf2,
        viewport:
          ViewPort(x: 54, y: 0, width: 26, height: 24, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        active: true,
      )
    )
    wm.activeWindowIndex = 2

    wm.swapWindows()

    # Last window (buf2) swaps with first window (buf0)
    check wm.activeWindowIndex == 0
    check wm.windows[0].buffer == buf2
    check wm.windows[0].viewport.x == 0
    check wm.windows[0].viewport.width == 26

    check wm.windows[2].buffer == buf0
    check wm.windows[2].viewport.x == 54
    check wm.windows[2].viewport.width == 26

    # Middle window unchanged
    check wm.windows[1].buffer == buf1

  test "swapWindows preserves cursor and scroll state":
    let wm = newEditorWindowManager()
    let buf0 = newTextBuffer()
    discard buf0.insertText(BufferPosition(line: 0, column: 0), "line1\nline2\nline3")
    let buf1 = newTextBuffer()
    discard buf1.insertText(BufferPosition(line: 0, column: 0), "other content")

    wm.windows.add(
      EditorWindow(
        buffer: buf0,
        viewport: ViewPort(x: 0, y: 0, width: 39, height: 24, topLine: 2, leftColumn: 3),
        cursor: BufferPosition(line: 2, column: 4),
        active: true,
      )
    )
    wm.windows.add(
      EditorWindow(
        buffer: buf1,
        viewport:
          ViewPort(x: 40, y: 0, width: 40, height: 24, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 7),
        active: false,
      )
    )
    wm.activeWindowIndex = 0

    wm.swapWindows()

    # buf0's cursor/scroll state should be preserved
    check wm.windows[1].buffer == buf0
    check wm.windows[1].cursor.line == 2
    check wm.windows[1].cursor.column == 4
    check wm.windows[1].viewport.topLine == 2
    check wm.windows[1].viewport.leftColumn == 3

    # buf1's cursor/scroll state should be preserved
    check wm.windows[0].buffer == buf1
    check wm.windows[0].cursor.line == 0
    check wm.windows[0].cursor.column == 7

  test "swapWindows twice returns to original layout":
    let wm = newEditorWindowManager()
    let buf0 = newTextBuffer()
    let buf1 = newTextBuffer()

    wm.windows.add(
      EditorWindow(
        buffer: buf0,
        viewport: ViewPort(x: 0, y: 0, width: 39, height: 24, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        active: true,
      )
    )
    wm.windows.add(
      EditorWindow(
        buffer: buf1,
        viewport:
          ViewPort(x: 40, y: 0, width: 40, height: 24, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        active: false,
      )
    )
    wm.activeWindowIndex = 0

    wm.swapWindows()
    wm.swapWindows()

    # Should be back to original: buf0 at index 0 (left), buf1 at index 1 (right)
    check wm.windows[0].buffer == buf0
    check wm.windows[0].viewport.x == 0
    check wm.windows[0].viewport.width == 39
    check wm.windows[1].buffer == buf1
    check wm.windows[1].viewport.x == 40
    check wm.windows[1].viewport.width == 40
    check wm.activeWindowIndex == 0
