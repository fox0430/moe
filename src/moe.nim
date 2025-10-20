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

import std/[strformat, monotimes, times]

import pkg/[celina, results]

import moepkg/[editor, handler, modes, logger, cmdline]

proc handleResize(e: Editor) =
  ## Debounce resize events to prevent terminal buffer overflow
  ## Only process if at least 50ms have passed since last resize
  const resizeDebounceMs = initDuration(milliseconds = 50)
  let
    now = getMonoTime()
    timeSinceLastResize = now - e.state.lastResizeTime

  if timeSinceLastResize < resizeDebounceMs:
    # Too soon after last resize, skip processing
    return

  # Update last resize time
  e.state.lastResizeTime = now

  # Physically clear the terminal screen to remove artifacts
  clearScreen()
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
      mouseCapture: false,
      rawMode: true,
      windowMode: false,
    )
  )

  let editor = newEditor()

  if config.filePath.len > 0:
    block:
      let r = editor.loadFile(config.filePath)
      if r.isErr:
        echo fmt"Error: {r.error}"
        quit(1)

  app.onEvent proc(e: Event): bool =
    if e.kind == EventKind.Resize:
      # Special handling for resize events to force screen clear
      editor.handleResize
      return true

    return editor.handleEvent(e)

  app.onRender proc(b: var Buffer) =
    # Update editor view
    editor.render(b)

    # Set cursor style based on editor mode
    case editor.state.mode
    of EditorMode.Insert:
      app.setCursorStyle(CursorStyle.SteadyBar)
    else:
      app.setCursorStyle(CursorStyle.SteadyBlock)

    # Set cursor position from calculated screen coordinates
    app.setCursor(editor.state.screenCursor.x, editor.state.screenCursor.y)

  app.run()

  # Clean up logger
  if config.debugEnabled:
    logInfo("moe", "Editor shutting down")
    log.close()

when isMainModule:
  main()
