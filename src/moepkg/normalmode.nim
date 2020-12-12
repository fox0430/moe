from strutils import parseInt
import terminal, times
import editorstatus, ui, gapbuffer, unicodetext, fileutils, undoredostack,
       window, movement, editor, search, color, bufferstatus, quickrun,
       messages, commandline

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
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex

  status.bufStatus[currentBufferIndex].isSearchHighlight = true

  status.updateHighlight(status.workspace[workspaceIndex].currentMainWindowNode)

  var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode

  status.bufStatus[currentBufferIndex].keyRight(windowNode)
  let
    ignorecase = status.settings.ignorecase
    smartcase = status.settings.smartcase
    searchResult = status.searchBuffer(keyword, ignorecase, smartcase)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column:
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
  elif searchResult.line == -1: windowNode.keyLeft

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]

  status.searchNextOccurrence(keyword)

proc searchNextOccurrenceReversely(status: var EditorStatus, keyword: seq[Rune]) =
  currentBufStatus.isSearchHighlight = true
  status.updateHighlight(currentMainWindowNode)

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
  currentBufStatus.isSearchHighlight = false
  status.updateHighlight(currentMainWindowNode)

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
    quickRunWindowIndex = status.bufStatus.getQuickRunBufferIndex(currentWorkSpace)

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

# ci command
proc changeInnerCommand(status: var EditorStatus, key: Rune) =
  let
    currentLine = currentMainWindowNode.currentLine
    oldLine = currentBufStatus.buffer[currentLine]

  # Delete inside paren and enter insert mode
  if isParen(key):
    currentBufStatus.yankAndDeleteInsideOfParen(currentMainWindowNode,
                                                status.registers,
                                                key)

    if oldLine != currentBufStatus.buffer[currentLine]:
      currentMainWindowNode.currentColumn.inc
      status.changeMode(Mode.insert)
  # Delete current word and enter insert mode
  elif key == ru'w':
    if oldLine.len > 0:
      currentBufStatus.moveToBackwardWord(currentMainWindowNode)
      currentBufStatus.deleteWord(currentMainWindowNode, status.registers)
    status.changeMode(Mode.insert)
  else:
    discard

# di command
proc yankAndDeleteInnerCommand(status: var EditorStatus, key: Rune) =
  # Delete inside paren and enter insert mode
  if isParen(key):
    currentBufStatus.yankAndDeleteInsideOfParen(currentMainWindowNode,
                                                status.registers,
                                                key)
    currentBufStatus.keyRight(currentMainWindowNode)
  # Delete current word and enter insert mode
  elif key == ru'w':
    if currentBufStatus.buffer[currentMainWindowNode.currentLine].len > 0:
      currentBufStatus.moveToBackwardWord(currentMainWindowNode)
      currentBufStatus.deleteWord(currentMainWindowNode, status.registers)
  else:
    discard

proc normalCommand(status: var EditorStatus,
                   commands: seq[Rune],
                   height, width: int)

proc repeatNormalModeCommand(status: var Editorstatus, height, width: int) =
  if status.normalCommandHistory.len == 0: return

  let commands  = status.normalCommandHistory[^1]
  status.normalCommand(commands, height, width)

