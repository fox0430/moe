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

## Lightweight type definitions for editor persistence entries.
##
## Split out from `persist` so modules that only need these types (notably
## `types/editor_types` for the `Editor.persisted*` fields) do not
## transitively pull in the JSON / appdirs / file I/O of the full `persist`
## module. The save/load procs stay in `persist`.

import std/tables

type CursorPositionEntry* = object
  line*: int
  column*: int

type PersistedRecords*[T] = object
  ## Per-file records kept across sessions, keyed by `pathKey`. Saving merges
  ## `changes` into the file as it is then, so other sessions' entries survive.
  changes*: Table[string, T] ## This session's writes, merged on save.
  restored*: Table[string, T]
    ## The value each path was last opened with. A value equal to it is not a
    ## change, so it never overwrites what another session saved since.
  unreadableReported*: bool
    ## Whether the user was told the file cannot be read. Saving skips such a
    ## file, so it is reported once rather than lost silently.
