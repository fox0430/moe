import deques, strutils, strformat, sequtils, terminal, macros
from os import execShellCmd
import ui, editorstatus, gapbuffer, unicodeext, undoredostack, window,
       movement, editor, bufferstatus

proc correspondingCloseParen(c: char): char =
  case c
  of '(': return ')'
  of '{': return '}'
  of '[': return ']'
  of '"': return  '\"'
  of '\'': return '\''
  else: doAssert(false, fmt"Invalid parentheses: {c}")

proc isOpenParen(ch: char): bool = ch in {'(', '{', '[', '\"', '\''}

proc isCloseParen(ch: char): bool = ch in {')', '}', ']', '\"', '\''}

proc nextRuneIs(bufStatus: var BufferStatus,
                windowNode: WindowNode,
                c: Rune): bool =

  if bufStatus.buffer[windowNode.currentLine].len > windowNode.currentColumn:
    result =
      bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn] == c

proc insertCharacter*(bufStatus: var BufferStatus,
                      windowNode: WindowNode,
                      autoCloseParen: bool, c: Rune) =

  let oldLine = bufStatus.buffer[windowNode.currentLine]
  var newLine = bufStatus.buffer[windowNode.currentLine]
  template insert = newLine.insert(c, windowNode.currentColumn)
  template moveRight = inc(windowNode.currentColumn)
  template inserted =
    if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine
    inc(bufStatus.countChange)

  if autoCloseParen and canConvertToChar(c):
    let ch = c.toChar
    if isCloseParen(ch) and bufStatus.nextRuneIs(windowNode, c):
      moveRight()
      inserted()
    elif isOpenParen(ch):
      insert()
      moveRight()
      newLine.insert(correspondingCloseParen(ch).ru, windowNode.currentColumn)
      inserted()
    else:
      insert()
      moveRight()
      inserted()
  else:
    insert()
    moveRight()
    inserted()

proc currentLineDeleteCharacterBeforeCursor(bufStatus: var BufferStatus,
                                            windowNode: WindowNode,
                                            autoDeleteParen: bool) =

  if windowNode.currentLine == 0 and windowNode.currentColumn == 0: return

  dec(windowNode.currentColumn)
  let
    currentChar = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]
    oldLine     = bufStatus.buffer[windowNode.currentLine]
  var newLine   = bufStatus.buffer[windowNode.currentLine]
  newLine.delete(windowNode.currentColumn)

  if oldLine != newLine:
    bufStatus.buffer[windowNode.currentLine] = newLine

  if autoDeleteParen:
    bufStatus.deleteParen(windowNode, currentChar)

  if(bufStatus.mode == Mode.insert and
     windowNode.currentColumn > bufStatus.buffer[windowNode.currentLine].len):
    windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine].len
  
  inc(bufStatus.countChange)
     
proc currentLineDeleteLineBreakBeforeCursor*(bufStatus: var BufferStatus,
                                             windowNode: WindowNode,
                                             autoDeleteParen : bool) =

  if windowNode.currentLine == 0 and windowNode.currentColumn == 0: return

  windowNode.currentColumn = bufStatus.buffer[windowNode.currentLine - 1].len

  let oldLine = bufStatus.buffer[windowNode.currentLine - 1]
  var newLine = bufStatus.buffer[windowNode.currentLine - 1]
  newLine &= bufStatus.buffer[windowNode.currentLine]
  bufStatus.buffer.delete(windowNode.currentLine, windowNode.currentLine)
  if oldLine != newLine: bufStatus.buffer[windowNode.currentLine - 1] = newLine

  dec(windowNode.currentLine)
  
  inc(bufStatus.countChange)

proc keyBackspace*(bufStatus: var BufferStatus,
                   windowNode: WindowNode,
                   autoDeleteParen: bool) =

  if windowNode.currentColumn == 0:
    currentLineDeleteLineBreakBeforeCursor(bufStatus, windowNode, autoDeleteParen)
  else:
    currentLineDeleteCharacterBeforeCursor(bufStatus, windowNode, autoDeleteParen)

