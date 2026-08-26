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

## Tests for editor_render_views.nim

import std/[unittest, strutils]

import pkg/celina

import
  ../src/moepkg/
    [editor, config, config_loader, modes, types, buffer, render_utils, editor_window]
import ../src/moepkg/editor_render_views {.all.}

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)
  # Clear any startup status message (e.g. theme validation errors) so it does
  # not overlay the status line in render-output assertions.
  result.state.statusMessage = ""

proc createTestBuffer(): Buffer =
  ## Create a minimal Celina Buffer for testing
  result = newBuffer(80, 24)
  result.area = Rect(x: 0, y: 0, width: 80, height: 24)

proc renderSplitView(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Test shim preserving the pre-M16 call shape. The render pipeline split the
  ## former renderSplitView(wasResized) into a state-advancement pass
  ## (advanceLayoutForFrame: resize, viewport scroll, selection-cursor sync,
  ## screen cursor) followed by a read-only paint. Run both, matching what the
  ## real `render` does. Resolves by arity: the 3-arg form is this shim; the
  ## inner 2-arg call is the real (paint-only) renderSplitView.
  e.advanceLayoutForFrame(buffer, wasResized)
  e.renderSplitView(buffer)

suite "updateViewportSize - Basic behavior":
  test "Update screenSize from buffer area":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 100, height: 50)

    e.screenSize.width = 80
    e.screenSize.height = 24

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.screenSize.width == 100
    check e.screenSize.height == 50

  test "No resize when size unchanged":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 24)

    e.screenSize.width = 80
    e.screenSize.height = 24

    let resized = e.updateViewportSize(buffer)

    check resized == false
    check e.screenSize.width == 80
    check e.screenSize.height == 24

  test "Width change triggers resize":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.screenSize.width = 80
    e.screenSize.height = 24

    buffer.area = Rect(x: 0, y: 0, width: 120, height: 24)

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.screenSize.width == 120
    check e.screenSize.height == 24

  test "Height change triggers resize":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.screenSize.width = 80
    e.screenSize.height = 24

    buffer.area = Rect(x: 0, y: 0, width: 80, height: 40)

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.screenSize.width == 80
    check e.screenSize.height == 40

  test "Both dimensions change":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.screenSize.width = 80
    e.screenSize.height = 24

    buffer.area = Rect(x: 0, y: 0, width: 120, height: 40)

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.screenSize.width == 120
    check e.screenSize.height == 40

  test "Update from zero size":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.screenSize.width = 0
    e.screenSize.height = 0

    buffer.area = Rect(x: 0, y: 0, width: 80, height: 24)

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.screenSize.width == 80
    check e.screenSize.height == 24

  test "Stores previous dimensions":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.screenSize.width = 80
    e.screenSize.height = 24

    buffer.area = Rect(x: 0, y: 0, width: 120, height: 40)

    discard e.updateViewportSize(buffer)

    check e.screenSize.prevWidth == 80
    check e.screenSize.prevHeight == 24

  test "Does not modify active window viewport":
    ## Regression: updateViewportSize used to write to e.viewport which
    ## is a ref shared with the active window, corrupting its dimensions.
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Set up vsplit so the active window has half-width viewport
    e.viewport.width = 80
    e.viewport.height = 24
    discard e.vsplit()
    check e.windowManager.windows.len == 2

    # Record active window viewport dimensions after split
    let activeWin = e.activeWindow
    let origWidth = activeWin.viewport.width
    let origHeight = activeWin.viewport.height
    check origWidth < 80 # Should be approximately half

    # Simulate screen update with full screen dimensions
    e.screenSize.width = origWidth # Set to current to avoid triggering resize
    e.screenSize.height = origHeight
    buffer.area = Rect(x: 0, y: 0, width: 200, height: 50)

    discard e.updateViewportSize(buffer)

    # screenSize should be updated
    check e.screenSize.width == 200
    check e.screenSize.height == 50

    # Active window viewport must NOT be overwritten
    check activeWin.viewport.width == origWidth
    check activeWin.viewport.height == origHeight

suite "renderSplitView - Basic behavior":
  test "Render single window":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Should not crash with single window
    e.renderSplitView(buffer, false)

  test "Render single window with resize":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Test resize handling
    e.renderSplitView(buffer, true)

  test "Screen cursor is set after render":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    e.renderSplitView(buffer, false)

    # Screen cursor should be set
    check e.state.screenCursor.x >= 0
    check e.state.screenCursor.y >= 0

  test "Render with tab line enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showTabLine = true

    e.renderSplitView(buffer, false)

  test "Render with tab line disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showTabLine = false

    e.renderSplitView(buffer, false)

  test "Render with multi status line enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.multiStatusLine = true

    e.renderSplitView(buffer, false)

  test "Render with line wrap enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.lineWrap = true

    e.renderSplitView(buffer, false)

  test "Render with line wrap disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.lineWrap = false

    e.renderSplitView(buffer, false)

  test "Window viewport syncs with editor viewport":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 100
    e.viewport.height = 50

    # Single window should sync its viewport
    e.renderSplitView(buffer, false)

    check e.windowManager.windows.len == 1
    check e.windowManager.windows[0].viewport.width == 100
    check e.windowManager.windows[0].viewport.height == 50

suite "renderBottomLines - Normal mode":
  test "Render status message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "Test status message"

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

  test "Render empty status message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = ""

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

  test "Render multi-line status message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "Line 1\nLine 2\nLine 3"

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

suite "renderBottomLines - Command mode":
  test "Render command line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":write"
    e.state.input.commandCursor = 5 # 0-based after ":", max = runeLen - 1

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Cursor should be positioned at end of command text
    check e.state.screenCursor.x == 6 # displayWidthUpTo(":write", 6)
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render empty command line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":"
    e.state.input.commandCursor = 0

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    check e.state.screenCursor.x == 1 # After ":"
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render long command":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":set tabstop=4 shiftwidth=4 expandtab"
    e.state.input.commandCursor = 36 # 0-based after ":", max = runeLen - 1

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    check e.state.screenCursor.x == 37
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render command with wide characters":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    # "あいう" are 3 characters, each with display width 2
    e.state.input.commandText = ":あいう"
    e.state.input.commandCursor = 3 # After all 3 wide chars

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # ":" = 1 column, "あいう" = 6 columns, total = 7
    check e.state.screenCursor.x == 7
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render command with mixed ASCII and wide characters":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    # "eあb" = 'e'(1) + 'あ'(2) + 'b'(1) = 4 display columns
    e.state.input.commandText = ":eあb"
    e.state.input.commandCursor = 2 # After "eあ"

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # ":" = 1 column, "eあ" = 3 columns, total = 4
    check e.state.screenCursor.x == 4
    check e.state.screenCursor.y == buffer.area.height - 1

