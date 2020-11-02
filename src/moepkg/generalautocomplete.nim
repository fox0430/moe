import sugar, critbits, options
import unicodedb, unicodedb/properties
import unicodetext

const
  letterCharacter = ctgLu + ctgLl + ctgLt + ctgLm + ctgLo + ctgNl
  combiningCharacter = ctgMn + ctgMc
  decimalDigitCharacter = ctgNd
  connectingCharacter = ctgPc
  formattingCharacter = ctgCf
const
  firstCharacter = letterCharacter
  succeedingCharacter = letterCharacter + combiningCharacter + decimalDigitCharacter + connectingCharacter + formattingCharacter + formattingCharacter

iterator enumerateWords*(runes: seq[Rune]): seq[Rune] =
  for word in split(runes, r => r.unicodeCategory notin succeedingCharacter, true):
    if word[0].unicodeCategory notin firstCharacter: continue
    yield word

proc makeWordDictionary*(runes: seq[Rune]): CritBitTree[void] =
  for word in enumerateWords(runes):
    result.incl($word)

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

proc isCharacterInWord*(r: Rune): bool =
  r.unicodeCategory in succeedingCharacter

proc collectSuggestions*(wordDictionary: CritBitTree[void], word: seq[Rune]): seq[seq[Rune]] =
  collect(newSeq):
    for item in itemsWithPrefix(wordDictionary, $word):
      item.toRunes
