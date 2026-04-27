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

import
  editor_types, color, render_utils, unicode_utils, search_utils, highlight, modes,
  colorcode, git_conflict

proc colorIndexToStyle*(colorIdx: EditorColorPairIndex): Style =
  ## Convert EditorColorPairIndex to Celina Style using theme colors
  getThemeStyle(colorIdx)

proc isColumnInRanges*(ranges: seq[ColumnRange], col: int): bool {.inline.} =
  ## Check if a column is within any of the pre-computed ranges.
  ## O(m) where m is the number of ranges on the line (typically small).
  for r in ranges:
    if col >= r.startCol and col < r.endCol:
      return true
  return false

proc bufferColToDisplayCol*(
    text: string, bufferCol: int, tabStop: int, startCol: int = 0
): int =
  ## Convert a buffer column (character index) to a display column (screen position).
  ## Accounts for tab expansion and wide characters.
  ## startCol: first visible column (e.g. leftColumn for horizontal scroll).
  ## The result is relative to startCol, matching the rendering loop's behavior.
  ## Returns -1 if bufferCol is before startCol (cursor scrolled off-screen).
  if bufferCol < startCol:
    return -1
  var currentChar = 0
  for rune in text.runes:
    if currentChar >= bufferCol:
      break
    if currentChar >= startCol:
      if rune == '\t'.Rune:
        result += tabStop - (result mod tabStop)
      else:
        result += runeWidth(rune)
    currentChar.inc

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
    e.config.highlight.findCharHighlight and e.state.findCharMatches.len > 0 and
    pos.line == e.state.findCharMatchLine and pos.column in e.state.findCharMatches

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
