# History manager for automatic backup.

import re, os, times, terminal, osproc
import editorstatus, bufferstatus, unicodetext, ui, movement, gapbuffer,
       highlight, color, settings, messages, backup, commandview, fileutils,
       editorview, window

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

proc getBackupFiles(path: seq[Rune],
                    settings: AutoBackupSettings): seq[seq[Rune]] =

  let
    splitPath = splitPath($path)
    patern = generateFilenamePatern(splitPath.tail.toRunes)
    backupPath = if settings.backupDir.len > 0: $settings.backupDir
                 else: splitPath.head / ".history"
  for kind, path in walkDir(backupPath):
    if kind == PathComponent.pcFile:
      let splitPath = path.splitPath
      if splitPath.tail.match(re($patern)):
        let splitPath = splitPath(path)
        result.add(splitPath.tail.toRunes)

proc generateBackUpFilePath(originalFilePath, backupFileName: seq[Rune],
                            settings: AutoBackupSettings): seq[Rune] =

  if backupFileName.len == 0: return

  let slashPosition = originalFilePath.rfind(ru"/")

  if settings.backupDir.len > 0:
    if not dirExists($settings.backupDir): return ru""
    if slashPosition > 0:
      result = backupFileName[0 ..< slashPosition] /
               settings.backupDir /
               backupFileName[slashPosition + 1 ..< ^1]
    else:
      result = settings.backupDir / backupFileName
  else:
    if slashPosition > 0:
      let pathSplit = splitPath($originalFilePath)
      result = pathSplit.head.ru /
               ru".history" /
               backupFileName
    else:
      result = ru".history" / backupFileName

proc initHistoryManagerBuffer(status: var Editorstatus, sourcePath: seq[Rune]) =
  let list = getBackupFiles(sourcePath, status.settings.autoBackupSettings)

  if list.len == 0: return

  currentBufStatus.buffer = initGapBuffer[seq[Rune]]()

  for name in list:
    currentBufStatus.buffer.add(name)

proc initHistoryManagerHighlight(bufStatus: BufferStatus,
                                 currentLine: int): Highlight =

  for i in 0 ..< bufStatus.buffer.len:
    let
      line = bufStatus.buffer[i]
      color = if i == currentLine: EditorColorPair.currentHistory
              else: EditorColorPair.defaultChar

    result.colorSegments.add(ColorSegment(
      firstRow: i,
      firstColumn: 0,
      lastRow: i,
      lastColumn: line.high,
      color: color))

proc isHistoryManagerMode(status: var Editorstatus): bool =
  let index = status.bufferIndexInCurrentWindow
  status.bufStatus[index].mode == Mode.history

proc openDiffViewer(status: var Editorstatus, path: seq[Rune]) =
  if currentBufStatus.buffer.len == 0 or
     currentBufStatus.buffer[currentMainWindowNode.currentLine].len == 0: return

  # Setup backup file path and excute diff command
  let
    backupFilename = currentBufStatus.buffer[currentMainWindowNode.currentLine]
    settings = status.settings.autoBackupSettings
    backupPath = generateBackUpFilePath(path, backupFilename, settings)
    cmdOut = execCmdEx("diff -u " & $path & " " & $backupPath)
  var buffer: seq[seq[Rune]] = @[ru""]
  for r in ru(cmdOut.output):
    if r == '\n': buffer.add(ru"")
    else: buffer[^1].add(r)

  # Create new window
  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer(Mode.diff)
  status.changeCurrentBuffer(status.bufStatus.high)

  currentBufStatus.path = backupPath
  currentBufStatus.buffer = initGapBuffer(buffer)

proc getBackupDir(sourcePath: seq[Rune],
                  settings: AutoBackupSettings): seq[Rune] =

  if settings.backupDir.len > 0:
    result = settings.backupDir
  else:
    let slashPosition = sourcePath.rfind(ru"/")
    if slashPosition > 0:
      result = sourcePath[0 ..< slashPosition] / ru".history"
    else:
      result = getCurrentDir().ru / ru".history"

