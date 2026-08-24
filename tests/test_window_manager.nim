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

import std/[unittest, options, os, strutils]
import pkg/results
import ../src/moepkg/window_manager {.all.}
import ../src/moepkg/[types, buffer, render_utils, logger]

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

proc viewportsOverlap(a, b: ViewPort): bool =
  ## Independent overlap check: two axis-aligned rectangles overlap when
  ## both the x and y intervals intersect. Kept independent of the
  ## implementation's predicate so tests cannot mask an off-by-one.
  max(a.x, b.x) < min(a.x + a.width, b.x + b.width) and
    max(a.y, b.y) < min(a.y + a.height, b.y + b.height)

proc checkNoOverlappingWindows(wm: EditorWindowManager, allowTiny: bool = false) =
  ## Assert no pair of windows overlaps. allowTiny tolerates overlaps
  ## involving a 1-cell window (expected degradation on tiny screens).
  for i in 0 ..< wm.windows.len:
    for j in i + 1 ..< wm.windows.len:
      let
        a = wm.windows[i].viewport
        b = wm.windows[j].viewport
      let fullySized = a.width > 1 and a.height > 1 and b.width > 1 and b.height > 1
      check not (viewportsOverlap(a, b) and (not allowTiny or fullySized))

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

suite "EditorWindowManager - Layout invariants (S10)":
  test "equalizeWidthsInGroup keeps widths positive when fixed widths overflow":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 49, 24))
    wm.activeWindowIndex = 1

    # fixedWidth + separator exceeds totalWidth: the flex window must stay positive
    wm.equalizeWidthsInGroup(@[0, 1], 30, 0)

    check wm.windows[1].viewport.width >= 1
    # The clamped 1-cell window must not stick out past the group's right end
    check wm.windows[1].viewport.x + wm.windows[1].viewport.width <= 30

  test "equalizeWidthsForResize keeps widths positive when fixed widths overflow":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 49, 24))
    wm.activeWindowIndex = 1

    wm.equalizeWidthsForResize(@[0, 1], 30)

    check wm.windows[1].viewport.width >= 1

  test "resize shifts flex windows right of an oversized fixed-width window":
    # FileTree + split right column at 60 cols: the right column's scaled x
    # lands inside the FileTree span; shift the flex windows right of it.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24, active = true))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 49, 12))
    wm.windows.add(createTestWindow(31, 13, 49, 11))
    wm.activeWindowIndex = 0

    wm.resizeWindows(60, 24, 80, 24, multiStatusLine = false)

    # The fixed window keeps its width; both flex windows move right of it
    check wm.windows[0].viewport.width == 30
    check wm.windows[1].viewport.x >= 31
    check wm.windows[2].viewport.x >= 31
    check wm.windows[1].viewport.x + wm.windows[1].viewport.width <= 60
    check wm.windows[2].viewport.x + wm.windows[2].viewport.width <= 60
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
    checkNoOverlappingWindows(wm)

  test "resize shifts a flex group right of an oversized fixed-width window":
    # Same with a two-window flex group under the fixed window: the whole
    # group starts right of it.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24, active = true))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 25, 12))
    wm.windows.add(createTestWindow(57, 0, 23, 12))
    wm.activeWindowIndex = 0

    wm.resizeWindows(60, 24, 80, 24, multiStatusLine = false)

    check wm.windows[1].viewport.x >= 31
    check wm.windows[2].viewport.x >= 31
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
    checkNoOverlappingWindows(wm)

  test "resize keeps a nested T-junction column on screen":
    # A T-junction: the left column (one group) must stop at the right
    # column's differing height, or it extends over it and shoves it
    # off the screen edge.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 26, 12))
    wm.windows.add(createTestWindow(27, 0, 26, 12))
    wm.windows.add(createTestWindow(54, 0, 26, 4))
    wm.windows.add(createTestWindow(54, 5, 26, 7))
    wm.activeWindowIndex = 0

    wm.resizeWindows(60, 12, 80, 12, multiStatusLine = false)

    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.x >= 0
      check win.viewport.x + win.viewport.width <= 60
    checkNoOverlappingWindows(wm)

  test "closing a unique-dimension column re-tiles with multi status lines":
    # The closeWindow fallback must keep the invariants on the
    # multiStatusLine path too (its height arithmetic differs).
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 50, 24, active = true))
    wm.windows.add(createTestWindow(51, 0, 49, 12))
    wm.windows.add(createTestWindow(51, 13, 49, 11))
    wm.activeWindowIndex = 0

    discard wm.closeWindow(multiStatusLine = true)

    check wm.windows.len == 2
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.x >= 0
      check win.viewport.y >= 0
    checkNoOverlappingWindows(wm)

  test "equalizeHeightsForResize keeps heights positive on tiny screens":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 10, active = true))
    wm.windows.add(createTestWindow(0, 11, 80, 10))
    wm.activeWindowIndex = 0

    # 2 rows on a 2-row screen: total content must not go negative
    wm.equalizeHeightsForResize(@[0, 1], 2, multiStatusLine = false)

    for win in wm.windows:
      check win.viewport.height >= 1

  test "equalizeHeightsForResize stops a single window at a lower neighbor":
    # A single-element vertical group (gap exceeds the ±1 tolerance) must
    # stop at the lower neighbor's top instead of the screen bottom.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 10, active = true))
    wm.windows.add(createTestWindow(0, 12, 80, 10))
    wm.activeWindowIndex = 0

    wm.equalizeHeightsForResize(@[0], 24, multiStatusLine = false)

    # Stops at the lower neighbor: 12 (neighbor top) - 0 (minY) - 0, not 24 - 0
    check wm.windows[0].viewport.height == 12
    check wm.windows[0].viewport.y + wm.windows[0].viewport.height <=
      wm.windows[1].viewport.y

  test "closing a unique-dimension column re-tiles the rest (nested layout)":
    # :vsplit → right :split → left :q: the full-height left column matches
    # no remaining window; the fallback must reclaim its space.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 50, 24, active = true))
    wm.windows.add(createTestWindow(51, 0, 49, 12))
    wm.windows.add(createTestWindow(51, 13, 49, 11))
    wm.activeWindowIndex = 0

    discard wm.closeWindow(multiStatusLine = false)

    check wm.windows.len == 2
    # Remaining windows span the full width: no dead space on the left
    check wm.windows[0].viewport.x == 0
    check wm.windows[1].viewport.x == 0
    check wm.windows[0].viewport.x + wm.windows[0].viewport.width == 100
    check wm.windows[1].viewport.x + wm.windows[1].viewport.width == 100
    # Stacked without overlap
    check wm.windows[0].viewport.y + wm.windows[0].viewport.height <=
      wm.windows[1].viewport.y

  test "closing a unique-dimension row re-tiles the rest (nested layout)":
    # :hsplit → bottom :vsplit → top :q: the full-width top row matches no
    # remaining window; the fallback reclaims its space.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 100, 12, active = true))
    wm.windows.add(createTestWindow(0, 13, 50, 11))
    wm.windows.add(createTestWindow(51, 13, 49, 11))
    wm.activeWindowIndex = 0

    discard wm.closeWindow(multiStatusLine = false)

    check wm.windows.len == 2
    # Remaining windows span the full height: no dead space on top
    check wm.windows[0].viewport.y == 0
    check wm.windows[1].viewport.y == 0
    check wm.windows[0].viewport.y + wm.windows[0].viewport.height == 24
    check wm.windows[1].viewport.y + wm.windows[1].viewport.height == 24
    # Side by side without overlap
    check wm.windows[0].viewport.x + wm.windows[0].viewport.width <=
      wm.windows[1].viewport.x

  test "zero-height window still detects the right neighbor boundary":
    # A 0-height window must not swallow the right column; it bounds as one row tall.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 5, 40, 0, active = true))
    wm.windows.add(createTestWindow(41, 5, 39, 10))
    wm.activeWindowIndex = 0

    wm.equalizeWidthsForResize(@[0], 100)

    # Stops at the right column: 41 - 1 (separator) - 0 = 40
    check wm.windows[0].viewport.width == 40

  test "multi-window group with a zero-height head still bounds its width":
    # A group with a 0-row head must still detect the right neighbor in its band.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 0))
    wm.windows.add(createTestWindow(41, 0, 39, 12))
    wm.windows.add(createTestWindow(30, 0, 40, 10))
    wm.activeWindowIndex = 0

    wm.equalizeWidthsForResize(@[0, 1], 100)

    # Right boundary = 30: the group must not extend over the neighbor
    check wm.windows[0].viewport.x + wm.windows[0].viewport.width <= 30
    check wm.windows[1].viewport.x + wm.windows[1].viewport.width <= 30
    for win in wm.windows:
      check win.viewport.width >= 1

  test "resize bounds a group at a T-junction corner touching its top":
    # A neighbor row touching the group's top (T-junction corner) still
    # bounds the group's extension even without vertical overlap.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 5, 40, 10))
    wm.windows.add(createTestWindow(41, 5, 39, 10))
    wm.windows.add(createTestWindow(30, 0, 20, 5))
    wm.activeWindowIndex = 0

    wm.equalizeWidthsForResize(@[0, 1], 100)

    # Right boundary = 30: the group stops at the corner neighbor
    check wm.windows[0].viewport.x + wm.windows[0].viewport.width <= 30
    check wm.windows[1].viewport.x + wm.windows[1].viewport.width <= 30
    for win in wm.windows:
      check win.viewport.width >= 1

  test "continuous downscale keeps windows positive and non-overlapping":
    # Regression: ratio-scaling truncated a height-1 window to 0, which then
    # expanded to full width and overlapped the right column.
    let wm = newEditorWindowManager()
    # Tall-left + stacked-right (mismatched heights → single-element groups)
    wm.windows.add(createTestWindow(0, 0, 40, 20, active = true))
    wm.windows.add(createTestWindow(41, 0, 39, 10))
    wm.windows.add(createTestWindow(41, 11, 39, 9))
    wm.activeWindowIndex = 0

    var
      oldWidth = 80
      oldHeight = 20
    for newHeight in countdown(19, 3):
      wm.resizeWindows(60, newHeight, oldWidth, oldHeight, multiStatusLine = false)
      oldWidth = 60
      oldHeight = newHeight
      for win in wm.windows:
        check win.viewport.width >= 1
        check win.viewport.height >= 1
      checkNoOverlappingWindows(wm)

  test "closing a window in a complex nested layout stacks the rest (last resort)":
    # No two windows share x/width or y/height and the closed window's dims
    # match none of them: only the vertical-stack fallback can re-tile the box.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 5))
    wm.windows.add(createTestWindow(31, 6, 25, 5))
    wm.windows.add(createTestWindow(57, 12, 20, 5))
    wm.windows.add(createTestWindow(0, 18, 77, 1, active = true))
    wm.activeWindowIndex = 3

    discard wm.closeWindow(multiStatusLine = false)

    check wm.windows.len == 3
    # All windows stacked over the full bounding box (0,0)-(77,19)
    for win in wm.windows:
      check win.viewport.x == 0
      check win.viewport.width == 77
      check win.viewport.height >= 1
      check win.viewport.y >= 0
      check win.viewport.y + win.viewport.height <= 19
    # Stacked without overlap
    checkNoOverlappingWindows(wm)

  test "validateViewportInvariants detects non-positive dimensions":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 24))
    wm.windows.add(createTestWindow(0, 25, 0, 24))
    when defined(release):
      skip()
    else:
      expect AssertionDefect:
        wm.validateViewportInvariants()

  test "validateViewportInvariants detects overlapping windows":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24))
    wm.windows.add(createTestWindow(30, 0, 40, 24))
    when defined(release):
      skip()
    else:
      expect AssertionDefect:
        wm.validateViewportInvariants()

  test "validateViewportInvariants warns on windows outside the screen":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(-10, 0, 80, 24))
    let oldLogger = getGlobalLogger()
    let oldDir = getCurrentDir()
    # Per-process temp dir so the test cannot clobber a real ./moe-debug.log
    # or collide with parallel test processes.
    let logDir = getTempDir() / "moe-window-manager-log-" & $getCurrentProcessId()
    let logPath = logDir / "moe-debug.log"
    createDir(logDir)
    setCurrentDir(logDir)
    let newLogger = initLogger(LogLevel.Warn, enabled = true, clearOnStart = true)
    defer:
      # Close the logger first so its fd is not leaked.
      close(newLogger)
      setGlobalLogger(oldLogger)
      setCurrentDir(oldDir)
      removeFile(logPath)
      removeDir(logDir)
    setGlobalLogger(newLogger)
    # Screen-bound violations are warn-only: no crash, but a log entry
    wm.validateViewportInvariants(80, 24)
    check fileExists(logPath)
    check readFile(logPath).contains("outside the screen")

  test "tiny screen keeps the last window out of the next band":
    # Regression: the non-last windows' 1-cell floor plus a separator row
    # used to push the last window into the band below; the separator row
    # must be dropped instead.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 8))
    wm.windows.add(createTestWindow(0, 9, 30, 8))
    wm.windows.add(createTestWindow(0, 16, 15, 8))
    wm.windows.add(createTestWindow(16, 16, 14, 8))
    wm.windows.add(createTestWindow(31, 0, 49, 24))
    wm.activeWindowIndex = 0

    wm.resizeWindows(80, 3, 80, 24, multiStatusLine = false)

    # Windows 0..1 fit in rows 0..2 without a separator instead of shoving
    # window 1 into the band below at y == 2
    check wm.windows[1].viewport.y == 1
    check wm.windows[1].viewport.height == 1
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
    checkNoOverlappingWindows(wm)

  test "resize keeps windows positive and non-overlapping with multi status lines":
    # Per-window status-line arithmetic must keep the same invariants on a tiny screen.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 10, active = true))
    wm.windows.add(createTestWindow(0, 11, 80, 10))
    wm.activeWindowIndex = 0

    wm.resizeWindows(80, 3, 80, 24, multiStatusLine = true)

    check wm.windows[1].viewport.y + wm.windows[1].viewport.height <= 3
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
    checkNoOverlappingWindows(wm)

  test "resize keeps the last flex window off the right column (group overflow)":
    # FileTree(30) | X | C/D: on a narrow screen the group overflows the
    # space before the right column, so the last flex window slides left
    # instead of being drawn over it.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 30, 24))
    wm.windows.add(createTestWindow(61, 0, 30, 12))
    wm.windows.add(createTestWindow(61, 13, 30, 11))
    wm.activeWindowIndex = 0

    wm.resizeWindows(47, 24, 90, 24, multiStatusLine = false)

    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.x >= 0
      check win.viewport.x + win.viewport.width <= 47
    checkNoOverlappingWindows(wm)

  test "resize keeps a squeezed single window off its neighbors":
    # A squeezed single window: its scaled x lands inside the left neighbor
    # and the gap to the right column is too narrow, so it is pulled back
    # to the boundary.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 30, 12))
    wm.windows.add(createTestWindow(31, 13, 30, 11))
    wm.windows.add(createTestWindow(61, 0, 30, 24))
    wm.activeWindowIndex = 0

    wm.resizeWindows(47, 24, 90, 24, multiStatusLine = false)

    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.x >= 0
      check win.viewport.x + win.viewport.width <= 47
    checkNoOverlappingWindows(wm)

  test "resize clamps a fixed-width member wider than the available space":
    # A fixed-width window wider than the screen must shrink so nothing
    # overlaps the right column.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 30, 24))
    wm.windows.add(createTestWindow(61, 0, 30, 12))
    wm.windows.add(createTestWindow(61, 13, 30, 11))
    wm.activeWindowIndex = 0

    wm.resizeWindows(30, 24, 90, 24, multiStatusLine = false)

    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.x >= 0
      check win.viewport.x + win.viewport.width <= 30
    checkNoOverlappingWindows(wm)

  test "closing a unique-dimension column re-tiles a 2-row box":
    # The column fallback must drop the separator on a box too small to
    # hold it, so the last window stays inside the box.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 50, 2, active = true))
    wm.windows.add(createTestWindow(51, 0, 49, 1))
    wm.windows.add(createTestWindow(51, 1, 49, 1))
    wm.activeWindowIndex = 0

    discard wm.closeWindow(multiStatusLine = false)

    check wm.windows.len == 2
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.x == 0
      check win.viewport.width == 100
      check win.viewport.y >= 0
      check win.viewport.y + win.viewport.height <= 2
    checkNoOverlappingWindows(wm)

  test "closing a unique-dimension column re-tiles a 2-row box with multi status lines":
    # The multiStatusLine column fallback keeps the invariants on a box too
    # small for per-window status lines.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 50, 2, active = true))
    wm.windows.add(createTestWindow(51, 0, 49, 1))
    wm.windows.add(createTestWindow(51, 1, 49, 1))
    wm.activeWindowIndex = 0

    discard wm.closeWindow(multiStatusLine = true)

    check wm.windows.len == 2
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.x == 0
      check win.viewport.width == 100
      check win.viewport.y >= 0
      # Regression: an uncapped (content + status) height pushed the last
      # window below the 2-row box.
      check win.viewport.y + win.viewport.height <= 2
    checkNoOverlappingWindows(wm)

  test "resize keeps a vertical column from widening over a shorter row":
    # Regression: re-alignment copied the top member's width onto every
    # column member, widening a lower-left member over its row-mates.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 12))
    wm.windows.add(createTestWindow(41, 0, 39, 12))
    wm.windows.add(createTestWindow(0, 13, 40, 11))
    wm.windows.add(createTestWindow(41, 13, 19, 11))
    wm.windows.add(createTestWindow(61, 13, 19, 11))
    wm.activeWindowIndex = 0

    wm.resizeWindows(100, 24, 80, 24, multiStatusLine = false)

    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.x >= 0
      check win.viewport.x + win.viewport.width <= 100
    # The lower-left member must stay inside its own 3-member row.
    check wm.windows[2].viewport.x + wm.windows[2].viewport.width <=
      wm.windows[3].viewport.x
    checkNoOverlappingWindows(wm)

  test "multiStatusLine keeps the last window inside a tiny box":
    # Regression: uncapped (content + status) rows pushed the last window's
    # 1-row floor below the box end.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 24))
    wm.windows.add(createTestWindow(0, 25, 80, 24))
    wm.activeWindowIndex = 0

    wm.equalizeHeightsInGroup(@[0, 1], 2, 0, multiStatusLine = true)

    for win in wm.windows:
      check win.viewport.height >= 1
      check win.viewport.y >= 0
      check win.viewport.y + win.viewport.height <= 2

  test "equalizeHeightsForResize keeps the last window in a tiny box with multi status lines":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 10))
    wm.windows.add(createTestWindow(0, 11, 80, 10))
    wm.activeWindowIndex = 0

    wm.equalizeHeightsForResize(@[0, 1], 2, multiStatusLine = true)

    for win in wm.windows:
      check win.viewport.height >= 1
      check win.viewport.y >= 0
      check win.viewport.y + win.viewport.height <= 2

  test "resize on a tiny screen keeps the bottom window on-screen with multi status lines":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 10, active = true))
    wm.windows.add(createTestWindow(0, 11, 80, 10))
    wm.activeWindowIndex = 0

    wm.resizeWindows(80, 2, 80, 24, multiStatusLine = true)

    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
      check win.viewport.y >= 0
      check win.viewport.y + win.viewport.height <= 2
    checkNoOverlappingWindows(wm)

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

