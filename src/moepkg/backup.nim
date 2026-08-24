#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2026 Shuhei Nogawa                                       #
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

## Auto backup functionality for moe editor
##
## Backup files are stored in a configurable directory (default: ~/.cache/moe/backups).
## Each source file gets its own subdirectory identified by a unique ID.
## Backup filenames are timestamps (e.g., "2025-01-15T10:30:45+09:00").
## A backup.json file in each subdirectory maps the backup to the source file.

import std/[os, times, oids, json, options, strutils, algorithm]

import pkg/results

import config, logger

const
  BackupJsonFilename = "backup.json"
  BackupDateFormat = "yyyy-MM-dd'T'HH:mm:sszzz"
  NoChangesSinceLastBackupError* = "No changes since last backup"
  MaxBackupFiles* = 100 ## Maximum number of backup files per source file

type BackupResult* = Result[string, string]

proc expandBackupDir*(backupDir: string): string =
  ## Expand ~ in backup directory path
  ## Handles: ~/path, ~, but NOT ~user (which would require getpwnam)
  if backupDir.len == 1 and backupDir[0] == '~':
    return getHomeDir()
  elif backupDir.len > 1 and backupDir[0] == '~' and backupDir[1] == '/':
    return getHomeDir() / backupDir[2 .. ^1]
  return backupDir

proc getBaseBackupDir*(config: AutoBackupConfig): string =
  ## Get the base backup directory from config or use default
  if config.backupDir.isSome:
    expandBackupDir(config.backupDir.get)
  else:
    expandBackupDir(DefaultBackupDir)

proc backupInfoJsonPath(backupDir: string): string {.inline.} =
  backupDir / BackupJsonFilename

proc createBackupDir(dir: string): bool =
  ## Return true if dir already exists or is successfully created
  if dirExists(dir):
    return true
  try:
    createDir(dir)
    return true
  except CatchableError:
    return false

proc validateBackupInfoJson(jsonNode: JsonNode): bool =
  ## Return true if JSON has required fields
  jsonNode.contains("path") and jsonNode["path"].kind == JsonNodeKind.JString and
    jsonNode["path"].getStr.len > 0

proc getBackupDirForSource*(baseBackupDir, sourceFilePath: string): string =
  ## Find existing backup directory for a source file
  ## Returns empty string if not found
  # Use walkDir (not walkPattern) so that glob metacharacters like `[`, `*`,
  # `?` inside baseBackupDir are treated as literal path characters.
  if not dirExists(baseBackupDir):
    return ""

  for entry in walkDir(baseBackupDir):
    if entry.kind notin {PathComponent.pcDir, PathComponent.pcLinkToDir}:
      continue
    let jsonFilePath = entry.path / BackupJsonFilename
    if not fileExists(jsonFilePath):
      continue

    let backupJson =
      try:
        json.parseFile(jsonFilePath)
      except CatchableError:
        continue

    if validateBackupInfoJson(backupJson):
      if backupJson["path"].getStr == sourceFilePath:
        return entry.path

  return ""

proc validateBackupFileName*(filename: string): bool =
  ## Valid filename is DateTime string (e.g., "2025-01-15T10:30:45+09:00")
  try:
    discard filename.parse(BackupDateFormat)
    return true
  except CatchableError:
    return false

proc getBackupFilesInDir*(backupDir: string): seq[string] =
  ## Get all backup files in a backup directory (internal version)
  ## backupDir: the specific backup directory for a source file
  if backupDir.len == 0 or not dirExists(backupDir):
    return @[]

  for f in walkDir(backupDir):
    if f.kind == PathComponent.pcFile:
      let filename = f.path.extractFilename
      if validateBackupFileName(filename):
        result.add(filename)

proc getBackupFiles*(baseBackupDir, sourceFilePath: string): seq[string] =
  ## Get all backup files for a source file (public API)
  let backupDir = getBackupDirForSource(baseBackupDir, sourceFilePath)
  getBackupFilesInDir(backupDir)

proc initBackupDir(baseBackupDir, sourceFilePath: string): string =
  ## Initialize backup directory for a source file
  ## Returns the backup directory path, or empty string on error
  if not createBackupDir(baseBackupDir):
    return ""

  # Check if a backup directory already exists for this source file
  let existingDir = getBackupDirForSource(baseBackupDir, sourceFilePath)
  if existingDir.len > 0:
    return existingDir

  # Create a new directory with a unique ID
  let
    id = $genOid()
    backupDir = baseBackupDir / id

  if not createBackupDir(backupDir):
    return ""

  return backupDir

proc genBackupFilename(): string {.inline.} =
  ## Generate a backup filename from current timestamp
  now().format(BackupDateFormat)

proc getMostRecentBackupInDir(backupDir: string): string =
  ## Get the most recent backup file content from a backup directory (internal version)
  ## Returns empty string if no backup exists or on error
  let backupFiles = getBackupFilesInDir(backupDir)
  if backupFiles.len == 0:
    return ""

  var mostRecentFile = ""
  var mostRecentTime: DateTime

  for filename in backupFiles:
    try:
      let fileTime = filename.parse(BackupDateFormat)
      if mostRecentFile.len == 0 or fileTime > mostRecentTime:
        mostRecentFile = filename
        mostRecentTime = fileTime
    except CatchableError:
      continue

  if mostRecentFile.len == 0:
    return ""

  let backupFilePath = backupDir / mostRecentFile
  try:
    return readFile(backupFilePath)
  except CatchableError:
    return ""

