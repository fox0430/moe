#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, sequtils]

import ../src/moepkg/syntax/[tokenizer, syntax_yaml]

proc drainTokens(
    input: string, initialState = gtOther, maxTokens = 200
): tuple[kinds: seq[TokenClass], finalState: TokenClass] =
  ## Tokenize `input` to gtEof, collecting the non-EOF token kinds and the
  ## final tokenizer state (the value a chunked parse hands to the next
  ## chunk). Bounded so a non-progressing tokenizer fails the test instead of
  ## hanging it, and asserts the tokenizer never leaves the buffer (`g.start +
  ## g.length == g.pos` holds by construction, so `g.pos` is the only
  ## independent bounds invariant). Mirrors collectKinds in
  ## test_syntax_markdown / collectTokens in test_syntax_latex.
  var g: GeneralTokenizer
  g.initGeneralTokenizer(input)
  g.state = initialState
  for _ in 0 ..< maxTokens:
    g.yamlNextToken()
    check g.pos <= input.len
    if g.kind == gtEof:
      break
    result.kinds.add(g.kind)
  check g.kind == gtEof
  result.finalState = g.state

proc collectKinds(input: string, maxTokens = 200): seq[TokenClass] =
  drainTokens(input, maxTokens = maxTokens).kinds

proc checkTokenizesInBounds(buf: string, initialState = gtOther) =
  discard drainTokens(buf, initialState)

proc finalStateAtEof(input: string, initialState = gtOther): TokenClass =
  drainTokens(input, initialState).finalState

suite "syntax_yaml - yamlNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key:    value")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # spaces
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key:\tvalue")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # tab
    check g.kind == gtWhitespace

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key:\nvalue")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # newline
    check g.kind == gtWhitespace

suite "syntax_yaml - yamlNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "empty comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtComment
    check g.length == 1

  test "comment after key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value # comment")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtComment in tokens

suite "syntax_yaml - yamlNextToken double quoted strings":
  test "simple double quoted string (value)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtStringLit

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtStringLit

suite "syntax_yaml - yamlNextToken single quoted strings":
  test "simple single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtNone
    check g.state == gtCharLit

  test "single quoted string content":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.state = gtOther
    g.yamlNextToken() # start '
    g.yamlNextToken() # content
    check g.kind == gtStringLit

  test "escaped single quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'it''s'")
    g.state = gtOther
    g.yamlNextToken() # start '
    g.yamlNextToken() # it
    check g.kind == gtStringLit

    g.yamlNextToken() # ''
    check g.kind == gtEscapeSequence

suite "syntax_yaml - yamlNextToken escape sequences":
  test "newline escape in double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.state = gtOther
    g.yamlNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.yamlNextToken() # \n
    check g.kind == gtEscapeSequence

  test "hex escape \\x":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.state = gtOther
    g.yamlNextToken() # "
    check g.state == gtStringLit

    g.yamlNextToken() # \xFF
    check g.kind == gtEscapeSequence

  test "unicode escape \\u":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\u0041\"")
    g.state = gtOther
    g.yamlNextToken() # "
    g.yamlNextToken() # \u0041
    check g.kind == gtEscapeSequence

  test "unicode escape \\U":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\U00000041\"")
    g.state = gtOther
    g.yamlNextToken() # "
    g.yamlNextToken() # \U00000041
    check g.kind == gtEscapeSequence

suite "syntax_yaml - yamlNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "negative number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-123")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

suite "syntax_yaml - yamlNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtFloatNumber

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtFloatNumber

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtFloatNumber

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14e+2")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtFloatNumber

  test "negative float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-3.14")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtFloatNumber

suite "syntax_yaml - yamlNextToken document markers":
  test "document start ---":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("---\n")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "document end ...":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("...\n")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKeyword
    check g.length == 3

suite "syntax_yaml - yamlNextToken punctuation":
  test "list item -":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- item")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "mapping key ?":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("? key")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "mapping value :":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    check g.kind == gtPunctuation
    check g.length == 1

  test "flow sequence start [":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[a, b]")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "flow sequence end ]":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "flow mapping start {":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{a: b}")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "flow mapping end }":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma separator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_yaml - yamlNextToken tags":
  test "local tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!custom value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtTagStart

  test "prefixed tag !!str":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!!str value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtTagStart

  test "literal tag !<tag:yaml.org,2002:str>":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!<tag:yaml.org,2002:str> value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtTagStart

