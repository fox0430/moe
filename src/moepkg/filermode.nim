import std/[os, terminal, options]
import editorstatus, ui, window, bufferstatus, unicodeext, filerutils, messages,
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

proc currentPathInfo(
  status: EditorStatus,
  filerStatus: FilerStatus): PathInfo {.inline.} =
    filerStatus.pathList[currentMainWindowNode.currentLine]

# NOTE: WIP
proc execFilerModeCommand*(status: var EditorStatus, command: Runes) =
  let key = command[0]

  if key == ord(':'):
    status.changeMode(Mode.ex)
  elif key == ord('/'):
    const prompt = "/"
    if status.commandLine.getKeys(prompt):
      let keyword = status.commandLine.buffer
      currentBufStatus.searchFileMode(currentMainWindowNode, filerStatus.get, keyword)
  elif isEscKey(key):
    if filerStatus.get.searchMode == true:
      filerStatus.get.dirlistUpdate = true
      filerStatus.get.searchMode = false
  elif key == ord('D'):
    let r = deleteFile(status.currentPathInfo(filerStatus.get))
    if r.ok: status.commandLine.write(r.mess)
    else: status.commandLine.write(r.mess)
    status.messageLog.add r.mess
  elif key == ord('i'):
    currentBufStatus.writeFileDetail(
      currentMainWindowNode,
      status.settings,
      filerStatus.get.pathList.len,
      filerStatus.get.pathList[currentMainWindowNode.currentLine][1],
      terminalHeight(),
      terminalWidth())
    filerStatus.get.viewUpdate = true
  elif key == 'j' or isDownKey(key):
    filerStatus.get.keyDown(currentMainWindowNode.currentLine)
  elif key == ord('k') or isUpKey(key):
    filerStatus.get.keyUp(currentMainWindowNode.currentLine)
  elif key == ord('g'):
    filerStatus.get.moveToTopOfList(currentMainWindowNode.currentLine)
  elif key == ord('G'):
    filerStatus.get.moveToLastOfList(currentMainWindowNode.currentLine)
  elif key == ord('y'):
    filerStatus.get.copyFile(
      currentMainWindowNode.currentLine,
      currentBufStatus.path)
  elif key == ord('C'):
    filerStatus.get.cutFile(
      currentMainWindowNode.currentLine,
      currentBufStatus.path)
  elif key == ord('p'):
    status.commandLine.pasteFile(
      filerStatus.get,
      currentBufStatus.path,
      status.messageLog)
  elif key == ord('s'):
    filerStatus.get.changeSortBy
  elif key == ord('N'):
    let err = status.commandLine.createDir
    if err.len > 0:
      status.commandLine.writeError(err)
      status.messageLog.add err
  elif key == ord('v'):
    status.openNewWinAndOpenFilerOrDir(
      filerStatus.get,
      terminalHeight(),
      terminalWidth())
  elif isControlJ(key):
    status.movePrevWindow
  elif isControlK(key):
    status.moveNextWindow
  elif isEnterKey(key):
    status.bufStatus.openFileOrDir(
      currentMainWindowNode,
      filerStatus.get)
