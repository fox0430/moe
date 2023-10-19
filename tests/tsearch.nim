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

import std/[unittest, options, strformat]
import pkg/results
import moepkg/[unicodeext, editorstatus, gapbuffer, independentutils]

import moepkg/searchutils {.all.}

suite "search: searchLine":
  test "searchLine":
    let
      line = ru"abc efg hijkl"
      isIgnorecase = true
      isSmartcase = true
      position = line.searchLine(ru"ijk", isIgnorecase, isSmartcase)

    check position.get == 9

  test "searchLine 2":
    let
      line = ru"abc efg hijkl"
      isIgnorecase = true
      isSmartcase = true
      position = line.searchLine(ru"xyz", isIgnorecase, isSmartcase)

    check position.isNone

  test "Enable ignorecase, disable smartcase":
    let
      line = ru"Editor editor"
      isIgnorecase = true
      isSmartcase = true
      position = line.searchLine(ru"editor", isIgnorecase, isSmartcase)

    check position.get == 0

  test "Enable ignorecase and smartcase":
    block:
      let
        line = ru"editor Editor"
        isIgnorecase = true
        isSmartcase = true
        position = line.searchLine(ru"Editor", isIgnorecase, isSmartcase)

      check position.get == 7

    block:
      let
        line = ru"editor Editor"
        isIgnorecase = true
        isSmartcase = true
        position = line.searchLine(ru"editor", isIgnorecase, isSmartcase)

      check position.get == 0

  test "Disable ignorecase":
    let
      line = ru"Editor"
      isIgnorecase = false
      isSmartcase = false
      position = line.searchLine(ru"editor", isIgnorecase, isSmartcase)

    check position.isNone

suite "search: searchLineReversely":
  test "searchLineReversely":
    let
      line = ru"abc efg hijkl"
      isIgnorecase = true
      isSmartcase = true
      position = line.searchLineReversely(ru"ijk", isIgnorecase, isSmartcase)

    check position.get == 9

  test "searchLineReversely 2":
      let
        line = ru"abc efg hijkl"
        keyword = ru"xyz"
        isIgnorecase = true
        isSmartcase = true
        position = line.searchLineReversely(keyword, isIgnorecase, isSmartcase)

      check position.isNone

suite "search: searchBuffer":
  test "searchBuffer":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"i j"
      isIgnorecase = true
      isSmartcase = true
      searchResult = currentBufStatus.searchBuffer(
        currentMainWindowNode, keyword, isIgnorecase, isSmartcase)

    check searchResult.get.line == 1
    check searchResult.get.column == 2

  test "searchBuffer 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"xyz"
      isIgnorecase = true
      isSmartcase = true
      searchResult = currentBufStatus.searchBuffer(
        currentMainWindowNode, keyword, isIgnorecase, isSmartcase)

    check searchResult.isNone

suite "search: searchBufferReversely":
  test "searchBufferReversely":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"i j"
      isIgnorecase = true
      isSmartcase = true
      searchResult = currentBufStatus.searchBufferReversely(
        currentMainWindowNode,
        keyword,
        isIgnorecase,
        isSmartcase)

    check searchResult.get.line == 1
    check searchResult.get.column == 2

  test "searchBufferReversely 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"xyz"
      isIgnorecase = true
      isSmartcase = true
      searchResult = currentBufStatus.searchBufferReversely(
        currentMainWindowNode,
        keyword,
        isIgnorecase,
        isSmartcase)

    check searchResult.isNone

suite "search: searchAllOccurrence":
  test "searchAllOccurrence":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const
      Line1 = "abc def"
      Line2 = "ghi abc"
      Line3 = "abc pqr"
      Buffer = @[Line1, Line2, Line3].toSeqRunes
      Keyword = ru"abc"
      IsIgnorecase = true
      IsSmartcase = true

    let searchResult = Buffer.searchAllOccurrence(
      Keyword,
      IsIgnorecase,
      IsSmartcase)

    check searchResult.len == 3

    check searchResult[0].line == 0
    check searchResult[0].column == 0

    check searchResult[1].line == 1
    check searchResult[1].column == 4

    check searchResult[2].line == 2
    check searchResult[2].column == 0

  test "searchAllOccurrence 2":
    var status = initEditorStatus()
    discard status.addNewBufferInCurrentWin.get

    const
      Line1 = "abc def"
      Line2 = "ghi abc"
      Line3 = "abc pqr"
      Buffer = @[Line1, Line2, Line3].toSeqRunes
      Keyword = ru"xyz"
      IsIgnorecase = true
      IsSmartcase = true

    let searchResult = Buffer.searchAllOccurrence(
        Keyword,
        IsIgnorecase,
        IsSmartcase)

    check searchResult.len == 0