suite "syntax_yaml - yamlNextToken anchors and aliases":
  test "anchor &name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&anchor value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtLabel

  test "alias *name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*anchor")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtReference

suite "syntax_yaml - yamlNextToken block scalars":
  test "literal block scalar |":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|\ntext")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtCommand
    check g.state == gtCommand

  test "folded block scalar >":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">\ntext")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtCommand
    check g.state == gtCommand

  test "block scalar with indicators |+":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|+\ntext")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtCommand

  test "block scalar with indentation |2":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|2\ntext")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtCommand

suite "syntax_yaml - yamlNextToken directives":
  test "YAML directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%YAML 1.2")
    g.state = gtNone
    g.yamlNextToken()
    check g.kind == gtDirective

  test "TAG directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%TAG ! tag:example.com,2000:")
    g.state = gtNone
    g.yamlNextToken()
    check g.kind == gtDirective

suite "syntax_yaml - yamlNextToken plain strings":
  test "unquoted string (value)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello world")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtIdentifier

  test "unquoted string stops at colon with space (key)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey
    check g.length == 3 # "key"

suite "syntax_yaml - yamlNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # EOF
    check g.kind == gtEof

suite "syntax_yaml - yamlNextToken complete YAML":
  test "simple key-value pair":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("name: John")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens # name
    check gtIdentifier in tokens # John
    check gtPunctuation in tokens # :
    check gtWhitespace in tokens

  test "nested mapping":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("person:\n  name: John\n  age: 30")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens
    check gtPunctuation in tokens
    check gtDecNumber in tokens # 30

  test "list":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- item1\n- item2\n- item3")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # -
    check gtIdentifier in tokens # items

  test "flow sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[a, b, c]")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # [, ], ,

  test "flow mapping":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{key: value}")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # {, }, :

  test "document with directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%YAML 1.2\n---\nkey: value")
    g.state = gtNone

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDirective in tokens
    check gtKeyword in tokens # ---

  test "anchor and alias":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&anchor value\nalias: *anchor")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLabel in tokens # &anchor
    check gtReference in tokens # *anchor

  test "tagged value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!!str 123")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtTagStart in tokens # !!str

  test "multiline string with block scalar":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("description: |\n  This is a\n  multiline string")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtCommand in tokens # |
    check gtKey in tokens # description

suite "syntax_yaml - yamlNextToken edge cases":
  test "colon in unquoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("http://example.com")
    g.state = gtOther
    g.yamlNextToken()
    # colon followed by non-space is part of string
    check g.kind == gtIdentifier

  test "dash not followed by space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-123")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDecNumber

  test "question mark not followed by space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?unknown")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtIdentifier

  test "colon after flow indicator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}:")
    g.state = gtOther
    g.yamlNextToken() # }
    g.yamlNextToken() # :
    check g.kind == gtPunctuation

suite "syntax_yaml - yamlNextToken outside document":
  test "whitespace outside document":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("  ")
    g.state = gtNone
    g.yamlNextToken()
    check g.kind == gtWhitespace

  test "comment outside document":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.state = gtNone
    g.yamlNextToken()
    check g.kind == gtComment

  test "directive at start of line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%TAG ! tag:")
    g.state = gtNone
    g.yamlNextToken()
    check g.kind == gtDirective

suite "syntax_yaml - yamlNextToken key detection":
  test "unquoted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("name: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey
    check g.length == 4 # "name"

  test "double-quoted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"name\": value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey
    check g.state == gtKey

  test "single-quoted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'name': value")
    g.state = gtOther
    g.yamlNextToken() # start '
    check g.state == gtCharLit
    g.yamlNextToken() # content 'name'
    check g.kind == gtKey

  test "number key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("42: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "flow mapping key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{key: value}")
    g.state = gtOther

    var tokens: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKey in tokens
    check gtIdentifier in tokens

  test "value is not a key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.state = gtOther

    g.yamlNextToken() # key
    check g.kind == gtKey
    g.yamlNextToken() # :
    check g.kind == gtPunctuation
    g.yamlNextToken() # space
    g.yamlNextToken() # value
    check g.kind == gtIdentifier

