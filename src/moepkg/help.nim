import terminal
import editorstatus, bufferstatus, ui, movement, unicodeext, gapbuffer,
       strutils, os

proc staticReadHowToUseDocument: string {.compileTime.} =
  let doc = staticRead(currentSourcePath.parentDir() / "../../documents/howtouse.md")
  result = doc.multiReplace(@[("```", ""), ("  ", "")])

proc initHelpModeBuffer(status: var Editorstatus) =
  let currentBufferIndex = status.bufferIndexInCurrentWindow
  status.bufStatus[currentBufferIndex].path = ru"help"

  var line = ""
  let helpsentences = staticReadHowToUseDocument()
  for ch in helpSentences:
    if ch == '\n':
      status.bufStatus[currentBufferIndex].buffer.add(line.toRunes)
      line = ""
    else: line.add(ch)

proc isHelpMode(status: Editorstatus): bool =
  let
    currentMode = status.bufStatus[status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex].mode
    prevMode = status.bufStatus[status.workspace[status.currentWorkSpaceIndex].currentMainWindowNode.bufferIndex].prevMode
  result = currentMode == Mode.help or (prevMode == Mode.help and currentMode == Mode.ex)

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

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(
        status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window)

    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())

    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow

    elif key == ord(':'): status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key): status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif key == ord('j') or isDownKey(key): status.bufStatus[currentBufferIndex].keyDown(windowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key): windowNode.keyLeft
    elif key == ord('l') or isRightKey(key): status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif key == ord('0') or isHomeKey(key): windowNode.moveToFirstOfLine
    elif key == ord('$') or isEndKey(key): status.bufStatus[currentBufferIndex].moveToLastOfLine(windowNode)
    elif key == ord('g'):
      if getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode.window) == 'g': status.moveToFirstLine
    elif key == ord('G'): status.moveToLastLine
