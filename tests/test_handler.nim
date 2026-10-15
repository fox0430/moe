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

## Tests for handler.nim
## This module tests the main event handler functions including:
## - Screen to buffer position conversion
## - Background process management
## - Search mode event handling helpers

import std/[unittest, options, tables, os, osproc, times, posix]
from std/strutils import contains, continuesWith, repeat, strip

import pkg/[celina, chronos]
import pkg/celina/core/mouse_logic

import config_test_helper
import visual_test_helper, clipboard_test_helper

import
  ../src/moepkg/[
    buffer, types, modes, registers, editor, config, filer, key_bindings, config_loader,
    render_utils, clipboard, message_log, frontend_input, pending_input, key_router,
    completion, signature_help, macro_recording,
  ]
import ../src/moepkg/handler {.all.}
import ../src/moepkg/editor_build_jobs {.all.}
import ../src/moepkg/job_lanes
import ../src/moepkg/terminal_mode
import ../src/moepkg/terminal/[pty, ansi_parser]
import ../src/moepkg/command_handlers/result_processor
import ../src/moepkg/command_handlers/[handler_result, misc_ops]

proc createTestViewport(x, y, width, height, topLine, leftColumn: int): ViewPort =
  ViewPort(
    x: x, y: y, width: width, height: height, topLine: topLine, leftColumn: leftColumn
  )

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  let window = EditorWindow(
    cursor: BufferPosition(line: 0, column: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
    screenCursor: CursorPosition(x: 0, y: 0),
  )

  EditorState(
    activeWindow: window,
    config: newEditorConfig(),
    windowDisplay: WindowDisplayState(viewportReservedLines: steadyBottomAreaHeight()),
    pendingInput: PendingInputState(
      macroState: MacroState(
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        playbackDepth: 0,
      )
    ),
    registers: initRegisters(),
    overlay: none(OverlayKind),
    input: InputState(
      search: SearchState(
        direction: Forward,
        text: "",
        startPos: BufferPosition(line: 0, column: 0),
        history: @[],
        historyIndex: -1,
        ignorecase: true,
        smartcase: true,
        incsearch: true,
        hlsearch: true,
        hlsearchTempDisabled: false,
      )
    ),
  )

proc noOpFrontendHook(): Future[void] {.async.} =
  discard

proc failingFrontendHook(): Future[void] {.async.} =
  raise newException(ValueError, "frontend suspend failed")

proc frontendSuspendBodyRuns(
    frontend: FrontendHooks, editor: Editor
): Future[bool] {.async: (raises: [Exception]).} =
  var bodyRan = false
  {.cast(gcsafe).}:
    withFrontendSuspend(frontend, editor):
      bodyRan = true
  return bodyRan

suite "screenToBufferPosition - Basic":
  test "Click at top-left corner of viewport":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    let result = screenToBufferPosition(
      vp, buffer, 0, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 0

  test "Click with line number offset":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 4 # Space for line numbers
      reservedLines = steadyBottomAreaHeight()

    # Click at x=5, which is x=1 in text area (5 - 4 = 1)
    let result = screenToBufferPosition(
      vp, buffer, 5, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 1

  test "Click on second line":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Line 1\nLine 2\nLine 3")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    let result = screenToBufferPosition(
      vp, buffer, 3, 1, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 3

  test "Click outside text area (below reserved lines)":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click at y=23 is within reserved lines (height=24, reserved=2)
    let result = screenToBufferPosition(
      vp, buffer, 0, 23, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isNone

  test "Click outside text area (left of line number offset)":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 4
      reservedLines = steadyBottomAreaHeight()

    # Click at x=2 is within line number area
    let result = screenToBufferPosition(
      vp, buffer, 2, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isNone

suite "screenToBufferPosition - Scrolled Viewport":
  test "Click with topLine offset":
    let
      vp = createTestViewport(0, 0, 80, 24, 10, 0) # topLine = 10
      buffer = newTextBuffer(
        "line0\nline1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9\n" &
          "line10\nline11\nline12"
      )
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    let result = screenToBufferPosition(
      vp, buffer, 3, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 10 # topLine + screenY
    check result.get.column == 3

  test "Click with leftColumn offset (horizontal scroll)":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 5) # leftColumn = 5
      buffer = newTextBuffer("Hello World this is a long line")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    let result = screenToBufferPosition(
      vp, buffer, 3, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 8 # leftColumn + screenX = 5 + 3

  test "Click with both offsets":
    let
      vp = createTestViewport(0, 0, 80, 24, 5, 10) # topLine=5, leftColumn=10
      buffer = newTextBuffer(
        "line0\nline1\nline2\nline3\nline4\n" &
          "This is line 5 with some long content for horizontal scroll"
      )
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    let result = screenToBufferPosition(
      vp, buffer, 5, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 5
    check result.get.column == 15 # leftColumn + screenX = 10 + 5

suite "screenToBufferPosition - No Wrap Display Width":
  # screenX is a display-column offset while the column is a character index, so
  # tabs and wide characters must be converted, not added.
  test "Click past a leading tab":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("\tabc")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # tabStop=4: the tab covers columns 0..3, so 'a' is drawn at column 4
    let result = screenToBufferPosition(
      vp, buffer, 4, 0, lineNumOffset, reservedLines, lineWrap = false, tabStop = 4
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 1

  test "Click inside a tab selects the tab":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("\tabc")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    let result = screenToBufferPosition(
      vp, buffer, 2, 0, lineNumOffset, reservedLines, lineWrap = false, tabStop = 4
    )

    check result.isSome
    check result.get.column == 0

  test "Click past full width characters":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("あいうabc")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Each wide rune takes 2 cells, so 'a' is drawn at column 6
    let result = screenToBufferPosition(
      vp, buffer, 6, 0, lineNumOffset, reservedLines, lineWrap = false, tabStop = 4
    )

    check result.isSome
    check result.get.column == 3

  test "Click on the second cell of a full width character":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("あいうabc")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    let result = screenToBufferPosition(
      vp, buffer, 3, 0, lineNumOffset, reservedLines, lineWrap = false, tabStop = 4
    )

    check result.isSome
    check result.get.column == 1

  test "Click with horizontal scroll and full width characters":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 2) # leftColumn = 2
      buffer = newTextBuffer("あいうえお")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # The renderer slices from character 2, so う takes cells 0..1 and え cell 2
    let result = screenToBufferPosition(
      vp, buffer, 2, 0, lineNumOffset, reservedLines, lineWrap = false, tabStop = 4
    )

    check result.isSome
    check result.get.column == 3

  test "Click with horizontal scroll onto a tab boundary":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 2) # leftColumn = 2
      buffer = newTextBuffer("ab\tcd")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Slicing at character 2 restarts tab expansion, so 'c' is drawn at column 4
    let result = screenToBufferPosition(
      vp, buffer, 4, 0, lineNumOffset, reservedLines, lineWrap = false, tabStop = 4
    )

    check result.isSome
    check result.get.column == 3

suite "screenToBufferPosition - Column Clamping":
  test "Column clamped to line length":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hi") # Only 2 characters
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click at x=50, but line only has 2 chars
    let result = screenToBufferPosition(
      vp, buffer, 50, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 1 # Clamped to max(0, lineLen - 1) = 1

  test "Column clamped on empty line":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Line 1\n\nLine 3") # Line 1 is empty
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on empty line at x=10
    let result = screenToBufferPosition(
      vp, buffer, 10, 1, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 0 # Empty line, column stays at 0

  test "Column clamped to character count for multibyte":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("あいう") # 3 chars, 9 bytes
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click at x=50, but line only has 3 characters
    let result = screenToBufferPosition(
      vp, buffer, 50, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 2 # Clamped to max(0, charLen - 1) = 2, not 8

suite "screenToBufferPosition - Line Clamping":
  test "Line clamped when clicking beyond buffer":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Only one line")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click at y=10, but buffer only has 1 line
    let result = screenToBufferPosition(
      vp, buffer, 5, 10, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0 # Clamped to buffer.len - 1

  test "Line clamped with scrolled viewport":
    let
      vp = createTestViewport(0, 0, 80, 24, 5, 0) # topLine = 5
      buffer = newTextBuffer("line0\nline1\nline2\nline3\nline4\nline5\nline6")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click at y=10, topLine=5, so bufferLine = 15, but only 7 lines
    let result = screenToBufferPosition(
      vp, buffer, 0, 10, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 6 # Clamped to buffer.len - 1

suite "screenToBufferPosition - Viewport Position":
  test "Click with viewport at non-zero position":
    let
      vp = createTestViewport(10, 5, 60, 20, 0, 0) # Viewport at (10, 5)
      buffer = newTextBuffer("Hello World\nSecond line\nThird line")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click at absolute (12, 6) which is relative (2, 1) to viewport
    let result = screenToBufferPosition(
      vp, buffer, 12, 6, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 2

  test "Click outside viewport area (above)":
    let
      vp = createTestViewport(10, 5, 60, 20, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click at y=3, viewport starts at y=5
    let result = screenToBufferPosition(
      vp, buffer, 15, 3, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isNone

suite "screenToBufferPosition - Line Wrap Mode":
  test "Click with lineWrap enabled uses screen position directly":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 5) # leftColumn is set but ignored
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # With lineWrap=true, leftColumn should be ignored
    let result = screenToBufferPosition(
      vp,
      buffer,
      3,
      0,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 3 # screenX directly (not leftColumn + screenX)

  test "Click on second wrap segment":
    # Line "abcdefghij" (10 chars), viewport width=5, so wraps at col 5
    # Screen row 0 = "abcde" (chars 0-4), row 1 = "fghij" (chars 5-9)
    let
      vp = createTestViewport(0, 0, 5, 24, 0, 0)
      buffer = newTextBuffer("abcdefghij")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on screen row 1 (second wrap segment), col 2 => char 7 ('h')
    let result = screenToBufferPosition(
      vp,
      buffer,
      2,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 7

  test "Click after wrapped line goes to next buffer line":
    # Line 0: "abcde" (5 chars, 1 screen row at width=10)
    # Line 1: "fghij" (5 chars, 1 screen row)
    let
      vp = createTestViewport(0, 0, 10, 24, 0, 0)
      buffer = newTextBuffer("abcde\nfghij")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on screen row 1 => line 1
    let result = screenToBufferPosition(
      vp,
      buffer,
      2,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 2

  test "Click with wrap and line number offset":
    # viewport width=15, lineNumOffset=5, so maxWidth=10 for text
    # Line: "abcdefghijklmno" (15 chars)
    # Segment 0 (row 0): chars 0-9 (10 cols)
    # Segment 1 (row 1): chars 10-14 (5 cols)
    let
      vp = createTestViewport(0, 0, 15, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijklmno")
      lineNumOffset = 5
      reservedLines = steadyBottomAreaHeight()

    # Click at x=7 on row 1 => screenX = 7-5=2, segment 1, char 12 ('m')
    let result = screenToBufferPosition(
      vp,
      buffer,
      7,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 12

  test "Click with wrap and sidebar":
    # viewport width=17, sidebarWidth=2, lineNumOffset=5, so maxWidth=10 for text
    # Line: "abcdefghijklmno" (15 chars)
    # Segment 0 (row 0): chars 0-9 (10 cols)
    # Segment 1 (row 1): chars 10-14 (5 cols)
    let
      vp = createTestViewport(0, 0, 17, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijklmno")
      lineNumOffset = 5
      sidebarWidth = 2
      reservedLines = steadyBottomAreaHeight()

    # Click at x=9 on row 1 => screenX = 9-2-5=2, segment 1, char 12 ('m')
    let result = screenToBufferPosition(
      vp,
      buffer,
      9,
      1,
      lineNumOffset + sidebarWidth,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - sidebarWidth - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 12

  test "Click on wrap with wide characters":
    # "あいうえお" = 5 CJK chars = 10 display cols
    # maxWidth=6: segment 0 = "あいう" (3 chars, 6 cols), segment 1 = "えお" (2 chars, 4 cols)
    let
      vp = createTestViewport(0, 0, 6, 24, 0, 0)
      buffer = newTextBuffer("あいうえお")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on row 1, col 0 => first char of segment 1 = char 3 ('え')
    let result = screenToBufferPosition(
      vp,
      buffer,
      0,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 3

  test "Click on wrap with tabs":
    # "\tabcdefgh" with tabStop=4: tab=4 cols, then "abcdef"=6 cols = 10 cols for first 7 chars
    # maxWidth=10: segment 0 = "\tabcdef" (7 chars, 10 cols)
    # segment 1 = "gh" (2 chars, 2 cols)
    let
      vp = createTestViewport(0, 0, 10, 24, 0, 0)
      buffer = newTextBuffer("\tabcdefgh")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on row 1, col 1 => char 8 ('h')
    let result = screenToBufferPosition(
      vp,
      buffer,
      1,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      tabStop = 4,
      wrapWidth = vp.width - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 8

  test "Multiple buffer lines with wrapping":
    # Line 0: "abcdefghij" (10 chars) => 2 rows at maxWidth=5
    # Line 1: "klmno" (5 chars) => 1 row
    # Screen: row 0="abcde", row 1="fghij", row 2="klmno"
    let
      vp = createTestViewport(0, 0, 5, 24, 0, 0)
      buffer = newTextBuffer("abcdefghij\nklmno")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on row 2, col 1 => line 1, char 1 ('l')
    let result = screenToBufferPosition(
      vp,
      buffer,
      1,
      2,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 1

  test "Click honors topWrapOffset (sub-line scrolled top line)":
    # Line 0 (30 chars) wraps into 3 segments at maxWidth=10: seg0 0-9, seg1
    # 10-19, seg2 20-29. With topWrapOffset=1 the renderer hides seg0, so screen
    # row 0 shows seg1 and row 1 shows seg2; the mapping must mirror that.
    let
      vp = createTestViewport(0, 0, 10, 24, 0, 0)
      buffer = newTextBuffer("0123456789ABCDEFGHIJabcdefghij\ntail")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()
    vp.topWrapOffset = 1

    # Row 0, col 2 lands on seg1 => char 12, not seg0 char 2.
    let onTop = screenToBufferPosition(
      vp,
      buffer,
      2,
      0,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )
    check onTop.isSome
    check onTop.get.line == 0
    check onTop.get.column == 12

    # Line 0 shows only 2 visible rows (seg1, seg2), so screen row 2 is line 1 —
    # the over-counted top line must not swallow the click.
    let below = screenToBufferPosition(
      vp,
      buffer,
      1,
      2,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )
    check below.isSome
    check below.get.line == 1
    check below.get.column == 1

suite "screenToBufferPosition - Scrollbar":
  test "Click with scrollbar reduces text area width":
    # viewport width=12, sidebarWidth=0, scrollbarWidth=1, lineNumOffset=0
    # maxWidth = 12 - 0 - 1 - 0 = 11
    # Line: "abcdefghijklmno" (15 chars)
    # Segment 0 (row 0): chars 0-10 (11 cols)
    # Segment 1 (row 1): chars 11-14 (4 cols)
    let
      vp = createTestViewport(0, 0, 12, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijklmno")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on row 1, col 0 => char 11 ('l')
    let result = screenToBufferPosition(
      vp,
      buffer,
      0,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - 1 - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 11

  test "Click with scrollbar and sidebar":
    # viewport width=20, sidebarWidth=2, scrollbarWidth=1, lineNumOffset=5
    # maxWidth = 20 - 2 - 1 - 5 = 12
    # Line: "abcdefghijklmnopqrst" (20 chars)
    # Segment 0 (row 0): chars 0-11 (12 cols)
    # Segment 1 (row 1): chars 12-19 (8 cols)
    let
      vp = createTestViewport(0, 0, 20, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijklmnopqrst")
      lineNumOffset = 5
      sidebarWidth = 2
      reservedLines = steadyBottomAreaHeight()

    # Click at x=8 on row 1 => screenX = 8-2-5=1, segment 1, char 13 ('n')
    let result = screenToBufferPosition(
      vp,
      buffer,
      8,
      1,
      lineNumOffset + sidebarWidth,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - sidebarWidth - 1 - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 13

  test "Click without scrollbar has wider text area":
    # Same setup as above but without scrollbar
    # maxWidth = 20 - 2 - 0 - 5 = 13
    # Segment 0 (row 0): chars 0-12 (13 cols)
    # Segment 1 (row 1): chars 13-19 (7 cols)
    let
      vp = createTestViewport(0, 0, 20, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijklmnopqrst")
      lineNumOffset = 5
      sidebarWidth = 2
      reservedLines = steadyBottomAreaHeight()

    # Click at x=8 on row 1 => screenX = 8-2-5=1, segment 1, char 14 ('o')
    let result = screenToBufferPosition(
      vp,
      buffer,
      8,
      1,
      lineNumOffset + sidebarWidth,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - sidebarWidth - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 14

  test "No-wrap mode ignores scrollbar for column calculation":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    let result = screenToBufferPosition(
      vp, buffer, 5, 0, lineNumOffset, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 5

  test "Click with scrollbar width 2":
    # viewport width=14, scrollbarWidth=2, lineNumOffset=0
    # maxWidth = 14 - 0 - 2 - 0 = 12
    # Line: "abcdefghijklmnop" (16 chars)
    # Segment 0 (row 0): chars 0-11 (12 cols)
    # Segment 1 (row 1): chars 12-15 (4 cols)
    let
      vp = createTestViewport(0, 0, 14, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijklmnop")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on row 1, col 1 => char 13 ('n')
    let result = screenToBufferPosition(
      vp,
      buffer,
      1,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - 2 - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 13

  test "Click with scrollbar width 0 defaults to no scrollbar":
    # scrollbarWidth=0 should behave same as no scrollbar
    # viewport width=10, maxWidth = 10
    let
      vp = createTestViewport(0, 0, 10, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijklmno")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # 15 chars at maxWidth=10: segment 0 = 0-9, segment 1 = 10-14
    # Click on row 1, col 0 => char 10 ('k')
    let result = screenToBufferPosition(
      vp,
      buffer,
      0,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 10

  test "Click with scrollbar on multiline buffer":
    # viewport width=12, scrollbarWidth=1, lineNumOffset=0
    # maxWidth = 12 - 1 = 11
    # Line 0: "abcdefghijk" (11 chars) => 1 row
    # Line 1: "lmnop" (5 chars) => 1 row
    let
      vp = createTestViewport(0, 0, 12, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijk\nlmnop")
      lineNumOffset = 0
      reservedLines = steadyBottomAreaHeight()

    # Click on row 1, col 2 => line 1, char 2 ('n')
    let result = screenToBufferPosition(
      vp,
      buffer,
      2,
      1,
      lineNumOffset,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - 1 - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 2

  test "Click with scrollbar, sidebar, and line numbers":
    # viewport width=25, sidebarWidth=2, scrollbarWidth=2, lineNumOffset=4
    # maxWidth = 25 - 2 - 2 - 4 = 17
    # Line: 20 chars => segment 0 = chars 0-16 (17 cols), segment 1 = chars 17-19
    let
      vp = createTestViewport(0, 0, 25, 24, 0, 0)
      buffer = newTextBuffer("abcdefghijklmnopqrst")
      lineNumOffset = 4
      sidebarWidth = 2
      reservedLines = steadyBottomAreaHeight()

    # Click at x=7 on row 1 => screenX = 7-2-4 = 1, segment 1, char 18 ('s')
    let result = screenToBufferPosition(
      vp,
      buffer,
      7,
      1,
      lineNumOffset + sidebarWidth,
      reservedLines,
      lineWrap = true,
      wrapWidth = vp.width - sidebarWidth - 2 - lineNumOffset,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 18

suite "Background Process Management":
  test "addRunningProcess adds process to list":
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.cleanupBackgroundProcesses()

    # Note: We can't easily create a real BackgroundProcess in tests
    # This test verifies the function exists and can be called
    check editor.runningBackgroundProcesses.len == 0

  test "cleanupBackgroundProcesses clears the list":
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.cleanupBackgroundProcesses()
    # After cleanup, the list should be empty
    check editor.runningBackgroundProcesses.len == 0

suite "Filter op":
  proc filterEditor(lines: seq[string]): (Editor, TextBuffer) =
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let editor = newEditor(config)
    let buf = newTextBuffer()
    for i, line in lines:
      if i == 0:
        if line.len > 0:
          discard buf.insertText(BufferPosition(line: 0, column: 0), line)
      else:
        discard buf.insert(i, line)
    buf.markSaved()
    editor.addBuffer(buf)
    editor.activeWindow.setTab(buf)
    (editor, buf)

  proc runFilter(
      editor: Editor, buf: TextBuffer, command: string, first, last: int
  ): Future[void] {.async.} =
    ## Queue the op the command handler would have produced and let it finish.
    ## The window it was typed in is the active one, as at the command line.
    let statusBefore = editor.state.statusMessage
    let queueBefore = editor.state.notificationPopup.queue.len
    editor.state.pending.add PendingAsyncOp(
      kind: paoFilter,
      filter: (
        bufferId: buf.id,
        windowIndex: editor.windowManager.activeWindowIndex,
        command: command,
        first: first,
        last: last,
        contentVersion: buf.contentVersion,
      ),
    )
    await editor.handlePendingAsyncOperations(FrontendHooks())
    # The run is spawned, not awaited, so wait for it to land.
    for _ in 0 ..< 200:
      if editor.state.statusMessage != statusBefore or
          editor.state.notificationPopup.queue.len != queueBefore:
        break
      await sleepAsync(25)

  proc lines(buf: TextBuffer): seq[string] =
    for i in 0 ..< buf.len:
      result.add buf.getLine(i)

  test "The command's output replaces the lines it was given":
    let (editor, buf) = filterEditor(@["b", "a", "c"])
    waitFor editor.runFilter(buf, "sort", 0, 2)
    check buf.lines == @["a", "b", "c"]

  test "Only the range is replaced, the rest is left alone":
    let (editor, buf) = filterEditor(@["keep", "b", "a", "keep2"])
    waitFor editor.runFilter(buf, "sort", 1, 2)
    check buf.lines == @["keep", "a", "b", "keep2"]

  test "A command that writes more lines than it was given grows the range":
    let (editor, buf) = filterEditor(@["one", "x", "two"])
    waitFor editor.runFilter(buf, "sh -c 'echo a; echo b; echo c'", 1, 1)
    check buf.lines == @["one", "a", "b", "c", "two"]

  test "A command that writes nothing removes the lines":
    let (editor, buf) = filterEditor(@["one", "gone", "two"])
    waitFor editor.runFilter(buf, "true", 1, 1)
    check buf.lines == @["one", "two"]

  test "The replacement is one undo entry":
    let (editor, buf) = filterEditor(@["b", "a"])
    waitFor editor.runFilter(buf, "sort", 0, 1)
    check buf.lines == @["a", "b"]
    discard buf.undo()
    check buf.lines == @["b", "a"]

  test "Output that arrives after the buffer changed is not applied":
    # The editor stays live while the command runs, so what comes back can
    # describe lines that are no longer there.
    let (editor, buf) = filterEditor(@["b", "a"])
    editor.state.pending.add PendingAsyncOp(
      kind: paoFilter,
      filter: (
        bufferId: buf.id,
        windowIndex: 0,
        command: "sh -c 'sleep 0.3; sort'",
        first: 0,
        last: 1,
        contentVersion: buf.contentVersion,
      ),
    )
    waitFor editor.handlePendingAsyncOperations(FrontendHooks())
    discard buf.insert(0, "typed while it ran")
    waitFor sleepAsync(1200)
    check buf.lines == @["typed while it ran", "b", "a"]

  test "A non-zero exit does not disqualify the output":
    let (editor, buf) = filterEditor(@["x"])
    waitFor editor.runFilter(buf, "sh -c 'echo formatted; exit 1'", 0, 0)
    check buf.lines == @["formatted"]
    check editor.state.statusMessage.contains("exit 1")

  test "A command that matched nothing removes the lines it was given":
    # `grep` exits 1 having correctly produced nothing.
    let (editor, buf) = filterEditor(@["one", "drop me", "two"])
    waitFor editor.runFilter(buf, "grep nomatchhere", 1, 1)
    check buf.lines == @["one", "two"]

  test "A command that does not exist is not told apart from one that matched nothing":
    # Same empty output, same non-zero class of status. Vim applies both and
    # leaves the undo to the user, and inventing the distinction here would
    # get it wrong in whichever direction it guessed.
    let (editor, buf) = filterEditor(@["b", "a"])
    waitFor editor.runFilter(buf, "moe-no-such-command-here", 0, 1)
    check buf.lines == @[""]
    check editor.state.statusMessage.contains("exit 127")
    discard buf.undo()
    check buf.lines == @["b", "a"]

  test "Only the window the filter was typed in follows the output":
    # Vim moves the cursor of the window the command was given to. Another
    # split on the same buffer keeps looking where its user left it.
    let (editor, buf) = filterEditor(@["b", "a", "c"])
    editor.activeWindow.cursor = BufferPosition(line: 2, column: 0)
    let split = EditorWindow(viewBuffer: buf, tabBufferId: buf.id)
    split.cursor = BufferPosition(line: 2, column: 0)
    editor.windowManager.windows.add split

    waitFor editor.runFilter(buf, "sort", 0, 2)

    check buf.lines == @["a", "b", "c"]
    check editor.windowManager.windows[0].cursor == BufferPosition(line: 0, column: 0)
    check split.cursor == BufferPosition(line: 2, column: 0)

  test "A window that is no longer showing the buffer is left where it is":
    # The run is asynchronous, so the window the filter was typed in can be
    # showing something else by the time the output comes back.
    let (editor, buf) = filterEditor(@["b", "a", "c"])
    let other = newTextBuffer()
    discard other.insertText(BufferPosition(line: 0, column: 0), "elsewhere")
    editor.addBuffer(other)
    let split = EditorWindow(viewBuffer: other, tabBufferId: other.id)
    split.cursor = BufferPosition(line: 0, column: 3)
    editor.windowManager.windows.add split
    editor.windowManager.activeWindowIndex = 1

    waitFor editor.runFilter(buf, "sort", 0, 2)

    check buf.lines == @["a", "b", "c"]
    check split.cursor == BufferPosition(line: 0, column: 3)

  test "A filter that shrinks the buffer leaves no cursor past its end":
    let (editor, buf) = filterEditor(@["a", "b", "c"])
    editor.activeWindow.cursor = BufferPosition(line: 2, column: 0)

    waitFor editor.runFilter(buf, "true", 2, 2)

    check buf.lines == @["a", "b"]
    check editor.activeWindow.cursor.line == 1

  test "An inactive window on the filtered buffer is re-clamped too":
    let (editor, buf) = filterEditor(@["a", "b", "c", "d"])
    let split = EditorWindow(viewBuffer: buf, tabBufferId: buf.id)
    split.cursor = BufferPosition(line: 3, column: 0)
    editor.windowManager.windows.add split

    waitFor editor.runFilter(buf, "head -1", 0, 3)

    check buf.lines == @["a"]
    check split.cursor.line == 0

  test "What the command wrote on stderr is reported alongside the summary":
    let (editor, buf) = filterEditor(@["x"])
    editor.config.notification.popupNotifications = false

    waitFor editor.runFilter(buf, "sh -c 'echo careful >&2; cat'", 0, 0)

    check buf.lines == @["x"]
    check editor.state.statusMessage.contains("1 line filtered through")
    check editor.state.statusMessage.contains("careful")

  test "A command that exited cleanly is reported as such however chatty it was":
    # A formatter may print a deprecation note and still have done its job.
    let (editor, buf) = filterEditor(@["x"])
    editor.config.notification.popupNotifications = true

    waitFor editor.runFilter(buf, "sh -c 'echo note >&2; cat'", 0, 0)

    check buf.lines == @["x"]
    check editor.state.notificationPopup.queue.len == 1
    check editor.state.notificationPopup.queue[0].level == nlInfo

  test "Only the first lines of a torrent of diagnostics are kept":
    # They go to the message log, which is never trimmed, so an unbounded
    # standard error would grow it without bound.
    let (editor, buf) = filterEditor(@["x"])
    editor.config.notification.popupNotifications = false
    clearMessageLog()

    waitFor editor.runFilter(buf, "sh -c 'seq 1 5000 >&2; cat'", 0, 0)

    check buf.lines == @["x"]
    # The status line only has room for the first few, so the note about the
    # rest lands in the log with them.
    check getMessageLog().len < 20
    check getMessageLog()[^1].contains("stderr was dropped")

  test "Terminal escapes on stderr do not reach the status line":
    let (editor, buf) = filterEditor(@["x"])
    editor.config.notification.popupNotifications = false

    waitFor editor.runFilter(buf, "printf '\\033[31mred\\n' >&2; cat", 0, 0)

    check buf.lines == @["x"]
    check editor.state.statusMessage.contains("red")
    check not editor.state.statusMessage.contains("\e")

suite "Pending async operations":
  test "Returns false when no pending operations":
    let editor = newEditor(newEditorConfig())

    check editor.state.pending.len == 0

  test "Terminal command is skipped when frontend hooks are unavailable":
    let editor = newEditor(newEditorConfig())
    editor.state.pending.add PendingAsyncOp(
      kind: paoShellCommand, command: "command must not run"
    )

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0
    check editor.state.statusMessage ==
      "This frontend does not support terminal commands"

  test "Failed operation preserves later operations for the next tick":
    let editor = newEditor(newEditorConfig())
    editor.state.pending.add PendingAsyncOp(
      kind: paoShellCommand, command: "command must not run"
    )
    editor.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (cmd: "echo", args: @["hi"], filePath: "", workDir: ""),
    )

    waitFor editor.handlePendingAsyncOperations(
      FrontendHooks(suspend: failingFrontendHook, resume: noOpFrontendHook)
    )

    check editor.state.pending.len == 1
    check editor.state.pending[0].kind == paoQuickRun
    check editor.state.statusMessage.contains("Pending operation failed")

  test "Terminal body is skipped unless both frontend hooks are available":
    let editor = newEditor(newEditorConfig())
    for frontend in [
      FrontendHooks(),
      FrontendHooks(suspend: noOpFrontendHook),
      FrontendHooks(resume: noOpFrontendHook),
    ]:
      let bodyRan = waitFor frontendSuspendBodyRuns(frontend, editor)
      check not bodyRan

    let frontend = FrontendHooks(suspend: noOpFrontendHook, resume: noOpFrontendHook)
    let bodyRan = waitFor frontendSuspendBodyRuns(frontend, editor)
    check bodyRan

suite "releaseExternalResources":
  # persist off: savePersistData writes to the real user persist directory.
  proc newQuitPathEditor(): Editor =
    var config = newEditorConfig()
    config.persist.search = false
    config.persist.commandHistory = false
    config.persist.cursorPosition = false
    return newEditor(config)

  test "clears the process lists":
    let editor = newQuitPathEditor()

    editor.releaseExternalResources()

    check editor.runningBackgroundProcesses.len == 0
    check editor.runningQuickRunProcesses.len == 0

  test "is idempotent":
    # A crash during quit runs it twice.
    let editor = newQuitPathEditor()

    editor.releaseExternalResources()
    editor.releaseExternalResources()

    check editor.runningBackgroundProcesses.len == 0
    check editor.runningQuickRunProcesses.len == 0

proc detachedPendingWriter(e: Editor): Future[void] {.async: (raises: [Exception]).} =
  # Simulate the delayed pending set that happens inside
  # e.codeLensPickerConfirm() -> executeCodeLensItem(), which is asyncSpawn'd
  # from handler.nim after handleEvent has already returned.
  e.state.pending.add PendingAsyncOp(
    kind: paoQuickRun,
    quickRun: (cmd: "echo", args: @["detached"], filePath: "", workDir: ""),
  )

proc runDetachedScenario(e: Editor): Future[void] {.async: (raises: [Exception]).} =
  asyncSpawn detachedPendingWriter(e)
  # Yield so the detached task runs before the drain.
  await sleepAsync(10)
  await e.handlePendingAsyncOperations(FrontendHooks())

proc waitForOutputSplit(e: Editor): Future[bool] {.async: (raises: [Exception]).} =
  for _ in 0 ..< 200:
    if e.windowManager.windows.len > 1:
      return true
    await sleepAsync(10)
  return false

suite "Build output":
  test "build output remains Normal when forced Insert mode is enabled":
    let config = newEditorConfig()
    config.standard.forceInsertMode = true
    let editor = newEditor(config)
    editor.submitBuild(
      (
        path: getTempDir() / "x.nim",
        language: 0,
        customCmd: "echo hi",
        workspaceRoot: "",
        automatic: false,
      )
    )

    check waitFor waitForOutputSplit(editor)
    check editor.activeBuffer.readOnly
    check editor.state.mode == EditorMode.Normal
    check not editor.activeBuffer.inTransaction

suite "handlePendingAsyncOperations drains ops queued from async tasks":
  test "QuickRun output remains Normal when forced Insert mode is enabled":
    let config = newEditorConfig()
    config.standard.forceInsertMode = true
    let editor = newEditor(config)
    editor.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (cmd: "echo", args: @["hi"], filePath: "", workDir: ""),
    )

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0
    check waitFor waitForOutputSplit(editor)
    check editor.activeBuffer.readOnly
    check editor.state.mode == EditorMode.Normal
    check not editor.activeBuffer.inTransaction

  test "drain from detached async task (simulates CodeLens confirm)":
    # Reproduces the visible bug: handler.nim asyncSpawns a task, the task
    # queues an op *after* handleEvent returns. Without the unconditional
    # drain the op would sit until the next event.
    let config = newEditorConfig()
    let editor = newEditor(config)

    waitFor runDetachedScenario(editor)

    check editor.state.pending.len == 0

  test "multiple queued ops drain in one call":
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (cmd: "echo", args: @["hi"], filePath: "", workDir: ""),
    )
    editor.state.pending.add PendingAsyncOp(
      kind: paoFilter,
      filter: (
        bufferId: BufferId(999_999),
        windowIndex: 0,
        command: "cat",
        first: 0,
        last: 0,
        contentVersion: 0,
      ),
    )

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0

  test "duplicate ops of the same kind are both kept and drained":
    # The old flat-field layout silently overwrote the first request.
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (cmd: "echo", args: @["a"], filePath: "", workDir: ""),
    )
    editor.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (cmd: "echo", args: @["b"], filePath: "", workDir: ""),
    )
    check editor.state.pending.len == 2

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0

  test "a QuickRun stopped by :jobs! before it starts removes its work dir":
    let editor = newEditor(newEditorConfig())
    let workDir = getTempDir() / "moe_test_handler_quickrun_stopped"
    createDir(workDir)
    writeFile(workDir / "quickruntemp.py", "print('never run')")
    defer:
      removeDir(workDir)

    editor.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      epoch: editor.state.commandEpoch,
      quickRun: (
        cmd: "echo",
        args: @["never run"],
        filePath: workDir / "quickruntemp.py",
        workDir: workDir,
      ),
    )
    # What `:jobs!` does to work queued before it.
    editor.state.commandEpoch.inc

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0
    check not dirExists(workDir)

  test "drain with an empty queue is a no-op":
    let config = newEditorConfig()
    let editor = newEditor(config)

    # Should not raise and should leave state untouched.
    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0

suite "Background op failures route through notify":
  test "syntax check failure raises an error notification":
    # A bare statusMessage is wiped by prepareForInput on the next keystroke,
    # so a failure landing mid-typing was unreadable. langNone has no syntax
    # check command, which fails before any process is spawned.
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.config.notification.popupNotifications = true
    editor.state.setStatusQuiet("")

    waitFor runSyntaxCheckJob(
      editor,
      (path: "/nonexistent.txt", language: 0, buffer: BufferId(0), awaited: 0, text: ""),
      JobStop(),
    )

    check editor.state.notificationPopup.queue.len == 1
    check editor.state.notificationPopup.queue[0].level == nlError
    check "Syntax check error" in editor.state.notificationPopup.queue[0].message

  test "syntax check failure still reaches the status line without popups":
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.config.notification.popupNotifications = false
    editor.state.setStatusQuiet("")

    waitFor runSyntaxCheckJob(
      editor,
      (path: "/nonexistent.txt", language: 0, buffer: BufferId(0), awaited: 0, text: ""),
      JobStop(),
    )

    check editor.state.notificationPopup.queue.len == 0
    check "Syntax check error" in editor.state.statusMessage

suite "Search Mode - History Navigation":
  test "Search state initialized correctly":
    let state = createTestState()
    state.enterSearchOverlay(Forward)

    check state.input.search.direction == Forward
    check state.input.search.text == ""
    check state.input.search.historyIndex == -1

  test "Search state with backward direction":
    let state = createTestState()
    state.enterSearchOverlay(Backward)

    check state.input.search.direction == Backward
    check state.input.search.text == ""

  test "Search history index starts at -1":
    let state = createTestState()
    state.input.search.history = @["pattern1", "pattern2", "pattern3"]
    state.enterSearchOverlay(Forward)

    check state.input.search.historyIndex == -1

  test "Search state preserves history on enter":
    let state = createTestState()
    state.input.search.history = @["old_search"]
    state.enterSearchOverlay(Forward)

    # History should be preserved
    check state.input.search.history.len == 1
    check state.input.search.history[0] == "old_search"

suite "Search Mode - Start Position":
  test "Search start position captured from cursor":
    let state = createTestState()
    state.cursor = BufferPosition(line: 10, column: 5)
    state.enterSearchOverlay(Forward)

    check state.input.search.startPos.line == 10
    check state.input.search.startPos.column == 5

  test "Different cursor positions captured correctly":
    let state = createTestState()

    # First search
    state.cursor = BufferPosition(line: 0, column: 0)
    state.enterSearchOverlay(Forward)
    check state.input.search.startPos.line == 0
    check state.input.search.startPos.column == 0

    state.exitOverlay()

    # Second search from different position
    state.cursor = BufferPosition(line: 50, column: 20)
    state.enterSearchOverlay(Backward)
    check state.input.search.startPos.line == 50
    check state.input.search.startPos.column == 20

suite "Search Mode - Text Handling":
  test "Search text cleared on overlay enter":
    let state = createTestState()
    state.input.search.text = "previous search"
    state.enterSearchOverlay(Forward)

    check state.input.search.text == ""

  test "Search text cleared on overlay exit":
    let state = createTestState()
    state.enterSearchOverlay(Forward)
    state.input.search.text = "current search"
    state.exitOverlay()

    check state.input.search.text == ""

  test "History index reset on overlay exit":
    let state = createTestState()
    state.input.search.history = @["pattern1", "pattern2"]
    state.enterSearchOverlay(Forward)
    state.input.search.historyIndex = 1
    state.exitOverlay()

    check state.input.search.historyIndex == -1

suite "Search Mode - Search Options":
  test "Search ignorecase option preserved":
    let state = createTestState()
    state.input.search.ignorecase = false
    state.enterSearchOverlay(Forward)

    check state.input.search.ignorecase == false

  test "Search smartcase option preserved":
    let state = createTestState()
    state.input.search.smartcase = false
    state.enterSearchOverlay(Forward)

    check state.input.search.smartcase == false

  test "Search incsearch option preserved":
    let state = createTestState()
    state.input.search.incsearch = false
    state.enterSearchOverlay(Forward)

    check state.input.search.incsearch == false

  test "Search hlsearch option preserved":
    let state = createTestState()
    state.input.search.hlsearch = false
    state.enterSearchOverlay(Forward)

    check state.input.search.hlsearch == false

suite "BufferInfo - Basic":
  test "BufferInfo created with file path":
    let info = BufferInfo(filePath: some("test.nim"), isModified: false, isActive: true)

    check info.filePath.isSome
    check info.filePath.get == "test.nim"
    check info.isModified == false
    check info.isActive == true

  test "BufferInfo without file path":
    let info = BufferInfo(filePath: none(string), isModified: true, isActive: false)

    check info.filePath.isNone
    check info.isModified == true
    check info.isActive == false

suite "Command Mode - Text Input State":
  test "Command text initialized with colon":
    let state = createTestState()
    state.enterCommandOverlay()

    check state.input.commandText == ":"
    check state.input.commandCursor == 0

  test "Command cursor starts at 0":
    let state = createTestState()
    state.enterCommandOverlay()

    check state.input.commandCursor == 0

  test "Command state cleared on exit":
    let state = createTestState()
    state.enterCommandOverlay()
    state.input.commandText = ":wq"
    state.input.commandCursor = 2
    state.exitOverlay()

    check state.input.commandText == ""
    check state.input.commandCursor == 0

suite "Rename Mode - State":
  test "Rename state initialized with original word":
    let state = createTestState()
    state.enterRenameOverlay("myFunction", 10, 5)

    check state.renameState.text == "myFunction"
    check state.renameState.originalWord == "myFunction"
    check state.renameState.cursorLine == 10
    check state.renameState.cursorColumn == 5

  test "Rename text starts as original word":
    let state = createTestState()
    state.enterRenameOverlay("varName", 0, 0)

    # Text should be pre-filled with original word
    check state.renameState.text == "varName"

  test "Rename cursor position captured":
    let state = createTestState()
    state.enterRenameOverlay("symbol", 100, 50)

    check state.renameState.cursorLine == 100
    check state.renameState.cursorColumn == 50

proc createTestEditorWithBuffer(content: string): Editor =
  ## Create a minimal editor for mouse scroll testing
  let config = newEditorConfig()
  config.standard.mouse = true
  result = newEditor(config)
  let buf = newTextBuffer(content)
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.motionController.viewportManager.viewport = result.viewport
  result.state.mode = EditorMode.Normal

proc makeWheelEvent(button: MouseButton, x, y: int): Event =
  Event(
    kind: EventKind.Mouse,
    mouse: MouseEvent(kind: MouseEventKind.Press, button: button, x: x, y: y),
  )

suite "handleMouseEvent - Mouse Disabled":
  test "Wheel event ignored when mouse is disabled":
    let e = createTestEditorWithBuffer("line0\nline1\nline2\nline3\nline4\nline5")
    e.config.standard.mouse = false

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == false
    check e.windowManager.windows[0].cursor.line == 0

  test "Left click ignored when mouse is disabled":
    let e = createTestEditorWithBuffer("line0\nline1\nline2")
    e.config.standard.mouse = false

    let event = Event(
      kind: EventKind.Mouse,
      mouse: MouseEvent(
        kind: MouseEventKind.Press, button: mouse_logic.MouseButton.Left, x: 3, y: 1
      ),
    )
    let handled = e.handleMouseEvent(event)

    check handled == false
    check e.windowManager.windows[0].cursor.line == 0

suite "frontend-neutral pointer and scroll input":
  test "signed row delta scrolls the viewport without moving a visible cursor":
    let e =
      createTestEditorWithBuffer("line0\nline1\nline2\nline3\nline4\nline5\nline6")
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 40, height: 5, topLine: 0, leftColumn: 0)
    e.windowManager.windows[0].cursor = BufferPosition(line: 3, column: 0)

    let down = e.handleScrollInput(initScrollInput(2, 10, 2))
    check down.handled
    check down.requestedRows == 2
    check down.appliedRows == 2
    check down.viewportPhysicalRowsMoved == 2
    check e.windowManager.windows[0].viewport.topLine == 2
    check e.windowManager.windows[0].cursor.line == 3

    let up = e.handleScrollInput(initScrollInput(2, 10, -1))
    check up.handled
    check up.requestedRows == -1
    check up.appliedRows == -1
    check up.viewportPhysicalRowsMoved == -1
    check e.windowManager.windows[0].viewport.topLine == 1
    check e.windowManager.windows[0].cursor.line == 3

  test "scroll preserves the cursor after its row leaves the viewport":
    let e = createTestEditorWithBuffer("line0\nline1\nline2\nline3\nline4\nline5")
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 40, height: 3, topLine: 0, leftColumn: 0)
    e.windowManager.windows[0].cursor = BufferPosition(line: 1, column: 2)

    let outcome = e.handleScrollInput(initScrollInput(1, 10, 3))

    check outcome.appliedRows == 3
    check e.windowManager.windows[0].viewport.topLine == 3
    check e.windowManager.windows[0].viewport.detachedFromCursor
    check e.windowManager.windows[0].cursor == BufferPosition(line: 1, column: 2)

    check e.handleTextInput("j")
    check not e.windowManager.windows[0].viewport.detachedFromCursor

  test "outcome identifies the scrollable region and viewport movement":
    let e =
      createTestEditorWithBuffer("0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14")
    e.state.showTabLine = true
    e.state.showStatusLine = true
    e.screenSize.width = 40
    e.windowManager.windows[0].viewport =
      ViewPort(x: 2, y: 3, width: 40, height: 8, topLine: 0, leftColumn: 0)
    e.windowManager.windows[0].cursor = BufferPosition(line: 6, column: 0)

    let outcome = e.handleScrollInput(initScrollInput(5, 10, 4))

    check outcome.handled
    check outcome.region == initGridRegion(4, 2, 6, 40)
    check outcome.requestedRows == 4
    check outcome.appliedRows == 4
    check outcome.viewportPhysicalRowsMoved == 4
    check e.windowManager.windows[0].cursor.line == 6

  test "outcome reports the movement actually applied at a buffer edge":
    let e = createTestEditorWithBuffer("0\n1\n2")
    e.windowManager.windows[0].cursor = BufferPosition(line: 1, column: 0)

    let outcome = e.handleScrollInput(initScrollInput(2, 10, 8))

    check outcome.handled
    check outcome.requestedRows == 8
    check outcome.appliedRows == 2
    check outcome.viewportPhysicalRowsMoved == 2
    check e.viewport.topLine == 2
    check e.viewport.detachedFromCursor

    let beyondEdge = e.handleScrollInput(initScrollInput(2, 10, 1))

    check beyondEdge.handled
    check beyondEdge.appliedRows == 0
    check beyondEdge.viewportPhysicalRowsMoved == 0
    check e.viewport.topLine == 2
    check e.viewport.detachedFromCursor

  test "zero row input produces an unhandled outcome":
    let e = createTestEditorWithBuffer("0\n1\n2")

    let outcome = e.handleScrollInput(initScrollInput(2, 10, 0))

    check not outcome.handled
    check outcome.requestedRows == 0
    check outcome.appliedRows == 0
    check outcome.viewportPhysicalRowsMoved == 0
    check outcome.region == GridRegion()

  test "unsupported mode produces an unhandled outcome":
    let e = createTestEditorWithBuffer("0\n1\n2")
    e.state.mode = EditorMode.Help

    let outcome = e.handleScrollInput(initScrollInput(2, 10, 1))

    check not outcome.handled
    check outcome.requestedRows == 1
    check outcome.appliedRows == 0
    check outcome.viewportPhysicalRowsMoved == 0
    check outcome.region == GridRegion()

  test "wrapped text outcome remains physical-line based":
    let e = createTestEditorWithBuffer("abcdefghij\nnext")
    e.state.lineWrap = true
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 5, height: 2, topLine: 0, leftColumn: 0)

    let outcome = e.handleScrollInput(initScrollInput(0, 0, 1))

    check outcome.handled
    check outcome.appliedRows == 1
    check outcome.viewportPhysicalRowsMoved == 1
    check e.viewport.topLine == 0
    check e.viewport.topWrapOffset == 1
    check e.cursor.line == 0

  test "Filer outcome reports selection movement before layout":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Filer
    var filerState =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 0, showHidden: false)
    for i in 0 ..< 10:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)

    let outcome = e.handleScrollInput(initScrollInput(0, 0, 3))

    check outcome.handled
    check outcome.appliedRows == 3
    check outcome.viewportPhysicalRowsMoved == 0
    check e.activeWindow.modeState.filer.selectedIndex == 3

  test "outcome region follows the split window under the pointer":
    let e = createTestEditorWithBuffer("left0\nleft1\nleft2\nleft3")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    e.screenSize.width = 80
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 40, height: 24, topLine: 0, leftColumn: 0)
    let rightBuffer = newTextBuffer("right0\nright1\nright2\nright3\nright4")
    let rightWindow = EditorWindow(
      viewBuffer: rightBuffer,
      tabBufferId: rightBuffer.id,
      bufferIds: @[rightBuffer.id],
      viewport: ViewPort(x: 40, y: 0, width: 40, height: 24, topLine: 0, leftColumn: 0),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
      mode: EditorMode.Normal,
    )
    e.windowManager.windows.add(rightWindow)

    let outcome = e.handleScrollInput(initScrollInput(5, 50, 3))

    check outcome.handled
    check outcome.region == initGridRegion(0, 40, 23, 40)
    check outcome.appliedRows == 3
    check e.windowManager.windows[0].cursor.line == 0
    check e.windowManager.windows[1].cursor.line == 0
    check e.windowManager.windows[1].viewport.topLine == 3

  test "primary press uses rendered grid coordinates":
    let e = createTestEditorWithBuffer("zero\none\ntwo\nthree")
    e.state.showTabLine = false
    e.state.showStatusLine = true

    let handled = e.handlePointerInput(initPointerInput(2, 8))

    check handled
    check e.cursor.line == 2

  test "a click in another window ends Visual in the window left":
    let e = createTestEditorWithBuffer("left window text")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 20, height: 10, topLine: 0, leftColumn: 0)
    let rightBuffer = newTextBuffer("right window text")
    let rightWindow = EditorWindow(
      viewBuffer: rightBuffer,
      tabBufferId: rightBuffer.id,
      bufferIds: @[rightBuffer.id],
      viewport: ViewPort(x: 20, y: 0, width: 20, height: 10, topLine: 0, leftColumn: 0),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
      mode: EditorMode.Normal,
    )
    e.windowManager.windows.add(rightWindow)
    let leftWindow = e.activeWindow
    e.state.selectVisual(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 4)
    )

    check e.handlePointerInput(initPointerInput(0, 25))

    check e.activeWindow == rightWindow
    check leftWindow.mode == EditorMode.Normal
    check not leftWindow.visualSelection.active

  test "empty split tab-line area does not move the cursor":
    let e = createTestEditorWithBuffer("left window text")
    e.state.showTabLine = true
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 20, height: 10, topLine: 0, leftColumn: 0)
    let rightBuffer = newTextBuffer("right window text")
    let rightWindow = EditorWindow(
      viewBuffer: rightBuffer,
      tabBufferId: rightBuffer.id,
      bufferIds: @[rightBuffer.id],
      viewport: ViewPort(x: 20, y: 0, width: 20, height: 10, topLine: 0, leftColumn: 0),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
      mode: EditorMode.Normal,
    )
    e.windowManager.windows.add(rightWindow)
    e.cursor = BufferPosition(line: 0, column: 1)

    let handled = e.handlePointerInput(initPointerInput(0, 18))

    check not handled
    check e.windowManager.activeWindowIndex == 0
    check e.cursor == BufferPosition(line: 0, column: 1)

  test "non-primary pointer input remains available to the host":
    let e = createTestEditorWithBuffer("zero\none")

    let handled = e.handlePointerInput(initPointerInput(1, 5, button = pbSecondary))

    check not handled
    check e.cursor.line == 0

  test "primary click remains a caret and finalizes its gesture on release":
    let e = createTestEditorWithBuffer("alpha beta")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false

    check e.handlePointerInput(initPointerInput(0, 3))
    check e.cursor == BufferPosition(line: 0, column: 3)
    check e.state.mode == EditorMode.Normal
    check not e.state.visualSelection.active
    check e.state.pointerSelection.active

    check e.handlePointerInput(initPointerInput(0, 3, action = paRelease))
    check not e.state.pointerSelection.active
    check not e.state.visualSelection.active

  test "primary drag creates and release updates a character selection":
    let e = createTestEditorWithBuffer("alpha beta\nsecond line")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false

    check e.handlePointerInput(initPointerInput(0, 1))
    check e.handlePointerInput(initPointerInput(1, 3, action = paDrag))
    check e.state.mode == EditorMode.Visual
    check e.state.previousMode == EditorMode.Normal
    check e.state.visualSelection ==
      VisualSelection(
        start: BufferPosition(line: 0, column: 1),
        current: BufferPosition(line: 1, column: 3),
        active: true,
        kind: vskChar,
      )

    check e.handlePointerInput(initPointerInput(1, 5, action = paRelease))
    check e.state.visualSelection.current == BufferPosition(line: 1, column: 5)
    check e.cursor == BufferPosition(line: 1, column: 5)
    check not e.state.pointerSelection.active

  test "double-click selects a word and word drag keeps the press granularity":
    let e = createTestEditorWithBuffer("alpha beta gamma")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false

    check e.handlePointerInput(initPointerInput(0, 7, clickCount = 2))
    check e.state.mode == EditorMode.Visual
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 6)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 9)

    # GUI drag events commonly report clickCount=0/1. Moe retains the
    # double-click granularity established by the press.
    check e.handlePointerInput(initPointerInput(0, 1, action = paDrag))
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 9)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 0)
    check e.selectedText() == "alpha beta"

    check e.handlePointerInput(initPointerInput(0, 1, action = paRelease))
    check not e.state.pointerSelection.active

  test "triple-click and drag creates a line selection":
    let e = createTestEditorWithBuffer("zero\none\ntwo")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false

    check e.handlePointerInput(initPointerInput(1, 2, clickCount = 3))
    check e.state.mode == EditorMode.VisualLine
    check e.state.visualSelection.start == BufferPosition(line: 1, column: 0)
    check e.state.visualSelection.current == BufferPosition(line: 1, column: 0)

    check e.handlePointerInput(initPointerInput(2, 2, action = paDrag))
    check e.state.visualSelection.current == BufferPosition(line: 2, column: 0)
    check e.selectedText() == "one\ntwo\n"

  test "Shift-primary press extends from the existing caret":
    let e = createTestEditorWithBuffer("alpha beta")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.cursor = BufferPosition(line: 0, column: 2)

    check e.handlePointerInput(
      initPointerInput(0, 7, modifiers = {frontend_input.kmShift})
    )
    check e.state.mode == EditorMode.Visual
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 2)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 7)

  test "Shift-double-click expands the word containing the caret":
    let e = createTestEditorWithBuffer("alpha beta gamma")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.cursor = BufferPosition(line: 0, column: 8)

    check e.handlePointerInput(
      initPointerInput(0, 7, clickCount = 2, modifiers = {frontend_input.kmShift})
    )
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 6)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 9)
    check e.selectedText() == "beta"

  test "Shift-double-click extends forward from the caret through a word":
    let e = createTestEditorWithBuffer("alpha beta gamma")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.cursor = BufferPosition(line: 0, column: 2)

    check e.handlePointerInput(
      initPointerInput(0, 7, clickCount = 2, modifiers = {frontend_input.kmShift})
    )
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 2)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 9)

  test "Shift-double-click extends backward from the caret through a word":
    let e = createTestEditorWithBuffer("alpha beta gamma")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.cursor = BufferPosition(line: 0, column: 13)

    check e.handlePointerInput(
      initPointerInput(0, 7, clickCount = 2, modifiers = {frontend_input.kmShift})
    )
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 13)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 6)

  test "Shift-primary press preserves an existing block selection kind":
    let e = createTestEditorWithBuffer("alpha\nbeta\ngamma")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.state.mode = EditorMode.VisualBlock
    e.state.previousMode = EditorMode.Normal
    e.state.selectVisual(
      BufferPosition(line: 0, column: 1), BufferPosition(line: 1, column: 2), vskBlock
    )

    check e.handlePointerInput(
      initPointerInput(2, 4, modifiers = {frontend_input.kmShift})
    )
    check e.state.mode == EditorMode.VisualBlock
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 1)
    check e.state.visualSelection.current == BufferPosition(line: 2, column: 4)

  test "dragging from Insert mode commits the edit transaction before Visual mode":
    let e = createTestEditorWithBuffer("alpha beta")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.state.mode = EditorMode.Insert
    discard e.activeBuffer.beginTransaction("Insert mode edit")

    check e.handlePointerInput(initPointerInput(0, 1))
    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.inTransaction
    check e.handlePointerInput(initPointerInput(0, 4, action = paDrag))
    check e.state.mode == EditorMode.Visual
    check e.state.previousMode == EditorMode.Normal
    check not e.activeBuffer.inTransaction
    check e.state.visualSelection.active

  test "a press after Ctrl-o resumes Insert, so a drag starts as from Insert":
    # Vim reads the press as the command Ctrl-o runs.
    let e = createTestEditorWithBuffer("alpha beta")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.state.mode = EditorMode.Normal
    check e.handleKeyCombo(parseKeyCombo("i").get)
    check e.handleKeyCombo(parseKeyCombo("C-o").get)

    check e.handlePointerInput(initPointerInput(0, 1))
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone
    check e.activeBuffer.inTransaction
    check e.handlePointerInput(initPointerInput(0, 4, action = paDrag))

    check e.state.mode == EditorMode.Visual
    check e.state.previousMode == EditorMode.Normal
    check not e.activeBuffer.inTransaction
    check not e.state.editState.typing.open

  test "drag remains bound to the split where its press began":
    let e = createTestEditorWithBuffer("left")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 20, height: 10, topLine: 0, leftColumn: 0)
    let rightBuffer = newTextBuffer("right side")
    let rightWindow = EditorWindow(
      viewBuffer: rightBuffer,
      tabBufferId: rightBuffer.id,
      bufferIds: @[rightBuffer.id],
      viewport: ViewPort(x: 20, y: 0, width: 20, height: 10, topLine: 0, leftColumn: 0),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
      mode: EditorMode.Normal,
    )
    e.windowManager.windows.add(rightWindow)

    check e.handlePointerInput(initPointerInput(0, 22))
    check e.windowManager.activeWindowIndex == 1
    check e.handlePointerInput(initPointerInput(0, 25, action = paDrag))
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 2)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 5)

    check e.handlePointerInput(initPointerInput(0, 2, action = paDrag))
    check e.windowManager.activeWindowIndex == 1
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 5)
    check e.handlePointerInput(initPointerInput(0, 2, action = paRelease))
    check not e.state.pointerSelection.active

  test "key input cancels an unfinished pointer gesture":
    let e = createTestEditorWithBuffer("alpha beta")
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false

    check e.handlePointerInput(initPointerInput(0, 1))
    check e.state.pointerSelection.active
    check e.handleTextInput("l")
    check not e.state.pointerSelection.active
    check not e.handlePointerInput(initPointerInput(0, 5, action = paDrag))

suite "handleMouseEvent - Wheel Scroll":
  test "WheelDown scrolls the viewport down by 3 lines":
    let e = createTestEditorWithBuffer(
      "line0\nline1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9"
    )
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 0
    check e.windowManager.windows[0].viewport.topLine == 3

  test "WheelUp at the buffer top leaves the viewport and cursor unchanged":
    let e = createTestEditorWithBuffer(
      "line0\nline1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9"
    )
    e.windowManager.windows[0].cursor = BufferPosition(line: 6, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 6
    check e.windowManager.windows[0].viewport.topLine == 0

  test "WheelUp clamps the viewport to line 0":
    let e = createTestEditorWithBuffer("line0\nline1\nline2\nline3\nline4")
    e.windowManager.windows[0].cursor = BufferPosition(line: 1, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 1
    check e.windowManager.windows[0].viewport.topLine == 0

  test "WheelDown moves the viewport by the requested rows near the end":
    let e = createTestEditorWithBuffer("line0\nline1\nline2\nline3\nline4")
    e.windowManager.windows[0].cursor = BufferPosition(line: 3, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 3
    check e.windowManager.windows[0].viewport.topLine == 3

  test "WheelDown preserves the cursor column across shorter lines":
    let e = createTestEditorWithBuffer("long line here\nhi\nshort\nanother\nmore\nend")
    # Start on long line with column beyond short line's length
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 10)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor == BufferPosition(line: 0, column: 10)
    check e.windowManager.windows[0].viewport.topLine == 3

  test "WheelDown preserves a multibyte cursor column":
    let e = createTestEditorWithBuffer("あいうえお\nxx\nxx\nab")
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 4)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor == BufferPosition(line: 0, column: 4)
    check e.windowManager.windows[0].viewport.topLine == 3

  test "WheelDown moves the viewport while preserving a visible cursor":
    # Create a buffer with many lines and a small viewport (height=5)
    var lines: string
    for i in 0 ..< 30:
      if i > 0:
        lines.add "\n"
      lines.add "line" & $i
    let e = createTestEditorWithBuffer(lines)
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 5, topLine: 0, leftColumn: 0)
    e.windowManager.windows[0].cursor = BufferPosition(line: 3, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 2)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 3
    check e.windowManager.windows[0].viewport.topLine == 3

  test "WheelUp moves the viewport without moving a cursor below the visible rows":
    var lines: string
    for i in 0 ..< 30:
      if i > 0:
        lines.add "\n"
      lines.add "line" & $i
    let e = createTestEditorWithBuffer(lines)
    # Viewport starts at line 10 with height 5 (visible lines 10..14)
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 5, topLine: 10, leftColumn: 0)
    e.windowManager.windows[0].cursor = BufferPosition(line: 11, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 2)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 11
    check e.windowManager.windows[0].viewport.topLine == 7

  test "WheelDown moves the viewport without moving a cursor above the visible rows":
    var lines: string
    for i in 0 ..< 30:
      if i > 0:
        lines.add "\n"
      lines.add "line" & $i
    let e = createTestEditorWithBuffer(lines)
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 10, topLine: 0, leftColumn: 0)
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 2)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 0
    check e.windowManager.windows[0].viewport.topLine == 3

  test "Non-press mouse event is ignored":
    let e = createTestEditorWithBuffer("line0\nline1\nline2\nline3")
    let event = Event(
      kind: EventKind.Mouse,
      mouse: MouseEvent(
        kind: MouseEventKind.Release,
        button: mouse_logic.MouseButton.WheelDown,
        x: 10,
        y: 5,
      ),
    )

    let handled = e.handleMouseEvent(event)
    check handled == false

  test "Right button click is ignored":
    let e = createTestEditorWithBuffer("line0\nline1")
    let event = Event(
      kind: EventKind.Mouse,
      mouse: MouseEvent(
        kind: MouseEventKind.Press, button: mouse_logic.MouseButton.Right, x: 10, y: 5
      ),
    )

    let handled = e.handleMouseEvent(event)
    check handled == false

suite "handleMouseEvent - Wheel Scroll Multi-Window":
  test "WheelDown on non-active window scrolls that window":
    let e = createTestEditorWithBuffer(
      "line0\nline1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9"
    )
    # Shrink first window to left half
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 40, height: 24, topLine: 0, leftColumn: 0)
    # Create a second window for the right half
    let buf2 = newTextBuffer("a0\na1\na2\na3\na4\na5\na6\na7\na8\na9")
    let win2 = EditorWindow(
      viewBuffer: buf2,
      tabBufferId: buf2.id,
      bufferIds: @[buf2.id],
      viewport: ViewPort(x: 40, y: 0, width: 40, height: 24, topLine: 0, leftColumn: 0),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
      mode: EditorMode.Normal,
    )
    e.windowManager.windows.add(win2)

    # Wheel event at x=50 (within second window's viewport: x=40..79)
    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 50, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    # Second window should scroll, not first
    check e.windowManager.windows[1].cursor.line == 0
    check e.windowManager.windows[1].viewport.topLine == 3
    check e.windowManager.windows[0].cursor.line == 0

suite "handleMouseEvent - Wheel Scroll Filer Mode":
  test "WheelDown scrolls filer selection down":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Filer

    var filerState =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 0, showHidden: false)
    # Add dummy entries
    for i in 0 ..< 20:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].modeState.filer.selectedIndex == 3

  test "WheelUp scrolls filer selection up":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Filer

    var filerState =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 5, showHidden: false)
    for i in 0 ..< 20:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].modeState.filer.selectedIndex == 2

  test "WheelUp clamps filer selection to 0":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Filer

    var filerState =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 1, showHidden: false)
    for i in 0 ..< 10:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].modeState.filer.selectedIndex == 0

  test "WheelDown clamps filer selection to last entry":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Filer

    var filerState =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 8, showHidden: false)
    for i in 0 ..< 10:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].modeState.filer.selectedIndex == 9

