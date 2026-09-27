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
#  GNU General Public License for more details.                                 #
#                                                                              #
#  You should have received a copy of the GNU General Public License           #
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.      #
#                                                                              #
#[############################################################################]#

## What a window's tab makes it show and how it moves between tabs.
##
## `moveWindowToTab` is the single procedure that repoints a window at another
## tab and rebuilds the mode state the old tab owned. `deriveTabMode` rebuilds
## only the mode, for a window whose tab is already in place: a new split, or a
## viewer resuming after its tab moved underneath it.

import std/options

import types/editor_types, editor_mode, editor_window_state

when not defined(moe.embedded):
  import std/tables

when not defined(moe.embedded):
  proc syncTerminalView*(e: Editor, win: EditorWindow) =
    ## What a Terminal window shows, derived from its sub-mode. The only place
    ## that decides it, so the two cannot drift apart.
    if win.modeState.kind != mskTerminal:
      return
    case win.modeState.terminalSubMode
    of tsmNormal:
      win.setView(win.modeState.scrollbackSnapshot)
    of tsmInput:
      # View is only for the status line/tab list; `renderTerminal` draws the grid.
      win.setView(e.tabBuffer(win))

proc applyTabMode(e: Editor, win: EditorWindow, tabId: BufferId) =
  when not defined(moe.embedded):
    let session = e.terminalStates.getOrDefault(tabId)
    if session != nil:
      # First arrival starts live; staying keeps the browsing state.
      if win.modeState.kind != mskTerminal or win.modeState.terminal != session:
        win.modeState = ModeState(kind: mskTerminal, terminal: session)
      win.mode = EditorMode.Terminal
      e.syncTerminalView(win)
      return
  if win.mode == EditorMode.Terminal:
    win.modeState = ModeState(kind: mskNone)
    win.mode = EditorMode.Normal

proc deriveTabMode*(e: Editor, win: EditorWindow) =
  ## Terminal exactly when the tab is a session. Call only when no viewer
  ## holds the window.
  e.applyTabMode(win, win.tabBufferId)

proc modeMatchesTab(e: Editor, win: EditorWindow, tabId: BufferId): bool =
  ## True when the mode state matches the tab. A match means the window shows
  ## the tab itself, so re-moving would only discard its position.
  when defined(moe.embedded):
    win.modeState.kind == mskNone
  else:
    if e.terminalStates.hasKey(tabId):
      win.modeState.kind == mskTerminal
    else:
      win.modeState.kind == mskNone

proc moveWindowToTab*(e: Editor, win: EditorWindow, buf: TextBuffer): bool =
  ## Move `win` onto `buf`'s tab and rebuild state owned by the old tab
  ## (Insert session, buffer-swap modes, view position, derived mode).
  ##
  ## Returns false without moving when already on `buf`'s tab with no mode
  ## holding a different view.
  if win.tabBufferId == buf.id and win.viewerEntry.isNone and
      e.modeMatchesTab(win, buf.id):
    return false

  let isActiveWindow = win == e.activeWindow
  # Only the active window owns the global Insert session.
  if isActiveWindow:
    e.finalizeInsertSessionForBufferSwitch(win.buffer)

  # Null `originalBuffer` first to skip its restore. Terminal state stays in
  # `e.terminalStates`; never `cleanup()` it here.
  win.originalBuffer = nil
  # Drop both records: an overlay could strand the other mode's state.
  discard win.takeViewerEntry()
  discard win.takeSuspendedMode()
  let wasSpecialMode =
    when defined(moe.embedded):
      win.modeState.kind != mskNone
    else:
      win.modeState.kind != mskNone and win.modeState.kind != mskTerminal
  if wasSpecialMode:
    win.clearModeState(win.mode)

  win.setTab(buf)
  win.cursor = BufferPosition(line: 0, column: 0)
  win.viewport.resetViewportTop()
  win.viewport.leftColumn = 0

  e.applyTabMode(win, buf.id)
  if wasSpecialMode and win.mode != EditorMode.Terminal:
    # `clearModeState` leaves `win.mode` alone; reset `win` directly so a
    # background window doesn't stick in a special mode.
    win.mode = EditorMode.Normal

  # Re-apply forceInsertMode for the active window only.
  if isActiveWindow:
    e.enforceModePolicy()

  true
