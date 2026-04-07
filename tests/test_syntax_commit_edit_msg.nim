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

import ../src/moepkg/syntax/[tokenizer, syntax_commit_edit_msg]

suite "syntax_commit_edit_msg - Comment lines":
  test "comment line with # prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# This is a comment\n")
    g.commitEditMsgNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "comment line without trailing newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.commitEditMsgNextToken()
    check g.kind == gtComment
    check g.length == 9

suite "syntax_commit_edit_msg - Commit message text":
  test "plain text line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Fix a bug\n")
    g.commitEditMsgNextToken()
    check g.kind == gtNone
    check g.length == 10

  test "empty line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n")
    g.commitEditMsgNextToken()
    check g.kind == gtNone
    check g.length == 1

suite "syntax_commit_edit_msg - EOF handling":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.commitEditMsgNextToken()
    check g.kind == gtEof
    check g.length == 0

  test "EOF after comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.commitEditMsgNextToken()
    check g.kind == gtComment
    g.commitEditMsgNextToken()
    check g.kind == gtEof

suite "syntax_commit_edit_msg - Multiple lines":
  test "message followed by comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Fix bug\n# Please enter the commit message\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone # "Fix bug\n"

    g.commitEditMsgNextToken()
    check g.kind == gtComment # "# Please enter...\n"

    g.commitEditMsgNextToken()
    check g.kind == gtEof

  test "multiple comment lines":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# line 1\n# line 2\n")

    g.commitEditMsgNextToken()
    check g.kind == gtComment

    g.commitEditMsgNextToken()
    check g.kind == gtComment

    g.commitEditMsgNextToken()
    check g.kind == gtEof

  test "typical commit message format":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Add feature\n\n# Changes:\n# - file.nim\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone # "Add feature\n"

    g.commitEditMsgNextToken()
    check g.kind == gtNone # "\n" (empty line)

    g.commitEditMsgNextToken()
    check g.kind == gtComment # "# Changes:\n"

    g.commitEditMsgNextToken()
    check g.kind == gtComment # "# - file.nim\n"

    g.commitEditMsgNextToken()
    check g.kind == gtEof
