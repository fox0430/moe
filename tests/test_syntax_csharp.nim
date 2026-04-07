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

import ../src/moepkg/syntax/[tokenizer, syntax_csharp]

suite "syntax_csharp - csharpKeywords constant":
  test "csharpKeywords contains class keywords":
    check "class" in csharpKeywords
    check "interface" in csharpKeywords
    check "struct" in csharpKeywords
    check "enum" in csharpKeywords
    check "delegate" in csharpKeywords
    check "namespace" in csharpKeywords

  test "csharpKeywords contains access modifiers":
    check "public" in csharpKeywords
    check "private" in csharpKeywords
    check "protected" in csharpKeywords
    check "internal" in csharpKeywords

  test "csharpKeywords contains type modifiers":
    check "abstract" in csharpKeywords
    check "sealed" in csharpKeywords
    check "static" in csharpKeywords
    check "virtual" in csharpKeywords
    check "override" in csharpKeywords
    check "readonly" in csharpKeywords
    check "const" in csharpKeywords
    check "volatile" in csharpKeywords
    check "extern" in csharpKeywords

  test "csharpKeywords contains primitive types":
    check "bool" in csharpKeywords
    check "byte" in csharpKeywords
    check "sbyte" in csharpKeywords
    check "char" in csharpKeywords
    check "decimal" in csharpKeywords
    check "double" in csharpKeywords
    check "float" in csharpKeywords
    check "int" in csharpKeywords
    check "uint" in csharpKeywords
    check "long" in csharpKeywords
    check "ulong" in csharpKeywords
    check "short" in csharpKeywords
    check "ushort" in csharpKeywords
    check "string" in csharpKeywords
    check "object" in csharpKeywords
    check "void" in csharpKeywords

  test "csharpKeywords contains control flow keywords":
    check "if" in csharpKeywords
    check "else" in csharpKeywords
    check "switch" in csharpKeywords
    check "case" in csharpKeywords
    check "default" in csharpKeywords
    check "for" in csharpKeywords
    check "foreach" in csharpKeywords
    check "while" in csharpKeywords
    check "do" in csharpKeywords
    check "break" in csharpKeywords
    check "continue" in csharpKeywords
    check "return" in csharpKeywords
    check "goto" in csharpKeywords

  test "csharpKeywords contains exception handling keywords":
    check "try" in csharpKeywords
    check "catch" in csharpKeywords
    check "finally" in csharpKeywords
    check "throw" in csharpKeywords

  test "csharpKeywords contains boolean literals":
    check "true" in csharpKeywords
    check "false" in csharpKeywords
    check "null" in csharpKeywords

  test "csharpKeywords contains operator keywords":
    check "as" in csharpKeywords
    check "is" in csharpKeywords
    check "new" in csharpKeywords
    check "sizeof" in csharpKeywords
    check "typeof" in csharpKeywords

  test "csharpKeywords contains reference keywords":
    check "ref" in csharpKeywords
    check "out" in csharpKeywords
    check "in" in csharpKeywords
    check "params" in csharpKeywords

  test "csharpKeywords contains special keywords":
    check "this" in csharpKeywords
    check "base" in csharpKeywords
    check "using" in csharpKeywords
    check "event" in csharpKeywords
    check "operator" in csharpKeywords
    check "explicit" in csharpKeywords
    check "implicit" in csharpKeywords
    check "checked" in csharpKeywords
    check "unchecked" in csharpKeywords
    check "unsafe" in csharpKeywords
    check "fixed" in csharpKeywords
    check "stackalloc" in csharpKeywords
    check "lock" in csharpKeywords

  test "csharpKeywords is sorted":
    for i in 0 ..< csharpKeywords.len - 1:
      check csharpKeywords[i] < csharpKeywords[i + 1]

suite "syntax_csharp - csharpNextToken keywords":
  test "class keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "interface keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("interface")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "namespace keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("namespace")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "public keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "private keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("private")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "protected keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("protected")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "internal keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("internal")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "static keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("static")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "virtual keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("virtual")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "override keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("override")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "abstract keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abstract")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "sealed keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("sealed")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "foreach keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foreach")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "using keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("using")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "null keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.csharpNextToken()
    check g.kind == gtKeyword
    check g.length == 4

suite "syntax_csharp - csharpNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.csharpNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.csharpNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.csharpNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.csharpNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

suite "syntax_csharp - csharpNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.csharpNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.csharpNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

suite "syntax_csharp - csharpNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.csharpNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.csharpNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntax_csharp - csharpNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.csharpNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.csharpNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

suite "syntax_csharp - csharpNextToken string literals":
  test "simple string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.csharpNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.csharpNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with escape triggers state change":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.csharpNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntax_csharp - csharpNextToken character literals":
  test "simple char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a'")
    g.csharpNextToken()
    check g.kind == gtCharLit
    check g.length == 3

  test "escaped char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\n'")
    g.csharpNextToken()
    check g.kind == gtCharLit
    check g.length == 4

suite "syntax_csharp - csharpNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// this is a comment")
    g.csharpNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.csharpNextToken()
    check g.kind == gtLongComment
    check g.length == 13

  test "xml doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/// <summary>")
    g.csharpNextToken()
    check g.kind == gtDocComment

suite "syntax_csharp - csharpNextToken preprocessor":
  test "region directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#region")
    g.csharpNextToken()
    check g.kind == gtPreprocessor
    check g.length == 7

  test "endregion directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#endregion")
    g.csharpNextToken()
    check g.kind == gtPreprocessor
    check g.length == 10

  test "if directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#if")
    g.csharpNextToken()
    check g.kind == gtPreprocessor
    check g.length == 3

  test "define directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#define")
    g.csharpNextToken()
    check g.kind == gtPreprocessor
    check g.length == 7

