import std/[terminal, times]
import ui, editorstatus, unicodeext, movement, bufferstatus, window

proc exitLogViewer*(status: var Editorstatus, height, width: int) {.inline.} =
  status.deleteBuffer(status.bufferIndexInCurrentWindow, height, width)

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
      status.exitLogViewer(terminalHeight(), terminalWidth())
    elif command[0] == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)

# TODO: Remove
proc messageLogViewer*(status: var Editorstatus) =
  currentBufStatus.path = ru"Log viewer"

  status.resize
  status.update

  let currentBufferIndex = status.bufferIndexInCurrentWindow

  while isLogViewerMode(currentBufStatus.mode) and
        currentBufferIndex == status.bufferIndexInCurrentWindow:

    status.update

    var key = ERR_KEY
    while key == ERR_KEY:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize

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
