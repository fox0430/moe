import strutils, strformat, terminal, deques
import ncurses
import editorstatus, statusbar, editorview, cursor, ui, gapbuffer

proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  status.commandWindow.erase

  status.commandWindow.write(0, 0, "debuf info: ")
  status.commandWindow.append(fmt"currentLine: {status.currentLine}, currentColumn: {status.currentColumn}")
  status.commandWindow.append(fmt", cursor.y: {status.cursor.y}, cursor.x: {status.cursor.x}")
  status.commandWindow.append(fmt", {str}")

  status.commandWindow.refresh

proc resizeWindow(win: Window, height, width, y, x: int) =
  win.resize(height, width)
  win.move(y, x)


proc resizeEditor(status: var EditorStatus) =
  endwin()
  initscr()
  resizeWindow(status.mainWindow, terminalHeight()-2, terminalWidth(), 0, 0)
  resizeWindow(status.statusWindow, 1, terminalWidth(), terminalHeight()-2, 0)
  resizeWindow(status.commandWindow, 1, terminalWidth(), terminalHeight()-1, 0)
  
  if status.mode != Mode.filer:
    status.view.resize(status.buffer, terminalHeight()-2, terminalWidth()-status.view.widthOfLineNum-1, status.view.widthOfLineNum)
    status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

  writeStatusBar(status)

proc keyLeft(status: var EditorStatus) = 
  if status.currentColumn == 0: return

  dec(status.currentColumn)
  status.expandedColumn = status.currentColumn
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

proc keyRight(status: var EditorStatus) =
  if status.currentColumn+1 >= status.buffer[status.currentLine].len + (if status.mode == Mode.insert: 1 else: 0): return

  inc(status.currentColumn)
  status.expandedColumn = status.currentColumn
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

proc keyUp(status: var EditorStatus) =
  if status.currentLine == 0: return

  dec(status.currentLine)
  let maxColumn = status.buffer[status.currentLine].len-1+(if status.mode == Mode.insert: 1 else: 0)
  status.currentColumn = min(status.expandedColumn, maxColumn)
  if status.currentColumn < 0: status.currentColumn = 0
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

proc keyDown(status: var EditorStatus) =
  if status.currentLine+1 == status.buffer.len: return

  inc(status.currentLine)
  let maxColumn = status.buffer[status.currentLine].len-1+(if status.mode == Mode.insert: 1 else: 0)
  status.currentColumn = min(status.expandedColumn, maxColumn)
  if status.currentColumn < 0: status.currentColumn = 0
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

proc moveToFirstOfLine(status: var EditorStatus) =
  status.currentColumn = 0
  status.expandedColumn = status.currentColumn
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

proc moveToLastOfLine(status: var EditorStatus) =
  status.currentColumn = max(status.buffer[status.currentLine].len-1, 0)
  status.expandedColumn = status.currentColumn
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

proc deleteCurrentCharacter(status: var EditorStatus) =
  status.buffer[status.currentLine].delete(status.currentColumn, status.currentColumn)
  if status.buffer[status.currentLine].len > 0 and status.currentColumn == status.buffer[status.currentLine].len:
    status.currentColumn = status.buffer[status.currentLine].len-1
    status.expandedColumn = status.buffer[status.currentLine].len-1

  status.view.reload(status.buffer, status.view.originalLine[0])
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)
  inc(status.countChange)

proc jumpLine(status: var EditorStatus, destination: int) =
  let currentLine = status.currentLine
  status.currentLine = destination
  status.currentColumn = 0
  status.expandedColumn = 0
  if not (status.view.originalLine[0] <= destination and (status.view.originalLine[status.view.height - 1] == -1 or destination <= status.view.originalLine[status.view.height - 1])):
    let startOfPrintedLines = max(destination - (currentLine - status.view.originalLine[0]), 0)
    status.view.reload(status.buffer, startOfPrintedLines)
  status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)

proc moveToFirstLine(status: var EditorStatus) =
  jumpLine(status, 0)

proc moveToLastLine(status: var EditorStatus) =
  jumpLine(status, status.buffer.len-1)

proc pageUp(status: var EditorStatus) =
  let destination = max(status.currentLine - status.view.height, 0)
  jumpLine(status, destination)

proc pageDown(status: var EditorStatus) =
  let destination = min(status.currentLine + status.view.height, status.buffer.len - 1)
  jumpLine(status, destination)

proc normalCommand(status: var EditorStatus, key: int) =
  if status.cmdLoop == 0: status.cmdLoop = 1
  
  if key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0..status.cmdLoop-1: keyLeft(status)
  elif key == ord('l') or isRightKey(key):
    for i in 0..status.cmdLoop-1: keyRight(status)
  elif key == ord('k') or isUpKey(key):
    for i in 0..status.cmdLoop-1: keyUp(status)
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0..status.cmdLoop-1: keyDown(status)
  elif key == ord('x') or isDcKey(key):
    for i in 0..status.cmdLoop-1: deleteCurrentCharacter(status)
  elif key == ord('0') or isHomeKey(key):
    moveToFirstOfLine(status)
  elif key == ord('$') or isEndKey(key):
    moveToLastOfLine(status)
  elif key == ord('g'):
    if getKey(status.mainWindow) == ord('g'): moveToFirstLine(status)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isPageUpkey(key):
    for i in 0..status.cmdLoop-1: pageUp(status)
  elif isPageDownKey(key):
    for i in 0..status.cmdLoop-1: pageDown(status)
  else:
    discard

proc normalMode*(status: var EditorStatus) =
  status.cmdLoop = 0
  status.mode = Mode.normal
  
  while true:
    writeStatusBar(status)

    status.view.updated = true
    status.view.update(status.mainWindow, status.buffer, status.currentLine)
    status.cursor.update(status.view, status.currentLine, status.currentColumn)

    status.mainWindow.write(status.cursor.y, status.view.widthOfLineNum+status.cursor.x, "")
    status.mainWindow.refresh

    let key = getKey(status.mainWindow)

    if isResizekey(key):
      resizeEditor(status)
    elif key == ord(':'):
      status.mode = Mode.ex
      return
    elif key in 0..255 and isDigit(chr(key)):
      if status.cmdLoop == 0 and key == ord('0'):
        normalCommand(status, key)
        discard
        continue

      status.cmdLoop *= 10
      status.cmdLoop += key-ord('0')
      status.cmdLoop = min(100000, status.cmdLoop)
      continue
    else:
      normalCommand(status, key)
      status.cmdLoop = 0
