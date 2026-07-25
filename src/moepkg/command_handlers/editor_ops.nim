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

## Editor operations shared by Command mode handler and result processor.
##
## Contains editor-level helpers (mode entry, viewport updates, file save)
## invoked by both `handleCommandModeKeyCombo` and `processResult`. Kept in
## a separate module so both consumers can share the code without pulling
## in a circular import.

import std/[options, os, times, strutils, tables]

import pkg/results

import
  ../[
    editor, editor_window_state, editor_window_layout, modes, buffer, logger, types,
    filer, filetree, config_loader, terminal_mode, window_manager, log_viewer,
    syntax_checker, render_utils, motion,
  ]

import ./handler_result

proc trySaveLogViewerBuffer*(e: Editor): string =
  ## When the active window is showing the log viewer, persist its content
  ## to a timestamped file in the current directory. Returns a status message
  ## describing the outcome, or an empty string when not in LogViewer mode.
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
    cursorPos, lineCount, e.showStatusLine, e.state.windowDisplay.viewportReservedLines,
    e.lineWrap, activeBuffer, viewportOffset, e.tabStop,
  )

proc processSaveAndQuitResult*(e: Editor, r: HandlerResult): bool =
  ## Process hrSaveAndQuit: save file and return false (quit) on success,
  ## true (continue) on failure.
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
  ## Process hrSaveAll: save every modified buffer and report the outcome.
  ## Note: buildOnSave / syntaxCheckOnSave are intentionally not run here —
  ## :wa is a batch operation and triggering them per buffer would fan out
  ## N builds for N saved files.
  let saveResult = e.saveAllBuffers(r.forceSaveAll)
  let msg = saveAllStatusMessage(saveResult)
  # Always surface failures / skips / no-op; gate the success summary on
  # saveScreenNotify to match single-file :w behavior.
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
  ## Process hrSaveAllAndQuit: save every modified buffer and return false
  ## (quit) on full success, true (continue) when any save failed or any
  ## buffer was skipped due to external modification without force.
  let saveResult = e.saveAllBuffers(r.forceSaveAllAndQuitAfter)
  if saveResult.failures.len > 0 or saveResult.skippedExternal.len > 0:
    e.state.statusMessage = saveAllStatusMessage(saveResult)
    logError("handler", "Save all and quit aborted: " & e.state.statusMessage)
    return true
  logInfo("handler", "All files saved, quitting editor")
  false

proc processSaveResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer) =
  ## Process hrSave: save active buffer (or LogViewer/Config content) and
  ## trigger buildOnSave / syntaxCheckOnSave side effects.
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
  ## Process hrGotoLine: move cursor to the specified line number.
  let lineNum = r.lineNumber
  if lineNum > 0:
    # Clamp to last line if lineNum exceeds buffer length
    e.activeWindow.cursor.line = min(lineNum, activeBuffer.len) - 1
    e.activeWindow.cursor.column = 0
    e.updateViewportForCursor(e.cursor)

proc enterFilerInActiveWindow*(e: Editor, path: string) =
  ## Switch the active window to Filer mode with the given directory path.
  e.setMode(EditorMode.Filer)
  let activeWin = e.activeWindow
  activeWin.mode = EditorMode.Filer
  let filerState = newFilerState(path)
  # Capture the current position so quitting the filer can restore it.
  filerState.originCursor = activeWin.cursor
  filerState.originTopLine = activeWin.viewport.topLine
  filerState.originLeftColumn = activeWin.viewport.leftColumn
  activeWin.saveOriginalBuffer()
  activeWin.modeState = ModeState(kind: mskFiler, filer: filerState)
  activeWin.buffer = filerState.createFilerTextBuffer(e.config.filer.showIcons)
  activeWin.cursor = BufferPosition(line: 0, column: 0)
  activeWin.viewport.resetViewportTop()
  activeWin.viewport.leftColumn = 0

proc toggleFileTree*(e: Editor, pathOpt: Option[string], activeBuffer: TextBuffer) =
  ## Toggle the fileTree sidebar. If one already exists, close it.
  ## If none exists, open one.
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
  ## Open a new Terminal session as its own tab in the active window.
  ## The session is tracked in `e.terminalStates` keyed by the buffer id
  ## so the user can move between tabs without tearing down the PTY.
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
  ## Route a `:theme` selection through `e.config.theme` + `initTheme` so
  ## `themeColorsFromFile` and `config.theme.{kind,path}` stay in sync with
  ## `themeColors`. Otherwise a later `saveConfigToToml` would stamp the
  ## newly loaded colors over the previously configured theme file.
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
