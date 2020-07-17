import terminal, times
import ui, editorstatus, unicodeext, movement, bufferstatus

proc initMessageLog*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].filename = ru"Log viewer"

proc exitLogViewer*(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.deleteBuffer(currentBufferIndex)

proc isLogViewerMode(status: Editorstatus): bool =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    bufferIndex =
      status.workspace[workspaceIndex].currentMainWindowNode.bufferIndex
  status.bufStatus[bufferIndex].mode == Mode.logViewer

proc messageLogViewer*(status: var Editorstatus) =
  status.initMessageLog
  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  while status.isLogViewerMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    let currentBufferIndex = status.bufferIndexInCurrentWindow
    
    status.update

    var windowNode =
      status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase

    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow

    elif key == ord(':'): status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(windowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      windowNode.keyLeft
    elif key == ord('l') or isRightKey(key):
      status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif key == ord('0') or isHomeKey(key):
      windowNode.moveToFirstOfLine
    elif key == ord('$') or isEndKey(key):
      status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
    elif key == ord('q') or isEscKey(key):
      status.exitLogViewer
    elif key == ord('g'):
      if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == 'g':
        status.moveToFirstLine
    elif key == ord('G'): status.moveToLastLine