suite "search: searchClosingParen":
  const
    OpenParens = [ru'(', ru'{', ru'[']
    CloseParens = [ru')', ru'}', ru']']

  proc searchClosingParenTest(
    testIndex: int,
    openParen: Rune,
    buffer: seq[Runes],
    closeParenPosition: BufferPosition,
    expectResult: Option[BufferPosition]) =

      let testTitle =
        "Case " & $testIndex & ": '" & $openParen & "'"

      test testTitle:
        let searchResult = searchClosingParen(buffer, closeParenPosition)
        check searchResult == expectResult

  block searchClosingParenTestCase1:
    # Case 1 is starting the search on an empty line.
    const
      TestIndex = 1
      Buffer = @[ru""]
      CurrentPosition = BufferPosition(line: 0, column: 0)
      ExpectResult = SearchResult.none

    for paren in OpenParens:
      searchClosingParenTest(
        TestIndex,
        paren,
        Buffer,
        CurrentPosition,
        ExpectResult)

  block searchClosingParenTestCase2:
    const TestIndex = 2

    for i in 0 .. OpenParens.high:
      let buffer = @[toRunes(fmt"{OpenParens[i]}{CloseParens[i]}")]
      const
        CurrentPosition = BufferPosition(line: 0, column: 0)
        ExpectResult = SearchResult(line: 0, column: 1).some

      searchClosingParenTest(
        TestIndex,
        OpenParens[i],
        buffer,
        CurrentPosition,
        ExpectResult)

  block searchClosingParenTestCase3:
    const TestIndex = 3

    for i in 0 .. OpenParens.high:
      let buffer = @[toRunes(fmt"{OpenParens[i]} {CloseParens[i]}")]
      const
        CurrentPosition = BufferPosition(line: 0, column: 0)
        ExpectPosition = SearchResult(line: 0, column: 2).some
      searchClosingParenTest(
        TestIndex,
        OpenParens[i],
        buffer,
        CurrentPosition,
        ExpectPosition)

  block searchClosingParenTestCase4:
    const TestIndex = 4

    for i in 0 .. OpenParens.high:
      let buffer = @[OpenParens[i].toRunes, CloseParens[i].toRunes]
      const
        CurrentPosition = BufferPosition(line: 0, column: 0)
        ExpectResult = SearchResult(line: 1, column: 0).some
      searchClosingParenTest(
        TestIndex,
        OpenParens[i],
        buffer,
        CurrentPosition,
        ExpectResult)

  block searchClosingParenTestCase5:
    const TestIndex = 5

    for i in 0 .. OpenParens.high:
      let buffer = @[OpenParens[i].toRunes, ru"", CloseParens[i].toRunes]
      const
        CurrentPosition = BufferPosition(line: 0, column: 0)
        ExpectResult = SearchResult(line: 2, column: 0).some
      searchClosingParenTest(
        TestIndex,
        OpenParens[i],
        buffer,
        CurrentPosition,
        ExpectResult)

  block searchClosingParenTestCase6:
    const TestIndex = 6

    for i in 0 .. OpenParens.high:
      let buffer = @[OpenParens[i].toRunes, ru""]
      const
        CurrentPosition = BufferPosition(line: 0, column: 0)
        ExpectResult = none(SearchResult)
      searchClosingParenTest(
        TestIndex,
        OpenParens[i],
        buffer,
        CurrentPosition,
        ExpectResult)

  block searchOpeningParenTest7:
    # matchingParenPair should ignore '"'.
    const
      TestIndex = 7
      Buffer = @["\"\"".toRunes]
      Paren = ru'"'
      CurrentPosition = BufferPosition(line: 0, column: 0)
      ExpectResult = none(SearchResult)

    searchClosingParenTest(
      TestIndex,
      Paren,
      Buffer,
      CurrentPosition,
      ExpectResult)

  block searchOpeningParenTest8:
    # matchingParenPair should ignore '''.
    const
      TestIndex = 8
      Buffer = @["''".toRunes]
      Paren = ru'\''
      CurrentPosition = BufferPosition(line: 0, column: 0)
      ExpectResult = none(SearchResult)

    searchClosingParenTest(
      TestIndex,
      Paren,
      Buffer,
      CurrentPosition,
      ExpectResult)

