#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2024 Shuhei Nogawa                                       #
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

import std/[options, times, sequtils]

import pkg/results

import lsp/[client, utils]
import editorstatus, bufferstatus, windownode, unicodeext, gapbuffer, ui,
       normalmode, visualmode, insertmode, exmode, filermode, replacemode,
       buffermanager, recentfilemode, quickrun, backupmanager, diffviewer,
       configmode, debugmode, commandline, search, commandlineutils,
       popupwindow, messages, filermodeutils, editor, registers, exmodeutils,
       movement, searchutils, independentutils, lsp, viewhighlight, completion,
       completionwindow, worddictionary

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
      of Mode.normal, Mode.logViewer, Mode.help:
        isNormalModeCommand(command, recodingOperationRegister)
      of Mode.visual, Mode.visualBlock, Mode.visualLine:
        isVisualModeCommand(command)
      of Mode.replace:
        isReplaceModeCommand(command)
      of Mode.filer:
        isFilerModeCommand(command)
      of Mode.bufManager:
        isBufferManagerCommand(command)
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
    of Mode.normal, Mode.logViewer, Mode.help:
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

proc isExecMacroCommand(
  bufStatus: BufferStatus,
  registers: Registers,
  commands: Runes): bool =

    if bufStatus.mode.isNormalMode and commands.len > 1:
      if commands[0].isDigit:
        # If the first word (text) is a number, it is considered as the number
        # repetitions.
        var i = 0
        while i < commands.high and commands[i].isDigit: i.inc
        if commands.len - i == 2:
          return commands[i] == ord('@') and
            isOperationRegisterName(commands[i + 1]) and
            registers.getOperations(commands[i + 1]).get.commands.len > 0
      else:
        return commands.len == 2 and
          commands[0] == ord('@') and
          isOperationRegisterName(commands[1]) and
          registers.getOperations(commands[1]).get.commands.len > 0

proc execMacro(status: var EditorStatus, name: Rune) =
  ## Exec commands from the operationRegister.

  if isOperationRegisterName(name):
    let operations = status.registers.getOperations(name).get
    for c in operations.commands:
      discard status.execCommand(c)
      status.update

proc execEditorCommand(status: var EditorStatus, command: Runes): Option[Rune] =
  ## Exec editor commands.
  ## Return the key typed during command execution if needed.

  if status.recodingOperationRegister.isSome:
    if not isStopRecordingOperationsCommand(currentBufStatus, command):
      discard status.registers.addOperation(
        status.recodingOperationRegister.get,
        command).get

  status.lastOperatingTime = now()

  if isExecMacroCommand(currentBufStatus, status.registers, command):
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
    if pasteBuffer.len == 1:
      status.registers.setYankedRegister(pasteBuffer[0])
    else:
      status.registers.setYankedRegister(pasteBuffer)

    if currentBufStatus.isInsertMode:
      currentBufStatus.pasteAfterCursor(
        currentMainWindowNode,
        status.registers)
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
  ## Jump and highlight in replace command.
  ## Don't highlight and jump if info.sub is confirmed.

  let info = parseReplaceCommand(status.commandLine.buffer)
  if info.sub.len > 0 and info.by.len == 0:
    status.highlightingText = HighlightingText(
      kind: HighlightingTextKind.replace,
      text: info.sub.replaceToNewLines.splitLines)
      .some

    currentBufStatus.jumpToSearchForwardResults(
      currentMainWindowNode,
      info.sub,
      status.settings.standard.ignorecase,
      status.settings.standard.smartcase)

proc isReplaceCommand(status: EditorStatus): bool {.inline.} =
  ## Return true if the valid replace command ("%s/xxx/yyy").

  currentBufStatus.isExMode and
  status.commandLine.buffer.startsWith(ru"%s/") and
  status.commandLine.buffer.count(ru'/') > 1 and
  status.commandLine.buffer.count(ru'/') < 4

proc isIncrementalReplace(status: EditorStatus): bool {.inline.} =
  status.settings.standard.incrementalSearch and
  status.isReplaceCommand

