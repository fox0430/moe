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

import ../src/moepkg/syntax/[tokenizer, syntaxlisp]

suite "syntaxlisp - lispKeywords constant":
  test "lispKeywords contains special operators":
    check "if" in lispKeywords
    check "let" in lispKeywords
    check "let*" in lispKeywords
    check "cond" in lispKeywords
    check "progn" in lispKeywords
    check "block" in lispKeywords
    check "tagbody" in lispKeywords

  test "lispKeywords contains definition forms":
    check "defun" in lispKeywords
    check "defvar" in lispKeywords
    check "defmacro" in lispKeywords
    check "defclass" in lispKeywords
    check "defstruct" in lispKeywords
    check "defmethod" in lispKeywords
    check "defpackage" in lispKeywords
    check "defparameter" in lispKeywords
    check "defconstant" in lispKeywords

  test "lispKeywords contains control flow":
    check "when" in lispKeywords
    check "unless" in lispKeywords
    check "case" in lispKeywords
    check "ecase" in lispKeywords
    check "typecase" in lispKeywords
    check "etypecase" in lispKeywords
    check "loop" in lispKeywords
    check "do" in lispKeywords
    check "do*" in lispKeywords
    check "dolist" in lispKeywords
    check "dotimes" in lispKeywords

  test "lispKeywords contains boolean and special values":
    check "t" in lispKeywords
    check "nil" in lispKeywords

  test "lispKeywords contains condition handling":
    check "handler-bind" in lispKeywords
    check "handler-case" in lispKeywords
    check "restart-case" in lispKeywords
    check "error" in lispKeywords
    check "catch" in lispKeywords
    check "throw" in lispKeywords
    check "unwind-protect" in lispKeywords

suite "syntaxlisp - lispNextToken keywords":
  test "defun keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("defun")
    g.lispNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "lambda keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("lambda")
    g.lispNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "let* keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("let*")
    g.lispNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "handler-case keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("handler-case")
    g.lispNextToken()
    check g.kind == gtKeyword
    check g.length == 12

  test "with-open-file keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("with-open-file")
    g.lispNextToken()
    check g.kind == gtKeyword
    check g.length == 14

  test "define-method-combination keyword":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("define-method-combination")
    g.lispNextToken()
    check g.kind == gtKeyword
    check g.length == 25

suite "syntaxlisp - lispNextToken identifiers":
  test "simple identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("my-function")
    g.lispNextToken()
    check g.kind == gtIdentifier
    check g.length == 11

  test "identifier with special chars":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*global-var*")
    g.lispNextToken()
    check g.kind == gtIdentifier
    check g.length == 12

  test "predicate identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("null?")
    g.lispNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "identifier with plus":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+some-constant+")
    g.lispNextToken()
    check g.kind == gtIdentifier
    check g.length == 15

suite "syntaxlisp - lispNextToken numbers":
  test "decimal number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("42")
    g.lispNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

  test "negative number":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-7")
    g.lispNextToken()
    check g.kind == gtDecNumber
    check g.length == 2 # - is consumed then generalNumber parses the digit

  test "hex number #x":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#xFF")
    g.lispNextToken()
    check g.kind == gtHexNumber
    check g.length == 4

  test "octal number #o":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#o77")
    g.lispNextToken()
    check g.kind == gtOctNumber
    check g.length == 4

  test "binary number #b":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#b1010")
    g.lispNextToken()
    check g.kind == gtBinNumber
    check g.length == 6

suite "syntaxlisp - lispNextToken strings":
  test "simple string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\"")
    g.lispNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "string with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.lispNextToken()
    # First token is string up to the backslash
    check g.kind == gtStringLit
    check g.length == 6 # "hello\  (quote + hello + backslash)
    # State should indicate continuation
    check g.state == gtStringLit

  test "escape sequence in string continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    # First call: string up to escape
    g.lispNextToken()
    check g.kind == gtStringLit
    # Second call: escape sequence
    g.lispNextToken()
    check g.kind == gtEscapeSequence

suite "syntaxlisp - lispNextToken line comments":
  test "line comment with semicolon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("; this is a comment")
    g.lispNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "multiple semicolons":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(";;; section comment")
    g.lispNextToken()
    check g.kind == gtComment
    check g.length == 19

suite "syntaxlisp - lispNextToken block comments":
  test "simple block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#| comment |#")
    g.lispNextToken()
    check g.kind == gtLongComment
    check g.length == 13
    check g.state == gtNone # Comment fully closed

  test "nested block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#| outer #| inner |# still outer |#")
    g.lispNextToken()
    check g.kind == gtLongComment
    check g.length == 35
    check g.state == gtNone

  test "unterminated block comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#| unterminated")
    g.lispNextToken()
    check g.kind == gtLongComment
    check g.state == gtLongComment # Still in comment state

  test "block comment continuation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#| start")
    g.lispNextToken()
    check g.kind == gtLongComment
    check g.state == gtLongComment
    # Simulate next line
    g.buf = "continued |#"
    g.pos = 0
    g.lispNextToken()
    check g.kind == gtLongComment
    check g.state == gtNone # Now closed

