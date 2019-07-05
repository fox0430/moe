import terminal, strutils, sequtils
import editorstatus, editorview, ui, gapbuffer, normalmode, highlight, unicodeext

proc initColorSegment(startLine, startColumn: int): ColorSegment =
  result.firstRow = startLine
  result.firstColumn = startColumn
  result.lastRow = startLine
  result.lastColumn = startColumn
  result.color = EditorColorPair.visualMode

proc initSelectArea(startLine, startColumn: int): SelectArea =
  result.startLine = startLine
  result.startColumn = startColumn
  result.endLine = startLine
  result.endColumn = startColumn

proc updateSelectArea(area: var SelectArea, currentLine, currentColumn: int) =
  area.endLine = currentLine
  area.endColumn = currentColumn

proc updateColorSegment(colorSegment: var ColorSegment, area: SelectArea) =
  if area.startLine == area.endLine:
    colorSegment.firstRow = area.startLine
    colorSegment.lastRow = area.endLine
    if area.startColumn < area.endColumn:
      colorSegment.firstColumn = area.startColumn
      colorSegment.lastColumn = area.endColumn
    else:
      colorSegment.firstColumn = area.endColumn
      colorSegment.lastColumn = area.startColumn
  elif area.startLine < area.endLine:
    colorSegment.firstRow = area.startLine
    colorSegment.lastRow = area.endLine
    colorSegment.firstColumn = area.startColumn
    colorSegment.lastColumn = area.endColumn
  else:
    colorSegment.firstRow = area.endLine
    colorSegment.lastRow = area.startLine
    colorSegment.firstColumn = area.endColumn
    colorSegment.lastColumn = area.startColumn

proc overwriteColorSegmentBlock[T](highlight: var Highlight, area: SelectArea, buffer: T) =
  var
    startLine = area.startLine
    endLine = area.endLine
  if startLine > endLine: swap(startLine, endLine)

  for i in startLine .. endLine:
    let colorSegment = ColorSegment(firstRow: i, firstColumn: area.startColumn, lastRow: i, lastColumn: min(area.endColumn, buffer[i].high), color: EditorColorPair.visualMode)
    highlight = highlight.overwrite(colorSegment)

proc swapSlectArea(area: var SelectArea) =
  if area.startLine == area.endLine:
    if area.endColumn < area.startColumn: swap(area.startColumn, area.endColumn)
  elif area.endLine < area.startLine:
    swap(area.startLine, area.endLine)
    swap(area.startColumn, area.endColumn)

proc yankBuffer(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea) =
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

proc yankBufferBlock(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea) =
  if bufStatus.buffer.len == 1 and bufStatus.buffer[bufStatus.currentLine].len < 1: return
  registers.yankedLines = @[]
  registers.yankedStr = @[]

  for i in area.startLine .. area.endLine:
    registers.yankedLines.add(ru"")
    for j in area.startColumn .. min(bufStatus.buffer[i].high, area.endColumn): registers.yankedLines[registers.yankedLines.high].add(bufStatus.buffer[i][j])

proc deleteBuffer(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea) =
  if bufStatus.buffer.len == 1 and bufStatus.buffer[bufStatus.currentLine].len < 1: return
  yankBuffer(bufStatus, registers, area)

  var currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    let oldLine = bufStatus.buffer[area.startLine]
    var newLine = bufStatus.buffer[area.startLine]

    if area.startLine == area.endLine and 0 < bufStatus.buffer[currentLine].len:
      for j in area.startColumn .. area.endColumn: newLine.delete(area.startColumn)
    elif i == area.startLine and 0 < area.startColumn:
      for j in area.startColumn .. bufStatus.buffer[currentLine].high: newLine.delete(area.startColumn)
      inc(currentLine)
    elif i == area.endLine and area.endColumn < bufStatus.buffer[currentLine].high:
      for j in 0 .. area.endColumn: newLine.delete(0)
    else: bufStatus.buffer.delete(currentLine, currentLine + 1)
    
    if oldLine != newLine: bufStatus.buffer[area.startLine] = newLine

  if bufStatus.buffer.len < 1: bufStatus.buffer.add(ru"")

  if area.startLine > bufStatus.buffer.high: bufStatus.currentLine = bufStatus.buffer.high
  else: bufStatus.currentLine = area.startLine
  let column = if area.startColumn > 0: area.startColumn - 1 else: 0
  bufStatus.currentColumn = column
  bufStatus.expandedColumn = column

  inc(bufStatus.countChange)

