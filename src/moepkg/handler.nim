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

import std/options

import pkg/[celina, results]

import editor, keybindings, modes, buffer, logger, types, cursor, motion, search_utils
import command_handlers/handler_manager

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
    e.state.showStatusLine,
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
  let shouldIgnoreCase =
    shouldIgnoreCase(e.state.searchText, e.state.ignorecase, e.state.smartcase)

  let activeBuffer = e.activeBuffer()
  let searchResult =
    if e.state.searchDirection == Forward:
      activeBuffer.findNext(e.state.searchText, e.state.cursor, shouldIgnoreCase)
    else:
      activeBuffer.findPrev(e.state.searchText, e.state.cursor, shouldIgnoreCase)

  if searchResult.isSome:
    let pos = searchResult.get
    e.state.cursor = pos
    e.updateViewportForCursor(pos)
    e.state.statusMessage = "Found: " & e.state.searchText
    e.state.needsFullRedraw = true
    return true
  else:
    e.state.statusMessage = "Pattern not found: " & e.state.searchText
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
  if e.state.searchText.len > 0:
    # Save search text for n/N commands
    e.state.lastSearchText = e.state.searchText
    # Re-enable highlight for new search
    e.state.hlsearchTempDisabled = false

    # Add to search history (avoid duplicates)
    # Remove if already exists in history
    let searchTextCopy = e.state.searchText
    for i in countdown(e.state.searchHistory.high, 0):
      if e.state.searchHistory[i] == searchTextCopy:
        e.state.searchHistory.delete(i)

    # Add to beginning of history (most recent first)
    e.state.searchHistory.insert(searchTextCopy, 0)

    # Limit history size to MaxHistoryEntries
    if e.state.searchHistory.len > MaxHistoryEntries:
      e.state.searchHistory.setLen(MaxHistoryEntries)

    # If incsearch is enabled, cursor is already at the found position
    if e.state.incsearch:
      e.updateViewportForCursor(e.state.cursor)
      e.state.needsFullRedraw = true
    else:
      # If incsearch is disabled, perform search now
      discard e.executeSearchFromCurrentPosition()

  # Return to Normal mode
  e.state.previousMode = e.state.mode
  e.state.mode = EditorMode.Normal
  e.state.searchText = ""
  # Reset history navigation index
  e.state.searchHistoryIndex = -1

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
  if e.state.incsearch:
    e.state.cursor = e.state.searchStartPos
  e.state.mode = e.state.previousMode
  e.state.searchText = ""
  # Reset history navigation index
  e.state.searchHistoryIndex = -1

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
  if not e.state.incsearch or e.state.searchText.len == 0:
    return

  # Apply smartcase logic to determine if we should ignore case
  let shouldIgnoreCase =
    shouldIgnoreCase(e.state.searchText, e.state.ignorecase, e.state.smartcase)

  # Perform search from the original search start position (not current cursor!)
  let activeBuffer = e.activeBuffer()
  let searchResult =
    if e.state.searchDirection == Forward:
      activeBuffer.findNext(
        e.state.searchText, e.state.searchStartPos, shouldIgnoreCase
      )
    else:
      activeBuffer.findPrev(
        e.state.searchText, e.state.searchStartPos, shouldIgnoreCase
      )

  if searchResult.isSome:
    let pos = searchResult.get
    e.state.cursor = pos

    # Update viewport to follow cursor
    e.updateViewportForCursor(pos)

    e.state.statusMessage = "Found: " & e.state.searchText
    e.state.needsFullRedraw = true
  else:
    # No match found, restore to start position
    e.state.cursor = e.state.searchStartPos
    e.state.statusMessage = "Pattern not found: " & e.state.searchText

proc handleSearchCharacterInput(e: Editor, ch: string) =
  ## Handle character input in Search mode
  ##
  ## Called when: Any printable character is typed
  ##
  ## Behavior:
  ## - Append character to searchText
  ## - If incsearch enabled: Trigger incremental search
  e.state.searchText.add(ch)
  e.performIncrementalSearch()

