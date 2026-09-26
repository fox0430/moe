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

## Tests for viewer_mode.nim

import std/[unittest, options, os]

import pkg/results

import
  ../src/moepkg/[
    editor, config, config_loader, viewer_mode, help_viewer, editor_buffers,
    editor_window_state, window_manager, backup_manager, diff_viewer,
  ]
import ../src/moepkg/types/editor_types
import ../src/moepkg/buffer
import ../src/moepkg/command_handlers/editor_ops

const TestLines = "aaaa\nbbbb\ncccc\n"

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc editorOnFile(name: string): tuple[e: Editor, path: string] =
  ## Editor with `name` (under the temp dir) opened in the active window.
  let path = getTempDir() / name
  writeFile(path, TestLines)
  let e = createTestEditor()
  discard e.editFile(path)
  (e, path)

proc makeHelpModeState(): ModeState =
  ModeState(kind: mskHelp, help: newHelpViewerState())

suite "viewer_mode - enterViewerMode (vpInPlace)":
  test "snapshots placement and swaps the buffer":
    let (e, path) = editorOnFile("moe_viewer_enter1.txt")
    defer:
      removeFile(path)
    let originalBuffer = e.activeBuffer
    let helpBuffer = newTextBuffer("help line 1\nhelp line 2")
    let result =
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpInPlace)
    check result.isOk
    let entry = e.activeWindow.viewerEntry
    check entry.isSome
    check entry.get.placement == vpInPlace
    check entry.get.bufferId == helpBuffer.id
    check e.activeBuffer == helpBuffer

  test "re-entering the same mode keeps the original snapshot":
    let (e, path) = editorOnFile("moe_viewer_enter2.txt")
    defer:
      removeFile(path)
    let helpBuffer = newTextBuffer("help line 1")
    let result =
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpInPlace)
    check result.isOk
    let entryId = e.activeWindow.viewerEntry.get.bufferId
    let againBuffer = newTextBuffer("other")
    let again =
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), againBuffer, vpInPlace)
    check again.isOk
    check e.activeWindow.viewerEntry.get.bufferId == entryId
    check e.activeBuffer == againBuffer

  test "a different in-place viewer is torn down first":
    let (e, path) = editorOnFile("moe_viewer_enter3.txt")
    defer:
      removeFile(path)
    let helpBuffer = newTextBuffer("help line 1")
    discard
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpInPlace)
    let modeState = ModeState(kind: mskFiler, filer: FilerState())
    let result =
      e.enterViewerMode(EditorMode.Filer, modeState, newTextBuffer("filer"), vpInPlace)
    check result.isOk
    check e.activeWindow.viewerEntry.get.mode == EditorMode.Filer

suite "viewer_mode - leaveViewerMode":
  test "restores the original buffer, cursor, viewport and mode":
    let (e, path) = editorOnFile("moe_viewer_leave1.txt")
    defer:
      removeFile(path)
    let originalBuffer = e.activeBuffer
    e.activeWindow.cursor = BufferPosition(line: 1, column: 2)
    e.activeWindow.viewport.topLine = 1
    e.activeWindow.viewport.leftColumn = 3
    let helpBuffer = newTextBuffer("help line 1")
    discard
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpInPlace)
    check e.activeWindow.mode == EditorMode.Help
    e.leaveViewerMode(EditorMode.Help)
    check e.activeWindow.buffer == originalBuffer
    check e.activeWindow.cursor.line == 1
    check e.activeWindow.cursor.column == 2
    check e.activeWindow.viewport.topLine == 1
    check e.activeWindow.viewport.leftColumn == 3
    check e.activeWindow.mode == EditorMode.Normal

  test "is a no-op when the window has no viewer entry":
    let (e, path) = editorOnFile("moe_viewer_leave2.txt")
    defer:
      removeFile(path)
    e.leaveViewerMode(EditorMode.Help)
    check e.activeBuffer.len == 3

suite "viewer_mode - enterViewerMode (vpVSplit)":
  test "opens a new window with the listing buffer":
    let (e, path) = editorOnFile("moe_viewer_vsplit1.txt")
    defer:
      removeFile(path)
    let windowCount = e.windowManager.windows.len
    let helpBuffer = newTextBuffer("help line 1")
    let result =
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpVSplit)
    check result.isOk
    check e.windowManager.windows.len == windowCount + 1
    check e.activeWindow.buffer == helpBuffer
    check e.activeWindow.viewerEntry.isSome
    check e.activeWindow.viewerEntry.get.placement == vpVSplit

  test "leaveViewerMode closes the split":
    let (e, path) = editorOnFile("moe_viewer_vsplit2.txt")
    defer:
      removeFile(path)
    let windowCount = e.windowManager.windows.len
    let helpBuffer = newTextBuffer("help line 1")
    discard
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpVSplit)
    check e.windowManager.windows.len == windowCount + 1
    e.leaveViewerMode(EditorMode.Help)
    check e.windowManager.windows.len == windowCount

  test ":bd of the listing ends the viewer and keeps the window":
    let (e, path) = editorOnFile("moe_viewer_vsplit_bd.txt")
    defer:
      removeFile(path)
    let fileBuffer = e.activeBuffer()
    discard e.enterViewerMode(
      EditorMode.Help, makeHelpModeState(), newTextBuffer("help line 1"), vpVSplit
    )
    let win = e.activeWindow

    check e.deleteCurrentBuffer().isOk

    check e.activeWindow == win
    check win.viewerEntry.isNone
    check win.modeState.kind == mskNone
    check win.mode == EditorMode.Normal
    check win.buffer == fileBuffer

