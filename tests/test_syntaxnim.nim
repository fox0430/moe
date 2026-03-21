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

import ../src/moepkg/syntax/tokenizer
import ../src/moepkg/syntax/syntaxnim

suite "syntaxnim - NimKeywords constant":
  test "NimKeywords contains all essential keywords":
    check "proc" in NimKeywords
    check "func" in NimKeywords
    check "method" in NimKeywords
    check "template" in NimKeywords
    check "macro" in NimKeywords
    check "iterator" in NimKeywords
    check "converter" in NimKeywords

  test "NimKeywords contains control flow keywords":
    check "if" in NimKeywords
    check "elif" in NimKeywords
    check "else" in NimKeywords
    check "case" in NimKeywords
    check "of" in NimKeywords
    check "when" in NimKeywords
    check "while" in NimKeywords
    check "for" in NimKeywords
    check "break" in NimKeywords
    check "continue" in NimKeywords
    check "return" in NimKeywords
    check "yield" in NimKeywords

  test "NimKeywords contains type definition keywords":
    check "type" in NimKeywords
    check "object" in NimKeywords
    check "enum" in NimKeywords
    check "tuple" in NimKeywords
    check "concept" in NimKeywords
    check "distinct" in NimKeywords

  test "NimKeywords contains declaration keywords":
    check "var" in NimKeywords
    check "let" in NimKeywords
    check "const" in NimKeywords
    check "static" in NimKeywords
    check "using" in NimKeywords

  test "NimKeywords contains exception handling keywords":
    check "try" in NimKeywords
    check "except" in NimKeywords
    check "finally" in NimKeywords
    check "raise" in NimKeywords
    check "defer" in NimKeywords

  test "NimKeywords contains operator keywords":
    check "and" in NimKeywords
    check "or" in NimKeywords
    check "not" in NimKeywords
    check "xor" in NimKeywords
    check "shl" in NimKeywords
    check "shr" in NimKeywords
    check "div" in NimKeywords
    check "mod" in NimKeywords
    check "in" in NimKeywords
    check "notin" in NimKeywords
    check "is" in NimKeywords
    check "isnot" in NimKeywords

  test "NimKeywords contains other keywords":
    check "import" in NimKeywords
    check "export" in NimKeywords
    check "include" in NimKeywords
    check "from" in NimKeywords
    check "as" in NimKeywords
    check "block" in NimKeywords
    check "do" in NimKeywords
    check "discard" in NimKeywords
    check "nil" in NimKeywords
    check "addr" in NimKeywords
    check "ptr" in NimKeywords
    check "ref" in NimKeywords
    check "cast" in NimKeywords
    check "asm" in NimKeywords
    check "bind" in NimKeywords
    check "mixin" in NimKeywords
    check "interface" in NimKeywords
    check "out" in NimKeywords
    check "end" in NimKeywords

  test "NimKeywords is sorted":
    for i in 0 ..< NimKeywords.len - 1:
      check NimKeywords[i] < NimKeywords[i + 1]

suite "syntaxnim - NimBooleans constant":
  test "NimBooleans contains true and false":
    check "true" in NimBooleans
    check "false" in NimBooleans

  test "NimBooleans has exactly 2 elements":
    check NimBooleans.len == 2

suite "syntaxnim - NimSpecialVars constant":
  test "NimSpecialVars contains result":
    check "result" in NimSpecialVars

  test "NimSpecialVars has exactly 1 element":
    check NimSpecialVars.len == 1

