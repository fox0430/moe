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
    buffer, editor, editor_window_state, filetree, filer, logger, quick_run_utils,
    types, uri_utils, viewer_mode, window_manager,
  ]

import editor_ops, handler_result

proc restoreSidebarFocus(e: Editor, side: EditorWindow) =
  ## Return focus to the sidebar after a failed command, so the failure does
  ## not strand the cursor in the target window.
  for i, win in e.windowManager.windows:
    if win == side:
      e.windowManager.activateWindow(i)
      e.syncActiveWindow()
      return

proc openFromSidebar(e: Editor, inServed, beside: proc(): Result[(), string]): bool =
  ## From the sidebar, run `inServed` in the window it serves; beside a lone
  ## sidebar, `beside` opens a window next to it instead. A failure is reported
  ## and leaves the sidebar focused.
  let side = e.activeWindow
  let openResult =
    if e.sidebarTarget() < 0:
      beside()
    else:
      # Leave the sidebar through the shared primitive. The sidebar holds no
      # Insert session, so the focus move leaves nothing behind.
      discard e.leaveSidebar()
      inServed()
  if openResult.isErr:
    logError("handler", "Open from the file tree failed: " & openResult.error)
    e.state.statusMessage = "Error: " & openResult.error
    e.restoreSidebarFocus(side)
    return false
  true

proc splitFromSidebar(e: Editor, dir: Option[string], vertical: bool) =
  ## The sidebar has no tab to split, and its listing must not become one: open
  ## a window on the tab it serves and browse `dir`, or the tree's root, there,
  ## as Vim's split of a netrw window shows the listing again.
  let side = e.activeWindow
  let path =
    if dir.isSome:
      dir.get
    elif side.modeState.kind == mskFileTree:
      side.modeState.fileTree.rootPath
    else:
      getCurrentDir()
  let opened = e.openFromSidebar(
    proc(): Result[(), string] =
      if vertical:
        e.vsplitWithBuffer(e.tabBuffer(e.activeWindow))
      else:
        e.hsplitWithBuffer(e.tabBuffer(e.activeWindow)),
    proc(): Result[(), string] =
      # The window opened beside a lone sidebar is the split, as a split-viewer
      # request from it covers its new window in place.
      let tab = e.sidebarTab()
      if tab.isNone:
        return err("no buffer to open a window on")
      ?e.openWindowBesideSidebar(tab.get)
      ok(()),
  )
  if opened:
    e.enterFilerInActiveWindow(path)

proc splitFileFromSidebar(e: Editor, path: string, vertical: bool) =
  ## Open `path` in a split of the window the sidebar serves.
  discard e.openFromSidebar(
    proc(): Result[(), string] =
      if vertical:
        e.vsplit(some(path))
      else:
        e.hsplit(some(path)),
    proc(): Result[(), string] =
      e.openFileInNewRightWindow(path),
  )

proc newFromSidebar(e: Editor, vertical: bool) =
  ## `:new` / `:vnew` open a window, so from the sidebar they split the window
  ## it serves, as `:split <file>` does.
  discard e.openFromSidebar(
    proc(): Result[(), string] =
      if vertical:
        e.vnew()
      else:
        e.new(),
    proc(): Result[(), string] =
      e.newBesideSidebar(),
  )

proc openFileFromSidebar(e: Editor, path: string) =
  ## From the sidebar, open `path` in the window it serves; if it is alone, in
  ## a new window to its right. The tree reveals the file.
  let side = e.activeWindow
  let opened = e.openFromSidebar(
    proc(): Result[(), string] =
      e.editFile(path),
    proc(): Result[(), string] =
      e.openFileInNewRightWindow(path),
  )
  if not opened:
    return
  if side.modeState.kind == mskFileTree:
    side.modeState.fileTree.revealPath(path)
  e.state.statusMessage = "Opened: " & path

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
    e.openFileFromSidebar(r.fileTreeFilePath)
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
    let prepareResult = e.prepareQuickRun(activeBuffer)
    if prepareResult.isErr:
      e.state.statusMessage = "QuickRun error: " & prepareResult.error
      logError("handler", "QuickRun prepare failed: " & prepareResult.error)
    else:
      let prepared = prepareResult.get
      e.state.pending.add PendingAsyncOp(
        kind: paoQuickRun,
        epoch: e.state.commandEpoch,
        quickRun: (
          cmd: prepared.command.cmd,
          args: prepared.command.args,
          filePath: prepared.filePath,
          workDir: prepared.workDir,
        ),
      )
      if e.config.notification.screenNotifications and
          e.config.notification.quickRunScreenNotify:
        e.state.statusMessage = quickRunStartupMessage(prepared.filePath)
    return true
  of hrVSplit:
    if r.vsplitFilename.isNone and e.activeWindow.viewerEntry.isSome:
      let splitResult = e.splitViewer(vpVSplit)
      if splitResult.isErr:
        e.state.statusMessage = "Error: " & splitResult.error
      return true
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
    if splitFilename.isNone and e.activeWindow.isSidebar:
      e.splitFromSidebar(filerPath, vertical = true)
      return true
    if e.activeWindow.isSidebar and splitFilename.isSome:
      e.splitFileFromSidebar(splitFilename.get, vertical = true)
      return true
    let splitResult = e.vsplit(splitFilename)
    if splitResult.isErr:
      logError("handler", "Vertical split failed: " & splitResult.error)
      e.state.statusMessage = "Error: " & splitResult.error
    elif filerPath.isSome:
      e.enterFilerInActiveWindow(filerPath.get)
    return true
  of hrHSplit:
    if r.hsplitFilename.isNone and e.activeWindow.viewerEntry.isSome:
      let splitResult = e.splitViewer(vpHSplit)
      if splitResult.isErr:
        e.state.statusMessage = "Error: " & splitResult.error
      return true
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
    if splitFilename.isNone and e.activeWindow.isSidebar:
      e.splitFromSidebar(filerPath, vertical = false)
      return true
    if e.activeWindow.isSidebar and splitFilename.isSome:
      e.splitFileFromSidebar(splitFilename.get, vertical = false)
      return true
    let splitResult = e.hsplit(splitFilename)
    if splitResult.isErr:
      logError("handler", "Horizontal split failed: " & splitResult.error)
      e.state.statusMessage = "Error: " & splitResult.error
    elif filerPath.isSome:
      e.enterFilerInActiveWindow(filerPath.get)
    return true
  of hrNew:
    if e.activeWindow.isSidebar:
      e.newFromSidebar(vertical = false)
      return true
    let newResult = e.new()
    if newResult.isErr:
      logError("handler", "New failed: " & newResult.error)
      e.state.statusMessage = "Error: " & newResult.error
    return true
  of hrVnew:
    if e.activeWindow.isSidebar:
      e.newFromSidebar(vertical = true)
      return true
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
