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

import std/[options, os, strutils, sequtils, unicode]

when defined(posix):
  from std/posix import nil

import pkg/[celina, results, chronos]
from pkg/celina/core/mouse_logic import MouseButton

import
  editor, editor_window_layout, editor_window_state, key_bindings, modes, buffer,
  logger, types, motion, quick_run_utils, command_completion, build, render_utils,
  tab_line, terminal_mode, clipboard, status_line, cursor_util, syntax_checker,
  background_process, key_router
import
  command_handlers/[
    handler_manager, command_mode_handler, search_mode_handler, insert_commands,
    result_processor,
  ]
export command_mode_handler, search_mode_handler, cursor_util

# Wire the playback overlay hook so nested key replay routes to the overlay
# handler when Command / Search overlay is active.
overlayPlaybackHook = proc(e: Editor, keyCombo: KeyCombo): Option[bool] =
  if e.state.isCommandOverlay:
    return some(e.handleCommandModeKeyCombo(keyCombo))
  if e.state.isSearchOverlay:
    return some(e.handleSearchModeKeyCombo(keyCombo))
  return none(bool)

proc addRunningProcess*(e: Editor, p: BackgroundProcess) =
  e.runningBackgroundProcesses.add(p)

proc removeRunningProcess*(e: Editor, p: BackgroundProcess) =
  let idx = e.runningBackgroundProcesses.find(p)
  if idx >= 0:
    e.runningBackgroundProcesses.delete(idx)

proc cleanupBackgroundProcesses*(e: Editor) =
  ## Cancel all running background processes (call on editor exit)
  for p in e.runningBackgroundProcesses:
    if p.isRunning:
      p.kill()
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
  ## shutdown cleanup (`cleanupGitDiffCache`).
  for p in e.runningQuickRunProcesses:
    abandonQuickRunProcess(p)
  e.runningQuickRunProcesses = @[]

proc handleRenameModeKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in Rename mode - for LSP rename symbol input
  ##
  ## Key Mappings:
  ## - Escape      -> Cancel rename, return to Normal mode
  ## - Enter/CR    -> Execute rename with current text
  ## - Backspace   -> Remove last character
  ## - Character   -> Add character to rename text
  ##
  ## Returns: true (event handled)
  # Escape: Cancel rename and return to base mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.state.exitOverlay()
    e.setMode(e.state.mode) # Sync window mode
    e.state.statusMessage = "Rename cancelled"
    return true

  # Enter: Execute rename
  let isEnter =
    (keyCombo.isSpecial and keyCombo.special == skEnter) or
    (not keyCombo.isSpecial and (keyCombo.char == "\n" or keyCombo.char == "\r"))

  if isEnter:
    let newName = e.state.renameState.text
    if newName.len == 0:
      e.state.statusMessage = "Rename cancelled: empty name"
      e.state.exitOverlay()
      e.setMode(e.state.mode) # Sync window mode
    elif newName == e.state.renameState.originalWord:
      e.state.statusMessage = "Rename cancelled: same name"
      e.state.exitOverlay()
      e.setMode(e.state.mode) # Sync window mode
    else:
      # Execute the LSP rename asynchronously
      e.state.exitOverlay()
      e.setMode(e.state.mode) # Sync window mode
      asyncSpawn e.requestLspRename(newName)
    return true

  # Backspace: Remove last character (Unicode-aware)
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    if e.state.renameState.text.runeLen > 0:
      e.state.renameState.text =
        e.state.renameState.text.runeSubStr(0, e.state.renameState.text.runeLen - 1)
    return true

  # Character input: Add character to rename text
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    e.state.renameState.text &= keyCombo.char
    return true

  # Ignore other special keys
  return true

proc handleRecentFileModeKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in Recent File mode.
  # Get viewport height for the recent file list
  # Reserve: status/command line (shared row) + 1 line for title
  let viewportHeight = max(0, e.viewport.height - steadyBottomAreaHeight() - 1)

  let activeWin = e.activeWindow
  if activeWin.modeState.kind != mskRecentFile:
    return true

  let r = e.handlerManager.handleRecentFileMode(
    activeWin.modeState.recentFile, viewportHeight, keyCombo
  )

  case r.kind
  of hrRecentFileQuit:
    # Close the split window
    activeWin.clearModeState(EditorMode.RecentFile)
    let buf = activeWin.buffer
    let idx = e.bufferIndexById(buf.id)
    if idx >= 0:
      evictGitCacheForBuffer(buf)
      e.deleteBufferAt(idx)
      e.pruneBufferIdFromAllWindows(buf.id)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    discard e.closeWindow
    e.state.statusMessage = ""
    return true
  of hrRecentFileOpenFile:
    let filePath = r.recentFilePath
    if not fileExists(filePath):
      logError("handler", "File not found: " & filePath)
      e.state.statusMessage = "File not found: " & filePath
      return true
    # Close the split window first
    activeWin.clearModeState(EditorMode.RecentFile)
    let buf = activeWin.buffer
    let idx = e.bufferIndexById(buf.id)
    if idx >= 0:
      evictGitCacheForBuffer(buf)
      e.deleteBufferAt(idx)
      e.pruneBufferIdFromAllWindows(buf.id)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    discard e.closeWindow
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
      hrBufferFirst, hrBufferLast, hrBuffer, hrJumpToBuffer, hrBufferDelete,
      hrStripWhitespace, hrFilerOpenFile, hrFilerOpenFileVSplit, hrFilerOpenFileHSplit,
      hrFilerDeleteFile, hrFilerShowInfo, hrFilerQuit, hrEnterFiler, hrLogViewerQuit,
      hrLogViewerRefresh, hrEnterLogViewer, hrHelpViewerQuit, hrEnterHelpViewer,
      hrQuickRun, hrBufferManagerSelectBuffer, hrBufferManagerDeleteBuffer,
      hrBufferManagerQuit, hrEnterBufferManager, hrBookmarkManagerJump,
      hrBookmarkManagerDelete, hrBookmarkManagerQuit, hrEnterBookmarkManager,
      hrBackupManagerRestore, hrBackupManagerDelete, hrBackupManagerOpenDiff,
      hrBackupManagerRefresh, hrBackupManagerQuit, hrEnterBackupManager,
      hrDiffViewerQuit, hrEnterDiffViewer, hrRecentFile, hrNextWindow, hrPrevWindow,
      hrIncreaseWindowHeight, hrDecreaseWindowHeight, hrIncreaseWindowWidth,
      hrDecreaseWindowWidth, hrEqualizeWindows, hrSwapWindow, hrLspGotoDefinition,
      hrLspGotoDeclaration, hrLspFindReferences, hrLspDocumentSymbol,
      hrLspCodeLensExecute, hrLspCallHierarchyIncoming, hrLspCallHierarchyOutgoing,
      hrLspTypeDefinition, hrLspImplementation, hrLspHover, hrLspRename,
      hrLspSelectionRange, hrLspDocumentLink, hrShellCommand, hrBackground, hrJumpList,
      hrChanges, hrBuild, hrDebug, hrDebugViewerQuit, hrConfig, hrConfigQuit,
      hrConfigSaveConfig, hrPutConfigFile, hrTheme, hrLspLog, hrLspFormat, hrLspRestart,
      hrLspFold, hrLspExecuteCommand, hrSubstitute, hrDeleteLines, hrMan,
      hrReferencesQuit, hrReferencesJumpTo, hrEnterReferences, hrDocumentSymbolQuit,
      hrDocumentSymbolJumpTo, hrEnterDocumentSymbol, hrCallHierarchyQuit,
      hrCallHierarchyJumpTo, hrCallHierarchyRequestIncoming,
      hrCallHierarchyRequestOutgoing, hrEnterCallHierarchy, hrEnterTerminal,
      hrTerminalQuit, hrExecCommand, hrOnlyWindow, hrEnterFileTree, hrFileTreeOpenFile,
      hrFileTreeQuit, hrOpenUri, hrCquit, hrConflictNext, hrConflictPrev, hrMapAdd,
      hrMapRemove, hrMapClear, hrMapList, hrPlaybackMacro:
    discard # Not expected from RecentFile mode handler

  # Handle overlay transitions (e.g., entering Command mode with :)
  let overlayTransition = r.getOverlayTransition()
  if overlayTransition.isSome:
    case overlayTransition.get
    of okCommand:
      e.state.enterCommandOverlay()
    of okSearch:
      e.state.enterSearchOverlay(e.state.input.search.direction)
    of okRename:
      e.state.enterRenameOverlay(
        e.state.renameState.originalWord, e.state.renameState.cursorLine,
        e.state.renameState.cursorColumn,
      )

  # Handle mode transitions
  let modeTransition = r.getModeTransition()
  if modeTransition.isSome:
    e.state.previousMode = e.state.mode
    e.setMode(modeTransition.get)

  return true

