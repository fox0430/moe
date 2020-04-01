import terminal, strutils, sequtils
import editorstatus, ui, gapbuffer, normalmode, unicodeext, window, movement, editor

proc initSelectArea*(startLine, startColumn: int): SelectArea =
  result.startLine = startLine
  result.startColumn = startColumn
  result.endLine = startLine
  result.endColumn = startColumn

proc updateSelectArea*(area: var SelectArea, currentLine, currentColumn: int) =
  area.endLine = currentLine
  area.endColumn = currentColumn

proc swapSlectArea(area: var SelectArea) =
  if area.startLine == area.endLine:
    if area.endColumn < area.startColumn: swap(area.startColumn, area.endColumn)
  elif area.endLine < area.startLine:
    swap(area.startLine, area.endLine)
    swap(area.startColumn, area.endColumn)

proc yankBuffer*(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea, platform: Platform, clipboard: bool) =
  if bufStatus.buffer[bufStatus.currentLine].len < 1: return
  registers.yankedLines = @[]
  registers.yankedStr = @[]

  for i in area.startLine .. area.endLine:
    if area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn: registers.yankedStr.add(bufStatus.buffer[area.startLine][j])
    if i == area.startLine and area.startColumn > 0:
      registers.yankedLines.add(ru"")
      for j in area.startColumn ..< bufStatus.buffer[area.startLine].len:
        registers.yankedLines[registers.yankedLines.high].add(bufStatus.buffer[area.startLine][j])
    elif i == area.endLine and area.endColumn < bufStatus.buffer[area.endLine].len:
      registers.yankedLines.add(ru"")
      for j in 0 .. area.endColumn:
        registers.yankedLines[registers.yankedLines.high].add(bufStatus.buffer[area.endLine][j])
    else:
      registers.yankedLines.add(bufStatus.buffer[i])

    if clipboard: registers.sendToClipboad(platform)

proc yankBufferBlock*(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea, platform: Platform, clipboard: bool) =
  if bufStatus.buffer.len == 1 and bufStatus.buffer[bufStatus.currentLine].len < 1: return
  registers.yankedLines = @[]
  registers.yankedStr = @[]

  for i in area.startLine .. area.endLine:
    registers.yankedLines.add(ru"")
    for j in area.startColumn .. min(bufStatus.buffer[i].high, area.endColumn): registers.yankedLines[registers.yankedLines.high].add(bufStatus.buffer[i][j])

  if clipboard: registers.sendToClipboad(platform)

proc deleteBuffer(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea, platform: Platform, clipboard: bool) =
  if bufStatus.buffer.len == 1 and bufStatus.buffer[bufStatus.currentLine].len < 1: return
  bufStatus.yankBuffer(registers, area, platform, clipboard)

  var currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[currentLine]
    var newLine = bufStatus.buffer[currentLine]

    if area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn: newLine.delete(area.startColumn)
      if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
    elif i == area.startLine and 0 < area.startColumn:
      for j in area.startColumn .. bufStatus.buffer[currentLine].high: newLine.delete(area.startColumn)
      if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
      inc(currentLine)
    elif i == area.endLine and area.endColumn < bufStatus.buffer[currentLine].high:
      for j in 0 .. area.endColumn: newLine.delete(0)
      if oldLine != newLine: bufStatus.buffer[currentLine] = newLine
    else: bufStatus.buffer.delete(currentLine, currentLine)

  if bufStatus.buffer.len < 1: bufStatus.buffer.add(ru"")

  if area.startLine > bufStatus.buffer.high: bufStatus.currentLine = bufStatus.buffer.high
  else: bufStatus.currentLine = area.startLine
  let column = if area.startColumn > 0: area.startColumn - 1 else: 0
  bufStatus.currentColumn = column
  bufStatus.expandedColumn = column

  inc(bufStatus.countChange)

