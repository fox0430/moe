import std/[terminal, os, times]
import editorstatus, unicodeext, commandviewutils, ui, color

proc suggestCommandLine(status: var Editorstatus,
                        key: var Rune) =

  let
    suggestType = getSuggestType(status.commandLine.buffer)
    suggestlist = status.commandLine.getSuggestList(suggestType)

  var
    suggestIndex = 0
    # Pop up window initial size/position
    h = 1
    w = 1
    x = 0
    y = terminalHeight() - 1

  let command = if status.commandLine.buffer.len > 0:
                  (splitWhitespace(status.commandLine.buffer))[0]
                else: ru""

  if isSuggestTypeFilePath(suggestType):
    x = calcXWhenSuggestPath(status.commandLine.buffer)
  elif isSuggestTypeExCommandOption(suggestType):
    x = command.len + 1

  # TODO: Enable popUpWindow
  #var popUpWindow = initWindow(h, w, y, x, EditorColorPair.popUpWindow)

  template updateExModeViewStatus() =
    if isSuggestTypeFilePath(suggestType):
      status.commandLine.buffer = command & ru" "
      status.commandLine.currentPosition = command.len + status.commandLine.prompt.len
      status.commandLine.cursorX = status.commandLine.currentPosition
    else:
      status.commandLine.buffer = ru""
      status.commandLine.currentPosition = 0
      status.commandLine.cursorX = 0

  # TODO: I don't know why yet,
  #       but there is a bug which is related to scrolling of the pup-up window.

  while (isTabKey(key) or isShiftTab(key)) and suggestlist.len > 1:
    updateExModeViewStatus()

    if isTabKey(key) and suggestIndex < suggestlist.high: inc(suggestIndex)
    elif isShiftTab(key) and suggestIndex > 0: dec(suggestIndex)
    elif isShiftTab(key) and suggestIndex == 0: suggestIndex = suggestlist.high
    else: suggestIndex = 0

    # TODO: Enable popupwindow
    #if status.settings.popUpWindowInExmode:
    #  let
    #    currentLine = if suggestIndex == 0: -1 else: suggestIndex - 1
    #    displayBuffer = initDisplayBuffer(suggestlist, suggestType)
    #  # Pop up window size
    #  var (h, w) = displayBuffer.calcPopUpWindowSize

    #  popUpWindow.writePopUpWindow(h, w, y, x,
    #                               terminalHeight(), terminalWidth(),
    #                               currentLine,
    #                               displayBuffer)

    if isSuggestTypeExCommandOption(suggestType):
      status.commandLine.insertCommandBuffer(command & ru' ')

    status.commandLine.insertCommandBuffer(suggestlist[suggestIndex])
    status.commandLine.cursorX.inc

    status.commandLine.writeExModeView(EditorColorPair.commandBar)

    key = NONE_KEY
    while key == NONE_KEY:
      key = getKey()

    status.commandLine.cursorX = status.commandLine.currentPosition + 1

  # TODO: Enable cursor
  #status.commandLine.window.moveCursor(commandLine.cursorY, commandLine.cursorX)
  # TODO: Enable popUpWindow
  #if status.settings.popUpWindowInExmode: status.deletePopUpWindow