proc handleDebugModeKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in Debug mode.
  # Get viewport height for the debug viewer
  # Reserve: status/command line (shared row) + 1 line for title
  let viewportHeight = max(0, e.viewport.height - steadyBottomAreaHeight() - 1)

  let activeWin = e.activeWindow
  if activeWin.modeState.kind != mskDebug:
    e.state.statusMessage = "Debug viewer state not initialized"
    return true

  let r = handleDebugModeKey(activeWin.modeState.debug, viewportHeight, keyCombo)

  case r.kind
  of dvrEnterCommand:
    e.state.enterCommandOverlay()
    return true
  of dvrHandled, dvrUnhandled, dvrError:
    return true

proc handlePasteEvent*(e: Editor, event: Event): bool =
  ## Handle paste events from Bracketed Paste Mode
  ## Inserts pasted text without triggering auto-indentation
  if event.kind != EventKind.Paste:
    return true

  # Normalize CRLF / lone CR to LF up front (matching loadFile) so a stray \r
  # never reaches line content and the cursor advance below counts line breaks
  # correctly. insertText normalizes again defensively for non-paste callers.
  let pastedText = event.pastedText.normalizeNewlines()
  if pastedText.len == 0:
    return true

  # Command / Search overlay takes precedence over the base mode.
  # Only the first line is inserted since both are single-line.
  if e.state.isCommandOverlay:
    e.insertPastedTextInCommand(pastedText)
    return true
  if e.state.isSearchOverlay:
    e.insertPastedTextInSearch(pastedText)
    return true

  let activeBuffer = e.activeBuffer()

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

    var pos = e.cursor
    discard activeBuffer.insertText(pos, pastedText)

    # Calculate new cursor position after paste. Iterate by rune: cursor.column
    # is a rune index everywhere (insertTextWithNewlines/deleteChar), so byte
    # iteration would over-advance on multibyte text.
    var newLine = pos.line
    var newColumn = pos.column
    for r in pastedText.runes:
      if r == Rune('\n'):
        newLine += 1
        newColumn = 0
      else:
        newColumn += 1

    e.activeWindow.cursor.line = newLine
    e.activeWindow.cursor.column = newColumn

    if ownTransaction:
      discard activeBuffer.commitTransaction()
  else:
    # For other modes, just show a message
    e.state.statusMessage = "Paste not supported in this mode"

  return true

proc screenToBufferPosition(
    vp: ViewPort,
    buffer: TextBuffer,
    mouseX, mouseY: int,
    lineNumOffset, sidebarWidth, reservedLines: int,
    lineWrap: bool,
    tabStop: int = 4,
    scrollbarWidth: int = 0,
    wrapCache: WrapCountCache = nil,
): Option[BufferPosition] =
  ## Convert screen coordinates to buffer position.
  ## Returns none if click is outside the text area.
  ## Handles line wrap mode with display-width-based segment calculation.
  ##
  ## lineNumOffset: line number area width (from calculateLineNumOffset)
  ## sidebarWidth: sidebar area width (from calculateSidebarWidth)
  ## scrollbarWidth: scrollbar area width (from calculateScrollbarWidth)
  ## These are separate parameters to match the rendering calculation exactly.
  let
    totalOffset = sidebarWidth + lineNumOffset
    screenY = mouseY - vp.y
    screenX = mouseX - vp.x - totalOffset

  # Check if click is within the text area
  if screenY < 0 or screenY >= vp.height - reservedLines:
    return none(BufferPosition)
  if screenX < 0:
    return none(BufferPosition)

  if lineWrap:
    # Must match renderWindowLineWrapped: maxWidth = viewport.width - sidebarWidth - scrollbarWidth - lineNumOffset
    let maxWidth = max(1, vp.width - sidebarWidth - scrollbarWidth - lineNumOffset)
    if wrapCache != nil:
      wrapCache.ensureFresh(buffer, maxWidth, tabStop)
    # Walk through buffer lines, accumulating screen rows for each wrapped line.
    # Start above the top edge by the leading wrap segments the renderer skips on
    # the first line (topWrapOffset), mirroring calculateWindowCursor: screen row
    # 0 then maps to segment topWrapOffset of topLine, not segment 0.
    var currentScreenY = -vp.topWrapOffset
    var bufferLine = vp.topLine
    var wrapSegment = 0

    while bufferLine < buffer.len:
      let wrapCount =
        if wrapCache != nil:
          wrapCache.cachedWrapCount(buffer, bufferLine)
        else:
          calculateWrapCount(buffer.getLine(bufferLine), maxWidth, tabStop)
      if currentScreenY + wrapCount > screenY:
        wrapSegment = screenY - currentScreenY
        break
      currentScreenY += wrapCount
      bufferLine += 1

    if bufferLine >= buffer.len:
      bufferLine = max(0, buffer.len - 1)

    # Find the start character of the wrapSegment-th segment
    let line = buffer.getLine(bufferLine)
    var segStart = 0
    for i in 0 ..< wrapSegment:
      let (charCount, _) = displayWidthSubstrWithTabs(line, segStart, maxWidth, tabStop)
      segStart += max(1, charCount)

    # Convert screenX to a character offset within this segment
    var bufferColumn = segStart + screenXToCharIndex(line, segStart, screenX, tabStop)

    # Clamp column to valid range
    if bufferLine >= 0 and bufferLine < buffer.len:
      let lineCharLen = buffer.getLine(bufferLine).charLen
      bufferColumn = clamp(bufferColumn, 0, max(0, lineCharLen - 1))

    return some(BufferPosition(line: bufferLine, column: bufferColumn))
  else:
    # No-wrap mode: simple calculation
    var bufferLine = vp.topLine + screenY
    if bufferLine >= buffer.len:
      bufferLine = max(0, buffer.len - 1)

    var bufferColumn = vp.leftColumn + screenX

    # Clamp column to valid range
    if bufferLine >= 0 and bufferLine < buffer.len:
      let lineLen = buffer[bufferLine].charLen
      bufferColumn = clamp(bufferColumn, 0, max(0, lineLen - 1))

    return some(BufferPosition(line: bufferLine, column: bufferColumn))

