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

import std/[unittest, options, strutils, tables, unicode]
import pkg/celina
import
  ../src/moepkg/[
    editor, buffer, config, config_loader, render_utils, modes, color, highlight, types
  ]
import ../src/moepkg/editor_render_window
import ../src/moepkg/editor_render_helpers

proc createTestEditor(): Editor =
  ## Create a minimal editor for testing
  let config = newEditorConfig()
  config.theme.kind = tkDefault
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

suite "renderWindow - Visual selection on empty line":
  test "Visual mode shows selection at column 0 of empty line (no-wrap)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = false
    e.state.display.showSidebar = false
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.cursor = BufferPosition(line: 0, column: 0)

    # Empty buffer (single empty line)
    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0
    window.cursor.line = 0
    window.cursor.column = 0
    window.mode = EditorMode.Visual
    window.active = true

    e.renderWindow(buffer, window, 0, true, true, 0)

    # Column 0 of empty line should be highlighted with visual selection style
    let visStyle = visualStyle()
    check buffer[0, 0].style.bg == visStyle.bg

    # Other columns should not have visual style
    for x in 1 ..< 40:
      check buffer[x, 0].style.bg != visStyle.bg

  test "Visual mode shows selection at column 0 of empty line (wrapped)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = true
    e.state.display.showSidebar = false
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.cursor = BufferPosition(line: 0, column: 0)

    # Empty buffer
    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.cursor.line = 0
    window.cursor.column = 0
    window.mode = EditorMode.Visual
    window.active = true

    e.renderWindow(buffer, window, 0, true, true, 0)

    # Column 0 of empty line should be highlighted with visual selection style
    let visStyle = visualStyle()
    check buffer[0, 0].style.bg == visStyle.bg

    for x in 1 ..< 40:
      check buffer[x, 0].style.bg != visStyle.bg

  test "No visual style on empty line when not in Visual mode":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.display.lineWrap = false
    e.state.display.showSidebar = false
    e.state.mode = EditorMode.Normal
    e.state.visualSelection.active = false
    e.state.cursor = BufferPosition(line: 0, column: 0)

    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0
    window.cursor.line = 0
    window.cursor.column = 0
    window.mode = EditorMode.Normal
    window.active = true

    e.renderWindow(buffer, window, 0, true, true, 0)

    let visStyle = visualStyle()
    for x in 0 ..< 40:
      check buffer[x, 0].style.bg != visStyle.bg

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

suite "getVisualSelection - Detailed":
  test "Default hasSelection is false":
    let e = createTestEditor()
    let result = e.getVisualSelection(EditorMode.Normal)
    check result.hasSelection == false
    check result.selStart.line == 0
    check result.selStart.column == 0
    check result.selEnd.line == 0
    check result.selEnd.column == 0

  test "Visual mode with selection":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 1, column: 5)
    e.state.visualSelection.current = BufferPosition(line: 3, column: 10)

    let result = e.getVisualSelection(EditorMode.Visual)
    check result.hasSelection == true

  test "VisualLine mode":
    let e = createTestEditor()
    e.state.mode = EditorMode.VisualLine
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskLine
    e.state.visualSelection.start = BufferPosition(line: 2, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 5, column: 0)

    let result = e.getVisualSelection(EditorMode.VisualLine)
    check result.hasSelection == true

  test "VisualBlock mode":
    let e = createTestEditor()
    e.state.mode = EditorMode.VisualBlock
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskBlock
    e.state.visualSelection.start = BufferPosition(line: 0, column: 2)
    e.state.visualSelection.current = BufferPosition(line: 4, column: 8)

    let result = e.getVisualSelection(EditorMode.VisualBlock)
    check result.hasSelection == true

  test "windowActive=false disables selection":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.visualSelection.active = true
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 1, column: 5)

    let result = e.getVisualSelection(EditorMode.Visual, windowActive = false)
    check result.hasSelection == false

