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
import ../src/moepkg/syntax/syntaxcpp

suite "syntaxcpp - cppKeywords constant":
  test "cppKeywords contains C++ specific keywords":
    check "class" in cppKeywords
    check "public" in cppKeywords
    check "private" in cppKeywords
    check "protected" in cppKeywords
    check "virtual" in cppKeywords
    check "template" in cppKeywords
    check "new" in cppKeywords
    check "delete" in cppKeywords
    check "this" in cppKeywords
    check "friend" in cppKeywords
    check "inline" in cppKeywords
    check "operator" in cppKeywords

  test "cppKeywords contains exception handling keywords":
    check "try" in cppKeywords
    check "catch" in cppKeywords
    check "throw" in cppKeywords

  test "cppKeywords contains type keywords":
    check "char" in cppKeywords
    check "int" in cppKeywords
    check "short" in cppKeywords
    check "long" in cppKeywords
    check "float" in cppKeywords
    check "double" in cppKeywords
    check "void" in cppKeywords
    check "signed" in cppKeywords
    check "unsigned" in cppKeywords

  test "cppKeywords contains storage class keywords":
    check "auto" in cppKeywords
    check "static" in cppKeywords
    check "extern" in cppKeywords
    check "register" in cppKeywords
    check "typedef" in cppKeywords

  test "cppKeywords contains control flow keywords":
    check "if" in cppKeywords
    check "else" in cppKeywords
    check "switch" in cppKeywords
    check "case" in cppKeywords
    check "default" in cppKeywords
    check "for" in cppKeywords
    check "while" in cppKeywords
    check "do" in cppKeywords
    check "break" in cppKeywords
    check "continue" in cppKeywords
    check "return" in cppKeywords
    check "goto" in cppKeywords

  test "cppKeywords contains type modifier keywords":
    check "const" in cppKeywords
    check "volatile" in cppKeywords

  test "cppKeywords contains composite type keywords":
    check "struct" in cppKeywords
    check "union" in cppKeywords
    check "enum" in cppKeywords

  test "cppKeywords contains sizeof":
    check "sizeof" in cppKeywords

  test "cppKeywords is sorted":
    for i in 0 ..< cppKeywords.len - 1:
      check cppKeywords[i] < cppKeywords[i + 1]

suite "syntaxcpp - cppNextToken keywords":
  test "class keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "public keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "private keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("private")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "protected keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("protected")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "virtual keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("virtual")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "template keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("template")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "new keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("new")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "delete keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("delete")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "this keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("this")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "try keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("try")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "catch keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("catch")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "throw keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("throw")
    g.cppNextToken()
    check g.kind == gtKeyword
    check g.length == 5

suite "syntaxcpp - cppNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.cppNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.cppNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.cppNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.cppNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

suite "syntaxcpp - cppNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.cppNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.cppNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

suite "syntaxcpp - cppNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.cppNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.cppNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntaxcpp - cppNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.cppNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.cppNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

suite "syntaxcpp - cppNextToken string literals":
  test "simple string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.cppNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.cppNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with escape triggers state change":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.cppNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntaxcpp - cppNextToken character literals":
  test "simple char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'a'")
    g.cppNextToken()
    check g.kind == gtCharLit
    check g.length == 3

  test "escaped char":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\\n'")
    g.cppNextToken()
    check g.kind == gtCharLit
    check g.length == 4

suite "syntaxcpp - cppNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// this is a comment")
    g.cppNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* comment */")
    g.cppNextToken()
    check g.kind == gtLongComment
    check g.length == 13

suite "syntaxcpp - cppNextToken preprocessor":
  test "include directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#include")
    g.cppNextToken()
    check g.kind == gtPreprocessor
    check g.length == 8

  test "define directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#define")
    g.cppNextToken()
    check g.kind == gtPreprocessor
    check g.length == 7

suite "syntaxcpp - cppNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "scope resolution operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("::")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "arrow operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("->")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxcpp - cppNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.cppNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.cppNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.cppNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.cppNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.cppNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxcpp - cppNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.cppNextToken() # 'a'
    g.cppNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.cppNextToken() # 'a'
    g.cppNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

suite "syntaxcpp - cppNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.cppNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.cppNextToken() # 'x'
    g.cppNextToken() # EOF
    check g.kind == gtEof