proc initBeforeLineForIncrementalReplace(
  status: var EditorStatus): seq[BeforeLine] =

    let info = parseReplaceCommand(status.commandLine.buffer)
    if info.sub.len > 0 and info.by.len > 0:
      let positons = currentBufStatus.buffer.toSeqRunes.searchAllOccurrence(
        info.sub,
        false,
        false)
      for p in positons:
        if result.len == 0 or result[^1].lineNumber != p.line:
          result.add BeforeLine(
            lineNumber: p.line,
            lineBuffer: currentBufStatus.buffer[p.line])

proc isUpdateIncReplceInfo(
  incReplaceInfo: IncrementalReplaceInfo,
  replaceCommandInfo: ReplaceCommandInfo): bool {.inline.} =

    incReplaceInfo.by != replaceCommandInfo.by or
    incReplaceInfo.isGlobal != replaceCommandInfo.isGlobal

proc restoreLinesFromBeforeLines(
  bufStatus: var BufferStatus,
  beforeLines: seq[BeforeLine]) {.inline.} =
    ## Restore lines from beforeLines.

    for line in beforeLines:
      bufStatus.buffer[line.lineNumber] = line.lineBuffer

proc execIncrementalReplace(
  status: var EditorStatus,
  incReplaceInfo: IncrementalReplaceInfo) {.inline.} =

    status.replaceBuffer((
      sub: incReplaceInfo.sub,
      by: incReplaceInfo.by,
      isGlobal: incReplaceInfo.isGlobal))

proc incrementalReplace(
  status: var EditorStatus,
  incReplaceInfo: var Option[IncrementalReplaceInfo]) =
    ## Update IncrementalReplaceInfo and replacing buffer.

    let info = parseReplaceCommand(status.commandLine.buffer)
    if incReplaceInfo.isNone:
      # Init IncrementalReplaceInfo
      incReplaceInfo = IncrementalReplaceInfo(
        sub: info.sub,
        by: info.by,
        isGlobal: info.isGlobal,
        beforeLines: status.initBeforeLineForIncrementalReplace)
        .some
      status.execIncrementalReplace(incReplaceInfo.get)
    elif incReplaceInfo.get.isUpdateIncReplceInfo(info):
      # Update IncrementalReplaceInfo

      # Restore lines before ex mode.
      currentBufStatus.restoreLinesFromBeforeLines(
        incReplaceInfo.get.beforeLines)

      if incReplaceInfo.get.by != info.by:
        incReplaceInfo.get.by = info.by
        incReplaceInfo.get.beforeLines =
          status.initBeforeLineForIncrementalReplace

      if incReplaceInfo.get.isGlobal != info.isGlobal:
        incReplaceInfo.get.isGlobal = info.isGlobal

      status.execIncrementalReplace(incReplaceInfo.get)

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
      currentBufStatus.isExMode and
      status.commandLine.buffer.startsWith(ru"%s/")

  if currentBufStatus.isSearchMode:
    status.searchHistory.add "".toRunes

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
      status.incrementalReplace(incReplaceInfo)

    if suggestWin.isSome:
      suggestWin.closeSuggestWindow

    if currentBufStatus.isSearchMode:
      status.highlightingText = HighlightingText(
        kind: HighlightingTextKind.search,
        text: status.searchHistory[^1].replaceToNewLines.splitLines,
        isIgnorecase: status.settings.standard.ignorecase,
        isSmartcase: status.settings.standard.smartcase)
        .some

  if isCancel:
    if currentBufStatus.isSearchMode:
      if status.searchHistory[^1].len == 0:
        status.searchHistory.delete(status.searchHistory.high)

      status.highlightingText = none(HighlightingText)
      currentBufStatus.isUpdate = true

    elif incReplaceInfo.isSome:
      # Restore lines before ex mode.
      for beforeLine in incReplaceInfo.get.beforeLines:
        currentBufStatus.buffer[beforeLine.lineNumber] = beforeLine.lineBuffer

      status.highlightingText = none(HighlightingText)
      currentBufStatus.isUpdate = true

    status.changeMode(currentBufStatus.prevMode)
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

