import deques, strutils, strformat, sequtils, terminal
from os import execShellCmd
import ui, editorstatus, editorview, cursor, gapbuffer, editorview, normalmode, unicodeext, highlight

proc insertCloseParen(status: var EditorStatus, c: char) =
  case c
  of '(':
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(ru')', status.bufStatus[status.currentBuffer].currentColumn)
  of '{':
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(ru'}', status.bufStatus[status.currentBuffer].currentColumn)
  of '[':
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(ru']', status.bufStatus[status.currentBuffer].currentColumn)
  of '"':
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(ru('\"'), status.bufStatus[status.currentBuffer].currentColumn)
  of '\'':
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(ru'\'', status.bufStatus[status.currentBuffer].currentColumn)
  else:
    doAssert(false, fmt"Invalid parentheses: {c}")

proc isOpenParen(ch: char): bool = ch in ['(', '{', '[', '\"', '\'']

proc insertCharacter(status: var EditorStatus, c: Rune) =
  status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].insert(c, status.bufStatus[status.currentBuffer].currentColumn)
  inc(status.bufStatus[status.currentBuffer].currentColumn)

  if status.settings.autoCloseParen and canConvertToChar(c):
    let ch = c.toChar
    if isOpenParen(ch): insertCloseParen(status, ch)

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].view.originalLine[0])
  inc(status.bufStatus[status.currentBuffer].countChange)

proc keyBackspace(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].currentLine == 0 and status.bufStatus[status.currentBuffer].currentColumn == 0: return

  if status.bufStatus[status.currentBuffer].currentColumn == 0:
    status.bufStatus[status.currentBuffer].currentColumn = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine-1].len
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine-1] &= status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine]
    status.bufStatus[status.currentBuffer].buffer.delete(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentLine+1)
    dec(status.bufStatus[status.currentBuffer].currentLine)
  else:
    dec(status.bufStatus[status.currentBuffer].currentColumn)
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].delete(status.bufStatus[status.currentBuffer].currentColumn)

  status.bufStatus[status.currentBuffer].view.reload(status.bufStatus[status.currentBuffer].buffer, min(status.bufStatus[status.currentBuffer].view.originalLine[0], status.bufStatus[status.currentBuffer].buffer.high))
  inc(status.bufStatus[status.currentBuffer].countChange)

proc insertIndent(status: var EditorStatus) =
  let indent = min(countRepeat(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine], Whitespace, 0), status.bufStatus[status.currentBuffer].currentColumn)
  status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine+1] &= repeat(' ', indent).toRunes

proc keyEnter*(status: var EditorStatus) =
  status.bufStatus[status.currentBuffer].buffer.insert(ru"", status.bufStatus[status.currentBuffer].currentLine+1)
  if status.settings.autoIndent:
    insertIndent(status)

    var startOfCopy = max(countRepeat(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine], Whitespace, 0), status.bufStatus[status.currentBuffer].currentColumn)
    startOfCopy += countRepeat(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine], Whitespace, startOfCopy)

    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine + 1] &= status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][startOfCopy ..< status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len]
    let
      first = status.bufStatus[status.currentBuffer].currentColumn
      last = status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].high
    if first <= last: status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].delete(first, last)

    inc(status.bufStatus[status.currentBuffer].currentLine)
    status.bufStatus[status.currentBuffer].currentColumn = countRepeat(status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine], Whitespace, 0)
  else:
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine + 1] &= status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine][status.bufStatus[status.currentBuffer].currentColumn ..< status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len]
    status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].delete(status.bufStatus[status.currentBuffer].currentColumn, status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].high)

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
