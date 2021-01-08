import deques
import editorstatus, ui, editorview, gapbuffer, unicodetext, window, bufferstatus

template currentLineLen: int = bufStatus.buffer[windowNode.currentLine].len

proc keyLeft*(windowNode: var WindowNode) =
  if windowNode.currentColumn == 0: return

  dec(windowNode.currentColumn)
  windowNode.expandedColumn = windowNode.currentColumn

proc keyRight*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  let
    mode = bufStatus.mode
    maxColumn = currentLineLen + (if isInsertMode(mode) or isReplaceMode(mode): 1 else: 0)

  if windowNode.currentColumn + 1 >= maxColumn: return

  inc(windowNode.currentColumn)
  windowNode.expandedColumn = windowNode.currentColumn

proc keyUp*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentLine == 0: return

  dec(windowNode.currentLine)
  let maxColumn = currentLineLen - 1 + (if isInsertMode(bufStatus.mode): 1 else: 0)
  windowNode.currentColumn = min(windowNode.expandedColumn, maxColumn)

  if windowNode.currentColumn < 0: windowNode.currentColumn = 0

proc keyDown*(bufStatus: var BufferStatus, windowNode: var WindowNode) =
  if windowNode.currentLine + 1 == bufStatus.buffer.len: return

  inc(windowNode.currentLine)
  let maxColumn = currentLineLen + (if isInsertMode(bufStatus.mode): 0 else: -1)

  windowNode.currentColumn = min(windowNode.expandedColumn, maxColumn)
  if windowNode.currentColumn < 0: windowNode.currentColumn = 0

proc getFirstNonBlankOfLine*(bufStatus: BufferStatus,
                             windowNode: WindowNode): int =

  if currentLineLen == 0: return 0

  let lineLen = currentLineLen
  while bufStatus.buffer[windowNode.currentLine][result] == ru' ':
    inc(result)
    if result == lineLen: return -1

proc getFirstNonBlankOfLineOrLastColumn*(bufStatus  : BufferStatus,
                                         windowNode : WindowNode): int =

  result = getFirstNonBlankOfLine(bufStatus, windowNode)
  if result == -1:
    return currentLineLen - 1

proc getFirstNonBlankOfLineOrFirstColumn*(bufStatus  : BufferStatus,
                                          windowNode : WindowNode): int =

  result = getFirstNonBlankOfLine(bufStatus, windowNode)
  if result == -1: return 0

proc getLastNonBlankOfLine*(bufStatus: BufferStatus,
                            windowNode: WindowNode): Natural =

  if currentLineLen == 0: return 0

  result = currentLineLen - 1
  while bufStatus.buffer[windowNode.currentLine][result] == ru' ': dec(result)

proc moveToFirstNonBlankOfLine*(bufStatus: var BufferStatus,
                                windowNode: var WindowNode) =

  windowNode.currentColumn = getFirstNonBlankOfLineOrLastColumn(
    bufStatus,
    windowNode)
  windowNode.expandedColumn = windowNode.currentColumn

proc moveToLastNonBlankOfLine*(bufStatus: var BufferStatus,
                               windowNode: var WindowNode) =

  windowNode.currentColumn = getLastNonBlankOfLine(bufStatus, windowNode)
  windowNode.expandedColumn = windowNode.currentColumn

proc moveToFirstOfLine*(windowNode: var WindowNode) =
  windowNode.currentColumn = 0
  windowNode.expandedColumn = windowNode.currentColumn

proc moveToLastOfLine*(bufStatus: var BufferStatus,
                       windowNode: var WindowNode) =

  let destination = if isInsertMode(bufStatus.mode):
                      bufStatus.buffer[windowNode.currentLine].len
                    else:
                      bufStatus.buffer[windowNode.currentLine].high

  windowNode.currentColumn = max(destination, 0)
  windowNode.expandedColumn = windowNode.currentColumn

proc moveToFirstOfPreviousLine*(bufStatus: var BufferStatus,
                                windowNode: var WindowNode) =

  if windowNode.currentLine == 0: return
  bufStatus.keyUp(windowNode)
  windowNode.moveToFirstOfLine

proc moveToFirstOfNextLine*(bufStatus: var BufferStatus,
                            windowNode: var WindowNode) =

  if windowNode.currentLine + 1 == bufStatus.buffer.len: return
  bufStatus.keyDown(windowNode)
  windowNode.moveToFirstOfLine

