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
import ../src/moepkg/editor_render_window {.all.}
import ../src/moepkg/[editor_render_helpers, style_patch, colorcode, editor_codelens]

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

proc getSelectionStyleAt(
    e: Editor,
    buffer: TextBuffer,
    hasSelection: bool,
    pos: BufferPosition,
    cursorLine: int,
    cursorCol: int,
    windowMode: EditorMode,
    displayCol: int = -1,
    cursorDisplayCol: int = -1,
    lineConflict: ConflictMarkerKind = cmkNone,
    useTwoColor: bool = false,
    searchRanges: seq[ColumnRange] = @[],
    wordRanges: seq[ColumnRange] = @[],
    isActiveWindow: bool = true,
): Style =
  ## Test helper that bridges the legacy per-line params to the new
  ## LineStyleContext-based signature. Optional params let tests inject
  ## conflict/search/word state symmetrically with the other *At helpers.
  let lineCtx = LineStyleContext(
    lineIndex: pos.line,
    isActiveWindow: isActiveWindow,
    isCursorLine: pos.line == cursorLine,
    lineConflict: lineConflict,
    useTwoColor: useTwoColor,
    searchRanges: searchRanges,
    wordRanges: wordRanges,
  )
  e.getSelectionStyle(
    buffer,
    hasSelection = hasSelection,
    pos = pos,
    cursorCol = cursorCol,
    windowMode = windowMode,
    lineCtx = lineCtx,
    displayCol = displayCol,
    cursorDisplayCol = cursorDisplayCol,
  )

proc lineFillPatchAt(
    e: Editor,
    lineIndex: int,
    cursorLine: int,
    displayX: int,
    cursorDisplayCol: int,
    lineConflict: ConflictMarkerKind,
    useTwoColor: bool,
    inVisualSelection: bool,
): StylePatch =
  ## Test helper bridging the legacy explicit-args signature to the
  ## LineStyleContext-based one.
  let lineCtx = LineStyleContext(
    lineIndex: lineIndex,
    isCursorLine: lineIndex == cursorLine,
    lineConflict: lineConflict,
    useTwoColor: useTwoColor,
  )
  e.lineFillPatch(lineCtx, displayX, cursorDisplayCol, inVisualSelection)