proc handleSearchBackspace(e: Editor) =
  ## Handle Backspace key in Search mode
  ##
  ## Called when: Backspace is pressed
  ##
  ## Behavior:
  ## - Remove last character from searchText (if any)
  ## - If incsearch enabled: Trigger incremental search with updated text
  if e.state.searchText.len > 0:
    e.state.searchText = e.state.searchText[0 ..^ 2]
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
    e.state.mode = e.state.previousMode
    e.state.commandText = ""
    return true

  # Handle Enter to execute command
  let isEnter =
    (keyCombo.isSpecial and keyCombo.special == skEnter) or
    (not keyCombo.isSpecial and (keyCombo.char == "\n" or keyCombo.char == "\r"))

  if isEnter:
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
          e.state.statusMessage = "Error: " & splitResult.error

      if r.shouldHSplit():
        # Handle horizontal split
        let splitResult = e.hsplit(r.getHSplitFilename())
        if splitResult.isErr:
          logError("handler", "Horizontal split failed: " & splitResult.error)
          e.state.statusMessage = "Error: " & splitResult.error

      if r.shouldSetMultiStatusLine():
        # Handle multi status line setting
        e.setMultiStatusLine(r.getMultiStatusLineEnabled())

      if r.shouldSetIgnoreCase():
        # Handle ignorecase setting
        e.state.ignorecase = r.getIgnoreCaseEnabled()
        e.state.statusMessage = "ignorecase = " & $e.state.ignorecase

      if r.shouldSetSmartCase():
        # Handle smartcase setting
        e.state.smartcase = r.getSmartCaseEnabled()
        e.state.statusMessage = "smartcase = " & $e.state.smartcase

      if r.shouldSetIncSearch():
        # Handle incsearch setting
        e.state.incsearch = r.getIncSearchEnabled()
        e.state.statusMessage = "incsearch = " & $e.state.incsearch

      if r.shouldSetHlSearch():
        # Handle hlsearch setting
        e.state.hlsearch = r.getHlSearchEnabled()
        e.state.statusMessage = "hlsearch = " & $e.state.hlsearch

      if r.shouldSave():
        # Handle file save
        let saveResult = e.saveFile(r.getSaveFilename())
        if saveResult.isErr:
          logError("handler", "Save command failed: " & saveResult.error)
          e.state.statusMessage = "Error: " & saveResult.error
        else:
          # Get saved file path from active buffer
          let savedPath =
            if activeBuffer.filePath.isSome: activeBuffer.filePath.get else: "file"
          logInfo("handler", "File saved via command: " & savedPath)
          e.state.statusMessage = "Saved: " & savedPath

      if r.shouldSaveAndQuit():
        # Handle file save and quit
        let saveResult = e.saveFile(r.getSaveAndQuitFilename())
        if saveResult.isErr:
          logError("handler", "Save and quit failed: " & saveResult.error)
          e.state.statusMessage = "Error: " & saveResult.error
        else:
          # Save succeeded, now quit
          logInfo("handler", "File saved, quitting editor")
          return false # Signal app should quit

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
        e.state.statusMessage = statusMsg
    else:
      # Empty command, just return to previous mode
      e.state.mode = e.state.previousMode

    # Clear command text
    e.state.commandText = ""
    return true

  # Handle Backspace
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    if e.state.commandText.len > 1: # Keep the : prefix
      e.state.commandText = e.state.commandText[0 ..^ 2]
    return true

  # Handle character input
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    e.state.commandText.add(keyCombo.char)
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
    if e.state.searchHistory.len > 0:
      # If not yet navigating history, start from the most recent entry
      if e.state.searchHistoryIndex == -1:
        e.state.searchHistoryIndex = 0
      # Otherwise, move to the next older entry
      elif e.state.searchHistoryIndex < e.state.searchHistory.high:
        e.state.searchHistoryIndex += 1

      # Update search text with history entry
      e.state.searchText = e.state.searchHistory[e.state.searchHistoryIndex]
      # Trigger incremental search with history entry
      e.performIncrementalSearch()
    return true

  # Down arrow: Navigate to next (newer) search in history
  if keyCombo.isSpecial and keyCombo.special == skDown:
    if e.state.searchHistory.len > 0 and e.state.searchHistoryIndex >= 0:
      # Move to newer entry
      if e.state.searchHistoryIndex > 0:
        e.state.searchHistoryIndex -= 1
        e.state.searchText = e.state.searchHistory[e.state.searchHistoryIndex]
        e.performIncrementalSearch()
      else:
        # Reached the newest entry, clear search text
        e.state.searchHistoryIndex = -1
        e.state.searchText = ""
        # Restore cursor to start position if incsearch is enabled
        if e.state.incsearch:
          e.state.cursor = e.state.searchStartPos
    return true

  # Backspace: Remove last character and re-search
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    # Reset history navigation when user types
    e.state.searchHistoryIndex = -1
    e.handleSearchBackspace()
    return true

  # Character input: Add character and perform incremental search
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    # Reset history navigation when user types
    e.state.searchHistoryIndex = -1
    e.handleSearchCharacterInput(keyCombo.char)
    return true

  # Ignore other special keys
  return true

proc handleEvent*(e: Editor, event: Event): bool =
  ## Main event handler using the new handler manager system

  # Handle Command mode input differently (character by character)
  if e.state.mode == EditorMode.Command:
    return handleCommandModeEvent(e, event)

  # Handle Search mode input differently (character by character)
  if e.state.mode == EditorMode.Search:
    return handleSearchModeEvent(e, event)

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
          e.state.hlsearchTempDisabled = true
          e.state.needsFullRedraw = true
          e.state.statusMessage = "Search highlight cleared"
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
      if e.state.showStatusLine:
        if e.state.multiStatusLine:
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
    e.state.viewportReservedLines = if e.state.showStatusLine: 2 else: 1
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
      e.state.statusMessage = "Error: " & saveResult.error
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

  # Handle mode transitions
  let modeTransition = r.getModeTransition()
  if modeTransition.isSome:
    let oldMode = e.state.mode
    let newMode = modeTransition.get

    e.state.previousMode = oldMode
    e.state.mode = newMode

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
    e.state.statusMessage = statusMsg

  return true # Continue running