suite "viewer_mode - focusExistingViewerWindow":
  test "activates an existing viewer window":
    let (e, path) = editorOnFile("moe_viewer_focus1.txt")
    defer:
      removeFile(path)
    let helpBuffer = newTextBuffer("help line 1")
    discard
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpVSplit)
    let viewerIndex = e.windowManager.activeWindowIndex
    e.windowManager.activateWindow(0)
    check e.windowManager.activeWindowIndex == 0
    check e.focusExistingViewerWindow(EditorMode.Help)
    check e.windowManager.activeWindowIndex == viewerIndex

  test "returns false when no viewer window exists":
    let (e, path) = editorOnFile("moe_viewer_focus2.txt")
    defer:
      removeFile(path)
    check e.focusExistingViewerWindow(EditorMode.Help) == false

suite "viewer_mode - closeLiveViewer":
  test "is a no-op without a live viewer":
    let (e, path) = editorOnFile("moe_viewer_close1.txt")
    defer:
      removeFile(path)
    e.closeLiveViewer()
    check e.activeBuffer.len == 3

  test "closes a live in-place viewer and restores the return mode":
    let (e, path) = editorOnFile("moe_viewer_close2.txt")
    defer:
      removeFile(path)
    let originalBuffer = e.activeBuffer
    let helpBuffer = newTextBuffer("help line 1")
    discard
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpInPlace)
    check e.activeWindow.mode == EditorMode.Help
    e.closeLiveViewer()
    check e.activeWindow.buffer == originalBuffer
    check e.activeWindow.mode == EditorMode.Normal

suite "viewer_mode - leaveViewerModeForJump":
  test "returns the entry and lands in Normal at the origin position":
    let (e, path) = editorOnFile("moe_viewer_jump1.txt")
    defer:
      removeFile(path)
    e.activeWindow.cursor = BufferPosition(line: 2, column: 1)
    let helpBuffer = newTextBuffer("help line 1")
    discard
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpInPlace)
    e.activeWindow.cursor = BufferPosition(line: 0, column: 6)
    let entry = e.leaveViewerModeForJump(EditorMode.Help)
    check entry.isSome
    check e.activeWindow.mode == EditorMode.Normal
    # The jump list anchors at the cursor, so it must be the origin, not the
    # listing's.
    check e.activeWindow.cursor == BufferPosition(line: 2, column: 1)

suite "viewer_mode - resuming what an in-place viewer covered":
  test "a FileTree window gets its FileTree state back":
    let (e, path) = editorOnFile("moe_viewer_resume_filetree.txt")
    defer:
      removeFile(path)
    e.toggleFileTree(none(string), e.activeBuffer())
    require e.focusFileTreeWindow()
    let win = e.activeWindow
    let ftState = win.modeState.fileTree
    let ftView = win.buffer
    discard e.enterViewerMode(
      EditorMode.Help, makeHelpModeState(), newTextBuffer("help"), vpInPlace
    )
    require win.mode == EditorMode.Help

    e.leaveViewerMode(EditorMode.Help)

    check win.mode == EditorMode.FileTree
    check win.modeState.kind == mskFileTree
    if win.modeState.kind == mskFileTree:
      check win.modeState.fileTree == ftState
    check win.buffer == ftView

suite "viewer_mode - tab switch teardown":
  test "a tab switch drops a viewer entry owned by a suspended mode":
    # Regression: `clearModeState` only drops the entry belonging to the mode
    # it tears down, so the DiffViewer-over-BackupManager overlay left the
    # BackupManager's entry behind on a window now showing an unrelated tab.
    let (e, path) = editorOnFile("moe_viewer_tabswitch.txt")
    defer:
      removeFile(path)
    let listing = newTextBuffer("backups")
    let entered = e.enterViewerMode(
      EditorMode.BackupManager,
      ModeState(kind: mskBackupManager, backupManager: newBackupManagerState()),
      listing,
      vpInPlace,
    )
    check entered.isOk
    # The diff overlays the listing: (mode, modeState) are suspended and the
    # BackupManager's entry stays on the window.
    e.activeWindow.suspendMode()
    e.activeWindow.modeState =
      ModeState(kind: mskDiffViewer, diffViewer: newDiffViewerState())
    e.setMode(EditorMode.DiffViewer)

    e.switchToBufferByIndex(0)

    check e.activeWindow.viewerEntry.isNone
    check e.activeWindow.suspendedMode.isNone
    check e.activeWindow.modeState.kind == mskNone
    check e.activeWindow.mode == EditorMode.Normal
    check not e.focusExistingViewerWindow(EditorMode.BackupManager)
