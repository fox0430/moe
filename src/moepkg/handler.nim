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

import std/[options, os, strutils]

import pkg/[celina, results]

import
  editor, keybindings, modes, buffer, logger, types, cursor, motion, search_utils,
  filer, quickrunutils, messagelog, helpviewer, buffermanager, backupmanager, backup,
  diffviewer
import command_handlers/handler_manager

proc getBufferInfos(e: Editor): seq[BufferInfo] =
  ## Extract buffer information from the window manager for BufferManager
  result = @[]
  if e.windowManager.windows.len > 0:
    # Use windows from window manager
    for window in e.windowManager.windows:
      result.add(
        BufferInfo(
          filePath: window.buffer.filePath,
          isModified: window.buffer.isModified,
          isActive: window.active,
        )
      )
  else:
    # No windows - use the main textBuffer
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

    # Add to search history (avoid duplicates)
    # Remove if already exists in history
    let searchTextCopy = e.state.search.text
    for i in countdown(e.state.search.history.high, 0):
      if e.state.search.history[i] == searchTextCopy:
        e.state.search.history.delete(i)

    # Add to beginning of history (most recent first)
    e.state.search.history.insert(searchTextCopy, 0)

    # Limit history size to MaxHistoryEntries
    if e.state.search.history.len > MaxHistoryEntries:
      e.state.search.history.setLen(MaxHistoryEntries)

    # If incsearch is enabled, cursor is already at the found position
    if e.state.search.incsearch:
      e.updateViewportForCursor(e.state.cursor)
      e.state.needsFullRedraw = true
    else:
      # If incsearch is disabled, perform search now
      discard e.executeSearchFromCurrentPosition()

  # Return to Normal mode
  e.state.previousMode = e.state.mode
  e.state.mode = EditorMode.Normal
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
  e.state.search.text.add(ch)
  e.performIncrementalSearch()

proc handleSearchBackspace(e: Editor) =
  ## Handle Backspace key in Search mode
  ##
  ## Called when: Backspace is pressed
  ##
  ## Behavior:
  ## - Remove last character from searchText (if any)
  ## - If incsearch enabled: Trigger incremental search with updated text
  if e.state.search.text.len > 0:
    e.state.search.text = e.state.search.text[0 ..^ 2]
    e.performIncrementalSearch()

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
    e.state.mode = e.state.previousMode
    e.state.commandText = ""
    e.state.commandCursor = 0
    return true

  # Handle Tab key for command completion
  if keyCombo.isSpecial and keyCombo.special == skTab:
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

    if kmShift in keyCombo.modifiers:
      # Shift+Tab: select previous item
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
      mgr.cancelCompletion()
      # If directory was confirmed, re-trigger completion for its contents
      if isDir:
        mgr.triggerArgumentCompletion(e.state.commandText, getCurrentDir())
      return true

    # Cancel completion if active (no selection case)
    e.state.commandCompletionManager.cancelCompletion()

    if e.state.commandText.len > 1: # Must have something after :
      # Use the command handler with active buffer
      let activeBuffer = e.activeBuffer()
      # Check if the buffer is shared across multiple windows
      let isShared = e.isBufferShared(activeBuffer)
      let r =
        e.handlerManager.handleCommandMode(activeBuffer, e.state.commandText, isShared)

      if r.shouldQuit():
        return false # Signal app should quit

      if r.shouldCloseWindow():
        # Handle window close - may also quit if last window
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

      if r.shouldEdit():
        # Handle edit (open file in current window)
        let editResult = e.editFile(r.getEditFilename())
        if editResult.isErr:
          logError("handler", "Edit failed: " & editResult.error)
          e.state.setStatusMessage("Error: " & editResult.error)
        else:
          e.state.setStatusMessage("Opened: " & r.getEditFilename())

      if r.shouldSetMultiStatusLine():
        # Handle multi status line setting
        e.setMultiStatusLine(r.getMultiStatusLineEnabled())

      if r.shouldSetIgnoreCase():
        # Handle ignorecase setting
        e.state.search.ignorecase = r.getIgnoreCaseEnabled()
        e.state.setStatusMessage("ignorecase = " & $e.state.search.ignorecase)

      if r.shouldSetSmartCase():
        # Handle smartcase setting
        e.state.search.smartcase = r.getSmartCaseEnabled()
        e.state.setStatusMessage("smartcase = " & $e.state.search.smartcase)

      if r.shouldSetIncSearch():
        # Handle incsearch setting
        e.state.search.incsearch = r.getIncSearchEnabled()
        e.state.setStatusMessage("incsearch = " & $e.state.search.incsearch)

      if r.shouldSetHlSearch():
        # Handle hlsearch setting
        e.state.search.hlsearch = r.getHlSearchEnabled()
        e.state.setStatusMessage("hlsearch = " & $e.state.search.hlsearch)

      if r.shouldSave():
        # Handle file save
        let saveResult = e.saveFile(r.getSaveFilename())
        if saveResult.isErr:
          logError("handler", "Save command failed: " & saveResult.error)
          e.state.setStatusMessage("Error: " & saveResult.error)
        else:
          # Get saved file path from active buffer
          let savedPath =
            if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: "file"
          logInfo("handler", "File saved via command: " & savedPath)
          e.state.setStatusMessage("Saved: " & savedPath)

      if r.shouldSaveAndQuit():
        # Handle file save and quit
        let saveResult = e.saveFile(r.getSaveAndQuitFilename())
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

      if r.shouldQuickRun():
        # Handle QuickRun command
        let quickRunResult = startBackgroundQuickRun(activeBuffer, e.config)
        if quickRunResult.isErr:
          e.state.setStatusMessage("QuickRun error: " & quickRunResult.error)
          logError("handler", "QuickRun failed: " & quickRunResult.error)
        else:
          var qrProcess = quickRunResult.get
          e.state.setStatusMessage(quickRunStartupMessage(qrProcess.filePath))

          # Wait for the process to finish and get the result
          let outputResult = qrProcess.waitForResult()
          if outputResult.isErr:
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
              e.state.setStatusMessage(
                "Failed to open output window: " & splitResult.error
              )
              logError("handler", "QuickRun window split failed: " & splitResult.error)
            else:
              e.state.setStatusMessage("QuickRun completed: " & qrProcess.filePath)
              logInfo("handler", "QuickRun completed: " & qrProcess.filePath)
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
        # Open log viewer in a horizontal split
        let logs = getMessageLog()
        let logContent =
          if logs.len == 0:
            "(No messages)"
          else:
            logs.join("\n")
        let logBuffer = newTextBuffer(logContent)
        logBuffer.readOnly = true
        let splitResult = e.hsplitWithBuffer(logBuffer)
        if splitResult.isErr:
          e.state.setStatusMessage("Failed to open log: " & splitResult.error)
        else:
          e.state.setStatusMessage("Log: " & $logs.len & " messages")
        # Return to Normal mode
        e.state.previousMode = e.state.mode
        e.state.mode = EditorMode.Normal
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
      else:
        # Handle mode transitions
        let modeTransition = r.getModeTransition()
        if modeTransition.isSome:
          e.state.previousMode = e.state.mode
          e.state.mode = modeTransition.get
        else:
          e.state.previousMode = e.state.mode
          e.state.mode = EditorMode.Normal # Default back to normal

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

