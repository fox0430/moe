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

import std/options

import pkg/results

import ../[types, buffer, modes, keybindings, motion, commandregistry]

type
  InsertModeResultKind* = enum
    imrHandled
    imrUnhandled
    imrError

  InsertModeHandler* = ref object ## Handler for Insert mode specific commands
    keyBindingRegistry*: KeyBindingRegistry
    motionController*: MotionController
    commandRegistry*: CommandRegistry

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
    handler: InsertModeHandler, buffer: TextBuffer, char: char
): InsertModeResult =
  ## Handle regular character insertion
  let pos = buffer.cursor
  buffer.insertText(pos, $char)

  # Move cursor right after insertion
  buffer.cursor.column += 1

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleBackspace*(
    handler: InsertModeHandler, buffer: TextBuffer
): InsertModeResult =
  ## Handle backspace key
  let pos = buffer.cursor

  if pos.column > 0:
    # Move cursor back and delete
    buffer.cursor.column -= 1
    buffer.deleteChar(buffer.cursor)
  elif pos.line > 0:
    # At start of line, join with previous line
    let prevLine = buffer.getLine(pos.line - 1)
    buffer.cursor.line -= 1
    buffer.cursor.column = prevLine.len
    # Join lines by deleting the newline
    buffer.deleteChar(buffer.cursor)

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleDelete*(handler: InsertModeHandler, buffer: TextBuffer): InsertModeResult =
  ## Handle delete key
  buffer.deleteChar(buffer.cursor)

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleNewline*(handler: InsertModeHandler, buffer: TextBuffer): InsertModeResult =
  ## Handle newline insertion
  let pos = buffer.cursor
  buffer.insertText(pos, "\n")

  # Move cursor to start of new line
  buffer.cursor.line += 1
  buffer.cursor.column = 0

  return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))

proc handleMotion*(
    handler: InsertModeHandler, buffer: TextBuffer, motion: Motion
): InsertModeResult =
  ## Handle motion commands in insert mode
  let motionCmd = MotionCommand(motion: motion, count: 1)

  let r = handler.motionController.executeMotion(motionCmd)
  if r.isOk:
    return InsertModeResult(kind: imrHandled, modeTransition: none(EditorMode))
  else:
    return InsertModeResult(kind: imrError, errorMessage: r.error)

proc handleModeSwitch*(
    handler: InsertModeHandler, targetMode: EditorMode
): InsertModeResult =
  ## Handle mode switching from insert mode
  return InsertModeResult(kind: imrHandled, modeTransition: some(targetMode))

proc handleInsertModeKey*(
    handler: InsertModeHandler, buffer: TextBuffer, keyCombo: KeyCombo
): InsertModeResult =
  ## Main entry point for handling Insert mode key presses

  # Check for mode switch keys first (like Escape)
  let binding = handler.keyBindingRegistry.findBinding(EditorMode.Insert, keyCombo)
  if binding.isSome:
    let cmd = binding.get
    case cmd.kind
    of ctModeSwitch:
      return handler.handleModeSwitch(cmd.targetMode)
    of ctMotion:
      return handler.handleMotion(buffer, cmd.motion)
    else:
      # Other command types not supported in insert mode
      return InsertModeResult(kind: imrUnhandled)

  # Handle regular character insertion
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    return handler.handleCharacterInsertion(buffer, keyCombo.char)

  # Handle special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skBackspace:
      return handler.handleBackspace(buffer)
    of skDelete:
      return handler.handleDelete(buffer)
    of skEnter:
      return handler.handleNewline(buffer)
    of skLeft:
      return handler.handleMotion(buffer, Motion.Left)
    of skRight:
      return handler.handleMotion(buffer, Motion.Right)
    of skUp:
      return handler.handleMotion(buffer, Motion.Up)
    of skDown:
      return handler.handleMotion(buffer, Motion.Down)
    of skHome:
      return handler.handleMotion(buffer, Motion.Home)
    of skEnd:
      return handler.handleMotion(buffer, Motion.End)
    of skPageUp:
      return handler.handleMotion(buffer, Motion.PageUp)
    of skPageDown:
      return handler.handleMotion(buffer, Motion.PageDown)
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
