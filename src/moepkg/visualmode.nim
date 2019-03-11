import terminal
import editorstatus, ui, normalmode, highlight, unicodeext

proc initColorSegment(startLine, startColumn: int): ColorSegment =
  result.firstRow = startLine
  result.firstColumn = startColumn
  result.lastRow = startLine
  result.lastColumn = startColumn
  result.color = defaultMagenta

proc updateColorSegment(colorSegment: var ColorSegment, lastLine, lastColumn: int) =
  colorSegment.lastRow = lastLine
  colorSegment.lastColumn = lastColumn

proc visualMode*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())

  var colorSegment = initColorSegment(status.currentLine, status.currentColumn)

  while status.mode == Mode.visual:
    updateColorSegment(colorSegment, status.currentLine, status.currentColumn)
    status.highlight = status.highlight.overwrite(colorSegment)
    status.update

    let key = getKey(status.mainWindow)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      status.changeMode(Mode.normal)

    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      keyLeft(status)
    elif key == ord('l') or isRightKey(key):
      keyRight(status)
    elif key == ord('k') or isUpKey(key):
      keyUp(status)
    elif key == ord('j') or isDownKey(key) or isEnterKey(key):
      keyDown(status)