proc overlayPatchSyntaxAt(
    e: Editor,
    pos: BufferPosition,
    cursorLine: int,
    displayCol: int,
    cursorDisplayCol: int,
    lineConflict: ConflictMarkerKind,
    useTwoColor: bool,
    colorPair: EditorColorPairIndex,
): StylePatch =
  ## Test helper bridging the legacy explicit-args signature to the
  ## LineStyleContext-based one.
  let lineCtx = LineStyleContext(
    lineIndex: pos.line,
    isCursorLine: pos.line == cursorLine,
    lineConflict: lineConflict,
    useTwoColor: useTwoColor,
  )
  e.overlayPatchSyntax(pos, lineCtx, displayCol, cursorDisplayCol, colorPair)

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
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Test line")

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
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Test")

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

  test "skipSegments renders from a later wrap segment (sub-line scroll)":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.state.showSidebar = false
    e.state.scrollbar = false

    # 30 chars => 3 wrap segments at maxWidth 10: "0123456789" / "ABCDEFGHIJ" / ...
    let line = "0123456789ABCDEFGHIJabcdefghij"
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), line)

    let window = e.windowManager.windows[0]
    window.viewport.width = 10
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 10,
    )

    var screenY = 0
    var lineIndex = 0
    e.renderWindowLineWrapped(
      buffer, window, 0, ctx, screenY, lineIndex, 20, 0, skipSegments = 1
    )

    # Segment 0 is scrolled off the top; the first visible row is segment 1.
    check buffer[0, 0].symbol == "A"
    # The skip costs no screen rows: only the 2 remaining segments are drawn.
    check screenY == 2
    check lineIndex == 1

  test "Partial top line draws no line number on its first visible row":
    let e = createTestEditor()
    e.state.showSidebar = false
    e.state.scrollbar = false

    let line = "0123456789ABCDEFGHIJabcdefghij"
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), line)

    let window = e.windowManager.windows[0]
    window.viewport.width = 14 # lineNumOffset(4) + maxWidth(10)
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 14,
    )

    # skip = 1: continuation row, gutter blank (digit at x=2 becomes a space).
    var skipBuffer = createTestBuffer()
    var sY1 = 0
    var lI1 = 0
    e.renderWindowLineWrapped(
      skipBuffer, window, 4, ctx, sY1, lI1, 20, 0, skipSegments = 1
    )
    check skipBuffer[2, 0].symbol == " "
    check skipBuffer[4, 0].symbol == "A" # segment 1 text starts past the gutter

    # skip = 0: the first wrap row owns the line number "1".
    var fullBuffer = createTestBuffer()
    var sY0 = 0
    var lI0 = 0
    e.renderWindowLineWrapped(
      fullBuffer, window, 4, ctx, sY0, lI0, 20, 0, skipSegments = 0
    )
    check fullBuffer[2, 0].symbol == "1"
    check fullBuffer[4, 0].symbol == "0" # segment 0 text

  test "Per-line search highlight applies on every wrap segment":
    # Guards the precomputed LinePrecomputed path: the wrap loop builds
    # lineCtx once and reuses it across segments, so a match in each segment
    # must still carry the searchHighlight bg.
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.state.showSidebar = false
    e.state.scrollbar = false
    e.state.showCursorLine = false
    e.state.showSyntax = false
    e.state.input.search.hlsearch = true
    e.state.input.search.hlsearchTempDisabled = false
    e.state.input.search.lastText = "AA"
    e.state.mode = EditorMode.Normal

    # 30 chars => 3 wrap segments at maxWidth 10, each starting with "AA".
    let line = "AA12345678AA34567890AA56789012"
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), line)

    let window = e.windowManager.windows[0]
    window.viewport.width = 10
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.cursor.line = 5

    let ctx = RenderContext(
      cursorLine: 5,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 10,
    )

    var screenY = 0
    var lineIndex = 0
    e.renderWindowLineWrapped(buffer, window, 0, ctx, screenY, lineIndex, 20, 0)

    check screenY == 3
    let sh = searchHighlightStyle()
    for y in 0 ..< 3:
      check buffer[0, y].style.bg == sh.bg
      check buffer[1, y].style.bg == sh.bg

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Test line")

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
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Short")

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

    discard
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Current line")

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

    discard e.activeBuffer.insertText(
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

    discard e.activeBuffer.insertText(
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
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

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

    discard e.activeBuffer.insertText(
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
    e.state.lineWrap = true

    let longLine = "x".repeat(100)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

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
    e.state.lineWrap = false

    let longLine = "x".repeat(100)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

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
    e.state.showSidebar = true

    discard
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")

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
    e.state.showSidebar = false

    discard
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Line 1\nLine 2")

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Content")

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Content")

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Content")

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
    e.state.multiStatusLine = false

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
    e.state.multiStatusLine = true

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

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Hello World")

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

    discard e.activeBuffer.insertText(
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

    discard e.activeBuffer.insertText(
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
    e.state.lineWrap = false
    e.state.showSidebar = false
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
    e.state.lineWrap = true
    e.state.showSidebar = false
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
    e.state.lineWrap = false
    e.state.showSidebar = false
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
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), content)

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
    e.state.lineWrap = false

    let longLine = "x".repeat(200)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

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

    discard
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Small window")

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

    discard e.activeBuffer.insertText(
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

    discard e.activeBuffer.insertText(
      BufferPosition(line: 0, column: 0), "Hello 世界\n  indented\n\ttab"
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0

    e.renderWindow(buffer, window, 4, true, true, 0)

  test "Tiny terminal: visibleHeight clamped to 0 to prevent negative value":
    let e = createTestEditor()
    var buffer = createTestBuffer()
    e.state.showStatusLine = true
    e.state.multiStatusLine = true

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello")

    let window = e.windowManager.windows[0]
    # Viewport height is smaller than reservedLines + tabLineOffset
    window.viewport.height = 0

    # Must not crash
    e.renderWindow(
      buffer, window, 0, isBottomWindow = true, isActiveWindow = true, tabLineOffset = 0
    )

suite "Cursor line highlight - Window boundary clipping":
  test "Cursor line highlight does not exceed window right edge (no-wrap)":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    e.viewport.width = 80
    e.viewport.height = 24
    e.state.showCursorLine = true
    e.state.lineWrap = false

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Hi")

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
    e.state.showCursorLine = true
    e.state.lineWrap = true

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Hi")

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
    e.state.showCursorLine = true
    e.state.lineWrap = false

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Hi")

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
    e.state.showCursorLine = true
    e.state.showSidebar = false
    e.state.lineWrap = false

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

    e.state.showCursorLine = true

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

    e.state.showCursorLine = true

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

    e.state.showCursorLine = true
    e.state.showSyntax = false

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "AB")

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
      e.activeBuffer, buffer, "AB", 0, 0, 0, 0, ctx, useRunes = false
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

    e.state.showCursorLine = true
    e.state.showSyntax = false

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "AB")

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
      e.activeBuffer, buffer, "AB", 0, 0, 0, 0, ctx, useRunes = false
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
    e.state.showCursorLine = true
    e.state.lineWrap = false

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Hi")

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
    e.state.showCursorLine = true
    e.state.lineWrap = false

    # Insert two lines
    discard
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "Line1\nLine2")

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
    e.state.showIndentationLines = false
    let info = IndentInfo(leadingWhitespaceEnd: 7, hasContent: true)

    check e.shouldShowIndentationGuide(info, 4, 2) == false

  test "No guide at displayX 0":
    let e = createTestEditor()
    e.state.showIndentationLines = true
    e.state.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 7, hasContent: true)

    check e.shouldShowIndentationGuide(info, 0, 0) == false

  test "Guide at tabStop multiples":
    let e = createTestEditor()
    e.state.showIndentationLines = true
    e.state.tabStop = 4
    let info = IndentInfo(leadingWhitespaceEnd: 11, hasContent: true)

    # displayX=4 is a multiple of 4
    check e.shouldShowIndentationGuide(info, 4, 3) == true
    # displayX=8 is a multiple of 4
    check e.shouldShowIndentationGuide(info, 8, 7) == true

  test "No guide at non-tabStop positions":
    let e = createTestEditor()
    e.state.showIndentationLines = true
    e.state.tabStop = 4
    let info = IndentInfo(leadingWhitespaceEnd: 11, hasContent: true)

    check e.shouldShowIndentationGuide(info, 1, 0) == false
    check e.shouldShowIndentationGuide(info, 2, 1) == false
    check e.shouldShowIndentationGuide(info, 3, 2) == false
    check e.shouldShowIndentationGuide(info, 5, 4) == false

  test "No guide when hasContent is false":
    let e = createTestEditor()
    e.state.showIndentationLines = true
    e.state.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: -1, hasContent: false)

    check e.shouldShowIndentationGuide(info, 2, 1) == false
    check e.shouldShowIndentationGuide(info, 4, 3) == false

  test "No guide past leadingWhitespaceEnd":
    let e = createTestEditor()
    e.state.showIndentationLines = true
    e.state.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 3, hasContent: true)

    # charIdx=4 is past whitespace end (3)
    check e.shouldShowIndentationGuide(info, 4, 4) == false
    # charIdx=5 is past whitespace end
    check e.shouldShowIndentationGuide(info, 6, 5) == false

  test "No guide for negative charIdx":
    let e = createTestEditor()
    e.state.showIndentationLines = true
    e.state.tabStop = 2
    let info = IndentInfo(leadingWhitespaceEnd: 5, hasContent: true)

    check e.shouldShowIndentationGuide(info, 2, -1) == false

suite "getSelectionStyle - Basic":
  test "Returns cursor style at cursor position":
    let e = createTestEditor()
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showSyntax = false
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 10)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showSyntax = true
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 10)

    # Set up buffer with highlight
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "let x = 42")
    e.activeBuffer.language = SourceLanguage.langNim
    e.activeBuffer.highlight =
      initHighlight(@["let x = 42".toRunes], @[], SourceLanguage.langNim)

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 0,
      cursorCol = 10,
      windowMode = EditorMode.Visual,
    )
    # Background must be visual selection color
    check style.bg == visualStyle().bg
    # Foreground should come from syntax highlight, not visual selection
    let expectedFg = colorIndexToStyle(e.activeBuffer.highlight.getColorPair(0, 0)).fg
    check style.fg == expectedFg

  test "VisualLine selection preserves syntax highlight fg":
    let e = createTestEditor()
    e.state.mode = EditorMode.VisualLine
    e.state.showSyntax = true
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskLine
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 0)

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "let x = 42")
    e.activeBuffer.language = SourceLanguage.langNim
    e.activeBuffer.highlight =
      initHighlight(@["let x = 42".toRunes], @[], SourceLanguage.langNim)

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = true,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.VisualLine,
    )
    check style.bg == visualStyle().bg
    let expectedFg = colorIndexToStyle(e.activeBuffer.highlight.getColorPair(0, 0)).fg
    check style.fg == expectedFg

  test "Selection without syntax uses normal fg":
    let e = createTestEditor()
    e.state.mode = EditorMode.Visual
    e.state.showSyntax = false
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 10)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "(hello)")
    e.state.matchingParenPos = some(BufferPosition(line: 0, column: 6))

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 6),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check style == parenPairStyle()

  test "No paren pair style in an inactive window":
    # matchingParenPos is derived from the active window's cursor; an
    # inactive window showing the same line/column must not be painted.
    let e = createTestEditor()
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "(hello)")
    e.state.matchingParenPos = some(BufferPosition(line: 0, column: 6))

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 6),
      cursorLine = 0,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
      isActiveWindow = false,
    )
    check style != parenPairStyle()

