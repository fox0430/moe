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

## Normal mode command handler
##
## This module handles commands specific to Normal mode.

import std/[options, tables]

import pkg/results

import
  ../[
    types, buffer, modes, motion, key_bindings, command_registry, config, registers,
    render_utils,
  ]
import visual_handler, insert_commands

type
  NormalModeResultKind* = enum
    nmrHandled
    nmrUnhandled
    nmrError
    nmrSave
    nmrSaveAndQuit
    nmrQuitWithoutSave
    nmrCloseWindow # Signal to handler_manager to close current window (Ctrl-W c)
    nmrPlaybackMacro # Signal to handler_manager to playback a macro
    nmrLspGotoDefinition # Signal to handler_manager to execute LSP goto definition
    nmrLspGotoDeclaration # Signal to handler_manager to execute LSP goto declaration
    nmrLspFindReferences # Signal to handler_manager to execute LSP find references
    nmrLspCodeLensExecute # Signal to handler_manager to execute CodeLens on current line
    nmrLspCallHierarchyIncoming # Signal to handler_manager to show incoming calls
    nmrLspCallHierarchyOutgoing # Signal to handler_manager to show outgoing calls
    nmrLspTypeDefinition # Signal to handler_manager to execute LSP goto type definition
    nmrLspImplementation # Signal to handler_manager to execute LSP goto implementation
    nmrLspHover # Signal to handler_manager to execute LSP hover
    nmrLspRename # Signal to handler_manager to execute LSP rename
    nmrLspSelectionRange # Signal to handler_manager to execute LSP selection range
    nmrLspDocumentLink # Signal to handler_manager to execute LSP document link
    nmrJumpToBuffer # Signal to handler_manager to jump to buffer and position
    nmrBufferNext # Signal to handler_manager to switch to next buffer
    nmrBufferPrev # Signal to handler_manager to switch to previous buffer
    nmrNewFile # Signal to handler_manager to create new empty buffer
    nmrEnterFiler # Signal to handler_manager to enter filer mode
    nmrBufferDelete # Signal to handler_manager to delete current buffer
    nmrNextWindow # Signal to handler_manager to switch to next window
    nmrPrevWindow # Signal to handler_manager to switch to previous window
    nmrIncreaseWindowHeight # Signal to handler_manager to increase window height
    nmrDecreaseWindowHeight # Signal to handler_manager to decrease window height
    nmrIncreaseWindowWidth # Signal to handler_manager to increase window width
    nmrDecreaseWindowWidth # Signal to handler_manager to decrease window width
    nmrEqualizeWindows # Signal to handler_manager to equalize all windows

  NormalModeHandler* = ref object ## Handler for Normal mode specific commands
    motionController*: MotionController
    keyBindingRegistry*: KeyBindingRegistry
    commandRegistry*: CommandRegistry
    clipboardConfig*: ClipboardConfig
    smoothScrollConfig*: SmoothScrollConfig
    notificationConfig*: NotificationConfig

  NormalModeResult* = object ## Result of normal mode command execution
    case kind*: NormalModeResultKind
    of nmrHandled:
      modeTransition*: Option[EditorMode]
      overlayTransition*: Option[OverlayKind]
    of nmrUnhandled:
      discard
    of nmrError:
      errorMessage*: string
    of nmrSave:
      discard
    of nmrSaveAndQuit:
      discard
    of nmrQuitWithoutSave:
      discard
    of nmrCloseWindow:
      discard
    of nmrPlaybackMacro:
      macroKeys*: seq[string] # Keys to playback
      macroCount*: int # Number of times to playback (default 1)
    of nmrLspGotoDefinition:
      discard
    of nmrLspGotoDeclaration:
      discard
    of nmrLspFindReferences:
      discard
    of nmrLspCodeLensExecute:
      discard
    of nmrLspCallHierarchyIncoming:
      discard
    of nmrLspCallHierarchyOutgoing:
      discard
    of nmrLspTypeDefinition:
      discard
    of nmrLspImplementation:
      discard
    of nmrLspHover:
      discard
    of nmrLspRename:
      nmrLspNewName*: string
    of nmrLspSelectionRange:
      discard
    of nmrLspDocumentLink:
      discard
    of nmrJumpToBuffer:
      nmrJumpBufferIndex*: int # Target buffer index
      nmrJumpLine*: int # Target line number
      nmrJumpColumn*: int # Target column number
    of nmrBufferNext:
      discard
    of nmrBufferPrev:
      discard
    of nmrBufferDelete:
      discard
    of nmrNewFile:
      discard
    of nmrEnterFiler:
      discard
    of nmrNextWindow:
      discard
    of nmrPrevWindow:
      discard
    of nmrIncreaseWindowHeight, nmrDecreaseWindowHeight, nmrIncreaseWindowWidth,
        nmrDecreaseWindowWidth, nmrEqualizeWindows:
      discard

