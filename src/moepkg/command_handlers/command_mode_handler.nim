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

import std/[options, os, strutils, unicode]

import pkg/[celina, chronos]

import
  ../[
    editor, key_bindings, modes, buffer, types, command_line, command_completion,
    unicode_utils, key_router,
  ]
import handler_manager
import ./editor_ops
import ./result_processor
export editor_ops

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
    e.activeWindow.viewport.resetViewportTop(
      e.state.ui.substitutePreview.originalTopLine
    )
    e.activeWindow.viewport.leftColumn = e.state.ui.substitutePreview.originalLeftColumn

proc updateSubstitutePreviewIfNeeded(e: Editor) =
  ## Update or cancel the live substitute preview based on the current command
  ## text. Call after any edit to commandText (backspace, delete, char input).
  ##
  ## Behavior:
  ## - Pattern only (e.g. ":%s/foo"): jump cursor to first match (incsearch-like)
  ## - Pattern + replacement (e.g. ":%s/foo/bar"): also preview the replacement
  ##   in the buffer when config.highlight.replaceText is enabled.
  if e.state.input.commandText.contains("s/"):
    let pattern = extractSubstitutePattern(e.state.input.commandText)
    let (replacement, hasReplacement) =
      extractSubstituteReplacement(e.state.input.commandText)
    let flags = extractSubstituteFlags(e.state.input.commandText)
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
      e.jumpToFirstSubstituteMatch(pattern)
    elif e.state.ui.substitutePreview.isActive:
      e.cancelSubstitutePreview()

proc handleCommandModeKeyCombo*(e: Editor, keyCombo: KeyCombo): bool

proc insertPastedTextInCommand*(e: Editor, text: string) =
  ## Insert pasted text at the current command-line cursor.
  ## The command line is single-line: only the first line of the paste is used
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

  e.state.input.commandState.historyIndex = -1
  if e.state.input.commandText.len == 0:
    e.state.input.commandText = ":"
    e.state.input.commandCursor = 0

  let bytePos =
    charToBytePos(e.state.input.commandText, e.state.input.commandCursor + 1)
  e.state.input.commandText =
    e.state.input.commandText[0 ..< bytePos] & insertText &
    e.state.input.commandText[bytePos ..^ 1]
  e.state.input.commandCursor += insertText.runeLen

  e.state.commandCompletionManager.cancelCompletion()
  e.updateSubstitutePreviewIfNeeded()

proc handleCommandModeEvent*(e: Editor, event: Event): bool =
  ## Handle Command mode events (special handling for text input)
  if event.kind != EventKind.Key:
    return true

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return true

  return e.handleCommandModeKeyCombo(keyComboOpt.get)

proc findHistoryMatch(
    history: seq[string], prefix: string, startIndex, step: int
): int =
  ## Find the next history entry starting with `prefix`, scanning from
  ## `startIndex` by `step` (+1 = older, -1 = newer). Returns -1 if none.
  var i = startIndex
  while i >= 0 and i <= history.high:
    if history[i].startsWith(prefix):
      return i
    i += step
  return -1

