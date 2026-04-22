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

## Rendering helper functions and utilities
##
## This module contains pure functions and utilities for rendering operations
## that don't depend heavily on Editor state. Extracted from editor.nim to
## improve modularity and prepare for additional rendering features.

import std/unicode
import pkg/celina

import types, buffer, unicode_utils, color

# Rendering constants
const
  TAB_CHAR* = 0x09.Rune ## Tab character constant
  FULLWIDTH_SPACE* = 0x3000.Rune ## Full-width space character (U+3000)

  TabLineHeight* = 1 ## Height of tab line
  StatusLineReserve* = 1
  CommandLineReserve* = 1
  StatusAndCommandReserve* = 1

  # Line number display constants
  LineNumberBase* = 1 # Convert 0-based index to 1-based display
  LineNumberSpacer* = 1 # Space after line number
  LineNumberPadding* = 1 # Padding for alignment
  LineNumberWidthExtra* = 2 # Extra width for line number area (number + spaces)

# Rendering style getters - dynamically retrieve from theme

proc normalStyle*(): Style =
  ## Get default text style from theme
  getThemeStyle(EditorColorPairIndex.default)

proc visualStyle*(): Style =
  ## Get visual selection style from theme
  getThemeStyle(EditorColorPairIndex.selectArea)

proc searchHighlightStyle*(): Style =
  ## Get search result highlight style from theme
  getThemeStyle(EditorColorPairIndex.searchResult)

proc gitConflictStyle*(): Style =
  ## One-color fallback for git conflict highlighting (used when the
  ## two-color config is disabled).
  getThemeStyle(EditorColorPairIndex.gitConflict)

proc gitConflictMarkerStyle*(): Style =
  ## Style for the marker lines (`<<<<<<<` / `|||||||` / `=======` / `>>>>>>>`).
  getThemeStyle(EditorColorPairIndex.gitConflictMarker)

proc gitConflictOursStyle*(): Style =
  ## Style for the "ours" side of a merge conflict.
  getThemeStyle(EditorColorPairIndex.gitConflictOurs)

proc gitConflictBaseStyle*(): Style =
  ## Style for the base (merged common ancestor) side of a diff3 conflict.
  getThemeStyle(EditorColorPairIndex.gitConflictBase)

proc gitConflictTheirsStyle*(): Style =
  ## Style for the "theirs" side of a merge conflict.
  getThemeStyle(EditorColorPairIndex.gitConflictTheirs)

proc conflictStyleFor*(kind: ConflictMarkerKind, useTwoColor: bool): Style =
  ## Resolve the background style for a conflict line kind.
  if not useTwoColor:
    return gitConflictStyle()
  case kind
  of cmkStartMarker, cmkBaseMarker, cmkSeparator, cmkEndMarker:
    gitConflictMarkerStyle()
  of cmkOurs:
    gitConflictOursStyle()
  of cmkBase:
    gitConflictBaseStyle()
  of cmkTheirs:
    gitConflictTheirsStyle()
  of cmkNone:
    normalStyle()

proc lineNumStyle*(): Style =
  ## Get line number style from theme
  getThemeStyle(EditorColorPairIndex.lineNum)

proc currentLineStyle*(): Style =
  ## Get current line number style from theme (with bold)
  getThemeStyle(EditorColorPairIndex.currentLineNum, {StyleModifier.Bold})

proc separatorStyle*(): Style =
  ## Get separator style (uses line number colors)
  getThemeStyle(EditorColorPairIndex.lineNum)

proc commandStyle*(): Style =
  ## Get command line style from theme (with bold)
  getThemeStyle(EditorColorPairIndex.commandLine, {StyleModifier.Bold})

proc cursorLineHighlightStyle*(): Style =
  ## Get current line background highlight style from theme
  getThemeStyle(EditorColorPairIndex.currentLineBg)

proc cursorColumnHighlightStyle*(): Style =
  ## Get current column background highlight style from theme
  getThemeStyle(EditorColorPairIndex.currentColumnBg)

proc findCharMatchStyle*(): Style =
  ## Get find character match highlight style from theme (f/F/t/T)
  getThemeStyle(EditorColorPairIndex.findCharMatch)

