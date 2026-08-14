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

## HandlerResult processor: applies editor-level side effects from a handler
## result. A pure dispatch delegating each kind group to a per-feature ops
## module; trailing overlay/mode transitions live in `processResultEpilogue`.

import std/[options, os, monotimes, tables, unicode]

import pkg/[results, chronos]

import
  ../[
    editor, modes, buffer, logger, types, filer, filetree, lsp_service, primitives,
    syntax_checker, cursor_util, quick_run_utils, command_completion, key_bindings,
    key_router, lsp_integration,
  ]
import
  backup_ops, config_ops, debug_ops, editor_ops, file_ops, handler_result,
  handler_manager, list_ops, lsp_ops, misc_ops, option_ops, viewer_ops, window_ops

type
  ReplayOutcome* = enum
    ## Outcome from a single replayed key, after full processResult side effects.
    roContinue
    roQuit ## hrQuit / hrCquit — main loop terminates
    roAbort ## hrError — statusMessage already set; loop stops, app continues

  OverlayPlaybackHook* = proc(e: Editor, keyCombo: KeyCombo): Option[bool] {.closure.}
    ## Playback overlay dispatch. `none` = no overlay, fall through; `some(true)`
    ## = handled, continue; `some(false)` = handled, requested app exit. Wired
    ## from handler.nim to avoid an import cycle (overlay handlers import here).

const ModesNeedingContext = {
  EditorMode.References, EditorMode.DocumentSymbol, EditorMode.CallHierarchy,
  EditorMode.DiffViewer,
}
  ## Modes that need a payload (an LSP response, a file pair); `mode_switch`
  ## to one of these is rejected rather than entered with no listing.

var overlayPlaybackHook*: OverlayPlaybackHook = nil

proc executeCommandOverlay*(e: Editor, commandText: string): bool

