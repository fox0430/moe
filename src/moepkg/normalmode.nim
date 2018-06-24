import strutils, strformat, terminal, deques
import editorstatus, editorview, cursor, ui, gapbuffer

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

proc keyRight(status: var EditorStatus) =
  if status.currentColumn+1 >= status.buffer[status.currentLine].len + (if status.mode == Mode.insert: 1 else: 0): return

  inc(status.currentColumn)
  status.expandedColumn = status.currentColumn

proc keyUp(status: var EditorStatus) =
  if status.currentLine == 0: return

  dec(status.currentLine)
  let maxColumn = status.buffer[status.currentLine].len-1+(if status.mode == Mode.insert: 1 else: 0)
  status.currentColumn = min(status.expandedColumn, maxColumn)
  if status.currentColumn < 0: status.currentColumn = 0

proc keyDown(status: var EditorStatus) =
  if status.currentLine+1 == status.buffer.len: return

  inc(status.currentLine)
  let maxColumn = status.buffer[status.currentLine].len-1+(if status.mode == Mode.insert: 1 else: 0)
  status.currentColumn = min(status.expandedColumn, maxColumn)
  if status.currentColumn < 0: status.currentColumn = 0

proc moveToFirstOfLine(status: var EditorStatus) =
  status.currentColumn = 0
  status.expandedColumn = status.currentColumn

proc moveToLastOfLine(status: var EditorStatus) =
  status.currentColumn = max(status.buffer[status.currentLine].len-1, 0)
  status.expandedColumn = status.currentColumn

proc deleteCurrentCharacter(status: var EditorStatus) =
  status.buffer[status.currentLine].delete(status.currentColumn, status.currentColumn)
  if status.buffer[status.currentLine].len > 0 and status.currentColumn == status.buffer[status.currentLine].len:
    status.currentColumn = status.buffer[status.currentLine].len-1
    status.expandedColumn = status.buffer[status.currentLine].len-1

  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc jumpLine*(status: var EditorStatus, destination: int) =
  let currentLine = status.currentLine
  status.currentLine = destination
  status.currentColumn = 0
  status.expandedColumn = 0
  if not (status.view.originalLine[0] <= destination and (status.view.originalLine[status.view.height - 1] == -1 or destination <= status.view.originalLine[status.view.height - 1])):
    let startOfPrintedLines = max(destination - (currentLine - status.view.originalLine[0]), 0)
    status.view.reload(status.buffer, startOfPrintedLines)

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

proc isPunct(c: char): bool = return c in {'!', '"', '#', '$', '%', '$', '\'', '(', ')', '*', '+', ',', '-', '.', '/', ':', ';', '<', '=', '>', '?', '@', '[', '\\', ']', '^', '_', '`', '{', '=', '}'}

proc moveToForwardWord(status: var EditorStatus) =
  let
    startWith = if status.buffer[status.currentLine].len == 0: '\n' else: status.buffer[status.currentLine][status.currentColumn]
    isSkipped = if isPunct(startWith): isPunct elif isAlphaAscii(startWith): isAlphaAscii elif isDigit(startWith): isDigit else: nil

  if isSkipped == nil:
    (status.currentLine, status.currentColumn) = status.buffer.next(status.currentLine, status.currentColumn)
  else:
    while true:
      inc(status.currentColumn)
      if status.currentColumn >= status.buffer[status.currentLine].len:
        inc(status.currentLine)
        status.currentColumn = 0
        break
      if not isSkipped(status.buffer[status.currentLine][status.currentColumn]): break

  while true:
    if status.currentLine >= status.buffer.len:
      status.currentLine = status.buffer.len-1
      status.currentColumn = status.buffer[status.buffer.high].high
      if status.currentColumn == -1: status.currentColumn = 0
      break

    if status.buffer[status.currentLine].len == 0: break
    if status.currentColumn == status.buffer[status.currentLine].len:
      inc(status.currentLine)
      status.currentColumn = 0
      continue

    let curr = status.buffer[status.currentLine][status.currentColumn]
    if isPunct(curr) or isAlphaAscii(curr) or isDigit(curr): break
    inc(status.currentColumn)

  status.expandedColumn = status.currentColumn