suite "getSelectionStyle - Find char match highlight (f/F/t/T)":
  test "Returns findCharMatch style for matched position":
    let e = createTestEditor()
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style == findCharMatchStyle()

  test "Does not return findCharMatch style for non-matched position":
    let e = createTestEditor()
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 1),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

  test "Does not return findCharMatch style for different line":
    let e = createTestEditor()
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada\nabacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 1, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
    )
    check style != findCharMatchStyle()

  test "No findCharMatch style in an inactive window":
    # Find-char matches are anchored to the active window's cursor line; an
    # inactive window showing the same line/column must not be painted.
    let e = createTestEditor()
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 2),
      cursorLine = 0,
      cursorCol = 2,
      windowMode = EditorMode.Normal,
      isActiveWindow = false,
    )
    check style != findCharMatchStyle()

  test "No findCharMatch style when matches list is empty":
    let e = createTestEditor()
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showSyntax = false
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 6)
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "(abacada)")
    e.state.matchingParenPos = some(BufferPosition(line: 0, column: 8))
    e.state.ui.findCharMatches = @[1, 3, 5, 7]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abacada")
    e.state.ui.findCharMatches = @[0, 2, 4, 6]
    e.state.ui.findCharMatchLine = 0

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.input.search.hlsearch = true
    e.state.input.search.hlsearchTempDisabled = false
    e.state.input.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    e.state.showSyntax = false
    e.state.showCursorLine = false
    discard
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world hello")

    discard e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 5, # Cursor on different line
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No search highlight when hlsearch is disabled":
    let e = createTestEditor()
    e.state.input.search.hlsearch = false
    e.state.input.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    e.state.showSyntax = false
    e.state.showCursorLine = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 0),
      cursorLine = 5,
      cursorCol = 0,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No search highlight when hlsearchTempDisabled":
    let e = createTestEditor()
    e.state.input.search.hlsearch = true
    e.state.input.search.hlsearchTempDisabled = true
    e.state.input.search.lastText = "hello"
    e.state.mode = EditorMode.Normal
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorLine = true
    e.state.showSyntax = false
    e.state.showDocumentHighlight = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check true

  test "No cursor line style when showCursorLine is false":
    let e = createTestEditor()
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    discard e.getSelectionStyleAt(
      e.activeBuffer,
      hasSelection = false,
      pos = BufferPosition(line: 0, column: 3),
      cursorLine = 0,
      cursorCol = 5,
      windowMode = EditorMode.Normal,
    )
    check true

  test "searchResult highlight takes priority over cursor line bg":
    let e = createTestEditor()
    e.state.showCursorLine = true
    e.state.showSyntax = true
    e.state.showDocumentHighlight = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Set up highlight with searchResult color on columns 0-4
    let searchStyle = colorIndexToStyle(EditorColorPairIndex.searchResult)
    e.activeBuffer.highlight = Highlight(
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

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorLine = true
    e.state.showSyntax = true
    e.state.showDocumentHighlight = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Set up highlight with a normal (non-searchResult) color
    let defaultStyle = colorIndexToStyle(EditorColorPairIndex.default)
    e.activeBuffer.highlight = Highlight(
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

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorColumn = true
    e.state.showCursorLine = false
    e.state.showSyntax = false
    e.state.showDocumentHighlight = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorColumn = false
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorColumn = true
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorColumn = true
    e.state.showCursorLine = true
    e.state.showSyntax = false
    e.state.showDocumentHighlight = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # At intersection (same line AND same column): cursorLine wins
    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showCursorColumn = true
    e.state.showCursorLine = false
    e.state.showSyntax = false
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello world")

    # Without displayCol/cursorDisplayCol params (default -1), no column highlight
    let style = e.getSelectionStyleAt(
      e.activeBuffer,
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
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

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

  test "Current line highlights trailing spaces":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

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
    # Trailing spaces on the current line should be highlighted
    check buf[5, 0].style == trailingStyle
    check buf[6, 0].style == trailingStyle
    check buf[7, 0].style == trailingStyle

  test "Current line highlights trailing spaces when cursor-line highlight is on":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.showSyntax = false
    e.state.showCursorLine = true
    e.state.showIndentationLines = false

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
    # Even with cursor-line highlight on, trailing spaces on the current line
    # must still be visible: the per-cell trailing-space patch overrides the
    # cursor-line background.
    check buf[5, 0].style == trailingStyle
    check buf[6, 0].style == trailingStyle
    check buf[7, 0].style == trailingStyle

  test "Help mode does not highlight trailing spaces":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

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
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

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
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

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

suite "renderLineSegmentWithSelection - zero-width rune folding":
  proc plainEditor(): Editor =
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    result = newEditor(config, vr)
    result.state.showSyntax = false
    result.state.showCursorLine = false
    result.state.showIndentationLines = false

  test "Combining mark merges into the preceding base cell":
    var e = plainEditor()
    let text = "e" & $Rune(0x0301) & "X" # "éX" in NFD
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

    # The acute folds onto 'e'; 'X' keeps its own column instead of being
    # overwritten by a standalone zero-width cell.
    check buf[0, 0].symbol == "e" & $Rune(0x0301)
    check buf[1, 0].symbol == "X"
    check buf[2, 0].symbol == " "

  test "Variation selector folds onto a wide base, shadow preserved":
    var e = plainEditor()
    let text = "字" & $Rune(0xFE0E) & "z" # wide base + VS-15 + ascii
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

    check buf[0, 0].symbol == "字" & $Rune(0xFE0E)
    check buf[1, 0].symbol == "" # wide-char shadow intact
    check buf[2, 0].symbol == "z"

suite "renderLineSegmentWithSelection - full-width space highlight":
  test "Normal mode highlights full-width space":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.fullWidthSpace = true
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

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
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

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
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

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
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false
    e.state.tabStop = 4

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

  test "Current line highlights trailing tab":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false
    e.state.tabStop = 4

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
    # Trailing tab on the current line should be highlighted
    check buf[2, 0].style == trailingStyle

  test "Help mode does not highlight trailing tab":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.config.highlight.trailingSpaces = true
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false
    e.state.tabStop = 4

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

# Helpers for priority-chain tests.
proc setupDocumentHighlight(e: Editor, line, startCol, endCol, kind: int) =
  e.state.showDocumentHighlight = true
  e.state.lspCache.documentHighlightCache.isValid = true
  e.state.lspCache.documentHighlightCache.itemsByLine = {
    line: @[
      DocumentHighlightItem(
        line: line, startColumn: startCol, endColumn: endCol, kind: kind
      )
    ]
  }.toTable

suite "render layer predicates":
  test "matchesVisualSelection: hasSelection false short-circuits":
    let e = createTestEditor()
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 5)
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    check not e.matchesVisualSelection(false, BufferPosition(line: 0, column: 2))

  test "matchesVisualSelection: position inside selection":
    let e = createTestEditor()
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 5)
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    check e.matchesVisualSelection(true, BufferPosition(line: 0, column: 2))

  test "matchesVisualSelection: position outside selection":
    let e = createTestEditor()
    e.state.visualSelection.start = BufferPosition(line: 0, column: 0)
    e.state.visualSelection.current = BufferPosition(line: 0, column: 5)
    e.state.visualSelection.active = true
    e.state.visualSelection.kind = VisualSelectionKind.vskChar
    check not e.matchesVisualSelection(true, BufferPosition(line: 0, column: 9))

  test "matchesMatchingParen: positive match":
    let e = createTestEditor()
    e.state.matchingParenPos = some(BufferPosition(line: 2, column: 7))
    let lineCtx = LineStyleContext(isActiveWindow: true)
    check e.matchesMatchingParen(lineCtx, BufferPosition(line: 2, column: 7))

  test "matchesMatchingParen: different position":
    let e = createTestEditor()
    e.state.matchingParenPos = some(BufferPosition(line: 2, column: 7))
    let lineCtx = LineStyleContext(isActiveWindow: true)
    check not e.matchesMatchingParen(lineCtx, BufferPosition(line: 2, column: 8))
    check not e.matchesMatchingParen(lineCtx, BufferPosition(line: 3, column: 7))

  test "matchesMatchingParen: none set":
    let e = createTestEditor()
    e.state.matchingParenPos = none(BufferPosition)
    let lineCtx = LineStyleContext(isActiveWindow: true)
    check not e.matchesMatchingParen(lineCtx, BufferPosition(line: 0, column: 0))

  test "matchesMatchingParen: inactive window suppresses":
    let e = createTestEditor()
    e.state.matchingParenPos = some(BufferPosition(line: 2, column: 7))
    let lineCtx = LineStyleContext(isActiveWindow: false)
    check not e.matchesMatchingParen(lineCtx, BufferPosition(line: 2, column: 7))

  test "matchesFindCharMatch: in matches on right line":
    let e = createTestEditor()
    e.config.highlight.findCharHighlight = true
    e.state.ui.findCharMatchLine = 1
    e.state.ui.findCharMatches = @[3, 5, 9]
    let lineCtx = LineStyleContext(isActiveWindow: true)
    check e.matchesFindCharMatch(lineCtx, BufferPosition(line: 1, column: 5))

  test "matchesFindCharMatch: wrong line":
    let e = createTestEditor()
    e.config.highlight.findCharHighlight = true
    e.state.ui.findCharMatchLine = 1
    e.state.ui.findCharMatches = @[3, 5, 9]
    let lineCtx = LineStyleContext(isActiveWindow: true)
    check not e.matchesFindCharMatch(lineCtx, BufferPosition(line: 2, column: 5))

  test "matchesFindCharMatch: config disabled":
    let e = createTestEditor()
    e.config.highlight.findCharHighlight = false
    e.state.ui.findCharMatchLine = 1
    e.state.ui.findCharMatches = @[5]
    let lineCtx = LineStyleContext(isActiveWindow: true)
    check not e.matchesFindCharMatch(lineCtx, BufferPosition(line: 1, column: 5))

  test "matchesFindCharMatch: inactive window suppresses":
    let e = createTestEditor()
    e.config.highlight.findCharHighlight = true
    e.state.ui.findCharMatchLine = 1
    e.state.ui.findCharMatches = @[3, 5, 9]
    let lineCtx = LineStyleContext(isActiveWindow: false)
    check not e.matchesFindCharMatch(lineCtx, BufferPosition(line: 1, column: 5))

  test "matchesCurrentWord: word in range":
    let e = createTestEditor()
    let lineCtx = LineStyleContext(wordRanges: @[ColumnRange(startCol: 4, endCol: 9)])
    check e.matchesCurrentWord(lineCtx, BufferPosition(line: 0, column: 5))

  test "matchesCurrentWord: search overlay suppresses":
    let e = createTestEditor()
    e.state.overlay = some(OverlayKind.okSearch)
    let lineCtx = LineStyleContext(wordRanges: @[ColumnRange(startCol: 4, endCol: 9)])
    check not e.matchesCurrentWord(lineCtx, BufferPosition(line: 0, column: 5))

  test "matchesCurrentWord: outside range":
    let e = createTestEditor()
    let lineCtx = LineStyleContext(wordRanges: @[ColumnRange(startCol: 4, endCol: 9)])
    check not e.matchesCurrentWord(lineCtx, BufferPosition(line: 0, column: 2))

  test "matchesSearchHighlight: column in search range":
    let lineCtx = LineStyleContext(searchRanges: @[ColumnRange(startCol: 0, endCol: 4)])
    check lineCtx.matchesSearchHighlight(BufferPosition(line: 0, column: 2))
    check not lineCtx.matchesSearchHighlight(BufferPosition(line: 0, column: 4))

  test "gitConflictApplies: cmkNone is false":
    let lineCtx = LineStyleContext(lineConflict: cmkNone)
    check not lineCtx.gitConflictApplies

  test "gitConflictApplies: any other kind is true":
    let lineCtx = LineStyleContext(lineConflict: cmkOurs)
    check lineCtx.gitConflictApplies

  test "cursorLineApplies: both conditions true":
    let e = createTestEditor()
    e.state.showCursorLine = true
    let lineCtx = LineStyleContext(isCursorLine: true)
    check e.cursorLineApplies(lineCtx)

  test "cursorLineApplies: showCursorLine off":
    let e = createTestEditor()
    e.state.showCursorLine = false
    let lineCtx = LineStyleContext(isCursorLine: true)
    check not e.cursorLineApplies(lineCtx)

  test "cursorLineApplies: not on cursor line":
    let e = createTestEditor()
    e.state.showCursorLine = true
    let lineCtx = LineStyleContext(isCursorLine: false)
    check not e.cursorLineApplies(lineCtx)

  test "cursorColumnApplies: all conditions true":
    let e = createTestEditor()
    e.state.showCursorColumn = true
    check e.cursorColumnApplies(displayCol = 5, cursorDisplayCol = 5)

  test "cursorColumnApplies: config off":
    let e = createTestEditor()
    e.state.showCursorColumn = false
    check not e.cursorColumnApplies(displayCol = 5, cursorDisplayCol = 5)

  test "cursorColumnApplies: displayCol is -1 sentinel":
    let e = createTestEditor()
    e.state.showCursorColumn = true
    check not e.cursorColumnApplies(displayCol = -1, cursorDisplayCol = -1)

  test "cursorColumnApplies: columns differ":
    let e = createTestEditor()
    e.state.showCursorColumn = true
    check not e.cursorColumnApplies(displayCol = 3, cursorDisplayCol = 5)

suite "charOverridePatch":
  proc fileEditCtx(): RenderContext =
    RenderContext(windowMode: EditorMode.Normal, windowRightEdge: 80)

  proc helpCtx(): RenderContext =
    # Help mode is NOT a file edit mode; per-char overrides should suppress.
    RenderContext(windowMode: EditorMode.Help, windowRightEdge: 80)

  test "no override returns noPatch":
    let e = createTestEditor()
    e.config.highlight.fullWidthSpace = false
    e.config.highlight.trailingSpaces = false
    let ctx = fileEditCtx()
    let lineCtx = LineStyleContext()
    let p = e.charOverridePatch(ctx, lineCtx, 'a'.Rune, 0)
    check p == noPatch

  test "fullWidthSpace fires for FULLWIDTH_SPACE rune":
    let e = createTestEditor()
    e.config.highlight.fullWidthSpace = true
    let ctx = fileEditCtx()
    let lineCtx = LineStyleContext()
    let p = e.charOverridePatch(ctx, lineCtx, FULLWIDTH_SPACE, 3)
    check p == full(fullWidthSpaceStyle())

  test "fullWidthSpace ignored outside file edit mode":
    let e = createTestEditor()
    e.config.highlight.fullWidthSpace = true
    let ctx = helpCtx()
    let lineCtx = LineStyleContext()
    let p = e.charOverridePatch(ctx, lineCtx, FULLWIDTH_SPACE, 3)
    check p == noPatch

  test "trailingSpaces fires for trailing space char":
    let e = createTestEditor()
    e.config.highlight.trailingSpaces = true
    let ctx = fileEditCtx()
    let lineCtx = LineStyleContext(trailingSpaceStart: 5, isCursorLine: false)
    let p = e.charOverridePatch(ctx, lineCtx, ' '.Rune, 7)
    check p == full(trailingSpacesStyle())

  test "trailingSpaces fires on cursor line":
    let e = createTestEditor()
    e.config.highlight.trailingSpaces = true
    let ctx = fileEditCtx()
    let lineCtx = LineStyleContext(trailingSpaceStart: 5, isCursorLine: true)
    let p = e.charOverridePatch(ctx, lineCtx, ' '.Rune, 7)
    check p == full(trailingSpacesStyle())

  test "trailingSpaces ignored before trailingSpaceStart":
    let e = createTestEditor()
    e.config.highlight.trailingSpaces = true
    let ctx = fileEditCtx()
    let lineCtx = LineStyleContext(trailingSpaceStart: 5, isCursorLine: false)
    let p = e.charOverridePatch(ctx, lineCtx, ' '.Rune, 4)
    check p == noPatch

  test "trailingSpaces ignored for non-whitespace rune":
    let e = createTestEditor()
    e.config.highlight.trailingSpaces = true
    let ctx = fileEditCtx()
    let lineCtx = LineStyleContext(trailingSpaceStart: 5, isCursorLine: false)
    let p = e.charOverridePatch(ctx, lineCtx, 'x'.Rune, 7)
    check p == noPatch

  test "colorCode override beats trailingSpaces":
    let e = createTestEditor()
    e.config.highlight.trailingSpaces = true
    let ctx = fileEditCtx()
    let ccStyle = Style(
      fg: ColorValue(kind: Default),
      bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 1, g: 2, b: 3)),
      modifiers: {},
    )
    let lineCtx = LineStyleContext(
      trailingSpaceStart: 5,
      isCursorLine: false,
      colorCodeMatches: @[ColorCodeMatch(startCol: 6, endCol: 8, style: ccStyle)],
    )
    let p = e.charOverridePatch(ctx, lineCtx, ' '.Rune, 7)
    check p == full(ccStyle)

  test "colorCode requires col within range":
    let e = createTestEditor()
    let ctx = fileEditCtx()
    let ccStyle = Style(
      fg: ColorValue(kind: Default),
      bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 1, g: 2, b: 3)),
      modifiers: {},
    )
    let lineCtx = LineStyleContext(
      colorCodeMatches: @[ColorCodeMatch(startCol: 6, endCol: 8, style: ccStyle)]
    )
    check e.charOverridePatch(ctx, lineCtx, 'a'.Rune, 5) == noPatch
    check e.charOverridePatch(ctx, lineCtx, 'a'.Rune, 6) == full(ccStyle)
    check e.charOverridePatch(ctx, lineCtx, 'a'.Rune, 8) == full(ccStyle)
    check e.charOverridePatch(ctx, lineCtx, 'a'.Rune, 9) == noPatch

  test "trailingSpaces overrides fullWidthSpace at trailing position":
    let e = createTestEditor()
    e.config.highlight.fullWidthSpace = true
    e.config.highlight.trailingSpaces = true
    let ctx = fileEditCtx()
    let lineCtx = LineStyleContext(trailingSpaceStart: 5, isCursorLine: false)
    let p = e.charOverridePatch(ctx, lineCtx, FULLWIDTH_SPACE, 7)
    check p == full(trailingSpacesStyle())

  test "trailingSpaces fires for TAB rune at trailing position":
    let e = createTestEditor()
    e.config.highlight.trailingSpaces = true
    let ctx = fileEditCtx()
    let lineCtx = LineStyleContext(trailingSpaceStart: 5, isCursorLine: false)
    let p = e.charOverridePatch(ctx, lineCtx, TAB_CHAR, 7)
    check p == full(trailingSpacesStyle())

