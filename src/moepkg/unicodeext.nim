#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[unicode, sequtils, strutils, strformat, os, times, oids]
import pkg/unicodedb/widths

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

proc `$`*(encoding: CharacterEncoding): string =
  case encoding
  of CharacterEncoding.utf8: return "UTF-8"
  of CharacterEncoding.utf16: return "UTF-16"
  of CharacterEncoding.utf16Be: return "UTF-16BE"
  of CharacterEncoding.utf16Le: return "UTF-16LE"
  of CharacterEncoding.utf32: return "UTF-32"
  of CharacterEncoding.utf32Be: return "UTF-32BE"
  of CharacterEncoding.utf32Le: return "UTF-32LE"
  of CharacterEncoding.unknown: return "UNKNOWN"

proc validateUtf16Be(s: string): bool =
  if (s.len mod 2) != 0: return false

  var i = 0
  proc advance: int =
    result = 256*ord(s[i])+ord(s[i+1])
    i += 2

  while i < s.len:
    let curr = advance()
    if curr <= 0xD7FF or (0xE000 <= curr and curr <= 0xFFFF): continue
    let next = advance()
    if (not (0xD800 <= curr and curr <= 0xDBFF)) or
       (not (0xDC00 <= next and next <= 0xDFFF)): return false
    let
      higher = (curr and 0b11_1111_1111) shl 10
      lower = (next and 0b11_1111_1111)
      point = higher or lower
    if point < 0x10000: return false

  return true

proc validateUtf16Le(s: string): bool =
  if (s.len mod 2) != 0: return false

  var i = 0
  proc advance: int =
    result = ord(s[i])+256*ord(s[i+1])
    i += 2

  while i < s.len:
    let curr = advance()
    if curr <= 0xD7FF or (0xE000 <= curr and curr <= 0xFFFF): continue
    let next = advance()
    if (not (0xD800 <= curr and curr <= 0xDBFF)) or
       (not (0xDC00 <= next and next <= 0xDFFF)): return false
    let
      higher = (curr and 0b11_1111_1111) shl 10
      lower = (next and 0b11_1111_1111)
      point = higher or lower
    if point < 0x10000: return false

  return true

proc validateUtf32Be(s: string): bool =
  if (s.len mod 4) != 0: return false

  var i = 0
  proc advance: uint32 =
    result = 0x1000000'u32*uint32(ord(s[i]))+0x10000'u32*uint32(ord(s[i+1]))+0x100'u32*uint32(ord(s[i+2]))+uint32(ord(s[i+3]))
    i += 4

  while i < s.len:
    let curr = advance()
    if curr > 0x10FFFF'u32: return false

  return true

proc validateUtf32Le(s: string): bool =
  if (s.len mod 4) != 0: return false

  var i = 0
  proc advance: uint32 =
    result = uint32(ord(s[i]))+0x100'u32*uint32(ord(s[i+1]))+0x10000'u32*uint32(ord(s[i+2]))+0x1000000'u32*uint32(ord(s[i+3]))
    i += 4

  while i < s.len:
    let curr = advance()
    if curr > 0x10FFFF'u32: return false

  return true

proc count0000(s: string): int =
  var i = 0
  while i+1 < s.len:
    if ord(s[i]) == 0x00 and ord(s[i+1]) == 0x00: inc(result)
    i += 2

