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

import std/[strutils, unittest]
import ../src/moepkg/[buffer, render_utils, types]
import ../src/moepkg/motion {.all.}

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
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
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
      viewport: ViewPort(topLine: 80, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
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
        topLine: initialTopLine, leftCell: 0, height: 20, width: 80, x: 0, y: 0
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
      viewport: ViewPort(topLine: 80, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
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
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
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
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
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
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 30, width: 80, x: 0, y: 0)
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
      viewport: ViewPort(topLine: 10, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
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

  test "lineWrap: viewport keeps a mid-wrap top when the cursor stays visible":
    # A 40 cell line wrapped at width 10 gives 4 segments. The viewport starts
    # two segments into line 0, so line 1 is drawn whole on screen row 2 of the
    # 4 row text area.
    let buffer = newTextBuffer("a".repeat(40) & "\n" & "b".repeat(10))
    let viewportManager = ViewportManager(
      viewport: ViewPort(
        topLine: 0, topWrapOffset: 2, leftCell: 0, height: 5, width: 10, x: 0, y: 0
      )
    )

    viewportManager.updateViewport(
      CursorPosition(x: 0, y: 1),
      buffer.len,
      showStatusLine = true,
      reservedLines = 1,
      lineWrap = true,
      buffer = buffer,
      viewportOffset = 0,
      tabStop = 4,
    )

    check viewportManager.viewport.topLine == 0
    check viewportManager.viewport.topWrapOffset == 2

  test "lineWrap: a line sticking out below a mid-wrap top comes into view whole":
    let buffer = newTextBuffer("a".repeat(40) & "\n" & "b".repeat(40))
    let viewportManager = ViewportManager(
      viewport: ViewPort(
        topLine: 0, topWrapOffset: 2, leftCell: 0, height: 5, width: 10, x: 0, y: 0
      )
    )

    viewportManager.updateViewport(
      CursorPosition(x: 0, y: 1),
      buffer.len,
      showStatusLine = true,
      reservedLines = 1,
      lineWrap = true,
      buffer = buffer,
      viewportOffset = 0,
      tabStop = 4,
    )

    check viewportManager.viewport.topLine == 1
    check viewportManager.viewport.topWrapOffset == 0

  test "lineWrap: viewport scrolls up":
    let buffer = createTestBuffer(100)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 50, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
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

    # Far above, the cursor comes to the middle, which the buffer's start cuts.
    check viewportManager.viewport.topLine == 0

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
    # visibleHeight = 20 - 1 = 19: 9 whole lines fit, the last at the bottom
    # and a row left under it, as Vim's scroll_cursor_halfway puts them.
    let buffer = createLongLineBuffer(50, 40)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 20, width: 20, x: 0, y: 0)
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

    check viewportManager.viewport.topLine == lastLine - 8

  test "lineWrap: viewport scrolls with cursor at non-zero wrap offset":
    # Each line: 40 chars, viewport width 20 → 2 screen lines per logical line.
    # Cursor at column 25 → cursor wrap segment 1. The window starts at a
    # line's start as with the cursor on segment 0.
    let buffer = createLongLineBuffer(50, 40)
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 20, width: 20, x: 0, y: 0)
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
    check viewportManager.viewport.topWrapOffset == 0

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
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
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
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 20, width: 80, x: 0, y: 0)
    )

    vmDefault.updateViewport(cursorPos, buffer.len, showStatusLine = true)

    check vmExplicit.viewport.topLine == vmDefault.viewport.topLine

suite "ViewportManager - sideways scrolling":
  test "a cursor past tabs scrolls by the cells it is drawn at":
    # Each "x\t" takes 8 cells, so column 10 is drawn at cell 40, past the
    # 36 cells the window leaves for text.
    let buffer = newTextBuffer("x\t".repeat(8) & "END")
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftCell: 0, height: 20, width: 40, x: 0, y: 0)
    )

    viewportManager.updateViewport(
      CursorPosition(x: 10, y: 0),
      buffer.len,
      reservedLines = steadyBottomAreaHeight(),
      buffer = buffer,
      viewportOffset = 4,
      tabStop = 8,
    )

    check viewportManager.viewport.leftCell == 5
