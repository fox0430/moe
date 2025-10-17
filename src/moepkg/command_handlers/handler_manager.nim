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
    types, buffer, modes, motion, keybindings, commandline, commandconfig,
    commandregistry,
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
    hrSetMultiStatusLine # Set multi status line
    hrSave # Save file
    hrSaveAndQuit # Save file and quit
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
    of hrSetMultiStatusLine:
      enabled*: bool
    of hrSave:
      saveFilename*: Option[string]
    of hrSaveAndQuit:
      saveAndQuitFilename*: Option[string]
      forceQuitAfterSave*: bool
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
): HandlerManager =
  ## Create a new handler manager with all mode handlers

  let normalHandler =
    newNormalModeHandler(motionController, keyBindingRegistry, commandRegistry)
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

proc handleInsertMode*(
    manager: HandlerManager, buffer: TextBuffer, state: EditorState, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Insert mode input
  let r = manager.insertHandler.handleInsertModeKey(buffer, state, keyCombo)
  case r.kind
  of imrHandled:
    # Check if we're leaving Insert mode
    if r.modeTransition.isSome and r.modeTransition.get != EditorMode.Insert:
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
    manager: HandlerManager, buffer: TextBuffer, commandText: string
): HandlerResult =
  ## Handle Command mode input (when Enter is pressed)
  let r = manager.commandHandler.handleCommandModeInput(buffer, commandText)

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
  of cmrSetMultiStatusLine:
    return HandlerResult(kind: hrSetMultiStatusLine, enabled: r.enabled)
  of cmrSave:
    return HandlerResult(kind: hrSave, saveFilename: r.saveFilename)
  of cmrSaveAndQuit:
    return HandlerResult(
      kind: hrSaveAndQuit,
      saveAndQuitFilename: r.saveAndQuitFilename,
      forceQuitAfterSave: r.forceSaveAndQuit,
    )
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
  of EditorMode.Visual:
    return manager.handleVisualMode(buffer, state, viewport, keyCombo)
  of EditorMode.Replace:
    return manager.handleReplaceMode(buffer, state, keyCombo)

# Utility functions for HandlerResult
proc wasHandled*(hrResult: HandlerResult): bool =
  ## Check if the event was handled
  hrResult.kind in {
    hrHandled, hrQuit, hrCloseWindow, hrGotoLine, hrVSplit, hrHSplit, hrSave,
    hrSaveAndQuit,
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

proc shouldSetMultiStatusLine*(hrResult: HandlerResult): bool =
  ## Check if we should set multi status line mode
  hrResult.kind == hrSetMultiStatusLine

proc shouldSave*(hrResult: HandlerResult): bool =
  ## Check if we should save the file
  hrResult.kind == hrSave

proc shouldSaveAndQuit*(hrResult: HandlerResult): bool =
  ## Check if we should save the file and quit
  hrResult.kind == hrSaveAndQuit

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
