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
        status.registers.yankedStr.add(status.buffer[area.startLine][j])
    if i == area.startLine and area.startColumn > 0:
      status.registers.yankedLines.add(ru"")
      for j in area.startColumn ..< status.buffer[area.startLine].len:
        status.registers.yankedLines[status.registers.yankedLines.high].add(status.buffer[area.startLine][j])
    elif i == area.endLine and area.endColumn < status.buffer[area.endLine].len:
      status.registers.yankedLines.add(ru"")
      for j in 0 .. area.endColumn:
        status.registers.yankedLines[status.registers.yankedLines.high].add(status.buffer[area.endLine][j])
    else:
      status.registers.yankedLines.add(status.buffer[i])

proc deleteBuffer(status: var EditorStatus, area: SelectArea) =
  yankBuffer(status, area)

  for i in area.startLine ..< area.endLine:
    if area.startLine == area.endLine:
      for j in area.startColumn .. area.endColumn:
        status.buffer[area.startLine].delete(area.startColumn)
    elif i == area.startLine and area.startColumn > 0:
      for j in area.startColumn .. status.buffer[area.startLine].high:
        status.buffer[area.startLine].delete(area.startColumn)
    elif i == area.endLine and area.endColumn < status.buffer[area.startLine].high:
      for j in 0 .. area.endColumn:
        status.buffer[area.startLine].delete(0)
    else:
      status.buffer.delete(area.startLine, area.startLine + 1)

  inc(status.countChange)
  status.currentLine = area.startLine
  status.currentColumn = area.startColumn
  status.expandedColumn = area.startColumn

proc addIndent(status: var EditorStatus, area: SelectArea) =
  status.currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    addIndent(status)
    inc(status.currentLine)

  status.currentLine = area.startLine

proc deleteIndent(status: var EditorStatus, area: SelectArea) =
  status.currentLine = area.startLine
  for i in area.startLine .. area.endLine:
    deleteIndent(status)
    inc(status.currentLine)

  status.currentLine = area.startLine

proc visualCommand(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSlectArea

  if key == ord('y') or isDcKey(key):
    yankBuffer(status, area)
  elif key == ord('x') or key == ord('d'):
    deleteBuffer(status, area)
  elif key == ord('>'):
    addIndent(status, area)
  elif key == ord('<'):
    deleteIndent(status, area)
  else:
    discard

proc visualMode*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())

  var colorSegment = initColorSegment(status.currentLine, status.currentColumn)
  var area = initSelectArea(status.currentLine, status.currentColumn)

  while status.mode == Mode.visual:

    area.updateSelectArea(status.currentLine, status.currentColumn)
    colorSegment.updateColorSegment(area)

    status.updatehighlight
    status.highlight = status.highlight.overwrite(colorSegment)
    status.update

    let key = getKey(status.mainWindow)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      status.updatehighlight
      status.changeMode(Mode.normal)

    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      keyLeft(status)
    elif key == ord('l') or isRightKey(key):
      keyRight(status)
    elif key == ord('k') or isUpKey(key):
      keyUp(status)
    elif key == ord('j') or isDownKey(key) or isEnterKey(key):
      keyDown(status)
    elif key == ord('^'):
      moveToFirstNonBlankOfLine(status)
    elif key == ord('0') or isHomeKey(key):
      moveToFirstOfLine(status)
    elif key == ord('$') or isEndKey(key):
      moveToLastOfLine(status)
    elif key == ord('w'):
      moveToForwardWord(status)
    elif key == ord('b'):
      moveToBackwardWord(status)
    elif key == ord('e'):
      moveToForwardEndOfWord(status)
    elif key == ord('G'):
      moveToLastLine(status)
    elif key == ord('g'):
      if getKey(status.mainWindow) == ord('g'): moveToFirstLine(status)
    elif key == ord('i'):
      status.currentLine = area.startLine
      status.changeMode(Mode.insert)
    elif key == ord('I'):
      status.currentLine = area.startLine
      status.currentColumn = 0
      status.changeMode(Mode.insert)

    else:
      visualCommand(status, area, key)
      status.updatehighlight
      status.changeMode(Mode.normal)
