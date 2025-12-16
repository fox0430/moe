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

## Insert mode handler
##
## This module handles commands specific to Insert mode, including:
## - Character insertion
## - Backspace and delete
## - Navigation within insert mode
## - Mode switching (Escape)
## - Auto-completion (Ctrl+N/Ctrl+P to navigate, Tab to commit)
## - Macro recording support

import std/[options, unicode, strutils]

import pkg/results

import
  ../[
    types, buffer, modes, keybindings, motion, commandregistry, unicode_utils,
    completion, signaturehelp,
  ]
import insert_commands

type
  InsertModeResultKind* = enum
    imrHandled
    imrUnhandled
    imrError

  InsertModeHandler* = ref object ## Handler for Insert mode specific commands
    keyBindingRegistry*: KeyBindingRegistry
    motionController*: MotionController
    commandRegistry*: CommandRegistry
    completionManager*: CompletionManager
    signatureHelpManager*: SignatureHelpManager

  InsertModeResult* = object ## Result of insert mode command execution
    case kind*: InsertModeResultKind
    of imrHandled:
      modeTransition*: Option[EditorMode]
    of imrUnhandled:
      discard
    of imrError:
      errorMessage*: string

proc newInsertModeHandler*(
    keyBindingRegistry: KeyBindingRegistry,
    motionController: MotionController,
    commandRegistry: CommandRegistry,
): InsertModeHandler =
  ## Create a new Insert mode handler
  InsertModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    motionController: motionController,
    commandRegistry: commandRegistry,
    completionManager: newCompletionManager(),
    signatureHelpManager: newSignatureHelpManager(),
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
  if state.autoCloseParen and text.len == 1 and isOpeningParen(text[0]):
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
    if state.autoDeleteParen:
      # Get the character before cursor (the one to be deleted)
      let currentLine = buffer.getLine(pos.line)
      let lineCharLen = currentLine.charLen

      # Need at least 2 characters: one before cursor and one after
      if pos.column >= 1 and pos.column < lineCharLen:
        try:
          # Get the characters before and after cursor as strings
          let beforeStr = $currentLine.runeAtPos(pos.column - 1)
          let afterStr = $currentLine.runeAtPos(pos.column)

          # Check if both are single-byte ASCII characters
          if beforeStr.len == 1 and afterStr.len == 1:
            let beforeChar = beforeStr[0]
            let afterChar = afterStr[0]

            # Check if it's a matching paren pair
            if isMatchingPair(beforeChar, afterChar):
              # Delete both characters
              state.cursor.column -= 1
              discard buffer.deleteChar(state.cursor) # Delete opening paren
              discard buffer.deleteChar(state.cursor) # Delete closing paren
              return
                InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
        except IndexDefect, CatchableError:
          # If accessing rune fails, just fall through to normal backspace
          discard

    # Normal backspace: move cursor back and delete
    state.cursor.column -= 1
    discard buffer.deleteChar(state.cursor)
  elif pos.line > 0:
    # At start of line, join with previous line
    let prevLine = buffer.getLine(pos.line - 1)
    state.cursor.line -= 1
    state.cursor.column = prevLine.charLen
    # Join lines by deleting the newline
    discard buffer.deleteChar(state.cursor)

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
  let pos = state.cursor

  if state.expandTab:
    # Insert spaces instead of tab character
    let tabWidth = max(1, state.tabStop) # Ensure at least 1 space
    let spaces = " ".repeat(tabWidth)

    let insertResult = buffer.insertText(pos, spaces)
    if insertResult.isErr:
      return InsertModeResult(
        kind: imrError, errorMessage: "Failed to insert spaces: " & insertResult.error
      )

    # Move cursor right by number of spaces
    state.cursor.column += tabWidth
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
  ## Uses transaction to group delete+insert as single undo operation
  let selectedWord = handler.completionManager.getSelectedWord()
  if selectedWord.len == 0:
    if not keepPopupOpen:
      handler.completionManager.cancelCompletion()
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  let menu = handler.completionManager.menu

  # Delete the prefix that was typed (use runeLen for multi-byte character support)
  let prefixLen = menu.prefix.runeLen

  # Begin transaction to group delete+insert as single undo operation
  discard buffer.beginTransaction("completion")

  if prefixLen > 0:
    for _ in 0 ..< prefixLen:
      state.cursor.column -= 1
      discard buffer.deleteChar(state.cursor)

  # Insert the selected word
  discard buffer.insertText(state.cursor, selectedWord)
  state.cursor.column += selectedWord.runeLen

  # Commit transaction
  discard buffer.commitTransaction()

  # Close the completion menu (unless keepPopupOpen)
  if not keepPopupOpen:
    handler.completionManager.cancelCompletion()
  else:
    # Update the prefix to the full word (so further typing filters from here)
    handler.completionManager.menu.prefix = selectedWord

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

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

