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

import std/[os, times, oids, json]
import pkg/results
import settings, unicodeext, fileutils, bufferstatus, gapbuffer, messages,
       commandline

type
  AutoBackupStatus* = object
    lastBackupTime*: DateTime

proc initAutoBackupStatus*(): AutoBackupStatus {.inline.} =
  result.lastBackupTime = now()

template backupInfoJsonPath(backupDir: Runes): Runes =
  backupDir / "backup.json".toRunes

# Return true if already exists or create dir successfully.
proc createDir(dir: Runes): bool =
  if dirExists($dir):
    return true
  else:
    try: createDir($dir)
    except CatchableError: return false

    return true

# Return true if valid json.
proc validateBackupInfoJson*(jsonNode: JsonNode): bool =
  jsonNode.contains("path") and
  jsonNode["path"].kind == JsonNodeKind.JString and
  jsonNode["path"].getStr.len > 0

# Return path of backupDir.
# Return empty Runes if error or isn't exist.
proc getBackupDir*(baseBackupDir, sourceFilePath: Runes): Runes =
  if not dirExists($baseBackupDir):
    return "".toRunes

  for file in walkPattern($baseBackupDir / "*/backup.json" ):
    let backupJson =
      try: json.parseFile(file)
      except CatchableError: return "".toRunes

    if validateBackupInfoJson(backupJson):
      if backupJson["path"].getStr == $sourceFilePath:
        return file.splitPath.head.toRunes

# Valid filename is DateTime string.
# Exmaple: "2022-10-26T08:28:50+09:00"
proc validateBackupFileName*(filename: string): bool =
  try:
    filename.parse("yyyy-MM-dd\'T\'HH:mm:sszzz")
  except CatchableError:
    return false

  return true

# Return the backup dir for `sourceFilePath`.
# `sourceFilePath` is need to absolute path.
proc backupDir*(baseBackupDir, sourceFilePath: string): string =
  for jsonFilePath in walkPattern($baseBackupDir / "*/backup.json" ):
    let backupJson =
      try: json.parseFile(jsonFilePath)
      except CatchableError: return ""

    if validateBackupInfoJson(backupJson):
      if backupJson["path"].getStr == sourceFilePath:
        return (jsonFilePath.splitPath).head

template isPcFile*(f: tuple[kind: PathComponent, path: string]): bool =
  f.kind == PathComponent.pcFile

# `sourceFilePath` is need to absolute path.
proc getBackupFiles*(baseBackupDir, sourceFilePath: Runes): seq[Runes] =
  let backupDir = backupDir($baseBackupDir, $sourceFilePath)
  if dirExists(backupDir):
    for f in walkDir(backupDir):
      let filename = f.path.splitPath.tail
      if f.isPcFile and validateBackupFileName(filename):
        result.add(filename.toRunes)

# Return path of backupDir.
# Create dirs for base dir and for the backup source.
proc initBackupDir(baseBackupDir, sourceFilePath: Runes): Runes =
  if createDir(baseBackupDir):
    let backupDir = getBackupDir(baseBackupDir, sourceFilePath)
    if backupDir.len > 0:
      return backupDir
    else:
      let
        # `id` is the directory name for `sourceFilePath`.
        id = genOid()
        backupDir = baseBackupDir / id.toRunes
      try:
        createDir(backupDir)
      except CatchableError:
        return "".toRunes

      return backupDir

# Return the filename for the backup.
template genFilename(): Runes = now().toRunes

# Return true if the buffer changed after the previous backup.
proc diff(baseBackupDir, sourceFilePath: Runes, buffer: string): bool =
  const FORMAT = "yyyy-MM-dd\'T\'HH:mm:sszzz"
  var mostRecentFile = ""

  for f in getBackupFiles(baseBackupDir, sourceFilePath):
    let filename = $f
    if mostRecentFile.len == 0:
      mostRecentFile = filename
    else:
      if filename.parse(FORMAT) > mostRecentFile.parse(FORMAT):
        mostRecentFile = filename

  if fileExists(mostRecentFile):
    let mostRecentBuffer = openFile(mostRecentFile.toRunes)
    if mostRecentBuffer.isOk:
      return $mostRecentBuffer.get.text == buffer[0 ..< ^1]
    else:
      return false

# Return if successful.
proc writeBackupFile(
  path, buffer: Runes,
  encoding: CharacterEncoding): bool =

    try:
      saveFile(path, buffer, encoding)
    except CatchableError:
      return false

    return true

# Return true if successful.
# Save json file for backup info in the same dir of backup files.
proc writeBackupInfoJson(backupDir, sourceFilePath: Runes): bool =
  # `path` is the absolute path of backup source file.
  let jsonNode = %* { "path": $sourceFilePath }

  try:
    writeFile($backupInfoJsonPath(backupDir), $jsonNode)
  except CatchableError:
    return false

  return true

# Backup buffer to {autoBackupStatus.backupDir}/{id}/.
# Ignore if there is no change from the previous backup.
proc backupBuffer*(
  bufStatus: BufferStatus,
  autoBackupSettings: AutoBackupSettings,
  notificationSettings: NotificationSettings,
  commandLine: var CommandLine) =

    if bufStatus.path.len == 0: return

    let
      sourceFilePath = absolutePath($bufStatus.path)
      sourceFileDir = (sourceFilePath.splitPath).head
      dirToExclude = autoBackupSettings.dirToExclude

    if dirToExclude.contains(ru sourceFileDir): return

    let
      baseBackupDir = autoBackupSettings.backupDir
      backupFilename = genFilename()

    let backupDir = initBackupDir(baseBackupDir, sourceFilePath.toRunes)
    if backupDir.len == 0:
      commandLine.writeAutoBackupFailedMessage(
        backupFilename,
        notificationSettings)
      return

    let
      isSame = diff(baseBackupDir, sourceFilePath.toRunes, $bufStatus.buffer)
    if not isSame:
      commandLine.writeStartAutoBackupMessage(notificationSettings)

      let
        backupFilePath = backupDir / backupFilename
        buffer = bufStatus.buffer.toRunes
        encoding = bufStatus.characterEncoding

      if not writeBackupFile(backupFilePath, buffer, encoding):
        commandLine.writeAutoBackupFailedMessage(
          backupFilename,
          notificationSettings)
        return

      if not fileExists($backupInfoJsonPath(backupDir)):
        if not writeBackupInfoJson(backupDir, sourceFilePath.toRunes):
          commandLine.writeAutoBackupFailedMessage(
            backupFilename,
            notificationSettings)
          return

      let message = "Automatic backup successful: " & $backupFilePath
      commandLine.writeAutoBackupSuccessMessage(
        message,
        notificationSettings)