suite "overlayPatchSyntax priority chain":
  test "documentHighlight wins over gitConflict":
    let e = createTestEditor()
    e.setupDocumentHighlight(line = 0, startCol = 0, endCol = 5, kind = 2) # Read
    let pos = BufferPosition(line: 0, column: 2)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = -1,
      displayCol = -1,
      cursorDisplayCol = -1,
      lineConflict = cmkOurs,
      useTwoColor = true,
      colorPair = EditorColorPairIndex.default,
    )
    check patch.bg == some(getDocumentHighlightStyle(2).bg)

  test "documentHighlight wins over cursorLine":
    let e = createTestEditor()
    e.state.showCursorLine = true
    e.setupDocumentHighlight(line = 0, startCol = 0, endCol = 5, kind = 3) # Write
    let pos = BufferPosition(line: 0, column: 2)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = 0,
      displayCol = -1,
      cursorDisplayCol = -1,
      lineConflict = cmkNone,
      useTwoColor = false,
      colorPair = EditorColorPairIndex.default,
    )
    check patch.bg == some(getDocumentHighlightStyle(3).bg)

  test "gitConflict wins over cursorLine":
    let e = createTestEditor()
    e.state.showCursorLine = true
    let pos = BufferPosition(line: 0, column: 0)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = 0,
      displayCol = -1,
      cursorDisplayCol = -1,
      lineConflict = cmkOurs,
      useTwoColor = true,
      colorPair = EditorColorPairIndex.default,
    )
    check patch.bg == some(conflictStyleFor(cmkOurs, true).bg)

  test "gitConflict wins over cursorColumn":
    let e = createTestEditor()
    e.state.showCursorColumn = true
    let pos = BufferPosition(line: 0, column: 5)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = -1,
      displayCol = 5,
      cursorDisplayCol = 5,
      lineConflict = cmkTheirs,
      useTwoColor = true,
      colorPair = EditorColorPairIndex.default,
    )
    check patch.bg == some(conflictStyleFor(cmkTheirs, true).bg)

  test "cursorLine wins over cursorColumn":
    let e = createTestEditor()
    e.state.showCursorLine = true
    e.state.showCursorColumn = true
    let pos = BufferPosition(line: 0, column: 5)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = 0,
      displayCol = 5,
      cursorDisplayCol = 5,
      lineConflict = cmkNone,
      useTwoColor = false,
      colorPair = EditorColorPairIndex.default,
    )
    check patch.bg == some(cursorLineHighlightStyle().bg)

  test "searchResult colorPair suppresses cursorLine/cursorColumn":
    let e = createTestEditor()
    e.state.showCursorLine = true
    e.state.showCursorColumn = true
    let pos = BufferPosition(line: 0, column: 5)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = 0,
      displayCol = 5,
      cursorDisplayCol = 5,
      lineConflict = cmkNone,
      useTwoColor = false,
      colorPair = EditorColorPairIndex.searchResult,
    )
    check patch == noPatch

  test "searchResult colorPair does not suppress gitConflict":
    let e = createTestEditor()
    e.state.showCursorLine = true
    let pos = BufferPosition(line: 0, column: 0)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = 0,
      displayCol = -1,
      cursorDisplayCol = -1,
      lineConflict = cmkBase,
      useTwoColor = true,
      colorPair = EditorColorPairIndex.searchResult,
    )
    check patch.bg == some(conflictStyleFor(cmkBase, true).bg)

  test "searchResult colorPair does not suppress documentHighlight":
    let e = createTestEditor()
    e.setupDocumentHighlight(line = 0, startCol = 0, endCol = 5, kind = 1) # Text
    let pos = BufferPosition(line: 0, column: 2)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = -1,
      displayCol = -1,
      cursorDisplayCol = -1,
      lineConflict = cmkNone,
      useTwoColor = false,
      colorPair = EditorColorPairIndex.searchResult,
    )
    check patch.bg == some(getDocumentHighlightStyle(1).bg)

  test "no overrides returns noPatch":
    let e = createTestEditor()
    e.state.showCursorLine = false
    e.state.showCursorColumn = false
    let pos = BufferPosition(line: 0, column: 0)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = 0,
      displayCol = 0,
      cursorDisplayCol = 0,
      lineConflict = cmkNone,
      useTwoColor = false,
      colorPair = EditorColorPairIndex.default,
    )
    check patch == noPatch

  test "cursorLine not applied when showCursorLine is off":
    let e = createTestEditor()
    e.state.showCursorLine = false
    let pos = BufferPosition(line: 0, column: 0)
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = 0,
      displayCol = -1,
      cursorDisplayCol = -1,
      lineConflict = cmkNone,
      useTwoColor = false,
      colorPair = EditorColorPairIndex.default,
    )
    check patch == noPatch

  test "cursorColumn requires non-negative displayCol":
    let e = createTestEditor()
    e.state.showCursorColumn = true
    let pos = BufferPosition(line: 0, column: 0)
    # displayCol = -1 means the column position is unknown / not applicable
    let patch = e.overlayPatchSyntaxAt(
      pos = pos,
      cursorLine = -1,
      displayCol = -1,
      cursorDisplayCol = -1,
      lineConflict = cmkNone,
      useTwoColor = false,
      colorPair = EditorColorPairIndex.default,
    )
    check patch == noPatch

