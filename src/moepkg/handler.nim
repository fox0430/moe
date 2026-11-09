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

import std/[monotimes, options, os, strutils]

when defined(posix):
  from std/posix import nil

import pkg/[results, chronos]
from pkg/celina/core/mouse_logic import MouseButton

import
  celina_backend as celina,
  editor,
  editor_window_layout,
  key_bindings,
  modes,
  buffer,
  logger,
  types,
  motion,
  page_scroll,
  quick_run_utils,
  build,
  render_utils,
  tab_line,
  clipboard_backend,
  signal_watcher,
  terminal_command,
  git_cache,
  cursor_util,
  background_process,
  key_router,
  macro_recording,
  visible_rows,
  viewer_mode,
  frontend_input,
  hover_popup,
  encoding,
  unicode_utils,
  editor_mode,
  editor_lsp_rename,
  editor_file_jobs,
  editor_command_output,
  job_lanes,
  highlight,
  visual_selection,
  insert_record

when not defined(moe.embedded):
  import terminal_mode
import
  command_handlers/[
    handler_manager, command_mode_handler, search_mode_handler, result_processor,
    command_passthrough,
  ]
import prompt_line
from config_mode import clearKeySequence
export command_mode_handler, search_mode_handler, cursor_util, frontend_input

proc addRunningProcess*(e: Editor, p: BackgroundProcess, label = "", path = "") =
  e.runningBackgroundProcesses.add RunningCommand(
    process: p, label: label, path: path, startedAt: getMonoTime()
  )

proc removeRunningProcess*(e: Editor, p: BackgroundProcess) =
  for i, running in e.runningBackgroundProcesses:
    if running.process == p:
      e.runningBackgroundProcesses.delete(i)
      return

proc cleanupBackgroundProcesses*(e: Editor) =
  ## Kill every background command (call on editor exit), along with what one
  ## that has exited left running in its group.
  e.jobLanes.close()
  for running in e.runningBackgroundProcesses:
    running.process.kill()
  e.runningBackgroundProcesses = @[]

proc addRunningQuickRun*(e: Editor, p: QuickRunProcess) =
  e.runningQuickRunProcesses.add(p)

proc removeRunningQuickRun*(e: Editor, p: QuickRunProcess) =
  let idx = e.runningQuickRunProcesses.find(p)
  if idx >= 0:
    e.runningQuickRunProcesses.delete(idx)

proc cleanupQuickRunProcesses*(e: Editor) =
  ## Kill any in-flight QuickRun processes and remove their temporary files
  ## (temp source + build artifacts). Call on editor exit/crash so QuickRun
  ## never orphans a process or leaves temp files behind. Mirrors the git diff
  ## shutdown cleanup (`clearGitCache`).
  for p in e.runningQuickRunProcesses:
    abandonQuickRunProcess(p)
  e.runningQuickRunProcesses = @[]

proc releaseExternalResources*(e: Editor) =
  ## Tear down every OS resource the editor owns (background/QuickRun processes,
  ## terminal PTYs, git diff subprocesses, LSP servers), then flush persist data.
  ## Shared by the normal quit path and the crash path. Idempotent.
  e.cleanupBackgroundProcesses()
  e.cleanupQuickRunProcesses()
  when not defined(moe.embedded):
    e.cleanupAllTerminals()

  # Swallow so a git cache failure cannot block the rest of the sequence.
  try:
    e.state.git.clearGitCache()
  except CatchableError as ex:
    logError("moe", "clearGitCache failed: " & ex.msg)

  e.shutdown()
  e.savePersistData()

proc handleRenameModeKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in Rename mode - for LSP rename symbol input. It ends
  ## and edits as the command line does (prompt_line), as Vim's input():
  ## Enter, and an Esc a mapping or a register puts in, run the rename; a
  ## typed Esc and Ctrl-C cancel it. An erase on an empty line does not, as
  ## the prompt has words of its own.
  ##
  ## Returns: true (event handled)
  case e.state.input.line.takeKey(keyCombo, e.state.keyTyped, e.state.interrupted)
  of pkLeave:
    e.state.exitOverlay()
    e.setMode(e.state.mode) # Sync window mode
    e.state.statusMessage = "Rename cancelled"
  of pkEnter, pkRun:
    let newName = e.state.input.line.text
    e.state.exitOverlay()
    e.setMode(e.state.mode) # Sync window mode
    if newName.len == 0:
      e.state.statusMessage = "Rename cancelled: empty name"
    elif newName == e.state.renameState.originalWord:
      e.state.statusMessage = "Rename cancelled: same name"
    else:
      # Execute the LSP rename asynchronously
      asyncSpawn e.requestLspRename(newName)
  of pkOther, pkArgument:
    # No history of its own yet: Up and Down beep, as on an empty one.
    if e.state.editPrompt(e.activeBuffer, keyCombo, @[]) == leBeep:
      e.state.beep()
  true

proc handleRecentFileModeKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in Recent File mode.
  # Get viewport height for the recent file list
  # Reserve: status line + 1 line for title
  let viewportHeight =
    max(0, e.viewport.height - e.steadyReservedLines(e.activeWindow) - 1)

  let activeWin = e.activeWindow
  if activeWin.modeState.kind != mskRecentFile:
    return true

  let r = e.handlerManager.handleRecentFileMode(
    activeWin.modeState.recentFile, viewportHeight, keyCombo
  )

  case r.kind
  of hrRecentFileQuit:
    return e.processResult(r, e.activeBuffer())
  of hrRecentFileOpenFile:
    let filePath = r.recentFilePath
    if not fileExists(filePath):
      logError("handler", "File not found: " & filePath)
      e.state.statusMessage = "File not found: " & filePath
      return true
    e.leaveViewerMode(EditorMode.RecentFile)
    # Open the file in the now-active window
    let editResult = e.editFile(filePath)
    if editResult.isErr:
      logError("handler", "Failed to open file: " & editResult.error)
      e.state.statusMessage = "Error: " & editResult.error
    else:
      e.state.statusMessage = "Opened: " & filePath
    return true
  of hrHandled, hrUnhandled:
    discard # Fall through to overlay/mode transition handling
  of hrError:
    e.state.statusMessage = r.errorMessage
  of hrQuit, hrCloseWindow, hrGotoLine, hrVSplit, hrHSplit, hrNew, hrVnew, hrEnew,
      hrEdit, hrSetBoolOption, hrSetIntOption, hrSetFloatOption, hrClearSearchHighlight,
      hrSave, hrSaveAll, hrSaveAndQuit, hrSaveAllAndQuit, hrBufferNext, hrBufferPrev,
      hrBufferFirst, hrBufferLast, hrBufferNextTab, hrBufferPrevTab, hrBuffer,
      hrJumpToBuffer, hrBufferDelete, hrStripWhitespace, hrFilerOpenFile,
      hrFilerOpenFileVSplit, hrFilerOpenFileHSplit, hrFilerDeleteFile, hrFilerShowInfo,
      hrFilerQuit, hrEnterFiler, hrLogViewerQuit, hrLogViewerRefresh, hrEnterLogViewer,
      hrHelpViewerQuit, hrEnterHelpViewer, hrQuickRun, hrBufferManagerSelectBuffer,
      hrBufferManagerDeleteBuffer, hrBufferManagerQuit, hrEnterBufferManager,
      hrBookmarkManagerJump, hrBookmarkManagerDelete, hrBookmarkManagerQuit,
      hrEnterBookmarkManager, hrBackupManagerRestore, hrBackupManagerDelete,
      hrBackupManagerOpenDiff, hrBackupManagerRefresh, hrBackupManagerQuit,
      hrEnterBackupManager, hrRecoveryManagerRestore, hrRecoveryManagerToggleReviewed,
      hrRecoveryManagerDiscard, hrRecoveryManagerRefresh, hrRecoveryManagerQuit,
      hrEnterRecoveryManager, hrDiffViewerQuit, hrDiffViewerToggleView,
      hrDiffViewerToggleWord, hrRecentFile, hrNextWindow, hrPrevWindow,
      hrMoveWindowLeft, hrMoveWindowDown, hrMoveWindowUp, hrMoveWindowRight,
      hrMaximizeWindowHeight, hrIncreaseWindowHeight, hrDecreaseWindowHeight,
      hrIncreaseWindowWidth, hrDecreaseWindowWidth, hrEqualizeWindows, hrSwapWindow,
      hrLspGotoDefinition, hrLspGotoDeclaration, hrLspFindReferences,
      hrLspDocumentSymbol, hrLspCodeLensExecute, hrLspCallHierarchyIncoming,
      hrLspCallHierarchyOutgoing, hrLspTypeDefinition, hrLspImplementation, hrLspHover,
      hrLspRename, hrLspSelectionRange, hrLspDocumentLink, hrShellCommand, hrFilter,
      hrBackground, hrJumpList, hrChanges, hrVersion, hrChangeDir, hrBuild, hrDebug,
      hrDebugViewerQuit, hrConfig, hrConfigQuit, hrConfigSaveConfig, hrPutConfigFile,
      hrTheme, hrLspLog, hrLspFormat, hrLspRestart, hrLspFold, hrLspExecuteCommand,
      hrSubstitute, hrDeleteLines, hrMan, hrReferencesQuit, hrReferencesJumpTo,
      hrDocumentSymbolQuit, hrDocumentSymbolJumpTo, hrCallHierarchyQuit,
      hrCallHierarchyJumpTo, hrCallHierarchyRequestIncoming,
      hrCallHierarchyRequestOutgoing, hrEnterTerminal, hrTerminalQuit, hrExecCommand,
      hrOnlyWindow, hrEnterFileTree, hrFileTreeOpenFile, hrFileTreeQuit, hrOpenUri,
      hrCquit, hrConflictNext, hrConflictPrev, hrMapAdd, hrMapRemove, hrMapClear,
      hrMapList, hrPlaybackMacro, hrRepeatInsert, hrUndo, hrRedo, hrJobs:
    discard # Not expected from RecentFile mode handler

  # Route overlay/mode transitions through processResult so a viewer target
  # gets its real entry replayed, not a bare setMode. Only hrHandled carries
  # either transition.
  if r.kind == hrHandled:
    return e.processResult(r, e.activeBuffer())

  return true

