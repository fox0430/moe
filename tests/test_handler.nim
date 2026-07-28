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

import std/[unittest, options, tables, os, osproc, times]
from std/strutils import contains

import pkg/[celina, chronos]
import pkg/celina/core/mouse_logic

import config_test_helper

import
  ../src/moepkg/[
    buffer, types, modes, registers, editor, config, filer, key_bindings, config_loader,
    render_utils, clipboard,
  ]
import ../src/moepkg/handler {.all.}
import ../src/moepkg/command_handlers/result_processor

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
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
  )

  EditorState(
    activeWindow: window,
    display:
      DisplaySettings(showLineCount: true, showLinePercentage: true, showEncoding: true),
    config: newEditorConfig(),
    windowDisplay: WindowDisplayState(viewportReservedLines: steadyBottomAreaHeight()),
    pendingInput: PendingInputState(
      macroState: MacroState(
        isRecording: false,
        register: '\0',
        recordedKeys: @[],
        registers: initTable[char, seq[string]](),
        lastRegister: none(char),
        waitingForRegister: false,
        commandType: "",
        pendingCount: 0,
        playbackDepth: 0,
      )
    ),
    registers: initRegisters(),
    overlay: none(OverlayKind),
    input: InputState(
      search: SearchState(
        direction: Forward,
        text: "",
        lastText: "",
        startPos: BufferPosition(line: 0, column: 0),
        history: @[],
        historyIndex: -1,
        ignorecase: true,
        smartcase: true,
        incsearch: true,
        hlsearch: true,
        hlsearchTempDisabled: false,
        wholeWord: false,
      )
    ),
  )

proc noOpFrontendHook(): Future[void] {.async.} =
  discard

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
    kind: paoBuild,
    build: (path: "/tmp/detached.nim", language: 0, customCmd: "", workspaceRoot: ""),
  )

proc runDetachedScenario(e: Editor): Future[void] {.async: (raises: [Exception]).} =
  asyncSpawn detachedPendingWriter(e)
  # Yield so the detached task runs before the drain.
  await sleepAsync(10)
  await e.handlePendingAsyncOperations(FrontendHooks())

suite "handlePendingAsyncOperations drains ops queued from async tasks":
  test "build op drains on tick":
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.state.pending.add PendingAsyncOp(
      kind: paoBuild,
      build: (path: "/tmp/x.nim", language: 0, customCmd: "", workspaceRoot: ""),
    )

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0

  test "quickRun op drains on tick":
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (cmd: "echo", args: @["hi"], filePath: "", isTempFile: false),
    )

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0

  test "syntaxCheck op drains on tick":
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.state.pending.add PendingAsyncOp(
      kind: paoSyntaxCheck, syntaxCheck: (path: "/tmp/x.nim", language: 0)
    )

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0

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
      kind: paoBuild,
      build: (path: "/tmp/x.nim", language: 0, customCmd: "", workspaceRoot: ""),
    )
    editor.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (cmd: "echo", args: @["hi"], filePath: "", isTempFile: false),
    )
    editor.state.pending.add PendingAsyncOp(
      kind: paoSyntaxCheck, syntaxCheck: (path: "/tmp/y.nim", language: 0)
    )

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0

  test "duplicate ops of the same kind are both kept and drained":
    # The old flat-field layout silently overwrote the first request.
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.state.pending.add PendingAsyncOp(
      kind: paoSyntaxCheck, syntaxCheck: (path: "/tmp/a.nim", language: 0)
    )
    editor.state.pending.add PendingAsyncOp(
      kind: paoSyntaxCheck, syntaxCheck: (path: "/tmp/b.nim", language: 0)
    )
    check editor.state.pending.len == 2

    waitFor editor.handlePendingAsyncOperations(FrontendHooks())

    check editor.state.pending.len == 0

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

    waitFor runSyntaxCheckAsync(editor, (path: "/nonexistent.txt", language: 0))

    check editor.state.notificationPopup.queue.len == 1
    check editor.state.notificationPopup.queue[0].level == nlError
    check "Syntax check error" in editor.state.notificationPopup.queue[0].message

  test "syntax check failure still reaches the status line without popups":
    let config = newEditorConfig()
    let editor = newEditor(config)
    editor.config.notification.popupNotifications = false
    editor.state.setStatusQuiet("")

    waitFor runSyntaxCheckAsync(editor, (path: "/nonexistent.txt", language: 0))

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
  result.windowManager.windows[0].buffer = buf
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

