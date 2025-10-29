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

## Normal mode command handler
##
## This module handles commands specific to Normal mode.

import std/options

import pkg/results

import ../[types, buffer, modes, motion, keybindings, commandregistry, config]
import visual_handler, insert_commands

type
  NormalModeResultKind* = enum
    nmrHandled
    nmrUnhandled
    nmrError

  NormalModeHandler* = ref object ## Handler for Normal mode specific commands
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandRegistry*: CommandRegistry
    clipboardConfig*: ClipboardConfig

  NormalModeResult* = object ## Result of normal mode command execution
    case kind*: NormalModeResultKind
    of nmrHandled:
      modeTransition*: Option[EditorMode]
    of nmrUnhandled:
      discard
    of nmrError:
      errorMessage*: string

proc newNormalModeHandler*(
    motionController: MotionController,
    keyBindingRegistry: KeyBindingRegistry,
    commandRegistry: CommandRegistry,
    clipboardConfig: ClipboardConfig = ClipboardConfig(enable: false, tool: ctXclip),
): NormalModeHandler =
  ## Create a new Normal mode handler
  NormalModeHandler(
    motionController: motionController,
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    clipboardConfig: clipboardConfig,
  )

proc executeCommand*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    commandId: string,
    args: seq[string] = @[],
): NormalModeResult =
  ## Execute a command using the CommandRegistry
  let ctx = CommandContext(
    buffer: buffer,
    state: state,
    viewport: viewport,
    motionController: handler.motionController,
    keyBindingRegistry: handler.keyBindingRegistry,
    clipboardConfig: handler.clipboardConfig,
  )

  let r = handler.commandRegistry.execute(ctx, commandId, args)
  if r.isOk:
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
  else:
    return NormalModeResult(kind: nmrError, errorMessage: r.error)

proc handleMotionCommand*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    motion: Motion,
    count: int = 1,
): Result[(), string] =
  ## Handle motion commands (h, j, k, l, w, b, etc.)
  let motionCmd = MotionCommand(motion: motion, count: count)
  let r = handler.motionController.executeMotion(motionCmd, state.cursor)
  if r.isErr:
    return err(r.error)
  state.cursor = r.value
  return Result[(), string].ok ()

proc handleModeSwitch*(
    handler: NormalModeHandler,
    targetMode: EditorMode,
    state: EditorState,
    buffer: TextBuffer,
    commandName: string = "",
): NormalModeResult =
  ## Handle mode switching commands
  case targetMode
  of EditorMode.Insert:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))
  of EditorMode.Command:
    # Initialize command mode state
    state.commandText = ":"
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Command))
  of EditorMode.Search:
    # Initialize search mode state
    state.searchText = ""
    # Save current cursor position for incsearch cancellation
    state.searchStartPos = state.cursor
    # Set search direction based on command name
    if commandName == "switch-to-search-backward":
      state.searchDirection = Backward
    else:
      state.searchDirection = Forward
    # Reset history navigation index
    state.searchHistoryIndex = -1
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Search))
  of EditorMode.Visual:
    # Initialize visual selection at current cursor position
    state.initSelection(buffer)
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Visual))
  of EditorMode.Replace:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Replace))
  of EditorMode.Normal:
    # Already in Normal mode
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

proc handleInsertModeEntry*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    insertType: string,
): NormalModeResult =
  ## Handle different types of insert mode entry (i, a, o, O, etc.)
  case insertType
  of "insert":
    # Simple insert at cursor
    discard
  of "append":
    # Move cursor right if not at end of line
    let lineContent = buffer.getLine(state.cursor.line)
    # Use charLen (character count) not len (byte count) for multibyte character support
    if state.cursor.column < lineContent.charLen:
      state.cursor.column += 1
  of "append-end":
    # Move to end of line
    let lineContent = buffer.getLine(state.cursor.line)
    state.cursor.column = lineContent.charLen
  of "open-below":
    # Insert new line below and position cursor with auto-indent
    insertLineBelow(buffer, state)
    # Note: insertLineBelow already switches to Insert mode, but we override below
  of "open-above":
    # Insert new line above and position cursor with auto-indent
    insertLineAbove(buffer, state)
    # Note: insertLineAbove already switches to Insert mode, but we override below
  else:
    return NormalModeResult(
      kind: nmrError, errorMessage: "Unknown insert type: " & insertType
    )

  return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))

# All text manipulation (delete, yank, change) is now handled by the
# operator+motion system in commandregistry.nim

proc handleNormalModeKey*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): NormalModeResult =
  ## Main entry point for handling Normal mode key presses

  # Process the key (handles numeric prefixes, sequences, etc.)
  let cmdOption = handler.keyBindingRegistry.processKey(EditorMode.Normal, keyCombo)

  if cmdOption.isNone:
    # Key was consumed (e.g., building numeric prefix or sequence)
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  let cmd = cmdOption.get

  case cmd.kind
  of ctMotion:
    # Execute all motions through CommandRegistry to handle numeric prefixes
    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: handler.motionController,
      keyBindingRegistry: handler.keyBindingRegistry,
      clipboardConfig: handler.clipboardConfig,
    )

    # Execute the motion command directly through CommandRegistry
    let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)
    if cmdResult.isOk:
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
  of ctModeSwitch:
    return handler.handleModeSwitch(cmd.targetMode, state, buffer, cmd.name)
  of ctAction:
    # Handle various actions based on command ID
    case cmd.commandId
    of "insert.append":
      return handler.handleInsertModeEntry(buffer, state, "append")
    of "insert.append.end":
      return handler.handleInsertModeEntry(buffer, state, "append-end")
    of "insert.line.below":
      return handler.handleInsertModeEntry(buffer, state, "open-below")
    of "insert.line.above":
      return handler.handleInsertModeEntry(buffer, state, "open-above")
    # dd, yy, cc are handled by operator doubling in commandregistry
    of "edit.undo":
      let r = buffer.undo()
      if r.isOk:
        state.cursor = r.value
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        return NormalModeResult(kind: nmrError, errorMessage: r.error)
    of "edit.redo":
      let r = buffer.redo()
      if r.isOk:
        state.cursor = r.value
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        return NormalModeResult(kind: nmrError, errorMessage: r.error)
    else:
      # Try to execute using command registry for other actions
      let ctx = CommandContext(
        buffer: buffer,
        state: state,
        viewport: viewport,
        motionController: handler.motionController,
        keyBindingRegistry: handler.keyBindingRegistry,
        clipboardConfig: handler.clipboardConfig,
      )
      let cmdResult = handler.commandRegistry.execute(ctx, cmd.commandId, cmd.args)
      if cmdResult.isOk:
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
  of ctCustom, ctTextObject, ctOperator, ctOperatorPending:
    # Execute custom commands and operators through command registry
    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: handler.motionController,
      keyBindingRegistry: handler.keyBindingRegistry,
      clipboardConfig: handler.clipboardConfig,
    )
    # Use executeCommand to handle numeric prefixes properly
    let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)
    if cmdResult.isOk:
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)

proc isHandled*(nmResult: NormalModeResult): bool =
  ## Check if the command was handled
  nmResult.kind == nmrHandled

proc hasError*(nmResult: NormalModeResult): bool =
  ## Check if there was an error
  nmResult.kind == nmrError

proc getModeTransition*(nmResult: NormalModeResult): Option[EditorMode] =
  ## Get the mode transition if any
  if nmResult.kind == nmrHandled:
    nmResult.modeTransition
  else:
    none(EditorMode)
