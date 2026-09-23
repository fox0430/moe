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

## Recovery manager operations.
##
## The listing is rebuilt rather than edited in place: another editor may have
## discarded a session since it was built.
##
## Restoring puts the preserved text into the buffer as one undoable edit, then
## closes the listing and shows that buffer. Writing it to disk is left to the
## user: the copy is unsaved work and the file underneath may have moved on.
##
## The copy was written the way a save writes, so it is read back the way a load
## reads, not as raw bytes.

import pkg/results

import
  ../[
    buffer, editor, editor_buffers, highlight_config, message_log, types,
    recovery_index, recovery_manager, unicode_utils, viewer_mode,
  ]

import handler_result

proc refreshRecoveryView(e: Editor, rcState: RecoveryManagerState) =
  let activeWin = e.activeWindow
  activeWin.setView(rcState.createRecoveryManagerTextBuffer())
  activeWin.cursor.line = min(rcState.selectedIndex + 1, activeWin.buffer.len - 1)
  activeWin.cursor.column = 0

proc rereadAfterFailure(e: Editor, rcState: RecoveryManagerState) =
  ## A failed change may mean another editor changed the store first: show
  ## what is there now, in the list and on the status lines.
  rcState.refresh(e.buffers)
  e.refreshRecoveryView(rcState)

type
  RestoreOrigin = enum
    ## Where the target buffer came from, so a failed restore can undo it.
    roExisting ## Already in the list; the restore must leave it there.
    roFresh ## Created here, unnamed, and never seen by the language server.
    roLoaded ## Opened here from a path, so the language server has it open.

  RestoreTarget = object
    buffer: TextBuffer
    origin: RestoreOrigin
    adoptsShape: bool
      ## Whether the copy's line ending and encoding become the buffer's. The
      ## shape is set outside the undo entry, so only a buffer with no shape of
      ## its own and no unsaved work may take it.

proc undoOpen(e: Editor, target: RestoreTarget) =
  ## Take back a buffer this restore opened. Opening it may have reached the
  ## language server and asked git for a diff, so it goes out the same door a
  ## buffer the user closes does.
  if target.origin == roExisting:
    return
  let idx = e.bufferIndexById(target.buffer.id)
  if idx < 0:
    return
  discard e.removeBufferAt(idx)

proc takesCopyShape(b: TextBuffer): bool =
  ## Whether the copy's line ending and encoding should become `b`'s. A buffer
  ## with nothing behind its path holds only the defaults; unsaved work of its
  ## own was written in the buffer's shape, which undo would not bring back.
  b.fileBaseline.observed != fileObservedPresent and not b.isModified

proc restoreTarget(e: Editor, path: string): Result[RestoreTarget, string] =
  ## The buffer the copy goes into. A copy from an unnamed buffer gets a fresh
  ## one, and a named copy opens its file: the list is most useful right after
  ## the crash, when nothing is open yet.
  if path.len == 0:
    let buf = newTextBuffer()
    e.addBuffer(buf)
    applyHighlightConfig(buf, e.config)
    return ok(RestoreTarget(buffer: buf, origin: roFresh, adoptsShape: true))

  let index = e.findBufferByPath(path)
  if index >= 0:
    let buf = e.buffers[index]
    return ok(
      RestoreTarget(buffer: buf, origin: roExisting, adoptsShape: buf.takesCopyShape)
    )

  let loaded = e.loadOrCreateBuffer(path)
  if loaded.isErr:
    return err(loaded.error)
  ok(
    RestoreTarget(
      buffer: loaded.get, origin: roLoaded, adoptsShape: loaded.get.takesCopyShape
    )
  )