proc handleDebugModeKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in Debug mode.
  # Get viewport height for the debug viewer
  # Reserve: status line + 1 line for title
  let viewportHeight =
    max(0, e.viewport.height - e.steadyReservedLines(e.activeWindow) - 1)

  let activeWin = e.activeWindow
  if activeWin.modeState.kind != mskDebug:
    e.state.statusMessage = "Debug viewer state not initialized"
    return true

  let r = handleDebugModeKey(activeWin.modeState.debug, viewportHeight, keyCombo)

  case r.kind
  of dvrQuit:
    return e.processResult(HandlerResult(kind: hrDebugViewerQuit), e.activeBuffer())
  of dvrEnterCommand:
    e.state.enterCommandOverlay()
    return true
  of dvrHandled, dvrUnhandled, dvrError:
    return true

when not defined(moe.embedded):
  proc pasteIntoTerminal(e: Editor, text: string): Result[void, string] =
    ## Send a paste to the child process. The caller reports the error, since
    ## the Terminal and its overlays do not share a place to show a message.
    let activeWin = e.activeWindow
    if activeWin.modeState.kind != mskTerminal or
        activeWin.modeState.terminalSubMode != tsmInput:
      return err("Paste not supported in this mode")
    activeWin.modeState.terminal.pasteInput(text.sanitizeInvalidUtf8())

type PasteSink = enum
  ## Where a paste goes. One precedence list for both paste paths.
  psOverlay ## The prompt's line, which owns the keys while it is up
  psTerminal ## The child process of a Terminal window
  psBuffer ## The window's text buffer

proc pasteSinkOf(e: Editor, window: EditorWindow): PasteSink =
  ## Where a paste into `window` would go. `window` need not hold the keys yet:
  ## a click resolves its target before it moves the focus there.
  if e.state.isCommandOverlay or e.state.isSearchOverlay or e.state.isRenameOverlay:
    return psOverlay
  when not defined(moe.embedded):
    if window.modeState.kind == mskTerminal:
      return psTerminal
  psBuffer

proc resolvePasteSink(e: Editor): PasteSink =
  ## The sink for the window that has the keys.
  e.pasteSinkOf(e.activeWindow)

proc insertPastedTextInPrompt(e: Editor, text: string) =
  ## A paste into the open prompt's line, which the prompt then follows.
  if e.state.isCommandOverlay:
    e.insertPastedTextInCommand(text)
  elif e.state.isSearchOverlay:
    e.insertPastedTextInSearch(text)
  else:
    discard e.state.input.line.insertPasted(text)

proc handlePasteText(e: Editor, text: string): bool =
  ## Insert pasted text without triggering auto-indentation.
  e.state.armInsertResume()
  case e.resolvePasteSink()
  of psOverlay:
    # Single-line character fields, so normalize unconditionally.
    let overlayText = text.sanitizeInvalidUtf8().normalizeNewlines()
    if overlayText.len == 0:
      return true
    e.insertPastedTextInPrompt(overlayText)
    return true
  of psTerminal:
    when not defined(moe.embedded):
      # A paste belongs to the child process, not the buffer.
      let pasteResult = e.pasteIntoTerminal(text)
      if pasteResult.isErr:
        e.state.statusMessage = pasteResult.error
    return true
  of psBuffer:
    discard

  let activeBuffer = e.activeBuffer()

  # Sanitize paste for `b`; skipped for raw buffers.
  let pastedText = activeBuffer.preparePastedText(text)
  if pastedText.len == 0:
    return true

  # Handle paste differently based on mode
  case e.state.mode
  of EditorMode.Insert:
    # In Insert mode: Insert text directly without auto-indentation.
    # If a transaction is already active (e.g. Insert mode edit), use it
    # instead of starting a new one so the paste is part of the same undo group.
    let ownTransaction = not activeBuffer.inTransaction
    if ownTransaction:
      let transactionResult = activeBuffer.beginTransaction("Paste")
      if transactionResult.isErr:
        e.state.statusMessage = "Paste failed: " & transactionResult.error
        return true

    e.state.noteOutsideChange()
    let pos = e.cursor
    let insertResult = activeBuffer.insertTextEnd(pos, pastedText)
    if insertResult.isErr:
      var msg = "Paste failed: " & insertResult.error
      if ownTransaction:
        let rollbackResult = activeBuffer.rollbackTransaction()
        if rollbackResult.isErr:
          logError "handler",
            "Failed to rollback paste transaction: " & rollbackResult.error
          msg &= " (rollback failed: " & rollbackResult.error & ")"
      e.state.statusMessage = msg
      return true

    e.activeWindow.cursor = insertResult.get.cursor
    # Record it as typed, so `.` types the pasted text.
    e.state.noteTypedText(pastedText, pos)

    if ownTransaction:
      let commitResult = activeBuffer.commitTransaction()
      if commitResult.isErr:
        logError "handler", "Failed to commit paste transaction: " & commitResult.error
        e.state.statusMessage = "Paste failed: " & commitResult.error
  else:
    # For other modes, just show a message
    e.state.statusMessage = "Paste not supported in this mode"

  return true

proc screenToBufferPosition(
    vp: ViewPort,
    buffer: TextBuffer,
    mouseX, mouseY: int,
    gutterWidth, reservedLines: int,
    lineWrap: bool,
    tabStop: int = 4,
    wrapWidth: int = 1,
    wrapCache: WrapCountCache = nil,
): Option[BufferPosition] =
  ## Convert screen coordinates to buffer position.
  ## Returns none if click is outside the text area.
  ## Handles line wrap mode with display-width-based segment calculation.
  ##
  ## gutterWidth: sidebar + line number width the text starts after
  ## (`Editor.gutterWidth`); wrapWidth: the width the renderer wrapped at
  ## (`Editor.wrapWidth`, only consulted when `lineWrap`). Both come from the
  ## derivation the renderer used, so a click maps to the character drawn there.
  let
    screenY = mouseY - vp.y
    screenX = mouseX - vp.x - gutterWidth

  # Check if click is within the text area
  if screenY < 0 or screenY >= vp.height - reservedLines:
    return none(BufferPosition)
  if screenX < 0:
    return none(BufferPosition)

  let
    rl = initRowLayout(buffer, wrapCache, lineWrap, wrapWidth, tabStop)
    row = rl.rowAt(vp.topLine, vp.topWrapOffset, screenY)
    # Below the last rendered row (the blank tail): clamp onto the last line.
    line =
      if row.isSome:
        row.get.line
      else:
        max(0, buffer.len - 1)
    wrapSeg = if row.isSome: row.get.wrapSeg else: 0

  some(
    BufferPosition(
      line: line, column: rl.cellToColumn(line, wrapSeg, screenX, vp.leftCell)
    )
  )

