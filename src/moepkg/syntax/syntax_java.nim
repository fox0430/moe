import std/algorithm

import flags, tokenizer, syntax_c

const
  javaKeywords* = [
    "abstract", "assert", "break", "case", "catch", "class", "const", "continue",
    "default", "do", "else", "enum", "extends", "final", "finally", "for", "goto", "if",
    "implements", "import", "instanceof", "interface", "native", "new", "package",
    "private", "protected", "public", "return", "static", "strictfp", "super", "switch",
    "synchronized", "this", "throw", "throws", "transient", "try", "volatile", "while",
  ]

  javaBooleans* = ["false", "null", "true"]

  javaBuiltinTypes* =
    ["boolean", "byte", "char", "double", "float", "int", "long", "short", "void"]

static:
  doAssert javaKeywords.isSorted
  doAssert javaBooleans.isSorted
  doAssert javaBuiltinTypes.isSorted

proc javaNextToken*(g: var GeneralTokenizer) =
  clikeNextToken(g, javaKeywords, {hasGenerics}, javaBooleans, javaBuiltinTypes)