proc processRecoveryResult*(e: Editor, r: HandlerResult): bool =
  ## Handle hrRecoveryManager* kinds. Returns true to continue.
  let activeWin = e.activeWindow
  if activeWin.modeState.kind != mskRecoveryManager:
    return true
  let rcState = activeWin.modeState.recoveryManager

  case r.kind
  of hrRecoveryManagerRefresh:
    rcState.refresh(e.buffers)
    e.refreshRecoveryView(rcState)
    return true
  of hrRecoveryManagerRestore:
    let index = r.restoreRecoveryIndex
    if index < 0 or index >= rcState.items.len:
      return true
    let entry = rcState.items[index]

    # The list may span files, so fall back to the copy's own origin.
    let targetPath =
      if rcState.sourceFilePath.len > 0: rcState.sourceFilePath else: entry.originalPath

    var
      content: string
      readReason: string
    if not rcState.preservedContent(index, content, readReason):
      # Carry the reason: this copy is the only record of the work.
      let message =
        if readReason.len > 0:
          "Failed to read the preserved copy: " & sanitizeForDisplay(readReason)
        else:
          "Failed to read the preserved copy"
      e.rereadAfterFailure(rcState)
      e.state.statusMessage = message
      addMessageLog message
      return true

    let targetResult = e.restoreTarget(targetPath)
    if targetResult.isErr:
      # The path comes out of recovery.json, so it may carry control
      # characters. Log it too: the status line is gone on the next key press.
      let message = "Cannot restore: " & sanitizeForDisplay(targetResult.error)
      e.state.statusMessage = message
      addMessageLog message
      return true
    let target = targetResult.get

    # A buffer with no shape of its own takes the copy's: nothing else here
    # remembers how the work was written.
    let replaced = target.buffer.replaceWithDecodedText(
      decodeForBuffer(content),
      "restore preserved work",
      adoptShape = target.adoptsShape,
    )
    if replaced.isErr:
      # A buffer opened for a restore that put nothing in it holds nothing the
      # user asked for. Close it again; what opening it saw on disk stays
      # recorded, as it would for any other open.
      e.undoOpen(target)
      # The opened buffer is gone again, so only this record is left.
      let message = "Failed to restore: " & replaced.error
      e.state.statusMessage = message
      addMessageLog message
      return true

    # Unsaved, the work is held back only while this buffer has it: the copy
    # is dealt with once it is saved. Only a clean buffer whose file has the
    # text now counts as saved: one with edits of its own may be undone back
    # to them and saved over the file, and a clean buffer matches only what it
    # last read, which may be gone.
    var markReason = ""
    var marked = true
    let onDisk = not target.buffer.isModified and target.buffer.fileHoldsBuffer()
    if onDisk:
      marked =
        rcState.index.setReviewed(entry.copyPath, entry.sessionDir, true, markReason)
    # Recorded either way: it replaces whatever an earlier restore put here.
    rcState.index.noteRestored(
      entry.copyPath, entry.sessionDir, target.buffer, settled = onDisk and marked
    )

    if replaced.get.hunks.len > 0:
      # A replacement out of a load announces itself; this one has to. Every
      # position names text that is now gone, and the overlay caches are keyed
      # by lines that moved.
      target.buffer.emitContentReplaced()
      e.syncBufferAfterEdit(target.buffer)
      e.refreshBufferGitAndConflicts(target.buffer)

    # Show what was restored: a modified buffer left behind an open listing is
    # one `:wa` writes out before the user has seen it.
    let restoredId = target.buffer.id
    discard e.leaveViewerModeForJump(EditorMode.RecoveryManager)
    discard e.activateBuffer(restoredId)

    # How the restore got here decides the message, not the diff: a buffer
    # created or opened for this changed what the user sees even when the text
    # matched byte for byte.
    # A file that already has the text has nothing left to save.
    let saved =
      if not onDisk:
        " -- not saved yet"
      elif marked:
        "; the file already has it"
      else:
        "; the file already has it, but the copy could not be marked"
    e.state.statusMessage =
      if targetPath.len == 0:
        "Restored preserved work into a new buffer" & saved
      elif target.origin == roLoaded:
        "Opened " & sanitizeForDisplay(targetPath) & " and restored preserved work" &
          saved
      elif replaced.get.hunks.len == 0:
        "Buffer already holds the preserved work"
      else:
        "Restored preserved work into the buffer" & saved
    if not marked:
      addMessageLog "The restored copy is still announced: " & markReason
    return true
  of hrRecoveryManagerToggleReviewed:
    let index = r.reviewRecoveryIndex
    if index < 0 or index >= rcState.items.len:
      return true
    let reviewing = not rcState.items[index].reviewed
    var reason = ""
    if rcState.toggleReviewed(index, reason):
      e.refreshRecoveryView(rcState)
      e.state.statusMessage =
        if reviewing:
          "Preserved copy marked reviewed; it is kept but no longer announced"
        elif rcState.index.restoring(rcState.items[index].copyPath, e.buffers):
          # Held back by the restore, not by the mark just taken off.
          "Preserved copy is no longer marked reviewed; it is restored, not saved yet"
        else:
          "Preserved copy is announced again"
    else:
      let message = "Failed to mark the preserved copy: " & reason
      e.rereadAfterFailure(rcState)
      e.state.statusMessage = message
      addMessageLog message
    return true
  of hrRecoveryManagerDiscard:
    var discardReason = ""
    if rcState.discardEntry(r.discardRecoveryIndex, discardReason, e.buffers):
      e.state.statusMessage = "Preserved copy discarded"
      e.refreshRecoveryView(rcState)
    else:
      # Carry the filesystem reason; the user cannot see it from here.
      let message =
        if discardReason.len > 0:
          "Failed to discard the preserved copy: " & discardReason
        else:
          "Failed to discard the preserved copy"
      e.rereadAfterFailure(rcState)
      e.state.statusMessage = message
      addMessageLog message
    return true
  else:
    return true
