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

import std/[unicode, sequtils, strutils, strformat, os, times, oids, deques]

import pkg/unicodedb/[properties, widths]

export unicode

type
  Runes* = seq[Rune]

  CharacterEncoding* = enum
    utf8
    utf16
    utf16Be
    utf16Le
    utf32
    utf32Be
    utf32Le
    unknown

const
  LetterCharacter* = ctgLu + ctgLl + ctgLt + ctgLm + ctgLo + ctgNl
  CombiningCharacter* = ctgMn + ctgMc
  DecimalDigitCharacter* = ctgNd
  ConnectingCharacter* = ctgPc
  FormattingCharacter* = ctgCf

  WhitespaceRune* =
    [Rune(' '), Rune('\t'), Rune('\v'), Rune('\r'), Rune('\l'), Rune('\f')]

  DigitsRune* = [
    Rune('0'),
    Rune('1'),
    Rune('2'),
    Rune('3'),
    Rune('4'),
    Rune('5'),
    Rune('6'),
    Rune('7'),
    Rune('8'),
    Rune('9'),
  ]

proc `$`*(encoding: CharacterEncoding): string =
  case encoding
  of CharacterEncoding.utf8:
    return "UTF-8"
  of CharacterEncoding.utf16:
    return "UTF-16"
  of CharacterEncoding.utf16Be:
    return "UTF-16BE"
  of CharacterEncoding.utf16Le:
    return "UTF-16LE"
  of CharacterEncoding.utf32:
    return "UTF-32"
  of CharacterEncoding.utf32Be:
    return "UTF-32BE"
  of CharacterEncoding.utf32Le:
    return "UTF-32LE"
  of CharacterEncoding.unknown:
    return "UNKNOWN"

proc validateUtf16Be(s: string): bool =
  if (s.len mod 2) != 0:
    return false

  var i = 0
  proc advance(): int =
    result = 256 * ord(s[i]) + ord(s[i + 1])
    i += 2

  while i < s.len:
    let curr = advance()
    if curr <= 0xD7FF or (0xE000 <= curr and curr <= 0xFFFF):
      continue
    let next = advance()
    if (not (0xD800 <= curr and curr <= 0xDBFF)) or
        (not (0xDC00 <= next and next <= 0xDFFF)):
      return false
    let
      higher = (curr and 0b11_1111_1111) shl 10
      lower = (next and 0b11_1111_1111)
      point = higher or lower
    if point < 0x10000:
      return false

  return true

proc validateUtf16Le(s: string): bool =
  if (s.len mod 2) != 0:
    return false

  var i = 0
  proc advance(): int =
    result = ord(s[i]) + 256 * ord(s[i + 1])
    i += 2

  while i < s.len:
    let curr = advance()
    if curr <= 0xD7FF or (0xE000 <= curr and curr <= 0xFFFF):
      continue
    let next = advance()
    if (not (0xD800 <= curr and curr <= 0xDBFF)) or
        (not (0xDC00 <= next and next <= 0xDFFF)):
      return false
    let
      higher = (curr and 0b11_1111_1111) shl 10
      lower = (next and 0b11_1111_1111)
      point = higher or lower
    if point < 0x10000:
      return false

  return true

proc validateUtf32Be(s: string): bool =
  if (s.len mod 4) != 0:
    return false

  var i = 0
  proc advance(): uint32 =
    result =
      0x1000000'u32 * uint32(ord(s[i])) + 0x10000'u32 * uint32(ord(s[i + 1])) +
      0x100'u32 * uint32(ord(s[i + 2])) + uint32(ord(s[i + 3]))
    i += 4

  while i < s.len:
    let curr = advance()
    if curr > 0x10FFFF'u32:
      return false

  return true

proc validateUtf32Le(s: string): bool =
  if (s.len mod 4) != 0:
    return false

  var i = 0
  proc advance(): uint32 =
    result =
      uint32(ord(s[i])) + 0x100'u32 * uint32(ord(s[i + 1])) +
      0x10000'u32 * uint32(ord(s[i + 2])) + 0x1000000'u32 * uint32(ord(s[i + 3]))
    i += 4

  while i < s.len:
    let curr = advance()
    if curr > 0x10FFFF'u32:
      return false

  return true

