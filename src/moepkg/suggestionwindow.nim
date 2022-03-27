import std/[sugar, options, sequtils]
import ui, window, autocomplete, bufferstatus, gapbuffer, color,
       editorstatus, unicodeext, osext
import syntax/highlite

type SuggestionWindow* = object
  wordDictionary: WordDictionary
  oldLine: seq[Rune]
  inputWord: seq[Rune]
  firstColumn, lastColumn: int
  suggestoins: seq[seq[Rune]]
  selectedSuggestion: int
  popUpWindow: Window
  isPath: bool

proc selectedWordOrInputWord(suggestionWindow: SuggestionWindow): seq[Rune] =
  if suggestionWindow.selectedSuggestion == -1:
    suggestionWindow.inputWord
  else:
    suggestionWindow.suggestoins[suggestionWindow.selectedSuggestion]

proc newLine*(suggestionWindow: SuggestionWindow): seq[Rune] =
  suggestionWindow.oldLine.dup(
    proc (r: var seq[Rune]) =
      let
        firstColumn = suggestionWindow.firstColumn
        lastColumn = suggestionWindow.lastColumn
      r[firstColumn .. lastColumn] =
        if suggestionWindow.isPath and r.len > 0 and r[firstColumn] == '/'.ru:
          "/".ru & suggestionWindow.selectedWordOrInputWord
        else:
          suggestionWindow.selectedWordOrInputWord)

proc close*(suggestionWindow: var SuggestionWindow) =
  suggestionWindow.popUpWindow.deleteWindow

proc canHandleInSuggestionWindow*(key: Rune): bool {.inline.} =
  isTabKey(key) or
  isShiftTab(key) or
  isUpKey(key) or
  isDownKey(key) or
  isPageUpKey(key) or
  isPageDownKey(key)

proc handleKeyInSuggestionWindow*(
  suggestionWindow: var SuggestionWindow,
  bufStatus: var BufferStatus,
  windowNode: var WindowNode,
  key: Rune) =

  doAssert(canHandleInSuggestionWindow(key))

  # Check whether the selected suggestion is changed.
  let prevSuggestion = suggestionWindow.selectedSuggestion

  if isTabKey(key) or isDownKey(key):
    if suggestionWindow.selectedSuggestion == suggestionWindow.suggestoins.high:
      suggestionWindow.selectedSuggestion = 0
    else:
      inc(suggestionWindow.selectedSuggestion)
  elif isShiftTab(key) or isUpKey(key):
    if suggestionWindow.selectedSuggestion == 0:
      suggestionWindow.selectedSuggestion = suggestionWindow.suggestoins.high
    else:
      dec(suggestionWindow.selectedSuggestion)
  elif isPageDownkey(key):
    suggestionWindow.selectedSuggestion += suggestionWindow.popUpWindow.height - 1
  elif isPageUpKey(key):
    suggestionWindow.selectedSuggestion -= suggestionWindow.popUpWindow.height - 1

  suggestionWindow.selectedSuggestion =
    suggestionWindow.selectedSuggestion.clamp(0, suggestionWindow.suggestoins.high)

  if suggestionWindow.selectedSuggestion != prevSuggestion:
    # The selected suggestoin is changed.
    # Update the buffer without recording the change.
    let newLine = suggestionWindow.newLine
    bufStatus.buffer.assign(newLine, windowNode.currentLine, false)

    let
      firstColumn =
        if (suggestionwindow.isPath) and (newLine in '/'.ru):
          suggestionWindow.firstColumn + 1
        else:
          suggestionWindow.firstColumn
      wordLen = suggestionWindow.selectedWordOrInputWord.len
    windowNode.currentColumn = firstColumn + wordLen

    bufStatus.isUpdate = true

