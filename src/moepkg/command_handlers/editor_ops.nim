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

## Editor helpers shared by the Command mode handler and result processor
## without a circular import.

import std/[options, os, times, strutils, tables]

import pkg/results

import
  ../[
    editor, editor_window_state, editor_window_layout, modes, buffer, logger, types,
    filer, filetree, config_loader, terminal_mode, window_manager, log_viewer,
    syntax_checker, render_utils, motion, viewer_mode,
  ]

import handler_result

proc trySaveLogViewerBuffer*(e: Editor): string =
  ## Save the log viewer's content to a timestamped file in the current
  ## directory; returns the status message or "" outside LogViewer mode.
  let activeWin = e.activeWindow
  if e.state.mode != EditorMode.LogViewer or activeWin.modeState.kind != mskLogViewer:
    return ""
  let
    kind = activeWin.modeState.logViewer.contentKind
    path = getCurrentDir() / logViewerSaveFileName(kind, now())
    writeRes = saveLogViewerContentToFile(activeWin.buffer.getTextString(), path)
  if writeRes.isOk:
    return "Log saved: " & path
  return "Log save failed: " & writeRes.error

proc getBufferInfos*(e: Editor): seq[BufferInfo] =
  ## Extract buffer information from the buffer list for BufferManager
  result = @[]
  let currentBuffer = e.activeBuffer()
  for buf in e.buffers:
    result.add(
      BufferInfo(
        filePath: buf.filePath,
        isModified: buf.isModified,
        isActive: buf == currentBuffer,
      )
    )

proc updateViewportForCursor*(e: Editor, pos: BufferPosition) =
  ## Update viewport to follow cursor position
  ## Common helper to avoid code duplication in search operations
  let
    activeBuffer = e.activeBuffer()
    lineCount = activeBuffer.len
    cursorPos = CursorPosition(x: pos.column, y: pos.line)
    viewportOffset = viewportOffsetFor(activeBuffer, e.state)

  e.handlerManager.motionController.viewportManager.updateViewport(
    cursorPos,
    lineCount,
    e.showStatusLine,
    e.state.motionReservedLines(),
    e.state.effectiveLineWrap(),
    activeBuffer,
    viewportOffset,
    e.tabStop,
  )

proc modifiedBufferCountExcept*(e: Editor, exclude: TextBuffer): int =
  ## Number of modified buffers other than `exclude`.
  for buf in e.buffers:
    if buf != exclude and buf.isModified:
      result.inc

proc quitDiscardsBuffersError*(e: Editor, exclude: TextBuffer): string =
  ## Error for a quit that would end the session while buffers other than
  ## `exclude` are still modified, or "" when there are none. Such a buffer
  ## need not be visible anywhere: an LSP rename edits its targets in buffers
  ## that join no window.
  let count = e.modifiedBufferCountExcept(exclude)
  if count == 0:
    return ""
  "No write since last change: " & $count & " other buffer" &
    (if count > 1: "s" else: "") & " modified (add ! to override)"

proc processSaveAndQuitResult*(e: Editor, r: HandlerResult): bool =
  ## Save and quit: return false on success, true on failure.
  if not r.forceQuitAfterSave:
    # :wq/:x end the session, not just the window, so the other buffers go too.
    let discardErr = e.quitDiscardsBuffersError(e.activeBuffer())
    if discardErr.len > 0:
      e.state.statusMessage = discardErr
      return true
  let saveResult = e.saveFile(r.saveAndQuitFilename, r.forceQuitAfterSave)
  if saveResult.isErr:
    logError("handler", "Save and quit failed: " & saveResult.error)
    e.state.statusMessage = "Error: " & saveResult.error
    return true
  else:
    logInfo("handler", "File saved, quitting editor")
    return false