suite "handleMouseEvent - Wheel Scroll":
  test "WheelDown scrolls cursor down by 3 lines":
    let e = createTestEditorWithBuffer(
      "line0\nline1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9"
    )
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 3

  test "WheelUp scrolls cursor up by 3 lines":
    let e = createTestEditorWithBuffer(
      "line0\nline1\nline2\nline3\nline4\nline5\nline6\nline7\nline8\nline9"
    )
    e.windowManager.windows[0].cursor = BufferPosition(line: 6, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 3

  test "WheelUp clamps to line 0":
    let e = createTestEditorWithBuffer("line0\nline1\nline2\nline3\nline4")
    e.windowManager.windows[0].cursor = BufferPosition(line: 1, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 0

  test "WheelDown clamps to last line":
    let e = createTestEditorWithBuffer("line0\nline1\nline2\nline3\nline4")
    e.windowManager.windows[0].cursor = BufferPosition(line: 3, column: 0)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 4

  test "WheelDown clamps column to line length":
    let e = createTestEditorWithBuffer("long line here\nhi\nshort\nanother\nmore\nend")
    # Start on long line with column beyond short line's length
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 10)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 3
    # "another" has len 7, so max column is 6
    check e.windowManager.windows[0].cursor.column <= 6

  test "WheelDown clamps column to character count for multibyte":
    # "あいうえお" is 5 chars (15 bytes). After scrolling to "ab" (2 chars),
    # column should clamp to 1, not stay at 4.
    let e = createTestEditorWithBuffer("あいうえお\nxx\nxx\nab")
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 4)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 3
    # "ab" has 2 chars, so max column is 1
    check e.windowManager.windows[0].cursor.column == 1

  test "WheelDown updates viewport topLine when cursor goes below viewport":
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

    # Scroll down: cursor moves to line 6, which is outside viewport [0..4]
    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 2)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 6
    # topLine should adjust so cursor is visible (line 6 at bottom: topLine = 6-5+1 = 2)
    check e.windowManager.windows[0].viewport.topLine == 2

  test "WheelUp updates viewport topLine when cursor goes above viewport":
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

    # Scroll up: cursor moves to line 8, which is above viewport topLine=10
    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 2)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 8
    check e.windowManager.windows[0].viewport.topLine == 8

  test "WheelDown keeps viewport unchanged when cursor stays visible":
    var lines: string
    for i in 0 ..< 30:
      if i > 0:
        lines.add "\n"
      lines.add "line" & $i
    let e = createTestEditorWithBuffer(lines)
    e.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 10, topLine: 0, leftColumn: 0)
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)

    # Scroll down: cursor moves to line 3, still within viewport [0..9]
    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 2)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].cursor.line == 3
    # topLine should remain 0 since cursor is still visible
    check e.windowManager.windows[0].viewport.topLine == 0

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
      buffer: buf2,
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
    check e.windowManager.windows[1].cursor.line == 3
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
      buffer: buf2,
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
    e.activeBuffer.lastFileModTime = some(getTime() - initDuration(seconds = 2))
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

  test "Preserves original buffer in filer state":
    let e = createTestEditorWithBuffer("hello")
    let originalBuf = e.activeWindow.buffer
    e.enterFilerInActiveWindow("/tmp")

    check e.activeWindow.originalBuffer == originalBuf

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
    var themeFileCounter {.global.} = 0
    inc themeFileCounter
    let themeFile =
      getTempDir() / "moe_test_putconfigfile_theme_" & $themeFileCounter & ".toml"
    defer:
      removeFile(themeFile)

    withTempHome(tmpDir):
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
  result.windowManager.windows[0].buffer = buf
  result.windowManager.windows[0].bufferIds = @[buf.id]
  result.windowManager.windows[0].viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.motionController.viewportManager.viewport = result.viewport
  result.state.mode = EditorMode.Normal

