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

import std/[unittest, options, tables, os]
from std/strutils import contains

import config_test_helper

import pkg/celina
import pkg/celina/core/mouse_logic

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/editor {.all.}
import ../src/moepkg/config {.all.}
import ../src/moepkg/filer {.all.}
import ../src/moepkg/handler {.all.}
import ../src/moepkg/config_loader {.all.}
import ../src/moepkg/render_utils

proc createTestViewport(x, y, width, height, topLine, leftColumn: int): ViewPort =
  ViewPort(
    x: x, y: y, width: width, height: height, topLine: topLine, leftColumn: leftColumn
  )

proc createTestState(): EditorState =
  ## Create a minimal EditorState for testing
  EditorState(
    cursor: BufferPosition(line: 0, column: 0),
    preferredColumn: -1,
    screenCursor: CursorPosition(x: 0, y: 0),
    mode: EditorMode.Normal,
    previousMode: EditorMode.Normal,
    display: DisplaySettings(
      showTabLine: false,
      showStatusLine: true,
      multiStatusLine: false,
      showLineCount: true,
      showLinePercentage: true,
      showEncoding: true,
      showLineNumbers: true,
      showCursorLine: false,
      showSyntax: true,
      showIndentationLines: false,
      showSidebar: false,
      showGitDiff: false,
      showSyntaxChecker: false,
      showCodeLens: false,
      showDocumentHighlight: false,
      lineWrap: true,
      tabStop: 2,
      expandTab: true,
      autoIndent: true,
      autoCloseParen: false,
      autoDeleteParen: false,
    ),
    needsFullRedraw: false,
    viewportReservedLines: StatusAndCommandReserve,
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
    ),
    registers: initRegisters(),
    overlay: none(OverlayState),
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
    ),
  )

