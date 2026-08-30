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

import std/[unittest, unicode]

import pkg/celina

import ../src/moepkg/[unicode_utils, render_utils]
import ../src/moepkg/buffer/[core, edit]
import ../src/moepkg/buffer_backends/gap_buffer

suite "GapBuffer - Unicode Support":
  test "Create buffer with Japanese text":
    let gb = newGapBuffer("こんにちは\n世界")
    check gb.len == 2
    check gb[0] == "こんにちは"
    check gb[1] == "世界"

  test "Create buffer with emoji":
    let gb = newGapBuffer("Hello 👋\nWorld 🌍")
    check gb.len == 2
    check gb[0] == "Hello 👋"
    check gb[1] == "World 🌍"

  test "Insert ASCII into Japanese line at byte position":
    let gb = newGapBuffer("こんにちは")
    # "こんにちは" = each char is 3 bytes
    # Inserting at byte position 9 (after "こんに")
    gb.insertIntoLine(0, 9, "!")
    check gb[0] == "こんに!ちは"

  test "Insert Japanese into Japanese line at byte position":
    let gb = newGapBuffer("あいうえお")
    # Each hiragana is 3 bytes
    # Position 6 = after "あい"
    gb.insertIntoLine(0, 6, "ん")
    check gb[0] == "あいんうえお"

  test "Delete from Japanese text using byte positions":
    let gb = newGapBuffer("こんにちは")
    # Delete 3 bytes starting from position 0 (should delete "こ")
    gb.deleteAtLineCol(0, 0, 3)
    check gb[0] == "んにちは"

  test "Delete emoji (multi-byte)":
    let gb = newGapBuffer("Hello👋World")
    # 👋 is a 4-byte emoji at position 5
    gb.deleteAtLineCol(0, 5, 4)
    check gb[0] == "HelloWorld"

  test "charAtLineCol with Japanese text":
    let gb = newGapBuffer("あいう")
    # This will fail if col is expected to be character position
    # 'あ' = 0xe3 0x81 0x82 (3 bytes)
    let ch = gb.charAtLineCol(0, 0)
    # Returns first byte of 'あ'
    let expectedByte = "あ"[0]
    check ch == expectedByte

  test "Convert buffer with mixed Unicode to string":
    let gb = newGapBuffer("Hello世界\n日本語テスト")
    check $gb == "Hello世界\n日本語テスト"

  test "Insert line with Unicode content":
    let gb = newGapBuffer("first")
    gb.insertLine(1, "日本語")
    check gb.len == 2
    check gb[1] == "日本語"

  test "Replace line with Unicode content":
    let gb = newGapBuffer("old")
    gb.replaceLine(0, "新しい行")
    check gb[0] == "新しい行"

suite "Unicode Character Count":
  test "ASCII string character count":
    let text = "Hello World"
    check text.charLen == 11
    check text.len == 11 # byte length equals character count for ASCII

  test "Japanese string character count":
    let text = "こんにちは"
    check text.charLen == 5 # 5 characters
    check text.len == 15 # 15 bytes (3 bytes per hiragana character)

  test "Mixed ASCII and Japanese":
    let text = "Hello世界"
    check text.charLen == 7 # 5 ASCII + 2 Japanese
    check text.len == 11 # 5 bytes (ASCII) + 6 bytes (2 Japanese)

  test "Empty string":
    let text = ""
    check text.charLen == 0
    check text.len == 0

  test "charLen vs len (byte length)":
    let text = "漢字"
    check text.charLen == 2 # 2 characters
    check text.len == 6 # 6 bytes (each CJK char is 3 bytes in UTF-8)

suite "Unicode Position Conversion":
  test "charToBytePos with ASCII":
    let text = "Hello"
    check charToBytePos(text, 0) == 0
    check charToBytePos(text, 3) == 3
    check charToBytePos(text, 5) == 5

  test "charToBytePos with Japanese":
    let text = "こんにちは"
    check charToBytePos(text, 0) == 0 # First character starts at byte 0
    check charToBytePos(text, 1) == 3 # Second character starts at byte 3
    check charToBytePos(text, 2) == 6 # Third character starts at byte 6
    check charToBytePos(text, 5) == 15 # After last character

  test "charToBytePos with mixed content":
    let text = "Hello世界"
    check charToBytePos(text, 0) == 0 # 'H' at byte 0
    check charToBytePos(text, 5) == 5 # '世' at byte 5
    check charToBytePos(text, 6) == 8 # '界' at byte 8
    check charToBytePos(text, 7) == 11 # After last character

  test "byteToCharPos with Japanese":
    let text = "こんにちは"
    check byteToCharPos(text, 0) == 0 # Byte 0 -> char 0
    check byteToCharPos(text, 3) == 1 # Byte 3 -> char 1
    check byteToCharPos(text, 6) == 2 # Byte 6 -> char 2
    check byteToCharPos(text, 15) == 5 # Byte 15 -> char 5

  test "Byte positions follow consumed bytes, not re-encoded size":
    # A stray 0xFF decodes to Rune(0xFF) from one byte but re-encodes to two.
    # Walking by the encoded size would drift past every such byte.
    let text = "a\xFFb"
    check charToBytePos(text, 0) == 0
    check charToBytePos(text, 1) == 1
    check charToBytePos(text, 2) == 2
    check charToBytePos(text, 3) == 3
    check byteToCharPos(text, 2) == 2
    check byteToCharPos(text, 3) == 3
    check getCharAtPos(text, 1)[1] == 1
    check deleteCharAt(text, 1) == "ab"

  test "Byte positions clamp a truncated multi-byte tail":
    # 0xE3 advertises a 3-byte sequence but only one byte is left. runeLen
    # counts it as one character, so the byte walk must stop at the end of the
    # string instead of running past it.
    let text = "a\xE3"
    check text.runeLen == 2
    check runeSizeAt(text, 1) == 1
    check charToBytePos(text, 2) == text.len
    check byteToCharPos(text, text.len) == 2
    check getCharAtPos(text, 1)[1] == 1
    check deleteCharAt(text, 1) == "a"

  test "A truncated lead byte mid-string is one character, not a swallowed tail":
    # 0xE3 advertises three bytes and the byte after it is not a continuation
    # byte, so it stands alone: otherwise deleting that one cell would take the
    # visible "b" with it.
    let text = "a\xE3b"
    check text.toRunes.len == 3
    check runeSizeAt(text, 1) == 1
    check charToBytePos(text, 2) == 2
    check byteToCharPos(text, 2) == 2
    check deleteCharAt(text, 1) == "ab"

  test "charSubStr copies the source bytes":
    # `runeSubStr` walks with `runeLenAt` and gives up on the truncated tail,
    # returning "". These are the bytes that were actually there.
    let text = "a\xE3b"
    check text.charSubStr(1, 1) == "\xE3"
    check text.charSubStr(1) == "\xE3b"
    check text.charSubStr(0, 2) == "a\xE3"
    check text.charSubStr(0) == text
    check text.charSubStr(3) == ""
    check text.charSubStr(1, 0) == ""
    check "ab\u6F22cd".charSubStr(1, 3) == "b\u6F22c"

  test "charSubStr and charLen tile the text exactly":
    # The invariant the column model rests on: every byte belongs to exactly one
    # column, undecodable bytes included. `runeSubStr`/`runeLen` break it - they
    # step by the width a lead byte advertises, so a truncated tail hands back
    # bytes that belong to the next column.
    for text in [
      "", "abc", "ab\u6F22cd", "a\xE3b", "\xFF\xFE\xFFab", "\xE3", "a\xF0\x9Fb"
    ]:
      var rebuilt = ""
      for col in 0 ..< text.charLen:
        rebuilt.add text.charSubStr(col, 1)
      check rebuilt == text
      check text.charSubStr(0) == text

  test "Extract substring using character positions":
    let text = "ab漢cd"
    # Extract using charToBytePos
    let start0 = charToBytePos(text, 0)
    let end2 = charToBytePos(text, 2)
    check text[start0 ..< end2] == "ab"

    let start2 = charToBytePos(text, 2)
    let end3 = charToBytePos(text, 3)
    check text[start2 ..< end3] == "漢"

    let start3 = charToBytePos(text, 3)
    let end5 = charToBytePos(text, 5)
    check text[start3 ..< end5] == "cd"

