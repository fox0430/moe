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

suite "syntax_rust - rustBooleans constant":
  test "rustBooleans contains true and false":
    check "true" in rustBooleans
    check "false" in rustBooleans

  test "rustBooleans is sorted":
    for i in 0 ..< rustBooleans.len - 1:
      check rustBooleans[i] < rustBooleans[i + 1]

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

suite "syntax_rust - rustAttributes constant":
  test "rustAttributes contains common derive/repr attributes":
    check "derive" in rustAttributes
    check "repr" in rustAttributes

  test "rustAttributes contains conditional compilation attributes":
    check "cfg" in rustAttributes
    check "cfg_attr" in rustAttributes
    check "feature" in rustAttributes

  test "rustAttributes contains lint attributes":
    check "allow" in rustAttributes
    check "deny" in rustAttributes
    check "warn" in rustAttributes
    check "forbid" in rustAttributes

  test "rustAttributes contains code generation attributes":
    check "inline" in rustAttributes
    check "must_use" in rustAttributes
    check "no_mangle" in rustAttributes
    check "non_exhaustive" in rustAttributes
    check "track_caller" in rustAttributes

  test "rustAttributes contains test attributes":
    check "test" in rustAttributes
    check "bench" in rustAttributes
    check "should_panic" in rustAttributes

  test "rustAttributes is sorted":
    for i in 0 ..< rustAttributes.len - 1:
      check rustAttributes[i] < rustAttributes[i + 1]

suite "syntax_rust - rustNextToken attributes":
  test "derive inside #[]":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[derive]")
    g.rustNextToken() # #[
    g.rustNextToken() # derive
    check g.kind == gtPreprocessor
    check g.length == 6

  test "repr inside #[]":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[repr]")
    g.rustNextToken()
    g.rustNextToken()
    check g.kind == gtPreprocessor
    check g.length == 4

  test "cfg inside #[]":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[cfg]")
    g.rustNextToken()
    g.rustNextToken()
    check g.kind == gtPreprocessor
    check g.length == 3

  test "inline inside #[]":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[inline]")
    g.rustNextToken()
    g.rustNextToken()
    check g.kind == gtPreprocessor
    check g.length == 6

  test "attribute name outside #[] is plain identifier":
    # Regression guard for the pre-fix behavior where `rustGetKeyword`
    # returned gtPreprocessor unconditionally, mis-coloring bare uses
    # of common names like `path`, `test`, `derive` in regular code.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("derive")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "attribute name regains identifier color after closing ]":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[derive] derive")
    g.rustNextToken() # #[
    g.rustNextToken() # derive (inside attr)
    check g.kind == gtPreprocessor
    g.rustNextToken() # ]
    g.rustNextToken() # whitespace
    g.rustNextToken() # derive (outside)
    check g.kind == gtIdentifier

  test "attribute bracket depth balances to 0":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[cfg(any(a = \"b\"))]")
    while g.kind != gtEof:
      g.rustNextToken()
    check g.lang.rust.attrBracketDepth == 0

  test "Clone inside #[derive] stays gtBuiltin":
    # Names that resolve to gtBuiltin (e.g. `Clone`) must keep that color
    # even inside an attribute, because rustGetKeyword consults the
    # builtins table before the attributes table.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[derive(Clone)]")
    g.rustNextToken() # #[
    g.rustNextToken() # derive
    g.rustNextToken() # (
    g.rustNextToken() # Clone
    check g.kind == gtBuiltin

  test "inner #![] also enables attribute context":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#![allow]")
    g.rustNextToken() # #![
    g.rustNextToken() # allow
    check g.kind == gtPreprocessor

  test "closing ] of attribute is highlighted as preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[derive]")
    g.rustNextToken() # #[
    g.rustNextToken() # derive
    g.rustNextToken() # ]
    check g.kind == gtPreprocessor
    check g.length == 1

  test "inner ] of nested bracket stays punctuation":
    # In `#[foo([1,2,3])]`, the inner `]` closes the array literal and
    # must NOT be preprocessor-colored; only the outer `]` that closes
    # the attribute itself is.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[foo([1,2,3])]")
    g.rustNextToken() # #[
    g.rustNextToken() # foo
    g.rustNextToken() # (
    g.rustNextToken() # [
    g.rustNextToken() # 1
    g.rustNextToken() # ,
    g.rustNextToken() # 2
    g.rustNextToken() # ,
    g.rustNextToken() # 3
    g.rustNextToken() # ]  ← inner, array close
    check g.kind == gtPunctuation
    g.rustNextToken() # )
    g.rustNextToken() # ]  ← outer, attribute close
    check g.kind == gtPreprocessor

  test "stray ] outside attribute stays punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.rustNextToken()
    check g.kind == gtPunctuation

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

  test "capital X is not a hex prefix":
    # Rust only accepts lowercase `0x`. `0XAB` is decimal `0` with the
    # malformed suffix `XAB` consumed greedily — same as `0u32`-style suffixes
    # at the lexer level.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

suite "syntax_rust - rustNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.rustNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "capital B is not a binary prefix":
    # Rust only accepts lowercase `0b`. `0B1111` becomes decimal `0` with the
    # malformed suffix `B1111`.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 6

suite "syntax_rust - rustNextToken octal numbers":
  test "octal number with 0o prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o755")
    g.rustNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

  test "leading zero is not implicit octal":
    # Rust does not have C-style implicit octal: `0755` is decimal.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

  test "capital O is not an octal prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0O7")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

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

