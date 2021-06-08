from strutils import parseInt
import terminal, times, strutils
import editorstatus, ui, gapbuffer, unicodeext, fileutils, undoredostack,
       window, movement, editor, search, color, bufferstatus, quickrun,
       messages

type InputState = enum
  Continue
  Valid
  Invalid

proc searchOneCharactorToEndOfLine(bufStatus: var BufferStatus,
                                   windowNode: WindowNode,
                                   rune: Rune) =

  let line = bufStatus.buffer[windowNode.currentLine]

  if line.len < 1 or isEscKey(rune) or
     (windowNode.currentColumn == line.high): return

  for col in windowNode.currentColumn + 1 ..< line.len:
    if line[col] == rune:
      windowNode.currentColumn = col
      break

proc searchOneCharactorToBeginOfLine(bufStatus: var BufferStatus,
                                     windowNode: WindowNode,
                                     rune: Rune) =

  let line = bufStatus.buffer[windowNode.currentLine]

  if line.len < 1 or isEscKey(rune) or (windowNode.currentColumn == 0): return

  for col in countdown(windowNode.currentColumn - 1, 0):
    if line[col] == rune:
      windowNode.currentColumn = col
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

proc toggleCase(ch: Rune): Rune =
  result = ch
  if result.isUpper():
    result = result.toLower()
  elif result.isLower():
    result = result.toUpper()
  return result

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
                            status.platform,
                            status.settings.clipboard,
                            currentBufStatus.cmdLoop)

proc yankWord(status: var EditorStatus, isDelete: bool) =
  currentBufStatus.yankWord(status.registers,
                            currentMainWindowNode,
                            status.platform,
                            status.settings.clipboard,
                            currentBufStatus.cmdLoop,
                            isDelete)

proc yankWord(status: var EditorStatus, registerName: string) =
  currentBufStatus.yankWord(status.registers,
                            currentMainWindowNode,
                            status.platform,
                            status.settings.clipboard,
                            currentBufStatus.cmdLoop,
                            registerName)

proc deleteWord(status: var EditorStatus) =
  const registerName = ""
  currentBufStatus.deleteWord(
    currentMainWindowNode,
    currentBufStatus.cmdLoop,
    status.registers,
    registerName)

proc deleteWord(status: var EditorStatus, registerName: string) =
  currentBufStatus.deleteWord(
    currentMainWindowNode,
    currentBufStatus.cmdLoop,
    status.registers,
    registerName)

# ci command
proc changeInnerCommand(status: var EditorStatus, key: Rune) =
  let
    currentLine = currentMainWindowNode.currentLine
    oldLine = currentBufStatus.buffer[currentLine]

  # Delete inside paren and enter insert mode
  if isParen(key):
    currentBufStatus.deleteInsideOfParen(currentMainWindowNode,
                                                status.registers,
                                                key)

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

  let
    currentLine = currentMainWindowNode.currentLine
    oldLine = currentBufStatus.buffer[currentLine]

  # Delete inside paren and enter insert mode
  if isParen(key):
    currentBufStatus.deleteInsideOfParen(currentMainWindowNode,
                                         status.registers,
                                         registerName,
                                         key)

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
  # Delete inside paren and enter insert mode
  if isParen(key):
    if registerName.len > 0:
      currentBufStatus.deleteInsideOfParen(
        currentMainWindowNode,
        status.registers,
        registerName,
        key)
    else:
      currentBufStatus.deleteInsideOfParen(
        currentMainWindowNode,
        status.registers,
        key)

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

# name is the register name
proc yankLines(status: var Editorstatus, start, last: int, isDelete: bool) =
  let lastLine = min(last,
                     currentBufStatus.buffer.high)

  currentBufStatus.yankLines(status.registers,
                             status.commandLine,
                             status.messageLog,
                             status.settings.notificationSettings,
                             start, lastLine,
                             isDelete)

proc yankLines(status: var Editorstatus, start, last: int) =
  let lastLine = min(last,
                     currentBufStatus.buffer.high)

  currentBufStatus.yankLines(status.registers,
                             status.commandLine,
                             status.messageLog,
                             status.settings.notificationSettings,
                             start, lastLine)