suite "Line Wrapping with Unicode":
  test "Wrap calculation with Japanese characters":
    let text = "これは日本語のテストです"
    let charLen = text.charLen
    check charLen == 12 # 12 Japanese characters

    # If maxWidth is 5 characters, calculate wrapped lines
    let maxWidth = 5
    let wrappedLines = ((charLen - 1) div maxWidth) + 1
    check wrappedLines == 3 # (12 - 1) div 5 + 1 = 11 div 5 + 1 = 2 + 1 = 3

  test "Wrap calculation with mixed content":
    let text = "Hello世界World"
    let charLen = text.charLen
    check charLen == 12 # 5 + 2 + 5

    let maxWidth = 8
    let wrappedLines = ((charLen - 1) div maxWidth) + 1
    check wrappedLines == 2 # (12 - 1) div 8 + 1 = 11 div 8 + 1 = 1 + 1 = 2

  test "Extract wrapped line segments":
    let text = "これは日本語のテストです"

    # First wrap: characters 0..4 (5 chars)
    let startByte1 = charToBytePos(text, 0)
    let endByte1 = charToBytePos(text, min(5, text.charLen))
    let segment1 = text[startByte1 ..< endByte1]
    check segment1.charLen == 5

    # Second wrap: characters 5..9 (5 chars)
    let startByte2 = charToBytePos(text, 5)
    let endByte2 = charToBytePos(text, min(10, text.charLen))
    let segment2 = text[startByte2 ..< endByte2]
    check segment2.charLen == 5

    # Third wrap: characters 10..11 (2 chars)
    let startByte3 = charToBytePos(text, 10)
    let endByte3 = charToBytePos(text, text.charLen)
    let segment3 = text[startByte3 ..< endByte3]
    check segment3.charLen == 2

suite "Display Width - runeWidth":
  test "ASCII characters have width 1":
    check runeWidth("a".runeAt(0)) == 1
    check runeWidth("A".runeAt(0)) == 1
    check runeWidth("1".runeAt(0)) == 1
    check runeWidth(" ".runeAt(0)) == 1

  test "CJK characters have width 2":
    check runeWidth("漢".runeAt(0)) == 2
    check runeWidth("字".runeAt(0)) == 2
    check runeWidth("日".runeAt(0)) == 2
    check runeWidth("本".runeAt(0)) == 2
    check runeWidth("한".runeAt(0)) == 2
    check runeWidth("글".runeAt(0)) == 2
    check runeWidth("中".runeAt(0)) == 2
    check runeWidth("文".runeAt(0)) == 2

  test "Emoji have width 2":
    check runeWidth("👋".runeAt(0)) == 2
    check runeWidth("🌍".runeAt(0)) == 2
    check runeWidth("😀".runeAt(0)) == 2

suite "Display Width - displayWidthUpToWithTabs":
  test "Calculates correct width for ASCII":
    let text = "hello"
    check displayWidthUpToWithTabs(text, 0, 4) == 0
    check displayWidthUpToWithTabs(text, 1, 4) == 1
    check displayWidthUpToWithTabs(text, 5, 4) == 5

  test "Calculates correct width for CJK":
    let text = "漢字"
    check displayWidthUpToWithTabs(text, 0, 4) == 0
    check displayWidthUpToWithTabs(text, 1, 4) == 2 # '漢' has width 2
    check displayWidthUpToWithTabs(text, 2, 4) == 4 # '漢字' has width 4

  test "Calculates correct width for mixed text":
    let text = "ab漢cd"
    check displayWidthUpToWithTabs(text, 0, 4) == 0 # Before 'a'
    check displayWidthUpToWithTabs(text, 1, 4) == 1 # After 'a'
    check displayWidthUpToWithTabs(text, 2, 4) == 2 # After 'ab'
    check displayWidthUpToWithTabs(text, 3, 4) == 4 # After 'ab漢' (a=1, b=1, 漢=2)
    check displayWidthUpToWithTabs(text, 4, 4) == 5 # After 'ab漢c'
    check displayWidthUpToWithTabs(text, 5, 4) == 6 # After 'ab漢cd'

  test "Handles tab character":
    let text = "ab\tcd"
    # 'a'=1, 'b'=1, tab expands to next tab stop
    # At position 2, displayWidth=2, next tabStop is 4, so tab adds 2
    check displayWidthUpToWithTabs(text, 2, 4) == 2 # Before tab
    check displayWidthUpToWithTabs(text, 3, 4) == 4
      # After tab (2 + 2 spaces to reach tabStop 4)

  test "Negative charPos returns 0":
    let text = "hello"
    check displayWidthUpToWithTabs(text, -1, 4) == 0
    check displayWidthUpToWithTabs(text, -10, 4) == 0

  test "Invalid tabStop uses default":
    let text = "hello"
    check displayWidthUpToWithTabs(text, 3, 0) == 3 # Uses tabStop=1
    check displayWidthUpToWithTabs(text, 3, -5) == 3 # Uses tabStop=1