proc calculateLineNumOffsetForMouse(e: Editor, buffer: TextBuffer): int =
  ## Calculate line number offset (matching rendering calculation)
  calculateLineNumOffset(buffer, e.showLineNumbers)

proc middleClickPaste(e: Editor) =
  ## Paste clipboard content at current cursor position for middle-click.
  if not e.config.clipboard.enable:
    return

  # Command / Search overlay: paste into the command / search line instead
  # of the buffer. Only the first line is inserted since both are single-line.
  if e.state.isCommandOverlay or e.state.isSearchOverlay:
    let readResult = readFromPrimarySelectionSync(e.config.clipboard.tool)
    if readResult.isErr:
      return
    # Normalize so an embedded CR-only break can't leak a raw \r into the
    # single-line command / search field (matching the bracketed-paste path).
    let pastedText = readResult.get().normalizeNewlines()
    if pastedText.len == 0:
      return
    if e.state.isCommandOverlay:
      e.insertPastedTextInCommand(pastedText)
    else:
      e.insertPastedTextInSearch(pastedText)
    return

  # A read-only active buffer must not slip into Insert mode via middle-click:
  # the Insert-entry gate lives in normal_handler, which mouse events bypass.
  if e.activeBuffer().readOnly:
    e.state.statusMessage = "Buffer is read-only"
    return

  if e.state.mode == EditorMode.Normal:
    e.setMode(EditorMode.Insert)
    let activeBuffer = e.activeBuffer()
    discard activeBuffer.beginTransaction(
      "Insert mode edit", cursorPos = some(e.activeWindow.cursor)
    )
    e.state.statusMessage = "-- INSERT --"
  elif e.state.mode != EditorMode.Insert:
    return

  # Middle-click uses X11 PRIMARY selection (text selected by mouse),
  # not CLIPBOARD selection (Ctrl+C).
  let readResult = readFromPrimarySelectionSync(e.config.clipboard.tool)
  if readResult.isErr:
    return

  # Normalize CRLF / lone CR to LF (matching loadFile) before insert and the
  # cursor advance below, so embedded \r never corrupts line content.
  let pastedText = readResult.get().normalizeNewlines()
  if pastedText.len == 0:
    return

  let activeBuffer = e.activeBuffer()

  # In Insert mode, a transaction is already active. Use it directly
  # instead of starting a new one.
  let ownTransaction = not activeBuffer.inTransaction
  if ownTransaction:
    let transactionResult = activeBuffer.beginTransaction("Middle-click paste")
    if transactionResult.isErr:
      e.state.statusMessage = "Paste failed: " & transactionResult.error
      return

  var pos = e.cursor
  discard activeBuffer.insertText(pos, pastedText)

  # Calculate new cursor position after paste. Iterate by rune: cursor.column
  # is a rune index everywhere (insertTextWithNewlines/deleteChar), so byte
  # iteration would over-advance on multibyte text.
  var newLine = pos.line
  var newColumn = pos.column
  for r in pastedText.runes:
    if r == Rune('\n'):
      newLine += 1
      newColumn = 0
    else:
      newColumn += 1

  e.activeWindow.cursor.line = newLine
  e.activeWindow.cursor.column = newColumn

  if ownTransaction:
    discard activeBuffer.commitTransaction()

proc finalizeCurrentWindowForMouseJump(e: Editor) =
  ## Exit the current mode before a mouse click hands focus to another window.
  ## visualSelection and pendingOperator carry no buffer identity, and an open
  ## transaction is per-buffer, so any of them would misfire on the new buffer.
  let activeBuffer = e.activeBuffer()

  case e.state.mode
  of EditorMode.Insert, EditorMode.Replace:
    if activeBuffer.inTransaction:
      clearAutoIndentIfUnedited(activeBuffer, e.state)
      discard activeBuffer.commitTransaction()
    e.state.editState.insertModeStartPos = none(BufferPosition)
    e.state.editState.substituteContext = none(types.SubstituteContext)
    e.state.editState.replaceHistory = @[]
    e.state.editState.insertReplayCount = 0
    e.state.editState.insertReplayLineEntry = false
    e.state.editState.visualBlockInsertContext = none(types.VisualBlockInsertContext)
    let lineCharLen = activeBuffer.getLine(e.activeWindow.cursor.line).charLen
    adjustCursorAfterInsertExit(e.activeWindow.cursor, lineCharLen)
  of EditorMode.Visual, EditorMode.VisualLine, EditorMode.VisualBlock:
    e.state.visualSelection.active = false
  else:
    discard

  # Ctrl-o holds an open Insert transaction while state.mode is Normal.
  if e.state.insertNormalMode:
    if activeBuffer.inTransaction:
      clearAutoIndentIfUnedited(activeBuffer, e.state)
      discard activeBuffer.commitTransaction()
    e.state.insertNormalMode = false
    e.state.editState.insertModeStartPos = none(BufferPosition)

  e.state.editState.pendingOperator = none(PendingOperator)
  e.state.editState.pendingTextObject = none(PendingTextObject)
  e.state.pendingRegister = none(char)
  discard e.keyRouter.cancel()
  if e.state.macroState.waitingForRegister:
    e.state.macroState.waitingForRegister = false
    e.state.macroState.commandType = ""
    e.state.macroState.pendingCount = 0

  # state.mode aliases activeWindow.mode; the subsequent swap re-aliases to
  # the target window's own saved mode.
  e.state.previousMode = e.state.mode
  e.state.mode = EditorMode.Normal