suite "lineFillPatch priority chain":
  test "visualSelection wins over gitConflict":
    let e = createTestEditor()
    let patch = e.lineFillPatchAt(
      lineIndex = 0,
      cursorLine = -1,
      displayX = 0,
      cursorDisplayCol = -1,
      lineConflict = cmkOurs,
      useTwoColor = true,
      inVisualSelection = true,
    )
    check patch == full(visualStyle())

  test "visualSelection wins over cursorLine":
    let e = createTestEditor()
    e.state.showCursorLine = true
    let patch = e.lineFillPatchAt(
      lineIndex = 0,
      cursorLine = 0,
      displayX = 0,
      cursorDisplayCol = -1,
      lineConflict = cmkNone,
      useTwoColor = false,
      inVisualSelection = true,
    )
    check patch == full(visualStyle())

  test "gitConflict wins over cursorLine":
    let e = createTestEditor()
    e.state.showCursorLine = true
    let patch = e.lineFillPatchAt(
      lineIndex = 0,
      cursorLine = 0,
      displayX = 0,
      cursorDisplayCol = -1,
      lineConflict = cmkTheirs,
      useTwoColor = true,
      inVisualSelection = false,
    )
    check patch == full(conflictStyleFor(cmkTheirs, true))

  test "gitConflict wins over cursorColumn":
    let e = createTestEditor()
    e.state.showCursorColumn = true
    let patch = e.lineFillPatchAt(
      lineIndex = 0,
      cursorLine = -1,
      displayX = 5,
      cursorDisplayCol = 5,
      lineConflict = cmkBase,
      useTwoColor = true,
      inVisualSelection = false,
    )
    check patch == full(conflictStyleFor(cmkBase, true))

  test "cursorLine wins over cursorColumn":
    let e = createTestEditor()
    e.state.showCursorLine = true
    e.state.showCursorColumn = true
    let patch = e.lineFillPatchAt(
      lineIndex = 0,
      cursorLine = 0,
      displayX = 5,
      cursorDisplayCol = 5,
      lineConflict = cmkNone,
      useTwoColor = false,
      inVisualSelection = false,
    )
    check patch == full(cursorLineHighlightStyle())

  test "cursorColumn applied when only cursorColumn matches":
    let e = createTestEditor()
    e.state.showCursorLine = true
    e.state.showCursorColumn = true
    let patch = e.lineFillPatchAt(
      lineIndex = 0,
      cursorLine = 1, # different line
      displayX = 5,
      cursorDisplayCol = 5,
      lineConflict = cmkNone,
      useTwoColor = false,
      inVisualSelection = false,
    )
    check patch == full(cursorColumnHighlightStyle())

  test "no overrides returns noPatch":
    let e = createTestEditor()
    e.state.showCursorLine = false
    e.state.showCursorColumn = false
    let patch = e.lineFillPatchAt(
      lineIndex = 0,
      cursorLine = 0,
      displayX = 0,
      cursorDisplayCol = 0,
      lineConflict = cmkNone,
      useTwoColor = false,
      inVisualSelection = false,
    )
    check patch == noPatch

  test "cursorColumn requires non-negative cursorDisplayCol":
    let e = createTestEditor()
    e.state.showCursorColumn = true
    let patch = e.lineFillPatchAt(
      lineIndex = 0,
      cursorLine = -1,
      displayX = 5,
      cursorDisplayCol = -1,
      lineConflict = cmkNone,
      useTwoColor = false,
      inVisualSelection = false,
    )
    check patch == noPatch

