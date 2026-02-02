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
  moepkg/
    [
      editor, handler, modes, logger, cmdline, filer, lspintegration, config,
      configloader,
    ]

proc toCursorStyle(ct: CursorType): CursorStyle =
  ## Convert config CursorType to celina CursorStyle
  case ct
  of ctTerminalDefault: CursorStyle.Default
  of ctBlinkBlock: CursorStyle.BlinkingBlock
  of ctBlinkIbeam: CursorStyle.BlinkingBar
  of ctNonBlinkBlock: CursorStyle.SteadyBlock
  of ctNonBlinkIbeam: CursorStyle.SteadyBar

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

proc lspPollingTask(editor: Editor, running: ptr bool) {.async.} =
  ## Background task for periodic LSP polling
  ## Ensures LSP messages are processed even when no user input occurs
  const pollInterval = timer.milliseconds(50)
  while running[]:
    {.cast(gcsafe).}:
      {.cast(raises: []).}:
        try:
          editor.lsp.poll(0)
          # Also cleanup stale progress entries periodically
          editor.lsp.cleanupStaleProgress()
        except:
          discard
    await sleepAsync(pollInterval)

proc runEditor(
    editor: Editor, app: AsyncApp, cmdLineConfig: CmdLineConfig, log: Logger
) {.async.} =
  ## Async entry point for the editor main loop

  # Start LSP polling background task
  var lspPollingRunning = true
  asyncSpawn lspPollingTask(editor, addr lspPollingRunning)

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

          return shouldContinue

    app.onRenderAsync proc(
        asyncBuffer: async_buffer.AsyncBuffer
    ): Future[void] {.async.} =
      {.cast(gcsafe).}:
        {.cast(raises: []).}:
          asyncBuffer.withBuffer:
            editor.render(buffer)

          # Set cursor style based on editor mode (unless disabled)
          if not editor.config.standard.disableChangeCursor:
            let cursorStyle =
              case editor.state.mode
              of EditorMode.Insert:
                toCursorStyle(editor.config.standard.insertModeCursor)
              else:
                toCursorStyle(editor.config.standard.normalModeCursor)
            setCursorStyle(cursorStyle)

          # Set cursor position and visibility
          if editor.state.cursorVisible:
            terminal.setCursorPos(
              editor.state.screenCursor.x, editor.state.screenCursor.y
            )
            terminal.showCursor()
          else:
            terminal.hideCursor()

    # Run the async main loop
    # Note: Bracketed Paste Mode is enabled via AppConfig(bracketedPaste: true)
    await app.runAsync()

    # Stop LSP polling background task
    lspPollingRunning = false

    # Restore cursor to default style on exit
    if not editor.config.standard.disableChangeCursor:
      let cursorStyle = toCursorStyle(editor.config.standard.defaultCursor)
      terminal.setCursorStyle(cursorStyle)

    # Cleanup background processes before exiting
    cleanupBackgroundProcesses()

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

  # Create async app with config-based mouse setting
  let appConfig = AppConfig(
    title: "moe",
    alternateScreen: true,
    mouseCapture: editor.config.standard.mouse,
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
      activeWin.filerState = some(newFilerState(dirPath))
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
