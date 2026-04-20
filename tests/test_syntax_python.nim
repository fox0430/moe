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

import ../src/moepkg/syntax/[tokenizer, syntax_python]

suite "syntax_python - pythonKeywords constant":
  test "pythonKeywords contains boolean values":
    check "False" in pythonKeywords
    check "None" in pythonKeywords
    check "True" in pythonKeywords

  test "pythonKeywords contains control flow keywords":
    check "if" in pythonKeywords
    check "elif" in pythonKeywords
    check "else" in pythonKeywords
    check "for" in pythonKeywords
    check "while" in pythonKeywords
    check "break" in pythonKeywords
    check "continue" in pythonKeywords
    check "return" in pythonKeywords
    check "yield" in pythonKeywords
    check "pass" in pythonKeywords

  test "pythonKeywords contains definition keywords":
    check "def" in pythonKeywords
    check "class" in pythonKeywords
    check "lambda" in pythonKeywords

  test "pythonKeywords contains exception handling keywords":
    check "try" in pythonKeywords
    check "except" in pythonKeywords
    check "finally" in pythonKeywords
    check "raise" in pythonKeywords

  test "pythonKeywords contains logical operators":
    check "and" in pythonKeywords
    check "or" in pythonKeywords
    check "not" in pythonKeywords
    check "in" in pythonKeywords
    check "is" in pythonKeywords

  test "pythonKeywords contains import keywords":
    check "import" in pythonKeywords
    check "from" in pythonKeywords
    check "as" in pythonKeywords

  test "pythonKeywords contains async keywords":
    check "async" in pythonKeywords
    check "await" in pythonKeywords

  test "pythonKeywords contains scope keywords":
    check "global" in pythonKeywords
    check "nonlocal" in pythonKeywords

  test "pythonKeywords contains other keywords":
    check "with" in pythonKeywords
    check "assert" in pythonKeywords
    check "del" in pythonKeywords

suite "syntax_python - pythonNextToken keywords":
  test "def keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("def")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "class keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "elif keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("elif")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "else keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("else")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "for keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "while keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("while")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "import keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("import")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "from keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("from")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "True keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("True")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "False keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("False")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "None keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("None")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "lambda keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("lambda")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "async keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("async")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "await keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("await")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "try keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("try")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "except keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("except")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "finally keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("finally")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "with keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("with")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "as keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("as")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "and keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("and")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "or keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("or")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "not keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("not")
    g.pythonNextToken()
    check g.kind == gtKeyword
    check g.length == 3

suite "syntax_python - pythonNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.pythonNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.pythonNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.pythonNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.pythonNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "double underscore prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("__name__")
    g.pythonNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "camelCase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVariableName")
    g.pythonNextToken()
    check g.kind == gtIdentifier
    check g.length == 14

  test "PascalCase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MyClassName")
    g.pythonNextToken()
    check g.kind == gtIdentifier
    check g.length == 11

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.pythonNextToken()
    check g.kind == gtIdentifier

suite "syntax_python - pythonNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.pythonNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.pythonNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.pythonNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntax_python - pythonNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.pythonNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.pythonNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.pythonNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFa")
    g.pythonNextToken()
    check g.kind == gtHexNumber
    check g.length == 5

suite "syntax_python - pythonNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.pythonNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.pythonNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010a")
    g.pythonNextToken()
    check g.kind == gtBinNumber
    check g.length == 7

suite "syntax_python - pythonNextToken octal numbers":
  test "octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.pythonNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

  test "octal with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755a")
    g.pythonNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

suite "syntax_python - pythonNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.pythonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.pythonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.pythonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.pythonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.pythonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

  test "float with capital E":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1E10")
    g.pythonNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

suite "syntax_python - pythonNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "empty single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

  test "single quoted string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello\\nworld'")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

  test "single-quoted string containing double quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'\"'")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 3
    check g.state != gtStringLit

  test "double-quoted string containing single quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"'\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 3
    check g.state != gtStringLit

  test "single-quoted string with escape containing double quote":
    var g: GeneralTokenizer
    # The " must not close the single-quoted string after a \ split resumes.
    g.initGeneralTokenizer("'a\\t\"b'")
    g.pythonNextToken() # 'a
    check g.kind == gtStringLit
    check g.state == gtStringLit
    g.pythonNextToken() # \t
    check g.kind == gtEscapeSequence
    check g.state == gtStringLit
    g.pythonNextToken() # "b'
    check g.kind == gtStringLit
    check g.state != gtStringLit

  test "single-line string does not span newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello\nworld'")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 6 # 'hello, up to (but not including) the newline
    check g.state != gtStringLit