proc count0000(s: string): int =
  var i = 0
  while i + 1 < s.len:
    if ord(s[i]) == 0x00 and ord(s[i + 1]) == 0x00:
      inc(result)
    i += 2

proc detectCharacterEncoding*(s: string): CharacterEncoding =
  ## Guess the character encoding form of `s`.
  ## In currently, only the Unicode format is supported.
  ## Returns `CharacterEncoding.utf8` if only ASCII characters are included.
  ## Returns `CharacterEncoding.unknown` if encoding format is unknown.

  # Check UTF-8 BOM
  if s.len >= 3 and s[0 .. 2] == "\xEF\xBB\xBF":
    return CharacterEncoding.utf8

  if s.len >= 4:
    # Check UTF-32 BOM
    if s[0 .. 3] == "\x00\x00\xFE\xFF" or s[0 .. 3] == "\xFF\xFE\x00\x00":
      return CharacterEncoding.utf32

    # Check UTF-16 BOM
    if s[0 .. 1] == "\xFE\xFF" or s[0 .. 1] == "\xFF\xFE":
      return CharacterEncoding.utf16

  if s.validateUtf8 == -1:
    return CharacterEncoding.utf8

  var validEncodings: seq[CharacterEncoding]
  if s.validateUtf16Be:
    validEncodings.add(CharacterEncoding.utf16Be)
  if s.validateUtf16Le:
    validEncodings.add(CharacterEncoding.utf16Le)
  if s.validateUtf32Be:
    validEncodings.add(CharacterEncoding.utf32Be)
  if s.validateUtf32Le:
    validEncodings.add(CharacterEncoding.utf32Le)

  let threshold = (s.len / 2) * (2 / 5)
  if float(count0000(s)) >= threshold:
    # If there are too many 0x000, assume it is not UTF-16.
    if validEncodings.contains(CharacterEncoding.utf16Be):
      validEncodings.delete(validEncodings.find(CharacterEncoding.utf16Be))
    if validEncodings.contains(CharacterEncoding.utf16Le):
      validEncodings.delete(validEncodings.find(CharacterEncoding.utf16Le))

  if validEncodings.len == 1:
    return validEncodings[0]

  return CharacterEncoding.unknown

proc toRune*(c: char): Rune {.inline.} =
  doAssert(ord(c) <= 127)
  Rune(c)

proc toRune*(x: int): Rune {.inline.} =
  Rune(x)

proc `==`*(c: Rune, x: int): bool {.inline.} =
  c == toRune(x)

proc `==`*(c: Rune, x: char): bool {.inline.} =
  c == toRune(x)

proc ru*(c: char): Rune {.inline.} =
  toRune(c)

proc ru*(s: string): Runes {.inline.} =
  s.toRunes

proc ru*(array: seq[string]): Runes =
  for s in array:
    result.add s.toRunes

proc canConvertToChar*(c: Rune): bool {.inline.} =
  return ($c).len == 1

proc toChar*(c: Rune): char {.inline.} =
  doAssert(canConvertToChar(c), "Failed to convert Rune to char")
  return ($c)[0]

proc width*(c: Rune): int =
  const Tab = Rune('\t')
  if int(c) > 0x10FFFF:
    return 1
  if c == Tab:
    return 4
  case c.unicodeWidth
  of UnicodeWidth.uwdtNarrow, UnicodeWidth.uwdtHalf, UnicodeWidth.uwdtAmbiguous,
      UnicodeWidth.uwdtNeutral:
    1
  else:
    2

proc width*(runes: Runes): int {.inline.} =
  for c in runes:
    result += width(c)

proc numberOfBytes*(firstByte: char): int =
  if (int(firstByte) shr 7) == 0b0:
    return 1
  if (int(firstByte) shr 5) == 0b110:
    return 2
  if (int(firstByte) shr 4) == 0b1110:
    return 3
  if (int(firstByte) shr 3) == 0b11110:
    return 4
  doAssert(false, "Invalid UTF-8 first byte.")