proc handleEvent*(e: Editor, event: Event): bool =
  ## Main event handler using the new handler manager system

  # Update last input time for auto backup idle detection
  e.updateInputTime()

  # Handle Command mode input differently (character by character)
  if e.state.mode == EditorMode.Command:
    return handleCommandModeEvent(e, event)

  # Handle Search mode input differently (character by character)
  if e.state.mode == EditorMode.Search:
    return handleSearchModeEvent(e, event)

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

      # Handle Escape key to clear search highlight (like :nohlsearch in Vim)
      # Requires double-Escape (two consecutive Escape presses)
      if keyCombo.isSpecial and keyCombo.special == skEscape:
        if e.state.lastKeyWasEscape:
          # Second Escape press - clear highlight
          e.state.search.hlsearchTempDisabled = true
          e.state.needsFullRedraw = true
          e.state.setStatusMessage("Search highlight cleared")
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

        # Handle second key: j (down/prev) or k (up/next)
        if not keyCombo.isSpecial:
          if keyCombo.char == "j":
            e.switchToPrevWindow
            return true
          elif keyCombo.char == "k":
            e.switchToNextWindow
            return true
          else:
            # Unknown window command, just cancel
            return true

      # Check for Ctrl-w to enter window command mode
      if not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers:
        if keyCombo.char == "w":
          e.state.command = "window_cmd"
          e.state.statusMessage = "-- (window) --"
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
  else:
    # Single window mode - use default calculation
    e.state.viewportReservedLines = if e.state.display.showStatusLine: 2 else: 1
    # Sync the motion controller's viewport with the editor's viewport
    e.executer.motionController.viewportManager.viewport = e.viewport

  let r = e.handlerManager.handleEvent(activeBuffer, e.state, activeViewport, event)

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
    let saveResult = e.saveFile(r.getSaveAndQuitFilename())
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
    return true

  if r.kind == hrFilerQuit:
    # Close filer and return to Normal mode
    # (previousMode may be Filer if we went Command->Filer, so always use Normal)
    e.state.filerState = none(FilerState)
    e.state.mode = EditorMode.Normal
    return true

  if r.kind == hrHelpViewerQuit:
    # Close help viewer and return to Normal mode
    e.state.helpViewerState = none(HelpViewerState)
    e.state.mode = EditorMode.Normal
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
    if e.windowManager.windows.len > 0:
      # Window manager mode - switch between windows
      if bufferIndex >= 0 and bufferIndex < e.windowManager.windows.len:
        e.saveActiveWindowState()
        # Deactivate all windows
        for window in e.windowManager.windows.mitems:
          window.active = false
        # Activate the selected window
        e.windowManager.activeWindowIndex = bufferIndex
        e.windowManager.windows[bufferIndex].active = true
        e.syncActiveWindow()
    # else: Single buffer mode - already active, nothing to do
    # Close buffer manager and return to Normal mode
    e.state.bufferManagerState = none(BufferManagerState)
    e.state.mode = EditorMode.Normal
    return true

  if r.shouldBufferManagerDeleteBuffer():
    # Delete the buffer (close the window)
    let bufferIndex = r.getBufferManagerDeleteBufferIndex()
    if e.windowManager.windows.len > 1:
      # Window manager mode with multiple windows - can delete
      if bufferIndex >= 0 and bufferIndex < e.windowManager.windows.len:
        e.windowManager.windows.delete(bufferIndex)
        # Adjust active index if needed
        if e.windowManager.activeWindowIndex >= e.windowManager.windows.len:
          e.windowManager.activeWindowIndex = e.windowManager.windows.len - 1
        e.windowManager.windows[e.windowManager.activeWindowIndex].active = true
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
          let textResult = e.buffer.loadFile(e.buffer.filePath.get)
          if textResult.isOk:
            e.state.setStatusMessage("Backup restored successfully")
            # Refresh the backup list to show the new backup
            bkState.refresh()
          else:
            e.state.setStatusMessage(
              "Restored but failed to reload: " & textResult.error
            )
        else:
          e.state.setStatusMessage("Backup restored successfully")
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