proc makeLeftClickEvent(x, y: int): Event =
  Event(
    kind: EventKind.Mouse,
    mouse: MouseEvent(
      kind: MouseEventKind.Press, button: mouse_logic.MouseButton.Left, x: x, y: y
    ),
  )

proc createFilerEditor(
    entryCount: int, topLine: int = 0, selectedIndex: int = 0
): Editor =
  ## Create a minimal editor in Filer mode with dummy entries
  result = createTestEditorWithBuffer("")
  result.state.mode = EditorMode.Filer
  var filerState = FilerState(
    currentPath: "/tmp", entries: @[], selectedIndex: selectedIndex, showHidden: false
  )
  for i in 0 ..< entryCount:
    filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
  result.windowManager.windows[0].modeState =
    ModeState(kind: mskFiler, filer: filerState)
  result.windowManager.windows[0].viewport.topLine = topLine

suite "handleMouseEvent - Left Click Filer Mode":
  test "Click selects correct entry (no tab line)":
    let e = createFilerEditor(20)
    e.state.showTabLine = false
    e.state.showStatusLine = true

    # Click on y=3 → should select entry 3 (topLine=0, no tab offset)
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 3))

    check handled == true
    check e.windowManager.windows[0].modeState.filer.selectedIndex == 3

  test "Click selects correct entry with tab line offset":
    let e = createFilerEditor(20)
    e.state.showTabLine = true
    e.state.showStatusLine = true

    # Click on y=3 with tab line → adjustedY = 3 - 1 = 2 → entry 2
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 3))

    check handled == true
    check e.windowManager.windows[0].modeState.filer.selectedIndex == 2

  test "Click selects correct entry with topLine offset":
    let e = createFilerEditor(20, topLine = 5)
    e.state.showTabLine = false
    e.state.showStatusLine = true

    # Click on y=2, topLine=5 → entry 5 + 2 = 7
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 2))

    check handled == true
    check e.windowManager.windows[0].modeState.filer.selectedIndex == 7

  test "Click selects correct entry with both tab line and topLine":
    let e = createFilerEditor(20, topLine = 5)
    e.state.showTabLine = true
    e.state.showStatusLine = true

    # Click on y=4, tab offset=1 → adjustedY=3, topLine=5 → entry 8
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 4))

    check handled == true
    check e.windowManager.windows[0].modeState.filer.selectedIndex == 8

  test "Click on tab line area is ignored":
    let e = createFilerEditor(20)
    e.state.showTabLine = true
    e.state.showStatusLine = true

    # Click on y=0 (tab line row) → adjustedY = -1 → should be ignored
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 0))

    check handled == false

  test "Click on status line area is ignored":
    # viewport height=24, statusLine+cmdLine=2 reserved lines
    # valid filer area: y in [0..21] (without tab line)
    let e = createFilerEditor(20)
    e.state.showTabLine = false
    e.state.showStatusLine = true

    # Click on y=23 (last row, command line area) → adjustedY=23 >= 24-2=22 → ignored
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 23))

    check handled == false

  test "Click beyond entry count is ignored":
    let e = createFilerEditor(3)
    e.state.showTabLine = false
    e.state.showStatusLine = true

    # Click on y=5, but only 3 entries → clickedIndex=5 >= 3 → ignored
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 5))

    check handled == false

proc createSplitEditor(multiStatusLine: bool = true): Editor =
  ## Two windows stacked vertically. The bottom window's viewport includes the
  ## shared status/command row (window_manager gives the last window the
  ## remaining height), exactly as equalizeHeightsInGroup lays it out.
  result = createTestEditorWithBuffer("top0\ntop1\ntop2\ntop3\ntop4\ntop5")
  result.state.showTabLine = false
  result.state.multiStatusLine = multiStatusLine
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 12, topLine: 0, leftColumn: 0)

  var content = ""
  for i in 0 ..< 30:
    if i > 0:
      content.add("\n")
    content.add("bottom" & $i)
  let buf2 = newTextBuffer(content)
  result.windowManager.windows.add(
    EditorWindow(
      viewBuffer: buf2,
      tabBufferId: buf2.id,
      bufferIds: @[buf2.id],
      viewport: ViewPort(x: 0, y: 12, width: 80, height: 12, topLine: 0, leftColumn: 0),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
      mode: EditorMode.Normal,
    )
  )

suite "handleMouseEvent - Left Click Multi-Window Bottom Reserve":
  test "Click on command line row is ignored when the status line is hidden":
    # Bottom window: y=12..23, and y=23 is the shared status/command row that
    # the renderer always reserves — independent of showStatusLine.
    let e = createSplitEditor()
    e.state.showStatusLine = false

    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 23))

    check handled == false
    check e.windowManager.activeWindowIndex == 0
    check e.windowManager.windows[1].cursor.line == 0

  test "Click on the last text row still works when the status line is hidden":
    let e = createSplitEditor()
    e.state.showStatusLine = false

    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 22))

    check handled == true
    check e.windowManager.activeWindowIndex == 1
    check e.windowManager.windows[1].cursor.line == 10

  test "Non-bottom window last row is clickable without multiStatusLine":
    # Non-bottom windows reserve a status row only in multiStatusLine mode;
    # otherwise the separator sits outside the viewport.
    let e = createSplitEditor(multiStatusLine = false)
    e.state.showStatusLine = true

    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 11))

    check handled == true
    check e.windowManager.windows[0].cursor.line == 5

proc makeEnterEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))

proc handleCommandModeEvent(e: Editor, event: Event): bool =
  ## A key typed on the command line, the whole way a typed key goes (the
  ## command-line mappings included).
  e.dispatchEvent(event)

suite "handleCommandModeEvent - exitOverlay after command execution":
  ## Regression tests: commands that don't manage overlay themselves must still
  ## exit the command overlay after execution. Previously, converting independent
  ## if-blocks to a case statement caused these branches to skip exitOverlay().

  test "Overlay exited after :5 (gotoLine)":
    let e = createTestEditorWithBuffer("l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":5"
    e.state.input.commandCursor = 1

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited after :bn (bufferNext)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":bn"
    e.state.input.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited after :bp (bufferPrev)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":bp"
    e.state.input.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited after :bf (bufferFirst)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":bf"
    e.state.input.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited after :bl (bufferLast)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":bl"
    e.state.input.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited after :noh (clearSearchHighlight)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":noh"
    e.state.input.commandCursor = 3

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited after :set number (setBoolOption)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":set number"
    e.state.input.commandCursor = 10

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""
    check "number" in e.state.statusMessage

  test "Overlay exited after :set tabstop 4 (setIntOption)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":set tabstop 4"
    e.state.input.commandCursor = 13

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""
    check "tabstop" in e.state.statusMessage

  test "Overlay exited after :enew":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":enew"
    e.state.input.commandCursor = 4

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited after :stripws (stripWhitespace)":
    let e = createTestEditorWithBuffer("hello   \nworld  ")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":stripws"
    e.state.input.commandCursor = 7

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited after empty command (just Enter on ':')":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    # commandText is just ":" (default from enterCommandOverlay)

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test "Overlay exited and error shown after :wq on externally modified file":
    # Regression: :wq early-returned on save failure, skipping exitOverlay() and
    # leaving the editor stuck in command mode with the error message hidden.
    let e = createTestEditorWithBuffer("hello")
    let testFile = getTempDir() / "moe_test_wq_extmod.txt"
    writeFile(testFile, "Original content")
    defer:
      removeFile(testFile)
    check e.loadFile(testFile).isOk

    # Edit the buffer, then simulate an external write newer than our baseline.
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "X")
    e.activeBuffer.applyFileStamp(
      presentStamp(getTime() - initDuration(seconds = 2), 0)
    )
    writeFile(testFile, "Externally modified")

    e.state.enterCommandOverlay()
    e.state.input.commandText = ":wq"
    e.state.input.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true # save refused, editor keeps running
    check not e.state.isCommandOverlay # overlay exited
    check e.state.input.commandText == "" # command line cleared
    check "modified externally" in e.state.statusMessage

