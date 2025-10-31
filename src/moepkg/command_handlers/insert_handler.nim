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

import std/[options, unicode, strutils]

import pkg/results

import ../[types, buffer, modes, keybindings, motion, commandregistry, unicode_utils]
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
    handler: InsertModeHandler, buffer: TextBuffer, state: EditorState, text: string
): InsertModeResult =
  ## Handle regular character insertion with auto-close paren support
  let pos = state.cursor

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
  return InsertModeResult(kind: imrHandled, modeTransition: some(targetMode))

proc handleInsertModeKey*(
    handler: InsertModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    keyCombo: KeyCombo,
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
      return handler.handleMotion(buffer, state, cmd.motion)
    else:
      # Other command types not supported in insert mode
      return InsertModeResult(kind: imrUnhandled)

  # Handle regular character insertion
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    return handler.handleCharacterInsertion(buffer, state, keyCombo.char)

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
      return handler.handleMotion(buffer, state, Motion.Left)
    of skRight:
      return handler.handleMotion(buffer, state, Motion.Right)
    of skUp:
      return handler.handleMotion(buffer, state, Motion.Up)
    of skDown:
      return handler.handleMotion(buffer, state, Motion.Down)
    of skHome:
      return handler.handleMotion(buffer, state, Motion.Home)
    of skEnd:
      return handler.handleMotion(buffer, state, Motion.End)
    of skPageUp:
      return handler.handleMotion(buffer, state, Motion.PageUp)
    of skPageDown:
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
