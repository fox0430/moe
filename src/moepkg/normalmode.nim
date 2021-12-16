import std/[terminal, times, strutils]
import editorstatus, ui, gapbuffer, unicodeext, fileutils, undoredostack,
       window, movement, editor, search, bufferstatus, quickrun,
       messages

type InputState = enum
  Continue
  Valid
  Invalid

proc searchOneCharacterToEndOfLine(bufStatus: var BufferStatus,
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

proc searchOneCharacterToBeginOfLine(bufStatus: var BufferStatus,
                                     windowNode: WindowNode,
                                     rune: Rune): int =
  result = -1

  let line = bufStatus.buffer[windowNode.currentLine]

  if line.len < 1 or isEscKey(rune) or (windowNode.currentColumn == 0): return

  for col in countdown(windowNode.currentColumn - 1, 0):
    if line[col] == rune:
      result = col
      break

proc searchNextOccurrence(status: var EditorStatus, keyword: seq[Rune]) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  status.isSearchHighlight = true

  var highlight = currentMainWindowNode.highlight
  highlight.updateHighlight(
    currentBufStatus,
    currentMainWindowNode,
    status.isSearchHighlight,
    status.searchHistory,
    status.settings)

  status.bufStatus[currentBufferIndex].keyRight(currentMainWindowNode)
  let
    ignorecase = status.settings.ignorecase
    smartcase = status.settings.smartcase
    searchResult = status.searchBuffer(keyword, ignorecase, smartcase)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column:
      status.bufStatus[currentBufferIndex].keyRight(currentMainWindowNode)
  elif searchResult.line == -1: currentMainWindowNode.keyLeft

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]

  status.searchNextOccurrence(keyword)

proc searchNextOccurrenceReversely(status: var EditorStatus, keyword: seq[Rune]) =
  status.isSearchHighlight = true

  var highlight = currentMainWindowNode.highlight
  highlight.updateHighlight(
    currentBufStatus,
    currentMainWindowNode,
    status.isSearchHighlight,
    status.searchHistory,
    status.settings)

  var windowNode = currentMainWindowNode

  windowNode.keyLeft
  let
    ignorecase = status.settings.ignorecase
    smartcase = status.settings.smartcase
    searchResult = status.searchBufferReversely(keyword, ignorecase, smartcase)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column:
      currentBufStatus.keyRight(windowNode)
  elif searchResult.line == -1:
    currentBufStatus.keyRight(windowNode)