proc scrollTargetIndex(e: Editor, input: ScrollInput): int =
  ## Resolve the window under a cell-coordinate scroll, falling back to active.
  if e.windowManager.windows.len == 0:
    return -1

  result = clamp(e.windowManager.activeWindowIndex, 0, e.windowManager.windows.high)
  if e.windowManager.windows.len > 1:
    for i, window in e.windowManager.windows:
      let vp = window.viewport
      if input.column >= vp.x and input.column < vp.x + vp.width and input.row >= vp.y and
          input.row < vp.y + vp.height:
        return i

proc scrollRegion(e: Editor, window: EditorWindow): GridRegion =
  ## Grid rows belonging to scrollable window content. Tab and bottom/status
  ## rows are deliberately excluded so a GUI bridge can leave them stationary.
  let
    vp = window.viewport
    tabLineOffset = if e.showTabLine: TabLineHeight else: 0
    reservedLines =
      e.calculateReservedLines(e.windowManager.windows.reachesBottom(window))
  initGridRegion(
    vp.y + tabLineOffset, vp.x, vp.height - tabLineOffset - reservedLines, vp.width
  )

proc scrollTextViewport(e: Editor, window: EditorWindow, deltaPhysicalRows: int): int =
  ## Move a text viewport by rendered rows, including wrapped segments and folds.
  let layout = e.rowLayoutFor(
    window.buffer,
    window.viewport.width,
    e.viewportOffsetFor(window),
    window.wrapCountCache,
  )
  var
    topLine = window.viewport.topLine
    topWrapOffset = window.viewport.topWrapOffset
  var remaining = deltaPhysicalRows
  while remaining > 0:
    let next = layout.rowAt(topLine, topWrapOffset, 1)
    if next.isNone:
      break
    topLine = next.get.line
    topWrapOffset = next.get.wrapSeg
    inc result
    dec remaining
  while remaining < 0:
    let previous = layout.walkBackRows(topLine, topWrapOffset, 1)
    if previous == (line: topLine, offset: topWrapOffset):
      break
    topLine = previous.line
    topWrapOffset = previous.offset
    dec result
    inc remaining

  if result != 0:
    window.viewport.restoreViewportTop(topLine, topWrapOffset)
    window.viewport.detachedFromCursor = true

proc letHeldKeysGoFirst(e: Editor) =
  ## Let go of the keys held for a mapping before an input that is not a key
  ## acts, so it does not run ahead of them: Vim reads it after them from its
  ## typeahead. A quit they run is noted, and the frontend's tick ends the
  ## session.
  if e.keyRouter.isHoldingKeys and e.handlerManager.letHeldKeysGo(e) == roQuit:
    e.beginQuit()

proc handleScrollInputCore(e: Editor, input: ScrollInput): ScrollOutcome =
  ## Apply a frontend-neutral physical-line scroll and describe the affected
  ## rendered region for GUI repainting.
  result.requestedRows = input.deltaPhysicalRows
  if not e.config.standard.mouse:
    return
  if input.deltaPhysicalRows == 0:
    return
  if e.windowManager.windows.len == 0:
    return
  e.letHeldKeysGoFirst()
  e.state.armInsertResume()

  # Handle Filer mode scroll.
  if e.state.mode == EditorMode.Filer and e.activeWindow.modeState.kind == mskFiler:
    let window = e.activeWindow
    let filerState = e.activeWindow.modeState.filer
    let previousIndex = filerState.selectedIndex
    let previousTopLine = window.viewport.topLine
    if filerState.entries.len > 0:
      filerState.selectedIndex = clamp(
        filerState.selectedIndex + input.deltaPhysicalRows, 0, filerState.entries.high
      )
    result.handled = true
    result.region = e.scrollRegion(window)
    result.appliedRows = filerState.selectedIndex - previousIndex
    result.viewportPhysicalRowsMoved = window.viewport.topLine - previousTopLine
    return

  # Handle text editing modes.
  if e.state.mode in {
    EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualLine,
    EditorMode.VisualBlock, EditorMode.Replace,
  }:
    let targetIdx = e.scrollTargetIndex(input)
    let window = e.windowManager.windows[targetIdx]
    result.handled = true
    result.region = e.scrollRegion(window)
    result.appliedRows = e.scrollTextViewport(window, input.deltaPhysicalRows)
    result.viewportPhysicalRowsMoved = result.appliedRows
    return

type PointerTextHit = object
  windowIndex: int
  position: BufferPosition

proc pointerTabPress(e: Editor, input: PointerInput): bool =
  ## Switch a tab hit by a primary press. Drags and releases never switch tabs.
  if not e.showTabLine:
    return false

  if e.windowManager.windows.len == 1:
    if input.row != 0:
      return false
    let window = e.activeWindow
    let tabs = e.drawnTabs(window)
    let tabIdx =
      hitTestTabLine(tabs, window.mode, 0, window.viewport.width, input.column)
    if tabIdx >= 0:
      e.switchToDrawnTab(tabs[tabIdx])
      return true
    return false

  for i, window in e.windowManager.windows:
    let vp = window.viewport
    if input.row == vp.y and input.column >= vp.x and input.column < vp.x + vp.width:
      let tabs = e.drawnTabs(window)
      let tabIdx = hitTestTabLine(tabs, window.mode, vp.x, vp.width, input.column)
      if tabIdx >= 0:
        e.focusWindow(i)
        e.switchToDrawnTab(tabs[tabIdx])
        return true
  return false

proc pointerPositionInWindow(
    e: Editor, input: PointerInput, windowIndex: int
): Option[BufferPosition] =
  if windowIndex < 0 or windowIndex >= e.windowManager.windows.len:
    return none(BufferPosition)

  let
    window = e.windowManager.windows[windowIndex]
    vp = window.viewport
  if input.column < vp.x or input.column >= vp.x + vp.width:
    return none(BufferPosition)

  # The tab line is part of the window's rows, and `screenToBufferPosition`
  # bounds the row against `vp.height - reservedLines`, so the offset comes off
  # the reserve as well as off the row — otherwise the status row is
  # accepted and clamped onto the last buffer line.
  let
    tabLineOffset = if e.showTabLine: TabLineHeight else: 0
    adjustedRow = input.row - tabLineOffset

  if e.windowManager.windows.len > 1 and
      (input.row < vp.y or input.row >= vp.y + vp.height):
    return none(BufferPosition)

  screenToBufferPosition(
    vp,
    window.buffer,
    input.column,
    adjustedRow,
    e.gutterWidth(window),
    e.steadyReservedLines(window) + tabLineOffset,
    e.lineWrap,
    e.tabStop,
    e.wrapWidth(window),
    window.wrapCountCache,
  )

proc pointerTextHit(e: Editor, input: PointerInput): Option[PointerTextHit] =
  for i in 0 ..< e.windowManager.windows.len:
    let position = e.pointerPositionInWindow(input, i)
    if position.isSome:
      return some(PointerTextHit(windowIndex: i, position: position.get))
  none(PointerTextHit)

proc windowIndexAtCell(e: Editor, row, col: int): int =
  ## Index of the window whose text area contains this screen cell, or -1 for
  ## the tab line, the command line, or a gap between windows. Geometry only:
  ## a Terminal window draws its grid, not its buffer, so
  ## `screenToBufferPosition` would miss it.
  let
    tabLineOffset = if e.showTabLine: TabLineHeight else: 0
    maxBottomY = findMaxBottomY(e.windowManager.windows)
  for i, window in e.windowManager.windows:
    let vp = window.viewport
    if col < vp.x or col >= vp.x + vp.width:
      continue
    # Same text area as pointerPositionInWindow: the status line is not the
    # window's text.
    let reservedLines = e.steadyReservedLines(vp.y + vp.height == maxBottomY)
    if row < vp.y + tabLineOffset or row >= vp.y + vp.height - reservedLines:
      continue
    return i
  -1