suite "syntaxlisp - lispNextToken parentheses":
  test "open paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(")
    g.lispNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "close paren":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(")")
    g.lispNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntaxlisp - lispNextToken quote operators":
  test "quote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'x")
    g.lispNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "backquote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("`x")
    g.lispNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "unquote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",x")
    g.lispNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "splice unquote":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",@x")
    g.lispNextToken()
    check g.kind == gtOperator
    check g.length == 2

  test "function quote #'":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#'car")
    g.lispNextToken()
    check g.kind == gtOperator
    check g.length == 2

suite "syntaxlisp - lispNextToken character literals":
  test "character literal #\\a":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#\\a")
    g.lispNextToken()
    check g.kind == gtCharLit
    check g.length == 3

  test "character literal #\\space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#\\space")
    g.lispNextToken()
    check g.kind == gtCharLit
    check g.length == 7

  test "character literal #\\newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#\\newline")
    g.lispNextToken()
    check g.kind == gtCharLit
    check g.length == 9

suite "syntaxlisp - lispNextToken vector literal":
  test "vector #(":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#(1 2 3)")
    g.lispNextToken()
    check g.kind == gtPunctuation
    check g.length == 2 # #(

suite "syntaxlisp - lispNextToken whitespace":
  test "spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   ")
    g.lispNextToken()
    check g.kind == gtWhitespace
    check g.length == 3

  test "newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n  ")
    g.lispNextToken()
    check g.kind == gtWhitespace
    check g.length == 3

suite "syntaxlisp - lispNextToken EOF":
  test "empty input":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.lispNextToken()
    check g.kind == gtEof

suite "syntaxlisp - lispNextToken complete code":
  test "defun form":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(defun add (x y) (+ x y))")

    # (
    g.lispNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

    # defun
    g.lispNextToken()
    check g.kind == gtKeyword
    check g.length == 5

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # add
    g.lispNextToken()
    check g.kind == gtIdentifier
    check g.length == 3

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # (
    g.lispNextToken()
    check g.kind == gtPunctuation

    # x
    g.lispNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # y
    g.lispNextToken()
    check g.kind == gtIdentifier
    check g.length == 1

    # )
    g.lispNextToken()
    check g.kind == gtPunctuation

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # (
    g.lispNextToken()
    check g.kind == gtPunctuation

    # +
    g.lispNextToken()
    check g.kind == gtIdentifier # + is a symbol in Lisp

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # x
    g.lispNextToken()
    check g.kind == gtIdentifier

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # y
    g.lispNextToken()
    check g.kind == gtIdentifier

    # )
    g.lispNextToken()
    check g.kind == gtPunctuation

    # )
    g.lispNextToken()
    check g.kind == gtPunctuation

    # EOF
    g.lispNextToken()
    check g.kind == gtEof

  test "let binding with string and comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("(let ((x 42)) ; bind x\n  x)")

    # (
    g.lispNextToken()
    check g.kind == gtPunctuation

    # let
    g.lispNextToken()
    check g.kind == gtKeyword
    check g.length == 3

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # (
    g.lispNextToken()
    check g.kind == gtPunctuation

    # (
    g.lispNextToken()
    check g.kind == gtPunctuation

    # x
    g.lispNextToken()
    check g.kind == gtIdentifier

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # 42
    g.lispNextToken()
    check g.kind == gtDecNumber
    check g.length == 2

    # ))
    g.lispNextToken()
    check g.kind == gtPunctuation
    g.lispNextToken()
    check g.kind == gtPunctuation

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # ; bind x\n
    g.lispNextToken()
    check g.kind == gtComment

  test "quoted list":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'(1 2 3)")

    # '
    g.lispNextToken()
    check g.kind == gtOperator
    check g.length == 1

    # (
    g.lispNextToken()
    check g.kind == gtPunctuation

    # 1
    g.lispNextToken()
    check g.kind == gtDecNumber

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # 2
    g.lispNextToken()
    check g.kind == gtDecNumber

    # space
    g.lispNextToken()
    check g.kind == gtWhitespace

    # 3
    g.lispNextToken()
    check g.kind == gtDecNumber

    # )
    g.lispNextToken()
    check g.kind == gtPunctuation

    # EOF
    g.lispNextToken()
    check g.kind == gtEof
