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

import std/[strformat, monotimes, times, os, options]

import pkg/[celina, results, chronos]

import
  moepkg/[
    editor, handler, modes, logger, cmdline, filer, lsp_integration, config,
    config_loader,
  ]

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
  for i, window in e.windowManager.windows:
    if window.mode == EditorMode.Terminal and window.terminalState.isSome:
      let termState = window.terminalState.get
      if termState.subMode == tsmInput:
        # Resize terminal if window dimensions changed
        let (expectedCols, expectedRows) = e.calculateTerminalAreaDimensions(window)
        if expectedCols != termState.grid.cols or expectedRows != termState.grid.rows:
          if expectedCols > 0 and expectedRows > 0:
            termState.resize(expectedCols, expectedRows)
            e.state.needsFullRedraw = true

        let updated = termState.pollOutput()
        if updated:
          e.state.needsFullRedraw = true

        if termState.exitCode.isSome:
          if termState.command.len > 0:
            # Command mode (e.g. `:terminal ls`): show output in scrollback view
            let snapshot = termState.enterNormalSubMode()
            window.buffer = snapshot
            window.cursor = BufferPosition(line: max(0, snapshot.len - 1), column: 0)
            window.viewport.topLine = max(0, snapshot.len - window.viewport.height)
          else:
            # Interactive shell (`:terminal`): close terminal window
            window.clearModeState(EditorMode.Terminal)
            if e.windowManager.windows.len > 1:
              # Multiple windows: close the terminal window
              let origActive = e.windowManager.activeWindowIndex
              e.windowManager.activeWindowIndex = i
              discard e.windowManager.closeWindow(e.state.display.multiStatusLine)
              if origActive != i:
                e.windowManager.activeWindowIndex =
                  if origActive > i:
                    origActive - 1
                  else:
                    origActive
              e.syncActiveWindow()
              e.setMode(e.activeWindow.mode)
            else:
              # Last window: return to Normal mode
              window.mode = EditorMode.Normal
              e.setMode(EditorMode.Normal)
          e.state.needsFullRedraw = true
          return

proc handleResize(e: Editor) =
  ## Debounce resize events to prevent terminal buffer overflow
  ## Only process if at least 50ms have passed since last resize
  const resizeDebounceMs = initDuration(milliseconds = 50)
  let
    now = getMonoTime()
    timeSinceLastResize = now - e.state.timing.lastResizeTime

  if timeSinceLastResize < resizeDebounceMs:
    # Too soon after last resize, skip processing
    return

  # Update last resize time
  e.state.timing.lastResizeTime = now

  # Physically clear the terminal screen to remove artifacts
  terminal.clearScreen()
  # Set the editor's full redraw flag
  e.state.needsFullRedraw = true

proc runEditor(
    editor: Editor, app: AsyncApp, cmdLineConfig: CmdLineConfig, log: Logger
) {.async.} =
  ## Async entry point for the editor main loop

  {.cast(gcsafe).}:
    app.onEventAsync proc(e: Event, app: AsyncApp): Future[bool] {.async.} =
      {.cast(gcsafe).}:
        {.cast(raises: []).}:
          if e.kind == EventKind.Resize:
            # Special handling for resize events to force screen clear
            editor.handleResize
            return true

          let shouldContinue = editor.handleEvent(e)

          # Handle pending async operations (shell commands, :bg)
          if editor.hasPendingAsyncOperations():
            try:
              await editor.handlePendingAsyncOperations()
            except Exception as e:
              logError("moe", "handlePendingAsyncOperations failed: " & e.msg)

          # Key mapping timeout control
          if editor.keyBindingRegistry.runtimeMappingState.keys.len > 0:
            let tl = editor.config.standard.timeoutlen
            if tl > 0 and app.getApplicationTimeout() == 0:
              app.setApplicationTimeout(tl)
          elif app.getApplicationTimeout() > 0:
            app.setApplicationTimeout(0)

          return shouldContinue

    app.onTimeoutAsync proc(app: AsyncApp): Future[bool] {.async.} =
      {.cast(gcsafe).}:
        {.cast(raises: []).}:
          editor.handleKeyMappingTimeout()
          app.setApplicationTimeout(0) # One-shot: disable until next prefix match
          return true

    app.onTickAsync proc(app: AsyncApp): Future[bool] {.async.} =
      {.cast(gcsafe).}:
        {.cast(raises: []).}:
          editor.lsp.poll(0)
          editor.lsp.cleanupStaleProgress()
      return true

    app.onRenderAsync proc(buffer: var Buffer) =
      {.cast(gcsafe).}:
        {.cast(raises: []).}:
          # Poll terminal output for all windows in Terminal mode
          editor.pollTerminalWindows()

          editor.render(buffer)

          # Set cursor style based on editor mode (unless disabled)
          if not editor.config.standard.disableChangeCursor:
            let cursorStyle =
              case editor.state.mode
              of EditorMode.Insert:
                toCursorStyle(editor.config.standard.insertModeCursor)
              else:
                toCursorStyle(editor.config.standard.normalModeCursor)
            app.setCursorStyle(cursorStyle)

          # Set cursor position and visibility
          if editor.state.cursorVisible:
            app.setCursorPosition(
              editor.state.screenCursor.x, editor.state.screenCursor.y
            )
            app.showCursor()
          else:
            app.hideCursor()

    # Run the async main loop
    # Note: Bracketed Paste Mode is enabled via AppConfig(bracketedPaste: true)
    await app.runAsync()

    # Restore cursor to default style on exit
    if not editor.config.standard.disableChangeCursor:
      let cursorStyle = toCursorStyle(editor.config.standard.defaultCursor)
      app.setCursorStyle(cursorStyle)

    # Cleanup background processes before exiting
    editor.cleanupBackgroundProcesses()

    # Shutdown LSP servers before exiting
    editor.shutdown()

    # Save all persist data
    editor.savePersistData()

    # Clean up logger
    if cmdLineConfig.debugEnabled:
      logInfo("moe", "Editor shutting down")
      log.close()

