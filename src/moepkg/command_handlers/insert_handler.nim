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

## Insert mode handler
##
## This module handles commands specific to Insert mode, including:
## - Character insertion
## - Backspace and delete
## - Navigation within insert mode
## - Mode switching (Escape)
## - Auto-completion (Ctrl+N/Ctrl+P to navigate, Tab to commit)
## - Macro recording support

import std/[options, unicode, strutils, monotimes]

import pkg/results

import
  ../[
    types, buffer, config, modes, key_bindings, motion, command_registry, unicode_utils,
    completion, signature_help, lsp_integration,
  ]
import handler_types, insert_commands
import ../editor_types
export handler_types

type
  InsertModeResultKind* = enum
    imrHandled
    imrUnhandled
    imrError

  InsertModeResult* = object ## Result of insert mode command execution
    case kind*: InsertModeResultKind
    of imrHandled:
      modeTransition*: Option[EditorMode]
      overlayTransition*: Option[OverlayKind]
    of imrUnhandled:
      discard
    of imrError:
      errorMessage*: string

proc newInsertModeHandler*(
    keyBindingRegistry: KeyBindingRegistry,
    motionController: MotionController,
    commandRegistry: CommandRegistry,
    lsp: LspIntegration = nil,
    autocompleteEnabled: bool = true,
    notificationConfig: NotificationConfig = NotificationConfig(),
): InsertModeHandler =
  ## Create a new Insert mode handler
  InsertModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    motionController: motionController,
    commandRegistry: commandRegistry,
    completionManager: newCompletionManager(),
    signatureHelpManager: newSignatureHelpManager(),
    lsp: lsp,
    autocompleteEnabled: autocompleteEnabled,
    notificationConfig: notificationConfig,
  )

proc executeCommand*(
    handler: InsertModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    commandId: string,
    args: seq[string] = @[],
): InsertModeResult =
  ## Execute a command using the CommandRegistry
  let ctx = CommandContext(
    buffer: buffer,
    state: state,
    viewport: viewport,
    motionController: handler.motionController,
    keyBindingRegistry: handler.keyBindingRegistry,
    notificationConfig: handler.notificationConfig,
  )

  let cmdResult = handler.commandRegistry.execute(ctx, commandId, args)
  if cmdResult.isOk:
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
  else:
    return InsertModeResult(kind: imrError, errorMessage: cmdResult.error)

