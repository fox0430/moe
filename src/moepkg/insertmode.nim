import terminal, times, sugar, critbits, sequtils, options, strformat
import ui, editorstatus, gapbuffer, unicodeext, undoredostack, window,
       movement, editor, bufferstatus, generalautocomplete, color, cursor

type SuggestionWindow = object
  identifierDictionary: CritBitTree[void]
  inputWord: seq[Rune]
  firstColumn, lastColumn: int
  suggestoins: seq[seq[Rune]]
  popUpWindow: Window
  currentSuggestion: int
  isClosed: bool
  oldLine: seq[Rune]

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

proc getCursorY(windowNode: WindowNode): int =
  windowNode.y + windowNode.cursor.y

proc extractWordInFrontOfCursor(bufStatus: BufferStatus, windowNode: WindowNode): Option[tuple[word: seq[Rune], first, last: int]] =
  if windowNode.currentColumn - 1 < 0: return
  extractNeighborWord(bufStatus.buffer[windowNode.currentLine], windowNode.currentColumn - 1)

proc firstColumnOfWordInFrontOfCursor(bufStatus: BufferStatus, windowNode: WindowNode): int =
  extractWordInFrontOfCursor(bufStatus, windowNode).get.first

proc selectedWordOrInputWord(suggestionWindow: SuggestionWindow): seq[Rune] =
  if suggestionWindow.currentSuggestion == -1:
    suggestionWindow.inputWord
  else:
    suggestionWindow.suggestoins[suggestionWindow.currentSuggestion]

proc newLine(suggestionWindow: SuggestionWindow): seq[Rune] =
  suggestionWindow.oldLine.dup(proc (r: var seq[Rune]) = r[suggestionWindow.firstColumn .. suggestionWindow.lastColumn] = suggestionWindow.selectedWordOrInputWord)

proc wordExistsInFrontOfCursor(bufStatus: BufferStatus, windowNode: WindowNode): bool =
  if windowNode.currentColumn == 0: return false
  let wordFirstLast = extractWordInFrontOfCursor(bufStatus, windowNode)
  wordFirstLast.isSome and wordFirstLast.get.word.len > 0

proc initSuggestionWindow(text, word, currentLineText: seq[Rune], firstColumn, lastColumn: int): Option[SuggestionWindow] =
  var suggestionWindow: SuggestionWindow

  suggestionwindow.identifierDictionary = makeIdentifierDictionary(text)
  suggestionwindow.inputWord = word
  suggestionwindow.firstColumn = firstColumn
  suggestionwindow.lastColumn = lastColumn
  suggestionwindow.suggestoins = collectSuggestions(suggestionwindow.identifierDictionary, word)

  if suggestionwindow.suggestoins.len == 0: return none(SuggestionWindow)

  suggestionwindow.currentSuggestion = -1
  suggestionwindow.oldLine = currentLineText

  return some(suggestionWindow)

proc close(suggestionWindow: var SuggestionWindow) =
  doAssert(suggestionWindow.isClosed)
  suggestionWindow.popUpWindow.deleteWindow

proc isChangingSelectoinKey(key: Rune): bool =
  isTabKey(key) or isShiftTab(key) or isUpKey(key) or isDownKey(key) or isPageUpKey(key) or isPageDownKey(key)

proc isUpdatingWordKey(key: Rune): bool =
  not isChangingSelectoinKey(key) and (isBackspaceKey(key) or isControlH(key) or isCharacterInIdentifier(key))

proc isQuittingSuggestoinKey(key: Rune): bool =
  isEscKey(key) or isControlSquareBracketsRight(key)

