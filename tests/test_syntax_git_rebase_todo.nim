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

import ../src/moepkg/syntax/[tokenizer, syntax_git_rebase_todo]

suite "syntax_git_rebase_todo - Comment lines":
  test "comment line with # prefix":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# This is a comment\n")
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "comment line without trailing newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment
    check g.length == 9

suite "syntax_git_rebase_todo - Command lines":
  test "pick command with hash and message":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("pick abc1234 Fix bug\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 4 # "pick"

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

    g.gitRebaseTodoNextToken()
    check g.kind == gtDecNumber
    check g.length == 7 # "abc1234"

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace
    check g.length == 1

    g.gitRebaseTodoNextToken()
    check g.kind == gtNone # "Fix bug\n"

    g.gitRebaseTodoNextToken()
    check g.kind == gtEof

  test "short command p":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("p abc1234 msg\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 1

  test "reword command":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("reword def5678 Update message\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword

  test "short commands r, s, f, e, d":
    for cmd in ["r", "s", "f", "e", "d"]:
      var g: GeneralTokenizer
      g.initGeneralTokenizer(cmd & " abc1234 msg\n")
      g.gitRebaseTodoNextToken()
      check g.kind == gtKeyword
      check g.length == 1

  test "squash command":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("squash aaa1111 Some commit\n")
    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "fixup command":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("fixup bbb2222 Another commit\n")
    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "edit command":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("edit ccc3333 Edit this\n")
    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "drop command":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("drop ddd4444 Drop this\n")
    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 4

suite "syntax_git_rebase_todo - Special commands":
  test "exec command (no hash)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("exec make test\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 4 # "exec"

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    # "make" starts with 'm' which is not hex-only, but contains non-hex chars
    # so it goes to rest-of-line as gtNone
    g.gitRebaseTodoNextToken()
    check g.kind == gtNone

  test "break command (standalone)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("break\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "label command":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("label my-label\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 5

  test "update-ref command":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("update-ref refs/heads/main\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 10

suite "syntax_git_rebase_todo - EOF handling":
  test "empty string returns EOF":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("")
    g.gitRebaseTodoNextToken()
    check g.kind == gtEof
    check g.length == 0

  test "EOF after token":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# comment")
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment
    g.gitRebaseTodoNextToken()
    check g.kind == gtEof

suite "syntax_git_rebase_todo - Empty and unknown lines":
  test "empty line":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n")
    g.gitRebaseTodoNextToken()
    check g.kind == gtNone
    check g.length == 1

  test "unknown command treated as gtNone":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("unknown abc123\n")
    g.gitRebaseTodoNextToken()
    check g.kind == gtNone

suite "syntax_git_rebase_todo - Commit message starting with #":
  test "hash in commit message is not treated as comment":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("pick abc123 #42 fix\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword # pick

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    g.gitRebaseTodoNextToken()
    check g.kind == gtDecNumber # abc123

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    g.gitRebaseTodoNextToken()
    check g.kind == gtNone # "#42 fix\n" — not a comment

    g.gitRebaseTodoNextToken()
    check g.kind == gtEof

suite "syntax_git_rebase_todo - Multiple lines":
  test "sequence of different line types":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("pick abc1234 Fix\n# comment\nbreak\n")

    # pick
    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword

    # space
    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    # hash
    g.gitRebaseTodoNextToken()
    check g.kind == gtDecNumber

    # space
    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    # "Fix\n"
    g.gitRebaseTodoNextToken()
    check g.kind == gtNone

    # "# comment\n"
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment

    # "break"
    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword

    # "\n" after break
    g.gitRebaseTodoNextToken()
    check g.kind == gtNone

    g.gitRebaseTodoNextToken()
    check g.kind == gtEof

suite "syntax_git_rebase_todo - Identifier-arg commands":
  test "label <name> emits identifier, not hash":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("label my-label\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 5 # "label"

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    g.gitRebaseTodoNextToken()
    check g.kind == gtIdentifier
    check g.length == 8 # "my-label"

    g.gitRebaseTodoNextToken()
    check g.kind == gtNone # "\n"

  test "reset <label> emits identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("reset onto\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 5

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    g.gitRebaseTodoNextToken()
    check g.kind == gtIdentifier
    check g.length == 4 # "onto"

  test "update-ref <ref> emits identifier including slashes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("update-ref refs/heads/main\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 10 # "update-ref"

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    g.gitRebaseTodoNextToken()
    check g.kind == gtIdentifier
    check g.length == 15 # "refs/heads/main"

  test "merge <label> emits identifier":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("merge feature\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 5 # "merge"

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    g.gitRebaseTodoNextToken()
    check g.kind == gtIdentifier
    check g.length == 7 # "feature"

  test "short-form 'l' (label) also uses identifier arg":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("l my-label\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword
    check g.length == 1

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    g.gitRebaseTodoNextToken()
    check g.kind == gtIdentifier
    check g.length == 8

  test "hash-arg commands still emit gtDecNumber (regression check)":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("pick abc1234 msg\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtKeyword

    g.gitRebaseTodoNextToken()
    check g.kind == gtWhitespace

    g.gitRebaseTodoNextToken()
    check g.kind == gtDecNumber
    check g.length == 7 # "abc1234"

suite "syntax_git_rebase_todo - Sha in comments":
  test "abbreviated hash inside comment is highlighted":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Rebase abc1234 onto def5678\n")

    # `#`
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment
    check g.length == 1

    # ` Rebase `
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment

    # `abc1234`
    g.gitRebaseTodoNextToken()
    check g.kind == gtDecNumber
    check g.length == 7

    # ` onto `
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment

    # `def5678`
    g.gitRebaseTodoNextToken()
    check g.kind == gtDecNumber
    check g.length == 7

    # `\n`
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment

    g.gitRebaseTodoNextToken()
    check g.kind == gtEof

  test "short hex-only word (< 7 chars) is not treated as a hash":
    # "abed" is 4 hex-only chars but too short to be a hash.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# the abed cat\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtComment
    check g.length == 15 # whole line, still one token because there's no hash

    g.gitRebaseTodoNextToken()
    check g.kind == gtEof

  test "hex run inside a longer word is not a hash":
    # `abc1234x` — trailing 'x' means this is not a hash boundary.
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# tag abc1234x here\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtComment
    check g.length == 20

  test "hash separated by '..' is split into two hashes":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# Rebase abc1234..def5678 onto\n")

    g.gitRebaseTodoNextToken()
    check g.kind == gtComment # '#'
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment # ' Rebase '
    g.gitRebaseTodoNextToken()
    check g.kind == gtDecNumber # 'abc1234'
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment # '..'
    g.gitRebaseTodoNextToken()
    check g.kind == gtDecNumber # 'def5678'
    g.gitRebaseTodoNextToken()
    check g.kind == gtComment # ' onto\n'
