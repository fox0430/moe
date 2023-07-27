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

import std/[options, times]

import editorstatus, bufferstatus, windownode, unicodeext, gapbuffer, ui,
       normalmode, visualmode, insertmode, autocomplete, suggestionwindow,
       exmode, replacemode, filermode, buffermanager, logviewer, help,
       recentfilemode, quickrun, backupmanager, diffviewer, configmode,
       debugmode, commandline, search, commandlineutils, popupwindow,
       filermodeutils, messages

proc invokeCommand(currentMode: Mode, command: Runes): InputState =
  case currentMode:
    of Mode.insert, Mode.searchForward, Mode.searchBackward:
      InputState.Valid
    of Mode.ex:
      isExCommand(command)
    of Mode.normal:
      isNormalModeCommand(command)
    of Mode.visual, Mode.visualBlock, Mode.visualLine:
      isVisualModeCommand(command)
    of Mode.replace:
      isReplaceModeCommand(command)
    of Mode.filer:
      isFilerModeCommand(command)
    of Mode.bufManager:
      isBufferManagerCommand(command)
    of Mode.logViewer:
      isLogViewerCommand(command)
    of Mode.help:
      isHelpCommand(command)
    of Mode.recentFile:
      isRecentFileCommand(command)
    of Mode.quickRun:
      isQuickRunCommand(command)
    of Mode.backup:
      isBackupManagerCommand(command)
    of Mode.diff:
      isDiffViewerCommand(command)
    of Mode.config:
      isConfigModeCommand(command)
    of Mode.debug:
      isDebugModeCommand(command)

proc execCommand(status: var EditorStatus, command: Runes) =
  let currentMode = currentBufStatus.mode
  case currentMode:
    of Mode.insert:
      status.execInsertModeCommand(command)
    of Mode.ex:
      status.execExCommand(command)
    of Mode.normal:
      status.execNormalModeCommand(command)
    of Mode.visual, Mode.visualBlock, Mode.visualLine:
      status.execVisualModeCommand(command)
    of Mode.replace:
      status.execReplaceModeCommand(command)
    of Mode.searchForward, Mode.searchBackward:
      status.execSearchCommand(command)
    of Mode.filer:
      status.execFilerModeCommand(command)
    of Mode.bufManager:
      status.execBufferManagerCommand(command)
    of Mode.logviewer:
      status.execLogViewerCommand(command)
    of Mode.help:
      status.execHelpCommand(command)
    of Mode.recentFile:
      status.execRecentFileCommand(command)
    of Mode.quickRun:
      status.execQuickRunCommand(command)
    of Mode.backup:
      status.execBackupManagerCommand(command)
    of Mode.diff:
      status.execDiffViewerCommand(command)
    of Mode.config:
      status.execConfigCommand(command)
    of Mode.debug:
      status.execDebugModeCommand(command)

proc isOpenSuggestWindow(status: EditorStatus): bool {.inline.} =
  status.settings.autocomplete.enable and isInsertMode(currentBufStatus.mode)

proc tryOpenSuggestWindow(status: var EditorStatus) {.inline.} =
  status.suggestionWindow = tryOpenSuggestionWindow(
    status.wordDictionary,
    status.bufStatus,
    currentMainWindowNode.bufferIndex,
    mainWindowNode,
    currentMainWindowNode)

proc updateSelectedArea(status: var EditorStatus) {.inline.} =
  if currentBufStatus.isVisualLineMode:
    let
      currentLine = currentMainWindowNode.currentLine
      column =
        if currentBufStatus.buffer[currentLine].high > 0:
          currentBufStatus.buffer[currentLine].high
        else:
          0
    currentBufStatus.selectedArea.updateSelectedArea(currentLine, column)
  else:
    currentBufStatus.selectedArea.updateSelectedArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

proc isIncrementalSearch(status: EditorStatus): bool {.inline.} =
  isSearchMode(currentBufStatus.mode) and
  status.settings.incrementalSearch

proc decListIndex(list: var SuggestList) =
  if list.currentIndex == 0: list.currentIndex = -1
  elif list.currentIndex == -1: list.currentIndex = list.suggestions.high
  else: list.currentIndex.dec

proc incListIndex(list: var SuggestList) =
  if list.currentIndex == list.suggestions.high: list.currentIndex = -1
  else: list.currentIndex.inc

proc assignNextExCommandHistory(
  status: var EditorStatus,
  exCommandHistoryIndex: var Option[int]) =

    let exCommandHistory = status.exCommandHistory

    if exCommandHistory.len > 0 and exCommandHistoryIndex.isSome:
      if exCommandHistoryIndex.get < exCommandHistory.high:
        exCommandHistoryIndex.get.inc

      status.commandLine.buffer = exCommandHistory[exCommandHistoryIndex.get]
      status.commandLine.moveEnd

