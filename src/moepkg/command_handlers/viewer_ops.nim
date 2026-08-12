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

## Viewer quit / jump / refresh side effects, split out of result_processor.nim
## so viewer teardown and selection jumps live next to viewer_mode.nim.

import std/[options, os, strutils]

import pkg/results

import
  ../[
    buffer, buffer_manager, bookmark_manager, editor, editor_callhierarchy,
    editor_window_state, help_viewer, log_viewer, logger, lsp_service, message_log,
    types, viewer_mode,
  ]
import ../[backup, backup_manager]

import editor_ops, handler_result

proc processViewerResult*(e: Editor, r: HandlerResult): bool =
  ## Handle viewer quit / jump / refresh kinds. Returns true to continue.
  case r.kind
  of hrLogViewerQuit:
    e.leaveViewerMode(EditorMode.LogViewer)
    return true
  of hrFilerQuit:
    e.leaveViewerMode(EditorMode.Filer)
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
    # Restore the pre-viewer cursor so the jump list anchors at the origin.
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
    # Restore the pre-viewer cursor so the jump list anchors at the origin.
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
    # Restore the pre-viewer cursor so the jump list anchors at the origin.
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

        # Point currentBufferId at the replacement buffer so Jump List
        # (Ctrl-o/Ctrl-i) can't false-match the dead id; the BufferManager
        # overlay replaces activeWindow.buffer next.
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
    # Resume the suspended mode; clearModeState already restored the swapped
    # buffer, and syncSelectionCursor re-places the cursor on the next render.
    let activeWin = e.activeWindow
    let suspended = activeWin.takeSuspendedMode()
    activeWin.clearModeState(EditorMode.DiffViewer)
    if suspended.isSome:
      activeWin.mode = suspended.get.mode
      activeWin.modeState = suspended.get.modeState
    else:
      # Nothing was suspended: fall back to Normal so mode/modeState match.
      activeWin.mode = EditorMode.Normal
    # Reset to the top so a stale off-screen viewport can't survive the swap.
    activeWin.cursor = BufferPosition(line: 0, column: 0)
    activeWin.viewport.resetViewportTop()
    activeWin.viewport.leftColumn = 0
    return true
  of hrEnterFiler:
    # Tear down the viewer so startPath resolves from the underlying file.
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
    return true
  of hrEnterFileTree:
    let activeBufLocal = e.activeBuffer()
    e.toggleFileTree(r.enterFileTreePath, activeBufLocal)
    return true
  of hrRecentFile:
    if e.focusExistingViewerWindow(EditorMode.RecentFile):
      return true
    let loadResult = e.enterRecentFileMode()
    if loadResult.isErr:
      logError("handler", "Failed to enter Recent File mode: " & loadResult.error)
      e.state.statusMessage = "Error: " & loadResult.error
    else:
      e.state.statusMessage = ""
    return true
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
    return true
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
    return true
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
    return true
  of hrEnterBufferManager:
    let bmState = newBufferManagerState()
    bmState.updateEntries(e.getBufferInfos())
    discard e.enterViewerMode(
      EditorMode.BufferManager,
      ModeState(kind: mskBufferManager, bufferManager: bmState),
      bmState.createBufferManagerTextBuffer(),
      vpInPlace,
    )
    return true
  of hrEnterBookmarkManager:
    let bkmState = newBookmarkManagerState()
    bkmState.updateEntries(e.buffers)
    discard e.enterViewerMode(
      EditorMode.BookmarkManager,
      ModeState(kind: mskBookmarkManager, bookmarkManager: bkmState),
      bkmState.createBookmarkManagerTextBuffer(),
      vpInPlace,
    )
    return true
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
    return true
  of hrEnterTerminal:
    # Capture previousMode before teardown.
    e.state.previousMode = e.state.mode
    # Drain viewers so the terminal takeover leaves no dangling viewer state.
    while e.activeWindow.viewerEntry.isSome:
      e.closeLiveViewer()
    e.enterTerminalInActiveWindow(r.enterTerminalCommand)
    return true
  else:
    return true # Not a viewer kind; caller misrouted (defensive)
