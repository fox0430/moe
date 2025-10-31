#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

# Re-export runeWidth from celina's buffer module
# This provides Unicode-standard width detection for all characters including emoji
export buffer.runeWidth

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

proc displayWidth*(text: string): int =
  ## Calculate the display width of a string
  ## Accounts for East Asian Wide/Fullwidth characters (width 2)
  for rune in text.runes:
    result += runeWidth(rune)

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
