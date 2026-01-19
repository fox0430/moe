#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import std/[options, os, strutils, tables, monotimes]

import pkg/[celina, results]

import
  editor, keybindings, modes, buffer, logger, types, cursor, motion, search_utils,
  filer, quickrunutils, helpviewer, buffermanager, backupmanager, backup, diffviewer,
  command_completion, build, render_utils, sidebar, debugviewer, configloader,
  references_viewer, documentsymbol_viewer, messagelog, commandline
import command_handlers/handler_manager

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
  let activeBuffer = e.activeBuffer()
  let lineCount = activeBuffer.len
  let cursorPos = CursorPosition(x: pos.column, y: pos.line)

  e.handlerManager.motionController.viewportManager.updateViewport(
    cursorPos,
    lineCount,
    e.state.display.showStatusLine,
    e.state.viewportReservedLines,
    false, # Force immediate scroll
    activeBuffer,
    0, # lineNumOffset
  )

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
      activeBuffer.findNext(e.state.search.text, e.state.cursor, shouldIgnoreCase)
    else:
      activeBuffer.findPrev(e.state.search.text, e.state.cursor, shouldIgnoreCase)

  if searchResult.isSome:
    let pos = searchResult.get
    e.state.cursor = pos
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
      e.updateViewportForCursor(e.state.cursor)
      e.state.needsFullRedraw = true
    else:
      # If incsearch is disabled, perform search now
      discard e.executeSearchFromCurrentPosition()

  # Return to previous mode (Normal or LogViewer)
  let targetMode =
    if e.state.previousMode == EditorMode.LogViewer:
      EditorMode.LogViewer
    else:
      EditorMode.Normal
  e.state.previousMode = e.state.mode
  e.state.mode = targetMode
  e.state.search.text = ""
  # Reset history navigation index
  e.state.search.historyIndex = -1

proc cancelSearch(e: Editor) =
  ## Cancel search and return to previous mode
  ##
  ## Called when: Escape is pressed in Search mode
  ##
  ## Behavior:
  ## - If incsearch enabled: Restore cursor to original position (searchStartPos)
  ## - Transition back to previous mode
  ## - Clear searchText buffer
  ## - Does NOT save to lastSearchText (search was cancelled)
  if e.state.search.incsearch:
    e.state.cursor = e.state.search.startPos
  e.state.mode = e.state.previousMode
  e.state.search.text = ""
  # Reset history navigation index
  e.state.search.historyIndex = -1

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
    e.state.cursor = pos

    # Update viewport to follow cursor
    e.updateViewportForCursor(pos)

    e.state.setStatusMessage("Found: " & e.state.search.text)
    e.state.needsFullRedraw = true
  else:
    # No match found, restore to start position
    e.state.cursor = e.state.search.startPos
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
    e.state.search.text = e.state.search.text[0 ..^ 2]
    e.performIncrementalSearch()
  e.state.needsFullRedraw = true