suite "syntax_python - pythonNextToken string escape sequences":
  test "escape in double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.pythonNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.pythonNextToken()
    check g.kind == gtEscapeSequence

  test "numeric escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.pythonNextToken()
    check g.kind == gtEscapeSequence

  test "single hex digit escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xA\"")
    g.pythonNextToken()
    check g.state == gtStringLit

    g.pythonNextToken()
    check g.kind == gtEscapeSequence

suite "syntax_python - pythonNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.pythonNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "empty comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.pythonNextToken()
    check g.kind == gtComment
    check g.length == 1

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x # comment")

    g.pythonNextToken() # x
    check g.kind == gtIdentifier

    g.pythonNextToken() # space
    check g.kind == gtWhitespace

    g.pythonNextToken() # # comment
    check g.kind == gtComment

  test "double hash is not doc comment":
    # Python's ## is just a regular comment, not a doc comment
    var g: GeneralTokenizer
    g.initGeneralTokenizer("## TODO: fix this")
    g.pythonNextToken()
    check g.kind == gtComment
    check g.length == 17

  test "double hash only":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##")
    g.pythonNextToken()
    check g.kind == gtComment
    check g.length == 2

suite "syntax_python - pythonNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "divide operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comparison operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!=")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "less than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "greater than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "less than or equal operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<=")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "greater than or equal operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">=")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "power operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("**")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "floor division operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("//")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "modulo operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise and operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise or operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise xor operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("^")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise not operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("~")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "at operator (matrix multiplication)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "walrus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":=")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntax_python - pythonNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.pythonNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_python - pythonNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.pythonNextToken() # 'a'
    g.pythonNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.pythonNextToken() # 'a'
    g.pythonNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.pythonNextToken() # 'a'
    g.pythonNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.pythonNextToken() # 'a'
    g.pythonNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

  test "mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a \t\n b")
    g.pythonNextToken() # 'a'
    g.pythonNextToken() # ' \t\n '
    check g.kind == gtWhitespace
    check g.length == 4

suite "syntax_python - pythonNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.pythonNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.pythonNextToken() # 'x'
    g.pythonNextToken() # EOF
    check g.kind == gtEof

suite "syntax_python - pythonNextToken complete code":
  test "simple function definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("def add(a, b):\n    return a + b")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # def, return
    check gtIdentifier in tokens # add, a, b
    check gtPunctuation in tokens # (, ), ,, :
    check gtOperator in tokens # +

  test "variable declarations":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x = 10\ny = \"hello\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtDecNumber in tokens # 10
    check gtStringLit in tokens # "hello"
    check gtIdentifier in tokens # x, y

  test "class definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("class MyClass:\n    pass")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # class, pass
    check gtIdentifier in tokens # MyClass

  test "import statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("from os import path")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # from, import
    check gtIdentifier in tokens # os, path

  test "async function":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("async def fetch():\n    await get_data()")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # async, def, await

  test "try except finally":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("try:\n    x\nexcept:\n    y\nfinally:\n    z")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # try, except, finally

  test "with statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("with open(file) as f:\n    pass")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # with, as, pass

  test "list comprehension":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[x for x in range(10) if x > 5]")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # for, in, if
    check gtIdentifier in tokens # x, range
    check gtPunctuation in tokens # [, ], (, )
    check gtDecNumber in tokens # 10, 5

  test "lambda expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("f = lambda x: x * 2")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # lambda
    check gtIdentifier in tokens # f, x
    check gtOperator in tokens # =, *
    check gtDecNumber in tokens # 2

  test "comment preservation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x # comment\ny")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtComment in tokens
    check tokens.len >= 3 # at least x, comment, y