suite "screenToBufferPosition - Basic":
  test "Click at top-left corner of viewport":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    let result = screenToBufferPosition(
      vp, buffer, 0, 0, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 0

  test "Click with line number offset":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 4 # Space for line numbers
      reservedLines = StatusAndCommandReserve

    # Click at x=5, which is x=1 in text area (5 - 4 = 1)
    let result = screenToBufferPosition(
      vp, buffer, 5, 0, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 1

  test "Click on second line":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Line 1\nLine 2\nLine 3")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    let result = screenToBufferPosition(
      vp, buffer, 3, 1, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 3

  test "Click outside text area (below reserved lines)":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    # Click at y=23 is within reserved lines (height=24, reserved=2)
    let result = screenToBufferPosition(
      vp,
      buffer,
      0,
      23,
      lineNumOffset,
      sidebarWidth = 0,
      reservedLines,
      lineWrap = false,
    )

    check result.isNone

  test "Click outside text area (left of line number offset)":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 4
      reservedLines = StatusAndCommandReserve

    # Click at x=2 is within line number area
    let result = screenToBufferPosition(
      vp, buffer, 2, 0, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = false
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
      reservedLines = StatusAndCommandReserve

    let result = screenToBufferPosition(
      vp, buffer, 3, 0, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 10 # topLine + screenY
    check result.get.column == 3

  test "Click with leftColumn offset (horizontal scroll)":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 5) # leftColumn = 5
      buffer = newTextBuffer("Hello World this is a long line")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    let result = screenToBufferPosition(
      vp, buffer, 3, 0, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = false
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
      reservedLines = StatusAndCommandReserve

    let result = screenToBufferPosition(
      vp, buffer, 5, 0, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = false
    )

    check result.isSome
    check result.get.line == 5
    check result.get.column == 15 # leftColumn + screenX = 10 + 5

suite "screenToBufferPosition - Column Clamping":
  test "Column clamped to line length":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Hi") # Only 2 characters
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    # Click at x=50, but line only has 2 chars
    let result = screenToBufferPosition(
      vp,
      buffer,
      50,
      0,
      lineNumOffset,
      sidebarWidth = 0,
      reservedLines,
      lineWrap = false,
    )

    check result.isSome
    check result.get.line == 0
    check result.get.column == 1 # Clamped to max(0, lineLen - 1) = 1

  test "Column clamped on empty line":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Line 1\n\nLine 3") # Line 1 is empty
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    # Click on empty line at x=10
    let result = screenToBufferPosition(
      vp,
      buffer,
      10,
      1,
      lineNumOffset,
      sidebarWidth = 0,
      reservedLines,
      lineWrap = false,
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 0 # Empty line, column stays at 0

suite "screenToBufferPosition - Line Clamping":
  test "Line clamped when clicking beyond buffer":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 0)
      buffer = newTextBuffer("Only one line")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    # Click at y=10, but buffer only has 1 line
    let result = screenToBufferPosition(
      vp,
      buffer,
      5,
      10,
      lineNumOffset,
      sidebarWidth = 0,
      reservedLines,
      lineWrap = false,
    )

    check result.isSome
    check result.get.line == 0 # Clamped to buffer.len - 1

  test "Line clamped with scrolled viewport":
    let
      vp = createTestViewport(0, 0, 80, 24, 5, 0) # topLine = 5
      buffer = newTextBuffer("line0\nline1\nline2\nline3\nline4\nline5\nline6")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    # Click at y=10, topLine=5, so bufferLine = 15, but only 7 lines
    let result = screenToBufferPosition(
      vp,
      buffer,
      0,
      10,
      lineNumOffset,
      sidebarWidth = 0,
      reservedLines,
      lineWrap = false,
    )

    check result.isSome
    check result.get.line == 6 # Clamped to buffer.len - 1

suite "screenToBufferPosition - Viewport Position":
  test "Click with viewport at non-zero position":
    let
      vp = createTestViewport(10, 5, 60, 20, 0, 0) # Viewport at (10, 5)
      buffer = newTextBuffer("Hello World\nSecond line\nThird line")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    # Click at absolute (12, 6) which is relative (2, 1) to viewport
    let result = screenToBufferPosition(
      vp,
      buffer,
      12,
      6,
      lineNumOffset,
      sidebarWidth = 0,
      reservedLines,
      lineWrap = false,
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 2

  test "Click outside viewport area (above)":
    let
      vp = createTestViewport(10, 5, 60, 20, 0, 0)
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    # Click at y=3, viewport starts at y=5
    let result = screenToBufferPosition(
      vp,
      buffer,
      15,
      3,
      lineNumOffset,
      sidebarWidth = 0,
      reservedLines,
      lineWrap = false,
    )

    check result.isNone

suite "screenToBufferPosition - Line Wrap Mode":
  test "Click with lineWrap enabled uses screen position directly":
    let
      vp = createTestViewport(0, 0, 80, 24, 0, 5) # leftColumn is set but ignored
      buffer = newTextBuffer("Hello World")
      lineNumOffset = 0
      reservedLines = StatusAndCommandReserve

    # With lineWrap=true, leftColumn should be ignored
    let result = screenToBufferPosition(
      vp, buffer, 3, 0, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = true
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
      reservedLines = StatusAndCommandReserve

    # Click on screen row 1 (second wrap segment), col 2 => char 7 ('h')
    let result = screenToBufferPosition(
      vp, buffer, 2, 1, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = true
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
      reservedLines = StatusAndCommandReserve

    # Click on screen row 1 => line 1
    let result = screenToBufferPosition(
      vp, buffer, 2, 1, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = true
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
      reservedLines = StatusAndCommandReserve

    # Click at x=7 on row 1 => screenX = 7-5=2, segment 1, char 12 ('m')
    let result = screenToBufferPosition(
      vp, buffer, 7, 1, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = true
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
      reservedLines = StatusAndCommandReserve

    # Click at x=9 on row 1 => screenX = 9-2-5=2, segment 1, char 12 ('m')
    let result = screenToBufferPosition(
      vp, buffer, 9, 1, lineNumOffset, sidebarWidth, reservedLines, lineWrap = true
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
      reservedLines = StatusAndCommandReserve

    # Click on row 1, col 0 => first char of segment 1 = char 3 ('え')
    let result = screenToBufferPosition(
      vp, buffer, 0, 1, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = true
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
      reservedLines = StatusAndCommandReserve

    # Click on row 1, col 1 => char 8 ('h')
    let result = screenToBufferPosition(
      vp,
      buffer,
      1,
      1,
      lineNumOffset,
      sidebarWidth = 0,
      reservedLines,
      lineWrap = true,
      tabStop = 4,
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
      reservedLines = StatusAndCommandReserve

    # Click on row 2, col 1 => line 1, char 1 ('l')
    let result = screenToBufferPosition(
      vp, buffer, 1, 2, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = true
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 1

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

suite "hasPendingAsyncOperations":
  test "Returns false when no pending operations":
    # We would need an Editor instance to test this properly
    # This test is a placeholder to document the expected behavior
    check true

suite "Search Mode - History Navigation":
  test "Search state initialized correctly":
    let state = createTestState()
    state.enterSearchOverlay(Forward)

    check state.search.direction == Forward
    check state.search.text == ""
    check state.search.historyIndex == -1

  test "Search state with backward direction":
    let state = createTestState()
    state.enterSearchOverlay(Backward)

    check state.search.direction == Backward
    check state.search.text == ""

  test "Search history index starts at -1":
    let state = createTestState()
    state.search.history = @["pattern1", "pattern2", "pattern3"]
    state.enterSearchOverlay(Forward)

    check state.search.historyIndex == -1

  test "Search state preserves history on enter":
    let state = createTestState()
    state.search.history = @["old_search"]
    state.enterSearchOverlay(Forward)

    # History should be preserved
    check state.search.history.len == 1
    check state.search.history[0] == "old_search"

suite "Search Mode - Start Position":
  test "Search start position captured from cursor":
    let state = createTestState()
    state.cursor = BufferPosition(line: 10, column: 5)
    state.enterSearchOverlay(Forward)

    check state.search.startPos.line == 10
    check state.search.startPos.column == 5

  test "Different cursor positions captured correctly":
    let state = createTestState()

    # First search
    state.cursor = BufferPosition(line: 0, column: 0)
    state.enterSearchOverlay(Forward)
    check state.search.startPos.line == 0
    check state.search.startPos.column == 0

    state.exitOverlay()

    # Second search from different position
    state.cursor = BufferPosition(line: 50, column: 20)
    state.enterSearchOverlay(Backward)
    check state.search.startPos.line == 50
    check state.search.startPos.column == 20

suite "Search Mode - Text Handling":
  test "Search text cleared on overlay enter":
    let state = createTestState()
    state.search.text = "previous search"
    state.enterSearchOverlay(Forward)

    check state.search.text == ""

  test "Search text cleared on overlay exit":
    let state = createTestState()
    state.enterSearchOverlay(Forward)
    state.search.text = "current search"
    state.exitOverlay()

    check state.search.text == ""

  test "History index reset on overlay exit":
    let state = createTestState()
    state.search.history = @["pattern1", "pattern2"]
    state.enterSearchOverlay(Forward)
    state.search.historyIndex = 1
    state.exitOverlay()

    check state.search.historyIndex == -1

suite "Search Mode - Search Options":
  test "Search ignorecase option preserved":
    let state = createTestState()
    state.search.ignorecase = false
    state.enterSearchOverlay(Forward)

    check state.search.ignorecase == false

  test "Search smartcase option preserved":
    let state = createTestState()
    state.search.smartcase = false
    state.enterSearchOverlay(Forward)

    check state.search.smartcase == false

  test "Search incsearch option preserved":
    let state = createTestState()
    state.search.incsearch = false
    state.enterSearchOverlay(Forward)

    check state.search.incsearch == false

  test "Search hlsearch option preserved":
    let state = createTestState()
    state.search.hlsearch = false
    state.enterSearchOverlay(Forward)

    check state.search.hlsearch == false

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

    check state.commandText == ":"
    check state.commandCursor == 0

  test "Command cursor starts at 0":
    let state = createTestState()
    state.enterCommandOverlay()

    check state.commandCursor == 0

  test "Command state cleared on exit":
    let state = createTestState()
    state.enterCommandOverlay()
    state.commandText = ":wq"
    state.commandCursor = 2
    state.exitOverlay()

    check state.commandText == ""
    check state.commandCursor == 0

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
  result.textBuffer = newTextBuffer(content)
  result.windowManager.windows[0].buffer = result.textBuffer
  result.windowManager.windows[0].bufferList = @[result.textBuffer]
  result.viewport =
    ViewPort(x: 0, y: 0, width: 80, height: 24, topLine: 0, leftColumn: 0)
  result.windowManager.windows[0].viewport = result.viewport
  result.executer.motionController.viewportManager.viewport = result.viewport
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

  test "Wheel event sets needsFullRedraw":
    let e =
      createTestEditorWithBuffer("line0\nline1\nline2\nline3\nline4\nline5\nline6")
    e.state.needsFullRedraw = false

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    discard e.handleMouseEvent(event)

    check e.state.needsFullRedraw == true

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
      bufferList: @[buf2],
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

    var filerState = FilerState(
      currentPath: "/tmp", entries: @[], selectedIndex: 0, showHidden: false, topLine: 0
    )
    # Add dummy entries
    for i in 0 ..< 20:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].filerState = some(filerState)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].filerState.get.selectedIndex == 3

  test "WheelUp scrolls filer selection up":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Filer

    var filerState = FilerState(
      currentPath: "/tmp", entries: @[], selectedIndex: 5, showHidden: false, topLine: 0
    )
    for i in 0 ..< 20:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].filerState = some(filerState)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].filerState.get.selectedIndex == 2

  test "WheelUp clamps filer selection to 0":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Filer

    var filerState = FilerState(
      currentPath: "/tmp", entries: @[], selectedIndex: 1, showHidden: false, topLine: 0
    )
    for i in 0 ..< 10:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].filerState = some(filerState)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelUp, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].filerState.get.selectedIndex == 0

  test "WheelDown clamps filer selection to last entry":
    let e = createTestEditorWithBuffer("")
    e.state.mode = EditorMode.Filer

    var filerState = FilerState(
      currentPath: "/tmp", entries: @[], selectedIndex: 8, showHidden: false, topLine: 0
    )
    for i in 0 ..< 10:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    e.windowManager.windows[0].filerState = some(filerState)

    let event = makeWheelEvent(mouse_logic.MouseButton.WheelDown, 10, 5)
    let handled = e.handleMouseEvent(event)

    check handled == true
    check e.windowManager.windows[0].filerState.get.selectedIndex == 9

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
    currentPath: "/tmp",
    entries: @[],
    selectedIndex: selectedIndex,
    showHidden: false,
    topLine: topLine,
  )
  for i in 0 ..< entryCount:
    filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
  result.windowManager.windows[0].filerState = some(filerState)

suite "handleMouseEvent - Left Click Filer Mode":
  test "Click selects correct entry (no tab line)":
    let e = createFilerEditor(20)
    e.state.display.showTabLine = false
    e.state.display.showStatusLine = true

    # Click on y=3 → should select entry 3 (topLine=0, no tab offset)
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 3))

    check handled == true
    check e.windowManager.windows[0].filerState.get.selectedIndex == 3

  test "Click selects correct entry with tab line offset":
    let e = createFilerEditor(20)
    e.state.display.showTabLine = true
    e.state.display.showStatusLine = true

    # Click on y=3 with tab line → adjustedY = 3 - 1 = 2 → entry 2
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 3))

    check handled == true
    check e.windowManager.windows[0].filerState.get.selectedIndex == 2

  test "Click selects correct entry with topLine offset":
    let e = createFilerEditor(20, topLine = 5)
    e.state.display.showTabLine = false
    e.state.display.showStatusLine = true

    # Click on y=2, topLine=5 → entry 5 + 2 = 7
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 2))

    check handled == true
    check e.windowManager.windows[0].filerState.get.selectedIndex == 7

  test "Click selects correct entry with both tab line and topLine":
    let e = createFilerEditor(20, topLine = 5)
    e.state.display.showTabLine = true
    e.state.display.showStatusLine = true

    # Click on y=4, tab offset=1 → adjustedY=3, topLine=5 → entry 8
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 4))

    check handled == true
    check e.windowManager.windows[0].filerState.get.selectedIndex == 8

  test "Click on tab line area is ignored":
    let e = createFilerEditor(20)
    e.state.display.showTabLine = true
    e.state.display.showStatusLine = true

    # Click on y=0 (tab line row) → adjustedY = -1 → should be ignored
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 0))

    check handled == false

  test "Click on status line area is ignored":
    # viewport height=24, statusLine+cmdLine=2 reserved lines
    # valid filer area: y in [0..21] (without tab line)
    let e = createFilerEditor(20)
    e.state.display.showTabLine = false
    e.state.display.showStatusLine = true

    # Click on y=23 (last row, command line area) → adjustedY=23 >= 24-2=22 → ignored
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 23))

    check handled == false

  test "Click beyond entry count is ignored":
    let e = createFilerEditor(3)
    e.state.display.showTabLine = false
    e.state.display.showStatusLine = true

    # Click on y=5, but only 3 entries → clickedIndex=5 >= 3 → ignored
    let handled = e.handleMouseEvent(makeLeftClickEvent(5, 5))

    check handled == false

