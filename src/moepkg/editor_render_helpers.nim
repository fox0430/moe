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

## Common helper procedures for rendering

import std/[options, strutils, unicode, tables]

import pkg/celina

import editor_types, color, render_utils, unicode_utils, search_utils, highlight, modes

proc colorIndexToStyle*(colorIdx: EditorColorPairIndex): Style =
  ## Convert EditorColorPairIndex to Celina Style using theme colors
  getThemeStyle(colorIdx)

proc analyzeIndentation*(lineText: string): IndentInfo =
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

proc isPositionInDocumentHighlight*(e: Editor, pos: BufferPosition): Option[int] =
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

proc getDocumentHighlightStyle*(kind: int): Style =
  ## Get the style for a document highlight based on its kind
  case kind
  of 2: # Read
    documentHighlightReadStyle()
  of 3: # Write
    documentHighlightWriteStyle()
  else: # Text or unknown
    documentHighlightTextStyle()

proc hasSyntaxHighlight(
    e: Editor, buffer: TextBuffer, windowMode: EditorMode
): bool {.inline.} =
  e.state.display.showSyntax and not buffer.highlight.isNil and
    (windowMode.isFileEditMode or buffer.language != langNone or buffer.isUtilityBuffer)

proc getSelectionStyle*(
    e: Editor,
    buffer: TextBuffer,
    hasSelection: bool,
    pos: BufferPosition,
    cursorLine: int,
    cursorCol: int,
    windowMode: EditorMode,
): Style =
  ## Get the appropriate style for a character based on selection state and syntax
  ## windowMode: The mode of the window being rendered (for correct per-window highlighting)

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
    not e.state.isSearchOverlay and e.state.currentWord.len > 0 and
    not isInSameWordAsCursor and buffer.isPositionInWord(pos, e.state.currentWord)

  if hasSelection and e.state.visualSelection.isPositionInSelection(pos):
    visualStyle()
  elif isMatchingParen:
    # Highlight matching paren with special style
    parenPairStyle()
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
      if e.state.isSearchOverlay:
        # In Search mode: only highlight if user has typed something
        if e.state.search.text.len > 0:
          e.state.search.text
        else:
          "" # No highlight when starting a new search
      elif e.state.isCommandOverlay:
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
      elif e.hasSyntaxHighlight(buffer, windowMode):
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
    elif e.hasSyntaxHighlight(buffer, windowMode):
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
  elif e.hasSyntaxHighlight(buffer, windowMode):
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

proc isVisualMode*(mode: EditorMode): bool {.inline.} =
  ## Check if the mode is any visual mode variant
  mode in {EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine}

proc getVisualSelection*(
    e: Editor, windowMode: EditorMode, windowActive: bool = true
): tuple[hasSelection: bool, selStart, selEnd: BufferPosition] =
  ## Get visual selection range if active
  ## windowMode: The mode of the window being rendered
  ## windowActive: only show selection in active window (default true for compatibility)
  let hasSelection =
    isVisualMode(windowMode) and e.state.visualSelection.active and windowActive

  if hasSelection:
    let (start, endPos) = e.state.visualSelection.getSelectionRange()
    result = (hasSelection: true, selStart: start, selEnd: endPos)
  else:
    result = (
      hasSelection: false,
      selStart: BufferPosition(line: 0, column: 0),
      selEnd: BufferPosition(line: 0, column: 0),
    )

proc fillLine*(buffer: var Buffer, x, y, width: int, style: Style) =
  ## Fill a line with spaces at the given position and width
  buffer.setString(x, y, " ".repeat(width), style)

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
        if e.config.highlight.trailingSpaces and col >= trailingSpaceStart and
            ctx.windowMode.isFileEditMode:
          trailingSpacesStyle()
        else:
          style
      # Render spaces instead of tab character
      for i in 0 ..< spacesToNextTab:
        if screenX + displayX < ctx.windowRightEdge:
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

      # Highlight full-width space if enabled (only in file edit modes)
      if rune == FULLWIDTH_SPACE and e.config.highlight.fullWidthSpace and
          ctx.windowMode.isFileEditMode:
        renderStyle = fullWidthSpaceStyle()

      # Highlight trailing spaces if enabled (only in file edit modes)
      if e.config.highlight.trailingSpaces and col >= trailingSpaceStart and
          ctx.windowMode.isFileEditMode:
        if rune == ' '.Rune or rune == TAB_CHAR or rune == FULLWIDTH_SPACE:
          renderStyle = trailingSpacesStyle()

      if screenX + displayX < ctx.windowRightEdge:
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
          textBuffer, ctx.hasSelection, pos, ctx.cursorLine, ctx.cursorCol,
          ctx.windowMode,
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
          textBuffer, ctx.hasSelection, pos, ctx.cursorLine, ctx.cursorCol,
          ctx.windowMode,
        )
      renderChar(rune, col, style)
      charIdx += 1

  # Fill the rest of the line with cursor line highlight if on cursor line
  if e.state.display.showCursorLine and lineIndex == ctx.cursorLine:
    while screenX + displayX < ctx.windowRightEdge:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle())
      displayX += 1

proc fillCursorLineBackground*(
    e: Editor,
    buffer: var Buffer,
    screenX, screenY: int,
    lineIndex, cursorLine: int,
    windowRightEdge: int,
) =
  ## Fill the rest of the line with cursor line background if on cursor line
  if e.state.display.showCursorLine and lineIndex == cursorLine:
    var displayX = 0
    while screenX + displayX < windowRightEdge:
      buffer.setString(screenX + displayX, screenY, " ", cursorLineHighlightStyle())
      displayX += 1

proc renderCodeLensInline*(
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
