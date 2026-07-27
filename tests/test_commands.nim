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

## Tests for commands.nim

import std/unittest
import ../src/moepkg/[buffer, motion, render_utils, types]

suite "ViewportManager - Goto Line Scrolling":
  proc createTestBuffer(lineCount: int): TextBuffer =
    ## Create a buffer with specified number of lines
    var lines = ""
    for i in 1 .. lineCount:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)
    result = newTextBuffer(lines)

  test "viewport scrolls when jumping to line far below":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    # Jump to line 100 (0-based index: 99)
    let targetLine = 99
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    # Line 100 should be visible
    let visibleHeight = viewportManager.viewport.height - steadyBottomAreaHeight()
    let maxVisibleLine = viewportManager.viewport.topLine + visibleHeight - 1

    check targetLine >= viewportManager.viewport.topLine
    check targetLine <= maxVisibleLine
    check viewportManager.viewport.topLine > 70

  test "viewport scrolls when jumping to line far above":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 80, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    # Jump to line 10 (0-based index: 9)
    let targetLine = 9
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    check targetLine >= viewportManager.viewport.topLine
    check viewportManager.viewport.topLine <= 9

  test "viewport does not scroll if target line is already visible":
    let buffer = createTestBuffer(100)
    let initialTopLine = 40
    let viewportManager = ViewportManager(
      viewport: ViewPort(
        topLine: initialTopLine, leftColumn: 0, height: 20, width: 80, x: 0, y: 0
      )
    )

    # Jump to line 50 (already visible)
    let targetLine = 50
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    check viewportManager.viewport.topLine >= initialTopLine - 1
    check viewportManager.viewport.topLine <= initialTopLine + 1

  test "viewport scrolls to first line":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 80, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let cursorPos = CursorPosition(x: 0, y: 0)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    check viewportManager.viewport.topLine == 0

  test "viewport scrolls to last line":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    let visibleHeight = viewportManager.viewport.height - steadyBottomAreaHeight()
    let maxVisibleLine = viewportManager.viewport.topLine + visibleHeight - 1

    check lastLine >= viewportManager.viewport.topLine
    check lastLine <= maxVisibleLine

suite "ViewportManager - Line Wrap Scrolling":
  proc createTestBuffer(lineCount: int): TextBuffer =
    var lines = ""
    for i in 1 .. lineCount:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)
    result = newTextBuffer(lines)

  test "lineWrap: viewport scrolls to last line":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      viewportOffset = 0,
      tabStop = 4,
    )

    # Cursor must be visible
    check lastLine >= viewportManager.viewport.topLine
    check viewportManager.viewport.topLine > 0

  test "lineWrap: viewport scrolls to line far below":
    let buffer = createTestBuffer(1000)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 30, width: 80, x: 0, y: 0)
    )

    let targetLine = 999
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      viewportOffset = 0,
      tabStop = 4,
    )

    check targetLine >= viewportManager.viewport.topLine
    check viewportManager.viewport.topLine > 900

  test "lineWrap: viewport stays when cursor is visible":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 10, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let targetLine = 15
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      viewportOffset = 0,
      tabStop = 4,
    )

    # topLine should not change since cursor is already visible
    check viewportManager.viewport.topLine == 10

  test "lineWrap: viewport scrolls up":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 50, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    let cursorPos = CursorPosition(x: 0, y: 5)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      viewportOffset = 0,
      tabStop = 4,
    )

    check viewportManager.viewport.topLine == 5

  proc createLongLineBuffer(lineCount: int, lineWidth: int): TextBuffer =
    ## Create a buffer where each line has `lineWidth` characters (all 'a').
    var lines = ""
    for i in 1 .. lineCount:
      if i > 1:
        lines.add("\n")
      for j in 1 .. lineWidth:
        lines.add('a')
    result = newTextBuffer(lines)

  test "lineWrap: viewport scrolls to last line with wrapped lines":
    # Each line: 40 chars, viewport width 20 → 2 screen lines per logical line.
    # visibleHeight = 20 - 1 = 19. budget = 19 (cursorWrapOffset=0).
    # 9 lines × 2 = 18 < 19, 10 lines × 2 = 20 (not < 19) → topLine = lastLine - 9.
    let buffer = createLongLineBuffer(50, 40)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 20, x: 0, y: 0)
    )

    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      viewportOffset = 0,
      tabStop = 4,
    )

    check viewportManager.viewport.topLine == lastLine - 9

  test "lineWrap: viewport scrolls with cursor at non-zero wrap offset":
    # Each line: 40 chars, viewport width 20 → 2 screen lines per logical line.
    # Cursor at column 25 → cursorWrapOffset = 1.
    # visibleHeight = 19, budget = 19 - 1 = 18.
    # 8 lines × 2 = 16 < 18, 9 lines × 2 = 18 (not < 18) → topLine = lastLine - 8.
    let buffer = createLongLineBuffer(50, 40)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 20, x: 0, y: 0)
    )

    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 25, y: lastLine)

    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
      lineWrap = true,
      buffer = buffer,
      viewportOffset = 0,
      tabStop = 4,
    )

    check viewportManager.viewport.topLine == lastLine - 8

suite "ViewportManager - Default reservedLines":
  proc createTestBuffer(lineCount: int): TextBuffer =
    var lines = ""
    for i in 1 .. lineCount:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)
    result = newTextBuffer(lines)

  test "updateViewport default reservedLines matches steadyBottomAreaHeight()":
    ## When reservedLines is omitted (default = -1), the auto-calculated value
    ## for showStatusLine=true should equal steadyBottomAreaHeight().
    let buffer = createTestBuffer(100)

    # Explicit reservedLines = steadyBottomAreaHeight()
    let vmExplicit = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )
    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    vmExplicit.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = steadyBottomAreaHeight(),
    )

    # Default reservedLines (omitted → auto-calculated)
    let vmDefault = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    vmDefault.updateViewport(cursorPos, buffer.len, showStatusLine = true)

    check vmExplicit.viewport.topLine == vmDefault.viewport.topLine
