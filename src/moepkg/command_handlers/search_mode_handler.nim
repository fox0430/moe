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

import std/[options, strutils]

import pkg/results

import ../celina_backend as celina

import
  ../[
    editor, key_bindings, modes, buffer, types, help_viewer, config_mode, unicode_utils,
    search_ops, fold_open, pending_input,
  ]
import ../command_registry/core
import command_mode_handler, result_processor

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
      discard window.modeState.config.refreshItems(e.state)
      return window.modeState.config
  return nil

proc showFromSearchStart(e: Editor, pos: BufferPosition) =
  ## Scroll to `pos` from what the window showed as the search began, as
  ## Vim's incsearch restores the view before it moves to a match.
  let view = e.state.input.search.startView
  if view.isSome:
    e.showFromView(view.get, pos)
  else:
    e.updateViewportForCursor(pos)

proc backToSearchStart(e: Editor) =
  e.cursor = e.state.input.search.startPos
  e.showFromSearchStart(e.state.input.search.startPos)
  e.syncHelpViewerIndex(e.state.input.search.startPos.line)

proc searchFromStart(e: Editor, spec: SearchSpec): bool =
  ## Run `spec` from where the search began, as Vim's Enter does whatever
  ## incsearch showed, and move there or back to the anchor.
  let found = e.state.searchSubmitted(
    e.activeBuffer, spec, e.state.input.search.startPos, e.state.input.search.count
  )
  if found.isSome:
    e.cursor = found.get
    e.state.openCursorFolds()
    if e.state.input.search.incsearch:
      e.showFromSearchStart(e.cursor)
    else:
      e.updateViewportForCursor(e.cursor)
    return true
  elif e.state.input.search.incsearch:
    e.backToSearchStart()

proc operateOverSearch(e: Editor, typed: string): bool =
  ## Enter with an operator waiting (`d/foo`): it acts from where the search
  ## began up to the match, as Vim's normal_search, and `.` searches for
  ## `typed` again.
  e.cursor = e.state.input.search.startPos
  let ctx = newCommandContext(
    e.activeBuffer, e.state, e.viewport, e.motionController, e.keyBindingRegistry
  )
  let operated = e.commandRegistry.finishOperator(
    ctx,
    Operand(
      kind: odSearch,
      count: e.state.input.search.count,
      countGiven: e.state.input.search.countGiven,
      searchText: typed,
      searchDirection: e.state.input.search.direction,
    ),
  )
  if operated.isErr:
    e.state.statusMessage = operated.error
  e.showFromSearchStart(e.cursor)
  operated.isOk

proc goToSearch(e: Editor, spec: SearchSpec, isRepeat: bool): bool =
  ## Move to the match of `spec`, the search Enter made the last one, from
  ## where the search began: the selection in Config mode, the cursor
  ## elsewhere. `isRepeat` for an empty `/`, which repeats the last search.
  ## Returns whether there was one.
  let pattern = spec.pattern
  let cfg = e.activeConfigState()
  if cfg != nil:
    # Config mode: commit the query and move the selection to the first match,
    # anchored from where the search started.
    cfg.setSearchQuery(pattern, e.state.input.search.direction)
    let forward = e.state.input.search.direction == Forward
    # searchItems scans inclusive of its start index, so a repeat, which
    # opens with the selection already on a match, steps off it first.
    let startIndex =
      if not isRepeat:
        cfg.searchStartIndex
      elif forward:
        cfg.searchStartIndex + 1
      else:
        cfg.searchStartIndex - 1
    result = cfg.searchItems(pattern, startIndex, forward).isSome
    e.state.statusMessage =
      if result:
        "Found: " & pattern
      else:
        "Pattern not found: " & pattern
  else:
    # Vim records a jump for a search that found something, even one that
    # wrapped back to the anchor.
    result = e.searchFromStart(spec)
    if result:
      recordJump(e.state, e.state.input.search.startPos)

    # Sync search query and position to help viewer state if in Help mode
    if e.state.mode == EditorMode.Help:
      let window = e.activeWindow
      if window.modeState.kind == mskHelp:
        window.modeState.help.setSearchQuery(pattern, e.state.input.search.direction)
    e.syncHelpViewerIndex(e.cursor.line)

