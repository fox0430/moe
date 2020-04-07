import terminal
import gapbuffer, ui, editorstatus, unicodeext, movement

proc setMessageLog*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].filename = ru"Log viewer"
  for i in 0 ..< status.messageLog.len:
    if i == 0: status.bufStatus[currentBufferIndex].buffer[0] = status.messageLog[0]
    else: status.bufStatus[currentBufferIndex].buffer.add(status.messageLog[i])

  status.updateHighlight(currentBufferIndex)

proc exitLogViewer*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.deleteBuffer(currentBufferIndex)

proc messageLogViewer*(status: var Editorstatus) =
  status.addNewBuffer("")
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].mode = Mode.logViewer

  status.setMessageLog
  status.resize(terminalHeight(), terminalWidth())

  while status.bufStatus[currentBufferIndex].mode == Mode.logViewer:
    status.update

    let key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())

    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow

    elif key == ord(':'): status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key): status.bufStatus[currentBufferIndex].keyUp
    elif key == ord('j') or isDownKey(key): status.bufStatus[currentBufferIndex].keyDown
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key): keyLeft(status.bufStatus[currentBufferIndex])
    elif key == ord('l') or isRightKey(key): keyRight(status.bufStatus[currentBufferIndex])
    elif key == ord('0') or isHomeKey(key): moveToFirstOfLine(status.bufStatus[currentBufferIndex])
    elif key == ord('$') or isEndKey(key): moveToLastOfLine(status.bufStatus[currentBufferIndex])
    elif key == ord('q') or isEscKey(key): status.exitLogViewer
    elif key == ord('g'):
      if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == 'g': status.moveToFirstLine
    elif key == ord('G'): status.moveToLastLine
