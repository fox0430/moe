import terminal
import editorstatus, editorview, ui, gapbuffer, normalmode, highlight, unicodeext

type SelectArea = object
  startLine: int
  startColumn: int
  endLine: int
  endColumn: int

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
  for i in area.startLine .. area.endLine:
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

proc deleteBuffer(bufStatus: var BufferStatus, registers: var Registers, area: SelectArea) =
  if bufStatus.buffer.len == 1 and bufStatus.buffer[bufStatus.currentLine].len < 1: return
  yankBuffer(bufStatus, registers, area)

  var currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    if area.startLine == area.endLine and 0 < bufStatus.buffer[currentLine].len:
      for j in area.startColumn .. area.endColumn: bufStatus.buffer[currentLine].delete(area.startColumn)
    elif i == area.startLine and 0 < area.startColumn:
      for j in area.startColumn .. bufStatus.buffer[currentLine].high: bufStatus.buffer[currentLine].delete(area.startColumn)
      inc(currentLine)
    elif i == area.endLine and area.endColumn < bufStatus.buffer[currentLine].high:
      for j in 0 .. area.endColumn: bufStatus.buffer[currentLine].delete(0)
    else: bufStatus.buffer.delete(currentLine, currentLine + 1)

  if bufStatus.buffer.len < 1: bufStatus.buffer.add(ru"")

  if area.startLine > bufStatus.buffer.high: bufStatus.currentLine = bufStatus.buffer.high
  else: bufStatus.currentLine = area.startLine
  let column = if area.startColumn > 0: area.startColumn - 1 else: 0
  bufStatus.currentColumn = column
  bufStatus.expandedColumn = column

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

proc visualCommand(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSlectArea

  if key == ord('y') or isDcKey(key): yankBuffer(status.bufStatus[status.currentBuffer], status.registers, area)
  elif key == ord('x') or key == ord('d'): deleteBuffer(status.bufStatus[status.currentBuffer], status.registers, area)
  elif key == ord('>'): addIndent(status.bufStatus[status.currentBuffer], area, status.settings.tabStop)
  elif key == ord('<'): deleteIndent(status.bufStatus[status.currentBuffer], area, status.settings.tabStop)
  else: discard

proc visualMode*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())

  var colorSegment = initColorSegment(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  var area = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  while status.bufStatus[status.currentBuffer].mode == Mode.visual or status.bufStatus[status.currentBuffer].mode == Mode.visualBlock:
    let isBlock = if status.bufStatus[status.currentBuffer].mode == Mode.visualBlock: true else: false

    area.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    colorSegment.updateColorSegment(area)

    status.updatehighlight
    if isBlock: status.bufStatus[status.currentBuffer].highlight.overwriteColorSegmentBlock(area, status.bufStatus[status.currentBuffer].buffer)
    else: status.bufStatus[status.currentBuffer].highlight = status.bufStatus[status.currentBuffer].highlight.overwrite(colorSegment)

    status.update

    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

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
      status.bufStatus[status.currentBuffer].currentLine = area.startLine
      status.changeMode(Mode.insert)
    elif key == ord('I'):
      status.bufStatus[status.currentBuffer].currentLine = area.startLine
      status.bufStatus[status.currentBuffer].currentColumn = 0
      status.changeMode(Mode.insert)

    else:
      if isBlock: discard
      else: visualCommand(status, area, key)
      status.updatehighlight
      status.changeMode(Mode.normal)
