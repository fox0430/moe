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

## HandlerResult processor: editor-level side effects driven by the result of
## a handler dispatch. Phase 4 of the KeyRouter refactor extracts this from
## handler.handleEvent so the entry point stays focused on event routing.
##
## This module currently contains one large `processResult` proc covering the
## full `case r.kind` and the trailing overlay/mode transition handling. A
## later phase can split it further into per-feature files (file_ops,
## window_ops, viewer_ops, lsp_ops, ...) without touching handler.nim again.

import std/[options, os, strutils, monotimes, tables, unicode]

import pkg/[results, chronos]

import
  ../[
    editor, editor_window_state, modes, buffer, logger, types, filer, filetree,
    buffer_manager, bookmark_manager, backup_manager, backup, diff_viewer,
    config_loader, lsp_service, message_log, uri_utils, primitives, syntax_checker,
    cursor_util, quick_run_utils, help_viewer, debug_viewer, config_mode, log_viewer,
    git_conflict, registers, setting_options, command_completion, key_bindings,
    key_router, window_manager, lsp_integration, viewer_mode,
  ]
import editor_ops, handler_result, handler_manager

type
  ReplayOutcome* = enum
    ## Outcome from a single replayed key, after full processResult side effects.
    roContinue
    roQuit ## hrQuit / hrCquit — main loop terminates
    roAbort ## hrError — statusMessage already set; loop stops, app continues

  OverlayPlaybackHook* = proc(e: Editor, keyCombo: KeyCombo): Option[bool] {.closure.}
    ## Playback overlay dispatch. `none` = no overlay, fall through; `some(true)`
    ## = handled, continue; `some(false)` = handled, requested app exit. Wired
    ## from handler.nim to avoid an import cycle (overlay handlers import here).

const ModesNeedingContext = {
  EditorMode.References, EditorMode.DocumentSymbol, EditorMode.CallHierarchy,
  EditorMode.DiffViewer,
}
  ## Modes that only make sense with a payload (an LSP response, a pair of
  ## files). A `mode_switch` keybinding naming one of these is rejected rather
  ## than entered with no listing to show.

var overlayPlaybackHook*: OverlayPlaybackHook = nil

proc executeCommandOverlay*(e: Editor, commandText: string): bool

proc modeSwitchEntry(mode: EditorMode): Option[HandlerResult] =
  ## Entry result for the modes a `mode_switch` keybinding can name that build
  ## a listing and mode state on entry. Flipping `EditorWindow.mode` alone
  ## would leave the window in a mode whose dispatcher has no state to work
  ## with, and no key — not even `:` — would be dispatched again.
  case mode
  of EditorMode.Filer:
    some(HandlerResult(kind: hrEnterFiler, enterFilerPath: none(string)))
  of EditorMode.BufferManager:
    some(HandlerResult(kind: hrEnterBufferManager))
  of EditorMode.BookmarkManager:
    some(HandlerResult(kind: hrEnterBookmarkManager))
  of EditorMode.Help:
    some(HandlerResult(kind: hrEnterHelpViewer))
  of EditorMode.LogViewer:
    some(HandlerResult(kind: hrEnterLogViewer))
  of EditorMode.BackupManager:
    some(HandlerResult(kind: hrEnterBackupManager))
  of EditorMode.RecentFile:
    some(HandlerResult(kind: hrRecentFile))
  of EditorMode.Debug:
    some(HandlerResult(kind: hrDebug))
  of EditorMode.Config:
    some(HandlerResult(kind: hrConfig))
  of EditorMode.Terminal:
    some(HandlerResult(kind: hrEnterTerminal, enterTerminalCommand: ""))
  of EditorMode.FileTree:
    some(HandlerResult(kind: hrEnterFileTree, enterFileTreePath: none(string)))
  else:
    none(HandlerResult)

