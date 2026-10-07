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

## A split viewer (`:help`, `:log`, `:backup`, ...) opens a window on the
## active tab, as `:split` does, and covers it with its listing. The listing is
## never registered as a buffer, so it cannot be listed, switched to, or left
## behind, and ending the viewer leaves the window's tab as it was.

import std/[unittest, os, options, strutils, times, monotimes]

import pkg/[results, celina]

import
  ../src/moepkg/[
    editor, config, config_loader, types, editor_window, editor_buffers, window_manager,
    editor_frame,
  ]
import ../src/moepkg/command_handlers/[handler_result, result_processor, editor_ops]
import ../src/moepkg/buffer/edit
import ../src/moepkg/lsp/protocol/types as lspTypes
from ../src/moepkg/command_registry/core import recordJump

proc createTestEditor(): Editor =
  let config = newEditorConfig()
  let vr = newValidationResult()
  result = newEditor(config, vr)

proc editorOnFile(name: string): tuple[e: Editor, path: string] =
  let path = getTempDir() / name
  writeFile(path, "line0\nline1\n")
  let e = createTestEditor()
  check e.editFile(path).isOk
  (e, path)

proc run(e: Editor, r: HandlerResult) =
  discard e.processResult(r, e.activeBuffer())

proc openHelp(e: Editor): tuple[win: EditorWindow, listing: TextBuffer] =
  e.run(HandlerResult(kind: hrEnterHelpViewer))
  let win = e.activeWindow
  require win.viewerEntry.isSome
  (win, win.buffer)

proc focus(e: Editor, win: EditorWindow) =
  for i, w in e.windowManager.windows:
    if w == win:
      e.windowManager.activateWindow(i)
  e.syncActiveWindow()

template checkOnTab(e: Editor, win: EditorWindow, tab: TextBuffer) =
  ## `win` is out of any viewer and draws `tab`, a live buffer it lists.
  check win.viewerEntry.isNone
  check win.mode == EditorMode.Normal
  check win.tabBufferId == tab.id
  check win.buffer == tab
  check e.bufferById(tab.id).isSome
  check tab.id in win.bufferIds

