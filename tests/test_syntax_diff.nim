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

import ../src/moepkg/syntax/[tokenizer, syntax_diff]

suite "syntax_diff - Added lines":
  test "added line with + prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+added line\n")
    g.diffNextToken()
    check g.kind == gtStringLit
    check g.length == 12

  test "added line without trailing newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+added")
    g.diffNextToken()
    check g.kind == gtStringLit
    check g.length == 6

suite "syntax_diff - Deleted lines":
  test "deleted line with - prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-deleted line\n")
    g.diffNextToken()
    check g.kind == gtComment
    check g.length == 14

  test "deleted line without trailing newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("-removed")
    g.diffNextToken()
    check g.kind == gtComment
    check g.length == 8

suite "syntax_diff - Hunk headers":
  test "hunk header with @@ prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@@ -1,3 +1,4 @@\n")
    g.diffNextToken()
    check g.kind == gtPreprocessor

suite "syntax_diff - Meta lines":
  test "diff meta line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("diff --git a/file b/file\n")
    g.diffNextToken()
    check g.kind == gtKeyword

  test "index meta line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("index abc123..def456\n")
    g.diffNextToken()
    check g.kind == gtKeyword

  test "new file meta line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("new file mode 100644\n")
    g.diffNextToken()
    check g.kind == gtKeyword

  test "similarity meta line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("similarity index 100%\n")
    g.diffNextToken()
    check g.kind == gtKeyword

  test "rename meta line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("rename from old.txt\n")
    g.diffNextToken()
    check g.kind == gtKeyword

suite "syntax_diff - Context lines":
  test "context line (space prefix)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(" context line\n")
    g.diffNextToken()
    check g.kind == gtNone
    check g.length == 14

  test "context line with plain text":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("plain text\n")
    # Lines not starting with +, -, @, or meta chars are context
    g.diffNextToken()
    check g.kind == gtNone

suite "syntax_diff - EOF handling":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.diffNextToken()
    check g.kind == gtEof
    check g.length == 0

  test "EOF after token":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("+line")
    g.diffNextToken() # +line
    check g.kind == gtStringLit

    g.diffNextToken() # EOF
    check g.kind == gtEof

suite "syntax_diff - Multiple tokens":
  test "sequence of different line types":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("@@ -1,2 +1,3 @@\n-old\n+new\n context\n")

    g.diffNextToken()
    check g.kind == gtPreprocessor # @@ header

    g.diffNextToken()
    check g.kind == gtComment # -old

    g.diffNextToken()
    check g.kind == gtStringLit # +new

    g.diffNextToken()
    check g.kind == gtNone # context

    g.diffNextToken()
    check g.kind == gtEof
