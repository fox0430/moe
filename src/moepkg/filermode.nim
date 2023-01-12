import std/[os, terminal, options]
import editorstatus, ui, window, bufferstatus, unicodeext, filermodeutils, messages,
       commandline

proc openNewWinAndOpenFilerOrDir(
  status: var EditorStatus,
  filerStatus: var FilerStatus,
  terminalHeight, terminalWidth: int) =

    let path = filerStatus.pathList[currentMainWindowNode.currentLine].path

    status.verticalSplitWindow
    status.resize(terminalHeight, terminalWidth)
    status.moveNextWindow

    if dirExists($path):
      try:
        setCurrentDir($path)
      except OSError:
        status.commandLine.writeFileOpenError($path, status.messageLog)
        status.bufStatus.add initBufferStatus("")

      status.bufStatus.add initBufferStatus(Mode.filer)
    else:
      status.bufStatus.add initBufferStatus($path)

      status.changeCurrentBuffer(status.bufStatus.high)

proc currentPathInfo(status: EditorStatus,): PathInfo {.inline.} =
  currentFilerStatus.pathList[currentMainWindowNode.currentLine]

proc changeModeToExMode*(
  bufStatus: var BufferStatus,
  commandLine: var CommandLine) =

    bufStatus.changeMode(Mode.ex)
    commandLine.clear
    commandLine.setPrompt(exModePrompt)

# NOTE: WIP
proc execFilerModeCommand*(status: var EditorStatus, command: Runes) =
  let key = command[0]

  if key == ord(':'):
    currentBufStatus.changeModeToExMode(status.commandLine)
  elif key == ord('/'):
    const prompt = "/"
    if status.commandLine.getKeys(prompt):
      let keyword = status.commandLine.buffer
      currentBufStatus.searchFileMode(
        currentMainWindowNode,
        currentFilerStatus,
        keyword)
  elif isEscKey(key):
    if currentFilerStatus.searchMode == true:
      currentFilerStatus.isUpdateView = true
      currentFilerStatus.searchMode = false
  elif key == ord('D'):
    let r = status.currentPathInfo.deleteFile
    if r.ok: status.commandLine.write(r.mess)
    else: status.commandLine.write(r.mess)
    status.messageLog.add r.mess
  elif key == ord('i'):
    currentBufStatus.writeFileDetail(
      currentMainWindowNode,
      status.settings,
      currentFilerStatus.pathList.len,
      currentFilerStatus.pathList[currentMainWindowNode.currentLine][1],
      terminalHeight(),
      terminalWidth())
    currentFilerStatus.isUpdateView = true
  elif key == 'j' or isDownKey(key):
    currentFilerStatus.keyDown(currentMainWindowNode.currentLine)
  elif key == ord('k') or isUpKey(key):
    currentFilerStatus.keyUp(currentMainWindowNode.currentLine)
  elif key == ord('g'):
    currentFilerStatus.moveToTopOfList(currentMainWindowNode.currentLine)
  elif key == ord('G'):
    currentFilerStatus.moveToLastOfList(currentMainWindowNode.currentLine)
  elif key == ord('y'):
    currentFilerStatus.copyFile(
      currentMainWindowNode.currentLine,
      currentBufStatus.path)
  elif key == ord('C'):
    currentFilerStatus.cutFile(
      currentMainWindowNode.currentLine,
      currentBufStatus.path)
  elif key == ord('p'):
    status.commandLine.pasteFile(
      currentFilerStatus,
      currentBufStatus.path,
      status.messageLog)
  elif key == ord('s'):
    currentFilerStatus.changeSortBy
  elif key == ord('N'):
    let err = currentFilerStatus.createDir(status.commandLine)
    if err.len > 0:
      status.commandLine.writeError(err)
      status.messageLog.add err
  elif key == ord('v'):
    status.openNewWinAndOpenFilerOrDir(
      currentFilerStatus,
      terminalHeight(),
      terminalWidth())
  elif isControlJ(key):
    status.movePrevWindow
  elif isControlK(key):
    status.moveNextWindow
  elif isEnterKey(key):
    status.bufStatus.openFileOrDir(
      currentMainWindowNode,
      currentFilerStatus)