proc handleCommandModeEvent(e: Editor, event: Event): bool =
  ## Handle Command mode events (special handling for text input)
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  let keyCombo = keyComboOpt.get

  # Handle Escape to exit Command mode and return to previous mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.state.commandCompletionManager.cancelCompletion()
    # Cancel substitute preview and restore original content
    e.cancelSubstitutePreview()
    e.state.mode = e.state.previousMode
    e.state.commandText = ""
    e.state.commandCursor = 0
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
        activeBuffer, commandToExecute, isShared, e.state.cursor.line
      )

      # Add to command history (without the leading ":")
      if commandToExecute.len > 1:
        e.addCommandToHistory(commandToExecute[1 ..^ 1])

      if r.shouldQuit():
        return false # Signal app should quit

      if r.shouldCloseWindow():
        # Handle window close - may also quit if last window
        # If we're closing from LogViewer mode, clear LogViewer state
        if e.state.previousMode == EditorMode.LogViewer:
          e.state.logViewerState = none(LogViewerState)
          e.state.previousMode = EditorMode.Normal
        let shouldQuit = e.closeWindow
        if shouldQuit:
          return false # Last window closed, quit editor

      if r.shouldGotoLine():
        # Jump to the specified line
        let lineNum = r.getLineNumber()
        if lineNum > 0 and lineNum <= activeBuffer.len:
          e.state.cursor.line = lineNum - 1 # Convert to 0-based
          e.state.cursor.column = 0
          # Update viewport to make the line visible
          e.updateViewportForCursor(e.state.cursor)

      if r.shouldVSplit():
        # Handle vertical split
        let splitResult = e.vsplit(r.getVSplitFilename())
        if splitResult.isErr:
          logError("handler", "Vertical split failed: " & splitResult.error)
          e.state.setStatusMessage("Error: " & splitResult.error)

      if r.shouldHSplit():
        # Handle horizontal split
        let splitResult = e.hsplit(r.getHSplitFilename())
        if splitResult.isErr:
          logError("handler", "Horizontal split failed: " & splitResult.error)
          e.state.setStatusMessage("Error: " & splitResult.error)

      if r.shouldEnew():
        # Handle enew (create new empty buffer)
        let enewResult = e.enew()
        if enewResult.isErr:
          logError("handler", "Enew failed: " & enewResult.error)
          e.state.setStatusMessage("Error: " & enewResult.error)

      if r.shouldNew():
        # Handle new (create new empty buffer in horizontal split)
        let newResult = e.new()
        if newResult.isErr:
          logError("handler", "New failed: " & newResult.error)
          e.state.setStatusMessage("Error: " & newResult.error)

      if r.shouldVnew():
        # Handle vnew (create new empty buffer in vertical split)
        let vnewResult = e.vnew()
        if vnewResult.isErr:
          logError("handler", "Vnew failed: " & vnewResult.error)
          e.state.setStatusMessage("Error: " & vnewResult.error)

      if r.shouldEdit():
        # Handle edit (open file in current window)
        let editResult = e.editFile(r.getEditFilename())
        if editResult.isErr:
          logError("handler", "Edit failed: " & editResult.error)
          e.state.setStatusMessage("Error: " & editResult.error)
        else:
          e.state.setStatusMessage("Opened: " & r.getEditFilename())

      if r.shouldSetBoolOption():
        # Handle boolean option setting
        let opt = r.getBoolOption()
        let val = r.getBoolValue()
        case opt
        of bsoNumber:
          e.config.standard.number = val
          e.state.setStatusMessage("number = " & $val)
        of bsoCurrentNumber:
          e.config.standard.currentNumber = val
          e.state.setStatusMessage("currentnumber = " & $val)
        of bsoCursorLine:
          e.config.standard.cursorLine = val
          e.state.display.showCursorLine = val
          e.state.setStatusMessage("cursorline = " & $val)
        of bsoStatusLine:
          e.config.standard.statusLine = val
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
          e.config.standard.cursorLine = val # Keep both settings in sync
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
        e.state.needsFullRedraw = true

      if r.shouldSetIntOption():
        # Handle integer option setting
        let opt = r.getIntOption()
        let val = r.getIntValue()
        case opt
        of isoTabStop:
          e.config.standard.tabStop = val
          e.state.setStatusMessage("tabstop = " & $val)
        e.state.needsFullRedraw = true

      if r.shouldSetFloatOption():
        # Handle float option setting
        let opt = r.getFloatOption()
        let val = r.getFloatValue()
        case opt
        of fsoScrollFriction:
          e.config.smoothScroll.friction = val
          e.state.setStatusMessage("scrollfriction = " & $val)
        of fsoScrollAirDrag:
          e.config.smoothScroll.airDrag = val
          e.state.setStatusMessage("scrollairdrag = " & $val)
        e.state.needsFullRedraw = true

      if r.shouldClearSearchHighlight():
        # Handle clear search highlight (:noh)
        e.state.search.hlsearch = false
        e.state.needsFullRedraw = true

      if r.shouldShellCommand():
        # Handle shell command (:!command)
        let cmd = r.getShellCommand()
        if cmd.len > 0:
          var exitCode: int
          e.app.suspend()
          try:
            # Execute the shell command
            exitCode = execShellCmd(cmd)

            # Wait for user to press Enter
            stdout.write("\nPress Enter to continue...")
            stdout.flushFile()
            discard stdin.readLine()
          finally:
            e.app.resume()

          e.state.needsFullRedraw = true

          if exitCode == 0:
            e.state.setStatusMessage("Shell command completed")
          else:
            e.state.setStatusMessage("Shell command exited with code " & $exitCode)

      if r.shouldBackground():
        # Handle background command (:bg)
        # Pause editor and show recent terminal output
        e.app.suspend()
        try:
          # Wait for user to press Enter
          stdout.write("Press Enter to return to editor...")
          stdout.flushFile()
          discard stdin.readLine()
        finally:
          e.app.resume()

        e.state.needsFullRedraw = true

      if r.shouldJumpList():
        # Handle jump list command (:ju, :jump)
        # Display jump list temporarily like Vim using tempMessages
        if e.state.jumpList.len == 0:
          e.state.setStatusMessage("Jump list is empty")
        else:
          e.state.tempMessages = @[]
          e.state.tempMessages.add(" jump  line  col  file/text")
          for i, pos in e.state.jumpList:
            let marker = if i == e.state.jumpListIndex: ">" else: " "
            let jumpNum = e.state.jumpList.len - i
            let lineNum = pos.line + 1 # 1-based for display
            let colNum = pos.column + 1 # 1-based for display
            e.state.tempMessages.add(
              marker & ($jumpNum).align(4) & " " & ($lineNum).align(5) & " " &
                ($colNum).align(4)
            )
          e.state.needsFullRedraw = true
        # Return to Normal mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Normal

      if r.shouldSave():
        # Handle file save
        let saveResult = e.saveFile(r.getSaveFilename(), r.getForceSave())
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
            let buildResult = startBackgroundBuildOnSave(
              savedPath, activeBuffer.language, customCmd, workspaceRoot
            )
            if buildResult.isErr:
              # Always show errors
              e.state.setStatusMessage("Build error: " & buildResult.error)
              logError("handler", "Build on save failed: " & buildResult.error)
            else:
              var buildProcess = buildResult.get
              # Build on save screen notification (controlled by config)
              if e.config.notification.screenNotifications and
                  e.config.notification.buildOnSaveScreenNotify:
                e.state.setStatusMessage("Building: " & savedPath)
              # Build on save log notification (controlled by config)
              if e.config.notification.logNotifications and
                  e.config.notification.buildOnSaveLogNotify:
                logInfo("handler", "Build on save started: " & savedPath)

              # Wait for the process to finish and get the result
              let output = buildProcess.process.waitFor()
              # Create a new buffer with the output
              let outputContent = output.join("\n")
              let outputBuffer = newTextBuffer(outputContent)
              outputBuffer.readOnly = true

              # Open the output in a new horizontal split window
              let splitResult = e.hsplitWithBuffer(outputBuffer)
              if splitResult.isErr:
                # Always show errors
                e.state.setStatusMessage(
                  "Failed to open output window: " & splitResult.error
                )
                logError(
                  "handler", "Build on save window split failed: " & splitResult.error
                )
              else:
                # Build on save screen notification (controlled by config)
                if e.config.notification.screenNotifications and
                    e.config.notification.buildOnSaveScreenNotify:
                  e.state.setStatusMessage("Build completed: " & savedPath)
                # Build on save log notification (controlled by config)
                if e.config.notification.logNotifications and
                    e.config.notification.buildOnSaveLogNotify:
                  logInfo("handler", "Build on save completed: " & savedPath)

      if r.shouldSaveAndQuit():
        # Handle file save and quit
        let saveResult =
          e.saveFile(r.getSaveAndQuitFilename(), r.getForceQuitAfterSave())
        if saveResult.isErr:
          logError("handler", "Save and quit failed: " & saveResult.error)
          e.state.setStatusMessage("Error: " & saveResult.error)
        else:
          # Save succeeded, now quit
          logInfo("handler", "File saved, quitting editor")
          return false # Signal app should quit

      if r.shouldBufferNext():
        # Handle switch to next buffer
        e.switchToNextBuffer()

      if r.shouldBufferPrev():
        # Handle switch to previous buffer
        e.switchToPrevBuffer()

      if r.shouldBufferFirst():
        # Handle switch to first buffer
        e.switchToFirstBuffer()

      if r.shouldBufferLast():
        # Handle switch to last buffer
        e.switchToLastBuffer()

      if r.shouldBuffer():
        # Handle switch to buffer by number or name
        discard e.switchToBuffer(r.getBufferArg())

      if r.shouldBufferDelete():
        # Handle buffer delete (close window)
        let shouldQuit = e.closeWindow()
        if shouldQuit:
          # Last buffer deleted, create a new empty buffer instead of quitting
          let enewResult = e.enew()
          if enewResult.isErr:
            logError("handler", "Enew failed after buffer delete: " & enewResult.error)
            e.state.setStatusMessage("Error: " & enewResult.error)

      if r.shouldStripWhitespace():
        # Handle strip trailing whitespace
        let count = r.getStrippedLineCount()
        if count > 0:
          e.state.setStatusMessage(
            "Stripped trailing whitespace from " & $count & " lines"
          )
          e.state.needsFullRedraw = true
        else:
          e.state.setStatusMessage("No trailing whitespace found")

      if r.shouldQuickRun() or e.state.requestQuickRun:
        # Reset request flag if set
        e.state.requestQuickRun = false
        # Handle QuickRun command
        let quickRunResult = startBackgroundQuickRun(activeBuffer, e.config)
        if quickRunResult.isErr:
          # Always show errors
          e.state.setStatusMessage("QuickRun error: " & quickRunResult.error)
          logError("handler", "QuickRun failed: " & quickRunResult.error)
        else:
          var qrProcess = quickRunResult.get
          # QuickRun screen notification (controlled by config)
          if e.config.notification.screenNotifications and
              e.config.notification.quickRunScreenNotify:
            e.state.setStatusMessage(quickRunStartupMessage(qrProcess.filePath))

          # Wait for the process to finish and get the result
          let outputResult = qrProcess.waitForResult()
          if outputResult.isErr:
            # Always show errors
            e.state.setStatusMessage("QuickRun error: " & outputResult.error)
          else:
            let output = outputResult.get
            # Create a new buffer with the output
            let outputContent = output.join("\n")
            let outputBuffer = newTextBuffer(outputContent)
            # Mark as read-only since it's just output
            outputBuffer.readOnly = true

            # Open the output in a new horizontal split window
            let splitResult = e.hsplitWithBuffer(outputBuffer)
            if splitResult.isErr:
              # Always show errors
              e.state.setStatusMessage(
                "Failed to open output window: " & splitResult.error
              )
              logError("handler", "QuickRun window split failed: " & splitResult.error)
            else:
              # QuickRun screen notification (controlled by config)
              if e.config.notification.screenNotifications and
                  e.config.notification.quickRunScreenNotify:
                e.state.setStatusMessage("QuickRun completed: " & qrProcess.filePath)
              # QuickRun log notification (controlled by config)
              if e.config.notification.logNotifications and
                  e.config.notification.quickRunLogNotify:
                logInfo("handler", "QuickRun completed: " & qrProcess.filePath)
        # Return to Normal mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Normal

      if r.shouldBuild():
        # Handle Build command
        let filePath =
          if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: ""
        if filePath.len == 0:
          e.state.setStatusMessage("Build error: File not saved")
          logError("handler", "Build failed: No file path")
        else:
          let buildResult =
            startBackgroundBuild(filePath, activeBuffer.language, parentDir(filePath))
          if buildResult.isErr:
            e.state.setStatusMessage("Build error: " & buildResult.error)
            logError("handler", "Build failed: " & buildResult.error)
          else:
            var buildProcess = buildResult.get
            e.state.setStatusMessage("Building: " & filePath)

            # Wait for the process to finish and get the result
            let output = buildProcess.process.waitFor()
            # Create a new buffer with the output
            let outputContent = output.join("\n")
            let outputBuffer = newTextBuffer(outputContent)
            outputBuffer.readOnly = true

            # Open the output in a new horizontal split window
            let splitResult = e.hsplitWithBuffer(outputBuffer)
            if splitResult.isErr:
              e.state.setStatusMessage(
                "Failed to open output window: " & splitResult.error
              )
              logError("handler", "Build window split failed: " & splitResult.error)
            else:
              e.state.setStatusMessage("Build completed: " & filePath)
              logInfo("handler", "Build completed: " & filePath)
        # Return to Normal mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Normal

      if r.kind == hrSubstitute:
        # Handle substitute result - display count
        let count = r.hrSubstituteCount
        e.state.setStatusMessage(
          $count & " substitution" & (if count == 1: "" else: "s")
        )
        e.state.needsFullRedraw = true
        # Return to Normal mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Normal

      if r.shouldEnterFiler():
        # Enter filer mode with optional path
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Filer
        let filerPath = r.getEnterFilerPath()
        let startPath =
          if filerPath.isSome:
            filerPath.get
          elif activeBuffer.filePath.isSome:
            parentDir(activeBuffer.filePath.get)
          else:
            getCurrentDir()
        e.state.filerState = some(newFilerState(startPath))
      elif r.shouldEnterLogViewer():
        # Open LogViewer in a new split window for editor messages
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
          e.state.mode = EditorMode.LogViewer
          e.state.logViewerState = some(newLogViewerState(lckEditor))
      elif r.shouldLspLog():
        # Open LogViewer in a new split window for LSP messages
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
          e.state.mode = EditorMode.LogViewer
          e.state.logViewerState = some(newLogViewerState(lckLsp))
      elif r.shouldEnterHelpViewer():
        # Enter help viewer mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Help
        e.state.helpViewerState = some(newHelpViewerState())
      elif r.shouldEnterBufferManager():
        # Enter buffer manager mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.BufferManager
        let bmState = newBufferManagerState()
        bmState.updateEntries(e.getBufferInfos())
        bmState.previousWindowIndex = e.windowManager.activeWindowIndex
        e.state.bufferManagerState = some(bmState)
      elif r.shouldEnterBackupManager():
        # Enter backup manager mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.BackupManager
        let baseBackupDir = e.config.autoBackup.getBaseBackupDir()
        var sourceFilePath = ""
        if e.buffer.filePath.isSome:
          sourceFilePath = absolutePath(e.buffer.filePath.get)
        let bkState = initBackupManagerState(baseBackupDir, sourceFilePath)
        e.state.backupManagerState = some(bkState)
      elif r.shouldEnterRecentFileMode():
        # Enter recent file mode
        let loadResult = e.enterRecentFileMode()
        if loadResult.isErr:
          logError("handler", "Failed to enter Recent File mode: " & loadResult.error)
          e.state.statusMessage = "Error: " & loadResult.error
        else:
          e.state.previousMode = e.state.mode
          e.state.mode = EditorMode.RecentFile
          e.state.statusMessage = ""
      elif r.shouldEnterDebugViewer():
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
          debugLines, e.state.mode, e.state.previousMode, e.state.cursor.line,
          e.state.cursor.column, e.state.commandText, e.state.statusMessage,
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
        let debugContent = debugLines.join("\n")
        let debugBuffer = newTextBuffer(debugContent)
        debugBuffer.readOnly = true
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
        # Return to Normal mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Normal
      elif r.shouldEnterConfigMode():
        # Enter configuration mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Config
        e.state.configModeState = some(newConfigModeState(e.config))
      else:
        # Handle mode transitions
        let modeTransition = r.getModeTransition()
        if modeTransition.isSome:
          # Entering a new mode (e.g., Filer) - previousMode already set when entering Command
          e.state.mode = modeTransition.get
        else:
          # Return to the mode we were in before entering Command mode
          e.state.mode = e.state.previousMode

      # Set status message if any
      let statusMsg = r.getStatusMessage()
      if statusMsg.len > 0:
        e.state.setStatusMessage(statusMsg)
    else:
      # Empty command, just return to previous mode
      e.state.mode = e.state.previousMode

    # Clear command text and cursor
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
      # Handle substitute command preview
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
          # No longer have replacement, cancel preview
          e.cancelSubstitutePreview()
        else:
          e.state.needsFullRedraw = true
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
      # Handle substitute command preview
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
    # Handle substitute command preview
    if e.state.commandText.contains("s/"):
      let pattern = extractSubstitutePattern(e.state.commandText)
      let (replacement, hasReplacement) =
        extractSubstituteReplacement(e.state.commandText)
      let flags = extractSubstituteFlags(e.state.commandText)
      let isGlobal = "g" in flags
      if hasReplacement and pattern.len > 0 and e.config.highlight.replaceText:
        # Start preview if not active
        if not e.state.substitutePreview.isActive:
          e.startSubstitutePreview()
        # Update preview with current pattern and replacement
        e.updateSubstitutePreview(pattern, replacement, isGlobal)
      else:
        # No replacement yet, just highlight pattern
        e.state.needsFullRedraw = true
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
          e.state.cursor = e.state.search.startPos
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

  let r = e.handlerManager.handleRecentFileMode(
    e.recentFileModeState, viewportHeight, keyCombo
  )

  if r.shouldQuitRecentFileMode():
    e.state.previousMode = e.state.mode
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = ""
    e.state.needsFullRedraw = true
    return true

  if r.shouldNextWindow():
    if e.windowManager.windows.len > 1:
      e.windowManager.activeWindowIndex =
        (e.windowManager.activeWindowIndex + 1) mod e.windowManager.windows.len
      e.state.needsFullRedraw = true
    return true

  if r.shouldPrevWindow():
    if e.windowManager.windows.len > 1:
      e.windowManager.activeWindowIndex =
        (e.windowManager.activeWindowIndex - 1 + e.windowManager.windows.len) mod
        e.windowManager.windows.len
      e.state.needsFullRedraw = true
    return true

  if r.shouldOpenRecentFile():
    let filePath = r.getRecentFilePath()
    # Check if file exists before trying to open
    if not fileExists(filePath):
      logError("handler", "File not found: " & filePath)
      e.state.statusMessage = "File not found: " & filePath
      # Stay in Recent File mode so user can select another file
      e.state.needsFullRedraw = true
      return true
    # Load the file
    let loadResult = e.loadFile(filePath)
    if loadResult.isErr:
      logError("handler", "Failed to open file: " & loadResult.error)
      e.state.statusMessage = "Error: " & loadResult.error
    else:
      e.state.statusMessage = "Opened: " & filePath
    e.state.previousMode = e.state.mode
    e.state.mode = EditorMode.Normal
    e.state.needsFullRedraw = true
    return true

  # Handle mode transitions (e.g., entering Command mode with :)
  let modeTransition = r.getModeTransition()
  if modeTransition.isSome:
    e.state.previousMode = e.state.mode
    e.state.mode = modeTransition.get
    if modeTransition.get == EditorMode.Command:
      e.state.commandText = ":"
      e.state.commandCursor = 0

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

  let r = handleDebugModeKey(e.state, viewportHeight, keyCombo)

  case r.kind
  of dvrQuit:
    e.state.debugViewerState = none(DebugViewerState)
    e.state.previousMode = e.state.mode
    e.state.mode = EditorMode.Normal
    e.state.statusMessage = ""
    e.state.needsFullRedraw = true
    return true
  of dvrEnterCommand:
    e.state.previousMode = e.state.mode
    e.state.mode = EditorMode.Command
    e.state.commandText = ":"
    e.state.commandCursor = 0
    e.state.needsFullRedraw = true
    return true
  of dvrHandled, dvrUnhandled, dvrError:
    e.state.needsFullRedraw = true
    return true

