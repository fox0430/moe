# History manager for automatic backup.

import re, os, times, terminal, osproc
import editorstatus, bufferstatus, unicodeext, ui, movement, gapbuffer,
       highlight, color

proc generateFilenamePatern(path: seq[Rune]): seq[Rune] =
  let splitPath = splitPath($path)
  result = splitPath.tail.toRunes
  let dotPosi = result.rfind(ru".")
  if dotPosi > 0:
    result = result[0 ..< dotPosi] &
             ru"_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}:[0-9]{2}" &
             result[dotPosi .. ^1]
  else:
    result &= ru"_[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}:[0-9]{2}" 

proc getBackupFiles(path: seq[Rune]): seq[seq[Rune]] =
  let
    splitPath = splitPath($path)
    patern = generateFilenamePatern(splitPath.tail.toRunes)
  for kind, path in walkDir(splitPath.head / ".history"):
    if kind == PathComponent.pcFile:
      let splitPath = path.splitPath
      if splitPath.tail.match(re($patern)):
        let splitPath = splitPath(path)
        result.add(splitPath.tail.toRunes)

proc generateBackUpFilePath(path: seq[Rune]): seq[Rune] =
  if path.len == 0: return

  let slashPosition = path.rfind(ru"/")
  if  slashPosition > 0:
    result = path[0 ..< slashPosition] /
             ru".history" /
             path[slashPosition + 1 ..< ^1]
  else:
    result = ru".history" / path

proc initHistoryManagerBuffer(status: var Editorstatus, sourcePath: seq[Rune]) =
  let
    bufferIndex = status.bufferIndexInCurrentWindow
    path = sourcePath
    list = getBackupFiles(path)

  if list.len == 0: return 

  status.bufStatus[bufferIndex].buffer = initGapBuffer[seq[Rune]]()

  for name in list:
    status.bufStatus[bufferIndex].buffer.add(name)

proc isHistoryManagerMode(status: var Editorstatus): bool =
  let index = status.bufferIndexInCurrentWindow
  status.bufStatus[index].mode == Mode.history

proc openDiffViewer(status: var Editorstatus, path: seq[Rune]) =
  let
    workspaceIndex = status.currentWorkSpaceIndex
    currentLine = status.workSpace[workspaceIndex].currentMainWindowNode.currentLine
    bufferIndex = status.bufferIndexInCurrentWindow

  if status.bufStatus[bufferIndex].buffer.len == 0 or
     status.bufStatus[bufferIndex].buffer[currentLine].len == 0: return

  # Setup backup file path and excute diff command
  let
    backupFilename = status.bufStatus[bufferIndex].buffer[currentLine]
    backupPath = generateBackUpFilePath(backupFilename)
    cmdOut = execCmdEx("diff -u " & $path & " " & $backupPath)
  var buffer: seq[seq[Rune]] = @[ru""]
  for r in toRunes(cmdOut.output):
    if r == '\n': buffer.add(ru"")
    else: buffer[^1].add(r)

  # Create new window
  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer("")
  status.changeCurrentBuffer(status.bufStatus.high)
  status.changeMode(Mode.diff)

  status.bufStatus[status.bufStatus.high].buffer = initGapBuffer(buffer)

proc historyManager*(status: var EditorStatus) =
  let
    bufferIndex = status.bufferIndexInCurrentWindow
    sourcePath = status.bufStatus[status.prevBufferIndex].path
    workspaceIndex = status.currentWorkSpaceIndex

  status.initHistoryManagerBuffer(sourcePath)

  while status.isHistoryManagerMode:

    status.update
    setCursor(false)

    var key: Rune = ru'\0'
    while key == ru'\0':
      status.eventLoopTask
      key = getKey(status.workSpace[workspaceIndex].currentMainWindowNode.window)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
      status.commandWindow.erase
    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      status.bufStatus[bufferIndex].keyUp(status.workSpace[workspaceIndex].currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      status.bufStatus[bufferIndex].keyDown(status.workSpace[workspaceIndex].currentMainWindowNode)
    elif isEnterKey(key):
      status.openDiffViewer(sourcePath)