proc processResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Apply the editor-level side effects implied by `r`. Returns true to
  ## continue the main loop, false to quit.

  # Process the result
  case r.kind
  of hrQuit:
    return false # Signal app should quit
  of hrCquit:
    e.state.exitCode = 1
    return false # Signal app should quit with non-zero exit code
  of hrSaveAndQuit:
    return e.processSaveAndQuitResult(r)
  of hrSaveAllAndQuit:
    return e.processSaveAllAndQuitResult(r)
  of hrGotoLine:
    e.processGotoLineResult(r, activeBuffer)
  of hrJumpToBuffer:
    # Handle jump to buffer with position (Ctrl-o/Ctrl-i across files)
    let targetIdx = e.bufferIndexById(r.jumpBufferId)
    let targetLine = r.jumpLine
    let targetCol = r.jumpColumn
    if targetIdx >= 0:
      e.switchToBufferByIndex(targetIdx)
      # Update cursor position after buffer switch
      let buf = e.activeBuffer()
      if buf.len > 0:
        e.activeWindow.cursor.line = min(targetLine, buf.len - 1)
        let line = buf.getLine(e.activeWindow.cursor.line)
        let lineCharLen = line.charLen
        e.activeWindow.cursor.column =
          if lineCharLen == 0:
            0
          else:
            min(targetCol, max(0, lineCharLen - 1))
      e.updateViewportForCursor(e.cursor)
    else:
      # Buffer was deleted since the jump was recorded
      e.state.statusMessage = "Buffer no longer available"
  of hrFilerOpenFile:
    # Open file from filer (Adds to the active window's per-window tab list)
    discard e.leaveViewerModeForJump(EditorMode.Filer)
    let editResult = e.editFile(r.filerFilePath)
    if editResult.isErr:
      e.state.statusMessage = "Error: " & editResult.error
    else:
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.notify("Opened: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file: " & r.filerFilePath)
    return true
  of hrFilerOpenFileVSplit:
    # Open file in vertical split from filer
    discard e.leaveViewerModeForJump(EditorMode.Filer)
    let splitResult = e.vsplit(some(r.filerFilePath))
    if splitResult.isErr:
      e.state.statusMessage = "Error: " & splitResult.error
    else:
      e.setMode(EditorMode.Normal)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.notify("Opened in vsplit: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file in vsplit: " & r.filerFilePath)
    return true
  of hrFilerOpenFileHSplit:
    # Open file in horizontal split from filer
    discard e.leaveViewerModeForJump(EditorMode.Filer)
    let splitResult = e.hsplit(some(r.filerFilePath))
    if splitResult.isErr:
      e.state.statusMessage = "Error: " & splitResult.error
    else:
      e.setMode(EditorMode.Normal)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.notify("Opened in hsplit: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file in hsplit: " & r.filerFilePath)
    return true
  of hrFilerQuit:
    e.leaveViewerMode(EditorMode.Filer)
    return true
  of hrTerminalQuit:
    # Close the Terminal tab in the active window. closeTerminalBuffer
    # picks a successor tab (or spawns a No Name buffer) and resets the
    # window's mode to Normal.
    e.closeTerminalBuffer(e.activeWindow.buffer.id)
    return true
  of hrFileTreeOpenFile:
    # Open file from file tree in the first non-FileTree window.
    # If the FileTree is the only window, open the file in a new window
    # placed to the right of the FileTree.
    var targetWinIdx = -1
    for i, win in e.windowManager.windows:
      if win.mode != EditorMode.FileTree:
        targetWinIdx = i
        break

    # Reveal the opened file in the file tree (order-independent iteration)
    for win in e.windowManager.windows:
      if win.mode == EditorMode.FileTree and win.modeState.kind == mskFileTree:
        win.modeState.fileTree.revealPath(r.fileTreeFilePath)
        break

    if targetWinIdx >= 0:
      # Switch to the target window and open the file
      # editFile adds to the buffer list without discarding unsaved changes
      e.windowManager.activateWindow(targetWinIdx)
      e.syncActiveWindow()
      let editResult = e.editFile(r.fileTreeFilePath)
      if editResult.isErr:
        e.state.statusMessage = "Error: " & editResult.error
      else:
        e.state.statusMessage = "Opened: " & r.fileTreeFilePath
    else:
      # FileTree is the only window: create a new window on its right
      let openResult = e.openFileInNewRightWindow(r.fileTreeFilePath)
      if openResult.isErr:
        e.state.statusMessage = "Error: " & openResult.error
      else:
        e.state.statusMessage = "Opened: " & r.fileTreeFilePath
    return true
  of hrFileTreeQuit:
    # Close file tree window
    e.activeWindow.clearModeState(EditorMode.FileTree)
    # Remove file tree window and redistribute space
    let shouldQuit = e.closeWindow()
    if shouldQuit:
      let enewResult = e.enew()
      if enewResult.isErr:
        logError("handler", "Enew failed after file tree quit: " & enewResult.error)
        e.state.statusMessage = "Error: " & enewResult.error
    return true
  of hrFilerDeleteFile:
    # Delete file/directory from filer
    let activeWin = e.activeWindow
    if activeWin.modeState.kind == mskFiler:
      let deleteResult = activeWin.modeState.filer.deleteSelected()
      if deleteResult.success:
        # File/directory deleted successfully
        if e.config.notification.screenNotifications and
            e.config.notification.filerScreenNotify:
          e.notify("Deleted: " & deleteResult.path)
        if e.config.notification.logNotifications and
            e.config.notification.filerLogNotify:
          logInfo("filer", "Deleted: " & deleteResult.path)
      else:
        # Deletion failed
        e.state.statusMessage = "Delete failed: " & deleteResult.error
        logError("filer", "Delete failed: " & deleteResult.error)
    return true
  of hrFilerShowInfo:
    # Show file information in status line
    e.state.statusMessage = r.filerFileInfo
    return true
  of hrLogViewerQuit:
    e.leaveViewerMode(EditorMode.LogViewer)
    return true
  of hrLogViewerRefresh:
    # Refresh log viewer content by creating new buffer with updated content
    let activeWin = e.activeWindow
    if activeWin.modeState.kind == mskLogViewer:
      let logLines =
        case activeWin.modeState.logViewer.contentKind
        of lckEditor:
          getMessageLog()
        of lckLsp:
          getLspMessageLog()
      let logContent =
        if logLines.len > 0:
          logLines.join("\n")
        else:
          ""
      # Create new buffer with updated content
      let newBuffer = newTextBuffer(logContent)
      newBuffer.readOnly = true
      # Replace the window's buffer
      activeWin.buffer = newBuffer
      # Clamp cursor if needed
      let maxLine = max(0, newBuffer.len - 1)
      if e.activeWindow.cursor.line > maxLine:
        e.activeWindow.cursor.line = maxLine
      e.state.statusMessage = "Log refreshed"
    return true
  of hrHelpViewerQuit:
    e.leaveViewerMode(EditorMode.Help)
    return true
  of hrReferencesQuit:
    e.leaveViewerMode(EditorMode.References)
    return true
  of hrReferencesJumpTo:
    # Jump to selected reference. Restore the pre-viewer cursor first so the
    # jump list anchors at the original position (enabling jump-back).
    let win = e.activeWindow
    let openWindow =
      win.modeState.kind == mskReferences and win.modeState.references.openWindowOnJump
    let entry = e.leaveViewerModeForJump(EditorMode.References)
    if entry.isSome:
      win.cursor = entry.get.originCursor
    discard e.openFileAndJumpTo(r.jumpToPath, r.jumpToLine, r.jumpToColumn, openWindow)
    return true
  of hrDocumentSymbolQuit:
    e.leaveViewerMode(EditorMode.DocumentSymbol)
    return true
  of hrDocumentSymbolJumpTo:
    # Jump to selected symbol (same file). Restore the pre-viewer cursor first
    # so the jump list anchors at the original position (enabling jump-back).
    let activeWin = e.activeWindow
    let filePath =
      if activeWin.modeState.kind == mskDocumentSymbol:
        activeWin.modeState.documentSymbol.filePath
      else:
        ""
    let entry = e.leaveViewerModeForJump(EditorMode.DocumentSymbol)
    if entry.isSome:
      activeWin.cursor = entry.get.originCursor
    if filePath.len > 0:
      discard e.openFileAndJumpTo(filePath, r.symbolLine, r.symbolColumn)
    return true
  of hrCallHierarchyQuit:
    cancelAllCallHierarchy(e)
    e.leaveViewerMode(EditorMode.CallHierarchy)
    return true
  of hrCallHierarchyJumpTo:
    # Jump to selected call hierarchy item. Restore the pre-viewer cursor first
    # so the jump list anchors at the original position (enabling jump-back).
    let path = lsp_service.uriToPath(r.callHierarchyJumpUri)
    cancelAllCallHierarchy(e)
    let win = e.activeWindow
    let entry = e.leaveViewerModeForJump(EditorMode.CallHierarchy)
    win.cursor =
      if entry.isSome:
        entry.get.originCursor
      else:
        BufferPosition(line: 0, column: 0)
    discard
      e.openFileAndJumpTo(path, r.callHierarchyJumpLine, r.callHierarchyJumpColumn)
    return true
  of hrCallHierarchyRequestIncoming:
    # Request incoming calls for selected item
    discard e.requestCallHierarchyIncomingForItem(r.callHierarchyIncomingItem)
    return true
  of hrCallHierarchyRequestOutgoing:
    # Request outgoing calls for selected item
    discard e.requestCallHierarchyOutgoingForItem(r.callHierarchyOutgoingItem)
    return true
  of hrBufferManagerQuit:
    e.leaveViewerMode(EditorMode.BufferManager)
    return true
  of hrBufferManagerSelectBuffer:
    # Select the buffer and switch to it
    let bufferIndex = r.selectBufferIndex
    discard e.leaveViewerModeForJump(EditorMode.BufferManager)
    if bufferIndex >= 0 and bufferIndex < e.buffers.len:
      e.switchToBufferByIndex(bufferIndex)
    return true
  of hrBufferManagerDeleteBuffer:
    # Delete the buffer from the buffer list
    let bufferIndex = r.deleteBufferIdx
    if e.buffers.len > 1:
      # Can only delete if there's more than one buffer
      if bufferIndex >= 0 and bufferIndex < e.buffers.len:
        let deletedBuffer = e.removeBufferAt(bufferIndex)
        let deletedId = deletedBuffer.id

        # The outer `if e.buffers.len > 1` guarantees `e.buffers.len >= 1` here.
        let newBuf = e.buffers[min(bufferIndex, e.buffers.len - 1)]
        e.redirectWindowsFromBuffer(deletedBuffer, newBuf)

        # Update executor if current buffer was deleted
        if e.activeBuffer() != e.motionController.buffer:
          e.motionController.setBuffer(e.activeBuffer())

        # Keep state.windowDisplay.currentBufferId off the deleted buffer so subsequent
        # Jump List (Ctrl-o/Ctrl-i) compares don't false-match a dead id.
        # We don't go through syncActiveWindow here because the BufferManager
        # overlay is about to replace activeWindow.buffer with its own listing
        # TextBuffer right below — pointing currentBufferId at the underlying
        # replacement buffer is what we want for the post-exit state.
        if e.state.windowDisplay.currentBufferId == deletedId:
          e.state.windowDisplay.currentBufferId = newBuf.id

        # Update buffer manager entries and regenerate TextBuffer
        let activeWin = e.activeWindow
        if activeWin.modeState.kind == mskBufferManager:
          let bmState = activeWin.modeState.bufferManager
          bmState.updateEntries(e.getBufferInfos())
          activeWin.buffer = bmState.createBufferManagerTextBuffer()
          activeWin.cursor.line =
            min(bmState.selectedIndex + 1, activeWin.buffer.len - 1)
          activeWin.cursor.column = 0
    else:
      # Cannot delete the only buffer
      e.state.statusMessage = "Cannot delete the last buffer"
    return true
  of hrBookmarkManagerQuit:
    e.leaveViewerMode(EditorMode.BookmarkManager)
    return true
  of hrBookmarkManagerJump:
    # Resolve BufferId at jump time to survive buffer-list mutations.
    let jumpLine = r.bookmarkJumpLine
    discard e.leaveViewerModeForJump(EditorMode.BookmarkManager)
    let bufferIndex = e.bufferIndexById(r.bookmarkJumpBufferId)
    if bufferIndex >= 0:
      e.switchToBufferByIndex(bufferIndex)
      let buf = e.activeBuffer()
      let clampedLine = min(jumpLine, max(0, buf.len - 1))
      e.activeWindow.cursor = BufferPosition(line: clampedLine, column: 0)
      e.activeWindow.viewport.resetViewportTop(max(0, clampedLine - 5))
    return true
  of hrBookmarkManagerDelete:
    # Delete the bookmark and refresh
    let activeWin = e.activeWindow
    if activeWin.modeState.kind == mskBookmarkManager:
      let bmState = activeWin.modeState.bookmarkManager
      bmState.deleteSelectedBookmark(e.buffers)
      activeWin.buffer = bmState.createBookmarkManagerTextBuffer()
      activeWin.cursor.line = min(bmState.selectedIndex + 1, activeWin.buffer.len - 1)
      activeWin.cursor.column = 0
    return true
  of hrBackupManagerQuit:
    e.leaveViewerMode(EditorMode.BackupManager)
    return true
  of hrDiffViewerQuit:
    # Close the diff viewer overlay and resume the mode it was opened from.
    # Take the suspended (mode, modeState) before clearModeState — which clears
    # any leftover suspension as part of teardown — then re-install it as one
    # consistent pair. clearModeState restores the swapped buffer and resets the
    # live variant to mskNone. The selection cursor is re-placed by
    # syncSelectionCursor on the next render.
    let activeWin = e.activeWindow
    let suspended = activeWin.takeSuspendedMode()
    activeWin.clearModeState(EditorMode.DiffViewer)
    if suspended.isSome:
      activeWin.mode = suspended.get.mode
      activeWin.modeState = suspended.get.modeState
    else:
      # Nothing was suspended: fall back to a stateless mode so mode and
      # modeState stay consistent (a stateful mode left with mskNone state
      # would make the dispatcher reject every key).
      activeWin.mode = EditorMode.Normal
    # Reset cursor/viewport to the top of the restored (small) buffer, mirroring
    # the diff-entry reset. The diff may have scrolled far past the restored
    # buffer's length, so this prevents a stale off-screen viewport; the resumed
    # selection mode re-places the cursor via syncSelectionCursor on render.
    activeWin.cursor = BufferPosition(line: 0, column: 0)
    activeWin.viewport.resetViewportTop()
    activeWin.viewport.leftColumn = 0
    return true
  of hrConfigQuit:
    # Close config mode and return to previous mode
    let activeWin = e.activeWindow
    # Flush any pending config apply before wiping the config mode state.
    # The outer handleEvent's pendingApply check runs after processResult,
    # so a mapping RHS that both mutates a value and exits Config in one
    # event (e.g. `:map <F5> togglekey ZQ`) would otherwise lose the change.
    if activeWin.modeState.kind == mskConfig and activeWin.modeState.config.pendingApply:
      e.applyConfigSettings(e.config)
    e.leaveViewerMode(EditorMode.Config)
    return true
  of hrConfigSaveConfig:
    # Save configuration to TOML file
    let configPath = getConfigPath()

    # Backup existing config file if it exists
    if fileExists(configPath):
      let backupPath = configPath & ".bac"
      try:
        copyFile(configPath, backupPath)
        logInfo("config", "Backed up existing config to: " & backupPath)
      except CatchableError as ex:
        e.state.statusMessage = "Failed to backup config: " & ex.msg
        logError("config", "Failed to backup config: " & ex.msg)
        return true

    let saveResult = saveConfig(e.config)
    if saveResult.isOk:
      e.state.statusMessage = "Config saved: " & configPath
      logInfo("config", "Config saved: " & configPath)
    else:
      e.state.statusMessage = "Failed to save config: " & saveResult.error
      logError("config", "Failed to save config: " & saveResult.error)
    return true
  of hrPutConfigFile:
    # Write current configuration to file (:putConfigFile)
    let configPath = getConfigPath()

    # Backup existing config file if it exists
    if fileExists(configPath):
      let backupPath = configPath & ".bac"
      try:
        copyFile(configPath, backupPath)
        logInfo("config", "Backed up existing config to: " & backupPath)
      except CatchableError as ex:
        e.state.statusMessage = "Error: Failed to backup config: " & ex.msg
        logError("config", "Failed to backup config: " & ex.msg)
        e.setMode(EditorMode.Normal)
        return true

    let saveResult = saveConfig(e.config)
    if saveResult.isOk:
      e.state.statusMessage = "Config written: " & configPath
      logInfo("config", "Config written: " & configPath)
    else:
      e.state.statusMessage = "Failed to write config: " & saveResult.error
      logError("config", "Failed to write config: " & saveResult.error)
    e.setMode(EditorMode.Normal)
    return true
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
      # The backup manager runs in its own split, so the active buffer is the
      # backup-list view (no file path), not the file being restored. Operate
      # on the source buffer located by `bkState.sourceFilePath`.
      let sourcePath = bkState.sourceFilePath
      let srcIdx =
        if sourcePath.len > 0:
          e.findBufferByPath(sourcePath)
        else:
          -1
      if srcIdx < 0:
        # Without the source buffer we can neither take a pre-restore safety
        # backup nor reload the new content, so refuse rather than silently
        # overwrite the file on disk with no undo path.
        e.state.statusMessage = "Cannot restore: source buffer not found"
        return true
      let srcBuf = e.buffers[srcIdx]
      if bkState.restoreBackup(backupIndex):
        # Take the pre-restore safety backup *after* the restore copy. Its
        # cleanup of old backups must not delete the very entry being restored
        # (which it could, when the backup count is at the cap and the oldest
        # entry is the selected one). The restore is a disk-only copy, so
        # srcBuf's in-memory content is still the pre-restore content here and
        # is captured faithfully for undo.
        discard
          backupBuffer(srcBuf.filePath, srcBuf.getFileContent(), e.config.autoBackup)
        # Reload the source buffer from the restored file on disk
        let textResult = srcBuf.loadFile(sourcePath)
        if textResult.isOk:
          # didChange the source buffer on the server. The periodic LSP sync
          # (maybeUpdateLsp) only covers the active buffer, but the restored
          # buffer lives in another split, so without this the server's copy
          # and its pushed diagnostics stay stale until that window is focused.
          e.syncBufferAfterEdit(srcBuf, "restore")
          # The restored file may be shorter than before; re-clamp every
          # window's cursor (the source buffer is shown in another split) so a
          # stale out-of-bounds cursor can't be observed before the next motion.
          e.clampAllWindowCursors()
          # The restored content differs from before, so refresh the source
          # buffer's git-diff gutter and conflict markers (it is shown in
          # another split) the same way the reload paths do.
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
        # Refresh the backup list and regenerate its view buffer so the new
        # safety backup is actually visible, mirroring the refresh/delete
        # handlers (a bare `refresh()` leaves the rendered list stale).
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
        # Save original buffer and suspend the backup-manager mode, then
        # replace with diff content. The diff viewer is a transient overlay
        # over the backup manager; both the swapped buffer and the suspended
        # (mode, modeState) must be restored on exit.
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
  of hrLspGotoDefinition:
    discard e.requestLspGotoDefinition()
    return true
  of hrLspGotoDeclaration:
    discard e.requestLspGotoDeclaration()
    return true
  of hrLspFindReferences:
    discard e.requestLspReferences()
    return true
  of hrLspDocumentSymbol:
    discard e.startLspDocumentSymbols()
    return true
  of hrLspCodeLensExecute:
    asyncSpawn e.executeCurrentLineCodeLens()
    return true
  of hrLspCallHierarchyIncoming:
    discard e.requestLspCallHierarchyIncoming()
    return true
  of hrLspCallHierarchyOutgoing:
    discard e.requestLspCallHierarchyOutgoing()
    return true
  of hrLspTypeDefinition:
    discard e.requestLspTypeDefinition()
    return true
  of hrLspImplementation:
    discard e.requestLspImplementation()
    return true
  of hrLspHover:
    discard e.requestLspHover()
    return true
  of hrLspRename:
    # Enter Rename mode for user input
    if not e.lsp.enabled:
      e.state.statusMessage = "LSP not enabled"
      return true

    # Check if rename is supported
    if not e.lsp.hasRenameSupport(activeBuffer):
      e.state.statusMessage = "Rename not supported"
      return true

    # Get the word under cursor
    let word = activeBuffer.getWordAtPosition(e.cursor)
    if word.len == 0:
      e.state.statusMessage = "No symbol under cursor"
      return true

    # Initialize rename overlay
    e.state.enterRenameOverlay(
      word, e.activeWindow.cursor.line, e.activeWindow.cursor.column
    )
    e.state.statusMessage = ""
    return true
  of hrLspSelectionRange:
    discard e.requestLspSelectionRange()
    return true
  of hrLspDocumentLink:
    discard e.requestLspDocumentLinks()
    return true
  of hrLspFormat:
    discard e.requestLspFormat()
    return true
  of hrLspRestart:
    discard e.restartLspServer()
    return true
  of hrLspFold:
    asyncSpawn e.refreshLspFolds()
    return true
  of hrLspExecuteCommand:
    asyncSpawn e.requestLspExecuteCommand(r.hrLspCommand, r.hrLspCommandArgs)
    return true
  of hrOpenUri:
    let uri = r.openUri
    if isLocalFileUri(uri):
      let path = fileUriToPath(uri)
      if e.openFileAndJumpTo(path, 0, 0):
        e.state.statusMessage = "Opened: " & path.extractFilename
      else:
        e.state.statusMessage = "Failed to open: " & path
    elif isExternalUri(uri):
      if openExternalUri(uri):
        e.state.statusMessage = "Opened: " & uri
      else:
        e.state.statusMessage = "Failed to open: " & uri
    else:
      # Plain file path - resolve relative to current buffer's directory
      let activeBufferLocal = e.activeBuffer()
      let basePath =
        if activeBufferLocal.filePath.isSome:
          activeBufferLocal.filePath.get.parentDir
        else:
          getCurrentDir()
      let resolvedPath = basePath / uri
      if e.openFileAndJumpTo(resolvedPath, 0, 0):
        e.state.statusMessage = "Opened: " & resolvedPath.extractFilename
      else:
        e.state.statusMessage = "Failed to open: " & resolvedPath
    return true
  of hrBufferNext:
    e.switchToNextBuffer()
  of hrBufferPrev:
    e.switchToPrevBuffer()
  of hrBufferFirst:
    e.switchToFirstBuffer()
  of hrBufferLast:
    e.switchToLastBuffer()
  of hrBuffer:
    discard e.switchToBuffer(r.bufferArg)
  of hrHandled, hrUnhandled:
    discard # Fall through to post-processing
  of hrError:
    e.state.statusMessage = r.errorMessage
  of hrCloseWindow:
    let activeWin = e.activeWindow
    if e.terminalStates.hasKey(activeWin.buffer.id):
      e.closeTerminalBuffer(activeWin.buffer.id)
    let shouldQuit = e.closeWindow()
    if shouldQuit:
      return false
  of hrNextWindow:
    e.switchToNextWindow()
  of hrPrevWindow:
    e.switchToPrevWindow()
  of hrIncreaseWindowHeight:
    e.increaseWindowHeight()
  of hrDecreaseWindowHeight:
    e.decreaseWindowHeight()
  of hrIncreaseWindowWidth:
    e.increaseWindowWidth()
  of hrDecreaseWindowWidth:
    e.decreaseWindowWidth()
  of hrEqualizeWindows:
    e.equalizeWindowSizes()
  of hrSwapWindow:
    e.swapWindow()
  of hrEnew:
    let enewResult = e.enew()
    if enewResult.isErr:
      logError("handler", "Enew failed: " & enewResult.error)
      e.state.statusMessage = "Error: " & enewResult.error
  of hrEnterFiler:
    # Tear the active viewer down so startPath resolves from the file under
    # it, not the listing. When a split teardown surfaces another viewer as
    # active, its originalBuffer still holds the user's file.
    e.closeLiveViewer()
    let win = e.activeWindow
    let originBuffer =
      if win.viewerEntry.isSome and win.originalBuffer != nil:
        win.originalBuffer
      else:
        win.buffer
    let startPath =
      if r.enterFilerPath.isSome:
        r.enterFilerPath.get
      elif originBuffer.filePath.isSome:
        parentDir(originBuffer.filePath.get)
      else:
        getCurrentDir()
    e.enterFilerInActiveWindow(startPath)
  of hrEnterFileTree:
    let activeBufLocal = e.activeBuffer()
    e.toggleFileTree(r.enterFileTreePath, activeBufLocal)
  of hrBufferDelete:
    e.deleteCurrentBuffer()
  of hrExecCommand:
    # @: - repeat last Command mode command via the shared overlay wrapper.
    let count = r.execCommandCount
    let commandText = ":" & r.execCommandText
    for i in 0 ..< count:
      if not e.executeCommandOverlay(commandText):
        return false
  of hrQuickRun:
    # Prepare QuickRun (sync) and set pending for async execution. Mirrors
    # command_mode_handler.nim's hrQuickRun branch so Normal mode keybindings
    # (e.g. \r) reach the same execution path as `:quickrun`.
    let prepareResult = prepareQuickRun(activeBuffer, e.config)
    if prepareResult.isErr:
      e.state.statusMessage = "QuickRun error: " & prepareResult.error
      logError("handler", "QuickRun prepare failed: " & prepareResult.error)
    else:
      let prepared = prepareResult.get
      e.state.pending.add PendingAsyncOp(
        kind: paoQuickRun,
        quickRun: (
          cmd: prepared.command.cmd,
          args: prepared.command.args,
          filePath: prepared.filePath,
          isTempFile: prepared.isTempFile,
        ),
      )
      if e.config.notification.screenNotifications and
          e.config.notification.quickRunScreenNotify:
        e.state.statusMessage = quickRunStartupMessage(prepared.filePath)
  of hrSave:
    e.processSaveResult(r, activeBuffer)
  of hrSaveAll:
    e.processSaveAllResult(r)
  of hrVSplit:
    let expandedVsplit =
      if r.vsplitFilename.isSome:
        some(expandTilde(r.vsplitFilename.get))
      else:
        none(string)
    let filerPath =
      if expandedVsplit.isSome and dirExists(expandedVsplit.get):
        some(absolutePath(expandedVsplit.get))
      else:
        none(string)
    let splitFilename =
      if filerPath.isSome:
        none(string)
      else:
        expandedVsplit
    let splitResult = e.vsplit(splitFilename)
    if splitResult.isErr:
      logError("handler", "Vertical split failed: " & splitResult.error)
      e.state.statusMessage = "Error: " & splitResult.error
    elif filerPath.isSome:
      e.enterFilerInActiveWindow(filerPath.get)
  of hrHSplit:
    let expandedHsplit =
      if r.hsplitFilename.isSome:
        some(expandTilde(r.hsplitFilename.get))
      else:
        none(string)
    let filerPath =
      if expandedHsplit.isSome and dirExists(expandedHsplit.get):
        some(absolutePath(expandedHsplit.get))
      else:
        none(string)
    let splitFilename =
      if filerPath.isSome:
        none(string)
      else:
        expandedHsplit
    let splitResult = e.hsplit(splitFilename)
    if splitResult.isErr:
      logError("handler", "Horizontal split failed: " & splitResult.error)
      e.state.statusMessage = "Error: " & splitResult.error
    elif filerPath.isSome:
      e.enterFilerInActiveWindow(filerPath.get)
  of hrNew:
    let newResult = e.new()
    if newResult.isErr:
      logError("handler", "New failed: " & newResult.error)
      e.state.statusMessage = "Error: " & newResult.error
  of hrVnew:
    let vnewResult = e.vnew()
    if vnewResult.isErr:
      logError("handler", "Vnew failed: " & vnewResult.error)
      e.state.statusMessage = "Error: " & vnewResult.error
  of hrEdit:
    if r.editFilename.isSome:
      let editResult = e.editFile(r.editFilename.get)
      if editResult.isErr:
        logError("handler", "Edit failed: " & editResult.error)
        e.state.statusMessage = "Error: " & editResult.error
      else:
        e.state.statusMessage = "Opened: " & r.editFilename.get
    else:
      let reloadResult = e.reloadCurrentFile()
      if reloadResult.isErr:
        logError("handler", "Reload failed: " & reloadResult.error)
        e.state.statusMessage = "Error: " & reloadResult.error
  of hrSetBoolOption:
    let opt = r.boolOption
    let val = r.boolValue
    case opt
    of bsoNumber:
      e.config.standard.number = val
      e.state.statusMessage = "number = " & $val
    of bsoRelativeNumber:
      e.config.standard.relativeNumber = val
      e.state.statusMessage = "relativenumber = " & $val
    of bsoCursorLine:
      e.config.highlight.currentLine = val
      e.state.statusMessage = "cursorline = " & $val
    of bsoCursorColumn:
      e.config.highlight.currentColumn = val
      e.state.statusMessage = "cursorcolumn = " & $val
    of bsoStatusLine:
      e.config.standard.statusLine = val
      e.state.statusMessage = "statusline = " & $val
    of bsoSyntax:
      e.config.standard.syntax = val
      e.state.statusMessage = "syntax = " & $val
    of bsoIndentationLines:
      e.config.standard.indentationLines = val
      e.state.statusMessage = "indentationlines = " & $val
    of bsoAutoIndent:
      e.config.standard.autoIndent = val
      e.state.statusMessage = "autoindent = " & $val
    of bsoAutoCloseParen:
      e.config.standard.autoCloseParen = val
      e.state.statusMessage = "autocloseparen = " & $val
    of bsoAutoDeleteParen:
      e.config.standard.autoDeleteParen = val
      e.state.statusMessage = "autodeleteparen = " & $val
    of bsoClipboard:
      e.config.clipboard.enable = val
      e.state.statusMessage = "clipboard = " & $val
    of bsoSmoothScroll:
      e.config.smoothScroll.enable = val
      e.state.statusMessage = "smoothscroll = " & $val
    of bsoLiveReloadOfConf:
      e.config.standard.liveReloadOfConf = val
      e.state.statusMessage = "livereload = " & $val
    of bsoShowIcons:
      e.config.filer.showIcons = val
      e.state.statusMessage = "icon = " & $val
    of bsoHighlightCurrentLine:
      e.config.highlight.currentLine = val
      e.state.statusMessage = "highlightcurrentline = " & $val
    of bsoHighlightCurrentWord:
      e.config.highlight.currentWord = val
      e.state.statusMessage = "highlightcurrentword = " & $val
    of bsoHighlightFullWidthSpace:
      e.config.highlight.fullWidthSpace = val
      e.state.statusMessage = "highlightfullspace = " & $val
    of bsoHighlightPairOfParen:
      e.config.highlight.pairOfParen = val
      e.state.statusMessage = "highlightparen = " & $val
    of bsoHighlightFindChar:
      e.config.highlight.findCharHighlight = val
      e.state.statusMessage = "highlightfindchar = " & $val
    of bsoHighlightColorCode:
      e.config.highlight.colorCodeHighlight = val
      e.state.statusMessage = "highlightcolorcode = " & $val
    of bsoHighlightGitConflict:
      e.config.highlight.gitConflict = val
      e.state.statusMessage = "highlightgitconflict = " & $val
    of bsoHighlightGitConflictTwoColor:
      e.config.highlight.gitConflictTwoColor = val
      e.state.statusMessage = "highlightgitconflicttwocolor = " & $val
    of bsoMultipleStatusLine:
      e.config.statusLine.multipleStatusLine = val
      e.state.statusMessage = "multiplestatusline = " & $val
    of bsoIgnoreCase:
      e.state.ignorecase = val
      e.state.statusMessage = "ignorecase = " & $val
    of bsoSmartCase:
      e.state.smartcase = val
      e.state.statusMessage = "smartcase = " & $val
    of bsoIncSearch:
      e.state.incsearch = val
      e.state.statusMessage = "incsearch = " & $val
    of bsoHlSearch:
      e.state.input.search.hlsearch = val
      e.state.statusMessage = "hlsearch = " & $val
    of bsoBuildOnSave:
      e.config.buildOnSave.enable = val
      e.state.statusMessage = "buildonsave = " & $val
    of bsoShowGitInactive:
      e.config.statusLine.showGitInactive = val
      e.state.statusMessage = "showgitinactive = " & $val
    of bsoLineWrap:
      e.config.standard.lineWrap = val
      e.state.statusMessage = "wrap = " & $val
    of bsoExpandTab:
      e.state.expandTab = val
      e.state.statusMessage = "expandtab = " & $e.state.expandTab
    of bsoScrollbar:
      e.config.standard.scrollbar = val
      e.state.statusMessage = "scrollbar = " & $val
  of hrSetIntOption:
    let opt = r.intOption
    let val = r.intValue
    case opt
    of isoTabStop:
      e.state.tabStop = val
      e.state.statusMessage = "tabstop = " & $e.state.tabStop
    of isoShiftWidth:
      e.state.shiftWidth = val
      e.state.statusMessage = "shiftwidth = " & $e.state.shiftWidth
    of isoSoftTabStop:
      e.config.standard.softTabStop = val
      e.state.statusMessage = "softtabstop = " & $val
    of isoScrollbarWidth:
      e.config.standard.scrollbarWidth = val
      e.state.statusMessage = "scrollbarwidth = " & $val
  of hrSetFloatOption:
    let opt = r.floatOption
    let val = r.floatValue
    case opt
    of fsoScrollFriction:
      e.config.smoothScroll.friction = val
      e.state.statusMessage = "scrollfriction = " & $val
    of fsoScrollAirDrag:
      e.config.smoothScroll.airDrag = val
      e.state.statusMessage = "scrollairdrag = " & $val
  of hrClearSearchHighlight:
    e.state.input.search.hlsearch = false
  of hrStripWhitespace:
    let count = r.strippedLineCount
    if count > 0:
      e.state.statusMessage = "Stripped trailing whitespace from " & $count & " lines"
    else:
      e.state.statusMessage = "No trailing whitespace found"
  of hrShellCommand:
    e.state.pending.add PendingAsyncOp(kind: paoShellCommand, command: r.shellCommand)
  of hrBackground:
    e.state.pending.add PendingAsyncOp(kind: paoBackground)
  of hrMan:
    e.state.pending.add PendingAsyncOp(kind: paoManPage, command: r.hrManPage)
  of hrSubstitute:
    let count = r.hrSubstituteCount
    e.state.statusMessage = $count & " substitution" & (if count == 1: "" else: "s")
  of hrDeleteLines:
    e.state.registers.setDeletedRegister(r.hrDeletedText, true)
    let count = r.hrDeletedLineCount
    e.state.statusMessage =
      $count & " line" & (if count == 1: "" else: "s") & " deleted"
    let maxLine = e.activeBuffer().len - 1
    if e.activeWindow.cursor.line > maxLine:
      e.activeWindow.cursor.line = maxLine
    e.activeWindow.cursor.column = 0
  of hrBuild:
    let filePath = if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: ""
    if filePath.len == 0:
      e.state.statusMessage = "Build error: File not saved"
      logError("handler", "Build failed: No file path")
    else:
      e.state.pending.add PendingAsyncOp(
        kind: paoBuild,
        build: (
          path: filePath,
          language: activeBuffer.language.ord,
          customCmd: "",
          workspaceRoot: parentDir(filePath),
        ),
      )
      e.state.statusMessage = "Building: " & filePath
  of hrDebug:
    if e.focusExistingViewerWindow(EditorMode.Debug):
      return true
    var debugLines: seq[string] = @[]
    let debugConfig = e.config.debug
    for i, window in e.windowManager.windows:
      generateWindowInfo(
        debugLines,
        i,
        i == e.windowManager.activeWindowIndex,
        e.bufferIndexById(window.buffer.id),
        window.viewport.x,
        window.viewport.y,
        window.viewport.width,
        window.viewport.height,
        window.viewport.topLine,
        window.viewport.leftColumn,
        window.cursor.line,
        window.cursor.column,
        debugConfig.windowNode.enable,
      )
    for i, buf in e.buffers:
      generateBufferInfo(
        debugLines,
        i,
        buf.filePath,
        buf.isModified,
        buf.readOnly,
        $buf.language,
        $buf.encoding,
        buf.len,
        buf.changeSeq,
        debugConfig.bufferStatus.enable,
      )
    generateEditorStateInfo(
      debugLines, e.state.mode, e.state.previousMode, e.activeWindow.cursor.line,
      e.activeWindow.cursor.column, e.state.input.commandText, e.state.statusMessage,
      debugConfig.editorView.enable,
    )
    generateSearchInfo(
      debugLines,
      e.state.input.search.text,
      e.state.input.search.lastText,
      $e.state.input.search.direction,
      e.state.input.search.history.len,
      e.state.input.search.ignorecase,
      e.state.input.search.smartcase,
      e.state.input.search.incsearch,
      e.state.input.search.hlsearch,
      debugConfig.search.enable,
    )
    generateDisplayInfo(
      debugLines, e.showStatusLine, e.multiStatusLine, e.showLineNumbers,
      e.showCursorLine, e.showSyntax, e.showIndentationLines, e.showSidebar,
      e.scrollbarWidth, e.showModifiedLines, e.lineWrap, e.tabStop,
      debugConfig.editorView.enable,
    )
    generateMacroInfo(
      debugLines, e.state.pendingInput.macroState.isRecording,
      e.state.pendingInput.macroState.register,
      e.state.pendingInput.macroState.registers.len,
      e.state.pendingInput.macroState.playbackDepth, debugConfig.macroState.enable,
    )
    generateVisualInfo(
      debugLines,
      e.state.visualSelection.active,
      $e.state.visualSelection.kind,
      e.state.visualSelection.start.line,
      e.state.visualSelection.start.column,
      e.state.visualSelection.current.line,
      e.state.visualSelection.current.column,
      debugConfig.visual.enable,
    )
    generateJumpListInfo(
      debugLines, e.state.jumpList.list.len, e.state.jumpList.index,
      debugConfig.jumpList.enable,
    )
    generateLspInfo(
      debugLines, e.state.lspCache.codeLensCache.itemsByLine.len,
      e.state.lspCache.locations.isSome, e.state.lspCache.codeLensCache.isValid,
      debugConfig.lsp.enable,
    )
    let debugState = newDebugViewerState()
    debugState.items = debugLines
    let debugBuffer = debugState.createDebugTextBuffer()
    let enterResult = e.enterViewerMode(
      EditorMode.Debug,
      ModeState(kind: mskDebug, debug: debugState),
      debugBuffer,
      vpVSplit,
    )
    if enterResult.isErr:
      e.state.statusMessage = "Failed to open debug: " & enterResult.error
    else:
      e.state.statusMessage = "Debug info (auto-refresh)"
      e.state.windowDisplay.debugBuffer = debugBuffer
      e.state.timing.lastDebugUpdate = getMonoTime()
      if e.state.timing.debugUpdateInterval == 0:
        e.state.timing.debugUpdateInterval = 500
  of hrConfig:
    if e.focusExistingViewerWindow(EditorMode.Config):
      return true
    let configBuffer = newTextBuffer("")
    configBuffer.readOnly = true
    let enterResult = e.enterViewerMode(
      EditorMode.Config,
      ModeState(kind: mskConfig, config: newConfigModeState(e.config)),
      configBuffer,
      vpVSplit,
    )
    if enterResult.isErr:
      e.state.statusMessage = "Failed to open config: " & enterResult.error
  of hrTheme:
    e.applyThemeCommand(r.hrThemeName)
  of hrLspLog:
    if e.focusExistingViewerWindow(EditorMode.LogViewer):
      return true
    let logLines = getLspMessageLog()
    let logContent =
      if logLines.len > 0:
        logLines.join("\n")
      else:
        ""
    let logBuffer = newTextBuffer(logContent)
    logBuffer.readOnly = true
    let enterResult = e.enterViewerMode(
      EditorMode.LogViewer,
      ModeState(kind: mskLogViewer, logViewer: newLogViewerState(lckLsp)),
      logBuffer,
      vpHSplit,
    )
    if enterResult.isErr:
      e.state.statusMessage = "Failed to open LSP log: " & enterResult.error
  of hrJumpList:
    if e.state.jumpList.list.len == 0:
      e.state.statusMessage = "Jump list is empty"
    else:
      e.state.ui.tempMessages = @[]
      e.state.ui.tempMessages.add(" jump  line  col  file")
      for i, pos in e.state.jumpList.list:
        let marker = if i == e.state.jumpList.index: ">" else: " "
        let jumpNum = e.state.jumpList.list.len - i
        let lineNum = pos.line + 1
        let colNum = pos.column + 1
        let bufOpt = e.bufferById(pos.bufferId)
        let fileName =
          if bufOpt.isSome:
            let buf = bufOpt.get
            if buf.filePath.isSome: buf.filePath.get.extractFilename else: "[No Name]"
          else:
            "[Invalid]"
        e.state.ui.tempMessages.add(
          marker & ($jumpNum).align(4) & " " & ($lineNum).align(5) & " " &
            ($colNum).align(4) & "  " & fileName
        )
  of hrChanges:
    let buf = e.activeBuffer()
    if buf.changeList.len == 0:
      e.state.statusMessage = "No changes"
    else:
      e.state.ui.tempMessages = @[]
      e.state.ui.tempMessages.add("change  line  col  text")
      for i in 0 ..< buf.changeList.len:
        let pos = buf.changeList[i]
        let lineNum = pos.line + 1
        let colNum = pos.column + 1
        let marker = if i == buf.changeListIndex + 1: ">" else: " "
        let text =
          if pos.line < buf.len:
            let line = buf.getLine(pos.line)
            if line.runeLen > 40:
              line.runeSubStr(0, 40) & "..."
            else:
              line
          else:
            ""
        let changeNum = buf.changeList.len - i
        e.state.ui.tempMessages.add(
          marker & ($changeNum).align(4) & " " & ($lineNum).align(5) & " " &
            ($colNum).align(4) & "  " & text
        )
      let w = e.activeWindow
      let curMarker = if buf.changeListIndex == buf.changeList.len - 1: ">" else: " "
      e.state.ui.tempMessages.add(
        curMarker & "0".align(4) & " " & ($(w.cursor.line + 1)).align(5) & " " &
          ($(w.cursor.column + 1)).align(4) & "  "
      )
  of hrConflictNext:
    let buf = e.activeBuffer()
    let fromLine = e.activeWindow.cursor.line
    let nxt = buf.findNextConflict(fromLine)
    if nxt.isSome:
      e.activeWindow.cursor.line = nxt.get.startLine
      e.activeWindow.cursor.column = 0
      e.updateViewportForCursor(e.cursor)
    else:
      e.state.statusMessage = "No next git conflict"
  of hrConflictPrev:
    let buf = e.activeBuffer()
    let fromLine = e.activeWindow.cursor.line
    let prv = buf.findPrevConflict(fromLine)
    if prv.isSome:
      e.activeWindow.cursor.line = prv.get.startLine
      e.activeWindow.cursor.column = 0
      e.updateViewportForCursor(e.cursor)
    else:
      e.state.statusMessage = "No previous git conflict"
  of hrRecentFile:
    if e.focusExistingViewerWindow(EditorMode.RecentFile):
      return true
    let loadResult = e.enterRecentFileMode()
    if loadResult.isErr:
      logError("handler", "Failed to enter Recent File mode: " & loadResult.error)
      e.state.statusMessage = "Error: " & loadResult.error
    else:
      e.state.statusMessage = ""
  of hrEnterLogViewer:
    if e.focusExistingViewerWindow(EditorMode.LogViewer):
      return true
    let logLines = getMessageLog()
    let logContent =
      if logLines.len > 0:
        logLines.join("\n")
      else:
        ""
    let logBuffer = newTextBuffer(logContent)
    logBuffer.readOnly = true
    let enterResult = e.enterViewerMode(
      EditorMode.LogViewer,
      ModeState(kind: mskLogViewer, logViewer: newLogViewerState(lckEditor)),
      logBuffer,
      vpHSplit,
    )
    if enterResult.isErr:
      e.state.statusMessage = "Failed to open log: " & enterResult.error
  of hrEnterHelpViewer:
    if e.focusExistingViewerWindow(EditorMode.Help):
      return true
    let helpState = newHelpViewerState()
    let enterResult = e.enterViewerMode(
      EditorMode.Help,
      ModeState(kind: mskHelp, help: helpState),
      helpState.createHelpTextBuffer(),
      vpHSplit,
    )
    if enterResult.isErr:
      e.state.statusMessage = "Failed to open help: " & enterResult.error
  of hrEnterBufferManager:
    let bmState = newBufferManagerState()
    bmState.updateEntries(e.getBufferInfos())
    discard e.enterViewerMode(
      EditorMode.BufferManager,
      ModeState(kind: mskBufferManager, bufferManager: bmState),
      bmState.createBufferManagerTextBuffer(),
      vpInPlace,
    )
  of hrEnterBookmarkManager:
    let bkmState = newBookmarkManagerState()
    bkmState.updateEntries(e.buffers)
    discard e.enterViewerMode(
      EditorMode.BookmarkManager,
      ModeState(kind: mskBookmarkManager, bookmarkManager: bkmState),
      bkmState.createBookmarkManagerTextBuffer(),
      vpInPlace,
    )
  of hrEnterBackupManager:
    if e.focusExistingViewerWindow(EditorMode.BackupManager):
      return true
    let baseBackupDir = e.config.autoBackup.getBaseBackupDir()
    var sourceFilePath = ""
    if e.activeBuffer.filePath.isSome:
      sourceFilePath = absolutePath(e.activeBuffer.filePath.get)
    let bkState = initBackupManagerState(baseBackupDir, sourceFilePath)
    let enterResult = e.enterViewerMode(
      EditorMode.BackupManager,
      ModeState(kind: mskBackupManager, backupManager: bkState),
      bkState.createBackupManagerTextBuffer(),
      vpVSplit,
    )
    if enterResult.isErr:
      e.state.statusMessage = "Failed to open backup manager: " & enterResult.error
  of hrEnterTerminal:
    # Capture previousMode before teardown so it names the mode the user was
    # actually in, not the returnMode a closed viewer restored.
    e.state.previousMode = e.state.mode
    # Drain viewers on the active window: teardown may shift active to a
    # survivor that still holds its own viewerEntry/originalBuffer, and the
    # terminal takeover would leave those dangling.
    while e.activeWindow.viewerEntry.isSome:
      e.closeLiveViewer()
    e.enterTerminalInActiveWindow(r.enterTerminalCommand)
  of hrOnlyWindow:
    e.windowManager.onlyWindow(e.screenSize.width, e.screenSize.height)
    e.syncActiveWindow()
    if e.windowManager.windows.len > 0:
      e.setActiveWindowScreenCursor(e.activeWindow)
  of hrMapAdd, hrMapRemove, hrMapClear, hrMapList:
    discard # Folded to hrHandled/hrError by handleCommandMode; unreachable here.
  of hrPlaybackMacro:
    discard # Consumed by processReplayedResult; only reaches here defensively.
  of hrDebugViewerQuit:
    e.leaveViewerMode(EditorMode.Debug)
    e.state.windowDisplay.debugBuffer = nil
    return true
  of hrRecentFileOpenFile, hrRecentFileQuit, hrEnterDiffViewer, hrEnterReferences,
      hrEnterDocumentSymbol, hrEnterCallHierarchy:
    discard # Handled by per-mode dispatchers or produced from within those modes

  # Handle overlay transitions
  let overlayTransition = r.getOverlayTransition()
  if overlayTransition.isSome:
    case overlayTransition.get
    of okCommand:
      e.state.enterCommandOverlay()
    of okSearch:
      # Search mode needs direction from search state (already set by handler)
      e.state.enterSearchOverlay(e.state.input.search.direction)
    of okRename:
      e.state.enterRenameOverlay(
        e.state.renameState.originalWord, e.state.renameState.cursorLine,
        e.state.renameState.cursorColumn,
      )

  # Handle mode transitions
  let modeTransition = r.getModeTransition()
  if modeTransition.isSome:
    let oldMode = e.state.mode
    let newMode = modeTransition.get

    # A `mode_switch` keybinding can name a viewer mode directly. Replay that
    # mode's real entry result so it never goes live without its state.
    #
    # Only when the window does not already hold that state: a transition back
    # into a viewer the window is still showing (Escape out of a Visual
    # selection made inside it, which returns to `previousMode`) needs the mode
    # flipped, not a second listing and a second split.
    # Source of truth: viewerEntry names the mode the window is running.
    # Keying off modeState.kind would misclassify if any path reset the state
    # variant behind viewerEntry's back.
    let alreadyLive =
      e.activeWindow.viewerEntry.isSome and
      e.activeWindow.viewerEntry.get.mode == newMode

    # Reject only fresh entries; Escape back into a live viewer is a mode flip.
    if not alreadyLive and newMode in ModesNeedingContext:
      e.state.statusMessage = "Cannot switch to " & $newMode & " mode directly"
      return true

    e.state.previousMode = oldMode

    # FileTree is a sidebar with toggle semantics, so replaying its entry with
    # the sidebar open would close it. A `mode_switch` naming it focuses it.
    let focused = newMode == EditorMode.FileTree and e.focusFileTreeWindow()

    let entry =
      if alreadyLive or focused:
        none(HandlerResult)
      else:
        modeSwitchEntry(newMode)
    if entry.isSome:
      if not e.processResult(entry.get, activeBuffer):
        return false
    elif not focused:
      e.setMode(newMode)

      # Adjust cursor when transitioning from Insert to Normal mode
      # Skip cursor adjustment for insert-normal mode (Ctrl-o) since we'll return to Insert
      if oldMode == EditorMode.Insert and newMode == EditorMode.Normal and
          not e.state.insertNormalMode:
        let
          lineCharLen = activeBuffer.getLine(e.activeWindow.cursor.line).charLen
          oldColumn = e.activeWindow.cursor.column

        logDebug(
          "handler",
          "Insert→Normal transition: line=" & $e.activeWindow.cursor.line &
            " oldColumn=" & $oldColumn & " lineCharLen=" & $lineCharLen,
        )

        adjustCursorAfterInsertExit(e.activeWindow.cursor, lineCharLen)

        if oldColumn != e.activeWindow.cursor.column:
          logDebug(
            "handler",
            "Cursor adjusted: " & $oldColumn & " → " & $e.activeWindow.cursor.column,
          )

  # Filer buffer regeneration after state changes (e.g. enterDirectory, toggleHidden)
  if e.state.mode == EditorMode.Filer:
    let filerWin = e.activeWindow
    if filerWin.modeState.kind == mskFiler and
        filerWin.modeState.filer.needsBufferRefresh:
      filerWin.buffer =
        filerWin.modeState.filer.createFilerTextBuffer(e.config.filer.showIcons)
      filerWin.modeState.filer.needsBufferRefresh = false

  # FileTree buffer regeneration after state changes (check all windows since
  # the file tree sidebar may not be the active window)
  for win in e.windowManager.windows:
    if win.mode == EditorMode.FileTree and win.modeState.kind == mskFileTree and
        win.modeState.fileTree.needsBufferRefresh:
      win.buffer =
        win.modeState.fileTree.createFileTreeTextBuffer(e.config.filer.showIcons)
      win.modeState.fileTree.needsBufferRefresh = false

  # Set status message if any
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.statusMessage = statusMsg

  # Show syntax check message for current cursor line (if no other status message)
  if statusMsg.len == 0 and e.state.syntaxCheckResults.errors.len > 0:
    let activeBuf = e.activeBuffer()
    let activePath = if activeBuf.filePath.isSome: activeBuf.filePath.get else: ""
    if activePath.len > 0 and activePath == e.state.syntaxCheckResults.path:
      let syntaxMsg =
        formattedMessage(e.state.syntaxCheckResults.errors, e.activeWindow.cursor.line)
      if syntaxMsg.isSome:
        e.state.statusMessage = syntaxMsg.get

  return true # Continue running