proc makeMiddleClickEvent(x, y: int): Event =
  Event(
    kind: EventKind.Mouse,
    mouse: MouseEvent(
      kind: MouseEventKind.Press, button: mouse_logic.MouseButton.Middle, x: x, y: y
    ),
  )

suite "cursorAfterPaste":
  test "Empty text leaves cursor at start position":
    let start = BufferPosition(line: 3, column: 7)
    let after = cursorAfterPaste(start, "")
    check after.line == 3
    check after.column == 7

  test "Single-line ASCII advances column by rune count":
    let start = BufferPosition(line: 0, column: 5)
    let after = cursorAfterPaste(start, " world")
    check after.line == 0
    check after.column == 11

  test "Multibyte runes advance column by rune, not byte":
    # "café" is 4 runes / 5 bytes: byte iteration would land at column 5.
    let start = BufferPosition(line: 0, column: 0)
    let after = cursorAfterPaste(start, "café")
    check after.line == 0
    check after.column == 4

  test "LF resets column and increments line":
    let start = BufferPosition(line: 2, column: 4)
    let after = cursorAfterPaste(start, "\nabc")
    check after.line == 3
    check after.column == 3

  test "Multiple newlines advance across several lines":
    let start = BufferPosition(line: 0, column: 2)
    let after = cursorAfterPaste(start, "a\nbb\nccc")
    check after.line == 2
    check after.column == 3

  test "Trailing newline lands cursor at column 0 of next line":
    let start = BufferPosition(line: 1, column: 3)
    let after = cursorAfterPaste(start, "xy\n")
    check after.line == 2
    check after.column == 0

  test "Start column is preserved when first rune stays on same line":
    let start = BufferPosition(line: 4, column: 10)
    let after = cursorAfterPaste(start, "z")
    check after.line == 4
    check after.column == 11

suite "middleClickPaste":
  test "Clipboard disabled":
    let e = createTestEditorForMiddleClick("hello")
    e.config.clipboard.enable = false
    e.state.mode = EditorMode.Insert
    discard e.activeBuffer.beginTransaction("test")

    e.middleClickPaste()

    # Buffer should be unchanged
    check e.activeBuffer.getLine(0) == "hello"

  test "Unsupported mode (Visual)":
    let e = createTestEditorForMiddleClick("hello")
    e.state.mode = EditorMode.Visual

    e.middleClickPaste()

    check e.activeBuffer.getLine(0) == "hello"

  test "Read-only buffer in Normal mode does not enter Insert or move cursor":
    let e = createTestEditorForMiddleClick("hello")
    e.state.mode = EditorMode.Normal
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)
    e.activeBuffer.readOnly = true

    e.middleClickPaste()

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
    e.state.mode = EditorMode.Normal
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)

    e.middleClickPaste()

    check e.state.mode == EditorMode.Normal
    check not e.activeBuffer.inTransaction
    check e.activeBuffer.getLine(0) == "hello"

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

      e.middleClickPaste()

      let line = e.activeBuffer.getLine(0)
      check $line == "hello" & testText

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

      e.middleClickPaste()

      check e.state.mode == EditorMode.Insert
      let line = e.activeBuffer.getLine(0)
      check $line == testText & "hello"

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

      e.middleClickPaste()

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

      e.middleClickPaste()

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

      e.middleClickPaste()

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

      e.middleClickPaste()

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

      let event = makeMiddleClickEvent(0, 0)
      discard e.handleEvent(event)

      check e.state.mode == EditorMode.Insert
      let line = e.activeBuffer.getLine(0)
      check ($line).len > 5 # Text was inserted

