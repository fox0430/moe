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

import ../src/moepkg/syntax/[tokenizer, syntax_zsh]

suite "syntax_zsh - zshKeywords constant":
  test "zshKeywords contains control flow keywords":
    check "if" in zshKeywords
    check "then" in zshKeywords
    check "elif" in zshKeywords
    check "else" in zshKeywords
    check "fi" in zshKeywords
    check "case" in zshKeywords
    check "esac" in zshKeywords
    check "for" in zshKeywords
    check "while" in zshKeywords
    check "until" in zshKeywords
    check "do" in zshKeywords
    check "done" in zshKeywords
    check "in" in zshKeywords
    check "select" in zshKeywords

  test "zshKeywords contains definition keywords":
    check "function" in zshKeywords
    check "local" in zshKeywords
    check "declare" in zshKeywords
    check "typeset" in zshKeywords
    check "readonly" in zshKeywords
    check "export" in zshKeywords
    check "integer" in zshKeywords
    check "float" in zshKeywords

  test "zshKeywords contains builtin commands":
    check "echo" in zshKeywords
    check "print" in zshKeywords
    check "printf" in zshKeywords
    check "read" in zshKeywords
    check "cd" in zshKeywords
    check "exit" in zshKeywords
    check "return" in zshKeywords
    check "break" in zshKeywords
    check "continue" in zshKeywords
    check "test" in zshKeywords
    check "eval" in zshKeywords
    check "exec" in zshKeywords
    check "source" in zshKeywords
    check "alias" in zshKeywords
    check "unalias" in zshKeywords
    check "set" in zshKeywords
    check "unset" in zshKeywords
    check "shift" in zshKeywords
    check "history" in zshKeywords
    check "type" in zshKeywords
    check "time" in zshKeywords
    check "trap" in zshKeywords

  test "zshKeywords contains zsh-specific keywords":
    check "autoload" in zshKeywords
    check "bindkey" in zshKeywords
    check "compdef" in zshKeywords
    check "compinit" in zshKeywords
    check "emulate" in zshKeywords
    check "fpath" in zshKeywords
    check "nocorrect" in zshKeywords
    check "noglob" in zshKeywords
    check "setopt" in zshKeywords
    check "unsetopt" in zshKeywords
    check "vared" in zshKeywords
    check "whence" in zshKeywords
    check "which" in zshKeywords
    check "zcompile" in zshKeywords
    check "zle" in zshKeywords
    check "zmodload" in zshKeywords
    check "zparseopts" in zshKeywords
    check "zstyle" in zshKeywords

  test "zshKeywords contains boolean values":
    check "true" in zshKeywords
    check "false" in zshKeywords

  test "zshKeywords contains brackets and braces":
    check "[" in zshKeywords
    check "]" in zshKeywords
    check "{" in zshKeywords
    check "}" in zshKeywords

suite "syntax_zsh - zshNextToken keywords":
  test "if keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "then keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("then")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "fi keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fi")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "function keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "for keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "while keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("while")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "case keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("case")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "esac keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("esac")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "do keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("do")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 2

  test "done keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("done")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "set keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("set")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "echo keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "return keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("return")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "exit keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("exit")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "source keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("source")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "true keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("true")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "false keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("false")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 5

suite "syntax_zsh - zshNextToken zsh-specific keywords":
  test "autoload keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("autoload")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "setopt keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("setopt")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "unsetopt keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("unsetopt")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "bindkey keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("bindkey")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "zstyle keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("zstyle")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "compdef keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("compdef")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "compinit keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("compinit")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "emulate keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("emulate")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "zmodload keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("zmodload")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 8

  test "zle keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("zle")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "typeset keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("typeset")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "integer keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("integer")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "float keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("float")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 5

suite "syntax_zsh - zshNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("myvar")
    g.zshNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with underscore":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my_var")
    g.zshNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "identifier with numbers":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("var123")
    g.zshNextToken()
    check g.kind == gtIdentifier
    check g.length == 6

  test "underscore prefix identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("_private")
    g.zshNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "uppercase identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("MYCONST")
    g.zshNextToken()
    check g.kind == gtIdentifier
    check g.length == 7