proc shouldTriggerSignatureHelp*(keyCombo: KeyCombo): bool =
  ## Check if the typed character should trigger signature help
  not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char.len == 1 and
    isTriggerChar(keyCombo.char[0])

proc shouldRetriggerSignatureHelp*(keyCombo: KeyCombo): bool =
  ## Check if the typed character should retrigger signature help
  not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char.len == 1 and
    isRetriggerChar(keyCombo.char[0])

proc handleInsertModeKey*(
    handler: InsertModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    keyCombo: KeyCombo,
): InsertModeResult =
  ## Main entry point for handling Insert mode key presses

  # Record key for macro if recording is active
  if state.isRecordingMacro:
    state.recordedKeys.add(keyComboToString(keyCombo))

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
      return handler.commitCompletion(buffer, state, keepPopupOpen = true)

    # Ctrl+P, Up, or Shift+Tab - select previous and replace current word
    if keyCombo.isCtrlP or (keyCombo.isSpecial and keyCombo.special == skUp) or
        (
          keyCombo.isSpecial and keyCombo.special == skTab and
          kmShift in keyCombo.modifiers
        ):
      # First Shift+Tab activates selection mode
      if not handler.completionManager.menu.hasSelection:
        handler.completionManager.menu.hasSelection = true
      else:
        handler.completionManager.selectPrevious()
      # Replace current word with selected one
      return handler.commitCompletion(buffer, state, keepPopupOpen = true)

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

      if hasSelection:
        # Confirm current selection and close popup
        handler.completionManager.cancelCompletion()

      # Insert the new character
      discard handler.handleCharacterInsertion(buffer, state, keyCombo.char)

      # Re-trigger completion with new prefix (start fresh, no selection)
      let line = buffer.getLine(state.cursor.line)
      let newPrefix = extractPrefixBeforeCursor(line, state.cursor.column)
      if newPrefix.len >= AutoTriggerPrefixLength:
        handler.completionManager.triggerCompletion(
          buffer, state.cursor.line, state.cursor.column
        )
        # New completion starts without selection
      else:
        handler.completionManager.cancelCompletion()
      return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+N - trigger completion (when not active)
  if keyCombo.isCtrlN and not completionActive:
    handler.completionManager.triggerCompletion(
      buffer, state.cursor.line, state.cursor.column
    )
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Ctrl+Space - also trigger completion
  if keyCombo.isCtrlSpace and not completionActive:
    handler.completionManager.triggerCompletion(
      buffer, state.cursor.line, state.cursor.column
    )
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

  # Check for mode switch keys (like Escape)
  let binding = handler.keyBindingRegistry.findBinding(EditorMode.Insert, keyCombo)
  if binding.isSome:
    let cmd = binding.get
    case cmd.kind
    of ctModeSwitch:
      return handler.handleModeSwitch(cmd.targetMode)
    of ctMotion:
      # Cancel completion on motion
      handler.completionManager.cancelCompletion()
      return handler.handleMotion(buffer, state, cmd.motion)
    else:
      # Other command types not supported in insert mode
      return InsertModeResult(kind: imrUnhandled)

  # Handle regular character insertion with auto-completion trigger
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    discard handler.handleCharacterInsertion(buffer, state, keyCombo.char)
    # Auto-trigger completion after typing (when prefix is long enough)
    let line = buffer.getLine(state.cursor.line)
    let prefix = extractPrefixBeforeCursor(line, state.cursor.column)
    if prefix.len >= AutoTriggerPrefixLength:
      handler.completionManager.triggerCompletion(
        buffer, state.cursor.line, state.cursor.column
      )
      # Don't auto-insert - wait for Tab to be pressed first
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