proc handleKeyInSuggestionWindow(suggestionWindow: var SuggestionWindow, status: var EditorStatus, key: Rune) =
  doAssert(not suggestionWindow.isClosed)

  if isResizekey(key):
    status.resize(terminalHeight(), terminalWidth())
    status.commandWindow.erase
  elif isControlU(key):
    currentBufStatus.deleteBeforeCursorToFirstNonBlank(currentMainWindow)
  elif isLeftKey(key):
    currentMainWindow.keyLeft
    suggestionWindow.isClosed = true
  elif isRightkey(key):
    currentBufStatus.keyRight(currentMainWindow)
    suggestionWindow.isClosed = true
  elif isHomeKey(key):
    currentMainWindow.moveToFirstOfLine
    suggestionWindow.isClosed = true
  elif isEndKey(key):
    currentBufStatus.moveToLastOfLine(currentMainWindow)
    suggestionWindow.isClosed = true
  elif isDcKey(key):
    currentBufStatus.deleteCurrentCharacter(
      currentMainWindow,
      status.settings.autoDeleteParen)
    suggestionWindow.isClosed = true
  elif isEnterKey(key):
    currentBufStatus.keyEnter(currentMainWindow,
                              status.settings.autoIndent,
                              status.settings.tabStop)
    suggestionWindow.isClosed = true
  elif not isTabKey(key) and isControlI(key):
    currentBufStatus.insertTab(currentMainWindow,
                               status.settings.tabStop,
                               status.settings.autoCloseParen)
    suggestionWindow.isClosed = true
  elif isControlE(key) or isControlY(key):
    suggestionWindow.isClosed = true
  elif isControlW(key):
    currentBufStatus.deleteWordBeforeCursor(currentMainWindow,
                                            status.settings.tabStop)
    suggestionWindow.isClosed = true
  elif isControlU(key):
    currentBufStatus.deleteCharactersBeforeCursorInCurrentLine(currentMainWindow)
    suggestionWindow.isClosed = true
  elif isControlT(key):
    currentBufStatus.addIndentInCurrentLine(currentMainWindow,
                                            status.settings.view.tabStop)
    suggestionWindow.oldLine = currentBufStatus.buffer[currentMainWindow.currentLine]
    suggestionWindow.firstColumn = firstColumnOfWordInFrontOfCursor(currentBufStatus, currentMainWindow)
    suggestionWindow.lastColumn = suggestionwindow.firstColumn + suggestionWindow.selectedWordOrInputWord.len - 1
  elif isControlD(key):
    currentBufStatus.deleteIndentInCurrentLine(currentMainWindow,
                                               status.settings.view.tabStop)
    suggestionWindow.oldLine = currentBufStatus.buffer[currentMainWindow.currentLine]
    suggestionWindow.firstColumn = firstColumnOfWordInFrontOfCursor(currentBufStatus, currentMainWindow)
    suggestionWindow.lastColumn = suggestionwindow.firstColumn + suggestionWindow.selectedWordOrInputWord.len - 1
  elif isChangingSelectoinKey(key):
    # Check whether the selected suggestion is changed.
    let prevSuggestion = suggestionWindow.currentSuggestion

    if isTabKey(key) or isDownKey(key):
      inc(suggestionWindow.currentSuggestion)
    elif isShiftTab(key) or isUpKey(key):
      dec(suggestionWindow.currentSuggestion)
    elif isPageDownkey(key):
      suggestionWindow.currentSuggestion += suggestionWindow.popUpWindow.height - 1
    elif isPageUpKey(key):
      suggestionWindow.currentSuggestion -= suggestionWindow.popUpWindow.height - 1
    
    suggestionWindow.currentSuggestion = suggestionWindow.currentSuggestion.clamp(0, suggestionWindow.suggestoins.high)

    if suggestionWindow.currentSuggestion != prevSuggestion:
      # The selected suggestoin is changed.
      # Update the buffer without recording the change.
      currentBufStatus.buffer.assign(suggestionWindow.newLine, currentMainWindow.currentLine, false)
      currentMainWindow.currentColumn = suggestionWindow.firstColumn + suggestionWindow.selectedWordOrInputWord.len
  elif isUpdatingWordKey(key):
    # Update the input word.
    if isBackspaceKey(key) or isControlH(key):
      currentBufStatus.keyBackspace(
        currentMainWindow,
        status.settings.autoDeleteParen,
        status.settings.tabStop)
    elif isCharacterInIdentifier(key):
      insertCharacter(currentBufStatus,
                      currentMainWindow,
                      status.settings.autoCloseParen, key)

    let word = extractWordInFrontOfCursor(currentBufStatus, currentMainWindow).map(x => x.word)

    if word.isSome:
      suggestionWindow.inputWord = word.get
      suggestionWindow.suggestoins = collectSuggestions(suggestionWindow.identifierDictionary, word.get)
      suggestionWindow.currentSuggestion = -1

      if suggestionWindow.suggestoins.len == 0:
        suggestionWindow.isClosed = true
    else:
      suggestionWindow.inputWord.setLen(0)
      suggestionWindow.isClosed = true
  elif isQuittingSuggestoinKey(key):
    # Quit the suggestion window.
    suggestionWindow.isClosed = true

