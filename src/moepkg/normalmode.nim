import strutils, strformat, terminal, deques, sequtils
import editorstatus, editorview, cursor, ui, gapbuffer, unicodeext

proc writeDebugInfo(status: var EditorStatus, str: string = "") =
  status.commandWindow.erase

  status.commandWindow.write(0, 0, ru"debuf info: ")
  status.commandWindow.append(fmt"currentLine: {status.currentLine}, currentColumn: {status.currentColumn}")
  status.commandWindow.append(fmt", cursor.y: {status.cursor.y}, cursor.x: {status.cursor.x}")
  status.commandWindow.append(fmt", {str}")

  status.commandWindow.refresh

proc keyLeft*(status: var EditorStatus) =
  if status.currentColumn == 0: return

  dec(status.currentColumn)
  status.expandedColumn = status.currentColumn

proc keyRight*(status: var EditorStatus) =
  if status.currentColumn+1 >= status.buffer[status.currentLine].len + (if status.mode == Mode.insert: 1 else: 0): return

  inc(status.currentColumn)
  status.expandedColumn = status.currentColumn

proc keyUp*(status: var EditorStatus) =
  if status.currentLine == 0: return

  dec(status.currentLine)
  let maxColumn = status.buffer[status.currentLine].len-1+(if status.mode == Mode.insert: 1 else: 0)
  status.currentColumn = min(status.expandedColumn, maxColumn)
  if status.currentColumn < 0: status.currentColumn = 0

proc keyDown*(status: var EditorStatus) =
  if status.currentLine+1 == status.buffer.len: return

  inc(status.currentLine)
  let maxColumn = status.buffer[status.currentLine].len-1+(if status.mode == Mode.insert: 1 else: 0)
  status.currentColumn = min(status.expandedColumn, maxColumn)
  if status.currentColumn < 0: status.currentColumn = 0

proc moveToFirstNonBlankOfLine(status: var EditorStatus) =
  status.currentColumn = 0
  while status.buffer[status.currentLine][status.currentColumn] == ru' ': inc(status.currentColumn)
  status.expandedColumn = status.currentColumn

proc moveToFirstOfLine*(status: var EditorStatus) =
  status.currentColumn = 0
  status.expandedColumn = status.currentColumn

proc moveToLastOfLine*(status: var EditorStatus) =
  status.currentColumn = max(status.buffer[status.currentLine].len-1, 0)
  status.expandedColumn = status.currentColumn

proc moveToFirstOfPreviousLine(status: var EditorStatus) =
  if status.currentLine == 0: return
  keyUp(status)
  moveToFirstOfLine(status)

proc moveToFirstOfNextLine(status: var EditorStatus) =
  if status.currentLine+1 == status.buffer.len: return
  keyDown(status)
  moveToFirstOfLine(status)

proc deleteCurrentCharacter*(status: var EditorStatus) =
  status.buffer[status.currentLine].delete(status.currentColumn)
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
    var startOfPrintedLines = 0
    if destination > status.buffer.len - 1 - status.mainWindow.height - 1:
      startOfPrintedLines = status.buffer.len - 1 - status.mainWindow.height - 1
    else:
      startOfPrintedLines = max(destination - (currentLine - status.view.originalLine[0]), 0)
    status.view.reload(status.buffer, startOfPrintedLines)

proc moveToFirstLine(status: var EditorStatus) =
  jumpLine(status, 0)

proc moveToLastLine(status: var EditorStatus) =
  if status.cmdLoop > 1:
    jumpLine(status, status.cmdLoop - 1)
  else:
    jumpLine(status, status.buffer.len-1)

proc pageUp*(status: var EditorStatus) =
  let destination = max(status.currentLine - status.view.height, 0)
  jumpLine(status, destination)

proc pageDown*(status: var EditorStatus) =
  let destination = min(status.currentLine + status.view.height, status.buffer.len - 1)
  let currentLine = status.currentLine
  status.currentLine = destination
  status.currentColumn = 0
  status.expandedColumn = 0
  if not (status.view.originalLine[0] <= destination and (status.view.originalLine[status.view.height - 1] == -1 or destination <= status.view.originalLine[status.view.height - 1])):
    let startOfPrintedLines = max(destination - (currentLine - status.view.originalLine[0]), 0)
    status.view.reload(status.buffer, startOfPrintedLines)