suite "Display Width - displayWidthSubstr":
  test "ASCII text":
    let text = "hello world"
    # Within maxWidth=5, we can fit "hello" (5 chars, 5 width)
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 5)
    check charCount == 5
    check actualWidth == 5

  test "CJK text":
    let text = "漢字日本"
    # maxWidth=5 can fit "漢字" (2 chars, 4 width) but not "漢字日" (3 chars, 6 width)
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 5)
    check charCount == 2
    check actualWidth == 4

  test "Mixed text":
    let text = "ab漢cd"
    # maxWidth=4 can fit "ab漢" (3 chars: a=1, b=1, 漢=2)
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 4)
    check charCount == 3
    check actualWidth == 4

  test "With offset":
    let text = "hello漢字world"
    # Starting from char 5 (at '漢'), maxWidth=10
    # "漢字world" = 2+2+5 = 9 width, 7 chars
    let (charCount, actualWidth) = displayWidthSubstr(text, 5, 10)
    check charCount == 7
    check actualWidth == 9

  test "Stops before exceeding maxWidth":
    let text = "a漢b"
    # maxWidth=2 can only fit 'a' (1 width), cannot fit '漢' (would be 3 total)
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 2)
    check charCount == 1
    check actualWidth == 1

  test "Exact fit":
    let text = "漢字"
    # maxWidth=4 exactly fits both characters
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 4)
    check charCount == 2
    check actualWidth == 4

suite "Rendering Width Simulation":
  test "ASCII":
    var displayX = 0
    let text = "hello"
    for rune in text.runes:
      displayX += runeWidth(rune)
    check displayX == 5

  test "CJK":
    var displayX = 0
    let text = "漢字日本"
    for rune in text.runes:
      displayX += runeWidth(rune)
    check displayX == 8 # Each CJK char has width 2

  test "Mixed text":
    var displayX = 0
    let text = "ab漢cd"
    for rune in text.runes:
      displayX += runeWidth(rune)
    check displayX == 6 # a(1) + b(1) + 漢(2) + c(1) + d(1)

  test "Complex text":
    var displayX = 0
    let text = "CJK characters: 漢字 日本語 中文 한글"
    for rune in text.runes:
      displayX += runeWidth(rune)
    # "CJK characters: " = 16 chars (width 16)
    # "漢字 日本語 中文 한글" = 漢(2) + 字(2) + space(1) + 日(2) + 本(2) + 語(2) + space(1) + 中(2) + 文(2) + space(1) + 한(2) + 글(2) = 21
    # Total: 16 + 21 = 37
    check displayX == 37

suite "getCharAtPos":
  test "ASCII string":
    let text = "Hello"
    let (rune0, size0) = getCharAtPos(text, 0)
    check rune0 == Rune('H')
    check size0 == 1

    let (rune4, size4) = getCharAtPos(text, 4)
    check rune4 == Rune('o')
    check size4 == 1

  test "Japanese string":
    let text = "こんにちは"
    let (rune0, size0) = getCharAtPos(text, 0)
    check rune0 == "こ".runeAt(0)
    check size0 == 3

    let (rune2, size2) = getCharAtPos(text, 2)
    check rune2 == "に".runeAt(0)
    check size2 == 3

  test "Mixed content":
    let text = "ab漢cd"
    let (rune2, size2) = getCharAtPos(text, 2)
    check rune2 == "漢".runeAt(0)
    check size2 == 3

    let (rune3, size3) = getCharAtPos(text, 3)
    check rune3 == Rune('c')
    check size3 == 1

  test "Out of bounds returns null rune":
    let text = "Hello"
    let (rune, size) = getCharAtPos(text, 10)
    check rune == Rune(0)
    check size == 0

  test "Empty string":
    let text = ""
    let (rune, size) = getCharAtPos(text, 0)
    check rune == Rune(0)
    check size == 0

suite "deleteCharAt":
  test "Delete ASCII character":
    let text = "Hello"
    check deleteCharAt(text, 0) == "ello"
    check deleteCharAt(text, 2) == "Helo"
    check deleteCharAt(text, 4) == "Hell"

  test "Delete Japanese character":
    let text = "こんにちは"
    check deleteCharAt(text, 0) == "んにちは"
    check deleteCharAt(text, 2) == "こんちは"
    check deleteCharAt(text, 4) == "こんにち"

  test "Delete from mixed content":
    let text = "ab漢cd"
    check deleteCharAt(text, 2) == "abcd"
    check deleteCharAt(text, 0) == "b漢cd"
    check deleteCharAt(text, 4) == "ab漢c"

  test "Delete out of bounds returns original":
    let text = "Hello"
    check deleteCharAt(text, 10) == "Hello"

  test "Delete from empty string":
    let text = ""
    check deleteCharAt(text, 0) == ""

suite "displayWidth":
  test "ASCII string":
    check displayWidth("Hello") == 5
    check displayWidth("") == 0

  test "CJK string":
    check displayWidth("漢字") == 4
    check displayWidth("日本語") == 6

  test "Mixed content":
    check displayWidth("ab漢cd") == 6 # a(1) + b(1) + 漢(2) + c(1) + d(1)
    check displayWidth("Hello世界") == 9 # 5 + 4

  test "Emoji":
    check displayWidth("👋🌍") == 4

suite "displayWidthUpTo":
  test "ASCII string":
    let text = "Hello"
    check displayWidthUpTo(text, 0) == 0
    check displayWidthUpTo(text, 3) == 3
    check displayWidthUpTo(text, 5) == 5

  test "CJK string":
    let text = "漢字日本"
    check displayWidthUpTo(text, 0) == 0
    check displayWidthUpTo(text, 1) == 2 # '漢' has width 2
    check displayWidthUpTo(text, 2) == 4 # '漢字' has width 4
    check displayWidthUpTo(text, 4) == 8

  test "Mixed content":
    let text = "ab漢cd"
    check displayWidthUpTo(text, 0) == 0
    check displayWidthUpTo(text, 2) == 2 # 'ab'
    check displayWidthUpTo(text, 3) == 4 # 'ab漢'
    check displayWidthUpTo(text, 5) == 6 # 'ab漢cd'

  test "Beyond string length":
    let text = "Hello"
    check displayWidthUpTo(text, 10) == 5