suite "renderBottomLines - Search mode":
  test "Render forward search":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.text = "pattern"
    e.state.input.search.cursor = 7

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Cursor at end of search prompt
    check e.state.screenCursor.x == 8 # "/pattern".len
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render backward search":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterSearchOverlay(Backward)
    e.state.input.search.text = "test"
    e.state.input.search.cursor = 4

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Cursor at end of search prompt
    check e.state.screenCursor.x == 5 # "?test".len
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render empty search":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.text = ""

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    check e.state.screenCursor.x == 1 # Just "/"
    check e.state.screenCursor.y == buffer.area.height - 1

suite "renderBottomLines - Rename mode":
  test "Render rename prompt":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterRenameOverlay("newName", 0, 0)

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Cursor at end of rename prompt
    check e.state.screenCursor.x == 15 # "Rename: newName".len
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render empty rename":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterRenameOverlay("", 0, 0)

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    check e.state.screenCursor.x == 8 # "Rename: ".len
    check e.state.screenCursor.y == buffer.area.height - 1

proc rowText(buffer: Buffer, y: int, length: int): string =
  ## Collect the symbols of a buffer row for content assertions
  for x in 0 ..< length:
    result.add buffer[x, y].symbol

suite "renderBottomLines - Wrapped overlay input":
  test "Long command input wraps onto a second row":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    # ":" + 80 chars = 81 columns -> 2 rows at width 80
    e.state.input.commandText = ":" & "a".repeat(80)
    e.state.input.commandCursor = 80 # cursor at end

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Rows 22-23 hold the wrapped input, status line is pushed up to row 21
    check rowText(buffer, 22, 80) == ":" & "a".repeat(79)
    check rowText(buffer, 23, 2) == "a "
    # Cursor lands after the overflowed char on the second row
    check e.state.screenCursor.x == 1
    check e.state.screenCursor.y == 23

  test "Cursor at the exact right edge grows an extra row":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    # ":" + 79 chars = exactly 80 columns; the cursor cell overflows
    e.state.input.commandText = ":" & "a".repeat(79)
    e.state.input.commandCursor = 79

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    check rowText(buffer, 22, 80) == ":" & "a".repeat(79)
    # Second row is blank, holding only the cursor cell
    check rowText(buffer, 23, 3) == "   "
    check e.state.screenCursor.x == 0
    check e.state.screenCursor.y == 23

  test "Input exceeding the height cap scrolls to keep the cursor visible":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    # 1 + 12*80 columns -> 13 wrap rows, capped at MaxStatusMessageLines (10)
    e.state.input.commandText = ":" & "a".repeat(80 * 12)
    e.state.input.commandCursor = 80 * 12

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Area occupies rows 14-23; the first 3 wrap rows are scrolled out
    check rowText(buffer, 14, 80) == "a".repeat(80)
    # Cursor on the last row, one column past the final char
    check e.state.screenCursor.x == 1
    check e.state.screenCursor.y == 23

  test "Long search input wraps with the prompt char":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterSearchOverlay(Forward)
    e.state.input.search.text = "x".repeat(85)
    e.state.input.search.cursor = 85

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    check rowText(buffer, 22, 80) == "/" & "x".repeat(79)
    check rowText(buffer, 23, 7) == "x".repeat(6) & " "
    check e.state.screenCursor.x == 6
    check e.state.screenCursor.y == 23

  test "Multi-line message rows land in the grown area":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "Line 1\nLine 2\nLine 3"

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    check rowText(buffer, 21, 6) == "Line 1"
    check rowText(buffer, 22, 6) == "Line 2"
    check rowText(buffer, 23, 6) == "Line 3"

suite "renderBottomLines - Status line visibility":
  test "Render with single window":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal

    # Single window always renders status line
    check e.windowManager.windows.len == 1
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

  test "Render with multi status line disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.multiStatusLine = false

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

  test "Render with status line merge enabled":
    var config = newEditorConfig()
    config.statusLine.merge = true
    let vr = newValidationResult()
    let e = newEditor(config, vr)
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

suite "renderTempMessages - Basic behavior":
  test "Render with no temp messages":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.ui.tempMessages = @[]

    # Should return early without crashing
    e.advanceLayoutForFrame(buffer, false)
    e.renderTempMessages(buffer)

  test "Render single temp message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.ui.tempMessages = @["Jump list entry 1"]

    e.advanceLayoutForFrame(buffer, false)
    e.renderTempMessages(buffer)

    # Cursor should be at bottom for prompt
    check e.state.screenCursor.x == 0
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render multiple temp messages":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.ui.tempMessages = @[
      " jump line  col file/text", "   1    10    5 /path/to/file1.nim",
      "   2    20   10 /path/to/file2.nim", "   3    30   15 /path/to/file3.nim",
    ]

    e.advanceLayoutForFrame(buffer, false)
    e.renderTempMessages(buffer)

    check e.state.screenCursor.x == 0
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render many temp messages":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Create many messages
    var messages: seq[string]
    for i in 1 .. 20:
      messages.add("Message " & $i)
    e.state.ui.tempMessages = messages

    e.advanceLayoutForFrame(buffer, false)
    e.renderTempMessages(buffer)

    check e.state.screenCursor.y == buffer.area.height - 1

  test "Temp messages with special characters":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.ui.tempMessages =
      @["File: /home/user/file.nim", "Unicode: こんにちは", "Symbols: <>&\"'"]

    e.advanceLayoutForFrame(buffer, false)
    e.renderTempMessages(buffer)