const MaxMacroRecursionDepth = 100
  ## Macro recursion depth guard (@a inside @a...) before abort.

const MaxMapRecursionDepth = 50
  ## `:map` (noremap=false) expansion depth guard. Kept below
  ## MaxMacroRecursionDepth so a cyclic mapping reports "recursive mapping"
  ## before the macro depth guard fires.

proc playbackMacroImpl(e: Editor, keys: seq[string]): ReplayOutcome
proc playbackKeyCombosImpl(e: Editor, combos: seq[KeyCombo]): ReplayOutcome

proc runNestedKeyCombo*(
  manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): ReplayOutcome

proc processReplayedResult*(
    e: Editor, r: HandlerResult, activeBuffer: TextBuffer
): ReplayOutcome =
  ## Mini processor for keys fired from a nested replay context (macro,
  ## mapping RHS, timeout batch). Applies full side effects via
  ## `processResult` — no kind is silently dropped — and returns whether the
  ## loop should keep going. `hrPlaybackMacro` is intercepted here and drives
  ## the nested `playbackMacroImpl` loop count times.
  if r.kind == hrPlaybackMacro:
    for _ in 0 ..< r.playbackMacroCount:
      let outcome = playbackMacroImpl(e, r.playbackMacroKeys)
      if outcome != roContinue:
        return outcome
    # Finalize insert-normal after the macro. applyNormalModePostProcessing
    # skips hrPlaybackMacro's clean-up branch so the OUTER insertNormalMode
    # survives the propagation; if the macro's own keys never cleared it
    # (empty macro, all keys stayed pending), fold it back into Insert here.
    let state = e.state
    if state.insertNormalMode and state.mode == EditorMode.Normal and
        not hasPendingBuiltinInput(e):
      state.insertNormalMode = false
      e.setMode(EditorMode.Insert)
    return roContinue
  let shouldContinue = processResult(e, r, activeBuffer)
  if r.kind == hrError:
    return roAbort
  if not shouldContinue:
    return roQuit
  roContinue

