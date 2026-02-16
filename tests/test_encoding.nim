import std/unittest

import ../src/moepkg/encoding

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