proc yankLines(status: var Editorstatus, start, last: int, registerName: string) =
  let lastLine = min(last,
                     currentBufStatus.buffer.high)

  currentBufStatus.yankLines(status.registers,
                             status.commandLine,
                             status.messageLog,
                             status.settings.notificationSettings,
                             start, lastLine,
                             registerName)

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
                               count)

proc deleteLines(status: var EditorStatus, registerName: string) =
  let
    startLine = currentMainWindowNode.currentLine
    count = min(
      currentBufStatus.cmdLoop - 1,
      currentBufStatus.buffer.len - currentMainWindowNode.currentLine)
  currentBufStatus.deleteLines(status.registers,
                               currentMainWindowNode,
                               registerName,
                               startLine,
                               count)

proc yankString(status: var Editorstatus) =
  const
    registerName = ""
    isDelete = false
  let
    buffer = currentBufStatus.buffer
    lineLen = buffer[currentMainWindowNode.currentLine].len
    width = lineLen - currentMainWindowNode.currentColumn
    length = if width > currentBufStatus.cmdLoop: currentBufStatus.cmdLoop
             else: width

  currentBufStatus.yankString(status.registers,
                              currentMainWindowNode,
                              status.commandLine,
                              status.messageLog,
                              status.platform,
                              status.settings,
                              length,
                              registerName,
                              isDelete)

# name is the register name
proc yankString(status: var Editorstatus, registerName: string) =
  const isDelete = false
  let
    buffer = currentBufStatus.buffer
    lineLen = buffer[currentMainWindowNode.currentLine].len
    width = lineLen - currentMainWindowNode.currentColumn
    length = if width > currentBufStatus.cmdLoop: currentBufStatus.cmdLoop
             else: width

  currentBufStatus.yankString(status.registers,
                              currentMainWindowNode,
                              status.commandLine,
                              status.messageLog,
                              status.platform,
                              status.settings,
                              length,
                              registerName,
                              isDelete)

proc yankString(status: var Editorstatus, isDelete: bool) =
  const registerName = ""
  let
    buffer = currentBufStatus.buffer
    lineLen = buffer[currentMainWindowNode.currentLine].len
    width = lineLen - currentMainWindowNode.currentColumn
    length = if width > currentBufStatus.cmdLoop: currentBufStatus.cmdLoop
             else: width

  currentBufStatus.yankString(status.registers,
                              currentMainWindowNode,
                              status.commandLine,
                              status.messageLog,
                              status.platform,
                              status.settings,
                              length,
                              registerName,
                              isDelete)

proc yankString(status: var Editorstatus,
                registerName: string,
                isDelete: bool) =

  let
    buffer = currentBufStatus.buffer
    lineLen = buffer[currentMainWindowNode.currentLine].len
    width = lineLen - currentMainWindowNode.currentColumn
    length = if width > currentBufStatus.cmdLoop: currentBufStatus.cmdLoop
             else: width

  currentBufStatus.yankString(status.registers,
                              currentMainWindowNode,
                              status.commandLine,
                              status.messageLog,
                              status.platform,
                              status.settings,
                              length,
                              registerName,
                              isDelete)

proc deleteCharacters(status: var EditorStatus, registerName: string) =
  currentBufStatus.deleteCharacters(
    status.registers,
    registerName,
    status.settings.autoDeleteParen,
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn,
    currentBufStatus.cmdLoop)


proc deleteCharacters(status: var EditorStatus) =
  const registerName = ""
  currentBufStatus.deleteCharacters(
    status.registers,
    registerName,
    status.settings.autoDeleteParen,
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn,
    currentBufStatus.cmdLoop)

# d$ command
proc yankAndDeleteCharactersUntilEndOfLine(status: var EditorStatus, registerName: string) =
  let lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  currentBufStatus.cmdLoop = lineWidth - currentMainWindowNode.currentColumn

  if registerName.len > 0:
    status.yankString(registerName)
  else:
    status.yankString

  currentBufStatus.deleteCharacterUntilEndOfLine(
    status.settings.autoDeleteParen,
    currentMainWindowNode)

