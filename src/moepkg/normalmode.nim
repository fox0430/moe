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

import std/[times, strutils, sequtils, options, strformat, tables, logging]
import pkg/results
import lsp/[client, utils]
import editorstatus, ui, gapbuffer, unicodeext, fileutils, windownode, movement,
       editor, searchutils, bufferstatus, quickrunutils, messages, visualmode,
       commandline, viewhighlight, messagelog, registers, independentutils,
       popupwindow

proc changeModeToInsertMode(status: var EditorStatus) {.inline.} =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    changeCursorType(status.settings.insertModeCursor)
    status.changeMode(Mode.insert)

proc changeModeToReplaceMode(status: var EditorStatus) {.inline.} =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    status.changeMode(Mode.replace)

proc changeModeToVisualMode(status: var EditorStatus) =
  status.changeMode(Mode.visual)
  currentBufStatus.selectedArea = initSelectedArea(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)

proc changeModeToVisualBlockMode(status: var EditorStatus) =
  status.changeMode(Mode.visualBlock)
  currentBufStatus.selectedArea = initSelectedArea(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)

proc changeModeToVisualLineMode(status: var EditorStatus) =
  status.changeMode(Mode.visualLine)
  currentBufStatus.selectedArea = initSelectedArea(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)

proc changeModeToExMode*(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) =

    bufStatus.changeMode(Mode.ex)
    commandLine.clear
    commandLine.setPrompt(ExModePrompt)

proc searchOneCharacterToEndOfLine(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  rune: Rune): int =

    result = -1

    let line = bufStatus.buffer[windowNode.currentLine]

    if line.len < 1 or isEscKey(rune) or
       (windowNode.currentColumn == line.high): return

    for col in windowNode.currentColumn + 1 ..< line.len:
      if line[col] == rune:
        result = col
        break

proc searchOneCharacterToBeginOfLine(
  bufStatus: var BufferStatus,
  windowNode: WindowNode,
  rune: Rune): int =

    result = -1

    let line = bufStatus.buffer[windowNode.currentLine]

    if line.len < 1 or isEscKey(rune) or (windowNode.currentColumn == 0): return

    for col in countdown(windowNode.currentColumn - 1, 0):
      if line[col] == rune:
        result = col
        break

proc searchHistoryLimit(status: EditorStatus): int {.inline.} =
  status.settings.persist.searchHistoryLimit

proc searchNextOccurrence(status: var EditorStatus, keyword: Runes) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.isSearchHighlight = true

  var highlight = currentMainWindowNode.highlight
  highlight.updateViewHighlight(
    currentBufStatus,
    currentMainWindowNode,
    status.isSearchHighlight,
    status.searchHistory,
    status.settings)

  status.bufStatus[currentBufferIndex].keyRight(currentMainWindowNode)

  status.searchHistory.saveSearchHistory(keyword, status.searchHistoryLimit)

  let
    ignorecase = status.settings.ignorecase
    smartcase = status.settings.smartcase
    searchResult = currentBufStatus.searchBuffer(
      currentMainWindowNode, keyword, ignorecase, smartcase)
  if searchResult.isSome:
    currentBufStatus.jumpLine(currentMainWindowNode, searchResult.get.line)
    for column in 0 ..< searchResult.get.column:
      status.bufStatus[currentBufferIndex].keyRight(currentMainWindowNode)
  else:
    currentMainWindowNode.keyLeft

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]

  status.searchNextOccurrence(keyword)

proc searchNextOccurrenceReversely(
  status: var EditorStatus,
  keyword: Runes) =

    status.isSearchHighlight = true

    var highlight = currentMainWindowNode.highlight
    highlight.updateViewHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    currentMainWindowNode.keyLeft

    status.searchHistory.saveSearchHistory(keyword, status.searchHistoryLimit)

    let
      ignorecase = status.settings.ignorecase
      smartcase = status.settings.smartcase
      searchResult = currentBufStatus.searchBufferReversely(
        currentMainWindowNode, keyword, ignorecase, smartcase)
    if searchResult.isSome:
      currentBufStatus.jumpLine(currentMainWindowNode, searchResult.get.line)
      for column in 0 ..< searchResult.get.column:
        currentBufStatus.keyRight(currentMainWindowNode)
    else:
      currentBufStatus.keyRight(currentMainWindowNode)