proc indentationLineStyle*(): Style =
  ## Get indentation guide style (slightly darker than background)
  let colorPair = getThemeColor(EditorColorPairIndex.default)
  Style(
    fg: ColorValue(kind: Rgb, rgb: RgbColor(r: 70, g: 70, b: 70)),
    bg: colorPair.background.rgb.toColorValue,
    modifiers: {},
  )

proc foldStyle*(): Style =
  ## Get folding line style from theme
  getThemeStyle(EditorColorPairIndex.foldingLine)

proc scrollbarThumbStyle*(): Style =
  ## Get scrollbar thumb (handle) style — solid block via background color
  Style(
    fg: ColorValue(kind: Rgb, rgb: RgbColor(r: 120, g: 120, b: 120)),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 120, g: 120, b: 120)),
    modifiers: {},
  )

proc scrollbarTrackStyle*(): Style =
  ## Get scrollbar track (background) style — subtle via background color
  let colorPair = getThemeColor(EditorColorPairIndex.default)
  Style(
    fg: ColorValue(kind: Rgb, rgb: RgbColor(r: 50, g: 50, b: 50)),
    bg: colorPair.background.rgb.toColorValue,
    modifiers: {},
  )

proc fullWidthSpaceStyle*(): Style =
  ## Get full-width space highlight style from theme
  getThemeStyle(EditorColorPairIndex.highlightFullWidthSpace)

proc trailingSpacesStyle*(): Style =
  ## Get trailing spaces highlight style from theme
  getThemeStyle(EditorColorPairIndex.highlightTrailingSpaces)

proc parenPairStyle*(): Style =
  ## Get matching parenthesis pair highlight style from theme
  getThemeStyle(EditorColorPairIndex.parenPair)

proc currentWordStyle*(): Style =
  ## Get current word highlight style from theme
  getThemeStyle(EditorColorPairIndex.currentWord)

proc codeLensStyle*(): Style =
  ## Get code lens style from theme
  getThemeStyle(EditorColorPairIndex.codeLens)

# Document Highlight styles (LSP textDocument/documentHighlight)
# These use fixed colors for now as they are not in the theme
proc documentHighlightTextStyle*(): Style =
  ## Style for generic text occurrence (DocumentHighlightKind.Text)
  Style(
    fg: ColorValue(kind: Default),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 60, g: 60, b: 80)),
    modifiers: {},
  )

proc documentHighlightReadStyle*(): Style =
  ## Style for read-access of a symbol (DocumentHighlightKind.Read)
  Style(
    fg: ColorValue(kind: Default),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 40, g: 70, b: 40)),
    modifiers: {},
  )

proc documentHighlightWriteStyle*(): Style =
  ## Style for write-access of a symbol (DocumentHighlightKind.Write)
  Style(
    fg: ColorValue(kind: Default),
    bg: ColorValue(kind: Rgb, rgb: RgbColor(r: 80, g: 50, b: 50)),
    modifiers: {},
  )

# Pure utility functions

proc formatLineNumber*(lineIndex: int, width: int): string =
  ## Format a line number string with proper alignment
  align($(lineIndex + LineNumberBase), width - LineNumberPadding) & " "

proc formatRelativeLineNumber*(lineIndex: int, cursorLine: int, width: int): string =
  ## Format a relative line number string. Current line shows absolute number.
  let num =
    if lineIndex == cursorLine:
      lineIndex + LineNumberBase
    else:
      abs(lineIndex - cursorLine)
  align($num, width - LineNumberPadding) & " "

proc displayWidthSubstrWithTabs*(
    text: string, startChar: int, maxWidth: int, tabStop: int
): (int, int) =
  ## Calculate how many characters from startChar fit within maxWidth display columns,
  ## accounting for tab characters expanded relative to the segment start.
  ## Returns (charCount, actualDisplayWidth)
  let safeTabStop = if tabStop > 0: tabStop else: 1
  var
    currentChar = 0
    currentWidth = 0
    charCount = 0

  for rune in text.runes:
    if currentChar < startChar:
      currentChar += 1
      continue

    let w =
      if rune == TAB_CHAR:
        safeTabStop - (currentWidth mod safeTabStop)
      else:
        runeWidth(rune)

    if currentWidth + w > maxWidth:
      break

    currentWidth += w
    charCount += 1
    currentChar += 1

  return (charCount, currentWidth)