proc deleteBeforeCursorToFirstNonBlank*(bufStatus: var BufferStatus,
                                        windowNode: WindowNode  ) =
  if windowNode.currentColumn == 0:
    return
  let firstNonBlank = getFirstNonBlankOfLineOrFirstColumn(bufStatus, windowNode)
  
  for _ in firstNonBlank..max(0, windowNode.currentColumn-1):
    currentLineDeleteCharacterBeforeCursor(bufStatus, windowNode, false)

proc insertIndent(bufStatus: var BufferStatus, windowNode: WindowNode) =
  let indent = min(countRepeat(bufStatus.buffer[windowNode.currentLine], Whitespace, 0),
                   windowNode.currentColumn)

  let oldLine = bufStatus.buffer[windowNode.currentLine + 1]
  var newLine = bufStatus.buffer[windowNode.currentLine + 1]
  newLine &= repeat(' ', indent).toRunes
  if oldLine != newLine: bufStatus.buffer[windowNode.currentLine + 1] = newLine

proc keyEnter*(bufStatus: var BufferStatus, windowNode: WindowNode, autoIndent: bool) =
  bufStatus.buffer.insert(ru"", windowNode.currentLine + 1)

  if autoIndent:
    bufStatus.insertIndent(windowNode)

    var startOfCopy = max(
      countRepeat(bufStatus.buffer[windowNode.currentLine], Whitespace, 0),
      windowNode.currentColumn)
    startOfCopy += countRepeat(bufStatus.buffer[windowNode.currentLine],
                               Whitespace, startOfCopy)

    block:
      let oldLine = bufStatus.buffer[windowNode.currentLine + 1]
      var newLine = bufStatus.buffer[windowNode.currentLine + 1]

      let
        line = windowNode.currentLine
        startCol = startOfCopy
        endCol = bufStatus.buffer[windowNode.currentLine].len
      newLine &= bufStatus.buffer[line][startCol ..< endCol]

      if oldLine != newLine: bufStatus.buffer[windowNode.currentLine + 1] = newLine
    
    block:
      let
        first = windowNode.currentColumn
        last = bufStatus.buffer[windowNode.currentLine].high
      if first <= last:
        let oldLine = bufStatus.buffer[windowNode.currentLine]
        var newLine = bufStatus.buffer[windowNode.currentLine]
        newLine.delete(first, last)
        if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine

    inc(windowNode.currentLine)
    windowNode.currentColumn =
      countRepeat(bufStatus.buffer[windowNode.currentLine], Whitespace, 0)
  else:
    block:
      let oldLine = bufStatus.buffer[windowNode.currentLine + 1]
      var newLine = bufStatus.buffer[windowNode.currentLine + 1]

      let
        line = windowNode.currentLine
        startCol = windowNode.currentColumn
        endCol = bufStatus.buffer[windowNode.currentLine].len
      newLine &= bufStatus.buffer[line][startCol ..< endCol]

      if oldLine != newLine: bufStatus.buffer[windowNode.currentLine + 1] = newLine

    block:
      let oldLine = bufStatus.buffer[windowNode.currentLine]
      var newLine = bufStatus.buffer[windowNode.currentLine]
      newLine.delete(windowNode.currentColumn,
                     bufStatus.buffer[windowNode.currentLine].high)
      if oldLine != newLine: bufStatus.buffer[windowNode.currentLine] = newLine

    inc(windowNode.currentLine)
    windowNode.currentColumn = 0
    windowNode.expandedColumn = 0

  inc(bufStatus.countChange)

proc insertTab(bufStatus: var BufferStatus,
               windowNode: WindowNode,
               tabStop: int,
               autoCloseParen: bool) =

  for i in 0 ..< tabStop:
    insertCharacter(bufStatus, windowNode, autoCloseParen, ru' ')

