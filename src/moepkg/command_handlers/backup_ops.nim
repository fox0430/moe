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

import pkg/results

import
  ../[
    backup, backup_manager, buffer, diff_viewer, editor, editor_window_state, logger,
    types,
  ]

import handler_result

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
      if bkState.restoreBackup(backupIndex):
        # Take the safety backup after the restore so its cleanup can't delete
        # the entry being restored; the disk-only copy leaves srcBuf holding
        # the pre-restore content as the undo snapshot.
        discard
          backupBuffer(srcBuf.filePath, srcBuf.getFileContent(), e.config.autoBackup)
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
          e.state.statusMessage = "Restored but failed to reload: " & textResult.error
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
