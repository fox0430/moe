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

## Lightweight type definitions for the recovery manager.
##
## Split out from `recovery_manager` so modules that only need its State type
## (notably `types` and its importers) do not transitively pull in `emergency`
## and the buffer machinery behind it.

import std/[options, times]

import list_viewer_types

export list_viewer_types

type
  RecoveryEntry* = object
    ## One preserved copy, flattened for display. Copied out of
    ## `emergency.PreservedCopy` so this module stays free of the recovery
    ## machinery.
    copyPath*: string ## The preserved copy on disk
    originalPath*: string ## Where it came from, empty for an unnamed buffer
    sessionDir*: string ## The session the copy belongs to
    savedAt*: Option[Time] ## When the session was preserved
    cause*: string ## What ended that session
    detail*: string ## Free text about the cause, e.g. an exception message
    changedSince*: bool ## The original moved on disk after the copy was made
    matchesDisk*: bool ## The original already holds these bytes

  RecoveryManagerState* = ref object of ListViewer[RecoveryEntry]
    ## State for the recovery manager UI.
    sourceFilePath*: string
      ## The file the list is about. Empty lists every preserved copy.
    baseDir*: string ## Crash recovery base directory
    armedDiscardIndex*: Option[int]
      ## The row a first `D` armed, waiting for a second one to confirm.
      ## Discarding drops text that exists nowhere else, so one keypress is
      ## not enough. Cleared by any other key and by the selection moving.