proc isDigit*(r: Rune): bool =
  return r in DigitsRune

proc isDigit*(runes: Runes): bool {.inline.} =
  all(runes, isDigit)

proc isSpace*(r: Rune): bool {.inline.} =
  return r in WhitespaceRune

proc isPunct*(r: Rune): bool =
  return
    r in [
      ru '!',
      ru '"',
      ru '#',
      ru '$',
      ru '%',
      ru '\'',
      ru '(',
      ru ')',
      ru '*',
      ru '+',
      ru ',',
      ru '-',
      ru '.',
      ru '/',
      ru ':',
      ru ';',
      ru '<',
      ru '=',
      ru '>',
      ru '?',
      ru '@',
      ru '[',
      ru '\\',
      ru ']',
      ru '^',
      ru '_',
      ru '`',
      ru '{',
      ru '=',
      ru '}',
    ]

proc isNewline*(r: Rune): bool {.inline.} =
  r in [ru '\n', ru '\r']

proc countRepeat*(runes: Runes, runeArray: openArray[Rune], start: int): int =
  for i in start ..< runes.len:
    if not (runes[i] in runeArray):
      break
    else:
      result.inc

proc toRunes*(r: Runes): Runes {.inline.} =
  r

proc toRunes*(num: int): Runes {.inline.} =
  toRunes($num)

proc toRunes*(dateTime: DateTime): Runes {.inline.} =
  toRunes($dateTime)

proc toRunes*(oid: Oid): Runes {.inline.} =
  toRunes($oid)

proc toRunes*(s: seq[string]): Runes {.inline.} =
  for l in s:
    result.add l.toRunes

proc toRunes*(r: Rune): Runes {.inline.} =
  @[r]

proc toRunes*(r: seq[Runes]): Runes {.inline.} =
  for i, l in r:
    result.add l
    if i < r.high:
      result.add ru '\n'

proc toRunes*(a: openArray[char]): Runes {.inline.} =
  for i, c in a:
    result.add c.toRune

proc toSeqRunes*(s: seq[string]): seq[Runes] {.inline.} =
  for l in s:
    result.add l.toRunes

proc toSeqRunes*(r: Deque[Runes]): seq[Runes] {.inline.} =
  for l in r:
    result.add l

proc startsWith*(r: Runes, prefix: Rune): bool {.inline.} =
  result = r.len > 0 and r[0] == prefix

proc startsWith*(r, prefix: Runes): bool =
  let prefixLen = prefix.len
  let sLen = r.len
  var i = 0
  while true:
    if i >= prefixLen:
      return true
    if i >= sLen or r[i] != prefix[i]:
      return false
    inc(i)

proc endsWith*(r: Runes, suffix: Rune): bool {.inline.} =
  result = r.len > 0 and r[r.high] == suffix

proc endsWith*(r: Runes, suffix: Runes): bool =
  let suffixLen = suffix.len
  let sLen = r.len
  var i = 0
  var j = sLen - suffixLen
  while i + j >= 0 and i + j < sLen:
    if r[i + j] != suffix[i]:
      return false
    inc(i)
  if i >= suffixLen:
    return true

proc toString*(runes: Runes): string {.inline.} =
  return $runes

proc toString*(lines: seq[Runes]): string =
  for i, runes in lines:
    result &= $runes & '\n'

proc `&`*(r1, r2: Rune | Runes): Runes =
  result = r1
  result.add r2

proc `&`*(r1: Runes, r2: Rune): Runes =
  result = r1
  result.add r2

proc `&`*(r1: Rune, r2: Runes): Runes =
  result = @[r1]
  result.add r2

proc correspondingOpenParen*(r: Rune): Rune =
  case r
  of ru ')':
    return ru '('
  of ru '}':
    return ru '{'
  of ru ']':
    return ru '['
  of ru '"':
    return ru '\"'
  of ru '\'':
    return ru '\''
  else:
    doAssert(false, fmt"Invalid parentheses: {r}")

