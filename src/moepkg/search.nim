import unicodeext, system, terminal, strutils
import editorstatus, gapbuffer, commandview, movement, commandline

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
  let workSpaceIndex = status.currentWorkSpaceIndex
  var windowNode = status.workSpace[workSpaceIndex].currentMainWindowNode
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    startLine = windowNode.currentLine
  for i in 0 ..< status.bufStatus[currentBufferIndex].buffer.len:
    let
      buffer = status.bufStatus[currentBufferIndex].buffer
      lineNumber = (startLine + i) mod buffer.len
      begin = if lineNumber == startLine and i == 0: windowNode.currentColumn
              else: 0
      `end` = buffer[lineNumber].len
      line = buffer[lineNumber]
      position = searchLine(line[begin ..< `end`], keyword, ignorecase, smartcase)
    if position > -1:  return (lineNumber, begin + position)

proc searchBufferReversely*(status: var EditorStatus,
                            keyword: seq[Rune],
                            ignorecase, smartcase: bool): SearchResult =

  result = (-1, -1)
  let workSpaceIndex = status.currentWorkSpaceIndex
  var windowNode = status.workSpace[workSpaceIndex].currentMainWindowNode
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    startLine = windowNode.currentLine
  for i in 0 ..< status.bufStatus[currentBufferIndex].buffer.len + 1:
    let buffer = status.bufStatus[currentBufferIndex].buffer
    var lineNumber = (startLine - i) mod buffer.len
    if lineNumber < 0: lineNumber = buffer.len - i
    let
      endPosition = if lineNumber == startLine and i == 0:
                      windowNode.currentColumn
                    else:
                      buffer[lineNumber].len
      position = searchLineReversely(buffer[lineNumber][0 ..< endPosition],
                                     keyword,
                                     ignorecase,
                                     smartcase)

    if position > -1:  return (lineNumber, position)

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
        position = searchLine(line[begin ..< `end`], keyword, ignorecase, smartcase)
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
    let currentBufferIndex = status.bufferIndexInCurrentWindow
    for column in 0 ..< searchResult.column:
      status.bufStatus[currentBufferIndex].keyRight(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc jumpToSearchBackwordResults(status: var Editorstatus, keyword: seq[Rune]) =
  let
    ignorecase = status.settings.ignorecase
    smartcase = status.settings.smartcase
    searchResult = status.searchBufferReversely(keyword, ignorecase, smartcase)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    let currentBufferIndex = status.bufferIndexInCurrentWindow
    for column in 0 ..< searchResult.column:
      status.bufStatus[currentBufferIndex].keyRight(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

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

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.bufStatus[currentBufferIndex].isSearchHighlight = false

  else:
    if keyword.len > 0:
      let bufferIndex = status.bufferIndexInCurrentWindow
      status.bufStatus[bufferIndex].isSearchHighlight = true
      status.updateHighlight(
        status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc incrementalSearch(status: var Editorstatus, direction: Direction) =
  let prompt = if direction == Direction.forward: "/" else: "?"
  var
    keyword = ru""
    exitSearch = false
    cancelSearch = false
  status.searchHistory.add(ru"")

  # For jumpToSearchBackwordResults
  let
    node = status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode
    currentLine = node.currentLine
    currentColumn = node.currentColumn

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
    if keyword.len > 0: status.searchHistory[status.searchHistory.high] = keyword

    if exitSearch or cancelSearch: break

    let workSpaceIndex = status.currentWorkSpaceIndex
    var windowNode = status.workSpace[workSpaceIndex].currentMainWindowNode
    let bufferIndex = windowNode.bufferIndex
    if keyword.len > 0:
      status.bufStatus[bufferIndex].isSearchHighlight = true

      if direction == Direction.forward: status.jumpToSearchForwardResults(keyword)
      else:
        windowNode.currentLine = currentLine
        windowNode.currentColumn = currentColumn
        status.jumpToSearchBackwordResults(keyword)
    else: status.bufStatus[bufferIndex].isSearchHighlight = false

    status.updateHighlight(windowNode)
    status.resize(terminalHeight(), terminalWidth())
    status.update

  if cancelSearch:
    status.searchHistory.delete(status.searchHistory.high)

    let
      currentBufferIndex = status.bufferIndexInCurrentWindow
      workSpaceIndex = status.currentWorkSpaceIndex
    status.bufStatus[currentBufferIndex].isSearchHighlight = false
    var windowNode = status.workspace[workSpaceIndex].currentMainWindowNode
    status.updateHighlight(windowNode)

    status.commandLine.erase

proc searchFordwards*(status: var EditorStatus) =
  if status.settings.incrementalSearch:
      status.incrementalSearch(Direction.forward)
  else:
      searchFirstOccurrence(status)

proc searchBackwards*(status: var EditorStatus) =
  if status.settings.incrementalSearch:
      status.incrementalSearch(Direction.backward)
  else:
      searchFirstOccurrence(status)