proc handleCharacterInsertion*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState, text: string
): InsertModeResult =
  ## Handle regular character insertion with auto-close paren support
  let pos = state.cursor

  # Track paren depth for signature help
  if text.len == 1:
    if text[0] == '(':
      handler.signatureHelpManager.incrementParenDepth()
    elif text[0] == ')':
      handler.signatureHelpManager.decrementParenDepth()

  # Check if auto-close paren is enabled and text is a single character opening paren
  if state.display.autoCloseParen and text.len == 1 and isOpeningParen(text[0]):
    let openChar = text[0]
    let closeChar = getClosingChar(openChar)

    # Insert both opening and closing characters
    discard buffer.insertText(pos, text & $closeChar)

    # Move cursor to position between the pair (after opening char)
    state.cursor.column += 1
  else:
    # Normal insertion
    discard buffer.insertText(pos, text)

    # Move cursor right after insertion (by character count, not byte count)
    state.cursor.column += text.runeLen

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleBackspace*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Handle backspace key with auto-delete paren support
  let pos = state.cursor

  if pos.column > 0:
    # Check if auto-delete paren is enabled
    if state.display.autoDeleteParen:
      let currentLine = buffer.getLine(pos.line)
      let charBeforeCursor = currentLine.runeAtPos(pos.column - 1)

      try:
        # Auto-delete adjacent pairs only: cursor must be between open and close
        # e.g., (|), [|], {|}, "|", '|'
        if isAdjacentPair(currentLine, pos.column - 1):
          state.cursor.column -= 1
          discard buffer.deleteChar(state.cursor) # Delete opening char
          discard buffer.deleteChar(state.cursor) # Delete closing char
          return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
      except IndexDefect, CatchableError:
        # If accessing rune fails, fall through to normal backspace
        discard

    # softTabStop-aware backspace: delete to previous boundary in leading whitespace
    if state.display.expandTab:
      let currentLine = buffer.getLine(pos.line)
      # Check if cursor is within leading whitespace
      var allSpaces = true
      for i in 0 ..< pos.column:
        if i < currentLine.charLen:
          let ch = currentLine.runeAtPos(i)
          if ch != Rune(' ') and ch != Rune('\t'):
            allSpaces = false
            break
        else:
          allSpaces = false
          break
      if allSpaces and pos.column > 0:
        let sts = effectiveSoftTabStop(state)
        let tabWidth = max(1, sts)
        # Calculate how many chars to delete to reach previous boundary
        let remainder = pos.column mod tabWidth
        let deleteCount = if remainder == 0: tabWidth else: remainder
        let actualDelete = min(deleteCount, pos.column)
        for i in 0 ..< actualDelete:
          state.cursor.column -= 1
          discard buffer.deleteChar(state.cursor)
      else:
        # Normal backspace: move cursor back and delete
        state.cursor.column -= 1
        discard buffer.deleteChar(state.cursor)
    else:
      # Normal backspace: move cursor back and delete
      state.cursor.column -= 1
      discard buffer.deleteChar(state.cursor)
  elif pos.line > 0:
    # At start of line, join with previous line
    let prevLine = buffer.getLine(pos.line - 1)
    let currentLine = buffer.getLine(pos.line)
    let prevLineLen = prevLine.charLen

    # Delete the current line first
    discard buffer.deleteLine(pos.line)
    # Append current line content to previous line
    if currentLine.len > 0:
      discard buffer.insertText(
        BufferPosition(line: pos.line - 1, column: prevLineLen), currentLine
      )

    # Move cursor to the join point
    state.cursor.line -= 1
    state.cursor.column = prevLineLen

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleDelete*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Handle delete key
  discard buffer.deleteChar(state.cursor)

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleNewline*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Handle newline insertion with auto-indentation
  # Call the insert_commands implementation which has auto-indent logic
  insertNewline(buffer, state)

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleTab*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
): InsertModeResult =
  ## Handle tab key insertion
  ## Inserts either a tab character or spaces based on expandTab setting
  ## When expandTab is true, aligns to the next softTabStop boundary
  let pos = state.cursor

  if state.display.expandTab:
    # Insert spaces to align to next softTabStop boundary
    let sts = effectiveSoftTabStop(state)
    let tabWidth = max(1, sts) # Ensure at least 1 space
    let spacesToInsert = tabWidth - (pos.column mod tabWidth)
    let spaces = " ".repeat(spacesToInsert)

    let insertResult = buffer.insertText(pos, spaces)
    if insertResult.isErr:
      return InsertModeResult(
        kind: imrError, errorMessage: "Failed to insert spaces: " & insertResult.error
      )

    # Move cursor right by number of spaces inserted
    state.cursor.column += spacesToInsert
  else:
    # Insert actual tab character
    let insertResult = buffer.insertText(pos, "\t")
    if insertResult.isErr:
      return InsertModeResult(
        kind: imrError, errorMessage: "Failed to insert tab: " & insertResult.error
      )

    # Move cursor right after tab (1 character)
    state.cursor.column += 1

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleMotion*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState, motion: Motion
): InsertModeResult =
  ## Handle motion commands in insert mode
  let motionCmd = MotionCommand(motion: motion, count: 1)

  let r = handler.motionController.executeMotion(motionCmd, state.cursor)
  if r.isErr:
    return InsertModeResult(kind: imrError, errorMessage: r.error)
  state.cursor = r.value
  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleModeSwitch*(
    handler: InsertModeHandler, targetMode: EditorMode
): InsertModeResult =
  ## Handle mode switching from insert mode
  # Cancel completion and signature help when leaving insert mode
  handler.completionManager.cancelCompletion()
  handler.signatureHelpManager.hide()
  return InsertModeResult(kind: imrHandled, modeTransition: some(targetMode))

