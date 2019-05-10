import terminal, os
import gapbuffer, ui, editorstatus, normalmode, unicodeext

proc initBufferList(status: var Editorstatus) =
  status.bufStatus[status.currentBuffer].filename = ru"Buffer manager"

  for i in 0 ..< status.bufStatus.high:
    let
      currentMode = status.bufStatus[i].mode
      prevMode = status.bufStatus[i].prevMode
      line = if (currentMode == Mode.filer) or (prevMode == Mode.filer and currentMode == Mode.ex): getCurrentDir().toRunes else: status.bufStatus[i].filename
    if i == 0: status.bufStatus[status.currentBuffer].buffer[0] = line
    else: status.bufStatus[status.currentBuffer].buffer.add(line)

  status.updateHighlight

proc bufferManager*(status: var Editorstatus) =
  status.initBufferList
  status.resize(terminalHeight(), terminalWidth())

  while status.bufStatus[status.currentBuffer].mode == Mode.bufManager:
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
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      keyUp(status.bufStatus[status.currentBuffer])
    elif key == ord('j') or isDownKey(key) or isEnterKey(key):
      keyDown(status.bufStatus[status.currentBuffer])
