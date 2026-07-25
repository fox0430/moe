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

import types/editor_types, render_utils, buffer

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

  if e.lineWrap:
    # WRAP MODE: Calculate cursor position considering line wrapping
    let maxWidth = wrapWidthFor(viewport.width, gutterWidth + scrollbarWidth)

    if wrapCache != nil:
      wrapCache.ensureFresh(buffer, maxWidth, e.tabStop)

    # Start above the top edge by the wrap segments skipped on the first line:
    # the loop below adds topLine's full wrap count, so a non-zero offset shifts
    # every screen row up by exactly the hidden leading segments.
    var screenY = -viewport.topWrapOffset

    var lineIdx = viewport.topLine
    while lineIdx < cursor.line:
      if lineIdx < 0 or lineIdx >= buffer.len:
        inc lineIdx
        continue
      # A collapsed fold renders as a single marker row at its start line; its
      # hidden interior occupies no rows. Count the marker once and jump past
      # the interior in one step so a large fold above the cursor costs O(1),
      # not O(lines).
      let collapsed = buffer.foldState.getCollapsedFoldAt(lineIdx)
      if collapsed.isSome:
        if collapsed.get.startLine == lineIdx:
          screenY += 1
        lineIdx = collapsed.get.endLine + 1
      else:
        let wrappedLines =
          if wrapCache != nil:
            wrapCache.cachedWrapCount(buffer, lineIdx)
          else:
            calculateWrapCount(buffer.getLine(lineIdx), maxWidth, e.tabStop)
        screenY += wrappedLines
        inc lineIdx

      if screenY >= viewport.height - reservedLines:
        return CursorPosition(x: 0, y: 0)

    let
      cursorLineText = buffer.getLine(cursor.line)
      (wrapLineIndex, wrapLineColumn) =
        cursorWrapPosition(cursorLineText, cursor.column, maxWidth, e.tabStop)

    screenY += wrapLineIndex

    # Guard the lower bound too: with topWrapOffset > 0 a cursor on a segment
    # above the visible top would compute a negative screenY.
    if screenY >= 0 and screenY < viewport.height - reservedLines:
      let finalX = viewport.x + gutterWidth + wrapLineColumn
      let finalY = viewport.y + screenY
      return CursorPosition(x: finalX, y: finalY)
  else:
    # NO-WRAP MODE: Calculate cursor position with horizontal scrolling.
    # Count only the visible rows between topLine and the cursor so collapsed
    # folds above the cursor don't push it below the rendered content. Each
    # collapsed fold is a single marker row; skip its hidden interior in one
    # step so a large fold above the cursor costs O(1), not O(lines).
    var
      screenRow = 0
      l = viewport.topLine
    while l < cursor.line:
      if l < 0 or l >= buffer.len:
        inc l
        continue
      let fold = buffer.foldState.getCollapsedFoldAt(l)
      if fold.isSome:
        # Count the marker row only at the fold's start line; jump past the rest.
        if l == fold.get.startLine:
          screenRow.inc
        l = fold.get.endLine + 1
      else:
        screenRow.inc
        inc l

    if screenRow < viewport.height - reservedLines:
      let
        cursorLineText = buffer.getLine(cursor.line)
        displayWidthUpToCursor =
          displayWidthUpToWithTabs(cursorLineText, cursor.column, e.tabStop)
        displayWidthUpToLeftCol =
          displayWidthUpToWithTabs(cursorLineText, viewport.leftColumn, e.tabStop)
        screenY = viewport.y + screenRow
        screenX =
          viewport.x + gutterWidth +
          max(0, displayWidthUpToCursor - displayWidthUpToLeftCol)

      return CursorPosition(x: screenX, y: screenY)

  return CursorPosition(x: 0, y: 0)
