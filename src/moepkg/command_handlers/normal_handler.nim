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

import std/[options, tables, strutils]

import pkg/results

import
  ../[
    types, buffer, modes, motion, key_bindings, command_registry, registers,
    render_utils, search_utils, uri_utils, key_router,
  ]
import handler_types, visual_handler, insert_commands, command_passthrough
import ../types/editor_types
export handler_types

type
  NormalModeResultKind* = enum
    nmrHandled
    nmrUnhandled
    nmrError
    nmrPlaybackMacro # Signal to handler_manager to playback a macro
    nmrExecCommand # Signal to handler_manager to execute a Command mode command
    nmrJumpToBuffer # Signal to handler_manager to jump to buffer and position
    nmrOpenUri # Signal to handler_manager to open URI/file under cursor
    nmrPassthrough
      # Trivial 1:1 forward to a HandlerResult — payload is the canonical
      # PassthroughKind from command_passthrough.nim.

  NormalModeResult* = object ## Result of normal mode command execution
    case kind*: NormalModeResultKind
    of nmrHandled:
      modeTransition*: Option[EditorMode]
      overlayTransition*: Option[OverlayKind]
      insertReplayCount*: int
        # [count] for [count]i/a/I/A/o/O text replay; 0/1 mean no replay.
        # Carried to handler_manager, which stores it on the Insert transition.
      insertReplayLineEntry*: bool # entered via o/O (replay opens a new line)
    of nmrUnhandled:
      discard
    of nmrError:
      errorMessage*: string
    of nmrPlaybackMacro:
      macroKeys*: seq[string] # Keys to playback
      macroCount*: int # Number of times to playback (default 1)
    of nmrExecCommand:
      execCommandText*: string # Command text to execute (without leading ":")
      execCommandCount*: int # Number of times to execute (default 1)
    of nmrJumpToBuffer:
      nmrJumpBufferId*: BufferId # Target BufferId
      nmrJumpLine*: int # Target line number
      nmrJumpColumn*: int # Target column number
    of nmrOpenUri:
      openUri*: string
    of nmrPassthrough:
      passthroughKind*: PassthroughKind

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
    viewportOffset = viewportOffsetFor(buffer, state)
  handler.motionController.viewportManager.updateViewport(
    cursorPos, buffer.len, state.showStatusLine,
    state.windowDisplay.viewportReservedLines, state.lineWrap, buffer, viewportOffset,
    state.tabStop,
  )
  return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

proc newNormalModeHandler*(
    motionController: MotionController,
    keyBindingRegistry: KeyBindingRegistry,
    commandRegistry: CommandRegistry,
): NormalModeHandler =
  ## Create a new Normal mode handler. Config sections are pulled live from
  ## `state.config` via CommandContext getters, so no snapshot fields here.
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

proc findMatchContainingCursor(
    buffer: TextBuffer,
    searchText: string,
    cursorPos: BufferPosition,
    ignorecase: bool,
    wholeWord: bool,
): Option[BufferPosition] =
  ## Return start position of a match that contains the cursor, if any.
  ## Uses findSearchMatchRanges for regex-aware match detection.
  let ranges =
    buffer.findSearchMatchRanges(cursorPos.line, searchText, ignorecase, wholeWord)
  for r in ranges:
    if cursorPos.column >= r.startCol and cursorPos.column < r.endCol:
      return some(BufferPosition(line: cursorPos.line, column: r.startCol))
  return none(BufferPosition)

proc getMatchEndCol(
    buffer: TextBuffer,
    searchText: string,
    matchStart: BufferPosition,
    ignorecase: bool,
    wholeWord: bool,
): int =
  ## Get the end column (inclusive) of a match starting at matchStart.
  let ranges =
    buffer.findSearchMatchRanges(matchStart.line, searchText, ignorecase, wholeWord)
  for r in ranges:
    if r.startCol == matchStart.column:
      return r.endCol - 1
  # Fallback: use search text char length
  return matchStart.column + searchText.charLen - 1