import ../src/moepkg/virtual_text

proc stubProvider(items: seq[VirtualText]): VirtualTextProvider =
  result = proc(line: int): seq[VirtualText] {.closure, gcsafe, raises: [].} =
    for it in items:
      if it.line == line:
        result.add it

suite "renderLineSegmentWithSelection - end-of-line virtual text":
  test "appends virtual text after real text with inlay hint style":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

    let tb = newTextBuffer("abc")
    var buf = newBuffer(80, 1)
    let provider = stubProvider(
      @[
        VirtualText(
          line: 0,
          placement: vtpEndOfLine,
          chunks:
            @[VirtualTextChunk(text: ":int", color: EditorColorPairIndex.inlayHint)],
        )
      ]
    )
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[provider],
    )

    e.renderLineSegmentWithSelection(tb, buf, "abc", 0, 0, 0, 0, ctx)

    let hintStyle = colorIndexToStyle(EditorColorPairIndex.inlayHint)
    check buf[3, 0].symbol == ":"
    check buf[4, 0].symbol == "i"
    check buf[5, 0].symbol == "n"
    check buf[6, 0].symbol == "t"
    check buf[3, 0].style == hintStyle
    check buf[6, 0].style == hintStyle
    # Cells after the virtual text are filled with spaces
    check buf[7, 0].symbol == " "

  test "clips virtual text at the window right edge":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

    let tb = newTextBuffer("abc")
    var buf = newBuffer(80, 1)
    let provider = stubProvider(
      @[
        VirtualText(
          line: 0,
          placement: vtpEndOfLine,
          chunks:
            @[VirtualTextChunk(text: ":int", color: EditorColorPairIndex.inlayHint)],
        )
      ]
    )
    # Right edge at 5: only ':' (col 3) and 'i' (col 4) fit.
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 5,
      virtualTextProviders: @[provider],
    )

    e.renderLineSegmentWithSelection(tb, buf, "abc", 0, 0, 0, 0, ctx)

    check buf[3, 0].symbol == ":"
    check buf[4, 0].symbol == "i"
    # Column 5 is past the right edge; nothing drawn there.
    check buf[5, 0].symbol != "n"

  test "no providers leaves rendering unchanged (fills with spaces)":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false

    let tb = newTextBuffer("abc")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[],
    )

    e.renderLineSegmentWithSelection(tb, buf, "abc", 0, 0, 0, 0, ctx)

    check buf[3, 0].symbol == " "
    check buf[4, 0].symbol == " "

