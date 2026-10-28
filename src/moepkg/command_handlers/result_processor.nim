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
    syntax_checker, quick_run_utils, command_completion, key_bindings, key_router,
    lsp_integration, command_registry, command_line, editor_window_state, pending_input,
    macro_recording, insert_record, wanted_column,
  ]
import
  backup_ops, config_ops, debug_ops, editor_ops, file_ops, handler_result,
  handler_manager, list_ops, lsp_ops, misc_ops, option_ops, recovery_ops, viewer_ops,
  window_ops

type
  ReplayOutcome* = enum
    ## Outcome from a single replayed key, after full processResult side effects.
    roContinue
    roQuit ## hrQuit / hrCquit — main loop terminates
    roAbort ## Error or queued host result — loop stops, app continues

  LayerHook* = proc(e: Editor, keyCombo: KeyCombo): Option[ReplayOutcome] {.closure.}
    ## A layer a key meets on its way to the mode handlers. `none` = it does
    ## not take the key; `some` = it took it, with its outcome. Wired from
    ## handler.nim to avoid an import cycle (the layers' handlers import here).

const ModesNeedingContext = {
  EditorMode.References, EditorMode.DocumentSymbol, EditorMode.CallHierarchy,
  EditorMode.DiffViewer,
}
  ## Modes that need a payload (an LSP response, a file pair); `mode_switch`
  ## to one of these is rejected rather than entered with no listing.

var promptLayerHook*: LayerHook = nil
  ## The LSP popups, which read a key before the mappings.
var frontLayerHook*: LayerHook = nil
  ## The layers in front of the mode handlers that run a key as it is: the
  ## command line, Search, Rename, Debug, a viewer's Ctrl-W and Recent File.

proc executeCommandOverlay*(e: Editor, commandText: string): ReplayOutcome

proc processResultEpilogue(
  e: Editor, r: HandlerResult, activeBuffer: TextBuffer, hostHandled: var bool
): bool

proc processResultWithHost(
  e: Editor, r: HandlerResult, activeBuffer: TextBuffer, hostHandled: var bool
): bool

