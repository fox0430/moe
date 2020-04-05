import terminal
import editorstatus, ui, normalmode, unicodeext, movement, editor

proc replaceMode*(status: var EditorStatus) =

  var bufferChanged = false

  while status.bufStatus[status.currentBuffer].mode == Mode.replace:
    if bufferChanged:
      status.updateHighlight(status.currentBuffer)
      bufferChanged = false

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key = getKey(status.currentMainWindowNode.window)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isEscKey(key) or isControlSquareBracketsRight(key):
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
      status.bufStatus[status.currentBuffer].replaceCurrentCharacter(status.currentMainWindowNode, status.settings.autoIndent, status.settings.autoDeleteParen, key)
      keyRight(status.bufStatus[status.currentBuffer])
      bufferChanged = true
