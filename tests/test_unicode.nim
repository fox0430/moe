import std/unittest

import ../src/moepkg/[gapbuffer, buffer, unicode_utils]

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
    let maxWidth = 5

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