proc saveAllStatusMessage(saveResult: SaveAllBuffersResult): string =
  ## Build a status message summarising a saveAllBuffers result.
  if saveResult.failures.len > 0:
    let first = saveResult.failures[0]
    if saveResult.failures.len == 1:
      return "Save failed: " & first.path & ": " & first.error
    return
      "Save failed for " & $saveResult.failures.len & " files; first: " & first.path &
      ": " & first.error
  if saveResult.savedCount == 0:
    if saveResult.skippedExternal.len > 0:
      return
        "No files saved (" & $saveResult.skippedExternal.len &
        " externally modified, use :wa! to override)"
    return "No modified files to save"
  var msg =
    if saveResult.savedCount == 1:
      "Saved: " & saveResult.savedPaths[0]
    else:
      "Saved " & $saveResult.savedCount & " files"
  if saveResult.skippedExternal.len > 0:
    msg.add(
      " (" & $saveResult.skippedExternal.len &
        " skipped: externally modified, use :wa! to override)"
    )
  msg

proc processSaveAllResult*(e: Editor, r: HandlerResult) =
  ## Save all modified buffers and report the outcome.
  ## buildOnSave / syntaxCheckOnSave are skipped: :wa is a batch operation.
  let saveResult = e.saveAllBuffers(r.forceSaveAll)
  let msg = saveAllStatusMessage(saveResult)
  # Surface failures / skips / no-op; gate the success summary on saveScreenNotify.
  if saveResult.failures.len > 0 or saveResult.skippedExternal.len > 0 or
      saveResult.savedCount == 0:
    e.state.statusMessage = msg
  elif e.config.notification.screenNotifications and
      e.config.notification.saveScreenNotify:
    e.state.statusMessage = msg
  if e.config.notification.logNotifications and e.config.notification.saveLogNotify and
      saveResult.savedCount > 0:
    if saveResult.savedCount == 1:
      logInfo("handler", "Saved file via :wa: " & saveResult.savedPaths[0])
    else:
      logInfo("handler", "Saved " & $saveResult.savedCount & " files via :wa")

proc processSaveAllAndQuitResult*(e: Editor, r: HandlerResult): bool =
  ## Save all and quit: false on full success, true if any save failed or
  ## was skipped for external modification without force.
  let saveResult = e.saveAllBuffers(r.forceSaveAllAndQuitAfter)
  if saveResult.failures.len > 0 or saveResult.skippedExternal.len > 0:
    e.state.statusMessage = saveAllStatusMessage(saveResult)
    logError("handler", "Save all and quit aborted: " & e.state.statusMessage)
    return true
  logInfo("handler", "All files saved, quitting editor")
  false