suite "syntax_yaml - yamlNextToken boolean values":
  test "true":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: true")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # true
    check g.kind == gtBoolean

  test "false":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: false")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # false
    check g.kind == gtBoolean

  test "True":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: True")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # True
    check g.kind == gtBoolean

  test "yes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: yes")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # yes
    check g.kind == gtBoolean

  test "no":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: no")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # no
    check g.kind == gtBoolean

  test "on":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: on")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # on
    check g.kind == gtBoolean

  test "off":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: off")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # off
    check g.kind == gtBoolean

  test "boolean as key becomes gtKey":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

suite "syntax_yaml - yamlNextToken null values":
  test "null":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: null")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # null
    check g.kind == gtSpecialVar

  test "Null":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: Null")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # Null
    check g.kind == gtSpecialVar

  test "NULL":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: NULL")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # NULL
    check g.kind == gtSpecialVar

  test "tilde as null":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: ~")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # ~
    check g.kind == gtSpecialVar

suite "syntax_yaml - yamlNextToken special floats":
  test ".inf":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: .inf")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # .inf
    check g.kind == gtFloatNumber

  test ".nan":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: .nan")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # .nan
    check g.kind == gtFloatNumber

  test "-.inf":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: -.inf")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # -.inf
    check g.kind == gtFloatNumber

suite "syntax_yaml - yamlNextToken quoted values":
  test "double-quoted value stays gtStringLit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: \"value\"")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # "value"
    check g.kind == gtStringLit

  test "single-quoted value stays gtStringLit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: 'value'")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # ' (start)
    g.yamlNextToken() # value content
    check g.kind == gtStringLit

suite "syntax_yaml - false positive prevention":
  test "truthy is not boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: truthy")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # truthy
    check g.kind == gtIdentifier

  test "nullable is not null":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: nullable")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # nullable
    check g.kind == gtIdentifier

  test "nope is not boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: nope")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # nope
    check g.kind == gtIdentifier

  test "long token is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: enabled")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # enabled (7 chars, > 6 limit)
    check g.kind == gtIdentifier

suite "syntax_yaml - boolean uppercase variants":
  test "FALSE":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: FALSE")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # FALSE
    check g.kind == gtBoolean

  test "YES":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: YES")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # YES
    check g.kind == gtBoolean

  test "NO":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: NO")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # NO
    check g.kind == gtBoolean

  test "ON":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: ON")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # ON
    check g.kind == gtBoolean

  test "OFF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: OFF")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # OFF
    check g.kind == gtBoolean

suite "syntax_yaml - key priority over special values":
  test "null as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "tilde as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("~: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test ".inf as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".inf: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "yes as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("yes: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "float as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "negative number as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-42: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

suite "syntax_yaml - quoted key with escapes":
  test "double-quoted key with backslash escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"k\\\"ey\": value")
    g.state = gtOther
    g.yamlNextToken() # "k
    check g.kind == gtKey
    check g.state == gtKey

  test "single-quoted key with escaped quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'it''s': value")
    g.state = gtOther
    g.yamlNextToken() # start '
    check g.state == gtCharLit
    check g.yamlIsKey == true
    g.yamlNextToken() # it
    check g.kind == gtKey
    g.yamlNextToken() # '' escape
    check g.kind == gtEscapeSequence

  test "empty double-quoted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\": value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "escape sequence inside double-quoted key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"na\\nme\": value")
    g.state = gtOther
    g.yamlNextToken() # "na
    check g.kind == gtKey
    check g.state == gtKey
    g.yamlNextToken() # \n escape
    check g.kind == gtEscapeSequence
    g.yamlNextToken() # me"
    check g.kind == gtKey

