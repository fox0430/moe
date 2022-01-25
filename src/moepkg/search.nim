import std/terminal
import editorstatus, searchutils, unicodeext, commandview, color, ui,
       commandline, commandviewutils

# Search text in buffer
proc getKeyword*(status: var EditorStatus,
                 prompt: string,
                 isSearch: bool): (seq[Rune], bool) =

  var
    exStatus = initExModeViewStatus(prompt)
    cancelSearch = false
    searchHistoryIndex = status.searchHistory.high

  template setPrevSearchHistory() =
    if searchHistoryIndex > 0:
      exStatus.clearCommandBuffer
      dec searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextSearchHistory() =
    if searchHistoryIndex < status.searchHistory.high:
      exStatus.clearCommandBuffer
      inc searchHistoryIndex
      exStatus.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = status.commandLine.getKey

    if isEnterKey(key): break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key): status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key): exStatus.moveRight
    elif isUpKey(key) and isSearch: setPrevSearchHistory()
    elif isDownKey(key) and isSearch: setNextSearchHistory()
    elif isHomeKey(key): exStatus.moveTop
    elif isEndKey(key): exStatus.moveEnd
    elif isBackspaceKey(key): exStatus.deleteCommandBuffer
    elif isDcKey(key): exStatus.deleteCommandBufferCurrentPosition
    else: exStatus.insertCommandBuffer(key)

  return (exStatus.buffer, cancelSearch)

proc searchFirstOccurrence(status: var EditorStatus) =
  var
    exitSearch = false
    cancelSearch = false
    keyword = ru""

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

    if exitSearch or cancelSearch: break

  if cancelSearch:
    status.isSearchHighlight = false

  else:
    if keyword.len > 0:
      status.isSearchHighlight = true

      # Save keyword in search history
      status.searchHistory.addSearchHistory(keyword)

      var highlight = currentMainWindowNode.highlight
      highlight.updateHighlight(
        currentBufStatus,
        currentMainWindowNode,
        status.isSearchHighlight,
        status.searchHistory,
        status.settings)

proc incrementalSearch(status: var Editorstatus, direction: Direction) =
  let prompt = if direction == Direction.forward: "/" else: "?"

  status.searchHistory.add ru""

  var
    exitSearch = false
    cancelSearch = false

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
      status.searchHistory[^1],
      isSuggest,
      isSearch)

    status.searchHistory[^1] = returnWord[0]
    exitSearch = returnWord[1]
    cancelSearch = returnWord[2]

    if exitSearch or cancelSearch: break

    if status.searchHistory[^1].len > 0:
      let keyword = status.searchHistory[^1]
      status.isSearchHighlight = true

      if direction == Direction.forward:
        currentBufStatus.jumpToSearchForwardResults(
          currentMainWindowNode,
          keyword,
          status.settings.ignorecase,
          status.settings.smartcase)
      else:
        currentMainWindowNode.currentLine = currentLine
        currentMainWindowNode.currentColumn = currentColumn
        currentBufStatus.jumpToSearchBackwordResults(
          currentMainWindowNode,
          keyword,
          status.settings.ignorecase,
          status.settings.smartcase)
    else:
      status.isSearchHighlight = false

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    status.resize(terminalHeight(), terminalWidth())
    status.update

  if cancelSearch:
    status.searchHistory.delete(status.searchHistory.high)

    status.isSearchHighlight = false

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

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