proc processSaveResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer) =
  ## Save the active buffer (or LogViewer/Config content) and run the
  ## buildOnSave / syntaxCheckOnSave side effects.
  if e.state.mode == EditorMode.LogViewer:
    let msg = e.trySaveLogViewerBuffer()
    if msg.len > 0:
      e.state.statusMessage = msg
  elif e.state.mode == EditorMode.Config:
    let configPath = getConfigPath()
    var backupOk = true
    if fileExists(configPath):
      let backupPath = configPath & ".bac"
      try:
        copyFile(configPath, backupPath)
        logInfo("config", "Backed up existing config to: " & backupPath)
      except CatchableError as ex:
        backupOk = false
        e.state.statusMessage = "Failed to backup config: " & ex.msg
        logError("config", "Failed to backup config: " & ex.msg)
    if backupOk:
      let saveResult = saveConfig(e.config)
      if saveResult.isOk:
        e.state.statusMessage = "Config saved: " & configPath
        logInfo("config", "Config saved: " & configPath)
      else:
        e.state.statusMessage = "Failed to save config: " & saveResult.error
        logError("config", "Failed to save config: " & saveResult.error)
  else:
    let saveResult = e.saveFile(r.saveFilename, r.forceSave)
    if saveResult.isErr:
      logError("handler", "Save command failed: " & saveResult.error)
      e.state.statusMessage = "Error: " & saveResult.error
    else:
      let savedPath =
        if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: "file"
      if e.config.notification.logNotifications and e.config.notification.saveLogNotify:
        logInfo("handler", "File saved via command: " & savedPath)
      if e.config.notification.screenNotifications and
          e.config.notification.saveScreenNotify:
        e.state.statusMessage = "Saved: " & savedPath
      if e.config.buildOnSave.enable:
        let customCmd =
          if e.config.buildOnSave.command.isSome:
            e.config.buildOnSave.command.get
          else:
            ""
        let workspaceRoot =
          if e.config.buildOnSave.workspaceRoot.isSome:
            e.config.buildOnSave.workspaceRoot.get
          else:
            parentDir(savedPath)
        e.state.pending.add PendingAsyncOp(
          kind: paoBuild,
          build: (
            path: savedPath,
            language: activeBuffer.language.ord,
            customCmd: customCmd,
            workspaceRoot: workspaceRoot,
          ),
        )
        if e.config.notification.screenNotifications and
            e.config.notification.buildOnSaveScreenNotify:
          e.state.statusMessage = "Building: " & savedPath
      if e.config.syntaxChecker.enable and
          syntaxCheckCommand(savedPath, activeBuffer.language).isOk:
        e.state.pending.add PendingAsyncOp(
          kind: paoSyntaxCheck,
          syntaxCheck: (path: savedPath, language: activeBuffer.language.ord),
        )

proc processGotoLineResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer) =
  ## Move the cursor to the specified line number.
  let lineNum = r.lineNumber
  if lineNum > 0:
    # Clamp to last line if lineNum exceeds buffer length
    e.activeWindow.cursor.line = min(lineNum, activeBuffer.len) - 1
    e.activeWindow.cursor.column = 0
    e.updateViewportForCursor(e.cursor)

proc enterFilerInActiveWindow*(e: Editor, path: string) =
  let filerState = newFilerState(path)
  discard e.enterViewerMode(
    EditorMode.Filer,
    ModeState(kind: mskFiler, filer: filerState),
    filerState.createFilerTextBuffer(e.config.filer.showIcons),
    vpInPlace,
  )

proc focusFileTreeWindow*(e: Editor): bool =
  ## Focus the fileTree sidebar, or return false if none is open. Unlike
  ## `toggleFileTree`, it never closes the sidebar.
  for i, win in e.windowManager.windows:
    if win.mode == EditorMode.FileTree:
      e.windowManager.activateWindow(i)
      e.syncActiveWindow()
      return true
  false

