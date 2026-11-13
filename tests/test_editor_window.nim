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

import std/[unittest, options, os, sequtils, strutils, tables]

import pkg/results

import
  ../src/moepkg/[
    editor, window_manager, editor_window_state, path_key, config, types, buffer, modes,
    help_viewer, filer, backup_manager, diff_viewer, render_utils, completion,
    signature_help,
  ]
import ../src/moepkg/editor_window {.all.}
import ../src/moepkg/editor_render_views
import ../src/moepkg/handler
import ../src/moepkg/command_handlers/[handler_result, result_processor]
from ../src/moepkg/lsp_integration import applyTextEdits
from ../src/moepkg/lsp/protocol/types import TextEdit, newRange
from pkg/celina import newBuffer
import visual_test_helper
import vim_like_test_helper

# Helper to create a minimal Editor for testing
proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)
  result.syncActiveWindow()

suite "vsplit":
  test "vertical split creates two windows":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1

    let result = e.vsplit()
    check result.isOk
    check e.windowManager.windows.len == 2

  test "vertical split shares same buffer by default":
    let e = createTestEditor()
    # textBuffer is already initialized by newEditor

    let result = e.vsplit()
    check result.isOk
    check e.windowManager.windows.len == 2
    # Both windows should have the same buffer
    check e.windowManager.windows[0].buffer == e.windowManager.windows[1].buffer

  test "vsplit activates new window in Normal mode":
    let e = createTestEditor()
    e.setMode(EditorMode.Insert)

    let result = e.vsplit()
    check result.isOk
    # New window should be in Normal mode
    check e.activeWindow.mode == EditorMode.Normal

suite "vsplitWithBuffer":
  test "vertical split with new buffer":
    let e = createTestEditor()
    let newBuffer = newTextBuffer("New buffer content")

    let result = e.vsplitWithBuffer(newBuffer)
    check result.isOk
    check e.windowManager.windows.len == 2
    # Active window should have the new buffer
    check e.activeWindow.buffer == newBuffer

  test "buffer is added to buffer list":
    let e = createTestEditor()
    let initialBufferCount = e.buffers.len
    let newBuffer = newTextBuffer()

    let result = e.vsplitWithBuffer(newBuffer)
    check result.isOk
    check e.buffers.len == initialBufferCount + 1

suite "a split on a file that is already open":
  test "shows the buffer already holding it, not a second copy":
    let e = createTestEditor()
    let path = getTempDir() / "moe_test_split_reuse.txt"
    writeFile(path, "a\nb\nc")
    defer:
      removeFile(path)

    check e.vsplit(some(path)).isOk
    let opened = e.activeWindow.buffer
    let bufferCount = e.buffers.len

    check e.hsplit(some(path)).isOk
    # One buffer in three windows; a second copy could not both be written back.
    check e.buffers.len == bufferCount
    check e.activeWindow.buffer == opened
    check e.windowManager.windows.len == 3

  test "a split on a different file still opens its own buffer":
    let e = createTestEditor()
    let pathA = getTempDir() / "moe_test_split_reuse_a.txt"
    let pathB = getTempDir() / "moe_test_split_reuse_b.txt"
    writeFile(pathA, "a\n")
    writeFile(pathB, "b\n")
    defer:
      removeFile(pathA)
      removeFile(pathB)

    check e.vsplit(some(pathA)).isOk
    let bufferCount = e.buffers.len

    check e.vsplit(some(pathB)).isOk
    check e.buffers.len == bufferCount + 1
    check e.activeWindow.buffer.filePath == some(pathB)

suite "hsplit":
  test "horizontal split creates two windows":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1

    let result = e.hsplit()
    check result.isOk
    check e.windowManager.windows.len == 2

  test "horizontal split shares same buffer by default":
    let e = createTestEditor()
    # textBuffer is already initialized by newEditor

    let result = e.hsplit()
    check result.isOk
    check e.windowManager.windows.len == 2
    # Both windows should have the same buffer
    check e.windowManager.windows[0].buffer == e.windowManager.windows[1].buffer

  test "hsplit activates new window in Normal mode":
    let e = createTestEditor()
    e.setMode(EditorMode.Insert)

    let result = e.hsplit()
    check result.isOk
    # New window should be in Normal mode
    check e.activeWindow.mode == EditorMode.Normal

suite "hsplitWithBuffer":
  test "horizontal split with new buffer":
    let e = createTestEditor()
    let newBuffer = newTextBuffer("New buffer content")

    let result = e.hsplitWithBuffer(newBuffer)
    check result.isOk
    check e.windowManager.windows.len == 2
    # Active window should have the new buffer
    check e.activeWindow.buffer == newBuffer

  test "buffer is added to buffer list":
    let e = createTestEditor()
    let initialBufferCount = e.buffers.len
    let newBuffer = newTextBuffer()

    let result = e.hsplitWithBuffer(newBuffer)
    check result.isOk
    check e.buffers.len == initialBufferCount + 1

suite "enew":
  test "creates new empty buffer":
    let e = createTestEditor()
    let initialBufferCount = e.buffers.len

    let result = e.enew()
    check result.isOk
    check e.buffers.len == initialBufferCount + 1
    # Active window buffer should be empty (single empty line)
    check e.activeWindow.buffer.len == 1
    check e.activeWindow.buffer.getLine(0).len == 0

  test "resets cursor position":
    let e = createTestEditor()
    e.cursor = BufferPosition(line: 5, column: 10)

    let result = e.enew()
    check result.isOk
    check e.cursor.line == 0
    check e.cursor.column == 0

suite "new":
  test "creates horizontal split with empty buffer":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1

    let result = e.new()
    check result.isOk
    check e.windowManager.windows.len == 2
    # New buffer should be empty
    check e.activeWindow.buffer.len == 1
    check e.activeWindow.buffer.getLine(0).len == 0

suite "vnew":
  test "creates vertical split with empty buffer":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1

    let result = e.vnew()
    check result.isOk
    check e.windowManager.windows.len == 2
    # New buffer should be empty
    check e.activeWindow.buffer.len == 1
    check e.activeWindow.buffer.getLine(0).len == 0

suite "switchToNextWindow":
  test "switch to next window in two-window setup":
    let e = createTestEditor()
    discard e.vsplit()
    check e.windowManager.windows.len == 2

    let initialIndex = e.windowManager.activeWindowIndex
    e.switchToNextWindow()
    let newIndex = e.windowManager.activeWindowIndex

    check newIndex == (initialIndex + 1) mod 2

  test "switch wraps around to first window":
    let e = createTestEditor()
    discard e.vsplit()
    discard e.vsplit()
    check e.windowManager.windows.len == 3

    # Navigate to last window
    e.windowManager.activeWindowIndex = 2
    e.switchToNextWindow()

    check e.windowManager.activeWindowIndex == 0

  test "does nothing with single window":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1

    e.switchToNextWindow()
    check e.windowManager.activeWindowIndex == 0

suite "switchToPrevWindow":
  test "a split leaves the window it was made from as the previous one":
    let e = createTestEditor()
    discard e.vsplit()
    check e.windowManager.windows.len == 2
    check e.windowManager.activeWindowIndex == 0

    e.switchToPrevWindow()

    check e.windowManager.activeWindowIndex == 1

  test "switch toggles between the two last accessed windows":
    let e = createTestEditor()
    discard e.vsplit()
    discard e.vsplit()
    check e.windowManager.windows.len == 3

    e.windowManager.activateWindow(2)
    e.windowManager.activateWindow(0)

    e.switchToPrevWindow()
    check e.windowManager.activeWindowIndex == 2

    e.switchToPrevWindow()
    check e.windowManager.activeWindowIndex == 0

  test "does nothing with single window":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1

    e.switchToPrevWindow()
    check e.windowManager.activeWindowIndex == 0