suite "syntax_yaml - special values in flow context":
  test "booleans in flow sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[true, false]")
    g.state = gtOther

    var kinds: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)

    # [, true, ,, space, false, ]
    check kinds.count(gtBoolean) == 2

  test "null in flow sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[null, ~]")
    g.state = gtOther

    var kinds: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)

    check kinds.count(gtSpecialVar) == 2

  test "special float in flow sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[.inf, .nan]")
    g.state = gtOther

    var kinds: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)

    check kinds.count(gtFloatNumber) == 2

  test "special values as flow mapping keys":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{true: 1, null: 2}")
    g.state = gtOther

    var kinds: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)

    check kinds.count(gtKey) == 2
    check kinds.count(gtDecNumber) == 2

suite "syntax_yaml - special values in list context":
  test "boolean after list dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- true")
    g.state = gtOther
    g.yamlNextToken() # -
    check g.kind == gtPunctuation
    g.yamlNextToken() # space
    g.yamlNextToken() # true
    check g.kind == gtBoolean

  test "null after list dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- null")
    g.state = gtOther
    g.yamlNextToken() # -
    g.yamlNextToken() # space
    g.yamlNextToken() # null
    check g.kind == gtSpecialVar

  test "special float after list dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- .inf")
    g.state = gtOther
    g.yamlNextToken() # -
    g.yamlNextToken() # space
    g.yamlNextToken() # .inf
    check g.kind == gtFloatNumber

  test "key-value after list dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- name: John")
    g.state = gtOther
    g.yamlNextToken() # -
    check g.kind == gtPunctuation
    g.yamlNextToken() # space
    g.yamlNextToken() # name
    check g.kind == gtKey
    g.yamlNextToken() # :
    check g.kind == gtPunctuation
    g.yamlNextToken() # space
    g.yamlNextToken() # John
    check g.kind == gtIdentifier

suite "syntax_yaml - special float additional paths":
  test "+.inf via else branch":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: +.inf")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # +.inf
    check g.kind == gtFloatNumber

  test ".inf at start of line via dot branch":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".inf")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtFloatNumber

  test ".NaN case variant":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: .NaN")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # .NaN
    check g.kind == gtFloatNumber

  test ".INF case variant":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: .INF")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # .INF
    check g.kind == gtFloatNumber

suite "syntax_yaml - unquoted value with spaces":
  test "multi-word value is single identifier token":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: hello world")
    g.state = gtOther
    g.yamlNextToken() # key
    check g.kind == gtKey
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # hello world
    check g.kind == gtIdentifier
    check g.length == 11 # "hello world"

suite "syntax_yaml - yamlNextToken hex numbers":
  test "0xFF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "0X1A2B":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0X1A2B")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtHexNumber
    check g.length == 6

  test "0x0":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0x0")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtHexNumber
    check g.length == 3

  test "0xFF as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "0x with no hex digits":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0x")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtIdentifier

  test "hex in flow sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[0xFF, 0xAB]")
    g.state = gtOther

    var kinds: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)

    check kinds.count(gtHexNumber) == 2

  test "signed -0xFF is not hex":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-0xFF")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind != gtHexNumber

  test "hex as value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: 0xFF")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # 0xFF
    check g.kind == gtHexNumber

  test "hex in list context":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- 0xFF")
    g.state = gtOther
    g.yamlNextToken() # -
    check g.kind == gtPunctuation
    g.yamlNextToken() # space
    g.yamlNextToken() # 0xFF
    check g.kind == gtHexNumber

suite "syntax_yaml - yamlNextToken octal numbers":
  test "0o755":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "0O644":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0O644")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "0o0":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o0")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtOctNumber
    check g.length == 3

  test "0o755 as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "0o with no octal digits":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtIdentifier

  test "0o8 invalid octal digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o8")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtIdentifier

  test "signed -0o755 is not octal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-0o755")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind != gtOctNumber

  test "octal as value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: 0o755")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # 0o755
    check g.kind == gtOctNumber

  test "octal in list context":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- 0o755")
    g.state = gtOther
    g.yamlNextToken() # -
    check g.kind == gtPunctuation
    g.yamlNextToken() # space
    g.yamlNextToken() # 0o755
    check g.kind == gtOctNumber

