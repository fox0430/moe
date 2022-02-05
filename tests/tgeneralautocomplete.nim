import std/[unittest, sugar, sequtils]
import moepkg/unicodeext

include moepkg/generalautocomplete

const code = ru"""proc fibonacci(n: int): int =
  if n == 0: return 0
  if n == 1: return 1
  return fibonacci(n - 1) + fibonacci(n - 2)"""

test "enumerateWords":
  const
    expectedResult = @["proc", "fibonacci", "n", "int", "int", "if", "n", "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].map(s => s.ru)
    actualResult = collect(newSeq):
      for x in enumerateWords(code):
        x

  check actualResult == expectedResult

test "makeWordDictionary":
  const allWords = @["proc", "fibonacci", "n", "int", "int", "if", "n", "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].deduplicate
  let dictionary = makeWordDictionary(code)

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
