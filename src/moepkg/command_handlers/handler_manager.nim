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

## Unified handler manager
##
## Top-level orchestrator for the dispatcher layer. Owns the HandlerManager
## constructor, the Normal-mode dispatcher (with its post-processing helper),
## the runtime key-sequence mapping precheck, the macro playback driver, and
## the public Editor-based dispatch entry points (handleEvent / handleKeyCombo).
##
## Per-mode result translation (Insert, Visual, Replace, Command, Search and
## the sub-state modes) lives in mode_dispatchers.nim. Variant types and small
## getters live in handler_result.nim. Both are re-exported from this module
## so external callers (`editor.nim`, `handler.nim`, tests) see the same
## public surface as before.

import std/[options, tables, strutils]

import pkg/[results, celina]

import
  ../[
    types, buffer, modes, motion, key_bindings, command_line, command_config,
    command_registry, config, lsp_integration, logger,
  ]
import ../editor_types
import
  handler_types, handler_result, mode_dispatchers, normal_handler, insert_handler,
  insert_commands, command_handler, visual_handler, replace_handler, filer_handler,
  filetree_handler, log_viewer_handler, help_handler, buffer_manager_handler,
  bookmark_manager_handler, backup_manager_handler, diff_viewer_handler,
  recent_file_mode_handler, debug_handler, config_handler, references_handler,
  documentsymbol_handler, callhierarchy_handler, terminal_handler, command_passthrough

export
  handler_types, handler_result, mode_dispatchers, normal_handler, insert_handler,
  insert_commands, command_handler, visual_handler, replace_handler, filer_handler,
  filetree_handler, log_viewer_handler, help_handler, buffer_manager_handler,
  bookmark_manager_handler, backup_manager_handler, diff_viewer_handler,
  recent_file_mode_handler, debug_handler, config_handler, references_handler,
  documentsymbol_handler, callhierarchy_handler, terminal_handler

proc newHandlerManager*(
    motionController: MotionController,
    keyBindingRegistry: KeyBindingRegistry,
    commandLineParser: CommandLineParser,
    commandConfig: CommandConfig,
    commandRegistry: CommandRegistry,
    clipboardConfig: ClipboardConfig,
    smoothScrollConfig: SmoothScrollConfig =
      SmoothScrollConfig(enable: true, friction: 80.0, airDrag: 2.0),
    notificationConfig: NotificationConfig = NotificationConfig(),
    lsp: LspIntegration = nil,
    autocompleteEnabled: bool = true,
    lspCompletionEnabled: bool = true,
): HandlerManager =
  ## Create a new handler manager with all mode handlers

  let normalHandler = newNormalModeHandler(
    motionController, keyBindingRegistry, commandRegistry, clipboardConfig,
    smoothScrollConfig, notificationConfig,
  )
  let insertHandler = newInsertModeHandler(
    keyBindingRegistry, motionController, commandRegistry, lsp, autocompleteEnabled,
    lspCompletionEnabled, notificationConfig,
  )
  let commandHandler =
    newCommandModeHandler(commandLineParser, commandConfig, commandRegistry)
  let visualHandler = newVisualModeHandler(
    keyBindingRegistry, commandRegistry, motionController, notificationConfig
  )
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

# Forward declarations for the Normal-mode recursive cluster.
proc handleKeyCombo*(
  manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): HandlerResult

proc playbackMacro*(
  manager: HandlerManager, editor: Editor, keys: seq[string]
): HandlerResult