suite "syntax_zsh - zshNextToken numbers":
  test "simple decimal":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("42")
    g.zshNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

  test "single digit zero":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0")
    g.zshNextToken()
    check g.length == 1

  test "large number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("123456789")
    g.zshNextToken()
    check g.kind == gtDecNumber
    check g.length == 9

  test "hex number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0xFF")
    g.zshNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "binary number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0b1010")
    g.zshNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

  test "octal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("0755")
    g.zshNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

  test "float with decimal point":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("3.14")
    g.zshNextToken()
    check g.kind == gtFloatNumber
    check g.length == 4

suite "syntax_zsh - zshNextToken string literals":
  test "double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.zshNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.zshNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "empty double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\"")
    g.zshNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "empty single quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("''")
    g.zshNextToken()
    check g.kind == gtStringLit
    check g.length == 2

  test "string with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.zshNextToken()
    check g.kind == gtStringLit
    check g.length == 13

suite "syntax_zsh - zshNextToken escape sequences":
  test "escape in double quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"a\\nb\"")
    g.zshNextToken()
    check g.kind == gtStringLit
    g.zshNextToken()
    check g.kind == gtEscapeSequence

  test "hex escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\xFF\"")
    g.zshNextToken()
    check g.kind == gtStringLit
    g.zshNextToken()
    check g.kind == gtEscapeSequence

  test "numeric escape in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"\\123\"")
    g.zshNextToken()
    check g.kind == gtStringLit
    g.zshNextToken()
    check g.kind == gtEscapeSequence

suite "syntax_zsh - zshNextToken comments":
  test "line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.zshNextToken()
    check g.kind == gtComment

  test "empty comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    g.zshNextToken()
    check g.kind == gtComment

  test "comment after code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("set # set var")
    g.zshNextToken()
    check g.kind == gtKeyword
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtComment

suite "syntax_zsh - zshNextToken operators":
  test "plus operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+")
    g.zshNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "equals operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.zshNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "less than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("<")
    g.zshNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "greater than operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(">")
    g.zshNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "pipe operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("|")
    g.zshNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "dollar sign operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$")
    g.zshNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "ampersand operator":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("&")
    g.zshNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntax_zsh - zshNextToken brackets and braces":
  test "open bracket as keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 1

  test "close bracket as keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("]")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 1

  test "open brace as keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 1

  test "close brace as keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("}")
    g.zshNextToken()
    check g.kind == gtKeyword
    check g.length == 1

  test "open paren as punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.zshNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren as punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.zshNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "semicolon as punctuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";")
    g.zshNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_zsh - zshNextToken whitespace":
  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" ")
    g.zshNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   ")
    g.zshNextToken()
    check g.kind == gtWhitespace
    check g.length == 3

  test "tab whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\t")
    g.zshNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

suite "syntax_zsh - complex code":
  test "if then fi block":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("if [ -f /etc/zshrc ]; then source /etc/zshrc; fi")
    g.zshNextToken()
    check g.kind == gtKeyword # if
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtKeyword # [

  test "for loop":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("for f in *.zsh; do source $f; done")
    g.zshNextToken()
    check g.kind == gtKeyword # for
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtIdentifier # f
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtKeyword # in

  test "function definition":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("function greet { echo hello }")
    g.zshNextToken()
    check g.kind == gtKeyword # function
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtIdentifier # greet
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtKeyword # {

  test "autoload statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("autoload -Uz compinit")
    g.zshNextToken()
    check g.kind == gtKeyword # autoload
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtOperator # -
    g.zshNextToken()
    check g.kind == gtIdentifier # Uz
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtKeyword # compinit

  test "setopt statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("setopt AUTO_CD")
    g.zshNextToken()
    check g.kind == gtKeyword # setopt
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtIdentifier # AUTO_CD

  test "zstyle statement":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("zstyle ':completion:*' menu select")
    g.zshNextToken()
    check g.kind == gtKeyword # zstyle
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtStringLit # ':completion:*'

  test "case esac block":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("case $1 in start) echo go;; esac")
    g.zshNextToken()
    check g.kind == gtKeyword # case
    g.zshNextToken()
    check g.kind == gtWhitespace
    g.zshNextToken()
    check g.kind == gtOperator # $
    g.zshNextToken()
    check g.kind == gtDecNumber # 1
