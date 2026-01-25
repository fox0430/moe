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

# This file is included by editor.nim - do not import directly
# Contains all rendering-related procedures for the editor

type
  IndentInfo = object
    ## Cached indentation analysis for a line to avoid O(n²) performance
    leadingWhitespaceEnd: int
      # Character index where leading whitespace ends (-1 if no content)
    hasContent: bool # Whether the line contains non-whitespace content

  RenderContext* = object
    ## Context for rendering operations to reduce parameter passing
    cursorLine*: int
    cursorCol*: int
    hasSelection*: bool
    selStart*: BufferPosition
    selEnd*: BufferPosition

proc colorIndexToStyle(colorIdx: EditorColorPairIndex): Style =
  ## Convert EditorColorPairIndex to Celina Style using theme colors
  getThemeStyle(colorIdx)

proc analyzeIndentation(lineText: string): IndentInfo =
  ## Analyze a line once to determine indentation properties
  ## Returns cached information to avoid repeated line scanning (O(n) instead of O(n²))
  result.leadingWhitespaceEnd = -1
  result.hasContent = false

  var charIdx = 0
  for rune in lineText.runes:
    if rune != ' '.Rune and rune != TAB_CHAR:
      # Found first non-whitespace character
      result.leadingWhitespaceEnd = charIdx - 1
      result.hasContent = true
      break
    charIdx += 1

proc shouldShowIndentationGuide(
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

proc isPositionInDocumentHighlight(e: Editor, pos: BufferPosition): Option[int] =
  ## Check if position is within any document highlight range
  ## Returns the highlight kind (1=Text, 2=Read, 3=Write) if found, none otherwise
  ## Uses O(1) line lookup + O(m) column search where m is highlights on that line
  if not e.state.display.showDocumentHighlight or
      not e.state.lspCache.documentHighlightCache.isValid:
    return none(int)

  # O(1) lookup by line
  let items =
    e.state.lspCache.documentHighlightCache.itemsByLine.getOrDefault(pos.line, @[])
  for item in items:
    if pos.column >= item.startColumn and pos.column < item.endColumn:
      return some(item.kind)

  return none(int)

proc getDocumentHighlightStyle(kind: int): Style =
  ## Get the style for a document highlight based on its kind
  case kind
  of 2: # Read
    documentHighlightReadStyle()
  of 3: # Write
    documentHighlightWriteStyle()
  else: # Text or unknown
    documentHighlightTextStyle()

proc getSelectionStyle(
    e: Editor,
    buffer: TextBuffer,
    hasSelection: bool,
    pos: BufferPosition,
    cursorLine: int,
    cursorCol: int,
): Style =
  ## Get the appropriate style for a character based on selection state and syntax
  # Check if this is the cursor position
  let isCursorPos = (pos.line == cursorLine and pos.column == cursorCol)

  # Check if this position is the matching paren (highlight matching paren)
  let isMatchingParen =
    e.state.matchingParenPos.isSome and e.state.matchingParenPos.get.line == pos.line and
    e.state.matchingParenPos.get.column == pos.column

  # Check if this position is part of the current word (highlight all occurrences)
  # Skip the word under cursor itself - only highlight other occurrences
  # Also skip in Search mode to avoid interfering with search highlighting
  let isInSameWordAsCursor =
    pos.line == cursorLine and e.state.currentWord.len > 0 and
    buffer.isPositionInWord(pos, e.state.currentWord)

  let isInCurrentWord =
    e.state.mode != EditorMode.Search and e.state.currentWord.len > 0 and
    not isInSameWordAsCursor and buffer.isPositionInWord(pos, e.state.currentWord)

  if hasSelection and e.state.visualSelection.isPositionInSelection(pos):
    visualStyle()
  elif isMatchingParen:
    # Highlight matching paren with special style
    parenPairStyle()
  elif isCursorPos:
    # Cursor position: always use gray foreground color
    cursorCharStyle()
  elif isInCurrentWord:
    # Highlight other occurrences of the current word
    # (disabled in Search mode to avoid interfering with search highlighting)
    currentWordStyle()
  elif e.state.search.hlsearch and not e.state.search.hlsearchTempDisabled:
    # Determine which search pattern to use:
    # - In Search mode with text: use current searchText (incremental highlight)
    # - In Search mode without text: no highlight (user is starting a new search)
    # - In Command mode with substitute command: use substitute pattern (incremental highlight)
    # - Not in Search mode: use lastSearchText (persistent highlight from previous search)
    let searchPattern =
      if e.state.mode == EditorMode.Search:
        # In Search mode: only highlight if user has typed something
        if e.state.search.text.len > 0:
          e.state.search.text
        else:
          "" # No highlight when starting a new search
      elif e.state.mode == EditorMode.Command:
        # In Command mode: check for substitute command pattern
        let subPattern = extractSubstitutePattern(e.state.commandText)
        if subPattern.len > 0: subPattern else: e.state.search.lastText
      else:
        # Not in Search mode: use last search pattern
        e.state.search.lastText

    # Only apply highlight if we have a valid search pattern
    if searchPattern.len > 0:
      # Apply smartcase logic
      let shouldIgnoreCase = shouldIgnoreCase(
        searchPattern, e.state.search.ignorecase, e.state.search.smartcase
      )

      if buffer.isPositionInSearchMatch(
        pos, searchPattern, shouldIgnoreCase, e.state.search.wholeWord
      ):
        searchHighlightStyle()
      elif e.state.display.showSyntax and not buffer.highlight.isNil:
        # Apply syntax highlighting from buffer
        # Update highlight if needed (after text edits)
        buffer.updateHighlight()
        let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
        var style = colorIndexToStyle(colorPair)
        # Apply document highlight or cursor line highlighting
        let highlightKind = e.isPositionInDocumentHighlight(pos)
        if highlightKind.isSome:
          style.bg = getDocumentHighlightStyle(highlightKind.get).bg
        elif e.state.display.showCursorLine and pos.line == cursorLine:
          style.bg = cursorLineHighlightStyle().bg
        style
      else:
        # Check document highlight first
        let highlightKind = e.isPositionInDocumentHighlight(pos)
        if highlightKind.isSome:
          getDocumentHighlightStyle(highlightKind.get)
        elif e.state.display.showCursorLine and pos.line == cursorLine:
          cursorLineHighlightStyle()
        else:
          normalStyle()
    elif e.state.display.showSyntax and not buffer.highlight.isNil:
      # Apply syntax highlighting from buffer
      # Update highlight if needed (after text edits)
      buffer.updateHighlight()
      let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
      var style = colorIndexToStyle(colorPair)
      # Apply document highlight or cursor line highlighting
      let highlightKind = e.isPositionInDocumentHighlight(pos)
      if highlightKind.isSome:
        style.bg = getDocumentHighlightStyle(highlightKind.get).bg
      elif e.state.display.showCursorLine and pos.line == cursorLine:
        style.bg = cursorLineHighlightStyle().bg
      style
    else:
      # Check document highlight first
      let highlightKind = e.isPositionInDocumentHighlight(pos)
      if highlightKind.isSome:
        getDocumentHighlightStyle(highlightKind.get)
      elif e.state.display.showCursorLine and pos.line == cursorLine:
        cursorLineHighlightStyle()
      else:
        normalStyle()
  elif e.state.display.showSyntax and not buffer.highlight.isNil:
    # Apply syntax highlighting from buffer
    # Update highlight if needed (after text edits)
    buffer.updateHighlight()
    let colorPair = buffer.highlight.getColorPair(pos.line, pos.column)
    var style = colorIndexToStyle(colorPair)
    # Apply document highlight or cursor line highlighting
    let highlightKind = e.isPositionInDocumentHighlight(pos)
    if highlightKind.isSome:
      style.bg = getDocumentHighlightStyle(highlightKind.get).bg
    elif e.state.display.showCursorLine and pos.line == cursorLine:
      style.bg = cursorLineHighlightStyle().bg
    style
  else:
    # Check document highlight first
    let highlightKind = e.isPositionInDocumentHighlight(pos)
    if highlightKind.isSome:
      getDocumentHighlightStyle(highlightKind.get)
    elif e.state.display.showCursorLine and pos.line == cursorLine:
      cursorLineHighlightStyle()
    else:
      normalStyle()

proc isVisualMode(mode: EditorMode): bool {.inline.} =
  ## Check if the mode is any visual mode variant
  mode in {EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine}

proc getVisualSelection(
    e: Editor, windowActive: bool = true
): tuple[hasSelection: bool, selStart, selEnd: BufferPosition] =
  ## Get visual selection range if active
  ## windowActive: only show selection in active window (default true for compatibility)
  let hasSelection =
    isVisualMode(e.state.mode) and e.state.visualSelection.active and windowActive

  if hasSelection:
    let (start, endPos) = e.state.visualSelection.getSelectionRange()
    result = (hasSelection: true, selStart: start, selEnd: endPos)
  else:
    result = (
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
    )

proc renderLineSegmentWithSelection(
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

  # Get the full line for indentation guide checking
  let fullLine = textBuffer.getLine(lineIndex)
  # Analyze indentation once (O(n)) to avoid repeated scanning (O(n²))
  let indentInfo = analyzeIndentation(fullLine)
  # Find where trailing spaces start (for highlighting)
  let trailingSpaceStart = findTrailingSpaceStart(fullLine)

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
        if e.config.highlight.trailingSpaces and col >= trailingSpaceStart:
          trailingSpacesStyle()
        else:
          style
      # Render spaces instead of tab character
      for i in 0 ..< spacesToNextTab:
        if screenX + displayX < buffer.area.width:
          # Check if we should show indentation guide at this position
          if e.shouldShowIndentationGuide(indentInfo, displayX, col):
            buffer.setString(screenX + displayX, screenY, "│", indentationLineStyle())
          else:
            buffer.setString(screenX + displayX, screenY, " ", tabStyle)
        displayX += 1
    else:
      # Normal character
      var charStr = $rune
      var renderStyle = style

      # Check if this is a space and should show indentation guide
      if rune == ' '.Rune and e.shouldShowIndentationGuide(indentInfo, displayX, col):
        charStr = "│"
        renderStyle = indentationLineStyle()

      # Highlight full-width space if enabled
      if rune == FULLWIDTH_SPACE and e.config.highlight.fullWidthSpace:
        renderStyle = fullWidthSpaceStyle()

      # Highlight trailing spaces if enabled
      if e.config.highlight.trailingSpaces and col >= trailingSpaceStart:
        if rune == ' '.Rune or rune == TAB_CHAR or rune == FULLWIDTH_SPACE:
          renderStyle = trailingSpacesStyle()

      if screenX + displayX < buffer.area.width:
        buffer.setString(screenX + displayX, screenY, charStr, renderStyle)
      # Account for character width (wide characters like CJK are width 2)
      displayX += runeWidth(rune)

  if useRunes:
    # Character-based rendering (for wrapped mode)
    var charIdx = startColumn
    for rune in displayLine.runes:
      let
        pos = BufferPosition(line: lineIndex, column: charIdx)
        style = e.getSelectionStyle(
          textBuffer, ctx.hasSelection, pos, ctx.cursorLine, ctx.cursorCol
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
          textBuffer, ctx.hasSelection, pos, ctx.cursorLine, ctx.cursorCol
        )
      renderChar(rune, col, style)
      charIdx += 1

  # Fill the rest of the line with cursor line highlight if on cursor line
  if e.state.display.showCursorLine and lineIndex == ctx.cursorLine:
    while screenX + displayX < buffer.area.width:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle())
      displayX += 1

proc fillCursorLineBackground(
    e: Editor, buffer: var Buffer, screenX, screenY: int, lineIndex, cursorLine: int
) =
  ## Fill the rest of the line with cursor line background if on cursor line
  if e.state.display.showCursorLine and lineIndex == cursorLine:
    var displayX = 0
    while screenX + displayX < buffer.area.width:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle())
      displayX += 1

