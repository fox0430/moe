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

## Backup manager side effects (refresh, restore, delete, diff), split
## out of result_processor.nim.

import std/[options, os, times]
import pkg/results

import
  ../[
    backup, backup_manager, buffer, diff_viewer, editor, editor_window_state, logger,
    types,
  ]
import ../buffer/atomic_write

import handler_result

type RollbackOutcome = enum
  rollbackApplied
  rollbackSkippedExternalChange

proc rollbackRestoredFile(
    sourcePath: string,
    sourceExisted: bool,
    previousDiskContent: string,
    expectedRestoredContent: string,
): Result[RollbackOutcome, string] =
  ## Restore the source path to the state it had before the backup operation.
  ## Do not overwrite a file changed after the restore.
  if not fileExists(sourcePath):
    return Result[RollbackOutcome, string].ok rollbackSkippedExternalChange

  try:
    if readFile(sourcePath) != expectedRestoredContent:
      return Result[RollbackOutcome, string].ok rollbackSkippedExternalChange
  except CatchableError as ex:
    return Result[RollbackOutcome, string].err(
      "Cannot verify restored file before rollback: " & ex.msg
    )

  if not sourceExisted:
    try:
      removeFile(sourcePath)
      return Result[RollbackOutcome, string].ok rollbackApplied
    except CatchableError as ex:
      return Result[RollbackOutcome, string].err ex.msg

  let writeResult = writeAtomic(sourcePath, previousDiskContent)
  if writeResult.isErr:
    return Result[RollbackOutcome, string].err writeResult.error
  return Result[RollbackOutcome, string].ok rollbackApplied

proc refreshRollbackFileMetadata(
    buf: TextBuffer, path: string, preserveExternalChange: bool
) =
  ## Keep external-change detection aligned with a file restored by rollback.
  if preserveExternalChange:
    # Keep the old baseline so a stale buffer cannot overwrite external edits.
    buf.externalModWarned = false
    return

  if fileExists(path):
    try:
      buf.lastFileModTime = some(getFileInfo(path).lastWriteTime)
    except OSError:
      buf.lastFileModTime = none(Time)
  else:
    buf.lastFileModTime = none(Time)
  buf.externalModWarned = false

