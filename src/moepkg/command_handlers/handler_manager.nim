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
    command_registry, lsp_integration, logger, key_router, pending_input,
  ]
import ../types/editor_types
# The shared handler-module list lives in handler_modules (single source of
# truth, re-exported here). `mode_dispatchers` and `command_passthrough` are
# imported separately: the former imports handler_modules itself (so it can't
# be part of it without a cycle), the latter is an internal helper kept off the
# public surface.
import handler_modules, mode_dispatchers, command_passthrough

export handler_modules, mode_dispatchers

proc newHandlerManager*(
    motionController: MotionController,
    keyBindingRegistry: KeyBindingRegistry,
    commandLineParser: CommandLineParser,
    commandConfig: CommandConfig,
    commandRegistry: CommandRegistry,
    lsp: LspIntegration = nil,
): HandlerManager =
  ## Clipboard/SmoothScroll/Notification are read live from `state.config`
  ## through CommandContext getters, so newEditor no longer plumbs snapshots.
  let normalHandler =
    newNormalModeHandler(motionController, keyBindingRegistry, commandRegistry)
  let insertHandler =
    newInsertModeHandler(keyBindingRegistry, motionController, commandRegistry, lsp)
  let commandHandler =
    newCommandModeHandler(commandLineParser, commandConfig, commandRegistry)
  let visualHandler =
    newVisualModeHandler(keyBindingRegistry, commandRegistry, motionController)
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

proc hasPendingBuiltinInput*(editor: Editor): bool =
  ## True while any built-in multi-step input is still building. Callers use
  ## this to decide whether Ctrl-o insert-normal is safe to finalize.
  editor.state.pendingInput.isActive(editor.keyRouter.registry)

proc endInsertNormalSession(buffer: TextBuffer, state: EditorState) =
  ## Commit the pending Insert transaction (if any) and reset all insert-session
  ## tracking that carries over across a Ctrl-o boundary. Shared teardown so
  ## every insert-normal exit path clears the same set of fields.
  state.insertNormalMode = false
  if buffer.inTransaction:
    clearAutoIndentIfUnedited(buffer, state)
    discard buffer.commitTransaction()
  state.editState.insertModeStartPos = none(BufferPosition)
  state.editState.insertReplayCount = 0
  state.editState.insertReplayLineEntry = false
  state.editState.substituteContext = none(types.SubstituteContext)

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
    if not hasPendingBuiltinInput(editor) and not hasOverlay:
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
        endInsertNormalSession(buffer, state)
        let newMode = normalResult.modeTransition.get
        if newMode == EditorMode.Replace:
          discard buffer.beginTransaction("Replace mode edit")
        return normalResult

  if state.insertNormalMode and
      normalResult.kind notin {hrHandled, hrUnhandled, hrError, hrPlaybackMacro}:
    endInsertNormalSession(buffer, state)

  # hrPlaybackMacro defers the return-to-Insert finalization to the
  # nested-playback processor so it fires after the macro's own keys run
  # (an empty macro or one whose keys never satisfy the "clean command"
  # criteria would otherwise leave insert-normal state stuck).
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
          # Carry the [count]i/a/o/O replay request onto the Insert session.
          state.editState.insertReplayCount = r.insertReplayCount
          state.editState.insertReplayLineEntry = r.insertReplayLineEntry
      elif targetMode == EditorMode.Replace:
        # Reveal a collapsed fold at the cursor so Replace never overtypes text
        # hidden behind a fold marker (mirrors the Insert-mode entry behaviour).
        discard buffer.foldState.openFold(state.cursor.line)
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
    # Hand macro playback to the nested-playback processor (result_processor.nim)
    # so every key's side effects fire — the local playbackMacro loop used to
    # drop non-quit non-error kinds.
    return HandlerResult(
      kind: hrPlaybackMacro,
      playbackMacroKeys: r.macroKeys,
      playbackMacroCount: if r.macroCount > 0: r.macroCount else: 1,
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

proc handleKeyCombo*(
    manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Pure per-mode dispatcher. The runtime key-sequence mapping precheck lives
  ## in `runNestedKeyCombo` (result_processor.nim) so this proc can be reused
  ## verbatim by macro/mapping-RHS replay without re-entering the precheck.

  # Complete any active scroll animation on key input (instant jump to target)
  if e.state.windowDisplay.scrollAnimation.active:
    let (completed, cursorLine) =
      completeScrollAnimation(e.state.windowDisplay.scrollAnimation)
    if completed:
      e.state.cursor.line = cursorLine

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
