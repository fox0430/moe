#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[sugar, options, sequtils]
import syntax/highlite
import ui, windownode, autocomplete, bufferstatus, gapbuffer, unicodeext, osext,
       popupwindow, independentutils, completion

type SuggestionWindow* = object
  wordDictionary: WordDictionary
  oldLine: Runes
  inputWord: Runes
  firstColumn, lastColumn: int
  suggestoins: seq[Runes]
  selectedSuggestion*: int
  popupWindow: Option[PopupWindow]
  isPath: bool

proc selectedWordOrInputWord*(suggestionWindow: SuggestionWindow): Runes =
  if suggestionWindow.selectedSuggestion == -1:
    suggestionWindow.inputWord
  else:
    suggestionWindow.suggestoins[suggestionWindow.selectedSuggestion]

proc firstColumn*(s: SuggestionWindow): int {.inline.} = s.firstColumn

proc lastColumn*(s: SuggestionWindow): int {.inline.} = s.lastColumn

proc isPath*(s: SuggestionWindow): bool {.inline.} = s.isPath

proc lineSuggestionInserted*(
  oldLine, selectedWordOrInputWord: Runes,
  firstColumn, lastColumn: int,
  isPath: bool): Runes =
    ## Return the line after the suggestion or input is inserted.

    oldLine.dup(
      proc (r: var Runes) =
        let
          firstColumn = firstColumn
          lastColumn = lastColumn
        r[firstColumn .. lastColumn] =
          if isPath and r.len > 0 and r[firstColumn] == '/'.ru:
            "/".ru & selectedWordOrInputWord
          else:
            selectedWordOrInputWord)

proc newLine*(s: SuggestionWindow): Runes {.inline.} =
  ## Return the line after the suggestion or input is inserted.

  s.oldLine.lineSuggestionInserted(
    s.selectedWordOrInputWord,
    s.firstColumn,
    s.lastColumn,
    s.isPath)

proc close*(suggestionWindow: var SuggestionWindow) =
  suggestionWindow.popupWindow.get.close
  suggestionWindow.popupwindow = none(PopupWindow)

template canHandleInSuggestionWindow*(key: Rune): bool =
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

    when not defined(release):
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
    elif isPageDownKey(key):
      suggestionWindow.selectedSuggestion +=
        suggestionWindow.popupWindow.get.size.h - 1
    elif isPageUpKey(key):
      suggestionWindow.selectedSuggestion -=
        suggestionWindow.popupWindow.get.size.h - 1

    suggestionWindow.selectedSuggestion =
      suggestionWindow.selectedSuggestion.clamp(0, suggestionWindow.suggestoins.high)

    if suggestionWindow.selectedSuggestion != prevSuggestion:
      # The selected suggestoin is changed.
      # Update the buffer without recording the change.
      let newLine = suggestionWindow.newLine
      bufStatus.buffer.assign(newLine, windowNode.currentLine, false)

      let
        firstColumn =
          if (suggestionWindow.isPath) and (newLine in '/'.ru):
            suggestionWindow.firstColumn + 1
          else:
            suggestionWindow.firstColumn
        wordLen = suggestionWindow.selectedWordOrInputWord.len
      windowNode.currentColumn = firstColumn + wordLen

      bufStatus.isUpdate = true

proc initSuggestionWindow*(
  wordDictionary: var WordDictionary,
  text, word, currentLineText: Runes,
  firstColumn, lastColumn: int,
  isPath: bool): Option[SuggestionWindow] =
    ## Suggestions are extracted from `text`.
    ## `word` is the inputted text.
    ## `isPath` is true when the file path suggestions.

    if not isPath:
      wordDictionary.addWordToDictionary(text)

    var suggestionWindow: SuggestionWindow
    suggestionWindow.wordDictionary = wordDictionary
    suggestionWindow.inputWord = word
    suggestionWindow.firstColumn = firstColumn
    suggestionWindow.lastColumn = lastColumn
    suggestionWindow.isPath = isPath

    if isPath:
      suggestionWindow.suggestoins = text.splitWhitespace
    else:
      suggestionWindow.suggestoins = collectSuggestions(
        suggestionWindow.wordDictionary,
        word)

    if suggestionWindow.suggestoins.len == 0: return none(SuggestionWindow)

    suggestionWindow.selectedSuggestion = -1
    suggestionWindow.oldLine = currentLineText

    return some(suggestionWindow)

proc initLspSuggestionWindow*(
  completionList: CompletionList,
  word, currentLineText: Runes,
  firstColumn, lastColumn: int): Option[SuggestionWindow] =
    ## Suggestions are get from `CompletionList`.
    ## Ignore `WordDictionary`.
    ## `word` is the inputted text.

    var suggestionWindow: SuggestionWindow
    suggestionWindow.inputWord = word
    suggestionWindow.firstColumn = firstColumn
    suggestionWindow.lastColumn = lastColumn
    suggestionWindow.isPath = false

    suggestionWindow.suggestoins = completionList.collectLspSuggestions(word)

    if suggestionWindow.suggestoins.len > 0:
      suggestionWindow.selectedSuggestion = -1
      suggestionWindow.oldLine = currentLineText

      return some(suggestionWindow)

