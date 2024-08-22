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

proc inc*(d: var WordDictionary, word: Runes) {.inline.} =
  ## Increment a value

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

proc getCKeywords(): seq[Runes] {.compileTime.} =
  for s in cKeywords: result.add s.toRunes

proc getCppKeywords(): seq[Runes] {.compileTime.} =
  for s in cppKeywords: result.add s.toRunes

proc getCsharpKeywords(): seq[Runes] {.compileTime.} =
  for s in csharpKeywords: result.add s.toRunes

proc getHaskellKeywords(): seq[Runes] {.compileTime.} =
  for s in haskellKeywords: result.add s.toRunes

proc getJavaKeywords(): seq[Runes] {.compileTime.} =
  for s in javaKeywords: result.add s.toRunes

proc getJavaScriptKeywords(): seq[Runes] {.compileTime.} =
  for s in javaScriptkeywords: result.add s.toRunes

proc getNimKeywords(): seq[Runes] {.compileTime.} =
  for s in NimKeywords: result.add s.toRunes
  for s in NimBooleans: result.add s.toRunes
  for s in NimSpecialVars: result.add s.toRunes
  for s in NimPragmas: result.add s.toRunes
  for s in NimBuiltins: result.add s.toRunes
  for s in NimStdLibs: result.add s.toRunes

proc getPythonKeywords(): seq[Runes] {.compileTime.} =
  for s in pythonKeywords: result.add s.toRunes

proc getRustKeywords(): seq[Runes] {.compileTime.} =
  for s in rustKeywords: result.add s.toRunes

proc getTextFromLangKeywords*(lang: SourceLanguage): seq[Runes] =
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
  exclude: Runes,
  lang: SourceLanguage = SourceLanguage.langNone) =
    ## Update word dictionary from the text.

    for word in text.enumerateWords:
      if exclude != word and not d.contains(word): d.add word

    # Get reserved words for the language.
    for word in getTextFromLangKeywords(lang):
      if exclude != word and not d.contains(word): d.add word

proc update*(
  d: var WordDictionary,
  buffers: seq[Runes],
  exclude: Runes,
  lang: SourceLanguage = SourceLanguage.langNone) =
    ## Update word dictionary from the text.

    var runes: Runes
    for b in buffers: runes.add b & ru' '

    d.update(runes, exclude, lang)
