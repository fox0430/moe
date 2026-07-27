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

import std/[unittest, options, strutils]

import
  ../src/moepkg/[
    editor, editor_window_state, config, config_mode, types, modes, help_viewer,
    diff_viewer, buffer_manager, backup_manager, references_viewer, recent_file_mode,
    debug_viewer, message_log,
  ]
import ../src/moepkg/buffer/core

# Helper to create a minimal Editor for testing
proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)

# Helper to populate the window with a given mode variant and remember the
# original buffer on the window (the Phase 5 contract: `originalBuffer` is
# owned by EditorWindow, not by the per-mode state).
proc enterMode(
    win: EditorWindow,
    modeState: ModeState,
    swappedBuffer: TextBuffer,
    originalBuffer: TextBuffer = nil,
) =
  if originalBuffer != nil:
    win.originalBuffer = originalBuffer
  win.buffer = swappedBuffer
  win.modeState = modeState

suite "restoreOriginalBuffer":
  test "Filer - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let filerBuf = newTextBuffer("filer")
    win.enterMode(ModeState(kind: mskFiler, filer: FilerState()), filerBuf, origBuf)

    win.restoreOriginalBuffer(EditorMode.Filer)

    check win.buffer == origBuf
    # State is not cleared by restoreOriginalBuffer
    check win.modeState.kind == mskFiler
    # originalBuffer is cleared once it has been restored
    check win.originalBuffer == nil

  test "Filer - no-op when originalBuffer is nil":
    let e = createTestEditor()
    let win = e.activeWindow
    let filerBuf = newTextBuffer("filer")
    win.enterMode(ModeState(kind: mskFiler, filer: FilerState()), filerBuf)

    win.restoreOriginalBuffer(EditorMode.Filer)

    check win.buffer == filerBuf

  test "Help - no-op (split window mode, no originalBuffer)":
    let e = createTestEditor()
    let win = e.activeWindow
    let helpBuf = newTextBuffer("help")
    win.enterMode(ModeState(kind: mskHelp, help: newHelpViewerState()), helpBuf)

    win.restoreOriginalBuffer(EditorMode.Help)

    check win.buffer == helpBuf

  test "BufferManager - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let bmBuf = newTextBuffer("bm")
    win.enterMode(
      ModeState(kind: mskBufferManager, bufferManager: newBufferManagerState()),
      bmBuf,
      origBuf,
    )

    win.restoreOriginalBuffer(EditorMode.BufferManager)

    check win.buffer == origBuf

  test "DiffViewer - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let dvBuf = newTextBuffer("diff")
    win.enterMode(
      ModeState(kind: mskDiffViewer, diffViewer: newDiffViewerState()), dvBuf, origBuf
    )

    win.restoreOriginalBuffer(EditorMode.DiffViewer)

    check win.buffer == origBuf

  test "References - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let refBuf = newTextBuffer("refs")
    win.enterMode(
      ModeState(kind: mskReferences, references: newReferencesViewerState(@[])),
      refBuf,
      origBuf,
    )

    win.restoreOriginalBuffer(EditorMode.References)

    check win.buffer == origBuf

  test "DocumentSymbol - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let dsBuf = newTextBuffer("symbols")
    win.enterMode(
      ModeState(kind: mskDocumentSymbol, documentSymbol: DocumentSymbolViewerState()),
      dsBuf,
      origBuf,
    )

    win.restoreOriginalBuffer(EditorMode.DocumentSymbol)

    check win.buffer == origBuf

  test "CallHierarchy - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let chBuf = newTextBuffer("callhierarchy")
    win.enterMode(
      ModeState(kind: mskCallHierarchy, callHierarchy: CallHierarchyViewerState()),
      chBuf,
      origBuf,
    )

    win.restoreOriginalBuffer(EditorMode.CallHierarchy)

    check win.buffer == origBuf

  test "LogViewer - no-op (no originalBuffer)":
    let e = createTestEditor()
    let win = e.activeWindow
    let logBuf = newTextBuffer("log")
    win.enterMode(ModeState(kind: mskLogViewer, logViewer: newLogViewerState()), logBuf)

    win.restoreOriginalBuffer(EditorMode.LogViewer)

    check win.buffer == logBuf

  test "Normal mode - no-op":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("normal")
    win.buffer = buf

    win.restoreOriginalBuffer(EditorMode.Normal)

    check win.buffer == buf

