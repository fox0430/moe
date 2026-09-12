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

## File reload handling: detect external edits and reload (live reload / `:e!`),
## post-reload bookkeeping (cursor clamp, git gutter, conflict rescan, LSP
## re-open), and debounced conflict-marker scanning.

import std/[options, monotimes, times]

import pkg/results

import
  types/editor_types,
  editor_file,
  editor_lsp,
  motion,
  editor_codelens,
  editor_notify,
  editorconfig_helper,
  git_cache,
  git_conflict,
  logger,
  pending_input,
  buffer

proc isBeingEdited*(e: Editor, buf: TextBuffer): bool =
  ## True while an edit group is open on `buf`: an Insert or Replace session, or
  ## a multi-step command that began a transaction. Replacing the contents
  ## under one is unrecoverable: the reload clears the undo state while the
  ## session still holds a start position into text that is gone.
  if buf.inTransaction:
    return true
  # A live `:s` preview is an edit group nothing else can see: it opens no
  # transaction and leaves the base mode showing. Its Esc writes a whole-buffer
  # snapshot back, undoing any reload underneath it.
  if e.state.ui.substitutePreview.isActive and buf == e.activeBuffer():
    return true
  for window in e.windowManager.windows:
    if window.buffer == buf and window.mode in {EditorMode.Insert, EditorMode.Replace}:
      return true
  false

proc invalidatePositionStateForBuffer*(e: Editor, buf: TextBuffer) =
  ## Drop or re-clamp every editor-level state naming a position in `buf`,
  ## whose contents were just replaced wholesale. Nothing is remapped across
  ## such a replacement: a position is either clamped or abandoned.
  ##
  ## Driven by the buffer at the end of every load, so `:e!`, the
  ## external-change watcher and a backup restore all reach it. Decorations
  ## living on the buffer (undo, folds, bookmarks, diagnostics) are reset by
  ## `loadFile`; position-keyed state outside it belongs here.
  let isActive = buf == e.activeBuffer()
  var leftVisualMode = false

  for window in e.windowManager.windows:
    if window.buffer != buf:
      continue

    # Insert may rest one past the last character, so each window is clamped
    # with its own mode.
    let clamped = e.motionController.cursorManager.clampPosition(
      CursorPosition(x: window.cursor.column, y: window.cursor.line),
      buf,
      some(window.mode),
    )
    window.cursor = BufferPosition(line: clamped.y, column: clamped.x)
    window.preferredColumn = window.cursor.column

    # The selection anchor names text the reload dropped and cannot be
    # re-derived, so the mode goes with it.
    if window.mode.isVisualAllMode:
      window.mode = EditorMode.Normal
      window.previousMode = EditorMode.Normal
      leftVisualMode = true

    # A viewport past the new end renders an empty window that no cursor
    # movement scrolls back into view.
    if window.viewport.topLine >= buf.len:
      window.viewport.resetViewportTop(window.cursor.line)

  # The selection is a single global naming whichever window built it, so any
  # window forced out of Visual above has to drop it.
  if isActive or leftVisualMode:
    e.state.visualSelection.active = false

  if isActive:
    e.state.snippetSession.active = false
    e.state.matchingParenPos = none(BufferPosition)
    e.state.input.search.startPos = e.cursor
    # An operator waiting for its motion anchors at the position it was typed
    # on, and would build a range from text that is gone.
    e.state.pendingInput.cancelOperatorPending()
    # The preview snapshot describes the replaced text; keeping it would write
    # the old file back on Esc with no undo entry.
    e.state.ui.substitutePreview.isActive = false
    e.state.ui.substitutePreview.originalLines = @[]

  # The gesture anchors into the buffer it started on, whichever is active now.
  if e.state.pointerSelection.active and e.state.pointerSelection.bufferId == buf.id:
    e.state.pointerSelection.active = false

  # Jump entries still point at this file, but a line may be gone or shorter.
  for jump in e.state.jumpList.list.mitems:
    if jump.bufferId == buf.id:
      let clamped = e.motionController.cursorManager.clampPosition(
        CursorPosition(x: jump.column, y: jump.line), buf, some(EditorMode.Normal)
      )
      jump.line = clamped.y
      jump.column = clamped.x

proc invalidateForReplacedContent*(e: Editor, buf: TextBuffer) =
  ## Everything the editor owes a buffer whose contents were just replaced
  ## wholesale. Installed as `Editor.onBufferContentReplaced`, so it runs off
  ## the load itself instead of off a caller remembering to ask.
  ##
  ## Every buffer is registered before its first load, so no load path can
  ## bypass this.
  e.invalidatePositionStateForBuffer(buf)
  # The overlay caches are keyed by line, so the ones built from `buf` now
  # describe text that is gone.
  e.invalidateLspCachesForBuffer(buf)

proc refreshBufferGitAndConflicts*(e: Editor, buf: TextBuffer) =
  ## Refresh the git-diff gutter and rescan conflict markers for `buf` after its
  ## on-disk content was replaced out-of-band (e.g. a backup restore). Operates
  ## on an arbitrary, possibly non-active buffer, so it deliberately leaves the
  ## active-buffer conflict-scan throttle (`lastConflictScan*`) untouched.
  e.state.git.requestGitRefresh(buf)
  buf.refreshConflicts()