# Suggestions are extracted from `text`.
# `word` is the inputted text.
# `isPath` is true when the file path suggestions.
proc initSuggestionWindow*(
  wordDictionary: var WordDictionary,
  text, word, currentLineText: seq[Rune],
  firstColumn, lastColumn: int,
  isPath: bool): Option[SuggestionWindow] =

  if not isPath:
    wordDictionary.addWordToDictionary(text)

  var suggestionWindow: SuggestionWindow
  suggestionwindow.wordDictionary = wordDictionary
  suggestionwindow.inputWord = word
  suggestionwindow.firstColumn = firstColumn
  suggestionwindow.lastColumn = lastColumn
  suggestionwindow.isPath = isPath

  if isPath:
    suggestionwindow.suggestoins = text.splitWhitespace
  else:
    suggestionwindow.suggestoins = collectSuggestions(
      suggestionwindow.wordDictionary,
      word)

  if suggestionwindow.suggestoins.len == 0: return none(SuggestionWindow)

  suggestionwindow.selectedSuggestion = -1
  suggestionwindow.oldLine = currentLineText

  return some(suggestionWindow)

proc extractWordBeforeCursor(
  bufStatus: BufferStatus,
  windowNode: WindowNode): Option[tuple[word: seq[Rune], first, last: int]] =

  if windowNode.currentColumn - 1 < 0: return
  extractNeighborWord(
    bufStatus.buffer[windowNode.currentLine],
    windowNode.currentColumn - 1)

proc extractPathBeforeCursor(
  bufStatus: BufferStatus,
  windowNode: WindowNode): Option[tuple[path: seq[Rune], first, last: int]] =

  if windowNode.currentColumn - 1 < 0: return
  extractNeighborPath(
    bufStatus.buffer[windowNode.currentLine],
    windowNode.currentColumn - 1)

proc wordExistsBeforeCursor(
  bufStatus: BufferStatus,
  windowNode: WindowNode): bool =

  if windowNode.currentColumn == 0: return false
  let wordFirstLast = extractWordBeforeCursor(bufStatus, windowNode)
  wordFirstLast.isSome and wordFirstLast.get.word.len > 0

# Get a text in the buffer and language keywords
proc getBufferAndLangKeyword(
  checkBuffers: seq[BufferStatus],
  firstDeletedIndex, lastDeletedIndex: int,
  lang: SourceLanguage): seq[Rune] =

  let
    bufferText = getTextInBuffers(
      checkBuffers,
      firstDeletedIndex,
      lastDeletedIndex)
    keywordsText = getTextInLangKeywords(lang)

  return bufferText & keywordsText

proc buildSuggestionWindow*(
  wordDictionary: var WordDictionary,
  bufStatus: seq[BufferStatus],
  currentBufferIndex: int,
  root, currenWindowNode: WindowNode): Option[SuggestionWindow] =

  let
    currentBufStatus = bufStatus[currentBufferIndex]
    currentLineBuffer = currentBufStatus.buffer[currenWindowNode.currentLine]

    # Whether the word on the current position is a path.
    head = currentLineBuffer[0 .. currenWindowNode.currentColumn - 1]
    word = (head.splitWhitespace)[^1].removePrefix("\"".ru)
    isPath = word.isPath

  if isPath:
    let
      (path, firstColumn, lastColumn) = extractPathBeforeCursor(
        currentBufStatus,
        currenWindowNode).get

      (pathHead, pathTail) = splitPathExt(path)

      text = getPathList(path)

      # TODO: Fix and refactor
      first =
        if pathHead.high >= 0: firstColumn + pathHead.high
        else: 0
      last =
        if pathTail.len == 0: first
        else: lastColumn

    initSuggestionWindow(
      wordDictionary,
      text,
      pathTail,
      currentBufStatus.buffer[currenWindowNode.currentLine],
      first,
      last,
      isPath)

  else:
    let
      currentBufStatus = bufStatus[currentBufferIndex]
      (word, firstColumn, lastColumn) = extractWordBeforeCursor(
        currentBufStatus,
        currenWindowNode).get

      # Eliminate the word on the cursor.
      line = currenWindowNode.currentLine
      column = firstColumn
      firstDeletedIndex = currentBufStatus.buffer.calcIndexInEntireBuffer(
        line,
        column,
        true)
      lastDeletedIndex = firstDeletedIndex + word.len - 1
      bufferIndexList = root.getAllBufferIndex

    # 0 is current bufStatus
    var checkBuffers: seq[BufferStatus] = @[bufStatus[currentBufferIndex]]
    for i in bufferIndexList:
      if i != currentBufferIndex: checkBuffers.add bufStatus[i]

    let text = getBufferAndLangKeyword(
      checkBuffers,
      firstDeletedIndex,
      lastDeletedIndex,
      bufStatus[currentBufferIndex].language)

    initSuggestionWindow(
      wordDictionary,
      text,
      word,
      currentBufStatus.buffer[currenWindowNode.currentLine],
      firstColumn,
      lastColumn,
      isPath)

