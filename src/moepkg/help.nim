import editorstatus, bufferstatus, ui, movement, unicodeext, gapbuffer
include helpsentence
import terminal

proc initHelpModeBuffer(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].filename = ru"help"

  var line = ""
  for ch in helpSentences:
    if ch == '\n':
      status.bufStatus[currentBufferIndex].buffer.add(line.toRunes)
      line = ""
    else: line.add(ch)

proc exitHelpMode(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.deleteBuffer(currentBufferIndex)

proc isHelpMode(status: Editorstatus): bool = status.bufStatus[status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex].mode == Mode.help

proc helpMode*(status: var Editorstatus) =
  status.initHelpModeBuffer
  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  while status.isHelpMode and currentWorkSpace == status.currentWorkSpaceIndex and currentBufferIndex == status.bufferIndexInCurrentWindow:
    let currentBufferIndex = status.bufferIndexInCurrentWindow

    status.update

    var windowNode = status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode

    let key = getKey(windowNode.window)

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase

    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow

    elif key == ord(':'): status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key): status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif key == ord('j') or isDownKey(key): status.bufStatus[currentBufferIndex].keyDown(windowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key): windowNode.keyLeft
    elif key == ord('l') or isRightKey(key): status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif key == ord('0') or isHomeKey(key): windowNode.moveToFirstOfLine
    elif key == ord('$') or isEndKey(key): status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
    elif key == ord('q') or isEscKey(key): status.exitHelpMode
    elif key == ord('g'):
      if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == 'g': status.moveToFirstLine
    elif key == ord('G'): status.moveToLastLine