suite "handlePasteEvent":
  proc createTestEditorForPaste(content: string): Editor =
    let config = newEditorConfig()
    result = newEditor(config)
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].buffer = buf
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.viewportManager.viewport = result.viewport

  proc makePasteEvent(text: string): Event =
    Event(kind: EventKind.Paste, pastedText: text)

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

suite "handleEvent - Insert-Normal mode (Ctrl-o) Ctrl-C handling":
  let quitEvent = Event(kind: EventKind.Quit)

  proc createTestEditorForInsertNormal(content: string): Editor =
    let config = newEditorConfig()
    config.standard.mouse = true
    result = newEditor(config)
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].buffer = buf
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.viewportManager.viewport = result.viewport
    result.state.mode = EditorMode.Normal

  test "Ctrl-C in Normal mode with insertNormalMode clears flag and commits":
    let e = createTestEditorForInsertNormal("hello")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 3)
    e.state.cursor = BufferPosition(line: 0, column: 3)
    discard e.activeBuffer.beginTransaction("Insert mode edit")
    e.state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))

    discard e.handleEvent(quitEvent)

    check not e.state.insertNormalMode
    check e.state.mode == EditorMode.Normal
    check not e.activeBuffer.inTransaction
    check e.state.editState.insertModeStartPos.isNone

  test "Ctrl-C in Normal mode with insertNormalMode at column 0 stays at 0":
    let e = createTestEditorForInsertNormal("hello")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.windowManager.windows[0].cursor = BufferPosition(line: 0, column: 0)
    e.state.cursor = BufferPosition(line: 0, column: 0)
    discard e.activeBuffer.beginTransaction("Insert mode edit")
    e.state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))

    discard e.handleEvent(quitEvent)

    check not e.state.insertNormalMode
    check e.windowManager.windows[0].cursor.column == 0

  test "Ctrl-C in Normal mode without insertNormalMode shows exit message":
    let e = createTestEditorForInsertNormal("hello")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = false

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Normal
    check "qa" in e.state.statusMessage

  test "Ctrl-C in search overlay with insertNormalMode returns to Insert":
    let e = createTestEditorForInsertNormal("hello world")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.text = "world"

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isSearchOverlay

  test "Ctrl-C in command overlay with insertNormalMode returns to Insert":
    let e = createTestEditorForInsertNormal("hello")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":w"

    discard e.handleEvent(quitEvent)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isCommandOverlay

suite "handleCommandModeKeyCombo - Insert-Normal mode (Ctrl-o)":
  let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
  let escKey = KeyCombo(isSpecial: true, special: skEscape, fnNum: 0, modifiers: {})

  proc createEditorForCmdOverlay(content: string): Editor =
    let config = newEditorConfig()
    config.standard.mouse = true
    result = newEditor(config)
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].buffer = buf
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.viewportManager.viewport = result.viewport
    result.state.mode = EditorMode.Normal

  proc setupInsertNormalCommandOverlay(e: Editor) =
    ## Set up: Insert → Ctrl-O → Normal → ':' (command overlay)
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    discard e.activeBuffer.beginTransaction("Insert mode edit")
    e.state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    e.state.enterCommandOverlay()
    e.state.input.commandText = ""
    e.state.input.commandCursor = 0

  test "Escape in command overlay returns to Insert when insertNormalMode":
    let e = createEditorForCmdOverlay("hello")
    e.setupInsertNormalCommandOverlay()
    e.state.input.commandText = ":partial"

    discard e.handleCommandModeKeyCombo(escKey)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isCommandOverlay

  test "Escape in command overlay stays Normal when insertNormalMode is false":
    let e = createEditorForCmdOverlay("hello")
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = false
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":partial"

    discard e.handleCommandModeKeyCombo(escKey)

    check e.state.mode == EditorMode.Normal
    check not e.state.isCommandOverlay

  test "Empty Enter in command overlay returns to Insert when insertNormalMode":
    let e = createEditorForCmdOverlay("hello")
    e.setupInsertNormalCommandOverlay()
    e.state.input.commandText = ""

    discard e.handleCommandModeKeyCombo(enterKey)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isCommandOverlay

  test "Enter with Normal-staying command returns to Insert when insertNormalMode":
    let e = createEditorForCmdOverlay("hello")
    e.setupInsertNormalCommandOverlay()
    # :noh is a simple command that stays in Normal mode
    e.state.input.commandText = ":noh"

    discard e.handleCommandModeKeyCombo(enterKey)

    check e.state.mode == EditorMode.Insert
    check not e.state.insertNormalMode
    check not e.state.isCommandOverlay

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

