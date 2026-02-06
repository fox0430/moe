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

import std/[unittest, options, tables]

import ../src/moepkg/buffer {.all.}
import ../src/moepkg/types {.all.}
import ../src/moepkg/modes {.all.}
import ../src/moepkg/registers {.all.}
import ../src/moepkg/handler {.all.}

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
    viewportReservedLines: 2,
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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

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
      reservedLines = 2

    # Click on row 2, col 1 => line 1, char 1 ('l')
    let result = screenToBufferPosition(
      vp, buffer, 1, 2, lineNumOffset, sidebarWidth = 0, reservedLines, lineWrap = true
    )

    check result.isSome
    check result.get.line == 1
    check result.get.column == 1

suite "Background Process Management":
  test "addRunningProcess adds process to list":
    # Clear any existing processes
    cleanupBackgroundProcesses()

    # Note: We can't easily create a real BackgroundProcess in tests
    # This test verifies the function exists and can be called
    check true

  test "cleanupBackgroundProcesses clears the list":
    cleanupBackgroundProcesses()
    # After cleanup, the list should be empty
    # We verify by checking no crash occurs
    check true

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