proc renderCodeLensInline(
    e: Editor,
    buffer: var Buffer,
    screenX, screenY: int,
    lineIndex: int,
    lineDisplayWidth: int,
) =
  ## Render CodeLens text inline at the end of a line
  ## Shows CodeLens items after the line content with dimmed style
  if not e.state.display.showCodeLens or not e.state.lspCache.codeLensCache.isValid:
    return

  # Get CodeLens items for this line from cache (O(1) lookup)
  let items = e.state.lspCache.codeLensCache.itemsByLine.getOrDefault(lineIndex, @[])
  if items.len == 0:
    return

  var texts: seq[string] = @[]
  for item in items:
    if item.title.len > 0:
      texts.add(item.title)

  if texts.len == 0:
    return

  let codeLensText = texts.join(" | ")

  # Calculate position: after line content with some padding
  let padding = 2
  var displayX = lineDisplayWidth + padding

  # Add separator before CodeLens text
  let separator = "  "
  let displayText = separator & codeLensText

  # Render the CodeLens text
  for ch in displayText:
    if screenX + displayX >= buffer.area.width:
      break
    buffer.setString(screenX + displayX, screenY, $ch, codeLensStyle())
    displayX += 1

proc renderCodeLensPicker*(e: Editor, buffer: var Buffer) =
  ## Render CodeLens picker popup when multiple items are available
  if not e.state.lspCache.codeLensPicker.isActive or
      e.state.lspCache.codeLensPicker.items.len == 0:
    return

  let
    items = e.state.lspCache.codeLensPicker.items
    selectedIdx = e.state.lspCache.codeLensPicker.selectedIndex
    scrollOffset = e.state.lspCache.codeLensPicker.scrollOffset
    maxVisibleItems = e.state.lspCache.codeLensPicker.maxVisibleItems

  # Calculate how many items to actually show
  let visibleCount = min(maxVisibleItems, items.len - scrollOffset)

  # Check if scroll indicators are needed
  let hasMoreAbove = scrollOffset > 0
  let hasMoreBelow = scrollOffset + visibleCount < items.len

  # Calculate popup dimensions using display width for multi-byte characters
  var maxDisplayWidth = 0
  for item in items:
    let w = displayWidth(item.title)
    if w > maxDisplayWidth:
      maxDisplayWidth = w
  # Add padding (2 chars each side) + number prefix (3 chars: "N. ") and limit to screen width
  let contentWidth = min(maxDisplayWidth + 2 + 3, buffer.area.width - 6)
  let popupWidth = contentWidth + 2 # +2 for border

  let popupHeight = visibleCount + 2 # +2 for border

  # Position popup near cursor
  var
    popupX = e.state.screenCursor.x
    popupY = e.state.screenCursor.y + 1

  # Adjust if popup goes off screen
  if popupX + popupWidth > buffer.area.width:
    popupX = max(0, buffer.area.width - popupWidth)
  if popupY + popupHeight > buffer.area.height - 2:
    popupY = max(0, e.state.screenCursor.y - popupHeight)

  # Define styles
  let
    borderStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.BrightBlack),
      bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 30, g: 30, b: 30)),
      modifiers: {},
    )
    popupNormalStyle = Style(
      fg: ColorValue(kind: Default),
      bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 30, g: 30, b: 30)),
      modifiers: {},
    )
    selectedStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.Black),
      bg: ColorValue(kind: Indexed, indexed: Color.Cyan),
      modifiers: {},
    )
    scrollIndicatorStyle = Style(
      fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
      bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 30, g: 30, b: 30)),
      modifiers: {},
    )

  # Draw top border with scroll indicator if needed
  if popupY >= 0 and popupY < buffer.area.height:
    buffer.setString(popupX, popupY, "┌", borderStyle)
    for x in 1 ..< popupWidth - 1:
      if popupX + x < buffer.area.width:
        buffer.setString(popupX + x, popupY, "─", borderStyle)
    # Show scroll up indicator in top-right corner
    if hasMoreAbove and popupX + popupWidth - 2 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 2, popupY, "▲", scrollIndicatorStyle)
    if popupX + popupWidth - 1 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 1, popupY, "┐", borderStyle)

  # Draw visible items (based on scroll offset)
  for displayIdx in 0 ..< visibleCount:
    let itemIdx = scrollOffset + displayIdx
    if itemIdx >= items.len:
      break

    let item = items[itemIdx]
    let y = popupY + 1 + displayIdx
    if y >= buffer.area.height - 1:
      break

    let style = if itemIdx == selectedIdx: selectedStyle else: popupNormalStyle

    # Left border
    buffer.setString(popupX, y, "│", borderStyle)

    # Fill background first
    for x in 1 ..< popupWidth - 1:
      if popupX + x < buffer.area.width:
        buffer.setString(popupX + x, y, " ", style)

    # Draw number prefix for items 1-9
    var textX = popupX + 2
    if itemIdx < 9:
      let numStr = $(itemIdx + 1) & "."
      let numStyle = Style(
        fg: ColorValue(kind: Indexed, indexed: Color.Yellow),
        bg: style.bg,
        modifiers: {},
      )
      buffer.setString(textX, y, numStr, numStyle)
      textX += 2
      buffer.setString(textX, y, " ", style)
      textX += 1

    # Draw item text with proper multi-byte character handling
    let maxTextX = popupX + popupWidth - 2
    var currentWidth = 0
    # Adjust maxContentWidth for number prefix (3 chars: "N. ")
    let prefixWidth = if itemIdx < 9: 3 else: 0
    let maxContentWidth = contentWidth - 2 - prefixWidth
      # Leave space for padding and prefix

    for rune in item.title.runes:
      let runeW = runeWidth(rune)
      # Check if we need to truncate (leave space for ellipsis)
      if currentWidth + runeW > maxContentWidth - 1 and
          currentWidth + runeW < displayWidth(item.title):
        # Add ellipsis and stop
        if textX < maxTextX and textX < buffer.area.width:
          buffer.setString(textX, y, "…", style)
        break

      if textX + runeW <= maxTextX and textX < buffer.area.width:
        buffer.setString(textX, y, $rune, style)
        textX += runeW
        currentWidth += runeW
      else:
        break

    # Right border
    if popupX + popupWidth - 1 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 1, y, "│", borderStyle)

  # Draw bottom border with scroll indicator if needed
  let bottomY = popupY + visibleCount + 1
  if bottomY < buffer.area.height:
    buffer.setString(popupX, bottomY, "└", borderStyle)
    for x in 1 ..< popupWidth - 1:
      if popupX + x < buffer.area.width:
        buffer.setString(popupX + x, bottomY, "─", borderStyle)
    # Show scroll down indicator in bottom-right corner
    if hasMoreBelow and popupX + popupWidth - 2 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 2, bottomY, "▼", scrollIndicatorStyle)
    if popupX + popupWidth - 1 < buffer.area.width:
      buffer.setString(popupX + popupWidth - 1, bottomY, "┘", borderStyle)

