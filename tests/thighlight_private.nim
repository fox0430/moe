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

const ReservedWords = @[
  ReservedWord(word: "TODO", color: EditorColorPairIndex.reservedWord),
  ReservedWord(word: "WIP", color: EditorColorPairIndex.reservedWord),
  ReservedWord(word: "NOTE", color: EditorColorPairIndex.reservedWord)
]

suite "parseReservedWord":
  test "no reserved word":
    check parseReservedWord(
      "abcdefh",
      ReservedWords,
      EditorColorPairIndex.default).toSeq == @[("abcdefh", EditorColorPairIndex.default)]

  test "1 TODO":
    check parseReservedWord(
      "# hello TODO world",
      ReservedWords,
      EditorColorPairIndex.default).toSeq == @[
        ("# hello ", EditorColorPairIndex.default),
        ("TODO", EditorColorPairIndex.reservedWord),
        (" world", EditorColorPairIndex.default),
      ]

  test "2 TODO":
    check parseReservedWord(
      "# hello TODO world TODO",
      ReservedWords,
      EditorColorPairIndex.default).toSeq == @[
        ("# hello ", EditorColorPairIndex.default),
        ("TODO", EditorColorPairIndex.reservedWord),
        (" world ", EditorColorPairIndex.default),
        ("TODO", EditorColorPairIndex.reservedWord),
        ("", EditorColorPairIndex.default),
      ]

  test "edge TODO":
    check parseReservedWord(
      "TODO hello TODO",
      ReservedWords,
      EditorColorPairIndex.default).toSeq == @[
        ("", EditorColorPairIndex.default),
        ("TODO", EditorColorPairIndex.reservedWord),
        (" hello ", EditorColorPairIndex.default),
        ("TODO", EditorColorPairIndex.reservedWord),
        ("", EditorColorPairIndex.default),
      ]

  test "TODO and WIP and NOTE":
    check parseReservedWord(
      "hello TODO WIP NOTE world",
      ReservedWords,
      EditorColorPairIndex.default).toSeq == @[
        ("hello ", EditorColorPairIndex.default),
        ("TODO", EditorColorPairIndex.reservedWord),
        (" ", EditorColorPairIndex.default),
        ("WIP", EditorColorPairIndex.reservedWord),
        (" ", EditorColorPairIndex.default),
        ("NOTE", EditorColorPairIndex.reservedWord),
        (" world", EditorColorPairIndex.default),
      ]
  test "no whitespace":
    check parseReservedWord(
      "TODOWIPNOTETODOWIPNOTE",
      ReservedWords,
      EditorColorPairIndex.default).toSeq == @[
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