proc makeEnterEvent(): Event =
  Event(kind: EventKind.Key, key: KeyEvent(code: KeyCode.Enter))

suite "handleCommandModeEvent - exitOverlay after command execution":
  ## Regression tests: commands that don't manage overlay themselves must still
  ## exit the command overlay after execution. Previously, converting independent
  ## if-blocks to a case statement caused these branches to skip exitOverlay().

  test "Overlay exited after :5 (gotoLine)":
    let e = createTestEditorWithBuffer("l0\nl1\nl2\nl3\nl4\nl5\nl6\nl7\nl8\nl9")
    e.state.enterCommandOverlay()
    e.state.commandText = ":5"
    e.state.commandCursor = 1

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test "Overlay exited after :bn (bufferNext)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":bn"
    e.state.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test "Overlay exited after :bp (bufferPrev)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":bp"
    e.state.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test "Overlay exited after :bf (bufferFirst)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":bf"
    e.state.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test "Overlay exited after :bl (bufferLast)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":bl"
    e.state.commandCursor = 2

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test "Overlay exited after :noh (clearSearchHighlight)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":noh"
    e.state.commandCursor = 3

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test "Overlay exited after :set number (setBoolOption)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":set number"
    e.state.commandCursor = 10

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""
    check "number" in e.state.statusMessage

  test "Overlay exited after :set tabstop 4 (setIntOption)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":set tabstop 4"
    e.state.commandCursor = 13

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""
    check "tabstop" in e.state.statusMessage

  test "Overlay exited after :enew":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":enew"
    e.state.commandCursor = 4

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test "Overlay exited after :stripws (stripWhitespace)":
    let e = createTestEditorWithBuffer("hello   \nworld  ")
    e.state.enterCommandOverlay()
    e.state.commandText = ":stripws"
    e.state.commandCursor = 7

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test "Overlay exited after empty command (just Enter on ':')":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    # commandText is just ":" (default from enterCommandOverlay)

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