proc processResultEpilogue(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool

proc modeSwitchEntry(mode: EditorMode): Option[HandlerResult] =
  ## Entry result for `mode_switch`-able modes that build a listing on entry;
  ## flipping `EditorWindow.mode` alone leaves a dispatcher with no state.
  case mode
  of EditorMode.Filer:
    some(HandlerResult(kind: hrEnterFiler, enterFilerPath: none(string)))
  of EditorMode.BufferManager:
    some(HandlerResult(kind: hrEnterBufferManager))
  of EditorMode.BookmarkManager:
    some(HandlerResult(kind: hrEnterBookmarkManager))
  of EditorMode.Help:
    some(HandlerResult(kind: hrEnterHelpViewer))
  of EditorMode.LogViewer:
    some(HandlerResult(kind: hrEnterLogViewer))
  of EditorMode.BackupManager:
    some(HandlerResult(kind: hrEnterBackupManager))
  of EditorMode.RecentFile:
    some(HandlerResult(kind: hrRecentFile))
  of EditorMode.Debug:
    some(HandlerResult(kind: hrDebug))
  of EditorMode.Config:
    some(HandlerResult(kind: hrConfig))
  of EditorMode.Terminal:
    some(HandlerResult(kind: hrEnterTerminal, enterTerminalCommand: ""))
  of EditorMode.FileTree:
    some(HandlerResult(kind: hrEnterFileTree, enterFileTreePath: none(string)))
  else:
    none(HandlerResult)

proc processResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Apply the editor-level side effects implied by `r`. Returns true to
  ## continue the main loop, false to quit.

  # Process the result
  case r.kind
  of hrQuit:
    return false # Signal app should quit
  of hrCquit:
    e.state.exitCode = 1
    return false # Signal app should quit with non-zero exit code
  of hrSaveAndQuit:
    return e.processSaveAndQuitResult(r)
  of hrSaveAllAndQuit:
    return e.processSaveAllAndQuitResult(r)
  of hrGotoLine:
    e.processGotoLineResult(r, activeBuffer)
    return true # Skip the epilogue's status-line overwrite, like ops-moved kinds
  of hrJumpToBuffer, hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast, hrBuffer,
      hrCloseWindow, hrNextWindow, hrPrevWindow, hrIncreaseWindowHeight,
      hrDecreaseWindowHeight, hrIncreaseWindowWidth, hrDecreaseWindowWidth,
      hrEqualizeWindows, hrSwapWindow, hrOnlyWindow, hrBufferDelete, hrTerminalQuit,
      hrFileTreeQuit:
    return e.processWindowResult(r, activeBuffer)
  of hrFilerOpenFile, hrFilerOpenFileVSplit, hrFilerOpenFileHSplit, hrFileTreeOpenFile,
      hrFilerDeleteFile, hrOpenUri, hrQuickRun, hrVSplit, hrHSplit, hrNew, hrVnew,
      hrEdit, hrEnew:
    return e.processFileResult(r, activeBuffer)
  of hrFilerShowInfo:
    # Show file information in status line
    e.state.statusMessage = r.filerFileInfo
    return true
  of hrLogViewerQuit, hrLogViewerRefresh, hrHelpViewerQuit, hrReferencesQuit,
      hrReferencesJumpTo, hrDocumentSymbolQuit, hrDocumentSymbolJumpTo,
      hrCallHierarchyQuit, hrCallHierarchyJumpTo, hrCallHierarchyRequestIncoming,
      hrCallHierarchyRequestOutgoing, hrBufferManagerQuit, hrBufferManagerSelectBuffer,
      hrBufferManagerDeleteBuffer, hrBookmarkManagerQuit, hrBookmarkManagerJump,
      hrBookmarkManagerDelete, hrBackupManagerQuit, hrDiffViewerQuit, hrFilerQuit,
      hrLspLog:
    return e.processViewerResult(r)
  of hrConfigQuit, hrConfigSaveConfig, hrPutConfigFile:
    return e.processConfigResult(r)
  of hrBackupManagerRefresh, hrBackupManagerRestore, hrBackupManagerDelete,
      hrBackupManagerOpenDiff:
    return e.processBackupResult(r)
  of hrLspGotoDefinition, hrLspGotoDeclaration, hrLspFindReferences,
      hrLspDocumentSymbol, hrLspCodeLensExecute, hrLspCallHierarchyIncoming,
      hrLspCallHierarchyOutgoing, hrLspTypeDefinition, hrLspImplementation, hrLspHover,
      hrLspRename, hrLspSelectionRange, hrLspDocumentLink, hrLspFormat, hrLspRestart,
      hrLspFold, hrLspExecuteCommand:
    return e.processLspResult(r, activeBuffer)
  of hrHandled, hrUnhandled:
    discard # Fall through to post-processing
  of hrError:
    e.state.statusMessage = r.errorMessage
  of hrEnterFiler, hrEnterFileTree, hrRecentFile, hrEnterLogViewer, hrEnterHelpViewer,
      hrEnterBufferManager, hrEnterBookmarkManager, hrEnterBackupManager,
      hrEnterTerminal:
    return e.processViewerResult(r)
  of hrExecCommand:
    # @: - repeat last Command mode command via the shared overlay wrapper.
    let count = r.execCommandCount
    let commandText = ":" & r.execCommandText
    for i in 0 ..< count:
      if not e.executeCommandOverlay(commandText):
        return false
  of hrSave:
    e.processSaveResult(r, activeBuffer)
    return true # Unified: ops-moved kinds keep their own status message
  of hrSaveAll:
    e.processSaveAllResult(r)
    return true # Unified: ops-moved kinds keep their own status message
  of hrSetBoolOption, hrSetIntOption, hrSetFloatOption:
    return e.processSetOptionResult(r)
  of hrClearSearchHighlight, hrStripWhitespace, hrShellCommand, hrBackground, hrMan,
      hrSubstitute, hrDeleteLines, hrBuild:
    return e.processMiscResult(r, activeBuffer)
  of hrDebug:
    return e.processDebugResult(r)
  of hrConfig:
    return e.processConfigResult(r)
  of hrTheme:
    return e.processMiscResult(r, activeBuffer)
  of hrJumpList:
    return e.processJumpResult(r)
  of hrChanges:
    return e.processChangeResult(r)
  of hrConflictNext:
    return e.processConflictJumpResult(r)
  of hrConflictPrev:
    return e.processConflictJumpResult(r)
  of hrDebugViewerQuit:
    return e.processDebugResult(r)
  of hrRecentFileOpenFile, hrRecentFileQuit:
    logWarn(
      "result_processor",
      "unreachable kind reached processResult: " & $r.kind &
        " (handled by handler.handleRecentFileModeKeyCombo)",
    )
    discard # Handled by handler.handleRecentFileModeKeyCombo; unreachable here.
  of hrMapAdd, hrMapRemove, hrMapClear, hrMapList:
    logWarn(
      "result_processor",
      "unreachable kind reached processResult: " & $r.kind &
        " (folded by handleCommandMode)",
    )
    discard # Folded to hrHandled/hrError by handleCommandMode; unreachable here.
  of hrPlaybackMacro:
    logWarn(
      "result_processor",
      "unreachable kind reached processResult: hrPlaybackMacro" &
        " (intercepted by processReplayedResult)",
    )
    discard # Consumed by processReplayedResult; only reaches here defensively.

  return e.processResultEpilogue(r, activeBuffer)

proc processResultEpilogue(
    e: Editor, r: HandlerResult, activeBuffer: TextBuffer
): bool =
  ## Post-processing for falling-through arms (hrHandled / hrUnhandled /
  ## hrError / hrExecCommand): overlay and mode transitions, viewer buffer
  ## regeneration, status messages. Returns true to continue the main loop.
  #
  # Handle overlay transitions
  let overlayTransition = r.getOverlayTransition()
  if overlayTransition.isSome:
    case overlayTransition.get
    of okCommand:
      e.state.enterCommandOverlay()
    of okSearch:
      # Search mode needs direction from search state (already set by handler)
      e.state.enterSearchOverlay(e.state.input.search.direction)
    of okRename:
      e.state.enterRenameOverlay(
        e.state.renameState.originalWord, e.state.renameState.cursorLine,
        e.state.renameState.cursorColumn,
      )

  # Handle mode transitions
  let modeTransition = r.getModeTransition()
  if modeTransition.isSome:
    let oldMode = e.state.mode
    let newMode = modeTransition.get

    # Replay a `mode_switch`-named viewer's real entry result so it never
    # goes live without its state — but only if not already live (Escape back
    # into a shown viewer just flips the mode). viewerEntry is the source of
    # truth; modeState.kind could have been reset behind its back.
    let alreadyLive =
      e.activeWindow.viewerEntry.isSome and
      e.activeWindow.viewerEntry.get.mode == newMode

    if not alreadyLive and newMode in ModesNeedingContext:
      e.state.statusMessage = "Cannot switch to " & $newMode & " mode directly"
      return true

    e.state.previousMode = oldMode

    # FileTree toggles, so replaying its entry would close the open sidebar;
    # focus it instead.
    let focused = newMode == EditorMode.FileTree and e.focusFileTreeWindow()

    let entry =
      if alreadyLive or focused:
        none(HandlerResult)
      else:
        modeSwitchEntry(newMode)
    if entry.isSome:
      if not e.processResult(entry.get, activeBuffer):
        return false
    elif not focused:
      e.setMode(newMode)

      # Adjust cursor when transitioning from Insert to Normal mode
      # Skip cursor adjustment for insert-normal mode (Ctrl-o) since we'll return to Insert
      if oldMode == EditorMode.Insert and newMode == EditorMode.Normal and
          not e.state.insertNormalMode:
        let
          lineCharLen = activeBuffer.getLine(e.activeWindow.cursor.line).charLen
          oldColumn = e.activeWindow.cursor.column

        logDebug(
          "handler",
          "Insert→Normal transition: line=" & $e.activeWindow.cursor.line &
            " oldColumn=" & $oldColumn & " lineCharLen=" & $lineCharLen,
        )

        adjustCursorAfterInsertExit(e.activeWindow.cursor, lineCharLen)

        if oldColumn != e.activeWindow.cursor.column:
          logDebug(
            "handler",
            "Cursor adjusted: " & $oldColumn & " → " & $e.activeWindow.cursor.column,
          )

  # Filer buffer regeneration after state changes (e.g. enterDirectory, toggleHidden)
  if e.state.mode == EditorMode.Filer:
    let filerWin = e.activeWindow
    if filerWin.modeState.kind == mskFiler and
        filerWin.modeState.filer.needsBufferRefresh:
      filerWin.buffer =
        filerWin.modeState.filer.createFilerTextBuffer(e.config.filer.showIcons)
      filerWin.modeState.filer.needsBufferRefresh = false

  # FileTree buffer regeneration after state changes (check all windows since
  # the file tree sidebar may not be the active window)
  for win in e.windowManager.windows:
    if win.mode == EditorMode.FileTree and win.modeState.kind == mskFileTree and
        win.modeState.fileTree.needsBufferRefresh:
      win.buffer =
        win.modeState.fileTree.createFileTreeTextBuffer(e.config.filer.showIcons)
      win.modeState.fileTree.needsBufferRefresh = false

  # Set status message if any
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.statusMessage = statusMsg

  # Show syntax check message for current cursor line (if no other status message)
  if statusMsg.len == 0 and e.state.syntaxCheckResults.errors.len > 0:
    let activeBuf = e.activeBuffer()
    let activePath = if activeBuf.filePath.isSome: activeBuf.filePath.get else: ""
    if activePath.len > 0 and activePath == e.state.syntaxCheckResults.path:
      let syntaxMsg =
        formattedMessage(e.state.syntaxCheckResults.errors, e.activeWindow.cursor.line)
      if syntaxMsg.isSome:
        e.state.statusMessage = syntaxMsg.get

  return true # Continue running

const MaxMacroRecursionDepth* = 100
  ## Macro recursion depth guard (@a inside @a...) before abort.

const MaxMapRecursionDepth = 50
  ## `:map` (noremap=false) expansion depth guard. Kept below
  ## MaxMacroRecursionDepth so a cyclic mapping reports "recursive mapping"
  ## before the macro depth guard fires.

proc playbackMacroImpl(e: Editor, keys: seq[string]): ReplayOutcome
proc playbackKeyCombosImpl(e: Editor, combos: seq[KeyCombo]): ReplayOutcome

proc runNestedKeyCombo*(
  manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): ReplayOutcome

proc processReplayedResult*(
    e: Editor, r: HandlerResult, activeBuffer: TextBuffer
): ReplayOutcome =
  ## Mini processor for keys fired from a nested replay context (macro,
  ## mapping RHS, timeout batch). Applies full side effects via
  ## `processResult` — no kind is silently dropped — and returns whether the
  ## loop should keep going. `hrPlaybackMacro` is intercepted here and drives
  ## the nested `playbackMacroImpl` loop count times.
  if r.kind == hrPlaybackMacro:
    for _ in 0 ..< r.playbackMacroCount:
      let outcome = playbackMacroImpl(e, r.playbackMacroKeys)
      if outcome != roContinue:
        return outcome
    # Finalize insert-normal after the macro. applyNormalModePostProcessing
    # skips hrPlaybackMacro's clean-up branch so the OUTER insertNormalMode
    # survives the propagation; if the macro's own keys never cleared it
    # (empty macro, all keys stayed pending), fold it back into Insert here.
    let state = e.state
    if state.insertNormalMode and state.mode == EditorMode.Normal and
        not hasPendingBuiltinInput(e):
      state.insertNormalMode = false
      e.setMode(EditorMode.Insert)
    return roContinue
  let shouldContinue = processResult(e, r, activeBuffer)
  if r.kind == hrError:
    return roAbort
  if not shouldContinue:
    return roQuit
  roContinue

template withPlaybackGuard*(e: Editor, body: untyped): ReplayOutcome =
  ## Shared depth guard + isRecording suspension for macro / runtime-mapping
  ## replay loops. `body` must assign to `outcome`.
  ## Exposed for tests that fire the exception path with a raising body.
  block:
    let state = e.state
    if state.pendingInput.macroState.playbackDepth >= MaxMacroRecursionDepth:
      e.state.statusMessage =
        "Macro recursion limit exceeded (max " & $MaxMacroRecursionDepth & ")"
      roAbort
    else:
      state.pendingInput.macroState.playbackDepth += 1
      let wasRecording = state.pendingInput.macroState.isRecording
      state.pendingInput.macroState.isRecording = false
      var outcome {.inject.} = roContinue
      try:
        body
      finally:
        # Exception safety: always restore playback state, even on failure.
        state.pendingInput.macroState.isRecording = wasRecording
        state.pendingInput.macroState.playbackDepth -= 1
      outcome

proc playbackKeyCombosImpl(e: Editor, combos: seq[KeyCombo]): ReplayOutcome =
  ## Iterate `combos` through `runNestedKeyCombo` — no per-key parse. Used by
  ## runtime key-sequence mappings whose RHS is pre-parsed at registration.
  withPlaybackGuard(e):
    for k in combos:
      outcome = runNestedKeyCombo(e.handlerManager, e, k)
      if outcome != roContinue:
        break

proc playbackMacroImpl(e: Editor, keys: seq[string]): ReplayOutcome =
  ## Iterate user-recorded macro `keys` (register storage is seq[string]).
  ## Aborts on the first `stringToKeyCombo` failure but keeps executing the
  ## good prefix (matches pre-refactor behaviour).
  withPlaybackGuard(e):
    for keyStr in keys:
      let keyComboOpt = stringToKeyCombo(keyStr)
      if keyComboOpt.isNone:
        e.state.statusMessage = "Invalid key in macro: " & keyStr
        outcome = roAbort
        break
      outcome = runNestedKeyCombo(e.handlerManager, e, keyComboOpt.get)
      if outcome != roContinue:
        break

proc replayRuntimeKeySequence*(
    manager: HandlerManager, editor: Editor, targetKeys: seq[KeyCombo], noremap: bool
): ReplayOutcome =
  ## Replay the RHS of a fired runtime key-sequence mapping. `:noremap` runs
  ## verbatim under `withReplay` (isReplayingMapping suppresses re-expansion);
  ## `:map` runs without withReplay so each replayed key re-enters the
  ## precheck, bounded by `mapExpandDepth` / `MaxMapRecursionDepth`.
  if noremap:
    var outcome = roContinue
    editor.keyRouter.withReplay:
      outcome = playbackKeyCombosImpl(editor, targetKeys)
    return outcome

  if editor.keyRouter.mapExpandDepth >= MaxMapRecursionDepth:
    editor.state.statusMessage = "recursive mapping (max " & $MaxMapRecursionDepth & ")"
    return roAbort
  editor.keyRouter.mapExpandDepth += 1
  try:
    result = playbackKeyCombosImpl(editor, targetKeys)
  finally:
    editor.keyRouter.mapExpandDepth -= 1

proc checkRuntimeKeySeqMapping*(
    manager: HandlerManager, editor: Editor, keyCombo: KeyCombo
): Option[ReplayOutcome] =
  ## Ask the KeyRouter whether `keyCombo` is part of a runtime mapping. Returns
  ## `none` to let the caller fall through to built-in resolution, or `some`
  ## outcome when the mapping fired (or is still building).
  ##
  ## Flush semantics: rrUnhandledBatch replays accumulated keys *except* the
  ## current one; the caller re-processes the current key normally. The
  ## Command overlay path lives in `command_mode_handler.handleCommandModeKeyCombo`.
  let state = editor.state
  let route = editor.keyRouter.feedKey(state.mode, keyCombo)
  case route.kind
  of rrUnhandled, rrCancelled, rrCommand:
    # rrCommand is produced only by resolveBuiltin (Normal dispatcher), never by
    # feedKey; listed for exhaustiveness. Fall through to built-in resolution.
    return none(ReplayOutcome)
  of rrExecuteRuntimeCommand:
    let cmdResult = manager.executeCommandDirect(route.commandName)
    if cmdResult.isSome:
      return some(processReplayedResult(editor, cmdResult.get, editor.activeBuffer))
    return none(ReplayOutcome)
  of rrExecuteRuntimeKeySequence:
    return
      some(replayRuntimeKeySequence(manager, editor, route.targetKeys, route.noremap))
  of rrWaiting:
    return some(roContinue)
  of rrUnhandledBatch:
    let keysToFlush = route.keys[0 ..< route.keys.len - 1]
    var outcome = roContinue
    editor.keyRouter.withReplay:
      for k in keysToFlush:
        outcome = runNestedKeyCombo(manager, editor, k)
        if outcome != roContinue:
          break
    if outcome != roContinue:
      return some(outcome)
    return none(ReplayOutcome)

proc runNestedKeyCombo*(
    manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): ReplayOutcome =
  ## Single entry point that fuses precheck (runtime key-sequence mapping) with
  ## dispatch and full processResult side effects. Both the top-level event
  ## loop and nested-playback loops (macro, mapping RHS, timeout batch) call
  ## this so every kind's side effect fires exactly once.
  # When an overlay is active the live loop routes through the overlay handler;
  # replay must do the same or recorded overlay keys hit the base-mode handler.
  if not overlayPlaybackHook.isNil:
    let overlayResult = overlayPlaybackHook(e, keyCombo)
    if overlayResult.isSome:
      return if overlayResult.get: roContinue else: roQuit
  if not manager.keyBindingRegistry.isReplayingMapping:
    let expand = checkRuntimeKeySeqMapping(manager, e, keyCombo)
    if expand.isSome:
      return expand.get
  let r = manager.handleKeyCombo(e, keyCombo)
  processReplayedResult(e, r, e.activeBuffer)

proc outcomeToHandlerResult(e: Editor, outcome: ReplayOutcome): HandlerResult =
  ## Fold a ReplayOutcome into the HandlerResult shape test-facing wrappers
  ## return. `roAbort` pulls the diagnostic from `state.statusMessage`, which
  ## the abort site (`playbackMacroImpl`, `replayRuntimeKeySequence`, or
  ## `processResult`'s hrError arm) has already populated.
  case outcome
  of roContinue:
    HandlerResult(kind: hrHandled, modeTransition: none(EditorMode), statusMessage: "")
  of roQuit:
    HandlerResult(kind: hrQuit)
  of roAbort:
    HandlerResult(kind: hrError, errorMessage: e.state.statusMessage)

proc playbackMacro*(editor: Editor, keys: seq[string]): HandlerResult =
  ## Test-facing wrapper. Real callers go through `hrPlaybackMacro` +
  ## `processReplayedResult`; this preserves a HandlerResult return for
  ## tests that inspect it directly. Side effects are applied via
  ## `playbackMacroImpl`; the returned HandlerResult is a status signal.
  outcomeToHandlerResult(editor, playbackMacroImpl(editor, keys))

proc playbackKeyCombos*(editor: Editor, combos: seq[KeyCombo]): HandlerResult =
  ## Test-facing wrapper for the pre-parsed variant. Used by tests that
  ## execute a `RuntimeKeyMapping.targetKeys` (now seq[KeyCombo]) directly.
  outcomeToHandlerResult(editor, playbackKeyCombosImpl(editor, combos))

proc runKeyCombo*(
    manager: HandlerManager, e: Editor, keyCombo: KeyCombo
): HandlerResult =
  ## HandlerResult-returning form of `runNestedKeyCombo`, for tests that
  ## inspect kind/errorMessage. Full processResult side effects fire on every
  ## path (precheck, direct dispatch, hrPlaybackMacro expansion) so the
  ## observable state after this call matches production `handleEvent`. The
  ## returned HandlerResult is a status signal (hrHandled/hrQuit/hrError),
  ## not the raw dispatched result — inspect `state.mode`, `state.overlay`,
  ## and other mutations directly.
  outcomeToHandlerResult(e, runNestedKeyCombo(manager, e, keyCombo))

proc tryHandleQuickRunRequest(e: Editor, activeBuffer: TextBuffer): bool =
  ## Consume `state.requestQuickRun` (set by buffer-mode key handlers) and
  ## fire QuickRun via pending state. Returns true when a QuickRun request
  ## was consumed; callers should skip further hr-teardown in that case.
  if not e.state.requestQuickRun:
    return false
  e.state.requestQuickRun = false
  let prepareResult = prepareQuickRun(activeBuffer, e.config)
  if prepareResult.isErr:
    e.state.statusMessage = "QuickRun error: " & prepareResult.error
    logError("handler", "QuickRun prepare failed: " & prepareResult.error)
  else:
    let prepared = prepareResult.get
    e.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      quickRun: (
        cmd: prepared.command.cmd,
        args: prepared.command.args,
        filePath: prepared.filePath,
        isTempFile: prepared.isTempFile,
      ),
    )
    if e.config.notification.screenNotifications and
        e.config.notification.quickRunScreenNotify:
      e.state.statusMessage = quickRunStartupMessage(prepared.filePath)
  e.state.exitOverlay()
  e.setMode(EditorMode.Normal)
  return true

