import terminal
import editorstatus, ui, normalmode, unicodeext, movement, editor

proc replaceMode*(status: var EditorStatus) =

  var bufferChanged = false
  let currentBufferIndex = status.bufferIndexInCurrentWindow

  while status.bufStatus[currentBufferIndex].mode == Mode.replace:
    if bufferChanged:
      status.updateHighlight(currentBufferIndex)
      bufferChanged = false

    status.update

    var key: Rune = Rune('\0')
    while key == Rune('\0'):
      status.eventLoopTask
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isEscKey(key) or isControlSquareBracketsRight(key):
      status.changeMode(Mode.normal)

    elif isRightKey(key):
      keyRight(status.bufStatus[currentBufferIndex])
    elif isLeftKey(key) or isBackspaceKey(key):
      keyLeft(status.bufStatus[currentBufferIndex])
    elif isUpKey(key):
      keyUp(status.bufStatus[currentBufferIndex])
    elif isDownKey(key) or isEnterKey(key):
      keyDown(status.bufStatus[currentBufferIndex])
 
    else:
      status.bufStatus[currentBufferIndex].replaceCurrentCharacter(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode, status.settings.autoIndent, status.settings.autoDeleteParen, key)
      keyRight(status.bufStatus[currentBufferIndex])
      bufferChanged = true