proc deleteBufferBlock(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea) =
  if bufStatus.buffer.len == 1 and bufStatus.buffer[bufStatus.currentLine].len < 1: return
  yankBufferBlock(bufStatus, registers, area)

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

proc addIndent(bufStatus: var BufferStatus, area: SelectArea, tabStop: int) =
  bufStatus.currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    addIndent(bufStatus, tabStop)
    inc(bufStatus.currentLine)

  bufStatus.currentLine = area.startLine

proc deleteIndent(bufStatus: var BufferStatus, area: SelectArea, tabStop: int) =
  bufStatus.currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    deleteIndent(bufStatus, tabStop)
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

proc visualCommand(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSlectArea

  if key == ord('y') or isDcKey(key): yankBuffer(status.bufStatus[status.currentBuffer], status.registers, area)
  elif key == ord('x') or key == ord('d'): deleteBuffer(status.bufStatus[status.currentBuffer], status.registers, area)
  elif key == ord('>'): addIndent(status.bufStatus[status.currentBuffer], area, status.settings.tabStop)
  elif key == ord('<'): deleteIndent(status.bufStatus[status.currentBuffer], area, status.settings.tabStop)
  elif key == ord('r'):
    let ch = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    if not isEscKey(ch): replaceCharactor(status.bufStatus[status.currentBuffer], area, ch)
  else: discard

proc visualBlockCommand(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSlectArea

  if key == ord('y') or isDcKey(key): yankBufferBlock(status.bufStatus[status.currentBuffer], status.registers, area)
  elif key == ord('x') or key == ord('d'): deleteBufferBlock(status.bufStatus[status.currentBuffer], status.registers, area)
  elif key == ord('>'): insertIndent(status.bufStatus[status.currentBuffer], area, status.settings.tabStop)
  elif key == ord('r'):
    let ch = getKey(status.mainWindowInfo[status.currentMainWindow].window)
    if not isEscKey(ch): replaceCharactorBlock(status.bufStatus[status.currentBuffer], area, ch)
  else: discard

proc visualMode*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())
  let currentBuf = status.currentBuffer

  var colorSegment = initColorSegment(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  status.bufStatus[currentBuf].selectArea = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  while status.bufStatus[status.currentBuffer].mode == Mode.visual or status.bufStatus[status.currentBuffer].mode == Mode.visualBlock:
    let isBlockMode = if status.bufStatus[status.currentBuffer].mode == Mode.visualBlock: true else: false

    status.bufStatus[currentBuf].selectArea.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    colorSegment.updateColorSegment(status.bufStatus[currentBuf].selectArea)

    status.updatehighlight
    if isBlockMode: status.bufStatus[status.currentBuffer].highlight.overwriteColorSegmentBlock(status.bufStatus[currentBuf].selectArea, status.bufStatus[status.currentBuffer].buffer)
    else: status.bufStatus[status.currentBuffer].highlight = status.bufStatus[status.currentBuffer].highlight.overwrite(colorSegment)

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'): key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

    status.bufStatus[status.currentBuffer].buffer.beginNewSuitIfNeeded
    status.bufStatus[status.currentBuffer].tryRecordCurrentPosition

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      status.updatehighlight
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
      if getKey(status.mainWindowInfo[status.currentMainWindow].window) == ord('g'): moveToFirstLine(status)
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
      status.updatehighlight
      status.changeMode(Mode.normal)
