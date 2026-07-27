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

## Entry/exit for the read-only listing modes (Filer, BufferManager,
## BookmarkManager, References, DocumentSymbol, CallHierarchy, Help, LogViewer,
## BackupManager, Debug, Config, RecentFile). Entry records placement and the
## displaced cursor/viewport in `EditorWindow.viewerEntry`; exit replays it.
##
## Not covered: Terminal (owned by `Editor.terminalStates`), FileTree (toggled
## sidebar) and DiffViewer (uses `suspendMode`).

import std/options

import pkg/results

import
  types/editor_types,
  editor_window,
  editor_window_state,
  editor_buffers,
  git_cache,
  buffer,
  window_manager

proc closeViewerSplit(e: Editor, entry: ViewerEntry) =
  ## Discard the scratch buffer and close the split. When it is the only window,
  ## open an empty buffer instead so the user is not stranded on a read-only
  ## listing. The buffer id comes from the entry because refreshing viewers
  ## (log, backup, debug) may have swapped in an unregistered buffer.
  let singleWindow = e.windowManager.windows.len <= 1
  let idx = e.bufferIndexById(entry.bufferId)
  if idx >= 0:
    e.state.git.evictGitCacheForBuffer(e.buffers[idx])
    e.deleteBufferAt(idx)
    e.pruneBufferIdFromAllWindows(entry.bufferId)
  if singleWindow:
    discard e.enew()
  else:
    discard e.closeWindow()

proc resetViewerViewport(win: EditorWindow) =
  win.cursor = BufferPosition(line: 0, column: 0)
  win.viewport.resetViewportTop()
  win.viewport.leftColumn = 0

proc applyViewerUndo(
    e: Editor, win: EditorWindow, entry: ViewerEntry, restorePosition: bool
) =
  ## Reverse the placement: restore the displaced cursor/viewport or close the
  ## split. Jumping exits pass `restorePosition = false` and place the cursor
  ## themselves. The snapshot is clamped since the restored buffer may have
  ## shrunk (external reload, `:e!` from inside the viewer).
  case entry.placement
  of vpInPlace:
    if restorePosition:
      let lastLine = max(0, win.buffer.len - 1)
      let line = min(entry.originCursor.line, lastLine)
      let lineLen =
        if win.buffer.len > 0:
          win.buffer.getLine(line).charLen
        else:
          0
      win.cursor =
        BufferPosition(line: line, column: min(entry.originCursor.column, lineLen))
      win.viewport.restoreViewportTop(
        min(entry.originTopLine, lastLine), entry.originTopWrapOffset
      )
      win.viewport.leftColumn = entry.originLeftColumn
  of vpVSplit, vpHSplit:
    e.closeViewerSplit(entry)

proc closeLiveViewer*(e: Editor) =
  ## Tear down whichever viewer is live in the active window (no-op if none)
  ## and restore its returnMode. A split placement closes the active window, so
  ## callers must re-read `Editor.activeWindow` afterwards.
  let win = e.activeWindow
  let entry = win.takeViewerEntry()
  if entry.isNone:
    return
  win.clearModeState(entry.get.mode)
  e.applyViewerUndo(win, entry.get, restorePosition = true)
  if e.activeWindow == win:
    # Only when the window survived — a closed split leaves a neighbour that
    # was never in the viewer mode.
    e.setMode(entry.get.returnMode)

proc enterViewerMode*(
    e: Editor,
    mode: EditorMode,
    modeState: ModeState,
    buffer: TextBuffer,
    placement: ViewerPlacement,
): Result[void, string] =
  ## Show `buffer` as `mode`'s listing. `vpInPlace` swaps the active window's
  ## buffer and snapshots the displaced cursor; splits open a new window.
  ## Re-entering the same mode (CallHierarchy incoming/outgoing) keeps the
  ## original snapshot; a *different* in-place viewer is torn down first.
  ## Fails only when a split cannot be created.
  if placement == vpInPlace:
    # Peel any foreign viewer off the active window first. A split-placed
    # teardown may shift focus to a survivor also running a viewer, so loop.
    while true:
      let active = e.activeWindow
      if active.viewerEntry.isNone:
        break
      if active.viewerEntry.get.mode == mode and
          active.modeState.kind == modeStateKind(mode):
        break
      e.closeLiveViewer()

    let win = e.activeWindow
    let reentering =
      win.viewerEntry.isSome and win.viewerEntry.get.mode == mode and
      win.modeState.kind == modeStateKind(mode)
    if not reentering:
      win.viewerEntry = some(
        ViewerEntry(
          mode: mode,
          placement: vpInPlace,
          returnMode: win.mode,
          bufferId: buffer.id,
          originCursor: win.cursor,
          originTopLine: win.viewport.topLine,
          originTopWrapOffset: win.viewport.topWrapOffset,
          originLeftColumn: win.viewport.leftColumn,
        )
      )
      win.saveOriginalBuffer()
    e.state.previousMode = win.viewerEntry.get.returnMode
    win.buffer = buffer
    win.resetViewerViewport()
    win.modeState = modeState
    e.setMode(mode)
    return ok()

  # Capture returnMode before the split — the new window starts in Normal.
  let returnMode = e.state.mode
  let splitResult =
    if placement == vpVSplit:
      e.vsplitWithBuffer(buffer)
    else:
      e.hsplitWithBuffer(buffer)
  if splitResult.isErr:
    return err(splitResult.error)

  e.state.previousMode = returnMode
  let win = e.activeWindow
  win.viewerEntry = some(
    ViewerEntry(
      mode: mode, placement: placement, returnMode: returnMode, bufferId: buffer.id
    )
  )
  win.resetViewerViewport()
  win.modeState = modeState
  e.setMode(mode)
  ok()

proc focusExistingViewerWindow*(e: Editor, mode: EditorMode): bool =
  ## Activate an already-open viewer window in `mode`; false when none exists.
  ## Used by split viewers to focus instead of stacking a duplicate.
  for i, win in e.windowManager.windows:
    if win.viewerEntry.isSome and win.viewerEntry.get.mode == mode:
      e.windowManager.activateWindow(i)
      e.syncActiveWindow()
      return true
  false

proc tearDownViewer(
    e: Editor, mode: EditorMode, nextMode: Option[EditorMode], restorePosition: bool
): Option[ViewerEntry] =
  ## Shared exit. The record is taken only when it belongs to `mode` so an
  ## unrelated caller cannot consume it (no mode switch either in that case).
  ## `nextMode = none` falls back to `entry.returnMode` (round-trips Visual).
  ## The mode switch runs only if the window survived — a closed split leaves
  ## a neighbour that was never in `mode`.
  let win = e.activeWindow
  result = win.takeViewerEntry(mode)
  win.clearModeState(mode)
  if result.isNone:
    return
  e.applyViewerUndo(win, result.get, restorePosition)
  if e.activeWindow == win:
    e.setMode(if nextMode.isSome: nextMode.get else: result.get.returnMode)

proc leaveViewerMode*(e: Editor, mode: EditorMode) =
  ## Undo `enterViewerMode`, returning to `viewerEntry.returnMode`.
  discard e.tearDownViewer(mode, none(EditorMode), restorePosition = true)

proc leaveViewerModeForJump*(e: Editor, mode: EditorMode): Option[ViewerEntry] =
  ## Exit to Normal without restoring the cursor; the caller places it. Returns
  ## the entry so the jump list can be anchored at the origin position.
  e.tearDownViewer(mode, some(EditorMode.Normal), restorePosition = false)