proc handleMouseEvent(e: Editor, event: Event): bool =
  ## Handle mouse events for cursor movement
  ## Returns true if the event was handled, false otherwise
  if event.kind != EventKind.Mouse:
    return false
  if not e.config.standard.mouse:
    return false

  let mouse = event.mouse

  # Only handle left button, middle button press and wheel events
  if mouse.button notin {
    mouse_logic.MouseButton.Left, mouse_logic.MouseButton.Middle,
    mouse_logic.MouseButton.WheelUp, mouse_logic.MouseButton.WheelDown,
  }:
    return false
  if mouse.kind != celina.MouseEventKind.Press:
    return false

  # Handle wheel scroll events
  if mouse.button in {
    mouse_logic.MouseButton.WheelUp, mouse_logic.MouseButton.WheelDown
  }:
    const scrollLines = 3

    # Handle Filer mode scroll
    if e.state.mode == EditorMode.Filer and e.activeWindow.modeState.kind == mskFiler:
      let filerState = e.activeWindow.modeState.filer
      if filerState.entries.len > 0:
        if mouse.button == mouse_logic.MouseButton.WheelUp:
          filerState.selectedIndex = max(0, filerState.selectedIndex - scrollLines)
        else:
          filerState.selectedIndex =
            min(filerState.entries.len - 1, filerState.selectedIndex + scrollLines)
        # Adjust topLine to keep selectedIndex visible
        let viewportHeight = e.viewport.height
        if viewportHeight > 0:
          if filerState.selectedIndex < filerState.topLine:
            filerState.topLine = filerState.selectedIndex
          elif filerState.selectedIndex >= filerState.topLine + viewportHeight:
            filerState.topLine = filerState.selectedIndex - viewportHeight + 1
      return true

    # Handle text editing modes
    if e.state.mode in {
      EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualLine,
      EditorMode.VisualBlock, EditorMode.Replace,
    }:
      # Determine target window by mouse position
      var targetIdx = e.windowManager.activeWindowIndex
      if e.windowManager.windows.len > 1:
        for i, window in e.windowManager.windows:
          let vp = window.viewport
          if mouse.x >= vp.x and mouse.x < vp.x + vp.width and mouse.y >= vp.y and
              mouse.y < vp.y + vp.height:
            targetIdx = i
            break

      let window = e.windowManager.windows[targetIdx]
      let curLine = window.cursor.line
      let maxLine = window.buffer.len - 1
      let newLine =
        if mouse.button == mouse_logic.MouseButton.WheelUp:
          max(0, curLine - scrollLines)
        else:
          min(maxLine, curLine + scrollLines)

      if newLine != curLine:
        window.cursor = BufferPosition(line: newLine, column: window.cursor.column)
        # Clamp column to line length
        let lineLen = window.buffer[newLine].charLen
        if lineLen > 0:
          window.cursor.column = min(window.cursor.column, lineLen - 1)
        else:
          window.cursor.column = 0

        # Update viewport topLine to keep cursor visible
        let viewportHeight = window.viewport.height
        if viewportHeight > 0:
          if newLine < window.viewport.topLine:
            window.viewport.resetViewportTop(newLine)
          elif newLine >= window.viewport.topLine + viewportHeight:
            window.viewport.resetViewportTop(newLine - viewportHeight + 1)

      return true

    return true

  # Handle mouse click in text editing modes
  if e.state.mode in {
    EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualLine,
    EditorMode.VisualBlock, EditorMode.Replace,
  }:
    # Multiple windows mode
    if e.windowManager.windows.len > 1:
      # Check tab line click first
      if e.showTabLine:
        for i, window in e.windowManager.windows:
          let vp = window.viewport
          if mouse.y == vp.y and mouse.x >= vp.x and mouse.x < vp.x + vp.width:
            # Resolve this window's per-window tab list to TextBuffer refs.
            var buffersToShow: seq[TextBuffer] = @[]
            for id in window.bufferIds:
              let bufOpt = e.bufferById(id)
              if bufOpt.isSome:
                buffersToShow.add(bufOpt.get)
            if buffersToShow.len == 0:
              buffersToShow = @[window.buffer]
            let tabIdx =
              hitTestTabLine(buffersToShow, window.mode, vp.x, vp.width, mouse.x)
            if tabIdx >= 0:
              if i != e.windowManager.activeWindowIndex:
                e.finalizeCurrentWindowForMouseJump()
                e.windowManager.activeWindowIndex = i
                for j, w in e.windowManager.windows.mpairs:
                  w.active = (j == i)
                e.syncActiveWindow()
              e.switchToWindowBuffer(tabIdx)
              return true

      for i, window in e.windowManager.windows:
        let vp = window.viewport
        # Check if click is within this window's viewport
        if mouse.x >= vp.x and mouse.x < vp.x + vp.width and mouse.y >= vp.y and
            mouse.y < vp.y + vp.height:
          let
            lineNumOffset = e.calculateLineNumOffsetForMouse(window.buffer)
            sidebarWidth = e.calculateSidebarWidth(window.mode)
            scrollbarWidth = e.calculateScrollbarWidth(window.mode)
            # Each window has its own status line
            reservedLines = if e.showStatusLine: 1 else: 0
            posOpt = screenToBufferPosition(
              vp, window.buffer, mouse.x, mouse.y, lineNumOffset, sidebarWidth,
              reservedLines, e.lineWrap, e.tabStop, scrollbarWidth,
              window.wrapCountCache,
            )

          if posOpt.isNone:
            return false

          let pos = posOpt.get

          if i != e.windowManager.activeWindowIndex:
            e.finalizeCurrentWindowForMouseJump()
            e.windowManager.activeWindowIndex = i
            for j, w in e.windowManager.windows.mpairs:
              w.active = (j == i)
            e.syncActiveWindow()

          e.cursor = pos
          if mouse.button == mouse_logic.MouseButton.Middle:
            e.middleClickPaste()
          return true

      return false

    # Single window mode
    # Check tab line click first
    if e.showTabLine and mouse.y == 0:
      var buffersToShow: seq[TextBuffer] = @[]
      for id in e.activeWindow.bufferIds:
        let bufOpt = e.bufferById(id)
        if bufOpt.isSome:
          buffersToShow.add(bufOpt.get)
      if buffersToShow.len == 0:
        buffersToShow = @[e.activeBuffer()]
      let tabIdx =
        hitTestTabLine(buffersToShow, e.state.mode, 0, e.viewport.width, mouse.x)
      if tabIdx >= 0:
        e.switchToWindowBuffer(tabIdx)
        return true

    let
      activeBuffer = e.activeBuffer()
      lineNumOffset = e.calculateLineNumOffsetForMouse(activeBuffer)
      sidebarWidth = e.calculateSidebarWidth(e.activeWindow.mode)
      scrollbarWidth = e.calculateScrollbarWidth(e.activeWindow.mode)
      # Status line + command line (shared row)
      reservedLines = steadyBottomAreaHeight()
      # Account for tab line offset
      tabLineOffset = if e.showTabLine: TabLineHeight else: 0
      adjustedMouseY = mouse.y - tabLineOffset
      posOpt = screenToBufferPosition(
        e.viewport, activeBuffer, mouse.x, adjustedMouseY, lineNumOffset, sidebarWidth,
        reservedLines, e.lineWrap, e.tabStop, scrollbarWidth,
        e.activeWindow.wrapCountCache,
      )

    if posOpt.isNone:
      return false

    let pos = posOpt.get
    # e.cursor= sets both state.cursor and activeWindow.cursor
    e.cursor = pos
    if mouse.button == mouse_logic.MouseButton.Middle:
      e.middleClickPaste()
    return true

  # Handle mouse click in Filer mode
  if e.state.mode == EditorMode.Filer and e.activeWindow.modeState.kind == mskFiler:
    let filerState = e.activeWindow.modeState.filer
    let
      tabLineOffset = if e.showTabLine: TabLineHeight else: 0
      reservedLines = steadyBottomAreaHeight()
      adjustedMouseY = mouse.y - tabLineOffset

    # Ignore clicks on tab line or status/command line area
    if adjustedMouseY >= 0 and adjustedMouseY < e.viewport.height - reservedLines:
      let clickedIndex = filerState.topLine + adjustedMouseY
      if clickedIndex >= 0 and clickedIndex < filerState.entries.len:
        filerState.selectedIndex = clickedIndex
        return true

  return false