proc assignPrevExCommandHistory(
  status: var EditorStatus,
  exCommandHistoryIndex: var Option[int]) =

    let exCommandHistory = status.exCommandHistory

    if exCommandHistory.len > 0:
      if exCommandHistoryIndex.isNone:
        exCommandHistoryIndex = exCommandHistory.high.some
      elif exCommandHistoryIndex.get > 0:
        exCommandHistoryIndex.get.dec

      status.commandLine.buffer = exCommandHistory[exCommandHistoryIndex.get]
      status.commandLine.moveEnd

proc assignNextSearchHistory(
  status: var EditorStatus,
  searchHistoryIndex: var Option[int]) =

    let searchHistory = status.searchHistory

    if status.searchHistory.len > 0 and searchHistoryIndex.isSome:
      if searchHistoryIndex.get < searchHistory.high:
        searchHistoryIndex.get.inc

      status.commandLine.buffer = searchHistory[searchHistoryIndex.get]
      status.commandLine.moveEnd

proc assignPrevSearchHistory(
  status: var EditorStatus,
  searchHistoryIndex: var Option[int]) =

    let searchHistory = status.searchHistory

    if status.searchHistory.len > 0:
      if searchHistoryIndex.isNone:
        searchHistoryIndex = searchHistory.high.some
      elif searchHistoryIndex.get > 0:
        searchHistoryIndex.get.dec

      status.commandLine.buffer = searchHistory[searchHistoryIndex.get]
      status.commandLine.moveEnd

proc isResetExCommandHistoryIndex(
  exCommandHistoryIndex: Option[int],
  key: Rune): bool {.inline.} =

    (exCommandHistoryIndex.isSome) and not (isUpKey(key) or isDownKey(key))

proc isResetSearchHistoryIndex(
  searchHistoryIndex: Option[int],
  key: Rune): bool {.inline.} =

    (searchHistoryIndex.isSome) and not (isUpKey(key) or isDownKey(key))

proc commandLineLoop*(status: var EditorStatus) =
  ## Get keys and update view.

  proc openSuggestWindow(
    commandLine: var CommandLine,
    suggestList: var SuggestList): Option[Window] =
      ## If there is only one candidate, insert it without opening a window.

      suggestList = commandLine.buffer.initSuggestList
      if suggestList.suggestions.len == 1:
        commandLine.insertSuggestion(suggestList)
      elif suggestList.suggestions.len > 1:
        return tryOpenSuggestWindow()

  if currentBufStatus.isSearchMode:
    status.searchHistory.add "".toRunes

    if status.isIncrementalSearch:
      status.isSearchHighlight = true

  var
    isCancel = false

    # TODO: Change type to `SuggestionWindow`.
    suggestWin = none(Window)

    # Use when Ex mode and search mode.
    # TODO: Move
    suggestList: SuggestList

    # TODO: Remove
    exCommandHistoryIndex: Option[int]

    # TODO: Remove
    searchHistoryIndex: Option[int]

  if currentBufStatus.isSearchMode:
    suggestList.currentIndex = status.searchHistory.high

  while not isCancel:
    status.update

    if suggestWin.isSome:
      suggestWin.get.updateSuggestWindow(
        status.commandLine,
        suggestList)
      status.commandLine.update

    # TODO: Move to editorstatus.update?
    if currentBufStatus.isSearchMode:
      status.commandLine.buffer = status.searchHistory[suggestList.currentIndex]
      status.commandLine.update

    let key = status.getKeyFromCommandLine

    if isResizeKey(key):
      updateTerminalSize()
      status.resize
      continue

    if exCommandHistoryIndex.isResetExCommandHistoryIndex(key):
      exCommandHistoryIndex = none(int)

    if searchHistoryIndex.isResetSearchHistoryIndex(key):
      searchHistoryIndex = none(int)

    if isEscKey(key) or isControlC(key):
      isCancel = true
      if suggestWin.isSome:
        suggestWin.get.delete
        suggestWin = none(Window)
    elif isEnterKey(key):
      # Close the suggestion window.
      if suggestWin.isSome:
        suggestWin.get.delete
        suggestWin = none(Window)
        if suggestList.currentindex > -1:
          # Insert the current selection and continue the current mode.
          status.commandLine.insertSuggestion(suggestList)
      else:
        # Exit the current mode.
        break

    elif isTabKey(key):
      if suggestWin.isNone:
        suggestWin = status.commandLine.openSuggestWindow(suggestList)
      else:
        suggestList.incListIndex
      continue
    elif isShiftTab(key):
      if suggestWin.isNone:
        suggestWin = status.commandLine.openSuggestWindow(suggestList)
      else:
        suggestList.decListIndex
      continue

    elif isLeftKey(key):
      status.commandLine.moveLeft
    elif isRightKey(key):
      status.commandLine.moveRight
      if status.settings.popupWindowInExmode:
        if status.popupWindow != nil:
          status.popupWindow.deleteWindow
          continue

    elif isUpKey(key):
      if suggestWin.isSome and currentBufStatus.isExMode:
        # The suggestion window is used only when suggesting ex commands.
        suggestList.decListIndex
      else:
        if currentBufStatus.isSearchMode:
          status.assignPrevSearchHistory(searchHistoryIndex)
        else:
          status.assignPrevExCommandHistory(exCommandHistoryIndex)
          continue
    elif isDownKey(key):
      if suggestWin.isSome and currentBufStatus.isExMode:
        # The suggestion window is used only when suggesting ex commands.
        suggestList.incListIndex
      else:
        if currentBufStatus.isSearchMode:
          status.assignNextSearchHistory(searchHistoryIndex)
        else:
          status.assignNextExCommandHistory(exCommandHistoryIndex)
          continue

    elif isHomeKey(key):
      status.commandLine.moveTop
    elif isEndKey(key):
      status.commandLine.moveEnd
    elif isBackspaceKey(key):
      status.commandLine.deleteChar
    elif isDcKey(key):
      status.commandLine.deleteCurrentChar
    else:
      status.commandLine.insert(key)

    if status.isIncrementalSearch and status.commandLine.buffer.len > 0:
      status.execSearchCommand(status.commandLine.buffer)

    if suggestWin.isSome:
      suggestWin.get.delete
      suggestWin = none(Window)

  if isCancel:
    status.changeMode(currentBufStatus.prevMode)

    if currentBufStatus.isSearchMode:
      if status.searchHistory[^1].len == 0:
        status.searchHistory.delete(status.searchHistory.high)

      if status.isIncrementalSearch:
        status.isSearchHighlight = false
  else:
    if isExMode(currentBufStatus.mode):
      let command = status.commandLine.buffer

      case invokeCommand(currentBufStatus.mode, command):
        of InputState.Valid:
          status.execCommand(command)
        of InputState.Invalid:
          status.commandLine.writeNotEditorCommandError(command)
        else:
          discard

      if isExMode(currentBufStatus.mode):
        status.changeMode(currentBufStatus.prevMode)
    elif isSearchMode(currentBufStatus.mode):
      status.changeMode(currentBufStatus.prevMode)