proc searchMatchAndSelect(
    buffer: TextBuffer, state: EditorState, forward: bool
): NormalModeResult =
  ## Find a search match and enter Visual mode selecting it.
  ## Used by both gn (forward=true) and gN (forward=false).
  if state.input.search.lastText.len == 0:
    return NormalModeResult(kind: nmrError, errorMessage: "No previous search")
  let searchText = state.input.search.lastText
  let ignoreCase = shouldIgnoreCase(
    searchText, state.input.search.ignorecase, state.input.search.smartcase
  )
  let wholeWord = state.input.search.wholeWord
  state.input.search.hlsearchTempDisabled = false

  var matchStart =
    findMatchContainingCursor(buffer, searchText, state.cursor, ignoreCase, wholeWord)
  if matchStart.isNone:
    matchStart =
      if forward:
        findNext(buffer, searchText, state.cursor, ignoreCase)
      else:
        findPrev(buffer, searchText, state.cursor, ignoreCase)
  if matchStart.isNone:
    return
      NormalModeResult(kind: nmrError, errorMessage: "Pattern not found: " & searchText)

  let pos = matchStart.get
  let endCol = getMatchEndCol(buffer, searchText, pos, ignoreCase, wholeWord)
  let matchEnd = BufferPosition(line: pos.line, column: endCol)
  recordJump(state)
  state.initSelection(buffer, vskChar)
  state.visualSelection.start = pos
  state.visualSelection.current = matchEnd
  state.cursor = matchEnd
  return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Visual))