suite "syntax_rust - rustNextToken digit separators":
  test "decimal with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1_000")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 5

  test "double underscore in decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1__000")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 6

  test "float with underscore in integer part":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1_000.5")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 7

  test "float with underscore in fraction part":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1.000_5")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 7

  test "float with underscore in exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1_0e1_0")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 7

  test "hex with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF_FF")
    g.rustNextToken()
    check g.kind == gtHexNumber
    check g.length == 7

  test "binary with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010_1010")
    g.rustNextToken()
    check g.kind == gtBinNumber
    check g.length == 11

  test "octal with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o7_77")
    g.rustNextToken()
    check g.kind == gtOctNumber
    check g.length == 6

  test "range still tokenizes after digit (no `_` in `.` lookahead)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1..2")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "method call still tokenizes after digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1.method()")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

suite "syntax_rust - rustNextToken range expressions":
  test "exclusive range 1..2":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1..2")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "inclusive range 1..=5":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1..=5")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 3
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "range with leading zero 0..10":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0..10")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 2
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

  test "method call on integer 1.method":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1.method")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 1
    g.rustNextToken()
    check g.kind == gtPunctuation
    check g.length == 1
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

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

  test "2-byte UTF-8 char (Latin small letter e with acute)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'é'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 4

  test "3-byte UTF-8 char (Hiragana)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'あ'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 5

  test "4-byte UTF-8 char (emoji)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'😀'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 6

  test "escape char regression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\n'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 4

  test "invalid UTF-8 continuation falls back to lifetime":
    # `'\xE0a'` — lead byte 0xE0 expects two 0x80..0xBF continuation
    # bytes, but `a` (0x61) is not one. The tokenizer must not consume
    # the bytes as a 3-byte char literal; it should fall back to the
    # lifetime/identifier path instead of overshooting.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\xE0a'")
    g.rustNextToken()
    check g.kind == gtIdentifier

  test "truncated UTF-8 lead at buffer end is not a char literal":
    # `'\xE0` alone (no continuation, no closing quote) — must not be
    # mis-tokenized as a valid char lit and overrun the buffer.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\xE0")
    g.rustNextToken()
    check g.kind == gtIdentifier