proc displayWidthSubstrFromByte*(
    text: string, startByte: int, maxWidth: int, tabStop: int
): (int, int, int) =
  ## Calculate segment boundary starting from a byte position.
  ## Returns (charCount, actualDisplayWidth, endBytePosition).
  ## Unlike displayWidthSubstrWithTabs, this starts directly from startByte
  ## instead of scanning from the beginning, avoiding O(startChar) skip overhead.
  let safeTabStop = if tabStop > 0: tabStop else: 1
  var
    bytePos = startByte
    currentWidth = 0
    charCount = 0

  while bytePos < text.len:
    let
      rune = text.runeAt(bytePos)
      runeBytes = runeLenAt(text, bytePos)
      w =
        if rune == TAB_CHAR:
          safeTabStop - (currentWidth mod safeTabStop)
        else:
          runeWidth(rune)

    if charCount > 0 and currentWidth + w > maxWidth:
      # Character doesn't fit — return without including it
      return (charCount, currentWidth, bytePos)

    currentWidth += w
    charCount += 1
    bytePos += runeBytes

  return (charCount, currentWidth, bytePos)

proc screenXToCharIndex*(
    text: string, startChar: int, targetDisplayX: int, tabStop: int
): int =
  ## Return the character offset (from startChar) corresponding to targetDisplayX
  ## display columns within a wrap segment starting at startChar.
  ## For multi-column characters (tabs, wide chars), clicking anywhere within the
  ## character's display width selects that character.
  let safeTabStop = if tabStop > 0: tabStop else: 1
  var
    currentChar = 0
    currentWidth = 0
    charOffset = 0

  for rune in text.runes:
    if currentChar < startChar:
      currentChar += 1
      continue

    let w =
      if rune == TAB_CHAR:
        safeTabStop - (currentWidth mod safeTabStop)
      else:
        runeWidth(rune)

    # If targetDisplayX falls within this character's range, stop here
    if currentWidth + w > targetDisplayX:
      break

    currentWidth += w
    charOffset += 1
    currentChar += 1

  return charOffset

proc calculateWrapCount*(text: string, maxWidth: int, tabStop: int): int =
  ## Calculate how many screen lines a logical line will take when wrapped.
  ## Uses display width (accounting for tabs and wide characters).
  ## Single-pass O(n) implementation — iterates runes once without re-scanning.
  if text.len == 0:
    return 1
  let safeTabStop = if tabStop > 0: tabStop else: 1
  result = 1
  var segmentWidth = 0

  for rune in text.runes:
    let w =
      if rune == TAB_CHAR:
        safeTabStop - (segmentWidth mod safeTabStop)
      else:
        runeWidth(rune)

    if segmentWidth > 0 and segmentWidth + w > maxWidth:
      # This character starts a new segment
      result += 1
      # Recalculate width in new segment context (tab width depends on position)
      segmentWidth = if rune == TAB_CHAR: safeTabStop else: w
    else:
      segmentWidth += w

proc clearBuffer*(buffer: var Buffer) =
  ## Clear the entire buffer to prevent rendering artifacts
  ## Uses the theme's default background color for consistent appearance
  let clearStyle = normalStyle()

  for y in 0 ..< buffer.area.height:
    for x in 0 ..< buffer.area.width:
      buffer[x, y] = cell(" ", clearStyle)

# Layout calculation functions

proc calculateLineNumOffset*(buffer: TextBuffer, showLineNumber: bool = true): int =
  ## Calculate line number display offset based on buffer size
  ## If showLineNumber is false, returns 0 (line numbers hidden)
  ## Utility buffers (filer, buffer manager, etc.) never show line numbers
  if not showLineNumber or buffer.isUtilityBuffer:
    return 0
  if buffer.len > 0:
    len($buffer.len) + LineNumberSpacer
  else:
    0

proc calculateViewportOffset*(
    buffer: TextBuffer,
    showLineNumbers, showSidebar: bool,
    scrollbar: bool = false,
    scrollbarWidth: int = 0,
): int =
  ## Calculate the total line number + sidebar + scrollbar offset for viewport width calculations.
  ## Matches the rendering layout: sidebarWidth + lineNumOffset + scrollbarWidth.
  calculateLineNumOffset(buffer, showLineNumbers) + (if showSidebar: 2 else: 0) +
    # DefaultSidebarWidth = 2
  (if scrollbar: scrollbarWidth else: 0)