suite "syntaxcpp - cppNextToken complete code":
  test "class definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class MyClass { public: int x; };")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class, public, int
    check gtIdentifier in tokens # MyClass, x
    check gtPunctuation in tokens # {, :, ;, }

  test "template function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("template<typename T> T add(T a, T b) { return a + b; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # template, return
    check gtIdentifier in tokens # typename, T, add, a, b
    check gtOperator in tokens # +

  test "new and delete":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int* p = new int(10); delete p;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # int, new, delete
    check gtIdentifier in tokens # p
    check gtDecNumber in tokens # 10
    check gtOperator in tokens # *, =

  test "try catch block":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("try { throw 1; } catch(int e) {}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # try, throw, catch, int
    check gtDecNumber in tokens # 1

  test "virtual function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("virtual void foo() = 0;")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # virtual, void
    check gtIdentifier in tokens # foo
    check gtDecNumber in tokens # 0

  test "access specifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("private: protected: public:")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # private, protected, public

  test "this pointer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("this->value")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # this
    check gtIdentifier in tokens # value
    check gtOperator in tokens # ->

suite "syntaxcpp - cppNextToken edge cases":
  test "unterminated block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* unterminated")
    g.cppNextToken()
    check g.kind == gtLongComment
    check g.length == 15

  test "unterminated string literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.cppNextToken()
    check g.kind == gtStringLit

  test "unterminated char literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'x")
    g.cppNextToken()
    check g.kind == gtCharLit

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\nworld\"")
    g.cppNextToken()
    check g.kind == gtStringLit
    check g.length == 6

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.cppNextToken()
    check g.kind == gtIdentifier

suite "syntaxcpp - cppNextToken number suffixes":
  test "integer with L suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123L")
    g.cppNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

  test "integer with LL suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123LL")
    g.cppNextToken()
    check g.kind == gtDecNumber
    check g.length == 5

  test "hex with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFu")
    g.cppNextToken()
    check g.kind == gtHexNumber
    check g.length == 5

  test "float with f suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14f")
    g.cppNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

suite "syntaxcpp - cppNextToken string continuation":
  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

  test "escape sequence continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")

    g.cppNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.cppNextToken()
    check g.kind == gtEscapeSequence

    g.cppNextToken()
    check g.kind == gtStringLit
    check g.state == gtNone

suite "syntaxcpp - cppNextToken scope resolution":
  test "namespace access":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("std::cout")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # std, cout
    check gtOperator in tokens # ::

  test "nested namespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a::b::c")

    var kinds: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      kinds.add(g.kind)

    # Should be: identifier, operator, identifier, operator, identifier
    check kinds.len == 5
    check kinds[0] == gtIdentifier
    check kinds[1] == gtOperator
    check kinds[2] == gtIdentifier
    check kinds[3] == gtOperator
    check kinds[4] == gtIdentifier

suite "syntaxcpp - cppNextToken additional edge cases":
  test "empty block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**/")
    g.cppNextToken()
    check g.kind == gtLongComment
    check g.length == 4

  test "block comment with asterisks":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/****/")
    g.cppNextToken()
    check g.kind == gtLongComment
    check g.length == 6

  test "preprocessor with extra spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#  include")
    g.cppNextToken()
    check g.kind == gtPreprocessor
    check g.length == 10

suite "syntaxcpp - cppNextToken compound operators":
  test "increment operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("++")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "decrement operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "plus equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+=")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "left shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<<")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "right shift operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical and operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&&")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "logical or operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("||")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxcpp - cppNextToken float edge cases":
  test "float ending with dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5.")
    g.cppNextToken()
    check g.kind == gtFloatNumber
    check g.length == 2

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("5e3")
    g.cppNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "float with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14f")
    g.cppNextToken()
    check g.kind == gtFloatNumber
    check g.length == 5

suite "syntaxcpp - cppNextToken C++ specific":
  test "pointer to member":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("->*")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "member pointer":
    # Note: .* is split into . (punctuation) and * (operator)
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".*")
    g.cppNextToken()
    check g.kind == gtPunctuation
    check g.length == 1
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "spaceship operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<=>")
    g.cppNextToken()
    check g.kind == gtOperator
    check g.length == 3

  test "range-based for":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for (auto x : vec)")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # for, auto
    check gtIdentifier in tokens # x, vec
    check gtPunctuation in tokens # (, ), :

  test "lambda expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[](int x) { return x; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.cppNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtPunctuation in tokens # [, ], (, ), {, }, ;
    check gtKeyword in tokens # int, return
    check gtIdentifier in tokens # x
