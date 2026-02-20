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
import ../src/moepkg/syntax/syntaxshell

suite "syntaxshell - shellKeywords constant":
  test "shellKeywords contains control flow keywords":
    check "if" in shellKeywords
    check "then" in shellKeywords
    check "else" in shellKeywords
    check "elif" in shellKeywords
    check "fi" in shellKeywords
    check "case" in shellKeywords
    check "esac" in shellKeywords
    check "for" in shellKeywords
    check "while" in shellKeywords
    check "until" in shellKeywords
    check "do" in shellKeywords
    check "done" in shellKeywords
    check "in" in shellKeywords
    check "select" in shellKeywords

  test "shellKeywords contains definition keywords":
    check "function" in shellKeywords
    check "alias" in shellKeywords
    check "unalias" in shellKeywords

  test "shellKeywords contains variable keywords":
    check "local" in shellKeywords
    check "declare" in shellKeywords
    check "typeset" in shellKeywords
    check "export" in shellKeywords
    check "readonly" in shellKeywords
    check "unset" in shellKeywords

  test "shellKeywords contains builtin commands":
    check "echo" in shellKeywords
    check "printf" in shellKeywords
    check "print" in shellKeywords
    check "read" in shellKeywords
    check "cd" in shellKeywords
    check "chdir" in shellKeywords
    check "pwd" in shellKeywords
    check "exit" in shellKeywords
    check "return" in shellKeywords
    check "break" in shellKeywords
    check "continue" in shellKeywords
    check "shift" in shellKeywords
    check "test" in shellKeywords
    check "eval" in shellKeywords
    check "exec" in shellKeywords
    check "source" in shellKeywords

  test "shellKeywords contains job control keywords":
    check "bg" in shellKeywords
    check "fg" in shellKeywords
    check "jobs" in shellKeywords
    check "kill" in shellKeywords
    check "wait" in shellKeywords
    check "disown" in shellKeywords
    check "suspend" in shellKeywords
    check "stop" in shellKeywords

  test "shellKeywords contains directory stack commands":
    check "pushd" in shellKeywords
    check "popd" in shellKeywords
    check "dirs" in shellKeywords

  test "shellKeywords contains shell options and history":
    check "set" in shellKeywords
    check "shopt" in shellKeywords
    check "history" in shellKeywords
    check "fc" in shellKeywords

  test "shellKeywords contains completion keywords":
    check "compgen" in shellKeywords
    check "complete" in shellKeywords

  test "shellKeywords contains other builtins":
    check "builtin" in shellKeywords
    check "command" in shellKeywords
    check "enable" in shellKeywords
    check "hash" in shellKeywords
    check "help" in shellKeywords
    check "let" in shellKeywords
    check "time" in shellKeywords
    check "times" in shellKeywords
    check "trap" in shellKeywords
    check "type" in shellKeywords
    check "ulimit" in shellKeywords
    check "umask" in shellKeywords
    check "whence" in shellKeywords
    check "getopts" in shellKeywords
    check "bind" in shellKeywords

  test "shellKeywords contains bracket keywords":
    check "[" in shellKeywords
    check "]" in shellKeywords
    check "{" in shellKeywords
    check "}" in shellKeywords

  test "shellKeywords contains login keywords":
    check "login" in shellKeywords
    check "logout" in shellKeywords
    check "newgrp" in shellKeywords

suite "syntaxshell - shellNextToken keywords":
  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "then keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("then")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "else keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("else")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "elif keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("elif")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "fi keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fi")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "case keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("case")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "esac keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("esac")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "for keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "while keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("while")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "do keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("do")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "done keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("done")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "function keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "echo keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "export keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("export")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "local keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("local")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "exit keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("exit")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "source keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("source")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "cd keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("cd")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 2

suite "syntaxshell - shellNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.shellNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.shellNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.shellNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.shellNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "uppercase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MY_VAR")
    g.shellNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.shellNextToken()
    check g.kind == gtIdentifier

suite "syntaxshell - shellNextToken decimal numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.shellNextToken()
    check g.kind == gtDecNumber
    check g.length == 3

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.shellNextToken()
    check g.kind == gtDecNumber
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.shellNextToken()
    check g.kind == gtDecNumber
    check g.length == 10

suite "syntaxshell - shellNextToken hex numbers":
  test "hex number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.shellNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.shellNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number capital X":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0XAB")
    g.shellNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "hex number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFFa")
    g.shellNextToken()
    check g.kind == gtHexNumber
    check g.length == 5

suite "syntaxshell - shellNextToken binary numbers":
  test "binary number lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.shellNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number uppercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0B1111")
    g.shellNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "binary number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010a")
    g.shellNextToken()
    check g.kind == gtBinNumber
    check g.length == 7

suite "syntaxshell - shellNextToken octal numbers":
  test "octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.shellNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

  test "octal with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755a")
    g.shellNextToken()
    check g.kind == gtOctNumber
    check g.length == 5

suite "syntaxshell - shellNextToken float numbers":
  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.shellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e10")
    g.shellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with negative exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e-5")
    g.shellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "float with positive exponent":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1e+5")
    g.shellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

  test "full float":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14159e+2")
    g.shellNextToken()
    check g.kind == gtFloatNumber
    check g.length == 10