suite "closeWindow":
  test "close window with multiple windows":
    let e = createTestEditor()
    discard e.vsplit()
    check e.windowManager.windows.len == 2

    let shouldQuit = e.closeWindow()
    check not shouldQuit
    check e.windowManager.windows.len == 1

  test "close last window returns quit flag":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1

    let shouldQuit = e.closeWindow()
    check shouldQuit
    # Window should still exist (last window is never deleted)
    check e.windowManager.windows.len == 1

  test "close adjusts active index":
    let e = createTestEditor()
    discard e.vsplit()
    discard e.vsplit()
    check e.windowManager.windows.len == 3

    # Close window at index 2
    e.windowManager.activeWindowIndex = 2
    let shouldQuit = e.closeWindow()

    check not shouldQuit
    check e.windowManager.windows.len == 2
    # Active index should be adjusted
    check e.windowManager.activeWindowIndex < 2

suite "saveActiveWindowState":
  test "saves viewport state":
    let e = createTestEditor()
    # Set viewport in motion controller
    e.motionController.viewportManager.viewport.topLine = 10
    e.motionController.viewportManager.viewport.leftCell = 5

    e.saveActiveWindowState()

    check e.activeWindow.viewport.topLine == 10
    check e.activeWindow.viewport.leftCell == 5

  test "preserves base mode during overlay":
    let e = createTestEditor()
    # Set mode to Filer (state.mode and activeWindow.mode are the same via forwarding)
    e.state.mode = EditorMode.Filer
    # Enter command overlay (hasOverlay becomes true, base mode stays Filer)
    e.state.enterCommandOverlay()

    e.saveActiveWindowState()

    # Base mode (Filer) should be preserved in the window
    check e.activeWindow.mode == EditorMode.Filer

suite "syncActiveWindow":
  test "syncs buffer to executor":
    let e = createTestEditor()
    let newBuffer = newTextBuffer("New content")
    e.activeWindow.setTab(newBuffer)

    e.syncActiveWindow()

    check e.motionController.buffer == newBuffer
    check e.motionController.executor.buffer == newBuffer

  test "syncs viewport to motion controller":
    let e = createTestEditor()
    e.activeWindow.viewport.topLine = 15
    e.activeWindow.viewport.leftCell = 8

    e.syncActiveWindow()

    check e.motionController.viewportManager.viewport.topLine == 15
    check e.motionController.viewportManager.viewport.leftCell == 8

  test "binds wrapCountCache to active window's cache":
    let e = createTestEditor()
    e.syncActiveWindow()
    check e.motionController.viewportManager.wrapCountCache ==
      e.activeWindow.wrapCountCache

  test "hsplit rebinds wrapCountCache to the new active window":
    let e = createTestEditor()
    let win0 = e.activeWindow
    let res = e.hsplit()
    check res.isOk
    let win1 = e.activeWindow
    check win1 != win0
    check e.motionController.viewportManager.wrapCountCache == win1.wrapCountCache

  test "closeWindow rebinds wrapCountCache after switching active window":
    # vsplit inserts the new window at activeWindowIndex, so after vsplit
    # the new window is at index 0 and the original is at index 1. After
    # switchToPrevWindow, index 1 (the original) is active; closing it
    # leaves the new window as the survivor at index 0.
    let e = createTestEditor()
    let res = e.vsplit()
    check res.isOk
    let survivor = e.windowManager.windows[0]
    e.switchToPrevWindow()
    let shouldQuit = e.closeWindow()
    check not shouldQuit
    check e.activeWindow == survivor
    check e.motionController.viewportManager.wrapCountCache == survivor.wrapCountCache

  test "vsplit rebinds wrapCountCache to the new active window":
    let e = createTestEditor()
    let win0 = e.activeWindow
    let res = e.vsplit()
    check res.isOk
    let win1 = e.activeWindow
    check win1 != win0
    check e.motionController.viewportManager.wrapCountCache == win1.wrapCountCache

  test "switchToNextWindow rebinds wrapCountCache":
    let e = createTestEditor()
    let res = e.vsplit()
    check res.isOk
    let winA = e.activeWindow
    e.switchToNextWindow()
    let winB = e.activeWindow
    check winA != winB
    check e.motionController.viewportManager.wrapCountCache == winB.wrapCountCache

  test "closeWindow rebinds wrapCountCache to the surviving window":
    let e = createTestEditor()
    let res = e.vsplit()
    check res.isOk
    let shouldQuit = e.closeWindow()
    check not shouldQuit
    check e.motionController.viewportManager.wrapCountCache ==
      e.activeWindow.wrapCountCache

  test "enew rebinds wrapCountCache (same window, new buffer)":
    # enew swaps the active window's buffer in-place — the cache ref stays,
    # but its content must invalidate via bufferId.
    let e = createTestEditor()
    let oldBuf = e.activeWindow.buffer
    discard getWrapCount(e.activeWindow.wrapCountCache, oldBuf, 0, 10, 4)
    e.activeWindow.wrapCountCache.counts[0] = 999 # poison
    let oldId = e.activeWindow.wrapCountCache.bufferId

    let res = e.enew()
    check res.isOk

    check e.motionController.viewportManager.wrapCountCache ==
      e.activeWindow.wrapCountCache

    let newBuf = e.activeWindow.buffer
    check newBuf.id != oldId
    let r = getWrapCount(e.activeWindow.wrapCountCache, newBuf, 0, 10, 4)
    check r != 999
    check e.activeWindow.wrapCountCache.bufferId == newBuf.id

suite "setActiveWindowScreenCursor":
  test "sets screen cursor for active window":
    let e = createTestEditor()
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.state.showTabLine = false
    e.state.lineWrap = false
    # Set up buffer with enough content
    let buffer = newTextBuffer("Hello world test content")
    e.activeWindow.setTab(buffer)
    e.activeWindow.cursor = BufferPosition(line: 0, column: 5)
    e.activeWindow.viewport =
      ViewPort(topLine: 0, leftCell: 0, width: 80, height: 24, x: 0, y: 0)

    e.setActiveWindowScreenCursor(e.activeWindow)

    check e.state.screenCursor.x == 5 # No lineNumOffset, no sidebar
    check e.state.screenCursor.y == 0

  test "accounts for line numbers":
    let e = createTestEditor()
    e.state.showLineNumbers = true
    e.state.showSidebar = false
    e.state.showTabLine = false
    e.state.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    e.activeWindow.setTab(buffer)
    e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
    e.activeWindow.viewport =
      ViewPort(topLine: 0, leftCell: 0, width: 80, height: 24, x: 0, y: 0)

    e.setActiveWindowScreenCursor(e.activeWindow)

    # Should have line number offset
    check e.state.screenCursor.x > 0

  test "accounts for tab line":
    let e = createTestEditor()
    e.state.showLineNumbers = false
    e.state.showSidebar = false
    e.state.showTabLine = true
    e.state.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    e.activeWindow.setTab(buffer)
    e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
    e.activeWindow.viewport =
      ViewPort(topLine: 0, leftCell: 0, width: 80, height: 24, x: 0, y: 0)

    e.setActiveWindowScreenCursor(e.activeWindow)

    # Y should be offset by tab line height
    check e.state.screenCursor.y == 1 # TabLineHeight = 1

