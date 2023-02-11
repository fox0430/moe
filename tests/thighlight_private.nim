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
  ReservedWord(word: "TODO", color: EditorColorPair.reservedWord),
  ReservedWord(word: "WIP", color: EditorColorPair.reservedWord),
  ReservedWord(word: "NOTE", color: EditorColorPair.reservedWord)
]

suite "parseReservedWord":
  test "no reserved word":
    check toSeq(parseReservedWord("abcdefh", reservedWords, EditorColorPair.defaultChar)) == @[
      ("abcdefh", EditorColorPair.defaultChar),
    ]
  test "1 TODO":
    check toSeq(parseReservedWord("# hello TODO world", reservedWords, EditorColorPair.defaultChar)) == @[
      ("# hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      (" world", EditorColorPair.defaultChar),
    ]
  test "2 TODO":
    check toSeq(parseReservedWord("# hello TODO world TODO", reservedWords, EditorColorPair.defaultChar)) == @[
      ("# hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      (" world ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
    ]
  test "edge TODO":
    check toSeq(parseReservedWord("TODO hello TODO", reservedWords, EditorColorPair.defaultChar)) == @[
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      (" hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
    ]
  test "TODO and WIP and NOTE":
    check toSeq(parseReservedWord("hello TODO WIP NOTE world", reservedWords, EditorColorPair.defaultChar)) == @[
      ("hello ", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      (" ", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.reservedWord),
      (" ", EditorColorPair.defaultChar),
      ("NOTE", EditorColorPair.reservedWord),
      (" world", EditorColorPair.defaultChar),
    ]
  test "no whitespace":
    check toSeq(parseReservedWord("TODOWIPNOTETODOWIPNOTE", reservedWords, EditorColorPair.defaultChar)) == @[
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("NOTE", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("TODO", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("WIP", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
      ("NOTE", EditorColorPair.reservedWord),
      ("", EditorColorPair.defaultChar),
    ]
