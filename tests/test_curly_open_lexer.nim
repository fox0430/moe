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
import ../src/moepkg/syntax/flags
import ../src/moepkg/syntax/lexer/curly_open_lexer

suite "curly_open_lexer - lexCurlyDashComment basic tests":
  test "simple curly dash comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- comment -}")
    # Start after '{'
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 13

  test "empty curly dash comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{--}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 4

  test "curly dash comment with text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- This is a Haskell comment -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 31

  test "multiline curly dash comment":
    var g: GeneralTokenizer
    let s = "{- line1\nline2\nline3 -}"
    g.initGeneralTokenizer(s)
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == s.len

  test "curly dash comment followed by code":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- comment -} code")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 13

suite "curly_open_lexer - lexCurlyDashComment nested comments":
  test "single level nested comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- outer {- inner -} outer -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 29

  test "double nested comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- a {- b {- c -} b -} a -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 27

  test "adjacent nested comments":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- {- a -} {- b -} -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 21

  test "nested comment without nesting flag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- outer {- inner -} outer -}")
    # Without hasNestedComments flag, stops at first -}
    let flags: TokenizerFlags = {hasCurlyDashComments}
    let endPos = g.lexCurlyDashComment(1, flags)
    # Stops at first "-}" which is at position 18
    check endPos == 20

suite "curly_open_lexer - lexCurlyDashComment preprocessor":
  test "simple preprocessor directive":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-# LANGUAGE GADTs #-}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 22
    check g.kind == gtPreprocessor

  test "preprocessor OPTIONS_GHC":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-# OPTIONS_GHC -Wall #-}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 25
    check g.kind == gtPreprocessor

  test "preprocessor INLINE":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-# INLINE foo #-}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 18
    check g.kind == gtPreprocessor

  test "preprocessor without hasPreprocessor flag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-# LANGUAGE GADTs #-}")
    let flags: TokenizerFlags = {hasCurlyDashComments, hasNestedComments}
    let endPos = g.lexCurlyDashComment(1, flags)
    # Treated as regular comment, # is just content
    # Ends at first -}
    check endPos == 22
    check g.kind != gtPreprocessor

  test "nested preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-# outer {-# inner #-} outer #-}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 33
    check g.kind == gtPreprocessor

suite "curly_open_lexer - lexCurlyDashComment pipe comments":
  test "simple pipe comment (doc comment)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-| Documentation -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 20
    check g.kind == gtStringLit

  test "multiline pipe comment":
    var g: GeneralTokenizer
    let s = "{-| This is\nmultiline\ndocumentation -}"
    g.initGeneralTokenizer(s)
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == s.len
    check g.kind == gtStringLit

  test "pipe comment without hasCurlyDashPipeComments flag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-| Documentation -}")
    let flags: TokenizerFlags = {hasCurlyDashComments, hasNestedComments}
    let endPos = g.lexCurlyDashComment(1, flags)
    check endPos == 20
    # Without flag, kind is not set to gtStringLit
    check g.kind != gtStringLit

suite "curly_open_lexer - lexCurlyDashComment unterminated":
  test "unterminated comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- unterminated")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 15

  test "unterminated nested comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- outer {- inner")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 17

  test "unterminated preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-# LANGUAGE")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 12
    check g.kind == gtPreprocessor

  test "partial closing - only dash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- comment -")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 12

  test "partial closing - only curly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- comment }")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 12

suite "curly_open_lexer - lexCurlyDashComment edge cases":
  test "dash inside comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- a-b-c -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 11

  test "curly brace inside comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- a{b}c -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 11

  test "multiple dashes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- --- -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 9

  test "closing sequence in string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- contains -} inside -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    # Stops at first -}
    check endPos == 14

  test "opening sequence in comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- contains {- but not nested -}")
    let flags: TokenizerFlags = {hasCurlyDashComments} # No nesting
    let endPos = g.lexCurlyDashComment(1, flags)
    # Without nesting, stops at first -}
    check endPos == 32

  test "empty buffer after opening":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 2

  test "just dash after opening curly":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 2

suite "curly_open_lexer - lexCurlyDashComment position not at dash":
  test "position not at dash returns immediately":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{x comment -}")
    # Position 1 is 'x', not '-'
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    # Returns immediately since buf[1] != '-'
    check endPos == 1

  test "position at space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{ - comment -}")
    # Position 1 is ' ', not '-'
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 1

suite "curly_open_lexer - lexCurlyDashComment unicode":
  test "unicode in comment":
    var g: GeneralTokenizer
    let s = "{- 日本語コメント -}"
    g.initGeneralTokenizer(s)
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == s.len

  test "unicode in doc comment":
    var g: GeneralTokenizer
    let s = "{-| ドキュメント -}"
    g.initGeneralTokenizer(s)
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == s.len
    check g.kind == gtStringLit

  test "unicode in preprocessor":
    var g: GeneralTokenizer
    let s = "{-# LANGUAGE 日本語 #-}"
    g.initGeneralTokenizer(s)
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == s.len
    check g.kind == gtPreprocessor

suite "curly_open_lexer - lexCurlyDashComment with flagsHaskell":
  test "all Haskell flags together - comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- normal comment -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 20

  test "all Haskell flags together - nested":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{- {- nested -} -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 18

  test "all Haskell flags together - preprocessor":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-# PRAGMA #-}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 14
    check g.kind == gtPreprocessor

  test "all Haskell flags together - doc comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("{-| doc -}")
    let endPos = g.lexCurlyDashComment(1, flagsHaskell)
    check endPos == 10
    check g.kind == gtStringLit
