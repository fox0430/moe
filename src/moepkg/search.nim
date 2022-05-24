import std/[terminal, os, times]
import editorstatus, searchutils, unicodeext, color, ui, commandviewutils

# Search text in buffer
proc getKeyword*(status: var EditorStatus,
                 prompt: string,
                 isSearch: bool): (seq[Rune], bool) =

  var
    commandLine = initCommandLine(prompt)
    cancelSearch = false
    searchHistoryIndex = status.searchHistory.high

  template setPrevSearchHistory() =
    if searchHistoryIndex > 0:
      commandLine.clearCommandBuffer
      dec searchHistoryIndex
      commandLine.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextSearchHistory() =
    if searchHistoryIndex < status.searchHistory.high:
      commandLine.clearCommandBuffer
      inc searchHistoryIndex
      commandLine.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  while true:
    status.commandLine.writeCommandLine(ColorThemeTable[currentColorTheme].EditorColorPair.commandBar)

    var key = NONE_KEY
    while key == NONE_KEY:
      if isResizedWindow:
        status.resize(terminalHeight(), terminalWidth())
        status.update

      key = getKey()

      status.lastOperatingTime = now()
      sleep 20

    if isEnterKey(key): break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isLeftKey(key):
      discard
      status.commandLine.moveLeft
    elif isRightkey(key):
      commandLine.moveRight
    elif isUpKey(key) and isSearch: setPrevSearchHistory()
    elif isDownKey(key) and isSearch: setNextSearchHistory()
    elif isHomeKey(key): commandLine.moveTop
    elif isEndKey(key): commandLine.moveEnd
    elif isBackspaceKey(key): commandLine.deleteCommandBuffer
    elif isDeleteKey(key): commandLine.deleteCommandBufferCurrentPosition
    else: commandLine.insertCommandBuffer(key)

  return (commandLine.buffer, cancelSearch)

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

    status.commandLine.clear

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
