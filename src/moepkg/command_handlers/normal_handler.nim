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

import std/[options, strutils, tables]

import pkg/results

import
  ../[types, buffer, modes, motion, keybindings, commandregistry, config, registers]
import visual_handler, insert_commands

type
  NormalModeResultKind* = enum
    nmrHandled
    nmrUnhandled
    nmrError
    nmrSaveAndQuit
    nmrQuitWithoutSave

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
    of nmrSaveAndQuit:
      discard
    of nmrQuitWithoutSave:
      discard

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
    state.commandCursor = 0 # Cursor starts after the ":"
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
    # Initialize visual selection at current cursor position (character-wise)
    state.initSelection(buffer, vskChar)
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Visual))
  of EditorMode.VisualBlock:
    # Initialize visual selection at current cursor position (block/column)
    state.initSelection(buffer, vskBlock)
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.VisualBlock))
  of EditorMode.VisualLine:
    # Initialize visual selection at current cursor position (line-wise)
    state.initSelection(buffer, vskLine)
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.VisualLine))
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
  of "insert-first-non-blank":
    # Move to first non-blank character and insert
    let motionCmd = MotionCommand(motion: Motion.FirstNonBlank, count: 1)
    let r = handler.motionController.executeMotion(motionCmd, state.cursor)
    if r.isErr:
      return NormalModeResult(kind: nmrError, errorMessage: r.error)
    state.cursor = r.value
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

proc keyComboToString(keyCombo: KeyCombo): string =
  ## Convert a KeyCombo to a string for macro recording
  if keyCombo.isSpecial:
    case keyCombo.special
    of skEnter:
      return "<Enter>"
    of skTab:
      return "<Tab>"
    of skBackspace:
      return "<Backspace>"
    of skDelete:
      return "<Delete>"
    of skEscape:
      return "<Escape>"
    of skUp:
      return "<Up>"
    of skDown:
      return "<Down>"
    of skLeft:
      return "<Left>"
    of skRight:
      return "<Right>"
    of skPageUp:
      return "<PageUp>"
    of skPageDown:
      return "<PageDown>"
    of skHome:
      return "<Home>"
    of skEnd:
      return "<End>"
    of skFunction:
      return "<F" & $keyCombo.fnNum & ">"
    of skNone:
      return ""
  else:
    return keyCombo.char

proc stringToKeyCombo(s: string): Option[KeyCombo] =
  ## Convert a string back to a KeyCombo for macro playback
  if s.len == 0:
    return none(KeyCombo)

  if s.startsWith("<") and s.endsWith(">"):
    # Special key
    let key = s[1 ..< s.len - 1]
    case key
    of "Enter":
      return some(KeyCombo(isSpecial: true, special: skEnter, fnNum: 0))
    of "Tab":
      return some(KeyCombo(isSpecial: true, special: skTab, fnNum: 0))
    of "Backspace":
      return some(KeyCombo(isSpecial: true, special: skBackspace, fnNum: 0))
    of "Delete":
      return some(KeyCombo(isSpecial: true, special: skDelete, fnNum: 0))
    of "Escape":
      return some(KeyCombo(isSpecial: true, special: skEscape, fnNum: 0))
    of "Up":
      return some(KeyCombo(isSpecial: true, special: skUp, fnNum: 0))
    of "Down":
      return some(KeyCombo(isSpecial: true, special: skDown, fnNum: 0))
    of "Left":
      return some(KeyCombo(isSpecial: true, special: skLeft, fnNum: 0))
    of "Right":
      return some(KeyCombo(isSpecial: true, special: skRight, fnNum: 0))
    of "PageUp":
      return some(KeyCombo(isSpecial: true, special: skPageUp, fnNum: 0))
    of "PageDown":
      return some(KeyCombo(isSpecial: true, special: skPageDown, fnNum: 0))
    of "Home":
      return some(KeyCombo(isSpecial: true, special: skHome, fnNum: 0))
    of "End":
      return some(KeyCombo(isSpecial: true, special: skEnd, fnNum: 0))
    else:
      # Check for function keys
      if key.startsWith("F"):
        try:
          let num = parseInt(key[1 ..^ 1])
          return some(KeyCombo(isSpecial: true, special: skFunction, fnNum: num))
        except ValueError:
          return none(KeyCombo)
      else:
        return none(KeyCombo)
  else:
    # Regular character
    return some(KeyCombo(isSpecial: false, char: s, modifiers: {}))

# Forward declaration for recursive call in playbackMacro
proc handleNormalModeKey*(
  handler: NormalModeHandler,
  buffer: TextBuffer,
  state: EditorState,
  viewport: ViewPort,
  keyCombo: KeyCombo,
): NormalModeResult

proc playbackMacro(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keys: seq[string],
): NormalModeResult =
  ## Play back a recorded macro
  # Clear any pending key sequences before starting playback
  handler.keyBindingRegistry.clearSequence()

  for keyStr in keys:
    let keyComboOpt = stringToKeyCombo(keyStr)
    if keyComboOpt.isNone:
      return NormalModeResult(
        kind: nmrError, errorMessage: "Invalid key in macro: " & keyStr
      )

    let keyCombo = keyComboOpt.get
    # Recursively call handleNormalModeKey, but skip macro recording
    # We need to temporarily disable recording to avoid recording during playback
    let wasRecording = state.isRecordingMacro
    let wasWaitingForRegister = state.waitingForMacroRegister
    state.isRecordingMacro = false
    state.waitingForMacroRegister = false

    let res = handler.handleNormalModeKey(buffer, state, viewport, keyCombo)

    # Restore recording state
    state.isRecordingMacro = wasRecording
    state.waitingForMacroRegister = wasWaitingForRegister

    # If there was an error, stop playback
    if res.kind == nmrError:
      return res

    # If mode changed (e.g., entered insert mode), we should stop playback
    # This prevents issues with mode-specific commands
    if res.modeTransition.isSome:
      # Allow the mode transition but stop further playback
      return res

  # Clear any pending sequences after playback
  handler.keyBindingRegistry.clearSequence()
  return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