proc processResult*(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Apply a result unless the host takes ownership of it. Host-handled results
  ## keep the editor running and skip Moe's effects and mode transitions.
  var hostHandled: bool
  e.processResultWithHost(r, activeBuffer, hostHandled)

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
  of EditorMode.RecoveryManager:
    some(HandlerResult(kind: hrEnterRecoveryManager))
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

proc processHistoryResult(e: Editor, r: HandlerResult, activeBuffer: TextBuffer): bool =
  ## Execute undo/redo at a committed Insert boundary. Buffer history rejects
  ## open transactions, so commands such as forced-Insert `Ctrl-o :undo` first
  ## turn the current typing group into an ordinary undo entry.
  let resumeInsert = e.state.mode == EditorMode.Insert

  var boundaryResult = Result[void, string].ok()
  if activeBuffer.inTransaction:
    boundaryResult =
      if e.state.editState.visualBlockInsertContext.isSome:
        let finalizeResult = finalizeInsertExit(
          activeBuffer, e.state, if resumeInsert: bieTyping else: bieLeave
        )
        if finalizeResult.isErr:
          Result[void, string].err(finalizeResult.error)
        else:
          Result[void, string].ok()
      else:
        commitInsertModeBoundary(activeBuffer, e.state)

  if boundaryResult.isErr:
    e.state.statusMessage = boundaryResult.error
  else:
    let ctx = CommandContext(
      buffer: activeBuffer,
      state: e.state,
      viewport: e.viewport,
      motionController: e.motionController,
      keyBindingRegistry: e.keyBindingRegistry,
    )
    let commandId =
      if r.kind == hrUndo:
        builtin(bcEditUndo)
      else:
        builtin(bcEditRedo)
    let historyResult = e.commandRegistry.execute(ctx, commandId)
    if historyResult.isErr:
      e.state.statusMessage = historyResult.error

  if resumeInsert and not activeBuffer.readOnly and not activeBuffer.inTransaction:
    let beginResult = beginInsertModeSession(activeBuffer, e.state)
    if beginResult.isErr:
      e.state.statusMessage = "Failed to begin transaction: " & beginResult.error

  true

proc processResultWithHost(
    e: Editor, r: HandlerResult, activeBuffer: TextBuffer, hostHandled: var bool
): bool =
  ## Apply the editor-level side effects implied by `r`. Returns true to
  ## continue the main loop, false to quit.

  if e.interceptHostResult(r):
    hostHandled = true
    return true

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
      hrCloseWindow, hrNextWindow, hrPrevWindow, hrMoveWindowLeft, hrMoveWindowDown,
      hrMoveWindowUp, hrMoveWindowRight, hrMaximizeWindowHeight, hrIncreaseWindowHeight,
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
      hrBookmarkManagerDelete, hrBackupManagerQuit, hrRecoveryManagerQuit,
      hrDiffViewerQuit, hrDiffViewerToggleView, hrDiffViewerToggleWord, hrFilerQuit,
      hrLspLog:
    return e.processViewerResult(r)
  of hrConfigQuit, hrConfigSaveConfig, hrPutConfigFile:
    return e.processConfigResult(r)
  of hrBackupManagerRefresh, hrBackupManagerRestore, hrBackupManagerDelete,
      hrBackupManagerOpenDiff:
    return e.processBackupResult(r)
  of hrRecoveryManagerRefresh, hrRecoveryManagerRestore,
      hrRecoveryManagerToggleReviewed, hrRecoveryManagerDiscard:
    return e.processRecoveryResult(r)
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
      hrEnterRecoveryManager, hrEnterTerminal:
    return e.processViewerResult(r)
  of hrSave:
    e.processSaveResult(r, activeBuffer)
    return true # Unified: ops-moved kinds keep their own status message
  of hrSaveAll:
    e.processSaveAllResult(r)
    return true # Unified: ops-moved kinds keep their own status message
  of hrSetBoolOption, hrSetIntOption, hrSetFloatOption:
    return e.processSetOptionResult(r)
  of hrUndo, hrRedo:
    return e.processHistoryResult(r, activeBuffer)
  of hrClearSearchHighlight, hrStripWhitespace, hrShellCommand, hrBackground, hrMan,
      hrSubstitute, hrDeleteLines, hrBuild, hrFilter, hrJobs:
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
  of hrPlaybackMacro, hrExecCommand, hrRepeatInsert:
    logWarn(
      "result_processor",
      "unreachable kind reached processResult: " & $r.kind &
        " (intercepted by processReplayedResult)",
    )
    discard # Consumed by processReplayedResult; only reaches here defensively.

  return e.processResultEpilogue(r, activeBuffer, hostHandled)

proc processResultEpilogue(
    e: Editor, r: HandlerResult, activeBuffer: TextBuffer, hostHandled: var bool
): bool =
  ## Post-processing for falling-through arms (hrHandled / hrUnhandled /
  ## hrError): overlay and mode transitions, viewer buffer
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
    let newMode = e.effectiveMode(modeTransition.get)

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

    # Switching between Visual kinds keeps where Visual was entered from.
    if not (oldMode.isVisualAllMode and newMode.isVisualAllMode):
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
      if not e.processResultWithHost(entry.get, activeBuffer, hostHandled):
        return false
      if hostHandled:
        return true
    elif not focused:
      e.setMode(newMode)

      # Adjust cursor when transitioning from Insert or Replace to Normal mode
      # Ctrl-o has placed the cursor itself (leaveInsertForCtrlO)
      if oldMode in {EditorMode.Insert, EditorMode.Replace} and
          newMode == EditorMode.Normal and not e.state.resumesInsert:
        let oldColumn = e.activeWindow.cursor.column

        logDebug(
          "handler",
          $oldMode & "→Normal transition: line=" & $e.activeWindow.cursor.line &
            " oldColumn=" & $oldColumn,
        )

        e.activeWindow.adjustCursorAfterInsertExit()

        if oldColumn != e.activeWindow.cursor.column:
          logDebug(
            "handler",
            "Cursor adjusted: " & $oldColumn & " → " & $e.activeWindow.cursor.column,
          )

  # Terminal view follows the window's sub-mode, which the dispatcher set.
  when not defined(moe.embedded):
    if e.state.mode == EditorMode.Terminal:
      e.syncTerminalView(e.activeWindow)

  # Filer buffer regeneration after state changes (e.g. enterDirectory, toggleHidden)
  if e.state.mode == EditorMode.Filer:
    let filerWin = e.activeWindow
    if filerWin.modeState.kind == mskFiler and
        filerWin.modeState.filer.needsBufferRefresh:
      filerWin.setView(
        filerWin.modeState.filer.createFilerTextBuffer(e.config.filer.showIcons)
      )
      filerWin.modeState.filer.needsBufferRefresh = false

  # FileTree buffer regeneration after state changes (check all windows since
  # the file tree sidebar may not be the active window)
  for win in e.windowManager.windows:
    if win.isSidebar and win.modeState.kind == mskFileTree and
        win.modeState.fileTree.needsBufferRefresh:
      win.setView(
        win.modeState.fileTree.createFileTreeTextBuffer(e.config.filer.showIcons)
      )
      win.modeState.fileTree.needsBufferRefresh = false

  # Set status message if any
  let statusMsg = r.getStatusMessage()
  if statusMsg.len > 0:
    e.state.statusMessage = statusMsg

  # Show syntax check message for current cursor line (if no other status message)
  if statusMsg.len == 0:
    let syntaxMsg = e.activeBuffer().syntaxCheckMessage(e.activeWindow.cursor.line)
    if syntaxMsg.isSome:
      e.state.statusMessage = syntaxMsg.get

  return true # Continue running

proc armInsertResume*(state: EditorState) =
  ## A command input starts: a key, typed or replayed, a paste, a pointer press,
  ## a scroll or Ctrl-C. Once it is done, it ends the wait Ctrl-o set before
  ## it, but not one it sets itself (Vim's CA_COMMAND_BUSY).
  if state.insertResume == irWaiting:
    state.insertResume = irArmed

proc settleInsertResume*(e: Editor) =
  ## Vim checks restart_edit at the end of each Normal command; this runs at
  ## the end of each input, typed or replayed. A command is done once it
  ## returns: one that sends an LSP request does not wait for the response,
  ## so no later key runs as a Normal command. Once the command Ctrl-o waits
  ## for is done, Insert resumes from Normal mode, Visual mode keeps waiting,
  ## and any other mode ends the wait. Nothing resumes once the editor has
  ## decided to quit.
  let state = e.state
  if state.insertResume == irNone:
    return
  # Vim's edit() clears restart_edit, so Insert or Replace entered anyhow, in
  # a held mapping or a macro too, ends the wait.
  if state.mode in {EditorMode.Insert, EditorMode.Replace}:
    state.insertResume = irNone
    return
  # The CodeLens picker the command opens takes keys, so the command goes on
  # until it closes.
  if state.insertResume != irArmed or state.quitDecided or state.hasOverlay or
      hasPendingBuiltinInput(e) or e.keyRouter.isHoldingKeys or
      state.mode.isVisualAllMode or state.lspCache.codeLensPicker.isActive:
    return
  state.insertResume = irNone
  # Vim resumes Insert silently in a buffer it cannot change, so the command's
  # message stays; Insert cannot hold such a buffer here.
  if state.mode != EditorMode.Normal or e.activeBuffer.readOnly:
    return
  # Vim resumes past the end of the line if the cursor is on its last character
  # and either Ctrl-o left that line there (ins_at_eol) or the column vertical
  # moves want is right of it, as Insert shows it: a tab on its first cell. It
  # keeps that column (arrow_used).
  let
    wanted = state.wanted
    line = e.activeBuffer.getLine(state.cursor.line)
    lastColumn = line.charLen - 1
    append =
      state.cursor.column == lastColumn and (
        state.insertResumeLineEnd == some(state.cursor.line) or
        wanted.cell >
        line.cursorCell(state.cursor.column, state.tabStop, onTabEnd = false)
      )
    message = state.statusMessage
    resumedAt = state.cursor
  discard e.processResult(e.handlerManager.runInsertCommand(e, append), e.activeBuffer)
  # Vim notes where typing starts before stepping past the end of the line, and
  # takes the resume for a cursor move (arrow_used).
  if state.mode == EditorMode.Insert:
    state.resumeTyping(resumedAt)
  state.wanted = wanted
  # The command's message stays, as in Vim, over the syntax check's.
  if message.len > 0:
    state.statusMessage = message

template withInsertResumeAside(e: Editor, body: untyped): ReplayOutcome =
  ## Run a macro or repeated keys with the Insert Ctrl-o waits for set aside, so
  ## none of their keys resumes it, and put it back once they are done. An abort
  ## drops it with the rest of the keys.
  let waiting = e.state.insertResume
  e.state.insertResume = irNone
  var replayed = roContinue
  try:
    replayed = block:
      body
  finally:
    if waiting != irNone and replayed == roContinue:
      e.state.insertResume = waiting
  replayed

const MaxMacroRecursionDepth* = 100
  ## Macro recursion depth guard (@a inside @a...) before abort.

const MaxMapRecursionDepth = 50
  ## Depth guard for `:map` (noremap=false) expansion and held keys let go.
  ## Kept below MaxMacroRecursionDepth so a cyclic mapping reports "recursive
  ## mapping" before the macro depth guard fires.

proc playbackMacroImpl(e: Editor, keys: seq[string]): ReplayOutcome
proc playbackKeyCombosImpl(
  e: Editor, combos: seq[KeyCombo], remapFrom: int, standsFor: seq[KeyCombo]
): ReplayOutcome

proc repeatInsert(e: Editor, r: HandlerResult): ReplayOutcome

proc runNestedKeyCombo*(
  manager: HandlerManager, e: Editor, key: KeyInput
): ReplayOutcome

proc processReplayedResult*(
    e: Editor, r: HandlerResult, activeBuffer: TextBuffer
): ReplayOutcome =
  ## Mini processor for keys fired from a nested replay context (macro,
  ## mapping RHS, held keys let go). Applies full side effects via
  ## `processResult` — no kind is silently dropped — and returns whether the
  ## loop should keep going. `hrPlaybackMacro` and `hrExecCommand` run their
  ## keys or command line here count times, so a failure stops the rest and
  ## the keys after them.
  if r.kind == hrExecCommand:
    # Vim stuffs the command line count times and an error flushes the rest.
    if e.interceptHostResult(r):
      return roAbort
    var outcome = roContinue
    for _ in 0 ..< r.execCommandCount:
      outcome = e.executeCommandOverlay(":" & r.execCommandText)
      if outcome != roContinue:
        break
    return outcome
  if r.kind == hrRepeatInsert:
    # `<C-o>.` resumes Insert once the keys are typed and Insert is left.
    return e.withInsertResumeAside(e.repeatInsert(r))
  if r.kind == hrPlaybackMacro:
    # Vim queues the Insert that Ctrl-o waits for after the register's keys
    # (put_reedit_in_typebuf), so the whole macro runs before it resumes, and
    # an error flushes it with the rest of the register.
    return e.withInsertResumeAside:
      var outcome = roContinue
      for _ in 0 ..< r.playbackMacroCount:
        outcome = playbackMacroImpl(e, r.playbackMacroKeys)
        if outcome != roContinue:
          break
      outcome
  let queued = e.hostResultRequestCount
  let shouldContinue = e.processResult(r, activeBuffer)
  if e.hostResultRequestCount > queued or r.kind == hrError:
    return roAbort
  if not shouldContinue:
    return roQuit
  roContinue

template withPlaybackGuard*(e: Editor, body: untyped): ReplayOutcome =
  ## Shared depth guard for macro / runtime-mapping replay loops. Replayed keys
  ## never reach the recorder, so recording stays on. `body` must assign to
  ## `outcome`.
  ## Exposed for tests that fire the exception path with a raising body.
  block:
    let state = e.state
    if state.pendingInput.macroState.playbackDepth >= MaxMacroRecursionDepth:
      e.state.statusMessage =
        "Macro recursion limit exceeded (max " & $MaxMacroRecursionDepth & ")"
      roAbort
    else:
      state.pendingInput.macroState.playbackDepth += 1
      var outcome {.inject.} = roContinue
      try:
        # `if true` avoids UnreachableCode when body ends with `return`/`raise`.
        # `if` (unlike `block`) does not capture a bare `break`.
        if true:
          body
      finally:
        # Exception safety: always restore playback state, even on failure.
        state.pendingInput.macroState.playbackDepth -= 1
      outcome

template recordingIfRan(
    e: Editor, keys: seq[KeyCombo], body: untyped
): Option[ReplayOutcome] =
  ## `body` for a key that stands for the typed `keys`, recording them once it
  ## has run (`some`) if a recording was on before it. The keys that start or
  ## stop a recording thus stay out of it, as Vim drops what the stopping key's
  ## fetch recorded.
  block:
    let recording = e.state.pendingInput.macroState.isRecording
    let ran: Option[ReplayOutcome] = body
    if recording and ran.isSome:
      e.state.pendingInput.macroState.recordTypedKeys(keys)
    ran

proc playbackKeyCombosImpl(
    e: Editor, combos: seq[KeyCombo], remapFrom: int, standsFor: seq[KeyCombo]
): ReplayOutcome =
  ## Iterate `combos` through `runNestedKeyCombo` — no per-key parse. Used by
  ## runtime key-sequence mappings whose RHS is pre-parsed at registration.
  ## Mappings take the keys from `remapFrom` on. The first key stands for the
  ## typed left-hand side `standsFor`, as in Vim, so a stop there leaves it out
  ## of the recording and a later one keeps it.
  var handedOff = false
  result = withPlaybackGuard(e):
    for i, k in combos:
      var input = KeyInput(combo: k, remap: i >= remapFrom, typed: false)
      if i == 0:
        input.standsFor = standsFor
      handedOff = true
      outcome = runNestedKeyCombo(e.handlerManager, e, input)
      if outcome != roContinue:
        break
  if not handedOff:
    # Vim records typed keys as it reads them, whatever comes of them.
    e.state.pendingInput.macroState.recordTypedKeys(standsFor)

proc playbackMacroImpl(e: Editor, keys: seq[string]): ReplayOutcome =
  ## Iterate user-recorded macro `keys` (register storage is seq[string]).
  ## Aborts on the first `stringToKeyCombo` failure but keeps executing the
  ## good prefix (matches pre-refactor behaviour). Counts as a running
  ## register (Vim's reg_executing) while it runs.
  e.state.pendingInput.macroState.executingDepth += 1
  try:
    result = withPlaybackGuard(e):
      for keyStr in keys:
        let keyComboOpt = stringToKeyCombo(keyStr)
        if keyComboOpt.isNone:
          e.state.statusMessage = "Invalid key in macro: " & keyStr
          outcome = roAbort
          break
        outcome = runNestedKeyCombo(
          e.handlerManager,
          e,
          KeyInput(combo: keyComboOpt.get, remap: true, typed: false),
        )
        if outcome != roContinue:
          break
  finally:
    e.state.pendingInput.macroState.executingDepth -= 1

proc typeAgain(e: Editor, typed: TypedInput): ReplayOutcome =
  ## Type one recorded input again, a key unmapped.
  case typed.kind
  of tiKey:
    runNestedKeyCombo(
      e.handlerManager, e, KeyInput(combo: typed.key, remap: false, typed: false)
    )
  of tiText:
    processReplayedResult(e, e.handlerManager.typeText(e, typed), e.activeBuffer)

proc newLineAfterTyped(e: Editor, linesBelow: int): ReplayOutcome =
  ## Enter at the end of what o or O typed, on the line above the last
  ## `linesBelow` lines. A pair closed as typed leaves the cursor short of it.
  let buffer = e.activeBuffer
  let line = clamp(buffer.len - 1 - linesBelow, 0, buffer.len - 1)
  e.state.cursor = BufferPosition(line: line, column: buffer.getLine(line).charLen)
  e.typeAgain(TypedInput(kind: tiKey, key: KeyCombo(isSpecial: true, special: skEnter)))

proc repeatInsert(e: Editor, r: HandlerResult): ReplayOutcome =
  ## Type an Insert record again (`.`, Ctrl-A, the count of `3ifoo`), its keys
  ## unmapped, and leave Insert after if asked. The count's repeats type what is
  ## recorded, so the record does not take them again.
  let wasRepeating = e.state.editState.typing.repeating
  e.state.editState.typing.repeating = wasRepeating or not r.repeatAsTyping
  try:
    result = withPlaybackGuard(e):
      block typing:
        for _ in 0 ..< r.repeatTimes:
          if r.repeatNewLine.isSome:
            if e.state.mode != EditorMode.Insert:
              break typing
            outcome = e.newLineAfterTyped(r.repeatNewLine.get)
            if outcome != roContinue:
              break typing
          for typed in r.repeatTyped:
            if e.state.mode != EditorMode.Insert:
              break typing
            outcome = e.typeAgain(typed)
            if outcome != roContinue:
              break typing
  finally:
    e.state.editState.typing.repeating = wasRepeating
  if result == roContinue and r.repeatLeave and e.state.mode == EditorMode.Insert:
    result = processReplayedResult(e, e.handlerManager.leaveInsert(e), e.activeBuffer)
  if result == roContinue and r.repeatThenExec.len > 0:
    result = processReplayedResult(
      e,
      HandlerResult(
        kind: hrExecCommand, execCommandText: r.repeatThenExec, execCommandCount: 1
      ),
      e.activeBuffer,
    )

proc stopRecursiveMapping(editor: Editor): ReplayOutcome =
  ## End a mapping that keeps expanding, as Vim's E223 does.
  editor.state.statusMessage = "recursive mapping (max " & $MaxMapRecursionDepth & ")"
  roAbort

proc replayMappingKeys(
    editor: Editor, mapping: RuntimeKeyMapping, standsFor: seq[KeyCombo]
): ReplayOutcome =
  ## `:noremap` keys run unmapped; `:map` keys meet the mappings again,
  ## bounded by `mapExpandDepth` / `MaxMapRecursionDepth`, all but the first
  ## when they start with the left-hand side, so `:map a ab` does not recur, as
  ## in Vim. Either way only the keys themselves: a register they run is mapped
  ## as when typed, as in Vim.
  let targetKeys = mapping.targetKeys
  if mapping.noremap:
    return
      playbackKeyCombosImpl(editor, targetKeys, remapFrom = targetKeys.len, standsFor)

  if editor.keyRouter.mapExpandDepth >= MaxMapRecursionDepth:
    editor.state.pendingInput.macroState.recordTypedKeys(standsFor)
    return editor.stopRecursiveMapping()
  let remapFrom = if targetKeys.startsWith(mapping.triggerKeys): 1 else: 0
  editor.keyRouter.mapExpandDepth += 1
  try:
    result = playbackKeyCombosImpl(editor, targetKeys, remapFrom, standsFor)
  finally:
    editor.keyRouter.mapExpandDepth -= 1

proc replayRuntimeKeySequence(
    editor: Editor, mapping: RuntimeKeyMapping, standsFor: seq[KeyCombo]
): ReplayOutcome =
  ## Replay the RHS of a fired runtime key-sequence mapping, whose left-hand
  ## side stands for the typed keys `standsFor`. Vim resumes the Insert Ctrl-o
  ## waits for in the middle of a mapping, but not of one that starts in Visual
  ## mode (old_mapped_len): its keys after the one that leaves Visual are still
  ## Normal mode commands. Entering Insert in it still ends the wait, and a
  ## Ctrl-o in it waits anew.
  let waiting = editor.state.insertResume
  if waiting == irNone or not editor.state.mode.isVisualAllMode:
    return editor.replayMappingKeys(mapping, standsFor)
  editor.state.insertResume = irHeld
  try:
    result = editor.replayMappingKeys(mapping, standsFor)
  finally:
    if editor.state.insertResume == irHeld:
      editor.state.insertResume = waiting

proc runRuntimeCommand(
    manager: HandlerManager,
    editor: Editor,
    commandName: string,
    standsFor: seq[KeyCombo],
): Option[ReplayOutcome] =
  ## Run the command an `rmkCommand` mapping names, for the typed keys
  ## `standsFor` of its left-hand side. `none` when it names none that can run
  ## here, which runs nothing and records nothing.
  editor.recordingIfRan(standsFor):
    let cmdResult = manager.executeCommandDirect(commandName)
    if cmdResult.isSome:
      some(processReplayedResult(editor, cmdResult.get, editor.activeBuffer))
    else:
      none(ReplayOutcome)

proc runMapping(
    manager: HandlerManager,
    editor: Editor,
    mapping: RuntimeKeyMapping,
    lhsKeys: seq[KeyInput],
): Option[ReplayOutcome] =
  ## Run `mapping`, whose left-hand side took `lhsKeys`. `none` when it names a
  ## command that cannot run here.
  case mapping.kind
  of rmkCommand:
    manager.runRuntimeCommand(editor, mapping.commandName, lhsKeys.standsFor)
  of rmkKeySequence:
    some(editor.replayRuntimeKeySequence(mapping, lhsKeys.standsFor))

proc feedHeldKeys(
    manager: HandlerManager,
    editor: Editor,
    keys: seq[KeyInput],
    outcome: ReplayOutcome,
    remap = true,
): ReplayOutcome =
  ## Feed `keys` again after the keys before them ended with `outcome`. After an
  ## error only the typed ones go on, as Vim drops the keys mappings produced
  ## but keeps those typed, and the error still stops what the keys came from.
  ## Mappings take none of them unless `remap`.
  result = outcome
  for k in keys:
    if result == roQuit:
      break
    if result == roAbort and not k.typed:
      # Vim records typed keys as it reads them, whatever comes of them.
      editor.state.pendingInput.macroState.recordTypedKeys(k.standsFor)
      continue
    var input = k
    input.remap = remap and k.remap
    let fed = runNestedKeyCombo(manager, editor, input)
    if fed == roQuit or result == roContinue:
      result = fed

proc releaseHeldKeys*(
    manager: HandlerManager,
    editor: Editor,
    keys: seq[KeyInput],
    leading: Option[RuntimeKeyMapping],
): ReplayOutcome =
  ## Let go of the keys the router held for a mapping they broke, as Vim does:
  ## the mapping the first keys complete runs, or else the first key runs
  ## unmapped, and the keys after it are fed again, so they can still start or
  ## complete a mapping. A leading command mapping that cannot run here counts
  ## as none, as when it matches at once. Letting go is one expansion, so keys
  ## that keep breaking a mapping they start again end as a recursive one.
  let router = editor.keyRouter
  if router.mapExpandDepth >= MaxMapRecursionDepth:
    # Unmapped, so the typed keys cannot start the cycle again.
    return
      manager.feedHeldKeys(editor, keys, editor.stopRecursiveMapping(), remap = false)
  router.mapExpandDepth += 1
  try:
    var first = none(ReplayOutcome)
    var next = 1
    if leading.isSome:
      let n = leading.get.triggerKeys.len
      first = manager.runMapping(editor, leading.get, keys[0 ..< n])
      if first.isSome:
        next = n
    if first.isNone:
      var unmapped = keys[0]
      unmapped.remap = false
      first = some(runNestedKeyCombo(manager, editor, unmapped))
    result = manager.feedHeldKeys(editor, keys[next .. ^1], first.get)
  finally:
    router.mapExpandDepth -= 1

proc runRoute*(
    manager: HandlerManager, editor: Editor, route: RouteResult
): Option[ReplayOutcome] =
  ## Run what the router decided for a key fed to it or at the timeout. `none`
  ## when it leaves the key to run as it is, or holds nothing.
  case route.kind
  of rrUnhandled, rrCancelled, rrCommand:
    # rrCommand comes only from `resolveBuiltin`, never from the router.
    none(ReplayOutcome)
  of rrRunMapping:
    let ran = manager.runMapping(editor, route.mapping, route.lhsKeys)
    if ran.isSome:
      ran
    else:
      # A command that cannot run here counts as no mapping, as when the held
      # keys are let go, so its keys run unmapped instead of being lost.
      some(manager.releaseHeldKeys(editor, route.lhsKeys, none(RuntimeKeyMapping)))
  of rrWaiting:
    some(roContinue)
  of rrReleaseHeld:
    some(manager.releaseHeldKeys(editor, route.keys, route.leading))

proc routerMode*(e: Editor): EditorMode =
  ## The mode whose mappings a key meets: the command line's in the Command,
  ## Search and Rename overlays, as Vim maps `:`, `/` and `input()` alike, else
  ## the window's.
  if e.state.hasOverlay: EditorMode.Command else: e.state.mode

proc letHeldKeysGo*(manager: HandlerManager, editor: Editor): ReplayOutcome =
  ## Let go of the keys held for a mapping before an input that is not a key,
  ## as the timeout does, until none are held: a key let go can be held again
  ## as the start of another mapping. Keys that keep coming back end as a
  ## recursive mapping.
  result = roContinue
  for _ in 0 ..< MaxMapRecursionDepth:
    if not editor.keyRouter.isHoldingKeys or result != roContinue:
      return
    let route = editor.keyRouter.flushTimeout(editor.routerMode)
    result = manager.runRoute(editor, route).get(roContinue)
  if editor.keyRouter.isHoldingKeys:
    editor.keyRouter.dropHeldKeys()
    result = editor.stopRecursiveMapping()

proc escapeEndsCommand(e: Editor, keyCombo: KeyCombo): bool =
  ## Escape ends a Normal mode command being built before a Normal mode
  ## mapping can take it: Vim uses none for an operator's motion or a character
  ## argument.
  keyCombo.isSpecial and keyCombo.special == skEscape and
    e.state.mode == EditorMode.Normal and hasPendingBuiltinInput(e)

proc answerHitEnter(e: Editor, keyCombo: KeyCombo): bool =
  ## Dismiss temporary messages (e.g. :jump output) on any key, as Vim's
  ## hit-enter prompt does. True when that uses the key up: Enter, Space,
  ## Ctrl-J and Ctrl-C only dismiss. Vim puts any other key back to run, so
  ## `:` starts a command line, or types itself in Insert mode, and the keys
  ## after `:jump<CR>` in a mapping run.
  if e.state.ui.tempMessages.len == 0:
    return false
  e.state.ui.tempMessages = @[]
  if keyCombo.isSpecial:
    return keyCombo.special == skEnter and keyCombo.modifiers == {}
  if keyCombo.modifiers == {}:
    return keyCombo.char == " "
  keyCombo.modifiers == {kmCtrl} and keyCombo.char in ["c", "C", "j", "J"]

proc runAsItself(manager: HandlerManager, e: Editor, key: KeyInput): ReplayOutcome =
  ## Run `key` with no mapping applied: a layer in front of the mode handlers
  ## takes it if one is up, else the mode handler.
  let front =
    if frontLayerHook.isNil:
      none(ReplayOutcome)
    else:
      frontLayerHook(e, key.combo)
  if front.isSome:
    return front.get
  let r = manager.handleKeyCombo(e, key.combo)
  result = processReplayedResult(e, r, e.activeBuffer)
  e.enforceModePolicy()

proc dispatchNestedKeyCombo(
    manager: HandlerManager, e: Editor, key: KeyInput
): ReplayOutcome =
  # A prompt reads its keys before the mappings, as Vim reads a hit-enter
  # prompt's or a popup menu's, and lets one it does not take go on to them.
  # Keys the router holds meet it once they are let go.
  if not e.keyRouter.isHoldingKeys:
    if e.answerHitEnter(key.combo):
      # Vim reads it with the recording off. The typed keys a mapping's key
      # stands for were read before, with the mapping.
      if not key.typed:
        e.state.pendingInput.macroState.recordTypedKeys(key.standsFor)
      return roContinue
    if not promptLayerHook.isNil:
      let prompted = e.recordingIfRan(key.standsFor, promptLayerHook(e, key.combo))
      if prompted.isSome:
        return prompted.get
  let mode = e.routerMode
  let literal =
    mode != EditorMode.Command and (
      e.state.pendingInput.waitsForOperand(manager.keyBindingRegistry) or
      e.escapeEndsCommand(key.combo)
    )
  let routed = manager.runRoute(e, e.keyRouter.feedKey(mode, key, literal))
  if routed.isSome:
    return routed.get
  e.recordingIfRan(key.standsFor, some(manager.runAsItself(e, key))).get

proc runNestedKeyCombo*(
    manager: HandlerManager, e: Editor, key: KeyInput
): ReplayOutcome =
  ## The one way a key runs, typed or replayed (macro, mapping RHS, held keys
  ## let go): a prompt reads it first, then the router, then the layers and the
  ## mode handler that run it as it is, so a replay meets what typing met and
  ## every kind's side effect fires exactly once. Each key may finish the
  ## command Ctrl-o waits for, so Insert may resume after it, in the middle of
  ## a mapping too, as in Vim. `key.remap` covers this key alone, not the keys
  ## of a register it runs.
  # Before the command starts, so the jump is not counted as its move.
  e.completeScrollAnimation()
  e.state.armInsertResume()
  e.asCommand:
    result = manager.dispatchNestedKeyCombo(e, key)
  # Once the command has dropped the column vertical moves want, if it does,
  # so Insert resumes past the end only as Vim's would.
  if result != roQuit:
    e.settleInsertResume()

proc outcomeToHandlerResult(e: Editor, outcome: ReplayOutcome): HandlerResult =
  ## Fold a ReplayOutcome into the HandlerResult shape test-facing wrappers
  ## return. `roAbort` pulls the diagnostic from `state.statusMessage`, which
  ## the abort site (`playbackMacroImpl`, `replayRuntimeKeySequence`, or
  ## `processResult`'s hrError arm) has already populated. A host-owned
  ## result sets nothing, so `errorMessage` is stale.
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

proc playbackKeyCombos*(
    editor: Editor, combos: seq[KeyCombo], remap = true
): HandlerResult =
  ## Test-facing wrapper for the pre-parsed variant. Used by tests that
  ## execute a `RuntimeKeyMapping.targetKeys` (now seq[KeyCombo]) directly.
  let remapFrom = if remap: 0 else: combos.len
  outcomeToHandlerResult(editor, playbackKeyCombosImpl(editor, combos, remapFrom, @[]))

proc runKeyCombo*(
    manager: HandlerManager, e: Editor, keyCombo: KeyCombo, remap = true
): HandlerResult =
  ## HandlerResult-returning form of `runNestedKeyCombo`, for tests that
  ## inspect kind/errorMessage. Full processResult side effects fire on every
  ## path (precheck, direct dispatch, hrPlaybackMacro expansion) so the
  ## observable state after this call matches production `handleEvent`. The
  ## returned HandlerResult is a status signal (hrHandled/hrQuit/hrError),
  ## not the raw dispatched result — inspect `state.mode`, `state.overlay`,
  ## and other mutations directly.
  outcomeToHandlerResult(
    e,
    runNestedKeyCombo(manager, e, KeyInput(combo: keyCombo, remap: remap, typed: false)),
  )

proc tryHandleQuickRunRequest(e: Editor, activeBuffer: TextBuffer): bool =
  ## Consume `state.requestQuickRun` (set by buffer-mode key handlers) and
  ## fire QuickRun via pending state. Returns true when a QuickRun request
  ## was consumed; callers should skip further hr-teardown in that case.
  if not e.state.requestQuickRun:
    return false
  e.state.requestQuickRun = false
  let prepareResult = e.prepareQuickRun(activeBuffer)
  if prepareResult.isErr:
    e.state.statusMessage = "QuickRun error: " & prepareResult.error
    logError("handler", "QuickRun prepare failed: " & prepareResult.error)
  else:
    let prepared = prepareResult.get
    e.state.pending.add PendingAsyncOp(
      kind: paoQuickRun,
      epoch: e.state.commandEpoch,
      quickRun: (
        cmd: prepared.command.cmd,
        args: prepared.command.args,
        filePath: prepared.filePath,
        workDir: prepared.workDir,
      ),
    )
    if e.config.notification.screenNotifications and
        e.config.notification.quickRunScreenNotify:
      e.state.statusMessage = quickRunStartupMessage(prepared.filePath)
  e.state.exitOverlay()
  e.setMode(EditorMode.Normal)
  return true

proc executeCommandOverlay*(e: Editor, commandText: string): ReplayOutcome =
  ## Full lifecycle of a Command-overlay Enter: pre-teardown, dispatch,
  ## side effects via processResult, and teardown driven by `r.group`.
  ## `roAbort` when the command fails or the host takes its result, so the
  ## keys after it stop as after any replayed key that does.
  # 1. pre-teardown (kind-independent)
  # A command line runs outside Visual, as `:` leaves it in Vim; a Visual
  # mapping that runs one directly gets here without the overlay.
  e.state.leaveVisual()
  e.state.commandCompletionManager.cancelCompletion()
  if e.state.ui.substitutePreview.isActive:
    e.cancelSubstitutePreview()

  # 2. dispatch
  let activeBuffer = e.activeBuffer()
  let commandMode = e.currentMode
  let isShared = e.isBufferShared(activeBuffer)
  let otherModifiedCount = e.modifiedBufferCountExcept(activeBuffer)
  var r: HandlerResult
  if commandText.len <= 1:
    r = e.handlerManager.handleCommandMode(
      activeBuffer, commandText, isShared, e.activeWindow.cursor.line,
      otherModifiedCount,
    )
  else:
    let parsed = e.commandLineParser.parseCommandLine(commandText)
    if e.interceptHostCommand(parsed):
      r = HandlerResult(kind: hrHandled)
    else:
      let cmdResult = e.commandLineParser.execute(parsed)
      # As Vim's setpcmark, where the command starts is a jump, which its edit
      # then moves. A command that fails takes it back.
      var jumpsBefore = none(JumpListState)
      if cmdResult.kind in JumpActions:
        jumpsBefore = some(e.state.jumpList)
        e.addToJumpList(e.jumpOrigin())
      r = e.handlerManager.handleCommandMode(
        activeBuffer, cmdResult, isShared, e.activeWindow.cursor.line,
        otherModifiedCount,
      )
      if r.kind == hrError and jumpsBefore.isSome:
        e.state.jumpList = jumpsBefore.get
  if commandMode == EditorMode.Config and r.kind == hrCloseWindow:
    r = HandlerResult(kind: hrConfigQuit)
  if commandText.len > 1:
    e.addCommandToHistory(commandText[1 ..^ 1])

  # 3. requestQuickRun poll (set independently of r.kind by buffer-mode keys)
  if e.tryHandleQuickRunRequest(activeBuffer):
    return roContinue

  # 4. side effects
  let queued = e.hostResultRequestCount
  var hostHandled: bool
  let shouldContinue = e.processResultWithHost(r, activeBuffer, hostHandled)
  if not shouldContinue:
    return roQuit
  result =
    if e.hostResultRequestCount > queued or r.kind == hrError: roAbort else: roContinue
  if hostHandled:
    # A host-owned result must not quit or re-apply a synthesized mode switch
    # through the original result's group after its side effects were skipped.
    e.state.exitOverlay()
    e.setMode(e.state.mode)
    return

  # 5. teardown
  case r.group
  of hrgAppExit:
    return roQuit # unreachable — processResult would have returned false
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
