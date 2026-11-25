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

import std/[strutils, unittest]

import ../src/moepkg/syntax/[tokenizer, syntax_java]

suite "syntax_java - javaKeywords constant":
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

  test "javaBuiltinTypes contains primitive types":
    check "int" in javaBuiltinTypes
    check "int" notin javaKeywords
    check "long" in javaBuiltinTypes
    check "long" notin javaKeywords
    check "short" in javaBuiltinTypes
    check "short" notin javaKeywords
    check "byte" in javaBuiltinTypes
    check "byte" notin javaKeywords
    check "float" in javaBuiltinTypes
    check "float" notin javaKeywords
    check "double" in javaBuiltinTypes
    check "double" notin javaKeywords
    check "char" in javaBuiltinTypes
    check "char" notin javaKeywords
    check "boolean" in javaBuiltinTypes
    check "boolean" notin javaKeywords
    check "void" in javaBuiltinTypes
    check "void" notin javaKeywords

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

  test "javaBooleans contains literals":
    check "true" in javaBooleans
    check "true" notin javaKeywords
    check "false" in javaBooleans
    check "false" notin javaKeywords
    check "null" in javaBooleans
    check "null" notin javaKeywords

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

suite "syntax_java - javaNextToken keywords":
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

  test "int type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("int")
    g.javaNextToken()
    check g.kind == gtBuiltinType
    check g.length == 3

  test "boolean type":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("boolean")
    g.javaNextToken()
    check g.kind == gtBuiltinType
    check g.length == 7

  test "true literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.javaNextToken()
    check g.kind == gtBoolean
    check g.length == 4

  test "false literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.javaNextToken()
    check g.kind == gtBoolean
    check g.length == 5

  test "null literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null")
    g.javaNextToken()
    check g.kind == gtBoolean
    check g.length == 4

suite "syntax_java - javaNextToken word classes":
  test "every listed word gets its class":
    proc kindOf(word: string): TokenClass =
      var g: GeneralTokenizer
      g.initGeneralTokenizer(word)
      g.javaNextToken()
      check g.length == word.len
      g.kind

    for word in javaKeywords:
      check kindOf(word) == gtKeyword
    for word in javaBooleans:
      check kindOf(word) == gtBoolean
    for word in javaBuiltinTypes:
      check kindOf(word) == gtBuiltinType

  test "words that only contain a listed word stay identifiers":
    for word in ["trueValue", "nullable", "Boolean", "interval", "myInt"]:
      var g: GeneralTokenizer
      g.initGeneralTokenizer(word)
      g.javaNextToken()
      check g.kind == gtIdentifier
      check g.length == word.len

suite "syntax_java - javaNextToken identifiers":
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

suite "syntax_java - javaNextToken strings":
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

suite "syntax_java - javaNextToken numbers":
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

suite "syntax_java - javaNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("// comment")
    g.javaNextToken()
    check g.kind == gtComment
    check g.length == 10

suite "syntax_java - javaNextToken operators":
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

suite "syntax_java - javaNextToken EOF":
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

suite "syntax_java - javaNextToken doc comments":
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

suite "syntax_java - javaNextToken complete code":
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