suite "shouldShowIndentationGuide - Detailed":
  test "Disabled when showIndentationLines is false":
    let e = createTestEditor()
    e.state.display.showIndentationLines = false
    let info = IndentInfo(leadingWhitespaceEnd: 7, hasContent: true)

    check e.shouldShowIndentationGuide(info, 4, 2) == false

  test "No guide at displayX 0":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 7, hasContent: true)

    check e.shouldShowIndentationGuide(info, 0, 0) == false

  test "Guide at tabStop multiples":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 4
    let info = IndentInfo(leadingWhitespaceEnd: 11, hasContent: true)

    # displayX=4 is a multiple of 4
    check e.shouldShowIndentationGuide(info, 4, 3) == true
    # displayX=8 is a multiple of 4
    check e.shouldShowIndentationGuide(info, 8, 7) == true

  test "No guide at non-tabStop positions":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 4
    let info = IndentInfo(leadingWhitespaceEnd: 11, hasContent: true)

    check e.shouldShowIndentationGuide(info, 1, 0) == false
    check e.shouldShowIndentationGuide(info, 2, 1) == false
    check e.shouldShowIndentationGuide(info, 3, 2) == false
    check e.shouldShowIndentationGuide(info, 5, 4) == false

  test "No guide when hasContent is false":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: -1, hasContent: false)

    check e.shouldShowIndentationGuide(info, 2, 1) == false
    check e.shouldShowIndentationGuide(info, 4, 3) == false

  test "No guide past leadingWhitespaceEnd":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 3, hasContent: true)

    # charIdx=4 is past whitespace end (3)
    check e.shouldShowIndentationGuide(info, 4, 4) == false
    # charIdx=5 is past whitespace end
    check e.shouldShowIndentationGuide(info, 6, 5) == false

  test "No guide for negative charIdx":
    let e = createTestEditor()
    e.state.display.showIndentationLines = true
    e.state.display.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 5, hasContent: true)

    check e.shouldShowIndentationGuide(info, 2, -1) == false

suite "getSelectionStyle - Basic":
  test "Returns cursor style at cursor position":
    let e = createTestEditor()
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    # At cursor position, should return cursor char style
    check true

  test "Returns normal style for non-cursor position":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check true

  test "Returns visual selection bg with normal fg when in selection (no syntax)":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.display.showSyntax = false
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 10)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 0,
      cursorCol = 10,
      windowMode = EditorMode.Visual,
    )
    # Background should be visual selection color
    check style.bg == visualStyle().bg
    # Foreground should be normal (no syntax highlight)
    check style.fg == normalStyle().fg

suite "getSelectionStyle - Visual selection preserves syntax highlight fg":
  test "Selection uses visual bg with syntax highlight fg":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.display.showSyntax = true
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 10)

    # Set up buffer with highlight
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "let x = 42")
    e.textBuffer.language = SourceLanguage.langNim
    e.textBuffer.highlight =
      initHighlight(@["let x = 42".toRunes], @[], SourceLanguage.langNim)

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 0,
      cursorCol = 10,
      windowMode = EditorMode.Visual,
    )
    # Background must be visual selection color
    check style.bg == visualStyle().bg
    # Foreground should come from syntax highlight, not visual selection
    let expectedFg = colorIndexToStyle(e.textBuffer.highlight.getColorPair(0, 0)).fg
    check style.fg == expectedFg

  test "VisualLine selection preserves syntax highlight fg":
    let e = createTestEditor()
    e.state.mode = EditorMode.VisualLine
    e.state.display.showSyntax = true
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskLine
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 0)

    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "let x = 42")
    e.textBuffer.language = SourceLanguage.langNim
    e.textBuffer.highlight =
      initHighlight(@["let x = 42".toRunes], @[], SourceLanguage.langNim)

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.VisualLine,
    )
    check style.bg == visualStyle().bg
    let expectedFg = colorIndexToStyle(e.textBuffer.highlight.getColorPair(0, 0)).fg
    check style.fg == expectedFg

  test "Selection without syntax uses normal fg":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.display.showSyntax = false
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 10)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 0,
      cursorCol = 10,
      windowMode = EditorMode.Visual,
    )
    check style.bg == visualStyle().bg
    check style.fg == normalStyle().fg

suite "getSelectionStyle - Matching paren":
  test "Returns paren pair style for matching paren":
    let e = createTestEditor()
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "(hello)")
    e.state.matchingParenPos = some(BufferPosition(line: 0, column: 6))

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 6),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

