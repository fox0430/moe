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

import ../src/moepkg/syntax/[tokenizer, syntax_shell]

suite "syntax_shell - shellKeywords constant":
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

suite "syntax_shell - shellNextToken keywords":
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

suite "syntax_shell - shellNextToken identifiers":
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

suite "syntax_shell - shellNextToken decimal numbers":
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

suite "syntax_shell - shellNextToken hex numbers":
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

suite "syntax_shell - shellNextToken binary numbers":
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

suite "syntax_shell - shellNextToken octal numbers":
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

suite "syntax_shell - shellNextToken float numbers":
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

suite "syntax_shell - shellNextToken string literals":
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
    g.initGeneralTokenizer("\"hello\\$world\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

  test "a backslash before other characters in a double quoted string is literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\x41\\1\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.length == 12
    check g.state == gtNone

  test "a backslash in a single quoted string is literal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello\\nworld'")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.length == 14
    check g.state == gtNone

suite "syntax_shell - shellNextToken escape sequences":
  test "escape in double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\\"world\"")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$'\\xFF'")
    g.shellNextToken() # $
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence

  test "numeric escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$'\\123'")
    g.shellNextToken() # $
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence

  test "single hex digit escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$'\\xA'")
    g.shellNextToken() # $
    g.shellNextToken()
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEscapeSequence

suite "syntax_shell - shellNextToken comments":
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

suite "syntax_shell - shellNextToken operators":
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

suite "syntax_shell - shellNextToken punctuation":
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

suite "syntax_shell - shellNextToken whitespace":
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

suite "syntax_shell - shellNextToken EOF":
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

suite "syntax_shell - shellNextToken complete code":
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

suite "syntax_shell - shellNextToken edge cases":
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
    g.initGeneralTokenizer("\"test\rnext")
    g.shellNextToken()
    check g.kind == gtStringLit

  test "a backslash right before the end of the text stays in the string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.shellNextToken()
    check g.kind == gtStringLit
    check g.length == 6
    check g.state == gtStringLit

    g.shellNextToken()
    check g.kind == gtEof

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