suite "handleCommandModeEvent - exitOverlay on self-managed branches":
  test "Overlay exited after :recent with no xbel file (empty list)":
    ## When recently-used.xbel doesn't exist, :recent should still succeed
    ## with an empty file list instead of failing on supported platforms.
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":recent"
    e.state.input.commandCursor = 6

    let origHome = getEnv("HOME")
    putEnv("HOME", getTempDir() / "moe_test_nonexistent_home")
    defer:
      putEnv("HOME", origHome)

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""
    when defined(macosx):
      check e.state.mode == EditorMode.Normal
      check e.state.statusMessage == ":recent is not supported on macOS"
    else:
      check e.state.mode == EditorMode.RecentFile

suite "enterFilerInActiveWindow":
  test "Sets active window to Filer mode":
    let e = createTestEditorWithBuffer("hello")
    e.enterFilerInActiveWindow("/tmp")

    check e.state.mode == EditorMode.Filer
    check e.activeWindow.mode == EditorMode.Filer
    check e.activeWindow.modeState.kind == mskFiler
    check e.activeWindow.cursor == BufferPosition(line: 0, column: 0)
    check e.activeWindow.viewport.topLine == 0
    check e.activeWindow.viewport.leftColumn == 0

  test "Records the covered tab in the viewer entry":
    let e = createTestEditorWithBuffer("hello")
    let originalBuf = e.activeWindow.buffer
    e.enterFilerInActiveWindow("/tmp")

    check e.activeWindow.viewerEntry.get.returnTab == originalBuf.id

  test "Vsplit with directory opens Filer in new split window":
    let e = createTestEditorWithBuffer("hello")
    let originalWinCount = e.windowManager.windows.len

    discard e.vsplit(none(string))
    check e.windowManager.windows.len == originalWinCount + 1

    e.enterFilerInActiveWindow("/tmp")
    check e.state.mode == EditorMode.Filer
    check e.activeWindow.mode == EditorMode.Filer
    check e.activeWindow.modeState.kind == mskFiler

suite "handleCommandModeEvent - :putconfigfile":
  test "Overlay exited and config written":
    withTempHome(tmpDir):
      let e = createTestEditorWithBuffer("hello")
      e.config.theme.kind = tkDefault
      e.config.theme.path = ""
      e.state.enterCommandOverlay()
      e.state.input.commandText = ":putconfigfile"
      e.state.input.commandCursor = 14

      let cont = handleCommandModeEvent(e, makeEnterEvent())

      check cont == true
      check not e.state.isCommandOverlay
      check e.state.input.commandText == ""
      check e.state.mode == EditorMode.Normal
      check "Config written" in e.state.statusMessage

  test "Backup created when config already exists":
    withTempHome(tmpDir):
      let e = createTestEditorWithBuffer("hello")
      e.config.theme.kind = tkDefault
      e.config.theme.path = ""

      let configPath = getConfigPath()
      let backupPath = configPath & ".bac"

      # Ensure config file exists first
      e.state.enterCommandOverlay()
      e.state.input.commandText = ":putconfigfile"
      e.state.input.commandCursor = 14
      discard handleCommandModeEvent(e, makeEnterEvent())
      check fileExists(configPath)

      # Run again to trigger backup
      e.state.enterCommandOverlay()
      e.state.input.commandText = ":putconfigfile"
      e.state.input.commandCursor = 14
      let cont = handleCommandModeEvent(e, makeEnterEvent())

      check cont == true
      check "Config written" in e.state.statusMessage
      check fileExists(backupPath)

  test "Theme file saved when kind is tkConfig":
    withTempHome(tmpDir):
      let themeFile =
        tmpDir / ".config" / "moe" / "themes" / "moe_test_putconfigfile_theme.toml"

      let e = createTestEditorWithBuffer("hello")
      e.config.theme.kind = tkConfig
      e.config.theme.path = themeFile

      e.state.enterCommandOverlay()
      e.state.input.commandText = ":putconfigfile"
      e.state.input.commandCursor = 14

      let cont = handleCommandModeEvent(e, makeEnterEvent())

      check cont == true
      check "Config written" in e.state.statusMessage
      check fileExists(themeFile)

suite "handleCommandModeEvent - all command mode commands execute":
  ## Regression tests ensuring every command properly exits the overlay
  ## and clears commandText after execution.

  # --- Quit/Close ---

  test ":q exits editor (returns false)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":q"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == false

  test ":q! closes window (returns false for single window)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":q!"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == false

  # --- Window ---

  test ":vs vertical split":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":vs"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":sp horizontal split":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":sp"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":new creates new buffer in horizontal split":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":new"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":vnew creates new buffer in vertical split":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":vnew"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  # --- File/Buffer ---

  test ":e opens or creates file":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":e testfile"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":w save (no file path shows error)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":w"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":wq save and quit (save fails without file path)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":wq"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    # Save fails (no file path), processSaveAndQuitResult returns true (continue).
    # The overlay must still be exited so the editor isn't stuck in command mode.
    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":x on a clean unnamed buffer quits without trying to save":
    let e = createTestEditorWithBuffer("hello")
    e.activeBuffer.markSaved()
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":x"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    # A save attempt would fail for this unnamed buffer and return true.
    check cont == false

  test ":x on a modified unnamed buffer preserves save failure behavior":
    let e = createTestEditorWithBuffer("hello")
    e.activeBuffer.markSaved()
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 5), "!")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":x"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check e.activeBuffer.isModified
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":q refuses to quit while a background buffer is modified":
    # An LSP rename edits every file it touches in a buffer that joins no
    # window; quitting on the active buffer alone would drop the rest of it.
    let e = createTestEditorWithBuffer("hello")
    e.activeBuffer.markSaved()
    let background = newTextBuffer("world")
    e.addBuffer(background)
    discard background.insertText(BufferPosition(line: 0, column: 5), "!")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":q"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check "other buffer" in e.state.statusMessage
    check background.isModified

  test ":q! quits despite a modified background buffer":
    let e = createTestEditorWithBuffer("hello")
    e.activeBuffer.markSaved()
    let background = newTextBuffer("world")
    e.addBuffer(background)
    discard background.insertText(BufferPosition(line: 0, column: 5), "!")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":q!"

    check handleCommandModeEvent(e, makeEnterEvent()) == false

  test ":wq refuses to quit while a background buffer is modified":
    let e = createTestEditorWithBuffer("hello")
    let background = newTextBuffer("world")
    e.addBuffer(background)
    discard background.insertText(BufferPosition(line: 0, column: 5), "!")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":wq"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check "other buffer" in e.state.statusMessage

  test ":x on a clean buffer refuses while a background buffer is modified":
    let e = createTestEditorWithBuffer("hello")
    e.activeBuffer.markSaved()
    let background = newTextBuffer("world")
    e.addBuffer(background)
    discard background.insertText(BufferPosition(line: 0, column: 5), "!")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":x"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check "No write since last change" in e.state.statusMessage

  test ":b 0 switch to buffer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":b 0"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":bd delete buffer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":bd"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  # --- Option ---

  test ":set scrollfriction 50 (float option)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":set scrollfriction 50"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""
    check "scrollfriction" in e.state.statusMessage

  # --- Mode transitions ---

  test ":filer enters filer mode":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":filer"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":log enters log viewer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":log"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":help enters help viewer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":help"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":buffers enters buffer manager":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":buffers"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":backup enters backup manager":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":backup"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":jump shows jump list":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":jump"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":build with no file shows error":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":build"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":debug opens debug viewer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":debug"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":config opens configuration mode":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":config"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":quickrun with no file shows error":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":quickrun"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  # --- Theme/Substitute ---

  test ":theme default changes to default theme":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":theme default"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":s/a/b/ substitutes text":
    let e = createTestEditorWithBuffer("abc")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":s/a/b/"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  # --- Misc ---

  test ":!echo hi executes shell command":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":!echo hi"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":bg sends editor to background":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":bg"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":man ls shows man page":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":man ls"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  # --- LSP ---

  test ":lsplog opens LSP log viewer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":lsplog"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":lspformat requests LSP formatting":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":lspformat"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":lsprestart restarts LSP server":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":lsprestart"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":lspfold requests LSP folding":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":lspfold"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":lspexecommand executes LSP command":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":lspexecommand"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":lspcallhierarchyincoming requests incoming calls":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":lspcallhierarchyincoming"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

  test ":lspcallhierarchyoutgoing requests outgoing calls":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":lspcallhierarchyoutgoing"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.input.commandText == ""

proc makeUpArrowEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.ArrowUp))

proc makeDownArrowEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.ArrowDown))

proc makeCharEvent(c: string): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Char, char: c))

proc makeBackspaceEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Backspace))

suite "handleEvent - quit":
  test "Quitting is noted on the editor":
    # A signal from then on must not preserve what `:q!` discarded.
    let e = createTestEditorWithBuffer("hello")
    check not e.state.quitDecided
    var goesOn = true
    for key in [":", "q", "!"]:
      goesOn = e.handleEvent(makeCharEvent(key))
    check goesOn
    check not e.state.quitDecided
    goesOn = e.handleEvent(makeEnterEvent())
    check not goesOn
    check e.state.quitDecided

  test "Quitting through handleKeyCombo directly is noted":
    # GUI frontends can bypass `handleEvent`; the signal answer must still
    # see that the user already quit.
    proc charKey(c: string): KeyCombo =
      KeyCombo(isSpecial: false, char: c, modifiers: {})

    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    let e = createTestEditorWithBuffer("hello")
    check not e.state.quitDecided
    var goesOn = true
    for key in [":", "q", "!"]:
      goesOn = e.handleKeyCombo(charKey(key))
    check goesOn
    check not e.state.quitDecided
    goesOn = e.handleKeyCombo(enterKey)
    check not goesOn
    check e.state.quitDecided

  test "Ordinary input through handleKeyCombo does not note a quit":
    proc charKey(c: string): KeyCombo =
      KeyCombo(isSpecial: false, char: c, modifiers: {})

    let e = createTestEditorWithBuffer("hello")
    check e.handleKeyCombo(charKey("j"))
    check not e.state.quitDecided
    check e.handleTextInput("j")
    check not e.state.quitDecided

suite "Command Mode - History Navigation":
  test "Up with empty history does nothing":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    # No history entries
    e.state.input.commandState.history = @[]

    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    check e.state.input.commandText == ":"
    check e.state.input.commandCursor == 0
    check e.state.input.commandState.historyIndex == -1

  test "Up navigates to most recent entry":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]

    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    check e.state.input.commandText == ":w"
    check e.state.input.commandCursor == 1
    check e.state.input.commandState.historyIndex == 0

  test "Up twice navigates to second entry":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]

    discard handleCommandModeEvent(e, makeUpArrowEvent())
    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    check e.state.input.commandText == ":q"
    check e.state.input.commandCursor == 1
    check e.state.input.commandState.historyIndex == 1

  test "Up stops at oldest entry":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]

    discard handleCommandModeEvent(e, makeUpArrowEvent())
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    # Still at the oldest entry
    check e.state.input.commandText == ":q"
    check e.state.input.commandState.historyIndex == 1

  test "Down navigates to newer entry":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]

    # Navigate to oldest
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    # Navigate back to newer
    let cont = handleCommandModeEvent(e, makeDownArrowEvent())

    check cont == true
    check e.state.input.commandText == ":w"
    check e.state.input.commandCursor == 1
    check e.state.input.commandState.historyIndex == 0

  test "Down from index 0 resets to empty command":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]

    # Navigate to most recent
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    # Navigate past it
    let cont = handleCommandModeEvent(e, makeDownArrowEvent())

    check cont == true
    check e.state.input.commandText == ":"
    check e.state.input.commandCursor == 0
    check e.state.input.commandState.historyIndex == -1

  test "Character input resets historyIndex":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]

    # Navigate into history
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    check e.state.input.commandState.historyIndex == 0

    # Type a character
    discard handleCommandModeEvent(e, makeCharEvent("x"))

    check e.state.input.commandState.historyIndex == -1

  test "Backspace resets historyIndex":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]

    # Navigate into history (sets commandText to ":w")
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    check e.state.input.commandState.historyIndex == 0

    # Backspace
    discard handleCommandModeEvent(e, makeBackspaceEvent())

    check e.state.input.commandState.historyIndex == -1

suite "Command Mode - History Navigation (prefix match)":
  test "Up with typed prefix skips non-matching entries":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["git status", "cd /tmp", "git commit", "ls"]
    # Type "git" before pressing Up
    discard handleCommandModeEvent(e, makeCharEvent("g"))
    discard handleCommandModeEvent(e, makeCharEvent("i"))
    discard handleCommandModeEvent(e, makeCharEvent("t"))

    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    check e.state.input.commandText == ":git status"
    check e.state.input.commandState.historyIndex == 0
    check e.state.input.commandState.historyPrefix == "git"

  test "Successive Up keeps the same locked prefix":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["git status", "cd /tmp", "git commit", "ls"]
    discard handleCommandModeEvent(e, makeCharEvent("g"))
    discard handleCommandModeEvent(e, makeCharEvent("i"))
    discard handleCommandModeEvent(e, makeCharEvent("t"))

    discard handleCommandModeEvent(e, makeUpArrowEvent())
    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    check e.state.input.commandText == ":git commit"
    check e.state.input.commandState.historyIndex == 2
    check e.state.input.commandState.historyPrefix == "git"

  test "Up with no more matches leaves state unchanged":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["git status", "ls"]
    discard handleCommandModeEvent(e, makeCharEvent("g"))
    discard handleCommandModeEvent(e, makeCharEvent("i"))
    discard handleCommandModeEvent(e, makeCharEvent("t"))

    # First Up lands on "git status" (index 0)
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    # Second Up: no other "git" entries; state must not change
    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    check e.state.input.commandText == ":git status"
    check e.state.input.commandState.historyIndex == 0

  test "Up with prefix that matches nothing does not move":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]
    discard handleCommandModeEvent(e, makeCharEvent("z"))

    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    check e.state.input.commandText == ":z"
    check e.state.input.commandState.historyIndex == -1

  test "Down past newest match restores the locked prefix":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["git status", "cd /tmp", "git commit"]
    discard handleCommandModeEvent(e, makeCharEvent("g"))
    discard handleCommandModeEvent(e, makeCharEvent("i"))
    discard handleCommandModeEvent(e, makeCharEvent("t"))

    # Navigate to "git status"
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    # Down past newest match: restore prefix, not empty
    let cont = handleCommandModeEvent(e, makeDownArrowEvent())

    check cont == true
    check e.state.input.commandText == ":git"
    check e.state.input.commandCursor == 3
    check e.state.input.commandState.historyIndex == -1

  test "Down between two matches skips non-matching newer entry":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["git status", "cd /tmp", "git commit"]
    discard handleCommandModeEvent(e, makeCharEvent("g"))
    discard handleCommandModeEvent(e, makeCharEvent("i"))
    discard handleCommandModeEvent(e, makeCharEvent("t"))

    # Up twice: land on "git commit" (index 2), skipping "cd /tmp"
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    check e.state.input.commandState.historyIndex == 2

    # Down: back to "git status" (index 0), skipping "cd /tmp"
    let cont = handleCommandModeEvent(e, makeDownArrowEvent())

    check cont == true
    check e.state.input.commandText == ":git status"
    check e.state.input.commandState.historyIndex == 0

  test "Editing after Up locks a new prefix on the next Up":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["git status", "cd /tmp"]
    discard handleCommandModeEvent(e, makeCharEvent("g"))
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    check e.state.input.commandText == ":git status"

    # Backspace back to empty prefix, then type "cd"
    discard handleCommandModeEvent(e, makeBackspaceEvent())
    while e.state.input.commandText.len > 1:
      discard handleCommandModeEvent(e, makeBackspaceEvent())
    discard handleCommandModeEvent(e, makeCharEvent("c"))
    discard handleCommandModeEvent(e, makeCharEvent("d"))

    let cont = handleCommandModeEvent(e, makeUpArrowEvent())

    check cont == true
    check e.state.input.commandText == ":cd /tmp"
    check e.state.input.commandState.historyIndex == 1
    check e.state.input.commandState.historyPrefix == "cd"

  test "Empty prefix matches every entry (unchanged behavior)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.input.commandState.history = @["w", "q"]

    # No text typed: prefix is empty
    discard handleCommandModeEvent(e, makeUpArrowEvent())
    discard handleCommandModeEvent(e, makeUpArrowEvent())

    check e.state.input.commandText == ":q"
    check e.state.input.commandState.historyIndex == 1
    check e.state.input.commandState.historyPrefix == ""

suite "adjustCursorAfterInsertExit":
  test "Cursor moves one position left (middle of line)":
    var cursor = BufferPosition(line: 0, column: 3)
    adjustCursorAfterInsertExit(cursor, 5)
    check cursor.column == 2

  test "Cursor moves one position left (end of line)":
    var cursor = BufferPosition(line: 0, column: 5)
    adjustCursorAfterInsertExit(cursor, 5)
    check cursor.column == 4

  test "Cursor stays at column 0 (already at beginning)":
    var cursor = BufferPosition(line: 0, column: 0)
    adjustCursorAfterInsertExit(cursor, 5)
    check cursor.column == 0

  test "Cursor stays at column 0 (empty line)":
    var cursor = BufferPosition(line: 0, column: 0)
    adjustCursorAfterInsertExit(cursor, 0)
    check cursor.column == 0

  test "Cursor clamped when beyond line end":
    var cursor = BufferPosition(line: 0, column: 10)
    adjustCursorAfterInsertExit(cursor, 5)
    check cursor.column == 4

  test "Cursor at column 1 moves to column 0":
    var cursor = BufferPosition(line: 0, column: 1)
    adjustCursorAfterInsertExit(cursor, 5)
    check cursor.column == 0

  test "Single character line with cursor at column 1":
    var cursor = BufferPosition(line: 0, column: 1)
    adjustCursorAfterInsertExit(cursor, 1)
    check cursor.column == 0

  test "Single character line with cursor at column 0":
    var cursor = BufferPosition(line: 0, column: 0)
    adjustCursorAfterInsertExit(cursor, 1)
    check cursor.column == 0

proc isClipboardToolAvailable(): bool =
  try:
    let (_, exitCode) = execCmdEx("which xsel")
    if exitCode == 0 and existsEnv("DISPLAY"):
      return true
    let (_, exitCode2) = execCmdEx("which xclip")
    if exitCode2 == 0 and existsEnv("DISPLAY"):
      return true
    let (_, exitCode3) = execCmdEx("which wl-copy")
    if exitCode3 == 0 and existsEnv("WAYLAND_DISPLAY"):
      return true
  except CatchableError:
    discard
  return false

proc getAvailableClipboardTool(): ClipboardTool =
  if existsEnv("WAYLAND_DISPLAY"):
    try:
      let (_, exitCode) = execCmdEx("which wl-copy")
      if exitCode == 0:
        return cbtWlClipboard
    except CatchableError:
      discard
  if existsEnv("DISPLAY"):
    try:
      let (_, exitCode) = execCmdEx("which xsel")
      if exitCode == 0:
        return cbtXsel
    except CatchableError:
      discard
    try:
      let (_, exitCode) = execCmdEx("which xclip")
      if exitCode == 0:
        return cbtXclip
    except CatchableError:
      discard
  return cbtXsel # fallback

proc createTestEditorForMiddleClick(content: string): Editor =
  let config = newEditorConfig()
  config.standard.mouse = true
  config.clipboard.enable = true
  config.clipboard.tool = getAvailableClipboardTool()
  result = newEditor(config)
  let buf = newTextBuffer(content)
  result.windowManager.windows[0].setTab(buf)
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.motionController.viewportManager.viewport = result.viewport
  result.state.mode = EditorMode.Normal

proc middleClickInWindow(e: Editor, row = 2, col = 5) =
  ## Middle-click inside the active window's text area. The cell matters: the
  ## click picks the paste target, not the focused window.
  e.middleClickPaste(row, col)

proc makeMiddleClickEvent(x, y: int): Event =
  Event(
    kind: EventKind.Mouse,
    mouse: MouseEvent(
      kind: MouseEventKind.Press, button: mouse_logic.MouseButton.Middle, x: x, y: y
    ),
  )

suite "Paste cursor position":
  # The paste path takes its cursor from what the insertion reports instead of
  # counting the pasted text, so these exercise that report directly.
  const Grid = "0123456789\n0123456789\n0123456789\n0123456789\n0123456789"

  proc pasteCursor(start: BufferPosition, pasted: string): BufferPosition =
    let b = newTextBuffer(Grid)
    let r = b.insertTextEnd(start, pasted)
    doAssert r.isOk
    r.get.cursor

  test "Empty text leaves cursor at start position":
    let after = pasteCursor(BufferPosition(line: 3, column: 7), "")
    check after.line == 3
    check after.column == 7

  test "Single-line ASCII advances column by character count":
    let after = pasteCursor(BufferPosition(line: 0, column: 5), " world")
    check after.line == 0
    check after.column == 11

  test "Multibyte characters advance by character, not byte":
    # "café" is 4 characters / 5 bytes: byte counting would land at column 5.
    let after = pasteCursor(BufferPosition(line: 0, column: 0), "café")
    check after.line == 0
    check after.column == 4

  test "LF resets column and increments line":
    let after = pasteCursor(BufferPosition(line: 2, column: 4), "\nabc")
    check after.line == 3
    check after.column == 3

  test "Multiple newlines advance across several lines":
    let after = pasteCursor(BufferPosition(line: 0, column: 2), "a\nbb\nccc")
    check after.line == 2
    check after.column == 3

  test "Trailing newline lands cursor at column 0 of next line":
    let after = pasteCursor(BufferPosition(line: 1, column: 3), "xy\n")
    check after.line == 2
    check after.column == 0

  test "Start column is preserved when the text stays on the same line":
    let after = pasteCursor(BufferPosition(line: 4, column: 10), "z")
    check after.line == 4
    check after.column == 11

  test "Completing a split character reports the merged column":
    let b = newTextBuffer("\xF0")
    let r = b.insertTextEnd(BufferPosition(line: 0, column: 1), "\x9F\x98\x81")
    check r.isOk
    check b.getLine(0).charLen == 1
    check r.get.cursor.column == 1

suite "handlePasteText":
  test "Insert mode paste sanitizes invalid UTF-8":
    let e = createTestEditorForMiddleClick("hello")
    e.state.mode = EditorMode.Insert
    discard e.activeBuffer.beginTransaction("Insert mode edit")
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 5)

    # 0xC0 is an invalid UTF-8 leading byte; 0x41 is ASCII 'A'
    discard e.handlePasteText("\xC0\x41ok")

    let line = e.activeBuffer.getLine(0)
    check $line == "hello" & "\xEF\xBF\xBD" & "Aok"
    # Cursor advances by rune count: 4 runes inserted
    check e.windowManager.windows[0].cursor.column == 9

suite "middleClickPaste":
  test "Clipboard disabled":
    let e = createTestEditorForMiddleClick("hello")
    e.config.clipboard.enable = false
    e.state.mode = EditorMode.Insert
    discard e.activeBuffer.beginTransaction("test")

    e.middleClickInWindow()

    # Buffer should be unchanged
    check e.activeBuffer.getLine(0) == "hello"

  test "Unsupported mode (Visual)":
    let e = createTestEditorForMiddleClick("hello")
    e.state.mode = EditorMode.Visual

    e.middleClickInWindow()

    check e.activeBuffer.getLine(0) == "hello"

  test "Read-only buffer in Normal mode does not enter Insert or move cursor":
    let e = createTestEditorForMiddleClick("hello")
    # Reported via notify, so pin the route this test asserts on.
    e.config.notification.popupNotifications = false
    e.state.mode = EditorMode.Normal
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)
    e.activeBuffer.readOnly = true

    e.middleClickInWindow()

    check e.state.mode == EditorMode.Normal
    check e.state.statusMessage == "Buffer is read-only"
    check e.activeBuffer.getLine(0) == "hello"
    check e.windowManager.windows[0].cursor.line == 0
    check e.windowManager.windows[0].cursor.column == 0
    check not e.activeBuffer.inTransaction

  test "Normal mode - failed primary selection read leaves no open transaction":
    let e = createTestEditorForMiddleClick("hello")
    # win32yank.exe does not exist here, so the primary selection read fails.
    e.config.clipboard.tool = cbtWin32yank
    e.config.notification.popupNotifications = false
    e.state.mode = EditorMode.Normal
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)
    e.state.notificationPopup.queue = @[]
    e.state.setStatusQuiet("")
    clearMessageLog()

    e.middleClickInWindow()

    check e.state.mode == EditorMode.Normal
    check not e.activeBuffer.inTransaction
    check e.activeBuffer.getLine(0) == "hello"
    # notify() routes by config, so assert the exact route for each value
    # instead of a disjunction that holds whichever one fired.
    check e.state.statusMessage.contains("Paste failed")
    check e.state.notificationPopup.queue.len == 0

  test "Normal mode - failed primary selection read routes to popup when enabled":
    let e = createTestEditorForMiddleClick("hello")
    e.config.clipboard.tool = cbtWin32yank
    e.config.notification.popupNotifications = true
    e.state.mode = EditorMode.Normal
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)
    e.state.notificationPopup.queue = @[]
    e.state.setStatusQuiet("")
    clearMessageLog()

    e.middleClickInWindow()

    check e.state.notificationPopup.queue.len == 1
    check e.state.notificationPopup.queue[0].message.contains("Paste failed")
    check e.state.notificationPopup.queue[0].level == nlError
    check not e.state.statusMessage.contains("Paste failed")

  test "Normal mode - failed primary selection read with overlay uses the popup":
    # The overlay draws over the status row, so the configured route has nowhere
    # to put the message: routing it to the popup is what makes the failure
    # visible at all, instead of a paste that silently does nothing.
    let e = createTestEditorForMiddleClick("hello")
    e.config.clipboard.tool = cbtWin32yank
    e.config.notification.popupNotifications = false
    e.state.overlay = some(okCommand)
    e.state.mode = EditorMode.Normal
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)
    e.state.notificationPopup.queue = @[]
    e.state.setStatusQuiet("")
    clearMessageLog()

    e.middleClickInWindow()

    check e.state.mode == EditorMode.Normal
    check not e.activeBuffer.inTransaction
    check e.state.notificationPopup.queue.len == 1
    check e.state.notificationPopup.queue[0].message.contains("Paste failed")
    check not e.state.statusMessage.contains("Paste failed")
    check getMessageLog().len == 1
    check getMessageLog()[0].contains("Paste failed")

  test "Insert mode - paste from clipboard":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "middle_click_test"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("hello")
      e.state.mode = EditorMode.Insert
      discard e.activeBuffer.beginTransaction("Insert mode edit")
      e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 5)

      e.middleClickInWindow()

      let line = e.activeBuffer.getLine(0)
      check $line == "hello" & testText

  test "Insert mode - invalid UTF-8 in selection is sanitized":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      # 0xC0 is an invalid UTF-8 leading byte; 0x41 is ASCII 'A'
      let writeResult = writeToPrimarySelectionSync(tool, "\xC0\x41")
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("hello")
      e.state.mode = EditorMode.Insert
      discard e.activeBuffer.beginTransaction("Insert mode edit")
      e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 5)

      e.middleClickInWindow()

      let line = e.activeBuffer.getLine(0)
      check $line == "hello" & "\xEF\xBF\xBD" & "A"

  test "Normal mode - auto enter Insert mode and paste":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "normal_paste"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("hello")
      e.state.mode = EditorMode.Normal
      e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)

      e.middleClickInWindow()

      check e.state.mode == EditorMode.Insert
      let line = e.activeBuffer.getLine(0)
      check $line == testText & "hello"

  test "Normal mode - failed insert rolls back and returns to Normal":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "normal_fail_paste"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("hello")
      e.state.mode = EditorMode.Normal
      # Out-of-bounds line makes insertText fail, hitting the rollback path
      e.windowManager.windows[0].cursor = BufferPosition(line: 5, column: 0)

      e.middleClickInWindow()

      check e.state.mode == EditorMode.Normal
      check not e.activeBuffer.inTransaction
      check e.activeBuffer.getLine(0) == "hello"
      check e.activeBuffer.len == 1
      check e.windowManager.windows[0].cursor.line == 5
      check e.state.statusMessage == "Paste failed: Line position out of bounds: 5"

  test "Normal mode - failed insert clears the Insert indicator with popups on":
    # The paste puts "-- INSERT --" on the status row before inserting. With
    # popups enabled the failure never overwrites it, so the row would keep
    # advertising Insert while the editor is back in Normal.
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let writeResult = writeToPrimarySelectionSync(tool, "indicator_paste")
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("hello")
      e.config.notification.popupNotifications = true
      e.state.mode = EditorMode.Normal
      e.state.notificationPopup.queue = @[]
      e.state.setStatusQuiet("")
      # Out-of-bounds line makes insertText fail, hitting the rollback path
      e.windowManager.windows[0].cursor = BufferPosition(line: 5, column: 0)

      e.middleClickInWindow()

      check e.state.mode == EditorMode.Normal
      check e.state.statusMessage == ""
      check e.state.notificationPopup.queue.len == 1
      check e.state.notificationPopup.queue[0].message.contains("Paste failed")

  test "Insert mode - failed insert leaves joined session transaction open":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "insert_fail_paste"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("hello")
      e.state.mode = EditorMode.Insert
      discard e.activeBuffer.beginTransaction("Insert mode edit")
      e.windowManager.windows[0].cursor = BufferPosition(line: 5, column: 0)

      e.middleClickInWindow()

      check e.state.mode == EditorMode.Insert
      check e.activeBuffer.inTransaction
      check e.activeBuffer.getLine(0) == "hello"
      check e.state.statusMessage == "Paste failed: Line position out of bounds: 5"

  test "Insert mode without transaction - failed insert rolls back the paste's own transaction":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "insert_own_txn_fail_paste"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("hello")
      e.state.mode = EditorMode.Insert
      # No beginTransaction here, so middleClickPaste opens its own. The
      # out-of-bounds line makes insertText fail, hitting the own-transaction
      # rollback path (enteringInsertFromNormal is false here, so no mode
      # switch happens).
      e.windowManager.windows[0].cursor = BufferPosition(line: 5, column: 0)

      e.middleClickInWindow()

      check e.state.mode == EditorMode.Insert
      check not e.activeBuffer.inTransaction
      check e.activeBuffer.getLine(0) == "hello"
      check e.activeBuffer.len == 1
      check e.windowManager.windows[0].cursor.line == 5
      check e.state.statusMessage == "Paste failed: Line position out of bounds: 5"

  test "Insert mode - multiline paste":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "line1\nline2"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("")
      e.state.mode = EditorMode.Insert
      discard e.activeBuffer.beginTransaction("Insert mode edit")

      e.middleClickInWindow()

      check e.activeBuffer.len >= 2
      check $e.activeBuffer.getLine(0) == "line1"
      check $e.activeBuffer.getLine(1) == "line2"
      check e.windowManager.windows[0].cursor.line == 1
      check e.windowManager.windows[0].cursor.column == 5

  test "Command overlay - paste first line only":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "hello world"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("")
      e.state.enterCommandOverlay()

      e.middleClickInWindow()

      check e.state.input.commandText == ":hello world"
      check e.state.input.commandCursor == testText.len

  test "Command overlay - multiline paste keeps only first line":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "first\nsecond"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("")
      e.state.enterCommandOverlay()

      e.middleClickInWindow()

      check e.state.input.commandText == ":first"
      check e.state.input.commandCursor == 5

  test "Search overlay - paste appends first line":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "needle\nignored"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("haystack needle")
      e.state.enterSearchOverlay(SearchDirection.Forward)

      e.middleClickInWindow()

      check e.state.input.search.text == "needle"

  test "handleEvent dispatches middle-click even when mouse config disabled":
    if not isClipboardToolAvailable():
      skip()
    else:
      let tool = getAvailableClipboardTool()
      let testText = "event_test"
      let writeResult = writeToPrimarySelectionSync(tool, testText)
      check writeResult.isOk
      sleep(100)

      let e = createTestEditorForMiddleClick("hello")
      e.config.standard.mouse = false # Mouse disabled
      e.state.mode = EditorMode.Normal

      # Row 0 is the tab line; the cell has to land in the text area.
      let event = makeMiddleClickEvent(5, 2)
      discard e.handleEvent(event)

      check e.state.mode == EditorMode.Insert
      let line = e.activeBuffer.getLine(0)
      check ($line).len > 5 # Text was inserted

  test "a middle-click that pastes nothing leaves the viewport detached":
    # The reattach belongs to the insertion, the way the left-click one belongs
    # to the cursor move: a click that inserts nothing must not yank the view
    # back to the cursor.
    let e = createTestEditorForMiddleClick("hello")
    e.config.clipboard.enable = false
    e.viewport.detachedFromCursor = true

    discard e.handleEvent(makeMiddleClickEvent(0, 0))

    check e.viewport.detachedFromCursor

