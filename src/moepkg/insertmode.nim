import deques, strutils, strformat, sequtils, terminal
from os import execShellCmd
import ui, editorstatus, editorview, cursor, gapbuffer, editorview, normalmode, unicodeext

proc insertCloseParen(status: var EditorStatus, c: char) =
  case c
  of '(':
    status.buffer[status.currentLine].insert(ru')', status.currentColumn)
  of '{':
    status.buffer[status.currentLine].insert(ru'}', status.currentColumn)
  of '[':
    status.buffer[status.currentLine].insert(ru']', status.currentColumn)
  of '"':
    status.buffer[status.currentLine].insert(ru('\"'), status.currentColumn)
  of '\'':
    status.buffer[status.currentLine].insert(ru'\'', status.currentColumn)
  else:
    doAssert(false, fmt"Invalid parentheses: {c}")

proc isOpenParen(ch: char): bool = ch in ['(', '{', '[', '\"', '\'']

proc insertCharacter(status: var EditorStatus, c: Rune) =
  status.buffer[status.currentLine].insert(c, status.currentColumn)
  inc(status.currentColumn)

  if status.settings.autoCloseParen and canConvertToChar(c):
    let ch = c.toChar
    if isOpenParen(ch): insertCloseParen(status, ch)

  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc keyBackspace(status: var EditorStatus) =
  if status.currentLine == 0 and status.currentColumn == 0: return

  if status.currentColumn == 0:
    status.currentColumn = status.buffer[status.currentLine-1].len
    status.buffer[status.currentLine-1] &= status.buffer[status.currentLine]
    status.buffer.delete(status.currentLine, status.currentLine+1)
    dec(status.currentLine)
  else:
    dec(status.currentColumn)
    status.buffer[status.currentLine].delete(status.currentColumn)

  status.view.reload(status.buffer, min(status.view.originalLine[0], status.buffer.high))
  inc(status.countChange)

proc insertIndent(status: var EditorStatus) =
  let indent = min(countRepeat(status.buffer[status.currentLine], Whitespace, 0), status.currentColumn)
  status.buffer[status.currentLine+1] &= repeat(' ', indent).toRunes

proc keyEnter*(status: var EditorStatus) =
  status.buffer.insert(ru"", status.currentLine+1)
  if status.settings.autoIndent:
    insertIndent(status)

    var startOfCopy = max(countRepeat(status.buffer[status.currentLine], Whitespace, 0), status.currentColumn)
    startOfCopy += countRepeat(status.buffer[status.currentLine], Whitespace, startOfCopy)

    status.buffer[status.currentLine+1] &= status.buffer[status.currentLine][startOfCopy ..< status.buffer[status.currentLine].len]
    let
      first = status.currentColumn
      last = status.buffer[status.currentLine].high
    if first <= last: status.buffer[status.currentLine].delete(first, last)

    inc(status.currentLine)
    status.currentColumn = countRepeat(status.buffer[status.currentLine], Whitespace, 0)
  else:
    status.buffer[status.currentLine+1] &= status.buffer[status.currentLine][status.currentColumn ..< status.buffer[status.currentLine].len]
    status.buffer[status.currentLine].delete(status.currentColumn, status.buffer[status.currentLine].high)

    inc(status.currentLine)
    status.currentColumn = 0
    status.expandedColumn = 0

  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc insertTab(status: var EditorStatus) =
  for i in 0 ..< status.settings.tabStop: insertCharacter(status, ru' ')

proc insertMode*(status: var EditorStatus) =
  discard execShellCmd("printf '\\033[6 q'")
  while status.mode == Mode.insert:
    status.update

    let key = getKey(status.mainWindow)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      if status.currentColumn > 0: dec(status.currentColumn)
      status.expandedColumn = status.currentColumn
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
    elif isBackspaceKey(key):
      keyBackspace(status)
    elif isEnterKey(key):
      keyEnter(status)
    elif key == ord('\t'):
      insertTab(status)
    else:
      insertCharacter(status, key)
  discard execShellCmd("printf '\\033[2 q'")
