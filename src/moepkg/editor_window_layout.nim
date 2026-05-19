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

import editor_types, render_utils, sidebar

proc calculateReservedLines*(e: Editor, isBottomWindow: bool = true): int =
  ## Calculate number of reserved lines based on status line configuration
  ## and multi-line status messages
  result =
    if e.state.display.showStatusLine:
      if e.state.display.multiStatusLine:
        if isBottomWindow: StatusAndCommandReserve else: StatusLineReserve
      elif isBottomWindow:
        StatusAndCommandReserve
      else:
        0
    else:
      if isBottomWindow: CommandLineReserve else: 0

  # Add extra lines for multi-line status messages (only for bottom window)
  if isBottomWindow:
    result += e.state.statusMessageExtraLines()

proc calculateTerminalAreaDimensions*(
    e: Editor, window: EditorWindow
): tuple[cols, rows: int] =
  ## Compute the correct PTY cols/rows for a terminal in the given window,
  ## matching the formula used by renderTerminal.
  let
    maxBottomY = findMaxBottomY(e.windowManager.windows)
    windowBottomY = window.viewport.y + window.viewport.height
    isBottomWindow = (windowBottomY == maxBottomY)
    tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0
    reservedBottom =
      if isBottomWindow and e.state.display.showStatusLine:
        StatusAndCommandReserve
      elif isBottomWindow:
        CommandLineReserve
      else:
        0
  result = (
    cols: window.viewport.width,
    rows: max(1, window.viewport.height - reservedBottom - tabLineOffset),
  )

proc calculateWindowCursor*(
    e: Editor,
    buffer: TextBuffer,
    viewport: ViewPort,
    cursor: BufferPosition,
    lineNumOffset: int,
    reservedLines: int,
    scrollbarWidth: int = 0,
): CursorPosition =
  ## Calculate screen cursor position for a window
  ## Returns the absolute screen coordinates

  # Validate cursor is within buffer bounds
  if cursor.line < 0 or cursor.line >= buffer.len:
    return CursorPosition(x: 0, y: 0)

  # Cursor is above visible area
  if cursor.line < viewport.topLine:
    return CursorPosition(x: 0, y: 0)

  if e.state.display.lineWrap:
    # WRAP MODE: Calculate cursor position considering line wrapping
    let maxWidth = max(1, viewport.width - lineNumOffset - scrollbarWidth)

    var screenY = 0
    let maxVisibleLine = min(cursor.line, viewport.topLine + viewport.height)

    for lineIdx in viewport.topLine ..< maxVisibleLine:
      if lineIdx >= 0 and lineIdx < buffer.len:
        let line = buffer.getLine(lineIdx)

        let wrappedLines = calculateWrapCount(line, maxWidth, e.state.display.tabStop)
        screenY += wrappedLines

        if screenY >= viewport.height - reservedLines:
          return CursorPosition(x: 0, y: 0)

    let
      cursorLineText = buffer.getLine(cursor.line)
      (wrapLineIndex, wrapLineColumn) = cursorWrapPosition(
        cursorLineText, cursor.column, maxWidth, e.state.display.tabStop
      )

    screenY += wrapLineIndex

    if screenY < viewport.height - reservedLines:
      let finalX = viewport.x + lineNumOffset + wrapLineColumn
      let finalY = viewport.y + screenY
      return CursorPosition(x: finalX, y: finalY)
  else:
    # NO-WRAP MODE: Calculate cursor position with horizontal scrolling
    if cursor.line < viewport.topLine + viewport.height - reservedLines:
      let
        cursorLineText = buffer.getLine(cursor.line)
        displayWidthUpToCursor = displayWidthUpToWithTabs(
          cursorLineText, cursor.column, e.state.display.tabStop
        )
        displayWidthUpToLeftCol = displayWidthUpToWithTabs(
          cursorLineText, viewport.leftColumn, e.state.display.tabStop
        )
        screenY = viewport.y + (cursor.line - viewport.topLine)
        screenX =
          viewport.x + lineNumOffset +
          max(0, displayWidthUpToCursor - displayWidthUpToLeftCol)

      return CursorPosition(x: screenX, y: screenY)

  return CursorPosition(x: 0, y: 0)

proc calculateSidebarWidth*(e: Editor, mode: EditorMode): int =
  ## Calculate the width occupied by the sidebar (0 if disabled)
  if mode.isFileEditMode and e.state.display.showSidebar: DefaultSidebarWidth else: 0

proc calculateScrollbarWidth*(e: Editor, mode: EditorMode): int =
  ## Calculate the width occupied by the scrollbar (0 if disabled or non-edit mode)
  ## Only shown in file editing modes (same as sidebar).
  if mode.isFileEditMode and e.state.display.scrollbar and
      e.state.display.scrollbarWidth > 0: e.state.display.scrollbarWidth else: 0
