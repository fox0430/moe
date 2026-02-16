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

## Tests for editor_render_window.nim functions
## This module tests window and line rendering procedures

import std/[unittest, strutils]
import pkg/celina
import ../src/moepkg/[editor, buffer, config, config_loader, render_utils, modes]
import ../src/moepkg/editor_render_window
import ../src/moepkg/editor_render_helpers

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc createTestBuffer(): Buffer =
  ## Create a minimal Celina Buffer for testing
  result = newBuffer(80, 24)
  result.area = Rect(x: 0, y: 0, width: 80, height: 24)

proc createTestSidebar(height: int): Sidebar =
  ## Create a test sidebar with correct number of items per row
  result = Sidebar(width: 2, buffer: @[])
  for i in 0 ..< height:
    var row: seq[SidebarItem]
    # Add 2 items (one per column) to match width
    row.add(SidebarItem(text: " ", style: normalStyle()))
    row.add(SidebarItem(text: " ", style: normalStyle()))
    result.buffer.add(row)

suite "renderWindowLineWrapped - Basic behavior":
  test "Render empty line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    var screenY = 0
    var lineIndex = 0

    e.renderWindowLineWrapped(buffer, window, 0, ctx, screenY, lineIndex, 20, 0)

    check screenY == 1
    check lineIndex == 1

  test "Render short line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Add content to text buffer
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    var screenY = 0
    var lineIndex = 0

    e.renderWindowLineWrapped(buffer, window, 0, ctx, screenY, lineIndex, 20, 0)

    check screenY == 1
    check lineIndex == 1

  test "Render line with line number":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Test line")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    var screenY = 0
    var lineIndex = 0

    # Line number offset of 4 characters
    e.renderWindowLineWrapped(buffer, window, 4, ctx, screenY, lineIndex, 20, 0)

    check screenY == 1
    check lineIndex == 1

  test "Render line that wraps":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # Create a long line that will wrap
    let longLine = "x".repeat(100)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    let window = e.windowManager.windows[0]
    window.viewport.width = 40 # Narrow width to force wrapping
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 40,
    )

    var screenY = 0
    var lineIndex = 0

    e.renderWindowLineWrapped(buffer, window, 0, ctx, screenY, lineIndex, 20, 0)

    # Line should wrap multiple times
    check screenY > 1
    check lineIndex == 1

  test "Render with tab line offset":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Test")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    var screenY = 1 # Start after tab line
    var lineIndex = 0

    e.renderWindowLineWrapped(buffer, window, 0, ctx, screenY, lineIndex, 20, 1)

    check screenY == 2
    check lineIndex == 1

suite "renderWindowLineNoWrap - Basic behavior":
  test "Render empty line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)

  test "Render short line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)

  test "Render line with line number":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Test line")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    e.renderWindowLineNoWrap(buffer, window, 4, ctx, 0, 0)

  test "Render with horizontal scroll":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let longLine = "x".repeat(100)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 50 # Scroll right

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 50,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)

  test "Render scrolled past line end":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Short")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 100 # Scroll past line end

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)

  test "Render on current line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Current line")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0
    window.cursor.line = 0 # Cursor on this line

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

    e.renderWindowLineNoWrap(buffer, window, 4, ctx, 0, 0)

suite "renderWindowSidebar - Basic behavior":
  test "Render sidebar line":
    var buffer = createTestBuffer()

    let window = EditorWindow(
      viewport: ViewPort(x: 0, y: 0, width: 80, height: 24),
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )

    let sidebar = createTestSidebar(10)

    renderWindowSidebar(buffer, window, sidebar, 0, 0, 0)

  test "Render sidebar at offset":
    var buffer = createTestBuffer()

    let window = EditorWindow(
      viewport: ViewPort(x: 5, y: 2, width: 70, height: 20),
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )

    let sidebar = createTestSidebar(10)

    renderWindowSidebar(buffer, window, sidebar, 3, 3, 0)

  test "Render sidebar with invalid index":
    var buffer = createTestBuffer()

    let window = EditorWindow(
      viewport: ViewPort(x: 0, y: 0, width: 80, height: 24),
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )

    let sidebar = createTestSidebar(5)

    # Index out of bounds - should not crash
    renderWindowSidebar(buffer, window, sidebar, 0, 10, 0)

  test "Render sidebar with negative index":
    var buffer = createTestBuffer()

    let window = EditorWindow(
      viewport: ViewPort(x: 0, y: 0, width: 80, height: 24),
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )

    let sidebar = createTestSidebar(5)

    # Negative index - should not crash
    renderWindowSidebar(buffer, window, sidebar, 0, -1, 0)

