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

import editorstatus, bufferstatus, window, unicodeext, gapbuffer, ui,
       normalmode, visualmode, insertmode, autocomplete, suggestionwindow,
       exmode, replacemode, filermode, buffermanager, logviewer, help,
       recentfilemode, quickrun, backupmanager, diffviewer, configmode,
       debugmode, commandline, search, commandlineutils, popupwindow,
       filermodeutils

proc searchCommand(currentMode: Mode, command: Runes): InputState =
  case currentMode:
    of Mode.insert, Mode.searchForward, Mode.searchBackward:
      InputState.Valid
    of Mode.ex:
      isExCommand(command)
    of Mode.normal:
      isNormalModeCommand(command)
    of Mode.visual, Mode.visualBlock:
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
    of Mode.visual, Mode.visualBlock:
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

proc updateSuggestWindow(
  status: var EditorStatus,
  suggestWin: var SuggestionWindow) =

    let
      mainWindowY =
        if status.settings.tabLine.enable: 1
        else: 0
      mainWindowHeight = status.settings.getMainWindowHeight
      (y, x) = suggestWin.calcSuggestionWindowPosition(
        currentMainWindowNode,
        mainWindowHeight)

    suggestWin.writeSuggestionWindow(
      currentMainWindowNode,
      y, x,
      mainWindowY,
      status.settings.statusLine.enable)

proc updateSelectedArea(status: var EditorStatus) {.inline.} =
  currentBufStatus.selectedArea.updateSelectedArea(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)

proc isIncrementalSearch(status: EditorStatus): bool {.inline.} =
  isSearchMode(currentBufStatus.mode) and
  status.settings.incrementalSearch

proc decListIndex(index: var int, list: seq[Runes]) =
  if index == 0: index = list.high
  else: index .dec

proc incListIndex(index: var int, list: seq[Runes]) =
  if index == list.high: index = 0
  else: index .inc

## Get keys and update view.
proc commandLineLoop*(status: var EditorStatus) =
  # TODO: Remove
  template openSuggestWindow() =
    suggestType = status.commandLine.buffer.getSuggestType
    suggestList = status.commandLine.getSuggestList(suggestType)
    if suggestList.len > 0:
      if suggestIndex > suggestList.high:
        suggestIndex = suggestList.high

      suggestWin = tryOpenSuggestWindow()

  if currentBufStatus.isSearchMode:
    status.searchHistory.add "".toRunes

    if status.isIncrementalSearch:
      status.isSearchHighlight = true

  var
    isCancel = false

    # TODO: Change type to `SuggestionWindow`.
    suggestWin = none(Window)

    # Use only when Ex mode.
    # TODO: Move
    suggestType = SuggestType.exCommand

    # Use when Ex mode and search mode.
    # TODO: Move
    suggestList: seq[Runes]

    # Use when Ex mode and search mode.
    # TODO: Move
    suggestIndex =
      if currentBufStatus.isSearchMode: status.searchHistory.high
      else: 0

  while not isCancel:
    status.update

    if suggestWin.isSome:
      suggestWin.get.updateSuggestWindow(
        suggestType,
        suggestList,
        suggestIndex,
        status.commandLine)
      status.commandLine.update

    # TODO: Move to editorstatus.update?
    if currentBufStatus.isSearchMode:
      status.commandLine.buffer = status.searchHistory[suggestIndex]
      status.commandLine.update

    let key = status.getKeyFromCommandLine

    if isResizeKey(key):
      updateTerminalSize()
      status.resize
    elif isEscKey(key) or isControlC(key):
      isCancel = true
      if suggestWin.isSome:
        suggestWin.get.delete
        suggestWin = none(Window)
    elif isEnterKey(key):
      if suggestWin.isSome:
        suggestWin.get.delete
        suggestWin = none(Window)
      break

    elif isTabKey(key):
      if suggestWin.isNone: openSuggestWindow()
      else: suggestIndex.incListIndex(suggestList)

      continue
    elif isShiftTab(key):
      if suggestWin.isNone: openSuggestWindow()
      else: suggestIndex.decListIndex(suggestList)

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
      if currentBufStatus.isExMode:
        suggestIndex.decListIndex(suggestList)
      elif currentBufStatus.isSearchMode:
        suggestIndex.decListIndex(status.searchHistory)
      continue
    elif isDownKey(key):
      if currentBufStatus.isExMode:
        suggestIndex.incListIndex(suggestList)
      elif currentBufStatus.isSearchMode:
        suggestIndex.incListIndex(status.searchHistory)
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

      if status.isIncrementalSearch:
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

      if searchCommand(currentBufStatus.mode, command) == InputState.Valid:
        status.execCommand(command)

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

## Get keys and update view.
proc editorMainLoop*(status: var EditorStatus) =
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

    # TODO: Move to editorStatus.update?
    if status.suggestionWindow.isSome:
      status.updateSuggestWindow(status.suggestionWindow.get)

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

    let inputState = searchCommand(currentBufStatus.mode, command)
    case inputState:
      of Continue:
        continue
      of Valid:
        status.lastOperatingTime = now()
        status.execCommand(command)
        command.clear
      of Invalid, Cancel:
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
