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

import ../src/moepkg/syntax/[tokenizer, syntax_javascript]
import ../src/moepkg/highlight

suite "syntaxjavascript - javaScriptkeywords constant":
  test "javaScriptkeywords contains declaration keywords":
    check "var" in javaScriptkeywords
    check "let" in javaScriptkeywords
    check "const" in javaScriptkeywords
    check "function" in javaScriptkeywords
    check "class" in javaScriptkeywords

  test "javaScriptkeywords contains control flow keywords":
    check "if" in javaScriptkeywords
    check "else" in javaScriptkeywords
    check "switch" in javaScriptkeywords
    check "case" in javaScriptkeywords
    check "for" in javaScriptkeywords
    check "while" in javaScriptkeywords
    check "do" in javaScriptkeywords
    check "break" in javaScriptkeywords
    check "continue" in javaScriptkeywords
    check "return" in javaScriptkeywords

  test "javaScriptkeywords contains exception handling keywords":
    check "try" in javaScriptkeywords
    check "catch" in javaScriptkeywords
    check "finally" in javaScriptkeywords
    check "throw" in javaScriptkeywords

  test "javaScriptkeywords contains async keywords":
    check "async" in javaScriptkeywords
    check "await" in javaScriptkeywords

  test "javaScriptBooleans contains boolean values":
    check "true" in javaScriptBooleans
    check "false" in javaScriptBooleans
    check "null" in javaScriptBooleans
    check "undefined" in javaScriptBooleans

  test "javaScriptkeywords contains type keywords":
    check "typeof" in javaScriptkeywords
    check "instanceof" in javaScriptkeywords
    check "new" in javaScriptkeywords
    check "delete" in javaScriptkeywords
    check "void" in javaScriptkeywords

  test "javaScriptkeywords contains module keywords":
    check "import" in javaScriptkeywords
    check "from" in javaScriptkeywords

  test "javaScriptBuiltins contains built-in objects":
    check "Array" in javaScriptBuiltins
    check "Object" in javaScriptBuiltins
    check "String" in javaScriptBuiltins
    check "Number" in javaScriptBuiltins
    check "Boolean" in javaScriptBuiltins
    check "Function" in javaScriptBuiltins
    check "Promise" in javaScriptBuiltins
    check "Map" in javaScriptBuiltins
    check "Set" in javaScriptBuiltins
    check "JSON" in javaScriptBuiltins
    check "RegExp" in javaScriptBuiltins
    check "Error" in javaScriptBuiltins
    check "Date" in javaScriptBuiltins

  test "javaScriptkeywords contains global objects":
    check "console" in javaScriptkeywords
    check "document" in javaScriptkeywords
    check "window" in javaScriptkeywords
    check "globalThis" in javaScriptkeywords

  test "javaScriptBuiltins contains typed arrays":
    check "Int8Array" in javaScriptBuiltins
    check "Int16Array" in javaScriptBuiltins
    check "Int32Array" in javaScriptBuiltins
    check "Uint8Array" in javaScriptBuiltins
    check "Uint16Array" in javaScriptBuiltins
    check "Uint32Array" in javaScriptBuiltins
    check "Float32Array" in javaScriptBuiltins
    check "Float64Array" in javaScriptBuiltins

suite "syntaxjavascript - javaScriptNextToken keywords":
  test "var keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "let keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "const keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "function keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "class keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "for keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "async keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("async")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "await keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("await")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.javaScriptNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.javaScriptNextToken()
    check g.kind == gtBoolean
    check g.length == 5

  test "null keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.javaScriptNextToken()
    check g.kind == gtBoolean
    check g.length == 4

suite "syntaxjavascript - javaScriptNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.javaScriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.javaScriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.javaScriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.javaScriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "dollar prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$element")
    g.javaScriptNextToken()
    # $ is treated as operator
    check g.kind == gtOperator

  test "camelCase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVariableName")
    g.javaScriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 14