proc buildSuggestionWindow*(bufStatus: BufferStatus, windowNode: WindowNode): Option[SuggestionWindow] =
  let (word, firstColumn, lastColumn) = extractWordInFrontOfCursor(bufStatus, windowNode).get

  # Eliminate the word on the cursor.
  let
    line = windowNode.currentLine
    column = windowNode.currentColumn - 1
    lastDeletedIndex = bufStatus.buffer.calcIndexInEntireBuffer(line, column, true)
    firstDeletedIndex = lastDeletedIndex - word.len + 1
    text = bufStatus.buffer.toRunes.dup(delete(firstDeletedIndex, lastDeletedIndex))

  initSuggestionWindow(text, word, bufStatus.buffer[windowNode.currentLine], firstColumn, lastColumn)

proc tryOpenSuggestionWindow(bufStatus: BufferStatus, windowNode: WindowNode): Option[SuggestionWindow] =
  if wordExistsInFrontOfCursor(bufStatus, windowNode):
    return buildSuggestionWindow(bufStatus, windowNode)

proc writeSuggestionWindow(suggestionWindow: var SuggestionWindow, y, x: int) =
  let
    height = suggestionwindow.suggestoins.len
    width = suggestionwindow.suggestoins.map(item => item.len).max + 2

  if suggestionwindow.popUpWindow == nil:
    suggestionwindow.popUpWindow = initWindow(height, width, y, x, EditorColorPair.popUpWindow)
  else:
    suggestionwindow.popUpWindow.height = height
    suggestionwindow.popUpWindow.width = width
    suggestionwindow.popUpWindow.y = y
    suggestionwindow.popUpWindow.x = x

  var popUpWindow = suggestionWindow.popUpWindow
  popUpWindow.writePopUpWindow(popUpWindow.height, popUpWindow.width, popUpWindow.y, popUpWindow.x, suggestionWindow.currentSuggestion, suggestionWindow.suggestoins)

proc insertMode*(status: var EditorStatus) =
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.insertModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  var suggestionWindow = none(SuggestionWindow)

  while status.isInsertMode:
    status.update
    if suggestionWindow.isSome:
      # TODO: Clean up the below code, which calculates the position of the suggestion window.
      let
        line = currentMainWindow.currentLine
        column = suggestionWindow.get.firstColumn
        y = currentMainWindow.getCursorY + 1
        x = currentMainWindow.x + currentMainWindow.view.findCursorPosition(line, column).x + currentMainWindow.view.widthOfLineNum - 1
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
      suggestionWindow.get.handleKeyInSuggestionWindow(status, key)

      if suggestionWindow.get.isClosed:
        if suggestionWindow.get.oldLine != suggestionWindow.get.newLine:
          currentBufStatus.buffer[windowNode.currentLine] = suggestionWindow.get.newLine
        suggestionWindow.get.close
        suggestionWindow = none(SuggestionWindow)

      continue
    
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
      suggestionWindow = tryOpenSuggestionWindow(currentBufStatus, currentMainWindow)
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
      suggestionWindow = tryOpenSuggestionWindow(currentBufStatus, currentMainWindow)
