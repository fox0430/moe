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

## Character encoding detection and transcoding for text files
##
## This module provides utilities for detecting character encodings from
## raw file content. It supports various Unicode encodings (UTF-8, UTF-16, UTF-32)
## with BOM and without BOM detection, plus decoding to / encoding from the
## editor's internal UTF-8 representation.

import std/unicode

import pkg/results

type CharacterEncoding* = enum
  ## Supported character encodings
  utf8
  utf16
  utf16Be
  utf16Le
  utf32
  utf32Be
  utf32Le
  unknown

proc encodingToString*(encoding: CharacterEncoding): string =
  ## Convert encoding enum to display string
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
  ## Validate if string is valid UTF-16 Big Endian
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
  ## Validate if string is valid UTF-16 Little Endian
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
  ## Validate if string is valid UTF-32 Big Endian
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
  ## Validate if string is valid UTF-32 Little Endian
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
  ## Count consecutive null bytes (used for UTF-16 detection heuristic)
  var i = 0
  while i + 1 < s.len:
    if ord(s[i]) == 0x00 and ord(s[i + 1]) == 0x00:
      inc(result)
    i += 2

const EncodingDetectionSampleSize* = 8 * 1024
  ## Number of bytes to sample from the beginning of a file for encoding
  ## detection. 8 KB is enough to reliably detect BOM markers and encoding
  ## patterns while avoiding full-file scans on large files.

proc detectCharacterEncoding*(s: string): CharacterEncoding =
  ## Detect character encoding from raw file content
  ##
  ## This function attempts to guess the character encoding of a string by:
  ## 1. Checking for BOM (Byte Order Mark) headers
  ## 2. Validating against known Unicode formats
  ## 3. Using heuristics to disambiguate similar encodings
  ##
  ## Only the first `EncodingDetectionSampleSize` bytes are examined to avoid
  ## expensive full-file scans on large files.
  ##
  ## Returns:
  ## - `utf8` if only ASCII characters are included or UTF-8 BOM is found
  ## - Specific encoding type if detected with confidence
  ## - `unknown` if encoding format cannot be determined
  ##
  ## Note: Currently only Unicode formats are supported

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

  # Use a sample of the file for encoding validation to avoid O(n) scans.
  # Only truncate when the string is larger than the sample size.
  # When truncating, align to 4 bytes so UTF-16/UTF-32 validators don't
  # reject the sample due to misalignment.
  let sample =
    if s.len > EncodingDetectionSampleSize:
      let sampleLen = EncodingDetectionSampleSize div 4 * 4
      s[0 ..< sampleLen]
    else:
      s

  # Try UTF-8 validation first (most common)
  if sample.validateUtf8 == -1:
    return CharacterEncoding.utf8

  # Try other Unicode encodings
  var validEncodings: seq[CharacterEncoding]
  if sample.validateUtf16Be:
    validEncodings.add(CharacterEncoding.utf16Be)
  if sample.validateUtf16Le:
    validEncodings.add(CharacterEncoding.utf16Le)
  if sample.validateUtf32Be:
    validEncodings.add(CharacterEncoding.utf32Be)
  if sample.validateUtf32Le:
    validEncodings.add(CharacterEncoding.utf32Le)

  # Use heuristic to filter out UTF-16 if there are too many null bytes
  # (UTF-32 is more likely in that case)
  let threshold = (sample.len / 2) * (2 / 5)
  if float(count0000(sample)) >= threshold:
    # If there are too many 0x000, assume it is not UTF-16.
    if validEncodings.contains(CharacterEncoding.utf16Be):
      validEncodings.delete(validEncodings.find(CharacterEncoding.utf16Be))
    if validEncodings.contains(CharacterEncoding.utf16Le):
      validEncodings.delete(validEncodings.find(CharacterEncoding.utf16Le))

  if validEncodings.len == 1:
    return validEncodings[0]

  return CharacterEncoding.unknown

proc utf16ToUtf8(s: string, littleEndian: bool): Result[string, string] =
  if (s.len mod 2) != 0:
    return Result[string, string].err "byte length is not a multiple of 2"

  var res = newStringOfCap(s.len)
  var i = 0

  proc advance(): int =
    result =
      if littleEndian:
        ord(s[i]) + 256 * ord(s[i + 1])
      else:
        256 * ord(s[i]) + ord(s[i + 1])
    i += 2

  while i < s.len:
    let curr = advance()
    if curr >= 0xD800 and curr <= 0xDBFF:
      if i >= s.len:
        return Result[string, string].err "truncated surrogate pair"
      let next = advance()
      if next < 0xDC00 or next > 0xDFFF:
        return Result[string, string].err "invalid surrogate pair"
      let point = 0x10000 + ((curr - 0xD800) shl 10) + (next - 0xDC00)
      res.add Rune(point).toUTF8
    elif curr >= 0xDC00 and curr <= 0xDFFF:
      return Result[string, string].err "unpaired low surrogate"
    else:
      res.add Rune(curr).toUTF8

  Result[string, string].ok res

