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
import ../src/moepkg/[editor, config, configloader, modes]
import ../src/moepkg/editor_render_views

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestBuffer(): Buffer =
  ## Create a minimal Celina Buffer for testing
  result = newBuffer(80, 24)
  result.area = Rect(x: 0, y: 0, width: 80, height: 24)

suite "updateViewportSize - Basic behavior":
  test "Update viewport from buffer area":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 100, height: 50)

    # Initially viewport may have different size
    e.viewport.width = 80
    e.viewport.height = 24

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.viewport.width == 100
    check e.viewport.height == 50

  test "No resize when size unchanged":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    buffer.area = Rect(x: 0, y: 0, width: 80, height: 24)

    e.viewport.width = 80
    e.viewport.height = 24

    let resized = e.updateViewportSize(buffer)

    check resized == false
    check e.viewport.width == 80
    check e.viewport.height == 24

  test "Width change triggers resize":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    buffer.area = Rect(x: 0, y: 0, width: 120, height: 24)

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.viewport.width == 120
    check e.viewport.height == 24

  test "Height change triggers resize":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    buffer.area = Rect(x: 0, y: 0, width: 80, height: 40)

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.viewport.width == 80
    check e.viewport.height == 40

  test "Both dimensions change":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    buffer.area = Rect(x: 0, y: 0, width: 120, height: 40)

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.viewport.width == 120
    check e.viewport.height == 40

  test "Update from zero size":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 0
    e.viewport.height = 0

    buffer.area = Rect(x: 0, y: 0, width: 80, height: 24)

    let resized = e.updateViewportSize(buffer)

    check resized == true
    check e.viewport.width == 80
    check e.viewport.height == 24

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
    e.state.commandCursor = 6

    e.renderBottomLines(buffer)

    # Cursor should be positioned on command line
    check e.state.screenCursor.x == 7 # 1 + 6 (after ":" + cursor position)
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
    e.state.commandCursor = 37

    e.renderBottomLines(buffer)

    check e.state.screenCursor.x == 38
    check e.state.screenCursor.y == buffer.area.height - 1

suite "renderBottomLines - Search mode":
  test "Render forward search":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.enterSearchOverlay(Forward)
    e.state.search.text = "pattern"

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
    e.state.tempMessages = @[]

    # Should return early without crashing
    e.renderTempMessages(buffer)

  test "Render single temp message":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.tempMessages = @["Jump list entry 1"]

    e.renderTempMessages(buffer)

    # Cursor should be at bottom for prompt
    check e.state.screenCursor.x == 0
    check e.state.screenCursor.y == buffer.area.height - 1

  test "Render multiple temp messages":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.tempMessages =
      @[
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
    e.state.tempMessages = messages

    e.renderTempMessages(buffer)

    check e.state.screenCursor.y == buffer.area.height - 1

  test "Temp messages with special characters":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.tempMessages =
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
    e.state.tempMessages = @["Message 1", "Message 2"]

    discard e.updateViewportSize(buffer)
    e.renderSplitView(buffer, false)
    e.renderBottomLines(buffer)
    e.renderTempMessages(buffer)

    check e.state.screenCursor.y == buffer.area.height - 1