# d$ command
proc yankAndDeleteCharactersUntilEndOfLine(status: var EditorStatus) =
  let lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
  currentBufStatus.cmdLoop = lineWidth - currentMainWindowNode.currentColumn

  status.yankString

  currentBufStatus.deleteCharacterUntilEndOfLine(
    status.settings.autoDeleteParen,
    currentMainWindowNode)

# d0 command
proc yankAndDeleteCharacterBeginningOfLine(status: var EditorStatus,
                                           registerName: string) =

  let currentColumn = currentMainWindowNode.currentColumn
  currentBufStatus.cmdLoop = currentColumn
  currentMainWindowNode.currentColumn = 0

  if registerName.len > 0:
    status.yankString(registerName)
  else:
    status.yankString

  currentMainWindowNode.currentColumn = currentColumn

  currentBufStatus.deleteCharacterBeginningOfLine(
    status.settings.autoDeleteParen,
    currentMainWindowNode)

# d0 command
proc yankAndDeleteCharacterBeginningOfLine(status: var EditorStatus) =
  const registerName = ""
  status.yankAndDeleteCharacterBeginningOfLine(registerName)

# dG command
# Yank and delete the line from current line to last line
proc yankAndDeleteFromCurrentLineToLastLine(status: var EditorStatus,
                                            registerName: string) =

  let
    startLine = currentMainWindowNode.currentLine
    count = currentBufStatus.buffer.len - currentMainWindowNode.currentLine
  currentBufStatus.deleteLines(status.registers,
                               currentMainWindowNode,
                               registerName,
                               startLine,
                               count)

# dgg command
# Delete the line from first line to current line
proc yankAndDeleteLineFromFirstLineToCurrentLine(status: var EditorStatus,
                                                 registerName: string) =

  const startLine = 0
  let count = currentMainWindowNode.currentLine
  currentBufStatus.deleteLines(status.registers,
                               currentMainWindowNode,
                               registerName,
                               startLine,
                               count)

  status.moveToFirstLine

# d{ command
proc yankAndDeleteTillPreviousBlankLine(status: var EditorStatus,
                                        registerName: string) =

  let blankLine = currentBufStatus.findPreviousBlankLine(
    currentMainWindowNode.currentLine)

  if registerName.len > 0:
    status.yankLines(blankLine + 1,
                     currentMainWindowNode.currentLine,
                     registerName)
  else:
    const isDelete = true
    status.yankLines(blankLine + 1, currentMainWindowNode.currentLine, isDelete)

  currentBufStatus.deleteTillPreviousBlankLine(currentMainWindowNode)

proc yankAndDeleteTillPreviousBlankLine(status: var EditorStatus) =
  const registerName = ""
  status.yankAndDeleteTillPreviousBlankLine(registerName)

# d} command
proc yankAndDeleteTillNextBlankLine(status: var EditorStatus,
                                    registerName: string) =

  let blankLine = currentBufStatus.findNextBlankLine(
    currentMainWindowNode.currentLine)

  if registerName.len > 0:
    status.yankLines(currentMainWindowNode.currentLine,
                     blankLine - 1,
                     registerName)
  else:
    const isDelete = true
    status.yankLines(currentMainWindowNode.currentLine, blankLine - 1, isDelete)

  currentBufStatus.deleteTillNextBlankLine(currentMainWindowNode)

# X and dh command
proc cutCharacterBeforeCursor(status: var EditorStatus, registerName: string) =
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
  const registerName = ""
  status.cutCharacterBeforeCursor(registerName)

proc yankAndDeleteTillNextBlankLine(status: var EditorStatus) =
  const registerName = ""
  status.yankAndDeleteTillNextBlankLine(registerName)

proc yankAndDeleteLineFromFirstLineToCurrentLine(status: var EditorStatus) =
  const registerName = ""
  status.yankAndDeleteLineFromFirstLineToCurrentLine(registerName)

proc yankAndDeleteFromCurrentLineToLastLine(status: var EditorStatus) =
  const registerName = ""
  status.yankAndDeleteFromCurrentLineToLastLine(registerName)

