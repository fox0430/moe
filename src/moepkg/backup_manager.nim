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

## Backup Manager module
## Provides a UI for viewing and managing backup files

import std/[options, os, times, algorithm]

import pkg/results

import backup, buffer/core, list_viewer
import buffer/atomic_write
import types/backup_manager_types

export backup_manager_types
export list_viewer

const BackupDateFormat = "yyyy-MM-dd'T'HH:mm:sszzz"

proc newBackupManagerState*(): BackupManagerState =
  BackupManagerState(
    items: @[], selectedIndex: 0, sourceFilePath: "", backupDir: "", baseBackupDir: ""
  )

proc parseBackupTimestamp(filename: string): Option[DateTime] =
  ## Parse a backup filename into a DateTime
  try:
    some(filename.parse(BackupDateFormat))
  except CatchableError:
    none(DateTime)

proc initBackupManagerEntries*(backupDir: string): seq[BackupEntry] =
  ## Create backup entries from a backup directory
  result = @[]

  if backupDir.len == 0 or not dirExists(backupDir):
    return

  let files = getBackupFilesInDir(backupDir)
  for filename in files:
    let timestamp = parseBackupTimestamp(filename)
    if timestamp.isSome:
      result.add(
        BackupEntry(
          filename: filename, timestamp: timestamp.get, fullPath: backupDir / filename
        )
      )

  # Sort by timestamp descending (newest first)
  result.sort(
    proc(a, b: BackupEntry): int =
      if a.timestamp > b.timestamp:
        -1
      elif a.timestamp < b.timestamp:
        1
      else:
        0
  )

proc initBackupManagerState*(
    baseBackupDir: string, sourceFilePath: string
): BackupManagerState =
  ## Initialize backup manager state for a source file
  result = newBackupManagerState()
  result.sourceFilePath = sourceFilePath
  result.baseBackupDir = baseBackupDir
  result.backupDir = getBackupDirForSource(baseBackupDir, sourceFilePath)
  result.items = initBackupManagerEntries(result.backupDir)

proc refresh*(state: BackupManagerState) =
  ## Refresh the backup entries list
  state.backupDir = getBackupDirForSource(state.baseBackupDir, state.sourceFilePath)
  state.items = initBackupManagerEntries(state.backupDir)
  # Clamp selectedIndex to valid range
  if state.items.len > 0:
    if state.selectedIndex >= state.items.len:
      state.selectedIndex = state.items.len - 1
  else:
    state.selectedIndex = 0

proc formatTimestamp*(dt: DateTime): string =
  ## Format a DateTime for display
  dt.format("yyyy-MM-dd HH:mm:ss")

proc formatLine*(entry: BackupEntry): string =
  ## Format a backup entry for display
  formatTimestamp(entry.timestamp)

proc deleteBackup*(state: BackupManagerState, index: int): bool =
  ## Delete a backup file
  ## Returns true on success
  if index < 0 or index >= state.items.len:
    return false

  let entry = state.items[index]
  try:
    removeFile(entry.fullPath)
    state.refresh()
    return true
  except OSError:
    return false

proc restoreBackup*(state: BackupManagerState, index: int): bool =
  ## Restore a backup file to its source atomically.
  ## Returns true on success.
  if index < 0 or index >= state.items.len:
    return false

  let entry = state.items[index]
  if not fileExists(entry.fullPath):
    return false

  # rename() bypasses the read-only bit; check explicitly.
  if fileExists(state.sourceFilePath):
    try:
      if fpUserWrite notin getFilePermissions(state.sourceFilePath):
        return false
    except OSError:
      return false

  var content: string
  try:
    content = readFile(entry.fullPath)
  except CatchableError:
    return false

  not writeAtomic(state.sourceFilePath, content).isErr

proc createBackupManagerTextBuffer*(state: BackupManagerState): TextBuffer =
  ## Create a TextBuffer from backup entries for rendering via the normal view path
  state.toListTextBuffer(
    "-- Backup Manager: " & state.sourceFilePath & " --",
    formatLine,
    emptyPlaceholder = "No backup files found",
  )
