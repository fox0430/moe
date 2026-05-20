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

## Command mode event handler
##
## This module handles the command-line overlay mode (`:` commands).
## Extracted from handler.nim to reduce file size.

import std/[options, os, strutils, unicode, monotimes]

import pkg/[celina, results, chronos]

import
  ../[
    editor, editor_window_layout, editor_window_state, key_bindings, modes, buffer,
    logger, types, motion, filer, filetree, quick_run_utils, help_viewer,
    buffer_manager, bookmark_manager, backup_manager, backup, debug_viewer,
    config_loader, message_log, command_line, color, theme, terminal_mode,
    command_completion, render_utils, config_mode, log_viewer, syntax_checker,
    window_manager, registers, unicode_utils, git_conflict, status_line,
  ]
import handler_manager

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
  # Fallback if buffer list is empty
  if result.len == 0:
    result.add(
      BufferInfo(
        filePath: e.textBuffer.filePath,
        isModified: e.textBuffer.isModified,
        isActive: true,
      )
    )

proc updateViewportForCursor*(e: Editor, pos: BufferPosition) =
  ## Update viewport to follow cursor position
  ## Common helper to avoid code duplication in search operations
  let
    activeBuffer = e.activeBuffer()
    lineCount = activeBuffer.len
    cursorPos = CursorPosition(x: pos.column, y: pos.line)
    lineNumOffset = calculateViewportOffset(
      activeBuffer, e.state.display.showLineNumbers, e.state.display.showSidebar,
      e.state.display.scrollbar, e.state.display.scrollbarWidth,
    )

  e.handlerManager.motionController.viewportManager.updateViewport(
    cursorPos, lineCount, e.state.display.showStatusLine,
    e.state.windowDisplay.viewportReservedLines, e.state.display.lineWrap, activeBuffer,
    lineNumOffset, e.state.display.tabStop,
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
  activeWin.saveOriginalBuffer()
  activeWin.modeState = ModeState(kind: mskFiler, filer: filerState)
  activeWin.buffer = filerState.createFilerTextBuffer(e.config.filer.showIcons)
  activeWin.cursor = BufferPosition(line: 0, column: 0)
  activeWin.viewport.topLine = 0
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
  e.state.windowDisplay.needsFullRedraw = true

proc findFirstSubstituteMatch*(
    lines: seq[string], pattern: string
): Option[BufferPosition] =
  ## Find the first occurrence of pattern in the given lines (plain string match).
  ## Matches the plain-string semantics used by executeSubstitute / updateSubstitutePreview.
  if pattern.len == 0:
    return none(BufferPosition)
  for lineIdx in 0 ..< lines.len:
    let idx = lines[lineIdx].find(pattern)
    if idx >= 0:
      let charCol = byteToCharPos(lines[lineIdx], idx)
      return some(BufferPosition(line: lineIdx, column: charCol))
  return none(BufferPosition)

proc jumpToFirstSubstituteMatch*(e: Editor, pattern: string) =
  ## Move cursor/viewport to the first pattern match (incsearch-like behavior).
  ## If no match is found, restore cursor to the position captured at preview start.
  let match =
    findFirstSubstituteMatch(e.state.ui.substitutePreview.originalLines, pattern)
  if match.isSome:
    let pos = match.get
    e.cursor = pos
    e.updateViewportForCursor(pos)
  else:
    e.cursor = e.state.ui.substitutePreview.originalCursor
    e.activeWindow.viewport.topLine = e.state.ui.substitutePreview.originalTopLine
    e.activeWindow.viewport.leftColumn = e.state.ui.substitutePreview.originalLeftColumn

proc updateSubstitutePreviewIfNeeded(e: Editor) =
  ## Update or cancel the live substitute preview based on the current command
  ## text. Call after any edit to commandText (backspace, delete, char input).
  ##
  ## Behavior:
  ## - Pattern only (e.g. ":%s/foo"): jump cursor to first match (incsearch-like)
  ## - Pattern + replacement (e.g. ":%s/foo/bar"): also preview the replacement
  ##   in the buffer when config.highlight.replaceText is enabled.
  if e.state.commandText.contains("s/"):
    let pattern = extractSubstitutePattern(e.state.commandText)
    let (replacement, hasReplacement) =
      extractSubstituteReplacement(e.state.commandText)
    let flags = extractSubstituteFlags(e.state.commandText)
    let isGlobal = "g" in flags
    if pattern.len > 0:
      if not e.state.ui.substitutePreview.isActive:
        e.startSubstitutePreview()
      if hasReplacement and e.config.highlight.replaceText:
        e.updateSubstitutePreview(pattern, replacement, isGlobal)
      else:
        # Pattern-only state: restore buffer (in case a replacement preview was
        # previously applied) but keep the preview active for cursor tracking.
        e.restoreFromPreview()
        e.state.windowDisplay.needsFullRedraw = true
      e.jumpToFirstSubstituteMatch(pattern)
    elif e.state.ui.substitutePreview.isActive:
      e.cancelSubstitutePreview()
    else:
      e.state.windowDisplay.needsFullRedraw = true

proc enterTerminalInActiveWindow(e: Editor, command: string) =
  ## Switch the active window to Terminal mode.
  let activeWin = e.activeWindow
  let (cols, rows) = e.calculateTerminalAreaDimensions(activeWin)
  let termResult = newTerminalState(command, cols, rows)
  if termResult.isErr:
    e.state.statusMessage = "Terminal error: " & termResult.error
    return

  let termState = termResult.get
  activeWin.saveOriginalBuffer()
  activeWin.modeState = ModeState(kind: mskTerminal, terminal: termState)
  # Create a placeholder buffer (grid will be rendered directly)
  activeWin.buffer = newTextBuffer("")
  activeWin.cursor = BufferPosition(line: 0, column: 0)
  activeWin.viewport.topLine = 0
  activeWin.viewport.leftColumn = 0
  e.setMode(EditorMode.Terminal)
  activeWin.mode = EditorMode.Terminal

proc handleCommandModeKeyCombo*(e: Editor, keyCombo: KeyCombo): bool

proc insertPastedTextInCommand*(e: Editor, text: string) =
  ## Insert pasted text at the current command-line cursor.
  ## The command line is single-line: only the first line of the paste is used
  ## (everything up to the first newline, with a trailing CR stripped).
  let nlIdx = text.find('\n')
  var insertText =
    if nlIdx >= 0:
      text[0 ..< nlIdx]
    else:
      text
  if insertText.len > 0 and insertText[^1] == '\r':
    insertText = insertText[0 ..< ^1]
  if insertText.len == 0:
    return

  e.state.commandState.historyIndex = -1
  if e.state.commandText.len == 0:
    e.state.commandText = ":"
    e.state.commandCursor = 0

  let bytePos = charToBytePos(e.state.commandText, e.state.commandCursor + 1)
  e.state.commandText =
    e.state.commandText[0 ..< bytePos] & insertText & e.state.commandText[bytePos ..^ 1]
  e.state.commandCursor += insertText.runeLen

  e.state.commandCompletionManager.cancelCompletion()
  e.updateSubstitutePreviewIfNeeded()
  e.state.windowDisplay.needsFullRedraw = true

proc handleCommandModeEvent*(e: Editor, event: Event): bool =
  ## Handle Command mode events (special handling for text input)
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  return e.handleCommandModeKeyCombo(keyComboOpt.get)

proc handleCommandModeKeyCombo*(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in command-line mode, with runtime mapping support.
  ##
  ## Runtime-mapping routing is delegated to `KeyRouter.feedKey`. Command
  ## overlay execution differs from base mode in two ways:
  ## 1. On no-match flush we replay *all* accumulated keys (including the
  ##    current one) and return without falling through.
  ## 2. When the mappings table is empty but the accumulator still holds
  ##    keys (mappings were removed mid-sequence), we flush the leftovers
  ##    first, then fall through to handle the current key normally.
  if not e.keyBindingRegistry.isReplayingMapping:
    # Case: mappings table is empty but accumulator has leftover keys
    # (mappings were removed mid-sequence). Replay the leftovers first, then
    # fall through to process the current key normally.
    let leftover = e.keyRouter.flushPendingAccumulator(EditorMode.Command)
    if leftover.len > 0:
      var flushResult = true
      e.keyRouter.withReplay:
        for k in leftover:
          if not e.handleCommandModeKeyCombo(k):
            flushResult = false
            break
      if not flushResult:
        return false
      # Fall through to process current key normally
    else:
      let route = e.keyRouter.feedKey(EditorMode.Command, keyCombo)
      case route.kind
      of rrUnhandled, rrCancelled:
        discard # Fall through to normal handling
      of rrExecuteRuntimeCommand:
        # Unreachable: the Command overlay's mappings table is filtered to
        # key-seq only (see `KeyRouter.mappingsFor`), so `feedKey` never
        # returns rrExecuteRuntimeCommand for `EditorMode.Command`. Guarded
        # for case exhaustiveness; keep the historical no-op for safety.
        return true
      of rrExecuteRuntimeKeySequence:
        var replayResult = true
        e.keyRouter.withReplay:
          for targetKeyStr in route.targetKeys:
            let targetKeyOpt = stringToKeyCombo(targetKeyStr)
            if targetKeyOpt.isSome:
              if not e.handleCommandModeKeyCombo(targetKeyOpt.get):
                replayResult = false
                break
        return replayResult
      of rrWaiting:
        return true
      of rrUnhandledBatch:
        # Command overlay style: replay *all* accumulated keys (including the
        # current one) and return without falling through.
        var flushResult = true
        e.keyRouter.withReplay:
          for k in route.keys:
            if not e.handleCommandModeKeyCombo(k):
              flushResult = false
              break
        return flushResult

  # Handle Escape to exit Command mode and return to previous (base) mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.state.commandCompletionManager.cancelCompletion()
    # Cancel substitute preview and restore original content
    e.cancelSubstitutePreview()
    # Exit overlay and restore base mode
    e.state.exitOverlay()
    e.setMode(e.state.mode) # Sync window mode
    # Insert-Normal mode (Ctrl-o): return to Insert after overlay cancel
    if e.state.insertNormalMode and e.state.mode == EditorMode.Normal:
      e.state.insertNormalMode = false
      e.setMode(EditorMode.Insert)
    return true

  # Handle Tab key for command completion
  if keyCombo.isSpecial and (keyCombo.special == skTab or keyCombo.special == skBackTab):
    let mgr = e.state.commandCompletionManager
    let hasSpace = ' ' in e.state.commandText

    proc applyCompletion(): bool =
      ## Apply the selected completion to command text
      ## Returns true if a directory was selected (needs re-trigger)
      let selected = mgr.getSelectedCommand()
      if selected.len == 0:
        return false

      case mgr.mode
      of cmCommand:
        e.state.commandText = ":" & selected
        e.state.commandCursor = selected.runeLen
        return false
      of cmFilePath:
        # Use original directory prefix (saved when completion started)
        let newArg = mgr.originalDirPrefix & selected
        e.state.commandText = ":" & mgr.baseCommand & " " & newArg
        e.state.commandCursor = mgr.baseCommand.runeLen + 1 + newArg.runeLen
        # Return true if directory selected (ends with /)
        return selected.endsWith("/")
      of cmSetOption:
        # Replace only the argument part
        let (cmd, _) = parseCommandLine(e.state.commandText)
        e.state.commandText = ":" & cmd & " " & selected
        e.state.commandCursor = cmd.runeLen + 1 + selected.runeLen
        return false

    if kmShift in keyCombo.modifiers or keyCombo.special == skBackTab:
      # Shift+Tab (or BackTab): select previous item
      if mgr.isActive():
        mgr.selectPrevious()
        # Apply if something is now selected
        if mgr.menu.selectedIndex >= 0:
          discard applyCompletion()
    else:
      # Tab: trigger or select next item
      if mgr.isActive():
        mgr.selectNext()
        # Apply if something is now selected
        if mgr.menu.selectedIndex >= 0:
          discard applyCompletion()
      else:
        # Trigger completion
        if hasSpace:
          mgr.triggerArgumentCompletion(e.state.commandText, getCurrentDir())
        else:
          mgr.triggerCompletion(e.commandLineParser, e.state.commandText)
    return true

  # Handle Enter to execute command
  let isEnter =
    (keyCombo.isSpecial and keyCombo.special == skEnter) or
    (not keyCombo.isSpecial and (keyCombo.char == "\n" or keyCombo.char == "\r"))

  if isEnter:
    # If completion popup is active with a selection, confirm it
    if e.state.commandCompletionManager.isActive() and
        e.state.commandCompletionManager.menu.selectedIndex >= 0:
      let mgr = e.state.commandCompletionManager
      # Check if selected item is a directory (for file path mode)
      let isDir = mgr.mode == cmFilePath and mgr.getSelectedCommand().endsWith("/")
      let isFile = mgr.mode == cmFilePath and not isDir
      # Check if it's an action that should execute immediately
      let shouldExecuteNow =
        isFile or mgr.mode == cmSetOption or (
          mgr.mode == cmCommand and
          e.commandLineParser.isNoArgumentAction(mgr.getSelectedCommand())
        )
      mgr.cancelCompletion()
      # If directory was confirmed, re-trigger completion for its contents
      if isDir:
        mgr.triggerArgumentCompletion(e.state.commandText, getCurrentDir())
        return true
      # If not a no-argument command, wait for more input
      if not shouldExecuteNow:
        return true
      # Otherwise, fall through to execute the command immediately

    # Cancel completion if active (no selection case)
    e.state.commandCompletionManager.cancelCompletion()

    # Cancel substitute preview before executing command
    # The command handler will apply the substitute properly with undo support
    if e.state.ui.substitutePreview.isActive:
      e.cancelSubstitutePreview()

    if e.state.commandText.len > 1: # Must have something after :
      # Use the command handler with active buffer
      let activeBuffer = e.activeBuffer()
      # Check if the buffer is shared across multiple windows
      let isShared = e.isBufferShared(activeBuffer)
      let commandToExecute = e.state.commandText
      let r = e.handlerManager.handleCommandMode(
        activeBuffer, commandToExecute, isShared, e.activeWindow.cursor.line
      )

      # Add to command history (without the leading ":")
      if commandToExecute.len > 1:
        e.addCommandToHistory(commandToExecute[1 ..^ 1])

      # requestQuickRun is independent of r.kind, check before case
      var quickRunHandled = false
      if e.state.requestQuickRun:
        e.state.requestQuickRun = false
        quickRunHandled = true
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
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)

      var overlayHandled = false

      case r.kind
      of hrQuit:
        return false # Signal app should quit
      of hrCquit:
        e.state.exitCode = 1
        return false # Signal app should quit with non-zero exit code
      of hrCloseWindow:
        # Handle window close - may also quit if last window
        let activeWin = e.activeWindow

        # Save buffer ref before clearModeState restores originalBuffer
        let splitBuf = activeWin.buffer
        activeWin.clearModeState(e.state.mode)

        if not e.state.mode.isFileEditMode:
          # For special modes with split windows, remove the temporary buffer
          if e.windowManager.windows.len > 1:
            let idx = e.bufferIndexById(splitBuf.id)
            if idx >= 0:
              evictGitCacheForBuffer(splitBuf)
              e.deleteBufferAt(idx)
              e.pruneBufferIdFromAllWindows(splitBuf.id)

        # Reset mode before closing
        e.state.previousMode = EditorMode.Normal
        activeWin.mode = EditorMode.Normal
        e.setMode(EditorMode.Normal)
        let shouldQuit = e.closeWindow
        if shouldQuit:
          return false # Last window closed, quit editor
      of hrGotoLine:
        e.processGotoLineResult(r, activeBuffer)
      of hrVSplit:
        # Handle vertical split
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
        # Handle horizontal split
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
      of hrEnew:
        # Handle enew (create new empty buffer)
        let enewResult = e.enew()
        if enewResult.isErr:
          logError("handler", "Enew failed: " & enewResult.error)
          e.state.statusMessage = "Error: " & enewResult.error
      of hrNew:
        # Handle new (create new empty buffer in horizontal split)
        let newResult = e.new()
        if newResult.isErr:
          logError("handler", "New failed: " & newResult.error)
          e.state.statusMessage = "Error: " & newResult.error
      of hrVnew:
        # Handle vnew (create new empty buffer in vertical split)
        let vnewResult = e.vnew()
        if vnewResult.isErr:
          logError("handler", "Vnew failed: " & vnewResult.error)
          e.state.statusMessage = "Error: " & vnewResult.error
      of hrEdit:
        if r.editFilename.isSome:
          # Handle edit with filename (open file in current window)
          let editResult = e.editFile(r.editFilename.get)
          if editResult.isErr:
            logError("handler", "Edit failed: " & editResult.error)
            e.state.statusMessage = "Error: " & editResult.error
          else:
            e.state.statusMessage = "Opened: " & r.editFilename.get
        else:
          # Handle reload current file (:e or :e!)
          let reloadResult = e.reloadCurrentFile()
          if reloadResult.isErr:
            logError("handler", "Reload failed: " & reloadResult.error)
            e.state.statusMessage = "Error: " & reloadResult.error
      of hrSetBoolOption:
        # Handle boolean option setting
        let opt = r.boolOption
        let val = r.boolValue
        case opt
        of bsoNumber:
          e.config.standard.number = val
          e.state.display.showLineNumbers = val
          e.state.statusMessage = "number = " & $val
        of bsoRelativeNumber:
          e.config.standard.relativeNumber = val
          e.state.display.relativeLineNumbers = val
          e.state.statusMessage = "relativenumber = " & $val
        of bsoCursorLine:
          e.config.highlight.currentLine = val
          e.state.display.showCursorLine = val
          e.state.statusMessage = "cursorline = " & $val
        of bsoCursorColumn:
          e.config.highlight.currentColumn = val
          e.state.display.showCursorColumn = val
          e.state.statusMessage = "cursorcolumn = " & $val
        of bsoStatusLine:
          e.config.standard.statusLine = val
          e.state.display.showStatusLine = val
          e.state.statusMessage = "statusline = " & $val
        of bsoSyntax:
          e.config.standard.syntax = val
          e.state.display.showSyntax = val
          e.state.statusMessage = "syntax = " & $val
        of bsoIndentationLines:
          e.config.standard.indentationLines = val
          e.state.display.showIndentationLines = val
          e.state.statusMessage = "indentationlines = " & $val
        of bsoAutoIndent:
          e.config.standard.autoIndent = val
          e.state.display.autoIndent = val
          e.state.statusMessage = "autoindent = " & $val
        of bsoAutoCloseParen:
          e.config.standard.autoCloseParen = val
          e.state.display.autoCloseParen = val
          e.state.statusMessage = "autocloseparen = " & $val
        of bsoAutoDeleteParen:
          e.config.standard.autoDeleteParen = val
          e.state.display.autoDeleteParen = val
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
          e.state.display.showCursorLine = val
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
          e.state.windowDisplay.needsFullRedraw = true
        of bsoHighlightGitConflictTwoColor:
          e.config.highlight.gitConflictTwoColor = val
          e.state.statusMessage = "highlightgitconflicttwocolor = " & $val
          e.state.windowDisplay.needsFullRedraw = true
        of bsoMultipleStatusLine:
          e.setMultiStatusLine(val)
        of bsoIgnoreCase:
          e.state.search.ignorecase = val
          e.state.statusMessage = "ignorecase = " & $val
        of bsoSmartCase:
          e.state.search.smartcase = val
          e.state.statusMessage = "smartcase = " & $val
        of bsoIncSearch:
          e.state.search.incsearch = val
          e.state.statusMessage = "incsearch = " & $val
        of bsoHlSearch:
          e.state.search.hlsearch = val
          e.state.statusMessage = "hlsearch = " & $val
        of bsoBuildOnSave:
          e.config.buildOnSave.enable = val
          e.state.statusMessage = "buildonsave = " & $val
        of bsoShowGitInactive:
          e.config.statusLine.showGitInactive = val
          e.state.statusMessage = "showgitinactive = " & $val
        of bsoLineWrap:
          e.config.standard.lineWrap = val
          e.setLineWrap(val)
          e.state.statusMessage = "wrap = " & $val
        of bsoExpandTab:
          e.config.standard.expandTab = val
          e.state.display.expandTab = val
          e.state.statusMessage = "expandtab = " & $val
        of bsoScrollbar:
          e.config.standard.scrollbar = val
          e.state.display.scrollbar = val
          e.state.statusMessage = "scrollbar = " & $val
        e.state.windowDisplay.needsFullRedraw = true
      of hrSetIntOption:
        # Handle integer option setting
        let opt = r.intOption
        let val = r.intValue
        case opt
        of isoTabStop:
          e.config.standard.tabStop = val
          e.state.display.tabStop = val
          e.state.statusMessage = "tabstop = " & $val
        of isoShiftWidth:
          e.config.standard.shiftWidth = val
          e.state.display.shiftWidth = val
          e.state.statusMessage = "shiftwidth = " & $val
        of isoSoftTabStop:
          e.config.standard.softTabStop = val
          e.state.display.softTabStop = val
          e.state.statusMessage = "softtabstop = " & $val
        of isoScrollbarWidth:
          e.config.standard.scrollbarWidth = val
          e.state.display.scrollbarWidth = val
          e.state.statusMessage = "scrollbarwidth = " & $val
        e.state.windowDisplay.needsFullRedraw = true
      of hrSetFloatOption:
        # Handle float option setting
        let opt = r.floatOption
        let val = r.floatValue
        case opt
        of fsoScrollFriction:
          e.config.smoothScroll.friction = val
          e.state.statusMessage = "scrollfriction = " & $val
        of fsoScrollAirDrag:
          e.config.smoothScroll.airDrag = val
          e.state.statusMessage = "scrollairdrag = " & $val
        e.state.windowDisplay.needsFullRedraw = true
      of hrClearSearchHighlight:
        # Handle clear search highlight (:noh)
        e.state.search.hlsearch = false
        e.state.windowDisplay.needsFullRedraw = true
      of hrShellCommand:
        # Set pending shell command to be executed by handleEventAsync
        e.state.pending.shellCommand = r.shellCommand
      of hrMan:
        # Set pending man page to be executed by handleEventAsync
        e.state.pending.manPage = r.hrManPage
      of hrBackground:
        # Set pending background flag to be handled by handleEventAsync
        e.state.pending.background = true
      of hrSave:
        if e.state.mode == EditorMode.Config:
          # In Config mode, :w saves the configuration file instead of a buffer
          let configPath = getConfigPath()

          # Backup existing config file if it exists
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
          # Handle file save
          let saveResult = e.saveFile(r.saveFilename, r.forceSave)
          if saveResult.isErr:
            logError("handler", "Save command failed: " & saveResult.error)
            e.state.statusMessage = "Error: " & saveResult.error
          else:
            # Get saved file path from active buffer
            let savedPath =
              if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: "file"
            # Log notification (controlled by config)
            if e.config.notification.logNotifications and
                e.config.notification.saveLogNotify:
              logInfo("handler", "File saved via command: " & savedPath)
            # Screen notification (controlled by config)
            if e.config.notification.screenNotifications and
                e.config.notification.saveScreenNotify:
              e.state.statusMessage = "Saved: " & savedPath

            # Build on save if enabled
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
              # Set pending build info for async processing
              e.state.pending.buildOnSave = (
                path: savedPath,
                language: activeBuffer.language.ord,
                customCmd: customCmd,
                workspaceRoot: workspaceRoot,
              )
              # Build on save screen notification (controlled by config)
              if e.config.notification.screenNotifications and
                  e.config.notification.buildOnSaveScreenNotify:
                e.state.statusMessage = "Building: " & savedPath

            # Syntax check on save if enabled (only for supported languages)
            if e.config.syntaxChecker.enable and
                syntaxCheckCommand(savedPath, activeBuffer.language).isOk:
              e.state.pending.syntaxCheck =
                (path: savedPath, language: activeBuffer.language.ord)
      of hrSaveAll:
        e.processSaveAllResult(r)
      of hrSaveAndQuit:
        return e.processSaveAndQuitResult(r)
      of hrSaveAllAndQuit:
        return e.processSaveAllAndQuitResult(r)
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
      of hrBufferDelete:
        e.deleteCurrentBuffer()
      of hrStripWhitespace:
        # Handle strip trailing whitespace
        let count = r.strippedLineCount
        if count > 0:
          e.state.statusMessage =
            "Stripped trailing whitespace from " & $count & " lines"
          e.state.windowDisplay.needsFullRedraw = true
        else:
          e.state.statusMessage = "No trailing whitespace found"
      of hrQuickRun:
        overlayHandled = true
        if not quickRunHandled:
          # Prepare QuickRun (sync) and set pending for async execution
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
            # QuickRun screen notification (controlled by config)
            if e.config.notification.screenNotifications and
                e.config.notification.quickRunScreenNotify:
              e.state.statusMessage = quickRunStartupMessage(prepared.filePath)
          # Return to Normal mode - exit overlay first
          e.state.exitOverlay()
          e.setMode(EditorMode.Normal)
      of hrBuild:
        overlayHandled = true
        # Handle Build command
        let filePath =
          if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: ""
        if filePath.len == 0:
          e.state.statusMessage = "Build error: File not saved"
          logError("handler", "Build failed: No file path")
        else:
          # Set pending build info for async processing
          e.state.pending.buildOnSave = (
            path: filePath,
            language: activeBuffer.language.ord,
            customCmd: "",
            workspaceRoot: parentDir(filePath),
          )
          e.state.statusMessage = "Building: " & filePath
        # Return to Normal mode - exit overlay first
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrSubstitute:
        overlayHandled = true
        # Handle substitute result - display count
        let count = r.hrSubstituteCount
        e.state.statusMessage = $count & " substitution" & (if count == 1: "" else: "s")
        e.state.windowDisplay.needsFullRedraw = true
        # Return to Normal mode - exit overlay first
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrDeleteLines:
        overlayHandled = true
        # Store deleted text in register (linewise)
        e.state.registers.setDeletedRegister(r.hrDeletedText, true)
        # Display count
        let count = r.hrDeletedLineCount
        e.state.statusMessage =
          $count & " line" & (if count == 1: "" else: "s") & " deleted"
        e.state.windowDisplay.needsFullRedraw = true
        # Clamp cursor to valid buffer range
        let maxLine = e.activeBuffer().len - 1
        if e.activeWindow.cursor.line > maxLine:
          e.activeWindow.cursor.line = maxLine
        e.activeWindow.cursor.column = 0
        # Return to Normal mode - exit overlay first
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrEnterFiler:
        overlayHandled = true
        # Enter filer mode with optional path - save base mode, exit overlay
        let baseModeBeforeOverlay = e.state.baseMode
        e.state.exitOverlay()
        e.state.previousMode = baseModeBeforeOverlay
        let startPath =
          if r.enterFilerPath.isSome:
            r.enterFilerPath.get
          elif activeBuffer.filePath.isSome:
            parentDir(activeBuffer.filePath.get)
          else:
            getCurrentDir()
        e.enterFilerInActiveWindow(startPath)
      of hrEnterTerminal:
        overlayHandled = true
        let baseModeBeforeOverlay = e.state.baseMode
        e.state.exitOverlay()
        e.state.previousMode = baseModeBeforeOverlay
        e.enterTerminalInActiveWindow(r.enterTerminalCommand)
      of hrEnterFileTree:
        overlayHandled = true
        e.state.exitOverlay()
        e.setMode(e.state.mode)
        e.toggleFileTree(r.enterFileTreePath, activeBuffer)
      of hrEnterLogViewer:
        overlayHandled = true
        # Open LogViewer in a new split window for editor messages - exit overlay first
        e.state.exitOverlay()
        let logLines = getMessageLog()
        let logContent =
          if logLines.len > 0:
            logLines.join("\n")
          else:
            ""
        let logBuffer = newTextBuffer(logContent)
        logBuffer.readOnly = true
        let splitResult = e.hsplitWithBuffer(logBuffer)
        if splitResult.isErr:
          e.state.statusMessage = "Failed to open log: " & splitResult.error
        else:
          e.setMode(EditorMode.LogViewer)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.LogViewer
          let logState = newLogViewerState(lckEditor)
          activeWin.modeState = ModeState(kind: mskLogViewer, logViewer: logState)
      of hrLspLog:
        overlayHandled = true
        # Open LogViewer in a new split window for LSP messages - exit overlay first
        e.state.exitOverlay()
        let logLines = getLspMessageLog()
        let logContent =
          if logLines.len > 0:
            logLines.join("\n")
          else:
            ""
        let logBuffer = newTextBuffer(logContent)
        logBuffer.readOnly = true
        let splitResult = e.hsplitWithBuffer(logBuffer)
        if splitResult.isErr:
          e.state.statusMessage = "Failed to open LSP log: " & splitResult.error
        else:
          e.setMode(EditorMode.LogViewer)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.LogViewer
          let logState = newLogViewerState(lckLsp)
          activeWin.modeState = ModeState(kind: mskLogViewer, logViewer: logState)
      of hrEnterHelpViewer:
        overlayHandled = true
        # Enter help viewer mode in a split window
        let baseModeBeforeOverlay = e.state.baseMode
        e.state.exitOverlay()
        e.state.previousMode = baseModeBeforeOverlay
        let helpState = newHelpViewerState()
        let helpBuffer = helpState.createHelpTextBuffer()
        let splitResult = e.hsplitWithBuffer(helpBuffer)
        if splitResult.isErr:
          e.state.statusMessage = "Failed to open help: " & splitResult.error
        else:
          e.setMode(EditorMode.Help)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.Help
          activeWin.cursor = BufferPosition(line: 0, column: 0)
          activeWin.viewport.topLine = 0
          activeWin.viewport.leftColumn = 0
          activeWin.modeState = ModeState(kind: mskHelp, help: helpState)
      of hrEnterBufferManager:
        overlayHandled = true
        # Enter buffer manager mode - save base mode, exit overlay
        let baseModeBeforeOverlay = e.state.baseMode
        e.state.exitOverlay()
        e.state.previousMode = baseModeBeforeOverlay
        e.setMode(EditorMode.BufferManager)
        let bmState = newBufferManagerState()
        bmState.updateEntries(e.getBufferInfos())
        bmState.previousWindowIndex = e.windowManager.activeWindowIndex
        let activeWin = e.activeWindow
        activeWin.mode = EditorMode.BufferManager
        activeWin.saveOriginalBuffer()
        activeWin.buffer = bmState.createBufferManagerTextBuffer()
        activeWin.cursor = BufferPosition(line: 0, column: 0)
        activeWin.viewport.topLine = 0
        activeWin.viewport.leftColumn = 0
        activeWin.modeState = ModeState(kind: mskBufferManager, bufferManager: bmState)
      of hrEnterBackupManager:
        overlayHandled = true
        # Enter backup manager mode in a vertical split
        # Capture source file path before split (split changes active buffer)
        let baseBackupDir = e.config.autoBackup.getBaseBackupDir()
        var sourceFilePath = ""
        if e.buffer.filePath.isSome:
          sourceFilePath = absolutePath(e.buffer.filePath.get)
        let bkState = initBackupManagerState(baseBackupDir, sourceFilePath)
        let bkBuffer = bkState.createBackupManagerTextBuffer()
        let splitResult = e.vsplitWithBuffer(bkBuffer)
        if splitResult.isErr:
          e.state.statusMessage = "Failed to open backup manager: " & splitResult.error
        else:
          let baseModeBeforeOverlay = e.state.baseMode
          e.state.exitOverlay()
          e.state.previousMode = baseModeBeforeOverlay
          e.setMode(EditorMode.BackupManager)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.BackupManager
          activeWin.modeState =
            ModeState(kind: mskBackupManager, backupManager: bkState)
      of hrRecentFile:
        overlayHandled = true
        # Enter recent file mode in a vertical split
        let loadResult = e.enterRecentFileMode()
        if loadResult.isErr:
          logError("handler", "Failed to enter Recent File mode: " & loadResult.error)
          e.state.statusMessage = "Error: " & loadResult.error
        else:
          let baseModeBeforeOverlay = e.state.baseMode
          e.state.exitOverlay()
          e.state.previousMode = baseModeBeforeOverlay
          e.setMode(EditorMode.RecentFile)
          e.state.statusMessage = ""
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.RecentFile
      of hrDebug:
        overlayHandled = true
        # Open debug info in a vertical split (like log viewer)
        var debugLines: seq[string] = @[]
        let debugConfig = e.config.debug
        # Generate debug info based on config settings
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
          e.activeWindow.cursor.column, e.state.commandText, e.state.statusMessage,
          debugConfig.editorView.enable,
        )
        generateSearchInfo(
          debugLines,
          e.state.search.text,
          e.state.search.lastText,
          $e.state.search.direction,
          e.state.search.history.len,
          e.state.search.ignorecase,
          e.state.search.smartcase,
          e.state.search.incsearch,
          e.state.search.hlsearch,
          debugConfig.search.enable,
        )
        generateDisplayInfo(
          debugLines, e.state.display.showStatusLine, e.state.display.multiStatusLine,
          e.state.display.showLineNumbers, e.state.display.showCursorLine,
          e.state.display.showSyntax, e.state.display.showIndentationLines,
          e.state.display.showSidebar, e.state.display.scrollbarWidth,
          e.state.display.showModifiedLines, e.state.display.lineWrap,
          e.state.display.tabStop, debugConfig.editorView.enable,
        )
        generateMacroInfo(
          debugLines, e.state.macroState.isRecording, e.state.macroState.register,
          e.state.macroState.registers.len, e.state.macroState.playbackDepth,
          debugConfig.macroState.enable,
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
          debugLines, e.state.jumpList.len, e.state.jumpListIndex,
          debugConfig.jumpList.enable,
        )
        generateLspInfo(
          debugLines, e.state.lspCache.codeLensCache.itemsByLine.len,
          e.state.lspCache.locations.isSome, e.state.lspCache.codeLensCache.isValid,
          debugConfig.lsp.enable,
        )
        # Initialize debug viewer state
        let debugState = newDebugViewerState()
        debugState.lines = debugLines
        let debugBuffer = debugState.createDebugTextBuffer()
        let splitResult = e.vsplitWithBuffer(debugBuffer)
        if splitResult.isErr:
          e.state.statusMessage = "Failed to open debug: " & splitResult.error
        else:
          e.state.statusMessage = "Debug info (auto-refresh)"
          # Store debug buffer reference for auto-refresh
          e.state.windowDisplay.debugBuffer = debugBuffer
          e.state.timing.lastDebugUpdate = getMonoTime()
          if e.state.timing.debugUpdateInterval == 0:
            e.state.timing.debugUpdateInterval = 500 # Default: 500ms
          e.activeWindow.modeState = ModeState(kind: mskDebug, debug: debugState)
          # Enter debug mode
          e.state.exitOverlay()
          e.state.previousMode = e.state.baseMode
          e.setMode(EditorMode.Debug)
      of hrJumpList:
        overlayHandled = true
        # Handle jump list command (:ju, :jump)
        # Display jump list temporarily like Vim using tempMessages
        if e.state.jumpList.len == 0:
          e.state.statusMessage = "Jump list is empty"
        else:
          e.state.ui.tempMessages = @[]
          e.state.ui.tempMessages.add(" jump  line  col  file")
          for i, pos in e.state.jumpList:
            let marker = if i == e.state.jumpListIndex: ">" else: " "
            let jumpNum = e.state.jumpList.len - i
            let lineNum = pos.line + 1 # 1-based for display
            let colNum = pos.column + 1 # 1-based for display
            # Get file name from BufferId
            let bufOpt = e.bufferById(pos.bufferId)
            let fileName =
              if bufOpt.isSome:
                let buf = bufOpt.get
                if buf.filePath.isSome:
                  buf.filePath.get.extractFilename
                else:
                  "[No Name]"
              else:
                "[Invalid]"
            e.state.ui.tempMessages.add(
              marker & ($jumpNum).align(4) & " " & ($lineNum).align(5) & " " &
                ($colNum).align(4) & "  " & fileName
            )
          e.state.windowDisplay.needsFullRedraw = true
        # Return to Normal mode (not to previous Command mode) - exit overlay first
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrChanges:
        overlayHandled = true
        # Handle change list command (:changes)
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
          # Current position row (show > only when at the end of changelist)
          let w = e.activeWindow
          let curMarker =
            if buf.changeListIndex == buf.changeList.len - 1: ">" else: " "
          e.state.ui.tempMessages.add(
            curMarker & "0".align(4) & " " & ($(w.cursor.line + 1)).align(5) & " " &
              ($(w.cursor.column + 1)).align(4) & "  "
          )
          e.state.windowDisplay.needsFullRedraw = true
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrConflictNext:
        overlayHandled = true
        let buf = e.activeBuffer()
        let fromLine = e.activeWindow.cursor.line
        let nxt = buf.findNextConflict(fromLine)
        if nxt.isSome:
          e.activeWindow.cursor.line = nxt.get.startLine
          e.activeWindow.cursor.column = 0
          e.updateViewportForCursor(e.cursor)
        else:
          e.state.statusMessage = "No next git conflict"
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrConflictPrev:
        overlayHandled = true
        let buf = e.activeBuffer()
        let fromLine = e.activeWindow.cursor.line
        let prv = buf.findPrevConflict(fromLine)
        if prv.isSome:
          e.activeWindow.cursor.line = prv.get.startLine
          e.activeWindow.cursor.column = 0
          e.updateViewportForCursor(e.cursor)
        else:
          e.state.statusMessage = "No previous git conflict"
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrEnterBookmarkManager:
        overlayHandled = true
        let baseModeBeforeOverlay = e.state.baseMode
        e.state.exitOverlay()
        e.state.previousMode = baseModeBeforeOverlay
        e.setMode(EditorMode.BookmarkManager)
        let bkmState = newBookmarkManagerState()
        bkmState.updateEntries(e.buffers)
        bkmState.previousWindowIndex = e.windowManager.activeWindowIndex
        let activeWin = e.activeWindow
        activeWin.mode = EditorMode.BookmarkManager
        activeWin.saveOriginalBuffer()
        activeWin.buffer = bkmState.createBookmarkManagerTextBuffer()
        activeWin.cursor = BufferPosition(line: 0, column: 0)
        activeWin.viewport.topLine = 0
        activeWin.viewport.leftColumn = 0
        activeWin.modeState =
          ModeState(kind: mskBookmarkManager, bookmarkManager: bkmState)
      of hrTheme:
        overlayHandled = true
        # Handle theme change command
        let themeName = r.hrThemeName
        if themeName == "default":
          # Use default theme
          setThemeColors(DefaultColors)
          e.state.statusMessage = "Theme changed to: default"
        else:
          # Try to load theme from config directory
          let themePath =
            getHomeDir() / ".config" / "moe" / "themes" / (themeName & ".toml")
          let expandedPath = expandTilde(themePath)
          if fileExists(expandedPath):
            let themeResult = loadThemeFromToml(expandedPath)
            if themeResult.isOk:
              setThemeColors(themeResult.get)
              e.state.statusMessage = "Theme changed to: " & themeName
            else:
              e.state.statusMessage = "Failed to load theme: " & themeResult.error
          else:
            e.state.statusMessage = "Theme not found: " & themeName
        e.state.windowDisplay.needsFullRedraw = true
        # Exit overlay first, then set Normal mode
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrConfig:
        overlayHandled = true
        # Enter configuration mode in a vertical split (like debug viewer)
        let configBuffer = newTextBuffer("")
        configBuffer.readOnly = true
        let splitResult = e.vsplitWithBuffer(configBuffer)
        if splitResult.isErr:
          e.state.statusMessage = "Failed to open config: " & splitResult.error
        else:
          let baseModeBeforeOverlay = e.state.baseMode
          e.state.exitOverlay()
          e.state.previousMode = baseModeBeforeOverlay
          e.setMode(EditorMode.Config)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.Config
          let cfgState = newConfigModeState(e.config)
          activeWin.modeState = ModeState(kind: mskConfig, config: cfgState)
      of hrHandled, hrUnhandled, hrError:
        overlayHandled = true
        # Handle mode transitions
        let modeTransition = r.getModeTransition()
        if modeTransition.isSome:
          # Entering a new mode (e.g., Filer) - exit overlay first, then set new mode
          e.state.exitOverlay()
          e.setMode(modeTransition.get)
        else:
          # Return to the base mode we were in before entering Command overlay
          e.state.exitOverlay()
          e.setMode(e.state.mode) # Sync window mode
      of hrPutConfigFile:
        overlayHandled = true
        # Write current configuration to file (:putConfigFile)
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)

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
            return true

        let saveResult = saveConfig(e.config)
        if saveResult.isOk:
          e.state.statusMessage = "Config written: " & configPath
          logInfo("config", "Config written: " & configPath)
        else:
          e.state.statusMessage = "Failed to write config: " & saveResult.error
          logError("config", "Failed to write config: " & saveResult.error)
      of hrLspFormat:
        overlayHandled = true
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
        discard e.requestLspFormat()
      of hrLspRestart:
        overlayHandled = true
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
        discard e.restartLspServer()
      of hrLspFold:
        overlayHandled = true
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
        asyncSpawn e.refreshLspFolds()
      of hrLspExecuteCommand:
        overlayHandled = true
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
        asyncSpawn e.requestLspExecuteCommand(r.hrLspCommand, r.hrLspCommandArgs)
      of hrLspCallHierarchyIncoming:
        overlayHandled = true
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
        discard e.requestLspCallHierarchyIncoming()
      of hrLspCallHierarchyOutgoing:
        overlayHandled = true
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
        discard e.requestLspCallHierarchyOutgoing()
      of hrOnlyWindow:
        # Close all windows except the active one
        e.windowManager.onlyWindow(e.screenSize.width, e.screenSize.height)
        e.syncActiveWindow()
        if e.windowManager.windows.len > 0:
          e.setActiveWindowScreenCursor(e.activeWindow)
      of hrJumpToBuffer, hrFilerOpenFile, hrFilerOpenFileVSplit, hrFilerOpenFileHSplit,
          hrFilerDeleteFile, hrFilerShowInfo, hrFilerQuit, hrLogViewerRefresh,
          hrHelpViewerQuit, hrReferencesQuit, hrReferencesJumpTo, hrEnterReferences,
          hrDocumentSymbolQuit, hrDocumentSymbolJumpTo, hrEnterDocumentSymbol,
          hrCallHierarchyQuit, hrCallHierarchyJumpTo, hrCallHierarchyRequestIncoming,
          hrCallHierarchyRequestOutgoing, hrEnterCallHierarchy,
          hrBufferManagerSelectBuffer, hrBufferManagerDeleteBuffer, hrBufferManagerQuit,
          hrBookmarkManagerJump, hrBookmarkManagerDelete, hrBookmarkManagerQuit,
          hrBackupManagerRestore, hrBackupManagerDelete, hrBackupManagerOpenDiff,
          hrBackupManagerRefresh, hrBackupManagerQuit, hrDiffViewerQuit,
          hrEnterDiffViewer, hrRecentFileOpenFile, hrRecentFileQuit, hrNextWindow,
          hrPrevWindow, hrIncreaseWindowHeight, hrDecreaseWindowHeight,
          hrIncreaseWindowWidth, hrDecreaseWindowWidth, hrEqualizeWindows, hrSwapWindow,
          hrLspGotoDefinition, hrLspGotoDeclaration, hrLspFindReferences,
          hrLspCodeLensExecute, hrLspTypeDefinition, hrLspImplementation, hrLspHover,
          hrLspRename, hrLspSelectionRange, hrLspDocumentLink, hrConfigQuit,
          hrConfigSaveConfig, hrDebugViewerQuit, hrLogViewerQuit, hrTerminalQuit,
          hrExecCommand, hrFileTreeOpenFile, hrFileTreeQuit, hrOpenUri:
        discard # Not returned from command mode handler

      if not overlayHandled:
        e.state.exitOverlay()
        e.setMode(e.state.mode)

      # Set status message if any
      let statusMsg = r.getStatusMessage()
      if statusMsg.len > 0:
        e.state.statusMessage = statusMsg
    else:
      # Empty command, just return to base mode
      e.state.exitOverlay()
      e.setMode(e.state.mode) # Sync window mode

    # Clear command text and cursor (already done by exitOverlay, but ensure consistency)
    e.state.commandText = ""
    e.state.commandCursor = 0

    # Insert-Normal mode (Ctrl-o): handle mode after the command completes
    if e.state.insertNormalMode:
      if e.state.mode == EditorMode.Normal:
        # Normal commands (e.g., :w, :set): return to Insert mode
        e.state.insertNormalMode = false
        e.setMode(EditorMode.Insert)
      elif e.state.mode != EditorMode.Insert:
        # Mode changed to something other than Normal/Insert (e.g., Help, Filer)
        # Clear insert-normal and commit the Insert mode transaction
        e.state.insertNormalMode = false
        let activeBuffer = e.activeBuffer()
        if activeBuffer.inTransaction:
          clearAutoIndentIfUnedited(activeBuffer, e.state)
          discard activeBuffer.commitTransaction()
        e.state.editState.insertModeStartPos = none(BufferPosition)
        e.state.editState.substituteContext = none(types.SubstituteContext)

    return true

  # Handle Left arrow - move cursor left
  if keyCombo.isSpecial and keyCombo.special == skLeft:
    if e.state.commandCursor > 0:
      e.state.commandCursor -= 1
      e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle Right arrow - move cursor right
  if keyCombo.isSpecial and keyCombo.special == skRight:
    # commandText includes the ":" prefix, so max cursor position is runeLen - 1
    let maxPos = e.state.commandText.runeLen - 1
    if e.state.commandCursor < maxPos:
      e.state.commandCursor += 1
      e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle Backspace - delete character before cursor
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    e.state.commandState.historyIndex = -1
    if e.state.commandCursor > 0 and e.state.commandText.runeLen > 1:
      # Delete the character before cursor (commandCursor is 0-based after ":")
      let pos = e.state.commandCursor # Character position in commandText
      e.state.commandText = e.state.commandText.deleteCharAt(pos)
      e.state.commandCursor -= 1
      # Update completion
      let mgr = e.state.commandCompletionManager
      if ' ' in e.state.commandText:
        # Argument mode
        mgr.triggerArgumentCompletion(e.state.commandText, getCurrentDir())
      elif mgr.isActive():
        let prefix = extractCommandPrefix(e.state.commandText)
        mgr.updateFilter(prefix)
      e.updateSubstitutePreviewIfNeeded()
    return true

  # Handle Delete - delete character at cursor
  if keyCombo.isSpecial and keyCombo.special == skDelete:
    let charPos = e.state.commandCursor + 1
      # Character position in commandText (after ":")
    if charPos < e.state.commandText.runeLen:
      e.state.commandText = e.state.commandText.deleteCharAt(charPos)
      # Update completion
      let mgr = e.state.commandCompletionManager
      if ' ' in e.state.commandText:
        # Argument mode
        mgr.triggerArgumentCompletion(e.state.commandText, getCurrentDir())
      elif mgr.isActive():
        let prefix = extractCommandPrefix(e.state.commandText)
        mgr.updateFilter(prefix)
      e.updateSubstitutePreviewIfNeeded()
    return true

  # Handle Home - move cursor to beginning
  if keyCombo.isSpecial and keyCombo.special == skHome:
    e.state.commandCursor = 0
    e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle End - move cursor to end
  if keyCombo.isSpecial and keyCombo.special == skEnd:
    e.state.commandCursor = e.state.commandText.runeLen - 1
    e.state.commandCompletionManager.cancelCompletion()
    return true

  # Up arrow: Navigate to previous (older) command in history
  if keyCombo.isSpecial and keyCombo.special == skUp:
    if e.state.commandState.history.len > 0:
      # If not yet navigating history, start from the most recent entry
      if e.state.commandState.historyIndex == -1:
        e.state.commandState.historyIndex = 0
      # Otherwise, move to the next older entry
      elif e.state.commandState.historyIndex < e.state.commandState.history.high:
        e.state.commandState.historyIndex += 1

      # Update command text with history entry
      e.state.commandText =
        ":" & e.state.commandState.history[e.state.commandState.historyIndex]
      e.state.commandCursor = e.state.commandText.runeLen - 1
      e.state.commandCompletionManager.cancelCompletion()
      e.updateSubstitutePreviewIfNeeded()
    return true

  # Down arrow: Navigate to next (newer) command in history
  if keyCombo.isSpecial and keyCombo.special == skDown:
    if e.state.commandState.history.len > 0 and e.state.commandState.historyIndex >= 0:
      # Move to newer entry
      if e.state.commandState.historyIndex > 0:
        e.state.commandState.historyIndex -= 1
        e.state.commandText =
          ":" & e.state.commandState.history[e.state.commandState.historyIndex]
        e.state.commandCursor = e.state.commandText.runeLen - 1
      else:
        # Reached the newest entry, clear to empty command
        e.state.commandState.historyIndex = -1
        e.state.commandText = ":"
        e.state.commandCursor = 0
      e.state.commandCompletionManager.cancelCompletion()
      e.updateSubstitutePreviewIfNeeded()
    return true

  # Handle character input - insert at cursor position
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    e.state.commandState.historyIndex = -1
    # Guard against empty commandText (should have at least ":")
    if e.state.commandText.len == 0:
      e.state.commandText = ":"
      e.state.commandCursor = 0
    let bytePos = charToBytePos(e.state.commandText, e.state.commandCursor + 1)
    e.state.commandText =
      e.state.commandText[0 ..< bytePos] & keyCombo.char &
      e.state.commandText[bytePos ..^ 1]
    e.state.commandCursor += 1
    # Handle completion
    let mgr = e.state.commandCompletionManager
    let hasSpace = ' ' in e.state.commandText
    if keyCombo.char == " ":
      # Space is a delimiter - trigger argument completion if applicable
      mgr.cancelCompletion()
      mgr.triggerArgumentCompletion(e.state.commandText, getCurrentDir())
    elif hasSpace:
      # In argument mode - always update argument completion
      mgr.triggerArgumentCompletion(e.state.commandText, getCurrentDir())
    elif mgr.isActive():
      let prefix = extractCommandPrefix(e.state.commandText)
      mgr.updateFilter(prefix)
    else:
      # Auto-trigger command completion on first character
      mgr.triggerCompletion(e.commandLineParser, e.state.commandText)
    e.updateSubstitutePreviewIfNeeded()
    return true

  # Ignore other special keys
  return true
