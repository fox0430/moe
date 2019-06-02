import deques, strutils, strformat, sequtils, terminal, macros
from os import execShellCmd
import ui, editorstatus, editorview, cursor, gapbuffer, editorview, normalmode, unicodeext, highlight, undoredostack

proc insertCloseParen(bufStatus: var BufferStatus, c: char) =
  case c
  of '(':
    # TODO: bufStatus.buffer[bufStatus.currentLine].insert(ru')', bufStatus.currentColumn)
    discard
  of '{':
    # TODO: bufStatus.buffer[bufStatus.currentLine].insert(ru'}', bufStatus.currentColumn)
    discard
  of '[':
    # TODO: bufStatus.buffer[bufStatus.currentLine].insert(ru']', bufStatus.currentColumn)
    discard
  of '"':
    # TODO: bufStatus.buffer[bufStatus.currentLine].insert(ru('\"'), bufStatus.currentColumn)
    discard
  of '\'':
    # TODO: bufStatus.buffer[bufStatus.currentLine].insert(ru'\'', bufStatus.currentColumn)
    discard
  else:
    doAssert(false, fmt"Invalid parentheses: {c}")

proc isOpenParen(ch: char): bool = ch in ['(', '{', '[', '\"', '\'']

proc insertCharacter(bufStatus: var BufferStatus, autoCloseParen: bool, c: Rune) =
  var oldLine, newLine: seq[Rune]
  oldLine = bufStatus.buffer[bufStatus.currentLine]
  newLine = bufStatus.buffer[bufStatus.currentLine]
  newLine.insert(c, bufStatus.currentColumn)
  if oldLine != newLine:
    bufStatus.buffer[bufStatus.currentLine] = newLine
  inc(bufStatus.currentColumn)

  if autoCloseParen and canConvertToChar(c):
    let ch = c.toChar
    if isOpenParen(ch): insertCloseParen(bufStatus, ch)

  bufStatus.view.reload(bufStatus.buffer, bufStatus.view.originalLine[0])
  inc(bufStatus.countChange)

proc keyBackspace(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == 0 and bufStatus.currentColumn == 0: return

  if bufStatus.currentColumn == 0:
    bufStatus.currentColumn = bufStatus.buffer[bufStatus.currentLine - 1].len
    # TODO: bufStatus.buffer[bufStatus.currentLine - 1] &= bufStatus.buffer[bufStatus.currentLine]
    bufStatus.buffer.delete(bufStatus.currentLine, bufStatus.currentLine)
    dec(bufStatus.currentLine)
  else:
    dec(bufStatus.currentColumn)
    # TODO: bufStatus.buffer[bufStatus.currentLine].delete(bufStatus.currentColumn)

  bufStatus.view.reload(bufStatus.buffer, min(bufStatus.view.originalLine[0], bufStatus.buffer.high))
  inc(bufStatus.countChange)

proc insertIndent(bufStatus: var BufferStatus) =
  let indent = min(countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0), bufStatus.currentColumn)
  # TODO: bufStatus.buffer[bufStatus.currentLine + 1] &= repeat(' ', indent).toRunes

proc keyEnter*(bufStatus: var BufferStatus, autoIndent: bool) =
  bufStatus.buffer.insert(ru"", bufStatus.currentLine + 1)

  if autoIndent:
    insertIndent(bufStatus)

    var startOfCopy = max(countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0), bufStatus.currentColumn)
    startOfCopy += countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, startOfCopy)

    # TODO: bufStatus.buffer[bufStatus.currentLine + 1] &= bufStatus.buffer[bufStatus.currentLine][startOfCopy ..< bufStatus.buffer[bufStatus.currentLine].len]
    let
      first = bufStatus.currentColumn
      last = bufStatus.buffer[bufStatus.currentLine].high
    # TODO: if first <= last: bufStatus.buffer[bufStatus.currentLine].delete(first, last)

    inc(bufStatus.currentLine)
    bufStatus.currentColumn = countRepeat(bufStatus.buffer[bufStatus.currentLine], Whitespace, 0)
  else:
    # TODO: bufStatus.buffer[bufStatus.currentLine + 1] &= bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn ..< bufStatus.buffer[bufStatus.currentLine].len]
    # TODO: bufStatus.buffer[bufStatus.currentLine].delete(bufStatus.currentColumn, bufStatus.buffer[bufStatus.currentLine].high)

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

    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
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

  discard execShellCmd("printf '\\033[2 q'")
