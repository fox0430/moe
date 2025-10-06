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

## Character encoding detection for text files
##
## This module provides utilities for detecting character encodings from
## raw file content. It supports various Unicode encodings (UTF-8, UTF-16, UTF-32)
## with BOM and without BOM detection.

import std/unicode

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

proc detectCharacterEncoding*(s: string): CharacterEncoding =
  ## Detect character encoding from raw file content
  ##
  ## This function attempts to guess the character encoding of a string by:
  ## 1. Checking for BOM (Byte Order Mark) headers
  ## 2. Validating against known Unicode formats
  ## 3. Using heuristics to disambiguate similar encodings
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

  # Try UTF-8 validation first (most common)
  if s.validateUtf8 == -1:
    return CharacterEncoding.utf8

  # Try other Unicode encodings
  var validEncodings: seq[CharacterEncoding]
  if s.validateUtf16Be:
    validEncodings.add(CharacterEncoding.utf16Be)
  if s.validateUtf16Le:
    validEncodings.add(CharacterEncoding.utf16Le)
  if s.validateUtf32Be:
    validEncodings.add(CharacterEncoding.utf32Be)
  if s.validateUtf32Le:
    validEncodings.add(CharacterEncoding.utf32Le)

  # Use heuristic to filter out UTF-16 if there are too many null bytes
  # (UTF-32 is more likely in that case)
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