template withPlaybackGuard(e: Editor, body: untyped): ReplayOutcome =
  ## Shared depth guard + isRecording suspension for macro / runtime-mapping
  ## replay loops. `body` must assign to `outcome`.
  block:
    let state = e.state
    if state.pendingInput.macroState.playbackDepth >= MaxMacroRecursionDepth:
      e.state.statusMessage =
        "Macro recursion limit exceeded (max " & $MaxMacroRecursionDepth & ")"
      roAbort
    else:
      state.pendingInput.macroState.playbackDepth += 1
      let wasRecording = state.pendingInput.macroState.isRecording
      state.pendingInput.macroState.isRecording = false
      var outcome {.inject.} = roContinue
      body
      state.pendingInput.macroState.isRecording = wasRecording
      state.pendingInput.macroState.playbackDepth -= 1
      outcome

proc playbackKeyCombosImpl(e: Editor, combos: seq[KeyCombo]): ReplayOutcome =
  ## Iterate `combos` through `runNestedKeyCombo` — no per-key parse. Used by
  ## runtime key-sequence mappings whose RHS is pre-parsed at registration.
  withPlaybackGuard(e):
    for k in combos:
      outcome = runNestedKeyCombo(e.handlerManager, e, k)
      if outcome != roContinue:
        break

