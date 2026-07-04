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

## Unicode utilities for text editing
##
## This module provides utilities for handling Unicode text properly,
## including cursor positioning and character operations.

import std/[unicode, tables]
import pkg/celina

export buffer.runeWidth, buffer.displayWidth

proc foldZeroWidthRune*(buffer: var Buffer, x, y: int, r: Rune) =
  ## Merge a zero-width rune (combining mark, ZWJ, variation selector) into the
  ## base cell to the left of column `x`, so it renders on that grapheme rather
  ## than overwriting the next column. Callers advance the cursor per rune, so
  ## when a zero-width rune arrives `x` already sits past the base: a narrow
  ## base occupies `x-1`, a wide base its empty shadow at `x-1` and the lead at
  ## `x-2`. Rewrite the base via setCell so the wide-char shadow is preserved.
  ## No-op when no base cell precedes `x` (e.g. a leading combining mark).
  var bx = x - 1
  if bx < 0 or bx >= buffer.area.width or y < 0 or y >= buffer.area.height:
    return
  # Step left over a wide char's empty shadow cell onto its lead.
  if buffer[bx, y].isShadow and bx - 1 >= 0:
    dec bx
  let base = buffer[bx, y]
  if base.isEmpty:
    return
  buffer.setCell(bx, y, base.symbol & $r, base.width, base.style, base.hyperlink)

proc setRuneCell*(buffer: var Buffer, x, y: int, r: Rune, style: Style): int =
  ## Write a single rune at (x, y), returning its display width so callers can
  ## advance the cursor. Wide chars (width 2) get an empty continuation cell so
  ## celina's diff repaints the second column when the wide char is overwritten,
  ## avoiding ghost artifacts on popup close. Zero-width runes (combining marks,
  ## joiners, variation selectors) are folded into the preceding base cell and
  ## return 0 — writing them standalone would overwrite the following glyph.
  let w = runeWidth(r)
  if w == 0:
    foldZeroWidthRune(buffer, x, y, r)
    return 0
  buffer[x, y] = cell($r, style)
  if w == 2 and x + 1 < buffer.area.width:
    buffer[x + 1, y] = cell("", style)
  return w

type CursorPosCache* = object
  ## Cache for accelerating character-to-byte position conversions
  ## Dramatically improves performance for consecutive edits on long lines
  line*: int # Cached line number
  charPos*: int # Cached character position (Unicode character count)
  bytePos*: int # Cached byte position (UTF-8 byte offset)
  changeSeq*: int # Buffer change sequence number for invalidation

proc byteToCharPos*(text: string, bytePos: int): int =
  ## Convert byte position to character position (Unicode-aware)
  var currentByte = 0

  for rune in text.runes:
    if currentByte >= bytePos:
      break
    currentByte += rune.size
    result += 1

proc charToBytePos*(text: string, charPos: int): int =
  ## Convert character position to byte position (Unicode-aware)
  var currentChar = 0

  for rune in text.runes:
    if currentChar >= charPos:
      break
    result += rune.size
    currentChar += 1

proc getCharAtPos*(text: string, charPos: int): (Rune, int) =
  ## Get the Unicode character at the given character position
  ## Returns (rune, byte_size)
  var
    currentChar = 0
    bytePos = 0

  for rune in text.runes:
    if currentChar == charPos:
      return (rune, rune.size)
    bytePos += rune.size
    currentChar += 1

  # Return null rune if position is out of bounds
  (Rune(0), 0)

proc deleteCharAt*(text: string, charPos: int): string =
  ## Delete a Unicode character at the given character position
  let bytePos = charToBytePos(text, charPos)
  if bytePos >= text.len:
    return text

  let (_, size) = getCharAtPos(text, charPos)
  if size == 0:
    return text

  text[0 ..< bytePos] & text[bytePos + size ..^ 1]

proc displayWidthSubstr*(text: string, startChar: int, maxWidth: int): (int, int) =
  ## Calculate how many characters fit within maxWidth display columns
  ## Returns (charCount, actualWidth)
  var
    currentChar = 0
    currentWidth = 0

  for rune in text.runes:
    if currentChar < startChar:
      currentChar += 1
      continue

    let w = runeWidth(rune)
    if currentWidth + w > maxWidth:
      break

    currentWidth += w
    currentChar += 1

  return (currentChar - startChar, currentWidth)

