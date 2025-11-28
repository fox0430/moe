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

## Unified handler manager
##
## This module provides a unified interface for all mode-specific handlers,
## maintaining the shared infrastructure while delegating to specialized handlers.

import std/options

import pkg/[results, celina]

import
  ../[
    types, buffer, cursor, modes, motion, keybindings, commandline, commandconfig,
    commandregistry, config, stringbuilder,
  ]
import normal_handler, insert_handler, command_handler, visual_handler, replace_handler

export normal_handler, insert_handler, command_handler, visual_handler, replace_handler

type
  HandlerResultKind* = enum
    hrHandled # Command was handled successfully
    hrQuit # Application should quit
    hrCloseWindow # Close current window
    hrGotoLine # Jump to specific line
    hrVSplit # Vertical split window
    hrHSplit # Horizontal split window
    hrEnew # Create new empty buffer
    hrSetMultiStatusLine # Set multi status line
    hrSetIgnoreCase # Set ignorecase option
    hrSetSmartCase # Set smartcase option
    hrSetIncSearch # Set incsearch option
    hrSetHlSearch # Set hlsearch option
    hrSave # Save file
    hrSaveAndQuit # Save file and quit
    hrBufferNext # Switch to next buffer
    hrBufferPrev # Switch to previous buffer
    hrBufferFirst # Switch to first buffer
    hrBufferLast # Switch to last buffer
    hrBufferDelete # Delete current buffer
    hrStripWhitespace # Remove trailing whitespace
    hrUnhandled # Command was not handled
    hrError # Error occurred

  HandlerManager* = ref object ## Unified manager for all mode handlers
    normalHandler*: NormalModeHandler
    insertHandler*: InsertModeHandler
    commandHandler*: CommandModeHandler
    visualHandler*: VisualModeHandler
    replaceHandler*: ReplaceModeHandler
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandLineParser*: CommandLineParser
    commandConfig*: CommandConfig
    commandRegistry*: CommandRegistry

  HandlerResult* = object ## Unified result type for all handlers
    case kind*: HandlerResultKind
    of hrHandled:
      modeTransition*: Option[EditorMode]
      statusMessage*: string
    of hrQuit:
      shouldQuit*: bool
    of hrCloseWindow:
      forceClose*: bool
    of hrGotoLine:
      lineNumber*: int
    of hrVSplit:
      vsplitFilename*: Option[string]
    of hrHSplit:
      hsplitFilename*: Option[string]
    of hrEnew:
      discard
    of hrSetMultiStatusLine:
      enabled*: bool
    of hrSetIgnoreCase:
      ignorecaseEnabled*: bool
    of hrSetSmartCase:
      smartcaseEnabled*: bool
    of hrSetIncSearch:
      incsearchEnabled*: bool
    of hrSetHlSearch:
      hlsearchEnabled*: bool
    of hrSave:
      saveFilename*: Option[string]
    of hrSaveAndQuit:
      saveAndQuitFilename*: Option[string]
      forceQuitAfterSave*: bool
    of hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast:
      discard
    of hrBufferDelete:
      forceBufferDelete*: bool
    of hrStripWhitespace:
      strippedLineCount*: int
    of hrUnhandled:
      discard
    of hrError:
      errorMessage*: string

proc newHandlerManager*(
    motionController: MotionController,
    keyBindingRegistry: KeyBindingRegistry,
    commandLineParser: CommandLineParser,
    commandConfig: CommandConfig,
    commandRegistry: CommandRegistry,
    clipboardConfig: ClipboardConfig,
): HandlerManager =
  ## Create a new handler manager with all mode handlers

  let normalHandler = newNormalModeHandler(
    motionController, keyBindingRegistry, commandRegistry, clipboardConfig
  )
  let insertHandler =
    newInsertModeHandler(keyBindingRegistry, motionController, commandRegistry)
  let commandHandler =
    newCommandModeHandler(commandLineParser, commandConfig, commandRegistry)
  let visualHandler = newVisualModeHandler(keyBindingRegistry, commandRegistry)
  let replaceHandler =
    newReplaceModeHandler(keyBindingRegistry, motionController, commandRegistry)

  HandlerManager(
    normalHandler: normalHandler,
    insertHandler: insertHandler,
    commandHandler: commandHandler,
    visualHandler: visualHandler,
    replaceHandler: replaceHandler,
    motionController: motionController,
    keyBindingRegistry: keyBindingRegistry,
    commandLineParser: commandLineParser,
    commandConfig: commandConfig,
    commandRegistry: commandRegistry,
  )