suite "Parenthesis utilities":
  test "isOpeningParen":
    check isOpeningParen('(') == true
    check isOpeningParen('[') == true
    check isOpeningParen('{') == true
    check isOpeningParen('"') == true
    check isOpeningParen('\'') == true
    check isOpeningParen(')') == false
    check isOpeningParen('a') == false

  test "getClosingChar":
    check getClosingChar('(') == ')'
    check getClosingChar('[') == ']'
    check getClosingChar('{') == '}'
    check getClosingChar('"') == '"'
    check getClosingChar('\'') == '\''
    check getClosingChar('a') == '\0'

  test "isMatchingPair":
    check isMatchingPair('(', ')') == true
    check isMatchingPair('[', ']') == true
    check isMatchingPair('{', '}') == true
    check isMatchingPair('"', '"') == true
    check isMatchingPair('\'', '\'') == true
    check isMatchingPair('(', ']') == false
    check isMatchingPair('a', 'b') == false

suite "Bracket utilities (Rune)":
  test "isOpenBracket":
    check isOpenBracket(Rune('(')) == true
    check isOpenBracket(Rune('[')) == true
    check isOpenBracket(Rune('{')) == true
    check isOpenBracket(Rune(')')) == false
    check isOpenBracket(Rune('"')) == false
    check isOpenBracket(Rune('a')) == false

  test "isCloseBracket":
    check isCloseBracket(Rune(')')) == true
    check isCloseBracket(Rune(']')) == true
    check isCloseBracket(Rune('}')) == true
    check isCloseBracket(Rune('(')) == false
    check isCloseBracket(Rune('"')) == false

  test "isBracket":
    check isBracket(Rune('(')) == true
    check isBracket(Rune(')')) == true
    check isBracket(Rune('[')) == true
    check isBracket(Rune(']')) == true
    check isBracket(Rune('{')) == true
    check isBracket(Rune('}')) == true
    check isBracket(Rune('a')) == false
    check isBracket(Rune('"')) == false

  test "correspondingCloseBracket":
    check correspondingCloseBracket(Rune('(')) == Rune(')')
    check correspondingCloseBracket(Rune('[')) == Rune(']')
    check correspondingCloseBracket(Rune('{')) == Rune('}')
    check correspondingCloseBracket(Rune('a')) == Rune('a') # Returns same

  test "correspondingOpenBracket":
    check correspondingOpenBracket(Rune(')')) == Rune('(')
    check correspondingOpenBracket(Rune(']')) == Rune('[')
    check correspondingOpenBracket(Rune('}')) == Rune('{')
    check correspondingOpenBracket(Rune('a')) == Rune('a') # Returns same

suite "4-byte Emoji (Surrogate Pairs) Tests":
  test "charToBytePos with 4-byte emoji":
    # 🎉 (U+1F389) is a 4-byte emoji
    let text = "a🎉b"
    check charToBytePos(text, 0) == 0 # 'a' at byte 0
    check charToBytePos(text, 1) == 1 # '🎉' at byte 1
    check charToBytePos(text, 2) == 5 # 'b' at byte 5 (1 + 4)
    check charToBytePos(text, 3) == 6 # After 'b'

  test "byteToCharPos with 4-byte emoji":
    let text = "a🎉b"
    check byteToCharPos(text, 0) == 0 # Byte 0 -> char 0 ('a')
    check byteToCharPos(text, 1) == 1 # Byte 1 -> char 1 ('🎉')
    check byteToCharPos(text, 5) == 2 # Byte 5 -> char 2 ('b')

  test "getCharAtPos with 4-byte emoji":
    let text = "a🎉b"
    let (rune1, size1) = getCharAtPos(text, 1)
    check rune1 == "🎉".runeAt(0)
    check size1 == 4

  test "deleteCharAt with 4-byte emoji":
    let text = "a🎉b"
    check deleteCharAt(text, 1) == "ab"

  test "displayWidth with 4-byte emoji":
    check displayWidth("🎉") == 2
    check displayWidth("a🎉b") == 4 # 1 + 2 + 1

  test "displayWidthUpTo with 4-byte emoji":
    let text = "a🎉b"
    check displayWidthUpTo(text, 0) == 0
    check displayWidthUpTo(text, 1) == 1 # 'a'
    check displayWidthUpTo(text, 2) == 3 # 'a' + '🎉'
    check displayWidthUpTo(text, 3) == 4 # 'a' + '🎉' + 'b'

  test "Multiple 4-byte emoji":
    let text = "🎉🎊🎁"
    check text.len == 12 # 3 * 4 bytes
    check charToBytePos(text, 0) == 0
    check charToBytePos(text, 1) == 4
    check charToBytePos(text, 2) == 8
    check charToBytePos(text, 3) == 12
    check displayWidth(text) == 6 # 3 * 2

  test "Mixed ASCII, CJK, and 4-byte emoji":
    let text = "Hi漢🎉字!"
    # 'H'=1B, 'i'=1B, '漢'=3B, '🎉'=4B, '字'=3B, '!'=1B = 13 bytes
    check text.len == 13
    check charToBytePos(text, 0) == 0 # 'H'
    check charToBytePos(text, 1) == 1 # 'i'
    check charToBytePos(text, 2) == 2 # '漢'
    check charToBytePos(text, 3) == 5 # '🎉'
    check charToBytePos(text, 4) == 9 # '字'
    check charToBytePos(text, 5) == 12 # '!'
    check charToBytePos(text, 6) == 13 # End
    # Display width: H(1) + i(1) + 漢(2) + 🎉(2) + 字(2) + !(1) = 9
    check displayWidth(text) == 9

  test "Emoji sequences (skin tone modifiers)":
    # 👋🏻 = 👋 (U+1F44B, 4 bytes) + 🏻 (U+1F3FB, 4 bytes)
    let text = "👋🏻"
    check text.len == 8 # 4 + 4 bytes
    # Note: This counts as 2 Unicode code points, though it renders as 1 glyph
    let (_, size0) = getCharAtPos(text, 0)
    check size0 == 4
    let (_, size1) = getCharAtPos(text, 1)
    check size1 == 4

