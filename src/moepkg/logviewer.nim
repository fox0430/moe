import std/[terminal, times]
import ui, editorstatus, unicodeext, movement, bufferstatus, window

proc exitLogViewer*(status: var Editorstatus, height, width: int) {.inline.} =
  status.deleteBuffer(status.bufferIndexInCurrentWindow, height, width)

proc messageLogViewer*(status: var Editorstatus) =
  currentBufStatus.path = ru"Log viewer"

  status.resize(terminalHeight(), terminalWidth())
  status.update

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  while isLogViewerMode(currentBufStatus.mode) and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    status.update

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())

    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key):
      status.bufStatus[currentBufferIndex].keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[currentBufferIndex].keyDown(currentMainWindowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      currentMainWindowNode.keyLeft
    elif key == ord('l') or isRightKey(key):
      currentBufStatus.keyRight(currentMainWindowNode)
    elif key == ord('0') or isHomeKey(key):
      currentMainWindowNode.moveToFirstOfLine
    elif key == ord('$') or isEndKey(key):
      currentBufStatus.moveToLastOfLine(currentMainWindowNode)
    elif key == ord('q') or isEscKey(key):
      status.exitLogViewer(terminalHeight(), terminalWidth())
    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if secondKey == 'g': currentBufStatus.moveToFirstLine(currentMainWindowNode)
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
