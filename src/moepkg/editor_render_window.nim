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

import std/[options, strutils, unicode, tables]

import pkg/celina

import
  editor_types, editor_window_layout, editor_render_helpers, render_utils, sidebar,
  color, unicode_utils, search_utils, highlight, modes, colorcode, git_conflict
import command_handlers/visual_handler

proc hasSyntaxHighlight(
    e: Editor, buffer: TextBuffer, windowMode: EditorMode
): bool {.inline.} =
  e.state.display.showSyntax and not buffer.highlight.isNil and
    (windowMode.isFileEditMode or buffer.language != langNone or buffer.isUtilityBuffer)

proc baseStyleWithOverlay(
    e: Editor,
    buffer: TextBuffer,
    pos: BufferPosition,
    cursorLine: int,
    windowMode: EditorMode,
    displayCol: int,
    cursorDisplayCol: int,
    lineConflict: ConflictMarkerKind,
): Style =
  ## Compute base style (syntax highlight + document highlight / cursor line/column overlay).
  ## Extracted to avoid 4x duplication in getSelectionStyle.
  ## `lineConflict` is pre-computed once per line by the caller.
  let conflictKind = lineConflict
  let useTwoColor = e.config.highlight.gitConflictTwoColor

  if e.hasSyntaxHighlight(buffer, windowMode):
    let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
    var style = colorIndexToStyle(colorPair)
    style.modifiers =
      style.modifiers + buffer.highlight.getSegmentModifiers(pos.line, pos.column)
    let highlightKind = e.isPositionInDocumentHighlight(pos)
    if highlightKind.isSome:
      style.bg = getDocumentHighlightStyle(highlightKind.get).bg
    elif conflictKind != cmkNone:
      style.bg = conflictStyleFor(conflictKind, useTwoColor).bg
    elif colorPair != EditorColorPairIndex.searchResult:
      if e.state.display.showCursorLine and pos.line == cursorLine:
        style.bg = cursorLineHighlightStyle().bg
      elif e.state.display.showCursorColumn and displayCol >= 0 and
          displayCol == cursorDisplayCol:
        style.bg = cursorColumnHighlightStyle().bg
    style
  else:
    let highlightKind = e.isPositionInDocumentHighlight(pos)
    if highlightKind.isSome:
      getDocumentHighlightStyle(highlightKind.get)
    elif conflictKind != cmkNone:
      conflictStyleFor(conflictKind, useTwoColor)
    elif e.state.display.showCursorLine and pos.line == cursorLine:
      cursorLineHighlightStyle()
    elif e.state.display.showCursorColumn and displayCol >= 0 and
        displayCol == cursorDisplayCol:
      cursorColumnHighlightStyle()
    else:
      normalStyle()

proc getSelectionStyle*(
    e: Editor,
    buffer: TextBuffer,
    hasSelection: bool,
    pos: BufferPosition,
    cursorLine: int,
    cursorCol: int,
    windowMode: EditorMode,
    displayCol: int = -1,
    cursorDisplayCol: int = -1,
    searchMatchRanges: seq[ColumnRange] = @[],
    wordMatchRanges: seq[ColumnRange] = @[],
    lineConflict: ConflictMarkerKind = cmkNone,
): Style =
  ## Get the appropriate style for a character based on selection state and syntax.
  ## searchMatchRanges/wordMatchRanges: pre-computed per-line ranges for O(1) lookup.

  # Check if this position is the matching paren
  let isMatchingParen =
    e.state.matchingParenPos.isSome and e.state.matchingParenPos.get.line == pos.line and
    e.state.matchingParenPos.get.column == pos.column

  # Check current-word highlight using pre-computed ranges
  let isInCurrentWord =
    not e.state.isSearchOverlay and wordMatchRanges.isColumnInRanges(pos.column)

  let isInFindCharMatch =
    e.config.highlight.findCharHighlight and e.state.ui.findCharMatches.len > 0 and
    pos.line == e.state.ui.findCharMatchLine and pos.column in e.state.ui.findCharMatches

  if hasSelection and e.state.visualSelection.isPositionInSelection(pos):
    # Keep original foreground color (syntax highlight), override only background
    var style =
      if e.hasSyntaxHighlight(buffer, windowMode):
        let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
        var s = colorIndexToStyle(colorPair)
        s.modifiers =
          s.modifiers + buffer.highlight.getSegmentModifiers(pos.line, pos.column)
        s
      else:
        normalStyle()
    style.bg = visualStyle().bg
    style
  elif isMatchingParen:
    parenPairStyle()
  elif isInFindCharMatch:
    findCharMatchStyle()
  elif isInCurrentWord:
    currentWordStyle()
  elif searchMatchRanges.isColumnInRanges(pos.column):
    searchHighlightStyle()
  else:
    e.baseStyleWithOverlay(
      buffer, pos, cursorLine, windowMode, displayCol, cursorDisplayCol, lineConflict
    )