proc displayWidthUpTo*(text: string, charPos: int): int =
  ## Calculate the display width from start to charPos (not including charPos)
  ## charPos is a character index (not byte position)
  var currentChar = 0

  for rune in text.runes:
    if currentChar >= charPos:
      break
    result += runeWidth(rune)
    currentChar += 1

proc truncateToWidthWithSuffix*(
    text: string, maxWidth: int, suffix: string = "..."
): string =
  ## Truncate `text` so the result (including `suffix`) fits within
  ## `maxWidth` display columns.  If the text already fits, it is returned
  ## unchanged.
  if maxWidth <= 0:
    return ""
  let suffixWidth = displayWidth(suffix)
  let textWidth = displayWidth(text)
  if textWidth <= maxWidth:
    return text
  if suffixWidth > maxWidth:
    return ""
  var currentWidth = 0
  for r in text.runes:
    let w = runeWidth(r)
    if currentWidth + w + suffixWidth > maxWidth:
      result.add(suffix)
      return
    currentWidth += w
    result.add($r)

proc charToBytePosCached*(
    text: string, charPos: int, cache: var CursorPosCache, lineNum: int, changeSeq: int
): int =
  ## Convert character position to byte position using cache for performance
  ##
  ## This function dramatically improves performance for consecutive edits by
  ## caching the last conversion and performing incremental scans.
  ##
  ## Performance:
  ##   - Cache hit (same position): O(1)
  ##   - Cache hit (forward movement): O(distance)
  ##   - Cache miss: O(charPos)

  # Bounds check
  if charPos <= 0:
    # Update cache for position 0
    cache.line = lineNum
    cache.charPos = 0
    cache.bytePos = 0
    cache.changeSeq = changeSeq
    return 0

  # Check if cache is valid for this line and buffer state
  if cache.line == lineNum and cache.changeSeq == changeSeq:
    # Cache HIT!

    if cache.charPos == charPos:
      # Perfect match - return immediately
      return cache.bytePos
    elif cache.charPos < charPos:
      # Forward movement (most common case)
      # Scan from cached position to target
      result = cache.bytePos
      var currentChar = cache.charPos
      var byteIdx = cache.bytePos

      while byteIdx < text.len and currentChar < charPos:
        let rune = text.runeAt(byteIdx)
        result += rune.size
        byteIdx += rune.size
        currentChar += 1

      # Update cache
      cache.charPos = charPos
      cache.bytePos = result
      return result
    else:
      # Backward movement
      # For now, fall back to full scan from start
      # (Backward incremental scan is complex due to UTF-8 variable width)
      result = charToBytePos(text, charPos)
      cache.charPos = charPos
      cache.bytePos = result
      return result

  # Cache MISS - perform full scan from start
  result = charToBytePos(text, charPos)

  # Update cache with new values
  cache.line = lineNum
  cache.charPos = charPos
  cache.bytePos = result
  cache.changeSeq = changeSeq

# Parenthesis pairs for auto-close/delete feature
const parenPairs* = {'(': ')', '[': ']', '{': '}', '"': '"', '\'': '\''}.toTable

proc isOpeningParen*(ch: char): bool =
  ## Check if a character is an opening parenthesis/bracket/quote
  ch in parenPairs

proc getClosingChar*(openChar: char): char =
  ## Get the closing character for an opening character
  ## Returns '\0' if the character is not an opening paren
  if openChar in parenPairs:
    return parenPairs[openChar]
  return '\0'

proc isMatchingPair*(openChar, closeChar: char): bool =
  ## Check if two characters form a matching parenthesis pair
  ## Returns true if openChar is an opening paren and closeChar is its matching closing paren
  if openChar in parenPairs:
    return parenPairs[openChar] == closeChar
  return false

proc isAdjacentPair*(line: string, pos: int): bool =
  ## Check if the character at pos and pos+1 form a matching parenthesis pair.
  ## pos is a character index (not byte position).
  ## Returns true if line[pos] is an opening paren and line[pos+1] is its match.
  if pos < 0 or pos + 1 >= line.runeLen:
    return false
  let openStr = $line.runeAtPos(pos)
  let closeStr = $line.runeAtPos(pos + 1)
  if openStr.len == 1 and closeStr.len == 1:
    return isMatchingPair(openStr[0], closeStr[0])
  return false

