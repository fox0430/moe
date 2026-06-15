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

import ../src/moepkg/syntax/[tokenizer, flags]
import ../src/moepkg/syntax/lexer/hash_lexer

suite "hash_lexer - lexHashLineComment basic hash comments":
  test "simple hash comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 9

  test "empty hash comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 1

  test "hash comment ends at newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment\nnext line")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 9

  test "hash comment ends at carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment\rnext line")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 9

  test "hash comment ends at null":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 9

suite "hash_lexer - lexHashLineComment with hasDoubleHashComments flag":
  test "double hash comment (Nim style doc comment)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("## doc comment")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 14

  test "double hash comment ends at newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("## doc\nnext")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 6

  test "double hash without flag treated as line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("## comment")
    let endPos = g.lexHashLineComment(0, flagsShell)
    check endPos == 10

suite "hash_lexer - lexHashLineComment with hasHashBracketComments flag":
  test "hash bracket comment (Nim multiline)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ multiline ]#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 15
    check g.kind == gtLongComment

  test "hash bracket comment with content":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ this is a\nmultiline\ncomment ]#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 33
    check g.kind == gtLongComment

  test "hash bracket comment unterminated":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ unterminated")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 15
    check g.kind == gtLongComment

  test "hash bracket without flag treated as line comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ bracket ]#")
    let endPos = g.lexHashLineComment(0, flagsShell)
    check endPos == 13
    # g.kind is not set for line comments

suite "hash_lexer - lexHashLineComment nested hash bracket comments":
  test "nested hash bracket comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ outer #[ inner ]# outer ]#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 29
    check g.kind == gtLongComment

  test "deeply nested hash bracket comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ a #[ b #[ c ]# b ]# a ]#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 27
    check g.kind == gtLongComment

  test "nested without hasNestedComments flag":
    # Without hasNestedComments, inner ]# closes the comment
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ outer #[ inner ]# outer ]#")
    let flags: TokenizerFlags = {hasHashBracketComments, hasHashComments}
    let endPos = g.lexHashLineComment(0, flags)
    # Should stop at first ]#
    check endPos == 20
    check g.kind == gtLongComment

suite "hash_lexer - lexHashLineComment double hash bracket comments":
  test "double hash bracket comment (Nim doc block)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##[ doc block ]##")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 17
    # double hash bracket doesn't set g.kind

  test "double hash bracket comment multiline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##[ doc\nblock ]##")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 17

  test "double hash bracket comment nested":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##[ outer ##[ inner ]## outer ]##")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 33

  test "double hash bracket unterminated":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##[ unterminated")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 16

  test "double hash bracket without flag":
    # Without hasDoubleHashBracketComments, treated as double hash line comment
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##[ bracket ]##")
    let flags: TokenizerFlags = {hasDoubleHashComments, hasHashComments}
    let endPos = g.lexHashLineComment(0, flags)
    check endPos == 15

suite "hash_lexer - lexHashLineComment shebang":
  test "shebang line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#!/usr/bin/env python")
    let endPos = g.lexHashLineComment(0, flagsPython)
    check endPos == 21
    check g.kind == gtPreprocessor

  test "shebang line with Shell flags":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#!/bin/bash")
    let endPos = g.lexHashLineComment(0, flagsShell)
    check endPos == 11
    check g.kind == gtPreprocessor

  test "shebang without flag treated as comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#!/usr/bin/env")
    let flags: TokenizerFlags = {hasHashComments}
    let endPos = g.lexHashLineComment(0, flags)
    check endPos == 14
    # g.kind is not set for line comments without shebang flag

  test "hash exclamation not shebang without flag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#!not a shebang")
    let flags: TokenizerFlags = {hasHashComments}
    let endPos = g.lexHashLineComment(0, flags)
    check endPos == 15

suite "hash_lexer - lexHashLineComment edge cases":
  test "hash followed by nothing":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 1

  test "hash followed by space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# ")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 2

  test "hash bracket with only opening":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 2
    check g.kind == gtLongComment

  test "double hash followed by nothing":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 2

  test "double hash bracket with only opening":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##[")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 3

  test "hash bracket with partial closing":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ test ]")
    let endPos = g.lexHashLineComment(0, flagsNim)
    # ] without # doesn't close
    check endPos == 9
    check g.kind == gtLongComment

  test "hash bracket with extra hash in closing":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ test ]##")
    let endPos = g.lexHashLineComment(0, flagsNim)
    # ]# closes, then extra # remains
    check endPos == 10
    check g.kind == gtLongComment

suite "hash_lexer - lexHashLineComment position parameter":
  test "start from non-zero position":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc# comment")
    let endPos = g.lexHashLineComment(3, flagsNim)
    check endPos == 12

  test "hash bracket from non-zero position":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc#[ block ]#xyz")
    let endPos = g.lexHashLineComment(3, flagsNim)
    check endPos == 14
    check g.kind == gtLongComment

suite "hash_lexer - lexHashLineComment special characters":
  test "hash comment with unicode":
    var g: GeneralTokenizer
    let s = "# コメント"
    g.initGeneralTokenizer(s)
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == s.len

  test "hash bracket with unicode":
    var g: GeneralTokenizer
    let s = "#[ 日本語 ]#"
    g.initGeneralTokenizer(s)
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == s.len
    check g.kind == gtLongComment

  test "hash comment with tabs":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#\ttab\tcomment")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 13

suite "hash_lexer - lexHashLineComment YAML flags":
  test "YAML hash comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# yaml comment")
    let endPos = g.lexHashLineComment(0, flagsYaml)
    check endPos == 14

  test "YAML does not have bracket comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ not a block ]#")
    let endPos = g.lexHashLineComment(0, flagsYaml)
    # Treated as line comment
    check endPos == 17

suite "hash_lexer - lexHashLineComment TOML flags":
  test "TOML hash comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# toml comment")
    let endPos = g.lexHashLineComment(0, flagsToml)
    check endPos == 14

  test "TOML double hash is just comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("## comment")
    let endPos = g.lexHashLineComment(0, flagsToml)
    check endPos == 10

suite "hash_lexer - lexHashLineComment complex nested cases":
  test "multiple consecutive nested brackets":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ a #[ b ]# #[ c ]# a ]#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 25
    check g.kind == gtLongComment

  test "hash inside bracket comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ # inner hash ]#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 18
    check g.kind == gtLongComment

  test "double hash inside bracket comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ ## inner ]#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 14
    check g.kind == gtLongComment

  test "bracket inside double hash bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("##[ #[ inner ]# outer ]##")
    let endPos = g.lexHashLineComment(0, flagsNim)
    check endPos == 25

  test "incomplete nested bracket":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#[ outer #[ inner ]#")
    let endPos = g.lexHashLineComment(0, flagsNim)
    # outer bracket never closed
    check endPos == 20
    check g.kind == gtLongComment
