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

import std/[options, os, strutils, sequtils, tables, monotimes, unicode]

import pkg/[celina, results, chronos]
from pkg/celina/core/mouse_logic import MouseButton

import
  editor, key_bindings, modes, buffer, logger, types, motion, search_utils, filer,
  quick_run_utils, help_viewer, buffer_manager, backup_manager, backup, diff_viewer,
  command_completion, build, render_utils, debug_viewer, config_loader,
  documentsymbol_viewer, message_log, command_line, color, theme, tab_line
import command_handlers/handler_manager

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

proc getBufferInfos(e: Editor): seq[BufferInfo] =
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

## NOTE: While in Search Mode:
## - Character input: Add to searchText, trigger performIncrementalSearch (if enabled)
## - Backspace: Remove from searchText, trigger performIncrementalSearch (if enabled)
## - Enter: Save search, execute if needed, return to Normal mode
## - Escape: Cancel search, restore cursor if incsearch, return to previous mode

proc updateViewportForCursor(e: Editor, pos: BufferPosition) =
  ## Update viewport to follow cursor position
  ## Common helper to avoid code duplication in search operations
  let
    activeBuffer = e.activeBuffer()
    lineCount = activeBuffer.len
    cursorPos = CursorPosition(x: pos.column, y: pos.line)
    lineNumOffset = calculateViewportOffset(
      activeBuffer, e.state.display.showLineNumbers, e.state.display.showSidebar
    )

  e.handlerManager.motionController.viewportManager.updateViewport(
    cursorPos, lineCount, e.state.display.showStatusLine, e.state.viewportReservedLines,
    e.state.display.lineWrap, activeBuffer, lineNumOffset, e.state.display.tabStop,
  )

proc processSaveAndQuitResult(e: Editor, r: HandlerResult): bool =
  ## Process hrSaveAndQuit: save file and return false (quit) on success,
  ## true (continue) on failure.
  let saveResult = e.saveFile(r.saveAndQuitFilename, r.forceQuitAfterSave)
  if saveResult.isErr:
    logError("handler", "Save and quit failed: " & saveResult.error)
    e.state.setStatusMessage("Error: " & saveResult.error)
    return true
  else:
    logInfo("handler", "File saved, quitting editor")
    return false

proc processGotoLineResult(e: Editor, r: HandlerResult, activeBuffer: TextBuffer) =
  ## Process hrGotoLine: move cursor to the specified line number.
  let lineNum = r.lineNumber
  if lineNum > 0 and lineNum <= activeBuffer.len:
    e.activeWindow.cursor.line = lineNum - 1 # Convert to 0-based
    e.activeWindow.cursor.column = 0
    e.updateViewportForCursor(e.cursor)

proc executeSearchFromCurrentPosition(e: Editor): bool =
  ## Execute search from current position (used when incsearch is disabled)
  ##
  ## This is called when:
  ## - Enter is pressed in Search mode with incsearch disabled
  ##
  ## Returns: true if search was successful, false otherwise
  ##
  ## Side effects:
  ## - Updates cursor position if match found
  ## - Updates viewport to follow cursor
  ## - Sets status message (success or failure)
  ## - Sets needsFullRedraw flag
  let shouldIgnoreCase = shouldIgnoreCase(
    e.state.search.text, e.state.search.ignorecase, e.state.search.smartcase
  )

  let activeBuffer = e.activeBuffer()
  let searchResult =
    if e.state.search.direction == Forward:
      activeBuffer.findNext(e.state.search.text, e.cursor, shouldIgnoreCase)
    else:
      activeBuffer.findPrev(e.state.search.text, e.cursor, shouldIgnoreCase)

  if searchResult.isSome:
    let pos = searchResult.get
    e.cursor = pos
    e.updateViewportForCursor(pos)
    e.state.setStatusMessage("Found: " & e.state.search.text)
    e.state.needsFullRedraw = true
    return true
  else:
    e.state.setStatusMessage("Pattern not found: " & e.state.search.text)
    return false

proc finalizeSearch(e: Editor) =
  ## Finalize search and return to Normal mode
  ##
  ## Called when: Enter is pressed in Search mode
  ##
  ## Behavior:
  ## - If incsearch enabled: Cursor already at match, just update viewport
  ## - If incsearch disabled: Execute search now from current position
  ## - Save searchText to lastSearchText for n/N commands
  ## - Re-enable search highlight (hlsearch)
  ## - Transition to Normal mode
  ## - Clear searchText buffer
  if e.state.search.text.len > 0:
    # Save search text for n/N commands
    e.state.search.lastText = e.state.search.text
    # Re-enable highlight for new search
    e.state.search.hlsearchTempDisabled = false
    # Reset whole word mode (/ and ? are substring searches)
    e.state.search.wholeWord = false

    # Add to search history (avoid duplicates)
    # Remove if already exists in history
    let searchTextCopy = e.state.search.text
    for i in countdown(e.state.search.history.high, 0):
      if e.state.search.history[i] == searchTextCopy:
        e.state.search.history.delete(i)

    # Add to beginning of history (most recent first)
    e.state.search.history.insert(searchTextCopy, 0)

    # Limit history size to configured limit
    let historyLimit = e.config.persist.searchHistoryLimit
    if e.state.search.history.len > historyLimit:
      e.state.search.history.setLen(historyLimit)

    # If incsearch is enabled, cursor is already at the found position
    if e.state.search.incsearch:
      e.updateViewportForCursor(e.cursor)
      e.state.needsFullRedraw = true
    else:
      # If incsearch is disabled, perform search now
      discard e.executeSearchFromCurrentPosition()

    # Sync search query to help viewer state if in Help mode
    if e.state.mode == EditorMode.Help:
      let window = e.activeWindow
      if window.helpViewerState.isSome:
        let helpState = window.helpViewerState.get
        helpState.setSearchQuery(e.state.search.text)
        discard helpState.searchFirst()

  # Exit overlay and return to base mode
  # The base mode (Normal, LogViewer, Filer, etc.) is preserved
  e.state.exitOverlay()
  e.setMode(e.state.mode) # Sync window mode

proc cancelSearch(e: Editor) =
  ## Cancel search and return to base mode
  ##
  ## Called when: Escape is pressed in Search mode
  ##
  ## Behavior:
  ## - If incsearch enabled: Restore cursor to original position (searchStartPos)
  ## - Exit overlay and return to base mode
  ## - Clear searchText buffer
  ## - Does NOT save to lastSearchText (search was cancelled)
  if e.state.search.incsearch:
    e.cursor = e.state.search.startPos
  # Exit overlay and restore base mode
  e.state.exitOverlay()
  e.setMode(e.state.mode) # Sync window mode

proc performIncrementalSearch(e: Editor) =
  ## Perform incremental search and update cursor position dynamically
  ##
  ## Called when:
  ## - Character is added to searchText (handleSearchCharacterInput)
  ## - Character is removed from searchText (handleSearchBackspace)
  ##
  ## Behavior:
  ## - Only executes if incsearch is enabled AND searchText is not empty
  ## - Searches from original start position (searchStartPos), not current cursor
  ## - Updates cursor position to match if found
  ## - Restores cursor to start position if not found
  ## - Updates viewport to follow cursor
  ## - Sets appropriate status message
  ##
  ## This provides real-time feedback as the user types their search query.
  if not e.state.search.incsearch or e.state.search.text.len == 0:
    return

  # Apply smartcase logic to determine if we should ignore case
  let shouldIgnoreCase = shouldIgnoreCase(
    e.state.search.text, e.state.search.ignorecase, e.state.search.smartcase
  )

  # Perform search from the original search start position (not current cursor!)
  let activeBuffer = e.activeBuffer()
  let searchResult =
    if e.state.search.direction == Forward:
      activeBuffer.findNext(
        e.state.search.text, e.state.search.startPos, shouldIgnoreCase
      )
    else:
      activeBuffer.findPrev(
        e.state.search.text, e.state.search.startPos, shouldIgnoreCase
      )

  if searchResult.isSome:
    let pos = searchResult.get
    e.cursor = pos

    # Update viewport to follow cursor
    e.updateViewportForCursor(pos)

    e.state.setStatusMessage("Found: " & e.state.search.text)
    e.state.needsFullRedraw = true
  else:
    # No match found, restore to start position
    e.cursor = e.state.search.startPos
    e.state.setStatusMessage("Pattern not found: " & e.state.search.text)

proc handleSearchCharacterInput(e: Editor, ch: string) =
  ## Handle character input in Search mode
  ##
  ## Called when: Any printable character is typed
  ##
  ## Behavior:
  ## - Append character to searchText
  ## - If incsearch enabled: Trigger incremental search
  ## - Always trigger redraw to update search highlight
  e.state.search.text.add(ch)
  e.performIncrementalSearch()
  e.state.needsFullRedraw = true

proc handleSearchBackspace(e: Editor) =
  ## Handle Backspace key in Search mode
  ##
  ## Called when: Backspace is pressed
  ##
  ## Behavior:
  ## - Remove last character from searchText (if any)
  ## - If incsearch enabled: Trigger incremental search with updated text
  ## - Always trigger redraw to update search highlight
  if e.state.search.text.len > 0:
    e.state.search.text =
      e.state.search.text.runeSubStr(0, e.state.search.text.runeLen - 1)
    e.performIncrementalSearch()
  e.state.needsFullRedraw = true

proc updateSubstitutePreviewIfNeeded(e: Editor) =
  ## Update or cancel the live substitute preview based on the current command
  ## text. Call after any edit to commandText (backspace, delete, char input).
  if e.state.commandText.contains("s/"):
    let pattern = extractSubstitutePattern(e.state.commandText)
    let (replacement, hasReplacement) =
      extractSubstituteReplacement(e.state.commandText)
    let flags = extractSubstituteFlags(e.state.commandText)
    let isGlobal = "g" in flags
    if hasReplacement and pattern.len > 0 and e.config.highlight.replaceText:
      if not e.state.substitutePreview.isActive:
        e.startSubstitutePreview()
      e.updateSubstitutePreview(pattern, replacement, isGlobal)
    elif e.state.substitutePreview.isActive:
      e.cancelSubstitutePreview()
    else:
      e.state.needsFullRedraw = true

proc enterFilerInActiveWindow(e: Editor, path: string) =
  ## Switch the active window to Filer mode with the given directory path.
  e.setMode(EditorMode.Filer)
  let activeWin = e.activeWindow
  activeWin.mode = EditorMode.Filer
  let filerState = newFilerState(path)
  filerState.originalBuffer = activeWin.buffer
  activeWin.filerState = some(filerState)
  activeWin.buffer = filerState.createFilerTextBuffer(e.config.filer.showIcons)
  activeWin.cursor = BufferPosition(line: 0, column: 0)
  activeWin.viewport.topLine = 0
  activeWin.viewport.leftColumn = 0

proc handleCommandModeEvent(e: Editor, event: Event): bool =
  ## Handle Command mode events (special handling for text input)
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  let keyCombo = keyComboOpt.get

  # Handle Escape to exit Command mode and return to previous (base) mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.state.commandCompletionManager.cancelCompletion()
    # Cancel substitute preview and restore original content
    e.cancelSubstitutePreview()
    # Exit overlay and restore base mode
    e.state.exitOverlay()
    e.setMode(e.state.mode) # Sync window mode
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
        e.state.commandCursor = selected.len
        return false
      of cmFilePath:
        # Use original directory prefix (saved when completion started)
        let newArg = mgr.originalDirPrefix & selected
        e.state.commandText = ":" & mgr.baseCommand & " " & newArg
        e.state.commandCursor = mgr.baseCommand.len + 1 + newArg.len
        # Return true if directory selected (ends with /)
        return selected.endsWith("/")
      of cmSetOption:
        # Replace only the argument part
        let (cmd, _) = parseCommandLine(e.state.commandText)
        e.state.commandText = ":" & cmd & " " & selected
        e.state.commandCursor = cmd.len + 1 + selected.len
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
      # Check if it's a no-argument command that should execute immediately
      let shouldExecuteNow =
        mgr.mode == cmCommand and
        e.commandLineParser.isNoArgumentAction(mgr.getSelectedCommand())
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
    if e.state.substitutePreview.isActive:
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
          e.state.setStatusMessage("QuickRun error: " & prepareResult.error)
          logError("handler", "QuickRun prepare failed: " & prepareResult.error)
        else:
          let prepared = prepareResult.get
          e.state.pendingQuickRun = (
            cmd: prepared.command.cmd,
            args: prepared.command.args,
            filePath: prepared.filePath,
            isTempFile: prepared.isTempFile,
          )
          if e.config.notification.screenNotifications and
              e.config.notification.quickRunScreenNotify:
            e.state.setStatusMessage(quickRunStartupMessage(prepared.filePath))
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)

      var overlayHandled = false

      case r.kind
      of hrQuit:
        return false # Signal app should quit
      of hrCloseWindow:
        # Handle window close - may also quit if last window
        let activeWin = e.activeWindow
        # Save buffer ref before clearModeState restores originalBuffer
        let splitBuf = activeWin.buffer
        activeWin.clearModeState(e.state.mode)
        # For special modes with split windows, remove the temporary buffer
        if e.state.mode in {
          EditorMode.LogViewer, EditorMode.BackupManager, EditorMode.DiffViewer,
          EditorMode.Debug, EditorMode.Config, EditorMode.RecentFile,
        }:
          if e.windowManager.windows.len > 1:
            let idx = e.buffers.find(splitBuf)
            if idx >= 0:
              e.buffers.delete(idx)
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
        let filerPath =
          if r.vsplitFilename.isSome and dirExists(r.vsplitFilename.get):
            some(absolutePath(r.vsplitFilename.get))
          else:
            none(string)
        let splitFilename =
          if filerPath.isSome:
            none(string)
          else:
            r.vsplitFilename
        let splitResult = e.vsplit(splitFilename)
        if splitResult.isErr:
          logError("handler", "Vertical split failed: " & splitResult.error)
          e.state.setStatusMessage("Error: " & splitResult.error)
        elif filerPath.isSome:
          e.enterFilerInActiveWindow(filerPath.get)
      of hrHSplit:
        # Handle horizontal split
        let filerPath =
          if r.hsplitFilename.isSome and dirExists(r.hsplitFilename.get):
            some(absolutePath(r.hsplitFilename.get))
          else:
            none(string)
        let splitFilename =
          if filerPath.isSome:
            none(string)
          else:
            r.hsplitFilename
        let splitResult = e.hsplit(splitFilename)
        if splitResult.isErr:
          logError("handler", "Horizontal split failed: " & splitResult.error)
          e.state.setStatusMessage("Error: " & splitResult.error)
        elif filerPath.isSome:
          e.enterFilerInActiveWindow(filerPath.get)
      of hrEnew:
        # Handle enew (create new empty buffer)
        let enewResult = e.enew()
        if enewResult.isErr:
          logError("handler", "Enew failed: " & enewResult.error)
          e.state.setStatusMessage("Error: " & enewResult.error)
      of hrNew:
        # Handle new (create new empty buffer in horizontal split)
        let newResult = e.new()
        if newResult.isErr:
          logError("handler", "New failed: " & newResult.error)
          e.state.setStatusMessage("Error: " & newResult.error)
      of hrVnew:
        # Handle vnew (create new empty buffer in vertical split)
        let vnewResult = e.vnew()
        if vnewResult.isErr:
          logError("handler", "Vnew failed: " & vnewResult.error)
          e.state.setStatusMessage("Error: " & vnewResult.error)
      of hrEdit:
        # Handle edit (open file in current window)
        let editResult = e.editFile(r.editFilename)
        if editResult.isErr:
          logError("handler", "Edit failed: " & editResult.error)
          e.state.setStatusMessage("Error: " & editResult.error)
        else:
          e.state.setStatusMessage("Opened: " & r.editFilename)
      of hrSetBoolOption:
        # Handle boolean option setting
        let opt = r.boolOption
        let val = r.boolValue
        case opt
        of bsoNumber:
          e.config.standard.number = val
          e.state.display.showLineNumbers = val
          e.state.setStatusMessage("number = " & $val)
        of bsoCursorLine:
          e.config.highlight.currentLine = val
          e.state.display.showCursorLine = val
          e.state.setStatusMessage("cursorline = " & $val)
        of bsoStatusLine:
          e.config.standard.statusLine = val
          e.state.display.showStatusLine = val
          e.state.setStatusMessage("statusline = " & $val)
        of bsoSyntax:
          e.config.standard.syntax = val
          e.state.display.showSyntax = val
          e.state.setStatusMessage("syntax = " & $val)
        of bsoIndentationLines:
          e.config.standard.indentationLines = val
          e.state.display.showIndentationLines = val
          e.state.setStatusMessage("indentationlines = " & $val)
        of bsoAutoIndent:
          e.config.standard.autoIndent = val
          e.state.display.autoIndent = val
          e.state.setStatusMessage("autoindent = " & $val)
        of bsoAutoCloseParen:
          e.config.standard.autoCloseParen = val
          e.state.display.autoCloseParen = val
          e.state.setStatusMessage("autocloseparen = " & $val)
        of bsoAutoDeleteParen:
          e.config.standard.autoDeleteParen = val
          e.state.display.autoDeleteParen = val
          e.state.setStatusMessage("autodeleteparen = " & $val)
        of bsoClipboard:
          e.config.clipboard.enable = val
          e.state.setStatusMessage("clipboard = " & $val)
        of bsoSmoothScroll:
          e.config.smoothScroll.enable = val
          e.state.setStatusMessage("smoothscroll = " & $val)
        of bsoLiveReloadOfConf:
          e.config.standard.liveReloadOfConf = val
          e.state.setStatusMessage("livereload = " & $val)
        of bsoShowIcons:
          e.config.filer.showIcons = val
          e.state.setStatusMessage("icon = " & $val)
        of bsoHighlightCurrentLine:
          e.config.highlight.currentLine = val
          e.state.display.showCursorLine = val
          e.state.setStatusMessage("highlightcurrentline = " & $val)
        of bsoHighlightCurrentWord:
          e.config.highlight.currentWord = val
          e.state.setStatusMessage("highlightcurrentword = " & $val)
        of bsoHighlightFullWidthSpace:
          e.config.highlight.fullWidthSpace = val
          e.state.setStatusMessage("highlightfullspace = " & $val)
        of bsoHighlightPairOfParen:
          e.config.highlight.pairOfParen = val
          e.state.setStatusMessage("highlightparen = " & $val)
        of bsoMultipleStatusLine:
          e.setMultiStatusLine(val)
        of bsoIgnoreCase:
          e.state.search.ignorecase = val
          e.state.setStatusMessage("ignorecase = " & $val)
        of bsoSmartCase:
          e.state.search.smartcase = val
          e.state.setStatusMessage("smartcase = " & $val)
        of bsoIncSearch:
          e.state.search.incsearch = val
          e.state.setStatusMessage("incsearch = " & $val)
        of bsoHlSearch:
          e.state.search.hlsearch = val
          e.state.setStatusMessage("hlsearch = " & $val)
        of bsoBuildOnSave:
          e.config.buildOnSave.enable = val
          e.state.setStatusMessage("buildonsave = " & $val)
        of bsoShowGitInactive:
          e.config.statusLine.showGitInactive = val
          e.state.setStatusMessage("showgitinactive = " & $val)
        of bsoLineWrap:
          e.config.standard.lineWrap = val
          e.setLineWrap(val)
          e.state.setStatusMessage("wrap = " & $val)
        e.state.needsFullRedraw = true
      of hrSetIntOption:
        # Handle integer option setting
        let opt = r.intOption
        let val = r.intValue
        case opt
        of isoTabStop:
          e.config.standard.tabStop = val
          e.state.display.tabStop = val
          e.state.setStatusMessage("tabstop = " & $val)
        e.state.needsFullRedraw = true
      of hrSetFloatOption:
        # Handle float option setting
        let opt = r.floatOption
        let val = r.floatValue
        case opt
        of fsoScrollFriction:
          e.config.smoothScroll.friction = val
          e.state.setStatusMessage("scrollfriction = " & $val)
        of fsoScrollAirDrag:
          e.config.smoothScroll.airDrag = val
          e.state.setStatusMessage("scrollairdrag = " & $val)
        e.state.needsFullRedraw = true
      of hrClearSearchHighlight:
        # Handle clear search highlight (:noh)
        e.state.search.hlsearch = false
        e.state.needsFullRedraw = true
      of hrShellCommand:
        # Set pending shell command to be executed by handleEventAsync
        e.state.pendingShellCommand = r.shellCommand
      of hrMan:
        # Set pending man page to be executed by handleEventAsync
        e.state.pendingManPage = r.hrManPage
      of hrBackground:
        # Set pending background flag to be handled by handleEventAsync
        e.state.pendingBackground = true
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
              e.state.setStatusMessage("Failed to backup config: " & ex.msg)
              logError("config", "Failed to backup config: " & ex.msg)

          if backupOk:
            let saveResult = saveConfig(e.config)
            if saveResult.isOk:
              e.state.setStatusMessage("Config saved: " & configPath)
              logInfo("config", "Config saved: " & configPath)
            else:
              e.state.setStatusMessage("Failed to save config: " & saveResult.error)
              logError("config", "Failed to save config: " & saveResult.error)
        else:
          # Handle file save
          let saveResult = e.saveFile(r.saveFilename, r.forceSave)
          if saveResult.isErr:
            logError("handler", "Save command failed: " & saveResult.error)
            e.state.setStatusMessage("Error: " & saveResult.error)
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
              e.state.setStatusMessage("Saved: " & savedPath)

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
              e.state.pendingBuildOnSave = (
                path: savedPath,
                language: activeBuffer.language.ord,
                customCmd: customCmd,
                workspaceRoot: workspaceRoot,
              )
              # Build on save screen notification (controlled by config)
              if e.config.notification.screenNotifications and
                  e.config.notification.buildOnSaveScreenNotify:
                e.state.setStatusMessage("Building: " & savedPath)

            # Syntax check on save if enabled (only for supported languages)
            if e.config.syntaxChecker.enable and
                syntaxCheckCommand(savedPath, activeBuffer.language).isOk:
              e.state.pendingSyntaxCheck =
                (path: savedPath, language: activeBuffer.language.ord)
      of hrSaveAndQuit:
        return e.processSaveAndQuitResult(r)
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
        # Handle buffer delete (close window)
        let shouldQuit = e.closeWindow()
        if shouldQuit:
          # Last buffer deleted, create a new empty buffer instead of quitting
          let enewResult = e.enew()
          if enewResult.isErr:
            logError("handler", "Enew failed after buffer delete: " & enewResult.error)
            e.state.setStatusMessage("Error: " & enewResult.error)
      of hrStripWhitespace:
        # Handle strip trailing whitespace
        let count = r.strippedLineCount
        if count > 0:
          e.state.setStatusMessage(
            "Stripped trailing whitespace from " & $count & " lines"
          )
          e.state.needsFullRedraw = true
        else:
          e.state.setStatusMessage("No trailing whitespace found")
      of hrQuickRun:
        overlayHandled = true
        if not quickRunHandled:
          # Prepare QuickRun (sync) and set pending for async execution
          let prepareResult = prepareQuickRun(activeBuffer, e.config)
          if prepareResult.isErr:
            e.state.setStatusMessage("QuickRun error: " & prepareResult.error)
            logError("handler", "QuickRun prepare failed: " & prepareResult.error)
          else:
            let prepared = prepareResult.get
            e.state.pendingQuickRun = (
              cmd: prepared.command.cmd,
              args: prepared.command.args,
              filePath: prepared.filePath,
              isTempFile: prepared.isTempFile,
            )
            # QuickRun screen notification (controlled by config)
            if e.config.notification.screenNotifications and
                e.config.notification.quickRunScreenNotify:
              e.state.setStatusMessage(quickRunStartupMessage(prepared.filePath))
          # Return to Normal mode - exit overlay first
          e.state.exitOverlay()
          e.setMode(EditorMode.Normal)
      of hrBuild:
        overlayHandled = true
        # Handle Build command
        let filePath =
          if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: ""
        if filePath.len == 0:
          e.state.setStatusMessage("Build error: File not saved")
          logError("handler", "Build failed: No file path")
        else:
          # Set pending build info for async processing
          e.state.pendingBuildOnSave = (
            path: filePath,
            language: activeBuffer.language.ord,
            customCmd: "",
            workspaceRoot: parentDir(filePath),
          )
          e.state.setStatusMessage("Building: " & filePath)
        # Return to Normal mode - exit overlay first
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrSubstitute:
        overlayHandled = true
        # Handle substitute result - display count
        let count = r.hrSubstituteCount
        e.state.setStatusMessage(
          $count & " substitution" & (if count == 1: "" else: "s")
        )
        e.state.needsFullRedraw = true
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
          e.state.setStatusMessage("Failed to open log: " & splitResult.error)
        else:
          e.setMode(EditorMode.LogViewer)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.LogViewer
          activeWin.logViewerState = some(newLogViewerState(lckEditor))
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
          e.state.setStatusMessage("Failed to open LSP log: " & splitResult.error)
        else:
          e.setMode(EditorMode.LogViewer)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.LogViewer
          activeWin.logViewerState = some(newLogViewerState(lckLsp))
      of hrEnterHelpViewer:
        overlayHandled = true
        # Enter help viewer mode - save base mode, exit overlay
        let baseModeBeforeOverlay = e.state.baseMode
        e.state.exitOverlay()
        e.state.previousMode = baseModeBeforeOverlay
        e.setMode(EditorMode.Help)
        let activeWin = e.activeWindow
        activeWin.mode = EditorMode.Help
        let helpState = newHelpViewerState()
        helpState.originalBuffer = activeWin.buffer
        activeWin.buffer = helpState.createHelpTextBuffer()
        activeWin.cursor = BufferPosition(line: 0, column: 0)
        activeWin.viewport.topLine = 0
        activeWin.viewport.leftColumn = 0
        activeWin.helpViewerState = some(helpState)
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
        bmState.originalBuffer = activeWin.buffer
        activeWin.buffer = bmState.createBufferManagerTextBuffer()
        activeWin.cursor = BufferPosition(line: 0, column: 0)
        activeWin.viewport.topLine = 0
        activeWin.viewport.leftColumn = 0
        activeWin.bufferManagerState = some(bmState)
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
          e.state.setStatusMessage(
            "Failed to open backup manager: " & splitResult.error
          )
        else:
          let baseModeBeforeOverlay = e.state.baseMode
          e.state.exitOverlay()
          e.state.previousMode = baseModeBeforeOverlay
          e.setMode(EditorMode.BackupManager)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.BackupManager
          activeWin.backupManagerState = some(bkState)
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
            e.buffers.find(window.buffer),
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
          e.state.display.showSidebar, e.state.display.lineWrap,
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
          e.state.setStatusMessage("Failed to open debug: " & splitResult.error)
        else:
          e.state.setStatusMessage("Debug info (auto-refresh)")
          # Store debug buffer reference for auto-refresh
          e.state.debugBuffer = debugBuffer
          e.state.timing.lastDebugUpdate = getMonoTime()
          if e.state.timing.debugUpdateInterval == 0:
            e.state.timing.debugUpdateInterval = 500 # Default: 500ms
          e.activeWindow.debugViewerState = some(debugState)
          # Enter debug mode
          e.state.exitOverlay()
          e.state.previousMode = e.state.baseMode
          e.setMode(EditorMode.Debug)
      of hrJumpList:
        overlayHandled = true
        # Handle jump list command (:ju, :jump)
        # Display jump list temporarily like Vim using tempMessages
        if e.state.jumpList.len == 0:
          e.state.setStatusMessage("Jump list is empty")
        else:
          e.state.tempMessages = @[]
          e.state.tempMessages.add(" jump  line  col  file")
          for i, pos in e.state.jumpList:
            let marker = if i == e.state.jumpListIndex: ">" else: " "
            let jumpNum = e.state.jumpList.len - i
            let lineNum = pos.line + 1 # 1-based for display
            let colNum = pos.column + 1 # 1-based for display
            # Get file name from buffer index
            let fileName =
              if pos.bufferIndex >= 0 and pos.bufferIndex < e.buffers.len:
                let buf = e.buffers[pos.bufferIndex]
                if buf.filePath.isSome:
                  buf.filePath.get.extractFilename
                else:
                  "[No Name]"
              else:
                "[Invalid]"
            e.state.tempMessages.add(
              marker & ($jumpNum).align(4) & " " & ($lineNum).align(5) & " " &
                ($colNum).align(4) & "  " & fileName
            )
          e.state.needsFullRedraw = true
        # Return to Normal mode (not to previous Command mode) - exit overlay first
        e.state.exitOverlay()
        e.setMode(EditorMode.Normal)
      of hrTheme:
        overlayHandled = true
        # Handle theme change command
        let themeName = r.hrThemeName
        if themeName == "default":
          # Use default theme
          setThemeColors(DefaultColors)
          e.state.setStatusMessage("Theme changed to: default")
        else:
          # Try to load theme from config directory
          let themePath =
            getHomeDir() / ".config" / "moe" / "themes" / (themeName & ".toml")
          let expandedPath = expandTilde(themePath)
          if fileExists(expandedPath):
            let themeResult = loadThemeFromToml(expandedPath)
            if themeResult.isOk:
              setThemeColors(themeResult.get)
              e.state.setStatusMessage("Theme changed to: " & themeName)
            else:
              e.state.setStatusMessage("Failed to load theme: " & themeResult.error)
          else:
            e.state.setStatusMessage("Theme not found: " & themeName)
        e.state.needsFullRedraw = true
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
          e.state.setStatusMessage("Failed to open config: " & splitResult.error)
        else:
          let baseModeBeforeOverlay = e.state.baseMode
          e.state.exitOverlay()
          e.state.previousMode = baseModeBeforeOverlay
          e.setMode(EditorMode.Config)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.Config
          activeWin.configModeState = some(newConfigModeState(e.config))
      else:
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

      if not overlayHandled:
        e.state.exitOverlay()
        e.setMode(e.state.mode)

      # Set status message if any
      let statusMsg = r.getStatusMessage()
      if statusMsg.len > 0:
        e.state.setStatusMessage(statusMsg)
    else:
      # Empty command, just return to base mode
      e.state.exitOverlay()
      e.setMode(e.state.mode) # Sync window mode

    # Clear command text and cursor (already done by exitOverlay, but ensure consistency)
    e.state.commandText = ""
    e.state.commandCursor = 0
    return true

  # Handle Left arrow - move cursor left
  if keyCombo.isSpecial and keyCombo.special == skLeft:
    if e.state.commandCursor > 0:
      e.state.commandCursor -= 1
      e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle Right arrow - move cursor right
  if keyCombo.isSpecial and keyCombo.special == skRight:
    # commandText includes the ":" prefix, so max cursor position is len - 1
    let maxPos = e.state.commandText.len - 1
    if e.state.commandCursor < maxPos:
      e.state.commandCursor += 1
      e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle Backspace - delete character before cursor
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    if e.state.commandCursor > 0 and e.state.commandText.len > 1:
      # Calculate position in commandText (cursor is 0-based after ":")
      let pos = e.state.commandCursor # Position after ":"
      # Delete character at pos (which is pos in commandText since commandText starts with ":")
      e.state.commandText =
        e.state.commandText[0 ..< pos] & e.state.commandText[pos + 1 ..^ 1]
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
    let pos = e.state.commandCursor + 1 # Position in commandText (after ":")
    if pos < e.state.commandText.len:
      e.state.commandText =
        e.state.commandText[0 ..< pos] & e.state.commandText[pos + 1 ..^ 1]
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
    e.state.commandCursor = e.state.commandText.len - 1
    e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle character input - insert at cursor position
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    # Guard against empty commandText (should have at least ":")
    if e.state.commandText.len == 0:
      e.state.commandText = ":"
      e.state.commandCursor = 0
    let pos = e.state.commandCursor + 1 # Position in commandText (after ":")
    e.state.commandText =
      e.state.commandText[0 ..< pos] & keyCombo.char & e.state.commandText[pos ..^ 1]
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

proc handleSearchModeEvent(e: Editor, event: Event): bool =
  ## Handle Search mode events - main event dispatcher
  ##
  ## This function is the entry point for all key events in Search mode.
  ## It dispatches to specialized handlers based on key type:
  ##
  ## Key Mappings:
  ## - Escape      -> cancelSearch()         (abort, restore cursor if incsearch)
  ## - Enter/CR    -> finalizeSearch()       (save search, return to Normal mode)
  ## - Backspace   -> handleSearchBackspace() (remove char, trigger incsearch)
  ## - Character   -> handleSearchCharacterInput() (add char, trigger incsearch)
  ## - Other keys  -> Ignored
  ##
  ## Returns: true (event handled)
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  let keyCombo = keyComboOpt.get

  # Escape: Cancel search and return to previous mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.cancelSearch()
    return true

  # Enter: Execute search and return to Normal mode
  let isEnter =
    (keyCombo.isSpecial and keyCombo.special == skEnter) or
    (not keyCombo.isSpecial and (keyCombo.char == "\n" or keyCombo.char == "\r"))

  if isEnter:
    e.finalizeSearch()
    return true

  # Up arrow: Navigate to previous (older) search in history
  if keyCombo.isSpecial and keyCombo.special == skUp:
    if e.state.search.history.len > 0:
      # If not yet navigating history, start from the most recent entry
      if e.state.search.historyIndex == -1:
        e.state.search.historyIndex = 0
      # Otherwise, move to the next older entry
      elif e.state.search.historyIndex < e.state.search.history.high:
        e.state.search.historyIndex += 1

      # Update search text with history entry
      e.state.search.text = e.state.search.history[e.state.search.historyIndex]
      # Trigger incremental search with history entry
      e.performIncrementalSearch()
    return true

  # Down arrow: Navigate to next (newer) search in history
  if keyCombo.isSpecial and keyCombo.special == skDown:
    if e.state.search.history.len > 0 and e.state.search.historyIndex >= 0:
      # Move to newer entry
      if e.state.search.historyIndex > 0:
        e.state.search.historyIndex -= 1
        e.state.search.text = e.state.search.history[e.state.search.historyIndex]
        e.performIncrementalSearch()
      else:
        # Reached the newest entry, clear search text
        e.state.search.historyIndex = -1
        e.state.search.text = ""
        # Restore cursor to start position if incsearch is enabled
        if e.state.search.incsearch:
          e.cursor = e.state.search.startPos
    return true

  # Backspace: Remove last character and re-search
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    # Reset history navigation when user types
    e.state.search.historyIndex = -1
    e.handleSearchBackspace()
    return true

  # Character input: Add character and perform incremental search
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    # Reset history navigation when user types
    e.state.search.historyIndex = -1
    e.handleSearchCharacterInput(keyCombo.char)
    return true

  # Ignore other special keys
  return true

proc handleRenameModeEvent(e: Editor, event: Event): bool =
  ## Handle Rename mode events - for LSP rename symbol input
  ##
  ## Key Mappings:
  ## - Escape      -> Cancel rename, return to Normal mode
  ## - Enter/CR    -> Execute rename with current text
  ## - Backspace   -> Remove last character
  ## - Character   -> Add character to rename text
  ##
  ## Returns: true (event handled)
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  let keyCombo = keyComboOpt.get

  # Escape: Cancel rename and return to base mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.state.exitOverlay()
    e.setMode(e.state.mode) # Sync window mode
    e.state.statusMessage = "Rename cancelled"
    e.state.needsFullRedraw = true
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
    e.state.needsFullRedraw = true
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

proc handleRecentFileModeEvent(e: Editor, event: Event): bool =
  ## Handle Recent File mode events
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  let keyCombo = keyComboOpt.get

  # Get viewport height for the recent file list
  # Reserve: 2 lines for status/command line, 1 line for title
  let viewportHeight = max(0, e.viewport.height - 2 - 1)

  let activeWin = e.activeWindow
  if activeWin.recentFileModeState.isNone:
    return true

  let r = e.handlerManager.handleRecentFileMode(
    activeWin.recentFileModeState.get, viewportHeight, keyCombo
  )

  case r.kind
  of hrRecentFileQuit:
    # Close the split window
    activeWin.clearModeState(EditorMode.RecentFile)
    let buf = activeWin.buffer
    let idx = e.buffers.find(buf)
    if idx >= 0:
      e.buffers.delete(idx)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    discard e.closeWindow
    e.state.statusMessage = ""
    e.state.needsFullRedraw = true
    return true
  of hrRecentFileOpenFile:
    let filePath = r.recentFilePath
    if not fileExists(filePath):
      logError("handler", "File not found: " & filePath)
      e.state.statusMessage = "File not found: " & filePath
      e.state.needsFullRedraw = true
      return true
    # Close the split window first
    activeWin.clearModeState(EditorMode.RecentFile)
    let buf = activeWin.buffer
    let idx = e.buffers.find(buf)
    if idx >= 0:
      e.buffers.delete(idx)
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
    e.state.needsFullRedraw = true
    return true
  else:
    discard

  # Handle overlay transitions (e.g., entering Command mode with :)
  let overlayTransition = r.getOverlayTransition()
  if overlayTransition.isSome:
    case overlayTransition.get
    of okCommand:
      e.state.enterCommandOverlay()
    of okSearch:
      e.state.enterSearchOverlay(e.state.search.direction)
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

  e.state.needsFullRedraw = true
  return true

proc handleDebugModeEvent(e: Editor, event: Event): bool =
  ## Handle Debug mode events
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  let keyCombo = keyComboOpt.get

  # Get viewport height for the debug viewer
  # Reserve: 2 lines for status/command line, 1 line for title
  let viewportHeight = max(0, e.viewport.height - 2 - 1)

  let activeWin = e.activeWindow
  if activeWin.debugViewerState.isNone:
    e.state.statusMessage = "Debug viewer state not initialized"
    return true

  let r = handleDebugModeKey(activeWin.debugViewerState.get, viewportHeight, keyCombo)

  case r.kind
  of dvrEnterCommand:
    e.state.enterCommandOverlay()
    e.state.needsFullRedraw = true
    return true
  of dvrHandled, dvrUnhandled, dvrError:
    e.state.needsFullRedraw = true
    return true

proc handlePasteEvent*(e: Editor, event: Event): bool =
  ## Handle paste events from Bracketed Paste Mode
  ## Inserts pasted text without triggering auto-indentation
  if event.kind != EventKind.Paste:
    return true

  let pastedText = event.pastedText
  if pastedText.len == 0:
    return true

  let activeBuffer = e.activeBuffer()

  # Handle paste differently based on mode
  case e.state.mode
  of EditorMode.Insert:
    # In Insert mode: Insert text directly without auto-indentation
    let transactionResult = activeBuffer.beginTransaction("Paste")
    if transactionResult.isErr:
      e.state.setStatusMessage("Paste failed: " & transactionResult.error)
      return true

    var pos = e.cursor
    discard activeBuffer.insertText(pos, pastedText)

    # Calculate new cursor position after paste
    var newLine = pos.line
    var newColumn = pos.column
    for ch in pastedText:
      if ch == '\n':
        newLine += 1
        newColumn = 0
      else:
        newColumn += 1

    e.activeWindow.cursor.line = newLine
    e.activeWindow.cursor.column = newColumn

    discard activeBuffer.commitTransaction()
    e.state.needsFullRedraw = true
  else:
    # For other modes, just show a message
    e.state.setStatusMessage("Paste not supported in this mode")

  return true

proc screenToBufferPosition(
    vp: ViewPort,
    buffer: TextBuffer,
    mouseX, mouseY: int,
    lineNumOffset, sidebarWidth, reservedLines: int,
    lineWrap: bool,
    tabStop: int = 4,
): Option[BufferPosition] =
  ## Convert screen coordinates to buffer position.
  ## Returns none if click is outside the text area.
  ## Handles line wrap mode with display-width-based segment calculation.
  ##
  ## lineNumOffset: line number area width (from calculateLineNumOffset)
  ## sidebarWidth: sidebar area width (from calculateSidebarWidth)
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
    # Must match renderWindowLineWrapped: maxWidth = viewport.width - sidebarWidth - lineNumOffset
    let maxWidth = max(1, vp.width - sidebarWidth - lineNumOffset)
    # Walk through buffer lines, accumulating screen rows for each wrapped line
    var currentScreenY = 0
    var bufferLine = vp.topLine
    var wrapSegment = 0

    while bufferLine < buffer.len:
      let line = buffer.getLine(bufferLine)
      let wrapCount = calculateWrapCount(line, maxWidth, tabStop)
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
      let lineLen = buffer[bufferLine].len
      bufferColumn = clamp(bufferColumn, 0, max(0, lineLen - 1))

    return some(BufferPosition(line: bufferLine, column: bufferColumn))

proc calculateLineNumOffsetForMouse(e: Editor, buffer: TextBuffer): int =
  ## Calculate line number offset (matching rendering calculation)
  calculateLineNumOffset(buffer, e.state.display.showLineNumbers)