proc updateCursorToJumpPosition(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    pos: JumpPosition,
): NormalModeResult =
  ## Update cursor position to a jump list position in the same buffer
  ## Returns error result if buffer is empty, or handled result on success
  if buffer.len == 0:
    return
      NormalModeResult(kind: nmrError, errorMessage: "Cannot jump: buffer is empty")

  state.cursor.line = min(pos.line, buffer.len - 1)
  let line = buffer.getLine(state.cursor.line)
  let lineCharLen = line.charLen
  state.cursor.column =
    if lineCharLen == 0:
      0
    else:
      min(pos.column, max(0, lineCharLen - 1))

  let
    cursorPos = CursorPosition(x: state.cursor.column, y: state.cursor.line)
    lineNumOffset = calculateViewportOffset(
      buffer, state.display.showLineNumbers, state.display.showSidebar
    )
  handler.motionController.viewportManager.updateViewport(
    cursorPos, buffer.len, state.display.showStatusLine, state.viewportReservedLines,
    state.display.lineWrap, buffer, lineNumOffset, state.display.tabStop,
  )
  return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

proc newNormalModeHandler*(
    motionController: MotionController,
    keyBindingRegistry: KeyBindingRegistry,
    commandRegistry: CommandRegistry,
    clipboardConfig: ClipboardConfig = ClipboardConfig(enable: false, tool: cbtXclip),
    smoothScrollConfig: SmoothScrollConfig =
      SmoothScrollConfig(enable: true, friction: 80.0, airDrag: 2.0),
    notificationConfig: NotificationConfig = NotificationConfig(),
): NormalModeHandler =
  ## Create a new Normal mode handler
  NormalModeHandler(
    motionController: motionController,
    keyBindingRegistry: keyBindingRegistry,
    commandRegistry: commandRegistry,
    clipboardConfig: clipboardConfig,
    smoothScrollConfig: smoothScrollConfig,
    notificationConfig: notificationConfig,
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
    cursor: state.cursor,
    motionController: handler.motionController,
    keyBindingRegistry: handler.keyBindingRegistry,
    clipboardConfig: handler.clipboardConfig,
    smoothScrollConfig: handler.smoothScrollConfig,
    notificationConfig: handler.notificationConfig,
  )

  let r = handler.commandRegistry.execute(ctx, commandId, args)
  state.cursor = ctx.cursor
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

proc handleModeSwitchToOverlay*(
    handler: NormalModeHandler,
    overlay: OverlayKind,
    state: EditorState,
    commandName: string = "",
): NormalModeResult =
  ## Handle overlay mode switching commands
  case overlay
  of okCommand:
    # Initialize command mode state
    state.commandText = ":"
    state.commandCursor = 0 # Cursor starts after the ":"
    return NormalModeResult(kind: nmrHandled, overlayTransition: some(okCommand))
  of okSearch:
    # Initialize search mode state
    state.search.text = ""
    # Save current cursor position for incsearch cancellation
    state.search.startPos = state.cursor
    # Set search direction based on command name
    if commandName == "switch-to-search-backward":
      state.search.direction = Backward
    else:
      state.search.direction = Forward
    # Reset history navigation index
    state.search.historyIndex = -1
    return NormalModeResult(kind: nmrHandled, overlayTransition: some(okSearch))
  of okRename:
    # Rename mode is entered through LSP rename command, not mode switch
    return NormalModeResult(kind: nmrHandled)

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
  of EditorMode.Filer:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Filer))
  of EditorMode.QuickRun:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.QuickRun))
  of EditorMode.LogViewer:
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.LogViewer))
  of EditorMode.Help:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Help))
  of EditorMode.BufferManager:
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.BufferManager))
  of EditorMode.BackupManager:
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.BackupManager))
  of EditorMode.DiffViewer:
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.DiffViewer))
  of EditorMode.RecentFile:
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.RecentFile))
  of EditorMode.Debug:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Debug))
  of EditorMode.Config:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Config))
  of EditorMode.References:
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.References))
  of EditorMode.DocumentSymbol:
    return NormalModeResult(
      kind: nmrHandled, modeTransition: some(EditorMode.DocumentSymbol)
    )
  of EditorMode.CallHierarchy:
    return
      NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.CallHierarchy))
  of EditorMode.Terminal:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Terminal))
  of EditorMode.Command:
    # Command mode is handled via overlay, not direct mode switch
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
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
    let txResult = buffer.beginTransaction("Insert mode edit")
    if txResult.isErr:
      return NormalModeResult(kind: nmrError, errorMessage: txResult.error)
    insertLineBelow(buffer, state)
  of "open-above":
    let txResult = buffer.beginTransaction("Insert mode edit")
    if txResult.isErr:
      return NormalModeResult(kind: nmrError, errorMessage: txResult.error)
    insertLineAbove(buffer, state)
  else:
    return NormalModeResult(
      kind: nmrError, errorMessage: "Unknown insert type: " & insertType
    )

  return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))

