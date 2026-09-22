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

## UI for reviewing and restoring what a crash preserved.
##
## The list is about one file by default, and falls back to every preserved
## copy when no file is open. Discarding asks first, since the text exists
## nowhere else.
##
## Restoring puts the preserved text back into the buffer as one undoable
## edit, never onto the disk, so restoring the wrong copy costs one `u`.

import std/[options, os, strutils, times, unicode]

import buffer/core, list_viewer, recovery_index, unicode_utils
import types/recovery_manager_types

export recovery_manager_types
export list_viewer

proc toEntry(
    index: RecoveryIndex, c: PreservedCopy, buffers: openArray[TextBuffer]
): RecoveryEntry =
  RecoveryEntry(
    copyPath: c.file.path,
    originalPath: c.file.origin.get(""),
    sessionDir: c.session.dir,
    savedAt: c.session.savedAt,
    cause: $c.session.continuity,
    detail: c.session.detail,
    changedSince: c.originalChangedSince,
    matchesDisk: index.holds(c.file, buffers),
    reviewed: c.file.reviewed,
    restored: index.restoring(c.file, buffers),
  )

proc collectEntries(
    index: RecoveryIndex, sourceFilePath: string, buffers: openArray[TextBuffer]
): seq[RecoveryEntry] =
  ## Every copy, reviewed or not: setting one aside only stops the notice.
  if sourceFilePath.len > 0:
    for c in index.copiesOf(sourceFilePath):
      result.add index.toEntry(c, buffers)
  else:
    for session in index.sessions:
      for f in session.files:
        result.add index.toEntry(PreservedCopy(file: f, session: session), buffers)

proc newRecoveryManagerState*(): RecoveryManagerState =
  RecoveryManagerState(items: @[], selectedIndex: 0, sourceFilePath: "")

proc initRecoveryManagerState*(
    index: RecoveryIndex, sourceFilePath: string, buffers: openArray[TextBuffer]
): RecoveryManagerState =
  ## Initialize recovery manager state for a source file. An empty
  ## `sourceFilePath` lists every preserved copy. `buffers` are the open ones,
  ## which answer for their files the way the status line mark does.
  result = newRecoveryManagerState()
  result.index = index
  result.sourceFilePath = sourceFilePath
  result.items = collectEntries(index, sourceFilePath, buffers)

proc initRecoveryManagerState*(
    baseDir: string, sourceFilePath: string, buffers: openArray[TextBuffer]
): RecoveryManagerState =
  ## Over a fresh index of `baseDir`, shared with nothing.
  initRecoveryManagerState(newRecoveryIndex(baseDir), sourceFilePath, buffers)

proc refresh*(state: RecoveryManagerState, buffers: openArray[TextBuffer]) =
  ## Re-read the preserved copies, keeping the selection in range.
  state.index.refresh()
  state.items = collectEntries(state.index, state.sourceFilePath, buffers)
  if state.items.len > 0:
    if state.selectedIndex >= state.items.len:
      state.selectedIndex = state.items.high
  else:
    state.selectedIndex = 0

proc formatTimestamp*(t: Option[Time]): string =
  ## Local time: the user compares it against their memory of the crash.
  if t.isNone:
    return "unknown time"
  try:
    t.get.local.format("yyyy-MM-dd HH:mm:ss")
  except CatchableError:
    "unknown time"

proc noteFor*(entry: RecoveryEntry): string =
  ## Short note on whether the copy still has anything to offer.
  if entry.matchesDisk:
    "already saved"
  elif entry.reviewed:
    "reviewed"
  elif entry.restored:
    "restored, not saved yet"
  elif entry.changedSince:
    "file changed since"
  else:
    ""

const DetailWidth = 60 ## Enough to tell two endings of the same kind apart.

proc shownDetail*(entry: RecoveryEntry): string =
  ## The detail as one row can carry it: a single sanitized line, cut to
  ## length. It is arbitrary text and must not reach the terminal as-is.
  if entry.detail.len == 0:
    return ""
  let flat = sanitizeForDisplay(entry.detail.replace("\n", " ").strip())
  # By runes: cutting mid-character would put an invalid byte on the row.
  if flat.runeLen <= DetailWidth:
    flat
  else:
    flat.runeSubstr(0, DetailWidth - 1) & "…"

proc formatLine*(entry: RecoveryEntry, withPath: bool): string =
  ## One list row. The path is only worth a column when the list spans files.
  ## All metadata is sanitized: a file name may carry control characters, and
  ## a newline would shift every row below it out of sync with the selection.
  result = formatTimestamp(entry.savedAt) & "  " & sanitizeForDisplay(entry.cause)
  let detail = entry.shownDetail
  if detail.len > 0:
    result.add ": " & detail
  if withPath:
    # A copy with no origin is still identified by its preserved name.
    let shown =
      if entry.originalPath.len > 0:
        entry.originalPath
      else:
        "[No Name: " & entry.copyPath.lastPathPart & "]"
    result.add "  " & sanitizeForDisplay(shown)
  let note = entry.noteFor
  if note.len > 0:
    result.add "  (" & note & ")"

proc preservedContent*(
    state: RecoveryManagerState, index: int, content: var string, reason: var string
): bool =
  ## Read the preserved bytes of the selected copy. On failure, `reason` says
  ## why, for the caller to show.
  if index < 0 or index >= state.items.len:
    reason = "no copy is selected"
    return false
  try:
    content = readFile(state.items[index].copyPath)
    true
  except CatchableError as e:
    reason = e.msg
    false

proc discardEntry*(
    state: RecoveryManagerState,
    index: int,
    reason: var string,
    buffers: openArray[TextBuffer],
): bool =
  ## Drop the selected copy and refresh the list. On failure, `reason` says
  ## why, for the caller to show.
  if index < 0 or index >= state.items.len:
    reason = "no copy is selected"
    return false
  let entry = state.items[index]
  if not state.index.store.discardCopy(entry.copyPath, entry.sessionDir, reason):
    return false
  state.refresh(buffers)
  true

proc toggleReviewed*(
    state: RecoveryManagerState, index: int, reason: var string
): bool =
  ## Flip whether the selected copy counts as dealt with. Only that row
  ## changes.
  if index < 0 or index >= state.items.len:
    reason = "no copy is selected"
    return false
  let entry = state.items[index]
  if not state.index.setReviewed(
    entry.copyPath, entry.sessionDir, not entry.reviewed, reason
  ):
    return false
  state.items[index].reviewed = not entry.reviewed
  true

proc createRecoveryManagerTextBuffer*(state: RecoveryManagerState): TextBuffer =
  ## Create a TextBuffer from the preserved copies.
  let withPath = state.sourceFilePath.len == 0
  var header =
    if withPath:
      "-- Recovery: all preserved work --"
    else:
      "-- Recovery: " & sanitizeForDisplay(state.sourceFilePath) & " --"
  if state.index != nil and not state.index.listed:
    # An empty list here would read as nothing preserved.
    header.add " could not read " & sanitizeForDisplay(state.index.store.baseDir) &
      "; showing what was last read"
  state.toListTextBuffer(
    header,
    proc(entry: RecoveryEntry): string =
      entry.formatLine(withPath),
    emptyPlaceholder = "No preserved work found",
  )
