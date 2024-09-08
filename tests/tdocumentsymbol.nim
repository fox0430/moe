#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[unittest, options, sequtils, strutils]

import pkg/results

import moepkg/[editorstatus, unicodeext, gapbuffer]
import moepkg/lsp/[documentsymbol, utils]

import moepkg/documentsymbol {.all.}

suite "documentsymbol: jumpToSymbol":
  var status: EditorStatus

  setup:
    status = initEditorStatus()
    assert status.addNewBufferInCurrentWin().isOk

  test "Not found":
    currentBufStatus.documentSymbols = @[
      DocumentSymbol(
        name: "aba",
        kind: 1,
        range: some(LspRange(
          start: LspPosition(line: 0, character: 1),
          `end`: LspPosition(line: 2, character: 3)
        ))
      ),
      DocumentSymbol(
        name: "abb",
        kind: 2,
        range: some(LspRange(
          start: LspPosition(line: 4, character: 5),
          `end`: LspPosition(line: 6, character: 7)
        ))
      ),
      DocumentSymbol(
        name: "ccc",
        kind: 3,
        range: some(LspRange(
          start: LspPosition(line: 8, character: 9),
          `end`: LspPosition(line: 10, character: 11)
        ))
      )
    ]

    let symbolName = ru""

    status.jumpToSymbol(symbolName)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Not found 2":
    currentBufStatus.documentSymbols = @[
      DocumentSymbol(
        name: "aba",
        kind: 1,
        range: some(LspRange(
          start: LspPosition(line: 0, character: 1),
          `end`: LspPosition(line: 2, character: 3)
        ))
      ),
      DocumentSymbol(
        name: "abb",
        kind: 2,
        range: some(LspRange(
          start: LspPosition(line: 4, character: 5),
          `end`: LspPosition(line: 6, character: 7)
        ))
      ),
      DocumentSymbol(
        name: "ccc",
        kind: 3,
        range: some(LspRange(
          start: LspPosition(line: 8, character: 9),
          `end`: LspPosition(line: 10, character: 11)
        ))
      )
    ]

    let symbolName = ru"xyz"

    status.jumpToSymbol(symbolName)

    check currentMainWindowNode.currentLine == 0
    check currentMainWindowNode.currentColumn == 0

  test "Basic":
    currentBufStatus.buffer = toSeq(0..10)
      .mapIt(" ".repeat(11))
      .toSeqRunes
      .toGapBuffer

    currentBufStatus.documentSymbols = @[
      DocumentSymbol(
        name: "aba",
        kind: 1,
        range: some(LspRange(
          start: LspPosition(line: 0, character: 1),
          `end`: LspPosition(line: 2, character: 3)
        ))
      ),
      DocumentSymbol(
        name: "abb",
        kind: 2,
        range: some(LspRange(
          start: LspPosition(line: 4, character: 5),
          `end`: LspPosition(line: 6, character: 7)
        ))
      ),
      DocumentSymbol(
        name: "ccc",
        kind: 3,
        range: some(LspRange(
          start: LspPosition(line: 8, character: 9),
          `end`: LspPosition(line: 10, character: 11)
        ))
      )
    ]

    let symbolName = ru"abb"

    status.jumpToSymbol(symbolName)

    check currentMainWindowNode.currentLine == 4
    check currentMainWindowNode.currentColumn == 5

  test "Over length position":
    currentBufStatus.buffer = toSeq(0..10)
      .mapIt(" ".repeat(11))
      .toSeqRunes
      .toGapBuffer

    currentBufStatus.documentSymbols = @[
      DocumentSymbol(
        name: "a",
        kind: 1,
        range: some(LspRange(
          start: LspPosition(line: 100, character: 100),
          `end`: LspPosition(line: 100, character: 100)
        ))
      )
    ]

    let symbolName = ru"a"

    status.jumpToSymbol(symbolName)

    check currentMainWindowNode.currentLine == 10
    check currentMainWindowNode.currentColumn == 10