proc executeCommandDirect*(
    manager: HandlerManager, commandName: string
): Option[HandlerResult] =
  ## Execute a named command directly, returning a HandlerResult.
  ## This is used for rmkCommand runtime mappings in modes that don't use
  ## findBinding (Special modes like Filer, LogViewer, etc.).
  ## Returns none if the command is unknown or not executable directly.

  if not manager.keyBindingRegistry.commandRegistry.hasKey(commandName):
    return none(HandlerResult)

  let command = manager.keyBindingRegistry.commandRegistry[commandName]
  # Command mode command alias bridge: `exec.cmdline.<alias>` routes through
  # the full command-line parser so `:bd`-style safety checks fire even in
  # special modes.
  if command.kind == ctAction and command.commandId.startsWith(ExecCmdlinePrefix):
    let aliasText = command.commandId[ExecCmdlinePrefix.len ..^ 1]
    return some(
      HandlerResult(
        kind: hrExecCommand, execCommandText: aliasText, execCommandCount: 1
      )
    )
  case command.kind
  of ctAction:
    # Trivial passthrough commandIds (window.*, file.*, buffer.*.tab) share
    # their dispatch table with normal_handler via command_passthrough.
    let pt = lookupPassthrough(command.commandId)
    if pt.isSome:
      return some(toHandlerResult(pt.get))
    case command.commandId
    of "lsp.format":
      return some(HandlerResult(kind: hrLspFormat))
    of "lsp.restart":
      return some(HandlerResult(kind: hrLspRestart))
    of "lsp.fold":
      return some(HandlerResult(kind: hrLspFold))
    else:
      logWarn "executeCommandDirect",
        "Command '" & command.commandId &
          "' cannot be executed directly in special modes; use key sequence mapping instead"
      return none(HandlerResult)
  of ctCustom:
    # Trivial passthrough LSP commands and quickrun share their dispatch
    # table with normal_handler via command_passthrough.
    let pt = lookupPassthrough(command.commandId)
    if pt.isSome:
      return some(toHandlerResult(pt.get))
    logWarn "executeCommandDirect",
      "Command '" & command.commandId &
        "' cannot be executed directly in special modes; use key sequence mapping instead"
    return none(HandlerResult)
  of ctModeSwitch:
    return some(
      HandlerResult(
        kind: hrHandled, modeTransition: some(command.targetMode), statusMessage: ""
      )
    )
  of ctOverlaySwitch:
    return some(
      HandlerResult(
        kind: hrHandled,
        overlayTransition: some(command.targetOverlay),
        statusMessage: "",
      )
    )
  of ctMotion, ctOperator, ctTextObject, ctOperatorPending:
    logWarn "executeCommandDirect",
      "Command '" & commandName &
        "' cannot be executed directly in special modes; use key sequence mapping instead"
    return none(HandlerResult)

const MaxMacroRecursionDepth = 100
  ## Maximum macro recursion depth to prevent infinite loops

proc checkRuntimeKeySeqMapping(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): Option[HandlerResult] =
  ## Ask the KeyRouter whether `keyCombo` is part of a runtime mapping. The
  ## router picks the right mapping table for the current mode and returns a
  ## `RouteResult` telling us what to do. Built-in command resolution happens
  ## *after* this proc returns `none`, inside the mode-specific dispatcher.
  ##
  ## Flush semantics here are the "base mode" variant: when no match exists
  ## we replay all accumulated keys *except the current one* and let the
  ## caller re-process the current key. The Command overlay path lives in
  ## `command_mode_handler.handleCommandModeKeyCombo` and uses the full-flush
  ## variant.
  let state = editor.state
  let route = editor.keyRouter.feedKey(state.mode, keyCombo)
  case route.kind
  of rrUnhandled, rrCancelled, rrCommand:
    # rrCommand is produced only by resolveBuiltin (Normal dispatcher), never by
    # feedKey; listed for exhaustiveness. Fall through to built-in resolution.
    return none(HandlerResult)
  of rrExecuteRuntimeCommand:
    let cmdResult = manager.executeCommandDirect(route.commandName)
    if cmdResult.isSome:
      return cmdResult
    return none(HandlerResult)
  of rrExecuteRuntimeKeySequence:
    var playbackResult: HandlerResult
    editor.keyRouter.withReplay:
      playbackResult = manager.playbackMacro(editor, route.targetKeys)
    return some(playbackResult)
  of rrWaiting:
    return some(
      HandlerResult(
        kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
      )
    )
  of rrUnhandledBatch:
    # Replay all accumulated keys except the current one, then let the
    # caller re-process the current key normally.
    let keysToFlush = route.keys[0 ..< route.keys.len - 1]
    var earlyExit = none(HandlerResult)
    editor.keyRouter.withReplay:
      for k in keysToFlush:
        let flushResult = manager.handleKeyCombo(editor, k)
        if flushResult.kind == hrHandled and flushResult.modeTransition.isSome:
          state.mode = flushResult.modeTransition.get
        if flushResult.kind == hrError or flushResult.kind == hrQuit:
          earlyExit = some(flushResult)
          break
    if earlyExit.isSome:
      return earlyExit
    return none(HandlerResult)

