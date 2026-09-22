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

import buffer/core, list_viewer, recovery_store, unicode_utils
import types/recovery_manager_types

export recovery_manager_types
export list_viewer

proc toEntry(c: PreservedCopy): RecoveryEntry =
  RecoveryEntry(
    copyPath: c.file.path,
    originalPath: c.file.origin.get(""),
    sessionDir: c.session.dir,
    savedAt: c.session.savedAt,
    cause: $c.session.continuity,
    detail: c.session.detail,
    changedSince: c.originalChangedSince,
    matchesDisk: c.verdict == cvSame,
  )

proc collectEntries(baseDir, sourceFilePath: string): seq[RecoveryEntry] =
  let store = newRecoveryStore(baseDir)
  if sourceFilePath.len > 0:
    for c in store.copiesOf(sourceFilePath):
      result.add c.toEntry
  else:
    for session in store.sessions:
      for f in session.files:
        result.add PreservedCopy(file: f, session: session).toEntry

proc newRecoveryManagerState*(): RecoveryManagerState =
  RecoveryManagerState(items: @[], selectedIndex: 0, sourceFilePath: "", baseDir: "")

proc initRecoveryManagerState*(
    baseDir: string, sourceFilePath: string
): RecoveryManagerState =
  ## Initialize recovery manager state for a source file. An empty
  ## `sourceFilePath` lists every preserved copy.
  result = newRecoveryManagerState()
  result.baseDir = baseDir
  result.sourceFilePath = sourceFilePath
  result.items = collectEntries(baseDir, sourceFilePath)

proc refresh*(state: RecoveryManagerState) =
  ## Re-read the preserved copies, keeping the selection in range.
  state.items = collectEntries(state.baseDir, state.sourceFilePath)
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

proc discardEntry*(state: RecoveryManagerState, index: int, reason: var string): bool =
  ## Drop the selected copy and refresh the list. On failure, `reason` says
  ## why, for the caller to show.
  if index < 0 or index >= state.items.len:
    reason = "no copy is selected"
    return false
  let entry = state.items[index]
  let store = newRecoveryStore(state.baseDir)
  if not store.discardCopy(entry.copyPath, entry.sessionDir, reason):
    return false
  state.refresh()
  true

proc createRecoveryManagerTextBuffer*(state: RecoveryManagerState): TextBuffer =
  ## Create a TextBuffer from the preserved copies.
  let withPath = state.sourceFilePath.len == 0
  let header =
    if withPath:
      "-- Recovery: all preserved work --"
    else:
      "-- Recovery: " & sanitizeForDisplay(state.sourceFilePath) & " --"
  state.toListTextBuffer(
    header,
    proc(entry: RecoveryEntry): string =
      entry.formatLine(withPath),
    emptyPlaceholder = "No preserved work found",
  )