suite "syntaxjavascript - javaScriptNextToken object keys":
  test "identifier followed by colon is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("name:")
    g.javaScriptNextToken()
    check g.kind == gtKey
    check g.length == 4

  test "identifier followed by colon with space is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("name :")
    g.javaScriptNextToken()
    check g.kind == gtKey
    check g.length == 4

  test "quoted string followed by colon is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"name\":")
    g.javaScriptNextToken()
    check g.kind == gtKey
    check g.length == 6

  test "single quoted string followed by colon is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'name':")
    g.javaScriptNextToken()
    check g.kind == gtKey
    check g.length == 6

suite "syntaxjavascript - javaScriptNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.javaScriptNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.javaScriptNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.javaScriptNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntaxjavascript - javaScriptNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.javaScriptNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.javaScriptNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.javaScriptNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntaxjavascript - javaScriptNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.javaScriptNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.javaScriptNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

suite "syntaxjavascript - javaScriptNextToken octal numbers":
  test "octal number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755")
    g.javaScriptNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "octal number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0O777")
    g.javaScriptNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "legacy octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.javaScriptNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

suite "syntaxjavascript - javaScriptNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.javaScriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.javaScriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.javaScriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.javaScriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.javaScriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

suite "syntaxjavascript - javaScriptNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.javaScriptNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.javaScriptNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.javaScriptNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "empty single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''")
    g.javaScriptNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.javaScriptNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

  test "single quoted string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello\\nworld'")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

suite "syntaxjavascript - javaScriptNextToken template literals":
  test "simple template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello`")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit
    check g.length == 7

  test "empty template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("``")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit
    check g.length == 2

  test "template literal with text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello world`")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit
    check g.length == 13

  test "template literal with newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`line1\nline2`")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit

  test "template literal with interpolation start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello ${")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit
    # Should stop before ${

  test "template literal with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello\\`world`")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit

suite "syntaxjavascript - javaScriptNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// this is a comment")
    g.javaScriptNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "empty line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("//")
    g.javaScriptNextToken()
    check g.kind == gtComment
    check g.length == 2

  test "block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.javaScriptNextToken()
    check g.kind == gtLongComment
    check g.length == 13

  test "multiline block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* line1\nline2 */")
    g.javaScriptNextToken()
    check g.kind == gtLongComment

  test "JSDoc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @param x */")
    g.javaScriptNextToken()
    check g.kind == gtDocLongComment

suite "syntaxjavascript - javaScriptNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "division alone is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/ x")
    g.javaScriptNextToken()
    check g.kind == gtOperator

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comparison operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "strict equality operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("===")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "arrow function operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=>")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "spread operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("...")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "optional chaining operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?.")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "nullish coalescing operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("??")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxjavascript - javaScriptNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.javaScriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxjavascript - javaScriptNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.javaScriptNextToken() # 'a'
    g.javaScriptNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.javaScriptNextToken() # 'a'
    g.javaScriptNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.javaScriptNextToken() # 'a'
    g.javaScriptNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.javaScriptNextToken() # 'a'
    g.javaScriptNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

suite "syntaxjavascript - javaScriptNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.javaScriptNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.javaScriptNextToken() # 'x'
    g.javaScriptNextToken() # EOF
    check g.kind == gtEof

suite "syntaxjavascript - javaScriptNextToken complete code":
  test "simple function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function add(a, b) { return a + b; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # function, return
    check gtFunctionName in tokens # add
    check gtIdentifier in tokens # a, b
    check gtPunctuation in tokens # (, ), {, }, ,, ;
    check gtOperator in tokens # +

  test "arrow function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const add = (a, b) => a + b")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # const
    check gtIdentifier in tokens # add, a, b
    check gtOperator in tokens # =, =>, +

  test "variable declarations":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let x = 10;\nconst y = \"hello\";")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # let, const
    check gtDecNumber in tokens # 10
    check gtStringLit in tokens # "hello"
    check gtIdentifier in tokens # x, y

  test "async function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("async function fetchData() { await fetch(url); }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # async, function, await, fetch
    check gtFunctionName in tokens # fetchData

  test "class definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class MyClass { constructor() {} }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class, constructor
    check gtIdentifier in tokens # MyClass

  test "object literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const obj = { name: \"test\", value: 42 };")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # const
    check gtKey in tokens # name, value
    check gtStringLit in tokens # "test"
    check gtDecNumber in tokens # 42

  test "comment preservation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x // comment\ny")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtComment in tokens
    check tokens.len >= 3 # at least x, comment, y

