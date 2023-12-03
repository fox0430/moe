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
import pkg/results
import editorstatus, bufferstatus, windownode, unicodeext, gapbuffer, ui,
       normalmode, visualmode, insertmode, autocomplete, suggestionwindow,
       exmode, replacemode, filermode, buffermanager, logviewer, help,
       recentfilemode, quickrun, backupmanager, diffviewer, configmode,
       debugmode, commandline, search, commandlineutils, popupwindow,
       filermodeutils, messages, registers, exmodeutils, editor, movement,
       searchutils, independentutils

type
  BeforeLine = object
    lineNumber: int
    lineBuffer: Runes

  IncrementalReplaceInfo = ref object
    sub, by: Runes
    isGlobal: bool
    beforeLines: seq[BeforeLine]

proc invokeCommand(
  currentMode: Mode,
  command: Runes,
  recodingOperationRegister: Option[Rune]): InputState =

    case currentMode:
      of Mode.insert, Mode.insertMulti, Mode.searchForward, Mode.searchBackward:
        InputState.Valid
      of Mode.ex:
        isExCommandBuffer(command)
      of Mode.normal:
        isNormalModeCommand(command, recodingOperationRegister)
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

proc execCommand(status: var EditorStatus, command: Runes): Option[Rune] =
  ## Exec editor commands.
  ## Return the key typed during command execution if needed.

  let currentMode = currentBufStatus.mode
  case currentMode:
    of Mode.insert, Mode.insertMulti:
      status.execInsertModeCommand(command)
    of Mode.ex:
      status.execExCommand(command)
    of Mode.normal:
      return status.execNormalModeCommand(command)
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

proc isExecMacroCommand(bufStatus: BufferStatus, commands: Runes): bool =
  if bufStatus.mode.isNormalMode and commands.len > 1:
    if commands[0].isDigit:
      # If the first word (text) is a number, it is considered as the number
      # repetitions.
      var i = 0
      while i < commands.high and commands[i].isDigit: i.inc
      if commands.len - i == 2:
        return commands[i] == ord('@') and
          isOperationRegisterName(commands[i + 1]) and
          getOperationsFromRegister(commands[i + 1]).get.len > 0
    else:
      return commands.len == 2 and
        commands[0] == ord('@') and
        isOperationRegisterName(commands[1]) and
        getOperationsFromRegister(commands[1]).get.len > 0

proc execMacro(status: var EditorStatus, name: Rune) =
  ## Exec commands from the operationRegister.

  if isOperationRegisterName(name):
    let commands = getOperationsFromRegister(name).get
    for c in commands:
      discard status.execCommand(c)
      status.update

proc execEditorCommand(status: var EditorStatus, command: Runes): Option[Rune] =
  ## Exec editor commands.
  ## Return the key typed during command execution if needed.

  if status.recodingOperationRegister.isSome:
    if not isStopRecordingOperationsCommand(currentBufStatus, command):
      discard addOperationToRegister(
        status.recodingOperationRegister.get,
        command).get

  status.lastOperatingTime = now()

  if isExecMacroCommand(currentBufStatus, command):
    var repeat = 1
    if command[0].isDigit:
      # If the first word (text) is a number, it is considered as the number
      # repetitions.
      var i = 0
      while command[i + 1].isDigit: i.inc
      repeat = parseInt(command[0 .. i])

    let registerName = command[^1]
    for i in 0 ..< repeat:
      status.execMacro(registerName)
  else:
    return status.execCommand(command)