suite "handlePasteEvent":
  proc createTestEditorForPaste(content: string): Editor =
    let config = newEditorConfig()
    result = newEditor(config)
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.viewportManager.viewport = result.viewport

  proc makePasteEvent(text: string): Event =
    Event(kind: EventKind.Paste, pastedText: text)

  test "frontend-neutral paste does not require a Celina event":
    let e = createTestEditorForPaste("")
    e.state.mode = EditorMode.Insert

    discard e.handlePaste("café\r\nnext")

    check $e.activeBuffer.getLine(0) == "café"
    check $e.activeBuffer.getLine(1) == "next"
    check e.cursor == BufferPosition(line: 1, column: 4)

  test "Insert mode with active transaction - paste succeeds":
    let e = createTestEditorForPaste("hello")
    e.state.mode = EditorMode.Insert
    discard e.activeBuffer.beginTransaction("Insert mode edit")
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 5)
    e.state.cursor = BufferPosition(line: 0, column: 5)

    let event = makePasteEvent(" world")
    discard e.handleEvent(event)

    check $e.activeBuffer.getLine(0) == "hello world"
    # Transaction should still be active (owned by Insert mode, not paste)
    check e.activeBuffer.inTransaction

  test "Insert mode without transaction - paste creates own transaction":
    let e = createTestEditorForPaste("hello")
    e.state.mode = EditorMode.Insert
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 5)
    e.state.cursor = BufferPosition(line: 0, column: 5)

    let event = makePasteEvent(" world")
    discard e.handleEvent(event)

    check $e.activeBuffer.getLine(0) == "hello world"
    # Transaction should have been committed by paste
    check not e.activeBuffer.inTransaction

  test "Insert mode with active transaction - multiline paste":
    let e = createTestEditorForPaste("hello")
    e.state.mode = EditorMode.Insert
    discard e.activeBuffer.beginTransaction("Insert mode edit")
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 5)
    e.state.cursor = BufferPosition(line: 0, column: 5)

    let event = makePasteEvent("\nworld")
    discard e.handleEvent(event)

    check e.activeBuffer.len >= 2
    check e.activeBuffer.inTransaction

  test "Insert mode - cursor advances by runes, not bytes, for multibyte paste":
    let e = createTestEditorForPaste("")
    e.state.mode = EditorMode.Insert
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)
    e.state.cursor = BufferPosition(line: 0, column: 0)

    let event = makePasteEvent("café")
    discard e.handleEvent(event)

    # 4 runes (c, a, f, é); cursor must land at rune column 4, not byte 5.
    check e.windowManager.windows[0].cursor.column == 4

  test "Insert mode - CRLF paste advances cursor by one line, no raw CR":
    let e = createTestEditorForPaste("")
    e.state.mode = EditorMode.Insert
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)
    e.state.cursor = BufferPosition(line: 0, column: 0)

    let event = makePasteEvent("ab\r\ncd")
    discard e.handleEvent(event)

    check e.windowManager.windows[0].cursor.line == 1
    check e.windowManager.windows[0].cursor.column == 2
    check '\r' notin e.activeBuffer.getLine(0)
    check '\r' notin e.activeBuffer.getLine(1)

  test "Non-Insert mode - paste shows unsupported message":
    let e = createTestEditorForPaste("hello")
    e.state.mode = EditorMode.Normal

    let event = makePasteEvent("text")
    discard e.handleEvent(event)

    check e.state.statusMessage == "Paste not supported in this mode"

  test "Insert mode - failed insertText rolls back and does not move cursor":
    # A readOnly buffer makes insertText fail after beginTransaction has
    # succeeded. Without the guard the cursor would still advance past valid
    # bytes and the transaction would commit as an empty entry.
    let e = createTestEditorForPaste("hello")
    e.state.mode = EditorMode.Insert
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 5)
    e.state.cursor = BufferPosition(line: 0, column: 5)
    e.activeBuffer.readOnly = true

    let event = makePasteEvent(" world")
    discard e.handleEvent(event)

    check $e.activeBuffer.getLine(0) == "hello"
    check e.windowManager.windows[0].cursor.column == 5
    check not e.activeBuffer.inTransaction
    check e.state.statusMessage.len > 0
    check e.state.statusMessage[0 ..< len("Paste failed")] == "Paste failed"

  test "Command overlay - bracketed paste inserts at cursor":
    let e = createTestEditorForPaste("hello")
    e.state.enterCommandOverlay()

    let event = makePasteEvent("wq")
    discard e.handleEvent(event)

    check e.state.input.commandText == ":wq"
    check e.state.input.commandCursor == 2

  test "Command overlay - bracketed paste keeps only first line":
    let e = createTestEditorForPaste("hello")
    e.state.enterCommandOverlay()

    let event = makePasteEvent("set ts=4\nset nu")
    discard e.handleEvent(event)

    check e.state.input.commandText == ":set ts=4"
    check e.state.input.commandCursor == 8

  test "Search overlay - bracketed paste appends to search text":
    let e = createTestEditorForPaste("hello world")
    e.state.enterSearchOverlay(SearchDirection.Forward)

    let event = makePasteEvent("wor")
    discard e.handleEvent(event)

    check e.state.input.search.text == "wor"

  test "Search overlay - bracketed paste keeps only first line":
    let e = createTestEditorForPaste("hello world")
    e.state.enterSearchOverlay(SearchDirection.Forward)

    let event = makePasteEvent("wor\nignored")
    discard e.handleEvent(event)

    check e.state.input.search.text == "wor"

suite "handleKeyCombo - Insert resumes after the Ctrl-o command":
  # Vim 9.2 resumes Insert once the command ends, whether it succeeded, failed
  # or was cancelled (restart_edit). Each case types `x` afterwards.
  let quitEvent = Event(kind: EventKind.Quit)

  proc createEditorForCtrlO(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  for (name, content, keys, typed) in [
    ("a motion", "abc def", @["w"], "abc xdef"),
    ("a counted motion", "a b c", @["2", "w"], "a b xc"),
    ("an edit", "abc", @["x"], "xbc"),
    ("an operator and a motion", "abc def", @["d", "w"], "xdef"),
    ("an operator and a text object", "abc def", @["d", "i", "w"], "x def"),
    ("a yank", "abc", @["y", "y"], "xabc"),
    ("a line delete", "abc\ndef", @["d", "d"], "xdef"),
    ("an unbound key", "abc", @["C-q"], "xabc"),
    ("a command that fails (unset mark)", "abc", @["'", "z"], "xabc"),
    ("an operator whose motion fails", "abc", @["d", "'", "z"], "xabc"),
    ("Escape", "abc", @["Esc"], "xabc"),
    ("Escape cancelling an operator", "abc", @["d", "Esc"], "xabc"),
    ("Escape cancelling a count", "abc", @["2", "Esc"], "xabc"),
    ("Escape cancelling a register", "abc", @["\"", "a", "Esc"], "xabc"),
    ("Escape cancelling f", "abc", @["f", "Esc"], "xabc"),
    ("a command line", "abc def", @[":", "n", "o", "h", "Enter"], "xabc def"),
    ("an empty command line", "abc def", @[":", "Enter"], "xabc def"),
    ("a cancelled command line", "abc def", @[":", "n", "o", "Esc"], "xabc def"),
    ("a search", "abc def", @["/", "d", "e", "f", "Enter"], "abc xdef"),
    ("a cancelled search", "abc def", @["/", "d", "Esc"], "xabc def"),
  ]:
    test name:
      let e = createEditorForCtrlO(content)

      e.press("i", "C-o")
      e.press(keys)

      check e.state.mode == EditorMode.Insert
      check e.state.insertResume == irNone
      check not e.state.hasOverlay
      check not e.state.pendingInput.isActive(e.keyRouter.registry)
      check e.activeBuffer.inTransaction

      e.press("x")
      check e.activeBuffer.getLine(0) == typed

  for (name, keys) in [
    ("a count", @["2"]),
    ("the first key of gg", @["g"]),
    ("an operator", @["d"]),
    ("an operator and i", @["d", "i"]),
    ("a register", @["\"", "a"]),
    ("q", @["q"]),
    ("f", @["f"]),
    ("Ctrl-w", @["C-w"]),
    ("a command line being typed", @[":", "n"]),
    ("a search being typed", @["/", "d"]),
  ]:
    test name & " keeps Insert waiting":
      let e = createEditorForCtrlO("abc def")

      e.press("i", "C-o")
      e.press(keys)

      check e.state.mode == EditorMode.Normal
      check e.state.insertResume != irNone
      check not e.activeBuffer.inTransaction

  test "a join resumes Insert":
    # J opens its own undo step, which the open Insert session used to refuse.
    let e = createEditorForCtrlO("abc\ndef")

    e.press("i", "C-o", "J")

    check e.activeBuffer.getLine(0) == "abc def"
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

  test "a backward search resumes Insert at the match":
    let e = createEditorForCtrlO("abc def")

    e.press("A", "C-o", "?", "d", "e", "f", "Enter")

    check e.state.mode == EditorMode.Insert
    e.press("x")
    check e.activeBuffer.getLine(0) == "abc xdef"

  test "a command that fails at the end of the line resumes Insert there":
    let e = createEditorForCtrlO("abc")

    e.press("A", "C-o", "'", "z")
    check e.state.statusMessage == "Mark not set: z"

    e.press("x")
    check e.activeBuffer.getLine(0) == "abcx"

  test "a command that fails in a macro stops the macro in Insert":
    # Vim drops the rest of the register at the error, so "foo" is not typed.
    let e = createEditorForCtrlO("abc")
    e.state.pendingInput.macroState.registers['a'] =
      @["i", "<C-o>", "'", "z", "f", "o", "o"]

    e.press("@", "a")

    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

    e.press("x")
    check e.activeBuffer.getLine(0) == "xabc"

  test "a macro that fails stays in Normal mode, as in Vim":
    # Vim 9.2 with @a = jx on one line: the error flushes the Insert queued
    # after the register with the rest of it, so `i<C-o>@a~` toggles a case.
    let e = createEditorForCtrlO("abcdef")
    e.state.pendingInput.macroState.registers['a'] = @["'", "z", "x"]

    e.press("i", "C-o", "@", "a")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone

    e.press("~")
    check e.activeBuffer.getLine(0) == "Abcdef"

  test "@: resumes Insert after the repeated command":
    let e = createEditorForCtrlO("abc")
    e.press(":", "n", "o", "h", "Enter")

    e.press("i", "C-o", "@", ":")

    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

  test "a held mapping key is not typed into the resumed Insert":
    # Escape reaches the router, which plays the held Space as a Normal key
    # instead of leaving it to be flushed into Insert.
    let e = createEditorForCtrlO("abc")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Space w", "g g").len ==
      0

    e.press("i", "C-o", "Space", "Esc")

    check not e.keyRouter.isHoldingKeys
    check e.state.mode == EditorMode.Insert

    e.press("x")
    check e.activeBuffer.getLine(0) == "xabc"

  test "a held mapping key runs first, then Escape leaves the resumed Insert":
    # Vim 9.2 with `nmap lw gg`: `li<C-o>l<Esc>` moves right, resumes Insert,
    # and the Escape ends it one column left.
    let e = createEditorForCtrlO("abcdef")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "l w", "g g").len ==
      0

    e.press("l", "i", "C-o", "l", "Esc")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone
    check not e.activeBuffer.inTransaction
    check e.cursor == BufferPosition(line: 0, column: 1)

    e.press("i", "Z")
    check e.activeBuffer.getLine(0) == "aZbcdef"

  test "Escape in a macro resumes Insert as when typed":
    # Vim 9.2 replays `i<C-o>d<Esc>Z<Esc>` as typed, so Z is inserted.
    let e = createEditorForCtrlO("abc")
    e.state.pendingInput.macroState.registers['a'] =
      @["i", "<C-o>", "d", "<Escape>", "Z", "<Escape>"]

    e.press("@", "a")

    check e.activeBuffer.getLine(0) == "Zabc"
    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone
    check not e.state.pendingInput.isActive(e.keyRouter.registry)

  test "Escape in a mapping resumes Insert as when typed":
    let e = createEditorForCtrlO("abc")
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Normal, "Q", "i C-o d Esc Z"
    ).len == 0

    e.press("Q")

    check e.activeBuffer.getLine(0) == "Zabc"
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone
    check not e.state.pendingInput.isActive(e.keyRouter.registry)

  test "the keys of a mapping after its first command are typed, as in Vim":
    # Vim 9.2 with `nmap Q xx`: `i<C-o>QZ` deletes one character and types x.
    let e = createEditorForCtrlO("abcdef")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Q", "x x").len == 0

    e.press("i", "C-o", "Q", "Z")

    check e.activeBuffer.getLine(0) == "xZbcdef"

  test "a mapping that ends in Ctrl-o leaves Insert waiting, as in Vim":
    # Vim 9.2 with `nmap Q ax<C-o>`: the x after `i<C-o>Q` deletes.
    let e = createEditorForCtrlO("abc")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Q", "a x C-o").len ==
      0

    e.press("i", "C-o", "Q")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume != irNone

    e.press("x", "Y")
    check e.activeBuffer.getLine(0) == "axYc"

  test "the keys of a mapping that starts in Visual mode stay commands, as in Vim":
    # Vim 9.2 with `xnoremap X dp`: `i<C-o>vlX` puts what d deleted.
    let e = createEditorForCtrlO("abcdef")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Visual, "X", "d p").len == 0

    e.press("i", "C-o", "v", "l", "X")

    check e.activeBuffer.getLine(0) == "cabdef"
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

  test "a mapping that starts in Visual mode and ends in Ctrl-o leaves Insert waiting, as in Vim":
    # Vim 9.2 with `xnoremap X c<C-o>`: the l after `i<C-o>vlX` moves.
    let e = createEditorForCtrlO("abcdef")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Visual, "X", "c C-o").len ==
      0

    e.press("i", "C-o", "v", "l", "X")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume != irNone

    e.press("l", "Z")
    check e.activeBuffer.getLine(0) == "cZdef"

  test "a mapping that starts in Visual mode and leaves the Insert it enters ends the wait, as in Vim":
    # Vim 9.2 with `xnoremap X cfoo<Esc>`: the x after `li<C-o>vlX` deletes.
    let e = createEditorForCtrlO("abcdef")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Visual, "X", "c f o o Esc").len ==
      0

    e.press("l", "i", "C-o", "v", "l", "X")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone

    e.press("x")
    check e.activeBuffer.getLine(0) == "afodef"

  test "a command line a mapping ends on timeout resumes Insert":
    let e = createEditorForCtrlO("abc")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Command, "Q", "Enter").len ==
      0
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Command, "Q Q", "Esc").len ==
      0

    e.press("i", "C-o", ":", "n", "o", "h", "Q")
    check e.keyRouter.isHoldingKeys

    check e.handleKeyMappingTimeout()

    check not e.state.hasOverlay
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

  test "a macro runs whole before Insert resumes, as in Vim":
    # Vim 9.2 with @q = xx: `i<C-o>@qZ` deletes two characters.
    let e = createEditorForCtrlO("abcdef")
    e.state.pendingInput.macroState.registers['q'] = @["x", "x"]

    e.press("i", "C-o", "@", "q", "Z")

    check e.activeBuffer.getLine(0) == "Zcdef"

  test "a macro that enters and leaves Insert still resumes it, as in Vim":
    # Vim 9.2 with @q = iX<Esc>: `i<C-o>@qZ` gives ZXabc.
    let e = createEditorForCtrlO("abc")
    e.state.pendingInput.macroState.registers['q'] = @["i", "X", "<Escape>"]

    e.press("i", "C-o", "@", "q", "Z")

    check e.activeBuffer.getLine(0) == "ZXabc"
    check e.state.mode == EditorMode.Insert

  test "a macro that ends in Insert ends the wait, so Escape later leaves Insert":
    # The router still holds the macro's last key, a mapping prefix, when the
    # macro ends, which once kept the wait alive into Insert.
    let e = createEditorForCtrlO("abc")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Insert, "j k", "Esc").len ==
      0
    e.state.pendingInput.macroState.registers['q'] = @["i", "f", "o", "o", "j"]

    e.press("i", "C-o", "@", "q")
    check e.keyRouter.isHoldingKeys
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

    e.press("k")
    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone
    check not e.activeBuffer.inTransaction

  test "Ctrl-o in a macro resumes Insert within it, as in Vim":
    # Vim 9.2 with @q = ax<C-o>xY: Y is typed once the x has deleted.
    let e = createEditorForCtrlO("abc")
    e.state.pendingInput.macroState.registers['q'] = @["a", "x", "<C-o>", "x", "Y"]

    e.press("@", "q")

    check e.activeBuffer.getLine(0) == "axYc"
    check e.state.mode == EditorMode.Insert

  test "a command that shows another buffer resumes Insert there, as in Vim":
    let e = createEditorForCtrlO("abc")
    let first = e.activeBuffer
    let other = newTextBuffer("xyz")
    e.addBuffer(first)
    e.addBuffer(other)
    e.activeWindow.bufferIds.add(other.id)

    e.press("i", "C-o", ":", "b", "n", "Enter")

    check e.activeBuffer == other
    check e.state.mode == EditorMode.Insert
    check not first.inTransaction
    check other.inTransaction

  test "a paste after Ctrl-o resumes Insert":
    let e = createEditorForCtrlO("abc")

    e.press("i", "C-o")
    check e.handlePaste("XY")

    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

  test "Ctrl-o leaves Insert without the wait if the session cannot commit":
    let e = createEditorForCtrlO("abc")

    e.press("i")
    # The commit fails on a transaction flag left without its record.
    e.activeBuffer.currentTransaction = none(BufferTransaction)
    e.press("C-o")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone
    check e.state.statusMessage.contains("Failed to commit transaction")

  test "Ctrl-o that cannot commit past the end of the line leaves the cursor as Escape does":
    let e = createEditorForCtrlO("abc")

    e.press("A")
    e.activeBuffer.currentTransaction = none(BufferTransaction)
    e.press("C-o")

    check e.state.insertResume == irNone
    check e.cursor.column == 2

  test "a command that sends an LSP request is done once it returns":
    # What `gd` leaves behind while its response is due; no server runs here.
    # The keys after it are typed, so none runs as a Normal command.
    let e = createEditorForCtrlO("abc def")

    e.press("i", "C-o")
    e.state.lspCache.pending[lrfDefinition] =
      LspRequestContext(feature: lrfDefinition, validModes: LocationValidModes)
    e.press("w", "x")

    check e.activeBuffer.getLine(0) == "abc xdef"
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

  test "keys after Ctrl-o gL go to the CodeLens picker until it closes":
    # The picker answers the command, so Insert resumes once it is gone.
    let e = createEditorForCtrlO("abc")
    let path = getTempDir() / "ctrl_o_codelens.unknownlang"
    e.activeBuffer.filePath = some(path)
    e.lsp.enabled = true
    e.state.lspCache.codeLensCache = CodeLensCache(
      isValid: true,
      filePath: path,
      bufferId: e.activeBuffer.id,
      itemsByLine: {
        0: @[
          CodeLensItem(line: 0, title: "run", command: "run"),
          CodeLensItem(line: 0, title: "test", command: "test"),
        ]
      }.toTable,
    )

    e.press("i", "C-o", "g", "L")
    check e.state.lspCache.codeLensPicker.isActive
    check e.state.mode == EditorMode.Normal

    e.press("j")
    check e.state.lspCache.codeLensPicker.selectedIndex == 1
    check e.activeBuffer.getLine(0) == "abc"

    e.press("Esc")
    check not e.state.lspCache.codeLensPicker.isActive
    check e.state.mode == EditorMode.Insert
    e.press("x")
    check e.activeBuffer.getLine(0) == "xabc"

  test "the command's message stays over the line's syntax error, as in Vim":
    let e = createEditorForCtrlO("abc")
    let path = getTempDir() / "ctrl_o_syntax_message.nim"
    e.activeBuffer.filePath = some(path)
    e.activeBuffer.setDiagnostics(
      dsrcSyntaxCheck,
      @[BufferDiagnostic(startLine: 0, endLine: 0, severity: bdsError, message: "bad")],
    )

    e.press("i", "C-o", "'", "z")

    check e.state.mode == EditorMode.Insert
    check e.state.statusMessage.contains("Mark not set")

  test "a focus change, a pointer move or no text is not the command Ctrl-o waits for":
    let e = createEditorForCtrlO("abc")

    e.press("i", "C-o")
    check e.handleEvent(Event(kind: EventKind.FocusIn))
    discard e.handlePointerInput(initPointerInput(0, 1, action = paMove))
    discard e.handlePointerInput(initPointerInput(0, 1, action = paRelease))
    check e.handleTextInput("")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume != irNone

    e.press("x")
    check e.activeBuffer.getLine(0) == "bc"
    check e.state.mode == EditorMode.Insert

  for (name, content, keys, typed) in [
    ("x deletes the last character", "abc", @["x"], "abZ"),
    ("h moves off the last character", "abcdef", @["h"], "abcdZef"),
    ("a command that keeps the cursor leaves it there", "abc", @["z", "z"], "abcZ"),
    ("j keeps the column", "abc\nxyzw", @["j"], "xyzZw"),
    ("j onto a shorter line ends past its end", "abcdef\nxy", @["j"], "xyZ"),
  ]:
    test "past the end of the line, " & name & ", as in Vim":
      # Vim 9.2 puts the cursor on the last character at Ctrl-o, and back past
      # it if Insert resumes there.
      let e = createEditorForCtrlO(content)

      e.press("A", "C-o")
      e.press(keys)
      e.press("Z")

      check e.activeBuffer.getLine(e.cursor.line) == typed

  for (name, content, keys, typed) in [
    (
      "a shorter line ends past its end",
      "abcdef\nxy",
      @["A", "Left", "Left", "C-o", "j"],
      "xyZ",
    ),
    (
      "a vertical move before Ctrl-o keeps its column",
      "abcdefghij\nab\nabcdefghij",
      @["8", "l", "i", "Down", "C-o", "j"],
      "abcdefghZij",
    ),
    (
      "typing after a vertical move takes the column again",
      "abcdefghij\nabcdefghij\nabcdefghij",
      @["8", "l", "i", "Down", "X", "C-o", "j"],
      "abcdefghiZj",
    ),
    (
      "typing at the end of a line takes the column there",
      "abcdefghij\nab\nabcdefghij",
      @["8", "l", "i", "Down", "X", "C-o", "j"],
      "abcZdefghij",
    ),
    (
      "Insert takes the column again on entry",
      "abcdefgh\nabc",
      @["7", "l", "j", "i", "C-o", "z", "z"],
      "abZc",
    ),
    (
      "a search takes the column again",
      "abcdefgh\nxyz",
      @["A", "C-o", "/", "z", "Enter"],
      "xyZz",
    ),
    (
      "an edit takes the column again",
      "abcdefgh\nabcdefghijk",
      @["A", "C-o", "x", "Down"],
      "abcdefgZhijk",
    ),
  ]:
    test "the column a vertical move wants: " & name & ", as in Vim":
      # Vim 9.2 keeps the wanted column (curswant) only across vertical moves,
      # and resumes Insert past the end of the line if it is right of the cursor.
      let e = createEditorForCtrlO(content)

      e.press(keys)
      e.press("Z")

      check e.activeBuffer.getLine(e.cursor.line) == typed

  test "Insert resumed past the end of the line starts its session there":
    let e = createEditorForCtrlO("abc")

    e.press("A", "C-o", "z", "z")

    check e.cursor == BufferPosition(line: 0, column: 3)
    e.press("x")
    check e.activeBuffer.getLine(0) == "abcx"

  test "the cursor stays on a character when Insert cannot resume":
    let e = createEditorForCtrlO("abc")
    e.press("A", "C-o")
    e.activeBuffer.readOnly = true

    e.press("Esc")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone
    check e.cursor == BufferPosition(line: 0, column: 2)

  test "a read-only buffer keeps the message of the command, as in Vim":
    # Vim 9.2 resumes Insert in a 'nomodifiable' buffer without a word; E21
    # comes only with the first character typed.
    let e = createEditorForCtrlO("abc")
    e.press("i", "C-o")
    e.activeBuffer.readOnly = true

    e.press("'", "z")

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone
    check e.state.statusMessage.contains("Mark not set")

  test "a snippet ends at Ctrl-o, as the Insert session does":
    let e = createEditorForCtrlO("abc")
    e.press("i")
    e.state.snippetSession = SnippetSession(
      active: true,
      stops: @[
        SnippetStop(num: 1, pos: BufferPosition(line: 0, column: 1)),
        SnippetStop(num: 0, pos: BufferPosition(line: 0, column: 3)),
      ],
    )

    e.press("C-o", "o")

    check e.state.mode == EditorMode.Insert
    check not e.state.snippetSession.active

  for (name, keys, mode) in [
    ("i", @["i"], EditorMode.Insert),
    ("a", @["a"], EditorMode.Insert),
    ("o", @["o"], EditorMode.Insert),
    ("R", @["R"], EditorMode.Replace),
  ]:
    test "a command that enters " & $mode & " (" & name & ") opens its own session":
      let e = createEditorForCtrlO("abc")

      e.press("i", "C-o")
      e.press(keys)

      check e.state.mode == mode
      check e.state.insertResume == irNone
      check e.activeBuffer.inTransaction

  test "Visual mode entered after Ctrl-o resumes Insert when it ends, as in Vim":
    let e = createEditorForCtrlO("abc def")

    e.press("i", "C-o", "v")
    check e.state.mode == EditorMode.Visual
    check e.state.insertResume != irNone

    e.press("e", "d")
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

    e.press("x")
    check e.activeBuffer.getLine(0) == "x def"

  test "Escape in Visual mode entered after Ctrl-o resumes Insert":
    let e = createEditorForCtrlO("abc")

    e.press("i", "C-o", "V", "Esc")

    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

  test "Insert resumes with the cursor line unfolded":
    let e = createEditorForCtrlO("aaaa\nbbbb\ncccc\ndddd")
    e.press("i", "C-o")
    discard e.activeBuffer.foldState.addFold(1, 2, collapsed = true)

    e.press("j")

    check e.state.mode == EditorMode.Insert
    check e.cursor.line == 1
    check not e.activeBuffer.foldState.folds[0].collapsed

  test "Ctrl-C in a command line resumes Insert":
    let e = createEditorForCtrlO("abc")
    e.press("i", "C-o", ":", "w")

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone
    check not e.state.isCommandOverlay

  test "Ctrl-C in a search resumes Insert":
    let e = createEditorForCtrlO("abc")
    e.press("i", "C-o", "/", "b")

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone
    check not e.state.isSearchOverlay

  test "Ctrl-C stays in Normal mode, as in Vim":
    let e = createEditorForCtrlO("abc")
    e.press("A", "C-o")

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone
    check not e.activeBuffer.inTransaction
    check e.cursor == BufferPosition(line: 0, column: 2)
    check "qa" notin e.state.statusMessage

  test "Ctrl-C cancels an operator, as in Vim":
    let e = createEditorForCtrlO("abc def")
    e.press("i", "C-o", "d")

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Normal
    check not e.state.pendingInput.isActive(e.keyRouter.registry)

    e.press("w")
    check e.activeBuffer.getLine(0) == "abc def"

  test "Ctrl-C in Visual mode stays in Normal mode, as in Vim":
    let e = createEditorForCtrlO("abc")
    e.press("i", "C-o", "v")

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Normal
    check e.state.insertResume == irNone

suite "handleKeyCombo - Ctrl-o ends the Insert session":
  proc createEditorForCtrlO(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  test "it ends the undo step, as in Vim":
    let e = createEditorForCtrlO("abc")

    e.press("i", "f", "o", "o", "C-o", "l", "b", "a", "r", "Esc")
    check e.activeBuffer.getLine(0) == "fooabarbc"

    e.press("u")
    check e.activeBuffer.getLine(0) == "fooabc"
    e.press("u")
    check e.activeBuffer.getLine(0) == "abc"

  test "undo after it takes back the text typed before it":
    let e = createEditorForCtrlO("abc")

    e.press("i", "f", "o", "o", "C-o", "u")

    check e.activeBuffer.getLine(0) == "abc"
    check e.state.mode == EditorMode.Insert

  test "dot repeats only what was typed after the command, as in Vim":
    let e = createEditorForCtrlO("abc")

    e.press("i", "f", "o", "o", "C-o", "l", "b", "a", "r", "Esc", "0", ".")

    check e.activeBuffer.getLine(0) == "barfooabarbc"

  test "a count is dropped, as in Vim":
    let e = createEditorForCtrlO("abc")

    e.press("3", "i", "x", "C-o", "Esc", "Esc")

    check e.activeBuffer.getLine(0) == "xabc"

  test "an untouched auto-indent is deleted, as Vim's 'autoindent' does":
    let e = createEditorForCtrlO("  abc")

    e.press("o", "C-o")
    check e.activeBuffer.getLine(1) == ""

    e.press("Esc", "x")
    check e.activeBuffer.getLine(1) == "x"

suite "handleInterrupt - Normal":
  let quitEvent = Event(kind: EventKind.Quit)

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  test "Ctrl-C tells how to quit":
    let e = createTestEditorWithBuffer("hello")

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Normal
    check "qa" in e.state.statusMessage

  test "Ctrl-C cancels an operator without telling how to quit, as in Vim":
    let e = createTestEditorWithBuffer("hello world")
    e.motionController.bindToWindow(e.activeWindow)
    e.state.registers = initRegisters()
    e.press("d")

    discard e.handleEvent(quitEvent)

    check not e.state.pendingInput.isActive(e.keyRouter.registry)
    check "qa" notin e.state.statusMessage

    e.press("w")
    check e.activeBuffer.getLine(0) == "hello world"

suite "handleKeyCombo - Escape in Normal mode":
  proc createEditorForEscape(content: string): Editor =
    result = createTestEditorWithBuffer(content)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.registers = initRegisters()

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  test "Escape cancels an operator before a mapping of it, as in Vim":
    # Vim 9.2 with `nnoremap <Esc> ...`: `d<Esc>x` deletes one character.
    let e = createEditorForEscape("abc def")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Esc", "l l").len ==
      0

    e.press("d", "Esc", "x")

    check e.activeBuffer.getLine(0) == "bc def"

  test "R carries on a transaction left open, as i does":
    let e = createEditorForEscape("abc")
    check e.activeBuffer.beginTransaction("left open").isOk

    e.press("R")

    check e.state.mode == EditorMode.Replace

  test "Escape plays a held mapping key at once":
    # Vim 9.2 with `nmap lw gg`: `l<Esc>` moves right without waiting.
    let e = createEditorForEscape("abcdef")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "l w", "g g").len ==
      0

    e.press("l", "Esc")

    check not e.keyRouter.isHoldingKeys
    check e.cursor == BufferPosition(line: 0, column: 1)

  test "Escape in a macro cancels an operator as when typed":
    # Vim 9.2 replays `ld<Esc>x` as typed, so x deletes one character.
    let e = createEditorForEscape("abcdef")
    e.state.pendingInput.macroState.registers['a'] = @["l", "d", "<Escape>", "x"]

    e.press("@", "a")

    check e.activeBuffer.getLine(0) == "acdef"
    check not e.state.pendingInput.isActive(e.keyRouter.registry)

  test "two Escapes in a row hide search highlighting":
    let e = createEditorForEscape("abc")

    e.press("Esc")
    check not e.state.input.search.hlsearchTempDisabled

    e.press("Esc")
    check e.state.input.search.hlsearchTempDisabled

  test "a mapping that starts with Escape fires with nothing to cancel":
    let e = createEditorForEscape("abc")
    check e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "Esc Esc", "d l").len ==
      0

    e.press("Esc", "Esc")

    check e.activeBuffer.getLine(0) == "bc"

  test "an Escape that cancels a command does not count toward two":
    let e = createEditorForEscape("abc")

    e.press("d", "Esc", "Esc")
    check not e.state.input.search.hlsearchTempDisabled

    e.press("Esc")
    check e.state.input.search.hlsearchTempDisabled

suite "handleKeyCombo - frontend-neutral input":
  proc charKey(c: string): KeyCombo =
    KeyCombo(isSpecial: false, char: c, modifiers: {})

  test "Normal mode command enters Insert mode":
    let e = createTestEditorWithBuffer("hello")

    discard e.handleKeyCombo(charKey("i"))

    check e.state.mode == EditorMode.Insert

  test "Command overlay accepts character input":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()

    discard e.handleKeyCombo(charKey("w"))

    check e.state.isCommandOverlay
    check e.state.input.commandText == ":w"
    check e.state.input.commandCursor == 1

  test "Search overlay accepts character input":
    let e = createTestEditorWithBuffer("hello world")
    e.state.enterSearchOverlay(Forward)

    discard e.handleKeyCombo(charKey("w"))

    check e.state.isSearchOverlay
    check e.state.input.search.text == "w"
    check e.state.input.search.cursor == 1

  test "committed GUI text can contain composed Unicode":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Insert

    discard e.handleTextInput("é🙂")

    check $e.activeBuffer.getLine(0) == "é🙂"
    check e.cursor.column == 2

  test "multi-rune text advances the command cursor by runes":
    let e = createTestEditorWithBuffer("")
    e.state.enterCommandOverlay()

    discard e.handleTextInput("λx")

    check e.state.input.commandText == ":λx"
    check e.state.input.commandCursor == 2

suite "Insert mode Ctrl-A / Ctrl-@":
  proc charKey(c: string): KeyCombo =
    KeyCombo(isSpecial: false, char: c, modifiers: {})

  let
    escapeKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    ctrlAKey = KeyCombo(isSpecial: false, char: "a", modifiers: {key_bindings.kmCtrl})
    ctrlAtKey = KeyCombo(isSpecial: false, char: " ", modifiers: {key_bindings.kmCtrl})

  proc typeText(e: Editor, text: string) =
    for c in text:
      check e.handleKeyCombo(charKey($c))

  test "Ctrl-A re-inserts the last inserted text at the cursor":
    let e = createTestEditorWithBuffer("")
    discard e.handleKeyCombo(charKey("i"))
    e.typeText("abc")
    discard e.handleKeyCombo(escapeKey)
    # Normal mode parks on the last inserted character, so `i` re-enters
    # before it and Ctrl-A duplicates there.
    discard e.handleKeyCombo(charKey("i"))

    check e.handleKeyCombo(ctrlAKey)

    check e.state.mode == EditorMode.Insert
    check $e.activeBuffer.getLine(0) == "ababcc"
    check e.cursor == BufferPosition(line: 0, column: 5)

  test "Ctrl-@ inserts the last inserted text and leaves Insert mode":
    let e = createTestEditorWithBuffer("")
    discard e.handleKeyCombo(charKey("i"))
    e.typeText("abc")
    discard e.handleKeyCombo(escapeKey)
    discard e.handleKeyCombo(charKey("i"))

    check e.handleKeyCombo(ctrlAtKey)

    check e.state.mode == EditorMode.Normal
    check $e.activeBuffer.getLine(0) == "ababcc"
    check not e.activeBuffer.inTransaction

  test "Ctrl-@ after `o` records the re-inserted text for `.`":
    let e = createTestEditorWithBuffer("abc")
    discard e.handleKeyCombo(charKey("i"))
    e.typeText("xyz")
    discard e.handleKeyCombo(escapeKey)
    discard e.handleKeyCombo(charKey("o"))

    check e.handleKeyCombo(ctrlAtKey)

    check e.state.mode == EditorMode.Normal
    check $e.activeBuffer.getLine(1) == "xyz"
    check e.handleKeyCombo(charKey("."))
    check e.activeBuffer.len == 3
    check $e.activeBuffer.getLine(2) == "xyz"

suite "Visual-block insert - what the other lines get":
  # Vim copies what the first line gained, from the block column, when the
  # insert ends on the first line. Expected lines are measured in Vim.
  proc keysOf(spec: string): seq[KeyCombo] =
    const named = {
      "<C-v>": KeyCombo(isSpecial: false, char: "v", modifiers: {key_bindings.kmCtrl}),
      "<C-o>": KeyCombo(isSpecial: false, char: "o", modifiers: {key_bindings.kmCtrl}),
      "<Esc>": KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {}),
      "<CR>": KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {}),
      "<BS>": KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0, modifiers: {}),
      "<Del>": KeyCombo(isSpecial: true, special: skDelete, fnNum: 0, modifiers: {}),
      "<Left>": KeyCombo(isSpecial: true, special: skLeft, fnNum: 0, modifiers: {}),
      "<Right>": KeyCombo(isSpecial: true, special: skRight, fnNum: 0, modifiers: {}),
      "<Up>": KeyCombo(isSpecial: true, special: skUp, fnNum: 0, modifiers: {}),
      "<Down>": KeyCombo(isSpecial: true, special: skDown, fnNum: 0, modifiers: {}),
    }
    var i = 0
    while i < spec.len:
      var matched = false
      for (name, key) in named:
        if spec.continuesWith(name, i):
          result.add key
          i += name.len
          matched = true
          break
      if not matched:
        result.add KeyCombo(isSpecial: false, char: $spec[i], modifiers: {})
        inc i

  proc editorAfter(spec: string): Editor =
    result = createTestEditorWithBuffer("abcdef\nghijkl\nmnopqr")
    result.syncActiveWindow()
    result.activeWindow.cursor = BufferPosition(line: 0, column: 1)
    for key in keysOf(spec):
      discard result.handleKeyCombo(key)

  proc run(spec: string): seq[string] =
    let e = editorAfter(spec)
    for i in 0 ..< e.activeBuffer.len:
      result.add $e.activeBuffer.getLine(i)

  test "typing only":
    check run("<C-v>jjIab<Esc>") == @["aabbcdef", "gabhijkl", "mabnopqr"]
    check run("<C-v>jjAab<Esc>") == @["ababcdef", "ghabijkl", "mnabopqr"]
    check run("<C-v>jjlcab<Esc>") == @["aabdef", "gabjkl", "mabpqr"]

  test "moving along the first line copies what it gained":
    check run("<C-v>jjIab<Right><Right>Z<Esc>") ==
      @["aabbcZdef", "gabbhijkl", "mabbnopqr"]
    check run("<C-v>jjIab<Left>Z<Esc>") == @["aaZbbcdef", "gaZbhijkl", "maZbnopqr"]
    check run("<C-v>jjIab<Down><Up>Z<Esc>") == @["aabZbcdef", "gabZhijkl", "mabZnopqr"]
    check run("<C-v>jjlcab<Right>Z<Esc>") == @["aabdZef", "gabdjkl", "mabdpqr"]

  test "ending off the first line copies nothing":
    check run("<C-v>jjIab<Down>Z<Esc>") == @["aabbcdef", "ghiZjkl", "mnopqr"]
    check run("<C-v>jjIab<CR>Z<Esc>") == @["aab", "Zbcdef", "ghijkl", "mnopqr"]

  test "a first line that did not grow copies nothing":
    check run("<C-v>jjIab<BS><BS><BS><Esc>") == @["bcdef", "ghijkl", "mnopqr"]
    check run("<C-v>jjI<Del>Z<Esc>") == @["aZcdef", "ghijkl", "mnopqr"]

  test "Ctrl-O ends the block insert":
    # Vim also moves the cursor to the block start there, so its first line
    # reads "aaZbbcdef"; only the copies are compared.
    check run("<C-v>jjIab<C-o>lZ<Esc>")[1 .. 2] == @["gabhijkl", "mabnopqr"]

  test "Ctrl-O to the command line in forced Insert mode ends it too":
    let e = editorAfter("<C-v>jjIab")
    e.config.standard.forceInsertMode = true
    check e.handleKeyCombo(keysOf("<C-o>")[0])
    check e.state.isCommandOverlay
    check e.state.editState.visualBlockInsertContext.isNone
    check $e.activeBuffer.getLine(1) == "gabhijkl"
    check $e.activeBuffer.getLine(2) == "mabnopqr"

  test "`.` repeats what was typed, not the copies":
    let e = editorAfter("<C-v>jjIab<Esc>")
    check e.state.editState.lastEditCommand.get.kind == lecInsert
    check e.state.editState.insertRecord.entry.kind == ieInsert
    check e.state.editState.insertRecord.typed.len == 2

