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

## File operation procedures (load, save, auto-save, auto-backup)

import std/[options, strformat, os, monotimes, times, tables, strutils]

import pkg/results

import
  types/editor_types,
  logger,
  git_cache,
  git_conflict,
  backup,
  search_utils,
  editorconfig_helper,
  editor_codelens,
  highlight,
  highlight_config,
  persist,
  buffer,
  lsp_integration

type SaveAllBuffersResult* = object
  savedCount*: int
  savedPaths*: seq[string]
  skippedExternal*: seq[string] ## Buffers skipped because of external changes
  failures*: seq[tuple[path: string, error: string]]

proc refreshGitDiff*(e: Editor) =
  ## Mark the active buffer's diff stale so the next tick re-runs the pipeline.
  ## Used on the events that change the git state without touching the buffer:
  ## save, external reload and `:e!`.
  if e.showGitDiff:
    e.state.git.requestGitRefresh(e.activeBuffer())

template isPersistCursorPositionFile(lang: SourceLanguage): bool =
  lang notin {SourceLanguage.langGitRebaseTodo, SourceLanguage.langCommitEditMsg}

proc loadFile*(e: Editor, path: string): Result[(), string] =
  ## Load text file
  logDebug("editor", "Loading file: " & path)
  # Seed the highlight cap before loadFile builds the first chunk, so the cap
  # is not changed afterwards (which would nil the progressive-load cache).
  e.activeBuffer.applyHighlightCap(e.config)
  let r = e.activeBuffer.loadFile(path)
  if r.isErr:
    logError("editor", "Failed to load file " & path & ": " & r.error)
    return err r.error

  logInfo("editor", "Successfully loaded file: " & path)

  # Apply config-derived highlight settings (reserved words + line-length cap)
  applyHighlightConfig(e.activeBuffer, e.config)

  # Apply EditorConfig settings if enabled
  applyEditorConfigToBuffer(e.activeBuffer, e.config)

  # Restore cursor position if persisted, otherwise reset to file start
  # Don't restore for temporary git files
  let absPath = absolutePath(path)
  if e.config.persist.cursorPosition and
      isPersistCursorPositionFile(e.activeBuffer.language) and
      e.cursorPositions.hasKey(absPath):
    let savedPos = e.cursorPositions[absPath]
    # Ensure cursor position is within buffer bounds
    let line = min(savedPos.line, max(0, e.activeBuffer.len - 1))
    let col =
      if line < e.activeBuffer.len:
        min(savedPos.column, max(0, e.activeBuffer.getLine(line).charLen - 1))
      else:
        0
    e.cursor = BufferPosition(line: line, column: col)
    logDebug("editor", fmt"Restored cursor position for {path}: line={line}, col={col}")
  else:
    e.cursor = BufferPosition(line: 0, column: 0)

  # Restore bookmarks if persisted
  if e.config.persist.bookmarks and e.savedBookmarks.hasKey(absPath):
    e.activeBuffer.bookmarks = e.savedBookmarks[absPath]

  # Reset viewport to start (will be adjusted by motion controller)
  e.viewport.resetViewportTop()
  e.viewport.leftColumn = 0

  if e.showGitDiff:
    e.state.git.requestGitRefresh(e.activeBuffer)

  # Scan for git conflict markers. Run regardless of the highlight config so
  # that `buffer.conflictBlocks` is populated for future navigation commands.
  e.activeBuffer.refreshConflicts()
  e.state.timing.lastConflictScanSeq = e.activeBuffer.changeSeq
  e.state.timing.lastConflictScan = getMonoTime()

  # `loadFile` clears `highlightNeedsUpdate`, so the frame-loop invalidation
  # cascade would not fire; drop caches directly to avoid stale-coord overlays.
  e.invalidateAllLspCaches()

  # LSP initialization - non-blocking, will start in background
  if e.lsp.enabled:
    let lspResult = e.lsp.onBufferOpen(e.activeBuffer)
    if lspResult.isErr:
      logLspDegraded("didOpen", lspResult.error & " (" & path & ")")
    else:
      e.lastLspContentVersions[e.activeBuffer.id] = e.activeBuffer.contentVersion

  ok(())