proc finalizeSearch(e: Editor): bool =
  ## Finalize search and return to Normal mode
  ##
  ## Called when: Enter is pressed in Search mode
  ##
  ## Behavior:
  ## - Empty input repeats the last search (vim's `/<CR>` and `?<CR>`)
  ## - Search again from where the search began; incsearch only previews
  ## - Save searchText to lastSearchText for n/N commands
  ## - Re-enable search highlight (hlsearch)
  ## - Apply an operator waiting for the search (`d/foo`)
  ## - Transition to Normal mode
  ## - Clear searchText buffer
  ##
  ## Returns whether the search found a match.
  let typed = e.state.input.search.text
  if e.state.pendingInput.pendingOperator.isSome:
    result = e.operateOverSearch(typed)
  else:
    let spec = e.state.submitSearch(typed, e.state.input.search.direction)
    if spec.isSome:
      result = e.goToSearch(spec.get, isRepeat = typed.len == 0)

  # Exit overlay and return to base mode
  # The base mode (Normal, LogViewer, Filer, etc.) is preserved
  e.state.exitOverlay()
  e.setMode(e.state.mode) # Sync window mode

proc cancelSearch*(e: Editor) =
  ## Cancel search and return to base mode
  ##
  ## Called when: Escape or Ctrl-C is pressed in Search mode
  ##
  ## Behavior:
  ## - If incsearch enabled: Restore cursor to original position (searchStartPos)
  ## - Exit overlay and return to base mode
  ## - Clear searchText buffer
  ## - Does NOT save to lastSearchText (search was cancelled)
  ## - Cancels an operator waiting for it (`d/foo<Esc>`), as Vim's clearop

  e.state.pendingInput.cancelOperatorPending()
  let cfg = e.activeConfigState()
  if cfg != nil:
    # Config mode: restore the selection that was active before the search.
    if e.state.input.search.incsearch:
      cfg.selectedIndex = cfg.searchStartIndex
  elif e.state.input.search.incsearch:
    e.backToSearchStart()
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
  ## - Leaves the message alone, as Vim reports only on Enter
  ##
  ## This provides real-time feedback as the user types their search query.
  if not e.state.input.search.incsearch:
    return

  let cfg = e.activeConfigState()
  if cfg != nil:
    # Config mode: live-search the item list from the search start anchor. No
    # match (and an empty text matches none) restores the anchor, as the
    # buffer branch does.
    let forward = e.state.input.search.direction == Forward
    if cfg.searchItems(e.state.input.search.text, cfg.searchStartIndex, forward).isNone:
      cfg.selectedIndex = cfg.searchStartIndex
    return

  if e.state.input.search.text.len == 0:
    # Erasing the pattern restores the anchor, as the Config branch does.
    e.backToSearchStart()
    return

  let searchResult = e.state.findCounted(
    e.activeBuffer,
    SearchSpec(
      pattern: e.state.input.search.text, direction: e.state.input.search.direction
    ),
    e.state.input.search.startPos,
    e.state.input.search.count,
  )

  if searchResult.isSome:
    let pos = searchResult.get
    e.cursor = pos
    e.syncHelpViewerIndex(pos.line)

    e.showFromSearchStart(pos)
  else:
    e.backToSearchStart()

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
  # Recompute from the insertion end byte so a seam merge between the
  # existing bytes and the input keeps the cursor on the inserted tail.
  e.state.input.search.cursor =
    byteToCharPos(e.state.input.search.text, bytePos + ch.len)
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
  # Recompute from the insertion end byte so a seam merge between the
  # existing bytes and the paste keeps the cursor on the inserted tail.
  e.state.input.search.cursor =
    byteToCharPos(e.state.input.search.text, bytePos + insertText.len)
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