proc commitCompletion*(
    handler: InsertModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    keepPopupOpen: bool = false,
): InsertModeResult =
  ## Commit the selected completion item
  ## If keepPopupOpen is true, the popup remains visible for further selection
  ## Changes are added to the existing Insert mode transaction (do not start a new one)
  let entryOpt = handler.completionManager.getSelectedEntry()
  if entryOpt.isNone or entryOpt.get.word.len == 0:
    if not keepPopupOpen:
      handler.completionManager.cancelCompletion()
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  let entry = entryOpt.get
  let menu = handler.completionManager.menu

  # Note: We do NOT start a new transaction here because Insert mode already
  # has an active transaction. The completion changes will be part of that
  # transaction and undone together with other Insert mode edits.

  # For path completion, strip trailing '/' from directories so the user
  # can explicitly type '/' to drill in.
  let insertWord =
    if handler.completionManager.isPathCompletion and entry.word.endsWith("/"):
      entry.word[0 ..^ 2]
    else:
      entry.word

  if entry.textEdit.isSome and not keepPopupOpen:
    # Use textEdit for range-based replacement (LSP-provided edit)
    # Only used on final commit (not during Tab cycling) because the textEdit
    # range refers to the original buffer state and becomes invalid after cycling.
    let edit = entry.textEdit.get
    let applyResult = buffer.applyTextEdits(@[edit])
    if applyResult.isOk:
      # Position cursor at end of inserted text
      let newTextLines = edit.newText.split('\n')
      if newTextLines.len == 1:
        # Single-line edit: cursor at start column + newText length
        let startCol = utf16OffsetToUtf8(
          buffer.getLine(edit.range.start.line), edit.range.start.character
        )
        state.cursor.line = edit.range.start.line
        state.cursor.column = startCol + edit.newText.runeLen
      else:
        # Multi-line edit: cursor at end of last line
        let lastLine = edit.range.start.line + newTextLines.len - 1
        state.cursor.line = lastLine
        state.cursor.column = newTextLines[^1].runeLen

      # Apply additional text edits if present
      if entry.additionalTextEdits.isSome:
        discard buffer.applyTextEdits(entry.additionalTextEdits.get)
    else:
      # Fallback to simple prefix-deletion if textEdit application fails
      let prefixLen = menu.prefix.runeLen
      if prefixLen > 0:
        for _ in 0 ..< prefixLen:
          state.cursor.column -= 1
          discard buffer.deleteChar(state.cursor)
      discard buffer.insertText(state.cursor, entry.word)
      state.cursor.column += entry.word.runeLen
  else:
    # Simple prefix-deletion approach (no textEdit)
    let prefixLen = menu.prefix.runeLen
    if prefixLen > 0:
      for _ in 0 ..< prefixLen:
        state.cursor.column -= 1
        discard buffer.deleteChar(state.cursor)

    # Insert the selected word
    discard buffer.insertText(state.cursor, insertWord)
    state.cursor.column += insertWord.runeLen

  # Close the completion menu (unless keepPopupOpen)
  if not keepPopupOpen:
    handler.completionManager.cancelCompletion()
  else:
    # Update the prefix to the inserted text (so further cycling deletes it correctly)
    handler.completionManager.menu.prefix = insertWord

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc triggerLspCompletionRequest*(
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState
) =
  ## Trigger completion with LSP support
  ## Shows buffer completions immediately, then switches to LSP when response arrives

  # Skip if autocomplete is disabled
  if not handler.autocompleteEnabled:
    return

  # Extract prefix for debounce/skip check
  let line = buffer.getLine(state.cursor.line)
  let prefix = extractPrefixBeforeCursor(line, state.cursor.column)

  # If LSP is available, check if we can skip the request and filter client-side.
  # This must be checked BEFORE triggerCompletion, which clears lspItems.
  if not handler.lsp.isNil and handler.lsp.isEnabled:
    if handler.completionManager.shouldSkipLspRequest(prefix):
      # Filter existing LSP items client-side without clearing them
      if handler.completionManager.lspItems.len > 0:
        handler.completionManager.menu.prefix = prefix
        handler.completionManager.menu.entries =
          handler.completionManager.filterAndSortEntries(prefix)
        handler.completionManager.menu.selectedIndex = 0
        handler.completionManager.menu.scrollOffset = 0
        handler.completionManager.menu.hasSelection = false
        if handler.completionManager.menu.entries.len > 0:
          handler.completionManager.state = csActive
      return

  # First, show buffer completions immediately for instant feedback
  handler.completionManager.triggerCompletion(
    buffer, state.cursor.line, state.cursor.column, buffer.language
  )

  # If LSP is available, start async request in background
  if not handler.lsp.isNil and handler.lsp.isEnabled:
    # Cancel any pending LSP completion request to avoid orphaned responses
    let oldReqId = handler.completionManager.getLspRequestId
    if oldReqId.isSome:
      handler.lsp.cancelRequest(oldReqId.get)

    let reqResult =
      handler.lsp.startCompletionRequest(buffer, state.cursor.line, state.cursor.column)

    if reqResult.isOk:
      handler.completionManager.lastLspRequestTime = getMonoTime()
      handler.completionManager.lastLspPrefix = prefix
      handler.completionManager.setLspRequestPending(reqResult.get)