# s and cl commands
proc deleteCharacterAndEnterInsertMode(status: var EditorStatus) =
  if currentBufStatus.buffer[currentMainWindowNode.currentLine].len > 0:
    let
      lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
      cmdLoop = currentBufStatus.cmdLoop
      loop = min(cmdLoop, lineWidth - currentMainWindowNode.currentColumn)
    currentBufStatus.cmdLoop = loop

    status.deleteCharacters

  status.changeMode(Mode.insert)

# s and cl commands
proc deleteCharacterAndEnterInsertMode(status: var EditorStatus,
                                       registerName: string) =

  if currentBufStatus.buffer[currentMainWindowNode.currentLine].len > 0:
    let
      lineWidth = currentBufStatus.buffer[currentMainWindowNode.currentLine].len
      cmdLoop = currentBufStatus.cmdLoop
      loop = min(cmdLoop, lineWidth - currentMainWindowNode.currentColumn)
    currentBufStatus.cmdLoop = loop

    status.deleteCharacters

  status.changeMode(Mode.insert)

# cc/S command
proc yankAndDeleteCharactersOfLine(status: var EditorStatus) =
  const
    isDelete = true
    registerName = ""
  currentBufStatus.yankCharactersOfLines(
    currentMainWindowNode,
    status.registers,
    isDelete,
    registerName)

  currentBufStatus.deleteCharactersOfLine(
    status.settings.autoDeleteParen,
    currentMainWindowNode)

proc addRegister(status: var EditorStatus, command, registerName: string) =
  let
    cmdLoop = currentBufStatus.cmdLoop
    windowNode = currentMainWindowNode

  # yy command
  template yankLines() =
    let lastLine = min(windowNode.currentLine + cmdLoop - 1,
                       currentBufStatus.buffer.high)
    status.yankLines(windowNode.currentLine, lastLine, registerName)

  # yl command
  # Yank characters in the current line
  template yankCharacters() =
    let
      buffer = currentBufStatus.buffer
      width = buffer[windowNode.currentLine].len - windowNode.currentColumn
      count = if  width > cmdLoop: cmdLoop
              else: width
    status.yankString(registerName)

  if command == "yy":
    yankLines()
  elif command == "yl":
    yankCharacters()
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
    status.yankAndDeleteCharactersUntilEndOfLine(registerName)
  elif command == "d0":
    status.yankAndDeleteCharacterBeginningOfLine(registerName)
  elif command == "dG":
    status.yankAndDeleteFromCurrentLineToLastLine(registerName)
  elif command == "dgg":
    status.yankAndDeleteLineFromFirstLineToCurrentLine(registerName)
  elif command == "d{":
    status.yankAndDeleteTillPreviousBlankLine(registerName)
  elif command == "d}":
    status.yankAndDeleteTillNextBlankLine(registerName)
  elif command.len == 3 and command[0 .. 1] == "di":
    status.deleteInnerCommand(command[2].toRune, registerName)
  elif command == "dh":
    status.cutCharacterBeforeCursor(registerName)
  elif command == "cl" or command == "s":
    status.deleteCharacterAndEnterInsertMode(registerName)
  elif command.len == 3 and command[0 .. 1] == "ci":
    status.changeInnerCommand(command[2].toRune, registerName)
  else:
    discard

proc pasteFromRegister(status: var EditorStatus, command, name: string) =
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
       cmd.len == 3 and cmd[0 .. 1] == "di" or
       cmd == "dh" or
       cmd == "cl" or cmd == "s" or
       cmd.len == 3 and cmd[0 .. 1] == "ci":
    status.addRegister(cmd, $registerName)

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

