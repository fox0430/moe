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

## Window and line rendering procedures

import std/[options, strutils, unicode]

import pkg/celina

import editor_types, editor_window, editor_render_helpers, render_utils, sidebar

proc fmtLineNum(e: Editor, lineIndex: int, cursorLine: int, width: int): string =
  if e.state.display.relativeLineNumbers:
    formatRelativeLineNumber(lineIndex, cursorLine, width)
  else:
    formatLineNumber(lineIndex, width)

proc renderWindowLineWrapped*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    ctx: RenderContext,
    screenY: var int,
    lineIndex: var int,
    visibleHeight: int,
    tabLineOffset: int,
) =
  ## Render a single line with wrapping enabled
  let
    maxScreenY = visibleHeight + tabLineOffset
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth(window.mode)
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
    maxWidth = window.viewport.width - sidebarWidth - scrollbarWidth - lineNumOffset
    lineCharLen = line.charLen
    isCurrentLine = (lineIndex == window.cursor.line)
    # Apply currentNumber setting: highlight current line number only if enabled
    lineStyle =
      if isCurrentLine:
        currentLineStyle()
      else:
        lineNumStyle()
    lineNumScreenX = window.viewport.x + sidebarWidth

  if lineCharLen == 0:
    # Don't render if already past visible area
    if screenY >= maxScreenY:
      return
    # Empty line - just render line number (if enabled)
    if lineNumOffset > 0:
      let lineNumStr = e.fmtLineNum(lineIndex, window.cursor.line, lineNumOffset)
      if lineNumScreenX + lineNumStr.len <= buffer.area.width:
        buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)
    # Fill with cursor line/column highlight if on cursor line/column
    let textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    e.fillLineBackground(
      buffer,
      textScreenX,
      actualScreenY,
      lineIndex,
      window.cursor.line,
      window.viewport.x + window.viewport.width,
      cursorDisplayCol = ctx.cursorDisplayCol,
      textBuffer = window.buffer,
      isEmptyLine = true,
      hasSelection = ctx.hasSelection,
    )
    inc screenY
    inc lineIndex
    return

  var
    startCharCol = 0
    startByteCol = 0
    wrapLineCount = 0

  # Don't render if already past visible area
  if screenY >= maxScreenY:
    return

  let tabStop = e.state.display.tabStop

  while startCharCol < lineCharLen and screenY < maxScreenY:
    # Use byte-position-aware function to avoid O(n) skip per segment
    let
      (charCount, _, endBytePos) =
        displayWidthSubstrFromByte(line, startByteCol, maxWidth, tabStop)
      endCharCol = min(startCharCol + max(1, charCount), lineCharLen)
      actualEndByte = if endCharCol >= lineCharLen: line.len else: endBytePos
      displayLine = line[startByteCol ..< actualEndByte]
      textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
      currentActualScreenY = window.viewport.y + screenY

    # Render line number for first wrap, empty space for others (if enabled)
    if lineNumOffset > 0:
      if wrapLineCount == 0:
        let lineNumStr = e.fmtLineNum(lineIndex, window.cursor.line, lineNumOffset)
        if lineNumScreenX + lineNumStr.len <= buffer.area.width:
          buffer.setString(lineNumScreenX, currentActualScreenY, lineNumStr, lineStyle)
      else:
        if lineNumScreenX + lineNumOffset <= buffer.area.width:
          let emptyLineNumStr = spaces(lineNumOffset)
          buffer.setString(
            lineNumScreenX, currentActualScreenY, emptyLineNumStr, lineNumStyle()
          )

    if displayLine.len > 0 and textScreenX < buffer.area.width:
      let displayCharCount = endCharCol - startCharCol
      if displayCharCount > 0:
        # Render with selection highlighting if in visual mode
        e.renderLineSegmentWithSelection(
          window.buffer,
          buffer,
          displayLine,
          textScreenX,
          currentActualScreenY,
          lineIndex,
          startCharCol,
          ctx,
          useRunes = true,
        )

    inc screenY
    inc wrapLineCount
    startCharCol = endCharCol
    startByteCol = actualEndByte

    if screenY >= maxScreenY:
      break

  inc lineIndex