suite "clearModeState":
  test "Filer - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let filerBuf = newTextBuffer("filer")
    win.enterMode(ModeState(kind: mskFiler, filer: FilerState()), filerBuf, origBuf)

    win.clearModeState(EditorMode.Filer)

    check win.buffer == origBuf
    check win.modeState.kind == mskNone
    check win.originalBuffer == nil

  test "LogViewer - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let logBuf = newTextBuffer("log")
    win.enterMode(ModeState(kind: mskLogViewer, logViewer: newLogViewerState()), logBuf)

    win.clearModeState(EditorMode.LogViewer)

    check win.buffer == logBuf
    check win.modeState.kind == mskNone

  test "Help - clears state without buffer change (split window mode)":
    let e = createTestEditor()
    let win = e.activeWindow
    let helpBuf = newTextBuffer("help")
    win.enterMode(ModeState(kind: mskHelp, help: newHelpViewerState()), helpBuf)

    win.clearModeState(EditorMode.Help)

    check win.buffer == helpBuf
    check win.modeState.kind == mskNone

  test "BufferManager - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let bmBuf = newTextBuffer("bm")
    win.enterMode(
      ModeState(kind: mskBufferManager, bufferManager: newBufferManagerState()),
      bmBuf,
      origBuf,
    )

    win.clearModeState(EditorMode.BufferManager)

    check win.buffer == origBuf
    check win.modeState.kind == mskNone

  test "BackupManager - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("backup")
    win.enterMode(
      ModeState(kind: mskBackupManager, backupManager: newBackupManagerState()), buf
    )

    win.clearModeState(EditorMode.BackupManager)

    check win.buffer == buf
    check win.modeState.kind == mskNone

  test "DiffViewer - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let dvBuf = newTextBuffer("diff")
    win.enterMode(
      ModeState(kind: mskDiffViewer, diffViewer: newDiffViewerState()), dvBuf, origBuf
    )

    win.clearModeState(EditorMode.DiffViewer)

    check win.buffer == origBuf
    check win.modeState.kind == mskNone

  test "Debug - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("debug")
    win.enterMode(ModeState(kind: mskDebug, debug: newDebugViewerState()), buf)

    win.clearModeState(EditorMode.Debug)

    check win.buffer == buf
    check win.modeState.kind == mskNone

  test "Config - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("config")
    win.enterMode(
      ModeState(kind: mskConfig, config: newConfigModeState(newEditorConfig())), buf
    )

    win.clearModeState(EditorMode.Config)

    check win.buffer == buf
    check win.modeState.kind == mskNone

  test "References - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let refBuf = newTextBuffer("refs")
    win.enterMode(
      ModeState(kind: mskReferences, references: newReferencesViewerState(@[])),
      refBuf,
      origBuf,
    )

    win.clearModeState(EditorMode.References)

    check win.buffer == origBuf
    check win.modeState.kind == mskNone

  test "DocumentSymbol - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let dsBuf = newTextBuffer("symbols")
    win.enterMode(
      ModeState(kind: mskDocumentSymbol, documentSymbol: DocumentSymbolViewerState()),
      dsBuf,
      origBuf,
    )

    win.clearModeState(EditorMode.DocumentSymbol)

    check win.buffer == origBuf
    check win.modeState.kind == mskNone

  test "CallHierarchy - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let chBuf = newTextBuffer("callhierarchy")
    win.enterMode(
      ModeState(kind: mskCallHierarchy, callHierarchy: CallHierarchyViewerState()),
      chBuf,
      origBuf,
    )

    win.clearModeState(EditorMode.CallHierarchy)

    check win.buffer == origBuf
    check win.modeState.kind == mskNone

  test "RecentFile - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("recent")
    win.enterMode(
      ModeState(kind: mskRecentFile, recentFile: newRecentFileModeState()), buf
    )

    win.clearModeState(EditorMode.RecentFile)

    check win.buffer == buf
    check win.modeState.kind == mskNone

  test "Normal mode - no-op":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("normal")
    win.buffer = buf

    win.clearModeState(EditorMode.Normal)

    check win.buffer == buf

suite "suspendMode / takeSuspendedMode":
  test "round-trips a suspended (mode, modeState) across an overlay":
    # Mirrors the BackupManager -> DiffViewer -> BackupManager flow: suspend the
    # manager mode, swap in the overlay variant, then take + re-install on exit.
    let e = createTestEditor()
    let win = e.activeWindow
    let bkState = newBackupManagerState()
    win.mode = EditorMode.BackupManager
    win.modeState = ModeState(kind: mskBackupManager, backupManager: bkState)

    win.suspendMode()
    win.mode = EditorMode.DiffViewer
    win.modeState = ModeState(kind: mskDiffViewer, diffViewer: newDiffViewerState())

    # The exit path takes the suspension before tearing the overlay down.
    let suspended = win.takeSuspendedMode()
    check suspended.isSome
    # Taking consumes it so it can't be resumed twice.
    check win.suspendedMode.isNone

    # clearModeState resets the live variant to mskNone (and clears any leftover
    # suspension, already none here).
    win.clearModeState(EditorMode.DiffViewer)
    check win.modeState.kind == mskNone

    # Re-install the taken pair, mirroring hrDiffViewerQuit.
    win.mode = suspended.get.mode
    win.modeState = suspended.get.modeState
    check win.mode == EditorMode.BackupManager
    check win.modeState.kind == mskBackupManager
    check win.modeState.backupManager == bkState

  test "clearModeState clears a leftover suspension":
    # If the overlay is torn down via a path other than the take-before-clear
    # exit (window close, buffer/tab switch, ...), clearModeState must not
    # strand the suspension on the window.
    let e = createTestEditor()
    let win = e.activeWindow
    win.mode = EditorMode.BackupManager
    win.modeState =
      ModeState(kind: mskBackupManager, backupManager: newBackupManagerState())
    win.suspendMode()
    win.mode = EditorMode.DiffViewer
    win.modeState = ModeState(kind: mskDiffViewer, diffViewer: newDiffViewerState())

    win.clearModeState(EditorMode.DiffViewer)

    check win.modeState.kind == mskNone
    check win.suspendedMode.isNone

  test "takeSuspendedMode returns none when nothing was suspended":
    let e = createTestEditor()
    let win = e.activeWindow
    win.mode = EditorMode.Filer
    win.modeState = ModeState(kind: mskFiler, filer: FilerState())

    check win.takeSuspendedMode().isNone

    check win.mode == EditorMode.Filer
    check win.modeState.kind == mskFiler

  test "suspendMode warns when overwriting an existing suspension":
    let e = createTestEditor()
    let win = e.activeWindow
    win.mode = EditorMode.BackupManager
    win.modeState =
      ModeState(kind: mskBackupManager, backupManager: newBackupManagerState())
    win.suspendMode()

    win.mode = EditorMode.Filer
    win.modeState = ModeState(kind: mskFiler, filer: FilerState())
    let logLenBefore = getMessageLog().len
    win.suspendMode()

    let log = getMessageLog()
    check log.len == logLenBefore + 1
    check "suspendMode: overwriting existing suspension" in log[^1]

