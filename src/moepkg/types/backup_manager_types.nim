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

## Lightweight type definitions for the backup manager.
##
## Split out from `backup_manager` so modules that only need its State type
## (notably `types` and its importers) do not transitively pull in `backup` /
## `picker/nav` via the full `backup_manager` module.

import std/times

import list_viewer_types

export list_viewer_types

type
  BackupEntry* = object ## Represents a backup file entry in the backup manager list
    filename*: string # Backup filename (timestamp)
    timestamp*: DateTime # Parsed timestamp
    fullPath*: string # Full path to the backup file

  BackupManagerState* = ref object of ListViewer[BackupEntry]
    ## State for the backup manager UI.
    ## items (backup entries)/selectedIndex/waitingForG are inherited.
    sourceFilePath*: string # Path of the source file being backed up
    backupDir*: string # Directory containing backup files
    baseBackupDir*: string # Base backup directory from config