proc insertPasteBuffer(status: var EditorStatus, pasteBuffer: seq[Runes]) =
  ## Insert text to the buffer if Insert mode, Replace mode and Command line
  ## mode (Ex and Search).

  if currentBufStatus.isCommandLineMode:
    # Command line modes (Ex, Search).

    for lineNum, line in pasteBuffer:
      status.commandLine.insert(line)
      if lineNum < pasteBuffer.high:
        # Insert "\n". Don't insert '\n' (Newline).
        status.commandLine.insert(ru"\n")

    if currentBufStatus.isSearchMode:
      # Assign the buffer to the latest search history.
      status.searchHistory[^1] = status.commandLine.buffer.replaceToNewLines
  else:
    # File edit modes (Insert, Replace).

    # Assign the pasteBuffer to the no name register.
    let isLine = pasteBuffer.len > 1
    status.registers.addRegister(pasteBuffer, isLine, status.settings)

    if currentBufStatus.isInsertMode:
      currentBufStatus.pasteAfterCursor(
        currentMainWindowNode,
        status.registers.noNameRegisters)
    elif currentBufStatus.isReplaceMode:
      for lineNum, line in pasteBuffer:
        for r in line:
          currentBufStatus.replaceCurrentCharAndMoveToRight(
            currentMainWindowNode,
            status.settings.standard.autoCloseParen,
            r)
        if lineNum < pasteBuffer.high:
          # Insert a new line and move to the next line.
          currentBufStatus.keyEnter(
            currentMainWindowNode,
            status.settings.standard.autoIndent,
            status.settings.standard.tabStop)
          currentMainWindowNode.currentColumn = 0
    else:
      status.commandLine.writePasteIgnoreWarn

proc jumpAndHighlightInReplaceCommand(status: var EditorStatus) =
  # Jump and highlight in replace command.
  if not status.isSearchHighlight: status.isSearchHighlight = true

  let info = parseReplaceCommand(status.commandLine.buffer)
  if info.sub.len > 0 and info.by.len == 0:
    # TODO: Don't use `status.searchHistory`.
    status.searchHistory.add info.sub
    currentBufStatus.jumpToSearchForwardResults(
      currentMainWindowNode,
      info.sub,
      status.settings.standard.ignorecase,
      status.settings.standard.smartcase)

proc isReplaceCommand(commandLine: CommandLine): bool {.inline.} =
  commandLine.buffer.startsWith(ru"%s/")

proc isIncrementalReplace(status: EditorStatus): bool {.inline.} =
  status.settings.standard.incrementalSearch and
  currentBufStatus.isExMode and
  status.commandLine.isReplaceCommand and
  status.commandLine.buffer.count(ru'/') > 1 and
  status.commandLine.buffer.count(ru'/') < 3

proc initBeforeLineForIncrementalReplace(
  status: var EditorStatus): seq[BeforeLine] =

    let info = parseReplaceCommand(status.commandLine.buffer)
    if info.sub.len > 0 and info.by.len > 0:
      status.searchHistory[^1] = info.by

      let positons = currentBufStatus.buffer.toSeqRunes.searchAllOccurrence(
        info.sub,
        false,
        false)
      for p in positons:
        if result.len == 0 or result[^1].lineNumber != p.line:
          result.add BeforeLine(
            lineNumber: p.line,
            lineBuffer: currentBufStatus.buffer[p.line])

proc execIncrementalReplace(status: var EditorStatus,) {.inline.} =
  status.replaceBuffer(status.commandLine.buffer)