proc handleSearchModeKeyCombo*(e: Editor, keyCombo: KeyCombo): ReplayOutcome =
  ## Handle a KeyCombo in Search mode. Same dispatch as `handleSearchModeEvent`
  ## but reachable from replay paths (macro playback, runtime mapping RHS) that
  ## already hold a KeyCombo rather than a raw Event. `roAbort` when Enter
  ## runs a search that fails, so the keys a register or mapping queued after
  ## it are dropped, as Vim's error flushes them.
  # Escape: Cancel search and return to previous mode
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    e.cancelSearch()
    return roContinue

  # Enter: Execute search and return to Normal mode
  let isEnter =
    (keyCombo.isSpecial and keyCombo.special == skEnter) or
    (not keyCombo.isSpecial and (keyCombo.char == "\n" or keyCombo.char == "\r"))

  if isEnter:
    return if e.finalizeSearch(): roContinue else: roAbort

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
      e.state.input.search.cursor = e.state.input.search.text.charLen
      # Trigger incremental search with history entry
      e.performIncrementalSearch()
    return roContinue

  # Down arrow: Navigate to next (newer) search in history
  if keyCombo.isSpecial and keyCombo.special == skDown:
    if e.state.input.search.history.len > 0 and e.state.input.search.historyIndex >= 0:
      # Move to newer entry
      if e.state.input.search.historyIndex > 0:
        e.state.input.search.historyIndex -= 1
        e.state.input.search.text =
          e.state.input.search.history[e.state.input.search.historyIndex]
        e.state.input.search.cursor = e.state.input.search.text.charLen
        e.performIncrementalSearch()
      else:
        # Reached the newest entry, clear search text
        e.state.input.search.historyIndex = -1
        e.state.input.search.text = ""
        e.state.input.search.cursor = 0
        # Empty text restores the anchor (cursor, viewport and Config index).
        e.performIncrementalSearch()
    return roContinue

  # Left arrow: Move cursor left within search text
  if keyCombo.isSpecial and keyCombo.special == skLeft:
    if e.state.input.search.cursor > 0:
      e.state.input.search.cursor -= 1
    return roContinue

  # Right arrow: Move cursor right within search text
  if keyCombo.isSpecial and keyCombo.special == skRight:
    if e.state.input.search.cursor < e.state.input.search.text.charLen:
      e.state.input.search.cursor += 1
    return roContinue

  # Home: Move cursor to start of search text
  if keyCombo.isSpecial and keyCombo.special == skHome:
    e.state.input.search.cursor = 0
    return roContinue

  # End: Move cursor to end of search text
  if keyCombo.isSpecial and keyCombo.special == skEnd:
    e.state.input.search.cursor = e.state.input.search.text.charLen
    return roContinue

  # Delete: Remove character at cursor position
  if keyCombo.isSpecial and keyCombo.special == skDelete:
    if e.state.input.search.cursor < e.state.input.search.text.charLen:
      # Reset history navigation when user edits
      e.state.input.search.historyIndex = -1
      e.state.input.search.text =
        e.state.input.search.text.deleteCharAt(e.state.input.search.cursor)
      e.performIncrementalSearch()
    return roContinue

  # Backspace: Remove last character and re-search
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    # Reset history navigation when user types
    e.state.input.search.historyIndex = -1
    e.handleSearchBackspace()
    return roContinue

  # Character input: Add character and perform incremental search
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    # Reset history navigation when user types
    e.state.input.search.historyIndex = -1
    e.handleSearchCharacterInput(keyCombo.char)
    return roContinue

  # Ignore other special keys
  roContinue

proc handleSearchModeEvent*(e: Editor, event: Event): ReplayOutcome =
  ## Handle Search mode events - main event dispatcher.
  ## Extracts the KeyCombo and forwards to `handleSearchModeKeyCombo`, which
  ## replay paths call directly.
  if event.kind != EventKind.Key:
    return roContinue
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return roContinue
  return e.handleSearchModeKeyCombo(keyComboOpt.get)