suite "syntax_python - pythonNextToken edge cases":
  test "unterminated string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.pythonNextToken()
    check g.kind == gtStringLit

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\nnext")
    g.pythonNextToken()
    check g.kind == gtStringLit
    # String is terminated at newline

  test "string terminated by carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\x0Dnext")
    g.pythonNextToken()
    check g.kind == gtStringLit

  test "escape with null terminator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.pythonNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone

  test "number with single char suffix":
    # Implementation includes one trailing letter as numeric suffix
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123abc")
    g.pythonNextToken()
    check g.kind == gtDecNumber
    check g.length == 4 # "123a"

    g.pythonNextToken()
    check g.kind == gtIdentifier
    check g.length == 2 # "bc"

  test "operator sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+=")
    g.pythonNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntax_python - pythonNextToken string continuation":
  test "string continuation after escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.pythonNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.pythonNextToken() # \n
    check g.kind == gtEscapeSequence

    g.pythonNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

suite "syntax_python - pythonNextToken decorator syntax":
  test "decorator with at sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@decorator\ndef func():\n    pass")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtOperator in tokens # @
    check gtIdentifier in tokens # decorator, func
    check gtKeyword in tokens # def, pass

suite "syntax_python - pythonNextToken modern Python syntax":
  test "walrus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if (n := len(items)) > 10:")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # if
    check gtIdentifier in tokens # n, len, items
    check gtOperator in tokens # :=, >
    check gtDecNumber in tokens # 10

  test "f-string prefix is identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("f\"value\"")
    g.pythonNextToken()
    # f is parsed as identifier
    check g.kind == gtIdentifier
    check g.length == 1

  test "type hints":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("def func(x: int) -> str:")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.pythonNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # def
    check gtIdentifier in tokens # func, x, int, str
    check gtPunctuation in tokens # (, ), :
    check gtOperator in tokens # ->

suite "syntax_python - pythonNextToken boolean and None":
  test "True in expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x = True")

    g.pythonNextToken() # x
    check g.kind == gtIdentifier

    g.pythonNextToken() # space
    g.pythonNextToken() # =
    g.pythonNextToken() # space

    g.pythonNextToken() # True
    check g.kind == gtKeyword
    check g.length == 4

  test "False in expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x = False")

    g.pythonNextToken() # x
    g.pythonNextToken() # space
    g.pythonNextToken() # =
    g.pythonNextToken() # space

    g.pythonNextToken() # False
    check g.kind == gtKeyword
    check g.length == 5

  test "None in expression":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x = None")

    g.pythonNextToken() # x
    g.pythonNextToken() # space
    g.pythonNextToken() # =
    g.pythonNextToken() # space

    g.pythonNextToken() # None
    check g.kind == gtKeyword
    check g.length == 4

