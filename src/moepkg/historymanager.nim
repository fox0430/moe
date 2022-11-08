# History manager for automatic backup.

import std/[os, times, terminal, osproc, json, strformat]
import editorstatus, bufferstatus, unicodeext, ui, movement, gapbuffer,
       highlight, color, settings, messages, backup, fileutils, editorview,
       window, commandviewutils

proc initHistoryManagerBuffer(
  bufStatus: var BufferStatus,
  baseBackupDir, sourceFilePath: seq[Rune]) =

    let list = getBackupFiles(baseBackupDir, sourceFilePath)
    if list.len > 0:
      bufStatus.buffer = initGapBuffer[seq[Rune]]()

      for name in list:
        bufStatus.buffer.add(name)

proc initHistoryManagerHighlight(
  bufStatus: BufferStatus,
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

template baseBackupDir(status: EditorStatus): seq[Rune] =
  status.settings.autoBackup.backupDir

template currentLineBuffer(status: EditorStatus): seq[Rune] =
  currentBufStatus.buffer[currentMainWindowNode.currentLine]

# Create an new window and open the diff viewer.
# `sourceFilePath` and `backupFilePath` is need to absolute path.
# Use diff command.
proc openDiffViewer(status: var Editorstatus, sourceFilePath: string) =
  if currentBufStatus.buffer.len == 0 or status.currentLineBuffer.len == 0:
    return

  let
    backupDir = backupDir($status.baseBackupDir, sourceFilePath)
    backupFilePath = backupDir / $status.currentLineBuffer

  if not validateBackupFileName(backupFilePath.splitPath.tail):
    return

  let cmdResult = execCmdEx(fmt"diff -u {sourceFilePath} {backupFilePath}")
  # The diff command return 2 on failure.
  if cmdResult.exitCode == 2:
    # TODO: Write the error message to the command window.
    return

  var buffer: seq[seq[Rune]] = @[ru""]
  for r in ru(cmdResult.output):
    if r == '\n': buffer.add(ru"")
    else: buffer[^1].add(r)

  # Create new window
  status.verticalSplitWindow
  status.resize(terminalHeight(), terminalWidth())
  status.moveNextWindow

  status.addNewBuffer(Mode.diff)
  status.changeCurrentBuffer(status.bufStatus.high)

  currentBufStatus.path = backupFilePath.toRunes
  currentBufStatus.buffer = initGapBuffer(buffer)

# Restore the current buffer from backupFile.
# the filename is the curent line.
proc restoreBackupFile(
  status: var EditorStatus,
  sourceFilePath: seq[Rune],
  isForceRestore: bool) =

    if not fileExists($sourceFilePath): return

    let
      backupFilename = currentBufStatus.buffer[currentMainWindowNode.currentLine]
      baseBackupDir = status.settings.autoBackup.backupDir
      backupDir = getBackupDir(baseBackupDir, sourceFilePath)
      restoreFilePath = $backupDir / $backupFilename

    if not fileExists(restoreFilePath): return

    if not isForceRestore:
      let isRestore = status.commandLine.askBackupRestorePrompt(
        status.messageLog,
        backupFilename)
      if not isRestore: return

    # Backup the current buffer before restore
    for bufStatus in status.bufStatus:
      if bufStatus.absolutePath == sourceFilePath:
        bufStatus.backupBuffer(
          status.settings.autoBackup,
          status.settings.notification,
          status.commandLine,
          status.messageLog)

    try:
      copyFile(restoreFilePath, $sourceFilePath)
    except OSError:
      status.commandLine.writeBackupRestoreError
      return

    # Update restored buffer
    for i in 0 ..< status.bufStatus.len:
      if status.bufStatus[i].absolutePath == sourceFilePath:
        let beforeBufStatus = status.bufStatus[i]

        status.bufStatus[i] = initBufferStatus(sourceFilePath)

        try:
          let textAndEncoding = openFile(sourceFilePath)
          status.bufStatus[i].buffer = textAndEncoding.text.toGapBuffer
          status.bufStatus[i].characterEncoding = textAndEncoding.encoding
        except OSError:
          status.bufStatus[i] = beforeBufStatus
          status.commandLine.writeBackupRestoreError

        status.bufStatus[i].language = detectLanguage($sourceFilePath)

        currentMainWindowNode.view =
          status.bufStatus[i].buffer.initEditorView(1, 1)

        status.resize(terminalHeight(), terminalWidth())

        let settings = status.settings.notification
        status.commandLine.writeRestoreFileSuccessMessage(
          backupFilename,
          settings,
          status.messageLog)

        return

    status.commandLine.writeBackupRestoreError

template restoreBackupFile(
  status: var EditorStatus,
  sourceFilePath: seq[Rune]) =

    const IS_FORCE_RESTORE = false
    status.restoreBackupFile(sourceFilePath, IS_FORCE_RESTORE)

# Remove the backup file.
# the filename is the curent line.
proc removeBackupFile(
  status: var EditorStatus,
  sourceFilePath: seq[Rune],
  isForceRemove: bool) =

    let
      backupFilename = currentBufStatus.buffer[currentMainWindowNode.currentLine]
      baseBackupDir = status.settings.autoBackup.backupDir
      backupDir = backupDir($baseBackupDir, $sourceFilePath)
      backupFilePath = backupDir / $backupFilename

    if not fileExists(backupFilePath): return

    if not isForceRemove:
      let isRemove = status.commandLine.askDeleteBackupPrompt(
        status.messageLog,
        backupFilename)
      if not isRemove: return

    try:
      removeFile(backupFilePath)
    except OSError:
      status.commandLine.writeDeleteBackupError
      return

    let settings = status.settings.notification
    status.commandLine.writeMessageDeletedFile(
      $backupFilename,
      settings,
      status.messageLog)

template removeBackupFile(status: var EditorStatus, sourceFilePath: seq[Rune]) =
  const IS_FORCE_REMOVE = false
  status.removeBackupFile(sourceFilePath, IS_FORCE_REMOVE)

proc historyManager*(status: var EditorStatus) =
  status.resize(terminalHeight(), terminalWidth())

  let sourceFilePath = status.bufStatus[status.prevBufferIndex].absolutePath

  currentBufStatus.initHistoryManagerBuffer(
    status.baseBackupDir,
    sourceFilePath)

  while status.isHistoryManagerMode:
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
      status.openDiffViewer($sourceFilePath)
    elif key == ord('R'):
      status.restoreBackupFile(sourceFilePath)
    elif key == ord('D'):
      status.removeBackupFile(sourceFilePath)
      currentBufStatus.initHistoryManagerBuffer(
        status.baseBackupDir,
        sourceFilePath)
    elif key == ord('r'):
      # Reload backup files
      currentBufStatus.initHistoryManagerBuffer(
        status.baseBackupDir,
        sourceFilePath)
    elif key == ord('g'):
      let secondKey = getKey(currentMainWindowNode)
      if  secondKey == ord('g'):
        currentBufStatus.moveToFirstLine(currentMainWindowNode)
      else: discard
    elif key == ord('G'):
      currentBufStatus.moveToLastLine(currentMainWindowNode)
    else:
      discard
