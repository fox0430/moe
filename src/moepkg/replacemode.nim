import terminal
import editorstatus, ui, unicodeext, movement, editor, bufferstatus, gapbuffer

proc isReplaceMode(status: EditorStatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    bufferIndex = status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
  result = status.bufStatus[bufferIndex].mode == Mode.replace

proc replaceMode*(status: var EditorStatus) =
  var
    bufferChanged = false
    windowNode =
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

  template replaceCurrentCharacter() =
    let
      workspaceIndex = status.currentWorkSpaceIndex
      windowNode = status.workSpace[workSpaceIndex].currentMainWindowNode
      buffer = status.bufStatus[currentBufferIndex].buffer

    if windowNode.currentColumn < buffer[windowNode.currentLine].len:
      status.bufStatus[currentBufferIndex].replaceCurrentCharacter(
        status.workSpace[workspaceIndex].currentMainWindowNode,
        status.settings.autoIndent, status.settings.autoDeleteParen, key)

  while status.isReplaceMode:
    let currentBufferIndex = status.bufferIndexInCurrentWindow

    if bufferChanged:
      status.updatehighlight(status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode)
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
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif isLeftKey(key) or isBackspaceKey(key):
      windowNode.keyLeft
    elif isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif isDownKey(key) or isEnterKey(key):
      status.bufStatus[currentBufferIndex].keyDown(windowNode)
 
    else:
      replaceCurrentCharacter()

      status.bufStatus[currentBufferIndex].keyRight(windowNode)
      bufferChanged = true