suite "vsplitWithBuffer - duplicate buffer handling":
  test "does not add duplicate buffer":
    let e = createTestEditor()
    let sharedBuffer = e.activeBuffer
    let initialBufferCount = e.buffers.len

    # Split with the same buffer that's already in the list
    let result = e.vsplitWithBuffer(sharedBuffer)
    check result.isOk
    # Buffer count should not increase (buffer already exists)
    check e.buffers.len == initialBufferCount

suite "hsplitWithBuffer - duplicate buffer handling":
  test "does not add duplicate buffer":
    let e = createTestEditor()
    let sharedBuffer = e.activeBuffer
    let initialBufferCount = e.buffers.len

    # Split with the same buffer that's already in the list
    let result = e.hsplitWithBuffer(sharedBuffer)
    check result.isOk
    # Buffer count should not increase (buffer already exists)
    check e.buffers.len == initialBufferCount

suite "enew - additional cases":
  test "resets viewport position":
    let e = createTestEditor()
    e.activeWindow.viewport.topLine = 100
    e.activeWindow.viewport.leftCell = 50

    let result = e.enew()
    check result.isOk
    check e.activeWindow.viewport.topLine == 0
    check e.activeWindow.viewport.leftCell == 0

  test "syncs with executor":
    let e = createTestEditor()
    let oldBuffer = e.motionController.buffer

    let result = e.enew()
    check result.isOk
    # Executor should have the new buffer
    check e.motionController.buffer != oldBuffer
    check e.motionController.buffer == e.activeWindow.buffer

  test "leaves a viewer mode instead of stranding the window in it":
    # Regression: enew drops modeState, so a window left in Filer/References/...
    # would keep dispatching to a handler whose state is gone — every key,
    # including `:`, errors out with "Filer state not initialized".
    let e = createTestEditor()
    let listing = newTextBuffer("listing")
    e.activeWindow.setView(listing)
    e.activeWindow.modeState =
      ModeState(kind: mskFiler, filer: newFilerState(getTempDir()))
    e.setMode(EditorMode.Filer)

    let result = e.enew()
    check result.isOk
    check e.activeWindow.modeState.kind == mskNone
    check e.activeWindow.mode == EditorMode.Normal

  test "drops the backup manager's viewer entry from under a diff":
    # Regression: `clearModeState` only drops the entry belonging to the mode
    # it tears down, so the DiffViewer over the BackupManager left the
    # BackupManager's entry on a window that now holds an empty buffer. A
    # later `:backup` then focused this window and showed nothing, and the
    # next in-place viewer replayed the stale entry's undo.
    let e = createTestEditor()
    e.activeWindow.setView(newTextBuffer("diff"))
    e.activeWindow.viewerEntry = some(
      ViewerEntry(
        mode: EditorMode.BackupManager,
        placement: vpInPlace,
        returnMode: EditorMode.Normal,
      )
    )
    e.activeWindow.modeState = ModeState(
      kind: mskDiffViewer,
      diffViewer: newDiffViewerState(),
      diffReturn: newBackupManagerState(),
    )
    e.setMode(EditorMode.DiffViewer)

    let result = e.enew()
    check result.isOk
    check e.activeWindow.viewerEntry.isNone
    check e.activeWindow.modeState.kind == mskNone
    check e.activeWindow.mode == EditorMode.Normal

suite "closeWindow - sync after close":
  test "syncs to remaining window after close":
    let e = createTestEditor()
    let newBuffer = newTextBuffer("Window 2 content")
    discard e.vsplitWithBuffer(newBuffer)
    check e.windowManager.windows.len == 2

    # Close current window (window 1 with newBuffer)
    let shouldQuit = e.closeWindow()
    check not shouldQuit

    # Should be synced to remaining window
    check e.motionController.buffer == e.activeWindow.buffer

suite "switchToNextWindow - state preservation":
  test "preserves cursor position when switching":
    let e = createTestEditor()
    discard e.activeBuffer.insertText(
      BufferPosition(line: 0, column: 0), "0123456789ab\n".repeat(8)
    )
    discard e.vsplit()

    # Set cursor in first window
    e.activeWindow.cursor = BufferPosition(line: 5, column: 10)
    e.windowManager.activeWindowIndex = 0
    let savedCursor = e.activeWindow.cursor

    # Switch to next window and back
    e.switchToNextWindow()
    e.switchToPrevWindow()

    # Cursor should be preserved
    check e.activeWindow.cursor == savedCursor

suite "switchToPrevWindow - state preservation":
  test "preserves viewport when switching":
    let e = createTestEditor()
    discard e.vsplit()

    # Set viewport in first window
    e.windowManager.activeWindowIndex = 0
    e.motionController.viewportManager.viewport.topLine = 20
    e.saveActiveWindowState()
    let savedTopLine = e.activeWindow.viewport.topLine

    # Switch to next window and back
    e.switchToNextWindow()
    e.switchToPrevWindow()

    # Viewport should be preserved
    check e.activeWindow.viewport.topLine == savedTopLine

suite "Help viewer - split window open and close":
  test "Open help viewer creates a split window":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1
    let initialBufferCount = e.buffers.len

    let helpState = newHelpViewerState()
    let helpBuffer = helpState.createHelpTextBuffer()
    let splitResult = e.hsplitWithBuffer(helpBuffer)

    check splitResult.isOk
    check e.windowManager.windows.len == 2
    check e.buffers.len == initialBufferCount + 1
    check e.activeWindow.buffer == helpBuffer
    check helpBuffer.readOnly

  test "Open help viewer sets mode and state":
    let e = createTestEditor()
    let helpState = newHelpViewerState()
    let helpBuffer = helpState.createHelpTextBuffer()
    let splitResult = e.hsplitWithBuffer(helpBuffer)
    check splitResult.isOk

    e.setMode(EditorMode.Help)
    let activeWin = e.activeWindow
    activeWin.mode = EditorMode.Help
    activeWin.modeState = ModeState(kind: mskHelp, help: helpState)

    check activeWin.mode == EditorMode.Help
    check activeWin.modeState.kind == mskHelp

  test "Close help viewer removes split window and buffer":
    let e = createTestEditor()
    let origBuffer = e.activeWindow.buffer
    let initialBufferCount = e.buffers.len

    # Open help in split
    let helpState = newHelpViewerState()
    let helpBuffer = helpState.createHelpTextBuffer()
    let splitResult = e.hsplitWithBuffer(helpBuffer)
    check splitResult.isOk
    check e.windowManager.windows.len == 2

    # Set help mode on active window
    e.setMode(EditorMode.Help)
    let activeWin = e.activeWindow
    activeWin.mode = EditorMode.Help
    activeWin.modeState = ModeState(kind: mskHelp, help: helpState)

    # Close help viewer (same logic as hrHelpViewerQuit)
    activeWin.clearModeState(EditorMode.Help)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    let buf = activeWin.buffer
    let idx = e.buffers.find(buf)
    if idx >= 0:
      e.deleteBufferAt(idx)
    discard e.closeWindow()

    check e.windowManager.windows.len == 1
    check e.buffers.len == initialBufferCount
    check e.activeWindow.buffer == origBuffer

  test "Help viewer buffer contains help text":
    let helpState = newHelpViewerState()
    let helpBuffer = helpState.createHelpTextBuffer()

    check helpBuffer.len > 0
    check helpBuffer.readOnly

  test "Close help viewer with single window does not crash":
    let e = createTestEditor()
    check e.windowManager.windows.len == 1

    # Simulate help in single window (edge case - no split)
    let helpState = newHelpViewerState()
    let activeWin = e.activeWindow
    activeWin.mode = EditorMode.Help
    activeWin.modeState = ModeState(kind: mskHelp, help: helpState)

    # Close help viewer - should not close window since only 1 window
    activeWin.clearModeState(EditorMode.Help)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    # windows.len == 1, so skip closing
    check e.windowManager.windows.len == 1
    check activeWin.modeState.kind == mskNone

