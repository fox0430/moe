import ui, unicodeext, window, bufferstatus, movement, commandline

proc isDebugModeCommand*(command: Runes): InputState =
  result = InputState.Invalid

  if command.len == 1:
    let key = command[0]
    if key == ord(':') or
       isControlK(key) or
       isControlJ(key) or
       key == ord('k') or isUpKey(key) or
       key == ord('j') or isDownKey(key) or
       key == ord('g') or
       key == ord('G'):
         return InputState.Valid
    elif key == ord('g'):
      return InputState.Continue
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        return InputState.Valid

proc changeModeToExMode(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine)  =
    bufStatus.changeMode(Mode.ex)
    commandLine.clear
    commandLine.setPrompt(exModePrompt)

# TODO: Resolve the recursive module dependency and move to top.
import editorstatus

proc execDebugModeCommand*(status: var EditorStatus, command: Runes) =
  if command.len == 1:
    let key = command[0]
    if key == ord(':'):
      currentBufStatus.changeModeToExMode(status.commandLine)

    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow

    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)

    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
  elif command.len == 2:
    if command[0] == ord('g'):
      if command[1] == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