proc handleWindowCommand(e: Editor, keyCombo: KeyCombo): Option[bool] =
  ## Handle Ctrl-W window command second key (j/k/c).
  ## Returns some(true) if handled, some(false) if last window closed (quit),
  ## none if not a window command key.
  if e.state.pendingCommand == PendingWindowCmd:
    e.state.pendingCommand = PendingNone
    if not keyCombo.isSpecial:
      if keyCombo.char == "j":
        e.switchToPrevWindow
        return some(true)
      elif keyCombo.char == "k":
        e.switchToNextWindow
        return some(true)
      elif keyCombo.char == "c":
        let shouldQuit = e.closeWindow()
        if shouldQuit:
          return some(false)
        return some(true)
    return some(true) # Unknown window command, cancel

  # Check for Ctrl-w to enter window command mode
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and keyCombo.char == "w":
    e.state.pendingCommand = PendingWindowCmd
    return some(true)

  return none(bool)

proc prepareForInput(e: Editor, isKeyInput: bool) =
  ## Per-input setup: clear stale status, refresh input timestamp, cancel
  ## any in-flight scroll animation for key input.

  # Clear status message from previous event cycle:
  # messages persist for one render frame, then clear on next input)
  e.state.statusMessage = ""

  # Update last input time for auto backup idle detection
  e.updateInputTime()

  # Cancel smooth scroll animation on any key press
  if isKeyInput and e.state.windowDisplay.scrollAnimation.active:
    cancelScrollAnimation(e.state.windowDisplay.scrollAnimation)

proc prepareForEvent(e: Editor, event: Event) =
  ## Per-event setup for Celina events.
  e.prepareForInput(event.kind == EventKind.Key)

proc prepareForKeyCombo(e: Editor) =
  ## Per-input setup for frontend-neutral key handling.
  e.prepareForInput(true)

proc handleQuitEvent(e: Editor): bool =
  ## Handle Ctrl-C (Quit event from celina). Behaviour depends on the
  ## current mode/overlay: forward to Terminal PTY, cancel overlays, exit
  ## Insert-Normal, or transition file-edit modes back to Normal.

  # Terminal-Input mode: forward Ctrl-C to PTY as \x03
  if e.state.mode == EditorMode.Terminal:
    let activeWin = e.activeWindow
    if activeWin.modeState.kind == mskTerminal:
      let termState = activeWin.modeState.terminal
      if termState.subMode == tsmInput:
        termState.feedInput("\x03")
        return true

  # Search overlay: cancel search and exit overlay
  if e.state.isSearchOverlay:
    if e.state.input.search.incsearch:
      e.cursor = e.state.input.search.startPos
    e.state.exitOverlay()
    e.setMode(e.state.mode)
    # Insert-Normal mode (Ctrl-o): return to Insert after overlay cancel
    if e.state.insertNormalMode and e.state.mode == EditorMode.Normal:
      e.state.insertNormalMode = false
      e.setMode(EditorMode.Insert)
    return true

  # Command overlay: clear command line and exit overlay
  if e.state.isCommandOverlay:
    e.state.commandCompletionManager.cancelCompletion()
    e.cancelSubstitutePreview()
    e.state.exitOverlay()
    e.setMode(e.state.mode)
    # Insert-Normal mode (Ctrl-o): return to Insert after overlay cancel
    if e.state.insertNormalMode and e.state.mode == EditorMode.Normal:
      e.state.insertNormalMode = false
      e.setMode(EditorMode.Insert)
    return true

  if e.state.mode == EditorMode.Normal:
    # Insert-Normal mode (Ctrl-o): Ctrl-C cancels and stays in Normal mode
    if e.state.insertNormalMode:
      e.state.insertNormalMode = false
      let activeBuffer = e.activeBuffer()
      if activeBuffer.inTransaction:
        clearAutoIndentIfUnedited(activeBuffer, e.state)
        discard activeBuffer.commitTransaction()
      e.state.editState.insertModeStartPos = none(BufferPosition)
      e.state.editState.substituteContext = none(types.SubstituteContext)
      let lineCharLen = activeBuffer.getLine(e.activeWindow.cursor.line).charLen
      adjustCursorAfterInsertExit(e.activeWindow.cursor, lineCharLen)
      return true
    # Normal mode: show exit message like Vim
    e.state.statusMessage = "Type :qa and press <Enter> to exit"
  elif e.state.mode.isFileEditMode:
    # Other file edit modes (Insert, Visual, Replace, etc.): switch to Normal mode
    let activeBuffer = e.activeBuffer()

    # Commit transaction when leaving Insert or Replace mode
    if e.state.mode in {EditorMode.Insert, EditorMode.Replace}:
      if activeBuffer.inTransaction:
        clearAutoIndentIfUnedited(activeBuffer, e.state)
        discard activeBuffer.commitTransaction()
      # Clear insert mode tracking state
      e.state.editState.insertModeStartPos = none(BufferPosition)
      e.state.editState.substituteContext = none(types.SubstituteContext)
      e.state.editState.replaceHistory = @[]

    e.state.previousMode = e.state.mode
    e.setMode(EditorMode.Normal)

    # Adjust cursor: move one position left when exiting Insert mode
    let lineCharLen = activeBuffer.getLine(e.activeWindow.cursor.line).charLen
    adjustCursorAfterInsertExit(e.activeWindow.cursor, lineCharLen)

  return true

proc dismissTempMessagesKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## Dismiss temporary messages (e.g. :jumps output) on any key.
  ## Returns true when a message was dismissed (event consumed).
  if e.state.ui.tempMessages.len == 0:
    return false

  e.state.ui.tempMessages = @[]

  # If ":" was pressed, enter command overlay
  if not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char == ":":
    e.state.enterCommandOverlay()
  # Otherwise just dismiss and stay in current mode
  return true

