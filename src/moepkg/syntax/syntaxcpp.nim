import highlite, syntaxc

const
  cppKeywords* = ["asm", "auto", "break", "case", "catch", "char", "class",
    "const", "continue", "default", "delete", "do", "double", "else", "enum",
    "extern", "float", "for", "friend", "goto", "if", "inline", "int", "long",
    "new", "operator", "private", "protected", "public", "register", "return",
    "short", "signed", "sizeof", "static", "struct", "switch", "template",
    "this", "throw", "try", "typedef", "union", "unsigned", "virtual", "void",
    "volatile", "while"]

proc cppNextToken*(g: var GeneralTokenizer) =
  clikeNextToken(g, cppKeywords, {hasPreprocessor})
