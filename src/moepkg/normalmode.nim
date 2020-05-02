import strformat, terminal
import editorstatus, ui, gapbuffer, unicodeext, fileutils, commandview, undoredostack, window, movement, editor, searchmode, color, bufferstatus

proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  status.commandWindow.erase

  let windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  status.commandWindow.write(0, 0, "debuf info: ", EditorColorPair.commandBar)
  status.commandWindow.append(fmt"currentLine: {windowNode.currentLine}, currentColumn: {windowNode.currentColumn}")
  status.commandWindow.append(fmt", cursor.y: {windowNode.cursor.y}, cursor.x: {windowNode.cursor.x}")
  status.commandWindow.append(fmt", {str}")

  status.commandWindow.refresh

proc searchOneCharactorToEndOfLine(bufStatus: var BufferStatus, windowNode: WindowNode, rune: Rune) =
  let line = bufStatus.buffer[windowNode.currentLine]

  if line.len < 1 or isEscKey(rune) or (windowNode.currentColumn == line.high): return

  for col in windowNode.currentColumn + 1 ..< line.len:
    if line[col] == rune:
      windowNode.currentColumn = col
      break

proc searchOneCharactorToBeginOfLine(bufStatus: var BufferStatus, windowNode: WindowNode, rune: Rune) =
  let line = bufStatus.buffer[windowNode.currentLine]

  if line.len < 1 or isEscKey(rune) or (windowNode.currentColumn == 0): return

  for col in countdown(windowNode.currentColumn - 1, 0):
    if line[col] == rune:
      windowNode.currentColumn = col
      break

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].isHighlight = true
  status.updateHighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)

  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  status.bufStatus[currentBufferIndex].keyRight(windowNode)
  let searchResult = status.searchBuffer(keyword)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column: status.bufStatus[currentBufferIndex].keyRight(windowNode)
  elif searchResult.line == -1: windowNode.keyLeft

proc searchNextOccurrenceReversely(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].isHighlight = true
  status.updateHighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)

  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  windowNode.keyLeft
  let searchResult = status.searchBufferReversely(keyword)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column: status.bufStatus[currentBufferIndex].keyRight(windowNode)
  elif searchResult.line == -1:
    status.bufStatus[currentBufferIndex].keyRight(windowNode)

