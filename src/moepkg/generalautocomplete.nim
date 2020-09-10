import sugar, critbits, options
import unicodedb, unicodedb/properties
import unicodeext

const
  letterCharacter = ctgLu + ctgLl + ctgLt + ctgLm + ctgLo + ctgNl
  combiningCharacter = ctgMn + ctgMc
  decimalDigitCharacter = ctgNd
  connectingCharacter = ctgPc
  formattingCharacter = ctgCf
const
  firstCharacter = letterCharacter
  succeedingCharacter = letterCharacter + combiningCharacter + decimalDigitCharacter + connectingCharacter + formattingCharacter + formattingCharacter

iterator enumerateIdentifiers*(runes: seq[Rune]): seq[Rune] =
  # The name "enumerateIdentifiers" is a bit misleading because this proc also collects keywords in some programming language.
  for identifier in split(runes, r => r.unicodeCategory notin succeedingCharacter, true):
    if identifier[0].unicodeCategory notin firstCharacter: continue
    yield identifier

proc makeIdentifierDictionary*(runes: seq[Rune]): CritBitTree[void] =
  for identifier in enumerateIdentifiers(runes):
    result.incl($identifier)

proc extractNeighborWord*(runes: seq[Rune], pos: int): Option[tuple[word: seq[Rune], first, last: int]] =
  if runes.len == 0 or pos notin runes.low .. runes.high or runes[pos].unicodeCategory notin succeedingCharacter: return

  var
    first = pos
    last = pos

  while first-1 >= 0 and runes[first-1].unicodeCategory in succeedingCharacter:
    dec(first)
  while last+1 <= runes.high and runes[last+1].unicodeCategory in succeedingCharacter:
    inc(last)

  return some((runes[first..last], first, last))

proc isCharacterInIdentifier*(r: Rune): bool =
  r.unicodeCategory in succeedingCharacter

proc collectSuggestions*(idetifierDictionary: CritBitTree[void], word: seq[Rune]): seq[seq[Rune]] =
  collect(newSeq):
    for item in itemsWithPrefix(idetifierDictionary, $word):
      item.toRunes