proc moveToForwardWord(status: var EditorStatus) =
  let
    startWith = if status.buffer[status.currentLine].len == 0: ru'\n' else: status.buffer[status.currentLine][status.currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

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
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(status.currentColumn)

  status.expandedColumn = status.currentColumn

proc moveToBackwardWord(status: var EditorStatus) =
  if status.buffer.isFirst(status.currentLine, status.currentColumn): return

  while true:
    (status.currentLine, status.currentColumn) = status.buffer.prev(status.currentLine, status.currentColumn)
    if status.buffer[status.currentLine].len == 0 or status.buffer.isFirst(status.currentLine, status.currentColumn): break

    let curr = status.buffer[status.currentLine][status.currentColumn]
    if unicodeext.isSpace(curr): continue

    if status.currentColumn == 0: break

    let
      (backLine, backColumn) = status.buffer.prev(status.currentLine, status.currentColumn)
      back = status.buffer[backLine][backColumn]

    let
      currType = if isAlpha(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 3 else: 0
      backType = if isAlpha(back): 1 elif isDigit(back): 2 elif isPunct(back): 3 else: 0
    if currType != backType: break

  status.expandedColumn = status.currentColumn

proc openBlankLineBelow(status: var EditorStatus) =
  let indent = repeat(ru' ', countRepeat(status.buffer[status.currentLine], Whitespace, 0))

  status.buffer.insert(indent, status.currentLine+1)
  inc(status.currentLine)
  status.currentColumn = indent.len

  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc openBlankLineAbove(status: var EditorStatus) =
  let indent = repeat(ru' ', countRepeat(status.buffer[status.currentLine], Whitespace, 0))

  status.buffer.insert(indent, status.currentLine)
  status.currentColumn = indent.len

  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc deleteLine(status: var EditorStatus, line: int) =
  status.buffer.delete(line, line+1)

  if status.buffer.len == 0: status.buffer.insert(ru"", 0)

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

proc pasteLines(status: var EditorStatus) =
  for line in status.registers.yankedLines:
    inc(status.currentLine)
    status.buffer.insert(line, status.currentLine)

  status.view.reload(status.buffer, min(status.view.originalLine[0], status.buffer.high))
  inc(status.countChange)

proc replaceCurrentCharacter(status: var EditorStatus, character: Rune) =
  status.buffer[status.currentLine][status.currentColumn] = character
  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc addIndent(status: var EditorStatus) =
  status.buffer[status.currentLine].insert(newSeqWith(status.settings.tabStop, ru' '))

  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc deleteIndent(status: var EditorStatus) =
  if status.buffer.len == 0: return

  if status.buffer[status.currentLine][0] == ru' ':
    for i in 0 ..< status.settings.tabStop:
      if status.buffer.len == 0 or status.buffer[status.currentLine][0] != ru' ': break
      status.buffer[status.currentLine].delete(0, 0)
  status.view.reload(status.buffer, status.view.originalLine[0])
  inc(status.countChange)

proc joinLine(status: var EditorStatus) =
  if status.currentLine == status.buffer.len - 1 or status.buffer[status.currentLine + 1].len < 1:
    return

  status.buffer[status.currentLine].add(status.buffer[status.currentLine+1])
  status.buffer.delete(status.currentLine + 1, status.currentLine + 2)

  status.view.reload(status.buffer, min(status.view.originalLine[0], status.buffer.high))
  inc(status.countChange)


proc normalCommand(status: var EditorStatus, key: Rune) =
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
  elif key == ord('^'):
    moveToFirstNonBlankOfLine(status)
  elif key == ord('0') or isHomeKey(key):
    moveToFirstOfLine(status)
  elif key == ord('$') or isEndKey(key):
    moveToLastOfLine(status)
  elif key == ord('-'):
    moveToFirstOfPreviousLine(status)
  elif key == ord('+'):
    moveToFirstOfNextLine(status)
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
    status.changeMode(Mode.insert)
  elif key == ord('O'):
    for i in 0 ..< status.cmdLoop: openBlankLineAbove(status)
    status.changeMode(Mode.insert)
  elif key == ord('d'):
    if getKey(status.mainWindow) == ord('d'):
      for i in 0 ..< min(status.cmdLoop, status.buffer.len-status.currentLine): deleteLine(status, status.currentLine)
  elif key == ord('y'):
    if getkey(status.mainWindow) == ord('y'): yankLines(status, status.currentLine, min(status.currentLine+status.cmdLoop-1, status.buffer.high))
  elif key == ord('p'):
    pasteLines(status)
  elif key == ord('>'):
    for i in 0 ..< status.cmdLoop: addIndent(status)
  elif key == ord('<'):
    for i in 0 ..< status.cmdLoop: deleteIndent(status)
  elif key == ord('J'):
    joinLine(status)
  elif key == ord('r'):
    if status.cmdLoop > status.buffer[status.currentLine].len - status.currentColumn: return

    let ch = getKey(status.mainWindow)
    for i in 0 ..< status.cmdLoop:
      if i > 0:
        inc(status.currentColumn)
        status.expandedColumn = status.currentColumn
      replaceCurrentCharacter(status, ch)
  elif key == ord('i'):
    status.changeMode(Mode.insert)
  elif key == ord('I'):
    status.currentColumn = 0
    status.changeMode(Mode.insert)
  elif key == ord('a'):
    if status.buffer[status.currentLine].len > 0: inc(status.currentColumn)
    status.changeMode(Mode.insert)
  elif key == ord('A'):
    status.currentColumn = status.buffer[status.currentLine].len
    status.changeMode(Mode.insert)
  else:
    discard

proc normalMode*(status: var EditorStatus) =
  status.cmdLoop = 0
  status.resize(terminalHeight(), terminalWidth())
  
  while status.mode == Mode.normal:
    status.update

    let key = getKey(status.mainWindow)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif key == ord('/'):
      status.changeMode(Mode.search)
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif isDigit(key):
      let num = ($key)[0]
      if status.cmdLoop == 0 and num == '0':
        normalCommand(status, key)
        continue

      status.cmdLoop *= 10
      status.cmdLoop += ord(num)-ord('0')
      status.cmdLoop = min(100000, status.cmdLoop)
      continue
    else:
      normalCommand(status, key)
      status.cmdLoop = 0
