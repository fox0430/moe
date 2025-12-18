#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import backup

const BackupDateFormat = "yyyy-MM-dd'T'HH:mm:sszzz"

type
  BackupEntry* = object ## Represents a backup file entry in the backup manager list
    filename*: string # Backup filename (timestamp)
    timestamp*: DateTime # Parsed timestamp
    fullPath*: string # Full path to the backup file

  BackupManagerState* = ref object ## State for the backup manager UI
    entries*: seq[BackupEntry] # List of backup entries
    selectedIndex*: int # Currently selected entry index
    topLine*: int # Scroll position (first visible line)
    sourceFilePath*: string # Path of the source file being backed up
    backupDir*: string # Directory containing backup files
    baseBackupDir*: string # Base backup directory from config

proc newBackupManagerState*(): BackupManagerState =
  BackupManagerState(
    entries: @[],
    selectedIndex: 0,
    topLine: 0,
    sourceFilePath: "",
    backupDir: "",
    baseBackupDir: "",
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
  result.entries = initBackupManagerEntries(result.backupDir)

proc refresh*(state: BackupManagerState) =
  ## Refresh the backup entries list
  state.backupDir = getBackupDirForSource(state.baseBackupDir, state.sourceFilePath)
  state.entries = initBackupManagerEntries(state.backupDir)
  # Clamp selectedIndex to valid range
  if state.entries.len > 0:
    if state.selectedIndex >= state.entries.len:
      state.selectedIndex = state.entries.len - 1
  else:
    state.selectedIndex = 0

proc moveUp*(state: BackupManagerState) =
  ## Move selection up
  if state.entries.len > 0 and state.selectedIndex > 0:
    state.selectedIndex.dec
    # Adjust scroll position if needed
    if state.selectedIndex < state.topLine:
      state.topLine = state.selectedIndex

proc moveDown*(state: BackupManagerState) =
  ## Move selection down
  if state.entries.len > 0 and state.selectedIndex < state.entries.len - 1:
    state.selectedIndex.inc
    # Note: scroll adjustment for moving down is handled during rendering

proc moveToFirst*(state: BackupManagerState) =
  ## Move to first entry
  state.selectedIndex = 0
  state.topLine = 0

proc moveToLast*(state: BackupManagerState) =
  ## Move to last entry
  if state.entries.len > 0:
    state.selectedIndex = state.entries.len - 1

proc getSelectedEntry*(state: BackupManagerState): Option[BackupEntry] =
  ## Get the currently selected backup entry
  if state.selectedIndex >= 0 and state.selectedIndex < state.entries.len:
    some(state.entries[state.selectedIndex])
  else:
    none(BackupEntry)

proc formatTimestamp*(dt: DateTime): string =
  ## Format a DateTime for display
  dt.format("yyyy-MM-dd HH:mm:ss")

proc formatEntry*(entry: BackupEntry): string =
  ## Format a backup entry for display
  formatTimestamp(entry.timestamp)

proc deleteBackup*(state: BackupManagerState, index: int): bool =
  ## Delete a backup file
  ## Returns true on success
  if index < 0 or index >= state.entries.len:
    return false

  let entry = state.entries[index]
  try:
    removeFile(entry.fullPath)
    state.refresh()
    return true
  except OSError:
    return false

proc restoreBackup*(state: BackupManagerState, index: int): bool =
  ## Restore a backup file to its source
  ## Returns true on success
  if index < 0 or index >= state.entries.len:
    return false

  let entry = state.entries[index]
  if not fileExists(entry.fullPath):
    return false

  try:
    copyFile(entry.fullPath, state.sourceFilePath)
    return true
  except OSError:
    return false