proc jumpLine*(status: var EditorStatus, destination: int) =
  let
    currentLine = currentMainWindowNode.currentLine
    view = currentMainWindowNode.view

  currentMainWindowNode.currentLine = destination
  currentMainWindowNode.currentColumn = 0
  currentMainWindowNode.expandedColumn = 0

  if not (view.originalLine[0] <= destination and
     (view.originalLine[view.height - 1] == -1 or
     destination <= view.originalLine[view.height - 1])):
    var startOfPrintedLines = 0
    if destination > currentBufStatus.buffer.high - currentMainWindowNode.getHeight - 1:
      startOfPrintedLines = currentBufStatus.buffer.high - currentMainWindowNode.getHeight - 1
    else:
      startOfPrintedLines = max(destination - (currentLine - currentMainWindowNode.view.originalLine[0]), 0)

    currentMainWindowNode.view.reload(currentBufStatus.buffer, startOfPrintedLines)

proc findNextBlankLine*(bufStatus: BufferStatus, currentLine: int): int =
  result = -1

  if currentLine < bufStatus.buffer.len - 1:
    var currentLineStartedBlank = bufStatus.buffer[currentLine].len == 0
    for i in countup(currentLine + 1, bufStatus.buffer.len - 1):
      if bufStatus.buffer[i].len == 0:
        if not currentLineStartedBlank:
          return i
      elif currentLineStartedBlank:
        currentLineStartedBlank = false

  return -1

proc findPreviousBlankLine*(bufStatus: BufferStatus, currentLine: int): int =
  result = -1

  if currentLine > 0:
    var currentLineStartedBlank = bufStatus.buffer[currentLine].len == 0
    for i in countdown(currentLine - 1, 0):
      if bufStatus.buffer[i].len == 0:
        if not currentLineStartedBlank:
          return i
      elif currentLineStartedBlank:
        currentLineStartedBlank = false

  return -1

proc moveToNextBlankLine*(bufStatus: BufferStatus,
                          status: var EditorStatus,
                          windowNode: WindowNode) =

  let nextBlankLine = bufStatus.findNextBlankLine(windowNode.currentLine)
  if nextBlankLine >= 0: status.jumpLine(nextBlankLine)

proc moveToPreviousBlankLine*(bufStatus: BufferStatus,
                              status: var EditorStatus,
                              windowNode: WindowNode) =

  let previousBlankLine = bufStatus.findPreviousBlankLine(windowNode.currentLine)
  if previousBlankLine >= 0: status.jumpLine(previousBlankLine)

proc moveToFirstLine*(status: var EditorStatus) {.inline.} = status.jumpLine(0)

proc moveToLastLine*(status: var EditorStatus) =
  if currentBufStatus.cmdLoop > 1:
    status.jumpLine(currentBufStatus.cmdLoop - 1)
  else: status.jumpLine(currentBufStatus.buffer.high)

proc scrollUpNumberOfLines(status: var EditorStatus, numberOfLines: Natural) =
  let destination = max(currentMainWindowNode.currentLine - numberOfLines, 0)

  if status.settings.smoothScroll:
    let currentLine = currentMainWindowNode.currentLine
    for i in countdown(currentLine, destination):
      if i == 0: break

      currentBufStatus.keyUp(currentMainWindowNode)
      status.update
      currentMainWindowNode.setTimeout(status.settings.smoothScrollSpeed)
      var key = errorKey
      key = getKey(currentMainWindowNode)
      if key != errorKey: break

    ## Set default time out setting
    currentMainWindowNode.setTimeout

  else:
    status.jumpLine(destination)

proc pageUp*(status: var EditorStatus) =
  status.scrollUpNumberOfLines(currentMainWindowNode.view.height)

proc halfPageUp*(status: var EditorStatus) =
  status.scrollUpNumberOfLines(Natural(currentMainWindowNode.view.height / 2))

proc scrollDownNumberOfLines(status: var EditorStatus, numberOfLines: Natural) =
  let
    destination = min(currentMainWindowNode.currentLine + numberOfLines,
                      currentBufStatus.buffer.len - 1)
    currentLine = currentMainWindowNode.currentLine

  if status.settings.smoothScroll:
    for i in currentLine ..< destination:
      if i == currentBufStatus.buffer.high: break

      currentBufStatus.keyDown(currentMainWindowNode)
      status.update
      currentMainWindowNode.setTimeout(status.settings.smoothScrollSpeed)
      var key = errorKey
      key = getKey(currentMainWindowNode)
      if key != errorKey: break

    ## Set default time out setting
    currentMainWindowNode.setTimeout

  else:
    let view = currentMainWindowNode.view
    currentMainWindowNode.currentLine = destination
    currentMainWindowNode.currentColumn = 0
    currentMainWindowNode.expandedColumn = 0

    if not (view.originalLine[0] <= destination and
       (view.originalLine[view.height - 1] == -1 or
       destination <= view.originalLine[view.height - 1])):
      let startOfPrintedLines = max(destination - (currentLine - currentMainWindowNode.view.originalLine[0]), 0)
      currentMainWindowNode.view.reload(currentBufStatus.buffer, startOfPrintedLines)