template isBeginNewSuit(bufStatus: BufferStatus): bool =
  not bufStatus.isInsertMode and not bufStatus.isReplaceMode

template isOpenCompletionWindow(status: EditorStatus, key: Rune): bool =
  status.completionwindow.isNone and
  status.settings.autocomplete.enable and
  currentBufStatus.isInsertMode and
  isCompletionCharacter(key)

proc completionWindowPosition(status: var EditorStatus): Position {.inline.} =
  currentMainWindowNode.completionWindowPosition(currentBufStatus)

proc openCompletionWindow(status: var EditorStatus) =
  var bufferPosition = currentMainWindowNode.bufferPosition
  bufferPosition.column.dec

  status.completionWindow = some(initCompletionWindow(
    startPosition = bufferPosition,
    windowPosition = status.completionWindowPosition,
    list = currentBufStatus.lspCompletionList))

template closeCompletionWindow(status: var EditorStatus) =
  ## Close the completion window and reset completionList.

  status.completionWindow.get.close
  status.completionWindow = none(CompletionWindow)

  currentBufStatus.lspCompletionList.clear

proc updateCompletionWindowBuffer(status: var EditorStatus) =
  ## Update the buffer for the completion window and move, resize the
  ## completion window.

  if status.completionWindow.get.selectedIndex > -1:
    # Remove the temporary selection from the buffer before update.

    if currentBufStatus.isInsertMultiMode:
      let lines = currentBufStatus.selectedArea.get.selectedLineNumbers
      currentBufStatus.removeInsertedText(status.completionWindow.get, lines)
      status.completionWindow.get.selectedIndex = -1
      currentBufStatus.insertSelectedText(status.completionWindow.get, lines)
    else:
      currentBufStatus.removeInsertedText(status.completionWindow.get)
      status.completionWindow.get.selectedIndex = -1
      currentBufStatus.insertSelectedText(status.completionWindow.get)

    currentMainWindowNode.currentColumn =
      status.completionWindow.get.startColumn

  let
    # Calc min/max positions for the completion window.
    minPosition = Position(
      y: currentMainWindowNode.y,
      x: currentMainWindowNode.x)
    maxPosition = Position(
      y: currentMainWindowNode.y + currentMainWindowNode.h - 1,
      x: currentMainWindowNode.x + currentMainWindowNode.w)

  if status.completionWindow.get.isPathCompletion:
    status.completionWindow.get.setList pathCompletionList(
      status.completionWindow.get.inputText)
  elif currentBufStatus.lspCompletionList.len == 0:
    # If LSP completion items are not found, get items from WordDictionary.
    status.wordDictionary.update(
      status.bufStatus.mapIt(it.buffer.toRunes),
      status.completionWindow.get.inputText,
      currentBufStatus.language)
    status.completionWindow.get.setList status.wordDictionary
  else:
    status.completionWindow.get.setList currentBufStatus.lspCompletionList

  if status.completionWindow.get.list.len > 0:
    if status.completionWindow.get.popupWindow.isNone:
      status.completionWindow.get.reopen(status.completionWindowPosition)

    status.completionWindow.get.updateBuffer
    status.completionWindow.get.autoMoveAndResize(minPosition, maxPosition)
    status.completionWindow.get.update
  else:
    # Temporary close the ncurses window
    status.completionWindow.get.close

proc confirmCompletion(status: var EditorStatus) =
  ## Insert the selected suggestion to the buffer and close the completion
  ## window.

  if status.completionWindow.get.selectedIndex > -1:
    currentBufStatus.isUpdate = true
    currentBufStatus.countChange.inc

  status.closeCompletionWindow

template isConfirmCompletionAndContinue(
  status: var EditorStatus,
  key: Rune): bool =

    isCompletionCharacter(key) and
    status.completionWindow.get.selectedIndex > -1

proc confirmCompletionAndContinue(status: var EditorStatus) =
  ## Confirm the current selected and continue the completion.

  status.completionWindow.get.inputText =
    status.completionWindow.get.selectedText
  status.completionWindow.get.selectedIndex = -1