proc playbackMacroImpl(e: Editor, keys: seq[string]): ReplayOutcome =
  ## Iterate user-recorded macro `keys` (register storage is seq[string]).
  ## Aborts on the first `stringToKeyCombo` failure but keeps executing the
  ## good prefix (matches pre-refactor behaviour).
  withPlaybackGuard(e):
    for keyStr in keys:
      let keyComboOpt = stringToKeyCombo(keyStr)
      if keyComboOpt.isNone:
        e.state.statusMessage = "Invalid key in macro: " & keyStr
        outcome = roAbort
        break
      outcome = runNestedKeyCombo(e.handlerManager, e, keyComboOpt.get)
      if outcome != roContinue:
        break

proc replayRuntimeKeySequence*(
    manager: HandlerManager, editor: Editor, targetKeys: seq[KeyCombo], noremap: bool
): ReplayOutcome =
  ## Replay the RHS of a fired runtime key-sequence mapping. `:noremap` runs
  ## verbatim under `withReplay` (isReplayingMapping suppresses re-expansion);
  ## `:map` runs without withReplay so each replayed key re-enters the
  ## precheck, bounded by `mapExpandDepth` / `MaxMapRecursionDepth`.
  if noremap:
    var outcome = roContinue
    editor.keyRouter.withReplay:
      outcome = playbackKeyCombosImpl(editor, targetKeys)
    return outcome

  if editor.keyRouter.mapExpandDepth >= MaxMapRecursionDepth:
    editor.state.statusMessage = "recursive mapping (max " & $MaxMapRecursionDepth & ")"
    return roAbort
  editor.keyRouter.mapExpandDepth += 1
  try:
    result = playbackKeyCombosImpl(editor, targetKeys)
  finally:
    editor.keyRouter.mapExpandDepth -= 1