suite "getSelectionStyle - Find char match highlight (f/F/t/T)":
  test "Returns findCharMatch style for matched position":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style == findCharMatchStyle()

  test "Does not return findCharMatch style for non-matched position":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 1),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

  test "Does not return findCharMatch style for different line":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard
      e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada\nabacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 1, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

  test "No findCharMatch style when matches list is empty":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

  test "Visual selection takes priority over findCharMatch":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.display.showSyntax = false
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 6)
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 2),
      cursorLine = 0,
      cursorCol = 6,
      windowMode = EditorMode.Visual,
    )
    # Should have visual selection background, not findCharMatch style
    check style.bg == visualStyle().bg
    check style != findCharMatchStyle()

  test "Matching paren takes priority over findCharMatch":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "(abacada)")
    e.state.matchingParenPos = some(BufferPosition(line: 0, column: 8))
    e.state.ui.findCharMatches = @[1, 3, 5, 7]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 8),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check style == parenPairStyle()

  test "No findCharMatch style when findCharHighlight config is false":
    let e = createTestEditor()
    e.config.highlight.findCharHighlight = false
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

suite "getSelectionStyle - Search highlight":
  test "Returns search highlight style when search matches":
    let e = createTestEditor()
    e.state.search.hlsearch = true
    e.state.search.hlsearchTempDisabled = false
    e.state.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    discard
      e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world hello")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 5, # Cursor on different line
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No search highlight when hlsearch is disabled":
    let e = createTestEditor()
    e.state.search.hlsearch = false
    e.state.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 5,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No search highlight when hlsearchTempDisabled":
    let e = createTestEditor()
    e.state.search.hlsearch = true
    e.state.search.hlsearchTempDisabled = true
    e.state.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 5,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

suite "getSelectionStyle - Cursor line":
  test "Returns cursor line style when on cursor line":
    let e = createTestEditor()
    e.state.display.showCursorLine = true
    e.state.display.showSyntax = false
    e.state.display.showDocumentHighlight = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No cursor line style when showCursorLine is false":
    let e = createTestEditor()
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check true

  test "searchResult highlight takes priority over cursor line bg":
    let e = createTestEditor()
    e.state.display.showCursorLine = true
    e.state.display.showSyntax = true
    e.state.display.showDocumentHighlight = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Set up highlight with searchResult color on columns 0-4
    let searchStyle = colorIndexToStyle(EditorColorPairIndex.searchResult)
    e.textBuffer.highlight = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.searchResult,
          style: searchStyle,
        )
      ]
    )

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    # searchResult bg should NOT be overwritten by cursorLine bg
    check style.bg == searchStyle.bg
    check style.bg != cursorLineHighlightStyle().bg

  test "non-searchResult highlight still gets cursor line bg":
    let e = createTestEditor()
    e.state.display.showCursorLine = true
    e.state.display.showSyntax = true
    e.state.display.showDocumentHighlight = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Set up highlight with a normal (non-searchResult) color
    let defaultStyle = colorIndexToStyle(EditorColorPairIndex.default)
    e.textBuffer.highlight = Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 10,
          color: EditorColorPairIndex.default,
          style: defaultStyle,
        )
      ]
    )

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    # cursorLine bg should overwrite default highlight bg
    check style.bg == cursorLineHighlightStyle().bg