suite "Robustness Tests - Edge Cases and Invalid Input":
  test "charToBytePos with position beyond string length":
    let text = "Hello"
    check charToBytePos(text, 100) == 5 # Should return end of string

  test "byteToCharPos with position beyond string length":
    let text = "Hello"
    check byteToCharPos(text, 100) == 5 # Should return character count

  test "charToBytePos with negative position":
    let text = "Hello"
    check charToBytePos(text, -1) == 0 # Should handle gracefully

  test "displayWidthUpTo with position beyond string length":
    let text = "漢字"
    check displayWidthUpTo(text, 100) == 4 # Should return total width

  test "displayWidthSubstr with offset beyond string length":
    let text = "Hello"
    let (charCount, actualWidth) = displayWidthSubstr(text, 100, 10)
    # When offset > string length, charCount becomes negative (currentChar - startChar)
    # This reflects current implementation behavior
    check charCount == -95 # 5 - 100
    check actualWidth == 0

  test "displayWidthSubstr with maxWidth 0":
    let text = "Hello"
    let (charCount, actualWidth) = displayWidthSubstr(text, 0, 0)
    check charCount == 0
    check actualWidth == 0

  test "deleteCharAt with negative position":
    let text = "Hello"
    check deleteCharAt(text, -1) == "Hello" # Should return original

  test "getCharAtPos with negative position":
    let text = "Hello"
    let (rune, size) = getCharAtPos(text, -1)
    check rune == Rune(0)
    check size == 0

  test "Single character strings":
    check charToBytePos("a", 0) == 0
    check charToBytePos("a", 1) == 1
    check charToBytePos("漢", 0) == 0
    check charToBytePos("漢", 1) == 3
    check charToBytePos("🎉", 0) == 0
    check charToBytePos("🎉", 1) == 4

  test "Very long string with mixed content":
    var text = ""
    for i in 0 ..< 100:
      text.add("a漢🎉")
    # Each iteration: 'a'=1B + '漢'=3B + '🎉'=4B = 8 bytes, 3 chars
    check text.len == 800
    check charToBytePos(text, 0) == 0
    check charToBytePos(text, 3) == 8 # After first "a漢🎉"
    check charToBytePos(text, 300) == 800 # End of string

  test "String with only spaces":
    let text = "     "
    check charToBytePos(text, 2) == 2
    check displayWidth(text) == 5
    check deleteCharAt(text, 2) == "    "

  test "String with tabs":
    let text = "\t\t"
    check charToBytePos(text, 0) == 0
    check charToBytePos(text, 1) == 1
    check charToBytePos(text, 2) == 2
    let (rune, size) = getCharAtPos(text, 0)
    check rune == Rune('\t')
    check size == 1

  test "String with newlines":
    let text = "a\nb\nc"
    check charToBytePos(text, 0) == 0 # 'a'
    check charToBytePos(text, 1) == 1 # '\n'
    check charToBytePos(text, 2) == 2 # 'b'
    let (rune, size) = getCharAtPos(text, 1)
    check rune == Rune('\n')
    check size == 1

  test "String with null character":
    let text = "a\x00b"
    check text.len == 3
    check charToBytePos(text, 1) == 1
    let (rune, size) = getCharAtPos(text, 1)
    check rune == Rune(0)
    check size == 1

  test "Unicode control characters":
    # Zero-width space (U+200B)
    let text = "a\u200Bb"
    check text.len == 5 # 'a'=1B + ZWSP=3B + 'b'=1B
    let (_, size) = getCharAtPos(text, 1)
    check size == 3

  test "displayWidthSubstr edge cases":
    # Empty string
    let (c1, w1) = displayWidthSubstr("", 0, 10)
    check c1 == 0
    check w1 == 0

    # maxWidth exactly matches one wide character
    let (c2, w2) = displayWidthSubstr("漢字", 0, 2)
    check c2 == 1
    check w2 == 2

    # maxWidth is 1 (cannot fit any wide character)
    let (c3, w3) = displayWidthSubstr("漢字", 0, 1)
    check c3 == 0
    check w3 == 0

  test "Bracket functions with non-bracket characters":
    check isOpenBracket(Rune('a')) == false
    check isOpenBracket(Rune(' ')) == false
    check isOpenBracket(Rune('\n')) == false
    check isCloseBracket(Rune('z')) == false
    check isBracket(Rune('!')) == false

  test "correspondingBracket with edge cases":
    # Non-bracket returns itself
    check correspondingCloseBracket(Rune(' ')) == Rune(' ')
    check correspondingOpenBracket(Rune('\t')) == Rune('\t')
    check correspondingCloseBracket("漢".runeAt(0)) == "漢".runeAt(0)

  test "Repeated operations on same string":
    let text = "テスト文字列"
    # Ensure repeated calls produce consistent results
    for _ in 0 ..< 10:
      check charToBytePos(text, 3) == 9
      check byteToCharPos(text, 9) == 3
      check displayWidth(text) == 12
      let (rune, size) = getCharAtPos(text, 2)
      check rune == "ト".runeAt(0)
      check size == 3

suite "isAdjacentPair":
  test "Empty parens":
    check isAdjacentPair("()", 0) == true
    check isAdjacentPair("[]", 0) == true
    check isAdjacentPair("{}", 0) == true

  test "Quotes":
    check isAdjacentPair("\"\"", 0) == true
    check isAdjacentPair("''", 0) == true

  test "Non-adjacent pair":
    check isAdjacentPair("(hello)", 0) == false
    check isAdjacentPair("[items]", 0) == false

  test "Not a pair":
    check isAdjacentPair("ab", 0) == false
    check isAdjacentPair(")(", 0) == false
    check isAdjacentPair("][", 0) == false

  test "Out of bounds":
    check isAdjacentPair("()", -1) == false
    check isAdjacentPair("()", 1) == false
    check isAdjacentPair("", 0) == false

  test "Adjacent pair in middle of line":
    check isAdjacentPair("a()b", 1) == true
    check isAdjacentPair("a[]b", 1) == true
    check isAdjacentPair("func()end", 4) == true

  test "Non-matching adjacent chars":
    check isAdjacentPair("(]", 0) == false
    check isAdjacentPair("[}", 0) == false

  test "With spaces inside":
    check isAdjacentPair("[   ]", 0) == false
    check isAdjacentPair("( )", 0) == false

  test "Truncated lead byte: the pair is still found at its character column":
    # charLen counts the bytes after a truncated lead byte as characters of
    # their own, so a column past one exceeds runeLen. Bounds-checking with
    # runeLen used to make the pair invisible here.
    let line = "x\xF0()"
    check line.charLen == 4
    check line.charLen > line.runeLen
    check isAdjacentPair(line, 2) == true
    check isAdjacentBracketPair(line, 2) == true

