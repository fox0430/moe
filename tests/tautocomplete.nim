import std/[unittest, sugar, sequtils, macros, options]
import moepkg/unicodeext

include moepkg/autocomplete

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

suite "autocomplete: extractNeighborPath":
  # Generate test code
  # Check return values of suggestionwindow.isPath
  macro extractNeighborPathTest(
    testIndex: int,
    expectVal: Option[tuple[path: seq[Rune], first, last: int]],
    text: seq[Rune],
    position: int): untyped =

    quote do:
      let testTitle = "Case " & $`testIndex` & ": " & $`text` & ", " & $`position`

      # Generate test code
      test testTitle:
        check `expectVal` == extractNeighborPath(`text`, `position`)

  const
    testCases: seq[tuple[expectVal: Option[tuple[path: seq[Rune], first, last: int]], text: seq[Rune], position: int]] = @[
      (expectVal: none(tuple[path: seq[Rune], first, last: int]), text: "".ru, position: 0),
      (expectVal: some((path: "/home".ru, first: 0, last: "/home".ru.high)), text: "/home".ru, position: 0),
      (expectVal: some((path: "/home/user/".ru, first: 0, last: "/home/user/".ru.high)), text: "/home/user/".ru, position: 0),
      (expectVal: some((path: "../test".ru, first: 0, last: "../test".ru.high)), text: "../test".ru, position: 0),
      (expectVal: some((path: "/home/user/a".ru, first: 5, last: 16)), text: "test /home/user/a test".ru, position: 16),
      (expectVal: some((path: "../test/test2/".ru, first: 5, last: 18)), text: "test ../test/test2/ test".ru, position: 18),
      (expectVal: some((path: "~/".ru, first: 0, last: "~/".ru.high)), text: "~/".ru, position: 0),
      (expectVal: some((path: "~/".ru, first: 5, last: 6)), text: "test ~/".ru, position: 5)]

  for i, c in testCases:
    extractNeighborPathTest(i, c.expectVal, c.text, c.position)

suite "autocomplete: getPathList":
  block:
    # Generate test code
    # Check return values of suggestionwindow.getPathList
    macro getPathListTest(testIndex: int, expectVal, path: seq[Rune]): untyped =
      quote do:
        let testTitle = "Case :" & $`testIndex` & $`path`

        # Generate test code
        test testTitle:
          check `expectVal` == getPathList(`path`)

    const testCases: seq[tuple[expectVal, path: seq[Rune]]] = @[
      (expectVal: "moerc.toml ".ru, path: "./example/".ru),
      (expectVal: "moerc.toml ".ru, path: "./example/m".ru)]

    # Generate test code by macro
    for i, c in testCases:
      getPathListTest(i, c.expectVal, c.path)

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
    for s in nimStdLibs:
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
