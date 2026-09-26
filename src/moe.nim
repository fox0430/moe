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

when not defined(posix):
  {.error: "moe supports POSIX platforms only".}

import std/[strformat, os, options, tables]

import pkg/[celina, results, chronos]
from pkg/celina/async/async_io import tryWriteBlocking
from std/posix import isatty, STDERR_FILENO, Sigset, SIGTTOU

import
  moepkg/[
    editor, editor_window_layout, handler, modes, logger, cmdline, lsp_integration,
    config, config_loader, deadly_signals, emergency, key_router, terminal_mode,
    recovery_format, recovery_index, recovery_notice, signal_watcher, terminal_command,
    editor_file_jobs,
  ]
import moepkg/command_handlers/command_mode_handler

proc toCursorStyle(ct: CursorType): CursorStyle =
  ## Convert config CursorType to celina CursorStyle
  case ct
  of ctTerminalDefault: CursorStyle.Default
  of ctBlinkBlock: CursorStyle.BlinkingBlock
  of ctBlinkIbeam: CursorStyle.BlinkingBar
  of ctNonBlinkBlock: CursorStyle.SteadyBlock
  of ctNonBlinkIbeam: CursorStyle.SteadyBar

proc terminalWindowFor(e: Editor, id: BufferId): EditorWindow =
  ## The window showing the session parked on `id`, or nil for a background tab.
  for window in e.windowManager.windows:
    if window.mode == EditorMode.Terminal and window.modeState.kind == mskTerminal and
        window.tabBufferId == id:
      return window
  nil

proc pollTerminalSessions*(e: Editor) =
  ## Drain every live Terminal session's PTY and resize the ones on screen.
  ## Called on every render frame.
  ##
  ## Follows `e.terminalStates`, not the windows: a backgrounded session is in
  ## no window, and a child whose output nobody drains blocks in write().
  var exited: seq[BufferId]
  for id, session in e.terminalStates:
    discard session.pollOutput()

    let window = e.terminalWindowFor(id)
    if window == nil:
      # Backgrounded: no size to follow, and no teardown behind the user's back.
      continue

    # Sizing follows the window, not the sub-mode: output drained while the
    # user browses the scrollback still lands in the grid.
    let (expectedCols, expectedRows) = e.calculateTerminalAreaDimensions(window)
    if expectedCols > 0 and expectedRows > 0 and
        (expectedCols != session.grid.cols or expectedRows != session.grid.rows):
      session.resize(expectedCols, expectedRows)

    # A shell only exits when the user quits it, so the tab always goes — but
    # not while the user is browsing the scrollback of one that just exited.
    if session.subMode == tsmInput and session.exitCode.isSome:
      # After the loop: teardown mutates the table this one is walking.
      exited.add(id)

  for id in exited:
    e.closeTerminalBuffer(id)

proc handleStartUpWindows(e: Editor, termWidth, termHeight: int) =
  ## Execute startup window actions on first render when terminal size is known.
  ## Called once; guards itself with `startUpWindowsDone`.
  if e.state.startUpWindowsDone:
    return
  e.state.startUpWindowsDone = true

  # Apply the real terminal size to the startup window layout and sync
  # screenSize so the subsequent render does not re-trigger resizeWindows.
  e.applyStartUpScreenSize(termWidth, termHeight)

  # Open file tree sidebar if configured
  if e.config.startUpFileTree.enable:
    e.toggleFileTree(none(string), e.activeBuffer())

type Death = object ## Why the editor is leaving without the user asking it to.
  exception: ref Exception ## What ended the loop, if anything did.
  case kind: ContinuityKind
  of ckSignal:
    signal: cint
  of ckCrash, ckUnknown:
    discard

proc crashDeath(e: ref Exception): Death =
  ## Prefer a taken signal as the cause: a closed terminal fails tty I/O often
  ## before SIGHUP arrives, so an I/O crash waits briefly for one.
  var sig = takenSignal()
  let ioFailed = e of IOError or e of OSError or e of TerminalError
  if sig == 0 and ioFailed and signalWatcherRunning():
    sig = waitForTakenSignal(200.milliseconds)
  if sig == 0:
    Death(kind: ckCrash, exception: e)
  else:
    Death(kind: ckSignal, signal: sig, exception: e)

