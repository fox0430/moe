import deques
import editorstatus, ui, editorview, gapbuffer, unicodeext, window

proc keyLeft*(bufStatus: var BufferStatus) =
  if bufStatus.currentColumn == 0: return

  dec(bufStatus.currentColumn)
  bufStatus.expandedColumn = bufStatus.currentColumn

proc keyRight*(bufStatus: var BufferStatus) =
  if bufStatus.currentColumn + 1 >= bufStatus.buffer[bufStatus.currentLine].len + (if bufStatus.mode == Mode.insert: 1 else: 0): return
  inc(bufStatus.currentColumn)
  bufStatus.expandedColumn = bufStatus.currentColumn

proc keyUp*(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == 0: return

  dec(bufStatus.currentLine)
  let maxColumn = bufStatus.buffer[bufStatus.currentLine].len - 1 + (if bufStatus.mode == Mode.insert: 1 else: 0)
  bufStatus.currentColumn = min(bufStatus.expandedColumn, maxColumn)

  if bufStatus.currentColumn < 0: bufStatus.currentColumn = 0

proc keyDown*(bufStatus: var BufferStatus) =
  if bufStatus.currentLine + 1 == bufStatus.buffer.len: return

  inc(bufStatus.currentLine)
  let maxColumn = bufStatus.buffer[bufStatus.currentLine].len - 1 + (if bufStatus.mode == Mode.insert: 1 else: 0)

  bufStatus.currentColumn = min(bufStatus.expandedColumn, maxColumn)
  if bufStatus.currentColumn < 0: bufStatus.currentColumn = 0

proc moveToFirstNonBlankOfLine*(bufStatus: var BufferStatus) =
  bufStatus.currentColumn = 0
  while bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn] == ru' ':
    inc(bufStatus.currentColumn)
  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToFirstOfLine*(bufStatus: var BufferStatus) =
  bufStatus.currentColumn = 0
  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToLastOfLine*(bufStatus: var BufferStatus) =
  bufStatus.currentColumn = max(bufStatus.buffer[bufStatus.currentLine].len - 1, 0)
  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToFirstOfPreviousLine*(bufStatus: var BufferStatus) =
  if bufStatus.currentLine == 0: return
  keyUp(bufStatus)
  moveToFirstOfLine(bufStatus)

proc moveToFirstOfNextLine*(bufStatus: var BufferStatus) =
  if bufStatus.currentLine + 1 == bufStatus.buffer.len: return
  keyDown(bufStatus)
  moveToFirstOfLine(bufStatus)

proc jumpLine*(status: var EditorStatus, destination: int) =
  let
    currentLine = status.bufStatus[status.currentBuffer].currentLine
    view = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view
  status.bufStatus[status.currentBuffer].currentLine = destination
  status.bufStatus[status.currentBuffer].currentColumn = 0
  status.bufStatus[status.currentBuffer].expandedColumn = 0

  if not (view.originalLine[0] <= destination and (view.originalLine[view.height - 1] == -1 or destination <= view.originalLine[view.height - 1])):
    var startOfPrintedLines = 0
    if destination > status.bufStatus[status.currentBuffer].buffer.len - 1 - status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.height - 1:
      startOfPrintedLines = status.bufStatus[status.currentBuffer].buffer.len - 1 - status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.height - 1
    else:
      startOfPrintedLines = max(destination - (currentLine - status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.originalLine[0]), 0)
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.reload(status.bufStatus[status.currentBuffer].buffer, startOfPrintedLines)

proc moveToFirstLine*(status: var EditorStatus) = jumpLine(status, 0)

proc moveToLastLine*(status: var EditorStatus) =
  if status.bufStatus[status.currentBuffer].cmdLoop > 1: jumpLine(status, status.bufStatus[status.currentBuffer].cmdLoop - 1)
  else: jumpLine(status, status.bufStatus[status.currentBuffer].buffer.len - 1)

proc pageUp*(status: var EditorStatus) =
  let destination = max(status.bufStatus[status.currentBuffer].currentLine - status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.height, 0)

  if status.settings.smoothScroll:
    let  currentLine = status.bufStatus[status.currentBuffer].currentLine
    for i in countdown(currentLine, destination):
      if i == 0: break

      status.bufStatus[status.currentBuffer].keyUp
      status.update
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.setTimeout(status.settings.smoothScrollSpeed)
      var key: Rune = ru'\0'
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
      if key != ru'\0': break

    ## Set default time out setting
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.setTimeout

  else:
    jumpLine(status, destination)

proc pageDown*(status: var EditorStatus) =
  let
    destination = min(status.bufStatus[status.currentBuffer].currentLine + status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.height, status.bufStatus[status.currentBuffer].buffer.len - 1)
    currentLine = status.bufStatus[status.currentBuffer].currentLine

  if status.settings.smoothScroll:
    for i in currentLine ..< destination:
      if i == status.bufStatus[status.currentBuffer].buffer.high: break

      status.bufStatus[status.currentBuffer].keyDown
      status.update
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.setTimeout(status.settings.smoothScrollSpeed)
      var key: Rune = ru'\0'
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
      if key != ru'\0': break

    ## Set default time out setting
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.setTimeout

  else:
    let  view = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view
    status.bufStatus[status.currentBuffer].currentLine = destination
    status.bufStatus[status.currentBuffer].currentColumn = 0
    status.bufStatus[status.currentBuffer].expandedColumn = 0

    if not (view.originalLine[0] <= destination and (view.originalLine[view.height - 1] == -1 or destination <= view.originalLine[view.height - 1])):
      let startOfPrintedLines = max(destination - (currentLine - status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.originalLine[0]), 0)
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.reload(status.bufStatus[status.currentBuffer].buffer, startOfPrintedLines)
  
