import terminal
import editorstatus, ui, normalmode, highlight, unicodeext

proc replaceMode*(status: var EditorStatus) =

  var bufferChanged = false

  while status.bufStatus[status.currentBuffer].mode == Mode.replace:
    if bufferChanged:
      status.updateHighlight
      bufferChanged = false

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key = getKey(status.mainWindowInfo[status.currentMainWindow].window)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key):
      status.changeMode(Mode.normal)

    elif isRightKey(key):
      keyRight(status.bufStatus[status.currentBuffer])
    elif isLeftKey(key) or isBackspaceKey(key):
      keyLeft(status.bufStatus[status.currentBuffer])
    elif isUpKey(key):
      keyUp(status.bufStatus[status.currentBuffer])
    elif isDownKey(key) or isEnterKey(key):
      keyDown(status.bufStatus[status.currentBuffer])
 
    else:
      replaceCurrentCharacter(status.bufStatus[status.currentBuffer], status.settings.autoIndent, key)
      keyRight(status.bufStatus[status.currentBuffer])
      bufferChanged = true
