import std/[sugar, critbits, options, sequtils]
import pkg/unicodedb/properties
import unicodeext, bufferstatus, algorithm
import syntax/[highlite, syntaxnim, syntaxc, syntaxcpp, syntaxcsharp,
               syntaxjava, syntaxpython, syntaxjavascript]

type
  # `WordDictionary.val` is number of times used in the autocomplete.
  WordDictionary* = CritBitTree[int]

const
  letterCharacter = ctgLu + ctgLl + ctgLt + ctgLm + ctgLo + ctgNl
  combiningCharacter = ctgMn + ctgMc
  decimalDigitCharacter = ctgNd
  connectingCharacter = ctgPc
  formattingCharacter = ctgCf

  firstCharacter = letterCharacter
  succeedingCharacter = letterCharacter +
                        combiningCharacter +
                        decimalDigitCharacter +
                        connectingCharacter +
                        formattingCharacter +
                        formattingCharacter

iterator enumerateWords*(runes: seq[Rune]): seq[Rune] =
  for word in split(runes, r => r.unicodeCategory notin succeedingCharacter, true):
    if word[0].unicodeCategory notin firstCharacter: continue
    yield word

# Returns true if `word` is in `WordDictionary.word` or false if not found.
proc contains(wordDictionary: WordDictionary, word: seq[Rune]): bool {.inline.} =
  wordDictionary.contains($word)

# Get `WordDictionary.numOfUsed` by `word`
proc getNumOfUsed(wordDictionary: WordDictionary, word: seq[Rune]): int {.inline.} =
  wordDictionary[$word]

# Add words to the wordDictionary.
proc addWordToDictionary*(wordDictionary: var WordDictionary, text: seq[Rune]) =
  for word in enumerateWords(text):
    if not wordDictionary.contains(word):
      wordDictionary[$word] = 0

# Increment `WordDictionary.numOfUsed`
proc incNumOfUsed*(wordDictionary: var WordDictionary, word: seq[Rune]) =
  wordDictionary.inc($word)

proc extractNeighborWord*(
  runes: seq[Rune],
  pos: int): Option[tuple[word: seq[Rune], first, last: int]] =

  if runes.len == 0 or pos notin
     runes.low .. runes.high or runes[pos].unicodeCategory notin
     succeedingCharacter: return

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

# Collect words for suggestion from `wordDictionary`
proc collectSuggestions*(wordDictionary: CritBitTree[int], word: seq[Rune]): seq[seq[Rune]] =
  let pairs = collect:
    for item in wordDictionary.pairsWithPrefix($word): item

  result.add pairs.sortedByIt(it.val).reversed.mapIt(it.key.toRunes)

proc getTextInBuffers*(
  bufStatus: seq[BufferStatus],
  firstDeletedIndex, lastDeletedIndex: int): seq[Rune] =

  for i, buf in bufStatus:
    # 0 is current bufStatus
    if i == 0:
      var runeBuf = buf.buffer.toRunes
      for _ in firstDeletedIndex .. lastDeletedIndex:
        runeBuf.delete(firstDeletedIndex)
      result = runeBuf
    else:
      result.add buf.buffer.toRunes

proc getNimKeywords(): seq[Rune] {.compiletime.} =
  for s in nimKeywords: result.add toRunes(s & " ")
  for s in nimBooleans: result.add toRunes(s & " ")
  for s in nimSpecialVars: result.add toRunes(s & " ")
  for s in nimPragmas: result.add toRunes(s & " ")
  for s in nimBuiltins: result.add toRunes(s & " ")

proc getCKeywords(): seq[Rune] {.compiletime.} =
  for s in cKeywords: result.add toRunes(s & " ")

proc getCppKeywords(): seq[Rune] {.compiletime.} =
  for s in cppKeywords: result.add toRunes(s & " ")

proc getCsharpKeywords(): seq[Rune] {.compiletime.} =
  for s in csharpKeywords: result.add toRunes(s & " ")

proc getJavaKeywords(): seq[Rune] {.compiletime.} =
  for s in javaKeywords: result.add toRunes(s & " ")

proc getPythonKeywords(): seq[Rune] {.compiletime.} =
  for s in pythonKeywords: result.add toRunes(s & " ")

proc getJavaScriptKeywords(): seq[Rune] {.compiletime.} =
  for s in javaScriptkeywords: result.add toRunes(s & " ")

proc getTextInLangKeywords*(lang: SourceLanguage): seq[Rune] =
  case lang:
    of SourceLanguage.langNim:
      result = getNimKeywords()
    of SourceLanguage.langC:
      result = getCKeywords()
    of SourceLanguage.langCpp:
      result = getCppKeywords()
    of SourceLanguage.langCsharp:
      result = getCsharpKeywords()
    of SourceLanguage.langJava:
      result = getJavaKeywords()
    of SourceLanguage.langPython:
      result = getPythonKeywords()
    of SourceLanguage.langJavaScript:
      result = getJavaScriptKeywords()
    else:
      discard
