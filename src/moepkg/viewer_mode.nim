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
## BackupManager, Debug, Config, RecentFile). Entry records placement, the
## covered mode and the displaced cursor/viewport in `EditorWindow.viewerEntry`;
## exit replays it.
##
## Not covered: Terminal (owned by `Editor.terminalStates`), FileTree (toggled
## sidebar) and DiffViewer (opened over the backup manager, which it holds in
## its own variant).

import std/options

import pkg/results

import
  types/editor_types,
  editor_window,
  editor_window_state,
  editor_window_tab,
  buffer,
  window_manager

proc mainWindowCount(e: Editor): int =
  for win in e.windowManager.windows:
    if not win.isSidebar:
      inc result

proc tabBesideLoneSidebar(e: Editor): Option[TextBuffer] =
  ## What a window opened beside a lone sidebar shows: the last opened buffer.
  if e.buffers.len > 0:
    some(e.buffers[^1])
  else:
    none(TextBuffer)

proc commandTab*(e: Editor): TextBuffer =
  ## The tab a command typed in the active window is about. The FileTree
  ## sidebar has none; from it, the tab of the window `leaveSidebar` goes to.
  let win = e.activeWindow
  if not win.isSidebar:
    return e.tabBuffer(win)
  let target = e.sidebarTarget()
  if target >= 0:
    return e.tabBuffer(e.windowManager.windows[target])
  e.tabBesideLoneSidebar().get(e.tabBuffer(win))

proc leaveSidebar*(e: Editor): Result[bool, string] =
  ## A viewer covers a tab, which the FileTree sidebar does not have. From the
  ## sidebar, move to the window it opens files in, or open one beside it when
  ## it is alone; true when it opened one. No-op elsewhere.
  if not e.activeWindow.isSidebar:
    return ok(false)
  let target = e.sidebarTarget()
  if target >= 0:
    e.windowManager.activateWindow(target)
    e.syncActiveWindow()
    return ok(false)
  let tab = e.tabBesideLoneSidebar()
  if tab.isNone:
    return err("no buffer to open a window on")
  ?e.openWindowBesideSidebar(tab.get)
  ok(true)

proc resetViewerViewport(win: EditorWindow) =
  win.cursor = BufferPosition(line: 0, column: 0)
  win.viewport.resetViewportTop()
  win.viewport.leftColumn = 0

proc restoreViewerPosition(e: Editor, win: EditorWindow, entry: ViewerEntry) =
  ## Clamped for the resumed mode since the buffer may have shrunk (external
  ## reload, `:e!` from inside the viewer).
  let origin = e.viewerOrigin(entry, win.buffer, e.state.mode)
  win.cursor = origin.cursor
  win.viewport.restoreViewportTop(origin.topLine, entry.originTopWrapOffset)
  win.viewport.leftColumn = entry.originLeftColumn

proc resumeCoveredMode(
    e: Editor, win: EditorWindow, entry: ViewerEntry, textMode: Option[EditorMode]
) =
  ## Put back the (mode, modeState) the viewer covered, the view they show, then
  ## its position. Once the tab has moved (`:bd`, the shell exiting) nothing is
  ## left to put back, so derive from the new tab instead.
  if win.tabBufferId != entry.returnTab:
    win.modeState = ModeState(kind: mskNone)
    e.setMode(EditorMode.Normal)
    e.deriveTabMode(win)
    e.syncTabView(win)
    win.resetViewerViewport()
    return

  win.modeState = entry.returnState
  e.setMode(
    if textMode.isSome and entry.returnState.kind == mskNone:
      textMode.get
    else:
      entry.returnMode
  )
  e.syncTabView(win)
  e.restoreViewerPosition(win, entry)

proc undoViewer(
    e: Editor, win: EditorWindow, entry: ViewerEntry, textMode: Option[EditorMode]
) =
  ## Shared exit once the entry is taken. A split placement closes the window it
  ## opened unless it is the last one; the covered mode resumes only if the
  ## window survived — a closed split leaves a neighbour that was never in the
  ## viewer mode.
  # The window's state is the viewer's while its entry is live, the DiffViewer
  # opened over it included.
  win.dropModeState()
  if entry.placement != vpInPlace and e.mainWindowCount() > 1:
    discard e.closeWindow()
  if e.activeWindow == win:
    e.resumeCoveredMode(win, entry, textMode)
    # The view is the tab's again.
    e.syncActiveWindow()

proc closeLiveViewer*(e: Editor) =
  ## Tear down whichever viewer is live in the active window (no-op if none)
  ## and resume what it covered. A split placement closes the active window, so
  ## callers must re-read `Editor.activeWindow` afterwards.
  let win = e.activeWindow
  let entry = win.takeViewerEntry()
  if entry.isSome:
    e.undoViewer(win, entry.get, none(EditorMode))