proc detectCharacterEncoding*(s: string): CharacterEncoding =
  # Guess the character encoding form of `s`.
  # In currently, only the Unicode format is supported.
  # Returns `CharacterEncoding.utf8` if only ASCII characters are included.
  # Returns `CharacterEncoding.unknown` if encoding format is unknown.


  # Check UTF-8 BOM
  if s.len >= 3 and s[0..2] == "\xEF\xBB\xBF": return CharacterEncoding.utf8

  if s.len >= 4:
    # Check UTF-32 BOM
    if s[0..3] == "\x00\x00\xFE\xFF" or
       s[0..3] == "\xFF\xFE\x00\x00": return CharacterEncoding.utf32

    # Check UTF-16 BOM
    if s[0..1] == "\xFE\xFF" or s[0..1] == "\xFF\xFE": return CharacterEncoding.utf16

  if s.validateUtf8 == -1: return CharacterEncoding.utf8

  var validEncodings: seq[CharacterEncoding]
  if s.validateUtf16Be: validEncodings.add(CharacterEncoding.utf16Be)
  if s.validateUtf16Le: validEncodings.add(CharacterEncoding.utf16Le)
  if s.validateUtf32Be: validEncodings.add(CharacterEncoding.utf32Be)
  if s.validateUtf32Le: validEncodings.add(CharacterEncoding.utf32Le)

  let threshold = (s.len / 2) * (2 / 5)
  if float(count0000(s)) >= threshold:
    # If there are too many 0x000, assume it is not UTF-16.
    if validEncodings.contains(CharacterEncoding.utf16Be):
      validEncodings.delete(validEncodings.find(CharacterEncoding.utf16Be))
    if validEncodings.contains(CharacterEncoding.utf16Le):
      validEncodings.delete(validEncodings.find(CharacterEncoding.utf16Le))

  if validEncodings.len == 1: return validEncodings[0]

  return CharacterEncoding.unknown

proc toRune*(c: char): Rune {.inline.} =
  doAssert(ord(c) <= 127)
  Rune(c)

proc toRune*(x: int): Rune {.inline.} = Rune(x)

proc `==`*(c: Rune, x: int): bool {.inline.} = c == toRune(x)
proc `==`*(c: Rune, x: char): bool {.inline.} = c == toRune(x)

proc ru*(c: char): Rune {.inline.} = toRune(c)
proc ru*(s: string): seq[Rune] {.inline.} = s.toRunes
proc ru*(r: Rune): seq[Rune] {.inline.} = @[r]
proc ru*(array: seq[string]): seq[Rune] =
  for s in array:
    result.add s.toRunes

proc toCh*(r: Rune): char {.inline.} =
  result = ($r)[0]

proc canConvertToChar*(c: Rune): bool {.inline.} =
  return ($c).len == 1

proc toChar*(c: Rune): char {.inline.} =
  doAssert(canConvertToChar(c), "Failed to convert Rune to char")
  return ($c)[0]

proc width*(c: Rune): int =
  const tab = Rune('\t')
  if int(c) > 0x10FFFF: return 1
  if c == tab: return 4
  case c.unicodeWidth
  of UnicodeWidth.uwdtNarrow,
     UnicodeWidth.uwdtHalf,
     UnicodeWidth.uwdtAmbiguous,
     UnicodeWidth.uwdtNeutral: 1
  else: 2

proc width*(runes: seq[Rune]): int {.inline.} =
  for c in runes: result += width(c)

proc numberOfBytes*(firstByte: char): int =
  if (int(firstByte) shr 7) == 0b0: return 1
  if (int(firstByte) shr 5) == 0b110: return 2
  if (int(firstByte) shr 4) == 0b1110: return 3
  if (int(firstByte) shr 3) == 0b11110: return 4
  doAssert(false, "Invalid UTF-8 first byte.")

proc isDigit*(c: Rune): bool =
  let s = $c
  return s.len == 1 and strutils.isDigit(s[0])

proc isDigit*(runes: seq[Rune]): bool {.inline.} = all(runes, isDigit)

proc isSpace*(c: Rune): bool {.inline.} =
  return unicode.isSpace($c)

proc isPunct*(c: Rune): bool =
  let s = $c
  return s.len == 1 and s[0] in {
    '!',
    '"',
    '#',
    '$',
    '%',
    '$',
    '\'',
    '(',
    ')',
    '*',
    '+',
    ',',
    '-',
    '.',
    '/',
    ':',
    ';',
    '<',
    '=',
    '>',
    '?',
    '@',
    '[',
    '\\',
    ']',
    '^',
    '_',
    '`',
    '{',
    '=',
    '}'}

proc countRepeat*(runes: seq[Rune], charSet: set[char], start: int): int =
  for i in start ..< runes.len:
    let s = $runes[i]
    if s.len > 1 or (not (s[0] in charSet)): break
    inc(result)

proc split*(runes: seq[Rune], sep: Rune): seq[seq[Rune]] =
  result.add(@[])
  for c in runes:
    if c == sep: result.add(@[])
    else: result[result.high].add(c)

proc splitLines*(runes: seq[Rune]): seq[seq[Rune]] =
  runes.split(ru'\n')