suite "forced Insert mode":
  let
    escapeKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})
    enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    ctrlCKey = KeyCombo(isSpecial: false, char: "c", modifiers: {key_bindings.kmCtrl})
    ctrlOKey = KeyCombo(isSpecial: false, char: "o", modifiers: {key_bindings.kmCtrl})
    ctrlRKey = KeyCombo(isSpecial: false, char: "r", modifiers: {key_bindings.kmCtrl})

  proc charKey(c: string): KeyCombo =
    KeyCombo(isSpecial: false, char: c, modifiers: {})

  proc typeKeys(e: Editor, keys: string) =
    for key in keys:
      check e.handleKeyCombo(charKey($key))

  proc createForcedInsertEditor(): Editor =
    let config = newEditorConfig()
    config.standard.forceInsertMode = true
    newEditor(config)

  test "editor starts with a valid Insert session":
    let e = createForcedInsertEditor()

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.inTransaction

  test "committed GUI text inserts without a Normal-mode command":
    let e = createForcedInsertEditor()

    check e.handleTextInput("hello")

    check $e.activeBuffer.getLine(0) == "hello"
    check e.cursor == BufferPosition(line: 0, column: 5)
    check e.state.mode == EditorMode.Insert

  test "Escape commits the edit boundary and remains in Insert mode":
    let e = createForcedInsertEditor()
    check e.handleTextInput("a")

    check e.handleKeyCombo(escapeKey)

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.inTransaction
    check e.activeBuffer.undoStack.len == 1
    check e.activeBuffer.currentTransaction.get.changes.len == 0

  test "Ctrl-U after the Ctrl-O command line stops where typing resumed":
    # As Vim's `Aabc<C-o>:<Esc>d<C-u>`.
    let e = createForcedInsertEditor()
    e.typeKeys("abc")
    check e.handleKeyCombo(ctrlOKey)
    check e.state.isCommandOverlay
    check e.handleKeyCombo(escapeKey)
    check e.state.mode == EditorMode.Insert
    e.typeKeys("d")
    check e.handleKeyCombo(
      KeyCombo(isSpecial: false, char: "u", modifiers: {key_bindings.kmCtrl})
    )
    check $e.activeBuffer.getLine(0) == "abc"

  test "Ctrl-C commits the edit boundary and remains in Insert mode":
    let e = createForcedInsertEditor()
    check e.handleTextInput("a")

    check e.handleKeyCombo(ctrlCKey)

    check e.state.mode == EditorMode.Insert
    check e.cursor == BufferPosition(line: 0, column: 1)
    check e.activeBuffer.inTransaction
    check e.activeBuffer.undoStack.len == 1
    check e.activeBuffer.currentTransaction.get.changes.len == 0

  test "an Insert Ctrl-C remap runs without leaving Insert mode":
    let e = createTestEditorWithBuffer("")
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Insert, "C-c", "insert-newline"
    ).len == 0
    e.typeKeys("i")

    check e.handleKeyCombo(ctrlCKey)

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.len == 2
    check e.cursor == BufferPosition(line: 1, column: 0)
    check e.activeBuffer.inTransaction

  test "Ctrl-O opens the command line without exposing Normal mode":
    let e = createForcedInsertEditor()

    check e.handleKeyCombo(ctrlOKey)
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone
    check e.state.isCommandOverlay
    check e.state.input.commandText == ":"
    check e.activeBuffer.inTransaction

    check e.handleTextInput("w")
    check e.state.input.commandText == ":w"

  test "Ctrl-O undo and redo commit the current typing group":
    let e = createForcedInsertEditor()
    check e.handleTextInput("abc")
    check e.handleKeyCombo(escapeKey)
    check e.handleTextInput("de")

    check e.handleKeyCombo(ctrlOKey)
    check e.handleTextInput("undo")
    check e.handleKeyCombo(enterKey)

    check $e.activeBuffer.getLine(0) == "abc"
    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.inTransaction

    check e.handleKeyCombo(ctrlOKey)
    check e.handleTextInput("redo")
    check e.handleKeyCombo(enterKey)

    check $e.activeBuffer.getLine(0) == "abcde"
    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.inTransaction

  test "ordinary Ctrl-O u commits before undo and resumes Insert mode":
    let e = createTestEditorWithBuffer("")
    e.typeKeys("i")
    check e.handleTextInput("abc")

    check e.handleKeyCombo(ctrlOKey)
    check e.handleKeyCombo(charKey("u"))

    check $e.activeBuffer.getLine(0) == ""
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone
    check e.activeBuffer.inTransaction

    check e.handleKeyCombo(ctrlOKey)
    check e.handleKeyCombo(ctrlRKey)

    check $e.activeBuffer.getLine(0) == "abc"
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone
    check e.activeBuffer.inTransaction

  test "Ctrl-C does not replay a counted Insert command":
    let e = createTestEditorWithBuffer("")

    e.typeKeys("3ix")
    check e.handleKeyCombo(ctrlCKey)

    check e.state.mode == EditorMode.Normal
    check $e.activeBuffer.getLine(0) == "x"

  test "Ctrl-C does not replicate a visual block insertion":
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.mode = EditorMode.Insert
    check e.activeBuffer.beginTransaction("visual block insert").isOk
    e.state.editState.visualBlockInsertContext = some(
      VisualBlockInsertContext(
        kind: vbiInsert, startLine: 0, endLine: 2, insertColumn: 0
      )
    )

    check e.handleTextInput("X")
    check e.handleKeyCombo(ctrlCKey)

    check $e.activeBuffer.getLine(0) == "Xaaa"
    check $e.activeBuffer.getLine(1) == "bbb"
    check $e.activeBuffer.getLine(2) == "ccc"
    check e.state.editState.visualBlockInsertContext.isNone

  test "Ctrl-C after substitute does not corrupt the next dot repeat":
    let e = createTestEditorWithBuffer("old")

    e.typeKeys("ccN")
    check e.handleKeyCombo(ctrlCKey)
    e.typeKeys("iQ")
    check e.handleKeyCombo(escapeKey)
    e.typeKeys(".")

    check $e.activeBuffer.getLine(0) == "QQN"

  test "Ctrl-C after Replace clears the prior substitute context":
    let e = createTestEditorWithBuffer("old")

    e.typeKeys("ccN")
    check e.handleKeyCombo(escapeKey)
    e.typeKeys("Ry")
    check e.handleKeyCombo(ctrlCKey)
    e.typeKeys("iQ")
    check e.handleKeyCombo(escapeKey)
    e.typeKeys(".")

    check $e.activeBuffer.getLine(0) == "QQy"

  test "marking the first -R buffer leaves it in Normal mode":
    let e = createForcedInsertEditor()
    # main applies -R after loading the first path into the initial buffer.
    e.activeBuffer.readOnly = true

    e.enforceModePolicy()

    check e.state.mode == EditorMode.Normal
    check not e.activeBuffer.inTransaction

  test "policy restores a directly assigned Normal mode":
    let e = createForcedInsertEditor()

    e.setMode(EditorMode.Normal)
    e.enforceModePolicy()

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.inTransaction

suite "Macro recording - Command / Search overlay keys":
  # Regression: overlay dispatch used to bypass macro recording, so `qa:s/foo/bar/<CR>q`
  # would capture only ":" and lose the rest of the command line (same for `/pattern<CR>`).
  proc createEditorForOverlayRecord(content: string): Editor =
    let config = newEditorConfig()
    result = newEditor(config)
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.viewportManager.viewport = result.viewport
    result.state.mode = EditorMode.Normal

  proc startRecording(e: Editor, register: char) =
    e.state.pendingInput.macroState.recording = some(MacroRecording(register: register))

  test "Command overlay: keys after ':' are recorded":
    let e = createEditorForOverlayRecord("hello foo bar")
    e.startRecording('a')
    e.state.enterCommandOverlay()

    for ch in "s/foo/bar/":
      discard e.handleEvent(makeCharEvent($ch))
    discard e.handleEvent(makeEnterEvent())

    check e.state.pendingInput.macroState.recording.get.keys ==
      @["s", "/", "f", "o", "o", "/", "b", "a", "r", "/", "<Enter>"]

  test "Search overlay: pattern and Enter recorded":
    let e = createEditorForOverlayRecord("hello world")
    e.startRecording('a')
    e.state.enterSearchOverlay(SearchDirection.Forward)

    for ch in "wor":
      discard e.handleEvent(makeCharEvent($ch))
    discard e.handleEvent(makeEnterEvent())

    check e.state.pendingInput.macroState.recording.get.keys ==
      @["w", "o", "r", "<Enter>"]

  test "Command overlay Escape recorded so playback replays cancel":
    let e = createEditorForOverlayRecord("hello")
    e.startRecording('a')
    e.state.enterCommandOverlay()

    discard e.handleEvent(makeCharEvent("a"))
    discard e.handleEvent(makeCharEvent("b"))
    discard
      e.handleEvent(Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Escape)))

    check e.state.pendingInput.macroState.recording.get.keys == @["a", "b", "<Escape>"]
    check not e.state.isCommandOverlay

  test "q typed into the command line is recorded":
    let e = createEditorForOverlayRecord("hello")
    e.startRecording('a')
    e.state.enterCommandOverlay()

    discard e.handleEvent(makeCharEvent("q"))

    check e.state.pendingInput.macroState.isRecording
    check e.state.pendingInput.macroState.recording.get.keys == @["q"]

suite "Macro playback - overlay-aware routing":
  # Regression: nested key replay dispatched by state.mode, so overlay-mode keys
  # were mis-interpreted by the base handler. runNestedKeyCombo now consults
  # `frontLayerHook` (wired from handler.nim) to route via the overlay handler.
  proc createEditorForOverlayPlayback(content: string): Editor =
    let config = newEditorConfig()
    result = newEditor(config)
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.viewportManager.viewport = result.viewport
    result.state.mode = EditorMode.Normal

  test "Character keys in Command overlay build commandText, not buffer edits":
    let e = createEditorForOverlayPlayback("hello")
    e.state.enterCommandOverlay()

    let sKey = KeyCombo(isSpecial: false, char: "s", modifiers: {})
    let slashKey = KeyCombo(isSpecial: false, char: "/", modifiers: {})
    let fKey = KeyCombo(isSpecial: false, char: "f", modifiers: {})

    discard e.handlerManager.runKeyCombo(e, sKey)
    discard e.handlerManager.runKeyCombo(e, slashKey)
    discard e.handlerManager.runKeyCombo(e, fKey)

    check e.state.input.commandText == ":s/f"
    check $e.activeBuffer.getLine(0) == "hello"

  test "Character keys in Search overlay build search text":
    let e = createEditorForOverlayPlayback("hello world")
    e.state.enterSearchOverlay(SearchDirection.Forward)

    for ch in "wor":
      let kc = KeyCombo(isSpecial: false, char: $ch, modifiers: {})
      discard e.handlerManager.runKeyCombo(e, kc)

    check e.state.input.search.text == "wor"

suite "updateViewportReservedLines - steady reserve":
  test "Multi-line status message keeps the motion reserve steady":
    # Motion scrolling reads viewportReservedLines, which must
    # stay on the steady bottom reserve so a transient multi-line status message
    # does not change how far a motion scrolls (matching the scroll authority and
    # the screen cursor).
    let e = createTestEditorWithBuffer("line0\nline1\nline2")
    e.screenSize.width = 80
    e.state.showTabLine = false

    e.state.setStatusQuiet("error 1\nerror 2\nerror 3")
    # The message grew the dynamic reserve the old code would have used...
    check e.state.statusMessageLineCount == 3
    check e.state.bottomAreaHeight(80) > steadyBottomAreaHeight()

    # ...but the motion reserve stays steady.
    e.updateViewportReservedLines()
    check e.state.windowDisplay.viewportReservedLines == steadyBottomAreaHeight()

proc addSecondWindow(e: Editor, buf2: TextBuffer, vpx: int = 40) =
  ## Split the 80-wide viewport at `vpx` and add a right-half window.
  e.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: vpx, height: 24, topLine: 0, leftColumn: 0)
  let win2 = EditorWindow(
    viewBuffer: buf2,
    tabBufferId: buf2.id,
    bufferIds: @[buf2.id],
    viewport:
      ViewPort(x: vpx, y: 0, width: 80 - vpx, height: 24, topLine: 0, leftColumn: 0),
    cursor: BufferPosition(line: 0, column: 0),
    active: false,
    mode: EditorMode.Normal,
  )
  e.windowManager.windows.add(win2)

suite "handleMouseEvent - Cross-window jump finalizes stale state":
  test "Forced Insert mode survives a jump to a Normal-mode window":
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.config.standard.forceInsertMode = true
    e.state.config.standard.forceInsertMode = true
    e.enforceModePolicy()
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("xxx\nyyy\nzzz")
    e.addSecondWindow(buf2)

    let handled = e.handleMouseEvent(makeLeftClickEvent(50, 1))

    check handled
    check e.windowManager.activeWindowIndex == 1
    check e.state.mode == EditorMode.Insert
    check buf2.inTransaction

  test "Insert-mode transaction on old buffer is committed":
    # Without the finalize hook, bufA's open transaction leaks past the jump.
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("xxx\nyyy\nzzz")
    e.addSecondWindow(buf2)

    let bufA = e.windowManager.windows[0].buffer
    e.state.mode = EditorMode.Insert
    check bufA.beginTransaction("Insert mode edit").isOk
    check bufA.inTransaction

    let handled = e.handleMouseEvent(makeLeftClickEvent(50, 1))
    check handled == true

    check e.windowManager.activeWindowIndex == 1
    check not bufA.inTransaction
    check e.state.mode == EditorMode.Normal

  test "Completion and signature help close on the jump":
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("xxx\nyyy\nzzz")
    e.addSecondWindow(buf2)

    let bufA = e.windowManager.windows[0].buffer
    let insertHandler = e.handlerManager.insertHandler
    e.state.mode = EditorMode.Insert
    insertHandler.completionManager.state = csActive
    insertHandler.completionManager.setLspRequestPending(7, bufA.id)
    insertHandler.signatureHelpManager.state = shsActive

    check e.handleMouseEvent(makeLeftClickEvent(50, 1))

    check e.windowManager.activeWindowIndex == 1
    check not insertHandler.completionManager.isActive
    check not insertHandler.completionManager.isPendingLsp
    check insertHandler.signatureHelpManager.state == shsIdle

  test "Visual selection is cleared before touching new buffer":
    # Anchor line 5 on a 6-line buf, click into a 2-line buf: a surviving
    # visualSelection would OOB in the next Visual operator.
    let e = createTestEditorWithBuffer("a\nb\nc\nd\ne\nf")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("x\ny")
    e.addSecondWindow(buf2)

    e.state.selectVisual(
      BufferPosition(line: 5, column: 0), BufferPosition(line: 5, column: 0)
    )

    let handled = e.handleMouseEvent(makeLeftClickEvent(50, 0))
    check handled == true

    check e.windowManager.activeWindowIndex == 1
    check not e.state.visualSelection.active
    check e.state.mode == EditorMode.Normal

  test "Pending operator does not fire on the newly-active buffer":
    # PendingOperator.startPos has no buffer identity; a surviving one would
    # apply bufA's coordinates to bufB on the next motion.
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("xxx\nyyy")
    e.addSecondWindow(buf2)

    e.state.mode = EditorMode.Normal
    e.state.pendingInput.pendingOperator = some(
      PendingOperator(
        operatorType: OpDelete,
        operatorCount: 1,
        startPos: BufferPosition(line: 2, column: 0),
      )
    )
    e.state.pendingInput.pendingTextObject = some(PendingTextObject(modifier: tomInner))

    let handled = e.handleMouseEvent(makeLeftClickEvent(50, 0))
    check handled == true

    check e.windowManager.activeWindowIndex == 1
    check e.state.pendingInput.pendingOperator.isNone
    check e.state.pendingInput.pendingTextObject.isNone

  test "a click into another window after Ctrl-o resumes Insert there":
    # As Vim does for any window change the Ctrl-o command makes.
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("xxx\nyyy")
    e.addSecondWindow(buf2)

    let bufA = e.windowManager.windows[0].buffer
    e.state.mode = EditorMode.Normal
    check e.handleKeyCombo(parseKeyCombo("i").get)
    check e.handleKeyCombo(parseKeyCombo("C-o").get)
    check not bufA.inTransaction

    check e.handleEvent(makeLeftClickEvent(50, 0))

    check e.windowManager.activeWindowIndex == 1
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone
    check not bufA.inTransaction
    check buf2.inTransaction

  test "Click on the same window keeps mode/state intact":
    # The finalize hook must fire only on cross-window jumps.
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.showTabLine = false
    e.state.showStatusLine = true

    let bufA = e.windowManager.windows[0].buffer
    e.state.mode = EditorMode.Insert
    check bufA.beginTransaction("Insert mode edit").isOk

    # Two windows so the same-window branch (not the single-window one) runs.
    let buf2 = newTextBuffer("xxx")
    e.addSecondWindow(buf2)

    let handled = e.handleMouseEvent(makeLeftClickEvent(10, 1))
    check handled == true

    check e.windowManager.activeWindowIndex == 0
    check bufA.inTransaction
    check e.state.mode == EditorMode.Insert

proc enterRecentFileWith(e: Editor, paths: seq[string]) =
  ## Enter Recent File mode in a split window with a fixed entry list.
  check e.enterRecentFileMode().isOk
  check e.activeWindow.modeState.kind == mskRecentFile
  e.activeWindow.modeState.recentFile.items = @[]
  for p in paths:
    e.activeWindow.modeState.recentFile.items.add RecentFileEntry(path: p)
  e.activeWindow.modeState.recentFile.selectedIndex = 0
  e.state.mode = EditorMode.RecentFile
  e.activeWindow.mode = EditorMode.RecentFile

suite "handleRecentFileModeKeyCombo - window cleanup":
  let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})

  test "Enter opens the selected file and tears down the recent file window":
    let e = createTestEditorWithBuffer("hello")
    let winCount = e.windowManager.windows.len

    let testFile = getTempDir() / "moe_recent_open_test.txt"
    writeFile(testFile, "opened content")
    defer:
      removeFile(testFile)

    e.enterRecentFileWith(@[testFile])
    let recentBufId = e.activeWindow.buffer.id
    check e.windowManager.windows.len == winCount + 1

    check e.handleRecentFileModeKeyCombo(enterKey) == true

    # The split window and its scratch buffer are gone.
    check e.windowManager.windows.len == winCount
    check e.bufferIndexById(recentBufId) < 0
    for win in e.windowManager.windows:
      check recentBufId notin win.bufferIds

    check e.state.mode == EditorMode.Normal
    check e.activeWindow.mode == EditorMode.Normal
    check e.state.statusMessage == "Opened: " & testFile
    check e.activeBuffer.filePath == some(testFile)

  test "Enter on a missing file keeps the recent file window open":
    let e = createTestEditorWithBuffer("hello")
    let winCount = e.windowManager.windows.len

    let missing = getTempDir() / "moe_recent_missing_test.txt"
    removeFile(missing)

    e.enterRecentFileWith(@[missing])
    let recentBufId = e.activeWindow.buffer.id

    check e.handleRecentFileModeKeyCombo(enterKey) == true

    check e.windowManager.windows.len == winCount + 1
    check e.activeWindow.buffer.id == recentBufId
    check e.state.mode == EditorMode.RecentFile
    check e.state.statusMessage == "File not found: " & missing

suite "processMiscResult - hrDeleteLines":
  test "the cursor lands on the first deleted line, not on its old one":
    # An Ex range widened by a closed fold deletes above the cursor, so following
    # the range is what keeps the cursor on the line that came after it.
    let e = createTestEditorWithBuffer("a\nb\nf")
    e.activeWindow.cursor = BufferPosition(line: 2, column: 1)
    let r = HandlerResult(
      kind: hrDeleteLines,
      hrDeletedText: "c\nd\ne\n",
      hrDeletedLineCount: 3,
      hrDeleteStartLine: 2,
    )

    check e.processMiscResult(r, e.activeBuffer())
    check e.activeWindow.cursor.line == 2
    check e.activeWindow.cursor.column == 0

  test "a start line past the end of the buffer is clamped":
    let e = createTestEditorWithBuffer("a")
    e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
    let r = HandlerResult(
      kind: hrDeleteLines,
      hrDeletedText: "b\nc\n",
      hrDeletedLineCount: 2,
      hrDeleteStartLine: 5,
    )

    check e.processMiscResult(r, e.activeBuffer())
    check e.activeWindow.cursor.line == 0

suite "Ctrl-w window commands in special modes":
  proc createSplitEditorInFileTree(): Editor =
    let e = createTestEditorWithBuffer("line0\nline1")
    check e.vsplit().isOk
    e.windowManager.windows[0].mode = EditorMode.FileTree
    e.state.mode = EditorMode.FileTree
    e

  proc sendWindowCommand(e: Editor, key: string) =
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "w", modifiers: {kmCtrl}))
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: key, modifiers: {}))

  test "Ctrl-w > widens the active window":
    let e = createSplitEditorInFileTree()
    let width =
      e.windowManager.windows[e.windowManager.activeWindowIndex].viewport.width

    e.sendWindowCommand(">")

    check e.windowManager.windows[e.windowManager.activeWindowIndex].viewport.width >
      width

  test "Ctrl-w < narrows the active window":
    let e = createSplitEditorInFileTree()
    let width =
      e.windowManager.windows[e.windowManager.activeWindowIndex].viewport.width

    e.sendWindowCommand("<")

    check e.windowManager.windows[e.windowManager.activeWindowIndex].viewport.width <
      width

  proc editorOnTempFile(name: string): tuple[e: Editor, path: string] =
    let path = getTempDir() / name
    writeFile(path, "line0\nline1\n")
    let e = createTestEditorWithBuffer("")
    check e.editFile(path).isOk
    (e, path)

  test "Ctrl-w c closes a split viewer and drops its scratch buffer":
    for kind in [
      hrConfig, hrEnterHelpViewer, hrEnterLogViewer, hrEnterBackupManager,
      hrEnterRecoveryManager, hrRecentFile,
    ]:
      checkpoint $kind
      let (e, path) = editorOnTempFile("moe_ctrlw_close_viewer.txt")
      defer:
        removeFile(path)
      let origWin = e.activeWindow
      let windowsBefore = e.windowManager.windows.len
      check e.processResult(HandlerResult(kind: kind), e.activeBuffer())
      check e.windowManager.windows.len == windowsBefore + 1
      let scratchId = e.activeWindow.buffer.id

      e.sendWindowCommand("c")

      check e.windowManager.windows.len == windowsBefore
      check e.activeWindow == origWin
      check e.state.mode == EditorMode.Normal
      check e.bufferIndexById(scratchId) < 0

  test "Ctrl-w c on the last window does not quit over a modified buffer":
    # The in-place Filer hides the modified file buffer from the window.
    let (e, path) = editorOnTempFile("moe_ctrlw_close_last.txt")
    defer:
      removeFile(path)
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "x", modifiers: {}))
    check e.activeBuffer().isModified
    check e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer())
    check e.state.mode == EditorMode.Filer
    check e.windowManager.windows.len == 1

    e.sendWindowCommand("c")

    check e.state.mode == EditorMode.Filer
    check e.state.statusMessage.contains("No write since last change")

  test "Ctrl-w c on the last window does not quit over the visible modified buffer":
    let (e, path) = editorOnTempFile("moe_ctrlw_close_last_visible.txt")
    defer:
      removeFile(path)
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "x", modifiers: {}))
    check e.windowManager.windows.len == 1

    e.sendWindowCommand("c")

    check e.windowManager.windows.len == 1
    check e.activeBuffer().isModified
    check e.state.statusMessage == "No write since last change (use :q! to discard)"

  test "Ctrl-w c on the last window counts the visible and the hidden modified buffers":
    let (e, path) = editorOnTempFile("moe_ctrlw_close_last_both.txt")
    let other = getTempDir() / "moe_ctrlw_close_last_both_other.txt"
    writeFile(other, "other\n")
    defer:
      removeFile(path)
      removeFile(other)
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "x", modifiers: {}))
    check e.activeBuffer().isModified
    check e.editFile(other).isOk
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "x", modifiers: {}))
    check e.activeBuffer().isModified
    check e.windowManager.windows.len == 1

    e.sendWindowCommand("c")

    check e.windowManager.windows.len == 1
    check e.state.statusMessage ==
      "No write since last change: 2 buffers modified (use :q! to discard)"

  test "Ctrl-w c on the last window quits when nothing is modified":
    let (e, path) = editorOnTempFile("moe_ctrlw_close_last_clean.txt")
    defer:
      removeFile(path)
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "w", modifiers: {kmCtrl}))
    check not e.handleKeyCombo(KeyCombo(isSpecial: false, char: "c", modifiers: {}))

  test "Forced close of the last window quits over a modified buffer":
    let (e, path) = editorOnTempFile("moe_ctrlw_close_last_force.txt")
    defer:
      removeFile(path)
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "x", modifiers: {}))
    check not e.processResult(
      HandlerResult(kind: hrCloseWindow, forceClose: true), e.activeBuffer()
    )

  test ":q! quits with a modified visible buffer":
    let (e, path) = editorOnTempFile("moe_q_force_modified.txt")
    defer:
      removeFile(path)
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "x", modifiers: {}))
    check e.activeBuffer().isModified
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":q!"

    check not handleCommandModeEvent(e, makeEnterEvent())

  test "Ctrl-w c closes a split on a modified buffer and keeps the buffer":
    let (e, path) = editorOnTempFile("moe_ctrlw_close_split_a.txt")
    let other = getTempDir() / "moe_ctrlw_close_split_b.txt"
    writeFile(other, "other\n")
    defer:
      removeFile(path)
      removeFile(other)
    check e.vsplit().isOk
    check e.editFile(other).isOk
    check e.handleKeyCombo(KeyCombo(isSpecial: false, char: "x", modifiers: {}))
    let modifiedId = e.activeBuffer().id

    e.sendWindowCommand("c")

    check e.windowManager.windows.len == 1
    check e.activeBuffer().id != modifiedId
    let idx = e.bufferIndexById(modifiedId)
    check idx >= 0
    check e.buffers[idx].isModified

  test "Ctrl-w n opens an empty buffer in a new window above":
    let (e, path) = editorOnTempFile("moe_ctrlw_new.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let origBufferId = e.activeBuffer().id

    e.sendWindowCommand("n")

    check e.windowManager.windows.len == 2
    check e.activeWindow != origWin
    check e.activeWindow.viewport.x == origWin.viewport.x
    check e.activeWindow.viewport.y < origWin.viewport.y
    check e.activeBuffer().id != origBufferId
    check e.activeBuffer().len == 1
    check e.activeBuffer().getLine(0).len == 0
    check e.state.mode == EditorMode.Normal
    check origWin.buffer.id == origBufferId

  test "Ctrl-w n in a special mode opens an empty buffer in Normal mode":
    let e = createSplitEditorInFileTree()
    let windowsBefore = e.windowManager.windows.len

    e.sendWindowCommand("n")

    check e.windowManager.windows.len == windowsBefore + 1
    check e.activeBuffer().len == 1
    check e.activeBuffer().getLine(0).len == 0
    check e.state.mode == EditorMode.Normal

suite "Ctrl-C in Terminal mode":
  proc fakeTerminalState(): TerminalState =
    TerminalState(
      pty: PtyHandle(masterFd: -1, childPid: Pid(0), closed: true),
      grid: newTerminalGrid(80, 24),
      exitCode: none(int),
      waitingForCtrlN: false,
      needsBufferRefresh: false,
    )

  proc createTerminalEditor(subMode: TerminalSubMode): Editor =
    result = createTestEditorWithBuffer("")
    let termState = fakeTerminalState()
    result.terminalStates[result.activeWindow.buffer.id] = termState
    result.activeWindow.modeState = ModeState(
      kind: mskTerminal,
      terminal: termState,
      scrollbackSnapshot:
        if subMode == tsmNormal:
          termState.snapshotScrollback()
        else:
          nil,
    )
    result.activeWindow.mode = EditorMode.Terminal
    result.state.mode = EditorMode.Terminal

  test "Ctrl-C closes a command overlay opened over the Terminal":
    let e = createTerminalEditor(tsmNormal)
    e.state.enterCommandOverlay()

    check e.handleInterrupt()

    check not e.state.hasOverlay
    check e.state.mode == EditorMode.Terminal

  test "Ctrl-C closes a search overlay opened over the Terminal":
    let e = createTerminalEditor(tsmNormal)
    e.state.enterSearchOverlay(Forward)

    check e.handleInterrupt()

    check not e.state.hasOverlay
    check e.state.mode == EditorMode.Terminal

  proc createTerminalEditorWithPaste(subMode: TerminalSubMode = tsmNormal): Editor =
    result = createTerminalEditor(subMode)
    let termState = result.activeWindow.modeState.terminal
    termState.pty = PtyHandle(masterFd: -1, childPid: Pid(0), closed: false)
    check termState.pty.queueWrite("paste", wcDroppable).isOk

  test "Ctrl-C over the Terminal drops the queued paste":
    let e = createTerminalEditorWithPaste()

    check e.handleInterrupt()

    check e.activeWindow.modeState.terminal.pty.droppableBytes == 0

  test "Ctrl-C meant for an overlay leaves the queued paste draining":
    let e = createTerminalEditorWithPaste()
    e.state.enterCommandOverlay()

    check e.handleInterrupt()

    check not e.state.hasOverlay
    check e.activeWindow.modeState.terminal.pty.droppableBytes == 5

  test "Ctrl-C in the Input sub-mode stays with the child process":
    let e = createTerminalEditor(tsmInput)

    check e.handleInterrupt()

    check e.state.mode == EditorMode.Terminal

  test "Ctrl-C meant for an overlay never reaches the child in the Input sub-mode":
    let e = createTerminalEditorWithPaste(tsmInput)
    e.state.enterCommandOverlay()

    check e.handleInterrupt()

    check not e.state.hasOverlay
    check e.state.mode == EditorMode.Terminal
    # `interrupt()` would have dropped the paste on its way to the child.
    check e.activeWindow.modeState.terminal.pty.droppableBytes == 5

suite "gn - the match becomes the selection":
  proc charKey(c: string): KeyCombo =
    KeyCombo(isSpecial: false, char: c, modifiers: {})

  test "gn selects from the match start to its end":
    let e = createTestEditorWithBuffer("say hello")
    e.state.input.search.last.pattern = "hello"

    check e.handleKeyCombo(charKey("g"))
    check e.handleKeyCombo(charKey("n"))

    check e.state.mode == EditorMode.Visual
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 4)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 8)

  test "<C-o>gn selects the match, and Insert resumes after Visual mode":
    let e = createTestEditorWithBuffer("say hello")
    e.state.input.search.last.pattern = "hello"
    check e.handleKeyCombo(charKey("i"))
    check e.handleKeyCombo(
      KeyCombo(isSpecial: false, char: "o", modifiers: {key_bindings.kmCtrl})
    )

    check e.handleKeyCombo(charKey("g"))
    check e.handleKeyCombo(charKey("n"))

    check e.state.mode == EditorMode.Visual
    check e.state.insertResume != irNone
    check not e.activeBuffer.inTransaction
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 4)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 8)

    check e.handleKeyCombo(charKey("d"))

    check e.activeBuffer.getLine(0) == "say "
    check e.state.mode == EditorMode.Insert
    check e.state.insertResume == irNone

suite "handleInterrupt - Visual":
  test "Ctrl-C leaves Visual like Esc, back to the mode it was entered from":
    let e = createTestEditorWithBuffer("hello world")
    e.state.selectVisual(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 4)
    )
    e.state.previousMode = EditorMode.LogViewer

    check e.handleInterrupt()

    check e.state.mode == EditorMode.LogViewer
    # Unlike leaving Insert, the cursor stays put.
    check e.cursor == BufferPosition(line: 0, column: 4)

  test "switching the Visual kind keeps the mode Visual was entered from":
    let e = createTestEditorWithBuffer("hello world")
    e.state.selectVisual(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 4)
    )
    e.state.previousMode = EditorMode.LogViewer

    discard e.processResult(
      HandlerResult(kind: hrHandled, modeTransition: some(EditorMode.VisualLine)),
      e.activeBuffer(),
    )
    check e.state.mode == EditorMode.VisualLine
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 0)

    check e.handleInterrupt()

    check e.state.mode == EditorMode.LogViewer

  test "Ctrl-C clears a pending Visual operand":
    let e = createTestEditorWithBuffer("hello world")
    e.state.selectVisual(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 4)
    )
    e.keyRouter.registry.sequenceState.register = some('a')

    check e.handleInterrupt()

    check e.state.mode == EditorMode.Normal
    check e.keyRouter.registry.sequenceState.register.isNone

  proc typeChars(e: Editor, keys: string) =
    for key in keys:
      check e.handleKeyCombo(KeyCombo(isSpecial: false, char: $key, modifiers: {}))

  test "Ctrl-C after v$ puts the cursor back on the last character":
    let e = createTestEditorWithBuffer("abc\ndef")
    e.typeChars("v$")
    check e.cursor == BufferPosition(line: 0, column: 3)

    check e.handleInterrupt()

    check e.state.mode == EditorMode.Normal
    check e.cursor == BufferPosition(line: 0, column: 2)
    # A fresh `vd` takes the last character, not the newline.
    e.typeChars("vd")
    check e.activeBuffer.getLine(0) == "ab"
    check e.activeBuffer.getLine(1) == "def"

  test "Esc after v$ puts the cursor back on the last character":
    let e = createTestEditorWithBuffer("abc\ndef")
    e.typeChars("v$")

    check e.handleKeyCombo(KeyCombo(isSpecial: true, special: skEscape))

    check e.state.mode == EditorMode.Normal
    check e.cursor == BufferPosition(line: 0, column: 2)

  test "Ctrl-C from a mouse selection in forced Insert mode lands in Insert":
    let e = createTestEditorWithBuffer("hello world")
    e.config.standard.forceInsertMode = true
    e.state.config.standard.forceInsertMode = true
    e.enforceModePolicy()
    check e.activeBuffer.commitTransaction().isOk
    # A mouse selection started from Insert records Normal as the way back.
    e.state.selectVisual(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 4)
    )
    e.state.previousMode = EditorMode.Normal

    check e.handleInterrupt()

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.inTransaction

