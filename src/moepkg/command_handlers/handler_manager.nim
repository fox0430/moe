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

import pkg/results

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
  ## True while any built-in multi-step input is still building.
  editor.state.pendingInput.isActive(editor.keyRouter.registry)

proc cancelPendingCommand*(editor: Editor): bool =
  ## End the command being built (an operator, a count, a register), as
  ## Escape and Ctrl-C do in Normal mode. True when there was one.
  result = editor.state.pendingInput.cancelAll(editor.keyRouter.registry)
  if result:
    editor.state.statusMessage = ""

proc applyNormalModeResult(
    manager: HandlerManager, editor: Editor, r: NormalModeResult
): HandlerResult =
  ## Turn a Normal mode command's result into a HandlerResult, starting the
  ## Insert or Replace session the command enters.
  let buffer = editor.activeBuffer
  let state = editor.state

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
        let transactionResult = beginInsertModeSession(
          buffer, state, r.insertReplayCount, r.insertReplayLineEntry
        )
        if transactionResult.isErr:
          return HandlerResult(
            kind: hrError,
            errorMessage: "Failed to begin transaction: " & transactionResult.error,
          )
      elif targetMode == EditorMode.Replace:
        # As for Insert, a transaction a failed commit left open carries on.
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
    # An error ends the command, so nothing it was building (an operator, a
    # count, a register) carries over to the next key.
    state.pendingInput.cancelAll(editor.keyRouter.registry)
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

proc handleNormalMode*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Handle Normal mode input
  let buffer = editor.activeBuffer
  let state = editor.state

  # Escape ends the command being built. Typed and replayed keys both come
  # here, after the router has played any mapping keys it held, so a macro or
  # mapping cancels as the keys typed would. With nothing to cancel, a second
  # Escape in a row hides search highlighting.
  if keyCombo.isSpecial and keyCombo.special == skEscape:
    if editor.cancelPendingCommand() or state.resumesInsert:
      state.lastKeyWasEscape = false
    elif state.lastKeyWasEscape:
      state.input.search.hlsearchTempDisabled = true
      state.lastKeyWasEscape = false
    else:
      state.lastKeyWasEscape = true
    return HandlerResult(kind: hrHandled)
  state.lastKeyWasEscape = false

  let r =
    manager.normalHandler.handleNormalModeKey(buffer, state, editor.viewport, keyCombo)
  manager.applyNormalModeResult(editor, r)

proc keepCursorLineUnfolded(e: Editor, res: HandlerResult) =
  ## Typing lands on the cursor line, so Insert and Replace never leave it
  ## folded. Held after dispatch to cover both mode entry (several handlers, some
  ## via a transition) and an edit that moves the cursor into a closed fold.
  let effectiveMode =
    if res.getModeTransition().isSome:
      res.getModeTransition().get
    else:
      e.state.mode
  # Only for a dispatch that did something: a rejected key must not open a fold.
  if res.kind notin {hrError, hrUnhandled} and
      effectiveMode in {EditorMode.Insert, EditorMode.Replace} and e.activeBuffer != nil:
    discard e.activeBuffer.foldState.openFoldsInRange(
      e.state.cursor.line, e.state.cursor.line
    )

proc completeScrollAnimation*(e: Editor) =
  ## Jump an active scroll animation to its target, so a replayed key runs
  ## where the scroll ends. A typed key stops it instead (`prepareForInput`).
  if e.state.windowDisplay.scrollAnimation.active:
    let (completed, cursorLine) =
      completeScrollAnimation(e.state.windowDisplay.scrollAnimation)
    if completed:
      e.state.activeWindow.scrollCursor(cursorLine)

proc handleKeyCombo*(
    manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## Pure per-mode dispatcher. The runtime key-sequence mapping precheck and
  ## the scroll animation jump live in `runNestedKeyCombo` (result_processor.nim)
  ## so this proc can be reused verbatim by macro/mapping-RHS replay without
  ## re-entering the precheck.
  let res =
    case e.state.mode
    of EditorMode.Normal:
      manager.handleNormalMode(e, keyCombo)
    of EditorMode.Insert:
      manager.handleInsertMode(e, keyCombo)
    of EditorMode.Visual, EditorMode.VisualBlock, EditorMode.VisualLine:
      manager.handleVisualMode(e, keyCombo)
    of EditorMode.Replace:
      manager.handleReplaceMode(e, keyCombo)
    else:
      manager.dispatchSubStateMode(e, keyCombo)

  e.keepCursorLineUnfolded(res)
  return res

proc runInsertCommand*(
    manager: HandlerManager, e: Editor, append: bool
): HandlerResult =
  ## The `i` command, or `a` if `append`, whatever keys they are bound to. Vim
  ## resumes Insert after Ctrl-o by queueing `i` (unmapped), past the end of
  ## the line if need be, which is `a` on its last character.
  let r = manager.normalHandler.handleInsertModeEntry(
    e.activeBuffer, e.state, if append: "append" else: "insert"
  )
  result = manager.applyNormalModeResult(e, r)
  e.keepCursorLineUnfolded(result)
