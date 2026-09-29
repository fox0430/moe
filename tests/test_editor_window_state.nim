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

import std/[unittest, options]

import
  ../src/moepkg/[
    editor, editor_window_state, config, config_mode, types, modes, help_viewer,
    diff_viewer, buffer_manager, backup_manager, references_viewer, recent_file_mode,
    debug_viewer, log_viewer,
  ]
import ../src/moepkg/buffer/core

# Helper to create a minimal Editor for testing
proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)

proc enterMode(win: EditorWindow, modeState: ModeState, view: TextBuffer) =
  win.setView(view)
  win.modeState = modeState

suite "clearModeState":
  test "clears every listing mode's state and leaves the view alone":
    let cases = @[
      (EditorMode.Filer, ModeState(kind: mskFiler, filer: FilerState())),
      (
        EditorMode.LogViewer,
        ModeState(kind: mskLogViewer, logViewer: newLogViewerState()),
      ),
      (EditorMode.Help, ModeState(kind: mskHelp, help: newHelpViewerState())),
      (
        EditorMode.BufferManager,
        ModeState(kind: mskBufferManager, bufferManager: newBufferManagerState()),
      ),
      (
        EditorMode.BackupManager,
        ModeState(kind: mskBackupManager, backupManager: newBackupManagerState()),
      ),
      (
        EditorMode.DiffViewer,
        ModeState(
          kind: mskDiffViewer,
          diffViewer: newDiffViewerState(),
          diffReturn: newBackupManagerState(),
        ),
      ),
      (EditorMode.Debug, ModeState(kind: mskDebug, debug: newDebugViewerState())),
      (
        EditorMode.Config,
        ModeState(kind: mskConfig, config: newConfigModeState(newEditorConfig())),
      ),
      (
        EditorMode.References,
        ModeState(kind: mskReferences, references: newReferencesViewerState(@[])),
      ),
      (
        EditorMode.DocumentSymbol,
        ModeState(kind: mskDocumentSymbol, documentSymbol: DocumentSymbolViewerState()),
      ),
      (
        EditorMode.CallHierarchy,
        ModeState(kind: mskCallHierarchy, callHierarchy: CallHierarchyViewerState()),
      ),
      (
        EditorMode.RecentFile,
        ModeState(kind: mskRecentFile, recentFile: newRecentFileModeState()),
      ),
    ]
    for (mode, state) in cases:
      let e = createTestEditor()
      let win = e.activeWindow
      let listing = newTextBuffer($mode)
      win.enterMode(state, listing)

      win.clearModeState(mode)

      checkpoint $mode
      check win.buffer == listing
      check win.modeState.kind == mskNone

  test "Normal mode - no-op":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("normal")
    win.setTab(buf)

    win.clearModeState(EditorMode.Normal)

    check win.buffer == buf

  test "dropModeState resets the live variant whatever the mode says":
    let e = createTestEditor()
    let win = e.activeWindow
    win.enterMode(
      ModeState(kind: mskBufferManager, bufferManager: newBufferManagerState()),
      newTextBuffer("bm"),
    )
    win.mode = EditorMode.Normal

    win.clearModeState(win.mode)
    check win.modeState.kind == mskBufferManager

    win.dropModeState()
    check win.modeState.kind == mskNone

  test "a DiffViewer teardown keeps the backup manager's viewer entry":
    let e = createTestEditor()
    let win = e.activeWindow
    win.viewerEntry =
      some(ViewerEntry(mode: EditorMode.BackupManager, returnTab: win.tabBufferId))
    win.enterMode(
      ModeState(
        kind: mskDiffViewer,
        diffViewer: newDiffViewerState(),
        diffReturn: newBackupManagerState(),
      ),
      newTextBuffer("diff"),
    )

    win.clearModeState(EditorMode.DiffViewer)

    check win.modeState.kind == mskNone
    check win.viewerEntry.isSome

suite "ModeState variant invariants":
  test "modeStateKind maps every stateful mode":
    check modeStateKind(EditorMode.Normal) == mskNone
    check modeStateKind(EditorMode.Insert) == mskNone
    check modeStateKind(EditorMode.Command) == mskNone
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
    let beforeBuffer = win.buffer

    # Clearing a mode that does not match the current variant should not
    # erase the unrelated payload or touch the view.
    win.clearModeState(EditorMode.Help)

    check win.modeState.kind == mskFiler
    check win.buffer == beforeBuffer

  test "clearModeState skips Terminal cleanup when mode mismatches":
    # If the window holds a non-Terminal variant, clearing Terminal must
    # not touch any (potentially uninitialized) terminal payload.
    let e = createTestEditor()
    let win = e.activeWindow
    win.modeState = ModeState(kind: mskFiler, filer: FilerState())

    win.clearModeState(EditorMode.Terminal)

    check win.modeState.kind == mskFiler

  test "Default-constructed EditorWindow has mskNone variant":
    let e = createTestEditor()
    let win = e.activeWindow
    check win.modeState.kind == mskNone