# Bracket matching functions for % command
proc isOpenBracket*(r: Rune): bool =
  ## Check if a rune is an opening bracket (for % command)
  ## Note: Does not include quotes (", ') unlike isOpeningParen
  let ch = r.int32
  ch == ord('(') or ch == ord('{') or ch == ord('[')

proc isCloseBracket*(r: Rune): bool =
  ## Check if a rune is a closing bracket (for % command)
  ## Note: Does not include quotes (", ') unlike closing parens
  let ch = r.int32
  ch == ord(')') or ch == ord('}') or ch == ord(']')

proc isBracket*(r: Rune): bool =
  ## Check if a rune is any bracket (opening or closing)
  r.isOpenBracket or r.isCloseBracket

proc correspondingCloseBracket*(r: Rune): Rune =
  ## Get the corresponding closing bracket for an opening bracket
  let ch = r.int32
  if ch == ord('('):
    Rune(ord(')'))
  elif ch == ord('{'):
    Rune(ord('}'))
  elif ch == ord('['):
    Rune(ord(']'))
  else:
    r # Return same rune if not an opening bracket

proc correspondingOpenBracket*(r: Rune): Rune =
  ## Get the corresponding opening bracket for a closing bracket
  let ch = r.int32
  if ch == ord(')'):
    Rune(ord('('))
  elif ch == ord('}'):
    Rune(ord('{'))
  elif ch == ord(']'):
    Rune(ord('['))
  else:
    r # Return same rune if not a closing bracket

proc isAdjacentBracketPair*(line: string, pos: int): bool =
  ## Check if line[pos] is an opening bracket () [] {} and line[pos+1] is its
  ## matching closing bracket. Excludes quotes (", '), unlike isAdjacentPair.
  ## pos is a character index (not byte position).
  isAdjacentPair(line, pos) and line.runeAtPos(pos).isOpenBracket

proc findMatchingCloseOnLine*(line: string, openCol: int): int =
  ## Find the matching closing bracket for an opening bracket at openCol.
  ## Uses nesting-aware matching. Only searches within the same line.
  ## Only handles (), [], {} (not quotes).
  ## Returns -1 if no match found.
  let openRune = line.runeAtPos(openCol)
  if not isOpenBracket(openRune):
    return -1
  let closeRune = correspondingCloseBracket(openRune)
  var depth = 1
  for col in (openCol + 1) ..< line.runeLen:
    let ch = line.runeAtPos(col)
    if ch == openRune:
      depth += 1
    elif ch == closeRune:
      depth -= 1
      if depth == 0:
        return col
  return -1

proc utf16OffsetToRune*(
    line: string, utf16Offset: int
): tuple[runeIdx: int, utf16Walked: int] {.inline.} =
  ## Convert a UTF-16 code-unit offset into a rune index. Returns the rune
  ## index clamped to the line's rune count and the UTF-16 units actually
  ## walked. `utf16Walked < utf16Offset` signals that the target position
  ## lies past the line's end -- callers that need to distribute the
  ## remainder over subsequent rows (multi-line tokens) must add the
  ## overflow themselves.
  if utf16Offset <= 0 or line.len == 0:
    return (0, 0)
  var utf16Count = 0
  var runeIdx = 0
  for rune in line.runes:
    if utf16Count >= utf16Offset:
      break
    if rune.int >= 0x10000:
      utf16Count += 2
    else:
      utf16Count += 1
    inc runeIdx
  return (runeIdx, utf16Count)

proc utf16ToRuneIndex*(line: string, utf16Offset: int): int {.inline.} =
  ## Convert a UTF-16 code-unit offset into a rune index (clamped to the
  ## line's rune count). Thin wrapper over `utf16OffsetToRune` for callers
  ## that don't need the walked count.
  utf16OffsetToRune(line, utf16Offset).runeIdx

proc findMatchingOpenOnLine*(line: string, closeCol: int): int =
  ## Find the matching opening bracket for a closing bracket at closeCol.
  ## Uses nesting-aware matching. Only searches within the same line.
  ## Only handles (), [], {} (not quotes).
  ## Returns -1 if no match found.
  let closeRune = line.runeAtPos(closeCol)
  if not isCloseBracket(closeRune):
    return -1
  let openRune = correspondingOpenBracket(closeRune)
  var depth = 1
  for col in countdown(closeCol - 1, 0):
    let ch = line.runeAtPos(col)
    if ch == closeRune:
      depth += 1
    elif ch == openRune:
      depth -= 1
      if depth == 0:
        return col
  return -1
