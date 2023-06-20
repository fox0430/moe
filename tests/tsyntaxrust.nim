import std/unittest
import moepkg/syntax/highlite

type
  GT = GeneralTokenizer

suite "syntax: Rust":
  test "Hello world":
    const code = """fn main() { println!("Hello world"); }"""

    var token = GeneralTokenizer()
    token.initGeneralTokenizer(code)

    var tokens: seq[GT]

    while true:
      token.getNextToken(SourceLanguage.langRust)
      if token.kind == gtEof: break
      else:
        tokens.add token
        # Clear token.buf
        tokens[^1].buf = ""

    check tokens == @[
      GT(kind: gtKeyword, start: 0, length: 2, buf: "", pos: 2, state: gtEof),
      GT(kind: gtWhitespace, start: 2, length: 1, buf: "", pos: 3, state: gtEof),
      GT(kind: gtIdentifier, start: 3, length: 4, buf: "", pos: 7, state: gtEof),
      GT(kind: gtPunctuation, start: 7, length: 1, buf: "", pos: 8, state: gtEof),
      GT(kind: gtPunctuation, start: 8, length: 1, buf: "", pos: 9, state: gtEof),
      GT(kind: gtWhitespace, start: 9, length: 1, buf: "", pos: 10, state: gtEof),
      GT(kind: gtPunctuation, start: 10, length: 1, buf: "", pos: 11, state: gtEof),
      GT(kind: gtWhitespace, start: 11, length: 1, buf: "", pos: 12, state: gtEof),
      GT(kind: gtIdentifier, start: 12, length: 7, buf: "", pos: 19, state: gtEof),
      GT(kind: gtOperator, start: 19, length: 1, buf: "", pos: 20, state: gtEof),
      GT(kind: gtPunctuation, start: 20, length: 1, buf: "", pos: 21, state: gtEof),
      GT(kind: gtStringLit, start: 21, length: 13, buf: "", pos: 34, state: gtEof),
      GT(kind: gtPunctuation, start: 34, length: 1, buf: "", pos: 35, state: gtEof),
      GT(kind: gtPunctuation, start: 35, length: 1, buf: "", pos: 36, state: gtEof),
      GT(kind: gtWhitespace, start: 36, length: 1, buf: "", pos: 37, state: gtEof),
      GT(kind: gtPunctuation, start: 37, length: 1, buf: "", pos: 38, state: gtEof)
    ]

  test "Only '/'":
    # https://github.com/fox0430/moe/issues/1675

    const code = """/"""

    var token = GeneralTokenizer()
    token.initGeneralTokenizer(code)

    var tokens: seq[GT]

    while true:
      token.getNextToken(SourceLanguage.langRust)
      if token.kind == gtEof: break
      else:
        tokens.add token
        # Clear token.buf
        tokens[^1].buf = ""

    check tokens == @[
      GT(kind: gtOperator, start: 0, length: 1, buf: "", pos: 1, state: gtEof),
    ]

  test "Only comments":
    const code = """// fn main() { println!("Hello world"); }"""

    var token = GeneralTokenizer()
    token.initGeneralTokenizer(code)

    var tokens: seq[GT]

    while true:
      token.getNextToken(SourceLanguage.langRust)
      if token.kind == gtEof: break
      else:
        tokens.add token
        # Clear token.buf
        tokens[^1].buf = ""

    check tokens == @[
      GT(kind: gtComment, start: 0, length: 41, buf: "", pos: 41, state: gtEof)
    ]