proc checkRuntimeKeySeqMapping*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): Option[ReplayOutcome] =
  ## Ask the KeyRouter whether `keyCombo` is part of a runtime mapping. Returns
  ## `none` to let the caller fall through to built-in resolution, or `some`
  ## outcome when the mapping fired (or is still building).
  ##
  ## Flush semantics: rrUnhandledBatch replays accumulated keys *except* the
  ## current one; the caller re-processes the current key normally. The
  ## Command overlay path lives in `command_mode_handler.handleCommandModeKeyCombo`.
  let state = editor.state
  let route = editor.keyRouter.feedKey(state.mode, keyCombo)
  case route.kind
  of rrUnhandled, rrCancelled, rrCommand:
    # rrCommand is produced only by resolveBuiltin (Normal dispatcher), never by
    # feedKey; listed for exhaustiveness. Fall through to built-in resolution.
    return none(ReplayOutcome)
  of rrExecuteRuntimeCommand:
    let cmdResult = manager.executeCommandDirect(route.commandName)
    if cmdResult.isSome:
      return some(processReplayedResult(editor, cmdResult.get, editor.activeBuffer))
    return none(ReplayOutcome)
  of rrExecuteRuntimeKeySequence:
    return
      some(replayRuntimeKeySequence(manager, editor, route.targetKeys, route.noremap))
  of rrWaiting:
    return some(roContinue)
  of rrUnhandledBatch:
    let keysToFlush = route.keys[0 ..< route.keys.len - 1]
    var outcome = roContinue
    editor.keyRouter.withReplay:
      for k in keysToFlush:
        outcome = runNestedKeyCombo(manager, editor, k)
        if outcome != roContinue:
          break
    if outcome != roContinue:
      return some(outcome)
    return none(ReplayOutcome)

