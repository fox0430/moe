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

## File / buffer open and split side effects (filer, file tree, URI, quickrun),
## split out of result_processor.nim.

import std/[options, os]

import pkg/results

import
  ../[
    buffer, editor, filetree, filer, logger, quick_run_utils, types, uri_utils,
    viewer_mode, window_manager,
  ]

import editor_ops, handler_result

proc processFileResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Handle file / buffer open and split kinds. Returns true to continue.
  case r.kind
  of hrFilerOpenFile:
    # Open file from filer into the active window's tab list
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
  of hrFileTreeOpenFile:
    # Open in the first non-FileTree window; if the FileTree is alone,
    # open the file in a new window to its right.
    var targetWinIdx = -1
    for i, win in e.windowManager.windows:
      if win.mode != EditorMode.FileTree:
        targetWinIdx = i
        break

    # Reveal the opened file in the file tree
    for win in e.windowManager.windows:
      if win.mode == EditorMode.FileTree and win.modeState.kind == mskFileTree:
        win.modeState.fileTree.revealPath(r.fileTreeFilePath)
        break

    if targetWinIdx >= 0:
      # Switch to the target window and open the file (keeps unsaved changes)
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
  of hrOpenUri:
    let uri = r.openUri
    if isLocalFileUri(uri):
      let path = fileUriToPath(uri)
      if e.openFileAndJumpTo(path, 0, 0):
        e.state.statusMessage = "Opened: " & path.extractFilename
      else:
        e.state.statusMessage = "Failed to open: " & path
    elif isExternalUri(uri):
      let openResult = openExternalUri(uri)
      if openResult.isOk:
        e.state.statusMessage = "Opened: " & uri
      else:
        e.state.statusMessage = openResult.error
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
  of hrQuickRun:
    # Mirror command_mode_handler.nim's hrQuickRun branch so Normal mode
    # keybindings (e.g. \r) run the same path as `:quickrun`.
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
    return true
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
    return true
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
    return true
  of hrNew:
    let newResult = e.new()
    if newResult.isErr:
      logError("handler", "New failed: " & newResult.error)
      e.state.statusMessage = "Error: " & newResult.error
    return true
  of hrVnew:
    let vnewResult = e.vnew()
    if vnewResult.isErr:
      logError("handler", "Vnew failed: " & vnewResult.error)
      e.state.statusMessage = "Error: " & vnewResult.error
    return true
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
    return true
  of hrEnew:
    let enewResult = e.enew()
    if enewResult.isErr:
      logError("handler", "Enew failed: " & enewResult.error)
      e.state.statusMessage = "Error: " & enewResult.error
    return true
  else:
    return true # Not a file kind; caller misrouted (defensive)
