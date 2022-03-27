import std/[terminal, times, options, unicode]
import ui, editorstatus, gapbuffer, window, movement, editor, bufferstatus,
       suggestionwindow, settings, autocomplete

proc calcMainWindowY(isEnableTabLine: bool): int =
  if isEnableTabLine: result.inc

proc insertMode*(status: var EditorStatus) =
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.insertModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  var suggestionWindow = none(SuggestionWindow)

  while isInsertMode(currentBufStatus.mode):
    status.update

    if suggestionWindow.isSome:
      let
        mainWindowY = calcMainWindowY(status.settings.tabLine.enable)
        mainWindowHeight = status.settings.getMainWindowHeight(terminalHeight())
        (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(
          currentMainWindowNode,
          mainWindowHeight)
      suggestionWindow.get.writeSuggestionWindow(
        currentMainWindowNode,
        y, x,
        terminalHeight(), terminalWidth(),
        mainWindowY,
        status.settings.statusLine.enable)

    var key = errorKey
    while key == errorKey:
      if not pressCtrlC:
        status.eventLoopTask
        key = getKey(currentMainWindowNode)
      else:
        # Exit insert mode

        pressCtrlC = false

        if currentMainWindowNode.currentColumn > 0:
          dec(currentMainWindowNode.currentColumn)
        currentMainWindowNode.expandedColumn = currentMainWindowNode.currentColumn
        status.changeMode(Mode.normal)

        return

    status.lastOperatingTime = now()

    var windowNode = currentMainWindowNode

    currentBufStatus.buffer.beginNewSuitIfNeeded
    currentBufStatus.tryRecordCurrentPosition(windowNode)

    if suggestionWindow.isSome:
      if canHandleInSuggestionWindow(key):
        suggestionWindow.get.handleKeyInSuggestionWindow(
          currentBufStatus,
          currentMainWindowNode, key)
        continue
      else:
        if suggestionWindow.get.isLineChanged:
          currentBufStatus.buffer[currentMainWindowNode.currentLine] = suggestionWindow.get.newLine
          windowNode.expandedColumn = windowNode.currentColumn

        # Update WordDictionary
        block:
          let selectedWord = suggestionWindow.get.getSelectedWord
          if selectedWord.len > 0:
            status.wordDictionary.incNumOfUsed(selectedWord)

        # Close suggestionWindow
        suggestionWindow.get.close
        suggestionWindow = none(SuggestionWindow)

    let
      prevLine = currentBufStatus.buffer[currentMainWindowNode.currentLine]
      prevLineNumber = currentMainWindowNode.currentLine

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      if windowNode.currentColumn > 0: dec(windowNode.currentColumn)
      windowNode.expandedColumn = windowNode.currentColumn
      status.changeMode(Mode.normal)
    elif isControlU(key):
      currentBufStatus.deleteBeforeCursorToFirstNonBlank(
        currentMainWindowNode)
    elif isLeftKey(key):
      windowNode.keyLeft
    elif isRightkey(key):
      currentBufStatus.keyRight(windowNode)
    elif isUpKey(key):
      currentBufStatus.keyUp(windowNode)
    elif isDownKey(key):
      currentBufStatus.keyDown(windowNode)
    elif isPageUpKey(key):
      pageUp(status)
    elif isPageDownKey(key):
      pageDown(status)
    elif isHomeKey(key):
      windowNode.moveToFirstOfLine
    elif isEndKey(key):
      currentBufStatus.moveToLastOfLine(windowNode)
    elif isDcKey(key):
      currentBufStatus.deleteCharacter(
        windowNode.currentLine,
        windowNode.currentColumn,
        status.settings.autoDeleteParen)
    elif isBackspaceKey(key) or isControlH(key):
      currentBufStatus.keyBackspace(
        currentMainWindowNode,
        status.settings.autoDeleteParen,
        status.settings.tabStop)
    elif isEnterKey(key):
      keyEnter(currentBufStatus,
               currentMainWindowNode,
               status.settings.autoIndent,
               status.settings.tabStop)
    elif isTabKey(key) or isControlI(key):
      insertTab(currentBufStatus,
                currentMainWindowNode,
                status.settings.tabStop,
                status.settings.autoCloseParen)
    elif isControlE(key):
      currentBufStatus.insertCharacterBelowCursor(
        currentMainWindowNode)
    elif isControlY(key):
      currentBufStatus.insertCharacterAboveCursor(
        currentMainWindowNode)
    elif isControlW(key):
      const loop = 1
      currentBufStatus.deleteWordBeforeCursor(
        currentMainWindowNode,
        status.registers,
        loop,
        status.settings)
    elif isControlU(key):
      currentBufStatus.deleteCharactersBeforeCursorInCurrentLine(
        currentMainWindowNode)
    elif isControlT(key):
      currentBufStatus.addIndentInCurrentLine(
        currentMainWindowNode,
        status.settings.view.tabStop)
    elif isControlD(key):
      currentBufStatus.deleteIndentInCurrentLine(
        currentMainWindowNode,
        status.settings.view.tabStop)
    else:
      insertCharacter(currentBufStatus,
                      currentMainWindowNode,
                      status.settings.autoCloseParen, key)

    if status.settings.autocompleteSettings.enable and
       prevLineNumber == currentMainWindowNode.currentLine and
       prevLine != currentBufStatus.buffer[currentMainWindowNode.currentLine]:

      let currentBufferIndex =currentMainWindowNode.bufferIndex
      suggestionWindow = tryOpenSuggestionWindow(
        status.wordDictionary,
        status.bufStatus,
        currentBufferIndex,
        mainWindowNode,
        currentMainWindowNode)
