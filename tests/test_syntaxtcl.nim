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

import ../src/moepkg/syntax/[tokenizer, syntaxtcl]

suite "syntaxtcl - tclKeywords constant":
  test "tclKeywords contains control flow keywords":
    check "if" in tclKeywords
    check "else" in tclKeywords
    check "elseif" in tclKeywords
    check "for" in tclKeywords
    check "foreach" in tclKeywords
    check "while" in tclKeywords
    check "switch" in tclKeywords
    check "break" in tclKeywords
    check "continue" in tclKeywords
    check "return" in tclKeywords

  test "tclKeywords contains definition keywords":
    check "proc" in tclKeywords
    check "namespace" in tclKeywords
    check "variable" in tclKeywords
    check "global" in tclKeywords
    check "package" in tclKeywords

  test "tclKeywords contains variable keywords":
    check "set" in tclKeywords
    check "unset" in tclKeywords
    check "upvar" in tclKeywords
    check "uplevel" in tclKeywords
    check "append" in tclKeywords
    check "incr" in tclKeywords

  test "tclKeywords contains I/O commands":
    check "puts" in tclKeywords
    check "gets" in tclKeywords
    check "open" in tclKeywords
    check "close" in tclKeywords
    check "read" in tclKeywords
    check "flush" in tclKeywords
    check "seek" in tclKeywords
    check "tell" in tclKeywords
    check "eof" in tclKeywords

  test "tclKeywords contains list commands":
    check "list" in tclKeywords
    check "lappend" in tclKeywords
    check "lassign" in tclKeywords
    check "lindex" in tclKeywords
    check "linsert" in tclKeywords
    check "llength" in tclKeywords
    check "lmap" in tclKeywords
    check "lrange" in tclKeywords
    check "lrepeat" in tclKeywords
    check "lreplace" in tclKeywords
    check "lreverse" in tclKeywords
    check "lsearch" in tclKeywords
    check "lset" in tclKeywords
    check "lsort" in tclKeywords

  test "tclKeywords contains string and regexp commands":
    check "string" in tclKeywords
    check "format" in tclKeywords
    check "scan" in tclKeywords
    check "regexp" in tclKeywords
    check "regsub" in tclKeywords
    check "split" in tclKeywords
    check "join" in tclKeywords
    check "concat" in tclKeywords
    check "subst" in tclKeywords

  test "tclKeywords contains error handling commands":
    check "catch" in tclKeywords
    check "try" in tclKeywords
    check "throw" in tclKeywords
    check "error" in tclKeywords

  test "tclKeywords contains other core commands":
    check "eval" in tclKeywords
    check "exec" in tclKeywords
    check "expr" in tclKeywords
    check "source" in tclKeywords
    check "rename" in tclKeywords
    check "info" in tclKeywords
    check "after" in tclKeywords
    check "time" in tclKeywords
    check "dict" in tclKeywords
    check "array" in tclKeywords
    check "file" in tclKeywords
    check "glob" in tclKeywords
    check "cd" in tclKeywords
    check "pwd" in tclKeywords
    check "pid" in tclKeywords
    check "exit" in tclKeywords
    check "encoding" in tclKeywords
    check "socket" in tclKeywords
    check "coroutine" in tclKeywords
    check "yield" in tclKeywords
    check "yieldto" in tclKeywords
    check "tailcall" in tclKeywords

suite "syntaxtcl - tclNextToken keywords":
  test "proc keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("proc")
    g.tclNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "set keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("set")
    g.tclNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.tclNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "puts keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("puts")
    g.tclNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "foreach keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foreach")
    g.tclNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "namespace keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("namespace")
    g.tclNextToken()
    check g.kind == gtKeyword
    check g.length == 9

  test "expr keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("expr")
    g.tclNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.tclNextToken()
    check g.kind == gtKeyword
    check g.length == 6

suite "syntaxtcl - tclNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.tclNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.tclNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.tclNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.tclNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "uppercase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MY_VAR")
    g.tclNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

suite "syntaxtcl - tclNextToken variables":
  test "simple variable":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$name")
    g.tclNextToken()
    check g.kind == gtSpecialVar
    check g.length == 5

  test "variable with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$my_var")
    g.tclNextToken()
    check g.kind == gtSpecialVar
    check g.length == 7

  test "braced variable":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("${name}")
    g.tclNextToken()
    check g.kind == gtSpecialVar
    check g.length == 7

  test "braced variable with special chars":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("${my::var}")
    g.tclNextToken()
    check g.kind == gtSpecialVar
    check g.length == 10

  test "bare dollar sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$ ")
    g.tclNextToken()
    check g.kind == gtSpecialVar
    check g.length == 1

  test "variable followed by punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$x)")
    g.tclNextToken()
    check g.kind == gtSpecialVar
    check g.length == 2

suite "syntaxtcl - tclNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.tclNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.tclNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.tclNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntaxtcl - tclNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.tclNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.tclNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.tclNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

suite "syntaxtcl - tclNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.tclNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.tclNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

suite "syntaxtcl - tclNextToken octal numbers":
  test "octal number with o prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0o77")
    g.tclNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

  test "octal number with O prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0O55")
    g.tclNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

  test "octal number legacy":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.tclNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

suite "syntaxtcl - tclNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.tclNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.tclNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.tclNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.tclNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

suite "syntaxtcl - tclNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.tclNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.tclNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.tclNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "double quoted string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.tclNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntaxtcl - tclNextToken escape sequences":
  test "escape in double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.tclNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tclNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.tclNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tclNextToken()
    check g.kind == gtEscapeSequence

  test "numeric escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")
    g.tclNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tclNextToken()
    check g.kind == gtEscapeSequence

  test "string continuation after escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.tclNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tclNextToken() # \n
    check g.kind == gtEscapeSequence

    g.tclNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