suite "search: searchOpeningParen":
  const
    OpenParens = [ru'(', ru'{', ru'[']
    CloseParens = [ru')', ru'}', ru']']

  proc searchOpeningParenTest(
    testIndex: int,
    closeParen: Rune,
    buffer: seq[Runes],
    closeParenPosition: BufferPosition,
    expectResult: Option[BufferPosition]) =

      let testTitle =
        "Case " & $testIndex & ": '" & $closeParen & "'"

      test testTitle:
        let searchResult = searchOpeningParen(buffer, closeParenPosition)
        check searchResult == expectResult

  block searchOpeningParenTestCase1:
    # Case 1 is starting the search on an empty line.
    const
      TestIndex = 1
      Buffer = @[ru""]
      CurrentPosition = BufferPosition(line: 0, column: 0)
      ExpectResult = SearchResult.none

    for paren in CloseParens:
      searchOpeningParenTest(
        TestIndex,
        paren,
        Buffer,
        CurrentPosition,
        ExpectResult)

  block searchOpeningParenTestCase2:
    const TestIndex = 2

    for i in 0 .. OpenParens.high:
      let buffer = @[toRunes(fmt"{OpenParens[i]}{CloseParens[i]}")]
      const
        CurrentPosition = BufferPosition(line: 0, column: 1)
        ExpectResult = SearchResult(line: 0, column: 0).some

      searchOpeningParenTest(
        TestIndex,
        CloseParens[i],
        buffer,
        CurrentPosition,
        ExpectResult)

  block searchOpeningParenTestCase3:
    const TestIndex = 3

    for i in 0 .. OpenParens.high:
      let buffer = @[toRunes(fmt"{OpenParens[i]} {CloseParens[i]}")]
      const
        CurrentPosition = BufferPosition(line: 0, column: 2)
        ExpectPosition = SearchResult(line: 0, column: 0).some
      searchOpeningParenTest(
        TestIndex,
        CloseParens[i],
        buffer,
        CurrentPosition,
        ExpectPosition)

  block searchOpeningParenTestCase4:
    const TestIndex = 4

    for i in 0 .. OpenParens.high:
      let buffer = @[OpenParens[i].toRunes, CloseParens[i].toRunes]
      const
        CurrentPosition = BufferPosition(line: 1, column: 0)
        ExpectResult = SearchResult(line: 0, column: 0).some
      searchOpeningParenTest(
        TestIndex,
        CloseParens[i],
        buffer,
        CurrentPosition,
        ExpectResult)

  block searchOpeningParenTestCase5:
    const TestIndex = 5

    for i in 0 .. OpenParens.high:
      let buffer = @[OpenParens[i].toRunes, ru"", CloseParens[i].toRunes]
      const
        CurrentPosition = BufferPosition(line: 2, column: 0)
        ExpectResult = SearchResult(line: 0, column: 0).some
      searchOpeningParenTest(
        TestIndex,
        CloseParens[i],
        buffer,
        CurrentPosition,
        ExpectResult)

  block searchOpeningParenTestCase6:
    const TestIndex = 6

    for i in 0 .. OpenParens.high:
      let buffer = @[CloseParens[i].toRunes, ru""]
      const
        CurrentPosition = BufferPosition(line: 0, column: 0)
        ExpectResult = none(SearchResult)
      searchOpeningParenTest(
        TestIndex,
        CloseParens[i],
        buffer,
        CurrentPosition,
        ExpectResult)

  block searchOpeningParenTest7:
    # matchingParenPair should ignore '"'.
    const
      TestIndex = 7
      Buffer = @["\"\"".toRunes]
      Paren = ru'"'
      CurrentPosition = BufferPosition(line: 0, column: 0)
      ExpectResult = none(SearchResult)

    searchOpeningParenTest(
      TestIndex,
      Paren,
      Buffer,
      CurrentPosition,
      ExpectResult)

  block searchOpeningParenTest8:
    # matchingParenPair should ignore '''.
    const
      TestIndex = 8
      Buffer = @["''".toRunes]
      Paren = ru'\''
      CurrentPosition = BufferPosition(line: 0, column: 0)
      ExpectResult = none(SearchResult)

    searchOpeningParenTest(
      TestIndex,
      Paren,
      Buffer,
      CurrentPosition,
      ExpectResult)