suite "unicode_utils - char metric on undecodable bytes":
  test "truncateToCharsWithSuffix cuts at the character the caller asked for":
    check "abc".truncateToCharsWithSuffix(5) == "abc"
    check "abcdef".truncateToCharsWithSuffix(3) == "abc..."
    check "\u6F22\u5B57abc".truncateToCharsWithSuffix(2) == "\u6F22\u5B57..."
    check "abcdef".truncateToCharsWithSuffix(3, "~") == "abc~"

  test "truncateToCharsWithSuffix keeps a truncated lead byte addressable":
    # `runeSubStr` cannot address past a truncated lead byte and falls back to
    # returning the whole string, which turned the preview into the full line.
    # 0xF0 advertises four bytes but only three remain, so it is one character.
    let line = "abc\xF0de"
    check line.charLen == 6
    check line.truncateToCharsWithSuffix(4) == "abc\xF0..."
    check line.truncateToCharsWithSuffix(6) == line

  test "truncateToCharsWithSuffix decides on the boundary character alone":
    # The cut is inferred from the kept slice being shorter than the source
    # rather than from a length of the whole string, so the exact-fit and
    # one-over cases must still differ.
    check "abcd".truncateToCharsWithSuffix(4) == "abcd"
    check "abcde".truncateToCharsWithSuffix(4) == "abcd..."
    check "".truncateToCharsWithSuffix(3) == ""
    # A budget of nothing yields nothing, as truncateToWidthWithSuffix does:
    # the suffix would overflow the space the caller measured as empty.
    check "a".truncateToCharsWithSuffix(0) == ""
    check "".truncateToCharsWithSuffix(0) == ""

  test "truncateToWidthWithSuffix slices instead of re-encoding":
    # `$rune` turns an undecodable byte into a three-byte replacement, so the
    # result grew past the width just measured. The kept part is a slice of the
    # input, so every original byte survives verbatim.
    let line = "ab\xFFcdef"
    # 0xFF is drawn as `<ff>`: four cells, so keeping it needs 2 + 4 + 3.
    check line.truncateToWidthWithSuffix(9) == "ab\xFF..."
    check line.truncateToWidthWithSuffix(6) == "ab..."
    check line.truncateToWidthWithSuffix(99) == line
    check "abcdef".truncateToWidthWithSuffix(4) == "a..."
    check "abcdef".truncateToWidthWithSuffix(2) == ""
    check "abcdef".truncateToWidthWithSuffix(0) == ""

  test "an undecodable byte keeps its identity and is drawn as <e3>":
    # It must be distinguishable from a U+FFFD the file itself holds, and the
    # byte has to be recoverable, or the user cannot see what they are editing.
    let (broken, size) = "\xE3ab".charAtByte(0)
    check size == 1
    check broken.isInvalidByteRune
    check broken.invalidByteValue == 0xE3'u8
    check broken.invalidByteText == "<e3>"
    check broken.charWidth == 4

    let (real, realSize) = "\uFFFDx".charAtByte(0)
    check realSize == 3
    check not real.isInvalidByteRune
    check real.charWidth == 1
    check broken != real

  test "runeSizeAt admits exactly the well-formed sequences":
    # Unicode Table 3-7, row by row, each paired with the byte just outside the
    # range it allows. This table is the definition of a character for every
    # column index in the editor, so it is pinned rather than sampled.
    const cases = [
      ("\xC2\x80", 2), # U+0080, shortest two-byte form
      ("\xC1\xBF", 1), # overlong: C0/C1 lead nothing
      ("\xDF\xBF", 2), # U+07FF
      ("\xE0\xA0\x80", 3), # U+0800
      ("\xE0\x9F\xBF", 1), # overlong three-byte form
      ("\xE1\x80\x80", 3),
      ("\xEC\xBF\xBF", 3),
      ("\xED\x9F\xBF", 3), # U+D7FF, just below the surrogates
      ("\xED\xA0\x80", 1), # U+D800 written as three bytes
      ("\xEE\x80\x80", 3),
      ("\xEF\xBF\xBF", 3), # U+FFFF
      ("\xF0\x90\x80\x80", 4), # U+10000
      ("\xF0\x8F\xBF\xBF", 1), # overlong four-byte form
      ("\xF1\x80\x80\x80", 4),
      ("\xF3\xBF\xBF\xBF", 4),
      ("\xF4\x8F\xBF\xBF", 4), # U+10FFFF, the last code point
      ("\xF4\x90\x80\x80", 1), # one past U+10FFFF
      ("\xF5\x80\x80\x80", 1), # F5..FF lead nothing
      ("\xF0\x90\x41\x80", 1), # third byte is not a continuation byte
      ("\xF0\x90\x80\x41", 1), # fourth byte is not a continuation byte
      ("\xE3\x81", 1), # truncated: the bytes are simply not there yet
      ("\x80", 1), # a continuation byte with nothing leading it
    ]
    for (text, want) in cases:
      check text.runeSizeAt(0) == want

  test "a sequence that is not a character stands byte by byte":
    # These all have the continuation-byte shape a lead byte asks for, so the
    # advertised length alone accepts them: an overlong `/`, a surrogate written
    # as three bytes, and a code point above U+10FFFF. Decoded, they would be
    # drawn as an ordinary `/`, a replacement char and an out-of-range rune --
    # the screen would say something the bytes do not.
    for text in ["\xE0\x80\xAF", "\xED\xB2\x80", "\xF5\x80\x80\x80", "\xC0\x80"]:
      check text.charLen == text.len
      for i in 0 ..< text.len:
        let (r, size) = text.charAtByte(i)
        check size == 1
        check r.isInvalidByteRune
        check r.invalidByteValue == text[i].uint8

  test "the characters either side of the excluded ranges still decode":
    # U+D7FF sits just below the surrogate block and U+10FFFF is the last code
    # point; rejecting their neighbours must not reject them.
    for text in ["\xED\x9F\xBF", "\xF4\x8F\xBF\xBF", "\xE3\x81\x82", "\xC2\x80"]:
      check text.charLen == 1
      let (r, size) = text.charAtByte(0)
      check size == text.len
      check not r.isInvalidByteRune

  test "an undecodable byte never reaches a cell as a lone surrogate":
    # `$` on the carrier rune emits bytes no UTF-8 reader accepts, so the cell
    # sanitiser has to catch any that get past the renderer.
    let (broken, _) = "\xFF".charAtByte(0)
    check sanitizeCellRune(broken) == Rune(0xFFFD)

  test "charDisplayWidth counts the cells an undecodable byte takes":
    check "ab".charDisplayWidth == 2
    check "a\xE3b".charDisplayWidth == 6

  test "charSubStr takes the whole tail for any count past the end":
    # A count at least as large as the remaining bytes cannot end before the
    # text does, so it must behave like the omitted-count form.
    let text = "a\xE3b"
    check text.charSubStr(0, int.high) == text
    check text.charSubStr(0, 99) == text
    check text.charSubStr(0, text.len) == text
    check text.charSubStr(1, 99) == "\xE3b"

  test "runeSizeAt outside the text yields 0 instead of reading out of bounds":
    check "ab".runeSizeAt(2) == 0
    check "ab".runeSizeAt(99) == 0
    check "ab".runeSizeAt(-1) == 0
    check "".runeSizeAt(0) == 0