proc renderWindowLineNoWrap*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    ctx: RenderContext,
    screenY: int,
    lineIndex: int,
) =
  ## Render a single line without wrapping (horizontal scrolling)
  let
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth(window.mode)
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
    isCurrentLine = (lineIndex == window.cursor.line)
    # Apply currentNumber setting: highlight current line number only if enabled
    lineStyle =
      if isCurrentLine:
        currentLineStyle()
      else:
        lineNumStyle()
    lineNumScreenX = window.viewport.x + sidebarWidth

  # Render line number (if enabled)
  if lineNumOffset > 0:
    let lineNumStr = e.fmtLineNum(lineIndex, window.cursor.line, lineNumOffset)
    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)

  # Render text content
  # Use character-based slicing (not byte-based) for multibyte character support
  let
    displayLine =
      if window.viewport.leftColumn < line.charLen:
        line.runeSubStr(window.viewport.leftColumn)
      else:
        ""
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset

  if displayLine.len > 0 and textScreenX < buffer.area.width:
    let maxWidth = min(
      displayLine.len,
      window.viewport.width - sidebarWidth - scrollbarWidth - lineNumOffset,
    )
    if maxWidth > 0:
      # Render with selection highlighting if in visual mode
      e.renderLineSegmentWithSelection(
        window.buffer,
        buffer,
        displayLine[0 ..< maxWidth],
        textScreenX,
        actualScreenY,
        lineIndex,
        window.viewport.leftColumn,
        ctx,
        useRunes = false,
      )
  else:
    # Empty line or scrolled past line end - fill to clear stale content
    e.fillLineBackground(
      buffer,
      textScreenX,
      actualScreenY,
      lineIndex,
      window.cursor.line,
      window.viewport.x + window.viewport.width,
      cursorDisplayCol = ctx.cursorDisplayCol,
      textBuffer = window.buffer,
      isEmptyLine = (line.charLen == 0),
      hasSelection = ctx.hasSelection,
    )

proc renderWindowSidebar*(
    buffer: var Buffer,
    window: EditorWindow,
    sidebar: Sidebar,
    screenY: int,
    sidebarIndex: int,
    sidebarOffset: int,
) =
  ## Render a single line of the sidebar
  ## screenY: screen row offset from window.viewport.y
  ## sidebarIndex: index into sidebar.buffer (0-based, independent of tabLineOffset)
  let actualScreenY = window.viewport.y + screenY

  if sidebarIndex >= 0 and sidebarIndex < sidebar.buffer.len:
    for x in 0 ..< sidebar.width:
      let
        item = sidebar.buffer[sidebarIndex][x]
        screenX = window.viewport.x + sidebarOffset + x
      if screenX < buffer.area.width and actualScreenY < buffer.area.height:
        buffer.setString(screenX, actualScreenY, item.text, item.style)

proc renderFoldLine*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    screenY: int,
    fold: Fold,
) =
  ## Render a collapsed fold marker line (vim-style)
  let
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth(window.mode)
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
    lineNumScreenX = window.viewport.x + sidebarWidth
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    foldText = window.buffer.formatFoldText(fold)
    windowRightEdge = window.viewport.x + window.viewport.width - scrollbarWidth

  # Render line number (if enabled)
  if lineNumOffset > 0:
    let lineNumStr = e.fmtLineNum(fold.startLine, window.cursor.line, lineNumOffset)
    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineNumStyle())

  # Render fold text
  if textScreenX < buffer.area.width:
    let maxWidth = windowRightEdge - textScreenX
    let displayText =
      if foldText.len > maxWidth:
        foldText[0 ..< maxWidth]
      else:
        foldText
    buffer.setString(textScreenX, actualScreenY, displayText, foldStyle())

proc renderScrollbar*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    visibleHeight: int,
    tabLineOffset: int,
) =
  ## Render a scrollbar on the right edge of the window.
  ## The scrollbar shows the current viewport position within the buffer.
  let
    totalLines = window.buffer.len
    scrollbarWidth = e.calculateScrollbarWidth(window.mode)
    scrollbarStartX = window.viewport.x + window.viewport.width - scrollbarWidth

  if totalLines <= visibleHeight or visibleHeight <= 0 or scrollbarWidth <= 0:
    return

  # Calculate thumb size and position
  let
    thumbSize = max(1, (visibleHeight * visibleHeight) div totalLines)
    maxTopLine = totalLines - visibleHeight
    thumbPos =
      if maxTopLine > 0:
        (window.viewport.topLine * (visibleHeight - thumbSize)) div maxTopLine
      else:
        0

  for y in 0 ..< visibleHeight:
    let
      screenY = window.viewport.y + tabLineOffset + y
      isThumb = y >= thumbPos and y < thumbPos + thumbSize
      style =
        if isThumb:
          scrollbarThumbStyle()
        else:
          scrollbarTrackStyle()

    for col in 0 ..< scrollbarWidth:
      let screenX = scrollbarStartX + col
      if screenX < buffer.area.width and screenY < buffer.area.height:
        buffer.setCell(screenX, screenY, " ", 1, style)