proc middleClickPaste(e: Editor, row, col: int) =
  ## Paste the PRIMARY selection for a middle-click at this screen cell.
  if not e.config.clipboard.enable:
    return
  e.letHeldKeysGoFirst()
  e.state.armInsertResume()

  # An overlay owns the keys wherever the click landed, so it keeps the focus.
  # Otherwise the click picks the target window, not the focused one.
  let overlayHasKeys = e.resolvePasteSink() == psOverlay
  var windowIndex = -1
  if not overlayHasKeys:
    windowIndex = e.windowIndexAtCell(row, col)
    if windowIndex < 0:
      return

  # The sink is resolved before the focus moves: taking the focus finalizes the
  # old window's Insert session, so nothing below may bail out after that.
  let
    targetWindow =
      if overlayHasKeys:
        e.activeWindow
      else:
        e.windowManager.windows[windowIndex]
    sink = e.pasteSinkOf(targetWindow)

  if sink == psBuffer:
    # Before the read, so a rejected paste costs no clipboard round trip.
    if targetWindow.buffer.readOnly:
      e.notify("Buffer is read-only", nlError)
      return
    if targetWindow.mode != EditorMode.Normal and targetWindow.mode != EditorMode.Insert:
      return

  # Before any mode change, so a failure leaves no stray Insert state.
  let readResult = readFromPrimarySelectionSync(e.config.clipboard.tool)
  if readResult.isErr:
    if sink == psOverlay:
      # The overlay draws over the status row, so the message must go to the popup.
      e.notifyPopup("Paste failed: " & readResult.error, nlError)
    else:
      e.notify("Paste failed: " & readResult.error, nlError)
    return
  # A click that pastes nothing (no tool, empty PRIMARY) stays a no-op rather
  # than moving the focus.
  if readResult.get().len == 0:
    return

  if not overlayHasKeys:
    e.focusWindow(windowIndex)

  case sink
  of psOverlay:
    # Normalize for a single-line field.
    let pastedText = readResult.get().normalizeNewlines()
    if pastedText.len == 0:
      return
    e.insertPastedTextInPrompt(pastedText)
    return
  of psTerminal:
    when not defined(moe.embedded):
      let pasteResult = e.pasteIntoTerminal(readResult.get())
      if pasteResult.isErr:
        e.notify(pasteResult.error, nlWarning)
    return
  of psBuffer:
    discard

  let activeBuffer = e.activeBuffer()

  # Sanitize paste; skipped for raw buffers.
  let pastedText = activeBuffer.preparePastedText(readResult.get())
  if pastedText.len == 0:
    return

  let enteringInsertFromNormal = e.state.mode == EditorMode.Normal

  if enteringInsertFromNormal:
    let insertTransaction = activeBuffer.beginTransaction(
      "Insert mode edit", cursorPos = some(e.activeWindow.cursor)
    )
    if insertTransaction.isErr:
      e.notify("Paste failed: " & insertTransaction.error, nlError)
      return
    e.setMode(EditorMode.Insert)
    e.state.statusMessage = "-- INSERT --"

  # Reuse existing Insert transaction if any.
  let ownTransaction = not activeBuffer.inTransaction
  if ownTransaction:
    let transactionResult = activeBuffer.beginTransaction("Middle-click paste")
    if transactionResult.isErr:
      e.notify("Paste failed: " & transactionResult.error, nlError)
      return

  e.state.noteOutsideChange()
  let pos = e.cursor
  let insertResult = activeBuffer.insertTextEnd(pos, pastedText)
  if insertResult.isErr:
    var msg = "Paste failed: " & insertResult.error
    # Roll back the transaction we opened; a joined session transaction is
    # left untouched for the mode's own commit path.
    if ownTransaction or enteringInsertFromNormal:
      let rollbackResult = activeBuffer.rollbackTransaction()
      if rollbackResult.isErr:
        logError "handler",
          "Failed to rollback paste transaction: " & rollbackResult.error
        msg &= " (rollback failed: " & rollbackResult.error & ")"
      if enteringInsertFromNormal:
        # The Insert session never started: return to Normal mode and drop the
        # "-- INSERT --" indicator this paste put on the status row.
        e.setMode(EditorMode.Normal)
        e.state.statusMessage = ""
    e.notify(msg, nlError)
    return

  e.activeWindow.cursor = insertResult.get.cursor
  e.state.noteTypedText(pastedText, pos)
  # The click chose this window, so re-attach its viewport: a wheel-scrolled
  # split would otherwise keep the cursor off-screen after the insert.
  e.activeWindow.viewport.detachedFromCursor = false

  if ownTransaction:
    let commitResult = activeBuffer.commitTransaction()
    if commitResult.isErr:
      logError "handler", "Failed to commit paste transaction: " & commitResult.error
      e.notify("Paste failed: " & commitResult.error, nlError)

func pointerGranularity(
    input: PointerInput, selection: VisualSelection
): PointerSelectionGranularity =
  if input.clickCount >= 3:
    psgLine
  elif input.clickCount == 2:
    psgWord
  elif kmShift in input.modifiers and selection.active:
    case selection.kind
    of vskChar: psgCharacter
    of vskBlock: psgBlock
    of vskLine: psgLine
  else:
    psgCharacter

proc pointerRange(
    buffer: TextBuffer,
    position: BufferPosition,
    granularity: PointerSelectionGranularity,
): tuple[first, last: BufferPosition] =
  case granularity
  of psgWord:
    if position.line notin 0 ..< buffer.len:
      return (position, position)
    # `iw` from the character clicked, the last one past the line's end. On an
    # empty last line it reaches back over the line break before.
    let
      last = max(0, buffer.lineRunesNoNl(position.line).len - 1)
      word = buffer.currentWord(
        BufferPosition(line: position.line, column: min(position.column, last)),
        1,
        toWord,
        tomInner,
        EditorMode.Normal,
      )
    if word.found and word.start <= word.cursor:
      (word.start, word.cursor)
    else:
      (position, position)
  of psgLine:
    let lineStart = BufferPosition(line: position.line, column: 0)
    (lineStart, lineStart)
  of psgCharacter, psgBlock:
    (position, position)

func visualMode(granularity: PointerSelectionGranularity): EditorMode =
  case granularity
  of psgLine: EditorMode.VisualLine
  of psgBlock: EditorMode.VisualBlock
  of psgCharacter, psgWord: EditorMode.Visual

proc enterPointerVisualMode(e: Editor, granularity: PointerSelectionGranularity) =
  if not e.state.mode.isVisualAllMode:
    let previousMode = e.state.mode
    if previousMode in {EditorMode.Insert, EditorMode.Replace}:
      e.finalizeModeForFocusMove()
      e.state.previousMode = EditorMode.Normal
    else:
      e.state.previousMode = previousMode
  e.setMode(granularity.visualMode)

proc updatePointerSelection(e: Editor, position: BufferPosition) =
  let
    gesture = e.state.pointerSelection
    target = e.activeBuffer.pointerRange(position, gesture.granularity)
  var
    anchor = gesture.anchorFirst
    focus = target.last

  if gesture.granularity == psgWord:
    if gesture.extendMode:
      if target.first <= gesture.anchorFirst and gesture.anchorFirst <= target.last:
        anchor = target.first
        focus = target.last
      elif target.first >= gesture.anchorFirst:
        focus = target.last
      else:
        focus = target.first
    else:
      if target.last < gesture.anchorFirst:
        anchor = gesture.anchorLast
        focus = target.first
      elif target.first <= gesture.anchorLast:
        focus = gesture.anchorLast
  elif gesture.granularity == psgLine:
    focus = target.first

  if not gesture.selectionStarted:
    e.enterPointerVisualMode(gesture.granularity)
    e.state.pointerSelection.selectionStarted = true

  e.state.selectVisualRange(anchor, focus)
  e.activeWindow.viewport.detachedFromCursor = false

proc beginPointerSelection(e: Editor, input: PointerInput, hit: PointerTextHit) =
  e.focusWindow(hit.windowIndex)

  let
    oldCursor = e.cursor
    oldSelection = e.activeWindow.visualSelection
    extendSelection = kmShift in input.modifiers
    granularity = input.pointerGranularity(oldSelection)
    pressedRange = e.activeBuffer.pointerRange(hit.position, granularity)

  if not extendSelection:
    e.state.leaveVisual()

  let anchor =
    if extendSelection:
      if oldSelection.active: oldSelection.start else: oldCursor
    else:
      pressedRange.first

  e.state.pointerSelection = PointerSelectionGesture(
    active: true,
    windowIndex: hit.windowIndex,
    bufferId: e.activeBuffer.id,
    anchorFirst: anchor,
    anchorLast: if extendSelection: anchor else: pressedRange.last,
    granularity: granularity,
    extendMode: extendSelection,
  )

  if extendSelection or granularity in {psgWord, psgLine}:
    e.updatePointerSelection(hit.position)
  else:
    e.cursor = hit.position
    e.activeWindow.viewport.detachedFromCursor = false