proc saveBufferCursorPosition*(e: Editor, buffer: TextBuffer) =
  ## Save cursor position for a buffer if persist.cursorPosition is enabled
  if not e.config.persist.cursorPosition:
    return
  if buffer.filePath.isNone:
    return
  if not isPersistCursorPositionFile(buffer.language):
    return
  let absPath = absolutePath(buffer.filePath.get)
  e.cursorPositions[absPath] =
    CursorPositionEntry(line: e.cursor.line, column: e.cursor.column)

proc addCommandToHistory*(e: Editor, command: string) =
  ## Add a command to the command history
  ## Skips empty commands and duplicates of the last entry
  if command.len == 0:
    return
  # Skip if same as last entry
  if e.state.input.commandState.history.len > 0 and
      e.state.input.commandState.history[0] == command:
    return
  # Add to beginning (most recent first)
  e.state.input.commandState.history.insert(command, 0)
  # Trim to limit
  let limit = e.config.persist.commandHistoryLimit
  if e.state.input.commandState.history.len > limit:
    e.state.input.commandState.history.setLen(limit)

proc savePersistData*(e: Editor) =
  ## Save all persist data (search history, command history, cursor positions)
  ## Called on shutdown

  if e.config.persist.search:
    # Save search history
    let r = saveSearchHistory(
      e.state.input.search.history, e.config.persist.searchHistoryLimit
    )
    if r.isErr:
      logError("editor", "Failed to save search history: " & r.error)

  if e.config.persist.commandHistory:
    # Save command history
    let r = saveCommandHistory(
      e.state.input.commandState.history, e.config.persist.commandHistoryLimit
    )
    if r.isErr:
      logError("editor", "Failed to save command history: " & r.error)

  if e.config.persist.cursorPosition:
    # Save cursor positions
    # Save current buffer's cursor position first
    let activeBuffer = e.activeBuffer()
    e.saveBufferCursorPosition(activeBuffer)
    # Save all positions
    let r = saveCursorPositions(e.cursorPositions)
    if r.isErr:
      logError("editor", "Failed to save cursor positions: " & r.error)

  if e.config.persist.bookmarks:
    # Save bookmarks
    var allBookmarks = initTable[string, seq[int]]()
    for buf in e.buffers:
      if buf.filePath.isSome and buf.bookmarks.len > 0:
        let absPath = absolutePath(buf.filePath.get)
        allBookmarks[absPath] = buf.bookmarks
    if allBookmarks.len > 0:
      let r = saveBookmarks(allBookmarks)
      if r.isErr:
        logError("editor", "Failed to save bookmarks: " & r.error)
    else:
      # Remove the file if no bookmarks exist
      let bmPath = getBookmarksPath()
      if bmPath.isOk and fileExists(bmPath.get.string):
        try:
          removeFile(bmPath.get.string)
        except CatchableError as ex:
          logError("editor", "Failed to remove empty bookmark file: " & ex.msg)

proc trimTrailingWhitespaceIfConfigured(buffer: TextBuffer) =
  if shouldTrimTrailingWhitespace(buffer):
    for i in 0 ..< buffer.len:
      let line = buffer.getLine(i)
      let trimmed = line.strip(leading = false, trailing = true)
      if trimmed.len != line.len:
        discard buffer.replaceLine(i, trimmed)

