import terminal
import gapbuffer, ui, editorstatus, unicodeext, movement

proc setMessageLog(status: var Editorstatus) =
  status.bufStatus[status.currentBuffer].filename = ru"Buffer manager"
  for i in 0 ..< status.messageLog.len:
    if i == 0: status.bufStatus[status.currentBuffer].buffer[0] = status.messageLog[0]
    else: status.bufStatus[status.currentBuffer].buffer.add(status.messageLog[i])

  status.updateHighlight

proc exitLogViewer(status: var Editorstatus) = status.bufStatus.delete(status.currentBuffer)

proc messageLogViewer*(status: var Editorstatus) =
  status.addNewBuffer("")
  status.bufStatus[status.currentBuffer].mode = Mode.logViewer

  status.setMessageLog
  status.resize(terminalHeight(), terminalWidth())

  while status.bufStatus[status.currentBuffer].mode == Mode.logViewer:
    status.update

    let key = getKey(status.currentMainWindowNode.window)

    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())
    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow
    elif key == ord(':'): status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key): status.bufStatus[status.currentBuffer].keyUp
    elif key == ord('j') or isDownKey(key): status.bufStatus[status.currentBuffer].keyDown
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key): keyLeft(status.bufStatus[status.currentBuffer])
    elif key == ord('l') or isRightKey(key): keyRight(status.bufStatus[status.currentBuffer])
    elif key == ord('0') or isHomeKey(key): moveToFirstOfLine(status.bufStatus[status.currentBuffer])
    elif key == ord('$') or isEndKey(key): moveToLastOfLine(status.bufStatus[status.currentBuffer])
    elif key == ord('q') or isEscKey(key): status.exitLogViewer