suite "syntaxtcl - tclNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.tclNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "empty comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.tclNextToken()
    check g.kind == gtComment
    check g.length == 1

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x # comment")

    g.tclNextToken() # x
    check g.kind == gtIdentifier

    g.tclNextToken() # space
    check g.kind == gtWhitespace

    g.tclNextToken() # # comment
    check g.kind == gtComment

suite "syntaxtcl - tclNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!=")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "less than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "greater than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntaxtcl - tclNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.tclNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxtcl - tclNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.tclNextToken() # 'a'
    g.tclNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.tclNextToken() # 'a'
    g.tclNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.tclNextToken() # 'a'
    g.tclNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.tclNextToken() # 'a'
    g.tclNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

suite "syntaxtcl - tclNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.tclNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.tclNextToken() # 'x'
    g.tclNextToken() # EOF
    check g.kind == gtEof

suite "syntaxtcl - tclNextToken complete code":
  test "set command":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("set name \"world\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # set
    check gtIdentifier in tokens # name
    check gtStringLit in tokens # "world"

  test "puts with variable":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("puts $greeting")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # puts
    check gtSpecialVar in tokens # $greeting

  test "proc definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("proc hello {name} { puts $name }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # proc, puts
    check gtIdentifier in tokens # hello, name
    check gtSpecialVar in tokens # $name
    check gtPunctuation in tokens # {, }, {, }

  test "if statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if {$x > 0} { puts \"positive\" }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # if, puts
    check gtSpecialVar in tokens # $x
    check gtOperator in tokens # >
    check gtPunctuation in tokens # {, }, {, }
    check gtStringLit in tokens # "positive"

  test "for loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for {set i 0} {$i < 10} {incr i} { puts $i }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # for, set, incr, puts
    check gtSpecialVar in tokens # $i
    check gtDecNumber in tokens # 0, 10
    check gtPunctuation in tokens # {, }

  test "expr with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("expr {0xFF + 3.14}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # expr
    check gtHexNumber in tokens # 0xFF
    check gtFloatNumber in tokens # 3.14
    check gtOperator in tokens # +
    check gtPunctuation in tokens # {, }

  test "command with comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("puts hello # this is a comment")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # puts
    check gtIdentifier in tokens # hello
    check gtComment in tokens # # this is a comment

  test "namespace eval":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("namespace eval ::myns { variable counter 0 }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # namespace, eval, variable
    check gtPunctuation in tokens # {, }
    check gtDecNumber in tokens # 0

  test "braced variable reference":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("puts ${name}")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # puts
    check gtSpecialVar in tokens # ${name}

suite "syntaxtcl - tclNextToken edge cases":
  test "unterminated double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.tclNextToken()
    check g.kind == gtStringLit

  test "escape with null terminator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.tclNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.tclNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone

  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.tclNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

  test "number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123abc")
    g.tclNextToken()
    check g.kind == gtDecNumber
    check g.length == 4 # "123a"

    g.tclNextToken()
    check g.kind == gtIdentifier
    check g.length == 2 # "bc"

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\nnext")
    g.tclNextToken()
    check g.kind == gtStringLit

  test "string terminated by carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\x0Dnext")
    g.tclNextToken()
    check g.kind == gtStringLit

  test "unterminated braced variable":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("${noclose")
    g.tclNextToken()
    check g.kind == gtSpecialVar
    check g.length == 9

  test "zero followed by decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0.5")
    g.tclNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "zero followed by exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0e3")
    g.tclNextToken()
    check g.kind == gtFloatNumber
    check g.length == 3

  test "unknown character produces gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\x01")
    g.tclNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "single hex digit escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xA\"")
    g.tclNextToken()
    check g.state == gtStringLit

    g.tclNextToken()
    check g.kind == gtEscapeSequence

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.tclNextToken()
    check g.kind == gtIdentifier

suite "syntaxtcl - tclNextToken additional operators":
  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "divide operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "modulo operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise and operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise or operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise xor operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("^")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise not operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("~")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "exclamation operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "question operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "backslash operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "at sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "double ampersand":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&&")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "double pipe":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("||")
    g.tclNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxtcl - getNextToken dispatcher":
  test "langTcl dispatches to tclNextToken for keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("proc")
    g.getNextToken(langTcl)
    check g.kind == gtKeyword
    check g.length == 4

  test "langTcl dispatches to tclNextToken for variable":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$name")
    g.getNextToken(langTcl)
    check g.kind == gtSpecialVar
    check g.length == 5

  test "langTcl dispatches to tclNextToken for string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.getNextToken(langTcl)
    check g.kind == gtStringLit
    check g.length == 7

  test "langTcl dispatches to tclNextToken for comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.getNextToken(langTcl)
    check g.kind == gtComment

  test "langTcl full tokenization":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("set x 42")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.getNextToken(langTcl)
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check tokens == @[gtKeyword, gtWhitespace, gtIdentifier, gtWhitespace, gtDecNumber]

suite "syntaxtcl - getSourceLanguage":
  test "getSourceLanguage for Tcl":
    check getSourceLanguage("Tcl") == langTcl

  test "getSourceLanguage for tcl case insensitive":
    check getSourceLanguage("tcl") == langTcl

  test "getSourceLanguage for TCL uppercase":
    check getSourceLanguage("TCL") == langTcl