proc insertCharacterBelowCursor(bufStatus: var BufferStatus,
                              windowNode: WindowNode) =

  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
    buffer = bufStatus.buffer

  if currentLine == bufStatus.buffer.high: return
  if currentColumn > buffer[currentLine + 1].high: return

  let
    copyRune = buffer[currentLine + 1][currentColumn]
    oldLine = buffer[currentLine]
  var newLine = buffer[currentLine]

  newLine.insert(copyRune, currentColumn)
  if newLine != oldLine:
    bufStatus.buffer[currentLine] = newLine
    inc windowNode.currentColumn

proc insertCharacterAboveCursor(bufStatus: var BufferStatus,
                              windowNode: WindowNode) =

  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
    buffer = bufStatus.buffer

  if currentLine == 0: return
  if currentColumn > buffer[currentLine - 1].high: return

  let
    copyRune = buffer[currentLine - 1][currentColumn]
    oldLine = buffer[currentLine]
  var newLine = buffer[currentLine]

  newLine.insert(copyRune, currentColumn)
  if newLine != oldLine:
    bufStatus.buffer[currentLine] = newLine
    inc windowNode.currentColumn

proc isInsertMode(status: EditorStatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    bufferIndex =
      status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
    mode = status.bufStatus[bufferIndex].mode
  return mode == Mode.insert

proc insertMode*(status: var EditorStatus) =
  changeCursorType(status.settings.insertModeCursor)

  status.resize(terminalHeight(), terminalWidth())

  while status.isInsertMode:
    let
      currentBufferIndex = status.bufferIndexInCurrentWindow
      workspaceIndex = status.currentWorkSpaceIndex

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key =
        getKey(status.workSpace[workspaceIndex].currentMainWindowNode.window)

    var windowNode = status.workSpace[workspaceIndex].currentMainWindowNode

    status.bufStatus[currentBufferIndex].buffer.beginNewSuitIfNeeded
    status.bufStatus[currentBufferIndex].tryRecordCurrentPosition(windowNode)
    
    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      if windowNode.currentColumn > 0: dec(windowNode.currentColumn)
      windowNode.expandedColumn = windowNode.currentColumn
      status.changeMode(Mode.normal)
    elif isControlU(key):
      status.bufStatus[currentBufferIndex].deleteBeforeCursorToFirstNonBlank(
        status.workSpace[workspaceIndex].currentMainWindowNode)
    elif isLeftKey(key):
      windowNode.keyLeft
    elif isRightkey(key):
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(windowNode)
    elif isPageUpKey(key):
      pageUp(status)
    elif isPageDownKey(key):
      pageDown(status)
    elif isHomeKey(key):
      windowNode.moveToFirstOfLine
    elif isEndKey(key):
      status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
    elif isDcKey(key):
      status.bufStatus[currentBufferIndex].deleteCurrentCharacter(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.autoDeleteParen)
    elif isBackspaceKey(key):
      status.bufStatus[currentBufferIndex].keyBackspace(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.autoDeleteParen)
    elif isEnterKey(key):
      keyEnter(status.bufStatus[currentBufferIndex],
               status.workSpace[workspaceIndex].currentMainWindowNode,
               status.settings.autoIndent)
    elif key == ord('\t'):
      insertTab(status.bufStatus[currentBufferIndex],
                status.workSpace[workspaceIndex].currentMainWindowNode,
                status.settings.tabStop,
                status.settings.autoCloseParen)
    elif isControlE(key):
      status.bufStatus[currentBufferIndex].insertCharacterBelowCursor(
        status.workSpace[workspaceIndex].currentMainWindowNode
      )
    elif isControlY(key):
      status.bufStatus[currentBufferIndex].insertCharacterAboveCursor(
        status.workSpace[workspaceIndex].currentMainWindowNode
      )
    else:
      insertCharacter(status.bufStatus[currentBufferIndex],
                      status.workSpace[workspaceIndex].currentMainWindowNode,
                      status.settings.autoCloseParen, key)

  stdout.write "\x1b[2 q"