suite "middleClickPaste - the click picks the target":
  proc fakeTerminalState(): TerminalState =
    TerminalState(
      pty: PtyHandle(masterFd: -1, childPid: Pid(0), closed: false),
      grid: newTerminalGrid(80, 24),
      exitCode: none(int),
      waitingForCtrlN: false,
      needsBufferRefresh: false,
    )

  proc editorWithTerminalAndSplit(): tuple[e: Editor, term: TerminalState] =
    ## Active window (top) runs a Terminal session; a second window (bottom)
    ## shows an ordinary buffer.
    let e = createTestEditorForMiddleClick("")
    let top = e.windowManager.windows[0]
    top.viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 12, topLine: 0, leftColumn: 0)

    let term = fakeTerminalState()
    e.terminalStates[top.buffer.id] = term
    top.modeState = ModeState(kind: mskTerminal, terminal: term)
    top.mode = EditorMode.Terminal
    e.state.mode = EditorMode.Terminal

    let otherBuf = newTextBuffer("hello")
    e.addBuffer(otherBuf)
    let bottom = EditorWindow(
      viewBuffer: otherBuf,
      tabBufferId: otherBuf.id,
      bufferIds: @[otherBuf.id],
      viewport: ViewPort(x: 0, y: 12, width: 80, height: 12, topLine: 0, leftColumn: 0),
      cursor: BufferPosition(line: 0, column: 0),
      mode: EditorMode.Normal,
      previousMode: EditorMode.Normal,
      screenCursor: CursorPosition(x: 0, y: 0),
      active: false,
      wrapCountCache: WrapCountCache(),
    )
    e.windowManager.windows.add(bottom)
    (e, term)

  proc editorWithFullScreenTerminal(): tuple[e: Editor, term: TerminalState] =
    ## A single Terminal window over the whole screen, so the shared
    ## status/command row is the last row of its viewport.
    let e = createTestEditorForMiddleClick("")
    let win = e.windowManager.windows[0]
    win.viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)

    let term = fakeTerminalState()
    e.terminalStates[win.buffer.id] = term
    win.modeState = ModeState(kind: mskTerminal, terminal: term)
    win.mode = EditorMode.Terminal
    e.state.mode = EditorMode.Terminal
    (e, term)

  proc editorWithTwoBufferWindows(): Editor =
    ## Two ordinary buffer windows, the top one active.
    let e = createTestEditorForMiddleClick("top")
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 12, topLine: 0, leftColumn: 0)

    let bottomBuffer = newTextBuffer("bottom")
    e.addBuffer(bottomBuffer)
    e.windowManager.windows.add(
      EditorWindow(
        viewBuffer: bottomBuffer,
        tabBufferId: bottomBuffer.id,
        bufferIds: @[bottomBuffer.id],
        viewport:
          ViewPort(x: 0, y: 12, width: 80, height: 12, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        mode: EditorMode.Normal,
        previousMode: EditorMode.Normal,
        screenCursor: CursorPosition(x: 0, y: 0),
        active: false,
        wrapCountCache: WrapCountCache(),
      )
    )
    e

  proc primarySelectionHolds(text: string): bool =
    ## Put `text` in PRIMARY. False when this environment has no clipboard
    ## tool: a middle click with nothing to paste is a no-op by design, so a
    ## focus assertion needs a real selection behind it.
    if not isClipboardToolAvailable():
      return false
    if writeToPrimarySelectionSync(getAvailableClipboardTool(), text).isErr:
      return false
    sleep(100)
    true

  test "a click in another split does not reach the terminal's child":
    ## Regression: the Terminal branch ran before any hit test, so a click
    ## meant for another split queued the selection to the shell, which runs it
    ## (newlines are normalized to CR and the shell has no bracketed paste).
    if not primarySelectionHolds("split"):
      skip()
    else:
      let (e, term) = editorWithTerminalAndSplit()
      require term.pty.pendingWriteBytes == 0

      # Inside the bottom window.
      e.middleClickPaste(row = 15, col = 10)

      check term.pty.pendingWriteBytes == 0
      check e.activeWindow == e.windowManager.windows[1]
      check e.state.mode != EditorMode.Terminal

  test "a click on the tab line reaches nothing":
    let (e, term) = editorWithTerminalAndSplit()
    let activeBefore = e.activeWindow
    e.state.setStatusQuiet("")

    e.middleClickPaste(row = 0, col = 10)

    check term.pty.pendingWriteBytes == 0
    check e.state.statusMessage == ""
    check e.activeWindow == activeBefore
    check e.activeBuffer().getLine(0).len == 0

  test "a click below every window reaches nothing":
    let (e, term) = editorWithTerminalAndSplit()
    let activeBefore = e.activeWindow
    e.state.setStatusQuiet("")

    # The command-line row, under both viewports.
    e.middleClickPaste(row = 24, col = 10)

    check term.pty.pendingWriteBytes == 0
    check e.state.statusMessage == ""
    check e.activeWindow == activeBefore

  test "a click on the status row never reaches the child":
    ## Regression: the hit test bounded the window at the bottom of its
    ## viewport instead of subtracting the status/command reserve, so a click
    ## on the shared bottom row resolved to the terminal and the shell ran the
    ## selection.
    let (e, term) = editorWithFullScreenTerminal()
    e.state.setStatusQuiet("")

    e.middleClickPaste(row = 23, col = 10)

    check term.pty.pendingWriteBytes == 0
    # The fake pty cannot accept bytes, so the byte count alone would also hold
    # for a paste that was attempted and refused: an attempt leaves a message.
    check e.state.statusMessage == ""

  test "a click in another split leaves the terminal window in Terminal mode":
    ## Regression: the mouse-jump finalizer assigned Normal to `state.mode`,
    ## which aliases the window losing the focus, so the terminal window's mode
    ## stopped matching its modeState: it rendered as an empty buffer and its
    ## session was no longer resized or reaped.
    if not primarySelectionHolds("split"):
      skip()
    else:
      let (e, _) = editorWithTerminalAndSplit()

      e.middleClickPaste(row = 15, col = 10)

      check e.activeWindow == e.windowManager.windows[1]
      check e.windowManager.windows[0].mode == EditorMode.Terminal
      check e.windowManager.windows[0].modeState.kind == mskTerminal

  test "a click in another split still rewinds an edit mode to Normal":
    if not primarySelectionHolds("split"):
      skip()
    else:
      let e = editorWithTwoBufferWindows()
      e.state.mode = EditorMode.Insert

      e.middleClickPaste(row = 15, col = 10)

      check e.activeWindow == e.windowManager.windows[1]
      check e.windowManager.windows[0].mode == EditorMode.Normal

  test "the paste reattaches the window it landed in":
    ## Regression: the flag was cleared on the window that had the focus, while
    ## the click pastes into the window under the pointer. A wheel-scrolled
    ## split kept its detached viewport, leaving the cursor off-screen.
    if not isClipboardToolAvailable():
      skip()
    else:
      let writeResult =
        writeToPrimarySelectionSync(getAvailableClipboardTool(), "reattach")
      check writeResult.isOk
      sleep(100)

      let e = editorWithTwoBufferWindows()
      e.windowManager.windows[1].viewport.detachedFromCursor = true

      e.middleClickPaste(row = 15, col = 10)

      check e.activeWindow == e.windowManager.windows[1]
      check $e.activeBuffer.getLine(0) == "reattachbottom"
      check not e.windowManager.windows[1].viewport.detachedFromCursor

  test "a failed clipboard read leaves the focus where it was":
    ## Regression: the window was activated before PRIMARY was read, so a
    ## middle click with no working clipboard tool jumped the focus anyway and
    ## finalized the Insert session of the window it came from.
    let e = editorWithTwoBufferWindows()
    # win32yank.exe does not exist here, so the primary selection read fails.
    e.config.clipboard.tool = cbtWin32yank
    e.config.notification.popupNotifications = false
    e.state.mode = EditorMode.Insert

    e.middleClickPaste(row = 15, col = 10)

    check e.activeWindow == e.windowManager.windows[0]
    check e.windowManager.windows[0].mode == EditorMode.Insert
    check e.state.statusMessage.contains("Paste failed")

  test "a paste refused by the target does not move the focus either":
    ## The refusal is decided on the window the click picked, so it costs
    ## neither a clipboard round trip nor the focus.
    let e = editorWithTwoBufferWindows()
    e.config.notification.popupNotifications = false
    e.windowManager.windows[1].buffer.readOnly = true

    e.middleClickPaste(row = 15, col = 10)

    check e.activeWindow == e.windowManager.windows[0]
    check e.state.statusMessage == "Buffer is read-only"

  test "a click in the terminal delivers the selection to the child":
    if not primarySelectionHolds("term-ok"):
      skip()
    else:
      var fds: array[2, cint]
      require pipe(fds) == 0
      # Non-blocking read so a failed paste cannot hang the suite.
      discard fcntl(fds[0], F_SETFL, O_NONBLOCK)
      defer:
        discard close(fds[0])
        discard close(fds[1])

      let e = createTestEditorForMiddleClick("")
      let win = e.windowManager.windows[0]
      win.viewport =
        ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)

      let term = TerminalState(
        pty: PtyHandle(masterFd: fds[1], childPid: Pid(999999), closed: false),
        grid: newTerminalGrid(80, 24),
        exitCode: none(int),
        waitingForCtrlN: false,
        needsBufferRefresh: false,
      )
      e.terminalStates[win.buffer.id] = term
      win.modeState = ModeState(kind: mskTerminal, terminal: term)
      win.mode = EditorMode.Terminal
      e.state.mode = EditorMode.Terminal
      e.state.setStatusQuiet("")

      # Inside the terminal content area (not the status/command reserve).
      e.middleClickPaste(row = 5, col = 10)

      var buf = newString(64)
      let n = read(fds[0], addr buf[0], cint(buf.len))
      require n > 0
      buf.setLen(n)
      check buf == "term-ok"
      check e.activeBuffer().getLine(0).len == 0
      check e.state.mode == EditorMode.Terminal

suite "pointerPositionInWindow":
  proc singleWindowEditor(showTabLine: bool): Editor =
    let e = createTestEditorForMiddleClick("aaa\nbbb\nccc")
    e.state.showTabLine = showTabLine
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    e

  proc splitWindowEditor(): Editor =
    let e = singleWindowEditor(showTabLine = true)
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 12, topLine: 0, leftColumn: 0)

    let bottomBuffer = newTextBuffer("ddd\neee")
    e.addBuffer(bottomBuffer)
    e.windowManager.windows.add(
      EditorWindow(
        viewBuffer: bottomBuffer,
        tabBufferId: bottomBuffer.id,
        bufferIds: @[bottomBuffer.id],
        viewport:
          ViewPort(x: 0, y: 12, width: 80, height: 12, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        mode: EditorMode.Normal,
        active: false,
        wrapCountCache: WrapCountCache(),
      )
    )
    e

  test "the shared status/command row is not part of the window's text":
    # Regression: the tab line came off the clicked row but not off the bottom
    # reserve, so the row below the last one drawn was still accepted and
    # clamped onto the last buffer line.
    let e = singleWindowEditor(showTabLine = true)

    check e.pointerPositionInWindow(initPointerInput(22, 10), 0).isSome
    check e.pointerPositionInWindow(initPointerInput(23, 10), 0).isNone

  test "with the tab line off the window keeps its last text row":
    let e = singleWindowEditor(showTabLine = false)

    check e.pointerPositionInWindow(initPointerInput(0, 10), 0).isSome
    check e.pointerPositionInWindow(initPointerInput(22, 10), 0).isSome
    check e.pointerPositionInWindow(initPointerInput(23, 10), 0).isNone

  test "a non-bottom window stops above its own status row":
    let e = splitWindowEditor()

    check e.pointerPositionInWindow(initPointerInput(10, 10), 0).isSome
    check e.pointerPositionInWindow(initPointerInput(11, 10), 0).isNone
    check e.pointerPositionInWindow(initPointerInput(22, 10), 1).isSome
    check e.pointerPositionInWindow(initPointerInput(23, 10), 1).isNone

  test "agrees with windowIndexAtCell on every row":
    # The two hit tests answer the same question (left click vs middle click);
    # a row either belongs to a window's text area or it does not.
    for e in [singleWindowEditor(showTabLine = true), splitWindowEditor()]:
      for row in 0 .. 23:
        let hit = e.windowIndexAtCell(row, 10)
        for i in 0 ..< e.windowManager.windows.len:
          check e.pointerPositionInWindow(initPointerInput(row, 10), i).isSome ==
            (hit == i)

suite "windowIndexAtCell":
  proc singleWindowEditor(showTabLine: bool): Editor =
    let e = createTestEditorForMiddleClick("")
    e.state.showTabLine = showTabLine
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    e

  proc splitWindowEditor(): Editor =
    let e = singleWindowEditor(showTabLine = true)
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 12, topLine: 0, leftColumn: 0)

    let bottomBuffer = newTextBuffer("")
    e.addBuffer(bottomBuffer)
    e.windowManager.windows.add(
      EditorWindow(
        viewBuffer: bottomBuffer,
        tabBufferId: bottomBuffer.id,
        bufferIds: @[bottomBuffer.id],
        viewport:
          ViewPort(x: 0, y: 12, width: 80, height: 12, topLine: 0, leftColumn: 0),
        cursor: BufferPosition(line: 0, column: 0),
        mode: EditorMode.Normal,
        active: false,
        wrapCountCache: WrapCountCache(),
      )
    )
    e

  test "the shared status/command row belongs to no window":
    let e = singleWindowEditor(showTabLine = true)

    check e.windowIndexAtCell(22, 10) == 0
    check e.windowIndexAtCell(23, 10) == -1

  test "the status row is excluded with the tab line off too":
    # tabLineOffset drops to 0 while the bottom reserve stays, so the row the
    # window claims and the row it draws no longer happen to cancel out.
    let e = singleWindowEditor(showTabLine = false)

    check e.windowIndexAtCell(0, 10) == 0
    check e.windowIndexAtCell(22, 10) == 0
    check e.windowIndexAtCell(23, 10) == -1

  test "a non-bottom window reserves its own status row under multiStatusLine":
    let e = splitWindowEditor()

    check e.windowIndexAtCell(10, 10) == 0
    check e.windowIndexAtCell(11, 10) == -1
    check e.windowIndexAtCell(22, 10) == 1
    check e.windowIndexAtCell(23, 10) == -1

  test "without multiStatusLine the non-bottom window keeps its last row":
    let e = splitWindowEditor()
    e.state.multiStatusLine = false

    check e.windowIndexAtCell(11, 10) == 0
    check e.windowIndexAtCell(23, 10) == -1

suite "handleKeyCombo - the column vertical moves want":
  # Vim 9.2 keeps it across vertical moves, scrolls and commands that leave the
  # cursor and text alone, and takes it from the cursor again after any other
  # move, an edit, an operator, entering Insert or Replace, or leaving Visual
  # (curswant).
  proc createEditorForColumn(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal

  for (name, content, keys, typed) in [
    (
      "Insert keeps it across vertical moves",
      "abcdefghij\nab\nabcdefghij",
      @["8", "l", "i", "Down", "Down"],
      "abcdefghZij",
    ),
    (
      "Insert takes it again on entry",
      "abcdefgh\nabc\nabcdefgh",
      @["7", "l", "j", "i", "Down"],
      "abZcdefgh",
    ),
    (
      "Insert takes it again after typing",
      "abcdefghij\nab\nabcdefghij",
      @["8", "l", "i", "Down", "X", "Down"],
      "abcZdefghij",
    ),
    (
      "Replace takes it again on entry",
      "abcdefgh\nabc\nabcdefgh",
      @["7", "l", "j", "R", "Down"],
      "abZdefgh",
    ),
    (
      "Replace takes it again after typing",
      "abcdefghij\nab\nabcdefghij",
      @["8", "l", "R", "Down", "X", "Down"],
      "abcZefghij",
    ),
    (
      "a search takes it again",
      "abcdefgh\nxyz\nabcdefgh",
      @["$", "j", "?", "y", "Enter", "j", "i"],
      "aZbcdefgh",
    ),
    (
      "an edit takes it again",
      "abcdefgh\nabc\nabcdefgh",
      @["$", "j", "x", "j", "i"],
      "aZbcdefgh",
    ),
    (
      "an edit that keeps the cursor takes it again",
      "abcdefgh\nabc\nabcdefgh",
      @["$", "j", "r", "X", "j", "i"],
      "abZcdefgh",
    ),
    (
      "a scroll that moves the cursor keeps it",
      "ab\nabcdefgh\n".repeat(15),
      @["j", "$", "k", "C-e", "j", "j", "i"],
      "abcdefgZh",
    ),
    (
      "a scroll that pushes the cursor puts it on the column",
      "ab\nabcdefgh\n".repeat(15),
      @["j", "$", "k", "C-e", "i"],
      "abcdefgZh",
    ),
    (
      "a scroll that pushes the cursor keeps the column it had",
      "abcdefgh\nab\nabcdefgh\n" & "x\n".repeat(30),
      @["7", "l", "C-e", "C-e", "i"],
      "abcdefgZh",
    ),
    (
      "a vertical move after a scroll that pushed the cursor keeps it",
      "abcdefgh\nab\nabcdefgh\n" & "x\n".repeat(30),
      @["7", "l", "C-e", "j", "i"],
      "abcdefgZh",
    ),
    (
      "leaving Insert takes it again",
      "abcdefghij\n\nabcdefghij",
      @["8", "l", "i", "Down", "Escape", "j", "i"],
      "Zabcdefghij",
    ),
    (
      "leaving Replace takes it again",
      "abcdefgh\nabcde\nabcdefgh",
      @["7", "l", "R", "Down", "Escape", "j", "i"],
      "abcdZefgh",
    ),
    (
      "going back to Insert after a <C-o> command keeps it",
      "abcdefghij\nab\nabcdefghij",
      @["8", "l", "i", "C-o", "j", "Down"],
      "abcdefghZij",
    ),
    (
      "entering Insert with a <C-o> command takes it again",
      "abcdefghij\nab\nabcdefghij",
      @["8", "l", "i", "C-o", "j", "C-o", "i", "Down"],
      "aZbcdefghij",
    ),
    (
      "going back to Insert from a cancelled <C-o> command line keeps it",
      "abcdefghij\nab\nabcdefghij",
      @["8", "l", "i", "Down", "C-o", ":", "Escape", "Down"],
      "abcdefghZij",
    ),
    # The preview moves the cursor as Vim's incsearch does.
    (
      "a cancelled :s whose preview moved the cursor takes it again",
      "abcdefghij\nab\nabcdefghij",
      @["7", "l", "j", ":", "s", "/", "a", "/", "b", "Escape", "j", "i"],
      "aZbcdefghij",
    ),
    (
      "a cancelled search whose preview moved the cursor takes it again",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "/", "c", "Escape", "j", "i"],
      "aZbcdefgh",
    ),
    (
      "a yank of lines takes it again",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "y", "y", "j", "i"],
      "aZbcdefgh",
    ),
    (
      "a yank that leaves the cursor takes it again",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "y", "l", "j", "i"],
      "aZbcdefgh",
    ),
    (
      "leaving Visual takes it again",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "v", "Escape", "j", "i"],
      "aZbcdefgh",
    ),
    (
      "leaving Visual Line takes it again",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "V", "Escape", "j", "i"],
      "aZbcdefgh",
    ),
    (
      "0 in place takes it again",
      "abcdefgh\n\nabcdefgh",
      @["7", "l", "j", "0", "j", "i"],
      "Zabcdefgh",
    ),
    (
      "a command that leaves the cursor and text alone keeps it",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "z", "z", "m", "a", "j", "i"],
      "abcdefgZh",
    ),
    (
      "a move that fails in place keeps it",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "l", "f", "z", "j", "i"],
      "abcdefgZh",
    ),
    (
      "an operator whose motion fails keeps it",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "d", "f", "z", "j", "i"],
      "abcdefgZh",
    ),
    (
      "a cancelled operator keeps it",
      "abcdefgh\nab\nabcdefgh",
      @["7", "l", "j", "d", "Escape", "j", "i"],
      "abcdefgZh",
    ),
    (
      "a macro that moves after its vertical move takes it again",
      "abcdefgh\nab\nabcdefgh\nabcdefgh",
      @[
        "7", "l", "q", "a", "j", "/", "c", "Enter", "q", "g", "g", "7", "l", "@", "a",
        "j", "i",
      ],
      "abZcdefgh",
    ),
    (
      "a macro keeps the column its last vertical move kept",
      "abcdefghij\nab\nabcdefghij",
      @["q", "a", "l", "j", "q", "k", "4", "l", "@", "a", "j", "i"],
      "abcdefZghij",
    ),
  ]:
    test name & ", as in Vim":
      let e = createEditorForColumn(content)

      for key in keys & @["Z"]:
        check e.handleKeyCombo(parseKeyCombo(key).get)

      check e.activeBuffer.getLine(e.cursor.line) == typed

  test "a smooth half-page scroll keeps it as the plain one does":
    let e = createEditorForColumn("ab\n" & "abcdefgh\n".repeat(60))
    check e.config.smoothScroll.enable
    for key in ["j", "$", "k", "C-d"]:
      check e.handleKeyCombo(parseKeyCombo(key).get)

    let frame = newBuffer(80, 24)
    var frames = 0
    while e.state.windowDisplay.scrollAnimation.active and frames < 10_000:
      discard e.updateForFrame(frame)
      inc frames
    check not e.state.windowDisplay.scrollAnimation.active
    check e.cursor.line > 1

    for key in ["j", "i", "Z"]:
      check e.handleKeyCombo(parseKeyCombo(key).get)
    check e.activeBuffer.getLine(e.cursor.line) == "abcdefgZh"

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  test "a smooth half-page scroll moves the cursor onto the column it aims for":
    let e = createEditorForColumn("abcdefgh\n" & "ab\n".repeat(60))
    e.press("$", "C-d")
    check e.state.windowDisplay.scrollAnimation.active

    let frame = newBuffer(80, 24)
    var frames = 0
    while e.state.windowDisplay.scrollAnimation.active and frames < 10_000:
      discard e.updateForFrame(frame)
      inc frames
      check e.cursor.column <= max(0, e.activeBuffer.getLineLen(e.cursor.line) - 1)
    check e.cursor.line > 1
    e.press("i", "Z")

    check e.activeBuffer.getLine(e.cursor.line) == "aZb"

  test "a new split window takes it from the cursor when the window split has none":
    let e = createEditorForColumn("abcdefgh\nabcdefgh")
    e.press("3", "l")
    check e.hsplit().isOk
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(1) == "abcZdefgh"

  test "a new split window takes it from the window split, as in Vim":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.press("7", "l", "j")
    check e.hsplit().isOk
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(2) == "abcdefgZh"

  test "a split by a command keeps it in the new window":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    let origin = e.activeWindow
    e.press("7", "l", "j", ":", "s", "p", "Enter")
    check e.activeWindow != origin
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(2) == "abcdefgZh"

  test "a command that splits and jumps takes it again in the new window":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.press("7", "l", "j")
    e.asCommand:
      check e.hsplit().isOk
      e.activeWindow.cursor = BufferPosition(line: 1, column: 0)
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(2) == "Zabcdefgh"

  test "an edit from another window keeps it, as in Vim":
    # Vim drops curswant only for the window's own commands.
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.press("$", "j")
    check e.hsplit().isOk
    e.press("k", "x")
    e.press("C-w", "w")
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(0) == "abcdefg"
    check e.activeBuffer.getLine(2) == "abcdefgZh"

  test "the window's own edit before it is left takes it again":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.press("$", "j", "r", "X")
    check e.hsplit().isOk
    e.press("C-w", "w")
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(2) == "aZbcdefgh"

  test "a command that puts another buffer in the window takes it again":
    let e = createEditorForColumn("abcdefgh\nab")
    e.press("$", "j")
    let win = e.activeWindow
    let at = win.cursor
    require win.preferredColumn == 7
    let other = newTextBuffer("ab\nab")
    require other.contentVersion == win.buffer.contentVersion

    e.asCommand:
      win.setTab(other)
      win.cursor = at

    check win.preferredColumn == -1

  test "a move away and a jump back take it again, as in Vim":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.press("$", "j")
    let at = e.cursor
    e.press("/", "b", "Enter")
    check e.cursor != at
    e.press("C-o")
    check e.cursor == at
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(2) == "aZbcdefgh"

  test "a click that moves the cursor takes it again":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.config.standard.mouse = true
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.press("$", "j")
    check e.handlePointerInput(initPointerInput(1, 0))
    check e.cursor == BufferPosition(line: 1, column: 0)
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(2) == "Zabcdefgh"

  test "a middle-click paste in Insert takes it again":
    when defined(posix):
      let fakeDir = installFakeClipboardTool("XY")
      defer:
        removeFakeClipboardTool(fakeDir)
      let e = createEditorForColumn("abcdefghij\nab\nabcdefghij")
      e.config.clipboard.enable = true
      e.config.clipboard.tool = cbtXclip
      e.press("8", "l", "i", "Down")
      check e.handleEvent(makeMiddleClickEvent(5, 2))
      check e.activeBuffer.getLine(1) == "abXY"
      e.press("Down", "Z")

      check e.activeBuffer.getLine(2) == "abcdZefghij"

  test "a macro's edit from another window keeps it where the macro began, as in Vim":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh\nxyz")
    e.press("7", "l", "j")
    check e.hsplit().isOk
    e.press("G", "C-w", "w")
    e.press("q", "a", "C-w", "w", "x", "C-w", "w", "q")
    e.press("@", "a")
    check e.activeBuffer.getLine(3) == "z"
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(2) == "abcdefgZh"

  test "an edit after a command run inside it changed windows keeps it in the window left, as in Vim":
    # As `:execute "normal! \<C-w>w" | s/x/X/` edits only the window entered.
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh\nxyz")
    e.press("7", "l", "j")
    check e.hsplit().isOk
    e.press("G", "C-w", "w")
    e.asCommand:
      e.press("C-w", "w")
      let buf = e.activeBuffer
      check buf.beginTransaction("test").isOk
      check buf.insertTextEnd(BufferPosition(line: 3, column: 0), "X").isOk
      check buf.commitTransaction().isOk
    e.press("C-w", "w", "j", "i", "Z")

    check e.activeBuffer.getLine(2) == "abcdefgZh"

  test "a command that keeps it and then moves takes it again":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.press("$", "j")
    let win = e.activeWindow
    e.asCommand:
      win.scrollCursor(BufferPosition(line: 2, column: 7))
      win.cursor = BufferPosition(line: 2, column: 2)

    check win.preferredColumn == -1

  test "a move before a command run inside another takes it again, as in Vim":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.press("$", "j")
    e.asCommand:
      e.activeWindow.cursor = BufferPosition(line: 0, column: 2)
      e.press("j")
    e.press("j", "i", "Z")

    check e.activeBuffer.getLine(2) == "abZcdefgh"

  test "a command that raises takes it again":
    let e = createEditorForColumn("abcdefgh\nab\nabcdefgh")
    e.press("$", "j")
    let win = e.activeWindow
    expect ValueError:
      e.asCommand:
        win.cursor = BufferPosition(line: 0, column: 0)
        raise newException(ValueError, "failed")

    check win.preferredColumn == -1

  for smooth in [false, true]:
    test "a half-page scroll onto a closed fold keeps it (smooth: " & $smooth & ")":
      let e = createEditorForColumn("ab\n" & "abcdefgh\n".repeat(60))
      e.config.smoothScroll.enable = smooth
      e.press("j", "$", "k")
      # Where the scroll lands without folds, so a fold there takes its start.
      let target = block:
        let probe = createEditorForColumn("ab\n" & "abcdefgh\n".repeat(60))
        probe.config.smoothScroll.enable = false
        probe.press("C-d")
        probe.cursor.line
      require target > 1
      check e.activeBuffer.foldState.addFold(target, target + 3)
      e.press("C-d")

      let frame = newBuffer(80, 24)
      var frames = 0
      while frames < 10_000:
        discard e.updateForFrame(frame)
        inc frames
        if not e.state.windowDisplay.scrollAnimation.active:
          break
      check e.cursor == BufferPosition(line: target, column: 0)
      e.press("j", "i", "Z")

      check e.cursor.line == target + 4
      check e.activeBuffer.getLine(target + 4) == "abcdefgZh"

suite "handleKeyCombo - which keys a mapping takes, as in Vim":
  proc createEditorForMappings(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  proc map(e: Editor, mode: EditorMode, lhs, rhs: string, noremap = true) =
    check e.keyBindingRegistry.addRuntimeMapping(mode, lhs, rhs, noremap).len == 0

  test "the keys after a held one that breaks a mapping are mapped again":
    # Vim 9.2 with `nmap ,a …` and `nmap xy …`: `,xy` runs the xy mapping.
    let e = createEditorForMappings("abc\ndef")
    e.map(EditorMode.Normal, "l a", "G")
    e.map(EditorMode.Normal, "x y", "d d")

    e.press("l", "x", "y")

    check e.activeBuffer.len == 1
    check e.activeBuffer.getLine(0) == "def"

  test "a mapping the held keys complete runs when a later key breaks a longer one":
    # Vim 9.2 with `nmap a …` and `nmap ab …`: `ax` runs the a mapping, then x.
    let e = createEditorForMappings("abc\ndef\nghi")
    e.map(EditorMode.Normal, "a", "G")
    e.map(EditorMode.Normal, "a b", "g g")

    e.press("a", "x")

    check e.state.mode == EditorMode.Normal
    check e.activeBuffer.getLine(2) == "hi"

  test "the timeout runs the mapping the held keys complete, then the rest":
    let e = createEditorForMappings("abc\ndef\nghi")
    e.map(EditorMode.Normal, "a", "G")
    e.map(EditorMode.Normal, "a b c", "g g")

    e.press("a", "b")
    check e.keyRouter.isHoldingKeys

    check e.handleKeyMappingTimeout()

    check not e.keyRouter.isHoldingKeys
    check e.cursor == BufferPosition(line: 1, column: 0)

  test "an Insert mapping can start on the second of two held keys":
    # Vim 9.2 with `inoremap jk <Esc>`: `ijjk` types one j and leaves Insert.
    let e = createEditorForMappings("abc")
    e.map(EditorMode.Insert, "j k", "Esc")

    e.press("i", "j", "j", "k")

    check e.state.mode == EditorMode.Normal
    check e.activeBuffer.getLine(0) == "jabc"

  test "a register a noremap mapping runs is mapped as when typed":
    # Vim 9.2 with `nmap Z …`, @a = Z and `nnoremap ,q @a`: `,q` runs Z's mapping.
    let e = createEditorForMappings("abc\ndef")
    e.state.pendingInput.macroState.registers['a'] = @["Z"]
    e.map(EditorMode.Normal, "Z", "d d")
    e.map(EditorMode.Normal, "Q", "@ a")

    e.press("Q")

    check e.activeBuffer.len == 1
    check e.activeBuffer.getLine(0) == "def"

  test "a register run after a held key is mapped as when typed":
    # Vim 9.2 with `nmap @x …`, `nmap Z …` and @a = Z: `@a` runs Z's mapping.
    let e = createEditorForMappings("abc\ndef")
    e.state.pendingInput.macroState.registers['a'] = @["Z"]
    e.map(EditorMode.Normal, "@ x", "G")
    e.map(EditorMode.Normal, "Z", "d d")

    e.press("@", "a")

    check e.activeBuffer.len == 1
    check e.activeBuffer.getLine(0) == "def"

  test "the keys after an Enter in a command-line mapping reach Normal mode":
    # Vim 9.2 with `cnoremap ,, call …<CR>x`: the x deletes a character.
    let e = createEditorForMappings("abc")
    e.map(EditorMode.Command, "Q", "n o h Enter x")

    e.press(":", "Q")

    check not e.state.hasOverlay
    check e.activeBuffer.getLine(0) == "bc"

  test "a :cmap right-hand side is mapped again, a :cnoremap one is not":
    # Vim 9.2 with `cmap W …`: `cmap Q W` runs W's mapping, `cnoremap Q W` types W.
    let mapped = createEditorForMappings("abc")
    mapped.map(EditorMode.Command, "Q", "W", noremap = false)
    mapped.map(EditorMode.Command, "W", "n o h")
    mapped.press(":", "Q")
    check mapped.state.input.commandText == ":noh"

    let typed = createEditorForMappings("abc")
    typed.map(EditorMode.Command, "Q", "W")
    typed.map(EditorMode.Command, "W", "n o h")
    typed.press(":", "Q")
    check typed.state.input.commandText == ":W"

  test "a recursive :cmap stops the keys after it":
    # Vim 9.2 with `cmap a bx` and `cmap b a`: `:a` gives E223 and types no x.
    let e = createEditorForMappings("abc")
    e.map(EditorMode.Command, "a", "b x", noremap = false)
    e.map(EditorMode.Command, "b", "a", noremap = false)

    e.press(":", "a")

    check "recursive mapping" in e.state.statusMessage
    check e.state.isCommandOverlay
    check e.state.input.commandText == ":"
    check e.keyRouter.mapExpandDepth == 0

  test "a command line that fails in a mapping stops the keys after it":
    # Vim 9.2 with `nmap Q :badcmd<CR>x` or `cmap Q badcmd<CR>x`: E492, no x.
    let normal = createEditorForMappings("abc")
    normal.map(EditorMode.Normal, "Q", ": b a d Enter x")
    normal.press("Q")
    check "Not an editor command" in normal.state.statusMessage
    check normal.activeBuffer.getLine(0) == "abc"

    let command = createEditorForMappings("abc")
    command.map(EditorMode.Command, "Q", "b a d Enter x")
    command.press(":", "Q")
    check "Not an editor command" in command.state.statusMessage
    check command.activeBuffer.getLine(0) == "abc"

  test "a command line @: repeats that fails stops the keys after it":
    # Vim 9.2 with `nmap X @:j` after `:badcmd`: E492, no j.
    let e = createEditorForMappings("one\ntwo")
    e.map(EditorMode.Normal, "X", "@ : j")
    e.press(":", "b", "a", "d", "Enter")

    e.press("X")

    check "Not an editor command" in e.state.statusMessage
    check e.cursor.line == 0

  test "the character after f is not mapped":
    # Vim 9.2 with `nnoremap l …`: `fl` finds the l.
    let e = createEditorForMappings("hello")
    e.map(EditorMode.Normal, "l", "d d")

    e.press("f", "l")

    check e.cursor == BufferPosition(line: 0, column: 2)
    check e.activeBuffer.getLine(0) == "hello"

  test "the register after q is not mapped":
    # Vim 9.2 with `nnoremap a …`: `qaxq` records x into a.
    let e = createEditorForMappings("hello")
    e.map(EditorMode.Normal, "a", "j j")

    e.press("q", "a", "x", "q")

    check e.state.pendingInput.macroState.registers.getOrDefault('a') == @["x"]
    check 'j' notin e.state.pendingInput.macroState.registers

  test "the register after @ is not mapped":
    # Vim 9.2 with `nnoremap a …` and @a = x: `@a` deletes a character.
    let e = createEditorForMappings("hello")
    e.state.pendingInput.macroState.registers['a'] = @["x"]
    e.map(EditorMode.Normal, "a", "d d")

    e.press("@", "a")

    check e.activeBuffer.getLine(0) == "ello"

  test "a held key that begins a built-in sequence takes the next key at once":
    # Vim 9.2 with `nmap gx …`: `gg` goes to the first line.
    let e = createEditorForMappings("abc\ndef\nghi")
    e.map(EditorMode.Normal, "g x", "d d")

    e.press("G", "g", "g")

    check not e.keyRouter.isHoldingKeys
    check e.cursor.line == 0
    check e.activeBuffer.len == 3

  test "the second key of a built-in sequence is not mapped":
    # Vim 9.2 with `nnoremap _ dd`: `g_` goes to the last non-blank.
    let e = createEditorForMappings("abc  ")
    e.map(EditorMode.Normal, "_", "d d")

    e.press("g", "_")

    check e.cursor == BufferPosition(line: 0, column: 2)
    check e.activeBuffer.getLine(0) == "abc  "

  test "the key after Ctrl-w is not mapped":
    # Vim 9.2 with `nnoremap j dd`: `<C-w>j` goes to the window below.
    let e = createEditorForMappings("abc\ndef")
    e.map(EditorMode.Normal, "j", "d d")
    check e.hsplit().isOk
    e.press("C-w", "k")
    let upper = e.windowManager.activeWindowIndex

    e.press("C-w", "j")

    check e.windowManager.activeWindowIndex != upper
    check e.activeBuffer.len == 2

  test "the character of a text object is not mapped":
    # Vim 9.2 with `nnoremap w b`: `diw` deletes the word.
    let e = createEditorForMappings("abc def")
    e.map(EditorMode.Normal, "w", "b")

    e.press("d", "i", "w")

    check e.activeBuffer.getLine(0) == " def"

  test "the first key of a right-hand side that starts with its left-hand side is not mapped again":
    # Vim 9.2 with `nmap a ab`: `a` appends a b.
    let e = createEditorForMappings("abc")
    e.map(EditorMode.Normal, "a", "a b", noremap = false)

    e.press("a")

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.getLine(0) == "abbc"

  test "held keys a mapping starting with its left-hand side holds again go on":
    # Vim 9.2 with `nmap a ab` and `nmap abc G`: `ax` types bx after the a.
    let e = createEditorForMappings("abc")
    e.map(EditorMode.Normal, "a", "a b", noremap = false)
    e.map(EditorMode.Normal, "a b c", "G")

    e.press("a", "x")

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.getLine(0) == "abxbc"

  test "held keys that keep breaking the mapping they start again end as recursive":
    # Vim 9.2 with `nmap a Qb`, `nmap Q a` and `nmap abc G`: `ax` gives E223,
    # then x deletes the a.
    let e = createEditorForMappings("abc")
    e.map(EditorMode.Normal, "a", "Q b", noremap = false)
    e.map(EditorMode.Normal, "Q", "a", noremap = false)
    e.map(EditorMode.Normal, "a b c", "G")

    e.press("a", "x")

    check "recursive mapping" in e.state.statusMessage
    check e.activeBuffer.getLine(0) == "bc"
    check e.keyRouter.mapExpandDepth == 0
    check not e.keyRouter.isHoldingKeys

  test "a typed key held with one that fails still runs":
    # Vim 9.2 with `nmap na G`: `njx` gives E35, then j and x run.
    let e = createEditorForMappings("abc\ndef\nghi")
    e.map(EditorMode.Normal, "n a", "G")

    e.press("n", "j", "x")

    check e.cursor.line == 1
    check e.activeBuffer.getLine(1) == "ef"

  test "a typed key held after a mapping that fails still runs":
    # Vim 9.2 with `nmap a n` and `nmap ab G`: `ajx` gives E35, then j and x run.
    let e = createEditorForMappings("abc\ndef\nghi")
    e.map(EditorMode.Normal, "a", "n")
    e.map(EditorMode.Normal, "a b", "G")

    e.press("a", "j", "x")

    check e.cursor.line == 1
    check e.activeBuffer.getLine(1) == "ef"

  test "a leading command mapping that cannot run here lets its key go unmapped":
    # As when it matches at once: a motion cannot run in a viewer.
    let e = createEditorForMappings("")
    e.state.mode = EditorMode.Filer
    var filerState =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 0, showHidden: false)
    for i in 0 ..< 3:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)
    e.map(EditorMode.Filer, "j", "move-down")
    e.map(EditorMode.Filer, "j k", "window-prev")

    e.press("j", "j")

    check e.activeWindow.modeState.filer.selectedIndex == 1

  proc enterFiler(e: Editor) =
    e.state.mode = EditorMode.Filer
    var filerState =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 0, showHidden: false)
    for i in 0 ..< 3:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)

  test "the keys of a command mapping that cannot run here go on unmapped":
    # As when held keys are let go, the key after the first can start the
    # mapping again. The first was lost before.
    let e = createEditorForMappings("")
    e.enterFiler()
    e.map(EditorMode.Filer, "j j", "move-down")

    e.press("j", "j")

    check e.activeWindow.modeState.filer.selectedIndex == 1
    check e.keyRouter.isHoldingKeys

    check e.handleKeyMappingTimeout()

    check e.activeWindow.modeState.filer.selectedIndex == 2

  test "the timeout lets the keys of a command mapping that cannot run go":
    let e = createEditorForMappings("")
    e.enterFiler()
    e.map(EditorMode.Filer, "j", "move-down")
    e.map(EditorMode.Filer, "j k", "window-prev")

    e.press("j")
    check e.handleKeyMappingTimeout()

    check not e.keyRouter.isHoldingKeys
    check e.activeWindow.modeState.filer.selectedIndex == 1

  test "the keys of a command mapping that cannot run stay in the recording":
    let e = createEditorForMappings("")
    e.press("q", "a")
    e.enterFiler()
    e.map(EditorMode.Filer, "j j", "move-down")

    e.press("j", "j")
    check e.handleKeyMappingTimeout()

    check e.state.pendingInput.macroState.recording.get.keys == @["j", "j"]

  test "a noremap key after a key a register left held lets it go first":
    # Vim 9.2 with `nmap ja dd`, @q = j and `nnoremap Z @qa`: Z runs j, then a.
    let e = createEditorForMappings("one\ntwo\nthree")
    e.state.pendingInput.macroState.registers['q'] = @["j"]
    e.map(EditorMode.Normal, "j a", "d d")
    e.map(EditorMode.Normal, "Z", "@ q a")

    e.press("Z")

    check not e.keyRouter.isHoldingKeys
    check e.state.mode == EditorMode.Insert
    check e.cursor == BufferPosition(line: 1, column: 1)
    check e.activeBuffer.len == 3

  test "keys the timeout lets go can be held again and wait anew":
    # Vim 9.2 with `nmap jkx G` and `nmap kd dd`: after `jk` the j runs at the
    # timeout, and the k one timeout later.
    let e = createEditorForMappings("one\ntwo\nthree")
    e.map(EditorMode.Normal, "j k x", "G")
    e.map(EditorMode.Normal, "k d", "d d")

    e.press("j", "k")
    check e.handleKeyMappingTimeout()

    check e.cursor.line == 1
    check e.keyRouter.isHoldingKeys
    check e.keyRouter.nextTimeoutMs() > 0

    check e.handleKeyMappingTimeout()

    check e.cursor.line == 0
    check not e.keyRouter.isHoldingKeys
    check e.activeBuffer.len == 3