proc detail(death: Death): string =
  case death.kind
  of ckSignal:
    if death.exception.isNil:
      signalName(death.signal)
    else:
      signalName(death.signal) & ": " & death.exception.msg
  of ckCrash, ckUnknown:
    if death.exception.isNil: "" else: death.exception.msg

proc leave(death: Death) {.noreturn.} =
  ## Die of the signal so the parent sees `WIFSIGNALED`; otherwise `quit(1)`.
  if death.kind == ckSignal:
    reraiseAsDeath(death.signal)
  quit(1)

proc writeExitReports(editor: Editor) =
  ## Print the owed work's reports once the screen is gone, before teardown
  ## (which may block). SIGPIPE is ignored, so a closed stderr only raises.
  try:
    for report in editor.state.exitReports:
      stderr.writeLine "moe: " & report
  except IOError:
    discard

var preserving = none(Death)
  ## Set once, so a nested death cannot restart the sequence or change the exit.

proc preserveAndExit(
    editor: Editor,
    app: AsyncApp,
    death: Death,
    cmdLineConfig: CmdLineConfig,
    log: Logger,
) {.noreturn.} =
  ## Save unsaved buffers to recovery files, restore the terminal and leave.
  ## The single exit for both crashes and signals. Nothing is saved once the
  ## user quit, and the user's own files are never written. Recovery files are
  ## not fsynced: the process is dying, not the kernel.
  ##
  ## Every step is guarded, Defects included: callers are `raises: []`
  ## callbacks, and an escape would leave the terminal in raw mode.
  if preserving.isSome:
    # Safety net: a nested crash must not hide the first death's signal.
    preserving.get.leave()
  preserving = some(death)

  # In the background, touching the terminal would stop moe; with SIGTTOU
  # blocked, writes still go through under `stty tostop`.
  let background = inBackground()
  if background:
    var previous: Sigset
    discard blockSignal(SIGTTOU, previous)

  var savedPaths: seq[string]
  if not editor.state.quitDecided and beginPreserving():
    try:
      # `raises: []` does not cover Defects.
      savedPaths = editor.emergencySaveBuffers(death.kind, death.detail)
    except Exception as ex:
      logError("moe", "emergency save failed: " & ex.msg)

  # Record the owed work before teardown stops it silently.
  try:
    editor.abandonExitWait()
  except Exception as ex:
    logError("moe", "stopping owed work failed: " & ex.msg)

  # Before teardown: `releaseExternalResources` may block on wedged threads,
  # and the user must not wait in raw mode.
  try:
    if not app.isNil and not background:
      # CAN aborts an escape sequence a suspended frame write left open.
      # Blocking, since that write was suspended on a full tty.
      tryWriteBlocking("\x18")
      app.restoreTerminal()

    if not background or isatty(STDERR_FILENO) != 1:
      if death.kind == ckSignal:
        stderr.writeLine "moe: caught deadly signal " & signalName(death.signal)
      if not death.exception.isNil:
        stderr.writeLine "moe: fatal error: " & death.exception.msg
        stderr.writeLine death.exception.getStackTrace()
      if savedPaths.len > 0:
        stderr.writeLine "Recovery files saved to: " & savedPaths[0].parentDir
      editor.writeExitReports()
  except Exception as ex:
    logError("moe", "terminal restore/report failed: " & ex.msg)

  # Teardown below is capped by the watcher's finish deadline; after settle
  # the next signal ends the process at once.
  settle()

  try:
    if cmdLineConfig.debugEnabled:
      case death.kind
      of ckSignal:
        logInfo("moe", "Caught deadly signal " & death.detail)
      else:
        logError("moe", "Fatal: " & death.detail)

    editor.releaseExternalResources()

    if cmdLineConfig.debugEnabled:
      log.close()
  except Exception as ex:
    logError("moe", "cleanup failed: " & ex.msg)

  death.leave()

