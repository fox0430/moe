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
import normal_handler, insert_handler, command_handler

export normal_handler, insert_handler, command_handler

type
  HandlerResultKind* = enum
    hrHandled # Command was handled successfully
    hrQuit # Application should quit
    hrGotoLine # Jump to specific line
    hrUnhandled # Command was not handled
    hrError # Error occurred

  HandlerManager* = ref object ## Unified manager for all mode handlers
    normalHandler*: NormalModeHandler
    insertHandler*: InsertModeHandler
    commandHandler*: CommandModeHandler
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
    of hrGotoLine:
      lineNumber*: int
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

  HandlerManager(
    normalHandler: normalHandler,
    insertHandler: insertHandler,
    commandHandler: commandHandler,
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
    return HandlerResult(
      kind: hrHandled, modeTransition: r.modeTransition, statusMessage: ""
    )
  of nmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of nmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)

proc handleInsertMode*(
    manager: HandlerManager, buffer: TextBuffer, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Insert mode input
  let r = manager.insertHandler.handleInsertModeKey(buffer, keyCombo)
  case r.kind
  of imrHandled:
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
  of cmrError:
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
    return manager.handleInsertMode(buffer, keyCombo)
  of EditorMode.Command:
    # Command mode is handled differently - through text input
    # This should not be called for command mode key events
    return HandlerResult(kind: hrUnhandled)

# Utility functions for HandlerResult
proc wasHandled*(hrResult: HandlerResult): bool =
  ## Check if the event was handled
  hrResult.kind in {hrHandled, hrQuit, hrGotoLine}

proc shouldQuit*(hrResult: HandlerResult): bool =
  ## Check if the application should quit
  if hrResult.kind == hrQuit: hrResult.shouldQuit else: false

proc shouldGotoLine*(hrResult: HandlerResult): bool =
  ## Check if we should jump to a line
  hrResult.kind == hrGotoLine

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
