## GNU General Public License 3.0 ######################]#
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

import std/[unittest, strutils]

import pkg/results

import ../src/moepkg/encoding {.all.}

suite "Encoding Detection":
  test "Detect UTF-8 from ASCII text":
    let text = "Hello, World!"
    check detectCharacterEncoding(text) == CharacterEncoding.utf8

  test "Detect UTF-8 BOM":
    let text = "\xEF\xBB\xBF" & "Hello"
    check detectCharacterEncoding(text) == CharacterEncoding.utf8

  test "Detect UTF-8 with Japanese":
    let text = "こんにちは世界"
    check detectCharacterEncoding(text) == CharacterEncoding.utf8

  test "Detect UTF-16 BOM":
    let text = "\xFE\xFF\x00\x48\x00\x65" # UTF-16 BE BOM + "He"
    check detectCharacterEncoding(text) == CharacterEncoding.utf16

  test "Detect UTF-32 BOM":
    let text = "\x00\x00\xFE\xFF\x00\x00\x00\x48" # UTF-32 BE BOM + "H"
    check detectCharacterEncoding(text) == CharacterEncoding.utf32

  test "encodingToString returns correct names":
    check encodingToString(CharacterEncoding.utf8) == "UTF-8"
    check encodingToString(CharacterEncoding.utf16) == "UTF-16"
    check encodingToString(CharacterEncoding.utf16Be) == "UTF-16BE"
    check encodingToString(CharacterEncoding.utf16Le) == "UTF-16LE"
    check encodingToString(CharacterEncoding.utf32) == "UTF-32"
    check encodingToString(CharacterEncoding.utf32Be) == "UTF-32BE"
    check encodingToString(CharacterEncoding.utf32Le) == "UTF-32LE"
    check encodingToString(CharacterEncoding.unknown) == "UNKNOWN"

  test "Detect empty string as UTF-8":
    let text = ""
    check detectCharacterEncoding(text) == CharacterEncoding.utf8

  test "Detect UTF-16 LE BOM":
    let text = "\xFF\xFE\x48\x00\x65\x00" # UTF-16 LE BOM + "He"
    check detectCharacterEncoding(text) == CharacterEncoding.utf16

  test "Detect UTF-32 LE BOM":
    let text = "\xFF\xFE\x00\x00\x00\x00\x00\x48" # UTF-32 LE BOM + "H"
    check detectCharacterEncoding(text) == CharacterEncoding.utf32

  test "UTF-16 BE without BOM detected as UTF-8 when valid":
    # "Hello" in UTF-16 BE (no BOM) - also valid UTF-8 (contains NUL bytes)
    # UTF-8 is tried first and succeeds, so it's detected as UTF-8
    let text = "\x00\x48\x00\x65\x00\x6C\x00\x6C\x00\x6F"
    check detectCharacterEncoding(text) == CharacterEncoding.utf8

  test "UTF-16 LE without BOM detected as UTF-8 when valid":
    # "Hello" in UTF-16 LE (no BOM) - also valid UTF-8
    let text = "\x48\x00\x65\x00\x6C\x00\x6C\x00\x6F\x00"
    check detectCharacterEncoding(text) == CharacterEncoding.utf8

  test "Invalid UTF-8 with ambiguous encoding returns unknown":
    # Invalid UTF-8 that could be valid in multiple UTF-16/32 formats
    # When multiple encodings are valid, returns unknown
    let text = "\x80\x80\x80\x80"
    check detectCharacterEncoding(text) == CharacterEncoding.unknown

  test "Invalid UTF-8 with odd length returns unknown":
    # Odd length invalidates UTF-16 and UTF-32, invalid UTF-8 returns unknown
    let text = "\x80\x80\x80"
    check detectCharacterEncoding(text) == CharacterEncoding.unknown

  test "Ambiguous encoding returns unknown":
    # Byte sequences that could be multiple encodings
    # returns unknown when ambiguous
    let text = "\x80\x81\x82\x83"
    check detectCharacterEncoding(text) == CharacterEncoding.unknown

  test "Detect invalid UTF-8 returns unknown":
    # Invalid byte sequence that doesn't match any encoding
    # Odd length prevents UTF-16/32 validation
    let text = "\x80\x81\x82"
    check detectCharacterEncoding(text) == CharacterEncoding.unknown

  test "Lone high surrogate at end does not crash UTF-16 validation":
    # Regression: validateUtf16Be/Le read past the end when the input ends
    # with a lone high surrogate (previously raised IndexDefect)
    let inputs = ["\x00\xD8", "\x00\x00\x00\xD8", "\xD8\x00", "\xD8\x00\x00\x00"]
    for text in inputs:
      var crashed = false
      try:
        discard detectCharacterEncoding(text)
      except Defect:
        crashed = true
      check not crashed

  test "Lone low surrogate at end does not crash UTF-16 validation":
    # Regression: same class of defect as the high surrogate case
    let inputs = ["\x00\xDC", "\x00\x00\x00\xDC", "\xDC\x00", "\xDC\x00\x00\x00"]
    for text in inputs:
      var crashed = false
      try:
        discard detectCharacterEncoding(text)
      except Defect:
        crashed = true
      check not crashed

  test "Lone high surrogate at end is rejected by UTF-16 validators":
    check not validateUtf16Be("\xD8\x00")
    check not validateUtf16Be("\xD8\x00\x00\x00")
    check not validateUtf16Le("\x00\xD8")
    check not validateUtf16Le("\x00\x00\x00\xD8")

  test "Lone low surrogate at end is rejected by UTF-16 validators":
    check not validateUtf16Be("\xDC\x00")
    check not validateUtf16Be("\xDC\x00\x00\x00")
    check not validateUtf16Le("\x00\xDC")
    check not validateUtf16Le("\x00\x00\x00\xDC")

  test "Valid surrogate pair at end is accepted by UTF-16 validators":
    # U+20000 (0xD840 / 0xDC00)
    check validateUtf16Be("\xD8\x40\xDC\x00")
    check validateUtf16Le("\x40\xD8\x00\xDC")
    # U+1F600 (0xD83D / 0xDE00)
    check validateUtf16Be("\xD8\x3D\xDE\x00")
    check validateUtf16Le("\x3D\xD8\x00\xDE")

  test "UTF-16BE detection survives surrogate pair at sample boundary":
    # Regression: the sample cut used to split the surrogate pair
    let text =
      repeat("\x00A", EncodingDetectionSampleSize div 2 - 2) & "\x00\xD8" &
      "\xD8\x40\xDC\x00"
    check detectCharacterEncoding(text) == CharacterEncoding.utf16Be

  test "UTF-16LE detection survives surrogate pair at sample boundary":
    let text =
      repeat("\x41\x00", EncodingDetectionSampleSize div 2 - 2) & "\xD8\x00" &
      "\x40\xD8\x00\xDC"
    check detectCharacterEncoding(text) == CharacterEncoding.utf16Le

  test "Sample cut with 3 bytes remaining extends by 2 (s.len = 8195)":
    # Regression: the +2 extension branch fires when 3 bytes remain past
    # the cut. The extended sample completes the cut pair, keeping the LE
    # detection alive; without the extension the sample would end on a
    # lone high surrogate and UTF-16 detection would fail outright.
    let text =
      repeat("\x41\x00", EncodingDetectionSampleSize div 2 - 1) & "\xD8\x41" & "\x41\x41" &
      "\x00"
    check detectCharacterEncoding(text) == CharacterEncoding.utf16Le

  test "Sample cut with 1 byte remaining skips extension (s.len = 8193)":
    # Regression: the extension gate `sampleLen + 2 <= s.len` skips the
    # extension when only 1 byte remains. The full re-validation then
    # rejects UTF-16 (odd length) and the sample is ambiguous UTF-32.
    let text =
      repeat("\x41\x00", EncodingDetectionSampleSize div 2 - 1) & "\xD8\x41" & "\x41"
    check detectCharacterEncoding(text) == CharacterEncoding.unknown

  test "UTF-32BE detection survives surrogate-like code point at sample boundary":
    # Regression: the surrogate-pair guard used to extend the sample by 2
    # bytes, misaligning it for the UTF-32 validators when the code point
    # at the cut has low 16 bits in the high surrogate range.
    # U+2D800 (CJK Ext E) has low 16 bits 0xD800.
    let text =
      repeat("\x00\x00\x91\xE3", EncodingDetectionSampleSize div 4 - 1) &
      "\x00\x02\xD8\x00" & "\x00\x00\x91\xE3"
    check detectCharacterEncoding(text) == CharacterEncoding.utf32Be

  test "UTF-16BE detection does not flip to LE when the sample cut splits a pair":
    # Regression: when surrogate pairs surround the cut, the 4-byte
    # extension still leaves a lone high surrogate at the sample end. The
    # BE validation of the sample then fails while the LE validation
    # passes, misdetecting a BE file as LE. The UTF-16 re-validation
    # against the full content must not guess between two valid byte
    # orders.
    let text =
      repeat("\x00A", EncodingDetectionSampleSize div 2 - 1) &
      repeat("\xD8\x3D\xDE\x00", 20)
    check detectCharacterEncoding(text) == CharacterEncoding.unknown

  test "UTF-16LE detection does not flip to BE when the sample cut splits a pair":
    let text =
      repeat("\x41\x00", EncodingDetectionSampleSize div 2 - 1) &
      repeat("\x3D\xD8\x00\xDE", 20)
    check detectCharacterEncoding(text) == CharacterEncoding.unknown

  test "Detect UTF-8 with multi-byte characters":
    # Emoji (4-byte UTF-8 sequence)
    let text = "🎉"
    check detectCharacterEncoding(text) == CharacterEncoding.utf8

  test "Detect UTF-8 with mixed ASCII and multi-byte":
    let text = "Hello 世界! 🌍"
    check detectCharacterEncoding(text) == CharacterEncoding.utf8

  test "encodingToString covers all encodings":
    # Ensure all enum values have string representations
    for enc in CharacterEncoding:
      check encodingToString(enc).len > 0