proc applyNormalModePostProcessing(
    manager: HandlerManager, editor: Editor, normalResult: HandlerResult
): HandlerResult =
  ## Insert-Normal (Ctrl-o) bookkeeping run after a Normal mode command
  ## completes. Decides whether to return to Insert mode, commit the pending
  ## Insert transaction, or pass the result through unchanged.
  let buffer = editor.activeBuffer
  let state = editor.state

  if state.insertNormalMode and normalResult.kind == hrHandled:
    let hasOverlay = normalResult.overlayTransition.isSome
    let hasPending =
      state.editState.pendingOperator.isSome or state.editState.pendingTextObject.isSome or
      state.pendingCommand != PendingNone or state.pendingRegister.isSome or
      state.macroState.waitingForRegister or editor.keyRouter.hasActiveBuiltinSequence()
    if not hasPending and not hasOverlay:
      if normalResult.modeTransition.isSome and
          normalResult.modeTransition.get == EditorMode.Insert:
        state.insertNormalMode = false
        return normalResult
      elif normalResult.modeTransition.isNone or
          normalResult.modeTransition.get == EditorMode.Normal:
        state.insertNormalMode = false
        return HandlerResult(
          kind: hrHandled,
          modeTransition: some(EditorMode.Insert),
          statusMessage: normalResult.statusMessage,
        )
      else:
        state.insertNormalMode = false
        if buffer.inTransaction:
          clearAutoIndentIfUnedited(buffer, state)
          discard buffer.commitTransaction()
        state.editState.insertModeStartPos = none(BufferPosition)
        state.editState.substituteContext = none(types.SubstituteContext)
        let newMode = normalResult.modeTransition.get
        if newMode == EditorMode.Replace:
          discard buffer.beginTransaction("Replace mode edit")
        return normalResult

  if state.insertNormalMode and normalResult.kind notin {
    hrHandled, hrUnhandled, hrError
  }:
    state.insertNormalMode = false
    if buffer.inTransaction:
      clearAutoIndentIfUnedited(buffer, state)
      discard buffer.commitTransaction()
    state.editState.insertModeStartPos = none(BufferPosition)
    state.editState.substituteContext = none(types.SubstituteContext)

  return normalResult

proc handleNormalMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Normal mode input
  let buffer = editor.activeBuffer
  let state = editor.state
  let r =
    manager.normalHandler.handleNormalModeKey(buffer, state, editor.viewport, keyCombo)

  # Trivial passthrough variants (window.*, file.*, buffer.*.tab, lsp.*
  # custom) collapse into a single shared translation table.
  if r.kind == nmrPassthrough:
    return toHandlerResult(r.passthroughKind)

  case r.kind
  of nmrHandled:
    # Check if we're entering Insert or Replace mode
    if r.modeTransition.isSome:
      let targetMode = r.modeTransition.get
      if targetMode == EditorMode.Insert:
        if not buffer.inTransaction:
          let transactionResult =
            buffer.beginTransaction("Insert mode edit", cursorPos = some(state.cursor))
          if transactionResult.isErr:
            return HandlerResult(
              kind: hrError,
              errorMessage: "Failed to begin transaction: " & transactionResult.error,
            )
        # Record insert start position for text tracking
        # Don't reset if transaction is already active (e.g. returning from insert-normal)
        if state.editState.insertModeStartPos.isNone:
          state.editState.insertModeStartPos = some(state.cursor)
      elif targetMode == EditorMode.Replace:
        # Reveal a collapsed fold at the cursor so Replace never overtypes text
        # hidden behind a fold marker (mirrors the Insert-mode entry behaviour).
        if buffer.foldState.openFold(state.cursor.line):
          state.windowDisplay.needsFullRedraw = true
        # Begin a transaction when entering Replace mode
        # Guard: during insert-normal mode a transaction is already open
        if not buffer.inTransaction:
          let transactionResult =
            buffer.beginTransaction("Replace mode edit", cursorPos = some(state.cursor))
          if transactionResult.isErr:
            return HandlerResult(
              kind: hrError,
              errorMessage: "Failed to begin transaction: " & transactionResult.error,
            )
        # Clear replace history when entering Replace mode
        state.editState.replaceHistory = @[]
    return HandlerResult(
      kind: hrHandled,
      modeTransition: r.modeTransition,
      overlayTransition: r.overlayTransition,
      statusMessage: "",
    )
  of nmrUnhandled:
    return HandlerResult(kind: hrUnhandled)
  of nmrError:
    return HandlerResult(kind: hrError, errorMessage: r.errorMessage)
  of nmrPlaybackMacro:
    # Playback the macro through handler_manager which can dispatch to any mode
    # Loop for the specified count (e.g., 3@a plays macro 3 times)
    let count = if r.macroCount > 0: r.macroCount else: 1
    for i in 0 ..< count:
      let playbackResult = manager.playbackMacro(editor, r.macroKeys)
      if playbackResult.kind == hrError or playbackResult.kind == hrQuit:
        return playbackResult
    return HandlerResult(
      kind: hrHandled, modeTransition: none(EditorMode), statusMessage: ""
    )
  of nmrExecCommand:
    # @: - repeat last Command mode command
    # Pass through to handler.nim which has access to Editor for full result processing
    return HandlerResult(
      kind: hrExecCommand,
      execCommandText: r.execCommandText,
      execCommandCount: if r.execCommandCount > 0: r.execCommandCount else: 1,
    )
  of nmrJumpToBuffer:
    # Signal to editor to jump to a specific buffer and position
    return HandlerResult(
      kind: hrJumpToBuffer,
      jumpBufferId: r.nmrJumpBufferId,
      jumpLine: r.nmrJumpLine,
      jumpColumn: r.nmrJumpColumn,
    )
  of nmrOpenUri:
    return HandlerResult(kind: hrOpenUri, openUri: r.openUri)
  of nmrPassthrough:
    # Unreachable: captured by the early return above. Listed to satisfy
    # case exhaustiveness.
    return HandlerResult(kind: hrUnhandled)