const FilerHeaderLines = 2 ## Filer mode header: title + separator

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
    # Split the pasted text into lines and insert each
    var pos = e.state.cursor

    # Insert the entire text at once - this bypasses auto-indent
    # because we're not going through insertNewline()
    discard activeBuffer.insertText(pos, pastedText)

    # Calculate new cursor position after paste
    # Count newlines and find position on last line
    var newLine = pos.line
    var newColumn = pos.column
    for ch in pastedText:
      if ch == '\n':
        newLine += 1
        newColumn = 0
      else:
        newColumn += 1

    e.state.cursor.line = newLine
    e.state.cursor.column = newColumn
    e.state.needsFullRedraw = true
  of EditorMode.Normal:
    # In Normal mode: Enter Insert mode first, then paste
    # Begin a transaction for undo support
    let transactionResult = activeBuffer.beginTransaction("Paste")
    if transactionResult.isErr:
      e.state.setStatusMessage("Paste failed: " & transactionResult.error)
      return true

    # Record insert start position for text tracking
    e.state.editState.insertModeStartPos = some(e.state.cursor)

    # Insert the pasted text
    var pos = e.state.cursor
    discard activeBuffer.insertText(pos, pastedText)

    # Calculate new cursor position
    var newLine = pos.line
    var newColumn = pos.column
    for ch in pastedText:
      if ch == '\n':
        newLine += 1
        newColumn = 0
      else:
        newColumn += 1

    e.state.cursor.line = newLine
    e.state.cursor.column = newColumn

    # Commit the transaction
    discard activeBuffer.commitTransaction()

    e.state.needsFullRedraw = true
    e.state.setStatusMessage("Pasted " & $pastedText.len & " characters")
  else:
    # For other modes, just show a message
    e.state.setStatusMessage("Paste not supported in this mode")

  return true

