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

suite "syntax_commit_edit_msg - Conventional Commits":
  test "type only: feat: add foo":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("feat: add foo\n")

    g.commitEditMsgNextToken()
    check g.kind == gtKeyword
    check g.length == 4 # "feat"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation
    check g.length == 1 # ":"

    g.commitEditMsgNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

    g.commitEditMsgNextToken()
    check g.kind == gtNone # "add foo\n"
    check g.length == 8

    g.commitEditMsgNextToken()
    check g.kind == gtEof

  test "type with scope: fix(parser): trim":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fix(parser): trim\n")

    g.commitEditMsgNextToken()
    check g.kind == gtKeyword
    check g.length == 3 # "fix"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation
    check g.length == 1 # "("

    g.commitEditMsgNextToken()
    check g.kind == gtIdentifier
    check g.length == 6 # "parser"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation
    check g.length == 1 # ")"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation
    check g.length == 1 # ":"

    g.commitEditMsgNextToken()
    check g.kind == gtWhitespace

    g.commitEditMsgNextToken()
    check g.kind == gtNone # "trim\n"

  test "breaking change: feat!: change API":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("feat!: change API\n")

    g.commitEditMsgNextToken()
    check g.kind == gtKeyword
    check g.length == 4

    g.commitEditMsgNextToken()
    check g.kind == gtOperator
    check g.length == 1 # "!"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation
    check g.length == 1 # ":"

    g.commitEditMsgNextToken()
    check g.kind == gtWhitespace

    g.commitEditMsgNextToken()
    check g.kind == gtNone

  test "scope + breaking: refactor(api)!: rework":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("refactor(api)!: rework\n")

    g.commitEditMsgNextToken()
    check g.kind == gtKeyword
    check g.length == 8 # "refactor"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation # "("

    g.commitEditMsgNextToken()
    check g.kind == gtIdentifier
    check g.length == 3 # "api"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation # ")"

    g.commitEditMsgNextToken()
    check g.kind == gtOperator # "!"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation # ":"

    g.commitEditMsgNextToken()
    check g.kind == gtWhitespace

    g.commitEditMsgNextToken()
    check g.kind == gtNone

  test "non-Conventional subject stays as gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Merge branch 'topic'\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone
    check g.length == 21

  test "unknown type prefix is not treated as Conventional Commits":
    # "hello:" looks structurally like a Conventional Commits prefix but
    # "hello" is not in the canonical type set — the whole line falls back
    # to a plain subject line.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("hello: world\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone
    check g.length == 13

  test "body line that looks like a type prefix is not Conventional Commits":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Subject\n\nfeat: not a subject anymore\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone # subject

    g.commitEditMsgNextToken()
    check g.kind == gtNone # blank

    g.commitEditMsgNextToken()
    check g.kind == gtNone # body line, no Conventional Commits split

suite "syntax_commit_edit_msg - Trailer lines":
  test "Signed-off-by trailer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("subject\n\nSigned-off-by: Foo <foo@example.com>\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone # subject

    g.commitEditMsgNextToken()
    check g.kind == gtNone # blank

    g.commitEditMsgNextToken()
    check g.kind == gtKey
    check g.length == 13 # "Signed-off-by"

    g.commitEditMsgNextToken()
    check g.kind == gtPunctuation
    check g.length == 1 # ":"

    g.commitEditMsgNextToken()
    check g.kind == gtWhitespace

    g.commitEditMsgNextToken()
    check g.kind == gtNone # "Foo <foo@example.com>\n"

  test "Co-authored-by trailer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("subject\n\nCo-authored-by: Bar <bar@example.com>\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone

    g.commitEditMsgNextToken()
    check g.kind == gtNone

    g.commitEditMsgNextToken()
    check g.kind == gtKey
    check g.length == 14

  test "unknown key: value is not treated as trailer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("subject\n\nRandom-thing: whatever\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone

    g.commitEditMsgNextToken()
    check g.kind == gtNone

    g.commitEditMsgNextToken()
    check g.kind == gtNone # not a trailer

  test "trailer key requires whitespace after colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("subject\n\nSigned-off-by:no-space\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone

    g.commitEditMsgNextToken()
    check g.kind == gtNone

    g.commitEditMsgNextToken()
    check g.kind == gtNone # missing space after ':' — not a trailer

  test "trailer on first line is treated as subject, not trailer":
    # Trailers only apply after the subject line — so a trailer-like first
    # line is emitted as a plain gtNone subject.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("Signed-off-by: Foo\n")

    g.commitEditMsgNextToken()
    check g.kind == gtNone

suite "syntax_commit_edit_msg - Git status comment lines":
  test "section header inside comment: Changes to be committed:":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Changes to be committed:\n")

    g.commitEditMsgNextToken()
    check g.kind == gtPreprocessor

  test "'On branch <name>' comment is a status marker":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# On branch develop\n")

    g.commitEditMsgNextToken()
    check g.kind == gtPreprocessor

  test "status label 'modified:' in tab-indented comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("#\tmodified:   foo.txt\n")

    g.commitEditMsgNextToken()
    check g.kind == gtPreprocessor

  test "prose comment stays as gtComment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Please enter the commit message\n")

    g.commitEditMsgNextToken()
    check g.kind == gtComment

  test "similar-looking prefix that isn't a status marker stays as gtComment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Changes anyway\n")

    g.commitEditMsgNextToken()
    check g.kind == gtComment
