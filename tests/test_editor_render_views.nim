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
import ../src/moepkg/[editor, config, config_loader, modes, types, buffer, render_utils]
import ../src/moepkg/editor_render_views
import ../src/moepkg/editor_window

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
    e.state.display.showTabLine = true

    e.renderSplitView(buffer, false)

  test "Render with tab line disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showTabLine = false

    e.renderSplitView(buffer, false)

  test "Render with multi status line enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.multiStatusLine = true

    e.renderSplitView(buffer, false)

  test "Render with line wrap enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = true

    e.renderSplitView(buffer, false)

  test "Render with line wrap disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = false

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

    e.renderBottomLines(buffer)

  test "Render empty status message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = ""

    e.renderBottomLines(buffer)

  test "Render multi-line status message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "Line 1\nLine 2\nLine 3"

    e.renderBottomLines(buffer)

suite "renderBottomLines - Command mode":
  test "Render command line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    e.state.commandText = ":write"
    e.state.commandCursor = 5 # 0-based after ":", max = runeLen - 1

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
    e.state.commandText = ":"
    e.state.commandCursor = 0

    e.renderBottomLines(buffer)

    check e.state.screenCursor.x == 1 # After ":"
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render long command":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterCommandOverlay()
    e.state.commandText = ":set tabstop=4 shiftwidth=4 expandtab"
    e.state.commandCursor = 36 # 0-based after ":", max = runeLen - 1

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
    e.state.commandText = ":あいう"
    e.state.commandCursor = 3 # After all 3 wide chars

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
    e.state.commandText = ":eあb"
    e.state.commandCursor = 2 # After "eあ"

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
    e.state.search.text = "pattern"
    e.state.search.cursor = 7

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
    e.state.search.text = "test"
    e.state.search.cursor = 4

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
    e.state.search.text = ""

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

    e.renderBottomLines(buffer)

    check e.state.screenCursor.x == 8 # "Rename: ".len
    check e.state.screenCursor.y == buffer.area.height - 1

suite "renderBottomLines - Status line visibility":
  test "Render with single window":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal

    # Single window always renders status line
    check e.windowManager.windows.len == 1
    e.renderBottomLines(buffer)

  test "Render with multi status line disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.display.multiStatusLine = false

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

    e.renderBottomLines(buffer)

suite "renderTempMessages - Basic behavior":
  test "Render with no temp messages":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.ui.tempMessages = @[]

    # Should return early without crashing
    e.renderTempMessages(buffer)

  test "Render single temp message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.ui.tempMessages = @["Jump list entry 1"]

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

    e.renderTempMessages(buffer)

    check e.state.screenCursor.y == buffer.area.height - 1

  test "Temp messages with special characters":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.ui.tempMessages =
      @["File: /home/user/file.nim", "Unicode: こんにちは", "Symbols: <>&\"'"]

    e.renderTempMessages(buffer)

suite "renderSplitView - Viewport adjustment":
  test "Viewport follows cursor down":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Add content to buffer
    for i in 0 ..< 100:
      discard
        e.textBuffer.insertText(BufferPosition(line: i, column: 0), "Line " & $i & "\n")

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
    e.state.display.lineWrap = false

    # Add long line
    let longLine = "x".repeat(200)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    # Move cursor far right (use e.cursor to sync with EditorWindow)
    e.cursor = BufferPosition(line: 0, column: 150)

    e.renderSplitView(buffer, false)

    # Viewport should have scrolled horizontally
    let window2 = e.windowManager.windows[0]
    check window2.viewport.leftColumn > 0

  test "Viewport does not scroll horizontally when line wrap enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = true

    # Add long line
    let longLine = "x".repeat(200)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

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
    e.state.display.showLineNumbers = true

    e.renderSplitView(buffer, false)

  test "Render with line numbers disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showLineNumbers = false

    e.renderSplitView(buffer, false)

  test "Render with status line visible":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showStatusLine = true

    e.renderSplitView(buffer, false)

  test "Render with status line hidden":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showStatusLine = false

    e.renderSplitView(buffer, false)

suite "renderBottomLines - Edge cases":
  test "Very long status message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "x".repeat(200)

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

    e.renderBottomLines(buffer)

  test "Small buffer height":
    let e = createTestEditor()
    var buffer = newBuffer(80, 5)
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 5)

    e.viewport.width = 80
    e.viewport.height = 5
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "Status"

    e.renderBottomLines(buffer)

  test "Minimum buffer height":
    let e = createTestEditor()
    var buffer = newBuffer(80, 3)
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 3)

    e.viewport.width = 80
    e.viewport.height = 3
    e.state.mode = EditorMode.Normal

    e.renderBottomLines(buffer)

suite "Integration - Full render cycle":
  test "Complete render with all components":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showStatusLine = true
    e.state.display.showTabLine = true
    e.state.display.showLineNumbers = true
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = "Ready"

    # Full render cycle
    discard e.updateViewportSize(buffer)
    e.renderSplitView(buffer, false)
    e.renderBottomLines(buffer)

  test "Render cycle with mode change":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Normal mode
    e.state.mode = EditorMode.Normal
    e.renderSplitView(buffer, false)
    e.renderBottomLines(buffer)

    # Switch to command mode
    e.state.enterCommandOverlay()
    e.state.commandText = ":quit"
    e.state.commandCursor = 5
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
    e.renderBottomLines(buffer)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = false

    # Create hsplit
    discard e.hsplit()
    check e.windowManager.windows.len == 2

    # Render with 2 windows (draws separator between them)
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.renderBottomLines(buffer)

    # The old separator Y should now be normal content, not a separator
    let afterLine = getBufferLine(buffer, separatorY)
    check "─" notin afterLine

  test "hsplit close: no stale per-window status line (multi status line)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

    # Create hsplit
    discard e.hsplit()
    check e.windowManager.windows.len == 2

    # Render with 2 windows
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = false

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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = false

    discard e.vsplit()
    check e.windowManager.windows.len == 2

    # Render with 2 windows (draws vertical separator)
    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = false

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Each window gets its own status line
    check positions.len == 2

  test "2 hsplit windows, multiStatusLine=false: exactly 1 status line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = false

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

    discard e.vsplit()
    check e.windowManager.windows.len == 2

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true
    e.state.display.showTabLine = true

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

    # Enter command mode
    e.state.enterCommandOverlay()
    e.state.commandText = ":write"

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
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
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true

    discard e.hsplit()
    check e.windowManager.windows.len == 2

    clearBuffer(buffer)
    e.renderSplitView(buffer, false)
    e.renderBottomLines(buffer)

    let positions = statusLineYPositions(buffer)
    # Window 1 status line + Window 2 status line
    check positions.len == 2
    # Bottom window's status line should be at y=23 (last row)
    check positions[^1] == 23

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