proc correspondingCloseParen*(r: Rune): Rune =
  case r
  of ru '(':
    return ru ')'
  of ru '{':
    return ru '}'
  of ru '[':
    return ru ']'
  of ru '"':
    return ru '\"'
  of ru '\'':
    return ru '\''
  else:
    doAssert(false, fmt"Invalid parentheses: {r}")

proc isCorrespondingParen*(openParen, closeParen: Rune): bool =
  let
    open = char(openParen)
    close = char(closeParen)
  if (open == '(' and close == ')') or (open == '{' and close == '}') or
      (open == '[' and close == ']') or (open == '"' and close == '\"') or
      (open == '\'' and close == '\''):
    return true

proc isOpenParen*(r: Rune): bool =
  case r
  of ru '(', ru '{', ru '[', ru '\"', ru '\'':
    return true
  else:
    return false

proc isCloseParen*(r: Rune): bool =
  case r
  of ru ')', ru '}', ru ']', ru '\"', ru '\'':
    return true
  else:
    return false

proc isParen*(r: Rune): bool =
  if r.isOpenParen or r.isCloseParen:
    return true
  else:
    return false

proc find*(runes, sub: Runes, start: Natural = 0, last = 0): int =
  ## If `last` is unspecified, it defaults to `runes.high`(the last element).
  ## If `sub` is no in `runes`, -1 is returned. Otherwise the index is returned.

  let last = if last == 0: runes.high else: last

  var startAsUtf8, lastAsUtf8: Natural
  for i, r in runes:
    let s = $r
    if i < start:
      startAsUtf8 += s.len
    if i <= last:
      lastAsUtf8 += s.len
    else:
      break

  let
    str = $runes
    i = find(str, $sub, startAsUtf8, lastAsUtf8)

  if i == -1:
    return -1
  else:
    return runeLen(str[0 ..< i])

proc find*(runes: Runes, sub: Rune, start: Natural = 0, last = 0): int {.inline.} =
  runes.find(sub.toRunes, start, last)

proc rfind*(runes: Runes, r: Rune, start: Natural = 0, last = -1): int =
  ## If `last` is unspecified, it defaults to `runes.high`(the last element).
  ## If `r` is no in `runes`, -1 is returned. Otherwise the index is returned.

  let last = if last == -1: runes.high else: last

  for i in countdown(last, start):
    if runes[i] == r:
      return i

  return -1

proc rfind*(runes, sub: Runes, start: Natural = 0, last = -1): int =
  ## If `last` is unspecified, it defaults to `runes.high`(the last element).
  ## If `sub` is no in `runes`, -1 is returned. Otherwise the index is returned.

  if sub.len == 0:
    return -1

  let last = if last == -1: runes.high else: last

  for i in countdown(last - sub.len + 1, start):
    result = i
    for j in 0 ..< sub.len:
      if runes[i + j] != sub[j]:
        result = -1
        break
    if result != -1:
      return
  return -1

proc substr*(runes: Runes, first, last: int): Runes {.inline.} =
  runes[first .. last]

proc substr*(runes: Runes, first = 0): Runes {.inline.} =
  substr(runes, first, runes.high)

proc contains*(runes: Runes, sub: Rune): bool {.inline.} =
  find(runes, sub) >= 0

proc contains*(runes, sub: Runes): bool {.inline.} =
  return find(runes, sub) >= 0

proc contains*(runes: seq[Runes], sub: Runes): bool {.inline.} =
  find(runes, sub) >= 0

proc `in`*(runes: Runes, sub: Rune): bool {.inline.} =
  find(runes, sub) >= 0

proc `in`*(runes, sub: Runes): bool {.inline.} =
  find(runes, sub) >= 0

proc `in`*(runes: seq[Runes], sub: Runes): bool {.inline.} =
  find(runes, sub) >= 0

iterator split*(
    runes: Runes, isSep: proc(r: Rune): bool, removeEmptyEntries: bool = false
): Runes =
  ## Splits the runes by `isSep`.
  ## if `removeEmptyEntries` is false, including empty runes.

  var first = 0
  while first <= runes.len:
    var last = first
    while last < runes.len and not isSep(runes[last]):
      last.inc

    if first < last:
      yield runes[first ..< last]
    if last < runes.len and not removeEmptyEntries:
      yield ru""

    first = last + 1

