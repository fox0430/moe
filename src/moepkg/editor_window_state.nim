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

## Per-window mode state lifecycle: resets the `modeState` variant on
## `EditorWindow` back to `mskNone`. Viewers keep what they covered in their
## `ViewerEntry`, and the DiffViewer the backup manager it came from in its
## own variant.

import std/options

import types/editor_types

proc isSidebar*(win: EditorWindow): bool =
  ## The FileTree pane. Its width is what marks it: a mode switch over it
  ## changes `mode` and `modeState` but not that. It has no tab of its own.
  win.fixedWidth.isSome

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

proc dropModeState*(win: EditorWindow) =
  ## Run the live variant's cleanup and reset it back to `mskNone`, whatever
  ## mode the window claims: a mode switch over a viewer flips only the mode.
  ## For the owner of the window's state (a viewer ending, a tab switch).
  ##
  ## Not for Terminal: `mskTerminal`'s PTY is owned by `Editor.terminalStates`,
  ## not by the window. Terminal teardown must go through `closeTerminalBuffer`
  ## so the map entry, PTY, and window state are dropped together.
  if win.modeState.kind == mskFileTree:
    win.fixedWidth = none(int)
  win.modeState = ModeState(kind: mskNone)

proc clearModeState*(win: EditorWindow, mode: EditorMode) =
  ## `dropModeState` plus `mode`'s viewer entry, gated on the variant actually
  ## matching `mode` so callers that clear an unrelated mode do not disturb
  ## whatever state happens to be live on the window. Not for Terminal either
  ## (see `dropModeState`).
  if win.modeState.kind != modeStateKind(mode):
    return

  win.dropModeState()

  # Drop the viewer entry too; leaveViewerMode takes it beforehand. Gated on
  # ownership so a DiffViewer teardown does not strip the backup manager's
  # record.
  if win.viewerEntry.isSome and win.viewerEntry.get.mode == mode:
    win.viewerEntry = none(ViewerEntry)