proc searchNextOccurrenceReversely(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[^1]

  status.searchNextOccurrenceReversely(keyword)

proc turnOffHighlighting*(status: var EditorStatus) =
  status.isSearchHighlight = false
  status.update

proc writeFileAndExit(status: var EditorStatus, height, width: int) =
  if currentBufStatus.path.len == 0:
    status.commandLine.writeNoFileNameError(status.messageLog)
    status.changeMode(Mode.normal)
  else:
    try:
      saveFile(currentBufStatus.path,
               currentBufStatus.buffer.toRunes,
               currentBufStatus.characterEncoding)
      status.closeWindow(currentMainWindowNode, height, width)
    except IOError:
      status.commandLine.writeSaveError(status.messageLog)

proc forceExit(status: var Editorstatus, height, width: int) {.inline.} =
  status.closeWindow(currentMainWindowNode, height, width)

proc runQuickRunCommand(status: var Editorstatus) =
  let
    buffer = runQuickRun(status.bufStatus[currentMainWindowNode.bufferIndex],
                         status.commandLine,
                         status.messageLog,
                         status.settings)
    quickRunWindowIndex = status.bufStatus.getQuickRunBufferIndex(mainWindowNode)

  if quickRunWindowIndex == -1:
    status.verticalSplitWindow
    status.resize(terminalHeight(), terminalWidth())
    status.moveNextWindow

    status.addNewBuffer("")
    status.bufStatus[^1].buffer = initGapBuffer(buffer)

    status.changeCurrentBuffer(status.bufStatus.high)

    status.changeMode(Mode.quickRun)
  else:
    status.bufStatus[quickRunWindowIndex].buffer = initGapBuffer(buffer)

proc yankWord(status: var EditorStatus) =
  currentBufStatus.yankWord(status.registers,
                            currentMainWindowNode,
                            currentBufStatus.cmdLoop,
                            status.settings)

proc yankWord(status: var EditorStatus, registerName: string) =
  currentBufStatus.yankWord(status.registers,
                            currentMainWindowNode,
                            currentBufStatus.cmdLoop,
                            registerName,
                            status.settings)

proc deleteWord(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  currentBufStatus.deleteWord(
    currentMainWindowNode,
    currentBufStatus.cmdLoop,
    status.registers,
    registerName,
    status.settings)

proc deleteWord(status: var EditorStatus, registerName: string) =
  currentBufStatus.deleteWord(
    currentMainWindowNode,
    currentBufStatus.cmdLoop,
    status.registers,
    registerName,
    status.settings)

# ci command
proc changeInnerCommand(status: var EditorStatus, key: Rune) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let
    currentLine = currentMainWindowNode.currentLine
    oldLine = currentBufStatus.buffer[currentLine]

  # Delete inside paren and enter insert mode
  if isParen(key):
    currentBufStatus.deleteInsideOfParen(
      currentMainWindowNode,
      status.registers,
      key,
      status.settings)

    if oldLine != currentBufStatus.buffer[currentLine]:
      currentMainWindowNode.currentColumn.inc
      status.changeMode(Mode.insert)
  # Delete current word and enter insert mode
  elif key == ru'w':
    if oldLine.len > 0:
      currentBufStatus.moveToBackwardWord(currentMainWindowNode)
      status.deleteWord
    status.changeMode(Mode.insert)
  else:
    discard

# ci command
proc changeInnerCommand(status: var EditorStatus,
                        key: Rune,
                        registerName: string) =

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let
    currentLine = currentMainWindowNode.currentLine
    oldLine = currentBufStatus.buffer[currentLine]

  # Delete inside paren and enter insert mode
  if isParen(key):
    currentBufStatus.deleteInsideOfParen(
      currentMainWindowNode,
      status.registers,
      registerName,
      key,
      status.settings)

    if oldLine != currentBufStatus.buffer[currentLine]:
      currentMainWindowNode.currentColumn.inc
      status.changeMode(Mode.insert)
  # Delete current word and enter insert mode
  elif key == ru'w':
    if oldLine.len > 0:
      currentBufStatus.moveToBackwardWord(currentMainWindowNode)
      status.deleteWord
    status.changeMode(Mode.insert)
  else:
    discard

# di command
proc deleteInnerCommand(status: var EditorStatus, key: Rune, registerName: string) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  # Delete inside paren and enter insert mode
  if isParen(key):
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

# di command
proc deleteInnerCommand(status: var EditorStatus, key: Rune) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  status.deleteInnerCommand(key, registerName)

proc showCurrentCharInfoCommand(status: var EditorStatus,
                                windowNode: WindowNode) =

  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
    currentChar = currentBufStatus.buffer[currentLine][currentColumn]

  status.commandLine.writeCurrentCharInfo(currentChar)

proc normalCommand(status: var EditorStatus,
                   commands: seq[Rune],
                   height, width: int)

proc repeatNormalModeCommand(status: var Editorstatus, height, width: int) =
  if status.normalCommandHistory.len == 0: return

  let commands  = status.normalCommandHistory[^1]
  status.normalCommand(commands, height, width)

proc yankLines(status: var Editorstatus, start, last: int) =
  let lastLine = min(last,
                     currentBufStatus.buffer.high)

  currentBufStatus.yankLines(status.registers,
                             status.commandLine,
                             status.messageLog,
                             status.settings.notificationSettings,
                             start, lastLine,
                             status.settings)

proc yankLines(status: var Editorstatus, start, last: int, registerName: string) =
  let lastLine = min(last,
                     currentBufStatus.buffer.high)

  currentBufStatus.yankLines(status.registers,
                             status.commandLine,
                             status.messageLog,
                             status.settings.notificationSettings,
                             start, lastLine,
                             registerName,
                             status.settings)

# yy command
# Ynak lines from the current line
proc yankLines(status: var Editorstatus) =
  const registerName = ""
  let
    cmdLoop = currentBufStatus.cmdLoop
    currentLine = currentMainWindowNode.currentLine
    lastLine = min(currentLine + cmdLoop - 1, currentBufStatus.buffer.high)
  currentBufStatus.yankLines(status.registers,
                             status.commandLine,
                             status.messageLog,
                             status.settings.notificationSettings,
                             currentLine, lastLine,
                             registerName,
                             status.settings)

# Ynak lines from the current line
proc yankLines(status: var Editorstatus, registerName: string) =
  let
    cmdLoop = currentBufStatus.cmdLoop
    currentLine = currentMainWindowNode.currentLine
    lastLine = min(currentLine + cmdLoop - 1, currentBufStatus.buffer.high)
  currentBufStatus.yankLines(status.registers,
                             status.commandLine,
                             status.messageLog,
                             status.settings.notificationSettings,
                             currentLine, lastLine,
                             registerName,
                             status.settings)

# y{ command
proc yankToPreviousBlankLine(status: var EditorStatus, registerName: string) =
  let
    currentLine = currentMainWindowNode.currentLine
    previousBlankLine = currentBufStatus.findPreviousBlankLine(currentLine)
  status.yankLines(max(previousBlankLine, 0), currentLine, registerName)
  if previousBlankLine >= 0: status.jumpLine(previousBlankLine)

# y{ command
proc yankToPreviousBlankLine(status: var EditorStatus) =
  let
    currentLine = currentMainWindowNode.currentLine
    previousBlankLine = currentBufStatus.findPreviousBlankLine(currentLine)
  status.yankLines(max(previousBlankLine, 0), currentLine)
  if previousBlankLine >= 0: status.jumpLine(previousBlankLine)

# y} command
proc yankToNextBlankLine(status: var EditorStatus, registerName: string) =
  let
    currentLine = currentMainWindowNode.currentLine
    buffer = currentBufStatus.buffer
    nextBlankLine = currentBufStatus.findNextBlankLine(currentLine)
  status.yankLines(currentLine, min(nextBlankLine, buffer.high), registerName)
  if nextBlankLine >= 0: status.jumpLine(nextBlankLine)

# y} command
proc yankToNextBlankLine(status: var EditorStatus) =
  let
    currentLine = currentMainWindowNode.currentLine
    buffer = currentBufStatus.buffer
    nextBlankLine = currentBufStatus.findNextBlankLine(currentLine)
  status.yankLines(currentLine, min(nextBlankLine, buffer.high))
  if nextBlankLine >= 0: status.jumpLine(nextBlankLine)

# dd command
proc deleteLines(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  let
    startLine = currentMainWindowNode.currentLine
    count = min(
      currentBufStatus.cmdLoop - 1,
      currentBufStatus.buffer.len - currentMainWindowNode.currentLine)
  currentBufStatus.deleteLines(status.registers,
                               currentMainWindowNode,
                               registerName,
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
  currentBufStatus.deleteLines(status.registers,
                               currentMainWindowNode,
                               registerName,
                               startLine,
                               count,
                               status.settings)

proc yankCharacters(status: var Editorstatus) =
  const
    registerName = ""
    isDelete = false
  let
    buffer = currentBufStatus.buffer
    lineLen = buffer[currentMainWindowNode.currentLine].len
    width = lineLen - currentMainWindowNode.currentColumn
    length = if width > currentBufStatus.cmdLoop: currentBufStatus.cmdLoop
             else: width

  currentBufStatus.yankCharacters(
    status.registers,
    currentMainWindowNode,
    status.commandLine,
    status.messageLog,
    status.settings,
    length,
    registerName,
    isDelete)

# name is the register name
proc yankCharacters(status: var Editorstatus, registerName: string) =
  const isDelete = false
  let
    buffer = currentBufStatus.buffer
    lineLen = buffer[currentMainWindowNode.currentLine].len
    width = lineLen - currentMainWindowNode.currentColumn
    length = if width > currentBufStatus.cmdLoop: currentBufStatus.cmdLoop
             else: width

  currentBufStatus.yankCharacters(
    status.registers,
    currentMainWindowNode,
    status.commandLine,
    status.messageLog,
    status.settings,
    length,
    registerName,
    isDelete)

# yt command
proc yankCharactersToCharacter(status: var EditorStatus,
                               rune: Rune) =

  let
    currentColumn = currentMainWindowNode.currentColumn
    # Get the position of a character
    position = currentBufStatus.searchOneCharacterToEndOfLine(
      currentMainWindowNode,
      rune)

  if position > currentColumn:
    const
      isDelete = false
      registerName = ""
    currentBufStatus.yankCharacters(
      status.registers,
      currentMainWindowNode,
      status.commandLine,
      status.messageLog,
      status.settings,
      position,
      registerName,
      isDelete)

# yt command
proc yankCharactersToCharacter(status: var EditorStatus,
                               rune: Rune,
                               registerName: string) =

  let
    currentColumn = currentMainWindowNode.currentColumn
    # Get the position of a character
    position = currentBufStatus.searchOneCharacterToEndOfLine(
      currentMainWindowNode,
      rune)

  if position > currentColumn:
    const isDelete = false
    currentBufStatus.yankCharacters(
      status.registers,
      currentMainWindowNode,
      status.commandLine,
      status.messageLog,
      status.settings,
      position,
      registerName,
      isDelete)

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

  const registerName = ""
  currentBufStatus.deleteCharacters(
    status.registers,
    registerName,
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn,
    currentBufStatus.cmdLoop,
    status.settings)

# d$ command
proc deleteCharactersUntilEndOfLine(status: var EditorStatus,
                                    registerName: string) =

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  currentBufStatus.cmdLoop = lineWidth - currentMainWindowNode.currentColumn

  currentBufStatus.deleteCharacterUntilEndOfLine(
    status.registers,
    registerName,
    currentMainWindowNode,
    status.settings)

# d$ command
proc deleteCharactersUntilEndOfLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  currentBufStatus.cmdLoop = lineWidth - currentMainWindowNode.currentColumn

  const registerName = ""
  currentBufStatus.deleteCharacterUntilEndOfLine(
    status.registers,
    registerName,
    currentMainWindowNode,
    status.settings)

# d0 command
proc deleteCharacterBeginningOfLine(status: var EditorStatus,
                                    registerName: string) =

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.deleteCharacterBeginningOfLine(
    status.registers,
    currentMainWindowNode,
    registerName,
    status.settings)

# d0 command
proc deleteCharacterBeginningOfLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  status.deleteCharacterBeginningOfLine(registerName)

# dG command
# Yank and delete the line from current line to last line
proc deleteFromCurrentLineToLastLine(status: var EditorStatus,
                                     registerName: string) =

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let
    startLine = currentMainWindowNode.currentLine
    count = currentBufStatus.buffer.len - currentMainWindowNode.currentLine
  currentBufStatus.deleteLines(status.registers,
                               currentMainWindowNode,
                               registerName,
                               startLine,
                               count,
                               status.settings)

# dgg command
# Delete the line from first line to current line
proc deleteLineFromFirstLineToCurrentLine(status: var EditorStatus,
                                          registerName: string) =

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const startLine = 0
  let count = currentMainWindowNode.currentLine
  currentBufStatus.deleteLines(status.registers,
                               currentMainWindowNode,
                               registerName,
                               startLine,
                               count,
                               status.settings)

  status.moveToFirstLine

# d{ command
proc deleteTillPreviousBlankLine(status: var EditorStatus,
                                 registerName: string) =

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

  const registerName = ""
  status.deleteTillPreviousBlankLine(registerName)

# d} command
proc deleteTillNextBlankLine(status: var EditorStatus,
                             registerName: string) =

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.deleteTillNextBlankLine(
    status.registers,
    currentMainWindowNode,
    registerName,
    status.settings)

# X and dh command
proc cutCharacterBeforeCursor(status: var EditorStatus, registerName: string) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  if currentMainWindowNode.currentColumn > 0:
    let
      currentColumn = currentMainWindowNode.currentColumn
      cmdLoop = currentBufStatus.cmdLoop
      loop = if currentColumn - cmdLoop > 0: cmdLoop
             else: currentColumn
    currentMainWindowNode.currentColumn = currentColumn - loop
    currentBufStatus.cmdLoop = loop

    status.deleteCharacters(registerName)

# X and dh command
proc cutCharacterBeforeCursor(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  status.cutCharacterBeforeCursor(registerName)

proc deleteTillNextBlankLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  status.deleteTillNextBlankLine(registerName)

proc deleteLineFromFirstLineToCurrentLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  status.deleteLineFromFirstLineToCurrentLine(registerName)

proc deleteFromCurrentLineToLastLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  status.deleteFromCurrentLineToLastLine(registerName)

# s and cl commands
proc deleteCharacterAndEnterInsertMode(status: var EditorStatus,
                                       registerName: string) =

  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  if currentBufStatus.buffer[currentMainWindowNode.currentLine].len > 0:
    let
      lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
      cmdLoop = currentBufStatus.cmdLoop
      loop = min(cmdLoop, lineWidth - currentMainWindowNode.currentColumn)
    currentBufStatus.cmdLoop = loop

    status.deleteCharacters(registerName)

  status.changeMode(Mode.insert)

# s and cl commands
proc deleteCharacterAndEnterInsertMode(status: var EditorStatus) =
  const registerName = ""
  status.deleteCharacterAndEnterInsertMode(registerName)

# cc/S command
proc deleteCharactersAfterBlankInLine(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  const registerName = ""
  currentBufStatus.deleteCharactersAfterBlankInLine(
    status.registers,
    currentMainWindowNode,
    registerName,
    status.settings)

# cf command
proc deleteCharactersToCharacterAndEnterInsertMode(status: var EditorStatus,
                                                   rune: Rune,
                                                   registerName: string) =

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

    status.changeMode(Mode.insert)

# cf command
proc deleteCharactersToCharacterAndEnterInsertMode(status: var EditorStatus,
                                                   rune: Rune) =

  const registerName = ""
  status.deleteCharactersToCharacterAndEnterInsertMode(rune, registerName)

proc enterInsertModeAfterCursor(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  if lineWidth == 0: discard
  elif lineWidth == currentMainWindowNode.currentColumn: discard
  else: inc(currentMainWindowNode.currentColumn)
  status.changeMode(Mode.insert)

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

  currentBufStatus.openBlankLineBelow(currentMainWindowNode,
                                      status.settings.autoIndent,
                                      status.settings.tabStop)
  status.changeMode(Mode.insert)

proc openBlankLineAboveAndEnterInsertMode(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.openBlankLineAbove(currentMainWindowNode,
                                      status.settings.autoIndent,
                                      status.settings.tabStop)

  var highlight = currentMainWindowNode.highlight
  highlight.updateHighlight(
    currentBufStatus,
    currentMainWindowNode,
    status.isSearchHighlight,
    status.searchHistory,
    status.settings)

  status.changeMode(Mode.insert)

proc moveToFirstNonBlankOfLineAndEnterInsertMode(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  currentBufStatus.moveToFirstNonBlankOfLine(currentMainWindowNode)
  status.changeMode(Mode.insert)

proc moveToEndOfLineAndEnterInsertMode(status: var EditorStatus) =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
    return

  let lineLen = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  currentMainWindowNode.currentColumn = lineLen
  status.changeMode(Mode.insert)

proc closeCurrentWindow(status: var EditorStatus, height, width: int) =
  if status.mainWindow.numOfMainWindow == 1: return

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if currentBufStatus.countChange == 0 or
     mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
    status.closeWindow(currentMainWindowNode, height, width)

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

proc registerCommand(status: var EditorStatus, command: seq[Rune]) =
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
  currentBufStatus.cmdLoop = if numberStr == "": 1
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

proc pasteAfterCursor(status: var EditorStatus) {.inline.} =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    currentBufStatus.pasteAfterCursor(currentMainWindowNode, status.registers)

proc pasteBeforeCursor(status: var EditorStatus) {.inline.} =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    currentBufStatus.pasteBeforeCursor(currentMainWindowNode, status.registers)

proc isMovementKey(key: Rune): bool =
  return isControlK(key) or
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
         isPageUpkey(key) or
         isPageDownKey(key) or
         key == ord('w') or
         key == ord('b') or
         key == ord('e') or
         key == ord('{') or
         key == ord('}')

proc isChangeModeKey(key: Rune): bool =
   return key == ord('v') or
          isControlV(key) or
          key == ord('R') or
          key == ord('i') or
          key == ord('I') or
          key == ord('a') or
          key == ord('A')

proc changeModeToInsertMode(status: var EditorStatus) {.inline.} =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    status.changeMode(Mode.insert)

proc changeModeToReplaceMode(status: var EditorStatus) {.inline.} =
  if currentBufStatus.isReadonly:
    status.commandLine.writeReadonlyModeWarning
  else:
    status.changeMode(Mode.replace)

proc changeModeToVisualMode(status: var EditorStatus) {.inline.} =
  status.changeMode(Mode.visual)

proc changeModeToVisualBlockMode(status: var EditorStatus) {.inline.} =
  status.changeMode(Mode.visualBlock)

proc normalCommand(status: var EditorStatus,
                   commands: seq[Rune],
                   height, width: int) =

  if commands.len == 0: return

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
    status.moveToPreviousBlankLine
  elif key == ord('}'):
    status.moveToNextBlankLine
  elif key == ord('g'):
    let secondKey = commands[1]
    if secondKey == ord('g'):
      status.jumpLine(cmdLoop - 1)
    elif secondKey == ord('_'):
      currentBufStatus.moveToLastNonBlankOfLine(currentMainWindowNode)
    elif secondKey == ord('a'):
      status.showCurrentCharInfoCommand(currentMainWindowNode)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isControlU(key):
    for i in 0 ..< cmdLoop: status.halfPageUp
  elif isControlD(key):
    for i in 0 ..< cmdLoop: status.halfPageDown
  elif isPageUpkey(key):
    for i in 0 ..< cmdLoop: status.pageUp
  elif isPageDownKey(key): ## Page down and Ctrl - F
    for i in 0 ..< cmdLoop: status.pageDown
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
      currentBufStatus.moveCenterScreen(currentMainWindowNode)
    elif secondKey == ord('t'):
      currentBufStatus.scrollScreenTop(currentMainWindowNode)
    elif secondKey == ord('b'):
      currentBufStatus.scrollScreenBottom(currentMainWindowNode)
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
      currentBufStatus.addIndent(currentMainWindowNode, status.settings.tabStop)
  elif key == ord('<'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.deleteIndent(currentMainWindowNode, status.settings.tabStop)
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
      status.writeFileAndExit(height, width)
    elif secondKey == ord('Q'):
      status.forceExit(height, width)
  elif isControlW(key):
    let secondKey = commands[1]
    if secondKey == ord('c'):
      status.closeCurrentWindow(height, width)
  elif key == ord('.'):
    status.repeatNormalModeCommand(height, width)
  elif key == ord('\\'):
    let secondKey = commands[1]
    if secondKey == ord('r'): status.runQuickRunCommand
  elif key == ord('"'):
    status.registerCommand(commands)
  else:
    return

  # Record normal mode commands
  if commands[0] != ord('.') and
     not isMovementKey(commands[0]) and
     not isChangeModeKey(commands[0]):
    status.normalCommandHistory.add commands

# Get a key and execute the event loop
proc getKey(status: var Editorstatus): Rune =
  result = errorKey
  while result == errorKey:
    if not pressCtrlC:
      status.eventLoopTask
      result = getKey(currentMainWindowNode)
    else:
      pressCtrlC = false
      status.commandLine.writeExitHelp
      status.update

proc isNormalModeCommand(command: seq[Rune]): InputState =
  result = InputState.Invalid

  if command.len == 0:
    result = InputState.Continue
  else:
    if isControlK(command[0]) or
       isControlJ(command[0]) or
       isControlV(command[0]) or
       command[0] == ord('h') or isLeftKey(command[0]) or isBackspaceKey(command[0]) or
       command[0] == ord('l') or isRightKey(command[0]) or
       command[0] == ord('k') or isUpKey(command[0]) or
       command[0] == ord('j') or isDownKey(command[0]) or
       isEnterKey(command[0]) or
       command[0] == ord('x') or isDcKey(command[0]) or
       command[0] == ord('X') or
       command[0] == ord('^') or command[0] == ord('_') or
       command[0] == ord('0') or isHomeKey(command[0]) or
       command[0] == ord('$') or isEndKey(command[0]) or
       command[0] == ord('{') or
       command[0] == ord('}') or
       command[0] == ord('-') or
       command[0] == ord('+') or
       command[0] == ord('G') or
       isControlU(command[0]) or
       isControlD(command[0]) or
       isPageUpKey(command[0]) or
       ## Page down and Ctrl - F
       isPageDownKey(command[0]) or
       command[0] == ord('w') or
       command[0] == ord('b') or
       command[0] == ord('e') or
       command[0] == ord('o') or
       command[0] == ord('O') or
       command[0] == ord('D') or
       command[0] == ord('S') or
       command[0] == ord('s') or
       command[0] == ord('p') or
       command[0] == ord('P') or
       command[0] == ord('>') or
       command[0] == ord('<') or
       command[0] == ord('J') or
       isControlA(command[0]) or
       isControlX(command[0]) or
       command[0] == ord('~') or
       command[0] == ord('n') or
       command[0] == ord('N') or
       command[0] == ord('*') or
       command[0] == ord('#') or
       command[0] == ord('R') or
       command[0] == ord('i') or
       command[0] == ord('I') or
       command[0] == ord('v') or
       command[0] == ord('a') or
       command[0] == ord('A') or
       command[0] == ord('u') or
       isControlR(command[0]) or
       command[0] == ord('.') or
       command[0] == ord('Y'):
      result = InputState.Valid

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

    else:
      discard

proc isNormalMode(status: Editorstatus): bool =
  let index = currentMainWindowNode.bufferIndex
  status.bufStatus[index].mode == Mode.normal

proc normalMode*(status: var EditorStatus) =
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.normalModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  let currentBufferIndex = status.bufferIndexInCurrentWindow
  var
    countChange = 0
    command = ru ""

  while status.isNormalMode and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    if currentBufStatus.countChange > countChange:
      countChange = currentBufStatus.countChange

    status.update

    var key = status.getKey

    status.lastOperatingTime = now()

    currentBufStatus.buffer.beginNewSuitIfNeeded
    currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

    if isEscKey(key):
      command = ru ""
      currentBufStatus.cmdLoop = 0

      let keyAfterEsc = getKey(currentMainWindowNode)
      if isEscKey(keyAfterEsc):
        status.turnOffHighlighting
        continue
      else:
        key = keyAfterEsc

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif key == ord('/'):
      status.searchFordwards
    elif key == ord('?'):
      status.searchBackwards
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif isDigit(command) and
         isDigit(key) and
         not (currentBufStatus.cmdLoop == 0 and ($key)[0] == '0'):

      let num = ($key)[0]

      currentBufStatus.cmdLoop *= 10
      currentBufStatus.cmdLoop += ord(num) - ord('0')
      currentBufStatus.cmdLoop = min(
        100000,
        currentBufStatus.cmdLoop)
      continue
    else:
      command &= key

      let state = isNormalModeCommand(command)
      if state == InputState.Continue:
        continue
      elif state == InputState.Valid:
        status.normalCommand(command, terminalHeight(), terminalWidth())

    command = ru ""
    currentBufStatus.cmdLoop = 0
