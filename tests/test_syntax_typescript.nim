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

import ../src/moepkg/syntax/[tokenizer, syntax_typescript]

suite "syntax_typescript - typescriptKeywords constant":
  test "typescriptKeywords contains TypeScript type keywords":
    check "any" in typescriptKeywords
    check "boolean" in typescriptKeywords
    check "number" in typescriptKeywords
    check "string" in typescriptKeywords
    check "void" in typescriptKeywords
    check "never" in typescriptKeywords
    check "unknown" in typescriptKeywords
    check "symbol" in typescriptKeywords
    check "bigint" in typescriptKeywords

  test "typescriptKeywords contains declaration keywords":
    check "var" in typescriptKeywords
    check "let" in typescriptKeywords
    check "const" in typescriptKeywords
    check "function" in typescriptKeywords
    check "class" in typescriptKeywords
    check "interface" in typescriptKeywords
    check "type" in typescriptKeywords
    check "enum" in typescriptKeywords
    check "namespace" in typescriptKeywords
    check "module" in typescriptKeywords

  test "typescriptKeywords contains access modifiers":
    check "public" in typescriptKeywords
    check "private" in typescriptKeywords
    check "readonly" in typescriptKeywords

  test "typescriptKeywords contains control flow keywords":
    check "if" in typescriptKeywords
    check "else" in typescriptKeywords
    check "switch" in typescriptKeywords
    check "for" in typescriptKeywords
    check "while" in typescriptKeywords
    check "do" in typescriptKeywords
    check "break" in typescriptKeywords
    check "continue" in typescriptKeywords
    check "return" in typescriptKeywords

  test "typescriptKeywords contains exception handling keywords":
    check "try" in typescriptKeywords
    check "catch" in typescriptKeywords
    check "finally" in typescriptKeywords
    check "throw" in typescriptKeywords

  test "typescriptKeywords contains async keywords":
    check "async" in typescriptKeywords
    check "await" in typescriptKeywords

  test "typescriptBooleans contains boolean and null values":
    check "true" in typescriptBooleans
    check "false" in typescriptBooleans
    check "null" in typescriptBooleans
    check "undefined" in typescriptBooleans

  test "typescriptKeywords contains TypeScript-specific keywords":
    check "abstract" in typescriptKeywords
    check "declare" in typescriptKeywords
    check "implements" in typescriptKeywords
    check "extends" in typescriptKeywords
    check "infer" in typescriptKeywords
    check "keyof" in typescriptKeywords
    check "is" in typescriptKeywords
    check "as" in typescriptKeywords
    check "asserts" in typescriptKeywords
    check "satisfies" in typescriptKeywords
    check "override" in typescriptKeywords
    check "accessor" in typescriptKeywords
    check "unique" in typescriptKeywords
    check "using" in typescriptKeywords

  test "typescriptBuiltins contains built-in objects":
    check "Object" in typescriptBuiltins
    check "String" in typescriptBuiltins
    check "Promise" in typescriptBuiltins
    check "Map" in typescriptBuiltins
    check "Set" in typescriptBuiltins
    check "JSON" in typescriptBuiltins
    check "RegExp" in typescriptBuiltins

  test "typescriptKeywords contains global objects":
    check "console" in typescriptKeywords
    check "document" in typescriptKeywords
    check "window" in typescriptKeywords
    check "globalThis" in typescriptKeywords

  test "typescriptBuiltins contains typed arrays":
    check "Int8Array" in typescriptBuiltins
    check "Int16Array" in typescriptBuiltins
    check "Int32Array" in typescriptBuiltins
    check "Uint8Array" in typescriptBuiltins
    check "Uint16Array" in typescriptBuiltins
    check "Uint32Array" in typescriptBuiltins
    check "Uint8ClampedArray" in typescriptBuiltins

suite "syntax_typescript - typescriptNextToken keywords":
  test "var keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "let keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "const keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "function keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "class keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "interface keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("interface")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "type keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "enum keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("enum")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "namespace keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("namespace")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "abstract keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abstract")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "public keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "private keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("private")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "readonly keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("readonly")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "declare keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("declare")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "keyof keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("keyof")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "typeof keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("typeof")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "infer keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("infer")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("is")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "as keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("as")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "satisfies keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("satisfies")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "async keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("async")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "await keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("await")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.typescriptNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.typescriptNextToken()
    check g.kind == gtBoolean
    check g.length == 5

  test "null keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.typescriptNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "undefined keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("undefined")
    g.typescriptNextToken()
    check g.kind == gtBoolean
    check g.length == 9

  test "never keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("never")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "unknown keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("unknown")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "any keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("any")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 3