proc inlayHintProvider(): VirtualTextProvider =
  stubProvider(
    @[
      VirtualText(
        line: 0,
        placement: vtpEndOfLine,
        chunks:
          @[VirtualTextChunk(text: ":hint", color: EditorColorPairIndex.inlayHint)],
      )
    ]
  )

proc rowHasHint(buffer: Buffer): bool =
  for x in 0 ..< 80:
    if buffer[x, 0].symbol == ":":
      return true
  false

suite "Empty-line end-of-line virtual text":
  test "no-wrap draws virtual text on an empty line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[inlayHintProvider()],
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)
    check buffer.rowHasHint

  test "no-wrap skips virtual text when scrolled past the line end":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abc")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 10 # scrolled past the 3-rune line

    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[inlayHintProvider()],
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)
    check not buffer.rowHasHint

  test "no-wrap draws virtual text after a fully visible line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "abc")

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[inlayHintProvider()],
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)
    check buffer.rowHasHint

  test "no-wrap skips virtual text on a line truncated at the window edge":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # 100-rune line in a 40-column window: the line end is off-screen, so no
    # part of the hint may be drawn at the truncation point. windowRightEdge
    # is wider than the text budget (as with a scrollbar gutter) so clipping
    # alone would not hide a stray hint rune.
    var longLine = ""
    for _ in 0 ..< 100:
      longLine.add "a"
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), longLine)

    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[inlayHintProvider()],
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)
    check not buffer.rowHasHint

  test "no-wrap draws virtual text after a fully visible multibyte line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    # 10 CJK runes: 30 bytes but only 20 display cells. In a 40-column window
    # the line end is on-screen, so the hint must be drawn. Gating on byte
    # length (30) vs the cell budget would wrongly hide it.
    var cjkLine = ""
    for _ in 0 ..< 10:
      cjkLine.add "あ"
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), cjkLine)

    let window = e.windowManager.windows[0]
    window.viewport.width = 40
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 40,
      virtualTextProviders: @[inlayHintProvider()],
    )

    e.renderWindowLineNoWrap(buffer, window, 0, ctx, 0, 0)
    check buffer.rowHasHint

  test "wrapped draws virtual text on an empty line":
    let e = createTestEditor()
    var buffer = createTestBuffer()

    let window = e.windowManager.windows[0]
    window.viewport.width = 80
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[inlayHintProvider()],
    )

    var screenY = 0
    var lineIndex = 0
    e.renderWindowLineWrapped(buffer, window, 0, ctx, screenY, lineIndex, 20, 0)
    check buffer.rowHasHint

