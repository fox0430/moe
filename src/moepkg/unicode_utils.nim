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

import std/[options, strutils, unicode, tables]
import pkg/celina

export buffer.runeWidth, buffer.displayWidth, buffer.foldZeroWidthRune

proc isC0Control*(r: Rune): bool =
  ## C0 control character (0x00..0x1F) or DEL (0x7F). Must be substituted
  ## before reaching a terminal cell (terminal injection).
  int(r) < 0x20 or int(r) == 0x7F

const InvalidByteRuneBase = 0xDC00
  ## Undecodable bytes are carried as U+DC80..U+DCFF -- lone low surrogates,
  ## so the byte stays recoverable and distinct from a U+FFFD the file holds
  ## (like Python's `surrogateescape`). Never encode such a rune into a string
  ## leaving the editor: it would emit invalid UTF-8.

proc invalidByteRune*(b: uint8): Rune =
  ## The rune standing for a byte that does not decode.
  Rune(InvalidByteRuneBase + b.int)

proc isInvalidByteRune*(r: Rune): bool =
  ## Whether `r` stands for a byte that does not decode rather than a character.
  r.int >= InvalidByteRuneBase + 0x80 and r.int <= InvalidByteRuneBase + 0xFF

proc invalidByteValue*(r: Rune): uint8 =
  ## The byte `r` stands for. Only meaningful for `isInvalidByteRune`.
  uint8(r.int - InvalidByteRuneBase)

proc invalidByteText*(r: Rune): string =
  ## How an undecodable byte is drawn: `<e3>`, the way vim shows it.
  "<" & toHex(r.invalidByteValue.int, 2).toLowerAscii & ">"

proc charWidth*(r: Rune): int =
  ## Display cells the character occupies. Undecodable bytes are drawn as
  ## `<e3>`; everything else defers to `runeWidth`. Every walk that measures
  ## buffer text must use this, or it disagrees with the renderer.
  if r.isInvalidByteRune:
    invalidByteText(r).len
  else:
    runeWidth(r)

proc sanitizeCellRune*(r: Rune): Rune =
  ## Substitute C0 controls and DEL with a space so they never reach a
  ## terminal cell as raw control sequences, and undecodable bytes with the
  ## replacement character (a lone surrogate would emit invalid UTF-8).
  if isC0Control(r):
    ' '.Rune
  elif isInvalidByteRune(r):
    Rune(0xFFFD)
  else:
    r

proc sanitizeForDisplay*(s: string): string =
  ## Replace C0 controls and DEL with spaces so metadata (file names, branch
  ## names, `setupText` interpolations) cannot inject terminal sequences via
  ## the status/tab lines. Mirrors `sanitizeCellRune` so `displayWidth` stays
  ## consistent with the rendered cells.
  result = newStringOfCap(s.len)
  for r in s.runes:
    result.add($sanitizeCellRune(r))

proc setRuneCell*(buffer: var Buffer, x, y: int, r: Rune, style: Style): int =
  ## Write a single rune at (x, y), returning its display width so callers can
  ## advance the cursor. Wide chars (width 2) get an empty continuation cell so
  ## celina's diff repaints it on overwrite; zero-width runes are folded into
  ## the preceding base cell. C0 controls and DEL are substituted with a space.
  let rune = sanitizeCellRune(r)
  let w = charWidth(rune)
  if w == 0:
    foldZeroWidthRune(buffer, x, y, rune)
    return 0
  buffer[x, y] = cell($rune, style)
  if w == 2 and x + 1 < buffer.area.width:
    buffer[x + 1, y] = cell("", style)
  return w

proc leadByteLen(b: uint8): int =
  ## Bytes the character led by `b` needs, or 0 when `b` cannot lead one.
  ## Only C2..F4 lead: C0/C1 start overlong forms and F5..FF encode nothing
  ## (the five- and six-byte forms left UTF-8 in RFC 3629).
  if b < 0x80'u8:
    1
  elif b >= 0xC2'u8 and b <= 0xDF'u8:
    2
  elif b >= 0xE0'u8 and b <= 0xEF'u8:
    3
  elif b >= 0xF0'u8 and b <= 0xF4'u8:
    4
  else:
    0