suite "Encoding Transcoding":
  test "UTF-16LE decodes to UTF-8":
    # "He" in UTF-16 LE
    let bytes = "\x48\x00\x65\x00"
    check decodeToUtf8(bytes, CharacterEncoding.utf16Le).get == "He"

  test "UTF-16BE decodes to UTF-8":
    # "こん" in UTF-16 BE (U+3053 U+3093)
    let bytes = "\x30\x53\x30\x93"
    check decodeToUtf8(bytes, CharacterEncoding.utf16Be).get == "こん"

  test "UTF-16 surrogate pair decodes to UTF-8":
    # "😀" (U+1F600) in UTF-16 LE: D83D DE00
    let bytes = "\x3D\xD8\x00\xDE"
    check decodeToUtf8(bytes, CharacterEncoding.utf16Le).get == "😀"

  test "UTF-16 decode rejects odd byte length":
    check decodeToUtf8("\x48\x00\x65", CharacterEncoding.utf16Le).isErr

  test "UTF-16 decode rejects unpaired surrogates":
    # Lone high surrogate D800 followed by a non-surrogate
    check decodeToUtf8("\x00\xD8\x41\x00", CharacterEncoding.utf16Le).isErr
    # Lone low surrogate DC00
    check decodeToUtf8("\x00\xDC", CharacterEncoding.utf16Le).isErr
    # Truncated pair (high surrogate at end of input)
    check decodeToUtf8("\x00\xD8", CharacterEncoding.utf16Le).isErr

  test "UTF-32 decodes to UTF-8":
    # "a😀" in UTF-32 LE
    let bytes = "\x61\x00\x00\x00\x00\xF6\x01\x00"
    check decodeToUtf8(bytes, CharacterEncoding.utf32Le).get == "a😀"

  test "UTF-32 decode rejects out-of-range code points":
    # U+110000 (one past the Unicode maximum)
    check decodeToUtf8("\x00\x11\x00\x00", CharacterEncoding.utf32Be).isErr

  test "UTF-32 decode rejects length not multiple of 4":
    check decodeToUtf8("\x61\x00\x00", CharacterEncoding.utf32Le).isErr

  test "decode is identity for UTF-8 and unknown":
    check decodeToUtf8("héllo", CharacterEncoding.utf8).get == "héllo"
    check decodeToUtf8("\x80\x81", CharacterEncoding.unknown).get == "\x80\x81"

  test "encode/decode round-trips for all UTF-16/32 variants":
    let text = "Hello, 世界! 🌍\nsecond line\r\n"
    for enc in [
      CharacterEncoding.utf16Le, CharacterEncoding.utf16Be, CharacterEncoding.utf32Le,
      CharacterEncoding.utf32Be,
    ]:
      check decodeToUtf8(encodeFromUtf8(text, enc), enc).get == text

  test "encode is identity for UTF-8 and unknown":
    check encodeFromUtf8("héllo", CharacterEncoding.utf8) == "héllo"
    check encodeFromUtf8("\x80\x81", CharacterEncoding.unknown) == "\x80\x81"

  test "generic utf16/utf32 encode as big endian":
    check encodeFromUtf8("A", CharacterEncoding.utf16) == "\x00\x41"
    check encodeFromUtf8("A", CharacterEncoding.utf32) == "\x00\x00\x00\x41"

  test "bomBytes returns the BOM for each encoding":
    check bomBytes(CharacterEncoding.utf8) == "\xEF\xBB\xBF"
    check bomBytes(CharacterEncoding.utf16Le) == "\xFF\xFE"
    check bomBytes(CharacterEncoding.utf16Be) == "\xFE\xFF"
    check bomBytes(CharacterEncoding.utf32Le) == "\xFF\xFE\x00\x00"
    check bomBytes(CharacterEncoding.utf32Be) == "\x00\x00\xFE\xFF"
    check bomBytes(CharacterEncoding.unknown) == ""

