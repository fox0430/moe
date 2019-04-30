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
  result.color = defaultMagenta

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

proc swapSlectArea(area: var SelectArea) =
  if area.startLine == area.endLine:
    if area.endColumn < area.startColumn: swap(area.startColumn, area.endColumn)
  elif area.endLine < area.startLine:
    swap(area.startLine, area.endLine)
    swap(area.startColumn, area.endColumn)

proc yankBuffer(status: var EditorStatus, area: SelectArea) =
  status.registers.yankedLines = @[]
  status.registers.yankedStr = @[]

  for i in area.startLine .. area.endLine:
    if area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn:
        status.registers.yankedStr.add(status.bufStatus[status.currentBuffer].buffer[area.startLine][j])
    if i == area.startLine and area.startColumn > 0:
      status.registers.yankedLines.add(ru"")
      for j in area.startColumn ..< status.bufStatus[status.currentBuffer].buffer[area.startLine].len:
        status.registers.yankedLines[status.registers.yankedLines.high].add(status.bufStatus[status.currentBuffer].buffer[area.startLine][j])
    elif i == area.endLine and area.endColumn < status.bufStatus[status.currentBuffer].buffer[area.endLine].len:
      status.registers.yankedLines.add(ru"")
      for j in 0 .. area.endColumn:
        status.registers.yankedLines[status.registers.yankedLines.high].add(status.bufStatus[status.currentBuffer].buffer[area.endLine][j])
    else:
      status.registers.yankedLines.add(status.bufStatus[status.currentBuffer].buffer[i])

proc deleteBuffer(status: var EditorStatus, area: SelectArea) =
  if status.bufStatus[status.currentBuffer].buffer.len == 1 and status.bufStatus[status.currentBuffer].buffer[status.bufStatus[status.currentBuffer].currentLine].len < 1: return
  yankBuffer(status, area)

  for i in area.startLine .. area.endLine:
    if area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn:
        status.bufStatus[status.currentBuffer].buffer[area.startLine].delete(area.startColumn)
    elif i == area.startLine and area.startColumn > 0:
      for j in area.startColumn .. status.bufStatus[status.currentBuffer].buffer[area.startLine].high:
        status.bufStatus[status.currentBuffer].buffer[area.startLine].delete(area.startColumn)
    elif i == area.endLine and area.endColumn < status.bufStatus[status.currentBuffer].buffer[area.startLine].high:
      for j in 0 .. area.endColumn:
        status.bufStatus[status.currentBuffer].buffer[area.startLine].delete(0)
    elif status.bufStatus[status.currentBuffer].buffer.len == 1 and status.bufStatus[status.currentBuffer].buffer[0].len < 1:
      break
    else:
      status.bufStatus[status.currentBuffer].buffer.delete(area.startLine, area.startLine + 1)

  inc(status.bufStatus[status.currentBuffer].countChange)
  status.bufStatus[status.currentBuffer].currentLine = area.startLine
  status.bufStatus[status.currentBuffer].currentColumn = area.startColumn
  status.bufStatus[status.currentBuffer].expandedColumn = area.startColumn

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

  if key == ord('y') or isDcKey(key): yankBuffer(status, area)
  elif key == ord('x') or key == ord('d'): deleteBuffer(status, area)
  elif key == ord('>'): addIndent(status.bufStatus[status.currentBuffer], area, status.settings.tabStop)
  elif key == ord('<'): deleteIndent(status.bufStatus[status.currentBuffer], area, status.settings.tabStop)
  else: discard

proc visualMode*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())

  var colorSegment = initColorSegment(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
  var area = initSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)

  while status.bufStatus[status.currentBuffer].mode == Mode.visual:

    area.updateSelectArea(status.bufStatus[status.currentBuffer].currentLine, status.bufStatus[status.currentBuffer].currentColumn)
    colorSegment.updateColorSegment(area)

    status.updatehighlight
    status.bufStatus[status.currentBuffer].highlight = status.bufStatus[status.currentBuffer].highlight.overwrite(colorSegment)
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
      visualCommand(status, area, key)
      status.updatehighlight
      status.changeMode(Mode.normal)