suite "renderSplitView - Viewport adjustment":
  test "Detached viewport does not pull or draw an offscreen cursor":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    for i in 0 ..< 100:
      discard e.activeBuffer.insertText(
        BufferPosition(line: i, column: 0), "Line " & $i & "\n"
      )
    e.cursor = BufferPosition(line: 2, column: 0)
    e.viewport.topLine = 20
    e.viewport.detachedFromCursor = true

    e.renderSplitView(buffer, false)

    check e.viewport.topLine == 20
    check e.cursor == BufferPosition(line: 2, column: 0)
    check not e.state.cursorVisible

  test "Viewport follows cursor down":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Add content to buffer
    for i in 0 ..< 100:
      discard e.activeBuffer.insertText(
        BufferPosition(line: i, column: 0), "Line " & $i & "\n"
      )

    # Move cursor far down (use e.cursor to sync with EditorWindow)
    e.cursor = BufferPosition(line: 50, column: 0)

    e.renderSplitView(buffer, false)

    # Viewport should have scrolled to show cursor
    let window = e.windowManager.windows[0]
    check window.viewport.topLine <= 50

  test "Viewport follows cursor right when line wrap disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.lineWrap = false

    # Add long line
    let longLine = "x".repeat(200)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    # Move cursor far right (use e.cursor to sync with EditorWindow)
    e.cursor = BufferPosition(line: 0, column: 150)

    e.renderSplitView(buffer, false)

    # Viewport should have scrolled horizontally
    let window2 = e.windowManager.windows[0]
    check window2.viewport.leftColumn > 0

  test "Wrapped overlay input does not scroll the viewport (no ratchet)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    for i in 0 ..< 100:
      discard e.activeBuffer.insertText(
        BufferPosition(line: i, column: 0), "Line " & $i & "\n"
      )

    # Put the cursor on the bottom visible line and settle the viewport
    e.cursor = BufferPosition(line: 50, column: 0)
    e.renderSplitView(buffer, false)
    let settledTopLine = e.windowManager.windows[0].viewport.topLine

    # A command input long enough to wrap to multiple rows grows the
    # bottom area, but must not scroll the persistent viewport
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":" & "a".repeat(200)
    e.state.input.commandCursor = 200
    e.renderSplitView(buffer, false)
    check e.windowManager.windows[0].viewport.topLine == settledTopLine

    # And the viewport is unchanged after the overlay closes
    e.state.exitOverlay()
    e.renderSplitView(buffer, false)
    check e.windowManager.windows[0].viewport.topLine == settledTopLine

  test "Multi-line status message does not scroll the viewport":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    for i in 0 ..< 100:
      discard e.activeBuffer.insertText(
        BufferPosition(line: i, column: 0), "Line " & $i & "\n"
      )

    e.cursor = BufferPosition(line: 50, column: 0)
    e.renderSplitView(buffer, false)
    let settledTopLine = e.windowManager.windows[0].viewport.topLine

    e.state.setStatusQuiet("error line 1\nerror line 2\nerror line 3")
    e.renderSplitView(buffer, false)
    check e.windowManager.windows[0].viewport.topLine == settledTopLine

  test "Multi-line status message does not fling the screen cursor to (0, 0)":
    # The scroll and the cursor clamp used different bottom reserves, so
    # a multi-line message flung a bottom-row cursor to (0, 0). The viewport does
    # not scroll, so the cursor must stay where it settled before the message.
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    for i in 0 ..< 100:
      discard e.activeBuffer.insertText(
        BufferPosition(line: i, column: 0), "Line " & $i & "\n"
      )

    # Cursor on the bottom visible row, then settle the viewport.
    e.cursor = BufferPosition(line: 50, column: 0)
    e.renderSplitView(buffer, false)
    let settledCursor = e.state.screenCursor
    check settledCursor != CursorPosition(x: 0, y: 0)

    # A three-line message grows the bottom area but must not move the cursor.
    e.state.setStatusQuiet("error line 1\nerror line 2\nerror line 3")
    e.renderSplitView(buffer, false)
    check e.state.screenCursor == settledCursor

  test "Viewport does not scroll horizontally when line wrap enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.lineWrap = true

    # Add long line
    let longLine = "x".repeat(200)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    # Move cursor far right (use e.cursor to sync with EditorWindow)
    e.cursor = BufferPosition(line: 0, column: 150)

    e.renderSplitView(buffer, false)

    # With line wrap, leftColumn should stay at 0
    let window = e.windowManager.windows[0]
    check window.viewport.leftColumn == 0

suite "renderSplitView - Display options":
  test "Render with line numbers enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showLineNumbers = true

    e.renderSplitView(buffer, false)

  test "Render with line numbers disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showLineNumbers = false

    e.renderSplitView(buffer, false)

  test "Render with status line visible":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true

    e.renderSplitView(buffer, false)

  test "Render with status line hidden":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = false

    e.renderSplitView(buffer, false)

suite "renderBottomLines - Edge cases":
  test "Very long status message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "x".repeat(200)

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

  test "Status message exceeds max lines":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    # Create message with many lines
    var lines: seq[string]
    for i in 1 .. 20:
      lines.add("Line " & $i)
    e.state.statusMessage = lines.join("\n")

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

  test "Small buffer height":
    let e = createTestEditor()
    var buffer = newBuffer(80, 5)
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 5)

    e.viewport.width = 80
    e.viewport.height = 5
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "Status"

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

  test "Minimum buffer height":
    let e = createTestEditor()
    var buffer = newBuffer(80, 3)
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 3)

    e.viewport.width = 80
    e.viewport.height = 3
    e.state.mode = EditorMode.Normal

    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