suite "registerSplitBuffer":
  const editorConfigContent = """
root = true

[*.py]
indent_style = space
indent_size = 4
"""

  test "adds a new buffer to the buffer list":
    let e = createTestEditor()
    let initialCount = e.buffers.len
    let newBuffer = newTextBuffer("split content")

    e.registerSplitBuffer(newBuffer, applyConfig = true, context = "test")

    check e.buffers.len == initialCount + 1
    check newBuffer in e.buffers

  test "does not add a buffer that is already tracked":
    let e = createTestEditor()
    let existing = e.activeBuffer
    let initialCount = e.buffers.len

    e.registerSplitBuffer(existing, applyConfig = true, context = "test")

    check e.buffers.len == initialCount

  test "sets reserved words from config on the new buffer":
    let e = createTestEditor()
    e.config.highlight.reservedWord = @["TODO", "FIXME"]
    let newBuffer = newTextBuffer()

    e.registerSplitBuffer(newBuffer, applyConfig = false, context = "test")

    check newBuffer.reservedWords == toReservedWords(@["TODO", "FIXME"])
    check newBuffer.highlightNeedsUpdate

  test "leaves an already-tracked buffer untouched (early return)":
    let e = createTestEditor()
    let existing = e.activeBuffer
    existing.setReservedWords(toReservedWords(@["KEEP"]))
    existing.highlightNeedsUpdate = false
    # Config differs from the words currently on the buffer; if the early
    # return were skipped, the buffer would be re-tagged with these instead.
    e.config.highlight.reservedWord = @["TODO"]

    e.registerSplitBuffer(existing, applyConfig = false, context = "test")

    check existing.reservedWords == toReservedWords(@["KEEP"])
    check not existing.highlightNeedsUpdate

  test "applyConfig = true applies EditorConfig to the new buffer":
    let testDir = getTempDir() / "moe_register_split_buffer_apply"
    let testFile = testDir / "main.py"
    createDir(testDir)
    defer:
      removeDir(testDir)
    writeFile(testDir / ".editorconfig", editorConfigContent)
    writeFile(testFile, "print('hi')\n")

    let e = createTestEditor()
    let newBuffer = newTextBuffer(filePath = some(testFile))

    e.registerSplitBuffer(newBuffer, applyConfig = true, context = "test")

    check newBuffer in e.buffers
    check newBuffer.editorConfig.isSome
    check newBuffer.editorConfig.get.expandTab == some(true)
    check newBuffer.editorConfig.get.shiftWidth == some(4)

  test "applyConfig = false skips EditorConfig on the new buffer":
    let testDir = getTempDir() / "moe_register_split_buffer_skip"
    let testFile = testDir / "main.py"
    createDir(testDir)
    defer:
      removeDir(testDir)
    writeFile(testDir / ".editorconfig", editorConfigContent)
    writeFile(testFile, "print('hi')\n")

    let e = createTestEditor()
    let newBuffer = newTextBuffer(filePath = some(testFile))

    e.registerSplitBuffer(newBuffer, applyConfig = false, context = "test")

    # Buffer is still registered, but EditorConfig is not applied.
    check newBuffer in e.buffers
    check newBuffer.editorConfig.isNone

  const conflictContent =
    "line before\n" & "<<<<<<< HEAD\n" & "ours\n" & "=======\n" & "theirs\n" &
    ">>>>>>> feature\n" & "line after\n"

  test "applyConfig = true scans conflict markers on the new buffer":
    # The split startup path must give freshly loaded files the same per-buffer
    # setup as no-split startup, so conflict navigation works immediately.
    let e = createTestEditor()
    e.state.showGitDiff = false
    let newBuffer =
      newTextBuffer(conflictContent, some(getTempDir() / "moe_split_conflict.txt"))

    e.registerSplitBuffer(newBuffer, applyConfig = true, context = "test")

    check newBuffer.conflictBlocks.len == 1

  test "applyConfig = true restores persisted bookmarks":
    let e = createTestEditor()
    e.state.showGitDiff = false
    e.config.persist.bookmarks = true
    let testFile = getTempDir() / "moe_split_bookmark.txt"
    e.persistedBookmarks.changes[pathKey(testFile)] = @[2]
    let newBuffer = newTextBuffer("a\nb\nc\n", some(testFile))

    e.registerSplitBuffer(newBuffer, applyConfig = true, context = "test")

    check newBuffer.bookmarks == @[2]

  test "applyConfig = false leaves conflict markers and bookmarks untouched":
    # WithBuffer splits show an existing/synthetic buffer that is already set up
    # elsewhere; the helper must not re-initialise it.
    let e = createTestEditor()
    e.config.persist.bookmarks = true
    let testFile = getTempDir() / "moe_split_noinit.txt"
    e.persistedBookmarks.changes[pathKey(testFile)] = @[1]
    let newBuffer = newTextBuffer(conflictContent, some(testFile))

    e.registerSplitBuffer(newBuffer, applyConfig = false, context = "test")

    check newBuffer.conflictBlocks.len == 0
    check newBuffer.bookmarks.len == 0

suite "applyStartUpScreenSize":
  ## First-render sizing: the startup window layout is built against the
  ## initial default screen size (80x20) before the real terminal size is
  ## known. applyStartUpScreenSize must rescale it without breaking the
  ## layout (startup multi-file splits previously overlapped because only
  ## the active window was resized to the real terminal size).
  const
    TermWidth = 180
    TermHeight = 45

  proc checkScreenSizeSynced(e: Editor) =
    check e.screenSize.width == TermWidth
    check e.screenSize.height == TermHeight
    check e.screenSize.prevWidth == TermWidth
    check e.screenSize.prevHeight == TermHeight

  test "single window fills the terminal":
    let e = createTestEditor()

    e.applyStartUpScreenSize(TermWidth, TermHeight)

    check e.windowManager.windows.len == 1
    let win = e.activeWindow
    check win.viewport.x == 0
    check win.viewport.y == 0
    check win.viewport.width == TermWidth
    check win.viewport.height == TermHeight - StatusLineReserve
    e.checkScreenSizeSynced()

  test "startup vsplit windows are rescaled without overlap":
    let e = createTestEditor()
    check e.vsplit().isOk

    e.applyStartUpScreenSize(TermWidth, TermHeight)

    check e.windowManager.windows.len == 2
    var wins = @[e.windowManager.windows[0], e.windowManager.windows[1]]
    if wins[0].viewport.x > wins[1].viewport.x:
      swap(wins[0], wins[1])
    let (left, right) = (wins[0], wins[1])

    # Tile the full width with no overlap
    check left.viewport.x == 0
    check right.viewport.x >= left.viewport.x + left.viewport.width
    check right.viewport.x + right.viewport.width == TermWidth

    # Roughly equal widths
    check abs(left.viewport.width - right.viewport.width) <= WindowSeparatorWidth + 1

    # Side-by-side windows span the full height above the command line
    for win in wins:
      check win.viewport.y == 0
      check win.viewport.height == TermHeight - StatusLineReserve

    e.checkScreenSizeSynced()

  test "startup hsplit windows are rescaled without overlap":
    let e = createTestEditor()
    check e.hsplit().isOk

    e.applyStartUpScreenSize(TermWidth, TermHeight)

    check e.windowManager.windows.len == 2
    var wins = @[e.windowManager.windows[0], e.windowManager.windows[1]]
    if wins[0].viewport.y > wins[1].viewport.y:
      swap(wins[0], wins[1])
    let (top, bottom) = (wins[0], wins[1])

    # Tile the full height with no overlap, reserving the command line row
    check top.viewport.y == 0
    check bottom.viewport.y >= top.viewport.y + top.viewport.height
    check bottom.viewport.y + bottom.viewport.height == TermHeight - StatusLineReserve

    # Stacked windows span the full width
    for win in wins:
      check win.viewport.x == 0
      check win.viewport.width == TermWidth

    e.checkScreenSizeSynced()

  test "three startup vsplits tile the full width":
    let e = createTestEditor()
    check e.vsplit().isOk
    check e.vsplit().isOk

    e.applyStartUpScreenSize(TermWidth, TermHeight)

    check e.windowManager.windows.len == 3
    var wins = e.windowManager.windows
    for i in 0 ..< wins.len - 1:
      for j in i + 1 ..< wins.len:
        if wins[i].viewport.x > wins[j].viewport.x:
          swap(wins[i], wins[j])

    check wins[0].viewport.x == 0
    for i in 1 ..< wins.len:
      # No horizontal overlap between neighbors
      check wins[i].viewport.x >= wins[i - 1].viewport.x + wins[i - 1].viewport.width
    check wins[^1].viewport.x + wins[^1].viewport.width == TermWidth

    for win in wins:
      check win.viewport.y == 0
      check win.viewport.height == TermHeight - StatusLineReserve

    e.checkScreenSizeSynced()