proc normalCommand(status: var EditorStatus,
                   commands: seq[Rune],
                   height, width: int) =

  if commands.len == 0: return

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex

  if status.bufStatus[currentBufferIndex].cmdLoop == 0:
    status.bufStatus[currentBufferIndex].cmdLoop = 1

  let cmdLoop = status.bufStatus[currentBufferIndex].cmdLoop
  var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode

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

  # d$ command
  template yankAndDeleteCharactersUntilEndOfLine() =
    let
      lineWidth = currentBufStatus.buffer[windowNode.currentLine].len
      count = lineWidth - windowNode.currentColumn
    status.yankString(count)

    currentBufStatus.deleteCharacterUntilEndOfLine(
      status.settings.autoDeleteParen, windowNode)

  template deleteCharactersOfLine() =
    currentBufStatus.deleteCharactersOfLine(
      status.settings.autoDeleteParen,
      windowNode)

  template deleteCurrentCharacter() =
    currentBufStatus.deleteCurrentCharacter(
      windowNode,
      status.settings.autoDeleteParen)

  template replaceCurrentCharacter(newCharacter: Rune) =
    currentBufStatus.replaceCurrentCharacter(
      currentWorkSpace.currentMainWindowNode,
      status.settings.autoIndent,
      status.settings.autoDeleteParen,
      status.settings.tabStop,
      newCharacter)

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
    let workspaceIndex = status.currentWorkSpaceIndex

    if status.workspace[workspaceIndex].numOfMainWindow == 1: return

    if currentBufStatus.countChange == 0 or
       mainWindowNode.countReferencedWindow(currentBufferIndex) > 1:
        status.closeWindow(currentWorkSpace.currentMainWindowNode, height, width)

  # dgg command
  # Delete the line from first line to current line
  template yankAndDeleteLineFromFirstLineToCurrentLine() =
    let currentLine = windowNode.currentLine
    status.yankLines(0, currentLine)
    status.moveToFirstLine
    for i in 0 ..< currentLine + 1:
      currentBufStatus.deleteLine(windowNode, windowNode.currentLine)

  # s and cl commands
  template deleteCharacterAndEnterInsertMode() =
    if currentBufStatus.buffer[windowNode.currentLine].len > 0:
      let
        lineWidth = currentBufStatus.buffer[windowNode.currentLine].len
        loop = min(cmdLoop, lineWidth - windowNode.currentColumn)
      status.yankString(loop)

      for i in 0 ..< loop:
        currentBufStatus.deleteCurrentCharacter(
          windowNode,
          status.settings.autoDeleteParen)

    status.changeMode(Mode.insert)

  # d{ command
  template yankAndDeleteTillPreviousBlankLine() =
    let
      blankLine = currentBufStatus.findPreviousBlankLine(windowNode.currentLine)
    status.yankLines(blankLine + 1, windowNode.currentLine)
    currentBufStatus.deleteTillPreviousBlankLine(windowNode)

  # d} command
  template yankAndDeleteTillNextBlankLine() =
    let blankLine = currentBufStatus.findNextBlankLine(windowNode.currentLine)
    status.yankLines(windowNode.currentLine, blankLine - 1)
    currentBufStatus.deleteTillNextBlankLine(windowNode)

  # y{ command
  template yankToPreviousBlankLine() =
    let
      currentLine = windowNode.currentLine
      previousBlankLine = currentBufStatus.findPreviousBlankLine(currentLine)
    status.yankLines(max(previousBlankLine, 0), currentLine)
    if previousBlankLine >= 0: status.jumpLine(previousBlankLine)

  # y} command
  template yankToNextBlankLine() =
    let
      currentLine = windowNode.currentLine
      buffer = currentBufStatus.buffer
      nextBlankLine = currentBufStatus.findNextBlankLine(currentLine)
    status.yankLines(currentLine, max(nextBlankLine, buffer.high))
    if nextBlankLine >= 0: status.jumpLine(nextBlankLine)

  # dd command
  template yankAndDeleteLines() =
    let lastLine = min(windowNode.currentLine + cmdLoop - 1,
                       currentBufStatus.buffer.high)
    status.yankLines(windowNode.currentLine, lastLine)
    let count = min(cmdLoop,
                    currentBufStatus.buffer.len - windowNode.currentLine)
    for i in 0 ..< count:
      currentBufStatus.deleteLine(windowNode, windowNode.currentLine)

  # d0 command
  template yankAndDeleteCharacterBeginningOfLine() =
    let currentColumn = windowNode.currentColumn
    windowNode.currentColumn = 0
    status.yankString(currentColumn)
    windowNode.currentColumn = currentColumn

    currentBufStatus.deleteCharacterBeginningOfLine(
      status.settings.autoDeleteParen,
      windowNode)

  # dG command
  # Yank and delete the line from current line to last line
  template yankAndDeleteFromCurrentLineToLastLine() =
    let lastLine = currentBufStatus.buffer.high
    status.yankLines(windowNode.currentLine, lastLine)
    let count = currentBufStatus.buffer.len - windowNode.currentLine

    for i in 0 ..< count:
      currentBufStatus.deleteLine(windowNode, windowNode.currentLine)

  ## yy command
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
      count = if  width > cmdLoop: cmdLoop
              else: width
    status.yankString(count)

  # X and dh command
  template cutCharacterBeforeCursor() =
    if windowNode.currentColumn > 0:
      let
        currentColumn = windowNode.currentColumn
        loop = if currentColumn - cmdLoop > 0: cmdLoop
               else: currentColumn
      currentMainWindowNode.currentColumn = currentColumn - loop

      status.yankString(loop)
      for i in 0 ..< loop:
        deleteCurrentCharacter()

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
    let
      lineWidth = currentBufStatus.buffer[windowNode.currentLine].len
      loop = min(cmdLoop, lineWidth - windowNode.currentColumn)
    status.yankString(loop)
    for i in 0 ..< loop:
      deleteCurrentCharacter()
  elif key == ord('X'):
    cutCharacterBeforeCursor()
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
    status.updateHighlight(currentMainWindowNode)
    status.changeMode(Mode.insert)
  elif key == ord('c'):
    let secondKey = commands[1]
    if secondKey == ord('c'):
      deleteCharactersOfLine()
      insertAfterCursor()
    if secondKey == ord('l'):
      deleteCharacterAndEnterInsertMode()
    elif secondKey == ord('i'):
      let thirdKey = commands[2]
      if isParen(thirdKey) or
         thirdKey == ord('w'):
        status.changeInnerCommand(thirdKey)
  elif key == ord('d'):
    let secondKey = commands[1]
    if secondKey == ord('d'):
      yankAndDeleteLines()
    elif secondKey == ord('w'):
      currentBufStatus.deleteWord(windowNode, status.registers)
    elif secondKey == ('$') or isEndKey(secondKey):
      yankAndDeleteCharactersUntilEndOfLine()
    elif secondKey == ('0') or isHomeKey(secondKey):
     yankAndDeleteCharacterBeginningOfLine()
    elif secondKey == ord('G'):
      yankAndDeleteFromCurrentLineToLastLine()
    elif secondKey == ord('g'):
      let thirdKey = commands[2]
      if thirdKey == ord('g'):
        yankAndDeleteLineFromFirstLineToCurrentLine()
    elif secondKey == ord('{'):
      yankAndDeleteTillPreviousBlankLine()
    elif secondKey == ord('}'):
      yankAndDeleteTillNextBlankLine()
    elif secondKey == ord('i'):
      let thirdKey = commands[2]
      status.yankAndDeleteInnerCommand(thirdKey)
    elif secondKey == ord('h'):
      cutCharacterBeforeCursor()
  elif key == ord('D'):
     yankAndDeleteCharactersUntilEndOfLine()
  elif key == ord('S'):
     deleteCharactersOfLine()
     insertAfterCursor()
  elif key == ord('s'):
    deleteCharacterAndEnterInsertMode()
  elif key == ord('y'):
    let secondKey = commands[1]
    if secondKey == ord('y'):
      yankLines()
    elif secondKey == ord('w'):
      status.yankWord(cmdLoop)
    elif secondKey == ord('{'):
      yankToPreviousBlankLine()
    elif secondKey == ord('}'):
      yankToNextBlankLine()
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
  else:
    discard

