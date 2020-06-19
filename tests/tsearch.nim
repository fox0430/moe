import unittest
import moepkg/[editorstatus]

include moepkg/search

suite "search.nim: searchLine":
  test "searchLine":
    let line = ru"abc efg hijkl"
    let position = line.searchLine(ru"ijk")

    check(position == 9)

  test "searchLine 2":
      let line = ru"abc efg hijkl"
      let position = line.searchLine(ru"xyz")
  
      check(position == -1)
  
suite "search.nim: searchLineReversely":
  test "searchLineReversely":
      let line = ru"abc efg hijkl"
      let position = line.searchLineReversely(ru"ijk")
  
      check(position == 9)
  
  test "searchLineReversely 2":
      let
        line = ru"abc efg hijkl"
        keyword = ru"xyz"
        position = line.searchLineReversely(keyword)
  
      check(position == -1)

suite "search.nim: searchBuffer":
  test "searchBuffer":
    var status = initEditorStatus()
    status.addNewBuffer("")

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"i j"
      searchResult = status.searchBuffer(keyword)

    check(searchResult.line == 1)
    check(searchResult.column == 2)

  test "searchBuffer 2":
    var status = initEditorStatus()
    status.addNewBuffer("")

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"xyz"
      searchResult = status.searchBuffer(keyword)

    check(searchResult.line == -1)
    check(searchResult.column == -1)

suite "search.nim: searchBufferReversely":
  test "searchBufferReversely":
    var status = initEditorStatus()
    status.addNewBuffer("")

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"i j"
      searchResult = status.searchBufferReversely(keyword)

    check(searchResult.line == 1)
    check(searchResult.column == 2)

  test "searchBufferReversely 2":
    var status = initEditorStatus()
    status.addNewBuffer("")

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"xyz"
      searchResult = status.searchBufferReversely(keyword)

    check(searchResult.line == -1)
    check(searchResult.column == -1)

suite "search.nim: searchAllOccurrence":
  test "searchAllOccurrence":
    var status = initEditorStatus()
    status.addNewBuffer("")

    let
      line1 = ru"abc def"
      line2 = ru"ghi abc"
      line3 = ru"abc pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"abc"
      buffer = status.bufStatus[0].buffer
      searchResult = buffer.searchAllOccurrence(keyword)

    check(searchResult.len == 3)

    check(searchResult[0].line == 0)
    check(searchResult[0].column == 0)

    check(searchResult[1].line == 1)
    check(searchResult[1].column == 4)

    check(searchResult[2].line == 2)
    check(searchResult[2].column == 0)

  test "searchAllOccurrence 2":
    var status = initEditorStatus()
    status.addNewBuffer("")

    let
      line1 = ru"abc def"
      line2 = ru"ghi abc"
      line3 = ru"abc pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"xyz"
      buffer = status.bufStatus[0].buffer
      searchResult = buffer.searchAllOccurrence(keyword)

    check(searchResult.len == 0)

suite "search.nim: jumpToSearchForwardResults":
  test "jumpToSearchForwardResults":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.workspace[0].currentMainWindowNode.currentColumn = 1

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno jkl"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let keyword = ru"jkl"
    status.jumpToSearchForwardResults(keyword)

    check(status.workspace[0].currentMainWindowNode.currentLine == 1)
    check(status.workspace[0].currentMainWindowNode.currentColumn == 4)

  test "jumpToSearchForwardResults 2":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.workspace[0].currentMainWindowNode.currentColumn = 1

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let keyword = ru"xyz"
    status.jumpToSearchForwardResults(keyword)

    check(status.workspace[0].currentMainWindowNode.currentLine == 0)
    check(status.workspace[0].currentMainWindowNode.currentColumn == 1)

suite "search.nim: jumpToSearchBackwordResults":
  test "jumpToSearchBackwordResults":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.workspace[0].currentMainWindowNode.currentLine = 1

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno abc"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let keyword = ru"abc"
    status.jumpToSearchBackwordResults(keyword)

    check(status.workspace[0].currentMainWindowNode.currentLine == 0)
    check(status.workspace[0].currentMainWindowNode.currentColumn == 0)

  test "jumpToSearchBackwordResults 2":
    var status = initEditorStatus()
    status.addNewBuffer("")

    status.workspace[0].currentMainWindowNode.currentColumn = 1

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let keyword = ru"xyz"
    status.jumpToSearchBackwordResults(keyword)

    check(status.workspace[0].currentMainWindowNode.currentLine == 0)
    check(status.workspace[0].currentMainWindowNode.currentColumn == 1)
