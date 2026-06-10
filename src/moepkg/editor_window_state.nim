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

## Per-window mode state lifecycle.
## Restores the original buffer for modes that swap the window buffer
## (Filer, BufferManager, Terminal, ...) and resets the `modeState`
## variant on `EditorWindow` back to `mskNone`.

import std/options

import types/editor_types, terminal_mode, message_log

proc saveOriginalBuffer*(win: EditorWindow) =
  ## Stash the current buffer as `originalBuffer` so a later mode exit can
  ## restore it. Logs a warning if a previous save is still live — that
  ## means an upstream mode transition skipped `clearModeState` and the
  ## prior original is about to be lost.
  if win.originalBuffer != nil:
    addMessageLog(
      "saveOriginalBuffer: overwriting existing originalBuffer " & "(modeState.kind=" &
        $win.modeState.kind & ") — missing clearModeState upstream?"
    )
  win.originalBuffer = win.buffer

proc restoreOriginalBufferUnchecked(win: EditorWindow) =
  if win.originalBuffer != nil:
    win.buffer = win.originalBuffer
    win.originalBuffer = nil

proc restoreOriginalBuffer*(win: EditorWindow, mode: EditorMode) =
  ## Restore the saved buffer (if any) for modes that replace the window
  ## buffer on entry. No-op when the live ModeState variant does not match
  ## `mode` (defensive against unmatched callers) or when no buffer was
  ## saved (modes that open their own split window — Help, LogViewer,
  ## BackupManager, Debug, Config, RecentFile, FileTree).
  if win.modeState.kind != modeStateKind(mode):
    return
  win.restoreOriginalBufferUnchecked()

proc clearModeState*(win: EditorWindow, mode: EditorMode) =
  ## Restore the original buffer (if any), run mode-specific cleanup, and
  ## reset the `modeState` variant back to `mskNone`. All side effects
  ## are gated on the variant actually matching `mode`, so callers that
  ## clear an unrelated mode do not disturb whatever state happens to be
  ## live on the window.
  if win.modeState.kind != modeStateKind(mode):
    return

  win.restoreOriginalBufferUnchecked()

  # Snapshot the Terminal's PTY owner before touching the variant. The reset
  # to `mskNone` below must not be gated behind PTY teardown: resetting first
  # keeps the window consistent even if `cleanup` ever starts to fail, and the
  # local ref keeps the TerminalState alive until cleanup runs.
  let term = if win.modeState.kind == mskTerminal: win.modeState.terminal else: nil

  if win.modeState.kind == mskFileTree:
    win.fixedWidth = none(int)

  win.modeState = ModeState(kind: mskNone)

  # Terminal owns a PTY that must be cleaned up before the ref is dropped.
  if term != nil:
    term.cleanup()