proc isNormalModeCommand(status: var Editorstatus, key: Rune): seq[Rune] =
  template getAnotherKey(): Rune =
    let workspaceIndex = status.currentWorkSpaceIndex
    getKey(status.workSpace[workspaceIndex].currentMainWindowNode)

  # Single key commands
  if isControlK(key) or
     isControlJ(key) or
     isControlV(key) or
     key == ord('h') or isLeftKey(key) or isBackspaceKey(key) or
     key == ord('l') or isRightKey(key) or
     key == ord('k') or isUpKey(key) or
     key == ord('j') or isDownKey(key) or
     isEnterKey(key) or
     key == ord('x') or isDcKey(key) or
     key == ord('X') or
     key == ord('^') or key == ord('_') or
     key == ord('0') or isHomeKey(key) or
     key == ord('$') or isEndKey(key) or
     key == ord('{') or
     key == ord('}') or
     key == ord('-') or
     key == ord('+') or
     key == ord('G') or
     isControlU(key) or
     isControlD(key) or
     isPageUpkey(key) or
     ## Page down and Ctrl - F
     isPageDownKey(key) or
     key == ord('w') or
     key == ord('b') or
     key == ord('e') or
     key == ord('o') or
     key == ord('O') or
     key == ord('D') or
     key == ord('S') or
     key == ord('s') or
     key == ord('p') or
     key == ord('P') or
     key == ord('>') or
     key == ord('<') or
     key == ord('J') or
     isControlA(key) or
     isControlX(key) or
     key == ord('~') or
     key == ord('n') or
     key == ord('N') or
     key == ord('*') or
     key == ord('#') or
     key == ord('R') or
     key == ord('i') or
     key == ord('I') or
     key == ord('v') or
     key == ord('a') or
     key == ord('A') or
     key == ord('u') or
     isControlR(key) or
     key == ord('.'): result = @[key]
  # Multiple key commands
  # TODO: Refactor
  elif key == ord('g'):
      let secondKey = getAnotherKey()
      if secondKey == ord('g') or secondKey == ord('_'):
        result = @[key, secondKey]
  elif key == ord('z'):
    let secondKey = getAnotherKey()
    if secondKey == ord('.') or key == ord('t') or key == ord('b'):
      result = @[key, secondKey]
  elif key == ord('c'):
    let secondKey = getAnotherKey()
    if secondKey == ord('c') or secondKey == ('l'):
      result = @[key, secondKey]
    elif secondKey == ('i'):
      let thirdKey = getAnotherKey()
      if isParen(thirdKey) or
         thirdKey == ('w'):
        result = @[key, secondKey, thirdKey]
  elif key == ord('d'):
    let secondKey = getAnotherKey()
    if secondKey == ord('d') or
       secondKey == ord('w') or
       secondKey == ord('$') or isEndKey(secondKey) or
       secondKey == ord('0') or isHomeKey(secondKey) or
       secondKey == ord('G') or
       secondKey == ord('{') or
       secondKey == ord('}'): result = @[key, secondKey]
    elif secondKey == ord('g'):
      let thirdKey = getAnotherKey()
      if thirdKey == ord('g'): result = @[key, secondKey, thirdKey]
    elif secondKey == ord('i'):
      let thirdKey = getAnotherKey()
      if isParen(thirdKey) or
         thirdKey == ('w'):
        result = @[key, secondKey, thirdKey]
  elif key == ord('y'):
    let secondKey = getAnotherKey()
    if key == ord('y') or
       key == ord('w') or
       key == ord('{') or
       key == ord('}') or
       key == ord('l'):
      result = @[key, secondKey]
  elif key == ord('Y'):
      result = @[key]
  elif key == ord('='):
    let secondKey = getAnotherKey()
    if secondKey == ord('='):
      result = @[key, secondKey]
  elif key == ord('r'):
    let secondKey = getAnotherKey()
    result = @[key, secondKey]
  elif key == ord('f'):
    let secondKey = getAnotherKey()
    result = @[key, secondKey]
  elif key == ord('F'):
    let secondKey = getAnotherKey()
    result = @[key, secondKey]
  elif key == ord('Z'):
    let secondKey = getAnotherKey()
    if  secondKey == ord('Z') or secondKey == ord('Q'):
      result = @[key, secondKey]
  elif isControlW(key):
    let secondKey = getAnotherKey()
    if secondKey == ord('c'):
      result = @[key, secondKey]
  elif key == ('\\'):
    let secondKey = getAnotherKey()
    if secondKey == ord('r'): result = @[key, secondKey]
  else: discard

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

  # Record normal mode commands
  if result.len > 0 and
     key != ord('.') and
     not isMovementKey(key) and
     not isChangeModeKey(key): status.normalCommandHistory.add(@[result])