suite "syntax_rust - rustNextToken lifetimes":
  test "lifetime annotation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 2

  test "static lifetime":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'static")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 7

  test "underscore lifetime placeholder":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'_")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 2

  test "lifetime followed by punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a>")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 2
    g.rustNextToken()
    check g.kind == gtOperator

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

  test "string chars before a second escape stay a string token":
    # Regression: the gtStringLit resume loop used to call rustReadEscape
    # when it hit a `\` after consuming string chars, overwriting `kind`
    # and folding the preceding chars into the escape token (`bc\t` was
    # one gtEscapeSequence token instead of `bc` + `\t`).
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nbc\\td\"")

    g.rustNextToken() # "a
    check g.kind == gtStringLit

    g.rustNextToken() # \n
    check g.kind == gtEscapeSequence
    check g.length == 2

    g.rustNextToken() # bc — its own string token
    check g.kind == gtStringLit
    check g.length == 2

    g.rustNextToken() # \t
    check g.kind == gtEscapeSequence
    check g.length == 2

    g.rustNextToken() # d"
    check g.kind == gtStringLit
    check g.state == gtNone

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
    # Rust string literals can span multiple lines, emitted as one sub-token
    # per source line so per-line tokenizer-state captures stay accurate for
    # incremental re-highlighting.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\nworld\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 7 # "hello\n
    check g.state == gtLongStringLit
    g.rustNextToken()
    check g.kind == gtLongStringLit
    check g.length == 6 # world"
    check g.state == gtNone

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

  test "integer with f32 suffix promotes to gtFloatNumber":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1f32")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "integer with f64 suffix promotes to gtFloatNumber":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1f64")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "leading-zero literal with f64 suffix promotes to gtFloatNumber":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0f64")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "integer with f32 suffix and digit separators stays gtFloatNumber":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1_000f32")
    g.rustNextToken()
    check g.kind == gtFloatNumber
    check g.length == 8

  test "integer with non-float suffix stays gtDecNumber":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1isize")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 6

  test "f-prefixed but not f32/f64 suffix stays gtDecNumber":
    # `1f16` is not a valid Rust suffix; we keep it as gtDecNumber rather
    # than promoting on any `f...` to avoid mis-coloring exotic suffixes.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1f16")
    g.rustNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

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
    # Trailing `\` before buffer end parks state for line continuation.
    check g.state == gtLongStringLit
    check g.lang.rust.rawStringHashCount == 0

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

  test "outer attribute opener":
    # `#[` is recognized as a preprocessor-style opener; the body tokenizes
    # normally afterwards.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[derive(Debug)]")
    g.rustNextToken()
    check g.kind == gtPreprocessor
    check g.length == 2
    g.rustNextToken()
    check g.kind == gtPreprocessor # derive

  test "inner attribute opener":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#![allow(dead_code)]")
    g.rustNextToken()
    check g.kind == gtPreprocessor
    check g.length == 3
    g.rustNextToken()
    check g.kind == gtPreprocessor # allow

  test "bare hash is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# x")
    g.rustNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "raw string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r\"raw\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 6

  test "byte string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("b\"bytes\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 8

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

suite "syntax_rust - rustBuiltins sorting and membership":
  test "rustBuiltins is sorted (binarySearch precondition)":
    for i in 0 ..< rustBuiltins.len - 1:
      check rustBuiltins[i] < rustBuiltins[i + 1]

  test "Err and Ok are both builtins":
    check "Ok" in rustBuiltins
    check "Err" in rustBuiltins

  test "SliceConcatExt is a builtin":
    check "SliceConcatExt" in rustBuiltins

  test "Self is a keyword and not duplicated as builtin":
    check "Self" in rustKeywords
    check "Self" notin rustBuiltins

  test "Variant is not a Rust builtin":
    check "Variant" notin rustBuiltins

suite "syntax_rust - rustNextToken raw string literals":
  test "raw string with hash delimiter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r#\"raw\"#")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 8

  test "raw string with double hash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r##\"raw\"##")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 10

  test "raw string can contain inner quote":
    # r#"a "b" c"# — the inner unescaped quote does not close the string.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r#\"a \"b\" c\"#")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 12

  test "raw string ignores backslash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r\"\\n\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 5

  test "unterminated raw string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r\"unterm")
    g.rustNextToken()
    check g.kind == gtStringLit

  test "r followed by identifier char is not raw string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r2d2")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 4

  test "r alone is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r ")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

