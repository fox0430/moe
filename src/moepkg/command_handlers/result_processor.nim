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

import std/[options, os, strutils]

import pkg/[results, chronos]

import
  ../[
    editor, editor_window_state, modes, buffer, logger, types, filer, filetree,
    buffer_manager, bookmark_manager, backup_manager, backup, diff_viewer,
    config_loader, message_log, uri_utils, primitives, syntax_checker, status_line,
    cursor_util, quick_run_utils,
  ]
import ../key_bindings except Command
import ./[command_mode_handler, handler_result]

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
    let activeWin = e.activeWindow
    activeWin.restoreOriginalBuffer(EditorMode.Filer)
    let editResult = e.editFile(r.filerFilePath)
    if editResult.isErr:
      e.state.statusMessage = "Error: " & editResult.error
    else:
      activeWin.modeState = ModeState(kind: mskNone)
      activeWin.mode = EditorMode.Normal
      e.setMode(EditorMode.Normal)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.notify("Opened: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file: " & r.filerFilePath)
    return true
  of hrFilerOpenFileVSplit:
    # Open file in vertical split from filer
    let activeWinVS = e.activeWindow
    activeWinVS.restoreOriginalBuffer(EditorMode.Filer)
    let splitResult = e.vsplit(some(r.filerFilePath))
    if splitResult.isErr:
      e.state.statusMessage = "Error: " & splitResult.error
    else:
      let activeWin = e.activeWindow
      activeWin.modeState = ModeState(kind: mskNone)
      activeWin.mode = EditorMode.Normal
      e.setMode(EditorMode.Normal)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.notify("Opened in vsplit: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file in vsplit: " & r.filerFilePath)
    return true
  of hrFilerOpenFileHSplit:
    # Open file in horizontal split from filer
    let activeWinHS = e.activeWindow
    activeWinHS.restoreOriginalBuffer(EditorMode.Filer)
    let splitResult = e.hsplit(some(r.filerFilePath))
    if splitResult.isErr:
      e.state.statusMessage = "Error: " & splitResult.error
    else:
      let activeWin = e.activeWindow
      activeWin.modeState = ModeState(kind: mskNone)
      activeWin.mode = EditorMode.Normal
      e.setMode(EditorMode.Normal)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.notify("Opened in hsplit: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file in hsplit: " & r.filerFilePath)
    return true
  of hrFilerQuit:
    # Close filer and return to Normal mode
    e.activeWindow.clearModeState(EditorMode.Filer)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
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
    # Close log viewer window and return to Normal mode
    let activeWin = e.activeWindow
    activeWin.clearModeState(EditorMode.LogViewer)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    # Remove the split buffer from the buffer list and close the window
    if e.windowManager.windows.len > 1:
      let buf = activeWin.buffer
      let idx = e.bufferIndexById(buf.id)
      if idx >= 0:
        evictGitCacheForBuffer(buf)
        e.deleteBufferAt(idx)
        e.pruneBufferIdFromAllWindows(buf.id)
      discard e.closeWindow()
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
    # Close help viewer split window and return to Normal mode
    let activeWin = e.activeWindow
    activeWin.clearModeState(EditorMode.Help)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    # Remove the split buffer from the buffer list and close the window
    if e.windowManager.windows.len > 1:
      let buf = activeWin.buffer
      let idx = e.bufferIndexById(buf.id)
      if idx >= 0:
        evictGitCacheForBuffer(buf)
        e.deleteBufferAt(idx)
        e.pruneBufferIdFromAllWindows(buf.id)
      discard e.closeWindow()
    return true
  of hrReferencesQuit:
    # Close references viewer and return to Normal mode, restoring the
    # cursor/viewport that were active before the viewer was opened.
    let win = e.activeWindow
    var origin = none(ReferencesViewerState)
    if win.modeState.kind == mskReferences:
      origin = some(win.modeState.references)
    win.clearModeState(EditorMode.References) # restores the original buffer
    if origin.isSome:
      let refState = origin.get
      win.cursor = refState.originCursor
      win.viewport.topLine = refState.originTopLine
      win.viewport.leftColumn = refState.originLeftColumn
    win.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrReferencesJumpTo:
    # Jump to selected reference. Restore the pre-viewer cursor first so the
    # jump list anchors at the original position (enabling jump-back).
    let win = e.activeWindow
    var openWindow = false
    if win.modeState.kind == mskReferences:
      let refState = win.modeState.references
      openWindow = refState.openWindowOnJump
      win.clearModeState(EditorMode.References)
      win.cursor = refState.originCursor
    else:
      win.clearModeState(EditorMode.References)
    win.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    discard e.openFileAndJumpTo(r.jumpToPath, r.jumpToLine, r.jumpToColumn, openWindow)
    return true
  of hrDocumentSymbolQuit:
    # Close document symbol viewer and return to Normal mode, restoring the
    # cursor/viewport that were active before the viewer was opened.
    let win = e.activeWindow
    var origin = none(DocumentSymbolViewerState)
    if win.modeState.kind == mskDocumentSymbol:
      origin = some(win.modeState.documentSymbol)
    win.clearModeState(EditorMode.DocumentSymbol) # restores the original buffer
    if origin.isSome:
      let st = origin.get
      win.cursor = st.originCursor
      win.viewport.topLine = st.originTopLine
      win.viewport.leftColumn = st.originLeftColumn
    win.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrDocumentSymbolJumpTo:
    # Jump to selected symbol (same file). Restore the pre-viewer cursor first
    # so the jump list anchors at the original position (enabling jump-back).
    let activeWin = e.activeWindow
    let st = activeWin.modeState.documentSymbol
    let
      filePath = st.filePath
      originCursor = st.originCursor
    activeWin.clearModeState(EditorMode.DocumentSymbol)
    activeWin.cursor = originCursor
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    discard e.openFileAndJumpTo(filePath, r.symbolLine, r.symbolColumn)
    return true
  of hrCallHierarchyQuit:
    # Close call hierarchy viewer and return to Normal mode, restoring the
    # cursor/viewport that were active before the viewer was opened.
    if e.state.lspCache.pendingCallHierarchyRequestId != 0:
      e.lsp.cancelRequest(e.state.lspCache.pendingCallHierarchyRequestId)
      e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone
    let win = e.activeWindow
    var origin = none(CallHierarchyViewerState)
    if win.modeState.kind == mskCallHierarchy:
      origin = some(win.modeState.callHierarchy)
    win.clearModeState(EditorMode.CallHierarchy) # restores the original buffer
    if origin.isSome:
      let st = origin.get
      win.cursor = st.originCursor
      win.viewport.topLine = st.originTopLine
      win.viewport.leftColumn = st.originLeftColumn
    win.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrCallHierarchyJumpTo:
    # Jump to selected call hierarchy item. Restore the pre-viewer cursor first
    # so the jump list anchors at the original position (enabling jump-back).
    let path =
      if r.callHierarchyJumpUri.startsWith("file://"):
        r.callHierarchyJumpUri[7 ..^ 1]
      else:
        r.callHierarchyJumpUri
    if e.state.lspCache.pendingCallHierarchyRequestId != 0:
      e.lsp.cancelRequest(e.state.lspCache.pendingCallHierarchyRequestId)
      e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone
    let win = e.activeWindow
    var originCursor = BufferPosition(line: 0, column: 0)
    if win.modeState.kind == mskCallHierarchy:
      originCursor = win.modeState.callHierarchy.originCursor
    win.clearModeState(EditorMode.CallHierarchy)
    win.cursor = originCursor
    win.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
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
    # Close buffer manager and return to Normal mode
    e.activeWindow.clearModeState(EditorMode.BufferManager)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrBufferManagerSelectBuffer:
    # Select the buffer and switch to it
    let bufferIndex = r.selectBufferIndex
    let activeWin = e.activeWindow
    activeWin.restoreOriginalBuffer(EditorMode.BufferManager)
    if bufferIndex >= 0 and bufferIndex < e.buffers.len:
      e.switchToBufferByIndex(bufferIndex)
    activeWin.modeState = ModeState(kind: mskNone)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
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
        if e.activeBuffer() != e.executer.buffer:
          e.executer.setBuffer(e.activeBuffer())

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
    # Close bookmark manager and return to Normal mode
    e.activeWindow.clearModeState(EditorMode.BookmarkManager)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrBookmarkManagerJump:
    # Jump to the selected bookmark (buffer + line)
    let bufferIndex = r.bookmarkJumpBufferIndex
    let jumpLine = r.bookmarkJumpLine
    let activeWin = e.activeWindow
    activeWin.restoreOriginalBuffer(EditorMode.BookmarkManager)
    if bufferIndex >= 0 and bufferIndex < e.buffers.len:
      e.switchToBufferByIndex(bufferIndex)
      let buf = e.activeBuffer()
      let clampedLine = min(jumpLine, max(0, buf.len - 1))
      e.activeWindow.cursor = BufferPosition(line: clampedLine, column: 0)
      e.activeWindow.viewport.topLine = max(0, clampedLine - 5)
    activeWin.modeState = ModeState(kind: mskNone)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
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
    # Close backup manager and return to Normal mode
    let activeWin = e.activeWindow
    activeWin.clearModeState(EditorMode.BackupManager)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    # Remove the split buffer from the buffer list and close the window
    if e.windowManager.windows.len > 1:
      let buf = activeWin.buffer
      let idx = e.bufferIndexById(buf.id)
      if idx >= 0:
        evictGitCacheForBuffer(buf)
        e.deleteBufferAt(idx)
        e.pruneBufferIdFromAllWindows(buf.id)
      discard e.closeWindow()
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
    activeWin.viewport.topLine = 0
    activeWin.viewport.leftColumn = 0
    return true
  of hrConfigQuit:
    # Close config mode and return to previous mode
    let activeWin = e.activeWindow
    activeWin.clearModeState(EditorMode.Config)
    activeWin.mode = e.state.previousMode
    e.setMode(e.state.previousMode)
    # Remove the split buffer from the buffer list and close the window
    if e.windowManager.windows.len > 1:
      let buf = activeWin.buffer
      let idx = e.bufferIndexById(buf.id)
      if idx >= 0:
        evictGitCacheForBuffer(buf)
        e.deleteBufferAt(idx)
        e.pruneBufferIdFromAllWindows(buf.id)
      discard e.closeWindow()
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
        activeWin.viewport.topLine = 0
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
    let startPath =
      if r.enterFilerPath.isSome:
        r.enterFilerPath.get
      elif e.activeWindow.buffer.filePath.isSome:
        parentDir(e.activeWindow.buffer.filePath.get)
      else:
        getCurrentDir()
    e.enterFilerInActiveWindow(startPath)
  of hrEnterFileTree:
    let activeBufLocal = e.activeBuffer()
    e.toggleFileTree(r.enterFileTreePath, activeBufLocal)
  of hrBufferDelete:
    e.deleteCurrentBuffer()
  of hrExecCommand:
    # @: - repeat last Command mode command
    # Execute via handleCommandModeKeyCombo which has full result processing
    let count = r.execCommandCount
    let commandText = ":" & r.execCommandText
    let enterKey = KeyCombo(isSpecial: true, special: skEnter, fnNum: 0, modifiers: {})
    for i in 0 ..< count:
      e.state.commandText = commandText
      e.state.commandCursor = commandText.len
      let continueRunning = e.handleCommandModeKeyCombo(enterKey)
      if not continueRunning:
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
      e.state.pending.quickRun = (
        cmd: prepared.command.cmd,
        args: prepared.command.args,
        filePath: prepared.filePath,
        isTempFile: prepared.isTempFile,
      )
      if e.config.notification.screenNotifications and
          e.config.notification.quickRunScreenNotify:
        e.state.statusMessage = quickRunStartupMessage(prepared.filePath)
  of hrVSplit, hrHSplit, hrNew, hrVnew, hrEdit, hrSetBoolOption, hrSetIntOption,
      hrSetFloatOption, hrClearSearchHighlight, hrSave, hrSaveAll, hrStripWhitespace,
      hrShellCommand, hrBackground, hrMan, hrSubstitute, hrDeleteLines, hrBuild,
      hrDebug, hrDebugViewerQuit, hrConfig, hrTheme, hrLspLog, hrJumpList, hrChanges,
      hrRecentFile, hrRecentFileOpenFile, hrRecentFileQuit, hrEnterLogViewer,
      hrEnterHelpViewer, hrEnterBufferManager, hrEnterBookmarkManager,
      hrEnterBackupManager, hrEnterDiffViewer, hrEnterReferences, hrEnterDocumentSymbol,
      hrEnterCallHierarchy, hrEnterTerminal, hrOnlyWindow, hrConflictNext,
      hrConflictPrev:
    discard # Handled by handleCommandModeEvent or other code paths

  # Handle overlay transitions
  let overlayTransition = r.getOverlayTransition()
  if overlayTransition.isSome:
    case overlayTransition.get
    of okCommand:
      e.state.enterCommandOverlay()
    of okSearch:
      # Search mode needs direction from search state (already set by handler)
      e.state.enterSearchOverlay(e.state.search.direction)
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
    e.state.previousMode = oldMode
    e.setMode(newMode)

    # Initialize filer state when entering Filer mode
    let activeWin = e.activeWindow
    if newMode == EditorMode.Filer and activeWin.modeState.kind != mskFiler:
      # Use buffer's directory or current working directory
      let startPath =
        if activeBuffer.filePath.isSome:
          parentDir(activeBuffer.filePath.get)
        else:
          getCurrentDir()
      let filerState = newFilerState(startPath)
      activeWin.saveOriginalBuffer()
      activeWin.modeState = ModeState(kind: mskFiler, filer: filerState)
      activeWin.buffer = filerState.createFilerTextBuffer(e.config.filer.showIcons)
      activeWin.cursor = BufferPosition(line: 0, column: 0)
      activeWin.viewport.topLine = 0
      activeWin.viewport.leftColumn = 0
      activeWin.mode = EditorMode.Filer

    # Initialize buffer manager state when entering BufferManager mode
    if newMode == EditorMode.BufferManager:
      let bmState = newBufferManagerState()
      bmState.updateEntries(e.getBufferInfos())
      bmState.previousWindowIndex = e.windowManager.activeWindowIndex
      activeWin.modeState = ModeState(kind: mskBufferManager, bufferManager: bmState)
      activeWin.mode = EditorMode.BufferManager

    # Initialize bookmark manager state when entering BookmarkManager mode
    if newMode == EditorMode.BookmarkManager:
      let bkmState = newBookmarkManagerState()
      bkmState.updateEntries(e.buffers)
      bkmState.previousWindowIndex = e.windowManager.activeWindowIndex
      activeWin.saveOriginalBuffer()
      activeWin.modeState =
        ModeState(kind: mskBookmarkManager, bookmarkManager: bkmState)
      activeWin.buffer = bkmState.createBookmarkManagerTextBuffer()
      activeWin.cursor = BufferPosition(line: 0, column: 0)
      activeWin.viewport.topLine = 0
      activeWin.mode = EditorMode.BookmarkManager

    # Adjust cursor when transitioning from Insert to Normal mode
    # Skip cursor adjustment for insert-normal mode (Ctrl-o) since we'll return to Insert
    if oldMode == EditorMode.Insert and newMode == EditorMode.Normal and
        not e.state.insertNormalMode:
      let
        lineCharLen = activeBuffer.getLine(e.activeWindow.cursor.line).charLen
        oldColumn = e.activeWindow.cursor.column

      logDebug(
        "handler",
        "Insert→Normal transition: line=" & $e.activeWindow.cursor.line & " oldColumn=" &
          $oldColumn & " lineCharLen=" & $lineCharLen,
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