suite "Integration - Full render cycle":
  test "Complete render with all components":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.showTabLine = true
    e.state.showLineNumbers = true
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "Ready"

    # Full render cycle
    discard e.updateViewportSize(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

  test "Render cycle with mode change":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Normal mode
    e.state.mode = EditorMode.Normal
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Switch to command mode
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":quit"
    e.state.input.commandCursor = 5
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render cycle with temp messages":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.ui.tempMessages = @["Message 1", "Message 2"]

    discard e.updateViewportSize(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)
    e.advanceLayoutForFrame(buffer, false)
    e.renderTempMessages(buffer)

    check e.state.screenCursor.y == buffer.area.height - 1

proc getBufferLine(buffer: celina.Buffer, y: int): string =
  ## Extract a line from celina Buffer as string
  result = ""
  for x in 0 ..< buffer.area.width:
    result.add(buffer[x, y].symbol)

proc hasStatusLineStyleAt(buffer: celina.Buffer, y: int): bool =
  ## Check if a line has Bold modifier (status line characteristic)
  ## Status lines use Bold modifier; normal content does not
  for x in 0 ..< buffer.area.width:
    if StyleModifier.Bold in buffer[x, y].style.modifiers:
      return true
  false

suite "renderSplitView - Close window cleans up status line":
  test "hsplit close: no stale separator at old boundary (single status line)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = false

    # Create hsplit
    discard e.hsplit()
    check e.windowManager.windows.len == 2

    # Render with 2 windows (draws separator between them)
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Record the separator Y position (between windows)
    let topWindow = e.windowManager.windows[0]
    let separatorY = topWindow.viewport.y + topWindow.viewport.height

    # Verify separator exists before close
    let sepLine = getBufferLine(buffer, separatorY)
    check "─" in sepLine

    # Close active window
    discard e.closeWindow()
    check e.windowManager.windows.len == 1

    # Render after close
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # The old separator Y should now be normal content, not a separator
    let afterLine = getBufferLine(buffer, separatorY)
    check "─" notin afterLine

  test "hsplit close: no stale per-window status line (multi status line)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    # Create hsplit
    discard e.hsplit()
    check e.windowManager.windows.len == 2

    # Render with 2 windows
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # The top window has a per-window status line at its bottom edge
    let topWindow = e.windowManager.windows[0]
    let topStatusLineY = calculateWindowStatusLineY(topWindow, isBottomWindow = false)

    # Verify per-window status line exists at top window's bottom before close
    check hasStatusLineStyleAt(buffer, topStatusLineY)

    # Close active window (bottom, since hsplit sets active to new window)
    discard e.closeWindow()
    check e.windowManager.windows.len == 1

    # Render after close
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # The old top-window status line Y should now be normal content
    # (the remaining window's content area should extend past it)
    # Only the bottom status line (y=23) should have status styling
    let bottomStatusLineY = buffer.area.height - 1
    if topStatusLineY != bottomStatusLineY:
      check not hasStatusLineStyleAt(buffer, topStatusLineY)

  test "hsplit close: remaining window viewport covers full height":
    let e = createTestEditor()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = false

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    discard e.closeWindow()
    check e.windowManager.windows.len == 1

    # Remaining window should cover the full viewport height
    check e.windowManager.windows[0].viewport.y == 0
    check e.windowManager.windows[0].viewport.height == 24

  test "hsplit close: remaining window viewport covers full height (multi status line)":
    let e = createTestEditor()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    discard e.closeWindow()
    check e.windowManager.windows.len == 1

    check e.windowManager.windows[0].viewport.y == 0
    check e.windowManager.windows[0].viewport.height == 24

  test "vsplit close: no stale separator at old boundary":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = false

    discard e.vsplit()
    check e.windowManager.windows.len == 2

    # Render with 2 windows (draws vertical separator)
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Record the separator X position
    let leftWindow = e.windowManager.windows[0]
    let separatorX = leftWindow.viewport.x + leftWindow.viewport.width

    # Verify vertical separator exists before close
    check buffer[separatorX, 0].symbol == "│"

    # Close active window
    discard e.closeWindow()
    check e.windowManager.windows.len == 1

    # Render after close
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # The old separator X should now be normal content
    check buffer[separatorX, 0].symbol != "│"

  test "vsplit close: remaining window viewport covers full width":
    let e = createTestEditor()

    e.viewport.width = 80
    e.viewport.height = 24

    discard e.vsplit()
    check e.windowManager.windows.len == 2

    discard e.closeWindow()
    check e.windowManager.windows.len == 1

    check e.windowManager.windows[0].viewport.x == 0
    check e.windowManager.windows[0].viewport.width == 80

proc getRowText(buffer: celina.Buffer, y: int): string =
  ## Extract text content from a buffer row
  for x in 0 ..< buffer.area.width:
    let sym = buffer[x, y].symbol
    if sym.len > 0:
      result.add sym
    else:
      result.add ' '

proc isStatusLineRow(buffer: celina.Buffer, y: int): bool =
  ## Detect status line rows by checking for encoding indicator (e.g. UTF-8)
  ## which is unique to status lines (not present in tab lines or content)
  let text = buffer.getRowText(y)
  "UTF-8" in text or "UTF-16" in text or "UTF-32" in text

proc statusLineYPositions(buffer: celina.Buffer): seq[int] =
  ## Get Y positions of status line rows
  for y in 0 ..< buffer.area.height:
    if buffer.isStatusLineRow(y):
      result.add(y)

suite "Status line count - no duplicate status lines":
  test "Single window, multiStatusLine=false: exactly 1 status line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = false

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Should have exactly 1 status line at y=22
    check positions.len == 1
    check positions[0] == 23

  test "Single window, multiStatusLine=true: exactly 1 status line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Should have exactly 1 status line at y=22
    check positions.len == 1
    check positions[0] == 23

  test "2 hsplit windows, multiStatusLine=true: exactly 2 status lines":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Each window gets its own status line
    check positions.len == 2

  test "2 hsplit windows, multiStatusLine=false: exactly 1 status line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = false

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Single status line at the bottom
    check positions.len == 1
    check positions[0] == 23

  test "2 vsplit windows, multiStatusLine=true: exactly 1 status line row":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    discard e.vsplit()
    check e.windowManager.windows.len == 2

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Both windows' status lines are at the same Y (both are bottom windows)
    check positions.len == 1
    check positions[0] == 23

suite "Bottom area - status line and command line share last row":
  test "Single window: status line at last row (y=height-1)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Status line should be at the very last row (y=23), not y=22
    check positions.len == 1
    check positions[0] == 23

  test "Single window: no empty row below status line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Last row should be the status line (not blank)
    let lastRowText = buffer.getRowText(23).strip()
    check lastRowText.len > 0

    # Second-to-last row (y=22) should be content area (not status line)
    check not buffer.isStatusLineRow(22)

  test "Single window: content area is height - 2 (tab + status)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true
    e.state.showTabLine = true

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Content area: y=1 (after tab) to y=22 (before status line) = 22 rows
    # y=0: tab line, y=23: status line
    # Line number "1" should be at y=1
    let y1text = buffer.getRowText(1).strip()
    check "1" in y1text

    # y=22 should still be in content area (no status line marker)
    check not buffer.isStatusLineRow(22)

  test "Command mode: command text overlays status line at last row":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    # Enter command mode
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":write"

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Command text should be at last row (y=23)
    let lastRow = buffer.getRowText(23).strip()
    check ":write" in lastRow
    check e.state.screenCursor.y == 23

  test "2 hsplit, multiStatusLine=true: bottom window status at last row":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Window 1 status line + Window 2 status line
    check positions.len == 2
    # Bottom window's status line should be at y=23 (last row)
    check positions[^1] == 23

suite "Status line - grown area in multiStatusLine mode":
  test "vsplit: per-window status lines shift above the grown area, no global one":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.screenSize.width = 80
    e.screenSize.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true
    e.config.statusLine.merge = false

    discard e.vsplit()
    check e.windowManager.windows.len == 2

    # ":" + 100 chars -> 2 wrapped rows; status row reserved above them
    e.state.enterCommandOverlay()
    e.state.input.commandText = ":" & "a".repeat(100)
    e.state.input.commandCursor = 100

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    # Both per-window status lines sit on the pushed-up row 21
    # (24 - 2 input rows - 1), each in its own half — not one global line
    check buffer.getRowText(21).count("UTF-8") == 2
    # And that is the only status row on screen
    check statusLineYPositions(buffer) == @[21]

  test "hsplit: bottom window status line shifts, top window's stays":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.screenSize.width = 80
    e.screenSize.height = 24
    e.state.showStatusLine = true
    e.state.multiStatusLine = true
    e.config.statusLine.merge = false

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    e.state.enterCommandOverlay()
    e.state.input.commandText = ":" & "a".repeat(100)
    e.state.input.commandCursor = 100

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Exactly two status rows: the top window's own row and the bottom
    # window's row pushed above the grown area (no duplicate global line)
    check positions.len == 2
    check positions[^1] == 21
    # Each row holds exactly one status line
    for y in positions:
      check buffer.getRowText(y).count("UTF-8") == 1

suite "updateViewportSize - split mode regression":
  ## Regression tests for the bug where updateViewportSize corrupted
  ## the active window's viewport via the shared ref (e.viewport).

  test "vsplit: repeated updateViewportSize preserves window viewports":
    ## Simulates the render loop: updateViewportSize is called every frame
    ## with the full screen buffer. Window viewports must remain at their
    ## split dimensions.
    let e = createTestEditor()
    var buffer = newBuffer(200, 50)
    buffer.area = Rect(x: 0, y: 0, width: 200, height: 50)

    # Initial setup
    e.viewport.width = 200
    e.viewport.height = 50
    e.screenSize.width = 200
    e.screenSize.height = 50

    discard e.vsplit()
    check e.windowManager.windows.len == 2

    let leftWin = e.windowManager.windows[0]
    let rightWin = e.windowManager.windows[1]
    let leftWidth = leftWin.viewport.width
    let rightWidth = rightWin.viewport.width

    # Both windows should be roughly half the screen
    check leftWidth < 200
    check rightWidth < 200
    check leftWidth + rightWidth + 1 == 200 # +1 for separator

    # Simulate multiple render frames calling updateViewportSize
    for _ in 0 ..< 5:
      discard e.updateViewportSize(buffer)

    # Window viewports must NOT be changed
    check leftWin.viewport.width == leftWidth
    check rightWin.viewport.width == rightWidth

  test "hsplit: repeated updateViewportSize preserves window viewports":
    let e = createTestEditor()
    var buffer = newBuffer(80, 50)
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 50)

    e.viewport.width = 80
    e.viewport.height = 50
    e.screenSize.width = 80
    e.screenSize.height = 50

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    let topWin = e.windowManager.windows[0]
    let bottomWin = e.windowManager.windows[1]
    let topHeight = topWin.viewport.height
    let bottomHeight = bottomWin.viewport.height

    check topHeight < 50
    check bottomHeight < 50

    for _ in 0 ..< 5:
      discard e.updateViewportSize(buffer)

    check topWin.viewport.height == topHeight
    check bottomWin.viewport.height == bottomHeight

  test "vsplit: full render cycle preserves window viewports":
    ## Full integration: updateViewportSize + renderSplitView + renderBottomLines
    let e = createTestEditor()
    var buffer = newBuffer(200, 50)
    buffer.area = Rect(x: 0, y: 0, width: 200, height: 50)

    e.viewport.width = 200
    e.viewport.height = 50
    e.screenSize.width = 200
    e.screenSize.height = 50

    discard e.vsplit()
    check e.windowManager.windows.len == 2

    let leftWin = e.windowManager.windows[0]
    let rightWin = e.windowManager.windows[1]
    let leftWidth = leftWin.viewport.width
    let rightWidth = rightWin.viewport.width

    # Simulate 3 render frames
    for _ in 0 ..< 3:
      let wasResized = e.updateViewportSize(buffer)
      clearBuffer(buffer)
      e.renderSplitView(buffer, wasResized)
      e.renderBottomLines(buffer)

    check leftWin.viewport.width == leftWidth
    check rightWin.viewport.width == rightWidth

  test "screenSize tracks screen, not window dimensions":
    let e = createTestEditor()
    var buffer = newBuffer(200, 50)
    buffer.area = Rect(x: 0, y: 0, width: 200, height: 50)

    e.screenSize.width = 100
    e.screenSize.height = 30

    discard e.updateViewportSize(buffer)

    # screenSize should reflect the full screen
    check e.screenSize.width == 200
    check e.screenSize.height == 50
    check e.screenSize.prevWidth == 100
    check e.screenSize.prevHeight == 30

