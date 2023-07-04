#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
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

import std/[unittest, sequtils]
import moepkg/color

import moepkg/highlight {.all.}

const reservedWords = @[
  ReservedWord(word: "TODO", color: EditorColorPairIndex.reservedWord),
  ReservedWord(word: "WIP", color: EditorColorPairIndex.reservedWord),
  ReservedWord(word: "NOTE", color: EditorColorPairIndex.reservedWord)
]

suite "parseReservedWord":
  test "no reserved word":
    check toSeq(parseReservedWord("abcdefh", reservedWords, EditorColorPairIndex.default)) == @[
      ("abcdefh", EditorColorPairIndex.default),
    ]
  test "1 TODO":
    check toSeq(parseReservedWord("# hello TODO world", reservedWords, EditorColorPairIndex.default)) == @[
      ("# hello ", EditorColorPairIndex.default),
      ("TODO", EditorColorPairIndex.reservedWord),
      (" world", EditorColorPairIndex.default),
    ]
  test "2 TODO":
    check toSeq(parseReservedWord("# hello TODO world TODO", reservedWords, EditorColorPairIndex.default)) == @[
      ("# hello ", EditorColorPairIndex.default),
      ("TODO", EditorColorPairIndex.reservedWord),
      (" world ", EditorColorPairIndex.default),
      ("TODO", EditorColorPairIndex.reservedWord),
      ("", EditorColorPairIndex.default),
    ]
  test "edge TODO":
    check toSeq(parseReservedWord("TODO hello TODO", reservedWords, EditorColorPairIndex.default)) == @[
      ("", EditorColorPairIndex.default),
      ("TODO", EditorColorPairIndex.reservedWord),
      (" hello ", EditorColorPairIndex.default),
      ("TODO", EditorColorPairIndex.reservedWord),
      ("", EditorColorPairIndex.default),
    ]
  test "TODO and WIP and NOTE":
    check toSeq(parseReservedWord("hello TODO WIP NOTE world", reservedWords, EditorColorPairIndex.default)) == @[
      ("hello ", EditorColorPairIndex.default),
      ("TODO", EditorColorPairIndex.reservedWord),
      (" ", EditorColorPairIndex.default),
      ("WIP", EditorColorPairIndex.reservedWord),
      (" ", EditorColorPairIndex.default),
      ("NOTE", EditorColorPairIndex.reservedWord),
      (" world", EditorColorPairIndex.default),
    ]
  test "no whitespace":
    check toSeq(parseReservedWord("TODOWIPNOTETODOWIPNOTE", reservedWords, EditorColorPairIndex.default)) == @[
      ("", EditorColorPairIndex.default),
      ("TODO", EditorColorPairIndex.reservedWord),
      ("", EditorColorPairIndex.default),
      ("WIP", EditorColorPairIndex.reservedWord),
      ("", EditorColorPairIndex.default),
      ("NOTE", EditorColorPairIndex.reservedWord),
      ("", EditorColorPairIndex.default),
      ("TODO", EditorColorPairIndex.reservedWord),
      ("", EditorColorPairIndex.default),
      ("WIP", EditorColorPairIndex.reservedWord),
      ("", EditorColorPairIndex.default),
      ("NOTE", EditorColorPairIndex.reservedWord),
      ("", EditorColorPairIndex.default),
    ]
