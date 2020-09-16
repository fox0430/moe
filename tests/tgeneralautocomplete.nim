import unittest, sugar, sequtils
import moepkg/unicodeext

include moepkg/generalautocomplete

const code = ru"""proc fibonacci(n: int): int =
  if n == 0: return 0
  if n == 1: return 1
  return fibonacci(n - 1) + fibonacci(n - 2)"""
 
test "enumerateIdentifiers":
  const
    expectedResult = @["proc", "fibonacci", "n", "int", "int", "if", "n", "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].map(s => s.ru)
    actualResult = collect(newSeq):
      for x in enumerateIdentifiers(code):
        x

  check actualResult == expectedResult

test "makeIdentifierDictionary":
  const allIdentifiers = @["proc", "fibonacci", "n", "int", "int", "if", "n", "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].deduplicate
  let dictionary = makeIdentifierDictionary(code)

  for x in allIdentifiers:
    check dictionary.contains(x)
  for x in dictionary.items:
    check allIdentifiers.contains(x)

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
