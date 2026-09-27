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

type WindowView* = enum
  ## What a window is currently drawing, in terms of the tab it belongs to.
  ## Naming each case makes a new view kind an exhaustiveness question
  ## instead of a silent extra branch.
  wvTabView ## The tab's own content: a text buffer, or a live terminal grid.
  wvTabSnapshot ## A frozen view of the tab's terminal scrollback (Terminal-Normal).
  wvSplitViewer
    ## A viewer's listing hosted in its own split window; the listing is the
    ## window's tab.
  wvInPlaceViewer ## A viewer's listing covering a tab's view in place.
  wvForeignMode ## A non-viewer mode (Filer, Help, ...) over a hidden tab.

proc windowViewOf(e: Editor, win: EditorWindow): WindowView =
  ## Derive what `win` draws, from `viewerEntry`, `modeState` and
  ## `terminalStates`. The only place that reads those fields together.
  if win.viewerEntry.isSome:
    return
      if win.viewerEntry.get.placement == vpInPlace: wvInPlaceViewer else: wvSplitViewer
  when defined(moe.embedded):
    if win.modeState.kind == mskNone: wvTabView else: wvForeignMode
  else:
    if e.terminalStates.hasKey(win.tabBufferId):
      if win.modeState.kind != mskTerminal:
        wvForeignMode
      elif win.modeState.terminalSubMode == tsmNormal:
        wvTabSnapshot
      else:
        wvTabView
    elif win.modeState.kind == mskNone:
      wvTabView
    else:
      wvForeignMode

proc isShowingTab*(e: Editor, win: EditorWindow, tabId: BufferId): bool =
  ## True when `win` already presents `tabId` itself, so a tab switch would
  ## only discard its position. The shared "already there" predicate for
  ## `moveWindowToTab` and the :b/:bfirst/:blast guards.
  if win.tabBufferId != tabId:
    return false
  case e.windowViewOf(win)
  of wvTabView, wvTabSnapshot:
    true
  of wvSplitViewer:
    win.viewerEntry.get.bufferId == tabId
  of wvInPlaceViewer, wvForeignMode:
    false

proc moveWindowToTab*(e: Editor, win: EditorWindow, buf: TextBuffer): bool =
  ## Move `win` onto `buf`'s tab and rebuild state owned by the old tab
  ## (Insert session, buffer-swap modes, view position, derived mode).
  ##
  ## Returns false when the window already shows `buf`'s tab itself.
  if e.isShowingTab(win, buf.id):
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