suite "moveWindowToTab - Visual":
  test "the window that moves leaves Visual":
    let e = createTestEditor()
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let other = newTextBuffer("other tab")
    e.addBuffer(other)
    e.state.selectVisual(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 3)
    )

    check e.moveWindowToTab(e.activeWindow, other) == tabMoved

    check e.state.mode == EditorMode.Normal
    check not e.state.visualSelection.active

  test "a window moved in the background leaves the active window's selection":
    let e = createTestEditor()
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let other = newTextBuffer("other tab")
    e.addBuffer(other)
    let background = e.activeWindow
    discard e.vsplit()
    require e.activeWindow != background
    e.state.selectVisual(
      BufferPosition(line: 0, column: 0), BufferPosition(line: 0, column: 4)
    )

    check e.moveWindowToTab(background, other) == tabMoved

    check e.state.visualSelection.active
    check e.state.visualSelection.current == BufferPosition(line: 0, column: 4)

suite "moveWindowToTab - Insert":
  test "the active window that moves closes completion and signature help":
    let e = createTestEditor()
    let other = newTextBuffer("other tab")
    e.addBuffer(other)
    let insertHandler = e.handlerManager.insertHandler
    e.state.mode = EditorMode.Insert
    insertHandler.completionManager.state = csActive
    insertHandler.completionManager.setLspRequestPending(7, e.activeBuffer.id)
    insertHandler.signatureHelpManager.state = shsActive

    check e.moveWindowToTab(e.activeWindow, other) == tabMoved

    check not insertHandler.completionManager.isActive
    check not insertHandler.completionManager.isPendingLsp
    check insertHandler.signatureHelpManager.state == shsIdle

suite "Visual and the focus":
  test "the window that loses the focus leaves Visual":
    let e = createTestEditor()
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let origin = e.activeWindow
    e.state.selectVisual(
      BufferPosition(line: 0, column: 1), BufferPosition(line: 0, column: 3)
    )

    discard e.vsplit()

    require e.activeWindow != origin
    check origin.mode == EditorMode.Normal
    check not origin.visualSelection.active
    check not e.state.visualSelection.active

  test "it returns to the mode Visual was entered from":
    let e = createTestEditor()
    let origin = e.activeWindow
    e.state.previousMode = EditorMode.LogViewer
    e.state.mode = EditorMode.Visual
    let next = newTextBuffer("next")
    e.addBuffer(next)
    discard e.vsplitWithBuffer(next)

    require e.activeWindow != origin
    check origin.mode == EditorMode.LogViewer

  test "going back to the window does not resume the selection":
    let e = createTestEditor()
    discard e.activeBuffer.insertText(BufferPosition(line: 0, column: 0), "hello")
    let origin = e.activeWindow
    e.state.selectVisual(
      BufferPosition(line: 0, column: 1), BufferPosition(line: 0, column: 3)
    )
    discard e.vsplit()

    for i, win in e.windowManager.windows:
      if win == origin:
        e.windowManager.activateWindow(i)
    e.syncActiveWindow()

    check e.activeWindow == origin
    check e.state.mode == EditorMode.Normal

suite "Editor window - hsplit without room":
  proc tinyEditor(): Editor =
    result = newEditor(newEditorConfig())
    result.state.showStatusLine = true
    result.state.multiStatusLine = true
    result.state.showTabLine = false
    result.viewport.height = 3

  test "a refused :split {file} registers no buffer":
    let
      e = tinyEditor()
      buffersBefore = e.buffers.len
      path = getTempDir() / "moe_hsplit_no_room.txt"
    writeFile(path, "text")
    defer:
      removeFile(path)

    let split = e.hsplit(some(path))

    check split.isErr
    check split.error == "E36: Not enough room"
    check e.buffers.len == buffersBefore
    check e.windowManager.windows.len == 1

  test "a refused :new leaves the windows alone":
    let e = tinyEditor()
    check e.hsplitWithBuffer(newTextBuffer()).isErr
    check e.windowManager.windows.len == 1

  test "startup files split before the real size is known":
    let e = tinyEditor()
    let path = getTempDir() / "moe_hsplit_startup.txt"
    writeFile(path, "text")
    defer:
      removeFile(path)

    check e.hsplit(some(path), checkRoom = false).isOk
    check e.windowManager.windows.len == 2

