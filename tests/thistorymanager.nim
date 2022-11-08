import std/[unittest, os, oids, json, strformat]
import moepkg/[unicodeext, settings, editorstatus, backup]
include moepkg/historymanager

template writeBackupInfoJson(backupDir, sourceFilePath: string) =
  let jsonNode = %* { "path": sourceFilePath }
  writeFile(backupDir / "backup.json", $jsonNode)

template addHistoryManagerBuffer(status: var EditorStatus) =
    status.addNewBuffer(Mode.history)
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.initHistoryManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes)

suite "History Manager: initHistoryManagerBuffer":
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

  test "initHistoryManagerBuffer":
    var status = initEditorStatus()
    status.addNewBuffer

    status.addNewBuffer(Mode.history)
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.initHistoryManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes)

    check currentBufStatus.buffer.toRunes == ru""

  test "initHistoryManagerBuffer 2":
    writeFile(sourceFilePath, "test")

    writeBackupInfoJson(backupDir, sourceFilePath)

    var status = initEditorStatus()
    status.addNewBuffer(sourceFilePath)
    status.settings.autoBackup.backupDir = baseBackupDir.toRunes

    currentBufStatus.backupBuffer(
      status.settings.autoBackup,
      status.settings.notification,
      status.commandLine,
      status.messageLog)

    status.addNewBuffer(Mode.history)
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.initHistoryManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes)

    removeFile(sourceFilePath)

    check currentBufStatus.buffer.len == 1

    let backupFilename = $currentBufStatus.buffer[0]
    check validateBackupFileName(backupFilename)

suite "History Manager: openDiffViewer":
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
    status.addNewBuffer(sourceFilePath)
    status.settings.autoBackup.backupDir = baseBackupDir.toRunes

    currentBufStatus.backupBuffer(
      status.settings.autoBackup,
      status.settings.notification,
      status.commandLine,
      status.messageLog)

    # Update the source file.
    writeFile(sourceFilePath, "test2\n")

    status.addHistoryManagerBuffer

    status.openDiffViewer(sourceFilePath)

    check status.bufStatus.len == 3
    check currentBufStatus.mode == Mode.diff

suite "History Manager: restoreBackupFile":
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
    status.addNewBuffer(sourceFilePath)
    status.settings.autoBackup.backupDir = baseBackupDir.toRunes

    currentBufStatus.backupBuffer(
      status.settings.autoBackup,
      status.settings.notification,
      status.commandLine,
      status.messageLog)

    # Update the source file.
    writeFile(sourceFilePath, "test2\n")

    status.addHistoryManagerBuffer

    const IS_FORCE_RESTORE = true
    status.restoreBackupFile(sourceFilePath.toRunes, IS_FORCE_RESTORE)

    check readFile(sourceFilePath) == "test\n"

    removeFile(sourceFilePath)

suite "History Manager: removeBackupFile":
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
    status.addNewBuffer(sourceFilePath)
    status.settings.autoBackup.backupDir = baseBackupDir.toRunes

    currentBufStatus.backupBuffer(
      status.settings.autoBackup,
      status.settings.notification,
      status.commandLine,
      status.messageLog)

    status.addHistoryManagerBuffer

    const IS_FORCE_REMOVE = true
    status.removeBackupFile(sourceFilePath.toRunes, IS_FORCE_REMOVE)

    check getBackupFiles(status.baseBackupDir, sourceFilePath.toRunes).len == 0
