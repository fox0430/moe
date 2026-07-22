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

## Search mode event handler
##
## This module handles incremental search mode (/ and ? commands).
## Extracted from handler.nim to reduce file size.

import std/[options, strutils, unicode]

import pkg/celina

import
  ../[
    editor, key_bindings, modes, buffer, search_utils, types, help_viewer, config_mode,
    unicode_utils,
  ]
import command_mode_handler

## NOTE: While in Search Mode:
## - Character input: Add to searchText, trigger performIncrementalSearch (if enabled)
## - Backspace: Remove from searchText, trigger performIncrementalSearch (if enabled)
## - Enter: Save search, execute if needed, return to Normal mode
## - Escape: Cancel search, restore cursor if incsearch, return to previous mode

proc syncHelpViewerIndex(e: Editor, line: int) =
  ## Sync help viewer selectedIndex with the given line position.
  ## No-op if not in Help mode or the variant payload is missing.
  if e.state.mode == EditorMode.Help:
    let window = e.activeWindow
    if window.modeState.kind == mskHelp:
      window.modeState.help.selectedIndex = line

proc activeConfigState(e: Editor): ConfigModeState =
  ## Returns the active window's ConfigModeState, or nil when not in Config mode.
  ## Config mode renders an item list rather than a text buffer, so its search
  ## operates on that list instead of the buffer search machinery.
  if e.state.mode == EditorMode.Config:
    let window = e.activeWindow
    if window.modeState.kind == mskConfig:
      return window.modeState.config
  return nil

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
  let shouldIgnoreCase = shouldIgnoreCase(
    e.state.input.search.text, e.state.input.search.ignorecase,
    e.state.input.search.smartcase,
  )

  # Validate regex before searching
  if compileSearchRegex(e.state.input.search.text, shouldIgnoreCase).isNone:
    e.state.statusMessage = "Invalid regex: " & e.state.input.search.text
    return false

  let activeBuffer = e.activeBuffer()
  let searchResult =
    if e.state.input.search.direction == Forward:
      activeBuffer.findNext(e.state.input.search.text, e.cursor, shouldIgnoreCase)
    else:
      activeBuffer.findPrev(e.state.input.search.text, e.cursor, shouldIgnoreCase)

  if searchResult.isSome:
    let pos = searchResult.get
    e.cursor = pos
    e.updateViewportForCursor(pos)
    e.state.statusMessage = "Found: " & e.state.input.search.text
    return true
  else:
    e.state.statusMessage = "Pattern not found: " & e.state.input.search.text
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
  if e.state.input.search.text.len > 0:
    # Save search text for n/N commands
    e.state.input.search.lastText = e.state.input.search.text
    # Re-enable highlight for new search
    e.state.input.search.hlsearchTempDisabled = false
    # Reset whole word mode (/ and ? are substring searches)
    e.state.input.search.wholeWord = false

    # Add to search history (avoid duplicates)
    # Remove if already exists in history
    let searchTextCopy = e.state.input.search.text
    for i in countdown(e.state.input.search.history.high, 0):
      if e.state.input.search.history[i] == searchTextCopy:
        e.state.input.search.history.delete(i)

    # Add to beginning of history (most recent first)
    e.state.input.search.history.insert(searchTextCopy, 0)

    # Limit history size to configured limit
    let historyLimit = e.config.persist.searchHistoryLimit
    if e.state.input.search.history.len > historyLimit:
      e.state.input.search.history.setLen(historyLimit)

    let cfg = e.activeConfigState()
    if cfg != nil:
      # Config mode: commit the query and move the selection to the first match,
      # anchored from where the search started.
      cfg.setSearchQuery(e.state.input.search.text)
      let forward = e.state.input.search.direction == Forward
      discard cfg.searchItems(e.state.input.search.text, cfg.searchStartIndex, forward)
    else:
      # If incsearch is enabled, cursor is already at the found position
      if e.state.input.search.incsearch:
        e.updateViewportForCursor(e.cursor)
      else:
        # If incsearch is disabled, perform search now
        discard e.executeSearchFromCurrentPosition()

      # Sync search query and position to help viewer state if in Help mode
      if e.state.mode == EditorMode.Help:
        let window = e.activeWindow
        if window.modeState.kind == mskHelp:
          window.modeState.help.setSearchQuery(e.state.input.search.text)
      e.syncHelpViewerIndex(e.cursor.line)

  # Exit overlay and return to base mode
  # The base mode (Normal, LogViewer, Filer, etc.) is preserved
  e.state.exitOverlay()
  e.setMode(e.state.mode) # Sync window mode

  # Insert-Normal mode (Ctrl-o): return to Insert after the search completes
  if e.state.insertNormalMode and e.state.mode == EditorMode.Normal:
    e.state.insertNormalMode = false
    e.setMode(EditorMode.Insert)

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
  let cfg = e.activeConfigState()
  if cfg != nil:
    # Config mode: restore the selection that was active before the search.
    if e.state.input.search.incsearch:
      cfg.selectedIndex = cfg.searchStartIndex
  elif e.state.input.search.incsearch:
    e.cursor = e.state.input.search.startPos
    e.syncHelpViewerIndex(e.state.input.search.startPos.line)
  # Exit overlay and restore base mode
  e.state.exitOverlay()
  e.setMode(e.state.mode) # Sync window mode

  # Insert-Normal mode (Ctrl-o): return to Insert after the search is cancelled
  if e.state.insertNormalMode and e.state.mode == EditorMode.Normal:
    e.state.insertNormalMode = false
    e.setMode(EditorMode.Insert)

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
  if not e.state.input.search.incsearch:
    return

  let cfg = e.activeConfigState()
  if cfg != nil:
    # Config mode: live-search the item list from the search start anchor.
    if e.state.input.search.text.len == 0:
      cfg.selectedIndex = cfg.searchStartIndex
    else:
      let forward = e.state.input.search.direction == Forward
      discard cfg.searchItems(e.state.input.search.text, cfg.searchStartIndex, forward)
    return

  if e.state.input.search.text.len == 0:
    return

  # Apply smartcase logic to determine if we should ignore case
  let shouldIgnoreCase = shouldIgnoreCase(
    e.state.input.search.text, e.state.input.search.ignorecase,
    e.state.input.search.smartcase,
  )

  # Validate regex - silently ignore invalid patterns during typing
  if compileSearchRegex(e.state.input.search.text, shouldIgnoreCase).isNone:
    e.state.statusMessage = "Invalid regex: " & e.state.input.search.text
    return

  # Perform search from the original search start position (not current cursor!)
  let activeBuffer = e.activeBuffer()
  let searchResult =
    if e.state.input.search.direction == Forward:
      activeBuffer.findNext(
        e.state.input.search.text, e.state.input.search.startPos, shouldIgnoreCase
      )
    else:
      activeBuffer.findPrev(
        e.state.input.search.text, e.state.input.search.startPos, shouldIgnoreCase
      )

  if searchResult.isSome:
    let pos = searchResult.get
    e.cursor = pos
    e.syncHelpViewerIndex(pos.line)

    # Update viewport to follow cursor
    e.updateViewportForCursor(pos)

    e.state.statusMessage = "Found: " & e.state.input.search.text
  else:
    # No match found, restore to start position
    e.cursor = e.state.input.search.startPos
    e.syncHelpViewerIndex(e.state.input.search.startPos.line)

    e.state.statusMessage = "Pattern not found: " & e.state.input.search.text