proc runNestedKeyCombo*(
    manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): ReplayOutcome =
  ## Single entry point that fuses precheck (runtime key-sequence mapping) with
  ## dispatch and full processResult side effects. Both the top-level event
  ## loop and nested-playback loops (macro, mapping RHS, timeout batch) call
  ## this so every kind's side effect fires exactly once.
  # When an overlay is active the live loop routes through the overlay handler;
  # replay must do the same or recorded overlay keys hit the base-mode handler.
  if not overlayPlaybackHook.isNil:
    let overlayResult = overlayPlaybackHook(e, keyCombo)
    if overlayResult.isSome:
      return if overlayResult.get: roContinue else: roQuit
  if not manager.keyBindingRegistry.isReplayingMapping:
    let expand = checkRuntimeKeySeqMapping(manager, e, keyCombo)
    if expand.isSome:
      return expand.get
  let r = manager.handleKeyCombo(e, keyCombo)
  processReplayedResult(e, r, e.activeBuffer)

proc outcomeToHandlerResult(e: Editor, outcome: ReplayOutcome): HandlerResult =
  ## Fold a ReplayOutcome into the HandlerResult shape test-facing wrappers
  ## return. `roAbort` pulls the diagnostic from `state.statusMessage`, which
  ## the abort site (`playbackMacroImpl`, `replayRuntimeKeySequence`, or
  ## `processResult`'s hrError arm) has already populated.
  case outcome
  of roContinue:
    HandlerResult(kind: hrHandled, modeTransition: none(EditorMode), statusMessage: "")
  of roQuit:
    HandlerResult(kind: hrQuit)
  of roAbort:
    HandlerResult(kind: hrError, errorMessage: e.state.statusMessage)