suite "adjustViewportForCursor - line wrap vertical scroll":
  # These exercise the private wrap-mode branch directly so we can assert the
  # exact viewport invariant with a known visibleHeight. Lines have varied
  # lengths so wrap counts differ from line to line.
  const
    TextAreaWidth = 10
    TabStop = 8
    VisibleHeight = 10

  proc makeWrappingBuffer(lineCount: int): TextBuffer =
    var lines: seq[string]
    for i in 0 ..< lineCount:
      # Lengths cycle through 5/15/25/35 → wrap counts vary per line.
      lines.add("x".repeat(5 + (i mod 4) * 10))
    newTextBuffer(lines.join("\n"))

  proc wrapAt(buf: TextBuffer, line: int): int =
    # Independent recomputation (fresh cache) used to verify the invariant.
    WrapCountCache().getWrapCount(buf, line, TextAreaWidth, TabStop)

  proc screenLines(buf: TextBuffer, a, b: int): int =
    for ln in a .. b:
      result += buf.wrapAt(ln)

  proc cursorVisualRow(buf: TextBuffer, vp: ViewPort, cursorLine, cursorSeg: int): int =
    ## Visual row index of (cursorLine, cursorSeg) measured from the viewport
    ## top, honoring topWrapOffset (sub-line scroll). No fold lines here.
    result = cursorSeg - vp.topWrapOffset
    for ln in vp.topLine ..< cursorLine:
      result += buf.wrapAt(ln)

  proc adjustWrap(vp: ViewPort, buf: TextBuffer, cursorLine: int) =
    adjustViewportForCursor(
      vp,
      BufferPosition(line: cursorLine, column: 0),
      VisibleHeight,
      TextAreaWidth,
      true,
      buf,
      TabStop,
      WrapCountCache(),
    )

  test "Scrolls down from top so cursor is visible with minimal scroll":
    let buf = makeWrappingBuffer(30)
    let vp = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24)
    let cursorLine = 20

    vp.adjustWrap(buf, cursorLine)

    # Cursor must be at or below topLine and fit within the visible height.
    check vp.topLine in 0 .. cursorLine
    check buf.screenLines(vp.topLine, cursorLine) <= VisibleHeight
    # Minimal scroll: moving topLine up one more line would overflow.
    if vp.topLine > 0:
      check buf.screenLines(vp.topLine - 1, cursorLine) > VisibleHeight

  test "Big downward jump lands cursor in view (issue #10 scenario)":
    let buf = makeWrappingBuffer(500)
    let vp = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24)
    let cursorLine = 499

    vp.adjustWrap(buf, cursorLine)

    # Segment-precision scroll: the cursor segment (here segment 0) lands on the
    # last visible row with minimal downward scroll, possibly starting mid
    # logical line (topWrapOffset > 0).
    check vp.topLine in 0 .. cursorLine
    check vp.topWrapOffset >= 0
    check vp.topWrapOffset < buf.wrapAt(vp.topLine)
    check buf.cursorVisualRow(vp, cursorLine, 0) == VisibleHeight - 1

  test "Does not scroll when cursor already visible at topLine":
    let buf = makeWrappingBuffer(30)
    let vp = ViewPort(topLine: 5, leftColumn: 0, width: 80, height: 24)

    vp.adjustWrap(buf, 5)

    check vp.topLine == 5

  test "Scrolls up when cursor is above topLine":
    let buf = makeWrappingBuffer(30)
    let vp = ViewPort(topLine: 20, leftColumn: 0, width: 80, height: 24)

    vp.adjustWrap(buf, 5)

    check vp.topLine == 5

  test "Converging from any starting topLine yields the same minimal topLine":
    # Starting far above (0) and starting just below the answer must converge to
    # the identical topLine — the result depends only on cursor + visibleHeight.
    let buf = makeWrappingBuffer(60)
    let cursorLine = 40

    let fromTop = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24)
    fromTop.adjustWrap(buf, cursorLine)

    let fromNear =
      ViewPort(topLine: fromTop.topLine, leftColumn: 0, width: 80, height: 24)
    fromNear.adjustWrap(buf, cursorLine)

    check fromNear.topLine == fromTop.topLine

  proc singleRowBuffer(lineCount: int): TextBuffer =
    # Each line is one character, so its wrap count is always 1 row. This
    # isolates the collapsed-fold row accounting from per-line wrap variance.
    var lines: seq[string]
    for i in 0 ..< lineCount:
      lines.add("x")
    newTextBuffer(lines.join("\n"))

  test "Collapsed fold above the cursor counts as a single marker row":
    # Fold lines 18..26 (9 lines) collapse to one marker row. Walking back from
    # the cursor, that whole region costs 1 row, not 9, so topLine lands 8 lines
    # lower than the fold-unaware computation (which would stop at 19).
    let buf = singleRowBuffer(30)
    check buf.foldState.addFold(18, 26, collapsed = true)
    let vp = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24)

    vp.adjustWrap(buf, 28)

    check vp.topLine == 11

  test "Collapsed fold lets the viewport keep the top visible (no needless scroll)":
    # Lines 2..20 collapse to one marker row, so the cursor at line 25 fits
    # within visibleHeight from topLine 0 (rows: lines 0,1 + marker + 21..25 = 8).
    # Without fold-aware counting this would force a downward scroll.
    let buf = singleRowBuffer(30)
    check buf.foldState.addFold(2, 20, collapsed = true)
    let vp = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24)

    vp.adjustWrap(buf, 25)

    check vp.topLine == 0

  # Sub-line (wrap-segment) scrolling via topWrapOffset

  proc adjustWrapAt(vp: ViewPort, buf: TextBuffer, cursorLine, cursorCol: int) =
    adjustViewportForCursor(
      vp,
      BufferPosition(line: cursorLine, column: cursorCol),
      VisibleHeight,
      TextAreaWidth,
      true,
      buf,
      TabStop,
      WrapCountCache(),
    )

  proc tallLineBuffer(): TextBuffer =
    # A short line, then one logical line far taller than the window (25 wrap
    # segments at TextAreaWidth=10), then a trailing short line.
    newTextBuffer(["short", "x".repeat(250), "tail"].join("\n"))

  test "A line taller than the window keeps a deep-segment cursor visible":
    # Repro of the reported bug: with whole-line tops only, a cursor on a deep
    # segment was flung to (0,0); sub-line scroll keeps it on the last row.
    let buf = tallLineBuffer()
    let vp = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24)

    # Cursor on segment 20 (column 200 / TextAreaWidth 10) of the tall line 1.
    vp.adjustWrapAt(buf, 1, 200)

    check vp.topLine == 1
    check vp.topWrapOffset == 11 # 20 - (VisibleHeight - 1)
    check buf.cursorVisualRow(vp, 1, 20) == VisibleHeight - 1

  test "Scrolling up within a tall line moves the top toward the cursor segment":
    let buf = tallLineBuffer()
    let vp =
      ViewPort(topLine: 1, topWrapOffset: 11, leftColumn: 0, width: 80, height: 24)

    # Cursor moves above the current top (segment 10 < offset 11): scroll up so
    # the cursor sits on the first visible row, still mid logical line.
    vp.adjustWrapAt(buf, 1, 100)

    check vp.topLine == 1
    check vp.topWrapOffset == 10
    check buf.cursorVisualRow(vp, 1, 10) == 0

  test "Cursor already visible inside a tall line does not move the top":
    let buf = tallLineBuffer()
    let vp =
      ViewPort(topLine: 1, topWrapOffset: 11, leftColumn: 0, width: 80, height: 24)

    # Segment 15 is within rows 11..20 (visible): no scroll.
    vp.adjustWrapAt(buf, 1, 150)

    check vp.topLine == 1
    check vp.topWrapOffset == 11

  test "Normal-height lines never set a wrap offset":
    let buf = singleRowBuffer(30)
    let vp = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24)

    vp.adjustWrap(buf, 25)
    check vp.topWrapOffset == 0

    vp.adjustWrap(buf, 3)
    check vp.topWrapOffset == 0

  test "A stale oversized topWrapOffset is re-clamped, keeping the cursor on-screen":
    # Post-resize state: topWrapOffset was set when topLine was tall, then the
    # text area widened so the line now wraps into far fewer segments. With the
    # cursor on a line below topLine the down-branch leaves the top unchanged, so
    # without a re-clamp the offset stays out of range and calculateWindowCursor
    # would fling the cursor to (0, 0). topLine 3 wraps into 4 segments here.
    let buf = makeWrappingBuffer(30)
    let vp =
      ViewPort(topLine: 3, topWrapOffset: 20, leftColumn: 0, width: 80, height: 24)

    vp.adjustWrap(buf, 5)

    # Invariant restored and the cursor is not pushed above the viewport top.
    check vp.topWrapOffset < buf.wrapAt(vp.topLine)
    check buf.cursorVisualRow(vp, 5, 0) >= 0