proc answerDeadlySignals(
    editor: Editor, app: AsyncApp, cmdLineConfig: CmdLineConfig, log: Logger
) {.async: (raises: []).} =
  ## Preserve on the first signal, unless the user already quit: teardown then
  ## re-raises it.
  try:
    await signalForwarded()
  except CancelledError:
    return
  if editor.state.quitDecided:
    beginWindingDown()
    # Stop the hooks the quit is waiting for, so the loop ends on its own.
    editor.abandonExitWait()
  else:
    {.cast(gcsafe).}:
      editor.preserveAndExit(
        app, Death(kind: ckSignal, signal: takenSignal()), cmdLineConfig, log
      )

template editorCallback(
    ed: Editor, app: AsyncApp, clc: CmdLineConfig, lg: Logger, body: untyped
): untyped =
  ## Wrap callback body with gcsafe/raises casts and emergency save on crash.
  {.cast(gcsafe).}:
    {.cast(raises: []).}:
      try:
        body
      except Exception as e:
        ed.preserveAndExit(app, crashDeath(e), clc, lg)

proc applyFrontendRequests(editor: Editor, app: AsyncApp) =
  ## Drain editor-core requests that need concrete Celina app side effects.
  let mouseCapture = editor.state.takeMouseCaptureRequest()
  if mouseCapture.isSome:
    if mouseCapture.get:
      app.enableMouse()
    else:
      app.disableMouse()