suite "syntax_typescript - typescriptNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.typescriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.typescriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.typescriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.typescriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "camelCase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVariableName")
    g.typescriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 14

  test "PascalCase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MyClassName")
    g.typescriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 11

suite "syntax_typescript - typescriptNextToken object keys":
  test "identifier followed by colon is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("name:")
    g.typescriptNextToken()
    check g.kind == gtKey
    check g.length == 4

  test "identifier followed by colon with space is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("name :")
    g.typescriptNextToken()
    check g.kind == gtKey
    check g.length == 4

  test "identifier followed by optional property marker is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("name?:")
    g.typescriptNextToken()
    check g.kind == gtKey
    check g.length == 4

  test "quoted string followed by colon is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"name\":")
    g.typescriptNextToken()
    check g.kind == gtKey
    check g.length == 6

  test "single quoted string followed by colon is key":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'name':")
    g.typescriptNextToken()
    check g.kind == gtKey
    check g.length == 6

suite "syntax_typescript - typescriptNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.typescriptNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.typescriptNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.typescriptNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntax_typescript - typescriptNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.typescriptNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.typescriptNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.typescriptNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntax_typescript - typescriptNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.typescriptNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.typescriptNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

suite "syntax_typescript - typescriptNextToken octal numbers":
  test "octal number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755")
    g.typescriptNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "octal number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0O777")
    g.typescriptNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "legacy octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.typescriptNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

suite "syntax_typescript - typescriptNextToken BigInt numbers":
  test "decimal BigInt":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123n")
    g.typescriptNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

  test "hex BigInt":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFn")
    g.typescriptNextToken()
    check g.kind == gtHexNumber
    check g.length == 5

  test "binary BigInt":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010n")
    g.typescriptNextToken()
    check g.kind == gtBinNumber
    check g.length == 7

  test "octal BigInt":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755n")
    g.typescriptNextToken()
    check g.kind == gtOctNumber
    check g.length == 6

suite "syntax_typescript - typescriptNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.typescriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.typescriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.typescriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.typescriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.typescriptNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

suite "syntax_typescript - typescriptNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.typescriptNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.typescriptNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.typescriptNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "empty single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''")
    g.typescriptNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.typescriptNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.typescriptNextToken()
    check g.kind == gtStringLit

  test "single quoted string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello\\nworld'")
    g.typescriptNextToken()
    check g.kind == gtStringLit

suite "syntax_typescript - typescriptNextToken template literals":
  test "simple template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello`")
    g.typescriptNextToken()
    check g.kind == gtLongStringLit
    check g.length == 7

  test "empty template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("``")
    g.typescriptNextToken()
    check g.kind == gtLongStringLit
    check g.length == 2

  test "template literal with text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello world`")
    g.typescriptNextToken()
    check g.kind == gtLongStringLit
    check g.length == 13

  test "template literal with newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`line1\nline2`")
    g.typescriptNextToken()
    check g.kind == gtLongStringLit

  test "template literal with interpolation start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello ${")
    g.typescriptNextToken()
    check g.kind == gtLongStringLit

  test "template literal with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`hello\\`world`")
    g.typescriptNextToken()
    check g.kind == gtLongStringLit

suite "syntax_typescript - typescriptNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// this is a comment")
    g.typescriptNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "empty line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("//")
    g.typescriptNextToken()
    check g.kind == gtComment
    check g.length == 2

  test "block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.typescriptNextToken()
    check g.kind == gtLongComment
    check g.length == 13

  test "multiline block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* line1\nline2 */")
    g.typescriptNextToken()
    check g.kind == gtLongComment

  test "TSDoc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @param x */")
    g.typescriptNextToken()
    check g.kind == gtDocLongComment

suite "syntax_typescript - typescriptNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "division alone is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/ x")
    g.typescriptNextToken()
    check g.kind == gtOperator

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comparison operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "strict equality operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("===")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "arrow function operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=>")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "spread operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("...")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "optional chaining operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?.")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "nullish coalescing operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("??")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "non-null assertion operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!=")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "strict not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!==")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 3

suite "syntax_typescript - typescriptNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.typescriptNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_typescript - typescriptNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.typescriptNextToken() # 'a'
    g.typescriptNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.typescriptNextToken() # 'a'
    g.typescriptNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.typescriptNextToken() # 'a'
    g.typescriptNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.typescriptNextToken() # 'a'
    g.typescriptNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