proc searchMatchAndOperate(
    buffer: TextBuffer, state: EditorState, forward: bool, op: PendingOperator
): NormalModeResult =
  ## Find a search match and apply an operator (delete/change/yank) to it.
  if state.input.search.lastText.len == 0:
    return NormalModeResult(kind: nmrError, errorMessage: "No previous search")
  let searchText = state.input.search.lastText
  let ignoreCase = shouldIgnoreCase(
    searchText, state.input.search.ignorecase, state.input.search.smartcase
  )
  let wholeWord = state.input.search.wholeWord
  state.input.search.hlsearchTempDisabled = false

  var matchStart =
    findMatchContainingCursor(buffer, searchText, state.cursor, ignoreCase, wholeWord)
  if matchStart.isNone:
    matchStart =
      if forward:
        findNext(buffer, searchText, state.cursor, ignoreCase)
      else:
        findPrev(buffer, searchText, state.cursor, ignoreCase)
  if matchStart.isNone:
    return
      NormalModeResult(kind: nmrError, errorMessage: "Pattern not found: " & searchText)

  let pos = matchStart.get
  let endCol = getMatchEndCol(buffer, searchText, pos, ignoreCase, wholeWord)
  let matchEnd = BufferPosition(line: pos.line, column: endCol)
  recordJump(state)

  # Get text in the match range
  let selectedText = buffer.getTextInRange(pos, matchEnd)
  let isMultiLine = pos.line != matchEnd.line

  # Store in register only after the buffer change succeeded (registers are not
  # covered by the buffer transaction, so a rollback would not undo them)
  proc storeMatchText() =
    if state.pendingInput.pendingRegister.isSome and
        state.pendingInput.pendingRegister.get != '\0':
      let regName = state.pendingInput.pendingRegister.get
      if regName.isNamedRegisterName:
        discard state.registers.setNamedRegister(regName, selectedText, false)
      elif regName.isClipboardRegisterName:
        state.registers.setClipboardRegister(regName, selectedText, false)
      else:
        state.registers.setDeletedRegister(selectedText, isMultiLine)
    else:
      state.registers.setDeletedRegister(selectedText, isMultiLine)
    state.pendingInput.pendingRegister = none(char)

  case op.operatorType
  of OpDelete, OpChange:
    let transactionName =
      if op.operatorType == OpDelete: "Delete search match" else: "Change search match"
    let txr = withTransaction(buffer, transactionName):
      let deleteResult = buffer.deleteRange(pos, matchEnd)
      if deleteResult.isErr:
        return NormalModeResult(kind: nmrError, errorMessage: "Failed to delete match")
    if txr.isErr:
      return NormalModeResult(
        kind: nmrError, errorMessage: "Transaction failed: " & txr.error
      )

    storeMatchText()

    # Move cursor to start of deleted range and clamp
    state.cursor = pos
    if state.cursor.line >= buffer.len:
      state.cursor.line = max(0, buffer.len - 1)
    if buffer.len > 0:
      let line = buffer.getLine(state.cursor.line)
      if line.charLen > 0:
        state.cursor.column = min(state.cursor.column, line.charLen - 1)
      else:
        state.cursor.column = 0

    if op.operatorType == OpChange:
      return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.Insert))
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
  of OpYank:
    # Yank only - no deletion, move cursor to match start
    storeMatchText()
    state.cursor = pos
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
  else:
    # Unsupported operator for search match
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

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
    state.input.commandText = ":"
    state.input.commandCursor = 0 # Cursor starts after the ":"
    return NormalModeResult(kind: nmrHandled, overlayTransition: some(okCommand))
  of okSearch:
    # Initialize search mode state
    state.input.search.text = ""
    state.input.search.cursor = 0
    # Save current cursor position for incsearch cancellation
    state.input.search.startPos = state.cursor
    # Set search direction based on command name
    if commandName == "switch-to-search-backward":
      state.input.search.direction = Backward
    else:
      state.input.search.direction = Forward
    # Reset history navigation index
    state.input.search.historyIndex = -1
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
    count: int = 1,
): NormalModeResult =
  ## Handle mode switching commands
  case targetMode
  of EditorMode.Insert:
    if buffer.readOnly:
      state.statusMessage = "Buffer is read-only"
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    # Plain `i`: honour a [count] prefix by replaying the typed text on exit.
    return NormalModeResult(
      kind: nmrHandled,
      modeTransition: some(EditorMode.Insert),
      insertReplayCount: max(1, count),
    )
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
    if buffer.readOnly:
      state.statusMessage = "Buffer is read-only"
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
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
  of EditorMode.BookmarkManager:
    return NormalModeResult(
      kind: nmrHandled, modeTransition: some(EditorMode.BookmarkManager)
    )
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
  of EditorMode.FileTree:
    return NormalModeResult(kind: nmrHandled, modeTransition: some(EditorMode.FileTree))
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
    count: int = 1,
): NormalModeResult =
  ## Handle different types of insert mode entry (i, a, o, O, etc.)
  ## `count` is the numeric prefix for [count]a/[count]o etc.; the typed text is
  ## replayed (count - 1) more times when Insert mode is left.
  if buffer.readOnly:
    state.statusMessage = "Buffer is read-only"
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
  # Expand a collapsed fold at the cursor so inserted text is never hidden
  # behind a fold marker.
  discard buffer.foldState.openFold(state.cursor.line)
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
    if not buffer.inTransaction:
      let txResult =
        buffer.beginTransaction("Insert mode edit", cursorPos = some(state.cursor))
      if txResult.isErr:
        return NormalModeResult(kind: nmrError, errorMessage: txResult.error)
    insertLineBelow(buffer, state)
  of "open-above":
    if not buffer.inTransaction:
      let txResult =
        buffer.beginTransaction("Insert mode edit", cursorPos = some(state.cursor))
      if txResult.isErr:
        return NormalModeResult(kind: nmrError, errorMessage: txResult.error)
    insertLineAbove(buffer, state)
  else:
    return NormalModeResult(
      kind: nmrError, errorMessage: "Unknown insert type: " & insertType
    )

  return NormalModeResult(
    kind: nmrHandled,
    modeTransition: some(EditorMode.Insert),
    insertReplayCount: max(1, count),
    insertReplayLineEntry: insertType in ["open-below", "open-above"],
  )

# All text manipulation (delete, yank, change) is now handled by the
# operator+motion system in command_registry.nim

proc requestMacroPlayback(keys: seq[string], count: int = 1): NormalModeResult =
  ## Request macro playback - actual playback is done by handler_manager
  ## This returns the keys to be played back, and handler_manager will
  ## dispatch each key to the appropriate mode handler
  NormalModeResult(kind: nmrPlaybackMacro, macroKeys: keys, macroCount: count)

proc fromPassthrough(k: PassthroughKind): NormalModeResult {.inline.} =
  ## Wrap a PassthroughKind in NormalModeResult. handler_manager will unwrap
  ## it back to a HandlerResult via command_passthrough.toHandlerResult.
  NormalModeResult(kind: nmrPassthrough, passthroughKind: k)

