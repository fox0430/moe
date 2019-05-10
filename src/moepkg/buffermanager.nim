import terminal, os
import gapbuffer, ui, editorstatus, normalmode, unicodeext, highlight

proc initFilelistHighlight[T](buffer: T, currentLine: int): Highlight =
  for i in 0 ..< buffer.len:
    let color = if i == currentLine: Colorpair.brightGreenDefault else: brightWhiteDefault
    result.colorSegments.add(ColorSegment(firstRow: i, firstColumn: 0, lastRow: i, lastColumn: buffer[i].len, color: color))

proc initBufferList(status: var Editorstatus) =
  status.bufStatus[status.currentBuffer].filename = ru"Buffer manager"

  for i in 0 ..< status.bufStatus.high:
    let
      currentMode = status.bufStatus[i].mode
      prevMode = status.bufStatus[i].prevMode
      line = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir().toRunes else: status.bufStatus[i].filename
    if i == 0: status.bufStatus[status.currentBuffer].buffer[0] = line
    else: status.bufStatus[status.currentBuffer].buffer.add(line)

  #status.updateHighlight

proc updateBufferManagerHighlight(status: var Editorstatus) =
  status.bufStatus[status.currentBuffer].highlight = initFilelistHighlight(status.bufStatus[status.currentBuffer].buffer, status.bufStatus[status.currentBuffer].currentLine)

proc openSelectedBuffer(status: var Editorstatus, isNewWindow: bool) =
  if isNewWindow:
    status.splitWindow
    status.moveNextWindow
    status.changeCurrentBuffer(status.bufStatus[status.currentBuffer].currentLine)
  else:
    status.changeCurrentBuffer(status.bufStatus[status.currentBuffer].currentLine)
    status.bufStatus.delete(status.bufStatus.high)

proc bufferManager*(status: var Editorstatus) =
  status.initBufferList
  status.resize(terminalHeight(), terminalWidth())

  while status.bufStatus[status.currentBuffer].mode == Mode.bufManager:
    status.updateBufferManagerHighlight
    status.update
    setCursor(false)
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isControlL(key):
      moveNextWindow(status)
    elif isControlH(key):
      movePrevWindow(status)
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      keyUp(status.bufStatus[status.currentBuffer])
    elif key == ord('j') or isDownKey(key):
      keyDown(status.bufStatus[status.currentBuffer])
    elif isEnterKey(key):
      openSelectedBuffer(status, false)
    elif key == ord('o'):
      openSelectedBuffer(status, true)