proc runEditor(
    editor: Editor, app: AsyncApp, cmdLineConfig: CmdLineConfig, log: Logger
) {.async.} =
  ## Async entry point for the editor main loop

  proc suspendFrontend(): Future[void] {.async.} =
    await app.suspendAsync()

  proc resumeFrontend(): Future[void] {.async.} =
    await app.resumeAsync()

  let frontendHooks = FrontendHooks(suspend: suspendFrontend, resume: resumeFrontend)

  {.cast(gcsafe).}:
    app.onEventAsync proc(e: Event, app: AsyncApp): Future[EventResult] {.async.} =
      editorCallback(editor, app, cmdLineConfig, log):
        if e.kind == EventKind.Resize:
          # celina's async_app already updates the terminal size, clears the
          # screen and forces a full render on the next frame.
          return erContinue

        if editor.state.quitDecided:
          # Waiting for the hooks the quit owes: no key reaches the editor,
          # and Ctrl-C gives up on them.
          if e.kind == EventKind.Quit:
            return erQuit
          return erContinue

        let shouldContinue = editor.handleEvent(e)
        editor.applyFrontendRequests(app)

        # Drain unconditionally: detached async tasks can set pending fields
        # after handleEvent returns; a guard here would skip that drain. A quit
        # drains too, so a `:!` queued ahead of it in one mapping still runs.
        await editor.handlePendingAsyncOperations(frontendHooks)

        if not shouldContinue:
          app.setApplicationTimeout(0)
          # Otherwise the tick ends the session once the owed hooks are done.
          return if editor.readyToExit(): erQuit else: erContinue

        # Key mapping timeout control — delegated to KeyRouter so policy
        # (enabled/timeoutlen) and accumulator state are queried in one place.
        let routerTimeout = editor.keyRouter.nextTimeoutMs()
        if routerTimeout > 0 and app.getApplicationTimeout() == 0:
          app.setApplicationTimeout(routerTimeout)
        elif routerTimeout == 0 and app.getApplicationTimeout() > 0:
          app.setApplicationTimeout(0)

        return erContinue

    app.onTimeoutAsync proc(app: AsyncApp): Future[TickResult] {.async.} =
      editorCallback(editor, app, cmdLineConfig, log):
        let shouldContinue = editor.handleKeyMappingTimeout()
        editor.applyFrontendRequests(app)
        app.setApplicationTimeout(0) # One-shot: disable until next prefix match
        await editor.handlePendingAsyncOperations(frontendHooks)
        if not shouldContinue and editor.readyToExit():
          return trQuit
        return trContinue

    app.onTickAsync proc(app: AsyncApp): Future[TickResult] {.async.} =
      editorCallback(editor, app, cmdLineConfig, log):
        editor.lsp.poll(0)
        editor.lsp.cleanupStaleProgress()
        await editor.handlePendingAsyncOperations(frontendHooks)
        if editor.readyToExit():
          return trQuit
        editor.showExitWait()
      return trContinue

    app.onRenderAsync proc(buffer: var Buffer) =
      editorCallback(editor, app, cmdLineConfig, log):
        # Execute startup window actions on first render
        if not editor.state.startUpWindowsDone:
          editor.handleStartUpWindows(buffer.area.width, buffer.area.height)

        # Poll terminal output for all windows in Terminal mode
        editor.pollTerminalSessions()

        editor.render(buffer)
        editor.applyFrontendRequests(app)

        if not editor.config.standard.disableChangeCursor:
          # Set cursor style based on editor mode (unless disabled)
          let cursorStyle =
            case editor.state.mode
            of EditorMode.Insert:
              toCursorStyle(editor.config.standard.insertModeCursor)
            else:
              toCursorStyle(editor.config.standard.normalModeCursor)
          app.setCursorStyle(cursorStyle)

        if editor.state.cursorVisible:
          # Set cursor position and visibility
          app.setCursorPosition(
            editor.state.screenCursor.x, editor.state.screenCursor.y
          )
          app.showCursor()
        else:
          app.hideCursor()

    # Not before the loop runs: until then the default action is better.
    if signalWatcherRunning():
      loopAnswers()
      asyncSpawn editor.answerDeadlySignals(app, cmdLineConfig, log)
    elif signalWatcherSupported:
      editor.appendStatus(
        "Warning: unsaved buffers will not be preserved if moe is terminated"
      )

    try:
      # Run the async main loop
      # Note: Bracketed Paste Mode is enabled via AppConfig(bracketedPaste: true)
      await app.runAsync()
    except Exception as e:
      editor.preserveAndExit(app, crashDeath(e), cmdLineConfig, log)

    if not editor.config.standard.disableChangeCursor:
      # Restore cursor to default style on exit
      let cursorStyle = toCursorStyle(editor.config.standard.defaultCursor)
      app.setCursorStyle(cursorStyle)

    # Teardown can block on a wedged language server; it is capped by the
    # watcher's finish deadline, and from here the next signal ends moe.
    settle()

    # After Ctrl-C, record the owed work before teardown stops it silently.
    editor.abandonExitWait()
    editor.writeExitReports()
    editor.releaseExternalResources()

    if cmdLineConfig.debugEnabled:
      # Clean up logger
      logInfo("moe", "Editor shutting down")
      log.close()

    let lateSignal = takenSignal()
    if lateSignal != 0:
      reraiseAsDeath(lateSignal)