suite "search: matchingParenPair":
  let
    openParens = @[ru'(', ru'{', ru'[']
    closeParens = @[ru')', ru'}', ru']']

  proc matchingParenPairTest(
    testIndex: int,
    paren: Rune,
    buffer: seq[Runes],
    currentPosition: BufferPosition,
    expectPosition: Option[BufferPosition]) =

      let testTitle =
        "Case " & $testIndex & ": matchingParenPair: '" & $paren & "'"

      test testTitle:
        var status = initEditorStatus()
        discard status.addNewBufferInCurrentWin.get

        status.bufStatus[0].buffer = `buffer`.toGapBuffer

        let searchResult = status.bufStatus[0].matchingParenPair(
          currentPosition)
        check searchResult == expectPosition

  block matchingParenPairTestCase1:
    ## Case 1 is starting the search on an empty line.
    let
      testIndex = 1
      buffer = @[ru""]
      currentPosition = BufferPosition(line: 0, column: 0)
      expectPosition = SearchResult.none

    for i in 0 ..< openParens.len:
      block open:
        matchingParenPairTest(testIndex, openParens[i], buffer, currentPosition, expectPosition)
      block close:
        matchingParenPairTest(testIndex, closeParens[i], buffer, currentPosition, expectPosition)

  block matchingParenPairTestCase2:
    let testIndex = 2

    for i in 0 ..< openParens.len:
      let buffer = @[toRunes(fmt"{openParens[i]}{closeParens[i]}")]

      block open:
        let
          currentPosition = BufferPosition(line: 0, column: 0)
          expectPosition = SearchResult(line: 0, column: 1).some
        matchingParenPairTest(testIndex, openParens[i], buffer, currentPosition, expectPosition)

      block close:
        let
          currentPosition = BufferPosition(line: 0, column: 1)
          expectPosition = SearchResult(line: 0, column: 0).some
        matchingParenPairTest(testIndex, closeParens[i], buffer, currentPosition, expectPosition)

  block matchingParenPairTestCase3:
    let testIndex = 3

    for i in 0 ..< openParens.len:
      let buffer = @[toRunes(fmt"{openParens[i]} {closeParens[i]}")]

      block open:
        let
          currentPosition = BufferPosition(line: 0, column: 0)
          expectPosition = SearchResult(line: 0, column: 2).some
        matchingParenPairTest(testIndex, openParens[i], buffer, currentPosition, expectPosition)

      block close:
        let
          currentPosition = BufferPosition(line: 0, column: 2)
          expectPosition = SearchResult(line: 0, column: 0).some
        matchingParenPairTest(testIndex, closeParens[i], buffer, currentPosition, expectPosition)

  block matchingParenPairTestCase4:
    let testIndex = 4

    for i in 0 ..< openParens.len:
      let buffer = @[openParens[i].toRunes, closeParens[i].toRunes]

      block open:
        let
          currentPosition = BufferPosition(line: 0, column: 0)
          expectPosition = SearchResult(line: 1, column: 0).some
        matchingParenPairTest(testIndex, openParens[i], buffer, currentPosition, expectPosition)

      block close:
        let
          currentPosition = BufferPosition(line: 1, column: 0)
          expectPosition = SearchResult(line: 0, column: 0).some
        matchingParenPairTest(testIndex, closeParens[i], buffer, currentPosition, expectPosition)

  block matchingParenPairTestCase5:
    let testIndex = 5

    for i in 0 ..< openParens.len:
      let buffer = @[openParens[i].toRunes, ru"", closeParens[i].toRunes]

      block open:
        let
          currentPosition = BufferPosition(line: 0, column: 0)
          expectPosition = SearchResult(line: 2, column: 0).some
        matchingParenPairTest(testIndex, openParens[i], buffer, currentPosition, expectPosition)

      block close:
        let
          currentPosition = BufferPosition(line: 2, column: 0)
          expectPosition = SearchResult(line: 0, column: 0).some
        matchingParenPairTest(testIndex, closeParens[i], buffer, currentPosition, expectPosition)

  block matchingParenPairTestCase6:
    let testIndex = 6

    for i in 0 ..< openParens.len:

      block open:
        let buffer = @[openParens[i].toRunes, ru""]
        let
          currentPosition = BufferPosition(line: 0, column: 0)
          expectPosition = none(SearchResult)
        matchingParenPairTest(testIndex, openParens[i], buffer, currentPosition, expectPosition)

      block close:
        let buffer = @[ru"", closeParens[i].toRunes]
        let
          currentPosition = BufferPosition(line: 1, column: 0)
          expectPosition = none(SearchResult)
        matchingParenPairTest(testIndex, closeParens[i], buffer, currentPosition, expectPosition)

  block matchingParenPairTestCase7:
    ## matchingParenPair should ignore '"'.
    let
      testIndex = 7
      buffer = @["\"\"".toRunes]
      paren = ru'"'
      currentPosition = BufferPosition(line: 0, column: 0)
      expectPosition = none(SearchResult)

    matchingParenPairTest(testIndex, paren, buffer, currentPosition, expectPosition)

  block matchingParenPairTestCase8:
    ## matchingParenPair should ignore '''.
    let
      testIndex = 8
      buffer = @["''".toRunes]
      paren = ru'\''
      currentPosition = BufferPosition(line: 0, column: 0)
      expectPosition = none(SearchResult)

    matchingParenPairTest(testIndex, paren, buffer, currentPosition, expectPosition)