suite "End-of-line virtual text - cursor line highlight":
  test "virtual text cells take the cursor-line background but keep the hint fg":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.state.showSyntax = false
    e.state.showCursorLine = true
    e.state.showIndentationLines = false

    let tb = newTextBuffer("abc")
    var buf = newBuffer(80, 1)
    let provider = stubProvider(
      @[
        VirtualText(
          line: 0,
          placement: vtpEndOfLine,
          chunks:
            @[VirtualTextChunk(text: ":int", color: EditorColorPairIndex.inlayHint)],
        )
      ]
    )
    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[provider],
    )

    e.renderLineSegmentWithSelection(tb, buf, "abc", 0, 0, 0, 0, ctx)

    let
      hlStyle = cursorLineHighlightStyle()
      hintStyle = colorIndexToStyle(EditorColorPairIndex.inlayHint)
    # The hint text keeps its own foreground but shares the cursor-line bg, so
    # the current-line highlight extends across the virtual text, not just the
    # real text and the trailing fill.
    check buf[3, 0].symbol == ":"
    check buf[6, 0].symbol == "t"
    check buf[3, 0].style.bg == hlStyle.bg
    check buf[6, 0].style.bg == hlStyle.bg
    check buf[3, 0].style.fg == hintStyle.fg
    check buf[6, 0].style.fg == hintStyle.fg
    # The trailing fill past the hint stays on the cursor-line bg too.
    check buf[7, 0].symbol == " "
    check buf[7, 0].style.bg == hlStyle.bg

  test "virtual text keeps the plain hint style off the cursor line":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.state.showSyntax = false
    e.state.showCursorLine = true
    e.state.showIndentationLines = false

    let tb = newTextBuffer("abc\ndef")
    var buf = newBuffer(80, 2)
    let provider = stubProvider(
      @[
        VirtualText(
          line: 1,
          placement: vtpEndOfLine,
          chunks:
            @[VirtualTextChunk(text: ":int", color: EditorColorPairIndex.inlayHint)],
        )
      ]
    )
    # Cursor on line 0; the hint is on line 1 (a non-cursor line).
    let ctx = RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: @[provider],
    )

    e.renderLineSegmentWithSelection(tb, buf, "def", 0, 1, 1, 0, ctx)

    let hintStyle = colorIndexToStyle(EditorColorPairIndex.inlayHint)
    check buf[3, 1].symbol == ":"
    check buf[3, 1].style == hintStyle
    check buf[6, 1].style == hintStyle

  test "real inlayHintVirtualTextProvider prepends a space":
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    var e = newEditor(config, vr)
    e.state.showSyntax = false
    e.state.showCursorLine = false
    e.state.showIndentationLines = false
    e.state.showInlayHint = true
    e.activeBuffer().filePath = some("/test/file.nim")

    # Populate the inlay hint cache so the real provider yields text.
    e.state.lspCache.inlayHintCache = InlayHintCache(
      isValid: true,
      filePath: "/test/file.nim",
      changeSeq: e.activeBuffer().changeSeq,
      itemsByLine:
        {0: @[InlayHintItem(line: 0, column: 3, label: ":int", kind: 1)]}.toTable,
    )

    let providers = e.buildVirtualTextProviders()
    check providers.len == 1

    let tb = newTextBuffer("abc")
    var buf = newBuffer(80, 1)
    let ctx = RenderContext(
      cursorLine: -1,
      cursorCol: -1,
      hasSelection: false,
      windowMode: EditorMode.Normal,
      windowRightEdge: 80,
      virtualTextProviders: providers,
    )

    e.renderLineSegmentWithSelection(tb, buf, "abc", 0, 0, 0, 0, ctx)

    let hintStyle = colorIndexToStyle(EditorColorPairIndex.inlayHint)
    # Real text "abc" occupies cols 0,1,2.
    # The provider prepends " " → label ":int" → total " :int".
    check buf[3, 0].symbol == " "
    check buf[3, 0].style == hintStyle
    check buf[4, 0].symbol == ":"
    check buf[5, 0].symbol == "i"
    check buf[6, 0].symbol == "n"
    check buf[7, 0].symbol == "t"
    # Cells after the virtual text are filled with plain spaces.
    check buf[8, 0].symbol == " "

suite "renderWindowLineNoWrap - display-width clipping":
  proc plainNoWrapEditor(): Editor =
    ## No-wrap editor with every cell-adding decoration disabled so that
    ## cellBudget == viewport.width and the rendered columns are deterministic.
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    let vr = newValidationResult()
    result = newEditor(config, vr)
    result.state.showSyntax = false
    result.state.showCursorLine = false
    result.state.showIndentationLines = false
    result.state.showSidebar = false
    result.state.scrollbar = false

  proc noWrapCtx(): RenderContext =
    RenderContext(
      cursorLine: 0,
      cursorCol: 0,
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
      windowRightEdge: 80,
    )

  test "CJK line fills the budget instead of being byte-truncated":
    # 10 wide runes = 20 display cells but 30 bytes. With cellBudget 25 the old
    # `min(displayLine.len, cellBudget)` byte-sliced at 25 bytes and dropped the
    # last runes; clipping by display width keeps all 10 on screen.
    let e = plainNoWrapEditor()
    var buffer = createTestBuffer()
    discard
      e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "あ".repeat(10))

    let window = e.windowManager.windows[0]
    window.viewport.width = 25
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    e.renderWindowLineNoWrap(buffer, window, 0, noWrapCtx(), 0, 0)

    # Each wide rune occupies two cells, so the 10th rune leads at col 18.
    check buffer[0, 0].symbol == "あ"
    check buffer[18, 0].symbol == "あ"
    check buffer[19, 0].symbol == "" # wide-char shadow

  test "Tab-heavy line stops at the budget instead of overflowing the edge":
    # tab (8 cells) + 30 'X'. With cellBudget 25 the old byte-slice (31 bytes
    # clamped to 25) still emitted runes past col 24; clipping by display width
    # stops at the budget so nothing is drawn beyond it.
    let e = plainNoWrapEditor()
    e.state.tabStop = 8
    var buffer = createTestBuffer()
    discard e.activeBuffer.insertText(
      BufferPosition(line: 0, column: 0), "\t" & "X".repeat(30)
    )

    let window = e.windowManager.windows[0]
    window.viewport.width = 25
    window.viewport.height = 24
    window.viewport.x = 0
    window.viewport.y = 0
    window.viewport.leftColumn = 0

    e.renderWindowLineNoWrap(buffer, window, 0, noWrapCtx(), 0, 0)

    # The tab expands to cols 0..7; 'X' runs from col 8. The last cell within
    # the 25-cell budget is col 24 and must hold an 'X'; col 25 must not.
    check buffer[24, 0].symbol == "X"
    check buffer[25, 0].symbol != "X"