proc handleNormalModeKey*(
    handler: NormalModeHandler,
    buffer: TextBuffer,
    state: EditorState,
    viewport: ViewPort,
    keyCombo: KeyCombo,
): NormalModeResult =
  ## Main entry point for handling Normal mode key presses

  # Check if we're waiting for a macro register name
  if state.pendingInput.macroState.waitingForRegister:
    # Expecting a register name (a-z or @)
    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      let registerChar =
        if keyCombo.char.len > 0:
          keyCombo.char[0]
        else:
          '\0'

      if state.pendingInput.macroState.commandType == "record":
        # Start recording to the specified register
        if registerChar >= 'a' and registerChar <= 'z':
          state.pendingInput.macroState.isRecording = true
          state.pendingInput.macroState.register = registerChar
          state.pendingInput.macroState.recordedKeys = @[]
          state.statusMessage = "recording @" & $registerChar
          state.pendingInput.macroState.waitingForRegister = false
          state.pendingInput.macroState.commandType = ""
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          state.statusMessage = "Invalid register (use a-z)"
          state.pendingInput.macroState.waitingForRegister = false
          state.pendingInput.macroState.commandType = ""
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Cancel on any non-char key
      state.statusMessage = ""
      state.pendingInput.macroState.waitingForRegister = false
      state.pendingInput.macroState.commandType = ""
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  # Stop recording when the user re-presses the record-start key (`q`).
  # Per-key recording is captured centrally in `handler.handleKeyCombo`; the
  # matching `isMacroStopKey` guard suppresses recording of this closing key.
  if state.pendingInput.macroState.isRecording:
    let currentKeyStr = keyComboToString(keyCombo)
    if currentKeyStr == state.pendingInput.macroState.recordStartKey and
        not handler.keyBindingRegistry.isWaitingForChar():
      state.pendingInput.macroState.registers[state.pendingInput.macroState.register] =
        state.pendingInput.macroState.recordedKeys
      state.pendingInput.macroState.isRecording = false
      state.pendingInput.macroState.recordedKeys = @[]
      state.pendingInput.macroState.recordStartKey = ""
      state.statusMessage = ""
      handler.keyBindingRegistry.clearSequence()
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  # Handle pending text object - waiting for text object kind (w, ", (, etc.)
  # This handles the second part of commands like 'diw', 'da"', 'ci(' etc.
  # IMPORTANT: This must be checked BEFORE the '"' register selection handling below,
  # so that ci" works correctly (the " is the text object, not a register selection)
  if state.pendingInput.pendingTextObject.isSome:
    if not keyCombo.isSpecial and keyCombo.modifiers == {}:
      # Map key to text object kind command (shared with the Visual handler)
      let textObjectCommandId = textObjectCommandIdFor(keyCombo.char)

      if textObjectCommandId.len > 0:
        let ctx = CommandContext(
          buffer: buffer,
          state: state,
          viewport: viewport,
          motionController: handler.motionController,
          keyBindingRegistry: handler.keyBindingRegistry,
        )

        let cmdResult = handler.commandRegistry.execute(ctx, textObjectCommandId, @[])
        if cmdResult.isOk:
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
      else:
        # Not a text object key - cancel pending state with feedback (no silent
        # drop of the pending operator).
        state.pendingInput.pendingTextObject = none(PendingTextObject)
        state.pendingInput.pendingOperator = none(PendingOperator)
        state.statusMessage = "Not a text object: " & keyCombo.char
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Special key or key with modifiers - cancel pending state
      state.pendingInput.pendingTextObject = none(PendingTextObject)
      state.pendingInput.pendingOperator = none(PendingOperator)
      state.statusMessage = ""
      # Fall through to process the key normally

  # `guu` / `gUU` lowercase/uppercase whole lines. Handled here because the
  # second key is not the operator key: the router would turn `u` into undo.
  # (`gugu` / `gUgU` need no special case - they re-enter the operator handler.)
  let pendingOp = state.pendingInput.pendingOperator
  if pendingOp.isSome and not keyCombo.isSpecial and keyCombo.modifiers == {} and (
    (pendingOp.get.operatorType == OpLowerCase and keyCombo.char == "u") or
    (pendingOp.get.operatorType == OpUpperCase and keyCombo.char == "U")
  ):
    let doubledOperatorId =
      if pendingOp.get.operatorType == OpLowerCase:
        "operator.lowercase"
      else:
        "operator.uppercase"

    # Consume a count typed between the halves (gu3u); the router never sees
    # the key that would clear it
    let count = handler.keyBindingRegistry.getNumericPrefix()
    handler.keyBindingRegistry.clearNumericPrefix()
    # gugu/gUgU: drop the intermediate `g` the router already stashed.
    handler.keyBindingRegistry.clearSequence()

    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: handler.motionController,
      keyBindingRegistry: handler.keyBindingRegistry,
    )

    let cmdResult = handler.commandRegistry.execute(ctx, doubledOperatorId, @[$count])
    if cmdResult.isOk:
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)

  # Resolve the key through the router (numeric prefixes, sequences, f/t/r, etc.)
  let route = handler.keyBindingRegistry.resolveBuiltin(EditorMode.Normal, keyCombo)
  if route.kind != rrCommand:
    # Key consumed (waiting / cancelled) or unhandled: all collapse to the
    # previous `cmdOption.isNone` behaviour (handled, no mode transition).
    return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))

  let cmd = route.command

  case cmd.kind
  of ctMotion:
    # Execute all motions through CommandRegistry to handle numeric prefixes
    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: handler.motionController,
      keyBindingRegistry: handler.keyBindingRegistry,
    )

    # Execute the motion command directly through CommandRegistry
    let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)
    if cmdResult.isOk:
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
  of ctModeSwitch:
    return handler.handleModeSwitch(cmd.targetMode, state, buffer, cmd.name, cmd.count)
  of ctOverlaySwitch:
    return handler.handleModeSwitchToOverlay(cmd.targetOverlay, state, cmd.name)
  of ctAction:
    # Command mode command alias bridge: `exec.cmdline.<alias>` runs
    # `:<alias>` via the full command-line parser, so safety checks
    # (modified-buffer guard etc.) fire.
    if cmd.commandId.startsWith(ExecCmdlinePrefix):
      let aliasText = cmd.commandId[ExecCmdlinePrefix.len ..^ 1]
      return NormalModeResult(
        kind: nmrExecCommand, execCommandText: aliasText, execCommandCount: 1
      )
    # Trivial passthrough commands (window.*, file.*, buffer.*.tab) share
    # their commandId table with executeCommandDirect via command_passthrough.
    let ptAction = lookupPassthrough(cmd.commandId)
    if ptAction.isSome:
      return fromPassthrough(ptAction.get)
    # Handle various actions based on command ID
    case cmd.commandId
    of "insert.append":
      return handler.handleInsertModeEntry(buffer, state, "append", cmd.count)
    of "insert.append.end":
      return handler.handleInsertModeEntry(buffer, state, "append-end", cmd.count)
    of "insert.first.non.blank":
      return handler.handleInsertModeEntry(
        buffer, state, "insert-first-non-blank", cmd.count
      )
    of "insert.line.below":
      return handler.handleInsertModeEntry(buffer, state, "open-below", cmd.count)
    of "insert.line.above":
      return handler.handleInsertModeEntry(buffer, state, "open-above", cmd.count)
    # dd, yy, cc are handled by operator doubling in command_registry
    of "edit.undo":
      let r = buffer.undo()
      if r.isOk:
        state.cursor = r.value
        # Clamp cursor to valid buffer range
        if buffer.len > 0:
          if state.cursor.line >= buffer.len:
            state.cursor.line = buffer.len - 1
          let line = buffer.getLine(state.cursor.line)
          let maxCol = max(0, line.charLen - 1)
          if state.cursor.column > maxCol:
            state.cursor.column = maxCol
        else:
          state.cursor = BufferPosition(line: 0, column: 0)
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        return NormalModeResult(kind: nmrError, errorMessage: r.error)
    of "edit.redo":
      let r = buffer.redo()
      if r.isOk:
        state.cursor = r.value
        # Clamp cursor to valid buffer range
        if buffer.len > 0:
          if state.cursor.line >= buffer.len:
            state.cursor.line = buffer.len - 1
          let line = buffer.getLine(state.cursor.line)
          let maxCol = max(0, line.charLen - 1)
          if state.cursor.column > maxCol:
            state.cursor.column = maxCol
        else:
          state.cursor = BufferPosition(line: 0, column: 0)
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        return NormalModeResult(kind: nmrError, errorMessage: r.error)
    of "macro.record":
      state.pendingInput.macroState.waitingForRegister = true
      state.pendingInput.macroState.commandType = "record"
      state.pendingInput.macroState.recordStartKey = keyComboToString(keyCombo)
      state.statusMessage = "recording @"
      return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    of "changelist.prev":
      # g; - Jump to older change position
      if buffer.changeList.len == 0:
        return NormalModeResult(kind: nmrError, errorMessage: "Change list is empty")

      if buffer.changeListIndex < 0:
        return
          NormalModeResult(kind: nmrError, errorMessage: "Already at oldest change")

      let pos = buffer.changeList[buffer.changeListIndex]
      buffer.changeListIndex = max(0, buffer.changeListIndex - 1)
      let jumpPos = JumpPosition(
        bufferId: state.windowDisplay.currentBufferId,
        line: pos.line,
        column: pos.column,
      )
      return handler.updateCursorToJumpPosition(buffer, state, jumpPos)
    of "changelist.next":
      # g, - Jump to newer change position
      if buffer.changeList.len == 0:
        return NormalModeResult(kind: nmrError, errorMessage: "Change list is empty")

      if buffer.changeListIndex >= buffer.changeList.len - 1:
        return
          NormalModeResult(kind: nmrError, errorMessage: "Already at newest change")

      buffer.changeListIndex += 1
      let pos = buffer.changeList[buffer.changeListIndex]
      let jumpPos = JumpPosition(
        bufferId: state.windowDisplay.currentBufferId,
        line: pos.line,
        column: pos.column,
      )
      return handler.updateCursorToJumpPosition(buffer, state, jumpPos)
    of "bookmark.toggle":
      buffer.toggleBookmark(state.cursor.line)
      return NormalModeResult(kind: nmrHandled)
    of "bookmark.next":
      let next = buffer.findNextBookmark(state.cursor.line)
      if next.isNone:
        return NormalModeResult(kind: nmrError, errorMessage: "No bookmarks")
      let jumpPos = JumpPosition(
        bufferId: state.windowDisplay.currentBufferId, line: next.get, column: 0
      )
      return handler.updateCursorToJumpPosition(buffer, state, jumpPos)
    of "bookmark.prev":
      let prev = buffer.findPrevBookmark(state.cursor.line)
      if prev.isNone:
        return NormalModeResult(kind: nmrError, errorMessage: "No bookmarks")
      let jumpPos = JumpPosition(
        bufferId: state.windowDisplay.currentBufferId, line: prev.get, column: 0
      )
      return handler.updateCursorToJumpPosition(buffer, state, jumpPos)
    of "bookmark.clear":
      buffer.clearBookmarks()
      return NormalModeResult(kind: nmrHandled)
    of "jump.back":
      # Ctrl-o - Jump to previous position in jump list
      if state.jumpList.list.len == 0:
        return NormalModeResult(kind: nmrError, errorMessage: "Jump list is empty")

      # If this is the first jump back, record current position and start from end
      if state.jumpList.index < 0:
        let currentPos = JumpPosition(
          bufferId: state.windowDisplay.currentBufferId,
          line: state.cursor.line,
          column: state.cursor.column,
        )
        state.jumpList.list.add(currentPos)
        state.jumpList.index = state.jumpList.list.len - 2
      else:
        state.jumpList.index = max(0, state.jumpList.index - 1)

      let pos = state.jumpList.list[state.jumpList.index]

      # Check if we need to switch buffers
      if pos.bufferId != state.windowDisplay.currentBufferId:
        return NormalModeResult(
          kind: nmrJumpToBuffer,
          nmrJumpBufferId: pos.bufferId,
          nmrJumpLine: pos.line,
          nmrJumpColumn: pos.column,
        )

      # Same buffer - update cursor position
      return handler.updateCursorToJumpPosition(buffer, state, pos)
    of "jump.forward":
      # Ctrl-i - Jump to next position in jump list
      if state.jumpList.list.len == 0 or state.jumpList.index < 0:
        return NormalModeResult(kind: nmrError, errorMessage: "No newer jump position")

      if state.jumpList.index >= state.jumpList.list.len - 1:
        return NormalModeResult(
          kind: nmrError, errorMessage: "Already at newest jump position"
        )

      state.jumpList.index = state.jumpList.index + 1
      let pos = state.jumpList.list[state.jumpList.index]

      # Check if we need to switch buffers
      if pos.bufferId != state.windowDisplay.currentBufferId:
        return NormalModeResult(
          kind: nmrJumpToBuffer,
          nmrJumpBufferId: pos.bufferId,
          nmrJumpLine: pos.line,
          nmrJumpColumn: pos.column,
        )

      # Same buffer - update cursor position
      return handler.updateCursorToJumpPosition(buffer, state, pos)
    of "search.next.select":
      if state.pendingInput.pendingOperator.isSome:
        let op = state.pendingInput.pendingOperator.get
        state.pendingInput.pendingOperator = none(PendingOperator)
        return searchMatchAndOperate(buffer, state, forward = true, op)
      return searchMatchAndSelect(buffer, state, forward = true)
    of "search.prev.select":
      if state.pendingInput.pendingOperator.isSome:
        let op = state.pendingInput.pendingOperator.get
        state.pendingInput.pendingOperator = none(PendingOperator)
        return searchMatchAndOperate(buffer, state, forward = false, op)
      return searchMatchAndSelect(buffer, state, forward = false)
    else:
      # Try to execute using command registry for other actions
      let ctx = CommandContext(
        buffer: buffer,
        state: state,
        viewport: viewport,
        motionController: handler.motionController,
        keyBindingRegistry: handler.keyBindingRegistry,
      )
      let cmdResult = handler.commandRegistry.execute(ctx, cmd.commandId, cmd.args)
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
        if state.pendingInput.macroState.lastRegister.isSome:
          let reg = state.pendingInput.macroState.lastRegister.get
          if state.pendingInput.macroState.registers.hasKey(reg):
            let keys = state.pendingInput.macroState.registers[reg]
            return requestMacroPlayback(keys, count)
          else:
            state.statusMessage = "Register @" & $reg & " is empty"
            return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
        else:
          state.statusMessage = "No previous macro"
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      elif registerChar == ':':
        # @: - repeat last Command mode command
        if state.input.commandState.history.len > 0:
          let lastCmd = state.input.commandState.history[0]
          return NormalModeResult(
            kind: nmrExecCommand, execCommandText: lastCmd, execCommandCount: count
          )
        else:
          state.statusMessage = "No previous Command mode command"
          return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      elif registerChar >= 'a' and registerChar <= 'z':
        if state.pendingInput.macroState.registers.hasKey(registerChar):
          state.pendingInput.macroState.lastRegister = some(registerChar)
          let keys = state.pendingInput.macroState.registers[registerChar]
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
        state.pendingInput.pendingRegister = some(registerChar)
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        state.pendingInput.pendingRegister = none(char)
        state.statusMessage = "Invalid register"
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
    else:
      # Handle operators that require additional input (f, t, r, etc)
      let ctx = CommandContext(
        buffer: buffer,
        state: state,
        viewport: viewport,
        motionController: handler.motionController,
        keyBindingRegistry: handler.keyBindingRegistry,
      )
      let cmdResult = handler.commandRegistry.executeCommand(ctx, cmd)
      if cmdResult.isOk:
        return NormalModeResult(kind: nmrHandled, modeTransition: none(EditorMode))
      else:
        return NormalModeResult(kind: nmrError, errorMessage: cmdResult.error)
  of ctCustom, ctTextObject, ctOperator:
    # Trivial passthrough LSP commands share their commandId table with
    # executeCommandDirect via command_passthrough.
    let ptCustom = lookupPassthrough(cmd.commandId)
    if ptCustom.isSome:
      return fromPassthrough(ptCustom.get)
    if cmd.commandId == "editor.open.uri":
      let line = buffer.getLine(state.cursor.line)
      let uriOpt = extractUriAtPosition(line, state.cursor.column)
      if uriOpt.isSome:
        return NormalModeResult(kind: nmrOpenUri, openUri: uriOpt.get)
      let pathOpt = extractFilePathAtPosition(line, state.cursor.column)
      if pathOpt.isSome:
        return NormalModeResult(kind: nmrOpenUri, openUri: pathOpt.get)
      return NormalModeResult(
        kind: nmrError, errorMessage: "No URI or file path under cursor"
      )

    # Execute custom commands and operators through command registry
    let ctx = CommandContext(
      buffer: buffer,
      state: state,
      viewport: viewport,
      motionController: handler.motionController,
      keyBindingRegistry: handler.keyBindingRegistry,
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

proc getOverlayTransition*(nmResult: NormalModeResult): Option[OverlayKind] =
  ## Get the overlay transition if any
  if nmResult.kind == nmrHandled:
    nmResult.overlayTransition
  else:
    none(OverlayKind)
