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
import moepkg/[color, unicodeext]
import moepkg/syntax/highlite

import moepkg/highlight {.all.}

suite "highlight: initHighlight":
  const ReservedWords = @[
    ReservedWord(word: "WIP", color: EditorColorPairIndex.reservedWord)
  ]

  test "langNone":
    const Buffer = @["", "1", "123"].toSeqRunes
    let h = initHighlight(Buffer, ReservedWords, SourceLanguage.langNone)
    check h.colorSegments == @[
      ColorSegment(
        firstRow: 0,
        firstColumn: 0,
        lastRow: 0,
        lastColumn: -1,
        color: EditorColorPairIndex.default),
      ColorSegment(
        firstRow: 1,
        firstColumn: 0,
        lastRow: 1,
        lastColumn: 0,
        color: EditorColorPairIndex.default),
      ColorSegment(
        firstRow: 2,
        firstColumn: 0,
        lastRow: 2,
        lastColumn: 2,
        color: EditorColorPairIndex.default)]

  test """Highlight "echo \"""":
    # Fix #733
    const Code = """echo "\""""
    let buffer = @[Code].toSeqRunes
    discard initHighlight(
      buffer,
      ReservedWords,
      SourceLanguage.langNim)

  test "Only '/' in Clang":
    # https://github.com/fox0430/moe/issues/1568

    const
      Code = "/"
      EmptyReservedWords = @[]
    let
      buffer = @[Code].toSeqRunes
      highlight = initHighlight(
        buffer,
        EmptyReservedWords,
        SourceLanguage.langC)

    check highlight[] == Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 0,
          color: EditorColorPairIndex.default)])[]

  test "initHighlight shell script (Fix #1166)":
    const Code = "echo hello"
    let
      buffer = @[Code].toSeqRunes
      highlight = initHighlight(
        buffer,
        ReservedWords,
        SourceLanguage.langShell)

    check highlight.len > 0

  test "Nim pragma":
    const Code = """{.pragma.}""""
    let
      buffer = @[Code].toSeqRunes
      highlight = initHighlight(
        buffer,
        ReservedWords,
        SourceLanguage.langNim)

    check highlight[2] == ColorSegment(
      firstRow: 0,
      firstColumn: 2,
      lastRow: 0,
      lastColumn: 7,
      color: EditorColorPairIndex.pragma)

  test "Fix #1524":
    # https://github.com/fox0430/moe/issues/1524

    const Code = "test: '0'"
    let
      buffer = @[Code].toSeqRunes
      highlight = initHighlight(
        buffer,
        ReservedWords,
        SourceLanguage.langYaml)

    check highlight[] == Highlight(
      colorSegments: @[
        ColorSegment(
          firstRow: 0,
          firstColumn: 0,
          lastRow: 0,
          lastColumn: 3,
          color: EditorColorPairIndex.default),
        ColorSegment(
          firstRow: 0,
          firstColumn: 4,
          lastRow: 0,
          lastColumn: 4,
          color: EditorColorPairIndex.default),
        ColorSegment(
          firstRow: 0,
          firstColumn: 5,
          lastRow: 0,
          lastColumn: 5,
          color: EditorColorPairIndex.default),
        ColorSegment(
          firstRow: 0,
          firstColumn: 6,
          lastRow: 0,
          lastColumn: 8,
          color: EditorColorPairIndex.default)])[]

suite "highlight: indexOf":
  const ReservedWords = @[
    ReservedWord(word: "WIP", color: EditorColorPairIndex.reservedWord)
  ]

  test "Basic":
    const Code = "proc test =\x0A  echo \"Hello, world!\""
    let
      buffer = @[Code].toSeqRunes
      highlight = initHighlight(
       buffer,
       ReservedWords,
       SourceLanguage.langNim)

    check(highlight.indexOf(0, 0) == 0)

  test "Start with newline":
    const Code = "\x0Aproc test =\x0A  echo \"Hello, world!\""
    let
      buffer = @[Code].toSeqRunes
      highlight = initHighlight(
       buffer,
       ReservedWords,
       SourceLanguage.langNim)

    check(highlight.indexOf(0, 0) == 0)

suite "highlight: overwrite":
  const ReservedWords = @[
    ReservedWord(word: "WIP", color: EditorColorPairIndex.reservedWord)
  ]

  test "Basic":
    # Full width space
    const Code = "　"
    let buffer = @[Code].toSeqRunes
    var
      highlight = initHighlight(
        buffer,
        ReservedWords,
        SourceLanguage.langNone)

    let colorSegment = ColorSegment(
      firstRow: 0,
      firstColumn: 0,
      lastRow: 0,
      lastColumn: 0,
      color: EditorColorPairIndex.highlightFullWidthSpace)

    highlight.overwrite(colorSegment)

    check(highlight.len == 1)
    check(highlight[0].firstRow == 0)
    check(highlight[0].firstColumn == 0)
    check(highlight[0].lastRow == 0)
    check(highlight[0].lastColumn == 0)
    check(highlight[0].color == EditorColorPairIndex.highlightFullWidthSpace)

suite "parseReservedWord":
  const ReservedWords = @[
    ReservedWord(word: "TODO", color: EditorColorPairIndex.reservedWord),
    ReservedWord(word: "WIP", color: EditorColorPairIndex.reservedWord),
    ReservedWord(word: "NOTE", color: EditorColorPairIndex.reservedWord)
  ]

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