proc findMaxBottomY*(windows: seq[EditorWindow]): int =
  ## Find the maximum bottom Y coordinate among all windows
  result = 0
  for window in windows:
    let bottomY = window.viewport.y + window.viewport.height
    if bottomY > result:
      result = bottomY

proc calculateWindowStatusLineY*(window: EditorWindow, isBottomWindow: bool): int =
  ## Calculate Y position for window status line
  ## Status line is always at the last row of the window area (y + height - 1)
  ## For bottom windows, the command line overlays the status line when active
  window.viewport.y + window.viewport.height - 1

# Display width calculation with tab support

proc displayWidthUpToWithTabs*(text: string, charPos: int, tabStop: int): int =
  ## Calculate the display width from start to charPos, accounting for tab characters
  ## charPos is a character index (not byte position)
  ## Tab characters expand to the next tab stop position
  ##
  ## Note: If tabStop <= 0, it defaults to 1 to prevent division by zero.
  ##       If charPos < 0, returns 0.

  # Guard against invalid inputs without crashing
  if charPos < 0:
    return 0

  let safeTabStop = if tabStop > 0: tabStop else: 1

  result = 0
  var currentChar = 0

  for rune in text.runes:
    if currentChar >= charPos:
      break

    # Handle tab character specially
    if rune == TAB_CHAR:
      # Calculate spaces to next tab stop
      let spacesToNextTab = safeTabStop - (result mod safeTabStop)
      result += spacesToNextTab
    else:
      result += runeWidth(rune)

    currentChar += 1

proc displayWidthWithTabs*(text: string, tabStop: int): int =
  ## Calculate the display width of a string, accounting for tab characters
  ## Tab characters expand to the next tab stop position
  ##
  ## Note: If tabStop <= 0, it defaults to 1 to prevent division by zero.

  let safeTabStop = if tabStop > 0: tabStop else: 1

  result = 0
  for rune in text.runes:
    if rune == TAB_CHAR:
      let spacesToNextTab = safeTabStop - (result mod safeTabStop)
      result += spacesToNextTab
    else:
      result += runeWidth(rune)

proc cursorWrapPosition*(
    text: string, cursorChar: int, maxWidth: int, tabStop: int
): (int, int) =
  ## Calculate which wrap segment the cursor falls in and its display column
  ## within that segment. Returns (wrapLineIndex, displayColumnInSegment).
  ## Single-pass O(n) implementation — iterates runes once without re-scanning.
  if text.len == 0 or cursorChar <= 0:
    return (0, 0)

  let safeTabStop = if tabStop > 0: tabStop else: 1
  var
    segmentWidth = 0
    wrapLine = 0
    charIndex = 0

  for rune in text.runes:
    let w =
      if rune == TAB_CHAR:
        safeTabStop - (segmentWidth mod safeTabStop)
      else:
        runeWidth(rune)

    if segmentWidth > 0 and segmentWidth + w > maxWidth:
      # This character starts a new segment
      wrapLine += 1
      let newW = if rune == TAB_CHAR: safeTabStop else: w

      # Check if cursor is at (or past) this character
      if charIndex >= cursorChar:
        return (wrapLine, 0)

      segmentWidth = newW
    else:
      # Check if cursor is at (or past) this character
      if charIndex >= cursorChar:
        return (wrapLine, segmentWidth)

      segmentWidth += w

    charIndex += 1

  # Cursor is at or past end of text — return current segment position
  return (wrapLine, segmentWidth)

proc isWhitespace(rune: Rune): bool =
  ## Check if a rune is a whitespace character (space, tab, full-width space)
  rune == ' '.Rune or rune == TAB_CHAR or rune == FULLWIDTH_SPACE

proc findTrailingSpaceStart*(text: string): int =
  ## Find the character index where trailing spaces start.
  ## Returns the character count (length) if no trailing spaces.
  ## Returns 0 if the entire line is whitespace.
  var runes: seq[Rune] = @[]
  for r in text.runes:
    runes.add(r)

  if runes.len == 0:
    return 0

  # Scan backwards to find first non-whitespace character
  var lastNonSpace = runes.len - 1
  while lastNonSpace >= 0 and isWhitespace(runes[lastNonSpace]):
    dec lastNonSpace

  # Return the index after the last non-whitespace character
  result = lastNonSpace + 1
