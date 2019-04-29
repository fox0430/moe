import terminal
import editorstatus, ui, normalmode, highlight

proc replaceMode*(status: var EditorStatus) =

  var bufferChanged = false

  while status.bufStatus[status.currentBuffer].mode == Mode.replace:
    if bufferChanged:
      status.updateHighlight
      bufferChanged = false

    status.update

    let key = getkey(status.mainWindowInfo[status.currentMainWindow].window)
    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      status.changeMode(Mode.normal)

    elif isRightKey(key):
      keyRight(status)
    elif isLeftKey(key) or isBackspaceKey(key):
      keyLeft(status)
    elif isUpKey(key):
      keyUp(status)
    elif isDownKey(key) or isEnterKey(key):
      keyDown(status)
 
    else:
      replaceCurrentCharacter(status, key)
      keyRight(status)
      bufferChanged = true
