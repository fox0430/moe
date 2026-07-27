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

import std/[strformat, os, options]

import pkg/[celina, results, chronos]

import
  moepkg/[
    editor, editor_window_layout, handler, modes, logger, cmdline, lsp_integration,
    config, config_loader, emergency, key_router,
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

proc pollTerminalWindows*(e: Editor) =
  ## Poll PTY output for all windows in Terminal mode.
  ## Called on every render frame to ensure terminal output is up-to-date.
  ## Also handles automatic cleanup when the shell process exits.
  for window in e.windowManager.windows:
    if window.mode == EditorMode.Terminal and window.modeState.kind == mskTerminal:
      let termState = window.modeState.terminal
      if termState.subMode == tsmInput:
        # Resize terminal if window dimensions changed
        let (expectedCols, expectedRows) = e.calculateTerminalAreaDimensions(window)
        if expectedCols != termState.grid.cols or expectedRows != termState.grid.rows:
          if expectedCols > 0 and expectedRows > 0:
            termState.resize(expectedCols, expectedRows)

        discard termState.pollOutput()

        if termState.exitCode.isSome:
          # The session always runs as a persistent interactive shell (even
          # `:terminal ls` runs the command and then drops into a live shell),
          # so an exit only happens when the user quits the shell itself.
          # Tear down the tab in every case.
          e.closeTerminalBuffer(window.buffer.id)
          return

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

proc emergencySaveAndQuit(
    editor: Editor,
    app: AsyncApp,
    e: ref Exception,
    cmdLineConfig: CmdLineConfig,
    log: Logger,
) {.noreturn.} =
  ## Emergency save modified buffers and exit on crash.
  ##
  ## This runs as a last-resort handler for an already-fatal exception from
  ## inside `{.cast(raises: []).}` callbacks, so a secondary exception raised by
  ## the rescue body would escape unchecked and skip the terminal restore below,
  ## stranding the user in raw mode. Guard the save/cleanup sequence and always
  ## fall through to restoreTerminal()/quit(1) no matter what it throws.
  var savedPaths: seq[string]
  try:
    savedPaths = editor.emergencySaveBuffers()

    editor.releaseExternalResources()

    if cmdLineConfig.debugEnabled:
      logError("moe", "Fatal: " & e.msg)
      log.close()
  except CatchableError as ce:
    logError("moe", "emergency save/cleanup failed: " & ce.msg)

  # Always restore the terminal and report the crash, even if the rescue body
  # above threw. Guarded so a failure here still reaches quit(1).
  try:
    if not app.isNil:
      app.restoreTerminal()

    stderr.writeLine "moe: fatal error: " & e.msg
    stderr.writeLine e.getStackTrace()
    if savedPaths.len > 0:
      stderr.writeLine "Recovery files saved to: " & savedPaths[0].parentDir
  except CatchableError as ce:
    logError("moe", "terminal restore/report failed: " & ce.msg)

  quit(1)

template editorCallback(
    ed: Editor, app: AsyncApp, clc: CmdLineConfig, lg: Logger, body: untyped
): untyped =
  ## Wrap callback body with gcsafe/raises casts and emergency save on crash.
  {.cast(gcsafe).}:
    {.cast(raises: []).}:
      try:
        body
      except Exception as e:
        ed.emergencySaveAndQuit(app, e, clc, lg)

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

        let shouldContinue = editor.handleEvent(e)
        editor.applyFrontendRequests(app)

        # Drain unconditionally: detached async tasks can set pending fields
        # after handleEvent returns; a guard here would skip that drain.
        await editor.handlePendingAsyncOperations(frontendHooks)

        # Key mapping timeout control — delegated to KeyRouter so policy
        # (enabled/timeoutlen) and accumulator state are queried in one place.
        let routerTimeout = editor.keyRouter.nextTimeoutMs()
        if routerTimeout > 0 and app.getApplicationTimeout() == 0:
          app.setApplicationTimeout(routerTimeout)
        elif routerTimeout == 0 and app.getApplicationTimeout() > 0:
          app.setApplicationTimeout(0)

        return if shouldContinue: erContinue else: erQuit

    app.onTimeoutAsync proc(app: AsyncApp): Future[TickResult] {.async.} =
      editorCallback(editor, app, cmdLineConfig, log):
        let shouldContinue = editor.handleKeyMappingTimeout()
        editor.applyFrontendRequests(app)
        app.setApplicationTimeout(0) # One-shot: disable until next prefix match
        await editor.handlePendingAsyncOperations(frontendHooks)
        return if shouldContinue: trContinue else: trQuit

    app.onTickAsync proc(app: AsyncApp): Future[TickResult] {.async.} =
      editorCallback(editor, app, cmdLineConfig, log):
        editor.lsp.poll(0)
        editor.lsp.cleanupStaleProgress()
        await editor.handlePendingAsyncOperations(frontendHooks)
      return trContinue

    app.onRenderAsync proc(buffer: var Buffer) =
      editorCallback(editor, app, cmdLineConfig, log):
        # Execute startup window actions on first render
        if not editor.state.startUpWindowsDone:
          editor.handleStartUpWindows(buffer.area.width, buffer.area.height)

        # Poll terminal output for all windows in Terminal mode
        editor.pollTerminalWindows()

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

    try:
      # Run the async main loop
      # Note: Bracketed Paste Mode is enabled via AppConfig(bracketedPaste: true)
      await app.runAsync()
    except Exception as e:
      editor.emergencySaveAndQuit(app, e, cmdLineConfig, log)

    if not editor.config.standard.disableChangeCursor:
      # Restore cursor to default style on exit
      let cursorStyle = toCursorStyle(editor.config.standard.defaultCursor)
      app.setCursorStyle(cursorStyle)

    editor.releaseExternalResources()

    if cmdLineConfig.debugEnabled:
      # Clean up logger
      logInfo("moe", "Editor shutting down")
      log.close()

proc main() =
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

      # Open any additional files (after the first). The auto-split vs no-split
      # decision and the per-file loop live in openAdditionalStartupFiles so the
      # two paths stay in sync and the behaviour is unit-testable.
      if cmdLineConfig.filePaths.len > 1:
        editor.openAdditionalStartupFiles(
          cmdLineConfig.filePaths, cmdLineConfig.isReadonly
        )

  # Run the async editor main loop
  waitFor runEditor(editor, app, cmdLineConfig, log)

  if editor.state.exitCode != 0:
    quit(editor.state.exitCode)

when isMainModule:
  main()