proc getMostRecentBackup(baseBackupDir, sourceFilePath: string): string {.used.} =
  ## Get the most recent backup file content for comparison (public API)
  ## Returns empty string if no backup exists or on error
  let backupDir = getBackupDirForSource(baseBackupDir, sourceFilePath)
  if backupDir.len == 0:
    return ""
  getMostRecentBackupInDir(backupDir)

proc writeBackupInfoJson(backupDir, sourceFilePath: string): bool =
  ## Write backup info JSON file
  let jsonNode = %*{"path": sourceFilePath}
  try:
    writeFile(backupInfoJsonPath(backupDir), $jsonNode)
    return true
  except CatchableError:
    return false

proc cleanupOldBackupsInDir(backupDir: string, maxFiles: int) =
  ## Remove oldest backup files if count exceeds maxFiles (internal version)
  let backupFiles = getBackupFilesInDir(backupDir)
  if backupFiles.len <= maxFiles:
    return

  # Sort by timestamp (oldest first)
  var sortedFiles: seq[tuple[time: DateTime, name: string]] = @[]
  for filename in backupFiles:
    try:
      let fileTime = filename.parse(BackupDateFormat)
      sortedFiles.add((time: fileTime, name: filename))
    except CatchableError:
      continue

  # Sort by time ascending (oldest first)
  sortedFiles.sort(
    proc(a, b: tuple[time: DateTime, name: string]): int =
      if a.time < b.time:
        -1
      elif a.time > b.time:
        1
      else:
        0
  )

  # Delete oldest files to keep only maxFiles
  let toDelete = sortedFiles.len - maxFiles
  for i in 0 ..< toDelete:
    let filePath = backupDir / sortedFiles[i].name
    try:
      removeFile(filePath)
      logDebug("backup", "Removed old backup: " & filePath)
    except CatchableError:
      discard

proc cleanupOldBackups(baseBackupDir, sourceFilePath: string, maxFiles: int) {.used.} =
  ## Remove oldest backup files if count exceeds maxFiles (public API)
  let backupDir = getBackupDirForSource(baseBackupDir, sourceFilePath)
  if backupDir.len == 0:
    return
  cleanupOldBackupsInDir(backupDir, maxFiles)

proc backupBuffer*(
    filePath: Option[string], content: string, config: AutoBackupConfig
): BackupResult =
  ## Backup the buffer content to the backup directory
  ## Returns Ok with backup file path on success, Err with message on failure
  ##
  ## Conditions checked:
  ## - filePath must be Some
  ## - Source file directory must not be in dirToExclude
  ## - Content must be different from the most recent backup

  # Check if file path exists
  if filePath.isNone:
    return err("No file path")

  let
    sourceFilePath = absolutePath(filePath.get)
    sourceFileDir = sourceFilePath.parentDir
    baseBackupDir = getBaseBackupDir(config)

  # Check if source directory is excluded
  # Properly handle path boundaries to avoid /etc matching /etcfoo
  for excludeDir in config.dirToExclude:
    if sourceFileDir == excludeDir:
      # Exact match
      return err("Directory excluded from backup")
    elif excludeDir.endsWith("/"):
      # excludeDir already has trailing slash
      if sourceFileDir.startsWith(excludeDir):
        return err("Directory excluded from backup")
    else:
      # Add trailing slash for proper prefix matching
      if sourceFileDir.startsWith(excludeDir & "/"):
        return err("Directory excluded from backup")

  # Initialize backup directory (this is the only call to getBackupDirForSource)
  let backupDir = initBackupDir(baseBackupDir, sourceFilePath)
  if backupDir.len == 0:
    return err("Failed to create backup directory")

  # Use provided content
  let currentContent = content

  # Check if content is different from most recent backup
  # Use *InDir version to avoid redundant getBackupDirForSource call
  let mostRecentContent = getMostRecentBackupInDir(backupDir)
  if mostRecentContent == currentContent:
    return err(NoChangesSinceLastBackupError)

  # Generate backup filename and write
  let
    backupFilename = genBackupFilename()
    backupFilePath = backupDir / backupFilename

  try:
    writeFile(backupFilePath, currentContent)
  except CatchableError as e:
    return err("Failed to write backup: " & e.msg)

  # Write backup info JSON if it doesn't exist
  if not fileExists(backupInfoJsonPath(backupDir)):
    if not writeBackupInfoJson(backupDir, sourceFilePath):
      return err("Failed to write backup info")

  # Cleanup old backups to prevent disk filling
  # Use *InDir version to avoid redundant getBackupDirForSource call
  cleanupOldBackupsInDir(backupDir, MaxBackupFiles)

  logInfo("backup", "Created backup: " & backupFilePath)
  return ok(backupFilePath)
