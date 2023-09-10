#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[sugar, critbits, options, sequtils, strutils]
import pkg/unicodedb/properties
import unicodeext, bufferstatus, algorithm, osext, gapbuffer
import syntax/[highlite, syntaxc, syntaxcpp, syntaxcsharp, syntaxhaskell,
               syntaxjava, syntaxjavascript, syntaxnim, syntaxpython,
               syntaxrust]

type
  # `WordDictionary.val` is number of times used in the autocomplete.
  WordDictionary* = CritBitTree[int]

const
  LetterCharacter = ctgLu + ctgLl + ctgLt + ctgLm + ctgLo + ctgNl
  CombiningCharacter = ctgMn + ctgMc
  DecimalDigitCharacter = ctgNd
  ConnectingCharacter = ctgPc
  FormattingCharacter = ctgCf

  FirstCharacter = LetterCharacter
  SucceedingCharacter = LetterCharacter +
                        CombiningCharacter +
                        DecimalDigitCharacter +
                        ConnectingCharacter +
                        FormattingCharacter +
                        FormattingCharacter

iterator enumerateWords*(runes: Runes): Runes =
  for word in split(
    runes,
    r => r.unicodeCategory notin SucceedingCharacter,
    true):
      if word[0].unicodeCategory notin FirstCharacter: continue
      yield word

proc contains(wordDictionary: WordDictionary, word: Runes): bool {.inline.} =
  ## Returns true if `word` is in `WordDictionary.word` or false if not found.

  wordDictionary.contains($word)

proc addWordToDictionary*(wordDictionary: var WordDictionary, text: Runes) =
  ## Add words to the wordDictionary.

  for word in enumerateWords(text):
    if not wordDictionary.contains(word):
      wordDictionary[$word] = 0

proc incNumOfUsed*(wordDictionary: var WordDictionary, word: Runes) {.inline.} =
  ## Increment `WordDictionary.numOfUsed`

  wordDictionary.inc($word)

proc extractNeighborWord*(
  runes: Runes,
  pos: int): Option[tuple[word: Runes, first, last: int]] =
    ## Extract a word from `runes` based on position.

    block:
      let
        r = runes[pos]
        unicodeCategory = r.unicodeCategory
      if (runes.len == 0) or
         (pos notin runes.low .. runes.high) or
         ((r != '/'.ru) and (unicodeCategory notin SucceedingCharacter)): return

    var
      first = pos
      last = pos

    block:
      template r: Rune = runes[first - 1]

      while first - 1 >= 0 and r.unicodeCategory in SucceedingCharacter:
        dec(first)

    block:
      template r: Rune = runes[last + 1]

      while last + 1 <= runes.high and r.unicodeCategory in SucceedingCharacter:
        inc(last)

    return some((runes[first .. last], first, last))

proc extractNeighborPath*(
  runes: Runes,
  pos: int): Option[tuple[path: Runes, first, last: int]] =
    ## Extract a path from `runes` based on position.

    if (runes.len == 0) or (pos notin runes.low .. runes.high):
      return

    var
      first = pos
      last = pos

    block:
      template r: Rune = runes[first - 1]

      # The starting point of the path is after '"' or ''' or spaces.
      while (first - 1 >= 0) and
            ((r != '"') and (r != '\'') and (r.toCh notin Whitespace)): dec(first)

    block:
      template r: Rune = runes[last + 1]

      # The ending point of the path is before '"' or ''' or spaces.
      while (last + 1 <= runes.high) and
            ((r != '"') and (r != '\'') and (r.toCh notin Whitespace)): inc(last)

    return some((runes[first..last], first, last))

proc isCharacterInWord*(r: Rune): bool =
  r.unicodeCategory in SucceedingCharacter

proc collectSuggestions*(
  wordDictionary: CritBitTree[int],
  word: Runes): seq[Runes] =
    ## Collect words for suggestion from `wordDictionary`

    let pairs = collect:
      for item in wordDictionary.pairsWithPrefix($word): item

    result.add pairs.sortedByIt(it.val).reversed.mapIt(it.key.toRunes)

proc getTextInBuffers*(
  bufStatus: seq[BufferStatus],
  firstDeletedIndex, lastDeletedIndex: int): Runes =

    for i, buf in bufStatus:
      # 0 is current bufStatus
      if i == 0:
        var runeBuf = buf.buffer.toRunes
        for _ in firstDeletedIndex .. lastDeletedIndex:
          runeBuf.delete(firstDeletedIndex)
        result = runeBuf
      else:
        result.add buf.buffer.toRunes

proc getCKeywords(): Runes {.compileTime.} =
  for s in cKeywords: result.add toRunes(s & " ")

proc getCppKeywords(): Runes {.compileTime.} =
  for s in cppKeywords: result.add toRunes(s & " ")

proc getCsharpKeywords(): Runes {.compileTime.} =
  for s in csharpKeywords: result.add toRunes(s & " ")

proc getHaskellKeywords(): Runes {.compileTime.} =
  for s in haskellKeywords: result.add toRunes(s & " ")

proc getJavaKeywords(): Runes {.compileTime.} =
  for s in javaKeywords: result.add toRunes(s & " ")

proc getJavaScriptKeywords(): Runes {.compileTime.} =
  for s in javaScriptkeywords: result.add toRunes(s & " ")

proc getNimKeywords(): Runes {.compileTime.} =
  for s in nimKeywords: result.add toRunes(s & " ")
  for s in nimBooleans: result.add toRunes(s & " ")
  for s in nimSpecialVars: result.add toRunes(s & " ")
  for s in nimPragmas: result.add toRunes(s & " ")
  for s in nimBuiltins: result.add toRunes(s & " ")
  for s in nimStdLibs: result.add toRunes(s & " ")

proc getPythonKeywords(): Runes {.compileTime.} =
  for s in pythonKeywords: result.add toRunes(s & " ")

proc getRustKeywords(): Runes {.compileTime.} =
  for s in rustKeywords: result.add toRunes(s & " ")

proc getTextInLangKeywords*(lang: SourceLanguage): Runes =
  case lang:
    of SourceLanguage.langC:
      result = getCKeywords()
    of SourceLanguage.langCpp:
      result = getCppKeywords()
    of SourceLanguage.langCsharp:
      result = getCsharpKeywords()
    of SourceLanguage.langHaskell:
      result = getHaskellKeywords()
    of SourceLanguage.langJava:
      result = getJavaKeywords()
    of SourceLanguage.langJavaScript:
      result = getJavaScriptKeywords()
    of SourceLanguage.langPython:
      result = getPythonKeywords()
    of SourceLanguage.langNim:
      result = getNimKeywords()
    of SourceLanguage.langRust:
      result = getRustKeywords()
    else:
      discard

proc getPathList*(path: Runes): Runes =
  ## Return Path list for the autocomplete.

  let
    (head, tail) = splitPathExt($path)
    paths = walkDir(head.expandTilde).toSeq.mapIt(it.path.getPathTail)

  for item in paths:
    if item.startsWith(tail):
      result &= (item & " ").ru