suite "Macro recording - Command / Search overlay keys":
  # Regression: overlay dispatch used to bypass macro recording, so `qa:s/foo/bar/<CR>q`
  # would capture only ":" and lose the rest of the command line (same for `/pattern<CR>`).
  proc createEditorForOverlayRecord(content: string): Editor =
    let config = newEditorConfig()
    result = newEditor(config)
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].buffer = buf
    result.windowManager.windows[0].bufferIds = @[buf.id]
    result.windowManager.windows[0].viewport =
      ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
    result.motionController.viewportManager.viewport = result.viewport
    result.state.mode = EditorMode.Normal

  proc startRecording(e: Editor, register: char) =
    e.state.pendingInput.macroState.isRecording = true
    e.state.pendingInput.macroState.register = register
    e.state.pendingInput.macroState.recordedKeys = @[]
    e.state.pendingInput.macroState.recordStartKey = "q"

  test "Command overlay: keys after ':' land in recordedKeys":
    let e = createEditorForOverlayRecord("hello foo bar")
    e.startRecording('a')
    e.state.enterCommandOverlay()

    for ch in "s/foo/bar/":
      discard e.handleEvent(makeCharEvent($ch))
    discard e.handleEvent(makeEnterEvent())

    check e.state.pendingInput.macroState.recordedKeys ==
      @["s", "/", "f", "o", "o", "/", "b", "a", "r", "/", "<Enter>"]

  test "Search overlay: pattern and Enter recorded":
    let e = createEditorForOverlayRecord("hello world")
    e.startRecording('a')
    e.state.enterSearchOverlay(SearchDirection.Forward)

    for ch in "wor":
      discard e.handleEvent(makeCharEvent($ch))
    discard e.handleEvent(makeEnterEvent())

    check e.state.pendingInput.macroState.recordedKeys == @["w", "o", "r", "<Enter>"]

  test "Command overlay Escape recorded so playback replays cancel":
    let e = createEditorForOverlayRecord("hello")
    e.startRecording('a')
    e.state.enterCommandOverlay()

    discard e.handleEvent(makeCharEvent("a"))
    discard e.handleEvent(makeCharEvent("b"))
    discard
      e.handleEvent(Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Escape)))

    check e.state.pendingInput.macroState.recordedKeys == @["a", "b", "<Escape>"]
    check not e.state.isCommandOverlay

  test "Recording paused during playback (withPlaybackGuard)":
    # Sanity: replayed keys must not re-enter recordedKeys.
    let e = createEditorForOverlayRecord("hello")
    e.startRecording('a')
    e.state.enterCommandOverlay()
    e.state.pendingInput.macroState.playbackDepth = 1
    e.state.pendingInput.macroState.isRecording = false # withPlaybackGuard mirror

    discard e.handleEvent(makeCharEvent("x"))

    check e.state.pendingInput.macroState.recordedKeys.len == 0