suite "syntaxjavascript - javaScriptNextToken edge cases":
  test "unterminated string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

  test "unterminated template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`unterminated")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit

  test "unterminated block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* unterminated")
    g.javaScriptNextToken()
    check g.kind == gtLongComment

  test "string terminated by newline for double quotes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\nworld\"")
    g.javaScriptNextToken()
    check g.kind == gtStringLit
    # String is terminated at newline
    check g.length == 6

  test "single quoted string allows newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello\nworld'")
    g.javaScriptNextToken()
    check g.kind == gtStringLit
    # Single quoted string allows newline continuation

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.javaScriptNextToken()
    check g.kind == gtIdentifier

suite "syntaxjavascript - javaScriptNextToken template literal interpolation":
  test "template literal before interpolation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`Hello ${name}`")

    g.javaScriptNextToken()
    check g.kind == gtLongStringLit
    # First token is the string part up to ${

  test "interpolation operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`Hello ${name}`")

    g.javaScriptNextToken() # `Hello
    g.javaScriptNextToken() # ${
    check g.kind == gtOperator
    check g.length == 2

  test "template literal with multiple interpolations":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`${a} and ${b}`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLongStringLit in tokens
    check gtOperator in tokens # ${ and }
    check gtIdentifier in tokens # a, b

suite "syntaxjavascript - javaScriptNextToken brace tracking":
  test "nested braces in template interpolation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`${obj.name}`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLongStringLit in tokens
    check gtIdentifier in tokens # obj, name

  test "closing brace returns to template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`Hello ${name}!`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    # Should contain multiple gtLongStringLit tokens (before and after interpolation)
    var stringLitCount = 0
    for t in tokens:
      if t == gtLongStringLit:
        inc stringLitCount
    check stringLitCount >= 2

suite "syntaxjavascript - javaScriptNextToken compound operators":
  test "increment operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("++")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "decrement operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "plus equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+=")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "minus equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-=")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "multiply equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*=")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "divide equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/=")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical and operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&&")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical or operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("||")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!=")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "strict not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!==")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "less than or equal operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<=")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "greater than or equal operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">=")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxjavascript - javaScriptNextToken special cases":
  test "division vs comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a / b")

    g.javaScriptNextToken() # a
    check g.kind == gtIdentifier

    g.javaScriptNextToken() # space
    check g.kind == gtWhitespace

    g.javaScriptNextToken() # /
    check g.kind == gtOperator
    check g.length == 1

  test "regex-like division":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x/y/z")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x, y, z
    check gtOperator in tokens # /

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x = 1; // comment")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x
    check gtOperator in tokens # =
    check gtDecNumber in tokens # 1
    check gtPunctuation in tokens # ;
    check gtComment in tokens # // comment

suite "syntaxjavascript - javaScriptNextToken modern JavaScript":
  test "destructuring assignment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const { a, b } = obj")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # const
    check gtPunctuation in tokens # {, ,, }
    check gtIdentifier in tokens # a, b, obj

  test "array destructuring":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const [x, y] = arr")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # const
    check gtPunctuation in tokens # [, ,, ]
    check gtIdentifier in tokens # x, y, arr

  test "optional chaining":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("obj?.prop?.method?.()")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # obj, prop, method
    check gtOperator in tokens # ?.

  test "nullish coalescing":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x ?? defaultValue")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x, defaultValue
    check gtOperator in tokens # ??

suite "syntaxjavascript - javaScriptNextToken number edge cases":
  test "number with suffix character":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123n")
    g.javaScriptNextToken()
    # BigInt suffix
    check g.kind == gtDecNumber
    check g.length == 4

  test "hex with BigInt suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFn")
    g.javaScriptNextToken()
    check g.kind == gtHexNumber
    check g.length == 5

  test "float starting with zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0.5")
    g.javaScriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "float ending with dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5.")
    g.javaScriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 2