template isChangeModeToInsert(b: BufferStatus, prevMode: Mode): bool =
 b.mode.isInsertMode and not prevMode.isInsertMode

template resetKeyAndContinue(key: var Option[Rune]) =
  key = none(Rune)
  continue

template isUpdateCompletionWindow(
  status: EditorStatus,
  beforeWaitingResponse: Option[LspMethod]): bool =

    status.completionWindow.isSome and
    beforeWaitingResponse == some(LspMethod.textDocumentCompletion) and
    lspClient.waitingResponse.isNone

proc editorMainLoop*(status: var EditorStatus) =
  ## Get keys, exec commands and update view.

  status.resize

  var
    isSkipGetKey = false
    key: Option[Rune]
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
      # Wait a key and check background tasks, LSP response.
      while key.isNone:
        const Timeout = 100 # 100 milliseconds
        key = currentMainWindowNode.getKey(Timeout)

        status.runBackgroundTasks
        if status.bufStatus.isUpdate:
          break

        if status.isLspResponse:
          let beforeWaitingResponse = lspClient.waitingResponse
          status.handleLspResponse

          if status.isUpdateCompletionWindow(beforeWaitingResponse):
            status.updateCompletionWindowBuffer

          break

      if key.isSome:
        if isResizeKey(key.get):
          updateTerminalSize()
          status.resize
          key.resetKeyAndContinue
        elif isPasteKey(key.get):
          let pasteBuffer = getPasteBuffer()
          if pasteBuffer.isSome: status.insertPasteBuffer(pasteBuffer.get)
          key.resetKeyAndContinue

        var isClosedCompletionWindow = false
        if status.completionWindow.isSome:
          if canHandleInCompletionWindow(key.get):
            status.completionWindow.get.handleKey(
              currentBufStatus,
              currentMainWindowNode,
              key.get)
            key.resetKeyAndContinue
          else:
            if isEnterKey(key.get):
              status.confirmCompletion
              key = none(Rune)
              isClosedCompletionWindow = true
            elif isConfirmCompletionAndContinue(status, key.get):
              status.confirmCompletionAndContinue
            elif isEscKey(key.get):
              status.confirmCompletion
            elif isBackspaceKey(key.get):
              status.confirmCompletionAndContinue
            elif not isCompletionCharacter(key.get):
              status.confirmCompletion
              isClosedCompletionWindow = true

        command.add key.get

        let inputState = invokeCommand(
          currentBufStatus.mode,
          command,
          status.recodingOperationRegister)
        case inputState:
          of InputState.Continue:
            key.resetKeyAndContinue
          of InputState.Valid:
            let prevMode = currentBufStatus.mode

            let interruptKey = status.execEditorCommand(command)
            if interruptKey.isSome:
              key = some(interruptKey.get)
              isSkipGetKey = true

              command.clear
              continue
            elif currentBufStatus.isChangeModeToInsert(prevMode):
              # Skip recording the key to the completionWindow when changing
              # the mode to Insert.
              command.clear
              key.resetKeyAndContinue
            else:
              command.clear
          of InputState.Invalid, InputState.Cancel:
            command.clear
            currentBufStatus.cmdLoop = 0
            key.resetKeyAndContinue

        if not isClosedCompletionWindow and
           status.isOpenCompletionWindow(key.get):
             status.openCompletionWindow()

        if status.completionWindow.isSome:
          if not currentBufStatus.isInsertMode:
            status.closeCompletionWindow
          elif isBackspaceKey(key.get):
            if status.completionWindow.get.inputText.len == 1:
              status.closeCompletionWindow
            else:
              status.completionWindow.get.removeInput
              status.updateCompletionWindowBuffer
          else:
            status.completionWindow.get.addInput(key.get)
            status.updateCompletionWindowBuffer

        key = none(Rune)

      if currentBufStatus.isCommandLineMode:
        let interruptKey = status.commandLineLoop
        if interruptKey.isSome: key = some(interruptKey.get)
        continue