suite "syntax_typescript - typescriptNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.typescriptNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.typescriptNextToken() # 'x'
    g.typescriptNextToken() # EOF
    check g.kind == gtEof

suite "syntax_typescript - typescriptNextToken template literal interpolation":
  test "template literal before interpolation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`Hello ${name}`")

    g.typescriptNextToken()
    check g.kind == gtLongStringLit

  test "interpolation operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`Hello ${name}`")

    g.typescriptNextToken() # `Hello
    g.typescriptNextToken() # ${
    check g.kind == gtOperator
    check g.length == 2

  test "template literal with multiple interpolations":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`${a} and ${b}`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLongStringLit in tokens
    check gtOperator in tokens
    check gtIdentifier in tokens

suite "syntax_typescript - typescriptNextToken TypeScript-specific syntax":
  test "interface definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("interface User { name: string; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # interface, string
    check gtIdentifier in tokens # User
    check gtKey in tokens # name
    check gtPunctuation in tokens # {, :, ;, }

  test "type alias":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type ID = string | number;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type, string, number
    check gtIdentifier in tokens # ID
    check gtOperator in tokens # =, |

  test "generic type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Array<string>")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtBuiltin in tokens # Array
    check gtKeyword in tokens # string

  test "keyof operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type Keys = keyof T;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type, keyof

  test "typeof operator in type position":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type T = typeof obj;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type, typeof

  test "as type assertion":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x as string")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # as, string
    check gtIdentifier in tokens # x

  test "satisfies operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("obj satisfies Type")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # satisfies

  test "class with access modifiers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class Foo { private x: number; public y: string; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class, private, public, number, string

  test "abstract class":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abstract class Base { abstract method(): void; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # abstract, class, void

  test "readonly property":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("interface Config { readonly host: string; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # interface, readonly, string

  test "enum definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("enum Direction { Up, Down, Left, Right }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # enum
    check gtIdentifier in tokens # Direction, Up, Down, Left, Right

  test "namespace declaration":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("namespace MyNamespace { export const x = 1; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # namespace, const

  test "declare keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("declare const VERSION: string;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # declare, const, string

  test "conditional type with infer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type Unwrap<T> = T extends Promise<infer U> ? U : T;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type, extends, infer
    check gtBuiltin in tokens # Promise

  test "mapped type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type Readonly<T> = { readonly [K in keyof T]: T[K]; };")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type, readonly, in, keyof

suite "syntax_typescript - typescriptNextToken complete TypeScript code":
  test "simple function with types":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      "function add(a: number, b: number): number { return a + b; }"
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # function, number, return
    check gtIdentifier in tokens # add, a, b
    check gtPunctuation in tokens # (, :, ,, ), {, ;, }
    check gtOperator in tokens # +

  test "arrow function with types":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const add = (a: number, b: number): number => a + b;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # const, number
    check gtOperator in tokens # =, =>

  test "async function with Promise type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      "async function fetchData(): Promise<string> { return await fetch(url); }"
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # async, function, string, return, await
    check gtBuiltin in tokens # Promise

  test "class with constructor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class User { constructor(public name: string) {} }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class, constructor, public, string

  test "generic class":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class Container<T> { value: T; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class
    check gtIdentifier in tokens # Container, T, value

  test "union type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let x: string | number | null;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # let, string, number
    check gtBoolean in tokens # null
    check gtOperator in tokens # :, |

  test "intersection type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type Combined = A & B & C;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type
    check gtOperator in tokens # =, &

  test "ES6 module import":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import { Component } from 'react';")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # import, from
    check gtStringLit in tokens # 'react'

  test "type import":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import type { User } from './types';")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # import, type, from

  test "export default":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("export default function main() {}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # function

suite "syntax_typescript - typescriptNextToken edge cases":
  test "unterminated string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.typescriptNextToken()
    check g.kind == gtStringLit

  test "unterminated template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`unterminated")
    g.typescriptNextToken()
    check g.kind == gtLongStringLit

  test "unterminated block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* unterminated")
    g.typescriptNextToken()
    check g.kind == gtLongComment

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.typescriptNextToken()
    check g.kind == gtIdentifier

  test "string with escaped quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\\"more\"")
    g.typescriptNextToken()
    check g.kind == gtStringLit

  test "template literal with escaped backtick":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`test\\`more`")
    g.typescriptNextToken()
    check g.kind == gtLongStringLit

suite "syntax_typescript - typescriptNextToken TSX/JSX mode":
  test "TSX opening tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<div>")
    g.typescriptNextToken()
    check g.kind == gtTagStart

  test "TSX self-closing tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<br/>")
    g.typescriptNextToken()
    check g.kind == gtTagStart

  test "TSX with component name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<MyComponent>")
    g.typescriptNextToken()
    check g.kind == gtTagStart

  test "TSX closing tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("</div>")
    g.typescriptNextToken()
    check g.kind == gtTagStart

  test "less than operator not TSX":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("< 5")
    g.typescriptNextToken()
    check g.kind == gtOperator

  test "less than with number not TSX":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<5")
    g.typescriptNextToken()
    check g.kind == gtOperator

suite "syntax_typescript - typescriptNextToken brace tracking":
  test "nested braces in template interpolation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`${obj.name}`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtLongStringLit in tokens
    check gtIdentifier in tokens

  test "closing brace returns to template literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`Hello ${name}!`")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    var stringLitCount = 0
    for t in tokens:
      if t == gtLongStringLit:
        inc stringLitCount
    check stringLitCount >= 2

suite "syntax_typescript - typescriptNextToken state reset":
  test "state reset at position 0":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("test")
    g.templateLiteralDepth = 5
    g.braceDepthStack = @[1, 2, 3]
    g.inJsxMode = true

    g.typescriptNextToken()

    check g.templateLiteralDepth == 0
    check g.braceDepthStack.len == 0
    check g.inJsxMode == false

suite "syntax_typescript - typescriptNextToken advanced TypeScript patterns":
  test "discriminated union":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      "type Result = { kind: 'success'; value: string } | { kind: 'error'; error: Error };"
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type, string
    check gtKey in tokens # kind, value, error
    check gtOperator in tokens # =, |
    check gtStringLit in tokens # 'success', 'error'

  test "type guard function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      "function isString(x: unknown): x is string { return typeof x === 'string'; }"
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # function, unknown, is, string, return, typeof

  test "assertion function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(
      "function assertDefined<T>(x: T): asserts x is NonNullable<T> {}"
    )

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # function, asserts, is

  test "const assertion":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const colors = ['red', 'green', 'blue'] as const;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # const, as

  test "template literal type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type EventName = `on${string}`;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type, string
    check gtLongStringLit in tokens

  test "override modifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class Child extends Parent { override method() {} }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class, extends, override

  test "accessor modifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class Foo { accessor x: number = 0; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class, accessor, number

  test "using declaration":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("using resource = getResource();")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # using

suite "syntax_typescript - typescriptBooleans constant":
  test "typescriptBooleans contains boolean and null values":
    check "true" in typescriptBooleans
    check "false" in typescriptBooleans
    check "null" in typescriptBooleans
    check "undefined" in typescriptBooleans

suite "syntax_typescript - typescriptBuiltins constant":
  test "typescriptBuiltins contains built-in objects":
    check "Object" in typescriptBuiltins
    check "String" in typescriptBuiltins
    check "Number" in typescriptBuiltins
    check "Promise" in typescriptBuiltins
    check "Map" in typescriptBuiltins
    check "Set" in typescriptBuiltins
    check "JSON" in typescriptBuiltins
    check "RegExp" in typescriptBuiltins
    check "Math" in typescriptBuiltins
    check "Date" in typescriptBuiltins
    check "DataView" in typescriptBuiltins
    check "Symbol" in typescriptBuiltins

  test "typescriptBuiltins contains typed arrays":
    check "Int8Array" in typescriptBuiltins
    check "Int16Array" in typescriptBuiltins
    check "Int32Array" in typescriptBuiltins
    check "Uint8Array" in typescriptBuiltins
    check "Uint16Array" in typescriptBuiltins
    check "Uint32Array" in typescriptBuiltins
    check "Uint8ClampedArray" in typescriptBuiltins

suite "syntax_typescript - typescriptNextToken boolean tokens":
  test "true is boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.typescriptNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "false is boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.typescriptNextToken()
    check g.kind == gtBoolean
    check g.length == 5

  test "null is boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.typescriptNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "undefined is boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("undefined")
    g.typescriptNextToken()
    check g.kind == gtBoolean
    check g.length == 9

suite "syntax_typescript - typescriptNextToken builtin tokens":
  test "Object is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Object")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 6

  test "Promise is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Promise")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 7

  test "Map is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Map")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 3

  test "JSON is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("JSON")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

  test "Math is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Math")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

  test "Date is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Date")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

  test "DataView is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("DataView")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 8

  test "Number is builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Number")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 6

suite "syntax_typescript - typescriptNextToken function name tokens":
  test "identifier followed by paren is function name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foo(")
    g.typescriptNextToken()
    check g.kind == gtFunctionName
    check g.length == 3

  test "identifier not followed by paren is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foo ")
    g.typescriptNextToken()
    check g.kind == gtIdentifier
    check g.length == 3

  test "keyword followed by paren stays keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if(")
    g.typescriptNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "builtin followed by paren stays builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Array(")
    g.typescriptNextToken()
    check g.kind == gtBuiltin
    check g.length == 5

  test "function call in expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myFunc(x)")
    g.typescriptNextToken()
    check g.kind == gtFunctionName
    check g.length == 6

suite "syntax_typescript - typescriptNextToken decorator tokens":
  test "decorator is preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@Component")
    g.typescriptNextToken()
    check g.kind == gtPreprocessor
    check g.length == 10

  test "decorator with lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@injectable")
    g.typescriptNextToken()
    check g.kind == gtPreprocessor
    check g.length == 11

  test "at sign alone is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@ ")
    g.typescriptNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntax_typescript - keyword bug fixes":
  test "DataView and Date are separate keywords":
    check "DataView" in typescriptBuiltins
    check "Date" in typescriptBuiltins

  test "Math and Number are separate keywords":
    check "Math" in typescriptBuiltins
    check "Number" in typescriptBuiltins

  test "catch and export are separate keywords":
    check "catch" in typescriptKeywords
    check "export" in typescriptKeywords

  test "encodeURIComponent and eval are separate keywords":
    check "encodeURIComponent" in typescriptKeywords
    check "eval" in typescriptKeywords

  test "implements and protected are separate keywords":
    check "implements" in typescriptKeywords
    check "protected" in typescriptKeywords

  test "parseInt and uneval are separate keywords":
    check "parseInt" in typescriptKeywords
    check "uneval" in typescriptKeywords

  test "concatenated bugs no longer exist":
    check "DataViewDate" notin typescriptKeywords
    check "DataViewDate" notin typescriptBuiltins
    check "MathNumber" notin typescriptKeywords
    check "MathNumber" notin typescriptBuiltins
    check "catchexport" notin typescriptKeywords
    check "encodeURIComponenteval" notin typescriptKeywords
    check "implementsprotected" notin typescriptKeywords
    check "parseIntuneval" notin typescriptKeywords

suite "syntax_typescript - JSDoc highlighting":
  test "regular block comment has no JSDoc tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* @param x */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "JSDoc tag is preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @param x */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
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
      g.typescriptNextToken()
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
      g.typescriptNextToken()
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
        g.typescriptNextToken()
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
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "triple star /***/ has no preprocessor tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/***/")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "regular block comment with braces has no preprocessor tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* {string} @param */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
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
      g.typescriptNextToken()
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
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
    check g.state == gtDocLongComment
    check g.commentDepth == 1

    # Second line: * @param x
    let savedState = g.state
    let savedDepth = g.commentDepth
    g.initGeneralTokenizer(" * @param x")
    g.state = savedState
    g.commentDepth = savedDepth
    var hasPreprocessor = false
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      if g.kind == gtPreprocessor:
        hasPreprocessor = true
    check hasPreprocessor
    check g.state == gtDocLongComment

    # Third line: */
    let savedState2 = g.state
    let savedDepth2 = g.commentDepth
    g.initGeneralTokenizer(" */")
    g.state = savedState2
    g.commentDepth = savedDepth2
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
    check g.state == gtNone
    check g.commentDepth == 0

  test "JSDoc unclosed type before comment end":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** {unclosed */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor in tokens

  test "JSDoc nested braces in type annotation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @param {{key: string}} opts */")
    var kinds: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
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
      g2.typescriptNextToken()
      if g2.kind == gtEof:
        break
      if g2.kind == gtPreprocessor and g2.length > 1:
        let startIdx = g2.pos - g2.length
        if g2.buf[startIdx] == '{':
          if g2.buf[g2.pos - 1] == '}':
            foundType = true
    check foundType

  test "email address in JSDoc is not a tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** Contact user@example.com for help */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens

  test "at sign followed by number in JSDoc is not a tag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** @123 */")
    var tokens: seq[TokenClass] = @[]
    while true:
      g.typescriptNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)
    check gtPreprocessor notin tokens
