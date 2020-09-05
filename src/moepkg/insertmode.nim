import terminal, times, sugar, critbits, sequtils, options
from os import execShellCmd
import ui, editorstatus, gapbuffer, unicodeext, undoredostack, window,
       movement, editor, bufferstatus, generalautocomplete, color

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

proc extractNeighborWord(bufStatus: BufferStatus, windowNode: WindowNode): Option[tuple[word: seq[Rune], first, last: int]] =
  extractNeighborWord(bufStatus.buffer[windowNode.currentLine], max(windowNode.currentColumn-1, 0))

proc selectedWordOrInputWord(suggestionWindow: SuggestionWindow): seq[Rune] =
  if suggestionWindow.currentSuggestion == -1:
    suggestionWindow.inputWord
  else:
    suggestionWindow.suggestoins[suggestionWindow.currentSuggestion]

proc newLine(suggestionWindow: SuggestionWindow): seq[Rune] =
  suggestionWindow.oldLine.dup(proc (r: var seq[Rune]) = r[suggestionWindow.firstColumn .. suggestionWindow.lastColumn] = suggestionWindow.selectedWordOrInputWord)

proc shouldTryOpenSuggestionWindow(bufStatus: BufferStatus, windowNode: WindowNode): bool =
  extractNeighborWord(bufStatus, windowNode).get.word.len > 0

proc initSuggestionWindow(text, word, currentLineText: seq[Rune], firstColumn, lastColumn: int, y, x: int): Option[SuggestionWindow] =
  var suggestionWindow: SuggestionWindow

  suggestionwindow.identifierDictionary = makeIdentifierDictionary(text)
  suggestionwindow.inputWord = word
  suggestionwindow.firstColumn = firstColumn
  suggestionwindow.lastColumn = lastColumn
  suggestionwindow.suggestoins = collectSuggestions(suggestionwindow.identifierDictionary, word)

  if suggestionwindow.suggestoins.len == 0: return none(SuggestionWindow)

  let
    height = suggestionwindow.suggestoins.len
    width = suggestionwindow.suggestoins.map(item => item.len).max + 2
  suggestionwindow.popUpWindow = initWindow(height, width, y, x, EditorColorPair.popUpWindow)

  suggestionwindow.currentSuggestion = -1
  suggestionwindow.oldLine = currentLineText
  
  return some(suggestionWindow)

proc close(suggestionWindow: var SuggestionWindow) =
  doAssert(suggestionWindow.isClosed)
  suggestionWindow.popUpWindow.deleteWindow

proc writeSuggestionWindow(suggestionWindow: SuggestionWindow) =
  var popUpWindow = suggestionWindow.popUpWindow
  popUpWindow.writePopUpWindow(popUpWindow.height, popUpWindow.width, popUpWindow.y, popUpWindow.x, suggestionWindow.currentSuggestion, suggestionWindow.suggestoins)

proc isChangingSelectoinKey(key: Rune): bool =
  isTabKey(key) or isShiftTab(key)

proc isUpdatingWordKey(key: Rune): bool =
  not isChangingSelectoinKey(key) and (isBackspaceKey(key) or isControlH(key) or isCharacterInIdentifier(key))

proc isQuittingSuggestoinKey(key: Rune): bool =
  isEscKey(key)

proc handleKeyInSuggestionWindow(suggestionWindow: var SuggestionWindow, status: var EditorStatus, key: Rune) =
  doAssert(not suggestionWindow.isClosed)

  if isChangingSelectoinKey(key):
    # Check whether the selected suggestion is changed.
    let prevSuggestion = suggestionWindow.currentSuggestion

    if isTabKey(key):
      inc(suggestionWindow.currentSuggestion)
    elif isShiftTab(key):
      dec(suggestionWindow.currentSuggestion)
    
    suggestionWindow.currentSuggestion = suggestionWindow.currentSuggestion.clamp(0, suggestionWindow.suggestoins.high)

    if suggestionWindow.currentSuggestion != prevSuggestion:
      # The selected suggestoin is changed.
      # Update the buffer without recording the change.
      currentBufStatus.buffer.assign(suggestionWindow.newLine, currentMainWindow.currentLine, false)
      currentMainWindow.currentColumn = suggestionWindow.firstColumn + suggestionWindow.selectedWordOrInputWord.len

  if isUpdatingWordKey(key):
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

    let word = extractNeighborWord(currentBufStatus, currentMainWindow).map(x => x.word)

    if word.isSome:
      suggestionWindow.inputWord = word.get
      suggestionWindow.suggestoins = collectSuggestions(suggestionWindow.identifierDictionary, word.get)
      suggestionWindow.currentSuggestion = -1

      if suggestionWindow.suggestoins.len == 0:
        suggestionWindow.isClosed = true
    else:
      suggestionWindow.isClosed = true

  if isQuittingSuggestoinKey(key):
    # Quit the suggestion window.
    suggestionWindow.isClosed = true

  if suggestionWindow.isClosed: return

  # Update the suggestion window.
  let
    height = suggestionWindow.suggestoins.len
    width = suggestionWindow.suggestoins.map(item => item.len).max + 2
  suggestionWindow.popUpWindow.resize(height, width)
 
proc getCursorY(windowNode: WindowNode): int =
  windowNode.y + windowNode.cursor.y

proc getCursorX(windowNode: WindowNode): int =
  windowNode.x + windowNode.cursor.x + windowNode.view.widthOfLineNum

proc buildSuggestionWindow*(status: var EditorStatus): Option[SuggestionWindow] =
  let (word, firstColumn, lastColumn) = extractNeighborWord(currentBufStatus, currentMainWindow).get

  # Eliminate the word on the cursor.
  let
    line = currentMainWindow.currentLine
    column = currentMainWindow.currentColumn - 1
    lastDeletedIndex = currentBufStatus.buffer.calcIndexInEntireBuffer(line, column, true)
    firstDeletedIndex = lastDeletedIndex - word.len + 1
    text = currentBufStatus.buffer.toRunes.dup(delete(firstDeletedIndex, lastDeletedIndex))

  let
    y = getCursorY(currentMainWindow) + 1
    x = getCursorX(currentMainWindow) - word.len

  initSuggestionWindow(text, word, currentBufStatus.buffer[currentMainWindow.currentLine], firstColumn, lastColumn, y, x)

proc insertMode*(status: var EditorStatus) =
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.insertModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  var suggestionWindow = none(SuggestionWindow)

  while status.isInsertMode:
    let
      currentBufferIndex = status.bufferIndexInCurrentWindow
      workSpaceIndex = status.currentWorkSpaceIndex

    status.update
    if suggestionWindow.isSome:
      suggestionWindow.get.writeSuggestionWindow

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
    elif isEnterKey(key):
      keyEnter(currentBufStatus,
               currentMainWindow,
               status.settings.autoIndent,
               status.settings.tabStop)
    elif key == ord('\t') or isControlI(key):
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
      if isCharacterInIdentifier(key) and shouldTryOpenSuggestionWindow(currentBufStatus, currentMainWindow):
        suggestionWindow = some(status.buildSuggestionWindow).flatten
