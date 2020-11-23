import terminal, strutils, sequtils, times
import editorstatus, ui, gapbuffer, unicodetext, window, movement, editor,
       bufferstatus

proc initSelectArea(startLine, startColumn: int): SelectArea =
  result.startLine = startLine
  result.startColumn = startColumn
  result.endLine = startLine
  result.endColumn = startColumn

proc updateSelectArea(area: var SelectArea,
                      currentLine, currentColumn: int) {.inline.} =

  area.endLine = currentLine
  area.endColumn = currentColumn

proc swapSelectArea(area: var SelectArea) =
  if area.startLine == area.endLine:
    if area.endColumn < area.startColumn: swap(area.startColumn, area.endColumn)
  elif area.endLine < area.startLine:
    swap(area.startLine, area.endLine)
    swap(area.startColumn, area.endColumn)

proc yankBuffer(bufStatus: var BufferStatus,
                registers: var Registers,
                windowNode: WindowNode,
                area: SelectArea,
                platform: Platform,
                clipboard: bool) =

  registers.yankedLines = @[]
  registers.yankedStr = @[]

  if area.startLine == area.endLine:
    if bufStatus.buffer[windowNode.currentLine].len < 1:
        registers.yankedLines.add(@[ru""])
    else:
      for j in area.startColumn .. area.endColumn:
        registers.yankedStr.add(bufStatus.buffer[area.startLine][j])
  else:
    for i in area.startLine .. area.endLine:
      if i == area.startLine and area.startColumn > 0:
        registers.yankedLines.add(ru"")
        for j in area.startColumn ..< bufStatus.buffer[area.startLine].len:
          registers.yankedLines[^1].add(bufStatus.buffer[area.startLine][j])
      elif i == area.endLine and
           area.endColumn < bufStatus.buffer[area.endLine].len:
        registers.yankedLines.add(ru"")
        for j in 0 .. area.endColumn:
          registers.yankedLines[^1].add(bufStatus.buffer[area.endLine][j])
      else:
        registers.yankedLines.add(bufStatus.buffer[i])

  if clipboard: registers.sendToClipboad(platform)

proc yankBufferBlock(bufStatus: var BufferStatus,
                     registers: var Registers,
                     windowNode: WindowNode,
                     area: SelectArea,
                     platform: Platform,
                     clipboard: bool) =

  if bufStatus.buffer.len == 1 and
     bufStatus.buffer[windowNode.currentLine].len < 1: return
  registers.yankedLines = @[]
  registers.yankedStr = @[]

  for i in area.startLine .. area.endLine:
    registers.yankedLines.add(ru"")
    for j in area.startColumn .. min(bufStatus.buffer[i].high, area.endColumn):
      registers.yankedLines[^1].add(bufStatus.buffer[i][j])

  if clipboard: registers.sendToClipboad(platform)

proc deleteBuffer(bufStatus: var BufferStatus,
                  registers: var Registers,
                  windowNode: WindowNode,
                  area: SelectArea,
                  platform: Platform,
                  clipboard: bool) =

  if bufStatus.buffer.len == 1 and
     bufStatus.buffer[windowNode.currentLine].len < 1: return
  bufStatus.yankBuffer(registers, windowNode, area, platform, clipboard)

  var currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[currentLine]
    var newLine = bufStatus.buffer[currentLine]

    if area.startLine == area.endLine:
      if oldLine.len > 0:
        for j in area.startColumn .. area.endColumn:
          newLine.delete(area.startColumn)
        if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
      else:
        bufStatus.buffer.delete(currentLine, currentLine)
    elif i == area.startLine and 0 < area.startColumn:
      for j in area.startColumn .. bufStatus.buffer[currentLine].high:
        newLine.delete(area.startColumn)
      if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
      inc(currentLine)
    elif i == area.endLine and area.endColumn < bufStatus.buffer[currentLine].high:
      for j in 0 .. area.endColumn: newLine.delete(0)
      if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
    else: bufStatus.buffer.delete(currentLine, currentLine)

  if bufStatus.buffer.len < 1: bufStatus.buffer.add(ru"")

  if area.startLine > bufStatus.buffer.high:
    windowNode.currentLine = bufStatus.buffer.high
  else: windowNode.currentLine = area.startLine
  let column = if area.startColumn > 0: area.startColumn - 1 else: 0
  windowNode.currentColumn = column
  windowNode.expandedColumn = column

  inc(bufStatus.countChange)

