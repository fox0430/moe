#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

## Word Dictionary for auto-completion
##
## This module provides a CritBitTree-based word dictionary for efficient
## prefix-based word lookup. It collects words from buffers and language
## keywords, tracking usage frequency to prioritize commonly used words.

import std/[algorithm, critbits, sequtils, unicode]

import pkg/unicodedb/properties

import
  syntax/[
    highlite, syntaxc, syntaxcpp, syntaxcsharp, syntaxhaskell, syntaxjava,
    syntaxjavascript, syntaxnim, syntaxpython, syntaxrust, syntaxshell, syntaxtypescript,
  ]

type WordDictionary* = CritBitTree[int]
  ## Word dictionary using CritBitTree for efficient prefix-based lookup.
  ## The value is the number of times the word has been used in completions,
  ## allowing prioritization of frequently used words.

const
  ## Characters that can appear in words (Unicode categories)
  LetterCharacter = ctgLu + ctgLl + ctgLt + ctgLm + ctgLo + ctgNl
  CombiningCharacter = ctgMn + ctgMc
  DecimalDigitCharacter = ctgNd
  ConnectingCharacter = ctgPc
  FormattingCharacter = ctgCf

  SucceedingCharacter* =
    LetterCharacter + CombiningCharacter + DecimalDigitCharacter + ConnectingCharacter +
    FormattingCharacter

proc contains*(wordDictionary: WordDictionary, word: string): bool {.inline.} =
  ## Returns true if `word` is in the dictionary.
  critbits.contains(wordDictionary, word)

proc add*(d: var WordDictionary, word: string) {.inline.} =
  ## Add a word to the dictionary if it doesn't already exist.
  if not d.contains(word):
    d[word] = 0

proc incUsage*(d: var WordDictionary, word: string) {.inline.} =
  ## Increment the usage count for a word.
  critbits.inc(d, word)

proc collect*(wordDictionary: WordDictionary, prefix: string): seq[string] =
  ## Collect words matching the prefix, sorted by usage count (descending).

  wordDictionary.pairsWithPrefix(prefix).toSeq.sortedByIt(it.val).reversed.mapIt(it.key)

# Language keyword getters

proc getCKeywords(): seq[string] {.compileTime.} =
  for s in cKeywords:
    result.add s

proc getCppKeywords(): seq[string] {.compileTime.} =
  for s in cppKeywords:
    result.add s

proc getCsharpKeywords(): seq[string] {.compileTime.} =
  for s in csharpKeywords:
    result.add s

proc getHaskellKeywords(): seq[string] {.compileTime.} =
  for s in haskellKeywords:
    result.add s

proc getJavaKeywords(): seq[string] {.compileTime.} =
  for s in javaKeywords:
    result.add s

proc getJavaScriptKeywords(): seq[string] {.compileTime.} =
  for s in javaScriptkeywords:
    result.add s

proc getNimKeywords(): seq[string] {.compileTime.} =
  for s in NimKeywords:
    result.add s
  for s in NimBooleans:
    result.add s
  for s in NimSpecialVars:
    result.add s
  for s in NimPragmas:
    result.add s
  for s in NimBuiltins:
    result.add s
  for s in NimStdLibs:
    result.add s

proc getPythonKeywords(): seq[string] {.compileTime.} =
  for s in pythonKeywords:
    result.add s

proc getRustKeywords(): seq[string] {.compileTime.} =
  for s in rustKeywords:
    result.add s
  for s in rustBuiltins:
    result.add s

proc getShellKeywords(): seq[string] {.compileTime.} =
  for s in shellKeywords:
    result.add s

proc getTypeScriptKeywords(): seq[string] {.compileTime.} =
  for s in typescriptKeywords:
    result.add s

# Pre-computed keyword tables for efficiency
const
  CKeywordList = getCKeywords()
  CppKeywordList = getCppKeywords()
  CsharpKeywordList = getCsharpKeywords()
  HaskellKeywordList = getHaskellKeywords()
  JavaKeywordList = getJavaKeywords()
  JavaScriptKeywordList = getJavaScriptKeywords()
  NimKeywordList = getNimKeywords()
  PythonKeywordList = getPythonKeywords()
  RustKeywordList = getRustKeywords()
  ShellKeywordList = getShellKeywords()
  TypeScriptKeywordList = getTypeScriptKeywords()

proc getLanguageKeywords*(lang: SourceLanguage): seq[string] =
  ## Get the keywords for a specific language.
  ## Returns pre-computed keyword lists for efficiency.
  case lang
  of langC:
    @CKeywordList
  of langCpp:
    @CppKeywordList
  of langCsharp:
    @CsharpKeywordList
  of langHaskell:
    @HaskellKeywordList
  of langJava:
    @JavaKeywordList
  of langJavaScript, langJsx:
    @JavaScriptKeywordList
  of langPython:
    @PythonKeywordList
  of langNim:
    @NimKeywordList
  of langRust:
    @RustKeywordList
  of langShell:
    @ShellKeywordList
  of langTypeScript, langTsx:
    @TypeScriptKeywordList
  else:
    @[]

iterator enumerateWords*(text: string): string =
  ## Enumerate words from text.
  ## Words are sequences of characters that can appear in identifiers.
  ## Single-character words are filtered out.
  var word = ""
  var inWord = false

  for rune in text.runes:
    let cat = rune.unicodeCategory
    if cat in SucceedingCharacter:
      if not inWord:
        # Start of a new word - must begin with a letter
        if cat in LetterCharacter:
          inWord = true
          word = $rune
      else:
        word.add($rune)
    else:
      if inWord and word.len >= 2:
        yield word
      word = ""
      inWord = false

  # Don't forget the last word
  if inWord and word.len >= 2:
    yield word

proc update*(
    d: var WordDictionary,
    text: string,
    exclude: string = "",
    lang: SourceLanguage = langNone,
) =
  ## Update word dictionary from text.
  ## Optionally excludes a specific word (e.g., the word being typed).
  ## Optionally adds language keywords.
  for word in text.enumerateWords:
    if word != exclude and not d.contains(word):
      d.add(word)

  # Add language keywords
  for word in getLanguageKeywords(lang):
    if word != exclude and not d.contains(word):
      d.add(word)

proc update*(
    d: var WordDictionary,
    buffers: seq[string],
    exclude: string = "",
    lang: SourceLanguage = langNone,
) =
  ## Update word dictionary from multiple buffers.
  var combined = ""
  for b in buffers:
    combined.add(b)
    combined.add(" ")

  d.update(combined, exclude, lang)

proc clear*(d: var WordDictionary) =
  ## Clear all entries from the dictionary.
  d = WordDictionary()

proc len*(d: WordDictionary): int {.inline.} =
  ## Return the number of entries in the dictionary.
  critbits.len(d)