proc recordOverlayKey(e: Editor, keyCombo: KeyCombo) =
  ## Append the overlay key to the active macro register. Overlay handlers
  ## do not record inline, so capture at the dispatcher entry instead.
  ## Suppressed during playback via `withPlaybackGuard` clearing `isRecording`.
  if not e.state.macroState.isRecording:
    return
  e.state.macroState.recordedKeys.add(keyComboToString(keyCombo))

proc handleOverlayKeyCombo(
    e: Editor, keyCombo: KeyCombo, recordKey = false
): Option[bool] =
  ## Dispatch overlay modes (Command, Search, Rename) and Debug mode.
  ## Returns some(result) if handled, none otherwise.
  if e.state.isCommandOverlay:
    if recordKey:
      e.recordOverlayKey(keyCombo)
    return some(e.handleCommandModeKeyCombo(keyCombo))
  if e.state.isSearchOverlay:
    if recordKey:
      e.recordOverlayKey(keyCombo)
    return some(e.handleSearchModeKeyCombo(keyCombo))
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
    # Escape - cancel picker
    if keyCombo.isSpecial and keyCombo.special == skEscape:
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
      if keyCombo.char.len == 1 and keyCombo.char[0] in '1' .. '9':
        let num = ord(keyCombo.char[0]) - ord('0')
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

proc handleEscapeCancellationKeyCombo(e: Editor, keyCombo: KeyCombo): bool =
  ## In Normal mode, Escape cancels pending multi-key state (macro register,
  ## operator, text object, register, key router, window command). Also tracks
  ## double-Escape to clear search highlight. Returns true when Escape was
  ## handled; non-Escape keys reset the Escape counter but are not consumed.
  if e.state.mode != EditorMode.Normal:
    return false

  # Handle Escape key to cancel pending multi-key commands
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    # Check if any pending state needs to be cancelled
    var cancelled = false

    # Cancel macro register waiting (q, @)
    if e.state.macroState.waitingForRegister:
      e.state.macroState.waitingForRegister = false
      e.state.macroState.commandType = ""
      e.state.macroState.pendingCount = 0
      cancelled = true

    # Cancel pending operator (d, c, y, etc.)
    if e.state.editState.pendingOperator.isSome:
      e.state.editState.pendingOperator = none(PendingOperator)
      cancelled = true

    # Cancel pending text object (i, a)
    if e.state.editState.pendingTextObject.isSome:
      e.state.editState.pendingTextObject = none(PendingTextObject)
      cancelled = true

    # Cancel pending register (")
    if e.state.pendingRegister.isSome:
      e.state.pendingRegister = none(char)
      cancelled = true

    # Cancel pending key binding sequence (built-in multi-key accumulator).
    # Runtime mapping accumulator is intentionally not cleared here; the
    # timeout path handles that. See `KeyRouter.cancel` for details.
    if e.keyRouter.cancel():
      cancelled = true

    # Cancel window command mode (Ctrl-w)
    if e.state.pendingCommand != PendingNone:
      e.state.pendingCommand = PendingNone
      cancelled = true

    if cancelled:
      e.state.statusMessage = ""
      return true

    # No pending state - handle double-Escape to clear search highlight
    if e.state.lastKeyWasEscape:
      # Second Escape press - clear highlight
      e.state.input.search.hlsearchTempDisabled = true
      e.state.lastKeyWasEscape = false
    else:
      # First Escape press - just mark it
      e.state.lastKeyWasEscape = true
    return true
  else:
    # Any other key resets the Escape counter
    e.state.lastKeyWasEscape = false
    return false

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
  if e.state.pendingCommand == PendingWindowCmd and keyCombo.isSpecial and
      keyCombo.special == skEscape:
    e.state.pendingCommand = PendingNone
    return some(true)

  return e.handleWindowCommand(keyCombo)

proc updateViewportReservedLines(e: Editor) =
  ## Recompute `state.windowDisplay.viewportReservedLines` from current
  ## status/tab line configuration and window layout. Status line and
  ## command line share the same row (command overlays status).
  let hasWindows =
    e.windowManager.windows.len > 0 and
    e.windowManager.activeWindowIndex < e.windowManager.windows.len

  let isBottomWindow =
    if hasWindows:
      # A window is a bottom window if its bottom edge is at the maximum bottom Y
      let
        maxBottomY = findMaxBottomY(e.windowManager.windows)
        windowBottomY = e.activeWindow.viewport.y + e.activeWindow.viewport.height
      windowBottomY == maxBottomY
    else:
      true

  # Steady reserve: motion scrolling is persistent geometry and must match the
  # scroll authority and screen cursor, not flap with a transient status message.
  e.state.windowDisplay.viewportReservedLines = e.steadyReservedLines(isBottomWindow)

  # Add tab line height if shown
  if e.showTabLine:
    e.state.windowDisplay.viewportReservedLines += TabLineHeight

proc syncCompletionOtherBuffers(e: Editor, activeBuffer: TextBuffer) =
  ## Populate completion manager's `otherBuffers` with all FileEditMode
  ## buffers except the active one.
  var otherBufs: seq[TextBuffer] = @[]
  for win in e.windowManager.windows:
    if win.mode.isFileEditMode and win.buffer != activeBuffer:
      otherBufs.add(win.buffer)
  e.handlerManager.insertHandler.completionManager.otherBuffers = otherBufs