proc handleInsertNormalReturn(e: Editor) =
  ## After a Command overlay completes, if we were in insert-normal mode
  ## (Ctrl-o), return to Insert (for :w/:set) or commit the Insert transaction
  ## (when the command switched to a non-Normal/Insert mode).
  if not e.state.insertNormalMode:
    return
  if e.state.mode == EditorMode.Normal:
    e.state.insertNormalMode = false
    e.setMode(EditorMode.Insert)
  elif e.state.mode != EditorMode.Insert:
    e.state.insertNormalMode = false
    let activeBuffer = e.activeBuffer()
    if activeBuffer.inTransaction:
      clearAutoIndentIfUnedited(activeBuffer, e.state)
      let commitResult = activeBuffer.commitTransaction()
      if commitResult.isErr:
        logError "result_processor",
          "Failed to commit transaction: " & commitResult.error
        e.state.statusMessage = "Failed to commit transaction: " & commitResult.error
    e.state.editState.insertModeStartPos = none(BufferPosition)
    e.state.editState.substituteContext = none(types.SubstituteContext)

proc executeCommandOverlay*(e: Editor, commandText: string): bool =
  ## Full lifecycle of a Command-overlay Enter: pre-teardown, dispatch,
  ## side effects via processResult, teardown driven by `r.group`, then
  ## Insert-Normal recovery. Returns false when the caller should stop the
  ## main loop (app quit).
  # 1. pre-teardown (kind-independent)
  e.state.commandCompletionManager.cancelCompletion()
  if e.state.ui.substitutePreview.isActive:
    e.cancelSubstitutePreview()

  # 2. dispatch
  let activeBuffer = e.activeBuffer()
  let isShared = e.isBufferShared(activeBuffer)
  var otherModifiedCount = 0
  for buf in e.buffers:
    if buf != activeBuffer and buf.isModified:
      otherModifiedCount.inc
  let r = e.handlerManager.handleCommandMode(
    activeBuffer, commandText, isShared, e.activeWindow.cursor.line, otherModifiedCount
  )
  if commandText.len > 1:
    e.addCommandToHistory(commandText[1 ..^ 1])

  # 3. requestQuickRun poll (set independently of r.kind by buffer-mode keys)
  if e.tryHandleQuickRunRequest(activeBuffer):
    e.handleInsertNormalReturn()
    return true

  # 4. side effects
  let shouldContinue = e.processResult(r, activeBuffer)
  if not shouldContinue:
    return false

  # 5. teardown
  case r.group
  of hrgAppExit:
    return false # unreachable — processResult would have returned false
  of hrgExitToNormal:
    e.state.exitOverlay()
    e.setMode(EditorMode.Normal)
  of hrgExitToNewMode:
    e.state.exitOverlay()
  of hrgExitAndResync:
    e.state.exitOverlay()
    e.setMode(e.state.mode)
  of hrgHandledGeneric:
    e.state.exitOverlay()
    let t = r.getModeTransition()
    # `ModesNeedingContext` targets were refused by processResult; re-applying
    # the transition here would put the window in that mode with no state.
    if t.isSome and t.get notin ModesNeedingContext:
      e.setMode(t.get)
    else:
      e.setMode(e.state.mode)

  # 6. status message from HandlerResult payload
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.statusMessage = statusMsg

  # 7. Insert-Normal recovery (Ctrl-o)
  e.handleInsertNormalReturn()
  return true