proc extractWordBeforeCursor(
  bufStatus: BufferStatus,
  windowNode: WindowNode): Option[tuple[word: Runes, first, last: int]] =

    if windowNode.currentColumn - 1 < 0: return
    extractNeighborWord(
      bufStatus.buffer[windowNode.currentLine],
      windowNode.currentColumn - 1)

proc extractPathBeforeCursor(
  bufStatus: BufferStatus,
  windowNode: WindowNode): Option[tuple[path: Runes, first, last: int]] =

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

proc getBufferAndLangKeyword(
  checkBuffers: seq[BufferStatus],
  firstDeletedIndex, lastDeletedIndex: int,
  lang: SourceLanguage): Runes =
    ## Get a text in the buffer and language keywords

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

proc buildLspSuggestionWindow*(
  bufStatus: BufferStatus,
  currenWindowNode: WindowNode): Option[SuggestionWindow] =
    ## Build a suggestoin window from `CompletionList`.

    let
      (word, firstColumn, lastColumn) = extractWordBeforeCursor(
        bufStatus,
        currenWindowNode).get

      # Eliminate the word on the cursor.
      firstDeletedIndex = bufStatus.buffer.calcIndexInEntireBuffer(
        currenWindowNode.currentLine,
        firstColumn,
        true)
      lastDeletedIndex = firstDeletedIndex + word.high

    initLspSuggestionWindow(
      bufStatus.completionList,
      word,
      bufStatus.buffer[currenWindowNode.currentLine],
      firstColumn,
      lastColumn)

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

proc tryOpenLspSuggestionWindow*(
  bufStatus: BufferStatus,
  currenWindowNode: WindowNode): Option[SuggestionWindow] =

    if wordExistsBeforeCursor(bufStatus, currenWindowNode):
      return buildLspSuggestionWindow(bufStatus, currenWindowNode)

proc calcSuggestionWindowPosition*(
  suggestionWindow: SuggestionWindow,
  windowNode: WindowNode,
  mainWindowHeight: int): tuple[y, x: int] =
    # TODO: Use `popupwindow.autoMoveAndResize`

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

proc calcMaxSugestionWindowHeight(
  y, cursorYPosition, mainWindowNodeY: int,
  isEnableStatusLine: bool): int =
    # TODO: Use `popupwindow.autoMoveAndResize`

    const CommanLineHeight = 1
    let statusLineHeight = if isEnableStatusLine: 1 else: 0

    # cursorYPosition is absolute y
    if y > cursorYPosition:
      result =
        (getTerminalHeight() - 1) -
        cursorYPosition -
        CommanLineHeight -
        statusLineHeight
    else:
      result = cursorYPosition - mainWindowNodeY

proc writeSuggestionWindow*(
  suggestionWindow: var SuggestionWindow,
  windowNode: WindowNode,
  y, x: int,
  mainWindowNodeY: int,
  isEnableStatusLine: bool) =

    let
      line = windowNode.currentLine
      column = windowNode.currentColumn
      (absoluteY, _) = windowNode.absolutePosition(line, column)
      maxHeight = calcMaxSugestionWindowHeight(
        y,
        absoluteY,
        mainWindowNodeY,
        isEnableStatusLine)
      height = min(suggestionWindow.suggestoins.len, maxHeight)
      width = suggestionWindow.suggestoins.maxLen + 2

    if suggestionWindow.popupWindow.isNone:
      let
        y =
          if y < mainWindowNodeY: mainWindowNodeY
          else: y
      suggestionWindow.popupWindow = initPopupWindow(
        Position(y: y, x: x),
        Size(h: height, w: width))
        .some
    else:
      suggestionWindow.popupWindow.get.size = Size(h: height, w: width)
      suggestionWindow.popupWindow.get.position = Position(y: y, x: x)

    suggestionWindow.popupWindow.get.currentLine =
      if suggestionWindow.selectedSuggestion == -1: none(int)
      else: suggestionWindow.selectedSuggestion.some

    # Add margin to both sides.
    suggestionWindow.popupWindow.get.buffer = suggestionWindow.suggestoins
      .mapIt(ru" " & it & ru" ")

    suggestionWindow.popupWindow.get.update

proc isLineChanged*(suggestionWindow: SuggestionWindow): bool {.inline.} =
  suggestionWindow.newLine != suggestionWindow.oldLine

proc getSelectedWord*(suggestionWindow: SuggestionWindow): Runes {.inline.} =
  if suggestionWindow.selectedSuggestion >= 0:
    return suggestionWindow.suggestoins[suggestionWindow.selectedSuggestion]