proc screenToBufferPosition(
    vp: ViewPort,
    buffer: TextBuffer,
    mouseX, mouseY: int,
    lineNumOffset, reservedLines: int,
    lineWrap: bool,
): Option[BufferPosition] =
  ## Convert screen coordinates to buffer position.
  ## Returns none if click is outside the text area.
  ## Note: lineWrap handling is simplified; accurate wrap calculation would
  ## require iterating through wrapped lines.
  let
    screenY = mouseY - vp.y
    screenX = mouseX - vp.x - lineNumOffset

  # Check if click is within the text area
  if screenY < 0 or screenY >= vp.height - reservedLines:
    return none(BufferPosition)
  if screenX < 0:
    return none(BufferPosition)

  # Calculate buffer line
  var bufferLine = vp.topLine + screenY
  if bufferLine >= buffer.len:
    bufferLine = max(0, buffer.len - 1)

  # Calculate buffer column
  var bufferColumn =
    if lineWrap:
      screenX
    else:
      vp.leftColumn + screenX

  # Clamp column to valid range
  if bufferLine >= 0 and bufferLine < buffer.len:
    let lineLen = buffer[bufferLine].len
    bufferColumn = clamp(bufferColumn, 0, max(0, lineLen - 1))

  return some(BufferPosition(line: bufferLine, column: bufferColumn))