proc restoreBackupFile(status: var EditorStatus, sourcePath: seq[Rune]) =
  let
    backupFilename = currentBufStatus.buffer[currentMainWindowNode.currentLine]
    backupDir = getBackupDir(sourcePath, status.settings.autoBackupSettings)
    backupFilePath = backupDir / backupFilename

  let isRestore = status.commandLine.askBackupRestorePrompt(
    status.messageLog,
    backupFilename)
  if not isRestore: return

  # Backup files before restore
  currentBufStatus.backupBuffer(currentBufStatus.characterEncoding,
                                status.settings.autoBackupSettings,
                                status.settings.notificationSettings,
                                status.commandLine,
                                status.messageLog)

  try:
    copyFile($backupFilePath, $sourcePath)
  except OSError:
    status.commandLine.writeBackupRestoreError
    return

  # Update restored buffer
  for i in 0 ..< status.bufStatus.len:
    if status.bufStatus[i].path == sourcePath:
      let lang = status.bufStatus[i].language
      status.bufStatus[i] = BufferStatus(path: sourcePath,
                                         mode: Mode.normal,
                                         language: lang,
                                         lastSaveTime: now())
      let textAndEncoding = openFile(sourcePath)
      status.bufStatus[i].buffer = textAndEncoding.text.toGapBuffer
      status.bufStatus[i].characterEncoding = textAndEncoding.encoding

      currentMainWindowNode.view =
        status.bufStatus[i].buffer.initEditorView(terminalHeight(),
                                                  terminalWidth())

  status.resize(terminalHeight(), terminalWidth())

  let settings = status.settings.notificationSettings
  status.commandLine.writeRestoreFileSuccessMessage(backupFilename,
                                                    settings,
                                                    status.messageLog)

proc deleteBackupFiles(status: var EditorStatus, sourcePath: seq[Rune]) =
  let
    backupFilename = currentBufStatus.buffer[currentMainWindowNode.currentLine]
    backupDir = getBackupDir(sourcePath, status.settings.autoBackupSettings)
    backupFilePath = backupDir / backupFilename

  let isDelete = status.commandLine.askDeleteBackupPrompt(
    status.messageLog,
    backupFilename)

  if not isDelete: return

  try:
    removeFile($backupFilePath)
  except OSError:
    status.commandLine.writeDeleteBackupError
    return

  let settings = status.settings.notificationSettings
  status.commandLine.writeMessageDeletedFile($backupFilename,
                                             settings,
                                             status.messageLog)

proc historyManager*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())

  # BufferStatus.path is the path of the backup source file
  if currentBufStatus.path.len == 0:
    currentBufStatus.path = status.bufStatus[status.prevBufferIndex].path

  status.initHistoryManagerBuffer(currentBufStatus.path)

  while status.isHistoryManagerMode:
    let sourcePath = currentBufStatus.path

    block:
      let
        currentLine = currentMainWindowNode.currentLine
        highlight = currentBufStatus.initHistoryManagerHighlight(currentLine)
      currentMainWindowNode.highlight = highlight

    status.update
    setCursor(false)

    var key = errorKey
    while key == errorKey:
      status.eventLoopTask
      key = getKey(currentMainWindowNode)

    status.lastOperatingTime = now()

    if isResizekey(key):
      status.resize(terminalHeight(), terminalWidth())
    elif isControlK(key):
      status.moveNextWindow
    elif isControlJ(key):
      status.movePrevWindow
    elif key == ord(':'):
      status.changeMode(Mode.ex)
    elif key == ord('k') or isUpKey(key):
      currentBufStatus.keyUp(currentMainWindowNode)
    elif key == ord('j') or isDownKey(key):
      currentBufStatus.keyDown(currentMainWindowNode)
    elif isEnterKey(key):
      status.openDiffViewer(sourcePath)
    elif key == ord('R'):
      status.restoreBackupFile(sourcePath)
    elif key == ord('D'):
      status.deleteBackupFiles(sourcePath)
      status.initHistoryManagerBuffer(sourcePath)
    elif key == ord('r'):
      # Reload backup files
      status.initHistoryManagerBuffer(sourcePath)
    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if  secondKey == ord('g'): status.moveToFirstLine
      else: discard
    elif key == ord('G'):
      status.moveToLastLine
    else:
      discard
