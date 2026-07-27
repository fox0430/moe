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

import types/editor_types, message_log

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

proc takeViewerEntry*(win: EditorWindow): Option[ViewerEntry] =
  ## Remove and return the viewer entry, whichever mode it belongs to.
  result = win.viewerEntry
  win.viewerEntry = none(ViewerEntry)

proc takeViewerEntry*(win: EditorWindow, mode: EditorMode): Option[ViewerEntry] =
  ## Take only when the entry belongs to `mode`, so an unrelated caller cannot
  ## strip another viewer's record.
  if win.viewerEntry.isSome and win.viewerEntry.get.mode == mode:
    win.takeViewerEntry()
  else:
    none(ViewerEntry)

proc suspendMode*(win: EditorWindow) =
  ## Suspend the current (mode, modeState) so a transient overlay (the
  ## DiffViewer opened from the BackupManager) can resume it on exit. The
  ## mode-state analogue of `saveOriginalBuffer`; mode and variant are
  ## captured together so they can never be resumed out of sync.
  if win.suspendedMode.isSome:
    addMessageLog(
      "suspendMode: overwriting existing suspension (mode=" & $win.suspendedMode.get.mode &
        ") — missing resumeMode upstream?"
    )
  win.suspendedMode = some(SuspendedMode(mode: win.mode, modeState: win.modeState))

proc takeSuspendedMode*(win: EditorWindow): Option[SuspendedMode] =
  ## Remove and return the suspended (mode, modeState), if any. The overlay
  ## exit path takes the suspension *before* `clearModeState` (which clears any
  ## leftover suspension as part of teardown) and re-installs it afterward, so
  ## the live-variant reset can never strand a suspension on the window.
  result = win.suspendedMode
  win.suspendedMode = none(SuspendedMode)

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
  ## Restore the original buffer (if any), run mode-specific cleanup, reset the
  ## `modeState` variant back to `mskNone`, and drop any overlay suspension.
  ## All side effects are gated on the variant actually matching `mode`, so
  ## callers that clear an unrelated mode do not disturb whatever state happens
  ## to be live on the window.
  ##
  ## Not for Terminal: `mskTerminal`'s PTY is owned by `Editor.terminalStates`,
  ## not by the window. Terminal teardown must go through `closeTerminalBuffer`
  ## so the map entry, PTY, and window state are dropped together — calling
  ## this proc with `EditorMode.Terminal` would strand the `terminalStates`
  ## entry (and, before it was removed, would have double-freed the PTY).
  if win.modeState.kind != modeStateKind(mode):
    return

  win.restoreOriginalBufferUnchecked()

  if win.modeState.kind == mskFileTree:
    win.fixedWidth = none(int)

  win.modeState = ModeState(kind: mskNone)

  # Drop any overlay suspension belonging to the mode being torn down so it
  # can't strand on the window. The overlay-exit path takes the suspension
  # beforehand (takeSuspendedMode), so this only fires for non-resume exits
  # (window close, buffer/tab switch, ...).
  win.suspendedMode = none(SuspendedMode)

  # Same for the viewer entry — leaveViewerMode takes it beforehand. Gated on
  # ownership so an overlay teardown (DiffViewer over BackupManager) does not
  # strip the suspended viewer's record.
  if win.viewerEntry.isSome and win.viewerEntry.get.mode == mode:
    win.viewerEntry = none(ViewerEntry)