suite "syntaxnim - NimPragmas constant":
  test "NimPragmas contains common pragmas":
    check "inline" in NimPragmas
    check "noSideEffect" in NimPragmas
    check "deprecated" in NimPragmas
    check "exportc" in NimPragmas
    check "importc" in NimPragmas
    check "importcpp" in NimPragmas
    check "emit" in NimPragmas
    check "pure" in NimPragmas
    check "raises" in NimPragmas
    check "tags" in NimPragmas
    check "push" in NimPragmas
    check "pop" in NimPragmas
    check "pragma" in NimPragmas
    check "closure" in NimPragmas
    check "gcsafe" in NimPragmas
    check "noInit" in NimPragmas
    check "used" in NimPragmas
    check "inject" in NimPragmas
    check "gensym" in NimPragmas
    check "borrow" in NimPragmas

  test "NimPragmas contains check pragmas":
    check "assertions" in NimPragmas
    check "boundChecks" in NimPragmas
    check "nilChecks" in NimPragmas
    check "overflowChecks" in NimPragmas
    check "nanChecks" in NimPragmas
    check "infChecks" in NimPragmas
    check "floatChecks" in NimPragmas

  test "NimPragmas contains calling convention pragmas":
    check "cdecl" in NimPragmas
    check "stdcall" in NimPragmas
    check "fastcall" in NimPragmas
    check "safecall" in NimPragmas
    check "syscall" in NimPragmas
    check "nimcall" in NimPragmas
    check "noconv" in NimPragmas

  test "NimPragmas is sorted":
    for i in 0 ..< NimPragmas.len - 1:
      check NimPragmas[i] < NimPragmas[i + 1]

suite "syntaxnim - NimBuiltins constant":
  test "NimBuiltins contains basic types":
    check "int" in NimBuiltins
    check "int8" in NimBuiltins
    check "int16" in NimBuiltins
    check "int32" in NimBuiltins
    check "int64" in NimBuiltins
    check "uint" in NimBuiltins
    check "uint8" in NimBuiltins
    check "uint16" in NimBuiltins
    check "uint32" in NimBuiltins
    check "uint64" in NimBuiltins
    check "float" in NimBuiltins
    check "float32" in NimBuiltins
    check "float64" in NimBuiltins
    check "bool" in NimBuiltins
    check "char" in NimBuiltins
    check "string" in NimBuiltins
    check "cstring" in NimBuiltins

  test "NimBuiltins contains collection types":
    check "seq" in NimBuiltins
    check "array" in NimBuiltins
    check "set" in NimBuiltins
    check "openArray" in NimBuiltins

  test "NimBuiltins contains common procs":
    check "echo" in NimBuiltins
    check "len" in NimBuiltins
    check "add" in NimBuiltins
    check "inc" in NimBuiltins
    check "dec" in NimBuiltins
    check "high" in NimBuiltins
    check "low" in NimBuiltins
    check "sizeof" in NimBuiltins
    check "new" in NimBuiltins
    check "assert" in NimBuiltins
    check "quit" in NimBuiltins
    check "repr" in NimBuiltins
    check "swap" in NimBuiltins
    check "ord" in NimBuiltins
    check "chr" in NimBuiltins
    check "abs" in NimBuiltins
    check "min" in NimBuiltins
    check "max" in NimBuiltins

  test "NimBuiltins contains exception types":
    check "Exception" in NimBuiltins
    check "IOError" in NimBuiltins
    check "OSError" in NimBuiltins
    check "ValueError" in NimBuiltins
    check "KeyError" in NimBuiltins
    check "IndexError" in NimBuiltins
    check "AssertionError" in NimBuiltins
    check "OverflowError" in NimBuiltins
    check "DivByZeroError" in NimBuiltins

  test "NimBuiltins contains special objects":
    check "RootObj" in NimBuiltins
    check "RootEffect" in NimBuiltins
    check "File" in NimBuiltins
    check "NimNode" in NimBuiltins

  test "NimBuiltins is sorted":
    for i in 0 ..< NimBuiltins.len - 1:
      check NimBuiltins[i] < NimBuiltins[i + 1]