proc updatePointerGesture(e: Editor, input: PointerInput): bool =
  if not e.state.pointerSelection.active:
    return false

  let gesture = e.state.pointerSelection
  if gesture.windowIndex != e.windowManager.activeWindowIndex or gesture.windowIndex < 0 or
      gesture.windowIndex >= e.windowManager.windows.len or
      e.activeBuffer.id != gesture.bufferId:
    e.state.pointerSelection.active = false
    return false

  let position = e.pointerPositionInWindow(input, gesture.windowIndex)
  if position.isSome:
    let moved =
      position.get != gesture.anchorFirst or gesture.anchorFirst != gesture.anchorLast
    if gesture.selectionStarted or input.action == paDrag or moved:
      e.updatePointerSelection(position.get)
  true

proc handlePointerInputCore(e: Editor, input: PointerInput): bool =
  ## Apply a frontend-neutral pointer event expressed in rendered grid cells.
  if not e.config.standard.mouse or input.button != pbPrimary:
    return false

  if input.action in {paDrag, paRelease}:
    result = e.updatePointerGesture(input)
    if input.action == paRelease:
      e.state.pointerSelection.active = false
    return
  if input.action != paPress:
    return false

  e.letHeldKeysGoFirst()
  e.state.armInsertResume()
  e.state.pointerSelection.active = false

  # Handle pointer selection in text editing modes.
  if e.state.mode in {
    EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualLine,
    EditorMode.VisualBlock, EditorMode.Replace,
  }:
    if e.pointerTabPress(input):
      return true

    let hit = e.pointerTextHit(input)
    if hit.isNone:
      return false
    e.beginPointerSelection(input, hit.get)
    return true

  # Handle mouse click in Filer mode
  if e.state.mode == EditorMode.Filer and e.activeWindow.modeState.kind == mskFiler:
    let filerState = e.activeWindow.modeState.filer
    let
      vp = e.activeWindow.viewport
      tabLineOffset = if e.showTabLine: TabLineHeight else: 0
      # Same reserve the renderer uses, so the hit test maps to the drawn row.
      reservedLines = e.steadyReservedLines(e.activeWindow)
      screenY = input.row - vp.y - tabLineOffset

    # Ignore clicks on tab line or status line
    if screenY >= 0 and screenY < vp.height - tabLineOffset - reservedLines:
      let clickedIndex = vp.topLine + screenY
      if clickedIndex >= 0 and clickedIndex < filerState.entries.len:
        filerState.selectedIndex = clickedIndex
        return true

  return false

proc handleWindowCommand(e: Editor, keyCombo: KeyCombo): Option[bool] =
  ## Handle Ctrl-W window command second key. Runs the same result as the file
  ## edit modes (see `WindowSecondKeyCommands`), so closing a viewer or
  ## Terminal window tears it down too.
  ## Returns some(true) if handled, some(false) if last window closed (quit),
  ## none if not a window command key.
  if e.state.pendingInput.pendingCommand == PendingWindowCmd:
    e.state.pendingInput.pendingCommand = PendingNone
    let r = windowSecondKeyToHandlerResult(keyCombo)
    if r.isSome:
      return some(e.processResult(r.get, e.activeBuffer()))
    return some(true) # Unknown window command, cancel

  # Check for Ctrl-w to enter window command mode
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and keyCombo.char == "w":
    e.state.pendingInput.pendingCommand = PendingWindowCmd
    return some(true)

  return none(bool)

proc beginInput(e: Editor) =
  ## Clear stale status, keep the mode policy and refresh the input time.

  # Clear status message from previous event cycle:
  # messages persist for one render frame, then clear on next input)
  e.state.statusMessage = ""
  e.enforceModePolicy()

  # Update last input time for auto backup idle detection
  e.updateInputTime()

proc settleWindowForInput(e: Editor, isKeyInput: bool) =
  ## A key runs where a smooth page scroll ends and resumes cursor-following;
  ## other input acts on what the window shows.
  if isKeyInput:
    e.state.windowDisplay.scrollAnimation.finishPageScroll()
    e.state.pointerSelection.active = false
    if e.windowManager.windows.len > 0:
      e.activeWindow.viewport.detachedFromCursor = false
  else:
    e.state.windowDisplay.scrollAnimation.stopPageScroll()

proc prepareForInput(e: Editor, isKeyInput: bool) =
  ## Per-input setup: clear stale status, refresh input timestamp, end any
  ## smooth page scroll on its way.
  e.beginInput()
  e.settleWindowForInput(isKeyInput)

proc prepareForKeyCombo(e: Editor) =
  ## Per-input setup for frontend-neutral key handling.
  e.prepareForInput(true)

template asInput(e: Editor, body: untyped) =
  ## Run a public input entry as one command (`asCommand`). Whichever way the
  ## input went (a mode, an overlay, the pointer, a mapping timeout), Insert
  ## then resumes if it ended the command Ctrl-o waits for, with the column
  ## vertical moves want as the command leaves it. Only the inputs that are
  ## commands start one (armInsertResume), so the others leave the wait alone.
  e.asCommand:
    body
  e.settleInsertResume()

proc handlePaste*(e: Editor, text: string): bool =
  ## Handle pasted text supplied by any frontend.
  e.prepareForInput(false)
  if e.windowManager.windows.len > 0:
    e.activeWindow.viewport.detachedFromCursor = false
  e.asInput:
    e.letHeldKeysGoFirst()
    result = e.handlePasteText(text)

proc handlePasteEvent*(e: Editor, event: Event): bool =
  ## Compatibility adapter for Celina bracketed-paste events.
  if event.kind != EventKind.Paste:
    return true
  e.handlePaste(event.pastedText)

proc handlePointerInput*(e: Editor, input: PointerInput): bool =
  ## Handle a pointer event whose coordinates are cells in the rendered grid.
  ## Middle-click paste is intentionally a host policy: GUI frontends should
  ## obtain the selection text and pass it to `handlePaste`.
  e.prepareForInput(false)
  e.asInput:
    result = e.handlePointerInputCore(input)
  e.enforceModePolicy()

proc handleScrollInput*(e: Editor, input: ScrollInput): ScrollOutcome =
  ## Handle a vertical scroll expressed as a signed number of physical lines
  ## and return the movement/region metadata needed for GUI repainting.
  e.prepareForInput(false)
  e.asInput:
    result = e.handleScrollInputCore(input)

proc celinaMouseModifiers(
    modifiers: set[celina.KeyModifier]
): set[key_bindings.KeyModifier] =
  if celina.KeyModifier.Ctrl in modifiers:
    result.incl(kmCtrl)
  if celina.KeyModifier.Alt in modifiers:
    result.incl(kmAlt)
  if celina.KeyModifier.Shift in modifiers:
    result.incl(kmShift)

proc handleMouseEventCore(e: Editor, event: Event): bool =
  e.prepareForInput(false)
  if event.kind != EventKind.Mouse:
    return false

  let mouse = event.mouse
  if mouse.kind != celina.MouseEventKind.Press:
    return false

  let modifiers = celinaMouseModifiers(mouse.modifiers)
  case mouse.button
  of mouse_logic.MouseButton.WheelUp:
    result =
      e.handleScrollInputCore(initScrollInput(mouse.y, mouse.x, -3, modifiers)).handled
  of mouse_logic.MouseButton.WheelDown:
    result =
      e.handleScrollInputCore(initScrollInput(mouse.y, mouse.x, 3, modifiers)).handled
  of mouse_logic.MouseButton.Left:
    result = e.handlePointerInputCore(
      initPointerInput(mouse.y, mouse.x, modifiers = modifiers)
    )
  else:
    result = false
  e.enforceModePolicy()

proc handleMouseEvent*(e: Editor, event: Event): bool =
  ## Compatibility adapter from Celina mouse events to Moe input values.
  e.asInput:
    result = e.handleMouseEventCore(event)

proc handleOverlayKeyCombo(e: Editor, keyCombo: KeyCombo): Option[bool] =
  ## Dispatch the Rename overlay and Debug mode. Returns some(result) if
  ## handled, none otherwise.
  if e.state.isRenameOverlay:
    return some(e.handleRenameModeKeyCombo(keyCombo))
  if e.state.mode == EditorMode.Debug:
    return some(e.handleDebugModeKeyCombo(keyCombo))
  return none(bool)

