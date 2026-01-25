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

import
  editor_types, editor_window, editor_render_helpers, render_utils, unicode_utils,
  sidebar

proc renderLineNumbers*(
    e: Editor,
    buffer: var Buffer,
    textAreaWidth: int,
    sidebarWidth: int = 0,
    startY: int = 0,
): int =
  ## Render line numbers and return max width of the line number text.
  ## startY: Y offset for rendering (e.g., TabLineHeight when tab line is shown)

  # Guard against invalid text area width
  if textAreaWidth <= 0:
    return 0

  let
    lineLen = e.textBuffer.len
    maxLineNumWidth = len($lineLen) + LineNumberSpacer
    reservedLines = e.calculateReservedLines(isBottomWindow = true)
    lineNumX = buffer.area.x + sidebarWidth
  var
    screenY = startY
    lineIndex = e.viewport.topLine

  while screenY < buffer.area.height - reservedLines and lineIndex < lineLen:
    # Render line numbers with wrapping support
    let
      line = e.textBuffer.getLine(lineIndex)
      isCurrentLine = lineIndex == e.state.cursor.line
      # Apply currentNumber setting: highlight current line number only if enabled
      lineStyle =
        if isCurrentLine and e.state.display.showCurrentLineNumber:
          currentLineStyle()
        else:
          lineNumStyle()

    if e.state.display.lineWrap:
      let
        lineCharLen = line.charLen # Use character count, not byte count
        numWraps = calculateWrapCount(lineCharLen, textAreaWidth)
        lineNumStr = formatLineNumber(lineIndex, maxLineNumWidth)

      buffer.setString(lineNumX, buffer.area.y + screenY, lineNumStr, lineStyle)
      inc screenY

      for _ in 1 ..< numWraps:
        # Render empty space for wrapped parts (no line number)
        if screenY >= buffer.area.height - reservedLines:
          break
        let emptyLineNumStr = spaces(maxLineNumWidth)
        buffer.setString(
          lineNumX, buffer.area.y + screenY, emptyLineNumStr, lineNumStyle()
        )
        inc screenY
    else:
      # Normal single-line display
      let lineNumStr = formatLineNumber(lineIndex, maxLineNumWidth)
      buffer.setString(lineNumX, buffer.area.y + screenY, lineNumStr, lineStyle)
      inc screenY

    inc lineIndex

  while screenY < buffer.area.height - reservedLines:
    # Clear remaining line number area to prevent artifacts
    let emptyLineNumStr = spaces(maxLineNumWidth)
    buffer.setString(lineNumX, buffer.area.y + screenY, emptyLineNumStr, lineNumStyle())
    inc screenY

  return maxLineNumWidth

