import terminal
import gapbuffer, ui, editorstatus, unicodeext, movement, bufferstatus

proc setMessageLog*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].filename = ru"Log viewer"
  for i in 0 ..< status.messageLog.len:
    if i == 0: status.bufStatus[currentBufferIndex].buffer[0] = status.messageLog[0]
    else: status.bufStatus[currentBufferIndex].buffer.add(status.messageLog[i])

  status.updatehighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)

proc exitLogViewer*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.deleteBuffer(currentBufferIndex)

proc messageLogViewer*(status: var Editorstatus) =
  status.addNewBuffer("")
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].mode = Mode.logViewer

  status.setMessageLog
  status.resize(terminalHeight(), terminalWidth())

  var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  while status.bufStatus[currentBufferIndex].mode == Mode.logViewer:
    status.update

    let key = getKey(windowNode.window)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase

    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow

    elif key == ord(':'): status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key): status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif key == ord('j') or isDownKey(key): status.bufStatus[currentBufferIndex].keyDown(windowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key): windowNode.keyLeft
    elif key == ord('l') or isRightKey(key): status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif key == ord('0') or isHomeKey(key): windowNode.moveToFirstOfLine
    elif key == ord('$') or isEndKey(key): status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
    elif key == ord('q') or isEscKey(key): status.exitLogViewer
    elif key == ord('g'):
      if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == 'g': status.moveToFirstLine
    elif key == ord('G'): status.moveToLastLine
