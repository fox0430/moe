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
## (Filer, BufferManager, Terminal, ...) and clears the matching mode
## state Option fields on `EditorWindow`.

import std/options

import editor_types, terminal_mode

proc restoreOriginalBuffer*(win: EditorWindow, mode: EditorMode) =
  ## Restore the original buffer for modes that replace the window buffer.
  case mode
  of EditorMode.Filer:
    if win.filerState.isSome and win.filerState.get.originalBuffer != nil:
      win.buffer = win.filerState.get.originalBuffer
  of EditorMode.BufferManager:
    if win.bufferManagerState.isSome and win.bufferManagerState.get.originalBuffer != nil:
      win.buffer = win.bufferManagerState.get.originalBuffer
  of EditorMode.BookmarkManager:
    if win.bookmarkManagerState.isSome and
        win.bookmarkManagerState.get.originalBuffer != nil:
      win.buffer = win.bookmarkManagerState.get.originalBuffer
  of EditorMode.DiffViewer:
    if win.diffViewerState.isSome and win.diffViewerState.get.originalBuffer != nil:
      win.buffer = win.diffViewerState.get.originalBuffer
  of EditorMode.References:
    if win.referencesViewerState.isSome and
        win.referencesViewerState.get.originalBuffer != nil:
      win.buffer = win.referencesViewerState.get.originalBuffer
  of EditorMode.DocumentSymbol:
    if win.documentSymbolViewerState.isSome and
        win.documentSymbolViewerState.get.originalBuffer != nil:
      win.buffer = win.documentSymbolViewerState.get.originalBuffer
  of EditorMode.CallHierarchy:
    if win.callHierarchyViewerState.isSome and
        win.callHierarchyViewerState.get.originalBuffer != nil:
      win.buffer = win.callHierarchyViewerState.get.originalBuffer
  of EditorMode.Terminal:
    if win.terminalState.isSome and win.terminalState.get.originalBuffer != nil:
      win.buffer = win.terminalState.get.originalBuffer
  of EditorMode.FileTree:
    discard # FileTree uses its own window; no original buffer to restore
  else:
    discard

proc clearModeState*(win: EditorWindow, mode: EditorMode) =
  ## Restore original buffer (if any) and clear the mode state field.
  win.restoreOriginalBuffer(mode)

  case mode
  of EditorMode.Filer:
    win.filerState = none(FilerState)
  of EditorMode.LogViewer:
    win.logViewerState = none(LogViewerState)
  of EditorMode.Help:
    win.helpViewerState = none(HelpViewerState)
  of EditorMode.BufferManager:
    win.bufferManagerState = none(BufferManagerState)
  of EditorMode.BookmarkManager:
    win.bookmarkManagerState = none(BookmarkManagerState)
  of EditorMode.BackupManager:
    win.backupManagerState = none(BackupManagerState)
  of EditorMode.DiffViewer:
    win.diffViewerState = none(DiffViewerState)
  of EditorMode.Debug:
    win.debugViewerState = none(DebugViewerState)
  of EditorMode.Config:
    win.configModeState = none(ConfigModeState)
  of EditorMode.References:
    win.referencesViewerState = none(ReferencesViewerState)
  of EditorMode.DocumentSymbol:
    win.documentSymbolViewerState = none(DocumentSymbolViewerState)
  of EditorMode.CallHierarchy:
    win.callHierarchyViewerState = none(CallHierarchyViewerState)
  of EditorMode.RecentFile:
    win.recentFileModeState = none(RecentFileModeState)
  of EditorMode.Terminal:
    if win.terminalState.isSome:
      win.terminalState.get.cleanup()
    win.terminalState = none(TerminalState)
  of EditorMode.FileTree:
    win.fileTreeState = none(FileTreeState)
    win.fixedWidth = none(int)
  else:
    discard