suite "syntaxjavascript - javaScriptNextToken JSX mode":
  test "JSX opening tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div>")
    g.javaScriptNextToken()
    # Should switch to JSX/HTML mode
    check g.kind == gtTagStart

  test "JSX self-closing tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<br/>")
    g.javaScriptNextToken()
    check g.kind == gtTagStart

  test "JSX with component name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<MyComponent>")
    g.javaScriptNextToken()
    check g.kind == gtTagStart

  test "JSX closing tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("</div>")
    g.javaScriptNextToken()
    check g.kind == gtTagStart

  test "less than operator not JSX":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("< 5")
    g.javaScriptNextToken()
    check g.kind == gtOperator

  test "less than with number not JSX":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<5")
    g.javaScriptNextToken()
    check g.kind == gtOperator

suite "syntaxjavascript - javaScriptNextToken template literal advanced":
  test "template literal with dollar sign not interpolation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`$100`")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit
    check g.length == 6

  test "template literal continuation state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello ${")

    g.javaScriptNextToken() # `hello
    check g.kind == gtLongStringLit

    g.javaScriptNextToken() # ${
    check g.kind == gtOperator
    check g.length == 2

  test "template literal nested object in interpolation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`${({a: 1})}`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLongStringLit in tokens
    check gtPunctuation in tokens # {, }
    check gtKey in tokens # a
    check gtDecNumber in tokens # 1

  test "template literal with escaped backtick":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`test\\`more`")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit

  test "template literal with escaped dollar":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`\\${notInterpolation}`")
    g.javaScriptNextToken()
    check g.kind == gtLongStringLit

  test "nested template literals":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`outer ${`inner`} outer`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    # Should have multiple gtLongStringLit tokens
    var stringLitCount = 0
    for t in tokens:
      if t == gtLongStringLit:
        inc stringLitCount
    check stringLitCount >= 3

  test "template literal interpolation with function call":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`${fn()}`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLongStringLit in tokens
    check gtFunctionName in tokens # fn
    check gtPunctuation in tokens # (, )

suite "syntaxjavascript - javaScriptNextToken string edge cases":
  test "string with escaped quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\\"more\"")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

  test "single quoted string with escaped quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'test\\'more'")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

  test "string with unicode escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\u0041\"")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

  test "string with hex escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\x41\"")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

  test "string terminated at null":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

  test "string with backslash at end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.javaScriptNextToken()
    check g.kind == gtStringLit

suite "syntaxjavascript - javaScriptNextToken comment edge cases":
  test "block comment with asterisks":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/****/")
    g.javaScriptNextToken()
    check g.kind == gtDocLongComment
    check g.length == 6

  test "block comment with nested slash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* a / b */")
    g.javaScriptNextToken()
    check g.kind == gtLongComment

  test "block comment with slash asterisk inside":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* test /* not nested */")
    g.javaScriptNextToken()
    check g.kind == gtLongComment

  test "unterminated block comment at EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* no end")
    g.javaScriptNextToken()
    check g.kind == gtLongComment

suite "syntaxjavascript - javaScriptNextToken operator edge cases":
  test "question mark operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise operators":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.javaScriptNextToken()
    check g.kind == gtOperator

  test "bitwise xor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("^")
    g.javaScriptNextToken()
    check g.kind == gtOperator

  test "bitwise not":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("~")
    g.javaScriptNextToken()
    check g.kind == gtOperator

  test "modulo operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%")
    g.javaScriptNextToken()
    check g.kind == gtOperator

  test "exponentiation operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("**")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "left shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<<")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "right shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "unsigned right shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>>")
    g.javaScriptNextToken()
    check g.kind == gtOperator
    check g.length == 3

suite "syntaxjavascript - javaScriptNextToken gtNone handling":
  test "unknown character":
    var g: GeneralTokenizer
    # Using a character that's not handled
    g.initGeneralTokenizer("#")
    g.javaScriptNextToken()
    check g.kind == gtNone

  test "at sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.javaScriptNextToken()
    check g.kind == gtOperator

suite "syntaxjavascript - javaScriptNextToken state preservation":
  test "preserves restored state on resumed tokenization at position 0":
    # When `restoreTokenizerState` (used by incremental re-highlight) has
    # pre-loaded JSX / template-literal / brace-depth context for a new
    # chunk, the tokenizer must NOT clear those fields just because
    # `g.pos == 0`. The bug previously silently lost JSX mode across chunk
    # boundaries, making incremental output diverge from a full reparse.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("test")
    # Simulate a caller-restored mid-stream state.
    g.lang.jslike =
      JsLikeState(templateLiteralDepth: 5, braceDepthStack: @[1, 2, 3], inJsxMode: true)

    g.javaScriptNextToken()

    check g.lang.jslike.templateLiteralDepth == 5
    check g.lang.jslike.braceDepthStack == @[1, 2, 3]
    check g.lang.jslike.inJsxMode == true

suite "syntaxjavascript - javaScriptNextToken complete JavaScript code":
  test "ES6 module syntax":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import { foo } from 'module';")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # import, from
    check gtPunctuation in tokens # {, }, ;
    check gtIdentifier in tokens # foo
    check gtStringLit in tokens # 'module'

  test "export default":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("export default function() {}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # export, default, function

  test "for...of loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for (const x of items) {}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # for, const, of
    check gtIdentifier in tokens # x, items

  test "try catch finally":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("try { x } catch (e) { y } finally { z }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # try, catch, finally

  test "switch case default":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("switch (x) { case 1: break; default: return; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # switch, case, default, break, return

suite "syntaxjavascript - javaScriptBooleans constant":
  test "javaScriptBooleans contains boolean values":
    check "true" in javaScriptBooleans
    check "false" in javaScriptBooleans
    check "null" in javaScriptBooleans
    check "undefined" in javaScriptBooleans

suite "syntaxjavascript - javaScriptBuiltins constant":
  test "javaScriptBuiltins contains built-in objects":
    check "Array" in javaScriptBuiltins
    check "Object" in javaScriptBuiltins
    check "String" in javaScriptBuiltins
    check "Number" in javaScriptBuiltins
    check "Boolean" in javaScriptBuiltins
    check "Function" in javaScriptBuiltins
    check "Promise" in javaScriptBuiltins
    check "Map" in javaScriptBuiltins
    check "Set" in javaScriptBuiltins
    check "JSON" in javaScriptBuiltins
    check "RegExp" in javaScriptBuiltins
    check "Error" in javaScriptBuiltins
    check "Date" in javaScriptBuiltins
    check "Math" in javaScriptBuiltins
    check "Symbol" in javaScriptBuiltins

  test "javaScriptBuiltins contains typed arrays":
    check "Int8Array" in javaScriptBuiltins
    check "Int16Array" in javaScriptBuiltins
    check "Int32Array" in javaScriptBuiltins
    check "Uint8Array" in javaScriptBuiltins
    check "Uint16Array" in javaScriptBuiltins
    check "Uint32Array" in javaScriptBuiltins
    check "Float32Array" in javaScriptBuiltins
    check "Float64Array" in javaScriptBuiltins

suite "syntaxjavascript - javaScriptNextToken boolean tokens":
  test "true is boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.javaScriptNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "false is boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.javaScriptNextToken()
    check g.kind == gtBoolean
    check g.length == 5

  test "null is boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.javaScriptNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "undefined is boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("undefined")
    g.javaScriptNextToken()
    check g.kind == gtBoolean
    check g.length == 9

suite "syntaxjavascript - javaScriptNextToken builtin tokens":
  test "Array is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Array")
    g.javaScriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 5

  test "Map is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Map")
    g.javaScriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 3

  test "Promise is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Promise")
    g.javaScriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 7

  test "JSON is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("JSON")
    g.javaScriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

  test "Math is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Math")
    g.javaScriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

suite "syntaxjavascript - javaScriptNextToken function name tokens":
  test "identifier followed by paren is function name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foo(")
    g.javaScriptNextToken()
    check g.kind == gtFunctionName
    check g.length == 3

  test "identifier not followed by paren is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foo ")
    g.javaScriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 3

  test "keyword followed by paren stays keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if(")
    g.javaScriptNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "builtin followed by paren stays builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Array(")
    g.javaScriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 5

  test "function call in expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myFunc(x)")
    g.javaScriptNextToken()
    check g.kind == gtFunctionName
    check g.length == 6

suite "syntaxjavascript - JSDoc highlighting":
  test "regular block comment has no JSDoc tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* @param x */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "JSDoc tag is preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @param x */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor in tokens
    check gtDocLongComment in tokens

  test "JSDoc type annotation is preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @param {string} name */")
    var kinds: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)
    var preprocCount = 0
    for k in kinds:
      if k == gtPreprocessor:
        inc preprocCount
    check preprocCount >= 2 # @param and {string}

  test "JSDoc multiple tags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @param x @returns y */")
    var kinds: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)
    var preprocCount = 0
    for k in kinds:
      if k == gtPreprocessor:
        inc preprocCount
    check preprocCount >= 2

  test "JSDoc common tags":
    for tag in [
      "@param", "@returns", "@type", "@typedef", "@callback", "@deprecated", "@example"
    ]:
      var g: GeneralTokenizer
      g.initGeneralTokenizer("/** " & tag & " */")
      var hasPreprocessor = false
      while true:
        g.javaScriptNextToken()
        if g.kind == gtEof:
          break
        if g.kind == gtPreprocessor:
          hasPreprocessor = true
      check hasPreprocessor

  test "empty JSDoc /**/ has no preprocessor tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**/")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "triple star /***/ has no preprocessor tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/***/")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "regular block comment with braces has no preprocessor tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* {string} @param */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "multi-line JSDoc via single buffer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**\n * @param {string} name\n */")
    var hasPreprocessor = false
    var hasDocLongComment = false
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtPreprocessor:
        hasPreprocessor = true
      if g.kind == gtDocLongComment:
        hasDocLongComment = true
    check hasPreprocessor
    check hasDocLongComment

  test "multi-line JSDoc continuation (line-by-line)":
    # First line: /**
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**")
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
    check g.state == gtDocLongComment
    check g.lang.jslike.commentDepth == 1

    # Second line: * @param x
    let snap1 = captureTokenizerState(g)
    g.initGeneralTokenizer(" * @param x")
    g.restoreTokenizerState(snap1)
    var hasPreprocessor = false
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtPreprocessor:
        hasPreprocessor = true
    check hasPreprocessor
    check g.state == gtDocLongComment

    # Third line: */
    let snap2 = captureTokenizerState(g)
    g.initGeneralTokenizer(" */")
    g.restoreTokenizerState(snap2)
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
    check g.state == gtNone
    check g.lang.jslike.commentDepth == 0

  test "JSDoc unclosed type before comment end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** {unclosed */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor in tokens

  test "JSDoc nested braces in type annotation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @param {{key: string}} opts */")
    var kinds: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)
    var preprocCount = 0
    for k in kinds:
      if k == gtPreprocessor:
        inc preprocCount
    check preprocCount >= 2 # @param and {{key: string}}
    # Verify the type annotation includes both opening and closing braces
    var foundType = false
    var g2: GeneralTokenizer
    g2.initGeneralTokenizer("/** @param {{key: string}} opts */")
    while true:
      g2.javaScriptNextToken()
      if g2.kind == gtEof:
        break
      if g2.kind == gtPreprocessor and g2.length > 1:
        let startIdx = g2.pos - g2.length
        if g2.buf[startIdx] == '{':
          # Check the last char is '}'
          if g2.buf[g2.pos - 1] == '}':
            foundType = true
    check foundType

  test "email address in JSDoc is not a tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** Contact user@example.com for help */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "at sign followed by number in JSDoc is not a tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @123 */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaScriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens
