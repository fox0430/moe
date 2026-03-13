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
    editor, key_bindings, modes, buffer, logger, types, motion, filer, quick_run_utils,
    help_viewer, buffer_manager, bookmark_manager, backup_manager, backup, debug_viewer,
    config_loader, message_log, command_line, color, theme, terminal_mode,
    command_completion, render_utils, config_mode, log_viewer, syntax_checker,
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
      activeBuffer, e.state.display.showLineNumbers, e.state.display.showSidebar
    )

  e.handlerManager.motionController.viewportManager.updateViewport(
    cursorPos, lineCount, e.state.display.showStatusLine, e.state.viewportReservedLines,
    e.state.display.lineWrap, activeBuffer, lineNumOffset, e.state.display.tabStop,
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

proc processGotoLineResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer) =
  ## Process hrGotoLine: move cursor to the specified line number.
  let lineNum = r.lineNumber
  if lineNum > 0 and lineNum <= activeBuffer.len:
    e.activeWindow.cursor.line = lineNum - 1 # Convert to 0-based
    e.activeWindow.cursor.column = 0
    e.updateViewportForCursor(e.cursor)

proc enterFilerInActiveWindow*(e: Editor, path: string) =
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

proc enterTerminalInActiveWindow(e: Editor, command: string) =
  ## Switch the active window to Terminal mode.
  let activeWin = e.activeWindow
  let (cols, rows) = e.calculateTerminalAreaDimensions(activeWin)
  let termResult = newTerminalState(command, cols, rows)
  if termResult.isErr:
    e.state.statusMessage = "Terminal error: " & termResult.error
    return

  let termState = termResult.get
  termState.originalBuffer = activeWin.buffer
  activeWin.terminalState = some(termState)
  # Create a placeholder buffer (grid will be rendered directly)
  activeWin.buffer = newTextBuffer("")
  activeWin.cursor = BufferPosition(line: 0, column: 0)
  activeWin.viewport.topLine = 0
  activeWin.viewport.leftColumn = 0
  e.setMode(EditorMode.Terminal)
  activeWin.mode = EditorMode.Terminal

proc handleCommandModeKeyCombo*(e: Editor, keyCombo: KeyCombo): bool

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

  # Runtime key mapping check for command-line mode
  if not e.keyBindingRegistry.isReplayingMapping:
    let registry = e.keyBindingRegistry
    let mappings = registry.getRuntimeKeySeqMappings(EditorMode.Command)
    if mappings.len > 0:
      registry.runtimeMappingState.keys.add(keyCombo)
      let accKeys = registry.runtimeMappingState.keys
      var exactMatch: Option[RuntimeKeyMapping] = none(RuntimeKeyMapping)
      var hasLongerMatch = false
      for m in mappings:
        if m.triggerKeys == accKeys:
          exactMatch = some(m)
        elif m.triggerKeys.len > accKeys.len and
            m.triggerKeys[0 ..< accKeys.len] == accKeys:
          hasLongerMatch = true

      if exactMatch.isSome and not hasLongerMatch:
        # Exact match: execute mapping
        registry.clearRuntimeMappingState()
        registry.isReplayingMapping = true
        var replayResult = true
        for targetKeyStr in exactMatch.get.targetKeys:
          let targetKeyOpt = stringToKeyCombo(targetKeyStr)
          if targetKeyOpt.isSome:
            if not e.handleCommandModeKeyCombo(targetKeyOpt.get):
              replayResult = false
              break
        registry.isReplayingMapping = false
        return replayResult

      if hasLongerMatch:
        # Wait for more keys or timeout
        return true

      # No match: flush accumulated keys
      let keysToFlush = registry.runtimeMappingState.keys
      registry.clearRuntimeMappingState()
      registry.isReplayingMapping = true
      var flushResult = true
      for k in keysToFlush:
        if not e.handleCommandModeKeyCombo(k):
          flushResult = false
          break
      registry.isReplayingMapping = false
      return flushResult
    elif registry.runtimeMappingState.keys.len > 0:
      # No command-line mappings but keys accumulated (mappings removed) - flush
      let keysToFlush = registry.runtimeMappingState.keys
      registry.clearRuntimeMappingState()
      registry.isReplayingMapping = true
      var flushResult = true
      for k in keysToFlush:
        if not e.handleCommandModeKeyCombo(k):
          flushResult = false
          break
      registry.isReplayingMapping = false
      if not flushResult:
        return false
      # Fall through to process current key normally

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
          e.state.statusMessage = "QuickRun error: " & prepareResult.error
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
            e.state.statusMessage = quickRunStartupMessage(prepared.filePath)
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

        if not e.state.mode.isFileEditMode:
          # For special modes with split windows, remove the temporary buffer
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
        e.state.needsFullRedraw = true
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
        e.state.needsFullRedraw = true
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
              e.state.pendingBuildOnSave = (
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
            e.state.statusMessage = "Error: " & enewResult.error
      of hrStripWhitespace:
        # Handle strip trailing whitespace
        let count = r.strippedLineCount
        if count > 0:
          e.state.statusMessage =
            "Stripped trailing whitespace from " & $count & " lines"
          e.state.needsFullRedraw = true
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
            e.state.pendingQuickRun = (
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
          e.state.pendingBuildOnSave = (
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
      of hrEnterTerminal:
        overlayHandled = true
        let baseModeBeforeOverlay = e.state.baseMode
        e.state.exitOverlay()
        e.state.previousMode = baseModeBeforeOverlay
        e.enterTerminalInActiveWindow(r.enterTerminalCommand)
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
          e.state.statusMessage = "Failed to open LSP log: " & splitResult.error
        else:
          e.setMode(EditorMode.LogViewer)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.LogViewer
          activeWin.logViewerState = some(newLogViewerState(lckLsp))
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
          e.state.statusMessage = "Failed to open backup manager: " & splitResult.error
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
          e.state.display.showSidebar, e.state.display.showModifiedLines,
          e.state.display.lineWrap, e.state.display.tabStop,
          debugConfig.editorView.enable,
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
          e.state.statusMessage = "Jump list is empty"
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
      of hrChanges:
        overlayHandled = true
        # Handle change list command (:changes)
        let buf = e.activeBuffer()
        if buf.changeList.len == 0:
          e.state.statusMessage = "No changes"
        else:
          e.state.tempMessages = @[]
          e.state.tempMessages.add("change  line  col  text")
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
            e.state.tempMessages.add(
              marker & ($changeNum).align(4) & " " & ($lineNum).align(5) & " " &
                ($colNum).align(4) & "  " & text
            )
          # Current position row (show > only when at the end of changelist)
          let w = e.activeWindow
          let curMarker =
            if buf.changeListIndex == buf.changeList.len - 1: ">" else: " "
          e.state.tempMessages.add(
            curMarker & "0".align(4) & " " & ($(w.cursor.line + 1)).align(5) & " " &
              ($(w.cursor.column + 1)).align(4) & "  "
          )
          e.state.needsFullRedraw = true
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
        bkmState.originalBuffer = activeWin.buffer
        activeWin.buffer = bkmState.createBookmarkManagerTextBuffer()
        activeWin.cursor = BufferPosition(line: 0, column: 0)
        activeWin.viewport.topLine = 0
        activeWin.viewport.leftColumn = 0
        activeWin.bookmarkManagerState = some(bkmState)
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
          e.state.statusMessage = "Failed to open config: " & splitResult.error
        else:
          let baseModeBeforeOverlay = e.state.baseMode
          e.state.exitOverlay()
          e.state.previousMode = baseModeBeforeOverlay
          e.setMode(EditorMode.Config)
          let activeWin = e.activeWindow
          activeWin.mode = EditorMode.Config
          activeWin.configModeState = some(newConfigModeState(e.config))
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
          hrIncreaseWindowWidth, hrDecreaseWindowWidth, hrEqualizeWindows,
          hrLspGotoDefinition, hrLspGotoDeclaration, hrLspFindReferences,
          hrLspCodeLensExecute, hrLspTypeDefinition, hrLspImplementation, hrLspHover,
          hrLspRename, hrLspSelectionRange, hrLspDocumentLink, hrConfigQuit,
          hrConfigSaveConfig, hrDebugViewerQuit, hrLogViewerQuit, hrTerminalQuit,
          hrExecCommand:
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
    # commandText includes the ":" prefix, so max cursor position is len - 1
    let maxPos = e.state.commandText.len - 1
    if e.state.commandCursor < maxPos:
      e.state.commandCursor += 1
      e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle Backspace - delete character before cursor
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    e.state.commandState.historyIndex = -1
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
      e.state.commandCursor = e.state.commandText.len - 1
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
        e.state.commandCursor = e.state.commandText.len - 1
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
