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

## Replace mode handler

import std/[options, unicode]

import pkg/results

import ../[types, modes, key_bindings, motion, command_registry, key_router]
import ../buffer/[core, edit]
import ../types/editor_types
import handler_types
export handler_types

type
  ReplaceModeResultKind* = enum
    rmrHandled
    rmrUnhandled
    rmrError

  ReplaceModeResult* = object ## Result of replace mode command execution
    case kind*: ReplaceModeResultKind
    of rmrHandled:
      modeTransition*: Option[EditorMode]
    of rmrUnhandled:
      discard
    of rmrError:
      errorMessage*: string

proc newReplaceModeHandler*(
    keyBindingRegistry: KeyBindingRegistry,
    motionController: MotionController,
    commandRegistry: CommandRegistry,
): ReplaceModeHandler =
  ## Create a new Replace mode handler
  ReplaceModeHandler(
    keyBindingRegistry: keyBindingRegistry,
    motionController: motionController,
    commandRegistry: commandRegistry,
  )

proc handleCharacterReplacement*(
    handler: ReplaceModeHandler, buffer: TextBuffer, state: EditorState, text: string
): ReplaceModeResult =
  ## Handle character replacement in Replace mode
  ##
  ## If cursor is at end of line, insert character (like Insert mode).
  ## Otherwise, replace the character at cursor position.
  let pos = state.cursor
  let lineContent = buffer.getLine(pos.line)

  if pos.column >= lineContent.charLen:
    # At end of line, insert character (no original character to save)
    let insertResult = buffer.insertText(pos, text)
    if insertResult.isErr:
      return ReplaceModeResult(
        kind: rmrError, errorMessage: "Failed to insert text: " & insertResult.error
      )
    # Save empty string as original character for consistency
    state.editState.replaceHistory.add(ReplaceHistoryEntry(pos: pos, originalChar: ""))
  else:
    # Replace character at cursor
    # Save original character for undo with backspace
    let originalChar = $lineContent.runeAtPos(pos.column)

    # Delete existing character
    let deleteResult = buffer.deleteChar(pos)
    if deleteResult.isErr:
      return ReplaceModeResult(
        kind: rmrError,
        errorMessage: "Failed to delete character: " & deleteResult.error,
      )

    # Insert new character
    let insertResult = buffer.insertText(pos, text)
    if insertResult.isErr:
      return ReplaceModeResult(
        kind: rmrError, errorMessage: "Failed to insert text: " & insertResult.error
      )

    # Only add to history if operations succeeded
    state.editState.replaceHistory.add(
      ReplaceHistoryEntry(pos: pos, originalChar: originalChar)
    )

  # Move cursor right after replacement/insertion
  state.cursor.column += text.runeLen

  return ReplaceModeResult(kind: rmrHandled, modeTransition: none(EditorMode))

proc handleBackspace*(
    handler: ReplaceModeHandler, buffer: TextBuffer, state: EditorState
): ReplaceModeResult =
  ## Handle backspace in Replace mode
  ##
  ## In Vim's Replace mode, backspace restores the original character and moves cursor left.
  ## This is achieved by using the replace history.

  # Check if there's any replace history to undo
  if state.editState.replaceHistory.len == 0:
    # No history, just move cursor back (beginning of replace session)
    if state.cursor.column > 0:
      state.cursor.column -= 1
    elif state.cursor.line > 0:
      let prevLine = buffer.getLine(state.cursor.line - 1)
      state.cursor.line -= 1
      state.cursor.column = prevLine.charLen
    return ReplaceModeResult(kind: rmrHandled, modeTransition: none(EditorMode))

  # Pop last replace entry
  let lastEntry = state.editState.replaceHistory.pop()

  # Move cursor to the position where the character was replaced
  state.cursor = lastEntry.pos

  # Restore original character if there was one
  if lastEntry.originalChar.len > 0:
    # Delete the replacement character and restore original
    let deleteResult = buffer.deleteChar(state.cursor)
    if deleteResult.isErr:
      # Restore history entry on error
      state.editState.replaceHistory.add(lastEntry)
      return ReplaceModeResult(
        kind: rmrError,
        errorMessage: "Failed to delete character: " & deleteResult.error,
      )

    let insertResult = buffer.insertText(state.cursor, lastEntry.originalChar)
    if insertResult.isErr:
      # Restore history entry on error
      state.editState.replaceHistory.add(lastEntry)
      return ReplaceModeResult(
        kind: rmrError,
        errorMessage: "Failed to restore character: " & insertResult.error,
      )
  else:
    # Was an insertion at end of line, just delete it
    let deleteResult = buffer.deleteChar(state.cursor)
    if deleteResult.isErr:
      # Restore history entry on error
      state.editState.replaceHistory.add(lastEntry)
      return ReplaceModeResult(
        kind: rmrError,
        errorMessage: "Failed to delete character: " & deleteResult.error,
      )

  return ReplaceModeResult(kind: rmrHandled, modeTransition: none(EditorMode))