suite "saveSearchHistory":
  test "Save search history 1":
    var searchHistory: seq[Runes]
    let
      keywords = @[ru"test", ru"test2"]
      limit = 1000

    for word in keywords:
      searchHistory.saveSearchHistory(word, limit)

    check searchHistory == keywords

  test "Save search history 2":
    var searchHistory: seq[Runes]
    let
      keywords = @[ru"test", ru"test2"]
      limit = 1

    for word in keywords:
      searchHistory.saveSearchHistory(word, limit)

    check searchHistory == @[keywords[1]]

  test "Save search history 3":
    var searchHistory: seq[Runes]
    let
      keywords = @[ru"test", ru"test2"]
      limit = 0

    for word in keywords:
      searchHistory.saveSearchHistory(word, limit)
      check searchHistory.len == 0

suite "searchutils: findFirstOfWord":
  test "Empty line":
    const Position = 0
    check findFirstOfWord(ru"", Position) == 0

  test "Alfabets":
    const Position = 2
    check findFirstOfWord(ru"abc", Position) == 0

  test "Alfabets with space":
    const Position = 6
    check findFirstOfWord(ru"abc def", Position) == 4

  test "Alfabets with symbol":
    const Position = 6
    check findFirstOfWord(ru"abc*def", Position) == 4

  test "Digits":
    const Position = 2
    check findFirstOfWord(ru"123", Position) == 0

  test "Digits with space":
    const Position = 6
    check findFirstOfWord(ru"123 456", Position) == 4

  test "Digits with symbol":
    const Position = 6
    check findFirstOfWord(ru"123*456", Position) == 4

  test "Spaces":
    const Position = 2
    check findFirstOfWord(ru"   ", Position) == 0

  test "Spaces with alfabet":
    const Position = 6
    check findFirstOfWord(ru"   a   ", Position) == 4

  test "Spaces with symbol":
    const Position = 6
    check findFirstOfWord(ru"   *   ", Position) == 4

  test "Symbol with Alfabets":
    const Position = 3
    check findFirstOfWord(ru"abc*def", Position) == 3