proc extractInsertedText(transaction: buffer.BufferTransaction): string =
  ## Extract net inserted text from a transaction
  ## Handles insertions and deletions (backspace during insert mode)
  ## Optimized with StringBuilder for O(n) instead of O(n²) performance
  var sb = stringbuilder.newStringBuilder()
  for change in transaction.changes:
    case change.kind
    of buffer.ckInsertText:
      sb.add(change.insertText)
    of buffer.ckDeleteText:
      # Backspace - remove from end of accumulated text
      sb.removeLast(change.deletedText.len)
    of buffer.ckInsertLine:
      # Line insertion - add the line text
      sb.add(change.insertLineText)
      # Ensure it ends with newline if it doesn't already
      if change.insertLineText.len == 0 or change.insertLineText[^1] != '\n':
        sb.add("\n")
    of buffer.ckDeleteLine:
      # Line deletion during insert mode (rare, but handle it)
      # We can't easily track which line was deleted, so clear accumulated text
      sb.clear()
    of buffer.ckDeleteRange:
      # Range deletion - remove from end of accumulated text
      sb.removeLast(change.deletedRangeText.len)
    of buffer.ckTransaction:
      # Nested transaction - recursively extract text
      let nestedTransaction = buffer.BufferTransaction(
        changes: change.transactionChanges,
        description: change.transactionDescription,
        startSeq: 0,
      )
      sb.add(extractInsertedText(nestedTransaction))
  return sb.toString()

proc handleNormalMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Normal mode input
  let r = manager.normalHandler.handleNormalModeKey(buffer, state, viewport, keyCombo)
  case r.kind
  of nmrHandled:
    # Check if we're entering Insert or Replace mode
    if r.modeTransition.isSome:
      let targetMode = r.modeTransition.get
      if targetMode == EditorMode.Insert:
        # Begin a transaction when entering Insert mode
        let transactionResult = buffer.beginTransaction("Insert mode edit")
        if transactionResult.isErr:
          # This should not happen in normal operation, but handle it gracefully
          return HandlerResult(
            kind: hrError,
            errorMessage: "Failed to begin transaction: " & transactionResult.error,
          )
        # Record insert start position for text tracking
        state.insertModeStartPos = some(state.cursor)
      elif targetMode == EditorMode.Replace:
        # Begin a transaction when entering Replace mode
        let transactionResult = buffer.beginTransaction("Replace mode edit")
        if transactionResult.isErr:
          # This should not happen in normal operation, but handle it gracefully
          return HandlerResult(
            kind: hrError,
            errorMessage: "Failed to begin transaction: " & transactionResult.error,
          )
        # Clear replace history when entering Replace mode
        state.replaceHistory = @[]
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of nmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of nmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)
  of nmrSaveAndQuit:
    # ZZ command - Save and quit
    return HandlerResult(
      kind: hrSaveAndQuit, saveAndQuitFilename: none(string), forceQuitAfterSave: false
    )
  of nmrQuitWithoutSave:
    # ZQ command - Quit without saving (force quit)
    return HandlerResult(kind: hrQuit, shouldQuit: true)

