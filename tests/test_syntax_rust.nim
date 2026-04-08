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

import ../src/moepkg/syntax/[tokenizer, syntax_rust]

suite "syntax_rust - rustKeywords constant":
  test "rustKeywords contains control flow keywords":
    check "if" in rustKeywords
    check "else" in rustKeywords
    check "match" in rustKeywords
    check "for" in rustKeywords
    check "while" in rustKeywords
    check "loop" in rustKeywords
    check "break" in rustKeywords
    check "continue" in rustKeywords
    check "return" in rustKeywords

  test "rustKeywords contains declaration keywords":
    check "fn" in rustKeywords
    check "let" in rustKeywords
    check "const" in rustKeywords
    check "static" in rustKeywords
    check "struct" in rustKeywords
    check "enum" in rustKeywords
    check "trait" in rustKeywords
    check "impl" in rustKeywords
    check "type" in rustKeywords
    check "mod" in rustKeywords
    check "use" in rustKeywords

  test "rustKeywords contains modifier keywords":
    check "pub" in rustKeywords
    check "mut" in rustKeywords
    check "ref" in rustKeywords
    check "unsafe" in rustKeywords
    check "async" in rustKeywords
    check "await" in rustKeywords
    check "dyn" in rustKeywords
    check "move" in rustKeywords

  test "rustKeywords contains other keywords":
    check "as" in rustKeywords
    check "crate" in rustKeywords
    check "extern" in rustKeywords
    check "in" in rustKeywords
    check "Self" in rustKeywords
    check "self" in rustKeywords
    check "super" in rustKeywords
    check "where" in rustKeywords

  test "rustKeywords is sorted":
    for i in 0 ..< rustKeywords.len - 1:
      check rustKeywords[i] < rustKeywords[i + 1]

suite "syntax_rust - rustBuiltins constant":
  test "rustBuiltins contains primitive types":
    check "bool" in rustBuiltins
    check "char" in rustBuiltins
    check "str" in rustBuiltins
    check "i8" in rustBuiltins
    check "i16" in rustBuiltins
    check "i32" in rustBuiltins
    check "i64" in rustBuiltins
    check "i128" in rustBuiltins
    check "isize" in rustBuiltins
    check "u8" in rustBuiltins
    check "u16" in rustBuiltins
    check "u32" in rustBuiltins
    check "u64" in rustBuiltins
    check "u128" in rustBuiltins
    check "usize" in rustBuiltins
    check "f32" in rustBuiltins
    check "f64" in rustBuiltins

  test "rustBuiltins contains common types":
    check "String" in rustBuiltins
    check "Vec" in rustBuiltins
    check "Box" in rustBuiltins
    check "Option" in rustBuiltins
    check "Result" in rustBuiltins

  test "rustBuiltins contains option/result variants":
    check "Some" in rustBuiltins
    check "None" in rustBuiltins
    check "Ok" in rustBuiltins

  test "rustBuiltins contains common traits":
    check "Clone" in rustBuiltins
    check "Copy" in rustBuiltins
    check "Default" in rustBuiltins
    check "Drop" in rustBuiltins
    check "Eq" in rustBuiltins
    check "Ord" in rustBuiltins
    check "PartialEq" in rustBuiltins
    check "PartialOrd" in rustBuiltins
    check "Send" in rustBuiltins
    check "Sync" in rustBuiltins
    check "Sized" in rustBuiltins

  test "rustBuiltins contains Fn traits":
    check "Fn" in rustBuiltins
    check "FnMut" in rustBuiltins
    check "FnOnce" in rustBuiltins

  test "rustBuiltins contains iterator traits":
    check "Iterator" in rustBuiltins
    check "IntoIterator" in rustBuiltins
    check "ExactSizeIterator" in rustBuiltins
    check "DoubleEndedIterator" in rustBuiltins
    check "Extend" in rustBuiltins

  test "rustBuiltins is sorted":
    for i in 0 ..< rustBuiltins.len - 1:
      check rustBuiltins[i] < rustBuiltins[i + 1]