proc toRunes*(num: int): seq[Rune] {.inline.} = toRunes($num)

proc toRunes*(dateTime: DateTime): seq[Rune] {.inline.} = toRunes($dateTime)

proc toRunes*(oid: Oid): seq[Rune] {.inline.} = toRunes($oid)

proc toRunes*(s: seq[string]): Runes =
  for l in s: result.add l.toRunes

proc toRunes*(r: Rune): Runes {.inline.} = @[r]

proc startsWith*(runes1, runes2: seq[Rune]): bool =
  result = true
  for i in 0 ..< min(runes1.len, runes2.len):
    if runes1[i] != runes2[i]:
      result = false
      break

proc startsWith*(runes1: seq[Rune], r: Rune): bool {.inline.} = runes1[0] == r

proc `$`*(seqRunes: seq[seq[Rune]]): string =
  for runes in seqRunes: result = result & $runes

proc `&`*(runes1, runes2: seq[Rune]): seq[Rune] {.inline.} =
  result = runes1
  result.add runes2

proc correspondingOpenParen*(r: Rune): Rune =
  case r
  of ru')': return ru'('
  of ru'}': return ru'{'
  of ru']': return ru'['
  of ru'"': return ru '\"'
  of ru'\'': return ru'\''
  else: doAssert(false, fmt"Invalid parentheses: {r}")

proc correspondingCloseParen*(r: Rune): Rune =
  case r
  of ru'(': return ru')'
  of ru'{': return ru'}'
  of ru'[': return ru']'
  of ru'"': return ru '\"'
  of ru'\'': return ru'\''
  else: doAssert(false, fmt"Invalid parentheses: {r}")

proc isCorrespondingParen*(openParen, closeParen: Rune): bool =
  let
    open = char(openParen)
    close = char(closeParen)
  if (open == '(' and close == ')') or
     (open == '{' and close == '}') or
     (open == '[' and close == ']') or
     (open == '"' and close == '\"') or
     (open == '\'' and close == '\''): return true

proc isOpenParen*(r: Rune): bool =
  case r
  of ru'(', ru'{', ru'[', ru'\"', ru'\'': return true
  else: return false

proc isCloseParen*(r: Rune): bool =
  case r
  of ru')', ru'}', ru']', ru'\"', ru'\'': return true
  else: return false

proc isParen*(r: Rune): bool =
  if r.isOpenParen or r.isCloseParen: return true
  else: return false

proc find*(runes, sub: seq[Rune], start: Natural = 0, last = 0): int =
  ## If `last` is unspecified, it defaults to `runes.high`(the last element).
  ## If `sub` is no in `runes`, -1 is returned. Otherwise the index is returned.

  let last = if last == 0: runes.high else: last

  var startAsUtf8, lastAsUtf8: Natural
  for i, r in runes:
    let s = $r
    if i < start: startAsUtf8 += s.len
    if i <= last: lastAsUtf8 += s.len
    else: break

  let
    str = $runes
    i = find(str, $sub, startAsUtf8, lastAsUtf8)

  if i == -1: return -1
  else: return runeLen(str[0..<i])

proc rfind*(runes: seq[Rune], r: Rune, start: Natural = 0, last = -1): int =
  ## If `last` is unspecified, it defaults to `runes.high`(the last element).
  ## If `r` is no in `runes`, -1 is returned. Otherwise the index is returned.

  let last = if last == -1: runes.high else: last

  for i in countdown(last, start):
    if runes[i] == r: return i

  return -1

proc rfind*(runes, sub: seq[Rune], start: Natural = 0, last = -1): int =
  ## If `last` is unspecified, it defaults to `runes.high`(the last element).
  ## If `sub` is no in `runes`, -1 is returned. Otherwise the index is returned.

  if sub.len == 0: return -1

  let last = if last == -1: runes.high else: last

  for i in countdown(last - sub.len + 1, start):
    result = i
    for j in 0 ..< sub.len:
      if runes[i+j] != sub[j]:
        result = -1
        break
    if result != -1: return
  return -1

proc substr*(runes: seq[Rune], first, last: int): seq[Rune] {.inline.} =
  runes[first .. last]

proc substr*(runes: seq[Rune], first = 0): seq[Rune] {.inline.} =
  substr(runes, first, runes.high)

