import std/unittest

import pkg/results

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
