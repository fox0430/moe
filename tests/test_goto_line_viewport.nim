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

## Tests for goto line command viewport scrolling
## This test ensures that when jumping to a line (e.g., :100),
## the viewport scrolls to make that line visible.

import std/[unittest]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/motion {.all.}
import ../src/moepkg/cursor {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/commandline {.all.}
import ../src/moepkg/commandconfig {.all.}
import ../src/moepkg/commandregistry {.all.}
import ../src/moepkg/command_handlers/command_handler {.all.}

suite "Goto Line - Viewport Scrolling":
  test "viewport scrolls when jumping to line far below":
    # Create a buffer with 100 lines
    var lines = ""
    for i in 1 .. 100:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)

    let buffer = newTextBuffer(lines)

    # Create viewport manager with a small viewport (20 lines visible)
    let viewportManager = ViewportManager(
      viewport: ViewPort(
        topLine: 0,
        leftColumn: 0,
        height: 20, # Only 20 lines visible
        width: 80,
        x: 0,
        y: 0,
      )
    )

    # Jump to line 100 (0-based index: 99)
    let targetLine = 99
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    # Update viewport to follow cursor
    viewportManager.updateViewport(
      cursorPos,
      buffer.len,
      showStatusLine = true,
      reservedLines = 2, # Status line + command line
    )

    # Viewport should have scrolled to make line 100 visible
    # Line 100 (index 99) should be within the visible range
    let visibleHeight = viewportManager.viewport.height - 2 # 20 - 2 = 18 lines visible
    let maxVisibleLine = viewportManager.viewport.topLine + visibleHeight - 1

    check targetLine >= viewportManager.viewport.topLine
    check targetLine <= maxVisibleLine

    # topLine should be significantly greater than 0
    check viewportManager.viewport.topLine > 70 # Should be around 82 (100 - 18)

  test "viewport scrolls when jumping to line far above":
    # Create a buffer with 100 lines
    var lines = ""
    for i in 1 .. 100:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)

    let buffer = newTextBuffer(lines)

    # Create viewport manager positioned at the bottom
    let viewportManager = ViewportManager(
      viewport: ViewPort(
        topLine: 80, # Near the bottom
        leftColumn: 0,
        height: 20,
        width: 80,
        x: 0,
        y: 0,
      )
    )

    # Jump to line 10 (0-based index: 9)
    let targetLine = 9
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    # Update viewport to follow cursor
    viewportManager.updateViewport(
      cursorPos, buffer.len, showStatusLine = true, reservedLines = 2
    )

    # Viewport should have scrolled up to make line 10 visible
    check targetLine >= viewportManager.viewport.topLine
    check viewportManager.viewport.topLine <= 9 # Should be at or below line 10

  test "viewport does not scroll if target line is already visible":
    # Create a buffer with 100 lines
    var lines = ""
    for i in 1 .. 100:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)

    let buffer = newTextBuffer(lines)

    # Create viewport positioned to show lines 40-59
    let initialTopLine = 40
    let viewportManager = ViewportManager(
      viewport: ViewPort(
        topLine: initialTopLine, leftColumn: 0, height: 20, width: 80, x: 0, y: 0
      )
    )

    # Jump to line 50 (which is already visible)
    let targetLine = 50
    let cursorPos = CursorPosition(x: 0, y: targetLine)

    # Update viewport
    viewportManager.updateViewport(
      cursorPos, buffer.len, showStatusLine = true, reservedLines = 2
    )

    # Viewport topLine should remain the same or close
    check viewportManager.viewport.topLine >= initialTopLine - 1
    check viewportManager.viewport.topLine <= initialTopLine + 1

  test "command handler returns correct line number for goto command":
    # Test that the command handler correctly processes goto command with valid line
    # Create buffer with 100 lines
    var lines = ""
    for i in 1 .. 100:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)

    let buffer = newTextBuffer(lines)
    let parser = newCommandLineParser()
    let config = newCommandConfig()
    let commandRegistry = newCommandRegistry()
    let handler = newCommandModeHandler(parser, config, commandRegistry)

    # Test :100 command with a buffer that has 100 lines
    let result = handler.handleCommandModeInput(buffer, ":100")

    check result.kind == cmrGotoLine
    if result.kind == cmrGotoLine:
      check result.lineNumber == 100

  test "command handler validates line numbers":
    let buffer = newTextBuffer("Line 1\nLine 2\nLine 3")
    let parser = newCommandLineParser()
    let config = newCommandConfig()
    let commandRegistry = newCommandRegistry()
    let handler = newCommandModeHandler(parser, config, commandRegistry)

    # Test invalid line number (0)
    let result1 = handler.handleCommandModeInput(buffer, ":0")
    check result1.kind == cmrError

    # Test line number beyond buffer length
    let result2 = handler.handleCommandModeInput(buffer, ":100")
    check result2.kind == cmrError

  test "viewport scrolls to first line with :1":
    var lines = ""
    for i in 1 .. 100:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)

    let buffer = newTextBuffer(lines)

    # Start at bottom
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 80, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    # Jump to line 1 (index 0)
    let cursorPos = CursorPosition(x: 0, y: 0)

    viewportManager.updateViewport(
      cursorPos, buffer.len, showStatusLine = true, reservedLines = 2
    )

    # Should scroll to the very top
    check viewportManager.viewport.topLine == 0

  test "viewport scrolls to last line with :$":
    # Note: This test is for the viewport behavior,
    # actual :$ command parsing is handled separately
    var lines = ""
    for i in 1 .. 100:
      if i > 1:
        lines.add("\n")
      lines.add("Line " & $i)

    let buffer = newTextBuffer(lines)

    # Start at top
    let viewportManager = ViewportManager(
      viewport: ViewPort(topLine: 0, leftColumn: 0, height: 20, width: 80, x: 0, y: 0)
    )

    # Jump to last line (index 99)
    let lastLine = buffer.len - 1
    let cursorPos = CursorPosition(x: 0, y: lastLine)

    viewportManager.updateViewport(
      cursorPos, buffer.len, showStatusLine = true, reservedLines = 2
    )

    # Should scroll so last line is visible
    let visibleHeight = viewportManager.viewport.height - 2
    let maxVisibleLine = viewportManager.viewport.topLine + visibleHeight - 1

    check lastLine >= viewportManager.viewport.topLine
    check lastLine <= maxVisibleLine
