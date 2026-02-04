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

import std/unittest

import ../src/moepkg/syntax/[tokenizer, syntaxyaml]

suite "syntaxyaml - yamlNextToken whitespace":
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

suite "syntaxyaml - yamlNextToken comments":
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

suite "syntaxyaml - yamlNextToken double quoted strings":
  test "simple double quoted string":
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

suite "syntaxyaml - yamlNextToken single quoted strings":
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

suite "syntaxyaml - yamlNextToken escape sequences":
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

suite "syntaxyaml - yamlNextToken decimal numbers":
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

suite "syntaxyaml - yamlNextToken float numbers":
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

suite "syntaxyaml - yamlNextToken document markers":
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

suite "syntaxyaml - yamlNextToken punctuation":
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

suite "syntaxyaml - yamlNextToken tags":
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

suite "syntaxyaml - yamlNextToken anchors and aliases":
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

suite "syntaxyaml - yamlNextToken block scalars":
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

suite "syntaxyaml - yamlNextToken directives":
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

suite "syntaxyaml - yamlNextToken plain strings":
  test "unquoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello world")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtStringLit

  test "unquoted string stops at colon with space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("key: value")
    g.state = gtOther
    g.yamlNextToken()
    check g.kind == gtStringLit
    check g.length == 3 # "key"

suite "syntaxyaml - yamlNextToken EOF":
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

suite "syntaxyaml - yamlNextToken complete YAML":
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

    check gtStringLit in tokens # name, John
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

    check gtStringLit in tokens
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
    check gtStringLit in tokens # items

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
    check gtStringLit in tokens # description

suite "syntaxyaml - yamlNextToken edge cases":
  test "colon in unquoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("http://example.com")
    g.state = gtOther
    g.yamlNextToken()
    # colon followed by non-space is part of string
    check g.kind == gtStringLit

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
    check g.kind == gtStringLit

  test "colon after flow indicator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}:")
    g.state = gtOther
    g.yamlNextToken() # }
    g.yamlNextToken() # :
    check g.kind == gtPunctuation

suite "syntaxyaml - yamlNextToken outside document":
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