proc renderTextBuffer*(e: Editor, buffer: var Buffer, area: Rect) =
  # Get visual selection range if active
  let (hasSelection, selStart, selEnd) = e.getVisualSelection()

  # Create render context
  let ctx = RenderContext(
    cursorLine: e.state.cursor.line,
    cursorCol: e.state.cursor.column,
    hasSelection: hasSelection,
    selStart: selStart,
    selEnd: selEnd,
  )

  var
    screenY = 0
    lineIndex = e.viewport.topLine

  while screenY < area.height and lineIndex < e.textBuffer.len:
    # Render file content with optional line wrapping
    let line = e.textBuffer.getLine(lineIndex)

    if e.state.display.lineWrap:
      # Line wrapping enabled - split long lines across multiple screen lines
      let
        maxWidth = area.width
        lineCharLen = line.charLen # Use character count, not byte count

      if lineCharLen == 0:
        # Empty line - fill with cursor line highlight if on cursor line
        e.fillCursorLineBackground(
          buffer, area.x, area.y + screenY, lineIndex, e.state.cursor.line
        )
        # Render CodeLens on empty lines
        e.renderCodeLensInline(buffer, area.x, area.y + screenY, lineIndex, 0)
        inc screenY
        inc lineIndex
        continue

      var startCharCol = 0 # Character position, not byte position
      var isFirstWrappedLine = true
        # Track if this is the first screen line for this logical line
      while startCharCol < lineCharLen and screenY < area.height:
        # Calculate how many characters fit in maxWidth display columns
        # This properly handles wide characters (CJK, etc.)
        let (charCount, _) = displayWidthSubstr(line, startCharCol, maxWidth)
        let
          endCharCol = startCharCol + charCount
          # Convert character positions to byte positions for slicing
          startBytePos = charToBytePos(line, startCharCol)
          endBytePos = charToBytePos(line, endCharCol)
          displayLine = line[startBytePos ..< endBytePos]

        if displayLine.len > 0:
          # Render with selection highlighting if in visual mode
          e.renderLineSegmentWithSelection(
            e.textBuffer,
            buffer,
            displayLine,
            area.x,
            area.y + screenY,
            lineIndex,
            startCharCol,
            ctx,
            useRunes = true,
          )

          # Render CodeLens only on the first wrapped line
          if isFirstWrappedLine:
            let lineDisplayWidth =
              displayWidthWithTabs(displayLine, e.state.display.tabStop)
            e.renderCodeLensInline(
              buffer, area.x, area.y + screenY, lineIndex, lineDisplayWidth
            )
            isFirstWrappedLine = false

        inc screenY
        startCharCol += charCount # Use actual character count, not maxWidth
    else:
      # No line wrapping - use horizontal scrolling
      # Use character-based slicing (not byte-based) for multibyte character support
      let displayLine =
        if e.viewport.leftColumn < line.charLen:
          line.runeSubStr(e.viewport.leftColumn)
        else:
          ""

      if displayLine.len > 0:
        # Render with selection highlighting if in visual mode
        e.renderLineSegmentWithSelection(
          e.textBuffer,
          buffer,
          displayLine,
          area.x,
          area.y + screenY,
          lineIndex,
          e.viewport.leftColumn,
          ctx,
          useRunes = false,
        )

        # Render CodeLens inline after line content
        let lineDisplayWidth =
          displayWidthWithTabs(displayLine, e.state.display.tabStop)
        e.renderCodeLensInline(
          buffer, area.x, area.y + screenY, lineIndex, lineDisplayWidth
        )
      else:
        # Empty line or scrolled past line end - fill with cursor line highlight if on cursor line
        e.fillCursorLineBackground(
          buffer, area.x, area.y + screenY, lineIndex, e.state.cursor.line
        )

        # Render CodeLens even on empty lines
        e.renderCodeLensInline(buffer, area.x, area.y + screenY, lineIndex, 0)

      inc screenY

    inc lineIndex

proc renderWindowLineWrapped*(
    e: Editor,
    buffer: var Buffer,
    window: EditorWindow,
    lineNumOffset: int,
    ctx: RenderContext,
    screenY: var int,
    lineIndex: var int,
    visibleHeight: int,
) =
  ## Render a single line with wrapping enabled
  let
    line = window.buffer.getLine(lineIndex)
    actualScreenY = window.viewport.y + screenY
    sidebarWidth = e.calculateSidebarWidth()
    maxWidth = window.viewport.width - sidebarWidth - lineNumOffset
    lineCharLen = line.charLen
    isCurrentLine = (lineIndex == window.cursor.line)
    # Apply currentNumber setting: highlight current line number only if enabled
    lineStyle =
      if isCurrentLine and e.config.standard.currentNumber:
        currentLineStyle()
      else:
        lineNumStyle()
    lineNumScreenX = window.viewport.x + sidebarWidth

  if lineCharLen == 0:
    # Empty line - just render line number (if enabled)
    if lineNumOffset > 0:
      let lineNumStr = formatLineNumber(lineIndex, lineNumOffset)
      if lineNumScreenX + lineNumStr.len <= buffer.area.width:
        buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineStyle)
    # Fill with cursor line highlight if on cursor line
    let textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    e.fillCursorLineBackground(
      buffer, textScreenX, actualScreenY, lineIndex, window.cursor.line
    )
    inc screenY
    inc lineIndex
    return

  var
    startCharCol = 0
    wrapLineCount = 0

  while startCharCol < lineCharLen and screenY < visibleHeight:
    let
      endCharCol = min(startCharCol + maxWidth, lineCharLen)
      startBytePos = charToBytePos(line, startCharCol)
      endBytePos = charToBytePos(line, endCharCol)
      displayLine = line[startBytePos ..< endBytePos]
      textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
      currentActualScreenY = window.viewport.y + screenY

    # Render line number for first wrap, empty space for others (if enabled)
    if lineNumOffset > 0:
      if wrapLineCount == 0:
        let lineNumStr = formatLineNumber(lineIndex, lineNumOffset)
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
    startCharCol += maxWidth

    if screenY >= visibleHeight:
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
    sidebarWidth = e.calculateSidebarWidth()
    isCurrentLine = (lineIndex == window.cursor.line)
    # Apply currentNumber setting: highlight current line number only if enabled
    lineStyle =
      if isCurrentLine and e.config.standard.currentNumber:
        currentLineStyle()
      else:
        lineNumStyle()
    lineNumScreenX = window.viewport.x + sidebarWidth

  # Render line number (if enabled)
  if lineNumOffset > 0:
    let lineNumStr = formatLineNumber(lineIndex, lineNumOffset)
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
    let maxWidth = min(displayLine.len, window.viewport.width - lineNumOffset)
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
    # Empty line or scrolled past line end - fill with cursor line highlight if on cursor line
    e.fillCursorLineBackground(
      buffer, textScreenX, actualScreenY, lineIndex, window.cursor.line
    )