suite "syntaxnim - NimStdLibs constant":
  test "NimStdLibs contains core libraries":
    check "os" in NimStdLibs
    check "strutils" in NimStdLibs
    check "sequtils" in NimStdLibs
    check "tables" in NimStdLibs
    check "sets" in NimStdLibs
    check "algorithm" in NimStdLibs
    check "math" in NimStdLibs
    check "times" in NimStdLibs
    check "json" in NimStdLibs
    check "options" in NimStdLibs
    check "sugar" in NimStdLibs
    check "macros" in NimStdLibs
    check "unittest" in NimStdLibs

  test "NimStdLibs contains IO libraries":
    check "streams" in NimStdLibs
    check "terminal" in NimStdLibs

  test "NimStdLibs contains async libraries":
    check "asyncdispatch" in NimStdLibs
    check "asyncnet" in NimStdLibs
    check "asyncfile" in NimStdLibs
    check "asyncstreams" in NimStdLibs

  test "NimStdLibs contains parsing libraries":
    check "parseopt" in NimStdLibs
    check "parseutils" in NimStdLibs
    check "parsecfg" in NimStdLibs
    check "parsecsv" in NimStdLibs
    check "parsejson" in NimStdLibs
    check "parsexml" in NimStdLibs
    check "parsesql" in NimStdLibs

  test "NimStdLibs is sorted":
    for i in 0 ..< NimStdLibs.len - 1:
      check NimStdLibs[i] < NimStdLibs[i + 1]

suite "syntaxnim - nimNextToken keywords":
  test "proc keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("proc")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "func keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("func")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "template keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("template")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "macro keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("macro")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "var keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "let keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "const keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("const")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "case keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("case")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "import keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "nil keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("nil")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 3

suite "syntaxnim - nimNextToken booleans":
  test "true boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.nimNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "false boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.nimNextToken()
    check g.kind == gtBoolean
    check g.length == 5

suite "syntaxnim - nimNextToken special vars":
  test "result special var":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("result")
    g.nimNextToken()
    check g.kind == gtSpecialVar
    check g.length == 6

suite "syntaxnim - nimNextToken type names":
  test "capitalized identifier as type name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MyType")
    g.nimNextToken()
    check g.kind == gtTypeName
    check g.length == 6

  test "simple capitalized as type name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("T")
    g.nimNextToken()
    check g.kind == gtTypeName
    check g.length == 1

  test "PascalCase as type name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("SomeTypeName")
    g.nimNextToken()
    check g.kind == gtTypeName
    check g.length == 12

suite "syntaxnim - nimNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.nimNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.nimNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.nimNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore only identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_")
    g.nimNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

suite "syntaxnim - nimNextToken function names":
  test "identifier followed by parenthesis is function name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myFunc(")
    g.nimNextToken()
    check g.kind == gtFunctionName
    check g.length == 6

  test "identifier followed by asterisk is function name":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myFunc*")
    g.nimNextToken()
    check g.kind == gtFunctionName
    check g.length == 6

  test "keyword followed by paren is still keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("proc(")
    g.nimNextToken()
    check g.kind == gtKeyword

suite "syntaxnim - nimNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "decimal with underscores":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1_000_000")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 9

  test "single digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "decimal with type suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123'i32")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 7

  test "decimal with type suffix 'i64":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123'i64")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 7

suite "syntaxnim - nimNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with capital E exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1E10")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

  test "float with type suffix 'f32":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14'f32")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 8

  test "float with type suffix 'f64":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14'f64")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 8

suite "syntaxnim - nimNextToken hex numbers":
  test "hex number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.nimNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.nimNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number with underscores":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF_FF_FF")
    g.nimNextToken()
    check g.kind == gtHexNumber
    check g.length == 10

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.nimNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntaxnim - nimNextToken octal numbers":
  test "octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755")
    g.nimNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "octal number capital O":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0O777")
    g.nimNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "octal with underscores":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o7_5_5")
    g.nimNextToken()
    check g.kind == gtOctNumber
    check g.length == 7

