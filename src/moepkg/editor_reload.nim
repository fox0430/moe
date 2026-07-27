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
  editor_codelens,
  editorconfig_helper,
  git_cache,
  git_conflict,
  motion,
  logger,
  buffer

proc clampCursorAfterReload(e: Editor, buf: TextBuffer) =
  ## A reload swaps the buffer contents wholesale without touching the cursor.
  ## If the file shrank, the cursor can now point past the last line (or past a
  ## now-shorter line's end); if it grew, the column may dangle past the new
  ## line. Re-clamp to valid bounds here so rendering, completion and
  ## word-at-cursor reads don't observe a stale out-of-range position in the
  ## window before the next motion would have re-clamped it.
  let clamped = e.motionController.cursorManager.clampPosition(
    CursorPosition(x: e.cursor.column, y: e.cursor.line), buf
  )
  e.cursor = BufferPosition(line: clamped.y, column: clamped.x)

proc finishReload(e: Editor, buf: TextBuffer, filePath: string) =
  ## Shared post-reload bookkeeping for both the external-change and `:e!` paths:
  ## re-clamp the cursor, refresh the git gutter, rescan conflict markers against
  ## the new content, and re-open the document so the LSP re-publishes diagnostics.
  ## The reload dropped the buffer's diagnostics; re-open ensures the server
  ## re-publishes them regardless of whether the on-disk bytes changed.
  # Reload is the user's chance to pick up an edited .editorconfig.
  applyEditorConfigToBuffer(buf, e.config)
  e.clampCursorAfterReload(buf)
  e.state.statusMessage = "File reloaded: " & filePath
  e.refreshGitDiff()
  buf.refreshConflicts()
  e.state.timing.lastConflictScan = getMonoTime()
  e.state.timing.lastConflictScanSeq = buf.changeSeq
  # Reload clears highlightNeedsUpdate; drop caches so a pre-reload response
  # cannot paint stale coords onto the fresh buffer.
  e.invalidateAllLspCaches()
  e.resyncBufferAfterReload(buf)

proc maybeReloadExternallyModifiedFile*(e: Editor) =
  ## Check if files were modified externally and reload them if:
  ##   - liveReloadOfFile is enabled in config
  ##   - Buffer has no unsaved changes (if modified, just show a message)
  ##   - Enough time has passed since last check (debouncing)

  if not e.config.standard.liveReloadOfFile:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastFileModCheck
  let threshold = initDuration(milliseconds = e.state.timing.fileModCheckInterval)

  if elapsed < threshold:
    return

  e.state.timing.lastFileModCheck = now

  # Check the active buffer
  let activeBuffer = e.activeBuffer()
  if not activeBuffer.isExternallyModified():
    return

  let filePath =
    if activeBuffer.filePath.isSome:
      activeBuffer.filePath.get
    else:
      return

  # If buffer has unsaved changes, warn the user instead of reloading
  if activeBuffer.isModified:
    if not activeBuffer.externalModWarned:
      e.state.statusMessage =
        "Warning: " & filePath & " changed on disk (buffer has unsaved changes)"
      activeBuffer.externalModWarned = true
    return

  # Reload the file
  logInfo("editor", "File externally modified, reloading: " & filePath)
  let reloadResult = activeBuffer.reloadFile()
  if reloadResult.isOk:
    e.finishReload(activeBuffer, filePath)
  else:
    e.state.statusMessage = "Failed to reload file: " & reloadResult.error

proc reloadCurrentFile*(e: Editor): Result[void, string] =
  ## Reload the current buffer from disk (for :e! command)
  let activeBuffer = e.activeBuffer()
  if activeBuffer.filePath.isNone:
    return err("No file name")

  let filePath = activeBuffer.filePath.get
  let reloadResult = activeBuffer.reloadFile()
  if reloadResult.isErr:
    return err(reloadResult.error)

  e.finishReload(activeBuffer, filePath)
  return ok()

proc refreshBufferGitAndConflicts*(e: Editor, buf: TextBuffer) =
  ## Refresh the git-diff gutter and rescan conflict markers for `buf` after its
  ## on-disk content was replaced out-of-band (e.g. a backup restore). Operates
  ## on an arbitrary, possibly non-active buffer, so it deliberately leaves the
  ## active-buffer conflict-scan throttle (`lastConflictScan*`) untouched.
  e.state.git.requestGitRefresh(buf)
  buf.refreshConflicts()

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