suite "syntax_java - generics":
  proc angles(code: string): seq[(string, TokenClass)] =
    ## The tokens that contain `<` or `>`.
    var g: GeneralTokenizer
    g.initGeneralTokenizer(code)
    while true:
      g.javaNextToken()
      if g.kind == gtEof:
        break
      let text = code[g.start ..< g.start + g.length]
      if '\n' in text:
        check g.genericDepth == 0
      if '<' in text or '>' in text:
        result.add (text, g.kind)
    check g.genericDepth == 0

  const
    Open = ("<", gtPunctuation)
    Close = (">", gtPunctuation)
    Less = ("<", gtOperator)
    Greater = (">", gtOperator)

  test "type arguments and the diamond are punctuation":
    check angles("HashSet<Integer> set = new HashSet<>();") ==
      @[Open, Close, Open, Close]
    check angles("Map<String, List<int[]>> m;") == @[Open, Open, Close, Close]
    check angles("Class<?> c; List<? extends a.B> l;") == @[Open, Close, Open, Close]
    check angles("public <T extends A & B> void f()") == @[Open, Close]
    check angles("List.<String>of()") == @[Open, Close]

  test "comparisons, shifts and arrows are operators":
    check angles("if (a < b && c > d)") == @[("<", gtOperator), (">", gtOperator)]
    check angles("if (a<b && c>d)") == @[("<", gtOperator), (">", gtOperator)]
    check angles("for (; i<n; i++)") == @[("<", gtOperator)]
    check angles("f(a < b, c > d)") == @[("<", gtOperator), (">", gtOperator)]
    check angles("x<y>>1") == @[("<", gtOperator), (">>", gtOperator)]
    check angles("a <<= b >>> c; d <= e; f >= g; () -> h") ==
      @[
        ("<<=", gtOperator),
        (">>>", gtOperator),
        ("<=", gtOperator),
        (">=", gtOperator),
        ("->", gtOperator),
      ]

  test "bounds, wildcards, arrays and annotations are punctuation":
    check angles("<T extends Comparable<T> & A, U extends B & C> void f()") ==
      @[Open, Open, Close, Close]
    check angles("Map<?, ? super T> m;") == @[Open, Close]
    check angles("Map<? extends A<?>, ?> m;") == @[Open, Open, Close, Close]
    check angles("List<@A ? extends B> l; List<@a.A ?> k;") ==
      @[Open, Close, Open, Close]
    check angles("List<int[ ][]> l;") == @[Open, Close]
    check angles("List<T1>x=y; List<thisType> z;") == @[Open, Close, Open, Close]
    check angles("A<B<C<D>>> x;") == @[Open, Open, Open, Close, Close, Close]

  test "unspaced comparisons are operators":
    check angles("a<b>=c") == @[Less, (">=", gtOperator)]
    check angles("f(a<b, c>=d)") == @[Less, (">=", gtOperator)]
    check angles("if (a<b & c>d)") == @[Less, Greater]
    check angles("if (a<b & c>=d)") == @[Less, (">=", gtOperator)]
    check angles("r = a<b?c>d?1:2:3;") == @[Less, Greater]
    check angles("a<b[i]>c") == @[Less, Greater]
    check angles("f(a<b[i], c>d)") == @[Less, Greater]
    check angles("f(i<n, 3>k)") == @[Less, Greater]
    check angles("a<b, 1.>c") == @[Less, (">", gtOperator)]
    check angles("x<y<<z>>w, b>c") ==
      @[Less, ("<<", gtOperator), (">>", gtOperator), Greater]
    for word in [
      "this.x", "super.x", "null", "true", "false", "new A", "e instanceof B"
    ]:
      check angles("f(a<" & word & ", c>d)") == @[Less, Greater]

  test "a literal or a prefix operator after the close makes a comparison":
    for operand in ["0", " 0", "-1", "!x", "~x", "+1", ".5", "'x'", "\"x\""]:
      let tokens = angles("f(i<n, j>" & operand & ")")
      check Open notin tokens
      check Close notin tokens
    check angles("f(i<n, j > 0)") == @[Less, Greater]
    check angles("f(a<b, c<d>>1)") == @[Less, Less, (">>", gtOperator)]
    check angles("new A<B>(); A<B>::new; A<B>[] x; A<B>.C y; A<B> z") ==
      @[Open, Close, Open, Close, Open, Close, Open, Close, Open, Close]

  test "a call, an index or a literal before the open makes a comparison":
    for operand in ["a.size()", "x[0]", "1", "1.0", "0x1F", "10L", "'a'", "\"a\"", "1 "]:
      check angles("f(" & operand & "<n, m>k)") == @[Less, Greater]
    check angles("T1<A> x; a1.B2<C> y") == @[Open, Close, Open, Close]
    check angles("<T> void f() {} <U> void g()") == @[Open, Close, Open, Close]
    check angles("int[] a;\n<T> f()\n<U> g") == @[Open, Close, Open, Close]

  test "limitation: comma-separated comparisons of names read as type arguments":
    check angles("f(a<b, c>d)") == @[Open, Close]
    check angles("f(a<b, c > d)") == @[Open, Close]
    check angles("f(a<b, c<d>>e)") == @[Open, Open, Close, Close]

  test "limitation: type parameters after annotation arguments are operators":
    check angles("@A(\"x\") <T> T f()") == @[Less, Greater]

  test "deep nesting is not followed":
    let code = "A<".repeat(70) & "B" & ">".repeat(70)
    check Open notin angles(code)

  test "type arguments do not span lines":
    check angles("Map<String,\n  Integer> m;") == @[
      ("<", gtOperator), (">", gtOperator)
    ]
