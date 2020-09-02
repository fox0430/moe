import unittest, sugar, sequtils
import moepkg/generalautocomplete, moepkg/unicodeext

test "enumerateIdentifiers":
  const
    code = ru"""proc fibonacci(n: int): int =
  if n == 0: return 0
  if n == 1: return 1
  return fibonacci(n - 1) + fibonacci(n - 2)"""
    expectedResult = @["proc", "fibonacci", "n", "int", "int", "if", "n", "return", "if", "n", "return", "return", "fibonacci", "n", "fibonacci", "n"].map(ru)
    actualResult = collect(newSeq):
      for x in enumerateIdentifiers(code):
        x

  check actualResult == expectedResult