proc deleteBufferBlock(bufStatus: var BufferStatus,
                       registers: var Registers,
                       windowNode: WindowNode,
                       area: SelectArea,
                       platform: Platform,
                       clipboard: bool) =

  if bufStatus.buffer.len == 1 and
     bufStatus.buffer[windowNode.currentLine].len < 1: return
  bufStatus.yankBufferBlock(registers, windowNode, area, platform, clipboard)

  if area.startLine == area.endLine and bufStatus.buffer[area.startLine].len < 1:
    bufStatus.buffer.delete(area.startLine, area.startLine + 1)
  else:
    var currentLine = area.startLine
    for i in area.startLine .. area.endLine:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      for j in area.startColumn.. min(area.endColumn, bufStatus.buffer[i].high):
        newLine.delete(area.startColumn)
        inc(currentLine)
      if oldLine != newLine: bufStatus.buffer[i] = newLine

  windowNode.currentLine = min(area.startLine, bufStatus.buffer.high)
  windowNode.currentColumn = area.startColumn
  inc(bufStatus.countChange)

proc addIndent(bufStatus: var BufferStatus,
               windowNode: WindowNode,
               area: SelectArea,
               tabStop: int) =

  windowNode.currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    bufStatus.addIndent(windowNode, tabStop)
    inc(windowNode.currentLine)

  windowNode.currentLine = area.startLine

proc deleteIndent(bufStatus: var BufferStatus,
                  windowNode: WindowNode,
                  area: SelectArea,
                  tabStop: int) =

  windowNode.currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    deleteIndent(bufStatus, windowNode, tabStop)
    inc(windowNode.currentLine)

  windowNode.currentLine = area.startLine

proc insertIndent(bufStatus: var BufferStatus, area: SelectArea, tabStop: int) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    newLine.insert(ru' '.repeat(tabStop),
                   min(area.startColumn,
                   bufStatus.buffer[i].high))
    if oldLine != newLine: bufStatus.buffer[i] = newLine

proc replaceCharacter(bufStatus: var BufferStatus, area: SelectArea, ch: Rune) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    if area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn: newLine[j] = ch
    elif i == area.startLine:
      for j in area.startColumn .. bufStatus.buffer[i].high: newLine[j] = ch
    elif i == area.endLine:
      for j in 0 .. area.endColumn: newLine[j] = ch
    else:
      for j in 0 .. bufStatus.buffer[i].high: newLine[j] = ch
    if oldLine != newLine: bufStatus.buffer[i] = newLine

  inc(bufStatus.countChange)

proc replaceCharacterBlock(bufStatus: var BufferStatus,
                           area: SelectArea,
                           ch: Rune) =

  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high):
      newLine[j] = ch
    if oldLine != newLine: bufStatus.buffer[i] = newLine

proc joinLines(bufStatus: var BufferStatus,
               windowNode: WindowNode,
               area: SelectArea) =

  for i in area.startLine .. area.endLine:
    windowNode.currentLine = area.startLine
    bufStatus.joinLine(windowNode)

proc toLowerString(bufStatus: var BufferStatus, area: SelectArea) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    if oldLine.len == 0: discard
    elif area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn:
        newLine[j] = oldLine[j].toLower
    elif i == area.startLine:
      for j in area.startColumn .. bufStatus.buffer[i].high:
        newLine[j] = oldLine[j].toLower
    elif i == area.endLine:
      for j in 0 .. area.endColumn: newLine[j] = oldLine[j].toLower
    else:
      for j in 0 .. bufStatus.buffer[i].high: newLine[j] = oldLine[j].toLower
    if oldLine != newLine: bufStatus.buffer[i] = newLine

  inc(bufStatus.countChange)

