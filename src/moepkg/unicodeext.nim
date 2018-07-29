import unicode, strutils, sequtils
export unicode

proc width*(c: Rune): int = return if int32(c) <= 127: 1 else: 2

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