proc finishReload*(e: Editor, buf: TextBuffer, filePath: string, announce = true) =
  ## Shared post-reload bookkeeping for every path that replaces a buffer's
  ## contents from disk (the external-change watcher, `:e!`, a hook that
  ## rewrote the file): refresh the git gutter, rescan conflict markers, and
  ## re-open the document so the LSP re-publishes the diagnostics the reload
  ## dropped. Position and overlay invalidation is driven by the load itself.
  ##
  ## `buf` need not be the active buffer; the status message and conflict-scan
  ## throttle are skipped when it is not. `announce = false` leaves the status
  ## line alone, for a reload no keystroke asked for.
  let isActive = buf == e.activeBuffer()

  # Reload is the user's chance to pick up an edited .editorconfig.
  applyEditorConfigToBuffer(buf, e.config)

  if isActive:
    if announce:
      e.state.statusMessage = "File reloaded: " & filePath
    e.refreshGitDiff()
    buf.refreshConflicts()
    e.state.timing.lastConflictScan = getMonoTime()
    e.state.timing.lastConflictScanSeq = buf.changeSeq
  else:
    e.refreshBufferGitAndConflicts(buf)

  e.resyncBufferAfterReload(buf)

proc reportExternalChange(e: Editor, buf: TextBuffer, msg: string, isError: bool) =
  ## Report something about `buf` that no keystroke asked for. The buffer in
  ## front of the user gets a status message; anything else goes through the
  ## notification path, which carries a level. Both reach `:messages`.
  if buf == e.activeBuffer():
    e.state.statusMessage = msg
  else:
    e.notify(msg, if isError: nlError else: nlInfo)

proc actOnExternalChange(e: Editor, buf: TextBuffer, filePath: string) =
  ## Handle a detected external change on `buf`: a buffer with unsaved changes
  ## is never overwritten, only warned about once; anything else is reloaded.
  if buf.isModified:
    if not buf.externalModWarned:
      e.reportExternalChange(
        buf,
        "Warning: " & filePath & " changed on disk (buffer has unsaved changes)",
        isError = false,
      )
      buf.externalModWarned = true
    return

  logInfo("editor", "File externally modified, reloading: " & filePath)
  let reloadResult = buf.reloadFileIfContentChanged()
  if reloadResult.isErr:
    e.reportExternalChange(
      buf, "Failed to reload file: " & reloadResult.error, isError = true
    )
    return
  if not reloadResult.get:
    # Only the stat moved; `reloadFileIfContentChanged` re-baselined it.
    return

  e.finishReload(buf, filePath, announce = buf == e.activeBuffer())

proc checkBufferForExternalChange(e: Editor, buf: TextBuffer) =
  ## One buffer's half of the poll sweep: detect, then either owe the reload
  ## until the edit group closes or act on it now.
  # A viewer's buffer holds rendered content, not the file it came from.
  if buf.isUtilityBuffer or buf.filePath.isNone or not buf.isExternallyModified():
    return

  let filePath = buf.filePath.get

  # Mid-edit: keep the text the session started on, warn now rather than let
  # the user type against a file that moved, and owe the reload.
  if e.isBeingEdited(buf):
    buf.reloadDeferred = true
    if not buf.externalModWarned:
      e.reportExternalChange(
        buf,
        "Warning: " & filePath & " changed on disk (not reloaded while editing)",
        isError = false,
      )
      buf.externalModWarned = true
    return

  e.actOnExternalChange(buf, filePath)

proc maybeReloadExternallyModifiedFile*(e: Editor) =
  ## Poll every file buffer for an external change and act on it: reload a
  ## clean buffer, warn about a modified one, and owe the reload while an edit
  ## group is open. Background splits are polled too, so a `git checkout` that
  ## rewrites several open files is picked up in all of them.
  ##
  ## Enabled by `liveReloadOfFile`. The `stat` sweep is rate-limited by
  ## `fileModCheckInterval`; an owed reload is not, and runs on the first frame
  ## after the edit group closes.
  if not e.config.standard.liveReloadOfFile:
    return

  for buf in e.buffers:
    if buf.reloadDeferred and not e.isBeingEdited(buf):
      buf.reloadDeferred = false
      if buf.filePath.isSome and buf.isExternallyModified():
        e.actOnExternalChange(buf, buf.filePath.get)

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastFileModCheck
  let threshold = initDuration(milliseconds = e.state.timing.fileModCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastFileModCheck = now

  for buf in e.buffers:
    if not buf.reloadDeferred:
      e.checkBufferForExternalChange(buf)

proc reloadCurrentFile*(e: Editor, announce = true): Result[void, string] =
  ## Reload the current buffer from disk (for :e! command). `announce = false`
  ## leaves the status line untouched, for a reload the user did not ask for.
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return err("No file name")

  let filePath = activeBuffer.filePath.get
  let reloadResult = activeBuffer.reloadFile()
  if reloadResult.isErr:
    return err(reloadResult.error)

  e.finishReload(activeBuffer, filePath, announce)
  return ok()

proc maybeUpdateConflicts*(e: Editor) =
  ## Rescan the active buffer for git conflict markers when it has been
  ## modified since the last scan. Debounced by `conflictScanInterval` to
  ## keep editing responsive on very large files.
  let activeBuffer = e.activeBuffer()
  if activeBuffer.changeSeq == e.state.timing.lastConflictScanSeq:
    return
  let now = getMonoTime()
  let threshold = initDuration(milliseconds = e.state.timing.conflictScanInterval)
  if now - e.state.timing.lastConflictScan < threshold:
    return
  activeBuffer.refreshConflicts()
  e.state.timing.lastConflictScan = now
  e.state.timing.lastConflictScanSeq = activeBuffer.changeSeq
