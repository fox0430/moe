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

import std/[options, unicode, tables]

import celina_backend as celina

import types/editor_types, color, render_utils, unicode_utils

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
  for (rune, _) in text.chars:
    if currentChar >= bufferCol:
      break
    if currentChar >= startCol:
      if rune == TAB_CHAR:
        result += tabAdvance(result, tabStop)
      else:
        result += charWidth(rune)
    currentChar.inc

proc analyzeIndentation*(lineText: string): IndentInfo =
  ## Analyze a line once to determine indentation properties
  ## Returns cached information to avoid repeated line scanning (O(n) instead of O(n²))
  result.leadingWhitespaceEnd = -1
  result.hasContent = false

  var charIdx = 0
  for (rune, _) in lineText.chars:
    if rune != ' '.Rune and rune != TAB_CHAR:
      # Found first non-whitespace character
      result.leadingWhitespaceEnd = charIdx - 1
      result.hasContent = true
      break
    charIdx += 1

proc isPositionInDocumentHighlight*(
    state: EditorState, pos: BufferPosition
): Option[int] =
  ## Check if position is within any document highlight range
  ## Returns the highlight kind (1=Text, 2=Read, 3=Write) if found, none otherwise
  ## Uses O(1) line lookup + O(m) column search where m is highlights on that line
  if not state.showDocumentHighlight or not state.lspCache.documentHighlightCache.isValid:
    return none(int)

  # O(1) lookup by line
  let items =
    state.lspCache.documentHighlightCache.itemsByLine.getOrDefault(pos.line, @[])
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