proc getVisualSelection*(
    e: Editor, windowMode: EditorMode, windowActive: bool = true
): tuple[hasSelection: bool, selStart, selEnd: BufferPosition] =
  ## Get visual selection range if active
  ## windowMode: The mode of the window being rendered
  ## windowActive: only show selection in active window (default true for compatibility)
  let hasSelection =
    isVisualAllMode(windowMode) and e.state.visualSelection.active and windowActive

  if hasSelection:
    let (start, endPos) = e.state.visualSelection.getSelectionRange()
    result = (hasSelection: true, selStart: start, selEnd: endPos)
  else:
    result = (
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
    )

proc shouldShowIndentationGuide*(
    e: Editor, indentInfo: IndentInfo, displayX: int, charIdx: int
): bool =
  ## Check if an indentation guide should be shown at this position
  ## Uses cached indentInfo to avoid O(n²) performance
  ## displayX: the display column position (accounting for tabs)
  ## charIdx: the character index in the line
  if not e.state.display.showIndentationLines:
    return false

  # Don't show indentation guides in utility buffers (jumplist, log, etc.)
  if e.activeBuffer().isUtilityBuffer:
    return false

  # Only show guides at indent levels (multiples of tabStop)
  if displayX mod e.state.display.tabStop != 0:
    return false

  # Don't show on column 0
  if displayX == 0:
    return false

  # Check if this position is within leading whitespace
  if charIdx < 0:
    return false

  # Use cached indentation info: O(1) instead of O(n)
  # Show guide only if we're within leading whitespace and line has content
  return indentInfo.hasContent and charIdx <= indentInfo.leadingWhitespaceEnd

proc fillLineBackground*(
    e: Editor,
    buffer: var Buffer,
    screenX, screenY: int,
    lineIndex, cursorLine: int,
    windowRightEdge: int,
    cursorDisplayCol: int = -1,
    textBuffer: TextBuffer = nil,
    isEmptyLine: bool = false,
    hasSelection: bool = false,
) =
  ## Fill the rest of the line to the window right edge.
  ## Uses cursor line highlight for the cursor line, normal style otherwise.
  ## When `textBuffer` is provided and the line is inside a git conflict block,
  ## the conflict background takes priority over cursor-line highlight.
  ## When `isEmptyLine` and `hasSelection` are both true and the visual
  ## selection covers (lineIndex, 0), column 0 is rendered with the visual
  ## selection background so that Visual mode is visible on empty lines.
  let lineConflict =
    if textBuffer != nil and e.config.highlight.gitConflict:
      textBuffer.lineConflictKind(lineIndex)
    else:
      cmkNone
  let useTwoColor = e.config.highlight.gitConflictTwoColor
  let selectionAtStart =
    isEmptyLine and hasSelection and
    e.state.visualSelection.isPositionInSelection(
      BufferPosition(line: lineIndex, column: 0)
    )
  var displayX = 0
  while screenX + displayX < windowRightEdge:
    let fillStyle =
      if displayX == 0 and selectionAtStart:
        visualStyle()
      elif lineConflict != cmkNone:
        conflictStyleFor(lineConflict, useTwoColor)
      elif e.state.display.showCursorLine and lineIndex == cursorLine:
        cursorLineHighlightStyle()
      elif e.state.display.showCursorColumn and cursorDisplayCol >= 0 and
        displayX == cursorDisplayCol:
        cursorColumnHighlightStyle()
      else:
        normalStyle()
    buffer.setCell(screenX + displayX, screenY, " ", 1, fillStyle)
    displayX += 1

