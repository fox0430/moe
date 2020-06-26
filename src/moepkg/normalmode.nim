from strutils import parseInt
import strformat, terminal
import editorstatus, ui, gapbuffer, unicodeext, fileutils, commandview,
       undoredostack, window, movement, editor, search, color,
       bufferstatus

proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  status.commandWindow.erase

  let windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  status.commandWindow.write(0, 0, "debuf info: ", EditorColorPair.commandBar)
  status.commandWindow.append(fmt"currentLine: {windowNode.currentLine}, currentColumn: {windowNode.currentColumn}")
  status.commandWindow.append(fmt", cursor.y: {windowNode.cursor.y}, cursor.x: {windowNode.cursor.x}")
  status.commandWindow.append(fmt", {str}")

  status.commandWindow.refresh

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
  
  status.bufStatus[currentBufferIndex].isHighlight = true

  status.updateHighlight(status.workspace[workspaceIndex].currentMainWindowNode)

  var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode

  status.bufStatus[currentBufferIndex].keyRight(windowNode)
  let searchResult = status.searchBuffer(keyword)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column:
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
  elif searchResult.line == -1: windowNode.keyLeft

proc searchNextOccurrence(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]

  searchNextOccurrence(status, keyword)

proc searchNextOccurrenceReversely(status: var EditorStatus, keyword: seq[Rune]) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex

  status.bufStatus[currentBufferIndex].isHighlight = true
  status.updateHighlight(status.workspace[workspaceIndex].currentMainWindowNode)

  var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode

  windowNode.keyLeft
  let searchResult = status.searchBufferReversely(keyword)
  if searchResult.line > -1:
    status.jumpLine(searchResult.line)
    for column in 0 ..< searchResult.column:
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
  elif searchResult.line == -1:
    status.bufStatus[currentBufferIndex].keyRight(windowNode)

proc searchNextOccurrenceReversely(status: var EditorStatus) =
  if status.searchHistory.len < 1: return

  let keyword = status.searchHistory[status.searchHistory.high]
  
  searchNextOccurrenceReversely(status, keyword)


proc turnOffHighlighting*(status: var EditorStatus) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex

  status.bufStatus[currentBufferIndex].isHighlight = false
  status.updateHighlight(status.workspace[workspaceIndex].currentMainWindowNode)

proc undo(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if not bufStatus.buffer.canUndo: return
  bufStatus.buffer.undo
  bufStatus.revertPosition(windowNode, bufStatus.buffer.lastSuitId)
  if windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].len and
     windowNode.currentColumn > 0:
    (windowNode.currentLine, windowNode.currentColumn) =
      bufStatus.buffer.prev(windowNode.currentLine,
      windowNode.currentColumn)

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
      saveFile(status.bufStatus[currentBufferIndex].filename,
               status.bufStatus[currentBufferIndex].buffer.toRunes,
               status.settings.characterEncoding)
      let workspaceIndex = status.currentWorkSpaceIndex
      status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)
    except IOError:
      status.commandWindow.writeSaveError(status.messageLog)

proc forceExit(status: var Editorstatus) =
  let workspaceIndex = status.currentWorkSpaceIndex
  status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)

proc toggleCase(ch: Rune): Rune =
  result = ch
  if result.isUpper():
    result = result.toLower()
  elif result.isLower():
    result = result.toUpper()
  return result

