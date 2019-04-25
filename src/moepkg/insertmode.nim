import deques, strutils, strformat, sequtils, terminal
from os import execShellCmd
import ui, editorstatus, editorview, cursor, gapbuffer, editorview, normalmode, unicodeext, highlight

proc insertCloseParen(status: var EditorStatus, c: char) =
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    currentColumn = status.bufStatus[status.currentBuffer].currentColumn

  case c
  of '(':
    status.bufStatus[status.currentBuffer].buffer[currentLine].insert(ru')', currentColumn)
  of '{':
    status.bufStatus[status.currentBuffer].buffer[currentLine].insert(ru'}', currentColumn)
  of '[':
    status.bufStatus[status.currentBuffer].buffer[currentLine].insert(ru']', currentColumn)
  of '"':
    status.bufStatus[status.currentBuffer].buffer[currentLine].insert(ru('\"'), currentColumn)
  of '\'':
    status.bufStatus[status.currentBuffer].buffer[currentLine].insert(ru'\'', currentColumn)
  else:
    doAssert(false, fmt"Invalid parentheses: {c}")

proc isOpenParen(ch: char): bool = ch in ['(', '{', '[', '\"', '\'']

proc insertCharacter(status: var EditorStatus, c: Rune) =
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    currentColumn = status.bufStatus[status.currentBuffer].currentColumn

  status.bufStatus[status.currentBuffer].buffer[currentLine].insert(c, currentColumn)
  inc(status.bufStatus[status.currentBuffer].currentColumn)

  if status.settings.autoCloseParen and canConvertToChar(c):
    let ch = c.toChar
    if isOpenParen(ch): insertCloseParen(status, ch)

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc keyBackspace(status: var EditorStatus) =
  let index = status.currentBuffer
  if status.bufStatus[status.currentBuffer].currentLine == 0 and status.bufStatus[status.currentBuffer].currentColumn == 0: return

  if status.bufStatus[index].currentColumn == 0:
    status.bufStatus[index].currentColumn = status.bufStatus[index].buffer[status.bufStatus[index].currentLine - 1].len
    status.bufStatus[index].buffer[status.bufStatus[index].currentLine - 1] &= status.bufStatus[index].buffer[status.bufStatus[index].currentLine]
    status.bufStatus[index].buffer.delete(status.bufStatus[index].currentLine, status.bufStatus[index].currentLine + 1)
    dec(status.bufStatus[index].currentLine)
  else:
    dec(status.bufStatus[index].currentColumn)
    status.bufStatus[index].buffer[status.bufStatus[index].currentLine].delete(status.bufStatus[index].currentColumn)

  status.bufStatus[index].view.reload(status.bufStatus[index].buffer, min(status.bufStatus[index].view.originalLine[0], status.bufStatus[index].buffer.high))
  inc(status.bufStatus[index].countChange)

proc insertIndent(status: var EditorStatus) =
  let
    index = status.currentBuffer
    indent = min(countRepeat(status.bufStatus[index].buffer[status.bufStatus[index].currentLine], Whitespace, 0), status.bufStatus[index].currentColumn)

  status.bufStatus[index].buffer[status.bufStatus[index].currentLine+1] &= repeat(' ', indent).toRunes

proc keyEnter*(status: var EditorStatus) =
  let
    index = status.currentBuffer
    currentLine = status.bufStatus[index].currentLine
    currentColumn = status.bufStatus[index].currentColumn
  status.bufStatus[index].buffer.insert(ru"", status.bufStatus[index].currentLine + 1)
  if status.settings.autoIndent:
    insertIndent(status)

    var startOfCopy = max(countRepeat(status.bufStatus[index].buffer[status.bufStatus[index].currentLine], Whitespace, 0), currentColumn)
    startOfCopy += countRepeat(status.bufStatus[index].buffer[status.bufStatus[index].currentLine], Whitespace, startOfCopy)

    status.bufStatus[index].buffer[currentLine + 1] &= status.bufStatus[index].buffer[currentLine][startOfCopy ..< status.bufStatus[index].buffer[currentLine].len]
    let
      first = status.bufStatus[index].currentColumn
      last = status.bufStatus[index].buffer[status.bufStatus[index].currentLine].high
    if first <= last: status.bufStatus[index].buffer[status.bufStatus[index].currentLine].delete(first, last)

    inc(status.bufStatus[index].currentLine)
    status.bufStatus[index].currentColumn = countRepeat(status.bufStatus[index].buffer[status.bufStatus[index].currentLine], Whitespace, 0)
  else:
    status.bufStatus[index].buffer[status.bufStatus[index].currentLine + 1] &= status.bufStatus[index].buffer[currentLine][currentColumn ..< status.bufStatus[index].buffer[currentLine].len]
    status.bufStatus[index].buffer[status.bufStatus[index].currentLine].delete(status.bufStatus[index].currentColumn, status.bufStatus[index].buffer[status.bufStatus[index].currentLine].high)

    inc(status.bufStatus[status.currentBuffer].currentLine)
    status.bufStatus[status.currentBuffer].currentColumn = 0
    status.bufStatus[status.currentBuffer].expandedColumn = 0

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc insertTab(status: var EditorStatus) =
  for i in 0 ..< status.settings.tabStop: insertCharacter(status, ru' ')

proc insertMode*(status: var EditorStatus) =
  changeCursorType(status.settings.insertModeCursor)
  var bufferChanged = false

  while status.bufStatus[status.currentBuffer].mode == Mode.insert:
    if bufferChanged:
      status.updateHighlight
      bufferChanged = false

    status.update

    let key = getKey(status.mainWindow[status.currentMainWindow])

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      if status.bufStatus[status.currentBuffer].currentColumn > 0: dec(status.bufStatus[status.currentBuffer].currentColumn)
      status.bufStatus[status.currentBuffer].expandedColumn = status.bufStatus[status.currentBuffer].currentColumn
      status.changeMode(Mode.normal)
    elif isLeftKey(key):
      keyLeft(status)
    elif isRightkey(key):
      keyRight(status)
    elif isUpKey(key):
      keyUp(status)
    elif isDownKey(key):
      keyDown(status)
    elif isPageUpKey(key):
      pageUp(status)
    elif isPageDownKey(key):
      pageDown(status)
    elif isHomeKey(key):
      moveToFirstOfLine(status)
    elif isEndKey(key):
      moveToLastOfLine(status)
    elif isDcKey(key):
      deleteCurrentCharacter(status)
      bufferChanged = true
    elif isBackspaceKey(key):
      keyBackspace(status)
      bufferChanged = true
    elif isEnterKey(key):
      keyEnter(status)
      bufferChanged = true
    elif key == ord('\t'):
      insertTab(status)
      bufferChanged = true
    else:
      insertCharacter(status, key)
      bufferChanged = true

  discard execShellCmd("printf '\\033[2 q'")