proc saveFile*(
    e: Editor, path: Option[string] = none(string), force: bool = false
): Result[(), string] =
  ## Save the active buffer to file
  ## If path is provided, save to that path, otherwise use buffer's current file path
  ## If force is false, check if file was modified externally and refuse to save
  let activeBuffer = e.activeBuffer()

  # Determine the file path to save to
  let savePath =
    if path.isSome:
      path.get
    elif activeBuffer.filePath.isSome:
      activeBuffer.filePath.get
    else:
      logError("editor", "Save failed: No file path specified")
      return err("No file path specified")

  # Check for external modification (unless force is true). Only guard saves
  # that write back to the buffer's own file; a save-as to a different path
  # has no external-mod baseline to compare against.
  if not force and activeBuffer.filePath == some(savePath) and
      activeBuffer.isExternallyModified():
    logError("editor", "Save failed: File was modified externally: " & savePath)
    return err(ExternalModErrorMsg)

  # Trim trailing whitespace if EditorConfig says so
  trimTrailingWhitespaceIfConfigured(activeBuffer)

  # Save the file
  logDebug("editor", "Saving file: " & savePath)
  let saveResult = activeBuffer.saveFile(savePath, checkExternalMod = not force)
  if saveResult.isErr:
    logError("editor", "Failed to save file " & savePath & ": " & saveResult.error)
    return err(saveResult.error)

  logInfo("editor", "Successfully saved file: " & savePath)

  e.refreshGitDiff()

  # Notify LSP that a document was saved
  if e.lsp.enabled:
    let lspResult = e.lsp.onBufferSave(activeBuffer)
    if lspResult.isErr:
      logLspDegraded("didSave", lspResult.error & " (" & savePath & ")")

  ok(())

proc saveAllBuffers*(e: Editor, force: bool = false): SaveAllBuffersResult =
  ## Save every modified buffer that has a file path.
  ##
  ## Buffers without a file path are silently skipped (matches Vim's `:wa`).
  ## When `force` is false, buffers whose underlying file was changed externally
  ## are skipped and reported via `skippedExternal`. When true, those changes
  ## are overwritten.
  for buffer in e.buffers:
    if not buffer.isModified:
      continue
    if buffer.filePath.isNone:
      continue

    let savePath = buffer.filePath.get
    if not force and buffer.isExternallyModified():
      logError("editor", "Save all skipped externally modified file: " & savePath)
      result.skippedExternal.add(savePath)
      continue

    # Mirror saveFile: honor EditorConfig trim_trailing_whitespace per buffer.
    trimTrailingWhitespaceIfConfigured(buffer)

    let saveResult = buffer.saveFile(savePath, checkExternalMod = not force)
    if saveResult.isErr:
      logError("editor", "Save all failed for " & savePath & ": " & saveResult.error)
      result.failures.add((path: savePath, error: saveResult.error))
      continue

    result.savedCount += 1
    result.savedPaths.add(savePath)
    logInfo("editor", "Saved file: " & savePath)

    if e.showGitDiff:
      e.state.git.requestGitRefresh(buffer)

    if e.lsp.enabled:
      let lspResult = e.lsp.onBufferSave(buffer)
      if lspResult.isErr:
        logLspDegraded("didSave", lspResult.error & " (" & savePath & ")")