suite "syntax_shell - shellNextToken string continuation":
  test "string continuation after escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\\"world\"")
    g.shellNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.shellNextToken() # \"
    check g.kind == gtEscapeSequence

    g.shellNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\$b\\`c\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

suite "syntax_shell - shellNextToken shebang":
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

suite "syntax_shell - shellNextToken special shell constructs":
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

suite "syntax_shell - heredocs":
  proc kinds(text: string): seq[(TokenClass, string)] =
    var g: GeneralTokenizer
    g.initGeneralTokenizer(text)
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      if g.kind != gtWhitespace:
        result.add (g.kind, text[g.start ..< g.start + g.length])

  test "the body is a string up to the end marker":
    check kinds("cat <<EOF\n  {\n}\nEOF\necho }") ==
      @[
        (gtIdentifier, "cat"),
        (gtOperator, "<<"),
        (gtIdentifier, "EOF"),
        (gtLongStringLit, "  {\n"),
        (gtLongStringLit, "}\n"),
        (gtKeyword, "EOF"),
        (gtKeyword, "echo"),
        (gtKeyword, "}"),
      ]

  test "the rest of the opening line is code":
    check kinds("cat <<EOF | sort # c\nx\nEOF")[3 .. ^1] ==
      @[
        (gtOperator, "|"),
        (gtIdentifier, "sort"),
        (gtComment, "# c"),
        (gtLongStringLit, "x\n"),
        (gtKeyword, "EOF"),
      ]

  test "a quoted or escaped marker ends at its text":
    check kinds("cat <<'E F'\nx\nE F")[^1] == (gtKeyword, "E F")
    check kinds("cat <<\"EOF\"\nx\nEOF")[^1] == (gtKeyword, "EOF")
    check kinds("cat <<\\EOF\nx\nEOF")[^1] == (gtKeyword, "EOF")

  test "with `<<-`, tabs may come before the end marker":
    check kinds("cat <<-EOF\n\tx\n\tEOF\ny")[^2] == (gtKeyword, "\tEOF")
    check kinds("cat <<EOF\n\tEOF\nEOF")[^2] == (gtLongStringLit, "\tEOF\n")

  test "a marker with more on its line does not end the body":
    check kinds("cat <<EOF\nEOF x\n EOF\nEOF")[3 .. ^1] ==
      @[(gtLongStringLit, "EOF x\n"), (gtLongStringLit, " EOF\n"), (gtKeyword, "EOF")]

  test "a here-string and an arithmetic shift open no body":
    check kinds("tr a b <<< x\n{")[^1] == (gtKeyword, "{")
    check kinds("x=$((1<<2))\n{")[^1] == (gtKeyword, "{")
    check kinds("((x <<= 2))\n{")[^1] == (gtKeyword, "{")

  test "a shift by a variable in arithmetic opens no body":
    check kinds("mask=$(( (1 << width) - 1 ))\necho }")[^1] == (gtKeyword, "}")
    check kinds("(( x = y << n ))\n{")[^1] == (gtKeyword, "{")
    check kinds("x=$((\n  1 << n\n))\n{")[^1] == (gtKeyword, "{")
    check kinds("(( x << 1 )); cat <<EOF\n{\nEOF")[^2] == (gtLongStringLit, "{\n")

  test "a `#` inside a word in arithmetic does not hide its closing parentheses":
    check kinds("n=$(( ${#arr[@]} - 1 ))\ncat <<EOF\n{\nEOF")[^2] ==
      (gtLongStringLit, "{\n")
    check kinds("n=$(( $# - 1 ))\ncat <<EOF\n{\nEOF")[^2] == (gtLongStringLit, "{\n")
    check kinds("n=$((10#$x))\ncat <<EOF\n{\nEOF")[^2] == (gtLongStringLit, "{\n")

  test "a shift in `$[ ]` arithmetic opens no body":
    check kinds("x=$[a<<n]\n{")[^1] == (gtKeyword, "{")
    check kinds("x=$[a[1]<<n]; cat <<EOF\n{\nEOF")[^2] == (gtLongStringLit, "{\n")

  test "the body starts after a `\\` continuation":
    check kinds("cat <<EOF \\\n| sort\nbody\nEOF")[3 .. ^1] ==
      @[
        (gtOperator, "\\\n"),
        (gtOperator, "|"),
        (gtIdentifier, "sort"),
        (gtLongStringLit, "body\n"),
        (gtKeyword, "EOF"),
      ]
    check kinds("cat <<EOF x\\\\\n{\nEOF")[^2] == (gtLongStringLit, "{\n")

  test "a `#` right after a redirection starts a comment":
    check kinds("echo a >#b")[^1] == (gtComment, "#b")

  test "a heredoc after a string that spans lines opens after it closes":
    check kinds("cat <<EOF \"a\nb\"\n{\nEOF")[3 .. ^1] ==
      @[
        (gtStringLit, "\"a\n"),
        (gtStringLit, "b\""),
        (gtLongStringLit, "{\n"),
        (gtKeyword, "EOF"),
      ]

  test "a line resumes inside the body from the state at its start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("cat <<EOF\n")
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
    check g.state == gtLongStringLit
    var resumed: GeneralTokenizer
    resumed.initGeneralTokenizer("}\nEOF")
    resumed.state = g.state
    resumed.lang = g.lang
    resumed.shellNextToken()
    check resumed.kind == gtLongStringLit
    resumed.shellNextToken()
    check resumed.kind == gtKeyword
    check resumed.state == gtNone