proc contains*(runes: seq[Rune], sub: Rune): bool {.inline.} =
  find(runes, sub) >= 0

proc contains*(runes, sub: seq[Rune]): bool {.inline.} =
  find(runes, sub) >= 0

proc contains*(runes: seq[seq[Rune]], sub: seq[Rune]): bool {.inline.} =
  find(runes, sub) >= 0

proc `in`*(runes: seq[Rune], sub: Rune): bool {.inline.} =
  find(runes, sub) >= 0

proc `in`*(runes, sub: seq[Rune]): bool {.inline.} =
  find(runes, sub) >= 0

proc `in`*(runes: seq[seq[Rune]], sub: seq[Rune]): bool {.inline.} =
  find(runes, sub) >= 0

proc splitWhitespace*(runes: seq[Rune]): seq[seq[Rune]] =
  for s in unicode.split($runes):
    if not s.isEmptyOrWhitespace:
      result.add(s.toRunes)

iterator split*(runes: seq[Rune], isSep: proc (r: Rune): bool, removeEmptyEntries: bool = false): seq[Rune] =
  var first = 0
  while first <= runes.len:
    var last = first
    while last < runes.len and not isSep(runes[last]):
      inc(last)
    if not removeEmptyEntries or first < last:
      yield runes[first ..< last]
    first = last + 1

proc parseInt*(rune: Rune): int {.inline.} = parseInt($rune)

proc parseInt*(runes: seq[Rune]): int {.inline.} = parseInt($runes)

proc toggleCase*(ch: Rune): Rune =
  result = ch
  if result.isUpper():
    result = result.toLower()
  elif result.isLower():
    result = result.toUpper()
  return result

proc `/`*(runes1, runes2: seq[Rune]): seq[Rune] {.inline.} =
  toRunes($runes1 / $runes2)

proc repeat*(runes: seq[Rune], n: Natural): seq[Rune] =
  let str = repeat($runes, n)
  result = str.toRunes

proc repeat*(rune: Rune, n: Natural): seq[Rune] =
  let str = repeat($rune, n)
  result = str.ru

proc encodeUTF8*(r: Rune): seq[uint32] =
  const
    # first byte of a 2-byte encoding starts 110 and carries 5 bits of data
    b2Lead = 0xC0 # 1100 0000
    b2Mask = 0x1F # 0001 1111

    # first byte of a 3-byte encoding starts 1110 and carries 4 bits of data
    b3Lead = 0xE0 # 1110 0000
    b3Mask = 0x0F # 0000 1111

    # first byte of a 4-byte encoding starts 11110 and carries 3 bits of data
    b4Lead = 0xF0 # 1111 0000
    b4Mask = 0x07 # 0000 0111

    # non-first bytes start 10 and carry 6 bits of data
    mbLead = 0x80 # 1000 0000
    mbMask = 0x3F # 0011 1111

  let i = uint32(r)
  if i <= i shl 7 - 1:
    result.add uint32(r)
  if i <= 1 shl 11 - 1:
    result.add b2Lead or i shr 6
    result.add mbLead or i and mbMask
  if i <= i shl 16 - 1:
    result.add b3Lead or i shr 12
    result.add mbLead or i shr 6
    result.add mbLead or i and mbLead
  else:
    result.add uint32(r)
    result.add b4Lead or i shl 18
    result.add mbLead or i shl 12
    result.add mbLead or i shl 6
    result.add mbLead or i and mbMask

proc absolutePath*(runes: seq[Rune]): seq[Rune] {.inline.} =
  result = absolutePath($runes).ru
  if result.len > 0 and dirExists($runes) and result[^1] != ru '/':
    result &= ru "/"

proc removePrefix*(runes: seq[Rune], prefix: seq[Rune]): seq[Rune] {.inline.} =
  var str = $runes
  removePrefix(str, $prefix)
  return str.ru

# Count `r` contained in `runes`
proc count*(runes: seq[Rune], r: Rune): int {.inline.} =
  for r2 in runes:
    if r2 == r: result.inc

# Assign empty rune.
template clear*(r: var Rune) = r = "".ru

# Assign empty runes.
template clear*(r: var Runes) = r = "".ru

proc isContainUpper*(runes: Runes): bool =
  for r in runes:
    let ch = ($r)[0]
    if isUpperAscii(ch): return true
