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

import ../src/moepkg/syntax/[tokenizer, syntax_fish]

suite "syntax_fish - fishKeywords constant":
  test "fishKeywords contains control flow keywords":
    check "if" in fishKeywords
    check "else" in fishKeywords
    check "switch" in fishKeywords
    check "case" in fishKeywords
    check "for" in fishKeywords
    check "while" in fishKeywords
    check "in" in fishKeywords
    check "begin" in fishKeywords
    check "end" in fishKeywords

  test "fishKeywords contains definition keywords":
    check "function" in fishKeywords
    check "functions" in fishKeywords

  test "fishKeywords contains variable keywords":
    check "set" in fishKeywords
    check "set_color" in fishKeywords

  test "fishKeywords contains builtin commands":
    check "echo" in fishKeywords
    check "printf" in fishKeywords
    check "read" in fishKeywords
    check "cd" in fishKeywords
    check "exit" in fishKeywords
    check "return" in fishKeywords
    check "break" in fishKeywords
    check "continue" in fishKeywords
    check "test" in fishKeywords
    check "eval" in fishKeywords
    check "exec" in fishKeywords
    check "source" in fishKeywords
    check "emit" in fishKeywords
    check "contains" in fishKeywords
    check "count" in fishKeywords
    check "math" in fishKeywords
    check "string" in fishKeywords
    check "status" in fishKeywords
    check "type" in fishKeywords
    check "time" in fishKeywords
    check "history" in fishKeywords

  test "fishKeywords contains logical operators":
    check "and" in fishKeywords
    check "or" in fishKeywords
    check "not" in fishKeywords

  test "fishKeywords contains boolean values":
    check "true" in fishKeywords
    check "false" in fishKeywords

  test "fishKeywords contains other builtins":
    check "abbr" in fishKeywords
    check "alias" in fishKeywords
    check "argparse" in fishKeywords
    check "bind" in fishKeywords
    check "builtin" in fishKeywords
    check "command" in fishKeywords
    check "complete" in fishKeywords

suite "syntax_fish - fishNextToken keywords":
  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "end keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("end")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "else keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("else")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "function keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "for keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "while keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("while")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "switch keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("switch")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "case keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("case")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "begin keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("begin")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "set keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("set")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "echo keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "and keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("and")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "or keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("or")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "not keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("not")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "exit keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("exit")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "source keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("source")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "cd keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("cd")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.fishNextToken()
    check g.kind == gtKeyword
    check g.length == 5

suite "syntax_fish - fishNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myVar")
    g.fishNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.fishNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.fishNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.fishNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "uppercase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MY_VAR")
    g.fishNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "unicode identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("変数")
    g.fishNextToken()
    check g.kind == gtIdentifier

suite "syntax_fish - fishNextToken numbers (no highlight)":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 3

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("1234567890")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 10

  test "hex number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xff")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 4

  test "binary number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 6

  test "octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 4

  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 4

suite "syntax_fish - fishNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "empty single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "double quoted string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

suite "syntax_fish - fishNextToken single quote no escape":
  test "single quoted string with backslash is literal":
    # In Fish, single quotes don't support escape sequences.
    # The backslash is treated as a literal character.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'ab'")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.length == 4
    check g.state != gtStringLit

  test "single quoted string does not enter escape state":
    # Unlike double quotes, single quotes never set state to gtStringLit
    # (which would indicate an escape continuation).
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.state != gtStringLit

suite "syntax_fish - fishNextToken escape sequences":
  test "escape in double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.fishNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.fishNextToken()
    check g.kind == gtEscapeSequence

  test "numeric escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.fishNextToken()
    check g.kind == gtEscapeSequence

  test "single hex digit escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xA\"")
    g.fishNextToken()
    check g.state == gtStringLit

    g.fishNextToken()
    check g.kind == gtEscapeSequence

suite "syntax_fish - fishNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.fishNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "empty comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.fishNextToken()
    check g.kind == gtComment
    check g.length == 1

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x # comment")

    g.fishNextToken() # x
    check g.kind == gtIdentifier

    g.fishNextToken() # space
    check g.kind == gtWhitespace

    g.fishNextToken() # # comment
    check g.kind == gtComment

suite "syntax_fish - fishNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "minus is not operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "multiply operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "slash is not operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "less than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "greater than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "pipe operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "dollar sign alone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "dollar variable":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$HOME")
    g.fishNextToken()
    check g.kind == gtSpecialVar
    check g.length == 5

  test "dollar variable lowercase":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$fish_pid")
    g.fishNextToken()
    check g.kind == gtSpecialVar
    check g.length == 9

  test "dollar variable with underscore prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$_var")
    g.fishNextToken()
    check g.kind == gtSpecialVar
    check g.length == 5

  test "dollar followed by non-identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$1")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "backslash operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "exclamation operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "ampersand operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntax_fish - fishNextToken punctuation":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.fishNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.fishNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.fishNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.fishNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.fishNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.fishNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "open brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.fishNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close brace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.fishNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_fish - fishNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a b")
    g.fishNextToken() # 'a'
    g.fishNextToken() # ' '
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a    b")
    g.fishNextToken() # 'a'
    g.fishNextToken() # '    '
    check g.kind == gtWhitespace
    check g.length == 4

  test "tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\tb")
    g.fishNextToken() # 'a'
    g.fishNextToken() # '\t'
    check g.kind == gtWhitespace
    check g.length == 1

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a\nb")
    g.fishNextToken() # 'a'
    g.fishNextToken() # '\n'
    check g.kind == gtWhitespace
    check g.length == 1

  test "mixed whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a \t\n b")
    g.fishNextToken() # 'a'
    g.fishNextToken() # ' \t\n '
    check g.kind == gtWhitespace
    check g.length == 4

