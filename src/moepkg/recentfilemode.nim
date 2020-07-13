import os, re, terminal
import editorstatus, ui, unicodeext, bufferstatus, movement, gapbuffer,
       commandview

proc openSelectedBuffer(status: var Editorstatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    windowNode = status.workspace[workspaceIndex].currentMainWindowNode
    line = windowNode.currentLine
    filename = status.bufStatus[windowNode.bufferIndex].buffer[line]

  if existsFile($filename):
    status.addNewBuffer($filename)
  else:
    status.commandWindow.writeFileNotFoundError(filename, status.messageLog)

proc initRecentFileModeBuffer(bufStatus: var BufferStatus) =
  var f = open(getHomeDir() / ".local/share/recently-used.xbel")
  let text = f.readAll
  f.close

  let recentUsedFiles = text.findAll(re"""(?<=file://).*?(?=")""")
  for index, str in recentUsedFiles:
    if index == 0: bufStatus.buffer[0] = str.toRunes
    else: bufStatus.buffer.add(str.toRunes)

proc isRecentFileMode(bufStatus: BufferStatus): bool =
  result = (bufStatus.mode == Mode.recentFile) or
           (bufStatus.mode == Mode.ex and bufStatus.prevMode == Mode.recentFile)

proc recentFileMode*(status: var Editorstatus) =
  status.resize(terminalHeight(), terminalWidth())

  let
    currentBufferIndex = status.bufferIndexInCurrentWindow
    currentWorkSpace = status.currentWorkSpaceIndex

  status.bufStatus[currentBufferIndex].initRecentFileModeBuffer

  while status.bufStatus[currentBufferIndex].isRecentFileMode and
        currentWorkSpace == status.currentWorkSpaceIndex and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

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
    elif isEnterKey(key): status.openSelectedBuffer

  # Delete buffer of recent used file list
  status.deleteBuffer(currentBufferIndex)