suite "syntax_python - pythonNextToken special characters":
  test "unknown character":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`")
    g.pythonNextToken()
    check g.kind == gtNone

  test "backslash outside string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\")
    g.pythonNextToken()
    check g.kind == gtOperator

suite "syntax_python - pythonNextToken triple-quoted docstrings":
  test "triple double-quote docstring":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"hello world\"\"\"")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.length == 17

  test "triple single-quote docstring":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'''hello world'''")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.length == 17

  test "empty triple double-quote docstring":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"\"\"\"")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.length == 6

  test "empty triple single-quote docstring":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''''''")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.length == 6

  test "triple double-quote with embedded single quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"it's a test\"\"\"")
    g.pythonNextToken()
    check g.kind == gtDocLongComment

  test "triple single-quote with embedded double quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'''say \"hello\"'''")
    g.pythonNextToken()
    check g.kind == gtDocLongComment

  test "triple double-quote with embedded single double-quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"a \" b\"\"\"")
    g.pythonNextToken()
    check g.kind == gtDocLongComment

  test "triple double-quote with embedded double double-quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"a \"\" b\"\"\"")
    g.pythonNextToken()
    check g.kind == gtDocLongComment

  test "unterminated triple double-quote sets continuation state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"hello world")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment
    check g.commentDepth == 1

  test "unterminated triple single-quote sets continuation state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'''hello world")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment
    check g.commentDepth == 2

  test "multi-line triple double-quote continuation":
    var g: GeneralTokenizer
    # First line: opening triple quote
    g.initGeneralTokenizer("\"\"\"first line")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment
    check g.commentDepth == 1

    # Second line: simulate continuation by setting buf/pos directly
    let line2 = "second line\"\"\""
    g.buf = line2
    g.pos = 0
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtNone
    check g.commentDepth == 0

  test "multi-line triple single-quote continuation":
    var g: GeneralTokenizer
    # First line: opening triple quote
    g.initGeneralTokenizer("'''first line")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment
    check g.commentDepth == 2

    # Second line: simulate continuation
    let line2 = "second line'''"
    g.buf = line2
    g.pos = 0
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtNone
    check g.commentDepth == 0

  test "triple-quote with escape sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"test\\\"\\\"\\\"more\"\"\"")
    g.pythonNextToken()
    check g.kind == gtDocLongComment

  test "docstring after def":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("def foo():\n    \"\"\"Docstring.\"\"\"")

    # def
    g.pythonNextToken()
    check g.kind == gtKeyword

    # space
    g.pythonNextToken()
    check g.kind == gtWhitespace

    # foo
    g.pythonNextToken()
    check g.kind == gtIdentifier

    # (
    g.pythonNextToken()
    check g.kind == gtPunctuation

    # )
    g.pythonNextToken()
    check g.kind == gtPunctuation

    # :
    g.pythonNextToken()
    check g.kind == gtPunctuation

    # \n    (whitespace)
    g.pythonNextToken()
    check g.kind == gtWhitespace

    # """Docstring."""
    g.pythonNextToken()
    check g.kind == gtDocLongComment

  test "single double-quote string still works":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.pythonNextToken()
    check g.kind == gtStringLit

  test "single single-quote string still works":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.pythonNextToken()
    check g.kind == gtStringLit

  test "empty double-quote string still works":
    # "" is two quotes, not start of triple quote
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "empty single-quote string still works":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''")
    g.pythonNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "three-line triple double-quote continuation":
    var g: GeneralTokenizer
    # Line 1: opening
    g.initGeneralTokenizer("\"\"\"first")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment

    # Line 2: middle (no open/close)
    let line2 = "middle line"
    g.buf = line2
    g.pos = 0
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment

    # Line 3: closing
    let line3 = "last\"\"\""
    g.buf = line3
    g.pos = 0
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtNone
    check g.commentDepth == 0

  test "token after completed docstring":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"doc\"\"\" + x")

    # """doc"""
    g.pythonNextToken()
    check g.kind == gtDocLongComment

    # space
    g.pythonNextToken()
    check g.kind == gtWhitespace

    # +
    g.pythonNextToken()
    check g.kind == gtOperator

    # space
    g.pythonNextToken()
    check g.kind == gtWhitespace

    # x
    g.pythonNextToken()
    check g.kind == gtIdentifier

  test "backslash at end of unterminated docstring line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"test\\")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment
    check g.commentDepth == 1

  test "triple single-quote not closed by triple double-quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'''hello\"\"\"world'''")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.length == 19

  test "triple double-quote not closed by triple single-quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"hello'''world\"\"\"")
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.length == 19

  test "mismatched quotes in continuation do not close":
    var g: GeneralTokenizer
    # Open with """
    g.initGeneralTokenizer("\"\"\"start")
    g.pythonNextToken()
    check g.state == gtDocLongComment
    check g.commentDepth == 1

    # Continuation with ''' should NOT close
    let line2 = "has ''' inside"
    g.buf = line2
    g.pos = 0
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtDocLongComment

    # Close with correct """
    let line3 = "end\"\"\""
    g.buf = line3
    g.pos = 0
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtNone

  test "unterminated docstring at end-of-buffer does not assert on next call":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"unterminated")
    g.pythonNextToken()
    check g.state == gtDocLongComment

    # Simulate being called again with no more input (end-of-buffer).
    # Previously this would assert due to producing an empty token.
    let emptyBuf = ""
    g.buf = emptyBuf
    g.pos = 0
    g.pythonNextToken()
    check g.kind == gtEof

  test "token after completed continuation docstring":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"\"start")
    g.pythonNextToken()
    check g.state == gtDocLongComment

    # Closing + more tokens on same line
    let line2 = "end\"\"\" + y"
    g.buf = line2
    g.pos = 0
    g.pythonNextToken()
    check g.kind == gtDocLongComment
    check g.state == gtNone

    g.pythonNextToken()
    check g.kind == gtWhitespace

    g.pythonNextToken()
    check g.kind == gtOperator

    g.pythonNextToken()
    check g.kind == gtWhitespace

    g.pythonNextToken()
    check g.kind == gtIdentifier