suite "unicode_utils - setRuneCell":
  test "ASCII rune writes only the main cell, returns width 1":
    var buf = newBuffer(10, 3)
    let style = defaultStyle()
    let w = setRuneCell(buf, 2, 1, "a".runeAt(0), style)
    check w == 1
    check buf[2, 1].symbol == "a"
    # Adjacent cell is untouched (remains default)
    check buf[3, 1].symbol == " "

  test "C0 control rune is substituted with a single space":
    var buf = newBuffer(10, 3)
    let style = defaultStyle()
    # ESC (0x1B) must never reach a cell as a raw control sequence
    let w = setRuneCell(buf, 2, 1, Rune(0x1B), style)
    check w == 1
    check buf[2, 1].symbol == " "

  test "DEL (0x7F) rune is substituted with a single space":
    var buf = newBuffer(10, 3)
    let style = defaultStyle()
    let w = setRuneCell(buf, 2, 1, Rune(0x7F), style)
    check w == 1
    check buf[2, 1].symbol == " "

  test "isC0Control covers C0 range and DEL but not printable ASCII":
    check isC0Control(Rune(0x00))
    check isC0Control(Rune(0x08))
    check isC0Control(Rune(0x1B))
    check isC0Control(Rune(0x1F))
    check isC0Control(Rune(0x7F))
    check not isC0Control(Rune(0x20))
    check not isC0Control(Rune(0x41))
    check not isC0Control(Rune(0x80))

  test "sanitizeCellRune substitutes only C0 controls and DEL":
    check sanitizeCellRune(Rune(0x1B)) == ' '.Rune
    check sanitizeCellRune(Rune(0x00)) == ' '.Rune
    check sanitizeCellRune(Rune(0x7F)) == ' '.Rune
    check sanitizeCellRune(Rune(0x41)) == 'A'.Rune
    check sanitizeCellRune(Rune(0x80)) == Rune(0x80)

  test "Wide rune writes main and continuation cell, returns width 2":
    var buf = newBuffer(10, 3)
    let style = defaultStyle()
    let w = setRuneCell(buf, 2, 1, "日".runeAt(0), style)
    check w == 2
    check buf[2, 1].symbol == "日"
    # Continuation cell at x+1 is empty string with the same style
    check buf[3, 1].symbol == ""
    check buf[3, 1].style == style

  test "Wide rune at right edge does not write beyond buffer":
    var buf = newBuffer(3, 3)
    let style = defaultStyle()
    # x+1 is the last valid cell - continuation is written
    let w = setRuneCell(buf, 1, 0, "日".runeAt(0), style)
    check w == 2
    check buf[1, 0].symbol == "日"
    check buf[2, 0].symbol == ""

  test "Wide rune at exact buffer right edge skips continuation":
    var buf = newBuffer(3, 3)
    let style = defaultStyle()
    # x=2 is the last valid col; x+1=3 is out of bounds - skip continuation
    let w = setRuneCell(buf, 2, 0, "日".runeAt(0), style)
    check w == 2
    check buf[2, 0].symbol == "日"

  test "Combining mark folds into the preceding base cell, returns width 0":
    var buf = newBuffer(10, 3)
    let style = defaultStyle()
    var x = 0
    x += setRuneCell(buf, x, 0, "e".runeAt(0), style)
    check x == 1
    let w = setRuneCell(buf, x, 0, Rune(0x0301), style) # combining acute
    check w == 0
    check x == 1 # no advance
    # The mark merged onto 'e' rather than landing on the next column.
    check buf[0, 0].symbol == "e" & $Rune(0x0301)
    check buf[1, 0].symbol == " " # next column untouched

  test "Combining mark on a wide base keeps the continuation cell":
    var buf = newBuffer(10, 3)
    let style = defaultStyle()
    var x = 0
    x += setRuneCell(buf, x, 0, "漢".runeAt(0), style)
    check x == 2
    discard setRuneCell(buf, x, 0, Rune(0x0301), style)
    check buf[0, 0].symbol == "漢" & $Rune(0x0301)
    check buf[1, 0].symbol == "" # shadow cell still present

  test "Variation selector folds into the preceding base cell":
    var buf = newBuffer(10, 3)
    let style = defaultStyle()
    var x = 0
    x += setRuneCell(buf, x, 0, "▶".runeAt(0), style)
    let w = setRuneCell(buf, x, 0, Rune(0xFE0E), style) # VARIATION SELECTOR-15
    check w == 0
    check buf[0, 0].symbol == "▶" & $Rune(0xFE0E)

  test "Leading zero-width rune has no base and is a no-op":
    var buf = newBuffer(10, 3)
    let style = defaultStyle()
    let w = setRuneCell(buf, 0, 0, Rune(0x0301), style)
    check w == 0
    check buf[0, 0].symbol == " " # nothing written, cell stays default

  test "Per-rune render loop keeps decomposed text in one cell":
    # Mirrors the per-rune setCell loop used by the editor render path.
    var buf = newBuffer(10, 1)
    let text = "e" & $Rune(0x0301) & "X" # "éX" in NFD
    var x = 0
    for r in text.runes:
      x += setRuneCell(buf, x, 0, r, defaultStyle())
    check x == 2
    check buf[0, 0].symbol == "e" & $Rune(0x0301)
    check buf[1, 0].symbol == "X"

