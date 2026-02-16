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
import ../src/moepkg/syntax/lexer/end_lexer

suite "end_lexer - endLine basic tests":
  test "empty string (null terminator)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    let endPos = g.endLine(0)
    check endPos == 0

  test "single character":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("a")
    let endPos = g.endLine(0)
    check endPos == 1

  test "simple text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello world")
    let endPos = g.endLine(0)
    check endPos == 11

  test "text ending with newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello\n")
    let endPos = g.endLine(0)
    check endPos == 5

  test "text ending with carriage return":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello\r")
    let endPos = g.endLine(0)
    check endPos == 5

  test "multiple lines - first line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("first\nsecond\nthird")
    let endPos = g.endLine(0)
    check endPos == 5

  test "multiple lines - second line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("first\nsecond\nthird")
    let endPos = g.endLine(6)
    check endPos == 12

  test "multiple lines - third line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("first\nsecond\nthird")
    let endPos = g.endLine(13)
    check endPos == 18

suite "end_lexer - endLine with different line endings":
  test "CRLF line ending":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello\r\nworld")
    let endPos = g.endLine(0)
    # Stops at \r
    check endPos == 5

  test "LF only":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello\nworld")
    let endPos = g.endLine(0)
    check endPos == 5

  test "CR only":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello\rworld")
    let endPos = g.endLine(0)
    check endPos == 5

suite "end_lexer - endLine with special characters":
  test "line with tabs":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\t\ttabbed\n")
    let endPos = g.endLine(0)
    check endPos == 8

  test "line with spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   spaced   \n")
    let endPos = g.endLine(0)
    check endPos == 12

  test "unicode characters":
    var g: GeneralTokenizer
    let s = "日本語テスト\n"
    g.initGeneralTokenizer(s)
    let endPos = g.endLine(0)
    check endPos == s.len - 1 # excluding \n

suite "end_lexer - endLine starting from non-zero position":
  test "start from middle of line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello world\n")
    let endPos = g.endLine(6)
    check endPos == 11

  test "start from end of line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello\nworld")
    let endPos = g.endLine(5)
    # Already at \n, returns immediately
    check endPos == 5

  test "start after newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello\nworld")
    let endPos = g.endLine(6)
    check endPos == 11

suite "end_lexer - endLWS basic tests":
  test "empty string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    let endPos = g.endLWS(0)
    check endPos == 0

  test "no whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello")
    let endPos = g.endLWS(0)
    check endPos == 0

  test "single space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" ")
    let endPos = g.endLWS(0)
    check endPos == 1

  test "single tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\t")
    let endPos = g.endLWS(0)
    check endPos == 1

  test "multiple spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("    ")
    let endPos = g.endLWS(0)
    check endPos == 4

  test "multiple tabs":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\t\t\t")
    let endPos = g.endLWS(0)
    check endPos == 3

  test "mixed spaces and tabs":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \t \t ")
    let endPos = g.endLWS(0)
    check endPos == 5

suite "end_lexer - endLWS with text":
  test "whitespace before text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("  hello")
    let endPos = g.endLWS(0)
    check endPos == 2

  test "whitespace after text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello  ")
    let endPos = g.endLWS(0)
    check endPos == 0

  test "whitespace in middle":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello  world")
    let endPos = g.endLWS(5)
    check endPos == 7

  test "tab before text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\thello")
    let endPos = g.endLWS(0)
    check endPos == 1

  test "indentation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("    code")
    let endPos = g.endLWS(0)
    check endPos == 4

suite "end_lexer - endLWS does not include other whitespace":
  test "newline is not LWS":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \n ")
    let endPos = g.endLWS(0)
    # Stops at \n
    check endPos == 1

  test "carriage return is not LWS":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \r ")
    let endPos = g.endLWS(0)
    # Stops at \r
    check endPos == 1

  test "vertical tab is not LWS":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \v ")
    let endPos = g.endLWS(0)
    # Stops at \v (vertical tab)
    check endPos == 1

  test "form feed is not LWS":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \f ")
    let endPos = g.endLWS(0)
    # Stops at \f (form feed)
    check endPos == 1

suite "end_lexer - endLWS starting from non-zero position":
  test "start from beginning of whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc   def")
    let endPos = g.endLWS(3)
    check endPos == 6

  test "start from middle of whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc   def")
    let endPos = g.endLWS(4)
    check endPos == 6

  test "start from end of whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc   def")
    let endPos = g.endLWS(6)
    check endPos == 6

  test "start from non-whitespace":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("abc   def")
    let endPos = g.endLWS(7)
    check endPos == 7

suite "end_lexer - endLWS edge cases":
  test "only whitespace then newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   \n")
    let endPos = g.endLWS(0)
    check endPos == 3

  test "whitespace between newlines":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n   \n")
    let endPos = g.endLWS(1)
    check endPos == 4

  test "alternating space and tab":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" \t \t \t")
    let endPos = g.endLWS(0)
    check endPos == 6
