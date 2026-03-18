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

import ../src/moepkg/[buffer, unicode_utils, render_utils]
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

suite "charToBytePosCached":
  test "Basic caching":
    var cache = CursorPosCache()
    let text = "こんにちは"

    # First call - cache miss
    let pos1 = charToBytePosCached(text, 2, cache, 0, 1)
    check pos1 == 6
    check cache.charPos == 2
    check cache.bytePos == 6
    check cache.line == 0
    check cache.changeSeq == 1

  test "Cache hit - same position":
    var cache = CursorPosCache()
    let text = "こんにちは"

    discard charToBytePosCached(text, 2, cache, 0, 1)
    let pos2 = charToBytePosCached(text, 2, cache, 0, 1)
    check pos2 == 6

  test "Cache hit - forward movement":
    var cache = CursorPosCache()
    let text = "こんにちは"

    discard charToBytePosCached(text, 2, cache, 0, 1)
    let pos3 = charToBytePosCached(text, 4, cache, 0, 1)
    check pos3 == 12

  test "Cache hit - backward movement":
    var cache = CursorPosCache()
    let text = "こんにちは"

    discard charToBytePosCached(text, 4, cache, 0, 1)
    let pos1 = charToBytePosCached(text, 1, cache, 0, 1)
    check pos1 == 3

  test "Cache invalidation on line change":
    var cache = CursorPosCache()
    let text = "こんにちは"

    discard charToBytePosCached(text, 2, cache, 0, 1)
    let pos2 = charToBytePosCached(text, 2, cache, 1, 1) # Different line
    check pos2 == 6
    check cache.line == 1

  test "Cache invalidation on changeSeq change":
    var cache = CursorPosCache()
    let text = "こんにちは"

    discard charToBytePosCached(text, 2, cache, 0, 1)
    let pos2 = charToBytePosCached(text, 2, cache, 0, 2) # Different changeSeq
    check pos2 == 6
    check cache.changeSeq == 2

  test "Position 0 or negative":
    var cache = CursorPosCache()
    let text = "Hello"

    check charToBytePosCached(text, 0, cache, 0, 1) == 0
    check charToBytePosCached(text, -1, cache, 0, 1) == 0

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

  test "charToBytePosCached with 4-byte emoji":
    var cache = CursorPosCache()
    let text = "a🎉b🎊c"
    # 'a'=1B, '🎉'=4B, 'b'=1B, '🎊'=4B, 'c'=1B = 11 bytes

    let pos1 = charToBytePosCached(text, 1, cache, 0, 1)
    check pos1 == 1 # '🎉' starts at byte 1

    let pos3 = charToBytePosCached(text, 3, cache, 0, 1) # Forward movement
    check pos3 == 6 # '🎊' starts at byte 6 (1 + 4 + 1)

    let pos4 = charToBytePosCached(text, 4, cache, 0, 1)
    check pos4 == 10 # 'c' starts at byte 10

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

  test "charToBytePosCached robustness":
    var cache = CursorPosCache()
    let text = "Hello"

    # Multiple calls with same parameters should be consistent
    for i in 0 ..< 10:
      check charToBytePosCached(text, 3, cache, 0, 1) == 3

    # Rapid line changes
    for line in 0 ..< 5:
      check charToBytePosCached(text, 2, cache, line, 1) == 2
      check cache.line == line

    # Rapid changeSeq changes
    for seq in 1 .. 5:
      check charToBytePosCached(text, 2, cache, 0, seq) == 2
      check cache.changeSeq == seq

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

suite "findMatchingCloseOnLine":
  test "Simple paren":
    check findMatchingCloseOnLine("(hello)", 0) == 6

  test "Simple bracket":
    check findMatchingCloseOnLine("[hello]", 0) == 6

  test "Simple brace":
    check findMatchingCloseOnLine("{hello}", 0) == 6

  test "Nested parens":
    # ((hello))
    check findMatchingCloseOnLine("((hello))", 0) == 8 # outer
    check findMatchingCloseOnLine("((hello))", 1) == 7 # inner

  test "Mixed nested brackets":
    # (a[b{c}d]e)
    check findMatchingCloseOnLine("(a[b{c}d]e)", 0) == 10 # outer (
    check findMatchingCloseOnLine("(a[b{c}d]e)", 2) == 8 # [
    check findMatchingCloseOnLine("(a[b{c}d]e)", 4) == 6 # {

  test "No matching close":
    check findMatchingCloseOnLine("(hello", 0) == -1

  test "Not an opening bracket":
    check findMatchingCloseOnLine("hello)", 0) == -1

  test "Quote is not handled":
    check findMatchingCloseOnLine("\"hello\"", 0) == -1

  test "Empty parens":
    check findMatchingCloseOnLine("()", 0) == 1

  test "With prefix":
    check findMatchingCloseOnLine("func(args)", 4) == 9

suite "findMatchingOpenOnLine":
  test "Simple paren":
    check findMatchingOpenOnLine("(hello)", 6) == 0

  test "Simple bracket":
    check findMatchingOpenOnLine("[hello]", 6) == 0

  test "Simple brace":
    check findMatchingOpenOnLine("{hello}", 6) == 0

  test "Nested parens":
    # ((hello))
    check findMatchingOpenOnLine("((hello))", 8) == 0 # outer
    check findMatchingOpenOnLine("((hello))", 7) == 1 # inner

  test "Mixed nested brackets":
    # (a[b{c}d]e)
    check findMatchingOpenOnLine("(a[b{c}d]e)", 10) == 0 # outer )
    check findMatchingOpenOnLine("(a[b{c}d]e)", 8) == 2 # ]
    check findMatchingOpenOnLine("(a[b{c}d]e)", 6) == 4 # }

  test "No matching open":
    check findMatchingOpenOnLine("hello)", 5) == -1

  test "Not a closing bracket":
    check findMatchingOpenOnLine("(hello", 4) == -1

  test "Quote is not handled":
    check findMatchingOpenOnLine("\"hello\"", 6) == -1

  test "Empty parens":
    check findMatchingOpenOnLine("()", 1) == 0

  test "With prefix":
    check findMatchingOpenOnLine("func(args)", 9) == 4

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
