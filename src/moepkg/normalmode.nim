import strutils, strformat, terminal
import ncurses
import editorstatus, statusbar, editorview, cursor, ui, gapbuffer

const
  escKey = 27
  resizeKey = 410

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

proc normalCommand(status: var EditorStatus, key: int) =
  if status.cmdLoop == 0: status.cmdLoop = 1
  
  case key:
  of ord('h'):
    for i in 0..status.cmdLoop-1: keyLeft(status)
  of ord('l'):
    for i in 0..status.cmdLoop-1: keyRight(status)
  of ord('k'):
    for i in 0..status.cmdLoop-1: keyUp(status)
  of ord('j'):
    for i in 0..status.cmdLoop-1: keyDown(status)
  else:
    discard

proc normalMode*(status: var EditorStatus) =
  status.cmdLoop = 0
  status.mode = Mode.normal
  
  noecho()

  while true:
    writeStatusBar(status)

    status.view.updated = true
    status.view.update(status.mainWindow, status.buffer, status.currentLine)
    status.cursor.update(status.view, status.currentLine, status.currentColumn)

    status.mainWindow.write(status.cursor.y, status.view.widthOfLineNum+status.cursor.x, "")
    status.mainWindow.refresh

    let key = getKey(status.mainWindow)

    if key == escKey:
      break
    elif key == resizeKey:
      resizeEditor(status)
    elif key == ord(':'):
      # exMode()
      discard
    elif isDigit(char(key)):
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
