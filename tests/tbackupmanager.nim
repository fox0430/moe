#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2023 Shuhei Nogawa                                       #
#                                                                              #
#  This program is free software: you can redistribute it and/or modify        #
#  it under the terms of the GNU General Public License as published by        #
#  the Free Software Foundation, either version 3 of the License, or           #
#  (at your option) any later version.                                         #
#                                                                              #
#  This program is distributed in the hope that it will be useful,             #
#  but WITHOUT ANY WARRANTY; without even the implied warranty of              #
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
#  GNU General Public License for more details.                                #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

import std/[unittest, oids, os, json, strformat]
import moepkg/[unicodeext, editorstatus, bufferstatus, backup, gapbuffer]

import moepkg/backupmanagerutils {.all.}
import moepkg/backupmanager {.all.}

template writeBackupInfoJson(backupDir, sourceFilePath: string) =
  let jsonNode = %* { "path": sourceFilePath }
  writeFile(backupDir / "backup.json", $jsonNode)

template addBackupManagerBuffer(status: var EditorStatus) =
    status.addNewBufferInCurrentWin(Mode.backup)
    status.changeCurrentBuffer(status.bufStatus.high)
    currentBufStatus.buffer = initBackupManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes).toGapbuffer

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
    currentBufStatus.buffer = initBackupManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes).toGapbuffer

    check "" == $currentBufStatus.buffer[0]

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
    currentBufStatus.buffer = initBackupManagerBuffer(
      status.baseBackupDir,
      sourceFilePath.toRunes).toGapbuffer

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
