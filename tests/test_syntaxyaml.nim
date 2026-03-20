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

suite "syntaxyaml - yamlNextToken edge cases":
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

suite "syntaxyaml - yamlNextToken key detection":
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

suite "syntaxyaml - yamlNextToken boolean values":
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

suite "syntaxyaml - yamlNextToken null values":
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

suite "syntaxyaml - yamlNextToken special floats":
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

suite "syntaxyaml - yamlNextToken quoted values":
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

suite "syntaxyaml - false positive prevention":
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

suite "syntaxyaml - boolean uppercase variants":
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

suite "syntaxyaml - key priority over special values":
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

suite "syntaxyaml - quoted key with escapes":
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

suite "syntaxyaml - special values in flow context":
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

suite "syntaxyaml - special values in list context":
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

suite "syntaxyaml - special float additional paths":
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

suite "syntaxyaml - unquoted value with spaces":
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

suite "syntaxyaml - yamlNextToken hex numbers":
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

suite "syntaxyaml - yamlNextToken octal numbers":
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

suite "syntaxyaml - yamlNextToken timestamps":
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

suite "syntaxyaml - block scalar stale state recovery":
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