proc pageDown*(status: var EditorStatus) =
  status.scrollDownNumberOfLines(currentMainWindowNode.view.height)

proc halfPageDown*(status: var EditorStatus) =
  status.scrollDownNumberOfLines(Natural(currentMainWindowNode.view.height / 2))

proc moveToForwardWord*(bufStatus: var BufferStatus,
                        windowNode: var WindowNode) =

  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
    startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n' else:
                   bufStatus.buffer[currentLine][currentColumn]
    isSkipped = if unicodetext.isPunct(startWith): unicodetext.isPunct elif
                   unicodetext.isAlpha(startWith): unicodetext.isAlpha elif
                   unicodetext.isDigit(startWith): unicodetext.isDigit
                else: nil

  if isSkipped == nil:
    (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.next(
      currentLine,
      currentColumn)

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

proc moveToBackwardWord*(bufStatus: var BufferStatus,
                         windowNode: var WindowNode) =

  if bufStatus.buffer.isFirst(windowNode.currentLine,
                              windowNode.currentColumn): return

  while true:
    (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.prev(
      windowNode.currentLine,
      windowNode.currentColumn)

    let
      currentLine = windowNode.currentLine
      currentColumn = windowNode.currentColumn

    if currentLineLen == 0 or
       bufStatus.buffer.isFirst(currentLine, currentColumn): break

    let curr = bufStatus.buffer[currentLine][currentColumn]
    if unicodetext.isSpace(curr): continue

    if windowNode.currentColumn == 0: break

    let
      (backLine, backColumn) = bufStatus.buffer.prev(currentLine, currentColumn)
      back = bufStatus.buffer[backLine][backColumn]

    let
      currType = if isAlpha(curr): 1 elif isDigit(curr): 2 elif isPunct(curr): 3 else: 0
      backType = if isAlpha(back): 1 elif isDigit(back): 2 elif isPunct(back): 3 else: 0
    if currType != backType: break

  windowNode.expandedColumn = windowNode.currentColumn

proc moveToForwardEndOfWord*(bufStatus: var BufferStatus,
                             windowNode: var WindowNode) =

  let
    currentLine = windowNode.currentLine
    currentColumn = windowNode.currentColumn
    startWith = if bufStatus.buffer[currentLine].len == 0: ru'\n'
                else: bufStatus.buffer[currentLine][currentColumn]
    isSkipped = if unicodetext.isPunct(startWith): unicodetext.isPunct elif
                   unicodetext.isAlpha(startWith): unicodetext.isAlpha elif
                   unicodetext.isDigit(startWith): unicodetext.isDigit
                else: nil

  if isSkipped == nil:
    (windowNode.currentLine, windowNode.currentColumn) = bufStatus.buffer.next(
      currentLine,
      currentColumn)

  else:
    while true:
      inc(windowNode.currentColumn)
      if windowNode.currentColumn == currentLineLen - 1: break
      if windowNode.currentColumn >= currentLineLen:
        inc(windowNode.currentLine)
        windowNode.currentColumn = 0
        break
      let r = bufStatus.buffer[windowNode.currentLine][windowNode.currentColumn + 1]
      if not isSkipped(r): break

  while true:
    if windowNode.currentLine >= bufStatus.buffer.len:
      windowNode.currentLine = bufStatus.buffer.len - 1
      windowNode.currentColumn = bufStatus.buffer[bufStatus.buffer.high].high
      if windowNode.currentColumn == -1: windowNode.currentColumn = 0
      break

    if bufStatus.buffer[windowNode.currentLine].len == 0: break
    if windowNode.currentColumn == currentLineLen:
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
      windowNode.view.reload(bufStatus.buffer,
                             windowNode.view.originalLine[startOfPrintedLines])
    else:
      let numOfTime = int(windowNode.view.height / 2) - windowNode.cursor.y
      for i in 0 ..< numOfTime: scrollUp(windowNode.view, bufStatus.buffer)

proc scrollScreenTop*(bufStatus: var BufferStatus,
                      windowNode: var WindowNode) {.inline.} =

  windowNode.view.reload(bufStatus.buffer,
                         windowNode.view.originalLine[windowNode.cursor.y])

proc scrollScreenBottom*(bufStatus: var BufferStatus, windowNode: WindowNode) =
  if windowNode.currentLine > windowNode.view.height:
    let numOfTime = windowNode.view.height - windowNode.cursor.y - 2
    for i in 0 ..< numOfTime: windowNode.view.scrollUp(bufStatus.buffer)
