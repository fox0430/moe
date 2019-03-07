import terminal
import editorstatus, ui, normalmode

proc replaceMode*(status: var EditorStatus) =

  while status.mode == Mode.replace:
    status.update

    let key = getkey(status.mainWindow)
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