proc deleteBufferBlock*(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea, platform: Platform, clipboard: bool) =
  if bufStatus.buffer.len == 1 and bufStatus.buffer[bufStatus.currentLine].len < 1: return
  yankBufferBlock(bufStatus, registers, area, platform, clipboard)

  var currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    if bufStatus.buffer[currentLine].len < 1: bufStatus.buffer.delete(currentLine, currentLine + 1)
    else:
      let oldLine = bufStatus.buffer[i]
      var newLine = bufStatus.buffer[i]
      for j in area.startColumn.. min(area.endColumn, bufStatus.buffer[i].high):
        newLine.delete(area.startColumn)
        inc(currentLine)
      if oldLine != newLine: bufStatus.buffer[i] = newLine

  bufStatus.currentLine = min(area.startLine, bufStatus.buffer.high)
  bufStatus.currentColumn = area.startColumn
  inc(bufStatus.countChange)

proc addIndent(bufStatus: var BufferStatus, currentWin: WindowNode, area: SelectArea, tabStop: int) =
  bufStatus.currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    addIndent(bufStatus, currentWin, tabStop)
    inc(bufStatus.currentLine)

  bufStatus.currentLine = area.startLine

proc deleteIndent(bufStatus: var BufferStatus, currentWin: WindowNode, area: SelectArea, tabStop: int) =
  bufStatus.currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    deleteIndent(bufStatus, currentWin, tabStop)
    inc(bufStatus.currentLine)

  bufStatus.currentLine = area.startLine

proc insertIndent(bufStatus: var BufferStatus, area: SelectArea, tabStop: int) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    newLine.insert(ru' '.repeat(tabStop), min(area.startColumn, bufStatus.buffer[i].high))
    if oldLine != newLine: bufStatus.buffer[i] = newLine

proc replaceCharactor(bufStatus: var BufferStatus, area: SelectArea, ch: Rune) =
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

proc replaceCharactorBlock(bufStatus: var BufferStatus, area: SelectArea, ch: Rune) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high): newLine[j] = ch
    if oldLine != newLine: bufStatus.buffer[i] = newLine

proc joinLines*(bufStatus: var BufferStatus, win: WindowNode, area: SelectArea) =
  for i in area.startLine .. area.endLine:
    bufStatus.currentLine = area.startLine
    bufStatus.joinLine(win)

proc toLowerString(bufStatus: var BufferStatus, area: SelectArea) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    if area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn: newLine[j] = oldLine[j].toLower
    elif i == area.startLine:
      for j in area.startColumn .. bufStatus.buffer[i].high: newLine[j] = oldLine[j].toLower
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
    for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high): newLine[j] = oldLine[j].toLower
    if oldLine != newLine: bufStatus.buffer[i] = newLine

proc toUpperString(bufStatus: var BufferStatus, area: SelectArea) =
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[i]
    var newLine = bufStatus.buffer[i]
    if area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn: newLine[j] = oldLine[j].toUpper
    elif i == area.startLine:
      for j in area.startColumn .. bufStatus.buffer[i].high: newLine[j] = oldLine[j].toUpper
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
    for j in area.startColumn .. min(area.endColumn, bufStatus.buffer[i].high): newLine[j] = oldLine[j].toUpper
    if oldLine != newLine: bufStatus.buffer[i] = newLine