suite "syntax_yaml - yamlNextToken timestamps":
  test "2024-01-01":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-01")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDate
    check g.length == 10

  test "2024-01-01T12:00:00":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-01T12:00:00")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDate
    check g.length == 19

  test "2024-01-01T12:00:00Z":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-01T12:00:00Z")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDate
    check g.length == 20

  test "2024-01-01T12:00:00+09:00":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-01T12:00:00+09:00")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDate
    check g.length == 25

  test "date as key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-01: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtKey

  test "date in flow sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[2024-01-01, 2024-12-31]")
    g.state = gtOther

    var kinds: seq[TokenClass] = @[]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)

    check kinds.count(gtDate) == 2

  test "date in list context":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("- 2024-01-01")
    g.state = gtOther
    g.yamlNextToken() # -
    check g.kind == gtPunctuation
    g.yamlNextToken() # space
    g.yamlNextToken() # 2024-01-01
    check g.kind == gtDate

  test "two-digit year is not date":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("24-01-01")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtIdentifier

  test "2024-hello is not date":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-hello")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtIdentifier

  test "lowercase t separator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("2024-01-01t12:00:00")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDate
    check g.length == 19

  test "timestamp as value":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: 2024-01-01")
    g.state = gtOther
    g.yamlNextToken() # key
    g.yamlNextToken() # :
    g.yamlNextToken() # space
    g.yamlNextToken() # 2024-01-01
    check g.kind == gtDate

  test "signed -2024-01-01 becomes date (known limitation)":
    # YAML 1.2 doesn't define negative dates, but the highlighter
    # treats the digit portion after '-' as a 4-digit year.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-2024-01-01")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtDate

suite "syntax_yaml - block scalar stale state recovery":
  test "gtLongStringLit state with non-newline pos does not crash":
    # Regression: when the buffer is modified (e.g. paste) the highlighter may
    # resume in gtLongStringLit state but pos no longer points to a newline.
    # Previously this triggered an AssertionDefect.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello world")
    g.state = gtLongStringLit
    # Should not crash; should gracefully fall back.
    g.yamlNextToken()
    check g.kind == gtNone
    check g.state == gtOther

  test "gtLongStringLit state with newline but no block header does not crash":
    # Regression: headerStart == -1 assertion when block scalar header is
    # missing from the buffer (buffer was edited after state was saved).
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\nplain text here")
    g.state = gtLongStringLit
    # pos=0 is '\n' so the first assert passes, but there is no '|' or '>'
    # before it, so headerStart stays -1. Should fall back gracefully.
    g.yamlNextToken()
    check g.kind == gtNone
    check g.state == gtOther

  test "gtLongStringLit recovery allows continued parsing":
    # After recovery from stale state, subsequent tokens should parse normally.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.state = gtLongStringLit
    g.yamlNextToken() # recovery
    check g.state == gtOther
    # Continue parsing the rest of the buffer.
    var kinds: seq[TokenClass]
    while g.kind != gtEof:
      g.yamlNextToken()
      kinds.add(g.kind)
    # Should reach EOF without crashing.
    check kinds[^1] == gtEof

  test "stale gtLongStringLit on an empty buffer stays in bounds":
    # Regression: the fallback did `inc(pos)` even when the first char was the
    # NUL terminator, setting `g.pos = len + 1` so the next call read past the
    # end of the cstring (out-of-bounds garbage tokenized as gtIdentifier).
    checkTokenizesInBounds("", initialState = gtLongStringLit)

  test "stale fallback consumes nothing and reports zero length":
    # Regression: the fallback consumed the first char but returned without
    # setting `g.length`, leaving the previous token's stale length on a token
    # that swallowed one char — shifting every following segment on the line.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.state = gtLongStringLit
    g.yamlNextToken() # recovery token
    check g.kind == gtNone
    check g.length == 0
    check g.pos == 0
    g.yamlNextToken() # 'key' must be intact, not 'ey'
    check g.kind == gtKey
    check g.start == 0
    check g.length == 3

  test "stale fallback at a headerless newline keeps the newline":
    # Regression: the headerStart == -1 fallback consumed the newline with a
    # stale length, so the consumer never saw it and attributed every following
    # segment one row too high.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\nkey: value")
    g.state = gtLongStringLit
    g.yamlNextToken() # recovery token
    check g.kind == gtNone
    check g.length == 0
    check g.pos == 0
    g.yamlNextToken() # the newline survives as whitespace
    check g.kind == gtWhitespace
    check g.start == 0
    check g.length == 1

  test "gtCommand with non-newline char transitions to gtOther":
    # When in gtCommand state (block scalar header) and the current char is
    # not whitespace/comment/newline, state should reset to gtOther.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc")
    g.state = gtCommand
    g.yamlNextToken()
    check g.state == gtOther

  test "normal block scalar still works after fix":
    # Ensure the fix does not break valid block scalar parsing.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|\n  hello\n  world\n")
    g.state = gtOther
    g.yamlNextToken() # '|'
    check g.kind == gtCommand
    g.yamlNextToken() # newline
    check g.state == gtLongStringLit
    g.yamlNextToken() # block scalar content
    check g.kind == gtLongStringLit