suite "syntax_csharp - csharpNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "lambda operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=>")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "null conditional operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?.")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "null coalescing operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("??")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntax_csharp - csharpNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.csharpNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.csharpNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.csharpNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.csharpNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.csharpNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_csharp - csharpNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.csharpNextToken() # 'a'
    g.csharpNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.csharpNextToken() # 'a'
    g.csharpNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

suite "syntax_csharp - csharpNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.csharpNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.csharpNextToken() # 'x'
    g.csharpNextToken() # EOF
    check g.kind == gtEof

suite "syntax_csharp - csharpNextToken complete code":
  test "class definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public class MyClass { private int x; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # public, class, private, int
    check gtIdentifier in tokens # MyClass, x
    check gtPunctuation in tokens # {, ;, }

  test "interface definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public interface IMyInterface { void Method(); }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # public, interface, void
    check gtIdentifier in tokens # IMyInterface, Method

  test "namespace and using":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("using System; namespace MyApp { }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # using, namespace
    check gtIdentifier in tokens # System, MyApp

  test "foreach loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foreach (var item in items) { }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # foreach, in

  test "try catch finally":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("try { } catch (Exception e) { } finally { }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # try, catch, finally
    check gtIdentifier in tokens # Exception, e

  test "property with getter and setter":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public int Value { get; set; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # public, int
    check gtIdentifier in tokens # Value, get, set

  test "lambda expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x => x * 2")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x
    check gtOperator in tokens # =>, *
    check gtDecNumber in tokens # 2

  test "null conditional":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("obj?.Method() ?? default")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # obj, Method
    check gtOperator in tokens # ?., ??
    check gtKeyword in tokens # default

  test "async await":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("async Task Method() { await Task.Delay(1); }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # async, Task, Method, await, Delay
    check gtDecNumber in tokens # 1

  test "generic class":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class List<T> where T : class { }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class
    check gtIdentifier in tokens # List, T, where

suite "syntax_csharp - csharpNextToken edge cases":
  test "unterminated block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* unterminated")
    g.csharpNextToken()
    check g.kind == gtLongComment
    check g.length == 15

  test "unterminated string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.csharpNextToken()
    check g.kind == gtStringLit

  test "unterminated char literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'x")
    g.csharpNextToken()
    check g.kind == gtCharLit

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\nworld\"")
    g.csharpNextToken()
    check g.kind == gtStringLit
    check g.length == 6

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.csharpNextToken()
    check g.kind == gtIdentifier

suite "syntax_csharp - csharpNextToken number suffixes":
  test "integer with L suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123L")
    g.csharpNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

  test "integer with UL suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123UL")
    g.csharpNextToken()
    check g.kind == gtDecNumber
    check g.length == 5

  test "hex with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFu")
    g.csharpNextToken()
    check g.kind == gtHexNumber
    check g.length == 5

  test "float with f suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14f")
    g.csharpNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

  test "float with m suffix (decimal)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14m")
    g.csharpNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

  test "float with d suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14d")
    g.csharpNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

suite "syntax_csharp - csharpNextToken string continuation":
  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

  test "escape sequence continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")

    g.csharpNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.csharpNextToken()
    check g.kind == gtEscapeSequence

    g.csharpNextToken()
    check g.kind == gtStringLit
    check g.state == gtNone

suite "syntax_csharp - csharpNextToken colon handling":
  test "single colon is punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.csharpNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "double colon is operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("::")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "colon in generic constraint":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("where T : class")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # :
    check gtKeyword in tokens # class
    check gtIdentifier in tokens # where, T

suite "syntax_csharp - csharpNextToken additional edge cases":
  test "empty block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**/")
    g.csharpNextToken()
    check g.kind == gtLongComment
    check g.length == 4

  test "block comment with asterisks":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/****/")
    g.csharpNextToken()
    check g.kind == gtDocLongComment
    check g.length == 6

  test "preprocessor with extra spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#  region")
    g.csharpNextToken()
    check g.kind == gtPreprocessor
    check g.length == 9

suite "syntax_csharp - csharpNextToken compound operators":
  test "increment operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("++")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "decrement operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "plus equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+=")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "left shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<<")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "right shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical and operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&&")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical or operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("||")
    g.csharpNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntax_csharp - csharpNextToken float edge cases":
  test "float ending with dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5.")
    g.csharpNextToken()
    check g.kind == gtFloatNumber
    check g.length == 2

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5e3")
    g.csharpNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "float with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14f")
    g.csharpNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

suite "syntax_csharp - csharpNextToken C# specific":
  test "verbatim string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@\"path\\to\\file\"")
    g.csharpNextToken()
    # @ is treated as operator
    check g.kind == gtOperator

  test "string interpolation start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$\"Hello {name}\"")
    g.csharpNextToken()
    # $ is treated as operator
    check g.kind == gtOperator

  test "LINQ query":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("from x in list where x > 0 select x")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # from, x, list, where, select
    check gtKeyword in tokens # in
    check gtOperator in tokens # >
    check gtDecNumber in tokens # 0

  test "nullable type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int? value")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # int
    check gtOperator in tokens # ?
    check gtIdentifier in tokens # value

  test "pattern matching":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x is int i")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.csharpNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # x, i
    check gtKeyword in tokens # is, int

suite "syntax_csharp - csharpNextToken doc comments":
  test "triple slash doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/// <summary>")
    g.csharpNextToken()
    check g.kind == gtDocComment

  test "regular line comment is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// regular")
    g.csharpNextToken()
    check g.kind == gtComment

  test "doc block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** doc */")
    g.csharpNextToken()
    check g.kind == gtDocLongComment