suite "syntax_shell - strings across lines":
  proc kinds(text: string): seq[(TokenClass, string)] =
    var g: GeneralTokenizer
    g.initGeneralTokenizer(text)
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
      if g.kind != gtWhitespace:
        result.add (g.kind, text[g.start ..< g.start + g.length])

  test "a quoted string goes on to its closing quote, one token per line":
    check kinds("x='a\n# b\n' {") ==
      @[
        (gtIdentifier, "x"),
        (gtOperator, "="),
        (gtStringLit, "'a\n"),
        (gtStringLit, "# b\n"),
        (gtStringLit, "'"),
        (gtKeyword, "{"),
      ]
    check kinds("x=\"a\r\nb\"")[2 .. ^1] ==
      @[(gtStringLit, "\"a\r\n"), (gtStringLit, "b\"")]

  test "a `<<` inside a string opens no heredoc":
    check kinds("python3 -c '\nx = 1 << n\n'\n{")[^1] == (gtKeyword, "{")
    check kinds("x=\"a\nb << EOF c\"\n{")[^1] == (gtKeyword, "{")

  test "escapes work in double quoted and `$'` strings, not single quoted ones":
    check kinds("\"a\\\"b\" {")[^1] == (gtKeyword, "{")
    check kinds("$'a\\'b' {")[^1] == (gtKeyword, "{")
    check kinds("'a\\' {")[^1] == (gtKeyword, "{")

  test "an escaped line break goes on with the string":
    check kinds("\"a\\\nb\" {") ==
      @[
        (gtStringLit, "\"a"),
        (gtEscapeSequence, "\\\n"),
        (gtStringLit, "b\""),
        (gtKeyword, "{"),
      ]

  test "a line resumes inside the string from the state at its start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo 'a\n")
    while true:
      g.shellNextToken()
      if g.kind == gtEof:
        break
    check g.state == gtStringLit
    var resumed: GeneralTokenizer
    resumed.initGeneralTokenizer("\"b' {")
    resumed.state = g.state
    resumed.lang = g.lang
    resumed.shellNextToken()
    check resumed.kind == gtStringLit
    check resumed.length == 3
    check resumed.state == gtNone

  test "a backslash quotes the next character outside a string":
    check kinds("echo It\\'s ok\nls")[^1] == (gtIdentifier, "ls")
    check kinds("grep \\\"x\\\" f\n{")[^1] == (gtKeyword, "{")
    check kinds("echo \\$'a\\'b c")[^1] == (gtIdentifier, "c")

  test "a command substitution in a double quoted string holds its own strings":
    check kinds("msg=\"$(gettext \"Don't\")\"\nls")[^1] == (gtIdentifier, "ls")
    check kinds("x=\"`echo \"a'b\"`\"\n{")[^1] == (gtKeyword, "{")
    check kinds("x=\"$(echo $(date) \"(\")\" '\n{")[^1] == (gtStringLit, "{")

  test "a heredoc opened in a command substitution in a string":
    check kinds("x=\"$(cat <<EOF\nit's {\nEOF\n)\"\necho }")[^6 .. ^1] ==
      @[
        (gtLongStringLit, "it's {\n"),
        (gtKeyword, "EOF"),
        (gtPunctuation, ")"),
        (gtStringLit, "\""),
        (gtKeyword, "echo"),
        (gtKeyword, "}"),
      ]

  test "arithmetic in a string is not a heredoc":
    check kinds("x=\"$((1 << n))\"\n{")[^1] == (gtKeyword, "{")

  test "a `<<` later in an operator run opens a heredoc":
    check kinds("python3 -<<EOF\nit's\nEOF\nls")[^3 .. ^1] ==
      @[(gtLongStringLit, "it's\n"), (gtKeyword, "EOF"), (gtIdentifier, "ls")]
    check kinds("tr a b <<<x\n{")[^1] == (gtKeyword, "{")

  test "a marker may start with any character but a metacharacter":
    check kinds("ftp -n <<!\nit's\n!\nls")[^3 .. ^1] ==
      @[(gtLongStringLit, "it's\n"), (gtKeyword, "!"), (gtIdentifier, "ls")]
    check kinds("cat <<1\nx\n1")[^1] == (gtKeyword, "1")

  test "quotes nest inside `${ }`":
    check kinds("x=\"${y:-\"don't\"}\"\nls")[^1] == (gtIdentifier, "ls")
    check kinds("x=${y:-\"a\"} 'b'\nls")[^1] == (gtIdentifier, "ls")
    check kinds("x=\"$(echo {)\" 'b'\nls")[^1] == (gtIdentifier, "ls")

  test "in a command substitution, the marker may end with the substitution":
    check kinds("x=$(cat <<EOF\nbody\nEOF)\necho 'a'")[^4 .. ^1] ==
      @[
        (gtKeyword, "EOF"),
        (gtPunctuation, ")"),
        (gtKeyword, "echo"),
        (gtStringLit, "'a'"),
      ]
    check kinds("echo `cat <<EOF\nit's\nEOF`\nls")[^1] == (gtIdentifier, "ls")
    check kinds("cat <<EOF\nEOF)\nEOF")[^2 .. ^1] ==
      @[(gtLongStringLit, "EOF)\n"), (gtKeyword, "EOF")]

  test "a `#` after an escaped space is part of the word":
    check kinds("echo foo\\ #bar")[^2 .. ^1] ==
      @[(gtPunctuation, "#"), (gtIdentifier, "bar")]

  test "a `#` at the start of a line after a `\\` continuation is a comment":
    check kinds("echo foo \\\n#bar")[^1] == (gtComment, "#bar")

  test "an escaped multibyte character is one token":
    check kinds("echo \\\xC3\xA9 ok")[1 .. ^1] ==
      @[(gtOperator, "\\\xC3\xA9"), (gtIdentifier, "ok")]
    check (gtEscapeSequence, "\\\xC3\xA9") in kinds("echo $'\\\xC3\xA9' x")

  test "an unbalanced brace or parenthesis ends with its substitution":
    check kinds("x=\"`echo {`\" 'b'\nls")[^1] == (gtIdentifier, "ls")
    check kinds("x=\"${y%%(*}\" 'b'\nls")[^1] == (gtIdentifier, "ls")

  test "`$$'` and `\\$[` are not ANSI-C strings or arithmetic":
    check kinds("echo $$'a\\' b")[^1] == (gtIdentifier, "b")
    check kinds("echo \\$[a<<n]\nx\nn]")[^1] == (gtKeyword, "n]")

  test "in a backquoted substitution, a backquote ends the marker":
    check kinds("x=`cat <<EOF`\necho a\nEOF\nls")[^2 .. ^1] ==
      @[(gtKeyword, "EOF"), (gtIdentifier, "ls")]

  test "a `<<` in a `${ }` expansion opens no heredoc":
    check kinds("x=\"${s//<</LT}\"\necho }")[^1] == (gtKeyword, "}")
    check kinds("x=${y//<<}\n{")[^1] == (gtKeyword, "{")
    check kinds("x=$(echo ${a:-<<})\n{")[^1] == (gtKeyword, "{")

  test "a heredoc in a command substitution inside arithmetic":
    check kinds("echo $(( $(cat <<EOF\nit's\nEOF\n) << 1 ))\nls")[^1] ==
      (gtIdentifier, "ls")
    check (gtLongStringLit, "it's\n") in kinds("x=$[ $(cat <<EOF\nit's\nEOF\n) ]\nls")
    check kinds("x=\"$(( $(cat <<EOF\nit's\nEOF\n) ))\"\nls")[^1] == (
      gtIdentifier, "ls"
    )
    check kinds("echo $(( `cat <<EOF\nit's\nEOF\n` << 1 ))\n{")[^1] == (gtKeyword, "{")

  test "arithmetic goes on after a command substitution in it closes":
    check kinds("echo $(( $(echo 1) << n ))\n{")[^1] == (gtKeyword, "{")
    check kinds("echo $(( ($(echo 1)) << n ))\n{")[^1] == (gtKeyword, "{")

  test "a shift in a `name[` subscript opens no heredoc":
    check kinds("a[i<<1]=x\necho }")[^1] == (gtKeyword, "}")
    check kinds("echo ${a[i<<1]}\necho }")[^1] == (gtKeyword, "}")
    check kinds("echo a[ cat <<EOF\n{\nEOF")[^2] == (gtLongStringLit, "{\n")

  test "an unbalanced parenthesis in a `${ }` in arithmetic ends with it":
    check kinds("(( n = ${x%(*} ))\ncat <<EOF\nit's\nEOF\necho }")[^1] ==
      (gtKeyword, "}")
    check kinds("x=$[ ${x%[*} ]\ncat <<EOF\nit's\nEOF\necho }")[^1] == (gtKeyword, "}")

  test "a heredoc state without a marker resumes as code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.state = gtLongStringLit
    g.shellNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

  test "a `case` pattern's `)` in a substitution does not close it":
    check kinds("x=\"$(case $y in a) echo \"it's\";; esac)\"\nls")[^1] ==
      (gtIdentifier, "ls")
    check kinds("x=\"$(case $y in (a|b) echo 'c';; esac)\" 'd'\nls")[^1] ==
      (gtIdentifier, "ls")

  test "`case=` is an assignment, which opens no `case`":
    check kinds("x=$(case=1; echo)\ncat <<EOF\nEOF)\nEOF")[^2 .. ^1] ==
      @[(gtLongStringLit, "EOF)\n"), (gtKeyword, "EOF")]

  test "in a process substitution, the marker may end with the substitution":
    check kinds("cat <(cat <<EOF\nhello\nEOF)\necho after")[^4 .. ^1] ==
      @[
        (gtKeyword, "EOF"),
        (gtPunctuation, ")"),
        (gtKeyword, "echo"),
        (gtIdentifier, "after"),
      ]
    check kinds("diff >(cat <<EOF\nx\nEOF) y\nls")[^1] == (gtIdentifier, "ls")

  test "a quoted command substitution in arithmetic keeps its depth":
    check kinds("echo $[ \"$(cmd)\" << 2 ]\n{")[^1] == (gtKeyword, "{")
    check kinds("(( \"$(a)\" + \"$(b)\" << 1 ))\n{")[^1] == (gtKeyword, "{")

  test "ANSI-C `\\u`, `\\U` and `\\c` escapes take their characters":
    let tokens = kinds("echo $'\\u00e9\\U0001F600\\cAz'")
    check (gtEscapeSequence, "\\u00e9") in tokens
    check (gtEscapeSequence, "\\U0001F600") in tokens
    check (gtEscapeSequence, "\\cA") in tokens
    check (gtStringLit, "z'") in tokens
    check kinds("x=\"$(if t; then case $y in\n  a) :;;\nesac; fi)\" 'd'\nls")[^1] ==
      (gtIdentifier, "ls")
    check kinds("x=\"$(echo case a)\" 'b'\nls")[^1] == (gtIdentifier, "ls")
    check kinds("x=$(case $y in a) cat <<EOF;; esac\nit's\nEOF\n)\nls")[^1] ==
      (gtIdentifier, "ls")

  test "inside `${ }`, no command starts":
    check kinds("echo \"${case}\" 'x'\nls")[^1] == (gtIdentifier, "ls")
    check kinds("echo ${!case} 'x'\nls")[^1] == (gtIdentifier, "ls")
    check kinds("x=\"${line%% #*}\"\necho 'a' ls")[^1] == (gtIdentifier, "ls")
    check kinds("v=\"$(echo ${x%)})\"; echo 'a'\nls")[^1] == (gtIdentifier, "ls")
    check kinds("v=\"${x:-{}\" 'a'\nls")[^1] == (gtIdentifier, "ls")

  test "a `case` nested after a pattern in a substitution":
    check kinds(
      "x=\"$(case $a in\n a) case $b in\n b) :;;\n esac;;\n c) :;;\nesac)\" 'd'\nls"
    )[^1] == (gtIdentifier, "ls")

  test "a `\\` line continuation joins the marker with the next line":
    check kinds("cat <<EOF\\\nX\nbody\nEOFX\necho after")[^3 .. ^1] ==
      @[(gtKeyword, "EOFX"), (gtKeyword, "echo"), (gtIdentifier, "after")]

  test "an `esac` that is an argument does not end the `case`":
    check kinds("x=\"$(case $y in a) echo esac;; b) :;; esac)\" 'ok'\nls")[^1] ==
      (gtIdentifier, "ls")

  test "an empty quoted marker ends the body at its first empty line":
    check kinds("cat <<''\nit's\n\necho x")[^4 .. ^1] ==
      @[
        (gtLongStringLit, "it's\n"),
        (gtKeyword, "\n"),
        (gtKeyword, "echo"),
        (gtIdentifier, "x"),
      ]
    check kinds("cat <<-\"\"\nit's\n\t\necho x")[^1] == (gtIdentifier, "x")

  test "a `#` right after an opening backquote is a comment":
    check kinds("x=`#note it's` 'a'\nls")[^4 .. ^1] ==
      @[
        (gtComment, "#note it's"),
        (gtNone, "`"),
        (gtStringLit, "'a'"),
        (gtIdentifier, "ls"),
      ]
    check kinds("echo `date`#x")[^1] == (gtIdentifier, "x")
