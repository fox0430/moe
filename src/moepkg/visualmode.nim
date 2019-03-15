import terminal
import editorstatus, ui, gapbuffer, normalmode, highlight, unicodeext

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
 
proc visualCommand(status: var EditorStatus, area: var SelectArea, key: Rune) =
  area.swapSlectArea

  if key == ord('y') or isDcKey(key):
    yankBuffer(status, area)
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

    else:
      visualCommand(status, area, key)
      status.updatehighlight
      status.changeMode(Mode.normal)