suite "syntaxnim - nimNextToken binary numbers":
  test "binary number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.nimNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number capital B":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.nimNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary with underscores":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010_1010")
    g.nimNextToken()
    check g.kind == gtBinNumber
    check g.length == 11

suite "syntaxnim - nimNextToken string literals":
  test "simple string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.nimNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.nimNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.nimNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with escape triggers state change":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.nimNextToken()
    # First token is the string part before escape
    check g.kind == gtStringLit
    # State should change to indicate escape processing
    check g.state == gtStringLit

  test "triple quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"long string\"\"\"")
    g.nimNextToken()
    check g.kind == gtLongStringLit
    check g.length == 17

  test "triple quoted string multiline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"line1\nline2\"\"\"")
    g.nimNextToken()
    check g.kind == gtLongStringLit

suite "syntaxnim - nimNextToken raw strings":
  test "raw string with r prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r\"raw string\"")
    g.nimNextToken()
    # r is an identifier, followed by string
    check g.kind == gtIdentifier

  test "builtin raw string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("re\"regex\"")
    g.nimNextToken()
    # re is a builtin followed by string (becomes identifier with string)
    check g.kind == gtBuiltin

  test "fmt string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fmt\"value: {x}\"")
    g.nimNextToken()
    check g.kind == gtBuiltin

suite "syntaxnim - nimNextToken character literals":
  test "simple char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a'")
    g.nimNextToken()
    check g.kind == gtCharLit
    check g.length == 3

  test "escaped char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\n'")
    g.nimNextToken()
    check g.kind == gtCharLit
    check g.length == 4

  test "hex escaped char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\x41'")
    g.nimNextToken()
    check g.kind == gtCharLit
    check g.length == 6

  test "unicode char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'日'")
    g.nimNextToken()
    check g.kind == gtCharLit

suite "syntaxnim - nimNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.nimNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "empty comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.nimNextToken()
    check g.kind == gtComment
    check g.length == 1

  test "doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("## doc comment")
    g.nimNextToken()
    check g.kind == gtDocComment
    check g.length == 14

  test "multiline comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ multi ]#")
    g.nimNextToken()
    check g.kind == gtLongComment
    check g.length == 11

  test "nested multiline comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ outer #[ inner ]# outer ]#")
    g.nimNextToken()
    check g.kind == gtLongComment
    check g.length == 29