suite "sanitizeInvalidUtf8":
  test "valid UTF-8 passes through unchanged":
    check sanitizeInvalidUtf8("hello") == "hello"
    check sanitizeInvalidUtf8("こんにちは") == "こんにちは"
    check sanitizeInvalidUtf8("héllo") == "héllo"
    check sanitizeInvalidUtf8("a😀b") == "a😀b"

  test "invalid leading byte becomes U+FFFD":
    check sanitizeInvalidUtf8("\xC0\x41") == "\xEF\xBF\xBD" & "A"
    # 0xF5-0xF7 are invalid 4-byte leading bytes (code point > U+10FFFF);
    # the trailing continuation bytes are each substituted too.
    check sanitizeInvalidUtf8("\xF5\x80\x80\x80") ==
      "\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD"

  test "truncated sequence becomes U+FFFD per byte":
    check sanitizeInvalidUtf8("\xE3\x81") == "\xEF\xBF\xBD\xEF\xBF\xBD"
    check sanitizeInvalidUtf8("\xF0\x9F") == "\xEF\xBF\xBD\xEF\xBF\xBD"

  test "bad continuation byte splits the sequence":
    # 0xE3 0x28 (ASCII '(') is not a valid continuation
    check sanitizeInvalidUtf8("\xE3\x28") == "\xEF\xBF\xBD" & "("
    check sanitizeInvalidUtf8("\xE3\x81\x28") == "\xEF\xBF\xBD\xEF\xBF\xBD" & "("

  test "overlong encoding becomes U+FFFD per byte":
    # 0xC0 0x80 encodes NUL overlong; 0x80 alone is also invalid
    check sanitizeInvalidUtf8("\xC0\x80") == "\xEF\xBF\xBD\xEF\xBF\xBD"
    # 0xE0 0x80 0x80 encodes NUL overlong in 3 bytes
    check sanitizeInvalidUtf8("\xE0\x80\x80") == "\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD"

  test "surrogate code point becomes U+FFFD per byte":
    # 0xED 0xA0 0x80 is a UTF-8-encoded surrogate
    check sanitizeInvalidUtf8("\xED\xA0\x80") == "\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD"

  test "code point above U+10FFFF becomes U+FFFD per byte":
    # 0xF4 0x90 0x80 0x80 encodes U+110000
    check sanitizeInvalidUtf8("\xF4\x90\x80\x80") ==
      "\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD\xEF\xBF\xBD"

  test "mixed valid and invalid text":
    check sanitizeInvalidUtf8("ok\xC0\x41ok") == "ok" & "\xEF\xBF\xBD" & "Aok"
    check sanitizeInvalidUtf8("a\xE3\x81\x82b") == "aあb"
