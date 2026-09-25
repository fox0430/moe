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

## The window a background command writes its output into.

import std/strutils

import pkg/results

import
  types/editor_types,
  editor_buffers,
  editor_hooks,
  editor_mode,
  editor_notify,
  editor_window,
  buffer,
  highlight_config,
  modes,
  window_manager

proc focusOutputWindow(
    editor: Editor, target: EditorWindow, mode, previousMode: EditorMode
) =
  ## Move the focus to `target` and leave the editor in `mode`.
  ## Unlike `hsplitWithBuffer`, reusing a window does not activate it.
  for i, window in editor.windowManager.windows:
    if window == target:
      editor.windowManager.activateWindow(i)
      # Sync first: `state.activeWindow` is cached, so `previousMode` would
      # otherwise land on the window just left.
      editor.syncActiveWindow()
      editor.setMode(mode)
      editor.state.previousMode = previousMode
      editor.setActiveWindowScreenCursor(editor.activeWindow)
      break

proc showCommandOutput*(
    editor: Editor, output: seq[string], keepFocus: bool
): bool {.discardable.} =
  ## Show the output of a background command (build, QuickRun, hook) and report
  ## whether the window could be opened. One window is reused for all of them,
  ## since `buildOnSave` and hooks fire as often as the user writes.
  ##
  ## `keepFocus` keeps the focus and mode on the user's window, for a command
  ## they did not start; an explicit `:QuickRun` or `:build` follows its
  ## output.
  let outputBuffer = newTextBuffer(output.join("\n"))
  outputBuffer.readOnly = true

  let staleIdx = editor.bufferIndexById(editor.state.commandOutputBufferId)
  if staleIdx >= 0:
    let stale = editor.buffers[staleIdx]
    var outputWindow: EditorWindow = nil
    for window in editor.windowManager.windows:
      if window.buffer == stale:
        outputWindow = window
        break
    if not outputWindow.isNil:
      discard editor.removeBufferAt(staleIdx)
      editor.addBuffer(outputBuffer)
      applyHighlightConfig(outputBuffer, editor.config)
      editor.redirectWindowsFromBuffer(stale, outputBuffer)
      editor.state.commandOutputBufferId = outputBuffer.id
      editor.syncActiveWindow()
      if not keepFocus:
        editor.focusOutputWindow(outputWindow, EditorMode.Normal, EditorMode.Normal)
      editor.enforceModePolicy()
      return true
    else:
      # The window is gone but its buffer is still listed; drop it, or every
      # close-split-then-run cycle strands another one.
      discard editor.removeBufferAt(staleIdx)
      editor.state.commandOutputBufferId = BufferId(0)

  let
    previousWindow = editor.activeWindow
    previousMode = editor.state.mode
    previousPreviousMode = editor.state.previousMode
  let splitResult = editor.hsplitWithBuffer(outputBuffer)
  if splitResult.isErr:
    editor.notify("Failed to open output window: " & splitResult.error, nlError)
    return false
  editor.state.commandOutputBufferId = outputBuffer.id

  if keepFocus:
    editor.focusOutputWindow(previousWindow, previousMode, previousPreviousMode)
  editor.enforceModePolicy()
  true

hookOutputPresenter = proc(e: Editor, output: seq[string]) =
  # A hook fires on its own, so the user's focus and mode stay.
  e.showCommandOutput(output, keepFocus = true)