suite "syntaxnim - nimNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "asterisk operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "slash operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comparison operators":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "arrow operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("->")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "dot dot operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("..")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "at operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntaxnim - nimNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.nimNextToken()
    # Colon is treated as punctuation in Nim tokenizer
    check g.kind == gtPunctuation
    check g.length == 1

  test "backtick":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`")
    g.nimNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxnim - nimNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.nimNextToken() # 'a'
    g.nimNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.nimNextToken() # 'a'
    g.nimNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.nimNextToken() # 'a'
    g.nimNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.nimNextToken() # 'a'
    g.nimNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

  test "mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a \t\n b")
    g.nimNextToken() # 'a'
    g.nimNextToken() # ' \t\n '
    check g.kind == gtWhitespace
    check g.length == 4

suite "syntaxnim - nimNextToken escape sequences":
  test "escape in string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.nimNextToken() # First part of string
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.nimNextToken() # Escape sequence
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.nimNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.nimNextToken()
    check g.kind == gtEscapeSequence

  test "numeric escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")
    g.nimNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.nimNextToken()
    check g.kind == gtEscapeSequence

suite "syntaxnim - nimNextToken builtins":
  test "echo builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo")
    g.nimNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

  test "len builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("len")
    g.nimNextToken()
    check g.kind == gtBuiltin
    check g.length == 3

  test "add builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("add")
    g.nimNextToken()
    check g.kind == gtBuiltin
    check g.length == 3

  test "Exception is type name (capitalized)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Exception")
    g.nimNextToken()
    # Capitalized identifiers are treated as type names, even if in NimBuiltins
    check g.kind == gtTypeName
    check g.length == 9

suite "syntaxnim - nimNextToken stdlib":
  test "os stdlib":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("os")
    g.nimNextToken()
    check g.kind == gtBuiltin
    check g.length == 2

  test "strutils stdlib":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("strutils")
    g.nimNextToken()
    check g.kind == gtBuiltin
    check g.length == 8

  test "json stdlib":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("json")
    g.nimNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

suite "syntaxnim - nimNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.nimNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.nimNextToken() # 'x'
    g.nimNextToken() # EOF
    check g.kind == gtEof

suite "syntaxnim - nimNextToken complete code":
  test "simple proc definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("proc add(a, b: int): int = a + b")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.nimNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # proc, int
    # Note: 'add' is a builtin, not a function name
    check gtBuiltin in tokens # add, int
    check gtPunctuation in tokens # (, ), ,, :
    check gtIdentifier in tokens # a, b
    check gtOperator in tokens # =, +

  test "variable declarations":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var x = 10\nlet y = \"hello\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.nimNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # var, let
    check gtDecNumber in tokens # 10
    check gtStringLit in tokens # "hello"
    check gtIdentifier in tokens # x, y

  test "type definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("type MyType = object\n  field: int")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.nimNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # type, object
    check gtTypeName in tokens # MyType

  test "import statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import std/os, strutils")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.nimNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # import
    check gtBuiltin in tokens # os, strutils

  test "comment preservation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x # comment\ny")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.nimNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtComment in tokens
    check tokens.len >= 3 # at least x, comment, y

suite "syntaxnim - nimNextToken edge cases":
  test "identifier with leading underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.nimNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "identifier with unicode":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.nimNextToken()
    check g.kind == gtIdentifier

  test "number followed by identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123abc")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "operator sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+=")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "dot operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "unterminated string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.nimNextToken()
    check g.kind == gtStringLit

  test "unterminated char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'x")
    g.nimNextToken()
    check g.kind == gtCharLit

  test "empty triple quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"\"\"\"")
    g.nimNextToken()
    check g.kind == gtLongStringLit
    check g.length == 6

  test "asterisk paren for export+call":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*(")
    g.nimNextToken()
    check g.kind == gtSpecialVar

suite "syntaxnim - nimNextToken long string edge cases":
  test "long string with quotes inside":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"contains \"quotes\" inside\"\"\"")
    g.nimNextToken()
    check g.kind == gtLongStringLit

  test "long string with double quote inside":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"contains \"\" double\"\"\"")
    g.nimNextToken()
    check g.kind == gtLongStringLit

  test "unterminated long string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"not closed")
    g.nimNextToken()
    check g.kind == gtLongStringLit

suite "syntaxnim - nimNextToken raw data handling":
  test "identifier with invalid string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("xyz\"test\"")
    g.nimNextToken()
    # xyz is not a builtin, so the string part is raw data
    check g.kind == gtIdentifier

  test "sql builtin with string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("sql\"SELECT *\"")
    g.nimNextToken()
    check g.kind == gtBuiltin

suite "syntaxnim - nimNextToken pragmas":
  test "inline pragma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("inline")
    g.nimNextToken()
    check g.kind == gtPragma
    check g.length == 6

  test "deprecated pragma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("deprecated")
    g.nimNextToken()
    check g.kind == gtPragma
    check g.length == 10

  test "exportc pragma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("exportc")
    g.nimNextToken()
    check g.kind == gtPragma
    check g.length == 7

  test "noSideEffect pragma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("noSideEffect")
    g.nimNextToken()
    check g.kind == gtPragma
    check g.length == 12

  test "raises pragma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("raises")
    g.nimNextToken()
    check g.kind == gtPragma
    check g.length == 6

  test "cdecl pragma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("cdecl")
    g.nimNextToken()
    check g.kind == gtPragma
    check g.length == 5

suite "syntaxnim - nimNextToken keyword style insensitivity":
  test "Proc with capital P":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Proc")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "PROC all caps":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("PROC")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "pRoC mixed case":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("pRoC")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "If with capital I":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("If")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "IMPORT all caps":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("IMPORT")
    g.nimNextToken()
    check g.kind == gtKeyword
    check g.length == 6

suite "syntaxnim - nimNextToken number suffix variations":
  test "integer with 'i8 suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123'i8")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 6

  test "integer with 'i16 suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123'i16")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 7

  test "integer with 'I32 capital suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123'I32")
    g.nimNextToken()
    check g.kind == gtDecNumber
    check g.length == 7

  test "integer with 'u8 unsigned suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123'u8")
    g.nimNextToken()
    # 'u is not recognized as a special suffix, so only 123' is consumed
    check g.kind == gtDecNumber

  test "float with 'f suffix only":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14'f")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 6

  test "float with 'F capital suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14'F32")
    g.nimNextToken()
    check g.kind == gtFloatNumber
    check g.length == 8

  test "hex with type suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF'i32")
    g.nimNextToken()
    check g.kind == gtHexNumber
    check g.length == 8

  test "binary with type suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010'i8")
    g.nimNextToken()
    check g.kind == gtBinNumber
    check g.length == 9

  test "octal with type suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o777'i16")
    g.nimNextToken()
    check g.kind == gtOctNumber
    check g.length == 9

suite "syntaxnim - nimNextToken identifier with long string":
  test "identifier followed by triple quote string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r\"\"\"raw long\"\"\"")
    g.nimNextToken()
    # In Nim, identifier + """ is treated as a long string literal
    check g.kind == gtLongStringLit
    check g.length == 15

  test "builtin followed by triple quote string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("re\"\"\"regex pattern\"\"\"")
    g.nimNextToken()
    # re + """ is treated as a long string literal
    check g.kind == gtLongStringLit

suite "syntaxnim - nimNextToken string continuation":
  test "string continuation after escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.nimNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.nimNextToken() # \n
    check g.kind == gtEscapeSequence

    g.nimNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.nimNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

  test "escape at end of string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\n\"")
    g.nimNextToken() # "test
    check g.kind == gtStringLit

    g.nimNextToken() # \n
    check g.kind == gtEscapeSequence

    g.nimNextToken() # "
    check g.kind == gtStringLit

suite "syntaxnim - nimNextToken special operator cases":
  test "asterisk followed by open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*(x)")
    g.nimNextToken()
    check g.kind == gtSpecialVar

  test "standalone asterisk":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("* x")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "double asterisk":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("**")
    g.nimNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxnim - nimNextToken carriage return handling":
  test "string terminated by carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\x0Dnext")
    g.nimNextToken()
    check g.kind == gtStringLit
    # String is terminated at carriage return

  test "char terminated by carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'x\x0Dnext")
    g.nimNextToken()
    check g.kind == gtCharLit

suite "syntaxnim - nimNextToken escape edge cases":
  test "escape with null terminator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.nimNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.nimNextToken()
    check g.kind == gtEscapeSequence
    # After \0, state should reset
    check g.state == gtNone

  test "hex escape with single digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xA\"")
    g.nimNextToken()
    check g.state == gtStringLit

    g.nimNextToken()
    check g.kind == gtEscapeSequence

suite "syntaxnim - nimNextToken doc comments":
  test "doc line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("## doc comment")
    g.nimNextToken()
    check g.kind == gtDocComment
    check g.length == 14

  test "doc block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##[doc block]##")
    g.nimNextToken()
    check g.kind == gtDocLongComment

  test "regular line comment is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# regular comment")
    g.nimNextToken()
    check g.kind == gtComment

  test "regular block comment is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[regular block]#")
    g.nimNextToken()
    check g.kind == gtLongComment
