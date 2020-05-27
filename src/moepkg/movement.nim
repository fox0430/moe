import deques
import editorstatus, ui, editorview, gapbuffer, unicodeext, window, bufferstatus

proc keyLeft*(windowNode: var WindowNode) =
  if windowNode.currentColumn == 0: return

  dec(windowNode.currentColumn)
  windowNode.expandedColumn = windowNode.currentColumn

proc keyRight*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentColumn + 1 >= bufStatus.buffer[windowNode.currentLine].len + (if bufStatus.mode == Mode.insert: 1 else: 0): return
  inc(windowNode.currentColumn)
  windowNode.expandedColumn = windowNode.currentColumn

proc keyUp*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentLine == 0: return

  dec(windowNode.currentLine)
  let maxColumn = bufStatus.buffer[windowNode.currentLine].len - 1 + (if bufStatus.mode == Mode.insert: 1 else: 0)
  windowNode.currentColumn = min(windowNode.expandedColumn, maxColumn)

  if windowNode.currentColumn < 0: windowNode.currentColumn = 0

proc keyDown*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentLine + 1 == bufStatus.buffer.len: return

  inc(windowNode.currentLine)
  let maxColumn = bufStatus.buffer[windowNode.currentLine].len - 1 + (if bufStatus.mode == Mode.insert: 1 else: 0)

  windowNode.currentColumn = min(windowNode.expandedColumn, maxColumn)
  if windowNode.currentColumn < 0: windowNode.currentColumn = 0

proc getFirstNonBlankOfLine*(bufStatus: BufferStatus, windowNode: WindowNode): Natural =
  if bufStatus.buffer[windowNode.currentLine].len() == 0:
    return 0
  while bufStatus.buffer[windowNode.currentLine][result] == ru' ':
    inc(result)

proc moveToFirstNonBlankOfLine*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  windowNode.currentColumn = getFirstNonBlankOfLine(bufStatus, windowNode)
  windowNode.expandedColumn = windowNode.currentColumn

proc moveToFirstOfLine*(windowNode: var WindowNode) =
  windowNode.currentColumn = 0
  windowNode.expandedColumn = windowNode.currentColumn

proc moveToLastOfLine*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  windowNode.currentColumn = max(bufStatus.buffer[windowNode.currentLine].len - 1, 0)
  windowNode.expandedColumn = windowNode.currentColumn

proc moveToFirstOfPreviousLine*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentLine == 0: return
  bufStatus.keyUp(windowNode)
  windowNode.moveToFirstOfLine

proc moveToFirstOfNextLine*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentLine + 1 == bufStatus.buffer.len: return
  bufStatus.keyDown(windowNode)
  windowNode.moveToFirstOfLine

proc jumpLine*(status: var EditorStatus, destination: int) =
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  let
    currentBufferIndex = windowNode.bufferIndex
    currentLine = windowNode.currentLine
    view = windowNode.view

  windowNode.currentLine = destination
  windowNode.currentColumn = 0
  windowNode.expandedColumn = 0

  if not (view.originalLine[0] <= destination and (view.originalLine[view.height - 1] == -1 or destination <= view.originalLine[view.height - 1])):
    var startOfPrintedLines = 0
    if destination > status.bufStatus[currentBufferIndex].buffer.high - windowNode.window.height - 1:
      startOfPrintedLines = status.bufStatus[currentBufferIndex].buffer.high - windowNode.window.height - 1
    else:
      startOfPrintedLines = max(destination - (currentLine - windowNode.view.originalLine[0]), 0)

    windowNode.view.reload(status.bufStatus[currentBufferIndex].buffer, startOfPrintedLines)

proc moveToFirstLine*(status: var EditorStatus) = status.jumpLine(0)

proc moveToLastLine*(status: var EditorStatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  if status.bufStatus[currentBufferIndex].cmdLoop > 1: jumpLine(status, status.bufStatus[currentBufferIndex].cmdLoop - 1)
  else: status.jumpLine(status.bufStatus[currentBufferIndex].buffer.high)

proc scrollUpNumberOfLines(status: var EditorStatus, numberOfLines: Natural) =
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    destination = max(windowNode.currentLine - numberOfLines, 0)

  if status.settings.smoothScroll:
    let  currentLine = windowNode.currentLine
    for i in countdown(currentLine, destination):
      if i == 0: break

      status.bufStatus[currentBufferIndex].keyUp(windowNode)
      status.update
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.setTimeout(status.settings.smoothScrollSpeed)
      var key: Rune = ru'\0'
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
      if key != ru'\0': break

    ## Set default time out setting
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.setTimeout

  else:
    jumpLine(status, destination)

proc pageUp*(status: var EditorStatus) =
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  scrollUpNumberOfLines(status, windowNode.view.height)

proc halfPageUp*(status: var EditorStatus) =
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  scrollUpNumberOfLines(status, Natural(windowNode.view.height / 2))

proc scrollDownNumberOfLines(status: var EditorStatus, numberOfLines: Natural) =
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    destination = min(windowNode.currentLine + numberOfLines, status.bufStatus[currentBufferIndex].buffer.len - 1)
    currentLine = windowNode.currentLine

  if status.settings.smoothScroll:
    for i in currentLine ..< destination:
      if i == status.bufStatus[currentBufferIndex].buffer.high: break

      status.bufStatus[currentBufferIndex].keyDown(windowNode)
      status.update
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.setTimeout(status.settings.smoothScrollSpeed)
      var key: Rune = ru'\0'
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)
      if key != ru'\0': break

    ## Set default time out setting
    status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window.setTimeout

  else:
    let  view = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view
    windowNode.currentLine = destination
    windowNode.currentColumn = 0
    windowNode.expandedColumn = 0

    if not (view.originalLine[0] <= destination and (view.originalLine[view.height - 1] == -1 or destination <= view.originalLine[view.height - 1])):
      let startOfPrintedLines = max(destination - (currentLine - status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.originalLine[0]), 0)
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.view.reload(status.bufStatus[currentBufferIndex].buffer, startOfPrintedLines)

