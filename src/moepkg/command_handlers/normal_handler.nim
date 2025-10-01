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
## This module handles commands specific to Normal mode, including:
## - Movement commands (h, j, k, l, w, b, etc.)
## - Mode switching commands (i, a, o, O, :)
## - Text manipulation commands (d, y, c, etc.)

import std/options

import pkg/results

import ../[types, buffer, modes, motion, keybindings, commandregistry]
import visual_handler

type
  NormalModeResultKind* = enum
    nmrHandled
    nmrUnhandled
    nmrError

  NormalModeHandler* = ref object ## Handler for Normal mode specific commands
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandRegistry*: CommandRegistry

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
): NormalModeHandler =
  ## Create a new Normal mode handler
  NormalModeHandler(
    motionController: motionController,
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
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
  )

  let r = handler.commandRegistry.execute(ctx, commandId, args)
  if r.isOk:
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
  else:
    return NormalModeResult(kind: nmrError, errorMessage: r.error)

proc handleMotionCommand*(
    handler: NormalModeHandler, buffer: TextBuffer, motion: Motion, count: int = 1
): Result[(), string] =
  ## Handle motion commands (h, j, k, l, w, b, etc.)
  let motionCmd = MotionCommand(motion: motion, count: count)
  return handler.motionController.executeMotion(motionCmd)

proc handleModeSwitch*(
    handler: NormalModeHandler,
    targetMode: EditorMode,
    state: EditorState,
    buffer: TextBuffer,
): NormalModeResult =
  ## Handle mode switching commands
  case targetMode
  of EditorMode.Insert:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))
  of EditorMode.Command:
    # Initialize command mode state
    state.commandText = ":"
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Command))
  of EditorMode.Visual:
    # Initialize visual selection at current cursor position
    state.initSelection(buffer)
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Visual))
  of EditorMode.Normal:
    # Already in Normal mode
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

proc handleInsertModeEntry*(
    handler: NormalModeHandler, buffer: TextBuffer, insertType: string
): NormalModeResult =
  ## Handle different types of insert mode entry (i, a, o, O, etc.)
  case insertType
  of "insert":
    # Simple insert at cursor
    discard
  of "append":
    # Move cursor right if not at end of line
    let lineContent = buffer.getLine(buffer.cursor.line)
    if buffer.cursor.column < lineContent.len:
      buffer.cursor.column += 1
  of "append-end":
    # Move to end of line
    let lineContent = buffer.getLine(buffer.cursor.line)
    buffer.cursor.column = lineContent.len
  of "open-below":
    # Insert new line below and position cursor
    let currentLine = buffer.cursor.line
    let lineContent = buffer.getLine(currentLine)
    buffer.cursor.column = lineContent.len
    buffer.insertText(buffer.cursor, "\n")
    buffer.cursor.line = currentLine + 1
    buffer.cursor.column = 0
  of "open-above":
    # Insert new line above and position cursor
    let currentLine = buffer.cursor.line
    buffer.cursor.column = 0
    buffer.insertText(buffer.cursor, "\n")
    buffer.cursor.line = currentLine
    buffer.cursor.column = 0
  else:
    return NormalModeResult(
      kind: nmrError, errorMessage: "Unknown insert type: " & insertType
    )

  return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))

proc handleTextManipulation*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    operation: string,
    target: string = "",
    count: int = 1,
): NormalModeResult =
  ## Handle text manipulation commands (d, y, c, etc.)
  case operation
  of "delete":
    case target
    of "word":
      # TODO: Implement delete word
      return
        NormalModeResult(kind: nmrError, errorMessage: "Delete word not implemented")
    of "line":
      # TODO: Implement delete line
      return
        NormalModeResult(kind: nmrError, errorMessage: "Delete line not implemented")
    else:
      return NormalModeResult(
        kind: nmrError, errorMessage: "Unknown delete target: " & target
      )
  of "yank":
    # TODO: Implement yank operations
    return NormalModeResult(kind: nmrError, errorMessage: "Yank not implemented")
  of "change":
    # TODO: Implement change operations
    return NormalModeResult(kind: nmrError, errorMessage: "Change not implemented")
  else:
    return
      NormalModeResult(kind: nmrError, errorMessage: "Unknown operation: " & operation)

proc handleNormalModeKey*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): NormalModeResult =
  ## Main entry point for handling Normal mode key presses

  # Try to find a binding for this key
  let binding = handler.keyBindingRegistry.findBinding(EditorMode.Normal, keyCombo)

  if binding.isNone:
    return NormalModeResult(kind: nmrUnhandled)

  let cmd = binding.get

  case cmd.kind
  of ctMotion:
    # Map motion to command ID and use CommandRegistry
    let commandId =
      case cmd.motion
      of Motion.Left:
        "motion.left"
      of Motion.Right:
        "motion.right"
      of Motion.Up:
        "motion.up"
      of Motion.Down:
        "motion.down"
      of Motion.Home:
        "motion.home"
      of Motion.End:
        "motion.end"
      of Motion.PageUp:
        "motion.pageup"
      of Motion.PageDown:
        "motion.pagedown"
      else:
        # Fallback to direct motion execution for unsupported motions
        let motionResult = handler.handleMotionCommand(buffer, cmd.motion)
        if motionResult.isOk:
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          return NormalModeResult(kind: nmrError, errorMessage: motionResult.error)

    # Execute through CommandRegistry
    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: handler.motionController,
      keyBindingRegistry: handler.keyBindingRegistry,
    )

    let cmdResult = handler.commandRegistry.execute(ctx, commandId, @[])
    if cmdResult.isOk:
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
  of ctModeSwitch:
    return handler.handleModeSwitch(cmd.targetMode, state, buffer)
  of ctAction:
    # Handle various actions based on command ID
    case cmd.commandId
    of "insert.append":
      return handler.handleInsertModeEntry(buffer, "append")
    of "insert.append.end":
      return handler.handleInsertModeEntry(buffer, "append-end")
    of "insert.line.below":
      return handler.handleInsertModeEntry(buffer, "open-below")
    of "insert.line.above":
      return handler.handleInsertModeEntry(buffer, "open-above")
    of "delete.word":
      return handler.handleTextManipulation(buffer, "delete", "word")
    of "delete.line":
      return handler.handleTextManipulation(buffer, "delete", "line")
    else:
      return NormalModeResult(
        kind: nmrError, errorMessage: "Unknown action: " & cmd.commandId
      )
  else:
    return NormalModeResult(
      kind: nmrError, errorMessage: "Unsupported command type in Normal mode"
    )

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