proc pollLspCompletion*(handler: InsertModeHandler) =
  ## Poll for pending LSP completion response
  if handler.lsp.isNil or not handler.lsp.isEnabled:
    return

  if not handler.completionManager.isPendingLsp:
    return

  let reqIdOpt = handler.completionManager.getLspRequestId
  if reqIdOpt.isNone:
    return

  # Poll LSP service for events
  handler.lsp.poll()

  # Check for response
  let (status, resultOpt, _) = handler.lsp.checkResponse(reqIdOpt.get)

  case status
  of lrsPending:
    discard # Still waiting
  of lrsSuccess:
    if resultOpt.isSome:
      let (items, rawJsonItems, isIncomplete) = parseCompletionResponse(resultOpt.get)
      handler.completionManager.setLspItems(items, rawJsonItems, isIncomplete)
  of lrsError, lrsTimeout:
    # Clear pending state on error/timeout
    handler.completionManager.setLspItems(@[])

proc triggerResolveRequest*(handler: InsertModeHandler, buffer: TextBuffer) =
  ## Trigger a completionItem/resolve request for the selected item
  if handler.lsp.isNil or not handler.lsp.isEnabled:
    return
  if not handler.completionManager.needsResolve():
    return

  let rawJsonOpt = handler.completionManager.getSelectedRawJson()
  if rawJsonOpt.isNone:
    return

  # Cancel any pending resolve request before starting a new one
  if handler.completionManager.resolveRequestId.isSome:
    handler.lsp.cancelRequest(handler.completionManager.resolveRequestId.get)
    handler.completionManager.resolveRequestId = none(int)

  let reqResult = handler.lsp.startCompletionResolveRequest(buffer, rawJsonOpt.get)
  if reqResult.isOk:
    handler.completionManager.resolveRequestId = some(reqResult.get)
    handler.completionManager.resolvedIndex =
      handler.completionManager.menu.selectedIndex

proc pollLspResolve*(handler: InsertModeHandler) =
  ## Poll for pending completionItem/resolve response
  if handler.lsp.isNil or not handler.lsp.isEnabled:
    return

  if handler.completionManager.resolveRequestId.isNone:
    return

  let reqId = handler.completionManager.resolveRequestId.get

  handler.lsp.poll()

  let (status, resultOpt, _) = handler.lsp.checkResponse(reqId)

  case status
  of lrsPending:
    discard
  of lrsSuccess:
    if resultOpt.isSome:
      let resolved = parseCompletionItem(resultOpt.get)
      handler.completionManager.updateResolvedEntry(resolved)
      handler.completionManager.updateDocPanel()
    handler.completionManager.resolveRequestId = none(int)
  of lrsError, lrsTimeout:
    handler.completionManager.resolveRequestId = none(int)

