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

import ../src/moepkg/syntax/[tokenizer, syntax_dockerfile]

suite "syntax_dockerfile - instructions":
  test "FROM":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("FROM")
    g.dockerfileNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "RUN":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("RUN")
    g.dockerfileNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "CMD":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("CMD")
    g.dockerfileNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "COPY":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("COPY")
    g.dockerfileNextToken()
    check g.kind == gtKeyword
    check g.length == 4

  test "WORKDIR":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("WORKDIR")
    g.dockerfileNextToken()
    check g.kind == gtKeyword
    check g.length == 7

  test "ENV":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("ENV")
    g.dockerfileNextToken()
    check g.kind == gtKeyword
    check g.length == 3

  test "EXPOSE":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("EXPOSE")
    g.dockerfileNextToken()
    check g.kind == gtKeyword
    check g.length == 6

  test "ENTRYPOINT":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("ENTRYPOINT")
    g.dockerfileNextToken()
    check g.kind == gtKeyword
    check g.length == 10

  test "Instruction not at line start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("echo FROM")
    # First token is "echo" (identifier, not keyword)
    g.dockerfileNextToken()
    check g.kind == gtIdentifier
    # Whitespace
    g.dockerfileNextToken()
    check g.kind == gtWhitespace
    # "FROM" not at line start -> identifier
    g.dockerfileNextToken()
    check g.kind == gtIdentifier

suite "syntax_dockerfile - AS keyword":
  test "AS after FROM":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("FROM ubuntu AS base")
    g.dockerfileNextToken()
    check g.kind == gtKeyword # FROM
    g.dockerfileNextToken()
    check g.kind == gtWhitespace
    g.dockerfileNextToken()
    check g.kind == gtIdentifier # ubuntu
    g.dockerfileNextToken()
    check g.kind == gtWhitespace
    g.dockerfileNextToken()
    check g.kind == gtKeyword # AS
    g.dockerfileNextToken()
    check g.kind == gtWhitespace
    g.dockerfileNextToken()
    check g.kind == gtIdentifier # base

suite "syntax_dockerfile - comments":
  test "Comment at line start":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("# this is a comment")
    g.dockerfileNextToken()
    check g.kind == gtComment
    check g.length == 19

  test "Comment after newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("FROM ubuntu\n# comment")
    g.dockerfileNextToken() # FROM
    g.dockerfileNextToken() # space
    g.dockerfileNextToken() # ubuntu
    g.dockerfileNextToken() # newline
    g.dockerfileNextToken()
    check g.kind == gtComment

suite "syntax_dockerfile - strings":
  test "Double-quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello world\"")
    g.dockerfileNextToken()
    check g.kind == gtStringLit
    check g.length == 13

  test "Single-quoted string":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("'hello'")
    g.dockerfileNextToken()
    check g.kind == gtStringLit
    check g.length == 7

  test "String with escape":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\"hello\\nworld\"")
    g.dockerfileNextToken()
    check g.kind == gtStringLit
    check g.length == 14

suite "syntax_dockerfile - variable expansion":
  test "$VAR":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("$HOME")
    g.dockerfileNextToken()
    check g.kind == gtBuiltin
    check g.length == 5

  test "${VAR}":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("${HOME}")
    g.dockerfileNextToken()
    check g.kind == gtBuiltin
    check g.length == 7

suite "syntax_dockerfile - numbers":
  test "Integer":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("8080")
    g.dockerfileNextToken()
    check g.kind == gtDecNumber
    check g.length == 4

suite "syntax_dockerfile - operators":
  test "Equals":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("=")
    g.dockerfileNextToken()
    check g.kind == gtOperator
    check g.length == 1

  test "Colon":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(":")
    g.dockerfileNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntax_dockerfile - flags":
  test "--from flag":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--from")
    g.dockerfileNextToken()
    check g.kind == gtPreprocessor
    check g.length == 6

  test "--from=builder":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("--from=builder")
    g.dockerfileNextToken()
    check g.kind == gtPreprocessor
    check g.length == 6 # --from
    g.dockerfileNextToken()
    check g.kind == gtOperator
    check g.length == 1 # =
    g.dockerfileNextToken()
    check g.kind == gtIdentifier
    check g.length == 7 # builder

suite "syntax_dockerfile - punctuation":
  test "Brackets":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("[")
    g.dockerfileNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

  test "Comma":
    var g: GeneralTokenizer
    g.initGeneralTokenizer(",")
    g.dockerfileNextToken()
    check g.kind == gtPunctuation
    check g.length == 1

suite "syntax_dockerfile - line continuation":
  test "Backslash before newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\\\n")
    g.dockerfileNextToken()
    check g.kind == gtOperator
    check g.length == 1

suite "syntax_dockerfile - whitespace":
  test "Spaces":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("   ")
    g.dockerfileNextToken()
    check g.kind == gtWhitespace
    check g.length == 3

  test "Newline":
    var g: GeneralTokenizer
    g.initGeneralTokenizer("\n")
    g.dockerfileNextToken()
    check g.kind == gtWhitespace
    check g.length == 1
