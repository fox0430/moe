import system, terminal, strutils
import editorstatus, gapbuffer, commandview, movement, commandline, unicodetext

type
  SearchResult* = tuple[line: int, column: int]

type Direction = enum
  forward = 0
  backward = 1

proc compare(rune, sub: seq[Rune], ignorecase, smartcase: bool): bool =
  proc isContainUpper(sub: seq[Rune]): bool =
    for r in sub:
      let ch = ($r)[0]
      if isUpperAscii(ch): return true

  if ignorecase and not smartcase:
    if cmpIgnoreCase($rune, $sub) == 0: return true
  elif smartcase and ignorecase:
    if isContainUpper(sub):
      return rune == sub
    else:
      if cmpIgnoreCase($rune, $sub) == 0: return true
  else:
    return rune == sub

proc searchLine(line: seq[Rune],
                keyword: seq[Rune],
                ignorecase, smartcase: bool): int =

  result = -1
  for startPostion in 0 .. (line.len - keyword.len):
    let
      endPosition = startPostion + keyword.len
      rune = line[startPostion ..< endPosition]

    if compare(rune, keyword, ignorecase, smartcase): return startPostion

proc searchLineReversely(line: seq[Rune],
                         keyword: seq[Rune],
                         ignorecase, smartcase: bool): int =

  result = -1
  for startPostion in countdown((line.len - keyword.len), 0):
    let
      endPosition = startPostion + keyword.len
      rune = line[startPostion ..< endPosition]

    if compare(rune, keyword, ignorecase, smartcase): return startPostion

proc searchBuffer*(status: var EditorStatus,
                   keyword: seq[Rune],
                   ignorecase, smartcase: bool): SearchResult =

  result = (-1, -1)
  let
    startLine = currentMainWindowNode.currentLine
    buffer = currentBufStatus.buffer
  for i in 0 ..< buffer.len:
    let
      lineNumber = (startLine + i) mod buffer.len
      begin = if lineNumber == startLine and
                 i == 0: currentMainWindowNode.currentColumn
              else: 0
      `end` = buffer[lineNumber].len
      line = buffer[lineNumber]
      position = searchLine(line[begin ..< `end`],
                            keyword,
                            ignorecase,
                            smartcase)

    if position > -1: return (lineNumber, begin + position)

proc searchBufferReversely*(status: var EditorStatus,
                            keyword: seq[Rune],
                            ignorecase, smartcase: bool): SearchResult =

  result = (-1, -1)
  let
    startLine = currentMainWindowNode.currentLine
    buffer = currentBufStatus.buffer
  for i in 0 ..< currentBufStatus.buffer.len + 1:
    var lineNumber = (startLine - i) mod buffer.len
    if lineNumber < 0: lineNumber = buffer.len - i
    let
      endPosition = if lineNumber == startLine and i == 0:
                      currentMainWindowNode.currentColumn
                    else:
                      buffer[lineNumber].len
      position = searchLineReversely(buffer[lineNumber][0 ..< endPosition],
                                     keyword,
                                     ignorecase,
                                     smartcase)

    if position > -1: return (lineNumber, position)

proc searchAllOccurrence*(buffer: GapBuffer[seq[Rune]],
                          keyword: seq[Rune],
                          ignorecase, smartcase: bool): seq[SearchResult] =

  if keyword.len < 1: return

  for lineNumber in 0 ..< buffer.len:
    var begin = 0
    while begin < buffer[lineNumber].len:
      let
        `end` = buffer[lineNumber].len
        line = buffer[lineNumber]
        position = searchLine(line[begin ..< `end`],
                              keyword,
                              ignorecase,
                              smartcase)
      if position == -1: break
      result.add((lineNumber, begin + position))
      begin += position + keyword.len

proc jumpToSearchForwardResults*(status: var Editorstatus, keyword: seq[Rune]) =
  let
    ignorecase = status.settings.ignorecase
    smartcase = status.settings.smartcase
    searchResult = status.searchBuffer(keyword, ignorecase, smartcase)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column:
      currentBufStatus.keyRight(currentMainWindowNode)

proc jumpToSearchBackwordResults(status: var Editorstatus, keyword: seq[Rune]) =
  let
    ignorecase = status.settings.ignorecase
    smartcase = status.settings.smartcase
    searchResult = status.searchBufferReversely(keyword, ignorecase, smartcase)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column:
      currentBufStatus.keyRight(currentMainWindowNode)

proc searchFirstOccurrence(status: var EditorStatus) =
  var
    exitSearch = false
    cancelSearch = false
    keyword = ru""

  status.searchHistory.add(ru"")

  const
    prompt = "/"
    isSuggest = false
    isSearch = true

  while exitSearch == false:
    let returnWord = status.getKeyOnceAndWriteCommandView(
      prompt,
      keyword,
      isSuggest,
      isSearch)

    keyword = returnWord[0]
    exitSearch = returnWord[1]
    cancelSearch = returnWord[2]
    if keyword.len > 0:
        status.searchHistory[status.searchHistory.high] = keyword

    if exitSearch or cancelSearch: break

  if cancelSearch:
    status.searchHistory.delete(status.searchHistory.high)

    currentBufStatus.isSearchHighlight = false

  else:
    if keyword.len > 0:
      currentBufStatus.isSearchHighlight = true
      status.updateHighlight(currentMainWindowNode)

proc incrementalSearch(status: var Editorstatus, direction: Direction) =
  let prompt = if direction == Direction.forward: "/" else: "?"
  var
    keyword = ru""
    exitSearch = false
    cancelSearch = false
  status.searchHistory.add(ru"")

  # For jumpToSearchBackwordResults
  let
    currentLine = currentMainWindowNode.currentLine
    currentColumn = currentMainWindowNode.currentColumn

  while exitSearch == false:
    const
      isSuggest = false
      isSearch = true
    let returnWord = status.getKeyOnceAndWriteCommandView(
      prompt,
      keyword,
      isSuggest,
      isSearch)

    keyword = returnWord[0]
    exitSearch = returnWord[1]
    cancelSearch = returnWord[2]
    if keyword.len > 0: status.searchHistory[^1] = keyword

    if exitSearch or cancelSearch: break

    if keyword.len > 0:
      currentBufStatus.isSearchHighlight = true

      if direction == Direction.forward:
        status.jumpToSearchForwardResults(keyword)
      else:
        currentMainWindowNode.currentLine = currentLine
        currentMainWindowNode.currentColumn = currentColumn
        status.jumpToSearchBackwordResults(keyword)
    else:
      currentBufStatus.isSearchHighlight = false

    status.updateHighlight(currentMainWindowNode)
    status.resize(terminalHeight(), terminalWidth())
    status.update

  if cancelSearch:
    status.searchHistory.delete(status.searchHistory.high)

    currentBufStatus.isSearchHighlight = false
    status.updateHighlight(currentMainWindowNode)

    status.commandLine.erase

proc searchFordwards*(status: var EditorStatus) =
  if status.settings.incrementalSearch:
      status.incrementalSearch(Direction.forward)
  else:
      status.searchFirstOccurrence

proc searchBackwards*(status: var EditorStatus) =
  if status.settings.incrementalSearch:
      status.incrementalSearch(Direction.backward)
  else:
      status.searchFirstOccurrence