suite "EditorWindowManager - Layout invariants (tiny-resize roundtrip)":
  proc checkWindowManagerInvariants(wm: EditorWindowManager, allowTiny: bool = false) =
    ## Windows must stay positive-sized and fully-sized windows must not
    ## overlap; a 1-cell window is the expected degradation on tiny screens
    ## (matching validateViewportInvariants), so allowTiny tolerates it.
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
    checkNoOverlappingWindows(wm, allowTiny)

  proc createVsplitHsplit(): EditorWindowManager =
    ## :vsplit then :hsplit on the right pane: full-height left column,
    ## split right column.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 24))
    wm.windows.add(createTestWindow(41, 0, 39, 12))
    wm.windows.add(createTestWindow(41, 13, 39, 11))
    wm.activeWindowIndex = 0
    wm

  test "vsplit+hsplit roundtrip through a 3-row terminal":
    # Regression: shrink to 3 rows and grow back used to overlap the right
    # column's bottom window with the left column.
    let wm = createVsplitHsplit()
    wm.resizeWindows(5, 3, 80, 24, multiStatusLine = true)
    wm.resizeWindows(80, 24, 5, 3, multiStatusLine = true)
    checkWindowManagerInvariants(wm)

  test "vsplit+hsplit roundtrip through a 3-row terminal to another size":
    let wm = createVsplitHsplit()
    wm.resizeWindows(5, 3, 80, 24, multiStatusLine = true)
    wm.resizeWindows(60, 18, 5, 3, multiStatusLine = true)
    checkWindowManagerInvariants(wm)

  test "vsplit+hsplit roundtrips at odd widths on a 3-row terminal":
    for w in [3, 7, 21, 39]:
      let wm = createVsplitHsplit()
      wm.resizeWindows(w, 3, 80, 24, multiStatusLine = true)
      wm.resizeWindows(80, 24, w, 3, multiStatusLine = true)
      checkWindowManagerInvariants(wm)

  test "hsplit+vsplit roundtrip through a 2-row terminal":
    # :hsplit then :vsplit on the bottom pane: full-width top window, bottom
    # row split into two windows.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 12))
    wm.windows.add(createTestWindow(0, 13, 40, 11))
    wm.windows.add(createTestWindow(41, 13, 39, 11))
    wm.activeWindowIndex = 0

    wm.resizeWindows(4, 2, 80, 24, multiStatusLine = true)
    wm.resizeWindows(58, 27, 4, 2, multiStatusLine = true)
    checkWindowManagerInvariants(wm)

  test "vsplit+hsplit multi-step chain with single status line":
    let wm = createVsplitHsplit()
    var
      oldWidth = 80
      oldHeight = 24
    for (newWidth, newHeight) in [(10, 4), (64, 13), (8, 2), (38, 15)]:
      wm.resizeWindows(
        newWidth, newHeight, oldWidth, oldHeight, multiStatusLine = false
      )
      oldWidth = newWidth
      oldHeight = newHeight
    checkWindowManagerInvariants(wm)

  test "hsplit+vsplit roundtrip through a 2-row terminal with single status line":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 80, 12))
    wm.windows.add(createTestWindow(0, 13, 40, 11))
    wm.windows.add(createTestWindow(41, 13, 39, 11))
    wm.activeWindowIndex = 0

    wm.resizeWindows(4, 2, 80, 24, multiStatusLine = false)
    wm.resizeWindows(62, 19, 4, 2, multiStatusLine = false)
    checkWindowManagerInvariants(wm)

  test "FileTree column stays clear of the fixed-width sidebar":
    # A sidebar wider than the screen must squeeze the right column away
    # from it instead of overlapping after a tiny-screen excursion.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 49, 12))
    wm.windows.add(createTestWindow(31, 13, 49, 11))
    wm.activeWindowIndex = 0

    var
      oldWidth = 80
      oldHeight = 24
    for (newWidth, newHeight) in [
      (68, 29), (8, 2), (34, 19), (6, 4), (44, 25), (4, 2), (30, 15)
    ]:
      wm.resizeWindows(newWidth, newHeight, oldWidth, oldHeight, multiStatusLine = true)
      oldWidth = newWidth
      oldHeight = newHeight
    # 30 columns cannot fit the sidebar next to the right column: 1-cell
    # windows are the expected degradation.
    checkWindowManagerInvariants(wm, allowTiny = true)

  test "2x2 grid roundtrip through a tiny terminal":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 40, 12))
    wm.windows.add(createTestWindow(41, 0, 39, 12))
    wm.windows.add(createTestWindow(0, 13, 40, 11))
    wm.windows.add(createTestWindow(41, 13, 39, 11))
    wm.activeWindowIndex = 0

    wm.resizeWindows(3, 5, 80, 24, multiStatusLine = true)
    wm.resizeWindows(80, 24, 3, 5, multiStatusLine = true)
    checkWindowManagerInvariants(wm)

  test "zero-height right neighbor still bounds the left window":
    # A 0-height window at the left window's top must still bound its width.
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 10, 2))
    wm.windows.add(createTestWindow(10, 0, 9, 0))
    wm.windows.add(createTestWindow(10, 3, 9, 2))
    wm.activeWindowIndex = 0

    wm.resizeWindows(20, 6, 20, 6, multiStatusLine = false)
    # A 20x6 end size can squeeze a window to 1 cell: expected degradation.
    checkWindowManagerInvariants(wm, allowTiny = true)