proc isCtrlN(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+N
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "n"

proc isCtrlP(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+P
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "p"

proc isCtrlSpace(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+Space (manual completion trigger)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and keyCombo.char == " "

proc isCtrlW(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+W (delete word backward)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "w"

proc isCtrlU(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+U (delete to line start)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "u"

proc isCtrlT(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+T (indent line)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "t"

proc isCtrlD(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+D (dedent line)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "d"

proc isCtrlE(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+E (insert char from below)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "e"

proc isCtrlY(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+Y (insert char from above)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "y"

proc isCtrlR(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+R (signature help)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "r"

proc isCtrlO(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+O (one-shot normal mode)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "o"

proc isCtrlI(keyCombo: KeyCombo): bool =
  ## Check if key is Ctrl+I (insert tab)
  not keyCombo.isSpecial and kmCtrl in keyCombo.modifiers and
    keyCombo.char.toLowerAscii == "i"

proc shouldTriggerSignatureHelp*(keyCombo: KeyCombo): bool =
  ## Check if the typed character should trigger signature help
  not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char.len == 1 and
    isTriggerChar(keyCombo.char[0])

proc shouldRetriggerSignatureHelp*(keyCombo: KeyCombo): bool =
  ## Check if the typed character should retrigger signature help
  not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char.len == 1 and
    isRetriggerChar(keyCombo.char[0])

proc handleInsertModeKey*(
    handler: InsertModeHandler, editor: Editor, keyCombo: KeyCombo
): InsertModeResult =
  ## Main entry point for handling Insert mode key presses
  let buffer = editor.activeBuffer
  let state = editor.state

  # Record key for macro if recording is active
  if state.macroState.isRecording:
    state.macroState.recordedKeys.add(keyComboToString(keyCombo))

  let completionActive = handler.completionManager.isActive()

  # Handle completion-specific keys when completion is active
  if completionActive:
    # Ctrl+N, Down, or Tab - select next and replace current word
    if keyCombo.isCtrlN or (keyCombo.isSpecial and keyCombo.special == skDown) or (
      keyCombo.isSpecial and keyCombo.special == skTab and
      kmShift notin keyCombo.modifiers
    ):
      # First Tab activates selection mode
      if not handler.completionManager.menu.hasSelection:
        handler.completionManager.menu.hasSelection = true
      else:
        handler.completionManager.selectNext()
      # Replace current word with selected one
      let commitResult = handler.commitCompletion(buffer, state, keepPopupOpen = true)
      handler.completionManager.updateDocPanel()
      handler.triggerResolveRequest(buffer)
      return commitResult

    # Ctrl+P, Up, or Shift+Tab/BackTab - select previous and replace current word
    if keyCombo.isCtrlP or (keyCombo.isSpecial and keyCombo.special == skUp) or (
      keyCombo.isSpecial and keyCombo.special == skTab and kmShift in keyCombo.modifiers
    ) or (keyCombo.isSpecial and keyCombo.special == skBackTab):
      # First Shift+Tab activates selection mode
      if not handler.completionManager.menu.hasSelection:
        handler.completionManager.menu.hasSelection = true
      else:
        handler.completionManager.selectPrevious()
      # Replace current word with selected one
      let commitResult = handler.commitCompletion(buffer, state, keepPopupOpen = true)
      handler.completionManager.updateDocPanel()
      handler.triggerResolveRequest(buffer)
      return commitResult

    # Enter - confirm selection and close popup
    if keyCombo.isSpecial and keyCombo.special == skEnter:
      handler.completionManager.cancelCompletion()
      return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

    # Escape - cancel completion and leave insert mode
    if keyCombo.isSpecial and keyCombo.special == skEscape:
      handler.completionManager.cancelCompletion()
      return handler.handleModeSwitch(EditorMode.Normal)

    # Backspace - update filter or cancel if prefix is empty
    if keyCombo.isSpecial and keyCombo.special == skBackspace:
      let backspaceResult = handler.handleBackspace(buffer, state)
      if handler.completionManager.isPathCompletion:
        # Re-check path context after backspace
        let line = buffer.getLine(state.cursor.line)
        let pathPrefix = extractPathPrefixBeforeCursor(line, state.cursor.column)
        if pathPrefix.len > 0:
          handler.completionManager.triggerPathCompletion(
            buffer, state.cursor.line, state.cursor.column
          )
        else:
          handler.completionManager.cancelCompletion()
      else:
        # Update completion filter with new prefix
        let line = buffer.getLine(state.cursor.line)
        let newPrefix = extractPrefixBeforeCursor(line, state.cursor.column)
        if newPrefix.len >= MinPrefixLength:
          handler.completionManager.updateFilter(newPrefix)
        else:
          handler.completionManager.cancelCompletion()
      return backspaceResult

    # Regular character input while completion is active
    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      let hasSelection = handler.completionManager.menu.hasSelection
      let wasPathCompletion = handler.completionManager.isPathCompletion

      if hasSelection and not wasPathCompletion:
        # Confirm current selection and close popup (non-path only)
        handler.completionManager.cancelCompletion()

      # Insert the new character
      discard handler.handleCharacterInsertion(buffer, state, keyCombo.char)

      # Re-trigger completion with new prefix
      let line = buffer.getLine(state.cursor.line)
      let pathPrefix = extractPathPrefixBeforeCursor(line, state.cursor.column)
      if pathPrefix.len > 0:
        handler.completionManager.triggerPathCompletion(
          buffer, state.cursor.line, state.cursor.column
        )
      else:
        let newPrefix = extractPrefixBeforeCursor(line, state.cursor.column)
        if newPrefix.len >= AutoTriggerPrefixLength:
          # Show buffer completions immediately, LSP will update when ready
          handler.triggerLspCompletionRequest(buffer, state)
        else:
          handler.completionManager.cancelCompletion()
      return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+N - trigger completion (when not active)
  if keyCombo.isCtrlN and not completionActive:
    # Show buffer completions immediately, LSP will update when ready
    handler.triggerLspCompletionRequest(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+Space - also trigger completion
  if keyCombo.isCtrlSpace and not completionActive:
    # Show buffer completions immediately, LSP will update when ready
    handler.triggerLspCompletionRequest(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+W - delete word backward
  if keyCombo.isCtrlW:
    handler.completionManager.cancelCompletion()
    deleteWordBackward(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+U - delete to line start
  if keyCombo.isCtrlU:
    handler.completionManager.cancelCompletion()
    deleteToLineStart(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+T - indent line
  if keyCombo.isCtrlT:
    handler.completionManager.cancelCompletion()
    indentLine(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+D - dedent line
  if keyCombo.isCtrlD:
    handler.completionManager.cancelCompletion()
    dedentLine(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+E - insert character from line below
  if keyCombo.isCtrlE:
    handler.completionManager.cancelCompletion()
    discard insertCharFromBelow(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+Y - insert character from line above
  if keyCombo.isCtrlY:
    handler.completionManager.cancelCompletion()
    discard insertCharFromAbove(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+R - trigger signature help (LSP)
  if keyCombo.isCtrlR:
    handler.completionManager.cancelCompletion()
    # Request signature help from LSP if available
    if not handler.lsp.isNil and handler.lsp.isEnabled:
      # Cancel any pending signature help request
      if state.lspCache.pendingSignatureHelpRequestId != 0:
        handler.lsp.cancelRequest(state.lspCache.pendingSignatureHelpRequestId)
        state.lspCache.pendingSignatureHelpRequestId = 0
      let reqResult = handler.lsp.startSignatureHelpRequest(
        buffer, state.cursor.line, state.cursor.column
      )
      if reqResult.isOk:
        state.lspCache.pendingSignatureHelpRequestId = reqResult.get
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+O - execute one Normal mode command then return to Insert mode
  if keyCombo.isCtrlO:
    handler.completionManager.cancelCompletion()
    handler.signatureHelpManager.hide()
    state.insertNormalMode = true
    return InsertModeResult(kind: imrHandled, modeTransition: some(EditorMode.Normal))

  # Ctrl+I - insert tab
  if keyCombo.isCtrlI:
    return handler.handleTab(buffer, state)

  # Check for mode switch keys (like Escape)
  let binding = handler.keyBindingRegistry.findBinding(EditorMode.Insert, keyCombo)
  if binding.isSome:
    let cmd = binding.get
    case cmd.kind
    of ctModeSwitch:
      return handler.handleModeSwitch(cmd.targetMode)
    of ctOverlaySwitch:
      # Overlay switches not supported in insert mode
      return InsertModeResult(kind: imrUnhandled)
    of ctMotion:
      # Cancel completion on motion
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, cmd.motion)
    of ctAction, ctCustom:
      # Handle action commands (e.g., from :imap)
      handler.completionManager.cancelCompletion()
      case cmd.commandId
      of "insert.backspace":
        return handler.handleBackspace(buffer, state)
      of "insert.delete":
        return handler.handleDelete(buffer, state)
      of "insert.newline":
        return handler.handleNewline(buffer, state)
      else:
        return InsertModeResult(kind: imrUnhandled)
    else:
      # Other command types not supported in insert mode
      return InsertModeResult(kind: imrUnhandled)

  # Handle regular character insertion with auto-completion trigger
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    discard handler.handleCharacterInsertion(buffer, state, keyCombo.char)
    # Check for path completion first
    let line = buffer.getLine(state.cursor.line)
    let pathPrefix = extractPathPrefixBeforeCursor(line, state.cursor.column)
    if pathPrefix.len > 0:
      handler.completionManager.triggerPathCompletion(
        buffer, state.cursor.line, state.cursor.column
      )
    else:
      # Auto-trigger word completion after typing (when prefix is long enough)
      let prefix = extractPrefixBeforeCursor(line, state.cursor.column)
      if prefix.len >= AutoTriggerPrefixLength:
        # Show buffer completions immediately, LSP will update when ready
        handler.triggerLspCompletionRequest(buffer, state)
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Handle special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skBackspace:
      return handler.handleBackspace(buffer, state)
    of skDelete:
      return handler.handleDelete(buffer, state)
    of skEnter:
      return handler.handleNewline(buffer, state)
    of skTab:
      return handler.handleTab(buffer, state)
    of skLeft:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.Left)
    of skRight:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.Right)
    of skUp:
      return handler.handleMotion(buffer, state, Motion.Up)
    of skDown:
      return handler.handleMotion(buffer, state, Motion.Down)
    of skHome:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.Home)
    of skEnd:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.End)
    of skPageUp:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.PageUp)
    of skPageDown:
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, Motion.PageDown)
    else:
      return InsertModeResult(kind: imrUnhandled)

  # Unhandled key combination
  return InsertModeResult(kind: imrUnhandled)

proc isHandled*(imResult: InsertModeResult): bool =
  ## Check if the command was handled
  imResult.kind == imrHandled

proc hasError*(imResult: InsertModeResult): bool =
  ## Check if there was an error
  imResult.kind == imrError

proc getModeTransition*(imResult: InsertModeResult): Option[EditorMode] =
  ## Get the mode transition if any
  if imResult.kind == imrHandled:
    imResult.modeTransition
  else:
    none(EditorMode)

proc getOverlayTransition*(imResult: InsertModeResult): Option[OverlayKind] =
  ## Get the overlay transition if any
  if imResult.kind == imrHandled:
    imResult.overlayTransition
  else:
    none(OverlayKind)