proc calculateLineNumOffsetForMouse(e: Editor, buffer: TextBuffer): int =
  ## Calculate the total offset for line numbers and sidebar
  let sidebarWidth = if e.state.display.showSidebar: DefaultSidebarWidth else: 0
  calculateLineNumOffset(buffer, e.state.display.showLineNumbers) + sidebarWidth +
    LineNumberPadding

proc handleMouseEvent(e: Editor, event: Event): bool =
  ## Handle mouse events for cursor movement
  ## Returns true if the event was handled, false otherwise
  if event.kind != EventKind.Mouse:
    return false

  let mouse = event.mouse

  # Only handle left button press (not release, move, or drag)
  if mouse.button != celina.MouseButton.Left:
    return false
  if mouse.kind != celina.MouseEventKind.Press:
    return false

  # Handle mouse click in text editing modes
  if e.state.mode in {
    EditorMode.Normal, EditorMode.Insert, EditorMode.Visual, EditorMode.VisualLine,
    EditorMode.VisualBlock, EditorMode.Replace,
  }:
    # Multiple windows mode
    if e.windowManager.windows.len > 1:
      for i, window in e.windowManager.windows:
        let vp = window.viewport
        # Check if click is within this window's viewport
        if mouse.x >= vp.x and mouse.x < vp.x + vp.width and mouse.y >= vp.y and
            mouse.y < vp.y + vp.height:
          let
            lineNumOffset = e.calculateLineNumOffsetForMouse(window.buffer)
            # Each window has its own status line
            reservedLines = if e.state.display.showStatusLine: 1 else: 0
            posOpt = screenToBufferPosition(
              vp, window.buffer, mouse.x, mouse.y, lineNumOffset, reservedLines,
              e.state.display.lineWrap,
            )

          if posOpt.isNone:
            return false

          let pos = posOpt.get

          # Switch to clicked window if not already active
          if i != e.windowManager.activeWindowIndex:
            e.windowManager.activeWindowIndex = i
            for j, w in e.windowManager.windows.mpairs:
              w.active = (j == i)

          # Update cursor
          e.windowManager.windows[i].cursor = pos
          e.state.cursor = pos
          e.state.needsFullRedraw = true
          return true

      return false

    # Single window mode
    let
      activeBuffer = e.activeBuffer()
      lineNumOffset = e.calculateLineNumOffsetForMouse(activeBuffer)
      # Status line + command line
      reservedLines = if e.state.display.showStatusLine: 2 else: 1
      posOpt = screenToBufferPosition(
        e.viewport, activeBuffer, mouse.x, mouse.y, lineNumOffset, reservedLines,
        e.state.display.lineWrap,
      )

    if posOpt.isNone:
      return false

    e.state.cursor = posOpt.get
    e.state.needsFullRedraw = true
    return true

  # Handle mouse click in Filer mode
  if e.state.mode == EditorMode.Filer and e.state.filerState.isSome:
    var filerState = e.state.filerState.get
    let clickedIndex = filerState.topLine + (mouse.y - FilerHeaderLines)

    if clickedIndex >= 0 and clickedIndex < filerState.entries.len:
      filerState.selectedIndex = clickedIndex
      e.state.filerState = some(filerState)
      e.state.needsFullRedraw = true
      return true

  return false

