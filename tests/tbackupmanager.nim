import std/[unittest, oids, os, json, strformat]
import moepkg/[unicodeext, editorstatus, bufferstatus, backup, gapbuffer]

import moepkg/backupmanager {.all.}

template writeBackupInfoJson(backupDir, sourceFilePath: string) =
  let jsonNode = %* { "path": sourceFilePath }
  writeFile(backupDir / "backup.json", $jsonNode)

template addBackupManagerBuffer(status: var EditorStatus) =
    status.addNewBufferInCurrentWin(Mode.backup)
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.initBackupManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes)

suite "Backup Manager: initbackupManagerBuffer":
  let
    baseBackupDir = getCurrentDir() / "baseBackupDirForTest"
    backupDir = baseBackupDir / $genOid()
    sourceFilePath = fmt"{getCurrentDir()}/{$genOid()}.txt"

  setup:
    os.createDir(baseBackupDir)
    os.createDir(backupDir)

  teardown:
    removeDir(baseBackupDir)
    if fileExists(sourceFilePath):
      removeFile(sourceFilePath)

  test "initBackupManagerBuffer":
    var status = initEditorStatus()
    status.addNewBufferInCurrentWin

    status.addNewBufferInCurrentWin(Mode.backup)
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.initBackupManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes)

    check currentBufStatus.buffer.toRunes == ru""

  test "initBackupManagerBuffer 2":
    writeFile(sourceFilePath, "test")

    writeBackupInfoJson(backupDir, sourceFilePath)

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin(sourceFilePath)
    status.settings.autoBackup.backupDir = baseBackupDir.toRunes

    currentBufStatus.backupBuffer(
      status.settings.autoBackup,
      status.settings.notification,
      status.commandLine,
      status.messageLog)

    status.addNewBufferInCurrentWin(Mode.backup)
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.initBackupManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes)

    removeFile(sourceFilePath)

    check currentBufStatus.buffer.len == 1

    let backupFilename = $currentBufStatus.buffer[0]
    check validateBackupFileName(backupFilename)

suite "Backup Manager: openDiffViewer":
  let
    baseBackupDir = getCurrentDir() / "baseBackupDirForTest"
    backupDir = baseBackupDir / $genOid()
    sourceFilePath = fmt"{getCurrentDir()}/{$genOid()}.txt"

  setup:
    os.createDir(baseBackupDir)
    os.createDir(backupDir)

  teardown:
    removeDir(baseBackupDir)
    if fileExists(sourceFilePath):
      removeFile(sourceFilePath)

  test "openDiffViewer":
    writeFile(sourceFilePath, "test\n")

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin(sourceFilePath)
    status.settings.autoBackup.backupDir = baseBackupDir.toRunes

    currentBufStatus.backupBuffer(
      status.settings.autoBackup,
      status.settings.notification,
      status.commandLine,
      status.messageLog)

    # Update the source file.
    writeFile(sourceFilePath, "test2\n")

    status.addBackupManagerBuffer

    status.openDiffViewer(sourceFilePath)

    check status.bufStatus.len == 3
    check currentBufStatus.mode == Mode.diff

suite "Backup Manager: restoreBackupFile":
  let
    baseBackupDir = getCurrentDir() / "baseBackupDirForTest"
    backupDir = baseBackupDir / $genOid()
    sourceFilePath = fmt"{getCurrentDir()}/{$genOid()}.txt"

  setup:
    os.createDir(baseBackupDir)
    os.createDir(backupDir)

  teardown:
    removeDir(baseBackupDir)
    if fileExists(sourceFilePath):
      removeFile(sourceFilePath)

  test "restoreBackupFile":
    writeFile(sourceFilePath, "test\n")

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin(sourceFilePath)
    status.settings.autoBackup.backupDir = baseBackupDir.toRunes

    currentBufStatus.backupBuffer(
      status.settings.autoBackup,
      status.settings.notification,
      status.commandLine,
      status.messageLog)

    # Update the source file.
    writeFile(sourceFilePath, "test2\n")

    status.addBackupManagerBuffer

    const IS_FORCE_RESTORE = true
    status.restoreBackupFile(sourceFilePath.toRunes, IS_FORCE_RESTORE)

    check readFile(sourceFilePath) == "test\n"

    removeFile(sourceFilePath)

suite "Backup Manager: removeBackupFile":
  let
    baseBackupDir = getCurrentDir() / "baseBackupDirForTest"
    backupDir = baseBackupDir / $genOid()
    sourceFilePath = fmt"{getCurrentDir()}/{$genOid()}.txt"

  setup:
    os.createDir(baseBackupDir)
    os.createDir(backupDir)

  teardown:
    removeDir(baseBackupDir)
    if fileExists(sourceFilePath):
      removeFile(sourceFilePath)

  test "removeBackupFile":
    writeFile(sourceFilePath, "test\n")

    var status = initEditorStatus()
    status.addNewBufferInCurrentWin(sourceFilePath)
    status.settings.autoBackup.backupDir = baseBackupDir.toRunes

    currentBufStatus.backupBuffer(
      status.settings.autoBackup,
      status.settings.notification,
      status.commandLine,
      status.messageLog)

    status.addBackupManagerBuffer

    const IS_FORCE_REMOVE = true
    status.removeBackupFile(sourceFilePath.toRunes, IS_FORCE_REMOVE)

    check getBackupFiles(status.baseBackupDir, sourceFilePath.toRunes).len == 0
