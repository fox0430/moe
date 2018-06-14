import strutils, strformat
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

proc keyUp(status: var EditorStatus) = discard
proc keyDown(status: var EditorStatus) = discard

proc normalCommand(status: var EditorStatus, key: char) =
  if status.cmdLoop == 0: status.cmdLoop = 1
  
  case key:
  of 'h':
    for i in 0..status.cmdLoop-1: keyLeft(status)
  of 'l':
    for i in 0..status.cmdLoop-1: keyRight(status)
  of 'k':
    for i in 0..status.cmdLoop-1: keyUp(status)
  of 'j':
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

    let key = char(getch())

    if ord(key) == escKey: break
    elif ord(key) == resizeKey: discard
      # winResizeEvent()
    elif key == ':': discard
      # exMode()
    elif isDigit(key):
      if status.cmdLoop == 0 and key == '0':
        normalCommand(status, key)
        discard
        continue

      status.cmdLoop *= 10
      status.cmdLoop += ord(key)-ord('0')
      status.cmdLoop = min(100000, status.cmdLoop)
      continue
    else:
      normalCommand(status, key)
      status.cmdLoop = 0
