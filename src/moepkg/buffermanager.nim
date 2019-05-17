import terminal, os
import gapbuffer, ui, editorstatus, normalmode, unicodeext, highlight

proc initFilelistHighlight[T](buffer: T, currentLine: int): Highlight =
  for i in 0 ..< buffer.len:
    let color = if i == currentLine: EditorColorPair.currentLineNum else: EditorColorPair.defaultChar
    result.colorSegments.add(ColorSegment(firstRow: i, firstColumn: 0, lastRow: i, lastColumn: buffer[i].len, color: color))

proc setBufferList(status: var Editorstatus) =
  status.bufStatus[status.currentBuffer].filename = ru"Buffer manager"
  status.bufStatus[status.currentBuffer].buffer = initGapBuffer[seq[Rune]]()

  for i in 0 ..< status.bufStatus.len:
    let currentMode = status.bufStatus[i].mode
    if currentMode != Mode.bufManager:
      let
        prevMode = status.bufStatus[i].prevMode
        line = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir().toRunes else: status.bufStatus[i].filename
      status.bufStatus[status.currentBuffer].buffer.add(line)

proc updateBufferManagerHighlight(status: var Editorstatus) =
  let index = status.currentBuffer
  status.bufStatus[index].highlight = initFilelistHighlight(status.bufStatus[index].buffer, status.bufStatus[index].currentLine)

proc deleteSelectedBuffer(status: var Editorstatus) =
  let deleteIndex = status.bufStatus[status.currentBuffer].currentLine
  for i in 0 ..< status.mainWindowInfo.high:
    if status.mainWindowInfo[i].bufferIndex == deleteIndex: status.closeWindow(i)

  if status.mainWindowInfo.len > 0:
    status.bufStatus.delete(deleteIndex)
    for i in 0 ..< status.mainWindowInfo.len:
      if status.mainWindowInfo[i].bufferIndex > deleteIndex: dec(status.mainWindowInfo[i].bufferIndex)

    if status.currentBuffer > deleteIndex: dec(status.currentBuffer)
    if status.bufStatus[status.currentBuffer].currentLine > 0: dec(status.bufStatus[status.currentBuffer].currentLine)
    status.currentMainWindow = status.mainWindowInfo.high
    status.setBufferList
    status.resize(terminalHeight(), terminalWidth())
  
proc openSelectedBuffer(status: var Editorstatus, isNewWindow: bool) =
  if isNewWindow:
    status.splitWindow
    status.moveNextWindow
    status.changeCurrentBuffer(status.bufStatus[status.currentBuffer].currentLine)
  else:
    status.changeCurrentBuffer(status.bufStatus[status.currentBuffer].currentLine)
    status.bufStatus.delete(status.bufStatus.high)

proc bufferManager*(status: var Editorstatus) =
  status.setBufferList
  status.resize(terminalHeight(), terminalWidth())

  while status.bufStatus[status.currentBuffer].mode == Mode.bufManager:
    status.updateBufferManagerHighlight
    status.update
    setCursor(false)
    let key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif isControlL(key): status.moveNextWindow
    elif isControlH(key): status.movePrevWindow
    elif key == ord(':'): status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key): status.bufStatus[status.currentBuffer].keyUp
    elif key == ord('j') or isDownKey(key): status.bufStatus[status.currentBuffer].keyDown
    elif isEnterKey(key): status.openSelectedBuffer(false)
    elif key == ord('o'): status.openSelectedBuffer(true)
    elif key == ord('D'): status.deleteSelectedBuffer

    if status.bufStatus.len < 2: exitEditor(status.settings)