proc autoSave*(e: Editor) =
  ## Automatically save modified buffers if auto save is enabled and interval has passed
  ## This should be called periodically (e.g., from render loop)
  ##
  ## Conditions for auto save:
  ## - autoSave.enable is true in config
  ## - Buffer has been modified (isModified)
  ## - Buffer has a file path
  ## - Enough time has passed since last auto save (interval in minutes)

  if not e.config.autoSave.enable:
    return

  let now = getMonoTime()
  let elapsed = now - e.state.timing.lastAutoSave

  # Convert interval from minutes to Duration
  let intervalMinutes = e.config.autoSave.interval
  let threshold = initDuration(minutes = intervalMinutes)

  if elapsed < threshold:
    return

  # Iterate `e.buffers`, not windows: windows only expose foreground tabs,
  # so background-tab buffers would silently miss auto save.
  var savedCount = 0
  var savedPaths: seq[string] = @[]

  for buffer in e.buffers:
    # Check if buffer is modified and has a file path
    if buffer.isModified and buffer.filePath.isSome:
      let savePath = buffer.filePath.get

      # Skip externally modified files to avoid overwriting external changes
      if buffer.isExternallyModified():
        logDebug(
          "editor", "Skipping auto save for externally modified file: " & savePath
        )
        continue

      let saveResult = buffer.saveFile(savePath, checkExternalMod = true)

      if saveResult.isOk:
        savedCount += 1
        savedPaths.add(savePath)

        if e.showGitDiff:
          e.state.git.requestGitRefresh(buffer)

        # Notify LSP that a document was saved
        if e.lsp.enabled:
          let lspResult = e.lsp.onBufferSave(buffer)
          if lspResult.isErr:
            logLspDegraded("didSave", lspResult.error & " (" & savePath & ")")
      else:
        logError("editor", "Auto save failed for " & savePath & ": " & saveResult.error)

  # Update last auto save time
  e.state.timing.lastAutoSave = now

  # Show notification if any files were saved
  if savedCount > 0:
    # Log notification
    if e.config.notification.logNotifications and e.config.notification.autoSaveLogNotify:
      if savedCount == 1:
        logInfo("editor", "Auto saved: " & savedPaths[0])
      else:
        logInfo("editor", "Auto saved " & $savedCount & " files")

    # Screen notification (status message)
    if e.config.notification.screenNotifications and
        e.config.notification.autoSaveScreenNotify:
      if savedCount == 1:
        e.state.statusMessage = "Auto saved: " & savedPaths[0]
      else:
        e.state.statusMessage = "Auto saved " & $savedCount & " files"

proc updateInputTime*(e: Editor) =
  ## Update the last input time (called when user provides input)
  e.state.timing.lastInputTime = getMonoTime()

proc autoBackup*(e: Editor) =
  ## Automatically backup modified buffers if auto backup is enabled
  ## This should be called periodically (e.g., from render loop)
  ##
  ## Conditions for auto backup:
  ## - autoBackup.enable is true in config
  ## - User has been idle for idleTime seconds
  ## - Enough time has passed since last backup (interval in minutes)

  if not e.config.autoBackup.enable:
    return

  let now = getMonoTime()

  # Check idle time (user must be idle for idleTime seconds)
  let idleElapsed = now - e.state.timing.lastInputTime
  let idleThreshold = initDuration(seconds = e.config.autoBackup.idleTime)

  if idleElapsed < idleThreshold:
    return

  # Check backup interval (must have passed interval minutes since last backup)
  let backupElapsed = now - e.state.timing.lastAutoBackup
  let backupThreshold = initDuration(minutes = e.config.autoBackup.interval)

  if backupElapsed < backupThreshold:
    return

  # Iterate `e.buffers`, not windows: windows only expose foreground tabs,
  # so background-tab buffers would silently miss auto backup.
  var backupCount = 0
  var backupPaths: seq[string] = @[]

  for buffer in e.buffers:
    # Only backup modified buffers with a file path
    if buffer.isModified and buffer.filePath.isSome:
      let backupResult =
        backupBuffer(buffer.filePath, buffer.getFileContent(), e.config.autoBackup)

      if backupResult.isOk:
        backupCount += 1
        backupPaths.add(backupResult.get)

  # Always update last backup time to prevent repeated checks every frame
  e.state.timing.lastAutoBackup = now

  # Show notification if any files were backed up
  if backupCount > 0:
    # Log notification
    if e.config.notification.logNotifications and
        e.config.notification.autoBackupLogNotify:
      if backupCount == 1:
        logInfo("editor", "Auto backup: " & backupPaths[0])
      else:
        logInfo("editor", "Auto backup: " & $backupCount & " files")

    # Screen notification (status message)
    if e.config.notification.screenNotifications and
        e.config.notification.autoBackupScreenNotify:
      if backupCount == 1:
        e.state.statusMessage = "Auto backup created"
      else:
        e.state.statusMessage = "Auto backup: " & $backupCount & " files"
