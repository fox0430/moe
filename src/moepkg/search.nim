import unicodeext, system, terminal
import ui, editorstatus, gapbuffer, commandview, movement

type
  SearchResult* = tuple[line: int, column: int]

type Direction = enum
  forward = 0
  backward = 1

proc searchLine(line: seq[Rune], keyword: seq[Rune]): int =
  result = -1
  for startPostion in 0 .. (line.len - keyword.len):
    let endPosition = startPostion + keyword.len
    if line[startPostion ..< endPosition] == keyword:
      return startPostion

proc searchLineReversely(line: seq[Rune], keyword: seq[Rune]): int =
  result = -1
  for startPostion in countdown((line.len - keyword.len), 0):
    let endPosition = startPostion + keyword.len
    if line[startPostion ..< endPosition] == keyword:
      return startPostion

proc searchBuffer*(status: var EditorStatus, keyword: seq[Rune]): SearchResult =
  result = (-1, -1)
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    startLine = windowNode.currentLine
  for i in 0 ..< status.bufStatus[currentBufferIndex].buffer.len:
    let
      line = (startLine + i) mod status.bufStatus[currentBufferIndex].buffer.len
      begin = if line == startLine and i == 0: windowNode.currentColumn else: 0
      position = searchLine(status.bufStatus[currentBufferIndex].buffer[line][begin ..< status.bufStatus[currentBufferIndex].buffer[line].len],
                            keyword)
    if position > -1:  return (line, begin + position)

proc searchBufferReversely*(status: var EditorStatus, keyword: seq[Rune]): SearchResult =
  result = (-1, -1)
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    startLine = windowNode.currentLine
  for i in 0 ..< status.bufStatus[currentBufferIndex].buffer.len + 1:
    var line = (startLine - i) mod status.bufStatus[currentBufferIndex].buffer.len
    if line < 0: line = status.bufStatus[currentBufferIndex].buffer.len - i
    let
      endPosition = if line == startLine and
                       i == 0: windowNode.currentColumn
                    else: status.bufStatus[currentBufferIndex].buffer[line].len 
      position = searchLineReversely(status.bufStatus[currentBufferIndex].buffer[line][0 ..< endPosition], keyword)
    if position > -1:  return (line, position)

proc searchAllOccurrence*(buffer: GapBuffer[seq[Rune]], keyword: seq[Rune]): seq[SearchResult] =
  for line in 0 ..< buffer.len:
    var begin = 0
    while begin < buffer[line].len:
      let position = searchLine(buffer[line][begin ..< buffer[line].len], keyword)
      if position == -1: break
      result.add((line, begin + position))
      begin += position + keyword.len

proc jumpToSearchForwardResults(status: var Editorstatus, keyword: seq[Rune]) =
  let searchResult = status.searchBuffer(keyword)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    let currentBufferIndex = status.bufferIndexInCurrentWindow
    for column in 0 ..< searchResult.column:
      status.bufStatus[currentBufferIndex].keyRight(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc jumpToSearchBackwordResults(status: var Editorstatus, keyword: seq[Rune]) =
  let searchResult = status.searchBufferReversely(keyword)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    let currentBufferIndex = status.bufferIndexInCurrentWindow
    for column in 0 ..< searchResult.column:
      status.bufStatus[currentBufferIndex].keyRight(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc searchFirstOccurrence(status: var EditorStatus) =
  const prompt = "/"
  let
    returnWord = getKeyword(status, prompt)
    keyword = returnWord[0]
    isCancel = returnWord[1]

  if keyword.len == 0 or isCancel:
    status.commandWindow.erase
    status.commandWindow.refresh
    return

  status.searchHistory.add(keyword)
  let bufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[bufferIndex].isHighlight = true
  status.jumpToSearchForwardResults(keyword)

  status.updateHighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc realtimeSearch(status: var Editorstatus, direction: Direction) =
  let prompt = if direction == Direction.forward: "/" else: "?"
  var
    keyword = ru""
    exitSearch = false
    cancelSearch = false
  status.searchHistory.add(ru"")

  # For jumpToSearchBackwordResults
  let
    currentLine = status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.currentLine
    currentColumn = status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.currentColumn

  while exitSearch == false:
    const
      isSuggest = false
      isSearch = true
    let returnWord = status.getKeyOnceAndWriteCommandView(prompt, keyword, isSuggest, isSearch)

    keyword = returnWord[0]
    exitSearch = returnWord[1]
    cancelSearch = returnWord[2]
    if keyword.len > 0: status.searchHistory[status.searchHistory.high] = keyword

    if exitSearch or cancelSearch: break

    let bufferIndex = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
    if keyword.len > 0:
      status.bufStatus[bufferIndex].isHighlight = true

      if direction == Direction.forward: status.jumpToSearchForwardResults(keyword)
      else:
        status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.currentLine = currentLine
        status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.currentColumn = currentColumn
        status.jumpToSearchBackwordResults(keyword)
    else: status.bufStatus[bufferIndex].isHighlight = false

    status.updateHighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.resize(terminalHeight(), terminalWidth())
    status.update

  if cancelSearch:
    status.searchHistory.delete(status.searchHistory.high)

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    status.bufStatus[currentBufferIndex].isHighlight = false
    status.updateHighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)

    status.commandWindow.erase

proc searchFordwards*(status: var EditorStatus) =
  if status.settings.realtimeSearch: status.realtimeSearch(Direction.forward)
  else: searchFirstOccurrence(status)

proc searchBackwards*(status: var EditorStatus) =
  if status.settings.realtimeSearch: status.realtimeSearch(Direction.backward)
  else: searchFirstOccurrence(status)