suite "syntaxshell - shellNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "empty single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "double quoted string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

  test "single quoted string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello\\nworld'")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntaxshell - shellNextToken escape sequences":
  test "escape in double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence

  test "numeric escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence

  test "single hex digit escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xA\"")
    g.shellNextToken()
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence

suite "syntaxshell - shellNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.shellNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "empty comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.shellNextToken()
    check g.kind == gtComment
    check g.length == 1

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x # comment")

    g.shellNextToken() # x
    check g.kind == gtIdentifier

    g.shellNextToken() # space
    check g.kind == gtWhitespace

    g.shellNextToken() # # comment
    check g.kind == gtComment

suite "syntaxshell - shellNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "divide operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "comparison operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("==")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "not equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!=")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "less than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "greater than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "modulo operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("%")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise and operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise or operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise xor operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("^")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "bitwise not operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("~")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "exclamation operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "question operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "dollar sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "backslash operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "at sign":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntaxshell - shellNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.shellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.shellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.shellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.shellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.shellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "dot":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(".")
    g.shellNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxshell - shellNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.shellNextToken() # 'a'
    g.shellNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.shellNextToken() # 'a'
    g.shellNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.shellNextToken() # 'a'
    g.shellNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.shellNextToken() # 'a'
    g.shellNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

  test "mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a \t\n b")
    g.shellNextToken() # 'a'
    g.shellNextToken() # ' \t\n '
    check g.kind == gtWhitespace
    check g.length == 4

suite "syntaxshell - shellNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.shellNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.shellNextToken() # 'x'
    g.shellNextToken() # EOF
    check g.kind == gtEof

suite "syntaxshell - shellNextToken complete code":
  test "simple if statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if [ -f file ]; then echo ok; fi")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # if, then, echo, fi
    check gtIdentifier in tokens # file, ok
    check gtPunctuation in tokens # ;

  test "for loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for i in 1 2 3; do echo $i; done")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # for, in, do, echo, done
    check gtIdentifier in tokens # i
    check gtDecNumber in tokens # 1, 2, 3
    check gtOperator in tokens # $

  test "while loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("while true; do echo loop; done")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # while, do, echo, done
    check gtIdentifier in tokens # true, loop

  test "function definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function hello() { echo world; }")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # function, echo
    check gtIdentifier in tokens # hello, world
    check gtPunctuation in tokens # (, ), ;

  test "case statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("case $x in a) echo a;; esac")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # case, in, echo, esac
    check gtOperator in tokens # $
    check gtIdentifier in tokens # x, a

  test "variable assignment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MY_VAR=\"hello world\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # MY_VAR
    check gtOperator in tokens # =
    check gtStringLit in tokens # "hello world"

  test "export statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("export PATH=/usr/bin:$PATH")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # export
    check gtIdentifier in tokens # PATH
    check gtOperator in tokens # =, $

  test "command with comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo hello # this is a comment")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # echo
    check gtIdentifier in tokens # hello
    check gtComment in tokens # # this is a comment

  test "pipeline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("ls | grep foo")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # ls, grep, foo
    check gtOperator in tokens # |

  test "redirection":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo hello > file.txt")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # echo
    check gtIdentifier in tokens # hello, file
    check gtOperator in tokens # >

suite "syntaxshell - shellNextToken edge cases":
  test "unterminated double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.shellNextToken()
    check g.kind == gtStringLit

  test "unterminated single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'unterminated")
    g.shellNextToken()
    check g.kind == gtStringLit

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\nnext")
    g.shellNextToken()
    check g.kind == gtStringLit

  test "string terminated by carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\x0Dnext")
    g.shellNextToken()
    check g.kind == gtStringLit

  test "escape with null terminator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone

  test "number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123abc")
    g.shellNextToken()
    check g.kind == gtDecNumber
    check g.length == 4 # "123a"

    g.shellNextToken()
    check g.kind == gtIdentifier
    check g.length == 2 # "bc"

  test "operator sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&&")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "or operator sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("||")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "append redirection":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>")
    g.shellNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxshell - shellNextToken string continuation":
  test "string continuation after escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.shellNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken() # \n
    check g.kind == gtEscapeSequence

    g.shellNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

suite "syntaxshell - shellNextToken shebang":
  test "shebang line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#!/bin/bash")
    g.shellNextToken()
    check g.kind == gtPreprocessor
    check g.length == 11

  test "shebang with env":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#!/usr/bin/env bash")
    g.shellNextToken()
    check g.kind == gtPreprocessor
    check g.length == 19

suite "syntaxshell - shellNextToken special shell constructs":
  test "subshell":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$(ls)")

    g.shellNextToken() # $
    check g.kind == gtOperator

    g.shellNextToken() # (
    check g.kind == gtPunctuation

  test "brace expansion start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("${VAR}")

    g.shellNextToken() # $
    check g.kind == gtOperator

  test "arithmetic expansion":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$((1+2))")

    g.shellNextToken() # $
    check g.kind == gtOperator

    g.shellNextToken() # (
    check g.kind == gtPunctuation

  test "test bracket is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 1

  test "test bracket closing is keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 1

  test "brace keyword opening":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 1

  test "brace keyword closing":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.shellNextToken()
    check g.kind == gtKeyword
    check g.length == 1