suite "syntax_fish - fishNextToken EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.fishNextToken()
    check g.kind == gtEof

  test "EOF after tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("x")
    g.fishNextToken() # 'x'
    g.fishNextToken() # EOF
    check g.kind == gtEof

suite "syntax_fish - fishNextToken complete code":
  test "simple if statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if test -f file; echo ok; end")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # if, test, echo, end
    check gtIdentifier in tokens # file, ok
    check gtPunctuation in tokens # ;

  test "for loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for i in 1 2 3; echo $i; end")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # for, in, echo, end
    check gtIdentifier in tokens # i
    check gtNone in tokens # 1, 2, 3
    check gtSpecialVar in tokens # $i

  test "while loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("while true; echo loop; end")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # while, true, echo, end

  test "function definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function hello; echo world; end")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # function, echo, end
    check gtIdentifier in tokens # hello, world
    check gtPunctuation in tokens # ;

  test "switch statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("switch $x; case a; echo a; end")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # switch, case, echo, end
    check gtSpecialVar in tokens # $x
    check gtIdentifier in tokens # a

  test "variable assignment with set":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("set MY_VAR \"hello world\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # set
    check gtIdentifier in tokens # MY_VAR
    check gtStringLit in tokens # "hello world"

  test "command with comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo hello # this is a comment")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
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
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtIdentifier in tokens # ls, grep, foo
    check gtOperator in tokens # |

  test "command substitution":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo (date)")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # echo
    check gtPunctuation in tokens # (, )
    check gtIdentifier in tokens # date

  test "logical operators":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("test -f file; and echo exists")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # test, and, echo

  test "redirection":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo hello > file.txt")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtKeyword in tokens # echo
    check gtIdentifier in tokens # hello, file
    check gtOperator in tokens # >

suite "syntax_fish - fishNextToken edge cases":
  test "unterminated double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"unterminated")
    g.fishNextToken()
    check g.kind == gtStringLit

  test "unterminated single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'unterminated")
    g.fishNextToken()
    check g.kind == gtStringLit

  test "string terminated by newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\nnext")
    g.fishNextToken()
    check g.kind == gtStringLit

  test "string terminated by carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\x0Dnext")
    g.fishNextToken()
    check g.kind == gtStringLit

  test "escape with null terminator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"test\\")
    g.fishNextToken()
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.fishNextToken()
    check g.kind == gtEscapeSequence
    check g.state == gtNone

  test "number with suffix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123abc")
    g.fishNextToken()
    check g.kind == gtNone
    check g.length == 4 # "123a"

    g.fishNextToken()
    check g.kind == gtIdentifier
    check g.length == 2 # "bc"

  test "operator sequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">>")
    g.fishNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntax_fish - fishNextToken string continuation":
  test "string continuation after escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.fishNextToken() # "hello
    check g.kind == gtStringLit
    check g.state == gtStringLit

    g.fishNextToken() # \n
    check g.kind == gtEscapeSequence

    g.fishNextToken() # world"
    check g.kind == gtStringLit
    check g.state == gtNone

  test "multiple escapes in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\\tc\"")

    var tokens: seq[TokenClass] = @[]
    while true:
      g.fishNextToken()
      if g.kind == gtEof:
        break
      tokens.add(g.kind)

    check gtStringLit in tokens
    check gtEscapeSequence in tokens

  test "string content before escape is stringLit not escapeSequence":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")

    g.fishNextToken() # "hello
    check g.kind == gtStringLit
    check g.length == 6

    g.fishNextToken() # \n
    check g.kind == gtEscapeSequence
    check g.length == 2

    g.fishNextToken() # world"
    check g.kind == gtStringLit
    check g.length == 6
    check g.state == gtNone

  test "consecutive escapes each split correctly":
    # "Tab:\there Newline:\nhere Backslash:\\"
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"Tab:\\there Newline:\\nhere Backslash:\\\\\"")

    g.fishNextToken() # "Tab:
    check g.kind == gtStringLit
    check g.length == 5

    g.fishNextToken() # \t
    check g.kind == gtEscapeSequence
    check g.length == 2

    g.fishNextToken() # here Newline:
    check g.kind == gtStringLit
    check g.length == 13

    g.fishNextToken() # \n
    check g.kind == gtEscapeSequence
    check g.length == 2

    g.fishNextToken() # here Backslash:
    check g.kind == gtStringLit
    check g.length == 15

    g.fishNextToken() # \\
    check g.kind == gtEscapeSequence
    check g.length == 2

    g.fishNextToken() # "
    check g.kind == gtStringLit
    check g.length == 1
    check g.state == gtNone

  test "escape at start of string continuation":
    # When \ is the very first char in continuation, no split needed
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\nabc\"")

    g.fishNextToken() # "
    check g.kind == gtStringLit
    check g.state == gtStringLit
    check g.length == 1

    g.fishNextToken() # \n
    check g.kind == gtEscapeSequence
    check g.length == 2

    g.fishNextToken() # abc"
    check g.kind == gtStringLit
    check g.length == 4
    check g.state == gtNone

  test "hex escape after string content":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"val:\\xFF\"")

    g.fishNextToken() # "val:
    check g.kind == gtStringLit
    check g.length == 5

    g.fishNextToken() # \xFF
    check g.kind == gtEscapeSequence
    check g.length == 4

    g.fishNextToken() # "
    check g.kind == gtStringLit
    check g.state == gtNone

suite "syntax_fish - fishNextToken shebang":
  test "shebang line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#!/usr/bin/fish")
    g.fishNextToken()
    check g.kind == gtPreprocessor
    check g.length == 15

  test "shebang with env":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#!/usr/bin/env fish")
    g.fishNextToken()
    check g.kind == gtPreprocessor
    check g.length == 19