proc moveToBackwardWord(status: var EditorStatus) =
  if status.buffer.isFirst(status.currentLine, status.currentColumn): return

  while true:
    (status.currentLine, status.currentColumn) = status.buffer.prev(status.currentLine, status.currentColumn)
    if status.buffer[status.currentLine].len == 0 or status.buffer.isFirst(status.currentLine, status.currentColumn): break

    let curr = status.buffer[status.currentLine][status.currentColumn]
    if isSpaceAscii(curr): continue

    if status.currentColumn == 0: break

    let
      (backLine, backColumn) = status.buffer.prev(status.currentLine, status.currentColumn)
      back = status.buffer[backLine][backColumn]

    let
      currType = if isAlphaAscii(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 4 else: 0
      backType = if isAlphaAscii(back): 1 elif isDigit(back): 2 elif isPunct(back): 4 else: 0
    if currType != backType: break

  status.expandedColumn = status.currentColumn

proc countRepeat(s: string, charSet: set[char], start: int): int =
  for i in start .. s.high:
    if not (s[i] in charSet): break
    inc(result)

proc openBlankLineBelow(status: var EditorStatus) =
  let indent = repeat(' ', countRepeat(status.buffer[status.currentLine], Whitespace, 0))

  status.buffer.insert(indent, status.currentLine+1)
  inc(status.currentLine)
  status.currentColumn = indent.len

  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc openBlankLineAbove(status: var EditorStatus) =
  let indent = repeat(' ', countRepeat(status.buffer[status.currentLine], Whitespace, 0))

  status.buffer.insert(indent, status.currentLine)
  status.currentColumn = indent.len

  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc deleteLine(status: var EditorStatus, line: int) =
  status.buffer.delete(line, line+1)

  if status.buffer.len == 0: status.buffer.insert("", 0)

  if line < status.currentLine: dec(status.currentLine)
  if status.currentLine >= status.buffer.len: status.currentLine = status.buffer.high
  
  status.currentColumn = 0
  status.expandedColumn = 0

  status.view.reload(status.buffer, min(status.view.originalLine[0], status.buffer.high))
  inc(status.countChange)

proc yankLines(status: var EditorStatus, first, last: int) =
  status.registers.yankedLines = @[]
  for i in first .. last: status.registers.yankedLines.add(status.buffer[i])

  status.commandWindow.erase
  status.commandwindow.write(0, 0, fmt"{status.registers.yankedLines.len} line yanked")
  status.commandWindow.refresh

proc pasterLines(status: var EditorStatus) =
  for line in status.registers.yankedLines:
    inc(status.currentLine)
    status.buffer.insert(line, status.currentLine)

  status.view.reload(status.buffer, min(status.view.originalLine[0], status.buffer.high))
  inc(status.countChange)

proc replaceCurrentCharacter(status: var EditorStatus, character: int) =
  status.buffer[status.currentLine][status.currentColumn] = char(character)
  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc normalCommand(status: var EditorStatus, key: int) =
  if status.cmdLoop == 0: status.cmdLoop = 1
  
  if key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
    for i in 0 ..< status.cmdLoop: keyLeft(status)
  elif key == ord('l') or isRightKey(key):
    for i in 0 ..< status.cmdLoop: keyRight(status)
  elif key == ord('k') or isUpKey(key):
    for i in 0 ..< status.cmdLoop: keyUp(status)
  elif key == ord('j') or isDownKey(key) or isEnterKey(key):
    for i in 0 ..< status.cmdLoop: keyDown(status)
  elif key == ord('x') or isDcKey(key):
    for i in 0 ..< min(status.cmdLoop, status.buffer[status.currentLine].len - status.currentColumn): deleteCurrentCharacter(status)
  elif key == ord('0') or isHomeKey(key):
    moveToFirstOfLine(status)
  elif key == ord('$') or isEndKey(key):
    moveToLastOfLine(status)
  elif key == ord('g'):
    if getKey(status.mainWindow) == ord('g'): moveToFirstLine(status)
  elif key == ord('G'):
    moveToLastLine(status)
  elif isPageUpkey(key):
    for i in 0 ..< status.cmdLoop: pageUp(status)
  elif isPageDownKey(key):
    for i in 0 ..< status.cmdLoop: pageDown(status)
  elif key == ord('w'):
    for i in 0 ..< status.cmdLoop: moveToForwardWord(status)
  elif key == ord('b'):
    for i in 0 ..< status.cmdLoop: moveToBackwardWord(status)
  elif key == ord('o'):
    for i in 0 ..< status.cmdLoop: openBlankLineBelow(status)
    status.mode = Mode.insert
  elif key == ord('O'):
    for i in 0 ..< status.cmdLoop: openBlankLineAbove(status)
    status.mode = Mode.insert
  elif key == ord('d'):
    if getKey(status.mainWindow) == ord('d'):
      for i in 0 ..< min(status.cmdLoop, status.buffer.len-status.currentLine): deleteLine(status, status.currentLine)
  elif key == ord('y'):
    if getkey(status.mainWindow) == ord('y'): yankLines(status, status.currentLine, min(status.currentLine+status.cmdLoop-1, status.buffer.high))
  elif key == ord('p'):
    pasterLines(status)
  elif key == ord('r'):
    if status.cmdLoop > status.buffer[status.currentLine].len - status.currentColumn: return

    let ch = getKey(status.mainWindow)
    for i in 0 ..< status.cmdLoop:
      if i > 0:
        inc(status.currentColumn)
        status.expandedColumn = status.currentColumn
      replaceCurrentCharacter(status, ch)
  elif key == ord('i'):
    status.mode = Mode.insert
  elif key == ord('I'):
    status.currentColumn = 0
    status.mode = Mode.insert
  elif key == ord('a'):
    inc(status.currentColumn)
    status.mode = Mode.insert
  elif key == ord('A'):
    status.currentColumn = status.buffer[status.currentLine].len
    status.mode = Mode.insert
  else:
    discard

proc normalMode*(status: var EditorStatus) =
  status.cmdLoop = 0
  status.resize
  
  while status.mode == Mode.normal:
    writeStatusBar(status)

    status.view.seekCursor(status.buffer, status.currentLine, status.currentColumn)
    status.view.update(status.mainWindow, status.buffer, status.currentLine)
    status.cursor.update(status.view, status.currentLine, status.currentColumn)

    status.mainWindow.write(status.cursor.y, status.view.widthOfLineNum+status.cursor.x, "")
    status.mainWindow.refresh

    let key = getKey(status.mainWindow)

    if isResizekey(key):
      status.resize
    elif key == ord(':'):
      status.mode = Mode.ex
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