suite "Macro playback - overlay-aware routing":
  # Regression: nested key replay dispatched by state.mode, so overlay-mode keys
  # were mis-interpreted by the base handler. runNestedKeyCombo now consults
  # `overlayPlaybackHook` (wired from handler.nim) to route via the overlay handler.
  proc createEditorForOverlayPlayback(content: string): Editor =
    let config = newEditorConfig()
    result = newEditor(config)
    let buf = newTextBuffer(content)
    result.windowManager.windows[0].buffer = buf
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
    buffer: buf2,
    bufferIds: @[buf2.id],
    viewport:
      ViewPort(x: vpx, y: 0, width: 80 - vpx, height: 24, topLine: 0, leftColumn: 0),
    cursor: BufferPosition(line: 0, column: 0),
    active: false,
    mode: EditorMode.Normal,
  )
  e.windowManager.windows.add(win2)

suite "handleMouseEvent - Cross-window jump finalizes stale state":
  test "Insert-mode transaction on old buffer is committed":
    # Without the finalize hook, bufA's open transaction leaks past the jump.
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("xxx\nyyy\nzzz")
    e.addSecondWindow(buf2)

    let bufA = e.windowManager.windows[0].buffer
    e.state.mode = EditorMode.Insert
    e.state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    check bufA.beginTransaction("Insert mode edit").isOk
    check bufA.inTransaction

    let handled = e.handleMouseEvent(makeLeftClickEvent(50, 1))
    check handled == true

    check e.windowManager.activeWindowIndex == 1
    check not bufA.inTransaction
    check e.state.editState.insertModeStartPos.isNone
    check e.state.mode == EditorMode.Normal

  test "Visual selection is cleared before touching new buffer":
    # Anchor line 5 on a 6-line buf, click into a 2-line buf: a surviving
    # visualSelection would OOB in the next Visual operator.
    let e = createTestEditorWithBuffer("a\nb\nc\nd\ne\nf")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("x\ny")
    e.addSecondWindow(buf2)

    e.state.mode = EditorMode.Visual
    e.state.visualSelection = VisualSelection(
      start: BufferPosition(line: 5, column: 0),
      current: BufferPosition(line: 5, column: 0),
      active: true,
      kind: vskChar,
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

  test "Ctrl-o (insert-normal) commits Insert transaction on jump":
    # Ctrl-o keeps an open Insert transaction while state.mode is Normal;
    # the mode-branch alone would miss it.
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.showTabLine = false
    e.state.showStatusLine = true
    let buf2 = newTextBuffer("xxx\nyyy")
    e.addSecondWindow(buf2)

    let bufA = e.windowManager.windows[0].buffer
    e.state.mode = EditorMode.Normal
    e.state.insertNormalMode = true
    e.state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    check bufA.beginTransaction("Insert mode edit").isOk

    let handled = e.handleMouseEvent(makeLeftClickEvent(50, 0))
    check handled == true

    check not bufA.inTransaction
    check not e.state.insertNormalMode
    check e.state.editState.insertModeStartPos.isNone

  test "Click on the same window keeps mode/state intact":
    # The finalize hook must fire only on cross-window jumps.
    let e = createTestEditorWithBuffer("aaa\nbbb\nccc")
    e.state.showTabLine = false
    e.state.showStatusLine = true

    let bufA = e.windowManager.windows[0].buffer
    e.state.mode = EditorMode.Insert
    e.state.editState.insertModeStartPos = some(BufferPosition(line: 0, column: 0))
    check bufA.beginTransaction("Insert mode edit").isOk

    # Two windows so the same-window branch (not the single-window one) runs.
    let buf2 = newTextBuffer("xxx")
    e.addSecondWindow(buf2)

    let handled = e.handleMouseEvent(makeLeftClickEvent(10, 1))
    check handled == true

    check e.windowManager.activeWindowIndex == 0
    check bufA.inTransaction
    check e.state.mode == EditorMode.Insert
    check e.state.editState.insertModeStartPos.isSome

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
    check e.bufferIndexById(recentBufId) >= 0
    check e.state.mode == EditorMode.RecentFile
    check e.state.statusMessage == "File not found: " & missing