suite "syntax_yaml - in-string state survives end of buffer":
  # A chunked parse (updateHighlightIncremental / continueInitialHighlight)
  # hands the buffer-final tokenizer state to the next chunk. Resetting to
  # gtOther at the NUL while still inside a string made every quoted string
  # crossing a chunk boundary resume as plain YAML.

  test "double-quoted continuation keeps gtStringLit at end of buffer":
    # not gtOther: the string is still open
    check finalStateAtEof("multi: \"open string\nstill inside") == gtStringLit

  test "single-quoted continuation keeps gtCharLit at end of buffer":
    # not gtOther: the string is still open
    check finalStateAtEof("single: 'open string\nstill inside") == gtCharLit

  test "end of buffer reports gtEof without a zero-length string token":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"abc")
    g.state = gtOther
    g.yamlNextToken() # the unterminated opener run
    check g.kind == gtStringLit
    g.yamlNextToken() # directly gtEof, not a zero-length gtStringLit first
    check g.kind == gtEof
    check g.state == gtStringLit

  test "block scalar keeps gtLongStringLit at end of buffer":
    # The scalar's extent decision is incomplete when the buffer ends while
    # scanning it: whether it continues depends on lines a chunked parse does
    # not contain. The truthful state lets the chunked drivers rewind the
    # handoff (a fresh buffer cannot resume a scalar without its header).
    # not gtOther: the scalar is still open
    check finalStateAtEof("key: |\n  content\n  more content") == gtLongStringLit

  test "block scalar still resets to gtOther at a dedent inside the buffer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: |\n  content\nother: x")
    g.state = gtOther
    var sawScalar = false
    for i in 0 .. 100:
      g.yamlNextToken()
      if g.kind == gtLongStringLit:
        sawScalar = true
        check g.state == gtOther # the dedent line ended the scalar for real
      if g.kind == gtEof:
        break
    check sawScalar
    check g.state == gtOther

  test "block scalar header keeps gtCommand at end of buffer":
    # A header line as the buffer's last line previously fell into the
    # "illegal here" arm at the NUL and parked gtOther, losing the pending
    # scalar at a chunk boundary.
    check finalStateAtEof("key: |") == gtCommand

  test "closed string at end of buffer still resets to gtOther":
    check finalStateAtEof("done: \"closed\"") == gtOther

  test "gtCommand resume on a newline does not leak a phantom gtEof":
    # Regression: resuming a fresh tokenizer from a captured gtCommand state
    # with the buffer starting on a newline hit the header branch's '\n' arm,
    # which never assigned `kind` — the init value gtEof leaked out of the
    # first call, so the consumer stopped before reading anything and the
    # whole chunk's highlighting was lost.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n  content")
    g.state = gtCommand
    g.yamlNextToken() # the zero-length header→scalar transition token
    check g.kind != gtEof
    check g.state == gtLongStringLit
    # Tokenization still reaches a true EOF afterwards.
    for i in 0 .. 100:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
    check g.kind == gtEof