proc split*(
    runes: Runes, isSep: proc(r: Rune): bool, removeEmptyEntries: bool = false
): seq[Runes] {.inline.} =
  if runes.len == 0:
    if removeEmptyEntries:
      return @[]
    else:
      return @[ru""]

  for r in runes.split(isSep, removeEmptyEntries):
    if removeEmptyEntries and r.len > 0:
      result.add r
    else:
      result.add r

proc split*(
    runes: Runes, sep: Rune, removeEmptyEntries: bool = false
): seq[Runes] {.inline.} =
  runes.split(
    proc(r: Rune): bool =
      r == sep,
    removeEmptyEntries,
  )

proc splitWhitespace*(
    runes: Runes, removeEmptyEntries: bool = false
): seq[Runes] {.inline.} =
  runes.split(
    proc(r: Rune): bool =
      r.isWhiteSpace,
    removeEmptyEntries,
  )

iterator splitLines*(runes: Runes): Runes =
  var first = 0
  while first <= runes.len:
    var last = first
    while last < runes.len and not isNewline(runes[last]):
      last.inc

    if first < last:
      yield runes[first ..< last]
    else:
      yield ru""

    first = last + 1

proc splitLines*(runes: Runes): seq[Runes] {.inline.} =
  for line in runes.splitLines:
    result.add line

proc parseInt*(rune: Rune): int {.inline.} =
  parseInt($rune)

proc parseInt*(runes: Runes): int {.inline.} =
  parseInt($runes)

proc toggleCase*(ch: Rune): Rune =
  result = ch
  if result.isUpper():
    result = result.toLower()
  elif result.isLower():
    result = result.toUpper()
  return result

proc removePrefix*(r: var Runes, prefix: Runes) =
  var start = 0
  while start < r.len and r[start] in prefix:
    start += 1
  if start > 0:
    r.delete(0 .. start - 1)

proc removePrefix*(r: var Runes, prefix: Rune) {.inline.} =
  r.removePrefix(@[prefix])

proc removePrefix*(r: Rune | Runes, prefix: Rune): Runes {.inline.} =
  result = r
  result.removePrefix(prefix)

proc removeSuffix*(r: var Runes, suffix: Runes) =
  if r.len == 0:
    return
  var last = r.high
  while last > -1 and r[last] in suffix:
    last -= 1
  r.setLen(last + 1)

proc removeSuffix*(r: var Runes, suffix: Rune) {.inline.} =
  r.removeSuffix(@[suffix])

proc removeSuffix*(r: Rune | Runes, suffix: Rune): Runes {.inline.} =
  result = r
  result.removeSuffix(suffix)

proc `/`*(head, tail: Runes): Runes {.inline.} =
  return toRunes($head / $tail)

proc repeat*(r: Rune | Runes, n: Natural): Runes {.inline.} =
  for _ in 0 ..< n:
    result.add r

proc encodeUTF8*(r: Rune): seq[uint32] =
  const
    # first byte of a 2-byte encoding starts 110 and carries 5 bits of data
    B2Lead = 0xC0 # 1100 0000
    B2Mask {.used.} = 0x1F # 0001 1111

    # first byte of a 3-byte encoding starts 1110 and carries 4 bits of data
    B3Lead = 0xE0 # 1110 0000
    B3Mask {.used.} = 0x0F # 0000 1111

    # first byte of a 4-byte encoding starts 11110 and carries 3 bits of data
    B4Lead = 0xF0 # 1111 0000
    B4Mask {.used.} = 0x07 # 0000 0111

    # non-first bytes start 10 and carry 6 bits of data
    MbLead = 0x80 # 1000 0000
    MbMask = 0x3F # 0011 1111

  let i = uint32(r)
  if i <= i shl 7 - 1:
    result.add uint32(r)
  if i <= 1 shl 11 - 1:
    result.add B2Lead or i shr 6
    result.add MbLead or i and MbMask
  if i <= i shl 16 - 1:
    result.add B3Lead or i shr 12
    result.add MbLead or i shr 6
    result.add MbLead or i and MbLead
  else:
    result.add uint32(r)
    result.add B4Lead or i shl 18
    result.add MbLead or i shl 12
    result.add MbLead or i shl 6
    result.add MbLead or i and MbMask

