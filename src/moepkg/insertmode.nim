import deques, strutils
import ui, editorstatus, editorview, cursor, gapbuffer, editorview, normalmode

proc insertCloseParen(status: var EditorStatus, ch: int) =
  case ch
  of ord('('):
    status.buffer[status.currentLine].insert(")", status.currentColumn)
  of ord('{'):
    status.buffer[status.currentLine].insert("}", status.currentColumn)
  of ord('"'):
    status.buffer[status.currentLine].insert("\"", status.currentColumn)
  of ord('\''):
    status.buffer[status.currentLine].insert("'", status.currentColumn)
  else:
    doAssert(false, "Invalid parentheses")

proc isOpenParen(ch: int): bool = ch == ord('(') or ch == ord('{') or ch == ord('"') or ch == ord('\'')

proc insertCharacter(status: var EditorStatus, ch: int) =
  status.buffer[status.currentLine].insert($char(ch), status.currentColumn)
  inc(status.currentColumn)

  if status.settings.autoCloseParen and isOpenParen(ch): insertCloseParen(status, ch)

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
    status.buffer[status.currentLine].delete(status.currentColumn, status.currentColumn)

  status.view.reload(status.buffer, min(status.view.originalLine[0], status.buffer.high))
  inc(status.countChange)

proc insertIndent(status: var EditorStatus) =
  let indent = min(countRepeat(status.buffer[status.currentLine], Whitespace, 0), status.currentColumn)
  status.buffer[status.currentLine+1] &= repeat(' ', indent)

proc keyEnter(status: var EditorStatus) =
  status.buffer.insert("", status.currentLine+1)
  if status.settings.autoIndent:
    insertIndent(status)

    var startOfCopy = max(countRepeat(status.buffer[status.currentLine], Whitespace, 0), status.currentColumn)
    startOfCopy += countRepeat(status.buffer[status.currentLine], Whitespace, startOfCopy)

    status.buffer[status.currentLine+1] &= status.buffer[status.currentLine][startOfCopy ..< status.buffer[status.currentLine].len]
    status.buffer[status.currentLine].delete(status.buffer[status.currentLine].len-(status.buffer[status.currentLine].len-status.currentColumn), status.buffer[status.currentLine].high)

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
  for i in 0 ..< status.settings.tabStop: insertCharacter(status, int(' '))

proc insertMode*(status: var EditorStatus) =
  while status.mode == Mode.insert:
    writeStatusBar(status)
    
    status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)
    status.view.update(status.mainWindow, status.buffer, status.currentLine)
    status.cursor.update(status.view, status.currentLine, status.currentColumn)

    status.mainWindow.write(status.cursor.y, status.view.widthOfLineNum+status.cursor.x, "")
    status.mainWindow.refresh

    let key = getKey(status.mainWindow)

    if isResizekey(key):
      status.resize
    elif isEscKey(key):
      if status.currentColumn > 0: dec(status.currentColumn)
      status.expandedColumn = status.currentColumn
      status.mode = Mode.normal
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