proc commandLineLoop*(status: var EditorStatus): Option[Rune] =
  ## Get keys and update view.
  ## Return the key typed during command execution if needed.

  proc openSuggestWindow(
    commandLine: var CommandLine,
    suggestList: var SuggestList): Option[PopupWindow] =
      ## If there is only one candidate, insert it without opening a window.

      suggestList = commandLine.buffer.initSuggestList
      if suggestList.suggestions.len == 1:
        commandLine.insertSuggestion(suggestList)
      elif suggestList.suggestions.len > 1:
        return tryOpenSuggestWindow()

  proc closeSuggestWindow(suggestWin: var Option[PopupWindow]) {.inline.} =
    suggestWin.get.close
    suggestWin = none(PopupWindow)

  proc isJumpAndHighlightInReplaceCommand(
    status: EditorStatus): bool {.inline.} =
      status.settings.standard.incrementalSearch and
      status.commandLine.isReplaceCommand and
      status.commandLine.buffer.len > 3

  if currentBufStatus.isSearchMode:
    status.searchHistory.add "".toRunes

    if not status.isSearchHighlight: status.isSearchHighlight = true

  var
    isCancel = false

    # TODO: Change type to `SuggestionWindow`.
    suggestWin = none(PopupWindow)

    # Use when Ex mode and search mode.
    # TODO: Move
    suggestList: SuggestList

    # TODO: Remove
    exCommandHistoryIndex: Option[int]

    # TODO: Remove
    searchHistoryIndex: Option[int]

    incReplaceInfo: Option[IncrementalReplaceInfo]

  if currentBufStatus.isSearchMode:
    suggestList.currentIndex = status.searchHistory.high

  while not isCancel:
    if suggestWin.isSome:
      # Update suggestion window and command line.

      suggestList.updateSuggestions
      if suggestList.suggestions.len == 0:
        suggestWin.closeSuggestWindow
      elif suggestList.suggestions.len == 1:
        # If there is only one candidate, remove the window and insert it.
        suggestWin.closeSuggestWindow
        status.commandLine.insertSuggestion(suggestList)
      elif suggestList.suggestions.len > 1:
        suggestWin.get.updateSuggestWindow(suggestList)
        status.commandLine.insertSuggestion(suggestList)

      status.commandLine.update
    else:
      status.update

    # TODO: Move to editorstatus.update?
    if currentBufStatus.isSearchMode:
      status.commandLine.buffer = status.searchHistory[suggestList.currentIndex]
      status.commandLine.update

    let key = status.getKeyFromCommandLine

    if isResizeKey(key):
      updateTerminalSize()
      status.resize
      continue
    elif isPasteKey(key):
      let pasteBuffer = getPasteBuffer()
      if pasteBuffer.isSome: status.insertPasteBuffer(pasteBuffer.get)
      continue

    if exCommandHistoryIndex.isResetExCommandHistoryIndex(key):
      exCommandHistoryIndex = none(int)

    if searchHistoryIndex.isResetSearchHistoryIndex(key):
      searchHistoryIndex = none(int)

    if isEscKey(key) or isCtrlC(key):
      isCancel = true
      if suggestWin.isSome:
        suggestWin.closeSuggestWindow
    elif isEnterKey(key):
      if suggestWin.isSome:
        suggestWin.closeSuggestWindow
        if suggestList.currentindex > -1:
          # Insert the current selection and continue the current mode.
          status.commandLine.insertSuggestion(suggestList)

          if isValidFileOpenCommand(status.commandLine.buffer):
            # If the command is valid command to open the file,
            # it will open the file immediately.
            break
      else:
        # Exit the current mode.
        break

    elif isTabKey(key):
      if currentBufStatus.isExMode:
        if suggestWin.isNone:
          suggestWin = status.commandLine.openSuggestWindow(suggestList)
        else:
          suggestList.incListIndex
        continue
    elif isShiftTab(key):
      if currentBufStatus.isExMode:
        if suggestWin.isNone:
          suggestWin = status.commandLine.openSuggestWindow(suggestList)
        else:
          suggestList.decListIndex
        continue

    elif isLeftKey(key):
      status.commandLine.moveLeft
    elif isRightKey(key):
      status.commandLine.moveRight
      if status.settings.standard.popupWindowInExmode:
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
    elif isDeleteKey(key):
      status.commandLine.deleteCurrentChar
    else:
      status.commandLine.insert(key)

    if status.settings.standard.incrementalSearch and
       currentBufStatus.isSearchMode:
         status.execSearchCommand(status.commandLine.buffer)
    elif status.isJumpAndHighlightInReplaceCommand:
      status.jumpAndHighlightInReplaceCommand

    if status.isIncrementalReplace:
      let info = parseReplaceCommand(status.commandLine.buffer)
      if incReplaceInfo.isNone:
        incReplaceInfo = IncrementalReplaceInfo(
          sub: info.sub,
          by: info.by,
          isGlobal: info.isGlobal,
          beforeLines: status.initBeforeLineForIncrementalReplace)
          .some
      elif incReplaceInfo.get.by != info.by or
           incReplaceInfo.get.isGlobal != info.isGlobal:
             # Restore lines before ex mode.
             for beforeLine in incReplaceInfo.get.beforeLines:
               currentBufStatus.buffer[beforeLine.lineNumber] = beforeLine.lineBuffer

             if incReplaceInfo.get.by != info.by:
               incReplaceInfo.get.beforeLines = status.initBeforeLineForIncrementalReplace
               incReplaceInfo.get.by = info.by

             if incReplaceInfo.get.isGlobal != info.isGlobal:
               incReplaceInfo.get.isGlobal = info.isGlobal

      status.execIncrementalReplace

    if suggestWin.isSome:
      suggestWin.closeSuggestWindow

  if isCancel:
    if incReplaceInfo.isSome:
      # Restore lines before ex mode.
      for beforeLine in incReplaceInfo.get.beforeLines:
        currentBufStatus.buffer[beforeLine.lineNumber] = beforeLine.lineBuffer

      currentBufStatus.isUpdate = true

    status.changeMode(currentBufStatus.prevMode)

    if currentBufStatus.isSearchMode:
      if status.searchHistory[^1].len == 0:
        status.searchHistory.delete(status.searchHistory.high)

      if status.settings.standard.incrementalSearch:
        status.isSearchHighlight = false
  else:
    if isExMode(currentBufStatus.mode):
      let command = status.commandLine.buffer

      let inputState = invokeCommand(
        currentBufStatus.mode,
        command,
        status.recodingOperationRegister)
      case inputState:
        of InputState.Valid:
          result = status.execEditorCommand(command)
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