proc handleNormalModeKey*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): NormalModeResult =
  ## Main entry point for handling Normal mode key presses

  # Check if we're waiting for a macro register name
  if state.waitingForMacroRegister:
    # Expecting a register name (a-z or @)
    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      let registerChar =
        if keyCombo.char.len > 0:
          keyCombo.char[0]
        else:
          '\0'

      if state.macroCommandType == "record":
        # Start recording to the specified register
        if registerChar >= 'a' and registerChar <= 'z':
          state.isRecordingMacro = true
          state.macroRegister = registerChar
          state.recordedKeys = @[]
          state.statusMessage = "recording @" & $registerChar
          state.waitingForMacroRegister = false
          state.macroCommandType = ""
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          state.statusMessage = "Invalid register (use a-z)"
          state.waitingForMacroRegister = false
          state.macroCommandType = ""
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      elif state.macroCommandType == "playback":
        # Play back the macro from the specified register
        if registerChar == '@':
          # @@ - repeat last macro
          if state.lastMacroRegister.isSome:
            let reg = state.lastMacroRegister.get
            if state.macroRegisters.hasKey(reg):
              state.waitingForMacroRegister = false
              state.macroCommandType = ""
              let keys = state.macroRegisters[reg]
              return handler.playbackMacro(buffer, state, viewport, keys)
            else:
              state.statusMessage = "Register @" & $reg & " is empty"
              state.waitingForMacroRegister = false
              state.macroCommandType = ""
              return
                NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
          else:
            state.statusMessage = "No previous macro"
            state.waitingForMacroRegister = false
            state.macroCommandType = ""
            return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        elif registerChar >= 'a' and registerChar <= 'z':
          if state.macroRegisters.hasKey(registerChar):
            state.lastMacroRegister = some(registerChar)
            state.waitingForMacroRegister = false
            state.macroCommandType = ""
            let keys = state.macroRegisters[registerChar]
            return handler.playbackMacro(buffer, state, viewport, keys)
          else:
            state.statusMessage = "Register @" & $registerChar & " is empty"
            state.waitingForMacroRegister = false
            state.macroCommandType = ""
            return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          state.statusMessage = "Invalid register (use a-z or @)"
          state.waitingForMacroRegister = false
          state.macroCommandType = ""
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Cancel on any non-char key
      state.statusMessage = ""
      state.waitingForMacroRegister = false
      state.macroCommandType = ""
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  # Handle macro recording - check if we're in recording mode
  # and this is not the 'q' key that would stop recording
  if state.isRecordingMacro:
    # Check if this is 'q' to stop recording
    if not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char == "q":
      # Stop recording
      state.macroRegisters[state.macroRegister] = state.recordedKeys
      state.isRecordingMacro = false
      state.recordedKeys = @[]
      state.statusMessage = ""
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Record this key
      state.recordedKeys.add(keyComboToString(keyCombo))
      # Continue processing the key normally

  # Check for macro commands before processing through key bindings
  # Handle 'q' for macro recording start
  if not state.isRecordingMacro and not keyCombo.isSpecial and keyCombo.modifiers == {} and
      keyCombo.char == "q":
    # Wait for the next key (register name)
    state.waitingForMacroRegister = true
    state.macroCommandType = "record"
    state.statusMessage = "recording @"
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  # Handle '@' for macro playback - only when NOT recording
  if not state.isRecordingMacro and not keyCombo.isSpecial and keyCombo.modifiers == {} and
      keyCombo.char == "@":
    # Wait for the next key (register name)
    state.waitingForMacroRegister = true
    state.macroCommandType = "playback"
    state.statusMessage = "@"
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  # Handle '"' for register selection
  # When pendingRegister is '\0' (null), we're waiting for register name
  # When pendingRegister is a valid register name, we proceed with the command
  if state.pendingRegister.isSome and state.pendingRegister.get == '\0':
    # We're waiting for a register name after "
    if not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char.len > 0:
      let registerChar = keyCombo.char[0]
      if isValidRegisterName(registerChar):
        state.pendingRegister = some(registerChar)
        state.statusMessage = "\"" & $registerChar
        # Now wait for the actual command (y, d, p, etc.)
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        # Invalid register name, cancel
        state.pendingRegister = none(char)
        state.statusMessage = ""
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Cancel on special key
      state.pendingRegister = none(char)
      state.statusMessage = ""
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  # Handle '"' key to start register selection
  if not keyCombo.isSpecial and keyCombo.modifiers == {} and keyCombo.char == "\"":
    state.pendingRegister = some('\0') # Placeholder - next key will be actual register
    state.statusMessage = "\""
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

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
    of "insert.first.non.blank":
      return handler.handleInsertModeEntry(buffer, state, "insert-first-non-blank")
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
    of "file.save.and.quit":
      # ZZ command - Save and quit
      return NormalModeResult(kind: nmrSaveAndQuit)
    of "file.quit.force":
      # ZQ command - Quit without saving
      return NormalModeResult(kind: nmrQuitWithoutSave)
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
