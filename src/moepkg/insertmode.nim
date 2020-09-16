import terminal, times, sugar, critbits, sequtils, options, strformat
import ui, editorstatus, gapbuffer, unicodeext, undoredostack, window,
       movement, editor, bufferstatus, generalautocomplete, color, cursor, suggestionwindow

template currentBufStatus: var BufferStatus =
  mixin status
  status.bufStatus[status.bufferIndexInCurrentWindow]

template currentMainWindow: var WindowNode =
  mixin status
  status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

proc isInsertMode(status: EditorStatus): bool =
  let
    workSpaceIndex = status.currentWorkSpaceIndex
    bufferIndex =
      status.workspace[workSpaceIndex].currentMainWindowNode.bufferIndex
    mode = status.bufStatus[bufferIndex].mode
  return mode == Mode.insert

proc insertMode*(status: var EditorStatus) =
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.insertModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  var suggestionWindow = none(SuggestionWindow)

  while status.isInsertMode:
    status.update

    if suggestionWindow.isSome:
      let (y, x) = suggestionWindow.get.calcSuggestionWindowPosition(currentMainWindow)
      suggestionWindow.get.writeSuggestionWindow(y, x)

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindow.window)

    status.lastOperatingTime = now()

    var windowNode = currentMainWindow

    currentBufStatus.buffer.beginNewSuitIfNeeded
    currentBufStatus.tryRecordCurrentPosition(windowNode)
   
    if suggestionWindow.isSome:
      if canHandleInSuggestionWindow(key):
        suggestionWindow.get.handleKeyInSuggestionWindow(currentBufStatus, currentMainWindow, key)
        continue
      else:
        if suggestionWindow.get.isLineChanged:
          currentBufStatus.buffer[currentMainWindow.currentLine] = suggestionWindow.get.newLine
        suggestionWindow.get.close
        suggestionWindow = none(SuggestionWindow)

    let
      prevLine = currentBufStatus.buffer[currentMainWindow.currentLine]
      prevLineNumber = currentMainWindow.currentLine
    
    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      if windowNode.currentColumn > 0: dec(windowNode.currentColumn)
      windowNode.expandedColumn = windowNode.currentColumn
      status.changeMode(Mode.normal)
    elif isControlU(key):
      currentBufStatus.deleteBeforeCursorToFirstNonBlank(
        currentMainWindow)
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
      currentBufStatus.deleteCurrentCharacter(
        currentMainWindow,
        status.settings.autoDeleteParen)
    elif isBackspaceKey(key) or isControlH(key):
      currentBufStatus.keyBackspace(
        currentMainWindow,
        status.settings.autoDeleteParen,
        status.settings.tabStop)
    elif isEnterKey(key):
      keyEnter(currentBufStatus,
               currentMainWindow,
               status.settings.autoIndent,
               status.settings.tabStop)
    elif isTabKey(key) or isControlI(key):
      insertTab(currentBufStatus,
                currentMainWindow,
                status.settings.tabStop,
                status.settings.autoCloseParen)
    elif isControlE(key):
      currentBufStatus.insertCharacterBelowCursor(
        currentMainWindow
      )
    elif isControlY(key):
      currentBufStatus.insertCharacterAboveCursor(
        currentMainWindow
      )
    elif isControlW(key):
      currentBufStatus.deleteWordBeforeCursor(
        currentMainWindow,
        status.settings.tabStop)
    elif isControlU(key):
      currentBufStatus.deleteCharactersBeforeCursorInCurrentLine(
        currentMainWindow
      )
    elif isControlT(key):
      currentBufStatus.addIndentInCurrentLine(
        currentMainWindow,
        status.settings.view.tabStop
      )
    elif isControlD(key):
      currentBufStatus.deleteIndentInCurrentLine(
        currentMainWindow,
        status.settings.view.tabStop
      )
    else:
      insertCharacter(currentBufStatus,
                      currentMainWindow,
                      status.settings.autoCloseParen, key)

    if status.settings.autocompleteSettings.enable and prevLineNumber == currentMainWindow.currentLine and prevLine != currentBufStatus.buffer[currentMainWindow.currentLine]:
      suggestionWindow = tryOpenSuggestionWindow(currentBufStatus, currentMainWindow)