proc close(suggestWin: var Option[SuggestionWindow]) {.inline.} =
  suggestWin.get.close
  suggestWin = none(SuggestionWindow)

proc isBeginNewSuit(bufStatus: BufferStatus): bool {.inline.} =
  not bufStatus.isInsertMode and not bufStatus.isReplaceMode

proc editorMainLoop*(status: var EditorStatus) =
  ## Get keys, exec commands and update view.

  status.resize

  var
    isSkipGetKey = false
    key: Rune
    command: Runes

  while mainWindow.numOfMainWindow > 0:
    if currentBufStatus.isEditMode:
      # Record undo/redo suit
      if currentBufStatus.isBeginNewSuit:
        currentBufStatus.buffer.beginNewSuitIfNeeded
        currentBufStatus.recordCurrentPosition(currentMainWindowNode)

    status.update

    if isSkipGetKey:
      isSkipGetKey = false
    else:
      key = status.getKeyFromMainWindow

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
    elif isPasteKey(key):
      let pasteBuffer = getPasteBuffer()
      if pasteBuffer.isSome: status.insertPasteBuffer(pasteBuffer.get)
      continue

    command.add key

    let inputState = invokeCommand(
      currentBufStatus.mode,
      command,
      status.recodingOperationRegister)
    case inputState:
      of InputState.Continue:
        continue
      of InputState.Valid:
        let interruptKey = status.execEditorCommand(command)
        if interruptKey.isSome:
          key = interruptKey.get
          isSkipGetKey = true

          command.clear
          continue
        else:
          command.clear
      of InputState.Invalid, InputState.Cancel:
        command.clear
        currentBufStatus.cmdLoop = 0
        continue

    if status.isOpenSuggestWindow:
      status.tryOpenSuggestWindow

    if currentBufStatus.isCommandLineMode:
      let interruptKey = status.commandLineLoop
      if interruptKey.isSome: key = interruptKey.get
      continue
