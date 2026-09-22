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

## Types of crash recovery: what the store lists and what the running editor
## knows about it.
##
## Split out so modules that only hold a `RecoveryIndex` (notably `types` and
## its importers) do not pull in the store and the file I/O behind it.

import std/[options, sets, tables, times]

import ../buffer/core

type
  ContinuityKind* = enum
    ckCrash = "crash"
    ckSignal = "signal"
    ckUnknown = "unknown" ## Unrecorded, or a value this version does not know.

  OriginStamp* = object
    ## Original file at preserve time; both fields optional, from one stat.
    mtime*: Option[Time]
    size*: Option[int64]

  RecoveredFile* = object
    path*: string ## Copy inside the session directory.
    origin*: Option[string]
      ## None for an unnamed buffer, and also for a copy the manifest never
      ## described. `described` tells the two apart.
    described*: bool
    originStamp*: OriginStamp
    reviewed*: bool
      ## The user has dealt with this copy: saved what was restored from it, or
      ## chose to set it aside. It stays listed; it is just no longer announced.

  RecoverySession* = object
    dir*: string
    complete*: bool
      ## Manifest landed. The preserve may still have died after it, on a file
      ## it went on to read, leaving a later copy it does not name.
    listed*: bool ## False: `files` may be incomplete, including empty.
    continuity*: ContinuityKind
    detail*: string
    savedAt*: Option[Time]
    files*: seq[RecoveredFile]

  PreservedCopy* = object
    file*: RecoveredFile
    session*: RecoverySession

  RecoveryStore* = object ## Binds listing and discard to one base directory.
    baseDir*: string

  BufferSeen* = tuple[path: string, observed: FileObservation]
    ## What a buffer's file is. Its copies are looked for again only when this
    ## changes. Not the inode: a plain save replaces it every time, and a
    ## linked file, the only kind an inode could attribute, is written in
    ## place.

  Attribution* = object
    seen*: BufferSeen
    copies*: HashSet[string] ## Paths of the copies preserved from its file.

  Restored* = object
    buffer*: BufferId
    sessionDir*: string
    change*: int64
      ## The undo entry on top of the buffer right after the restore, 0 for
      ## none.
    resets*: int
      ## The buffer's `historyResets` right after. A wholesale load since
      ## replaced what the restore put there.
    settled*: bool ## Saved into its file. Kept so it still covers the restores under it.

  CopyPrint* = object
    ## A copy's bytes, as far as they have been needed. Copies never change.
    size*: int64
    print*: Option[ContentFingerprint] ## Read only once a size matched.

  RecoveryIndex* = ref object
    store*: RecoveryStore
    listed*: bool
      ## False: the last refresh could not read the base directory, and the
      ## sessions are what an earlier one read.
    sessions*: seq[RecoverySession] ## Newest first, as the store lists them.
    originKeys*: Table[string, string]
      ## By copy path: `pathKey` of its origin, empty without one.
    attributions*: Table[BufferId, Attribution]
      ## Which copies came from each buffer's file, worked out on first asking
      ## after a refresh or after the buffer's file changed, not per frame.
    restored*: Table[string, Restored]
      ## By copy path: the buffer the copy was restored into, and the change
      ## that did it. Never written down, so it goes with this process.
    copyPrints*: Table[string, CopyPrint] ## By copy path.