proc enterViewerMode*(
    e: Editor,
    mode: EditorMode,
    modeState: ModeState,
    buffer: TextBuffer,
    placement: ViewerPlacement,
): Result[void, string] =
  ## Show `buffer` as `mode`'s listing over the active window's tab, snapshotting
  ## the displaced cursor. A split placement first opens a window on the same
  ## tab, as `:split` does, and covers that one. The listing is never registered
  ## as a buffer. Re-entering the same mode (CallHierarchy incoming/outgoing)
  ## keeps the original snapshot; a *different* in-place viewer is torn down
  ## first. From the FileTree sidebar, it goes to a main window
  ## (`leaveSidebar`). Fails only when no window can be made for it.
  var placement = placement
  if ?e.leaveSidebar():
    # That window is new already: cover it rather than split it again.
    placement = vpInPlace
  let originMode = e.state.mode
  var reentering = false
  if placement == vpInPlace:
    # Peel any foreign viewer off the active window first. A split-placed
    # teardown may shift focus to a survivor also running a viewer, so loop.
    while true:
      let active = e.activeWindow
      if active.viewerEntry.isNone:
        break
      if active.viewerEntry.get.mode == mode and
          active.modeState.kind == modeStateKind(mode):
        reentering = true
        break
      e.closeLiveViewer()
  else:
    let splitResult =
      if placement == vpVSplit:
        e.vsplit()
      else:
        e.hsplit()
    if splitResult.isErr:
      return err(splitResult.error)

  let win = e.activeWindow
  if not reentering:
    win.viewerEntry = some(
      ViewerEntry(
        mode: mode,
        placement: placement,
        returnMode: win.mode,
        returnState: win.modeState,
        returnTab: win.tabBufferId,
        originCursor: win.cursor,
        originTopLine: win.viewport.topLine,
        originTopWrapOffset: win.viewport.topWrapOffset,
        originLeftColumn: win.viewport.leftColumn,
      )
    )
  # A split starts in its tab's mode; what the user left is the origin's.
  e.state.previousMode =
    if placement == vpInPlace: win.viewerEntry.get.returnMode else: originMode
  win.setView(buffer)
  win.resetViewerViewport()
  win.modeState = modeState
  e.setMode(mode)
  e.syncActiveWindow()
  ok()

proc splitCopy[T: ref](x: T): T =
  if x != nil:
    new(result)
    result[] = x[]

proc splitCopy(s: ModeState): ModeState =
  ## Another window's own copy of a viewer's state: Vim gives each window on a
  ## buffer its own cursor.
  case s.kind
  of mskFiler:
    ModeState(kind: mskFiler, filer: s.filer.splitCopy)
  of mskLogViewer:
    ModeState(kind: mskLogViewer, logViewer: s.logViewer.splitCopy)
  of mskHelp:
    ModeState(kind: mskHelp, help: s.help.splitCopy)
  of mskBufferManager:
    ModeState(kind: mskBufferManager, bufferManager: s.bufferManager.splitCopy)
  of mskBookmarkManager:
    ModeState(kind: mskBookmarkManager, bookmarkManager: s.bookmarkManager.splitCopy)
  of mskBackupManager:
    ModeState(kind: mskBackupManager, backupManager: s.backupManager.splitCopy)
  of mskRecoveryManager:
    ModeState(kind: mskRecoveryManager, recoveryManager: s.recoveryManager.splitCopy)
  of mskDiffViewer:
    ModeState(
      kind: mskDiffViewer,
      diffViewer: s.diffViewer.splitCopy,
      diffReturn: s.diffReturn.splitCopy,
    )
  of mskDebug:
    ModeState(kind: mskDebug, debug: s.debug.splitCopy)
  of mskConfig:
    ModeState(kind: mskConfig, config: s.config.splitCopy)
  of mskReferences:
    ModeState(kind: mskReferences, references: s.references.splitCopy)
  of mskDocumentSymbol:
    ModeState(kind: mskDocumentSymbol, documentSymbol: s.documentSymbol.splitCopy)
  of mskCallHierarchy:
    ModeState(kind: mskCallHierarchy, callHierarchy: s.callHierarchy.splitCopy)
  of mskRecentFile:
    ModeState(kind: mskRecentFile, recentFile: s.recentFile.splitCopy)
  of mskNone, mskFileTree, mskTerminal:
    # Not a viewer's state.
    s

proc splitViewer*(e: Editor, placement: ViewerPlacement): Result[void, string] =
  ## `:split` / `:vsplit` in a viewer window: show the same viewer in a split
  ## too, as Vim shows the window's buffer in both. The copy keeps its own
  ## selection and position, and closing it closes the split.
  let win = e.activeWindow
  if win.viewerEntry.isNone:
    return err("No viewer in the active window")
  let
    entryMode = win.viewerEntry.get.mode
    mode = win.mode
    state = win.modeState.splitCopy
    cursor = win.cursor
    topLine = win.viewport.topLine
    topWrapOffset = win.viewport.topWrapOffset
    leftColumn = win.viewport.leftColumn
  ?e.enterViewerMode(entryMode, state, win.buffer, placement)
  let copy = e.activeWindow
  # A DiffViewer over its backup manager: the window is in the diff.
  e.setMode(mode)
  copy.cursor = cursor
  copy.viewport.restoreViewportTop(topLine, topWrapOffset)
  copy.viewport.leftColumn = leftColumn
  e.syncActiveWindow()
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
    e: Editor, mode: EditorMode, textMode: Option[EditorMode]
): Option[ViewerEntry] =
  ## Shared exit. The record is taken only when it belongs to `mode` so an
  ## unrelated caller cannot consume it (no mode switch either in that case).
  let win = e.activeWindow
  result = win.takeViewerEntry(mode)
  if result.isNone:
    win.clearModeState(mode)
    return
  e.undoViewer(win, result.get, textMode)

proc leaveViewerMode*(e: Editor, mode: EditorMode) =
  ## Undo `enterViewerMode`, resuming what the viewer covered (round-trips
  ## Visual).
  discard e.tearDownViewer(mode, none(EditorMode))

proc leaveViewerModeForJump*(e: Editor, mode: EditorMode): Option[ViewerEntry] =
  ## Exit before a jump: a text mode lands in Normal, and the origin position is
  ## restored so the jump list anchors there. Returns the entry, none when
  ## `mode` held no viewer.
  e.tearDownViewer(mode, some(EditorMode.Normal))