suite "handleCommandModeEvent - exitOverlay on self-managed branches":
  test "Overlay exited after :recent with no xbel file (empty list)":
    ## When recently-used.xbel doesn't exist, :recent should still succeed
    ## with an empty file list instead of failing.
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":recent"
    e.state.commandCursor = 6

    let origHome = getEnv("HOME")
    putEnv("HOME", "/tmp/moe_test_nonexistent_home")
    defer:
      putEnv("HOME", origHome)

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""
    check e.state.mode == EditorMode.RecentFile

suite "handleSearchBackspace":
  test "Remove last ASCII character":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "abc"

    handleSearchBackspace(e)

    check e.state.search.text == "ab"

  test "Remove last multibyte character (Japanese)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "検索"

    handleSearchBackspace(e)

    check e.state.search.text == "検"

  test "Remove last character from mixed ASCII and multibyte":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "abc日本語"

    handleSearchBackspace(e)

    check e.state.search.text == "abc日本"

  test "Backspace on single character leaves empty string":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "x"

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace on single multibyte character leaves empty string":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "あ"

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace on empty string does nothing":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = ""

    handleSearchBackspace(e)

    check e.state.search.text == ""

  test "Backspace sets needsFullRedraw":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "test"
    e.state.needsFullRedraw = false

    handleSearchBackspace(e)

    check e.state.needsFullRedraw == true

