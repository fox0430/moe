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

import std/[unittest, strutils]

import ../src/moepkg/editor
import ../src/moepkg/editor_window
import ../src/moepkg/config
import ../src/moepkg/types
import ../src/moepkg/buffer
import ../src/moepkg/modes

# Helper to create a minimal Editor for testing
proc createTestEditor(): Editor =
  let config = newEditorConfig()
  result = newEditor(config)

suite "calculateReservedLines":
  test "status line enabled, multi status line, bottom window":
    let e = createTestEditor()
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true
    let reserved = e.calculateReservedLines(isBottomWindow = true)
    # StatusAndCommandReserve = 2
    check reserved == 2

  test "status line enabled, multi status line, non-bottom window":
    let e = createTestEditor()
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = true
    let reserved = e.calculateReservedLines(isBottomWindow = false)
    # StatusLineReserve = 1
    check reserved == 1

  test "status line enabled, single status line, bottom window":
    let e = createTestEditor()
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = false
    let reserved = e.calculateReservedLines(isBottomWindow = true)
    # StatusAndCommandReserve = 2
    check reserved == 2

  test "status line enabled, single status line, non-bottom window":
    let e = createTestEditor()
    e.state.display.showStatusLine = true
    e.state.display.multiStatusLine = false
    let reserved = e.calculateReservedLines(isBottomWindow = false)
    # No status line for non-bottom window in single status line mode
    check reserved == 0

  test "status line disabled, bottom window":
    let e = createTestEditor()
    e.state.display.showStatusLine = false
    let reserved = e.calculateReservedLines(isBottomWindow = true)
    # CommandLineReserve = 1
    check reserved == 1

  test "status line disabled, non-bottom window":
    let e = createTestEditor()
    e.state.display.showStatusLine = false
    let reserved = e.calculateReservedLines(isBottomWindow = false)
    check reserved == 0

suite "calculateSidebarWidth":
  test "sidebar enabled":
    let e = createTestEditor()
    e.state.display.showSidebar = true
    let width = e.calculateSidebarWidth()
    # DefaultSidebarWidth = 2
    check width == 2

  test "sidebar disabled":
    let e = createTestEditor()
    e.state.display.showSidebar = false
    let width = e.calculateSidebarWidth()
    check width == 0

suite "calculateWindowCursor":
  test "cursor at buffer start, no wrap":
    let e = createTestEditor()
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 0)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 4 # lineNumOffset
    check pos.y == 0

  test "cursor in middle of line, no wrap":
    let e = createTestEditor()
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Hello world")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 5)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 9 # lineNumOffset + 5
    check pos.y == 0

  test "cursor on second line, no wrap":
    let e = createTestEditor()
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Line 1\nLine 2")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 1, column: 0)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 4 # lineNumOffset
    check pos.y == 1 # second line

  test "cursor above visible area returns (0, 0)":
    let e = createTestEditor()
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Line 1\nLine 2\nLine 3")
    let viewport =
      ViewPort(topLine: 2, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 0) # Above visible area

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 0
    check pos.y == 0

  test "cursor with horizontal scroll, no wrap":
    let e = createTestEditor()
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("0123456789ABCDEFGHIJ")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 5, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 10)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 9 # lineNumOffset + (10 - 5) = 4 + 5 = 9
    check pos.y == 0

  test "cursor out of buffer bounds returns (0, 0)":
    let e = createTestEditor()
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Hello")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 10, column: 0) # Beyond buffer

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 0
    check pos.y == 0

  test "cursor at buffer start, with wrap":
    let e = createTestEditor()
    e.state.display.lineWrap = true
    let buffer = newTextBuffer("Hello world")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 0, column: 0)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 4
    check pos.y == 0

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

  test "saves base mode for overlay modes":
    let e = createTestEditor()
    # Set base mode to Filer (state.mode holds the base mode)
    e.state.mode = EditorMode.Filer
    # Enter command overlay (hasOverlay becomes true)
    e.state.enterCommandOverlay()
    # Window mode was showing Normal before overlay activation
    e.activeWindow.mode = EditorMode.Normal

    e.saveActiveWindowState()

    # Should save the base mode (state.mode = Filer), not the window's previous mode
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
    e.state.needsFullRedraw = false

    e.syncActiveWindow()

    check e.state.needsFullRedraw

suite "calculateWindowCursor - wrap mode edge cases":
  test "wrap mode with empty line":
    let e = createTestEditor()
    e.state.display.lineWrap = true
    let buffer = newTextBuffer("Line 1\n\nLine 3") # Middle line is empty
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 2, column: 0)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 4
    check pos.y == 2 # Line 0, empty line 1, Line 2

  test "wrap mode with long line that wraps":
    let e = createTestEditor()
    e.state.display.lineWrap = true
    # Create a line that will wrap (wider than viewport)
    let longLine = "A".repeat(100)
    let buffer = newTextBuffer(longLine & "\nLine 2")
    # Viewport width 20, minus lineNumOffset 4 = 16 chars per wrapped line
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 20, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: 1, column: 0)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 4
    # Line 0 wraps to multiple screen lines, then Line 2
    check pos.y > 1

  test "cursor on wrapped portion of line":
    let e = createTestEditor()
    e.state.display.lineWrap = true
    let longLine = "ABCDEFGHIJ" & "KLMNOPQRST" # 20 chars
    let buffer = newTextBuffer(longLine)
    # Viewport width 14, minus lineNumOffset 4 = 10 chars per wrapped line
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 14, height: 24, x: 0, y: 0)
    # Cursor at column 15 (in the wrapped portion)
    let cursor = BufferPosition(line: 0, column: 15)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    # Should be on wrapped line (y=1) at column 5 (15 - 10 = 5)
    check pos.y == 1
    check pos.x == 4 + 5 # lineNumOffset + column within wrapped line

  test "negative line returns (0, 0)":
    let e = createTestEditor()
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Hello")
    let viewport =
      ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 24, x: 0, y: 0)
    let cursor = BufferPosition(line: -1, column: 0)

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 0
    check pos.y == 0

  test "cursor below visible area, no wrap":
    let e = createTestEditor()
    e.state.display.lineWrap = false
    let buffer = newTextBuffer("Line 1\nLine 2\nLine 3\nLine 4\nLine 5")
    # Small viewport height of 3, with reserved 2 = only 1 visible line
    let viewport = ViewPort(topLine: 0, leftColumn: 0, width: 80, height: 3, x: 0, y: 0)
    let cursor = BufferPosition(line: 4, column: 0) # Beyond visible area

    let pos = e.calculateWindowCursor(
      buffer, viewport, cursor, lineNumOffset = 4, reservedLines = 2
    )
    check pos.x == 0
    check pos.y == 0

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