proc handleEvent*(manager: HandlerManager, e: Editor, event: Event): HandlerResult =
  ## Editor-based event entry point. Stays entirely on the Editor dispatch path.
  if event.kind != EventKind.Key:
    return HandlerResult(kind: hrUnhandled)
  let keyComboOpt = eventToKeyCombo(event)
  if keyComboOpt.isNone:
    return HandlerResult(kind: hrUnhandled)
  manager.handleKeyCombo(e, keyComboOpt.get)

proc handleKeyCombo*(
    manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Editor-based dispatch. Migrated modes (Normal/Insert/Visual/Replace)
  ## are handled directly here; sub-state modes are forwarded
  ## to dispatchSubStateMode.

  # Complete any active scroll animation on key input (instant jump to target)
  if e.state.windowDisplay.scrollAnimation.active:
    let (completed, cursorLine) =
      completeScrollAnimation(e.state.windowDisplay.scrollAnimation)
    if completed:
      e.state.cursor.line = cursorLine

  # Runtime key-sequence mapping precheck (noremap: skip during replay)
  if not manager.keyBindingRegistry.isReplayingMapping:
    let expandResult = manager.checkRuntimeKeySeqMapping(e, keyCombo)
    if expandResult.isSome:
      return expandResult.get

  case e.state.mode
  of EditorMode.Normal:
    let normalResult = manager.handleNormalMode(e, keyCombo)
    return manager.applyNormalModePostProcessing(e, normalResult)
  of EditorMode.Insert:
    return manager.handleInsertMode(e, keyCombo)
  of EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine:
    return manager.handleVisualMode(e, keyCombo)
  of EditorMode.Replace:
    return manager.handleReplaceMode(e, keyCombo)
  else:
    return manager.dispatchSubStateMode(e, keyCombo)

proc playbackMacro*(
    manager: HandlerManager, editor: Editor, keys: seq[string]
): HandlerResult =
  ## Editor-based macro playback. Iterates keys and dispatches each through
  ## the Editor-aware handleKeyCombo so migrated modes (Insert/Visual/Replace)
  ## are handled correctly during playback.
  let state = editor.state

  if state.macroState.playbackDepth >= MaxMacroRecursionDepth:
    return HandlerResult(
      kind: hrError,
      errorMessage:
        "Macro recursion limit exceeded (max " & $MaxMacroRecursionDepth & ")",
    )

  state.macroState.playbackDepth += 1
  editor.keyRouter.clearBuiltinSequence()
  let wasRecording = state.macroState.isRecording
  state.macroState.isRecording = false

  for keyStr in keys:
    let keyComboOpt = stringToKeyCombo(keyStr)
    if keyComboOpt.isNone:
      state.macroState.isRecording = wasRecording
      state.macroState.playbackDepth -= 1
      return
        HandlerResult(kind: hrError, errorMessage: "Invalid key in macro: " & keyStr)

    let keyResult = manager.handleKeyCombo(editor, keyComboOpt.get)

    if keyResult.kind == hrHandled and keyResult.modeTransition.isSome:
      state.mode = keyResult.modeTransition.get

    if keyResult.kind == hrError or keyResult.kind == hrQuit:
      state.macroState.isRecording = wasRecording
      state.macroState.playbackDepth -= 1
      return keyResult

  state.macroState.isRecording = wasRecording
  state.macroState.playbackDepth -= 1
  editor.keyRouter.clearBuiltinSequence()
  HandlerResult(kind: hrHandled, modeTransition: none(EditorMode), statusMessage: "")
