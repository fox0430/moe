import sugar
import unicodedb, unicodedb/properties
import unicodeext

iterator enumerateIdentifiers*(runes: seq[Rune]): seq[Rune] =
  # The name "enumerateIdentifiers" is a bit misleading because this proc also collects keywords in some programming language.
  const
    letterCharacter = ctgLu + ctgLl + ctgLt + ctgLm + ctgLo + ctgNl
    combiningCharacter = ctgMn + ctgMc
    decimalDigitCharacter = ctgNd
    connectingCharacter = ctgPc
    formattingCharacter = ctgCf
  const
    firstCharacter = letterCharacter
    nonFirstCharacter = letterCharacter + combiningCharacter + decimalDigitCharacter + connectingCharacter + formattingCharacter + formattingCharacter

  for token in split(runes, r => r.unicodeCategory notin nonFirstCharacter, true):
    if token[0].unicodeCategory notin firstCharacter: continue
    yield token
