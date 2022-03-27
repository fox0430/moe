import std/[unittest, sugar, sequtils]
import moepkg/unicodeext

include moepkg/autocomplete

const code = ru"""proc fibonacci(n: int): int =
  if n == 0: return 0
  if n == 1: return 1
  return fibonacci(n - 1) + fibonacci(n - 2)"""

suite "autocomplete":
  test "enumerateWords":
    const
      expectedResult = @["proc", "fibonacci", "n", "int", "int", "if", "n", "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].map(s => s.ru)
      actualResult = collect(newSeq):
        for x in enumerateWords(code):
          x

    check actualResult == expectedResult

  test "addWordToDictionary":
    var dictionary: WordDictionary
    const allWords = @["proc", "fibonacci", "n", "int", "int", "if", "n", "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].deduplicate
    dictionary.addWordToDictionary(code)

    for x in allWords:
      check dictionary.contains(x)
    for x in dictionary.items:
      check allWords.contains(x)

  test "extractNeighborWord":
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

  test "collectSuggestions":
    var dictionary: WordDictionary
    const allWords = @["proc", "pass", "parse", "paste", "pop", "path"]
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

suite "getTextInLangKeywords":
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

  test "Java":
    let
      r = getTextInLangKeywords(SourceLanguage.langJava)
      splited = r.split(' '.ru)

    for s in javaKeywords:
      check splited.in s.ru

  test "Python":
    let
      r = getTextInLangKeywords(SourceLanguage.langPython)
      splited = r.split(' '.ru)

    for s in pythonKeywords:
      check splited.in s.ru

  test "JavaScript":
    let
      r = getTextInLangKeywords(SourceLanguage.langJavaScript)
      splited = r.split(' '.ru)

    for s in javaScriptkeywords:
      check splited.in s.ru
