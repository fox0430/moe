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
    window_manager, backup_manager, diff_viewer,
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
    check entry.get.returnTab == originalBuffer.id
    check e.activeBuffer == helpBuffer

  test "re-entering the same mode keeps the original snapshot":
    let (e, path) = editorOnFile("moe_viewer_enter2.txt")
    defer:
      removeFile(path)
    e.activeWindow.cursor = BufferPosition(line: 1, column: 1)
    let helpBuffer = newTextBuffer("help line 1")
    let result =
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), helpBuffer, vpInPlace)
    check result.isOk
    let againBuffer = newTextBuffer("other")
    let again =
      e.enterViewerMode(EditorMode.Help, makeHelpModeState(), againBuffer, vpInPlace)
    check again.isOk
    check e.activeWindow.viewerEntry.get.originCursor ==
      BufferPosition(line: 1, column: 1)
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

  test "resumes Normal on the last character of a line that shrank":
    let (e, path) = editorOnFile("moe_viewer_leave_shrunk.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer
    e.activeWindow.cursor = BufferPosition(line: 1, column: 3)
    discard e.enterViewerMode(
      EditorMode.Help, makeHelpModeState(), newTextBuffer("help"), vpInPlace
    )
    require fileBuf.replaceAllLines(["ab"]).isOk

    e.leaveViewerMode(EditorMode.Help)

    check e.activeWindow.mode == EditorMode.Normal
    check e.activeWindow.cursor == BufferPosition(line: 0, column: 1)

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

  test ":bd closes the split, as Vim closes the windows on a deleted buffer":
    let (e, path) = editorOnFile("moe_viewer_vsplit_bd.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let fileBuffer = e.activeBuffer()
    let windowCount = e.windowManager.windows.len
    discard e.enterViewerMode(
      EditorMode.Help, makeHelpModeState(), newTextBuffer("help line 1"), vpVSplit
    )

    check e.deleteCurrentBuffer().isOk

    check e.windowManager.windows.len == windowCount
    check e.activeWindow == origWin
    check e.bufferById(fileBuffer.id).isSome
    check origWin.buffer == fileBuffer

  test ":bd in the last window keeps it and goes back to the covered tab":
    let (e, path) = editorOnFile("moe_viewer_vsplit_bd_last.txt")
    defer:
      removeFile(path)
    let fileBuffer = e.activeBuffer()
    discard e.enterViewerMode(
      EditorMode.Help, makeHelpModeState(), newTextBuffer("help line 1"), vpVSplit
    )
    let win = e.activeWindow
    e.windowManager.onlyWindow(e.screenSize.width, e.screenSize.height)
    e.syncActiveWindow()
    require e.windowManager.windows.len == 1

    check e.deleteCurrentBuffer().isOk

    check e.activeWindow == win
    check win.viewerEntry.isNone
    check win.modeState.kind == mskNone
    check win.mode == EditorMode.Normal
    check win.buffer == fileBuffer
    check e.bufferById(fileBuffer.id).isSome

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

suite "viewer_mode - from the FileTree sidebar":
  test "an in-place viewer covers the file window, not the sidebar":
    let (e, path) = editorOnFile("moe_viewer_from_filetree.txt")
    defer:
      removeFile(path)
    let fileWin = e.activeWindow
    let fileBuf = fileWin.buffer
    e.toggleFileTree(none(string), e.activeBuffer())
    require e.focusFileTreeWindow()
    let tree = e.activeWindow
    let ftState = tree.modeState.fileTree

    check e.enterViewerMode(
      EditorMode.Help, makeHelpModeState(), newTextBuffer("help"), vpInPlace
    ).isOk

    check e.activeWindow == fileWin
    check fileWin.mode == EditorMode.Help
    check tree.mode == EditorMode.FileTree
    check tree.viewerEntry.isNone

    e.leaveViewerMode(EditorMode.Help)

    check fileWin.mode == EditorMode.Normal
    check fileWin.buffer == fileBuf
    check tree.modeState.kind == mskFileTree
    if tree.modeState.kind == mskFileTree:
      check tree.modeState.fileTree == ftState

suite "viewer_mode - tab switch teardown":
  test "a tab switch drops the backup manager's viewer entry from under a diff":
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
    # The diff covers the listing and holds the backup manager; the
    # BackupManager's entry stays on the window.
    e.activeWindow.modeState = ModeState(
      kind: mskDiffViewer,
      diffViewer: newDiffViewerState(),
      diffReturn: e.activeWindow.modeState.backupManager,
    )
    e.setMode(EditorMode.DiffViewer)

    e.switchToBufferByIndex(0)

    check e.activeWindow.viewerEntry.isNone
    check e.activeWindow.modeState.kind == mskNone
    check e.activeWindow.mode == EditorMode.Normal
    check not e.focusExistingViewerWindow(EditorMode.BackupManager)

  test "a tab switch drops the viewer's state after a mode switch over it":
    # `mode_switch` to a text mode only flips the mode, so the mode no longer
    # names the state the viewer left on the window.
    let (e, path) = editorOnFile("moe_viewer_tabswitch_modeswitch.txt")
    defer:
      removeFile(path)
    let entered = e.enterViewerMode(
      EditorMode.BackupManager,
      ModeState(kind: mskBackupManager, backupManager: newBackupManagerState()),
      newTextBuffer("backups"),
      vpInPlace,
    )
    check entered.isOk
    e.setMode(EditorMode.Normal)

    e.switchToBufferByIndex(0)

    check e.activeWindow.viewerEntry.isNone
    check e.activeWindow.modeState.kind == mskNone
    check e.activeWindow.mode == EditorMode.Normal

suite "viewer_mode - splitting from an in-place viewer":
  test "a split of the covered tab starts where the tab was, not at the listing's cursor":
    for (vertical, withFilename) in [
      (false, false), (false, true), (true, false), (true, true)
    ]:
      checkpoint "vertical=" & $vertical & " withFilename=" & $withFilename
      let (e, path) = editorOnFile("moe_viewer_split_origin.txt")
      defer:
        removeFile(path)
      let fileBuffer = e.activeBuffer
      e.activeWindow.cursor = BufferPosition(line: 2, column: 1)
      discard e.enterViewerMode(
        EditorMode.Help, makeHelpModeState(), newTextBuffer("help 1\nhelp 2"), vpInPlace
      )
      e.activeWindow.cursor = BufferPosition(line: 1, column: 5)

      let filename =
        if withFilename:
          some(path)
        else:
          none(string)
      check (if vertical: e.vsplit(filename) else: e.hsplit(filename)).isOk

      check e.activeWindow.buffer == fileBuffer
      check e.activeWindow.cursor == BufferPosition(line: 2, column: 1)