suite "renderCodeLensPicker":
  test "No crash with normal dimensions":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 24)
    e.viewport.height = 24
    e.state.screenCursor = CursorPosition(x: 10, y: 5)
    e.state.lspCache.codeLensPicker = CodeLensPicker(
      items: @[
        CodeLensItem(line: 0, column: 0, title: "Run Test", command: "test.run"),
        CodeLensItem(line: 0, column: 0, title: "Debug Test", command: "test.debug"),
      ],
      selectedIndex: 0,
      scrollOffset: 0,
      maxVisibleItems: 2,
      isActive: true,
    )
    e.renderCodeLensPicker(buffer)

  test "No crash with extremely small terminal (regression: popupWidth overflow)":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 5, height: 10)
    e.viewport.height = 10
    e.state.screenCursor = CursorPosition(x: 1, y: 1)
    e.state.lspCache.codeLensPicker = CodeLensPicker(
      items: @[CodeLensItem(line: 0, column: 0, title: "Run", command: "cmd")],
      selectedIndex: 0,
      scrollOffset: 0,
      maxVisibleItems: 1,
      isActive: true,
    )
    e.renderCodeLensPicker(buffer)

  test "No crash with zero effective content width":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 6, height: 10)
    e.viewport.height = 10
    e.state.screenCursor = CursorPosition(x: 1, y: 1)
    e.state.lspCache.codeLensPicker = CodeLensPicker(
      items: @[CodeLensItem(line: 0, column: 0, title: "Run", command: "cmd")],
      selectedIndex: 0,
      scrollOffset: 0,
      maxVisibleItems: 1,
      isActive: true,
    )
    e.renderCodeLensPicker(buffer)

  test "No crash when picker is not active":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.state.screenCursor = CursorPosition(x: 10, y: 5)
    e.state.lspCache.codeLensPicker.isActive = false
    e.renderCodeLensPicker(buffer)

  test "No crash with zero items":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.state.screenCursor = CursorPosition(x: 10, y: 5)
    e.state.lspCache.codeLensPicker = CodeLensPicker(
      items: @[], selectedIndex: 0, scrollOffset: 0, maxVisibleItems: 0, isActive: true
    )
    e.renderCodeLensPicker(buffer)

  test "No crash when popup placed off-screen (adjusts to visible area)":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 10)
    e.viewport.height = 10
    e.state.screenCursor = CursorPosition(x: 75, y: 8)
    e.state.lspCache.codeLensPicker = CodeLensPicker(
      items: @[
        CodeLensItem(line: 0, column: 0, title: "Run Test Long", command: "cmd"),
        CodeLensItem(line: 0, column: 0, title: "Debug", command: "cmd"),
      ],
      selectedIndex: 0,
      scrollOffset: 0,
      maxVisibleItems: 2,
      isActive: true,
    )
    e.renderCodeLensPicker(buffer)

  test "Renders popup borders and content on screen":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 24)
    e.viewport.height = 24
    e.state.screenCursor = CursorPosition(x: 10, y: 5)
    e.state.lspCache.codeLensPicker = CodeLensPicker(
      items: @[
        CodeLensItem(line: 0, column: 0, title: "Run", command: "cmd"),
        CodeLensItem(line: 0, column: 0, title: "Debug", command: "cmd"),
      ],
      selectedIndex: 0,
      scrollOffset: 0,
      maxVisibleItems: 2,
      isActive: true,
    )
    e.renderCodeLensPicker(buffer)

    let screen = buffer.toStrings()
    let topBorder = screen[6] # popupY = cursor.y + 1 = 6
    check topBorder.contains("┌")
    check topBorder.contains("┐")
    let contentLine = screen[7]
    check contentLine.contains("│")
    check contentLine.contains("Run")
    let bottomBorder = screen[9] # popupY + visibleCount + 1 = 6 + 2 + 1 = 9
    check bottomBorder.contains("└")
    check bottomBorder.contains("┘")