suite "Split viewer - covers a split of the active tab":
  test "entering registers no buffer":
    let (e, path) = editorOnFile("moe_sv_enter.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let buffersBefore = e.buffers.len

    let (helpWin, listing) = e.openHelp()

    check e.buffers.len == buffersBefore
    check e.bufferById(listing.id).isNone
    check helpWin.tabBufferId == fileBuf.id
    check helpWin.buffer == listing

  test "the listing is neither listed nor reachable by :b":
    let (e, path) = editorOnFile("moe_sv_ls.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let origTab = origWin.tabBufferId
    let (_, listing) = e.openHelp()
    e.focus(origWin)

    for info in e.getBufferInfos():
      check info.number != listing.id.int
    check not e.switchToBuffer($listing.id.int)
    check e.tryActivateBuffer(listing.id).isErr
    check origWin.tabBufferId == origTab

  test ":vsplit inside the viewer shows the viewer in both, as Vim does":
    let (e, path) = editorOnFile("moe_sv_vsplit.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let buffersBefore = e.buffers.len
    let (helpWin, listing) = e.openHelp()
    helpWin.modeState.help.selectedIndex = 3
    helpWin.cursor = BufferPosition(line: 3, column: 0)

    e.run(HandlerResult(kind: hrVSplit))

    let dupWin = e.activeWindow
    require dupWin != helpWin
    check dupWin.mode == EditorMode.Help
    check dupWin.viewerEntry.get.mode == EditorMode.Help
    check dupWin.tabBufferId == fileBuf.id
    check dupWin.buffer == listing
    check dupWin.cursor == BufferPosition(line: 3, column: 0)
    check e.buffers.len == buffersBefore
    # Each window has its own selection.
    require dupWin.modeState.kind == mskHelp
    check dupWin.modeState.help != helpWin.modeState.help
    check dupWin.modeState.help.selectedIndex == 3
    dupWin.modeState.help.selectedIndex = 5
    check helpWin.modeState.help.selectedIndex == 3

    e.run(HandlerResult(kind: hrHelpViewerQuit))

    check dupWin notin e.windowManager.windows
    check helpWin in e.windowManager.windows
    check helpWin.mode == EditorMode.Help

  test "both copies of the debug viewer keep refreshing":
    let (e, path) = editorOnFile("moe_sv_debug_copies.txt")
    defer:
      removeFile(path)
    e.run(HandlerResult(kind: hrDebug))
    let debugWin = e.activeWindow
    require debugWin.mode == EditorMode.Debug
    e.run(HandlerResult(kind: hrVSplit))
    let dupWin = e.activeWindow
    require dupWin != debugWin
    require dupWin.mode == EditorMode.Debug

    let (before, dupBefore) = (debugWin.buffer, dupWin.buffer)
    e.state.timing.lastDebugUpdate = MonoTime()
    e.maybeUpdateDebugBuffer()
    check debugWin.buffer != before
    check dupWin.buffer != dupBefore

    # Closing one copy leaves the other refreshing.
    e.run(HandlerResult(kind: hrDebugViewerQuit))
    require dupWin notin e.windowManager.windows
    let after = debugWin.buffer
    e.state.timing.lastDebugUpdate = MonoTime()
    e.maybeUpdateDebugBuffer()
    check debugWin.buffer != after

  test ":vsplit from Visual in the viewer copies the listing, not the selection":
    let (e, path) = editorOnFile("moe_sv_vsplit_visual.txt")
    defer:
      removeFile(path)
    let (helpWin, _) = e.openHelp()
    helpWin.cursor = BufferPosition(line: 3, column: 0)
    e.state.previousMode = e.state.mode
    e.state.mode = EditorMode.Visual
    helpWin.cursor = BufferPosition(line: 5, column: 0)

    e.run(HandlerResult(kind: hrVSplit))

    let dupWin = e.activeWindow
    require dupWin != helpWin
    check dupWin.mode == EditorMode.Help
    check dupWin.cursor == BufferPosition(line: 5, column: 0)
    check helpWin.mode == EditorMode.Help

  test ":split inside an in-place viewer opens it again in a split":
    let (e, path) = editorOnFile("moe_sv_split_inplace.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let origWin = e.activeWindow
    e.run(HandlerResult(kind: hrEnterBufferManager))
    require origWin.mode == EditorMode.BufferManager

    e.run(HandlerResult(kind: hrHSplit))

    let dupWin = e.activeWindow
    require dupWin != origWin
    check dupWin.mode == EditorMode.BufferManager
    check dupWin.viewerEntry.get.placement == vpHSplit

    e.run(HandlerResult(kind: hrBufferManagerQuit))

    check dupWin notin e.windowManager.windows
    check origWin.mode == EditorMode.BufferManager
    e.focus(origWin)
    e.run(HandlerResult(kind: hrBufferManagerQuit))
    e.checkOnTab(origWin, fileBuf)

  test ":vsplit with a file inside the viewer opens the file":
    let (e, path) = editorOnFile("moe_sv_vsplit_file.txt")
    defer:
      removeFile(path)
    let other = getTempDir() / "moe_sv_vsplit_other.txt"
    writeFile(other, "other\n")
    defer:
      removeFile(other)
    let (helpWin, _) = e.openHelp()

    e.run(HandlerResult(kind: hrVSplit, vsplitFilename: some(other)))

    let fileWin = e.activeWindow
    require fileWin != helpWin
    check fileWin.viewerEntry.isNone
    check e.tabBuffer(fileWin).filePath == some(other)
    check helpWin.mode == EditorMode.Help

suite "Split viewer - tab line":
  test "the viewer's window marks no tab current":
    # Vim leaves the listed buffers unmarked while a window shows an unlisted
    # one (a help buffer); the covered file is not what the window shows.
    let config = newEditorConfig()
    config.theme.kind = tkDefault
    config.tabLine.enable = true
    let e = newEditor(config, newValidationResult())
    let path = getTempDir() / "moe_sv_tabline.txt"
    writeFile(path, "line0\nline1\n")
    defer:
      removeFile(path)
    require e.editFile(path).isOk
    let fileWin = e.activeWindow
    let (helpWin, _) = e.openHelp()
    var screen = newBuffer(120, 40)

    e.render(screen)

    proc tabCell(win: EditorWindow): Cell =
      ## The first cell of the file's tab in `win`'s tab line.
      let name = path.extractFilename
      for x in win.viewport.x ..< win.viewport.x + win.viewport.width - name.len:
        var text = ""
        for i in 0 ..< name.len:
          text.add screen[x + i, win.viewport.y].symbol
        if text == name:
          return screen[x, win.viewport.y]
      check false

    check fileWin.tabCell.style != helpWin.tabCell.style

suite "Split viewer - ending it":
  test "q with other windows open closes the viewer's window":
    let (e, path) = editorOnFile("moe_sv_q.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let fileBuf = e.activeBuffer()
    let buffersBefore = e.buffers.len
    let (helpWin, _) = e.openHelp()

    e.run(HandlerResult(kind: hrHelpViewerQuit))

    check helpWin notin e.windowManager.windows
    check e.activeWindow == origWin
    check e.buffers.len == buffersBefore
    e.checkOnTab(origWin, fileBuf)

  test "q as the only window returns to the covered tab where the split was made":
    let (e, path) = editorOnFile("moe_sv_sole.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    e.activeWindow.cursor = BufferPosition(line: 1, column: 2)
    let buffersBefore = e.buffers.len
    let (helpWin, _) = e.openHelp()
    e.run(HandlerResult(kind: hrOnlyWindow))
    require e.windowManager.windows.len == 1

    e.run(HandlerResult(kind: hrHelpViewerQuit))

    check e.activeWindow == helpWin
    check e.buffers.len == buffersBefore
    e.checkOnTab(helpWin, fileBuf)
    check helpWin.cursor == BufferPosition(line: 1, column: 2)

  test ":b N inside the viewer ends it and leaves nothing behind":
    let (e, path) = editorOnFile("moe_sv_b_inside.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let buffersBefore = e.buffers.len

    for _ in 0 ..< 3:
      let (helpWin, _) = e.openHelp()
      e.run(HandlerResult(kind: hrBuffer, bufferArg: $fileBuf.id.int))
      e.checkOnTab(helpWin, fileBuf)
      e.run(HandlerResult(kind: hrCloseWindow))

    check e.buffers.len == buffersBefore

  test "a refreshed viewer ends as cleanly":
    # Refreshing swaps in a new listing.
    let (e, path) = editorOnFile("moe_sv_refreshed.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let buffersBefore = e.buffers.len
    e.run(HandlerResult(kind: hrEnterLogViewer))
    let logWin = e.activeWindow
    let first = logWin.buffer
    e.run(HandlerResult(kind: hrLogViewerRefresh))
    require logWin.buffer != first

    e.run(HandlerResult(kind: hrBuffer, bufferArg: $fileBuf.id.int))

    check e.buffers.len == buffersBefore
    e.checkOnTab(logWin, fileBuf)

  test ":only from another window ends the viewer with its window":
    let (e, path) = editorOnFile("moe_sv_only.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let buffersBefore = e.buffers.len
    discard e.openHelp()
    e.focus(origWin)

    e.run(HandlerResult(kind: hrOnlyWindow))

    check e.windowManager.windows.len == 1
    check e.buffers.len == buffersBefore

  test ":bd inside the viewer closes its window and keeps the covered buffer":
    let (e, path) = editorOnFile("moe_sv_bd.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let fileBuf = e.activeBuffer()
    let windowsBefore = e.windowManager.windows.len
    let (helpWin, _) = e.openHelp()

    e.run(HandlerResult(kind: hrBufferDelete))

    check helpWin notin e.windowManager.windows
    check e.windowManager.windows.len == windowsBefore
    check e.activeWindow == origWin
    e.checkOnTab(origWin, fileBuf)

  test ":bd inside the viewer as the only window returns to the covered tab":
    let (e, path) = editorOnFile("moe_sv_bd_sole.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let (helpWin, _) = e.openHelp()
    e.run(HandlerResult(kind: hrOnlyWindow))
    require e.windowManager.windows.len == 1

    e.run(HandlerResult(kind: hrBufferDelete))

    check e.activeWindow == helpWin
    e.checkOnTab(helpWin, fileBuf)

  test ":bd of the covered buffer elsewhere moves the viewer's tab along":
    let (e, path) = editorOnFile("moe_sv_bd_under.txt")
    defer:
      removeFile(path)
    let origWin = e.activeWindow
    let fileBuf = e.activeBuffer()
    let (helpWin, listing) = e.openHelp()
    e.focus(origWin)

    e.run(HandlerResult(kind: hrBufferDelete))

    check e.bufferById(fileBuf.id).isNone
    check helpWin.viewerEntry.isSome
    check helpWin.buffer == listing
    check helpWin.tabBufferId == origWin.tabBufferId
    check e.bufferById(helpWin.tabBufferId).isSome

suite "Split viewer - what is taken from inside it":
  test ":backup from inside the listing is about the covered file":
    let (e, path) = editorOnFile("moe_sv_backup_source.txt")
    defer:
      removeFile(path)
    discard e.openHelp()

    e.run(HandlerResult(kind: hrEnterBackupManager))

    let win = e.activeWindow
    require win.modeState.kind == mskBackupManager
    check win.modeState.backupManager.sourceFilePath == absolutePath(path)

  test ":recover from inside the listing is about the covered file":
    let (e, path) = editorOnFile("moe_sv_recover_source.txt")
    defer:
      removeFile(path)
    discard e.openHelp()

    e.run(HandlerResult(kind: hrEnterRecoveryManager))

    let win = e.activeWindow
    require win.modeState.kind == mskRecoveryManager
    check win.modeState.recoveryManager.sourceFilePath == absolutePath(path)

  test "a jump recorded in the listing does not resolve to the covered file":
    # The position is the listing's: filed under the file, Ctrl-o there would
    # land on the listing's line.
    let (e, path) = editorOnFile("moe_sv_jump.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let (helpWin, _) = e.openHelp()
    recordJump(e.state, BufferPosition(line: 40, column: 3))
    e.run(HandlerResult(kind: hrHelpViewerQuit))

    let jump = e.state.jumpList.list[^1]
    check jump.line == 40
    check jump.bufferId != fileBuf.id
    check e.bufferById(jump.bufferId).isNone
    check e.state.windowDisplay.currentBufferId == fileBuf.id
    check helpWin notin e.windowManager.windows

  test "the filer opens from the tab of the window the viewer hands focus to":
    # That window runs an in-place viewer whose covered buffer was deleted, so
    # only its tab still names a live file.
    let dirA = getTempDir() / "moe_sv_filer_a"
    let dirB = getTempDir() / "moe_sv_filer_b"
    createDir(dirA)
    createDir(dirB)
    defer:
      removeDir(dirA)
      removeDir(dirB)
    let fooPath = dirB / "foo.txt"
    let barPath = dirA / "bar.txt"
    writeFile(fooPath, "foo\n")
    writeFile(barPath, "bar\n")
    let e = createTestEditor()
    require e.editFile(fooPath).isOk
    let winA = e.activeWindow
    e.run(HandlerResult(kind: hrVSplit))
    let winB = e.activeWindow
    require e.editFile(barPath).isOk
    let barBuf = e.activeBuffer()
    e.focus(winA)
    require e.editFile(barPath).isOk
    e.run(HandlerResult(kind: hrEnterBufferManager))
    e.focus(winB)
    require e.deleteBufferById(barBuf.id).isOk
    require e.tabBuffer(winA).filePath == some(fooPath)
    e.focus(winA)
    discard e.openHelp()

    e.run(HandlerResult(kind: hrEnterFiler))

    check e.activeWindow == winA
    require winA.modeState.kind == mskFiler
    check winA.modeState.filer.currentPath.lastPathPart == "moe_sv_filer_b"

proc openBackupDiff(e: Editor): EditorWindow =
  ## `:backup`, then the diff of an entry, through the real handlers.
  e.run(HandlerResult(kind: hrEnterBackupManager))
  result = e.activeWindow
  require result.modeState.kind == mskBackupManager
  let backup = getTempDir() / "moe_sv_backup.txt"
  writeFile(backup, "line0\nchanged\n")
  result.modeState.backupManager.items.add(
    BackupEntry(filename: "backup", timestamp: now(), fullPath: backup)
  )
  e.run(HandlerResult(kind: hrBackupManagerOpenDiff, diffBackupIndex: 0))
  require result.modeState.kind == mskDiffViewer

template checkNoModeState(win: EditorWindow) =
  ## Neither the diff nor the backup manager it holds is left on `win`.
  check win.modeState.kind == mskNone

suite "Split viewer - with a DiffViewer over it":
  test ":vsplit in the diff opens the diff again over its own backup manager":
    let (e, path) = editorOnFile("moe_sv_diff_vsplit.txt")
    defer:
      removeFile(path)
    let win = e.openBackupDiff()
    let bkState = win.modeState.diffReturn

    e.run(HandlerResult(kind: hrVSplit))

    let dupWin = e.activeWindow
    require dupWin != win
    check dupWin.mode == EditorMode.DiffViewer
    check dupWin.viewerEntry.get.mode == EditorMode.BackupManager
    require dupWin.modeState.kind == mskDiffViewer
    check dupWin.modeState.diffReturn != bkState

    e.run(HandlerResult(kind: hrDiffViewerQuit))

    check dupWin.mode == EditorMode.BackupManager
    check win.mode == EditorMode.DiffViewer
    check win.modeState.diffReturn == bkState

  test "q after the diff, as the only window, returns to the covered tab":
    let (e, path) = editorOnFile("moe_sv_diff_q.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let win = e.openBackupDiff()
    e.run(HandlerResult(kind: hrDiffViewerQuit))
    e.run(HandlerResult(kind: hrOnlyWindow))
    require e.windowManager.windows.len == 1

    e.run(HandlerResult(kind: hrBackupManagerQuit))

    e.checkOnTab(win, fileBuf)
    win.checkNoModeState()

  test ":bd from the diff, as the only window, ends both":
    let (e, path) = editorOnFile("moe_sv_diff_bd.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let win = e.openBackupDiff()
    e.run(HandlerResult(kind: hrOnlyWindow))
    require e.windowManager.windows.len == 1

    e.run(HandlerResult(kind: hrBufferDelete))

    e.checkOnTab(win, fileBuf)
    win.checkNoModeState()

  test "an in-place viewer opened from the diff returns to the covered tab":
    let (e, path) = editorOnFile("moe_sv_diff_bm.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let win = e.openBackupDiff()
    e.run(HandlerResult(kind: hrOnlyWindow))
    require e.windowManager.windows.len == 1

    e.run(HandlerResult(kind: hrEnterBufferManager))
    require win.mode == EditorMode.BufferManager
    e.run(HandlerResult(kind: hrBufferManagerQuit))

    e.checkOnTab(win, fileBuf)
    win.checkNoModeState()

suite "Split viewer - a split made from a listing starts where the tab was":
  test "a split viewer opened from another starts at the covered position":
    let (e, path) = editorOnFile("moe_sv_from_split.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    e.activeWindow.cursor = BufferPosition(line: 1, column: 2)
    let (helpWin, _) = e.openHelp()
    helpWin.cursor = BufferPosition(line: 40, column: 3)
    helpWin.viewport.topLine = 30

    e.run(HandlerResult(kind: hrEnterLogViewer))
    let logWin = e.activeWindow
    require logWin != helpWin
    check logWin.viewerEntry.get.originCursor == BufferPosition(line: 1, column: 2)
    check logWin.viewerEntry.get.originTopLine == 0

    e.run(HandlerResult(kind: hrOnlyWindow))
    e.run(HandlerResult(kind: hrLogViewerQuit))
    e.checkOnTab(logWin, fileBuf)
    check logWin.cursor == BufferPosition(line: 1, column: 2)

  test "a split viewer opened from an in-place one starts at the covered position":
    let (e, path) = editorOnFile("moe_sv_from_inplace.txt")
    defer:
      removeFile(path)
    e.activeWindow.cursor = BufferPosition(line: 1, column: 2)
    e.run(HandlerResult(kind: hrEnterBufferManager))
    e.activeWindow.cursor = BufferPosition(line: 30, column: 4)

    let (helpWin, _) = e.openHelp()

    check helpWin.viewerEntry.get.originCursor == BufferPosition(line: 1, column: 2)

  test "a viewer split from a viewer covers the tab within it, even after it shrank":
    let (e, path) = editorOnFile("moe_sv_vsplit_shrunk.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    e.activeWindow.cursor = BufferPosition(line: 1, column: 4)
    let (helpWin, _) = e.openHelp()
    helpWin.cursor = BufferPosition(line: 40, column: 3)
    require fileBuf.replaceAllLines(["ab"]).isOk

    e.run(HandlerResult(kind: hrVSplit))

    let dupWin = e.activeWindow
    require dupWin != helpWin
    # Normal: on the last character, not past it.
    check dupWin.viewerEntry.get.originCursor == BufferPosition(line: 0, column: 1)
    e.run(HandlerResult(kind: hrOnlyWindow))
    e.run(HandlerResult(kind: hrHelpViewerQuit))
    e.checkOnTab(dupWin, fileBuf)
    check dupWin.cursor == BufferPosition(line: 0, column: 1)

  test "a viewer split after its tab moved starts at the fallback position":
    # splitOrigin falls back when the window left its returnTab: :bd elsewhere
    # moves the tab via retabTo while returnTab stays stale. The survivor keeps
    # the covered position valid, so a non-fallback path would reuse it.
    let (e, path) = editorOnFile("moe_sv_vsplit_moved.txt")
    let otherPath = getTempDir() / "moe_sv_vsplit_moved_other.txt"
    writeFile(otherPath, "a0\na1\na2\na3\n")
    defer:
      removeFile(path)
      removeFile(otherPath)
    require e.editFile(otherPath).isOk
    let otherBuf = e.activeBuffer()
    require e.editFile(path).isOk
    e.activeWindow.cursor = BufferPosition(line: 1, column: 1)
    let origWin = e.activeWindow
    let fileBuf = e.activeBuffer()
    let (helpWin, _) = e.openHelp()
    helpWin.cursor = BufferPosition(line: 3, column: 0)
    e.focus(origWin)

    e.run(HandlerResult(kind: hrBufferDelete))

    require helpWin.viewerEntry.isSome
    check helpWin.viewerEntry.get.returnTab == fileBuf.id
    require helpWin.tabBufferId != helpWin.viewerEntry.get.returnTab
    check helpWin.tabBufferId == otherBuf.id
    check helpWin.tabBufferId == origWin.tabBufferId
    e.focus(helpWin)

    e.run(HandlerResult(kind: hrVSplit))

    let dupWin = e.activeWindow
    require dupWin != helpWin
    check dupWin.mode == EditorMode.Help
    check dupWin.viewerEntry.get.placement == vpVSplit
    check dupWin.tabBufferId == helpWin.tabBufferId
    check e.bufferById(dupWin.tabBufferId).isSome
    check dupWin.viewerEntry.get.originCursor == BufferPosition(line: 0, column: 0)
    check dupWin.viewerEntry.get.originTopLine == 0
    # The listing position itself is preserved, not reset.
    check dupWin.cursor == BufferPosition(line: 3, column: 0)

proc openFileTree(e: Editor): EditorWindow =
  e.toggleFileTree(none(string), e.activeBuffer())
  require e.focusFileTreeWindow()
  e.activeWindow

proc loneSidebar(e: Editor): EditorWindow =
  ## Open the sidebar and close the file window, leaving the sidebar focused.
  let fileWin = e.activeWindow
  let tree = e.openFileTree()
  e.focus(fileWin)
  require not e.closeWindow()
  require e.windowManager.windows.len == 1
  require e.activeWindow == tree
  tree

proc resize(e: Editor, width, height: int) =
  e.windowManager.resizeWindows(
    width, height, e.screenSize.width, e.screenSize.height, e.multiStatusLine
  )
  e.screenSize.width = width
  e.screenSize.height = height

template checkSidebar(e: Editor, tree: EditorWindow) =
  ## `tree` is still the FileTree sidebar, uncovered.
  check tree in e.windowManager.windows
  check tree.mode == EditorMode.FileTree
  check tree.modeState.kind == mskFileTree
  check tree.viewerEntry.isNone
  check tree.fixedWidth.isSome

suite "Split viewer - with the FileTree sidebar":
  test "opened from the sidebar, it splits the file window instead":
    let (e, path) = editorOnFile("moe_sv_tree_open.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let fileWin = e.activeWindow
    let buffersBefore = e.buffers.len
    let tree = e.openFileTree()
    let treeView = tree.buffer
    let treeWidth = tree.viewport.width

    let (win, _) = e.openHelp()

    check e.buffers.len == buffersBefore
    check e.bufferById(treeView.id).isNone
    check win != tree
    check win.tabBufferId == fileBuf.id
    check e.windowManager.windows.len == 3
    check tree.mode == EditorMode.FileTree
    check tree.buffer == treeView
    check tree.viewport.width == treeWidth
    check fileWin.buffer == fileBuf

  test "beside only the sidebar, quitting goes back to the covered tab":
    let (e, path) = editorOnFile("moe_sv_tree_last.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let fileWin = e.activeWindow
    let tree = e.openFileTree()
    e.focus(fileWin)
    let (win, _) = e.openHelp()
    e.focus(fileWin)
    require not e.closeWindow()
    require e.windowManager.windows.len == 2
    e.focus(win)

    e.run(HandlerResult(kind: hrHelpViewerQuit))

    check e.windowManager.windows.len == 2
    check e.activeWindow == win
    e.checkOnTab(win, fileBuf)
    check tree.mode == EditorMode.FileTree

  test "with only the sidebar left, it opens a window beside it on the last opened buffer":
    let (e, path) = editorOnFile("moe_sv_tree_alone.txt")
    let lastPath = getTempDir() / "moe_sv_tree_alone_last.txt"
    writeFile(lastPath, "last\n")
    defer:
      removeFile(path)
      removeFile(lastPath)
    check e.editFile(lastPath).isOk
    let lastBuf = e.activeBuffer()
    check e.editFile(path).isOk
    let tree = e.loneSidebar()
    let buffersBefore = e.buffers.len

    let (win, _) = e.openHelp()

    check win != tree
    check e.windowManager.windows.len == 2
    check win.tabBufferId == lastBuf.id
    check e.buffers.len == buffersBefore
    e.checkSidebar(tree)

    e.run(HandlerResult(kind: hrHelpViewerQuit))

    check e.windowManager.windows.len == 2
    e.checkOnTab(win, lastBuf)
    e.checkSidebar(tree)

  test ":filetree over a viewer beside a lone sidebar closes the sidebar":
    let (e, path) = editorOnFile("moe_sv_tree_toggle.txt")
    defer:
      removeFile(path)
    discard e.loneSidebar()
    let (win, _) = e.openHelp()

    e.run(HandlerResult(kind: hrEnterFileTree, enterFileTreePath: none(string)))

    check e.windowManager.windows.len == 1
    check e.activeWindow == win
    check win.mode == EditorMode.Help
    check win.fixedWidth.isNone

  test ":vsplit in a viewer opened from a lone sidebar splits it":
    let (e, path) = editorOnFile("moe_sv_tree_vsplit.txt")
    defer:
      removeFile(path)
    let tree = e.loneSidebar()
    e.run(HandlerResult(kind: hrEnterBufferManager))
    let win = e.activeWindow
    require win != tree

    e.run(HandlerResult(kind: hrVSplit, vsplitFilename: none(string)))

    check e.windowManager.windows.len == 3
    check e.activeWindow != win
    check e.activeWindow.mode == EditorMode.BufferManager
    check win.mode == EditorMode.BufferManager
    e.checkSidebar(tree)

  test "an in-place viewer from the sidebar covers the file window":
    let (e, path) = editorOnFile("moe_sv_tree_inplace.txt")
    defer:
      removeFile(path)
    let fileWin = e.activeWindow
    let tree = e.openFileTree()

    e.run(HandlerResult(kind: hrEnterBufferManager))

    check e.windowManager.windows.len == 2
    check e.activeWindow == fileWin
    check fileWin.mode == EditorMode.BufferManager
    e.checkSidebar(tree)

  test "the filer from the sidebar starts in the file window's directory":
    let (e, path) = editorOnFile("moe_sv_tree_filer.txt")
    defer:
      removeFile(path)
    let fileWin = e.activeWindow
    let tree = e.openFileTree()

    e.run(HandlerResult(kind: hrEnterFiler))

    check e.activeWindow == fileWin
    require fileWin.modeState.kind == mskFiler
    check fileWin.modeState.filer.currentPath == path.parentDir
    e.checkSidebar(tree)

  test "with no room beside a lone sidebar, a viewer is refused":
    let (e, path) = editorOnFile("moe_sv_tree_noroom.txt")
    defer:
      removeFile(path)
    let tree = e.loneSidebar()
    tree.fixedWidth = some(tree.viewport.width)

    e.run(HandlerResult(kind: hrEnterHelpViewer))

    check e.windowManager.windows.len == 1
    check "not enough space" in e.state.statusMessage
    e.checkSidebar(tree)

    e.state.statusMessage = ""
    e.run(HandlerResult(kind: hrEnterBufferManager))

    check e.windowManager.windows.len == 1
    check "not enough space" in e.state.statusMessage
    e.checkSidebar(tree)

  test "after a resize, a viewer from a lone sidebar still opens beside it":
    let (e, path) = editorOnFile("moe_sv_tree_resize.txt")
    defer:
      removeFile(path)
    let tree = e.loneSidebar()
    e.resize(100, 30)
    require tree.viewport.width == tree.fixedWidth.get

    let (win, _) = e.openHelp()

    check win != tree
    check e.windowManager.windows.len == 2
    check win.viewport.x + win.viewport.width == e.screenSize.width
    e.checkSidebar(tree)

  test "after a resize, a file from a lone sidebar still opens beside it":
    let (e, path) = editorOnFile("moe_sv_tree_resize_open.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let tree = e.loneSidebar()
    e.resize(100, 30)

    e.run(HandlerResult(kind: hrFileTreeOpenFile, fileTreeFilePath: path))

    let win = e.activeWindow
    check win != tree
    check e.windowManager.windows.len == 2
    check win.tabBufferId == fileBuf.id
    check win.viewport.x + win.viewport.width == e.screenSize.width

  test ":backup and :recover from the sidebar are about the file it serves":
    let (e, path) = editorOnFile("moe_sv_tree_backup.txt")
    defer:
      removeFile(path)
    discard e.openFileTree()

    e.run(HandlerResult(kind: hrEnterBackupManager))

    require e.activeWindow.modeState.kind == mskBackupManager
    check e.activeWindow.modeState.backupManager.sourceFilePath == absolutePath(path)

    require e.focusFileTreeWindow()
    e.run(HandlerResult(kind: hrEnterRecoveryManager))

    require e.activeWindow.modeState.kind == mskRecoveryManager
    check e.activeWindow.modeState.recoveryManager.sourceFilePath == absolutePath(path)

  test ":backup from a lone sidebar is about the buffer its new window shows":
    let (e, path) = editorOnFile("moe_sv_tree_backup_alone.txt")
    defer:
      removeFile(path)
    let tree = e.loneSidebar()

    e.run(HandlerResult(kind: hrEnterBackupManager))

    check e.windowManager.windows.len == 2
    require e.activeWindow.modeState.kind == mskBackupManager
    check e.activeWindow.modeState.backupManager.sourceFilePath == absolutePath(path)
    e.checkSidebar(tree)

  test "the buffer manager from the sidebar marks the tab it serves":
    let (e, path) = editorOnFile("moe_sv_tree_bm_active.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    discard e.openFileTree()

    e.run(HandlerResult(kind: hrEnterBufferManager))

    require e.activeWindow.modeState.kind == mskBufferManager
    var marked: seq[int]
    for entry in e.activeWindow.modeState.bufferManager.items:
      if entry.active:
        marked.add(entry.number)
    check marked == @[fileBuf.id.int]

  test "from the sidebar, a viewer and a file go to the window last focused":
    let (e, path) = editorOnFile("moe_sv_tree_prev.txt")
    let otherPath = getTempDir() / "moe_sv_tree_prev_other.txt"
    writeFile(otherPath, "other\n")
    defer:
      removeFile(path)
      removeFile(otherPath)
    let fileBuf = e.activeBuffer()
    e.run(HandlerResult(kind: hrVSplit, vsplitFilename: none(string)))
    let tree = e.openFileTree()
    require e.windowManager.windows.len == 3
    let first = e.windowManager.windows[1]
    let last = e.windowManager.windows[2]
    e.focus(last)
    require e.focusFileTreeWindow()

    e.run(HandlerResult(kind: hrEnterBufferManager))

    check e.activeWindow == last
    check last.mode == EditorMode.BufferManager
    e.checkOnTab(first, fileBuf)

    e.run(HandlerResult(kind: hrBufferManagerQuit))
    require e.focusFileTreeWindow()
    e.run(HandlerResult(kind: hrFileTreeOpenFile, fileTreeFilePath: otherPath))

    check e.activeWindow == last
    check e.tabBuffer(last).filePath == some(otherPath)
    e.checkOnTab(first, fileBuf)
    e.checkSidebar(tree)

  test "a split viewer from the sidebar records the file window's mode as left":
    let (e, path) = editorOnFile("moe_sv_tree_prev_mode.txt")
    defer:
      removeFile(path)
    discard e.openFileTree()

    discard e.openHelp()

    check e.state.previousMode == EditorMode.Normal

suite "Split from the FileTree sidebar":
  template checkFilerOver(
      e: Editor, win, tree: EditorWindow, tab: TextBuffer, dir: string
  ) =
    ## `win` is a new window browsing `dir` in the Filer over `tab`.
    check win != tree
    check win.fixedWidth.isNone
    check win.mode == EditorMode.Filer
    check win.modeState.kind == mskFiler
    check win.modeState.filer.currentPath == dir
    check win.tabBufferId == tab.id

  for kind in [hrVSplit, hrHSplit]:
    test $kind & " browses the tree's root over the file window's tab":
      let (e, path) = editorOnFile("moe_sidebar_split_" & $kind & ".txt")
      defer:
        removeFile(path)
      let fileBuf = e.activeBuffer()
      let buffersBefore = e.buffers.len
      let tree = e.openFileTree()
      let treeView = tree.buffer
      let treeWidth = tree.fixedWidth.get
      let treeX = tree.viewport.x
      let treeY = tree.viewport.y
      let treeH = tree.viewport.height
      let root = tree.modeState.fileTree.rootPath

      e.run(HandlerResult(kind: kind))

      let win = e.activeWindow
      check e.windowManager.windows.len == 3
      check e.buffers.len == buffersBefore
      check e.bufferById(treeView.id).isNone
      e.checkFilerOver(win, tree, fileBuf, root)
      e.checkSidebar(tree)
      check tree.buffer == treeView
      check tree.fixedWidth.get == treeWidth
      # Regression: the split divides a main window, never the sidebar strip.
      check tree.viewport.x == treeX
      check tree.viewport.width == treeWidth
      check tree.viewport.y == treeY
      check tree.viewport.height == treeH
      check win.viewport.x >= tree.viewport.x + tree.viewport.width

      e.run(HandlerResult(kind: hrFilerQuit))

      e.checkOnTab(win, fileBuf)
      check e.buffers.len == buffersBefore

  test "a directory argument is browsed instead of the root":
    let (e, path) = editorOnFile("moe_sidebar_split_dir.txt")
    let dir = getTempDir() / "moe_sidebar_split_dir"
    createDir(dir)
    defer:
      removeFile(path)
      removeDir(dir)
    let fileBuf = e.activeBuffer()
    let buffersBefore = e.buffers.len
    let tree = e.openFileTree()

    e.run(HandlerResult(kind: hrVSplit, vsplitFilename: some(dir)))

    check e.buffers.len == buffersBefore
    e.checkFilerOver(e.activeWindow, tree, fileBuf, absolutePath(dir))
    e.checkSidebar(tree)

  for kind in [hrVSplit, hrHSplit]:
    test "from a lone sidebar " & $kind & " browses over the last opened buffer":
      let (e, path) = editorOnFile("moe_sidebar_split_lone_" & $kind & ".txt")
      defer:
        removeFile(path)
      let fileBuf = e.activeBuffer()
      let buffersBefore = e.buffers.len
      let tree = e.loneSidebar()
      let treeX = tree.viewport.x

      e.run(HandlerResult(kind: kind))

      check e.windowManager.windows.len == 2
      check e.buffers.len == buffersBefore
      e.checkFilerOver(e.activeWindow, tree, fileBuf, tree.modeState.fileTree.rootPath)
      e.checkSidebar(tree)
      # Regression: the new window opens beside the sidebar, never inside it.
      # The lone sidebar shrinks to its fixed width, as it does when any
      # window opens beside it.
      check tree.viewport.x == treeX
      check tree.viewport.width == tree.fixedWidth.get
      check e.activeWindow.viewport.x >= tree.viewport.x + tree.viewport.width

  for kind in [hrVSplit, hrHSplit]:
    test "from a lone sidebar " & $kind & " with no room keeps the sidebar and reports":
      # The lone-sidebar branch of splitFromSidebar refuses before opening
      # anything, as the parallel viewer path does.
      let (e, path) = editorOnFile("moe_sidebar_split_noroom_" & $kind & ".txt")
      defer:
        removeFile(path)
      let buffersBefore = e.buffers.len
      let tree = e.loneSidebar()
      tree.fixedWidth = some(tree.viewport.width)

      e.run(HandlerResult(kind: kind))

      check e.windowManager.windows.len == 1
      check e.activeWindow == tree
      check "not enough space" in e.state.statusMessage
      check e.buffers.len == buffersBefore
      e.checkSidebar(tree)

  for kind in [hrVSplit, hrHSplit]:
    test $kind & " with a file argument opens the file, registering no listing":
      let (e, path) = editorOnFile("moe_sidebar_split_file_" & $kind & ".txt")
      let other = getTempDir() / ("moe_sidebar_split_other_" & $kind & ".txt")
      writeFile(other, "other\n")
      defer:
        removeFile(path)
        removeFile(other)
      let buffersBefore = e.buffers.len
      let tree = e.openFileTree()
      let treeView = tree.buffer
      let treeX = tree.viewport.x
      let treeWidth = tree.viewport.width
      let treeY = tree.viewport.y
      let treeH = tree.viewport.height

      if kind == hrVSplit:
        e.run(HandlerResult(kind: hrVSplit, vsplitFilename: some(other)))
      else:
        e.run(HandlerResult(kind: hrHSplit, hsplitFilename: some(other)))

      let win = e.activeWindow
      check e.buffers.len == buffersBefore + 1
      check e.bufferById(treeView.id).isNone
      check win.mode == EditorMode.Normal
      check win.buffer.filePath == some(other)
      e.checkSidebar(tree)
      # Regression: the file opens in a split of a main window, never inside
      # the sidebar strip.
      check tree.viewport.x == treeX
      check tree.viewport.width == treeWidth
      check tree.viewport.y == treeY
      check tree.viewport.height == treeH
      check win.viewport.x >= tree.viewport.x + tree.viewport.width

  for kind in [hrVSplit, hrHSplit]:
    test $kind & " with a file argument from a lone sidebar opens the file beside it":
      let (e, path) = editorOnFile("moe_sidebar_split_lone_file_" & $kind & ".txt")
      let other = getTempDir() / ("moe_sidebar_split_lone_other_" & $kind & ".txt")
      writeFile(other, "other\n")
      defer:
        removeFile(path)
        removeFile(other)
      let buffersBefore = e.buffers.len
      let tree = e.loneSidebar()
      let treeView = tree.buffer
      let treeX = tree.viewport.x

      if kind == hrVSplit:
        e.run(HandlerResult(kind: hrVSplit, vsplitFilename: some(other)))
      else:
        e.run(HandlerResult(kind: hrHSplit, hsplitFilename: some(other)))

      let win = e.activeWindow
      check e.windowManager.windows.len == 2
      check e.buffers.len == buffersBefore + 1
      check e.bufferById(treeView.id).isNone
      check win.mode == EditorMode.Normal
      check win.buffer.filePath == some(other)
      e.checkSidebar(tree)
      # Regression: the file opens beside the sidebar, never inside its strip.
      check tree.viewport.x == treeX
      check tree.viewport.width == tree.fixedWidth.get
      check win.viewport.x >= tree.viewport.x + tree.viewport.width

  for kind in [hrVSplit, hrHSplit]:
    test $kind &
      " with a file argument from a lone sidebar and no room keeps the sidebar":
      # openFileInNewRightWindow checks the room before loading, so a refused
      # open registers nothing.
      let (e, path) =
        editorOnFile("moe_sidebar_split_lone_file_noroom_" & $kind & ".txt")
      let other =
        getTempDir() / ("moe_sidebar_split_lone_noroom_other_" & $kind & ".txt")
      writeFile(other, "other\n")
      defer:
        removeFile(path)
        removeFile(other)
      let buffersBefore = e.buffers.len
      let tree = e.loneSidebar()
      tree.fixedWidth = some(tree.viewport.width)

      if kind == hrVSplit:
        e.run(HandlerResult(kind: hrVSplit, vsplitFilename: some(other)))
      else:
        e.run(HandlerResult(kind: hrHSplit, hsplitFilename: some(other)))

      check e.windowManager.windows.len == 1
      check e.activeWindow == tree
      check "not enough space" in e.state.statusMessage
      check e.buffers.len == buffersBefore
      e.checkSidebar(tree)

  for kind in [hrVSplit, hrHSplit]:
    test $kind & " with an unreadable file keeps the focus in the sidebar":
      when defined(posix):
        let (e, path) = editorOnFile("moe_sidebar_split_unreadable_" & $kind & ".txt")
        let other =
          getTempDir() / ("moe_sidebar_split_unreadable_file_" & $kind & ".txt")
        writeFile(other, "secret\n")
        setFilePermissions(other, {})
        defer:
          setFilePermissions(other, {fpUserRead, fpUserWrite})
          removeFile(path)
          removeFile(other)
        var canRead = true
        try:
          discard readFile(other)
        except CatchableError:
          canRead = false
        if canRead:
          # Running as root: an unreadable file is still readable, so there is
          # no way to fail the load here.
          skip()
        let buffersBefore = e.buffers.len
        let tree = e.openFileTree()
        let windowsBefore = e.windowManager.windows.len

        if kind == hrVSplit:
          e.run(HandlerResult(kind: hrVSplit, vsplitFilename: some(other)))
        else:
          e.run(HandlerResult(kind: hrHSplit, hsplitFilename: some(other)))

        check e.activeWindow == tree
        check e.windowManager.windows.len == windowsBefore
        check e.buffers.len == buffersBefore
        e.checkSidebar(tree)

suite "Tab commands from the FileTree sidebar":
  ## The sidebar keeps its listing, as Vim's 'winfixbuf' window keeps its
  ## buffer: a command that would show another buffer there is refused, one
  ## that opens a window splits the window it serves, and the rest act on the
  ## listing, which refuses writes and reloads.
  proc twoFiles(name: string): tuple[e: Editor, first, second: TextBuffer] =
    let (e, _) = editorOnFile(name & "_a.txt")
    let first = e.activeBuffer()
    let other = getTempDir() / (name & "_b.txt")
    writeFile(other, "other\n")
    check e.editFile(other).isOk
    (e, first, e.activeBuffer())

  proc cleanup(name: string) =
    removeFile(getTempDir() / (name & "_a.txt"))
    removeFile(getTempDir() / (name & "_b.txt"))

  template checkUntouched(e: Editor, tree: EditorWindow, width: int) =
    e.checkSidebar(tree)
    check tree.viewport.x == 0
    check tree.viewport.width == width
    check e.bufferById(tree.buffer.id).isNone

  template checkRefused(e: Editor, tree: EditorWindow, width: int) =
    check e.activeWindow == tree
    check e.state.statusMessage.contains("E1513")
    e.checkUntouched(tree, width)

  for lone in [false, true]:
    let where = if lone: " from a lone sidebar" else: ""
    test "commands that show another buffer are refused" & where:
      let name = "moe_sidebar_tab_refuse" & (if lone: "_lone" else: "")
      let (e, first, _) = twoFiles(name)
      let third = getTempDir() / (name & "_c.txt")
      writeFile(third, "third\n")
      let absent = getTempDir() / (name & "_absent.txt")
      removeFile(absent)
      defer:
        cleanup(name)
        removeFile(third)
      let fileWin = e.activeWindow
      let tabBefore = fileWin.tabBufferId
      let tree =
        if lone:
          e.loneSidebar()
        else:
          e.openFileTree()
      let width = tree.viewport.width
      let windowsBefore = e.windowManager.windows.len
      let buffersBefore = e.buffers.len
      var refused = @[
        HandlerResult(kind: hrEdit, editFilename: some(third)),
        HandlerResult(kind: hrEdit, editFilename: some(absent)),
        HandlerResult(kind: hrBuffer, bufferArg: $first.id),
        HandlerResult(kind: hrEnew),
      ]
      when not defined(moe.embedded):
        refused.add HandlerResult(kind: hrEnterTerminal, enterTerminalCommand: "true")

      for r in refused:
        e.state.statusMessage = ""
        e.run(r)

        check e.windowManager.windows.len == windowsBefore
        check e.buffers.len == buffersBefore
        check first.id notin tree.bufferIds
        e.checkRefused(tree, width)
      if not lone:
        check fileWin.tabBufferId == tabBefore

  for kind in [hrBufferNext, hrBufferPrev, hrBufferFirst, hrBufferLast]:
    test $kind & " is refused on the sidebar with E1513 instead of E88":
      let name = "moe_sidebar_tab_cycle_" & $kind
      let (e, _, _) = twoFiles(name)
      defer:
        cleanup(name)
      let fileWin = e.activeWindow
      let tabBefore = fileWin.tabBufferId
      let buffersBefore = e.buffers.len
      let tree = e.openFileTree()
      let width = tree.viewport.width

      e.run(HandlerResult(kind: kind))

      check e.state.statusMessage == "E1513: Cannot switch buffer in the file tree"
      check e.activeWindow == tree
      check fileWin.tabBufferId == tabBefore
      check e.buffers.len == buffersBefore
      e.checkUntouched(tree, width)

  for force in [false, true]:
    test (if force: ":bd!" else: ":bd") & " closes the tree and deletes no buffer":
      let name = "moe_sidebar_tab_bd" & (if force: "_force" else: "")
      let (e, _, second) = twoFiles(name)
      defer:
        cleanup(name)
      let fileWin = e.activeWindow
      discard second.insertText(BufferPosition(line: 0, column: 0), "typed ")
      let buffersBefore = e.buffers.len
      let tree = e.openFileTree()

      e.run(HandlerResult(kind: hrBufferDelete, forceBufferDelete: force))

      check tree notin e.windowManager.windows
      check e.windowManager.windows.len == 1
      check e.activeWindow == fileWin
      e.checkOnTab(fileWin, second)
      check e.buffers.len == buffersBefore
      check second.getLine(0) == "typed other"

  for r in [
    HandlerResult(kind: hrBufferDelete, forceBufferDelete: true),
    HandlerResult(kind: hrFileTreeQuit),
    HandlerResult(kind: hrEnterFileTree),
  ]:
    test "from a lone sidebar, " & $r.kind & " leaves a window on the last opened buffer":
      let name = "moe_sidebar_tab_close_lone_" & $r.kind
      let (e, _, second) = twoFiles(name)
      defer:
        cleanup(name)
      discard second.insertText(BufferPosition(line: 0, column: 0), "typed ")
      let tree = e.loneSidebar()
      # A resize shrinks the lone sidebar to its fixed width.
      e.resize(e.screenSize.width + 10, e.screenSize.height)
      require tree.viewport.width < e.screenSize.width
      let height = tree.viewport.height
      let buffersBefore = e.buffers.len

      # Regression: `:bd!` ran on the last opened buffer, in a window opened for
      # it and closed again, and discarded its unsaved changes unseen; `q` and
      # `:filetree` left the window in FileTree mode with no tree, and then it
      # kept the tree's width and listed the listing as a tab. Each close also
      # added a new empty buffer while the user's file stayed hidden.
      e.run(r)

      let win = e.activeWindow
      check e.windowManager.windows.len == 1
      check win.fixedWidth.isNone
      check win.mode == EditorMode.Normal
      check win.modeState.kind == mskNone
      check e.state.mode == EditorMode.Normal
      e.checkOnTab(win, second)
      check win.bufferIds == @[second.id]
      check win.viewport.x == 0
      check win.viewport.width == e.screenSize.width
      check win.viewport.height == height
      check e.buffers.len == buffersBefore
      check second.getLine(0) == "typed other"

  for kind in [hrNew, hrVnew]:
    test $kind & " splits the served window, never the sidebar":
      let name = "moe_sidebar_tab_" & $kind
      let (e, _, _) = twoFiles(name)
      defer:
        cleanup(name)
      let fileWin = e.activeWindow
      let tree = e.openFileTree()
      let width = tree.viewport.width
      let height = tree.viewport.height

      e.run(HandlerResult(kind: kind))

      check e.windowManager.windows.len == 3
      check e.activeWindow notin [tree, fileWin]
      check e.activeBuffer().filePath.isNone
      check tree.viewport.height == height
      e.checkUntouched(tree, width)

    test $kind & " from a lone sidebar opens one window beside it":
      let name = "moe_sidebar_tab_lone_" & $kind
      let (e, _, _) = twoFiles(name)
      defer:
        cleanup(name)
      let tree = e.loneSidebar()
      let buffersBefore = e.buffers.len

      e.run(HandlerResult(kind: kind))

      check e.windowManager.windows.len == 2
      check e.activeWindow != tree
      check e.buffers.len == buffersBefore + 1
      check e.activeBuffer().filePath.isNone
      e.checkSidebar(tree)

  for lone in [false, true]:
    for command in [":e", ":e!"]:
      test command & " is refused" & (if lone: " from a lone sidebar" else: "") &
        ": the listing is not a file to reload":
        let name =
          "moe_sidebar_tab_reload" & (if command == ":e!": "_force" else: "") &
          (if lone: "_lone" else: "")
        let (e, _, second) = twoFiles(name)
        defer:
          cleanup(name)
        let tree =
          if lone:
            e.loneSidebar()
          else:
            e.openFileTree()
        let width = tree.viewport.width
        writeFile(second.filePath.get, "changed\n")
        discard second.insertText(BufferPosition(line: 0, column: 0), "typed ")

        check e.executeCommandOverlay(command)

        # Regression: the listing's root directory was "reloaded", and from a
        # lone sidebar the last opened buffer lost its unsaved changes.
        check second.getLine(0) == "typed other"
        check second.isModified
        check e.state.statusMessage.contains("Cannot reload a listing")
        check e.activeWindow == tree
        e.checkUntouched(tree, width)

  test ":w and :w <name> are refused: the listing is not a file":
    const name = "moe_sidebar_tab_write"
    let (e, _, _) = twoFiles(name)
    let dst = getTempDir() / (name & "_dst.txt")
    removeFile(dst)
    defer:
      cleanup(name)
      removeFile(dst)
    let tree = e.openFileTree()
    let width = tree.viewport.width

    # Regression: `:w <name>` wrote the listing's text to the file.
    check e.executeCommandOverlay(":w " & dst)
    check not fileExists(dst)
    check e.state.statusMessage.contains("Cannot write a listing")

    check e.executeCommandOverlay(":w")
    check e.state.statusMessage.contains("Cannot write a listing")
    check e.activeWindow == tree
    e.checkUntouched(tree, width)

  test "a tab-line click on the sidebar is refused with a reason":
    const name = "moe_sidebar_tab_click"
    let (e, _, _) = twoFiles(name)
    defer:
      cleanup(name)
    let tree = e.openFileTree()
    let width = tree.viewport.width
    e.state.statusMessage = ""

    # Regression: the click was dropped silently, and pruned the sidebar's own
    # listing out of its tab list as if a deleted buffer had left it behind.
    check not e.switchToWindowBuffer(0)

    check e.state.statusMessage.contains("E1513")
    check tree.bufferIds == @[tree.tabBufferId]
    e.checkUntouched(tree, width)

  test "a refused :bnext keeps its reason instead of clearing it":
    const name = "moe_sidebar_tab_bnext_refused"
    let (e, first, _) = twoFiles(name)
    defer:
      cleanup(name)
    let fileWin = e.activeWindow
    let tabBefore = fileWin.tabBufferId
    let tree = e.openFileTree()
    let width = tree.viewport.width
    require first.id notin tree.bufferIds
    tree.bufferIds.add(first.id)

    e.switchToNextBuffer()

    check e.state.statusMessage.contains("E1513")
    check fileWin.tabBufferId == tabBefore
    check tree.bufferIds.len == 2
    e.checkRefused(tree, width)

  test "a location response landing while the tree has focus splits the served window":
    const name = "moe_sidebar_tab_jump_open_window"
    let (e, _, _) = twoFiles(name)
    let third = getTempDir() / (name & "_c.txt")
    writeFile(third, "third\nline\n")
    defer:
      cleanup(name)
      removeFile(third)
    let fileWin = e.activeWindow
    let tabBefore = fileWin.tabBufferId
    fileWin.cursor = BufferPosition(line: 0, column: 2)
    let tree = e.openFileTree()
    let width = tree.viewport.width
    let buffersBefore = e.buffers.len

    # Regression: the split landed on the sidebar, halving its width and
    # registering the listing as a buffer it then listed as a tab. Then the
    # jump list recorded the listing, so `C-o` found no buffer to go back to.
    check e.jumpToLspLocation(
      lspTypes.Location(
        uri: "file://" & third,
        range: lspTypes.Range(
          start: lspTypes.Position(line: 1, character: 0),
          `end`: lspTypes.Position(line: 1, character: 4),
        ),
      ),
      "Definition",
      openWindow = true,
    )

    check e.windowManager.windows.len == 3
    check e.buffers.len == buffersBefore + 1
    check e.activeBuffer().filePath == some(absolutePath(third))
    check e.activeWindow != fileWin
    check fileWin.tabBufferId == tabBefore
    check e.state.jumpList.list[^1] ==
      JumpPosition(bufferId: tabBefore, line: 0, column: 2)
    e.checkUntouched(tree, width)

  test "a location response landing on a lone sidebar jumps into one new window":
    const name = "moe_sidebar_tab_jump_open_window_lone"
    let (e, _, second) = twoFiles(name)
    let third = getTempDir() / (name & "_c.txt")
    writeFile(third, "third\nline\n")
    defer:
      cleanup(name)
      removeFile(third)
    let tree = e.loneSidebar()
    let treeView = tree.buffer
    let sidebarWidth = tree.fixedWidth.get
    let buffersBefore = e.buffers.len

    # Regression: the split landed on the sidebar itself, so the jump opened a
    # second window on the listing and registered it as a buffer.
    check e.jumpToLspLocation(
      lspTypes.Location(
        uri: "file://" & third,
        range: lspTypes.Range(
          start: lspTypes.Position(line: 1, character: 0),
          `end`: lspTypes.Position(line: 1, character: 4),
        ),
      ),
      "Definition",
      openWindow = true,
    )

    check e.windowManager.windows.len == 2
    check e.buffers.len == buffersBefore + 1
    check e.activeBuffer().filePath == some(absolutePath(third))
    check e.activeWindow != tree
    check tree.viewport.x == 0
    check tree.viewport.width == sidebarWidth
    check e.bufferById(treeView.id).isNone
    # The jump starts in the window opened for it, not on the listing.
    check e.state.jumpList.list[^1].bufferId == second.id
    e.checkSidebar(tree)

  test "a jump that lands while the tree has focus moves nothing there":
    const name = "moe_sidebar_tab_jump"
    let (e, first, _) = twoFiles(name)
    let third = getTempDir() / (name & "_c.txt")
    writeFile(third, "third\nline\n")
    defer:
      cleanup(name)
      removeFile(third)
    let tree = e.openFileTree()
    let width = tree.viewport.width
    let cursorBefore = tree.cursor
    let buffersBefore = e.buffers.len
    let jumpsBefore = e.state.jumpList.list.len

    # Regression: the jump was taken as done and its position was set on the
    # listing; a refused jump still went into the jump list.
    check not e.openFileAndJumpTo(third, 1, 0)
    check not e.openFileAndJumpTo(first.filePath.get, 1, 0)
    check e.tryActivateBuffer(first.id).error.contains("E1513")
    check not e.activateBuffer(first.id)

    check e.state.jumpList.list.len == jumpsBefore
    check e.buffers.len == buffersBefore
    check tree.cursor == cursorBefore
    check first.id notin tree.bufferIds
    e.checkRefused(tree, width)

  test "deleting the last buffer while the tree has focus moves its windows":
    let (e, path) = editorOnFile("moe_sidebar_tab_last_buffer.txt")
    defer:
      removeFile(path)
    let fileBuf = e.activeBuffer()
    let fileWin = e.activeWindow
    let tree = e.openFileTree()
    let width = tree.viewport.width

    check e.deleteBufferById(fileBuf.id).isOk

    check e.buffers.len == 1
    e.checkOnTab(fileWin, e.buffers[0])
    check e.buffers[0].filePath.isNone
    check e.activeWindow == tree
    check e.bufferById(tree.buffer.id).isNone
    e.checkSidebar(tree)
    check tree.viewport.width == width

  test "the sidebar is never moved onto a tab":
    const name = "moe_sidebar_tab_guard"
    let (e, first, _) = twoFiles(name)
    defer:
      cleanup(name)
    let tree = e.openFileTree()
    let width = tree.viewport.width

    check e.moveWindowToTab(tree, first) == tabSwitchRefused
    # A switch that skipped `checkTabSwitch` does not list the buffer either.
    e.switchToBufferByIndex(e.bufferIndexById(first.id))

    check tree.bufferIds == @[tree.tabBufferId]
    e.checkUntouched(tree, width)

  test "a jump back to a buffer is refused there, not taken for a deleted one":
    const name = "moe_sidebar_tab_jump_back"
    let (e, first, _) = twoFiles(name)
    defer:
      cleanup(name)
    let tree = e.openFileTree()
    let width = tree.viewport.width

    # Regression: it said "Buffer no longer available".
    e.run(HandlerResult(kind: hrJumpToBuffer, jumpBufferId: first.id))

    check first.id notin tree.bufferIds
    e.checkRefused(tree, width)

  when not defined(moe.embedded):
    test ":terminal is refused before it touches a split viewer the sidebar serves":
      const name = "moe_sidebar_tab_terminal_viewer"
      let (e, _, _) = twoFiles(name)
      defer:
        cleanup(name)
      let (helpWin, _) = e.openHelp()
      let tree = e.openFileTree()
      require e.windowManager.windows[e.sidebarTarget()] == helpWin
      let width = tree.viewport.width
      let windowsBefore = e.windowManager.windows.len
      let buffersBefore = e.buffers.len

      # Regression: the viewer's window was closed before the terminal was
      # refused.
      e.run(HandlerResult(kind: hrEnterTerminal, enterTerminalCommand: "true"))

      check helpWin in e.windowManager.windows
      check helpWin.viewerEntry.isSome
      check e.windowManager.windows.len == windowsBefore
      check e.buffers.len == buffersBefore
      e.checkRefused(tree, width)