suite "syntax_rust - rustNextToken byte literals":
  test "byte char literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("b'A'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 4

  test "byte char with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("b'\\n'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 5

  test "byte raw string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("br\"raw\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "byte raw string with hash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("br#\"raw\"#")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.length == 9

  test "b followed by identifier char is not byte literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("bar")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 3

suite "syntax_rust - rustNextToken char escape sequences":
  test "newline char escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\n'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 4

  test "backslash char escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\\\'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 4

  test "null char escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\0'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 4

  test "hex char escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\xFF'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 6

  test "unicode char escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\u{1F600}'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 11

  test "single quote char escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\''")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 4

suite "syntax_rust - rustNextToken nested block comments":
  test "single level nested block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* outer /* inner */ outer */")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 29

  test "deeply nested block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* a /* b /* c */ b */ a */")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 27

suite "syntax_rust - rustNextToken unicode escape in strings":
  test "unicode escape sequence in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\u{1F600}\"")
    g.rustNextToken()
    check g.state == gtStringLit
    g.rustNextToken()
    check g.kind == gtEscapeSequence
    check g.length == 9

suite "syntax_rust - byte string escape handling":
  test "byte string with \\x escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("b\"\\x41\"")
    g.rustNextToken()
    check g.kind == gtStringLit # b" + nothing yet
    check g.state == gtStringLit
    g.rustNextToken()
    check g.kind == gtEscapeSequence
    check g.length == 4 # \x41

  test "byte string with \\u is not a unicode escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("b\"\\u{61}\"")
    g.rustNextToken()
    check g.kind == gtStringLit # b" prefix and body up to backslash
    check g.state == gtStringLit
    g.rustNextToken()
    check g.kind == gtEscapeSequence
    # Only the `\` itself is emitted as a broken-escape signal (length 1);
    # `u{61}` flows on as ordinary string text. This avoids the highlighter
    # claiming `\u{...}` is a valid escape in a byte-string context.
    check g.length == 1

  test "byte string clears flag on close":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("b\"x\"")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.lang.rust.inByteString == false

  test "regular string still highlights \\u escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\u{61}\"")
    g.rustNextToken()
    check g.state == gtStringLit
    check g.lang.rust.inByteString == false
    g.rustNextToken()
    check g.kind == gtEscapeSequence
    check g.length == 6 # \u{61}

suite "syntax_rust - rustNextToken raw identifiers":
  test "raw identifier r#fn":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r#fn")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 4

  test "raw identifier r#type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r#type")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "raw identifier with underscore start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r#_internal")
    g.rustNextToken()
    check g.kind == gtIdentifier
    check g.length == 11

  test "r# followed by digit is not a raw identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r#1")
    g.rustNextToken()
    check g.kind == gtIdentifier # "r"
    check g.length == 1
    g.rustNextToken()
    check g.kind == gtOperator # "#"
    g.rustNextToken()
    check g.kind == gtDecNumber # "1"