proc getKeyOnceAndWriteCommandView*(
  status: var Editorstatus,
  prompt: string,
  buffer: seq[Rune],
  isSuggest, isSearch : bool): (seq[Rune], bool, bool) =

  status.commandLine = initExModeViewStatus(prompt)

  var
    exitSearch = false
    cancelSearch = false
    searchHistoryIndex = status.searchHistory.high
    commandHistoryIndex = status.exCommandHistory.high
  for rune in buffer: status.commandLine.insertCommandBuffer(rune)

  template setPrevSearchHistory() =
    if searchHistoryIndex > 0:
      status.commandLine.clearCommandBuffer
      dec searchHistoryIndex
      status.commandLine.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextSearchHistory() =
    if searchHistoryIndex < status.searchHistory.high:
      status.commandLine.clearCommandBuffer
      inc searchHistoryIndex
      status.commandLine.insertCommandBuffer(status.searchHistory[searchHistoryIndex])

  template setNextCommandHistory() =
    if commandHistoryIndex < status.exCommandHistory.high:
      status.commandLine.clearCommandBuffer
      inc commandHistoryIndex
      status.commandLine.insertCommandBuffer(status.exCommandHistory[commandHistoryIndex])

  template setPrevCommandHistory() =
    if commandHistoryIndex > 0:
      status.commandLine.clearCommandBuffer
      dec commandHistoryIndex
      status.commandLine.insertCommandBuffer(status.exCommandHistory[commandHistoryIndex])

  while true:
    var key = NONE_KEY
    while key == NONE_KEY:
      if pressCtrlC:
        # Exit command line mode
        pressCtrlC = false

        exitSearch = true

        return (status.commandLine.buffer, exitSearch, cancelSearch)

      if isResizedWindow:
        status.resize(terminalHeight(), terminalWidth())

      status.update

      key = getKey()

      status.lastOperatingTime = now()
      sleep 100

    # Suggestion mode
    if isTabKey(key) or isShiftTab(key):
      status.suggestCommandLine(key)
      if status.settings.popUpWindowInExmode and isEnterKey(key):
        discard
        # TODO: Enable cursor
        #status.commandLine.window.moveCursor(commandLine.cursorY, commandLine.cursorX)

    if isEnterKey(key):
      exitSearch = true
      break
    elif isEscKey(key):
      cancelSearch = true
      break
    elif isLeftKey(key):
      discard
      # TODO: Enable cursor
      #status.commandLine.window.moveLeft(commandLine.
    elif isRightkey(key):
      discard
      # TODO: Enable cursor
      #commandLine.moveRight
      # TODO: Enable popupwindow
      #if status.settings.popUpWindowInExmode:
      #  status.deletePopUpWindow
      #  status.update
    elif isUpKey(key):
      if isSearch: setPrevSearchHistory()
      else: setPrevCommandHistory()
    elif isDownKey(key):
      if isSearch: setNextSearchHistory()
      else: setNextCommandHistory()
    elif isHomeKey(key):
      status.commandLine.moveTop
    elif isEndKey(key):
      status.commandLine.moveEnd
    elif isBackspaceKey(key):
      status.commandLine.deleteCommandBuffer
      break
    elif isDeleteKey(key):
      status.commandLine.deleteCommandBufferCurrentPosition
      break
    else:
      status.commandLine.insertCommandBuffer(key)
      # TODO: Fix
      status.commandLine.buffer = status.commandLine.buffer
      status.update
      break

  status.commandLine.writeExModeView(EditorColorPair.commandBar)
  return (status.commandLine.buffer, exitSearch, cancelSearch)

proc getCommand*(status: var EditorStatus, prompt: string): seq[seq[Rune]] =
  var commandLine = initExModeViewStatus(prompt)
  status.resize(terminalHeight(), terminalWidth())

  while true:
    status.commandLine.writeExModeView(EditorColorPair.commandBar)

    var key = NONE_KEY
    while key == NONE_KEY:
      if isResizedWindow:
        status.resize(terminalHeight(), terminalWidth())
        status.update

      key = getKey()

      status.lastOperatingTime = now()
      sleep 100

    # Suggestion mode
    if isTabKey(key) or isShiftTab(key):
      status.suggestCommandLine(key)
      if status.settings.popUpWindowInExmode and isEnterKey(key):
        discard
        # TODO: Enable cursor
          #status.commandLine.window.moveCursor(commandLine.cursorY, commandLine.cursorX)
          #key = getKey()

    if isEnterKey(key): break
    elif isEscKey(key):
      status.commandLine.clear
      return @[ru""]
    elif isLeftKey(key):
      discard
      # TODO: Enable cursor
      #status.commandLine.window.moveLeft(commandLine.
    elif isRightkey(key):
      discard
      # TODO: Enable cursor
      #moveRight(commandLine.
    elif isHomeKey(key):
      moveTop(commandLine)
    elif isEndKey(key):
      moveEnd(commandLine)
    elif isBackspaceKey(key):
      deleteCommandBuffer(commandLine)
    elif isDeleteKey(key):
      deleteCommandBufferCurrentPosition(commandLine)
    else:
      insertCommandBuffer(commandLine, key)
      # TODO: Fix
      status.commandLine.buffer = commandLine.buffer
      status.update

  return splitCommand($commandLine.buffer)