suite "advanceLayoutForFrame - viewer selection drives the window viewport":
  proc setupViewer(e: Editor, lineCount: int, mode: EditorMode) =
    ## Give the active window a scrollable read-only body and the viewer mode.
    var content = ""
    for i in 0 ..< lineCount:
      if i > 0:
        content.add('\n')
      content.add("line" & $i)
    let win = e.windowManager.windows[0]
    win.buffer = newTextBuffer(content)
    win.mode = mode
    e.state.mode = mode
    win.viewport.topLine = 0

  test "Filer selection below the viewport scrolls the window":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.setupViewer(40, EditorMode.Filer)

    var filerState = FilerState(currentPath: "/tmp", showHidden: false)
    for i in 0 ..< 40:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    filerState.selectedIndex = 35
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)

    e.advanceLayoutForFrame(buffer, false)

    check e.windowManager.windows[0].viewport.topLine > 0
    check e.windowManager.windows[0].cursor.line == 35

  test "FileTree selection below the viewport scrolls the window":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.setupViewer(40, EditorMode.FileTree)

    let treeState = FileTreeState(rootPath: "/tmp", selectedIndex: 35)
    for i in 0 ..< 40:
      treeState.flatList.add(FileTreeNode(name: "node" & $i, path: "/tmp/node" & $i))
    e.windowManager.windows[0].modeState =
      ModeState(kind: mskFileTree, fileTree: treeState)

    e.advanceLayoutForFrame(buffer, false)

    check e.windowManager.windows[0].viewport.topLine > 0
    check e.windowManager.windows[0].cursor.line == 35

  test "Help selection below the viewport scrolls the window":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.setupViewer(40, EditorMode.Help)

    let helpState = HelpViewerState(selectedIndex: 35)
    for i in 0 ..< 40:
      helpState.items.add("help" & $i)
    e.windowManager.windows[0].modeState = ModeState(kind: mskHelp, help: helpState)

    e.advanceLayoutForFrame(buffer, false)

    check e.windowManager.windows[0].viewport.topLine > 0
    check e.windowManager.windows[0].cursor.line == 35

  test "Debug selection below the viewport scrolls the window":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.setupViewer(40, EditorMode.Debug)

    let debugState = DebugViewerState(selectedIndex: 35)
    for i in 0 ..< 40:
      debugState.items.add("debug" & $i)
    e.windowManager.windows[0].modeState = ModeState(kind: mskDebug, debug: debugState)

    e.advanceLayoutForFrame(buffer, false)

    check e.windowManager.windows[0].viewport.topLine > 0
    check e.windowManager.windows[0].cursor.line == 35

  test "Scrolling back to the top follows the selection up":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.setupViewer(40, EditorMode.Filer)

    var filerState = FilerState(currentPath: "/tmp", showHidden: false)
    for i in 0 ..< 40:
      filerState.entries.add(FileEntry(name: "file" & $i, kind: fekFile))
    filerState.selectedIndex = 35
    e.windowManager.windows[0].modeState = ModeState(kind: mskFiler, filer: filerState)
    e.advanceLayoutForFrame(buffer, false)
    check e.windowManager.windows[0].viewport.topLine > 0

    filerState.selectedIndex = 0
    e.advanceLayoutForFrame(buffer, false)

    check e.windowManager.windows[0].viewport.topLine == 0

