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

import ../src/moepkg/editor
import ../src/moepkg/editor_window
import ../src/moepkg/editor_window_state
import ../src/moepkg/config
import ../src/moepkg/types
import ../src/moepkg/buffer
import ../src/moepkg/modes
import ../src/moepkg/help_viewer

# Helper to create a minimal Editor for testing
proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)

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
  test "switch to previous window in two-window setup":
    let e = createTestEditor()
    discard e.vsplit()
    check e.windowManager.windows.len == 2

    # Start at window 1
    e.windowManager.activeWindowIndex = 1
    e.switchToPrevWindow()

    check e.windowManager.activeWindowIndex == 0

  test "switch wraps around to last window":
    let e = createTestEditor()
    discard e.vsplit()
    discard e.vsplit()
    check e.windowManager.windows.len == 3

    # Start at window 0
    e.windowManager.activeWindowIndex = 0
    e.switchToPrevWindow()

    check e.windowManager.activeWindowIndex == 2

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
    e.executer.motionController.viewportManager.viewport.topLine = 10
    e.executer.motionController.viewportManager.viewport.leftColumn = 5

    e.saveActiveWindowState()

    check e.activeWindow.viewport.topLine == 10
    check e.activeWindow.viewport.leftColumn == 5

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
    e.activeWindow.buffer = newBuffer

    e.syncActiveWindow()

    check e.executer.buffer == newBuffer
    check e.executer.motionController.executor.buffer == newBuffer

  test "syncs viewport to motion controller":
    let e = createTestEditor()
    e.activeWindow.viewport.topLine = 15
    e.activeWindow.viewport.leftColumn = 8

    e.syncActiveWindow()

    check e.executer.motionController.viewportManager.viewport.topLine == 15
    check e.executer.motionController.viewportManager.viewport.leftColumn == 8

  test "sets needsFullRedraw":
    let e = createTestEditor()
    e.state.windowDisplay.needsFullRedraw = false

    e.syncActiveWindow()

    check e.state.windowDisplay.needsFullRedraw

suite "setActiveWindowScreenCursor":
  test "sets screen cursor for active window":
    let e = createTestEditor()
    e.state.display.showLineNumbers = false
    e.state.display.showSidebar = false
    e.state.display.showTabLine = false
    e.state.display.lineWrap = false
    # Set up buffer with enough content
    let buffer = newTextBuffer("Hello world test content")
    e.activeWindow.buffer = buffer
    e.activeWindow.cursor = BufferPosition(line: 0, column: 5)
    e.activeWindow.viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

    e.setActiveWindowScreenCursor(e.activeWindow)

    check e.state.screenCursor.x == 5 # No lineNumOffset, no sidebar
    check e.state.screenCursor.y == 0

  test "accounts for line numbers":
    let e = createTestEditor()
    e.state.display.showLineNumbers = true
    e.state.display.showSidebar = false
    e.state.display.showTabLine = false
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    e.activeWindow.buffer = buffer
    e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
    e.activeWindow.viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

    e.setActiveWindowScreenCursor(e.activeWindow)

    # Should have line number offset
    check e.state.screenCursor.x > 0

  test "accounts for tab line":
    let e = createTestEditor()
    e.state.display.showLineNumbers = false
    e.state.display.showSidebar = false
    e.state.display.showTabLine = true
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    e.activeWindow.buffer = buffer
    e.activeWindow.cursor = BufferPosition(line: 0, column: 0)
    e.activeWindow.viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)

    e.setActiveWindowScreenCursor(e.activeWindow)

    # Y should be offset by tab line height
    check e.state.screenCursor.y == 1 # TabLineHeight = 1

suite "vsplitWithBuffer - duplicate buffer handling":
  test "does not add duplicate buffer":
    let e = createTestEditor()
    let sharedBuffer = e.textBuffer
    let initialBufferCount = e.buffers.len

    # Split with the same buffer that's already in the list
    let result = e.vsplitWithBuffer(sharedBuffer)
    check result.isOk
    # Buffer count should not increase (buffer already exists)
    check e.buffers.len == initialBufferCount

suite "hsplitWithBuffer - duplicate buffer handling":
  test "does not add duplicate buffer":
    let e = createTestEditor()
    let sharedBuffer = e.textBuffer
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
    e.activeWindow.viewport.leftColumn = 50

    let result = e.enew()
    check result.isOk
    check e.activeWindow.viewport.topLine == 0
    check e.activeWindow.viewport.leftColumn == 0

  test "syncs with executor":
    let e = createTestEditor()
    let oldBuffer = e.executer.buffer

    let result = e.enew()
    check result.isOk
    # Executor should have the new buffer
    check e.executer.buffer != oldBuffer
    check e.executer.buffer == e.activeWindow.buffer

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
    check e.executer.buffer == e.activeWindow.buffer

suite "switchToNextWindow - state preservation":
  test "preserves cursor position when switching":
    let e = createTestEditor()
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
    e.executer.motionController.viewportManager.viewport.topLine = 20
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
    activeWin.helpViewerState = some(helpState)

    check activeWin.mode == EditorMode.Help
    check activeWin.helpViewerState.isSome

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
    activeWin.helpViewerState = some(helpState)

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
    activeWin.helpViewerState = some(helpState)

    # Close help viewer - should not close window since only 1 window
    activeWin.clearModeState(EditorMode.Help)
    activeWin.mode = EditorMode.Normal
    e.setMode(EditorMode.Normal)
    # windows.len == 1, so skip closing
    check e.windowManager.windows.len == 1
    check activeWin.helpViewerState.isNone