proc updateAfterInsertFromSuggestion(status: var EditorStatus) =
  if status.suggestionWindow.get.isLineChanged:
    currentBufStatus.buffer[currentMainWindowNode.currentLine] =
      status.suggestionWindow.get.newLine
    currentMainWindowNode.expandedColumn = currentMainWindowNode.currentColumn

  # Update WordDictionary
  block:
    let selectedWord = status.suggestionWindow.get.getSelectedWord
    if selectedWord.len > 0:
      status.wordDictionary.incNumOfUsed(selectedWord)

# TODO: Move
proc close(suggestWin: var Option[SuggestionWindow]) {.inline.} =
  suggestWin.get.close
  suggestWin = none(SuggestionWindow)

proc editorMainLoop*(status: var EditorStatus) =
  ## Get keys and update view.

  status.resize

  var command: Runes

  while mainWindow.numOfMainWindow > 0:
    if currentBufStatus.isEditMode:
      # For undo/redo
      currentBufStatus.buffer.beginNewSuitIfNeeded
      currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

    # TODO: Move to editorstatus.update
    if isVisualMode(currentBufStatus.mode):
      status.updateSelectedArea

    status.update

    let key = status.getKeyFromMainWindow

    if status.suggestionWindow.isSome:
      if canHandleInSuggestionWindow(key):
        status.suggestionWindow.get.handleKeyInSuggestionWindow(
          currentBufStatus,
          currentMainWindowNode,
          key)
        continue
      else:
        status.updateAfterInsertFromSuggestion
        status.suggestionWindow.close

    if isResizeKey(key):
      updateTerminalSize()
      status.resize
      continue

    command.add key

    case invokeCommand(currentBufStatus.mode, command):
      of InputState.Continue:
        continue
      of InputState.Valid:
        status.lastOperatingTime = now()
        status.execCommand(command)
        command.clear
      of InputState.Invalid, InputState.Cancel:
        command.clear
        currentBufStatus.cmdLoop = 0
        continue

    if status.isOpenSuggestWindow:
      status.tryOpenSuggestWindow

    # TODO: Fix condition.
    # I think this should use something like a flag or enum
    # for switching to the command line instead of modes.
    if currentBufStatus.isExMode or
       currentBufStatus.isSearchMode:
         status.commandLineLoop