proc handleSearchCharacterInput(e: Editor, ch: string) =
  ## Handle character input in Search mode
  ##
  ## Called when: Any printable character is typed
  ##
  ## Behavior:
  ## - Insert character at cursor position in searchText
  ## - Advance cursor past the inserted character
  ## - If incsearch enabled: Trigger incremental search
  ## - Always trigger redraw to update search highlight
  let bytePos = charToBytePos(e.state.input.search.text, e.state.input.search.cursor)
  e.state.input.search.text =
    e.state.input.search.text[0 ..< bytePos] & ch &
    e.state.input.search.text[bytePos ..^ 1]
  e.state.input.search.cursor += ch.runeLen
  e.performIncrementalSearch()

proc insertPastedTextInSearch*(e: Editor, text: string) =
  ## Insert pasted text at the cursor position in the search text.
  ## The search line is single-line: only the first line of the paste is used
  ## (everything up to the first newline). A stray CR is stripped defensively so
  ## a raw \r can never leak into the field even if a caller skips normalizing.
  let nlIdx = text.find('\n')
  let firstLine =
    if nlIdx >= 0:
      text[0 ..< nlIdx]
    else:
      text
  let insertText = firstLine.replace("\r", "")
  if insertText.len == 0:
    return

  let bytePos = charToBytePos(e.state.input.search.text, e.state.input.search.cursor)
  e.state.input.search.text =
    e.state.input.search.text[0 ..< bytePos] & insertText &
    e.state.input.search.text[bytePos ..^ 1]
  e.state.input.search.cursor += insertText.runeLen
  e.performIncrementalSearch()