proc handleCommandModeKeyCombo*(e: Editor, keyCombo: KeyCombo): bool =
  ## Handle a KeyCombo in command-line mode, with runtime mapping support.
  ##
  ## Runtime-mapping routing is delegated to `KeyRouter.feedKey`. Command
  ## overlay execution differs from base mode in one way: on no-match flush
  ## we replay *all* accumulated keys (including the current one) and return
  ## without falling through.
  if not e.keyBindingRegistry.isReplayingMapping:
    let route = e.keyRouter.feedKey(EditorMode.Command, keyCombo)
    case route.kind
    of rrUnhandled, rrCancelled, rrCommand:
      discard # Fall through to normal handling (rrCommand never from feedKey)
    of rrExecuteRuntimeCommand:
      # Unreachable: the Command overlay's mappings table is filtered to
      # key-seq only (see `KeyRouter.mappingsFor`), so `feedKey` never
      # returns rrExecuteRuntimeCommand for `EditorMode.Command`. Guarded
      # for case exhaustiveness; keep the historical no-op for safety.
      return true
    of rrExecuteRuntimeKeySequence:
      # Command overlay always replays verbatim (non-recursive), even for a
      # :cmap. handleCommandModeKeyCombo has no mapping-expansion precheck, so
      # noremap is not honoured here (known limitation).
      var replayResult = true
      e.keyRouter.withReplay:
        for k in route.targetKeys:
          if not e.handleCommandModeKeyCombo(k):
            replayResult = false
            break
      return replayResult
    of rrWaiting:
      return true
    of rrUnhandledBatch:
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
    let hasSpace = ' ' in e.state.input.commandText

    proc applyCompletion(): bool =
      ## Apply the selected completion to command text
      ## Returns true if a directory was selected (needs re-trigger)
      let selected = mgr.getSelectedCommand()
      if selected.len == 0:
        return false

      case mgr.mode
      of cmCommand:
        e.state.input.commandText = ":" & selected
        e.state.input.commandCursor = selected.runeLen
        return false
      of cmFilePath:
        # Use original directory prefix (saved when completion started)
        let newArg = mgr.originalDirPrefix & selected
        e.state.input.commandText = ":" & mgr.baseCommand & " " & newArg
        e.state.input.commandCursor = mgr.baseCommand.runeLen + 1 + newArg.runeLen
        # Return true if directory selected (ends with /)
        return selected.endsWith("/")
      of cmSetOption:
        # Replace only the argument part
        let (cmd, _) = parseCommandLine(e.state.input.commandText)
        e.state.input.commandText = ":" & cmd & " " & selected
        e.state.input.commandCursor = cmd.runeLen + 1 + selected.runeLen
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
          mgr.triggerArgumentCompletion(e.state.input.commandText, getCurrentDir())
        else:
          mgr.triggerCompletion(e.commandLineParser, e.state.input.commandText)
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
        mgr.triggerArgumentCompletion(e.state.input.commandText, getCurrentDir())
        return true
      # If not a no-argument command, wait for more input
      if not shouldExecuteNow:
        return true
      # Otherwise, fall through to execute the command immediately

    if e.state.input.commandText.len > 1: # Must have something after :
      # Full-lifecycle dispatch (pre-teardown, side effects, post-teardown,
      # Insert-Normal recovery) is centralised in executeCommandOverlay so
      # the Command overlay Enter path and hrExecCommand (@:) share a single
      # entry point.
      return e.executeCommandOverlay(e.state.input.commandText)

    # Empty command (just ":"): no dispatch, just return to base mode.
    e.state.exitOverlay()
    e.setMode(e.state.mode)
    e.state.input.commandText = ""
    e.state.input.commandCursor = 0
    if e.state.insertNormalMode:
      if e.state.mode == EditorMode.Normal:
        e.state.insertNormalMode = false
        e.setMode(EditorMode.Insert)
      elif e.state.mode != EditorMode.Insert:
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
    if e.state.input.commandCursor > 0:
      e.state.input.commandCursor -= 1
      e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle Right arrow - move cursor right
  if keyCombo.isSpecial and keyCombo.special == skRight:
    # commandText includes the ":" prefix, so max cursor position is runeLen - 1
    let maxPos = e.state.input.commandText.runeLen - 1
    if e.state.input.commandCursor < maxPos:
      e.state.input.commandCursor += 1
      e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle Backspace - delete character before cursor
  if keyCombo.isSpecial and keyCombo.special == skBackspace:
    e.state.input.commandState.historyIndex = -1
    if e.state.input.commandCursor > 0 and e.state.input.commandText.runeLen > 1:
      # Delete the character before cursor (commandCursor is 0-based after ":")
      let pos = e.state.input.commandCursor # Character position in commandText
      e.state.input.commandText = e.state.input.commandText.deleteCharAt(pos)
      e.state.input.commandCursor -= 1
      # Update completion
      let mgr = e.state.commandCompletionManager
      if ' ' in e.state.input.commandText:
        # Argument mode
        mgr.triggerArgumentCompletion(e.state.input.commandText, getCurrentDir())
      elif mgr.isActive():
        let prefix = extractCommandPrefix(e.state.input.commandText)
        mgr.updateFilter(prefix)
      e.updateSubstitutePreviewIfNeeded()
    return true

  # Handle Delete - delete character at cursor
  if keyCombo.isSpecial and keyCombo.special == skDelete:
    let charPos = e.state.input.commandCursor + 1
      # Character position in commandText (after ":")
    if charPos < e.state.input.commandText.runeLen:
      e.state.input.commandText = e.state.input.commandText.deleteCharAt(charPos)
      # Update completion
      let mgr = e.state.commandCompletionManager
      if ' ' in e.state.input.commandText:
        # Argument mode
        mgr.triggerArgumentCompletion(e.state.input.commandText, getCurrentDir())
      elif mgr.isActive():
        let prefix = extractCommandPrefix(e.state.input.commandText)
        mgr.updateFilter(prefix)
      e.updateSubstitutePreviewIfNeeded()
    return true

  # Handle Home - move cursor to beginning
  if keyCombo.isSpecial and keyCombo.special == skHome:
    e.state.input.commandCursor = 0
    e.state.commandCompletionManager.cancelCompletion()
    return true

  # Handle End - move cursor to end
  if keyCombo.isSpecial and keyCombo.special == skEnd:
    e.state.input.commandCursor = e.state.input.commandText.runeLen - 1
    e.state.commandCompletionManager.cancelCompletion()
    return true

  # Up arrow: Navigate to previous (older) command in history, restricted to
  # entries starting with the prefix captured when navigation began.
  if keyCombo.isSpecial and keyCombo.special == skUp:
    if e.state.input.commandState.history.len > 0:
      let startIndex =
        if e.state.input.commandState.historyIndex == -1:
          # First Up: lock the current text as the prefix filter.
          e.state.input.commandState.historyPrefix = e.state.input.commandText[1 ..^ 1]
          0
        else:
          e.state.input.commandState.historyIndex + 1
      let idx = findHistoryMatch(
        e.state.input.commandState.history, e.state.input.commandState.historyPrefix,
        startIndex, 1,
      )
      if idx >= 0:
        e.state.input.commandState.historyIndex = idx
        e.state.input.commandText = ":" & e.state.input.commandState.history[idx]
        e.state.input.commandCursor = e.state.input.commandText.runeLen - 1
        e.state.commandCompletionManager.cancelCompletion()
        e.updateSubstitutePreviewIfNeeded()
    return true

  # Down arrow: Navigate to next (newer) command in history, restricted to
  # entries starting with the locked prefix. Falling off the newest match
  # restores the original prefix instead of clearing the line.
  if keyCombo.isSpecial and keyCombo.special == skDown:
    if e.state.input.commandState.history.len > 0 and
        e.state.input.commandState.historyIndex >= 0:
      let idx = findHistoryMatch(
        e.state.input.commandState.history,
        e.state.input.commandState.historyPrefix,
        e.state.input.commandState.historyIndex - 1,
        -1,
      )
      if idx >= 0:
        e.state.input.commandState.historyIndex = idx
        e.state.input.commandText = ":" & e.state.input.commandState.history[idx]
        e.state.input.commandCursor = e.state.input.commandText.runeLen - 1
      else:
        e.state.input.commandState.historyIndex = -1
        e.state.input.commandText = ":" & e.state.input.commandState.historyPrefix
        e.state.input.commandCursor = e.state.input.commandState.historyPrefix.runeLen
      e.state.commandCompletionManager.cancelCompletion()
      e.updateSubstitutePreviewIfNeeded()
    return true

  # Handle character input - insert at cursor position
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    e.state.input.commandState.historyIndex = -1
    # Guard against empty commandText (should have at least ":")
    if e.state.input.commandText.len == 0:
      e.state.input.commandText = ":"
      e.state.input.commandCursor = 0
    let bytePos =
      charToBytePos(e.state.input.commandText, e.state.input.commandCursor + 1)
    e.state.input.commandText =
      e.state.input.commandText[0 ..< bytePos] & keyCombo.char &
      e.state.input.commandText[bytePos ..^ 1]
    e.state.input.commandCursor += keyCombo.char.runeLen
    # Handle completion
    let mgr = e.state.commandCompletionManager
    let hasSpace = ' ' in e.state.input.commandText
    if keyCombo.char == " ":
      # Space is a delimiter - trigger argument completion if applicable
      mgr.cancelCompletion()
      mgr.triggerArgumentCompletion(e.state.input.commandText, getCurrentDir())
    elif hasSpace:
      # In argument mode - always update argument completion
      mgr.triggerArgumentCompletion(e.state.input.commandText, getCurrentDir())
    elif mgr.isActive():
      let prefix = extractCommandPrefix(e.state.input.commandText)
      mgr.updateFilter(prefix)
    else:
      # Auto-trigger command completion on first character
      mgr.triggerCompletion(e.commandLineParser, e.state.input.commandText)
    e.updateSubstitutePreviewIfNeeded()
    return true

  # Ignore other special keys
  return true
