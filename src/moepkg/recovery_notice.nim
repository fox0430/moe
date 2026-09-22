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

## Telling the user about work a crash preserved.
##
## That a file has a copy nobody has dealt with is a standing fact about its
## buffer, so it is drawn with the buffer for as long as it holds. A message
## raised while loading is overwritten by the next one, and says nothing to a
## buffer loaded in the background.

import std/[options, sequtils, strutils]

import types/editor_types, buffer/core, message_log, recovery_index, unicode_utils

proc owesPreservedWork*(e: Editor, buf: TextBuffer): bool =
  ## Whether a crash preserved work for `buf`'s file that is still owed.
  e.recovery.isSome and e.recovery.get.owes(buf, e.buffers)

proc noteReadForRecovery*(e: Editor, buf: TextBuffer) =
  ## `buf` just read or wrote its file: a copy the file holds is dealt with.
  ## Installed as `Editor.onBufferFileRead`, so every read and write path
  ## reaches it.
  if e.recovery.isNone:
    return
  for reason in e.recovery.get.noteObserved(buf):
    addMessageLog "A copy its file already holds is still announced: " & reason

proc noteSavedForRecovery*(e: Editor, buf: TextBuffer) =
  ## A copy restored into `buf` is dealt with once its text is on disk.
  if e.recovery.isNone:
    return
  for reason in e.recovery.get.noteSaved(buf):
    addMessageLog "A restored copy is still announced: " & reason

proc announce(e: Editor, notice: string) =
  ## Below whatever the status line already says: a config error owns it from
  ## startup, and a copy from a file nobody opens has no other trace.
  let standing = e.state.statusMessage
  if standing.len == 0:
    e.state.statusMessage = notice
  else:
    # `statusMessage=` would log the standing message a second time.
    addMessageLog(notice)
    e.state.setStatusQuiet(standing & "\n" & notice)

proc joinParts(parts: seq[string]): string =
  if parts.len <= 2:
    return parts.join(" and ")
  parts[0 ..^ 2].join(", ") & " and " & parts[^1]

proc counted(n: int, one, many: string): seq[string] =
  if n == 1:
    @[one]
  elif n > 1:
    @[$n & " " & many]
  else:
    @[]

proc noteRecoveryAtStartup*(e: Editor) =
  ## Once, after the startup files are open: how much preserved work is owed.
  ## Each open file's own mark says which it is, but only while it is shown,
  ## and a copy from an unnamed buffer or an unopened file has no mark at all.
  ## A session nobody is told about ages out unseen.
  if e.recovery.isNone:
    return
  let index = e.recovery.get
  let dir = sanitizeForDisplay(index.store.baseDir)
  if not index.listed:
    # Nothing is known about what is in there, so nothing is claimed.
    e.announce("Could not read the crash recovery directory " & dir)
    return
  # A file nobody opened is read only here; an open one was seen on load.
  for reason in index.noteObservedOnDisk(e.buffers):
    addMessageLog "A copy its file already holds is still announced: " & reason

  var
    holders: seq[BufferId]
    elsewhere: seq[RecoveredFile]
    unnamed = 0
    unrecorded = 0
    unreadable = false
  for session in index.sessions:
    if not session.listed:
      unreadable = true
    for f in session.files:
      if not index.owed(f, e.buffers):
        continue
      if f.origin.isSome:
        let holder = index.holderOf(f, e.buffers)
        if holder.isSome:
          # Its buffer answers for it, the same way the mark does.
          if holder.get.id notin holders:
            holders.add holder.get.id
        elif not elsewhere.anyIt(index.sameOrigin(f, it)):
          elsewhere.add f
      elif f.described:
        inc unnamed
      else:
        # The manifest never landed, did not survive being read, or was not
        # written again after this copy before the preserve died. A file
        # this copy came from may well have had a name; nobody can say which.
        inc unrecorded

  let parts =
    counted(holders.len, "a file open here", "files open here") &
    counted(elsewhere.len, "a file not open here", "files not open here") &
    counted(unnamed, "an unnamed buffer", "unnamed buffers") &
    counted(
      unrecorded, "a buffer whose file was not recorded",
      "buffers whose files were not recorded",
    )
  if parts.len > 0:
    var notice =
      "A crash preserved unsaved work from " & joinParts(parts) &
      ". :recover! to review it"
    if unreadable:
      notice.add "; part of " & dir & " could not be read"
    e.announce(notice)
  elif unreadable:
    e.announce("Part of the crash recovery directory could not be read: " & dir)
