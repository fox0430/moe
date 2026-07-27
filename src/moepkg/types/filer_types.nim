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

## Lightweight type definitions for the file explorer (filer).
##
## Split out from `filer` so modules that only need `FilerState` (notably
## `types` and the many modules importing it) do not transitively pull in
## `highlight` / `syntax/tokenizer` / `celina` via the full `filer` module.

import std/times

type
  FileEntryKind* = enum
    fekFile
    fekDirectory
    fekSymlink

  FileEntry* = object
    name*: string
    kind*: FileEntryKind
    size*: int64
    modified*: Time
    isHidden*: bool
    isExecutable*: bool # Whether the file has execute permission
    targetKind*: FileEntryKind # For symlinks: the kind of the target (fekFile if broken)

  FilerState* = ref object
    currentPath*: string # Current directory path
    entries*: seq[FileEntry] # File/directory entries
    selectedIndex*: int # Currently selected entry index
    showHidden*: bool # Whether to show hidden files
    needsBufferRefresh*: bool # Flag to trigger buffer regeneration after state changes
    waitingForG*: bool # Waiting for second 'g' for 'gg' command
