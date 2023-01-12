import std/[os, re]
import editorstatus, ui, unicodeext, bufferstatus, movement, gapbuffer,
       messages, window

proc openSelectedBuffer(status: var Editorstatus) =
  let
    line = currentMainWindowNode.currentLine
    filename = status.bufStatus[currentMainWindowNode.bufferIndex].buffer[line]

  if fileExists($filename):
    status.addNewBufferInCurrentWin($filename)
  else:
    status.commandLine.writeFileNotFoundError(filename, status.messageLog)

proc initRecentFileModeBuffer*(bufStatus: var BufferStatus) =
  var f = open(getHomeDir() / ".local/share/recently-used.xbel")
  let text = f.readAll
  f.close

  let recentUsedFiles = text.findAll(re"""(?<=file://).*?(?=")""")
  for index, str in recentUsedFiles:
    if index == 0: bufStatus.buffer[0] = str.toRunes
    else: bufStatus.buffer.add(str.toRunes)

proc isRecentFileCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if isControlK(key) or
       isControlJ(key) or
       key == ord(':') or
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       key == ord('h') or isLeftKey(key) or isBackspaceKey(key) or
       key == ord('l') or isRightKey(key) or
       key == ord('G') or
       isEnterKey(key):
         return InputState.Valid
    elif key == ord('g'):
      return InputState.Continue
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        return InputState.Valid

proc execRecentFileCommand*(status: var Editorstatus, command: Runes) =
  if command.len == 1:
    let key = command[0]
    if isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord(':'):
      status.changeMode(Mode.ex)

    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif key == ord('h') or isLeftKey(key) or isBackspaceKey(key):
      currentMainWindowNode.keyLeft
    elif key == ord('l') or isRightKey(key):
      currentBufStatus.keyRight(currentMainWindowNode)
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
    elif isEnterKey(key):
      status.openSelectedBuffer
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
