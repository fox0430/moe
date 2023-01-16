import ui, editorstatus, unicodeext, movement, bufferstatus, window

proc exitLogViewer*(status: var EditorStatus) {.inline.} =
  status.deleteBuffer(status.bufferIndexInCurrentWindow)

proc isLogViewerCommand*(command: Runes): InputState =
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
       key == ord('0') or isHomeKey(key) or
       key == ord('$') or isEndKey(key) or
       key == ord('q') or isEscKey(key) or
       key == ord('G'):
         return InputState.Valid
    elif key == ord('g'):
      return InputState.Continue
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        return InputState.Valid

proc execLogViewerCommand*(status: var EditorStatus, command: Runes) =
  if command.len == 1:
    let key = command[0]
    if isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif command[0] == ord(':'):
      status.changeMode(Mode.ex)

    elif command[0] == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif command[0] == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif command[0] == ord('q') or isEscKey(key):
      status.exitLogViewer
    elif command[0] == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
