import terminal
import editorstatus, ui, normalmode, highlight, unicodeext

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