proc isNormalMode(status: Editorstatus): bool =
  let index =
    status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[index].mode == Mode.normal

proc normalMode*(status: var EditorStatus) =
  if not status.settings.disableChangeCursor:
    changeCursorType(status.settings.normalModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpaceIndex = status.currentWorkSpaceIndex
  var countChange = 0

  while status.isNormalMode and
        currentWorkSpaceIndex == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    if currentBufStatus.countChange > countChange:
      countChange = currentBufStatus.countChange

    status.update

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    currentBufStatus.buffer.beginNewSuitIfNeeded
    currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

    if isEscKey(key):
      let keyAfterEsc = getKey(currentMainWindowNode)
      if isEscKey(keyAfterEsc):
        status.turnOffHighlighting
        continue
      else: key = keyAfterEsc

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif key == ord('/'):
      status.searchFordwards
    elif key == ord('?'):
      status.searchBackwards
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif isDigit(key):
      let num = ($key)[0]
      if status.bufStatus[currentBufferIndex].cmdLoop == 0 and num == '0':
        let commands = status.isNormalModeCommand(key)
        status.normalCommand(commands, terminalHeight(), terminalWidth())
        continue

      currentBufStatus.cmdLoop *= 10
      currentBufStatus.cmdLoop += ord(num)-ord('0')
      currentBufStatus.cmdLoop = min(
        100000,
        currentBufStatus.cmdLoop)
      continue
    else:
      let commands = status.isNormalModeCommand(key)
      status.normalCommand(commands, terminalHeight(), terminalWidth())
      currentBufStatus.cmdLoop = 0