suite "syntax_rust - rustNextToken keywords":
  test "fn keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fn")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "let keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "mut keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("mut")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "struct keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("struct")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "impl keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("impl")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "match keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("match")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "async keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("async")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "unsafe keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("unsafe")
    g.rustNextToken()
    check g.kind == gtKeyword
    check g.length == 6

suite "syntax_rust - rustNextToken booleans":
  test "true boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.rustNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "false boolean":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.rustNextToken()
    check g.kind == gtBoolean
    check g.length == 5

suite "syntax_rust - rustNextToken builtins":
  test "i32 builtin type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("i32")
    g.rustNextToken()
    check g.kind == gtBuiltin
    check g.length == 3

  test "String builtin type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("String")
    g.rustNextToken()
    check g.kind == gtBuiltin
    check g.length == 6

  test "Vec builtin type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Vec")
    g.rustNextToken()
    check g.kind == gtBuiltin
    check g.length == 3

  test "Option builtin type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Option")
    g.rustNextToken()
    check g.kind == gtBuiltin
    check g.length == 6

  test "Result builtin type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Result")
    g.rustNextToken()
    check g.kind == gtBuiltin
    check g.length == 6

  test "Some builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Some")
    g.rustNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

  test "None builtin":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("None")
    g.rustNextToken()
    check g.kind == gtBuiltin
    check g.length == 4

suite "syntax_rust - rustNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

suite "syntax_rust - rustNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntax_rust - rustNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.rustNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.rustNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.rustNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntax_rust - rustNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.rustNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.rustNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

suite "syntax_rust - rustNextToken octal numbers":
  test "octal number with 0o prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755")
    g.rustNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "octal number legacy style":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.rustNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

suite "syntax_rust - rustNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

suite "syntax_rust - rustNextToken string literals":
  test "simple string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with escape triggers state change":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntax_rust - rustNextToken character literals":
  test "simple char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 3

suite "syntax_rust - rustNextToken lifetimes":
  test "lifetime annotation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

suite "syntax_rust - rustNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// this is a comment")
    g.rustNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "empty line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("//")
    g.rustNextToken()
    check g.kind == gtComment
    check g.length == 2

  test "block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 13

  test "multiline block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* line1\nline2 */")
    g.rustNextToken()
    check g.kind == gtLongComment

  test "doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/// doc comment")
    g.rustNextToken()
    check g.kind == gtDocComment

suite "syntax_rust - rustNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "division alone is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/ x")
    g.rustNextToken()
    check g.kind == gtOperator

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comparison operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "arrow operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("->")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "fat arrow operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=>")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "ampersand operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "pipe operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "double colon operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("::")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntax_rust - rustNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "single colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(": i32")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_rust - rustNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.rustNextToken() # 'a'
    g.rustNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.rustNextToken() # 'a'
    g.rustNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.rustNextToken() # 'a'
    g.rustNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.rustNextToken() # 'a'
    g.rustNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

suite "syntax_rust - rustNextToken escape sequences":
  test "escape in string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.rustNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.rustNextToken()
    check g.state == gtStringLit

    g.rustNextToken()
    check g.kind == gtEscapeSequence

suite "syntax_rust - rustNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.rustNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.rustNextToken() # 'x'
    g.rustNextToken() # EOF
    check g.kind == gtEof

suite "syntax_rust - rustNextToken complete code":
  test "simple function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fn main() { println!(\"Hello\"); }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.rustNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # fn
    check gtIdentifier in tokens # main, println
    check gtPunctuation in tokens # (, ), {, }, ;
    check gtStringLit in tokens # "Hello"

  test "variable declaration":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let mut x: i32 = 10;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.rustNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # let, mut
    check gtIdentifier in tokens # x
    check gtBuiltin in tokens # i32
    check gtOperator in tokens # =
    check gtDecNumber in tokens # 10
    check gtPunctuation in tokens # :, ;

  test "struct definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("struct Point { x: f64, y: f64 }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.rustNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # struct
    check gtIdentifier in tokens # Point, x, y
    check gtBuiltin in tokens # f64
    check gtPunctuation in tokens # {, }, :, ,

  test "match expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("match x { Some(v) => v, None => 0 }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.rustNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # match
    check gtBuiltin in tokens # Some, None
    check gtOperator in tokens # =>
    check gtDecNumber in tokens # 0

  test "for loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for i in 0..10 { }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.rustNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # for, in
    check gtIdentifier in tokens # i
    check gtDecNumber in tokens # 0, 10