proc renderWindow*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    isBottomWindow: bool,
    isActiveWindow: bool,
    tabLineOffset: int = 0,
) =
  ## Render a single window with sidebar, line numbers and text content
  ## tabLineOffset: Y offset for rendering (TabLineHeight when tab line is shown)
  let
    lineCount = window.buffer.len
    reservedLines = e.calculateReservedLines(isBottomWindow)
    visibleHeight = window.viewport.height - reservedLines - tabLineOffset

  # Generate sidebar dynamically from buffer markers if enabled
  # Note: sidebar needs visibleHeight rows (screenY goes from tabLineOffset to visibleHeight + tabLineOffset)
  let maybeSidebar =
    if e.state.display.showSidebar:
      some(
        generateSidebarFromBuffer(
          window.buffer,
          window.viewport.topLine,
          visibleHeight,
          modifiedLines = window.buffer.modifiedLines,
          showModifiedLines = e.state.display.showModifiedLines,
          bookmarks = window.buffer.bookmarks,
        )
      )
    else:
      none(Sidebar)

  # Get visual selection range if active
  let (hasSelection, selStart, selEnd) =
    e.getVisualSelection(window.mode, window.active)

  # Compute cursor's display column (accounting for tabs/wide chars and scroll offset)
  let leftCol = if e.state.display.lineWrap: 0 else: window.viewport.leftColumn
  let cursorDisplayCol =
    if window.cursor.line < lineCount:
      let cursorLineText = window.buffer.getLine(window.cursor.line)
      bufferColToDisplayCol(
        cursorLineText, window.cursor.column, e.state.display.tabStop, leftCol
      )
    else:
      window.cursor.column

  # Create render context for this window
  let ctx = RenderContext(
    cursorLine: window.cursor.line,
    cursorCol: window.cursor.column,
    cursorDisplayCol: cursorDisplayCol,
    hasSelection: hasSelection,
    selStart: selStart,
    selEnd: selEnd,
    windowMode: window.mode,
    windowRightEdge: window.viewport.x + window.viewport.width,
  )

  var
    screenY = tabLineOffset
    lineIndex = window.viewport.topLine

  while screenY < visibleHeight + tabLineOffset and lineIndex < lineCount:
    # sidebarIndex is 0-based index into sidebar buffer (based on logical line, not screen row)
    let sidebarIndex = lineIndex - window.viewport.topLine

    # Check if this line is inside a collapsed fold (but not the start line)
    if window.buffer.foldState.isLineInCollapsedFold(lineIndex):
      # Skip this line (it's hidden inside a fold)
      inc lineIndex
      continue

    # Check if this line is the start of a collapsed fold
    let foldOpt = window.buffer.foldState.getCollapsedFoldAt(lineIndex)
    if foldOpt.isSome and foldOpt.get.startLine == lineIndex:
      # Render the fold marker
      if maybeSidebar.isSome:
        renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, sidebarIndex, 0)
      e.renderFoldLine(buffer, window, lineNumOffset, screenY, foldOpt.get)
      # Skip to the line after the fold
      lineIndex = foldOpt.get.endLine + 1
      inc screenY
      continue

    # Normal line rendering
    # Render sidebar if enabled
    if maybeSidebar.isSome:
      renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, sidebarIndex, 0)

    if e.state.display.lineWrap:
      e.renderWindowLineWrapped(
        buffer, window, lineNumOffset, ctx, screenY, lineIndex, visibleHeight,
        tabLineOffset,
      )
    else:
      e.renderWindowLineNoWrap(buffer, window, lineNumOffset, ctx, screenY, lineIndex)
      inc screenY
      inc lineIndex

  # Render scrollbar on the right edge if enabled (file editing modes only)
  if e.calculateScrollbarWidth(window.mode) > 0:
    e.renderScrollbar(buffer, window, visibleHeight, tabLineOffset)

proc renderWindowSeparator*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    nextWindow: EditorWindow,
    isBottomWindow: bool,
) =
  ## Draw separator between adjacent windows (vertical or horizontal)
  # Check if windows are side by side (vertical split) or top/bottom (horizontal split)
  if window.viewport.y == nextWindow.viewport.y:
    # Vertical split - draw vertical separator at window boundary
    let sepX = window.viewport.x + window.viewport.width
    if sepX < buffer.area.width:
      # Calculate separator height using helper
      let
        sepHeight = e.calculateReservedLines(isBottomWindow)
        actualSepHeight = window.viewport.height - sepHeight

      # Draw separator for the content height of this window
      for y in window.viewport.y ..< (window.viewport.y + actualSepHeight):
        if y < buffer.area.height:
          buffer.setString(sepX, y, "│", separatorStyle())
  elif not e.state.display.multiStatusLine:
    # Horizontal split - draw horizontal separator at window boundary
    # ONLY when using a single status line
    let sepY = window.viewport.y + window.viewport.height
    if sepY < buffer.area.height:
      # Draw separator for the width of this window
      for x in window.viewport.x ..< (window.viewport.x + window.viewport.width):
        if x < buffer.area.width:
          buffer.setString(x, sepY, "─", separatorStyle())