proc pageDown*(status: var EditorStatus) =
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  scrollDownNumberOfLines(status, windowNode.view.height)

proc halfPageDown*(status: var EditorStatus) =
  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode
  scrollDownNumberOfLines(status, Natural(windowNode.view.height / 2))
  
proc moveToForwardWord*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
    startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n' else: bufStatus.buffer[currentLine][currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.next(currentLine, currentColumn)
  else:
    while true:
      inc(windowNode.currentColumn)
      if windowNode.currentColumn >= bufStatus.buffer[windowNode.currentLine].len:
        inc(windowNode.currentLine)
        windowNode.currentColumn = 0
        break
      if not isSkipped(bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]): break

  while true:
    if windowNode.currentLine >= bufStatus.buffer.len:
      windowNode.currentLine = bufStatus.buffer.len-1
      windowNode.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
      if windowNode.currentColumn == -1: windowNode.currentColumn = 0
      break

    if bufStatus.buffer[windowNode.currentLine].len == 0: break
    if windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].len:
      inc(windowNode.currentLine)
      windowNode.currentColumn = 0
      continue

    let curr = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(windowNode.currentColumn)

  windowNode.expandedColumn = windowNode.currentColumn

proc moveToBackwardWord*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if bufStatus.buffer.isFirst(windowNode.currentLine, windowNode.currentColumn): return

  while true:
    (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.prev(windowNode.currentLine, windowNode.currentColumn)
    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn
      
    if bufStatus.buffer[windowNode.currentLine].len == 0 or bufStatus.buffer.isFirst(currentLine, currentColumn): break

    let curr = bufStatus.buffer[currentLine][currentColumn]
    if unicodeext.isSpace(curr): continue

    if windowNode.currentColumn == 0: break

    let
      (backLine, backColumn) = bufStatus.buffer.prev(currentLine, currentColumn)
      back = bufStatus.buffer[backLine][backColumn]

    let
      currType = if isAlpha(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 3 else: 0
      backType = if isAlpha(back): 1 elif isDigit(back): 2 elif isPunct(back): 3 else: 0
    if currType != backType: break

  windowNode.expandedColumn = windowNode.currentColumn

proc moveToForwardEndOfWord*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
    startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n' else: bufStatus.buffer[currentLine][currentColumn]
    isSkipped = if unicodeext.isPunct(startWith): unicodeext.isPunct elif unicodeext.isAlpha(startWith): unicodeext.isAlpha elif unicodeext.isDigit(startWith): unicodeext.isDigit else: nil

  if isSkipped == nil:
    (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.next(currentLine, currentColumn)
  else:
    while true:
      inc(windowNode.currentColumn)
      if windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].len - 1: break
      if windowNode.currentColumn >= bufStatus.buffer[windowNode.currentLine].len:
        inc(windowNode.currentLine)
        windowNode.currentColumn = 0
        break
      if not isSkipped(bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn + 1]): break

  while true:
    if windowNode.currentLine >= bufStatus.buffer.len:
      windowNode.currentLine = bufStatus.buffer.len - 1
      windowNode.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
      if windowNode.currentColumn == -1: windowNode.currentColumn = 0
      break

    if bufStatus.buffer[windowNode.currentLine].len == 0: break
    if windowNode.currentColumn == bufStatus.buffer[windowNode.currentLine].len:
      inc(windowNode.currentLine)
      windowNode.currentColumn = 0
      continue

    let curr = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn]
    if isPunct(curr) or isAlpha(curr) or isDigit(curr): break
    inc(windowNode.currentColumn)

  windowNode.expandedColumn = windowNode.currentColumn

proc moveCenterScreen*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if windowNode.currentLine > int(windowNode.view.height / 2):
    if windowNode.cursor.y > int(windowNode.view.height / 2):
      let startOfPrintedLines = windowNode.cursor.y - int(windowNode.view.height / 2)
      windowNode.view.reload(bufStatus.buffer, windowNode.view.originalLine[startOfPrintedLines])
    else:
      let numOfTime = int(windowNode.view.height / 2) - windowNode.cursor.y
      for i in 0 ..< numOfTime: scrollUp(windowNode.view, bufStatus.buffer)

proc scrollScreenTop*(bufStatus: var BufferStatus, windowNode: var WindowNode) = windowNode.view.reload(bufStatus.buffer, windowNode.view.originalLine[windowNode.cursor.y])

proc scrollScreenBottom*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if windowNode.currentLine > windowNode.view.height:
    let numOfTime = windowNode.view.height - windowNode.cursor.y - 2
    for i in 0 ..< numOfTime: windowNode.view.scrollUp(bufStatus.buffer)