suite "syntax_rust - rustNextToken edge cases":
  test "unterminated block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* unterminated")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 15

  test "unterminated string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.rustNextToken()
    check g.kind == gtStringLit

  test "string with newline continues":
    # Rust string literals can span multiple lines
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\nworld\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with carriage return continues":
    # Rust string literals can contain carriage returns
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\rworld\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.rustNextToken()
    check g.kind == gtIdentifier

  test "empty block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**/")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 4

  test "block comment with asterisks":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/****/")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 6

suite "syntax_rust - rustNextToken number suffixes":
  test "integer with i32 suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123i32")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 6

  test "integer with u64 suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123u64")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 6

  test "hex with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFu8")
    g.rustNextToken()
    check g.kind == gtHexNumber
    check g.length == 6

  test "binary with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010i8")
    g.rustNextToken()
    check g.kind == gtBinNumber
    check g.length == 8

  test "float with f32 suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14f32")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 7

  test "float with f64 suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14f64")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 7

suite "syntax_rust - rustNextToken string continuation":
  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.rustNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

  test "escape sequence continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")

    # First token: string part before escape
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    # Second token: escape sequence
    g.rustNextToken()
    check g.kind == gtEscapeSequence

    # Third token: rest of string
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.state == gtNone

  test "hex escape sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\x41\"")

    g.rustNextToken() # empty string before escape
    check g.state == gtStringLit

    g.rustNextToken() # \x41
    check g.kind == gtEscapeSequence
    check g.length == 4

  test "numeric escape sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")

    g.rustNextToken()
    check g.state == gtStringLit

    g.rustNextToken()
    check g.kind == gtEscapeSequence

  test "escape at end of input":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")

    g.rustNextToken()
    check g.state == gtStringLit

    g.rustNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone

suite "syntax_rust - rustNextToken compound operators":
  test "increment-like operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("++")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "plus equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "minus equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "multiply equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "divide equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "modulo equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "left shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<<")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "right shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "bitwise and equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "bitwise or equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "bitwise xor equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("^=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical and operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&&")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical or operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("||")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "less than or equal operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "greater than or equal operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntax_rust - rustNextToken range operators":
  test "range operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("..")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "inclusive range operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("..=")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "rest pattern operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("...")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "single dot is punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".x")
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_rust - rustNextToken special cases":
  test "division vs comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a / b")

    g.rustNextToken() # a
    check g.kind == gtIdentifier

    g.rustNextToken() # space
    check g.kind == gtWhitespace

    g.rustNextToken() # /
    check g.kind == gtOperator
    check g.length == 1

  test "multiline block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* line1\nline2\nline3 */")
    g.rustNextToken()
    check g.kind == gtLongComment

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x = 1; // comment")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.rustNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x
    check gtOperator in tokens # =
    check gtDecNumber in tokens # 1
    check gtPunctuation in tokens # ;
    check gtComment in tokens # // comment

  test "attribute macro":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[derive(Debug)]")

    g.rustNextToken()
    # Hash is treated as operator (preprocessor not enabled by default in Rust)
    check g.kind == gtOperator

  test "raw string literal prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r\"raw\"")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

  test "byte string literal prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("b\"bytes\"")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

suite "syntax_rust - rustNextToken doc comments":
  test "outer doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/// outer doc")
    g.rustNextToken()
    check g.kind == gtDocComment

  test "inner doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("//! inner doc")
    g.rustNextToken()
    check g.kind == gtDocComment

  test "regular line comment is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// regular comment")
    g.rustNextToken()
    check g.kind == gtComment

  test "quadruple slash is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("//// not doc")
    g.rustNextToken()
    check g.kind == gtComment
