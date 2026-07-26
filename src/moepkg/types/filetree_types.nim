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

## Lightweight type definitions for the file tree sidebar.
##
## Split out from `filetree` so modules that only need `FileTreeState` (notably
## `types` and its importers) do not transitively pull in `highlight` /
## `celina` via the full `filetree` module. `FileEntryKind` is reused from
## `filer_types`.

import std/[sets, tables]

import filer_types

type
  FileTreeNode* = object
    name*: string
    path*: string # Absolute path
    kind*: FileEntryKind # Reuse from filer.nim
    depth*: int # Indentation level
    isHidden*: bool
    isExecutable*: bool
    targetKind*: FileEntryKind # For symlinks

  FileTreeState* = ref object
    rootPath*: string
    rootNodes*: seq[FileTreeNode]
    flatList*: seq[FileTreeNode] # Flattened visible nodes
    selectedIndex*: int
    showHidden*: bool
    expandedDirs*: HashSet[string] # Set of expanded directory paths
    needsBufferRefresh*: bool
    width*: int # Default sidebar width
    lastError*: string # Last error message (e.g. permission denied)
    childrenCache*: Table[string, seq[FileTreeNode]]
    waitingForG*: bool # Waiting for second 'g' for 'gg' command
    waitingForCtrlW*: bool # Waiting for second key after Ctrl-w
    lastKeyWasEscape*: bool # Waiting for second Escape to clear search highlight
    isSearching*: bool # In search input mode
    searchText*: string # Current search text
    searchMatches*: seq[int] # Indices in flatList that match
    searchMatchIndex*: int # Current position in searchMatches (-1 = none)