proc searchNextOccurrenceReversely(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[^1]

  status.searchNextOccurrenceReversely(keyword)

proc turnOffHighlighting*(status: var EditorStatus) =
  status.isSearchHighlight = false
  status.update

proc pageUpCommand(status: var EditorStatus): Option[Rune] =
  ## Interrupt scrolling and return a key If a key is pressed while scrolling.

  for i in 0 ..< currentBufStatus.cmdLoop:
    if status.settings.smoothScroll.enable:
      let interruptKey = status.smoothPageUp
      if interruptKey.isSome:
        return interruptKey
    else:
      status.pageUp

proc pageDownCommand(status: var EditorStatus): Option[Rune] =
  ## Interrupt scrolling and return a key If a key is pressed while scrolling.

  for i in 0 ..< currentBufStatus.cmdLoop:
    if status.settings.smoothScroll.enable:
      let interruptKey = status.smoothPageDown
      if interruptKey.isSome:
        return interruptKey
    else:
      status.pageDown

proc halfPageUpCommand(status: var EditorStatus): Option[Rune] =
  ## Interrupt scrolling and return a key If a key is pressed while scrolling.

  for i in 0 ..< currentBufStatus.cmdLoop:
    if status.settings.smoothScroll.enable:
      let interruptKey = status.smoothHalfPageUp
      if interruptKey.isSome:
        return interruptKey
    else:
      status.halfPageUp

proc halfPageDownCommand(status: var EditorStatus): Option[Rune] =
  ## Interrupt scrolling and return a key If a key is pressed while scrolling.

  for i in 0 ..< currentBufStatus.cmdLoop:
    if status.settings.smoothScroll.enable:
      let interruptKey = status.smoothHalfPageDown
      if interruptKey.isSome:
        return interruptKey
    else:
      status.halfPageDown

proc changeModeToNormalMode(status: var EditorStatus) =
  status.changeMode(Mode.normal)
  setBlinkingBlockCursor()

proc writeFileAndExit(status: var EditorStatus) =
  if currentBufStatus.path.len == 0:
    status.commandLine.writeNoFileNameError
    status.changeModeToNormalMode
  else:
    let r = saveFile(
      currentBufStatus.path,
      currentBufStatus.buffer.toRunes,
      currentBufStatus.characterEncoding)
    if r.isOk:
      status.closeWindow(currentMainWindowNode)
    else:
      status.commandLine.writeSaveError

proc forceExit(status: var EditorStatus) {.inline.} =
  status.closeWindow(currentMainWindowNode)

proc runQuickRunCommand(status: var EditorStatus) =
  let quickRunProcess = startBackgroundQuickRun(
    status.bufStatus[currentMainWindowNode.bufferIndex],
    status.settings)
  if quickRunProcess.isErr:
    status.commandLine.writeError(quickRunProcess.error.toRunes)
    addMessageLog quickRunProcess.error.toRunes
    return

  status.backgroundTasks.quickRun.add quickRunProcess.get

  let index = status.bufStatus.quickRunBufferIndex(quickRunProcess.get.filePath)

  if index.isSome:
    # Overwrite the quickrun buffer.
    status.bufStatus[index.get].buffer = quickRunStartupMessage(
      $status.bufStatus[index.get].path).toRunes.toGapBuffer
  else:
    # Open a new window and add a buffer for this quickrun.
    status.verticalSplitWindow
    status.resize
    status.moveNextWindow

    discard status.addNewBufferInCurrentWin
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.path = quickRunProcess.get.filePath.toRunes
    currentBufStatus.buffer[0] =
      quickRunStartupMessage($currentBufStatus.path).toRunes
    status.changeMode(Mode.quickRun)

    status.resize

  status.commandLine.writeRunQuickRunMessage(status.settings.notification)

proc yankWord(status: var EditorStatus) =
  currentBufStatus.yankWord(
    status.registers,
    currentMainWindowNode,
    currentBufStatus.cmdLoop,
    status.settings)

proc yankWord(status: var EditorStatus, registerName: string) =
  currentBufStatus.yankWord(
    status.registers,
   currentMainWindowNode,
   currentBufStatus.cmdLoop,
   registerName,
   status.settings)

proc deleteWord(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  currentBufStatus.deleteWord(
    currentMainWindowNode,
    currentBufStatus.cmdLoop,
    status.registers,
    RegisterName,
    status.settings)

proc deleteWord(status: var EditorStatus, registerName: string) =
  currentBufStatus.deleteWord(
    currentMainWindowNode,
    currentBufStatus.cmdLoop,
    status.registers,
    registerName,
    status.settings)

proc changeInnerCommand(status: var EditorStatus, key: Rune) =
  # # ci command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let
    currentLine = currentMainWindowNode.currentLine
    oldLine = currentBufStatus.buffer[currentLine]

  if isParen(key):
    # Delete inside paren and enter insert mode
    currentBufStatus.deleteInsideOfParen(
      currentMainWindowNode,
      status.registers,
      key,
      status.settings)

    if oldLine != currentBufStatus.buffer[currentLine]:
      currentMainWindowNode.currentColumn.inc
      status.changeModeToInsertMode
  elif key == ru'w':
    # Delete current word and enter insert mode
    if oldLine.len > 0:
      currentBufStatus.moveToBackwardWord(currentMainWindowNode)
      status.deleteWord
    status.changeModeToInsertMode
  else:
    discard

proc changeInnerCommand(
  status: var EditorStatus,
  key: Rune,
  registerName: string) =
    ## ci command

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    let
      currentLine = currentMainWindowNode.currentLine
      oldLine = currentBufStatus.buffer[currentLine]

    if isParen(key):
      # Delete inside paren and enter insert mode
      currentBufStatus.deleteInsideOfParen(
        currentMainWindowNode,
        status.registers,
        registerName,
        key,
        status.settings)

      if oldLine != currentBufStatus.buffer[currentLine]:
        currentMainWindowNode.currentColumn.inc
        status.changeModeToInsertMode
    elif key == ru'w':
      # Delete current word and enter insert mode
      if oldLine.len > 0:
        currentBufStatus.moveToBackwardWord(currentMainWindowNode)
        status.deleteWord
      status.changeModeToInsertMode
    else:
      discard

proc deleteInnerCommand(status: var EditorStatus, key: Rune, registerName: string) =
  ## di command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  if isParen(key):
    # Delete inside paren and enter insert mode
    if registerName.len > 0:
      currentBufStatus.deleteInsideOfParen(
        currentMainWindowNode,
        status.registers,
        registerName,
        key,
       status.settings)
    else:
      currentBufStatus.deleteInsideOfParen(
        currentMainWindowNode,
        status.registers,
        key,
       status.settings)

    currentBufStatus.keyRight(currentMainWindowNode)
  # Delete current word and enter insert mode
  elif key == ru'w':
    if currentBufStatus.buffer[currentMainWindowNode.currentLine].len > 0:
      currentBufStatus.moveToBackwardWord(currentMainWindowNode)
      status.deleteWord
  else:
    discard

proc deleteInnerCommand(status: var EditorStatus, key: Rune) =
  ## di command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  status.deleteInnerCommand(key, registerName)

proc showCurrentCharInfoCommand(
  status: var EditorStatus,
  windowNode: WindowNode) =

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      currentChar = currentBufStatus.buffer[currentLine][currentColumn]

    status.commandLine.writeCurrentCharInfo(currentChar)

proc yankLines(status: var EditorStatus, start, last: int) =
  let lastLine = min(
    last,
    currentBufStatus.buffer.high)

  currentBufStatus.yankLines(
    status.registers,
    status.commandLine,
    status.settings.notification,
    start, lastLine,
    status.settings)

proc yankLines(
  status: var EditorStatus,
  start, last: int,
  registerName: string) =

    let lastLine = min(
      last,
      currentBufStatus.buffer.high)

    currentBufStatus.yankLines(
      status.registers,
      status.commandLine,
      status.settings.notification,
      start, lastLine,
      registerName,
      status.settings)

proc yankLines(status: var EditorStatus) =
  ## yy command
  ## Ynak lines from the current line

  const RegisterName = ""
  let
    cmdLoop = currentBufStatus.cmdLoop
    currentLine = currentMainWindowNode.currentLine
    lastLine = min(currentLine + cmdLoop - 1, currentBufStatus.buffer.high)
  currentBufStatus.yankLines(
    status.registers,
    status.commandLine,
    status.settings.notification,
    currentLine, lastLine,
    RegisterName,
    status.settings)

proc yankLines(status: var EditorStatus, registerName: string) =
  ## Ynak lines from the current line

  let
    cmdLoop = currentBufStatus.cmdLoop
    currentLine = currentMainWindowNode.currentLine
    lastLine = min(currentLine + cmdLoop - 1, currentBufStatus.buffer.high)
  currentBufStatus.yankLines(
    status.registers,
    status.commandLine,
    status.settings.notification,
    currentLine, lastLine,
    registerName,
    status.settings)

proc yankToPreviousBlankLine(status: var EditorStatus, registerName: string) =
  ## y{ command

  let
    currentLine = currentMainWindowNode.currentLine
    previousBlankLine = currentBufStatus.findPreviousBlankLine(currentLine)
  status.yankLines(max(previousBlankLine, 0), currentLine, registerName)
  if previousBlankLine >= 0:
    currentBufStatus.jumpLine(currentMainWindowNode, previousBlankLine)

proc yankToPreviousBlankLine(status: var EditorStatus) =
  ## y{ command

  let
    currentLine = currentMainWindowNode.currentLine
    previousBlankLine = currentBufStatus.findPreviousBlankLine(currentLine)
  status.yankLines(max(previousBlankLine, 0), currentLine)
  if previousBlankLine >= 0:
    currentBufStatus.jumpLine(currentMainWindowNode, previousBlankLine)

proc yankToNextBlankLine(status: var EditorStatus, registerName: string) =
  ## y} command

  let
    currentLine = currentMainWindowNode.currentLine
    buffer = currentBufStatus.buffer
    nextBlankLine = currentBufStatus.findNextBlankLine(currentLine)
  status.yankLines(currentLine, min(nextBlankLine, buffer.high), registerName)
  if nextBlankLine >= 0:
    currentBufStatus.jumpLine(currentMainWindowNode, nextBlankLine)

proc yankToNextBlankLine(status: var EditorStatus) =
  ## y} command

  let
    currentLine = currentMainWindowNode.currentLine
    buffer = currentBufStatus.buffer
    nextBlankLine = currentBufStatus.findNextBlankLine(currentLine)
  status.yankLines(currentLine, min(nextBlankLine, buffer.high))
  if nextBlankLine >= 0:
    currentBufStatus.jumpLine(currentMainWindowNode, nextBlankLine)

proc deleteLines(status: var EditorStatus) =
  ## dd command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  let
    startLine = currentMainWindowNode.currentLine
    count = min(
      currentBufStatus.cmdLoop - 1,
      currentBufStatus.buffer.len - currentMainWindowNode.currentLine)
  currentBufStatus.deleteLines(
    status.registers,
   currentMainWindowNode,
   RegisterName,
   startLine,
   count,
   status.settings)

proc deleteLines(status: var EditorStatus, registerName: string) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let
    startLine = currentMainWindowNode.currentLine
    count = min(
      currentBufStatus.cmdLoop - 1,
      currentBufStatus.buffer.len - currentMainWindowNode.currentLine)
  currentBufStatus.deleteLines(
    status.registers,
   currentMainWindowNode,
   registerName,
   startLine,
   count,
   status.settings)

proc yankCharacters(status: var EditorStatus) =
  const
    RegisterName = ""
    IsDelete = false
  let
    buffer = currentBufStatus.buffer
    lineLen = buffer[currentMainWindowNode.currentLine].len
    width = lineLen - currentMainWindowNode.currentColumn
    length =
      if width > currentBufStatus.cmdLoop: currentBufStatus.cmdLoop
      else: width

  currentBufStatus.yankCharacters(
    status.registers,
    currentMainWindowNode,
    status.commandLine,
    status.settings,
    length,
    RegisterName,
    IsDelete)

proc yankCharacters(status: var EditorStatus, registerName: string) =
  const IsDelete = false
  let
    buffer = currentBufStatus.buffer
    lineLen = buffer[currentMainWindowNode.currentLine].len
    width = lineLen - currentMainWindowNode.currentColumn
    length =
      if width > currentBufStatus.cmdLoop: currentBufStatus.cmdLoop
      else: width

  currentBufStatus.yankCharacters(
    status.registers,
    currentMainWindowNode,
    status.commandLine,
    status.settings,
    length,
    registerName,
    IsDelete)

proc yankCharactersToCharacter(
  status: var EditorStatus,
  rune: Rune) =
    ## yt command

    let
      currentColumn = currentMainWindowNode.currentColumn
      # Get the position of a character
      position = currentBufStatus.searchOneCharacterToEndOfLine(
        currentMainWindowNode,
        rune)

    if position > currentColumn:
      const
        IsDelete = false
        RegisterName = ""
      currentBufStatus.yankCharacters(
        status.registers,
        currentMainWindowNode,
        status.commandLine,
        status.settings,
        position,
        RegisterName,
        IsDelete)

proc yankCharactersToCharacter(
  status: var EditorStatus,
  rune: Rune,
  registerName: string) =
    ## yt command

    let
      currentColumn = currentMainWindowNode.currentColumn
      # Get the position of a character
      position = currentBufStatus.searchOneCharacterToEndOfLine(
        currentMainWindowNode,
        rune)

    if position > currentColumn:
      const IsDelete = false
      currentBufStatus.yankCharacters(
        status.registers,
        currentMainWindowNode,
        status.commandLine,
        status.settings,
        position,
        registerName,
        IsDelete)

proc deleteCharacters(status: var EditorStatus, registerName: string) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.deleteCharacters(
    status.registers,
    registerName,
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn,
    currentBufStatus.cmdLoop,
    status.settings)

proc deleteCharacters(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  currentBufStatus.deleteCharacters(
    status.registers,
    RegisterName,
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn,
    currentBufStatus.cmdLoop,
    status.settings)

proc deleteCharactersUntilEndOfLine(
  status: var EditorStatus,
  registerName: string) =
    ## d$ command

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    let lineWidth =
      currentBufStatus.buffer[currentMainWindowNode.currentLine].len

    currentBufStatus.cmdLoop = lineWidth - currentMainWindowNode.currentColumn

    currentBufStatus.deleteCharacterUntilEndOfLine(
      status.registers,
      registerName,
      currentMainWindowNode,
      status.settings)

proc deleteCharactersUntilEndOfLine(status: var EditorStatus) =
  ## d$ command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  currentBufStatus.cmdLoop = lineWidth - currentMainWindowNode.currentColumn

  const RegisterName = ""
  currentBufStatus.deleteCharacterUntilEndOfLine(
    status.registers,
    RegisterName,
    currentMainWindowNode,
    status.settings)

proc deleteCharacterBeginningOfLine(
  status: var EditorStatus,
  registerName: string) =
    ## d0 command

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    currentBufStatus.deleteCharacterBeginningOfLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

proc deleteCharacterBeginningOfLine(status: var EditorStatus) =
  ## d0 command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  status.deleteCharacterBeginningOfLine(RegisterName)

proc deleteFromCurrentLineToLastLine(
  status: var EditorStatus,
  registerName: string) =
    ## dG command
    ## Yank and delete the line from current line to last line

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    let
      startLine = currentMainWindowNode.currentLine
      count = currentBufStatus.buffer.len - currentMainWindowNode.currentLine
    currentBufStatus.deleteLines(
      status.registers,
      currentMainWindowNode,
      registerName,
      startLine,
      count,
      status.settings)

proc deleteLineFromFirstLineToCurrentLine(
  status: var EditorStatus,
  registerName: string) =
    ## dgg command
    ## Delete the line from first line to current line

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    const StartLine = 0
    let count = currentMainWindowNode.currentLine
    currentBufStatus.deleteLines(
      status.registers,
      currentMainWindowNode,
      registerName,
      StartLine,
      count,
      status.settings)

    currentBufStatus.moveToFirstLine(currentMainWindowNode)

proc deleteTillPreviousBlankLine(
  status: var EditorStatus,
  registerName: string) =
    ## d{ command

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    currentBufStatus.deleteTillPreviousBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

proc deleteTillPreviousBlankLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  status.deleteTillPreviousBlankLine(RegisterName)

proc deleteTillNextBlankLine(
  status: var EditorStatus,
  registerName: string) =
    ## d} command

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    currentBufStatus.deleteTillNextBlankLine(
      status.registers,
      currentMainWindowNode,
      registerName,
      status.settings)

proc cutCharacterBeforeCursor(status: var EditorStatus, registerName: string) =
  ## X and dh command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  if currentMainWindowNode.currentColumn > 0:
    let
      currentColumn = currentMainWindowNode.currentColumn
      cmdLoop = currentBufStatus.cmdLoop
      loop =
        if currentColumn - cmdLoop > 0: cmdLoop
        else: currentColumn
    currentMainWindowNode.currentColumn = currentColumn - loop
    currentBufStatus.cmdLoop = loop

    status.deleteCharacters(registerName)

proc cutCharacterBeforeCursor(status: var EditorStatus) =
  ## X and dh command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  status.cutCharacterBeforeCursor(RegisterName)

proc deleteTillNextBlankLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  status.deleteTillNextBlankLine(RegisterName)

proc deleteLineFromFirstLineToCurrentLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  status.deleteLineFromFirstLineToCurrentLine(RegisterName)

proc deleteFromCurrentLineToLastLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  status.deleteFromCurrentLineToLastLine(RegisterName)

proc deleteCharacterAndEnterInsertMode(
  status: var EditorStatus,
  registerName: string) =
    ## s and cl commands

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    if currentBufStatus.buffer[currentMainWindowNode.currentLine].len > 0:
      let
        lineWidth =
          currentBufStatus.buffer[currentMainWindowNode.currentLine].len
        cmdLoop = currentBufStatus.cmdLoop
        loop = min(cmdLoop, lineWidth - currentMainWindowNode.currentColumn)
      currentBufStatus.cmdLoop = loop

      status.deleteCharacters(registerName)

    status.changeModeToInsertMode

proc deleteCharacterAndEnterInsertMode(status: var EditorStatus) =
  ## s and cl commands

  const RegisterName = ""
  status.deleteCharacterAndEnterInsertMode(RegisterName)

proc deleteCharactersAfterBlankInLine(status: var EditorStatus) =
  ## cc/S command

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const RegisterName = ""
  currentBufStatus.deleteCharactersAfterBlankInLine(
    status.registers,
    currentMainWindowNode,
    RegisterName,
    status.settings)

proc deleteCharactersToCharacterAndEnterInsertMode(
  status: var EditorStatus,
  rune: Rune,
  registerName: string) =
    ## cf command

    if currentBufStatus.isReadonly:
      status.commandLine.writeReadonlyModeWarning
      return

    let
      currentColumn = currentMainWindowNode.currentColumn
      # Get the position of a character
      position = currentBufStatus.searchOneCharacterToEndOfLine(
        currentMainWindowNode,
        rune)

    if position > currentColumn:
      currentBufStatus.cmdLoop = position - currentColumn + 1
      status.deleteCharacters

      status.changeModeToInsertMode

proc deleteCharactersToCharacterAndEnterInsertMode(
  status: var EditorStatus,
  rune: Rune) =
    ## cf command

    const RegisterName = ""
    status.deleteCharactersToCharacterAndEnterInsertMode(rune, RegisterName)

proc enterInsertModeAfterCursor(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  if lineWidth == 0: discard
  elif lineWidth == currentMainWindowNode.currentColumn: discard
  else: inc(currentMainWindowNode.currentColumn)
  status.changeModeToInsertMode

proc toggleCharacterAndMoveRight(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.toggleCharacters(
    currentMainWindowNode,
    currentBufStatus.cmdLoop)

proc replaceCurrentCharacter(status: var EditorStatus, newCharacter: Rune) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.replaceCharacters(
    currentMainWindowNode,
    status.settings.autoIndent,
    status.settings.autoDeleteParen,
    status.settings.tabStop,
    currentBufStatus.cmdLoop,
    newCharacter)

proc openBlankLineBelowAndEnterInsertMode(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.openBlankLineBelow(
    currentMainWindowNode,
    status.settings.autoIndent,
    status.settings.tabStop)
  status.changeModeToInsertMode

proc openBlankLineAboveAndEnterInsertMode(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.openBlankLineAbove(
    currentMainWindowNode,
    status.settings.autoIndent,
    status.settings.tabStop)

  var highlight = currentMainWindowNode.highlight
  highlight.updateViewHighlight(
    currentBufStatus,
    currentMainWindowNode,
    status.isSearchHighlight,
    status.searchHistory,
    status.settings)

  status.changeModeToInsertMode

proc moveToFirstNonBlankOfLineAndEnterInsertMode(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.moveToFirstNonBlankOfLine(currentMainWindowNode)
  status.changeModeToInsertMode

proc moveToEndOfLineAndEnterInsertMode(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let lineLen = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  currentMainWindowNode.currentColumn = lineLen
  status.changeModeToInsertMode

proc closeCurrentWindow(status: var EditorStatus) =
  if status.mainWindow.numOfMainWindow == 1: return

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if currentBufStatus.countChange == 0 or
     mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
    status.closeWindow(currentMainWindowNode)

proc hover(status: var EditorStatus) =
  ## Display info on a hover. Get info from the LSP server.
  ## Call textDocument/hover.
  ## TODO: Add tests after resolving the forever key waiting problem.

  if not status.lspClients.contains($currentBufStatus.extension) or
     not status.lspClients[$currentBufStatus.extension].isInitialized:
       debug "lsp client is not ready"
       return

  let r = status.lspClients[$currentBufStatus.extension].textDocumentHover(
    currentBufStatus.buffer.high,
    $currentBufStatus.path.absolutePath,
    currentMainWindowNode.bufferPosition)
  if r.isErr:
    status.commandLine.writeLspHoverError(r.error)
    return

  # Display info on a popup window.

  let hoverContent = r.get.toHoverContent
  var buffer: seq[Runes]
  if hoverContent.title.len > 0:
    buffer = @[hoverContent.title, ru""]
  for line in hoverContent.description:
    buffer.add line

  let
    absPositon = currentMainWindowNode.absolutePosition
    expectPosition = Position(y: absPositon.y + 1, x: absPositon.x + 1)
  var hoverWin = initPopupWindow(
    expectPosition,
    Size(h: buffer.len, w: buffer.maxLen),
    buffer)

  let
    minPosition = Position(y: mainWindowNode.y, x: mainWindowNode.x)
    maxPostion = Position(
      y: mainWindowNode.y + mainWindowNode.h,
      x: mainWindowNode.x + mainWindowNode.w)
  hoverWin.autoMoveAndResize(minPosition, maxPostion)
  hoverWin.update

  # Keep the cursor position on currentMainWindowNode and display the hover
  # window on the top.
  hoverWin.overlay(currentMainWindowNode.window.get)

  # Wait until any key is pressed.
  discard status.getKeyFromMainWindow
  hoverWin.close

proc addRegister(status: var EditorStatus, command, registerName: string) =
  if command == "yy":
    status.yankLines(registerName)
  elif command == "yl":
    status.yankCharacters(registerName)
  elif command == "yw":
    status.yankWord(registerName)
  elif command == "y{":
    status.yankToPreviousBlankLine(registerName)
  elif command == "y}":
    status.yankToNextBlankLine(registerName)
  elif command == "dd":
    status.deleteLines(registerName)
  elif command == "dw":
    status.deleteWord(registerName)
  elif command == "d$" or (command.len == 1 and isEndKey(command[0].toRune)):
    status.deleteCharactersUntilEndOfLine(registerName)
  elif command == "d0":
    status.deleteCharacterBeginningOfLine(registerName)
  elif command == "dG":
    status.deleteFromCurrentLineToLastLine(registerName)
  elif command == "dgg":
    status.deleteLineFromFirstLineToCurrentLine(registerName)
  elif command == "d{":
    status.deleteTillPreviousBlankLine(registerName)
  elif command == "d}":
    status.deleteTillNextBlankLine(registerName)
  elif command.len == 3 and command[0 .. 1] == "di":
    status.deleteInnerCommand(command[2].toRune, registerName)
  elif command == "dh":
    status.cutCharacterBeforeCursor(registerName)
  elif command == "cl" or command == "s":
    status.deleteCharacterAndEnterInsertMode(registerName)
  elif command.len == 3 and command[0 .. 1] == "ci":
    status.changeInnerCommand(command[2].toRune, registerName)
  elif command.len == 3 and command[0 .. 1] == "yt":
    status.yankCharactersToCharacter(command[2].toRune, registerName)
  elif command.len == 3 and command[0 .. 1] == "cf":
    status.deleteCharactersToCharacterAndEnterInsertMode(
      command[2].toRune,
      registerName)
  else:
    discard

proc pasteFromRegister(status: var EditorStatus, command, name: string) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  if name.len == 0: return

  case command:
    of "p":
      currentBufStatus.pasteAfterCursor(
        currentMainWindowNode,
        status.registers,
        name)
    of "P":
      currentBufStatus.pasteBeforeCursor(
        currentMainWindowNode,
        status.registers,
        name)
    else:
      discard

proc registerCommand(status: var EditorStatus, command: Runes) =
  var
    numberStr = ""
    currentIndex = 2
    registerName = command[1]

  # Check the number of times the command is repeated
  if isDigit(command[2]):
    while isDigit(command[currentIndex]):
      numberStr &= $command[currentIndex]
      inc(currentIndex)

  let cmd = $command[currentIndex .. ^1]
  currentBufStatus.cmdLoop =
    if numberStr == "": 1
    else: numberStr.parseInt

  if cmd == "p" or cmd == "P":
    status.pasteFromRegister(cmd, $registerName)
  elif cmd == "yy" or
       cmd == "yw" or
       cmd == "yl" or
       cmd == "y{" or
       cmd == "y}" or
       cmd == "dd" or
       cmd == "dw" or
       cmd == "d$" or (cmd.len == 1 and isEndKey(command[0])) or
       cmd == "d0" or
       cmd == "dG" or
       cmd == "dgg" or
       cmd == "d{" or
       cmd == "d}" or
       (cmd.len == 3 and cmd[0 .. 1] == "di") or
       cmd == "dh" or
       cmd == "cl" or cmd == "s" or
       (cmd.len == 3 and cmd[0 .. 1] == "ci") or
       (cmd.len == 3 and cmd[0 .. 1] == "yt") or
       (cmd.len == 3 and cmd[0 .. 1] == "cf"):
         status.addRegister(cmd, $registerName)

proc pasteAfterCursor(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)
proc pasteBeforeCursor(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

proc startRecordingOperations(status: var EditorStatus, name: Rune) =
  ## Start recoding editor operations for macro.

  if isOperationRegisterName(name):
    discard clearOperationToRegister(name).get
    status.recodingOperationRegister = some(name)
  else:
    let errMess = fmt"Error: Invalid operation register name: {name}"
    addMessageLog errMess.toRunes

proc stopRecordingOperations(status: var EditorStatus) =
  status.recodingOperationRegister = none(Rune)
  status.commandLine.clear

proc isStopRecordingOperationsCommand*(
  bufStatus: BufferStatus,
  command: Runes): bool {.inline.} =

    bufStatus.mode.isNormalMode and $command == "q"

proc isMovementKey(key: Rune): bool {.inline.} =
  isControlK(key) or
  isControlJ(key) or
  isControlV(key) or
  key == ord('h') or isLeftKey(key) or isBackspaceKey(key) or
  key == ord('l') or isRightKey(key) or
  key == ord('k') or isUpKey(key) or
  key == ord('j') or isDownKey(key) or
  isEnterKey(key) or
  key == ord('^') or key == ord('_') or
  key == ord('0') or isHomeKey(key) or
  key == ord('$') or isEndKey(key) or
  key == ord('-') or
  key == ord('+') or
  key == ord('G') or
  isControlU(key) or
  isControlD(key) or
  isPageUpKey(key) or
  isPageDownKey(key) or
  key == ord('w') or
  key == ord('b') or
  key == ord('e') or
  key == ord('{') or
  key == ord('}')

proc isChangeModeKey(key: Rune): bool {.inline.} =
   key == ord('v') or
   isControlV(key) or
   key == ord('R') or
   key == ord('i') or
   key == ord('I') or
   key == ord('a') or
   key == ord('A')

proc changeModeToSearchForwardMode(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) =

    bufStatus.changeMode(Mode.searchForward)
    commandLine.clear
    commandLine.setPrompt(SearchForwardModePrompt)

proc changeModeToSearchBackwardMode(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) =

    bufStatus.changeMode(Mode.searchBackward)
    commandLine.clear
    commandLine.setPrompt(SearchBackwardModePrompt)

proc normalCommand(status: var EditorStatus, commands: Runes): Option[Rune] =
  ## Exec normal mode commands.
  ## Return the key typed during command execution if needed.

  if commands.len == 0:
    return
  elif isControlC(commands[^1]):
    # Cnacel commands and show the exit help
    status.commandLine.writeExitHelp
  elif commands.len > 1 and isEscKey(commands[0]):
    # Remove ECS key and call recursively.
    discard status.normalCommand(commands[1..commands.high])

  if currentBufStatus.cmdLoop == 0: currentBufStatus.cmdLoop = 1

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    cmdLoop = currentBufStatus.cmdLoop

    key = commands[0]

  if isControlK(key):
    status.moveNextWindow
  elif isControlJ(key):
    status.movePrevWindow
  elif isControlV(key):
    status.changeModeToVisualBlockMode
  elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< cmdLoop: currentMainWindowNode.keyLeft
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< cmdLoop: currentBufStatus.keyRight(currentMainWindowNode)
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< cmdLoop: currentBufStatus.keyUp(currentMainWindowNode)
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< cmdLoop: currentBufStatus.keyDown(currentMainWindowNode)
  elif key == ord('x') or isDcKey(key):
    status.deleteCharacters
  elif key == ord('X'):
    status.cutCharacterBeforeCursor
  elif key == ord('^') or key == ord('_'):
    currentBufStatus.moveToFirstNonBlankOfLine(currentMainWindowNode)
  elif key == ord('0') or isHomeKey(key):
    currentMainWindowNode.moveToFirstOfLine
  elif key == ord('$') or isEndKey(key):
    currentBufStatus.moveToLastOfLine(currentMainWindowNode)
  elif key == ord('-'):
    currentBufStatus.moveToFirstOfPreviousLine(currentMainWindowNode)
  elif key == ord('+'):
    currentBufStatus.moveToFirstOfNextLine(currentMainWindowNode)
  elif key == ord('{'):
    currentBufStatus.moveToPreviousBlankLine(currentMainWindowNode)
  elif key == ord('}'):
    currentBufStatus.moveToNextBlankLine(currentMainWindowNode)
  elif key == ord('g'):
    let secondKey = commands[1]
    if secondKey == ord('g'):
      currentBufStatus.jumpLine(currentMainWindowNode, cmdLoop - 1)
    elif secondKey == ord('_'):
      currentBufStatus.moveToLastNonBlankOfLine(currentMainWindowNode)
    elif secondKey == ord('a'):
      status.showCurrentCharInfoCommand(currentMainWindowNode)
  elif key == ord('G'):
    currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif isControlU(key):
    return status.halfPageUpCommand
  elif isControlD(key):
    return status.halfPageDownCommand
  elif isPageUpKey(key):
    return status.pageUpCommand
  elif isPageDownKey(key): ## Page down and Ctrl - F
    return status.pageDownCommand
  elif key == ord('w'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.moveToForwardWord(currentMainWindowNode)
  elif key == ord('b'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.moveToBackwardWord(currentMainWindowNode)
  elif key == ord('e'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
  elif key == ord('z'):
    let secondKey = commands[1]
    if secondKey == ord('.'):
      currentBufStatus.scrollScreenCenter(currentMainWindowNode)
    elif secondKey == ord('t'):
      currentBufStatus.scrollScreenTop(currentMainWindowNode)
    elif secondKey == ord('b'):
      currentBufStatus.scrollScreenBottom(currentMainWindowNode)
  elif key == ord('H'):
    currentBufStatus.moveToTopOfScreen(currentMainWindowNode)
  elif key == ord('M'):
    currentBufStatus.moveToCenterOfScreen(currentMainWindowNode)
  elif key == ord('L'):
    currentBufStatus.moveToBottomOfScreen(currentMainWindowNode)
  elif key == ord('%'):
    currentBufStatus.moveToPairOfParen(currentMainWindowNode)
  elif key == ord('o'):
    status.openBlankLineBelowAndEnterInsertMode
  elif key == ord('O'):
    status.openBlankLineAboveAndEnterInsertMode
  elif key == ord('c'):
    let secondKey = commands[1]
    if secondKey == ord('c'):
      status.deleteCharactersAfterBlankInLine
      status.enterInsertModeAfterCursor
    elif secondKey == ord('l'):
      status.deleteCharacterAndEnterInsertMode
    elif secondKey == ord('i'):
      let thirdKey = commands[2]
      if isParen(thirdKey) or
         thirdKey == ord('w'):
        status.changeInnerCommand(thirdKey)
    elif secondKey == ord('f'):
      let thirdKey = commands[2]
      status.deleteCharactersToCharacterAndEnterInsertMode(thirdKey)
  elif key == ord('d'):
    let secondKey = commands[1]
    if secondKey == ord('d'):
      status.deleteLines
    elif secondKey == ord('w'):
      status.deleteWord
    elif secondKey == ('$') or isEndKey(secondKey):
      status.deleteCharactersUntilEndOfLine
    elif secondKey == ('0') or isHomeKey(secondKey):
     status.deleteCharacterBeginningOfLine
    elif secondKey == ord('G'):
      status.deleteFromCurrentLineToLastLine
    elif secondKey == ord('g'):
      let thirdKey = commands[2]
      if thirdKey == ord('g'):
        status.deleteLineFromFirstLineToCurrentLine
    elif secondKey == ord('{'):
      status.deleteTillPreviousBlankLine
    elif secondKey == ord('}'):
      status.deleteTillNextBlankLine
    elif secondKey == ord('i'):
      let thirdKey = commands[2]
      status.deleteInnerCommand(thirdKey)
    elif secondKey == ord('h'):
      status.cutCharacterBeforeCursor
  elif key == ord('D'):
     status.deleteCharactersUntilEndOfLine
  elif key == ord('S'):
     status.deleteCharactersAfterBlankInLine
     status.enterInsertModeAfterCursor
  elif key == ord('s'):
    status.deleteCharacterAndEnterInsertMode
  elif key == ord('y'):
    let secondKey = commands[1]
    if secondKey == ord('y'):
      status.yankLines
    elif secondKey == ord('w'):
      status.yankWord
    elif secondKey == ord('{'):
      status.yankToPreviousBlankLine
    elif secondKey == ord('}'):
      status.yankToNextBlankLine
    elif secondKey == ord('l'):
      status.yankCharacters
    elif secondKey == ord('t'):
      let thirdKey = commands[2]
      status.yankCharactersToCharacter(thirdKey)
  elif key == ord('Y'):
    status.yankLines
  elif key == ord('p'):
    status.pasteAfterCursor
  elif key == ord('P'):
    status.pasteBeforeCursor
  elif key == ord('>'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.indent(currentMainWindowNode, status.settings.tabStop)
  elif key == ord('<'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.unindent(currentMainWindowNode, status.settings.tabStop)
  elif key == ord('='):
    let secondKey = commands[1]
    if secondKey == ord('='):
      currentBufStatus.autoIndentCurrentLine(currentMainWindowNode)
  elif key == ord('J'):
    currentBufStatus.joinLine(currentMainWindowNode)
  elif isControlA(key):
    currentBufStatus.modifyNumberTextUnderCurosr(currentMainWindowNode, cmdLoop)
  elif isControlX(key):
    currentBufStatus.modifyNumberTextUnderCurosr(currentMainWindowNode,
                                                 -cmdLoop)
  elif key == ord('~'):
    status.toggleCharacterAndMoveRight
  elif key == ord('r'):
    status.replaceCurrentCharacter(commands[1])
  elif key == ord('n'):
    status.searchNextOccurrence
  elif key == ord('N'):
    status.searchNextOccurrenceReversely
  elif key == ord('*'):
    let word = currentBufStatus.getWordUnderCursor(currentMainWindowNode)[1]
    status.searchNextOccurrence(word)
  elif key == ord('#'):
    let word = currentBufStatus.getWordUnderCursor(currentMainWindowNode)[1]
    status.searchNextOccurrenceReversely(word)
  elif key == ord('f'):
    let secondKey = commands[1]
    let pos =
      currentBufStatus.searchOneCharacterToEndOfLine(
        currentMainWindowNode,
        secondKey)
    if pos != -1:
      currentMainWindowNode.currentColumn = pos
  elif key == ord('t'):
    let secondKey = commands[1]
    let pos =
      currentBufStatus.searchOneCharacterToEndOfLine(
        currentMainWindowNode,
        secondKey)
    if pos != -1:
      currentMainWindowNode.currentColumn = pos - 1
  elif key == ord('F'):
    let secondKey = commands[1]
    let pos =
      currentBufStatus.searchOneCharacterToBeginOfLine(
        currentMainWindowNode,
        secondKey)
    if pos != -1:
      currentMainWindowNode.currentColumn = pos
  elif key == ord('T'):
    let secondKey = commands[1]
    let pos =
      currentBufStatus.searchOneCharacterToBeginOfLine(
        currentMainWindowNode,
        secondKey)
    if pos != -1:
      currentMainWindowNode.currentColumn = pos + 1
  elif key == ord('R'):
    status.changeModeToReplaceMode
  elif key == ord('i'):
    status.changeModeToInsertMode
  elif key == ord('I'):
    status.moveToFirstNonBlankOfLineAndEnterInsertMode
  elif key == ord('v'):
    status.changeModeToVisualMode
  elif key == ord('V'):
    status.changeModeToVisualLineMode
  elif key == ord('a'):
    status.enterInsertModeAfterCursor
  elif key == ord('A'):
    status.moveToEndOfLineAndEnterInsertMode
  elif key == ord('u'):
    status.bufStatus[currentBufferIndex].undo(currentMainWindowNode)
  elif isControlR(key):
    currentBufStatus.redo(currentMainWindowNode)
  elif key == ord('Z'):
    let secondKey = commands[1]
    if  secondKey == ord('Z'):
      status.writeFileAndExit
    elif secondKey == ord('Q'):
      status.forceExit
  elif isControlW(key):
    let secondKey = commands[1]
    if secondKey == ord('c'):
      status.closeCurrentWindow
  elif key == ord('\\'):
    let secondKey = commands[1]
    if secondKey == ord('r'): status.runQuickRunCommand
  elif key == ord('"'):
    status.registerCommand(commands)
  elif key == ord('q'):
    if commands.len == 1: status.stopRecordingOperations
    elif commands.len == 2: status.startRecordingOperations(commands[1])
  elif key == ord('K'):
    status.hover
  else:
    return

  addOperationToNormalModeOperationsRegister(commands)

proc isNormalModeCommand*(
  command: Runes,
  recodingOperationRegister: Option[Rune]): InputState =

    result = InputState.Invalid

    if command.len == 0:
      return InputState.Continue
    elif isControlC(command[^1]):
      result = InputState.Valid
    elif isEscKey(command[0]):
      if command.len == 1:
        result = InputState.Continue
      elif command.len == 2 and isEscKey(command[1]):
        result = InputState.Valid
      else:
        # Remove ECS key and call recursively.
        return isNormalModeCommand(
          command[1 .. command.high],
          recodingOperationRegister)

    elif isEscKey(command[^1]):
      # Cancel commands.
      result = InputState.Invalid

    else:
      if $command == "/" or
         $command == "?" or
         $command == ":" or
         isControlK(command) or
         isControlJ(command) or
         isControlV(command) or
         $command == "h" or isLeftKey(command) or isBackspaceKey(command[0]) or
         $command == "l" or isRightKey(command) or
         $command == "k" or isUpKey(command) or
         $command == "j" or isDownKey(command) or
         isEnterKey(command) or
         $command == "x" or isDcKey(command) or
         $command == "X" or
         $command == "^" or $command == "_" or
         $command == "0" or isHomeKey(command) or
         $command == "$" or isEndKey(command) or
         $command == "{" or
         $command == "}" or
         $command == "-" or
         $command == "+" or
         $command == "G" or
         isControlU(command) or
         isControlD(command) or
         isPageUpKey(command) or
         ## Page down and Ctrl - F
         isPageDownKey(command) or
         $command == "w" or
         $command == "b" or
         $command == "e" or
         $command == "o" or
         $command == "O" or
         $command == "D" or
         $command == "S" or
         $command == "s" or
         $command == "p" or
         $command == "P" or
         $command == ">" or
         $command == "<" or
         $command == "J" or
         isControlA(command) or
         isControlX(command) or
         $command == "~" or
         $command == "n" or
         $command == "N" or
         $command == "*" or
         $command == "#" or
         $command == "R" or
         $command == "i" or
         $command == "I" or
         $command == "v" or
         $command == "a" or
         $command == "A" or
         $command == "u" or
         isControlR(command) or
         $command == "." or
         $command == "Y" or
         $command == "V" or
         $command == "H" or
         $command == "M" or
         $command == "L" or
         $command == "%" or
         $command == "K":
           result = InputState.Valid

      elif isDigit(command[0]):
        # Remove numbers and call recursively.
        var i = 0
        while i < command.high and command[i].isDigit: i.inc
        if i == command.high:
          result = InputState.Continue
        else:
          return isNormalModeCommand(
            command[i .. command.high],
            recodingOperationRegister)

      elif command[0] == ord('g'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          if command[1] == ord('g') or
             command[1] == ord('_') or
             command[1] == ord('a'):
               result = InputState.Valid

      elif command[0] == ord('z'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          if command[1] == ord('.') or
             command[1] == ord('t') or
             command[1] == ord('b'):
               result = InputState.Valid

      elif command[0] == ord('c'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          if command[1] == ord('i') or
             command[1] == ord('f'):
               result = InputState.Continue
          elif command[1] == ord('c') or command[1] == ('l'):
            result = InputState.Valid
        elif command.len == 3:
          if command[1] == ord('f') or
             (command[1] == ord('i') and
             (isParen(command[2]) or command[2] == ord('w'))):
               result = InputState.Valid

      elif command[0] == ord('d'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          if command[1] == ord('d') or
             command[1] == ord('w') or
             command[1] == ord('$') or isEndKey(command[1]) or
             command[1] == ord('0') or isHomeKey(command[1]) or
             command[1] == ord('G') or
             command[1] == ord('{') or
             command[1] == ord('}'):
               result = InputState.Valid
          elif command[1] == ord('g') or command[1] == ord('i'):
            result = InputState.Continue
        elif command.len == 3:
          if command[2] == ord('g'):
            result = InputState.Valid
          elif command[1] == ord('i'):
            if isParen(command[2]) or
               command[2] == ord('w'):
                 result = InputState.Valid

      elif command[0] == ord('y'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          if command[1] == ord('y') or
             command[1] == ord('w') or
             command[1] == ord('{') or
             command[1] == ord('}') or
             command[1] == ord('l'):
            result = InputState.Valid
          elif command == "yt".ru:
            result = InputState.Continue
        elif command.len == 3:
          if command[0 .. 1] == "yt".ru:
            result = InputState.Valid

      elif command[0] == ord('='):
        if command.len == 1:
          result = InputState.Continue
        elif command[1] == ord('='):
          result = InputState.Valid

      elif command[0] == ord('r'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          result = InputState.Valid

      elif command[0] == ord('f'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          result = InputState.Valid

      elif command[0] == ord('t'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          result = InputState.Valid

      elif command[0] == ord('F'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          result = InputState.Valid

      elif command[0] == ord('T'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          result = InputState.Valid

      elif command[0] == ord('Z'):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          if command[1] == ord('Z') or command[1] == ord('Q'):
            result = InputState.Valid

      elif isControlW(command[0]):
        if command.len == 1:
          result = InputState.Continue
        elif command.len == 2:
          if command[1] == ord('c'):
            result = InputState.Valid

      elif command[0] == ('\\'):
        if command.len == 1:
          result = InputState.Continue
        elif command[1] == ord('r'):
          result = InputState.Valid

      elif command[0] == ord('"'):
        if command.len < 3:
          result = InputState.Continue
        else:
          block:
            let ch = char(command[2])
            if not (ch in Letters and isDigit(ch)):
              result = InputState.Invalid

          var
            currentIndex = 2
            ch = char(command[currentIndex])
          while ch in Digits and currentIndex < command.len:
            inc(currentIndex)
            ch = char(command[currentIndex])

          let cmd = $command[currentIndex .. ^1]
          if cmd == "y" or
             cmd == "d" or
             cmd == "dg" or
             cmd == "di" or
             cmd == "c" or
             cmd == "ci":
               result = InputState.Continue
          elif cmd == "p" or
               cmd == "P" or
               cmd == "yy" or
               cmd == "yw" or
               cmd == "yl" or
               cmd == "y{" or
               cmd == "y}" or
               cmd == "dd" or
               cmd == "dw" or
               cmd == "d$" or (cmd.len == 1 and isEndKey(cmd[0].toRune)) or
               cmd == "d0" or
               cmd == "dG" or
               cmd == "dgg" or
               cmd == "d{" or
               cmd == "d}" or
               (cmd.len == 3 and cmd[0 .. 1] == "di") or
               cmd == "dh" or
               cmd == "cl" or cmd == "s" or
               (cmd.len == 3 and cmd[0 .. 1] == "ci"):
                 result = InputState.Valid

      elif command[0] == 'q':
        if command.len == 1:
          if recodingOperationRegister.isSome:
            result = InputState.Valid
          else:
            result = InputState.Continue
        elif command.len == 2:
          let ch = char(command[1])
          if ch >= 'a' and ch <= 'z':
            result = InputState.Valid
          else:
            result = InputState.Invalid

      elif command[0] == '@':
        if command.len == 1:
            result = InputState.Continue
        elif command.len == 2:
          if isOperationRegisterName(command[1]):
            result = InputState.Valid
          else:
            result = InputState.Invalid

proc repeatNormalModeCommand(status: var EditorStatus): Option[Rune] =
  ## Exec the last used normal mode command.
  ## Not executed for movement and mode change commands.
  ## Return the key typed during command execution if needed.

  let command = getLatestNormalModeOperation()
  if command.isSome:
    if not isMovementKey(command.get[0]) and
       not isChangeModeKey(command.get[0]):
         result = status.normalCommand(command.get)

proc execNormalModeCommand*(
  status: var EditorStatus,
  command: Runes): Option[Rune] =

    status.lastOperatingTime = now()

    if $command == "/":
      currentBufStatus.changeModeToSearchForwardMode(status.commandLine)
    elif $command == "?":
      currentBufStatus.changeModeToSearchBackwardMode(status.commandLine)
    elif $command == ":":
      currentBufStatus.changeModeToExMode(status.commandLine)
    elif $command == ".":
      result = status.repeatNormalModeCommand
    elif isEscKey(command[0]):
      if command.len == 2 and isEscKey(command[1]):
        status.turnOffHighlighting
      else:
        # Remove ECS key and call recursively.
        discard status.execNormalModeCommand(command[1..command.high])
    else:
      if command[0] != '0' and isDigit(command[0]):
        currentBufStatus.cmdLoop = parseInt($command.filterIt(isDigit(it)))

      let cmd =
        if command[0] != '0' and isDigit(command[0]):
          command.filterIt(not isDigit(it))
        else:
          command
      result = status.normalCommand(cmd)

    currentBufStatus.cmdLoop = 0