proc handleMouseEvent(e: Editor, event: Event): bool =
  ## Handle mouse events for cursor movement
  ## Returns true if the event was handled, false otherwise
  if event.kind != EventKind.Mouse:
    return false
  if not e.config.standard.mouse:
    return false

  let mouse = event.mouse

  # Only handle left button press and wheel events
  if mouse.button notin {
    mouse_logic.MouseButton.Left, mouse_logic.MouseButton.WheelUp,
    mouse_logic.MouseButton.WheelDown,
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
    if e.state.mode == EditorMode.Filer and e.activeWindow.filerState.isSome:
      var filerState = e.activeWindow.filerState.get
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
        e.activeWindow.filerState = some(filerState)
        e.state.needsFullRedraw = true
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
        let lineLen = window.buffer[newLine].len
        if lineLen > 0:
          window.cursor.column = min(window.cursor.column, lineLen - 1)
        else:
          window.cursor.column = 0

        # Update viewport topLine to keep cursor visible
        let viewportHeight = window.viewport.height
        if viewportHeight > 0:
          if newLine < window.viewport.topLine:
            window.viewport.topLine = newLine
          elif newLine >= window.viewport.topLine + viewportHeight:
            window.viewport.topLine = newLine - viewportHeight + 1

        e.state.needsFullRedraw = true

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
      if e.state.display.showTabLine:
        for i, window in e.windowManager.windows:
          let vp = window.viewport
          if mouse.y == vp.y and mouse.x >= vp.x and mouse.x < vp.x + vp.width:
            let buffersToShow =
              if window.bufferList.len > 0:
                window.bufferList
              else:
                @[window.buffer]
            let tabIdx =
              hitTestTabLine(buffersToShow, window.mode, vp.x, vp.width, mouse.x)
            if tabIdx >= 0:
              # Switch to clicked window if not already active
              if i != e.windowManager.activeWindowIndex:
                e.windowManager.activeWindowIndex = i
                for j, w in e.windowManager.windows.mpairs:
                  w.active = (j == i)
              e.switchToWindowBuffer(tabIdx)
              e.state.needsFullRedraw = true
              return true

      for i, window in e.windowManager.windows:
        let vp = window.viewport
        # Check if click is within this window's viewport
        if mouse.x >= vp.x and mouse.x < vp.x + vp.width and mouse.y >= vp.y and
            mouse.y < vp.y + vp.height:
          let
            lineNumOffset = e.calculateLineNumOffsetForMouse(window.buffer)
            sidebarWidth = e.calculateSidebarWidth(window.mode)
            # Each window has its own status line
            reservedLines = if e.state.display.showStatusLine: 1 else: 0
            posOpt = screenToBufferPosition(
              vp, window.buffer, mouse.x, mouse.y, lineNumOffset, sidebarWidth,
              reservedLines, e.state.display.lineWrap, e.state.display.tabStop,
            )

          if posOpt.isNone:
            return false

          let pos = posOpt.get

          # Switch to clicked window if not already active
          if i != e.windowManager.activeWindowIndex:
            e.windowManager.activeWindowIndex = i
            for j, w in e.windowManager.windows.mpairs:
              w.active = (j == i)

          # Update cursor (e.cursor= sets both state.cursor and activeWindow.cursor)
          # Note: After switching window index, e.activeWindow now refers to window i
          e.cursor = pos
          e.state.needsFullRedraw = true
          return true

      return false

    # Single window mode
    # Check tab line click first
    if e.state.display.showTabLine and mouse.y == 0:
      let buffersToShow =
        if e.activeWindow.bufferList.len > 0:
          e.activeWindow.bufferList
        else:
          @[e.activeBuffer()]
      let tabIdx =
        hitTestTabLine(buffersToShow, e.state.mode, 0, e.viewport.width, mouse.x)
      if tabIdx >= 0:
        e.switchToWindowBuffer(tabIdx)
        e.state.needsFullRedraw = true
        return true

    let
      activeBuffer = e.activeBuffer()
      lineNumOffset = e.calculateLineNumOffsetForMouse(activeBuffer)
      sidebarWidth = e.calculateSidebarWidth(e.activeWindow.mode)
      # Status line + command line
      reservedLines = if e.state.display.showStatusLine: 2 else: 1
      # Account for tab line offset
      tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0
      adjustedMouseY = mouse.y - tabLineOffset
      posOpt = screenToBufferPosition(
        e.viewport, activeBuffer, mouse.x, adjustedMouseY, lineNumOffset, sidebarWidth,
        reservedLines, e.state.display.lineWrap, e.state.display.tabStop,
      )

    if posOpt.isNone:
      return false

    let pos = posOpt.get
    # e.cursor= sets both state.cursor and activeWindow.cursor
    e.cursor = pos
    e.state.needsFullRedraw = true
    return true

  # Handle mouse click in Filer mode
  if e.state.mode == EditorMode.Filer and e.activeWindow.filerState.isSome:
    var filerState = e.activeWindow.filerState.get
    let
      tabLineOffset = if e.state.display.showTabLine: TabLineHeight else: 0
      reservedLines = if e.state.display.showStatusLine: 2 else: 1
      adjustedMouseY = mouse.y - tabLineOffset

    # Ignore clicks on tab line or status/command line area
    if adjustedMouseY >= 0 and adjustedMouseY < e.viewport.height - reservedLines:
      let clickedIndex = filerState.topLine + adjustedMouseY
      if clickedIndex >= 0 and clickedIndex < filerState.entries.len:
        filerState.selectedIndex = clickedIndex
        e.activeWindow.filerState = some(filerState)
        e.state.needsFullRedraw = true
        return true

  return false

proc handleWindowCommand(e: Editor, keyCombo: KeyCombo, syncState: bool): Option[bool] =
  ## Handle Ctrl-W window command second key (j/k/c).
  ## Returns some(true) if handled, some(false) if last window closed (quit),
  ## none if not a window command key.
  if e.state.pendingCommand == PendingWindowCmd:
    e.state.pendingCommand = PendingNone
    if not keyCombo.isSpecial:
      if keyCombo.char == "j":
        e.switchToPrevWindow
        if syncState:
          e.syncStateFromWindow()
        return some(true)
      elif keyCombo.char == "k":
        e.switchToNextWindow
        if syncState:
          e.syncStateFromWindow()
        return some(true)
      elif keyCombo.char == "c":
        let shouldQuit = e.closeWindow()
        if shouldQuit:
          return some(false)
        if syncState:
          e.syncStateFromWindow()
        return some(true)
    return some(true) # Unknown window command, cancel

  # Check for Ctrl-w to enter window command mode
  if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and keyCombo.char == "w":
    e.state.pendingCommand = PendingWindowCmd
    return some(true)

  return none(bool)

proc handleEvent*(e: Editor, event: Event): bool =
  ## Main event handler using the new handler manager system

  # Clear status message from previous event cycle:
  # messages persist for one render frame, then clear on next input)
  e.state.statusMessage = ""

  # Update last input time for auto backup idle detection
  e.updateInputTime()

  # Cancel smooth scroll animation on any key press
  if event.kind == EventKind.Key and e.state.scrollAnimation.active:
    cancelScrollAnimation(e.state.scrollAnimation)

  # Handle mouse events first
  if event.kind == EventKind.Mouse:
    discard e.handleMouseEvent(event)
    return true # Always continue running after mouse events

  # Handle paste events (Bracketed Paste Mode)
  if event.kind == EventKind.Paste:
    return e.handlePasteEvent(event)

  # Handle temporary messages (like :jumps output) - dismiss on any key
  if e.state.tempMessages.len > 0 and event.kind == EventKind.Key:
    let keyComboOpt = eventToKeyCombo(event)
    if keyComboOpt.isSome:
      let keyCombo = keyComboOpt.get
      e.state.tempMessages = @[]
      e.state.needsFullRedraw = true

      # If ":" was pressed, enter command overlay
      if not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char == ":":
        e.state.enterCommandOverlay()
      # Otherwise just dismiss and stay in current mode
      return true

  # Handle overlay modes (Command, Search, Rename) - these sit on top of base modes
  if e.state.isCommandOverlay:
    return handleCommandModeEvent(e, event)

  if e.state.isSearchOverlay:
    return handleSearchModeEvent(e, event)

  if e.state.isRenameOverlay:
    return handleRenameModeEvent(e, event)

  # Handle Debug mode input
  if e.state.mode == EditorMode.Debug:
    return handleDebugModeEvent(e, event)

  # Handle CodeLens picker input when active
  if e.state.lspCache.codeLensPicker.isActive and event.kind == EventKind.Key:
    let keyComboOpt = eventToKeyCombo(event)
    if keyComboOpt.isSome:
      let keyCombo = keyComboOpt.get

      # Escape - cancel picker
      if keyCombo.isSpecial and keyCombo.special == skEscape:
        e.hideCodeLensPicker()
        e.state.statusMessage = ""
        return true

      # Enter - confirm selection
      if keyCombo.isSpecial and keyCombo.special == skEnter:
        asyncSpawn e.codeLensPickerConfirm()
        return true

      # j or Down - next item
      if not keyCombo.isSpecial:
        if keyCombo.char == "j":
          e.codeLensPickerSelectNext()
          return true
        # k or Up - previous item
        if keyCombo.char == "k":
          e.codeLensPickerSelectPrev()
          return true
        # Number keys 1-9 - direct selection
        if keyCombo.char.len == 1 and keyCombo.char[0] in '1' .. '9':
          let num = ord(keyCombo.char[0]) - ord('0')
          asyncSpawn e.codeLensPickerSelectByNumber(num)
          return true

      if keyCombo.isSpecial:
        if keyCombo.special == skDown:
          e.codeLensPickerSelectNext()
          return true
        if keyCombo.special == skUp:
          e.codeLensPickerSelectPrev()
          return true

      # Any other key closes picker
      e.hideCodeLensPicker()
      e.state.statusMessage = ""
      # Don't return - let the key be processed normally

  # Handle Hover popup input when active
  if e.state.lspCache.hoverPopup.isActive() and event.kind == EventKind.Key:
    let keyComboOpt = eventToKeyCombo(event)
    if keyComboOpt.isSome:
      let keyCombo = keyComboOpt.get

      # Escape - close popup
      if keyCombo.isSpecial and keyCombo.special == skEscape:
        e.hideHoverPopup()
        return true

      # j/k/h/l - scroll
      if not keyCombo.isSpecial:
        if keyCombo.char == "j":
          e.hoverPopupScrollDown()
          return true
        if keyCombo.char == "k":
          e.hoverPopupScrollUp()
          return true
        if keyCombo.char == "l":
          e.hoverPopupScrollRight()
          return true
        if keyCombo.char == "h":
          e.hoverPopupScrollLeft()
          return true

      if keyCombo.isSpecial:
        if keyCombo.special == skDown:
          e.hoverPopupScrollDown()
          return true
        if keyCombo.special == skUp:
          e.hoverPopupScrollUp()
          return true
        if keyCombo.special == skRight:
          e.hoverPopupScrollRight()
          return true
        if keyCombo.special == skLeft:
          e.hoverPopupScrollLeft()
          return true

      # Any other key closes popup and processes normally
      e.hideHoverPopup()
      # Don't return - let the key be processed normally

  # Check for Vim-style Ctrl-w prefix for window commands
  if e.state.mode == EditorMode.Normal and event.kind == EventKind.Key:
    let keyComboOpt = eventToKeyCombo(event)
    if keyComboOpt.isSome:
      let keyCombo = keyComboOpt.get

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
          e.state.search.hlsearchTempDisabled = true
          e.state.needsFullRedraw = true
          e.state.lastKeyWasEscape = false
        else:
          # First Escape press - just mark it
          e.state.lastKeyWasEscape = true
        return true
      else:
        # Any other key resets the Escape counter
        e.state.lastKeyWasEscape = false

      # Ctrl-W window commands (no syncState needed in Normal mode)
      let winCmd = e.handleWindowCommand(keyCombo, syncState = false)
      if winCmd.isSome:
        return winCmd.get

  # Ctrl-W window commands for special/viewer modes
  if e.state.mode notin {
    EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualBlock,
    EditorMode.VisualLine, EditorMode.Replace,
  } and event.kind == EventKind.Key:
    let keyComboOpt = eventToKeyCombo(event)
    if keyComboOpt.isSome:
      let keyCombo = keyComboOpt.get

      # Cancel window command mode on Escape
      if e.state.pendingCommand == PendingWindowCmd and keyCombo.isSpecial and
          keyCombo.special == skEscape:
        e.state.pendingCommand = PendingNone
        return true

      let winCmd = e.handleWindowCommand(keyCombo, syncState = true)
      if winCmd.isSome:
        return winCmd.get

  # Handle Recent File mode input (after Ctrl-W window commands)
  if e.state.mode == EditorMode.RecentFile:
    return handleRecentFileModeEvent(e, event)

  # For other modes, use the unified handler manager with active buffer
  let activeBuffer = e.activeBuffer

  # Get the active viewport if in split mode and sync with motion controller
  var activeViewport = e.viewport
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    activeViewport = e.activeWindow.viewport
    # Sync the motion controller's viewport with the active window's viewport
    e.executer.motionController.viewportManager.viewport = activeViewport

    # Set reserved lines for viewport calculations
    # Find the maximum bottom Y coordinate to determine bottom windows
    var maxBottomY = 0
    for window in e.windowManager.windows:
      let bottomY = window.viewport.y + window.viewport.height
      if bottomY > maxBottomY:
        maxBottomY = bottomY

    # A window is a bottom window if its bottom edge is at the maximum bottom Y
    let
      windowBottomY = e.activeWindow.viewport.y + e.activeWindow.viewport.height
      isBottomWindow = (windowBottomY == maxBottomY)

    # Calculate reserved lines based on window position and status line mode
    e.state.viewportReservedLines =
      if e.state.display.showStatusLine:
        if e.state.display.multiStatusLine:
          # Multi status line mode: each window has status, bottom has command too
          if isBottomWindow: 2 else: 1
        else:
          # Single status line mode: only bottom has status + command
          if isBottomWindow: 2 else: 0
      else:
        # No status line: only bottom has command line
        if isBottomWindow: 1 else: 0

    # Add tab line height if shown
    if e.state.display.showTabLine:
      e.state.viewportReservedLines += TabLineHeight

    # Add extra lines for multi-line status messages (only for bottom window)
    if isBottomWindow:
      e.state.viewportReservedLines += e.state.statusMessageExtraLines()
  else:
    # Single window mode - use default calculation
    e.state.viewportReservedLines = if e.state.display.showStatusLine: 2 else: 1

    # Add tab line height if shown
    if e.state.display.showTabLine:
      e.state.viewportReservedLines += TabLineHeight

    # Add extra lines for multi-line status messages
    e.state.viewportReservedLines += e.state.statusMessageExtraLines()
    # Sync the motion controller's viewport with the editor's viewport
    e.executer.motionController.viewportManager.viewport = e.viewport

  # Get active window for handleEvent (needed for special modes like Filer)
  let activeWin =
    if e.windowManager.windows.len > 0 and
        e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      some(e.activeWindow)
    else:
      none(EditorWindow)

  # Sync EditorState from EditorWindow before handler call
  # (handlers read/write state.cursor and state.mode)
  e.syncStateFromWindow()

  let r = e.handlerManager.handleEvent(
    activeBuffer, e.state, activeViewport, event, activeWin
  )

  # Sync EditorState back to EditorWindow after handler call
  e.syncStateToWindow()

  # Sync display settings when in Config mode (config changes update EditorConfig
  # but the cached display state needs to be kept in sync)
  if e.currentMode == EditorMode.Config:
    e.applyConfigSettings(e.config)

  # For LogViewer mode, update viewport to follow cursor
  # (LogViewer handles cursor directly without using MotionController)
  if e.currentMode == EditorMode.LogViewer:
    e.updateViewportForCursor(e.cursor)

  # Sync viewport from motionController to window
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.activeWindow.viewport = e.executer.motionController.viewportManager.viewport
  else:
    # Single window mode - sync viewport from motionController
    e.viewport = e.executer.motionController.viewportManager.viewport

  # Process the result
  case r.kind
  of hrQuit:
    return false # Signal app should quit
  of hrSaveAndQuit:
    return e.processSaveAndQuitResult(r)
  of hrGotoLine:
    e.processGotoLineResult(r, activeBuffer)
  of hrJumpToBuffer:
    # Handle jump to buffer with position (Ctrl-o/Ctrl-i across files)
    let targetIdx = r.jumpBufferIndex
    let targetLine = r.jumpLine
    let targetCol = r.jumpColumn
    if targetIdx >= 0 and targetIdx < e.buffers.len:
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
      e.state.needsFullRedraw = true
      e.updateViewportForCursor(e.cursor)
  of hrFilerOpenFile:
    # Open file from filer (Adds to window's bufferList as new tab)
    let activeWin = e.activeWindow
    activeWin.restoreOriginalBuffer(EditorMode.Filer)
    let editResult = e.editFile(r.filerFilePath)
    if editResult.isErr:
      e.state.setStatusMessage("Error: " & editResult.error)
    else:
      activeWin.filerState = none(FilerState)
      activeWin.mode = EditorMode.Normal
      e.setMode(EditorMode.Normal)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.state.setStatusMessage("Opened: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file: " & r.filerFilePath)
    return true
  of hrFilerOpenFileVSplit:
    # Open file in vertical split from filer
    let activeWinVS = e.activeWindow
    activeWinVS.restoreOriginalBuffer(EditorMode.Filer)
    let splitResult = e.vsplit(some(r.filerFilePath))
    if splitResult.isErr:
      e.state.setStatusMessage("Error: " & splitResult.error)
    else:
      let activeWin = e.activeWindow
      activeWin.filerState = none(FilerState)
      activeWin.mode = EditorMode.Normal
      e.setMode(EditorMode.Normal)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.state.setStatusMessage("Opened in vsplit: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file in vsplit: " & r.filerFilePath)
    return true
  of hrFilerOpenFileHSplit:
    # Open file in horizontal split from filer
    let activeWinHS = e.activeWindow
    activeWinHS.restoreOriginalBuffer(EditorMode.Filer)
    let splitResult = e.hsplit(some(r.filerFilePath))
    if splitResult.isErr:
      e.state.setStatusMessage("Error: " & splitResult.error)
    else:
      let activeWin = e.activeWindow
      activeWin.filerState = none(FilerState)
      activeWin.mode = EditorMode.Normal
      e.setMode(EditorMode.Normal)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.state.setStatusMessage("Opened in hsplit: " & r.filerFilePath)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file in hsplit: " & r.filerFilePath)
    return true
  of hrFilerQuit:
    # Close filer and return to Normal mode
    e.activeWindow.clearModeState(EditorMode.Filer)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrFilerDeleteFile:
    # Delete file/directory from filer
    let activeWin = e.activeWindow
    if activeWin.filerState.isSome:
      let deleteResult = activeWin.filerState.get.deleteSelected()
      if deleteResult.success:
        # File/directory deleted successfully
        if e.config.notification.screenNotifications and
            e.config.notification.filerScreenNotify:
          e.state.setStatusMessage("Deleted: " & deleteResult.path)
        if e.config.notification.logNotifications and
            e.config.notification.filerLogNotify:
          logInfo("filer", "Deleted: " & deleteResult.path)
      else:
        # Deletion failed
        e.state.setStatusMessage("Delete failed: " & deleteResult.error)
        logError("filer", "Delete failed: " & deleteResult.error)
    return true
  of hrFilerShowInfo:
    # Show file information in status line
    e.state.setStatusMessage(r.filerFileInfo)
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
      let idx = e.buffers.find(buf)
      if idx >= 0:
        e.buffers.delete(idx)
      discard e.closeWindow()
    return true
  of hrLogViewerRefresh:
    # Refresh log viewer content by creating new buffer with updated content
    let activeWin = e.activeWindow
    if activeWin.logViewerState.isSome:
      let logLines =
        case activeWin.logViewerState.get.contentKind
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
      e.state.setStatusMessage("Log refreshed")
    return true
  of hrHelpViewerQuit:
    # Close help viewer and return to Normal mode
    e.activeWindow.clearModeState(EditorMode.Help)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrReferencesQuit:
    # Close references viewer and return to Normal mode
    e.activeWindow.clearModeState(EditorMode.References)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrReferencesJumpTo:
    # Jump to selected reference
    e.activeWindow.clearModeState(EditorMode.References)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    discard e.openFileAndJumpTo(r.jumpToPath, r.jumpToLine, r.jumpToColumn)
    return true
  of hrDocumentSymbolQuit:
    # Close document symbol viewer and return to Normal mode
    e.activeWindow.clearModeState(EditorMode.DocumentSymbol)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrDocumentSymbolJumpTo:
    # Jump to selected symbol (same file)
    let activeWin = e.activeWindow
    let filePath = activeWin.documentSymbolViewerState.get.filePath
    activeWin.clearModeState(EditorMode.DocumentSymbol)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    discard e.openFileAndJumpTo(filePath, r.symbolLine, r.symbolColumn)
    return true
  of hrCallHierarchyQuit:
    # Close call hierarchy viewer and return to Normal mode
    e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone
    e.activeWindow.clearModeState(EditorMode.CallHierarchy)
    e.activeWindow.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrCallHierarchyJumpTo:
    # Jump to selected call hierarchy item
    let path =
      if r.callHierarchyJumpUri.startsWith("file://"):
        r.callHierarchyJumpUri[7 ..^ 1]
      else:
        r.callHierarchyJumpUri
    e.state.lspCache.pendingCallHierarchyRequestId = 0
    e.state.lspCache.pendingCallHierarchyKind = chrkNone
    e.activeWindow.clearModeState(EditorMode.CallHierarchy)
    e.activeWindow.mode = EditorMode.Normal
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
    activeWin.bufferManagerState = none(BufferManagerState)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    return true
  of hrBufferManagerDeleteBuffer:
    # Delete the buffer from the buffer list
    let bufferIndex = r.deleteBufferIdx
    if e.buffers.len > 1:
      # Can only delete if there's more than one buffer
      if bufferIndex >= 0 and bufferIndex < e.buffers.len:
        let deletedBuffer = e.buffers[bufferIndex]
        e.buffers.delete(bufferIndex)

        # If deleted buffer was shown in any window, switch to another buffer
        for window in e.windowManager.windows:
          if window.buffer == deletedBuffer:
            # Switch to the first available buffer
            let newIdx = min(bufferIndex, e.buffers.len - 1)
            window.buffer = e.buffers[newIdx]
            window.cursor = BufferPosition(line: 0, column: 0)
            window.viewport.topLine = 0
            window.viewport.leftColumn = 0

        # Update executor if current buffer was deleted
        if e.activeBuffer() != e.executer.buffer:
          e.executer.buffer = e.activeBuffer()
          e.executer.motionController.executor.buffer = e.activeBuffer()

        # Update buffer manager entries and regenerate TextBuffer
        let activeWin = e.activeWindow
        if activeWin.bufferManagerState.isSome:
          let bmState = activeWin.bufferManagerState.get
          bmState.updateEntries(e.getBufferInfos())
          activeWin.buffer = bmState.createBufferManagerTextBuffer()
          activeWin.cursor.line =
            min(bmState.selectedIndex + 1, activeWin.buffer.len - 1)
          activeWin.cursor.column = 0
    else:
      # Cannot delete the only buffer
      e.state.setStatusMessage("Cannot delete the last buffer")
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
      let idx = e.buffers.find(buf)
      if idx >= 0:
        e.buffers.delete(idx)
      discard e.closeWindow()
    return true
  of hrDiffViewerQuit:
    # Close diff viewer and return to BackupManager
    e.activeWindow.clearModeState(EditorMode.DiffViewer)
    e.activeWindow.mode = EditorMode.BackupManager
    e.setMode(EditorMode.BackupManager)
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
      let idx = e.buffers.find(buf)
      if idx >= 0:
        e.buffers.delete(idx)
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
        e.state.setStatusMessage("Failed to backup config: " & ex.msg)
        logError("config", "Failed to backup config: " & ex.msg)
        return true

    let saveResult = saveConfig(e.config)
    if saveResult.isOk:
      e.state.setStatusMessage("Config saved: " & configPath)
      logInfo("config", "Config saved: " & configPath)
    else:
      e.state.setStatusMessage("Failed to save config: " & saveResult.error)
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
        e.state.setStatusMessage("Error: Failed to backup config: " & ex.msg)
        logError("config", "Failed to backup config: " & ex.msg)
        e.setMode(EditorMode.Normal)
        return true

    let saveResult = saveConfig(e.config)
    if saveResult.isOk:
      e.state.setStatusMessage("Config written: " & configPath)
      logInfo("config", "Config written: " & configPath)
    else:
      e.state.setStatusMessage("Failed to write config: " & saveResult.error)
      logError("config", "Failed to write config: " & saveResult.error)
    e.setMode(EditorMode.Normal)
    return true
  of hrBackupManagerRefresh:
    # Refresh backup list and regenerate TextBuffer
    let activeWin = e.activeWindow
    if activeWin.backupManagerState.isSome:
      let bkState = activeWin.backupManagerState.get
      bkState.refresh()
      activeWin.buffer = bkState.createBackupManagerTextBuffer()
      activeWin.cursor.line = min(bkState.selectedIndex + 1, activeWin.buffer.len - 1)
      activeWin.cursor.column = 0
    return true
  of hrBackupManagerRestore:
    # Restore the selected backup
    let backupIndex = r.restoreBackupIndex
    let activeWin = e.activeWindow
    if activeWin.backupManagerState.isSome:
      let bkState = activeWin.backupManagerState.get
      # Backup current buffer before restore (in case user wants to undo)
      discard
        backupBuffer(e.buffer.filePath, e.buffer.getFileContent(), e.config.autoBackup)
      if bkState.restoreBackup(backupIndex):
        # Reload the buffer from the restored file
        if e.buffer.filePath.isSome:
          let filePath = e.buffer.filePath.get
          let textResult = e.buffer.loadFile(filePath)
          if textResult.isOk:
            # Restore screen notification (controlled by config)
            if e.config.notification.screenNotifications and
                e.config.notification.restoreScreenNotify:
              e.state.setStatusMessage("Backup restored: " & filePath)
            # Restore log notification (controlled by config)
            if e.config.notification.logNotifications and
                e.config.notification.restoreLogNotify:
              logInfo("restore", "Backup restored: " & filePath)
            # Refresh the backup list to show the new backup
            bkState.refresh()
          else:
            e.state.setStatusMessage(
              "Restored but failed to reload: " & textResult.error
            )
        else:
          # Restore screen notification (controlled by config)
          if e.config.notification.screenNotifications and
              e.config.notification.restoreScreenNotify:
            e.state.setStatusMessage("Backup restored successfully")
          # Restore log notification (controlled by config)
          if e.config.notification.logNotifications and
              e.config.notification.restoreLogNotify:
            logInfo("restore", "Backup restored successfully")
      else:
        e.state.setStatusMessage("Failed to restore backup")
    return true
  of hrBackupManagerDelete:
    # Delete the selected backup
    let backupIndex = r.deleteBackupIndex
    let activeWin = e.activeWindow
    if activeWin.backupManagerState.isSome:
      let bkState = activeWin.backupManagerState.get
      if bkState.deleteBackup(backupIndex):
        e.state.setStatusMessage("Backup deleted")
        # Regenerate TextBuffer after deletion
        activeWin.buffer = bkState.createBackupManagerTextBuffer()
        activeWin.cursor.line = min(bkState.selectedIndex + 1, activeWin.buffer.len - 1)
        activeWin.cursor.column = 0
      else:
        e.state.setStatusMessage("Failed to delete backup")
    return true
  of hrBackupManagerOpenDiff:
    # Open diff viewer for the selected backup
    let backupIndex = r.diffBackupIndex
    let activeWin = e.activeWindow
    if activeWin.backupManagerState.isSome:
      let bkState = activeWin.backupManagerState.get
      if backupIndex >= 0 and backupIndex < bkState.entries.len:
        let entry = bkState.entries[backupIndex]
        # Initialize diff viewer with source and backup paths
        let dvState = initDiffViewerState(bkState.sourceFilePath, entry.fullPath)
        # Save original buffer and replace with diff content TextBuffer
        dvState.originalBuffer = activeWin.buffer
        activeWin.buffer = dvState.createDiffTextBuffer()
        activeWin.cursor = BufferPosition(line: 0, column: 0)
        activeWin.viewport.topLine = 0
        activeWin.viewport.leftColumn = 0
        activeWin.diffViewerState = some(dvState)
        e.state.previousMode = e.state.mode
        e.setMode(EditorMode.DiffViewer)
        activeWin.mode = EditorMode.DiffViewer
        if dvState.errorMessage.len > 0:
          e.state.setStatusMessage("Diff error: " & dvState.errorMessage)
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
    e.state.needsFullRedraw = true
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
  else:
    discard # Fall through to post-processing

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
    if newMode == EditorMode.Filer and activeWin.filerState.isNone:
      # Use buffer's directory or current working directory
      let startPath =
        if activeBuffer.filePath.isSome:
          parentDir(activeBuffer.filePath.get)
        else:
          getCurrentDir()
      let filerState = newFilerState(startPath)
      filerState.originalBuffer = activeWin.buffer
      activeWin.filerState = some(filerState)
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
      activeWin.bufferManagerState = some(bmState)
      activeWin.mode = EditorMode.BufferManager

    # Adjust cursor when transitioning from Insert to Normal mode
    # In Insert mode, cursor can be after the last character
    # In Normal mode, cursor must be on a character (not after)
    if oldMode == EditorMode.Insert and newMode == EditorMode.Normal:
      let
        currentLine = activeBuffer.getLine(e.activeWindow.cursor.line)
        lineCharLen = currentLine.charLen
        oldColumn = e.activeWindow.cursor.column

      logDebug(
        "handler",
        "Insert→Normal transition: line=" & $e.activeWindow.cursor.line & " oldColumn=" &
          $oldColumn & " lineCharLen=" & $lineCharLen,
      )

      if lineCharLen == 0:
        # Empty line: cursor should be at column 0
        e.activeWindow.cursor.column = 0
      elif e.activeWindow.cursor.column >= lineCharLen:
        # Cursor is beyond last character, move it back to last char
        e.activeWindow.cursor.column = lineCharLen - 1

      if oldColumn != e.activeWindow.cursor.column:
        logDebug(
          "handler",
          "Cursor adjusted: " & $oldColumn & " → " & $e.activeWindow.cursor.column,
        )

  # Filer buffer regeneration after state changes (e.g. enterDirectory, toggleHidden)
  if e.state.mode == EditorMode.Filer:
    let filerWin = e.activeWindow
    if filerWin.filerState.isSome and filerWin.filerState.get.needsBufferRefresh:
      filerWin.buffer =
        filerWin.filerState.get.createFilerTextBuffer(e.config.filer.showIcons)
      filerWin.filerState.get.needsBufferRefresh = false

  # Set status message if any
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.setStatusMessage(statusMsg)

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

proc hasPendingAsyncOperations*(e: Editor): bool =
  ## Check if there are pending async operations
  e.state.pendingShellCommand.len > 0 or e.state.pendingManPage.len > 0 or
    e.state.pendingBackground or e.state.pendingBuildOnSave.path.len > 0 or
    e.state.pendingQuickRun.cmd.len > 0 or e.state.pendingSyntaxCheck.path.len > 0

type
  BuildInfo =
    tuple[path: string, language: int, customCmd: string, workspaceRoot: string]
  QuickRunInfo =
    tuple[cmd: string, args: seq[string], filePath: string, isTempFile: bool]
  SyntaxCheckInfo = tuple[path: string, language: int]

proc runSyntaxCheckAsync(
    editor: Editor, info: SyntaxCheckInfo
): Future[void] {.async: (raises: []).} =
  ## Run syntax check process in background and apply results to buffer
  {.cast(gcsafe).}:
    try:
      let checkResult =
        await startBackgroundSyntaxCheck(info.path, SourceLanguage(info.language))
      if checkResult.isErr:
        editor.state.setStatusMessage("Syntax check error: " & checkResult.error)
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
          editor.state.setStatusMessage(
            "Syntax check: " & $errorCount & " error(s), " & $warnCount & " warning(s)"
          )
        else:
          editor.state.setStatusMessage("Syntax check: OK")
      editor.state.needsFullRedraw = true
    except Exception as ex:
      editor.state.setStatusMessage("Syntax check error: " & ex.msg)

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
        editor.state.setStatusMessage("Build error: " & buildResult.error)
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
          editor.state.setStatusMessage(
            "Failed to open output window: " & splitResult.error
          )
        else:
          if editor.config.notification.screenNotifications and
              editor.config.notification.buildOnSaveScreenNotify:
            editor.state.setStatusMessage("Build completed: " & info.path)
      editor.state.needsFullRedraw = true
    except Exception as ex:
      editor.state.setStatusMessage("Build error: " & ex.msg)

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
        editor.state.setStatusMessage("QuickRun error: " & quickRunResult.error)
      else:
        let qrProcess = quickRunResult.get
        editor.addRunningProcess(qrProcess.process)
        let outputResult = await qrProcess.waitForResultAsync()
        editor.removeRunningProcess(qrProcess.process)
        if outputResult.isErr:
          editor.state.setStatusMessage("QuickRun error: " & outputResult.error)
        else:
          let output = outputResult.get
          let outputContent = output.join("\n")
          let outputBuffer = newTextBuffer(outputContent)
          outputBuffer.readOnly = true
          let splitResult = editor.hsplitWithBuffer(outputBuffer)
          if splitResult.isErr:
            editor.state.setStatusMessage(
              "Failed to open output window: " & splitResult.error
            )
          else:
            if editor.config.notification.screenNotifications and
                editor.config.notification.quickRunScreenNotify:
              editor.state.setStatusMessage("QuickRun completed: " & qrProcess.filePath)
      editor.state.needsFullRedraw = true
    except Exception as ex:
      editor.state.setStatusMessage("QuickRun error: " & ex.msg)

proc handlePendingAsyncOperationsImpl(
    e: Editor
): Future[void] {.async: (raises: [Exception]).} =
  ## Handle pending async operations that require TUI suspend or background processing
  ## Called from the main event loop after handleEvent returns

  {.cast(gcsafe).}:
    # Handle shell command
    if e.state.pendingShellCommand.len > 0:
      let cmd = e.state.pendingShellCommand
      e.state.pendingShellCommand = ""
      await e.app.suspendAsync()
      stdout.write("\e[H\e[2J") # Clear screen
      stdout.flushFile()
      let exitCode = execShellCmd(cmd)
      stdout.write("\n\nShell returned " & $exitCode & "\n")
      stdout.write("Press Enter to continue...")
      stdout.flushFile()
      discard stdin.readLine()
      await e.app.resumeAsync()
      e.state.needsFullRedraw = true

    # Handle man page display
    if e.state.pendingManPage.len > 0:
      let page = e.state.pendingManPage
      e.state.pendingManPage = ""
      await e.app.suspendAsync()
      stdout.write("\e[H\e[2J") # Clear screen
      stdout.flushFile()
      let exitCode = execShellCmd("man " & quoteShell(page))
      if exitCode != 0:
        stdout.write("man: " & page & " not found\n")
      stdout.write("\nPress Enter to continue...")
      stdout.flushFile()
      discard stdin.readLine()
      await e.app.resumeAsync()
      e.state.needsFullRedraw = true

    # Handle background suspend
    if e.state.pendingBackground:
      e.state.pendingBackground = false
      await e.app.suspendAsync()
      stdout.write("\e[H\e[2J")
      stdout.write("moe suspended. Press Enter to return to moe...")
      stdout.flushFile()
      discard stdin.readLine()
      await e.app.resumeAsync()
      e.state.needsFullRedraw = true

    # Handle pending build - spawn as background task
    if e.state.pendingBuildOnSave.path.len > 0:
      let buildInfo = e.state.pendingBuildOnSave
      e.state.pendingBuildOnSave =
        (path: "", language: 0, customCmd: "", workspaceRoot: "")
      asyncSpawn runBuildAsync(e, buildInfo)

    # Handle pending QuickRun - spawn as background task
    if e.state.pendingQuickRun.cmd.len > 0:
      let qrInfo = e.state.pendingQuickRun
      e.state.pendingQuickRun = (cmd: "", args: @[], filePath: "", isTempFile: false)
      asyncSpawn runQuickRunAsync(e, qrInfo)

    # Handle pending syntax check - spawn as background task
    if e.state.pendingSyntaxCheck.path.len > 0:
      let checkInfo = e.state.pendingSyntaxCheck
      e.state.pendingSyntaxCheck = (path: "", language: 0)
      asyncSpawn runSyntaxCheckAsync(e, checkInfo)

proc handlePendingAsyncOperations*(
    e: Editor
): Future[void] {.async: (raises: [Exception]).} =
  ## Wrapper for handlePendingAsyncOperationsImpl with gcsafe cast
  {.cast(gcsafe).}:
    await handlePendingAsyncOperationsImpl(e)