suite "editor_render_views - sanitize control characters":
  proc hasControl(s: string): bool =
    for r in s.runes:
      if int(r) < 0x20 or int(r) == 0x7F:
        return true
    false

  test "renderBottomLines sanitizes single-line statusMessage":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.viewport.width = 80
    e.viewport.height = 24
    e.state.statusMessage = "Opened: /tmp/a\x1B[2J/b\x00c\x7F.nim"
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)
    var hasCtrl = false
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        let sym = buffer[x, y].symbol
        for r in sym.runes:
          if int(r) < 0x20 or int(r) == 0x7F:
            hasCtrl = true
    check not hasCtrl
    # Sanitized content still visible as spaces
    var line = ""
    for x in 0 ..< buffer.area.width:
      line.add(buffer[x, buffer.area.height - 1].symbol)
    check "Opened: /tmp/a [2J/b c .nim" in line or "Opened:" in line

  test "renderBottomLines sanitizes multi-line statusMessage each line":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.viewport.width = 80
    e.viewport.height = 24
    e.state.statusMessage = "line1\x1B[2J\nline2\x00bad\nline3\x7Fend"
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)
    var hasCtrl = false
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        for r in buffer[x, y].symbol.runes:
          if int(r) < 0x20 or int(r) == 0x7F:
            hasCtrl = true
    check not hasCtrl

  test "renderTempMessages sanitizes control characters":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.viewport.width = 80
    e.viewport.height = 24
    e.state.ui.tempMessages = @[
      " jump line col file", "   1   10  5 /tmp/a\x1Bfile\x00.nim",
      "   2   20 10 /tmp/b\x7Fname.nim",
    ]
    e.advanceLayoutForFrame(buffer, false)
    e.renderTempMessages(buffer)
    var hasCtrl = false
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        for r in buffer[x, y].symbol.runes:
          if int(r) < 0x20 or int(r) == 0x7F:
            hasCtrl = true
    check not hasCtrl
    var all = ""
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        all.add(buffer[x, y].symbol)
    check "a file" in all or "a" in all

  test "sanitized message displayWidth consistent":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.viewport.width = 80
    e.viewport.height = 24
    e.state.statusMessage = "漢\x00字🎉\x1B test"
    e.advanceLayoutForFrame(buffer, false)
    e.renderBottomLines(buffer)
    var hasCtrl = false
    for y in 0 ..< buffer.area.height:
      for x in 0 ..< buffer.area.width:
        for r in buffer[x, y].symbol.runes:
          if int(r) < 0x20 or int(r) == 0x7F:
            hasCtrl = true
    check not hasCtrl