proc handleEvent*(e: Editor, event: Event): bool =
  ## Main event handler using the new handler manager system

  # Update last input time for auto backup idle detection
  e.updateInputTime()

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

      # If ":" was pressed, enter command mode
      if not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char == ":":
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Command
        e.state.commandText = ":"
        e.state.commandCursor = 0
      # Otherwise just dismiss and stay in current mode
      return true

  # Handle Command mode input differently (character by character)
  if e.state.mode == EditorMode.Command:
    return handleCommandModeEvent(e, event)

  # Handle Search mode input differently (character by character)
  if e.state.mode == EditorMode.Search:
    return handleSearchModeEvent(e, event)

  # Handle Recent File mode input
  if e.state.mode == EditorMode.RecentFile:
    return handleRecentFileModeEvent(e, event)

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
        discard e.codeLensPickerConfirm()
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
          if e.codeLensPickerSelectByNumber(num):
            return true
          # If number is out of range, just ignore
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
        if e.state.command.len > 0:
          e.state.command = ""
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

      # Check if we're in window command mode (waiting for second key after Ctrl-w)
      if e.state.command == "window_cmd":
        e.state.command = "" # Reset command state

        # Handle second key: j (down/prev), k (up/next), c (close)
        if not keyCombo.isSpecial:
          if keyCombo.char == "j":
            e.switchToPrevWindow
            return true
          elif keyCombo.char == "k":
            e.switchToNextWindow
            return true
          elif keyCombo.char == "c":
            # Close current window
            let shouldQuit = e.closeWindow()
            if shouldQuit:
              return false # Last window closed, quit editor
            return true
          else:
            # Unknown window command, just cancel
            return true

      # Check for Ctrl-w to enter window command mode
      if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers:
        if keyCombo.char == "w":
          e.state.command = "window_cmd"
          return true

  # For other modes, use the unified handler manager with active buffer
  let activeBuffer = e.activeBuffer

  # Get the active viewport if in split mode and sync with motion controller
  var activeViewport = e.viewport
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    activeViewport = e.windowManager.windows[e.windowManager.activeWindowIndex].viewport
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
      activeWindow = e.windowManager.windows[e.windowManager.activeWindowIndex]
      windowBottomY = activeWindow.viewport.y + activeWindow.viewport.height
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

    # Add extra lines for multi-line status messages (only for bottom window)
    if isBottomWindow:
      e.state.viewportReservedLines += e.state.statusMessageExtraLines()
  else:
    # Single window mode - use default calculation
    e.state.viewportReservedLines = if e.state.display.showStatusLine: 2 else: 1

    # Add extra lines for multi-line status messages
    e.state.viewportReservedLines += e.state.statusMessageExtraLines()
    # Sync the motion controller's viewport with the editor's viewport
    e.executer.motionController.viewportManager.viewport = e.viewport

  let r = e.handlerManager.handleEvent(activeBuffer, e.state, activeViewport, event)

  # For LogViewer mode, update viewport to follow cursor
  # (LogViewer handles cursor directly without using MotionController)
  if e.state.mode == EditorMode.LogViewer:
    e.updateViewportForCursor(e.state.cursor)

  # Sync viewport and cursor back from state to active window
  if e.windowManager.windows.len > 0 and
      e.windowManager.activeWindowIndex < e.windowManager.windows.len:
    e.windowManager.windows[e.windowManager.activeWindowIndex].viewport =
      e.executer.motionController.viewportManager.viewport
    e.windowManager.windows[e.windowManager.activeWindowIndex].cursor = e.state.cursor
  else:
    # Single window mode - sync viewport from motionController
    e.viewport = e.executer.motionController.viewportManager.viewport

  # Process the result
  if r.shouldQuit():
    return false # Signal app should quit

  if r.shouldSaveAndQuit():
    # Handle file save and quit
    let saveResult = e.saveFile(r.getSaveAndQuitFilename(), r.getForceQuitAfterSave())
    if saveResult.isErr:
      logError("handler", "Save and quit failed: " & saveResult.error)
      e.state.setStatusMessage("Error: " & saveResult.error)
    else:
      # Save succeeded, now quit
      logInfo("handler", "File saved, quitting editor")
      return false # Signal app should quit

  if r.shouldGotoLine():
    # Jump to the specified line
    let lineNum = r.getLineNumber()
    if lineNum > 0 and lineNum <= activeBuffer.len:
      e.state.cursor.line = lineNum - 1 # Convert to 0-based
      e.state.cursor.column = 0
      # Update viewport to make the line visible
      e.updateViewportForCursor(e.state.cursor)

  # Handle Filer mode results
  if r.kind == hrFilerOpenFile:
    # Open file from filer
    let loadResult = e.loadFile(r.filerFilePath)
    if loadResult.isErr:
      e.state.setStatusMessage("Error: " & loadResult.error)
    else:
      # Clear filer state and switch to Normal mode
      e.state.filerState = none(FilerState)
      e.state.mode = EditorMode.Normal
      e.state.cursor = BufferPosition(line: 0, column: 0)
      # Filer screen notification (controlled by config)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.state.setStatusMessage("Opened: " & r.filerFilePath)
      # Filer log notification (controlled by config)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file: " & r.filerFilePath)
    return true

  if r.kind == hrFilerOpenFileVSplit:
    # Open file in vertical split from filer
    let splitResult = e.vsplit(some(r.filerFilePath))
    if splitResult.isErr:
      e.state.setStatusMessage("Error: " & splitResult.error)
    else:
      # Clear filer state and switch to Normal mode
      e.state.filerState = none(FilerState)
      e.state.mode = EditorMode.Normal
      # Filer screen notification (controlled by config)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.state.setStatusMessage("Opened in vsplit: " & r.filerFilePath)
      # Filer log notification (controlled by config)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file in vsplit: " & r.filerFilePath)
    return true

  if r.kind == hrFilerOpenFileHSplit:
    # Open file in horizontal split from filer
    let splitResult = e.hsplit(some(r.filerFilePath))
    if splitResult.isErr:
      e.state.setStatusMessage("Error: " & splitResult.error)
    else:
      # Clear filer state and switch to Normal mode
      e.state.filerState = none(FilerState)
      e.state.mode = EditorMode.Normal
      # Filer screen notification (controlled by config)
      if e.config.notification.screenNotifications and
          e.config.notification.filerScreenNotify:
        e.state.setStatusMessage("Opened in hsplit: " & r.filerFilePath)
      # Filer log notification (controlled by config)
      if e.config.notification.logNotifications and e.config.notification.filerLogNotify:
        logInfo("filer", "Opened file in hsplit: " & r.filerFilePath)
    return true

  if r.kind == hrFilerQuit:
    # Close filer and return to Normal mode
    # (previousMode may be Filer if we went Command->Filer, so always use Normal)
    e.state.filerState = none(FilerState)
    e.state.mode = EditorMode.Normal
    return true

  if r.kind == hrLogViewerQuit:
    # Close log viewer window and return to Normal mode
    e.state.logViewerState = none(LogViewerState)
    e.state.mode = EditorMode.Normal
    # Close the window if we're in split view
    if e.windowManager.windows.len > 1:
      discard e.closeWindow()
    return true

  if r.kind == hrLogViewerRefresh:
    # Refresh log viewer content by creating new buffer with updated content
    if e.state.logViewerState.isSome and
        e.windowManager.activeWindowIndex < e.windowManager.windows.len:
      let logLines =
        case e.state.logViewerState.get.contentKind
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
      e.windowManager.windows[e.windowManager.activeWindowIndex].buffer = newBuffer
      # Clamp cursor if needed
      let maxLine = max(0, newBuffer.len - 1)
      if e.state.cursor.line > maxLine:
        e.state.cursor.line = maxLine
      e.state.setStatusMessage("Log refreshed")
    return true

  if r.kind == hrHelpViewerQuit:
    # Close help viewer and return to Normal mode
    e.state.helpViewerState = none(HelpViewerState)
    e.state.mode = EditorMode.Normal
    return true

  if r.shouldReferencesQuit():
    # Close references viewer and return to Normal mode
    e.state.referencesViewerState = none(ReferencesViewerState)
    e.state.mode = EditorMode.Normal
    return true

  if r.shouldReferencesJumpTo():
    # Jump to selected reference
    let target = r.getReferencesJumpTarget()
    # Close references viewer first
    e.state.referencesViewerState = none(ReferencesViewerState)
    e.state.mode = EditorMode.Normal
    # Open file and jump to location
    discard e.openFileAndJumpTo(target.path, target.line, target.column)
    return true

  if r.shouldDocumentSymbolQuit():
    # Close document symbol viewer and return to Normal mode
    e.state.documentSymbolViewerState = none(DocumentSymbolViewerState)
    e.state.mode = EditorMode.Normal
    return true

  if r.shouldDocumentSymbolJumpTo():
    # Jump to selected symbol (same file)
    let target = r.getDocumentSymbolJumpTarget()
    let filePath = e.state.documentSymbolViewerState.get.filePath
    # Close document symbol viewer first
    e.state.documentSymbolViewerState = none(DocumentSymbolViewerState)
    e.state.mode = EditorMode.Normal
    # Open file and jump to location (adds to jump list)
    discard e.openFileAndJumpTo(filePath, target.line, target.column)
    return true

  # Handle Buffer Manager mode results
  if r.shouldBufferManagerQuit():
    # Close buffer manager and return to Normal mode
    e.state.bufferManagerState = none(BufferManagerState)
    e.state.mode = EditorMode.Normal
    return true

  if r.shouldBufferManagerSelectBuffer():
    # Select the buffer and switch to it
    let bufferIndex = r.getBufferManagerSelectBufferIndex()
    if bufferIndex >= 0 and bufferIndex < e.buffers.len:
      e.switchToBufferByIndex(bufferIndex)
    # Close buffer manager and return to Normal mode
    e.state.bufferManagerState = none(BufferManagerState)
    e.state.mode = EditorMode.Normal
    return true

  if r.shouldBufferManagerDeleteBuffer():
    # Delete the buffer from the buffer list
    let bufferIndex = r.getBufferManagerDeleteBufferIndex()
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

        # Update buffer manager entries
        if e.state.bufferManagerState.isSome:
          e.state.bufferManagerState.get.updateEntries(e.getBufferInfos())
    else:
      # Cannot delete the only buffer
      e.state.setStatusMessage("Cannot delete the last buffer")
    return true

  # Handle Backup Manager mode results
  if r.shouldBackupManagerQuit():
    # Close backup manager and return to Normal mode
    e.state.backupManagerState = none(BackupManagerState)
    e.state.mode = EditorMode.Normal
    return true

  # Handle Diff Viewer mode results
  if r.shouldDiffViewerQuit():
    # Close diff viewer and return to BackupManager
    # Note: We return to BackupManager directly instead of using previousMode
    # because previousMode can get corrupted if the user enters Command mode
    # (e.g., BackupManager -> DiffViewer -> Command -> DiffViewer -> quit
    #  would incorrectly stay in DiffViewer if we used previousMode)
    e.state.diffViewerState = none(DiffViewerState)
    e.state.mode = EditorMode.BackupManager
    return true

  # Handle Config mode results
  if r.shouldConfigQuit():
    # Close config mode and return to previous mode
    e.state.configModeState = none(ConfigModeState)
    e.state.mode = e.state.previousMode
    return true

  if r.shouldConfigSaveConfig():
    # Save configuration to TOML file
    let saveResult = saveConfig(e.config)
    if saveResult.isOk:
      let configPath = getConfigPath()
      e.state.setStatusMessage("Config saved: " & configPath)
      logInfo("config", "Configuration saved to: " & configPath)
    else:
      e.state.setStatusMessage("Error: " & saveResult.error)
      logError("config", "Failed to save config: " & saveResult.error)
    return true

  if r.shouldBackupManagerRefresh():
    # Refresh backup list
    if e.state.backupManagerState.isSome:
      e.state.backupManagerState.get.refresh()
    return true

  if r.shouldBackupManagerRestore():
    # Restore the selected backup
    let backupIndex = r.getBackupManagerRestoreIndex()
    if e.state.backupManagerState.isSome:
      let bkState = e.state.backupManagerState.get
      # Backup current buffer before restore (in case user wants to undo)
      discard e.buffer.backupBuffer(e.config.autoBackup)
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

  if r.shouldBackupManagerDelete():
    # Delete the selected backup
    let backupIndex = r.getBackupManagerDeleteIndex()
    if e.state.backupManagerState.isSome:
      let bkState = e.state.backupManagerState.get
      if bkState.deleteBackup(backupIndex):
        e.state.setStatusMessage("Backup deleted")
      else:
        e.state.setStatusMessage("Failed to delete backup")
    return true

  if r.shouldBackupManagerOpenDiff():
    # Open diff viewer for the selected backup
    let backupIndex = r.getBackupManagerDiffIndex()
    if e.state.backupManagerState.isSome:
      let bkState = e.state.backupManagerState.get
      if backupIndex >= 0 and backupIndex < bkState.entries.len:
        let entry = bkState.entries[backupIndex]
        # Initialize diff viewer with source and backup paths
        let dvState = initDiffViewerState(bkState.sourceFilePath, entry.fullPath)
        e.state.diffViewerState = some(dvState)
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.DiffViewer
        if dvState.errorMessage.len > 0:
          e.state.setStatusMessage("Diff error: " & dvState.errorMessage)
    return true

  # Handle LSP goto definition
  if r.shouldLspGotoDefinition():
    discard e.requestLspGotoDefinition()
    return true

  # Handle LSP goto declaration
  if r.shouldLspGotoDeclaration():
    discard e.requestLspGotoDeclaration()
    return true

  # Handle LSP find references
  if r.shouldLspFindReferences():
    discard e.requestLspReferences()
    return true

  # Handle LSP CodeLens execute
  if r.shouldLspCodeLensExecute():
    discard e.executeCurrentLineCodeLens()
    return true

  # Handle LSP Call Hierarchy incoming calls
  if r.shouldLspCallHierarchyIncoming():
    discard e.requestLspCallHierarchyIncoming()
    return true

  # Handle LSP Call Hierarchy outgoing calls
  if r.shouldLspCallHierarchyOutgoing():
    discard e.requestLspCallHierarchyOutgoing()
    return true

  # Handle LSP Type Definition
  if r.shouldLspTypeDefinition():
    discard e.requestLspTypeDefinition()
    return true

  # Handle LSP Implementation
  if r.shouldLspImplementation():
    discard e.requestLspImplementation()
    return true

  # Handle LSP Hover
  if r.shouldLspHover():
    discard e.requestLspHover()
    return true

  # Handle LSP Rename - for now just show status message, rename requires user input
  if r.shouldLspRename():
    e.state.statusMessage = "Rename: Use :lspRename <newname> command"
    return true

  # Handle LSP Selection Range
  if r.shouldLspSelectionRange():
    discard e.requestLspSelectionRange()
    return true

  # Handle mode transitions
  let modeTransition = r.getModeTransition()
  if modeTransition.isSome:
    let oldMode = e.state.mode
    let newMode = modeTransition.get

    e.state.previousMode = oldMode
    e.state.mode = newMode

    # Initialize filer state when entering Filer mode
    if newMode == EditorMode.Filer and e.state.filerState.isNone:
      # Use buffer's directory or current working directory
      let startPath =
        if activeBuffer.filePath.isSome:
          parentDir(activeBuffer.filePath.get)
        else:
          getCurrentDir()
      e.state.filerState = some(newFilerState(startPath))

    # Initialize buffer manager state when entering BufferManager mode
    if newMode == EditorMode.BufferManager:
      let bmState = newBufferManagerState()
      bmState.updateEntries(e.getBufferInfos())
      bmState.previousWindowIndex = e.windowManager.activeWindowIndex
      e.state.bufferManagerState = some(bmState)

    # Adjust cursor when transitioning from Insert to Normal mode
    # In Insert mode, cursor can be after the last character
    # In Normal mode, cursor must be on a character (not after)
    if oldMode == EditorMode.Insert and newMode == EditorMode.Normal:
      let
        currentLine = activeBuffer.getLine(e.state.cursor.line)
        lineCharLen = currentLine.charLen
        oldColumn = e.state.cursor.column

      logDebug(
        "handler",
        "Insert→Normal transition: line=" & $e.state.cursor.line & " oldColumn=" &
          $oldColumn & " lineCharLen=" & $lineCharLen,
      )

      if lineCharLen == 0:
        # Empty line: cursor should be at column 0
        e.state.cursor.column = 0
      elif e.state.cursor.column >= lineCharLen:
        # Cursor is beyond last character, move it back to last char
        e.state.cursor.column = lineCharLen - 1

      if oldColumn != e.state.cursor.column:
        logDebug(
          "handler", "Cursor adjusted: " & $oldColumn & " → " & $e.state.cursor.column
        )

  # Set status message if any
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.setStatusMessage(statusMsg)

  return true # Continue running
