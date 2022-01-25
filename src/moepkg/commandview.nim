import std/[terminal]
import editorstatus, unicodeext, commandviewutils, ui, color, commandline

proc suggestCommandLine(status: var Editorstatus,
                        exStatus: var ExModeViewStatus,
                        key: var Rune) =

  let
    suggestType = getSuggestType(exStatus.buffer)
    suggestlist = exStatus.getSuggestList(suggestType)

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    x = 0
    y = terminalHeight() - 1

  let command = if exStatus.buffer.len > 0:
                  (splitWhitespace(exStatus.buffer))[0]
                else: ru""

  if isSuggestTypeFilePath(suggestType):
    x = calcXWhenSuggestPath(exStatus.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    x = command.len + 1

  var popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  template updateExModeViewStatus() =
    if isSuggestTypeFilePath(suggestType):
      exStatus.buffer = command & ru" "
      exStatus.currentPosition = command.len + exStatus.prompt.len
      exStatus.cursorX = exStatus.currentPosition
    else:
      exStatus.buffer = ru""
      exStatus.currentPosition = 0
      exStatus.cursorX = 0

  # TODO: I don't know why yet,
  #       but there is a bug which is related to scrolling of the pup-up window.

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    updateExModeViewStatus()

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    if status.settings.popUpWindowInExmode:
      let
        currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1
        displayBuffer = initDisplayBuffer(suggestlist, suggestType)
      # Pop up window size
      var (h, w) = displayBuffer.calcPopUpWindowSize

      popUpWindow.writePopUpWindow(h, w, y, x,
                                   terminalHeight(), terminalWidth(),
                                   currentLine,
                                   displayBuffer)

    if isSuggestTypeExCommandOption(suggestType):
      exStatus.insertCommandBuffer(command & ru' ')

    exStatus.insertCommandBuffer(suggestlist[suggestIndex])
    exStatus.cursorX.inc

    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    key = errorKey
    while key == errorKey:
      key = status.commandLine.getKey

    exStatus.cursorX = exStatus.currentPosition + 1

  status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)
  if status.settings.popUpWindowInExmode: status.deletePopUpWindow

proc getKeyOnceAndWriteCommandView*(
  status: var Editorstatus,
  prompt: string,
  buffer: seq[Rune],
  isSuggest, isSearch : bool): (seq[Rune], bool, bool) =

  var
    exStatus = initExModeViewStatus(prompt)
    exitSearch = false
    cancelSearch = false
    searchHistoryIndex = status.searchHistory.high
    commandHistoryIndex = status.exCommandHistory.high
  for rune in buffer: exStatus.insertCommandBuffer(rune)

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

  template setNextCommandHistory() =
    if commandHistoryIndex < status.exCommandHistory.high:
      exStatus.clearCommandBuffer
      inc commandHistoryIndex
      exStatus.insertCommandBuffer(status.exCommandHistory[commandHistoryIndex])

  template setPrevCommandHistory() =
    if commandHistoryIndex > 0:
      exStatus.clearCommandBuffer
      dec commandHistoryIndex
      exStatus.insertCommandBuffer(status.exCommandHistory[commandHistoryIndex])

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = errorKey
    while key == errorKey:
      if not pressCtrlC:
        key = status.commandLine.getKey
      else:
        # Exit command line mode
        pressCtrlC = false

        status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)
        exitSearch = true

        return (exStatus.buffer, exitSearch, cancelSearch)

    # Suggestion mode
    if isTabKey(key) or isShiftTab(key):
      status.suggestCommandLine(exStatus, key)
      if status.settings.popUpWindowInExmode and isEnterKey(key):
        status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)

    if isEnterKey(key):
      exitSearch = true
      break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key):
      status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key):
      exStatus.moveRight
      if status.settings.popUpWindowInExmode:
        status.deletePopUpWindow
        status.update
    elif isUpKey(key):
      if isSearch: setPrevSearchHistory()
      else: setPrevCommandHistory()
    elif isDownKey(key):
      if isSearch: setNextSearchHistory()
      else: setNextCommandHistory()
    elif isHomeKey(key):
      exStatus.moveTop
    elif isEndKey(key):
      exStatus.moveEnd
    elif isBackspaceKey(key):
      exStatus.deleteCommandBuffer
      break
    elif isDcKey(key):
      exStatus.deleteCommandBufferCurrentPosition
      break
    else:
      exStatus.insertCommandBuffer(key)
      break

  status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)
  return (exStatus.buffer, exitSearch, cancelSearch)

proc getCommand*(status: var EditorStatus, prompt: string): seq[seq[Rune]] =
  var exStatus = initExModeViewStatus(prompt)
  status.resize(terminalHeight(), terminalWidth())

  while true:
    status.commandLine.writeExModeView(exStatus, EditorColorPair.commandBar)

    var key = status.commandLine.getKey

    # Suggestion mode
    if isTabKey(key) or isShiftTab(key):
      status.suggestCommandLine(exStatus, key)
      if status.settings.popUpWindowInExmode and isEnterKey(key):
          status.commandLine.window.moveCursor(exStatus.cursorY, exStatus.cursorX)
          key = status.commandLine.getKey

    if isEnterKey(key): break
    elif isEscKey(key):
      status.commandLine.erase
      return @[ru""]
    elif isResizeKey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.update
    elif isLeftKey(key): status.commandLine.window.moveLeft(exStatus)
    elif isRightkey(key): moveRight(exStatus)
    elif isHomeKey(key): moveTop(exStatus)
    elif isEndKey(key): moveEnd(exStatus)
    elif isBackspaceKey(key): deleteCommandBuffer(exStatus)
    elif isDcKey(key): deleteCommandBufferCurrentPosition(exStatus)
    else: insertCommandBuffer(exStatus, key)

  return splitCommand($exStatus.buffer)
