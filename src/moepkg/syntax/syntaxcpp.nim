import highlite, syntaxc

proc cppNextToken*(g: var GeneralTokenizer) =
  const
    keywords: array[0..47, string] = ["asm", "auto", "break", "case", "catch",
      "char", "class", "const", "continue", "default", "delete", "do", "double",
      "else", "enum", "extern", "float", "for", "friend", "goto", "if",
      "inline", "int", "long", "new", "operator", "private", "protected",
      "public", "register", "return", "short", "signed", "sizeof", "static",
      "struct", "switch", "template", "this", "throw", "try", "typedef",
      "union", "unsigned", "virtual", "void", "volatile", "while"]
  clikeNextToken(g, keywords, {hasPreprocessor})