suite "syntax_rust - multi-line string continuation":
  test "unterminated normal string parks gtLongStringLit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"line1")
    g.rustNextToken()
    check g.kind == gtStringLit
    check g.state == gtLongStringLit
    check g.lang.rust.rawStringHashCount == 0

  test "unterminated raw string parks hash count":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r##\"line1")
    g.rustNextToken()
    check g.state == gtLongStringLit
    check g.lang.rust.rawStringHashCount == 2
    check g.lang.rust.inRawString

  test "raw string continuation closes on matching hashes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("line2\"##rest")
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 2
    g.lang.rust.inRawString = true
    g.rustNextToken()
    check g.kind == gtLongStringLit
    check g.state == gtNone
    check g.lang.rust.rawStringHashCount == 0
    check not g.lang.rust.inRawString
    check g.length == 8 # "line2\"##"

  test "raw string continuation that does not close keeps state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("still inside")
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 1
    g.lang.rust.inRawString = true
    g.rustNextToken()
    check g.kind == gtLongStringLit
    check g.state == gtLongStringLit
    check g.lang.rust.rawStringHashCount == 1
    check g.lang.rust.inRawString

  test "non-raw continuation starting with backslash does not raise":
    # Regression: previously emitted an empty token of kind gtLongStringLit
    # and tripped the rustNextToken safety raise.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\nrest\"")
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 0
    g.lang.rust.inRawString = false
    g.rustNextToken()
    check g.kind == gtEscapeSequence
    check g.length == 2 # `\n`
    g.rustNextToken()
    check g.kind == gtLongStringLit
    check g.state == gtNone

  test "raw string with zero hashes parks rustInRawString":
    # Bug fix: distinguishes `r"..."` (hash 0) from non-raw `"..."` when
    # the buffer ends mid-string.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("r\"hello")
    g.rustNextToken()
    check g.state == gtLongStringLit
    check g.lang.rust.rawStringHashCount == 0
    check g.lang.rust.inRawString

  test "raw string with zero hashes continues across buffers":
    # Regression: previously the `\\n` would be treated as an escape because
    # `(state=gtLongStringLit, hashCount=0)` collided with the non-raw case.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("backslash \\n still raw\"")
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 0
    g.lang.rust.inRawString = true
    g.rustNextToken()
    check g.kind == gtLongStringLit
    check g.state == gtNone
    check not g.lang.rust.inRawString

  test "non-raw continuation parks rustInRawString as false":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello")
    g.rustNextToken()
    check g.state == gtLongStringLit
    check not g.lang.rust.inRawString

  test "normal string continuation closes on quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("rest\"")
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 0
    g.rustNextToken()
    check g.kind == gtLongStringLit
    check g.state == gtNone
    check g.length == 5

  test "normal string continuation hits backslash and yields to escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("rest\\nmore\"")
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 0
    g.rustNextToken()
    check g.kind == gtLongStringLit
    check g.state == gtStringLit
    check g.length == 4 # "rest"
    g.rustNextToken()
    check g.kind == gtEscapeSequence # \n
    g.rustNextToken()
    check g.kind == gtStringLit # "more"
    g.rustNextToken()
    # closing " consumed as part of the trailing string token
    check g.state == gtNone

  test "empty continuation line returns gtEof":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.state = gtLongStringLit
    g.lang.rust.rawStringHashCount = 0
    g.rustNextToken()
    check g.kind == gtEof

suite "syntax_rust - rustNextToken malformed char literals":
  test "malformed hex escape consumes trailing digits and closing quote":
    # `\` after `'` rules out a lifetime, so `'\xZZ'` is a malformed char lit
    # rather than two adjacent identifier tokens.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\xZZ'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 6

  test "malformed unicode escape with bad body":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\u{XX'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 7

  test "unterminated escape char literal consumes through symbol chars":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\xAB; ")
    g.rustNextToken()
    check g.kind == gtCharLit
    # `'\xAB` — stops at `;` since it's not a sym char and not `'`.
    check g.length == 5

  test "well-formed hex escape still tokenizes correctly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\xAB'")
    g.rustNextToken()
    check g.kind == gtCharLit
    check g.length == 6