proc tryOpenSuggestionWindow*(
  wordDictionary: var WordDictionary,
  bufStatus: seq[BufferStatus],
  currentBufferIndex: int,
  root, currenWindowNode: WindowNode): Option[SuggestionWindow] =

  if wordExistsBeforeCursor(bufStatus[currentBufferIndex], currenWindowNode):
    return buildSuggestionWindow(
      wordDictionary,
      bufStatus,
      currentBufferIndex,
      root,
      currenWindowNode)

proc calcSuggestionWindowPosition*(
  suggestionWindow: SuggestionWindow,
  windowNode: WindowNode,
  mainWindowHeight: int): tuple[y, x: int] =

  let
    line = windowNode.currentLine
    column = suggestionWindow.firstColumn
    (absoluteY, absoluteX) = windowNode.absolutePosition(line, column)
    diffY = 1
    leftMargin = 1

    # If the suggest window height is higher than the main window height under the cursor position,
    # the suggest window  move to over the cursor position
    suggestHigh = suggestionWindow.suggestoins.high
    y =
      if suggestHigh > (mainWindowHeight - absoluteY - diffY) and
        absoluteY > (mainWindowHeight - absoluteY):
        max(absoluteY - suggestHigh - diffY, 0)
      else:
        absoluteY + diffY

    x =
      if suggestionWindow.isPath and suggestionWindow.oldLine.count('/'.ru) > 1:
        absoluteX - leftMargin + 1
      else:
        absoluteX - leftMargin

  return (y, x)

# cursorPosition is absolute y
proc calcMaxSugestionWindowHeight(
  y,
  terminalHeight,
  cursorYPosition,
  mainWindowNodeY: int,
  isEnableStatusLine: bool): int =

  const commanLineHeight = 1
  let statusLineHeight = if isEnableStatusLine: 1 else: 0

  if y > cursorYPosition:
    result = (terminalHeight - 1) - cursorYPosition - commanLineHeight - statusLineHeight
  else:
    result = cursorYPosition - mainWindowNodeY

proc writeSuggestionWindow*(
  suggestionWindow: var SuggestionWindow,
  windowNode: WindowNode,
  y, x,
  terminalHeight, terminalWidth,
  mainWindowNodeY: int,
  isEnableStatusLine: bool) =

  let
    line = windowNode.currentLine
    column = windowNode.currentColumn
    (absoluteY, _) = windowNode.absolutePosition(line, column)
    maxHeight = calcMaxSugestionWindowHeight(
      y,
      terminalHeight,
      absoluteY,
      mainWindowNodeY,
      isEnableStatusLine)
    height = min(suggestionwindow.suggestoins.len, maxHeight)
    width = suggestionwindow.suggestoins.map(item => item.len).max + 2

  if suggestionwindow.popUpWindow == nil:
    suggestionwindow.popUpWindow = initWindow(
      height,
      width,
      if y < mainWindowNodeY: mainWindowNodeY else: y,
      x,
      EditorColorPair.popUpWindow)
  else:
    suggestionwindow.popUpWindow.height = height
    suggestionwindow.popUpWindow.width = width
    suggestionwindow.popUpWindow.y = y
    suggestionwindow.popUpWindow.x = x

  var popUpWindow = suggestionWindow.popUpWindow
  popUpWindow.writePopUpWindow(
    popUpWindow.height,
    popUpWindow.width,
    popUpWindow.y,
    popUpWindow.x,
    terminalHeight,
    terminalWidth,
    suggestionWindow.selectedSuggestion,
    suggestionWindow.suggestoins)

proc isLineChanged*(suggestionWindow: SuggestionWindow): bool {.inline.} =
  suggestionWindow.newLine != suggestionWindow.oldLine

proc getSelectedWord*(suggestionWindow: SuggestionWindow): seq[Rune] {.inline.} =
  if suggestionWindow.selectedSuggestion >= 0:
    return suggestionWindow.suggestoins[suggestionWindow.selectedSuggestion]