suite "unicode_utils - sanitizeForDisplay":
  test "Empty string":
    check sanitizeForDisplay("") == ""

  test "C0 range and DEL are substituted with a single space":
    for i in 0x00 .. 0x1F:
      let s = $Rune(i)
      check sanitizeForDisplay(s) == " "
    check sanitizeForDisplay($Rune(0x7F)) == " "
    # Tab, LF, CR, ESC are all C0 controls
    check sanitizeForDisplay("\t") == " "
    check sanitizeForDisplay("\n") == " "
    check sanitizeForDisplay("\r") == " "
    check sanitizeForDisplay("\x1B") == " "

  test "Printable ASCII is preserved":
    check sanitizeForDisplay("ABCaz09!@#") == "ABCaz09!@#"
    check sanitizeForDisplay("Hello, World!") == "Hello, World!"
    check sanitizeForDisplay(" ") == " "
    check sanitizeForDisplay("~") == "~"

  test "C1 range 0x80 is not substituted":
    check sanitizeForDisplay($Rune(0x80)) == $Rune(0x80)
    check not isC0Control(Rune(0x80))

  test "Mixed C0 controls with normal text":
    check sanitizeForDisplay("a\x00b\x1B c\x7Fd") == "a b  c d"
    check sanitizeForDisplay("\x1B[2J") == " [2J"
    check sanitizeForDisplay("pre\x1Bpost") == "pre post"

  test "Preserves wide characters and emoji while sanitizing controls":
    check sanitizeForDisplay("漢字") == "漢字"
    check sanitizeForDisplay("👋🌍") == "👋🌍"
    check sanitizeForDisplay("漢\x00字🎉\x1B👋") == "漢 字🎉 👋"
    check sanitizeForDisplay("日\x00本\x1F語") == "日 本 語"

  test "displayWidth stays consistent after sanitization":
    # Controls have displayWidth 1 via runeWidth fast path, same as space
    for s in ["a\x00b", "a\x1Bb", "\x1B[2J", "漢\x00字", "a\tb"]:
      check displayWidth(sanitizeForDisplay(s)) == displayWidth(s)
    # Mixed wide + control keeps width: each wide 2, control->space 1
    let mixed = "漢\x00🎉\x1B"
    check displayWidth(sanitizeForDisplay(mixed)) == 2 + 1 + 2 + 1

  test "Idempotent double sanitization":
    let s = "a\x00b\x1B漢\x7F字"
    let once = sanitizeForDisplay(s)
    check sanitizeForDisplay(once) == once

  test "Combining marks are not sanitized":
    let eAcute = "e" & $Rune(0x0301)
    check sanitizeForDisplay(eAcute) == eAcute
    let zwjSeq = "👨" & $Rune(0x200D) & "👩"
    check sanitizeForDisplay(zwjSeq) == zwjSeq

  test "Null and DEL interleaved":
    check sanitizeForDisplay("\x00\x00") == "  "
    check sanitizeForDisplay("\x7F\x7F") == "  "
    check sanitizeForDisplay("\x00a\x7F") == " a "

suite "truncateToWidthWithSuffix":
  test "returns empty string when maxWidth <= 0":
    check truncateToWidthWithSuffix("hello", 0) == ""
    check truncateToWidthWithSuffix("hello", -2) == ""

  test "returns empty string when suffix is wider than maxWidth":
    let suffix = "~~~~" # display width 4
    check truncateToWidthWithSuffix("hello", 2, suffix) == ""

  test "returns original text when it fits within maxWidth":
    check truncateToWidthWithSuffix("hello", 10) == "hello"
    check truncateToWidthWithSuffix("hello", 5) == "hello"

  test "handles empty text":
    check truncateToWidthWithSuffix("", 10) == ""
    check truncateToWidthWithSuffix("", 0) == ""

  test "uses default suffix \"...\"":
    let result = truncateToWidthWithSuffix("hello world", 8)
    check result == "hello..."
    check displayWidth(result) <= 8

  test "truncates ASCII text correctly":
    let result = truncateToWidthWithSuffix("hello world", 8, "~")
    check result == "hello w~"
    check displayWidth(result) <= 8

  test "truncates mixed half/full-width text":
    let result = truncateToWidthWithSuffix("ab漢cd", 4, "~")
    check result == "ab~"
    check displayWidth(result) <= 4

  test "truncates full-width chars exactly at boundary with suffix":
    let result = truncateToWidthWithSuffix("日本語", 5, "~")
    check result == "日本~"
    check displayWidth(result) <= 5

  test "suffix fits exactly when text is one full-width char":
    let result = truncateToWidthWithSuffix("日本", 3, "~")
    check result == "日~"
    check displayWidth(result) <= 3

suite "mayAbsorbAtSeam":
  test "false for text whose bytes all stand on their own":
    check not "hello".mayAbsorbAtSeam
    check not "".mayAbsorbAtSeam
    check not "\u65e5\u672c\u8a9e".mayAbsorbAtSeam

  test "true when a lead byte was left without the bytes it advertised":
    check "x\xF0".mayAbsorbAtSeam
    check "caf\xE9".mayAbsorbAtSeam
    check "\xF0\x9F".mayAbsorbAtSeam

  test "false for a lead byte no character can start with":
    # 0xF8 announced a five-byte form, which left UTF-8 in RFC 3629. Nothing
    # written after it can make those bytes a character, so the seam cannot
    # move and each byte keeps its own column however much follows.
    let text = "A\xF8\x80\x80\x80"
    check text.charLen == 5
    check not text.mayAbsorbAtSeam
    check (text & "\x80").charLen == 6

  test "true only while a real lead byte is still short of its bytes":
    # 0xF0 leads a four-byte character: truncated to three it can still absorb,
    # and the window has to look three bytes back to see it.
    let text = "A\xF0\x9F\x98"
    check text.mayAbsorbAtSeam
    check (text & "\x81").charLen == 2

  test "seam is measured against a given byte, not only the end":
    # A lead byte left truncated part-way through a line takes what is written
    # next to it just as one at the end does.
    let line = "\xF0a"
    check line.charLen == 2
    check line.mayAbsorbAtSeam(1)
    check not line.mayAbsorbAtSeam(0)

  test "false when the advertised bytes are not continuation bytes":
    # 0xF0 has four bytes here but they do not belong to it, so it stands alone
    # and nothing written next to this text changes how it counts.
    check "x\xF0abc".charLen == 5
    check not "x\xF0abc".mayAbsorbAtSeam
