import deques, strutils, strformat, sequtils, terminal, macros
from os import execShellCmd
import ui, editorstatus, editorview, gapbuffer, editorview, normalmode, unicodeext, highlight, undoredostack

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

proc nextRuneIs(bufStatus: var BufferStatus, c: Rune): bool =
  if bufStatus.buffer[bufStatus.currentLine].len > bufStatus.currentColumn:
    result = bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn] == c

proc insertCharacter(bufStatus: var BufferStatus, autoCloseParen: bool, c: Rune) =
  let oldLine = bufStatus.buffer[bufStatus.currentLine]
  var newLine = bufStatus.buffer[bufStatus.currentLine]
  template insert = newLine.insert(c, bufStatus.currentColumn)
  template moveRight = inc(bufStatus.currentColumn)
  template inserted =
    if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine
    bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
    inc(bufStatus.countChange)

  if autoCloseParen and canConvertToChar(c):
    let ch = c.toChar
    if isCloseParen(ch) and nextRuneIs(bufStatus, c):
      moveRight()
      inserted()
    elif isOpenParen(ch):
      insert()
      moveRight()
      newLine.insert(correspondingCloseParen(ch).ru, bufStatus.currentColumn)
      inserted()
    else:
      insert()
      moveRight()
      inserted()
  else:
    insert()
    moveRight()
    inserted()

proc keyBackspace(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == 0 and bufStatus.currentColumn == 0: return

  if bufStatus.currentColumn == 0:
    bufStatus.currentColumn = bufStatus.buffer[bufStatus.currentLine - 1].len

    let oldLine = bufStatus.buffer[bufStatus.currentLine - 1]
    var newLine = bufStatus.buffer[bufStatus.currentLine - 1]
    newLine &= bufStatus.buffer[bufStatus.currentLine]
    bufStatus.buffer.delete(bufStatus.currentLine, bufStatus.currentLine)
    if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine - 1] = newLine

    dec(bufStatus.currentLine)
  else:
    dec(bufStatus.currentColumn)

    let oldLine = bufStatus.buffer[bufStatus.currentLine]
    var newLine = bufStatus.buffer[bufStatus.currentLine]
    newLine.delete(bufStatus.currentColumn)
    if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc insertIndent(bufStatus: var BufferStatus) =
  let indent = min(countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0), bufStatus.currentColumn)

  let oldLine = bufStatus.buffer[bufStatus.currentLine + 1]
  var newLine = bufStatus.buffer[bufStatus.currentLine + 1]
  newLine &= repeat(' ', indent).toRunes
  if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine + 1] = newLine

proc keyEnter*(bufStatus: var BufferStatus, autoIndent: bool) =
  bufStatus.buffer.insert(ru"", bufStatus.currentLine + 1)

  if autoIndent:
    insertIndent(bufStatus)

    var startOfCopy = max(countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0), bufStatus.currentColumn)
    startOfCopy += countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, startOfCopy)

    block:
      let oldLine = bufStatus.buffer[bufStatus.currentLine + 1]
      var newLine = bufStatus.buffer[bufStatus.currentLine + 1]
      newLine &= bufStatus.buffer[bufStatus.currentLine][startOfCopy ..< bufStatus.buffer[bufStatus.currentLine].len]
      if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine + 1] = newLine
    
    block:
      let
        first = bufStatus.currentColumn
        last = bufStatus.buffer[bufStatus.currentLine].high
      if first <= last:
        let oldLine = bufStatus.buffer[bufStatus.currentLine]
        var newLine = bufStatus.buffer[bufStatus.currentLine]
        newLine.delete(first, last)
        if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

    inc(bufStatus.currentLine)
    bufStatus.currentColumn = countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0)
  else:
    block:
      let oldLine = bufStatus.buffer[bufStatus.currentLine + 1]
      var newLine = bufStatus.buffer[bufStatus.currentLine + 1]
      newLine &= bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn ..< bufStatus.buffer[bufStatus.currentLine].len]
      if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine + 1] = newLine

    block:
      let oldLine = bufStatus.buffer[bufStatus.currentLine]
      var newLine = bufStatus.buffer[bufStatus.currentLine]
      newLine.delete(bufStatus.currentColumn, bufStatus.buffer[bufStatus.currentLine].high)
      if oldLine != newLine: bufStatus.buffer[bufStatus.currentLine] = newLine

    inc(bufStatus.currentLine)
    bufStatus.currentColumn = 0
    bufStatus.expandedColumn = 0

  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

proc insertTab(bufStatus: var BufferStatus, tabStop: int, autoCloseParen: bool) =
  for i in 0 ..< tabStop: insertCharacter(bufStatus, autoCloseParen, ru' ')

proc insertMode*(status: var EditorStatus) =
  changeCursorType(status.settings.insertModeCursor)
  var bufferChanged = false

  while status.bufStatus[status.currentBuffer].mode == Mode.insert:
    if bufferChanged:
      status.updateHighlight
      bufferChanged = false

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key = getKey(status.currentMainWindowNode.mainWindowInfo.window)

    status.bufStatus[status.currentBuffer].buffer.beginNewSuitIfNeeded
    status.bufStatus[status.currentBuffer].tryRecordCurrentPosition
    
    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      if status.bufStatus[status.currentBuffer].currentColumn > 0: dec(status.bufStatus[status.currentBuffer].currentColumn)
      status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn
      status.changeMode(Mode.normal)
    elif isLeftKey(key):
      keyLeft(status.bufStatus[status.currentBuffer])
    elif isRightkey(key):
      keyRight(status.bufStatus[status.currentBuffer])
    elif isUpKey(key):
      keyUp(status.bufStatus[status.currentBuffer])
    elif isDownKey(key):
      keyDown(status.bufStatus[status.currentBuffer])
    elif isPageUpKey(key):
      pageUp(status)
    elif isPageDownKey(key):
      pageDown(status)
    elif isHomeKey(key):
      moveToFirstOfLine(status.bufStatus[status.currentBuffer])
    elif isEndKey(key):
      moveToLastOfLine(status.bufStatus[status.currentBuffer])
    elif isDcKey(key):
      deleteCurrentCharacter(status.bufStatus[status.currentBuffer])
      bufferChanged = true
    elif isBackspaceKey(key):
      keyBackspace(status.bufStatus[status.currentBuffer])
      bufferChanged = true
    elif isEnterKey(key):
      keyEnter(status.bufStatus[status.currentBuffer], status.settings.autoIndent)
      bufferChanged = true
    elif key == ord('\t'):
      insertTab(status.bufStatus[status.currentBuffer], status.settings.tabStop, status.settings.autoCloseParen)
      bufferChanged = true
    else:
      insertCharacter(status.bufStatus[status.currentBuffer], status.settings.autoCloseParen, key)
      bufferChanged = true

  stdout.write "\x1b[2 q"
