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
import ../src/moepkg/syntax/syntaxjava

suite "syntaxjava - javaKeywords constant":
  test "javaKeywords contains class definition keywords":
    check "class" in javaKeywords
    check "interface" in javaKeywords
    check "enum" in javaKeywords
    check "abstract" in javaKeywords
    check "extends" in javaKeywords
    check "implements" in javaKeywords

  test "javaKeywords contains control flow keywords":
    check "if" in javaKeywords
    check "else" in javaKeywords
    check "for" in javaKeywords
    check "while" in javaKeywords
    check "do" in javaKeywords
    check "switch" in javaKeywords
    check "case" in javaKeywords
    check "break" in javaKeywords
    check "continue" in javaKeywords
    check "return" in javaKeywords

  test "javaKeywords contains type keywords":
    check "int" in javaKeywords
    check "long" in javaKeywords
    check "short" in javaKeywords
    check "byte" in javaKeywords
    check "float" in javaKeywords
    check "double" in javaKeywords
    check "char" in javaKeywords
    check "boolean" in javaKeywords
    check "void" in javaKeywords

  test "javaKeywords contains access modifiers":
    check "public" in javaKeywords
    check "private" in javaKeywords
    check "protected" in javaKeywords
    check "static" in javaKeywords
    check "final" in javaKeywords

  test "javaKeywords contains exception handling keywords":
    check "try" in javaKeywords
    check "catch" in javaKeywords
    check "finally" in javaKeywords
    check "throw" in javaKeywords
    check "throws" in javaKeywords

  test "javaKeywords contains boolean literals":
    check "true" in javaKeywords
    check "false" in javaKeywords
    check "null" in javaKeywords

  test "javaKeywords contains other keywords":
    check "new" in javaKeywords
    check "this" in javaKeywords
    check "super" in javaKeywords
    check "import" in javaKeywords
    check "package" in javaKeywords
    check "instanceof" in javaKeywords
    check "synchronized" in javaKeywords
    check "volatile" in javaKeywords
    check "transient" in javaKeywords
    check "native" in javaKeywords

suite "syntaxjava - javaNextToken keywords":
  test "class keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "public keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "import keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "int keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "boolean keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("boolean")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "null keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.javaNextToken()
    check g.kind == gtKeyword
    check g.length == 4

suite "syntaxjava - javaNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.javaNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.javaNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "PascalCase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MyClassName")
    g.javaNextToken()
    check g.kind == gtIdentifier
    check g.length == 11

suite "syntaxjava - javaNextToken strings":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.javaNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.javaNextToken()
    check g.kind == gtStringLit
    check g.length == 2

suite "syntaxjava - javaNextToken numbers":
  test "decimal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("42")
    g.javaNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

  test "hex number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.javaNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntaxjava - javaNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// comment")
    g.javaNextToken()
    check g.kind == gtComment
    check g.length == 10

suite "syntaxjava - javaNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.javaNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.javaNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntaxjava - javaNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.javaNextToken()
    check g.kind == gtEof

  test "EOF after token":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.javaNextToken() # x
    g.javaNextToken() # EOF
    check g.kind == gtEof

suite "syntaxjava - javaNextToken doc comments":
  test "doc block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/** doc */")
    g.javaNextToken()
    check g.kind == gtDocLongComment

  test "regular block comment is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/* regular */")
    g.javaNextToken()
    check g.kind == gtLongComment

  test "empty doc comment is not doc":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**/")
    g.javaNextToken()
    check g.kind == gtLongComment

  test "multiline doc block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/**\n * @param x\n */")
    g.javaNextToken()
    check g.kind == gtDocLongComment

suite "syntaxjava - javaNextToken complete code":
  test "simple class definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("public class Main { }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.javaNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # public, class
    check gtIdentifier in tokens # Main
    check gtPunctuation in tokens # {, }
