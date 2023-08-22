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

import std/[unittest, sequtils, sugar, critbits, options]
import moepkg/unicodeext
import moepkg/syntax/[highlite, syntaxc, syntaxcpp, syntaxcsharp, syntaxhaskell,
                      syntaxjava, syntaxjavascript, syntaxnim, syntaxpython,
                      syntaxrust]

import moepkg/autocomplete {.all.}

const code = ru"""proc fibonacci(n: int): int =
  if n == 0: return 0
  if n == 1: return 1
  return fibonacci(n - 1) + fibonacci(n - 2)"""

suite "autocomplete: enumerateWords":
  test "Case 1":
    const
      expectedResult = @["proc", "fibonacci", "n", "int", "int", "if", "n",
        "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].map(s => s.ru)

      actualResult = collect(newSeq):
        for x in enumerateWords(code):
          x

    check actualResult == expectedResult

suite "autocomplete: enumerateWords":
  test "Case 1":
    var dictionary: WordDictionary
    const allWords = @["proc", "fibonacci", "n", "int", "int", "if", "n",
      "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].deduplicate

    dictionary.addWordToDictionary(code)

    for x in allWords:
      check dictionary.contains(x)
    for x in dictionary.items:
      check allWords.contains(x)

suite "autocomplete: extractNeighborWord":
  test "Case 1":
    const text = ru"This is a sample text."

    proc validate(pos: int, expected: string) =
      let wordFirstLast = extractNeighborWord(text, pos)
      if expected.len > 0:
        check wordFirstLast.get.word == expected.ru
      else:
        check wordFirstLast.isNone

    validate(0, "This")
    validate(3, "This")
    validate(4, "")
    validate(7, "")
    validate(8, "a")
    validate(20, "text")
    validate(21, "")

suite "autocomplete: collectSuggestions":
  test "Case 1":
    var dictionary: WordDictionary
    dictionary.addWordToDictionary(code)

    dictionary.incNumOfUsed("proc".toRunes)

    block:
      let suggestions = dictionary.collectSuggestions("p".toRunes)
      check suggestions[0] == "proc".toRunes

    dictionary.incNumOfUsed("pop".toRunes)

    block:
      let suggestions = dictionary.collectSuggestions("p".toRunes)
      check suggestions[0] == "proc".toRunes
      check suggestions[1] == "pop".toRunes

    dictionary.incNumOfUsed("pop".toRunes)

    block:
      let suggestions = dictionary.collectSuggestions("p".toRunes)
      check suggestions[0] == "pop".toRunes
      check suggestions[1] == "proc".toRunes

suite "autocomplete: extractNeighborPath":
  proc extractNeighborPathTest(
    testIndex: int,
    expectVal: Option[tuple[path: Runes, first, last: int]],
    text: Runes,
    position: int) =
      ## Check return values of suggestionwindow.isPath

      let testTitle = "Case " & $testIndex & ": " & $text & ", " & $position
      test testTitle:
        check expectVal == extractNeighborPath(`text`, position)

  const
    TestCases: seq[tuple[expectVal: Option[tuple[path: Runes, first, last: int]], text: Runes, position: int]] = @[
      (expectVal: none(tuple[path: Runes, first, last: int]), text: "".ru, position: 0),
      (expectVal: some((path: "/home".ru, first: 0, last: "/home".ru.high)), text: "/home".ru, position: 0),
      (expectVal: some((path: "/home/user/".ru, first: 0, last: "/home/user/".ru.high)), text: "/home/user/".ru, position: 0),
      (expectVal: some((path: "../test".ru, first: 0, last: "../test".ru.high)), text: "../test".ru, position: 0),
      (expectVal: some((path: "/home/user/a".ru, first: 5, last: 16)), text: "test /home/user/a test".ru, position: 16),
      (expectVal: some((path: "../test/test2/".ru, first: 5, last: 18)), text: "test ../test/test2/ test".ru, position: 18),
      (expectVal: some((path: "~/".ru, first: 0, last: "~/".ru.high)), text: "~/".ru, position: 0),
      (expectVal: some((path: "~/".ru, first: 5, last: 6)), text: "test ~/".ru, position: 5)]

  for i, c in TestCases:
    extractNeighborPathTest(i, c.expectVal, c.text, c.position)

suite "autocomplete: getPathList":
  block:
    proc getPathListTest(testIndex: int, expectVal, path: Runes) =
      ## Check return values of suggestionwindow.getPathList

      let testTitle = "Case :" & $testIndex & $path
      test testTitle:
        check expectVal == getPathList(path)

    const TestCases: seq[tuple[expectVal, path: Runes]] = @[
      (expectVal: "moerc.toml ".ru, path: "./example/".ru),
      (expectVal: "moerc.toml ".ru, path: "./example/m".ru)]

    for i, c in TestCases:
      getPathListTest(i, c.expectVal, c.path)

suite "getTextInLangKeywords":
  test "C":
    let
      r = getTextInLangKeywords(SourceLanguage.langC)
      splited = r.split(' '.ru)

    for s in cKeywords:
      check splited.in s.ru

  test "C++":
    let
      r = getTextInLangKeywords(SourceLanguage.langCpp)
      splited = r.split(' '.ru)

    for s in cppKeywords:
      check splited.in s.ru

  test "C#":
    let
      r = getTextInLangKeywords(SourceLanguage.langCsharp)
      splited = r.split(' '.ru)

    for s in csharpKeywords:
      check splited.in s.ru

  test "Haskell":
    let
      r = getTextInLangKeywords(SourceLanguage.langHaskell)
      splited = r.split(' '.ru)

    for s in haskellKeywords:
      check splited.in s.ru

  test "Java":
    let
      r = getTextInLangKeywords(SourceLanguage.langJava)
      splited = r.split(' '.ru)

    for s in javaKeywords:
      check splited.in s.ru

  test "JavaScript":
    let
      r = getTextInLangKeywords(SourceLanguage.langJavaScript)
      splited = r.split(' '.ru)

    for s in javaScriptkeywords:
      check splited.in s.ru

  test "Nim":
    let
      r = getTextInLangKeywords(SourceLanguage.langNim)
      splited = r.split(' '.ru)

    for s in nimKeywords:
      check splited.in s.ru
    for s in nimBooleans:
      check splited.in s.ru
    for s in nimSpecialVars:
      check splited.in s.ru
    for s in nimPragmas:
      check splited.in s.ru
    for s in nimBuiltins:
      check splited.in s.ru
    for s in nimStdLibs:
      check splited.in s.ru

  test "Python":
    let
      r = getTextInLangKeywords(SourceLanguage.langPython)
      splited = r.split(' '.ru)

    for s in pythonKeywords:
      check splited.in s.ru

  test "Rust":
    let
      r = getTextInLangKeywords(SourceLanguage.langRust)
      splited = r.split(' '.ru)

    for s in rustKeywords:
      check splited.in s.ru