suite "EditorWindowManager - Layout invariant diagnostics":
  proc withCapturedWindowManagerLog(body: proc(logPath: string)) =
    let oldLogger = getGlobalLogger()
    let oldDir = getCurrentDir()
    let logDir = getTempDir() / "moe-window-manager-log-" & $getCurrentProcessId()
    let logPath = logDir / "moe-debug.log"
    createDir(logDir)
    setCurrentDir(logDir)
    let newLogger = initLogger(LogLevel.Warn, enabled = true, clearOnStart = true)
    setGlobalLogger(newLogger)
    try:
      body(logPath)
    finally:
      # Close the logger first so its fd is not leaked.
      close(newLogger)
      setGlobalLogger(oldLogger)
      setCurrentDir(oldDir)
      removeFile(logPath)
      removeDir(logDir)

  test "equalizeWidthsInGroup warns when the last window cannot fit":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 49, 24))
    withCapturedWindowManagerLog(
      proc(logPath: string) =
        # fixedWidth(30) + separator(1) exceeds totalWidth(30)
        wm.equalizeWidthsInGroup(@[0, 1], 30, 0)
        check readFile(logPath).contains("last window does not fit")
    )

  test "equalizeWidthsForResize warns when the last window cannot fit":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows.add(createTestWindow(31, 0, 30, 12))
    wm.windows.add(createTestWindow(31, 13, 30, 11))
    withCapturedWindowManagerLog(
      proc(logPath: string) =
        # Three windows need at least 5 columns (1+1+1+sep+sep) on a 3-wide box
        wm.equalizeWidthsForResize(@[0, 1, 2], 3)
        check readFile(logPath).contains("last window does not fit")
    )

  test "equalizeHeightsInGroup warns when the last window cannot fit":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 8))
    wm.windows.add(createTestWindow(0, 9, 30, 8))
    wm.windows.add(createTestWindow(0, 16, 30, 8))
    withCapturedWindowManagerLog(
      proc(logPath: string) =
        # Three windows need at least 3 rows (1+1+1) plus separators/status
        wm.equalizeHeightsInGroup(@[0, 1, 2], 2, 0, multiStatusLine = false)
        check readFile(logPath).contains("last window does not fit")
    )

  test "equalizeHeightsForResize warns when the last window cannot fit":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 8))
    wm.windows.add(createTestWindow(0, 9, 30, 8))
    wm.windows.add(createTestWindow(0, 16, 30, 8))
    withCapturedWindowManagerLog(
      proc(logPath: string) =
        # Command-line reserve leaves a 1-row box for three windows
        wm.equalizeHeightsForResize(@[0, 1, 2], 2, multiStatusLine = false)
        check readFile(logPath).contains("last window does not fit")
    )

  test "resizeWindows on a tiny screen keeps all windows positive and non-overlapping":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows.add(createTestWindow(31, 0, 49, 12))
    wm.windows.add(createTestWindow(31, 13, 49, 11))
    # A 2-column terminal cannot tile three windows side by side; the
    # endpoint must still normalize sizes and leave no overlaps.
    wm.resizeWindows(2, 24, 80, 24, multiStatusLine = false)
    for win in wm.windows:
      check win.viewport.width >= 1
      check win.viewport.height >= 1
    checkNoOverlappingWindows(wm)

  test "resizeWindows warns about a fixed-width sidebar outside the screen":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 49, 12))
    wm.windows.add(createTestWindow(31, 13, 49, 11))
    withCapturedWindowManagerLog(
      proc(logPath: string) =
        # The sidebar legitimately exceeds the 20-column screen; the
        # end-point check must receive the screen dims and warn about it.
        wm.resizeWindows(20, 24, 80, 24, multiStatusLine = false)
        check readFile(logPath).contains("outside the screen")
    )

  test "closeWindow passes screen dimensions to the invariant check":
    let wm = newEditorWindowManager()
    wm.windows.add(createTestWindow(0, 0, 30, 24))
    wm.windows[0].fixedWidth = some(30)
    wm.windows.add(createTestWindow(31, 0, 49, 12))
    wm.windows.add(createTestWindow(31, 13, 49, 11))
    wm.activeWindowIndex = 1
    withCapturedWindowManagerLog(
      proc(logPath: string) =
        # Re-tiling after the close overflows the 20-column screen; the
        # end-point check must receive the screen dims to flag it.
        discard
          wm.closeWindow(multiStatusLine = false, screenWidth = 20, screenHeight = 24)
        check readFile(logPath).contains("outside the screen")
    )