proc handlePopupKeyCombo(e: Editor, keyCombo: KeyCombo): Option[bool] =
  ## Dispatch LSP popups (CodeLens picker, Hover popup). Returns some(true)
  ## when the event was consumed; returns none when no popup is active, or
  ## when a popup was closed and the event should fall through to normal
  ## key processing (e.g. auto-hover popup will reappear on next render).

  # Handle CodeLens picker input when active
  if e.state.lspCache.codeLensPicker.isActive:
    # Escape or Ctrl-C - cancel picker, as a Vim popup menu
    if keyCombo.isEscOrCtrlC:
      e.state.lspCache.hideCodeLensPicker()
      e.state.statusMessage = ""
      return some(true)

    # Enter - confirm selection
    if keyCombo.isSpecial and keyCombo.special == skEnter:
      asyncSpawn e.codeLensPickerConfirm()
      return some(true)

    # j or Down - next item
    if not keyCombo.isSpecial:
      if keyCombo.char == "j":
        e.codeLensPickerSelectNext()
        return some(true)
      # k or Up - previous item
      if keyCombo.char == "k":
        e.codeLensPickerSelectPrev()
        return some(true)
      # Number keys 1-9 - direct selection
      let digit = keyCombo.char.asciiChar
      if digit.isSome and digit.get in '1' .. '9':
        let num = ord(digit.get) - ord('0')
        asyncSpawn e.codeLensPickerSelectByNumber(num)
        return some(true)

    if keyCombo.isSpecial:
      if keyCombo.special == skDown:
        e.codeLensPickerSelectNext()
        return some(true)
      if keyCombo.special == skUp:
        e.codeLensPickerSelectPrev()
        return some(true)

    # Any other key closes picker
    e.state.lspCache.hideCodeLensPicker()
    e.state.statusMessage = ""
    # Don't return - let the key be processed normally

  # Handle Hover popup input when active
  if e.state.lspCache.hoverPopup.isActive():
    # Escape always closes the popup
    if keyCombo.isSpecial and keyCombo.special == skEscape:
      e.state.lspCache.hideHoverPopup()
      return some(true)

    # Manual hover (K key): allow j/k/h/l and arrow keys for scrolling
    if not e.state.lspCache.hoverPopup.isAutoHover:
      # Ctrl-C closes it as Esc does, as a Vim popup with a filter. An
      # automatic one takes no keys, so Ctrl-C goes on as any other key.
      if keyCombo.isCtrlC:
        e.state.lspCache.hideHoverPopup()
        return some(true)
      if not keyCombo.isSpecial:
        if keyCombo.char == "j":
          e.state.lspCache.hoverPopupScrollDown()
          return some(true)
        if keyCombo.char == "k":
          e.state.lspCache.hoverPopupScrollUp()
          return some(true)
        if keyCombo.char == "l":
          e.state.lspCache.hoverPopupScrollRight()
          return some(true)
        if keyCombo.char == "h":
          e.state.lspCache.hoverPopupScrollLeft()
          return some(true)

      if keyCombo.isSpecial:
        if keyCombo.special == skDown:
          e.state.lspCache.hoverPopupScrollDown()
          return some(true)
        if keyCombo.special == skUp:
          e.state.lspCache.hoverPopupScrollUp()
          return some(true)
        if keyCombo.special == skRight:
          e.state.lspCache.hoverPopupScrollRight()
          return some(true)
        if keyCombo.special == skLeft:
          e.state.lspCache.hoverPopupScrollLeft()
          return some(true)

    # Close popup and fall through to normal key processing.
    # Auto-hover popup will reappear if cursor is still on a diagnostic.
    e.state.lspCache.hideHoverPopup()
    # Don't return - let the key be processed normally

  return none(bool)

proc handleSpecialModeWindowCommandKeyCombo(
    e: Editor, keyCombo: KeyCombo
): Option[bool] =
  ## Ctrl-W window commands for special/viewer modes (those outside the
  ## file-edit mode set). Returns some(result) if handled, none otherwise.
  if e.state.mode in {
    EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualBlock,
    EditorMode.VisualLine, EditorMode.Replace,
  }:
    return none(bool)

  # Cancel window command mode on Escape
  if e.state.pendingInput.pendingCommand == PendingWindowCmd and keyCombo.isSpecial and
      keyCombo.special == skEscape:
    e.state.pendingInput.pendingCommand = PendingNone
    return some(true)

  let window = e.activeWindow
  result = e.handleWindowCommand(keyCombo)
  # These keys never reach the Config handler that clears the sequence.
  if result.isSome and window.modeState.kind == mskConfig:
    window.modeState.config.clearKeySequence()

proc syncCompletionOtherBuffers(e: Editor, activeBuffer: TextBuffer) =
  ## Populate completion manager's `otherBuffers` with all FileEditMode
  ## buffers except the active one.
  var otherBufs: seq[TextBuffer] = @[]
  for win in e.windowManager.windows:
    if win.mode.isFileEditMode and win.buffer != activeBuffer and
        not win.buffer.isUtilityBuffer:
      otherBufs.add(win.buffer)
  e.handlerManager.insertHandler.completionManager.otherBuffers = otherBufs

proc dispatchPrompts(e: Editor, keyCombo: KeyCombo): Option[ReplayOutcome] =
  ## The LSP popups, which read a key before the mappings as Vim's popup menus
  ## do. `none` when none takes the key; one that only closes a popup goes on
  ## to the mappings. A popup belongs to the window, and an overlay is a line
  ## typed over it, so the popup takes no keys from the overlay.
  if e.state.hasOverlay:
    return none(ReplayOutcome)
  let queued = e.hostResultRequestCount
  if e.handlePopupKeyCombo(keyCombo).isNone:
    return none(ReplayOutcome)
  some(if e.hostResultRequestCount > queued: roAbort else: roContinue)

proc dispatchFrontLayers(e: Editor, keyCombo: KeyCombo): Option[ReplayOutcome] =
  ## The layers in front of the mode handlers, which run a key the mappings
  ## have had: the overlays, Debug mode, a viewer's Ctrl-W and Recent File
  ## mode. `none` falls through to the mode handlers.
  # The command and search lines report how their Enter went themselves.
  let line =
    if e.state.isCommandOverlay:
      some(e.handleCommandModeKeyCombo(keyCombo))
    elif e.state.isSearchOverlay:
      some(e.handleSearchModeKeyCombo(keyCombo))
    else:
      none(ReplayOutcome)
  if line.isSome:
    e.enforceModePolicy()
    return line

  let queued = e.hostResultRequestCount
  # Handle the Rename overlay + Debug mode
  var handled = e.handleOverlayKeyCombo(keyCombo)
  if handled.isSome:
    e.enforceModePolicy()
  if handled.isNone:
    # Ctrl-W window commands for special/viewer modes
    handled = e.handleSpecialModeWindowCommandKeyCombo(keyCombo)
  if handled.isNone and e.state.mode == EditorMode.RecentFile:
    # Handle Recent File mode input (after Ctrl-W window commands)
    handled = some(e.handleRecentFileModeKeyCombo(keyCombo))
  if handled.isNone:
    return none(ReplayOutcome)
  if not handled.get:
    some(roQuit)
  elif e.hostResultRequestCount > queued:
    some(roAbort)
  else:
    some(roContinue)

promptLayerHook = proc(e: Editor, keyCombo: KeyCombo): Option[ReplayOutcome] =
  e.dispatchPrompts(keyCombo)

frontLayerHook = proc(e: Editor, keyCombo: KeyCombo): Option[ReplayOutcome] =
  e.dispatchFrontLayers(keyCombo)

proc flushTypeahead(e: Editor) =
  ## Drop the input queued before an interrupt, as Vim flushes its typeahead:
  ## the keys held for a mapping, and the pastes the active terminal has yet
  ## to send.
  e.keyRouter.dropHeldKeys()
  when not defined(moe.embedded):
    # An overlay over Terminal or the hit-enter prompt takes the Ctrl-C; the
    # session's pastes stay.
    let win = e.activeWindow
    if win.modeState.kind == mskTerminal and not e.state.hasOverlay and
        e.state.ui.tempMessages.len == 0:
      win.modeState.terminal.cancelQueuedPastes()