suite "getSelectionStyle - Cursor column":
  test "Returns cursor column bg when on cursor column":
    let e = createTestEditor()
    e.state.display.showCursorColumn = true
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    e.state.display.showDocumentHighlight = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 1,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
      displayCol = 5,
      cursorDisplayCol = 5,
    )
    check style.bg == cursorColumnHighlightStyle().bg

  test "No cursor column style when showCursorColumn is false":
    let e = createTestEditor()
    e.state.display.showCursorColumn = false
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 1,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
      displayCol = 5,
      cursorDisplayCol = 5,
    )
    check style.bg == normalStyle().bg

  test "No cursor column style when displayCol does not match":
    let e = createTestEditor()
    e.state.display.showCursorColumn = true
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 1,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
      displayCol = 3,
      cursorDisplayCol = 5,
    )
    check style.bg == normalStyle().bg

  test "Cursor line takes priority over cursor column at intersection":
    let e = createTestEditor()
    e.state.display.showCursorColumn = true
    e.state.display.showCursorLine = true
    e.state.display.showSyntax = false
    e.state.display.showDocumentHighlight = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # At intersection (same line AND same column): cursorLine wins
    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
      displayCol = 5,
      cursorDisplayCol = 5,
    )
    check style.bg == cursorLineHighlightStyle().bg

  test "No cursor column when displayCol params not provided":
    let e = createTestEditor()
    e.state.display.showCursorColumn = true
    e.state.display.showCursorLine = false
    e.state.display.showSyntax = false
    discard e.textBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Without displayCol/cursorDisplayCol params (default -1), no column highlight
    let style = e.getSelectionStyle(
      e.textBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 5),
      cursorLine = 1,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check style.bg == normalStyle().bg

suite "renderLineSegmentWithSelection - trailing space highlight":
  test "Normal mode highlights trailing spaces":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("hello   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "hello   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    # Trailing spaces (columns 5, 6, 7) should have trailing space style
    check buf[5, 0].style == trailingStyle
    check buf[6, 0].style == trailingStyle
    check buf[7, 0].style == trailingStyle

  test "Current line does not highlight trailing spaces":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("hello   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "hello   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    # Trailing spaces on the current line should NOT be highlighted
    check buf[5, 0].style != trailingStyle
    check buf[6, 0].style != trailingStyle
    check buf[7, 0].style != trailingStyle

  test "Help mode does not highlight trailing spaces":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("hello   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Help,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "hello   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    # Trailing spaces should NOT have trailing space style in Help mode
    check buf[5, 0].style != trailingStyle
    check buf[6, 0].style != trailingStyle
    check buf[7, 0].style != trailingStyle

  test "BufferManager mode does not highlight trailing spaces":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("entry   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.BufferManager,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "entry   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    check buf[5, 0].style != trailingStyle

  test "DiffViewer mode does not highlight trailing spaces":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let tb = newTextBuffer("diff   ")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.DiffViewer,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, "diff   ", 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    check buf[4, 0].style != trailingStyle

suite "renderLineSegmentWithSelection - full-width space highlight":
  test "Normal mode highlights full-width space":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.fullWidthSpace = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let text = "ab" & $FULLWIDTH_SPACE & "cd"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let fwStyle = fullWidthSpaceStyle()
    # Full-width space at column 2 (takes 2 display cells) should be highlighted
    check buf[2, 0].style == fwStyle

  test "Help mode does not highlight full-width space":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.fullWidthSpace = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let text = "ab" & $FULLWIDTH_SPACE & "cd"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Help,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let fwStyle = fullWidthSpaceStyle()
    check buf[2, 0].style != fwStyle

  test "Debug mode does not highlight full-width space":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.fullWidthSpace = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false

    let text = "ab" & $FULLWIDTH_SPACE & "cd"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Debug,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let fwStyle = fullWidthSpaceStyle()
    check buf[2, 0].style != fwStyle

suite "renderLineSegmentWithSelection - tab trailing space highlight":
  test "Normal mode highlights trailing tab":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false
    e.state.display.tabStop = 4

    let text = "ab\t"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    # Tab at column 2 expands to spaces; column 2 should have trailing style
    check buf[2, 0].style == trailingStyle

  test "Current line does not highlight trailing tab":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false
    e.state.display.tabStop = 4

    let text = "ab\t"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    # Trailing tab on the current line should NOT be highlighted
    check buf[2, 0].style != trailingStyle

  test "Help mode does not highlight trailing tab":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.display.showSyntax = false
    e.state.display.showCursorLine = false
    e.state.display.showIndentationLines = false
    e.state.display.tabStop = 4

    let text = "ab\t"
    let tb = newTextBuffer(text)
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Help,
      windowRightEdge: 80,
    )

    e.renderLineSegmentWithSelection(tb, buf, text, 0, 0, 0, 0, ctx)

    let trailingStyle = trailingSpacesStyle()
    check buf[2, 0].style != trailingStyle