suite "ModeState variant invariants":
  test "modeStateKind maps every stateful mode":
    check modeStateKind(EditorMode.Normal) == mskNone
    check modeStateKind(EditorMode.Insert) == mskNone
    check modeStateKind(EditorMode.Command) == mskNone
    check modeStateKind(EditorMode.QuickRun) == mskNone
    check modeStateKind(EditorMode.Filer) == mskFiler
    check modeStateKind(EditorMode.FileTree) == mskFileTree
    check modeStateKind(EditorMode.LogViewer) == mskLogViewer
    check modeStateKind(EditorMode.Help) == mskHelp
    check modeStateKind(EditorMode.BufferManager) == mskBufferManager
    check modeStateKind(EditorMode.BookmarkManager) == mskBookmarkManager
    check modeStateKind(EditorMode.BackupManager) == mskBackupManager
    check modeStateKind(EditorMode.DiffViewer) == mskDiffViewer
    check modeStateKind(EditorMode.Debug) == mskDebug
    check modeStateKind(EditorMode.Config) == mskConfig
    check modeStateKind(EditorMode.References) == mskReferences
    check modeStateKind(EditorMode.DocumentSymbol) == mskDocumentSymbol
    check modeStateKind(EditorMode.CallHierarchy) == mskCallHierarchy
    check modeStateKind(EditorMode.RecentFile) == mskRecentFile
    check modeStateKind(EditorMode.Terminal) == mskTerminal

  test "clearModeState leaves unrelated variant payload untouched":
    let e = createTestEditor()
    let win = e.activeWindow
    win.modeState = ModeState(kind: mskFiler, filer: FilerState())
    win.originalBuffer = newTextBuffer("orig")
    let beforeBuffer = win.buffer
    let beforeOriginal = win.originalBuffer

    # Clearing a mode that does not match the current variant should not
    # erase the unrelated payload, restore a buffer, or touch the window's
    # saved originalBuffer.
    win.clearModeState(EditorMode.Help)

    check win.modeState.kind == mskFiler
    check win.buffer == beforeBuffer
    check win.originalBuffer == beforeOriginal

  test "clearModeState skips Terminal cleanup when mode mismatches":
    # If the window holds a non-Terminal variant, clearing Terminal must
    # not touch any (potentially uninitialized) terminal payload.
    let e = createTestEditor()
    let win = e.activeWindow
    win.modeState = ModeState(kind: mskFiler, filer: FilerState())

    win.clearModeState(EditorMode.Terminal)

    check win.modeState.kind == mskFiler

  test "restoreOriginalBuffer is a no-op when variant kind mismatches mode":
    # The early-return guard protects against callers passing a mode whose
    # kind does not match the live variant. Keep that contract under test.
    let e = createTestEditor()
    let win = e.activeWindow
    let activeBuf = newTextBuffer("active")
    win.buffer = activeBuf
    win.originalBuffer = newTextBuffer("orig")
    win.modeState = ModeState(kind: mskFiler, filer: FilerState())

    win.restoreOriginalBuffer(EditorMode.BufferManager)

    check win.buffer == activeBuf
    check win.modeState.kind == mskFiler
    # originalBuffer must remain intact on a guard-rejected call
    check win.originalBuffer != nil

  test "restoreOriginalBuffer is a no-op when variant kind is mskNone":
    let e = createTestEditor()
    let win = e.activeWindow
    let activeBuf = newTextBuffer("active")
    win.buffer = activeBuf

    win.restoreOriginalBuffer(EditorMode.Filer)

    check win.buffer == activeBuf

  test "Default-constructed EditorWindow has mskNone variant":
    let e = createTestEditor()
    let win = e.activeWindow
    check win.modeState.kind == mskNone
    check win.originalBuffer == nil