proc runeSizeAt*(text: string, bytePos: int): int =
  ## Bytes the character starting at `bytePos` occupies, or 1 when the bytes
  ## there are not a character at all. A position outside the text yields 0.
  ##
  ## Well-formedness follows Unicode Table 3-7, not the lead byte's advertised
  ## length alone: overlong forms, surrogates, and code points above U+10FFFF
  ## have the continuation-byte shape but encode nothing, so each byte stands
  ## alone and is shown as the byte it is. The rule reads only the character's
  ## own bytes, except where a lead byte still short of its advertised length
  ## counts as one until the bytes that complete it are written right after it
  ## (the seam problem; `mayAbsorbAtSeam`).
  if bytePos < 0 or bytePos >= text.len:
    return 0

  let b0 = text[bytePos].uint8
  if b0 < 0x80'u8:
    return 1

  let size = leadByteLen(b0)
  if size <= 1 or bytePos + size > text.len:
    return 1

  # The byte after the lead carries the range restrictions that rule out
  # overlongs (E0, F0), surrogates (ED) and anything past U+10FFFF (F4).
  let
    b1 = text[bytePos + 1].uint8
    lo =
      case b0
      of 0xE0'u8: 0xA0'u8
      of 0xF0'u8: 0x90'u8
      else: 0x80'u8
    hi =
      case b0
      of 0xED'u8: 0x9F'u8
      of 0xF4'u8: 0x8F'u8
      else: 0xBF'u8
  if b1 < lo or b1 > hi:
    return 1

  # Every byte after that is an unrestricted continuation byte.
  for i in 2 ..< size:
    if (text[bytePos + i].uint8 and 0xC0'u8) != 0x80'u8:
      return 1

  size

proc charAtByte*(text: string, bytePos: int): (Rune, int) =
  ## The character starting at `bytePos` as (rune, byte size). A byte that
  ## stands alone without decoding yields its `invalidByteRune`; `runeAt`
  ## would instead build a character out of the bytes that follow.
  ##
  ## `bytePos` must be inside the text: a caller stepping by the returned size
  ## would spin forever on a zero.
  let size = text.runeSizeAt(bytePos)
  doAssert size > 0, "charAtByte out of range: " & $bytePos & " of " & $text.len
  if size == 1 and text[bytePos].uint8 >= 0x80'u8:
    return (invalidByteRune(text[bytePos].uint8), 1)
  var r: Rune
  var next = bytePos
  fastRuneAt(text, next, r, true)
  (r, size)

iterator chars*(text: string): (Rune, int) =
  ## Every character of `text` as (rune, byte size), stepped with `runeSizeAt`.
  ## `std/unicode`'s `runes` steps by a different rule and would disagree with
  ## every column index in the editor.
  var i = 0
  while i < text.len:
    let (r, size) = text.charAtByte(i)
    yield (r, size)
    i += size

proc toCharRunes*(text: string): seq[Rune] =
  ## `text` as one Rune per character in the same model `charLen` counts, so an
  ## index into the result is a buffer column. `toRunes` folds broken bytes
  ## into a following character and yields indices in a different column space.
  for (r, _) in text.chars:
    result.add(r)

proc charLen*(text: string): int =
  ## Character length (not byte length), stepped with `runeSizeAt` so a column
  ## index addresses the same cell here, in the renderer and in `charSubStr`.
  ## `runeLen` disagrees on a lead byte that overruns the string.
  var i = 0
  while i < text.len:
    i += text.runeSizeAt(i)
    inc result

proc isContinuationByte*(c: char): bool =
  ## A byte that can only appear inside a character, never start one.
  (c.uint8 and 0xC0'u8) == 0x80'u8

proc mayAbsorbAtSeam*(text: string, endByte: int): bool =
  ## Whether `text[0 ..< endByte]` ends in a lead byte still short of the bytes
  ## it advertised, with only continuation bytes since -- the one state that
  ## more continuation bytes written at `endByte` would complete. Reading at
  ## most three bytes back is enough: a character is four bytes at the most.
  ## An `endByte` past the text is answered against the text that is there.
  ## Errs towards yes; the caller only pays for a re-measure it did not need.
  let last = min(endByte, text.len)
  for i in countdown(last - 1, max(0, last - 3)):
    if text[i].isContinuationByte:
      continue
    let need = leadByteLen(text[i].uint8)
    return need > 1 and need > last - i
  false

proc mayAbsorbAtSeam*(text: string): bool =
  ## Whether appending to `text` can change how its own bytes count.
  text.mayAbsorbAtSeam(text.len)

proc absorbsAtSeam*(before: string, endByte: int, after: string): bool =
  ## Whether writing `after` at `endByte` makes the bytes on the two sides stop
  ## counting apart. It takes both a lead byte left waiting on one side and
  ## continuation bytes to feed it on the other.
  before.mayAbsorbAtSeam(endByte) and after.len > 0 and after[0].isContinuationByte

proc byteToCharPos*(text: string, bytePos: int): int =
  ## Convert byte position to character position (Unicode-aware)
  var currentByte = 0

  while currentByte < text.len and currentByte < bytePos:
    currentByte += text.runeSizeAt(currentByte)
    result += 1

proc charToBytePos*(text: string, charPos: int): int =
  ## Convert character position to byte position (Unicode-aware)
  var currentChar = 0

  while result < text.len and currentChar < charPos:
    result += text.runeSizeAt(result)
    currentChar += 1

proc charSubStr*(text: string, startChar: int, charCount: int = int.high): string =
  ## Byte-exact substring of `charCount` characters starting at character index
  ## `startChar`, or the rest of the text when `charCount` is omitted. A start
  ## past the end, or a non-positive count, yields "".
  ##
  ## Walks with `runeSizeAt`, so it counts characters the way `charLen` and the
  ## renderer do; `runeSubStr` overruns a truncated tail. Negative indices are
  ## not supported. The result is sliced out of `text`, so a byte that does not
  ## decode keeps the bytes it had -- re-encoding it would widen it.
  if startChar < 0 or charCount <= 0:
    return ""

  let startByte = text.charToBytePos(startChar)
  var endByte = text.len
  # A count at least as large as the remaining byte span cannot end before the
  # text does, so skip the walk.
  if charCount < text.len - startByte:
    endByte = startByte
    var taken = 0
    while endByte < text.len and taken < charCount:
      endByte += text.runeSizeAt(endByte)
      inc taken

  text[startByte ..< endByte]

proc asciiChar*(s: string): Option[char] =
  ## Single ASCII char in `s`, or none if empty, multi-char, or multi-byte.
  ## Avoids `s[0]` returning a lead byte that accidentally passes range checks.
  ## NUL is valid and distinct from none.
  if s.len == 1 and s[0] < '\x80':
    some(s[0])
  else:
    none(char)

proc toggleAsciiCase*(c: char): char =
  ## Upper to lower and lower to upper; anything else unchanged.
  if c.isUpperAscii:
    c.toLowerAscii
  elif c.isLowerAscii:
    c.toUpperAscii
  else:
    c

proc toggleAsciiCase*(s: string): string =
  ## `toggleAsciiCase` over every byte. Safe byte by byte: every byte of a
  ## multi-byte character is 0x80 and up, so a byte with a case is always a
  ## character of its own.
  result = newStringOfCap(s.len)
  for c in s:
    result.add(c.toggleAsciiCase)

proc getCharAtPos*(text: string, charPos: int): (Rune, int) =
  ## The character at the given character position as (rune, byte size), in the
  ## same column model `charLen` and `charSubStr` count in.
  ## Returns (Rune(0), 0) when the position is out of bounds.
  var currentChar = 0
  for (rune, size) in text.chars:
    if currentChar == charPos:
      return (rune, size)
    currentChar += 1

  (Rune(0), 0)

proc deleteCharAt*(text: string, charPos: int): string =
  ## Delete a Unicode character at the given character position
  if charPos < 0:
    return text

  let bytePos = charToBytePos(text, charPos)
  if bytePos >= text.len:
    return text

  let size = text.runeSizeAt(bytePos)
  text[0 ..< bytePos] & text[bytePos + size ..^ 1]

proc displayWidthSubstr*(text: string, startChar: int, maxWidth: int): (int, int) =
  ## Calculate how many characters fit within maxWidth display columns
  ## Returns (charCount, actualWidth)
  var
    currentChar = 0
    currentWidth = 0

  for (rune, _) in text.chars:
    if currentChar < startChar:
      currentChar += 1
      continue

    let w = charWidth(rune)
    if currentWidth + w > maxWidth:
      break

    currentWidth += w
    currentChar += 1

  return (currentChar - startChar, currentWidth)

proc displayWidthUpTo*(text: string, charPos: int): int =
  ## Calculate the display width from start to charPos (not including charPos)
  ## charPos is a character index (not byte position)
  var currentChar = 0

  for (rune, _) in text.chars:
    if currentChar >= charPos:
      break
    result += charWidth(rune)
    currentChar += 1

proc truncateToCharsWithSuffix*(
    text: string, maxChars: int, suffix: string = "..."
): string =
  ## Truncate `text` to `maxChars` characters, appending `suffix` when anything
  ## was cut. Walks no further than `maxChars` characters (buffer lines can be
  ## megabytes). `charSubStr` returns the whole string when it fits, so a
  ## shorter result is itself the "was cut" answer. A budget of nothing yields
  ## nothing, like the display-width sibling.
  if maxChars <= 0:
    return ""
  let kept = text.charSubStr(0, maxChars)
  if kept.len < text.len:
    kept & suffix
  else:
    text

proc charDisplayWidth*(text: string): int =
  ## Display cells `text` occupies, stepped and measured the way the renderer
  ## draws it. `displayWidth` steps with `std/unicode` rules and knows nothing
  ## of the four cells an undecodable byte takes.
  for (r, _) in text.chars:
    result += r.charWidth

proc alignLeftDisplay*(text: string, width: int): string =
  ## Pad `text` with spaces to `width` display columns, unlike the byte-counting
  ## `strutils.alignLeft`.
  let w = charDisplayWidth(text)
  if w >= width:
    text
  else:
    text & ' '.repeat(width - w)

proc charStartAtWidth*(text: string, minWidth: int): (int, int) =
  ## The first character position whose prefix reaches `minWidth` display
  ## columns, and that prefix's width. Wide characters are never split, so the
  ## width can overshoot `minWidth`; a `minWidth` past the end returns the whole
  ## text and a width short of it.
  var
    charPos = 0
    width = 0
  for (r, _) in text.chars:
    if width >= minWidth:
      break
    width += r.charWidth
    charPos += 1
  (charPos, width)

proc setCharString*(buffer: var Buffer, x, y: int, text: string, style: Style): int =
  ## Draw `text` in the model `charLen` and `charDisplayWidth` use, giving an
  ## undecodable byte its own `<f0>` columns unlike celina's `setString`.
  ## Returns the next free column; drawing stops at the buffer's right edge.
  result = x
  for (r, _) in text.chars:
    if result >= buffer.area.width:
      break
    if r.isInvalidByteRune:
      for ch in invalidByteText(r):
        if result >= buffer.area.width:
          break
        buffer[result, y] = cell($ch, style)
        inc result
    else:
      # A lead without its continuation cell spills past the right edge.
      if sanitizeCellRune(r).charWidth == 2 and result + 2 > buffer.area.width:
        break
      result += setRuneCell(buffer, result, y, r, style)

proc truncateToWidthWithSuffix*(
    text: string, maxWidth: int, suffix: string = "..."
): string =
  ## Truncate `text` so the result (including `suffix`) fits within
  ## `maxWidth` display columns. If the text already fits, it is returned
  ## unchanged. The kept part is sliced out of `text` rather than re-encoded
  ## rune by rune, so a byte that does not decode keeps the bytes it had.
  if maxWidth <= 0:
    return ""
  let suffixWidth = charDisplayWidth(suffix)
  if charDisplayWidth(text) <= maxWidth:
    return text
  if suffixWidth > maxWidth:
    return ""
  var
    currentWidth = 0
    byteOff = 0
  while byteOff < text.len:
    # One walk decides both the width and the step, so the cut lands on a
    # character boundary the renderer agrees with.
    let (r, size) = text.charAtByte(byteOff)
    let w = r.charWidth
    if currentWidth + w + suffixWidth > maxWidth:
      return text[0 ..< byteOff] & suffix
    currentWidth += w
    byteOff += size
  text

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

proc singleBytePairAt(line: string, pos: int): (char, char) =
  ## The characters at `pos` and `pos + 1` when both are single-byte, else
  ## NULs. One walk to `pos`, where decoding each character separately would
  ## rescan the line twice.
  if pos < 0:
    return ('\0', '\0')
  let openByte = line.charToBytePos(pos)
  if openByte >= line.len or line.runeSizeAt(openByte) != 1:
    return ('\0', '\0')
  let closeByte = openByte + 1
  if closeByte >= line.len or line.runeSizeAt(closeByte) != 1:
    return ('\0', '\0')
  (line[openByte], line[closeByte])

proc isAdjacentPair*(line: string, pos: int): bool =
  ## Check if the character at pos and pos+1 form a matching parenthesis pair.
  ## pos is a character index (not byte position).
  ## Returns true if line[pos] is an opening paren and line[pos+1] is its match.
  let (openChar, closeChar) = line.singleBytePairAt(pos)
  openChar != '\0' and isMatchingPair(openChar, closeChar)

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
  line.isAdjacentPair(pos) and Rune(ord(line.singleBytePairAt(pos)[0])).isOpenBracket

proc utf16OffsetToChar*(
    line: string, utf16Offset: int
): tuple[charIdx: int, utf16Walked: int] {.inline.} =
  ## Convert a UTF-16 code-unit offset into a character index in the same
  ## column space `charLen` and the renderer count in. Returns the index
  ## clamped to the line's character count and the UTF-16 units actually
  ## walked; `utf16Walked < utf16Offset` signals the target lies past the
  ## line's end (callers distribute the remainder over subsequent rows).
  if utf16Offset <= 0 or line.len == 0:
    return (0, 0)
  var utf16Count = 0
  var charIdx = 0
  for (rune, _) in line.chars:
    if utf16Count >= utf16Offset:
      break
    if rune.int >= 0x10000:
      utf16Count += 2
    else:
      utf16Count += 1
    inc charIdx
  return (charIdx, utf16Count)

proc utf16ToCharIndex*(line: string, utf16Offset: int): int {.inline.} =
  ## Convert a UTF-16 code-unit offset into a character index (clamped to the
  ## line's character count). Thin wrapper over `utf16OffsetToChar` for callers
  ## that don't need the walked count.
  utf16OffsetToChar(line, utf16Offset).charIdx