proc handleSearchBackspace(e: Editor) =
  ## Handle Backspace key in Search mode
  ##
  ## Called when: Backspace is pressed
  ##
  ## Behavior:
  ## - Remove the character before the cursor (if any)
  ## - Move cursor left by one
  ## - If incsearch enabled: Trigger incremental search with updated text
  ## - Always trigger redraw to update search highlight
  if e.state.input.search.cursor > 0:
    e.state.input.search.text =
      e.state.input.search.text.deleteCharAt(e.state.input.search.cursor - 1)
    e.state.input.search.cursor -= 1
    e.performIncrementalSearch()

proc handleSearchModeKeyCombo*(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in Search mode. Same dispatch as `handleSearchModeEvent`
  ## but reachable from replay paths (macro playback, runtime mapping RHS) that
  ## already hold a KeyCombo rather than a raw Event.
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
    if e.state.input.search.history.len > 0:
      # If not yet navigating history, start from the most recent entry
      if e.state.input.search.historyIndex == -1:
        e.state.input.search.historyIndex = 0
      # Otherwise, move to the next older entry
      elif e.state.input.search.historyIndex < e.state.input.search.history.high:
        e.state.input.search.historyIndex += 1

      # Update search text with history entry
      e.state.input.search.text =
        e.state.input.search.history[e.state.input.search.historyIndex]
      e.state.input.search.cursor = e.state.input.search.text.runeLen
      # Trigger incremental search with history entry
      e.performIncrementalSearch()
    return true

  # Down arrow: Navigate to next (newer) search in history
  if keyCombo.isSpecial and keyCombo.special == skDown:
    if e.state.input.search.history.len > 0 and e.state.input.search.historyIndex >= 0:
      # Move to newer entry
      if e.state.input.search.historyIndex > 0:
        e.state.input.search.historyIndex -= 1
        e.state.input.search.text =
          e.state.input.search.history[e.state.input.search.historyIndex]
        e.state.input.search.cursor = e.state.input.search.text.runeLen
        e.performIncrementalSearch()
      else:
        # Reached the newest entry, clear search text
        e.state.input.search.historyIndex = -1
        e.state.input.search.text = ""
        e.state.input.search.cursor = 0
        # Restore position to start if incsearch is enabled
        if e.state.input.search.incsearch:
          let cfg = e.activeConfigState()
          if cfg != nil:
            cfg.selectedIndex = cfg.searchStartIndex
          else:
            e.cursor = e.state.input.search.startPos
            e.syncHelpViewerIndex(e.state.input.search.startPos.line)
    return true

  # Left arrow: Move cursor left within search text
  if keyCombo.isSpecial and keyCombo.special == skLeft:
    if e.state.input.search.cursor > 0:
      e.state.input.search.cursor -= 1
    return true

  # Right arrow: Move cursor right within search text
  if keyCombo.isSpecial and keyCombo.special == skRight:
    if e.state.input.search.cursor < e.state.input.search.text.runeLen:
      e.state.input.search.cursor += 1
    return true

  # Home: Move cursor to start of search text
  if keyCombo.isSpecial and keyCombo.special == skHome:
    e.state.input.search.cursor = 0
    return true

  # End: Move cursor to end of search text
  if keyCombo.isSpecial and keyCombo.special == skEnd:
    e.state.input.search.cursor = e.state.input.search.text.runeLen
    return true

  # Delete: Remove character at cursor position
  if keyCombo.isSpecial and keyCombo.special == skDelete:
    if e.state.input.search.cursor < e.state.input.search.text.runeLen:
      # Reset history navigation when user edits
      e.state.input.search.historyIndex = -1
      e.state.input.search.text =
        e.state.input.search.text.deleteCharAt(e.state.input.search.cursor)
      e.performIncrementalSearch()
    return true

  # Backspace: Remove last character and re-search
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    # Reset history navigation when user types
    e.state.input.search.historyIndex = -1
    e.handleSearchBackspace()
    return true

  # Character input: Add character and perform incremental search
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    # Reset history navigation when user types
    e.state.input.search.historyIndex = -1
    e.handleSearchCharacterInput(keyCombo.char)
    return true

  # Ignore other special keys
  return true

proc handleSearchModeEvent*(e: Editor, event: Event): bool =
  ## Handle Search mode events - main event dispatcher.
  ## Extracts the KeyCombo and forwards to `handleSearchModeKeyCombo`, which
  ## replay paths call directly.
  if event.kind != EventKind.Key:
    return true
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true
  return e.handleSearchModeKeyCombo(keyComboOpt.get)
