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
  ../src/moepkg/[editor, editor_window_state, config, types, buffer, modes, help_viewer]

# Helper to create a minimal Editor for testing
proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)

suite "restoreOriginalBuffer":
  test "Filer - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let filerBuf = newTextBuffer("filer")
    win.buffer = filerBuf
    let fs = FilerState(originalBuffer: origBuf)
    win.filerState = some(fs)

    win.restoreOriginalBuffer(EditorMode.Filer)

    check win.buffer == origBuf
    # State field is not cleared by restoreOriginalBuffer
    check win.filerState.isSome

  test "Filer - no-op when originalBuffer is nil":
    let e = createTestEditor()
    let win = e.activeWindow
    let filerBuf = newTextBuffer("filer")
    win.buffer = filerBuf
    let fs = FilerState(originalBuffer: nil)
    win.filerState = some(fs)

    win.restoreOriginalBuffer(EditorMode.Filer)

    check win.buffer == filerBuf

  test "Help - no-op (split window mode, no originalBuffer)":
    let e = createTestEditor()
    let win = e.activeWindow
    let helpBuf = newTextBuffer("help")
    win.buffer = helpBuf
    let hs = newHelpViewerState()
    win.helpViewerState = some(hs)

    win.restoreOriginalBuffer(EditorMode.Help)

    check win.buffer == helpBuf

  test "BufferManager - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let bmBuf = newTextBuffer("bm")
    win.buffer = bmBuf
    let bms = newBufferManagerState()
    bms.originalBuffer = origBuf
    win.bufferManagerState = some(bms)

    win.restoreOriginalBuffer(EditorMode.BufferManager)

    check win.buffer == origBuf

  test "DiffViewer - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let dvBuf = newTextBuffer("diff")
    win.buffer = dvBuf
    let dvs = newDiffViewerState()
    dvs.originalBuffer = origBuf
    win.diffViewerState = some(dvs)

    win.restoreOriginalBuffer(EditorMode.DiffViewer)

    check win.buffer == origBuf

  test "References - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let refBuf = newTextBuffer("refs")
    win.buffer = refBuf
    let rs = newReferencesViewerState(@[])
    rs.originalBuffer = origBuf
    win.referencesViewerState = some(rs)

    win.restoreOriginalBuffer(EditorMode.References)

    check win.buffer == origBuf

  test "DocumentSymbol - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let dsBuf = newTextBuffer("symbols")
    win.buffer = dsBuf
    let dss = DocumentSymbolViewerState(originalBuffer: origBuf)
    win.documentSymbolViewerState = some(dss)

    win.restoreOriginalBuffer(EditorMode.DocumentSymbol)

    check win.buffer == origBuf

  test "CallHierarchy - restores original buffer":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let chBuf = newTextBuffer("callhierarchy")
    win.buffer = chBuf
    let chs = CallHierarchyViewerState(originalBuffer: origBuf)
    win.callHierarchyViewerState = some(chs)

    win.restoreOriginalBuffer(EditorMode.CallHierarchy)

    check win.buffer == origBuf

  test "LogViewer - no-op (no originalBuffer)":
    let e = createTestEditor()
    let win = e.activeWindow
    let logBuf = newTextBuffer("log")
    win.buffer = logBuf
    win.logViewerState = some(newLogViewerState())

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
    win.buffer = filerBuf
    let fs = FilerState(originalBuffer: origBuf)
    win.filerState = some(fs)

    win.clearModeState(EditorMode.Filer)

    check win.buffer == origBuf
    check win.filerState.isNone

  test "LogViewer - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let logBuf = newTextBuffer("log")
    win.buffer = logBuf
    win.logViewerState = some(newLogViewerState())

    win.clearModeState(EditorMode.LogViewer)

    check win.buffer == logBuf
    check win.logViewerState.isNone

  test "Help - clears state without buffer change (split window mode)":
    let e = createTestEditor()
    let win = e.activeWindow
    let helpBuf = newTextBuffer("help")
    win.buffer = helpBuf
    let hs = newHelpViewerState()
    win.helpViewerState = some(hs)

    win.clearModeState(EditorMode.Help)

    check win.buffer == helpBuf
    check win.helpViewerState.isNone

  test "BufferManager - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let bmBuf = newTextBuffer("bm")
    win.buffer = bmBuf
    let bms = newBufferManagerState()
    bms.originalBuffer = origBuf
    win.bufferManagerState = some(bms)

    win.clearModeState(EditorMode.BufferManager)

    check win.buffer == origBuf
    check win.bufferManagerState.isNone

  test "BackupManager - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("backup")
    win.buffer = buf
    win.backupManagerState = some(newBackupManagerState())

    win.clearModeState(EditorMode.BackupManager)

    check win.buffer == buf
    check win.backupManagerState.isNone

  test "DiffViewer - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let dvBuf = newTextBuffer("diff")
    win.buffer = dvBuf
    let dvs = newDiffViewerState()
    dvs.originalBuffer = origBuf
    win.diffViewerState = some(dvs)

    win.clearModeState(EditorMode.DiffViewer)

    check win.buffer == origBuf
    check win.diffViewerState.isNone

  test "Debug - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("debug")
    win.buffer = buf
    win.debugViewerState = some(newDebugViewerState())

    win.clearModeState(EditorMode.Debug)

    check win.buffer == buf
    check win.debugViewerState.isNone

  test "Config - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("config")
    win.buffer = buf
    win.configModeState = some(newConfigModeState(newEditorConfig()))

    win.clearModeState(EditorMode.Config)

    check win.buffer == buf
    check win.configModeState.isNone

  test "References - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let refBuf = newTextBuffer("refs")
    win.buffer = refBuf
    let rs = newReferencesViewerState(@[])
    rs.originalBuffer = origBuf
    win.referencesViewerState = some(rs)

    win.clearModeState(EditorMode.References)

    check win.buffer == origBuf
    check win.referencesViewerState.isNone

  test "DocumentSymbol - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let dsBuf = newTextBuffer("symbols")
    win.buffer = dsBuf
    let dss = DocumentSymbolViewerState(originalBuffer: origBuf)
    win.documentSymbolViewerState = some(dss)

    win.clearModeState(EditorMode.DocumentSymbol)

    check win.buffer == origBuf
    check win.documentSymbolViewerState.isNone

  test "CallHierarchy - restores buffer and clears state":
    let e = createTestEditor()
    let win = e.activeWindow
    let origBuf = newTextBuffer("original")
    let chBuf = newTextBuffer("callhierarchy")
    win.buffer = chBuf
    let chs = CallHierarchyViewerState(originalBuffer: origBuf)
    win.callHierarchyViewerState = some(chs)

    win.clearModeState(EditorMode.CallHierarchy)

    check win.buffer == origBuf
    check win.callHierarchyViewerState.isNone

  test "RecentFile - clears state without buffer change":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("recent")
    win.buffer = buf
    win.recentFileModeState = some(newRecentFileModeState())

    win.clearModeState(EditorMode.RecentFile)

    check win.buffer == buf
    check win.recentFileModeState.isNone

  test "Normal mode - no-op":
    let e = createTestEditor()
    let win = e.activeWindow
    let buf = newTextBuffer("normal")
    win.buffer = buf

    win.clearModeState(EditorMode.Normal)

    check win.buffer == buf