proc renderWindowSidebar*(
    buffer: var Buffer,
    window: EditorWindow,
    sidebar: Sidebar,
    screenY: int,
    sidebarOffset: int,
) =
  ## Render a single line of the sidebar
  let actualScreenY = window.viewport.y + screenY

  if screenY >= 0 and screenY < sidebar.buffer.len:
    for x in 0 ..< sidebar.width:
      let
        item = sidebar.buffer[screenY][x]
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
    sidebarWidth = e.calculateSidebarWidth()
    lineNumScreenX = window.viewport.x + sidebarWidth
    textScreenX = window.viewport.x + sidebarWidth + lineNumOffset
    foldText = window.buffer.formatFoldText(fold)

  # Render line number (if enabled)
  if lineNumOffset > 0:
    let lineNumStr = formatLineNumber(fold.startLine, lineNumOffset)
    if lineNumScreenX + lineNumStr.len <= buffer.area.width:
      buffer.setString(lineNumScreenX, actualScreenY, lineNumStr, lineNumStyle())

  # Render fold text
  if textScreenX < buffer.area.width:
    let maxWidth = buffer.area.width - textScreenX
    let displayText =
      if foldText.len > maxWidth:
        foldText[0 ..< maxWidth]
      else:
        foldText
    buffer.setString(textScreenX, actualScreenY, displayText, foldStyle())

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
  let maybeSidebar =
    if e.state.display.showSidebar:
      some(
        generateSidebarFromBuffer(window.buffer, window.viewport.topLine, visibleHeight)
      )
    else:
      none(Sidebar)

  # Get visual selection range if active
  let (hasSelection, selStart, selEnd) = e.getVisualSelection(window.active)

  # Create render context for this window
  let ctx = RenderContext(
    cursorLine: window.cursor.line,
    cursorCol: window.cursor.column,
    hasSelection: hasSelection,
    selStart: selStart,
    selEnd: selEnd,
  )

  var
    screenY = tabLineOffset
    lineIndex = window.viewport.topLine

  while screenY < visibleHeight + tabLineOffset and lineIndex < lineCount:
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
        renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, 0)
      e.renderFoldLine(buffer, window, lineNumOffset, screenY, foldOpt.get)
      # Skip to the line after the fold
      lineIndex = foldOpt.get.endLine + 1
      inc screenY
      continue

    # Normal line rendering
    # Render sidebar if enabled
    if maybeSidebar.isSome:
      renderWindowSidebar(buffer, window, maybeSidebar.get, screenY, 0)

    if e.state.display.lineWrap:
      e.renderWindowLineWrapped(
        buffer, window, lineNumOffset, ctx, screenY, lineIndex, visibleHeight
      )
    else:
      e.renderWindowLineNoWrap(buffer, window, lineNumOffset, ctx, screenY, lineIndex)
      inc screenY
      inc lineIndex

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