suite "syntax_yaml - multi-line scalars fold across lines":
  test "unterminated single-quoted scalar at end of buffer does not read past it":
    # Regression: the single-quoted continuation loop lacked a NUL terminator,
    # so an unterminated string ran off the end of the buffer, producing a token
    # whose length overshoots the buffer (which later raised RangeDefect when the
    # highlighter sliced it). Every token must stay within the buffer.
    let src = "single: 'it''s open\nmore text"
    var g: GeneralTokenizer
    g.initGeneralTokenizer(src)
    g.state = gtOther
    var kinds: seq[TokenClass]
    for _ in 0 .. 40:
      g.yamlNextToken()
      check g.start + g.length <= src.len # never extends past the buffer
      kinds.add(g.kind)
      if g.kind == gtEof:
        break
    # Must terminate at EOF instead of looping/crashing.
    check kinds[^1] == gtEof

  test "single-quoted scalar folds across a line keeping gtCharLit":
    # The content reader breaks at the newline but stays in gtCharLit, so the
    # next line resumes the same string. This keeps the closing-quote token (the
    # one that returns to gtOther) on its own line, which is what lets an
    # incremental reparse mark the intervening lines as inside the string.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'first\nsecond'")
    g.state = gtOther
    g.yamlNextToken() # opening '
    check g.kind == gtNone
    check g.state == gtCharLit
    g.yamlNextToken() # 'first<newline>
    check g.kind == gtStringLit
    check g.state == gtCharLit # still inside the single-quoted scalar
    g.yamlNextToken() # second'
    check g.kind == gtStringLit
    check g.state == gtOther # closing quote ends the scalar

  test "double-quoted scalar folds across a line keeping gtStringLit":
    # After an escape splits the opening run, the resumed reader must also break
    # at the newline while staying in gtStringLit. Otherwise a run that reaches
    # end of buffer parks gtOther and back-fills it onto the intervening lines.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\nc\"")
    g.state = gtOther
    g.yamlNextToken() # "a
    check g.kind == gtStringLit
    check g.state == gtStringLit
    g.yamlNextToken() # \n escape
    check g.kind == gtEscapeSequence
    g.yamlNextToken() # b<newline>
    check g.kind == gtStringLit
    check g.state == gtStringLit # still inside the double-quoted scalar
    g.yamlNextToken() # c"
    check g.state == gtOther # closing quote ends the scalar

  test "simple multi-line double-quoted scalar still parses as one run":
    # Without an escape the opening reader spans the lines in a single token and
    # never resets mid-string; the fold support must not regress this.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"line one\nline two\"")
    g.state = gtOther
    g.yamlNextToken() # "line one<newline>
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntax_yaml - block scalar parent indentation":
  test "inline block scalar header at buffer start does not swallow the next key":
    # `key: |` as the very first line: the block body's indentation is derived
    # from the header line itself, so a following same-indent key must stay a
    # key rather than being absorbed as block content.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("description: |\n  body line\nname: value")
    g.state = gtOther
    var keyCount = 0
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtKey:
        inc keyCount
    check keyCount == 2 # "description" and "name"

  test "alone block scalar header honours a parent that is the first line":
    # Mirrors an incremental reparse whose chunk begins on the block scalar's
    # parent line: the parent's indentation must be honoured rather than reset
    # to top level. `lookbehind` reaching the buffer start here means "the parent
    # is the first line", NOT "there is no parent", so the empty `>` block must
    # not swallow the following key.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("  keep trailing\n\n\n>\nnext: done")
    g.state = gtOther
    var tokens: seq[TokenClass]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtKey in tokens # "next" stays a key

  test "alone block scalar header at top level consumes following content":
    # With genuinely no parent above it, an alone header sits at top level and
    # the block scalar owns the rest of the document.
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">\n  folded content\n  more content\n")
    g.state = gtOther
    var tokens: seq[TokenClass]
    while true:
      g.yamlNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtLongStringLit in tokens

  test "document marker as parent line is honoured at buffer start":
    # Fuzz seed 59437: an incremental reparse chunk can begin on the `---`
    # line itself, so there is no newline before it (`lookbehind == -1`). The
    # document-marker check must still fire: the alone header is then at top
    # level and the block scalar owns the rest of the document — including a
    # less-indented line — exactly as a full reparse sees it.
    let tokens = collectKinds("---\n>\n  folded scalar text\nlist")
    check gtLongStringLit in tokens
    check gtIdentifier notin tokens # "list" stays inside the block scalar

  test "document marker with inline header at buffer start forces top level":
    # `--- |` — the marker and the header share the line, so the doc-marker
    # check applies to the header's own line. The scalar is then at top level
    # (parent indentation -1) and owns following column-0 lines, exactly as a
    # full parse treats the same construct mid-buffer. Pins the behavior
    # change from removing the `lookbehind >= 0` guard: previously a buffer
    # STARTING with `--- |` kept parent indentation 0 and released the
    # column-0 line below.
    let tokens = collectKinds("--- |\n  text\nkey: value")
    check gtLongStringLit in tokens
    check gtKey notin tokens # swallowed by the top-level scalar