proc turnOffHighlighting*(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].isHighlight = false
  status.updateHighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc undo(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if not bufStatus.buffer.canUndo: return
  bufStatus.buffer.undo
  bufStatus.revertPosition(windowNode, bufStatus.buffer.lastSuitId)
  if windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].len and windowNode.currentColumn > 0:
    (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.prev(windowNode.currentLine, windowNode.currentColumn)
  inc(bufStatus.countChange)

proc redo(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if not bufStatus.buffer.canRedo: return
  bufStatus.buffer.redo
  bufStatus.revertPosition(windowNode, bufStatus.buffer.lastSuitId)
  inc(bufStatus.countChange)

proc writeFileAndExit(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].filename.len == 0:
    status.commandwindow.writeNoFileNameError(status.messageLog)
    status.changeMode(Mode.normal)
  else:
    try:
      saveFile(status.bufStatus[currentBufferIndex].filename, status.bufStatus[currentBufferIndex].buffer.toRunes, status.settings.characterEncoding)
      status.closeWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    except IOError:
      status.commandWindow.writeSaveError(status.messageLog)

proc forceExit(status: var Editorstatus) = status.closeWindow(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc normalCommand*(status: var EditorStatus, key: Rune) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  if status.bufStatus[currentBufferIndex].cmdLoop == 0: status.bufStatus[currentBufferIndex].cmdLoop = 1

  let cmdLoop = status.bufStatus[currentBufferIndex].cmdLoop
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  if isControlK(key):
    moveNextWindow(status)
  elif isControlJ(key):
    movePrevWindow(status)
  elif isControlV(key):
    status.changeMode(Mode.visualBlock)
  elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< cmdLoop: windowNode.keyLeft
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< cmdLoop: status.bufStatus[currentBufferIndex].keyRight(windowNode)
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< cmdLoop: status.bufStatus[currentBufferIndex].keyUp(windowNode)
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< cmdLoop: status.bufStatus[currentBufferIndex].keyDown(windowNode)
  elif key == ord('x') or isDcKey(key):
    status.yankString(min(cmdLoop, status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len - windowNode.currentColumn))
    for i in 0 ..< min(cmdLoop, status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len - windowNode.currentColumn):
      status.bufStatus[currentBufferIndex].deleteCurrentCharacter(windowNode, status.settings.autoDeleteParen)
  elif key == ord('^'):
    status.bufStatus[currentBufferIndex].moveToFirstNonBlankOfLine(windowNode)
  elif key == ord('0') or isHomeKey(key):
    windowNode.moveToFirstOfLine
  elif key == ord('$') or isEndKey(key):
    status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
  elif key == ord('-'):
    status.bufStatus[currentBufferIndex].moveToFirstOfPreviousLine(windowNode)
  elif key == ord('+'):
    status.bufStatus[currentBufferIndex].moveToFirstOfNextLine(windowNode)
  elif key == ord('g'):
    if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == ord('g'): moveToFirstLine(status)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isPageUpkey(key) or isControlU(key):
    for i in 0 ..< cmdLoop: pageUp(status)
  elif isPageDownKey(key): ## Page down and Ctrl - F
    for i in 0 ..< cmdLoop: pageDown(status)
  elif key == ord('w'):
    for i in 0 ..< cmdLoop: status.bufStatus[currentBufferIndex].moveToForwardWord(windowNode)
  elif key == ord('b'):
    for i in 0 ..< cmdLoop: status.bufStatus[currentBufferIndex].moveToBackwardWord(windowNode)
  elif key == ord('e'):
    for i in 0 ..< cmdLoop: status.bufStatus[currentBufferIndex].moveToForwardEndOfWord(windowNode)
  elif key == ord('z'):
    let key = getkey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if key == ord('.'): moveCenterScreen(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('t'): scrollScreenTop(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('b'): scrollScreenBottom(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('o'):
    for i in 0 ..< cmdLoop: openBlankLineBelow(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< cmdLoop: openBlankLineAbove(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.updateHighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.changeMode(Mode.insert)
  elif key == ord('d'):
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if key == ord('d'):
      status.yankLines(windowNode.currentLine, min(windowNode.currentLine + cmdLoop - 1, status.bufStatus[currentBufferIndex].buffer.high))
      for i in 0 ..< min(cmdLoop, status.bufStatus[currentBufferIndex].buffer.len - windowNode.currentLine):
        status.bufStatus[currentBufferIndex].deleteLine(windowNode, windowNode.currentLine)
    elif key == ord('w'): status.bufStatus[currentBufferIndex].deleteWord(windowNode)
    elif key == ('$') or isEndKey(key):
      status.bufStatus[currentBufferIndex].deleteCharacterUntilEndOfLine(status.settings.autoDeleteParen, windowNode)
    elif key == ('0') or isHomeKey(key):
      status.bufStatus[currentBufferIndex].deleteCharacterBeginningOfLine(status.settings.autoDeleteParen, windowNode)
  elif key == ord('y'):
    let key = getkey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if key == ord('y'): status.yankLines(windowNode.currentLine, min(windowNode.currentLine + cmdLoop - 1, status.bufStatus[currentBufferIndex].buffer.high))
    elif key == ord('w'): status.yankWord(cmdLoop)
  elif key == ord('p'):
    status.pasteAfterCursor
  elif key == ord('P'):
    status.pasteBeforeCursor
  elif key == ord('>'):
    for i in 0 ..< cmdLoop: status.bufStatus[currentBufferIndex].addIndent(windowNode, status.settings.tabStop)
  elif key == ord('<'):
    for i in 0 ..< cmdLoop: deleteIndent(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings.tabStop)
  elif key == ord('J'):
    joinLine(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('r'):
    if cmdLoop > status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len - windowNode.currentColumn: return

    let ch = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    for i in 0 ..< cmdLoop:
      if i > 0:
        inc(windowNode.currentColumn)
        windowNode.expandedColumn = windowNode.currentColumn
      status.bufStatus[currentBufferIndex].replaceCurrentCharacter(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings.autoIndent, status.settings.autoDeleteParen, ch)
  elif key == ord('n'):
    searchNextOccurrence(status)
  elif key == ord('N'):
    searchNextOccurrenceReversely(status)
  elif key == ord('f'):
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    status.bufStatus[currentBufferIndex].searchOneCharactorToEndOfLine(windowNode, key)
  elif key == ord('F'):
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    status.bufStatus[currentBufferIndex].searchOneCharactorToBeginOfLine(windowNode, key)
  elif key == ord('R'):
    status.changeMode(Mode.replace)
  elif key == ord('i'):
    status.changeMode(Mode.insert)
  elif key == ord('I'):
    windowNode.currentColumn = 0
    status.changeMode(Mode.insert)
  elif key == ord('v'):
    status.changeMode(Mode.visual)
  elif key == ord('a'):
    let lineWidth = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len
    if lineWidth == 0: discard
    elif lineWidth == windowNode.currentColumn: discard
    else: inc(windowNode.currentColumn)
    status.changeMode(Mode.insert)
  elif key == ord('A'):
    windowNode.currentColumn = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len
    status.changeMode(Mode.insert)
  elif key == ord('u'):
    status.bufStatus[currentBufferIndex].undo(windowNode)
  elif isControlR(key):
    redo(status.bufStatus[currentBufferIndex], status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('Z'):
    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
    if  key == ord('Z'): writeFileAndExit(status)
    elif key == ord('Q'): forceExit(status)
  else:
    discard

proc isNormalMode(status: Editorstatus): bool = status.bufStatus[status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex].mode == Mode.normal

proc normalMode*(status: var EditorStatus) =
  changeCursorType(status.settings.normalModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex
  var countChange = 0

  while status.isNormalMode and currentWorkSpace == status.currentWorkSpaceIndex and currentBufferIndex == status.bufferIndexInCurrentWindow:
    if status.bufStatus[currentBufferIndex].countChange > countChange:
      countChange = status.bufStatus[currentBufferIndex].countChange

    status.update

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

    if isEscKey(key):
      let keyAfterEsc = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
      if isEscKey(keyAfterEsc):
        status.turnOffHighlighting
        continue
      else: key = keyAfterEsc

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif key == ord('/'):
      status.changeMode(Mode.search)
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif isDigit(key):
      let num = ($key)[0]
      if status.bufStatus[currentBufferIndex].cmdLoop == 0 and num == '0':
        status.normalCommand(key)
        continue

      status.bufStatus[currentBufferIndex].cmdLoop *= 10
      status.bufStatus[currentBufferIndex].cmdLoop += ord(num)-ord('0')
      status.bufStatus[currentBufferIndex].cmdLoop = min(100000, status.bufStatus[currentBufferIndex].cmdLoop)
      continue
    else:
      status.normalCommand(key)
      status.bufStatus[currentBufferIndex].cmdLoop = 0