proc handleInsertMode*(
    manager: HandlerManager, buffer: TextBuffer, state: EditorState, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Insert mode input
  let r = manager.insertHandler.handleInsertModeKey(buffer, state, keyCombo)
  case r.kind
  of imrHandled:
    # Check if we're leaving Insert mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Insert:
      # Extract inserted text before committing transaction
      if buffer.currentTransaction.isSome and state.insertModeStartPos.isSome:
        let transaction = buffer.currentTransaction.get
        let insertedText = extractInsertedText(transaction)

        # Record the insert command for repeat (.) if text was actually inserted
        if insertedText.len > 0:
          # Check if we entered Insert mode via substitute command (s/S/cc)
          if state.substituteContext.isSome:
            let subCtx = state.substituteContext.get
            state.lastEditCommand = some(
              types.LastEditCommand(
                kind: types.lecSubstitute,
                substituteText: insertedText,
                substituteCount: subCtx.deleteCount,
                substituteKind: subCtx.kind,
              )
            )
          else:
            # Normal insert (i, a, o, O)
            state.lastEditCommand = some(
              types.LastEditCommand(
                kind: types.lecInsertText,
                insertedText: insertedText,
                insertPosition: state.insertModeStartPos.get,
              )
            )

        # Clear insert position tracking and substitute context
        state.insertModeStartPos = none(BufferPosition)
        state.substituteContext = none(types.SubstituteContext)

      # Commit the transaction when leaving Insert mode
      let transactionResult = buffer.commitTransaction()
      if transactionResult.isErr:
        # This should not happen in normal operation, but handle it gracefully
        return HandlerResult(
          kind: hrError,
          errorMessage: "Failed to commit transaction: " & transactionResult.error,
        )
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of imrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of imrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleCommandMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    commandText: string,
    isSharedBuffer: bool = false,
): HandlerResult =
  ## Handle Command mode input (when Enter is pressed)
  ## isSharedBuffer: true if the buffer is shared across multiple windows
  let r =
    manager.commandHandler.handleCommandModeInput(buffer, commandText, isSharedBuffer)

  case r.kind
  of cmrQuit:
    return HandlerResult(kind: hrQuit, shouldQuit: true)
  of cmrCloseWindow:
    return HandlerResult(kind: hrCloseWindow, forceClose: r.forceClose)
  of cmrModeSwitch:
    return HandlerResult(
      kind: hrHandled, modeTransition: some(r.targetMode), statusMessage: ""
    )
  of cmrMessage:
    return HandlerResult(
      kind: hrHandled, modeTransition: some(EditorMode.Normal), statusMessage: r.message
    )
  of cmrGotoLine:
    return HandlerResult(kind: hrGotoLine, lineNumber: r.lineNumber)
  of cmrVSplit:
    return HandlerResult(kind: hrVSplit, vsplitFilename: r.vsplitFilename)
  of cmrHSplit:
    return HandlerResult(kind: hrHSplit, hsplitFilename: r.hsplitFilename)
  of cmrEnew:
    return HandlerResult(kind: hrEnew)
  of cmrSetMultiStatusLine:
    return HandlerResult(kind: hrSetMultiStatusLine, enabled: r.enabled)
  of cmrSetIgnoreCase:
    return HandlerResult(kind: hrSetIgnoreCase, ignorecaseEnabled: r.ignorecaseEnabled)
  of cmrSetSmartCase:
    return HandlerResult(kind: hrSetSmartCase, smartcaseEnabled: r.smartcaseEnabled)
  of cmrSetIncSearch:
    return HandlerResult(kind: hrSetIncSearch, incsearchEnabled: r.incsearchEnabled)
  of cmrSetHlSearch:
    return HandlerResult(kind: hrSetHlSearch, hlsearchEnabled: r.hlsearchEnabled)
  of cmrSave:
    return HandlerResult(kind: hrSave, saveFilename: r.saveFilename)
  of cmrSaveAndQuit:
    return HandlerResult(
      kind: hrSaveAndQuit,
      saveAndQuitFilename: r.saveAndQuitFilename,
      forceQuitAfterSave: r.forceSaveAndQuit,
    )
  of cmrBufferNext:
    return HandlerResult(kind: hrBufferNext)
  of cmrBufferPrev:
    return HandlerResult(kind: hrBufferPrev)
  of cmrBufferFirst:
    return HandlerResult(kind: hrBufferFirst)
  of cmrBufferLast:
    return HandlerResult(kind: hrBufferLast)
  of cmrBufferDelete:
    return HandlerResult(kind: hrBufferDelete, forceBufferDelete: r.forceBufferDelete)
  of cmrStripWhitespace:
    return
      HandlerResult(kind: hrStripWhitespace, strippedLineCount: r.strippedLineCount)
  of cmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleVisualMode*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): HandlerResult =
  ## Handle Visual mode input
  let r = manager.visualHandler.handleVisualModeKey(buffer, state, viewport, keyCombo)
  case r.kind
  of vmrHandled:
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of vmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of vmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleReplaceMode*(
    manager: HandlerManager, buffer: TextBuffer, state: EditorState, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Replace mode input
  let r = manager.replaceHandler.handleReplaceModeKey(buffer, state, keyCombo)
  case r.kind
  of rmrHandled:
    # Check if we're leaving Replace mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Replace:
      # Commit the transaction when leaving Replace mode
      let transactionResult = buffer.commitTransaction()
      if transactionResult.isErr:
        # This should not happen in normal operation, but handle it gracefully
        return HandlerResult(
          kind: hrError,
          errorMessage: "Failed to commit transaction: " & transactionResult.error,
        )
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of rmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of rmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleEvent*(
    manager: HandlerManager,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    event: Event,
): HandlerResult =
  ## Main entry point for handling events across all modes

  if event.kind != EventKind.Key:
    return HandlerResult(kind: hrUnhandled)

  # Convert event to key combo
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return HandlerResult(kind: hrUnhandled)

  let keyCombo = keyComboOpt.get

  # Delegate to appropriate mode handler
  case state.mode
  of EditorMode.Normal:
    return manager.handleNormalMode(buffer, state, viewport, keyCombo)
  of EditorMode.Insert:
    return manager.handleInsertMode(buffer, state, keyCombo)
  of EditorMode.Command:
    # Command mode is handled differently - through text input
    # This should not be called for command mode key events
    return HandlerResult(kind: hrUnhandled)
  of EditorMode.Search:
    # Search mode is handled differently - through text input
    # This should not be called for search mode key events
    return HandlerResult(kind: hrUnhandled)
  of EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine:
    return manager.handleVisualMode(buffer, state, viewport, keyCombo)
  of EditorMode.Replace:
    return manager.handleReplaceMode(buffer, state, keyCombo)

# Utility functions for HandlerResult
proc wasHandled*(hrResult: HandlerResult): bool =
  ## Check if the event was handled
  hrResult.kind in {
    hrHandled, hrQuit, hrCloseWindow, hrGotoLine, hrVSplit, hrHSplit, hrEnew, hrSave,
    hrSaveAndQuit, hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast,
    hrBufferDelete, hrStripWhitespace,
  }

proc shouldQuit*(hrResult: HandlerResult): bool =
  ## Check if the application should quit
  if hrResult.kind == hrQuit: hrResult.shouldQuit else: false

proc shouldCloseWindow*(hrResult: HandlerResult): bool =
  ## Check if we should close the current window
  hrResult.kind == hrCloseWindow

proc shouldGotoLine*(hrResult: HandlerResult): bool =
  ## Check if we should jump to a line
  hrResult.kind == hrGotoLine

proc shouldVSplit*(hrResult: HandlerResult): bool =
  ## Check if we should create a vertical split
  hrResult.kind == hrVSplit

proc shouldHSplit*(hrResult: HandlerResult): bool =
  ## Check if we should create a horizontal split
  hrResult.kind == hrHSplit

proc shouldEnew*(hrResult: HandlerResult): bool =
  ## Check if we should create a new empty buffer
  hrResult.kind == hrEnew

proc shouldSetMultiStatusLine*(hrResult: HandlerResult): bool =
  ## Check if we should set multi status line mode
  hrResult.kind == hrSetMultiStatusLine

proc shouldSetIgnoreCase*(hrResult: HandlerResult): bool =
  ## Check if we should set ignorecase option
  hrResult.kind == hrSetIgnoreCase

proc shouldSetSmartCase*(hrResult: HandlerResult): bool =
  ## Check if we should set smartcase option
  hrResult.kind == hrSetSmartCase

proc shouldSetIncSearch*(hrResult: HandlerResult): bool =
  ## Check if we should set incsearch option
  hrResult.kind == hrSetIncSearch

proc shouldSetHlSearch*(hrResult: HandlerResult): bool =
  ## Check if we should set hlsearch option
  hrResult.kind == hrSetHlSearch

proc shouldSave*(hrResult: HandlerResult): bool =
  ## Check if we should save the file
  hrResult.kind == hrSave

proc shouldSaveAndQuit*(hrResult: HandlerResult): bool =
  ## Check if we should save the file and quit
  hrResult.kind == hrSaveAndQuit

proc shouldBufferNext*(hrResult: HandlerResult): bool =
  ## Check if we should switch to next buffer
  hrResult.kind == hrBufferNext

proc shouldBufferPrev*(hrResult: HandlerResult): bool =
  ## Check if we should switch to previous buffer
  hrResult.kind == hrBufferPrev

proc shouldBufferFirst*(hrResult: HandlerResult): bool =
  ## Check if we should switch to first buffer
  hrResult.kind == hrBufferFirst

proc shouldBufferLast*(hrResult: HandlerResult): bool =
  ## Check if we should switch to last buffer
  hrResult.kind == hrBufferLast

proc shouldBufferDelete*(hrResult: HandlerResult): bool =
  ## Check if we should delete the current buffer
  hrResult.kind == hrBufferDelete

proc getForceBufferDelete*(hrResult: HandlerResult): bool =
  ## Get force flag for buffer delete
  if hrResult.kind == hrBufferDelete: hrResult.forceBufferDelete else: false

proc shouldStripWhitespace*(hrResult: HandlerResult): bool =
  ## Check if we should strip trailing whitespace
  hrResult.kind == hrStripWhitespace

proc getStrippedLineCount*(hrResult: HandlerResult): int =
  ## Get number of lines that had whitespace stripped
  if hrResult.kind == hrStripWhitespace: hrResult.strippedLineCount else: 0

proc hasError*(hrResult: HandlerResult): bool =
  ## Check if there was an error
  hrResult.kind == hrError

proc getModeTransition*(hrResult: HandlerResult): Option[EditorMode] =
  ## Get mode transition if any
  if hrResult.kind == hrHandled:
    hrResult.modeTransition
  else:
    none(EditorMode)

proc getStatusMessage*(hrResult: HandlerResult): string =
  ## Get status message if any
  case hrResult.kind
  of hrHandled: hrResult.statusMessage
  of hrError: hrResult.errorMessage
  else: ""

proc getLineNumber*(hrResult: HandlerResult): int =
  ## Get line number for goto
  if hrResult.kind == hrGotoLine: hrResult.lineNumber else: 0

proc getVSplitFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for vertical split
  if hrResult.kind == hrVSplit:
    hrResult.vsplitFilename
  else:
    none(string)

proc getHSplitFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for horizontal split
  if hrResult.kind == hrHSplit:
    hrResult.hsplitFilename
  else:
    none(string)

proc getMultiStatusLineEnabled*(hrResult: HandlerResult): bool =
  ## Get multi status line enabled setting
  if hrResult.kind == hrSetMultiStatusLine: hrResult.enabled else: false

proc getIgnoreCaseEnabled*(hrResult: HandlerResult): bool =
  ## Get ignorecase enabled setting
  if hrResult.kind == hrSetIgnoreCase: hrResult.ignorecaseEnabled else: false

proc getSmartCaseEnabled*(hrResult: HandlerResult): bool =
  ## Get smartcase enabled setting
  if hrResult.kind == hrSetSmartCase: hrResult.smartcaseEnabled else: false

proc getIncSearchEnabled*(hrResult: HandlerResult): bool =
  ## Get incsearch enabled setting
  if hrResult.kind == hrSetIncSearch: hrResult.incsearchEnabled else: false

proc getHlSearchEnabled*(hrResult: HandlerResult): bool =
  ## Get hlsearch enabled setting
  if hrResult.kind == hrSetHlSearch: hrResult.hlsearchEnabled else: false

proc getSaveFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for save operation
  if hrResult.kind == hrSave:
    hrResult.saveFilename
  else:
    none(string)

proc getSaveAndQuitFilename*(hrResult: HandlerResult): Option[string] =
  ## Get filename for save and quit operation
  if hrResult.kind == hrSaveAndQuit:
    hrResult.saveAndQuitFilename
  else:
    none(string)

proc getForceQuitAfterSave*(hrResult: HandlerResult): bool =
  ## Get force quit flag for save and quit operation
  if hrResult.kind == hrSaveAndQuit: hrResult.forceQuitAfterSave else: false