proc utf8ToUtf16(s: string, littleEndian: bool): string =
  result = newStringOfCap(s.len * 2)

  template addUnit(unit: int) =
    if littleEndian:
      result.add char(unit and 0xFF)
      result.add char((unit shr 8) and 0xFF)
    else:
      result.add char((unit shr 8) and 0xFF)
      result.add char(unit and 0xFF)

  for r in s.runes:
    let point = int(r)
    if point < 0x10000:
      addUnit(point)
    elif point <= 0x10FFFF:
      let v = point - 0x10000
      addUnit(0xD800 + (v shr 10))
      addUnit(0xDC00 + (v and 0x3FF))
    else:
      addUnit(0xFFFD)

proc utf32ToUtf8(s: string, littleEndian: bool): Result[string, string] =
  if (s.len mod 4) != 0:
    return Result[string, string].err "byte length is not a multiple of 4"

  var res = newStringOfCap(s.len div 2)
  var i = 0

  proc advance(): uint32 =
    result =
      if littleEndian:
        uint32(ord(s[i])) + 0x100'u32 * uint32(ord(s[i + 1])) +
          0x10000'u32 * uint32(ord(s[i + 2])) + 0x1000000'u32 * uint32(ord(s[i + 3]))
      else:
        0x1000000'u32 * uint32(ord(s[i])) + 0x10000'u32 * uint32(ord(s[i + 1])) +
          0x100'u32 * uint32(ord(s[i + 2])) + uint32(ord(s[i + 3]))
    i += 4

  while i < s.len:
    let point = advance()
    if point > 0x10FFFF'u32:
      return Result[string, string].err "code point out of range"
    res.add Rune(int(point)).toUTF8

  Result[string, string].ok res

proc utf8ToUtf32(s: string, littleEndian: bool): string =
  result = newStringOfCap(s.len * 4)
  for r in s.runes:
    var point = uint32(r)
    if point > 0x10FFFF'u32:
      point = 0xFFFD
    if littleEndian:
      result.add char(point and 0xFF)
      result.add char((point shr 8) and 0xFF)
      result.add char((point shr 16) and 0xFF)
      result.add char((point shr 24) and 0xFF)
    else:
      result.add char((point shr 24) and 0xFF)
      result.add char((point shr 16) and 0xFF)
      result.add char((point shr 8) and 0xFF)
      result.add char(point and 0xFF)

proc decodeToUtf8*(s: string, encoding: CharacterEncoding): Result[string, string] =
  ## Decode raw file bytes (BOM already stripped) to UTF-8 for internal
  ## storage. `utf8`/`unknown` are returned unchanged; the generic
  ## `utf16`/`utf32` values assume big endian (the Unicode default when
  ## the byte order is unspecified).
  case encoding
  of CharacterEncoding.utf16Le:
    utf16ToUtf8(s, littleEndian = true)
  of CharacterEncoding.utf16Be, CharacterEncoding.utf16:
    utf16ToUtf8(s, littleEndian = false)
  of CharacterEncoding.utf32Le:
    utf32ToUtf8(s, littleEndian = true)
  of CharacterEncoding.utf32Be, CharacterEncoding.utf32:
    utf32ToUtf8(s, littleEndian = false)
  of CharacterEncoding.utf8, CharacterEncoding.unknown:
    Result[string, string].ok s

proc encodeFromUtf8*(s: string, encoding: CharacterEncoding): string =
  ## Encode internal UTF-8 text to the given on-disk encoding (without BOM).
  ## Invalid code points are replaced with U+FFFD.
  case encoding
  of CharacterEncoding.utf16Le:
    utf8ToUtf16(s, littleEndian = true)
  of CharacterEncoding.utf16Be, CharacterEncoding.utf16:
    utf8ToUtf16(s, littleEndian = false)
  of CharacterEncoding.utf32Le:
    utf8ToUtf32(s, littleEndian = true)
  of CharacterEncoding.utf32Be, CharacterEncoding.utf32:
    utf8ToUtf32(s, littleEndian = false)
  of CharacterEncoding.utf8, CharacterEncoding.unknown:
    s

proc bomBytes*(encoding: CharacterEncoding): string =
  ## BOM byte sequence for the given encoding (big endian for the generic
  ## utf16/utf32 values). Empty for unknown.
  case encoding
  of CharacterEncoding.utf8: "\xEF\xBB\xBF"
  of CharacterEncoding.utf16Le: "\xFF\xFE"
  of CharacterEncoding.utf16Be, CharacterEncoding.utf16: "\xFE\xFF"
  of CharacterEncoding.utf32Le: "\xFF\xFE\x00\x00"
  of CharacterEncoding.utf32Be, CharacterEncoding.utf32: "\x00\x00\xFE\xFF"
  of CharacterEncoding.unknown: ""
