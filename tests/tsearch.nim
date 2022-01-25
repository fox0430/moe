import std/unittest
import moepkg/editorstatus

include moepkg/[search, searchutils]

suite "search.nim: searchLine":
  test "searchLine":
    let
      line = ru"abc efg hijkl"
      ignorecase = true
      smartcase = true
      position = line.searchLine(ru"ijk", ignorecase, smartcase)

    check(position == 9)

  test "searchLine 2":
    let
      line = ru"abc efg hijkl"
      ignorecase = true
      smartcase = true
      position = line.searchLine(ru"xyz", ignorecase, smartcase)

    check(position == -1)

  test "Enable ignorecase, disable smartcase":
    let
      line = ru"Editor editor"
      ignorecase = true
      smartcase = true
      position = line.searchLine(ru"editor", ignorecase, smartcase)

    check(position == 0)

  test "Enable ignorecase and smartcase":
    block:
      let
        line = ru"editor Editor"
        ignorecase = true
        smartcase = true
        position = line.searchLine(ru"Editor", ignorecase, smartcase)

      check(position == 7)

    block:
      let
        line = ru"editor Editor"
        ignorecase = true
        smartcase = true
        position = line.searchLine(ru"editor", ignorecase, smartcase)

      check(position == 0)

  test "Disable ignorecase":
    let
      line = ru"Editor"
      ignorecase = false
      smartcase = false
      position = line.searchLine(ru"editor", ignorecase, smartcase)

    check(position == -1)

suite "search.nim: searchLineReversely":
  test "searchLineReversely":
    let
      line = ru"abc efg hijkl"
      ignorecase = true
      smartcase = true
      position = line.searchLineReversely(ru"ijk", ignorecase, smartcase)

    check(position == 9)

  test "searchLineReversely 2":
      let
        line = ru"abc efg hijkl"
        keyword = ru"xyz"
        ignorecase = true
        smartcase = true
        position = line.searchLineReversely(keyword, ignorecase, smartcase)

      check(position == -1)

suite "search.nim: searchBuffer":
  test "searchBuffer":
    var status = initEditorStatus()
    status.addNewBuffer

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"i j"
      ignorecase = true
      smartcase = true
      searchResult = currentBufStatus.searchBuffer(
        currentMainWindowNode, keyword, ignorecase, smartcase)

    check(searchResult.line == 1)
    check(searchResult.column == 2)

  test "searchBuffer 2":
    var status = initEditorStatus()
    status.addNewBuffer

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"xyz"
      ignorecase = true
      smartcase = true
      searchResult = currentBufStatus.searchBuffer(
        currentMainWindowNode, keyword, ignorecase, smartcase)

    check(searchResult.line == -1)
    check(searchResult.column == -1)

suite "search.nim: searchBufferReversely":
  test "searchBufferReversely":
    var status = initEditorStatus()
    status.addNewBuffer

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"i j"
      ignorecase = true
      smartcase = true
      searchResult = currentBufStatus.searchBufferReversely(
        currentMainWindowNode,
        keyword,
        ignorecase,
        smartcase)

    check(searchResult.line == 1)
    check(searchResult.column == 2)

  test "searchBufferReversely 2":
    var status = initEditorStatus()
    status.addNewBuffer

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"xyz"
      ignorecase = true
      smartcase = true
      searchResult = currentBufStatus.searchBufferReversely(
        currentMainWindowNode,
        keyword,
        ignorecase,
        smartcase)

    check(searchResult.line == -1)
    check(searchResult.column == -1)

suite "search.nim: searchAllOccurrence":
  test "searchAllOccurrence":
    var status = initEditorStatus()
    status.addNewBuffer

    let
      line1 = ru"abc def"
      line2 = ru"ghi abc"
      line3 = ru"abc pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"abc"
      buffer = status.bufStatus[0].buffer
      ignorecase = true
      smartcase = true
      searchResult = buffer.searchAllOccurrence(keyword, ignorecase, smartcase)

    check(searchResult.len == 3)

    check(searchResult[0].line == 0)
    check(searchResult[0].column == 0)

    check(searchResult[1].line == 1)
    check(searchResult[1].column == 4)

    check(searchResult[2].line == 2)
    check(searchResult[2].column == 0)

  test "searchAllOccurrence 2":
    var status = initEditorStatus()
    status.addNewBuffer

    let
      line1 = ru"abc def"
      line2 = ru"ghi abc"
      line3 = ru"abc pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let
      keyword = ru"xyz"
      buffer = status.bufStatus[0].buffer
      ignorecase = true
      smartcase = true
      searchResult = buffer.searchAllOccurrence(keyword, ignorecase, smartcase)

    check(searchResult.len == 0)

suite "search.nim: jumpToSearchForwardResults":
  test "jumpToSearchForwardResults":
    var status = initEditorStatus()
    status.addNewBuffer

    currentMainWindowNode.currentColumn = 1

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno jkl"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let keyword = ru"jkl"
    currentBufStatus.jumpToSearchForwardResults(
      currentMainWindowNode,
      keyword,
      status.settings.ignorecase,
      status.settings.smartcase)

    check(currentMainWindowNode.currentLine == 1)
    check(currentMainWindowNode.currentColumn == 4)

  test "jumpToSearchForwardResults 2":
    var status = initEditorStatus()
    status.addNewBuffer

    currentMainWindowNode.currentColumn = 1

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let keyword = ru"xyz"
    currentBufStatus.jumpToSearchForwardResults(
      currentMainWindowNode,
      keyword,
      status.settings.ignorecase,
      status.settings.smartcase)

    check(currentMainWindowNode.currentLine == 0)
    check(currentMainWindowNode.currentColumn == 1)

suite "search.nim: jumpToSearchBackwordResults":
  test "jumpToSearchBackwordResults":
    var status = initEditorStatus()
    status.addNewBuffer

    currentMainWindowNode.currentLine = 1

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno abc"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let keyword = ru"abc"
    currentBufStatus.jumpToSearchBackwordResults(
      currentMainWindowNode,
      keyword,
      status.settings.ignorecase,
      status.settings.smartcase)

    check(currentMainWindowNode.currentLine == 0)
    check(currentMainWindowNode.currentColumn == 0)

  test "jumpToSearchBackwordResults 2":
    var status = initEditorStatus()
    status.addNewBuffer

    currentMainWindowNode.currentColumn = 1

    let
      line1 = ru"abc def"
      line2 = ru"ghi jkl"
      line3 = ru"mno pqr"
    status.bufStatus[0].buffer = initGapBuffer(@[line1, line2, line3])

    let keyword = ru"xyz"
    currentBufStatus.jumpToSearchBackwordResults(
      currentMainWindowNode,
      keyword,
      status.settings.ignorecase,
      status.settings.smartcase)

    check(currentMainWindowNode.currentLine == 0)
    check(currentMainWindowNode.currentColumn == 1)