proc renderLineSegmentWithSelection*(
    e: Editor,
    textBuffer: TextBuffer,
    buffer: var Buffer,
    displayLine: string,
    screenX, screenY: int,
    lineIndex: int,
    startColumn: int,
    ctx: RenderContext,
    useRunes: bool = true,
) =
  ## Render a line segment with selection highlighting and syntax highlighting
  ## useRunes: true for wrapped mode (character-based), false for byte-based rendering
  ## ctx: RenderContext containing cursor position and selection information

  # Update syntax highlighting once per line (not per character)
  if e.hasSyntaxHighlight(textBuffer, ctx.windowMode):
    textBuffer.updateHighlight()

  # Get the full line for indentation guide checking
  let fullLine = textBuffer.getLine(lineIndex)
  # Analyze indentation once (O(n)) to avoid repeated scanning (O(n²))
  let indentInfo = analyzeIndentation(fullLine)
  # Find where trailing spaces start (for highlighting)
  let trailingSpaceStart = findTrailingSpaceStart(fullLine)

  # Scan for inline color codes if enabled
  let colorCodeMatches =
    if e.config.highlight.colorCodeHighlight and ctx.windowMode.isFileEditMode:
      scanLineForColorCodes(fullLine)
    else:
      @[]

  # Pre-compute search match ranges for this line (O(n) once instead of O(n) per char)
  let searchMatchRanges =
    if e.state.search.hlsearch and not e.state.search.hlsearchTempDisabled:
      let searchPattern =
        if e.state.isSearchOverlay:
          if e.state.search.text.len > 0: e.state.search.text else: ""
        elif e.state.isCommandOverlay:
          let subPattern = extractSubstitutePattern(e.state.commandText)
          if subPattern.len > 0: subPattern else: e.state.search.lastText
        else:
          e.state.search.lastText
      if searchPattern.len > 0:
        let shouldIgnoreCase = shouldIgnoreCase(
          searchPattern, e.state.search.ignorecase, e.state.search.smartcase
        )
        textBuffer.findSearchMatchRanges(
          lineIndex, searchPattern, shouldIgnoreCase, e.state.search.wholeWord
        )
      else:
        @[]
    else:
      @[]

  # Pre-compute word match ranges for this line (O(n) once instead of O(n) per char)
  let wordMatchRanges =
    if not e.state.isSearchOverlay and e.state.currentWord.len > 0:
      let excludeCol = if lineIndex == ctx.cursorLine: ctx.cursorCol else: -1
      textBuffer.findWordMatchRanges(lineIndex, e.state.currentWord, excludeCol)
    else:
      @[]

  # Pre-compute conflict kind once per line (avoids O(K) scan per character)
  let lineConflict =
    if e.config.highlight.gitConflict:
      textBuffer.lineConflictKind(lineIndex)
    else:
      cmkNone

  # Always render character by character to apply syntax highlighting
  var displayX = 0

  # Template to render a single character (eliminates code duplication)
  # Using template instead of proc to avoid closure capture issues
  template renderChar(rune: Rune, col: int, style: Style) =
    # Handle tab character specially
    if rune == TAB_CHAR:
      # Calculate how many spaces until next tab stop
      let spacesToNextTab =
        e.state.display.tabStop - (displayX mod e.state.display.tabStop)
      # Determine style for tab (trailing space highlighting takes priority)
      let tabStyle =
        if e.config.highlight.trailingSpaces and col >= trailingSpaceStart and
            ctx.windowMode.isFileEditMode and lineIndex != ctx.cursorLine:
          trailingSpacesStyle()
        else:
          style
      # Render spaces instead of tab character
      for i in 0 ..< spacesToNextTab:
        if screenX + displayX < ctx.windowRightEdge:
          # Check if we should show indentation guide at this position
          if e.shouldShowIndentationGuide(indentInfo, displayX, col):
            buffer.setCell(
              screenX + displayX, screenY, "│", 1, indentationLineStyle()
            )
          else:
            buffer.setCell(screenX + displayX, screenY, " ", 1, tabStyle)
        displayX += 1
    else:
      # Normal character
      var renderStyle = style
      let width = runeWidth(rune)

      # Check if this is a space and should show indentation guide
      if rune == ' '.Rune and e.shouldShowIndentationGuide(indentInfo, displayX, col):
        if screenX + displayX < ctx.windowRightEdge:
          buffer.setCell(screenX + displayX, screenY, "│", 1, indentationLineStyle())
        displayX += 1
      else:
        # Highlight full-width space if enabled (only in file edit modes)
        if rune == FULLWIDTH_SPACE and e.config.highlight.fullWidthSpace and
            ctx.windowMode.isFileEditMode:
          renderStyle = fullWidthSpaceStyle()

        # Highlight trailing spaces if enabled (only in file edit modes)
        if e.config.highlight.trailingSpaces and col >= trailingSpaceStart and
            ctx.windowMode.isFileEditMode and lineIndex != ctx.cursorLine:
          if rune == ' '.Rune or rune == TAB_CHAR or rune == FULLWIDTH_SPACE:
            renderStyle = trailingSpacesStyle()

        # Highlight inline color codes if enabled
        for ccm in colorCodeMatches:
          if col >= ccm.startCol and col <= ccm.endCol:
            renderStyle = ccm.style
            break

        if screenX + displayX < ctx.windowRightEdge:
          buffer.setCell(screenX + displayX, screenY, rune, width, renderStyle)
        displayX += width

  if useRunes:
    # Character-based rendering (for wrapped mode)
    var charIdx = startColumn
    for rune in displayLine.runes:
      let
        pos = BufferPosition(line: lineIndex, column: charIdx)
        style = e.getSelectionStyle(
          textBuffer,
          ctx.hasSelection,
          pos,
          ctx.cursorLine,
          ctx.cursorCol,
          ctx.windowMode,
          displayCol = displayX,
          cursorDisplayCol = ctx.cursorDisplayCol,
          searchMatchRanges = searchMatchRanges,
          wordMatchRanges = wordMatchRanges,
          lineConflict = lineConflict,
        )
      renderChar(rune, charIdx, style)
      charIdx += 1
  else:
    # Byte-based rendering (for non-wrapped mode)
    var charIdx = 0
    for rune in displayLine.runes:
      let
        col = startColumn + charIdx
        pos = BufferPosition(line: lineIndex, column: col)
        style = e.getSelectionStyle(
          textBuffer,
          ctx.hasSelection,
          pos,
          ctx.cursorLine,
          ctx.cursorCol,
          ctx.windowMode,
          displayCol = displayX,
          cursorDisplayCol = ctx.cursorDisplayCol,
          searchMatchRanges = searchMatchRanges,
          wordMatchRanges = wordMatchRanges,
          lineConflict = lineConflict,
        )
      renderChar(rune, col, style)
      charIdx += 1

  # Fill the rest of the line to the window right edge.
  # Always fill to clear stale content (e.g. old cursor line highlight).
  let useTwoColor = e.config.highlight.gitConflictTwoColor
  while screenX + displayX < ctx.windowRightEdge:
    let fillStyle =
      if lineConflict != cmkNone:
        conflictStyleFor(lineConflict, useTwoColor)
      elif e.state.display.showCursorLine and lineIndex == ctx.cursorLine:
        cursorLineHighlightStyle()
      elif e.state.display.showCursorColumn and ctx.cursorDisplayCol >= 0 and
        displayX == ctx.cursorDisplayCol:
        cursorColumnHighlightStyle()
      else:
        normalStyle()
    buffer.setCell(screenX + displayX, screenY, " ", 1, fillStyle)
    displayX += 1

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