# All text manipulation (delete, yank, change) is now handled by the
# operator+motion system in command_registry.nim

# Forward declaration for recursive call in playbackMacro
proc handleNormalModeKey*(
  handler: NormalModeHandler,
  buffer: TextBuffer,
  state: EditorState,
  viewport: ViewPort,
  keyCombo: KeyCombo,
): NormalModeResult

proc requestMacroPlayback(keys: seq[string], count: int = 1): NormalModeResult =
  ## Request macro playback - actual playback is done by handler_manager
  ## This returns the keys to be played back, and handler_manager will
  ## dispatch each key to the appropriate mode handler
  NormalModeResult(kind: nmrPlaybackMacro, macroKeys: keys, macroCount: count)

proc handleNormalModeKey*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): NormalModeResult =
  ## Main entry point for handling Normal mode key presses

  # Check if we're waiting for a macro register name
  if state.macroState.waitingForRegister:
    # Expecting a register name (a-z or @)
    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      let registerChar =
        if keyCombo.char.len > 0:
          keyCombo.char[0]
        else:
          '\0'

      if state.macroState.commandType == "record":
        # Start recording to the specified register
        if registerChar >= 'a' and registerChar <= 'z':
          state.macroState.isRecording = true
          state.macroState.register = registerChar
          state.macroState.recordedKeys = @[]
          state.statusMessage = "recording @" & $registerChar
          state.macroState.waitingForRegister = false
          state.macroState.commandType = ""
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          state.statusMessage = "Invalid register (use a-z)"
          state.macroState.waitingForRegister = false
          state.macroState.commandType = ""
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      elif state.macroState.commandType == "playback":
        # Play back the macro from the specified register
        let count = state.macroState.pendingCount
        state.macroState.pendingCount = 0 # Reset for next use
        if registerChar == '@':
          # @@ - repeat last macro
          if state.macroState.lastRegister.isSome:
            let reg = state.macroState.lastRegister.get
            if state.macroState.registers.hasKey(reg):
              state.macroState.waitingForRegister = false
              state.macroState.commandType = ""
              let keys = state.macroState.registers[reg]
              return requestMacroPlayback(keys, count)
            else:
              state.statusMessage = "Register @" & $reg & " is empty"
              state.macroState.waitingForRegister = false
              state.macroState.commandType = ""
              return
                NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
          else:
            state.statusMessage = "No previous macro"
            state.macroState.waitingForRegister = false
            state.macroState.commandType = ""
            return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        elif registerChar == ':':
          # @: - repeat last Command mode command
          state.macroState.waitingForRegister = false
          state.macroState.commandType = ""
          if state.commandState.history.len > 0:
            let lastCmd = state.commandState.history[0]
            var keys: seq[string] = @[":"]
            for ch in lastCmd:
              keys.add($ch)
            keys.add("Enter")
            return requestMacroPlayback(keys, count)
          else:
            state.statusMessage = "No previous Command mode command"
            return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        elif registerChar >= 'a' and registerChar <= 'z':
          if state.macroState.registers.hasKey(registerChar):
            state.macroState.lastRegister = some(registerChar)
            state.macroState.waitingForRegister = false
            state.macroState.commandType = ""
            let keys = state.macroState.registers[registerChar]
            return requestMacroPlayback(keys, count)
          else:
            state.statusMessage = "Register @" & $registerChar & " is empty"
            state.macroState.waitingForRegister = false
            state.macroState.commandType = ""
            return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          state.statusMessage = "Invalid register (use a-z, @, or :)"
          state.macroState.waitingForRegister = false
          state.macroState.commandType = ""
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Cancel on any non-char key
      state.statusMessage = ""
      state.macroState.waitingForRegister = false
      state.macroState.commandType = ""
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  # Handle macro recording - check if we're in recording mode
  if state.macroState.isRecording:
    # Check if this key matches the key that started recording (stop recording)
    let currentKeyStr = keyComboToString(keyCombo)
    if currentKeyStr == state.macroState.recordStartKey:
      # Stop recording
      state.macroState.registers[state.macroState.register] =
        state.macroState.recordedKeys
      state.macroState.isRecording = false
      state.macroState.recordedKeys = @[]
      state.macroState.recordStartKey = ""
      state.statusMessage = ""
      handler.keyBindingRegistry.clearSequence()
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Record this key
      state.macroState.recordedKeys.add(currentKeyStr)
      # Continue processing the key normally

  # Handle pending text object - waiting for text object kind (w, ", (, etc.)
  # This handles the second part of commands like 'diw', 'da"', 'ci(' etc.
  # IMPORTANT: This must be checked BEFORE the '"' register selection handling below,
  # so that ci" works correctly (the " is the text object, not a register selection)
  if state.editState.pendingTextObject.isSome:
    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      # Map key to text object kind command
      let textObjectCommandId =
        case keyCombo.char
        of "w": "textobject.word"
        of "W": "textobject.wideword"
        of "\"": "textobject.quote.double"
        of "'": "textobject.quote.single"
        of "`": "textobject.quote.backtick"
        of "(", ")", "b": "textobject.paren"
        of "[", "]": "textobject.bracket"
        of "{", "}": "textobject.brace"
        of "<", ">": "textobject.angle"
        else: ""

      if textObjectCommandId.len > 0:
        let ctx = CommandContext(
          buffer: buffer,
          state: state,
          viewport: viewport,
          cursor: state.cursor,
          motionController: handler.motionController,
          keyBindingRegistry: handler.keyBindingRegistry,
          clipboardConfig: handler.clipboardConfig,
          smoothScrollConfig: handler.smoothScrollConfig,
          notificationConfig: handler.notificationConfig,
        )

        let cmdResult = handler.commandRegistry.execute(ctx, textObjectCommandId, @[])
        state.cursor = ctx.cursor
        if cmdResult.isOk:
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
      else:
        # Unknown text object kind - cancel pending state
        state.editState.pendingTextObject = none(PendingTextObject)
        state.editState.pendingOperator = none(PendingOperator)
        state.statusMessage = ""
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Special key or key with modifiers - cancel pending state
      state.editState.pendingTextObject = none(PendingTextObject)
      state.editState.pendingOperator = none(PendingOperator)
      state.statusMessage = ""
      # Fall through to process the key normally

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
      cursor: state.cursor,
      motionController: handler.motionController,
      keyBindingRegistry: handler.keyBindingRegistry,
      clipboardConfig: handler.clipboardConfig,
      smoothScrollConfig: handler.smoothScrollConfig,
      notificationConfig: handler.notificationConfig,
    )

    # Execute the motion command directly through CommandRegistry
    let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)
    state.cursor = ctx.cursor
    if cmdResult.isOk:
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
  of ctModeSwitch:
    return handler.handleModeSwitch(cmd.targetMode, state, buffer, cmd.name)
  of ctOverlaySwitch:
    return handler.handleModeSwitchToOverlay(cmd.targetOverlay, state, cmd.name)
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
    # dd, yy, cc are handled by operator doubling in command_registry
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
    of "file.save":
      # Save file
      return NormalModeResult(kind: nmrSave)
    of "file.save.and.quit":
      # ZZ command - Save and quit
      return NormalModeResult(kind: nmrSaveAndQuit)
    of "file.quit.force":
      # ZQ command - Quit without saving
      return NormalModeResult(kind: nmrQuitWithoutSave)
    of "window.close":
      # Close current window
      return NormalModeResult(kind: nmrCloseWindow)
    of "file.close":
      # Close current buffer
      return NormalModeResult(kind: nmrBufferDelete)
    of "window.next":
      return NormalModeResult(kind: nmrNextWindow)
    of "window.prev":
      return NormalModeResult(kind: nmrPrevWindow)
    of "window.increase-height":
      return NormalModeResult(kind: nmrIncreaseWindowHeight)
    of "window.decrease-height":
      return NormalModeResult(kind: nmrDecreaseWindowHeight)
    of "window.increase-width":
      return NormalModeResult(kind: nmrIncreaseWindowWidth)
    of "window.decrease-width":
      return NormalModeResult(kind: nmrDecreaseWindowWidth)
    of "window.equalize":
      return NormalModeResult(kind: nmrEqualizeWindows)
    of "macro.record":
      state.macroState.waitingForRegister = true
      state.macroState.commandType = "record"
      state.macroState.recordStartKey = keyComboToString(keyCombo)
      state.statusMessage = "recording @"
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    of "file.new":
      # Create new empty buffer
      return NormalModeResult(kind: nmrNewFile)
    of "file.open", "filer.open":
      # Enter filer mode to open a file
      return NormalModeResult(kind: nmrEnterFiler)
    of "buffer.next.tab":
      return NormalModeResult(kind: nmrBufferNext)
    of "buffer.prev.tab":
      return NormalModeResult(kind: nmrBufferPrev)
    of "jump.back":
      # Ctrl-o - Jump to previous position in jump list
      if state.jumpList.len == 0:
        return NormalModeResult(kind: nmrError, errorMessage: "Jump list is empty")

      # If this is the first jump back, record current position and start from end
      if state.jumpListIndex < 0:
        let currentPos = JumpPosition(
          bufferIndex: state.currentBufferIndex,
          line: state.cursor.line,
          column: state.cursor.column,
        )
        state.jumpList.add(currentPos)
        state.jumpListIndex = state.jumpList.len - 2
      else:
        state.jumpListIndex = max(0, state.jumpListIndex - 1)

      let pos = state.jumpList[state.jumpListIndex]

      # Check if we need to switch buffers
      if pos.bufferIndex != state.currentBufferIndex:
        return NormalModeResult(
          kind: nmrJumpToBuffer,
          nmrJumpBufferIndex: pos.bufferIndex,
          nmrJumpLine: pos.line,
          nmrJumpColumn: pos.column,
        )

      # Same buffer - update cursor position
      return handler.updateCursorToJumpPosition(buffer, state, pos)
    of "jump.forward":
      # Ctrl-i - Jump to next position in jump list
      if state.jumpList.len == 0 or state.jumpListIndex < 0:
        return NormalModeResult(kind: nmrError, errorMessage: "No newer jump position")

      if state.jumpListIndex >= state.jumpList.len - 1:
        return NormalModeResult(
          kind: nmrError, errorMessage: "Already at newest jump position"
        )

      state.jumpListIndex = state.jumpListIndex + 1
      let pos = state.jumpList[state.jumpListIndex]

      # Check if we need to switch buffers
      if pos.bufferIndex != state.currentBufferIndex:
        return NormalModeResult(
          kind: nmrJumpToBuffer,
          nmrJumpBufferIndex: pos.bufferIndex,
          nmrJumpLine: pos.line,
          nmrJumpColumn: pos.column,
        )

      # Same buffer - update cursor position
      return handler.updateCursorToJumpPosition(buffer, state, pos)
    else:
      # Try to execute using command registry for other actions
      let ctx = CommandContext(
        buffer: buffer,
        state: state,
        viewport: viewport,
        cursor: state.cursor,
        motionController: handler.motionController,
        keyBindingRegistry: handler.keyBindingRegistry,
        clipboardConfig: handler.clipboardConfig,
        smoothScrollConfig: handler.smoothScrollConfig,
        notificationConfig: handler.notificationConfig,
      )
      let cmdResult = handler.commandRegistry.execute(ctx, cmd.commandId, cmd.args)
      state.cursor = ctx.cursor
      if cmdResult.isOk:
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
  of ctOperatorPending:
    case cmd.operatorType
    of "macro-play":
      let registerChar =
        if cmd.targetChar.len > 0:
          cmd.targetChar[0]
        else:
          '\0'
      let count = if cmd.count > 0: cmd.count else: 1
      if registerChar == '@':
        # @@ - repeat last macro
        if state.macroState.lastRegister.isSome:
          let reg = state.macroState.lastRegister.get
          if state.macroState.registers.hasKey(reg):
            let keys = state.macroState.registers[reg]
            return requestMacroPlayback(keys, count)
          else:
            state.statusMessage = "Register @" & $reg & " is empty"
            return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          state.statusMessage = "No previous macro"
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      elif registerChar == ':':
        # @: - repeat last Command mode command
        if state.commandState.history.len > 0:
          let lastCmd = state.commandState.history[0]
          var keys: seq[string] = @[":"]
          for ch in lastCmd:
            keys.add($ch)
          keys.add("Enter")
          return requestMacroPlayback(keys, count)
        else:
          state.statusMessage = "No previous Command mode command"
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      elif registerChar >= 'a' and registerChar <= 'z':
        if state.macroState.registers.hasKey(registerChar):
          state.macroState.lastRegister = some(registerChar)
          let keys = state.macroState.registers[registerChar]
          return requestMacroPlayback(keys, count)
        else:
          state.statusMessage = "Register @" & $registerChar & " is empty"
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        state.statusMessage = "Invalid register (use a-z, @, or :)"
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    of "register-select":
      let registerChar =
        if cmd.targetChar.len > 0:
          cmd.targetChar[0]
        else:
          '\0'
      if isValidRegisterName(registerChar):
        state.pendingRegister = some(registerChar)
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        state.pendingRegister = none(char)
        state.statusMessage = "Invalid register"
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Handle operators that require additional input (f, t, r, etc)
      let ctx = CommandContext(
        buffer: buffer,
        state: state,
        viewport: viewport,
        cursor: state.cursor,
        motionController: handler.motionController,
        keyBindingRegistry: handler.keyBindingRegistry,
        clipboardConfig: handler.clipboardConfig,
        smoothScrollConfig: handler.smoothScrollConfig,
        notificationConfig: handler.notificationConfig,
      )
      let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)
      state.cursor = ctx.cursor
      if cmdResult.isOk:
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
  of ctCustom, ctTextObject, ctOperator:
    # Check for LSP commands first
    if cmd.commandId == "lsp.goto.definition":
      return NormalModeResult(kind: nmrLspGotoDefinition)
    elif cmd.commandId == "lsp.goto.declaration":
      return NormalModeResult(kind: nmrLspGotoDeclaration)
    elif cmd.commandId == "lsp.find.references":
      return NormalModeResult(kind: nmrLspFindReferences)
    elif cmd.commandId == "lsp.codelens.execute":
      return NormalModeResult(kind: nmrLspCodeLensExecute)
    elif cmd.commandId == "lsp.callhierarchy.incoming":
      return NormalModeResult(kind: nmrLspCallHierarchyIncoming)
    elif cmd.commandId == "lsp.callhierarchy.outgoing":
      return NormalModeResult(kind: nmrLspCallHierarchyOutgoing)
    elif cmd.commandId == "lsp.goto.type.definition":
      return NormalModeResult(kind: nmrLspTypeDefinition)
    elif cmd.commandId == "lsp.goto.implementation":
      return NormalModeResult(kind: nmrLspImplementation)
    elif cmd.commandId == "lsp.hover":
      return NormalModeResult(kind: nmrLspHover)
    elif cmd.commandId == "lsp.rename":
      return NormalModeResult(kind: nmrLspRename, nmrLspNewName: "")
    elif cmd.commandId == "lsp.selection.range":
      return NormalModeResult(kind: nmrLspSelectionRange)
    elif cmd.commandId == "lsp.document.link":
      return NormalModeResult(kind: nmrLspDocumentLink)
    elif cmd.commandId == "lsp.document.symbol":
      # Transition to DocumentSymbol mode
      return NormalModeResult(
        kind: nmrHandled, modeTransition: some(EditorMode.DocumentSymbol)
      )

    # Execute custom commands and operators through command registry
    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      cursor: state.cursor,
      motionController: handler.motionController,
      keyBindingRegistry: handler.keyBindingRegistry,
      clipboardConfig: handler.clipboardConfig,
      smoothScrollConfig: handler.smoothScrollConfig,
      notificationConfig: handler.notificationConfig,
    )
    # Use executeCommand to handle numeric prefixes properly
    let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)
    state.cursor = ctx.cursor
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

proc getOverlayTransition*(nmResult: NormalModeResult): Option[OverlayKind] =
  ## Get the overlay transition if any
  if nmResult.kind == nmrHandled:
    nmResult.overlayTransition
  else:
    none(OverlayKind)
