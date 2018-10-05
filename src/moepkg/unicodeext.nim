import unicode, strutils, sequtils
import unicodedb/widths
export unicode

type CharacterEncoding* = enum
  utf8, utf16Be, utf16Le, utf32Be, utf32Le, unknown

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
    if (not (0xD800 <= curr and curr <= 0xDBFF)) or (not (0xDC00 <= next and next <= 0xDFFF)): return false
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
    if (not (0xD800 <= curr and curr <= 0xDBFF)) or (not (0xDC00 <= next and next <= 0xDFFF)): return false
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

proc detectCharacterEncoding*(s: string): CharacterEncoding =
  ## sの文字符号化形式を推測する
  ## 現時点ではUnicodeの符号化形式にしか対応してない
  ## ASCIIの文字しか含まれてない場合にはCharacterEncoding.utf8を返す
  ## 符号化形式が不明な場合にはCharacterEncoding.unknownを返す

  # UTF-8のBOMチェック
  if s.len >= 3 and s[0..2] == "\xEF\xBB\xBF": return CharacterEncoding.utf8

  if s.len >= 4:
    # UTF-32のBOMチェック
    if s[0..3] == "\x00\x00\xFE\xFF": return CharacterEncoding.utf32Be
    if s[0..3] == "\xFF\xFE\x00\x00": return CharacterEncoding.utf32Le
    # UTF-16のBOMチェック
    if s[0..1] == "\xFE\xFF": return CharacterEncoding.utf16Be
    if s[0..1] == "\xFF\xFE": return CharacterEncoding.utf16Le

  if s.validateUtf8 == -1: return CharacterEncoding.utf8
  if s.validateUtf16Be: return CharacterEncoding.utf16Be
  if s.validateUtf16Le: return CharacterEncoding.utf16Le
  if s.validateUtf32Be: return CharacterEncoding.utf32Be
  if s.validateUtf32Le: return CharacterEncoding.utf32Le

  return CharacterEncoding.unknown

proc width*(c: Rune): int =
  if int(c) > 0x10FFFF: return 1
  case c.unicodeWidth
  of UnicodeWidth.uwdtNarrow, UnicodeWidth.uwdtHalf, UnicodeWidth.uwdtAmbiguous, UnicodeWidth.uwdtNeutral: 1
  else: 2

proc width*(runes: seq[Rune]): int =
  for c in runes: result += width(c)

proc toRune*(c: char): Rune =
  doAssert(ord(c) <= 127)
  ($c).toRunes[0]

proc toRune*(x: int): Rune = Rune(x)

proc `==`*(c: Rune, x: int): bool = c == toRune(x)
proc `==`*(c: Rune, x: char): bool = c == toRune(x)

proc ru*(c: char): Rune = toRune(c)

proc ru*(s: string): seq[Rune] = s.toRunes

proc canConvertToChar*(c: Rune): bool =
  return ($c).len == 1

proc toChar*(c: Rune): char =
  doAssert(canConvertToChar(c), "Failed to convert Rune to char")
  return ($c)[0]

proc numberOfBytes*(firstByte: char): int =
  if (int(firstByte) shr 7) == 0b0: return 1
  if (int(firstByte) shr 5) == 0b110: return 2
  if (int(firstByte) shr 4) == 0b1110: return 3
  if (int(firstByte) shr 3) == 0b11110: return 4
  doAssert(false, "Invalid UTF-8 first byte.")

proc isDigit*(c: Rune): bool =
  let s = $c
  return s.len == 1 and strutils.isDigit(s[0])

proc isDigit*(runes: seq[Rune]): bool = all(runes, isDigit)

proc isSpace*(c: Rune): bool =
  return unicode.isSpace($c)

proc isPunct*(c: Rune): bool =
  let s = $c
  return s.len == 1 and s[0] in {'!', '"', '#', '$', '%', '$', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '=', '}'}

proc countRepeat*(runes: seq[Rune], charSet: set[char], start: int): int =
  for i in start ..< runes.len:
    let s = $runes[i]
    if s.len > 1 or (not (s[0] in charSet)): break
    inc(result)