suite "moveWindowToTab - the line a window left":
  proc tabs(e: Editor): tuple[first, second: TextBuffer] =
    ## Two tabs of 100 lines, the first one active.
    let first = e.activeBuffer
    let second = newTextBuffer("other")
    e.addBuffer(second)
    for buffer in [first, second]:
      discard buffer.insertText(BufferPosition(line: 0, column: 0), "  x\n".repeat(99))
    (first, second)

  test "a window comes back to its line, in the first column":
    let e = createTestEditor()
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 60, column: 2)

    check e.moveWindowToTab(e.activeWindow, second) == tabMoved
    check e.cursor == BufferPosition(line: 0, column: 0)
    e.cursor = BufferPosition(line: 30, column: 2)
    check e.moveWindowToTab(e.activeWindow, first) == tabMoved
    check e.cursor == BufferPosition(line: 60, column: 0)
    check e.moveWindowToTab(e.activeWindow, second) == tabMoved
    check e.cursor == BufferPosition(line: 30, column: 0)

  test "each window keeps its own line":
    let e = createTestEditor()
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 60, column: 0)
    let left = e.activeWindow
    discard e.moveWindowToTab(left, second)
    discard e.vsplit()
    let right = e.activeWindow
    require right != left
    discard e.moveWindowToTab(right, first)
    e.cursor = BufferPosition(line: 70, column: 0)
    discard e.moveWindowToTab(right, second)
    discard e.moveWindowToTab(left, first)

    check left.cursor.line == 60
    discard e.moveWindowToTab(right, first)
    check right.cursor.line == 70

  test "a window new to a buffer takes the line last left there":
    let e = createTestEditor()
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 60, column: 0)
    discard e.moveWindowToTab(e.activeWindow, second)
    discard e.vsplit()

    discard e.moveWindowToTab(e.activeWindow, first)

    check e.cursor.line == 60

  test "a split onto a buffer left comes back centered":
    let e = createTestEditor()
    e.activeWindow.viewport.height = 24
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 60, column: 0)
    discard e.moveWindowToTab(e.activeWindow, second)

    check e.vsplitWithBuffer(first).isOk

    check e.cursor.line == 60
    check 60 - e.activeWindow.viewport.topLine in 8 .. 12

  test "a closed window leaves its line behind":
    let e = createTestEditor()
    let (_, second) = e.tabs()
    let left = e.activeWindow
    discard e.vsplit()
    discard e.moveWindowToTab(e.activeWindow, second)
    e.cursor = BufferPosition(line: 70, column: 0)
    check not e.closeWindow()

    require e.activeWindow == left
    discard e.moveWindowToTab(left, second)

    check e.cursor.line == 70
    for spot in e.state.tabLines:
      check spot.window.isNil or spot.window == left

  test "the line follows edits made while the window is away":
    let e = createTestEditor()
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 60, column: 0)
    discard e.moveWindowToTab(e.activeWindow, second)
    discard first.deleteRange(
      BufferPosition(line: 10, column: 0), BufferPosition(line: 19, column: 2)
    )

    discard e.moveWindowToTab(e.activeWindow, first)

    # Line 10 stays, emptied; nine lines go.
    check e.cursor.line == 51

  test "a line past the end lands on the last line":
    let e = createTestEditor()
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 99, column: 0)
    discard e.moveWindowToTab(e.activeWindow, second)
    discard first.deleteRange(
      BufferPosition(line: 50, column: 0), BufferPosition(line: 99, column: 0)
    )

    discard e.moveWindowToTab(e.activeWindow, first)

    check e.cursor.line == first.len - 1

  test "a deleted buffer leaves nothing behind":
    let e = createTestEditor()
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 60, column: 0)
    discard e.moveWindowToTab(e.activeWindow, second)

    check e.deleteBufferById(first.id).isOk

    check e.state.tabLines.allIt(it.bufferId != first.id)

  test "coming back centers the line before any frame":
    let e = createTestEditor()
    e.activeWindow.viewport.height = 24
    let frame = newBuffer(80, 24)
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 19, column: 0)
    discard e.moveWindowToTab(e.activeWindow, second)
    discard e.moveWindowToTab(e.activeWindow, first)

    let centered = e.activeWindow.viewport.topLine
    check 19 - centered in 8 .. 12

    # The frame keeps it, and the window then scrolls as usual.
    e.advanceLayoutForFrame(frame, false)
    check e.activeWindow.viewport.topLine == centered
    e.cursor = BufferPosition(line: centered + 1, column: 0)
    e.advanceLayoutForFrame(frame, false)
    check e.activeWindow.viewport.topLine == centered

  test "a view placed after coming back stays":
    let e = createTestEditor()
    e.activeWindow.viewport.height = 24
    let frame = newBuffer(80, 24)
    let (first, second) = e.tabs()
    e.cursor = BufferPosition(line: 60, column: 0)
    discard e.moveWindowToTab(e.activeWindow, second)
    discard e.moveWindowToTab(e.activeWindow, first)

    e.cursor = BufferPosition(line: 80, column: 0)
    e.activeWindow.viewport.resetViewportTop(75)
    e.advanceLayoutForFrame(frame, false)

    check e.activeWindow.viewport.topLine == 75

  test "deleting the buffer a window shows leaves nothing behind":
    let e = createTestEditor()
    let (first, _) = e.tabs()
    e.cursor = BufferPosition(line: 60, column: 0)

    check e.deleteBufferById(first.id).isOk

    check e.state.tabLines.allIt(it.bufferId != first.id)

  test "a closed window replaces the line an older one left":
    let e = createTestEditor()
    let (first, _) = e.tabs()
    for line in [60, 70, 80]:
      discard e.vsplit()
      e.cursor = BufferPosition(line: line, column: 0)
      discard e.closeWindow()

    let left = e.state.tabLines.filterIt(it.bufferId == first.id and it.window.isNil)
    check left.len == 1
    check left[0].line == 80

  test "a buffer never left starts at its top":
    let e = createTestEditor()
    let (_, second) = e.tabs()

    discard e.moveWindowToTab(e.activeWindow, second)

    check e.cursor == BufferPosition(line: 0, column: 0)
    check e.activeWindow.viewport.topLine == 0