proc handleKeyCombo*(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle one frontend-neutral key combination.
  ##
  ## GUI frontends can call this directly after translating their native key
  ## input into Moe's `KeyCombo` type. Terminal-specific events such as Quit,
  ## paste, and mouse input remain handled by `handleEvent`.
  e.prepareForKeyCombo()

  # Handle temporary messages (like :jumps output) - dismiss on any key
  if e.dismissTempMessagesKeyCombo(keyCombo):
    return true

  # Handle overlay modes (Command, Search, Rename) + Debug mode
  let overlayResult = e.handleOverlayKeyCombo(keyCombo, recordKey = true)
  if overlayResult.isSome:
    return overlayResult.get

  # Handle LSP popups (CodeLens picker, Hover popup); some keys fall through
  let popupResult = e.handlePopupKeyCombo(keyCombo)
  if popupResult.isSome:
    return popupResult.get

  # In Normal mode, Escape cancels pending multi-key state
  if e.handleEscapeCancellationKeyCombo(keyCombo):
    return true

  # Ctrl-W window commands for special/viewer modes
  let winResult = e.handleSpecialModeWindowCommandKeyCombo(keyCombo)
  if winResult.isSome:
    return winResult.get

  # Handle Recent File mode input (after Ctrl-W window commands)
  if e.state.mode == EditorMode.RecentFile:
    return e.handleRecentFileModeKeyCombo(keyCombo)

  # For other modes, use the unified handler manager with active buffer
  let activeBuffer = e.activeBuffer

  e.updateViewportReservedLines()
  e.syncCompletionOtherBuffers(activeBuffer)

  let outcome = e.handlerManager.runNestedKeyCombo(e, keyCombo)

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

proc handleEvent*(e: Editor, event: Event): bool =
  ## Main event handler using the new handler manager system
  if event.kind == EventKind.Key:
    let keyComboOpt = eventToKeyCombo(event)
    if keyComboOpt.isNone:
      e.prepareForKeyCombo()
      return true
    return e.handleKeyCombo(keyComboOpt.get)

  prepareForEvent(e, event)

  # Handle Ctrl-C (Quit event from celina)
  if event.kind == EventKind.Quit:
    return e.handleQuitEvent()

  # Handle mouse events first
  if event.kind == EventKind.Mouse:
    # Middle-click paste works regardless of mouse config since mouseCapture
    # is always enabled and would otherwise block the terminal's native paste.
    if event.mouse.button == mouse_logic.MouseButton.Middle and
        event.mouse.kind == celina.MouseEventKind.Press:
      e.middleClickPaste()
      return true
    discard e.handleMouseEvent(event)
    return true # Always continue running after mouse events

  # Handle paste events (Bracketed Paste Mode)
  if event.kind == EventKind.Paste:
    return e.handlePasteEvent(event)

  return true

proc hasPendingAsyncOperations*(e: Editor): bool =
  ## Check if there are pending async operations
  e.state.pending.shellCommand.len > 0 or e.state.pending.terminalCommand.len > 0 or
    e.state.pending.manPage.len > 0 or e.state.pending.background or
    e.state.pending.buildOnSave.path.len > 0 or e.state.pending.quickRun.cmd.len > 0 or
    e.state.pending.syntaxCheck.path.len > 0

type
  FrontendSuspendHook* = proc(): Future[void]
  FrontendHooks* = object
    ## Optional frontend callbacks for operations that need the host UI.
    suspend*: FrontendSuspendHook
    resume*: FrontendSuspendHook

  BuildInfo =
    tuple[path: string, language: int, customCmd: string, workspaceRoot: string]
  QuickRunInfo =
    tuple[cmd: string, args: seq[string], filePath: string, isTempFile: bool]
  SyntaxCheckInfo = tuple[path: string, language: int]

template withFrontendSuspend(frontend: FrontendHooks, body: untyped) =
  ## Suspend the owning frontend around synchronous terminal interaction.
  if not frontend.suspend.isNil:
    await frontend.suspend()
  try:
    body
  finally:
    if not frontend.resume.isNil:
      await frontend.resume()

proc runSyntaxCheckAsync(
    editor: Editor, info: SyntaxCheckInfo
): Future[void] {.async: (raises: []).} =
  ## Run syntax check process in background and apply results to buffer
  {.cast(gcsafe).}:
    try:
      let checkResult =
        await startBackgroundSyntaxCheck(info.path, SourceLanguage(info.language))
      if checkResult.isErr:
        editor.state.statusMessage = "Syntax check error: " & checkResult.error
      else:
        let checkProcess = checkResult.get
        editor.addRunningProcess(checkProcess.process)
        let output = await checkProcess.waitForAsync()
        editor.removeRunningProcess(checkProcess.process)
        let errors = parseNimCheckResult(info.path, output)
        # Apply markers to buffer
        let bufIdx = editor.findBufferByPath(info.path)
        if bufIdx >= 0:
          applySyntaxCheckToBuffer(editor.buffers[bufIdx], errors)
        # Store results for status message display
        editor.state.syntaxCheckResults = (path: info.path, errors: errors)
        let errorCount = errors.countIt(it.messageType == SyntaxCheckMessageType.error)
        let warnCount = errors.countIt(it.messageType == SyntaxCheckMessageType.warning)
        if errorCount > 0 or warnCount > 0:
          editor.state.statusMessage =
            "Syntax check: " & $errorCount & " error(s), " & $warnCount & " warning(s)"
        else:
          editor.state.statusMessage = "Syntax check: OK"
    except Exception as ex:
      editor.state.statusMessage = "Syntax check error: " & ex.msg

proc runBuildAsync(
    editor: Editor, info: BuildInfo
): Future[void] {.async: (raises: []).} =
  ## Run build process in background and display output when complete
  {.cast(gcsafe).}:
    try:
      let buildResult = await startBackgroundBuildOnSave(
        info.path, SourceLanguage(info.language), info.customCmd, info.workspaceRoot
      )
      if buildResult.isErr:
        editor.state.statusMessage = "Build error: " & buildResult.error
      else:
        let buildProcess = buildResult.get
        editor.addRunningProcess(buildProcess.process)
        let output = await buildProcess.waitForAsync()
        editor.removeRunningProcess(buildProcess.process)
        let outputContent = output.join("\n")
        let outputBuffer = newTextBuffer(outputContent)
        outputBuffer.readOnly = true
        let splitResult = editor.hsplitWithBuffer(outputBuffer)
        if splitResult.isErr:
          editor.state.statusMessage =
            "Failed to open output window: " & splitResult.error
        else:
          if editor.config.notification.screenNotifications and
              editor.config.notification.buildOnSaveScreenNotify:
            editor.notify("Build completed: " & info.path)
    except Exception as ex:
      editor.state.statusMessage = "Build error: " & ex.msg

proc runQuickRunAsync(
    editor: Editor, info: QuickRunInfo
): Future[void] {.async: (raises: []).} =
  ## Run QuickRun process in background and display output when complete
  {.cast(gcsafe).}:
    try:
      let prepared = QuickRunPrepareResult(
        command: BackgroundProcessCommand(cmd: info.cmd, args: info.args),
        filePath: info.filePath,
        isTempFile: info.isTempFile,
      )
      let quickRunResult = await startBackgroundQuickRun(prepared)
      if quickRunResult.isErr:
        editor.state.statusMessage = "QuickRun error: " & quickRunResult.error
      else:
        let qrProcess = quickRunResult.get
        # Track the full QuickRunProcess (not just its BackgroundProcess) so
        # editor exit/crash can also remove its temp files, not only kill the
        # process. See cleanupQuickRunProcesses.
        editor.addRunningQuickRun(qrProcess)
        let outputResult = await qrProcess.waitForResultAsync()
        editor.removeRunningQuickRun(qrProcess)
        if outputResult.isErr:
          editor.state.statusMessage = "QuickRun error: " & outputResult.error
        else:
          let output = outputResult.get
          let outputContent = output.join("\n")
          let outputBuffer = newTextBuffer(outputContent)
          outputBuffer.readOnly = true
          let splitResult = editor.hsplitWithBuffer(outputBuffer)
          if splitResult.isErr:
            editor.state.statusMessage =
              "Failed to open output window: " & splitResult.error
          else:
            if editor.config.notification.screenNotifications and
                editor.config.notification.quickRunScreenNotify:
              editor.notify("QuickRun completed: " & qrProcess.filePath)
    except Exception as ex:
      editor.state.statusMessage = "QuickRun error: " & ex.msg

proc handlePendingAsyncOperationsImpl(
    e: Editor, frontend: FrontendHooks
): Future[void] {.async: (raises: [Exception]).} =
  ## Handle pending async operations that require TUI suspend or background processing
  ## Called from the main event loop after handleEvent returns

  {.cast(gcsafe).}:
    # Open a queued terminal command (e.g. rust-analyzer run/debug single) as a
    # new terminal tab in the active window.
    if e.state.pending.terminalCommand.len > 0:
      let cmd = e.state.pending.terminalCommand
      e.state.pending.terminalCommand = ""
      e.enterTerminalInActiveWindow(cmd)

    # Handle shell command
    if e.state.pending.shellCommand.len > 0:
      let cmd = e.state.pending.shellCommand
      e.state.pending.shellCommand = ""
      # withFrontendSuspend wraps the body in try/finally so the TUI
      # resumes, even if execShellCmd/readLine raises (a missed resume leaves
      # the terminal in raw mode and destroys the screen).
      withFrontendSuspend(frontend):
        stdout.write("\e[H\e[2J") # Clear screen
        stdout.flushFile()
        let exitCode = execShellCmd(cmd)
        stdout.write("\n\nShell returned " & $exitCode & "\n")
        stdout.write("Press Enter to continue...")
        stdout.flushFile()
        discard stdin.readLine()

    # Handle man page display
    if e.state.pending.manPage.len > 0:
      let page = e.state.pending.manPage
      e.state.pending.manPage = ""
      withFrontendSuspend(frontend):
        stdout.write("\e[H\e[2J") # Clear screen
        stdout.flushFile()
        let exitCode = execShellCmd("man " & quoteShell(page))
        if exitCode != 0:
          stdout.write("man: " & page & " not found\n")
        stdout.write("\nPress Enter to continue...")
        stdout.flushFile()
        discard stdin.readLine()

    # Handle background suspend: send SIGTSTP to self so the shell registers moe
    # as a proper stopped job (visible in `jobs`, resumable via `fg`). Falls back
    # to a blocking readLine on non-POSIX platforms where SIGTSTP is unavailable.
    if e.state.pending.background:
      e.state.pending.background = false
      withFrontendSuspend(frontend):
        when defined(posix):
          discard posix.kill(posix.Pid(posix.getpid()), posix.SIGTSTP)
        else:
          stdout.write("\e[H\e[2J")
          stdout.write("moe suspended. Press Enter to return to moe...")
          stdout.flushFile()
          discard stdin.readLine()

    # Handle pending build - spawn as background task
    if e.state.pending.buildOnSave.path.len > 0:
      let buildInfo = e.state.pending.buildOnSave
      e.state.pending.buildOnSave =
        (path: "", language: 0, customCmd: "", workspaceRoot: "")
      asyncSpawn runBuildAsync(e, buildInfo)

    # Handle pending QuickRun - spawn as background task
    if e.state.pending.quickRun.cmd.len > 0:
      let qrInfo = e.state.pending.quickRun
      e.state.pending.quickRun = (cmd: "", args: @[], filePath: "", isTempFile: false)
      asyncSpawn runQuickRunAsync(e, qrInfo)

    # Handle pending syntax check - spawn as background task
    if e.state.pending.syntaxCheck.path.len > 0:
      let checkInfo = e.state.pending.syntaxCheck
      e.state.pending.syntaxCheck = (path: "", language: 0)
      asyncSpawn runSyntaxCheckAsync(e, checkInfo)

proc handlePendingAsyncOperations*(
    e: Editor, frontend: FrontendHooks = FrontendHooks()
): Future[void] {.async: (raises: [Exception]).} =
  ## Wrapper for handlePendingAsyncOperationsImpl with gcsafe cast
  {.cast(gcsafe).}:
    await handlePendingAsyncOperationsImpl(e, frontend)

proc handleKeyMappingTimeout*(e: Editor): bool =
  ## Called when the key mapping timeout fires.
  ## Matching is delegated to `KeyRouter.flushTimeout`; this proc only chooses
  ## the dispatch mode (base vs Command overlay) and executes the plan.
  ## Command overlay and base mode use different executors (the former replays
  ## via `handleCommandModeKeyCombo` and historically does not honour
  ## rmkCommand; the latter uses `executeCommandDirect` / `playbackMacro` /
  ## `handleKeyCombo`).
  ## Returns true to continue running, false to quit.

  let inCommandOverlay = e.state.isCommandOverlay
  let routerMode = if inCommandOverlay: EditorMode.Command else: e.state.mode

  let route = e.keyRouter.flushTimeout(routerMode)
  var shouldContinue = true

  case route.kind
  of rrCancelled:
    # `flushTimeout` returns rrCancelled when the accumulator was already
    # empty; nothing to do, do not request a redraw.
    return true
  of rrUnhandled, rrWaiting, rrCommand:
    # `flushTimeout` never returns these variants; guard for exhaustiveness.
    return true
  of rrExecuteRuntimeCommand:
    # `mappingsFor(Command)` filters rmkCommand out, so `flushTimeout(Command)`
    # cannot return this variant. If the invariant is ever broken, prefer a
    # loud failure over a silent drop that would swallow the mapping.
    doAssert not inCommandOverlay,
      "flushTimeout(Command) returned rrExecuteRuntimeCommand; " &
        "mappingsFor(Command) must filter rmkCommand out (see key_router.mappingsFor)"
    let cmdResult = e.handlerManager.executeCommandDirect(route.commandName)
    if cmdResult.isSome:
      # Route through `processResult` so bridge-produced `hrExecCommand`
      # (and other non-trivial kinds) are dispatched the same way as in the
      # main feedKey path. Without this, `K = "bdelete"` would silently no-op
      # when fired via timeout flush.
      shouldContinue = e.processResult(cmdResult.get, e.activeBuffer)
  of rrExecuteRuntimeKeySequence:
    if inCommandOverlay:
      # Command overlay replays through a different dispatcher
      # (handleCommandModeKeyCombo) that has no mapping-expansion precheck, so it
      # stays non-recursive regardless of noremap (known limitation).
      e.keyRouter.withReplay:
        for k in route.targetKeys:
          if not e.handleCommandModeKeyCombo(k):
            shouldContinue = false
            break
    else:
      # Base mode: honour noremap so a timeout-fired mapping expands the same way
      # as an immediate match (recursive for :map, verbatim for :noremap).
      let outcome =
        e.handlerManager.replayRuntimeKeySequence(e, route.targetKeys, route.noremap)
      if outcome == roQuit:
        shouldContinue = false
  of rrUnhandledBatch:
    if inCommandOverlay:
      e.keyRouter.withReplay:
        for k in route.keys:
          if not e.handleCommandModeKeyCombo(k):
            shouldContinue = false
            break
    else:
      e.keyRouter.withReplay:
        for k in route.keys:
          case e.handlerManager.runNestedKeyCombo(e, k)
          of roContinue:
            discard
          of roQuit:
            shouldContinue = false
            break
          of roAbort:
            break

  return shouldContinue
