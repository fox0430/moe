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

## Lightweight type definitions for the diff viewer.
##
## Split out from `diff_viewer` so modules that only need `DiffViewerState`
## (notably `types` and its importers) do not transitively pull in `highlight`
## / `syntax/tokenizer` via the full `diff_viewer` module.

import list_viewer_types
export list_viewer_types

type
  DiffLineKind* = enum
    dlkNormal # Normal (context) line
    dlkAdded # Added line (starts with +)
    dlkDeleted # Deleted line (starts with -)
    dlkHeader # Header line (@@, ---, +++)
    dlkMeta # Meta line (diff --git, index, etc.)

  DiffLine* = object ## Represents a single line in the diff output
    text*: string
    kind*: DiffLineKind

  DiffViewerState* = ref object of ListViewer[DiffLine]
    ## State for the diff viewer UI.
    ## items (diff lines)/selectedIndex/waitingForG are inherited.
    sourceFilePath*: string # Path of the source file (current version)
    backupFilePath*: string # Path of the backup file (old version)
    errorMessage*: string # Error message if diff failed