proc toLowerStringBlock(bufStatus: var BufferStatus, area: SelectArea) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high):
      newLine[j] = oldLine[j].toLower
    if oldLine != newLine: bufStatus.buffer[i] = newLine

proc toUpperString(bufStatus: var BufferStatus, area: SelectArea) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    if oldLine.len == 0: discard
    elif area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn:
        newLine[j] = oldLine[j].toUpper
    elif i == area.startLine:
      for j in area.startColumn .. bufStatus.buffer[i].high:
        newLine[j] = oldLine[j].toUpper
    elif i == area.endLine:
      for j in 0 .. area.endColumn: newLine[j] = oldLine[j].toUpper
    else:
      for j in 0 .. bufStatus.buffer[i].high: newLine[j] = oldLine[j].toUpper
    if oldLine != newLine: bufStatus.buffer[i] = newLine

  inc(bufStatus.countChange)

proc toUpperStringBlock(bufStatus: var BufferStatus, area: SelectArea) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high):
      newLine[j] = oldLine[j].toUpper
    if oldLine != newLine: bufStatus.buffer[i] = newLine

proc getInsertBuffer(status: var Editorstatus): seq[Rune] =
  while true:
    status.update

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    if isEscKey(key):
      break
    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEnterKey(key):
      currentBufStatus.keyEnter(
        currentMainWindowNode,
        status.settings.autoIndent,
        status.settings.tabStop)
      break
    elif isDcKey(key):
      currentBufStatus.deleteCurrentCharacter(
        currentMainWindowNode,
        status.settings.autoDeleteParen)
      break
    elif isTabKey(key):
      result.add(key)
      insertTab(currentBufStatus,
                currentMainWindowNode,
                status.settings.tabStop,
                status.settings.autoCloseParen)
    else:
      result.add(key)
      currentBufStatus.insertCharacter(
        currentMainWindowNode,
        status.settings.autoCloseParen,
        key)

proc insertCharBlock(bufStatus: var BufferStatus,
                     windowNode: var WindowNode,
                     insertBuffer: seq[Rune],
                     area: SelectArea,
                     tabStop: int,
                     autoCloseParen: bool) =

  if area.startLine == area.endLine: return

  let beforeLine = windowNode.currentLine

  for i in area.startLine + 1 .. area.endLine:
    windowNode.currentLine = i
    windowNode.currentColumn = area.startColumn

    if bufStatus.buffer[i].high >= area.startColumn:
      for c in insertBuffer:
        if isTabKey(c):
          insertTab(bufStatus,
                    windowNode,
                    tabStop,
                    autoCloseParen)
        else:
          bufStatus.insertCharacter(windowNode,
                                    autoCloseParen,
                                    c)
  windowNode.currentLine = beforeLine