proc normalCommand(status: var EditorStatus, key: Rune) =
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    workspaceIndex = status.currentWorkSpaceIndex

  if status.bufStatus[currentBufferIndex].cmdLoop == 0:
    status.bufStatus[currentBufferIndex].cmdLoop = 1

  let cmdLoop = status.bufStatus[currentBufferIndex].cmdLoop
  var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode

  template getWordUnderCursor(): (int, seq[Rune]) =
    let line = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine]
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
    let line = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine]
    if line.len() <= windowNode.currentColumn:
      return
      
    line[windowNode.currentColumn]

  template insertAfterCursor() =
    let lineWidth = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len
    if lineWidth == 0: discard
    elif lineWidth == windowNode.currentColumn: discard
    else: inc(windowNode.currentColumn)
    status.changeMode(Mode.insert)
  
  template insertCharacter(rune: Rune) =
    insertCharacter(
      status.bufStatus[currentBufferIndex],
      windowNode,
      status.settings.autoCloseParen,
      rune)
  
  template deleteCharactersUntilEndOfLine() =
    status.bufStatus[currentBufferIndex].deleteCharacterUntilEndOfLine(
      status.settings.autoDeleteParen, windowNode)
  
  template deleteCharactersOfLine() =
    status.bufStatus[currentBufferIndex].deleteCharactersOfLine(
      status.settings.autoDeleteParen,
      windowNode)
  
  template deleteCurrentCharacter() =
    status.bufStatus[currentBufferIndex].deleteCurrentCharacter(
      windowNode,
      status.settings.autoDeleteParen)
  
  template replaceCurrentCharacter(newCharacter: Rune) =
    status.bufStatus[currentBufferIndex].replaceCurrentCharacter(
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode,
      status.settings.autoIndent,
      status.settings.autoDeleteParen,
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

    if status.bufStatus[currentBufferIndex].countChange == 0 or
       status.workSpace[workspaceIndex].mainWindowNode.countReferencedWindow(
         currentBufferIndex
       ) > 1:
        status.closeWindow(status.workSpace[workspaceIndex].currentMainWindowNode)

  template getAnotherKey(): Rune =
    getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

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
    let
      lineWidth = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len
      loop = min(cmdLoop,
                 lineWidth - windowNode.currentColumn)
    status.yankString(loop)
    for i in 0 ..< loop:
      deleteCurrentCharacter()
  elif key == ord('^') or key == ord('_'):
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
    let secondKey = getAnotherKey()
    if secondKey == ord('g'):
      moveToFirstLine(status)
    elif secondKey == ord('_'):
      status.bufStatus[currentBufferIndex].moveToLastNonBlankOfLine(windowNode)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isControlU(key):
    for i in 0 ..< cmdLoop: halfPageUp(status)
  elif isControlD(key):
    for i in 0 ..< cmdLoop: halfPageDown(status)
  elif isPageUpkey(key):
    for i in 0 ..< cmdLoop: pageUp(status)
  elif isPageDownKey(key): ## Page down and Ctrl - F
    for i in 0 ..< cmdLoop: pageDown(status)
  elif key == ord('w'):
    for i in 0 ..< cmdLoop:
      status.bufStatus[currentBufferIndex].moveToForwardWord(windowNode)
  elif key == ord('b'):
    for i in 0 ..< cmdLoop:
      status.bufStatus[currentBufferIndex].moveToBackwardWord(windowNode)
  elif key == ord('e'):
    for i in 0 ..< cmdLoop:
      status.bufStatus[currentBufferIndex].moveToForwardEndOfWord(windowNode)
  elif key == ord('z'):
    let key = getAnotherKey()
    if key == ord('.'):
      moveCenterScreen(
        status.bufStatus[currentBufferIndex],
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('t'):
      scrollScreenTop(
        status.bufStatus[currentBufferIndex],
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    elif key == ord('b'):
      scrollScreenBottom(
        status.bufStatus[currentBufferIndex],
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('o'):
    for i in 0 ..< cmdLoop:
      openBlankLineBelow(
        status.bufStatus[currentBufferIndex],
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< cmdLoop:
      openBlankLineAbove(
        status.bufStatus[currentBufferIndex],
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.updateHighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)
    status.changeMode(Mode.insert)
  elif key == ord('c'):
    let key = getAnotherKey()
    if key == ord('c'):
      deleteCharactersOfLine()
      insertAfterCursor()
  elif key == ord('d'):
    let key = getAnotherKey()
    if key == ord('d'):
      let lastLine = min(windowNode.currentLine + cmdLoop - 1,
                         status.bufStatus[currentBufferIndex].buffer.high)
      status.yankLines(windowNode.currentLine, lastLine)
      let loop = min(cmdLoop,
                     status.bufStatus[currentBufferIndex].buffer.len - windowNode.currentLine)
      for i in 0 ..< loop:
        status.bufStatus[currentBufferIndex].deleteLine(windowNode, windowNode.currentLine)
    elif key == ord('w'): status.bufStatus[currentBufferIndex].deleteWord(windowNode)
    elif key == ('$') or isEndKey(key):
      deleteCharactersUntilEndOfLine()
    elif key == ('0') or isHomeKey(key):
      status.bufStatus[currentBufferIndex].deleteCharacterBeginningOfLine(
        status.settings.autoDeleteParen,
        windowNode)
  elif key == ord('D'):
     deleteCharactersUntilEndOfLine()
  elif key == ord('S'):
     deleteCharactersOfLine()
     insertAfterCursor()
  elif key == ord('y'):
    let key = getAnotherKey()
    if key == ord('y'):
      let lastLine = min(windowNode.currentLine + cmdLoop - 1,
                         status.bufStatus[currentBufferIndex].buffer.high)
      status.yankLines(windowNode.currentLine, lastLine)
    elif key == ord('w'): status.yankWord(cmdLoop)
  elif key == ord('p'):
    status.pasteAfterCursor
  elif key == ord('P'):
    status.pasteBeforeCursor
  elif key == ord('>'):
    for i in 0 ..< cmdLoop:
      status.bufStatus[currentBufferIndex].addIndent(
        windowNode,
        status.settings.tabStop)
  elif key == ord('<'):
    for i in 0 ..< cmdLoop:
      deleteIndent(
        status.bufStatus[currentBufferIndex],
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode,
        status.settings.tabStop)
  elif key == ord('='):
    let key = getAnotherKey()
    if key == ord('='):
      status.bufStatus[currentBufferIndex].autoIndentCurrentLine(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
      )
  elif key == ord('J'):
    joinLine(status.bufStatus[currentBufferIndex],
             status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif isControlA(key):
    modifyWordUnderCursor(cmdLoop)
  elif isControlX(key):
    modifyWordUnderCursor(-cmdLoop)
  elif key == ord('~'):
    for i in 0 ..< cmdLoop:
      replaceCurrentCharacter(toggleCase(getCharacterUnderCursor()))
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
  elif key == ord('r'):
    let
      lineWidth = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len
      loop = lineWidth - windowNode.currentColumn
    if cmdLoop > loop: return

    let ch = getAnotherKey()
    for i in 0 ..< cmdLoop:
      if i > 0:
        inc(windowNode.currentColumn)
        windowNode.expandedColumn = windowNode.currentColumn
      replaceCurrentCharacter(ch)
  elif key == ord('n'):
    searchNextOccurrence(status)
  elif key == ord('N'):
    searchNextOccurrenceReversely(status)
  elif key == ord('*'):
    searchNextOccurrence(status, getWordUnderCursor()[1])
  elif key == ord('#'):
    searchNextOccurrenceReversely(status, getWordUnderCursor()[1])
  elif key == ord('f'):
    let key = getAnotherKey()
    status.bufStatus[currentBufferIndex].searchOneCharactorToEndOfLine(windowNode, key)
  elif key == ord('F'):
    let key = getAnotherKey()
    status.bufStatus[currentBufferIndex].searchOneCharactorToBeginOfLine(windowNode, key)
  elif key == ord('R'):
    status.changeMode(Mode.replace)
  elif key == ord('i'):
    status.changeMode(Mode.insert)
  elif key == ord('I'):
    status.bufStatus[currentBufferIndex].moveToFirstNonBlankOfLine(windowNode)
    status.changeMode(Mode.insert)
  elif key == ord('v'):
    status.changeMode(Mode.visual)
  elif key == ord('a'):
    insertAfterCursor()
  elif key == ord('A'):
    windowNode.currentColumn = status.bufStatus[currentBufferIndex].buffer[windowNode.currentLine].len
    status.changeMode(Mode.insert)
  elif key == ord('u'):
    status.bufStatus[currentBufferIndex].undo(windowNode)
  elif isControlR(key):
    redo(status.bufStatus[currentBufferIndex],
         status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)
  elif key == ord('Z'):
    let key = getAnotherKey()
    if  key == ord('Z'): writeFileAndExit(status)
    elif key == ord('Q'): forceExit(status)
  elif isControlW(key):
    let key = getAnotherKey()
    if key == ord('c'): closeWindow()
  else:
    discard

proc isNormalMode(status: Editorstatus): bool =
  let index =
    status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[index].mode == Mode.normal

proc normalMode*(status: var EditorStatus) =
  changeCursorType(status.settings.normalModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex
  var countChange = 0

  while status.isNormalMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    if status.bufStatus[currentBufferIndex].countChange > countChange:
      countChange = status.bufStatus[currentBufferIndex].countChange

    status.update

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

    if isEscKey(key):
      let keyAfterEsc = getKey(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
      if isEscKey(keyAfterEsc):
        status.turnOffHighlighting
        continue
      else: key = keyAfterEsc

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif key == ord('/'):
      status.searchFordwards
    elif key == ord('?'):
      status.searchBackwards
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif isDigit(key):
      let num = ($key)[0]
      if status.bufStatus[currentBufferIndex].cmdLoop == 0 and num == '0':
        status.normalCommand(key)
        continue

      status.bufStatus[currentBufferIndex].cmdLoop *= 10
      status.bufStatus[currentBufferIndex].cmdLoop += ord(num)-ord('0')
      status.bufStatus[currentBufferIndex].cmdLoop = min(
        100000,
        status.bufStatus[currentBufferIndex].cmdLoop)
      continue
    else:
      status.normalCommand(key)
      status.bufStatus[currentBufferIndex].cmdLoop = 0