proc normalCommand(status: var EditorStatus,
                   commands: seq[Rune],
                   height, width: int) =

  if commands.len == 0: return

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if status.bufStatus[currentBufferIndex].cmdLoop == 0:
    status.bufStatus[currentBufferIndex].cmdLoop = 1

  let cmdLoop = status.bufStatus[currentBufferIndex].cmdLoop
  var windowNode = currentMainWindowNode

  template getWordUnderCursor(): (int, seq[Rune]) =
    let line = currentBufStatus.buffer[windowNode.currentLine]
    if line.len() <= windowNode.currentColumn:
      return

    let atCursorRune = line[windowNode.currentColumn]
    if not atCursorRune.isAlpha() and not (char(atCursorRune) in '0'..'9'):
      return

    var beginCol = -1
    var endCol = -1
    for i in countdown(windowNode.currentColumn, 0):
      if not line[i].isAlpha() and not (char(line[i]) in '0'..'9'):
        break
      beginCol = i
    for i in windowNode.currentColumn..line.len()-1:
      if not line[i].isAlpha() and not (char(line[i]) in '0'..'9'):
        break
      endCol = i
    if endCol == -1 or beginCol == -1:
      (-1, seq[Rune].default)
    else:
      (beginCol, line[beginCol..endCol])

  template getCharacterUnderCursor(): Rune =
    let line = currentBufStatus.buffer[windowNode.currentLine]
    if line.len() <= windowNode.currentColumn:
      return

    line[windowNode.currentColumn]

  template insertAfterCursor() =
    let lineWidth = currentBufStatus.buffer[windowNode.currentLine].len
    if lineWidth == 0: discard
    elif lineWidth == windowNode.currentColumn: discard
    else: inc(windowNode.currentColumn)
    status.changeMode(Mode.insert)

  template insertCharacter(rune: Rune) =
    currentBufStatus.insertCharacter(
      windowNode,
      status.settings.autoCloseParen,
      rune)

  template deleteCurrentCharacter() =
    currentBufStatus.deleteCurrentCharacter(
      windowNode,
      status.settings.autoDeleteParen)

  template replaceCurrentCharacter(newCharacter: Rune) =
    currentBufStatus.replaceCurrentCharacter(
      status.mainWindow.currentMainWindowNode,
      status.settings.autoIndent,
      status.settings.autoDeleteParen,
      status.settings.tabStop,
      newCharacter)

  # TODO: Refactor
  template modifyWordUnderCursor(amount: int) =
    let wordUnderCursor      = getWordUnderCursor()
    var theWord              = wordUnderCursor[1]
    var beginCol             = wordUnderCursor[0]
    var num                  = 0
    var runeBefore           : Rune
    var currentColumnBefore  = windowNode.currentColumn
    var expandedColumnBefore = windowNode.expandedColumn
    try:
      # first we check if there could possibly be a
      # minus sign before our word
      if beginCol > 0:
        windowNode.currentColumn  = beginCol - 1
        windowNode.expandedColumn = windowNode.currentColumn - 1
        runeBefore = getCharacterUnderCursor()
        if runeBefore == toRune('-'):
          # there is a minus sign
          theWord.insert(runeBefore, 0)
          beginCol = beginCol - 1

      # if the word is a number, this will be successful,
      # if not we land in the exception case
      num               = parseInt($theWord) + amount

      # delete the old word/number
      windowNode.currentColumn  = beginCol
      windowNode.expandedColumn = windowNode.currentColumn
      for _ in 1..len(theWord):
        deleteCurrentCharacter()

      # change the word to the new number
      theWord = toRunes($num)

      # insert the new number
      for i in 0..len(theWord)-1:
        insertCharacter(theWord[i])

      # put the cursor on the last character of the number
      windowNode.currentColumn  = beginCol + len(theWord)-1
      windowNode.expandedColumn = windowNode.currentColumn
    except:
      windowNode.currentColumn  = currentColumnBefore
      windowNode.expandedColumn = expandedColumnBefore

  template closeWindow() =
    let currentBufferIndex = status.bufferIndexInCurrentWindow

    if status.mainWindow.numOfMainWindow == 1: return

    if currentBufStatus.countChange == 0 or
       mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
        status.closeWindow(
          status.mainWindow.currentMainWindowNode,
          height, width)

  # yy command
  template yankLines() =
    let lastLine = min(windowNode.currentLine + cmdLoop - 1,
                       currentBufStatus.buffer.high)
    status.yankLines(windowNode.currentLine, lastLine)

  # yl command
  # Yank characters in the current line
  template yankCharacters() =
    let
      buffer = currentBufStatus.buffer
      width = buffer[windowNode.currentLine].len - windowNode.currentColumn
    status.yankString

  let key = commands[0]

  if isControlK(key):
    status.moveNextWindow
  elif isControlJ(key):
    status.movePrevWindow
  elif isControlV(key):
    status.changeMode(Mode.visualBlock)
  elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< cmdLoop: windowNode.keyLeft
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< cmdLoop: currentBufStatus.keyRight(windowNode)
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< cmdLoop: currentBufStatus.keyUp(windowNode)
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< cmdLoop: currentBufStatus.keyDown(windowNode)
  elif key == ord('x') or isDcKey(key):
    status.deleteCharacters
  elif key == ord('X'):
    status.cutCharacterBeforeCursor
  elif key == ord('^') or key == ord('_'):
    currentBufStatus.moveToFirstNonBlankOfLine(windowNode)
  elif key == ord('0') or isHomeKey(key):
    windowNode.moveToFirstOfLine
  elif key == ord('$') or isEndKey(key):
    currentBufStatus.moveToLastOfLine(windowNode)
  elif key == ord('-'):
    currentBufStatus.moveToFirstOfPreviousLine(windowNode)
  elif key == ord('+'):
    currentBufStatus.moveToFirstOfNextLine(windowNode)
  elif key == ord('{'):
    currentBufStatus.moveToPreviousBlankLine(status, windowNode)
  elif key == ord('}'):
    currentBufStatus.moveToNextBlankLine(status, windowNode)
  elif key == ord('g'):
    let secondKey = commands[1]
    if secondKey == ord('g'):
      status.jumpLine(cmdLoop - 1)
    elif secondKey == ord('_'):
      currentBufStatus.moveToLastNonBlankOfLine(windowNode)
    elif secondKey == ord('a'):
      status.showCurrentCharInfoCommand(windowNode)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isControlU(key):
    for i in 0 ..< cmdLoop: status.halfPageUp
  elif isControlD(key):
    for i in 0 ..< cmdLoop: halfPageDown(status)
  elif isPageUpkey(key):
    for i in 0 ..< cmdLoop: status.pageUp
  elif isPageDownKey(key): ## Page down and Ctrl - F
    for i in 0 ..< cmdLoop: status.pageDown
  elif key == ord('w'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.moveToForwardWord(windowNode)
  elif key == ord('b'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.moveToBackwardWord(windowNode)
  elif key == ord('e'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.moveToForwardEndOfWord(windowNode)
  elif key == ord('z'):
    let secondKey = commands[1]
    if secondKey == ord('.'):
      currentBufStatus.moveCenterScreen(currentMainWindowNode)
    elif secondKey == ord('t'):
      currentBufStatus.scrollScreenTop(currentMainWindowNode)
    elif secondKey == ord('b'):
      currentBufStatus.scrollScreenBottom(currentMainWindowNode)
  elif key == ord('o'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.openBlankLineBelow(currentMainWindowNode)
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.openBlankLineAbove(currentMainWindowNode)

    var highlight = currentMainWindowNode.highlight
    highlight.updateHighlight(
      currentBufStatus,
      currentMainWindowNode,
      status.isSearchHighlight,
      status.searchHistory,
      status.settings)

    status.changeMode(Mode.insert)
  elif key == ord('c'):
    let secondKey = commands[1]
    if secondKey == ord('c'):
      status.yankAndDeleteCharactersOfLine
      insertAfterCursor()
    if secondKey == ord('l'):
      status.deleteCharacterAndEnterInsertMode
    elif secondKey == ord('i'):
      let thirdKey = commands[2]
      if isParen(thirdKey) or
         thirdKey == ord('w'):
        status.changeInnerCommand(thirdKey)
  elif key == ord('d'):
    let secondKey = commands[1]
    if secondKey == ord('d'):
      status.deleteLines
    elif secondKey == ord('w'):
      status.deleteWord
    elif secondKey == ('$') or isEndKey(secondKey):
      status.yankAndDeleteCharactersUntilEndOfLine
    elif secondKey == ('0') or isHomeKey(secondKey):
     status.yankAndDeleteCharacterBeginningOfLine
    elif secondKey == ord('G'):
      status.yankAndDeleteFromCurrentLineToLastLine
    elif secondKey == ord('g'):
      let thirdKey = commands[2]
      if thirdKey == ord('g'):
        status.yankAndDeleteLineFromFirstLineToCurrentLine
    elif secondKey == ord('{'):
      status.yankAndDeleteTillPreviousBlankLine
    elif secondKey == ord('}'):
      status.yankAndDeleteTillNextBlankLine
    elif secondKey == ord('i'):
      let thirdKey = commands[2]
      status.deleteInnerCommand(thirdKey)
    elif secondKey == ord('h'):
      status.cutCharacterBeforeCursor
  elif key == ord('D'):
     status.yankAndDeleteCharactersUntilEndOfLine
  elif key == ord('S'):
     status.yankAndDeleteCharactersOfLine
     insertAfterCursor()
  elif key == ord('s'):
    status.deleteCharacterAndEnterInsertMode
  elif key == ord('y'):
    let secondKey = commands[1]
    if secondKey == ord('y'):
      yankLines()
    elif secondKey == ord('w'):
      status.yankWord
    elif secondKey == ord('{'):
      status.yankToPreviousBlankLine
    elif secondKey == ord('}'):
      status.yankToNextBlankLine
    elif secondKey == ord('l'):
      yankCharacters()
  elif key == ord('Y'):
    yankLines()
  elif key == ord('p'):
    currentBufStatus.pasteAfterCursor(windowNode, status.registers)
  elif key == ord('P'):
    currentBufStatus.pasteBeforeCursor(windowNode, status.registers)
  elif key == ord('>'):
    for i in 0 ..< cmdLoop:
      currentBufStatus.addIndent(windowNode, status.settings.tabStop)
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
    modifyWordUnderCursor(cmdLoop)
  elif isControlX(key):
    modifyWordUnderCursor(-cmdLoop)
  elif key == ord('~'):
    for i in 0 ..< cmdLoop:
      replaceCurrentCharacter(toggleCase(getCharacterUnderCursor()))
      currentBufStatus.keyRight(windowNode)
  elif key == ord('r'):
    let
      lineWidth = currentBufStatus.buffer[windowNode.currentLine].len
      loop = lineWidth - windowNode.currentColumn
    if cmdLoop > loop: return

    let secondKey = commands[1]
    for i in 0 ..< cmdLoop:
      if i > 0:
        inc(windowNode.currentColumn)
        windowNode.expandedColumn = windowNode.currentColumn
      replaceCurrentCharacter(secondKey)
  elif key == ord('n'):
    status.searchNextOccurrence
  elif key == ord('N'):
    status.searchNextOccurrenceReversely
  elif key == ord('*'):
    status.searchNextOccurrence(getWordUnderCursor()[1])
  elif key == ord('#'):
    status.searchNextOccurrenceReversely(getWordUnderCursor()[1])
  elif key == ord('f'):
    let secondKey = commands[1]
    currentBufStatus.searchOneCharactorToEndOfLine(windowNode, secondKey)
  elif key == ord('F'):
    let secondKey = commands[1]
    currentBufStatus.searchOneCharactorToBeginOfLine(windowNode, secondKey)
  elif key == ord('R'):
    status.changeMode(Mode.replace)
  elif key == ord('i'):
    status.changeMode(Mode.insert)
  elif key == ord('I'):
    currentBufStatus.moveToFirstNonBlankOfLine(windowNode)
    status.changeMode(Mode.insert)
  elif key == ord('v'):
    status.changeMode(Mode.visual)
  elif key == ord('a'):
    insertAfterCursor()
  elif key == ord('A'):
    windowNode.currentColumn = currentBufStatus.buffer[windowNode.currentLine].len
    status.changeMode(Mode.insert)
  elif key == ord('u'):
    status.bufStatus[currentBufferIndex].undo(windowNode)
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
    if secondKey == ord('c'): closeWindow()
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
        if command[1] == ord('i'):
          result = InputState.Continue
        elif command[1] == ord('c') or command[1] == ('l'):
          result = InputState.Valid
      elif command.len == 3:
        if command[1] == ord('i'):
          if isParen(command[2]) or
             command[2] == ord('w'):
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

    elif command[0] == ord('F'):
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
      if command[1] == ord('r'):
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
