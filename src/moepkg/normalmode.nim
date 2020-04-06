import strformat, terminal, deques
import editorstatus, editorview, ui, gapbuffer, unicodeext, fileutils, commandview, undoredostack, window, movement, editor, searchmode, color

proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  status.commandWindow.erase

  status.commandWindow.write(0, 0, "debuf info: ", EditorColorPair.commandBar)
  status.commandWindow.append(fmt"currentLine: {status.bufStatus[status.currentBuffer].currentLine}, currentColumn: {status.bufStatus[status.currentBuffer].currentColumn}")
  status.commandWindow.append(fmt", cursor.y: {status.bufStatus[status.currentBuffer].cursor.y}, cursor.x: {status.bufStatus[status.currentBuffer].cursor.x}")
  status.commandWindow.append(fmt", {str}")

  status.commandWindow.refresh

proc searchOneCharactorToEndOfLine(bufStatus: var BufferStatus, rune: Rune) =
  let line = bufStatus.buffer[bufStatus.currentLine]

  if line.len < 1 or isEscKey(rune) or (bufStatus.currentColumn == line.high): return

  for col in bufStatus.currentColumn + 1 ..< line.len:
    if line[col] == rune:
      bufStatus.currentColumn = col
      break

proc searchOneCharactorToBeginOfLine(bufStatus: var BufferStatus, rune: Rune) =
  let line = bufStatus.buffer[bufStatus.currentLine]

  if line.len < 1 or isEscKey(rune) or (bufStatus.currentColumn == 0): return

  for col in countdown(bufStatus.currentColumn - 1, 0):
    if line[col] == rune:
      bufStatus.currentColumn = col
      break

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  let bufferIndex = status.currentWorkSpace.currentMainWindowNode.bufferIndex
  status.bufStatus[bufferIndex].isHighlight = true
  status.updateHighlight(status.currentBuffer)

  keyRight(status.bufStatus[status.currentBuffer])
  let searchResult = searchBuffer(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column: keyRight(status.bufStatus[status.currentBuffer])
  elif searchResult.line == -1:
    keyLeft(status.bufStatus[status.currentBuffer])

proc searchNextOccurrenceReversely(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  let bufferIndex = status.currentWorkSpace.currentMainWindowNode.bufferIndex
  status.bufStatus[bufferIndex].isHighlight = true
  status.updateHighlight(status.currentBuffer)

  keyLeft(status.bufStatus[status.currentBuffer])
  let searchResult = searchBufferReversely(status, keyword)
  if searchResult.line > -1:
    jumpLine(status, searchResult.line)
    for column in 0 ..< searchResult.column: keyRight(status.bufStatus[status.currentBuffer])
  elif searchResult.line == -1:
    keyRight(status.bufStatus[status.currentBuffer])

proc turnOffHighlighting*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].isHighlight = false
  status.updateHighlight(status.currentBuffer)

proc undo(bufStatus: var BufferStatus, currentWin: WindowNode) =
  if not bufStatus.buffer.canUndo: return
  bufStatus.buffer.undo
  bufStatus.revertPosition(bufStatus.buffer.lastSuitId)
  if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len and bufStatus.currentColumn > 0:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.prev(bufStatus.currentLine, bufStatus.currentColumn)
  currentWin.view.reload(bufStatus.buffer, min(currentWin.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc redo(bufStatus: var BufferStatus, currentWin: WindowNode) =
  if not bufStatus.buffer.canRedo: return
  bufStatus.buffer.redo
  bufStatus.revertPosition(bufStatus.buffer.lastSuitId)
  currentWin.view.reload(bufStatus.buffer, min(currentWin.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc writeFileAndExit(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].filename.len == 0:
    status.commandwindow.writeNoFileNameError(status.messageLog)
    status.changeMode(Mode.normal)
  else:
    try:
      saveFile(status.bufStatus[status.currentBuffer].filename, status.bufStatus[status.currentBuffer].buffer.toRunes, status.settings.characterEncoding)
      status.closeWindow(status.currentWorkSpace.currentMainWindowNode)
    except IOError:
      status.commandWindow.writeSaveError(status.messageLog)

proc forceExit(status: var Editorstatus) = status.closeWindow(status.currentWorkSpace.currentMainWindowNode)

proc normalCommand(status: var EditorStatus, key: Rune) =
  if status.bufStatus[status.currentBuffer].cmdLoop == 0: status.bufStatus[status.currentBuffer].cmdLoop = 1

  let
    cmdLoop = status.bufStatus[status.currentBuffer].cmdLoop
    currentBuf = status.currentBuffer

  if isControlK(key):
    moveNextWindow(status)
  elif isControlJ(key):
    movePrevWindow(status)
  elif isControlV(key):
    status.changeMode(Mode.visualBlock)
  elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< cmdLoop: keyLeft(status.bufStatus[status.currentBuffer])
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< cmdLoop: keyRight(status.bufStatus[status.currentBuffer])
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< cmdLoop: keyUp(status.bufStatus[status.currentBuffer])
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< cmdLoop: keyDown(status.bufStatus[status.currentBuffer])
  elif key == ord('x') or isDcKey(key):
    yankString(status, min(cmdLoop, status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn))
    for i in 0 ..< min(cmdLoop, status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn):
      status.bufStatus[status.currentBuffer].deleteCurrentCharacter(status.settings.autoDeleteParen, status.currentWorkSpace.currentMainWindowNode)
  elif key == ord('^'):
    moveToFirstNonBlankOfLine(status.bufStatus[status.currentBuffer])
  elif key == ord('0') or isHomeKey(key):
    moveToFirstOfLine(status.bufStatus[status.currentBuffer])
  elif key == ord('$') or isEndKey(key):
    moveToLastOfLine(status.bufStatus[status.currentBuffer])
  elif key == ord('-'):
    moveToFirstOfPreviousLine(status.bufStatus[status.currentBuffer])
  elif key == ord('+'):
    moveToFirstOfNextLine(status.bufStatus[status.currentBuffer])
  elif key == ord('g'):
    if getKey(status.currentWorkSpace.currentMainWindowNode.window) == ord('g'): moveToFirstLine(status)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isPageUpkey(key) or isControlU(key):
    for i in 0 ..< cmdLoop: pageUp(status)
  elif isPageDownKey(key): ## Page down and Ctrl - F
    for i in 0 ..< cmdLoop: pageDown(status)
  elif key == ord('w'):
    for i in 0 ..< cmdLoop: moveToForwardWord(status.bufStatus[status.currentBuffer])
  elif key == ord('b'):
    for i in 0 ..< cmdLoop: moveToBackwardWord(status.bufStatus[status.currentBuffer])
  elif key == ord('e'):
    for i in 0 ..< cmdLoop: moveToForwardEndOfWord(status.bufStatus[status.currentBuffer])
  elif key == ord('z'):
    let key = getkey(status.currentWorkSpace.currentMainWindowNode.window)
    if key == ord('.'): moveCenterScreen(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
    elif key == ord('t'): scrollScreenTop(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
    elif key == ord('b'): scrollScreenBottom(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
  elif key == ord('o'):
    for i in 0 ..< cmdLoop: openBlankLineBelow(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
    status.updateHighlight(status.currentBuffer)
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< cmdLoop: openBlankLineAbove(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
    status.updateHighlight(status.currentBuffer)
    status.changeMode(Mode.insert)
  elif key == ord('d'):
    let key = getKey(status.currentWorkSpace.currentMainWindowNode.window)
    if key == ord('d'):
      yankLines(status, status.bufStatus[currentBuf].currentLine, min(status.bufStatus[currentBuf].currentLine + cmdLoop - 1, status.bufStatus[currentBuf].buffer.high))
      for i in 0 ..< min(cmdLoop, status.bufStatus[currentBuf].buffer.len - status.bufStatus[currentBuf].currentLine):
        deleteLine(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode, status.bufStatus[currentBuf].currentLine)
    elif key == ord('w'): deleteWord(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
    elif key == ('$') or isEndKey(key):
      status.bufStatus[status.currentBuffer].deleteCharacterUntilEndOfLine(status.settings.autoDeleteParen, status.currentWorkSpace.currentMainWindowNode)
    elif key == ('0') or isHomeKey(key):
      status.bufStatus[status.currentBuffer].deleteCharacterBeginningOfLine(status.settings.autoDeleteParen, status.currentWorkSpace.currentMainWindowNode)
  elif key == ord('y'):
    let key = getkey(status.currentWorkSpace.currentMainWindowNode.window)
    if key == ord('y'): yankLines(status, status.bufStatus[currentBuf].currentLine, min(status.bufStatus[currentBuf].currentLine + cmdLoop - 1, status.bufStatus[currentBuf].buffer.high))
    elif key == ord('w'): yankWord(status, cmdLoop)
  elif key == ord('p'):
    pasteAfterCursor(status)
  elif key == ord('P'):
    pasteBeforeCursor(status)
  elif key == ord('>'):
    for i in 0 ..< cmdLoop: addIndent(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode, status.settings.tabStop)
  elif key == ord('<'):
    for i in 0 ..< cmdLoop: deleteIndent(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode, status.settings.tabStop)
  elif key == ord('J'):
    joinLine(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
  elif key == ord('r'):
    if cmdLoop > status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len - status.bufStatus[currentBuf].currentColumn: return

    let ch = getKey(status.currentWorkSpace.currentMainWindowNode.window)
    for i in 0 ..< cmdLoop:
      if i > 0:
        inc(status.bufStatus[status.currentBuffer].currentColumn)
        status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn
      status.bufStatus[status.currentBuffer].replaceCurrentCharacter(status.currentWorkSpace.currentMainWindowNode, status.settings.autoIndent, status.settings.autoDeleteParen, ch)
  elif key == ord('n'):
    searchNextOccurrence(status)
  elif key == ord('N'):
    searchNextOccurrenceReversely(status)
  elif key == ord('f'):
    let key = getKey(status.currentWorkSpace.currentMainWindowNode.window)
    searchOneCharactorToEndOfLine(status.bufStatus[status.currentBuffer], key)
  elif key == ord('F'):
    let key = getKey(status.currentWorkSpace.currentMainWindowNode.window)
    searchOneCharactorToBeginOfLine(status.bufStatus[status.currentBuffer], key)
  elif key == ord('R'):
    status.changeMode(Mode.replace)
  elif key == ord('i'):
    status.changeMode(Mode.insert)
  elif key == ord('I'):
    status.bufStatus[status.currentBuffer].currentColumn = 0
    status.changeMode(Mode.insert)
  elif key == ord('v'):
    status.changeMode(Mode.visual)
  elif key == ord('a'):
    let lineWidth = status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len
    if lineWidth == 0: discard
    elif lineWidth == status.bufStatus[currentBuf].currentColumn: discard
    else: inc(status.bufStatus[currentBuf].currentColumn)
    status.changeMode(Mode.insert)
  elif key == ord('A'):
    status.bufStatus[currentBuf].currentColumn = status.bufStatus[currentBuf].buffer[status.bufStatus[currentBuf].currentLine].len
    status.changeMode(Mode.insert)
  elif key == ord('u'):
    undo(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
  elif isControlR(key):
    redo(status.bufStatus[status.currentBuffer], status.currentWorkSpace.currentMainWindowNode)
  elif key == ord('Z'):
    let key = getKey(status.currentWorkSpace.currentMainWindowNode.window)
    if  key == ord('Z'): writeFileAndExit(status)
    elif key == ord('Q'): forceExit(status)
  else:
    discard

proc normalMode*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].cmdLoop = 0
  status.resize(terminalHeight(), terminalWidth())
  var countChange = 0

  changeCursorType(status.settings.normalModeCursor)

  while status.bufStatus[status.currentBuffer].mode == Mode.normal and status.currentWorkSpace.numOfMainWindow > 0:
    if status.bufStatus[status.currentBuffer].countChange > countChange:
      status.updateHighlight(status.currentBuffer)
      countChange = status.bufStatus[status.currentBuffer].countChange

    status.update

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(status.currentWorkSpace.currentMainWindowNode.window)

    status.bufStatus[status.currentBuffer].buffer.beginNewSuitIfNeeded
    status.bufStatus[status.currentBuffer].tryRecordCurrentPosition

    if isEscKey(key):
      let keyAfterEsc = getKey(status.currentWorkSpace.currentMainWindowNode.window)
      if isEscKey(keyAfterEsc):
        turnOffHighlighting(status)
        continue
      else: key = keyAfterEsc

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif key == ord('/'):
      status.changeMode(Mode.search)
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif isDigit(key):
      let num = ($key)[0]
      if status.bufStatus[status.currentBuffer].cmdLoop == 0 and num == '0':
        normalCommand(status, key)
        continue

      status.bufStatus[status.currentBuffer].cmdLoop *= 10
      status.bufStatus[status.currentBuffer].cmdLoop += ord(num)-ord('0')
      status.bufStatus[status.currentBuffer].cmdLoop = min(100000, status.bufStatus[status.currentBuffer].cmdLoop)
      continue
    else:
      normalCommand(status, key)
      status.bufStatus[status.currentBuffer].cmdLoop = 0