proc playbackMacro*(editor: Editor, keys: seq[string]): HandlerResult =
  ## Test-facing wrapper. Real callers go through `hrPlaybackMacro` +
  ## `processReplayedResult`; this preserves a HandlerResult return for
  ## tests that inspect it directly. Side effects are applied via
  ## `playbackMacroImpl`; the returned HandlerResult is a status signal.
  outcomeToHandlerResult(editor, playbackMacroImpl(editor, keys))

proc playbackKeyCombos*(editor: Editor, combos: seq[KeyCombo]): HandlerResult =
  ## Test-facing wrapper for the pre-parsed variant. Used by tests that
  ## execute a `RuntimeKeyMapping.targetKeys` (now seq[KeyCombo]) directly.
  outcomeToHandlerResult(editor, playbackKeyCombosImpl(editor, combos))

proc runKeyCombo*(
    manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## HandlerResult-returning form of `runNestedKeyCombo`, for tests that
  ## inspect kind/errorMessage. Full processResult side effects fire on every
  ## path (precheck, direct dispatch, hrPlaybackMacro expansion) so the
  ## observable state after this call matches production `handleEvent`. The
  ## returned HandlerResult is a status signal (hrHandled/hrQuit/hrError),
  ## not the raw dispatched result — inspect `state.mode`, `state.overlay`,
  ## and other mutations directly.
  outcomeToHandlerResult(e, runNestedKeyCombo(manager, e, keyCombo))

proc tryHandleQuickRunRequest(e: Editor, activeBuffer: TextBuffer): bool =
  ## Consume `state.requestQuickRun` (set by buffer-mode key handlers) and
  ## fire QuickRun via pending state. Returns true when a QuickRun request
  ## was consumed; callers should skip further hr-teardown in that case.
  if not e.state.requestQuickRun:
    return false
  e.state.requestQuickRun = false
  let prepareResult = prepareQuickRun(activeBuffer, e.config)
  if prepareResult.isErr:
    e.state.statusMessage = "QuickRun error: " & prepareResult.error
    logError("handler", "QuickRun prepare failed: " & prepareResult.error)
  else:
    let prepared = prepareResult.get
    e.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (
        cmd: prepared.command.cmd,
        args: prepared.command.args,
        filePath: prepared.filePath,
        isTempFile: prepared.isTempFile,
      ),
    )
    if e.config.notification.screenNotifications and
        e.config.notification.quickRunScreenNotify:
      e.state.statusMessage = quickRunStartupMessage(prepared.filePath)
  e.state.exitOverlay()
  e.setMode(EditorMode.Normal)
  return true

proc handleInsertNormalReturn(e: Editor) =
  ## After a Command overlay completes, if we were in insert-normal mode
  ## (Ctrl-o), return to Insert (for :w/:set) or commit the Insert transaction
  ## (when the command switched to a non-Normal/Insert mode).
  if not e.state.insertNormalMode:
    return
  if e.state.mode == EditorMode.Normal:
    e.state.insertNormalMode = false
    e.setMode(EditorMode.Insert)
  elif e.state.mode != EditorMode.Insert:
    e.state.insertNormalMode = false
    let activeBuffer = e.activeBuffer()
    if activeBuffer.inTransaction:
      clearAutoIndentIfUnedited(activeBuffer, e.state)
      discard activeBuffer.commitTransaction()
    e.state.editState.insertModeStartPos = none(BufferPosition)
    e.state.editState.substituteContext = none(types.SubstituteContext)

proc executeCommandOverlay*(e: Editor, commandText: string): bool =
  ## Full lifecycle of a Command-overlay Enter: pre-teardown, dispatch,
  ## side effects via processResult, teardown driven by `r.group`, then
  ## Insert-Normal recovery. Returns false when the caller should stop the
  ## main loop (app quit).
  # 1. pre-teardown (kind-independent)
  e.state.commandCompletionManager.cancelCompletion()
  if e.state.ui.substitutePreview.isActive:
    e.cancelSubstitutePreview()

  # 2. dispatch
  let activeBuffer = e.activeBuffer()
  let isShared = e.isBufferShared(activeBuffer)
  var otherModifiedCount = 0
  for buf in e.buffers:
    if buf != activeBuffer and buf.isModified:
      otherModifiedCount.inc
  let r = e.handlerManager.handleCommandMode(
    activeBuffer, commandText, isShared, e.activeWindow.cursor.line, otherModifiedCount
  )
  if commandText.len > 1:
    e.addCommandToHistory(commandText[1 ..^ 1])

  # 3. requestQuickRun poll (set independently of r.kind by buffer-mode keys)
  if e.tryHandleQuickRunRequest(activeBuffer):
    e.handleInsertNormalReturn()
    return true

  # 4. side effects
  let shouldContinue = e.processResult(r, activeBuffer)
  if not shouldContinue:
    return false

  # 5. teardown
  case r.group
  of hrgAppExit:
    return false # unreachable — processResult would have returned false
  of hrgExitToNormal:
    e.state.exitOverlay()
    e.setMode(EditorMode.Normal)
  of hrgExitToNewMode:
    e.state.exitOverlay()
  of hrgExitAndResync:
    e.state.exitOverlay()
    e.setMode(e.state.mode)
  of hrgHandledGeneric:
    e.state.exitOverlay()
    let t = r.getModeTransition()
    # `ModesNeedingContext` targets were refused by processResult; re-applying
    # the transition here would put the window in that mode with no state.
    if t.isSome and t.get notin ModesNeedingContext:
      e.setMode(t.get)
    else:
      e.setMode(e.state.mode)

  # 6. status message from HandlerResult payload
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.statusMessage = statusMsg

  # 7. Insert-Normal recovery (Ctrl-o)
  e.handleInsertNormalReturn()
  return true
