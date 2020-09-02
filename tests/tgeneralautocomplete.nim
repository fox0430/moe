import unittest, sugar, sequtils
import moepkg/unicodeext

include moepkg/generalautocomplete

const code = ru"""proc fibonacci(n: int): int =
  if n == 0: return 0
  if n == 1: return 1
  return fibonacci(n - 1) + fibonacci(n - 2)"""
 
test "enumerateIdentifiers":
  const
    expectedResult = @["proc", "fibonacci", "n", "int", "int", "if", "n", "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].map(ru)
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

  check extractNeighborWord(text, 0) == ru"This"
  check extractNeighborWord(text, 3) == ru"This"
  check extractNeighborWord(text, 4) == ru""
  check extractNeighborWord(text, 7) == ru""
  check extractNeighborWord(text, 8) == ru"a"
  check extractNeighborWord(text, 20) == ru"text"
  check extractNeighborWord(text, 21) == ru""