proc visualCommand(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSelectArea

  let clipboard = status.settings.systemClipboard

  if key == ord('y') or isDcKey(key):
    currentBufStatus.yankBuffer(status.registers,
                                currentMainWindowNode,
                                area, status.platform,
                                clipboard)
  elif key == ord('x') or key == ord('d'):
    currentBufStatus.deleteBuffer(status.registers,
                                  currentMainWindowNode,
                                  area,
                                  status.platform,
                                  clipboard)
  elif key == ord('>'):
    currentBufStatus.addIndent(currentMainWindowNode,
                               area,
                               status.settings.tabStop)
  elif key == ord('<'):
    currentBufStatus.deleteIndent(currentMainWindowNode,
                                  area,
                                  status.settings.tabStop)
  elif key == ord('J'):
    currentBufStatus.joinLines(currentMainWindowNode, area)
  elif key == ord('u'):
    currentBufStatus.toLowerString(area)
  elif key == ord('U'):
    currentBufStatus.toUpperString(area)
  elif key == ord('r'):
    let ch = currentMainWindowNode.getKey
    if not isEscKey(ch):
      currentBufStatus.replaceCharacter(area, ch)
  elif key == ord('I'):
    currentMainWindowNode.currentLine = currentBufStatus.selectArea.startLine
    currentMainWindowNode.currentColumn = 0
    status.changeMode(Mode.insert)
  else: discard

proc visualBlockCommand(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSelectArea

  let clipboard = status.settings.systemClipboard

  template insertCharacterMultipleLines() =
    status.changeMode(Mode.insert)

    currentMainWindowNode.currentLine = area.startLine
    currentMainWindowNode.currentColumn = area.startColumn
    let insertBuffer = status.getInsertBuffer

    if insertBuffer.len > 0:
      var windowNode = currentMainWindowNode
      currentBufStatus.insertCharBlock(
        windowNode,
        insertBuffer,
        area,
        status.settings.tabStop,
        status.settings.autoCloseParen)
    else:
      currentMainWindowNode.currentLine = area.startLine
      currentMainWindowNode.currentColumn = area.startColumn

  if key == ord('y') or isDcKey(key):
    currentBufStatus.yankBufferBlock(status.registers,
                                     currentMainWindowNode,
                                     area,
                                     status.platform,
                                     clipboard)
  elif key == ord('x') or key == ord('d'):
    currentBufStatus.deleteBufferBlock(status.registers,
                                       currentMainWindowNode,
                                       area,
                                       status.platform,
                                       clipboard)
  elif key == ord('>'):
    currentBufStatus.insertIndent(area, status.settings.tabStop)
  elif key == ord('<'):
    currentBufStatus.deleteIndent(currentMainWindowNode,
                                  area,
                                  status.settings.tabStop)
  elif key == ord('J'):
    currentBufStatus.joinLines(currentMainWindowNode, area)
  elif key == ord('u'):
    currentBufStatus.toLowerStringBlock(area)
  elif key == ord('U'):
    currentBufStatus.toUpperStringBlock(area)
  elif key == ord('r'):
    let ch = currentMainWindowNode.getKey
    if not isEscKey(ch): currentBufStatus.replaceCharacterBlock(area, ch)
  elif key == ord('I'):
    insertCharacterMultipleLines()
  else: discard

proc visualMode*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())
  currentBufStatus.selectArea = initSelectArea(
    currentMainWindowNode.currentLine,
    currentMainWindowNode.currentColumn)

  while currentBufStatus.mode == Mode.visual or
        currentBufStatus.mode == Mode.visualBlock:

    currentBufStatus.selectArea.updateSelectArea(
      currentMainWindowNode.currentLine,
      currentMainWindowNode.currentColumn)

    status.update

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    currentBufStatus.buffer.beginNewSuitIfNeeded
    currentBufStatus.tryRecordCurrentPosition(currentMainWindowNode)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      status.updatehighlight(currentMainWindowNode)
      status.changeMode(Mode.normal)

    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      currentMainWindowNode.keyLeft
    elif key == ord('l') or isRightKey(key):
      currentBufStatus.keyRight(currentMainWindowNode)
    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key) or isEnterKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif key == ord('^'):
      currentBufStatus.moveToFirstNonBlankOfLine(currentMainWindowNode)
    elif key == ord('0') or isHomeKey(key):
      currentMainWindowNode.moveToFirstOfLine
    elif key == ord('$') or isEndKey(key):
      currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    elif key == ord('w'):
      currentBufStatus.moveToForwardWord(currentMainWindowNode)
    elif key == ord('b'):
      currentBufStatus.moveToBackwardWord(currentMainWindowNode)
    elif key == ord('e'):
      currentBufStatus.moveToForwardEndOfWord(currentMainWindowNode)
    elif key == ord('G'):
      moveToLastLine(status)
    elif key == ord('g'):
      if getKey(currentMainWindowNode) == ord('g'):
        moveToFirstLine(status)
    elif key == ord('i'):
      currentMainWindowNode.currentLine = currentBufStatus.selectArea.startLine
      status.changeMode(Mode.insert)
    else:
      if isVisualBlockMode(currentBufStatus.mode):
        status.visualBlockCommand(currentBufStatus.selectArea, key)
      else:
        status.visualCommand(currentBufStatus.selectArea, key)
      status.update
      status.changeMode(Mode.normal)