proc dispatchKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle one frontend-neutral key combination, without noting a quit.
  ## Public entry points (`handleKeyCombo`, `handleTextInput`, `handleEvent`)
  ## record the result through `noteQuit`. A typed Ctrl-C no mapping of the
  ## mode it meets takes is also an interrupt, as Vim's got_int.
  e.beginInput()
  let interrupts =
    keyCombo.isCtrlC and (
      e.readsKeyUnmapped(keyCombo) or
      not e.keyRouter.startsMapping(e.routerMode, keyCombo)
    )
  # Like input that is not a key, an interrupt leaves the window as it shows:
  # a smooth page scroll stops there.
  e.settleWindowForInput(isKeyInput = not interrupts)
  e.state.armInsertResume()

  when not defined(moe.embedded):
    # Before any dispatch, so a key the editor consumes never leaves a Ctrl-\
    # held past the keystroke it was pressed for.
    for win in e.windowManager.windows:
      if win.modeState.kind == mskTerminal:
        win.modeState.terminal.releaseHeldQuitForKey(keyCombo)

  e.updateViewportReservedLines()
  e.syncCompletionOtherBuffers(e.activeBuffer)

  # The one place a key enters as typed, so every mode records it alike.
  # Playback loops enter `runNestedKeyCombo` directly and stand for no typed
  # keys.
  var key = typedKey(keyCombo)
  let wasInterrupted = e.state.interrupted
  if interrupts:
    e.flushTypeahead()
    # Recorded as it is read, whatever then takes it, as Vim records it.
    e.state.pendingInput.macroState.recordTypedKeys([CtrlC])
    key.standsFor = @[]
    e.state.interrupted = true
  let outcome =
    try:
      e.handlerManager.runNestedKeyCombo(e, key)
    finally:
      e.state.interrupted = wasInterrupted

  # In Config mode, sync display state only when a value was actually mutated.
  # Plain cursor movement leaves pendingApply false, avoiding a theme reread and
  # a full re-highlight of every buffer on each keystroke.
  if e.currentMode == EditorMode.Config:
    let win = e.activeWindow
    if win.modeState.kind == mskConfig and win.modeState.config.pendingApply:
      e.applyConfigSettings(e.config)
      win.modeState.config.pendingApply = false

  # For LogViewer mode, update viewport to follow cursor
  # (LogViewer handles cursor directly without using MotionController)
  if e.currentMode == EditorMode.LogViewer:
    e.updateViewportForCursor(e.cursor)

  return outcome != roQuit

proc dispatchTextInput(e: Editor, text: string): bool =
  ## Handle committed text from a GUI text-input protocol, without noting a quit.
  ##
  ## This is distinct from a physical key event so frontends can preserve IME,
  ## dead-key, and composed Unicode input. Special keys and modified shortcuts
  ## should still be sent through `handleKeyCombo`. `text` may contain more than
  ## one rune, but paste operations should use `handlePaste`.
  if text.len == 0:
    return true
  e.dispatchKeyCombo(KeyCombo(isSpecial: false, char: text, modifiers: {}))

proc dispatchEvent(e: Editor, event: Event): bool =
  ## Main event handler using the new handler manager system
  if event.kind == EventKind.Key:
    let keyComboOpt = eventToKeyCombo(event)
    if keyComboOpt.isNone:
      e.prepareForKeyCombo()
      return true
    return e.dispatchKeyCombo(keyComboOpt.get)

  # A terminal's Ctrl-C comes as celina's Quit event.
  if event.kind == EventKind.Quit:
    return e.dispatchKeyCombo(CtrlC)

  # Handle mouse events first
  if event.kind == EventKind.Mouse:
    # Middle-click paste works regardless of mouse config since mouseCapture
    # is always enabled and would otherwise block the terminal's native paste.
    if event.mouse.button == mouse_logic.MouseButton.Middle and
        event.mouse.kind == celina.MouseEventKind.Press:
      e.prepareForInput(false)
      e.middleClickPaste(event.mouse.y, event.mouse.x)
      return true
    discard e.handleMouseEvent(event)
    return true # Always continue running after mouse events

  # Handle paste events (Bracketed Paste Mode)
  if event.kind == EventKind.Paste:
    return e.handlePasteEvent(event)

  e.prepareForInput(false)
  return true

type
  FrontendSuspendHook* = proc(): Future[void]
  FrontendHooks* = object
    ## Optional frontend callbacks for operations that need the host UI.
    suspend*: FrontendSuspendHook
    resume*: FrontendSuspendHook

template withFrontendSuspend(frontend: FrontendHooks, e: Editor, body: untyped) =
  ## Suspend the owning frontend around synchronous terminal interaction.
  ## `body` blocks the event loop, so it must return soon after a deadly signal
  ## (see `runInTerminal`, `waitForEnter`). Ctrl-C there is dropped.
  if frontend.suspend.isNil or frontend.resume.isNil:
    e.state.statusMessage = "This frontend does not support terminal commands"
  elif takenSignal() != 0:
    logInfo("handler", "Terminal not handed over: a deadly signal is being answered")
  else:
    withTerminalHandedOver:
      await frontend.suspend()
      try:
        body
      finally:
        # Still in the background (after `kill %1`), the loop answers without
        # the terminal: taking it would stop moe.
        stayStoppedInBackground()
        if not inBackground():
          await frontend.resume()

proc runQuickRunJob(
    editor: Editor, info: QuickRunInfo
): Future[void] {.async: (raises: []).} =
  ## Run QuickRun process in background and display output when complete
  {.cast(gcsafe).}:
    try:
      let prepared = QuickRunPrepareResult(
        command: BackgroundProcessCommand(cmd: info.cmd, args: info.args),
        filePath: info.filePath,
        workDir: info.workDir,
      )
      let quickRunResult = startBackgroundQuickRun(prepared)
      if quickRunResult.isErr:
        editor.notify("QuickRun error: " & quickRunResult.error, nlError)
      else:
        let qrProcess = quickRunResult.get
        # Track the full QuickRunProcess (not just its BackgroundProcess) so
        # editor exit/crash can also remove its temp files, not only kill the
        # process. See cleanupQuickRunProcesses.
        editor.addRunningQuickRun(qrProcess)
        # In a `finally`, as with the syntax check; a stale entry would also
        # keep the temporary file alive.
        let outputResult =
          try:
            await qrProcess.waitForResultAsync(
              timeoutFromSeconds(editor.config.quickRun.timeout)
            )
          finally:
            editor.removeRunningQuickRun(qrProcess)
        if outputResult.isErr:
          editor.notify("QuickRun error: " & outputResult.error, nlError)
        else:
          let shown = editor.showCommandOutput(outputResult.get, keepFocus = false)
          if shown and editor.config.notification.screenNotifications and
              editor.config.notification.quickRunScreenNotify:
            editor.notify("QuickRun completed: " & qrProcess.filePath)
    except Exception as ex:
      editor.notify("QuickRun error: " & ex.msg, nlError)

