import unicode
export unicode

proc width*(c: Rune): int = return if c.toUTF8.len == 1: 1 else: 2

proc width*(runes: seq[Rune]): int =
  for c in runes: result += width(c)

proc toRune*(c: char): Rune = ($c).toRunes[0]

proc toRune*(x: int): Rune = char(x).toRune

proc u8*(c: char): Rune = toRune(c)

proc u8*(s: string): seq[Rune] = s.toRunes