proc main() =
  # Before any thread exists: threads inherit their creator's signal mask.
  discard startSignalWatcher()

  # Parse command line arguments
  let cmdLineConfig = parseCmdLine()

  # Load configuration
  let loadResult = loadConfig()
  var
    editorConfig: EditorConfig
    validationResult = newValidationResult()
  if loadResult.isOk:
    let (config, vr) = loadResult.get
    editorConfig = config
    validationResult = vr
  else:
    # Config file parse error - add to validation result and use default config
    validationResult.addError("config", loadResult.error, "valid TOML file")
    editorConfig = newEditorConfig()

  # Apply command-line overrides on top of the TOML-loaded config.
  if cmdLineConfig.bufferBackend.isSome:
    editorConfig.bufferBackend.kind = cmdLineConfig.bufferBackend.get

  # Initialize file logging system for debugging
  # clearOnStart is enabled if set via command line or config file
  let clearLog = cmdLineConfig.clearLog or editorConfig.log.clearOnStart
  let log = initLogger(
    LogLevel.Debug, enabled = cmdLineConfig.debugEnabled, clearOnStart = clearLog
  )
  setGlobalLogger(log)
  if cmdLineConfig.debugEnabled:
    logInfo("moe", "Editor starting with debug logging enabled")

  # Create editor with loaded configuration and validation result
  var editor = newEditor(editorConfig, validationResult)
  # Not in newEditor: tests construct editors and must not read the user's
  # cache. Pruned first so the index never lists what is about to go.
  for dir in newRecoveryStore(getCrashRecoveryBaseDir()).pruneSettledSessions():
    logInfo("moe", "Pruned settled recovery session " & dir.lastPathPart)
  editor.recovery = some(newRecoveryIndex(getCrashRecoveryBaseDir()))

  # Always capture mouse events so the terminal doesn't convert wheel events
  # to arrow key sequences. When mouse is disabled in config, events are
  # ignored in handleMouseEvent instead.
  let appConfig = AppConfig(
    title: "moe",
    alternateScreen: true,
    mouseCapture: false,
    rawMode: true,
    windowMode: false,
    bracketedPaste: true,
    # `signal_watcher` owns the deadly signals.
    installSignalHandler: false,
  )
  var app = newAsyncApp(appConfig)

  # Apply initial frontend requests queued by newEditor/applyConfigSettings.
  editor.applyFrontendRequests(app)

  # Set up LSP diagnostics callback to update buffer markers. Route to the
  # buffer matching the URI (not only the active one) so diagnostics for
  # background buffers aren't dropped.
  editor.lsp.setDiagnosticsCallback(
    proc(uri: string, diagnostics: seq[Diagnostic], version: Option[int]) {.gcsafe.} =
      editor.applyDiagnosticsForUri(uri, diagnostics, version)
  )

  # Re-open buffers automatically when a language server recovers from a crash,
  # so its diagnostics/completion come back without a manual `:lspRestart`.
  editor.lsp.setServerRestartCallback(
    proc(langId: string) {.gcsafe.} =
      editor.onLspServerRestart(langId)
  )

  # Apply server-initiated workspace/applyEdit requests (e.g. rust-analyzer
  # refactors delivered via executeCommand) to the editor's buffers.
  # applyWorkspaceEditFromServer re-clamps window cursors itself after any edit.
  editor.lsp.setApplyEditCallback(
    proc(edit: WorkspaceEdit): ApplyWorkspaceEditResult {.gcsafe.} =
      {.cast(gcsafe).}:
        editor.applyWorkspaceEditFromServer(edit)
  )

  if cmdLineConfig.filePaths.len > 0:
    # Check if first path is a directory
    if cmdLineConfig.filePaths.len == 1 and dirExists(cmdLineConfig.filePaths[0]):
      # Directory specified - start in Filer mode
      editor.enterFilerInActiveWindow(absolutePath(cmdLineConfig.filePaths[0]))
    else:
      # Load first file
      block:
        let r = editor.loadFile(cmdLineConfig.filePaths[0])
        if r.isErr:
          echo fmt"Error: {r.error}"
          quit(1)
        # Apply readonly mode if specified
        if cmdLineConfig.isReadonly:
          editor.activeBuffer().readOnly = true
          editor.enforceModePolicy()

      # Open any additional files (after the first). The auto-split vs no-split
      # decision and the per-file loop live in openAdditionalStartupFiles so the
      # two paths stay in sync and the behaviour is unit-testable.
      if cmdLineConfig.filePaths.len > 1:
        editor.openAdditionalStartupFiles(
          cmdLineConfig.filePaths, cmdLineConfig.isReadonly
        )

  # After the startup files are open, so the count can tell them apart from
  # work no open buffer shows.
  editor.noteRecoveryAtStartup()

  # Run the async editor main loop
  waitFor runEditor(editor, app, cmdLineConfig, log)

  if editor.state.exitCode != 0:
    quit(editor.state.exitCode)

when isMainModule:
  main()
