import os, re, terminal
import editorstatus, ui, unicodetext, bufferstatus, movement, gapbuffer,
       messages, window

proc openSelectedBuffer(status: var Editorstatus) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    windowNode = status.workspace[workspaceIndex].currentMainWindowNode
    line = windowNode.currentLine
    filename = status.bufStatus[windowNode.bufferIndex].buffer[line]

  if fileExists($filename):
    status.addNewBuffer($filename)
  else:
    status.commandLine.writeFileNotFoundError(filename, status.messageLog)

proc initRecentFileModeBuffer(bufStatus: var BufferStatus) =
  var f = open(getHomeDir() / ".local/share/recently-used.xbel")
  let text = f.readAll
  f.close

  let recentUsedFiles = text.findAll(re"""(?<=file://).*?(?=")""")
  for index, str in recentUsedFiles:
    if index == 0: bufStatus.buffer[0] = str.toRunes
    else: bufStatus.buffer.add(str.toRunes)

proc isRecentFileMode(bufStatus: BufferStatus): bool {.inline.} =
  bufStatus.mode == Mode.recentFile

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

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(status.workSpace[status.currentWorkSpaceIndex].currentMainWindowNode)

    if isResizekey(key): status.resize(terminalHeight(), terminalWidth())

    elif isControlK(key): status.moveNextWindow
    elif isControlJ(key): status.movePrevWindow

    elif key == ord(':'): status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key): status.bufStatus[currentBufferIndex].keyUp(windowNode)
    elif key == ord('j') or isDownKey(key): status.bufStatus[currentBufferIndex].keyDown(windowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key): windowNode.keyLeft
    elif key == ord('l') or isRightKey(key): status.bufStatus[currentBufferIndex].keyRight(windowNode)
    elif key == ord('G'): status.moveToLastLine
    elif key == ord('g') and getKey(windowNode) == ord('g'): status.moveToFirstLine
    elif isEnterKey(key): status.openSelectedBuffer