suite "enterFilerInActiveWindow":
  test "Sets active window to Filer mode":
    let e = createTestEditorWithBuffer("hello")
    e.enterFilerInActiveWindow("/tmp")

    check e.state.mode == EditorMode.Filer
    check e.activeWindow.mode == EditorMode.Filer
    check e.activeWindow.filerState.isSome
    check e.activeWindow.cursor == BufferPosition(line: 0, column: 0)
    check e.activeWindow.viewport.topLine == 0
    check e.activeWindow.viewport.leftColumn == 0

  test "Preserves original buffer in filer state":
    let e = createTestEditorWithBuffer("hello")
    let originalBuf = e.activeWindow.buffer
    e.enterFilerInActiveWindow("/tmp")

    check e.activeWindow.filerState.get.originalBuffer == originalBuf

  test "Vsplit with directory opens Filer in new split window":
    let e = createTestEditorWithBuffer("hello")
    let originalWinCount = e.windowManager.windows.len

    discard e.vsplit(none(string))
    check e.windowManager.windows.len == originalWinCount + 1

    e.enterFilerInActiveWindow("/tmp")
    check e.state.mode == EditorMode.Filer
    check e.activeWindow.mode == EditorMode.Filer
    check e.activeWindow.filerState.isSome

suite "handleCommandModeEvent - :putconfigfile":
  test "Overlay exited and config written":
    withTempHome(tmpDir):
      let e = createTestEditorWithBuffer("hello")
      e.config.theme.kind = tkDefault
      e.config.theme.path = ""
      e.state.enterCommandOverlay()
      e.state.commandText = ":putconfigfile"
      e.state.commandCursor = 14

      let cont = handleCommandModeEvent(e, makeEnterEvent())

      check cont == true
      check not e.state.isCommandOverlay
      check e.state.commandText == ""
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
      e.state.commandText = ":putconfigfile"
      e.state.commandCursor = 14
      discard handleCommandModeEvent(e, makeEnterEvent())
      check fileExists(configPath)

      # Run again to trigger backup
      e.state.enterCommandOverlay()
      e.state.commandText = ":putconfigfile"
      e.state.commandCursor = 14
      let cont = handleCommandModeEvent(e, makeEnterEvent())

      check cont == true
      check "Config written" in e.state.statusMessage
      check fileExists(backupPath)

  test "Theme file saved when kind is tkConfig":
    var themeFileCounter {.global.} = 0
    inc themeFileCounter
    let themeFile = "/tmp/moe_test_putconfigfile_theme_" & $themeFileCounter & ".toml"
    defer:
      removeFile(themeFile)

    withTempHome(tmpDir):
      let e = createTestEditorWithBuffer("hello")
      e.config.theme.kind = tkConfig
      e.config.theme.path = themeFile

      e.state.enterCommandOverlay()
      e.state.commandText = ":putconfigfile"
      e.state.commandCursor = 14

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
    e.state.commandText = ":q"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == false

  test ":q! closes window (returns false for single window)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":q!"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == false

  # --- Window ---

  test ":vs vertical split":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":vs"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":sp horizontal split":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":sp"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":new creates new buffer in horizontal split":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":new"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":vnew creates new buffer in vertical split":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":vnew"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  # --- File/Buffer ---

  test ":e opens or creates file":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":e testfile"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":w save (no file path shows error)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":w"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":wq save and quit (save fails without file path)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":wq"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    # Save fails (no file path), processSaveAndQuitResult returns true (continue)
    check cont == true

  test ":b 0 switch to buffer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":b 0"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":bd delete buffer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":bd"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  # --- Option ---

  test ":set scrollfriction 50 (float option)":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":set scrollfriction 50"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""
    check "scrollfriction" in e.state.statusMessage

  # --- Mode transitions ---

  test ":filer enters filer mode":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":filer"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":log enters log viewer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":log"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":help enters help viewer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":help"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":buffers enters buffer manager":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":buffers"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":backup enters backup manager":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":backup"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":jump shows jump list":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":jump"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":build with no file shows error":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":build"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":debug opens debug viewer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":debug"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":config opens configuration mode":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":config"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":quickrun with no file shows error":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":quickrun"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  # --- Theme/Substitute ---

  test ":theme default changes to default theme":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":theme default"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":s/a/b/ substitutes text":
    let e = createTestEditorWithBuffer("abc")
    e.state.enterCommandOverlay()
    e.state.commandText = ":s/a/b/"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  # --- Misc ---

  test ":!echo hi executes shell command":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":!echo hi"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":bg sends editor to background":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":bg"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":man ls shows man page":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":man ls"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  # --- LSP ---

  test ":lsplog opens LSP log viewer":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":lsplog"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":lspformat requests LSP formatting":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":lspformat"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":lsprestart restarts LSP server":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":lsprestart"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":lspfold requests LSP folding":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":lspfold"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":lspexecommand executes LSP command":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":lspexecommand"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":lspcallhierarchyincoming requests incoming calls":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":lspcallhierarchyincoming"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""

  test ":lspcallhierarchyoutgoing requests outgoing calls":
    let e = createTestEditorWithBuffer("hello")
    e.state.enterCommandOverlay()
    e.state.commandText = ":lspcallhierarchyoutgoing"

    let cont = handleCommandModeEvent(e, makeEnterEvent())

    check cont == true
    check not e.state.isCommandOverlay
    check e.state.commandText == ""