suite "Other windows on the buffer follow its text":
  # Expected as Vim 9.2's getwininfo().topline and getcurpos() of a second
  # window on the buffer, with the same keys typed in the first.
  proc twoWindows(): tuple[e: Editor, other: EditorWindow] =
    var lines: seq[string]
    for i in 1 .. 40:
      lines.add "line" & align($i, 2, '0')
    let e = newVimLikeEditor(lines, 0, 0)
    check e.vsplit().isOk
    (e, e.windowManager.windows[1 - e.windowManager.activeWindowIndex])

  proc place(win: EditorWindow, top, line, column: int) =
    win.viewport.topLine = top
    win.cursor = BufferPosition(line: line, column: column)

  proc typeKeys(e: Editor, spec: string) =
    for key in keysOf(spec):
      check e.handleKeyCombo(key)

  proc shows(win: EditorWindow): (int, int, int) =
    (win.viewport.topLine, win.cursor.line, win.cursor.column)

  test "A line deleted under the cursor takes it to the start of the line above":
    let (e, other) = twoWindows()
    other.place(7, 9, 2)
    e.typeKeys("10Gdd")
    check other.shows == (7, 8, 0)
    # The window typed in places its own cursor.
    check e.cursor == BufferPosition(line: 9, column: 0)

  test "Lines deleted above take the cursor and the top line up":
    let (e, other) = twoWindows()
    other.place(7, 9, 2)
    e.typeKeys("3G2dd")
    check other.shows == (5, 7, 2)

  test "A deleted top line gives way to the line above":
    let (e, other) = twoWindows()
    other.place(7, 11, 2)
    e.typeKeys("7G3dd")
    check other.shows == (5, 8, 2)

  test "A line opened just above the top line comes into view":
    let (e, other) = twoWindows()
    other.place(7, 9, 2)
    e.typeKeys("7Gox<Esc>")
    check other.shows == (7, 10, 2)

  test "A line opened further up moves the top line down":
    let (e, other) = twoWindows()
    other.place(7, 9, 2)
    e.typeKeys("6Gox<Esc>")
    check other.shows == (8, 10, 2)

  test "A line split just above the top line leaves the top line":
    let (e, other) = twoWindows()
    other.place(9, 11, 1)
    e.typeKeys("9G0lli<Enter><Esc>")
    check other.shows == (9, 12, 1)

  test "A split of the cursor's own line leaves the cursor on it":
    let (e, other) = twoWindows()
    other.place(7, 9, 4)
    e.typeKeys("10G0lli<Enter><Esc>")
    check other.shows == (7, 9, 4)

  test "A split at column 0 leaves the cursor on the line split":
    let (e, other) = twoWindows()
    other.place(7, 9, 4)
    e.typeKeys("10G0i<Enter><Esc>")
    check other.shows == (7, 9, 4)

  test "A split at column 0 just above the top line leaves the top line":
    let (e, other) = twoWindows()
    other.place(9, 11, 1)
    e.typeKeys("9G0i<Enter><Esc>")
    check other.shows == (9, 12, 1)

  test "A charwise put at column 0 leaves the cursor on the line put into":
    let (e, other) = twoWindows()
    other.place(7, 9, 4)
    e.typeKeys("1G0lvjy10G0P")
    check other.shows == (7, 9, 4)

  test "A line opened above the cursor's line takes the cursor down":
    let (e, other) = twoWindows()
    other.place(7, 9, 4)
    e.typeKeys("10GOx<Esc>")
    check other.shows == (7, 10, 4)

  test "J takes the cursor along onto the joined line":
    let (e, other) = twoWindows()
    other.place(7, 10, 2)
    e.typeKeys("10GJ")
    check other.shows == (7, 9, 9)

  test "Backspace joining lines takes the cursor along":
    let (e, other) = twoWindows()
    other.place(7, 10, 5)
    e.typeKeys("11G0i<Backspace><Esc>")
    check other.shows == (7, 9, 11)

  test "A charwise delete over lines takes the cursor to where it began":
    let (e, other) = twoWindows()
    other.place(7, 10, 2)
    e.typeKeys("10G0llvjjd")
    check other.shows == (7, 9, 0)

  test "A charwise delete over lines keeps the cursor on the text it joins":
    # Vim 9.2 counts the deleted head twice and lands past the line (column 6).
    let (e, other) = twoWindows()
    other.place(7, 11, 4)
    e.typeKeys("10G0llvjjd")
    check other.shows == (7, 9, 3)

  test "Deleting every line leaves the cursor and the top line at the top":
    let (e, other) = twoWindows()
    other.place(30, 35, 2)
    e.typeKeys("ggdG")
    check other.shows == (0, 0, 0)

  test "Undoing a deletion moves the cursor back down":
    let (e, other) = twoWindows()
    e.typeKeys("10Gdd")
    other.place(7, 9, 2)
    e.typeKeys("u")
    check other.shows == (7, 10, 2)

  test "Undoing an opened line takes a cursor on it to the line above":
    let (e, other) = twoWindows()
    e.typeKeys("7Gox<Esc>")
    other.place(7, 7, 0)
    e.typeKeys("u")
    check other.shows == (6, 6, 0)

  test "Redoing a deletion moves the cursor as the deletion did":
    let (e, other) = twoWindows()
    e.typeKeys("10Gddu")
    other.place(7, 9, 2)
    e.typeKeys("<C-r>")
    check other.shows == (7, 8, 0)

  test "Undoing a join takes a cursor on the joined line to the line above":
    let (e, other) = twoWindows()
    e.typeKeys("10GJ")
    other.place(7, 9, 9)
    e.typeKeys("u")
    check other.shows == (7, 8, 0)

  test "Entering the window brings its cursor back onto a shortened line":
    let (e, other) = twoWindows()
    other.place(7, 9, 4)
    e.typeKeys("10GD")
    check other.shows == (7, 9, 4)
    e.focusWindow(1 - e.windowManager.activeWindowIndex)
    check e.cursor == BufferPosition(line: 9, column: 0)

  test "A viewer over the window puts it back where its text went":
    let (e, other) = twoWindows()
    let first = e.windowManager.activeWindowIndex
    e.focusWindow(1 - first)
    other.place(7, 9, 2)
    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer)
    check other.mode == EditorMode.Filer
    e.focusWindow(first)
    e.typeKeys("3G2dd")
    e.focusWindow(1 - first)
    discard e.processResult(HandlerResult(kind: hrFilerQuit), e.activeBuffer)
    check other.mode == EditorMode.Normal
    check other.shows == (5, 7, 2)

  test "A viewer in the current window puts it back where its text went":
    # Not the cursor of the command run, so an edit made meanwhile moves it.
    let (e, other) = twoWindows()
    let buf = e.activeBuffer
    e.focusWindow(1 - e.windowManager.activeWindowIndex)
    other.place(7, 9, 2)
    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer)
    check buf.deleteLine(2).isOk
    discard e.processResult(HandlerResult(kind: hrFilerQuit), e.activeBuffer)
    check other.shows == (6, 8, 2)

  test "Entering the window keeps the column it wants past a shortened line":
    let (e, _) = twoWindows()
    e.typeKeys("<C-w>w9G04lj<C-w>w")
    e.typeKeys("10GD<C-w>wj")
    check e.cursor == BufferPosition(line: 10, column: 4)

  test "The column a window left takes from its cursor stays past a shortened line":
    # Vim's update_curswant takes it after the window's last command.
    let (e, _) = twoWindows()
    e.typeKeys("<C-w>w10G04l<C-w>w")
    e.typeKeys("10GD<C-w>wj")
    check e.cursor == BufferPosition(line: 10, column: 4)

  test "A line deleted under the cursor keeps the column it wants":
    let (e, _) = twoWindows()
    e.typeKeys("<C-w>w10G04l<C-w>w")
    e.typeKeys("10Gdd<C-w>wj")
    check e.cursor == BufferPosition(line: 9, column: 4)

  test "Entering the window to resume Insert leaves its cursor at the line end":
    let (e, _) = twoWindows()
    e.typeKeys("<C-w>w10G04l<C-w>w")
    # Ctrl-o comes on another line, which Insert resuming leaves alone.
    e.typeKeys("10G$a<Backspace><Backspace><Down><C-o><C-w>wX<Esc>")
    check e.activeBuffer.getLine(9) == "lineX"

  test "A line opened just above the top line shows from its first row":
    let (e, other) = twoWindows()
    other.place(7, 9, 2)
    other.viewport.topWrapOffset = 2
    e.typeKeys("7Gox<Esc>")
    check other.viewport.topWrapOffset == 0

  test "A top line moved down keeps the row it shows from":
    let (e, other) = twoWindows()
    other.place(7, 9, 2)
    other.viewport.topWrapOffset = 2
    e.typeKeys("6Gox<Esc>")
    check other.viewport.topWrapOffset == 2

  test "Leaving a listing keeps no column for it":
    let (e, other) = twoWindows()
    let first = e.windowManager.activeWindowIndex
    e.focusWindow(1 - first)
    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer)
    check other.mode == EditorMode.Filer
    other.preferredColumn = -1
    e.focusWindow(first)
    check other.preferredColumn == -1

  # Expected as Neovim 0.12's vim.lsp.util.apply_text_edits, which moves the
  # other windows and the jumps as nvim_buf_set_text does. Neovim brings the
  # column onto a shortened line at once; here entering the window does.
  proc lspEdit(e: Editor, first, last: (int, int), text: string) =
    check e.activeBuffer.applyTextEdits(
      @[TextEdit(range: newRange(first[0], first[1], last[0], last[1]), newText: text)]
    ).isOk

  proc jumpsOn(e: Editor, lines: openArray[int]): seq[int] =
    for line in lines:
      e.typeKeys($(line + 1) & "G")
    e.typeKeys("gg")
    e.state.jumpList.list.mapIt(it.line)

  test "Whole lines an LSP edit puts at column 0 take the cursor and jumps down":
    let (e, other) = twoWindows()
    let jumps = e.jumpsOn([9])
    other.place(7, 9, 4)
    e.lspEdit((9, 0), (9, 0), "import x\n")
    check other.shows == (7, 10, 4)
    check e.state.jumpList.list.mapIt(it.line) == jumps.mapIt(it + ord(it >= 9))

  test "A line an LSP edit rewrites keeps the cursor and the jumps on it":
    let (e, other) = twoWindows()
    let jumps = e.jumpsOn([9, 10, 11])
    other.place(7, 9, 4)
    e.lspEdit((9, 0), (10, 0), "bar\n")
    check other.shows == (7, 9, 4)
    check e.state.jumpList.list.mapIt(it.line) == jumps
    e.focusWindow(1 - e.windowManager.activeWindowIndex)
    check e.cursor == BufferPosition(line: 9, column: 2)

  test "The line after a span an LSP edit rewrites moves with its text":
    let (e, other) = twoWindows()
    other.place(10, 10, 2)
    e.lspEdit((9, 0), (10, 0), "a\nb\nc\n")
    check other.shows == (12, 12, 2)

  test "A top line an LSP edit rewrites into more lines stays":
    let (e, other) = twoWindows()
    other.place(9, 14, 1)
    e.lspEdit((9, 0), (10, 0), "a\nb\nc\n")
    check other.shows == (9, 16, 1)

  test "Lines an LSP edit deletes take the cursor to the start of the span":
    for (line, column) in [(9, 5), (10, 2), (11, 2)]:
      let (e, other) = twoWindows()
      other.place(7, line, column)
      e.lspEdit((9, 0), (12, 0), "")
      check other.shows == (7, 9, 0)

  test "The line after lines an LSP edit deletes keeps its column":
    let (e, other) = twoWindows()
    other.place(7, 12, 2)
    e.lspEdit((9, 0), (12, 0), "")
    check other.shows == (7, 9, 2)

  test "A top line an LSP edit deletes gives way to the line above":
    for top in [9, 10, 11]:
      let (e, other) = twoWindows()
      other.place(top, 14, 1)
      e.lspEdit((9, 0), (12, 0), "")
      check other.shows == (8, 11, 1)
    let (e, other) = twoWindows()
    other.place(12, 14, 1)
    e.lspEdit((9, 0), (12, 0), "")
    check other.shows == (9, 11, 1)

  test "Jumps on lines an LSP edit deletes go to the start of the span":
    let (e, _) = twoWindows()
    let jumps = e.jumpsOn([9, 10, 11, 12, 13])
    e.lspEdit((9, 0), (12, 0), "")
    check e.state.jumpList.list.mapIt(it.line) ==
      jumps.mapIt(
        if it in 9 .. 11:
          9
        elif it >= 12:
          it - 3
        else:
          it
      )

  test "A cursor in a span an LSP edit replaces stays in the new text, after it moves with it":
    for (place, shown) in [
      ((9, 1), (9, 1)),
      ((9, 5), (9, 3)),
      ((10, 1), (9, 3)),
      ((11, 2), (9, 3)),
      ((11, 3), (9, 4)),
      ((11, 5), (9, 6)),
    ]:
      let (e, other) = twoWindows()
      other.place(7, place[0], place[1])
      e.lspEdit((9, 2), (11, 3), "XY")
      check other.shows == (7, shown[0], shown[1])

  test "A charwise delete from column 0 keeps the cursor on the line it starts on":
    # Unlike an LSP edit: Vim 9.2's op_delete truncates that line.
    let (e, other) = twoWindows()
    other.place(7, 9, 5)
    e.typeKeys("10G0vjj$d")
    check other.shows == (7, 9, 5)

  test "A top line in rows an LSP edit drops stays on the rows that replace them":
    # Neovim leaves it on 13 for its cursor to bring back, which a window
    # scrolled away from its cursor never does here.
    let (e, other) = twoWindows()
    other.place(13, 20, 1)
    e.lspEdit((9, 0), (14, 0), "a\nb\n")
    check other.shows == (11, 17, 1)

  test "A top line stays in the text an LSP edit rewrites into fewer lines":
    let (e, other) = twoWindows()
    other.place(30, 35, 2)
    e.lspEdit((0, 0), (39, 6), "x\n".repeat(19) & "x")
    check e.activeBuffer.len == 20
    check other.shows == (19, 19, 0)

  test "LSP edits rolled back move no window and no jump":
    let (e, other) = twoWindows()
    let jumps = e.jumpsOn([21, 22])
    other.place(19, 21, 5)
    # Applied back to front: the line 6 edit ends past its line, after the
    # deletion is in.
    check e.activeBuffer.applyTextEdits(
      @[
        TextEdit(range: newRange(20, 0, 23, 0), newText: ""),
        TextEdit(range: newRange(5, 0, 5, 99), newText: "x"),
      ]
    ).isErr
    check e.activeBuffer.getLine(21) == "line22"
    check other.shows == (19, 21, 5)
    check e.state.jumpList.list.mapIt(it.line) == jumps
    # Nor do failed edits keep later ones from moving it.
    check e.activeBuffer.replaceSpan(
      BufferPosition(line: -1, column: 0), BufferPosition(line: 0, column: 0), "x"
    ).isErr
    e.typeKeys("3G2dd")
    check other.shows == (17, 19, 5)

  test "LSP edits rolled back by the transaction they joined move no window and no jump":
    # As a workspace edit applies them: the buffer's own transaction rolls
    # back what they put in, after they have moved the windows and jumps.
    let (e, other) = twoWindows()
    let jumps = e.jumpsOn([21, 22])
    other.place(19, 21, 5)
    let buffer = e.activeBuffer
    var failed = false
    try:
      let rolledBack = withTransaction(buffer, "workspace edit"):
        var applied: seq[TextEdit]
        let r = buffer.applyTextEdits(
          @[
            TextEdit(range: newRange(20, 0, 23, 0), newText: ""),
            TextEdit(range: newRange(5, 0, 5, 99), newText: "x"),
          ],
          applied,
          discloseJoined = false,
        )
        if r.isErr:
          raise newException(ValueError, r.error)
      discard rolledBack
    except ValueError:
      failed = true
    check failed
    check buffer.getLine(21) == "line22"
    check other.shows == (19, 21, 5)
    check e.state.jumpList.list.mapIt(it.line) == jumps

  test "A rolled back command moves no window back off its line":
    # Undo would leave a cursor deleted with its line on the line above.
    let (e, other) = twoWindows()
    other.place(7, 9, 2)
    let buffer = e.activeBuffer
    check buffer.beginTransaction("delete").isOk
    for i in countdown(10, 8):
      check buffer.deleteLine(i).isOk
    check other.shows == (7, 7, 0)
    check buffer.rollbackTransaction().isOk
    check other.shows == (7, 9, 2)

  test "An LSP edit moves the last Visual area as the jumps":
    # Neovim's nvim_buf_set_text moves '< and '> as it moves the jumps, by
    # rows across the span replaced as a whole.
    let (e, _) = twoWindows()
    let jumps = e.jumpsOn([14, 15])
    e.activeBuffer.lastVisual = some(
      VisualArea(
        start: BufferPosition(line: 14, column: 5),
        cursor: BufferPosition(line: 15, column: 1),
        kind: vskChar,
      )
    )
    e.lspEdit((10, 3), (14, 2), "X\nY")
    let area = e.activeBuffer.lastVisual.get
    check (area.start, area.cursor) ==
      (BufferPosition(line: 11, column: 5), BufferPosition(line: 12, column: 1))
    check e.state.jumpList.list.mapIt(it.line) ==
      jumps.mapIt(
        if it >= 14:
          it - 3
        else:
          it
      )

  test "A viewer over the window puts it back above its deleted line":
    let (e, other) = twoWindows()
    let first = e.windowManager.activeWindowIndex
    e.focusWindow(1 - first)
    other.place(7, 9, 2)
    discard e.processResult(HandlerResult(kind: hrEnterFiler), e.activeBuffer)
    e.focusWindow(first)
    e.typeKeys("10Gdd")
    e.focusWindow(1 - first)
    discard e.processResult(HandlerResult(kind: hrFilerQuit), e.activeBuffer)
    check other.shows == (7, 8, 0)