suite "renderFoldLine - Basic behavior":
  test "Render fold marker":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.textBuffer.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3"
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let fold = Fold(startLine: 0, endLine: 2, collapsed: true)

    e.renderFoldLine(buffer, window, 0, 0, fold)

  test "Render fold marker with line number":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.textBuffer.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3"
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let fold = Fold(startLine: 0, endLine: 2, collapsed: true)

    e.renderFoldLine(buffer, window, 4, 0, fold)

  test "Render fold marker at window offset":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard
      e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")

    let window = e.windowManager.windows[0]
    window.viewport.width = 60
    window.viewport.height = 20
    window.viewport.x = 10
    window.viewport.y = 5

    let fold = Fold(startLine: 0, endLine: 1, collapsed: true)

    e.renderFoldLine(buffer, window, 4, 0, fold)

suite "renderWindow - Basic behavior":
  test "Render window with single line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

  test "Render window with multiple lines":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    discard e.textBuffer.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3\nLine 4\nLine 5"
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 4, true, true, 0)

  test "Render window with line wrap enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = true

    let longLine = "x".repeat(100)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

  test "Render window with line wrap disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = false

    let longLine = "x".repeat(100)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

  test "Render window with sidebar enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showSidebar = true

    discard
      e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 4, true, true, 0)

  test "Render window with sidebar disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showSidebar = false

    discard
      e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 4, true, true, 0)

  test "Render window with tab line offset":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Content")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 4, true, true, 1)

  test "Render window as non-active":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Content")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.active = false

    e.renderWindow(buffer, window, 4, true, false, 0)

  test "Render window as non-bottom":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Content")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 12
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 4, false, true, 0)

suite "renderWindowSeparator - Basic behavior":
  test "Render vertical separator":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Create two side-by-side windows
    let window1 = EditorWindow(
      viewport: ViewPort(x: 0, y: 0, width: 40, height: 24),
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )
    let window2 = EditorWindow(
      viewport: ViewPort(x: 40, y: 0, width: 40, height: 24),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
    )

    e.renderWindowSeparator(buffer, window1, window2, true)

  test "Render horizontal separator when multi status line disabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.multiStatusLine = false

    # Create two stacked windows
    let window1 = EditorWindow(
      viewport: ViewPort(x: 0, y: 0, width: 80, height: 12),
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )
    let window2 = EditorWindow(
      viewport: ViewPort(x: 0, y: 12, width: 80, height: 12),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
    )

    e.renderWindowSeparator(buffer, window1, window2, false)

  test "No horizontal separator when multi status line enabled":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.multiStatusLine = true

    # Create two stacked windows
    let window1 = EditorWindow(
      viewport: ViewPort(x: 0, y: 0, width: 80, height: 12),
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )
    let window2 = EditorWindow(
      viewport: ViewPort(x: 0, y: 12, width: 80, height: 12),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
    )

    # Should not draw horizontal separator
    e.renderWindowSeparator(buffer, window1, window2, false)

  test "Separator at window offset":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    let window1 = EditorWindow(
      viewport: ViewPort(x: 10, y: 5, width: 30, height: 15),
      cursor: BufferPosition(line: 0, column: 0),
      active: true,
    )
    let window2 = EditorWindow(
      viewport: ViewPort(x: 40, y: 5, width: 30, height: 15),
      cursor: BufferPosition(line: 0, column: 0),
      active: false,
    )

    e.renderWindowSeparator(buffer, window1, window2, true)

suite "renderWindow - Visual selection":
  test "Render window with visual selection":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 5)
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.cursor = BufferPosition(line: 0, column: 5)

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.active = true

    e.renderWindow(buffer, window, 0, true, true, 0)

  test "Render window with visual line selection":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.VisualLine
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 2, column: 0)
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskLine
    e.state.cursor = BufferPosition(line: 2, column: 0)

    discard e.textBuffer.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3"
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.active = true

    e.renderWindow(buffer, window, 0, true, true, 0)

  test "Render window with visual block selection":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.mode = EditorMode.VisualBlock
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 2, column: 5)
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskBlock
    e.state.cursor = BufferPosition(line: 2, column: 5)

    discard e.textBuffer.insertText(
      BufferPosition(line: 0, column: 0), "Line 1\nLine 2\nLine 3"
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.active = true

    e.renderWindow(buffer, window, 0, true, true, 0)

suite "renderWindow - Scrolling":
  test "Render window with vertical scroll":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    # Add many lines
    var content = ""
    for i in 0 ..< 100:
      content &= "Line " & $i & "\n"
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), content)

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.topLine = 50 # Scroll down

    e.renderWindow(buffer, window, 4, true, true, 0)

  test "Render window with horizontal scroll":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = false

    let longLine = "x".repeat(200)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 100 # Scroll right

    e.renderWindow(buffer, window, 0, true, true, 0)

