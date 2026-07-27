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

## Pure layout/geometry calculations for editor windows.
## These procs are side-effect-free helpers used by both the window
## management layer and the rendering layer.

import types/editor_types, render_utils, buffer/core, visible_rows

proc calculateReservedLines*(e: Editor, isBottomWindow: bool = true): int =
  ## Calculate number of reserved lines based on status line configuration
  ## and the dynamic command-line area height (wrapped overlay input and
  ## multi-line status messages grow the bottom reserve)
  if isBottomWindow:
    e.state.bottomAreaHeight(e.screenSize.width)
  else:
    if e.showStatusLine and e.multiStatusLine: StatusLineReserve else: 0

proc steadyReservedLines*(e: Editor, isBottomWindow: bool): int =
  ## `calculateReservedLines` with the steady bottom-area floor, so it is stable
  ## against transient command-line growth (wrapped input, multi-line messages).
  ## The viewport scroll and the screen-cursor clamp must share this; clamping
  ## with the dynamic reserve instead flings a bottom-row cursor to (0, 0).
  if isBottomWindow:
    steadyBottomAreaHeight()
  else:
    e.calculateReservedLines(isBottomWindow)

proc terminalContentRows*(
    window: EditorWindow, isBottomWindow: bool, tabLineOffset: int
): int =
  ## Rows available for a terminal grid in a window. Shared by renderTerminal
  ## and calculateTerminalAreaDimensions so the rendered grid and the PTY size
  ## can never diverge.
  ## Deliberately steady, not dynamic: PTY resize sends SIGWINCH to the
  ## shell, so transient command-line growth must not flap the PTY size.
  window.viewport.height - steadyReservedBottom(isBottomWindow) - tabLineOffset

proc calculateTerminalAreaDimensions*(
    e: Editor, window: EditorWindow
): tuple[cols, rows: int] =
  ## Compute the correct PTY cols/rows for a terminal in the given window.
  let
    maxBottomY = findMaxBottomY(e.windowManager.windows)
    windowBottomY = window.viewport.y + window.viewport.height
    isBottomWindow = (windowBottomY == maxBottomY)
    tabLineOffset = if e.showTabLine: TabLineHeight else: 0
  result = (
    cols: window.viewport.width,
    rows: max(1, terminalContentRows(window, isBottomWindow, tabLineOffset)),
  )

proc calculateSidebarWidth*(e: Editor, window: EditorWindow): int =
  ## Calculate the width occupied by the sidebar (0 if disabled).
  sidebarWidthFor(window, e.showSidebar)

proc calculateScrollbarWidth*(e: Editor, window: EditorWindow): int =
  ## Calculate the width occupied by the scrollbar (0 if disabled or non-edit mode)
  scrollbarWidthFor(window, e.scrollbar, e.scrollbarWidth)

proc gutterWidth*(e: Editor, window: EditorWindow): int =
  ## Sidebar + line-number width: the X offset of the text area's first column.
  e.calculateSidebarWidth(window) +
    calculateLineNumOffset(window.buffer, e.showLineNumbers)

proc viewportOffsetFor*(e: Editor, window: EditorWindow, lineNumOffset: int): int =
  ## Everything in the window that is not text: line number + sidebar +
  ## scrollbar. Takes the line-number width the caller is drawing with.
  lineNumOffset + e.calculateSidebarWidth(window) + e.calculateScrollbarWidth(window)

proc viewportOffsetFor*(e: Editor, window: EditorWindow): int =
  ## `viewportOffsetFor` with the window's own line-number width.
  viewportOffsetFor(
    window.buffer, window, e.showLineNumbers, e.showSidebar, e.scrollbar,
    e.scrollbarWidth,
  )

proc textAreaWidth*(e: Editor, window: EditorWindow, lineNumOffset: int): int =
  ## Cells the window leaves for text. Single source for the renderer, the
  ## screen-cursor pass and the mouse hit-test.
  textAreaWidthFor(window.viewport.width, e.viewportOffsetFor(window, lineNumOffset))

proc textAreaWidth*(e: Editor, window: EditorWindow): int =
  ## `textAreaWidth` with the window's own line-number width.
  textAreaWidthFor(window.viewport.width, e.viewportOffsetFor(window))

proc wrapWidth*(e: Editor, window: EditorWindow, lineNumOffset: int): int =
  ## `textAreaWidth` clamped to at least one cell: the `WrapCountCache` key.
  wrapWidthFor(window.viewport.width, e.viewportOffsetFor(window, lineNumOffset))

proc wrapWidth*(e: Editor, window: EditorWindow): int =
  ## `wrapWidth` with the window's own line-number width.
  wrapWidthFor(window.viewport.width, e.viewportOffsetFor(window))

proc renderedCellPos*(
    e: Editor, window: EditorWindow, lineText: string, column: int
): tuple[row, cellX: int] =
  ## Row and display column where `column` of `lineText` is drawn, relative to
  ## the text area start. `row` is the wrap segment index (always 0 without
  ## `lineWrap`). Tabs are expanded from the origin the renderer sliced at, so
  ## two columns' `cellX` are only comparable when their `row` matches.
  let (wrapSeg, cellX) = textCell(
    lineText,
    column,
    e.lineWrap,
    e.wrapWidth(window),
    e.tabStop,
    window.viewport.leftColumn,
  )
  (row: wrapSeg, cellX: cellX)

proc rowLayoutFor*(
    e: Editor,
    buffer: TextBuffer,
    viewportWidth, gutterAndScrollbar: int,
    wrapCache: WrapCountCache,
): RowLayout =
  ## `RowLayout` for a window whose text area starts after `gutterAndScrollbar`
  ## cells, using the same wrap width the renderer wrapped at.
  initRowLayout(
    buffer,
    wrapCache,
    e.lineWrap,
    wrapWidthFor(viewportWidth, gutterAndScrollbar),
    e.tabStop,
  )

proc calculateWindowCursor*(
    e: Editor,
    buffer: TextBuffer,
    viewport: ViewPort,
    cursor: BufferPosition,
    gutterWidth: int,
    reservedLines: int,
    scrollbarWidth: int = 0,
    wrapCache: WrapCountCache = nil,
): CursorPosition =
  ## Calculate screen cursor position for a window
  ## Returns the absolute screen coordinates
  ## `gutterWidth` is the sidebar + line-number width the text starts after.

  # Validate cursor is within buffer bounds
  if cursor.line < 0 or cursor.line >= buffer.len:
    return CursorPosition(x: 0, y: 0)

  # Cursor is above visible area
  if cursor.line < viewport.topLine:
    return CursorPosition(x: 0, y: 0)

  let
    rl = e.rowLayoutFor(buffer, viewport.width, gutterWidth + scrollbarWidth, wrapCache)
    visibleRows = viewport.height - reservedLines
    (wrapSeg, cellX) = rl.cursorCell(cursor.line, cursor.column, viewport.leftColumn)
    # `rowOfLine` stops once the walk passes the last visible row, so a cursor
    # far below the viewport costs O(visibleRows), not O(lines).
    screenY =
      rl.rowOfLine(viewport.topLine, viewport.topWrapOffset, cursor.line, visibleRows) +
      wrapSeg

  # Guard the lower bound too: with topWrapOffset > 0 a cursor on a segment
  # above the visible top computes a negative screenY.
  if screenY < 0 or screenY >= visibleRows:
    return CursorPosition(x: 0, y: 0)

  CursorPosition(x: viewport.x + gutterWidth + cellX, y: viewport.y + screenY)
