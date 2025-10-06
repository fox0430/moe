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
