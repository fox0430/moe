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

import ../src/moepkg/syntax/[tokenizer, syntax_gitignore]

suite "syntax_gitignore - Comments":
  test "comment line with # prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# This is a comment\n")
    g.gitignoreNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "comment without trailing newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.gitignoreNextToken()
    check g.kind == gtComment
    check g.length == 9

  test "# is not a comment when not at line start":
    # After parsing 'foo', '#' should be treated as part of the next pattern token
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foo#bar\n")
    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 7 # "foo#bar"

suite "syntax_gitignore - Negation":
  test "negation operator at line start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("!important.txt\n")
    g.gitignoreNextToken()
    check g.kind == gtOperator
    check g.length == 1

    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 13 # "important.txt"

  test "! mid-line is plain text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foo!bar\n")
    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 7 # "foo!bar" — '!' is not a metacharacter mid-pattern

suite "syntax_gitignore - Glob wildcards":
  test "single asterisk":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*.log\n")
    g.gitignoreNextToken()
    check g.kind == gtOperator
    check g.length == 1

    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 4 # ".log"

  test "double asterisk":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("**/foo\n")
    g.gitignoreNextToken()
    check g.kind == gtOperator
    check g.length == 2

    g.gitignoreNextToken()
    check g.kind == gtPunctuation
    check g.length == 1 # "/"

    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 3 # "foo"

  test "question mark":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("?bc\n")
    g.gitignoreNextToken()
    check g.kind == gtOperator
    check g.length == 1

    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 2 # "bc"

  test "adjacent * and ? are separate tokens":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("*?\n")
    g.gitignoreNextToken()
    check g.kind == gtOperator
    check g.length == 1 # "*"

    g.gitignoreNextToken()
    check g.kind == gtOperator
    check g.length == 1 # "?"

  test "triple asterisk splits into ** and *":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("***\n")
    g.gitignoreNextToken()
    check g.kind == gtOperator
    check g.length == 2 # "**"

    g.gitignoreNextToken()
    check g.kind == gtOperator
    check g.length == 1 # "*"

suite "syntax_gitignore - Path separator":
  test "leading slash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("/build\n")
    g.gitignoreNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 5

  test "trailing slash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("logs/\n")
    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 4

    g.gitignoreNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_gitignore - Character class":
  test "simple character class":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[abc].txt\n")
    g.gitignoreNextToken()
    check g.kind == gtRegularExpression
    check g.length == 5 # "[abc]"

    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 4 # ".txt"

  test "character class with range":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[0-9]\n")
    g.gitignoreNextToken()
    check g.kind == gtRegularExpression
    check g.length == 5

  test "unterminated character class consumes to end of line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[abc\n")
    g.gitignoreNextToken()
    check g.kind == gtRegularExpression
    check g.length == 4 # "[abc"

suite "syntax_gitignore - Escape sequence":
  test "escaped hash at line start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\#literal\n")
    g.gitignoreNextToken()
    check g.kind == gtEscapeSequence
    check g.length == 2 # "\\#"

    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 7 # "literal"

  test "escaped space":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foo\\ bar\n")
    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 3 # "foo"

    g.gitignoreNextToken()
    check g.kind == gtEscapeSequence
    check g.length == 2 # "\\ "

    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    check g.length == 3 # "bar"

suite "syntax_gitignore - EOF":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.gitignoreNextToken()
    check g.kind == gtEof
    check g.length == 0

  test "EOF after pattern":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("foo")
    g.gitignoreNextToken()
    check g.kind == gtIdentifier
    g.gitignoreNextToken()
    check g.kind == gtEof

suite "syntax_gitignore - Multi-line":
  test "comment then pattern then negation":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# build artifacts\n*.o\n!keep.o\n")

    g.gitignoreNextToken()
    check g.kind == gtComment
    g.gitignoreNextToken()
    check g.kind == gtWhitespace # "\n"

    g.gitignoreNextToken()
    check g.kind == gtOperator # "*"
    g.gitignoreNextToken()
    check g.kind == gtIdentifier # ".o"
    g.gitignoreNextToken()
    check g.kind == gtWhitespace # "\n"

    g.gitignoreNextToken()
    check g.kind == gtOperator # "!"
    g.gitignoreNextToken()
    check g.kind == gtIdentifier # "keep.o"
    g.gitignoreNextToken()
    check g.kind == gtWhitespace # "\n"

    g.gitignoreNextToken()
    check g.kind == gtEof

  test "blank line preserves line-start state":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n# comment\n")

    g.gitignoreNextToken()
    check g.kind == gtWhitespace # "\n"

    g.gitignoreNextToken()
    check g.kind == gtComment

  test "complex pattern with multiple metacharacters":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("src/**/*.tmp\n")

    g.gitignoreNextToken()
    check g.kind == gtIdentifier # "src"
    g.gitignoreNextToken()
    check g.kind == gtPunctuation # "/"
    g.gitignoreNextToken()
    check g.kind == gtOperator # "**"
    g.gitignoreNextToken()
    check g.kind == gtPunctuation # "/"
    g.gitignoreNextToken()
    check g.kind == gtOperator # "*"
    g.gitignoreNextToken()
    check g.kind == gtIdentifier # ".tmp"
    g.gitignoreNextToken()
    check g.kind == gtWhitespace # "\n"
    g.gitignoreNextToken()
    check g.kind == gtEof