proc toggleFileTree*(e: Editor, pathOpt: Option[string], activeBuffer: TextBuffer) =
  ## Toggle the fileTree sidebar (open if absent, close if present).
  var existingIdx = -1
  for i, win in e.windowManager.windows:
    if win.mode == EditorMode.FileTree:
      existingIdx = i
      break

  if existingIdx >= 0:
    # Close existing fileTree window
    e.windowManager.activateWindow(existingIdx)
    e.syncActiveWindow()
    e.activeWindow.clearModeState(EditorMode.FileTree)
    discard e.closeWindow()
    return

  # Create fileTree window as left-side vsplit (follows vsplit pattern)
  let rootPath =
    if pathOpt.isSome:
      pathOpt.get
    elif activeBuffer.filePath.isSome:
      parentDir(activeBuffer.filePath.get)
    else:
      getCurrentDir()

  let ftState = newFileTreeState(rootPath, e.config.fileTree.width)
  let ftBuffer = ftState.createFileTreeTextBuffer(e.config.filer.showIcons)
  let ftWidth = ftState.width

  # Compute full extent across ALL windows for filetree's full-height span
  var minX = int.high
  var maxXEnd = 0
  var minY = int.high
  var maxYEnd = 0
  for win in e.windowManager.windows:
    minX = min(minX, win.viewport.x)
    maxXEnd = max(maxXEnd, win.viewport.x + win.viewport.width)
    minY = min(minY, win.viewport.y)
    maxYEnd = max(maxYEnd, win.viewport.y + win.viewport.height)

  let
    totalWidth = maxXEnd - minX
    startX = minX
    fullHeight = maxYEnd - minY

  e.windowManager.deactivateAllWindows()

  let ftWindow = EditorWindow(
    buffer: ftBuffer,
    bufferIds: @[ftBuffer.id], # FileTree pane has its own single-tab list
    viewport: ViewPort(
      topLine: 0, leftColumn: 0, width: ftWidth, height: fullHeight, x: startX, y: minY
    ),
    cursor: BufferPosition(line: 0, column: 0),
    active: false,
    mode: EditorMode.FileTree,
    modeState: ModeState(kind: mskFileTree, fileTree: ftState),
    fixedWidth: some(ftWidth),
    wrapCountCache: WrapCountCache(),
  )

  e.windowManager.windows.insert(ftWindow, 0)
  e.windowManager.activeWindowIndex += 1
  e.windowManager.windows[e.windowManager.activeWindowIndex].active = true

  # Group by Y-row and equalize each row's widths
  var yRows: seq[int] = @[]
  for i in 1 ..< e.windowManager.windows.len:
    let y = e.windowManager.windows[i].viewport.y
    if y notin yRows:
      yRows.add(y)

  for y in yRows:
    var group: seq[int] = @[0] # filetree spans all rows (fullHeight)
    for i in 1 ..< e.windowManager.windows.len:
      if e.windowManager.windows[i].viewport.y == y:
        group.add(i)
    e.windowManager.equalizeWidthsInGroup(group, totalWidth, startX)

  e.syncActiveWindow()

proc enterTerminalInActiveWindow*(e: Editor, command: string) =
  ## Open a new Terminal session as a tab in the active window; the PTY is
  ## tracked in `e.terminalStates` by buffer id so tabs survive switching.
  let activeWin = e.activeWindow
  let (cols, rows) = e.calculateTerminalAreaDimensions(activeWin)
  let termResult = newTerminalState(command, cols, rows)
  if termResult.isErr:
    e.state.statusMessage = "Terminal error: " & termResult.error
    return

  let termState = termResult.get
  let termBuf = newTextBuffer("")
  termBuf.displayName = some("[Terminal: " & command & "]")

  e.addBuffer(termBuf)
  e.addBufferToWindowList(termBuf)
  e.terminalStates[termBuf.id] = termState

  activeWin.buffer = termBuf
  activeWin.modeState = ModeState(kind: mskTerminal, terminal: termState)
  activeWin.cursor = BufferPosition(line: 0, column: 0)
  activeWin.viewport.resetViewportTop()
  activeWin.viewport.leftColumn = 0
  e.setMode(EditorMode.Terminal)

proc applyThemeCommand*(e: Editor, themeName: string) =
  ## Apply a `:theme` selection via `initTheme` so `config.theme` and
  ## `themeColors` stay in sync before saveConfigToToml.
  if themeName == "default":
    e.config.theme.kind = tkDefault
    e.config.theme.path = ""
    initTheme(e.config)
    e.state.statusMessage = "Theme changed to: default"
    return

  let themePath = getHomeDir() / ".config" / "moe" / "themes" / (themeName & ".toml")
  if not fileExists(themePath):
    e.state.statusMessage = "Theme not found: " & themeName
    return

  let previousTheme = e.config.theme
  e.config.theme.kind = tkConfig
  e.config.theme.path = themePath
  var vr = newValidationResult()
  initTheme(e.config, vr)
  if vr.hasErrors:
    e.config.theme = previousTheme
    initTheme(e.config)
    e.state.statusMessage = "Failed to load theme: " & vr.toErrorMessages.join("; ")
  else:
    e.state.statusMessage = "Theme changed to: " & themeName