suite "renderWindow - Edge cases":
  test "Render window with empty buffer":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

  test "Render window with very small size":
    let e = createTestEditor()
    var buffer = newBuffer(20, 5)
    buffer.area = Rect(x: 0, y: 0, width: 20, height: 5)

    e.viewport.width = 20
    e.viewport.height = 5

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Small window")

    let window = e.windowManager.windows[0]
    window.viewport.width = 20
    window.viewport.height = 5
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 2, true, true, 0)

  test "Render window with Unicode content":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    discard e.textBuffer.insertText(
      BufferPosition(line: 0, column: 0), "こんにちは世界\n日本語テスト"
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 4, true, true, 0)

  test "Render window with mixed content":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24

    discard e.textBuffer.insertText(
      BufferPosition(line: 0, column: 0), "Hello 世界\n  indented\n\ttab"
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 4, true, true, 0)

suite "Cursor line highlight - Window boundary clipping":
  test "Cursor line highlight does not exceed window right edge (no-wrap)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showCursorLine = true
    e.state.display.lineWrap = false

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Hi")

    # Simulate a left window in a vertical split: width=40, starting at x=0
    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0
    window.cursor.line = 0
    window.cursor.column = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

    # Cells within window (x < 40) on cursor line should have cursor line style
    let hlStyle = cursorLineHighlightStyle()
    # After content "Hi" (2 chars), positions 2..39 should be filled with highlight
    for x in 2 ..< 40:
      check buffer[x, 0].style.bg == hlStyle.bg

    # Cells at and beyond window right edge (x >= 40) should NOT have cursor line style
    for x in 40 ..< 80:
      check buffer[x, 0].style.bg != hlStyle.bg

  test "Cursor line highlight does not exceed window right edge (wrapped)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showCursorLine = true
    e.state.display.lineWrap = true

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Hi")

    # Left window of vertical split
    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.cursor.line = 0
    window.cursor.column = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

    let hlStyle = cursorLineHighlightStyle()
    for x in 2 ..< 40:
      check buffer[x, 0].style.bg == hlStyle.bg

    for x in 40 ..< 80:
      check buffer[x, 0].style.bg != hlStyle.bg

  test "Cursor line highlight respects window x offset":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showCursorLine = true
    e.state.display.lineWrap = false

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Hi")

    # Right window of vertical split: width=40, starting at x=40
    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 40
    window.viewport.y = 0
    window.viewport.leftColumn = 0
    window.cursor.line = 0
    window.cursor.column = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

    let hlStyle = cursorLineHighlightStyle()
    # Content "Hi" starts at x=40, fill from x=42..79
    for x in 42 ..< 80:
      check buffer[x, 0].style.bg == hlStyle.bg

    # Cells before the window (x < 40) should NOT have cursor line style
    for x in 0 ..< 40:
      check buffer[x, 0].style.bg != hlStyle.bg

  test "Empty line cursor highlight clipped to window boundary":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showCursorLine = true
    e.state.display.showSidebar = false
    e.state.display.lineWrap = false

    # Empty buffer (single empty line)
    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0
    window.cursor.line = 0
    window.cursor.column = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

    let hlStyle = cursorLineHighlightStyle()
    # Cursor line highlight should fill within window (no sidebar, no line numbers)
    for x in 0 ..< 40:
      check buffer[x, 0].style.bg == hlStyle.bg

    # Should NOT fill beyond window
    for x in 40 ..< 80:
      check buffer[x, 0].style.bg != hlStyle.bg

  test "fillLineBackground clipped to window boundary":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.state.display.showCursorLine = true

    # Call fillLineBackground directly with windowRightEdge=30
    e.fillLineBackground(buffer, 0, 0, 0, 0, 30)

    let hlStyle = cursorLineHighlightStyle()
    # Should fill positions 0..29
    for x in 0 ..< 30:
      check buffer[x, 0].style.bg == hlStyle.bg

    # Should NOT fill positions 30+
    for x in 30 ..< 80:
      check buffer[x, 0].style.bg != hlStyle.bg

  test "fillLineBackground fills normalStyle for non-cursor line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.state.display.showCursorLine = true

    # Pre-fill with cursor line highlight to simulate stale content
    let hlStyle = cursorLineHighlightStyle()
    for x in 0 ..< 40:
      buffer.setString(x, 0, " ", hlStyle)

    # Fill line 1 (non-cursor), cursor is on line 0
    e.fillLineBackground(buffer, 0, 0, 1, 0, 40)

    # All positions should now have normalStyle (stale highlight cleared)
    let nStyle = normalStyle()
    for x in 0 ..< 40:
      check buffer[x, 0].style.bg == nStyle.bg

  test "renderLineSegmentWithSelection clipped to window boundary":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.state.display.showCursorLine = true
    e.state.display.showSyntax = false

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "AB")

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowMode: EditorMode.Normal,
      windowRightEdge: 30,
    )

    e.renderLineSegmentWithSelection(
      e.textBuffer, buffer, "AB", 0, 0, 0, 0, ctx, useRunes = false
    )

    let hlStyle = cursorLineHighlightStyle()
    # Cursor line fill should stop before windowRightEdge
    for x in 2 ..< 30:
      check buffer[x, 0].style.bg == hlStyle.bg

    # Beyond windowRightEdge should NOT be filled
    for x in 30 ..< 80:
      check buffer[x, 0].style.bg != hlStyle.bg

  test "Non-cursor line clears stale cursor line highlight":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.state.display.showCursorLine = true
    e.state.display.showSyntax = false

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "AB")

    # Pre-fill the trailing area with cursor line highlight to simulate
    # a previous frame where this line was the cursor line
    let hlStyle = cursorLineHighlightStyle()
    for x in 2 ..< 40:
      buffer.setString(x, 0, " ", hlStyle)

    # Now render this line as a NON-cursor line (cursor is on line 99)
    let ctx = RenderContext(
      cursorLine: 99,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowMode: EditorMode.Normal,
      windowRightEdge: 40,
    )

    e.renderLineSegmentWithSelection(
      e.textBuffer, buffer, "AB", 0, 0, 0, 0, ctx, useRunes = false
    )

    # Trailing area should be cleared to normalStyle, not cursor highlight
    let nStyle = normalStyle()
    for x in 2 ..< 40:
      check buffer[x, 0].style.bg == nStyle.bg

  test "Stale cursor highlight cleared after vsplit":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showCursorLine = true
    e.state.display.lineWrap = false

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Hi")

    # First render: single full-width window, cursor on line 0
    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0
    window.cursor.line = 0
    window.cursor.column = 0

    e.renderWindow(buffer, window, 0, true, true, 0)

    let hlStyle = cursorLineHighlightStyle()
    # Verify highlight spans full 80-column window
    for x in 2 ..< 80:
      check buffer[x, 0].style.bg == hlStyle.bg

    # Second render: simulate vsplit — left window now only 39 columns wide
    window.viewport.width = 39

    e.renderWindow(buffer, window, 0, true, true, 0)

    # Highlight should only cover within the narrower window
    for x in 2 ..< 39:
      check buffer[x, 0].style.bg == hlStyle.bg

    # Old highlight beyond new window right edge should be untouched by
    # this window's render (it's now part of another window's area).
    # The key point: cells 39..79 are NOT written by the left window.
    # In a real split, the right window would overwrite them.

  test "Non-cursor line cleared in window render (no-wrap)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.showCursorLine = true
    e.state.display.lineWrap = false

    # Insert two lines
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "Line1\nLine2")

    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0
    window.cursor.line = 0
    window.cursor.column = 0

    # Pre-fill row 1 (line 1) trailing area with cursor highlight
    # to simulate it being the previous cursor line
    let hlStyle = cursorLineHighlightStyle()
    for x in 5 ..< 40:
      buffer.setString(x, 1, " ", hlStyle)

    # Render with cursor on line 0
    e.renderWindow(buffer, window, 0, true, true, 0)

    # Row 0 (cursor line) should have cursor highlight
    for x in 5 ..< 40:
      check buffer[x, 0].style.bg == hlStyle.bg

    # Row 1 (non-cursor line) trailing area should be cleared
    let nStyle = normalStyle()
    for x in 5 ..< 40:
      check buffer[x, 1].style.bg == nStyle.bg