proc runFilterAsync(
    editor: Editor, info: FilterInfo
): Future[void] {.async: (raises: []).} =
  ## Run a command as a text filter and put its output back into the buffer.
  {.cast(gcsafe).}:
    try:
      let before = editor.bufferById(info.bufferId)
      if before.isNone:
        editor.notify("Filter error: the buffer is gone", nlError)
        return
      if before.get.contentVersion != info.contentVersion:
        editor.notify("Filter: the buffer changed before the command ran", nlError)
        return

      # Filters expect every line newline-terminated, the last one included.
      # Read here rather than copied into the op: the version gate protects it.
      var input = ""
      for i in info.first .. info.last:
        input.add before.get.getLine(i)
        input.add '\n'

      let startResult = startFilterProcess(
        BackgroundProcessCommand(
          cmd: "sh", args: @["-c", info.command], workingDir: getCurrentDir()
        )
      )
      if startResult.isErr:
        editor.notify("Filter error: " & startResult.error, nlError)
        return

      let bp = startResult.get
      # Labelled but pathless: a filter rewrites the buffer, not a file, so it
      # claims no job and only has to show up in `:jobs`.
      editor.addRunningProcess(bp, "Filter")
      let filtered = await bp.filterOutput(
        input,
        timeoutFromSeconds(editor.config.filter.timeout),
        editor.config.filter.maxOutputSize,
      )
      editor.removeRunningProcess(bp)
      if filtered.isErr:
        editor.notify("Filter error: " & filtered.error.message, nlError)
        return

      let buf = editor.bufferById(info.bufferId)
      if buf.isNone:
        editor.notify("Filter error: the buffer is gone", nlError)
        return
      let buffer = buf.get
      if buffer.contentVersion != info.contentVersion:
        # The output describes lines that are no longer there.
        editor.notify("Filter: the buffer changed while the command ran", nlError)
        return
      if not buffer.allowsTextTransforms:
        editor.notify("Filter error: " & rawBytesRejection("filter"), nlError)
        return

      # Use the output whatever the exit status, as `!` in vim does: `grep`
      # with no match exits 1 having correctly produced nothing. The status
      # only goes in the message. A trailing newline closes the last line
      # rather than opening an empty one, and outside text is sanitized like
      # a paste.
      var produced: seq[string]
      if filtered.get.output.len > 0:
        let body =
          if filtered.get.output.endsWith("\n"):
            filtered.get.output[0 ..^ 2]
          else:
            filtered.get.output
        for line in body.split('\n'):
          produced.add line.sanitizeInvalidUtf8()

      let replaced = info.last - info.first + 1
      if buffer.len - replaced + produced.len == 0:
        # A buffer always holds at least one line.
        produced.add ""

      # Replace the span rather than diffing a rebuilt buffer: the cost follows
      # the range, and no line outside it can be rewritten. `keepRows = false`
      # because the range is rewritten wholesale, leaving folds and bookmarks
      # on it nothing to point at.
      let applied =
        buffer.replaceLines(info.first, replaced, produced, keepRows = false)
      if applied.isErr:
        editor.notify("Filter error: " & applied.error, nlError)
        return

      # Only the window the command was typed in jumps to the start of the
      # range, as in vim, and it may be gone or showing something else by now.
      # The rest are re-clamped: a filter can leave the buffer shorter.
      let windows = editor.windowManager.windows
      if info.windowIndex in 0 ..< windows.len and
          windows[info.windowIndex].buffer.id == info.bufferId:
        windows[info.windowIndex].cursor = BufferPosition(line: info.first, column: 0)
      editor.clampAllWindowCursors()

      # One report: separate notifications overwrite each other on the status
      # line.
      let
        status = filtered.get.exitCode
        ranCleanly = status.isSome and status.get == 0
        howItEnded =
          if status.isNone:
            " (exit status unknown)"
          elif ranCleanly:
            ""
          else:
            " (exit " & $status.get & ")"
      var report = @[
        $replaced & " line" & (if replaced == 1: "" else: "s") & " filtered through " &
          info.command & howItEnded
      ]
      for line in filtered.get.diagnostics:
        # stderr goes straight to the status line, so strip escape sequences
        # (a byte-bounded read can also cut one in half).
        report.add line.forDisplay
      if filtered.get.diagnosticsTruncated:
        report.add "... the rest of what it wrote on stderr was dropped"
      # stderr output is not failure; only the exit status decides.
      editor.notifyAll(report, if ranCleanly: nlInfo else: nlError)
    except Exception as ex:
      editor.notify("Filter error: " & ex.msg, nlError)

proc runQuickRunAsync(
    editor: Editor, info: QuickRunInfo, epoch: uint64
): Future[void] {.async: (raises: []).} =
  ## `epoch` is what the op carried when queued, so an earlier `:jobs!` stops
  ## the run rather than letting it start late.
  if editor.commandsStoppedSince(epoch):
    removeQuickRunWorkDir(info.workDir)
    return
  await runQuickRunJob(editor, info)

proc handlePendingAsyncOperationsImpl(
    e: Editor, frontend: FrontendHooks
): Future[void] {.async: (raises: [Exception]).} =
  ## Drain the pending async op queue in FIFO order. Called from the main event
  ## loop on every tick. Ops queued while draining run on the next tick.

  {.cast(gcsafe).}:
    let ops = move(e.state.pending)
    e.state.pending.setLen(0)

    for index, op in ops:
      try:
        case op.kind
        of paoTerminalCommand:
          e.enterTerminalInActiveWindow(op.command)
        of paoShellCommand:
          # withFrontendSuspend wraps the body in try/finally so the TUI always
          # resumes, even if the command or the prompt raises (a missed resume
          # leaves the terminal in raw mode and destroys the screen).
          withFrontendSuspend(frontend, e):
            stdout.write("\e[H\e[2J") # Clear screen
            stdout.flushFile()
            let exitCode = runInTerminal(op.command)
            withTerminalOutput:
              stdout.write("\n\nShell returned " & $exitCode & "\n")
              stdout.write("Press Enter to continue...")
              stdout.flushFile()
            waitForEnter()
        of paoManPage:
          withFrontendSuspend(frontend, e):
            stdout.write("\e[H\e[2J") # Clear screen
            stdout.flushFile()
            let exitCode = runInTerminal("man " & quoteShell(op.command))
            # Past 127: killed. -1: did not run or was lost.
            withTerminalOutput:
              if exitCode in 1 .. 127:
                stdout.write("man: " & op.command & " not found\n")
              stdout.write("\nPress Enter to continue...")
              stdout.flushFile()
            waitForEnter()
        of paoBackground:
          # SIGTSTP to self so the shell registers moe as a proper stopped job
          # (visible in `jobs`, resumable via `fg`). Falls back to a blocking
          # readLine where SIGTSTP is unavailable.
          withFrontendSuspend(frontend, e):
            when defined(posix):
              discard posix.kill(posix.Pid(posix.getpid()), posix.SIGTSTP)
            else:
              stdout.write("\e[H\e[2J")
              stdout.write("moe suspended. Press Enter to return to moe...")
              stdout.flushFile()
              discard stdin.readLine()
        of paoQuickRun:
          asyncSpawn runQuickRunAsync(e, op.quickRun, op.epoch)
        of paoFilter:
          asyncSpawn runFilterAsync(e, op.filter)
      except Exception as ex:
        logError("moe", "Pending async operation " & $op.kind & " failed: " & ex.msg)
        e.notify("Pending operation failed (" & $op.kind & "): " & ex.msg, nlError)

        # Do not lose work queued behind a failed operation.
        if index + 1 < ops.len:
          e.state.pending = ops[index + 1 .. ^1] & e.state.pending
        break

proc handlePendingAsyncOperations*(
    e: Editor, frontend: FrontendHooks
): Future[void] {.async: (raises: []).} =
  ## Wrapper for handlePendingAsyncOperationsImpl. Swallows and logs any
  ## exception so a pending-op failure does not trip editorCallback's
  ## emergency-save-and-quit path (drain is called from every tick).
  {.cast(gcsafe).}:
    try:
      await handlePendingAsyncOperationsImpl(e, frontend)
    except Exception as ex:
      logError("moe", "handlePendingAsyncOperations failed: " & ex.msg)

proc dispatchKeyMappingTimeout(e: Editor): bool =
  ## Called when the key mapping timeout fires. `KeyRouter.flushTimeout`
  ## decides against the table of the mode it fires in, as Vim reads its
  ## typeahead in the mode it is in then, and the plan runs as a typed key's
  ## would. Returns true to continue running, false to quit.
  let route = e.keyRouter.flushTimeout(e.routerMode)
  e.handlerManager.runRoute(e, route).get(roContinue) != roQuit

proc noteQuit(e: Editor, goesOn: bool): bool =
  ## Every quit reaches the frontend through here, so it is noted once.
  ## Background work stops, except what the quit is owed.
  if not goesOn:
    e.beginQuit()
  goesOn

proc handleKeyCombo*(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle one frontend-neutral key combination. False when the editor decided
  ## to quit.
  ##
  ## GUI frontends can call this directly after translating their native key
  ## input into Moe's `KeyCombo` type. Terminal-specific events such as Quit,
  ## paste, and mouse input remain handled by `handleEvent`.
  e.asInput:
    result = e.noteQuit(e.dispatchKeyCombo(keyCombo))

proc handleInterrupt*(e: Editor): bool =
  ## Handle a frontend interrupt request, such as Ctrl-C in a terminal: the
  ## typed Ctrl-C key, which interrupts unless a mapping takes it. False when
  ## the editor decided to quit.
  e.handleKeyCombo(CtrlC)

proc handleTextInput*(e: Editor, text: string): bool =
  ## Handle committed text from a GUI text-input protocol. False when the
  ## editor decided to quit.
  e.asInput:
    result = e.noteQuit(e.dispatchTextInput(text))

proc handleEvent*(e: Editor, event: Event): bool =
  ## Handle `event`. False when the editor decided to quit.
  e.asInput:
    result = e.noteQuit(e.dispatchEvent(event))

proc handleKeyMappingTimeout*(e: Editor): bool =
  ## Handle the key mapping timeout. False when the editor decided to quit.
  e.asInput:
    result = e.noteQuit(e.dispatchKeyMappingTimeout())