proc handleNewline*(
    handler: ReplaceModeHandler, buffer: TextBuffer, state: EditorState
): ReplaceModeResult =
  ## Handle newline in Replace mode
  ##
  ## Insert newline and move to next line
  let pos = state.cursor
  let insertResult = buffer.insertText(pos, "\n")
  if insertResult.isErr:
    return ReplaceModeResult(
      kind: rmrError, errorMessage: "Failed to insert newline: " & insertResult.error
    )

  # Move cursor to start of new line
  state.cursor.line += 1
  state.cursor.column = 0

  return ReplaceModeResult(kind: rmrHandled, modeTransition: none(EditorMode))

proc handleMotion*(
    handler: ReplaceModeHandler, buffer: TextBuffer, state: EditorState, motion: Motion
): ReplaceModeResult =
  ## Handle motion commands in replace mode
  let motionCmd = MotionCommand(motion: motion, count: 1)

  let r = handler.motionController.executeMotion(motionCmd, state.cursor)
  if r.isErr:
    return ReplaceModeResult(kind: rmrError, errorMessage: r.error)
  state.cursor = r.value
  return ReplaceModeResult(kind: rmrHandled, modeTransition: none(EditorMode))

proc handleModeSwitch*(
    handler: ReplaceModeHandler, targetMode: EditorMode
): ReplaceModeResult =
  ## Handle mode switching from replace mode
  return ReplaceModeResult(kind: rmrHandled, modeTransition: some(targetMode))

proc handleReplaceModeKey*(
    handler: ReplaceModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    keyCombo: KeyCombo,
): ReplaceModeResult =
  ## Main entry point for handling Replace mode key presses.
  ## Macro recording is captured centrally in `handler.handleKeyCombo`.

  # Resolve through the shared built-in decode entry (`resolveBuiltin`), the
  # same path Normal/Visual/Insert use. Replace has no built-in sequences, but a
  # user `:rmap` may bind a multi-key command, so the FSM-backed entry (not a
  # plain single-key lookup) is still required. Only `rrCommand` carries a
  # binding to dispatch; every other result falls through to character replace,
  # matching the previous `findBinding` `none` path exactly.
  let route = handler.keyBindingRegistry.resolveBuiltin(EditorMode.Replace, keyCombo)
  if route.kind == rrCommand:
    let cmd = route.command
    case cmd.kind
    of ctModeSwitch:
      return handler.handleModeSwitch(cmd.targetMode)
    of ctOverlaySwitch:
      # Overlay switches not supported in replace mode
      return ReplaceModeResult(kind: rmrUnhandled)
    of ctMotion:
      return handler.handleMotion(buffer, state, cmd.motion)
    else:
      # Other command types not supported in replace mode
      return ReplaceModeResult(kind: rmrUnhandled)

  # Handle regular character replacement
  if not keyCombo.isSpecial and keyCombo.modifiers == {}:
    return handler.handleCharacterReplacement(buffer, state, keyCombo.char)

  # Handle special keys
  if keyCombo.isSpecial:
    case keyCombo.special
    of skBackspace:
      return handler.handleBackspace(buffer, state)
    of skEnter:
      return handler.handleNewline(buffer, state)
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
      return ReplaceModeResult(kind: rmrUnhandled)

  # Unhandled key combination
  return ReplaceModeResult(kind: rmrUnhandled)

proc isHandled*(rmResult: ReplaceModeResult): bool =
  ## Check if the command was handled
  rmResult.kind == rmrHandled

proc hasError*(rmResult: ReplaceModeResult): bool =
  ## Check if there was an error
  rmResult.kind == rmrError

proc getModeTransition*(rmResult: ReplaceModeResult): Option[EditorMode] =
  ## Get the mode transition if any
  if rmResult.kind == rmrHandled:
    rmResult.modeTransition
  else:
    none(EditorMode)