proc main() =
  # Parse command line arguments
  let cmdLineConfig = parseCmdLine()

  # Initialize file logging system for debugging
  let log = initLogger(LogLevel.Debug, enabled = cmdLineConfig.debugEnabled)
  setGlobalLogger(log)
  if cmdLineConfig.debugEnabled:
    logInfo("moe", "Editor starting with debug logging enabled")

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

  # Create editor with loaded configuration and validation result
  var editor = newEditor(editorConfig, validationResult)

  # Always capture mouse events so the terminal doesn't convert wheel events
  # to arrow key sequences. When mouse is disabled in config, events are
  # ignored in handleMouseEvent instead.
  let appConfig = AppConfig(
    title: "moe",
    alternateScreen: true,
    mouseCapture: true,
    rawMode: true,
    windowMode: false,
    bracketedPaste: true,
  )
  var app = newAsyncApp(appConfig)
  editor.app = app

  # Set up LSP diagnostics callback to update buffer markers
  editor.lsp.setDiagnosticsCallback(
    proc(uri: string, diagnostics: seq[Diagnostic]) {.gcsafe.} =
      # Find the buffer with this URI and apply diagnostics
      let path = uriToPath(uri).absolutePath()
      let activeBuffer = editor.activeBuffer()
      if activeBuffer.filePath.isSome and
          activeBuffer.filePath.get.absolutePath() == path:
        applyDiagnosticsToBuffer(activeBuffer, diagnostics)
        editor.state.needsFullRedraw = true
  )

  if cmdLineConfig.filePaths.len > 0:
    # Check if first path is a directory
    if cmdLineConfig.filePaths.len == 1 and dirExists(cmdLineConfig.filePaths[0]):
      # Directory specified - start in Filer mode
      let dirPath = absolutePath(cmdLineConfig.filePaths[0])
      editor.state.mode = EditorMode.Filer
      let activeWin =
        editor.windowManager.windows[editor.windowManager.activeWindowIndex]
      activeWin.mode = EditorMode.Filer
      let filerState = newFilerState(dirPath)
      filerState.originalBuffer = activeWin.buffer
      activeWin.filerState = some(filerState)
      activeWin.buffer = filerState.createFilerTextBuffer(editor.config.filer.showIcons)
      activeWin.cursor = BufferPosition(line: 0, column: 0)
      activeWin.viewport.topLine = 0
      activeWin.viewport.leftColumn = 0
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

      # Load additional files with auto-split if enabled
      if cmdLineConfig.filePaths.len > 1 and editor.config.startUpFileOpen.autoSplit:
        for i in 1 ..< cmdLineConfig.filePaths.len:
          let filePath = cmdLineConfig.filePaths[i]
          if fileExists(filePath):
            # Split based on config
            let splitResult =
              case editor.config.startUpFileOpen.splitType
              of stVertical:
                editor.vsplit(some(filePath))
              of stHorizontal:
                editor.hsplit(some(filePath))
            if splitResult.isErr:
              logError("moe", fmt"Failed to split for {filePath}: {splitResult.error}")
            elif cmdLineConfig.isReadonly:
              editor.activeBuffer().readOnly = true
      elif cmdLineConfig.filePaths.len > 1:
        # No auto-split, just load files into buffer list
        for i in 1 ..< cmdLineConfig.filePaths.len:
          let filePath = cmdLineConfig.filePaths[i]
          if fileExists(filePath):
            discard editor.loadFile(filePath)
            if cmdLineConfig.isReadonly:
              editor.activeBuffer().readOnly = true

  # Run the async editor main loop
  waitFor runEditor(editor, app, cmdLineConfig, log)

when isMainModule:
  main()