proc processBackupResult*(e: Editor, r: HandlerResult): bool =
  ## Handle hrBackupManager* kinds (refresh, restore, delete, diff).
  ## Returns true to continue.
  case r.kind
  of hrBackupManagerRefresh:
    # Refresh backup list and regenerate TextBuffer
    let activeWin = e.activeWindow
    if activeWin.modeState.kind == mskBackupManager:
      let bkState = activeWin.modeState.backupManager
      bkState.refresh()
      activeWin.buffer = bkState.createBackupManagerTextBuffer()
      activeWin.cursor.line = min(bkState.selectedIndex + 1, activeWin.buffer.len - 1)
      activeWin.cursor.column = 0
    return true
  of hrBackupManagerRestore:
    # Restore the selected backup
    let backupIndex = r.restoreBackupIndex
    let activeWin = e.activeWindow
    if activeWin.modeState.kind == mskBackupManager:
      let bkState = activeWin.modeState.backupManager
      # The active buffer is the backup-list view, not the restored file.
      # Operate on the source buffer located by `bkState.sourceFilePath`.
      let sourcePath = bkState.sourceFilePath
      let srcIdx =
        if sourcePath.len > 0:
          e.findBufferByPath(sourcePath)
        else:
          -1
      if srcIdx < 0:
        # No source buffer: refuse rather than overwrite the file without undo.
        e.state.statusMessage = "Cannot restore: source buffer not found"
        return true
      let srcBuf = e.buffers[srcIdx]
      let previousContent = srcBuf.getFileContent()
      let sourceExisted = fileExists(sourcePath)
      var previousDiskContent = ""
      if sourceExisted:
        try:
          previousDiskContent = readFile(sourcePath)
        except CatchableError as ex:
          # A clean buffer may still be stale after an external edit. Without a
          # disk snapshot, restoring it would risk overwriting newer content.
          logError(
            "restore",
            "Cannot safely snapshot current file " & sourcePath & ": " & ex.msg,
          )
          e.state.statusMessage =
            "Cannot restore: failed to read the current file safely: " & ex.msg
          return true
      let sourceWasExternallyModified = srcBuf.isExternallyModified()
      var restoredContent: string
      if bkState.restoreBackup(backupIndex, restoredContent):
        # Take the safety backup after the restore so its cleanup can't delete
        # the entry being restored; the disk-only copy leaves srcBuf holding
        # the pre-restore content as the undo snapshot.
        let safetyBackupResult =
          backupBuffer(srcBuf.filePath, previousContent, e.config.autoBackup)
        let safetyBackupFailed =
          safetyBackupResult.isErr and
          safetyBackupResult.error != NoChangesSinceLastBackupError
        if safetyBackupFailed:
          let recoveryContext =
            if srcBuf.isModified: "preserve unsaved changes" else: "create safety backup"
          let rollbackResult = rollbackRestoredFile(
            sourcePath, sourceExisted, previousDiskContent, restoredContent
          )
          if rollbackResult.isOk:
            let externalChangePreserved =
              rollbackResult.get == rollbackSkippedExternalChange
            srcBuf.refreshRollbackFileMetadata(
              sourcePath, sourceWasExternallyModified or externalChangePreserved
            )
            if externalChangePreserved:
              e.state.statusMessage =
                "Backup restore cancelled; source file changed externally"
            else:
              e.state.statusMessage =
                "Backup restore cancelled; failed to " & recoveryContext & ": " &
                safetyBackupResult.error
          else:
            srcBuf.refreshRollbackFileMetadata(sourcePath, true)
            logError(
              "restore",
              "Failed to " & recoveryContext & " and roll back " & sourcePath & ": " &
                safetyBackupResult.error & "; rollback: " & rollbackResult.error,
            )
            e.state.statusMessage =
              "Backup restore failed and could not " & recoveryContext & ": " &
              rollbackResult.error
        else:
          # Reload the source buffer from the restored file on disk
          let textResult = srcBuf.loadFile(sourcePath)
          if textResult.isOk:
            # Periodic LSP sync only covers the active buffer; the restored
            # buffer is in another split, so sync it explicitly.
            e.syncBufferAfterEdit(srcBuf, "restore")
            # The restored file may be shorter; re-clamp cursors in other splits.
            e.clampAllWindowCursors()
            # Refresh the restored buffer's git-diff gutter and conflicts.
            e.refreshBufferGitAndConflicts(srcBuf)
            # Restore screen notification (controlled by config)
            if e.config.notification.screenNotifications and
                e.config.notification.restoreScreenNotify:
              e.notify("Backup restored: " & sourcePath)
            # Restore log notification (controlled by config)
            if e.config.notification.logNotifications and
                e.config.notification.restoreLogNotify:
              logInfo("restore", "Backup restored: " & sourcePath)
          else:
            # loadFile leaves srcBuf unchanged when reading fails. Restore the
            # disk content as well so a later save cannot overwrite the backup
            # with the stale in-memory buffer.
            let rollbackResult = rollbackRestoredFile(
              sourcePath, sourceExisted, previousDiskContent, restoredContent
            )
            if rollbackResult.isOk:
              let externalChangePreserved =
                rollbackResult.get == rollbackSkippedExternalChange
              srcBuf.refreshRollbackFileMetadata(
                sourcePath, sourceWasExternallyModified or externalChangePreserved
              )
              if externalChangePreserved:
                e.state.statusMessage =
                  "Backup restore cancelled; source file changed externally"
              else:
                e.state.statusMessage =
                  "Backup restore rolled back after reload failure: " & textResult.error
            else:
              srcBuf.refreshRollbackFileMetadata(sourcePath, true)
              logError(
                "restore",
                "Failed to reload restored backup and roll back " & sourcePath & ": " &
                  textResult.error & "; rollback: " & rollbackResult.error,
              )
              e.state.statusMessage =
                "Restored but failed to reload or roll back: " & textResult.error
        # Refresh the list so the new safety backup is visible.
        bkState.refresh()
        activeWin.buffer = bkState.createBackupManagerTextBuffer()
        activeWin.cursor.line = min(bkState.selectedIndex + 1, activeWin.buffer.len - 1)
        activeWin.cursor.column = 0
      else:
        e.state.statusMessage = "Failed to restore backup"
    return true
  of hrBackupManagerDelete:
    # Delete the selected backup
    let backupIndex = r.deleteBackupIndex
    let activeWin = e.activeWindow
    if activeWin.modeState.kind == mskBackupManager:
      let bkState = activeWin.modeState.backupManager
      if bkState.deleteBackup(backupIndex):
        e.state.statusMessage = "Backup deleted"
        # Regenerate TextBuffer after deletion
        activeWin.buffer = bkState.createBackupManagerTextBuffer()
        activeWin.cursor.line = min(bkState.selectedIndex + 1, activeWin.buffer.len - 1)
        activeWin.cursor.column = 0
      else:
        e.state.statusMessage = "Failed to delete backup"
    return true
  of hrBackupManagerOpenDiff:
    # Open diff viewer for the selected backup
    let backupIndex = r.diffBackupIndex
    let activeWin = e.activeWindow
    if activeWin.modeState.kind == mskBackupManager:
      let bkState = activeWin.modeState.backupManager
      if backupIndex >= 0 and backupIndex < bkState.items.len:
        let entry = bkState.items[backupIndex]
        # Initialize diff viewer with source and backup paths
        let dvState = initDiffViewerState(bkState.sourceFilePath, entry.fullPath)
        # Suspend backup-manager mode and overlay the diff; both the swapped
        # buffer and the suspended (mode, modeState) must be restored on exit.
        activeWin.saveOriginalBuffer()
        activeWin.suspendMode()
        activeWin.buffer = dvState.createDiffTextBuffer()
        activeWin.cursor = BufferPosition(line: 0, column: 0)
        activeWin.viewport.resetViewportTop()
        activeWin.viewport.leftColumn = 0
        activeWin.modeState = ModeState(kind: mskDiffViewer, diffViewer: dvState)
        e.state.previousMode = e.state.mode
        e.setMode(EditorMode.DiffViewer)
        activeWin.mode = EditorMode.DiffViewer
        if dvState.errorMessage.len > 0:
          e.state.statusMessage = "Diff error: " & dvState.errorMessage
    return true
  else:
    return true # Not a backup-manager kind; caller misrouted (defensive)