suite "handleKeyCombo - temporary messages, as at Vim's hit-enter prompt":
  proc createEditorWithMessages(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal
    result.state.ui.tempMessages = @["message"]

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  test "Enter, Space and Ctrl-J only dismiss them":
    for key in ["Enter", "Space", "C-j"]:
      let e = createEditorWithMessages("abc\ndef")

      e.press(key)

      check e.state.ui.tempMessages.len == 0
      check e.cursor == BufferPosition(line: 0, column: 0)

  test "Ctrl-C only dismisses them":
    let e = createEditorWithMessages("abc")
    check e.handleInterrupt()

    check e.state.ui.tempMessages.len == 0
    check e.state.statusMessage == ""

  test "another key dismisses them and runs":
    let e = createEditorWithMessages("abc\ndef")

    e.press("j")

    check e.state.ui.tempMessages.len == 0
    check e.cursor == BufferPosition(line: 1, column: 0)

  test "a key that only dismisses them is left out of the recording":
    # Vim 9.2: `qa:echo "a\nb"<CR><CR>q` records the command and its Enter
    # only, as the prompt reads with the recording off. A key it puts back is
    # recorded once it runs.
    let e = createEditorWithMessages("abc")
    e.state.ui.tempMessages = @[]
    e.press("q", "a")
    e.state.ui.tempMessages = @["message"]
    e.press("Enter")
    e.state.ui.tempMessages = @["message"]
    e.press("x", "q")

    check e.state.pendingInput.macroState.registers['a'] == @["x"]
    check e.activeBuffer.getLine(0) == "bc"

  test "`:` goes on to run as any other key":
    # Vim 9.2: `i<C-o>:echo "a\nb"<CR>:x` types `:x`.
    let e = createEditorWithMessages("")
    e.press(":")
    check e.state.isCommandOverlay

    let i = createEditorWithMessages("")
    i.state.ui.tempMessages = @[]
    i.press("i")
    i.state.ui.tempMessages = @["message"]
    i.press(":")

    check i.state.ui.tempMessages.len == 0
    check i.state.mode == EditorMode.Insert
    check not i.state.isCommandOverlay
    check i.activeBuffer.getLine(0) == ":"

  test "the keys after a mapping's command that shows them run":
    # Vim 9.2 with `nnoremap Q :echo "a\nb"<CR>j`: the j runs after hit-enter.
    let e = createEditorWithMessages("abc\ndef\nghi")
    e.state.ui.tempMessages = @[]
    e.press("G", "g", "g")
    check e.keyBindingRegistry.addRuntimeMapping(
      EditorMode.Normal, "Q", ": j u m p Enter j", true
    ).len == 0

    e.press("Q")

    check e.state.ui.tempMessages.len == 0
    check e.cursor == BufferPosition(line: 1, column: 0)

suite "handleKeyCombo - the mappings come before the layers that run a key":
  proc createEditorForLayers(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  proc map(e: Editor, mode: EditorMode, lhs, rhs: string) =
    check e.keyBindingRegistry.addRuntimeMapping(mode, lhs, rhs, true).len == 0

  test "a command-line mapping applies on the search line":
    # Vim 9.2 maps `/` with cmap as it maps `:`.
    let e = createEditorForLayers("abc foo")
    e.map(EditorMode.Command, ",", "f o o")

    e.press("/", ",")

    check e.state.isSearchOverlay
    check e.state.input.search.text == "foo"

  test "the timeout on the search line runs the command-line mapping":
    let e = createEditorForLayers("abc")
    e.map(EditorMode.Command, "j", "a b")
    e.map(EditorMode.Command, "j k", "y z")

    e.press("/", "j")
    check e.keyRouter.isHoldingKeys
    check e.handleKeyMappingTimeout()

    check e.state.input.search.text == "ab"

  test "a command-line mapping applies on the rename line":
    # As Vim maps input() with cmap.
    let e = createEditorForLayers("abc")
    e.state.enterRenameOverlay("abc", 0, 0)
    e.map(EditorMode.Command, ",", "x y")

    e.press(",")

    check e.state.isRenameOverlay
    check e.state.renameState.text == "abcxy"

  test "the Recent File mode's mappings apply":
    let e = createEditorForLayers("")
    e.enterRecentFileWith(@["/a", "/b", "/c"])
    e.map(EditorMode.RecentFile, "x", "j")

    e.press("x")

    check e.activeWindow.modeState.recentFile.selectedIndex == 1

  test "a viewer's mapping can start with Ctrl-W":
    let e = createEditorForLayers("")
    e.state.mode = EditorMode.Filer
    var filerState =
      FilerState(currentPath: "/tmp", entries: @[], selectedIndex: 0, showHidden: false)
    for i in 0 ..< 3:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)
    e.map(EditorMode.Filer, "C-w x", "j")

    e.press("C-w", "x")

    check e.state.pendingInput.pendingCommand == PendingNone
    check e.activeWindow.modeState.filer.selectedIndex == 1

  test "a key held for a mapping is let go before a prompt reads the next":
    # The held key meets the temporary messages first, as Vim's hit-enter
    # prompt reads the typeahead in order, and the Enter then runs.
    let e = createEditorForLayers("abc\ndef")
    e.map(EditorMode.Normal, ", x", "d d")

    e.press(",")
    check e.keyRouter.isHoldingKeys
    e.state.ui.tempMessages = @["message"]

    e.press("Enter")

    check not e.keyRouter.isHoldingKeys
    check e.state.ui.tempMessages.len == 0
    check e.cursor.line == 1

  test "Ctrl-C drops the keys held for a mapping":
    # Vim flushes the typeahead on an interrupt, so a key held on the search
    # line does not run later in Normal mode.
    let e = createEditorForLayers("abc\ndef")
    e.map(EditorMode.Command, "j k", "Escape")

    e.press("/", "j")
    check e.keyRouter.isHoldingKeys

    check e.handleInterrupt()
    check not e.keyRouter.isHoldingKeys
    check not e.state.isSearchOverlay

    check e.handleKeyMappingTimeout()
    check e.cursor.line == 0

  test "a paste goes after the keys held for a mapping":
    # Vim 9.2 with `inoremap jk <Esc>`: j then a paste of foo types jfoo.
    let e = createEditorForLayers("")
    e.map(EditorMode.Insert, "j k", "Escape")

    e.press("i", "j")
    check e.keyRouter.isHoldingKeys
    check e.handlePaste("foo")

    check not e.keyRouter.isHoldingKeys
    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.getLine(0) == "jfoo"

  test "a paste on the search line goes after the keys held for a mapping":
    let e = createEditorForLayers("abc")
    e.map(EditorMode.Command, "j k", "Escape")

    e.press("/", "j")
    check e.handlePaste("foo")

    check e.state.input.search.text == "jfoo"

  test "a paste lets go of every key held for a mapping first":
    # A key let go can be held again as the start of another mapping. Vim
    # with `inoremap abc Z` and `inoremap bd W`: a, b, then a paste of foo
    # types abfoo.
    let e = createEditorForLayers("")
    e.map(EditorMode.Insert, "a b c", "Z")
    e.map(EditorMode.Insert, "b d", "W")

    e.press("i", "a", "b")
    check e.handlePaste("foo")

    check not e.keyRouter.isHoldingKeys
    check e.activeBuffer.getLine(0) == "abfoo"

  proc plainLayout(e: Editor) =
    e.config.standard.mouse = true
    e.state.showTabLine = false
    e.state.showLineNumbers = false
    e.state.showSidebar = false

  test "a click lets go of the keys held for a mapping first":
    let e = createEditorForLayers("abc\ndef")
    e.plainLayout()
    e.map(EditorMode.Insert, "j k", "Escape")

    e.press("i", "j")
    check e.handlePointerInput(initPointerInput(1, 0))

    check not e.keyRouter.isHoldingKeys
    check e.activeBuffer.getLine(0) == "jabc"
    check e.cursor.line == 1

  test "a scroll lets go of the keys held for a mapping first":
    let e = createEditorForLayers("abc\ndef")
    e.plainLayout()
    e.map(EditorMode.Insert, "j k", "Escape")

    e.press("i", "j")
    discard e.handleScrollInput(initScrollInput(0, 0, 1))

    check not e.keyRouter.isHoldingKeys
    check e.activeBuffer.getLine(0) == "jabc"

  test "a middle-click paste lets go of the keys held for a mapping first":
    when defined(posix):
      let fakeDir = installFakeClipboardTool("XY")
      defer:
        removeFakeClipboardTool(fakeDir)
      let e = createEditorForLayers("abc\ndef")
      e.plainLayout()
      e.config.clipboard.enable = true
      e.config.clipboard.tool = cbtXclip
      e.map(EditorMode.Insert, "j k", "Escape")

      e.press("i", "j")
      check e.handleEvent(makeMiddleClickEvent(0, 1))

      # Insert mode pastes at the cursor, after the j let go.
      check not e.keyRouter.isHoldingKeys
      check e.activeBuffer.getLine(0) == "jXYabc"

suite "handleKeyCombo - the register named for a command, as Vim's regname":
  # Vim drops the register after a command that neither starts nor finishes an
  # operator (normal_cmd). Expectations are Vim 9.2's.
  proc createEditorForRegisters(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  proc register(e: Editor, name: char): string =
    e.state.registers.getRegisterContent(name)

  test "a motion drops it":
    let e = createEditorForRegisters("abc\ndef")

    e.press("\"", "a", "j", "x")

    check e.register('a') == ""
    check e.register('"') == "d"

  test "a text object that fails drops it":
    let e = createEditorForRegisters("abc def")

    e.press("\"", "b", "c", "i", "q", "x")

    check e.register('b') == ""
    check e.register('"') == "a"
    check e.activeBuffer.getLine(0) == "bc def"

  test "a special key that ends a text object is used up and drops it":
    let e = createEditorForRegisters("abc def")
    e.press("l", "l", "l")

    e.press("\"", "b", "d", "i", "Left", "x")

    check e.register('b') == ""
    check e.register('"') == " "
    check e.activeBuffer.getLine(0) == "abcdef"

  test "stopping a recording drops it":
    let e = createEditorForRegisters("abcdef")

    e.press("q", "a", "x", "\"", "a", "q", "x")

    check e.state.pendingInput.macroState.registers['a'] == @["x", "\"", "a"]
    check e.register('a') == ""
    check e.register('"') == "b"

  test "entering Visual drops it":
    let e = createEditorForRegisters("abc")

    e.press("\"", "a", "v", "l", "y")

    check e.register('a') == ""
    check e.register('"') == "ab"

  test "Visual mode names a register as Normal mode does":
    let e = createEditorForRegisters("abc")

    e.press("v", "l", "\"", "a", "y")

    check e.register('a') == "ab"

  test "naming it again keeps it":
    let e = createEditorForRegisters("abc")

    e.press("\"", "a", "\"", "a", "x")

    check e.register('a') == "a"

  test "a count keeps it":
    let e = createEditorForRegisters("abcd")

    e.press("\"", "a", "3", "x")

    check e.register('a') == "abc"

  test "a macro the command runs meets no register":
    let e = createEditorForRegisters("abc")
    e.state.pendingInput.macroState.registers['q'] = @["x"]

    e.press("\"", "a", "@", "q")

    check e.register('a') == ""
    check e.register('"') == "a"

  test "Insert resumes after a Ctrl-o command that drops it":
    let e = createEditorForRegisters("abc\nxyz")

    e.press("i", "C-o", "\"", "a", "j", "x")

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.getLine(1) == "xxyz"
    check e.register('a') == ""

  test "a special key that ends a Visual text object is used up":
    let e = createEditorForRegisters("abc def")
    e.press("l", "l", "l")

    e.press("v", "i", "Left")

    check e.state.mode == EditorMode.Visual
    check e.cursor.column == 3

  test "a count before it carries over to the command":
    let e = createEditorForRegisters("abcdef")

    e.press("3", "\"", "a", "x")

    check e.register('a') == "abc"
    check e.activeBuffer.getLine(0) == "def"

  test "a count before it multiplies the count after it":
    let e = createEditorForRegisters("abcdefghij")

    e.press("3", "\"", "a", "2", "x")

    check e.register('a') == "abcdef"

  test "naming another register keeps the counts":
    let e = createEditorForRegisters("abcdefghij")

    e.press("\"", "a", "2", "\"", "b", "3", "x")

    check e.register('a') == ""
    check e.register('b') == "abcdef"

  test "a count before it reaches the operator":
    let e = createEditorForRegisters("a b c d e f g h")

    e.press("3", "\"", "a", "d", "2", "w")

    check e.register('a') == "a b c d e f "
    check e.activeBuffer.getLine(0) == "g h"

  test "a special key as the name drops the one named before":
    let e = createEditorForRegisters("abcdef")
    e.press("l", "l")

    e.press("\"", "a", "\"", "Left")
    check e.cursor.column == 2

    e.press("x")
    check e.register('a') == ""
    check e.register('"') == "c"

  test "an invalid name drops the one named before":
    let e = createEditorForRegisters("abcdef")

    e.press("\"", "a", "\"", "!")
    check e.state.statusMessage == "Invalid register"

    e.press("x")
    check e.register('a') == ""
    check e.register('"') == "a"

  test "a key with no binding drops it and the count":
    let e = createEditorForRegisters("abcdef")

    e.press("\"", "a", "F5", "x")
    check e.register('a') == ""
    check e.register('"') == "a"

    e.press("3", "F5", "x")
    check e.activeBuffer.getLine(0) == "cdef"

  test "a key with no binding in Visual drops it and the count":
    let e = createEditorForRegisters("abcdef")

    e.press("v", "l", "\"", "a", "F5", "y")
    check e.register('a') == ""
    check e.register('"') == "ab"

    e.press("v", "l", "3", "F5", "l")
    check e.cursor.column == 2

  test "a Visual binding that VisualLine falls back to runs with it":
    let e = createEditorForRegisters("abc\ndef")
    e.keyBindingRegistry.bindKey(EditorMode.Visual, "Z", "visual-yank")

    e.press("V", "\"", "a", "Z")

    check e.state.registers.isRegisterLinewise('a')
    check e.state.registers.getRegister('a').buffer[0] == "abc"

  test "a special key as an operand cancels the operator":
    let e = createEditorForRegisters("abc def")

    e.press("d", "f", "Left", "w")

    check e.activeBuffer.getLine(0) == "abc def"
    check e.cursor.column == 4

  test "naming one while an operator waits cancels the operator":
    let e = createEditorForRegisters("abc def")

    e.press("d", "\"", "a", "w")

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.getLine(0) == "awbc def"
    check e.register('a') == ""

  test "Escape or Ctrl-c after it or a count leaves Visual":
    for key in ["Escape", "C-c"]:
      for prefix in [@["\"", "a"], @["3"]]:
        let e = createEditorForRegisters("abc")

        e.press("v")
        e.press(prefix)
        e.press(key)
        check e.state.mode == EditorMode.Normal

        e.press("y", "l")
        check e.register('a') == ""
        check e.register('"') == "a"

  test "Escape that ends a register name or a sequence stays in Visual":
    for keys in [@["\""], @["\"", "a", "\""], @["g"]]:
      let e = createEditorForRegisters("abc")

      e.press("v")
      e.press(keys)
      e.press("Escape")

      check e.state.mode == EditorMode.Visual

  test "Escape and Ctrl-c that end a Visual text object stay in Visual":
    for key in ["Escape", "C-c"]:
      let e = createEditorForRegisters("abc def")
      e.press("l")

      e.press("v", "i", key)

      check e.state.mode == EditorMode.Visual

  test "a mapping after it runs with it":
    let e = createEditorForRegisters("abc\ndef")
    let error = e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "X", "d d")
    check error.len == 0

    e.press("\"", "a", "X")

    check e.state.registers.isRegisterLinewise('a')
    check e.state.registers.getRegister('a').buffer[0] == "abc"
    check e.activeBuffer.getLine(0) == "def"

  test "Insert waits for the command after it from Ctrl-o":
    let e = createEditorForRegisters("abcdef")
    check e.state.registers.setRegister('a', "XY", false).isOk
    e.state.registers.storeYanked(none(char), "Q", false)

    e.press("i", "C-o", "\"", "a", "p")

    check e.state.mode == EditorMode.Insert
    check e.activeBuffer.getLine(0) == "aXYbcdef"

  test "a command a mapping names takes it":
    let e = createEditorForRegisters("abc\ndef\nghi")
    let error =
      e.keyBindingRegistry.addRuntimeMapping(EditorMode.Normal, "F2", "move-down")
    check error.len == 0

    e.press("\"", "a", "F2", "d", "d")

    check e.register('a') == ""
    check e.state.registers.getRegister('"').buffer[0] == "def"

  test "gn yanks the match into the yank register":
    let e = createEditorForRegisters("foo bar foo")
    e.state.input.search.last.pattern = "bar"

    e.press("y", "g", "n")

    check e.register('0') == "bar"
    check e.register('"') == "bar"
    check e.register('-') == ""

  test "gn takes the register named for the operator":
    for op in ["y", "d"]:
      let e = createEditorForRegisters("foo bar foo")
      e.state.input.search.last.pattern = "bar"

      e.press("\"", "a", op, "g", "n")

      check e.register('a') == "bar"
      check e.register('-') == ""
      check e.register('0') == ""

  test "the black hole register keeps nothing":
    for keys in [
      @["\"", "_", "d", "d"],
      @["\"", "_", "x"],
      @["\"", "_", "y", "y"],
      @["\"", "_", "c", "w", "Escape"],
      @["v", "\"", "_", "d"],
      @["v", "\"", "_", "y"],
    ]:
      let e = createEditorForRegisters("abc def\nghi")
      e.state.registers.storeYanked(none(char), "Q", false)

      e.press(keys)

      check e.register('"') == "Q"
      check e.register('0') == "Q"
      check e.register('1') == ""
      check e.register('-') == ""

  test "putting the black hole register puts nothing":
    let fakeDir = installFakeClipboardTool(fakeClipboardContent)
    if fakeDir.len == 0:
      skip()
    else:
      try:
        for (keys, line) in [
          (@["\"", "_", "p"], "abc"),
          (@["\"", "_", "P"], "abc"),
          (@["v", "\"", "_", "p"], "bc"),
        ]:
          let e = createEditorForRegisters("abc")
          # An empty register falls back to the system clipboard; this one
          # reads nothing.
          e.state.config.clipboard = ClipboardConfig(enable: true, tool: cbtXclip)
          e.state.registers.setClipboardTool(cbtXclip)

          e.press(keys)

          check e.activeBuffer.getLine(0) == line
      finally:
        removeFakeClipboardTool(fakeDir)

  test "putting nothing over a selection still deletes it":
    # The black hole register puts an empty string, a blank line over whole
    # lines; an empty register puts nothing and says so.
    for (keys, lines, message) in [
      (@["v", "i", "w", "\"", "_", "p"], @[" def", "ghi"], ""),
      (@["V", "\"", "_", "p"], @["", "ghi"], ""),
      (
        @["v", "i", "w", "\"", "b", "p"],
        @[" def", "ghi"],
        "E353: Nothing in register b",
      ),
      (@["V", "\"", "b", "p"], @["ghi"], "E353: Nothing in register b"),
    ]:
      let e = createEditorForRegisters("abc def\nghi")
      e.state.config.clipboard = ClipboardConfig(enable: false, tool: cbtXclip)

      e.press(keys)

      check e.activeBuffer.len == lines.len
      for i, line in lines:
        check e.activeBuffer.getLine(i) == line
      check e.register('"') == (if keys[0] == "V": "abc def\n" else: "abc")
      check e.state.registers.isRegisterLinewise('"') == (keys[0] == "V")
      check e.state.statusMessage.contains(message)
      check e.state.mode == EditorMode.Normal

  test "`.` puts the change in the register it used again":
    for (keys, name, content) in [
      (@["\"", "a", "d", "d", "."], 'a', "four five six\n"),
      (@["\"", "a", "d", "d", "\"", "b", "."], 'a', "four five six\n"),
      (@["\"", "a", "x", "."], 'a', "n"),
      (@["\"", "A", "x", "."], 'a', "on"),
      (@["\"", "a", "d", "w", "."], 'a', "two "),
      (@["d", "d", "\"", "b", "."], 'b', "four five six\n"),
    ]:
      let e = createEditorForRegisters("one two three\nfour five six\nseven")

      e.press(keys)

      check e.register(name) == content
      if name == 'a':
        check e.register('b') == ""

  test "`.` after the black hole register keeps nothing again":
    for (keys, line) in [
      (@["\"", "_", "d", "d", "."], "seven"), (@["\"", "_", "x", "."], "e two three")
    ]:
      let e = createEditorForRegisters("one two three\nfour five six\nseven")
      e.state.registers.storeYanked(none(char), "Q", false)

      e.press(keys)

      check e.activeBuffer.getLine(0) == line
      check e.register('"') == "Q"
      check e.register('0') == "Q"
      check e.register('1') == ""
      check e.register('-') == ""

  test "`.` puts from the register the put used, a numbered one counting up":
    let e = createEditorForRegisters("one two three\nfour")
    for (name, content) in [('1', "R1\n"), ('2', "R2\n"), ('3', "R3\n")]:
      check e.state.registers.setRegister(name, content, true).isOk
    check e.state.registers.setRegister('a', "A", false).isOk
    check e.state.registers.setRegister('b', "B", false).isOk

    e.press("\"", "1", "p", ".", ".")

    check e.activeBuffer.getLine(1) == "R1"
    check e.activeBuffer.getLine(2) == "R2"
    check e.activeBuffer.getLine(3) == "R3"

    e.press("g", "g", "0", "\"", "a", "p", "\"", "b", ".")

    check e.activeBuffer.getLine(0) == "oAAne two three"

suite "handleKeyCombo - a command an operator cannot act over cancels it, as Vim's checkclearop":
  # Expectations are Vim 9.2's.
  proc createEditorForOperators(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  proc lines(e: Editor): seq[string] =
    for i in 0 ..< e.activeBuffer.len:
      result.add e.activeBuffer.getLine(i)

  test "a command that is no motion does not run, and the motion after it moves":
    for keys in [@["x"], @["J"], @["~"], @["p"], @["C-a"], @["z", "z"]]:
      let e = createEditorForOperators("abc def\nghi")
      e.state.registers.storeYanked(none(char), "Q", false)

      e.press("d")
      e.press(keys)
      e.press("w")

      check e.activeBuffer.getLine(0) == "abc def"
      check e.activeBuffer.getLine(1) == "ghi"
      check e.cursor.column == 4
      check e.state.pendingInput.pendingOperator.isNone

  test "a command that enters another mode does not run":
    for key in ["I", "A", "o", "R"]:
      let e = createEditorForOperators("abc def")

      e.press("d", key)
      check e.state.mode == EditorMode.Normal

      e.press("w")
      check e.activeBuffer.getLine(0) == "abc def"
      check e.cursor.column == 4

  test "v and V cancel it too":
    # Vim forces the motion's kind with them (`dVw`); moe has no forced
    # motion, so they cancel the operator as other commands do.
    for key in ["v", "V"]:
      let e = createEditorForOperators("abc def")

      e.press("d", key)
      check e.state.mode == EditorMode.Normal
      check e.state.pendingInput.pendingOperator.isNone

  test "the register named after it goes to the next command":
    let e = createEditorForOperators("abc def")
    check e.state.registers.setRegister('a', "XY", false).isOk

    e.press("d", "I", "\"", "a", "p")

    check e.activeBuffer.getLine(0) == "aXYbc def"

  test "a command that waits for a key takes none":
    for key in ["r", "m", "@", "q"]:
      let e = createEditorForOperators("abc def")

      e.press("d", key, "x")

      check e.activeBuffer.getLine(0) == "bc def"
      check e.state.pendingInput.macroState.isRecording == false

  test "the search line opens without it":
    let e = createEditorForOperators("abc def ghi")

    e.press("d", "/", "d", "e", "f", "Enter", "w")

    check e.activeBuffer.getLine(0) == "abc def ghi"
    check e.cursor.column == 8

  test "a motion, a text object, a mark and the operator again end it":
    for (keys, line) in [
      (@["d", "w"], "def ghi"),
      (@["d", "f", "e"], "f ghi"),
      (@["d", "i", "w"], " def ghi"),
      (@["d", "`", "a"], "def ghi"),
      (@["d", "d"], ""),
    ]:
      let e = createEditorForOperators("abc def ghi")
      e.activeBuffer.namedMarks['a'] = some(BufferPosition(line: 0, column: 4))

      e.press(keys)

      check e.activeBuffer.getLine(0) == line

  test "an operator of another kind cancels it, and the motion after it moves":
    for keys in [
      @["d", "y"], @["y", "d"], @["d", ">"], @["c", "d"], @["g", "u", "g", "U"]
    ]:
      let e = createEditorForOperators("abc def\nghi")
      e.state.registers.storeYanked(none(char), "Q", false)

      e.press(keys)
      check e.state.pendingInput.pendingOperator.isNone
      e.press("w")

      check e.activeBuffer.getLine(0) == "abc def"
      check e.cursor.column == 4
      check e.state.registers.getRegisterContent('"') == "Q"

  test "the register named for an operator another cancels goes with it":
    let e = createEditorForOperators("abc def")

    e.press("\"", "a", "d", "y", "x")

    check e.state.registers.getRegisterContent('a') == ""
    check e.state.registers.getRegisterContent('"') == "a"
    check e.activeBuffer.getLine(0) == "bc def"

  test "a scroll does not run under it":
    var text = ""
    for i in 1 .. 100:
      if i > 1:
        text.add '\n'
      text.add "line " & $i
    for key in ["C-d", "C-f", "C-u", "C-b", "PageDown", "PageUp"]:
      let e = createEditorForOperators(text)
      e.press("5", "0", "G")

      e.press("d", key)

      check e.activeBuffer.len == 100
      check e.cursor.line == 49
      check e.state.pendingInput.pendingOperator.isNone

  test "a search acts as a motion that stops short of the match":
    # Exclusive: one that ends at a line start stops at the end of the line
    # before, and takes whole lines when it starts in the indent.
    for (pattern, start, keys, lines, deleted) in [
      (
        "five",
        (0, 0),
        @["d", "n"],
        @["five six", "seven", "eight", "nine"],
        "one two three\nfour ",
      ),
      (
        "two",
        (2, 0),
        @["d", "N"],
        @["one ", "seven", "eight", "nine"],
        "two three\nfour five six",
      ),
      (
        "e",
        (0, 0),
        @["2", "d", "n"],
        @["ee", "four five six", "seven", "eight", "nine"],
        "one two thr",
      ),
      (
        "^seven",
        (1, 0),
        @["d", "n"],
        @["one two three", "seven", "eight", "nine"],
        "four five six\n",
      ),
      (
        "one",
        (1, 0),
        @["d", "n"],
        @["four five six", "seven", "eight", "nine"],
        "one two three\n",
      ),
    ]:
      let e =
        createEditorForOperators("one two three\nfour five six\nseven\neight\nnine")
      e.state.input.search.last.pattern = pattern
      e.activeWindow.cursor = BufferPosition(line: start[0], column: start[1])

      e.press(keys)

      check e.lines == lines
      check e.state.registers.getRegisterContent('"') == deleted
      check e.state.pendingInput.pendingOperator.isNone

  test "yanking or changing up to a search":
    let e = createEditorForOperators("one two three\nfour five six")
    e.state.input.search.last.pattern = "five"

    e.press("y", "n")

    check e.state.registers.getRegisterContent('0') == "one two three\nfour "
    check e.lines == @["one two three", "four five six"]
    check e.cursor == BufferPosition(line: 0, column: 0)

    e.press("c", "n", "X", "Escape")

    check e.lines == @["Xfive six"]

  test "searching for the word under the cursor acts as a motion":
    for (start, key) in [((0, 0), "*"), ((1, 4), "#")]:
      let e = createEditorForOperators("foo bar\nbaz foo qux")
      e.activeWindow.cursor = BufferPosition(line: start[0], column: start[1])

      e.press("d", key)

      check e.lines == @["foo qux"]
      check e.cursor == BufferPosition(line: 0, column: 0)

  test "a counted search for the word under the cursor may wrap back to it":
    # Vim 9.2: `2d*` on `foo bar foo` stops at the word under the cursor again
    for (start, key, lines) in [
      (0, "*", @["foo bar foo"]), (1, "*", @["oo bar foo"]), (8, "#", @["foo bar foo"])
    ]:
      let e = createEditorForOperators("foo bar foo")
      e.activeWindow.cursor = BufferPosition(line: 0, column: start)

      e.press("2", "d", key)

      check e.lines == lines
      check e.state.pendingInput.pendingOperator.isNone

  test "a counted search for the word under the cursor passes matches":
    let e = createEditorForOperators("foo bar foo baz foo")

    e.press("2", "d", "*")

    check e.lines == @["foo"]

  test "a search that finds no other match ends it with no change":
    for (pattern, start) in [("zzz", (0, 0)), ("five", (1, 5))]:
      let e = createEditorForOperators("one two three\nfour five six")
      e.state.input.search.last.pattern = pattern
      e.activeWindow.cursor = BufferPosition(line: start[0], column: start[1])

      e.press("d", "n")

      check e.lines == @["one two three", "four five six"]
      check e.state.pendingInput.pendingOperator.isNone

  test "`.` searches again from where it is":
    let e = createEditorForOperators("one two three\nfour")
    e.state.input.search.last.pattern = "e"

    e.press("d", "n", ".")

    check e.lines == @["ee", "four"]

suite "handleKeyCombo - an operator acts over what a motion finds, as Vim's do_pending_operator":
  # Expectations are Vim 9.2's.
  proc createEditorForOperators(content: string, line = 0, column = 0): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal
    result.activeWindow.cursor = BufferPosition(line: line, column: column)

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  proc lines(e: Editor): seq[string] =
    for i in 0 ..< e.activeBuffer.len:
      result.add e.activeBuffer.getLine(i)

  const SevenLines = "a\nb\nc\nd\ne\nf\ng"

  test "a count after the operator multiplies into lines of its own kind":
    for (keys, lines) in [
      (@["d", "3", "d"], @["d", "e", "f", "g"]),
      (@["2", "d", "3", "d"], @["g"]),
      (@["c", "2", "c", "X", "Escape"], @["X", "c", "d", "e", "f", "g"]),
      (@[">", "2", ">"], @["\ta", "\tb", "c", "d", "e", "f", "g"]),
    ]:
      let e = createEditorForOperators(SevenLines)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines
      check e.state.pendingInput.pendingOperator.isNone

    let e = createEditorForOperators(SevenLines)
    e.press("y", "3", "y")
    check e.state.registers.getRegisterContent('0') == "a\nb\nc\n"

  test "a count after the operator reaches a text object, a search and gn":
    for (content, column, search, keys, lines) in [
      ("foo bar baz qux", 0, "", @["d", "2", "i", "w"], @["bar baz qux"]),
      ("foo bar baz qux", 0, "", @["2", "d", "i", "w"], @["bar baz qux"]),
      ("foo bar baz qux", 0, "", @["d", "2", "a", "w"], @["baz qux"]),
      ("x\nfoo\nx\nfoo\nx", 0, "foo", @["d", "2", "n"], @["foo", "x"]),
      ("foo x foo x foo", 2, "foo", @["d", "2", "g", "n"], @["foo x  x foo"]),
    ]:
      let e = createEditorForOperators(content, column = column)
      e.state.input.search.last.pattern = search

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines

  test "a count before the operator makes G a line number":
    for (line, keys, lines) in [
      (1, @["3", "d", "G"], @["a", "d", "e", "f", "g"]),
      (0, @["d", "3", "G"], @["d", "e", "f", "g"]),
      (5, @["d", "G"], @["a", "b", "c", "d", "e"]),
    ]:
      let e = createEditorForOperators(SevenLines, line = line)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines

  test "an exclusive motion that ends at a line start stops at the line before":
    # And takes whole lines when it starts in the indent (`:h exclusive`)
    for (content, line, column, keys, lines) in [
      ("a\nb\n\nc", 0, 0, @["d", "}"], @["", "c"]),
      ("abc\nd\n\ne", 0, 1, @["d", "}"], @["a", "", "e"]),
      ("a\n\nb\nc", 3, 0, @["d", "{"], @["a", "c"]),
      ("  a\nb\nc", 0, 0, @["d", "`", "a"], @["c"]),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)
      e.activeBuffer.namedMarks['a'] = some(BufferPosition(line: 2, column: 0))

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines

  test "each motion keeps its own kind":
    for (content, line, column, keys, lines) in [
      ("a1\nb2\nc3", 0, 1, @["d", "L"], @[""]),
      ("a1\nb2\nc3", 2, 1, @["d", "H"], @[""]),
      ("a\nb\nc", 0, 0, @["d", "H"], @["b", "c"]),
      ("axbxcx", 0, 4, @["d", "F", "x"], @["axbcx"]),
      ("axbxcx", 0, 4, @["d", "T", "x"], @["axbxcx"]),
      ("a\nb\nc", 0, 0, @["d", "g", "g"], @["b", "c"]),
      ("a\nb\nc", 2, 0, @["d", "G"], @["a", "b"]),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines

  test "a motion that cannot move does nothing, one that moves nowhere acts over nothing":
    for (content, line, column, keys, lines) in [
      ("a\nb\nc", 0, 0, @["d", "k"], @["a", "b", "c"]),
      ("a\nb\nc", 2, 0, @["d", "j"], @["a", "b", "c"]),
      ("abc", 0, 0, @["d", "0"], @["abc"]),
      ("abc", 0, 0, @["d", "b"], @["abc"]),
      ("\nb", 0, 0, @["d", "l"], @["", "b"]),
      ("abc", 0, 2, @["d", "l"], @["ab"]),
      ("abc", 0, 1, @["d", "3", "l"], @["a"]),
      # `c` over nothing still inserts
      ("abc", 0, 0, @["c", "0", "X", "Escape"], @["Xabc"]),
      ("abc", 0, 0, @["c", "h", "X", "Escape"], @["Xabc"]),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines

  test "w stops at the end of the line its last word is on":
    for (content, line, column, keys, lines) in [
      ("foo bar\nbaz qux", 0, 4, @["d", "w"], @["foo ", "baz qux"]),
      ("foo bar\nbaz qux", 0, 4, @["d", "2", "w"], @["foo qux"]),
      ("foo   \nbar", 0, 0, @["d", "w"], @["", "bar"]),
      ("  foo\nbar", 0, 2, @["d", "w"], @["  ", "bar"]),
      ("foo\n\nbar", 0, 0, @["d", "2", "w"], @["bar"]),
      ("foo bar\nbaz", 0, 4, @["d", "3", "w"], @["foo "]),
      ("foo\n  bar", 0, 0, @["d", "2", "w"], @[""]),
      ("foo bar", 0, 4, @["d", "w"], @["foo "]),
      ("a\n\nb", 1, 0, @["d", "w"], @["a", "b"]),
      # From the last character of a line, even after only blanks
      ("  x\nfoo", 0, 2, @["d", "w"], @["  ", "foo"]),
      ("x\nfoo", 0, 0, @["d", "w"], @["", "foo"]),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines

  test "cw on a word changes up to its end, as ce":
    for (content, line, column, keys, lines) in [
      ("foo bar baz", 0, 0, @["c", "w"], @["X bar baz"]),
      ("foo bar baz", 0, 2, @["c", "w"], @["foX bar baz"]),
      ("foo  bar baz", 0, 3, @["c", "w"], @["fooXbar baz"]),
      ("foo bar baz", 0, 0, @["c", "2", "w"], @["X baz"]),
      ("foo\nbar", 0, 0, @["c", "w"], @["X", "bar"]),
      ("a\n\nb", 1, 0, @["c", "w"], @["a", "X", "b"]),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)

      e.press(keys)
      e.press("X", "Escape")

      checkpoint($keys)
      check e.lines == lines

  test "} in the last paragraph goes to its last character, which an operator takes":
    for (content, line, column, keys, lines, cursor) in [
      ("a\nb\nc", 0, 0, @["}"], @["a", "b", "c"], (2, 0)),
      ("ab\ncd", 0, 0, @["}"], @["ab", "cd"], (1, 1)),
      ("a\nb\nc", 0, 0, @["d", "}"], @[""], (0, 0)),
      ("foo bar", 0, 4, @["d", "}"], @["foo "], (0, 3)),
      ("ab\ncd", 1, 1, @["d", "}"], @["ab", "c"], (1, 0)),
      # With paragraphs still to go it fails in place
      ("a\n\nb\nc", 2, 0, @["5", "}"], @["a", "", "b", "c"], (2, 0)),
      ("a\n\nb\nc", 2, 0, @["d", "5", "}"], @["a", "", "b", "c"], (2, 0)),
      # An empty line ends a paragraph, a line of blanks does not
      ("a\n  \nb\n\nc", 0, 0, @["}"], @["a", "  ", "b", "", "c"], (3, 0)),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines
      check e.cursor == BufferPosition(line: cursor[0], column: cursor[1])

  test "l with an operator takes nothing on an empty line, and c still inserts":
    let e = createEditorForOperators("a\n\nb", line = 1)

    e.press("c", "l", "X", "Escape")

    check e.lines == @["a", "X", "b"]

  test "an operator over an end on an empty line takes nothing there":
    for keys in [@["d", "$"], @["d", "g", "_"], @["y", "$"]]:
      let e = createEditorForOperators("a\n\nb", line = 1)

      e.press(keys)

      checkpoint($keys)
      check e.lines == @["a", "", "b"]
      check e.state.registers.getRegisterContent('"') == ""

  test "cw past the last word of the buffer stops at its last character":
    let e = createEditorForOperators("foo bar", column = 4)

    e.press("c", "2", "w", "X", "Escape")

    check e.lines == @["foo X"]
    check e.state.registers.getRegisterContent('"') == "bar"

  test "a delete over lines lands on the first non-blank of the line that follows":
    for (content, line, column, keys, lines, cursor) in [
      ("x\ny\n  z", 0, 0, @["d", "j"], @["  z"], (0, 2)),
      ("x\n\n  y\nz", 1, 0, @["d", "w"], @["x", "  y", "z"], (1, 2)),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines
      check e.cursor == BufferPosition(line: cursor[0], column: cursor[1])

  test "a delete over lines that leaves only blanks around takes them whole":
    let e = createEditorForOperators("  x\ny  \nz", column = 2)

    e.press("d", "2", "w")

    check e.lines == @["z"]
    check e.state.registers.getRegisterContent('"') == "  x\ny  \n"

  test "a motion that fails part of the way does nothing but leaves the cursor moved":
    let e = createEditorForOperators("a.b \nx ab}()", column = 1)

    e.press("d", "3", "g", "e")

    check e.lines == @["a.b ", "x ab}()"]
    check e.cursor == BufferPosition(line: 0, column: 0)

  test "a line motion with no line to go to fails":
    let e = createEditorForOperators("ab\ncd", line = 1, column = 1)

    e.press("y", "+")

    check e.state.registers.getRegisterContent('"') == ""
    check e.cursor == BufferPosition(line: 1, column: 1)

  test "; after t steps past the match it stands next to, unless counted":
    let e = createEditorForOperators("a.b.c.d")

    e.press("t", ".", ";")
    check e.cursor == BufferPosition(line: 0, column: 2)

    e.press("2", ";")
    check e.cursor == BufferPosition(line: 0, column: 4)

  test "w goes over lines of blanks to the next word":
    let e = createEditorForOperators("foo{ \n \n ", column = 4)

    e.press("w")

    check e.cursor == BufferPosition(line: 2, column: 0)

  test "a yank over a block ending past a line leaves the cursor on a character":
    let e = createEditorForOperators("fn() {\n  x\n}", line = 1, column = 2)

    e.press("y", "i", "{")

    check e.cursor.column < e.activeBuffer.getLine(e.cursor.line).charLen

  test "a block object takes the block around the cursor, as Vim's current_block":
    for (content, line, column, keys, lines, register) in [
      # A count goes out to the enclosing block; past the last one it fails
      ("f(a(b)c)", 0, 4, @["d", "2", "i", "("], @["f()"], "a(b)c"),
      ("f(a(b)c)", 0, 4, @["d", "3", "i", "("], @["f(a(b)c)"], ""),
      # Outside any block it takes the next one, even on a later line
      ("x (y) z", 0, 0, @["d", "i", "("], @["x () z"], "y"),
      ("x\n(y)", 0, 0, @["d", "i", "("], @["x", "()"], "y"),
      ("f(a)", 0, 0, @["d", "a", "("], @["f"], "(a)"),
      # An escaped bracket does not count
      ("(a \\( b)", 0, 5, @["d", "i", "("], @["()"], "a \\( b"),
      # The indent before a closing bracket that starts its line is left out
      ("fn() {\n  x\n  }", 1, 2, @["d", "i", "{"], @["fn() {", "  }"], "  x\n"),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines
      check e.state.registers.getRegisterContent('"') == register

  test "> leaves empty lines unshifted":
    let e = createEditorForOperators("a\n\nb")

    e.press(">", "2", "j")

    check e.lines == @["\ta", "", "\tb"]

  test "guu and gUU leave a key f, t or a mark waits for to them":
    for (content, keys, lines) in [
      ("FOO BuR uX", @["g", "u", "f", "u"], @["foo buR uX"]),
      ("foo bar Ux", @["g", "U", "t", "U"], @["FOO BAR Ux"]),
      ("FOO\nBAR", @["g", "u", "u"], @["foo", "BAR"]),
      ("FOO\nBAR", @["g", "u", "g", "u"], @["foo", "BAR"]),
      ("FOO\nBAR\nBAZ", @["g", "u", "2", "u"], @["foo", "bar", "BAZ"]),
    ]:
      let e = createEditorForOperators(content)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines
      check e.state.pendingInput.pendingOperator.isNone

  test "`.` repeats an operator over a text object or gn":
    let e = createEditorForOperators("foo bar baz")
    e.press("d", "i", "w", ".")
    check e.lines == @["bar baz"]

    let g = createEditorForOperators("foo x foo x foo")
    g.state.input.search.last.pattern = "foo"
    g.press("d", "g", "n", ".")
    check g.lines == @[" x  x foo"]

  test "gn takes any operator":
    let e = createEditorForOperators("x FOO x")
    e.state.input.search.last.pattern = "FOO"

    e.press("g", "u", "g", "n")

    check e.lines == @["x foo x"]

  test "a refused operator still puts the cursor where the text starts":
    # Vim puts the cursor there before the operator runs, so 'nomodifiable'
    # refusing the change leaves it there.
    for keys in [@["g", "U", "b"], @["g", "U", "i", "w"]]:
      let e = createEditorForOperators("foo bar bazz qux", column = 10)
      e.activeBuffer.keepRaw = true

      e.press(keys)

      checkpoint($keys)
      check e.lines == @["foo bar bazz qux"]
      check e.cursor == BufferPosition(line: 0, column: 8)

  test "a refused operator over gn still makes the match what gv selects":
    # Vim keeps the Visual area gn made before the operator runs.
    let e = createEditorForOperators("x foo x\nbar")
    e.activeBuffer.keepRaw = true
    e.state.input.search.last.pattern = "foo"
    e.press("j", "v", "l", "Esc", "k", "0")

    e.press("g", "U", "g", "n", "g", "v")

    check e.lines == @["x foo x", "bar"]
    check e.state.visualSelection.start == BufferPosition(line: 0, column: 2)
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 4)

  test "gn on a zero-width match takes the character it stands at":
    # At the end of a line that is the line break, as Vim's gn selects it
    let e = createEditorForOperators("foo\nbar", column = 1)
    e.state.input.search.last.pattern = "$"

    e.press("d", "g", "n")

    check e.lines == @["foobar"]

  test "a count before gn in Visual mode selects that match":
    let e = createEditorForOperators("foo x foo x foo")
    e.state.input.search.last.pattern = "foo"

    e.press("2", "g", "n", "d")

    check e.lines == @["foo x  x foo"]

  test "a count past the matches goes round them, and one match is found again":
    for (content, search, keys, lines) in [
      ("foo x foo", "foo", @["d", "9", "9", "9", "9", "9", "9", "g", "n"], @[" x foo"]),
      ("x foo y", "foo", @["d", "9", "9", "9", "9", "9", "9", "n"], @["foo y"]),
      ("x foo y", "foo", @["d", "2", "n"], @["foo y"]),
    ]:
      let e = createEditorForOperators(content)
      e.state.input.search.last.pattern = search

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines

  test "a yank leaves the cursor where the yanked text starts":
    for (content, line, column, keys, cursor) in [
      ("abc def\nghi jkl", 0, 4, @["y", "j"], (0, 4)),
      ("abc def\nghi jkl", 1, 4, @["y", "k"], (0, 4)),
      ("abc def", 0, 5, @["y", "b"], (0, 4)),
      ("abc def", 0, 5, @["y", "i", "w"], (0, 4)),
      ("abc def", 0, 6, @["y", "F", "a"], (0, 0)),
      ("abc\ndef\nghi", 2, 1, @["y", "g", "g"], (0, 0)),
      ("abc def", 0, 1, @["y", "$"], (0, 1)),
    ]:
      let e = createEditorForOperators(content, line = line, column = column)

      e.press(keys)

      checkpoint($keys)
      check e.cursor == BufferPosition(line: cursor[0], column: cursor[1])

    let g = createEditorForOperators("abc def")
    g.state.input.search.last.pattern = "def"
    g.press("y", "g", "n")
    check g.cursor == BufferPosition(line: 0, column: 4)
    check g.state.registers.getRegisterContent('0') == "def"

suite "handleKeyCombo - the registers a yank or delete fills, as Vim's op_yank and op_delete":
  # Expectations are Vim 9.2's, with "1-"3 holding R1-R3 beforehand.
  proc createEditorForRegisters(content: string): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    result.state.autoIndent = false
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal
    for (name, text) in [('1', "R1"), ('2', "R2"), ('3', "R3")]:
      check result.state.registers.setRegister(name, text, false).isOk
    result.state.registers.noNamed = Register()

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  proc lines(e: Editor, name: char): seq[string] =
    e.state.registers.getRegister(name).getLines

  proc linewise(e: Editor, name: char): bool =
    e.state.registers.isRegisterLinewise(name)

  proc buffer(e: Editor): seq[string] =
    for i in 0 ..< e.activeBuffer.len:
      result.add e.activeBuffer.getLine(i)

  test "a yank into a numbered register or - leaves register 0":
    for (keys, name, lines, linewise) in [
      (@["\"", "3", "y", "y"], '3', @["two"], true),
      (@["\"", "9", "y", "y"], '9', @["two"], true),
      (@["\"", "-", "y", "w"], '-', @["two"], false),
      (@["\"", "-", "y", "y"], '-', @["two"], true),
    ]:
      let e = createEditorForRegisters("one\ntwo\nthree")
      e.press("j")

      e.press(keys)

      check e.lines(name) == lines
      check e.linewise(name) == linewise
      check e.lines('"') == lines
      check e.state.registers.getNumberRegister(0).isEmpty

  test "a yank or delete into the unnamed register writes register 0":
    for keys in [@["\"", "\"", "y", "w"], @["\"", "\"", "d", "w"]]:
      let e = createEditorForRegisters("one\ntwo")

      e.press(keys)

      check e.lines('0') == @["one"]
      check e.lines('"') == @["one"]
      check e.state.registers.getSmallDeleteRegister().isEmpty

  test "a delete over lines into a register shifts the numbered ones too":
    for (keys, regs) in [
      (@["\"", "a", "d", "d"], @[('a', "one"), ('1', "one"), ('2', "R1"), ('4', "R3")]),
      (@["\"", "3", "d", "d"], @[('1', "one"), ('2', "R1"), ('3', "R2"), ('4', "one")]),
      (@["\"", "1", "d", "d"], @[('1', "one"), ('2', "one"), ('3', "R2")]),
      (@["\"", "0", "d", "d"], @[('0', "one"), ('1', "one"), ('2', "R1")]),
    ]:
      let e = createEditorForRegisters("one\ntwo")

      e.press(keys)

      for (name, text) in regs:
        check e.lines(name) == @[text]
      check e.lines('"') == @["one"]

  test "a delete within a line into a register leaves 1 and -":
    let e = createEditorForRegisters("one two")

    e.press("\"", "a", "d", "w")

    check e.lines('a') == @["one "]
    check e.lines('1') == @["R1"]
    check e.state.registers.getSmallDeleteRegister().isEmpty

  test "a delete over %, }, `, n or * within a line goes to 1 and -":
    for (content, setup, keys, deleted) in [
      ("(a b) c", newSeq[string](), @["d", "%"], "(a b)"),
      ("a b c\nd", @["l"], @["d", "}"], " b c\nd"),
      ("foo bar", @["f", "b", "m", "a", "0"], @["d", "`", "a"], "foo "),
      ("x foo x foo", @["l", "l", "*", "0"], @["d", "n"], "x "),
      ("x foo x foo", @["l", "l"], @["d", "*"], "foo x "),
    ]:
      let e = createEditorForRegisters(content)
      e.press(setup)

      e.press(keys)

      check e.state.registers.getNumberRegister(1).getContent == deleted
      check e.lines('2') == @["R1"]
      if '\n' notin deleted:
        check e.state.registers.getSmallDeleteRegister().getContent == deleted

  test "a delete over % into a register goes to 1 but not -":
    let e = createEditorForRegisters("(a b) c")

    e.press("\"", "a", "d", "%")

    check e.lines('a') == @["(a b)"]
    check e.lines('1') == @["(a b)"]
    check e.state.registers.getSmallDeleteRegister().isEmpty

  test "gn is no reason to use register 1":
    let e = createEditorForRegisters("x foo x foo")
    e.press("l", "l", "*", "0")

    e.press("d", "g", "n")

    check e.lines('-') == @["foo"]
    check e.lines('1') == @["R1"]

  test "adding to a register leaves all of it unnamed":
    for (keys, a, unnamed, one) in [
      (
        @["\"", "a", "y", "y", "j", "\"", "A", "y", "y"],
        @["one", "two"],
        @["one", "two"],
        "R1",
      ),
      (
        @["\"", "a", "y", "y", "j", "\"", "A", "d", "d"],
        @["one", "two"],
        @["one", "two"],
        "two",
      ),
      (@["\"", "a", "y", "w", "j", "\"", "A", "y", "w"], @["onetwo"], @["onetwo"], "R1"),
      (
        @["\"", "a", "y", "y", "j", "\"", "A", "y", "w"],
        @["one", "two"],
        @["one", "two"],
        "R1",
      ),
      (
        @["\"", "a", "y", "w", "j", "\"", "A", "y", "y"],
        @["one", "two"],
        @["one", "two"],
        "R1",
      ),
    ]:
      let e = createEditorForRegisters("one\ntwo\nthree")

      e.press(keys)

      check e.lines('a') == a
      check e.lines('"') == unnamed
      check e.state.registers.getNumberRegister(1).getContent.strip == one

  test "linewise text keeps its empty last lines when put":
    for (keys, cursor, expected) in [
      (@["3", "y", "y", "G", "p"], 0, @["foo", "", "", "bar", "", "foo", "", ""]),
      (@["2", "y", "y", "G", "p"], 1, @["foo", "", "", "bar", "", "", ""]),
      (@["3", "d", "d", "p"], 0, @["bar", "foo", "", "", ""]),
      (@["V", "j", "j", "y", "G", "p"], 0, @["foo", "", "", "bar", "", "foo", "", ""]),
      (
        @["\"", "a", "y", "y", "j", "\"", "A", "y", "y", "\"", "a", "p"],
        0,
        @["foo", "", "foo", "", "", "bar", ""],
      ),
    ]:
      let e = createEditorForRegisters("foo\n\n\nbar\n\n")
      e.activeWindow.cursor.line = cursor

      e.press(keys)

      check e.buffer == expected

  test "putting over a selection fills the registers as a delete does":
    let e = createEditorForRegisters("one\ntwo\nthree")
    e.press("y", "w", "v", "j", "p")

    check e.state.registers.getRegisterContent('1') == "one\nt"
    check not e.linewise('1')
    check e.state.registers.getRegisterContent('"') == "one\nt"

  test "P over a selection leaves the registers, as Vim's v_P":
    let e = createEditorForRegisters("one\ntwo\nthree")
    e.press("y", "w", "V", "j", "P")

    check e.buffer == @["one", "three"]
    check e.lines('"') == @["one"]
    check e.lines('1') == @["R1"]

  test "gP over a selection fills the registers as p does":
    let e = createEditorForRegisters("one\ntwo")
    e.press("j", "y", "w", "v", "l", "g", "P")

    check e.buffer == @["one", "twoo"]
    check e.lines('"') == @["tw"]
    check e.lines('-') == @["tw"]

  test "putting an empty register is Vim's E353":
    let e = createEditorForRegisters("one")

    discard e.handleKeyCombo(parseKeyCombo("\"").get)
    discard e.handleKeyCombo(parseKeyCombo("b").get)
    discard e.handleKeyCombo(parseKeyCombo("p").get)

    check e.buffer == @["one"]
    check e.state.statusMessage.contains("E353: Nothing in register b")

  test "lines put over a block go below it, as in Vim":
    let e = createEditorForRegisters("one\nabcd")
    e.press("y", "y", "j", "l", "C-v", "l", "p")

    check e.buffer == @["one", "ad", "one"]
    check e.activeWindow.cursor == BufferPosition(line: 2, column: 0)

  test "the cursor goes to the first non-blank of lines put over a selection":
    for (keys, lines, cursor) in [
      (
        @["v", "l", "p"],
        @["    foo", "a", "    foo", "d"],
        BufferPosition(line: 2, column: 4),
      ),
      (@["V", "p"], @["    foo", "    foo"], BufferPosition(line: 1, column: 4)),
    ]:
      let e = createEditorForRegisters("    foo\nabcd")
      e.press("y", "y", "j", "0", "l")

      e.press(keys)

      check e.buffer == lines
      check e.activeWindow.cursor == cursor

  test "P and gP put lines above a block, or below its first line at the line end":
    # Vim 9.2: P keeps the registers, gP does not; both put lines above the
    # block unless the block reached the end of its first line.
    for (content, column, keys, lines, cursor) in [
      ("one\nabcd", 1, @["C-v", "l", "P"], @["one", "one", "ad"], (1, 0)),
      (
        "one\nabcd\nefgh",
        1,
        @["C-v", "j", "l", "P"],
        @["one", "one", "ad", "eh"],
        (1, 0),
      ),
      ("one\nabcd\nx", 1, @["C-v", "l", "g", "P"], @["one", "one", "ad", "x"], (2, 0)),
      ("one\nabcd", 2, @["C-v", "l", "P"], @["one", "ab", "one"], (2, 0)),
      (
        "one\nabcd\nefgh",
        2,
        @["C-v", "j", "l", "P"],
        @["one", "ab", "one", "ef"],
        (2, 0),
      ),
      ("one\nab\nef", 0, @["C-v", "j", "l", "P"], @["one", "one", "", ""], (1, 0)),
    ]:
      let e = createEditorForRegisters(content)
      e.press("y", "y", "j", "0")
      for _ in 1 .. column:
        e.press("l")

      e.press(keys)

      check e.buffer == lines
      check e.activeWindow.cursor == BufferPosition(line: cursor[0], column: cursor[1])

  test "p and v_p make the text fit for the buffer alike":
    # Text yanked from a raw buffer can hold bytes that are not UTF-8; a
    # decoded buffer gets U+FFFD for them.
    for keys in [@["\"", "a", "p"], @["v", "\"", "a", "p"]]:
      let e = createEditorForRegisters("xy")
      check e.state.registers.setRegister('a', "a\xFFb", false).isOk

      e.press(keys)

      check e.buffer[0].contains("a\xEF\xBF\xBDb")

  test "p puts lines over a block below the line the cursor ended on":
    # Vim 9.2 puts them below b_visual.vi_end, which `k` or `o` can make the
    # top line of the block.
    for (setup, keys) in [
      (@["j", "j"], @["C-v", "k", "l", "p"]), (@["j"], @["C-v", "j", "l", "o", "p"])
    ]:
      let e = createEditorForRegisters("one\nabcd\nefgh\nijkl")
      e.press("y", "y")
      e.press(setup)
      e.press("l")

      e.press(keys)

      check e.buffer == @["one", "ad", "one", "eh", "ijkl"]
      check e.activeWindow.cursor == BufferPosition(line: 2, column: 0)

  test "^ and a put of lines land on the same first non-blank, as Vim's beginline":
    # Vim 9.2 skips spaces and tabs only, and stops on the last blank of an
    # all-blank line.
    for (content, column) in [("x\n   ", 2), ("x\n　foo", 0), ("x\n\t\tfoo", 2)]:
      let e = createEditorForRegisters(content)
      e.press("j", "^")
      check e.activeWindow.cursor.column == column

      e.press("y", "y", "k", "p")
      check e.activeWindow.cursor == BufferPosition(line: 1, column: column)

suite "handleKeyCombo - a count and the shape of a motion, as in Vim":
  # Expectations are Vim 9.2's.
  proc createEditorForCounts(content: string, line = 0, column = 0): Editor =
    result = newEditor(newEditorConfig())
    result.state.registers = initRegisters()
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].setTab(buf)
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.bindToWindow(result.activeWindow)
    result.state.mode = EditorMode.Normal
    result.activeWindow.cursor = BufferPosition(line: line, column: column)

  proc press(e: Editor, keys: varargs[string]) =
    for key in keys:
      check e.handleKeyCombo(parseKeyCombo(key).get)

  proc lines(e: Editor): seq[string] =
    for i in 0 ..< e.activeBuffer.len:
      result.add e.activeBuffer.getLine(i)

  proc at(line, column: int): BufferPosition =
    BufferPosition(line: line, column: column)

  test "a count goes to the count-th match of n, N, * and #":
    for (content, column, search, keys, cursor) in [
      ("x foo x foo x foo", 0, "foo", @["3", "n"], at(0, 14)),
      ("x foo x foo x foo", 14, "foo", @["2", "N"], at(0, 2)),
      ("foo x foo x foo", 0, "", @["2", "*"], at(0, 12)),
      ("foo x foo x foo", 0, "", @["3", "#"], at(0, 0)),
    ]:
      let e = createEditorForCounts(content, column = column)
      e.state.input.search.last.pattern = search

      e.press(keys)

      checkpoint($keys)
      check e.activeWindow.cursor == cursor

  test "_ goes count-1 lines down and takes whole lines":
    for (content, line, column, keys, lines, cursor, register) in [
      ("a\n  b\n  c\nd", 0, 0, @["3", "_"], @["a", "  b", "  c", "d"], at(2, 2), ""),
      ("a\n  b\n  c\nd", 0, 0, @["d", "3", "_"], @["d"], at(0, 0), "a\n  b\n  c\n"),
      # A yank leaves the cursor where it is.
      ("  foo bar\nx", 0, 6, @["y", "_"], @["  foo bar", "x"], at(0, 6), "  foo bar\n"),
      ("  foo bar\nx", 0, 6, @["d", "_"], @["x"], at(0, 0), "  foo bar\n"),
      ("foo\nx", 0, 1, @["c", "_", "X", "Escape"], @["X", "x"], at(0, 0), "foo\n"),
      # There is no line to go to from the last one.
      ("a\nb", 1, 0, @["2", "_"], @["a", "b"], at(1, 0), ""),
      ("a\nb", 1, 0, @["d", "2", "_"], @["a", "b"], at(1, 0), ""),
    ]:
      let e = createEditorForCounts(content, line, column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines
      check e.activeWindow.cursor == cursor
      check e.state.registers.getRegisterContent('"') == register

  test "a count takes $, D and C to the end of a later line":
    for (line, column, keys, lines, cursor, register) in [
      (0, 0, @["2", "$"], @["abc", "def", "ghi"], at(1, 2), ""),
      (0, 0, @["9", "$"], @["abc", "def", "ghi"], at(2, 2), ""),
      (0, 1, @["d", "2", "$"], @["a", "ghi"], at(0, 0), "bc\ndef"),
      (0, 1, @["2", "D"], @["a", "ghi"], at(0, 0), "bc\ndef"),
      (0, 1, @["D"], @["a", "def", "ghi"], at(0, 0), "bc"),
      (0, 1, @["2", "C", "X", "Escape"], @["aX", "ghi"], at(0, 1), "bc\ndef"),
      # There is no line to go to from the last one.
      (2, 0, @["2", "$"], @["abc", "def", "ghi"], at(2, 0), ""),
      (2, 0, @["d", "2", "$"], @["abc", "def", "ghi"], at(2, 0), ""),
    ]:
      let e = createEditorForCounts("abc\ndef\nghi", line, column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines
      check e.activeWindow.cursor == cursor
      check e.state.registers.getRegisterContent('"') == register

  test "gN puts the cursor at the start of the match":
    let e = createEditorForCounts("foo bar foo baz", column = 14)
    e.state.input.search.last.pattern = "baz"

    e.press("g", "N")

    check e.state.mode == EditorMode.Visual
    check e.state.visualSelection.start == at(0, 14)
    check e.activeWindow.cursor == at(0, 12)

    e.press("y", "g", "v")

    check e.state.visualSelection.start == at(0, 14)
    check e.activeWindow.cursor == at(0, 12)

  test "a count reaches the Visual h, j, k, l and $":
    for (content, line, column, keys, lines, register) in [
      ("a\nb\nc\nd\ne", 0, 0, @["V", "2", "j", "d"], @["d", "e"], "a\nb\nc\n"),
      ("a\nb\nc\nd\ne", 4, 0, @["V", "2", "k", "d"], @["a", "b"], "c\nd\ne\n"),
      ("a\nb\nc\nd\ne", 0, 0, @["V", "9", "j", "d"], @[""], "a\nb\nc\nd\ne\n"),
      ("abcdef", 0, 0, @["v", "3", "l", "y"], @["abcdef"], "abcd"),
      ("abcdef", 0, 5, @["v", "3", "h", "y"], @["abcdef"], "cdef"),
      ("abc\ndef\nghi", 0, 0, @["v", "2", "$", "d"], @["ghi"], "abc\ndef\n"),
      # There is no line to go to from the last one.
      ("abc\ndef\nghi", 2, 0, @["v", "2", "$", "d"], @["abc", "def", "hi"], "g"),
    ]:
      let e = createEditorForCounts(content, line, column)

      e.press(keys)

      checkpoint($keys)
      check e.lines == lines
      check e.state.registers.getRegisterContent('"') == register

  test "the Visual j and k keep the column they aim for over a shorter line":
    for keys in [@["v", "j", "j", "y"], @["v", "2", "j", "y"]]:
      let e = createEditorForCounts("abcdef\nx\nabcdef", column = 4)

      e.press(keys)

      checkpoint($keys)
      check e.state.registers.getRegisterContent('"') == "ef\nx\nabcde"

    # The shorter line puts the cursor on its line break.
    let e = createEditorForCounts("abcdef\nx\nabcdef", column = 4)
    e.press("v", "j", "y")
    check e.state.registers.getRegisterContent('"') == "ef\nx\n"

  test "a closed fold counts as one line for a count, as Vim's cursor_down":
    const TenLines = "l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9"
    for (line, keys, cursor) in [
      (0, @["3", "j"], at(7, 0)),
      (0, @["4", "$"], at(7, 1)),
      (0, @["3", "+"], at(7, 0)),
      (7, @["3", "k"], at(0, 0)),
      (7, @["2", "-"], at(1, 0)),
      (0, @["v", "3", "j"], at(7, 0)),
    ]:
      let e = createEditorForCounts(TenLines, line)
      check e.activeBuffer.foldState.addFold(1, 5)

      e.press(keys)

      checkpoint($keys)
      check e.activeWindow.cursor == cursor

    let e = createEditorForCounts(TenLines)
    check e.activeBuffer.foldState.addFold(1, 5)
    e.press("d", "3", "_")
    check e.lines == @["l7", "l8", "l9"]

  test "_, + and - that find no line keep the column vertical moves want":
    for (content, line, keys) in [
      ("abcdefghijk\nab", 0, @["j", "2", "_", "k"]),
      ("abcdefghijk\nab", 0, @["j", "2", "+", "k"]),
      ("ab\nabcdefghijk", 1, @["k", "2", "-", "j"]),
    ]:
      let e = createEditorForCounts(content, line, 10)

      e.press(keys)

      checkpoint($keys)
      check e.activeWindow.cursor.column == 10