proc visualCommand*(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSlectArea

  let clipboard = status.settings.systemClipboard

  if key == ord('y') or isDcKey(key): status.bufStatus[status.currentBuffer].yankBuffer(status.registers, area, status.platform, clipboard)
  elif key == ord('x') or key == ord('d'): status.bufStatus[status.currentBuffer].deleteBuffer(status.registers, area, status.platform, clipboard)
  elif key == ord('>'): status.bufStatus[status.currentBuffer].addIndent(status.currentMainWindowNode, area, status.settings.tabStop)
  elif key == ord('<'): status.bufStatus[status.currentBuffer].deleteIndent(status.currentMainWindowNode, area, status.settings.tabStop)
  elif key == ord('J'): status.bufStatus[status.currentBuffer].joinLines(status.currentMainWindowNode, area)
  elif key == ord('u'): status.bufStatus[status.currentBuffer].toLowerString(area)
  elif key == ord('U'): status.bufStatus[status.currentBuffer].toUpperString(area)
  elif key == ord('r'):
    let ch = status.currentMainWindowNode.window.getKey
    if not isEscKey(ch): status.bufStatus[status.currentBuffer].replaceCharactor(area, ch)
  else: discard

proc visualBlockCommand*(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSlectArea

  let clipboard = status.settings.systemClipboard

  if key == ord('y') or isDcKey(key): status.bufStatus[status.currentBuffer].yankBufferBlock(status.registers, area, status.platform, clipboard)
  elif key == ord('x') or key == ord('d'): status.bufStatus[status.currentBuffer].deleteBufferBlock(status.registers, area, status.platform, clipboard)
  elif key == ord('>'): status.bufStatus[status.currentBuffer].insertIndent(area, status.settings.tabStop)
  elif key == ord('<'): status.bufStatus[status.currentBuffer].deleteIndent(status.currentMainWindowNode, area, status.settings.tabStop)
  elif key == ord('J'): status.bufStatus[status.currentBuffer].joinLines(status.currentMainWindowNode, area)
  elif key == ord('u'): status.bufStatus[status.currentBuffer].toLowerStringBlock(area)
  elif key == ord('U'): status.bufStatus[status.currentBuffer].toUpperStringBlock(area)
  elif key == ord('r'):
    let ch = status.currentMainWindowNode.window.getKey
    if not isEscKey(ch): status.bufStatus[status.currentBuffer].replaceCharactorBlock(area, ch)
  else: discard

proc visualMode*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())
  let currentBuf = status.currentBuffer

  status.bufStatus[currentBuf].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  while status.bufStatus[status.currentBuffer].mode == Mode.visual or status.bufStatus[status.currentBuffer].mode == Mode.visualBlock:
    let isBlockMode = if status.bufStatus[status.currentBuffer].mode == Mode.visualBlock: true else: false

    status.bufStatus[currentBuf].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key = getKey(status.currentMainWindowNode.window)

    status.bufStatus[status.currentBuffer].buffer.beginNewSuitIfNeeded
    status.bufStatus[status.currentBuffer].tryRecordCurrentPosition

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      status.updatehighlight(status.currentBuffer)
      status.changeMode(Mode.normal)

    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      keyLeft(status.bufStatus[status.currentBuffer])
    elif key == ord('l') or isRightKey(key):
      keyRight(status.bufStatus[status.currentBuffer])
    elif key == ord('k') or isUpKey(key):
      keyUp(status.bufStatus[status.currentBuffer])
    elif key == ord('j') or isDownKey(key) or isEnterKey(key):
      keyDown(status.bufStatus[status.currentBuffer])
    elif key == ord('^'):
      moveToFirstNonBlankOfLine(status.bufStatus[status.currentBuffer])
    elif key == ord('0') or isHomeKey(key):
      moveToFirstOfLine(status.bufStatus[status.currentBuffer])
    elif key == ord('$') or isEndKey(key):
      moveToLastOfLine(status.bufStatus[status.currentBuffer])
    elif key == ord('w'):
      moveToForwardWord(status.bufStatus[status.currentBuffer])
    elif key == ord('b'):
      moveToBackwardWord(status.bufStatus[status.currentBuffer])
    elif key == ord('e'):
      moveToForwardEndOfWord(status.bufStatus[status.currentBuffer])
    elif key == ord('G'):
      moveToLastLine(status)
    elif key == ord('g'):
      if getKey(status.currentMainWindowNode.window) == ord('g'): moveToFirstLine(status)
    elif key == ord('i'):
      status.bufStatus[status.currentBuffer].currentLine = status.bufStatus[currentBuf].selectArea.startLine
      status.changeMode(Mode.insert)
    elif key == ord('I'):
      status.bufStatus[status.currentBuffer].currentLine = status.bufStatus[currentBuf].selectArea.startLine
      status.bufStatus[status.currentBuffer].currentColumn = 0
      status.changeMode(Mode.insert)

    else:
      if isBlockMode: visualBlockCommand(status, status.bufStatus[currentBuf].selectArea, key)
      else: visualCommand(status, status.bufStatus[currentBuf].selectArea, key)
      status.updatehighlight(status.currentBuffer)
      status.changeMode(Mode.normal)
