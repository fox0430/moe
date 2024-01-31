#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[algorithm, critbits, sequtils, sugar]

import pkg/unicodedb/properties

import unicodeext
import syntax/[highlite, syntaxc, syntaxcpp, syntaxcsharp, syntaxhaskell,
               syntaxjava, syntaxjavascript, syntaxnim, syntaxpython,
               syntaxrust]

type
  WordDictionary* = CritBitTree[int]
    # `WordDictionary.val` is number of times used in completions.

const
  SucceedingCharacter* =
    LetterCharacter +
    CombiningCharacter +
    DecimalDigitCharacter +
    ConnectingCharacter +
    FormattingCharacter +
    FormattingCharacter

proc contains(wordDictionary: WordDictionary, word: Runes): bool {.inline.} =
  ## Returns true if `word` is in `WordDictionary.word` or false if not found.

  wordDictionary.contains($word)

proc add*(d: var WordDictionary, word: Runes) {.inline.} =
  ## Add words in the text to the wordDictionary.

  if not d.contains(word): d[$word] = 0

proc incNumOfUsed*(d: var WordDictionary, word: Runes) {.inline.} =
  ## Increment `WordDictionary.numOfUsed`

  d.inc($word)

proc collect*(
  wordDictionary: WordDictionary,
  word: Runes): seq[Runes] =
    ## Collect words for suggestion from `wordDictionary`

    result.add wordDictionary.pairsWithPrefix($word)
      .toSeq
      .sortedByIt(it.val)
      .reversed
      .mapIt(it.key.toRunes)

proc getTextFromBuffer*[T](
  buffer: T,
  firstDeletedIndex, lastDeletedIndex: int): Runes =

    result.add buffer.toRunes

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
  for s in NimKeywords: result.add toRunes(s & " ")
  for s in NimBooleans: result.add toRunes(s & " ")
  for s in NimSpecialVars: result.add toRunes(s & " ")
  for s in NimPragmas: result.add toRunes(s & " ")
  for s in NimBuiltins: result.add toRunes(s & " ")
  for s in NimStdLibs: result.add toRunes(s & " ")

proc getPythonKeywords(): Runes {.compileTime.} =
  for s in pythonKeywords: result.add toRunes(s & " ")

proc getRustKeywords(): Runes {.compileTime.} =
  for s in rustKeywords: result.add toRunes(s & " ")

proc getTextFromLangKeywords*(lang: SourceLanguage): Runes =
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

iterator enumerateWords*(text: Runes): Runes =
  for word in split(
    text,
    r => r.unicodeCategory notin SucceedingCharacter,
    true):
      if word[0].unicodeCategory notin LetterCharacter or word.len < 2:
        continue

      yield word

proc update*(
  d: var WordDictionary,
  text: Runes,
  exclude: Runes = ru"",
  lang: SourceLanguage = SourceLanguage.langNone) =
    ## Update word dictionary from the text.

    for word in text.enumerateWords:
      if exclude != word: d.add word

    # Get reserved words for the language.
    d.add getTextFromLangKeywords(lang)

proc update*(
  d: var WordDictionary,
  buffers: seq[Runes],
  exclude: Runes = ru"",
  lang: SourceLanguage = SourceLanguage.langNone) =
    ## Update word dictionary from the text.

    var runes: Runes
    for b in buffers: runes.add b

    d.update(runes, exclude, lang)