suite "syntax_yaml - escape at buffer and line boundaries":
  test "trailing backslash at end of buffer stays in bounds":
    # Fuzz seeds 4309/114098/208087: an unterminated double-quoted string
    # earlier in the buffer leaves the tokenizer in string state, and a `\` as
    # the very last char made the escape reader consume past the NUL
    # terminator (`g.pos = len + 1`), producing a negative-length slice in the
    # incremental highlighter (RangeDefect).
    checkTokenizesInBounds("multi: \"this string\ntrailing: done\\")

  test "escaped newline in string continuation stays line-bounded":
    # The escape token must stop before the newline so the per-line fold still
    # captures the boundary state for incremental re-highlighting.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"abc\\\ndef\"")
    g.state = gtOther
    g.yamlNextToken() # "abc
    check g.kind == gtStringLit
    g.yamlNextToken() # the lone backslash
    check g.kind == gtEscapeSequence
    check g.length == 1 # does not swallow the newline
    g.yamlNextToken() # fold across the newline
    check g.kind == gtStringLit
    check g.state == gtStringLit

  test "key lookahead does not cross an escaped newline":
    # Skipping `\<newline>` during the opener's key lookahead would make this
    # line's key-ness depend on a later line — a backward dependency the
    # incremental highlighter cannot observe (same pattern as the JS isKey bug).
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\\nb\": c")
    g.state = gtOther
    g.yamlNextToken() # "a
    check g.kind == gtStringLit # NOT gtKey: the quote does not close on line 0
    check g.yamlIsKey == false

  test "key lookahead with backslash as last buffer char stays in bounds":
    # NOTE: the lookahead is a pure read (`tempPos` never feeds `g.pos`), so
    # the bounds checks below cannot detect a reverted guard by themselves —
    # only a sanitizer would. The kind/yamlIsKey pins are the deterministic
    # part: with the guard the lookahead stops at the backslash and the
    # opener cannot be a key; without it the result depends on out-of-buffer
    # garbage.
    let buf = "\"a\\"
    var g: GeneralTokenizer
    g.initGeneralTokenizer(buf)
    g.state = gtOther
    g.yamlNextToken() # the opener run
    check g.kind == gtStringLit # NOT gtKey
    check g.yamlIsKey == false
    check g.pos <= buf.len
    # Drain the rest (re-tokenizes from the start, covering the opener too).
    checkTokenizesInBounds(buf)

  test "colon as first char of a chunk does not read before the buffer":
    # `pos > 0` guarded `g.buf[pos - 2]`, but after consuming the ':' the
    # previous char is at `pos - 2`, so a ':' at buffer start read `g.buf[-1]`.
    # An incremental chunk can start at any line, so this garbage read could
    # diverge from the full reparse. The plain scalar `:x` must be classified
    # deterministically.
    # NOTE: this pins the classification only. The byte before the buffer is
    # 0x00 in practice, so the old out-of-bounds read usually classified `:x`
    # the same way — the read itself is only observable under a sanitizer.
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":x")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtIdentifier
    check g.length == 2

  test "colon as second char still consults the previous char":
    # The tightened `pos > 1` guard must not over-guard: with the ':' at
    # index 1 the previous char exists (index 0), and a flow terminator there
    # makes the colon punctuation.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}:x")
    g.state = gtOther
    g.yamlNextToken() # }
    check g.kind == gtPunctuation
    g.yamlNextToken() # ':' preceded by '}' → punctuation, not a plain scalar
    check g.kind == gtPunctuation
    check g.length == 1