proc renderLineNumbers(
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

proc renderTextBuffer(e: Editor, buffer: var Buffer, area: Rect) =
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

proc renderWindowLineWrapped(
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

proc renderWindowLineNoWrap(
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

proc renderWindowSidebar(
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

proc renderFoldLine(
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

proc renderWindow(
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

proc renderWindowSeparator(
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

proc updateViewportSize(e: Editor, buffer: Buffer): bool =
  ## Update viewport size from buffer area and return true if resized
  let
    oldWidth = e.viewport.width
    oldHeight = e.viewport.height

  e.viewport.width = buffer.area.width
  e.viewport.height = buffer.area.height

  (oldWidth != e.viewport.width) or (oldHeight != e.viewport.height)

proc renderSplitView(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render split window view
  let
    oldWidth = e.viewport.width
    oldHeight = e.viewport.height

  # If terminal was resized, rebuild window layout
  if wasResized and oldWidth > 0 and oldHeight > 0 and e.viewport.width > 0 and
      e.viewport.height > 0:
    # Save current state to window before resize
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      e.windowManager.windows[e.windowManager.activeWindowIndex].cursor = e.state.cursor

    e.windowManager.resizeWindows(
      e.viewport.width, e.viewport.height, oldWidth, oldHeight,
      e.state.display.multiStatusLine,
    )

    # After resize, restore viewport scroll position from window to motion controller
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
      e.executer.motionController.viewportManager.viewport.topLine =
        activeWindow.viewport.topLine
      e.executer.motionController.viewportManager.viewport.leftColumn =
        activeWindow.viewport.leftColumn
  else:
    # Normal case: sync active window's cursor with state cursor
    if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      # Update window cursor from editor state
      e.windowManager.windows[e.windowManager.activeWindowIndex].cursor = e.state.cursor

  # Find the maximum bottom Y coordinate (to determine bottom windows)
  let maxBottomY = findMaxBottomY(e.windowManager.windows)

  # Calculate tab line offset (1 if tab line is shown, 0 otherwise)
  let tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0

  # Render all split windows
  for i, window in e.windowManager.windows:
    # Calculate line number offset dynamically based on buffer size
    let lineNumOffset =
      calculateLineNumOffset(window.buffer, e.state.display.showLineNumbers)

    # Determine if this is a bottom window (needs status line reservation)
    # A window is a bottom window if its bottom edge is at the maximum bottom Y
    let
      windowBottomY = window.viewport.y + window.viewport.height
      isBottomWindow = (windowBottomY == maxBottomY)
      isActiveWindow = (i == e.windowManager.activeWindowIndex)

    # Render tab line for this window if enabled
    if e.state.display.showTabLine:
      let buffersToShow =
        if e.buffers.len > 0:
          e.buffers
        else:
          @[e.textBuffer]
      renderWindowTabLine(
        buffersToShow, window.buffer, buffer, window.viewport.y, window.viewport.x,
        window.viewport.width, e.state.display.showTabLine,
      )

    # Render window (LogViewer uses normal buffer rendering now)
    e.renderWindow(
      buffer, window, lineNumOffset, isBottomWindow, isActiveWindow, tabLineOffset
    )

    # Render per-window status line if multi-status line mode is enabled
    # (and merge is disabled - merge shows only one status line at bottom)
    if e.state.display.showStatusLine and e.state.display.multiStatusLine and
        not e.config.statusLine.merge:
      let statusLineY = calculateWindowStatusLineY(window, isBottomWindow)
      e.state.renderWindowStatusLine(
        window.buffer, buffer, statusLineY, window.viewport.x, window.viewport.width,
        isActiveWindow, e.config.statusLine,
      )

    # Draw separator between windows (except for last window)
    if i < e.windowManager.windows.len - 1:
      let nextWindow = e.windowManager.windows[i + 1]
      e.renderWindowSeparator(buffer, window, nextWindow, isBottomWindow)

  # Set cursor to active window position
  if e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    let activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
    e.setActiveWindowScreenCursor(activeWindow)

proc renderSingleViewSidebar(
    buffer: var Buffer, sidebar: Sidebar, sidebarLineIndex: int, screenY: int
) =
  ## Render a single line of the sidebar for single view mode
  ## sidebarLineIndex: index into sidebar.buffer (logical line based)
  ## screenY: actual screen Y coordinate for rendering
  if sidebarLineIndex >= 0 and sidebarLineIndex < sidebar.buffer.len:
    for x in 0 ..< sidebar.width:
      let item = sidebar.buffer[sidebarLineIndex][x]
      if x < buffer.area.width and screenY < buffer.area.height:
        buffer.setString(x, screenY, item.text, item.style)

proc renderSingleView(e: Editor, buffer: var Buffer, wasResized: bool) =
  ## Render single buffer view (no split windows)
  # Sync viewport with motion controller (both directions)
  e.executer.motionController.viewportManager.viewport.width = e.viewport.width
  e.executer.motionController.viewportManager.viewport.height = e.viewport.height
  e.viewport = e.executer.motionController.viewportManager.viewport

  # Calculate tab line offset (1 if tab line is shown, 0 otherwise)
  let tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0

  let
    reservedLines = e.calculateReservedLines(isBottomWindow = true)
    sidebarWidth = e.calculateSidebarWidth()
    lineNumOffset =
      calculateLineNumOffset(e.textBuffer, e.state.display.showLineNumbers)
    textAreaWidth =
      max(0, buffer.area.width - sidebarWidth - lineNumOffset - LineNumberPadding)
    textArea = Rect(
      x: buffer.area.x + sidebarWidth + lineNumOffset,
      y: buffer.area.y + tabLineOffset,
      width: max(0, buffer.area.width - sidebarWidth - lineNumOffset),
      height: max(0, buffer.area.height - reservedLines - tabLineOffset),
    )

  # Calculate visible height accounting for tab line
  let visibleHeight = max(1, buffer.area.height - reservedLines - tabLineOffset)

  # Generate sidebar dynamically from buffer markers if enabled
  let maybeSidebar =
    if e.state.display.showSidebar:
      some(generateSidebarFromBuffer(e.textBuffer, e.viewport.topLine, visibleHeight))
    else:
      none(Sidebar)

  # If terminal was resized, adjust viewport to keep cursor visible
  if wasResized:
    # If cursor is now below the visible area, adjust topLine
    if e.state.cursor.line >= e.viewport.topLine + visibleHeight:
      let newTopLine = max(0, e.state.cursor.line - visibleHeight + 1)
      e.viewport.topLine = newTopLine
      e.executer.motionController.viewportManager.viewport.topLine = newTopLine
    # If cursor is above the visible area
    elif e.state.cursor.line < e.viewport.topLine:
      e.viewport.topLine = e.state.cursor.line
      e.executer.motionController.viewportManager.viewport.topLine = e.state.cursor.line

  # Render sidebar if enabled (with line wrap support)
  if maybeSidebar.isSome:
    let sidebar = maybeSidebar.get
    var screenY = tabLineOffset
    var lineIndex = e.viewport.topLine
    while screenY < buffer.area.height - reservedLines and lineIndex < e.textBuffer.len:
      let sidebarLineIndex = lineIndex - e.viewport.topLine

      if e.state.display.lineWrap:
        let
          line = e.textBuffer.getLine(lineIndex)
          lineCharLen = line.charLen
          numWraps = calculateWrapCount(lineCharLen, textAreaWidth)

        # Render sidebar marker for first screen line of this logical line
        renderSingleViewSidebar(buffer, sidebar, sidebarLineIndex, screenY)
        inc screenY

        # For wrapped continuation lines, render empty sidebar
        for _ in 1 ..< numWraps:
          if screenY >= buffer.area.height - reservedLines:
            break
          inc screenY
      else:
        renderSingleViewSidebar(buffer, sidebar, sidebarLineIndex, screenY)
        inc screenY

      inc lineIndex

  # Render line numbers only if enabled
  if e.state.display.showLineNumbers:
    discard e.renderLineNumbers(buffer, textAreaWidth, sidebarWidth, tabLineOffset)
  e.renderTextBuffer(buffer, textArea)

  # Calculate and set cursor position (including sidebar width)
  var cursorPos = e.calculateWindowCursor(
    e.textBuffer,
    e.viewport,
    e.state.cursor,
    sidebarWidth + lineNumOffset,
    reservedLines + tabLineOffset,
  )
  # Adjust cursor Y for tab line offset
  cursorPos.y += tabLineOffset
  e.state.screenCursor = cursorPos

proc renderBottomLines(e: Editor, buffer: var Buffer) =
  ## Render status line and command line at the bottom of the screen
  let
    statusLineY = buffer.area.y + buffer.area.height - 2
    commandLineY = buffer.area.y + buffer.area.height - 1

  # Render status line using active buffer
  # - Single window mode: always render status line at bottom
  # - Multi-window mode: only render if multiStatusLine is disabled OR merge is enabled
  if e.windowManager.windows.len == 0 or not e.state.display.multiStatusLine or
      e.config.statusLine.merge:
    e.state.renderStatusLine(e.activeBuffer(), buffer, statusLineY, e.config.statusLine)

  # Handle command line
  if e.state.mode == EditorMode.Command:
    buffer.setString(buffer.area.x, commandLineY, e.state.commandText, commandStyle())
    # Cursor position: ":" + commandCursor (0-based after ":")
    e.state.screenCursor.x = 1 + e.state.commandCursor
    e.state.screenCursor.y = buffer.area.height - 1

    # Render command completion popup if active
    if e.state.commandCompletionManager.isActive():
      let popupPos = calculateCommandPopupPosition(
        e.state.commandCursor, buffer.area.width, buffer.area.height,
        e.state.commandCompletionManager.menu.entries,
        e.state.commandCompletionManager.menu.maxVisible,
        e.state.commandCompletionManager.argStartX,
      )
      renderCommandCompletionPopup(
        buffer, e.state.commandCompletionManager.menu, popupPos
      )
  elif e.state.mode == EditorMode.Search:
    let searchChar = if e.state.search.direction == Forward: "/" else: "?"
    let searchPrompt = searchChar & e.state.search.text
    buffer.setString(buffer.area.x, commandLineY, searchPrompt, commandStyle())
    e.state.screenCursor.x = searchPrompt.len
    e.state.screenCursor.y = buffer.area.height - 1
  else:
    let lineCount = e.state.statusMessageLineCount()
    if lineCount == 1:
      # Single line: render as before
      buffer.setString(
        buffer.area.x, commandLineY, e.state.statusMessage, commandStyle()
      )
    elif lineCount > 1:
      # Multi-line: move status line up, expand command line area
      let
        allLines = e.state.statusMessage.split('\n')
        # Limit to MaxStatusMessageLines, show last N lines if exceeded
        lines =
          if allLines.len > MaxStatusMessageLines:
            allLines[allLines.len - MaxStatusMessageLines .. ^1]
          else:
            allLines
        extraLines = lines.len - 1
        newStatusLineY = max(0, statusLineY - extraLines)
        messageStartY = newStatusLineY + 1

      # Re-render status line at new position
      e.state.renderStatusLine(
        e.activeBuffer(), buffer, newStatusLineY, e.config.statusLine
      )

      # Render message lines from messageStartY to commandLineY
      for i, line in lines:
        let y = messageStartY + i
        if y >= messageStartY and y <= commandLineY:
          buffer.setString(
            buffer.area.x, y, " ".repeat(buffer.area.width), commandStyle()
          )
          buffer.setString(buffer.area.x, y, line, commandStyle())

proc renderTempMessages(e: Editor, buffer: var Buffer) =
  ## Render temporary messages at the bottom of screen (like Vim's :jumps output)
  ## Overwrites the buffer content from bottom up, with a border at top
  if e.state.tempMessages.len == 0:
    return

  let
    # +2 for border line and "Press ENTER..." prompt
    totalLines = e.state.tempMessages.len + 2
    startY = max(0, buffer.area.height - totalLines)
    borderLine = " ".repeat(buffer.area.width)
    # White background style for border
    whiteBorderStyle = Style(
      fg: ColorValue(kind: Default),
      bg: ColorValue(kind: Indexed, indexed: Color.White),
      modifiers: {},
    )
    theNormalStyle = normalStyle()

  # Clear the area where messages will be displayed
  for y in startY ..< buffer.area.height:
    buffer.setString(buffer.area.x, y, " ".repeat(buffer.area.width), theNormalStyle)

  # Render border line at top (white background)
  buffer.setString(buffer.area.x, startY, borderLine, whiteBorderStyle)

  # Render each message line
  for i, msg in e.state.tempMessages:
    let y = startY + 1 + i # +1 to skip border
    if y < buffer.area.height - 1: # Leave last line for prompt
      buffer.setString(buffer.area.x, y, msg, theNormalStyle)

  # Render the prompt on the last line
  let promptY = buffer.area.height - 1
  buffer.setString(
    buffer.area.x, promptY, "Press ENTER or type command to continue", commandStyle()
  )

  # Position cursor at the end of the prompt
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = promptY

proc pathToIcon(entry: FileEntry): string =
  ## Get an emoji icon for a file entry based on its type and extension
  if entry.kind == fekDirectory or entry.targetKind == fekDirectory:
    return "📁 "

  if entry.isExecutable:
    return "🏃 "

  let filename = entry.name
  # Check for Dockerfile
  if filename == "Dockerfile" or filename.startsWith("Dockerfile."):
    return "🐳 "

  # Get extension
  let dotPos = filename.rfind('.')
  if dotPos < 0:
    return "📄 "

  let ext = filename[dotPos + 1 .. ^1].toLower()
  case ext
  of "nim": "👑 "
  of "nimble", "rpm", "deb": "📦 "
  of "py": "🐍 "
  of "ui", "glade": "🏠 "
  of "txt", "md", "rst": "📝 "
  of "cpp", "cxx", "hpp", "cc": "⧺ "
  of "c", "h": "🅒 "
  of "java": "🍵 "
  of "php": "🙈 "
  of "js", "json", "mjs", "cjs": "🙉 "
  of "ts", "tsx": "📘 "
  of "rs": "🦀 "
  of "go": "🐹 "
  of "html", "xhtml", "htm": "🏄 "
  of "css", "scss", "sass": "👚 "
  of "xml": "༕ "
  of "cfg", "ini", "conf": "🍳 "
  of "sh", "bash", "zsh", "fish": "🐚 "
  of "pdf", "doc", "docx", "odf", "ods", "odt": "🍞 "
  of "wav", "mp3", "ogg", "flac", "m4a": "🎼 "
  of "zip", "bz2", "xz", "gz", "tgz", "zst", "tar", "7z", "rar": "🚢 "
  of "exe", "bin", "elf": "🏃 "
  of "mp4", "webm", "avi", "mpeg", "mkv", "mov": "🎞 "
  of "patch", "diff": "💊 "
  of "lock": "🔒 "
  of "pem", "crt", "key": "🔏 "
  of "png", "jpeg", "jpg", "bmp", "gif", "svg", "webp", "ico": "🎨 "
  of "toml", "yaml", "yml": "⚙ "
  of "nix": "❄ "
  of "hs", "lhs": "λ "
  of "lua": "🌙 "
  of "rb": "💎 "
  of "pl", "pm": "🐪 "
  of "sql": "🗃 "
  of "vim": "📗 "
  of "el", "lisp", "scm": "λ "
  else: "📄 "

proc renderFiler(e: Editor, buffer: var Buffer) =
  ## Render the file explorer view
  if e.state.filerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    filerState = e.state.filerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header (current path)
  let headerText =
    if filerState.currentPath.len > width - 2:
      "..." & filerState.currentPath[^(width - 5) .. ^1]
    else:
      filerState.currentPath
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected entry is visible (pass total reserved: 1 header + reservedBottom)
  filerState.ensureSelectedVisible(buffer.area.height, 1 + reservedBottom)

  # Render file entries
  var screenY = listStartY
  for i in filerState.topLine ..< filerState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = filerState.entries[i]
      isSelected = i == filerState.selectedIndex

    # Build display line
    var displayLine: string

    let icon =
      if e.config.filer.showIcons:
        pathToIcon(entry)
      else:
        case entry.kind
        of fekDirectory: "▸ "
        of fekSymlink: "@ "
        of fekFile: "  "

    let name =
      if entry.isDirectory:
        entry.name & "/"
      else:
        entry.name

    displayLine = " " & icon & name

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Pad to full width for selected line (so background color fills entire line)
    if isSelected and displayLine.len < width:
      displayLine = displayLine & " ".repeat(width - displayLine.len)

    # Apply style (use theme background color to match clearBuffer)
    let themeBg = normalStyle().bg
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif entry.kind == fekDirectory:
        Style(fg: rgb(0x5f, 0x87, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif entry.kind == fekSymlink:
        # Symlinks: cyan for files, magenta for directories
        if entry.targetKind == fekDirectory:
          Style(fg: rgb(0xaf, 0x5f, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
        else:
          Style(fg: rgb(0x00, 0xff, 0xff), bg: themeBg, modifiers: {})
      elif entry.isHidden:
        Style(fg: rgb(0x80, 0x80, 0x80), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in filer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (filerState.selectedIndex - filerState.topLine)

proc renderBufferManager(e: Editor, buffer: var Buffer) =
  ## Render the buffer manager view
  if e.state.bufferManagerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    bmState = e.state.bufferManagerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- Buffer Manager --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  if bmState.selectedIndex >= bmState.topLine + visibleLines:
    bmState.topLine = bmState.selectedIndex - visibleLines + 1
  if bmState.selectedIndex < bmState.topLine:
    bmState.topLine = bmState.selectedIndex

  # Render buffer entries
  var screenY = listStartY
  for i in bmState.topLine ..< bmState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = bmState.entries[i]
      isSelected = i == bmState.selectedIndex

    # Build display line
    var displayLine: string
    let prefix = if isSelected: "> " else: "  "
    let activeMark = if entry.active: "* " else: "  "
    let modifiedMark = if entry.modified: "[+] " else: "    "
    let indexStr = $entry.index & ": "

    displayLine = prefix & activeMark & indexStr & modifiedMark & entry.name

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Pad to full width for selected line (so background color fills entire line)
    if isSelected and displayLine.len < width:
      displayLine = displayLine & " ".repeat(width - displayLine.len)

    # Apply style (use theme background color to match clearBuffer)
    let themeBg = normalStyle().bg
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif entry.active:
        Style(fg: rgb(0x5f, 0xff, 0x5f), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif entry.modified:
        Style(fg: rgb(0xff, 0x87, 0x00), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in buffer manager mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (bmState.selectedIndex - bmState.topLine)

proc renderConfigMode(e: Editor, buffer: var Buffer) =
  ## Render the configuration mode view
  if e.state.configModeState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    configState = e.state.configModeState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  var headerText = "-- Configuration --"
  if headerText.len < width:
    headerText = headerText & ' '.repeat(width - headerText.len)
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Calculate max name width for alignment
  var maxNameWidth = 0
  for item in configState.items:
    if item.kind != cvkSection:
      maxNameWidth = max(maxNameWidth, item.displayName.len + item.depth * 2)
  maxNameWidth = min(maxNameWidth + 4, width div 2) # Limit to half of width

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  configState.ensureSelectedVisible(visibleLines)

  # Render config entries
  var screenY = listStartY
  let isEditMode = configState.isEditing()
  let editInfo = configState.getEditInfo()
  let themeBg = normalStyle().bg

  for i in configState.topLine ..< configState.items.len:
    if screenY >= listEndY:
      break

    let
      item = configState.items[i]
      isSelected = i == configState.selectedIndex
      isBeingEdited = isSelected and isEditMode and item.kind in {cvkInt, cvkString}

    # Build display line
    var displayLine: string
    if isBeingEdited:
      # Show edit buffer
      let indent = "  ".repeat(item.depth)
      let name = item.displayName.alignLeft(maxNameWidth - item.depth * 2)
      displayLine = indent & name & " : " & editInfo.buffer
    else:
      displayLine = formatItemForDisplay(item, maxNameWidth)

    # Truncate if too long, or pad to full width for consistent background
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."
    elif displayLine.len < width:
      displayLine = displayLine & ' '.repeat(width - displayLine.len)

    # Apply style (use theme background color to match clearBuffer)
    let style =
      if isBeingEdited:
        # Edit mode style - yellow background
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xd7, 0x00), modifiers: {})
      elif isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif item.kind == cvkSection:
        Style(fg: rgb(0x5f, 0xff, 0x5f), bg: themeBg, modifiers: {StyleModifier.Bold})
      elif item.kind == cvkBool:
        if item.boolValue:
          Style(fg: rgb(0x5f, 0xaf, 0x5f), bg: themeBg, modifiers: {})
        else:
          Style(fg: rgb(0xaf, 0x5f, 0x5f), bg: themeBg, modifiers: {})
      elif item.kind == cvkEnum:
        Style(fg: rgb(0x87, 0xaf, 0xd7), bg: themeBg, modifiers: {})
      elif item.kind == cvkInt:
        Style(fg: rgb(0xd7, 0xaf, 0x5f), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Clear remaining lines (when sections are collapsed)
  let emptyLine = ' '.repeat(width)
  while screenY < listEndY:
    buffer.setString(buffer.area.x, screenY, emptyLine, normalStyle())
    inc screenY

  # Render enum popup if open
  let isEnumPopupOpen = configState.isEnumPopupOpen()
  if isEnumPopupOpen:
    let enumInfo = configState.getEnumPopupInfo()
    if enumInfo.options.len > 0:
      # Calculate popup dimensions
      var popupWidth = 0
      for opt in enumInfo.options:
        popupWidth = max(popupWidth, opt.len)
      popupWidth += 4 # padding and border
      let popupHeight = enumInfo.options.len + 2 # options + border

      # Calculate popup position (near the value display position)
      let selectedY = listStartY + (configState.selectedIndex - configState.topLine)
      let selectedItem = configState.getSelectedItem()
      var valueX = maxNameWidth + 5 # indent + name + " : "
      if selectedItem.isSome:
        valueX =
          selectedItem.get.depth * 2 + maxNameWidth - selectedItem.get.depth * 2 + 3

      var popupX = valueX
      var popupY = selectedY + 1
      # Adjust if popup goes off screen
      if popupX + popupWidth > width:
        popupX = max(0, width - popupWidth)
      if popupY + popupHeight > listEndY:
        popupY = max(listStartY, selectedY - popupHeight)
      if popupX < 0:
        popupX = 0

      let
        popupBg = rgb(0x30, 0x30, 0x30)
        popupFg = rgb(0xff, 0xff, 0xff)
        selectedBg = rgb(0x00, 0x5f, 0xaf)
        borderStyle = Style(fg: popupFg, bg: popupBg, modifiers: {})
        normalStyle = Style(fg: popupFg, bg: popupBg, modifiers: {})
        selectedStyle =
          Style(fg: popupFg, bg: selectedBg, modifiers: {StyleModifier.Bold})

      # Draw top border
      let topBorder = "┌" & "─".repeat(popupWidth - 2) & "┐"
      buffer.setString(buffer.area.x + popupX, popupY, topBorder, borderStyle)

      # Draw options
      for i, opt in enumInfo.options:
        let
          y = popupY + 1 + i
          isSelected = i == enumInfo.selectedIndex
          style = if isSelected: selectedStyle else: normalStyle
          line = "│ " & opt.alignLeft(popupWidth - 4) & " │"
        buffer.setString(buffer.area.x + popupX, y, line, style)

      # Draw bottom border
      let bottomBorder = "└" & "─".repeat(popupWidth - 2) & "┘"
      buffer.setString(
        buffer.area.x + popupX, popupY + popupHeight - 1, bottomBorder, borderStyle
      )

  # Set cursor position - only visible in edit mode
  if isEditMode:
    # Position cursor within the edit buffer
    let selectedItem = configState.getSelectedItem()
    if selectedItem.isSome:
      let item = selectedItem.get
      let indent = item.depth * 2
      let nameWidth = maxNameWidth - item.depth * 2
      # cursor x = indent + name + " : " + edit cursor position
      e.state.screenCursor.x = indent + nameWidth + 3 + editInfo.cursor
      e.state.screenCursor.y =
        listStartY + (configState.selectedIndex - configState.topLine)
  else:
    # Hide cursor by moving it off-screen
    e.state.screenCursor.x = -1
    e.state.screenCursor.y = -1

proc renderBackupManager(e: Editor, buffer: var Buffer) =
  ## Render the backup manager view
  if e.state.backupManagerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    bkState = e.state.backupManagerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- Backup Manager: " & bkState.sourceFilePath & " --"
  buffer.setString(
    buffer.area.x,
    headerY,
    if headerText.len > width:
      headerText[0 ..< width]
    else:
      headerText,
    Style(
      fg: rgb(0xff, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Handle empty list
  if bkState.entries.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No backup files found",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: normalStyle().bg, modifiers: {}),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Ensure selected entry is visible
  let visibleLines = listEndY - listStartY
  if bkState.selectedIndex >= bkState.topLine + visibleLines:
    bkState.topLine = bkState.selectedIndex - visibleLines + 1
  if bkState.selectedIndex < bkState.topLine:
    bkState.topLine = bkState.selectedIndex

  # Render backup entries
  var screenY = listStartY
  for i in bkState.topLine ..< bkState.entries.len:
    if screenY >= listEndY:
      break

    let
      entry = bkState.entries[i]
      isSelected = i == bkState.selectedIndex

    # Build display line with formatted timestamp
    let prefix = if isSelected: "> " else: "  "
    let displayLine = prefix & formatEntry(entry)

    # Apply style (use theme background color to match clearBuffer)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (bkState.selectedIndex - bkState.topLine)

proc renderDiffViewer(e: Editor, buffer: var Buffer) =
  ## Render the diff viewer view
  if e.state.diffViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    dvState = e.state.diffViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText =
    "-- Diff: " & extractFilename(dvState.sourceFilePath) & " vs backup --"
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    if headerText.len > width:
      headerText[0 ..< width]
    else:
      headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
  )

  # Handle empty diff
  if dvState.lines.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No diff content",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: themeBg, modifiers: {}),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Ensure selected line is visible
  let visibleLines = listEndY - listStartY
  if dvState.selectedLine >= dvState.topLine + visibleLines:
    dvState.topLine = dvState.selectedLine - visibleLines + 1
  if dvState.selectedLine < dvState.topLine:
    dvState.topLine = dvState.selectedLine

  # Render diff lines
  var screenY = listStartY
  for i in dvState.topLine ..< dvState.lines.len:
    if screenY >= listEndY:
      break

    let
      line = dvState.lines[i]
      isSelected = i == dvState.selectedLine

    # Truncate line if too long
    let displayText =
      if line.text.len > width:
        line.text[0 ..< width]
      else:
        line.text

    # Apply style based on diff line kind and selection (use theme background)
    let style =
      if isSelected:
        # Highlighted/selected line
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        case line.kind
        of dlkAdded:
          # Added lines in green
          Style(fg: rgb(0x00, 0xd7, 0x00), bg: themeBg, modifiers: {})
        of dlkDeleted:
          # Deleted lines in red
          Style(fg: rgb(0xff, 0x5f, 0x5f), bg: themeBg, modifiers: {})
        of dlkHeader:
          # Header lines (@@, ---, +++) in cyan/bold
          Style(fg: rgb(0x00, 0xd7, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
        of dlkMeta:
          # Meta lines (diff --git, index) in yellow
          Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {})
        of dlkNormal:
          # Normal context lines
          normalStyle()

    buffer.setString(buffer.area.x, screenY, displayText, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (dvState.selectedLine - dvState.topLine)

proc renderRecentFileMode(e: Editor, buffer: var Buffer) =
  ## Render the recent file selection view
  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    state = e.recentFileModeState
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width
    viewportHeight = listEndY - listStartY

  # Render header
  let headerText = "-- Recent Files --"
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
  )

  # Handle empty list
  if state.files.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No recent files found",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: themeBg, modifiers: {}),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Adjust viewport to keep selected visible
  state.adjustViewport(viewportHeight)

  # Render file entries
  let visibleFiles = state.getVisibleFiles(viewportHeight)
  var screenY = listStartY
  for i, entry in visibleFiles:
    if screenY >= listEndY:
      break

    let
      actualIndex = state.topLine + i
      isSelected = actualIndex == state.selectedIndex

    # Build display line
    let prefix = if isSelected: "> " else: "  "
    var displayLine = prefix & entry.path

    # Truncate if too long
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Apply style - check if file exists (use theme background)
    let exists = fileExists(entry.path)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif not exists:
        # Non-existent files in dim gray
        Style(fg: rgb(0x60, 0x60, 0x60), bg: themeBg, modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (state.selectedIndex - state.topLine)

proc renderDebugMode(e: Editor, buffer: var Buffer) =
  ## Render the debug viewer
  if e.state.debugViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    debugState = e.state.debugViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width
    viewportHeight = listEndY - listStartY

  # Get theme colors
  let
    defaultStyle = getThemeStyle(EditorColorPairIndex.default)
    defaultBg = defaultStyle.bg

  # Fill entire area with default background first
  let emptyLine = spaces(width)
  for y in buffer.area.y ..< listEndY:
    buffer.setString(buffer.area.x, y, emptyLine, defaultStyle)

  # Render header
  let headerText = "-- DEBUG --"
  let headerStyle =
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: defaultBg, modifiers: {StyleModifier.Bold})
  buffer.setString(buffer.area.x, headerY, headerText, headerStyle)

  # Handle empty list
  if debugState.lines.len == 0:
    buffer.setString(
      buffer.area.x,
      listStartY,
      "No debug information available",
      Style(fg: rgb(0x87, 0x87, 0x87), bg: defaultBg, modifiers: {}),
    )
    e.state.screenCursor.x = 0
    e.state.screenCursor.y = listStartY
    return

  # Render debug lines
  var screenY = listStartY
  for i in debugState.topLine ..<
      min(debugState.lines.len, debugState.topLine + viewportHeight):
    if screenY >= listEndY:
      break

    let
      line = debugState.lines[i]
      isSelected = i == debugState.selectedLine

    # Truncate if too long
    var displayLine = line
    if displayLine.len > width:
      displayLine = displayLine[0 ..< width - 3] & "..."

    # Apply style based on content
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif line.startsWith("--"):
        # Section headers
        Style(fg: rgb(0x87, 0xaf, 0xff), bg: defaultBg, modifiers: {StyleModifier.Bold})
      else:
        defaultStyle

    # Pad line to fill width for consistent background
    let paddedLine = displayLine & spaces(max(0, width - displayLine.len))
    buffer.setString(buffer.area.x, screenY, paddedLine, style)
    inc screenY

  # Set cursor position
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (debugState.selectedLine - debugState.topLine)

proc renderReferencesViewer(e: Editor, buffer: var Buffer) =
  ## Render the references viewer view
  if e.state.referencesViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    refState = e.state.referencesViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header with title
  let headerText =
    "-- " & refState.title.toUpperAscii() & " (" & $refState.itemCount() & ") --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0x00, 0xaf, 0xff), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected line is visible
  refState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render reference lines
  var screenY = listStartY
  for i in refState.topLine ..< refState.itemCount:
    if screenY >= listEndY:
      break

    let
      line = refState.getLine(i)
      isSelected = i == refState.selectedIndex

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in references viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (refState.selectedIndex - refState.topLine)

proc renderDocumentSymbolViewer(e: Editor, buffer: var Buffer) =
  ## Render the document symbol viewer view
  if e.state.documentSymbolViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    symState = e.state.documentSymbolViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header with title
  let headerText = "-- SYMBOLS (" & $symState.itemCount() & ") --"
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(
      fg: rgb(0xaf, 0xd7, 0x00), bg: normalStyle().bg, modifiers: {StyleModifier.Bold}
    ),
  )

  # Ensure selected line is visible
  symState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render symbol lines
  var screenY = listStartY
  for i in symState.topLine ..< symState.itemCount:
    if screenY >= listEndY:
      break

    let
      line = symState.getLine(i)
      isSelected = i == symState.selectedIndex

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in document symbol viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (symState.selectedIndex - symState.topLine)

proc renderHelpViewer(e: Editor, buffer: var Buffer) =
  ## Render the help viewer view
  if e.state.helpViewerState.isNone:
    return

  # Calculate reserved lines at bottom: status line (if shown) + command line
  let reservedBottom =
    if e.state.display.showStatusLine: StatusAndCommandReserve else: CommandLineReserve

  let
    helpState = e.state.helpViewerState.get
    headerY = buffer.area.y
    listStartY = buffer.area.y + 1
    listEndY = buffer.area.y + buffer.area.height - reservedBottom
    width = buffer.area.width

  # Render header
  let headerText = "-- HELP --"
  let themeBg = normalStyle().bg
  buffer.setString(
    buffer.area.x,
    headerY,
    headerText,
    Style(fg: rgb(0xff, 0xd7, 0x00), bg: themeBg, modifiers: {StyleModifier.Bold}),
  )

  # Ensure selected line is visible
  helpState.ensureSelectedVisible(buffer.area.height - 1 - reservedBottom)

  # Render help lines
  var screenY = listStartY
  for i in helpState.topLine ..< helpState.lineCount:
    if screenY >= listEndY:
      break

    let
      line = helpState.getLine(i)
      isSelected = i == helpState.selectedIndex
      isHeader = line.len > 0 and line[0] == '#'

    # Truncate if too long
    var displayLine =
      if line.len > width:
        line[0 ..< width - 3] & "..."
      else:
        line

    # Apply style (use theme background)
    let style =
      if isSelected:
        Style(fg: rgb(0x00, 0x00, 0x00), bg: rgb(0xff, 0xff, 0xff), modifiers: {})
      elif isHeader:
        Style(fg: rgb(0x5f, 0xaf, 0xff), bg: themeBg, modifiers: {StyleModifier.Bold})
      else:
        normalStyle()

    buffer.setString(buffer.area.x, screenY, displayLine, style)
    inc screenY

  # Set cursor position (hidden in help viewer mode, but set to selected line)
  e.state.screenCursor.x = 0
  e.state.screenCursor.y = listStartY + (helpState.selectedIndex - helpState.topLine)
