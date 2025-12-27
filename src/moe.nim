#[###################### GNU General Public License 3.0 ######################]#
#                                                                              #
#  Copyright (C) 2017─2025 Shuhei Nogawa                                       #
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

import pkg/[celina, results]

import moepkg/[editor, handler, modes, logger, cmdline, filer, lspintegration, config]

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

proc main() =
  # Parse command line arguments
  let config = parseCmdLine()

  # Initialize file logging system for debugging
  let log = initLogger(LogLevel.Debug, enabled = config.debugEnabled)
  setGlobalLogger(log)
  if config.debugEnabled:
    logInfo("moe", "Editor starting with debug logging enabled")

  var app = newApp(
    AppConfig(
      title: "moe",
      alternateScreen: true,
      mouseCapture: true,
      rawMode: true,
      windowMode: false,
    )
  )

  var editor = newEditor()
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

  if config.filePaths.len > 0:
    # Check if first path is a directory
    if config.filePaths.len == 1 and dirExists(config.filePaths[0]):
      # Directory specified - start in Filer mode
      let dirPath = absolutePath(config.filePaths[0])
      editor.state.mode = EditorMode.Filer
      editor.state.filerState = some(newFilerState(dirPath))
    else:
      # Load first file
      block:
        let r = editor.loadFile(config.filePaths[0])
        if r.isErr:
          echo fmt"Error: {r.error}"
          quit(1)
        # Apply readonly mode if specified
        if config.isReadonly:
          editor.activeBuffer().readOnly = true

      # Load additional files with auto-split if enabled
      if config.filePaths.len > 1 and editor.config.startUpFileOpen.autoSplit:
        for i in 1 ..< config.filePaths.len:
          let filePath = config.filePaths[i]
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
            elif config.isReadonly:
              editor.activeBuffer().readOnly = true
      elif config.filePaths.len > 1:
        # No auto-split, just load files into buffer list
        for i in 1 ..< config.filePaths.len:
          let filePath = config.filePaths[i]
          if fileExists(filePath):
            discard editor.loadFile(filePath)
            if config.isReadonly:
              editor.activeBuffer().readOnly = true

  app.onEvent proc(e: Event, app: App): bool =
    if e.kind == EventKind.Resize:
      # Special handling for resize events to force screen clear
      editor.handleResize
      return true

    return editor.handleEvent(e)

  app.onRender proc(b: var Buffer) =
    # Update editor view
    editor.render(b)

    # Set cursor style based on editor mode (unless disabled)
    if not editor.config.standard.disableChangeCursor:
      case editor.state.mode
      of EditorMode.Insert:
        app.setCursorStyle(toCursorStyle(editor.config.standard.insertModeCursor))
      else:
        app.setCursorStyle(toCursorStyle(editor.config.standard.normalModeCursor))

    # Set cursor position from calculated screen coordinates
    app.showCursorAt(editor.state.screenCursor.x, editor.state.screenCursor.y)

  app.run()

  # Restore cursor to default style on exit
  if not editor.config.standard.disableChangeCursor:
    # Write ANSI escape sequence directly to restore cursor
    let cursorStyle = toCursorStyle(editor.config.standard.defaultCursor)
    let escSeq =
      case cursorStyle
      of CursorStyle.Default: "\e[0 q"
      of CursorStyle.BlinkingBlock: "\e[1 q"
      of CursorStyle.SteadyBlock: "\e[2 q"
      of CursorStyle.BlinkingUnderline: "\e[3 q"
      of CursorStyle.SteadyUnderline: "\e[4 q"
      of CursorStyle.BlinkingBar: "\e[5 q"
      of CursorStyle.SteadyBar: "\e[6 q"
    stdout.write(escSeq)
    stdout.flushFile()

  # Shutdown LSP servers before exiting
  editor.shutdown()

  # Save all persist data (search history, command history, cursor positions)
  editor.savePersistData()

  # Clean up logger
  if config.debugEnabled:
    logInfo("moe", "Editor shutting down")
    log.close()

when isMainModule:
  main()