proc moveToForwardWord*(bufStatus: var BufferStatus) =
  let
    currentLine = bufStatus.currentLine
    currentColumn = bufStatus.currentColumn
    startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n' else: bufStatus.buffer[currentLine][currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.next(currentLine, currentColumn)
  else:
    while true:
      inc(bufStatus.currentColumn)
      if bufStatus.currentColumn >= bufStatus.buffer[bufStatus.currentLine].len:
        inc(bufStatus.currentLine)
        bufStatus.currentColumn = 0
        break
      if not isSkipped(bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn]): break

  while true:
    if bufStatus.currentLine >= bufStatus.buffer.len:
      bufStatus.currentLine = bufStatus.buffer.len-1
      bufStatus.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
      if bufStatus.currentColumn == -1: bufStatus.currentColumn = 0
      break

    if bufStatus.buffer[bufStatus.currentLine].len == 0: break
    if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len:
      inc(bufStatus.currentLine)
      bufStatus.currentColumn = 0
      continue

    let curr = bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(bufStatus.currentColumn)

  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToBackwardWord*(bufStatus: var BufferStatus) =
  if bufStatus.buffer.isFirst(bufStatus.currentLine, bufStatus.currentColumn): return

  while true:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.prev(bufStatus.currentLine, bufStatus.currentColumn)
    let
      currentLine = bufStatus.currentLine
      currentColumn = bufStatus.currentColumn
      
    if bufStatus.buffer[bufStatus.currentLine].len == 0 or bufStatus.buffer.isFirst(currentLine, currentColumn): break

    let curr = bufStatus.buffer[currentLine][currentColumn]
    if unicodeext.isSpace(curr): continue

    if bufStatus.currentColumn == 0: break

    let
      (backLine, backColumn) = bufStatus.buffer.prev(currentLine, currentColumn)
      back = bufStatus.buffer[backLine][backColumn]

    let
      currType = if isAlpha(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 3 else: 0
      backType = if isAlpha(back): 1 elif isDigit(back): 2 elif isPunct(back): 3 else: 0
    if currType != backType: break

  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveToForwardEndOfWord*(bufStatus: var BufferStatus) =
  let
    currentLine = bufStatus.currentLine
    currentColumn = bufStatus.currentColumn
    startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n' else: bufStatus.buffer[currentLine][currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (bufStatus.currentLine, bufStatus.currentColumn) = bufStatus.buffer.next(currentLine, currentColumn)
  else:
    while true:
      inc(bufStatus.currentColumn)
      if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len - 1: break
      if bufStatus.currentColumn >= bufStatus.buffer[bufStatus.currentLine].len:
        inc(bufStatus.currentLine)
        bufStatus.currentColumn = 0
        break
      if not isSkipped(bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn + 1]): break

  while true:
    if bufStatus.currentLine >= bufStatus.buffer.len:
      bufStatus.currentLine = bufStatus.buffer.len - 1
      bufStatus.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
      if bufStatus.currentColumn == -1: bufStatus.currentColumn = 0
      break

    if bufStatus.buffer[bufStatus.currentLine].len == 0: break
    if bufStatus.currentColumn == bufStatus.buffer[bufStatus.currentLine].len:
      inc(bufStatus.currentLine)
      bufStatus.currentColumn = 0
      continue

    let curr = bufStatus.buffer[bufStatus.currentLine][bufStatus.currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(bufStatus.currentColumn)

  bufStatus.expandedColumn = bufStatus.currentColumn

proc moveCenterScreen*(bufStatus: var BufferStatus, currentWin: WindowNode) =
  if bufStatus.currentLine > int(currentWin.view.height / 2):
    if bufStatus.cursor.y > int(currentWin.view.height / 2):
      let startOfPrintedLines = bufStatus.cursor.y - int(currentWin.view.height / 2)
      currentWin.view.reload(bufStatus.buffer, currentWin.view.originalLine[startOfPrintedLines])
    else:
      let numOfTime = int(currentWin.view.height / 2) - bufStatus.cursor.y
      for i in 0 ..< numOfTime: scrollUp(currentWin.view, bufStatus.buffer)

proc scrollScreenTop*(bufStatus: var BufferStatus, currentWin: WindowNode) = currentWin.view.reload(bufStatus.buffer, currentWin.view.originalLine[bufStatus.cursor.y])

proc scrollScreenBottom*(bufStatus: var BufferStatus, currentWin: WindowNode) =
  if bufStatus.currentLine > currentWin.view.height:
    let numOfTime = currentWin.view.height - bufStatus.cursor.y - 2
    for i in 0 ..< numOfTime: scrollUp(currentWin.view, bufStatus.buffer)