suite "syntax_rust - rustNextToken block doc comments":
  test "outer block doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** outer */")
    g.rustNextToken()
    check g.kind == gtDocLongComment
    check g.length == 12

  test "inner block doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/*! inner */")
    g.rustNextToken()
    check g.kind == gtDocLongComment
    check g.length == 12

  test "empty /**/ is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**/")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 4

  test "/***/ is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/***/")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 5

  test "/*** ... */ (3+ stars) is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/*** decorative */")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 18

  test "regular block comment is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* regular */")
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.length == 13

  test "block doc with nested non-doc stays doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** outer /* inner */ outer */")
    g.rustNextToken()
    check g.kind == gtDocLongComment
    check g.length == 30

  test "unterminated block doc parks state as gtDocLongComment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** start ")
    g.rustNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment

  test "block doc continuation closes via gtDocLongComment state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("more text */")
    g.state = gtDocLongComment
    g.lang.rust.commentDepth = 0
    g.rustNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtNone
    check g.length == 12

  test "block doc continuation EOF preserves state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("still inside")
    g.state = gtDocLongComment
    g.lang.rust.commentDepth = 0
    g.rustNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment

  test "non-doc block continuation still works":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("rest */")
    g.state = gtLongComment
    g.lang.rust.commentDepth = 0
    g.rustNextToken()
    check g.kind == gtLongComment
    check g.state == gtNone

suite "syntax_rust - line-bounded escapes and buffer-end safety":
  # Regression tests for the fuzz crash at seed 214015 (in-sequence): an
  # escaped newline inside a multi-line string left `state = gtStringLit`
  # at buffer end, producing an empty non-EOF token whose recovery stepped
  # past the NUL terminator (out-of-bounds read on the cstring buffer).

  test "escaped newline ends the sub-token and parks gtLongStringLit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\\nb\"")

    g.rustNextToken() # "a
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.rustNextToken() # \<newline> — the line-continuation escape
    check g.kind == gtEscapeSequence
    check g.length == 2
    check g.state == gtLongStringLit
    check g.lang.rust.rawStringHashCount == 0

    g.rustNextToken() # b" resumes the string on the next line
    check g.kind == gtLongStringLit
    check g.state == gtNone

    g.rustNextToken()
    check g.kind == gtEof

  test "buffer ending right after an escaped newline reaches EOF":
    # Distilled from the fuzz failure: open string, next line ends with a
    # lone `\`, then a final empty line. Must terminate at gtEof without
    # ever emitting an empty non-EOF token or scanning past the buffer.
    var g: GeneralTokenizer
    let src = "\"a }\n}\\\n"
    g.initGeneralTokenizer(src)
    var steps = 0
    while true:
      g.rustNextToken()
      if g.kind == gtEof:
        break
      check g.length > 0
      check g.start + g.length <= src.len
      inc steps
      check steps < 100

  test "string escape consumed up to buffer end yields EOF next":
    # `\x` at the very end of the buffer leaves state = gtStringLit with the
    # scan position at the terminator; the next call must yield gtEof
    # instead of an empty gtStringLit token.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\x")

    g.rustNextToken() # "a
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.rustNextToken() # \x
    check g.kind == gtEscapeSequence

    g.rustNextToken()
    check g.kind == gtEof

  test "char-literal escape never crosses the newline":
    # `'\` at end of line must not pull the next line's identifier into the
    # char-literal token; that would invalidate per-line state captures.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\\nabc")

    g.rustNextToken() # '\
    check g.kind == gtCharLit
    check g.length == 2

    g.rustNextToken() # the newline as whitespace
    check g.kind == gtWhitespace

    g.rustNextToken() # abc on its own line
    check g.kind == gtIdentifier
    check g.length == 3

  test "bare quote at end of line never absorbs the next line's quote":
    # `'` + newline + `'` used to form a single cross-line gtCharLit via
    # the closing-quote lookahead. gtCharLit is not a boundary-captured
    # kind, so the line boundary inside the token saved the post-token
    # state and an incremental reparse of the next line diverged from a
    # full reparse (`'x` became one identifier instead of charlit + ident).
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\n'x")

    g.rustNextToken() # ' alone — lifetime/identifier fallback
    check g.kind == gtIdentifier
    check g.length == 1

    g.rustNextToken() # the newline as whitespace
    check g.kind == gtWhitespace

    g.rustNextToken() # 'x on its own line
    check g.kind == gtIdentifier
    check g.length == 2

    g.rustNextToken()
    check g.kind == gtEof