proc absolutePath*(runes: Runes): Runes =
  let pathStr = $runes
  result = absolutePath(pathStr).toRunes
  if result.len > 0 and dirExists(pathStr) and result[^1] != ru '/':
    result &= ru '/'

proc count*(runes: Runes, r: Rune): int {.inline.} =
  ## Count `r` contained in `runes`

  for r2 in runes:
    if r2 == r:
      result.inc

template clear*(r: var Rune) =
  ## Assign empty rune.

  r = "".ru

template clear*(r: var Runes) =
  ## Assign empty runes.

  r = "".ru

proc isContainUpper*(runes: Runes): bool =
  for r in runes:
    let ch = r.toChar
    if isUpperAscii(ch):
      return true

proc join*(lines: seq[Runes], sep: Runes = ru""): Runes =
  for index, runes in lines:
    result.add runes
    if index < lines.high:
      result.add sep

proc toLower*(runes: Runes): Runes =
  for r in runes:
    result.add toLower(r)

proc toLower*(lines: seq[Runes]): seq[Runes] =
  for runes in lines:
    result.add toLower(runes)

proc isAllLower*(runes: Runes): bool =
  result = true
  for r in runes:
    if not r.isLower:
      return false

proc stripLineEnd*(r: var Runes) =
  if r.len > 0:
    case r[^1]
    of ru '\n':
      if r.len > 1 and r[^2] == ru '\r':
        r.setLen r.len - 2
      else:
        r.setLen r.len - 1
    of ru '\r', ru '\v', ru '\f':
      r.setLen r.len - 1
    else:
      discard

proc replace*(r, sub: Runes, by: Runes = ru""): Runes =
  ## Replaces every occurrence of the `sub` sequence in `s` with `by`.

  result = @[]
  let subLen = sub.len
  if subLen == 0:
    result = r
    return

  var i = 0
  while i <= r.len - subLen:
    if r[i ..< i + subLen] == sub:
      result.add(by)
      i += subLen
    else:
      result.add(r[i])
      inc i

  # Copy the remaining runes, if any
  while i < r.len:
    result.add(r[i])
    inc i

proc replaceToNewLines*(runes: Runes): Runes =
  ## Replaces "\n" to '\n' in `runes`.
  ## Ignore "\\n".

  var
    i = 0
    isEscape = false
  while i < runes.len:
    if runes[i] == ru '\\':
      if not isEscape:
        isEscape = true
      elif runes[i - 1] == ru '\\':
        isEscape = false
        result.add runes[i]
    elif isEscape and runes[i] == ru 'n':
      result.add ru '\n'
      isEscape = false
    else:
      result.add runes[i]

    i.inc

proc maxLen*(lines: seq[Runes]): int {.inline.} =
  lines.mapIt(it.len).max

proc maxHigh*(lines: seq[Runes]): int {.inline.} =
  lines.mapIt(it.high).max

proc removeNewLineAtEnd*(runes: Runes): Runes =
  result = runes

  var countNewline = 0
  for i in countdown(runes.high, 0):
    if runes[i] in [ru '\n', ru '\r']:
      countNewline.inc
    else:
      break

  if countNewline > 0:
    return result[0 .. countNewline]

proc addMargins*(lines: seq[Runes], width: int = 1): seq[Runes] =
  let maxLen = lines.maxLen
  for line in lines:
    if line.len == maxLen:
      result.add ru" " & line & ru" "
    else:
      result.add ru" " & line

proc skipWhitespace*(r: Runes, start = 0): int =
  let array = r[start .. r.high]
  while result < array.len and array[result] in WhitespaceRune:
    result.inc
