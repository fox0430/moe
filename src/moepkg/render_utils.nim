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

import pkg/celina
import std/unicode

import types, buffer, unicode_utils, color

# Rendering constants
const
  TAB_CHAR* = 0x09.Rune ## Tab character constant
  FULLWIDTH_SPACE* = 0x3000.Rune ## Full-width space character (U+3000)

  TabLineHeight* = 1 ## Height of tab line
  StatusLineReserve* = 1
  CommandLineReserve* = 1
  StatusAndCommandReserve* = 2

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

proc cursorCharStyle*(): Style =
  ## Get cursor character style (uses default with custom foreground)
  let colorPair = getThemeColor(EditorColorPairIndex.default)
  Style(
    fg: ColorValue(kind: Rgb, rgb: RgbColor(r: 180, g: 180, b: 180)),
    bg: colorPair.background.rgb.toColorValue,
    modifiers: {},
  )

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

proc calculateWrapCount*(lineCharLen: int, maxWidth: int): int =
  ## Calculate how many screen lines a logical line will take when wrapped
  if lineCharLen == 0:
    1
  else:
    ((lineCharLen - 1) div maxWidth) + 1

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
  if not showLineNumber:
    return 0
  if buffer.len > 0:
    len($buffer.len) + LineNumberSpacer
  else:
    0

proc findMaxBottomY*(windows: seq[EditorWindow]): int =
  ## Find the maximum bottom Y coordinate among all windows
  result = 0
  for window in windows:
    let bottomY = window.viewport.y + window.viewport.height
    if bottomY > result:
      result = bottomY

proc calculateWindowStatusLineY*(window: EditorWindow, isBottomWindow: bool): int =
  ## Calculate Y position for window status line
  ## Bottom windows: place above command line (height - 2)
  ## Non-bottom windows: place at window bottom (height - 1)
  if isBottomWindow:
    window.viewport.y + window.viewport.height - 2
  else:
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
